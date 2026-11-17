import 'dart:ui' show AppExitResponse;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/guided_tour_overlay.dart';
import '../../dhcp/views/dhcp_service_panel.dart';
import '../../dns/views/dns_service_panel.dart';
import '../../ntp/views/ntp_service_panel.dart';
import '../../shared/log_detail_panel.dart';
import '../../wol/views/wol_service_panel.dart';
import '../view_models/network_services_view_model.dart';
import 'activity_log_table_view.dart';
import 'global_error_banner.dart';
import 'top_control_bar.dart';

class NetworkServicesScreen extends StatefulWidget {
  const NetworkServicesScreen({super.key});

  @override
  State<NetworkServicesScreen> createState() => _NetworkServicesScreenState();
}

class _NetworkServicesScreenState extends State<NetworkServicesScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;

  final GlobalKey _zone2Key = GlobalKey();
  final GlobalKey _zone3Key = GlobalKey();
  final GlobalKey _dhcpPanelKey = GlobalKey();
  final GlobalKey _dnsPanelKey = GlobalKey();
  final GlobalKey _activityLogKey = GlobalKey();
  final GlobalKey _exitDemoKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(
      length: 5,
      vsync: this,
      animationDuration: Duration.zero,
    );
  }

  void _jumpToTab(int index) {
    if (!mounted) return;
    if (_tabController.index != index) {
      _tabController.animateTo(index, duration: Duration.zero);
    }
  }

  List<GuidedTourStep> _buildTourSteps(NetworkServicesViewModel vm) {
    return [
      GuidedTourStep(
        targetKey: _zone2Key,
        title: 'Zone 2: Server Bind Interface',
        description:
            'Select the local network adapter IP that the standalone DHCP, DNS, and NTP servers bind to, refresh available interfaces, and verify OS privilege status.',
      ),
      GuidedTourStep(
        targetKey: _zone3Key,
        title: 'Zone 3: Individual & Master Service Controls',
        description:
            'Start or stop DHCP, DNS, and NTP simultaneously using the master control, or manage each server independently from its dedicated tab.',
      ),
      GuidedTourStep(
        targetKey: _dhcpPanelKey,
        title: 'DHCP Scope & Active Leases Panel',
        description:
            'Configure your IP pool range, subnet mask, gateway, and lease duration, and inspect assigned client leases or static MAC-to-IP reservations.',
        onStepEnter: () => _jumpToTab(0),
      ),
      GuidedTourStep(
        targetKey: _dnsPanelKey,
        title: 'DNS Local Records & Forwarder Panel',
        description:
            'Add custom local domain overrides (A records) and wildcards for lab testing, and optionally configure an upstream DNS forwarder.',
        onStepEnter: () => _jumpToTab(2),
      ),
      GuidedTourStep(
        targetKey: _activityLogKey,
        title: 'Live Protocol Transaction Log',
        description:
            'Monitor real-time DHCPDISCOVER/DHCPACK transactions, DNS queries, NTP time sync replies, and Wake-on-LAN packets. Select any row to inspect full details.',
        onStepEnter: () {
          _jumpToTab(4);
          if (vm.selectedLog == null && vm.filteredLogs.isNotEmpty) {
            vm.selectLog(vm.filteredLogs.first);
          }
        },
      ),
    ];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    final vm = Provider.of<NetworkServicesViewModel>(context, listen: false);
    await vm.stopAll();
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NetworkServicesViewModel>();
    final errorMsg = vm.activeErrorMessage;
    final selectedLog = vm.selectedLog;

    return Scaffold(
      body: GuidedTourOverlay(
        isActive: vm.isDemoMode,
        steps: _buildTourSteps(vm),
        exitTargetKey: _exitDemoKey,
        onFinish: () => vm.endDemoWalkthrough(),
        child: Column(
          children: [
            // Top Control Bar
            TopControlBar(
              zone2Key: _zone2Key,
              zone3Key: _zone3Key,
              exitDemoKey: _exitDemoKey,
            ),

          // Socket error banner if present
          if (errorMsg != null)
            GlobalErrorBanner(errorMessage: errorMsg),

          // Navigation Tab Bar
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: Theme.of(context).colorScheme.primary,
              indicatorWeight: 3,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: AppTheme.textSecondary,
              tabs: [
                Tab(
                  icon: const Icon(Icons.router_outlined, size: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('DHCP Server'),
                      if (vm.dhcpStatus.isRunning) ...[
                        const SizedBox(width: 6),
                        _indicator(AppTheme.success),
                      ],
                    ],
                  ),
                ),
                Tab(
                  icon: const Icon(Icons.access_time_outlined, size: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('NTP Time Server'),
                      if (vm.ntpStatus.isRunning) ...[
                        const SizedBox(width: 6),
                        _indicator(AppTheme.success),
                      ],
                    ],
                  ),
                ),
                Tab(
                  icon: const Icon(Icons.dns_outlined, size: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('DNS Server'),
                      if (vm.dnsStatus.isRunning) ...[
                        const SizedBox(width: 6),
                        _indicator(AppTheme.success),
                      ],
                    ],
                  ),
                ),
                Tab(
                  icon: const Icon(Icons.bolt_outlined, size: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Wake-on-LAN'),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          vm.wolDevices.length.toString(),
                          style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  icon: const Icon(Icons.list_alt_outlined, size: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Activity Logs'),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          vm.filteredLogs.length.toString(),
                          style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

            // Main View Tabs
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  DhcpServicePanel(key: _dhcpPanelKey),
                  const NtpServicePanel(),
                  DnsServicePanel(key: _dnsPanelKey),
                  const WakeOnLanPanel(),
                  ActivityLogTableView(key: _activityLogKey),
                ],
              ),
            ),

            // Collapsible Bottom Log Detail Inspector
            if (selectedLog != null)
              LogDetailPanel(
                record: selectedLog,
                onClose: () => vm.selectLog(null),
              ),
          ],
        ),
      ),
    );
  }

  Widget _indicator(Color color) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
