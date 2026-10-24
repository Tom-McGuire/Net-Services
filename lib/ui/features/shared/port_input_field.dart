import 'package:flutter/material.dart';

class PortInputField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final List<int> presets;
  final ValueChanged<int>? onPortChanged;

  const PortInputField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.presets,
    this.onPortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Port:', style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(width: 6),
        SizedBox(
          width: 75,
          height: 32,
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            onChanged: (val) {
              final port = int.tryParse(val.trim());
              if (port != null && port >= 1 && port <= 65535 && onPortChanged != null) {
                onPortChanged!(port);
              }
            },
          ),
        ),
        if (enabled && presets.isNotEmpty)
          PopupMenuButton<int>(
            tooltip: 'Port Presets',
            icon: const Icon(Icons.arrow_drop_down, size: 20),
            padding: EdgeInsets.zero,
            onSelected: (port) {
              controller.text = port.toString();
              if (onPortChanged != null) {
                onPortChanged!(port);
              }
            },
            itemBuilder: (context) => presets.map((p) {
              final isPrivileged = p < 1024;
              return PopupMenuItem<int>(
                value: p,
                child: Text(
                  '$p (${isPrivileged ? "Standard" : "Unprivileged"})',
                  style: const TextStyle(fontSize: 12),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
