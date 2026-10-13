// analyzer_router_signal_test.dart
// S1 Task 1.2 — analyzer_router 發射 SemiSignal（TDD）
// [小葵 2026-10-09] 第一個器官發射訊號：路由決策從純規則升級為帶置信度判斷。

import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/services/brain_pipeline/analyzer_config.dart';
import 'package:bridge_app/services/brain_pipeline/analyzer_router.dart';
import 'package:bridge_app/services/brain_pipeline/cost_tracker.dart';
import 'package:bridge_app/services/semi/semi_signal.dart';

void main() {
  group('AnalyzerRouter × SemiSignal（S 線第一個器官）', () {
    test('cache hit → confidence 0.99（RuleConfidence.cacheHit）', () {
      final router = AnalyzerRouter(config: const AnalyzerConfig());
      final route = router.decide(
        layerIndex: 2,
        llmAvailable: true,
        cacheHit: true,
      );
      expect(route.confidence, RuleConfidence.cacheHit);
      expect(route.decision, RouteDecision.cached);
    });

    test('globalAiEnabled=false → fullRule 0.95（規則完整鏈命中）', () {
      final router = AnalyzerRouter(
        config: const AnalyzerConfig(globalAiEnabled: false),
      );
      final route = router.decide(
        layerIndex: 2,
        llmAvailable: true,
        cacheHit: false,
      );
      expect(route.confidence, RuleConfidence.fullRule);
    });

    test('LLM unavailable → fullRule 0.95（規則完整鏈命中）', () {
      final router = AnalyzerRouter(config: const AnalyzerConfig());
      final route = router.decide(
        layerIndex: 2,
        llmAvailable: false,
        cacheHit: false,
      );
      expect(route.confidence, RuleConfidence.fullRule);
    });

    test('layer override ai → overridden 0.8', () {
      final router = AnalyzerRouter(
        config: const AnalyzerConfig(
          globalAiEnabled: true,
          layerOverrides: {2: AnalyzerKind.ai},
        ),
      );
      final route = router.decide(
        layerIndex: 2,
        llmAvailable: true,
        cacheHit: false,
      );
      expect(route.decision, RouteDecision.ai);
      expect(route.confidence, RuleConfidence.overridden);
    });

    test('auto → mixed → ambiguous 0.6（說不上來——Semi 的不安）', () {
      final router = AnalyzerRouter(
        config: const AnalyzerConfig(
          globalAiEnabled: true,
          layerOverrides: {2: AnalyzerKind.auto},
        ),
      );
      final route = router.decide(
        layerIndex: 2,
        llmAvailable: true,
        cacheHit: false,
      );
      expect(route.decision, RouteDecision.mixed);
      expect(route.confidence, RuleConfidence.ambiguous);
      expect(route.isUneasy, isTrue);
    });

    test('cost limit exceeded → fallback 0.3（不安——反思原料）', () {
      final costTracker = CostTracker(dailyTokenLimit: 10);
      costTracker.recordCall(
        layerName: 'test',
        tokens: 100,
        latencyMs: 500,
        succeeded: true,
      );
      final router = AnalyzerRouter(
        config: const AnalyzerConfig(globalAiEnabled: true),
        costTracker: costTracker,
      );
      final route = router.decide(
        layerIndex: 2,
        llmAvailable: true,
        cacheHit: false,
      );
      expect(route.decision, RouteDecision.rule);
      expect(route.confidence, RuleConfidence.fallback);
      expect(route.isUneasy, isTrue);
    });

    test('toSemiSignal() — 器官=intuition、kind=route、payload 帶決策', () {
      final router = AnalyzerRouter(config: const AnalyzerConfig());
      final route = router.decide(
        layerIndex: 2,
        llmAvailable: true,
        cacheHit: false,
      );
      final sig = route.toSemiSignal();
      expect(sig.organ, SemiOrgan.intuition);
      expect(sig.kind, 'route');
      expect(sig.confidence, route.confidence);
      expect(sig.payload['layerIndex'], 2);
      expect(sig.payload['decision'], isA<String>());
      expect(sig.payload['reason'], isA<String>());
    });

    test('向下相容——既有欄位（decision/reason/layerIndex）不變', () {
      final router = AnalyzerRouter(
        config: const AnalyzerConfig(globalAiEnabled: false),
      );
      final route = router.decide(
        layerIndex: 1,
        llmAvailable: true,
        cacheHit: false,
      );
      expect(route.decision, RouteDecision.rule);
      expect(route.reason, isNotEmpty);
      expect(route.layerIndex, 1);
    });
  });
}
