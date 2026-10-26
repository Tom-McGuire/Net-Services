import 'dart:async';
import 'dart:io';
import '../../domain/models/dhcp_config.dart';
import '../../domain/models/dhcp_lease.dart';
import '../../domain/models/dns_record.dart';
import '../../domain/models/network_interface_info.dart';
import '../../domain/models/service_log_record.dart';
import '../../domain/models/service_status.dart';
import '../../domain/models/wol_device.dart';
import '../services/dhcp/dhcp_server_service.dart';
import '../services/dns/dns_server_service.dart';
import '../services/network/network_interface_service.dart';
import '../services/ntp/ntp_server_service.dart';
import '../services/wol/wol_service.dart';
import '../services/wol/wol_storage_service.dart';

class NetworkServicesRepository {
  final NetworkInterfaceService _interfaceService = NetworkInterfaceService();
  final DnsServerService _dnsService = DnsServerService();
  final NtpServerService _ntpService = NtpServerService();
  late DhcpServerService _dhcpService;
  final WolService _wolService = WolService();
  final WolStorageService _wolStorage = WolStorageService();

  final List<ServiceLogRecord> _logs = [];
  final _logsController = StreamController<List<ServiceLogRecord>>.broadcast();

  final List<WolDevice> _wolDevices = [];
  final _wolDevicesController = StreamController<List<WolDevice>>.broadcast();

  // M2: Throttled log batching to prevent UI freeze under packet flood
  Timer? _logBatchTimer;
  bool _hasPendingLogUpdate = false;
  int _logSequence = 0;

  NetworkServicesRepository({DhcpConfig? initialConfig, WolStorageService? customStorage}) {
    _dhcpService = DhcpServerService(
      initialConfig: initialConfig ?? DhcpConfig.defaultConfig,
    );

    // Pipe individual service logs into repository log list
    _dnsService.logStream.listen(_appendLog);
    _ntpService.logStream.listen(_appendLog);
    _dhcpService.logStream.listen(_appendLog);

    loadWolDevices();
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
  Stream<List<WolDevice>> get wolDevicesStream => _wolDevicesController.stream;

  ServiceStatus get dnsStatus => _dnsService.status;
  ServiceStatus get ntpStatus => _ntpService.status;
  ServiceStatus get dhcpStatus => _dhcpService.status;
  List<DhcpLease> get dhcpLeases => _dhcpService.activeLeases;
  List<DnsRecord> get dnsRecords => _dnsService.records;
  DhcpConfig get dhcpConfig => _dhcpService.config;
  List<WolDevice> get wolDevices => List.unmodifiable(_wolDevices);

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

  // Wake-on-LAN Operations
  Future<void> loadWolDevices() async {
    final devices = await _wolStorage.loadDevices();
    _wolDevices.clear();
    _wolDevices.addAll(devices);
    if (!_wolDevicesController.isClosed) {
      _wolDevicesController.add(List.unmodifiable(_wolDevices));
    }
  }

  Future<void> addWolDevice(WolDevice device) async {
    _wolDevices.removeWhere((d) => d.id == device.id || d.macAddress == device.macAddress);
    _wolDevices.add(device);
    await _wolStorage.saveDevices(_wolDevices);
    if (!_wolDevicesController.isClosed) {
      _wolDevicesController.add(List.unmodifiable(_wolDevices));
    }
    _emitWolLog(
      action: 'ADD_DEVICE',
      summary: 'Added WOL device "${device.name}" (${device.macAddress})',
      clientAddress: device.ipAddress ?? device.macAddress,
    );
  }

  Future<void> updateWolDevice(WolDevice device) async {
    final index = _wolDevices.indexWhere((d) => d.id == device.id);
    if (index != -1) {
      _wolDevices[index] = device;
    } else {
      _wolDevices.add(device);
    }
    await _wolStorage.saveDevices(_wolDevices);
    if (!_wolDevicesController.isClosed) {
      _wolDevicesController.add(List.unmodifiable(_wolDevices));
    }
  }

  Future<void> deleteWolDevice(String id) async {
    final removed = _wolDevices.where((d) => d.id == id).firstOrNull;
    _wolDevices.removeWhere((d) => d.id == id);
    await _wolStorage.saveDevices(_wolDevices);
    if (!_wolDevicesController.isClosed) {
      _wolDevicesController.add(List.unmodifiable(_wolDevices));
    }
    if (removed != null) {
      _emitWolLog(
        action: 'DELETE_DEVICE',
        summary: 'Removed WOL device "${removed.name}" (${removed.macAddress})',
        clientAddress: removed.ipAddress ?? removed.macAddress,
      );
    }
  }

  Future<bool> wakeDevice(WolDevice device) async {
    final success = await _wolService.sendWakePacket(
      macAddress: device.macAddress,
      broadcastAddress: device.broadcastAddress,
      port: device.port,
    );

    if (success) {
      final updated = device.copyWith(lastWoken: DateTime.now());
      final index = _wolDevices.indexWhere((d) => d.id == device.id);
      if (index != -1) {
        _wolDevices[index] = updated;
        await _wolStorage.saveDevices(_wolDevices);
        if (!_wolDevicesController.isClosed) {
          _wolDevicesController.add(List.unmodifiable(_wolDevices));
        }
      }

      _emitWolLog(
        action: 'MAGIC_PACKET',
        summary: 'Sent Wake-on-LAN Magic Packet to "${device.name}" (${device.macAddress}) on port ${device.port}',
        clientAddress: device.ipAddress ?? device.macAddress,
        severity: LogSeverity.success,
        details: 'Device: ${device.name}\n'
            'Target MAC: ${device.macAddress}\n'
            'IP: ${device.ipAddress ?? "Not specified"}\n'
            'Broadcast: ${device.broadcastAddress}:${device.port}\n'
            'Payload: 102 bytes (6x0xFF + 16xMAC)',
      );
    } else {
      _emitWolLog(
        action: 'WAKE_FAILED',
        summary: 'Failed to broadcast Wake-on-LAN packet for "${device.name}" (${device.macAddress})',
        clientAddress: device.ipAddress ?? device.macAddress,
        severity: LogSeverity.error,
      );
    }

    return success;
  }

  Future<String?> resolveMacFromIp(String ip) {
    return _wolService.resolveMacFromIp(ip);
  }

  void _emitWolLog({
    required String action,
    required String summary,
    LogSeverity severity = LogSeverity.info,
    String? clientAddress,
    String? details,
  }) {
    final logId = '${DateTime.now().millisecondsSinceEpoch}_${++_logSequence}';
    _appendLog(
      ServiceLogRecord(
        id: logId,
        timestamp: DateTime.now(),
        serviceType: ServiceType.wol,
        action: action,
        summary: summary,
        severity: severity,
        clientAddress: clientAddress,
        details: details,
      ),
    );
  }

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
    _wolDevicesController.close();
  }
}
