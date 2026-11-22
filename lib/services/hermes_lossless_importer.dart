// [小葵 2026-09-24 Blue 大搬家·記憶完整匯入]
// 把 hermes 對話歷史（conversations_lossless.jsonl）讀進 agent_memories。
//
// 設計：
// - 1 session = 1 條記憶（含所有有意義的 user/asst 輪次交織）
// - 直接寫 DB 繞過 AgentKnowledgeService.createMemory（不寫 embedding）
// - 落地 768 維向量 → memoryFlash 能查得到「你們的對話」
//
// 觸發：BridgeDesktopScreen 啟動時若檢測未跑過就跑一次（idempotent）
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:bridge_app/services/brain_container/brain_database.dart';
import 'package:bridge_app/services/brain_container/embedding/embedding_service.dart';
import 'package:bridge_app/services/brain_container/memory_provenance_service.dart'; // [小葵 2026-11-11] 出處簽章

class HermesLosslessImporter {
  HermesLosslessImporter({
    required this.database,
    required this.embedder,
    required this.companionId,
  });

  final BrainDatabase database;
  final EmbeddingService embedder;
  final String companionId;

  static const String importMarkerTitle =
      'hermes_lossless_import_complete';
  static const String memoryType = 'hermes_conversation';

  /// 對話歷史 jsonl 的標準位置
  static File defaultArtifactFile() {
    final home = Platform.environment['HOME'] ?? '';
    return File(p.join(
      home,
      'Library', 'Application Support', 'farm.semiwasabi.bridgeApp',
      'migration_artifacts', 'conversations_lossless.jsonl',
    ));
  }

  /// [917 重複事故 2026-09-25 根治] 內容指紋——marker 之外的第二道防線。
  /// 指紋 = sha1(owner + title + content)。embedding 前先過濾，
  /// 已存在就跳過。這讓「marker 寫入失敗」不再可能造成全量重複：
  /// 重跑第二次時，全部重複被指紋層攔下（連 embedding 計算都省）。
  ///
  /// 事故根因（9/24）：run_A marker INSERT 因 Dart 內嵌 SQL 引號 bug
  /// 失敗 → idempotent 查無 marker 誤判未搬 → run_B 全量重搬 917 條。
  /// marker 修好後加了 n>800 雙保險，但那只能防「再跑」，救不回
  /// 「已重複」。指紋去重是內容級防線：不管 marker 狀態如何，
  /// 相同內容永遠只入庫一次。
  ///
  /// 去重鍵選 (title, content) 而非 session_id：DB 舊列沒存 session_id，
  /// 但 title+content 在同一 jsonl 來源下是決定性的（同源 → 同內容）。
  /// 這也讓增量搬家自然成立：jsonl 長大後重跑，舊 session 被指紋
  /// 攔下、新 session 淨空入庫。
  String _contentFingerprint(String title, String content) {
    final bytes = utf8.encode('$companionId|$title|$content');
    return sha1.convert(bytes).toString();
  }

  /// 既有內容的指紋集（去重層用）
  Set<String> _existingFingerprints() {
    final keys = <String>{};
    final rows = database.db.select(
      "SELECT title, content FROM agent_memories "
      "WHERE memory_type = ? AND owner_companion_id = ?",
      [memoryType, companionId],
    );
    for (final row in rows) {
      keys.add(_contentFingerprint(
        (row['title'] as String?) ?? '',
        (row['content'] as String?) ?? '',
      ));
    }
    return keys;
  }

  /// 已經匯入過？查 import marker（避免重複匯入膨脹 DB）
  /// 額外防護：DB 裡 hermes_conversation 已超過 800 條就視為已跑過
  bool isAlreadyImported() {
    final rows = database.db.select(
      "SELECT id FROM agent_memories "
      "WHERE title = ? AND owner_companion_id = ? AND is_archived = 0 "
      "LIMIT 1",
      [importMarkerTitle, companionId],
    );
    if (rows.isNotEmpty) return true;
    // 雙保險：直接數量
    final countRows = database.db.select(
      "SELECT COUNT(*) AS n FROM agent_memories "
      "WHERE memory_type = ? AND owner_companion_id = ? AND is_archived = 0",
      [memoryType, companionId],
    );
    final n = (countRows.first['n'] as int?) ?? 0;
    if (n > 800) {
      debugPrint('[LosslessImporter] 已有 $n 條 hermes_conversation，視為已匯入');
      return true;
    }
    return false;
  }

  /// 跑匯入。回傳 ImportReport。
  Future<ImportReport> run({File? source, int batchSize = 32}) async {
    final file = source ?? defaultArtifactFile();
    if (!await file.exists()) {
      return ImportReport(skipped: true, reason: 'jsonl 不存在：${file.path}');
    }
    if (isAlreadyImported()) {
      return ImportReport(skipped: true, reason: '已匯入（marker 存在）');
    }

    debugPrint('[LosslessImporter] 讀 ${file.path} …');
    final raw = await file.readAsString();
    final lines = const LineSplitter().convert(raw);
    debugPrint('[LosslessImporter] ${lines.length} 行');

    // 第一輪：解析、按 session 分組
    final sessions = <String, List<Map<String, dynamic>>>{};
    var skippedEmpty = 0;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final m = jsonDecode(line) as Map<String, dynamic>;
      final sid = m['session_id'] as String? ?? '';
      final content = (m['content'] as String?) ?? '';
      if (content.trim().isEmpty) {
        skippedEmpty++;
        continue;
      }
      sessions.putIfAbsent(sid, () => []).add(m);
    }

    // 第二輪：組裝有意義對話（user ≥1 且 asst content > 50 字 ≥1）
    var drafts = <ConversationDraft>[];
    var skippedSubstantive = 0;
    for (final entry in sessions.entries) {
      final sid = entry.key;
      final msgs = entry.value;
      final hasUser = msgs.any((m) =>
          m['role'] == 'user' && (m['content'] as String).trim().isNotEmpty);
      final hasSubstantiveAsst = msgs.any((m) =>
          m['role'] == 'assistant' &&
          (m['content'] as String).length > 50);
      if (!hasUser || !hasSubstantiveAsst) {
        skippedSubstantive++;
        continue;
      }
      // 取第一個 user 的 timestamp 當 session 起始
      final firstUserTs = msgs
          .firstWhere((m) => m['role'] == 'user')['timestamp']
          .toString();
      // 取 session_title（第一個非空）
      String? sessionTitle;
      for (final m in msgs) {
        final t = m['session_title'] as String?;
        if (t != null && t.trim().isNotEmpty) {
          sessionTitle = t.trim();
          break;
        }
      }
      // 組裝交織文字
      final lines2 = <String>[];
      for (final m in msgs) {
        final role = m['role'] as String;
        if (role != 'user' && role != 'assistant') continue;
        final c = (m['content'] as String).trim();
        if (c.isEmpty) continue;
        // 超長訊息截 1500 字（避免 embedding 超限 + 噪音）
        final body = c.length > 1500 ? '${c.substring(0, 1500)}…' : c;
        lines2.add(
            '${role == "user" ? "Blue" : "小葵"}: ${body.replaceAll("\n", " ")}');
      }
      final content2 = lines2.join('\n');
      if (content2.length > 4000) continue; // 太長的 session 跳過
      drafts.add(ConversationDraft(
        sessionId: sid,
        timestamp: firstUserTs,
        sessionTitle: sessionTitle,
        content: content2,
      ));
    }

    debugPrint('[LosslessImporter] 組裝 ${drafts.length} 個 session（跳過 $skippedEmpty 空白、$skippedSubstantive 不充實）');

    // [917 根治] 第 2.5 輪：指紋去重——embedding 前過濾
    final existing = _existingFingerprints();
    final fresh = <ConversationDraft>[];
    var skippedDuplicate = 0;
    for (final d in drafts) {
      final title = d.sessionTitle ?? '對話 ${d.sessionId.substring(0, 12)}';
      if (existing.contains(_contentFingerprint(title, d.content))) {
        skippedDuplicate++;
        continue;
      }
      fresh.add(d);
    }
    debugPrint('[LosslessImporter] 指紋去重：${drafts.length} → ${fresh.length}（攔下 $skippedDuplicate 重複）');
    if (fresh.isEmpty) {
      // 全部已存在——不寫 marker（避免洗掉既有 marker 語意），
      // 也不膨脹 DB。回報 skippedDuplicate 讓上層知道。
      return ImportReport(
        sessions: 0,
        embedded: 0,
        written: 0,
        skippedEmpty: skippedEmpty,
        skippedSubstantive: skippedSubstantive,
        skippedDuplicate: skippedDuplicate,
      );
    }
    drafts = fresh;

    if (drafts.isEmpty) {
      // 仍寫 marker 避免每次啟動都跑
      _writeMarker(0);
      return ImportReport(sessions: 0, embedded: 0, written: 0);
    }

    // 第三輪：批次 embedding
    var embedded = 0;
    final vectors = <List<double>?>[];
    for (var i = 0; i < drafts.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, drafts.length);
      final batch = drafts.sublist(i, end);
      try {
        final results = await embedder.embedBatch(
          batch.map((d) => d.content).toList(),
        );
        for (var j = 0; j < results.length; j++) {
          vectors.add(results[j].vector);
          embedded++;
        }
      } catch (e) {
        debugPrint('[LosslessImporter] embed 批次 $i 失敗: $e');
        for (var j = 0; j < batch.length; j++) {
          vectors.add(null);
        }
      }
      if (i % 320 == 0) {
        debugPrint('[LosslessImporter] embedding $i / ${drafts.length}');
      }
    }

    // 第四輪：寫 DB（帶 embedding）
    var written = 0;
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    database.db.execute('BEGIN TRANSACTION');
    try {
      for (var i = 0; i < drafts.length; i++) {
        final d = drafts[i];
        final v = vectors[i];
        if (v == null) continue;
        final id = 'mem_lossless_${nowMs}_${i.toString().padLeft(6, '0')}_${Random().nextInt(99999)}';
        final title = d.sessionTitle ?? '對話 ${d.sessionId.substring(0, 12)}';
        // [小葵 2026-09-25 根因修復] embedding 必須是 f32 little-endian BLOB
        // （vector_full_scan 擴展只吃 binary）——之前 jsonEncode 成字串，
        // 917 塊向量形同虛設、語意搜尋永遠查不到（檢索驗收抓包）。
        final embBytes = Uint8List(v.length * 4);
        final embView = ByteData.view(embBytes.buffer);
        for (var j = 0; j < v.length; j++) {
          embView.setFloat32(j * 4, v[j], Endian.little);
        }
        // [小葵 2026-11-11 出處簽章] 匯入即簽（ importer 是合法寫入點）
        final provSig = await MemoryProvenanceService.instance
            .sign(id, title, companionId);
        database.db.execute(
          'INSERT INTO agent_memories '
          '(id, title, content, tags, memory_type, embedding, '
          'created_at, is_archived, owner_companion_id, provenance_sig) '
          'VALUES (?, ?, ?, ?, ?, ?, datetime(?, \'unixepoch\'), 0, ?, ?)',
          [
            id,
            title,
            d.content,
            jsonEncode(['hermes', '對話歷史', '完整匯入']),
            memoryType,
            embBytes,
            (double.parse(d.timestamp)).round(),
            companionId,
            provSig,
          ],
        );
        written++;
      }
      database.db.execute('COMMIT');
    } catch (e) {
      database.db.execute('ROLLBACK');
      debugPrint('[LosslessImporter] DB 寫入失敗: $e');
      rethrow;
    }

    // 第五輪：FTS 同步（external content FTS5 無觸發器）
    // 'rebuild' 命令格式：VALUES 第一個欄位是特殊指令，後面對應 shadow 表欄位。
    debugPrint('[LosslessImporter] 同步 FTS…');
    try {
      // [外部 content FTS5 重建索引]
      // 正確語法：INSERT INTO fts(rowid, col1, col2, ...) SELECT ...
      // 不用 rebuild 特殊指令（語法在純 SQL 模式下較 tricky）
      database.db.execute(
        'INSERT INTO agent_memories_fts(rowid, title, content, tags) '
        'SELECT rowid, title, content, tags FROM agent_memories',
      );
    } catch (e) {
      debugPrint('[LosslessImporter] FTS 同步失敗: $e');
    }

    _writeMarker(written);

    return ImportReport(
      sessions: drafts.length,
      embedded: embedded,
      written: written,
      skippedEmpty: skippedEmpty,
      skippedSubstantive: skippedSubstantive,
    );
  }

  void _writeMarker(int written) {
    final id = 'mem_lossless_marker_${DateTime.now().millisecondsSinceEpoch}';
    database.db.execute(
      'INSERT INTO agent_memories '
      '(id, title, content, tags, memory_type, created_at, '
      'is_archived, owner_companion_id) '
      'VALUES (?, ?, ?, ?, ?, datetime(\'now\'), 0, ?)',
      [
        id,
        importMarkerTitle,
        'marker:$written',
        'system',
        'import_marker',
        companionId,
      ],
    );
  }
}

class ConversationDraft {
  ConversationDraft({
    required this.sessionId,
    required this.timestamp,
    required this.sessionTitle,
    required this.content,
  });
  final String sessionId;
  final String timestamp;
  final String? sessionTitle;
  final String content;
}

class ImportReport {
  ImportReport({
    this.sessions = 0,
    this.embedded = 0,
    this.written = 0,
    this.skippedEmpty = 0,
    this.skippedSubstantive = 0,
    this.skippedDuplicate = 0,
    this.skipped = false,
    this.reason,
  });
  final int sessions;
  final int embedded;
  final int written;
  final int skippedEmpty;
  final int skippedSubstantive;

  /// [917 根治] 被指紋層攔下的重複數（增量搬家時 >0 是正常）
  final int skippedDuplicate;
  final bool skipped;
  final String? reason;

  @override
  String toString() => skipped
      ? 'ImportReport(skipped: $reason)'
      : 'ImportReport(sessions=$sessions embedded=$embedded written=$written '
          'skippedEmpty=$skippedEmpty skippedSubstantive=$skippedSubstantive '
          'skippedDuplicate=$skippedDuplicate)';
}
