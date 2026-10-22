import 'dart:async';
import 'dart:io';
import '../../../domain/models/dhcp_config.dart';
import '../../../domain/models/dhcp_lease.dart';
import '../../../domain/models/service_log_record.dart';
import '../../../domain/models/service_status.dart';
import 'dhcp_lease_manager.dart';
import 'dhcp_packet_parser.dart';

class DhcpServerService {
  RawDatagramSocket? _socket;
  ServiceStatus _status = const ServiceStatus(port: 67);
  late DhcpLeaseManager _leaseManager;

  final _logController = StreamController<ServiceLogRecord>.broadcast();
  final _statusController = StreamController<ServiceStatus>.broadcast();
  final _leasesController = StreamController<List<DhcpLease>>.broadcast();

  DhcpServerService({required DhcpConfig initialConfig}) {
    _leaseManager = DhcpLeaseManager(config: initialConfig);
  }

  Stream<ServiceLogRecord> get logStream => _logController.stream;
  Stream<ServiceStatus> get statusStream => _statusController.stream;
  Stream<List<DhcpLease>> get leasesStream => _leasesController.stream;
  ServiceStatus get status => _status;
  List<DhcpLease> get activeLeases => _leaseManager.activeLeases;
  DhcpConfig get config => _leaseManager.config;

  void updateConfig(DhcpConfig config) {
    _leaseManager.updateConfig(config);
  }

  Future<void> start({int port = 67, InternetAddress? bindAddress}) async {
    if (_status.isRunning) return;

    final targetAddress = bindAddress ?? InternetAddress.anyIPv4;

    try {
      _socket = await RawDatagramSocket.bind(
        targetAddress,
        port,
        reuseAddress: true,
        reusePort: true,
      );

      _socket!.broadcastEnabled = true;

      _status = ServiceStatus(
        state: ServiceState.running,
        port: port,
        startedAt: DateTime.now(),
      );
      _statusController.add(_status);

      _emitLog(
        action: 'START',
        summary: 'DHCP Server listening on ${targetAddress.address}:$port (Range: ${config.startIp} - ${config.endIp})',
        severity: LogSeverity.success,
      );

      _socket!.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket?.receive();
            if (datagram != null) {
              _handlePacket(datagram);
            }
          }
        },
        onError: (err) {
          _status = _status.copyWith(
            state: ServiceState.error,
            lastError: err.toString(),
          );
          _statusController.add(_status);
          _emitLog(
            action: 'ERROR',
            summary: 'DHCP Socket error: $err',
            severity: LogSeverity.error,
          );
        },
      );
    } catch (e) {
      _status = ServiceStatus(
        state: ServiceState.error,
        port: port,
        lastError: e.toString(),
      );
      _statusController.add(_status);
      _emitLog(
        action: 'ERROR',
        summary: 'Failed to bind DHCP port $port: $e',
        severity: LogSeverity.error,
        details: 'Binding port 67 requires elevated root/administrator privileges on Linux/macOS. '
            'Run the application with sudo or try an unprivileged test port like 6767.',
      );
    }
  }

  void _handlePacket(Datagram datagram) {
    try {
      final packet = DhcpPacketParser.parse(datagram.data);
      if (packet == null) return;

      switch (packet.messageType) {
        case DhcpMessageType.discover:
          _handleDiscover(packet);
          break;
        case DhcpMessageType.request:
          _handleRequest(packet);
          break;
        case DhcpMessageType.release:
          _handleRelease(packet);
          break;
        default:
          break;
      }
    } catch (e) {
      _emitLog(
        action: 'PARSE_ERROR',
        summary: 'Malformed DHCP packet: $e',
        severity: LogSeverity.warning,
      );
    }
  }

  void _handleDiscover(DhcpPacket packet) {
    final lease = _leaseManager.allocateOrGetLease(
      packet.chaddrMac,
      requestedIp: packet.requestedIp,
      hostname: packet.hostname,
    );

    if (lease == null) {
      _emitLog(
        action: 'DISCOVER_FAILED',
        summary: 'DHCPDISCOVER from ${packet.chaddrMac} ignored: IP Pool Exhausted!',
        severity: LogSeverity.error,
      );
      return;
    }

    _emitLog(
      action: 'DISCOVER',
      summary: 'DHCPDISCOVER from ${packet.chaddrMac} (${packet.hostname ?? "Unknown"})',
      clientAddress: packet.chaddrMac,
      severity: LogSeverity.info,
      details: 'Transaction ID: 0x${packet.xid.toRadixString(16).padLeft(8, '0')}\n'
          'Client MAC: ${packet.chaddrMac}\n'
          'Requested IP: ${packet.requestedIp ?? "None"}\n'
          'Offered IP: ${lease.ipAddress}',
    );

    // Send DHCPOFFER
    final replyBytes = DhcpPacketParser.buildReply(
      request: packet,
      replyType: DhcpMessageType.offer,
      offeredIp: lease.ipAddress,
      serverIp: config.gatewayIp,
      subnetMask: config.subnetMask,
      routerIp: config.gatewayIp,
      dnsServerIp: config.dnsServerIp,
      leaseTimeSeconds: config.leaseTimeSeconds,
    );

    _sendReply(replyBytes);

    _emitLog(
      action: 'OFFER',
      summary: 'DHCPOFFER ${lease.ipAddress} sent to ${packet.chaddrMac}',
      clientAddress: packet.chaddrMac,
      severity: LogSeverity.success,
    );
  }

  void _handleRequest(DhcpPacket packet) {
    final lease = _leaseManager.allocateOrGetLease(
      packet.chaddrMac,
      requestedIp: packet.requestedIp ?? packet.ciaddr,
      hostname: packet.hostname,
    );

    if (lease == null) {
      _emitLog(
        action: 'REQUEST_NAK',
        summary: 'DHCPREQUEST from ${packet.chaddrMac} could not be satisfied',
        severity: LogSeverity.warning,
      );
      return;
    }

    // Send DHCPACK
    final replyBytes = DhcpPacketParser.buildReply(
      request: packet,
      replyType: DhcpMessageType.ack,
      offeredIp: lease.ipAddress,
      serverIp: config.gatewayIp,
      subnetMask: config.subnetMask,
      routerIp: config.gatewayIp,
      dnsServerIp: config.dnsServerIp,
      leaseTimeSeconds: config.leaseTimeSeconds,
    );

    _sendReply(replyBytes);

    _leasesController.add(_leaseManager.activeLeases);

    _emitLog(
      action: 'ACK',
      summary: 'DHCPACK: Leased ${lease.ipAddress} to ${packet.chaddrMac} (${lease.hostname})',
      clientAddress: packet.chaddrMac,
      severity: LogSeverity.success,
      details: 'Assigned IP: ${lease.ipAddress}\n'
          'MAC: ${lease.macAddress}\n'
          'Hostname: ${lease.hostname}\n'
          'Lease Expiry: ${lease.leaseExpiry.toIso8601String()}',
    );
  }

  void _handleRelease(DhcpPacket packet) {
    _leaseManager.releaseLease(packet.chaddrMac);
    _leasesController.add(_leaseManager.activeLeases);

    _emitLog(
      action: 'RELEASE',
      summary: 'DHCPRELEASE received from ${packet.chaddrMac}',
      clientAddress: packet.chaddrMac,
      severity: LogSeverity.info,
    );
  }

  void _sendReply(List<int> bytes) {
    // Send to broadcast 255.255.255.255 on port 68 (DHCP client port)
    try {
      _socket?.send(bytes, InternetAddress('255.255.255.255'), 68);
    } catch (_) {
      // If broadcast fails, send to loopback or fallback
      try {
        _socket?.send(bytes, InternetAddress('127.0.0.1'), 68);
      } catch (_) {}
    }
  }

  void clearLeases() {
    _leaseManager.clearAll();
    _leasesController.add([]);
    _emitLog(
      action: 'CLEAR',
      summary: 'All DHCP active leases cleared',
      severity: LogSeverity.info,
    );
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    _status = _status.copyWith(state: ServiceState.stopped);
    _statusController.add(_status);

    _emitLog(
      action: 'STOP',
      summary: 'DHCP Server stopped',
      severity: LogSeverity.info,
    );
  }

  void _emitLog({
    required String action,
    required String summary,
    LogSeverity severity = LogSeverity.info,
    String? clientAddress,
    String? details,
  }) {
    if (_logController.isClosed) return;
    _logController.add(
      ServiceLogRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        serviceType: ServiceType.dhcp,
        action: action,
        summary: summary,
        severity: severity,
        clientAddress: clientAddress,
        details: details,
      ),
    );
  }

  void dispose() {
    _socket?.close();
    _socket = null;
    _status = _status.copyWith(state: ServiceState.stopped);
    _logController.close();
    _statusController.close();
    _leasesController.close();
  }
}
