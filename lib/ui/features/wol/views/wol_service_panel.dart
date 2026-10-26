import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/wol_device.dart';
import '../../dashboard/view_models/network_services_view_model.dart';

class WakeOnLanPanel extends StatefulWidget {
  const WakeOnLanPanel({super.key});

  @override
  State<WakeOnLanPanel> createState() => _WakeOnLanPanelState();
}

class _WakeOnLanPanelState extends State<WakeOnLanPanel> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _wakingDeviceIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleWakeDevice(WolDevice device, NetworkServicesViewModel vm) async {
    setState(() => _wakingDeviceIds.add(device.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final success = await vm.wakeDevice(device);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  success ? Icons.check_circle : Icons.error_outline,
                  color: success ? Colors.greenAccent : Colors.redAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  success
                      ? 'Magic packet sent to "${device.name}" (${device.macAddress})'
                      : 'Failed to send packet to "${device.name}"',
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF2D2D30),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _wakingDeviceIds.remove(device.id));
      }
    }
  }

  void _showDeviceDialog([WolDevice? existingDevice]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _WolDeviceDialog(device: existingDevice),
    );
  }

  Future<void> _confirmDeleteDevice(WolDevice device, NetworkServicesViewModel vm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete WOL Device'),
        content: Text('Are you sure you want to remove "${device.name}" (${device.macAddress})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await vm.deleteWolDevice(device.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed "${device.name}"')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NetworkServicesViewModel>();
    final devices = vm.wolDevices;
    final query = _searchController.text.trim().toLowerCase();

    final filteredDevices = devices.where((d) {
      if (query.isEmpty) return true;
      return d.name.toLowerCase().contains(query) ||
          d.macAddress.toLowerCase().contains(query) ||
          (d.ipAddress != null && d.ipAddress!.toLowerCase().contains(query));
    }).toList();

    return Column(
      children: [
        // Top Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Row(
            children: [
              Icon(Icons.power_settings_new, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text(
                'Wake-on-LAN (WOL)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${devices.length} ${devices.length == 1 ? 'Device' : 'Devices'}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
              const SizedBox(width: 16),
              // Search input
              SizedBox(
                width: 240,
                height: 36,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Search by name, MAC, or IP...',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 14),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showDeviceDialog(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Device'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Device List / Empty State
        Expanded(
          child: devices.isEmpty
              ? _buildEmptyState()
              : filteredDevices.isEmpty
                  ? Center(
                      child: Text(
                        'No devices match "$query"',
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 420,
                          mainAxisExtent: 215,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: filteredDevices.length,
                        itemBuilder: (context, index) {
                          final device = filteredDevices[index];
                          final isWaking = _wakingDeviceIds.contains(device.id);
                          return _buildDeviceCard(device, isWaking, vm);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.power_settings_new, size: 64, color: Colors.grey.shade600),
          const SizedBox(height: 16),
          const Text(
            'No Wake-on-LAN Devices Configured',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const SizedBox(
            width: 480,
            child: Text(
              'Add local network devices to wake them remotely using standard Magic Packets. You can enter a MAC address manually or resolve it automatically from an active IP address.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _showDeviceDialog(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Your First Device'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(WolDevice device, bool isWaking, NetworkServicesViewModel vm) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final lastWokenStr = device.lastWoken != null ? dateFormat.format(device.lastWoken!) : 'Never';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Icon + Name + Popup Menu
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.desktop_windows_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    device.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  tooltip: 'Edit Device',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showDeviceDialog(device),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                  tooltip: 'Delete Device',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmDeleteDevice(device, vm),
                ),
              ],
            ),
            const Divider(height: 16),

            // Device Details
            Row(
              children: [
                const Text('MAC: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Expanded(
                  child: SelectableText(
                    device.macAddress,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.lightBlueAccent,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 13),
                  tooltip: 'Copy MAC',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: device.macAddress));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('MAC copied to clipboard'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('IP: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text(
                  device.ipAddress ?? 'None (Broadcast only)',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
                const Spacer(),
                const Text('Port: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text('${device.port}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('Last Woken: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text(
                  lastWokenStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: device.lastWoken != null ? Colors.white70 : Colors.grey,
                  ),
                ),
              ],
            ),
            const Spacer(),

            // Action Button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isWaking ? null : () => _handleWakeDevice(device, vm),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0E639C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: isWaking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.power_settings_new, size: 16),
                label: Text(isWaking ? 'Sending Magic Packet...' : 'Wake Device'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WolDeviceDialog extends StatefulWidget {
  final WolDevice? device;

  const _WolDeviceDialog({this.device});

  @override
  State<_WolDeviceDialog> createState() => _WolDeviceDialogState();
}

class _WolDeviceDialogState extends State<_WolDeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _macController;
  late TextEditingController _ipController;
  late TextEditingController _portController;
  late TextEditingController _broadcastController;

  bool _isResolving = false;
  String? _resolveStatusMessage;
  bool _resolveSuccess = false;

  @override
  void initState() {
    super.initState();
    final d = widget.device;
    _nameController = TextEditingController(text: d?.name ?? '');
    _macController = TextEditingController(text: d?.macAddress ?? '');
    _ipController = TextEditingController(text: d?.ipAddress ?? '');
    _portController = TextEditingController(text: (d?.port ?? 9).toString());
    _broadcastController = TextEditingController(text: d?.broadcastAddress ?? '255.255.255.255');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _macController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _broadcastController.dispose();
    super.dispose();
  }

  Future<void> _handleResolveMac() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _resolveStatusMessage = 'Please enter an IP address to resolve.';
        _resolveSuccess = false;
      });
      return;
    }

    final parsedIp = InternetAddress.tryParse(ip);
    if (parsedIp == null || parsedIp.type != InternetAddressType.IPv4) {
      setState(() {
        _resolveStatusMessage = 'Enter a valid IPv4 address (e.g. 192.168.1.50)';
        _resolveSuccess = false;
      });
      return;
    }

    setState(() {
      _isResolving = true;
      _resolveStatusMessage = null;
    });

    final vm = context.read<NetworkServicesViewModel>();
    final mac = await vm.resolveMacFromIp(ip);

    if (!mounted) return;

    if (mac != null) {
      setState(() {
        _macController.text = mac;
        _isResolving = false;
        _resolveSuccess = true;
        _resolveStatusMessage = 'Resolved MAC: $mac';
      });
    } else {
      setState(() {
        _isResolving = false;
        _resolveSuccess = false;
        _resolveStatusMessage = 'Could not find MAC for $ip. Ensure the host is powered on and reachable.';
      });
    }
  }

  void _handleSave() {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final rawMac = _macController.text.trim();
    final ip = _ipController.text.trim().isEmpty ? null : _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 9;
    final broadcast = _broadcastController.text.trim().isEmpty
        ? '255.255.255.255'
        : _broadcastController.text.trim();

    final normalizedMac = WolDevice.normalizeMac(rawMac);
    if (normalizedMac == null) return;

    final vm = context.read<NetworkServicesViewModel>();
    if (widget.device != null) {
      final updated = widget.device!.copyWith(
        name: name,
        macAddress: normalizedMac,
        ipAddress: ip,
        port: port,
        broadcastAddress: broadcast,
      );
      vm.updateWolDevice(updated);
    } else {
      final newDevice = WolDevice(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        macAddress: normalizedMac,
        ipAddress: ip,
        port: port,
        broadcastAddress: broadcast,
      );
      vm.addWolDevice(newDevice);
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.device != null;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.power_settings_new, color: Theme.of(context).colorScheme.primary, size: 22),
          const SizedBox(width: 10),
          Text(isEditing ? 'Edit Wake-on-LAN Device' : 'Add Wake-on-LAN Device'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Device Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Device Name *',
                    hintText: 'e.g. Media Server, Desktop PC, Lab Host',
                    prefixIcon: Icon(Icons.label_outline, size: 18),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please provide a device name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // IP Address and Auto-Resolve MAC section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.network_check, size: 16, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 6),
                          const Text(
                            'Network IP & MAC Resolver (Optional)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Enter an IP of an online machine to automatically retrieve its MAC address via ARP.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _ipController,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                              decoration: const InputDecoration(
                                labelText: 'IP Address',
                                hintText: '192.168.1.100',
                                isDense: true,
                              ),
                              validator: (val) {
                                if (val != null && val.trim().isNotEmpty) {
                                  final addr = InternetAddress.tryParse(val.trim());
                                  if (addr == null || addr.type != InternetAddressType.IPv4) {
                                    return 'Invalid IPv4 address';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonalIcon(
                            onPressed: _isResolving ? null : _handleResolveMac,
                            icon: _isResolving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.sync, size: 16),
                            label: Text(_isResolving ? 'Resolving...' : 'Resolve MAC'),
                          ),
                        ],
                      ),
                      if (_resolveStatusMessage != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              _resolveSuccess ? Icons.check_circle : Icons.warning_amber_rounded,
                              size: 14,
                              color: _resolveSuccess ? Colors.green : Colors.amber,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _resolveStatusMessage!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _resolveSuccess ? Colors.green : Colors.amber,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // MAC Address (Manual or Resolved)
                TextFormField(
                  controller: _macController,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    labelText: 'MAC Address *',
                    hintText: 'AA:BB:CC:DD:EE:FF',
                    helperText: 'Standard formats accepted: AA:BB:CC:DD:EE:FF or AA-BB-CC-DD-EE-FF',
                    prefixIcon: Icon(Icons.fingerprint, size: 18),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a MAC address';
                    }
                    if (!WolDevice.isValidMac(val.trim())) {
                      return 'Invalid MAC address format (must be 12 hex digits)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Port & Broadcast Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _portController,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'WOL Port',
                          hintText: '9',
                          helperText: 'Default: 9 (or 7)',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (val) {
                          final p = int.tryParse(val ?? '');
                          if (p == null || p < 1 || p > 65535) {
                            return 'Port 1-65535';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _broadcastController,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'Broadcast Address',
                          hintText: '255.255.255.255',
                          helperText: 'Subnet or 255.255.255.255',
                        ),
                        validator: (val) {
                          if (val != null && val.trim().isNotEmpty) {
                            final addr = InternetAddress.tryParse(val.trim());
                            if (addr == null || addr.type != InternetAddressType.IPv4) {
                              return 'Invalid broadcast IP';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
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
          child: Text(isEditing ? 'Save Changes' : 'Add Device'),
        ),
      ],
    );
  }
}
