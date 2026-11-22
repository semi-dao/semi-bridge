// [S1 收尾] MobileBridgeClient token 重連＋拍板發送——client 層測試
// 對真 gateway 打（loopback）——鎖 hello 兩路、token 落地、失效紅字引導
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';

import 'package:bridge_app/services/desktop_bridge_local_gateway.dart';
import 'package:bridge_app/services/desktop_bridge_pairing_contract.dart';
import 'package:bridge_app/services/desktop_companion_shell_config.dart';
import 'package:bridge_app/services/desktop_shell_environment_report.dart';
import 'package:bridge_app/services/mobile/mobile_device_token_store.dart';
import 'package:bridge_app/services/mobile_bridge_client.dart';
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
    pairingCode: 'BRIDGE-424242',
  );
}

Future<DesktopBridgeLocalGatewayHandle> _startGateway(
  MemoryTokenStore tokenStore,
) async {
  final gateway = DesktopBridgeLocalGateway(
    tokenService: DeviceTokenService(store: tokenStore),
  );
  return gateway.start(
    pairingContract: _contract(),
    runtimePayloadProvider: () => const {'runtime': {'ok': 1}},
    config: const DesktopBridgeLocalGatewayConfig(host: '127.0.0.1', port: 0),
  );
}

void main() {
  // [2026-11-11 一機一證] deviceId 走 SharedPreferences——測試掛 mock platform channel
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late MemoryTokenStore tokenStore;

  setUp(() {
    tokenStore = MemoryTokenStore();
    MobileBridgeClient.instance.disconnect();
  });

  test('client：配對碼路 connect → ready + deviceToken 落地', () async {
    final handle = await _startGateway(tokenStore);
    addTearDown(handle.close);

    final client = MobileBridgeClient.instance;
    final ok = await client.connect(
      host: '127.0.0.1',
      port: handle.port,
      pairingCode: 'BRIDGE-424242',
    );
    expect(ok, isTrue);

    // 等 hello 回應處理完（client 是 async message loop）
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(client.isConnected, isTrue);
    expect(client.deviceToken, isA<String>(),
        reason: '配對成功後 client 必須持有主機簽發的 token');
    client.disconnect();
  });

  test('client：token 重連路 reconnectWithToken → ready（不帶配對碼）', () async {
    final handle = await _startGateway(tokenStore);
    addTearDown(handle.close);

    // 先用主機端服務直接簽一個 token（模擬先前配對過）
    final token = await DeviceTokenService(store: tokenStore)
        .issueForPairing('BRIDGE-424242', 'BRIDGE-424242');

    final client = MobileBridgeClient.instance;
    final ok = await client.reconnectWithToken(
      host: '127.0.0.1',
      port: handle.port,
      deviceToken: token!,
    );
    expect(ok, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(client.isConnected, isTrue, reason: '有效 token → 重連 ready');
    client.disconnect();
  });

  test('client：被撤銷 token → 紅字引導重新配對（token 清空）', () async {
    final svc = DeviceTokenService(store: tokenStore);
    final handle = await _startGateway(tokenStore);
    addTearDown(handle.close);

    final token = (await svc.issueForPairing('BRIDGE-424242', 'BRIDGE-424242'))!;
    await svc.revoke(token);

    final client = MobileBridgeClient.instance;
    await client.reconnectWithToken(
      host: '127.0.0.1',
      port: handle.port,
      deviceToken: token,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(client.isConnected, isFalse, reason: '撤銷 token 必須被拒');
    expect(client.lastError, contains('重新掃描 QR'),
        reason: '錯誤訊息要引導重配對（寧紅字）');
    expect(client.deviceToken, isNull, reason: '失效 token 要清掉');
  });

  test('client：sendConfirmationRespond 離線時回 false（不假成功）', () async {
    final client = MobileBridgeClient.instance;
    client.disconnect();
    final sent = await client.sendConfirmationRespond(
      taskId: 'task-x',
      approve: true,
    );
    expect(sent, isFalse, reason: '離線拍板必須明確失敗，不排隊不假成功');
  });
}
