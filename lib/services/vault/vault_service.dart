// vault_service.dart
// 向量資料庫服務 — 搜尋 API（全文 + 語意 + 標籤）+ wiki-link 解析
// [教練 Agent 2026-07-22] Phase 1 ②
//
// 這是 Vault 頁面和畫布側欄共用的搜尋入口。
// 底層使用 BrainDatabase 的 SQLite + sqlite_vector。

import 'dart:convert';

import 'package:bridge_app/models/brain_container/memory.dart';
import 'package:bridge_app/services/brain_container/brain_database.dart';
import 'package:bridge_app/services/brain_container/embedding/embedding_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:sqlite3/sqlite3.dart' show Database;
import 'dart:ui' show Offset;

/// 搜尋模式
enum VaultSearchMode {
  /// 全文搜尋（LIKE '%keyword%'）
  fullText,

  /// 語意搜尋（embedding cosine similarity）
  semantic,

  /// 標籤篩選
  tag,

  /// [教練 Agent 2026-07-25] 混合搜尋（全文 + 語意 + 圖譜展開 + 跨島聯想）
  hybrid,
}

/// Vault 條目 — 資料庫條目的完整表示
class VaultEntry {
  final String id;
  final String content;
  final String room;
  final String subCategory;
  final String agent;
  final String source;
  final String project;
  final List<String> tags;
  final int importance;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int accessCount;
  final bool archived;

  /// 連結數（outgoing wiki-links）
  final int linkCount;

  /// Backlink 數（incoming wiki-links）
  final int backlinkCount;

  VaultEntry({
    required this.id,
    required this.content,
    required this.room,
    required this.subCategory,
    required this.agent,
    required this.source,
    required this.project,
    required this.tags,
    required this.importance,
    required this.createdAt,
    required this.updatedAt,
    required this.accessCount,
    required this.archived,
    this.linkCount = 0,
    this.backlinkCount = 0,
  });

  factory VaultEntry.fromMap(Map<String, dynamic> map) {
    List<String> tags;
    try {
      tags = (jsonDecode(map['tags'] as String? ?? '[]') as List)
          .cast<String>();
    } catch (_) {
      tags = [];
    }

    return VaultEntry(
      id: map['id'] as String? ?? '',
      content: map['content'] as String? ?? '',
      room: map['room'] as String? ?? '',
      subCategory: map['sub_category'] as String? ?? '',
      agent: map['agent'] as String? ?? '',
      source: map['source'] as String? ?? '',
      project: map['project'] as String? ?? '',
      tags: tags,
      importance: (map['importance'] as int?) ?? 3,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as int?) ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['updated_at'] as int?) ?? 0),
      accessCount: (map['access_count'] as int?) ?? 0,
      archived: (map['archived'] as int?) == 1,
      linkCount: (map['link_count'] as int?) ?? 0,
      backlinkCount: (map['backlink_count'] as int?) ?? 0,
    );
  }

  /// 條目摘要（前 100 字）
  String get summary {
    if (content.length <= 100) return content;
    return '${content.substring(0, 100)}...';
  }

  /// 條目類型（從 source 推導）
  String get typeLabel {
    switch (source) {
      case 'chat':
        return '記憶';
      case 'agent_perception':
        return '感知';
      case 'system_sop':
        return 'SOP';
      case 'knowledge_base':
        return '知識';
      case 'sub_analysis':
        return '子分析';
      default:
        return '條目';
    }
  }
}

/// Wiki-link 連結資訊
class WikiLinkInfo {
  final String id;
  final String sourceMemoryId;
  final String targetMemoryId;
  final String linkText;
  final DateTime createdAt;

  WikiLinkInfo({
    required this.id,
    required this.sourceMemoryId,
    required this.targetMemoryId,
    required this.linkText,
    required this.createdAt,
  });

  factory WikiLinkInfo.fromMap(Map<String, dynamic> map) {
    return WikiLinkInfo(
      id: map['id'] as String? ?? '',
      sourceMemoryId: map['source_memory'] as String? ?? '',
      targetMemoryId: map['target_memory'] as String? ?? '',
      linkText: map['link_text'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as int?) ?? 0),
    );
  }
}

/// 圖譜節點
class VaultGraphNode {
  final String id;
  final String label;
  final String room;
  final String source;
  final int importance;
  final int linkCount;
  final int backlinkCount;

  /// [教練 Agent 2026-07-25] Phase 4 — 節點類型：memory 或 asset
  final String nodeType; // 'memory' 或 'asset'

  /// [教練 Agent 2026-07-25] Phase 4 — 檔案類型（asset 節點用）
  final String? assetKind;

  /// 佈局計算後的位置（由 GraphView widget 填充）
  Offset? position;

  /// 佈局計算後的速度
  Offset? velocity;

  VaultGraphNode({
    required this.id,
    required this.label,
    required this.room,
    required this.source,
    required this.importance,
    required this.linkCount,
    required this.backlinkCount,
    this.nodeType = 'memory',
    this.assetKind,
    this.position,
    this.velocity,
  });

  /// 節點顏色（依 source 類型）
  Color get color {
    // [教練 Agent 2026-07-25] Phase 4 — 檔案節點用藍色
    if (nodeType == 'asset') {
      return const Color(0xFF4A9EFF); // 檔案 — 藍色
    }
    switch (source) {
      case 'chat':
        return const Color(0xFF7C89FF); // 記憶 — 藍紫
      case 'agent_perception':
        return const Color(0xFF4ECDC4); // 感知 — 青綠
      case 'system_sop':
        return const Color(0xFFFFB454); // SOP — 橙黃
      case 'knowledge_base':
        return const Color(0xFFB388FF); // 知識 — 紫
      case 'sub_analysis':
        return const Color(0xFFFF6B9D); // 子分析 — 粉紅
      default:
        return const Color(0xFF8E9AAF); // 預設 — 灰
    }
  }

  /// 節點半徑（依 importance + 連結數）
  double get radius {
    var r = 12.0 + (importance - 3) * 3.0;
    r += (linkCount + backlinkCount) * 1.5;
    return r.clamp(10.0, 32.0);
  }
}

/// 圖譜邊
class VaultGraphEdge {
  final String id;
  final String source;
  final String target;
  final String label;

  VaultGraphEdge({
    required this.id,
    required this.source,
    required this.target,
    required this.label,
  });
}

/// 圖譜資料（節點 + 邊）
class VaultGraphData {
  final List<VaultGraphNode> nodes;
  final List<VaultGraphEdge> edges;

  VaultGraphData({required this.nodes, required this.edges});

  factory VaultGraphData.empty() => VaultGraphData(nodes: [], edges: []);

  bool get isEmpty => nodes.isEmpty;
}

/// 向量資料庫服務（單例）
///
/// 提供：
/// 1. 三模式搜尋（全文 / 語意 / 標籤）
/// 2. 條目 CRUD
/// 3. Wiki-link 解析與查詢
/// 4. 標籤統計
class VaultService {
  VaultService._();
  static final VaultService instance = VaultService._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// 搜尋條目。
  ///
  /// [mode] 搜尋模式
  /// [query] 搜尋關鍵字或自然語言查詢
  /// [roomFilter] 可選，只搜特定房間
  /// [tagFilter] 可選，只搜帶特定標籤的條目
  /// [limit] 最大結果數
  /// [offset] 分頁偏移
  Future<List<VaultEntry>> search({
    required VaultSearchMode mode,
    String query = '',
    String? roomFilter,
    List<String>? tagFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) return [];

    try {
      final db = BrainDatabase.instance.db;

      switch (mode) {
        case VaultSearchMode.fullText:
          return _searchFullText(db, query, roomFilter, tagFilter, limit, offset);

        case VaultSearchMode.semantic:
          return _searchSemantic(db, query, roomFilter, tagFilter, limit);

        case VaultSearchMode.tag:
          return _searchByTag(db, tagFilter, roomFilter, limit, offset);

        case VaultSearchMode.hybrid:
          // [教練 Agent 2026-07-25] hybrid 由 VaultScreen 直接呼叫 HybridSearchService
          // 如果走到這裡，降級為全文搜尋
          return _searchFullText(db, query, roomFilter, tagFilter, limit, offset);
      }
    } catch (e) {
      debugPrint('[VaultService] search 失敗: $e');
      return [];
    }
  }

  /// 全文搜尋（LIKE）
  ///
  /// 設計文件決策 #5：先用 LIKE，後 FTS5。
  /// LIKE 搜尋 content 欄位，大小寫不敏感（SQLite 預設對 ASCII 不敏感）。
  List<VaultEntry> _searchFullText(
    Database db,
    String query,
    String? roomFilter,
    List<String>? tagFilter,
    int limit,
    int offset,
  ) {
    final whereParts = <String>['archived = 0'];
    final params = <Object?>[];

    if (query.isNotEmpty) {
      whereParts.add('content LIKE ?');
      params.add('%$query%');
    }

    if (roomFilter != null && roomFilter.isNotEmpty) {
      whereParts.add('room = ?');
      params.add(roomFilter);
    }

    if (tagFilter != null && tagFilter.isNotEmpty) {
      // 標籤以 JSON array 存儲，用 LIKE 模糊匹配
      final tagConditions = tagFilter.map((tag) {
        params.add('%"$tag"%');
        return 'tags LIKE ?';
      }).join(' OR ');
      whereParts.add('($tagConditions)');
    }

    final whereClause = whereParts.join(' AND ');
    params.add(limit);
    params.add(offset);

    final rows = db.select(
      'SELECT m.*, '
      '  (SELECT COUNT(*) FROM wiki_links w WHERE w.source_memory = m.id) AS link_count, '
      '  (SELECT COUNT(*) FROM wiki_links w WHERE w.target_memory = m.id) AS backlink_count '
      'FROM memories m '
      'WHERE $whereClause '
      'ORDER BY created_at DESC '
      'LIMIT ? OFFSET ?',
      params,
    );

    return rows.map<VaultEntry>((r) => VaultEntry.fromMap(r)).toList();
  }

  /// 語意搜尋（embedding cosine similarity）
  ///
  /// 使用 EmbeddingService 將 query 轉成向量，
  /// 再用 vector_full_scan 做 k-NN 搜尋。
  Future<List<VaultEntry>> _searchSemantic(
    Database db,
    String query,
    String? roomFilter,
    List<String>? tagFilter,
    int limit,
  ) async {
    if (query.isEmpty) return [];

    // 生成 query embedding
    final embedder = EmbeddingService.instance;
    if (!embedder.isModelAvailable) {
      // fallback 到全文搜尋
      return _searchFullText(db, query, roomFilter, tagFilter, limit, 0);
    }

    List<double> queryVector;
    try {
      queryVector = await embedder.embedQuery(query);
    } catch (e) {
      debugPrint('[VaultService] embedQuery 失敗，fallback 到全文: $e');
      return _searchFullText(db, query, roomFilter, tagFilter, limit, 0);
    }
    if (queryVector.isEmpty || queryVector.every((v) => v == 0.0)) {
      return _searchFullText(db, query, roomFilter, tagFilter, limit, 0);
    }

    final whereParts = <String>['m.archived = 0'];
    final params = <Object?>[
      Memory.vectorToJson(queryVector),
      (limit * 3).clamp(10, 100), // k
    ];

    if (roomFilter != null && roomFilter.isNotEmpty) {
      whereParts.add('m.room = ?');
      params.add(roomFilter);
    }

    if (tagFilter != null && tagFilter.isNotEmpty) {
      final tagConditions = tagFilter.map((tag) {
        params.add('%"$tag"%');
        return 'm.tags LIKE ?';
      }).join(' OR ');
      whereParts.add('($tagConditions)');
    }

    final whereClause = whereParts.join(' AND ');
    params.add(limit);

    final rows = db.select(
      'SELECT m.*, v.distance, '
      '  (SELECT COUNT(*) FROM wiki_links w WHERE w.source_memory = m.id) AS link_count, '
      '  (SELECT COUNT(*) FROM wiki_links w WHERE w.target_memory = m.id) AS backlink_count '
      'FROM memories m '
      'JOIN vector_full_scan(\'memories\', \'embedding\', vector_as_f32(?), ?) AS v '
      '  ON m.rowid = v.rowid '
      'WHERE $whereClause '
      'ORDER BY v.distance ASC '
      'LIMIT ?',
      params,
    );

    return rows.map<VaultEntry>((r) => VaultEntry.fromMap(r)).toList();
  }

  /// 標籤篩選搜尋
  List<VaultEntry> _searchByTag(
    Database db,
    List<String>? tagFilter,
    String? roomFilter,
    int limit,
    int offset,
  ) {
    if (tagFilter == null || tagFilter.isEmpty) {
      // 無標籤篩選 → 回傳全部
      return _searchFullText(db, '', roomFilter, null, limit, offset);
    }

    final whereParts = <String>['archived = 0'];
    final params = <Object?>[];

    final tagConditions = tagFilter.map((tag) {
      params.add('%"$tag"%');
      return 'tags LIKE ?';
    }).join(' OR ');
    whereParts.add('($tagConditions)');

    if (roomFilter != null && roomFilter.isNotEmpty) {
      whereParts.add('room = ?');
      params.add(roomFilter);
    }

    final whereClause = whereParts.join(' AND ');
    params.add(limit);
    params.add(offset);

    final rows = db.select(
      'SELECT m.*, '
      '  (SELECT COUNT(*) FROM wiki_links w WHERE w.source_memory = m.id) AS link_count, '
      '  (SELECT COUNT(*) FROM wiki_links w WHERE w.target_memory = m.id) AS backlink_count '
      'FROM memories m '
      'WHERE $whereClause '
      'ORDER BY created_at DESC '
      'LIMIT ? OFFSET ?',
      params,
    );

    return rows.map<VaultEntry>((r) => VaultEntry.fromMap(r)).toList();
  }

  /// 取得所有標籤及其條目數。
  ///
  /// 回傳 `Map<tag, count>`，按 count 降序排列。
  Future<Map<String, int>> getAllTags() async {
    if (!_initialized) return {};

    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        "SELECT tags FROM memories WHERE archived = 0 AND tags != '[]'",
      );

      final tagCounts = <String, int>{};
      for (final row in rows) {
        final tagsJson = row['tags'] as String? ?? '[]';
        try {
          final tags = (jsonDecode(tagsJson) as List).cast<String>();
          for (final tag in tags) {
            tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
          }
        } catch (_) {}
      }

      // 按 count 降序排列
      final sorted = tagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return Map.fromEntries(sorted);
    } catch (e) {
      debugPrint('[VaultService] getAllTags 失敗: $e');
      return {};
    }
  }

  /// 取得單一條目的完整資訊（含連結和 backlinks）。
  Future<VaultEntry?> getEntry(String memoryId) async {
    if (!_initialized) return null;

    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        'SELECT m.*, '
        '  (SELECT COUNT(*) FROM wiki_links w WHERE w.source_memory = m.id) AS link_count, '
        '  (SELECT COUNT(*) FROM wiki_links w WHERE w.target_memory = m.id) AS backlink_count '
        'FROM memories m '
        'WHERE m.id = ?',
        [memoryId],
      );

      if (rows.isEmpty) return null;
      return VaultEntry.fromMap(rows.first);
    } catch (e) {
      debugPrint('[VaultService] getEntry 失敗: $e');
      return null;
    }
  }

  /// 取得條目的出向連結（outgoing wiki-links）。
  Future<List<WikiLinkInfo>> getOutgoingLinks(String memoryId) async {
    if (!_initialized) return [];

    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        'SELECT * FROM wiki_links WHERE source_memory = ? ORDER BY created_at DESC',
        [memoryId],
      );
      return rows.map((r) => WikiLinkInfo.fromMap(r)).toList();
    } catch (e) {
      debugPrint('[VaultService] getOutgoingLinks 失敗: $e');
      return [];
    }
  }

  /// 取得條目的入向連結（backlinks）。
  Future<List<WikiLinkInfo>> getBacklinks(String memoryId) async {
    if (!_initialized) return [];

    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        'SELECT * FROM wiki_links WHERE target_memory = ? ORDER BY created_at DESC',
        [memoryId],
      );
      return rows.map((r) => WikiLinkInfo.fromMap(r)).toList();
    } catch (e) {
      debugPrint('[VaultService] getBacklinks 失敗: $e');
      return [];
    }
  }

  /// 取得圖譜資料（所有節點 + 所有邊）。
  ///
  /// 用於 Graph View 力導向圖譜渲染。
  /// [教練 Agent 2026-07-22] Phase 2 ⑥
  Future<VaultGraphData> getGraphData({
    int maxNodes = 200,
    String? roomFilter,
  }) async {
    if (!_initialized) return VaultGraphData.empty();

    try {
      final db = BrainDatabase.instance.db;

      // 1. 取節點（記憶條目）
      final roomClause = roomFilter != null ? 'AND room = ? ' : '';
      final params = <dynamic>[];
      if (roomFilter != null) params.add(roomFilter);
      params.add(maxNodes);

      final nodeRows = db.select(
        'SELECT id, content, room, source, importance, created_at, '
        '(SELECT COUNT(*) FROM wiki_links WHERE source_memory = m.id) AS link_count, '
        '(SELECT COUNT(*) FROM wiki_links WHERE target_memory = m.id) AS backlink_count '
        'FROM memories m WHERE archived = 0 '
        '$roomClause'
        'ORDER BY importance DESC, created_at DESC '
        'LIMIT ?',
        params,
      );

      final nodes = <VaultGraphNode>[];
      final nodeIdSet = <String>{};

      for (final row in nodeRows) {
        final id = row['id'] as String;
        nodeIdSet.add(id);
        nodes.add(VaultGraphNode(
          id: id,
          label: _extractLabel(row['content'] as String? ?? ''),
          room: row['room'] as String? ?? '',
          source: row['source'] as String? ?? '',
          importance: (row['importance'] as int?) ?? 3,
          linkCount: (row['link_count'] as int?) ?? 0,
          backlinkCount: (row['backlink_count'] as int?) ?? 0,
        ));
      }

      // 2. 取邊（wiki_links，只取兩端都在節點集合中的）
      final edgeRows = db.select(
        'SELECT id, source_memory, target_memory, link_text, created_at '
        'FROM wiki_links '
        'WHERE source_memory IN (${nodeIdSet.map((_) => '?').join(',')}) '
        'AND target_memory IN (${nodeIdSet.map((_) => '?').join(',')})',
        [...nodeIdSet, ...nodeIdSet],
      );

      final edges = edgeRows.map((row) => VaultGraphEdge(
        id: row['id'] as String,
        source: row['source_memory'] as String,
        target: row['target_memory'] as String,
        label: row['link_text'] as String? ?? '',
      )).toList();

      // 3. 如果沒有 wiki_links，用共同標籤建立隱性邊
      if (edges.isEmpty && nodes.length > 1) {
        edges.addAll(_buildImplicitEdges(nodes, nodeRows));
      }

      // [教練 Agent 2026-07-25] Phase 4 — 加入檔案節點 + 交叉引用邊
      final memoryIds = nodeIdSet.toList();
      if (memoryIds.isNotEmpty) {
        final crossRefEdges = await _buildCrossRefEdges(memoryIds, nodes);
        edges.addAll(crossRefEdges.edges);
        nodes.addAll(crossRefEdges.newNodes);
      }

      return VaultGraphData(nodes: nodes, edges: edges);
    } catch (e) {
      debugPrint('[VaultService] getGraphData 失敗: $e');
      return VaultGraphData.empty();
    }
  }

  /// 從內容擷取簡短標籤（前 20 字或第一行）
  String _extractLabel(String content) {
    final firstLine = content.split('\n').first;
    if (firstLine.length <= 20) return firstLine;
    return '${firstLine.substring(0, 20)}…';
  }

  /// 當沒有顯式 wiki-links 時，用共同標籤建立隱性連結。
  List<VaultGraphEdge> _buildImplicitEdges(
    List<VaultGraphNode> nodes,
    List<Map<String, dynamic>> rawRows,
  ) {
    final edges = <VaultGraphEdge>[];
    final tagMap = <String, List<String>>{}; // tag -> [nodeId, ...]

    for (var i = 0; i < nodes.length; i++) {
      final tags = _parseTags(rawRows[i]);
      for (final tag in tags) {
        tagMap.putIfAbsent(tag, () => []).add(nodes[i].id);
      }
    }

    // 共同標籤的節點之間建邊（避免重複）
    final seen = <String>{};
    for (final entry in tagMap.entries) {
      final ids = entry.value;
      if (ids.length < 2) continue;
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final key = '${ids[i]}->${ids[j]}';
          if (seen.contains(key)) continue;
          seen.add(key);
          edges.add(VaultGraphEdge(
            id: 'implicit_$key',
            source: ids[i],
            target: ids[j],
            label: '#${entry.key}',
          ));
        }
      }
    }

    return edges;
  }

  // [教練 Agent 2026-07-25] Phase 4 — 交叉引用邊 + 檔案節點

  /// 從 memory_asset_links 建立交叉引用邊 + 檔案節點
  Future<_CrossRefResult> _buildCrossRefEdges(
    List<String> memoryIds,
    List<VaultGraphNode> existingNodes,
  ) async {
    final edges = <VaultGraphEdge>[];
    final newNodes = <VaultGraphNode>[];
    final existingIds = existingNodes.map((n) => n.id).toSet();
    final addedAssetIds = <String>{};

    try {
      final db = BrainDatabase.instance.db;
      final placeholders = memoryIds.map((_) => '?').join(',');

      // 查交叉引用
      final rows = db.select(
        'SELECT mal.id, mal.memory_id, mal.asset_id, mal.link_type, '
        '  a.file_name, a.asset_kind, a.title '
        'FROM memory_asset_links mal '
        'JOIN asset_index a ON a.id = mal.asset_id '
        'WHERE mal.memory_id IN ($placeholders)',
        memoryIds,
      );

      for (final row in rows) {
        final memoryId = row['memory_id'] as String;
        final assetId = row['asset_id'] as String;
        final linkType = row['link_type'] as String? ?? 'referenced';
        final fileName = row['file_name'] as String? ?? '?';
        final assetKind = row['asset_kind'] as String? ?? 'other';
        final title = row['title'] as String?;

        // 加邊
        final edgeLabel = switch (linkType) {
          'referenced' => '提及',
          'inspired' => '啟發',
          'produced_from' => '產出',
          _ => linkType,
        };
        edges.add(VaultGraphEdge(
          id: 'xref_${row['id']}',
          source: memoryId,
          target: assetId,
          label: edgeLabel,
        ));

        // 加檔案節點（只加一次）
        if (!addedAssetIds.contains(assetId) && !existingIds.contains(assetId)) {
          addedAssetIds.add(assetId);
          newNodes.add(VaultGraphNode(
            id: assetId,
            label: title?.isNotEmpty == true ? title! : fileName,
            room: '',
            source: 'asset',
            importance: 2,
            linkCount: 0,
            backlinkCount: 0,
            nodeType: 'asset',
            assetKind: assetKind,
          ));
        }
      }

      if (newNodes.isNotEmpty || edges.isNotEmpty) {
        debugPrint('[VaultService] 圖譜交叉引用: ${newNodes.length} 檔案節點, ${edges.length} 邊');
      }
    } catch (e) {
      debugPrint('[VaultService] _buildCrossRefEdges 失敗: $e');
    }

    return _CrossRefResult(edges, newNodes);
  }

  List<String> _parseTags(Map<String, dynamic> row) {
    try {
      final tagsJson = row['tags'] as String?;
      if (tagsJson == null || tagsJson.isEmpty) return [];
      return (jsonDecode(tagsJson) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  /// 取得資料庫總條目數。
  Future<int> getTotalEntryCount() async {
    // [小葵 2026-10-16 Blue 報案] 總條目語意＝向量庫全部內容——
    // asset_index（活躍：排除 missing）＋ memories（未封存）。
    // 原版只數 memories 且 _initialized 未設直接回 0（vault 底部
    // 永遠「總共 0 條目」的假象）。
    try {
      final db = BrainDatabase.instance.db;
      final assets = db.select(
        "SELECT COUNT(*) as count FROM asset_index "
        "WHERE index_status != 'missing'",
      );
      final mems = db.select(
        'SELECT COUNT(*) as count FROM memories WHERE archived = 0',
      );
      return ((assets.first['count'] as int?) ?? 0) +
          ((mems.first['count'] as int?) ?? 0);
    } catch (e) {
      return 0;
    }
  }

  /// 更新條目標籤。
  Future<bool> updateTags(String memoryId, List<String> tags) async {
    if (!_initialized) return false;

    try {
      final db = BrainDatabase.instance.db;
      final tagsJson = jsonEncode(tags);
      db.execute(
        'UPDATE memories SET tags = ?, updated_at = ? WHERE id = ?',
        [tagsJson, DateTime.now().millisecondsSinceEpoch, memoryId],
      );
      return true;
    } catch (e) {
      debugPrint('[VaultService] updateTags 失敗: $e');
      return false;
    }
  }

  /// 初始化（標記為可用）。
  ///
  /// VaultService 本身不需要複雜初始化——它直接使用 BrainDatabase。
  /// 這裡只標記 _initialized = true，前提是 BrainDatabase 已初始化。
  void markInitialized() {
    if (BrainDatabase.instance.isInitialized) {
      _initialized = true;
    }
  }
}

/// [教練 Agent 2026-07-25] Phase 4 — 交叉引用邊建構結果
class _CrossRefResult {
  final List<VaultGraphEdge> edges;
  final List<VaultGraphNode> newNodes;

  _CrossRefResult(this.edges, this.newNodes);
}
