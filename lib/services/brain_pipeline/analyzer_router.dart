// analyzer_router.dart
// Sprint 10 — 統一決定每層走 AI 還是規則版
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 根據 AnalyzerConfig + CostTracker + LayerCache 的狀態，
// 決定每層 analyze 時實際走哪條路徑。
//
// 決策優先序：
// 1. globalAiEnabled == false → 規則版
// 2. CostTracker 超額 → 規則版
// 3. layerOverrides[layerIndex] == rule → 規則版
// 4. layerOverrides[layerIndex] == ai → AI 版（需 LLM 可用）
// 5. auto 模式 → 規則版先跑，信心不夠才叫 AI（由混合策略器自行處理）
//
// 注意：Router 不直接呼叫 analyzer，只回傳「該走哪條路」的決策。
// Pipeline 拿到決策後選擇對應的 analyzer 或 mixed 策略器。

import 'analyzer_config.dart';
import 'cost_tracker.dart';
import '../semi/semi_signal.dart';

/// 路由決策結果。
enum RouteDecision {
  /// 走規則版
  rule,

  /// 走 AI 版（含混合策略）
  ai,

  /// 走混合策略（rule 先跑 + AI 覆蓋）
  mixed,

  /// 走快取
  cached,
}

/// 每層的路由決策。
class LayerRoute {
  final int layerIndex;
  final RouteDecision decision;
  final String reason;

  /// [S 線 2026-10-09] 規則版近似置信度（五檔寫死——見 RuleConfidence）。
  /// 無置信度不成訊號（SemiSignal 鐵則 1）。
  final double confidence;

  const LayerRoute({
    required this.layerIndex,
    required this.decision,
    required this.reason,
    this.confidence = RuleConfidence.ambiguous,
  });

  /// 低置信度 = 不安（反思原料）——定義單一真相源在 SemiSignal。
  bool get isUneasy => SemiSignal.uneasyThreshold >= confidence;

  /// 發射 SemiSignal——Semi 的直覺器官（路由判斷）第一次有了標準訊號形狀。
  SemiSignal toSemiSignal() => SemiSignal(
        organ: SemiOrgan.intuition,
        kind: 'route',
        payload: {
          'layerIndex': layerIndex,
          'decision': decision.name,
          'reason': reason,
        },
        confidence: confidence,
      );

  @override
  String toString() => 'LayerRoute($layerIndex: $decision — $reason)';
}

/// 統一決定每層走 AI 還是規則版。
///
/// Pipeline 在跑每層之前呼叫 [decide]，拿到決策後選擇對應 analyzer。
class AnalyzerRouter {
  final AnalyzerConfig config;
  final CostTracker? costTracker;

  AnalyzerRouter({
    this.config = const AnalyzerConfig(),
    this.costTracker,
  });

  /// 決定某層該走哪條路。
  LayerRoute decide({
    required int layerIndex,
    required bool llmAvailable,
    required bool cacheHit,
  }) {
    // 快取命中優先
    if (cacheHit) {
      return LayerRoute(
        layerIndex: layerIndex,
        decision: RouteDecision.cached,
        reason: 'cache hit',
        confidence: RuleConfidence.cacheHit,
      );
    }

    // 全域 AI 關閉 → 規則版
    if (!config.globalAiEnabled) {
      return LayerRoute(
        layerIndex: layerIndex,
        decision: RouteDecision.rule,
        reason: 'globalAiEnabled=false',
        confidence: RuleConfidence.fullRule,
      );
    }

    // LLM 不可用 → 規則版
    if (!llmAvailable) {
      return LayerRoute(
        layerIndex: layerIndex,
        decision: RouteDecision.rule,
        reason: 'LLM unavailable',
        confidence: RuleConfidence.fullRule,
      );
    }

    // 成本超額 → 規則版
    if (costTracker != null && costTracker!.isOverLimit) {
      return LayerRoute(
        layerIndex: layerIndex,
        decision: RouteDecision.rule,
        reason: 'cost limit exceeded (${costTracker!.todayTokenCount} tokens)',
        confidence: RuleConfidence.fallback,
      );
    }

    // 每層覆寫
    final kind = config.kindForLayer(layerIndex);
    switch (kind) {
      case AnalyzerKind.rule:
        return LayerRoute(
          layerIndex: layerIndex,
          decision: RouteDecision.rule,
          reason: 'layer override: rule',
          confidence: RuleConfidence.fullRule,
        );
      case AnalyzerKind.ai:
        return LayerRoute(
          layerIndex: layerIndex,
          decision: RouteDecision.ai,
          reason: 'layer override: ai',
          confidence: RuleConfidence.overridden,
        );
      case AnalyzerKind.auto:
        // auto 模式：走混合策略（rule 先跑，AI 覆蓋）
        return LayerRoute(
          layerIndex: layerIndex,
          decision: RouteDecision.mixed,
          reason: 'auto → mixed',
          confidence: RuleConfidence.ambiguous,
        );
    }
  }

  /// 更新配置（運行時切換，例如 CostTracker 超額後關 AI）。
  AnalyzerRouter withConfig(AnalyzerConfig newConfig) {
    return AnalyzerRouter(
      config: newConfig,
      costTracker: costTracker,
    );
  }
}
