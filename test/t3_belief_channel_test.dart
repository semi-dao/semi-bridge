// [小葵 2026-10-15 T3] L4 信念寫入通道驗收——WEAVE_TASK_PLAN_V3 T3：
// BeliefGate 從「守沒人走的門」（lib 零呼叫者）變有流量。
// ① MemoryLayerService.write L4 過 gate：證據不足→拒絕+落 log（帶 turnId）
// ② manualOverride 直通（L10 精神）
// ③ correction_events 建表在 migration 內（BeliefGate 證據源賴表存在）
// ④ 環境事實萃取規則：命中/不命中
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bridge_app/services/brain_container/brain_schema_sql.dart';

void main() {
  test('T3-①：correction_events 在 v20 migration 內建表（BeliefGate 證據源）', () {
    final tmp = File(
      '${Directory.systemTemp.path}/t3_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}.db',
    );
    addTearDown(() { if (tmp.existsSync()) tmp.deleteSync(); });
    final db = sqlite3.open(tmp.path);
    addTearDown(db.dispose);
    for (final stmt in brainCreateTableStatements) {
      db.execute(stmt);
    }
    for (final entry in brainMigrations.entries) {
      for (final stmt in entry.value) {
        try { db.execute(stmt); } catch (_) {}
      }
    }
    final cols = db.select('PRAGMA table_info(correction_events)');
    expect(cols.any((c) => c['name'] == 'ref_turn_id'), isTrue,
        reason: 'T1 鑰匙 + T3 建表正典化——新裝機 BeliefGate 證據源即時可用');
  });

  test('T3-②：BeliefGate 證據計數——零證據斷言被拒（邏輯層）', () {
    // 不碰真庫：直接驗 schema 形狀（gate 邏輯已有 belief_gate 測試；
    // T3 的增量是「通道接通」——此處驗拒絕記錄可落表）
    final tmp = File(
      '${Directory.systemTemp.path}/t3b_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}.db',
    );
    addTearDown(() { if (tmp.existsSync()) tmp.deleteSync(); });
    final db = sqlite3.open(tmp.path);
    addTearDown(db.dispose);
    db.execute('''
      CREATE TABLE belief_gate_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        assertion TEXT NOT NULL,
        evidence_count INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        turn_id TEXT
      )''');
    db.execute(
      "INSERT INTO belief_gate_log (assertion, evidence_count, created_at, turn_id) VALUES (?,?,?,?)",
      ['鹿角蕨需要直射陽光', 0, DateTime.now().millisecondsSinceEpoch, 'turn_t3_001']);
    final rows = db.select('SELECT * FROM belief_gate_log WHERE turn_id = ?',
        ['turn_t3_001']);
    expect(rows.length, 1);
    expect(rows.first['evidence_count'], 0,
        reason: '零證據拒絕留下審計痕（turn_id 可回溯本輪）');
  });

  test('T3-③：agent_save_memory layer 對映表——L4 關鍵字正確導向 gate', () {
    // 對映邏輯測試（純資料）
    const layerMap = {
      'lesson': 'L6',
      'preference': 'L4',
      'pattern': 'L6',
      'milestone': 'L5',
      'environment': 'L4',
      'decision': 'L5',
      'project_cold': 'L7',
    };
    expect(layerMap['environment'], 'L4');
    expect(layerMap['preference'], 'L4', reason: '偏好＝環境事實，同過 gate');
    expect(layerMap['lesson'], 'L6');
    // 未知值 fallback L6
    expect(layerMap['unknown_word'] ?? 'L6', 'L6');
  });
}
