// [小葵 2026-09-21] R1——生命樹雙主幹資料層
//
// Blue 2026-09-20 設計（已入 ledger）、2026-09-21 拍板動刀：
//   生命樹 = 夢境主幹 ⊕ 歷史主幹（雙幹合體）
//   夢境主幹：主枝幹=與使用者討論後結論(human_consensus)、
//             子枝幹=agents(≥2)討論後結論(agent_consensus)
//   歷史主幹：主枝幹=agent_causal_ledger 既有執行記錄、
//             子枝幹=agent 想過但未走的分支(thought_branch)
//
// 本檔是唯一寫入口（單一咽喉點模式，同 gate 家族）。
// 使用 package:sqlite3（與 BrainDatabase 同款同步 API）。
// 真相源：~/Library/Application Support/bridge_app/causal_ledger.db

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:sqlite3/sqlite3.dart';

/// 夢境主幹的結論卡
class LifeTreeDream {
  final int? id;
  final String? dreamSessionId;
  final String branchType; // human_consensus / agent_consensus
  final String conclusion;
  final String decision; // maintain / propose / escalate_to_user
  final List<String> sourceClues; // 議程線索（K1錯題/W4新藥/儀表紅燈）
  final List<String> companionIds;
  final String? modelUsed;
  final DateTime createdAt;
  final int? linkedLedgerId;
  // [小葵 2026-10-05 Blue 令] 裁決——propose 卡使用者直接在卡上回覆
  final DateTime? adjudicatedAt;
  final String? adjudication;

  const LifeTreeDream({
    this.id,
    this.dreamSessionId,
    required this.branchType,
    required this.conclusion,
    required this.decision,
    this.sourceClues = const [],
    this.companionIds = const [],
    this.modelUsed,
    required this.createdAt,
    this.linkedLedgerId,
    this.adjudicatedAt,
    this.adjudication,
  });
}

/// 歷史主幹的未走分支（「遺憾」——agent 想過但沒走的路）
class LifeTreeThoughtBranch {
  final int? id;
  final int ledgerId; // 源自哪筆執行記錄
  final String thought;
  final String? whyNotTaken;
  final DateTime createdAt;
  final DateTime? revisitedAt; // 夢境重評後填
  final String? revisitVerdict; // still_valid / superseded / worth_taking

  const LifeTreeThoughtBranch({
    this.id,
    required this.ledgerId,
    required this.thought,
    this.whyNotTaken,
    required this.createdAt,
    this.revisitedAt,
    this.revisitVerdict,
  });
}

/// 生命樹資料層——唯一寫入口
class LifeTreeStore {
  LifeTreeStore._();
  static final LifeTreeStore instance = LifeTreeStore._();

  // [小葵 2026-09-21 抓包修正] 測試路徑注入——測試曾因無法覆寫 HOME
  // 環境變數，直接把測試卡寫進真 causal_ledger.db（已清）。
  // 正解：測試用 override 指到暫存 DB，絕不碰真庫。
  @visibleForTesting
  static String? dbPathOverride;

  Database? _db;

  Database _open() {
    if (_db != null) return _db!;
    final String path;
    if (dbPathOverride != null) {
      path = dbPathOverride!; // 測試注入——絕不碰真庫
    } else {
      final home = Platform.environment['HOME'] ?? '.';
      // 權威路徑：bridge_app（與 agent_causal_ledger 既有寫入者一致）
      path = '$home/Library/Application Support/bridge_app/causal_ledger.db';
      // fallback：farm 變體路徑（若權威不存在且 farm 存在）
      // 注意：兩者皆可能不存在（全新機）——_ensureTables 會建表
    }
    _db = sqlite3.open(path);
    _ensureTables(_db!);
    return _db!;
  }

  void _ensureTables(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS life_tree_dreams (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dream_session_id TEXT,
        trunk TEXT NOT NULL DEFAULT 'dream',
        branch_type TEXT NOT NULL,
        conclusion TEXT NOT NULL,
        decision TEXT NOT NULL,
        source_clues TEXT,
        companion_ids TEXT,
        model_used TEXT,
        created_at TEXT NOT NULL,
        linked_ledger_id INTEGER
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS life_tree_thought_branches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ledger_id INTEGER NOT NULL,
        thought TEXT NOT NULL,
        why_not_taken TEXT,
        revisited_at TEXT,
        revisit_verdict TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (ledger_id) REFERENCES agent_causal_ledger(id)
      )
    ''');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_dream_trunk ON life_tree_dreams(trunk, branch_type)');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tb_ledger ON life_tree_thought_branches(ledger_id)');
    // [小葵 2026-10-05 Blue 令] 裁決欄——propose 卡讓使用者直接在卡上回覆。
    // ALTER 失敗=欄位已存在，靜默忽略（冪等遷移）。
    try {
      db.execute(
          'ALTER TABLE life_tree_dreams ADD COLUMN adjudicated_at TEXT');
      db.execute(
          'ALTER TABLE life_tree_dreams ADD COLUMN adjudication TEXT');
    } catch (_) {}
  }

  // ── 夢境主幹 ──────────────────────────────

  /// 寫入一張結論卡（fail-open：失敗留痕不擋任務）。回傳新 id（失敗 -1）。
  int addDream(LifeTreeDream dream) {
    try {
      final db = _open();
      db.execute(
        'INSERT INTO life_tree_dreams (dream_session_id, branch_type, conclusion, decision, source_clues, companion_ids, model_used, created_at, linked_ledger_id) VALUES (?,?,?,?,?,?,?,?,?)',
        [
          dream.dreamSessionId,
          dream.branchType,
          dream.conclusion,
          dream.decision,
          jsonEncode(dream.sourceClues),
          jsonEncode(dream.companionIds),
          dream.modelUsed,
          dream.createdAt.toIso8601String(),
          dream.linkedLedgerId,
        ],
      );
      return db.lastInsertRowId;
    } catch (e) {
      debugPrint('[LifeTree] addDream 失敗（fail-open）: $e');
      return -1;
    }
  }

  /// 夢境主幹最近結論卡（K5 議程讀歷史用）
  List<LifeTreeDream> recentDreams({int limit = 20}) {
    try {
      final rows = _open().select(
          'SELECT * FROM life_tree_dreams ORDER BY created_at DESC LIMIT ?',
          [limit]);
      return rows.map(_dreamFromRow).toList();
    } catch (e) {
      debugPrint('[LifeTree] recentDreams 失敗: $e');
      return const [];
    }
  }

  LifeTreeDream _dreamFromRow(Row row) => LifeTreeDream(
        id: row['id'] as int?,
        dreamSessionId: row['dream_session_id'] as String?,
        branchType: row['branch_type'] as String,
        conclusion: row['conclusion'] as String,
        decision: row['decision'] as String,
        sourceClues: _decodeList(row['source_clues']),
        companionIds: _decodeList(row['companion_ids']),
        modelUsed: row['model_used'] as String?,
        createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        linkedLedgerId: row['linked_ledger_id'] as int?,
        adjudicatedAt: row['adjudicated_at'] == null
            ? null
            : DateTime.tryParse(row['adjudicated_at'] as String),
        adjudication: row['adjudication'] as String?,
      );

  // ── 歷史主幹：未走分支 ──────────────────────

  /// 記下「agent 想過但未走的分支」。回傳新 id（失敗 -1）。
  int addThoughtBranch(LifeTreeThoughtBranch b) {
    try {
      final db = _open();
      db.execute(
        'INSERT INTO life_tree_thought_branches (ledger_id, thought, why_not_taken, created_at) VALUES (?,?,?,?)',
        [b.ledgerId, b.thought, b.whyNotTaken, b.createdAt.toIso8601String()],
      );
      return db.lastInsertRowId;
    } catch (e) {
      debugPrint('[LifeTree] addThoughtBranch 失敗（fail-open）: $e');
      return -1;
    }
  }

  /// 夢境重評：標記某未走分支的重訪結論（K5「重走沒走的路」）。回傳影響列數。
  int markRevisited(int branchId, String verdict) {
    try {
      final db = _open();
      db.execute(
        'UPDATE life_tree_thought_branches SET revisited_at = ?, revisit_verdict = ? WHERE id = ?',
        [DateTime.now().toIso8601String(), verdict, branchId],
      );
      // sqlite3 package 的 execute 不回列數——用 select 驗證已更新
      final row = db.select(
          'SELECT revisit_verdict FROM life_tree_thought_branches WHERE id = ?',
          [branchId]);
      return row.isNotEmpty && row.first['revisit_verdict'] == verdict ? 1 : 0;
    } catch (e) {
      debugPrint('[LifeTree] markRevisited 失敗: $e');
      return 0;
    }
  }

  /// 尚未被夢境重評的未走分支（K5 議程素材——「遺憾清單」）
  List<LifeTreeThoughtBranch> unrevisitedBranches({int limit = 10}) {
    try {
      final rows = _open().select(
          'SELECT * FROM life_tree_thought_branches WHERE revisited_at IS NULL ORDER BY created_at DESC LIMIT ?',
          [limit]);
      return rows.map(_tbFromRow).toList();
    } catch (e) {
      debugPrint('[LifeTree] unrevisitedBranches 失敗: $e');
      return const [];
    }
  }

  LifeTreeThoughtBranch _tbFromRow(Row row) => LifeTreeThoughtBranch(
        id: row['id'] as int?,
        ledgerId: row['ledger_id'] as int,
        thought: row['thought'] as String,
        whyNotTaken: row['why_not_taken'] as String?,
        createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        revisitedAt: row['revisited_at'] == null
            ? null
            : DateTime.tryParse(row['revisited_at'] as String),
        revisitVerdict: row['revisit_verdict'] as String?,
      );

  List<String> _decodeList(dynamic raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  /// 健康快照（R4 儀表用）：兩主幹規模
  Map<String, int> snapshot() {
    try {
      final db = _open();
      final d =
          db.select('SELECT COUNT(*) c FROM life_tree_dreams').first['c'] as int;
      final t = db
          .select('SELECT COUNT(*) c FROM life_tree_thought_branches')
          .first['c'] as int;
      final u = db
          .select(
              'SELECT COUNT(*) c FROM life_tree_thought_branches WHERE revisited_at IS NULL')
          .first['c'] as int;
      return {'dreams': d, 'thoughtBranches': t, 'unrevisited': u};
    } catch (e) {
      debugPrint('[LifeTree] snapshot 失敗: $e');
      return {'dreams': -1, 'thoughtBranches': -1, 'unrevisited': -1};
    }
  }

  // ── 夢的藥回灌（2026-10-05 生命樹代謝）──────────────
  //
  // 洞二的修法：夢卡不再是只寫不讀的日記。她每次開工（AgentLoop
  // 組 prompt）時帶上「最近的、夠新的夢結論」——昨晚學到的教訓，
  // 白天就帶在身上。設計原則（生命樹自己長）：
  //   - 不欽點內容：按 decision 種類+新鮮度檢索，不是我們挑過的 SOP
  //   - 藥有效期限：7 天——過期的教訓會變迷信，自動退成純歷史
  //   - 上限 3 張：養分是提神不是灌爆 prompt

  /// 最近 N 天內、仍有效的夢結論卡（回灌候選）。
  /// 排除：安睡卡（無資訊量）、propose 卡還沒人裁決（不是藥是議題）。
  List<LifeTreeDream> activeLessons({int days = 7, int limit = 3}) {
    try {
      final cutoff =
          DateTime.now().subtract(Duration(days: days)).toIso8601String();
      final rows = _open().select(
        'SELECT * FROM life_tree_dreams '
        'WHERE created_at > ? '
        "AND conclusion NOT LIKE '這場夢沒有發現問題%' "
        "AND (decision IN ('maintain','escalate_to_user','agent_consensus') "
        "     OR (decision = 'propose' AND adjudicated_at IS NOT NULL)) "
        // 同結論去重——傷口銷案卡常常連發，留最新一張
        'GROUP BY substr(conclusion, 1, 40) '
        'ORDER BY created_at DESC LIMIT ?',
        [cutoff, limit],
      );
      return rows.map(_dreamFromRow).toList();
    } catch (e) {
      debugPrint('[LifeTree] activeLessons 失敗: $e');
      return const [];
    }
  }

  /// [小葵 2026-10-05 Blue 令] 裁決 propose 卡——使用者直接在卡上回覆。
  /// 寫入裁決文字＋時間戳；回傳成功與否。
  /// 訊息送達 Agent 夥伴由 UI 層負責（本方法只管樹的帳）。
  bool adjudicate(int dreamId, String verdict) {
    try {
      final db = _open();
      db.execute(
        'UPDATE life_tree_dreams SET adjudicated_at = ?, adjudication = ? '
        'WHERE id = ?',
        [DateTime.now().toIso8601String(), verdict, dreamId],
      );
      final row = db.select(
          'SELECT adjudication FROM life_tree_dreams WHERE id = ?', [dreamId]);
      return row.isNotEmpty && row.first['adjudication'] == verdict;
    } catch (e) {
      debugPrint('[LifeTree] adjudicate 失敗: $e');
      return false;
    }
  }

  /// [代謝·洞三] 草稿卡升級：被回灌引用過的 agent_draft 升級
  /// agent_consensus——「夢裡悟的藥，白天真的用了」就是複驗通過。
  /// 純 SQL 零 token；升級留痕在結論前綴（不覆寫原文）。
  int promoteDraftsReferenced(List<int> dreamIds) {
    if (dreamIds.isEmpty) return 0;
    var n = 0;
    try {
      final db = _open();
      for (final id in dreamIds) {
        // 先查現況——已是 consensus 的冪等跳過（不算新升級）
        final cur = db.select(
            'SELECT branch_type FROM life_tree_dreams WHERE id = ?', [id]);
        if (cur.isEmpty || cur.first['branch_type'] != 'agent_draft') continue;
        db.execute(
          "UPDATE life_tree_dreams SET branch_type = 'agent_consensus', "
          "conclusion = '[已用於白天·升級] ' || conclusion, "
          "model_used = COALESCE(model_used, '') || '+reused' "
          'WHERE id = ? AND branch_type = ?',
          [id, 'agent_draft'],
        );
        final ok = db.select(
            "SELECT COUNT(*) c FROM life_tree_dreams WHERE id = ? AND branch_type = 'agent_consensus'",
            [id]);
        if ((ok.first['c'] as int) > 0) n++;
      }
      return n;
    } catch (e) {
      debugPrint('[LifeTree] promoteDraftsReferenced 失敗: $e');
      return n;
    }
  }

  void dispose() {
    _db?.close();
    _db = null;
  }
}
