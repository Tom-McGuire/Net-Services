import 'dart:typed_data';

class NtpPacketParser {
  static const int ntpEpochOffsetSeconds = 2208988800;

  /// Checks if packet is a valid NTP client request (Mode 3, at least 48 bytes)
  static bool isValidClientRequest(Uint8List data) {
    if (data.length < 48) return false;
    final mode = data[0] & 0x07;
    return mode == 3; // Mode 3: Client
  }

  /// Extracts the client's transmit timestamp from bytes 40..47
  static Uint8List extractClientTransmitTimestamp(Uint8List data) {
    return data.sublist(40, 48);
  }

  /// Builds a 48-byte NTP Mode 4 Server response using the local machine time
  static Uint8List buildResponse({
    required Uint8List clientData,
    required DateTime receiveTime,
    required DateTime transmitTime,
  }) {
    final response = Uint8List(48);
    final byteData = ByteData.sublistView(response);

    // Byte 0: LI = 0, VN = 4 (or client's version), Mode = 4 (Server)
    final clientVersion = (clientData[0] >> 3) & 0x07;
    final vn = (clientVersion >= 1 && clientVersion <= 4) ? clientVersion : 4;
    response[0] = (0 << 6) | (vn << 3) | 4; // 0x24 for VN=4

    // Byte 1: Stratum 1 (Primary reference clock / local system clock)
    response[1] = 1;

    // Byte 2: Poll interval (echo client poll or 4)
    response[2] = clientData[2] > 0 ? clientData[2] : 4;

    // Byte 3: Precision (-20 in two's complement = 0xEC, ~1 microsecond)
    response[3] = 0xEC;

    // Bytes 4-7: Root Delay (0)
    byteData.setUint32(4, 0);

    // Bytes 8-11: Root Dispersion (small value, e.g. 0x00000010)
    byteData.setUint32(8, 0x00000010);

    // Bytes 12-15: Reference Identifier "LOCL"
    response[12] = 0x4C; // 'L'
    response[13] = 0x4F; // 'O'
    response[14] = 0x43; // 'C'
    response[15] = 0x4C; // 'L'

    // Bytes 16-23: Reference Timestamp (time of local clock)
    _writeNtpTimestamp(byteData, 16, receiveTime);

    // Bytes 24-31: Originate Timestamp (copied directly from client's transmit timestamp)
    response.setRange(24, 32, clientData.sublist(40, 48));

    // Bytes 32-39: Receive Timestamp (local time when received)
    _writeNtpTimestamp(byteData, 32, receiveTime);

    // Bytes 40-47: Transmit Timestamp (local time when replying)
    _writeNtpTimestamp(byteData, 40, transmitTime);

    return response;
  }

  static void _writeNtpTimestamp(ByteData byteData, int offset, DateTime dt) {
    final utc = dt.toUtc();
    final seconds = (utc.millisecondsSinceEpoch ~/ 1000) + ntpEpochOffsetSeconds;
    final micros = utc.microsecondsSinceEpoch % 1000000;
    // Map 0..999,999 to 0..2^32-1
    final fraction = ((micros * 4294967296) ~/ 1000000) & 0xFFFFFFFF;

    byteData.setUint32(offset, seconds);
    byteData.setUint32(offset + 4, fraction);
  }
}
