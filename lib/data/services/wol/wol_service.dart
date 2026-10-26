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

      final targetIp = InternetAddress(broadcastAddress);
      socket.send(packet, targetIp, port);

      // Also send to universal broadcast (255.255.255.255) if a subnet broadcast was given
      if (broadcastAddress != '255.255.255.255') {
        try {
          socket.send(packet, InternetAddress('255.255.255.255'), port);
        } catch (_) {}
      }

      // Also send to port 7 (echo/WOL fallback)
      if (port == 9) {
        try {
          socket.send(packet, targetIp, 7);
        } catch (_) {}
      }

      return true;
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

    // Step 2: Query system ARP table
    try {
      ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('arp', ['-a', ip]);
      } else {
        result = await Process.run('arp', ['-n', ip]);
      }

      if (result.exitCode == 0) {
        final stdout = result.stdout as String;
        final macRegex = RegExp(r'([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})');
        final match = macRegex.firstMatch(stdout);
        if (match != null) {
          final rawMac = match.group(0);
          if (rawMac != null) {
            final normalized = WolDevice.normalizeMac(rawMac);
            // Ensure not a broadcast or multicast MAC
            if (normalized != null &&
                normalized != 'FF:FF:FF:FF:FF:FF' &&
                !normalized.startsWith('01:00:5E')) {
              return normalized;
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }
}
