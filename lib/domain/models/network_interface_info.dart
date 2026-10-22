class NetworkInterfaceInfo {
  final String name;
  final String ip;
  final String subnetMask;
  final int prefixLength;

  const NetworkInterfaceInfo({
    required this.name,
    required this.ip,
    required this.subnetMask,
    required this.prefixLength,
  });

  /// Calculates the next sequential IP address (Host IP + 1).
  String get hostIpPlusOne {
    final parts = ip.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    if (parts.length != 4) return '192.168.1.100';

    int ipNum = (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
    int nextIpNum = ipNum + 1;

    final o1 = (nextIpNum >> 24) & 0xFF;
    final o2 = (nextIpNum >> 16) & 0xFF;
    final o3 = (nextIpNum >> 8) & 0xFF;
    final o4 = nextIpNum & 0xFF;

    return '$o1.$o2.$o3.$o4';
  }

  /// Helper to convert a CIDR prefix length (e.g. 24) to a subnet mask string (e.g. '255.255.255.0').
  static String prefixToSubnetMask(int prefix) {
    if (prefix <= 0) return '0.0.0.0';
    if (prefix >= 32) return '255.255.255.255';
    final mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    final o1 = (mask >> 24) & 0xFF;
    final o2 = (mask >> 16) & 0xFF;
    final o3 = (mask >> 8) & 0xFF;
    final o4 = mask & 0xFF;
    return '$o1.$o2.$o3.$o4';
  }
}
