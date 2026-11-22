// relay_host_connector_e2e_test.dart
// 第 3 層中繼第二哩 e2e（SPEC §6.3）：
// Mac 連接器註冊 → 手機模擬端配對 → 位元組穿隧到本機 gateway
//
// 拓撲：
//   fakeGateway(localhost) ← RelayHostConnector ← relay ← fakePhone

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/relay/relay_server_core.dart';
import 'package:bridge_app/services/relay/relay_host_connector.dart';

void main() {
  test('完整鏈路：手機位元組穿中繼到本機 gateway（雙向）', () async {
    // ① 假 gateway（echo server）
    final gateway = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final gatewayPort = gateway.port;
    gateway.listen((s) => s.listen((d) => s.add(d))); // echo

    // ② 中繼
    final relayPort = await _freePort();
    final relay = await RelayServerCore.start(port: relayPort);

    // ③ Mac 連接器（往外連註冊）
    final connector = RelayHostConnector();
    await connector.start(RelayHostConnectorConfig(
      relayHost: '127.0.0.1',
      relayPort: relayPort,
      hostId: 'mac-mini-1',
      secret: 'relay-secret-1',
      gatewayPort: gatewayPort,
    ));
    await Future.delayed(const Duration(milliseconds: 300));

    // ④ 手機模擬端（往外連配對）
    final phone = await Socket.connect('127.0.0.1', relayPort);
    phone.write('${jsonEncode({
      'role': 'client',
      'hostId': 'mac-mini-1',
      'secret': 'relay-secret-1',
    })}\n');
    await phone.flush();
    await Future.delayed(const Duration(milliseconds: 300));

    // ⑤ 穿隧測試：手機發話 → 中繼 → connector → gateway echo → 回手機
    final phoneGot = BytesBuilder();
    final got = Completer<void>();
    phone.listen((d) {
      phoneGot.add(d);
      if (!got.isCompleted && utf8.decode(phoneGot.toBytes()).contains('ECHO')) {
        got.complete();
      }
    });
    phone.write('PING');
    await phone.flush();
    await Future.delayed(const Duration(milliseconds: 200));
    phone.write('-ECHO');
    await phone.flush();

    await got.future.timeout(const Duration(seconds: 5));
    expect(utf8.decode(phoneGot.toBytes()).contains('PING-ECHO'), true,
        reason: 'echo 往返證明雙向穿隧成立');

    // ⑥ 收場
    phone.destroy();
    await connector.stop();
    await relay.close();
    await gateway.close();
  });
}

Future<int> _freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}
