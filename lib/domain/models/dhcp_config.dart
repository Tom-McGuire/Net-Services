import 'dart:io';

class DhcpConfig {
  final String startIp;
  final int poolSize;
  final String subnetMask;
  final String gatewayIp;
  final String dnsServerIp;
  final int leaseTimeSeconds;

  static const DhcpConfig defaultConfig = DhcpConfig(
    startIp: '192.168.1.100',
    poolSize: 20,
    subnetMask: '255.255.255.0',
    gatewayIp: '192.168.1.1',
    dnsServerIp: '192.168.1.1',
    leaseTimeSeconds: 86400,
  );

  const DhcpConfig({
    required this.startIp,
    this.poolSize = 20,
    required this.subnetMask,
    required this.gatewayIp,
    required this.dnsServerIp,
    this.leaseTimeSeconds = 86400, // 24 hours
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
  }) {
    return DhcpConfig(
      startIp: startIp ?? this.startIp,
      poolSize: poolSize ?? this.poolSize,
      subnetMask: subnetMask ?? this.subnetMask,
      gatewayIp: gatewayIp ?? this.gatewayIp,
      dnsServerIp: dnsServerIp ?? this.dnsServerIp,
      leaseTimeSeconds: leaseTimeSeconds ?? this.leaseTimeSeconds,
    );
  }

  /// Validates the DHCP configuration and returns a list of error messages (empty if valid).
  List<String> validate() {
    final errors = <String>[];

    final startAddr = InternetAddress.tryParse(startIp);
    if (startAddr == null || startAddr.type != InternetAddressType.IPv4) {
      errors.add('Start IP must be a valid IPv4 address.');
    }

    final maskAddr = InternetAddress.tryParse(subnetMask);
    if (maskAddr == null || maskAddr.type != InternetAddressType.IPv4) {
      errors.add('Subnet mask must be a valid IPv4 address.');
    }

    final gatewayAddr = InternetAddress.tryParse(gatewayIp);
    if (gatewayAddr == null || gatewayAddr.type != InternetAddressType.IPv4) {
      errors.add('Gateway IP must be a valid IPv4 address.');
    }

    final dnsAddr = InternetAddress.tryParse(dnsServerIp);
    if (dnsAddr == null || dnsAddr.type != InternetAddressType.IPv4) {
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
      }
    }

    return errors;
  }

  static bool _isValidSubnetMask(int mask) {
    if (mask == 0) return false;
    final inverted = (~mask) & 0xFFFFFFFF;
    return (inverted & (inverted + 1)) == 0;
  }

  static int ipToNum(String ip) {
    final parts = ip.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    if (parts.length != 4) return 0;
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }

  static String numToIp(int num) {
    final o1 = (num >> 24) & 0xFF;
    final o2 = (num >> 16) & 0xFF;
    final o3 = (num >> 8) & 0xFF;
    final o4 = num & 0xFF;
    return '$o1.$o2.$o3.$o4';
  }
}
