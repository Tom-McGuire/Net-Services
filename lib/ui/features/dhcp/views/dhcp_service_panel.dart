import 'package:flutter/material.dart';
import 'package:net_services/domain/models/dhcp_config.dart';
import 'package:provider/provider.dart';
import '../../dashboard/view_models/network_services_view_model.dart';
import '../../shared/port_input_field.dart';
import '../../shared/service_status_badge.dart';

class DhcpServicePanel extends StatefulWidget {
  const DhcpServicePanel({super.key});

  @override
  State<DhcpServicePanel> createState() => _DhcpServicePanelState();
}

class _DhcpServicePanelState extends State<DhcpServicePanel> {
  late TextEditingController _portController;
  late TextEditingController _startIpController;
  late TextEditingController _poolSizeController;
  late TextEditingController _subnetMaskController;
  late TextEditingController _gatewayController;
  late TextEditingController _dnsController;
  late TextEditingController _leaseHoursController;

  @override
  void initState() {
    super.initState();
    final vm = context.read<NetworkServicesViewModel>();
    _portController = TextEditingController(text: vm.dhcpPort.toString());
    _startIpController = TextEditingController(text: vm.dhcpConfig.startIp);
    _poolSizeController = TextEditingController(text: vm.dhcpConfig.poolSize.toString());
    _subnetMaskController = TextEditingController(text: vm.dhcpConfig.subnetMask);
    _gatewayController = TextEditingController(text: vm.dhcpConfig.gatewayIp);
    _dnsController = TextEditingController(text: vm.dhcpConfig.dnsServerIp);
    _leaseHoursController = TextEditingController(
      text: (vm.dhcpConfig.leaseTimeSeconds ~/ 3600).toString(),
    );
  }

  @override
  void dispose() {
    _portController.dispose();
    _startIpController.dispose();
    _poolSizeController.dispose();
    _subnetMaskController.dispose();
    _gatewayController.dispose();
    _dnsController.dispose();
    _leaseHoursController.dispose();
    super.dispose();
  }

  void _syncControllersWithVm(DhcpConfig config) {
    if (_startIpController.text != config.startIp) {
      _startIpController.text = config.startIp;
    }
    if (_subnetMaskController.text != config.subnetMask) {
      _subnetMaskController.text = config.subnetMask;
    }
    if (_gatewayController.text != config.gatewayIp) {
      _gatewayController.text = config.gatewayIp;
    }
    if (_dnsController.text != config.dnsServerIp) {
      _dnsController.text = config.dnsServerIp;
    }
  }

  void _applyConfig(NetworkServicesViewModel vm) {
    final startIp = _startIpController.text.trim();
    final poolSize = int.tryParse(_poolSizeController.text.trim()) ?? 20;
    final mask = _subnetMaskController.text.trim();
    final gateway = _gatewayController.text.trim();
    final dns = _dnsController.text.trim();
    final hours = int.tryParse(_leaseHoursController.text.trim()) ?? 24;

    final newConfig = DhcpConfig(
      startIp: startIp,
      poolSize: poolSize,
      subnetMask: mask,
      gatewayIp: gateway,
      dnsServerIp: dns,
      leaseTimeSeconds: hours * 3600,
    );

    vm.updateDhcpConfig(newConfig);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('DHCP Configuration updated'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NetworkServicesViewModel>();
    final isRunning = vm.dhcpStatus.isRunning;
    final config = vm.dhcpConfig;

    if (!isRunning) {
      _syncControllersWithVm(config);
    }

    return Column(
      children: [
        // Service Control Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Row(
            children: [
              Icon(Icons.router_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text(
                'DHCP Server',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              ServiceStatusBadge(status: vm.dhcpStatus),
              const Spacer(),
              PortInputField(
                controller: _portController,
                enabled: !isRunning,
                presets: const [67, 6767],
                onPortChanged: (port) => vm.setDhcpPort(port),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: () => vm.toggleDhcp(),
                style: FilledButton.styleFrom(
                  backgroundColor: isRunning ? Colors.red.shade700 : Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: Icon(isRunning ? Icons.stop : Icons.play_arrow, size: 16),
                label: Text(isRunning ? 'Stop DHCP' : 'Start DHCP'),
              ),
            ],
          ),
        ),
        const Divider(),

        // Configuration Inputs
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune, size: 16, color: Colors.grey),
                  SizedBox(width: 6),
                  Text(
                    'Pool & Network Settings',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Start IP
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _startIpController,
                      enabled: !isRunning,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'First Address (Start IP)',
                        helperText: 'Default: Host IP + 1',
                        helperStyle: TextStyle(fontSize: 10),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),

                  // Range Size
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _poolSizeController,
                      enabled: !isRunning,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'Range Size',
                        helperText: '# of addresses',
                        helperStyle: TextStyle(fontSize: 10),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),

                  // Auto-Calculated End Address Chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Calculated Last Address:',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          config.endIp,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Subnet Mask
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _subnetMaskController,
                      enabled: !isRunning,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'Subnet Mask',
                        helperText: 'Auto-detected',
                        helperStyle: TextStyle(fontSize: 10),
                      ),
                    ),
                  ),

                  // Default Gateway
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _gatewayController,
                      enabled: !isRunning,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'Default Gateway (Router)',
                        helperText: 'Host IP',
                        helperStyle: TextStyle(fontSize: 10),
                      ),
                    ),
                  ),

                  // DNS Server
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _dnsController,
                      enabled: !isRunning,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'DNS Server',
                        helperText: 'Host IP or 8.8.8.8',
                        helperStyle: TextStyle(fontSize: 10),
                      ),
                    ),
                  ),

                  // Lease Duration
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _leaseHoursController,
                      enabled: !isRunning,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'Lease (Hours)',
                        helperText: 'e.g. 24',
                        helperStyle: TextStyle(fontSize: 10),
                      ),
                    ),
                  ),

                  // Apply button
                  if (!isRunning)
                    ElevatedButton.icon(
                      onPressed: () => _applyConfig(vm),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Apply Changes'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Divider(),

        // Active Leases Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Row(
            children: [
              const Icon(Icons.devices, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                'Active DHCP Leases (${vm.dhcpLeases.length})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (vm.dhcpLeases.isNotEmpty)
                TextButton.icon(
                  onPressed: () => vm.clearDhcpLeases(),
                  icon: const Icon(Icons.clear_all, size: 14),
                  label: const Text('Clear Leases', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),

        // Leases Table
        Expanded(
          child: vm.dhcpLeases.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lan_outlined, size: 40, color: Colors.grey.shade700),
                      const SizedBox(height: 8),
                      Text(
                        isRunning
                            ? 'DHCP server running. Waiting for client discovery requests...'
                            : 'Start the DHCP server to begin leasing addresses.',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: vm.dhcpLeases.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final lease = vm.dhcpLeases[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.laptop_chromebook, size: 20),
                      title: Row(
                        children: [
                          Text(
                            lease.ipAddress,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            lease.hostname,
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        'MAC: ${lease.macAddress} • Expires in: ${lease.remainingDuration.inMinutes}m',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'ACTIVE',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
