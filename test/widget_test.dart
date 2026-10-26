import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/main.dart';
import 'package:net_services/ui/features/dashboard/views/top_control_bar.dart';

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
    expect(find.text('Activity Logs'), findsOneWidget);
  });
}
