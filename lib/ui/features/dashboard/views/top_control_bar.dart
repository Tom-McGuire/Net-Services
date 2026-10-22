import 'package:flutter/material.dart';
import 'package:net_services/domain/models/network_interface_info.dart';
import 'package:provider/provider.dart';
import '../view_models/network_services_view_model.dart';

class TopControlBar extends StatelessWidget {
  const TopControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NetworkServicesViewModel>();
    final isAnyRunning = vm.isAnyServiceRunning;
    final hasElevated = vm.hasElevatedPrivileges;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // App Logo & Title
            Icon(
              Icons.hub_outlined,
              size: 24,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Network Services',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'DHCP • NTP • DNS Server Suite',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(width: 24),

            // Interface Selector
            const Text('Interface:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<NetworkInterfaceInfo>(
                  value: vm.selectedInterface,
                  isDense: true,
                  style: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'monospace'),
                  items: vm.interfaces.map((iface) {
                    return DropdownMenuItem<NetworkInterfaceInfo>(
                      value: iface,
                      child: Text('${iface.name} - ${iface.ip} (/${iface.prefixLength})'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      vm.selectInterface(val);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Privilege Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasElevated
                    ? Colors.green.withValues(alpha: 0.15)
                    : Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: hasElevated
                      ? Colors.green.withValues(alpha: 0.4)
                      : Colors.orange.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasElevated ? Icons.admin_panel_settings : Icons.lock_outline,
                    size: 14,
                    color: hasElevated ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    hasElevated ? 'Elevated / Root' : 'Standard User (sudo needed for <1024)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: hasElevated ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),

            // Start All / Stop All Button
            FilledButton.icon(
              onPressed: () {
                if (isAnyRunning) {
                  vm.stopAll();
                } else {
                  vm.startAll();
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: isAnyRunning ? Colors.red.shade700 : Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              icon: Icon(
                isAnyRunning ? Icons.stop : Icons.play_arrow,
                size: 18,
              ),
              label: Text(
                isAnyRunning ? 'Stop All Services' : 'Start All Services',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),

            // Clear Logs Button
            OutlinedButton.icon(
              onPressed: vm.filteredLogs.isEmpty ? null : () => _confirmClear(context, vm),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Clear Logs'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade300,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
            const SizedBox(width: 8),

            // Export Menu
            PopupMenuButton<String>(
              tooltip: 'Export Logs',
              enabled: vm.filteredLogs.isNotEmpty,
              icon: const Icon(Icons.file_download_outlined, size: 20),
              onSelected: (val) async {
                if (val == 'csv') {
                  final path = await vm.exportCsv();
                  if (path != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Exported logs to CSV: $path')),
                    );
                  }
                } else if (val == 'json') {
                  final path = await vm.exportJson();
                  if (path != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Exported logs to JSON: $path')),
                    );
                  }
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'csv',
                  child: Row(
                    children: [
                      Icon(Icons.table_chart, size: 16),
                      SizedBox(width: 8),
                      Text('Export as CSV'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'json',
                  child: Row(
                    children: [
                      Icon(Icons.code, size: 16),
                      SizedBox(width: 8),
                      Text('Export as JSON'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClear(BuildContext context, NetworkServicesViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Activity Logs?'),
        content: const Text('This will clear all captured activity records from this session.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(ctx).pop();
              vm.clearLogs();
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
