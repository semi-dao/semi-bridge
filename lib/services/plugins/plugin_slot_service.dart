/// Plugin Slot Service — agent-plugins.org plugin 分支的核心（A線 刀2）
///
/// [A線 2026-10-22] SlotInstaller 探到 `.cursor-plugin/plugin.json` 後交棒：
/// 1. skills 進庫：複用 SkillIntakeService 的複製模式（遞迴掃 .md，
///    落點 `skillsDir/<category>/<pluginName>` 雙底線 `<skillName>.md`，
///    origin 前綴防撞名，不覆寫）——**但跳過逐檔建卡**（卡粒度設計：
///    一個 plugin 一張插槽卡，56 張卡會塞爆插槽頁）。
/// 2. SlotRegistry 建一張卡（manifest 建卡：label=displayName||name、
///    version、origin='agent-plugins.org'）→ enableWithPermissions(id, [])。
/// 3. 卸載掃除：按 `<pluginName>` 雙底線前綴掃掉 skillsDir 檔案＋catalog
///    reload（uninstall 只刪 slots/`<id>`/，不掃這裡會留幽靈 skills）。
///
/// 不碰：SkillCatalog 解析器、SlotRecord schema、watchdog。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../skills/skill_catalog.dart';
import 'plugin_manifest.dart';

/// plugin 入庫報告——數字誠實呈現
class PluginSlotReport {
  /// 掃到的 skills .md 總數
  final int scanned;

  /// 實際複製進 skillsDir 的數
  final int imported;

  /// 目標已存在而跳過的數（不覆寫——本地版本為準）
  final int skippedExisting;

  /// 卸載掃除刪掉的檔案數（安裝路徑恆 0）
  final int removed;

  const PluginSlotReport({
    required this.scanned,
    required this.imported,
    required this.skippedExisting,
    this.removed = 0,
  });

  @override
  String toString() =>
      'PluginSlotReport(掃 $scanned、入 $imported、跳 $skippedExisting、刪 $removed)';
}

class PluginSlotService {
  /// 出身標記（插槽卡徽章用——「agent-plugins.org 出身」）
  static const String origin = 'agent-plugins.org';

  /// 分類 fallback（manifest category 映射不到插槽分類時歸這）
  static const String defaultCategory = '未分類';

  /// [A線] manifest category → 插槽分類映射。
  /// agent-plugins.org 用 kebab-case 英文（developer-tools 等）；
  /// 插槽既有中文分類（SlotRegistry.categoryDescription）。
  /// 映射不到 → null（呼叫方歸 defaultCategory）。
  static String? mapCategory(String? manifestCategory) {
    switch (manifestCategory) {
      case 'developer-tools':
      case 'dev-tools':
        return '開發技能';
      case 'content-creation':
      case 'creative':
        return '內容創作';
      case 'research':
      case 'productivity':
        return '研究調查';
      case 'lifestyle':
      case 'communication':
        return '生活助理';
      default:
        return null;
    }
  }

  final SkillCatalog catalog;
  final Directory skillsDir;

  PluginSlotService({
    required this.catalog,
    required this.skillsDir,
  });

  /// skills 進庫（冪等、不逐檔建卡）——照 SkillIntakeService L109-155 複製模式。
  ///
  /// 回 null＝skills 目錄不存在或無可收檔案（呼叫方決定算不算失敗）。
  Future<PluginSlotReport?> importSkills(PluginManifest manifest) async {
    final skillsPath = manifest.skillsDirPath;
    if (skillsPath == null) {
      debugPrint('[PluginSlotService] skills 路徑逃脫 root，拒收：${manifest.name}');
      return null;
    }
    final src = Directory(skillsPath);
    if (!await src.exists()) {
      debugPrint('[PluginSlotService] skills 目錄不存在：$skillsPath');
      return null;
    }

    final destDir = Directory('${skillsDir.path}/$origin');
    await destDir.create(recursive: true);

    // 收集所有 .md（遞迴、跳符號連結）——含 SKILL.md 與其他任意檔名
    final mdFiles = <File>[];
    for (final e in src.listSync(recursive: true, followLinks: false)) {
      if (e is File && e.path.toLowerCase().endsWith('.md')) {
        mdFiles.add(e);
      }
    }
    if (mdFiles.isEmpty) return null;

    var imported = 0;
    var skippedExisting = 0;
    for (final f in mdFiles) {
      // skill 名取 frontmatter `name:`，沒有則檔名去 .md（寬容——
      // SkillCatalog 本身會濾掉無 frontmatter 的檔，這裡先收著）
      final content = await f.readAsString();
      final fmName = _frontmatterName(content) ??
          f.uri.pathSegments.last.replaceAll(RegExp(r'\.md$', caseSensitive: false), '');
      if (fmName.isEmpty) continue;

      // 目標：skillsDir/<origin>/<pluginName>__<skillName>.md（拍平＋前綴防撞名）
      final flatName = '${manifest.name}__$fmName';
      final dest = File('${destDir.path}/$flatName.md');
      if (!await dest.exists()) {
        await dest.writeAsString(content);
        imported++;
      } else {
        skippedExisting++; // 不覆寫——本地版本為準
      }
    }

    // catalog 重掃——入庫即可搜尋/匹配
    await catalog.reload();

    return PluginSlotReport(
      scanned: mdFiles.length,
      imported: imported,
      skippedExisting: skippedExisting,
    );
  }

  /// 卸載掃除：按 `<pluginName>` 前綴（即雙底線 `__` 前綴）刪 skillsDir 下的
  /// .md ＋ catalog reload。
  ///
  /// [A線] uninstall 只刪 `slots/<id>/`，skillsDir 幽靈檔這裡掃。
  /// 回傳刪掉的檔案數（誠實回報）。
  Future<int> removePluginSkills(String pluginName) async {
    final prefix = '${pluginName}__';
    final dir = Directory(skillsDir.path);
    var removed = 0;
    if (!await dir.exists()) return 0;
    final entities = dir.listSync(recursive: true, followLinks: false);
    for (final e in entities) {
      if (e is! File) continue;
      if (!e.path.toLowerCase().endsWith('.md')) continue;
      final base = e.uri.pathSegments.last;
      if (base.startsWith(prefix)) {
        try {
          await e.delete();
          removed++;
        } catch (err) {
          debugPrint('[PluginSlotService] 刪除失敗（跳過）: ${e.path}: $err');
        }
      }
    }
    if (removed > 0) {
      await catalog.reload();
      debugPrint('[PluginSlotService] 卸載掃除 $pluginName：刪 $removed 個 skills');
    }
    return removed;
  }

  /// 萃取 frontmatter name（`name: xxx`）——照 SkillIntakeService 的規則。
  static String? _frontmatterName(String content) {
    final m = RegExp(r'^---\s*\n(.*?\n)---', dotAll: true).firstMatch(content);
    if (m == null) return null;
    final nm =
        RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(m.group(1)!);
    return nm?.group(1)?.trim();
  }
}
