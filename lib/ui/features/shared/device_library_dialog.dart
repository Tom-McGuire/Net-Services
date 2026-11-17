import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import '../../theme/app_theme.dart';

/// Modal dialog allowing users to browse, search, and manage devices
/// in the Shared Device Library across Network Suite applications.
class DeviceLibraryDialog extends StatefulWidget {
  const DeviceLibraryDialog({super.key});

  static Future<void> show(BuildContext context) async {
    try {
      if (!SharedDeviceDatabase.instance.isInitialized) {
        await SharedDeviceDatabase.instance.init();
      }
    } catch (e) {
      debugPrint('DeviceLibrary init warning: $e');
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => const DeviceLibraryDialog(),
    );
  }

  @override
  State<DeviceLibraryDialog> createState() => _DeviceLibraryDialogState();
}

class _DeviceLibraryDialogState extends State<DeviceLibraryDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<SharedDevice> _devices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    try {
      if (!SharedDeviceDatabase.instance.isInitialized) {
        await SharedDeviceDatabase.instance.init();
      }
      final all = SharedDeviceDatabase.instance.getAllDevices();
      if (mounted) {
        setState(() {
          _devices = all;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<SharedDevice> get _filteredDevices {
    if (_searchQuery.isEmpty) return _devices;
    final q = _searchQuery.toLowerCase();
    return _devices.where((d) {
      return d.name.toLowerCase().contains(q) ||
          d.macAddress.toLowerCase().contains(q) ||
          (d.vendor?.toLowerCase().contains(q) ?? false) ||
          (d.notes?.toLowerCase().contains(q) ?? false) ||
          (d.deviceType?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  InputDecoration _deviceFieldDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(fontSize: 11, color: AppTheme.textMuted),
      filled: true,
      fillColor: AppTheme.isDark ? AppTheme.surface : AppTheme.surfaceHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: AppTheme.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: AppTheme.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: AppTheme.accent, width: 1.5),
      ),
    );
  }

  void _showEditDeviceDialog({SharedDevice? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final macCtrl = TextEditingController(text: existing?.macAddress ?? '');
    final vendorCtrl = TextEditingController(text: existing?.vendor ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    String selectedCategory = existing?.deviceType ?? 'pc';

    final categories = DeviceCategory.values;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: AppTheme.border),
          ),
          title: Text(
            existing == null ? 'Add Device to Library' : 'Edit Device in Library',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MAC Address', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: macCtrl,
                    enabled: existing == null,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    decoration: _deviceFieldDecoration('AA:BB:CC:DD:EE:FF'),
                  ),
                  const SizedBox(height: 12),
                  Text('Friendly Name', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: _deviceFieldDecoration('e.g. Office Workstation'),
                  ),
                  const SizedBox(height: 12),
                  Text('Device Category', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.isDark ? AppTheme.surface : AppTheme.surfaceHigh,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.inputBorder),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: categories.any((c) => c.key == selectedCategory)
                            ? selectedCategory
                            : (categories.isNotEmpty ? categories.first.key : null),
                        dropdownColor: AppTheme.surfaceElevated,
                        isDense: true,
                        style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedCategory = val);
                          }
                        },
                        items: categories.map((c) {
                          return DropdownMenuItem<String>(
                            value: c.key,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(c.icon, size: 14, color: AppTheme.accent),
                                const SizedBox(width: 8),
                                Text(c.label),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Hardware Vendor', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: vendorCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: _deviceFieldDecoration('e.g. Apple, Dell, Intel'),
                  ),
                  const SizedBox(height: 12),
                  Text('Notes', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 12),
                    decoration: _deviceFieldDecoration('e.g. Server room rack unit 4'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: () {
                final rawMac = macCtrl.text.trim();
                final name = nameCtrl.text.trim();
                if (rawMac.isEmpty || name.isEmpty) return;

                final normMac = SharedDevice.normalizeMac(rawMac);
                final dev = SharedDevice(
                  macAddress: normMac,
                  name: name,
                  deviceType: selectedCategory,
                  vendor: vendorCtrl.text.trim().isNotEmpty ? vendorCtrl.text.trim() : null,
                  notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                  sourceApp: 'net_services',
                  createdAt: existing?.createdAt ?? DateTime.now(),
                  updatedAt: DateTime.now(),
                );

                try {
                  SharedDeviceDatabase.instance.upsertDevice(dev);
                  Navigator.of(ctx).pop();
                  _loadDevices();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save device: $e')),
                  );
                }
              },
              child: const Text('Save Device', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteDevice(SharedDevice device) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppTheme.border),
        ),
        title: Text('Delete Device', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text(
          'Remove "${device.name}" (${device.macAddress}) from the Shared Device Library?',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () {
              try {
                SharedDeviceDatabase.instance.deleteDevice(device.macAddress);
                Navigator.of(ctx).pop();
                _loadDevices();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete: $e')),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredDevices;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 660),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.devices, color: Theme.of(context).colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shared Device Library',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'Global device identity and classification database shared across the Network Suite.',
                          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Device', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () => _showEditDeviceDialog(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Search Bar
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontSize: 12),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search devices by name, MAC, vendor, or notes...',
                    hintStyle: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    prefixIcon: Icon(Icons.search, size: 16, color: AppTheme.textSecondary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 14),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppTheme.surfaceHigh,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.accent, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Devices List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.devices_other, size: 44, color: AppTheme.textMuted),
                                const SizedBox(height: 10),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'No matching devices found.'
                                      : 'No devices in the shared library yet.',
                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final dev = filtered[index];
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceHigh,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.inputBorder),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                      child: Icon(
                                        dev.category.icon,
                                        size: 16,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  dev.name,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: AppTheme.textPrimary,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.success.withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  dev.category.label,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: AppTheme.success,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${dev.macAddress} • ${dev.vendor ?? "Unknown Vendor"}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontFamily: 'monospace',
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                          if (dev.notes != null && dev.notes!.trim().isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              dev.notes!,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontStyle: FontStyle.italic,
                                                color: AppTheme.textSecondary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      tooltip: 'Edit Device',
                                      onPressed: () => _showEditDeviceDialog(existing: dev),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline, size: 18, color: AppTheme.textSecondary),
                                      tooltip: 'Delete Device',
                                      onPressed: () => _confirmDeleteDevice(dev),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
