// decision_card_agent_tool.dart
// [小葵 2026-11-03 待決策卡閉環 Step 3] agent 拍板流工具——
// 主動回應的「討論完 → 拍板 → 執行 → 結案」軌道。
// Spec: docs/specs/2026-11-03-decision-card-loop.md §3
//
// 三件套：
//   decision_cards        ——查未結案卡（agent 開工先看有沒有待決策線）
//   decision_propose      ——agent 給 2-3 選項 → 卡進 awaiting_decision
//   decision_resolve      ——拍板執行（chosen）／先不處理（dismissed+冷卻7天）
//
// 病例（2026-11-03）：Blue 問「這題你建議該如何調整？」→ 小橋收證據
// → 卡死逾時 → 罐頭道歉。沒有軌道：建議靠 LLM 自由發揮、拍板無記錄、
// 紅旗不知道使用者回應了。本工具組是結構化載體。
//
// 工具錯誤訊息鐵則（compass_propose 案）：報錯要當教材不只擋——
// 附正確格式範例照抄。

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../agent_tool.dart';
import '../../compass/decision_card_store.dart';
import '../../compass/red_flag_reporter.dart';

/// 查未結案待決策卡
class DecisionCardsTool extends AgentTool {
  @override
  String get name => 'decision_cards';

  @override
  String get description =>
      '查目前的待決策卡清單（主動回報開出的待討論事項）。'
      '每張卡是一條待使用者拍板的線——狀態：open（待討論）/'
      'discussing（討論中）/awaiting_decision（等你給選項）/'
      'executing（已拍板執行中）。主動回應對話裡使用者問建議時，'
      '先查這裡找到對應的卡。';

  @override
  List<AgentToolParamSpec> get paramSpecs => const [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final cards = DecisionCardStore.instance.unresolvedCards();
    if (cards.isEmpty) {
      return AgentToolResult.success('目前沒有未結案的待決策卡。');
    }
    final buf = StringBuffer();
    buf.writeln('未結案待決策卡 ${cards.length} 張：');
    for (final c in cards) {
      buf.writeln('---');
      buf.writeln('id: ${c.id}');
      buf.writeln('title: ${c.title}');
      buf.writeln('status: ${c.status}');
      if (c.conversationId != null) {
        buf.writeln('conversation: ${c.conversationId}');
      }
      buf.writeln('body: ${c.body.length > 300 ? '${c.body.substring(0, 300)}…' : c.body}');
      if (c.options.isNotEmpty) {
        buf.writeln('options: ${c.options.map((o) => '${o.id}=${o.label}').join('; ')}');
      }
    }
    return AgentToolResult.success(buf.toString());
  }
}

/// agent 提案——給 2-3 個選項，卡進 awaiting_decision
class DecisionProposeTool extends AgentTool {
  @override
  String get name => 'decision_propose';

  @override
  String get description =>
      '對一張待決策卡提出 2-3 個明確選項讓使用者拍板。'
      '使用者問「建議如何調整／怎麼做」時，收集完證據後用這個工具'
      '把選項寫進卡（不是只在對話裡說）。選項要具體可執行，'
      '並標記你建議哪個。範例：'
      'decision_propose(card_id="dc_...", options='
      '[{"id":"opt_1","label":"訓練K1頭","detail":"用累積的判斷樣本重訓","recommended":true},'
      '{"id":"opt_2","label":"補規則層","detail":"把已知案例寫成硬規則"}])';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'card_id',
          description: '待決策卡 id（decision_cards 查得到）',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'options',
          description:
              '選項陣列 JSON 字串，每項 {"id":"opt_1","label":"一行標籤",'
              '"detail":"說明","recommended":true/false}（2-3 個，'
              '恰一個 recommended）',
          required: true,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final cardId = args['card_id'] as String?;
    final optionsRaw = args['options'] as String?;
    if (cardId == null || cardId.trim().isEmpty) {
      return AgentToolResult.failure(
          '缺少 card_id。先呼叫 decision_cards 查卡 id。');
    }
    if (optionsRaw == null || optionsRaw.trim().isEmpty) {
      return AgentToolResult.failure(
          '缺少 options。正確格式：options='
          '[{"id":"opt_1","label":"…","detail":"…","recommended":true},'
          '{"id":"opt_2","label":"…","detail":"…"}]');
    }

    final card = DecisionCardStore.instance.byId(cardId);
    if (card == null) {
      return AgentToolResult.failure('找不到卡 $cardId。用 decision_cards 重查。');
    }

    // 解析選項（容錯：先直解，失敗再抓陣列段）
    List<dynamic> list;
    try {
      list = jsonDecodeLoose(optionsRaw);
    } catch (_) {
      return AgentToolResult.failure(
          'options 不是合法 JSON。照抄格式：'
          '[{"id":"opt_1","label":"一行標籤","detail":"說明","recommended":true}]'
          '（注意雙引號，label 內不要用未轉義的雙引號）');
    }
    if (list.length < 2 || list.length > 3) {
      return AgentToolResult.failure('選項要 2-3 個（收到 ${list.length} 個）。');
    }
    final options = <DecisionOption>[];
    for (var i = 0; i < list.length; i++) {
      final m = list[i];
      if (m is! Map) {
        return AgentToolResult.failure('第 ${i + 1} 個選項不是物件。');
      }
      final label = (m['label'] as String?)?.trim() ?? '';
      if (label.isEmpty) {
        return AgentToolResult.failure('第 ${i + 1} 個選項缺 label。');
      }
      options.add(DecisionOption(
        id: 'opt_${i + 1}',
        label: label,
        detail: (m['detail'] as String?) ?? '',
        recommended: m['recommended'] == true || m['recommended'] == 'true',
      ));
    }
    final recCount = options.where((o) => o.recommended).length;
    if (recCount != 1) {
      return AgentToolResult.failure(
          '恰一個選項 recommended=true（收到 $recCount 個）——'
          '使用者要看你建議哪個。');
    }

    DecisionCardStore.instance.markAwaitingDecision(cardId, options);
    debugPrint('[DecisionCard] $cardId 提案 ${options.length} 選項 '
        '（awaiting_decision）');
    return AgentToolResult.success(
        '已提交 ${options.length} 個選項，卡進入 awaiting_decision。'
        '回覆使用者時把選項列出（含標號與建議），等使用者拍板。');
  }

  static List<dynamic> jsonDecodeLoose(String raw) {
    final s = raw.trim();
    try {
      return jsonDecode(s) as List<dynamic>;
    } catch (_) {
      // 抓第一個 [ 到最後一個 ] ——模型常包一層字串或 ```json 圍籬
      final start = s.indexOf('[');
      final end = s.lastIndexOf(']');
      if (start >= 0 && end > start) {
        return jsonDecode(s.substring(start, end + 1)) as List<dynamic>;
      }
      rethrow;
    }
  }
}

/// 拍板結案——resolved（執行完）或 dismissed（先不處理）
class DecisionResolveTool extends AgentTool {
  @override
  String get name => 'decision_resolve';

  @override
  String get description =>
      '待決策卡結案。兩種：(1) 使用者拍板某選項且你已執行完成 → '
      'action="done"＋chosen_option_id＋完成證據 note（什麼做了、驗證結果）；'
      '(2) 使用者說先不處理／晚點再說 → action="dismiss"（同類紅旗冷卻 7 天）。'
      '★done 必附證據——不能只說完成，要說做了什麼動作、看到什麼結果。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'card_id',
          description: '待決策卡 id',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'action',
          description: 'done（拍板執行完成）/ dismiss（先不處理）',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'chosen_option_id',
          description: '使用者拍板的選項 id（action=done 時必填）',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'note',
          description: '完成證據或 dismiss 理由（action=done 時必填）',
          required: false,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final cardId = args['card_id'] as String?;
    final action = (args['action'] as String?)?.trim();
    final store = DecisionCardStore.instance;

    if (cardId == null || cardId.trim().isEmpty) {
      return AgentToolResult.failure('缺少 card_id。用 decision_cards 查。');
    }
    final card = store.byId(cardId);
    if (card == null) {
      return AgentToolResult.failure('找不到卡 $cardId。');
    }

    if (action == 'dismiss') {
      store.closeDismissed(cardId);
      RedFlagReporter.instance.startCooldown(card.categoryKey);
      debugPrint('[DecisionCard] $cardId dismissed（冷卻 7 天）');
      return AgentToolResult.success(
          '已結案（先不處理）。同類紅旗 7 天內不會再報。');
    }

    if (action == 'done') {
      final chosen = args['chosen_option_id'] as String?;
      final note = (args['note'] as String?)?.trim() ?? '';
      if (chosen == null || chosen.isEmpty) {
        return AgentToolResult.failure(
            'action=done 要帶 chosen_option_id（使用者拍板的選項）。');
      }
      if (note.isEmpty) {
        return AgentToolResult.failure(
            'action=done 要帶 note——完成證據：做了什麼動作、驗證結果是什麼。'
            '「已完成」不算證據。');
      }
      store.markDecided(cardId, chosen);
      store.closeResolved(cardId, note: note);
      // [Blue 抓包 2026-11-04] done 也是「已處理」——同類紅旗 3 天冷卻。
      // 病例：K1 卡 done 後 30 秒，心跳又報同類紅旗開新卡開口
      // （「才剛解決的又提出來」）。
      RedFlagReporter.instance.startResolvedCooldown(card.categoryKey);
      debugPrint('[DecisionCard] $cardId done（$chosen，同類冷卻 3 天）');
      return AgentToolResult.success('已結案（resolved）。待決策線閉環完成。');
    }

    return AgentToolResult.failure(
        'action 只能是 done 或 dismiss（收到 "$action"）。');
  }
}
