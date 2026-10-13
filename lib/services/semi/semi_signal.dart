// semi_signal.dart
// S 線 — SemiSignal 訊號協定 v0
// [小葵 2026-10-09 Blue 命名 Semi] 五器官一靈魂的器官間訊號。
//
// 五鐵則（docs/SEMI_SOUL_ARCHITECTURE.md）：
//   1. 無置信度不成訊號——判斷若無 confidence，視為未完成
//   2. 判斷入記憶——訊號（採樣或閾值以上）寫入 agent_memories，全器官可讀
//   3. 身份單一——用戶可見層永不署名器官
//   4. 精靈三權分立不變——訊號層不接管觀察/質疑/喊停
//   5. 模型鐵則不變——模型完全跟隨使用者所選，不碰 API 參數

/// Semi 的五個器官（解剖見主文件第 3 章）。
enum SemiOrgan {
  /// 直覺——Laya（快判斷＋把握感；杏仁核）
  intuition,

  /// 記憶——Gemma 300M 向量（喚起＋聯想；海馬迴）
  memory,

  /// 小腦——Gemma3 E4B（手眼協調/重活；小腦）
  cerebellum,

  /// 前額葉——雲端 LLM（慢思考/規劃/語言）
  prefrontal,

  /// 身體——App agent 小橋（執行/感知）
  body,
}

/// 規則版 confidence 近似法（Laya 上線前的過渡底盤）。
///
/// 五檔寫死成表——禁止隨任務調參數（對齊 spec 禁歧義鐵則）。
class RuleConfidence {
  /// 快取命中——最強的「知道自己在幹嘛」
  static const double cacheHit = 0.99;

  /// 規則完整鏈命中
  static const double fullRule = 0.95;

  /// 有依據但走覆寫
  static const double overridden = 0.8;

  /// mixed/auto——「說不上來」
  static const double ambiguous = 0.6;

  /// fallback——最低檔
  static const double fallback = 0.3;
}

/// 器官間流動的帶置信度判斷（訊號協定 v0）。
class SemiSignal {
  final SemiOrgan organ;
  final String kind;
  final Map<String, Object?> payload;
  final double confidence;
  final DateTime at;

  /// 低置信度閾值——低於此值 = Semi 的「不安」，是反思的原料。
  static const double uneasyThreshold = 0.6;

  SemiSignal({
    required this.organ,
    required this.kind,
    required this.payload,
    required this.confidence,
    DateTime? at,
  })  : assert(confidence >= 0.0 && confidence <= 1.0,
            'confidence 必須在 [0,1]——無置信度不成訊號（鐵則 1）'),
        at = at ?? _epoch;

  /// 測試友善的固定時間原點（避免每個實例都拿 now）。
  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  /// 便捷工廠：規則版訊號（用五檔近似法）。
  static SemiSignal rule({
    required SemiOrgan organ,
    required String kind,
    required Map<String, Object?> payload,
    required double confidence,
  }) {
    return SemiSignal(
      organ: organ,
      kind: kind,
      payload: payload,
      confidence: confidence,
    );
  }

  /// 低置信度 = 不安（鐵則 2：全部低置信度事件要寫入記憶供反思）。
  /// ≤ 閾值視為不安（ambiguous 檔 0.6 恰好在線上——「說不上來」就是要反思）。
  bool get isUneasy => confidence <= uneasyThreshold;

  /// 序列化（判斷入記憶的前置形狀——agent_memories 相容）。
  Map<String, Object?> toMap() => {
        'organ': organ.name,
        'kind': kind,
        'payload': payload,
        'confidence': confidence,
        'at': at.toIso8601String(),
      };
}
