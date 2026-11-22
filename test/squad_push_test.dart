// 小隊動態推播（squadChanged）協定層測試
// [2026-11-17] gateway pushSquadChanged + protocol message type。
//
// 範圍：
// 1. protocol 序列化來回（Push.toJson / Request.fromJson / handleRequest push-only 拒絕）
// 2. 真 gateway loopback WS：hello 配對後 pushSquadChanged → 手機端收到正確 payload
//    （走真實 socket，不碰 shared_preferences——gateway 端不需要 path_provider
//     模擬，既有 desktop_bridge_local_gateway_test.dart 同款模式已驗證可跑）
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bridge_app/services/desktop_bridge_gateway_protocol.dart';
import 'package:bridge_app/services/desktop_bridge_local_gateway.dart';
import 'package:bridge_app/services/desktop_bridge_pairing_contract.dart';
import 'package:bridge_app/services/desktop_companion_shell_config.dart';
import 'package:bridge_app/services/desktop_shell_environment_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('squadChanged 序列化來回', () {
    test('Push.toJson 帶 type=squadChanged 與 payload 欄位', () {
      const push = DesktopBridgeGatewayPush(
        type: DesktopBridgeGatewayMessageType.squadChanged,
        payload: {
          'parentId': 'conv-parent',
          'event': 'spawned',
          'squadId': 'conv-squad-1',
          'at': '2026-11-17T00:00:00.000Z',
        },
      );
      final json = push.toJson();
      expect(json['schema'], 'bridge.desktop.gateway.push.v1');
      expect(json['type'], 'squadChanged');
      final payload = json['payload'] as Map;
      expect(payload['parentId'], 'conv-parent');
      expect(payload['event'], 'spawned');
      expect(payload['squadId'], 'conv-squad-1');
      expect(payload['at'], '2026-11-17T00:00:00.000Z');

      // 來回：還原 type 必須對回枚舉 squadChanged
      final restored = DesktopBridgeGatewayMessageType.values.firstWhere(
        (m) => m.name == json['type'],
      );
      expect(restored, DesktopBridgeGatewayMessageType.squadChanged);
    });

    test('Request.fromJson 認得 squadChanged（供 push-only 拒絕路徑）', () {
      final req = DesktopBridgeGatewayRequest.fromJson({
        'schema': 'bridge.desktop.gateway.request.v1',
        'id': 'x-1',
        'type': 'squadChanged',
        'payload': const {},
      });
      expect(req.type, DesktopBridgeGatewayMessageType.squadChanged);
      // toJson 來回
      final roundTrip =
          DesktopBridgeGatewayRequest.fromJson(req.toJson().cast<String, dynamic>());
      expect(roundTrip.type, DesktopBridgeGatewayMessageType.squadChanged);
      expect(roundTrip.id, 'x-1');
    });

    test('squadChanged 從手機送來必須被 protocol 以 push-only 拒絕', () {
      const protocol = DesktopBridgeGatewayProtocol();
      final response = protocol.handleRequest(
        request: const DesktopBridgeGatewayRequest(
          id: 'r-1',
          type: DesktopBridgeGatewayMessageType.squadChanged,
        ),
        pairingContract: _contract(),
        runtimePayload: const {},
      );
      expect(response.ok, isFalse);
      expect(response.error, contains('Push-only'));
    });
  });

  group('pushSquadChanged over loopback websocket', () {
    test('hello 配對後 pushSquadChanged → socket 收到正確 push payload', () async {
      final contract = _contract();
      final gateway = DesktopBridgeLocalGateway();
      final handle = await gateway.start(
        pairingContract: contract,
        runtimePayloadProvider: _runtimePayload,
        config: const DesktopBridgeLocalGatewayConfig(port: 0),
      );
      addTearDown(handle.close);

      final socket = await WebSocket.connect(handle.endpoint.toString());
      addTearDown(socket.close);
      final messages = StreamIterator(socket);
      addTearDown(messages.cancel);

      // 先過配對閘門（hello）
      socket.add(
        jsonEncode(
          DesktopBridgeGatewayRequest(
            id: 'hello-1',
            type: DesktopBridgeGatewayMessageType.hello,
            payload: {'pairingCode': contract.pairingCode},
          ).toJson(),
        ),
      );
      expect(await messages.moveNext(), isTrue);
      final hello = jsonDecode(messages.current as String) as Map;
      expect(hello['ok'], isTrue);

      // 桌面端主動推播小隊動態
      handle.pushSquadChanged(
        parentId: 'parent-42',
        event: 'reported',
        squadId: 'squad-7',
      );

      expect(await messages.moveNext(), isTrue);
      final push = jsonDecode(messages.current as String) as Map;
      expect(push['schema'], 'bridge.desktop.gateway.push.v1');
      expect(push['type'], 'squadChanged');
      final payload = push['payload'] as Map;
      expect(payload['parentId'], 'parent-42');
      expect(payload['event'], 'reported');
      expect(payload['squadId'], 'squad-7');
      // at 欄位為推播當下時間戳（ISO8601 字串）
      expect(DateTime.tryParse(payload['at'] as String), isNotNull);
    });
  });
}

DesktopBridgePairingContract _contract() {
  return const DesktopBridgePairingContractService().buildContract(
    config: DesktopCompanionShellConfig(),
    environmentReport: DesktopShellEnvironmentReportService().fromSignals(
      flutterAvailable: true,
      fullXcodeAvailable: true,
      swiftParsePassed: true,
      macosBuildPassed: true,
    ),
    nativeShellConnected: true,
    localGatewayReady: true,
    generatedAt: DateTime.utc(2026, 6, 3, 10),
  );
}

Map<String, dynamic> _runtimePayload() => const {
      'runtime': {'activeCompanionName': '星槌'},
    };
