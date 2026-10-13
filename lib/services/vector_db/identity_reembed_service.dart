// identity_reembed_service.dart
// [小葵 2026-09-09 Blue v2 檢索令] 全量身份重嵌——6,140 筆背景重嵌。
//
// 設計稿 §5：
// - embed_text 用 IdentityEmbedText 重建（五因素）
// - vision 描述不重跑（content_text 已有）——只重嵌向量
// - embed_source 統一升級 'identity'
// - 冪等：只處理 embed_source != 'identity' 的筆數
// - 讓出資源：每筆間 10ms，批次間 200ms

import 'dart:convert';

import '../activity/background_task_registry.dart';

import 'package:flutter/foundation.dart';

import '../brain_container/brain_database.dart';
import '../brain_container/brain_container_service.dart';
import '../brain_container/embedding/embedding_service.dart';
import 'identity_embed_text.dart';
import 'vector_sketch_service.dart';

class IdentityReembedService {
  IdentityReembedService._();
  static final IdentityReembedService instance = IdentityReembedService._();

  bool _running = false;
  int _done = 0;
  int _total = 0;
  String _currentFile = '';

  bool get isRunning => _running;
  int get done => _done;
  int get total => _total;

  /// 啟動全量身份重嵌（冪等——已在跑就直接回）。
  Future<void> start() async {
    if (_running) return;
    if (!BrainContainerService.instance.isInitialized) return;

    final embedder = EmbeddingService.instance;
    if (!embedder.isModelAvailable) {
      debugPrint('[IdentityReembed] embedding 模型不可用，跳過');
      return;
    }

    _running = true;
    try {
      final db = BrainDatabase.instance.db;

      // 待辦：還不是 identity 的全部（general+technical 都要——技術層也該有身份）
      final pending = db.select(
        "SELECT file_path, folder_root, content_text, summary, file_name, "
        "  origin_kind, embed_source "
        "FROM asset_index "
        "WHERE COALESCE(embed_source, '') != 'identity' "
        "  AND index_status = 'indexed'",
      );
      _total = pending.length;
      _done = 0;
      debugPrint('[IdentityReembed] 開始：$_total 筆');

      for (final row in pending) {
        // [U1] 溫和暫停——批次邊界檢查
        while (BackgroundTaskRegistry.instance.isPauseRequested('identity_reembed')) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        final relPath = row['file_path'] as String;
        final folderRoot = row['folder_root'] as String;
        final content = (row['content_text'] as String?) ??
            (row['summary'] as String?) ??
            (row['file_name'] as String);
        final originKind = row['origin_kind'] as String?;

        try {
          // content_text 可能已帶舊前綴 [資料夾: ...]——IdentityEmbedText
          // 會再組一次；先剝掉舊前綴避免重複
          var body = content;
          final oldPrefix = RegExp(r'^\[資料夾: [^\]]*\]\s*');
          body = body.replaceFirst(oldPrefix, '');

          final text = await IdentityEmbedText.instance.build(
            relPath: relPath,
            folderRoot: folderRoot,
            content: body,
            originKind: originKind,
          );
          final clamped =
              text.length > 2000 ? text.substring(0, 2000) : text;
          final result = await embedder.embedOne(clamped);

          db.execute(
            "UPDATE asset_index SET embedding = vector_as_f32(?), "
            "  content_text = ?, embed_source = 'identity', "
            "  indexed_at = ? WHERE file_path = ?",
            [
              jsonEncode(result.vector),
              clamped,
              DateTime.now().millisecondsSinceEpoch,
              relPath,
            ],
          );
        } catch (e) {
          debugPrint('[IdentityReembed] 單筆失敗 ($relPath): $e');
        }

        _done++;
        _currentFile = relPath;
        if (_done % 50 == 0) {
          debugPrint(
              '[IdentityReembed] 進度 $_done/$_total: $_currentFile');
        }
        // 讓出資源
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      debugPrint('[IdentityReembed] ✅ 完成 $_done/$_total');
      // [小葵 2026-09-09 Blue 令] 嵌入完成 → 自動「向量資料素描」
      if (_done > 0) {
        try {
          await VectorSketchService.instance.run();
        } catch (e) {
          debugPrint('[IdentityReembed] 素描失敗（不影響重嵌）: $e');
        }
      }
    } catch (e) {
      debugPrint('[IdentityReembed] ❌ 失敗: $e');
    } finally {
      _running = false;
    }
  }

  Map<String, dynamic> progress() => {
        'running': _running,
        'done': _done,
        'total': _total,
        'current': _currentFile,
      };
}
