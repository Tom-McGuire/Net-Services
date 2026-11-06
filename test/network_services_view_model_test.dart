import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/repositories/network_services_repository.dart';
import 'package:net_services/data/services/storage/settings_storage_service.dart';
import 'package:net_services/data/services/wol/wol_storage_service.dart';
import 'package:net_services/domain/models/dhcp_static_reservation.dart';
import 'package:net_services/domain/models/dns_record.dart';
import 'package:net_services/domain/models/network_interface_info.dart';
import 'package:net_services/domain/models/service_log_record.dart';
import 'package:net_services/domain/models/service_status.dart';
import 'package:net_services/ui/features/dashboard/view_models/network_services_view_model.dart';

void main() {
  group('NetworkServicesViewModel Tests', () {
    late NetworkServicesRepository repository;
    late NetworkServicesViewModel viewModel;

    setUp(() {
      repository = NetworkServicesRepository(
        customStorage: WolStorageService(inMemory: true),
        customSettingsStorage: SettingsStorageService(inMemory: true),
      );
      viewModel = NetworkServicesViewModel(repository: repository);
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('Initializes with default ports and empty search filters', () {
      expect(viewModel.dnsPort, equals(53));
      expect(viewModel.ntpPort, equals(123));
      expect(viewModel.dhcpPort, equals(67));
      expect(viewModel.logFilter, equals('ALL'));
      expect(viewModel.searchQuery, isEmpty);
      expect(viewModel.selectedLog, isNull);
      expect(viewModel.isAnyServiceRunning, isFalse);
    });

    test('Port updates validate bounds and persist', () {
      viewModel.setDnsPort(5353);
      expect(viewModel.dnsPort, equals(5353));

      viewModel.setNtpPort(1123);
      expect(viewModel.ntpPort, equals(1123));

      viewModel.setDhcpPort(6767);
      expect(viewModel.dhcpPort, equals(6767));

      // Out of bounds port is ignored
      viewModel.setDnsPort(70000);
      expect(viewModel.dnsPort, equals(5353));
    });

    test('Log filtering matches service type and search text across action, summary, client', () {
      repository.logServiceEvent(
        serviceType: ServiceType.dns,
        action: 'RESOLVED',
        summary: 'Query router.local from 192.168.1.55',
        details: 'Type 1 A record',
      );
      repository.logServiceEvent(
        serviceType: ServiceType.dhcp,
        action: 'ACK',
        summary: 'Leased 192.168.1.105 to AA:BB:CC:DD:EE:01',
      );
      repository.logServiceEvent(
        serviceType: ServiceType.ntp,
        action: 'TIME_SYNC',
        summary: 'Sync reply sent to 192.168.1.80',
      );

      // Total repository logs
      expect(repository.logs.length, equals(3));

      // Filter by DNS only
      viewModel.setLogFilter('DNS');
      expect(viewModel.filteredLogs.length, equals(1));
      expect(viewModel.filteredLogs.first.action, equals('RESOLVED'));

      // Filter by DHCP only
      viewModel.setLogFilter('DHCP');
      expect(viewModel.filteredLogs.length, equals(1));
      expect(viewModel.filteredLogs.first.action, equals('ACK'));

      // Filter ALL with search query
      viewModel.setLogFilter('ALL');
      viewModel.setSearchQuery('router.local');
      expect(viewModel.filteredLogs.length, equals(1));

      viewModel.setSearchQuery('192.168.1');
      expect(viewModel.filteredLogs.length, equals(3));

      // Clear logs
      viewModel.clearLogs();
      expect(viewModel.filteredLogs, isEmpty);
      expect(repository.logs, isEmpty);
    });

    test('Selecting interface updates DHCP defaults without overwriting user state while DHCP is running', () {
      const iface1 = NetworkInterfaceInfo(
        name: 'eth0',
        ip: '10.0.0.5',
        subnetMask: '255.255.255.0',
        prefixLength: 24,
        defaultGateway: '10.0.0.1',
      );

      viewModel.selectInterface(iface1);
      expect(viewModel.selectedInterface?.name, equals('eth0'));
      expect(viewModel.dhcpConfig.gatewayIp, equals('10.0.0.1'));
      expect(viewModel.dhcpConfig.startIp, equals('10.0.0.6'));
    });

    test('DHCP validation prevents starting server when configuration has errors', () async {
      // Invalidate DHCP config: pool includes gateway IP
      final invalidConfig = viewModel.dhcpConfig.copyWith(
        startIp: '192.168.1.1',
        gatewayIp: '192.168.1.1',
        poolSize: 10,
        subnetMask: '255.255.255.0',
      );
      viewModel.updateDhcpConfig(invalidConfig);

      // Attempt to toggle DHCP
      await viewModel.toggleDhcp();

      expect(viewModel.dhcpStatus.state, equals(ServiceState.stopped));
      expect(viewModel.dhcpValidationError, isNotNull);
      expect(viewModel.activeErrorMessage, contains('DHCP Config'));
    });

    test('DNS records and Upstream IP management', () {
      viewModel.addDnsRecord(const DnsRecord(domain: 'printer.lan', ip: '192.168.1.200'));
      expect(viewModel.dnsRecords.any((r) => r.domain == 'printer.lan'), isTrue);

      viewModel.setUpstreamDnsIp('1.1.1.1');
      expect(viewModel.upstreamDnsIp, equals('1.1.1.1'));

      viewModel.removeDnsRecord('printer.lan');
      expect(viewModel.dnsRecords.any((r) => r.domain == 'printer.lan'), isFalse);
    });

    test('Static reservations addition and removal', () {
      const res = DhcpStaticReservation(
        macAddress: '11:22:33:44:55:66',
        ipAddress: '192.168.1.44',
        deviceName: 'Workstation',
      );

      viewModel.addStaticReservation(res);
      expect(viewModel.dhcpConfig.staticReservations.length, equals(1));
      expect(viewModel.dhcpConfig.staticReservations.first.deviceName, equals('Workstation'));

      viewModel.removeStaticReservation('11:22:33:44:55:66');
      expect(viewModel.dhcpConfig.staticReservations, isEmpty);
    });
  });
}
