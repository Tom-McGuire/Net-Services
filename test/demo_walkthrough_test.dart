import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:net_services/data/repositories/network_services_repository.dart';
import 'package:net_services/data/services/storage/settings_storage_service.dart';
import 'package:net_services/data/services/wol/wol_storage_service.dart';
import 'package:net_services/domain/models/network_interface_info.dart';
import 'package:net_services/main.dart';
import 'package:net_services/ui/features/dashboard/view_models/network_services_view_model.dart';
import 'package:net_services/ui/features/dashboard/views/activity_log_table_view.dart';
import 'package:net_services/ui/features/dhcp/views/dhcp_service_panel.dart';
import 'package:net_services/ui/features/dns/views/dns_service_panel.dart';
import 'package:net_services/ui/features/shared/log_detail_panel.dart';
import 'package:net_services/ui/theme/app_theme.dart';
import 'package:net_services/ui/widgets/guided_tour_overlay.dart';
import 'package:network_suite_shared/network_suite_shared.dart';

void main() {
  late WolStorageService wolStorage;
  late SettingsStorageService settingsStorage;
  late NetworkServicesRepository repository;
  late NetworkServicesViewModel viewModel;

  setUp(() async {
    AppTheme.applyThemeMode('dark');
    await SharedDeviceDatabase.instance.init(dbPath: ':memory:');
    await SharedDeviceDatabase.instance.setThemeMode('dark');

    wolStorage = WolStorageService(inMemory: true);
    settingsStorage = SettingsStorageService(inMemory: true);
    repository = NetworkServicesRepository(
      customStorage: wolStorage,
      customSettingsStorage: settingsStorage,
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
    AppTheme.applyThemeMode('dark');
    if (SharedDeviceDatabase.instance.isInitialized) {
      await SharedDeviceDatabase.instance.setThemeMode('dark');
    }
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      NetworkServicesApp(
        viewModel: viewModel,
        database: SharedDeviceDatabase.instance,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Demo Walkthrough Spotlight & Auto-Clear', () {
    testWidgets(
      'Load Demo starts walkthrough, populates demo data, highlights Step 1, and toggles button to amber Exit Demo',
      (tester) async {
        await pumpApp(tester);

        expect(viewModel.isDemoMode, isFalse);
        expect(viewModel.dnsRecords, isEmpty);
        expect(viewModel.dhcpLeases, isEmpty);
        expect(viewModel.wolDevices, isEmpty);
        expect(viewModel.filteredLogs, isEmpty);
        expect(find.text('Load Demo'), findsOneWidget);
        expect(find.byType(GuidedTourOverlay), findsOneWidget);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isTrue);
        expect(viewModel.dnsRecords.any((r) => r.domain == 'router.lab'), isTrue);
        expect(viewModel.dnsRecords.any((r) => r.domain == 'nas.lab'), isTrue);
        expect(viewModel.dnsRecords.any((r) => r.domain == '*.lab'), isTrue);
        expect(viewModel.dhcpLeases.length, 3);
        expect(viewModel.wolDevices.length, 2);
        expect(viewModel.filteredLogs.length, 4);
        expect(viewModel.selectedLog, isNull);

        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 5'), findsOneWidget);
        expect(find.text('Zone 2: Server Bind Interface'), findsOneWidget);
        expect(find.text('Exit Demo'), findsOneWidget);
        expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

        final stopIcon = tester.widget<Icon>(
          find.byIcon(Icons.stop_circle_outlined),
        );
        expect(stopIcon.color, AppTheme.warning);
      },
    );

    testWidgets(
      'Walkthrough steps 1..5 in order (switching tabs & selecting log on step 5), supports Back/Next, and Finish & Clear auto-clears all demo data',
      (tester) async {
        await pumpApp(tester);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();

        // Step 1
        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 5'), findsOneWidget);
        expect(find.text('Zone 2: Server Bind Interface'), findsOneWidget);

        // Step 2
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 5'), findsOneWidget);
        expect(
          find.text('Zone 3: Individual & Master Service Controls'),
          findsOneWidget,
        );

        // Step 3 -> DHCP Panel
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 3 OF 5'), findsOneWidget);
        expect(find.text('DHCP Scope & Active Leases Panel'), findsOneWidget);
        expect(find.byType(DhcpServicePanel), findsOneWidget);

        // Step 4 -> DNS Panel
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 4 OF 5'), findsOneWidget);
        expect(
          find.text('DNS Local Records & Forwarder Panel'),
          findsOneWidget,
        );
        expect(find.byType(DnsServicePanel), findsOneWidget);
        expect(find.text('router.lab'), findsOneWidget);

        // Step 5 -> Activity Log Table + LogDetailPanel auto-opened
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 5 OF 5'), findsOneWidget);
        expect(find.text('Live Protocol Transaction Log'), findsOneWidget);
        expect(find.text('Finish & Clear'), findsOneWidget);
        expect(find.byType(ActivityLogTableView), findsOneWidget);
        expect(viewModel.selectedLog, isNotNull);
        expect(find.byType(LogDetailPanel), findsOneWidget);

        // Verify Back navigation from Step 5 to Step 4 switches back to DNS Panel
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 4 OF 5'), findsOneWidget);
        expect(find.byType(DnsServicePanel), findsOneWidget);

        // Return to Step 5 and click Finish & Clear
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('Finish & Clear'), findsOneWidget);

        await tester.tap(find.text('Finish & Clear'));
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isFalse);
        expect(viewModel.dnsRecords, isEmpty);
        expect(viewModel.dhcpLeases, isEmpty);
        expect(viewModel.wolDevices, isEmpty);
        expect(viewModel.filteredLogs, isEmpty);
        expect(repository.logs, isEmpty);
        expect(viewModel.selectedLog, isNull);
        expect(find.text('Load Demo'), findsOneWidget);
        expect(find.text('Exit Demo'), findsNothing);
        expect(find.text('DEMO WALKTHROUGH • STEP 5 OF 5'), findsNothing);
      },
    );

    testWidgets(
      'End Demo button exits walkthrough and auto-clears all demo data',
      (tester) async {
        await pumpApp(tester);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();
        expect(viewModel.isDemoMode, isTrue);
        expect(find.text('End Demo'), findsOneWidget);

        await tester.tap(find.text('End Demo'));
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isFalse);
        expect(viewModel.dnsRecords, isEmpty);
        expect(viewModel.dhcpLeases, isEmpty);
        expect(viewModel.wolDevices, isEmpty);
        expect(viewModel.filteredLogs, isEmpty);
        expect(find.text('Load Demo'), findsOneWidget);
      },
    );

    testWidgets(
      'Exit Demo button in TopControlBar remains clickable during active tour and auto-clears demo data',
      (tester) async {
        await pumpApp(tester);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();

        // Advance to Step 2 so we verify Exit Demo works at any step
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 5'), findsOneWidget);

        // Stray click on a background tab should be swallowed by the overlay.
        await tester.tapAt(tester.getCenter(find.text('NTP Time Server')));
        await tester.pumpAndSettle();
        expect(viewModel.isDemoMode, isTrue);
        expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 5'), findsOneWidget);

        // Tap Exit Demo in TopControlBar (handled via exitTargetKey pass-through)
        await tester.tapAt(tester.getCenter(find.text('Exit Demo')));
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isFalse);
        expect(viewModel.dnsRecords, isEmpty);
        expect(viewModel.dhcpLeases, isEmpty);
        expect(viewModel.wolDevices, isEmpty);
        expect(viewModel.filteredLogs, isEmpty);
        expect(find.text('Load Demo'), findsOneWidget);
        expect(find.text('Exit Demo'), findsNothing);
      },
    );

    testWidgets(
      'Keyboard navigation supports ArrowRight, Enter, ArrowLeft, and Escape auto-clear',
      (tester) async {
        await pumpApp(tester);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 5'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 3 OF 5'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 5'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 5'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 5'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isFalse);
        expect(viewModel.dnsRecords, isEmpty);
        expect(viewModel.dhcpLeases, isEmpty);
        expect(viewModel.wolDevices, isEmpty);
        expect(viewModel.filteredLogs, isEmpty);
        expect(find.text('Load Demo'), findsOneWidget);
      },
    );

    testWidgets(
      'GuidedTourOverlay renders cleanly in Light Mode and restores cleanly',
      (tester) async {
        await SharedDeviceDatabase.instance.setThemeMode('light');
        AppTheme.applyThemeMode('light');

        await pumpApp(tester);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();

        expect(AppTheme.isDark, isFalse);
        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 5'), findsOneWidget);
        expect(find.text('Exit Demo'), findsOneWidget);

        await tester.tap(find.text('End Demo'));
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isFalse);
        expect(viewModel.filteredLogs, isEmpty);
        expect(find.text('Load Demo'), findsOneWidget);
      },
    );

    testWidgets(
      'Demo walkthrough strictly isolates SharedDeviceDatabase and disk/storage persistence',
      (tester) async {
        await pumpApp(tester);

        expect(SharedDeviceDatabase.instance.getAllDevices(), isEmpty);
        expect(await wolStorage.loadDevices(), isEmpty);
        expect(await settingsStorage.loadSettings(), isNull);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();

        expect(SharedDeviceDatabase.instance.getAllDevices(), isEmpty);
        expect(await wolStorage.loadDevices(), isEmpty);
        expect(await settingsStorage.loadSettings(), isNull);

        for (var i = 0; i < 4; i++) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
          expect(SharedDeviceDatabase.instance.getAllDevices(), isEmpty);
          expect(await wolStorage.loadDevices(), isEmpty);
          expect(await settingsStorage.loadSettings(), isNull);
        }

        await tester.tap(find.text('Finish & Clear'));
        await tester.pumpAndSettle();

        expect(SharedDeviceDatabase.instance.getAllDevices(), isEmpty);
        expect(await wolStorage.loadDevices(), isEmpty);
        expect(await settingsStorage.loadSettings(), isNull);
      },
    );
  });
}
