import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/services/network/network_interface_service.dart';
import 'package:net_services/domain/models/network_interface_info.dart';

void main() {
  group('NetworkInterfaceService Tests', () {
    test('getAvailableInterfaces returns non-empty list with valid IP and subnet mask', () async {
      final service = NetworkInterfaceService();
      final interfaces = await service.getAvailableInterfaces();

      expect(interfaces, isNotEmpty);
      final first = interfaces.first;
      expect(first.name, isNotEmpty);
      expect(first.ip, isNotEmpty);
      expect(first.subnetMask, isNotEmpty);
      expect(first.prefixLength, inInclusiveRange(0, 32));
    });

    test('NetworkInterfaceInfo helper functions', () {
      const iface = NetworkInterfaceInfo(
        name: 'eth0',
        ip: '10.0.0.5',
        subnetMask: '255.255.255.0',
        prefixLength: 24,
        defaultGateway: '10.0.0.1',
      );

      expect(iface.hostIpPlusOne, equals('10.0.0.6'));
      expect(iface.broadcastAddress, equals('10.0.0.255'));
      expect(iface.toString(), contains('eth0'));
      expect(iface.toString(), contains('10.0.0.5'));
    });
  });
}
