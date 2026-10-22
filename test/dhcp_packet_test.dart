import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/services/dhcp/dhcp_packet_parser.dart';

void main() {
  group('DHCP Packet Parser & Reply Builder Tests', () {
    test('Parses DHCPDISCOVER packet and builds DHCPOFFER reply', () {
      final builder = BytesBuilder();
      // 0: op (1 = BOOTREQUEST)
      builder.addByte(1);
      // 1: htype (1 = Ethernet)
      builder.addByte(1);
      // 2: hlen (6 = MAC)
      builder.addByte(6);
      // 3: hops (0)
      builder.addByte(0);
      // 4..7: xid (0x12345678)
      builder.add([0x12, 0x34, 0x56, 0x78]);
      // 8..9: secs (0)
      builder.add([0x00, 0x00]);
      // 10..11: flags (0x8000 = Broadcast)
      builder.add([0x80, 0x00]);
      // 12..27: ciaddr, yiaddr, siaddr, giaddr (all 0)
      builder.add(Uint8List(16));
      // 28..43: chaddr (MAC: AA:BB:CC:DD:EE:FF + padding)
      builder.add([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]);
      builder.add(Uint8List(10));
      // 44..235: sname (64) + file (128)
      builder.add(Uint8List(64 + 128));
      // 236..239: magic cookie [0x63, 0x82, 0x53, 0x63]
      builder.add([0x63, 0x82, 0x53, 0x63]);
      // Options:
      // Option 53: DHCP Message Type (1 = DHCPDISCOVER)
      builder.add([53, 1, 1]);
      // Option 12: Host Name ("TestClient")
      builder.add([12, 10, ...'TestClient'.codeUnits]);
      // Option 255: End
      builder.addByte(255);

      final packet = DhcpPacketParser.parse(builder.toBytes());
      expect(packet, isNotNull);
      expect(packet!.op, equals(1));
      expect(packet.xid, equals(0x12345678));
      expect(packet.messageType, equals(DhcpMessageType.discover));
      expect(packet.chaddrMac, equals('AA:BB:CC:DD:EE:FF'));
      expect(packet.hostname, equals('TestClient'));

      // Build DHCPOFFER reply
      final offerBytes = DhcpPacketParser.buildReply(
        request: packet,
        replyType: DhcpMessageType.offer,
        offeredIp: '10.101.1.51',
        serverIp: '10.101.1.50',
        subnetMask: '255.255.255.0',
        routerIp: '10.101.1.50',
        dnsServerIp: '10.101.1.50',
        leaseTimeSeconds: 86400,
      );

      expect(offerBytes.length, greaterThanOrEqualTo(300));
      final replyPacket = DhcpPacketParser.parse(offerBytes);
      expect(replyPacket, isNotNull);
      expect(replyPacket!.op, equals(2)); // BOOTREPLY
      expect(replyPacket.xid, equals(0x12345678));
      expect(replyPacket.messageType, equals(DhcpMessageType.offer));
      expect(replyPacket.yiaddr, equals('10.101.1.51'));
      expect(replyPacket.siaddr, equals('10.101.1.50'));
    });
  });
}
