import 'dart:convert';
import 'dart:io';
import '../../../domain/models/dhcp_config.dart';
import '../../../domain/models/dhcp_lease.dart';
import '../../../domain/models/dns_record.dart';
import '../wol/wol_storage_service.dart';

class AppPersistedSettings {
  final DhcpConfig? dhcpConfig;
  final List<DnsRecord>? dnsRecords;
  final String? upstreamDnsIp;
  final int? dhcpPort;
  final int? dnsPort;
  final int? ntpPort;
  final String? selectedInterfaceName;
  final List<DhcpLease>? activeLeases;

  const AppPersistedSettings({
    this.dhcpConfig,
    this.dnsRecords,
    this.upstreamDnsIp,
    this.dhcpPort,
    this.dnsPort,
    this.ntpPort,
    this.selectedInterfaceName,
    this.activeLeases,
  });

  Map<String, dynamic> toJson() => {
    if (dhcpConfig != null) 'dhcpConfig': dhcpConfig!.toJson(),
    if (dnsRecords != null) 'dnsRecords': dnsRecords!.map((r) => r.toJson()).toList(),
    'upstreamDnsIp': upstreamDnsIp,
    if (dhcpPort != null) 'dhcpPort': dhcpPort,
    if (dnsPort != null) 'dnsPort': dnsPort,
    if (ntpPort != null) 'ntpPort': ntpPort,
    if (selectedInterfaceName != null) 'selectedInterfaceName': selectedInterfaceName,
    if (activeLeases != null) 'activeLeases': activeLeases!.map((l) => l.toJson()).toList(),
  };

  factory AppPersistedSettings.fromJson(Map<String, dynamic> json) {
    final rawRecords = json['dnsRecords'] as List<dynamic>?;
    final rawLeases = json['activeLeases'] as List<dynamic>?;
    final rawDhcp = json['dhcpConfig'];

    return AppPersistedSettings(
      dhcpConfig: rawDhcp is Map<String, dynamic> ? DhcpConfig.fromJson(rawDhcp) : null,
      dnsRecords: rawRecords
          ?.whereType<Map<String, dynamic>>()
          .map(DnsRecord.fromJson)
          .toList(),
      upstreamDnsIp: json['upstreamDnsIp'] as String?,
      dhcpPort: json['dhcpPort'] as int?,
      dnsPort: json['dnsPort'] as int?,
      ntpPort: json['ntpPort'] as int?,
      selectedInterfaceName: json['selectedInterfaceName'] as String?,
      activeLeases: rawLeases
          ?.whereType<Map<String, dynamic>>()
          .map(DhcpLease.fromJson)
          .where((l) => !l.isExpired)
          .toList(),
    );
  }
}

class SettingsStorageService {
  final String? customFilePath;
  final bool inMemory;
  AppPersistedSettings? _memorySettings;

  SettingsStorageService({this.customFilePath, this.inMemory = false});

  Future<File> getStorageFile() async {
    if (customFilePath != null) {
      final file = File(customFilePath!);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      return file;
    }

    final dir = WolStorageService.resolveConfigDirectory();
    final sep = Platform.isWindows ? '\\' : '/';
    final path = dir == '.' ? 'settings.json' : '$dir${sep}settings.json';
    final file = File(path);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return file;
  }

  Future<AppPersistedSettings?> loadSettings() async {
    if (inMemory) {
      return _memorySettings;
    }
    try {
      final file = await getStorageFile();
      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return null;
      }

      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return AppPersistedSettings.fromJson(decoded);
      }
    } catch (_) {
      try {
        final file = await getStorageFile();
        if (await file.exists()) {
          await file.copy('${file.path}.corrupt.bak');
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> saveSettings(AppPersistedSettings settings) async {
    if (inMemory) {
      _memorySettings = settings;
      return;
    }
    try {
      final file = await getStorageFile();
      const encoder = JsonEncoder.withIndent('  ');
      final content = encoder.convert(settings.toJson());
      final tmpFile = File('${file.path}.tmp');
      await tmpFile.writeAsString(content, flush: true);
      await tmpFile.rename(file.path);
    } catch (_) {
      // Storage failure handled silently
    }
  }
}
