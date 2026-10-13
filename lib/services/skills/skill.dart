/// Skill — 可重複使用的程序記憶
///
/// S20: Hermes SKILL.md 的橋樑 App 等價物。
/// 每個 Skill 是一個 markdown 檔案，帶 YAML frontmatter 描述觸發條件。
/// Agent Loop 根據使用者訊息匹配相關 skill，注入 system prompt。
///
/// 檔案格式：
/// ```markdown
/// ---
/// name: daily-briefing
/// description: 每日晨間簡報
/// trigger_keywords: [晨報, 簡報, 今日回顧]
/// trigger_patterns:
///   - "今天.*簡報"
/// priority: normal
/// version: 1
/// ---
///
/// # 每日晨間簡報
///
/// ## 步驟
/// 1. 使用 memory_search 搜尋昨日記憶
/// 2. 整理成結構化簡報
/// ```

/// Skill 優先級已抽出至 skill_priority.dart（SkillCatalog 免拖 body 依賴），
/// 此處 import（自身使用）+ re-export（既有 API 相容）。
import 'skill_priority.dart';

export 'skill_priority.dart';

/// Skill 模型
class Skill {
  /// 唯一名稱（snake-case）
  final String name;

  /// 一行描述
  final String description;

  /// 觸發關鍵字（精確匹配）
  final List<String> triggerKeywords;

  /// 觸發正則模式
  final List<String> triggerPatterns;

  /// 優先級
  final SkillPriority priority;

  /// 版本號
  final int version;

  /// Markdown body（不含 frontmatter）
  final String body;

  /// 檔案路徑（如果有）
  final String? filePath;

  const Skill({
    required this.name,
    required this.description,
    this.triggerKeywords = const [],
    this.triggerPatterns = const [],
    this.priority = SkillPriority.normal,
    this.version = 1,
    required this.body,
    this.filePath,
  });

  /// 從 markdown 檔案內容解析 Skill
  factory Skill.fromMarkdown(String content, {String? filePath}) {
    final parsed = _parseFrontmatter(content);
    final frontmatter = parsed.$1;
    final body = parsed.$2;

    return Skill(
      name: frontmatter['name'] as String? ?? 'unnamed',
      description: frontmatter['description'] as String? ?? '',
      triggerKeywords: _parseList(frontmatter['trigger_keywords']),
      triggerPatterns: _parseList(frontmatter['trigger_patterns']),
      priority: SkillPriority.fromString(frontmatter['priority'] as String?),
      version: int.tryParse(frontmatter['version']?.toString() ?? '1') ?? 1,
      body: body.trim(),
      filePath: filePath,
    );
  }

  /// 序列化回 markdown
  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('name: $name');
    buf.writeln('description: $description');
    if (triggerKeywords.isNotEmpty) {
      buf.writeln('trigger_keywords: [${triggerKeywords.join(', ')}]');
    }
    if (triggerPatterns.isNotEmpty) {
      buf.writeln('trigger_patterns:');
      for (final p in triggerPatterns) {
        buf.writeln('  - "$p"');
      }
    }
    buf.writeln('priority: ${priority.name}');
    buf.writeln('version: $version');
    buf.writeln('---');
    buf.writeln();
    buf.write(body);
    return buf.toString();
  }

  /// 簡短摘要（用於 prompt 注入的 header）
  String get summary => '**$name**: $description';

  @override
  String toString() => 'Skill($name, priority: ${priority.name})';
}

/// 解析 frontmatter — 回傳 (frontmatter map, body)
/// 使用狀態機：遇到 `key:` 開始，後續 `- item` 歸入同一個 key
(Map<String, dynamic>, String) _parseFrontmatter(String content) {
  final trimmed = content.trimLeft();
  if (!trimmed.startsWith('---')) {
    return ({}, content);
  }

  // 找第二個 ---
  final firstEnd = trimmed.indexOf('\n');
  if (firstEnd == -1) return ({}, content);

  final rest = trimmed.substring(firstEnd + 1);
  final secondDelimiter = rest.indexOf('\n---');
  if (secondDelimiter == -1) return ({}, content);

  final frontmatterText = rest.substring(0, secondDelimiter);
  final body = rest.substring(secondDelimiter + 4); // skip \n---

  final map = <String, dynamic>{};
  String? currentListKey;

  for (final line in frontmatterText.split('\n')) {
    final trimmedLine = line.trim();
    if (trimmedLine.isEmpty || trimmedLine.startsWith('#')) continue;

    // list item: - value
    if (trimmedLine.startsWith('- ')) {
      if (currentListKey != null) {
        final item = trimmedLine.substring(2).trim();
        // 移除引號
        final cleanItem = (item.startsWith('"') && item.endsWith('"')) ||
                (item.startsWith("'") && item.endsWith("'"))
            ? item.substring(1, item.length - 1)
            : item;
        final existing = map[currentListKey];
        if (existing is List) {
          existing.add(cleanItem);
        } else {
          map[currentListKey] = [cleanItem];
        }
      }
      continue;
    }

    // key: value
    final colonIdx = trimmedLine.indexOf(':');
    if (colonIdx == -1) continue;

    final key = trimmedLine.substring(0, colonIdx).trim();
    final value = trimmedLine.substring(colonIdx + 1).trim();

    if (value.isEmpty) {
      // 可能是多行 list 的開頭（key: 後面跟 - item）
      currentListKey = key;
      map[key] = <String>[];
    } else if (value.startsWith('[') && value.endsWith(']')) {
      // inline list: [item1, item2]
      currentListKey = null;
      final inner = value.substring(1, value.length - 1);
      map[key] = inner
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      currentListKey = null;
      map[key] = value;
    }
  }

  return (map, body);
}

/// 解析 list 值
List<String> _parseList(dynamic value) {
  if (value is List) {
    return value.map((e) => e.toString()).toList();
  }
  if (value is String && value.isNotEmpty) {
    return [value];
  }
  return [];
}
