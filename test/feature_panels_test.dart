import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/repositories/network_services_repository.dart';
import 'package:net_services/data/services/storage/settings_storage_service.dart';
import 'package:net_services/data/services/wol/wol_storage_service.dart';
import 'package:net_services/domain/models/service_log_record.dart';
import 'package:net_services/domain/models/wol_device.dart';
import 'package:net_services/ui/features/dashboard/view_models/network_services_view_model.dart';
import 'package:net_services/ui/features/dashboard/views/activity_log_table_view.dart';
import 'package:net_services/ui/features/dashboard/views/global_error_banner.dart';
import 'package:net_services/ui/features/dns/views/dns_service_panel.dart';
import 'package:net_services/ui/features/ntp/views/ntp_service_panel.dart';
import 'package:net_services/ui/features/shared/port_input_field.dart';
import 'package:net_services/ui/features/wol/views/wol_service_panel.dart';
import 'package:provider/provider.dart';

Widget _buildTestApp(Widget child, NetworkServicesViewModel vm) {
  return ChangeNotifierProvider<NetworkServicesViewModel>.value(
    value: vm,
    child: MaterialApp(
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  group('Feature Panels & Widget Tests', () {
    late NetworkServicesRepository repository;
    late NetworkServicesViewModel viewModel;

    setUp(() {
      repository = NetworkServicesRepository(
        customStorage: WolStorageService(inMemory: true),
        customSettingsStorage: SettingsStorageService(inMemory: true),
      );
      viewModel = NetworkServicesViewModel(repository: repository);
    });

    tearDown(() {
      viewModel.dispose();
    });

    testWidgets('DnsServicePanel adds records and sets upstream DNS forwarder', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(const DnsServicePanel(), viewModel));
      await tester.pumpAndSettle();

      expect(find.text('DNS Server'), findsOneWidget);
      expect(find.text('Static Host Records & Forwarding'), findsOneWidget);

      // Enter upstream forwarder into the textfield labeled 'Upstream DNS Forwarder (Optional)'
      final upstreamFinder = find.widgetWithText(TextField, 'Upstream DNS Forwarder (Optional)');
      await tester.enterText(upstreamFinder, '8.8.8.8');
      await tester.tap(find.text('Set Forwarder'));
      await tester.pumpAndSettle();

      expect(viewModel.upstreamDnsIp, equals('8.8.8.8'));

      // Add a DNS record
      final domainFinder = find.widgetWithText(TextField, 'Domain (e.g. gateway.local, *.lab.local, *)');
      final ipFinder = find.widgetWithText(TextField, 'IP (e.g. 192.168.1.1)');

      await tester.enterText(domainFinder, 'nas.lan');
      await tester.enterText(ipFinder, '192.168.1.50');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(viewModel.dnsRecords.length, equals(1));
      expect(viewModel.dnsRecords.first.domain, equals('nas.lan'));
      expect(find.text('nas.lan'), findsOneWidget);

      // Remove DNS record
      final removeButton = find.byIcon(Icons.close);
      await tester.tap(removeButton);
      await tester.pumpAndSettle();

      expect(viewModel.dnsRecords, isEmpty);
    });

    testWidgets('NtpServicePanel renders clock, port selector, and toggle button', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(const NtpServicePanel(), viewModel));
      await tester.pumpAndSettle();

      expect(find.text('Network Time (NTP) Server'), findsOneWidget);
      expect(find.text('Local System Time'), findsOneWidget);
      expect(find.text('UTC Clock Reference'), findsOneWidget);
      expect(find.text('Start NTP'), findsOneWidget);
    });

    testWidgets('ActivityLogTableView renders search, filter dropdown, and table headers', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      repository.logServiceEvent(
        serviceType: ServiceType.dns,
        action: 'QUERY',
        summary: 'Incoming query for home.local',
      );

      await tester.pumpWidget(_buildTestApp(const ActivityLogTableView(), viewModel));
      await tester.pumpAndSettle();

      expect(find.text('Filter:'), findsOneWidget);
      expect(find.text('All Services'), findsOneWidget);
      expect(find.text('Incoming query for home.local'), findsOneWidget);
    });

    testWidgets('GlobalErrorBanner displays error message when present', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GlobalErrorBanner(
                errorMessage: 'Failed to bind port: permission denied',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GlobalErrorBanner), findsOneWidget);
      expect(find.text('Failed to bind port: permission denied'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('WakeOnLanPanel renders device list and displays configured devices', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      viewModel.addWolDevice(const WolDevice(
        id: 'dev_1',
        name: 'Office NAS',
        macAddress: 'AA:BB:CC:DD:EE:77',
      ));

      await tester.pumpWidget(_buildTestApp(const WakeOnLanPanel(), viewModel));
      await tester.pumpAndSettle();

      expect(find.text('Office NAS'), findsOneWidget);
      expect(find.text('Wake-on-LAN (WOL)'), findsOneWidget);
      expect(find.text('Wake Device'), findsOneWidget);
    });

    testWidgets('PortInputField renders port, accepts typing, and supports presets dropdown', (WidgetTester tester) async {
      final controller = TextEditingController(text: '53');
      int? changedPort;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PortInputField(
              controller: controller,
              enabled: true,
              presets: const [53, 5353],
              onPortChanged: (val) => changedPort = val,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Port:'), findsOneWidget);
      expect(find.text('53'), findsOneWidget);

      // Enter new text
      await tester.enterText(find.byType(TextField), '1053');
      expect(changedPort, equals(1053));

      // Open presets popup
      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      await tester.pumpAndSettle();

      expect(find.text('53 (Standard)'), findsOneWidget);
      expect(find.text('5353 (Unprivileged)'), findsOneWidget);

      await tester.tap(find.text('5353 (Unprivileged)'));
      await tester.pumpAndSettle();

      expect(controller.text, equals('5353'));
      expect(changedPort, equals(5353));
    });
  });
}
