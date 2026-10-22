/// PluginManifest — agent-plugins.org schema 1.0.0（`.cursor-plugin/plugin.json`）解析器
///
/// [A線 2026-10-22] 刀1：插槽系統直接吃 Cursor plugin marketplace schema。
/// 官方 pstack 實抓（cursor/plugins pstack/.cursor-plugin/plugin.json v0.15.29）：
/// name/displayName/version/description/author{name}/homepage/repository/
/// license/logo/keywords/category/tags/skills/agents。
///
/// 寬容解析鐵則：
/// - 未知欄位一律忽略（上游加欄位不炸）
/// - 缺 name 或 version → 回 null（寧拒不誤裝——誠實鐵則）
/// - 相對路徑 skills/agents 以 plugin root resolve 成絕對路徑
///
/// 測試隔離照 SkillCatalog 模式：`PluginManifest.test()` 無 IO，
/// `parseFile()` 才碰磁碟。
library;

import 'dart:convert';
import 'dart:io';

class PluginManifest {
  final String name;
  final String displayName;
  final String version;
  final String description;

  /// author 是物件 {name, ...}——我們只收 name 字串（其餘忽略）
  final String? authorName;
  final String? homepage;
  final String? repository;
  final String? license;
  final String? logo;
  final List<String> keywords;
  final String? category;
  final List<String> tags;

  /// manifest 內 `skills` 欄位原值（如 "./skills/"）；null = 未宣告
  final String? skillsDirRaw;

  /// manifest 內 `agents` 欄位原值。Scope 外（另卡）——先收著不接。
  final String? agentsDirRaw;

  /// [A線] plugin root（.cursor-plugin/ 的上層）絕對路徑
  final String pluginRootPath;

  const PluginManifest({
    required this.name,
    this.displayName = '',
    required this.version,
    this.description = '',
    this.authorName,
    this.homepage,
    this.repository,
    this.license,
    this.logo,
    this.keywords = const [],
    this.category,
    this.tags = const [],
    this.skillsDirRaw,
    this.agentsDirRaw,
    required this.pluginRootPath,
  });

  /// 插槽卡顯示名：displayName 優先，無則 name
  String get label => displayName.trim().isNotEmpty ? displayName.trim() : name;

  /// skills 目錄以 plugin root resolve 成絕對路徑。
  /// 未宣告 skills 欄 → 預設 `<root>/skills/`（官方慣例）。
  /// 宣告了但相對路徑逃脫（../ 出 root）→ null（安全：不收）。
  String? get skillsDirPath {
    final raw = skillsDirRaw?.trim();
    final rel = (raw == null || raw.isEmpty) ? 'skills' : raw;
    final p = _resolveUnderRoot(rel);
    return p; // null = 逃脫，呼叫方誠實拒收
  }

  /// agents 目錄絕對路徑（Scope 外，先 resolve 著）。null = 逃脫。
  String? get agentsDirPath {
    final raw = agentsDirRaw?.trim();
    final rel = (raw == null || raw.isEmpty) ? 'agents' : raw;
    return _resolveUnderRoot(rel);
  }

  /// 相對路徑 resolve 到 root 之下；絕對路徑原樣收；
  /// `..` 逃出 root → null（紅隊基本功）。
  String? _resolveUnderRoot(String rel) {
    var p = rel.replaceAll('\\', '/');
    if (p.startsWith('/')) {
      // 絕對路徑——原樣（plugin 宣告什麼就是什麼，呼叫方再驗存在）
      return p;
    }
    // 正規化 ../
    // （保留開頭空段——macOS/Linux 絕對路徑開頭 '/' split 出的空字串，
    //   濾掉會把 '/var/...' 變成 'var/...'，絕對性被吃掉）
    final rootParts = pluginRootPath.split(Platform.pathSeparator);
    final parts = <String>[];
    for (final seg in p.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isEmpty) return null; // 逃出 root
        parts.removeLast();
        continue;
      }
      parts.add(seg);
    }
    if (parts.isEmpty) return null;
    final norm = '${rootParts.join(Platform.pathSeparator)}'
        '${Platform.pathSeparator}'
        '${parts.join(Platform.pathSeparator)}';
    return norm;
  }

  /// 從 plugin.json 檔案路徑解析。缺 name/version 或壞 JSON → null。
  /// [pluginJsonPath] 可指到 `.cursor-plugin/plugin.json` 本身。
  static Future<PluginManifest?> parseFile(String pluginJsonPath) async {
    try {
      final f = File(pluginJsonPath);
      if (!await f.exists()) return null;
      final content = await f.readAsString();
      final root = Directory(
          File(pluginJsonPath).parent.parent.path); // .cursor-plugin/ 的上層
      return _parseJsonString(content, root.path);
    } catch (_) {
      return null;
    }
  }

  /// 從 plugin root 目錄解析（探 `<root>/.cursor-plugin/plugin.json`）。
  static Future<PluginManifest?> parsePluginRoot(String rootPath) async =>
      parseFile('$rootPath/.cursor-plugin/plugin.json');

  /// 純解析（無 IO，測試友善）——餵 JSON 字串＋plugin root。
  static PluginManifest? parse(String jsonString, String pluginRootPath) =>
      _parseJsonString(jsonString, pluginRootPath);

  static PluginManifest? _parseJsonString(String content, String rootPath) {
    try {
      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return null;

      final name = (decoded['name'] as String?)?.trim() ?? '';
      final version = (decoded['version'] as String?)?.trim() ?? '';
      // 寧拒不誤裝：缺 name 或 version 直接拒收
      if (name.isEmpty || version.isEmpty) return null;

      final author = decoded['author'];
      String? authorName;
      if (author is Map<String, dynamic>) {
        authorName = (author['name'] as String?)?.trim();
      } else if (author is String) {
        // 寬容：有的實作 author 直接給字串
        authorName = author.trim();
      }

      List<String> strList(dynamic v) => v is List
          ? v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
          : const [];

      return PluginManifest(
        name: name,
        displayName: (decoded['displayName'] as String?)?.trim() ?? '',
        version: version,
        description: (decoded['description'] as String?)?.trim() ?? '',
        authorName: (authorName == null || authorName.isEmpty) ? null : authorName,
        homepage: (decoded['homepage'] as String?)?.trim(),
        repository: (decoded['repository'] as String?)?.trim(),
        license: (decoded['license'] as String?)?.trim(),
        logo: (decoded['logo'] as String?)?.trim(),
        keywords: strList(decoded['keywords']),
        category: (decoded['category'] as String?)?.trim(),
        tags: strList(decoded['tags']),
        skillsDirRaw: (decoded['skills'] as String?)?.trim(),
        agentsDirRaw: (decoded['agents'] as String?)?.trim(),
        pluginRootPath: rootPath,
      );
    } catch (_) {
      // 壞 JSON → null（誠實鐵則：不硬解不裝成功）
      return null;
    }
  }
}
