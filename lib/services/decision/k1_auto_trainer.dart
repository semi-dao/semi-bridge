// k1_auto_trainer.dart
// [小葵 2026-10-19 殘件②] K1 自訓練觸發器——樣本累積 → 門檻 → 自動訓練。
//
// 病史：/k1/train HTTP 入口在（bridge_mcp_server:848）、訓練引導器在
// （k1_bootstrapper），但「樣本 ≥200 筆自動訓練」的觸發邏輯從未存在
// （Fable V3 殘件②）——頭永遠停留在最後一次手動訓練的樣本上。
//
// 資料流（單向，只讀兩本帳）：
//   causal_ledger.agent_causal_ledger（k1_gatekeeper 記帳：turn_id + 判斷）
//   × event_ledger（同 turn_id 的 user_reaction：accepted/corrected）
//   → 配對樣本（判斷 + 校準訊號）
//   → 累積 ≥ threshold 觸發 bootstrapFromLabels
//
// 樣本語意（保守側）：
//   - reaction='accepted' 且 K1 判 need → label=need（使用者沒糾正，判對）
//   - reaction='accepted' 且 K1 判 no   → label=no（同上）
//   - reaction='corrected' → 不進樣本（糾正的語意是「該輪有問題」，
//     但問題可能在答案不在路由——寧缺勿濫，等糾正語意細化後再收）
//   - 無反應的輪 → 不進樣本（沒有校準訊號＝不知道判對判錯）
//
// 防重複訓練：訓練水位記在 compass_meta（k1_auto_train_watermark）——
// 只用「上次訓練後新增的配對樣本」計數，不會因為舊樣本反覆觸發。
// 單調升級守門在 bootstrapFromLabels 內建（LOO-CV + saveMonotonic），
// 觸發器只負責「該不該訓」，不負責「該不該掛」。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../compass/compass_store.dart';
import 'k1_bootstrapper.dart';

class K1AutoTrainer {
  K1AutoTrainer._();
  static final K1AutoTrainer instance = K1AutoTrainer._();

  /// 觸發門檻（Fable V3 / T5② 規格：≥200 配對）
  static const int triggerThreshold = 200;
  static const String _watermarkKey = 'k1_auto_train_watermark';

  String get _home => Platform.environment['HOME'] ?? '.';

  Database _openCausal() {
    var p = '$_home/Library/Application Support/bridge_app/causal_ledger.db';
    if (!File(p).existsSync()) {
      p = '$_home/Library/Application Support/'
          'farm.semiwasabi.bridgeApp/causal_ledger.db';
    }
    return sqlite3.open(p);
  }

  Database _openBrain() {
    // 陷阱 #58：bridge_app/ 目錄下的 brain_container.db 可能是 0-byte
    // 符號層；真庫在 farm 目錄（EventLedger 走 BrainDatabase 同源）。
    final p = '$_home/Library/Application Support/'
        'farm.semiwasabi.bridgeApp/brain_container.db';
    return sqlite3.open(p);
  }

  /// 掃描配對樣本。回傳 {paired, accepted, byLabel, newSinceWatermark}
  Map<String, dynamic> scanPairSamples() {
    final causal = _openCausal();
    final brain = _openBrain();
    try {
      return _scan(causal, brain);
    } finally {
      causal.close();
      brain.close();
    }
  }

  /// [殘件② test] 純掃描核心——測試注入 in-memory DB（絕不碰真庫）
  @visibleForTesting
  static Map<String, dynamic> scanPairSamplesForTest(
      Database causal, Database brain) {
    return _scan(causal, brain);
  }

  static Map<String, dynamic> _scan(Database causal, Database brain) {
    {
      // 1. 有反應的 turn（校準訊號）
      final reacted = <String, String>{};
      for (final row in brain.select(
          "SELECT ref_turn_id, user_reaction FROM event_ledger "
          "WHERE kind='reaction' AND ref_turn_id IS NOT NULL")) {
        reacted[row['ref_turn_id'] as String] = (row['user_reaction'] ?? '') as String;
      }
      // 2. K1 記帳配對
      final causalRows = causal.select(
          "SELECT turn_id, intervention FROM agent_causal_ledger "
          "WHERE tool_name='k1_gatekeeper' AND turn_id IS NOT NULL "
          "ORDER BY id");
      final byTurn = <String, String>{};
      for (final r in causalRows) {
        byTurn[r['turn_id'] as String] = (r['intervention'] ?? '') as String;
      }
      var accepted = 0;
      final byLabel = <String, int>{'need': 0, 'no': 0};
      for (final entry in reacted.entries) {
        if (entry.value != 'accepted') continue;
        final intervention = byTurn[entry.key];
        if (intervention == null) continue;
        final isNeed = intervention.contains('need_memory_lookup');
        byLabel[isNeed ? 'need' : 'no'] =
            (byLabel[isNeed ? 'need' : 'no'] ?? 0) + 1;
        accepted++;
      }
      // 3. 水位
      var watermark = 0;
      try {
        final w = CompassStore.instance.getMeta(_watermarkKey);
        watermark = w == null ? 0 : int.tryParse(w) ?? 0;
      } catch (_) {}
      return {
        'paired': reacted.length,
        'accepted': accepted,
        'by_label': byLabel,
        'new_since_watermark': accepted - watermark > 0
            ? accepted - watermark
            : 0,
        'watermark': watermark,
      };
    }
  }

  /// 觸發檢查（App 啟動時呼叫一次；冪等——不到門檻零動作）。
  /// 回傳 null=未觸發；Map=訓練報告（bootstrapFromLabels 的回傳）。
  Future<Map<String, dynamic>?> maybeTrain() async {
    try {
      final scan = scanPairSamples();
      final fresh = scan['new_since_watermark'] as int;
      debugPrint('[K1AutoTrainer] 配對 ${scan['paired']}、'
          '可用樣本 ${scan['accepted']}（水位後新增 $fresh）');
      if (fresh < triggerThreshold) return null;

      // 4. 組標註 JSONL：從配對樣本抽 text（context_digest 的
      // 「使用者最新訊息：」行之後）+ label
      final labelsJson = _buildLabelsJsonl();
      if (labelsJson == null) {
        debugPrint('[K1AutoTrainer] 標註組建失敗——跳過本輪觸發');
        return null;
      }
      final report = await K1Bootstrapper.instance
          .bootstrapFromLabels(labelsJson);
      // 5. 成功才推進水位（失敗下輪再試）
      if (report['ok'] == true) {
        CompassStore.instance
            .setMeta(_watermarkKey, '${scan['accepted']}');
        debugPrint('[K1AutoTrainer] ✅ 自動訓練完成：$report');
      } else {
        debugPrint('[K1AutoTrainer] 訓練未過門檻（單調守門拒絕）：$report');
      }
      return report;
    } catch (e) {
      debugPrint('[K1AutoTrainer] 檢查失敗（fail-quiet）: $e');
      return null;
    }
  }

  /// 從配對樣本組訓練標註（text=使用者訊息、label=need/no）
  String? _buildLabelsJsonl() {
    final causal = _openCausal();
    final brain = _openBrain();
    try {
      return buildLabelsJsonlForTest(causal, brain);
    } finally {
      causal.close();
      brain.close();
    }
  }

  /// [殘件② test] 純組建核心——測試注入 in-memory DB
  @visibleForTesting
  static String? buildLabelsJsonlForTest(Database causal, Database brain) {
    {
      final reacted = <String, String>{};
      for (final row in brain.select(
          "SELECT ref_turn_id, user_reaction FROM event_ledger "
          "WHERE kind='reaction' AND ref_turn_id IS NOT NULL")) {
        reacted[row['ref_turn_id'] as String] = (row['user_reaction'] ?? '') as String;
      }
      final buf = StringBuffer();
      var n = 0;
      for (final row in causal.select(
          "SELECT turn_id, intervention, context_digest FROM "
          "agent_causal_ledger WHERE tool_name='k1_gatekeeper' "
          "AND turn_id IS NOT NULL ORDER BY id")) {
        final tid = row['turn_id'] as String;
        final reaction = reacted[tid];
        if (reaction != 'accepted') continue; // 只收 accepted
        final intervention = (row['intervention'] ?? '') as String;
        final digest = (row['context_digest'] ?? '') as String;
        // 抽「使用者最新訊息：」之後的文本當訓練 text
        final m = RegExp('使用者最新訊息：(.*)', multiLine: false)
            .firstMatch(digest);
        if (m == null) continue;
        final text = m.group(1)!.trim();
        if (text.isEmpty || text.length > 500) continue;
        final label =
            intervention.contains('need_memory_lookup') ? 'need' : 'no';
        buf.writeln(jsonEncode({'text': text, 'label': label}));
        n++;
      }
      return n >= 20 ? buf.toString() : null;
    }
  }
}
