// red_flag_reporter.dart
// [小葵 2026-10-19 殘件①] 紅旗報告員——CompassSelfGauge.redFlags() 的「嘴」。
//
// 病史：T9① 修好了羅盤的儀表（K1 escalate 過高/認知傷口堆積/覆蓋率偏低
// 都算得出紅旗），T12-③ 修好了開口管線（佇列持久化/證據閘/額度），
// 但把紅旗餵進嘴的生產者只有 DreamScheduler 凌晨夢一條路——
// App 半夜沒開、或紅旗白天才出現，儀表就永遠只算不說（Fable：
// 「T9① 只做了一半」的另一半）。
//
// [小葵 2026-11-03 待決策卡閉環 B 案] 報告改走開卡——
// 病例：同三面紅旗 10/29–11/3 每天重報（使用者回應了紅旗也不知道）、
// 4 秒內三路搶閘開 3 個 session。藥方：
//   1. 每面紅旗先 DecisionCardStore.tryOpenCard（BEGIN IMMEDIATE 原子）：
//      同類未結案卡存在 → 靜默（治每天重報＋三連發，一石二鳥）
//   2. dismissed 冷卻：使用者說「先不處理」結案後，同類紅旗 7 天不再報
//      （拒絕也是授權鐵則——尊重「不要」，但不永遠閉嘴漏掉真惡化）
//   3. 開卡成功才入開口佇列——卡片與訊息一對一，conversation_id 事後綁
// （舊 compass_meta speak_redflags_<date> 記帳保留讀取相容，不再寫入）
//
// 本類：紅旗去重記帳＋委託 CompassSpeaker 開口（三閘仍在 speaker：
// 信心/證據/額度）。生產者兩條：
//   - DreamScheduler 夜夢路（原有）
//   - DreamScheduler 白天心跳路（每小時節流）

import 'package:flutter/foundation.dart';

import 'compass_speaker.dart';
import 'compass_store.dart';
import 'decision_card_store.dart';

/// 紅旗類別鍵——紅旗文字含動態數字（「未結案傷口 7 筆」），
/// 逐字比對會漏去重；把數字歸一成 # 再截斷，同類紅旗隔天數字變了
/// 仍是同一類。
String redFlagCategoryKey(String flag) {
  final normalized = flag.replaceAll(RegExp(r'[0-9]+'), '#');
  return normalized.length > 24 ? normalized.substring(0, 24) : normalized;
}

class RedFlagReporter {
  RedFlagReporter._();
  static final RedFlagReporter instance = RedFlagReporter._();

  static const int dismissCooldownDays = 7;

  /// dismissed 冷卻鍵（compass_meta key = `redflag_cooldown_<categoryKey>`，
  /// 值 = 冷卻到期日 yyyy-mm-dd）
  String _cooldownKey(String categoryKey) => 'redflag_cooldown_$categoryKey';

  /// [Blue 抓包 2026-11-04] resolved 冷卻——done 結案也是「已處理」。
  /// 病例：K1 卡 17:57 done → 30 秒後心跳又報同類紅旗開新卡＋開口
  /// 「才剛解決的又提出來」。done 冷卻 3 天（比 dismissed 7 天短——
  /// resolved 可能復發，早點允許再報；但絕不當天重報）。
  static const int resolvedCooldownDays = 3;

  String _resolvedCooldownKey(String categoryKey) =>
      'redflag_resolved_cooldown_$categoryKey';

  bool _inResolvedCooldown(String categoryKey) {
    try {
      final until = CompassStore.instance
          .getMeta(_resolvedCooldownKey(categoryKey));
      if (until == null) return false;
      final d = DateTime.tryParse(until);
      return d != null && DateTime.now().isBefore(d);
    } catch (_) {
      return false;
    }
  }

  void startResolvedCooldown(String categoryKey) {
    try {
      final until = DateTime.now()
          .add(const Duration(days: resolvedCooldownDays));
      CompassStore.instance.setMeta(
          _resolvedCooldownKey(categoryKey), until.toIso8601String());
    } catch (_) {}
  }

  /// [Blue 抓包 2026-11-04] 紅旗標題 → 人話開口文案。
  /// 鐵則：一句白話狀況＋一個具體可回覆的問題。不貼內部術語、
  /// 不叫使用者去別的頁面自己查。新增紅旗種類時在此補翻譯條目。
  ///
  /// [統合修復 #2 2026-11-04 晚場] 同步產出決策選項——開口給的
  /// 選項必須落卡（awaiting_decision），否則使用者拍板時 agent
  /// 沒有軌道接（病例：18:23 開口給「補規則/修管線」二選一、
  /// 18:28 使用者拍板「修管線」——沒進卡，拍板蒸發）。
  /// 文案與選項同源產生，保證「嘴上說的＝卡上有的」。
  static ({String speak, List<DecisionOption> options}) _toHumanSpeak(
      String flag) {
    // K1 升級率
    final k1 = RegExp(r'K1 escalate 率 (\d+)%').firstMatch(flag);
    if (k1 != null) {
      return (
        speak: '我判斷「要不要翻記憶」這件事，最近 100 次裡有 ${k1[1]} 次'
            '不敢自己決定、把問題丟給大模型，太頻繁了。\n'
            '想請你決定：要我先補幾條簡單規則讓我自己判（快，但學不到新招），'
            '還是先修資料管線讓我慢慢學會判斷（慢，但治本）？',
        options: const [
          DecisionOption(
              id: 'opt_1',
              label: '補簡單規則',
              detail: '在規則層加幾條關鍵字判斷。快，但學不到新招。',
              recommended: false),
          DecisionOption(
              id: 'opt_2',
              label: '修資料管線（治本）',
              detail: '修訓練樣本配對管線，讓我慢慢學會自己判斷。慢，但治本。',
              recommended: true),
        ],
      );
    }
    // 未結案傷口
    if (flag.contains('未結案傷口')) {
      final n = RegExp(r'(\d+) 筆').firstMatch(flag)?.group(1) ?? '數';
      return (
        speak: '我整理了我曾經失敗過的操作，有 $n 件一直沒有後續處理。\n'
            '想請你決定：要我現在把這些舊失敗整理成一份清單讓你掃一眼，'
            '還是先擱著、等真的再撞到同款失敗才處理？',
        options: const [
          DecisionOption(
              id: 'opt_1',
              label: '整理清單給我看',
              detail: '把舊失敗逐筆列出（時間、工具、原因），你掃一眼定奪。',
              recommended: true),
          DecisionOption(
              id: 'opt_2',
              label: '先擱著',
              detail: '等真的再撞到同款失敗才處理（同類冷卻，不會重複打擾）。',
              recommended: false),
        ],
      );
    }
    // 認知傷口
    if (flag.contains('認知傷口')) {
      final n = RegExp(r'(\d+) 筆').firstMatch(flag)?.group(1) ?? '數';
      return (
        speak: '我之前有 $n 次說了跟事實不符的話（宣稱看到沒有的東西），'
            '我想把這幾次攤開來檢查。\n'
            '想請你決定：要我把這幾次列給你看，還是你直接告訴我當時的狀況？',
        options: const [
          DecisionOption(
              id: 'opt_1',
              label: '列出來一起看',
              detail: '把說錯的幾次逐筆攤開（當時說了什麼、事實是什麼）。',
              recommended: true),
          DecisionOption(
              id: 'opt_2',
              label: '我來講當時狀況',
              detail: '你直接補充當時的背景，我對照修正。',
              recommended: false),
        ],
      );
    }
    // fallback：至少剝掉括號內的內部註記、補一個可回覆的問題
    final bare = flag.replaceAll(RegExp(r'（[^）]*）'), '').trim();
    return (
      speak: '我注意到一個狀況：$bare。\n'
          '想請你決定：要我深入調查這件事，還是先不用理它？',
      options: const [
        DecisionOption(
            id: 'opt_1',
            label: '深入調查',
            detail: '我把這件事查清楚再回報你。',
            recommended: true),
        DecisionOption(
            id: 'opt_2',
            label: '先不用理',
            detail: '先擱著（同類冷卻，不會重複打擾）。',
            recommended: false),
      ],
    );
  }

  /// 同類紅旗是否在 dismissed 冷卻期內
  bool _inCooldown(String categoryKey) {
    try {
      final until = CompassStore.instance.getMeta(_cooldownKey(categoryKey));
      if (until == null) return false;
      final d = DateTime.tryParse(until);
      return d != null && DateTime.now().isBefore(d);
    } catch (_) {
      return false; // 讀不到＝不在冷卻（fail-open：寧可多說）
    }
  }

  /// dismissed 結案時呼叫——同類紅旗冷卻 7 天
  void startCooldown(String categoryKey) {
    try {
      final until = DateTime.now().add(const Duration(days: dismissCooldownDays));
      CompassStore.instance.setMeta(
          _cooldownKey(categoryKey), until.toIso8601String());
    } catch (_) {} // fail-quiet
  }

  /// 回報紅旗。每面紅旗走「先開卡」：同類未結案卡存在 → 靜默；
  /// 冷卻期內 → 靜默；新卡開成 → 入開口佇列。
  /// 回傳 true＝本次有新紅旗入列（供呼叫端 log）。
  bool report(List<String> flags, {String source = 'unspecified'}) {
    if (flags.isEmpty) return false;

    final cards = DecisionCardStore.instance;
    final opened = <String>[]; // 開成卡的紅旗（要開口的）
    for (final f in flags) {
      final catKey = redFlagCategoryKey(f);
      // 閘①：dismissed 冷卻
      if (_inCooldown(catKey)) continue;
      // 閘①.5：[Blue 抓包 2026-11-04] resolved 冷卻——才剛 done 結案的
      // 同類紅旗 3 天內不再報（「才剛解決的又提出來」絕版）。
      if (_inResolvedCooldown(catKey)) continue;
      // 閘②：原子開卡（同類未結案卡存在 → null → 靜默不重報）
      final card = cards.tryOpenCard(
        title: f.length > 60 ? '${f.substring(0, 60)}…' : f,
        body: f,
        categoryKey: catKey,
        source: source,
      );
      if (card != null) {
        opened.add(f);
        // [統合修復 #2] 開口選項同步落卡——嘴上給的二選一必須
        // 寫進卡（awaiting_decision），使用者拍板才有軌道接。
        // 文案與選項同源（_toHumanSpeak 一份產出兩樣）。
        final spoken = _toHumanSpeak(f);
        cards.markAwaitingDecision(card.id, spoken.options);
      }
    }
    if (opened.isEmpty) return false;

    // 信心沿用夢路原版推導：1 紅旗=0.80、2=0.90、3+=0.95
    final conf = switch (opened.length) {
      1 => 0.80,
      2 => 0.90,
      _ => 0.95,
    };
    // [Blue 抓包 2026-11-04] 開口文案＝人話模板，不貼紅旗標題（內部術語）。
    // 模板：「一句白話狀況＋一個具體的問題（可回覆做決定）」。
    // 病例原文「整理內部時我注意到一些狀況（K1 escalate 率 62% 過高
    // （>50%）——頭沒訓練或規則層覆蓋不足；…）」——使用者看不懂、
    // 不知道怎麼決定。
    final humanLines =
        opened.map((f) => _toHumanSpeak(f).speak).take(2).join('\n');
    final added = CompassSpeaker.instance.tryEnqueue(CompassSpeakDraft(
      humanLines,
      '$source:${opened.length}',
      conf,
      // 證據主體沿用夢路結論：K1/工具循環/傷口證據都在 agent.loop
      organId: 'agent.loop',
    ));
    if (added) {
      debugPrint('[RedFlagReporter] $source 報了 ${opened.length} 面紅旗'
          '（已開 ${opened.length} 張待決策卡）');
    }
    return added;
  }
}
