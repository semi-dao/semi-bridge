// relay_client_ladder_test.dart
// 第三哩：手機 client 爬樓梯——中繼模式 WebSocket 全鏈路
//
// 驗證：MobileBridgeClient.setRelay() 後 connect() 走中繼穿隧到 gateway，
// hello/pairing 流程照常完成。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/services/relay/relay_server_core.dart';
import 'package:bridge_app/services/relay/relay_host_connector.dart';
import 'package:bridge_app/services/mobile_bridge_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('MobileBridgeClient 爬樓梯：setRelay → connect 穿中繼配對成功', () async {
    // ① 真 gateway：hello → 簽發 token（模擬配對成功）
    final gateway = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final gatewayPort = gateway.port;
    gateway.listen((req) async {
      if (req.uri.path == '/bridge') {
        final ws = await WebSocketTransformer.upgrade(req);
        ws.listen((msg) {
          final decoded = jsonDecode(msg as String);
          if (decoded['type'] == 'hello') {
            ws.add(jsonEncode({
              'id': decoded['id'],
              'type': 'hello',
              'ok': true,
              'payload': {
                'deviceToken': 'test-token-123',
                'desktopName': 'Test Desktop',
              },
            }));
          }
        });
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });

    // ② 中繼＋connector
    final relayPort = await _freePort();
    final relay = await RelayServerCore.start(port: relayPort);
    final connector = RelayHostConnector();
    await connector.start(RelayHostConnectorConfig(
      relayHost: '127.0.0.1',
      relayPort: relayPort,
      hostId: 'mac-mini-1',
      secret: 'relay-secret-1',
      gatewayPort: gatewayPort,
    ));
    await Future.delayed(const Duration(milliseconds: 300));

    // ③ 手機 client：setRelay → connect
    final client = MobileBridgeClient.instance;
    await client.setRelay(
      host: '127.0.0.1',
      port: relayPort,
      hostId: 'mac-mini-1',
      secret: 'relay-secret-1',
    );
    final ok = await client.connect(
      host: '127.0.0.1', // 直連欄位（failover 用）——本次走中繼
      port: gatewayPort,
      pairingCode: 'BRIDGE-TEST01',
    );
    expect(ok, true, reason: '穿中繼配對應成功');

    // 等 helloAck → deviceToken
    for (var i = 0; i < 20; i++) {
      if (client.deviceToken != null) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    expect(client.deviceToken, 'test-token-123',
        reason: 'token 簽發證明 gateway hello 流程走通');
    expect(client.isConnected, true);

    // ④ 收場
    client.disconnect();
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
