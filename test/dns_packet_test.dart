import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/services/dns/dns_packet_parser.dart';

void main() {
  group('DNS Packet Parser Tests', () {
    test('Correctly parses DNS query for example.local', () {
      final builder = BytesBuilder();
      // ID: 0x1234
      builder.add([0x12, 0x34]);
      // Flags: Standard query with RD=1 (0x0100)
      builder.add([0x01, 0x00]);
      // QDCOUNT: 1
      builder.add([0x00, 0x01]);
      // ANCOUNT: 0, NSCOUNT: 0, ARCOUNT: 0
      builder.add([0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
      // QNAME: \x07example\x05local\x00
      builder.add([7, ...'example'.codeUnits, 5, ...'local'.codeUnits, 0]);
      // QTYPE: 1 (A), QCLASS: 1 (IN)
      builder.add([0x00, 0x01, 0x00, 0x01]);

      final query = DnsPacketParser.parseQuery(builder.toBytes());
      expect(query, isNotNull);
      expect(query!.transactionId, equals(0x1234));
      expect(query.domain, equals('example.local'));
      expect(query.qType, equals(1));
      expect(query.qClass, equals(1));
    });

    test('Builds valid A record response with AA and echoed RD', () {
      final query = DnsQuery(
        transactionId: 0xABCD,
        flags: 0x0100, // RD = 1
        domain: 'router.local',
        qType: 1,
        qClass: 1,
        rawQuestionBytes: Uint8List.fromList([
          6, ...'router'.codeUnits, 5, ...'local'.codeUnits, 0, 0, 1, 0, 1,
        ]),
      );

      final responseBytes = DnsPacketParser.buildResponse(
        query: query,
        resolvedIp: '192.168.1.1',
        isDomainKnown: true,
        ttl: 300,
      );

      final byteData = ByteData.sublistView(responseBytes);
      // Verify Transaction ID
      expect(byteData.getUint16(0), equals(0xABCD));
      // Verify Flags: 0x8500 (Response, Authoritative, Recursion Desired echoed, No Error)
      expect(byteData.getUint16(2), equals(0x8500));
      // QDCOUNT: 1, ANCOUNT: 1
      expect(byteData.getUint16(4), equals(1));
      expect(byteData.getUint16(6), equals(1));

      // Check last 4 bytes are IP 192.168.1.1
      final len = responseBytes.length;
      expect(responseBytes.sublist(len - 4, len), equals([192, 168, 1, 1]));
    });

    test('Builds NXDOMAIN response when record not found', () {
      final query = DnsQuery(
        transactionId: 0x9999,
        flags: 0x0000,
        domain: 'unknown.box',
        qType: 1,
        qClass: 1,
        rawQuestionBytes: Uint8List.fromList([
          7, ...'unknown'.codeUnits, 3, ...'box'.codeUnits, 0, 0, 1, 0, 1,
        ]),
      );

      final responseBytes = DnsPacketParser.buildResponse(
        query: query,
        resolvedIp: null,
        isDomainKnown: false,
      );

      final byteData = ByteData.sublistView(responseBytes);
      expect(byteData.getUint16(0), equals(0x9999));
      // Flags: 0x8403 (Response, Authoritative, NXDOMAIN)
      expect(byteData.getUint16(2), equals(0x8403));
      // ANCOUNT: 0
      expect(byteData.getUint16(6), equals(0));
    });

    test('Rejects DNS response packets (QR=1) to prevent reflection loops', () {
      final responsePacket = Uint8List(20);
      responsePacket[0] = 0x12;
      responsePacket[1] = 0x34;
      // Flags with QR=1 (0x8000)
      responsePacket[2] = 0x80;
      responsePacket[3] = 0x00;

      expect(DnsPacketParser.parseQuery(responsePacket), isNull);
    });
  });
}
