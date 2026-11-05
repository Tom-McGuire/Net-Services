import 'dart:async';
import 'dart:io';
import '../../../domain/models/dhcp_config.dart';
import '../../../domain/models/dhcp_lease.dart';
import '../../../domain/models/service_log_record.dart';
import '../../../domain/models/service_status.dart';
import '../device/mac_address_helper.dart';
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
    _leasesController.add(_leaseManager.activeLeases);
  }

  void restoreLeases(List<DhcpLease> leases) {
    _leaseManager.restoreLeases(leases);
    _leasesController.add(_leaseManager.activeLeases);
  }

  String get _subnetBroadcastIp {
    final startNum = DhcpConfig.ipToNum(config.startIp);
    final maskNum = DhcpConfig.ipToNum(config.subnetMask);
    if (startNum == 0 || maskNum == 0) return '255.255.255.255';
    final broadcastNum = (startNum & maskNum) | (~maskNum & 0xFFFFFFFF);
    return DhcpConfig.numToIp(broadcastNum);
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
      if (packet == null) return;

      if (packet.op == 2) {
        final senderIp = datagram.address.address;
        if (senderIp != _serverIp && senderIp != '127.0.0.1' && packet.serverIdentifier != _serverIp) {
          _emitLog(
            action: 'ROGUE_DHCP',
            summary: 'Detected DHCP reply (${packet.messageType.name.toUpperCase()}) from another server at $senderIp',
            clientAddress: senderIp,
            severity: LogSeverity.warning,
            details: 'Sender IP: $senderIp\n'
                'Server Identifier (Option 54): ${packet.serverIdentifier ?? "None"}\n'
                'Offered IP (yiaddr): ${packet.yiaddr}\n'
                'Target Client MAC: ${packet.chaddrMac}',
          );
        }
        return;
      }

      if (packet.op != 1) return;

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
        case DhcpMessageType.inform:
          _handleInform(packet);
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
    // Inspect client MAC address in SharedDeviceDatabase
    final knownDevice = SharedDeviceHelper.getDevice(packet.chaddrMac);
    final friendlyName = knownDevice?.name ?? packet.hostname;

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
      summary: 'DHCPDISCOVER from ${packet.chaddrMac} (${friendlyName ?? "Unknown"})',
      clientAddress: packet.chaddrMac,
      severity: LogSeverity.info,
      details: 'Transaction ID: 0x${packet.xid.toRadixString(16).padLeft(8, '0')}\n'
          'Client MAC: ${packet.chaddrMac}\n'
          'Device Name: ${friendlyName ?? "None"}\n'
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
      broadcastIp: _subnetBroadcastIp,
      ntpServerIp: _serverIp != '0.0.0.0' ? _serverIp : null,
    );

    _sendReply(replyBytes);

    _emitLog(
      action: 'OFFER',
      summary: 'DHCPOFFER $offeredIp sent to ${packet.chaddrMac}${friendlyName != null ? " ($friendlyName)" : ""}',
      clientAddress: packet.chaddrMac,
      severity: LogSeverity.success,
    );
  }

  void _handleRequest(DhcpPacket packet) {
    final hasServerId = packet.serverIdentifier != null && packet.serverIdentifier != '0.0.0.0';

    // SELECTING state: if client specified a Server Identifier (Option 54) and it's NOT us, ignore packet
    if (hasServerId && packet.serverIdentifier != _serverIp) {
      _emitLog(
        action: 'REQUEST_IGNORED',
        summary: 'DHCPREQUEST from ${packet.chaddrMac} for other server ${packet.serverIdentifier} ignored',
        clientAddress: packet.chaddrMac,
        severity: LogSeverity.info,
      );
      return;
    }

    final targetIp = packet.requestedIp ?? (packet.ciaddr != '0.0.0.0' ? packet.ciaddr : null);

    // RFC 2131 §4.3.2 INIT-REBOOT / RENEWING / REBINDING without Option 54:
    // If we have no record of the client and its requested IP is in our subnet without conflict,
    // remain silent rather than sending a disruptive DHCPNAK.
    if (!hasServerId) {
      if (targetIp == null) return;
      final inSubnet = _leaseManager.isIpInSubnet(targetIp);
      final hasConflict = _leaseManager.isIpConflictingForMac(packet.chaddrMac, targetIp);
      final hasRecord = _leaseManager.hasClientRecord(packet.chaddrMac);

      if (inSubnet && !hasConflict && !hasRecord) {
        _emitLog(
          action: 'REQUEST_IGNORED',
          summary: 'Unrecorded INIT-REBOOT/RENEW DHCPREQUEST from ${packet.chaddrMac} for $targetIp ignored (RFC 2131 §4.3.2)',
          clientAddress: packet.chaddrMac,
          severity: LogSeverity.info,
        );
        return;
      }
    }

    // Inspect client MAC address in SharedDeviceDatabase or register new
    final knownDevice = SharedDeviceHelper.getDevice(packet.chaddrMac);
    final friendlyName = knownDevice?.name ?? packet.hostname;
    if (knownDevice == null) {
      SharedDeviceHelper.registerDiscoveredDevice(
        packet.chaddrMac,
        hostname: packet.hostname,
        notes: 'Discovered by DHCPREQUEST',
      );
    }

    final lease = _leaseManager.confirmLease(
      packet.chaddrMac,
      requestedIp: targetIp,
      hostname: packet.hostname,
      friendlyName: friendlyName,
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
      broadcastIp: _subnetBroadcastIp,
      ntpServerIp: _serverIp != '0.0.0.0' ? _serverIp : null,
    );

    // Respect broadcast bit (0x8000); if clear and client already has a valid ciaddr, unicast
    final broadcastFlagSet = (packet.flags & 0x8000) != 0;
    final unicastTarget = (!broadcastFlagSet && packet.ciaddr != '0.0.0.0') ? packet.ciaddr : null;
    _sendReply(replyBytes, targetIp: unicastTarget);

    _leasesController.add(_leaseManager.activeLeases);

    _emitLog(
      action: 'ACK',
      summary: 'DHCPACK: Leased ${lease.ipAddress} to ${packet.chaddrMac} (${lease.displayName})',
      clientAddress: packet.chaddrMac,
      severity: LogSeverity.success,
      details: 'Assigned IP: ${lease.ipAddress}\n'
          'MAC: ${lease.macAddress}\n'
          'Device Name: ${lease.displayName}\n'
          'Hostname: ${lease.hostname}\n'
          'Static Reservation: ${lease.isStatic ? "Yes" : "No"}\n'
          'Server IP: $_serverIp\n'
          'Lease Expiry: ${lease.isStatic ? "Permanent (Static)" : lease.leaseExpiry.toIso8601String()}',
    );
  }

  void _handleInform(DhcpPacket packet) {
    final replyBytes = DhcpPacketParser.buildReply(
      request: packet,
      replyType: DhcpMessageType.ack,
      offeredIp: '0.0.0.0',
      serverIp: _serverIp,
      subnetMask: config.subnetMask,
      routerIp: config.gatewayIp,
      dnsServerIp: config.useLocalDns ? _serverIp : config.dnsServerIp,
      leaseTimeSeconds: 0,
      includeLeaseTime: false,
      broadcastIp: _subnetBroadcastIp,
      ntpServerIp: _serverIp != '0.0.0.0' ? _serverIp : null,
    );

    final broadcastFlagSet = (packet.flags & 0x8000) != 0;
    final unicastTarget = (!broadcastFlagSet && packet.ciaddr != '0.0.0.0') ? packet.ciaddr : null;
    _sendReply(replyBytes, targetIp: unicastTarget);

    _emitLog(
      action: 'INFORM',
      summary: 'DHCPINFORM from ${packet.chaddrMac} (${packet.ciaddr}) answered with stateless DHCPACK',
      clientAddress: packet.chaddrMac,
      severity: LogSeverity.info,
    );
  }

  void _handleDecline(DhcpPacket packet) {
    if (packet.serverIdentifier != null &&
        packet.serverIdentifier != '0.0.0.0' &&
        packet.serverIdentifier != _serverIp) {
      return;
    }

    final declinedIp = packet.requestedIp ?? (packet.ciaddr != '0.0.0.0' ? packet.ciaddr : null);
    if (declinedIp == null) return;

    if (!_leaseManager.isIpHeldOrOfferedToMac(packet.chaddrMac, declinedIp)) {
      _emitLog(
        action: 'DECLINE_IGNORED',
        summary: 'Ignored unverified DHCPDECLINE from ${packet.chaddrMac} for $declinedIp (not leased/offered to this MAC)',
        clientAddress: packet.chaddrMac,
        severity: LogSeverity.warning,
      );
      return;
    }

    _leaseManager.declineIp(declinedIp);
    _leasesController.add(_leaseManager.activeLeases);

    _emitLog(
      action: 'DECLINE',
      summary: 'DHCPDECLINE received from ${packet.chaddrMac} for $declinedIp (quarantined for 10m)',
      clientAddress: packet.chaddrMac,
      severity: LogSeverity.warning,
    );
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
    if (_socket == null) return;

    if (targetIp != null && targetIp != '0.0.0.0') {
      try {
        final sent = _socket!.send(bytes, InternetAddress(targetIp), 68);
        if (sent > 0) return;
      } catch (_) {}
    }

    // Try directed subnet broadcast first, then limited broadcast 255.255.255.255 on port 68
    bool sentAny = false;
    final subnetBroadcast = _subnetBroadcastIp;
    if (subnetBroadcast != '255.255.255.255') {
      try {
        final sent = _socket!.send(bytes, InternetAddress(subnetBroadcast), 68);
        if (sent > 0) sentAny = true;
      } catch (_) {}
    }

    try {
      final sent = _socket!.send(bytes, InternetAddress('255.255.255.255'), 68);
      if (sent > 0) sentAny = true;
    } catch (e) {
      if (!sentAny) {
        _emitLog(
          action: 'SEND_ERROR',
          summary: 'Failed to broadcast DHCP reply on port 68: $e',
          severity: LogSeverity.error,
        );
      }
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
