import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../data/repositories/network_services_repository.dart';
import '../../../../data/services/export/csv_export_service.dart';
import '../../../../domain/models/dhcp_config.dart';
import '../../../../domain/models/dhcp_lease.dart';
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

  int _dnsPort = 53;
  int _ntpPort = 123;
  int _dhcpPort = 67;

  late DhcpConfig _dhcpConfig;
  final List<DnsRecord> _dnsRecords = [
    const DnsRecord(domain: 'router.local', ip: '192.168.1.1'),
    const DnsRecord(domain: 'gateway.local', ip: '192.168.1.1'),
    const DnsRecord(domain: 'testdevice.local', ip: '192.168.1.100'),
  ];

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

  NetworkServicesViewModel({NetworkServicesRepository? repository})
      : _repository = repository ?? NetworkServicesRepository() {
    _dhcpConfig = DhcpConfig.defaultConfig;
    _init();
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
  List<DnsRecord> get dnsRecords => _dnsRecords;
  List<WolDevice> get wolDevices => _repository.wolDevices;

  ServiceLogRecord? get selectedLog => _selectedLog;
  String get logFilter => _logFilter;
  String get searchQuery => _searchQuery;
  DateTime get currentTime => DateTime.now();

  bool get isAnyServiceRunning =>
      dnsStatus.isRunning || ntpStatus.isRunning || dhcpStatus.isRunning;

  String? get activeErrorMessage {
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
    _hasElevatedPrivileges = await _repository.checkPrivileges();
    _interfaces = await _repository.getInterfaces();

    if (_interfaces.isNotEmpty) {
      _selectedInterface = _interfaces.first;
      _applyInterfaceToDhcpDefaults(_selectedInterface!);
    }

    _repository.setDnsRecords(_dnsRecords);

    _logSub = _repository.logsStream.listen((_) {
      _invalidateLogCache();
      notifyListeners();
    });
    _dnsSub = _repository.dnsStatusStream.listen((_) => notifyListeners());
    _ntpSub = _repository.ntpStatusStream.listen((_) => notifyListeners());
    _dhcpSub = _repository.dhcpStatusStream.listen((_) => notifyListeners());
    _leaseSub = _repository.dhcpLeasesStream.listen((_) => notifyListeners());
    _wolSub = _repository.wolDevicesStream.listen((_) => notifyListeners());

    notifyListeners();
  }

  void _applyInterfaceToDhcpDefaults(NetworkInterfaceInfo iface) {
    _dhcpConfig = _dhcpConfig.copyWith(
      startIp: iface.hostIpPlusOne,
      subnetMask: iface.subnetMask,
      gatewayIp: iface.ip,
      dnsServerIp: _dhcpConfig.useLocalDns ? iface.ip : _dhcpConfig.dnsServerIp,
    );
    _repository.updateDhcpConfig(_dhcpConfig);
  }

  void selectInterface(NetworkInterfaceInfo iface) {
    _selectedInterface = iface;
    if (!dhcpStatus.isRunning) {
      _applyInterfaceToDhcpDefaults(iface);
    }
    notifyListeners();
  }

  void setDnsPort(int port) {
    if (port >= 1 && port <= 65535) {
      _dnsPort = port;
      notifyListeners();
    }
  }

  void setNtpPort(int port) {
    if (port >= 1 && port <= 65535) {
      _ntpPort = port;
      notifyListeners();
    }
  }

  void setDhcpPort(int port) {
    if (port >= 1 && port <= 65535) {
      _dhcpPort = port;
      notifyListeners();
    }
  }

  void setUseLocalDns(bool useLocal) {
    final hostIp = _selectedInterface?.ip ?? '127.0.0.1';
    _dhcpConfig = _dhcpConfig.copyWith(
      useLocalDns: useLocal,
      dnsServerIp: useLocal ? hostIp : _dhcpConfig.dnsServerIp,
    );
    _repository.updateDhcpConfig(_dhcpConfig);
    notifyListeners();
  }

  void updateDhcpConfig(DhcpConfig config) {
    _dhcpConfig = config;
    _repository.updateDhcpConfig(config);
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
      InternetAddress? addr;
      if (_selectedInterface != null) {
        addr = InternetAddress.tryParse(_selectedInterface!.ip);
      }
      if (_dhcpConfig.useLocalDns && _selectedInterface != null) {
        _dhcpConfig = _dhcpConfig.copyWith(dnsServerIp: _selectedInterface!.ip);
        _repository.updateDhcpConfig(_dhcpConfig);
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
    await _repository.startAll(
      dnsPort: _dnsPort,
      ntpPort: _ntpPort,
      dhcpPort: _dhcpPort,
      bindAddress: addr ?? InternetAddress.anyIPv4,
      serverIp: _selectedInterface?.ip,
    );
    notifyListeners();
  }

  Future<void> stopAll() async {
    await _repository.stopAll();
    notifyListeners();
  }

  // DNS Records Management
  void addDnsRecord(DnsRecord record) {
    _dnsRecords.removeWhere((r) => r.domain.toLowerCase() == record.domain.toLowerCase());
    _dnsRecords.add(record);
    _repository.setDnsRecords(_dnsRecords);
    notifyListeners();
  }

  void removeDnsRecord(String domain) {
    _dnsRecords.removeWhere((r) => r.domain.toLowerCase() == domain.toLowerCase());
    _repository.removeDnsRecord(domain);
    notifyListeners();
  }

  // Wake-on-LAN (WOL) Operations
  Future<void> addWolDevice(WolDevice device) => _repository.addWolDevice(device);
  Future<void> updateWolDevice(WolDevice device) => _repository.updateWolDevice(device);
  Future<void> deleteWolDevice(String id) => _repository.deleteWolDevice(id);
  Future<bool> wakeDevice(WolDevice device) => _repository.wakeDevice(device);
  Future<String?> resolveMacFromIp(String ip) => _repository.resolveMacFromIp(ip);

  // DHCP Leases
  void clearDhcpLeases() {
    _repository.clearDhcpLeases();
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

  @override
  void dispose() {
    _logSub?.cancel();
    _dnsSub?.cancel();
    _ntpSub?.cancel();
    _dhcpSub?.cancel();
    _leaseSub?.cancel();
    _wolSub?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
