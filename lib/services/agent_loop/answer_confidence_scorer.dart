// [T12-① / D2 拍板 2026-10-17] answer_confidence 唯一寫者——執行證據評分器。
//
// 病史（Fable V3 總體檢 斷鏈①＋新單點①）：event_ledger.answer_confidence
// 欄位自 T2 起「有欄位、零寫者」——熔斷器 onlineCalibration() 永遠回空、
// evaluate() 永不熔斷、羅盤開口閘吃的信心是寫死 0.85。校準體系整整齊齊
// 地靜默了兩天。
//
// D2 拍板（Blue 授權按優先序開工）：來源＝執行證據（deterministic），
// 不用 LLM 自評——
//   ① 對話直通道剛從 TASK_DONE 污染裡畢業（刀A 10-17），加信心標記
//     等於重新教壞它；
//   ② E4B 自信地錯的病例就是盲測 1/15——自評信心不可靠；
//   ③ 零延遲、零 token、可解釋、可測試。
// 語意：這是「本輪回答背後有多少可驗證的證據」的信心，不是「模型對
// 自己嘴上多自信」——寧紅字不假成功。
//
// 評分表（v1，全部來自 AgentLoopResult 的既有欄位）：
//   0.95  全裝多輪、工具全成功、非截斷非取消           —— 最高階證據
//   0.85  直通道（chat bypass）完整回答                 —— 單次 LLM、無工具
//         證據＝人格與對話能力，不含事實查證
//   0.60  工具部分失敗（有失敗的工具輪）               —— 部分證據
//   0.40  hitTurnLimit（工具上限強制收尾）              —— 證據被截斷
//   0.30  取消/取消性回覆（使用者停手）                 —— 非完成態
//   null  無法評分（compass 輪、空回覆、攔截取消）      —— 無訊號≠零分
//         （onlineCalibration 的 IS NULL 語意：無訊號不進統計）
//
// 寫入策略：收尾補寫（appendTurn 在輪開頭落盤、答案未生成；UPDATE 不破
// hash 鏈——hash 不含 answer_confidence，event_ledger.dart:321-328）。

import 'agent_loop.dart'; // AgentLoopResult 本居（Dart 循環 import 合法：
// agent_loop.dart 也 import 本檔做收尾評分——兩檔互指不構成 cycle error）

/// 執行證據評分器——answer_confidence 的唯一寫者。
/// 純函數（無狀態、無 IO），測試友善。
class AnswerConfidenceScorer {
  AnswerConfidenceScorer._();

  /// 誠實邊界訊號（與 agent_loop _kHonestySignals 同源口徑——
  /// 「我不確定/我看不見」＝誠實自白，出現在回覆裡時信心降一階。
  /// 這裡只列「自白級」關鍵詞，不含語氣詞。
  static const List<String> kHonestySignals = [
    '我不確定',
    '無法確定',
    '我沒有看到',
    '我看不到',
    '我無法驗證',
    '看不見',
    '看不出來',
    '我找不到',
    '無法確認',
    '不確定',
  ];

  /// 對 [result] 的回答證據評分。回傳 null＝本輪不可評分。
  static double? score(AgentLoopResult result) {
    // ── 不可評分：無本體、或非完成態的攔截輪 ─────────────────────
    final reply = result.reply;
    if (reply.isEmpty) return null;
    if (result.cancelled) return null; // 取消輪：不進校準統計（無訊號）
    if (reply == '（已取消——任務尚未開始）') return null;

    // ── 分階：按執行證據定階 ─────────────────────────────────────
    double score;
    if (result.usedChatBypass) {
      // 對話直通道：無工具、單次 completion。證據＝對話能力，非事實查證。
      score = 0.85;
    } else if (result.turns.isEmpty) {
      // 非 bypass、零輪——異常態（如錯誤回覆），無訊號。
      return null;
    } else {
      final toolTurns =
          result.turns.where((t) => t.toolCall != null).toList();
      if (toolTurns.isEmpty) {
        // 全裝但零工具（模型直接回答）——同直通道語意。
        score = 0.85;
      } else {
        final okCount = toolTurns
            .where((t) => t.toolResult?.success == true)
            .length;
        final failed = toolTurns.length - okCount;
        score = failed > 0 ? 0.60 : 0.95;
      }
    }

    // ── 截斷與上限 ───────────────────────────────────────────────
    if (result.hitTurnLimit) score = 0.40;

    // ── 誠實自白降一階 ───────────────────────────────────────────
    // 「我不確定」出現在回覆＝模型自己宣稱低信心。誠實不該被懲罰，
    // 但校準統計必須知道：這輪的自稱信心低。降 0.1（同 bucket 級距）。
    final replyLower = reply.toLowerCase();
    if (kHonestySignals.any(replyLower.contains)) {
      score = (score - 0.1).clamp(0.0, 1.0);
    }

    return score;
  }
}
