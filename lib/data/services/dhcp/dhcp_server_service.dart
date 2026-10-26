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
  String _serverIp = '0.0.0.0';
  int _logSequence = 0;

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
  String get serverIp => _serverIp;

  void updateConfig(DhcpConfig config) {
    _leaseManager.updateConfig(config);
  }

  Future<void> start({
    int port = 67,
    InternetAddress? bindAddress,
    String? serverIp,
  }) async {
    if (_status.isRunning) return;

    final targetAddress = bindAddress ?? InternetAddress.anyIPv4;
    _serverIp = serverIp ?? (targetAddress != InternetAddress.anyIPv4 ? targetAddress.address : config.gatewayIp);

    try {
      _socket = await RawDatagramSocket.bind(
        targetAddress,
        port,
        reuseAddress: true,
        reusePort: false, // Windows unsupported, and Linux security risk
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
        summary: 'DHCP Server listening on ${targetAddress.address}:$port (Server IP: $_serverIp, Range: ${config.startIp} - ${config.endIp})',
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
      if (packet == null || packet.op != 1) return;

      switch (packet.messageType) {
        case DhcpMessageType.discover:
          _handleDiscover(packet);
          break;
        case DhcpMessageType.request:
          _handleRequest(packet);
          break;
        case DhcpMessageType.decline:
          _handleDecline(packet);
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
    // Reserve tentatively without committing a 24-hr lease (prevents starvation)
    final offeredIp = _leaseManager.reserveOrGetOffer(
      packet.chaddrMac,
      requestedIp: packet.requestedIp,
      hostname: packet.hostname,
    );

    if (offeredIp == null) {
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
          'Offered IP: $offeredIp',
    );

    // Send DHCPOFFER
    final replyBytes = DhcpPacketParser.buildReply(
      request: packet,
      replyType: DhcpMessageType.offer,
      offeredIp: offeredIp,
      serverIp: _serverIp,
      subnetMask: config.subnetMask,
      routerIp: config.gatewayIp,
      dnsServerIp: config.useLocalDns ? _serverIp : config.dnsServerIp,
      leaseTimeSeconds: config.leaseTimeSeconds,
    );

    _sendReply(replyBytes);

    _emitLog(
      action: 'OFFER',
      summary: 'DHCPOFFER $offeredIp sent to ${packet.chaddrMac}',
      clientAddress: packet.chaddrMac,
      severity: LogSeverity.success,
    );
  }

  void _handleRequest(DhcpPacket packet) {
    // If client specified a Server Identifier (Option 54) and it's NOT us, ignore packet
    if (packet.serverIdentifier != null &&
        packet.serverIdentifier != '0.0.0.0' &&
        packet.serverIdentifier != _serverIp) {
      _emitLog(
        action: 'REQUEST_IGNORED',
        summary: 'DHCPREQUEST from ${packet.chaddrMac} for other server ${packet.serverIdentifier} ignored',
        clientAddress: packet.chaddrMac,
        severity: LogSeverity.info,
      );
      return;
    }

    final targetIp = packet.requestedIp ?? (packet.ciaddr != '0.0.0.0' ? packet.ciaddr : null);

    final lease = _leaseManager.confirmLease(
      packet.chaddrMac,
      requestedIp: targetIp,
      hostname: packet.hostname,
    );

    if (lease == null) {
      // Send DHCPNAK per RFC 2131
      final nakBytes = DhcpPacketParser.buildReply(
        request: packet,
        replyType: DhcpMessageType.nak,
        offeredIp: '0.0.0.0',
        serverIp: _serverIp,
        subnetMask: config.subnetMask,
        routerIp: config.gatewayIp,
        dnsServerIp: config.useLocalDns ? _serverIp : config.dnsServerIp,
        leaseTimeSeconds: 0,
        errorMessage: 'Requested address unavailable or invalid',
      );

      _sendReply(nakBytes);

      _emitLog(
        action: 'NAK',
        summary: 'DHCPNAK sent to ${packet.chaddrMac} (requested: ${targetIp ?? "Unknown"})',
        clientAddress: packet.chaddrMac,
        severity: LogSeverity.warning,
      );
      return;
    }

    // Send DHCPACK
    final replyBytes = DhcpPacketParser.buildReply(
      request: packet,
      replyType: DhcpMessageType.ack,
      offeredIp: lease.ipAddress,
      serverIp: _serverIp,
      subnetMask: config.subnetMask,
      routerIp: config.gatewayIp,
      dnsServerIp: config.useLocalDns ? _serverIp : config.dnsServerIp,
      leaseTimeSeconds: config.leaseTimeSeconds,
    );

    // If client already has a valid IP (renewal), we can unicast; otherwise broadcast
    final unicastTarget = (packet.ciaddr != '0.0.0.0') ? packet.ciaddr : null;
    _sendReply(replyBytes, targetIp: unicastTarget);

    _leasesController.add(_leaseManager.activeLeases);

    _emitLog(
      action: 'ACK',
      summary: 'DHCPACK: Leased ${lease.ipAddress} to ${packet.chaddrMac} (${lease.hostname})',
      clientAddress: packet.chaddrMac,
      severity: LogSeverity.success,
      details: 'Assigned IP: ${lease.ipAddress}\n'
          'MAC: ${lease.macAddress}\n'
          'Hostname: ${lease.hostname}\n'
          'Server IP: $_serverIp\n'
          'Lease Expiry: ${lease.leaseExpiry.toIso8601String()}',
    );
  }

  void _handleDecline(DhcpPacket packet) {
    final declinedIp = packet.requestedIp ?? (packet.ciaddr != '0.0.0.0' ? packet.ciaddr : null);
    if (declinedIp != null) {
      _leaseManager.declineIp(declinedIp);
      _leasesController.add(_leaseManager.activeLeases);

      _emitLog(
        action: 'DECLINE',
        summary: 'DHCPDECLINE received from ${packet.chaddrMac} for $declinedIp (quarantined)',
        clientAddress: packet.chaddrMac,
        severity: LogSeverity.warning,
      );
    }
  }

  void _handleRelease(DhcpPacket packet) {
    final clientIp = packet.ciaddr != '0.0.0.0' ? packet.ciaddr : null;
    _leaseManager.releaseLease(packet.chaddrMac, expectedIp: clientIp);
    _leasesController.add(_leaseManager.activeLeases);

    _emitLog(
      action: 'RELEASE',
      summary: 'DHCPRELEASE received from ${packet.chaddrMac} (IP: ${clientIp ?? "Unknown"})',
      clientAddress: packet.chaddrMac,
      severity: LogSeverity.info,
    );
  }

  void _sendReply(List<int> bytes, {String? targetIp}) {
    try {
      if (targetIp != null && targetIp != '0.0.0.0') {
        _socket?.send(bytes, InternetAddress(targetIp), 68);
        return;
      }
    } catch (_) {}

    // Send to broadcast 255.255.255.255 on port 68
    try {
      _socket?.send(bytes, InternetAddress('255.255.255.255'), 68);
    } catch (_) {
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
    final logId = '${DateTime.now().millisecondsSinceEpoch}_${++_logSequence}';
    _logController.add(
      ServiceLogRecord(
        id: logId,
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
