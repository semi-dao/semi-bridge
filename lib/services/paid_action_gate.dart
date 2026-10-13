// paid_action_gate.dart
// [教練 Agent 2026-08-21] $33 事件根治——中央付費動作閘門（機械保險絲）
//
// 稽核結論：付費路徑有五條（generate_image 工具、canvas 節點、
// sub-workflow、CapabilityExecutor、explicit-provider 直達），
// 過去的閘門只守了第一條。本閘門裝在 BridgeActionExecutor.execute
// 咽喉點——不論哪條路進來，付費動作一律：
//   1. 每日上限檢查（image 30 / video 5 / music 10，可調）
//   2. 超過 → 誠實擋下（寧紅字不假成功），附上限數字與重置時間
//   3. 未超過 → 佔位計數（保守：寧可少算不可漏算）
//
// 設計原則（使用者鐵則）：
// - 付費能力保留，不拔——但花錢必須有機械上限，不能只靠人守確認框
// - UI 誠實：擋下就明說擋下，理由、額度、重置時間講清楚
// - 確認框是人這關，本閘是保險絲那關——兩關都要在

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'budget_ledger.dart';

enum PaidActionKind { image, video, music, llm }

class PaidActionGate {
  PaidActionGate._();
  static final PaidActionGate instance = PaidActionGate._();

  /// [刀 2 D2.2] Ambient companionId——「這筆帳記在誰頭上」的環境語境。
  /// 派工開始時 set（dispatchTask），結束時清。五個 executor 呼叫點
  /// 零改動自動帶入（與 canvas ambient 覆寫堆疊同哲學：不開旁門，
  /// 上下文用環境帶）。
  String? _ambientCompanionId;
  // ignore: avoid_setters_without_getters
  set ambientCompanionId(String? v) => _ambientCompanionId = v;

  /// 每日上限（預設）。image 30 張 ≈ 最貴 $6/天的天險；
  /// video 最貴（數秒影片數美元）→ 5；music 10。
  /// llm：chat agent loop 對話輪數 [小葵 2026-09-21]——
  /// 9/21 astra 生日問答 5 題燒 $9 事件的止血天險（每輪含多輪檢索，
  /// 一輪可達數十萬 tokens）。500 輪/日 ≈ 一般使用量的 3-5 倍餘裕。
  /// 可透過 SharedPreferences 覆寫（paid_gate_cap_image 等）。
  static const Map<PaidActionKind, int> defaultCaps = {
    PaidActionKind.image: 30,
    PaidActionKind.video: 5,
    PaidActionKind.music: 10,
    PaidActionKind.llm: 500,
  };

  static const _prefsPrefix = 'paid_gate';

  String get _today =>
      DateTime.now().toIso8601String().substring(0, 10); // yyyy-mm-dd

  Future<Map<PaidActionKind, int>> _loadTodayCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('$_prefsPrefix.date') ?? '';
    if (savedDate != _today) {
      // 跨日重置
      await prefs.setString('$_prefsPrefix.date', _today);
      await prefs.setInt('$_prefsPrefix.count_image', 0);
      await prefs.setInt('$_prefsPrefix.count_video', 0);
      await prefs.setInt('$_prefsPrefix.count_music', 0);
      return {for (final k in PaidActionKind.values) k: 0};
    }
    return {
      PaidActionKind.image: prefs.getInt('$_prefsPrefix.count_image') ?? 0,
      PaidActionKind.video: prefs.getInt('$_prefsPrefix.count_video') ?? 0,
      PaidActionKind.music: prefs.getInt('$_prefsPrefix.count_music') ?? 0,
    };
  }

  /// 檢查＋佔位。allowed=false 時附誠實理由。
  /// [教練 Agent 2026-08-21] Phase A——可附 intent/prompt 進 Ledger 記帳。
  /// [刀 2 D2.2] companionId——這筆帳記在哪个夥伴頭上（身份卡審計軌跡）。
  Future<PaidGateVerdict> checkAndReserve(
    PaidActionKind kind, {
    String? intent,
    String? prompt,
    String? companionId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final counts = await _loadTodayCounts();
    String? ledgerId;
    final capKey = '$_prefsPrefix.cap_${kind.name}';
    final used = counts[kind] ?? 0;
    // [小葵 2026-09-24 Blue 令·拆牆] 單日上限檢查移除——Blue 拍板：
    // 「現在執行正常了，不需要設單日上限」。防失控已由智慧閘門接管
    // （workflow_executor：每輪上限＝付費節點數+20，超過停任務不殺 App）
    // ——runaway 迴圈在任務層就被攔，日上限對正當手動使用只是摩擦。
    // 計數（used）與 Ledger 照舊——帳要看，牆不擋。
    debugPrint('[PaidGate] 放行 ${kind.name}（今日計數 $used，上限牆已拆除）');

    // 佔位（保守計數：執行失敗也計——保險絲寧緊勿鬆）
    await prefs.setInt('$_prefsPrefix.count_${kind.name}', used + 1);

    // [教練 Agent 2026-08-21] Phase A——記入 Ledger（意圖/成敗，供覆盤與節流）
    if (intent != null) {
      ledgerId = await BudgetLedger.instance.record(
        kind: kind,
        intent: intent,
        prompt: prompt ?? '',
        companionId: companionId,
      );
    }
    return PaidGateVerdict(allowed: true, reason: '${used + 1}（無上限）', ledgerId: ledgerId);
  }

  /// [教練 Agent 2026-08-21] 動作結案——成功/失敗寫回 Ledger（誠實記帳）
  static Future<void> settle(String? ledgerId, {required bool ok, String? error}) async {
    if (ledgerId == null || ledgerId.isEmpty) return;
    await BudgetLedger.instance.settle(ledgerId, ok: ok, error: error);
  }

  /// [教練 Agent 2026-08-21] 預算之眼——即時額度狀態（system prompt 注入用）
  Future<String> budgetEye() async {
    final counts = await _loadTodayCounts();
    final prefs = await SharedPreferences.getInstance();
    final caps = <PaidActionKind, int>{};
    for (final k in PaidActionKind.values) {
      caps[k] = prefs.getInt('$_prefsPrefix.cap_${k.name}') ?? defaultCaps[k]!;
    }
    final stats = await BudgetLedger.instance.todayStats();
    final waste = await BudgetLedger.instance.wasteRate();
    final lines = <String>[];
    for (final k in PaidActionKind.values) {
      lines.add('${_kindLabel(k)} ${counts[k]}/${caps[k]}');
    }
    final buf = StringBuffer('[額度] 今日：${lines.join('、')}');
    if (stats.total > 0) {
      buf.write('\n[紀錄] 今日 ${stats.total} 筆：${stats.ok} 成功、${stats.failed} 失敗');
    }
    if (waste > 0) {
      final pct = (waste * 100).round();
      buf.write('\n[覆盤] 近期失敗率 $pct%（來源：BudgetLedger）'
          '${pct >= 30 ? '（偏高——同一 prompt 連續失敗**不可**直接重試，先換策略）' : ''}');
    }
    buf.write('\n[自律原則] 額度是使用者的信任。批量生成前先規劃用途；'
        '失敗 2 次必須換 prompt 或換服務；重複內容優先重用既有產出。');
    return buf.toString();
  }

  String _kindLabel(PaidActionKind k) => switch (k) {
        PaidActionKind.image => '圖片',
        PaidActionKind.video => '影片',
        PaidActionKind.music => '音樂',
        PaidActionKind.llm => '對話輪',
      };
}

class PaidGateVerdict {
  final bool allowed;
  final String reason;

  /// [教練 Agent 2026-08-21] 記帳 ID——動作結案時回寫成敗
  final String? ledgerId;
  const PaidGateVerdict(
      {required this.allowed, required this.reason, this.ledgerId});
}
