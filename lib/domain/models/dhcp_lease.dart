class DhcpLease {
  final String macAddress;
  final String ipAddress;
  final String hostname;
  final DateTime leaseStart;
  final int leaseDurationSeconds;

  const DhcpLease({
    required this.macAddress,
    required this.ipAddress,
    required this.hostname,
    required this.leaseStart,
    required this.leaseDurationSeconds,
  });

  DateTime get leaseExpiry => leaseStart.add(Duration(seconds: leaseDurationSeconds));

  bool get isExpired => DateTime.now().isAfter(leaseExpiry);

  Duration get remainingDuration {
    final diff = leaseExpiry.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  DhcpLease copyWith({
    String? macAddress,
    String? ipAddress,
    String? hostname,
    DateTime? leaseStart,
    int? leaseDurationSeconds,
  }) {
    return DhcpLease(
      macAddress: macAddress ?? this.macAddress,
      ipAddress: ipAddress ?? this.ipAddress,
      hostname: hostname ?? this.hostname,
      leaseStart: leaseStart ?? this.leaseStart,
      leaseDurationSeconds: leaseDurationSeconds ?? this.leaseDurationSeconds,
    );
  }
}
