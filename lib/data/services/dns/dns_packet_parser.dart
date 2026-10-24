import 'dart:typed_data';

class DnsQuery {
  final int transactionId;
  final int flags;
  final String domain;
  final int qType;
  final int qClass;
  final Uint8List rawQuestionBytes;

  const DnsQuery({
    required this.transactionId,
    required this.flags,
    required this.domain,
    required this.qType,
    required this.qClass,
    required this.rawQuestionBytes,
  });

  bool get recursionDesired => (flags & 0x0100) != 0;
  int get opcode => (flags >> 11) & 0x0F;
}

class DnsPacketParser {
  /// Parses an incoming DNS query datagram.
  /// Drops responses (QR=1), unsupported opcodes, or malformed queries.
  static DnsQuery? parseQuery(Uint8List data) {
    if (data.length < 12) return null;

    final byteData = ByteData.sublistView(data);
    final transactionId = byteData.getUint16(0);
    final flags = byteData.getUint16(2);

    // H4: Check QR bit (bit 15: 0x8000). If QR == 1, this is a response, NOT a query.
    // Drop it to avoid DNS reflection loops.
    if ((flags & 0x8000) != 0) {
      return null;
    }

    // Check opcode (bits 11-14). 0 is standard query. Drop if non-standard query.
    final opcode = (flags >> 11) & 0x0F;
    if (opcode != 0) {
      return null;
    }

    final qdCount = byteData.getUint16(4);
    // RFC standard: DNS servers typically process exactly 1 question per packet
    if (qdCount != 1) return null;

    // Parse QNAME starting at offset 12
    int offset = 12;
    final labels = <String>[];

    while (offset < data.length) {
      final len = data[offset];
      offset++;
      if (len == 0) break; // End of domain name
      // Compressed pointers (0xC0..) not supported in incoming questions, or label too long
      if ((len & 0xC0) != 0 || len > 63 || offset + len > data.length) {
        return null;
      }

      final rawLabel = String.fromCharCodes(data.sublist(offset, offset + len));
      // M5: Sanitize label
      final sanitized = _sanitizeDnsLabel(rawLabel);
      if (sanitized.isEmpty && rawLabel.isNotEmpty) return null;
      labels.add(sanitized);
      offset += len;
    }

    if (offset + 4 > data.length) return null;

    final qType = byteData.getUint16(offset);
    final qClass = byteData.getUint16(offset + 2);
    final rawQuestion = data.sublist(12, offset + 4);

    final fullDomain = labels.join('.');
    if (fullDomain.length > 253) return null;

    return DnsQuery(
      transactionId: transactionId,
      flags: flags,
      domain: fullDomain,
      qType: qType,
      qClass: qClass,
      rawQuestionBytes: rawQuestion,
    );
  }

  static String _sanitizeDnsLabel(String label) {
    return label.replaceAll(RegExp(r'[^a-zA-Z0-9\-_*]'), '');
  }

  /// Builds a DNS response packet.
  /// [resolvedIp]: The IPv4 address if matching A record found, or null.
  /// [isDomainKnown]: True if the domain exists in our zone (even if query was for non-A type).
  static Uint8List buildResponse({
    required DnsQuery query,
    required String? resolvedIp,
    bool isDomainKnown = false,
    int ttl = 300,
  }) {
    final builder = BytesBuilder();

    // 1. Transaction ID (16 bits)
    builder.add([
      (query.transactionId >> 8) & 0xFF,
      query.transactionId & 0xFF,
    ]);

    // 2. Flags:
    // Bit 15: QR = 1 (Response)
    // Bit 10: AA = 1 (Authoritative Answer, this server is authoritative for configured records)
    // Bit 8: RD = Echo client's Recursion Desired
    // Bit 7: RA = 0 (Recursion NOT available on this server)
    // Bits 0-3: RCODE (0 = NOERROR, 3 = NXDOMAIN)
    int responseFlags = 0x8400; // QR=1, AA=1, RA=0
    if (query.recursionDesired) {
      responseFlags |= 0x0100; // Echo RD
    }

    final bool hasAnswer = (resolvedIp != null && (query.qType == 1 || query.qType == 255));
    if (!hasAnswer && !isDomainKnown) {
      // Domain does not exist: RCODE = 3 (NXDOMAIN)
      responseFlags |= 0x0003;
    } else {
      // Domain exists (either with A answer or NODATA for other types): RCODE = 0 (NOERROR)
      responseFlags |= 0x0000;
    }

    builder.add([(responseFlags >> 8) & 0xFF, responseFlags & 0xFF]);

    // 3. QDCOUNT (1)
    builder.add([0x00, 0x01]);

    // 4. ANCOUNT (1 if A record answer included, 0 if NODATA / NXDOMAIN)
    builder.add([0x00, hasAnswer ? 0x01 : 0x00]);

    // 5. NSCOUNT (0)
    builder.add([0x00, 0x00]);

    // 6. ARCOUNT (0)
    builder.add([0x00, 0x00]);

    // 7. Question Section (verbatim from query)
    builder.add(query.rawQuestionBytes);

    // 8. Answer Section (if A record found and requested)
    if (hasAnswer) {
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
