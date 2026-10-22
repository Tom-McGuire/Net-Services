import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:net_services/domain/models/dns_record.dart';
import 'package:provider/provider.dart';
import '../../dashboard/view_models/network_services_view_model.dart';
import '../../shared/port_input_field.dart';
import '../../shared/service_status_badge.dart';

class DnsServicePanel extends StatefulWidget {
  const DnsServicePanel({super.key});

  @override
  State<DnsServicePanel> createState() => _DnsServicePanelState();
}

class _DnsServicePanelState extends State<DnsServicePanel> {
  late TextEditingController _portController;
  final TextEditingController _domainController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final vm = context.read<NetworkServicesViewModel>();
    _portController = TextEditingController(text: vm.dnsPort.toString());
  }

  @override
  void dispose() {
    _portController.dispose();
    _domainController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  void _addRecord(NetworkServicesViewModel vm) {
    final domain = _domainController.text.trim();
    final ip = _ipController.text.trim();

    if (domain.isEmpty || ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both domain name and target IP address')),
      );
      return;
    }

    vm.addDnsRecord(DnsRecord(domain: domain, ip: ip));
    _domainController.clear();
    _ipController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NetworkServicesViewModel>();
    final isRunning = vm.dnsStatus.isRunning;
    final dnsLogs = vm.filteredLogs.where((l) => l.serviceName == 'DNS').toList();

    return Column(
      children: [
        // Service Control Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Row(
            children: [
              Icon(Icons.dns_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text(
                'DNS Server',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              ServiceStatusBadge(status: vm.dnsStatus),
              const Spacer(),
              PortInputField(
                controller: _portController,
                enabled: !isRunning,
                presets: const [53, 5353],
                onPortChanged: (port) => vm.setDnsPort(port),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: () => vm.toggleDns(),
                style: FilledButton.styleFrom(
                  backgroundColor: isRunning ? Colors.red.shade700 : Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: Icon(isRunning ? Icons.stop : Icons.play_arrow, size: 16),
                label: Text(isRunning ? 'Stop DNS' : 'Start DNS'),
              ),
            ],
          ),
        ),
        const Divider(),

        // Add New Mapping Row
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              const Text(
                'New Record:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _domainController,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: 'e.g. printer.local or test.dev',
                    labelText: 'Domain / Hostname',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _ipController,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: 'e.g. 192.168.1.50',
                    labelText: 'Points to IP Address',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _addRecord(vm),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Mapping'),
              ),
            ],
          ),
        ),
        const Divider(),

        // Records Table & Live Queries Split View
        Expanded(
          child: Row(
            children: [
              // Configured Mappings Table
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: Text(
                        'Configured DNS Records (${vm.dnsRecords.length})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: vm.dnsRecords.isEmpty
                          ? const Center(
                              child: Text(
                                'No DNS records configured. Add one above.',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            )
                          : ListView.separated(
                              itemCount: vm.dnsRecords.length,
                              separatorBuilder: (_, _) => const Divider(),
                              itemBuilder: (context, index) {
                                final record = vm.dnsRecords[index];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.link, size: 18, color: Colors.blueAccent),
                                  title: Text(
                                    record.domain,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Points to: ${record.ip} • TTL: ${record.ttl}s',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                    onPressed: () => vm.removeDnsRecord(record.domain),
                                    tooltip: 'Remove Record',
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(),

              // Live DNS Queries Log
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: Text(
                        'Live DNS Query Activity (${dnsLogs.length})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: dnsLogs.isEmpty
                          ? Center(
                              child: Text(
                                isRunning
                                    ? 'DNS server active. Waiting for queries...'
                                    : 'Start the DNS server to begin resolving queries.',
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            )
                          : ListView.separated(
                              itemCount: dnsLogs.length,
                              separatorBuilder: (_, _) => const Divider(),
                              itemBuilder: (context, index) {
                                final log = dnsLogs[index];
                                final isResolved = log.action == 'RESOLVED';
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    isResolved ? Icons.check_circle_outline : Icons.help_outline,
                                    size: 16,
                                    color: isResolved ? Colors.green : Colors.orange,
                                  ),
                                  title: Text(
                                    log.summary,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Time: ${DateFormat("HH:mm:ss.SSS").format(log.timestamp)}',
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                  onTap: () => vm.selectLog(log),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
