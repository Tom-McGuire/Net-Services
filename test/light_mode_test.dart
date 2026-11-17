import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:net_services/data/repositories/network_services_repository.dart';
import 'package:net_services/data/services/storage/settings_storage_service.dart';
import 'package:net_services/data/services/wol/wol_storage_service.dart';
import 'package:net_services/domain/models/dns_record.dart';
import 'package:net_services/domain/models/network_interface_info.dart';
import 'package:net_services/domain/models/wol_device.dart';
import 'package:net_services/main.dart';
import 'package:net_services/ui/features/dashboard/view_models/network_services_view_model.dart';
import 'package:net_services/ui/features/shared/device_library_dialog.dart';
import 'package:net_services/ui/theme/app_theme.dart';
import 'package:network_suite_shared/network_suite_shared.dart';

void main() {
  tearDown(() async {
    AppTheme.applyThemeMode('dark');
    if (SharedDeviceDatabase.instance.isInitialized) {
      await SharedDeviceDatabase.instance.setThemeMode('dark');
    }
  });

  group('AppTheme Palette & SharedDeviceDatabase Persistence', () {
    test('AppTheme switches accurately between Dark and Light palettes', () {
      AppTheme.applyThemeMode('dark');
      expect(AppTheme.isDark, isTrue);
      expect(AppTheme.themeMode, 'dark');
      expect(AppTheme.scaffoldBg, const Color(0xFF141414));
      expect(AppTheme.surface, const Color(0xFF1E1E1E));
      expect(AppTheme.surfaceHigh, const Color(0xFF252526));
      expect(AppTheme.surfaceElevated, const Color(0xFF2D2D2D));
      expect(AppTheme.border, const Color(0xFF2C2C2C));
      expect(AppTheme.inputBorder, const Color(0xFF3E3E42));
      expect(AppTheme.textPrimary, const Color(0xFFE0E0E0));
      expect(AppTheme.textSecondary, const Color(0xFF9E9E9E));
      expect(AppTheme.textMuted, const Color(0xFF6E6E6E));
      expect(AppTheme.accent, const Color(0xFF007ACC));
      expect(AppTheme.success, const Color(0xFF10B981));
      expect(AppTheme.error, const Color(0xFFEF4444));
      expect(AppTheme.warning, const Color(0xFFF59E0B));
      expect(AppTheme.info, const Color(0xFF3B82F6));

      AppTheme.applyThemeMode('light');
      expect(AppTheme.isDark, isFalse);
      expect(AppTheme.themeMode, 'light');
      expect(AppTheme.scaffoldBg, const Color(0xFFF3F4F6));
      expect(AppTheme.surface, const Color(0xFFFFFFFF));
      expect(AppTheme.surfaceHigh, const Color(0xFFF9FAFB));
      expect(AppTheme.surfaceElevated, const Color(0xFFFFFFFF));
      expect(AppTheme.border, const Color(0xFFE5E7EB));
      expect(AppTheme.inputBorder, const Color(0xFFD1D5DB));
      expect(AppTheme.textPrimary, const Color(0xFF111827));
      expect(AppTheme.textSecondary, const Color(0xFF4B5563));
      expect(AppTheme.textMuted, const Color(0xFF6B7280));
      expect(AppTheme.accent, const Color(0xFF0284C7));
      expect(AppTheme.success, const Color(0xFF059669));
      expect(AppTheme.error, const Color(0xFFDC2626));
      expect(AppTheme.warning, const Color(0xFFD97706));
      expect(AppTheme.info, const Color(0xFF2563EB));
    });

    test(
      'lightTheme and darkTheme produce Material 3 ThemeData without mutating AppTheme.isDark',
      () {
        AppTheme.applyThemeMode('dark');
        expect(AppTheme.isDark, isTrue);
        final light = AppTheme.lightTheme();
        expect(AppTheme.isDark, isTrue);
        expect(light.useMaterial3, isTrue);
        expect(light.brightness, Brightness.light);
        expect(light.scaffoldBackgroundColor, const Color(0xFFF3F4F6));

        AppTheme.applyThemeMode('light');
        expect(AppTheme.isDark, isFalse);
        final dark = AppTheme.darkTheme();
        expect(AppTheme.isDark, isFalse);
        expect(dark.useMaterial3, isTrue);
        expect(dark.brightness, Brightness.dark);
        expect(dark.scaffoldBackgroundColor, const Color(0xFF141414));

        expect(AppTheme.currentTheme.brightness, Brightness.light);
        AppTheme.applyThemeMode('dark');
        expect(AppTheme.currentTheme.brightness, Brightness.dark);
      },
    );

    test(
      'SharedDeviceDatabaseThemeExt persists theme mode across instances on disk',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'net_services_theme_test_',
        );
        final dbWriter = SharedDeviceDatabase();
        final dbReader = SharedDeviceDatabase();
        try {
          final dbPath =
              '${tempDir.path}${Platform.pathSeparator}shared_devices.db';

          await dbWriter.init(dbPath: dbPath);
          expect(await dbWriter.getThemeMode(), 'dark');

          await dbWriter.setThemeMode('light');
          expect(await dbWriter.getThemeMode(), 'light');

          await dbReader.init(dbPath: dbPath);
          expect(await dbReader.getThemeMode(), 'light');

          await dbWriter.setThemeMode('dark');
          expect(await dbReader.getThemeMode(), 'dark');

          await expectLater(
            () => dbWriter.setThemeMode('system'),
            throwsArgumentError,
          );
        } finally {
          dbReader.close();
          dbWriter.close();
          await tempDir.delete(recursive: true);
        }
      },
    );
  });

  group('NetworkServicesApp Light Mode Widget Rendering', () {
    late NetworkServicesRepository repository;
    late NetworkServicesViewModel viewModel;

    setUp(() async {
      await SharedDeviceDatabase.instance.init(dbPath: ':memory:');
      repository = NetworkServicesRepository(
        customStorage: WolStorageService(inMemory: true),
        customSettingsStorage: SettingsStorageService(inMemory: true),
        interfacesProvider: () async => const [
          NetworkInterfaceInfo(
            name: 'eth0',
            ip: '192.168.1.10',
            subnetMask: '255.255.255.0',
            prefixLength: 24,
            defaultGateway: '192.168.1.1',
          ),
        ],
      );
      viewModel = NetworkServicesViewModel(repository: repository);
      await viewModel.refreshInterfaces();
    });

    tearDown(() async {
      viewModel.dispose();
    });

    testWidgets(
      'Starts cleanly in Light Mode and renders UI tabs and dialogs without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await SharedDeviceDatabase.instance.setThemeMode('light');
        AppTheme.applyThemeMode('light');

        await tester.pumpWidget(
          NetworkServicesApp(
            viewModel: viewModel,
            database: SharedDeviceDatabase.instance,
          ),
        );
        await tester.pumpAndSettle();

        final materialApp = tester.widget<MaterialApp>(
          find.byType(MaterialApp),
        );
        expect(materialApp.themeMode, ThemeMode.light);

        final titleText = tester.widget<Text>(find.text('NETWORK SERVICES'));
        expect(titleText.style?.color, const Color(0xFF111827));

        final subtitleText =
            tester.widget<Text>(find.text('DHCP • DNS • NTP • WOL'));
        expect(subtitleText.style?.color, const Color(0xFF4B5563));

        // Verify Load Demo opens Light Mode tour and End Demo exits cleanly,
        // then populate sample records and walk through all tabs + dialogs in Light Mode.
        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 5'), findsOneWidget);
        await tester.tap(find.text('End Demo'));
        await tester.pumpAndSettle();

        viewModel.addDnsRecord(
          const DnsRecord(domain: 'router.lab', ip: '192.168.1.1'),
        );
        await viewModel.addWolDevice(
          const WolDevice(
            id: 'light_demo_1',
            name: 'Studio Workstation',
            macAddress: '3C:06:30:AA:BB:CC',
            ipAddress: '192.168.1.105',
          ),
        );
        await tester.pumpAndSettle();

        // Check DHCP Static Reservations sub-tab too.
        await tester.tap(find.textContaining('Static Reservations'));
        await tester.pumpAndSettle();
        expect(find.text('Configured Static IP Reservations'), findsOneWidget);

        await tester.tap(find.text('NTP Time Server'));
        await tester.pumpAndSettle();
        expect(find.text('Local System Time'), findsOneWidget);

        await tester.tap(find.text('DNS Server').first);
        await tester.pumpAndSettle();
        expect(find.text('router.lab'), findsOneWidget);

        await tester.tap(find.text('Wake-on-LAN'));
        await tester.pumpAndSettle();
        expect(find.text('Studio Workstation'), findsOneWidget);

        await tester.tap(find.text('Activity Logs'));
        await tester.pumpAndSettle();
        expect(find.text('All Services'), findsOneWidget);

        // Open LogDetailPanel if a log exists, or open Device Library + Add Device dialog.
        await tester.tap(find.text('Device Library'));
        await tester.pumpAndSettle();
        expect(find.byType(DeviceLibraryDialog), findsOneWidget);

        await tester.tap(find.text('Add Device'));
        await tester.pumpAndSettle();
        expect(find.text('Add Device to Library'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(DeviceLibraryDialog), findsNothing);
      },
    );

    testWidgets('Starts cleanly in Dark Mode with dark palette tokens', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await SharedDeviceDatabase.instance.setThemeMode('dark');
      AppTheme.applyThemeMode('dark');

      await tester.pumpWidget(
        NetworkServicesApp(
          viewModel: viewModel,
          database: SharedDeviceDatabase.instance,
        ),
      );
      await tester.pumpAndSettle();

      final materialApp = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      expect(materialApp.themeMode, ThemeMode.dark);

      final titleText = tester.widget<Text>(find.text('NETWORK SERVICES'));
      expect(titleText.style?.color, const Color(0xFFE0E0E0));
    });

    testWidgets(
      'Updates MaterialApp and widget colors live when SharedDeviceDatabase theme changes',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await SharedDeviceDatabase.instance.setThemeMode('dark');
        AppTheme.applyThemeMode('dark');

        await tester.pumpWidget(
          NetworkServicesApp(
            viewModel: viewModel,
            database: SharedDeviceDatabase.instance,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.dark,
        );
        expect(
          tester.widget<Text>(find.text('NETWORK SERVICES')).style?.color,
          const Color(0xFFE0E0E0),
        );

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();
        expect(viewModel.dnsRecords, isNotEmpty);
        final recordCountBefore = viewModel.dnsRecords.length;

        await SharedDeviceDatabase.instance.setThemeMode('light');
        await tester.pumpAndSettle();

        expect(AppTheme.isDark, isFalse);
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.light,
        );
        expect(
          tester.widget<Text>(find.text('NETWORK SERVICES')).style?.color,
          const Color(0xFF111827),
        );
        expect(viewModel.dnsRecords.length, equals(recordCountBefore));

        await SharedDeviceDatabase.instance.setThemeMode('dark');
        await tester.pumpAndSettle();

        expect(AppTheme.isDark, isTrue);
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.dark,
        );
        expect(
          tester.widget<Text>(find.text('NETWORK SERVICES')).style?.color,
          const Color(0xFFE0E0E0),
        );
        expect(viewModel.dnsRecords.length, equals(recordCountBefore));
      },
    );
  });
}
