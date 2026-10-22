class DhcpConfig {
  final String startIp;
  final int poolSize;
  final String subnetMask;
  final String gatewayIp;
  final String dnsServerIp;
  final int leaseTimeSeconds;

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
    final parts = startIp.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    if (parts.length != 4 || poolSize <= 0) return startIp;

    int ipNum = (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
    int endIpNum = ipNum + poolSize - 1;

    final o1 = (endIpNum >> 24) & 0xFF;
    final o2 = (endIpNum >> 16) & 0xFF;
    final o3 = (endIpNum >> 8) & 0xFF;
    final o4 = endIpNum & 0xFF;

    return '$o1.$o2.$o3.$o4';
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
}
