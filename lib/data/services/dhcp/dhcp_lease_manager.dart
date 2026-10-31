import 'package:network_suite_shared/network_suite_shared.dart';
import '../../../domain/models/dhcp_config.dart';
import '../../../domain/models/dhcp_lease.dart';
import '../../../domain/models/dhcp_static_reservation.dart';

class _TentativeReservation {
  final String ipAddress;
  final String? hostname;
  final DateTime expiresAt;

  _TentativeReservation({
    required this.ipAddress,
    this.hostname,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class DhcpLeaseManager {
  DhcpConfig _config;
  final Map<String, DhcpLease> _leasesByMac = {};
  final Map<String, _TentativeReservation> _reservationsByMac = {};
  final Set<String> _declinedIps = {};

  DhcpLeaseManager({required DhcpConfig config}) : _config = config; // ignore: prefer_initializing_formals

  DhcpConfig get config => _config;

  DhcpStaticReservation? _findStaticReservation(String mac) {
    final norm = SharedDevice.normalizeMac(mac);
    for (final res in _config.staticReservations) {
      if (SharedDevice.normalizeMac(res.macAddress) == norm) {
        return res;
      }
    }
    return null;
  }

  bool _isIpStaticallyReserved(String ip, [String? forMac]) {
    final normForMac = forMac != null ? SharedDevice.normalizeMac(forMac) : null;
    for (final res in _config.staticReservations) {
      if (res.ipAddress == ip) {
        if (normForMac == null || SharedDevice.normalizeMac(res.macAddress) != normForMac) {
          return true;
        }
      }
    }
    return false;
  }

  void updateConfig(DhcpConfig config) {
    _config = config;
    _pruneExpired();
    // Prune any non-static leases and reservations that are outside the new pool
    _leasesByMac.removeWhere((_, lease) => !lease.isStatic && !_isIpInPool(lease.ipAddress));
    _reservationsByMac.removeWhere((_, res) => !_isIpInPool(res.ipAddress));

    // Update existing leases with any new static reservation information
    for (final entry in _leasesByMac.entries) {
      final staticRes = _findStaticReservation(entry.key);
      if (staticRes != null) {
        _leasesByMac[entry.key] = entry.value.copyWith(
          isStatic: true,
          friendlyName: staticRes.deviceName ?? entry.value.friendlyName,
        );
      } else if (entry.value.isStatic) {
        _leasesByMac[entry.key] = entry.value.copyWith(isStatic: false);
      }
    }
  }

  List<DhcpLease> get activeLeases {
    _pruneExpired();
    return List.unmodifiable(_leasesByMac.values.toList());
  }

  /// Reserves an IP address tentatively (60s) for DHCPOFFER in response to DHCPDISCOVER.
  /// Does NOT commit a full-length lease (preventing DHCP pool starvation).
  String? reserveOrGetOffer(
    String mac, {
    String? requestedIp,
    String? hostname,
    Duration reservationDuration = const Duration(seconds: 60),
  }) {
    _pruneExpired();
    final normMac = SharedDevice.normalizeMac(mac);

    // 0. Static Reservation check
    final staticRes = _findStaticReservation(normMac);
    if (staticRes != null) {
      return staticRes.ipAddress;
    }

    // 1. If MAC already has an active lease, offer that same IP
    final existingLease = _leasesByMac[normMac];
    if (existingLease != null && _isIpInPool(existingLease.ipAddress)) {
      return existingLease.ipAddress;
    }

    // 2. If MAC already has a tentative reservation, reuse it
    final existingRes = _reservationsByMac[normMac];
    if (existingRes != null && !existingRes.isExpired && _isIpInPool(existingRes.ipAddress)) {
      return existingRes.ipAddress;
    }

    // 3. If requested IP is valid, in pool, and not assigned, reserved, or statically assigned to another MAC
    if (requestedIp != null &&
        _isIpInPool(requestedIp) &&
        !_isIpAssignedOrReserved(requestedIp) &&
        !_isIpStaticallyReserved(requestedIp, normMac) &&
        !_declinedIps.contains(requestedIp)) {
      _reservationsByMac[normMac] = _TentativeReservation(
        ipAddress: requestedIp,
        hostname: hostname,
        expiresAt: DateTime.now().add(reservationDuration),
      );
      return requestedIp;
    }

    // 4. Find next available IP in pool (excluding statically reserved IPs)
    final assignedOrReserved = _allUsedIps();
    final startNum = DhcpConfig.ipToNum(_config.startIp);
    final totalPool = _config.poolSize;

    for (int i = 0; i < totalPool; i++) {
      final candidateIp = DhcpConfig.numToIp(startNum + i);
      if (!assignedOrReserved.contains(candidateIp) &&
          !_isIpStaticallyReserved(candidateIp, normMac) &&
          !_declinedIps.contains(candidateIp)) {
        _reservationsByMac[normMac] = _TentativeReservation(
          ipAddress: candidateIp,
          hostname: hostname,
          expiresAt: DateTime.now().add(reservationDuration),
        );
        return candidateIp;
      }
    }

    return null; // Pool exhausted
  }

  /// Confirms and commits a full DHCP lease on DHCPREQUEST.
  /// Returns the committed [DhcpLease], or null if invalid/unavailable (leading to DHCPNAK).
  DhcpLease? confirmLease(
    String mac, {
    String? requestedIp,
    String? hostname,
    String? friendlyName,
  }) {
    _pruneExpired();
    final normMac = SharedDevice.normalizeMac(mac);

    // Check static reservation
    final staticRes = _findStaticReservation(normMac);
    if (staticRes != null) {
      final lease = DhcpLease(
        macAddress: normMac,
        ipAddress: staticRes.ipAddress,
        hostname: (hostname != null && hostname.isNotEmpty) ? hostname : (staticRes.deviceName ?? 'Unknown'),
        leaseStart: DateTime.now(),
        leaseDurationSeconds: _config.leaseTimeSeconds,
        friendlyName: staticRes.deviceName ?? friendlyName,
        isStatic: true,
      );
      _leasesByMac[normMac] = lease;
      _reservationsByMac.remove(normMac);
      return lease;
    }

    // Check existing lease for this MAC
    final existing = _leasesByMac[normMac];
    if (existing != null) {
      if (requestedIp != null && requestedIp != existing.ipAddress) {
        // Client requested a different IP than its assigned lease!
        return null;
      }
      final renewed = existing.copyWith(
        leaseStart: DateTime.now(),
        hostname: (hostname != null && hostname.isNotEmpty) ? hostname : existing.hostname,
        leaseDurationSeconds: _config.leaseTimeSeconds,
        friendlyName: friendlyName ?? existing.friendlyName,
      );
      _leasesByMac[normMac] = renewed;
      _reservationsByMac.remove(normMac);
      return renewed;
    }

    // Check tentative reservation for this MAC
    final reservation = _reservationsByMac[normMac];
    final targetIp = requestedIp ?? reservation?.ipAddress;

    if (targetIp == null ||
        !_isIpInPool(targetIp) ||
        _declinedIps.contains(targetIp) ||
        _isIpStaticallyReserved(targetIp, normMac)) {
      return null;
    }

    // If another MAC already holds an active lease on this IP, refuse
    final currentHolder = _leasesByMac.entries
        .where((e) => e.value.ipAddress == targetIp && e.key != normMac)
        .map((e) => e.key)
        .firstOrNull;
    if (currentHolder != null) {
      return null;
    }

    final lease = DhcpLease(
      macAddress: normMac,
      ipAddress: targetIp,
      hostname: hostname ?? reservation?.hostname ?? 'Unknown',
      leaseStart: DateTime.now(),
      leaseDurationSeconds: _config.leaseTimeSeconds,
      friendlyName: friendlyName,
      isStatic: false,
    );

    _leasesByMac[normMac] = lease;
    _reservationsByMac.remove(normMac);
    return lease;
  }

  /// Backward-compatible helper method for tests or simple allocation.
  DhcpLease? allocateOrGetLease(
    String mac, {
    String? requestedIp,
    String? hostname,
    String? friendlyName,
  }) {
    final offerIp = reserveOrGetOffer(mac, requestedIp: requestedIp, hostname: hostname);
    if (offerIp == null) return null;
    return confirmLease(mac, requestedIp: offerIp, hostname: hostname, friendlyName: friendlyName);
  }

  void declineIp(String ip) {
    _declinedIps.add(ip);
    _leasesByMac.removeWhere((_, l) => l.ipAddress == ip);
    _reservationsByMac.removeWhere((_, r) => r.ipAddress == ip);
  }

  void releaseLease(String mac, {String? expectedIp}) {
    final normMac = SharedDevice.normalizeMac(mac);
    if (expectedIp != null) {
      final lease = _leasesByMac[normMac];
      if (lease != null && lease.ipAddress != expectedIp) {
        return; // Ignore RELEASE if ciaddr doesn't match leased IP
      }
    }
    _leasesByMac.remove(normMac);
    _reservationsByMac.remove(normMac);
  }

  void clearAll() {
    _leasesByMac.clear();
    _reservationsByMac.clear();
    _declinedIps.clear();
  }

  void _pruneExpired() {
    _leasesByMac.removeWhere((_, lease) => !lease.isStatic && lease.isExpired);
    _reservationsByMac.removeWhere((_, res) => res.isExpired);
  }

  bool _isIpAssignedOrReserved(String ip) {
    if (_leasesByMac.values.any((l) => l.ipAddress == ip)) return true;
    if (_reservationsByMac.values.any((r) => r.ipAddress == ip && !r.isExpired)) return true;
    return false;
  }

  Set<String> _allUsedIps() {
    final used = <String>{};
    for (final l in _leasesByMac.values) {
      used.add(l.ipAddress);
    }
    for (final r in _reservationsByMac.values) {
      if (!r.isExpired) used.add(r.ipAddress);
    }
    return used;
  }

  bool _isIpInPool(String ip) {
    final ipNum = DhcpConfig.ipToNum(ip);
    final startNum = DhcpConfig.ipToNum(_config.startIp);
    final endNum = startNum + _config.poolSize - 1;
    return ipNum >= startNum && ipNum <= endNum;
  }
}
