import 'dart:io';
import 'dart:typed_data';
import '../../../domain/models/wol_device.dart';

class WolService {
  /// Builds a standard 102-byte Wake-on-LAN Magic Packet.
  /// Structure: 6 bytes of 0xFF followed by 16 repetitions of the 6-byte MAC address.
  static Uint8List? buildMagicPacket(String macAddress) {
    final normalized = WolDevice.normalizeMac(macAddress);
    if (normalized == null) return null;

    final macOctets = normalized
        .split(':')
        .map((s) => int.parse(s, radix: 16))
        .toList();

    if (macOctets.length != 6) return null;

    final packet = Uint8List(102);

    // 1. Sync Stream: 6 bytes of 0xFF
    for (int i = 0; i < 6; i++) {
      packet[i] = 0xFF;
    }

    // 2. Target MAC: 16 iterations of 6 octets
    for (int rep = 0; rep < 16; rep++) {
      final offset = 6 + (rep * 6);
      for (int b = 0; b < 6; b++) {
        packet[offset + b] = macOctets[b];
      }
    }

    return packet;
  }

  /// Sends a Wake-on-LAN Magic Packet via UDP broadcast.
  Future<bool> sendWakePacket({
    required String macAddress,
    String broadcastAddress = '255.255.255.255',
    int port = 9,
  }) async {
    final packet = buildMagicPacket(macAddress);
    if (packet == null) return false;

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      int totalSent = 0;
      final targetIp = InternetAddress(broadcastAddress);
      totalSent += socket.send(packet, targetIp, port);

      // Also send to universal broadcast (255.255.255.255) if a subnet broadcast was given
      if (broadcastAddress != '255.255.255.255') {
        try {
          totalSent += socket.send(packet, InternetAddress('255.255.255.255'), port);
        } catch (_) {}
      }

      // Also send to port 7 (echo/WOL fallback)
      if (port == 9) {
        try {
          totalSent += socket.send(packet, targetIp, 7);
        } catch (_) {}
      }

      return totalSent > 0;
    } catch (_) {
      return false;
    } finally {
      socket?.close();
    }
  }

  /// Resolves the physical MAC address for an online IP address on the local network.
  /// Pings the IP briefly to ensure ARP cache population, then inspects system ARP table.
  Future<String?> resolveMacFromIp(String ip) async {
    final parsed = InternetAddress.tryParse(ip);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) {
      return null;
    }

    // Step 1: Prime the system ARP cache with a quick ping
    try {
      if (Platform.isWindows) {
        await Process.run('ping', ['-n', '1', '-w', '600', ip]);
      } else if (Platform.isMacOS) {
        await Process.run('ping', ['-c', '1', '-t', '1', ip]);
      } else {
        await Process.run('ping', ['-c', '1', '-W', '1', ip]);
      }
    } catch (_) {}

    // Step 2a: On Linux, check /proc/net/arp first (no external binary dependency)
    if (Platform.isLinux) {
      try {
        final arpFile = File('/proc/net/arp');
        if (await arpFile.exists()) {
          final lines = await arpFile.readAsLines();
          for (final line in lines.skip(1)) {
            final cols = line.trim().split(RegExp(r'\s+'));
            if (cols.length >= 4 && cols[0] == ip) {
              final normalized = _validateResolvedMac(cols[3]);
              if (normalized != null) return normalized;
            }
          }
        }
      } catch (_) {}

      // Step 2b: On Linux, try `ip neigh show <ip>`
      try {
        final ipRes = await Process.run('ip', ['neigh', 'show', ip]);
        if (ipRes.exitCode == 0) {
          final normalized = _extractMacFromText(ipRes.stdout as String);
          if (normalized != null) return normalized;
        }
      } catch (_) {}
    }

    // Step 2c: Fallback to `arp` CLI across Windows, macOS, and Linux
    try {
      final result = Platform.isWindows
          ? await Process.run('arp', ['-a', ip])
          : await Process.run('arp', ['-n', ip]);

      if (result.exitCode == 0) {
        final normalized = _extractMacFromText(result.stdout as String);
        if (normalized != null) return normalized;
      }
    } catch (_) {}

    return null;
  }

  static String? _extractMacFromText(String text) {
    final macRegex = RegExp(r'([0-9a-fA-F]{1,2}[:-]){5}([0-9a-fA-F]{1,2})');
    final match = macRegex.firstMatch(text);
    if (match == null) return null;
    final rawMac = match.group(0);
    if (rawMac == null) return null;
    // Pad single-digit hex octets (e.g. on macOS arp output `0:1a:2b:...`)
    final padded = rawMac
        .split(RegExp(r'[:-]'))
        .map((part) => part.padLeft(2, '0'))
        .join(':');
    return _validateResolvedMac(padded);
  }

  static String? _validateResolvedMac(String rawMac) {
    final normalized = WolDevice.normalizeMac(rawMac);
    if (normalized != null &&
        normalized != '00:00:00:00:00:00' &&
        normalized != 'FF:FF:FF:FF:FF:FF' &&
        !normalized.startsWith('01:00:5E')) {
      return normalized;
    }
    return null;
  }
}
