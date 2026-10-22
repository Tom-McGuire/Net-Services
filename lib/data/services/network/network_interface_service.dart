import 'dart:io';
import '../../../domain/models/network_interface_info.dart';

class NetworkInterfaceService {
  Future<List<NetworkInterfaceInfo>> getAvailableInterfaces() async {
    final results = <NetworkInterfaceInfo>[];

    // Map interface name to detected CIDR prefix length
    final prefixMap = await _detectPrefixLengths();

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final prefix = prefixMap[iface.name] ?? 24;
          final mask = NetworkInterfaceInfo.prefixToSubnetMask(prefix);
          results.add(
            NetworkInterfaceInfo(
              name: iface.name,
              ip: addr.address,
              subnetMask: mask,
              prefixLength: prefix,
            ),
          );
        }
      }
    } catch (_) {
      // Fallback if list fails
    }

    if (results.isEmpty) {
      results.add(
        const NetworkInterfaceInfo(
          name: 'Default',
          ip: '192.168.1.10',
          subnetMask: '255.255.255.0',
          prefixLength: 24,
        ),
      );
    }

    return results;
  }

  /// Parses CIDR prefix lengths from Linux `ip -o -f inet addr show`
  Future<Map<String, int>> _detectPrefixLengths() async {
    final map = <String, int>{};
    if (!Platform.isLinux && !Platform.isMacOS) return map;

    try {
      final result = await Process.run('ip', ['-o', '-f', 'inet', 'addr', 'show']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        for (final line in lines) {
          // Format e.g.: 2: enp1s0    inet 10.101.1.50/24 brd ...
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final ifName = parts[1];
            final ipCidr = parts[3];
            if (ipCidr.contains('/')) {
              final prefix = int.tryParse(ipCidr.split('/')[1]);
              if (prefix != null) {
                map[ifName] = prefix;
              }
            }
          }
        }
      }
    } catch (_) {}
    return map;
  }

  /// Checks if the process has elevated root privileges
  Future<bool> checkHasElevatedPrivileges() async {
    if (Platform.isWindows) return true; // Windows handles <1024 differently
    try {
      final result = await Process.run('id', ['-u']);
      if (result.exitCode == 0) {
        final uid = int.tryParse((result.stdout as String).trim());
        return uid == 0;
      }
    } catch (_) {}
    return false;
  }
}
