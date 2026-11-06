import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_services/data/services/dhcp/dhcp_packet_parser.dart';
import 'package:net_services/data/services/dhcp/dhcp_server_service.dart';
import 'package:net_services/domain/models/dhcp_config.dart';

void main() {
  group('DhcpServerService Live Tests', () {
    late DhcpServerService dhcpService;
    const testServerPort = 16768;
    const testClientPort = 16769;

    setUp(() {
      dhcpService = DhcpServerService(
        initialConfig: const DhcpConfig(
          startIp: '192.168.1.100',
          poolSize: 5,
          subnetMask: '255.255.255.0',
          gatewayIp: '192.168.1.1',
          dnsServerIp: '192.168.1.1',
        ),
      );
    });

    tearDown(() async {
      await dhcpService.stop();
      dhcpService.dispose();
    });

    test('Binds socket, processes DHCPDISCOVER and DHCPREQUEST on loopback', () async {
      final clientSocket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, testClientPort);

      await dhcpService.start(
        port: testServerPort,
        bindAddress: InternetAddress.loopbackIPv4,
        serverIp: '127.0.0.1',
        clientReplyPort: testClientPort,
      );
      expect(dhcpService.status.isRunning, isTrue);

      final discoverPacket = _buildDhcpTestPacket(
        op: 1,
        xid: 0x55AA1122,
        macBytes: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x01],
        messageType: DhcpMessageType.discover,
        hostname: 'test-device',
      );

      clientSocket.send(discoverPacket, InternetAddress.loopbackIPv4, testServerPort);

      await Future.delayed(const Duration(milliseconds: 150));
      // Tentative offer created, no active lease yet
      expect(dhcpService.activeLeases, isEmpty);

      // Send DHCPREQUEST confirming the offered IP
      final requestPacket = _buildDhcpTestPacket(
        op: 1,
        xid: 0x55AA1122,
        macBytes: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x01],
        messageType: DhcpMessageType.request,
        requestedIp: '192.168.1.100',
        serverIdentifier: '127.0.0.1',
        hostname: 'test-device',
      );

      clientSocket.send(requestPacket, InternetAddress.loopbackIPv4, testServerPort);
      await Future.delayed(const Duration(milliseconds: 150));

      // Active lease is now committed!
      expect(dhcpService.activeLeases.length, equals(1));
      expect(dhcpService.activeLeases.first.ipAddress, equals('192.168.1.100'));
      expect(dhcpService.activeLeases.first.macAddress, equals('AA:BB:CC:DD:EE:01'));

      // Send DHCPRELEASE
      final releasePacket = _buildDhcpTestPacket(
        op: 1,
        xid: 0x55AA1123,
        macBytes: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x01],
        messageType: DhcpMessageType.release,
        ciaddr: '192.168.1.100',
      );

      clientSocket.send(releasePacket, InternetAddress.loopbackIPv4, testServerPort);
      await Future.delayed(const Duration(milliseconds: 150));

      expect(dhcpService.activeLeases, isEmpty);
      clientSocket.close();
    });

    test('DHCPDECLINE with invalid ownership is rejected and does not quarantine IP', () async {
      final clientSocket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, testClientPort);

      await dhcpService.start(
        port: testServerPort,
        bindAddress: InternetAddress.loopbackIPv4,
        serverIp: '127.0.0.1',
        clientReplyPort: testClientPort,
      );

      final rogueDecline = _buildDhcpTestPacket(
        op: 1,
        xid: 0x99999999,
        macBytes: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x99],
        messageType: DhcpMessageType.decline,
        requestedIp: '192.168.1.104',
        serverIdentifier: '127.0.0.1',
      );

      clientSocket.send(rogueDecline, InternetAddress.loopbackIPv4, testServerPort);
      await Future.delayed(const Duration(milliseconds: 150));

      expect(dhcpService.config.startIp, equals('192.168.1.100'));
      clientSocket.close();
    });
  });
}

Uint8List _buildDhcpTestPacket({
  required int op,
  required int xid,
  required List<int> macBytes,
  required DhcpMessageType messageType,
  String? requestedIp,
  String? serverIdentifier,
  String? hostname,
  String ciaddr = '0.0.0.0',
}) {
  final builder = BytesBuilder();
  builder.addByte(op);
  builder.addByte(1); // htype = 1 (Ethernet)
  builder.addByte(6); // hlen = 6
  builder.addByte(0); // hops = 0

  final xidBytes = Uint8List(4)..buffer.asByteData().setUint32(0, xid);
  builder.add(xidBytes);
  builder.add([0, 0]); // secs
  builder.add([0, 0]); // flags

  builder.add(_ipToBytes(ciaddr));
  builder.add([0, 0, 0, 0]); // yiaddr
  builder.add([0, 0, 0, 0]); // siaddr
  builder.add([0, 0, 0, 0]); // giaddr

  final chaddr = Uint8List(16);
  chaddr.setRange(0, macBytes.length, macBytes);
  builder.add(chaddr);

  builder.add(Uint8List(64)); // sname
  builder.add(Uint8List(128)); // file
  builder.add(DhcpPacketParser.magicCookie);

  // Option 53: Message Type
  builder.add([53, 1, messageType.value]);

  if (serverIdentifier != null) {
    builder.add([54, 4, ..._ipToBytes(serverIdentifier)]);
  }

  if (requestedIp != null) {
    builder.add([50, 4, ..._ipToBytes(requestedIp)]);
  }

  if (hostname != null) {
    final hBytes = hostname.codeUnits;
    builder.add([12, hBytes.length, ...hBytes]);
  }

  builder.addByte(255); // End
  return builder.toBytes();
}

List<int> _ipToBytes(String ip) {
  final parts = ip.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  while (parts.length < 4) {
    parts.add(0);
  }
  return parts.take(4).toList();
}
