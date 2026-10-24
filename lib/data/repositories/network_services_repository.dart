import 'dart:async';
import 'dart:io';
import '../../domain/models/dhcp_config.dart';
import '../../domain/models/dhcp_lease.dart';
import '../../domain/models/dns_record.dart';
import '../../domain/models/network_interface_info.dart';
import '../../domain/models/service_log_record.dart';
import '../../domain/models/service_status.dart';
import '../services/dhcp/dhcp_server_service.dart';
import '../services/dns/dns_server_service.dart';
import '../services/network/network_interface_service.dart';
import '../services/ntp/ntp_server_service.dart';

class NetworkServicesRepository {
  final NetworkInterfaceService _interfaceService = NetworkInterfaceService();
  final DnsServerService _dnsService = DnsServerService();
  final NtpServerService _ntpService = NtpServerService();
  late DhcpServerService _dhcpService;

  final List<ServiceLogRecord> _logs = [];
  final _logsController = StreamController<List<ServiceLogRecord>>.broadcast();

  // M2: Throttled log batching to prevent UI freeze under packet flood
  Timer? _logBatchTimer;
  bool _hasPendingLogUpdate = false;

  NetworkServicesRepository({DhcpConfig? initialConfig}) {
    _dhcpService = DhcpServerService(
      initialConfig: initialConfig ?? DhcpConfig.defaultConfig,
    );

    // Pipe individual service logs into repository log list
    _dnsService.logStream.listen(_appendLog);
    _ntpService.logStream.listen(_appendLog);
    _dhcpService.logStream.listen(_appendLog);
  }

  void _appendLog(ServiceLogRecord log) {
    if (_logsController.isClosed) return;
    _logs.insert(0, log);
    if (_logs.length > 2000) {
      _logs.removeRange(2000, _logs.length);
    }
    _hasPendingLogUpdate = true;

    if (_logBatchTimer == null || !_logBatchTimer!.isActive) {
      _logBatchTimer = Timer(const Duration(milliseconds: 100), () {
        if (_hasPendingLogUpdate && !_logsController.isClosed) {
          _hasPendingLogUpdate = false;
          _logsController.add(List.unmodifiable(_logs));
        }
      });
    }
  }

  // Streams
  Stream<List<ServiceLogRecord>> get logsStream => _logsController.stream;
  List<ServiceLogRecord> get logs => List.unmodifiable(_logs);

  Stream<ServiceStatus> get dnsStatusStream => _dnsService.statusStream;
  Stream<ServiceStatus> get ntpStatusStream => _ntpService.statusStream;
  Stream<ServiceStatus> get dhcpStatusStream => _dhcpService.statusStream;
  Stream<List<DhcpLease>> get dhcpLeasesStream => _dhcpService.leasesStream;

  ServiceStatus get dnsStatus => _dnsService.status;
  ServiceStatus get ntpStatus => _ntpService.status;
  ServiceStatus get dhcpStatus => _dhcpService.status;
  List<DhcpLease> get dhcpLeases => _dhcpService.activeLeases;
  List<DnsRecord> get dnsRecords => _dnsService.records;
  DhcpConfig get dhcpConfig => _dhcpService.config;

  // Interfaces & Privileges
  Future<List<NetworkInterfaceInfo>> getInterfaces() => _interfaceService.getAvailableInterfaces();
  Future<bool> checkPrivileges() => _interfaceService.checkHasElevatedPrivileges();

  // DNS Operations
  Future<void> startDns({int port = 53, InternetAddress? bindAddress}) =>
      _dnsService.start(port: port, bindAddress: bindAddress);
  Future<void> stopDns() => _dnsService.stop();
  void setDnsRecords(List<DnsRecord> records) => _dnsService.setRecords(records);
  void addDnsRecord(DnsRecord record) => _dnsService.addRecord(record);
  void removeDnsRecord(String domain) => _dnsService.removeRecord(domain);

  // NTP Operations
  Future<void> startNtp({int port = 123, InternetAddress? bindAddress}) =>
      _ntpService.start(port: port, bindAddress: bindAddress);
  Future<void> stopNtp() => _ntpService.stop();

  // DHCP Operations
  Future<void> startDhcp({
    int port = 67,
    InternetAddress? bindAddress,
    String? serverIp,
  }) =>
      _dhcpService.start(port: port, bindAddress: bindAddress, serverIp: serverIp);
  Future<void> stopDhcp() => _dhcpService.stop();
  void updateDhcpConfig(DhcpConfig config) => _dhcpService.updateConfig(config);
  void clearDhcpLeases() => _dhcpService.clearLeases();

  // Bulk Operations
  Future<void> startAll({
    int dnsPort = 53,
    int ntpPort = 123,
    int dhcpPort = 67,
    InternetAddress? bindAddress,
    String? serverIp,
  }) async {
    await startDns(port: dnsPort, bindAddress: bindAddress);
    await startNtp(port: ntpPort, bindAddress: bindAddress);
    await startDhcp(port: dhcpPort, bindAddress: bindAddress, serverIp: serverIp);
  }

  Future<void> stopAll() async {
    await stopDns();
    await stopNtp();
    await stopDhcp();
  }

  void clearLogs() {
    _logs.clear();
    _logsController.add([]);
  }

  void dispose() {
    _logBatchTimer?.cancel();
    _dnsService.dispose();
    _ntpService.dispose();
    _dhcpService.dispose();
    _logsController.close();
  }
}
