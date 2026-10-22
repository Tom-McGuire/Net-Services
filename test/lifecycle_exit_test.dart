import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/repositories/network_services_repository.dart';
import 'package:net_services/domain/models/service_status.dart';
import 'package:net_services/ui/features/dashboard/view_models/network_services_view_model.dart';

void main() {
  group('Lifecycle and Shutdown Verification Tests', () {
    test('stopAll cleanly shuts down all services', () async {
      final repository = NetworkServicesRepository();
      final vm = NetworkServicesViewModel(repository: repository);

      // Start all on unprivileged test ports
      await repository.startDns(port: 5353);
      await repository.startNtp(port: 1123);
      await repository.startDhcp(port: 6767);

      expect(repository.dnsStatus.isRunning, isTrue);
      expect(repository.ntpStatus.isRunning, isTrue);
      expect(repository.dhcpStatus.isRunning, isTrue);

      // Trigger shutdown
      await vm.stopAll();

      // Verify all are stopped
      expect(repository.dnsStatus.state, equals(ServiceState.stopped));
      expect(repository.ntpStatus.state, equals(ServiceState.stopped));
      expect(repository.dhcpStatus.state, equals(ServiceState.stopped));
      expect(vm.isAnyServiceRunning, isFalse);

      vm.dispose();
    });
  });
}
