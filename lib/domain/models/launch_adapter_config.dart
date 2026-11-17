import 'network_interface_info.dart';

/// Parsed CLI configuration for pre-selecting a startup network adapter.
class LaunchAdapterConfig {
  final String? adapterIp;
  final String? adapterName;

  const LaunchAdapterConfig({this.adapterIp, this.adapterName});

  bool get hasOverride =>
      (adapterIp != null && adapterIp!.trim().isNotEmpty) ||
      (adapterName != null && adapterName!.trim().isNotEmpty);

  bool get hasAdapterOverride => hasOverride;

  /// Parses `--adapter-ip` and `--adapter-name` from CLI [args].
  factory LaunchAdapterConfig.fromArgs(List<String> args) {
    String? ip;
    String? name;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--adapter-ip' || arg.startsWith('--adapter-ip=')) {
        final (value, nextIndex) = _extractOptionValue(args, i, '--adapter-ip');
        if (value != null) ip = value;
        i = nextIndex;
      } else if (arg == '--adapter-name' || arg.startsWith('--adapter-name=')) {
        final (value, nextIndex) =
            _extractOptionValue(args, i, '--adapter-name');
        if (value != null) name = value;
        i = nextIndex;
      }
    }
    return LaunchAdapterConfig(adapterIp: ip, adapterName: name);
  }

  static (String?, int) _extractOptionValue(
    List<String> args,
    int index,
    String flag,
  ) {
    final arg = args[index];
    final prefix = '$flag=';
    if (arg.startsWith(prefix)) {
      final value = arg.substring(prefix.length).trim();
      return (value.isNotEmpty ? value : null, index);
    }
    if (arg == flag &&
        index + 1 < args.length &&
        !args[index + 1].trim().startsWith('--')) {
      final value = args[index + 1].trim();
      return (value.isNotEmpty ? value : null, index + 1);
    }
    return (null, index);
  }

  /// Matches the configured startup adapter against [interfaces].
  ///
  /// Priority 1: exact IPv4 match (`iface.ip == targetIp`).
  /// Priority 2: case-insensitive exact match on `iface.name` (skipping
  /// `0.0.0.0`), then case-insensitive substring match (skipping `0.0.0.0`).
  /// Priority 3: returns `null`.
  NetworkInterfaceInfo? matchInterface(List<NetworkInterfaceInfo> interfaces) {
    if (!hasOverride || interfaces.isEmpty) return null;

    final targetIp = adapterIp?.trim();
    if (targetIp != null && targetIp.isNotEmpty) {
      for (final iface in interfaces) {
        if (iface.ip == targetIp) {
          return iface;
        }
      }
    }

    final targetName = adapterName?.trim();
    if (targetName != null && targetName.isNotEmpty) {
      final lowerTargetName = targetName.toLowerCase();
      for (final iface in interfaces) {
        if (iface.ip == '0.0.0.0') continue;
        if (iface.name.toLowerCase() == lowerTargetName) {
          return iface;
        }
      }
      for (final iface in interfaces) {
        if (iface.ip == '0.0.0.0') continue;
        if (iface.name.toLowerCase().contains(lowerTargetName)) {
          return iface;
        }
      }
    }

    return null;
  }

  NetworkInterfaceInfo? matchAdapter(List<NetworkInterfaceInfo> interfaces) =>
      matchInterface(interfaces);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchAdapterConfig &&
          runtimeType == other.runtimeType &&
          adapterIp == other.adapterIp &&
          adapterName == other.adapterName;

  @override
  int get hashCode => Object.hash(adapterIp, adapterName);

  @override
  String toString() =>
      'LaunchAdapterConfig(adapterIp: $adapterIp, adapterName: $adapterName)';
}
