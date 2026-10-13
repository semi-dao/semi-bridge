// hybrid_search_service.dart
// [教練 Agent 2026-07-25] 統一搜尋服務
//
// 同時查詢大腦（memories 表）+ 圖書館（asset_index 表），
// 回傳合併後的搜尋結果。
//
// Phase 2：全文搜尋（FTS5 for asset_index + LIKE for memories）
// Phase 3：語意搜尋（向量相似度）+ hybrid 模式
// Phase 5：圖譜展開（memory_asset_links 交叉引用）— TODO
//
// 設計文件：B+-Hybrid-GraphRAG-大腦與圖書館協同架構.md §6

import 'dart:convert';

import 'package:bridge_app/services/brain_container/brain_database.dart';
import 'package:bridge_app/services/brain_container/embedding/embedding_service.dart';
import 'package:bridge_app/services/vector_db/five_factor_rerank.dart'; // [小葵 2026-09-09] 五因素重排
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 搜尋模式
enum SearchMode {
  /// 全文搜尋（LIKE + FTS5）
  fullText,
  /// 語意搜尋（向量相似度）— Phase 3 TODO
  semantic,
  /// 混合搜尋（全文 + 語意）— Phase 3 TODO
  hybrid,
}

/// 統一搜尋結果
class HybridSearchResults {
  /// 大腦記憶命中
  final List<MemoryHit> memoryHits;

  /// 圖書館檔案命中
  final List<AssetHit> assetHits;

  /// [Phase 5] 交叉引用關聯（記憶↔檔案的連結）
  final List<CrossLinkInfo> crossLinks;

  /// [Cerebras 啟發] LLM 綜合答案（含引用 + 衝突標注）
  final String? synthesizedAnswer;

  const HybridSearchResults({
    this.memoryHits = const [],
    this.assetHits = const [],
    this.crossLinks = const [],
    this.synthesizedAnswer,
  });

  /// 是否無結果
  bool get isEmpty =>
      memoryHits.isEmpty && assetHits.isEmpty && crossLinks.isEmpty;

  /// 總命中數
  int get totalHits => memoryHits.length + assetHits.length;

  /// 合併新的結果進來（去重 + 保留較高分）
  HybridSearchResults mergeWith(HybridSearchResults other) {
    final memMap = <String, MemoryHit>{};
    for (final h in [...memoryHits, ...other.memoryHits]) {
      final ex = memMap[h.id];
      if (ex == null || h.score > ex.score) memMap[h.id] = h;
    }
    final assetMap = <String, AssetHit>{};
    for (final h in [...assetHits, ...other.assetHits]) {
      final ex = assetMap[h.id];
      if (ex == null || h.score > ex.score) assetMap[h.id] = h;
    }
    final linkSet = <String>{};
    final links = <CrossLinkInfo>[...crossLinks, ...other.crossLinks].where((l) {
      final key = '${l.memoryId}_${l.assetId}_${l.linkType}';
      if (linkSet.contains(key)) return false;
      linkSet.add(key);
      return true;
    }).toList();

    final memories = memMap.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final assets = assetMap.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return HybridSearchResults(
      memoryHits: memories,
      assetHits: assets,
      crossLinks: links,
      // synthesizedAnswer 取非 null 的（對方優先，因為 mergeWith 是把 other 合進來）
      synthesizedAnswer: synthesizedAnswer ?? other.synthesizedAnswer,
    );
  }
}

/// [Phase 5] 交叉引用關聯資訊
class CrossLinkInfo {
  final String memoryId;
  final String assetId;
  final String linkType; // referenced / inspired / produced_from
  final String? note;

  const CrossLinkInfo({
    required this.memoryId,
    required this.assetId,
    required this.linkType,
    this.note,
  });
}

/// 大腦記憶命中
class MemoryHit {
  /// memories.id
  final String id;

  /// 記憶內容
  final String content;

  /// 所屬房間
  final String room;

  /// 相似度分數（0.0 ~ 1.0）
  final double score;

  const MemoryHit({
    required this.id,
    required this.content,
    required this.room,
    required this.score,
  });

  @override
  String toString() => 'MemoryHit(id: $id, room: $room, score: $score)';
}

/// 圖書館檔案命中
class AssetHit {
  /// asset_index.id
  final String id;

  /// 檔案路徑（相對於根資料夾）
  final String filePath;

  /// 檔名
  final String fileName;

  /// 標題（可為空）
  final String? title;

  /// 摘要（可為空）
  final String? summary;

  /// 檔案類型（image / video / document / audio / workflow / other）
  final String assetKind;

  /// 相似度分數（0.0 ~ 1.0）
  final double score;

  const AssetHit({
    required this.id,
    required this.filePath,
    required this.fileName,
    this.title,
    this.summary,
    required this.assetKind,
    required this.score,
  });

  @override
  String toString() => 'AssetHit(id: $id, file: $fileName, score: $score)';
}

/// 統一搜尋服務（單例）
///
/// 同時查詢大腦（memories 表）與圖書館（asset_index 表），
/// 將結果合併回傳。
///
/// 使用方式：
/// ```dart
/// final results = await HybridSearchService.instance.search(
///   query: '會議筆記',
///   mode: SearchMode.fullText,
/// );
/// ```
class HybridSearchService {
  HybridSearchService._();
  static final HybridSearchService instance = HybridSearchService._();

  /// 統一搜尋：同時查大腦 + 圖書館
  ///
  /// [query] — 搜尋關鍵字或自然語言查詢
  /// [mode] — 搜尋模式（fullText / semantic / hybrid）
  /// [limit] — 每邊最大命中數（預設 20）
  Future<HybridSearchResults> search({
    required String query,
    SearchMode mode = SearchMode.hybrid,
    int limit = 20,
    String? projectId,
    // [小葵 2026-09-09 Blue 分層令] 預設只搜 general 層；工程模式傳
    // true 才含 technical（vendored 依賴/工具設定/build 產物）
    bool includeTechnical = false,
    // [M1 K1 獨立通道 2026-10-10 Fable 拍板] false = 跳過圖譜展開與
    // 上下文展開——K1 候選只要 RRF 直接命中（展開命中分數固定 0.2~0.5
    // 會把 RRF 真命中（上限 ~0.033）擠出排序——噪音壓過真命中）。
    bool expand = true,
  }) async {
    // 空查詢直接回傳空結果
    if (query.trim().isEmpty) {
      return const HybridSearchResults();
    }

    switch (mode) {
      case SearchMode.fullText:
        // 純全文搜尋
        return HybridSearchResults(
          memoryHits: _searchMemoriesFullText(query, limit),
          assetHits: _searchAssetsFullText(query, limit,
              includeTechnical: includeTechnical),
        );

      case SearchMode.semantic:
        // 純語意搜尋
        return await _searchSemantic(query, limit,
            includeTechnical: includeTechnical);

      case SearchMode.hybrid:
        // RRF 融合：FTS + 語意各自跑，再用 RRF 合併排名
        final ftsMemories = _searchMemoriesFullText(query, limit);
        final ftsAssets = _searchAssetsFullText(query, limit,
              includeTechnical: includeTechnical);

        List<MemoryHit> semanticMemories = [];
        List<AssetHit> semanticAssets = [];

        final embedder = EmbeddingService.instance;
        if (embedder.isModelAvailable) {
          try {
            final queryVector = await embedder.embedQuery(query);
            if (queryVector.isNotEmpty && !queryVector.every((v) => v == 0.0)) {
              semanticMemories = [
                ..._searchMemoriesSemantic(queryVector, limit),
                // [小葵 2026-09-21] 搬家行囊進 hybrid 語意層——修「向量不可達」斷點
                ..._searchAgentMemoriesSemantic(queryVector, limit),
              ];
              semanticAssets = _searchAssetsSemantic(queryVector, limit,
              includeTechnical: includeTechnical);
            }
          } catch (e) {
            debugPrint('[HybridSearch] 語意搜尋失敗，只用 FTS: $e');
          }
        }

        // Project-scoped 過濾（如果指定了 projectId）
        List<MemoryHit> filteredFtsMemories = ftsMemories;
        List<AssetHit> filteredFtsAssets = ftsAssets;
        List<MemoryHit> filteredSemanticMemories = semanticMemories;
        List<AssetHit> filteredSemanticAssets = semanticAssets;

        if (projectId != null) {
          final validMemoryIds = _filterMemoryIdsByProject(
            [...ftsMemories, ...semanticMemories], projectId);
          final validAssetIds = _filterAssetIdsByProject(
            [...ftsAssets, ...semanticAssets], projectId);
          filteredFtsMemories = ftsMemories
              .where((m) => validMemoryIds.contains(m.id)).toList();
          filteredFtsAssets = ftsAssets
              .where((a) => validAssetIds.contains(a.id)).toList();
          filteredSemanticMemories = semanticMemories
              .where((m) => validMemoryIds.contains(m.id)).toList();
          filteredSemanticAssets = semanticAssets
              .where((a) => validAssetIds.contains(a.id)).toList();
        }

        // RRF 融合（含 IDF 加權）
        final fusedMemories = _fuseMemoriesRRF(filteredFtsMemories, filteredSemanticMemories, query, limit: limit);
        final fusedAssets = _fuseAssetsRRF(filteredFtsAssets, filteredSemanticAssets, query, limit: limit);

        // Reranker（本地 Gemma 重排 top-N）
        // [小葵 2026-09-09 Blue 回報] hybrid 預設化後 Gemma 重排（30s 超時）
        // 讓每次搜尋卡到像當機——五因素排序已是確定性最終排序，
        // LLM 重排關閉（保留程式碼，kUseLlmRerank 開回）。
        const kUseLlmRerank = false;
        final rerankedMemories = kUseLlmRerank
            ? await _rerankMemories(query, fusedMemories)
            : fusedMemories;
        final rerankedAssets = kUseLlmRerank
            ? await _rerankAssets(query, fusedAssets)
            : fusedAssets;

        // Dedup + Cap（確保結果多樣性）
        final dedupedMemories = _dedupAndCapMemories(rerankedMemories);
        final dedupedAssets = _dedupAndCapAssets(rerankedAssets, maxPerSource: 0); // 0=無上限

        // [小葵 2026-09-09 Blue v2 檢索令] 五因素加權重排——
        // 檔名>資料夾>分類/主題>任務>語意（Blue 重要性順序）。
        // 最後一層：不改召回，只改最終排序。
        final fiveFactorAssets = FiveFactorRerank.rerank(query, dedupedAssets);

        var result = HybridSearchResults(
          memoryHits: dedupedMemories,
          assetHits: fiveFactorAssets,
        );

        // 圖譜展開（保持原有邏輯）——[M1] expand:false 時跳過（K1 通道）
        if (expand) {
          final expanded = await _expandGraph(result, limit);
          result = result.mergeWith(expanded);

          // Context expansion（鄰近段落展開）
          final contextExpanded = await _expandContext(result, limit);
          result = result.mergeWith(contextExpanded);
        }

        // [小葵 2026-09-09 Blue 令] 最終排序（五因素+類型分層：圖片>
        // 文字>其他）搬到回傳前——圖譜/上下文展開新增的命中也要過排序
        final finalAssets = FiveFactorRerank.rerank(query, result.assetHits);

        // Synthesis LLM（綜合答案生成）
        // [小葵 2026-09-09 Blue 回報 20 秒卡頓] 綜合答案是第二個 LLM 呼叫
        // ——vault 檔案搜尋用不到，關閉（聊天引用搜尋要開回 kUseSynthesis）
        const kUseSynthesis = false;
        final synthesizedAnswer = kUseSynthesis
            ? await _synthesizeAnswer(query, result)
            : null;
        return HybridSearchResults(
          memoryHits: result.memoryHits,
          assetHits: finalAssets,
          crossLinks: result.crossLinks,
          synthesizedAnswer: synthesizedAnswer,
        );
    }
  }

  // ═══════════════════════════════════════════════════
  // RRF (Reciprocal Rank Fusion) — 融合多個排名列表
  // ═══════════════════════════════════════════════════

  /// RRF (Reciprocal Rank Fusion) — 融合多個排名列表
  /// Cerebras Knowledge 證明 RRF k=60 優於 score 加權合併
  /// 公式: score(d) = Σ weight / (k + rank)
  static const int _rrfK = 60;

  List<MemoryHit> _fuseMemoriesRRF(
    List<MemoryHit> ftsHits,
    List<MemoryHit> semanticHits,
    String query, {
    int limit = 20,
  }) {
    final scores = <String, double>{};
    final hitMap = <String, MemoryHit>{};

    // FTS 排名（weight=1.0）
    for (var i = 0; i < ftsHits.length; i++) {
      final hit = ftsHits[i];
      final rank = i + 1;
      scores[hit.id] = (scores[hit.id] ?? 0) + 1.0 / (_rrfK + rank);
      hitMap[hit.id] = hit;
    }

    // 語意排名（weight=1.0）
    for (var i = 0; i < semanticHits.length; i++) {
      final hit = semanticHits[i];
      final rank = i + 1;
      scores[hit.id] = (scores[hit.id] ?? 0) + 1.0 / (_rrfK + rank);
      hitMap[hit.id] = hit;
    }

    // 按融合分數排序
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(limit).map((e) {
      final hit = hitMap[e.key]!;
      // IDF 加權：稀有詞命中加權，常見詞降權
      final idfScore = _computeIDFScore(hit.content, query);
      return MemoryHit(
        id: hit.id,
        content: hit.content,
        room: hit.room,
        score: e.value * (0.5 + 0.5 * idfScore), // RRF score * (0.5~1.0 IDF 加權)
      );
    }).toList();
  }

  List<AssetHit> _fuseAssetsRRF(
    List<AssetHit> ftsHits,
    List<AssetHit> semanticHits,
    String query, {
    int limit = 20,
  }) {
    final scores = <String, double>{};
    final hitMap = <String, AssetHit>{};

    for (var i = 0; i < ftsHits.length; i++) {
      final hit = ftsHits[i];
      final rank = i + 1;
      scores[hit.id] = (scores[hit.id] ?? 0) + 1.0 / (_rrfK + rank);
      hitMap[hit.id] = hit;
    }

    for (var i = 0; i < semanticHits.length; i++) {
      final hit = semanticHits[i];
      final rank = i + 1;
      scores[hit.id] = (scores[hit.id] ?? 0) + 1.0 / (_rrfK + rank);
      hitMap[hit.id] = hit;
    }

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(limit).map((e) {
      final hit = hitMap[e.key]!;
      // IDF 加權：稀有詞命中加權，常見詞降權
      final idfScore = _computeIDFScore(hit.summary ?? hit.fileName, query);
      return AssetHit(
        id: hit.id,
        filePath: hit.filePath,
        fileName: hit.fileName,
        title: hit.title,
        summary: hit.summary,
        assetKind: hit.assetKind,
        score: e.value * (0.5 + 0.5 * idfScore),
      );
    }).toList();
  }

  // ═══════════════════════════════════════════════════
  // 大腦搜尋（memories 表）
  // ═══════════════════════════════════════════════════

  /// [小葵 2026-09-22 FTS 中文化] 中文 bigram 關鍵詞搜尋。
  ///
  /// 查詢切 CJK bigram（「我喜歡喝什麼飲料」→ 我喜/喜歡/歡喝/喝什麼…
  /// 去停用 bigram），每筆記憶對每個 bigram 做 LIKE 命中計數，
  /// 命中數 ≥ 全部 bigram 的 1/3 才入選，按命中數排序。
  /// 停用 bigram（的什麼/喜歡這類高頻組合）不計分避免全表命中。
  List<MemoryHit> _searchMemoriesCjkBigram(String query, int limit) {
    try {
      final db = BrainDatabase.instance.db;

      // 切 bigram（只取連續 CJK 段）
      final cjkRuns = RegExp(r'[\u4e00-\u9fff]{2,}')
          .allMatches(query)
          .map((m) => m.group(0)!)
          .toList();
      final bigrams = <String>{};
      for (final run in cjkRuns) {
        for (int i = 0; i + 1 < run.length; i++) {
          bigrams.add(run.substring(i, i + 2));
        }
      }
      if (bigrams.isEmpty) return [];

      // 停用 bigram：高頻功能詞組合，命中無鑑別度
      const stopBigrams = {
        '什麼', '怎麼', '哪個', '哪些', '現在', '時候', '喜歡', '最近',
        '每天', '早上', '可以', '沒有', '這個', '那個', '我們', '他們',
        '工作', '使用', '管理', '計劃', '時要', '偏好',
      };
      final scoring = bigrams.where((b) => !stopBigrams.contains(b)).toList();
      if (scoring.isEmpty) return [];
      final minHits = (scoring.length / 3).ceil().clamp(1, scoring.length);

      // 全表掃（memories 數百筆量級）；列寬極小化只取必要欄位
      final rows = db.select(
        "SELECT id, content, room FROM memories "
        "WHERE archived = 0 AND chunk_index = 0 "
        // [小葵 2026-09-22 v18 temporal filtering] 只走現行事實
        "AND superseded_by IS NULL "
        "AND (expires_at IS NULL OR expires_at > ?)",
        [DateTime.now().millisecondsSinceEpoch],
      );

      final scored = <(MemoryHit, int)>[];
      for (final row in rows) {
        final content = (row['content'] as String?) ?? '';
        var hits = 0;
        for (final b in scoring) {
          if (content.contains(b)) hits++;
        }
        if (hits >= minHits) {
          scored.add((
            MemoryHit(
              id: row['id'] as String,
              content: content,
              room: (row['room'] as String?) ?? '',
              score: hits / scoring.length,
            ),
            hits,
          ));
        }
      }
      scored.sort((a, b) => b.$2.compareTo(a.$2));
      return scored.take(limit).map((s) => s.$1).toList();
    } catch (e) {
      return [];
    }
  }

  /// 全文搜尋大腦記憶（memories_fts FTS5）
  ///
  /// 使用 memories_fts 虛擬表進行全文搜尋，
  /// JOIN 回 memories 取得完整欄位。
  /// FTS5 失敗時 fallback 到 LIKE 搜尋。
  ///
  /// [小葵 2026-09-22 FTS 中文化] 含 CJK 的查詢改走 bigram 關鍵詞 LIKE
  /// 路徑——FTS5 unicode61 tokenizer 不分詞中文（整句=單 token），
  /// 字面不同的中文查詢永遠零命中（benchmark 首跑 25/25 全 miss 證實）。
  /// bigram 切詞容錯：詞邊界切錯（「咖啡」切在「啡杯」）照樣靠相鄰
  /// bigram 命中。memories 表數百筆量級，LIKE 掃描成本可接受。
  List<MemoryHit> _searchMemoriesFullText(String query, int limit) {
    // CJK 判定＋bigram 切詞
    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(query);
    if (hasCjk) {
      final hits = _searchMemoriesCjkBigram(query, limit);
      if (hits.isNotEmpty) return hits;
      // bigram 全 miss → 續走 FTS/LIKE fallback（英文混合詞如「Go 語言」）
    }

    try {
      final db = BrainDatabase.instance.db;
      final ftsQuery = '"$query"';

      final rows = db.select(
        "SELECT m.id, m.content, m.room, bm25(memories_fts) AS rank "
        "FROM memories_fts "
        "JOIN memories m ON m.rowid = memories_fts.rowid "
        "WHERE m.archived = 0 AND memories_fts MATCH ? "
        // [小葵 2026-09-22 v18 temporal filtering] 全文搜尋只走現行事實
        "AND m.superseded_by IS NULL "
        "AND (m.expires_at IS NULL OR m.expires_at > ?) "
        "ORDER BY rank "
        "LIMIT ?",
        [ftsQuery, DateTime.now().millisecondsSinceEpoch, limit],
      );

      return rows.map((row) {
        final rawRank = row['rank'];
        double score = 1.0;
        if (rawRank is num) {
          final absRank = rawRank.abs();
          score = absRank == 0 ? 1.0 : 1.0 / (1.0 + absRank);
        }
        return MemoryHit(
          id: row['id'] as String,
          content: row['content'] as String,
          room: row['room'] as String,
          score: score,
        );
      }).toList();
    } catch (e) {
      // FTS5 失敗時 fallback 到 LIKE
      try {
        final db = BrainDatabase.instance.db;
        final rows = db.select(
          "SELECT id, content, room FROM memories "
          "WHERE archived = 0 AND content LIKE ? "
          "ORDER BY created_at DESC LIMIT ?",
          ['%$query%', limit],
        );
        return rows.map((row) => MemoryHit(
          id: row['id'] as String,
          content: row['content'] as String,
          room: row['room'] as String,
          score: 1.0,
        )).toList();
      } catch (_) {
        return [];
      }
    }
  }

  // ═══════════════════════════════════════════════════
  // 圖書館搜尋（asset_fts 虛擬表）
  // ═══════════════════════════════════════════════════

  /// 全文搜尋圖書館檔案（FTS5 MATCH）
  ///
  /// 透過 asset_fts 虛擬表搜尋 title / summary / content_text，
  /// JOIN 回 asset_index 取得完整欄位。
  /// [小葵 2026-09-09 Blue v2 檢索令] FTS 查詢擴展——
  /// 原詞 + topic_terms 聯動詞，OR 組合（召回廣度↑，排序交給五因素）。
  String _expandFtsQuery(String query) {
    final terms = query
        .split(RegExp(r'[\s,，、/]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return '"$query"';
    final expanded = <String>{...terms};
    try {
      final db = BrainDatabase.instance.db;
      for (final t in terms) {
        // [小葵 2026-09-09] 只吃 term= 精確命中——related LIKE 會兩跳
        // 聯動（鹿角蕨→千手皇冠→朝天椒），把辣椒羅勒全炸進來
        final rows = db.select(
          'SELECT related FROM topic_terms WHERE term = ?',
          [t],
        );
        // 通用詞停用——「植物/照顧」這種詞會命中所有同屬性檔案
        // （九層塔的 [屬性: 植物] 也中），從擴展詞剃除
        const genericWords = {'植物', '照顧', 'Blue陽台', '農場', '植物照顧'};
        for (final r in rows) {
          final raw = r['related'] as String?;
          if (raw == null) continue;
          try {
            final list = jsonDecode(raw);
            if (list is List) {
              expanded.addAll(list
                  .map((e) => e.toString())
                  .where((e) => !genericWords.contains(e)));
            }
          } catch (_) {}
        }
      }
    } catch (_) {/* 詞表不可用即原詞 */}
    return expanded.map((t) => '"$t"').join(' OR ');
  }

  List<AssetHit> _searchAssetsFullText(String query, int limit,
      {bool includeTechnical = false}) {
    try {
      final db = BrainDatabase.instance.db;

      // [小葵 2026-09-09 Blue v2 檢索令] 查詢擴展——topic_terms 屬性聯動。
      // 搜「鹿角蕨」自動 OR 出品種詞（千手皇冠/雷電/…）與上層詞（植物/蕨類），
      // 灑水系統這類「沒講到鹿角蕨但同屬農業照顧」的內容也召回。
      final ftsQuery = _expandFtsQuery(query);

      final rows = db.select(
        "SELECT a.id, a.file_path, a.file_name, "
        "  a.title, a.summary, a.asset_kind, "
        "  bm25(asset_fts) AS rank "
        "FROM asset_fts "
        "JOIN asset_index a ON a.rowid = asset_fts.rowid "
        "WHERE asset_fts MATCH ? "
        "  AND (a.audience = 'general' OR ?) "
        "ORDER BY rank "
        "LIMIT ?",
        [ftsQuery, includeTechnical, limit],
      );

      return rows.map((row) {
        // bm25() 回傳負值，越小越相關；正規化為 0.0~1.0 的分數
        final rawRank = row['rank'];
        double score = 1.0;
        if (rawRank is num) {
          // bm25 越接近 0 越相關；取絕對值後倒數正規化
          final absRank = rawRank.abs();
          score = absRank == 0 ? 1.0 : 1.0 / (1.0 + absRank);
        }

        return AssetHit(
          id: row['id'] as String,
          filePath: row['file_path'] as String,
          fileName: row['file_name'] as String,
          title: row['title'] as String?,
          summary: row['summary'] as String?,
          assetKind: (row['asset_kind'] as String?) ?? 'other',
          score: score,
        );
      }).toList();
    } catch (e) {
      // DB 操作失敗時回傳空列表
      return [];
    }
  }

  // ═══════════════════════════════════════════════════
  // Phase 3：語意搜尋（向量相似度）
  // ═══════════════════════════════════════════════════

  /// 語意搜尋 — 用 EmbeddingService 將 query 轉成向量，
  /// 然後用 sqlite_vector 的 vector_full_scan 做 k-NN 搜尋。
  ///
  /// 同時搜尋 memories.embedding 和 asset_index.embedding。
  /// 如果 embedding 模型不可用，fallback 到全文搜尋。
  Future<HybridSearchResults> _searchSemantic(
    String query,
    int limit, {
    bool includeTechnical = false,
  }) async {
    final embedder = EmbeddingService.instance;
    if (!embedder.isModelAvailable) {
      // 模型不可用 → fallback 到全文
      return HybridSearchResults(
        memoryHits: _searchMemoriesFullText(query, limit),
        assetHits: _searchAssetsFullText(query, limit,
              includeTechnical: includeTechnical),
      );
    }

    // 生成 query embedding
    List<double> queryVector;
    try {
      queryVector = await embedder.embedQuery(query);
    } catch (e) {
      debugPrint('[HybridSearch] embedQuery 失敗，fallback 到全文: $e');
      return HybridSearchResults(
        memoryHits: _searchMemoriesFullText(query, limit),
        assetHits: _searchAssetsFullText(query, limit,
              includeTechnical: includeTechnical),
      );
    }

    // 零向量 = fallback 失敗
    if (queryVector.isEmpty || queryVector.every((v) => v == 0.0)) {
      return HybridSearchResults(
        memoryHits: _searchMemoriesFullText(query, limit),
        assetHits: _searchAssetsFullText(query, limit,
              includeTechnical: includeTechnical),
      );
    }

    // 同時搜尋大腦和圖書館
    final memoryHits = _searchMemoriesSemantic(queryVector, limit);
    // [小葵 2026-09-21] agent 記憶（搬家行囊）也進語意搜尋——修「向量不可達」斷點
    final agentMemoryHits = _searchAgentMemoriesSemantic(queryVector, limit);
    final assetHits = _searchAssetsSemantic(queryVector, limit,
              includeTechnical: includeTechnical);

    return HybridSearchResults(
      memoryHits: [...memoryHits, ...agentMemoryHits]
          ..sort((a, b) => b.score.compareTo(a.score)),
      assetHits: assetHits,
    );
  }

  /// 向量搜尋大腦記憶（memories.embedding）
  List<MemoryHit> _searchMemoriesSemantic(List<double> queryVector, int limit) {
    try {
      final db = BrainDatabase.instance.db;
      final vectorJson = jsonEncode(queryVector);
      final k = (limit * 3).clamp(10, 100); // 取多一些再篩選

      final rows = db.select(
        "SELECT m.id, m.content, m.room, m.created_at, v.distance "
        "FROM memories m "
        "JOIN vector_full_scan('memories', 'embedding', vector_as_f32(?), ?) AS v "
        "  ON m.rowid = v.rowid "
        "WHERE m.archived = 0 "
        // [小葵 2026-09-22 v18 temporal filtering] 語意搜尋只走現行事實
        "AND m.superseded_by IS NULL "
        "AND (m.expires_at IS NULL OR m.expires_at > ?) "
        "ORDER BY v.distance ASC "
        "LIMIT ?",
        [vectorJson, k, DateTime.now().millisecondsSinceEpoch, limit],
      );

      return rows.map((row) {
        final distance = (row['distance'] as num?)?.toDouble() ?? 1.0;
        // distance 是 cosine distance (0=完全相同, 2=完全相反)
        // 轉成相似度分數 (0.0~1.0)
        final baseScore = (1.0 - (distance / 2.0)).clamp(0.0, 1.0);
        // Age decay 加權
        final createdAt = row['created_at'] as int?;
        final decay = _computeAgeDecay(createdAt);
        return MemoryHit(
          id: row['id'] as String,
          content: row['content'] as String,
          room: row['room'] as String,
          score: baseScore * decay,
        );
      }).toList();
    } catch (e) {
      debugPrint('[HybridSearch] 大腦語意搜尋失敗: $e');
      return [];
    }
  }

  /// [小葵 2026-09-21] 向量搜尋 agent 記憶（agent_memories.embedding）
  ///
  /// 修復「搬家記憶向量不可達」斷點：Hermes 大搬家進來的 67 條記憶
  /// （含 SOUL / identity / 行囊）做過 embedding，但本服務從來只掃
  /// memories 表——agent_memories 的向量形同虛設（9/21 實測
  /// /vector_search?q=小葵的生日 memoryHits 全空抓包）。
  ///
  /// - [ownerCompanionId] 過濾歸屬（null = 全部，含 shared）
  /// - 命中以 `agent:<id>` 前綴標示來源，與 memories 表命中去重不衝突
  List<MemoryHit> _searchAgentMemoriesSemantic(List<double> queryVector,
      int limit, {String? ownerCompanionId}) {
    try {
      final db = BrainDatabase.instance.db;
      final vectorJson = jsonEncode(queryVector);
      final k = (limit * 3).clamp(10, 100);

      final ownerFilter = ownerCompanionId == null
          ? ''
          : "AND (owner_companion_id = ? OR owner_companion_id = 'shared')";
      final args = ownerCompanionId == null
          ? [vectorJson, k, limit]
          : [vectorJson, k, ownerCompanionId, limit];

      final rows = db.select(
        "SELECT m.id, m.title, m.content, m.memory_type, m.created_at, v.distance "
        "FROM agent_memories m "
        "JOIN vector_full_scan('agent_memories', 'embedding', vector_as_f32(?), ?) AS v "
        "  ON m.rowid = v.rowid "
        "WHERE m.is_archived = 0 AND m.embedding IS NOT NULL $ownerFilter "
        "ORDER BY v.distance ASC "
        "LIMIT ?",
        args,
      );

      return rows.map((row) {
        final distance = (row['distance'] as num?)?.toDouble() ?? 1.0;
        final baseScore = (1.0 - (distance / 2.0)).clamp(0.0, 1.0);
        // created_at 是 TEXT（ISO）——年齡衰減用 whenPossible 解析，失敗不衰減
        DateTime? created;
        final rawCreated = row['created_at'] as String?;
        if (rawCreated != null) {
          created = DateTime.tryParse(rawCreated);
        }
        final decay = created == null ? 1.0 : _computeAgeDecay(created.millisecondsSinceEpoch);
        final title = (row['title'] as String?) ?? '';
        final type = (row['memory_type'] as String?) ?? '';
        return MemoryHit(
          id: 'agent:${row['id'] as String}',
          content: title.isEmpty
              ? row['content'] as String
              : '[$type] $title — ${row['content'] as String}',
          room: 'agent_memory',
          score: baseScore * decay,
        );
      }).toList();
    } catch (e) {
      debugPrint('[HybridSearch] agent 記憶語意搜尋失敗: $e');
      return [];
    }
  }

  /// 向量搜尋圖書館檔案（asset_index.embedding）
  List<AssetHit> _searchAssetsSemantic(List<double> queryVector, int limit,
      {bool includeTechnical = false}) {
    try {
      final db = BrainDatabase.instance.db;
      final vectorJson = jsonEncode(queryVector);
      final k = (limit * 3).clamp(10, 100);

      // 檢查 asset_index 是否有 vector_init
      // 如果還沒初始化向量索引，vector_full_scan 會失敗
      try {
        final rows = db.select(
          "SELECT a.id, a.file_path, a.file_name, "
          "  a.title, a.summary, a.asset_kind, a.indexed_at, v.distance "
          "FROM asset_index a "
          "JOIN vector_full_scan('asset_index', 'embedding', vector_as_f32(?), ?) AS v "
          "  ON a.rowid = v.rowid "
          "WHERE a.index_status = 'indexed' AND a.embedding IS NOT NULL "
          "  AND (a.audience = 'general' OR ?) "
          "ORDER BY v.distance ASC "
          "LIMIT ?",
          // [小葵 2026-09-09] 參數順序＝SQL 文字中 ? 出現順序：
          // vector → vector_full_scan 的 k → audience 旗標 → LIMIT
          [vectorJson, k, includeTechnical, limit],
        );

        final metadataHits = rows.map((row) {
          final distance = (row['distance'] as num?)?.toDouble() ?? 1.0;
          final baseScore = (1.0 - (distance / 2.0)).clamp(0.0, 1.0);
          // Age decay 加權
          final indexedAt = row['indexed_at'] as int?;
          final decay = _computeAgeDecay(indexedAt);
          return AssetHit(
            id: row['id'] as String,
            filePath: row['file_path'] as String,
            fileName: row['file_name'] as String,
            title: row['title'] as String?,
            summary: row['summary'] as String?,
            assetKind: (row['asset_kind'] as String?) ?? 'other',
            score: baseScore * decay,
          );
        }).toList();

        // [教練 Agent 2026-08-21] 鐵三角二期 #1——chunk 內容層搜尋：
        // asset_index 嵌的是中繼 metadata（display_title/路徑/系列），
        // 長文件的「內文某一段」要靠 asset_chunks 逐片比對才找得到。
        // 策略：chunk 最佳片分數代表該檔，與 metadata 層合併去重
        // （同檔取高分），使「檔名不匹配但內文匹配」的文件現身。
        try {
          final chunkRows = db.select(
            "SELECT a.id, a.file_path, a.file_name, "
            "  a.title, a.summary, a.asset_kind, a.indexed_at, "
            "  c.chunk_id, c.chunk_index, v.distance AS cdistance "
            "FROM asset_chunks c "
            "JOIN asset_index a ON a.id = c.asset_id "
            "JOIN vector_full_scan('asset_chunks', 'embedding', vector_as_f32(?), ?) AS v "
            "  ON c.rowid = v.rowid "
            "WHERE c.embedding IS NOT NULL "
            "  AND (a.audience = 'general' OR ?) "
            "ORDER BY v.distance ASC "
            "LIMIT ?",
            // [小葵 2026-09-09] 修參數序：vector→k→audience→LIMIT
            // （原多塞 includeTechnical 導致佔位符錯位、chunk 搜尋靜默失敗）
            [vectorJson, k, includeTechnical, limit],
            );
          for (final row in chunkRows) {
            final distance = (row['cdistance'] as num?)?.toDouble() ?? 1.0;
            final baseScore = (1.0 - (distance / 2.0)).clamp(0.0, 1.0);
            final decay = _computeAgeDecay(row['indexed_at'] as int?);
            final hit = AssetHit(
              id: row['id'] as String,
              filePath: row['file_path'] as String,
              fileName: row['file_name'] as String,
              title: row['title'] as String?,
              summary:
                  '【內文命中】${(row['chunk_id'] as String?) ?? ''} 第 ${(row['chunk_index'] as int?) ?? 0} 片',
              assetKind: (row['asset_kind'] as String?) ?? 'other',
              score: baseScore * decay,
            );
            final existing = metadataHits.indexWhere((h) => h.id == hit.id);
            if (existing >= 0) {
              // 同檔取高分（內文命中 vs metadata 命中）
              if (hit.score > metadataHits[existing].score) {
                metadataHits[existing] = hit;
              }
            } else {
              metadataHits.add(hit);
            }
          }
          metadataHits.sort((a, b) => b.score.compareTo(a.score));
        } catch (e) {
          // chunk 表可能還沒初始化/沒資料——不影響主流程
        }

        return metadataHits;
      } catch (e) {
        // asset_index 的 vector_init 可能還沒執行
        debugPrint('[HybridSearch] 圖書館向量搜尋未就緒（可能尚無 embedding）: $e');
        return [];
      }
    } catch (e) {
      debugPrint('[HybridSearch] 圖書館語意搜尋失敗: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════
  // Phase 5：圖譜展開 + 跨島聯想
  // ═══════════════════════════════════════════════════

  /// 圖譜展開 — 沿交叉引用找到更多關聯結果
  ///
  /// 設計文件 §5.3 跨島聯想流程：
  /// Step 1: 命中的記憶 → 查 memory_asset_links → 找到關聯檔案
  /// Step 2: 命中的檔案 → 查 memory_asset_links → 找到關聯記憶
  /// Step 3: 找到的記憶之間，用向量距離找出跨房間的隱藏關聯
  Future<HybridSearchResults> _expandGraph(
    HybridSearchResults initial,
    int limit,
  ) async {
    if (initial.memoryHits.isEmpty && initial.assetHits.isEmpty) {
      return const HybridSearchResults();
    }

    final newMemoryHits = <MemoryHit>[];
    final newAssetHits = <AssetHit>[];
    final crossLinks = <CrossLinkInfo>[];

    final existingMemoryIds = initial.memoryHits.map((m) => m.id).toSet();
    final existingAssetIds = initial.assetHits.map((a) => a.id).toSet();

    try {
      final db = BrainDatabase.instance.db;

      // Step 1: 命中的記憶 → 查 memory_asset_links → 找到關聯檔案
      if (initial.memoryHits.isNotEmpty) {
        final memoryIds = initial.memoryHits.map((m) => m.id).toList();
        final placeholders = memoryIds.map((_) => '?').join(',');

        final rows = db.select(
          'SELECT mal.memory_id, mal.asset_id, mal.link_type, mal.note, '
          '  a.id as asset_idx, a.file_path, a.file_name, a.title, a.summary, a.asset_kind '
          'FROM memory_asset_links mal '
          'JOIN asset_index a ON a.id = mal.asset_id '
          'WHERE mal.memory_id IN ($placeholders)',
          memoryIds,
        );

        for (final row in rows) {
          final assetId = row['asset_id'] as String;
          final memoryId = row['memory_id'] as String;
          final linkType = row['link_type'] as String? ?? 'referenced';

          // 記錄交叉引用
          crossLinks.add(CrossLinkInfo(
            memoryId: memoryId,
            assetId: assetId,
            linkType: linkType,
            note: row['note'] as String?,
          ));

          // 如果檔案還不在結果裡，加入
          if (!existingAssetIds.contains(assetId)) {
            newAssetHits.add(AssetHit(
              id: assetId,
              filePath: row['file_path'] as String,
              fileName: row['file_name'] as String,
              title: row['title'] as String?,
              summary: row['summary'] as String?,
              assetKind: (row['asset_kind'] as String?) ?? 'other',
              // 圖譜展開的命中分數較低（不是直接搜尋命中）
              score: 0.3,
            ));
            existingAssetIds.add(assetId);
          }
        }
      }

      // Step 2: 命中的檔案 → 查 memory_asset_links → 找到關聯記憶
      if (initial.assetHits.isNotEmpty) {
        final assetIds = initial.assetHits.map((a) => a.id).toList();
        final placeholders = assetIds.map((_) => '?').join(',');

        final rows = db.select(
          'SELECT mal.memory_id, mal.asset_id, mal.link_type, mal.note, '
          '  m.id as mem_id, m.content, m.room '
          'FROM memory_asset_links mal '
          'JOIN memories m ON m.id = mal.memory_id '
          'WHERE mal.asset_id IN ($placeholders) AND m.archived = 0',
          assetIds,
        );

        for (final row in rows) {
          final memoryId = row['mem_id'] as String;
          final assetId = row['asset_id'] as String;
          final linkType = row['link_type'] as String? ?? 'referenced';

          // 記錄交叉引用
          crossLinks.add(CrossLinkInfo(
            memoryId: memoryId,
            assetId: assetId,
            linkType: linkType,
            note: row['note'] as String?,
          ));

          // 如果記憶還不在結果裡，加入
          if (!existingMemoryIds.contains(memoryId)) {
            newMemoryHits.add(MemoryHit(
              id: memoryId,
              content: row['content'] as String,
              room: row['room'] as String,
              score: 0.3, // 圖譜展開命中，較低分
            ));
            existingMemoryIds.add(memoryId);
          }
        }
      }

      // Step 3: 跨島聯想 — 在命中的記憶之間找跨房間的向量近鄰
      final crossIslandHits = await _findCrossIslandAssociations(
        initial.memoryHits,
        existingMemoryIds,
        limit,
      );
      newMemoryHits.addAll(crossIslandHits);

      if (newMemoryHits.isNotEmpty || newAssetHits.isNotEmpty) {
        debugPrint('[HybridSearch] 圖譜展開: '
            '+${newMemoryHits.length} 記憶, +${newAssetHits.length} 檔案, '
            '${crossLinks.length} 交叉引用, '
            '${crossIslandHits.length} 跨島聯想');
      }

      return HybridSearchResults(
        memoryHits: newMemoryHits,
        assetHits: newAssetHits,
        crossLinks: crossLinks,
      );
    } catch (e) {
      debugPrint('[HybridSearch] 圖譜展開失敗: $e');
      return const HybridSearchResults();
    }
  }

  /// 跨島聯想 — 找出跟命中記憶語意相近但房間不同的記憶
  ///
  /// 這是「跨島聯想」的核心：表面不相關（不同房間），語意有關（向量距離近）。
  /// 只在 embedding 模型可用時執行。
  Future<List<MemoryHit>> _findCrossIslandAssociations(
    List<MemoryHit> baseHits,
    Set<String> excludeIds,
    int limit,
  ) async {
    if (baseHits.isEmpty) return [];

    final embedder = EmbeddingService.instance;
    if (!embedder.isModelAvailable) return [];

    final crossIslandHits = <MemoryHit>[];

    try {
      // 對每條命中的記憶，找它的 embedding，
      // 然後搜尋其他房間裡向量相近的記憶
      final db = BrainDatabase.instance.db;

      for (final hit in baseHits.take(5)) {
        // 取得這條記憶的 embedding
        final memRows = db.select(
          "SELECT embedding, room FROM memories WHERE id = ? AND embedding IS NOT NULL",
          [hit.id],
        );
        if (memRows.isEmpty) continue;

        final embedding = memRows.first['embedding'];
        if (embedding == null) continue;

        final memRoom = memRows.first['room'] as String? ?? '';

        // 用這條記憶的向量搜尋 k-NN，找不同房間的近鄰
        try {
          final k = (limit).clamp(5, 20);
          final rows = db.select(
            "SELECT m.id, m.content, m.room, v.distance "
            "FROM memories m "
            "JOIN vector_full_scan('memories', 'embedding', vector_as_f32(?), ?) AS v "
            "  ON m.rowid = v.rowid "
            "WHERE m.archived = 0 AND m.room != ? AND m.id NOT IN "
            "  (${excludeIds.map((_) => '?').join(',')}) "
            "ORDER BY v.distance ASC "
            "LIMIT ?",
            [
              embedding is String
                  ? embedding
                  : jsonEncode(embedding),
              k,
              memRoom,
              ...excludeIds,
              3, // 每條記憶最多帶出 3 個跨島聯想
            ],
          );

          for (final row in rows) {
            final id = row['id'] as String;
            if (excludeIds.contains(id)) continue;
            excludeIds.add(id);

            final distance = (row['distance'] as num?)?.toDouble() ?? 1.0;
            // 跨島聯想的分數較低（這是隱藏關聯，不是直接命中）
            final score = (1.0 - (distance / 2.0)).clamp(0.0, 1.0) * 0.5;

            // 只保留有一定相似度的
            if (score < 0.2) continue;

            crossIslandHits.add(MemoryHit(
              id: id,
              content: row['content'] as String,
              room: row['room'] as String,
              score: score,
            ));
          }
        } catch (e) {
          // vector_full_scan 可能失敗（embedding 格式問題等）
          continue;
        }
      }
    } catch (e) {
      debugPrint('[HybridSearch] 跨島聯想失敗: $e');
    }

    return crossIslandHits;
  }

  // ═══════════════════════════════════════════════════
  // Cerebras Knowledge 啟發的進階搜尋改進
  // ═══════════════════════════════════════════════════

  // ── 改進 1: IDF 過濾（噪音抑制） ──

  /// IDF (Inverse Document Frequency) 過濾
  /// Cerebras Knowledge 證明：高頻低信號內容會污染搜尋結果
  /// 對太短或太常見的記憶/檔案降權
  double _computeIDFScore(String content, String query) {
    // 簡化版 IDF：檢查 query 詞在 content 中是否罕見
    final queryTerms = query.toLowerCase().split(RegExp(r'\s+'));
    final contentLower = content.toLowerCase();

    double idfSum = 0.0;
    int matchCount = 0;

    for (final term in queryTerms) {
      if (term.isEmpty) continue;
      final count = _countOccurrences(contentLower, term);
      if (count > 0) {
        matchCount++;
        // 出現次數越少越珍貴（簡化版 IDF）
        idfSum += 1.0 / (1.0 + count.toDouble());
      }
    }

    // 沒有任何 query 詞命中 → IDF = 0
    if (matchCount == 0) return 0.0;

    // 正規化為 0.0~1.0
    return (idfSum / matchCount).clamp(0.0, 1.0);
  }

  /// 計算子字串出現次數
  int _countOccurrences(String text, String pattern) {
    if (pattern.isEmpty) return 0;
    int count = 0;
    int pos = 0;
    while ((pos = text.indexOf(pattern, pos)) != -1) {
      count++;
      pos += pattern.length;
    }
    return count;
  }

  // ── 改進 2: Age Decay（時間衰減） ──

  /// Age decay — 舊內容降權
  /// Cerebras Knowledge 證明：舊內容描述的可能已過時
  /// 公式: decay = 1 / (1 + age_days / half_life_days)
  /// half_life = 90 天（3 個月後影響力減半）
  static const int _ageDecayHalfLifeDays = 90;

  double _computeAgeDecay(int? timestampMs) {
    if (timestampMs == null || timestampMs == 0) return 1.0; // 無時間資訊不懲罰

    final ageMs = DateTime.now().millisecondsSinceEpoch - timestampMs;
    final ageDays = ageMs / (1000 * 60 * 60 * 24);

    if (ageDays <= 0) return 1.0; // 未來時間不懲罰

    // 指數衰減：half_life 天後影響力減半
    return 1.0 / (1.0 + ageDays / _ageDecayHalfLifeDays);
  }

  // ── 改進 3: Reranker（交叉編碼器重排） ──

  /// 用本地 Gemma 模型做 reranker
  /// Cerebras Knowledge 證明：cross-encoder 重排 top-k 提升精準度
  /// 對 top-N 結果用 LLM 打分 0-10，重新排序
  Future<List<MemoryHit>> _rerankMemories(
    String query,
    List<MemoryHit> hits, {
    int keepTop = 10,
  }) async {
    if (hits.length <= keepTop) return hits;

    // 取 top 20 候選（避免送太多給 LLM）
    final candidates = hits.take(20).toList();

    // 建構 reranker prompt
    final candidatesText = candidates.asMap().entries.map((e) {
      final idx = e.key + 1;
      final content = e.value.content.length > 200
          ? '${e.value.content.substring(0, 200)}...'
          : e.value.content;
      return '$idx. $content';
    }).join('\n');

    final prompt = '請對以下搜尋結果按照與查詢的相關性打分（0-10分，10分最相關）。'
        '只輸出編號和分數，每行一個，格式：編號:分數\n\n'
        '查詢: $query\n\n'
        '結果:\n$candidatesText';

    try {
      final response = await Dio().post(
        'http://127.0.0.1:18789/v1/chat/completions',
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
        data: {
          'model': 'gemma-4-e4b',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'stream': false,
          'max_tokens': 300,
          'temperature': 0.1,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final text = data['choices']?[0]?['message']?['content'] as String? ?? '';

        // 解析分數
        final scores = <int, double>{}; // index -> score
        for (final line in text.split('\n')) {
          final match = RegExp(r'(\d+)\s*[:：]\s*(\d+(?:\.\d+)?)').firstMatch(line);
          if (match != null) {
            final idx = int.parse(match.group(1)!) - 1;
            final score = double.parse(match.group(2)!);
            if (idx >= 0 && idx < candidates.length) {
              scores[idx] = score;
            }
          }
        }

        // 用 LLM 分數重排
        final reranked = candidates.asMap().entries.toList()
          ..sort((a, b) {
            final sa = scores[a.key] ?? 5.0;
            final sb = scores[b.key] ?? 5.0;
            return sb.compareTo(sa);
          });

        return reranked.take(keepTop).map((e) {
          final hit = e.value;
          final llmScore = scores[e.key] ?? 5.0;
          return MemoryHit(
            id: hit.id,
            content: hit.content,
            room: hit.room,
            score: llmScore / 10.0, // 正規化為 0.0~1.0
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('[HybridSearch] Memory reranker 失敗，保留原排序: $e');
    }

    // fallback: 保留原排序，只取 keepTop 個
    return hits.take(keepTop).toList();
  }

  /// Reranker for AssetHit
  Future<List<AssetHit>> _rerankAssets(
    String query,
    List<AssetHit> hits, {
    int keepTop = 10,
  }) async {
    if (hits.length <= keepTop) return hits;

    final candidates = hits.take(20).toList();

    final candidatesText = candidates.asMap().entries.map((e) {
      final idx = e.key + 1;
      final text = e.value.summary ?? e.value.title ?? e.value.fileName;
      return '$idx. $text';
    }).join('\n');

    final prompt = '請對以下搜尋結果按照與查詢的相關性打分（0-10分，10分最相關）。'
        '只輸出編號和分數，每行一個，格式：編號:分數\n\n'
        '查詢: $query\n\n'
        '結果:\n$candidatesText';

    try {
      final response = await Dio().post(
        'http://127.0.0.1:18789/v1/chat/completions',
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
        data: {
          'model': 'gemma-4-e4b',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'stream': false,
          'max_tokens': 300,
          'temperature': 0.1,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final text = data['choices']?[0]?['message']?['content'] as String? ?? '';

        final scores = <int, double>{};
        for (final line in text.split('\n')) {
          final match = RegExp(r'(\d+)\s*[:：]\s*(\d+(?:\.\d+)?)').firstMatch(line);
          if (match != null) {
            final idx = int.parse(match.group(1)!) - 1;
            final score = double.parse(match.group(2)!);
            if (idx >= 0 && idx < candidates.length) {
              scores[idx] = score;
            }
          }
        }

        final reranked = candidates.asMap().entries.toList()
          ..sort((a, b) {
            final sa = scores[a.key] ?? 5.0;
            final sb = scores[b.key] ?? 5.0;
            return sb.compareTo(sa);
          });

        return reranked.take(keepTop).map((e) {
          final hit = e.value;
          final llmScore = scores[e.key] ?? 5.0;
          return AssetHit(
            id: hit.id,
            filePath: hit.filePath,
            fileName: hit.fileName,
            title: hit.title,
            summary: hit.summary,
            assetKind: hit.assetKind,
            score: llmScore / 10.0,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('[HybridSearch] Asset reranker 失敗，保留原排序: $e');
    }

    return hits.take(keepTop).toList();
  }

  // ── 改進 4: Context Expansion（鄰近段落展開） ──

  /// Context expansion — 展開搜尋結果的鄰近內容
  /// Cerebras Knowledge 證明：單一 chunk 缺少上下文
  /// 對 asset 命中：查同一資料夾的鄰近檔案
  /// 對 memory 命中：查同一房間的時間相鄰記憶
  Future<HybridSearchResults> _expandContext(
    HybridSearchResults results,
    int limit,
  ) async {
    if (results.assetHits.isEmpty && results.memoryHits.isEmpty) {
      return const HybridSearchResults();
    }

    final expandedAssets = <AssetHit>[];
    final expandedMemories = <MemoryHit>[];
    final existingAssetIds = results.assetHits.map((a) => a.id).toSet();
    final existingMemoryIds = results.memoryHits.map((m) => m.id).toSet();

    try {
      final db = BrainDatabase.instance.db;

      // 對 asset 命中：查同一 folder_root 的鄰近檔案
      for (final hit in results.assetHits.take(5)) {
        try {
          // 從 asset_index 找同一 folder_root 的檔案
          final rows = db.select(
            "SELECT id, file_path, file_name, title, summary, asset_kind "
            "FROM asset_index "
            "WHERE file_path LIKE ? AND id != ? "
            "ORDER BY file_name ASC "
            "LIMIT 3",
            ['${hit.filePath.split('/').first}/%', hit.id],
          );

          for (final row in rows) {
            final id = row['id'] as String;
            if (!existingAssetIds.contains(id)) {
              expandedAssets.add(AssetHit(
                id: id,
                filePath: row['file_path'] as String,
                fileName: row['file_name'] as String,
                title: row['title'] as String?,
                summary: row['summary'] as String?,
                assetKind: (row['asset_kind'] as String?) ?? 'other',
                score: hit.score * 0.3, // 展開結果分數較低
              ));
              existingAssetIds.add(id);
            }
          }
        } catch (_) {}
      }

      // 對 memory 命中：查同一房間的時間相鄰記憶
      for (final hit in results.memoryHits.take(5)) {
        try {
          final rows = db.select(
            "SELECT id, content, room "
            "FROM memories "
            "WHERE room = ? AND archived = 0 AND id != ? "
            "ORDER BY ABS(created_at - "
            "  (SELECT created_at FROM memories WHERE id = ?)) ASC "
            "LIMIT 2",
            [hit.room, hit.id, hit.id],
          );

          for (final row in rows) {
            final id = row['id'] as String;
            if (!existingMemoryIds.contains(id)) {
              expandedMemories.add(MemoryHit(
                id: id,
                content: row['content'] as String,
                room: row['room'] as String,
                score: hit.score * 0.3,
              ));
              existingMemoryIds.add(id);
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[HybridSearch] Context expansion 失敗: $e');
    }

    if (expandedAssets.isEmpty && expandedMemories.isEmpty) {
      return const HybridSearchResults();
    }

    debugPrint('[HybridSearch] Context expansion: '
        '+${expandedMemories.length} 鄰近記憶, +${expandedAssets.length} 鄰近檔案');

    return HybridSearchResults(
      memoryHits: expandedMemories,
      assetHits: expandedAssets,
    );
  }

  // ═══════════════════════════════════════════════════
  // 改進 A: Dedup + Cap（結果多樣性）
  // ═══════════════════════════════════════════════════

  /// Dedup + Cap — 確保結果多樣性
  /// Cerebras Knowledge 證明：單一檔案/記憶不該佔滿搜尋結果
  /// 每個 file_path / memory 最多保留 maxPerSource 個結果
  List<MemoryHit> _dedupAndCapMemories(List<MemoryHit> hits, {int maxPerSource = 3}) {
    // memories 用 content 前 100 字做 dedup key
    final seenContentPrefixes = <String>{};
    final sourceCount = <String, int>{}; // room 為 source key
    final result = <MemoryHit>[];

    for (final hit in hits) {
      final prefix = hit.content.length > 100
          ? hit.content.substring(0, 100)
          : hit.content;

      // dedup：跳過內容前綴相同的
      if (seenContentPrefixes.contains(prefix)) continue;
      seenContentPrefixes.add(prefix);

      // cap：同一 room 最多 maxPerSource 個
      final roomCount = sourceCount[hit.room] ?? 0;
      if (roomCount >= maxPerSource) continue;
      sourceCount[hit.room] = roomCount + 1;

      result.add(hit);
    }

    return result;
  }

  List<AssetHit> _dedupAndCapAssets(List<AssetHit> hits, {int maxPerSource = 3}) {
    final seenPaths = <String>{};
    final folderCount = <String, int>{}; // folder 為 source key
    final result = <AssetHit>[];

    for (final hit in hits) {
      // dedup：跳過相同 file_path
      if (seenPaths.contains(hit.filePath)) continue;
      seenPaths.add(hit.filePath);

      // cap：同一資料夾最多 maxPerSource 個
      // [小葵 2026-09-09 Blue 令：搜尋無上限] 原本 maxPerSource=3 且以
      // 頂層資料夾為單位——整個農場照片被壓到 3 筆、品種全滅。
      // 改為無上限（保留 path 去重即可）。
      final folder = hit.filePath.contains('/')
          ? hit.filePath.split('/').first
          : hit.filePath;
      final count = folderCount[folder] ?? 0;
      if (maxPerSource > 0 && count >= maxPerSource) continue;
      folderCount[folder] = count + 1;

      result.add(hit);
    }

    return result;
  }

  // ═══════════════════════════════════════════════════
  // 改進 D: Project-scoped Search
  // ═══════════════════════════════════════════════════

  /// 批量檢查記憶的 project
  Set<String> _filterMemoryIdsByProject(List<MemoryHit> hits, String projectId) {
    if (hits.isEmpty) return {};
    try {
      final db = BrainDatabase.instance.db;
      final ids = hits.map((h) => h.id).toList();
      final placeholders = ids.map((_) => '?').join(',');
      final rows = db.select(
        "SELECT id FROM memories WHERE id IN ($placeholders) AND project = ?",
        [...ids, projectId],
      );
      return rows.map((r) => r['id'] as String).toSet();
    } catch (_) {
      return hits.map((h) => h.id).toSet(); // 失敗時不過濾
    }
  }

  /// 批量檢查檔案的 project_id
  Set<String> _filterAssetIdsByProject(List<AssetHit> hits, String projectId) {
    if (hits.isEmpty) return {};
    try {
      final db = BrainDatabase.instance.db;
      final ids = hits.map((h) => h.id).toList();
      final placeholders = ids.map((_) => '?').join(',');
      final rows = db.select(
        "SELECT id FROM asset_index WHERE id IN ($placeholders) AND project_id = ?",
        [...ids, projectId],
      );
      return rows.map((r) => r['id'] as String).toSet();
    } catch (_) {
      return hits.map((h) => h.id).toSet(); // 失敗時不過濾
    }
  }

  // ═══════════════════════════════════════════════════
  // 改進 B: Synthesis LLM（綜合答案生成）
  // ═══════════════════════════════════════════════════

  /// Synthesis LLM — 用本地 Gemma 生成綜合答案
  /// Cerebras Knowledge 證明：最終 LLM 讀所有檢索結果生成答案 + 引用 + 衝突標注
  /// 讀取所有 hits → LLM 生成附引用的答案
  Future<String?> _synthesizeAnswer(
    String query,
    HybridSearchResults results,
  ) async {
    if (results.memoryHits.isEmpty && results.assetHits.isEmpty) {
      return null;
    }

    // 收集證據
    final evidence = <String>[];

    for (var i = 0; i < results.memoryHits.take(10).length; i++) {
      final hit = results.memoryHits[i];
      final content = hit.content.length > 300
          ? '${hit.content.substring(0, 300)}...'
          : hit.content;
      evidence.add('[記憶${i + 1}] (房間: ${hit.room}) $content');
    }

    for (var i = 0; i < results.assetHits.take(10).length; i++) {
      final hit = results.assetHits[i];
      final text = hit.summary ?? hit.title ?? hit.fileName;
      evidence.add('[檔案${i + 1}] (${hit.fileName}) $text');
    }

    final evidenceText = evidence.join('\n');

    final prompt = '以下是針對查詢「$query」的搜尋結果。'
        '請根據這些結果生成一個綜合答案。\n'
        '要求：\n'
        '1. 引用來源（如 [記憶1]、[檔案2]）\n'
        '2. 如果來源之間有矛盾，標注出來\n'
        '3. 如果資訊不足，說明缺什麼\n'
        '4. 用繁體中文回答\n\n'
        '搜尋結果:\n$evidenceText';

    try {
      final response = await Dio().post(
        'http://127.0.0.1:18789/v1/chat/completions',
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
        data: {
          'model': 'gemma-4-e4b',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'stream': false,
          'max_tokens': 500,
          'temperature': 0.3,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final answer = data['choices']?[0]?['message']?['content'] as String? ?? '';
        if (answer.trim().isNotEmpty) {
          return answer.trim();
        }
      }
    } catch (e) {
      debugPrint('[HybridSearch] Synthesis LLM 失敗: $e');
    }

    return null;
  }
}
