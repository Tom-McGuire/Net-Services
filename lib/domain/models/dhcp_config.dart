import 'dart:io';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'dhcp_static_reservation.dart';

class DhcpConfig {
  final String startIp;
  final int poolSize;
  final String subnetMask;
  final String gatewayIp;
  final String dnsServerIp;
  final int leaseTimeSeconds;
  final bool useLocalDns;
  final List<DhcpStaticReservation> staticReservations;

  static const DhcpConfig defaultConfig = DhcpConfig(
    startIp: '192.168.1.100',
    poolSize: 20,
    subnetMask: '255.255.255.0',
    gatewayIp: '192.168.1.1',
    dnsServerIp: '192.168.1.1',
    leaseTimeSeconds: 86400,
    useLocalDns: false,
    staticReservations: [],
  );

  const DhcpConfig({
    required this.startIp,
    this.poolSize = 20,
    required this.subnetMask,
    required this.gatewayIp,
    required this.dnsServerIp,
    this.leaseTimeSeconds = 86400, // 24 hours
    this.useLocalDns = false,
    this.staticReservations = const [],
  });

  /// Dynamically computes the last address based on startIp and poolSize.
  String get endIp {
    final startNum = ipToNum(startIp);
    if (startNum == 0 || poolSize <= 0) return startIp;

    final endIpNum = startNum + poolSize - 1;
    return numToIp(endIpNum);
  }

  DhcpConfig copyWith({
    String? startIp,
    int? poolSize,
    String? subnetMask,
    String? gatewayIp,
    String? dnsServerIp,
    int? leaseTimeSeconds,
    bool? useLocalDns,
    List<DhcpStaticReservation>? staticReservations,
  }) {
    return DhcpConfig(
      startIp: startIp ?? this.startIp,
      poolSize: poolSize ?? this.poolSize,
      subnetMask: subnetMask ?? this.subnetMask,
      gatewayIp: gatewayIp ?? this.gatewayIp,
      dnsServerIp: dnsServerIp ?? this.dnsServerIp,
      leaseTimeSeconds: leaseTimeSeconds ?? this.leaseTimeSeconds,
      useLocalDns: useLocalDns ?? this.useLocalDns,
      staticReservations: staticReservations ?? this.staticReservations,
    );
  }

  /// Validates the DHCP configuration and returns a list of error messages (empty if valid).
  List<String> validate({String? serverIp}) {
    final errors = <String>[];

    final startAddr = InternetAddress.tryParse(startIp);
    if (startAddr == null || startAddr.type != InternetAddressType.IPv4 || ipToNum(startIp) == 0) {
      errors.add('Start IP must be a valid IPv4 address.');
    }

    final maskAddr = InternetAddress.tryParse(subnetMask);
    if (maskAddr == null || maskAddr.type != InternetAddressType.IPv4 || ipToNum(subnetMask) == 0) {
      errors.add('Subnet mask must be a valid IPv4 address.');
    }

    final gatewayAddr = InternetAddress.tryParse(gatewayIp);
    if (gatewayAddr == null || gatewayAddr.type != InternetAddressType.IPv4 || ipToNum(gatewayIp) == 0) {
      errors.add('Gateway IP must be a valid IPv4 address.');
    }

    final dnsAddr = InternetAddress.tryParse(dnsServerIp);
    if (dnsAddr == null || dnsAddr.type != InternetAddressType.IPv4 || ipToNum(dnsServerIp) == 0) {
      errors.add('DNS Server IP must be a valid IPv4 address.');
    }

    if (poolSize < 1) {
      errors.add('Pool size must be at least 1.');
    } else if (poolSize > 1024) {
      errors.add('Pool size cannot exceed 1024 addresses.');
    }

    if (leaseTimeSeconds < 60) {
      errors.add('Lease duration must be at least 60 seconds.');
    }

    // Advanced subnet boundary checks if IPs and mask are valid
    if (errors.isEmpty) {
      final startNum = ipToNum(startIp);
      final maskNum = ipToNum(subnetMask);
      final gatewayNum = ipToNum(gatewayIp);
      final endNum = startNum + poolSize - 1;
      final serverNum = (serverIp != null && serverIp != '0.0.0.0' && serverIp != '127.0.0.1')
          ? ipToNum(serverIp)
          : 0;

      // Ensure subnet mask is contiguous
      if (!_isValidSubnetMask(maskNum)) {
        errors.add('Subnet mask is not a contiguous netmask.');
      } else {
        final networkNum = startNum & maskNum;
        final broadcastNum = networkNum | (~maskNum & 0xFFFFFFFF);

        // Check if startIp and gateway are in the same subnet
        if ((gatewayNum & maskNum) != networkNum) {
          errors.add('Start IP and Gateway IP are on different subnets.');
        }

        // Check if endIp crosses subnet boundary
        if ((endNum & maskNum) != networkNum) {
          errors.add('IP pool range crosses the subnet boundary.');
        }

        // Check network or broadcast address collision
        if (startNum <= networkNum) {
          errors.add('IP pool includes the network address.');
        }
        if (endNum >= broadcastNum) {
          errors.add('IP pool includes the broadcast address.');
        }

        // Check gateway collision
        if (gatewayNum >= startNum && gatewayNum <= endNum) {
          errors.add('IP pool contains the gateway IP address ($gatewayIp).');
        }

        // Validate static reservations within the subnet
        final seenMacs = <String>{};
        final seenIps = <String>{};
        for (final res in staticReservations) {
          final normalized = SharedDevice.normalizeMac(res.macAddress);
          if (!SharedDevice.isValidMac(normalized)) {
            errors.add('Static reservation MAC "${res.macAddress}" is invalid.');
          } else if (!seenMacs.add(normalized)) {
            errors.add('Duplicate static reservation for MAC "$normalized".');
          }

          final resIp = InternetAddress.tryParse(res.ipAddress);
          final resNum = ipToNum(res.ipAddress);
          if (resIp == null || resIp.type != InternetAddressType.IPv4 || resNum == 0) {
            errors.add('Static reservation IP "${res.ipAddress}" is not a valid IPv4 address.');
          } else {
            if (!seenIps.add(res.ipAddress.trim())) {
              errors.add('Duplicate static reservation IP "${res.ipAddress}".');
            }
            if ((resNum & maskNum) != networkNum) {
              errors.add('Static reservation IP ${res.ipAddress} is outside the configured subnet.');
            }
            if (resNum <= networkNum || resNum >= broadcastNum) {
              errors.add('Static reservation IP ${res.ipAddress} cannot be the network or broadcast address.');
            }
            if (resNum == gatewayNum) {
              errors.add('Static reservation cannot use gateway IP ($gatewayIp).');
            }
            if (serverNum != 0 && resNum == serverNum) {
              errors.add('Static reservation cannot use host server IP ($serverIp).');
            }
          }
        }
      }
    }

    return errors;
  }

  Map<String, dynamic> toJson() => {
    'startIp': startIp,
    'poolSize': poolSize,
    'subnetMask': subnetMask,
    'gatewayIp': gatewayIp,
    'dnsServerIp': dnsServerIp,
    'leaseTimeSeconds': leaseTimeSeconds,
    'useLocalDns': useLocalDns,
    'staticReservations': staticReservations.map((r) => r.toJson()).toList(),
  };

  factory DhcpConfig.fromJson(Map<String, dynamic> json) {
    final rawReservations = json['staticReservations'] as List<dynamic>? ?? const [];
    return DhcpConfig(
      startIp: json['startIp'] as String? ?? defaultConfig.startIp,
      poolSize: json['poolSize'] as int? ?? defaultConfig.poolSize,
      subnetMask: json['subnetMask'] as String? ?? defaultConfig.subnetMask,
      gatewayIp: json['gatewayIp'] as String? ?? defaultConfig.gatewayIp,
      dnsServerIp: json['dnsServerIp'] as String? ?? defaultConfig.dnsServerIp,
      leaseTimeSeconds: json['leaseTimeSeconds'] as int? ?? defaultConfig.leaseTimeSeconds,
      useLocalDns: json['useLocalDns'] as bool? ?? defaultConfig.useLocalDns,
      staticReservations: rawReservations
          .whereType<Map<String, dynamic>>()
          .map(DhcpStaticReservation.fromJson)
          .toList(),
    );
  }

  static bool _isValidSubnetMask(int mask) {
    if (mask == 0) return false;
    final inverted = (~mask) & 0xFFFFFFFF;
    return (inverted & (inverted + 1)) == 0;
  }

  static int ipToNum(String ip) {
    final rawParts = ip.trim().split('.');
    if (rawParts.length != 4) return 0;
    final parts = <int>[];
    for (final s in rawParts) {
      final v = int.tryParse(s);
      if (v == null || v < 0 || v > 255) return 0;
      parts.add(v);
    }
    return ((parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]) & 0xFFFFFFFF;
  }

  static String numToIp(int num) {
    final o1 = (num >> 24) & 0xFF;
    final o2 = (num >> 16) & 0xFF;
    final o3 = (num >> 8) & 0xFF;
    final o4 = num & 0xFF;
    return '$o1.$o2.$o3.$o4';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DhcpConfig) return false;
    if (startIp != other.startIp ||
        poolSize != other.poolSize ||
        subnetMask != other.subnetMask ||
        gatewayIp != other.gatewayIp ||
        dnsServerIp != other.dnsServerIp ||
        leaseTimeSeconds != other.leaseTimeSeconds ||
        useLocalDns != other.useLocalDns ||
        staticReservations.length != other.staticReservations.length) {
      return false;
    }
    for (int i = 0; i < staticReservations.length; i++) {
      final a = staticReservations[i];
      final b = other.staticReservations[i];
      if (a.macAddress.toUpperCase() != b.macAddress.toUpperCase() ||
          a.ipAddress != b.ipAddress ||
          a.deviceName != b.deviceName) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        startIp,
        poolSize,
        subnetMask,
        gatewayIp,
        dnsServerIp,
        leaseTimeSeconds,
        useLocalDns,
        staticReservations.length,
      );
}
