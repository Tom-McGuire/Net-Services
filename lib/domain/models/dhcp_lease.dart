class DhcpLease {
  final String macAddress;
  final String ipAddress;
  final String hostname;
  final DateTime leaseStart;
  final int leaseDurationSeconds;
  final String? friendlyName;
  final bool isStatic;

  const DhcpLease({
    required this.macAddress,
    required this.ipAddress,
    required this.hostname,
    required this.leaseStart,
    required this.leaseDurationSeconds,
    this.friendlyName,
    this.isStatic = false,
  });

  DateTime get leaseExpiry => leaseStart.add(Duration(seconds: leaseDurationSeconds));

  bool get isExpired => isStatic ? false : DateTime.now().isAfter(leaseExpiry);

  Duration get remainingDuration {
    if (isStatic) return const Duration(days: 3650);
    final diff = leaseExpiry.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String get displayName => (friendlyName != null && friendlyName!.trim().isNotEmpty)
      ? friendlyName!.trim()
      : (hostname.isNotEmpty ? hostname : 'Device $macAddress');

  DhcpLease copyWith({
    String? macAddress,
    String? ipAddress,
    String? hostname,
    DateTime? leaseStart,
    int? leaseDurationSeconds,
    String? friendlyName,
    bool? isStatic,
  }) {
    return DhcpLease(
      macAddress: macAddress ?? this.macAddress,
      ipAddress: ipAddress ?? this.ipAddress,
      hostname: hostname ?? this.hostname,
      leaseStart: leaseStart ?? this.leaseStart,
      leaseDurationSeconds: leaseDurationSeconds ?? this.leaseDurationSeconds,
      friendlyName: friendlyName ?? this.friendlyName,
      isStatic: isStatic ?? this.isStatic,
    );
  }
}
