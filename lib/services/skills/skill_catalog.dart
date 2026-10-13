/// Skill Catalog — metadata-only 輕量索引（插槽輕量化 Task 1）
///
/// Hermes skills 模式的 App 版：目錄常駐記憶體，body 留磁碟懶載入。
/// 遞迴掃描 skillsDir（含子目錄），每檔只解析 frontmatter
/// （name/description/trigger_keywords/trigger_patterns/priority），
/// body 不讀進記憶體，只記 filePath + bodyOffset（body 起始位置）。
///
/// 修好的病根：SkillStore 舊世界只掃平面層——`Documents/skills/hermes/`
/// 子目錄 117 檔全死（插槽卡看得到、引擎吃不到）。SkillCatalog 遞迴掃全收。
///
/// 資料形狀抄 agency-agents 的 agents.json：slug/name/description/
/// category（頂層目錄名）/filePath。
///
/// 單例＋測試隔離照 CompanionStore 模式：`SkillCatalog.test(Directory)`
/// 建構子注入根目錄，不 import path_provider。
library;

import 'dart:convert';
import 'dart:io';

import 'skill_priority.dart';

/// Catalog 條目——只持 metadata，永不持有 body
class SkillCatalogEntry {
  /// 唯一名稱（frontmatter name）
  final String name;

  /// 一行描述
  final String description;

  /// 觸發關鍵字（精確匹配）
  final List<String> triggerKeywords;

  /// 觸發正則模式
  final List<String> triggerPatterns;

  /// 優先級
  final SkillPriority priority;

  /// 頂層目錄名（如 `hermes`）；平面層檔案為空字串
  final String category;

  /// 檔案絕對路徑
  final String filePath;

  /// body 起始的 byte offset（frontmatter 結束位置）——懶載入用
  final int bodyOffset;

  const SkillCatalogEntry({
    required this.name,
    required this.description,
    this.triggerKeywords = const [],
    this.triggerPatterns = const [],
    this.priority = SkillPriority.normal,
    required this.category,
    required this.filePath,
    required this.bodyOffset,
  });

  /// 是否具備任何觸發條件——無 trigger 的 skill 進目錄但永不被動匹配
  bool get hasTriggers =>
      triggerKeywords.isNotEmpty || triggerPatterns.isNotEmpty;

  /// 序列化（不含 body——metadata-only 的鐵證）
  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'triggerKeywords': triggerKeywords,
        'triggerPatterns': triggerPatterns,
        'priority': priority.name,
        'category': category,
        'filePath': filePath,
        'bodyOffset': bodyOffset,
      };
}

class SkillCatalog {
  static SkillCatalog? _instance;
  static SkillCatalog get instance => _instance ??= SkillCatalog._();

  /// 測試建構子——注入根目錄，隔離於全域單例
  SkillCatalog.test(Directory rootDir) : _rootOverride = rootDir;

  SkillCatalog._() : _rootOverride = null;

  final Directory? _rootOverride;
  final List<SkillCatalogEntry> _entries = [];
  bool _loaded = false;

  /// skills 根目錄路徑（測試注入優先）
  String? _skillsDirPath;

  /// 設定 skill 目錄（production 初始化路徑）
  void setSkillsDir(String path) {
    _skillsDirPath = path;
    _loaded = false; // 路徑變了要重掃
  }

  /// 所有條目（metadata-only）
  List<SkillCatalogEntry> get all => List.unmodifiable(_entries);

  /// 是否已載入
  bool get isLoaded => _loaded;

  /// 按 name 查找
  SkillCatalogEntry? find(String name) {
    for (final e in _entries) {
      if (e.name == name) return e;
    }
    return null;
  }

  /// 冪等 reload——清空重掃，單檔失敗跳過不炸全部
  Future<void> reload() async {
    _entries.clear();
    _loaded = false;

    final Directory root;
    if (_rootOverride != null) {
      root = _rootOverride;
    } else if (_skillsDirPath != null) {
      root = Directory(_skillsDirPath!);
    } else {
      return;
    }

    if (!await root.exists()) {
      _loaded = true;
      return;
    }

    // 遞迴掃描（含子目錄）——與 SkillStore 舊世界的平面掃描最大差異
    final List<FileSystemEntity> entities;
    try {
      entities = root.listSync(recursive: true, followLinks: false);
    } catch (_) {
      _loaded = true;
      return;
    }

    for (final entity in entities) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.md')) continue;

      try {
        final bytes = await entity.readAsBytes();
        final content = _decode(bytes);
        final parsed = _parseFrontmatterWindow(content);
        if (parsed == null) continue; // 無 frontmatter = 不是 skill，跳過

        final (frontmatterText, bodyOffset) = parsed;
        final meta = _parseFrontmatterMap(frontmatterText);
        final name = (meta['name'] as String?)?.trim() ?? '';
        if (name.isEmpty || name == 'unnamed') continue;

        final category = _categoryOf(root.path, entity.path);

        _entries.add(SkillCatalogEntry(
          name: name,
          description: (meta['description'] as String?) ?? '',
          triggerKeywords: _parseList(meta['trigger_keywords']),
          triggerPatterns: _parseList(meta['trigger_patterns']),
          priority: SkillPriority.fromString(meta['priority'] as String?),
          category: category,
          filePath: entity.path,
          bodyOffset: bodyOffset,
        ));
      } catch (_) {
        // 單檔失敗（IO/解析）跳過，不炸全部
        continue;
      }
    }

    _loaded = true;
  }

  /// 懶載入——從磁碟讀該條目的 body（用到才讀，讀完即棄）
  Future<String> loadBody(SkillCatalogEntry entry) async {
    final file = File(entry.filePath);
    final bytes = await file.readAsBytes();
    final content = _decode(bytes);
    if (entry.bodyOffset <= 0 || entry.bodyOffset >= content.length) {
      return content;
    }
    return content.substring(entry.bodyOffset).trim();
  }

  /// 分類＝頂層目錄名；平面層檔案為空字串
  static String _categoryOf(String rootPath, String filePath) {
    final rel = filePath.startsWith(rootPath)
        ? filePath.substring(rootPath.length)
        : filePath;
    final norm = rel.replaceAll('\\', '/').replaceFirst(RegExp(r'^/'), '');
    final slashIdx = norm.indexOf('/');
    if (slashIdx == -1) return '';
    return norm.substring(0, slashIdx);
  }

  static String _decode(List<int> bytes) {
    // 去掉 BOM 後 UTF-8 解碼（allowMalformed：壞編碼檔不炸整體掃描）
    var start = 0;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      start = 3;
    }
    return utf8.decode(bytes.sublist(start), allowMalformed: true);
  }

  /// 找出 frontmatter 窗口，回傳 (frontmatter 文字, bodyOffset)
  static (String, int)? _parseFrontmatterWindow(String content) {
    final trimmed = content.trimLeft();
    final leadingWs = content.length - trimmed.length;
    if (!trimmed.startsWith('---')) return null;

    final firstNl = trimmed.indexOf('\n');
    if (firstNl == -1) return null;

    final rest = trimmed.substring(firstNl + 1);
    final secondDelimiter = rest.indexOf('\n---');
    if (secondDelimiter == -1) return null;

    final frontmatterText = rest.substring(0, secondDelimiter);
    // bodyOffset = 邊界在原字串的位置 + "\n---".length
    final boundaryAbs =
        leadingWs + firstNl + 1 + secondDelimiter; // '\n---' 的 '\n' 位置
    final bodyOffset = boundaryAbs + 4; // skip \n---

    return (frontmatterText, bodyOffset);
  }

  /// 解析 frontmatter 文字成 map（狀態機：`key:` 開始，後續 `- item` 歸入同一 key）
  static Map<String, dynamic> _parseFrontmatterMap(String frontmatterText) {
    final map = <String, dynamic>{};
    String? currentListKey;

    for (final line in frontmatterText.split('\n')) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty || trimmedLine.startsWith('#')) continue;

      if (trimmedLine.startsWith('- ')) {
        if (currentListKey != null) {
          final item = trimmedLine.substring(2).trim();
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

      final colonIdx = trimmedLine.indexOf(':');
      if (colonIdx == -1) continue;

      final key = trimmedLine.substring(0, colonIdx).trim();
      final value = trimmedLine.substring(colonIdx + 1).trim();

      if (value.isEmpty) {
        currentListKey = key;
        map[key] = <String>[];
      } else if (value.startsWith('[') && value.endsWith(']')) {
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

    return map;
  }

  static List<String> _parseList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String && value.isNotEmpty) {
      return [value];
    }
    return [];
  }
}
