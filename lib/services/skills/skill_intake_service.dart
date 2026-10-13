/// Skill Intake Service — 背景入庫＋自動建卡（插槽輕量化 Task 4B）
///
/// Agent 對話「收進來」與精靈分流共用的單一入口：
/// 掃來源目錄所有 .md（遞迴）→ 複製進 `skillsDir/<category>/` 目錄
/// （檔名 `<origin>__<name>.md`）
/// → SkillCatalog.reload() → SlotRegistry 建卡（`skill://<origin>__<name>`、
/// origin 標記）。
///
/// 模式照 `hermes_skills_migration.dart` 的既有套路，三個差異：
/// 1. 不只收 SKILL.md——所有 .md 都收（GitHub repo 常見是任意檔名）
/// 2. 目標 .md 已存在就跳過（**不覆寫**——本地可能已被使用者改過）
/// 3. 回傳結構化 [SkillIntakeReport]（scanned/imported/cardsCreated/...），
///    agent 對話可直接唸數字給使用者聽
///
/// 冪等：重跑第二次 imported=0、卡片不重複。
/// 失敗誠實：無 frontmatter 的 .md 記進 report.errors，不硬搬不裝成功。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../slots/slot_registry.dart';
import 'skill_catalog.dart';

/// 入庫報告——數字誠實呈現
class SkillIntakeReport {
  /// 掃到的 .md 總數
  final int scanned;

  /// 實際複製進 skillsDir 的數
  final int imported;

  /// 目標已存在而跳過複製的數
  final int skippedExisting;

  /// 建立（或補齊）的插槽卡數
  final int cardsCreated;

  /// 解析/複製失敗數
  final int failed;

  /// 失敗明細（誠實鐵則——失敗要能說出是哪個檔案、什麼錯）
  final List<String> errors;

  const SkillIntakeReport({
    required this.scanned,
    required this.imported,
    required this.skippedExisting,
    required this.cardsCreated,
    required this.failed,
    required this.errors,
  });

  Map<String, dynamic> toJson() => {
        'scanned': scanned,
        'imported': imported,
        'skippedExisting': skippedExisting,
        'cardsCreated': cardsCreated,
        'failed': failed,
        if (errors.isNotEmpty) 'errors': errors,
      };

  @override
  String toString() =>
      'SkillIntakeReport(掃到 $scanned、入庫 $imported、已有 $skippedExisting、'
      '建卡 $cardsCreated、失敗 $failed)';
}

class SkillIntakeService {
  final SkillCatalog catalog;
  final Directory skillsDir;
  final SlotRegistry registry;

  /// 插槽卡分類 fallback（呼叫方沒指定 category 時用）
  static const String defaultCategory = '未分類';

  SkillIntakeService({
    required this.catalog,
    required this.skillsDir,
    required this.registry,
  });

  /// 從來源目錄入庫（冪等）。
  ///
  /// [sourceDir] 來源目錄（遞迴掃 .md）
  /// [category] 插槽卡分類＋skillsDir 子目錄名（如「顧問模式」「Hermes 移民」）
  /// [origin] 出身標記（如 'agency-agents'、'github:<repo>'）——
  ///          目標檔名與卡片 sourceRepo 都帶 origin，防不同來源撞名
  Future<SkillIntakeReport> intakeFromDir(
    String sourceDir, {
    String? category,
    required String origin,
  }) async {
    final effectiveCategory =
        (category == null || category.isEmpty) ? defaultCategory : category;
    final src = Directory(sourceDir);
    if (!await src.exists()) {
      return const SkillIntakeReport(
        scanned: 0,
        imported: 0,
        skippedExisting: 0,
        cardsCreated: 0,
        failed: 0,
        errors: [],
      );
    }

    final destDir = Directory('${skillsDir.path}/$effectiveCategory');
    await destDir.create(recursive: true);

    final errors = <String>[];
    var scanned = 0;
    var imported = 0;
    var skippedExisting = 0;
    var cardsCreated = 0;

    // 收集所有 .md（遞迴、跳符號連結）
    final mdFiles = <File>[];
    try {
      for (final e in src.listSync(recursive: true, followLinks: false)) {
        if (e is File && e.path.toLowerCase().endsWith('.md')) {
          mdFiles.add(e);
        }
      }
    } catch (e) {
      errors.add('掃描來源目錄失敗：$e');
    }
    scanned = mdFiles.length;

    await registry.ensureLoaded();
    // 已有的 skill:// 卡（冪等對位用）
    final existingRepos =
        registry.all.map((s) => s.sourceRepo).toSet();

    for (final f in mdFiles) {
      try {
        final content = await f.readAsString();
        final name = _frontmatterName(content);
        if (name == null || name.trim().isEmpty) {
          errors.add('${f.path}：無 frontmatter name——不硬搬');
          continue;
        }
        final cleanName = name.trim();

        // 目標：skillsDir/<category>/<origin>__<name>.md（拍平＋origin 防撞名）
        final flatName = '${origin}__$cleanName';
        final dest = File('${destDir.path}/$flatName.md');

        if (!await dest.exists()) {
          await dest.writeAsString(content);
          imported++;
        } else {
          skippedExisting++; // 不覆寫——本地版本為準
        }

        // 建卡（冪等：卡已存在跳過；檔案在庫就該有卡——含 skipped 補卡）
        final repo = 'skill://$flatName';
        if (!existingRepos.contains(repo)) {
          final record = await registry.addFromRepo(
            repo,
            label: cleanName,
            category: effectiveCategory,
          );
          // origin 出身標記（SlotRecord [H1] 欄）
          await registry
              .update(registry.getById(record.id)!.copyWith(origin: origin));
          // 知識型 skill 零權限直接啟用（照 hermes_skills_migration 模式）——
          // 不啟用會停在 pending，被 disabledSkillNames 排除、搜尋找不到
          await registry.enableWithPermissions(record.id, const []);
          existingRepos.add(repo);
          cardsCreated++;
        }
      } catch (e) {
        errors.add('${f.path}：$e');
      }
    }

    // catalog 重掃——入庫即可搜尋/匹配
    await catalog.reload();

    if (errors.isNotEmpty) {
      debugPrint('[SkillIntakeService] 失敗 ${errors.length} 筆：${errors.take(3)}');
    }

    return SkillIntakeReport(
      scanned: scanned,
      imported: imported,
      skippedExisting: skippedExisting,
      cardsCreated: cardsCreated,
      failed: errors.length,
      errors: errors,
    );
  }

  /// 萃取 frontmatter name（`name: xxx`）。沒有回 null。
  static String? _frontmatterName(String content) {
    final m = RegExp(r'^---\s*\n(.*?\n)---', dotAll: true).firstMatch(content);
    if (m == null) return null;
    final nm =
        RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(m.group(1)!);
    return nm?.group(1)?.trim();
  }
}
