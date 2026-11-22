// decision_card_store.dart
// [小葵 2026-11-03 Blue 拍板 B 案] 待決策卡閉環——主動回應從「斷頭線」
// 變成「討論完 → 拍板 → 執行 → 結案」的閉環。
// Spec: docs/specs/2026-11-03-decision-card-loop.md
//
// 病例（2026-11-03）：同三面紅旗 10/29–11/3 每天重報（紅旗無生命週期）；
// 4 秒內開 3 個 proactive session（三路搶閘 race）。本 store 是治本：
// 卡片本身就是去重真相源——開卡走 SQLite 事務（同類未結案卡存在即拒開），
// 天然原子，比修 compass_meta 讀→判→寫的搶閘更根本。
//
// DB 慣例照 compass_store.dart：sqlite3 直開 + WAL + synchronous=NORMAL。
// 表放同一顆 compass_store.db（羅盤體系真相源單一）。

import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'compass_store.dart';

/// 決策選項（agent 給使用者的 2-3 個方向）
class DecisionOption {
  final String id; // opt_1 / opt_2 / opt_3
  final String label; // 一行標籤
  final String detail; // 展開說明（做什麼、代價、風險）
  final bool recommended; // agent 建議標記
  const DecisionOption({
    required this.id,
    required this.label,
    required this.detail,
    this.recommended = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'detail': detail,
        'recommended': recommended,
      };

  static DecisionOption fromJson(Map<String, dynamic> j) => DecisionOption(
        id: j['id'] as String,
        label: j['label'] as String,
        detail: j['detail'] as String? ?? '',
        recommended: j['recommended'] as bool? ?? false,
      );
}

/// 待決策卡
class DecisionCard {
  final String id; // dc_<epoch_ms>
  final String title;
  final String body;
  final String categoryKey; // 紅旗類別鍵（redFlagCategoryKey 同款）——同類歸一
  final String status; // open/discussing/awaiting_decision/executing/done/dismissed
  final List<DecisionOption> options;
  final String? chosenOptionId;
  final String? conversationId; // 開話的 proactive session
  final String source; // daytime_heartbeat / dream / manual / timeout_rescue
  final String openedAt;
  final String? decidedAt;
  final String? closedAt;
  final String? closeReason; // resolved / dismissed / expired

  const DecisionCard({
    required this.id,
    required this.title,
    required this.body,
    required this.categoryKey,
    required this.status,
    this.options = const [],
    this.chosenOptionId,
    this.conversationId,
    required this.source,
    required this.openedAt,
    this.decidedAt,
    this.closedAt,
    this.closeReason,
  });

  /// 未結案（尚需使用者注意的卡）
  bool get isUnresolved =>
      status == 'open' ||
      status == 'discussing' ||
      status == 'awaiting_decision' ||
      status == 'executing';

  Map<String, dynamic> toRow() => {
        'id': id,
        'title': title,
        'body': body,
        'category_key': categoryKey,
        'status': status,
        'options_json': jsonEncode([for (final o in options) o.toJson()]),
        'chosen_option_id': chosenOptionId,
        'conversation_id': conversationId,
        'source': source,
        'opened_at': openedAt,
        'decided_at': decidedAt,
        'closed_at': closedAt,
        'close_reason': closeReason,
      };

  static DecisionCard fromRow(Map<String, dynamic> r) {
    List<DecisionOption> opts = [];
    final oj = r['options_json'] as String?;
    if (oj != null && oj.isNotEmpty && oj != '[]') {
      try {
        opts = [
          for (final e in jsonDecode(oj) as List)
            DecisionOption.fromJson(e as Map<String, dynamic>)
        ];
      } catch (_) {} // 壞 json 不炸整張卡
    }
    return DecisionCard(
      id: r['id'] as String,
      title: r['title'] as String,
      body: r['body'] as String? ?? '',
      categoryKey: r['category_key'] as String,
      status: r['status'] as String,
      options: opts,
      chosenOptionId: r['chosen_option_id'] as String?,
      conversationId: r['conversation_id'] as String?,
      source: r['source'] as String? ?? 'manual',
      openedAt: r['opened_at'] as String,
      decidedAt: r['decided_at'] as String?,
      closedAt: r['closed_at'] as String?,
      closeReason: r['close_reason'] as String?,
    );
  }

  DecisionCard copyWith({
    String? status,
    List<DecisionOption>? options,
    String? chosenOptionId,
    String? conversationId,
    String? decidedAt,
    String? closedAt,
    String? closeReason,
    String? body,
  }) =>
      DecisionCard(
        id: id,
        title: title,
        body: body ?? this.body,
        categoryKey: categoryKey,
        status: status ?? this.status,
        options: options ?? this.options,
        chosenOptionId: chosenOptionId ?? this.chosenOptionId,
        conversationId: conversationId ?? this.conversationId,
        source: source,
        openedAt: openedAt,
        decidedAt: decidedAt ?? this.decidedAt,
        closedAt: closedAt ?? this.closedAt,
        closeReason: closeReason ?? this.closeReason,
      );
}

class DecisionCardStore {
  DecisionCardStore._();
  static final DecisionCardStore instance = DecisionCardStore._();

  Database? _db;
  int _idSeq = 0; // [test 抓包] 同毫秒開卡序號——保 dc_id 唯一

  /// 初始化（冪等）。接 CompassStore 的 db（同顆 compass_store.db）。
  /// 獨立 initialize：CompassStore 還沒開時自己開（fail-open 不擋主流程）。
  Future<void> initialize({String? dbPath}) async {
    if (_db != null) return;
    final path = dbPath ?? await CompassStore.defaultDbPath();
    _db = sqlite3.open(path);
    _db!.execute('PRAGMA journal_mode = WAL');
    _db!.execute('PRAGMA synchronous = NORMAL');
    _migrate();
  }

  /// 測試隔離——每個測試 setUp 換乾淨 db（雙 singleton 注入鐵律近親）。
  @visibleForTesting
  Future<void> reopenForTest(String dbPath) async {
    _db?.close();
    _db = sqlite3.open(dbPath);
    _db!.execute('PRAGMA journal_mode = WAL');
    _db!.execute('PRAGMA synchronous = NORMAL');
    _migrate();
  }

  void _migrate() {
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS decision_cards (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '',
        category_key TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'open',
        options_json TEXT NOT NULL DEFAULT '[]',
        chosen_option_id TEXT,
        conversation_id TEXT,
        source TEXT NOT NULL DEFAULT 'manual',
        opened_at TEXT NOT NULL,
        decided_at TEXT,
        closed_at TEXT,
        close_reason TEXT
      )
    ''');
    _db!.execute('''
      CREATE INDEX IF NOT EXISTS idx_decision_cards_category_status
        ON decision_cards(category_key, status)
    ''');
  }

  // ── 核心：原子開卡（治三連發）────────────────────────────
  //
  // SELECT + INSERT 包在同一個 IMMEDIATE 交易：三條觸發路同時進來，
  // 第一個拿到寫鎖的開卡，其餘 SELECT 到未結案卡 → 拒開。SQLite 交易
  // 保證序列化——這是跟 compass_meta 讀→判→寫三步搶閘的根本差異。

  /// 原子開卡。同 categoryKey 已有未結案卡 → 回傳 null（靜默不重開）。
  /// 回傳卡片＝開卡成功。
  DecisionCard? tryOpenCard({
    required String title,
    required String body,
    required String categoryKey,
    String source = 'manual',
    String? conversationId,
  }) {
    final db = _db;
    if (db == null) return null;
    // [test 抓包 2026-11-03] 同毫秒開兩卡 → dc_<ms> 主鍵碰撞 → 交易回滾。
    // id 加微秒＋序號保唯一（nc = nanosecond-ish counter）。
    _idSeq = (_idSeq + 1) % 1000000;
    final now = DateTime.now();
    final card = DecisionCard(
      id:
          'dc_${now.millisecondsSinceEpoch}_${now.microsecond}_$_idSeq',
      title: title,
      body: body,
      categoryKey: categoryKey,
      status: 'open',
      source: source,
      conversationId: conversationId,
      openedAt: now.toIso8601String(),
    );
    try {
      db.execute('BEGIN IMMEDIATE');
      final existing = db.select(
        "SELECT id FROM decision_cards WHERE category_key = ? "
        "AND status IN ('open','discussing','awaiting_decision','executing') "
        "LIMIT 1",
        [categoryKey],
      );
      if (existing.isNotEmpty) {
        db.execute('ROLLBACK');
        return null; // 同類已有未結案卡——不重開（治每天重報）
      }
      final r = card.toRow();
      db.execute(
        'INSERT INTO decision_cards (id, title, body, category_key, status, '
        'options_json, chosen_option_id, conversation_id, source, opened_at, '
        'decided_at, closed_at, close_reason) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          r['id'], r['title'], r['body'], r['category_key'], r['status'],
          r['options_json'], r['chosen_option_id'], r['conversation_id'],
          r['source'], r['opened_at'], r['decided_at'], r['closed_at'],
          r['close_reason'],
        ],
      );
      db.execute('COMMIT');
      return card;
    } catch (_) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {}
      return null; // fail-quiet：開卡失敗不擋主動回報主流程
    }
  }

  // ── 讀取 ──────────────────────────────────────────────

  /// 未結案卡（等使用者注意的）
  List<DecisionCard> unresolvedCards() {
    final db = _db;
    if (db == null) return [];
    try {
      final rows = db.select(
        "SELECT * FROM decision_cards "
        "WHERE status IN ('open','discussing','awaiting_decision','executing') "
        "ORDER BY opened_at DESC",
      );
      return [for (final r in rows) DecisionCard.fromRow(r)];
    } catch (_) {
      return [];
    }
  }

  /// [2026-11-03 主動回應 GC 用] 全部卡（含已結案）——結案清場判斷
  /// 「對話綁的卡是否全部 done/dismissed」需要看歷史卡。
  List<DecisionCard> cardsForGc() {
    final db = _db;
    if (db == null) return [];
    try {
      final rows = db.select(
        "SELECT * FROM decision_cards ORDER BY opened_at DESC",
      );
      return [for (final r in rows) DecisionCard.fromRow(r)];
    } catch (_) {
      return [];
    }
  }

  /// 同類未結案卡（紅旗去重查詢用）
  DecisionCard? unresolvedCardFor(String categoryKey) {
    final db = _db;
    if (db == null) return null;
    try {
      final rows = db.select(
        "SELECT * FROM decision_cards WHERE category_key = ? "
        "AND status IN ('open','discussing','awaiting_decision','executing') "
        "LIMIT 1",
        [categoryKey],
      );
      return rows.isEmpty ? null : DecisionCard.fromRow(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// 指定對話的卡（agent 回覆時綁回用）
  DecisionCard? cardForConversation(String conversationId) {
    final db = _db;
    if (db == null) return null;
    try {
      final rows = db.select(
        "SELECT * FROM decision_cards WHERE conversation_id = ? "
        "AND status IN ('open','discussing','awaiting_decision','executing') "
        "LIMIT 1",
        [conversationId],
      );
      return rows.isEmpty ? null : DecisionCard.fromRow(rows.first);
    } catch (_) {
      return null;
    }
  }

  DecisionCard? byId(String id) {
    final db = _db;
    if (db == null) return null;
    try {
      final rows =
          db.select('SELECT * FROM decision_cards WHERE id = ?', [id]);
      return rows.isEmpty ? null : DecisionCard.fromRow(rows.first);
    } catch (_) {
      return null;
    }
  }

  // ── 狀態轉移 ────────────────────────────────────────────

  void _update(String id, String sql, List<Object?> params) {
    final db = _db;
    if (db == null) return;
    try {
      db.execute(sql, params);
    } catch (_) {} // fail-quiet
  }

  /// 綁對話（開話後 proactive session id 寫回卡）
  void bindConversation(String cardId, String conversationId) => _update(
        cardId,
        'UPDATE decision_cards SET conversation_id = ? WHERE id = ?',
        [conversationId, cardId],
      );

  /// 使用者回應了 → discussing
  void markDiscussing(String cardId) => _update(
        cardId,
        "UPDATE decision_cards SET status = 'discussing' "
        "WHERE id = ? AND status = 'open'",
        [cardId],
      );

  /// agent 給出選項 → awaiting_decision
  void markAwaitingDecision(String cardId, List<DecisionOption> options) {
    final db = _db;
    if (db == null) return;
    try {
      db.execute(
        "UPDATE decision_cards SET status = 'awaiting_decision', "
        "options_json = ? WHERE id = ?",
        [
          jsonEncode([for (final o in options) o.toJson()]),
          cardId,
        ],
      );
    } catch (_) {}
  }

  /// 使用者拍板 → executing（記 chosen + 時間）
  void markDecided(String cardId, String optionId) => _update(
        cardId,
        "UPDATE decision_cards SET status = 'executing', "
        "chosen_option_id = ?, decided_at = ? WHERE id = ?",
        [optionId, DateTime.now().toIso8601String(), cardId],
      );

  /// 執行完成結案
  void closeResolved(String cardId, {String? note}) => _update(
        cardId,
        "UPDATE decision_cards SET status = 'done', closed_at = ?, "
        "close_reason = 'resolved', body = COALESCE(?, body) WHERE id = ?",
        [DateTime.now().toIso8601String(), note, cardId],
      );

  /// 使用者說先不處理 → dismissed 結案（caller 負責記 7 天冷卻）
  void closeDismissed(String cardId) => _update(
        cardId,
        "UPDATE decision_cards SET status = 'dismissed', closed_at = ?, "
        "close_reason = 'dismissed' WHERE id = ?",
        [DateTime.now().toIso8601String(), cardId],
      );

  /// 證據追加（逾時救場把工具軌跡摘要接上用）
  void appendBody(String cardId, String addition) {
    final card = byId(cardId);
    if (card == null) return;
    _update(
      cardId,
      'UPDATE decision_cards SET body = ? WHERE id = ?',
      ['${card.body}\n$addition', cardId],
    );
  }
}

