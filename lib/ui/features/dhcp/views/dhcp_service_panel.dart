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
  late TextEditingController _endIpController;
  late TextEditingController _subnetMaskController;
  late TextEditingController _gatewayController;
  late TextEditingController _dnsController;
  late TextEditingController _leaseHoursController;
  bool _useLocalDns = false;

  @override
  void initState() {
    super.initState();
    final vm = context.read<NetworkServicesViewModel>();
    _portController = TextEditingController(text: vm.dhcpPort.toString());
    _startIpController = TextEditingController(text: vm.dhcpConfig.startIp);
    _poolSizeController = TextEditingController(text: vm.dhcpConfig.poolSize.toString());
    _endIpController = TextEditingController(text: vm.dhcpConfig.endIp);
    _subnetMaskController = TextEditingController(text: vm.dhcpConfig.subnetMask);
    _gatewayController = TextEditingController(text: vm.dhcpConfig.gatewayIp);
    _dnsController = TextEditingController(text: vm.dhcpConfig.dnsServerIp);
    _leaseHoursController = TextEditingController(
      text: (vm.dhcpConfig.leaseTimeSeconds ~/ 3600).toString(),
    );
    _useLocalDns = vm.dhcpConfig.useLocalDns;

    _startIpController.addListener(_recalculateEndIp);
    _poolSizeController.addListener(_recalculateEndIp);
  }

  void _recalculateEndIp() {
    final startIp = _startIpController.text.trim();
    final poolSize = int.tryParse(_poolSizeController.text.trim()) ?? 0;
    final startNum = DhcpConfig.ipToNum(startIp);
    if (startNum == 0 || poolSize <= 0) {
      if (_endIpController.text != startIp) {
        _endIpController.text = startIp;
      }
    } else {
      final computed = DhcpConfig.numToIp(startNum + poolSize - 1);
      if (_endIpController.text != computed) {
        _endIpController.text = computed;
      }
    }
  }

  @override
  void dispose() {
    _startIpController.removeListener(_recalculateEndIp);
    _poolSizeController.removeListener(_recalculateEndIp);
    _portController.dispose();
    _startIpController.dispose();
    _poolSizeController.dispose();
    _endIpController.dispose();
    _subnetMaskController.dispose();
    _gatewayController.dispose();
    _dnsController.dispose();
    _leaseHoursController.dispose();
    super.dispose();
  }

  void _syncControllersWithVm(DhcpConfig config, NetworkServicesViewModel vm) {
    if (_startIpController.text != config.startIp) {
      _startIpController.text = config.startIp;
    }
    if (_poolSizeController.text != config.poolSize.toString()) {
      _poolSizeController.text = config.poolSize.toString();
    }
    if (_endIpController.text != config.endIp) {
      _endIpController.text = config.endIp;
    }
    if (_subnetMaskController.text != config.subnetMask) {
      _subnetMaskController.text = config.subnetMask;
    }
    if (_gatewayController.text != config.gatewayIp) {
      _gatewayController.text = config.gatewayIp;
    }
    _useLocalDns = config.useLocalDns;
    final expectedDns = _useLocalDns ? (vm.selectedInterface?.ip ?? config.dnsServerIp) : config.dnsServerIp;
    if (_dnsController.text != expectedDns) {
      _dnsController.text = expectedDns;
    }
  }

  void _applyConfig(NetworkServicesViewModel vm) {
    final startIp = _startIpController.text.trim();
    final poolSize = int.tryParse(_poolSizeController.text.trim()) ?? 20;
    final mask = _subnetMaskController.text.trim();
    final gateway = _gatewayController.text.trim();
    final hostIp = vm.selectedInterface?.ip ?? '127.0.0.1';
    final dns = _useLocalDns ? hostIp : _dnsController.text.trim();
    final hours = int.tryParse(_leaseHoursController.text.trim()) ?? 24;

    final newConfig = DhcpConfig(
      startIp: startIp,
      poolSize: poolSize,
      subnetMask: mask,
      gatewayIp: gateway,
      dnsServerIp: dns,
      leaseTimeSeconds: hours * 3600,
      useLocalDns: _useLocalDns,
    );

    final errors = newConfig.validate();
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid DHCP configuration:\n• ${errors.join('\n• ')}'),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    vm.updateDhcpConfig(newConfig);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('DHCP Configuration updated'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _confirmAndToggleDhcp(NetworkServicesViewModel vm) async {
    if (vm.dhcpStatus.isRunning) {
      await vm.toggleDhcp();
      return;
    }

    final iface = vm.selectedInterface?.name ?? 'Default';
    final ip = vm.selectedInterface?.ip ?? '0.0.0.0';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber),
            SizedBox(width: 8),
            Text('DHCP Server Confirmation'),
          ],
        ),
        content: Text(
          'You are about to start a DHCP server on interface "$iface" ($ip).\n\n'
          'Running a DHCP server on an existing network with another DHCP server or router '
          'can cause IP conflicts and disconnect network clients.\n\n'
          '${_useLocalDns ? "DNS Option: Clients will receive this machine ($ip) as their DNS server to resolve local device names via the built-in DNS service.\n\n" : ""}'
          'Do you wish to start the DHCP server?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade800),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm & Start DHCP'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // If user enabled local DNS and DNS server isn't active, activate it as well
      if (_useLocalDns && !vm.dnsStatus.isRunning) {
        await vm.toggleDns();
      }
      await vm.toggleDhcp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NetworkServicesViewModel>();
    final isRunning = vm.dhcpStatus.isRunning;
    final config = vm.dhcpConfig;

    if (!isRunning) {
      _syncControllersWithVm(config, vm);
    }

    final hostIp = vm.selectedInterface?.ip ?? '127.0.0.1';

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
                onPressed: () => _confirmAndToggleDhcp(vm),
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
                    width: 140,
                    child: TextField(
                      controller: _startIpController,
                      enabled: !isRunning,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'Start IP',
                        isDense: true,
                      ),
                    ),
                  ),
                  // Pool Size
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _poolSizeController,
                      enabled: !isRunning,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'Pool Size',
                        isDense: true,
                      ),
                    ),
                  ),
                  // End IP (styled consistently with the other text boxes)
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _endIpController,
                      readOnly: true,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'End IP',
                        isDense: true,
                      ),
                    ),
                  ),
                  // Subnet Mask
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _subnetMaskController,
                      enabled: !isRunning,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'Subnet Mask',
                        isDense: true,
                      ),
                    ),
                  ),
                  // Gateway IP
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _gatewayController,
                      enabled: !isRunning,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'Default Gateway',
                        isDense: true,
                      ),
                    ),
                  ),
                  // DNS IP
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _dnsController,
                      enabled: !isRunning && !_useLocalDns,
                      readOnly: _useLocalDns,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        labelText: _useLocalDns ? 'DNS Server (This App)' : 'DNS Server',
                        isDense: true,
                      ),
                    ),
                  ),
                  // Lease Duration
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _leaseHoursController,
                      enabled: !isRunning,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: 'Lease (Hours)',
                        isDense: true,
                      ),
                    ),
                  ),
                  // Apply Button
                  FilledButton.icon(
                    onPressed: isRunning ? null : () => _applyConfig(vm),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Apply Changes'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Local DNS Server Option
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: isRunning
                    ? null
                    : () {
                        setState(() {
                          _useLocalDns = !_useLocalDns;
                          if (_useLocalDns) {
                            _dnsController.text = hostIp;
                          }
                        });
                        vm.setUseLocalDns(_useLocalDns);
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 20,
                        width: 20,
                        child: Checkbox(
                          value: _useLocalDns,
                          onChanged: isRunning
                              ? null
                              : (val) {
                                  setState(() {
                                    _useLocalDns = val ?? false;
                                    if (_useLocalDns) {
                                      _dnsController.text = hostIp;
                                    }
                                  });
                                  vm.setUseLocalDns(_useLocalDns);
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Hand out this machine\'s IP ($hostIp) as DNS server to resolve device names with the built-in DNS service',
                          style: TextStyle(
                            fontSize: 12,
                            color: isRunning ? Colors.grey : Colors.white70,
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
        const Divider(),

        // Active Leases Table Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Active Assigned Leases',
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
                      '${vm.dhcpLeases.length} / ${config.poolSize}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: vm.dhcpLeases.isEmpty ? null : () => vm.clearDhcpLeases(),
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Release All Leases'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
        ),

        // Leases List
        Expanded(
          child: vm.dhcpLeases.isEmpty
              ? const Center(
                  child: Text(
                    'No active DHCP leases assigned yet.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: vm.dhcpLeases.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final lease = vm.dhcpLeases[idx];
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
