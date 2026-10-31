import 'package:flutter/foundation.dart';
import 'package:network_suite_shared/network_suite_shared.dart';

/// Helper utility for interacting with the cross-process [SharedDeviceDatabase].
///
/// Ensures standalone resilience: all operations fail gracefully and safely
/// if the database is uninitialized or the launcher is not present.
class SharedDeviceHelper {
  /// Safely retrieves a registered [SharedDevice] by MAC address.
  /// Returns `null` if not found or if the shared database is uninitialized.
  static SharedDevice? getDevice(String mac) {
    try {
      if (SharedDeviceDatabase.instance.isInitialized) {
        final normalized = SharedDevice.normalizeMac(mac);
        return SharedDeviceDatabase.instance.getDeviceByMac(normalized);
      }
    } catch (e) {
      debugPrint('SharedDeviceHelper.getDevice error: $e');
    }
    return null;
  }

  /// Resolves the friendly display name for a given [mac].
  ///
  /// Priority:
  /// 1. Custom friendly name from [SharedDeviceDatabase].
  /// 2. Given [fallbackHostname] if not empty.
  /// 3. Hardware Vendor + last 3 bytes of MAC.
  /// 4. Normalized MAC address.
  static String getDisplayName(String mac, {String? fallbackHostname}) {
    final device = getDevice(mac);
    if (device != null && device.name.trim().isNotEmpty) {
      return device.name.trim();
    }

    if (fallbackHostname != null && fallbackHostname.trim().isNotEmpty && fallbackHostname != 'Unknown') {
      return fallbackHostname.trim();
    }

    final normalized = SharedDevice.normalizeMac(mac);
    try {
      final vendor = OuiLookup.lookupVendor(normalized);
      if (vendor != 'Unknown Vendor' &&
          vendor != 'Unknown Hardware' &&
          vendor != 'Randomized / Private MAC') {
        final suffix = normalized.length >= 17 ? normalized.substring(9) : normalized;
        return '$vendor ($suffix)';
      }
    } catch (_) {}

    return normalized;
  }

  /// Retrieves all devices stored in the shared database.
  static List<SharedDevice> getAllDevices({String? query, String? deviceType}) {
    try {
      if (SharedDeviceDatabase.instance.isInitialized) {
        return SharedDeviceDatabase.instance.getAllDevices(
          query: query,
          deviceType: deviceType,
        );
      }
    } catch (e) {
      debugPrint('SharedDeviceHelper.getAllDevices error: $e');
    }
    return const [];
  }

  /// Updates or sets a friendly name for a device in the shared database.
  static void updateDeviceName(String mac, String newName) {
    try {
      if (!SharedDeviceDatabase.instance.isInitialized) return;
      final normalized = SharedDevice.normalizeMac(mac);
      final existing = SharedDeviceDatabase.instance.getDeviceByMac(normalized);

      if (existing != null) {
        SharedDeviceDatabase.instance.updateDeviceName(normalized, newName.trim());
      } else {
        final vendor = OuiLookup.lookupVendor(normalized);
        final category = OuiLookup.inferCategory(vendor);
        final cleanVendor = (vendor != 'Unknown Vendor' && vendor != 'Unknown Hardware') ? vendor : null;

        SharedDeviceDatabase.instance.upsertDevice(SharedDevice(
          macAddress: normalized,
          name: newName.trim().isNotEmpty ? newName.trim() : 'Device $normalized',
          vendor: cleanVendor,
          deviceType: category.key,
          notes: 'Discovered by net-services',
          sourceApp: 'net-services',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('SharedDeviceHelper.updateDeviceName error: $e');
    }
  }

  /// Registers a newly discovered device in the shared database if not already present.
  static void registerDiscoveredDevice(
    String mac, {
    String? hostname,
    String? notes,
  }) {
    try {
      if (!SharedDeviceDatabase.instance.isInitialized) return;
      final normalized = SharedDevice.normalizeMac(mac);
      if (!SharedDevice.isValidMac(normalized)) return;

      final existing = SharedDeviceDatabase.instance.getDeviceByMac(normalized);
      if (existing != null) {
        // Already registered, preserve existing name
        return;
      }

      final vendor = OuiLookup.lookupVendor(normalized);
      final category = OuiLookup.inferCategory(vendor, hostname);
      final cleanVendor = (vendor != 'Unknown Vendor' && vendor != 'Unknown Hardware') ? vendor : null;

      final defaultName = (hostname != null && hostname.trim().isNotEmpty && hostname != 'Unknown')
          ? hostname.trim()
          : (cleanVendor != null ? '$cleanVendor (${normalized.length >= 17 ? normalized.substring(9) : normalized})' : 'Device $normalized');

      final device = SharedDevice(
        macAddress: normalized,
        name: defaultName,
        vendor: cleanVendor,
        deviceType: category.key,
        notes: notes ?? 'Discovered by net-services DHCP server',
        sourceApp: 'net-services',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      SharedDeviceDatabase.instance.upsertDevice(device);
    } catch (e) {
      debugPrint('SharedDeviceHelper.registerDiscoveredDevice error: $e');
    }
  }
}
