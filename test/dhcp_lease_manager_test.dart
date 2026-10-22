import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/services/dhcp/dhcp_lease_manager.dart';
import 'package:net_services/domain/models/dhcp_config.dart';
import 'package:net_services/domain/models/network_interface_info.dart';

void main() {
  group('DHCP Configuration & Lease Manager Tests', () {
    test('Calculates Host IP + 1 correctly', () {
      const iface = NetworkInterfaceInfo(
        name: 'enp1s0',
        ip: '10.101.1.50',
        subnetMask: '255.255.255.0',
        prefixLength: 24,
      );
      expect(iface.hostIpPlusOne, equals('10.101.1.51'));

      const ifaceBoundary = NetworkInterfaceInfo(
        name: 'en0',
        ip: '192.168.1.254',
        subnetMask: '255.255.255.0',
        prefixLength: 24,
      );
      expect(ifaceBoundary.hostIpPlusOne, equals('192.168.1.255'));
    });

    test('Converts CIDR prefix to subnet mask correctly', () {
      expect(NetworkInterfaceInfo.prefixToSubnetMask(24), equals('255.255.255.0'));
      expect(NetworkInterfaceInfo.prefixToSubnetMask(16), equals('255.255.0.0'));
      expect(NetworkInterfaceInfo.prefixToSubnetMask(8), equals('255.0.0.0'));
      expect(NetworkInterfaceInfo.prefixToSubnetMask(28), equals('255.255.255.240'));
    });

    test('Calculates End IP dynamically from Start IP and Pool Size', () {
      const config = DhcpConfig(
        startIp: '10.101.1.51',
        poolSize: 20,
        subnetMask: '255.255.255.0',
        gatewayIp: '10.101.1.50',
        dnsServerIp: '10.101.1.50',
      );
      // 51 + 20 - 1 = 70
      expect(config.endIp, equals('10.101.1.70'));
    });

    test('Allocates sequential leases and handles pool exhaustion', () {
      const config = DhcpConfig(
        startIp: '192.168.1.100',
        poolSize: 3, // only 100, 101, 102
        subnetMask: '255.255.255.0',
        gatewayIp: '192.168.1.1',
        dnsServerIp: '192.168.1.1',
      );

      final manager = DhcpLeaseManager(config: config);

      // Lease 1
      final lease1 = manager.allocateOrGetLease('AA:BB:CC:DD:EE:01', hostname: 'device1');
      expect(lease1, isNotNull);
      expect(lease1!.ipAddress, equals('192.168.1.100'));

      // Lease 2
      final lease2 = manager.allocateOrGetLease('AA:BB:CC:DD:EE:02', hostname: 'device2');
      expect(lease2, isNotNull);
      expect(lease2!.ipAddress, equals('192.168.1.101'));

      // Renewal for Lease 1
      final renewed = manager.allocateOrGetLease('AA:BB:CC:DD:EE:01');
      expect(renewed!.ipAddress, equals('192.168.1.100'));
      expect(manager.activeLeases.length, equals(2));

      // Lease 3
      final lease3 = manager.allocateOrGetLease('AA:BB:CC:DD:EE:03', hostname: 'device3');
      expect(lease3, isNotNull);
      expect(lease3!.ipAddress, equals('192.168.1.102'));

      // Attempt Lease 4 (Pool exhausted)
      final lease4 = manager.allocateOrGetLease('AA:BB:CC:DD:EE:04');
      expect(lease4, isNull);

      // Release Lease 2
      manager.releaseLease('AA:BB:CC:DD:EE:02');
      expect(manager.activeLeases.length, equals(2));

      // Now Lease 4 can take the freed IP (192.168.1.101)
      final lease4Retry = manager.allocateOrGetLease('AA:BB:CC:DD:EE:04');
      expect(lease4Retry, isNotNull);
      expect(lease4Retry!.ipAddress, equals('192.168.1.101'));
    });
  });
}
