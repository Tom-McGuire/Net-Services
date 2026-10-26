import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/domain/models/service_log_record.dart';
import 'package:net_services/main.dart';
import 'package:net_services/ui/features/dashboard/views/top_control_bar.dart';
import 'package:net_services/ui/features/shared/log_detail_panel.dart';

void main() {
  testWidgets('NetworkServicesApp smoke test renders TopControlBar and service tabs', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const NetworkServicesApp());
    await tester.pumpAndSettle();

    // Verify top title and main control bar render
    expect(find.byType(TopControlBar), findsOneWidget);
    expect(find.text('Network Services'), findsOneWidget);
    expect(find.text('DHCP Server'), findsWidgets);
    expect(find.text('NTP Time Server'), findsOneWidget);
    expect(find.text('DNS Server'), findsWidgets);
    expect(find.text('Wake-on-LAN'), findsWidgets);
    expect(find.byIcon(Icons.bolt_outlined), findsOneWidget);
    expect(find.text('Activity Logs'), findsOneWidget);
  });

  testWidgets('LogDetailPanel is vertically resizable via drag handle and maximize button', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final record = ServiceLogRecord(
      id: 'test_log_1',
      serviceType: ServiceType.wol,
      action: 'MAGIC_PACKET',
      summary: 'Sent Wake-on-LAN Magic Packet to "Server" (AA:BB:CC:DD:EE:FF)',
      details: 'Payload 102 bytes\nLine 2\nLine 3',
      timestamp: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              LogDetailPanel(
                record: record,
                onClose: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Event Inspector: WOL - MAGIC_PACKET'), findsOneWidget);

    // Initial height check
    final initialSize = tester.getSize(find.byType(LogDetailPanel));
    expect(initialSize.height, equals(260.0));

    // Drag the resize handle up to increase height
    final handleFinder = find.byKey(const Key('log_detail_resize_handle'));
    await tester.drag(handleFinder, const Offset(0, -100));
    await tester.pumpAndSettle();

    final draggedSize = tester.getSize(find.byType(LogDetailPanel));
    expect(draggedSize.height, equals(340.0));

    // Test maximize toggle button
    final maximizeButton = find.byIcon(Icons.unfold_more);
    expect(maximizeButton, findsOneWidget);
    await tester.tap(maximizeButton);
    await tester.pumpAndSettle();

    final maximizedSize = tester.getSize(find.byType(LogDetailPanel));
    expect(maximizedSize.height, greaterThan(500.0));
  });
}
