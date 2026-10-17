// memory_writer.dart
// 記憶寫入 DB（transaction + rooms 更新）
// 建立日期: 2026-07-02

import 'dart:convert';

import 'package:flutter/foundation.dart'; // [T6③] debugPrint

import 'package:bridge_app/models/brain_container/memory.dart';
import 'package:bridge_app/services/brain_container/brain_database.dart';
import 'package:bridge_app/services/brain_container/persistence/memory_draft.dart';
import 'package:bridge_app/services/brain_container/persistence/memory_file_exporter.dart';

/// 記憶寫入器。
///
/// 將 [MemoryDraft] 列表寫入 SQLite，包含：
/// - Memory 本體 + 向量（vector_as_f32）
/// - rooms 表計數更新
/// 全部在同一 transaction 內完成。
class MemoryWriter {
  final BrainDatabase database;
  int _uuidCounter = 0;

  MemoryWriter({required this.database});

  /// 批次寫入記憶。
  ///
  /// 第一筆為 parent（parentMemoryId = null），
  /// 後續筆的 parentMemoryId 指向第一筆。
  Future<List<Memory>> writeMany(List<MemoryDraft> drafts) async {
    final db = database.db;
    final results = <Memory>[];

    // [小葵 2026-09-07 心臟星防護令] 自我嵌套偵測：內容以「橋：」開頭
    // 疊超過 2 層（橋：橋：…）＝遞迴自我引用的污染鏈（2026-09-02 實案：
    // 46 條記憶 1 秒內嵌套 17 層，把一顆無內容星拱成心臟星）。
    // 嵌套鏈一律剔除——拒絕串接。
    drafts = drafts.where((d) {
      final c = d.content.trim();
      if (c.startsWith('橋：橋：')) {
        return false; // 嵌套 ≥2 層——拒絕
      }
      return true;
    }).toList();
    if (drafts.isEmpty) return results;

    // [T6③/D5 2026-10-17] 拒收 mock-fallback 向量——混血型入庫 = 永遠搜不到
    // 的死記憶（查詢側已過濾 eg2-300m-v1）。fallback 期寫入改為丟棄＋記錄，
    // reindexFallbackMemories 會在 EG2 恢復後補嵌。
    final rejected = drafts
        .where((d) => d.vectorModelVersion == 'mock-fallback')
        .length;
    if (rejected > 0) {
      // 全部都是 fallback = 連續期（EG2 掛了）——整批丟棄等重嵌，
      // 不寫半套（部分 fallback 部分 eg2 的批次會造成記憶斷頭）。
      debugPrint('[MemoryWriter] 🚫 拒收 $rejected 筆 mock-fallback 向量'
          '（EG2 不可用期的記憶，待重嵌後再寫）');
      return results;
    }

    db.execute('BEGIN TRANSACTION');
    try {
      String? parentId;
      for (var i = 0; i < drafts.length; i++) {
        final draft = drafts[i];
        final memoryId = _generateUuid();

        if (i == 0) {
          parentId = memoryId;
        }

        final now = DateTime.now().millisecondsSinceEpoch;

        db.execute(
          'INSERT INTO memories (id, content, embedding, room, sub_category, '
          'agent, companion_id, source, source_id, speaker, project, tags, importance, created_at, '
          'updated_at, access_count, archived, chunk_index, total_chunks, '
          'parent_memory_id, vector_model_version) '
          'VALUES (?, ?, vector_as_f32(?), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            memoryId,
            draft.content,
            Memory.vectorToJson(draft.vector),
            draft.room.name,
            draft.subCategory,
            draft.agent,
            draft.companionId,
            draft.source.dbValue,
            draft.sourceId,
            draft.speaker.dbValue, // [出處戳]
            draft.project,
            jsonEncode(draft.tags),
            draft.importance,
            now,
            now,
            0,
            0,
            draft.chunkIndex,
            draft.totalChunks,
            i == 0 ? null : parentId,
            draft.vectorModelVersion,
          ],
        );

        results.add(draft.toMemory(memoryId, i == 0 ? null : parentId));
      }

      // 更新 rooms 表
      if (results.isNotEmpty) {
        final room = results.first.room.name;
        final count = results.length;
        final now = DateTime.now().millisecondsSinceEpoch;
        db.execute(
          'UPDATE rooms SET memory_count = memory_count + ?, updated_at = ? '
          'WHERE room = ?',
          [count, now, room],
        );

        // [小葵 2026-09-24 鐵則：直寫 DB 必補 FTS] memories_fts 是 external
        // content 表（content='memories'）且無觸發器——INSERT memories 後
        // 不補 FTS，hybrid/fullText 搜尋會 miss 新記憶（搜不到剛存的東西）。
        // 用 last_insert_rowid 不可靠（多筆批次），改按剛寫入的 id 逐筆補。
        for (final mem in results) {
          db.execute(
            'INSERT INTO memories_fts(rowid, content) '
            "SELECT rowid, content FROM memories WHERE id = ? AND content IS NOT NULL",
            [mem.id],
          );
        }
      }

      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }

    // [教練 Agent 2026-08-21] 記憶落檔——「檔案系統是唯一真相」兌現。
    // memories 過去只活 SQLite：DB 損毀＝記憶蒸發，使用者無法用
    // Finder 看見自己的記憶。現在每筆記憶同時落成 md 檔（人類可讀），
    // DB 續任快取索引（向量檢索/圖譜用）。設計同 MediaIngestHook：
    // fire-and-forget、失敗只記 log 絕不阻塞寫入主流程。
    MemoryFileExporter.exportFireAndForget(results);

    return results;
  }

  /// 寫入單筆記憶。
  Future<Memory> writeOne(MemoryDraft draft) async {
    return (await writeMany([draft])).first;
  }

  /// 產生簡單 timestamp-based UUID（未來換 uuid 套件）。
  String _generateUuid() {
    _uuidCounter++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_uuidCounter';
  }
}
