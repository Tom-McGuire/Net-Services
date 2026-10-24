import 'dart:async';
import 'dart:io';
import '../../../domain/models/dns_record.dart';
import '../../../domain/models/service_log_record.dart';
import '../../../domain/models/service_status.dart';
import 'dns_packet_parser.dart';

class DnsServerService {
  RawDatagramSocket? _socket;
  ServiceStatus _status = const ServiceStatus(port: 53);
  final List<DnsRecord> _records = [];
  int _logSequence = 0;

  final _logController = StreamController<ServiceLogRecord>.broadcast();
  final _statusController = StreamController<ServiceStatus>.broadcast();

  Stream<ServiceLogRecord> get logStream => _logController.stream;
  Stream<ServiceStatus> get statusStream => _statusController.stream;
  ServiceStatus get status => _status;
  List<DnsRecord> get records => List.unmodifiable(_records);

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

      // L5: Exact match first, then fallback to wildcard '*'
      DnsRecord? record = _records.cast<DnsRecord?>().firstWhere(
            (r) => r?.domain.toLowerCase() == domain,
            orElse: () => null,
          );
      record ??= _records.cast<DnsRecord?>().firstWhere(
            (r) => r?.domain == '*',
            orElse: () => null,
          );

      final isKnown = record != null;
      final resolvedIp = record?.ip;

      final responseBytes = DnsPacketParser.buildResponse(
        query: query,
        resolvedIp: resolvedIp,
        isDomainKnown: isKnown,
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
