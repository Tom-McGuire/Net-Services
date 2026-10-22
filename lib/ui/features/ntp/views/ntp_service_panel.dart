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

  @override
  void initState() {
    super.initState();
    final vm = context.read<NetworkServicesViewModel>();
    _portController = TextEditingController(text: vm.ntpPort.toString());
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NetworkServicesViewModel>();
    final isRunning = vm.ntpStatus.isRunning;
    final currentTime = vm.currentTime;
    final utcTime = currentTime.toUtc();
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

        // Live Clock Hero Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              // Digital Clock
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HOST MACHINE LOCAL TIME',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat('HH:mm:ss').format(currentTime),
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat('EEEE, MMMM d, yyyy').format(currentTime)} (${currentTime.timeZoneName})',
                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
              ),

              // Diagnostics & Epoch
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _diagRow('Stratum', '1 (LOCL Primary Reference Clock)'),
                    const SizedBox(height: 6),
                    _diagRow('UTC Time', DateFormat('yyyy-MM-dd HH:mm:ss').format(utcTime)),
                    const SizedBox(height: 6),
                    _diagRow('NTP Epoch', '$ntpEpochSeconds sec'),
                    const SizedBox(height: 6),
                    _diagRow('Protocol', 'RFC 5905 UDP / Mode 4 Server'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(),

        // Sync Audit Log Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Row(
            children: [
              const Icon(Icons.history, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                'Recent Time Sync Requests (${ntpLogs.length})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),

        // Sync Requests List
        Expanded(
          child: ntpLogs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 40, color: Colors.grey.shade700),
                      const SizedBox(height: 8),
                      Text(
                        isRunning
                            ? 'NTP server listening on port ${vm.ntpPort}. Ready to serve time requests.'
                            : 'Start the NTP server to serve local time to client devices.',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: ntpLogs.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final log = ntpLogs[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.sync, size: 18, color: Colors.tealAccent),
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
