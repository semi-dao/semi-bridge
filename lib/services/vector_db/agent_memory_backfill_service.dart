// agent_memory_backfill_service.dart
// [教練 Agent 2026-08-21] 鐵三角二期 #10——agent_memories 補嵌入
//
// 現況：15 筆 agent 記憶 embedding 全空。Agent 記憶（原生 Agent的
// 工作筆記）不入向量層 → 語義搜尋永遠 miss。
// 本服務：冪等補嵌（有 embedding 的跳過），純本地 TFLite。
// 與 AssetChunkBackfillService 同 SOP：批間讓出、失敗靜默。

import 'package:flutter/foundation.dart';

import '../brain_container/brain_database.dart';
import '../brain_container/embedding/embedding_service.dart';
import '../brain_container/memory_provenance_service.dart'; // [小葵 2026-11-11] 出處簽章守門

class AgentMemoryBackfillService {
  AgentMemoryBackfillService._();
  static final AgentMemoryBackfillService instance = AgentMemoryBackfillService._();

  bool _running = false;

  bool get isRunning => _running;

  /// [教練 Agent 2026-08-21] #10 背景進度廣播（done/total）
  final progress = ValueNotifier<String>('');

  /// 啟動補嵌（冪等）

  Future<void> start() async {
    if (_running) return;
    final db = BrainDatabase.instance.db;

    final pendingResultSet = db.select(
      "SELECT id, title, content, owner_companion_id, provenance_sig FROM agent_memories "
      "WHERE (embedding IS NULL OR length(embedding) = 0) AND is_archived = 0",
    );
    var pending = List.of(pendingResultSet);
    if (pending.isEmpty) {
      debugPrint('[AgentMemBackfill] 無待辦');
      return;
    }
    progress.value = '0/${pending.length}';

    final embedder = EmbeddingService.instance;
    if (!embedder.isModelAvailable) {
      debugPrint('[AgentMemBackfill] embedding 模型不可用——中止');
      return;
    }

    _running = true;
    debugPrint('[AgentMemBackfill] 開始：${pending.length} 筆 agent 記憶待嵌入');

    // [小葵 2026-11-11 出處簽章守門] 無章條目不嵌入——斷「App 幫外部植入
    // 記憶洗白成可語意召回」的路。爺爺條款（backfillGrandfathered）在
    // 啟動鏈跑過後，正常記憶都有章。
    await MemoryProvenanceService.instance.ensureReady();
    if (MemoryProvenanceService.instance.isVerifyReady) {
      final before = pending.length;
      pending = pending.where((r) {
        return MemoryProvenanceService.instance.verify(
          r['id'] as String,
          (r['title'] as String?) ?? '',
          (r['owner_companion_id'] as String?) ?? 'shared',
          r['provenance_sig'] as String?,
        );
      }).toList();
      final blocked = before - pending.length;
      if (blocked > 0) {
        debugPrint('[AgentMemBackfill] ⚠️ 擋下 $blocked 筆無章記憶（不嵌入）');
      }
      if (pending.isEmpty) {
        debugPrint('[AgentMemBackfill] 全部被出處簽章擋下——中止');
        progress.value = '';
        _running = false;
        return;
      }
    }

    // [教練 Agent 2026-08-21] #11 model_version 守門員：brain_meta 記錄上次
    // 嵌入用的模型版本，版本不符 → 中止（防新舊混用污染語義空間）。
    final recorded = db.select(
      "SELECT value FROM brain_meta WHERE key = 'agent_mem_vector_model'",
    );
    final currentModel = EmbeddingService.currentModelVersion;
    if (recorded.isNotEmpty && (recorded.first['value'] as String) != currentModel) {
      debugPrint(
        '[AgentMemBackfill] 版本不符（表內 '
        '${recorded.first['value']} vs 現在 $currentModel）——中止防混用',
      );
      progress.value = ''; // 清空 = 結束
    _running = false;
      return;
    }

    // 15 筆級別——一次 batch 直接做完
    final texts = pending
        .map((r) => '${(r['title'] as String?) ?? ''}\n${(r['content'] as String?) ?? ''}')
        .toList();
    try {
      final results = await embedder.embedBatch(texts);
      for (var i = 0; i < pending.length; i++) {
        final vec = results[i].vector;
        final bytes = Uint8List(vec.length * 4);
        final bd = ByteData.view(bytes.buffer);
        for (var j = 0; j < vec.length; j++) {
          bd.setFloat32(j * 4, vec[j], Endian.little);
        }
        db.execute(
          'UPDATE agent_memories SET embedding = ? WHERE id = ?',
          [bytes, pending[i]['id']],
        );
      }
      db.execute(
        "INSERT OR REPLACE INTO brain_meta (key, value, updated_at) VALUES "
        "('agent_mem_vector_model', ?, ?)",
        [currentModel, DateTime.now().millisecondsSinceEpoch],
      );
      debugPrint('[AgentMemBackfill] 完成：${pending.length} 筆');
    } catch (e) {
      debugPrint('[AgentMemBackfill] 失敗: $e');
    } finally {
      _running = false;
    }
  }
}
