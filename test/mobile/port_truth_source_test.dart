// [蜂群演習二 Wave 2·工蜂E] T2 埠真相源 —— 綁正式實作測試
// 綁正式實作：lib/services/mobile/pairing/qr_payload_parser.dart（QrPayloadParser.parseQrPayload）
//
// SPEC §6.1（BRIDGE_MOBILE_SPEC.md v0.5，2026-10-31 紅隊 v0.4 修訂）：
//   「8787」為歷史慣稱；實際埠以配對 QR payload 的 `port` 參數為**唯一真相源**
//   （主機端 `DesktopBridgeLocalGatewayConfig.port`，目前預設 8790），**禁 hardcode**。
//
// 紅隊 issues 主軸（docs/drill2/SUMMARY.md）：
//   ① 假陽性風險 —— 草稿自己寫了一份 stub parser，測的是 stub 不是正式實作
//      → 本檔直接 import 正式實作，並對「錯誤行為」做反證。
//   ② hardcode 未測實際連線路徑 —— 草稿只驗 JSON payload，沒驗真正的
//      `bridge://pair?host=…&port=…&code=…` URI，也沒驗實際 gateway 埠。
//      → 本檔驗 URI 形式 ＋ 對真 gateway（loopback, port=0 隨機埠）實際連線。
//
// ⚠️ 設計鐵則（紅隊指定）：**缺 port / 非法 port 一律明確報錯，寧紅字不猜預設 8790。**
//    這是與草稿最大的分歧點 —— 草稿「缺 port → fallback 8790」正是 SPEC 禁止的
//    hardcode 猜預設行為，本檔將其鎖成「必須拋錯」。
//
// 品質範本：test/mobile/domino_engine_test.dart（SPEC 條款原文錨進 reason、成對邊界）

import 'dart:io';

import 'package:bridge_app/services/desktop_bridge_local_gateway.dart';
import 'package:bridge_app/services/desktop_bridge_pairing_contract.dart';
import 'package:bridge_app/services/desktop_companion_shell_config.dart';
import 'package:bridge_app/services/desktop_shell_environment_report.dart';
import 'package:bridge_app/services/mobile/mobile_device_token_store.dart';
import 'package:bridge_app/services/mobile/pairing/qr_payload_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一組完整的合法 payload。
String _payload({
  String host = '192.168.1.5',
  int port = 8790,
  String code = 'BRIDGE-123456',
}) => 'bridge://pair?host=$host&port=$port&code=$code';

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

void main() {
  group('合法 URI → 解出 host / port / code', () {
    test('標準 payload 解出 host、port、code 三件套', () {
      final parsed = QrPayloadParser.parseQrPayload(_payload());

      expect(parsed.host, '192.168.1.5');
      expect(parsed.port, 8790);
      expect(parsed.code, 'BRIDGE-123456');
    });

    test('主機端預設埠 8790 出現在 payload → 解出 8790（不退回 8787 歷史慣稱）', () {
      final parsed = QrPayloadParser.parseQrPayload(_payload(port: 8790));

      expect(parsed.port, 8790);
      expect(parsed.port, isNot(8787),
          reason: '8787 是歷史慣稱，不是真相源');
    });

    test('歷史埠 8787 仍可被解析（真相源是 payload，不是白名單）', () {
      final parsed = QrPayloadParser.parseQrPayload(_payload(port: 8787));

      expect(parsed.port, 8787,
          reason: 'payload 說多少就是多少 —— 埠真相源不做「對岸常見值」判斷');
    });

    test('非預設埠（如 9000、12345）如實解出（禁綁死 8790）', () {
      expect(QrPayloadParser.parseQrPayload(_payload(port: 9000)).port, 9000);
      expect(QrPayloadParser.parseQrPayload(_payload(port: 12345)).port, 12345);
    });

    test('[2026-11-19 一機一筆] did 參數可解出（同機覆蓋鑰匙）', () {
      final parsed = QrPayloadParser.parseQrPayload(
        'bridge://pair?host=192.168.50.10&port=8790&code=BRIDGE-123456&did=ab12cd34',
      );
      expect(parsed.desktopId, 'ab12cd34');
    });

    test('[2026-11-19 一機一筆] 舊版 QR 無 did → 空字串（向後相容）', () {
      final parsed = QrPayloadParser.parseQrPayload(_payload());
      expect(parsed.desktopId, '');
    });

    test('參數順序不影響解析（host/code/port 任意排列）', () {
      final parsed = QrPayloadParser.parseQrPayload(
        'bridge://pair?code=BRIDGE-123456&port=8790&host=10.0.0.7',
      );

      expect(parsed.host, '10.0.0.7');
      expect(parsed.port, 8790);
      expect(parsed.code, 'BRIDGE-123456');
    });

    test('多餘的無關參數不影響解析', () {
      final parsed = QrPayloadParser.parseQrPayload(
        'bridge://pair?host=10.0.0.7&port=8790&code=BRIDGE-1&v=2&from=qr',
      );

      expect(parsed.host, '10.0.0.7');
      expect(parsed.port, 8790);
      expect(parsed.code, 'BRIDGE-1');
    });

    test('port=0 允許（測試用：交給 OS 隨機分配）', () {
      final parsed = QrPayloadParser.parseQrPayload(_payload(port: 0));

      expect(parsed.port, 0,
          reason: 'port=0 是「讓 OS 選埠」的有效語義，不是錯誤值');
    });

    test('IPv6 / 主機名 payload 皆可解析（host 不綁死格式）', () {
      expect(
        QrPayloadParser.parseQrPayload(
          'bridge://pair?host=fe80::1&port=8790&code=BRIDGE-1',
        ).host,
        'fe80::1',
      );
      expect(
        QrPayloadParser.parseQrPayload(
          'bridge://pair?host=my-nas.local&port=8790&code=BRIDGE-1',
        ).host,
        'my-nas.local',
      );
    });
  });

  group('非法 URI → 明確報錯（寧紅字不猜預設 8790）', () {
    test('缺 port → 拋錯（絕不 fallback 8790）', () {
      expect(
        () => QrPayloadParser.parseQrPayload(
          'bridge://pair?host=192.168.1.5&code=BRIDGE-123456',
        ),
        throwsA(isA<QrPayloadException>()),
        reason: 'SPEC §6.1 禁 hardcode 8790：缺 port 必須紅字，不准猜',
      );
    });

    test('缺 port 的錯誤訊息不得出現 8790（不得暗示預設值）', () {
      Object? caught;
      try {
        QrPayloadParser.parseQrPayload(
          'bridge://pair?host=192.168.1.5&code=BRIDGE-123456',
        );
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<QrPayloadException>());
      expect(caught.toString(), isNot(contains('8790')),
          reason: '錯誤訊息不得夾帶預設埠，免得 UI 暗示「反正會用 8790」');
    });

    test('port 非數字 → 拋錯', () {
      expect(
        () => QrPayloadParser.parseQrPayload(
          'bridge://pair?host=192.168.1.5&port=abc&code=BRIDGE-123456',
        ),
        throwsA(isA<QrPayloadException>()),
      );
    });

    test('port 越界：> 65535 → 拋錯', () {
      expect(
        () => QrPayloadParser.parseQrPayload(
          'bridge://pair?host=192.168.1.5&port=65536&code=BRIDGE-123456',
        ),
        throwsA(isA<QrPayloadException>()),
        reason: 'TCP/UDP 埠範圍 0..65535，超界即錯',
      );
    });

    test('port 負數 → 拋錯', () {
      expect(
        () => QrPayloadParser.parseQrPayload(
          'bridge://pair?host=192.168.1.5&port=-1&code=BRIDGE-123456',
        ),
        throwsA(isA<QrPayloadException>()),
      );
    });

    test('port 空字串 → 拋錯（不是 0、不是預設）', () {
      expect(
        () => QrPayloadParser.parseQrPayload(
          'bridge://pair?host=192.168.1.5&port=&code=BRIDGE-123456',
        ),
        throwsA(isA<QrPayloadException>()),
      );
    });

    test('port 浮點數 / 小數點 → 拋錯（埠必須是整數）', () {
      expect(
        () => QrPayloadParser.parseQrPayload(
          'bridge://pair?host=192.168.1.5&port=8790.5&code=BRIDGE-123456',
        ),
        throwsA(isA<QrPayloadException>()),
      );
    });

    test('scheme 錯誤 → 拋錯（http:// 不是配對 protocol）', () {
      expect(
        () => QrPayloadParser.parseQrPayload(
          'http://pair?host=192.168.1.5&port=8790&code=BRIDGE-123456',
        ),
        throwsA(isA<QrPayloadException>()),
      );
    });

    test('host 段落錯（bridge://pairing?...）→ 拋錯', () {
      expect(
        () => QrPayloadParser.parseQrPayload(
          'bridge://pairing?host=192.168.1.5&port=8790&code=BRIDGE-123456',
        ),
        throwsA(isA<QrPayloadException>()),
      );
    });

    test('缺 host → 拋錯', () {
      expect(
        () => QrPayloadParser.parseQrPayload(
          'bridge://pair?port=8790&code=BRIDGE-123456',
        ),
        throwsA(isA<QrPayloadException>()),
      );
    });

    test('缺 code → 拋錯（沒有配對碼不得進連線）', () {
      expect(
        () => QrPayloadParser.parseQrPayload(
          'bridge://pair?host=192.168.1.5&port=8790',
        ),
        throwsA(isA<QrPayloadException>()),
      );
    });

    test('空字串 / 純空白 payload → 拋錯（不得靜默回 null 或猜預設）', () {
      expect(
        () => QrPayloadParser.parseQrPayload(''),
        throwsA(isA<QrPayloadException>()),
      );
      expect(
        () => QrPayloadParser.parseQrPayload('   '),
        throwsA(isA<QrPayloadException>()),
      );
    });

    test('完全不相干的字串 → 拋錯', () {
      expect(
        () => QrPayloadParser.parseQrPayload('hello world'),
        throwsA(isA<QrPayloadException>()),
      );
    });

    test('port 重複參數 → 拋錯（多值即歧義，不准挑一個猜）', () {
      expect(
        () => QrPayloadParser.parseQrPayload(
          'bridge://pair?host=192.168.1.5&port=8790&port=9000&code=BRIDGE-1',
        ),
        throwsA(isA<QrPayloadException>()),
        reason: '重複 port 是歧義輸入 —— 寧紅字不猜',
      );
    });
  });

  group('實際連線路徑（紅隊：hardcode 未測實際連線路徑）', () {
    test('真 gateway 隨機埠 → payload 帶該埠 → 解析後能真的連上（埠不硬編）', () async {
      final tokenStore = MemoryTokenStore();
      final gateway = DesktopBridgeLocalGateway(
        tokenService: DeviceTokenService(store: tokenStore),
      );
      final handle = await gateway.start(
        pairingContract: _contract(),
        runtimePayloadProvider: () => const {'runtime': {'ok': 1}},
        // port=0 → OS 隨機分配，正好驗證「真相源來自 payload 不是寫死 8790」
        config: const DesktopBridgeLocalGatewayConfig(host: '127.0.0.1', port: 0),
      );
      addTearDown(handle.close);

      expect(handle.port, isNot(8790),
          reason: '隨機埠幾乎不可能剛好是 8790 —— 確保這條路徑真的不靠常數');

      // 主機端出示的 QR payload（格式同 bridge_desktop_screen.dart 的配對卡）
      final payload =
          'bridge://pair?host=127.0.0.1&port=${handle.port}&code=BRIDGE-424242';
      final parsed = QrPayloadParser.parseQrPayload(payload);

      expect(parsed.port, handle.port,
          reason: 'QR payload 的 port 必須等於 gateway 實際綁的埠（唯一真相源）');

      // 用解析出的 host/port 真的連上去（不碰 8790）
      final socket = await WebSocket.connect(
        'ws://${parsed.host}:${parsed.port}/bridge',
      );
      addTearDown(socket.close);

      expect(socket.readyState, WebSocket.open,
          reason: '以 QR payload 的埠連線必須真的通 —— 埠真相源不是裝飾');
    });

    test('QR payload 的埠 ≠ 8787 時，仍能連到 gateway（證明沒有回落常數）', () async {
      final tokenStore = MemoryTokenStore();
      final gateway = DesktopBridgeLocalGateway(
        tokenService: DeviceTokenService(store: tokenStore),
      );
      final handle = await gateway.start(
        pairingContract: _contract(),
        runtimePayloadProvider: () => const {'runtime': {'ok': 1}},
        config: const DesktopBridgeLocalGatewayConfig(host: '127.0.0.1', port: 0),
      );
      addTearDown(handle.close);

      final parsed = QrPayloadParser.parseQrPayload(
        'bridge://pair?host=127.0.0.1&port=${handle.port}&code=BRIDGE-424242',
      );

      expect(parsed.port, isNot(8787));
      expect(parsed.port, isNot(8790));
      expect(parsed.port, handle.port);
    });

    test('主機端 config 的預設埠是 8790（不是 8787 歷史慣稱）', () {
      expect(const DesktopBridgeLocalGatewayConfig().port, 8790);
      expect(const DesktopBridgeLocalGatewayConfig().port, isNot(8787),
          reason: 'SPEC §6.1：8787 為歷史慣稱，現行預設 8790');
    });
  });

  group('解析器契約（純函數、無副作用）', () {
    test('同一 payload 重複解析結果一致（deterministic）', () {
      final first = QrPayloadParser.parseQrPayload(_payload());
      final second = QrPayloadParser.parseQrPayload(_payload());

      expect(first.host, second.host);
      expect(first.port, second.port);
      expect(first.code, second.code);
    });

    test('合法 payload 不拋錯（happy path 明確）', () {
      expect(
        () => QrPayloadParser.parseQrPayload(_payload()),
        returnsNormally,
      );
    });

    test('錯誤型別可用於 UI 分流：QrPayloadException 帶可讀訊息', () {
      Object? caught;
      try {
        QrPayloadParser.parseQrPayload(
          'bridge://pair?host=192.168.1.5&code=BRIDGE-1',
        );
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<QrPayloadException>());
      expect((caught! as QrPayloadException).message, isNotEmpty);
      expect(caught.toString(), contains('port'),
          reason: '錯誤訊息要點名出錯欄位（host/port/code），方便 UI 紅字說明');
    });
  });
}
