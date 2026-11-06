import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/services/ntp/ntp_server_service.dart';

void main() {
  group('NtpServerService Live Socket Tests', () {
    late NtpServerService ntpService;
    const testPort = 11123;

    setUp(() {
      ntpService = NtpServerService();
    });

    tearDown(() async {
      await ntpService.stop();
    });

    test('Binds socket, responds to NTP client queries, and increments sync count', () async {
      final clientSocket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final responseCompleter = Completer<Datagram>();

      clientSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = clientSocket.receive();
          if (datagram != null && !responseCompleter.isCompleted) {
            responseCompleter.complete(datagram);
          }
        }
      });

      await ntpService.start(
        port: testPort,
        bindAddress: InternetAddress.loopbackIPv4,
      );
      expect(ntpService.status.isRunning, isTrue);
      expect(ntpService.status.port, equals(testPort));
      expect(ntpService.syncCount, equals(0));

      // Construct 48-byte NTP client request packet (Mode 3, VN 4)
      final request = Uint8List(48);
      request[0] = (0 << 6) | (4 << 3) | 3; // Mode 3 (Client), Version 4
      // Set transmit timestamp dummy bytes
      for (int i = 40; i < 48; i++) {
        request[i] = i;
      }

      clientSocket.send(request, InternetAddress.loopbackIPv4, testPort);

      final reply = await responseCompleter.future.timeout(const Duration(seconds: 2));
      expect(reply.data.length, equals(48));

      // Check reply header
      final mode = reply.data[0] & 0x07;
      final stratum = reply.data[1];
      expect(mode, equals(4)); // Mode 4 (Server)
      expect(stratum, equals(10)); // Stratum 10 local clock
      expect(ntpService.syncCount, equals(1));

      // Stop service
      await ntpService.stop();
      expect(ntpService.status.isRunning, isFalse);

      clientSocket.close();
    });
  });
}
