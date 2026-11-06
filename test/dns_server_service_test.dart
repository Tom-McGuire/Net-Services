import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/services/dns/dns_server_service.dart';
import 'package:net_services/domain/models/dhcp_lease.dart';
import 'package:net_services/domain/models/dns_record.dart';

void main() {
  group('DnsServerService Live Tests', () {
    late DnsServerService dnsService;
    const testPort = 15354;

    setUp(() {
      dnsService = DnsServerService();
    });

    tearDown(() async {
      await dnsService.stop();
      dnsService.dispose();
    });

    test('Binds socket, responds to A record queries, and emits log records', () async {
      dnsService.setRecords([
        const DnsRecord(domain: 'router.home', ip: '192.168.1.1', ttl: 300),
        const DnsRecord(domain: '*.lab.local', ip: '192.168.1.50', ttl: 120),
        const DnsRecord(domain: '*', ip: '10.0.0.1', ttl: 60),
      ]);

      await dnsService.start(port: testPort);
      expect(dnsService.status.isRunning, isTrue);

      final clientSocket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final receivedResponses = StreamController<Uint8List>.broadcast();

      clientSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = clientSocket.receive();
          if (datagram != null) {
            receivedResponses.add(datagram.data);
          }
        }
      });

      // Query 1: Exact match "router.home"
      final query1Bytes = _buildStandardAQuery(0x1111, 'router.home');
      clientSocket.send(query1Bytes, InternetAddress.loopbackIPv4, testPort);

      final resp1 = await receivedResponses.stream.first.timeout(const Duration(seconds: 2));
      expect(resp1.sublist(resp1.length - 4), equals([192, 168, 1, 1]));

      // Query 2: Suffix wildcard "host.lab.local"
      final query2Bytes = _buildStandardAQuery(0x2222, 'host.lab.local');
      clientSocket.send(query2Bytes, InternetAddress.loopbackIPv4, testPort);

      final resp2 = await receivedResponses.stream.first.timeout(const Duration(seconds: 2));
      expect(resp2.sublist(resp2.length - 4), equals([192, 168, 1, 50]));

      // Query 3: Global wildcard "*" fallback for unmapped domain
      final query3Bytes = _buildStandardAQuery(0x3333, 'anything.unknown');
      clientSocket.send(query3Bytes, InternetAddress.loopbackIPv4, testPort);

      final resp3 = await receivedResponses.stream.first.timeout(const Duration(seconds: 2));
      expect(resp3.sublist(resp3.length - 4), equals([10, 0, 0, 1]));

      await receivedResponses.close();
      clientSocket.close();
    });

    test('Resolves reverse PTR queries and DHCP active lease hostnames', () {
      dnsService.setRecords([
        const DnsRecord(domain: 'gateway.lan', ip: '192.168.1.1'),
      ]);

      dnsService.setActiveLeasesProvider(() => [
        DhcpLease(
          macAddress: 'AA:BB:CC:DD:EE:01',
          ipAddress: '192.168.1.105',
          hostname: 'camera-front',
          leaseStart: DateTime.now(),
          leaseDurationSeconds: 3600,
        ),
      ]);

      // Reverse PTR for static record
      final ptr1 = dnsService.resolvePtr('1.1.168.192.in-addr.arpa');
      expect(ptr1, equals('gateway.lan'));

      // Reverse PTR for dynamic DHCP lease
      final ptr2 = dnsService.resolvePtr('105.1.168.192.in-addr.arpa');
      expect(ptr2, equals('camera-front.local'));

      // Forward query matching DHCP lease hostname
      final leaseHost = dnsService.resolveRecord('camera-front.local');
      expect(leaseHost, isNotNull);
      expect(leaseHost!.ip, equals('192.168.1.105'));
    });
  });
}

Uint8List _buildStandardAQuery(int txId, String domain) {
  final builder = BytesBuilder();
  builder.add([(txId >> 8) & 0xFF, txId & 0xFF]);
  builder.add([0x01, 0x00]); // Standard query, RD=1
  builder.add([0x00, 0x01]); // 1 question
  builder.add(Uint8List(6)); // ANCOUNT, NSCOUNT, ARCOUNT = 0

  for (final part in domain.split('.')) {
    builder.addByte(part.length);
    builder.add(part.codeUnits);
  }
  builder.addByte(0); // Root label
  builder.add([0x00, 0x01, 0x00, 0x01]); // Type A, Class IN
  return builder.toBytes();
}
