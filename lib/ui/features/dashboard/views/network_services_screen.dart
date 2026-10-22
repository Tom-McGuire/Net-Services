import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../dhcp/views/dhcp_service_panel.dart';
import '../../dns/views/dns_service_panel.dart';
import '../../ntp/views/ntp_service_panel.dart';
import '../../shared/log_detail_panel.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 4, vsync: this);
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
      body: Column(
        children: [
          // Top Control Bar
          const TopControlBar(),

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
              unselectedLabelColor: Colors.grey,
              tabs: [
                Tab(
                  icon: const Icon(Icons.router_outlined, size: 18),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('DHCP Server'),
                      if (vm.dhcpStatus.isRunning) ...[
                        const SizedBox(width: 6),
                        _indicator(Colors.green),
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
                        _indicator(Colors.green),
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
                        _indicator(Colors.green),
                      ],
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
                          style: const TextStyle(fontSize: 10, color: Colors.white70),
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
              children: const [
                DhcpServicePanel(),
                NtpServicePanel(),
                DnsServicePanel(),
                ActivityLogTableView(),
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
