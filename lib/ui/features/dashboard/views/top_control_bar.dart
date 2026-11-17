import 'package:material_ui/material_ui.dart';
import 'package:net_services/domain/models/network_interface_info.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../shared/device_library_dialog.dart';
import '../view_models/network_services_view_model.dart';

class TopControlBar extends StatelessWidget {
  final GlobalKey? zone2Key;
  final GlobalKey? zone3Key;
  final GlobalKey? exitDemoKey;

  const TopControlBar({
    super.key,
    this.zone2Key,
    this.zone3Key,
    this.exitDemoKey,
  });

  Future<void> _handleStartAll(BuildContext context, NetworkServicesViewModel vm) async {
    final iface = vm.selectedInterface?.name ?? 'Default';
    final ip = vm.selectedInterface?.ip ?? '0.0.0.0';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
            const SizedBox(width: 8),
            const Text('Start All Services Confirmation'),
          ],
        ),
        content: Text(
          'Starting all services will activate DNS, NTP, and DHCP on interface "$iface" ($ip).\n\n'
          'DHCP servers must only be run on isolated or test networks. '
          'Running DHCP on an existing network can cause address conflicts for other devices.\n\n'
          'Do you wish to start all services?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.warning,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm & Start All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await vm.startAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NetworkServicesViewModel>();
    final isAnyRunning = vm.isAnyServiceRunning;
    final hasElevated = vm.hasElevatedPrivileges;
    final exportEnabled = vm.filteredLogs.isNotEmpty;
    final exportForeground =
        exportEnabled ? AppTheme.textSecondary : AppTheme.textMuted;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : 1280.0;
          const minRequiredWidth = 1360.0;
          final contentWidth = availWidth > (minRequiredWidth + 32)
              ? (availWidth - 32)
              : minRequiredWidth;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: contentWidth,
              height: 52,
              child: Row(
                children: [
                  // ==================== ZONE 1: BRANDING ====================
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/icons/app_icon.jpg',
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.hub_outlined,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NETWORK SERVICES',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'DHCP • DNS • NTP • WOL',
                        style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),

                  // ==================== ZONE 2: INTERFACE & TARGET ====================
                  Row(
                    key: zone2Key,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 32,
                        width: 175,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceHigh,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.inputBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<NetworkInterfaceInfo>(
                            value: vm.selectedInterface,
                            isDense: true,
                            isExpanded: true,
                            dropdownColor: AppTheme.surfaceHigh,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textPrimary,
                              fontFamily: 'monospace',
                            ),
                            items: vm.interfaces.map((iface) {
                              return DropdownMenuItem<NetworkInterfaceInfo>(
                                value: iface,
                                child: Text(
                                  '${iface.name} - ${iface.ip} (/${iface.prefixLength})',
                                  overflow: TextOverflow.ellipsis,
                                ),
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
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 16),
                        tooltip: 'Refresh Interfaces',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () => vm.refreshInterfaces(),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: hasElevated ? 'Elevated / Root Privileges' : 'Standard User (sudo needed for ports < 1024)',
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: hasElevated
                                ? AppTheme.success.withValues(alpha: 0.15)
                                : AppTheme.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: hasElevated
                                  ? AppTheme.success.withValues(alpha: 0.4)
                                  : AppTheme.warning.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasElevated ? Icons.admin_panel_settings : Icons.lock_outline,
                                size: 13,
                                color: hasElevated ? AppTheme.success : AppTheme.warning,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                hasElevated ? 'Root' : 'User',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: hasElevated ? AppTheme.success : AppTheme.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // ==================== ZONE 3: PRIMARY ACTIONS ====================
                  FilledButton.icon(
                    key: zone3Key,
                    onPressed: () {
                      if (isAnyRunning) {
                        vm.stopAll();
                      } else {
                        _handleStartAll(context, vm);
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: isAnyRunning
                          ? AppTheme.error
                          : AppTheme.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(isAnyRunning ? Icons.stop : Icons.play_arrow, size: 16),
                    label: Text(
                      isAnyRunning ? 'Stop All' : 'Start All',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),

                  const Spacer(),

                  // ==================== ZONE 4: ECOSYSTEM & DEMO ====================
                  OutlinedButton.icon(
                    onPressed: () => DeviceLibraryDialog.show(context),
                    icon: const Icon(Icons.devices, size: 15),
                    label: const Text('Device Library', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: exitDemoKey,
                    onPressed: vm.isDemoMode
                        ? () => vm.endDemoWalkthrough()
                        : (isAnyRunning ? null : () => vm.startDemoWalkthrough()),
                    icon: Icon(
                      vm.isDemoMode
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outline,
                      size: 15,
                      color: vm.isDemoMode ? AppTheme.warning : null,
                    ),
                    label: Text(
                      vm.isDemoMode ? 'Exit Demo' : 'Load Demo',
                      style: TextStyle(
                        fontSize: 11,
                        color: vm.isDemoMode ? AppTheme.warning : null,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: vm.isDemoMode ? AppTheme.warning : null,
                      side: vm.isDemoMode
                          ? BorderSide(
                              color: AppTheme.warning.withValues(alpha: 0.7),
                            )
                          : null,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // ==================== ZONE 5: CLEAR & EXPORT ====================
                  OutlinedButton.icon(
                    onPressed: vm.filteredLogs.isEmpty ? null : () => _confirmClear(context, vm),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 15),
                    label: const Text('Clear', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    tooltip: 'Export',
                    enabled: exportEnabled,
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
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: exportEnabled ? AppTheme.inputBorder : AppTheme.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.download, size: 15, color: exportForeground),
                          const SizedBox(width: 6),
                          Text('Export', style: TextStyle(fontSize: 11, color: exportForeground)),
                          Icon(Icons.arrow_drop_down, size: 14, color: exportForeground),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmClear(BuildContext context, NetworkServicesViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Activity Logs?'),
        content: const Text('Are you sure you want to clear all logged server activity?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              vm.clearLogs();
              Navigator.of(ctx).pop();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
