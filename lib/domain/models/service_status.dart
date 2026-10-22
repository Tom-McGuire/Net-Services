enum ServiceState { stopped, running, error }

class ServiceStatus {
  final ServiceState state;
  final int port;
  final String? lastError;
  final DateTime? startedAt;

  const ServiceStatus({
    this.state = ServiceState.stopped,
    required this.port,
    this.lastError,
    this.startedAt,
  });

  bool get isRunning => state == ServiceState.running;
  bool get hasError => state == ServiceState.error;

  ServiceStatus copyWith({
    ServiceState? state,
    int? port,
    String? lastError,
    DateTime? startedAt,
  }) {
    return ServiceStatus(
      state: state ?? this.state,
      port: port ?? this.port,
      lastError: lastError,
      startedAt: startedAt ?? this.startedAt,
    );
  }
}
