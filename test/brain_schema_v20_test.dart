// [小葵 2026-10-15 T0] v20 migration 驗收——asset_index.embed_model_version。
// 手法比照 contradiction_resolution_test：raw sqlite3 跑 DDL + migrations，
// 驗證新裝機（全 migrations 跑過）asset_index 有 embed_model_version 欄。
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bridge_app/services/brain_container/brain_schema_sql.dart';

void main() {
  test('v20：新建 DB（全 migrations）asset_index.embed_model_version 欄存在', () {
    final tmp = File(
      '${Directory.systemTemp.path}/brain_v20_test_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}.db',
    );
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync();
    });
    final db = sqlite3.open(tmp.path);
    addTearDown(db.dispose);

    for (final stmt in brainCreateTableStatements) {
      db.execute(stmt);
    }
    for (final entry in brainMigrations.entries) {
      for (final stmt in entry.value) {
        try {
          db.execute(stmt);
        } catch (_) {
          // 冪等：欄位已存在則跳過（同 contradiction_resolution_test 手法）
        }
      }
    }
    for (final stmt in brainCreateIndexStatements) {
      db.execute(stmt);
    }

    final cols = db.select('PRAGMA table_info(asset_index)');
    expect(cols.any((c) => c['name'] == 'embed_model_version'), isTrue,
        reason: 'T0 驗收：新裝機 SELECT embed_model_version 不得 no such column');

    // Eg2Reembed 的 SELECT 原句不炸
    db.execute(
      "INSERT INTO asset_index (id, file_path, folder_root, file_name, file_size, "
      "file_modified, index_status, created_at, room, source_type) VALUES "
      "('t1','p1','r','n',1,1,'indexed',1,'bridges','imported')");
    final rows = db.select(
      "SELECT file_path FROM asset_index "
      "WHERE COALESCE(embed_model_version, '') != 'eg2-300m-v1' "
      "AND index_status = 'indexed' AND embedding IS NOT NULL");
    expect(rows, isEmpty); // embedding NULL → 不選（行為不變）

    // 版號字串 = 20
    expect(kBrainSchemaVersion, '20');
  });

  test('v20：v19 舊 DB（已有欄位）migration 不炸 duplicate column（冪等）', () {
    final tmp = File(
      '${Directory.systemTemp.path}/brain_v20_dup_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}.db',
    );
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync();
    });
    final db = sqlite3.open(tmp.path);
    addTearDown(db.dispose);

    for (final stmt in brainCreateTableStatements) {
      db.execute(stmt);
    }
    // 情境＝2026-10-15 的 live DB：欄位已存在（手動 ALTER 過）。
    // v20 migration steps 必須為空（不能有 ALTER）——否則 duplicate column 炸。
    final steps = brainMigrations['from_v19_to_v20']!;
    // D5 守門（2026-10-15 T3 更新）：migration 內禁 ALTER asset_index
    // （live DB 手動 ALTER 過會炸）；T3 加入的 correction_events DDL 是
    // IF NOT EXISTS——冪等，安全。
    expect(
      steps.where((s) => s.toUpperCase().contains('ALTER TABLE ASSET_INDEX')),
      isEmpty,
      reason: 'D5 守門：asset_index 欄位補齊只能走 PRAGMA 確保（brain_database）',
    );
    final cols = db.select('PRAGMA table_info(asset_index)');
    expect(cols.any((c) => c['name'] == 'embed_model_version'), isTrue,
        reason: 'DDL 已含欄位（live DB 由手動 ALTER 先行，2026-10-15 後新 DB 由 DDL 直給）');
  });
}
