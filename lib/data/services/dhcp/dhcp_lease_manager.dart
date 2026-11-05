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
  final Map<String, DateTime> _declinedIps = {};

  DhcpLeaseManager({required DhcpConfig config}) : _config = config; // ignore: prefer_initializing_formals

  DhcpConfig get config => _config;

  void restoreLeases(List<DhcpLease> leases) {
    for (final lease in leases) {
      if (!lease.isExpired) {
        final normMac = SharedDevice.normalizeMac(lease.macAddress);
        _leasesByMac[normMac] = lease;
      }
    }
    _pruneExpired();
  }

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

  bool _isIpDeclined(String ip) {
    final expiry = _declinedIps[ip];
    if (expiry == null) return false;
    if (DateTime.now().isAfter(expiry)) {
      _declinedIps.remove(ip);
      return false;
    }
    return true;
  }

  void updateConfig(DhcpConfig config) {
    _config = config;
    _pruneExpired();
    // Prune any non-static leases and reservations that are outside the new pool
    _leasesByMac.removeWhere((_, lease) => !lease.isStatic && !_isIpInPool(lease.ipAddress));
    _reservationsByMac.removeWhere((_, res) => !_isIpInPool(res.ipAddress));

    // Evict any lease or tentative reservation whose IP is now statically reserved for a different MAC
    _leasesByMac.removeWhere((mac, lease) => _isIpStaticallyReserved(lease.ipAddress, mac));
    _reservationsByMac.removeWhere((mac, res) => _isIpStaticallyReserved(res.ipAddress, mac));

    // Update existing leases with any new static reservation information
    final macs = _leasesByMac.keys.toList();
    for (final mac in macs) {
      final current = _leasesByMac[mac]!;
      final staticRes = _findStaticReservation(mac);
      if (staticRes != null) {
        _leasesByMac[mac] = current.copyWith(
          ipAddress: staticRes.ipAddress,
          isStatic: true,
          friendlyName: staticRes.deviceName ?? current.friendlyName,
        );
      } else if (current.isStatic) {
        if (_isIpInPool(current.ipAddress)) {
          _leasesByMac[mac] = current.copyWith(isStatic: false);
        } else {
          _leasesByMac.remove(mac);
        }
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

    // 0. Static Reservation check (evicting any conflicting dynamic holder on that IP)
    final staticRes = _findStaticReservation(normMac);
    if (staticRes != null) {
      _leasesByMac.removeWhere((k, v) => k != normMac && v.ipAddress == staticRes.ipAddress);
      _reservationsByMac.removeWhere((k, v) => k != normMac && v.ipAddress == staticRes.ipAddress);
      return staticRes.ipAddress;
    }

    // 1. If MAC already has an active lease, offer that same IP
    final existingLease = _leasesByMac[normMac];
    if (existingLease != null &&
        _isIpInPool(existingLease.ipAddress) &&
        !_isIpStaticallyReserved(existingLease.ipAddress, normMac) &&
        !_isIpDeclined(existingLease.ipAddress)) {
      return existingLease.ipAddress;
    }

    // 2. If MAC already has a tentative reservation, reuse it
    final existingRes = _reservationsByMac[normMac];
    if (existingRes != null &&
        !existingRes.isExpired &&
        _isIpInPool(existingRes.ipAddress) &&
        !_isIpStaticallyReserved(existingRes.ipAddress, normMac) &&
        !_isIpDeclined(existingRes.ipAddress)) {
      return existingRes.ipAddress;
    }

    // 3. If requested IP is valid, in pool, and not assigned, reserved, or statically assigned to another MAC
    if (requestedIp != null &&
        _isIpInPool(requestedIp) &&
        !_isIpAssignedOrReserved(requestedIp) &&
        !_isIpStaticallyReserved(requestedIp, normMac) &&
        !_isIpDeclined(requestedIp)) {
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
          !_isIpDeclined(candidateIp)) {
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
      if (requestedIp != null && requestedIp != staticRes.ipAddress) {
        // Client requested an IP that does not match its static reservation -> NAK so it re-discovers
        return null;
      }
      // Evict any conflicting dynamic lease or tentative offer holding the static IP
      _leasesByMac.removeWhere((k, v) => k != normMac && v.ipAddress == staticRes.ipAddress);
      _reservationsByMac.removeWhere((k, v) => k != normMac && v.ipAddress == staticRes.ipAddress);

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
      if (_isIpStaticallyReserved(existing.ipAddress, normMac) || _isIpDeclined(existing.ipAddress)) {
        _leasesByMac.remove(normMac);
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
        _isIpDeclined(targetIp) ||
        _isIpStaticallyReserved(targetIp, normMac)) {
      return null;
    }

    // If another MAC already holds an active lease or active tentative offer on this IP, refuse
    final currentLeaseHolder = _leasesByMac.entries
        .where((e) => e.value.ipAddress == targetIp && e.key != normMac)
        .map((e) => e.key)
        .firstOrNull;
    if (currentLeaseHolder != null) {
      return null;
    }

    final currentOfferHolder = _reservationsByMac.entries
        .where((e) => !e.value.isExpired && e.value.ipAddress == targetIp && e.key != normMac)
        .map((e) => e.key)
        .firstOrNull;
    if (currentOfferHolder != null) {
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

  /// Returns true if [ip] is currently leased, tentatively offered, or statically reserved to [mac].
  bool isIpHeldOrOfferedToMac(String mac, String ip) {
    _pruneExpired();
    final normMac = SharedDevice.normalizeMac(mac);
    if (_leasesByMac[normMac]?.ipAddress == ip) return true;
    final res = _reservationsByMac[normMac];
    if (res != null && !res.isExpired && res.ipAddress == ip) return true;
    final staticRes = _findStaticReservation(normMac);
    if (staticRes != null && staticRes.ipAddress == ip) return true;
    return false;
  }

  /// Returns true if the server has any record (active lease, tentative offer, or static reservation) for [mac].
  bool hasClientRecord(String mac) {
    _pruneExpired();
    final normMac = SharedDevice.normalizeMac(mac);
    return _leasesByMac.containsKey(normMac) ||
        (_reservationsByMac[normMac] != null && !_reservationsByMac[normMac]!.isExpired) ||
        _findStaticReservation(normMac) != null;
  }

  /// Returns true if [ip] is within the configured subnet mask of [config.startIp].
  bool isIpInSubnet(String ip) {
    final ipNum = DhcpConfig.ipToNum(ip);
    final startNum = DhcpConfig.ipToNum(_config.startIp);
    final maskNum = DhcpConfig.ipToNum(_config.subnetMask);
    if (ipNum == 0 || startNum == 0 || maskNum == 0) return false;
    return (ipNum & maskNum) == (startNum & maskNum);
  }

  /// Returns true if [ip] conflicts with another MAC's lease/reservation/static assignment or violates [mac]'s own record.
  bool isIpConflictingForMac(String mac, String ip) {
    _pruneExpired();
    final normMac = SharedDevice.normalizeMac(mac);
    final staticRes = _findStaticReservation(normMac);
    if (staticRes != null && staticRes.ipAddress != ip) return true;
    final existingLease = _leasesByMac[normMac];
    if (existingLease != null && existingLease.ipAddress != ip) return true;
    if (_isIpStaticallyReserved(ip, normMac)) return true;
    if (_isIpDeclined(ip)) return true;
    if (_leasesByMac.entries.any((e) => e.key != normMac && e.value.ipAddress == ip)) return true;
    if (_reservationsByMac.entries.any((e) => e.key != normMac && !e.value.isExpired && e.value.ipAddress == ip)) {
      return true;
    }
    return false;
  }

  void declineIp(String ip, {Duration quarantineDuration = const Duration(minutes: 10)}) {
    _declinedIps[ip] = DateTime.now().add(quarantineDuration);
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
    final now = DateTime.now();
    _leasesByMac.removeWhere((_, lease) => !lease.isStatic && lease.isExpired);
    _reservationsByMac.removeWhere((_, res) => res.isExpired);
    _declinedIps.removeWhere((_, expiry) => now.isAfter(expiry));
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
