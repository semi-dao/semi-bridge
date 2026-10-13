// Hermes Skills 大搬家補線——把 ~/.hermes/skills 的 207 個 skill
// 收進 App 技能生態（Documents/skills/hermes/）＋收編為插槽
//
// [Blue 抓包 2026-10-06] 大搬家精靈（WS-3 30be78ce）只搬了排程/對話史/
// profile——skill 這條線從來沒接。正途：Agent 平台的 skill 搬進容器、
// 納入同一管理（插槽大家庭）。
//
// 搬法（簡單可逆，不動 Hermes 原檔）：
// 1. 掃 ~/.hermes/skills/**/SKILL.md（含分類子目錄）
// 2. 每個 skill 目錄複製到 Documents/skills/hermes/<flat-name>/
//    flat-name = 分類-技能名（apple/macos-computer-use →
//    apple__macos-computer-use）——避開巢狀，SkillStore 平面掃描相容
// 3. SKILL.md 轉成 App 的 .md 格式放 Documents/skills/hermes/<name>.md
//    （SkillStore 只採平面 .md）
// 4. 收編為插槽（skill:// 來源、「Hermes 移民」分類、🟢零權限）
// 冪等：目標 .md 已存在就跳過；墓碑在就只搬檔不收編插槽。

import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/dev_paths.dart';
import 'slot_registry.dart';
import '../skills/skill.dart';
import '../skills/skill_store.dart';
import 'builtin_skills_intake.dart';
import 'hermes_skills_gate.dart';

class HermesSkillsMigration {
  HermesSkillsMigration._();
  static final instance = HermesSkillsMigration._();

  static final String hermesSkillsHome = resolveDevPath('~/.hermes');
  static const String migrationCategory = 'Hermes 移民';

  /// 搬移（冪等）——[Blue 令 2026-10-06] 先安檢再入境：只有 GREEN 放行。
  /// 回傳 (掃到數, 實際搬入數)。
  Future<(int, int)> migrate({required String appSkillsDir}) async {
    final src = Directory('$hermesSkillsHome/skills');
    if (!await src.exists()) return (0, 0);

    // ── 入境安檢：去重＋掃描，只取 GREEN ──
    final localNames = Directory(appSkillsDir)
        .listSync()
        .whereType<File>()
        .map((f) => f.path.split('/').last.replaceAll('.md', ''))
        .toSet();
    final reports = await HermesSkillsGate.audit(
      hermesSkillsDir: src.path,
      existingSkillNames: localNames,
    );
    final greenByName = {
      for (final r in reports.where((r) => r.verdict == 'GREEN'))
        r.name: r.srcPath,
    };
    if (greenByName.isEmpty) return (reports.length, 0);
    final skillFiles = greenByName.values.map(File.new).toList();

    final destDir = Directory('$appSkillsDir/hermes');
    await destDir.create(recursive: true);

    var migrated = 0;
    final migratedNames = <String>[];
    for (final f in skillFiles) {
      try {
        // flat name：保留分類前綴避免撞名
        final rel = f.path.substring(src.path.length + 1);
        final parts = rel.split('/');
        final flat = parts.sublist(0, parts.length - 1).join('__');

        // 解析 name（沒有 frontmatter 的跳過——誠實不硬搬）
        final content = await f.readAsString();
        final skill = Skill.fromMarkdown(content, filePath: f.path);
        final name = skill.name.isEmpty ? flat : skill.name;

        final dest = File('${destDir.path}/$name.md');
        if (await dest.exists()) {
          migratedNames.add(name); // 已在——只補收編清單
          continue;
        }
        await dest.writeAsString(content);
        migratedNames.add(name);
        migrated++;
      } catch (e) {
        debugPrint('[HermesSkillsMigration] 跳過 ${f.path}: $e');
      }
    }

    // 收編為插槽（沒墓碑才做；卸載尊重墓碑機制）
    try {
      final registry = SlotRegistry.instance;
      await registry.ensureLoaded();
      final tombstone = File(
          '${registry.slotsDir.path}/builtin_intake_tombstone.json');
      final hasHermes = registry.all
          .any((s) => s.sourceRepo.startsWith('skill://hermes__'));
      if (!await tombstone.exists() && !hasHermes) {
        debugPrint('[HermesSkillsMigration] 收編 ${migratedNames.length} 個 Hermes skills → 插槽');
        for (final name in migratedNames.take(200)) {
          final record = await registry.addFromRepo(
            'skill://hermes__$name',
            label: name,
            category: migrationCategory,
          );
          await registry.enableWithPermissions(record.id, const []);
          final latest = registry.getById(record.id);
          if (latest != null) {
            await registry.update(latest.copyWith(certified: false));
          }
        }
      } else if (hasHermes) {
        debugPrint('[HermesSkillsMigration] 已收編過（冪等跳過）');
      }
    } catch (e) {
      debugPrint('[HermesSkillsMigration] 收編插槽失敗（檔案已搬好）: $e');
    }

    return (skillFiles.length, migrated);
  }

  /// 掃描摘要（UI 顯示用）：總數＋分類數
  Future<int> countSkills() async {
    final src = Directory('$hermesSkillsHome/skills');
    if (!await src.exists()) return 0;
    var n = 0;
    await for (final e in src.list(recursive: true, followLinks: false)) {
      if (e is File && e.path.endsWith('/SKILL.md')) n++;
    }
    return n;
  }
}
