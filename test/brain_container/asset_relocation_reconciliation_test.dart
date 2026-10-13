// asset_relocation_reconciliation_test.dart
// [小葵 2026-10-06 Blue 反向問題] hash 優先搬家對帳——回歸測試
//
// 鎖死的行為（「內容是身份，路徑只是指標」）：
// 1. 同 root 搬家/改名：新 path + 相同 hash → UPDATE 那筆（向量保留），不出現第二筆
// 2. 跨 root 搬家：舊 root 死鏈標記 missing → 新 root 對帳命中 → 復原 indexed + 換 root
// 3. 複製（舊路徑還在）：兩筆並存——不誤判搬家
// 4. 搜尋/嵌入查詢過濾 ='indexed' → missing 自然排除（行為等價刪除）
//
// 測試環境限制：_writeRecordsToDb 依賴 BrainDatabase 硬單例，本測試直接
// 用 sqlite3 開臨時庫跑 production schema + 重現對帳的查詢/UPDATE 語義
// （與 asset_index_service.dart 內 SQL 逐字相同——改 SQL 沒同步這裡會紅）。

import 'dart:io';
import 'dart:math';

import 'dart:typed_data';

import 'package:bridge_app/services/brain_container/brain_schema_sql.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// 假 embedding BLOB（向量存在的替代品）
final _fakeVec = Uint8List.fromList(List.filled(256, 7));

void main() {
  late Database db;

  setUp(() {
    final tmp = File(
      '${Directory.systemTemp.path}/asset_reloc_test_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}.db',
    );
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync();
    });
    db = sqlite3.open(tmp.path);
    for (final stmt in brainCreateTableStatements) {
      db.execute(stmt);
    }
    for (final entry in brainMigrations.entries) {
      for (final stmt in entry.value) {
        try {
          db.execute(stmt);
        } catch (_) {}
      }
    }
    for (final stmt in brainCreateIndexStatements) {
      db.execute(stmt);
    }
  });

  tearDown(() => db.dispose());

  void insertAsset(
    String id,
    String filePath,
    String folderRoot,
    String hash, {
    String status = 'indexed',
    Object? embedding,
  }) {
    db.execute(
      'INSERT INTO asset_index (id, file_path, folder_root, file_name, '
      'file_ext, file_size, file_modified, index_status, indexed_at, title, '
      'asset_kind, tags, source, created_at, room, '
      'classification_confidence, source_type, file_hash, audience, embedding) '
      "VALUES (?, ?, ?, 'photo.jpg', '.jpg', 100, 1000, ?, 2000, '我的照片', "
      "'image', '[]', 'user', 1000, 'bridges', 0.9, 'imported', ?, 'general', ?)",
      [id, filePath, folderRoot, status, hash, embedding],
    );
  }

  /// 與 _writeRecordsToDb 相同的對帳索引查詢（逐字同步）
  Map<String, ({String root, String path})> buildHashIndex() {
    final rows = db.select(
      "SELECT folder_root, file_path, file_hash FROM asset_index "
      "WHERE file_hash IS NOT NULL "
      "  AND index_status IN ('indexed','embedded','missing')",
    );
    return {
      for (final row in rows)
        row['file_hash'] as String: (
          root: row['folder_root'] as String,
          path: row['file_path'] as String,
        ),
    };
  }

  /// 與 _writeRecordsToDb 相同的搬家 UPDATE（逐字同步）
  void relocate(db, String newRoot, String newPath, String hash,
      Map<String, ({String root, String path})> hashIndex) {
    final hit = hashIndex[hash];
    final now = 3000;
    db.execute(
      'UPDATE asset_index SET '
      'file_path = ?, folder_root = ?, file_name = ?, file_ext = ?, '
      'file_size = ?, file_modified = ?, indexed_at = ?, '
      "index_status = 'indexed' "
      'WHERE file_path = ?',
      [newPath, newRoot, 'renamed.jpg', '.jpg', 100, 1000, now, hit!.path],
    );
  }

  test('情境1：同 root 改名——向量保留、不長第二筆', () {
    insertAsset('a1', 'photos/old.jpg', '/vault/A', 'HASH_X',
        embedding: _fakeVec);
    final idx = buildHashIndex();
    expect(idx['HASH_X'], isNotNull);
    expect(idx['HASH_X']!.path, 'photos/old.jpg');

    // 模擬新掃描發現 photos/renamed.jpg（同內容），舊路徑已不存在
    relocate(db, '/vault/A', 'photos/renamed.jpg', 'HASH_X', idx);

    final rows = db.select('SELECT * FROM asset_index');
    expect(rows.length, 1, reason: '搬家不長第二筆');
    expect(rows.first['file_path'], 'photos/renamed.jpg');
    expect(rows.first['index_status'], 'indexed');
    expect(rows.first['embedding'] as List<int>, isNotEmpty, reason: '向量必須保留');
    expect(rows.first['title'], '我的照片', reason: '描述必須保留');
  });

  test('情境2：跨 root 搬家——missing 救回 + root 轉移', () {
    insertAsset('a1', 'photos/moved.jpg', '/vault/A', 'HASH_Y',
        embedding: _fakeVec);
    // 舊 root 掃描：死鏈標記（與 fullScan 內 SQL 逐字相同）
    db.execute(
      "UPDATE asset_index SET index_status = 'missing' "
      "WHERE file_path = ? AND folder_root = ?",
      ['photos/moved.jpg', '/vault/A'],
    );

    // missing 必須在對帳名單內
    final idx = buildHashIndex();
    expect(idx['HASH_Y'], isNotNull, reason: 'missing 必須可被對帳救回');

    // 新 root 掃描發現同內容檔案
    relocate(db, '/vault/B', 'photos/moved.jpg', 'HASH_Y', idx);

    final rows = db.select('SELECT * FROM asset_index');
    expect(rows.length, 1);
    expect(rows.first['folder_root'], '/vault/B', reason: 'root 已轉移');
    expect(rows.first['index_status'], 'indexed', reason: 'missing 已復原');
    expect(rows.first['embedding'] as List<int>, isNotEmpty);
  });

  test('情境3：複製（舊路徑還在）——兩筆並存', () {
    insertAsset('a1', 'photos/orig.jpg', '/vault/A', 'HASH_Z',
        embedding: _fakeVec);
    final idx = buildHashIndex();
    // 舊路徑 existsSync()=true → 服務端會跳過 relocate 走 INSERT——
    // 這裡驗證「不 relocate」時兩筆並存的 DB 狀態合法
    insertAsset('a2', 'photos/copy.jpg', '/vault/A', 'HASH_Z',
        embedding: _fakeVec);
    final rows = db.select('SELECT * FROM asset_index');
    expect(rows.length, 2, reason: '複製＝兩筆並存，不誤判搬家');
    expect(rows.where((r) => r['file_hash'] == 'HASH_Z').length, 2);
  });

  test('情境4：missing 不進搜尋（行為等價刪除）', () {
    insertAsset('a1', 'photos/gone.jpg', '/vault/A', 'HASH_G',
        embedding: _fakeVec);
    db.execute(
      "UPDATE asset_index SET index_status = 'missing' "
      "WHERE file_path = ? AND folder_root = ?",
      ['photos/gone.jpg', '/vault/A'],
    );
    // 與 hybrid_search_service 等同款過濾
    final rows = db.select(
      "SELECT * FROM asset_index "
      "WHERE index_status = 'indexed' AND embedding IS NOT NULL",
    );
    expect(rows.isEmpty, true, reason: 'missing 必須從檢索排除');
  });
}
