import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import 'ui/features/dashboard/view_models/network_services_view_model.dart';
import 'ui/features/dashboard/views/network_services_screen.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Safely initialize shared database.
  // Will create directory and table if launcher is not installed.
  try {
    await SharedDeviceDatabase.instance.init();
  } catch (e) {
    debugPrint('Shared device database fallback: $e');
  }

  runApp(const NetworkServicesApp());
}

class NetworkServicesApp extends StatelessWidget {
  const NetworkServicesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NetworkServicesViewModel(),
      child: MaterialApp(
        title: 'Network Services',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme(),
        home: const NetworkServicesScreen(),
      ),
    );
  }
}
