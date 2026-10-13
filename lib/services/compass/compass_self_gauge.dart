// [小葵 2026-09-21] R4——compass.self 儀表服務（K1＋W4 指標合體）
//
// 統一迴路 R4：W5 健康儀表＋K4 精靈複驗 合體為一個觀察者。
// 資料源全部是既有真實數據（causal_ledger＋compass_store＋life_tree），
// 零新增埋點——儀表是「讀者」不是「寫者」。
// 紅燈定義：任何指標越線 → 紅燈清單 → R5 夢境議程（精靈線索）。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// compass.self 儀表快照
class CompassSelfMetrics {
  final int k1Judgments; // K1 判斷總數
  final int k1Need; // 判 need 次數
  final int k1Escalated; // escalate 次數
  final double k1EscalateRate; // escalate 率
  final int k1RuleShare; // 規則層分擔率（%）
  final int selfHeals; // W4 自癒事件數
  final int pendingWounds; // 未結案傷口數
  final int cognitiveWounds; // 未結案認知傷口數（幻讀族——結論與事實不符）
  final int medicines; // 活規則數
  final int pitfalls; // 坑卡數
  final double coverage; // 器官覆蓋率（0-1）
  final int dreams; // 生命樹夢境結論卡數
  final int unrevisited; // 遺憾清單長度
  final DateTime computedAt;

  const CompassSelfMetrics({
    required this.k1Judgments,
    required this.k1Need,
    required this.k1Escalated,
    required this.k1EscalateRate,
    required this.k1RuleShare,
    required this.selfHeals,
    required this.pendingWounds,
    required this.cognitiveWounds,
    required this.medicines,
    required this.pitfalls,
    required this.coverage,
    required this.dreams,
    required this.unrevisited,
    required this.computedAt,
  });

  /// 紅燈清單（R5 夢境議程線索；空=無紅燈）
  List<String> redFlags() {
    final flags = <String>[];
    // escalate 率過高 → K1 沒在做事（全丟給 LLM）
    if (k1Judgments >= 10 && k1EscalateRate > 0.5) {
      flags.add('K1 escalate 率 ${(k1EscalateRate * 100).toStringAsFixed(0)}% 過高（>${50}%）——頭沒訓練或規則層覆蓋不足');
    }
    // 傷口堆積 → W4 出了口沒進口
    if (pendingWounds >= 5) {
      flags.add('未結案傷口 $pendingWounds 筆堆積——同工具反覆撞牆沒長出藥');
    }
    // [小葵 2026-10-05 開案令] 認知傷口——幻讀進夢的正門。
    // 有任何未結案認知傷口就是紅燈：這種病（成功地錯了）不會
    // 自動好，要夢裡消化成「誠實邊界」的藥。
    if (cognitiveWounds > 0) {
      flags.add('認知傷口 $cognitiveWounds 筆未結案——結論與事實不符'
          '（宣稱看到沒有的東西），痊癒條件=主動說出看不見');
    }
    // 覆蓋率太低 → 裸奔器官多
    if (coverage < 0.5 && medicines > 0) {
      flags.add('器官覆蓋率 ${(coverage * 100).toStringAsFixed(0)}% 偏低（<50%）');
    }
    // 遺憾清單太長 → 夢境欠帳
    if (unrevisited >= 10) {
      flags.add('遺憾清單 $unrevisited 條未重評——夢境議程積壓');
    }
    return flags;
  }

  Map<String, dynamic> toJson() => {
        'k1_judgments': k1Judgments,
        'k1_need': k1Need,
        'k1_escalated': k1Escalated,
        'k1_escalate_rate': k1EscalateRate,
        'k1_rule_share': k1RuleShare,
        'self_heals': selfHeals,
        'pending_wounds': pendingWounds,
        'medicines': medicines,
        'pitfalls': pitfalls,
        'coverage': coverage,
        'dreams': dreams,
        'unrevisited': unrevisited,
        'computed_at': computedAt.toIso8601String(),
      };
}

/// compass.self 儀表——只讀不寫（寫者是 K1/W4/LifeTree 各自的管線）
class CompassSelfGauge {
  CompassSelfGauge._();
  static final CompassSelfGauge instance = CompassSelfGauge._();

  // 保留：未來若 DB 搬家，可在啟動時 override 路徑（現在用預設解析鏈）
  // ignore: unused_field
  String? _ledgerPath;
  // ignore: unused_field
  String? _compassPath;

  void configure({String? ledgerPath, String? compassPath}) {
    _ledgerPath = ledgerPath;
    _compassPath = compassPath;
  }

  String get _home => Platform.environment['HOME'] ?? '.';

  Database _open(String base, String file) {
    final home = _home;
    var p = '$home/Library/Application Support/$base/$file';
    if (!File(p).existsSync()) {
      p = '$home/Library/Application Support/farm.semiwasabi.bridgeApp/$file';
    }
    return sqlite3.open(p);
  }

  /// 計算當前快照（fail-open：任一源失敗給 0，不炸）
  CompassSelfMetrics compute() {
    final now = DateTime.now();
    try {
      final ledger = _open('bridge_app', 'causal_ledger.db');
      try {
        final k1Total = _count(ledger,
            "SELECT COUNT(*) FROM agent_causal_ledger WHERE tool_name='k1_gatekeeper'");
        final k1Need = _count(ledger,
            "SELECT COUNT(*) FROM agent_causal_ledger WHERE tool_name='k1_gatekeeper' AND intervention LIKE '%need%'");
        final k1Esc = _count(ledger,
            "SELECT COUNT(*) FROM agent_causal_ledger WHERE tool_name='k1_gatekeeper' AND intervention LIKE '%escalate%'");
        final k1Rule = _count(ledger,
            "SELECT COUNT(*) FROM agent_causal_ledger WHERE tool_name='k1_gatekeeper' AND intervention LIKE '%source=rule%'");
        final heals = _count(ledger,
            "SELECT COUNT(*) FROM agent_causal_ledger WHERE tool_name='compass_self_heal'");
        final dreams = _count(ledger,
            'SELECT COUNT(*) FROM life_tree_dreams');
        final unrev = _count(ledger,
            'SELECT COUNT(*) FROM life_tree_thought_branches WHERE revisited_at IS NULL');
        final escRate = k1Total > 0 ? k1Esc / k1Total : 0.0;
        final ruleShare =
            k1Total > 0 ? (k1Rule * 100 / k1Total).round() : 0;

        var pending = 0, meds = 0, pits = 0, cogWounds = 0;
        double cov = 0;
        try {
          final compass = _open('bridge_app', 'compass_store.db');
          try {
            pending = _count(compass,
                "SELECT COUNT(*) FROM compass_pitfalls WHERE text LIKE '%【pending·傷口立案】%' AND text NOT LIKE '%【已自癒】%' AND text NOT LIKE '%【夢境銷案%'");
            // [小葵 2026-10-05 開案令] 認知傷口計數（幻讀族——與工具傷口分開算）
            cogWounds = _count(compass,
                "SELECT COUNT(*) FROM compass_pitfalls WHERE text LIKE '%【pending·認知傷口】%' AND text NOT LIKE '%【已自癒】%' AND text NOT LIKE '%【夢境銷案%'");
            meds = _count(compass,
                "SELECT COUNT(*) FROM compass_rules WHERE status='active'");
            pits = _count(compass, 'SELECT COUNT(*) FROM compass_pitfalls');
            final total = _count(compass,
                'SELECT COUNT(*) FROM compass_organs');
            // [小葵 2026-09-21 抓包] canvas.schedule 有規則但不在 organs
            // 表（幽靈器官）→ 分母沒它、分子有它 → 102%。
            // 分子限縮為 organs 表內的器官。
            final withRule = _count(compass,
                "SELECT COUNT(DISTINCT r.organ_id) FROM compass_rules r JOIN compass_organs o ON o.id = r.organ_id WHERE r.status='active'");
            cov = total > 0 ? withRule / total : 0.0;
          } finally {
            compass.close();
          }
        } catch (e) {
          debugPrint('[CompassSelf] compass 源失敗（給 0 不炸）: $e');
        }

        return CompassSelfMetrics(
          k1Judgments: k1Total,
          k1Need: k1Need,
          k1Escalated: k1Esc,
          k1EscalateRate: escRate,
          k1RuleShare: ruleShare,
          selfHeals: heals,
          pendingWounds: pending,
          cognitiveWounds: cogWounds,
          medicines: meds,
          pitfalls: pits,
          coverage: cov,
          dreams: dreams,
          unrevisited: unrev,
          computedAt: now,
        );
      } finally {
        ledger.close();
      }
    } catch (e) {
      debugPrint('[CompassSelf] compute 失敗: $e');
      return CompassSelfMetrics(
        k1Judgments: 0, k1Need: 0, k1Escalated: 0, k1EscalateRate: 0,
        k1RuleShare: 0, selfHeals: 0, pendingWounds: 0, cognitiveWounds: 0,
        medicines: 0, pitfalls: 0, coverage: 0, dreams: 0, unrevisited: 0,
        computedAt: now,
      );
    }
  }

  int _count(Database db, String sql) {
    try {
      final r = db.select(sql);
      return r.isNotEmpty ? (r.first.values.first as int? ?? 0) : 0;
    } catch (_) {
      return 0;
    }
  }

  /// 儀表文字版（compass_read 讀 compass.self 器官時的內容；R5 議程也用它）
  String briefing(CompassSelfMetrics m) {
    final buf = StringBuffer();
    buf.writeln('## compass.self 儀表（${m.computedAt.toIso8601String().substring(0, 16)}）');
    buf.writeln();
    buf.writeln('**K1 守門員**');
    buf.writeln('- 判斷數：${m.k1Judgments}（need=${m.k1Need}／escalate=${m.k1Escalated}）');
    buf.writeln('- escalate 率：${(m.k1EscalateRate * 100).toStringAsFixed(0)}%｜規則層分擔：${m.k1RuleShare}%');
    buf.writeln();
    buf.writeln('**W4 傷口自癒**');
    buf.writeln('- 已長藥：${m.selfHeals}｜未結案傷口：${m.pendingWounds}');
    buf.writeln();
    buf.writeln('**藥箱**');
    buf.writeln('- 活規則 ${m.medicines} 條｜坑卡 ${m.pitfalls} 張｜覆蓋率 ${(m.coverage * 100).toStringAsFixed(0)}%');
    buf.writeln();
    buf.writeln('**生命樹**');
    buf.writeln('- 夢境結論卡 ${m.dreams} 張｜遺憾清單 ${m.unrevisited} 條');
    final flags = m.redFlags();
    if (flags.isNotEmpty) {
      buf.writeln();
      buf.writeln('⚠️ 紅燈（${flags.length}）');
      for (final f in flags) {
        buf.writeln('- $f');
      }
    } else {
      buf.writeln();
      buf.writeln('✅ 無紅燈');
    }
    return buf.toString();
  }

  /// JSON 字串（寫入 compass_meta 給前端/agent 讀）
  String metricsJson(CompassSelfMetrics m) => jsonEncode(m.toJson());
}
