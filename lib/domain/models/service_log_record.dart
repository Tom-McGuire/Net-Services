enum ServiceType { dns, ntp, dhcp, system }
enum LogSeverity { info, warning, error, success }

class ServiceLogRecord {
  final String id;
  final DateTime timestamp;
  final ServiceType serviceType;
  final LogSeverity severity;
  final String action;
  final String summary;
  final String? clientAddress;
  final String? details;

  const ServiceLogRecord({
    required this.id,
    required this.timestamp,
    required this.serviceType,
    this.severity = LogSeverity.info,
    required this.action,
    required this.summary,
    this.clientAddress,
    this.details,
  });

  String get serviceName {
    switch (serviceType) {
      case ServiceType.dns:
        return 'DNS';
      case ServiceType.ntp:
        return 'NTP';
      case ServiceType.dhcp:
        return 'DHCP';
      case ServiceType.system:
        return 'SYSTEM';
    }
  }
}
