import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';

import 'data/repositories/network_services_repository.dart';
import 'domain/models/launch_adapter_config.dart';
import 'ui/features/dashboard/view_models/network_services_view_model.dart';
import 'ui/features/dashboard/views/network_services_screen.dart';
import 'ui/theme/app_theme.dart';

Future<void> main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  final launchAdapterConfig = LaunchAdapterConfig.fromArgs(args);

  // Safely initialize shared database.
  // Will create directory and table if launcher is not installed.
  try {
    await SharedDeviceDatabase.instance.init();
    final mode = await SharedDeviceDatabase.instance.getThemeMode();
    AppTheme.applyThemeMode(mode);
  } catch (e) {
    debugPrint('Shared device database fallback: $e');
  }

  runApp(NetworkServicesApp(launchAdapterConfig: launchAdapterConfig));
}

class NetworkServicesApp extends StatefulWidget {
  final NetworkServicesRepository? repository;
  final LaunchAdapterConfig? launchAdapterConfig;
  final NetworkServicesViewModel? viewModel;
  final SharedDeviceDatabase? database;

  const NetworkServicesApp({
    super.key,
    this.repository,
    this.launchAdapterConfig,
    this.viewModel,
    this.database,
  });

  @override
  State<NetworkServicesApp> createState() => _NetworkServicesAppState();
}

class _NetworkServicesAppState extends State<NetworkServicesApp> {
  late ThemeMode _themeMode;
  StreamSubscription<void>? _dbSubscription;
  Timer? _pollTimer;

  SharedDeviceDatabase get _db =>
      widget.database ?? SharedDeviceDatabase.instance;

  ThemeMode get _currentThemeMode =>
      AppTheme.isDark ? ThemeMode.dark : ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _themeMode = _currentThemeMode;
    _syncTheme();
    _dbSubscription = _db.onDatabaseChanged.listen((_) => _syncTheme());
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _syncTheme(),
      );
    }
  }

  Future<void> _syncTheme() async {
    try {
      final modeStr = await _db.getThemeMode();
      AppTheme.applyThemeMode(modeStr);
      final nextMode = _currentThemeMode;
      if (mounted && _themeMode != nextMode) {
        setState(() {
          _themeMode = nextMode;
        });
      }
    } catch (_) {
      // Ignore if shared database is unavailable during initialization.
    }
  }

  @override
  void dispose() {
    _dbSubscription?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'Network Services',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: KeyedSubtree(
        key: ValueKey(_themeMode),
        child: const NetworkServicesScreen(),
      ),
    );

    if (widget.viewModel != null) {
      return ChangeNotifierProvider<NetworkServicesViewModel>.value(
        value: widget.viewModel!,
        child: app,
      );
    }

    return ChangeNotifierProvider<NetworkServicesViewModel>(
      create: (_) => NetworkServicesViewModel(
        repository: widget.repository,
        initialAdapterConfig: widget.launchAdapterConfig,
      ),
      child: app,
    );
  }
}
