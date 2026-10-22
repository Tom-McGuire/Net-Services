import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:net_services/domain/models/service_log_record.dart';
import 'package:provider/provider.dart';
import '../view_models/network_services_view_model.dart';

class ActivityLogTableView extends StatelessWidget {
  const ActivityLogTableView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NetworkServicesViewModel>();
    final logs = vm.filteredLogs;

    return Column(
      children: [
        // Filter bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Row(
            children: [
              // Service Filter Segmented Buttons / Chips
              const Text('Filter:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 8),
              _filterChip(context, vm, 'ALL', 'All Services'),
              const SizedBox(width: 6),
              _filterChip(context, vm, 'DHCP', 'DHCP'),
              const SizedBox(width: 6),
              _filterChip(context, vm, 'NTP', 'NTP'),
              const SizedBox(width: 6),
              _filterChip(context, vm, 'DNS', 'DNS'),
              const Spacer(),

              // Search field
              SizedBox(
                width: 220,
                height: 32,
                child: TextField(
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Search activity logs...',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    suffixIcon: vm.searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 14),
                            onPressed: () => vm.setSearchQuery(''),
                          )
                        : null,
                  ),
                  onChanged: (val) => vm.setSearchQuery(val),
                ),
              ),
            ],
          ),
        ),
        const Divider(),

        // Log Table
        Expanded(
          child: logs.isEmpty
              ? const Center(
                  child: Text(
                    'No matching network activity recorded yet.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              : ListView.separated(
                  itemCount: logs.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final isSelected = vm.selectedLog?.id == log.id;

                    return InkWell(
                      onTap: () => vm.selectLog(log),
                      child: Container(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                            : null,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Row(
                          children: [
                            // Timestamp
                            SizedBox(
                              width: 85,
                              child: Text(
                                DateFormat('HH:mm:ss.SSS').format(log.timestamp),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Service Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _serviceColor(log.serviceType).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _serviceColor(log.serviceType).withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                log.serviceName,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _serviceColor(log.serviceType),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Action Tag
                            SizedBox(
                              width: 110,
                              child: Text(
                                log.action,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _severityColor(log.severity),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Client Address
                            SizedBox(
                              width: 140,
                              child: Text(
                                log.clientAddress ?? '-',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Summary
                            Expanded(
                              child: Text(
                                log.summary,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _filterChip(
    BuildContext context,
    NetworkServicesViewModel vm,
    String value,
    String label,
  ) {
    final isSelected = vm.logFilter == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      onSelected: (_) => vm.setLogFilter(value),
      visualDensity: VisualDensity.compact,
    );
  }

  Color _serviceColor(ServiceType type) {
    switch (type) {
      case ServiceType.dhcp:
        return Colors.amber;
      case ServiceType.ntp:
        return Colors.tealAccent;
      case ServiceType.dns:
        return Colors.lightBlueAccent;
      case ServiceType.system:
        return Colors.purpleAccent;
    }
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
        return Colors.white70;
    }
  }
}
