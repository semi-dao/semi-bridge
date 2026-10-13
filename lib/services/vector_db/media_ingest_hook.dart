// media_ingest_hook.dart
// [教練 Agent 2026-08-21] 鐵三角 #8 — 畫布產出自動入庫
//
// 畫布/工作流生成的媒體（圖/文/影片/音訊）過去只躺媒體夾，
// 大腦不知道它們存在。這個 hook 在 BridgeMediaStore 寫檔後
// fire-and-forget 把單檔寫入 asset_index（source_type='agent'、
// source='agent_generated'），內文用生成 prompt／文件內容，
// 並即時做本地 embedding——「畫布 → 大腦 → 檢索 → 畫布」成環。
//
// 設計原則：
// - 絕不阻塞媒體回傳路徑（await 只在背景 isolate 式 fire-and-forget 裡）
// - 失敗只 debugPrint，不影響生成結果（UI 誠實原則由 DB 查詢把關）
// - 冪等：file_path 已存在且非 pending 就跳過（沿用 AssetIndexService 慣例）

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../brain_container/brain_database.dart';
import '../brain_container/embedding/embedding_service.dart';

class MediaIngestHook {
  MediaIngestHook._();
  static final MediaIngestHook instance = MediaIngestHook._();

  bool _busy = false;

  /// 媒體寫檔後呼叫。同時打點不重入。
  void ingestGeneratedMedia({
    required String absolutePath,
    required String kind, // image / video / audio / document
    String? prompt, // 生成 prompt（圖/影片/音訊的語義內文）
    String? title, // 文件標題
    String? contentText, // 文件全文（md/html 已剝殼或原樣）
  }) {
    if (_busy) {
      // 上一筆還在嵌——直接排隊到下一輪會漏，誠實記下但不安靜丟失：
      // 重掃（#9 週期 ingest）會把 status=pending 的補上，這裡只提示。
      debugPrint('[MediaIngest] 忙碌中，$absolutePath 交給週期重掃補入');
      _enqueuePending(absolutePath, kind, prompt, title, contentText);
      return;
    }
    _busy = true;
    Future(() async {
      try {
        await _ingest(
          absolutePath: absolutePath,
          kind: kind,
          prompt: prompt,
          title: title,
          contentText: contentText,
        );
      } catch (e) {
        debugPrint('[MediaIngest] 入庫失敗 $absolutePath: $e');
        _enqueuePending(absolutePath, kind, prompt, title, contentText);
      } finally {
        _busy = false;
        _drainQueue();
      }
    });
  }

  final List<Map<String, String?>> _queue = [];

  void _enqueuePending(
    String absolutePath,
    String kind,
    String? prompt,
    String? title,
    String? contentText,
  ) {
    _queue.add({
      'absolutePath': absolutePath,
      'kind': kind,
      'prompt': prompt,
      'title': title,
      'contentText': contentText,
    });
    if (_queue.length > 32) {
      _queue.removeRange(0, _queue.length - 32); // 防爆隊列
    }
  }

  void _drainQueue() {
    if (_busy || _queue.isEmpty) return;
    final next = _queue.removeAt(0);
    ingestGeneratedMedia(
      absolutePath: next['absolutePath']!,
      kind: next['kind']!,
      prompt: next['prompt'],
      title: next['title'],
      contentText: next['contentText'],
    );
  }

  Future<void> _ingest({
    required String absolutePath,
    required String kind,
    String? prompt,
    String? title,
    String? contentText,
  }) async {
    final file = File(absolutePath);
    if (!await file.exists()) return;

    final db = BrainDatabase.instance.db;

    // 冪等：同 file_path 已 indexed 就跳過
    final existing = db.select(
      "SELECT index_status FROM asset_index WHERE file_path = ?",
      [absolutePath],
    );
    if (existing.isNotEmpty) {
      final status = existing.first['index_status'] as String?;
      if (status == 'indexed' || status == 'embedded') return;
    }

    // 內文：文件用全文、媒體用 prompt（截 2000 字，同 AssetIndexService 慣例）
    var text = contentText ?? prompt ?? '';
    if (text.isEmpty) text = p.basename(absolutePath);
    if (text.length > 2000) text = text.substring(0, 2000);

    // 本地 embedding
    final embedder = EmbeddingService.instance;
    List<double>? vector;
    try {
      final result = await embedder.embedOne(text);
      vector = result.vector;
    } catch (e) {
      debugPrint('[MediaIngest] embedding 失敗（先入庫 pending）: $e');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final assetKind = switch (kind) {
      'image' => 'image',
      'video' => 'video',
      'audio' => 'audio',
      _ => 'document',
    };

    db.execute(
      '''INSERT INTO asset_index
         (id, file_path, folder_root, file_name, file_ext, file_size,
          file_modified, index_status, indexed_at, title, asset_kind,
          tags, source, created_at, room, project_id,
          classification_confidence, source_type)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(file_path) DO UPDATE SET
          title = excluded.title,
          asset_kind = excluded.asset_kind,
          file_size = excluded.file_size,
          file_modified = excluded.file_modified,
          indexed_at = excluded.indexed_at
         -- [小葵 2026-09-30 狀態機] 不碰嵌入成果欄位（第七金礦）''',
      [
        'gen_${now}_${absolutePath.hashCode.toRadixString(16)}',
        absolutePath,
        p.dirname(absolutePath), // folder_root＝生成媒體所在目錄
        p.basename(absolutePath),
        p.extension(absolutePath),
        await file.length(),
        now,
        vector != null ? 'indexed' : 'pending',
        now,
        title ?? (prompt != null && prompt.length > 60
            ? '${prompt.substring(0, 60)}...'
            : prompt ?? p.basename(absolutePath)),
        assetKind,
        jsonEncode(<String>['agent_generated']),
        'agent_generated',
        now,
        'bridges', // 房間歸「橋」——畫布產出就是搭橋的行為
        null,
        0.6, // 信心度：規則指派
        'agent',
      ],
    );

    if (vector != null) {
      db.execute(
        "UPDATE asset_index SET embedding = vector_as_f32(?) WHERE file_path = ?",
        [jsonEncode(vector), absolutePath],
      );
    }

    debugPrint('[MediaIngest] 入庫完成: ${p.basename(absolutePath)} '
        '(kind=$assetKind, ${vector != null ? "已嵌入" : "pending 待補嵌"})');
  }
}
