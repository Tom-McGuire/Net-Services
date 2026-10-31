import 'dart:io';
import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import '../../../../data/services/device/mac_address_helper.dart';
import '../../../../domain/models/dhcp_config.dart';
import '../../../../domain/models/dhcp_static_reservation.dart';
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

        // Sub-tabs: Active Leases vs Static Reservations
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Container(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: Row(
                    children: [
                      TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        labelColor: Theme.of(context).colorScheme.primary,
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: Theme.of(context).colorScheme.primary,
                        tabs: [
                          Tab(
                            child: Row(
                              children: [
                                const Icon(Icons.devices, size: 16),
                                const SizedBox(width: 8),
                                Text('Active Leases (${vm.dhcpLeases.length})'),
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              children: [
                                const Icon(Icons.bookmark_border, size: 16),
                                const SizedBox(width: 8),
                                Text('Static Reservations (${config.staticReservations.length})'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildActiveLeasesView(context, vm, config),
                      _buildStaticReservationsView(context, vm, config),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveLeasesView(BuildContext context, NetworkServicesViewModel vm, DhcpConfig config) {
    return Column(
      children: [
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
                    final sharedDevice = SharedDeviceHelper.getDevice(lease.macAddress);
                    final friendlyName = sharedDevice?.name.trim().isNotEmpty == true
                        ? sharedDevice!.name.trim()
                        : (lease.friendlyName?.trim().isNotEmpty == true
                            ? lease.friendlyName!.trim()
                            : (lease.hostname.isNotEmpty && lease.hostname != 'Unknown'
                                ? lease.hostname
                                : 'Device ${lease.macAddress}'));
                    final vendor = sharedDevice?.vendor ?? OuiLookup.lookupVendor(lease.macAddress);
                    final cleanVendor = (vendor != 'Unknown Vendor' && vendor != 'Unknown Hardware') ? vendor : null;
                    final category = sharedDevice?.category ?? OuiLookup.inferCategory(cleanVendor);

                    return ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(category.icon, size: 20, color: Theme.of(context).colorScheme.primary),
                      ),
                      title: Row(
                        children: [
                          Text(
                            lease.ipAddress,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.lightBlueAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              friendlyName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (lease.hostname.isNotEmpty &&
                              lease.hostname != 'Unknown' &&
                              lease.hostname != friendlyName) ...[
                            const SizedBox(width: 8),
                            Text(
                              '(${lease.hostname})',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        'MAC: ${lease.macAddress}${cleanVendor != null ? ' • $cleanVendor' : ''} • '
                        '${lease.isStatic ? "Permanent (Static)" : "Expires: ${lease.remainingDuration.inMinutes}m"}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: lease.isStatic
                                  ? Colors.blue.withValues(alpha: 0.15)
                                  : Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: lease.isStatic
                                    ? Colors.blue.withValues(alpha: 0.3)
                                    : Colors.green.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              lease.isStatic ? 'STATIC' : 'ACTIVE',
                              style: TextStyle(
                                color: lease.isStatic ? Colors.lightBlueAccent : Colors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            tooltip: 'Rename Device in Suite',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _showRenameDialog(context, lease.macAddress, friendlyName, vm),
                          ),
                          if (!lease.isStatic)
                            IconButton(
                              icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                              tooltip: 'Set Static Reservation',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _showStaticReservationDialog(
                                context,
                                vm,
                                initialMac: lease.macAddress,
                                initialIp: lease.ipAddress,
                                initialName: friendlyName,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStaticReservationsView(BuildContext context, NetworkServicesViewModel vm, DhcpConfig config) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Configured Static IP Reservations',
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
                      '${config.staticReservations.length}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: () => _showStaticReservationDialog(context, vm),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Reservation'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: config.staticReservations.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bookmark_border, size: 40, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'No static IP reservations configured.',
                        style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Assign fixed IP addresses to network devices using friendly name auto-completion.',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: config.staticReservations.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final res = config.staticReservations[idx];
                    final sharedDevice = SharedDeviceHelper.getDevice(res.macAddress);
                    final friendlyName = res.deviceName?.trim().isNotEmpty == true
                        ? res.deviceName!.trim()
                        : (sharedDevice?.name.trim().isNotEmpty == true
                            ? sharedDevice!.name.trim()
                            : 'Device ${res.macAddress}');
                    final vendor = sharedDevice?.vendor ?? OuiLookup.lookupVendor(res.macAddress);
                    final cleanVendor = (vendor != 'Unknown Vendor' && vendor != 'Unknown Hardware') ? vendor : null;
                    final category = sharedDevice?.category ?? OuiLookup.inferCategory(cleanVendor);

                    return ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(category.icon, size: 20, color: Theme.of(context).colorScheme.primary),
                      ),
                      title: Row(
                        children: [
                          Text(
                            res.ipAddress,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.lightBlueAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              friendlyName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        'MAC: ${res.macAddress}${cleanVendor != null ? ' • $cleanVendor' : ''}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            tooltip: 'Edit Reservation',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _showStaticReservationDialog(
                              context,
                              vm,
                              reservation: res,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                            tooltip: 'Delete Reservation',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => vm.removeStaticReservation(res.macAddress),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showRenameDialog(BuildContext context, String mac, String currentName, NetworkServicesViewModel vm) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit_note, size: 22, color: Colors.lightBlueAccent),
            SizedBox(width: 8),
            Text('Rename Device in Suite'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MAC Address: $mac', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Friendly Device Name',
                hintText: 'e.g. Living Room Apple TV, Office Desktop',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                vm.updateSharedDeviceName(mac, newName);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Updated device name to "$newName" in Network Suite'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save Name'),
          ),
        ],
      ),
    );
  }

  void _showStaticReservationDialog(
    BuildContext context,
    NetworkServicesViewModel vm, {
    DhcpStaticReservation? reservation,
    String? initialMac,
    String? initialIp,
    String? initialName,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _StaticReservationDialog(
        reservation: reservation,
        initialMac: initialMac,
        initialIp: initialIp,
        initialName: initialName,
        onSave: (res) {
          vm.addStaticReservation(res);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved static reservation for ${res.ipAddress} (${res.deviceName ?? res.macAddress})'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }
}

class _StaticReservationDialog extends StatefulWidget {
  final DhcpStaticReservation? reservation;
  final String? initialMac;
  final String? initialIp;
  final String? initialName;
  final void Function(DhcpStaticReservation reservation) onSave;

  const _StaticReservationDialog({
    this.reservation,
    this.initialMac,
    this.initialIp,
    this.initialName,
    required this.onSave,
  });

  @override
  State<_StaticReservationDialog> createState() => _StaticReservationDialogState();
}

class _StaticReservationDialogState extends State<_StaticReservationDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _macController;
  late TextEditingController _ipController;
  SharedDevice? _matchedSharedDevice;

  @override
  void initState() {
    super.initState();
    final r = widget.reservation;
    _nameController = TextEditingController(text: r?.deviceName ?? widget.initialName ?? '');
    _macController = TextEditingController(text: r?.macAddress ?? widget.initialMac ?? '');
    _ipController = TextEditingController(text: r?.ipAddress ?? widget.initialIp ?? '');

    _macController.addListener(_checkMacMatch);
    if (_macController.text.isNotEmpty) {
      _checkMacMatch();
    }
  }

  void _checkMacMatch() {
    final raw = _macController.text.trim();
    final norm = SharedDevice.normalizeMac(raw);
    if (SharedDevice.isValidMac(norm)) {
      final device = SharedDeviceHelper.getDevice(norm);
      if (mounted && device != _matchedSharedDevice) {
        setState(() {
          _matchedSharedDevice = device;
          if (device != null && _nameController.text.trim().isEmpty) {
            _nameController.text = device.name;
          }
        });
      }
    } else if (_matchedSharedDevice != null) {
      setState(() {
        _matchedSharedDevice = null;
      });
    }
  }

  @override
  void dispose() {
    _macController.removeListener(_checkMacMatch);
    _nameController.dispose();
    _macController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (!_formKey.currentState!.validate()) return;
    final mac = SharedDevice.normalizeMac(_macController.text.trim());
    final ip = _ipController.text.trim();
    final name = _nameController.text.trim();

    widget.onSave(DhcpStaticReservation(
      macAddress: mac,
      ipAddress: ip,
      deviceName: name.isNotEmpty ? name : null,
    ));

    // Also persist name into shared database if specified
    if (name.isNotEmpty) {
      SharedDeviceHelper.updateDeviceName(mac, name);
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.reservation != null;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.bookmark_border, color: Theme.of(context).colorScheme.primary, size: 22),
          const SizedBox(width: 10),
          Text(isEditing ? 'Edit Static Reservation' : 'Add Static Reservation'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Friendly Name Autocomplete
                const Text(
                  'Device Name (Auto-complete from Shared Devices):',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Autocomplete<SharedDevice>(
                  displayStringForOption: (device) => device.name,
                  initialValue: TextEditingValue(text: _nameController.text),
                  optionsBuilder: (textEditingValue) {
                    final allDevices = SharedDeviceHelper.getAllDevices();
                    if (textEditingValue.text.isEmpty) {
                      return allDevices;
                    }
                    final query = textEditingValue.text.toLowerCase();
                    return allDevices.where((d) =>
                        d.name.toLowerCase().contains(query) ||
                        d.macAddress.toLowerCase().contains(query) ||
                        (d.vendor?.toLowerCase().contains(query) ?? false));
                  },
                  onSelected: (device) {
                    setState(() {
                      _nameController.text = device.name;
                      _macController.text = device.macAddress;
                      _matchedSharedDevice = device;
                    });
                  },
                  fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                    // Keep _nameController synced
                    textEditingController.addListener(() {
                      _nameController.text = textEditingController.text;
                    });
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Friendly Device Name',
                        hintText: 'e.g. Living Room Apple TV, Core Switch',
                        prefixIcon: Icon(Icons.label_outline, size: 18),
                        isDense: true,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // MAC Address Field
                TextFormField(
                  controller: _macController,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    labelText: 'MAC Address *',
                    hintText: 'AA:BB:CC:DD:EE:FF',
                    prefixIcon: Icon(Icons.fingerprint, size: 18),
                    helperText: 'Standard format: AA:BB:CC:DD:EE:FF',
                    isDense: true,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please provide a MAC address';
                    }
                    final norm = SharedDevice.normalizeMac(val.trim());
                    if (!SharedDevice.isValidMac(norm)) {
                      return 'Invalid MAC address format';
                    }
                    return null;
                  },
                ),

                // Matched Shared Device Banner
                if (_matchedSharedDevice != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified, size: 16, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Known Suite Device: "${_matchedSharedDevice!.name}"${_matchedSharedDevice!.vendor != null ? " (${_matchedSharedDevice!.vendor})" : ""}',
                            style: const TextStyle(fontSize: 12, color: Colors.lightBlueAccent, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Reserved IP Field
                TextFormField(
                  controller: _ipController,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Reserved Static IP *',
                    hintText: 'e.g. 192.168.1.50',
                    prefixIcon: Icon(Icons.lan_outlined, size: 18),
                    isDense: true,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please provide a static IP address';
                    }
                    final parsed = InternetAddress.tryParse(val.trim());
                    if (parsed == null || parsed.type != InternetAddressType.IPv4) {
                      return 'Invalid IPv4 address';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _handleSave,
          child: Text(isEditing ? 'Save Changes' : 'Add Reservation'),
        ),
      ],
    );
  }
}
