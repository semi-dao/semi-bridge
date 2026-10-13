// agent_knowledge_service.dart
// Agent 本地知識庫服務 — Phase E
// [教練 Agent 2026-07-22]
//
// 管理 agent_scripts（腳本/SOP/範本）和 agent_memories（記憶點）。
// 與使用者 Vault 共用 brain.db，用 agent_ 前綴區分表。
//
// FTS5 同步策略：
// - FTS 表用 content='agent_scripts' external content 模式
// - 每次寫入/更新/刪除時手動同步 FTS 索引（schema 未建 trigger）
// - 使用 INSERT INTO fts(rowid, ...) 和 DELETE FROM fts WHERE rowid=?

import 'dart:math';
import 'package:bridge_app/services/brain_container/brain_database.dart';
import 'package:bridge_app/services/vault/vault_templates.dart';
import 'package:bridge_app/services/companion_store.dart'; // 同層 services；[WS-2 2026-09-13] 知識歸屬
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// Agent 腳本
class AgentScript {
  final String id;
  final String title;
  final String? description;
  final String content;
  final String contentType;
  final String? tags;
  final String? category;
  final String? triggerKeywords;
  final String? triggerScenes;
  final int usageCount;
  final String? lastUsedAt;
  final String createdAt;
  final String updatedAt;
  final bool isPinned;
  final String source;

  const AgentScript({
    required this.id,
    required this.title,
    this.description,
    required this.content,
    this.contentType = 'dart',
    this.tags,
    this.category,
    this.triggerKeywords,
    this.triggerScenes,
    this.usageCount = 0,
    this.lastUsedAt,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.source = 'system',
  });

  factory AgentScript.fromRow(Row row) {
    return AgentScript(
      id: row['id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      content: row['content'] as String,
      contentType: row['content_type'] as String? ?? 'dart',
      tags: row['tags'] as String?,
      category: row['category'] as String?,
      triggerKeywords: row['trigger_keywords'] as String?,
      triggerScenes: row['trigger_scenes'] as String?,
      usageCount: row['usage_count'] as int? ?? 0,
      lastUsedAt: row['last_used_at'] as String?,
      createdAt: row['created_at'] as String? ?? '',
      updatedAt: row['updated_at'] as String? ?? '',
      isPinned: (row['is_pinned'] as int?) == 1,
      source: row['source'] as String? ?? 'system',
    );
  }
}

/// Agent 記憶點
class AgentMemory {
  final String id;
  final String title;
  final String content;
  final String? tags;
  final String? memoryType;
  final String createdAt;
  final bool isArchived;

  const AgentMemory({
    required this.id,
    required this.title,
    required this.content,
    this.tags,
    this.memoryType,
    required this.createdAt,
    this.isArchived = false,
  });

  factory AgentMemory.fromRow(Row row) {
    return AgentMemory(
      id: row['id'] as String,
      title: row['title'] as String,
      content: row['content'] as String,
      tags: row['tags'] as String?,
      memoryType: row['memory_type'] as String?,
      createdAt: row['created_at'] as String? ?? '',
      isArchived: (row['is_archived'] as int?) == 1,
    );
  }
}

/// 搜尋結果（腳本或記憶的統一格式）
class KnowledgeSearchResult {
  final String id;
  final String title;
  final String snippet;
  final String type; // 'script' or 'memory'
  final String? category;
  final String? tags;

  const KnowledgeSearchResult({
    required this.id,
    required this.title,
    required this.snippet,
    required this.type,
    this.category,
    this.tags,
  });
}

/// Agent 本地知識庫服務
///
/// 負責管理 agent_scripts 和 agent_memories 兩張表，
/// 提供 CRUD、FTS5 全文搜尋、以及統一的 getRelevantContext() 入口。
class AgentKnowledgeService {
  AgentKnowledgeService._();
  static final AgentKnowledgeService instance = AgentKnowledgeService._();

  Database get _db => BrainDatabase.instance.db;

  // ── Scripts CRUD ──────────────────────────────────────────────────

  /// FTS5 全文搜尋 agent_scripts
  /// [WS-2 2026-09-13 Blue B 決策] 招式預設共享，但私有可能存在——
  /// 同 searchMemories 的歸屬過濾（shared 或當前夥伴）。
  List<KnowledgeSearchResult> searchScripts(String query, {int limit = 5}) {
    if (query.trim().isEmpty) return [];
    final ownerId = _currentOwnerId();

    // [搬遷教訓 2026-09-13] FTS5 unicode61 不切連續中文（同 searchMemories
    // 修復）——CJK 查詢先走 LIKE，落空再 FTS
    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(query);
    if (hasCjk) {
      final likeHits = _searchScriptsLike(query, limit: limit, ownerId: ownerId);
      if (likeHits.isNotEmpty) return likeHits;
    }

    try {
      // FTS5 MATCH 查詢，用 prefix 搜尋提高召回率
      final ftsQuery = _buildFtsQuery(query);
      final results = _db.select(
        '''
        SELECT s.id, s.title, s.description, s.content, s.tags, s.category,
               s.is_pinned, s.usage_count
        FROM agent_scripts_fts f
        JOIN agent_scripts s ON s.rowid = f.rowid
        WHERE agent_scripts_fts MATCH ?
          AND (s.owner_companion_id = 'shared' OR s.owner_companion_id = ?)
        ORDER BY s.is_pinned DESC, s.usage_count DESC, rank
        LIMIT ?
        ''',
        [ftsQuery, ownerId, limit],
      );

      return results.map((row) {
        final content = row['content'] as String? ?? '';
        final desc = row['description'] as String? ?? '';
        final snippet = _makeSnippet(desc.isNotEmpty ? desc : content, 120);
        return KnowledgeSearchResult(
          id: row['id'] as String,
          title: row['title'] as String,
          snippet: snippet,
          type: 'script',
          category: row['category'] as String?,
          tags: row['tags'] as String?,
        );
      }).toList();
    } catch (e) {
      // FTS 查詢可能因特殊字元失敗，fallback 用 LIKE
      debugPrint('[AgentKnowledge] FTS 搜尋失敗，fallback LIKE: $e');
      return _searchScriptsLike(query, limit: limit, ownerId: ownerId);
    }
  }

  /// 取單一腳本
  AgentScript? getScript(String id) {
    final results = _db.select(
      'SELECT * FROM agent_scripts WHERE id = ?',
      [id],
    );
    if (results.isEmpty) return null;
    return AgentScript.fromRow(results.first);
  }

  /// 新增腳本
  String createScript({
    required String title,
    String? description,
    required String content,
    String contentType = 'dart',
    String? tags,
    String? category,
    String? triggerKeywords,
    String? triggerScenes,
    bool isPinned = false,
    String source = 'user',
  }) {
    final id = 'script_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final now = DateTime.now().toIso8601String();

    _db.execute(
      '''
      INSERT INTO agent_scripts (
        id, title, description, content, content_type, tags, category,
        trigger_keywords, trigger_scenes, usage_count, last_used_at,
        created_at, updated_at, is_pinned, source
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL, ?, ?, ?, ?)
      ''',
      [
        id, title, description, content, contentType, tags, category,
        triggerKeywords, triggerScenes, now, now,
        isPinned ? 1 : 0, source,
      ],
    );

    // 同步 FTS 索引
    _syncScriptFts(id);

    return id;
  }

  /// 更新腳本
  void updateScript(String id, {
    String? title,
    String? description,
    String? content,
    String? tags,
    String? category,
    String? triggerKeywords,
    String? triggerScenes,
  }) {
    final existing = getScript(id);
    if (existing == null) return;

    final now = DateTime.now().toIso8601String();
    _db.execute(
      '''
      UPDATE agent_scripts SET
        title = ?,
        description = ?,
        content = ?,
        tags = ?,
        category = ?,
        trigger_keywords = ?,
        trigger_scenes = ?,
        updated_at = ?
      WHERE id = ?
      ''',
      [
        title ?? existing.title,
        description ?? existing.description,
        content ?? existing.content,
        tags ?? existing.tags,
        category ?? existing.category,
        triggerKeywords ?? existing.triggerKeywords,
        triggerScenes ?? existing.triggerScenes,
        now,
        id,
      ],
    );

    // 同步 FTS 索引（先刪再建）
    _db.execute('DELETE FROM agent_scripts_fts WHERE rowid = (SELECT rowid FROM agent_scripts WHERE id = ?)', [id]);
    _syncScriptFts(id);
  }

  /// 刪除腳本（pinned 不可刪）
  bool deleteScript(String id) {
    final script = getScript(id);
    if (script == null) return false;
    if (script.isPinned) {
      debugPrint('[AgentKnowledge] 腳本 $id 已 pinned，不可刪除');
      return false;
    }

    // 先刪 FTS 再刟主表
    _db.execute('DELETE FROM agent_scripts_fts WHERE rowid = (SELECT rowid FROM agent_scripts WHERE id = ?)', [id]);
    _db.execute('DELETE FROM agent_scripts WHERE id = ?', [id]);
    return true;
  }

  /// 記錄使用
  void recordUsage(String id) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE agent_scripts SET usage_count = usage_count + 1, last_used_at = ? WHERE id = ?',
      [now, id],
    );
  }

  // ── Memories CRUD ─────────────────────────────────────────────────

  /// FTS5 全文搜尋 agent_memories
  ///
  /// [WS-2 2026-09-13 Blue B 決策] 記憶私有+招式共享：
  /// 只回傳 owner='shared' 或 owner=當前活躍夥伴的記憶。
  List<KnowledgeSearchResult> searchMemories(String query, {int limit = 5}) {
    if (query.trim().isEmpty) return [];
    final ownerId = _currentOwnerId();

    // [搬遷教訓 2026-09-13] FTS5 unicode61 不切連續中文——「寧紅字不假成功」
    // 整句是一個 token，MATCH 子字串永遠 miss 且不拋錯（LIKE fallback
    // 只在拋錯時觸發）。對策：查詢含 CJK 時直接走 LIKE（記憶庫規模
    // 幾百條，LIKE 掃描成本可接受），否則 FTS。
    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(query);
    if (hasCjk) {
      final likeHits = _searchMemoriesLike(query, limit: limit, ownerId: ownerId);
      if (likeHits.isNotEmpty) return likeHits;
      // LIKE 落空再試 FTS（也許英文混雜可中）
    }

    try {
      final ftsQuery = _buildFtsQuery(query);
      final results = _db.select(
        '''
        SELECT m.id, m.title, m.content, m.tags, m.memory_type
        FROM agent_memories_fts f
        JOIN agent_memories m ON m.rowid = f.rowid
        WHERE agent_memories_fts MATCH ? AND m.is_archived = 0
          AND (m.owner_companion_id = 'shared' OR m.owner_companion_id = ?)
        ORDER BY rank
        LIMIT ?
        ''',
        [ftsQuery, ownerId, limit],
      );

      return results.map((row) {
        final content = row['content'] as String? ?? '';
        return KnowledgeSearchResult(
          id: row['id'] as String,
          title: row['title'] as String,
          snippet: _makeSnippet(content, 120),
          type: 'memory',
          tags: row['tags'] as String?,
        );
      }).toList();
    } catch (e) {
      debugPrint('[AgentKnowledge] FTS 搜尋 memories 失敗，fallback LIKE: $e');
      return _searchMemoriesLike(query, limit: limit, ownerId: ownerId);
    }
  }

  /// [WS-2 2026-09-13] 當前活躍夥伴 ID（知識歸屬過濾用）。
  /// 找不到時回 'shared'（保守：只看得到共享知識，不誤讀他人私有）。
  String _currentOwnerId() {
    try {
      return CompanionStore().activeCompanionId ?? 'shared';
    } catch (_) {
      return 'shared';
    }
  }

  /// 新增記憶點
  String createMemory({
    required String title,
    required String content,
    String? tags,
    String? memoryType,
  }) {
    final id = 'mem_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

    // [WS-2 2026-09-13 Blue B 決策] 記憶預設私有——掛當前活躍夥伴
    final ownerId = _currentOwnerId();
    _db.execute(
      '''
      INSERT INTO agent_memories (id, title, content, tags, memory_type, created_at, is_archived, owner_companion_id)
      VALUES (?, ?, ?, ?, ?, datetime('now'), 0, ?)
      ''',
      [id, title, content, tags, memoryType, ownerId],
    );

    // 同步 FTS
    _syncMemoryFts(id);

    return id;
  }

  /// [教練 Agent 2026-07-22] Phase H — 用 title 精確查詢完整記憶內容
  /// 用於人格卡等需要完整 JSON content 的場景。
  /// [A5 修復 2026-09-14] 記憶私有隔離——與 searchMemories 同標準：
  /// 只回 shared 或當前活躍夥伴的記憶，不得讀到他人私有記憶。
  AgentMemory? getMemoryByTitle(String title) {
    final ownerId = _currentOwnerId();
    final results = _db.select(
      "SELECT * FROM agent_memories WHERE title = ? AND is_archived = 0 "
      "AND (owner_companion_id = 'shared' OR owner_companion_id = ?) "
      "ORDER BY created_at DESC LIMIT 1",
      [title, ownerId],
    );
    if (results.isEmpty) return null;
    return AgentMemory.fromRow(results.first);
  }

  /// [教練 Agent 2026-07-22] Phase H — 封存舊記憶（同一 title 的舊記錄）
  /// 用於人格卡更新時封存舊版本。
  void archiveMemoryByTitle(String title, {String? excludeId}) {
    if (excludeId != null) {
      _db.execute(
        'UPDATE agent_memories SET is_archived = 1 WHERE title = ? AND id != ?',
        [title, excludeId],
      );
    } else {
      _db.execute(
        'UPDATE agent_memories SET is_archived = 1 WHERE title = ?',
        [title],
      );
    }
  }

  // ── 統一入口 ──────────────────────────────────────────────────────

  /// 取得與查詢相關的知識上下文（先查 scripts → 再查 memories → 組合回傳）
  String? getRelevantContext(String query, {int limit = 5}) {
    if (query.trim().isEmpty) return null;

    final scripts = searchScripts(query, limit: limit);
    final memories = searchMemories(query, limit: 3);

    if (scripts.isEmpty && memories.isEmpty) return null;

    final parts = <String>[];

    if (scripts.isNotEmpty) {
      parts.add('### 相關腳本');
      for (final s in scripts) {
        parts.add('**${s.title}** ${s.category != null ? '(${s.category})' : ''}\n${s.snippet}');
      }
    }

    if (memories.isNotEmpty) {
      parts.add('### 相關記憶');
      for (final m in memories) {
        parts.add('**${m.title}**\n${m.snippet}');
      }
    }

    return parts.join('\n\n');
  }

  /// 取得所有 pinned 腳本（給 prompt builder 用）
  List<AgentScript> getPinnedScripts() {
    final results = _db.select(
      'SELECT * FROM agent_scripts WHERE is_pinned = 1 ORDER BY category, title',
    );
    return results.map(AgentScript.fromRow).toList();
  }

  // ── 範本對應（Phase F）──────────────────────────────────────────

  /// 知識庫腳本 ID → 畫布範本 ID 的對應表
  ///
  /// 讓 Agent 從知識庫搜到 SOP 後，能直接載入對應的畫布範本。
  static const Map<String, String> scriptToTemplate = {
    'seed_skill_ig_workflow': 'ig_post',
    'seed_skill_knowledge_organize': 'knowledge_digest',
    'seed_skill_memory_review': 'memory_review',
    'seed_skill_multi_model': 'multi_model',
  };

  /// 根據腳本 ID 取得對應的畫布範本
  WorkflowTemplate? getTemplateForScript(String scriptId) {
    final templateId = scriptToTemplate[scriptId];
    if (templateId == null) return null;
    final templates = VaultTemplateService.instance.getBuiltinTemplates();
    return templates.where((t) => t.id == templateId).firstOrNull;
  }

  /// 取得所有可用的範本摘要（給 Agent 列出用）
  List<Map<String, String>> listAvailableTemplates() {
    final templates = VaultTemplateService.instance.getBuiltinTemplates();
    return templates.map((t) => {
      'id': t.id,
      'name': t.name,
      'description': t.description,
      'category': t.category,
      'icon': t.icon,
    }).toList();
  }

  // ── 預裝腳本 seed ─────────────────────────────────────────────────

  /// 插入系統預裝腳本（首次啟動時呼叫，INSERT OR IGNORE 避免重複）
  void seedDefaultScripts() {
    final seeds = _defaultScriptSeeds;
    for (final seed in seeds) {
      _db.execute(
        '''
        INSERT OR IGNORE INTO agent_scripts (
          id, title, description, content, content_type, tags, category,
          trigger_keywords, trigger_scenes, usage_count, last_used_at,
          created_at, updated_at, is_pinned, source
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL, datetime('now'), datetime('now'), 1, 'system')
        ''',
        [
          seed['id'], seed['title'], seed['description'], seed['content'],
          seed['content_type'] ?? 'markdown', seed['tags'], seed['category'],
          seed['trigger_keywords'], seed['trigger_scenes'],
        ],
      );
    }

    // 同步所有未索引的腳本到 FTS
    _rebuildScriptFtsForAll();
  }

  /// 檢查是否已 seed 過
  bool get isSeeded {
    final result = _db.select(
      "SELECT COUNT(*) as cnt FROM agent_scripts WHERE source = 'system'",
    );
    final cnt = result.first['cnt'] as int? ?? 0;
    return cnt > 0;
  }

  // ── FTS 同步（private）──────────────────────────────────────────

  void _syncScriptFts(String id) {
    final row = _db.select(
      'SELECT rowid, title, description, content, tags, trigger_keywords FROM agent_scripts WHERE id = ?',
      [id],
    );
    if (row.isEmpty) return;
    final r = row.first;
    _db.execute(
      'INSERT INTO agent_scripts_fts(rowid, title, description, content, tags, trigger_keywords) VALUES (?, ?, ?, ?, ?, ?)',
      [
        r['rowid'],
        r['title'] as String? ?? '',
        r['description'] as String? ?? '',
        r['content'] as String? ?? '',
        r['tags'] as String? ?? '',
        r['trigger_keywords'] as String? ?? '',
      ],
    );
  }

  void _syncMemoryFts(String id) {
    final row = _db.select(
      'SELECT rowid, title, content, tags FROM agent_memories WHERE id = ?',
      [id],
    );
    if (row.isEmpty) return;
    final r = row.first;
    _db.execute(
      'INSERT INTO agent_memories_fts(rowid, title, content, tags) VALUES (?, ?, ?, ?)',
      [
        r['rowid'],
        r['title'] as String? ?? '',
        r['content'] as String? ?? '',
        r['tags'] as String? ?? '',
      ],
    );
  }

  /// 重建所有腳本的 FTS 索引（seed 後呼叫）
  void _rebuildScriptFtsForAll() {
    // 先清空 FTS，再重建
    _db.execute('DELETE FROM agent_scripts_fts');

    final rows = _db.select(
      'SELECT rowid, title, description, content, tags, trigger_keywords FROM agent_scripts',
    );
    for (final r in rows) {
      _db.execute(
        'INSERT INTO agent_scripts_fts(rowid, title, description, content, tags, trigger_keywords) VALUES (?, ?, ?, ?, ?, ?)',
        [
          r['rowid'],
          r['title'] as String? ?? '',
          r['description'] as String? ?? '',
          r['content'] as String? ?? '',
          r['tags'] as String? ?? '',
          r['trigger_keywords'] as String? ?? '',
        ],
      );
    }
  }

  // ── LIKE fallback 搜尋（private）─────────────────────────────────

  List<KnowledgeSearchResult> _searchScriptsLike(String query,
      {int limit = 5, String ownerId = 'shared'}) {
    final pattern = '%$query%';
    final results = _db.select(
      '''
      SELECT id, title, description, content, tags, category
      FROM agent_scripts
      WHERE (title LIKE ? OR description LIKE ? OR content LIKE ? OR tags LIKE ? OR trigger_keywords LIKE ?)
        AND (owner_companion_id = 'shared' OR owner_companion_id = ?)
      ORDER BY is_pinned DESC, usage_count DESC
      LIMIT ?
      ''',
      [pattern, pattern, pattern, pattern, pattern, ownerId, limit],
    );

    return results.map((row) {
      final content = row['content'] as String? ?? '';
      final desc = row['description'] as String? ?? '';
      return KnowledgeSearchResult(
        id: row['id'] as String,
        title: row['title'] as String,
        snippet: _makeSnippet(desc.isNotEmpty ? desc : content, 120),
        type: 'script',
        category: row['category'] as String?,
        tags: row['tags'] as String?,
      );
    }).toList();
  }

  List<KnowledgeSearchResult> _searchMemoriesLike(String query,
      {int limit = 5, String ownerId = 'shared'}) {
    final pattern = '%$query%';
    final results = _db.select(
      '''
      SELECT id, title, content, tags
      FROM agent_memories
      WHERE (title LIKE ? OR content LIKE ? OR tags LIKE ?) AND is_archived = 0
        AND (owner_companion_id = 'shared' OR owner_companion_id = ?)
      ORDER BY created_at DESC
      LIMIT ?
      ''',
      [pattern, pattern, pattern, ownerId, limit],
    );

    return results.map((row) {
      final content = row['content'] as String? ?? '';
      return KnowledgeSearchResult(
        id: row['id'] as String,
        title: row['title'] as String,
        snippet: _makeSnippet(content, 120),
        type: 'memory',
        tags: row['tags'] as String?,
      );
    }).toList();
  }

  // ── 工具方法（private）───────────────────────────────────────────

  /// 把使用者查詢轉成 FTS5 查詢語法
  /// "畫布工作流" → "畫布* OR 工作流*"
  String _buildFtsQuery(String query) {
    // 分詞，加 prefix wildcard
    final tokens = query
        .split(RegExp(r'[\s,，。、]+'))
        .where((t) => t.trim().isNotEmpty)
        .map((t) => '"$t"*')  // quoted prefix search
        .toList();
    if (tokens.isEmpty) return '"$query*"';
    return tokens.join(' OR ');
  }

  /// 截取 snippet
  String _makeSnippet(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }

  // ── 預裝腳本 seed data ───────────────────────────────────────────

  static const List<Map<String, String?>> _defaultScriptSeeds = [
    {
      'id': 'seed_sop_canvas_workflow',
      'title': '畫布工作流建立流程',
      'description': '從使用者需求到畫布工作流的標準建立流程',
      'content': '''# 畫布工作流建立流程

## 步驟
1. 理解使用者需求，拆解為可執行步驟
2. 用 canvas_place 逐一放置節點（每步驟一節點）
3. 用 canvas_connect 按依賴關係連接（relationType: depends）
4. 確認流程完整性，告知使用者
5. 等待使用者確認後才執行

## 原則
- 步驟內容要具體可執行
- 步驟數量 3-7 個為宜
- 先放節點再連線
- 破壞性操作需使用者確認''',
      'content_type': 'markdown',
      'tags': 'canvas, workflow, sop',
      'category': 'SOP',
      'trigger_keywords': '畫布,工作流,規劃,流程,計畫',
      'trigger_scenes': 'canvas_planning',
    },
    {
      'id': 'seed_sop_vault_organize',
      'title': 'Vault 條目整理流程',
      'description': '整理第二大腦 Vault 條目的標準流程',
      'content': '''# Vault 條目整理流程

## 步驟
1. 用 vault_search 搜尋相關條目
2. 用 vault_get_tags 了解現有標籤分布
3. 檢查條目是否有重複或可合併
4. 提出整理建議給使用者
5. 使用者確認後執行

## 原則
- 不擅自刪除使用者條目
- 合併前先展示內容讓使用者確認
- 標籤建議要符合使用者既有命名習慣''',
      'content_type': 'markdown',
      'tags': 'vault, organize, sop',
      'category': 'SOP',
      'trigger_keywords': '整理,Vault,資料庫,知識,條目',
      'trigger_scenes': 'vault_organize',
    },
    {
      'id': 'seed_sop_onboarding',
      'title': '使用者引導流程',
      'description': '新使用者首次設定的引導流程',
      'content': '''# 使用者引導流程

## 步驟
1. 用 check_capability_status 檢查目前設定狀態
2. 判斷缺少什麼（API Key / Companion）
3. 引導到對應設定頁面（open_setting_field）
4. 推薦 MiniMax（免費額度，台灣可用）
5. 設定完成後引導召喚夥伴

## 原則
- 不碰使用者的金鑰內容
- 一步一步引導，不要一次給太多資訊
- 使用者卡住時提供截圖或具體操作步驟''',
      'content_type': 'markdown',
      'tags': 'onboarding, guide, sop',
      'category': 'SOP',
      'trigger_keywords': '設定,開始,引導,新手,安裝',
      'trigger_scenes': 'onboarding',
    },
    {
      'id': 'seed_skill_ig_workflow',
      'title': '角色扮演 IG 範本',
      'description': '用角色視角寫 IG 貼文 + AI 生成配圖',
      'content': '''# 角色扮演 IG 工作流

## 效果
選一個角色（寵物、物品、今天的心情）→ AI 用角色的語氣寫一篇 IG 貼文 → 生成配圖

## 流程
1. input：使用者選角色 + 提供素材
2. llm：用角色的第一人稱視角寫 150-250 字貼文，要有個性
3. imageGen：根據貼文內容生成配圖
4. output：貼文 + 配圖

## 引導使用者
- 先問使用者想用什麼角色（寵物、物品、心情）
- 建議從使用者資料夾裡找素材當起點
- 排程建議：每天早上自動準備草稿''',
      'content_type': 'markdown',
      'tags': 'template, ig, social',
      'category': 'Skill',
      'trigger_keywords': 'IG,Instagram,發文,社群,貼文',
      'trigger_scenes': 'social_posting',
    },
    {
      'id': 'seed_skill_knowledge_organize',
      'title': '晨間情報站範本',
      'description': '搜尋網路新聞 + 本地檔案 → 合併 → AI 整理成日報',
      'content': '''# 晨間情報站工作流

## 效果
每天早上自動搜尋網路新聞 + 本地檔案 → 合併 → AI 整理成一份結構化日報

## 流程
1. input：使用者設定追蹤主題
2. tool(browse)：搜尋網路新聞
3. tool(desktop_files)：搜尋本地相關檔案
4. merge：合併兩個資料源
5. llm：整理成日報格式（今日要聞 + 本地筆記 + AI 建議）
6. output：Markdown 日報

## 引導使用者
- 問使用者想追蹤哪些主題
- 排程建議：每天早上 7:00 自動跑
- 溫度設 0.3（穩定輸出）''',
      'content_type': 'markdown',
      'tags': 'template, knowledge',
      'category': 'Skill',
      'trigger_keywords': '知識,整理,筆記,摘要,歸納',
      'trigger_scenes': 'knowledge_organize',
    },
    {
      'id': 'seed_skill_memory_review',
      'title': '短影音製作所範本',
      'description': '輸入主題 → 寫腳本 → 分支產出影音 → 合併短影音',
      'content': '''# 短影音製作所工作流

## 效果
輸入一個主題 → AI 寫腳本 → 判斷風格 → 分支產出（知識型走圖文+語音 / 感性型走影片+配樂）→ 合併成短影音

## 流程
1. input：使用者給主題
2. llm：寫 30 秒短影音腳本，標注 [知識型] 或 [感性型]
3. condition：判斷風格
4. 知識型分支：imageGen 解說圖 → tts 語音旁白
5. 感性型分支：videoGen 影片片段 → musicGen 配樂
6. merge：合併兩條分支
7. output：短影音成品

## 引導使用者
- 問使用者想做什麼主題的短影音
- 排程建議：按需觸發或每週自動產出''',
      'content_type': 'markdown',
      'tags': 'template, memory',
      'category': 'Skill',
      'trigger_keywords': '記憶,回顧,複習,回憶',
      'trigger_scenes': 'memory_review',
    },
    {
      'id': 'seed_skill_multi_model',
      'title': '多重宇宙簡報範本',
      'description': '同一主題在三個平行宇宙用三種方式呈現 → AI 觀察者合成簡報',
      'content': '''# 多重宇宙簡報工作流

## 效果
同一個主題，同時進入三個平行宇宙——宇宙 A 變成角色扮演貼文，宇宙 B 變成情報日報，宇宙 C 變成短影音。AI 觀察者把三個宇宙的結果合成一份多重宇宙簡報。

## 六概念流程
1. 🚪 門(input)：使用者選一個主題，打開門
2. 🌊 水流(subWorkflow×3)：主題流入三個宇宙，各自完成
3. 🌉 橋(merge)：三個宇宙的結果被連結
4. ⚖️ 鐘擺(llm+condition)：觀察者在視角間擺動找平衡
5. 💗🧠 心腦(output)：結果給使用者判斷
6. 📚 記憶：產出存入知識庫，不消失

## 引導使用者
- 這是畢業任務，前面三個範本的資產在這裡被引用
- 問使用者想用什麼主題開啟多重宇宙
- 排程建議：按需觸發或每週五跑一次''',
      'content_type': 'markdown',
      'tags': 'template, multi_model',
      'category': 'Skill',
      'trigger_keywords': '模型,切換,協作,多模型,vision',
      'trigger_scenes': 'model_switch',
    },
    {
      'id': 'seed_snippet_prompt_template',
      'title': '常用 prompt 模板',
      'description': '高頻使用的 prompt 模板片段',
      'content': '''# 常用 Prompt 模板

## 分析型
"請分析以下內容，找出核心問題和可能的解決方案：
{content}"

## 整理型
"請把以下資訊整理成結構化的筆記，包含：
- 核心要點
- 關鍵細節
- 待確認事項
{content}"

## 引導型
"我理解你想要{goal}。為了幫你做得更好，我需要確認：
1. {question1}
2. {question2}
請告訴我你的想法。"

## 總結型
"請用 3-5 個要點總結以下內容：
{content}"''',
      'content_type': 'markdown',
      'tags': 'prompt, template',
      'category': 'Snippet',
      'trigger_keywords': 'prompt,模板,範本,常用',
      'trigger_scenes': 'prompt_writing',
    },
    {
      'id': 'seed_snippet_canvas_actions',
      'title': '畫布操作快捷序列',
      'description': '常用畫布操作組合',
      'content': '''# 畫布操作快捷序列

## 建立流程
canvas_place × N → canvas_connect × (N-1) → canvas_send_chat 確認

## 修改流程
canvas_get_state → canvas_remove → canvas_place → canvas_connect → canvas_send_chat

## 執行流程
canvas_get_state → canvas_send_chat（告知）→ canvas_execute → canvas_get_state（驗證）

## 範本載入
canvas_list → canvas_load → canvas_get_state → canvas_send_chat（說明）''',
      'content_type': 'markdown',
      'tags': 'canvas, action, quick',
      'category': 'Snippet',
      'trigger_keywords': '畫布,操作,快捷,序列,動作',
      'trigger_scenes': 'canvas_action',
    },
    {
      'id': 'seed_tool_default_config',
      'title': '預設工具配置',
      'description': 'Agent 預設工具使用配置',
      'content': '''# 預設工具配置

## 感知工具（眼睛）
- screen_capture：截圖（注意隱私）
- read_app_log：讀 log
- canvas_screenshot：畫布截圖
- canvas_get_annotations：使用者標注
- check_capability_status：設定狀態
- memory_search：記憶檢索
- read_source_file：讀原始碼

## 行動工具（手腳）
- patch_source_file：改碼
- run_terminal：跑指令
- restart_app：重啟
- canvas_place / connect / remove：畫布操作
- canvas_execute：執行工作流
- ui_navigate / ui_tap：UI 操作

## 配置原則
- 預設全部啟用
- screen_capture 受隱私保護
- 破壞性操作需確認''',
      'content_type': 'markdown',
      'tags': 'tool, config, default',
      'category': 'Tool Config',
      'trigger_keywords': '工具,配置,設定,預設',
      'trigger_scenes': 'tool_config',
    },
    {
      // [Blue 令 2026-10-05] 反重複工鐵律——寫入 App Agent 的長期知識。
      // 起源：懸浮窗動圖 60fps 逐幀軟體去背燒 200% CPU 案——明知無效工卻讓它跑了數週。
      // 鐵律：發現重複工/無用工 = 當場修，不放過。程式碼裡也一樣（見 task_prompt_enhancer）。
      'id': 'seed_no_wasted_work',
      'title': '反重複工鐵律',
      'description': '發現重複工/無用工必須當場排除——浪費資源是自己造成的',
      'content': '''# 反重複工鐵律（Blue 令 2026-10-05）

## 核心原則
**發現任何「重複工」或「無用工」，當場排除，不放過、不拖延。**

判準（四問）：
1. 這段邏輯跑兩次 = 跑一次嗎？（不是→找出為什麼會跑兩次）
2. 這個計算的輸入沒變，輸出會變嗎？（不會→快取或跳過）
3. 這個輪詢有事件可訂閱嗎？（有→改事件驅動）
4. 這個幀/這個請求和上一個一樣嗎？（一樣→跳過）

## 典型案例（真實教訓）
- 60fps 逐幀軟體去背（素材只有 24fps，其餘 36 幀是重算）→ 預去背 + 硬解直通
- 不可見視窗仍在渲染 → isVisible 檢查跳過
- 同一工具被反覆提出 → 拒絕冷卻 15 分鐘

## 寫程式時的自律
- loop 內不做可提到 loop 外的計算
- 每幀不做可離線預處理的工作（離線一次勝過線上百萬次）
- 定時輪詢能改事件訂閱就改
- 寧可現在多花 10 分鐘修，不要讓它每秒浪費 60 次

**浪費不是外部強加的，是自己寫出來的。左腳踩右腳，永遠跑不快。**''',
      'content_type': 'markdown',
      'tags': 'efficiency, principle, discipline',
      'category': 'Principle',
      'trigger_keywords': '重複,無用,浪費,效能,輪詢,優化,資源',
      'trigger_scenes': 'efficiency, coding, loop_design',
    },
  ];
}
