// asset_content_reembed_service.dart
// [小葵 2026-08-28] Blue 開工 A——內容嵌入治本工程
//
// 問題：asset_index 6,562 筆 embedding 全滿，但 embed_source='metadata'
// 佔 6,561——嵌入的是中繼文字（標題/路徑/檔名），不是內容。
// content_text 有料的 5,645 筆（86%）沒被用上，語意檢索仍會 miss。
//
// 本服務：把「有真內容」的資產用內容重嵌。
// - 嵌入文字 = content_text 前 2000 字 +（標題輔助）
// - embed_source 升級為 'content'（冪等守門：只處理 metadata/NULL/filename）
// - content_text 只是檔名（isFilenameOnlyContent）→ 跳過（那些交給
//   VisionPipeline 或維持 metadata 嵌入——沒內容可嵌，不硬嵌）
// - 斷點續跑：批 50 commit + 300ms 讓出 isolate
// - fallback 停損：mock-fallback 出現即停，不寫零向量
// - 進度寫 brain_meta（content_reembed_status / content_reembed_progress）
//
// 未來新檔（Blue 指定）：新檔導入後本服務冪等掃描會自動補——
// 條件 embed_source != 'content' 且 content_text 非檔名 → 嵌。

import 'dart:async';

import '../activity/background_task_registry.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import 'brain_database.dart';
import 'embedding/embedding_service.dart';

class AssetContentReembedService {
  AssetContentReembedService._();
  static final AssetContentReembedService instance =
      AssetContentReembedService._();

  bool _running = false;
  int _reembedded = 0;

  bool get isRunning => _running;
  int get reembeddedCount => _reembedded;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      await _run(BrainDatabase.instance.db);
    } catch (e, st) {
      debugPrint('[ContentReembed] ❌ 失敗: $e\n$st');
      _mark('error:$e');
    } finally {
      _running = false;
    }
  }

  Future<void> _run(Database db) async {
    final embedder = EmbeddingService.instance;
    if (!embedder.isModelAvailable) {
      debugPrint('[ContentReembed] ⏸ 模型未就緒，跳過');
      _mark('model_unavailable');
      return;
    }

    // 待辦：有真內容（content_text 非空且非檔名）且 embed_source 還不是 content
    final total = db.select('''
      SELECT COUNT(*) AS n FROM asset_index
      WHERE content_text IS NOT NULL
        AND LENGTH(content_text) > 10
        AND TRIM(content_text) != TRIM(COALESCE(file_name, ''))
        AND COALESCE(embed_source, '') NOT IN ('content', 'identity')
    ''').first['n'] as int;

    if (total == 0) {
      debugPrint('[ContentReembed] ✅ 無待處理（冪等跳過）');
      _mark('idle');
      return;
    }
    debugPrint('[ContentReembed] 開始：$total 筆待內容重嵌');
    // [小葵 2026-09-30 F2] 活動中心掛牌
    BackgroundTaskRegistry.instance.update(BackgroundTask(
      id: 'content_reembed', name: '內容重嵌入',
      detail: '升級 $total 筆的內容嵌入',
      progress: 0, startedAt: DateTime.now(),
    ));

    final sw = Stopwatch()..start();
    var done = 0;
    const batchSize = 50;

    while (true) {
      final rows = db.select('''
        SELECT id, file_name, content_text, display_title
        FROM asset_index
        WHERE content_text IS NOT NULL
          AND LENGTH(content_text) > 10
          AND TRIM(content_text) != TRIM(COALESCE(file_name, ''))
          AND COALESCE(embed_source, '') NOT IN ('content', 'identity')
        LIMIT ?
      ''', [batchSize]);
      if (rows.isEmpty) break;

      if (done == 100) {
        final rate = done / sw.elapsedMilliseconds * 1000;
        final etaMin = (total - done) / rate / 60;
        debugPrint(
            '[ContentReembed] 📊 ${rate.toStringAsFixed(1)} 筆/秒，剩 ${total - done}，'
            '預估 ${etaMin.toStringAsFixed(1)} 分');
      }

      final texts = rows.map((r) {
        final content = (r['content_text'] as String).trim();
        final title = (r['display_title'] as String?)?.trim() ?? '';
        // 內容為主（前 2000 字，向量搜尋夠用）＋標題加權
        final body = content.length > 2000 ? content.substring(0, 2000) : content;
        return title.isNotEmpty && !body.contains(title) ? '$title。$body' : body;
      }).toList();

      final results = await embedder.embedBatch(texts);
      if (results.any((r) => r.modelVersion == 'mock-fallback')) {
        debugPrint('[ContentReembed] ⛔ fallback，停損');
        _mark('fallback_stop');
        return;
      }

      db.execute('BEGIN');
      try {
        for (var i = 0; i < rows.length; i++) {
          // [U1] 溫和暫停——批次邊界檢查（不打斷當前筆）
          while (BackgroundTaskRegistry.instance.isPauseRequested('content_reembed')) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          db.execute(
            "UPDATE asset_index SET embedding = ?, embed_source = 'content' "
            "WHERE id = ?",
            [_vecToBlob(results[i].vector), rows[i]['id']],
          );
        }
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }

      done += rows.length;
      _reembedded = done;
      _markProgress(done, total);
      if (done % 500 == 0) {
        debugPrint('[ContentReembed] 進度 $done/$total');
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }

    sw.stop();
    _mark('done');
    BackgroundTaskRegistry.instance.finish('content_reembed', note: '$done 筆完成');
    debugPrint('[ContentReembed] ✅ 完成 $done 筆 '
        '${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} 秒');
  }

  void _mark(String status) {
    try {
      BrainDatabase.instance.db.execute(
        "INSERT OR REPLACE INTO brain_meta (key, value) "
        "VALUES ('content_reembed_status', ?)",
        [status],
      );
    } catch (_) {}
  }

  void _markProgress(int done, int total) {
    // [F2] 活動中心進度
    BackgroundTaskRegistry.instance.update(BackgroundTask(
      id: 'content_reembed', name: '內容重嵌入',
      detail: '升級 $total 筆的內容嵌入',
      progress: total == 0 ? 1 : done / total,
      startedAt: DateTime.now(),
    ));
    try {
      BrainDatabase.instance.db.execute(
        "INSERT OR REPLACE INTO brain_meta (key, value) "
        "VALUES ('content_reembed_progress', '$done/$total')",
      );
    } catch (_) {}
  }

  static Uint8List _vecToBlob(List<double> vec) {
    final bytes = ByteData(vec.length * 4);
    for (var i = 0; i < vec.length; i++) {
      bytes.setFloat32(i * 4, vec[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}
