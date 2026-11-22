// [2026-11-21 對話tab速勝 刀1] conversationDelete 白名單回歸鎖
//
// 病根：mobile_bridge_client.dart _onMessage 同步回應白名單漏掛
// conversationDelete → sendConversationDelete 的 _requestVaultResponse
// completer 永不完成 → 10s timeout → 回 false → UI 誤報「刪除失敗」
// （實際桌面已刪）。
// 鎖法：fake gateway 照協議對 conversationDelete 回 ok:true，斷言
// sendConversationDelete 回 true（漏掛必 timeout→false，必紅）。
// 模式同 now_page_pagination_test.dart 的 FakeGateway（integration 式，
// 真 MobileBridgeClient 單例打進來）。連法同 mobile_bridge_client_test.dart
// （純 async test，真 socket IO 直跑）。
import 'dart:convert';
import 'dart:io';

import 'package:bridge_app/services/mobile_bridge_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeGateway {
  late final HttpServer _server;
  final requestTypes = <String>[];

  Future<int> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.transform(WebSocketTransformer()).listen(_onSocket);
    return _server.port;
  }

  Future<void> stop() async => _server.close(force: true);

  void _onSocket(WebSocket ws) {
    ws.listen((data) {
      final req = jsonDecode(data as String) as Map<String, dynamic>;
      final type = req['type'] as String? ?? '';
      final id = req['id'] as String? ?? '';
      if (type != 'hello') requestTypes.add(type);
      Map<String, dynamic> respPayload = const {};
      if (type == 'hello') {
        respPayload = {'deviceToken': 'fake-token', 'desktopName': 'fake'};
      } else if (type == 'conversationDelete') {
        respPayload = const {'deletedId': 'conv-x'};
      }
      ws.add(jsonEncode({
        'schema': 'bridge.desktop.gateway.response.v1',
        'requestId': id,
        'type': type,
        'ok': true,
        if (respPayload.isNotEmpty) 'payload': respPayload,
      }));
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('刀1：conversationDelete 在白名單——回應完成 completer，回 true 不 timeout',
      () async {
    final g = FakeGateway();
    final port = await g.start();
    addTearDown(g.stop);
    MobileBridgeClient.instance.disconnect();

    final client = MobileBridgeClient.instance;
    final connected = await client.connect(
        host: '127.0.0.1', port: port, pairingCode: 'BRIDGE-000001');
    expect(connected, isTrue);

    final ok = await client.sendConversationDelete('conv-x');
    expect(ok, isTrue,
        reason: '白名單漏掛 conversationDelete 會 timeout 回 false（誤報刪除失敗）');
    expect(g.requestTypes.contains('conversationDelete'), isTrue);
    client.disconnect();
  }, timeout: const Timeout(Duration(seconds: 30)));
}
