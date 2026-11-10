import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import '../../../../data/repositories/network_services_repository.dart';
import '../../../../data/services/device/mac_address_helper.dart';
import '../../../../data/services/export/csv_export_service.dart';
import '../../../../data/services/storage/settings_storage_service.dart';
import '../../../../domain/models/dhcp_config.dart';
import '../../../../domain/models/dhcp_lease.dart';
import '../../../../domain/models/dhcp_static_reservation.dart';
import '../../../../domain/models/dns_record.dart';
import '../../../../domain/models/network_interface_info.dart';
import '../../../../domain/models/service_log_record.dart';
import '../../../../domain/models/service_status.dart';
import '../../../../domain/models/wol_device.dart';

class NetworkServicesViewModel extends ChangeNotifier {
  final NetworkServicesRepository _repository;

  List<NetworkInterfaceInfo> _interfaces = [];
  NetworkInterfaceInfo? _selectedInterface;
  bool _hasElevatedPrivileges = false;
  bool _disposed = false;

  int _dnsPort = 53;
  int _ntpPort = 123;
  int _dhcpPort = 67;
  String? _dhcpValidationError;

  late DhcpConfig _dhcpConfig;

  ServiceLogRecord? _selectedLog;
  String _logFilter = 'ALL';
  String _searchQuery = '';

  // M2: Cache filtered logs to prevent re-filtering 4+ times per frame
  List<ServiceLogRecord>? _cachedFilteredLogs;

  StreamSubscription? _logSub;
  StreamSubscription? _dnsSub;
  StreamSubscription? _ntpSub;
  StreamSubscription? _dhcpSub;
  StreamSubscription? _leaseSub;
  StreamSubscription? _wolSub;
  StreamSubscription? _sharedDbSub;

  NetworkServicesViewModel({NetworkServicesRepository? repository})
      : _repository = repository ?? NetworkServicesRepository() {
    _dhcpConfig = _repository.dhcpConfig;
    _init();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  // Getters
  List<NetworkInterfaceInfo> get interfaces => _interfaces;
  NetworkInterfaceInfo? get selectedInterface => _selectedInterface;
  bool get hasElevatedPrivileges => _hasElevatedPrivileges;

  int get dnsPort => _dnsPort;
  int get ntpPort => _ntpPort;
  int get dhcpPort => _dhcpPort;

  ServiceStatus get dnsStatus => _repository.dnsStatus;
  ServiceStatus get ntpStatus => _repository.ntpStatus;
  ServiceStatus get dhcpStatus => _repository.dhcpStatus;

  DhcpConfig get dhcpConfig => _dhcpConfig;
  List<DhcpLease> get dhcpLeases => _repository.dhcpLeases;
  List<DnsRecord> get dnsRecords => _repository.dnsRecords;
  String? get upstreamDnsIp => _repository.upstreamDnsIp;
  List<WolDevice> get wolDevices => _repository.wolDevices;

  ServiceLogRecord? get selectedLog => _selectedLog;
  String? get dhcpValidationError => _dhcpValidationError;
  String get logFilter => _logFilter;
  String get searchQuery => _searchQuery;
  DateTime get currentTime => DateTime.now();

  bool get isAnyServiceRunning =>
      dnsStatus.isRunning || ntpStatus.isRunning || dhcpStatus.isRunning;

  String? get activeErrorMessage {
    if (_dhcpValidationError != null) return 'DHCP Config: $_dhcpValidationError';
    if (dnsStatus.hasError) return 'DNS: ${dnsStatus.lastError}';
    if (ntpStatus.hasError) return 'NTP: ${ntpStatus.lastError}';
    if (dhcpStatus.hasError) return 'DHCP: ${dhcpStatus.lastError}';
    return null;
  }

  List<ServiceLogRecord> get filteredLogs {
    if (_cachedFilteredLogs != null) return _cachedFilteredLogs!;

    final result = _repository.logs.where((log) {
      if (_logFilter != 'ALL') {
        if (log.serviceName != _logFilter) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesSummary = log.summary.toLowerCase().contains(query);
        final matchesAction = log.action.toLowerCase().contains(query);
        final matchesClient = log.clientAddress?.toLowerCase().contains(query) ?? false;
        if (!matchesSummary && !matchesAction && !matchesClient) return false;
      }
      return true;
    }).toList();

    _cachedFilteredLogs = result;
    return result;
  }

  void _invalidateLogCache() {
    _cachedFilteredLogs = null;
  }

  Future<void> _init() async {
    final persisted = await _repository.loadSettings();
    _hasElevatedPrivileges = await _repository.checkPrivileges();
    _interfaces = await _repository.getInterfaces();
    if (_disposed) return;

    if (persisted != null) {
      if (persisted.dnsPort != null) _dnsPort = persisted.dnsPort!;
      if (persisted.ntpPort != null) _ntpPort = persisted.ntpPort!;
      if (persisted.dhcpPort != null) _dhcpPort = persisted.dhcpPort!;
      if (persisted.upstreamDnsIp != null) {
        _repository.setUpstreamDnsIp(persisted.upstreamDnsIp);
      }
      if (persisted.dnsRecords != null) {
        _repository.setDnsRecords(persisted.dnsRecords!);
      }
      if (persisted.dhcpConfig != null) {
        _dhcpConfig = persisted.dhcpConfig!;
        _repository.updateDhcpConfig(_dhcpConfig);
      }
      if (persisted.activeLeases != null && persisted.activeLeases!.isNotEmpty) {
        _repository.restoreDhcpLeases(persisted.activeLeases!);
      }
    }

    if (_interfaces.isNotEmpty) {
      if (persisted?.selectedInterfaceName != null) {
        _selectedInterface = _interfaces.firstWhere(
          (i) => i.name == persisted!.selectedInterfaceName,
          orElse: () => _interfaces.first,
        );
      } else {
        _selectedInterface = _interfaces.first;
      }

      if (persisted?.dhcpConfig == null) {
        _applyInterfaceToDhcpDefaults(_selectedInterface!);
      }
    }

    _logSub = _repository.logsStream.listen((_) {
      _invalidateLogCache();
      notifyListeners();
    });
    _dnsSub = _repository.dnsStatusStream.listen((_) => notifyListeners());
    _ntpSub = _repository.ntpStatusStream.listen((_) => notifyListeners());
    _dhcpSub = _repository.dhcpStatusStream.listen((_) => notifyListeners());
    _leaseSub = _repository.dhcpLeasesStream.listen((_) {
      _persistSettings();
      notifyListeners();
    });
    _wolSub = _repository.wolDevicesStream.listen((_) => notifyListeners());

    try {
      if (SharedDeviceDatabase.instance.isInitialized) {
        _sharedDbSub = SharedDeviceDatabase.instance.onDatabaseChanged.listen((_) {
          notifyListeners();
        });
      }
    } catch (_) {}

    notifyListeners();
  }

  void _persistSettings() {
    _repository.saveSettings(
      AppPersistedSettings(
        dhcpConfig: _dhcpConfig,
        dnsRecords: _repository.dnsRecords,
        upstreamDnsIp: _repository.upstreamDnsIp,
        dhcpPort: _dhcpPort,
        dnsPort: _dnsPort,
        ntpPort: _ntpPort,
        selectedInterfaceName: _selectedInterface?.name,
        activeLeases: _repository.dhcpLeases,
      ),
    );
  }

  void _applyInterfaceToDhcpDefaults(NetworkInterfaceInfo iface) {
    final defaultGw = iface.defaultGateway ?? iface.ip;
    var candidateStart = iface.hostIpPlusOne;
    if (candidateStart == defaultGw) {
      final gwNum = DhcpConfig.ipToNum(defaultGw);
      if (gwNum != 0) {
        candidateStart = DhcpConfig.numToIp(gwNum + 1);
      }
    }
    _dhcpConfig = _dhcpConfig.copyWith(
      startIp: candidateStart,
      subnetMask: iface.subnetMask,
      gatewayIp: defaultGw,
      dnsServerIp: _dhcpConfig.useLocalDns ? iface.ip : defaultGw,
    );
    _repository.updateDhcpConfig(_dhcpConfig);
  }

  void selectInterface(NetworkInterfaceInfo iface) {
    _selectedInterface = iface;
    if (!dhcpStatus.isRunning) {
      _applyInterfaceToDhcpDefaults(iface);
    }
    _persistSettings();
    notifyListeners();
  }

  Future<void> refreshInterfaces() async {
    _interfaces = await _repository.getInterfaces();
    if (_disposed) return;
    if (_interfaces.isNotEmpty) {
      if (_selectedInterface != null) {
        _selectedInterface = _interfaces.firstWhere(
          (i) => i.name == _selectedInterface!.name,
          orElse: () => _interfaces.first,
        );
      } else {
        _selectedInterface = _interfaces.first;
      }
    }
    notifyListeners();
  }

  Future<void> loadDemoData() async {
    // 1. Add sample DNS records
    addDnsRecord(const DnsRecord(domain: 'router.lab', ip: '192.168.1.1'));
    addDnsRecord(const DnsRecord(domain: 'nas.lab', ip: '192.168.1.50'));
    addDnsRecord(const DnsRecord(domain: '*.lab', ip: '192.168.1.100'));

    // 2. Add sample DHCP leases
    final now = DateTime.now();
    _repository.restoreDhcpLeases([
      DhcpLease(
        ipAddress: '192.168.1.101',
        macAddress: '00:1A:2B:3C:4D:5E',
        hostname: 'MacBook-Pro',
        leaseStart: now,
        leaseDurationSeconds: 86400,
        friendlyName: 'MacBook Pro 16"',
      ),
      DhcpLease(
        ipAddress: '192.168.1.102',
        macAddress: 'B8:27:EB:11:22:33',
        hostname: 'RaspberryPi-DNS',
        leaseStart: now,
        leaseDurationSeconds: 86400,
        friendlyName: 'Pi-hole DNS',
      ),
      DhcpLease(
        ipAddress: '192.168.1.105',
        macAddress: '3C:06:30:AA:BB:CC',
        hostname: 'Workstation-Win11',
        leaseStart: now,
        leaseDurationSeconds: 86400,
        friendlyName: 'Studio Workstation',
      ),
    ]);

    // 3. Add sample WOL devices
    await addWolDevice(const WolDevice(
      id: 'demo_1',
      name: 'Studio Workstation',
      macAddress: '3C:06:30:AA:BB:CC',
      ipAddress: '192.168.1.105',
      port: 9,
    ));
    await addWolDevice(const WolDevice(
      id: 'demo_2',
      name: 'Backup Synology NAS',
      macAddress: '00:11:32:44:55:66',
      ipAddress: '192.168.1.50',
      port: 9,
    ));

    _invalidateLogCache();
    notifyListeners();
  }

  void setDnsPort(int port) {
    if (port >= 1 && port <= 65535) {
      _dnsPort = port;
      _persistSettings();
      notifyListeners();
    }
  }

  void setNtpPort(int port) {
    if (port >= 1 && port <= 65535) {
      _ntpPort = port;
      _persistSettings();
      notifyListeners();
    }
  }

  void setDhcpPort(int port) {
    if (port >= 1 && port <= 65535) {
      _dhcpPort = port;
      _persistSettings();
      notifyListeners();
    }
  }

  void setUseLocalDns(bool useLocal) {
    final hostIp = _selectedInterface?.ip ?? '127.0.0.1';
    _dhcpConfig = _dhcpConfig.copyWith(
      useLocalDns: useLocal,
      dnsServerIp: useLocal ? hostIp : _dhcpConfig.dnsServerIp,
    );
    _dhcpValidationError = null;
    _repository.updateDhcpConfig(_dhcpConfig);
    _persistSettings();
    notifyListeners();
  }

  void updateDhcpConfig(DhcpConfig config) {
    _dhcpConfig = config;
    _dhcpValidationError = null;
    _repository.updateDhcpConfig(config);
    _persistSettings();
    notifyListeners();
  }

  // Service toggles
  Future<void> toggleDns() async {
    if (dnsStatus.isRunning) {
      await _repository.stopDns();
    } else {
      InternetAddress? addr;
      if (_selectedInterface != null) {
        addr = InternetAddress.tryParse(_selectedInterface!.ip);
      }
      await _repository.startDns(port: _dnsPort, bindAddress: addr ?? InternetAddress.anyIPv4);
    }
    notifyListeners();
  }

  Future<void> toggleNtp() async {
    if (ntpStatus.isRunning) {
      await _repository.stopNtp();
    } else {
      InternetAddress? addr;
      if (_selectedInterface != null) {
        addr = InternetAddress.tryParse(_selectedInterface!.ip);
      }
      await _repository.startNtp(port: _ntpPort, bindAddress: addr ?? InternetAddress.anyIPv4);
    }
    notifyListeners();
  }

  Future<void> toggleDhcp() async {
    if (dhcpStatus.isRunning) {
      await _repository.stopDhcp();
    } else {
      if (_dhcpConfig.useLocalDns && _selectedInterface != null) {
        _dhcpConfig = _dhcpConfig.copyWith(dnsServerIp: _selectedInterface!.ip);
        _repository.updateDhcpConfig(_dhcpConfig);
      }

      final validationErrors = _dhcpConfig.validate(serverIp: _selectedInterface?.ip);
      if (validationErrors.isNotEmpty) {
        _dhcpValidationError = validationErrors.first;
        _repository.logServiceEvent(
          serviceType: ServiceType.dhcp,
          action: 'CONFIG_ERROR',
          summary: 'Cannot start DHCP Server: ${validationErrors.join(" ")}',
          severity: LogSeverity.error,
          details: validationErrors.join('\n'),
        );
        notifyListeners();
        return;
      }
      _dhcpValidationError = null;

      InternetAddress? addr;
      if (_selectedInterface != null) {
        addr = InternetAddress.tryParse(_selectedInterface!.ip);
      }
      // H1: Bind consistently with startAll and provide serverIp
      await _repository.startDhcp(
        port: _dhcpPort,
        bindAddress: addr ?? InternetAddress.anyIPv4,
        serverIp: _selectedInterface?.ip,
      );
    }
    notifyListeners();
  }

  Future<void> startAll() async {
    InternetAddress? addr;
    if (_selectedInterface != null) {
      addr = InternetAddress.tryParse(_selectedInterface!.ip);
    }
    if (_dhcpConfig.useLocalDns && _selectedInterface != null) {
      _dhcpConfig = _dhcpConfig.copyWith(dnsServerIp: _selectedInterface!.ip);
      _repository.updateDhcpConfig(_dhcpConfig);
    }

    await _repository.startDns(port: _dnsPort, bindAddress: addr ?? InternetAddress.anyIPv4);
    await _repository.startNtp(port: _ntpPort, bindAddress: addr ?? InternetAddress.anyIPv4);

    final validationErrors = _dhcpConfig.validate(serverIp: _selectedInterface?.ip);
    if (validationErrors.isNotEmpty) {
      _dhcpValidationError = validationErrors.first;
      _repository.logServiceEvent(
        serviceType: ServiceType.dhcp,
        action: 'CONFIG_ERROR',
        summary: 'Cannot start DHCP Server: ${validationErrors.join(" ")}',
        severity: LogSeverity.error,
        details: validationErrors.join('\n'),
      );
    } else {
      _dhcpValidationError = null;
      await _repository.startDhcp(
        port: _dhcpPort,
        bindAddress: addr ?? InternetAddress.anyIPv4,
        serverIp: _selectedInterface?.ip,
      );
    }
    notifyListeners();
  }

  Future<void> stopAll() async {
    await _repository.stopAll();
    notifyListeners();
  }

  // DNS Records & Forwarder Management
  void addDnsRecord(DnsRecord record) {
    _repository.addDnsRecord(record);
    _persistSettings();
    notifyListeners();
  }

  void removeDnsRecord(String domain) {
    _repository.removeDnsRecord(domain);
    _persistSettings();
    notifyListeners();
  }

  void setUpstreamDnsIp(String? ip) {
    _repository.setUpstreamDnsIp(ip);
    _persistSettings();
    notifyListeners();
  }

  // Wake-on-LAN (WOL) Operations
  Future<void> addWolDevice(WolDevice device) => _repository.addWolDevice(device);
  Future<void> updateWolDevice(WolDevice device) => _repository.updateWolDevice(device);
  Future<void> deleteWolDevice(String id) => _repository.deleteWolDevice(id);
  Future<bool> wakeDevice(WolDevice device) => _repository.wakeDevice(
        device,
        fallbackSubnetBroadcast: _selectedInterface?.broadcastAddress,
      );
  Future<String?> resolveMacFromIp(String ip) => _repository.resolveMacFromIp(ip);

  // DHCP Leases
  void clearDhcpLeases() {
    _repository.clearDhcpLeases();
    _persistSettings();
    notifyListeners();
  }

  // Log Inspection & Filtering
  void selectLog(ServiceLogRecord? log) {
    _selectedLog = log;
    notifyListeners();
  }

  void setLogFilter(String filter) {
    _logFilter = filter;
    _invalidateLogCache();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _invalidateLogCache();
    notifyListeners();
  }

  void clearLogs() {
    _repository.clearLogs();
    _selectedLog = null;
    _invalidateLogCache();
    notifyListeners();
  }

  Future<String?> exportCsv() async {
    if (_repository.logs.isEmpty) return null;
    final csv = CsvExportService.formatCsv(_repository.logs);
    final filename = 'net_services_logs_${DateTime.now().millisecondsSinceEpoch}.csv';
    return CsvExportService.exportToFile(csv, filename);
  }

  Future<String?> exportJson() async {
    if (_repository.logs.isEmpty) return null;
    final json = CsvExportService.formatJson(_repository.logs);
    final filename = 'net_services_logs_${DateTime.now().millisecondsSinceEpoch}.json';
    return CsvExportService.exportToFile(json, filename);
  }

  // Static Reservations & Shared Devices
  void addStaticReservation(DhcpStaticReservation reservation) {
    _repository.addStaticReservation(reservation);
    _dhcpConfig = _repository.dhcpConfig;
    _persistSettings();
    notifyListeners();
  }

  void removeStaticReservation(String macAddress) {
    _repository.removeStaticReservation(macAddress);
    _dhcpConfig = _repository.dhcpConfig;
    _persistSettings();
    notifyListeners();
  }

  void updateSharedDeviceName(String mac, String newName) {
    SharedDeviceHelper.updateDeviceName(mac, newName);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _logSub?.cancel();
    _dnsSub?.cancel();
    _ntpSub?.cancel();
    _dhcpSub?.cancel();
    _leaseSub?.cancel();
    _wolSub?.cancel();
    _sharedDbSub?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
