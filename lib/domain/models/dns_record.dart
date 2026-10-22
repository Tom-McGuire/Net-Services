class DnsRecord {
  final String domain;
  final String ip;
  final int ttl;

  const DnsRecord({
    required this.domain,
    required this.ip,
    this.ttl = 300,
  });

  DnsRecord copyWith({
    String? domain,
    String? ip,
    int? ttl,
  }) {
    return DnsRecord(
      domain: domain ?? this.domain,
      ip: ip ?? this.ip,
      ttl: ttl ?? this.ttl,
    );
  }

  Map<String, dynamic> toJson() => {
    'domain': domain,
    'ip': ip,
    'ttl': ttl,
  };

  factory DnsRecord.fromJson(Map<String, dynamic> json) => DnsRecord(
    domain: json['domain'] as String,
    ip: json['ip'] as String,
    ttl: json['ttl'] as int? ?? 300,
  );
}
