import 'dart:typed_data';

enum DhcpMessageType {
  discover(1),
  offer(2),
  request(3),
  decline(4),
  ack(5),
  nak(6),
  release(7),
  inform(8),
  unknown(0);

  final int value;
  const DhcpMessageType(this.value);

  static DhcpMessageType fromValue(int val) {
    return DhcpMessageType.values.firstWhere(
      (m) => m.value == val,
      orElse: () => DhcpMessageType.unknown,
    );
  }
}

class DhcpPacket {
  final int op;
  final int xid;
  final int flags;
  final String ciaddr;
  final String yiaddr;
  final String siaddr;
  final String chaddrMac;
  final Uint8List rawChaddr;
  final DhcpMessageType messageType;
  final String? requestedIp;
  final String? hostname;
  final Map<int, Uint8List> options;

  const DhcpPacket({
    required this.op,
    required this.xid,
    required this.flags,
    required this.ciaddr,
    required this.yiaddr,
    required this.siaddr,
    required this.chaddrMac,
    required this.rawChaddr,
    required this.messageType,
    this.requestedIp,
    this.hostname,
    required this.options,
  });
}

class DhcpPacketParser {
  static const magicCookie = [0x63, 0x82, 0x53, 0x63];

  /// Parses an incoming DHCP packet
  static DhcpPacket? parse(Uint8List data) {
    if (data.length < 240) return null;

    // Verify magic cookie at offset 236
    if (data[236] != magicCookie[0] ||
        data[237] != magicCookie[1] ||
        data[238] != magicCookie[2] ||
        data[239] != magicCookie[3]) {
      return null;
    }

    final byteData = ByteData.sublistView(data);
    final op = data[0];
    final hlen = data[2];
    final xid = byteData.getUint32(4);
    final flags = byteData.getUint16(10);

    final ciaddr = _formatIp(data, 12);
    final yiaddr = _formatIp(data, 16);
    final siaddr = _formatIp(data, 20);

    // MAC address from chaddr (offset 28)
    final macLength = (hlen > 0 && hlen <= 16) ? hlen : 6;
    final rawMac = data.sublist(28, 28 + macLength);
    final macStr = rawMac.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
    final rawChaddr = data.sublist(28, 44);

    // Parse options starting from offset 240
    final options = <int, Uint8List>{};
    int offset = 240;
    DhcpMessageType messageType = DhcpMessageType.unknown;
    String? requestedIp;
    String? hostname;

    while (offset < data.length) {
      final code = data[offset];
      offset++;

      if (code == 0) continue; // Pad
      if (code == 255) break; // End

      if (offset >= data.length) break;
      final len = data[offset];
      offset++;

      if (offset + len > data.length) break;
      final optData = data.sublist(offset, offset + len);
      options[code] = optData;

      if (code == 53 && len >= 1) {
        messageType = DhcpMessageType.fromValue(optData[0]);
      } else if (code == 50 && len == 4) {
        requestedIp = _formatIp(optData, 0);
      } else if (code == 12 && len > 0) {
        hostname = String.fromCharCodes(optData);
      }

      offset += len;
    }

    return DhcpPacket(
      op: op,
      xid: xid,
      flags: flags,
      ciaddr: ciaddr,
      yiaddr: yiaddr,
      siaddr: siaddr,
      chaddrMac: macStr,
      rawChaddr: rawChaddr,
      messageType: messageType,
      requestedIp: requestedIp,
      hostname: hostname,
      options: options,
    );
  }

  /// Builds a DHCP response packet (DHCPOFFER or DHCPACK)
  static Uint8List buildReply({
    required DhcpPacket request,
    required DhcpMessageType replyType,
    required String offeredIp,
    required String serverIp,
    required String subnetMask,
    required String routerIp,
    required String dnsServerIp,
    required int leaseTimeSeconds,
  }) {
    final builder = BytesBuilder();

    // 0: op (2 = BOOTREPLY)
    builder.addByte(2);
    // 1: htype (1 = Ethernet)
    builder.addByte(1);
    // 2: hlen (6 = MAC)
    builder.addByte(6);
    // 3: hops (0)
    builder.addByte(0);

    // 4..7: xid (from request)
    final xidBytes = Uint8List(4)..buffer.asByteData().setUint32(0, request.xid);
    builder.add(xidBytes);

    // 8..9: secs (0)
    builder.add([0x00, 0x00]);

    // 10..11: flags (echo client flags)
    builder.add([
      (request.flags >> 8) & 0xFF,
      request.flags & 0xFF,
    ]);

    // 12..15: ciaddr (0.0.0.0 for offer, or client IP)
    builder.add(_ipToBytes(request.ciaddr == '0.0.0.0' ? '0.0.0.0' : request.ciaddr));

    // 16..19: yiaddr ('Your' offered/assigned IP address)
    builder.add(_ipToBytes(offeredIp));

    // 20..23: siaddr (Next server IP address)
    builder.add(_ipToBytes(serverIp));

    // 24..27: giaddr (Relay agent: 0.0.0.0)
    builder.add([0x00, 0x00, 0x00, 0x00]);

    // 28..43: chaddr (Client hardware address: 16 bytes)
    builder.add(request.rawChaddr);

    // 44..107: sname (64 bytes of zeros)
    builder.add(Uint8List(64));

    // 108..235: file (128 bytes of zeros)
    builder.add(Uint8List(128));

    // 236..239: magic cookie
    builder.add(magicCookie);

    // Options:
    // Option 53: DHCP Message Type (OFFER = 2, ACK = 5)
    builder.add([53, 1, replyType.value]);

    // Option 54: Server Identifier
    builder.add([54, 4, ..._ipToBytes(serverIp)]);

    // Option 51: Lease Time (32-bit seconds)
    final leaseBytes = Uint8List(4)..buffer.asByteData().setUint32(0, leaseTimeSeconds);
    builder.add([51, 4, ...leaseBytes]);

    // Option 1: Subnet Mask
    builder.add([1, 4, ..._ipToBytes(subnetMask)]);

    // Option 3: Router / Default Gateway
    builder.add([3, 4, ..._ipToBytes(routerIp)]);

    // Option 6: Domain Name Server
    builder.add([6, 4, ..._ipToBytes(dnsServerIp)]);

    // Option 255: End marker
    builder.addByte(255);

    // RFC minimum BOOTP packet size is 300 bytes, pad with zeros if needed
    final result = builder.toBytes();
    if (result.length < 300) {
      final padded = Uint8List(300);
      padded.setRange(0, result.length, result);
      return padded;
    }

    return result;
  }

  static String _formatIp(Uint8List data, int offset) {
    if (offset + 4 > data.length) return '0.0.0.0';
    return '${data[offset]}.${data[offset + 1]}.${data[offset + 2]}.${data[offset + 3]}';
  }

  static List<int> _ipToBytes(String ip) {
    final parts = ip.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (parts.length < 4) {
      parts.add(0);
    }
    return parts.take(4).toList();
  }
}
