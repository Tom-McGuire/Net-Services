import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../domain/models/service_log_record.dart';

class LogDetailPanel extends StatefulWidget {
  final ServiceLogRecord record;
  final VoidCallback onClose;

  const LogDetailPanel({
    super.key,
    required this.record,
    required this.onClose,
  });

  @override
  State<LogDetailPanel> createState() => _LogDetailPanelState();
}

class _LogDetailPanelState extends State<LogDetailPanel> {
  // Remember user's preferred height across log selection switches
  static double _persistedHeight = 260.0;
  static double? _preMaximizedHeight;

  late double _currentHeight;
  bool _isDragging = false;
  bool _isHoveringHandle = false;

  @override
  void initState() {
    super.initState();
    _currentHeight = _persistedHeight;
  }

  void _toggleMaximize(double maxHeight) {
    setState(() {
      final isMaximized = _currentHeight >= maxHeight - 10;
      if (isMaximized) {
        // Restore to previous or default
        _currentHeight = (_preMaximizedHeight ?? 260.0).clamp(120.0, maxHeight);
      } else {
        // Maximize
        _preMaximizedHeight = _currentHeight;
        _currentHeight = maxHeight;
      }
      _persistedHeight = _currentHeight;
    });
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final screenHeight = MediaQuery.of(context).size.height;
    final minHeight = 120.0;
    final maxHeight = (screenHeight * 0.75).clamp(minHeight + 50.0, 750.0);

    // Ensure within valid bounds
    if (_currentHeight < minHeight) _currentHeight = minHeight;
    if (_currentHeight > maxHeight) _currentHeight = maxHeight;

    final isMaximized = _currentHeight >= maxHeight - 10;

    return Container(
      height: _currentHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(
            color: _isDragging || _isHoveringHandle
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: _isDragging ? 2.0 : 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle bar at top
          MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            onEnter: (_) => setState(() => _isHoveringHandle = true),
            onExit: (_) => setState(() => _isHoveringHandle = false),
            child: GestureDetector(
              key: const Key('log_detail_resize_handle'),
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) => setState(() => _isDragging = true),
              onVerticalDragEnd: (_) => setState(() => _isDragging = false),
              onVerticalDragCancel: () => setState(() => _isDragging = false),
              onVerticalDragUpdate: (details) {
                setState(() {
                  // Dragging UP (negative dy) increases height; dragging DOWN (positive dy) decreases height
                  final newHeight = (_currentHeight - details.delta.dy).clamp(minHeight, maxHeight);
                  _currentHeight = newHeight;
                  _persistedHeight = newHeight;
                });
              },
              onDoubleTap: () => _toggleMaximize(maxHeight),
              child: Container(
                height: 12,
                color: _isDragging
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                    : (_isHoveringHandle
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : Colors.transparent),
                child: Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _isDragging || _isHoveringHandle
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade600,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                const SizedBox(width: 8),
                Text(
                  '(${_currentHeight.round()}px)',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const Spacer(),
                // Maximize / Restore button
                IconButton(
                  icon: Icon(
                    isMaximized ? Icons.unfold_less : Icons.unfold_more,
                    size: 16,
                  ),
                  tooltip: isMaximized ? 'Restore height' : 'Maximize height',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _toggleMaximize(maxHeight),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: 'Copy details to clipboard',
                  visualDensity: VisualDensity.compact,
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
                  tooltip: 'Close inspector',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
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
