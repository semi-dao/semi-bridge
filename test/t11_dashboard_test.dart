// t11_dashboard_test.dart
// [T11②③ 2026-10-17] 雲端率儀表＋修正率週報——EventLedger 統計層測試。
// 注入暫存 DB（認知傷口鐵則：測試必雙 singleton 注入，絕不碰真庫）。
import 'dart:convert';

import 'package:bridge_app/services/brain_container/event_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

(EventLedger, Database) _freshLedger() {
  final db = sqlite3.openInMemory();
  return (EventLedger.forTest(db), db);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('T11② cloudRateStats——本地/雲端計數＋by_provider 分佈', () async {
    final (ledger, db) = _freshLedger();
    db.execute("CREATE TABLE IF NOT EXISTS event_ledger ("
        "rowid INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT DEFAULT 'turn',"
        "turn_id TEXT NOT NULL, ref_turn_id TEXT, ts INTEGER NOT NULL,"
        "input TEXT, input_hash TEXT, injected_ids TEXT, decision TEXT,"
        "confidence REAL, executor TEXT, output TEXT, user_reaction TEXT,"
        "meta TEXT, hash_prev TEXT NOT NULL, hash_self TEXT NOT NULL,"
        "answer_confidence REAL)");
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute("INSERT INTO event_ledger (kind, turn_id, ts, meta, hash_prev, hash_self) VALUES "
        "('turn','t1',?,?,'a','b'),('turn','t2',?,?,'a','b'),('turn','t3',?,?,'a','b')", [
      now, jsonEncode({'provider': 'local', 'is_local': true}),
      now, jsonEncode({'provider': 'zai', 'is_local': false}),
      now, jsonEncode({'provider': 'zai', 'is_local': false}),
    ]);

    final stats = ledger.cloudRateStats(days: 7);
    expect(stats['total'], 3);
    expect(stats['local'], 1);
    expect(stats['cloud'], 2);
    expect(stats['by_provider'], {'local': 1, 'zai': 2});
  });

  test('T11② cloudRateStats——無 meta 的舊輪次不計入分母（誠實）', () async {
    final (ledger, db) = _freshLedger();
    db.execute("CREATE TABLE IF NOT EXISTS event_ledger ("
        "rowid INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT DEFAULT 'turn',"
        "turn_id TEXT NOT NULL, ref_turn_id TEXT, ts INTEGER NOT NULL,"
        "input TEXT, input_hash TEXT, injected_ids TEXT, decision TEXT,"
        "confidence REAL, executor TEXT, output TEXT, user_reaction TEXT,"
        "meta TEXT, hash_prev TEXT NOT NULL, hash_self TEXT NOT NULL,"
        "answer_confidence REAL)");
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute("INSERT INTO event_ledger (kind, turn_id, ts, meta, hash_prev, hash_self) VALUES "
        "('turn','t_old',?,NULL,'a','b')", [now]);
    final stats = ledger.cloudRateStats(days: 7);
    expect(stats['total'], 0); // 舊輪次無 meta——不硬算
  });

  test('T11③ correctionWeeklyReport——三週數字＋無反應週 rate=null', () async {
    final (ledger, db) = _freshLedger();
    db.execute("CREATE TABLE IF NOT EXISTS event_ledger ("
        "rowid INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT DEFAULT 'turn',"
        "turn_id TEXT NOT NULL, ref_turn_id TEXT, ts INTEGER NOT NULL,"
        "input TEXT, input_hash TEXT, injected_ids TEXT, decision TEXT,"
        "confidence REAL, executor TEXT, output TEXT, user_reaction TEXT,"
        "meta TEXT, hash_prev TEXT NOT NULL, hash_self TEXT NOT NULL,"
        "answer_confidence REAL)");
    db.execute("CREATE TABLE IF NOT EXISTS correction_events ("
        "id TEXT PRIMARY KEY, conversation_id TEXT, message_id TEXT, kind TEXT,"
        "hit_pattern TEXT, user_text TEXT, assistant_context TEXT, created_at INTEGER)");
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute("INSERT INTO event_ledger (kind, turn_id, ts, meta, hash_prev, hash_self) VALUES "
        "('turn','t1',?,?,'a','b'),('turn','t2',?,?,'a','b')", [
      now, jsonEncode({'provider': 'local', 'is_local': true}),
      now, jsonEncode({'provider': 'zai', 'is_local': false}),
    ]);
    db.execute("INSERT INTO correction_events (id, created_at) VALUES ('c1', ?)", [now]);

    final report = ledger.correctionWeeklyReport(weeks: 3);
    expect(report, isNotNull);
    final weeks = (report!['weeks'] as List).cast<Map<String, dynamic>>();
    expect(weeks.length, 3);
    expect(weeks[0]['turns'], 2);
    expect(weeks[0]['corrected'], 1);
    expect(weeks[1]['turns'], 0); // 上週沒輪次
    expect(weeks[1]['rate'], isNull); // 分母 0 → 不硬算
  });

  test('T11② updateTurnMeta——補記 provider 進既有 meta（不覆蓋舊欄位）', () async {
    final (ledger, db) = _freshLedger();
    db.execute("CREATE TABLE IF NOT EXISTS event_ledger ("
        "rowid INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT DEFAULT 'turn',"
        "turn_id TEXT NOT NULL, ref_turn_id TEXT, ts INTEGER NOT NULL,"
        "input TEXT, input_hash TEXT, injected_ids TEXT, decision TEXT,"
        "confidence REAL, executor TEXT, output TEXT, user_reaction TEXT,"
        "meta TEXT, hash_prev TEXT NOT NULL, hash_self TEXT NOT NULL,"
        "answer_confidence REAL)");
    final now = DateTime.now().millisecondsSinceEpoch;
    db.execute("INSERT INTO event_ledger (kind, turn_id, ts, meta, hash_prev, hash_self) VALUES "
        "('turn','t1',?,?,'a','b')", [now, jsonEncode({'latency_ms': 120})]);

    ledger.updateTurnMeta('t1', {'provider': 'zai', 'is_local': false});
    final row = db.select("SELECT meta FROM event_ledger WHERE turn_id = 't1'").first;
    final meta = jsonDecode(row['meta'] as String) as Map<String, dynamic>;
    expect(meta['latency_ms'], 120); // 舊欄位保留
    expect(meta['provider'], 'zai'); // 新欄位補上
  });
}
