import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/services/storage/settings_storage_service.dart';
import 'package:net_services/domain/models/dhcp_config.dart';
import 'package:net_services/domain/models/dhcp_lease.dart';
import 'package:net_services/domain/models/dhcp_static_reservation.dart';
import 'package:net_services/domain/models/dns_record.dart';

void main() {
  group('SettingsStorageService Tests', () {
    late Directory tempDir;
    late String customFilePath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('settings_storage_test_');
      customFilePath = '${tempDir.path}/test_settings.json';
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('In-memory mode saves and loads settings without touching disk', () async {
      final storage = SettingsStorageService(inMemory: true);
      expect(await storage.loadSettings(), isNull);

      final settings = AppPersistedSettings(
        dhcpPort: 6767,
        dnsPort: 5353,
        ntpPort: 1123,
        upstreamDnsIp: '1.1.1.1',
        selectedInterfaceName: 'eth0',
      );

      await storage.saveSettings(settings);
      final loaded = await storage.loadSettings();

      expect(loaded, isNotNull);
      expect(loaded!.dhcpPort, equals(6767));
      expect(loaded.dnsPort, equals(5353));
      expect(loaded.ntpPort, equals(1123));
      expect(loaded.upstreamDnsIp, equals('1.1.1.1'));
      expect(loaded.selectedInterfaceName, equals('eth0'));
    });

    test('Saves and loads settings to disk with atomic write and JSON serialization', () async {
      final storage = SettingsStorageService(customFilePath: customFilePath);
      expect(await storage.loadSettings(), isNull);

      final settings = AppPersistedSettings(
        dhcpPort: 6767,
        dnsPort: 5353,
        ntpPort: 1123,
        upstreamDnsIp: '8.8.8.8',
        selectedInterfaceName: 'wlan0',
        dhcpConfig: const DhcpConfig(
          startIp: '192.168.10.100',
          poolSize: 30,
          subnetMask: '255.255.255.0',
          gatewayIp: '192.168.10.1',
          dnsServerIp: '192.168.10.1',
          leaseTimeSeconds: 7200,
          useLocalDns: true,
          staticReservations: [
            DhcpStaticReservation(
              macAddress: 'AA:BB:CC:DD:EE:01',
              ipAddress: '192.168.10.50',
              deviceName: 'Server',
            ),
          ],
        ),
        dnsRecords: const [
          DnsRecord(domain: 'nas.local', ip: '192.168.10.50', ttl: 120),
          DnsRecord(domain: '*.lab.local', ip: '192.168.10.1', ttl: 300),
        ],
        activeLeases: [
          DhcpLease(
            macAddress: '11:22:33:44:55:66',
            ipAddress: '192.168.10.101',
            hostname: 'livingroom-tv',
            leaseStart: DateTime.now(),
            leaseDurationSeconds: 7200,
            friendlyName: 'Living Room TV',
          ),
        ],
      );

      await storage.saveSettings(settings);

      // Verify file exists on disk
      final file = File(customFilePath);
      expect(await file.exists(), isTrue);

      final loaded = await storage.loadSettings();
      expect(loaded, isNotNull);
      expect(loaded!.dhcpPort, equals(6767));
      expect(loaded.upstreamDnsIp, equals('8.8.8.8'));
      expect(loaded.selectedInterfaceName, equals('wlan0'));

      // Check DHCP Config
      expect(loaded.dhcpConfig, isNotNull);
      expect(loaded.dhcpConfig!.startIp, equals('192.168.10.100'));
      expect(loaded.dhcpConfig!.poolSize, equals(30));
      expect(loaded.dhcpConfig!.useLocalDns, isTrue);
      expect(loaded.dhcpConfig!.staticReservations.length, equals(1));
      expect(loaded.dhcpConfig!.staticReservations.first.deviceName, equals('Server'));

      // Check DNS Records
      expect(loaded.dnsRecords, isNotNull);
      expect(loaded.dnsRecords!.length, equals(2));
      expect(loaded.dnsRecords!.first.domain, equals('nas.local'));
      expect(loaded.dnsRecords!.last.domain, equals('*.lab.local'));

      // Check Active Leases
      expect(loaded.activeLeases, isNotNull);
      expect(loaded.activeLeases!.length, equals(1));
      expect(loaded.activeLeases!.first.hostname, equals('livingroom-tv'));
    });

    test('Backs up corrupt settings file as .corrupt.bak instead of crashing', () async {
      final file = File(customFilePath);
      await file.writeAsString('{ invalid_json: true, ...');

      final storage = SettingsStorageService(customFilePath: customFilePath);
      final result = await storage.loadSettings();
      expect(result, isNull);

      final corruptBak = File('$customFilePath.corrupt.bak');
      expect(await corruptBak.exists(), isTrue);
      expect(await corruptBak.readAsString(), contains('invalid_json'));
    });
  });
}
