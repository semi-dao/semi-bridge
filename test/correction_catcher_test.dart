// M3 修正捕手——detect() 偵測邏輯單元測試（2026-10-14）
// 測資來源：今天真實對話中的糾正語料 + 刻意的反例（寧漏勿誤）
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/correction_catcher.dart';

void main() {
  group('CorrectionCatcher.detect', () {
    test('事實糾正——真實語料命中', () {
      expect(
          CorrectionCatcher.detect('不對，應該是乙', '我的答案是甲')?.kind,
          CorrectionKind.factual);
      expect(CorrectionCatcher.detect('你記錯了，那是昨天的事', null)?.kind,
          CorrectionKind.factual);
    });

    test('偏好糾正——命中', () {
      expect(CorrectionCatcher.detect('不要這樣說，講白話', null)?.kind,
          CorrectionKind.preference);
    });

    test('指令重申——真實語料（我說過）命中', () {
      expect(CorrectionCatcher.detect('我說過存檔前要先確認', null)?.kind,
          CorrectionKind.instruction);
    });

    test('邊界糾正——命中', () {
      expect(CorrectionCatcher.detect('不准刪我的記憶', null)?.kind,
          CorrectionKind.boundary);
    });

    test('寧漏勿誤——正常對話不誤報', () {
      // 日常對話含近似詞但不該命中
      expect(CorrectionCatcher.detect('早安！今天天氣很好', null), isNull);
      expect(CorrectionCatcher.detect('謝謝你，做得很好', null), isNull);
      expect(CorrectionCatcher.detect('幫我看看這個功能', null), isNull);
      expect(CorrectionCatcher.detect('這個不錯，是做對了', null), isNull);
    });

    test('寧漏勿誤——「不對」單獨出現但非完整糾正模式時不命中', () {
      // 「不對」本身不在 pattern 裡（太容易誤報），要有後續才算
      expect(CorrectionCatcher.detect('不對', null), isNull);
      expect(CorrectionCatcher.detect('我覺得不對勁', null), isNull);
    });

    test('空訊息與超長訊息——防護', () {
      expect(CorrectionCatcher.detect('', null), isNull);
      expect(CorrectionCatcher.detect('不對，應該是' + 'x' * 2000, null), isNull);
    });

    test('命中片段回傳（標籤可追溯）', () {
      final hit = CorrectionCatcher.detect('跟你講過幾次了，不要這樣', null);
      expect(hit, isNotNull);
      expect(hit!.hit, isNotEmpty);
      expect(hit.kind, CorrectionKind.instruction);
    });
  });
}
