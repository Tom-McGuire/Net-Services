import 'dart:io';
import 'package:flutter/material.dart';

class GlobalErrorBanner extends StatelessWidget {
  final String errorMessage;
  final VoidCallback? onDismiss;

  const GlobalErrorBanner({
    super.key,
    required this.errorMessage,
    this.onDismiss,
  });

  String _resolveTip() {
    if (Platform.isWindows &&
        errorMessage.contains('123') &&
        (errorMessage.contains('10013') || errorMessage.contains('forbidden'))) {
      return 'Tip (Windows): The Windows Time service (W32Time) holds UDP port 123 by default. Run "net stop w32time" in an Administrator command prompt to release it, or test using port 1123.';
    }
    if (Platform.isWindows &&
        (errorMessage.contains('10013') || errorMessage.contains('forbidden'))) {
      return 'Tip (Windows): Socket access forbidden (error 10013). Run Net-Services as Administrator or check if another application is holding this port.';
    }
    return 'Tip: Binding ports < 1024 requires root/sudo permissions on Linux. Either launch with sudo, or test using unprivileged ports (DNS: 5353, NTP: 1123, DHCP: 6767).';
  }

  @override
  Widget build(BuildContext context) {
    final tip = _resolveTip();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.red.shade900.withValues(alpha: 0.85),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  errorMessage,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tip,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.white70),
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}
