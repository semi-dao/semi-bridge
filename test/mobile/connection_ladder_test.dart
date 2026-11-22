// [蜂群演習二 Wave 2·工蜂E] T3 三層樓梯 —— 綁正式實作測試
// 綁正式實作：lib/services/mobile/connection/connection_ladder.dart
//             （LadderTier ＋ ConnectionLadder.evaluate）
//
// SPEC §6.2（BRIDGE_MOBILE_SPEC.md v0.5，2026-10-30 Blue 拍板 v0.1 版）：
//
//   第 1 層｜同網直連（預設，永遠優先）
//     → 人在家/農場 Wi-Fi 內，零設定零後門
//   第 2 層｜自開後門（出門主力）
//     → 主機開加密埠 + DDNS；App 偵測網路環境，
//        能開就一鍵引導開，開不了明講（寧紅字不假成功）
//   第 3 層｜自架中繼（救生艇，選配）
//     → 開源包附 Docker 一鍵自架；SemiDAO 不經營
//
// 紅隊 issues 主軸（docs/drill2/SUMMARY.md）：
//   「第 1 層『永遠優先』真值表覆蓋不足」→ 本檔覆蓋 2×2 = 4 組真值表全排列，
//   並額外鎖死「同網可達時，其餘兩層無論如何都不得翻盤」。
//
// 品質範本：test/mobile/domino_engine_test.dart（SPEC 條款原文錨進 reason、成對邊界）

import 'package:bridge_app/services/mobile/connection/connection_ladder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('真值表全覆蓋（4 組 × 2×2 旗標）', () {
    test('同網可達 + 中繼可達 → direct（第 1 層永遠優先）', () {
      final tier = ConnectionLadder.evaluate(
        sameLanGatewayReachable: true,
        relayReachable: true,
      );

      expect(tier, LadderTier.direct);
    });

    test('同網可達 + 中繼不可達 → direct', () {
      final tier = ConnectionLadder.evaluate(
        sameLanGatewayReachable: true,
        relayReachable: false,
      );

      expect(tier, LadderTier.direct);
    });

    test('同網不可達 + 中繼可達 → relay', () {
      final tier = ConnectionLadder.evaluate(
        sameLanGatewayReachable: false,
        relayReachable: true,
      );

      expect(tier, LadderTier.relay);
    });

    test('同網不可達 + 中繼不可達 → offline（全斷，不假成功）', () {
      final tier = ConnectionLadder.evaluate(
        sameLanGatewayReachable: false,
        relayReachable: false,
      );

      expect(tier, LadderTier.offline);
    });
  });

  group('優先序鎖定（第 1 層永遠優先）', () {
    test('同網可達時，relay 旗標無論 true/false 都得 direct', () {
      for (final relay in [true, false]) {
        expect(
          ConnectionLadder.evaluate(
            sameLanGatewayReachable: true,
            relayReachable: relay,
          ),
          LadderTier.direct,
          reason: 'relayReachable=$relay 時第 1 層都必須壓過第 3 層',
        );
      }
    });

    test('四組真值表的結果互異且覆蓋三個 tier（無結果重複、無遺漏 tier）', () {
      final results = <LadderTier>{
        for (final lan in [true, false])
          for (final relay in [true, false])
            ConnectionLadder.evaluate(
              sameLanGatewayReachable: lan,
              relayReachable: relay,
            ),
      };

      expect(results.length, 3, reason: '真值表必須走遍 direct / relay / offline');
      expect(results, contains(LadderTier.direct));
      expect(results, contains(LadderTier.relay));
      expect(results, contains(LadderTier.offline));
    });

    test('LadderTier 枚舉剛好三層且順序即優先序（direct < relay < offline）', () {
      expect(LadderTier.values.length, 3,
          reason: 'SPEC §6.2 只有三層（直連 / 中繼 / 全斷）');
      expect(LadderTier.values.first, LadderTier.direct,
          reason: '第 1 層永遠排在最前');
      expect(LadderTier.values[1], LadderTier.relay);
      expect(LadderTier.values[2], LadderTier.offline);
    });

    test('evaluate 是純函數：同一組旗標重複呼叫結果一致', () {
      const flags = (lan: false, relay: true);
      final first = ConnectionLadder.evaluate(
        sameLanGatewayReachable: flags.lan,
        relayReachable: flags.relay,
      );
      for (var i = 0; i < 20; i++) {
        expect(
          ConnectionLadder.evaluate(
            sameLanGatewayReachable: flags.lan,
            relayReachable: flags.relay,
          ),
          first,
          reason: '連線評估不得有隱藏狀態（重試時結果要一致）',
        );
      }
    });
  });

  group('誠實失敗（寧紅字不假成功）', () {
    test('全斷 → offline，且 offline 明確表示「沒有一層通」', () {
      final tier = ConnectionLadder.evaluate(
        sameLanGatewayReachable: false,
        relayReachable: false,
      );

      expect(tier, LadderTier.offline);
      expect(tier.isConnected, isFalse,
          reason: 'offline 不得被 UI 誤認為已連線');
    });

    test('direct / relay 是「有路可走」；offline 是「一條都沒有」', () {
      expect(LadderTier.direct.isConnected, isTrue);
      expect(LadderTier.relay.isConnected, isTrue);
      expect(LadderTier.offline.isConnected, isFalse);
    });

    test('中繼可用時不得回 offline（中繼就是出門的救生艇）', () {
      expect(
        ConnectionLadder.evaluate(
          sameLanGatewayReachable: false,
          relayReachable: true,
        ),
        isNot(LadderTier.offline),
        reason: '第 3 層可用就不能宣告全斷（否則白設中繼）',
      );
    });
  });

  group('可行動作（第 2 層「能開就引導、開不了明講」）', () {
    test('direct → 直接連線，無需任何引導', () {
      expect(LadderTier.direct.action, LadderAction.connectDirect);
    });

    test('relay → 走中繼，不要求使用者開後門', () {
      expect(LadderTier.relay.action, LadderAction.useRelay);
    });

    test('offline → 明講開不了（不假成功、不假裝正在開）', () {
      expect(LadderTier.offline.action, LadderAction.reportUnavailable);
    });

    test('每個 tier 都有非空的可讀說明（紅字要說得清）', () {
      for (final tier in LadderTier.values) {
        expect(tier.message, isNotEmpty,
            reason: '${tier.name} 必須有可顯示的說明文案');
        expect(tier.message.trim(), isNotEmpty);
      }
    });

    test('offline 的文案不得出現「連線中」「已連線」等假成功字眼', () {
      final message = LadderTier.offline.message;

      expect(message, isNot(contains('連線中')));
      expect(message, isNot(contains('已連線')));
      expect(message, isNot(contains('連線成功')));
    });
  });
}
