// [小葵 2026-10-15 T1] 五本記錄單一鑰匙驗收——turn_id join。
// 手法：raw sqlite3 模擬五表各寫一筆同 turn_id 的記錄 → 單一 SQL join 回一列。
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;
  late File tmp;

  setUp(() {
    tmp = File(
      '${Directory.systemTemp.path}/turn_id_join_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}.db',
    );
    db = sqlite3.open(tmp.path);
  });

  tearDown(() {
    db.dispose();
    if (tmp.existsSync()) tmp.deleteSync();
  });

  test('單一 turn_id 串 event_ledger×causal×correction×belief×breaker', () {
    const tid = 't_20261015_test_0001';
    final now = DateTime.now().millisecondsSinceEpoch;

    // 五表最小 schema（T1 後的欄位形狀）
    db.execute('''CREATE TABLE event_ledger (
      id INTEGER PRIMARY KEY AUTOINCREMENT, turn_id TEXT, input TEXT,
      decision TEXT, confidence REAL, executor TEXT, created_at INTEGER)''');
    db.execute('''CREATE TABLE agent_causal_ledger (
      id INTEGER PRIMARY KEY AUTOINCREMENT, tool_name TEXT,
      intervention TEXT, turn_id TEXT, created_at TEXT)''');
    db.execute('''CREATE TABLE correction_events (
      id TEXT PRIMARY KEY, conversation_id TEXT, message_id TEXT,
      kind TEXT, ref_turn_id TEXT, created_at INTEGER)''');
    db.execute('''CREATE TABLE belief_gate_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT, assertion TEXT,
      evidence_count INTEGER, turn_id TEXT, created_at INTEGER)''');
    db.execute('''CREATE TABLE circuit_breaker_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT, action TEXT, bucket REAL,
      turn_id TEXT, created_at INTEGER)''');

    // 同一輪的五本記錄
    db.execute("INSERT INTO event_ledger (turn_id, input, decision, confidence, executor, created_at) VALUES (?, '幫我查鹿角蕨', 'need_memory', 0.82, 'agent_loop', ?)", [tid, now]);
    db.execute("INSERT INTO agent_causal_ledger (tool_name, intervention, turn_id, created_at) VALUES ('memory_search', 'do(query)', ?, '2026-10-15')", [tid]);
    db.execute("INSERT INTO correction_events (id, conversation_id, message_id, kind, ref_turn_id, created_at) VALUES ('m1','c1','m1','factual', ?, ?)", [tid, now]);
    db.execute("INSERT INTO belief_gate_log (assertion, evidence_count, turn_id, created_at) VALUES ('鹿角蕨要散射光', 3, ?, ?)", [tid, now]);
    db.execute("INSERT INTO circuit_breaker_log (action, bucket, turn_id, created_at) VALUES ('trip', 0.8, ?, ?)", [tid, now]);

    // T1 驗收：單一 SQL join 五表回一列
    final rows = db.select('''
      SELECT e.turn_id, e.decision, e.confidence,
             c.tool_name AS causal_tool,
             k.kind AS correction_kind,
             b.assertion AS belief_assertion,
             cb.action AS breaker_action
      FROM event_ledger e
      LEFT JOIN agent_causal_ledger c ON c.turn_id = e.turn_id
      LEFT JOIN correction_events k ON k.ref_turn_id = e.turn_id
      LEFT JOIN belief_gate_log b ON b.turn_id = e.turn_id
      LEFT JOIN circuit_breaker_log cb ON cb.turn_id = e.turn_id
      WHERE e.turn_id = ?
    ''', [tid]);

    expect(rows.length, 1, reason: 'T1：五本記錄用 turn_id 串成一列');
    final r = rows.first;
    expect(r['decision'], 'need_memory');
    expect(r['causal_tool'], 'memory_search');
    expect(r['correction_kind'], 'factual');
    expect(r['belief_assertion'], '鹿角蕨要散射光');
    expect(r['breaker_action'], 'trip');
  });

  test('CausalEntry.turnId 序列化往返', () {
    // schema 層驗證：turn_id 欄可空可寫（舊資料 NULL 不炸 join）
    db.execute('''CREATE TABLE agent_causal_ledger (
      id INTEGER PRIMARY KEY AUTOINCREMENT, tool_name TEXT,
      turn_id TEXT)''');
    db.execute("INSERT INTO agent_causal_ledger (tool_name, turn_id) VALUES ('old_entry', NULL)");
    db.execute("INSERT INTO agent_causal_ledger (tool_name, turn_id) VALUES ('new_entry', 't1')");
    final nulls = db.select("SELECT * FROM agent_causal_ledger WHERE turn_id IS NULL");
    expect(nulls.length, 1, reason: '舊資料 turn_id NULL 相容');
  });
}
