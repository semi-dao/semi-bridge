// relay_ws_e2e_test.dart
// 第 3 層中繼第三哩 e2e（SPEC §6.3）——真 WebSocket 全鏈路：
//
//   flutter WebSocket(帶 x-bridge-* headers) → 中繼(HTTP peek 配對) →
//   RelayHostConnector 隧道 → 真 gateway WebSocketChannel
//
// 這是「手機明天早上正式連線」的最終形狀驗證：手機端完全用 WebSocket.connect，
// 零協議改動。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:bridge_app/services/relay/relay_server_core.dart';
import 'package:bridge_app/services/relay/relay_host_connector.dart';

void main() {
  test('真 WebSocket 穿中繼：手機 → 中繼 → connector → gateway', () async {
    // ① 真 gateway（原始 HttpServer + WebSocket 升級，回應 echo JSON）
    final gateway = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final gatewayPort = gateway.port;
    gateway.listen((req) async {
      if (req.uri.path == '/bridge') {
        final ws = await WebSocketTransformer.upgrade(req);
        ws.listen((msg) {
          final decoded = jsonDecode(msg as String);
          ws.add(jsonEncode({
            'id': decoded['id'],
            'type': 'echo',
            'ok': true,
            'payload': {'heard': decoded['type']},
          }));
        });
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });

    // ② 中繼
    final relayPort = await _freePort();
    final relay = await RelayServerCore.start(port: relayPort);

    // ③ Mac 連接器（host 註冊）
    final connector = RelayHostConnector();
    await connector.start(RelayHostConnectorConfig(
      relayHost: '127.0.0.1',
      relayPort: relayPort,
      hostId: 'mac-mini-1',
      secret: 'relay-secret-1',
      gatewayPort: gatewayPort,
    ));
    await Future.delayed(const Duration(milliseconds: 300));

    // ④ 手機端：真 WebSocket.connect 帶 x-bridge-* headers
    final phone = await WebSocket.connect(
      'ws://127.0.0.1:$relayPort/bridge',
      headers: {
        'x-bridge-host-id': 'mac-mini-1',
        'x-bridge-secret': 'relay-secret-1',
      },
    );
    final channel = IOWebSocketChannel(phone);

    // ⑤ echo 往返
    final reply = Completer<Map<String, dynamic>>();
    channel.stream.listen((msg) {
      if (!reply.isCompleted) {
        reply.complete(jsonDecode(msg as String));
      }
    });
    channel.sink.add(jsonEncode({'id': 't1', 'type': 'hello', 'payload': {}}));
    final r = await reply.future.timeout(const Duration(seconds: 8));
    expect(r['ok'], true);
    expect(r['payload']['heard'], 'hello',
        reason: 'echo 往返=手機 WebSocket 全鏈路穿隧成立');

    // ⑥ 收場
    await channel.sink.close();
    await phone.close();
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
