import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../dashboard/view_models/network_services_view_model.dart';
import '../../shared/port_input_field.dart';
import '../../shared/service_status_badge.dart';

class NtpServicePanel extends StatefulWidget {
  const NtpServicePanel({super.key});

  @override
  State<NtpServicePanel> createState() => _NtpServicePanelState();
}

class _NtpServicePanelState extends State<NtpServicePanel> {
  late TextEditingController _portController;
  Timer? _clockTimer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    final vm = context.read<NetworkServicesViewModel>();
    _portController = TextEditingController(text: vm.ntpPort.toString());

    // M2: Local timer updates clock locally without rebuilding the entire application
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NetworkServicesViewModel>();
    final isRunning = vm.ntpStatus.isRunning;
    final utcTime = _currentTime.toUtc();
    final ntpEpochSeconds = (utcTime.millisecondsSinceEpoch ~/ 1000) + 2208988800;

    final ntpLogs = vm.filteredLogs.where((l) => l.serviceName == 'NTP').toList();

    return Column(
      children: [
        // Service Control Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Row(
            children: [
              Icon(Icons.access_time_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Network Time (NTP) Server',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              ServiceStatusBadge(status: vm.ntpStatus),
              const Spacer(),
              PortInputField(
                controller: _portController,
                enabled: !isRunning,
                presets: const [123, 1123],
                onPortChanged: (port) => vm.setNtpPort(port),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: () => vm.toggleNtp(),
                style: FilledButton.styleFrom(
                  backgroundColor: isRunning ? Colors.red.shade700 : Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: Icon(isRunning ? Icons.stop : Icons.play_arrow, size: 16),
                label: Text(isRunning ? 'Stop NTP' : 'Start NTP'),
              ),
            ],
          ),
        ),
        const Divider(),

        // Digital Clock Hero Banner
        Container(
          padding: const EdgeInsets.all(24),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Local Clock Display
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Local System Time', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('HH:mm:ss').format(_currentTime),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    DateFormat('EEEE, MMMM d, y').format(_currentTime),
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),

              // UTC & Epoch Display
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('UTC Clock Reference', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('HH:mm:ss').format(utcTime),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueAccent,
                    ),
                  ),
                  Text(
                    'Timezone: ${_currentTime.timeZoneName} (UTC${_currentTime.timeZoneOffset.isNegative ? "" : "+"}${_currentTime.timeZoneOffset.inHours})',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),

              // NTP Metadata & Stratum
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _diagRow('Stratum', '10 (Local Reference Clock)'),
                    const SizedBox(height: 4),
                    _diagRow('Precision', '~1 microsecond'),
                    const SizedBox(height: 4),
                    _diagRow('Ref ID', 'LOCL'),
                    const SizedBox(height: 4),
                    _diagRow('NTP Epoch', '$ntpEpochSeconds s'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(),

        // Time Synchronization Audit Log Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Time Synchronization Requests',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${ntpLogs.length} syncs',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // NTP Sync List
        Expanded(
          child: ntpLogs.isEmpty
              ? const Center(
                  child: Text(
                    'No client time synchronization requests received yet.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: ntpLogs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final log = ntpLogs[idx];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.sync, size: 20, color: Colors.blueAccent),
                      title: Text(
                        log.summary,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        'Client: ${log.clientAddress ?? "Unknown"} • Time: ${DateFormat("HH:mm:ss.SSS").format(log.timestamp)}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                      onTap: () => vm.selectLog(log),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _diagRow(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
