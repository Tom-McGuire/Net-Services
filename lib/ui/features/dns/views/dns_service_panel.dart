import 'dart:io';
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

    final parsedIp = InternetAddress.tryParse(ip);
    if (parsedIp == null || parsedIp.type != InternetAddressType.IPv4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Target IP must be a valid IPv4 address (e.g. 192.168.1.10)')),
      );
      return;
    }

    if (domain != '*' && !RegExp(r'^[a-zA-Z0-9_\-\.]+$').hasMatch(domain)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Domain name contains invalid characters')),
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

        // Content Area: Split View (Records Config & Live Query Monitor)
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Configured Records Panel
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Static Host Records',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Map domain hostnames to IP addresses. Wildcard (*) matches any unmapped request.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),

                      // Add Record Form
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _domainController,
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                              decoration: const InputDecoration(
                                hintText: 'Domain (e.g. gateway.local or *)',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _ipController,
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                              decoration: const InputDecoration(
                                hintText: 'IP (e.g. 192.168.1.1)',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () => _addRecord(vm),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Records Table
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).dividerColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: vm.dnsRecords.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No DNS records added yet.',
                                    style: TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: vm.dnsRecords.length,
                                  separatorBuilder: (_, _) => const Divider(height: 1),
                                  itemBuilder: (context, idx) {
                                    final record = vm.dnsRecords[idx];
                                    final isWildcard = record.domain == '*';
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(
                                        isWildcard ? Icons.stars : Icons.public,
                                        size: 16,
                                        color: isWildcard ? Colors.amber : Colors.blue,
                                      ),
                                      title: Text(
                                        record.domain,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isWildcard ? Colors.amber : null,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'Type: A • TTL: ${record.ttl}s',
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              record.ip,
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 12,
                                                color: Colors.blue,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                                            tooltip: 'Remove Record',
                                            onPressed: () => vm.removeDnsRecord(record.domain),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const VerticalDivider(width: 1),

              // Right: Recent DNS Queries Log
              Expanded(
                flex: 5,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Live Query Resolution Stream',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${dnsLogs.length} events logged',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).dividerColor),
                            borderRadius: BorderRadius.circular(8),
                            color: Theme.of(context).colorScheme.surfaceContainerLowest,
                          ),
                          child: dnsLogs.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No DNS queries resolved yet.',
                                    style: TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: dnsLogs.length,
                                  itemBuilder: (context, idx) {
                                    final log = dnsLogs[idx];
                                    final isResolved = log.action == 'RESOLVED';
                                    final timeStr = DateFormat('HH:mm:ss.SSS').format(log.timestamp);
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            timeStr,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontFamily: 'monospace',
                                              color: Colors.grey,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isResolved
                                                  ? Colors.green.withValues(alpha: 0.15)
                                                  : Colors.orange.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              log.action,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: isResolved ? Colors.green : Colors.orange,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              log.summary,
                                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
