// M3 信念證據門檻——關鍵詞抽取與重疊判定單元測試（2026-10-14）
// （checkL4 走真 DB，整合測試另計；此處測純邏輯核心）
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/belief_gate.dart';

void main() {
  group('BeliefGate._keywords', () {
    test('中文抽取 2-gram＋短詞保留', () {
      final k = BeliefGate.debugKeywords('Blue 資料區路徑');
      expect(k, contains('blue'));
      expect(k.any((x) => x.contains('資料')), isTrue);
    });

    test('英數 token 抽取', () {
      final k = BeliefGate.debugKeywords('vault file_path 相對路徑');
      expect(k, containsAll(['vault', 'file', 'path']));
    });

    test('空白與雜訊清理', () {
      expect(BeliefGate.debugKeywords('  '), isEmpty);
    });
  });

  group('BeliefGate._keywordsOverlap', () {
    test('同主題（Jaccard ≥0.3）判定重疊', () {
      final a = BeliefGate.debugKeywords('vault 相對路徑 folder_root');
      final b = BeliefGate.debugKeywords('vault 相對路徑 file_path');
      expect(BeliefGate.debugOverlap(a, b), isTrue);
    });

    test('不同主題不重疊', () {
      final a = BeliefGate.debugKeywords('今天天氣很好');
      final b = BeliefGate.debugKeywords('build 指令失敗');
      expect(BeliefGate.debugOverlap(a, b), isFalse);
    });

    test('空集合安全', () {
      expect(
          BeliefGate.debugOverlap(
              BeliefGate.debugKeywords(''), BeliefGate.debugKeywords('abc')),
          isFalse);
    });
  });

  group('BeliefGateVerdict', () {
    test('manual override 直通', () {
      const v = BeliefGateVerdict(
          allowed: true, reason: 'manual_override', evidenceCount: -1);
      expect(v.allowed, isTrue);
      expect(v.reason, 'manual_override');
    });

    test('拒絕訊息可讀', () {
      const v = BeliefGateVerdict(
          allowed: false, reason: 'insufficient_evidence', evidenceCount: 1);
      expect(BeliefGateRejectedError(v).toString(),
          contains('evidence=1/3'));
    });
  });
}
