// eg2_reembed_service.dart
// [小葵 2026-10-15 Blue 令：EG2 三線上線] 第三線——全量 EG2 重嵌入。
//
// 設計（比照 identity_reembed_service 模式）：
// - 冪等判準：embed_model_version != 'eg2-300m-v1'（asset_index 新欄，2026-10-15 ALTER）
// - 只重算向量——content_text/embed_source（identity 五因素文本）不動
//   （文本沒變，只是換引擎重算向量）
// - EG2 走 EmbeddingService 雙 backend：_eg2 探測成功 = eg2ModelVersion 標記；
//   若 fallback 到 300M 會以 currentModelVersion 標記（下輪重跑時自動補）
// - 讓出資源：每筆 10ms、每 200 筆 200ms——不搶 App 前台
// - memories 表同步重嵌（vector_model_version 欄已存在）

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart' show Database;

import '../brain_container/brain_database.dart';
import '../brain_container/brain_container_service.dart';
import '../brain_container/embedding/embedding_service.dart';
import 'identity_embed_text.dart';

class Eg2ReembedService {
  Eg2ReembedService._();
  static final Eg2ReembedService instance = Eg2ReembedService._();

  static const _targetVersion = EmbeddingService.eg2ModelVersion; // eg2-300m-v1

  bool _running = false;
  int _done = 0;
  int _total = 0;
  String _lastError = ''; // [小葵 2026-10-15 T0] Fable V3：error 不吞——進度端點帶出

  bool get isRunning => _running;
  int get done => _done;
  int get total => _total;
  String get lastError => _lastError;

  /// 啟動全量 EG2 重嵌（冪等）。回傳實際處理筆數。
  Future<int> start() async {
    if (_running) return 0;
    if (!BrainContainerService.instance.isInitialized) return 0;

    final embedder = EmbeddingService.instance;
    await embedder.initialize();
    if (!embedder.isModelAvailable) {
      debugPrint('[EG2-Reembed] embedding 模型不可用，跳過');
      return 0;
    }

    _running = true;
    var processed = 0;
    try {
      final db = BrainDatabase.instance.db;

      // ── 主庫 asset_index ──
      processed += await _reembedAssetIndex(db, embedder);

      // ── memories 表（K1/背景記憶）──
      processed += await _reembedMemories(db, embedder);

      // ── [小葵 2026-10-15 T6] asset_chunks 內容層（35 萬筆舊血）──
      // 重嵌入 v1 只換了 asset_index 中繼層；chunk 層（長文件內文檢索）
      // 35 萬筆仍是 gemma——內容層語意搜尋跨血型比對。冪等同款。
      processed += await _reembedAssetChunks(db, embedder);

      // ── [小葵 2026-10-15 T6] agent_memories（搬家行囊/教訓）──
      processed += await _reembedAgentMemories(db, embedder);
    } catch (e) {
      _lastError = e.toString(); // [T0] 不吞——/eg2_reembed 端點帶出（診斷不再瞎）
      debugPrint('[EG2-Reembed] ❌ 失敗: $e');
    } finally {
      _running = false;
      debugPrint('[EG2-Reembed] 結束：$processed 筆（done=$_done/$_total）');
    }
    return processed;
  }

  Future<int> _reembedAssetIndex(db, EmbeddingService embedder) async {
    final pending = db.select(
      "SELECT file_path, folder_root, content_text, summary, file_name, "
      "  origin_kind FROM asset_index "
      "WHERE COALESCE(embed_model_version, '') != ? "
      "  AND index_status = 'indexed' AND embedding IS NOT NULL",
      [_targetVersion],
    );
    debugPrint('[EG2-Reembed] asset_index 待重嵌：${pending.length} 筆');
    _total += pending.length as int;
    var n = 0;

    for (final row in pending) {
      final relPath = row['file_path'] as String;
      final content = (row['content_text'] as String?) ??
          (row['summary'] as String?) ??
          (row['file_name'] as String);

      try {
        // 文本不動——直接用存量 content_text 重算向量
        final clamped = content.length > 2000 ? content.substring(0, 2000) : content;
        final result = await embedder.embedOne(clamped);
        if (result.modelVersion == 'mock-fallback') continue; // 引擎不可用

        db.execute(
          "UPDATE asset_index SET embedding = vector_as_f32(?), "
          "  embed_model_version = ?, indexed_at = ? WHERE file_path = ?",
          [jsonEncode(result.vector), result.modelVersion,
           DateTime.now().millisecondsSinceEpoch, relPath],
        );
        n++;
      } catch (e) {
        debugPrint('[EG2-Reembed] 單筆失敗 ($relPath): $e');
      }

      _done++;
      if (_done % 100 == 0) {
        debugPrint('[EG2-Reembed] 進度 $_done/$_total (asset_index)');
      }
      // 讓出資源
      if (n > 0 && n % 200 == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    return n;
  }

  Future<int> _reembedMemories(db, EmbeddingService embedder) async {
    final pending = db.select(
      "SELECT id, content FROM memories "
      "WHERE COALESCE(vector_model_version, '') != ? AND embedding IS NOT NULL",
      [_targetVersion],
    );
    debugPrint('[EG2-Reembed] memories 待重嵌：${pending.length} 筆');
    _total += pending.length as int;
    var n = 0;

    for (final row in pending) {
      final id = row['id'] as String;
      final content = row['content'] as String;
      try {
        final result = await embedder.embedOne(content);
        if (result.modelVersion == 'mock-fallback') continue;

        db.execute(
          "UPDATE memories SET embedding = vector_as_f32(?), "
          "  vector_model_version = ? WHERE id = ?",
          [jsonEncode(result.vector), result.modelVersion, id],
        );
        n++;
      } catch (e) {
        debugPrint('[EG2-Reembed] memories 單筆失敗 ($id): $e');
      }
      _done++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return n;
  }

  /// [小葵 2026-10-15 T6] asset_chunks 重嵌——內容層單一血型。
  /// 量大（35 萬筆）：每筆截 700 字（與 eg2_backend 同款保護）、
  /// 批次回報進度。冪端：model_version != eg2-300m-v1 才重嵌。
  Future<int> _reembedAssetChunks(db, EmbeddingService embedder) async {
    final pendingCount = db.select(
      "SELECT COUNT(*) AS n FROM asset_chunks "
      "WHERE COALESCE(model_version, '') != ? AND embedding IS NOT NULL",
      [_targetVersion],
    ).first['n'] as int;
    debugPrint('[EG2-Reembed] asset_chunks 待重嵌：$pendingCount 筆');
    if (pendingCount == 0) return 0;
    _total += pendingCount;

    // 分頁掃（35 萬筆一次 SELECT 會爆記憶體）
    const pageSize = 500;
    var lastId = '';
    var n = 0;
    while (true) {
      final page = db.select(
        "SELECT chunk_id, content FROM asset_chunks "
        "WHERE COALESCE(model_version, '') != ? AND embedding IS NOT NULL "
        "  AND chunk_id > ? ORDER BY chunk_id LIMIT ?",
        [_targetVersion, lastId, pageSize],
      );
      if (page.isEmpty) break;
      for (final row in page) {
        final id = row['chunk_id'] as String;
        final content = row['content'] as String;
        lastId = id;
        try {
          final clipped = content.length > 700
              ? content.substring(0, 700)
              : content;
          final result = await embedder.embedOne(clipped);
          if (result.modelVersion == 'mock-fallback') continue;
          db.execute(
            "UPDATE asset_chunks SET embedding = vector_as_f32(?), "
            "  model_version = ? WHERE chunk_id = ?",
            [jsonEncode(result.vector), result.modelVersion, id],
          );
          n++;
        } catch (e) {
          debugPrint('[EG2-Reembed] chunk 單筆失敗 ($id): $e');
        }
        _done++;
        if (_done % 500 == 0) {
          debugPrint('[EG2-Reembed] 進度 $_done/$_total (asset_chunks)');
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return n;
  }

  /// [小葵 2026-10-15 T6] agent_memories 重嵌——搬家行囊教訓層。
  Future<int> _reembedAgentMemories(db, EmbeddingService embedder) async {
    final pending = db.select(
      "SELECT id, title, content FROM agent_memories "
      "WHERE COALESCE(embed_model_version, '') != ? AND embedding IS NOT NULL",
      [_targetVersion],
    );
    final pendingCount = pending.length as int;
    debugPrint('[EG2-Reembed] agent_memories 待重嵌：$pendingCount 筆');
    if (pending.isEmpty) return 0;
    _total += pendingCount;
    var n = 0;
    for (final row in pending) {
      final id = row['id'] as String;
      final text = '${row['title'] ?? ''} ${row['content'] ?? ''}';
      try {
        final clipped = text.length > 700 ? text.substring(0, 700) : text;
        final result = await embedder.embedOne(clipped);
        if (result.modelVersion == 'mock-fallback') continue;
        db.execute(
          "UPDATE agent_memories SET embedding = vector_as_f32(?), "
          "  embed_model_version = ? WHERE id = ?",
          [jsonEncode(result.vector), result.modelVersion, id],
        );
        n++;
      } catch (e) {
        debugPrint('[EG2-Reembed] agent_memory 單筆失敗 ($id): $e');
      }
      _done++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return n;
  }
}
