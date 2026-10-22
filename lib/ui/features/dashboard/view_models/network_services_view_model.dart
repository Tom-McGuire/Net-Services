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
  DateTime _currentTime = DateTime.now();
  Timer? _clockTimer;

  StreamSubscription? _logSub;
  StreamSubscription? _dnsSub;
  StreamSubscription? _ntpSub;
  StreamSubscription? _dhcpSub;
  StreamSubscription? _leaseSub;

  NetworkServicesViewModel({NetworkServicesRepository? repository})
      : _repository = repository ?? NetworkServicesRepository() {
    _dhcpConfig = const DhcpConfig(
      startIp: '192.168.1.100',
      poolSize: 20,
      subnetMask: '255.255.255.0',
      gatewayIp: '192.168.1.1',
      dnsServerIp: '192.168.1.1',
    );

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

  ServiceLogRecord? get selectedLog => _selectedLog;
  String get logFilter => _logFilter;
  String get searchQuery => _searchQuery;
  DateTime get currentTime => _currentTime;

  bool get isAnyServiceRunning =>
      dnsStatus.isRunning || ntpStatus.isRunning || dhcpStatus.isRunning;

  String? get activeErrorMessage {
    if (dnsStatus.hasError) return 'DNS: ${dnsStatus.lastError}';
    if (ntpStatus.hasError) return 'NTP: ${ntpStatus.lastError}';
    if (dhcpStatus.hasError) return 'DHCP: ${dhcpStatus.lastError}';
    return null;
  }

  List<ServiceLogRecord> get filteredLogs {
    return _repository.logs.where((log) {
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
  }

  Future<void> _init() async {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _currentTime = DateTime.now();
      notifyListeners();
    });

    _hasElevatedPrivileges = await _repository.checkPrivileges();
    _interfaces = await _repository.getInterfaces();

    if (_interfaces.isNotEmpty) {
      // Pick first non-loopback
      _selectedInterface = _interfaces.first;
      _applyInterfaceToDhcpDefaults(_selectedInterface!);
    }

    _repository.setDnsRecords(_dnsRecords);

    _logSub = _repository.logsStream.listen((_) => notifyListeners());
    _dnsSub = _repository.dnsStatusStream.listen((_) => notifyListeners());
    _ntpSub = _repository.ntpStatusStream.listen((_) => notifyListeners());
    _dhcpSub = _repository.dhcpStatusStream.listen((_) => notifyListeners());
    _leaseSub = _repository.dhcpLeasesStream.listen((_) => notifyListeners());

    notifyListeners();
  }

  void _applyInterfaceToDhcpDefaults(NetworkInterfaceInfo iface) {
    _dhcpConfig = _dhcpConfig.copyWith(
      startIp: iface.hostIpPlusOne,
      subnetMask: iface.subnetMask,
      gatewayIp: iface.ip,
      dnsServerIp: iface.ip,
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
    _dnsPort = port;
    notifyListeners();
  }

  void setNtpPort(int port) {
    _ntpPort = port;
    notifyListeners();
  }

  void setDhcpPort(int port) {
    _dhcpPort = port;
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
      // DHCP must listen on 0.0.0.0 to catch broadcasts
      await _repository.startDhcp(port: _dhcpPort, bindAddress: InternetAddress.anyIPv4);
    }
    notifyListeners();
  }

  Future<void> startAll() async {
    InternetAddress? addr;
    if (_selectedInterface != null) {
      addr = InternetAddress.tryParse(_selectedInterface!.ip);
    }
    await _repository.startAll(
      dnsPort: _dnsPort,
      ntpPort: _ntpPort,
      dhcpPort: _dhcpPort,
      bindAddress: addr,
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
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearLogs() {
    _repository.clearLogs();
    _selectedLog = null;
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
    _clockTimer?.cancel();
    _logSub?.cancel();
    _dnsSub?.cancel();
    _ntpSub?.cancel();
    _dhcpSub?.cancel();
    _leaseSub?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
