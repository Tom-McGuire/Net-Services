import 'package:flutter/material.dart';
import '../../../domain/models/service_status.dart';

class ServiceStatusBadge extends StatelessWidget {
  final ServiceStatus status;

  const ServiceStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    switch (status.state) {
      case ServiceState.running:
        color = Colors.green;
        label = 'RUNNING (Port ${status.port})';
        icon = Icons.check_circle;
        break;
      case ServiceState.error:
        color = Colors.red;
        label = 'ERROR';
        icon = Icons.error_outline;
        break;
      case ServiceState.stopped:
        color = Colors.grey;
        label = 'STOPPED';
        icon = Icons.pause_circle_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
