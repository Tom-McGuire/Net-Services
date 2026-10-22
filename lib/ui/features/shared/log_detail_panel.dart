import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../domain/models/service_log_record.dart';

class LogDetailPanel extends StatelessWidget {
  final ServiceLogRecord record;
  final VoidCallback onClose;

  const LogDetailPanel({
    super.key,
    required this.record,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Event Inspector: ${record.serviceName} - ${record.action}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: 'Copy details to clipboard',
                  onPressed: () {
                    final text = 'Timestamp: ${record.timestamp}\n'
                        'Service: ${record.serviceName}\n'
                        'Action: ${record.action}\n'
                        'Severity: ${record.severity.name}\n'
                        'Client: ${record.clientAddress ?? "None"}\n'
                        'Summary: ${record.summary}\n'
                        'Details:\n${record.details ?? "None"}';
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied log details to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _badge('Service: ${record.serviceName}', Colors.blueGrey),
                      const SizedBox(width: 8),
                      _badge('Severity: ${record.severity.name.toUpperCase()}', _severityColor(record.severity)),
                      const SizedBox(width: 8),
                      if (record.clientAddress != null)
                        _badge('Client: ${record.clientAddress}', Colors.indigo),
                      const Spacer(),
                      Text(
                        record.timestamp.toIso8601String(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    record.summary,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  if (record.details != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: SelectableText(
                        record.details!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _severityColor(LogSeverity severity) {
    switch (severity) {
      case LogSeverity.error:
        return Colors.red;
      case LogSeverity.warning:
        return Colors.orange;
      case LogSeverity.success:
        return Colors.green;
      case LogSeverity.info:
        return Colors.blue;
    }
  }
}
