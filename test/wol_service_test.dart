import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/services/wol/wol_service.dart';
import 'package:net_services/data/services/wol/wol_storage_service.dart';
import 'package:net_services/domain/models/wol_device.dart';

void main() {
  group('WolDevice Model Tests', () {
    test('Validates and normalizes various MAC address formats', () {
      expect(WolDevice.isValidMac('AA:BB:CC:DD:EE:FF'), isTrue);
      expect(WolDevice.isValidMac('aa-bb-cc-dd-ee-ff'), isTrue);
      expect(WolDevice.isValidMac('aabb.ccdd.eeff'), isTrue);
      expect(WolDevice.isValidMac('001122334455'), isTrue);

      expect(WolDevice.normalizeMac('aa:bb:cc:dd:ee:ff'), equals('AA:BB:CC:DD:EE:FF'));
      expect(WolDevice.normalizeMac('00-11-22-33-44-55'), equals('00:11:22:33:44:55'));
      expect(WolDevice.normalizeMac('aabb.ccdd.eeff'), equals('AA:BB:CC:DD:EE:FF'));

      expect(WolDevice.isValidMac('invalid-mac'), isFalse);
      expect(WolDevice.isValidMac('00:11:22:33:44'), isFalse); // only 5 octets
      expect(WolDevice.isValidMac('00:11:22:33:44:55:66'), isFalse); // 7 octets
      expect(WolDevice.normalizeMac('XYZ'), isNull);
    });

    test('Serializes to and from JSON correctly', () {
      final now = DateTime.now();
      final device = WolDevice(
        id: 'dev_1',
        name: 'Office Desktop',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        ipAddress: '192.168.1.100',
        port: 9,
        broadcastAddress: '255.255.255.255',
        lastWoken: now,
      );

      final json = device.toJson();
      final deserialized = WolDevice.fromJson(json);

      expect(deserialized.id, equals('dev_1'));
      expect(deserialized.name, equals('Office Desktop'));
      expect(deserialized.macAddress, equals('AA:BB:CC:DD:EE:FF'));
      expect(deserialized.ipAddress, equals('192.168.1.100'));
      expect(deserialized.port, equals(9));
      expect(deserialized.broadcastAddress, equals('255.255.255.255'));
      expect(deserialized.lastWoken?.millisecondsSinceEpoch, equals(now.millisecondsSinceEpoch));
    });
  });

  group('WolService Tests', () {
    test('Constructs valid 102-byte Magic Packet', () {
      final packet = WolService.buildMagicPacket('00:11:22:33:44:55');

      expect(packet, isNotNull);
      expect(packet!.length, equals(102));

      // First 6 bytes must be 0xFF
      for (int i = 0; i < 6; i++) {
        expect(packet[i], equals(0xFF));
      }

      // Remaining 96 bytes must be 16 repetitions of 00:11:22:33:44:55
      final expectedMacBytes = [0x00, 0x11, 0x22, 0x33, 0x44, 0x55];
      for (int rep = 0; rep < 16; rep++) {
        final offset = 6 + (rep * 6);
        for (int octet = 0; octet < 6; octet++) {
          expect(packet[offset + octet], equals(expectedMacBytes[octet]));
        }
      }
    });

    test('Returns null for invalid MAC address in buildMagicPacket', () {
      expect(WolService.buildMagicPacket('not-a-mac'), isNull);
      expect(WolService.buildMagicPacket(''), isNull);
    });
  });

  group('WolStorageService Tests', () {
    test('Saves and loads devices from custom storage path', () async {
      final tempDir = Directory.systemTemp.createTempSync('wol_test_');
      final testFile = File('${tempDir.path}/test_wol.json');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final storage = WolStorageService(customFilePath: testFile.path);

      // Initially empty
      final initial = await storage.loadDevices();
      expect(initial, isEmpty);

      // Save devices
      final devices = [
        const WolDevice(
          id: '1',
          name: 'Device A',
          macAddress: '11:22:33:44:55:66',
          ipAddress: '192.168.1.10',
        ),
        const WolDevice(
          id: '2',
          name: 'Device B',
          macAddress: 'AA:BB:CC:DD:EE:FF',
          port: 7,
        ),
      ];

      await storage.saveDevices(devices);
      expect(testFile.existsSync(), isTrue);

      // Load back
      final loaded = await storage.loadDevices();
      expect(loaded.length, equals(2));
      expect(loaded[0].name, equals('Device A'));
      expect(loaded[0].macAddress, equals('11:22:33:44:55:66'));
      expect(loaded[1].name, equals('Device B'));
      expect(loaded[1].port, equals(7));
    });
  });
}
