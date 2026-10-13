// [小葵 2026-09-21] R5——夢境沉思 MVP（K5）
//
// Blue 2026-09-20 設計：夢境主幹收反思結論；動態冷門時段（不固定 23:00）。
// 統一迴路 R5：議程三源 → 結論卡 → 入生命樹 → 回饋。
//
// MVP 邊界（誠實標注）：
// - 本版結論卡為「規則引擎」產出（確定論、可測試）；
//   LLM 做夢版（敘事反思）是下一版——介面不變，換心臟即可
// - agent_consensus 需 ≥2 agents 共識；MVP 單 agent 夢先寫
//   branch_type=agent_draft（草稿卡），經 Blue 或第二 agent 複驗後
//   才升級 human_consensus / agent_consensus——不冒充共識
// - 文風鐵則：結論 ≤5 行、白話、禁工程術語

import 'package:flutter/foundation.dart';

import '../compass/compass_self_gauge.dart';
import 'global_notice_channel.dart';
import 'life_tree_store.dart';

/// 一條未結案傷口（來自 compass_pitfalls pending 條目）
class PendingWound {
  final int pitfallId;
  final String toolName; // 受傷的工具
  final String text; // 傷口全文（含症狀）

  const PendingWound({
    required this.pitfallId,
    required this.toolName,
    required this.text,
  });
}

/// 傷口驗證器：回傳 true＝病灶已痊癒（並已銷案改寫 pitfall）
typedef WoundHealer = bool Function(PendingWound wound);

/// 一場夢的結果
class DreamResult {
  final String sessionId;
  final int conclusions; // 產出結論卡數
  final int revisited; // 重評遺憾數
  final List<String> summary; // 給使用者看的白話摘要

  const DreamResult({
    required this.sessionId,
    required this.conclusions,
    required this.revisited,
    required this.summary,
  });
}

/// 夢境沉思引擎
class DreamService {
  DreamService._();
  static final DreamService instance = DreamService._();

  /// 跑一場夢。
  ///
  /// 議程三源由呼叫端組裝（agent tool 組真實數據；測試注入假數據）：
  /// - [redFlags] 儀表紅燈（R4）
  /// - [metrics] 儀表快照（K1/W4 統計）
  /// - [regrets] 遺憾清單（歷史主幹未重評分支）
  /// - [dreamers] 參與者（MVP=單 agent；≥2 才可寫 agent_consensus）
  DreamResult runDream({
    required List<String> redFlags,
    required CompassSelfMetrics metrics,
    required List<LifeTreeThoughtBranch> regrets,
    List<PendingWound> pendingWounds = const [],
    WoundHealer? woundHealer,
    List<String> dreamers = const [],
    String? modelUsed,
  }) {
    final store = LifeTreeStore.instance;
    final sessionId =
        'dream_${DateTime.now().millisecondsSinceEpoch}';
    final summary = <String>[];
    var conclusions = 0;

    // ── 議程 0：傷口收尾 [Blue 2026-09-21 拍板「夢境收尾」] ──
    // 傷口#38 教訓：病灶修好了（器官建了），但沒人回去結案——
    // 傷口永遠掛著 pending。夢裡主動驗證：痊癒就銷案＋說清楚誰治好的。
    for (final w in pendingWounds) {
      if (woundHealer == null) break;
      try {
        final healed = woundHealer(w);
        if (healed) {
          final id = store.addDream(LifeTreeDream(
            dreamSessionId: sessionId,
            // [Blue 2026-09-21 拍板] 銷案卡=零成本事實驗證（SQL 查表），
            // 通過即自動升級 agent_consensus——非判斷類不需要人確認。
            // （propose/escalate 類仍走全域對話問人）
            branchType: 'agent_consensus',
            conclusion: '一條舊傷口其實已經痊癒，替它銷案了：${_plain(w.text)}',
            decision: 'maintain',
            sourceClues: [
              '傷口 #${w.pitfallId} 驗證通過自動銷案',
              '升級依據：事實驗證（零 token），非 LLM 判斷'
            ],
            companionIds: dreamers,
            modelUsed: modelUsed ?? 'rule-engine',
            createdAt: DateTime.now(),
          ));
          if (id > 0) conclusions++;
          summary.add('發現一條舊傷口其實已經好了，替它銷案（${w.toolName}）');
        } else {
          summary.add('有條傷口還沒好，繼續觀察（${w.toolName}）');
        }
      } catch (_) {
        // fail-open：驗證失敗不擋夢
      }
    }

    // ── 議程 1：紅燈 → propose 結論卡 ─────────────
    for (final flag in redFlags) {
      final id = store.addDream(LifeTreeDream(
        dreamSessionId: sessionId,
        branchType: 'agent_draft',
        conclusion: '需要處理：$flag',
        decision: 'propose',
        sourceClues: ['紅燈: $flag'],
        companionIds: dreamers,
        modelUsed: modelUsed ?? 'rule-engine',
        createdAt: DateTime.now(),
      ));
      if (id > 0) conclusions++;
      summary.add('發現問題：$flag');
      // [Blue 2026-09-21 拍板] 確認類訊息走全域對話——不塞彈窗不干擾工作對話
      GlobalNoticeChannel.instance.push(
      title: '夢境發現一個問題，想跟你討論',
      body: flag,
      kind: 'dream_propose',
      );
      }

    // ── 議程 2：K1 統計 → 總結論卡（maintain 或 propose）──
    if (metrics.k1Judgments >= 10) {
      final healthy = metrics.k1EscalateRate <= 0.5;
      final conclusion = healthy
          ? '守門員運作正常：這段時間 ${metrics.k1Judgments} 次判斷中，'
              '${(metrics.k1EscalateRate * 100).toStringAsFixed(0)}% 交給大腦完整思考——'
              '維持現狀，繼續累積經驗。'
          : '守門員太常把問題丟給大腦（${(metrics.k1EscalateRate * 100).toStringAsFixed(0)}%）——'
              '建議累積經驗後重新訓練判斷力。';
      final id = store.addDream(LifeTreeDream(
        dreamSessionId: sessionId,
        branchType: 'agent_draft',
        conclusion: conclusion,
        decision: healthy ? 'maintain' : 'propose',
        sourceClues: [
          'K1 判斷 ${metrics.k1Judgments} 次（need=${metrics.k1Need}）',
          '規則層分擔 ${metrics.k1RuleShare}%'
        ],
        companionIds: dreamers,
        modelUsed: modelUsed ?? 'rule-engine',
        createdAt: DateTime.now(),
      ));
      if (id > 0) conclusions++;
      summary.add(healthy ? '守門員健康，維持現狀' : '守門員需要再訓練');
    }

    // ── 議程 3：遺憾清單 → escalate_to_user（MVP：重評交給人）──
    // [小葵 2026-10-05 生命樹代謝] 同時自動結案「已在夢裡重看過」的遺憾：
    // 夢把遺憾端上議程=重看完成。verdict 記「夢中重看」——
    // 不假裝有判斷力（LLM 深夢版未上），但清單會縮短，不再天天重複。
    var revisited = 0;
    for (final r in regrets.take(5)) {
      final id = store.addDream(LifeTreeDream(
        dreamSessionId: sessionId,
        branchType: 'agent_draft',
        conclusion: '有一條沒走的路想再看看：${_plain(r.thought)}',
        decision: 'escalate_to_user',
        sourceClues: ['遺憾 #${r.id}（源自執行記錄 ${r.ledgerId}）'],
        companionIds: dreamers,
        modelUsed: modelUsed ?? 'rule-engine',
        createdAt: DateTime.now(),
      ));
      if (id > 0) conclusions++;
      // 代謝：這條遺憾已進夢重看 → 結案，明晚不再重複夢它
      if (r.id != null && store.markRevisited(r.id!, '夢中重看（rule-engine）：已端上議題請主人裁決') > 0) {
        revisited++;
      }
      summary.add('想請你看看一條舊分支：${_plain(r.thought)}');
      // [Blue 2026-09-21 拍板] escalate 卡走全域對話——使用者可反問討論
      GlobalNoticeChannel.instance.push(
        title: '夢裡想到一條沒走的路，想請你看看',
        body: _plain(r.thought),
        kind: 'dream_escalate',
      );
    }

    // ── 無事可夢 → 一張「安睡卡」（夢境也要留痕，證明迴路活著）──
    if (conclusions == 0) {
      store.addDream(LifeTreeDream(
        dreamSessionId: sessionId,
        branchType: 'agent_draft',
        conclusion: '這場夢沒有發現問題：紅燈 0、遺憾 0、判斷樣本 '
            '${metrics.k1Judgments} 筆（不足 10 尚無統計意義）。安睡。',
        decision: 'maintain',
        sourceClues: ['無紅燈', '遺憾清單空'],
        companionIds: dreamers,
        modelUsed: modelUsed ?? 'rule-engine',
        createdAt: DateTime.now(),
      ));
      conclusions = 1;
      summary.add('一切平靜，沒有需要處理的事');
    }

    debugPrint('[Dream] $sessionId：$conclusions 張結論卡');
    return DreamResult(
      sessionId: sessionId,
      conclusions: conclusions,
      revisited: revisited, // [2026-10-05 代謝] 進夢即結案——清單會縮短
      summary: summary,
    );
  }

  /// 白話化（文風鐵則：禁工程術語洩漏給使用者）
  String _plain(String thought) {
    var t = thought.replaceAll(RegExp(r'[{}\[\]<>]'), '');
    return t.length > 60 ? '${t.substring(0, 60)}…' : t;
  }
}
