// semi_signal_test.dart
// S1 Task 1.1 — SemiSignal 訊號協定測試（TDD）
// [小葵 2026-10-09] S 線第一刀：無置信度不成訊號。

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/semi/semi_signal.dart';

void main() {
  group('SemiSignal 訊號協定 v0', () {
    test('五鐵則之 1：無置信度不成訊號——confidence 必填且界內', () {
      final s = SemiSignal(
        organ: SemiOrgan.intuition,
        kind: 'route',
        payload: const {'to': 'local'},
        confidence: 0.95,
      );
      expect(s.confidence, 0.95);
      expect(s.organ, SemiOrgan.intuition);
      expect(s.kind, 'route');
      expect(s.payload['to'], 'local');
    });

    test('confidence 界外丟出（>1.0 與 <0.0 都違法）', () {
      expect(
        () => SemiSignal(
          organ: SemiOrgan.memory,
          kind: 'recall',
          payload: const {},
          confidence: 1.5,
        ),
        throwsA(isA<Error>()),
      );
      expect(
        () => SemiSignal(
          organ: SemiOrgan.memory,
          kind: 'recall',
          payload: const {},
          confidence: -0.1,
        ),
        throwsA(isA<Error>()),
      );
    });

    group('規則版 confidence 近似法（五檔寫死，禁隨任務調參）', () {
      test('RuleConfidence.cacheHit == 0.99', () {
        expect(RuleConfidence.cacheHit, 0.99);
      });
      test('RuleConfidence.fullRule == 0.95', () {
        expect(RuleConfidence.fullRule, 0.95);
      });
      test('RuleConfidence.overridden == 0.8', () {
        expect(RuleConfidence.overridden, 0.8);
      });
      test('RuleConfidence.ambiguous == 0.6', () {
        expect(RuleConfidence.ambiguous, 0.6);
      });
      test('RuleConfidence.fallback == 0.3', () {
        expect(RuleConfidence.fallback, 0.3);
      });
    });

    test('工廠：SemiSignal.rule() 用五檔近似法', () {
      final s = SemiSignal.rule(
        organ: SemiOrgan.intuition,
        kind: 'route',
        payload: const {'to': 'rule'},
        confidence: RuleConfidence.fullRule,
      );
      expect(s.confidence, 0.95);
    });

    test('低置信度判斷（<0.6）= Semi 的不安——isUneasy 為真', () {
      final uneasy = SemiSignal.rule(
        organ: SemiOrgan.cerebellum,
        kind: 'act',
        payload: const {},
        confidence: RuleConfidence.fallback,
      );
      expect(uneasy.isUneasy, isTrue);

      final calm = SemiSignal.rule(
        organ: SemiOrgan.cerebellum,
        kind: 'act',
        payload: const {},
        confidence: RuleConfidence.fullRule,
      );
      expect(calm.isUneasy, isFalse);
    });

    test('器官五成員齊備（intuition/memory/cerebellum/prefrontal/body）', () {
      expect(SemiOrgan.values.length, 5);
      expect(SemiOrgan.values.map((e) => e.name).toSet(), {
        'intuition', 'memory', 'cerebellum', 'prefrontal', 'body',
      });
    });

    test('toMap() 可序列化（判斷入記憶的前置形狀）', () {
      final s = SemiSignal.rule(
        organ: SemiOrgan.intuition,
        kind: 'route',
        payload: const {'to': 'local'},
        confidence: RuleConfidence.fullRule,
      );
      final m = s.toMap();
      expect(m['organ'], 'intuition');
      expect(m['kind'], 'route');
      expect(m['confidence'], 0.95);
      expect(m['payload'], isA<Map<String, Object?>>());
      expect(m['at'], isA<String>());
    });
  });
}
