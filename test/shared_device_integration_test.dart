import 'package:flutter_test/flutter_test.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:net_services/data/services/device/mac_address_helper.dart';
import 'package:net_services/data/services/dhcp/dhcp_lease_manager.dart';
import 'package:net_services/domain/models/dhcp_config.dart';
import 'package:net_services/domain/models/dhcp_static_reservation.dart';
import 'package:net_services/domain/models/wol_device.dart';

void main() {
  group('Shared Device Library & Net-Services Integration Tests', () {
    setUp(() async {
      // Initialize an in-memory SharedDeviceDatabase for isolated testing
      await SharedDeviceDatabase.instance.init(dbPath: ':memory:');
    });

    tearDown(() {
      SharedDeviceDatabase.instance.close();
    });

    test('Resolves friendly device names from SharedDeviceDatabase', () {
      const mac = '00:11:22:33:44:55';
      final now = DateTime.now();

      SharedDeviceDatabase.instance.upsertDevice(
        SharedDevice(
          macAddress: mac,
          name: "Tom's Gaming Rig",
          vendor: 'ASUSTeK',
          deviceType: 'pc',
          sourceApp: 'net-services',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final device = SharedDeviceHelper.getDevice(mac);
      expect(device, isNotNull);
      expect(device!.name, equals("Tom's Gaming Rig"));
      expect(device.vendor, equals('ASUSTeK'));

      final displayName = SharedDeviceHelper.getDisplayName(mac, fallbackHostname: 'host-gaming');
      expect(displayName, equals("Tom's Gaming Rig"));
    });

    test('Falls back gracefully when device is not in database', () {
      const mac = 'AA:BB:CC:DD:EE:FF';
      final displayName = SharedDeviceHelper.getDisplayName(mac, fallbackHostname: 'my-laptop');
      expect(displayName, equals('my-laptop'));

      final withoutHostname = SharedDeviceHelper.getDisplayName(mac);
      expect(withoutHostname, isNotEmpty);
    });

    test('Updates friendly name and persists to database', () {
      const mac = '11:22:33:44:55:66';
      SharedDeviceHelper.updateDeviceName(mac, 'Living Room Apple TV');

      final device = SharedDeviceHelper.getDevice(mac);
      expect(device, isNotNull);
      expect(device!.name, equals('Living Room Apple TV'));

      // Update existing
      SharedDeviceHelper.updateDeviceName(mac, 'Basement Apple TV');
      final updated = SharedDeviceHelper.getDevice(mac);
      expect(updated!.name, equals('Basement Apple TV'));
    });

    test('Registers newly discovered device without overwriting existing friendly name', () {
      const mac = '22:33:44:55:66:77';
      SharedDeviceHelper.registerDiscoveredDevice(mac, hostname: 'Printer-Office');

      final device = SharedDeviceHelper.getDevice(mac);
      expect(device, isNotNull);
      expect(device!.name, equals('Printer-Office'));

      // Re-registering with different hostname should preserve user/existing name
      SharedDeviceHelper.registerDiscoveredDevice(mac, hostname: 'New-Hostname');
      final preserved = SharedDeviceHelper.getDevice(mac);
      expect(preserved!.name, equals('Printer-Office'));
    });

    test('DHCP Lease Manager allocates static reservations with friendly names', () {
      const config = DhcpConfig(
        startIp: '192.168.1.100',
        poolSize: 10,
        subnetMask: '255.255.255.0',
        gatewayIp: '192.168.1.1',
        dnsServerIp: '192.168.1.1',
        staticReservations: [
          DhcpStaticReservation(
            macAddress: 'AA:BB:CC:11:22:33',
            ipAddress: '192.168.1.50',
            deviceName: 'Core Switch',
          ),
          DhcpStaticReservation(
            macAddress: 'AA:BB:CC:44:55:66',
            ipAddress: '192.168.1.102',
            deviceName: 'NAS Storage',
          ),
        ],
      );

      final manager = DhcpLeaseManager(config: config);

      // Offer for static MAC returns reserved IP
      final offerIp = manager.reserveOrGetOffer('AA:BB:CC:11:22:33');
      expect(offerIp, equals('192.168.1.50'));

      // Confirm lease commits static lease
      final lease = manager.confirmLease('AA:BB:CC:11:22:33', requestedIp: '192.168.1.50');
      expect(lease, isNotNull);
      expect(lease!.ipAddress, equals('192.168.1.50'));
      expect(lease.isStatic, isTrue);
      expect(lease.friendlyName, equals('Core Switch'));

      // Dynamic client allocation skips statically reserved pool IP (192.168.1.102)
      final dyn1 = manager.allocateOrGetLease('00:00:00:00:00:01');
      expect(dyn1!.ipAddress, equals('192.168.1.100'));

      final dyn2 = manager.allocateOrGetLease('00:00:00:00:00:02');
      expect(dyn2!.ipAddress, equals('192.168.1.101'));

      // Next available should skip 192.168.1.102 (reserved for NAS Storage) and assign 103
      final dyn3 = manager.allocateOrGetLease('00:00:00:00:00:03');
      expect(dyn3!.ipAddress, equals('192.168.1.103'));

      // Static lease is not expired
      expect(lease.isExpired, isFalse);
    });

    test('WOL Device validation and Shared Device integration', () {
      const rawMac = 'aa-bb-cc-dd-ee-ff';
      final norm = SharedDevice.normalizeMac(rawMac);
      expect(norm, equals('AA:BB:CC:DD:EE:FF'));
      expect(WolDevice.isValidMac(norm), isTrue);

      SharedDeviceHelper.updateDeviceName(norm, 'Media Center');
      final device = SharedDeviceHelper.getDevice(norm);
      expect(device, isNotNull);
      expect(device!.name, equals('Media Center'));
    });
  });

  group('Standalone Resilience Tests (Uninitialized DB)', () {
    test('All helpers return safe fallbacks when DB is uninitialized', () {
      // SharedDeviceDatabase.instance is closed and uninitialized
      expect(SharedDeviceDatabase.instance.isInitialized, isFalse);

      final device = SharedDeviceHelper.getDevice('00:11:22:33:44:55');
      expect(device, isNull);

      final name = SharedDeviceHelper.getDisplayName('00:11:22:33:44:55', fallbackHostname: 'Desktop');
      expect(name, equals('Desktop'));

      final all = SharedDeviceHelper.getAllDevices();
      expect(all, isEmpty);

      // Should not throw
      SharedDeviceHelper.updateDeviceName('00:11:22:33:44:55', 'Test Name');
      SharedDeviceHelper.registerDiscoveredDevice('00:11:22:33:44:55');
    });
  });
}
