import 'dart:convert';
import 'dart:io';
import '../../../domain/models/wol_device.dart';

class WolStorageService {
  final String? customFilePath;
  final bool inMemory;
  List<WolDevice> _memoryDevices = [];

  WolStorageService({this.customFilePath, this.inMemory = false});

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

  static String resolveConfigDirectory() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return '$appData\\net_services';
      }
    } else if (Platform.isLinux) {
      final sudoUser = Platform.environment['SUDO_USER'];
      if (sudoUser != null && sudoUser.isNotEmpty && sudoUser != 'root') {
        final sudoHome = Directory('/home/$sudoUser');
        if (sudoHome.existsSync()) {
          return '/home/$sudoUser/.config/net_services';
        }
      }
      final xdgConfig = Platform.environment['XDG_CONFIG_HOME'];
      if (xdgConfig != null && xdgConfig.isNotEmpty) {
        return '$xdgConfig/net_services';
      }
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return '$home/.config/net_services';
      }
    } else if (Platform.isMacOS) {
      final sudoUser = Platform.environment['SUDO_USER'];
      if (sudoUser != null && sudoUser.isNotEmpty && sudoUser != 'root') {
        final sudoHome = Directory('/Users/$sudoUser');
        if (sudoHome.existsSync()) {
          return '/Users/$sudoUser/Library/Application Support/net_services';
        }
      }
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return '$home/Library/Application Support/net_services';
      }
    }
    return '.';
  }

  String _getDefaultStoragePath() {
    final dir = resolveConfigDirectory();
    if (dir == '.') return 'wol_devices.json';
    final sep = Platform.isWindows ? '\\' : '/';
    return '$dir${sep}wol_devices.json';
  }

  Future<List<WolDevice>> loadDevices() async {
    if (inMemory) {
      return List.from(_memoryDevices);
    }
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
      // Back up corrupt file before returning empty list so data is not silently overwritten
      try {
        final file = await getStorageFile();
        if (await file.exists()) {
          await file.copy('${file.path}.corrupt.bak');
        }
      } catch (_) {}
    }
    return [];
  }

  Future<void> saveDevices(List<WolDevice> devices) async {
    if (inMemory) {
      _memoryDevices = List.from(devices);
      return;
    }
    try {
      final file = await getStorageFile();
      final jsonList = devices.map((d) => d.toJson()).toList();
      const encoder = JsonEncoder.withIndent('  ');
      final content = encoder.convert(jsonList);
      final tmpFile = File('${file.path}.tmp');
      await tmpFile.writeAsString(content, flush: true);
      await tmpFile.rename(file.path);
    } catch (_) {
      // Storage failure handled silently or logged
    }
  }
}
