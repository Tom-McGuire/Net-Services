import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/services/ntp/ntp_packet_parser.dart';

void main() {
  group('NTP Packet Parser Tests', () {
    test('Identifies valid Mode 3 NTP Client request', () {
      final clientPacket = Uint8List(48);
      // Mode 3 (Client), Version 4 -> (4 << 3) | 3 = 0x23
      clientPacket[0] = 0x23;

      expect(NtpPacketParser.isValidClientRequest(clientPacket), isTrue);
    });

    test('Rejects packet shorter than 48 bytes or non-mode-3', () {
      expect(NtpPacketParser.isValidClientRequest(Uint8List(40)), isFalse);

      final invalidMode = Uint8List(48);
      invalidMode[0] = 0x24; // Mode 4 (Server)
      expect(NtpPacketParser.isValidClientRequest(invalidMode), isFalse);
    });

    test('Generates RFC 5905 Mode 4 Server response with local time', () {
      final clientPacket = Uint8List(48);
      clientPacket[0] = 0x23; // Version 4, Mode 3
      // Set dummy client transmit timestamp at bytes 40..47
      for (int i = 0; i < 8; i++) {
        clientPacket[40 + i] = 0xAA + i;
      }

      final receiveTime = DateTime.utc(2026, 10, 22, 12, 0, 0);
      final transmitTime = DateTime.utc(2026, 10, 22, 12, 0, 1);

      final response = NtpPacketParser.buildResponse(
        clientData: clientPacket,
        receiveTime: receiveTime,
        transmitTime: transmitTime,
      );

      expect(response.length, equals(48));

      // Byte 0: LI=0, VN=4, Mode=4 -> 0x24
      expect(response[0], equals(0x24));
      // Stratum 1 (Primary reference clock)
      expect(response[1], equals(10));
      // Reference ID: "LOCL" -> [0x4C, 0x4F, 0x43, 0x4C]
      expect(response.sublist(12, 16), equals([0x4C, 0x4F, 0x43, 0x4C]));

      // Originate timestamp (bytes 24..31) must echo client's transmit timestamp
      expect(response.sublist(24, 32), equals(clientPacket.sublist(40, 48)));

      // Check NTP epoch seconds in transmit timestamp (bytes 40..43)
      final byteData = ByteData.sublistView(response);
      final transmitSeconds = byteData.getUint32(40);
      // 2026-10-22 12:00:01 in NTP epoch should be > 3,900,000,000
      expect(transmitSeconds, greaterThan(3900000000));
    });
  });
}
