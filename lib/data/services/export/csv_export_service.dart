import 'dart:convert';
import 'dart:io';
import '../../../domain/models/service_log_record.dart';

class CsvExportService {
  static String formatCsv(List<ServiceLogRecord> logs) {
    final buffer = StringBuffer();
    buffer.writeln('"ID","Timestamp","Service","Action","Severity","Client Address","Summary"');

    for (final log in logs) {
      buffer.writeln([
        _sanitizeCsvCell(log.id),
        _sanitizeCsvCell(log.timestamp.toIso8601String()),
        _sanitizeCsvCell(log.serviceName),
        _sanitizeCsvCell(log.action),
        _sanitizeCsvCell(log.severity.name),
        _sanitizeCsvCell(log.clientAddress ?? ''),
        _sanitizeCsvCell(log.summary),
      ].join(','));
    }

    return buffer.toString();
  }

  static String _sanitizeCsvCell(String value) {
    var v = value;
    // Prevent spreadsheet formula injection (e.g. =CMD, +SUM, -DIFF, @IMPORT)
    if (v.startsWith('=') || v.startsWith('+') || v.startsWith('-') || v.startsWith('@')) {
      v = "'$v";
    }
    return '"${v.replaceAll('"', '""')}"';
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
    final sanitizedFilename = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._\-]'), '_');
    final tempDir = Directory.systemTemp;
    final exportDir = Directory('${tempDir.path}/net_services_exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final file = File('${exportDir.path}/$sanitizedFilename');
    await file.writeAsString(content);
    return file.path;
  }
}
