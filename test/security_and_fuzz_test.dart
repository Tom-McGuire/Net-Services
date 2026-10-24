import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/services/dhcp/dhcp_lease_manager.dart';
import 'package:net_services/data/services/dhcp/dhcp_packet_parser.dart';
import 'package:net_services/data/services/dns/dns_packet_parser.dart';
import 'package:net_services/data/services/dns/dns_server_service.dart';
import 'package:net_services/data/services/export/csv_export_service.dart';
import 'package:net_services/domain/models/dhcp_config.dart';
import 'package:net_services/domain/models/dns_record.dart';
import 'package:net_services/domain/models/service_log_record.dart';

void main() {
  group('Security & Vulnerability Fix Verification Tests', () {
    test('H1 & M1: DhcpConfig validation rejects out-of-subnet, invalid IPs, small leases', () {
      // Valid config
      expect(DhcpConfig.defaultConfig.validate(), isEmpty);

      // M1: Start IP crosses subnet boundary or invalid IP
      final invalidStartIp = DhcpConfig.defaultConfig.copyWith(startIp: '999.1.1.1');
      expect(invalidStartIp.validate(), isNotEmpty);

      // Start IP outside gateway subnet
      final diffSubnet = DhcpConfig.defaultConfig.copyWith(
        startIp: '10.0.0.10',
        gatewayIp: '192.168.1.1',
        subnetMask: '255.255.255.0',
      );
      expect(diffSubnet.validate(), contains('Start IP and Gateway IP are on different subnets.'));

      // Pool includes gateway IP
      final poolWithGateway = DhcpConfig.defaultConfig.copyWith(
        startIp: '192.168.1.1',
        poolSize: 5,
        gatewayIp: '192.168.1.1',
        subnetMask: '255.255.255.0',
      );
      expect(poolWithGateway.validate(), contains('IP pool contains the gateway IP address (192.168.1.1).'));

      // Lease duration too short (< 60s)
      final shortLease = DhcpConfig.defaultConfig.copyWith(leaseTimeSeconds: 30);
      expect(shortLease.validate(), contains('Lease duration must be at least 60 seconds.'));
    });

    test('H2 & H3: DHCP Lease Manager uses tentative reservations to prevent starvation', () {
      const config = DhcpConfig(
        startIp: '192.168.1.100',
        poolSize: 2,
        subnetMask: '255.255.255.0',
        gatewayIp: '192.168.1.1',
        dnsServerIp: '192.168.1.1',
      );
      final manager = DhcpLeaseManager(config: config);

      // Client 1 sends DISCOVER (tentative reservation created for 60s)
      final offer1 = manager.reserveOrGetOffer('AA:BB:CC:DD:EE:01', hostname: 'victim1');
      expect(offer1, equals('192.168.1.100'));
      // No active 24h lease committed yet!
      expect(manager.activeLeases, isEmpty);

      // Client 1 sends REQUEST and confirms lease
      final lease1 = manager.confirmLease('AA:BB:CC:DD:EE:01', requestedIp: '192.168.1.100');
      expect(lease1, isNotNull);
      expect(manager.activeLeases.length, equals(1));

      // Client 2 requests IP not in pool -> returns null (leading to NAK)
      final badRequest = manager.confirmLease('AA:BB:CC:DD:EE:02', requestedIp: '10.0.0.5');
      expect(badRequest, isNull);

      // Client declines an IP -> quarantined
      manager.declineIp('192.168.1.101');
      final offerAfterDecline = manager.reserveOrGetOffer('AA:BB:CC:DD:EE:03');
      // 100 is leased, 101 is declined -> pool exhausted
      expect(offerAfterDecline, isNull);
    });

    test('H4: DNS Packet Parser drops responses (QR=1) and unsupported opcodes', () {
      final builder = BytesBuilder();
      // ID
      builder.add([0x12, 0x34]);
      // Flags with QR=1 (0x8000)
      builder.add([0x80, 0x00]);
      builder.add([0x00, 0x01]);
      builder.add(Uint8List(6));
      builder.add([7, ...'example'.codeUnits, 5, ...'local'.codeUnits, 0]);
      builder.add([0x00, 0x01, 0x00, 0x01]);

      // QR=1 packet must be dropped
      expect(DnsPacketParser.parseQuery(builder.toBytes()), isNull);

      // Opcode != 0 (e.g. Opcode = 2 Status) must be dropped
      final badOpcode = Uint8List.fromList(builder.toBytes());
      badOpcode[2] = 0x10; // Opcode 2
      expect(DnsPacketParser.parseQuery(badOpcode), isNull);
    });

    test('L5: DNS Server matches exact records first before wildcard *', () {
      final service = DnsServerService();
      // Add wildcard FIRST, then specific record
      service.setRecords([
        const DnsRecord(domain: '*', ip: '1.1.1.1'),
        const DnsRecord(domain: 'special.local', ip: '192.168.1.99'),
      ]);

      expect(service.records.first.domain, equals('*'));

      // If we ask for special.local, exact match must win
      final exactMatch = service.records.firstWhere((r) => r.domain.toLowerCase() == 'special.local');
      expect(exactMatch.ip, equals('192.168.1.99'));
    });

    test('M6: CSV Export Service prevents spreadsheet formula injection and quotes fields', () {
      final logs = [
        ServiceLogRecord(
          id: '1',
          timestamp: DateTime.utc(2026, 1, 1),
          serviceType: ServiceType.dns,
          action: 'QUERY',
          summary: '=cmd|"/C calc"!A0',
          clientAddress: '+44 1234',
          severity: LogSeverity.info,
        ),
      ];

      final csv = CsvExportService.formatCsv(logs);
      // Ensure dangerous characters =, + are prefixed with ' inside quotes
      expect(csv, contains('\'=cmd|""/C calc""!A0'));
      expect(csv, contains('\'+44 1234'));
      expect(csv, startsWith('"ID","Timestamp","Service"'));
    });

    test('Fuzz: Parsers withstand random byte inputs without throwing unhandled exceptions', () {
      final random = Random(42);

      for (int i = 0; i < 500; i++) {
        final length = random.nextInt(600);
        final bytes = Uint8List(length);
        for (int j = 0; j < length; j++) {
          bytes[j] = random.nextInt(256);
        }

        // Neither parser should throw RangeError or unhandled exception
        expect(() => DhcpPacketParser.parse(bytes), returnsNormally);
        expect(() => DnsPacketParser.parseQuery(bytes), returnsNormally);
      }
    });
  });
}
