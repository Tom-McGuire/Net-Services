import 'dart:async';
import 'dart:ui' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/repositories/network_services_repository.dart';
import 'package:net_services/data/services/storage/settings_storage_service.dart';
import 'package:net_services/data/services/wol/wol_storage_service.dart';
import 'package:net_services/domain/models/launch_adapter_config.dart';
import 'package:net_services/domain/models/network_interface_info.dart';
import 'package:net_services/main.dart';
import 'package:net_services/ui/features/dashboard/view_models/network_services_view_model.dart';
import 'package:net_services/ui/features/dashboard/views/top_control_bar.dart';
import 'package:provider/provider.dart';

const _eth0 = NetworkInterfaceInfo(
  name: 'eth0',
  ip: '192.168.1.10',
  subnetMask: '255.255.255.0',
  prefixLength: 24,
  defaultGateway: '192.168.1.1',
);

const _eth01 = NetworkInterfaceInfo(
  name: 'eth01',
  ip: '192.168.2.20',
  subnetMask: '255.255.255.0',
  prefixLength: 24,
  defaultGateway: '192.168.2.1',
);

const _wlan0 = NetworkInterfaceInfo(
  name: 'wlan0',
  ip: '10.0.0.5',
  subnetMask: '255.255.255.0',
  prefixLength: 24,
  defaultGateway: '10.0.0.1',
);

const _unassignedEth = NetworkInterfaceInfo(
  name: 'eth-down',
  ip: '0.0.0.0',
  subnetMask: '0.0.0.0',
  prefixLength: 0,
);

Future<void> _waitForNextNotification(NetworkServicesViewModel vm) async {
  final completer = Completer<void>();
  void listener() {
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  vm.addListener(listener);
  try {
    await completer.future.timeout(const Duration(seconds: 5));
  } finally {
    vm.removeListener(listener);
  }
}

void main() {
  group('NetworkInterfaceInfo value equality', () {
    test('supports == and hashCode by field values', () {
      const a = NetworkInterfaceInfo(
        name: 'eth0',
        ip: '192.168.1.10',
        subnetMask: '255.255.255.0',
        prefixLength: 24,
        defaultGateway: '192.168.1.1',
      );
      final b = NetworkInterfaceInfo(
        name: String.fromCharCodes('eth0'.codeUnits),
        ip: String.fromCharCodes('192.168.1.10'.codeUnits),
        subnetMask: '255.255.255.0',
        prefixLength: 24,
        defaultGateway: '192.168.1.1',
      );
      const c = NetworkInterfaceInfo(
        name: 'eth0',
        ip: '192.168.1.11',
        subnetMask: '255.255.255.0',
        prefixLength: 24,
        defaultGateway: '192.168.1.1',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('LaunchAdapterConfig.fromArgs', () {
    test('returns empty config for empty args', () {
      final config = LaunchAdapterConfig.fromArgs(const []);
      expect(config.adapterIp, isNull);
      expect(config.adapterName, isNull);
      expect(config.hasOverride, isFalse);
      expect(config.hasAdapterOverride, isFalse);
    });

    test('parses --adapter-ip <ip> and --adapter-name <name>', () {
      final config = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip',
        '10.0.0.5',
        '--adapter-name',
        'Wi-Fi',
      ]);

      expect(config.adapterIp, equals('10.0.0.5'));
      expect(config.adapterName, equals('Wi-Fi'));
      expect(config.hasOverride, isTrue);
      expect(config.hasAdapterOverride, isTrue);
    });

    test('parses --adapter-ip=<ip> and --adapter-name=<name>', () {
      final config = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip=192.168.50.10',
        '--adapter-name=Ethernet 2',
      ]);

      expect(config.adapterIp, equals('192.168.50.10'));
      expect(config.adapterName, equals('Ethernet 2'));
      expect(config.hasOverride, isTrue);
    });

    test('trims whitespace and ignores blank values', () {
      final trimmed = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip',
        '  10.0.0.5  ',
        '--adapter-name=  eth0  ',
      ]);
      expect(trimmed.adapterIp, equals('10.0.0.5'));
      expect(trimmed.adapterName, equals('eth0'));

      final blank = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip',
        '   ',
        '--adapter-name=',
        '--adapter-name',
        '',
      ]);
      expect(blank.adapterIp, isNull);
      expect(blank.adapterName, isNull);
      expect(blank.hasOverride, isFalse);

      const directBlank = LaunchAdapterConfig(
        adapterIp: '   ',
        adapterName: '\t',
      );
      expect(directBlank.hasOverride, isFalse);
      expect(directBlank.hasAdapterOverride, isFalse);
    });

    test('ignores trailing flags without values, flags followed by --flag, and unknown flags', () {
      final trailing = LaunchAdapterConfig.fromArgs(const [
        '--unknown',
        'value',
        '--adapter-ip',
      ]);
      expect(trailing.adapterIp, isNull);
      expect(trailing.adapterName, isNull);
      expect(trailing.hasOverride, isFalse);

      final followedByFlag = LaunchAdapterConfig.fromArgs(const [
        '--foo=bar',
        '--adapter-ip',
        '--adapter-name',
        'wlan0',
        '--adapter-name',
        '--',
      ]);
      expect(followedByFlag.adapterIp, isNull);
      expect(followedByFlag.adapterName, equals('wlan0'));
    });

    test('implements value equality, hashCode, and toString', () {
      const a = LaunchAdapterConfig(adapterIp: '10.0.0.5', adapterName: 'wlan0');
      const b = LaunchAdapterConfig(adapterIp: '10.0.0.5', adapterName: 'wlan0');
      const c = LaunchAdapterConfig(adapterIp: '10.0.0.6', adapterName: 'wlan0');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('10.0.0.5'));
      expect(a.toString(), contains('wlan0'));
    });
  });

  group('LaunchAdapterConfig.matchInterface', () {
    test('returns null when override is absent or interfaces list is empty', () {
      const emptyConfig = LaunchAdapterConfig();
      expect(emptyConfig.matchInterface(const [_eth0, _wlan0]), isNull);

      const config = LaunchAdapterConfig(adapterIp: '10.0.0.5');
      expect(config.matchInterface(const []), isNull);
    });

    test('Priority 1: exact IPv4 match wins over name mismatch', () {
      const config = LaunchAdapterConfig(
        adapterIp: '10.0.0.5',
        adapterName: 'eth0',
      );

      final matched = config.matchInterface(const [_eth0, _wlan0]);
      expect(matched, equals(_wlan0));
      expect(config.matchAdapter(const [_eth0, _wlan0]), equals(_wlan0));
    });

    test('Priority 2: case-insensitive exact name match wins over substring match', () {
      const config = LaunchAdapterConfig(
        adapterIp: '172.16.0.99',
        adapterName: 'ETH0',
      );

      // Put _eth01 before _eth0 to verify exact match beats earlier substring.
      final matched = config.matchInterface(const [_eth01, _eth0, _wlan0]);
      expect(matched, equals(_eth0));
    });

    test('Priority 2: falls back to case-insensitive substring match when exact name misses', () {
      const config = LaunchAdapterConfig(adapterName: 'LAN0');

      final matched = config.matchInterface(const [_eth0, _wlan0]);
      expect(matched, equals(_wlan0));
    });

    test('Priority 2: skips interfaces with IP 0.0.0.0 during name matching', () {
      const config = LaunchAdapterConfig(adapterName: 'eth-down');

      final matched = config.matchInterface(const [_unassignedEth, _eth0]);
      expect(matched, isNull);

      const substringConfig = LaunchAdapterConfig(adapterName: 'eth');
      final substringMatched =
          substringConfig.matchInterface(const [_unassignedEth, _eth0]);
      expect(substringMatched, equals(_eth0));
    });

    test('Priority 3: returns null when neither IP nor name matches', () {
      const config = LaunchAdapterConfig(
        adapterIp: '172.16.99.99',
        adapterName: 'nonexistent0',
      );

      expect(config.matchInterface(const [_eth0, _wlan0]), isNull);
    });
  });

  group('NetworkServicesViewModel startup adapter override', () {
    test('pre-selects matching interface on startup via initialAdapterConfig', () async {
      final repository = NetworkServicesRepository(
        customStorage: WolStorageService(inMemory: true),
        customSettingsStorage: SettingsStorageService(inMemory: true),
        interfacesProvider: () async => const [_eth0, _wlan0],
      );

      final viewModel = NetworkServicesViewModel(
        repository: repository,
        initialAdapterConfig: LaunchAdapterConfig.fromArgs(const [
          '--adapter-ip',
          '10.0.0.5',
        ]),
      );
      addTearDown(viewModel.dispose);

      await _waitForNextNotification(viewModel);

      expect(viewModel.selectedInterface, equals(_wlan0));
      expect(viewModel.dhcpConfig.gatewayIp, equals('10.0.0.1'));
      expect(viewModel.dhcpConfig.startIp, equals('10.0.0.6'));
    });

    test('CLI override wins over persisted selectedInterfaceName on initial load', () async {
      final settingsStorage = SettingsStorageService(inMemory: true);
      await settingsStorage.saveSettings(
        const AppPersistedSettings(selectedInterfaceName: 'eth0'),
      );

      final repository = NetworkServicesRepository(
        customStorage: WolStorageService(inMemory: true),
        customSettingsStorage: settingsStorage,
        interfacesProvider: () async => const [_eth0, _wlan0],
      );

      final viewModel = NetworkServicesViewModel(
        repository: repository,
        initialAdapterConfig: const LaunchAdapterConfig(adapterName: 'wlan0'),
      );
      addTearDown(viewModel.dispose);

      await _waitForNextNotification(viewModel);

      expect(viewModel.selectedInterface, equals(_wlan0));
    });

    test('one-time startup rule: manual selection persists across refreshInterfaces', () async {
      final repository = NetworkServicesRepository(
        customStorage: WolStorageService(inMemory: true),
        customSettingsStorage: SettingsStorageService(inMemory: true),
        interfacesProvider: () async => const [_eth0, _wlan0],
      );

      final viewModel = NetworkServicesViewModel(
        repository: repository,
        initialAdapterConfig: LaunchAdapterConfig.fromArgs(const [
          '--adapter-ip',
          '10.0.0.5',
        ]),
      );
      addTearDown(viewModel.dispose);

      await _waitForNextNotification(viewModel);
      expect(viewModel.selectedInterface, equals(_wlan0));

      viewModel.selectInterface(_eth0);
      expect(viewModel.selectedInterface, equals(_eth0));

      await viewModel.refreshInterfaces();
      expect(viewModel.selectedInterface, equals(_eth0));
    });

    test('falls back to first interface when CLI override does not match', () async {
      final repository = NetworkServicesRepository(
        customStorage: WolStorageService(inMemory: true),
        customSettingsStorage: SettingsStorageService(inMemory: true),
        interfacesProvider: () async => const [_eth0, _wlan0],
      );

      final viewModel = NetworkServicesViewModel(
        repository: repository,
        initialAdapterConfig: const LaunchAdapterConfig(
          adapterIp: '172.16.0.99',
          adapterName: 'missing0',
        ),
      );
      addTearDown(viewModel.dispose);

      await _waitForNextNotification(viewModel);

      expect(viewModel.selectedInterface, equals(_eth0));
    });

    test('applies initial override once on first non-empty refresh if startup list was empty', () async {
      var available = <NetworkInterfaceInfo>[];
      final repository = NetworkServicesRepository(
        customStorage: WolStorageService(inMemory: true),
        customSettingsStorage: SettingsStorageService(inMemory: true),
        interfacesProvider: () async => available,
      );

      final viewModel = NetworkServicesViewModel(
        repository: repository,
        initialAdapterConfig: const LaunchAdapterConfig(adapterIp: '10.0.0.5'),
      );
      addTearDown(viewModel.dispose);

      await _waitForNextNotification(viewModel);
      expect(viewModel.interfaces, isEmpty);
      expect(viewModel.selectedInterface, isNull);

      available = const [_eth0, _wlan0];
      await viewModel.refreshInterfaces();
      expect(viewModel.selectedInterface, equals(_wlan0));
      expect(viewModel.dhcpConfig.gatewayIp, equals('10.0.0.1'));

      viewModel.selectInterface(_eth0);
      await viewModel.refreshInterfaces();
      expect(viewModel.selectedInterface, equals(_eth0));
    });

    testWidgets('NetworkServicesApp forwards launchAdapterConfig to ViewModel', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repository = NetworkServicesRepository(
        customStorage: WolStorageService(inMemory: true),
        customSettingsStorage: SettingsStorageService(inMemory: true),
        interfacesProvider: () async => const [],
      );

      await tester.pumpWidget(
        NetworkServicesApp(
          repository: repository,
          launchAdapterConfig: LaunchAdapterConfig.fromArgs(const [
            '--adapter-ip=10.0.0.5',
            '--adapter-name',
            'wlan0',
          ]),
        ),
      );
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(TopControlBar));
      final vm = Provider.of<NetworkServicesViewModel>(element, listen: false);
      expect(
        vm.initialAdapterConfig,
        equals(
          const LaunchAdapterConfig(
            adapterIp: '10.0.0.5',
            adapterName: 'wlan0',
          ),
        ),
      );
    });
  });
}
