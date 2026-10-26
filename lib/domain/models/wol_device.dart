class WolDevice {
  final String id;
  final String name;
  final String macAddress;
  final String? ipAddress;
  final int port;
  final String broadcastAddress;
  final DateTime? lastWoken;

  const WolDevice({
    required this.id,
    required this.name,
    required this.macAddress,
    this.ipAddress,
    this.port = 9,
    this.broadcastAddress = '255.255.255.255',
    this.lastWoken,
  });

  WolDevice copyWith({
    String? id,
    String? name,
    String? macAddress,
    String? ipAddress,
    int? port,
    String? broadcastAddress,
    DateTime? lastWoken,
  }) {
    return WolDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      macAddress: macAddress ?? this.macAddress,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      broadcastAddress: broadcastAddress ?? this.broadcastAddress,
      lastWoken: lastWoken ?? this.lastWoken,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'macAddress': macAddress,
      'ipAddress': ipAddress,
      'port': port,
      'broadcastAddress': broadcastAddress,
      'lastWoken': lastWoken?.toIso8601String(),
    };
  }

  factory WolDevice.fromJson(Map<String, dynamic> json) {
    return WolDevice(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Unnamed Device',
      macAddress: json['macAddress'] as String? ?? '',
      ipAddress: json['ipAddress'] as String?,
      port: (json['port'] as num?)?.toInt() ?? 9,
      broadcastAddress: json['broadcastAddress'] as String? ?? '255.255.255.255',
      lastWoken: json['lastWoken'] != null ? DateTime.tryParse(json['lastWoken'] as String) : null,
    );
  }

  /// Normalizes MAC address string to standard format: AA:BB:CC:DD:EE:FF
  static String? normalizeMac(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    if (cleaned.length != 12) return null;

    final parts = <String>[];
    for (int i = 0; i < 12; i += 2) {
      parts.add(cleaned.substring(i, i + 2));
    }
    return parts.join(':');
  }

  /// Validates if a string is a valid MAC address
  static bool isValidMac(String mac) {
    return normalizeMac(mac) != null;
  }
}
