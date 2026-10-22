import '../../../domain/models/dhcp_config.dart';
import '../../../domain/models/dhcp_lease.dart';

class DhcpLeaseManager {
  DhcpConfig _config;
  final Map<String, DhcpLease> _leasesByMac = {};

  DhcpLeaseManager({required DhcpConfig config}) : _config = config; // ignore: prefer_initializing_formals

  DhcpConfig get config => _config;

  void updateConfig(DhcpConfig config) {
    _config = config;
  }

  List<DhcpLease> get activeLeases {
    _pruneExpired();
    return List.unmodifiable(_leasesByMac.values.toList());
  }

  /// Allocates or renews a lease for the given MAC address
  DhcpLease? allocateOrGetLease(
    String mac, {
    String? requestedIp,
    String? hostname,
  }) {
    _pruneExpired();

    // 1. Check if MAC already holds an active lease
    final existing = _leasesByMac[mac];
    if (existing != null) {
      final renewed = existing.copyWith(
        leaseStart: DateTime.now(),
        hostname: (hostname != null && hostname.isNotEmpty) ? hostname : existing.hostname,
        leaseDurationSeconds: _config.leaseTimeSeconds,
      );
      _leasesByMac[mac] = renewed;
      return renewed;
    }

    // 2. Check if requested IP is within pool range and available
    if (requestedIp != null && _isIpInPool(requestedIp) && !_isIpAssigned(requestedIp)) {
      final lease = DhcpLease(
        macAddress: mac,
        ipAddress: requestedIp,
        hostname: hostname ?? 'Unknown',
        leaseStart: DateTime.now(),
        leaseDurationSeconds: _config.leaseTimeSeconds,
      );
      _leasesByMac[mac] = lease;
      return lease;
    }

    // 3. Sequential search for next available IP in pool
    final assignedIps = _leasesByMac.values.map((l) => l.ipAddress).toSet();
    final startNum = _ipToNum(_config.startIp);
    final totalPool = _config.poolSize;

    for (int i = 0; i < totalPool; i++) {
      final candidateIp = _numToIp(startNum + i);
      if (!assignedIps.contains(candidateIp)) {
        final lease = DhcpLease(
          macAddress: mac,
          ipAddress: candidateIp,
          hostname: hostname ?? 'Unknown',
          leaseStart: DateTime.now(),
          leaseDurationSeconds: _config.leaseTimeSeconds,
        );
        _leasesByMac[mac] = lease;
        return lease;
      }
    }

    return null; // Pool exhausted
  }

  void releaseLease(String mac) {
    _leasesByMac.remove(mac);
  }

  void clearAll() {
    _leasesByMac.clear();
  }

  void _pruneExpired() {
    _leasesByMac.removeWhere((_, lease) => lease.isExpired);
  }

  bool _isIpAssigned(String ip) {
    return _leasesByMac.values.any((l) => l.ipAddress == ip);
  }

  bool _isIpInPool(String ip) {
    final ipNum = _ipToNum(ip);
    final startNum = _ipToNum(_config.startIp);
    final endNum = startNum + _config.poolSize - 1;
    return ipNum >= startNum && ipNum <= endNum;
  }

  int _ipToNum(String ip) {
    final parts = ip.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    if (parts.length != 4) return 0;
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }

  String _numToIp(int num) {
    final o1 = (num >> 24) & 0xFF;
    final o2 = (num >> 16) & 0xFF;
    final o3 = (num >> 8) & 0xFF;
    final o4 = num & 0xFF;
    return '$o1.$o2.$o3.$o4';
  }
}
