import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../../../domain/models/dhcp_lease.dart';
import '../../../domain/models/dns_record.dart';
import '../../../domain/models/service_log_record.dart';
import '../../../domain/models/service_status.dart';
import 'dns_packet_parser.dart';

class DnsServerService {
  RawDatagramSocket? _socket;
  ServiceStatus _status = const ServiceStatus(port: 53);
  final List<DnsRecord> _records = [];
  String? _upstreamDnsIp;
  List<DhcpLease> Function()? _activeLeasesProvider;
  int _logSequence = 0;

  final _logController = StreamController<ServiceLogRecord>.broadcast();
  final _statusController = StreamController<ServiceStatus>.broadcast();

  Stream<ServiceLogRecord> get logStream => _logController.stream;
  Stream<ServiceStatus> get statusStream => _statusController.stream;
  ServiceStatus get status => _status;
  List<DnsRecord> get records => List.unmodifiable(_records);
  String? get upstreamDnsIp => _upstreamDnsIp;

  void setUpstreamDnsIp(String? ip) {
    final trimmed = ip?.trim();
    _upstreamDnsIp = (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
  }

  void setActiveLeasesProvider(List<DhcpLease> Function()? provider) {
    _activeLeasesProvider = provider;
  }

  void setRecords(List<DnsRecord> records) {
    _records.clear();
    _records.addAll(records);
  }

  void addRecord(DnsRecord record) {
    _records.removeWhere((r) => r.domain.toLowerCase() == record.domain.toLowerCase());
    _records.add(record);
  }

  void removeRecord(String domain) {
    _records.removeWhere((r) => r.domain.toLowerCase() == domain.toLowerCase());
  }

  /// Resolves a domain against local records (exact -> suffix wildcard `*.domain` -> DHCP leases -> global `*`).
  DnsRecord? resolveRecord(String rawDomain) {
    final domain = rawDomain.toLowerCase();

    // 1. Exact match
    for (final r in _records) {
      if (r.domain.toLowerCase() == domain) {
        return r;
      }
    }

    // 2. Suffix wildcard match (e.g. *.lab.local matches host.lab.local or a.b.lab.local)
    DnsRecord? bestSuffixMatch;
    int bestSuffixLength = -1;
    for (final r in _records) {
      final pat = r.domain.toLowerCase();
      if (pat.startsWith('*.') && pat.length > 2) {
        final suffix = pat.substring(1); // '.lab.local'
        if (domain.endsWith(suffix) && domain.length > suffix.length) {
          if (suffix.length > bestSuffixLength) {
            bestSuffixLength = suffix.length;
            bestSuffixMatch = r;
          }
        }
      }
    }
    if (bestSuffixMatch != null) return bestSuffixMatch;

    // 3. Active DHCP leases (hostname or hostname.local)
    final leases = _activeLeasesProvider?.call() ?? const [];
    for (final lease in leases) {
      final host = lease.hostname.trim().toLowerCase();
      if (host.isNotEmpty && host != 'unknown') {
        if (domain == host || domain == '$host.local' || domain == '$host.lan') {
          return DnsRecord(domain: domain, ip: lease.ipAddress, ttl: 60);
        }
      }
    }

    // 4. Global wildcard '*'
    for (final r in _records) {
      if (r.domain == '*') {
        return r;
      }
    }

    return null;
  }

  /// Resolves a reverse DNS PTR query (e.g. `100.1.168.192.in-addr.arpa`) against local records and DHCP leases.
  String? resolvePtr(String rawDomain) {
    final lower = rawDomain.toLowerCase();
    const suffix = '.in-addr.arpa';
    if (!lower.endsWith(suffix)) return null;
    final prefix = lower.substring(0, lower.length - suffix.length);
    final parts = prefix.split('.');
    if (parts.length != 4) return null;
    final reversedIp = '${parts[3]}.${parts[2]}.${parts[1]}.${parts[0]}';

    for (final r in _records) {
      if (r.ip == reversedIp && !r.domain.contains('*')) {
        return r.domain;
      }
    }

    final leases = _activeLeasesProvider?.call() ?? const [];
    for (final lease in leases) {
      if (lease.ipAddress == reversedIp) {
        final host = lease.hostname.trim();
        if (host.isNotEmpty && host.toLowerCase() != 'unknown') {
          return host.contains('.') ? host : '$host.local';
        }
      }
    }
    return null;
  }

  Future<void> start({int port = 53, InternetAddress? bindAddress}) async {
    if (_status.isRunning) return;

    final targetAddress = bindAddress ?? InternetAddress.anyIPv4;

    try {
      _socket = await RawDatagramSocket.bind(
        targetAddress,
        port,
        reuseAddress: false,
        reusePort: false,
      );

      _status = ServiceStatus(
        state: ServiceState.running,
        port: port,
        startedAt: DateTime.now(),
      );
      _statusController.add(_status);

      _emitLog(
        action: 'START',
        summary: 'DNS Server listening on ${targetAddress.address}:$port',
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
            summary: 'DNS Socket error: $err',
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
        summary: 'Failed to bind DNS port $port: $e',
        severity: LogSeverity.error,
        details: 'Ensure you have permission to bind to port $port (run with sudo/setcap on Linux if port < 1024), or try an unprivileged port like 5353.',
      );
    }
  }

  void _handlePacket(Datagram datagram) {
    try {
      final query = DnsPacketParser.parseQuery(datagram.data);
      if (query == null) return;

      final domain = query.domain.toLowerCase();
      final isPtrQuery = query.qType == 12;

      if (isPtrQuery) {
        final ptrTarget = resolvePtr(domain);
        if (ptrTarget != null) {
          final responseBytes = DnsPacketParser.buildResponse(
            query: query,
            resolvedIp: null,
            resolvedPtrDomain: ptrTarget,
            isDomainKnown: true,
            recursionAvailable: _upstreamDnsIp != null,
          );
          _socket?.send(responseBytes, datagram.address, datagram.port);
          _emitLog(
            action: 'RESOLVED',
            summary: 'PTR Query "$domain" from ${datagram.address.address} -> $ptrTarget',
            clientAddress: '${datagram.address.address}:${datagram.port}',
            severity: LogSeverity.info,
          );
          return;
        }
      }

      final record = resolveRecord(domain);
      final isKnown = record != null;
      final resolvedIp = record?.ip;

      // If not matched locally (or if matched locally but for a non-A record type when upstream is enabled)
      if (!isKnown && _upstreamDnsIp != null && _upstreamDnsIp!.isNotEmpty) {
        _forwardToUpstream(datagram, query, _upstreamDnsIp!);
        return;
      }

      final responseBytes = DnsPacketParser.buildResponse(
        query: query,
        resolvedIp: resolvedIp,
        isDomainKnown: isKnown,
        recursionAvailable: _upstreamDnsIp != null,
        ttl: record?.ttl ?? 300,
      );

      _socket?.send(responseBytes, datagram.address, datagram.port);

      final isAQuery = query.qType == 1 || query.qType == 255;
      final action = !isKnown
          ? 'NXDOMAIN'
          : (isAQuery ? 'RESOLVED' : 'NODATA');

      _emitLog(
        action: action,
        summary: 'Query "$domain" (Type ${query.qType}) from ${datagram.address.address} -> ${!isKnown ? "NXDOMAIN" : (isAQuery ? resolvedIp : "NODATA (NOERROR)")}',
        clientAddress: '${datagram.address.address}:${datagram.port}',
        severity: isKnown ? LogSeverity.info : LogSeverity.warning,
        details: 'Transaction ID: 0x${query.transactionId.toRadixString(16).padLeft(4, '0')}\n'
            'Domain: $domain\n'
            'Type: ${query.qType}\n'
            'Class: ${query.qClass}\n'
            'Result: ${!isKnown ? "NXDOMAIN" : (isAQuery ? resolvedIp : "NODATA (NOERROR)")}',
      );
    } catch (e) {
      _emitLog(
        action: 'PARSE_ERROR',
        summary: 'Malformed DNS packet from ${datagram.address.address}: $e',
        severity: LogSeverity.warning,
      );
    }
  }

  Future<void> _forwardToUpstream(
    Datagram clientDatagram,
    DnsQuery query,
    String upstreamIp,
  ) async {
    RawDatagramSocket? relaySocket;
    try {
      final upstreamAddr = InternetAddress.tryParse(upstreamIp);
      if (upstreamAddr == null) return;

      relaySocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final completer = Completer<Uint8List?>();

      relaySocket.listen(
        (event) {
          if (event == RawSocketEvent.read && !completer.isCompleted) {
            final reply = relaySocket?.receive();
            if (reply != null && reply.data.length >= 12) {
              completer.complete(reply.data);
            }
          }
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
      );

      relaySocket.send(clientDatagram.data, upstreamAddr, 53);

      final upstreamResponse = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );

      if (upstreamResponse != null && _socket != null) {
        _socket?.send(upstreamResponse, clientDatagram.address, clientDatagram.port);
        _emitLog(
          action: 'FORWARDED',
          summary: 'Forwarded "${query.domain}" (Type ${query.qType}) for ${clientDatagram.address.address} via $upstreamIp',
          clientAddress: '${clientDatagram.address.address}:${clientDatagram.port}',
          severity: LogSeverity.info,
        );
      } else {
        // Fallback to NXDOMAIN on upstream timeout
        final fallback = DnsPacketParser.buildResponse(
          query: query,
          resolvedIp: null,
          isDomainKnown: false,
          recursionAvailable: true,
        );
        _socket?.send(fallback, clientDatagram.address, clientDatagram.port);
        _emitLog(
          action: 'UPSTREAM_TIMEOUT',
          summary: 'Upstream DNS $upstreamIp timed out for "${query.domain}"',
          clientAddress: '${clientDatagram.address.address}:${clientDatagram.port}',
          severity: LogSeverity.warning,
        );
      }
    } catch (e) {
      _emitLog(
        action: 'UPSTREAM_ERROR',
        summary: 'Failed to forward "${query.domain}" to $upstreamIp: $e',
        severity: LogSeverity.warning,
      );
    } finally {
      relaySocket?.close();
    }
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    _status = _status.copyWith(state: ServiceState.stopped);
    _statusController.add(_status);

    _emitLog(
      action: 'STOP',
      summary: 'DNS Server stopped',
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
        serviceType: ServiceType.dns,
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
  }
}
