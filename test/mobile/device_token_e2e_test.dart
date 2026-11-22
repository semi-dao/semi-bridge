// [S1 收尾] token 端到端迴路測試——S1 驗收鐵則的核心場景
// 場景：首次配對（pairingCode → 拿 token）→ 斷線 → 重連（token 握手）→ 失效 token 被拒
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bridge_app/services/desktop_bridge_gateway_protocol.dart';
import 'package:bridge_app/services/desktop_bridge_local_gateway.dart';
import 'package:bridge_app/services/desktop_bridge_pairing_contract.dart';
import 'package:bridge_app/services/desktop_companion_shell_config.dart';
import 'package:bridge_app/services/desktop_shell_environment_report.dart';
import 'package:bridge_app/services/mobile/mobile_device_token_store.dart';
import 'package:flutter_test/flutter_test.dart';

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
    pairingCode: 'BRIDGE-777888',
  );
}

void main() {
  late MemoryTokenStore tokenStore;

  setUp(() {
    tokenStore = MemoryTokenStore();
  });

  test('E2E：配對拿 token → 斷線 → 憑 token 重連 → runtimeSnapshot 可用', () async {
    final gateway = DesktopBridgeLocalGateway(tokenService: DeviceTokenService(store: tokenStore));
    final handle = await gateway.start(
      pairingContract: _contract(),
      runtimePayloadProvider: () => const {'runtime': {'ok': 1}},
      config: const DesktopBridgeLocalGatewayConfig(host: '127.0.0.1', port: 0),
    );
    addTearDown(handle.close);

    // ── 第一段：首次配對 ──
    final phone1 = await WebSocket.connect('ws://127.0.0.1:${handle.port}/bridge');
    phone1.add(jsonEncode(DesktopBridgeGatewayRequest(
      id: 'pair-1',
      type: DesktopBridgeGatewayMessageType.hello,
      payload: {'pairingCode': 'BRIDGE-777888'},
    ).toJson()));
    final helloResp = await phone1
        .map((r) => jsonDecode(r as String) as Map<String, dynamic>)
        .first;
    expect(helloResp['ok'], isTrue, reason: '配對碼正確 → hello ok');
    final token = (helloResp['payload'] as Map)['deviceToken'];
    expect(token, isA<String>(), reason: '配對成功必須附 deviceToken');
    await phone1.close(); // 斷線（模擬殺 App）

    // ── 第二段：憑 token 重連 ──
    final phone2 = await WebSocket.connect('ws://127.0.0.1:${handle.port}/bridge');
    final msgs2 = StreamIterator(phone2.map((r) => jsonDecode(r as String) as Map<String, dynamic>));
    addTearDown(msgs2.cancel);
    phone2.add(jsonEncode(DesktopBridgeGatewayRequest(
      id: 'reconnect-1',
      type: DesktopBridgeGatewayMessageType.hello,
      payload: {'deviceToken': token},
    ).toJson()));
    expect(await msgs2.moveNext(), isTrue);
    final reconnectResp = msgs2.current;
    expect(reconnectResp['ok'], isTrue, reason: '有效 token → 重連成功');
    expect((reconnectResp['payload'] as Map)['reconnected'], isTrue);

    // 重連後可正常要求 runtimeSnapshot（過閘後功能可用）
    phone2.add(jsonEncode(const DesktopBridgeGatewayRequest(
      id: 'snap-1',
      type: DesktopBridgeGatewayMessageType.runtimeSnapshot,
    ).toJson()));
    Map<String, dynamic>? snapResp;
    while (await msgs2.moveNext()) {
      if (msgs2.current['type'] == 'runtimeSnapshot') {
        snapResp = msgs2.current;
        break;
      }
    }
    expect(snapResp, isNotNull, reason: '重連後 runtimeSnapshot 應可用');
    expect(snapResp!['ok'], isTrue);
    await phone2.close();
  });

  test('E2E：被撤銷的 token 重連 → ok:false + 明確錯誤訊息（寧紅字）', () async {
    final svc = DeviceTokenService(store: tokenStore);
    final gateway = DesktopBridgeLocalGateway(tokenService: svc);
    final handle = await gateway.start(
      pairingContract: _contract(),
      runtimePayloadProvider: () => const {'runtime': {'ok': 1}},
      config: const DesktopBridgeLocalGatewayConfig(host: '127.0.0.1', port: 0),
    );
    addTearDown(handle.close);

    // 配對拿 token 後立刻撤銷（模擬手機被偷救濟）
    final phone = await WebSocket.connect('ws://127.0.0.1:${handle.port}/bridge');
    phone.add(jsonEncode(DesktopBridgeGatewayRequest(
      id: 'pair-2',
      type: DesktopBridgeGatewayMessageType.hello,
      payload: {'pairingCode': 'BRIDGE-777888'},
    ).toJson()));
    final helloResp = await phone
        .map((r) => jsonDecode(r as String) as Map<String, dynamic>)
        .first;
    final token = (helloResp['payload'] as Map)['deviceToken'] as String;
    await phone.close();
    await svc.revoke(token);

    // 撤銷後重連 → 拒絕
    final thief = await WebSocket.connect('ws://127.0.0.1:${handle.port}/bridge');
    thief.add(jsonEncode(DesktopBridgeGatewayRequest(
      id: 'reconnect-2',
      type: DesktopBridgeGatewayMessageType.hello,
      payload: {'deviceToken': token},
    ).toJson()));
    final rejectResp = await thief
        .map((r) => jsonDecode(r as String) as Map<String, dynamic>)
        .first;
    expect(rejectResp['ok'], isFalse, reason: '撤銷的 token 必須被拒');
    expect(rejectResp['error'], contains('re-pair'),
        reason: '錯誤訊息要引導重新配對');
    await thief.close();
  });

  test('E2E：錯誤配對碼 → 不發 token（既有安全域不回退）', () async {
    final gateway = DesktopBridgeLocalGateway(tokenService: DeviceTokenService(store: tokenStore));
    final handle = await gateway.start(
      pairingContract: _contract(),
      runtimePayloadProvider: () => const {'runtime': {'ok': 1}},
      config: const DesktopBridgeLocalGatewayConfig(host: '127.0.0.1', port: 0),
    );
    addTearDown(handle.close);

    final phone = await WebSocket.connect('ws://127.0.0.1:${handle.port}/bridge');
    phone.add(jsonEncode(DesktopBridgeGatewayRequest(
      id: 'pair-3',
      type: DesktopBridgeGatewayMessageType.hello,
      payload: {'pairingCode': 'BRIDGE-000000'},
    ).toJson()));
    final resp = await phone
        .map((r) => jsonDecode(r as String) as Map<String, dynamic>)
        .first;
    expect(resp['ok'], isFalse);
    expect((resp['payload'] ?? const {})['deviceToken'], isNull,
        reason: '錯碼絕不發 token');
    await phone.close();
  });
}
