import 'dart:io';
import 'dart:typed_data';
import 'package:network_suite_shared/network_suite_shared.dart';
import '../../../domain/models/wol_device.dart';

class WolService {
  WolService({ArpCacheParser? arpCacheParser})
      : _arpCacheParser = arpCacheParser ?? ArpCacheParser();

  final ArpCacheParser _arpCacheParser;
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
  Future<String?> resolveMacFromIp(String ip) {
    return _arpCacheParser.resolveMacForIp(ip);
  }
}
