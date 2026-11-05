import 'dart:io';
import '../../../domain/models/network_interface_info.dart';

class NetworkInterfaceService {
  Future<List<NetworkInterfaceInfo>> getAvailableInterfaces() async {
    final results = <NetworkInterfaceInfo>[];

    // Map (interface:ip) or interface name to detected CIDR prefix length
    final prefixMap = await _detectPrefixLengths();
    final gatewayMap = await _detectDefaultGateways();

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final prefix = prefixMap['${iface.name}:${addr.address}'] ??
              prefixMap[addr.address] ??
              prefixMap[iface.name] ??
              24;
          final mask = NetworkInterfaceInfo.prefixToSubnetMask(prefix);
          final gateway = gatewayMap[iface.name] ?? gatewayMap['default'];
          results.add(
            NetworkInterfaceInfo(
              name: iface.name,
              ip: addr.address,
              subnetMask: mask,
              prefixLength: prefix,
              defaultGateway: gateway,
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
          defaultGateway: '192.168.1.1',
        ),
      );
    }

    return results;
  }

  /// Parses CIDR prefix lengths across Linux (`ip`), macOS (`ifconfig`), and Windows (`ipconfig`).
  Future<Map<String, int>> _detectPrefixLengths() async {
    final map = <String, int>{};

    if (Platform.isLinux) {
      try {
        final result = await Process.run('ip', ['-o', '-f', 'inet', 'addr', 'show']);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split('\n');
          for (final line in lines) {
            final parts = line.trim().split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              final ifName = parts[1];
              final ipCidr = parts[3];
              if (ipCidr.contains('/')) {
                final split = ipCidr.split('/');
                final ip = split[0];
                final prefix = int.tryParse(split[1]);
                if (prefix != null) {
                  map['$ifName:$ip'] = prefix;
                  map[ip] = prefix;
                  map.putIfAbsent(ifName, () => prefix);
                }
              }
            }
          }
        }
      } catch (_) {}
    } else if (Platform.isMacOS) {
      try {
        final result = await Process.run('ifconfig', []);
        if (result.exitCode == 0) {
          String? currentIf;
          for (final line in (result.stdout as String).split('\n')) {
            final headerMatch = RegExp(r'^([a-zA-Z0-9_]+):').firstMatch(line);
            if (headerMatch != null) {
              currentIf = headerMatch.group(1);
            }
            final inetMatch = RegExp(r'inet\s+(\d+\.\d+\.\d+\.\d+)\s+netmask\s+0x([0-9a-fA-F]{8})').firstMatch(line);
            if (inetMatch != null) {
              final ip = inetMatch.group(1)!;
              final maskVal = int.tryParse(inetMatch.group(2)!, radix: 16);
              if (maskVal != null) {
                final prefix = _netmaskIntToPrefix(maskVal);
                map[ip] = prefix;
                if (currentIf != null) {
                  map['$currentIf:$ip'] = prefix;
                  map.putIfAbsent(currentIf, () => prefix);
                }
              }
            }
          }
        }
      } catch (_) {}
    } else if (Platform.isWindows) {
      try {
        final result = await Process.run('ipconfig', []);
        if (result.exitCode == 0) {
          String? lastIp;
          for (final line in (result.stdout as String).split('\n')) {
            final ipMatch = RegExp(r'IPv4[^:]*:\s*(\d+\.\d+\.\d+\.\d+)').firstMatch(line);
            if (ipMatch != null) {
              lastIp = ipMatch.group(1);
            }
            final maskMatch = RegExp(r'Subnet Mask[^:]*:\s*(\d+\.\d+\.\d+\.\d+)').firstMatch(line);
            if (maskMatch != null && lastIp != null) {
              final maskStr = maskMatch.group(1)!;
              final prefix = _subnetMaskStringToPrefix(maskStr);
              if (prefix != null) {
                map[lastIp] = prefix;
              }
              lastIp = null;
            }
          }
        }
      } catch (_) {}
    }

    return map;
  }

  /// Detects default gateway IP per interface where available.
  Future<Map<String, String>> _detectDefaultGateways() async {
    final map = <String, String>{};
    if (Platform.isLinux) {
      try {
        final result = await Process.run('ip', ['route', 'show', 'default']);
        if (result.exitCode == 0) {
          for (final line in (result.stdout as String).split('\n')) {
            final viaMatch = RegExp(r'default\s+via\s+(\d+\.\d+\.\d+\.\d+)').firstMatch(line);
            final devMatch = RegExp(r'dev\s+(\S+)').firstMatch(line);
            if (viaMatch != null) {
              final gw = viaMatch.group(1)!;
              map.putIfAbsent('default', () => gw);
              if (devMatch != null) {
                map[devMatch.group(1)!] = gw;
              }
            }
          }
        }
      } catch (_) {}
    } else if (Platform.isMacOS) {
      try {
        final result = await Process.run('route', ['-n', 'get', 'default']);
        if (result.exitCode == 0) {
          final gwMatch = RegExp(r'gateway:\s*(\d+\.\d+\.\d+\.\d+)').firstMatch(result.stdout as String);
          final ifMatch = RegExp(r'interface:\s*(\S+)').firstMatch(result.stdout as String);
          if (gwMatch != null) {
            final gw = gwMatch.group(1)!;
            map['default'] = gw;
            if (ifMatch != null) {
              map[ifMatch.group(1)!] = gw;
            }
          }
        }
      } catch (_) {}
    }
    return map;
  }

  static int _netmaskIntToPrefix(int mask) {
    int count = 0;
    for (int i = 31; i >= 0; i--) {
      if ((mask & (1 << i)) != 0) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  static int? _subnetMaskStringToPrefix(String mask) {
    final parts = mask.split('.').map((s) => int.tryParse(s)).toList();
    if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) return null;
    final val = ((parts[0]! << 24) | (parts[1]! << 16) | (parts[2]! << 8) | parts[3]!) & 0xFFFFFFFF;
    return _netmaskIntToPrefix(val);
  }

  /// Checks if the process has elevated root/administrator privileges or CAP_NET_BIND_SERVICE on Linux.
  Future<bool> checkHasElevatedPrivileges() async {
    if (Platform.isWindows) {
      try {
        // 'net session' exits with 0 if running with Administrator privileges
        final result = await Process.run('net', ['session']);
        return result.exitCode == 0;
      } catch (_) {
        return false;
      }
    }

    if (Platform.isLinux) {
      try {
        final statusFile = File('/proc/self/status');
        if (await statusFile.exists()) {
          final content = await statusFile.readAsString();
          final capMatch = RegExp(r'CapEff:\s*([0-9a-fA-F]+)').firstMatch(content);
          if (capMatch != null) {
            final capEff = BigInt.tryParse(capMatch.group(1)!, radix: 16);
            // Bit 10 is CAP_NET_BIND_SERVICE
            if (capEff != null && (capEff & (BigInt.one << 10)) != BigInt.zero) {
              return true;
            }
          }
        }
      } catch (_) {}
    }

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
