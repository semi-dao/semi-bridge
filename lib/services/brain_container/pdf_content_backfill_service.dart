// pdf_content_backfill_service.dart
// [小葵 2026-08-28] Blue PDF 解析器補足
//
// PDF 是未來使用者的主力格式。本服務：
// 1. 文字層 PDF → pymupdf helper（tools/pdf_extract_text.py）抽文字 → 嵌入
// 2. 掃描 PDF（文字層薄）→ 標 'scanned_pdf'（未來走 Vision 頁面截圖路線）
// 3. 誠實標記：讀不到 → 'unreadable'；密碼 → 'encrypted'
//
// 冪等：embed_source != 'content' 的 .pdf 才處理。
// helper 依賴：python3 + pymupdf（開源使用者文檔需註明）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import '../../core/dev_paths.dart';

import 'brain_database.dart';
import 'embedding/embedding_service.dart';

class PdfContentBackfillService {
  PdfContentBackfillService._();
  static final PdfContentBackfillService instance =
      PdfContentBackfillService._();

  static const _helperPath = 'tools/pdf_extract_text.py';
  bool _running = false;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      await _run(BrainDatabase.instance.db);
    } catch (e, st) {
      debugPrint('[PdfBackfill] ❌ $e\n$st');
      _mark('error:$e');
    } finally {
      _running = false;
    }
  }

  Future<void> _run(Database db) async {
    final embedder = EmbeddingService.instance;
    if (!embedder.isModelAvailable) {
      _mark('model_unavailable');
      return;
    }

    final rows = db.select('''
      SELECT id, folder_root, file_path, file_name, display_title
      FROM asset_index
      WHERE COALESCE(embed_source,'') NOT IN ('content', 'identity')
        AND LOWER(COALESCE(file_ext,'')) = '.pdf'
    ''');

    if (rows.isEmpty) {
      _mark('idle');
      return;
    }
    debugPrint('[PdfBackfill] PDF 待補: ${rows.length} 筆');
    _markProgress(0, rows.length);

    var done = 0;
    var ok = 0;

    for (final r in rows) {
      final id = r['id'] as String;
      final fullPath = '${r['folder_root']}/${r['file_path']}';
      final title = (r['display_title'] as String? ?? r['file_name']) as String;

      try {
        final f = File(fullPath);
        if (!f.existsSync()) {
          db.execute(
              "UPDATE asset_index SET embed_source='unreadable' WHERE id=?",
              [id]);
          done++;
          _markProgress(done, rows.length);
          continue;
        }

        // helper 抽文字
        final pr = await Process.run('python3', [
          _helperPath,
          fullPath,
          '50',
        ], workingDirectory: _appDir());
        if (pr.exitCode != 0) {
          final err = (pr.stderr as String).toLowerCase();
          final mark = err.contains('password') ? 'encrypted' : 'unreadable';
          db.execute(
              "UPDATE asset_index SET embed_source=? WHERE id=?", [mark, id]);
          done++;
          _markProgress(done, rows.length);
          continue;
        }

        final j = jsonDecode(pr.stdout as String) as Map<String, dynamic>;
        if (j.containsKey('error')) {
          db.execute(
              "UPDATE asset_index SET embed_source='unreadable' WHERE id=?",
              [id]);
          done++;
          continue;
        }

        final text = (j['text'] as String? ?? '').trim();
        final scanned = j['scanned'] == true;

        if (scanned || text.length < 30) {
          // 掃描 PDF：文字層沒料。標記等 Vision 頁面路線（未來）
          db.execute(
              "UPDATE asset_index SET embed_source='scanned_pdf' WHERE id=?",
              [id]);
          done++;
          _markProgress(done, rows.length);
          continue;
        }

        // 嵌入：標題 + 內容前 2000 字
        final body = text.length > 2000 ? text.substring(0, 2000) : text;
        final embedText = '$title。$body';
        final result = await embedder.embedOne(embedText);
        if (result.modelVersion == 'mock-fallback') {
          _mark('fallback_stop');
          return;
        }
        db.execute(
          "UPDATE asset_index SET embedding=?, content_text=?, summary=?, "
          "embed_source='content', index_status='indexed', indexed_at=? "
          "WHERE id=?",
          [
            _vecToBlob(result.vector),
            body,
            body.length > 200 ? '${body.substring(0, 200)}...' : body,
            DateTime.now().millisecondsSinceEpoch,
            id,
          ],
        );
        ok++;
      } catch (e) {
        debugPrint('[PdfBackfill] ❌ ${r['file_name']}: $e');
      }
      done++;
      if (done % 5 == 0) _markProgress(done, rows.length);
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _mark('done');
    debugPrint('[PdfBackfill] ✅ 完成：$ok/${rows.length} 文字層嵌入成功');
  }

  String _appDir() {
    // helper 在 repo tools/（dev 機）；打包後 App 不含——fallback 用絕對路徑找
    final dev = Directory('<HOME>/Developer/bridge_app');
    if (File('${dev.path}/$_helperPath').existsSync()) return dev.path;
    return Directory.current.path;
  }

  void _mark(String status) {
    try {
      BrainDatabase.instance.db.execute(
        "INSERT OR REPLACE INTO brain_meta (key, value) VALUES ('pdf_backfill_status', ?)",
        [status],
      );
    } catch (_) {}
  }

  void _markProgress(int done, int total) {
    try {
      BrainDatabase.instance.db.execute(
        "INSERT OR REPLACE INTO brain_meta (key, value) VALUES ('pdf_backfill_progress', '$done/$total')",
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
