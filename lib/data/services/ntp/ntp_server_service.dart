import 'dart:async';
import 'dart:io';
import '../../../domain/models/service_log_record.dart';
import '../../../domain/models/service_status.dart';
import 'ntp_packet_parser.dart';

class NtpServerService {
  RawDatagramSocket? _socket;
  ServiceStatus _status = const ServiceStatus(port: 123);
  int _syncCount = 0;
  int _logSequence = 0;

  final _logController = StreamController<ServiceLogRecord>.broadcast();
  final _statusController = StreamController<ServiceStatus>.broadcast();

  Stream<ServiceLogRecord> get logStream => _logController.stream;
  Stream<ServiceStatus> get statusStream => _statusController.stream;
  ServiceStatus get status => _status;
  int get syncCount => _syncCount;

  Future<void> start({int port = 123, InternetAddress? bindAddress}) async {
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
        summary: 'NTP Time Server listening on ${targetAddress.address}:$port (Stratum 10 Local Clock)',
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
            summary: 'NTP Socket error: $err',
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
        summary: 'Failed to bind NTP port $port: $e',
        severity: LogSeverity.error,
        details: 'Ensure you have permission to bind to port $port (run with sudo/setcap on Linux if port < 1024), or try an unprivileged port like 1123.',
      );
    }
  }

  void _handlePacket(Datagram datagram) {
    final receiveTime = DateTime.now();

    if (!NtpPacketParser.isValidClientRequest(datagram.data)) {
      _emitLog(
        action: 'IGNORE',
        summary: 'Ignored non-NTP or malformed packet (${datagram.data.length} bytes) from ${datagram.address.address}',
        clientAddress: '${datagram.address.address}:${datagram.port}',
        severity: LogSeverity.warning,
      );
      return;
    }

    final transmitTime = DateTime.now();
    final responseBytes = NtpPacketParser.buildResponse(
      clientData: datagram.data,
      receiveTime: receiveTime,
      transmitTime: transmitTime,
    );

    _socket?.send(responseBytes, datagram.address, datagram.port);
    _syncCount++;

    _emitLog(
      action: 'SYNC',
      summary: 'NTP Sync with ${datagram.address.address}:${datagram.port}',
      clientAddress: '${datagram.address.address}:${datagram.port}',
      severity: LogSeverity.info,
      details: 'Local Time: ${transmitTime.toIso8601String()}\n'
          'Stratum: 10 (Undisciplined local reference clock)\n'
          'Precision: ~1 microsecond\n'
          'Reference ID: LOCL\n'
          'Total Syncs: $_syncCount',
    );
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    _status = _status.copyWith(state: ServiceState.stopped);
    _statusController.add(_status);

    _emitLog(
      action: 'STOP',
      summary: 'NTP Time Server stopped',
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
        serviceType: ServiceType.ntp,
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
