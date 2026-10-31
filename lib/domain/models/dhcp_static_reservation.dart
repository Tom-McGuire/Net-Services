class DhcpStaticReservation {
  final String macAddress;
  final String ipAddress;
  final String? deviceName;

  const DhcpStaticReservation({
    required this.macAddress,
    required this.ipAddress,
    this.deviceName,
  });

  Map<String, dynamic> toJson() => {
    'macAddress': macAddress,
    'ipAddress': ipAddress,
    'deviceName': deviceName,
  };

  factory DhcpStaticReservation.fromJson(Map<String, dynamic> json) => DhcpStaticReservation(
    macAddress: json['macAddress'] as String? ?? '',
    ipAddress: json['ipAddress'] as String? ?? '',
    deviceName: json['deviceName'] as String?,
  );

  DhcpStaticReservation copyWith({
    String? macAddress,
    String? ipAddress,
    String? deviceName,
  }) {
    return DhcpStaticReservation(
      macAddress: macAddress ?? this.macAddress,
      ipAddress: ipAddress ?? this.ipAddress,
      deviceName: deviceName ?? this.deviceName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DhcpStaticReservation &&
          runtimeType == other.runtimeType &&
          macAddress.toUpperCase() == other.macAddress.toUpperCase();

  @override
  int get hashCode => macAddress.toUpperCase().hashCode;
}
