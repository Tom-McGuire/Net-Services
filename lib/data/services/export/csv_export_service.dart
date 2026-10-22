import 'dart:convert';
import 'dart:io';
import '../../../domain/models/service_log_record.dart';

class CsvExportService {
  static String formatCsv(List<ServiceLogRecord> logs) {
    final buffer = StringBuffer();
    buffer.writeln('ID,Timestamp,Service,Action,Severity,Client Address,Summary');

    for (final log in logs) {
      final safeSummary = '"${log.summary.replaceAll('"', '""')}"';
      final client = log.clientAddress ?? '';
      buffer.writeln(
        '${log.id},${log.timestamp.toIso8601String()},${log.serviceName},${log.action},${log.severity.name},$client,$safeSummary',
      );
    }

    return buffer.toString();
  }

  static String formatJson(List<ServiceLogRecord> logs) {
    final list = logs.map((log) => {
      'id': log.id,
      'timestamp': log.timestamp.toIso8601String(),
      'service': log.serviceName,
      'action': log.action,
      'severity': log.severity.name,
      'clientAddress': log.clientAddress,
      'summary': log.summary,
      'details': log.details,
    }).toList();

    return const JsonEncoder.withIndent('  ').convert(list);
  }

  static Future<String> exportToFile(String content, String filename) async {
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/$filename');
    await file.writeAsString(content);
    return file.path;
  }
}
