import 'dart:convert';
import 'dart:io';
import '../../../domain/models/wol_device.dart';

class WolStorageService {
  final String? customFilePath;

  WolStorageService({this.customFilePath});

  Future<File> getStorageFile() async {
    if (customFilePath != null) {
      final file = File(customFilePath!);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      return file;
    }

    final path = _getDefaultStoragePath();
    final file = File(path);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return file;
  }

  String _getDefaultStoragePath() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return '$appData\\net_services\\wol_devices.json';
      }
    } else if (Platform.isLinux) {
      final xdgConfig = Platform.environment['XDG_CONFIG_HOME'];
      if (xdgConfig != null && xdgConfig.isNotEmpty) {
        return '$xdgConfig/net_services/wol_devices.json';
      }
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return '$home/.config/net_services/wol_devices.json';
      }
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return '$home/Library/Application Support/net_services/wol_devices.json';
      }
    }

    return 'wol_devices.json';
  }

  Future<List<WolDevice>> loadDevices() async {
    try {
      final file = await getStorageFile();
      if (!await file.exists()) {
        return [];
      }

      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return [];
      }

      final decoded = jsonDecode(content);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(WolDevice.fromJson)
            .toList();
      }
    } catch (_) {
      // Return empty list on parse error or read error
    }
    return [];
  }

  Future<void> saveDevices(List<WolDevice> devices) async {
    try {
      final file = await getStorageFile();
      final jsonList = devices.map((d) => d.toJson()).toList();
      const encoder = JsonEncoder.withIndent('  ');
      final content = encoder.convert(jsonList);
      await file.writeAsString(content);
    } catch (_) {
      // Storage failure handled silently or logged
    }
  }
}
