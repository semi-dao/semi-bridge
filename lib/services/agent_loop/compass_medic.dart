// compass_medic.dart
// [小葵 2026-09-17 W3+W4] 軍醫服務——羅盤出診＋傷口自癒一體。
//
// 設計稿：docs/specs/2026-09-17-compass-full-anatomy.md
// 掛載點：AgentLoop 工具執行咽喉點（與 CausalLedger.record 同址）
//
// 三個出診點（不靠 agent 自覺）：
//   1. 動手前：高風險工具執行前 compass_seek，命中卡注入該輪 context
//   2. 撞牆時：同工具連續失敗 ≥2 次 → 自動送該工具的藥
//   3. 開工時：AgentLoop 冷啟動注入器官地圖摘要卡（由 prompt builder 呼叫）
//
// 自癒循環（W4，Blue 拍板 Q1：治癒系統不靠 agent 動手自己長藥）：
//   工具失敗 → 自動立案 pending pitfall → 同工具後續成功 →
//   自動草擬藥方入庫（症狀→病根→藥方格式）→ 供 compass_seek 檢索
//
// 紀律（設計稿 3.2）：每輪最多 3 張卡、fail-open 必留錯誤痕跡、
// 注入計入 token 帳（BudgetLedger）。

import 'dart:convert';

import '../causal/causal_ledger_service.dart'; // [小葵 2026-09-21 R2] 自癒事件入歷史主幹
import '../compass/compass_store.dart';
import 'agent_loop_tools/compass_seek_agent_tool.dart'
    show ensureIntentIndexSeeded;

/// 軍醫——掛 AgentLoop 咽喉點的羅盤出診員。
class CompassMedic {
  CompassMedic._();
  static final CompassMedic instance = CompassMedic._();

  /// 動手前出診的高風險工具（會改變系統狀態的操作）。
  static const Set<String> kPreFlightTools = {
    'patch_source_file',
    'read_source_file',
    'canvas_add_node',
    'canvas_connect',
    'canvas_remove',
    'canvas_update_node',
    'run_terminal',
    'restart_app',
  };

  /// 工具名 → 檢索意圖詞（口語症狀導向，配合 intent_index 關鍵詞）。
  static const Map<String, String> kToolIntent = {
    'patch_source_file': '改檔 patch 原始碼',
    'read_source_file': '讀檔 原始碼 大檔',
    'canvas_add_node': '畫布 節點 空殼',
    'canvas_connect': '畫布 連線 port',
    'canvas_remove': '畫布 節點 移除',
    'canvas_update_node': '畫布 節點 參數',
    'run_terminal': '終端 指令 timeout',
    'restart_app': '重啟 行程 binary',
  };

  // ── 出診 1：動手前 ──────────────────────────────
  /// 高風險工具執行前查藥。回傳注入文字（null=無命中不注入）。
  /// fail-open：任何錯誤回 null，不擋任務。
  String? preFlight(String toolName, Map<String, dynamic> args) {
    if (!kPreFlightTools.contains(toolName)) return null;
    try {
      final hits = _seek(kToolIntent[toolName] ?? toolName);
      if (hits.isEmpty) return null;
      final buf = StringBuffer();
      buf.writeln('〔羅盤出診〕動手前必讀（$toolName 相關）：');
      var n = 0;
      for (final h in hits) {
        if (n >= 3) break; // 每輪上限 3 張卡
        buf.writeln('• ${h['hint']}');
        n++;
      }
      // 相關坑卡（該工具常見死法）
      final pits = _pitfallsForTool(toolName);
      for (final p in pits) {
        buf.writeln('• $p');
      }
      return buf.toString();
    } catch (e) {
      return null; // fail-open + 留痕由呼叫端 debugPrint
    }
  }

  // ── 出診 2：撞牆時 ──────────────────────────────
  /// 同工具連續失敗 ≥2 → 送藥。回傳注入文字（null=不送）。
  String? onWallHit(String toolName, String errorMessage) {
    try {
      final hits = _seek(kToolIntent[toolName] ?? toolName);
      final pits = _pitfallsForTool(toolName);
      if (hits.isEmpty && pits.isEmpty) return null;
      final buf = StringBuffer();
      buf.writeln('〔羅盤出診〕$toolName 連續失敗——歷史教訓：');
      for (final p in pits) {
        buf.writeln('• $p');
      }
      for (final h in hits.take(2)) {
        buf.writeln('• ${h['hint']}');
      }
      return buf.toString();
    } catch (_) {
      return null;
    }
  }

  // ── 開工時：器官地圖摘要卡 ──────────────────────
  /// AgentLoop 冷啟動注入（~250 tokens 瘦身版）。
  String bootBriefing() {
    try {
      final store = CompassStore.instance;
      final nRules =
          store.rules().where((r) => r.status.name == 'active').length;
      final nPits = store.pitfallCount();
      return '〔羅盤〕本 App 有 $nRules 條活規則、$nPits 張坑卡守護。'
          '修改任何功能前先 compass_seek(你的目的)——動手前查藥，'
          '撞牆兩次羅盤會自動送藥。立規則必答「誰在什麼時候執行」。';
    } catch (_) {
      return '〔羅盤〕修改任何功能前先 compass_seek(你的目的)。';
    }
  }

  // ── W4：傷口自癒 ────────────────────────────────
  /// 失敗自動立案（pending pitfall）。回傳案件 ID（null=未立案：
  /// 工具不在監視清單 / 7 天內同症狀已立案）。
  int? fileWoundCase(String toolName, String symptom) {
    try {
      final store = CompassStore.instance;
      final oid = _organForTool(toolName);
      if (oid == null) return null;
      // 去重：7 天內同工具同症狀不重複立案
      final key = 'wound:$toolName';
      final last = store.getMeta(key);
      final now = DateTime.now();
      if (last != null) {
        try {
          final lastAt = DateTime.parse(jsonDecode(last)['at'] as String);
          if (now.difference(lastAt).inDays < 7) return null;
        } catch (_) {}
      }
      final symptomShort =
          symptom.length > 120 ? symptom.substring(0, 120) : symptom;
      final text = '【pending·傷口立案】$toolName 失敗：$symptomShort';
      store.addPitfall(oid, text, author: 'auto:medic');
      // 去重時間戳記在 meta；案件 ID 不需要回傳給呼叫端（closeWoundCase
      // 以 pending 條目定位），lastInsertId 不另設 API。
      store.setMeta(key, jsonEncode({'at': now.toIso8601String()}));
      return 0; // 已立案（ID 內部定位）
    } catch (_) {
      return null;
    }
  }

  /// [小葵 2026-10-05 開案令] 認知傷口立案——「幻讀」進夢的正門。
  ///
  /// 跟工具傷口的差別：工具沒失敗（app_look 成功回傳 443KB PNG），
  /// 是「結論」錯了——宣稱看到了不存在的東西。這種病不留疤，
  /// 因為傷口系統只看工具成敗（Blue 10-05 開案：讓幻讀有資格進夢）。
  ///
  /// 訊號源：使用者糾正（AgentLoop.run 偵測糾正訊號後呼叫）。
  /// 痊癒條件（closeCognitiveWound）：下次同情境她主動說「我看不見/
  /// 我不確定」→ 誠實邊界 = 痊癒。與工具傷口共用 compass_pitfalls 表，
  /// 夢的三議程（銷案驗證/紅燈/深夢 corpus）自動帶上。
  int? fileCognitiveWound({
    required String symptom,
    String? source,
    String? toolHint,
  }) {
    try {
      final store = CompassStore.instance;
      const oid = 'agent.loop';
      // 去重：7 天內已有未結案認知傷口不重複立案
      // （認知病灶是「習慣」不是「事件」——一個未癒的幻讀習慣
      // 一晚只需要夢一次；重複立案會淹夢）
      final key = 'wound:cognitive';
      final last = store.getMeta(key);
      final now = DateTime.now();
      if (last != null) {
        try {
          final lastAt = DateTime.parse(jsonDecode(last)['at'] as String);
          if (now.difference(lastAt).inDays < 7) return null;
        } catch (_) {}
      }
      final symptomShort =
          symptom.length > 160 ? symptom.substring(0, 160) : symptom;
      final src = (source == null || source.isEmpty)
          ? ''
          : '（來源：${source.length > 60 ? source.substring(0, 60) : source}）';
      final hint = (toolHint == null || toolHint.isEmpty) ? '' : '[$toolHint] ';
      final text = '【pending·認知傷口】${hint}結論與事實不符：$symptomShort$src';
      store.addPitfall(oid, text, author: 'auto:medic');
      store.setMeta(key, jsonEncode({'at': now.toIso8601String()}));
      // 認知傷口進歷史主幹——歷史樹必須看見「她以為看到了」（否則
      // 戰後分析只能靠 conversations 重挖）
      try {
        CausalLedger.instance.record(CausalEntry(
          toolName: 'cognitive_wound',
          intervention: '認知傷口立案：$symptomShort',
          contextDigest: src.isEmpty ? hint : src,
          observedOutcome: '待夢境消化（議程 0 銷案驗證／深夢反思題材）',
          success: true,
          at: DateTime.now(),
        ));
      } catch (_) {}
      return 0; // 已立案
    } catch (_) {
      return null;
    }
  }

  /// 修復成功 → 自動草擬藥方（把 pending 案件升級為正式坑卡）。
  /// 藥方格式：症狀 → 病根 → 解法（來自失敗→成功的對照）。
  void closeWoundCase(String toolName, String howFixed) {
    try {
      final store = CompassStore.instance;
      final oid = _organForTool(toolName);
      if (oid == null) return;
      // 找該器官最新的 pending 案件
      final pits = store.pitfalls(oid);
      final pending = pits.where((p) => p.text.contains('【pending·傷口立案】') && p.text.contains(toolName));
      if (pending.isEmpty) return;
      final target = pending.first;
      final targetId = target.id;
      if (targetId == null) return;
      final fixed = howFixed.length > 200 ? howFixed.substring(0, 200) : howFixed;
      // 草擬藥方：追加到原條目（同一傷口的完整故事）
      final newText =
          '${target.text}\n【已自癒】解法：$fixed';
      store.replacePitfall(targetId, newText, author: 'auto:medic');
      // [小葵 2026-09-21 R2] 自癒事件寫入 causal_ledger——
      // 歷史主幹必須看見「傷口→長藥」，否則 K5 夢境議程少一源、
      // R4 儀表的藥效指標無料可用（fail-open，絕不影響主流程）。
      try {
        CausalLedger.instance.record(CausalEntry(
          toolName: 'compass_self_heal',
          intervention: '傷口自癒：$toolName（器官 $oid）',
          contextDigest: pending.isEmpty ? toolName : target.text.substring(0, target.text.length > 300 ? 300 : target.text.length),
          observedOutcome: '藥方入庫：${fixed.substring(0, fixed.length > 300 ? 300 : fixed.length)}',
          success: true,
          at: DateTime.now(),
        ));
      } catch (_) {}
    } catch (_) {}
  }

  /// [小葵 2026-10-05 開案令] 認知傷口銷案——誠實邊界 = 痊癒。
  ///
  /// 與工具傷口的「失敗→成功對照」不同：認知傷口痊癒的證據是
  /// **她主動說出看不見/不確定**（誠實邊界），由呼叫端在偵測到
  /// 誠實訊號時呼叫。痊癒不是「下次答對」——是「下次敢說不知道」。
  void closeCognitiveWound(String honestyEvidence, {String? toolHint}) {
    try {
      final store = CompassStore.instance;
      const oid = 'agent.loop';
      final pits = store.pitfalls(oid);
      final pending = pits.where((p) =>
          p.text.contains('【pending·認知傷口】') &&
          !p.text.contains('【已自癒】') &&
          (toolHint == null || p.text.contains('[$toolHint]')));
      if (pending.isEmpty) return;
      final target = pending.first;
      final targetId = target.id;
      if (targetId == null) return;
      final ev = honestyEvidence.length > 200
          ? honestyEvidence.substring(0, 200)
          : honestyEvidence;
      final newText =
          '${target.text}\n【已自癒】誠實邊界出現，銷案：$ev';
      store.replacePitfall(targetId, newText, author: 'auto:medic');
      try {
        CausalLedger.instance.record(CausalEntry(
          toolName: 'compass_self_heal',
          intervention: '認知傷口自癒：誠實邊界（器官 $oid）',
          contextDigest: target.text.substring(0,
              target.text.length > 300 ? 300 : target.text.length),
          observedOutcome: '藥方入庫：$ev',
          success: true,
          at: DateTime.now(),
        ));
      } catch (_) {}
    } catch (_) {}
  }

  // ── 內部 ────────────────────────────────────────
  /// 工具 → 器官映射（咽喉點對照表）
  static String? _organForTool(String toolName) {
    if (toolName.startsWith('canvas_')) {
      if (toolName == 'canvas_send_chat' || toolName == 'canvas_capture') {
        return 'canvas.chat';
      }
      return 'canvas.engine';
    }
    switch (toolName) {
      case 'run_terminal':
      case 'read_source_file':
      case 'patch_source_file':
      case 'restart_app':
      case 'read_app_log':
        return 'agent.tools';
      case 'ui_navigate':
      case 'ui_get_state':
      case 'ui_inspect':
        return 'theme';
      case 'memory_search':
        return 'memory';
      case 'delegate_subagent':
      case 'delegate_batch':
        return 'collab.delegate';
      case 'compass_seek':
      case 'compass_read':
      case 'compass_propose':
        return 'agent.loop';
      default:
        return null;
    }
  }

  List<Map<String, dynamic>> _seek(String intent) {
    final store = CompassStore.instance;
    ensureIntentIndexSeeded(store); // 冪等（W1 已 seed 則跳過）
    final raw = store.getMeta('intent_index');
    if (raw == null) return const [];
    final idx = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final intentLower = intent.toLowerCase();
    final hits = <Map<String, dynamic>>[];
    for (final e in idx) {
      final kws = (e['kw'] as String).split('|');
      final n = kws
          .where((k) => k.isNotEmpty && intentLower.contains(k.toLowerCase()))
          .length;
      if (n > 0) hits.add(e);
    }
    hits.sort((a, b) => _score(b, intentLower).compareTo(_score(a, intentLower)));
    return hits;
  }

  int _score(Map<String, dynamic> e, String intentLower) {
    final kws = (e['kw'] as String).split('|');
    return kws
        .where((k) => k.isNotEmpty && intentLower.contains(k.toLowerCase()))
        .length;
  }

  List<String> _pitfallsForTool(String toolName) {
    try {
      final oid = _organForTool(toolName);
      if (oid == null) return const [];
      return CompassStore.instance
          .pitfalls(oid)
          .where((p) => !p.text.contains('【pending'))
          .map((p) => p.text)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
