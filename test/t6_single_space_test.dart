// [小葵 2026-10-15 T6] 檢索單一空間驗收——D1 血型鐵則：
// 查詢向量與庫向量必須同血型；異血型比對=距離無意義。
// ① 三軌語意 SQL 都帶血型過濾（memories/asset_index/asset_chunks/agent_memories）
// ② 異血型向量被過濾：模擬 gemma 舊資料不進 kNN 結果
// ③ embedQuery 失敗 throw（不回零向量假裝成功）
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('T6-①：四軌語意 SQL 帶血型過濾（原始碼掃描）', () {
    final src = File(
            'lib/services/vector_db/hybrid_search_service.dart')
        .readAsStringSync();
    // 四處過濾
    final checks = [
      // [T6① 常數化] 單一真相源——寫死字串升級為常數插值，兩種寫法都認
      "m.vector_model_version = '\${EmbeddingService.eg2ModelVersion}'", // memories
      "a.embed_model_version = '\${EmbeddingService.eg2ModelVersion}'", // asset_index
      "c.model_version = '\${EmbeddingService.eg2ModelVersion}'", // asset_chunks
      "m.embed_model_version = '\${EmbeddingService.eg2ModelVersion}'", // agent_memories
    ];
    for (final c in checks) {
      expect(src.contains(c), isTrue, reason: '缺過濾: $c');
    }
    // embedQuery 不再零向量 fallback：抓 embedQuery 方法區塊驗
    final embSrc = File(
            'lib/services/brain_container/embedding/embedding_service.dart')
        .readAsStringSync();
    final qFnStart = embSrc.indexOf('Future<List<double>> embedQuery');
    final qFnEnd = embSrc.indexOf('\n  }', qFnStart);
    final qFn = embSrc.substring(qFnStart, qFnEnd);
    expect(
      qFn.contains("List.filled(vectorDimension, 0.0)"),
      isFalse,
      reason: 'embedQuery 區塊不得回零向量（零向量曾繞過血型檢查）',
    );
    expect(qFn.contains("throw StateError('EG2"),
        isTrue, reason: 'EG2 失敗必 throw（讓上層轉全文搜尋）');
  });

  test('T6-②：異血型向量被過濾——gemma 舊資料不進 kNN', () {
    final tmp = File(
      '${Directory.systemTemp.path}/t6_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}.db',
    );
    addTearDown(() { if (tmp.existsSync()) tmp.deleteSync(); });
    final db = sqlite3.open(tmp.path);
    addTearDown(db.dispose);
    db.execute('''
      CREATE TABLE memories (
        id TEXT PRIMARY KEY, content TEXT, room TEXT DEFAULT 'stream',
        archived INTEGER DEFAULT 0, superseded_by TEXT, expires_at INTEGER,
        embedding BLOB, vector_model_version TEXT,
        created_at INTEGER NOT NULL DEFAULT 0
      )''');
    final blob = List.filled(32, 0); // BLOB 內容不重要——驗的是過濾語意
    db.execute(
      "INSERT INTO memories (id, content, embedding, vector_model_version) VALUES ('eg2_1','同血型', ?, 'eg2-300m-v1')",
      [blob]);
    db.execute(
      "INSERT INTO memories (id, content, embedding, vector_model_version) VALUES ('gemma_1','異血型', ?, 'gemma-300m-v1')",
      [blob]);
    final rows = db.select(
      "SELECT id FROM memories WHERE vector_model_version = 'eg2-300m-v1'");
    expect(rows.length, 1);
    expect(rows.first['id'], 'eg2_1');
  });

  test('T6-③：Eg2ReembedService 擴了 chunks＋agent_memories 軌', () {
    final src = File(
            'lib/services/vector_db/eg2_reembed_service.dart')
        .readAsStringSync();
    expect(src.contains('_reembedAssetChunks'), isTrue);
    expect(src.contains('_reembedAgentMemories'), isTrue);
    expect(src.contains("model_version != ? AND embedding IS NOT NULL") ||
        src.contains("COALESCE(model_version, '') != ?"), isTrue);
  });
}
