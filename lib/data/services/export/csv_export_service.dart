import 'dart:convert';
import 'dart:io';
import '../../../domain/models/service_log_record.dart';

class CsvExportService {
  static String formatCsv(List<ServiceLogRecord> logs) {
    final buffer = StringBuffer();
    buffer.writeln('"ID","Timestamp","Service","Action","Severity","Client Address","Summary","Details"');

    for (final log in logs) {
      buffer.writeln([
        _sanitizeCsvCell(log.id),
        _sanitizeCsvCell(log.timestamp.toIso8601String()),
        _sanitizeCsvCell(log.serviceName),
        _sanitizeCsvCell(log.action),
        _sanitizeCsvCell(log.severity.name),
        _sanitizeCsvCell(log.clientAddress ?? ''),
        _sanitizeCsvCell(log.summary),
        _sanitizeCsvCell((log.details ?? '').replaceAll('\r\n', ' ').replaceAll('\n', ' ')),
      ].join(','));
    }

    return buffer.toString();
  }

  static String _sanitizeCsvCell(String value) {
    var v = value;
    // Prevent spreadsheet formula injection (e.g. =CMD, +SUM, -DIFF, @IMPORT, leading tab/CR)
    if (v.startsWith('=') ||
        v.startsWith('+') ||
        v.startsWith('-') ||
        v.startsWith('@') ||
        v.startsWith('\t') ||
        v.startsWith('\r')) {
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
    Directory baseDir = Directory.systemTemp;
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      final downloads = Directory('$home${Platform.pathSeparator}Downloads');
      if (await downloads.exists()) {
        baseDir = downloads;
      }
    }
    final exportDir = Directory('${baseDir.path}${Platform.pathSeparator}net_services_exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final file = File('${exportDir.path}${Platform.pathSeparator}$sanitizedFilename');
    await file.writeAsString(content);
    return file.path;
  }
}
