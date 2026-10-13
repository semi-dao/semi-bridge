/// Skill Tools — skill_search / skill_load agent 工具（插槽輕量化 Task 4）
///
/// Hermes agency-agents-router 四工具（search→inspect→load→delegate）的 App 版：
/// - [SkillTools.search]：對 [SkillCatalog] 條目評分（token 交集＋name/description
///   連續片段加權，參考 agency-agents-router `_score()`），回 slug+name+description。
/// - [SkillTools.load]：catalog.loadBody() 懶載入——body 永遠留磁碟，用到才讀。
/// - 失敗誠實鐵則：`{success:false, error}`，絕不空內容裝成功。
/// - 統一管理接線：SlotRegistry 停用的卡 → [SkillTools.disabledSkillNames]
///   收集成名單，搜尋/載入一律排除（插槽頁 = 管理真相源）。
///
/// 評分對位（agency-agents-router `_score()`）：
/// - 每個 query token 命中 haystack（name/description/category）＋1.0
/// - token 命中 name ＋3.0（連續子字串）
/// - token 命中 description ＋1.5（連續子字串）
/// - 整段 query 連續出現 ＋5.0
/// - 集中獎勵：+1/sqrt(metadataTokens)（描述精煉者略勝，body 不參與評分）
library;

import 'dart:convert';
import 'dart:math' as math;

import '../agent_loop/agent_tool.dart';
import '../slots/slot_registry.dart';
import 'skill_catalog.dart';

/// skill_search / skill_load 的 service 核心（純 Dart，不依賴 UI）
class SkillTools {
  SkillTools._();

  /// 搜尋上限（Hermes 同款：一次最多撈 25 條 metadata，不撈 body）
  static const int maxLimit = 25;

  /// skill_search——對 catalog 條目評分，回排序後的 metadata 卡
  ///
  /// [disabledNames] 停用插槽卡的 skill 名（SlotRegistry 接線，見
  /// [disabledSkillNames]）——結果一律排除。
  static Future<SkillSearchResult> search(
    SkillCatalog catalog,
    String query, {
    Set<String> disabledNames = const {},
    String? category,
    int limit = maxLimit,
  }) async {
    final effectiveLimit = limit.clamp(1, maxLimit);
    final tokens = _tokenize(query);
    if (tokens.isEmpty) {
      return const SkillSearchResult(results: []);
    }

    final scored = <_ScoredItem>[];
    for (final entry in catalog.all) {
      if (disabledNames.contains(entry.name)) continue;
      if (category != null && category.isNotEmpty && entry.category != category) {
        continue;
      }
      final score = _score(entry, tokens, query);
      if (score <= 0) continue; // 零分不硬湊——誠實空結果
      scored.add(_ScoredItem(entry, score));
    }

    // 分數高者先；同分 name 穩定排序（byte-stable，prompt caching 友善）
    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return a.entry.name.compareTo(b.entry.name);
    });

    return SkillSearchResult(
      results: scored
          .take(effectiveLimit)
          .map((s) => SkillSearchHit(
                slug: s.entry.name,
                name: s.entry.name,
                description: s.entry.description,
                category: s.entry.category,
                score: s.score,
              ))
          .toList(),
    );
  }

  /// skill_load——懶載入全文。失敗誠實回 {success:false, error}
  static Future<SkillLoadResult> load(
    SkillCatalog catalog,
    String slug, {
    Set<String> disabledNames = const {},
  }) async {
    final name = slug.trim();
    if (name.isEmpty) {
      return const SkillLoadResult.failure('請提供 skill 名稱（slug）');
    }
    if (disabledNames.contains(name)) {
      return SkillLoadResult.failure('skill「$name」已被停用（插槽管理頁可重新啟用）');
    }
    final entry = catalog.find(name);
    if (entry == null) {
      return SkillLoadResult.failure(
          '找不到 skill「$name」——先用 skill_search 確認名稱（停用的 skill 不在搜尋結果）');
    }
    try {
      final body = await catalog.loadBody(entry);
      return SkillLoadResult(
        slug: entry.name,
        name: entry.name,
        category: entry.category,
        body: body,
      );
    } catch (e) {
      return SkillLoadResult.failure('載入 skill「$name」失敗：$e');
    }
  }

  /// 統一管理接線：SlotRegistry 中「非 running」的 skill 卡名單
  ///
  /// 對位規則：卡片 sourceRepo = `skill://<origin>__<name>`，
  /// userLabel 或 repo 尾段即 skill 名。status != running（disabled/pending）
  /// 一律排除——插槽管理頁停用 → skillSearch/skillLoad 立即看不到。
  static Set<String> disabledSkillNames(SlotRegistry registry) {
    final names = <String>{};
    for (final slot in registry.all) {
      if (slot.isRunning) continue;
      final label = slot.userLabel.trim();
      if (label.isNotEmpty) {
        names.add(label);
        continue;
      }
      // label 空則從 sourceRepo 尾段萃取
      final repo = slot.sourceRepo;
      final idx = repo.lastIndexOf('__');
      if (idx != -1 && idx + 2 < repo.length) {
        names.add(repo.substring(idx + 2));
      }
    }
    return names;
  }

  // ═══════════════════════════════════════════════════
  // 評分核心（對位 agency-agents-router _score()）
  // ═══════════════════════════════════════════════════

  /// haystack：只吃 metadata（name/description/category）——body 永不參與評分，
  /// 這是「輕量化」的鐵則：搜尋 400 條也不讀 1 byte 的 body。
  static double _score(
    SkillCatalogEntry entry,
    Set<String> tokens,
    String query,
  ) {
    final nameLower = entry.name.toLowerCase();
    final descLower = entry.description.toLowerCase();
    final categoryLower = entry.category.toLowerCase();
    final haystackText = '$nameLower\n$descLower\n$categoryLower';
    final metadataTokens = _tokenize(haystackText);

    var score = 0.0;
    for (final token in tokens) {
      if (metadataTokens.contains(token)) score += 1.0; // token 交集
      if (nameLower.contains(token)) score += 3.0; // name 連續片段
      if (descLower.contains(token)) score += 1.5; // description 連續片段
    }
    final queryLower = query.trim().toLowerCase();
    if (queryLower.isNotEmpty && haystackText.contains(queryLower)) {
      score += 5.0; // 整句連續出現
    }
    if (score <= 0) return 0;
    // 集中獎勵：描述精煉者略勝（agency 同款，量級小不會壓過內容命中）
    return score + 1.0 / math.sqrt(math.max(metadataTokens.length, 1));
  }

  /// 分詞：小寫化、切非文字字元。中英混合下中文整段成一 token——
  /// 加上 contains 連續片段加分補足中文切詞的不足。
  static Set<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^\w\u4e00-\u9fff]+'))
        .where((s) => s.isNotEmpty)
        .toSet();
  }
}

/// 排序用中繼——entry + 評分
class _ScoredItem {
  final SkillCatalogEntry entry;
  final double score;
  const _ScoredItem(this.entry, this.score);
}

/// skill_search 單筆結果
class SkillSearchHit {
  final String slug;
  final String name;
  final String description;
  final String category;
  final double score;

  const SkillSearchHit({
    required this.slug,
    required this.name,
    required this.description,
    required this.category,
    required this.score,
  });

  Map<String, dynamic> toJson() => {
        'slug': slug,
        'name': name,
        'description': description,
        'category': category,
        'score': double.parse(score.toStringAsFixed(3)),
      };
}

/// skill_search 結果
class SkillSearchResult {
  final List<SkillSearchHit> results;

  const SkillSearchResult({required this.results});

  bool get success => true;

  Map<String, dynamic> toJson() => {
        'success': true,
        'count': results.length,
        'results': results.map((r) => r.toJson()).toList(),
      };
}

/// skill_load 結果
class SkillLoadResult {
  final String? slug;
  final String? name;
  final String? category;
  final String? body;
  final String? error;

  const SkillLoadResult({
    this.slug,
    this.name,
    this.category,
    this.body,
    this.error,
  });

  const SkillLoadResult.failure(this.error)
      : slug = null,
        name = null,
        category = null,
        body = null;

  bool get success => error == null;

  Map<String, dynamic> toJson() => success
      ? {
          'success': true,
          'slug': slug,
          'name': name,
          'category': category,
          'body': body,
        }
      : {'success': false, 'error': error};
}

// ═══════════════════════════════════════════════════
// AgentTool 版——註冊進 AgentToolRegistry 給 LLM 呼叫
// ═══════════════════════════════════════════════════

Set<String> _defaultDisabled() => const {};

/// skill_search——「需要時會想起」本體。回 JSON（slug+name+description+score）。
class SkillSearchTool extends AgentTool {
  final SkillCatalog catalog;
  final Set<String> Function() disabledNamesProvider;

  SkillSearchTool(
    this.catalog, {
    Set<String> Function()? disabledNamesProvider,
  }) : disabledNamesProvider = disabledNamesProvider ?? _defaultDisabled;

  @override
  String get name => 'skill_search';

  @override
  String get description =>
      '搜尋 skill/人格庫（metadata，含顧問模式人格）。要做某事前先搜尋有沒有現成的專家知識可用。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'query',
          description: '搜尋關鍵字，例如「行銷」「code review」「人類學」',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'category',
          description: '限定分類（選填），例如 agency-agents、hermes',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'limit',
          description: '最多回傳幾筆（選填，預設 25，上限 25）',
          required: false,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final query = (args['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) {
      return AgentToolResult.failure('請提供 query 參數', toolName: name);
    }
    try {
      final result = await SkillTools.search(
        catalog,
        query,
        disabledNames: disabledNamesProvider(),
        category: args['category'] as String?,
        limit: (args['limit'] as num?)?.toInt() ?? SkillTools.maxLimit,
      );
      return AgentToolResult.success(jsonEncode(result.toJson()));
    } catch (e) {
      return AgentToolResult.failure('skill_search 失敗：$e', toolName: name);
    }
  }
}

/// skill_load——懶載入全文。找到想要的 skill 後載入完整內容。
class SkillLoadTool extends AgentTool {
  final SkillCatalog catalog;
  final Set<String> Function() disabledNamesProvider;

  SkillLoadTool(
    this.catalog, {
    Set<String> Function()? disabledNamesProvider,
  }) : disabledNamesProvider = disabledNamesProvider ?? _defaultDisabled;

  @override
  String get name => 'skill_load';

  @override
  String get description => '載入 skill 的完整內容（先用 skill_search 找到名稱再載）。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'slug',
          description: 'skill 名稱（skill_search 回傳的 slug）',
          required: true,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final slug = (args['slug'] as String?)?.trim() ?? '';
    if (slug.isEmpty) {
      return AgentToolResult.failure('請提供 slug 參數', toolName: name);
    }
    try {
      final result = await SkillTools.load(
        catalog,
        slug,
        disabledNames: disabledNamesProvider(),
      );
      if (!result.success) {
        return AgentToolResult.failure(result.error ?? '未知錯誤', toolName: name);
      }
      return AgentToolResult.success(
          '${result.name}\n\n${result.body ?? ''}');
    } catch (e) {
      return AgentToolResult.failure('skill_load 失敗：$e', toolName: name);
    }
  }
}
