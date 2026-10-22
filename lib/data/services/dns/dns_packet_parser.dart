import 'dart:typed_data';

class DnsQuery {
  final int transactionId;
  final String domain;
  final int qType;
  final int qClass;
  final Uint8List rawQuestionBytes;

  const DnsQuery({
    required this.transactionId,
    required this.domain,
    required this.qType,
    required this.qClass,
    required this.rawQuestionBytes,
  });
}

class DnsPacketParser {
  /// Parses an incoming DNS query datagram
  static DnsQuery? parseQuery(Uint8List data) {
    if (data.length < 12) return null;

    final byteData = ByteData.sublistView(data);
    final transactionId = byteData.getUint16(0);
    final qdCount = byteData.getUint16(4);
    if (qdCount < 1) return null;

    // Parse QNAME starting at offset 12
    int offset = 12;
    final labels = <String>[];

    while (offset < data.length) {
      final len = data[offset];
      offset++;
      if (len == 0) break; // End of domain name
      if (len > 63 || offset + len > data.length) return null;

      final label = String.fromCharCodes(data.sublist(offset, offset + len));
      labels.add(label);
      offset += len;
    }

    if (offset + 4 > data.length) return null;

    final qType = byteData.getUint16(offset);
    final qClass = byteData.getUint16(offset + 2);
    final rawQuestion = data.sublist(12, offset + 4);

    return DnsQuery(
      transactionId: transactionId,
      domain: labels.join('.'),
      qType: qType,
      qClass: qClass,
      rawQuestionBytes: rawQuestion,
    );
  }

  /// Builds a DNS response packet
  static Uint8List buildResponse({
    required DnsQuery query,
    required String? resolvedIp,
    int ttl = 300,
  }) {
    final builder = BytesBuilder();

    // 1. Transaction ID (16 bits)
    builder.add([
      (query.transactionId >> 8) & 0xFF,
      query.transactionId & 0xFF,
    ]);

    // 2. Flags: Response, Authoritative Answer, Recursion Desired
    // 0x8180 (Standard response, No error) or 0x8183 (NXDOMAIN)
    final bool isFound = resolvedIp != null;
    final int flags = isFound ? 0x8180 : 0x8183;
    builder.add([(flags >> 8) & 0xFF, flags & 0xFF]);

    // 3. QDCOUNT (1)
    builder.add([0x00, 0x01]);

    // 4. ANCOUNT (1 if found, 0 if NXDOMAIN)
    builder.add([0x00, isFound ? 0x01 : 0x00]);

    // 5. NSCOUNT (0)
    builder.add([0x00, 0x00]);

    // 6. ARCOUNT (0)
    builder.add([0x00, 0x00]);

    // 7. Question Section (verbatim from query)
    builder.add(query.rawQuestionBytes);

    // 8. Answer Section (if found)
    if (isFound) {
      // Name pointer to offset 12 (0xC00C)
      builder.add([0xC0, 0x0C]);

      // Type 1 (A Record)
      builder.add([0x00, 0x01]);

      // Class 1 (IN)
      builder.add([0x00, 0x01]);

      // TTL (32 bits)
      builder.add([
        (ttl >> 24) & 0xFF,
        (ttl >> 16) & 0xFF,
        (ttl >> 8) & 0xFF,
        ttl & 0xFF,
      ]);

      // RDLENGTH (4 bytes for IPv4)
      builder.add([0x00, 0x04]);

      // RDATA (IPv4 octets)
      final octets = resolvedIp.split('.').map((s) => int.tryParse(s) ?? 0).toList();
      while (octets.length < 4) {
        octets.add(0);
      }
      builder.add(octets.take(4).toList());
    }

    return builder.toBytes();
  }
}
