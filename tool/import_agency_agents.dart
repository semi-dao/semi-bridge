/// agency-agents 282 人格匯入 CLI（開發期一次性腳本，插槽輕量化 Task 5）
///
/// 來源：~/.hermes/plugins/agency-agents-router/data/agents.json
/// 去處：`BRIDGE_APP_HOME/skills/agency-agents/` 底下每 agent 一支 .md ＋ 插槽總卡一張
///
/// ⚠️ [Blue 令 2026-10-13] 匯入由 Blue 親自驗收數字後才跑。
/// 建議順序：
///   1. `dart run tool/import_agency_agents.dart --dry-run`   # 只安檢，看 RED/YELLOW/GREEN 數字
///   2. 數字過目後：`dart run tool/import_agency_agents.dart`  # 真匯入
///
/// 冪等：重跑即同步上游（已存在的 .md 不覆寫）。
///
/// 注意：腳本需要在 App 容器外指定 skillsDir 與 slots 目錄——
/// 預設用 BRIDGE_APP_HOME 環境變數（與 App 相同的覆寫機制），
/// 未設定時印出用法並退出（不猜路徑——誠實鐵則）。
library;

import 'dart:io';

import 'package:bridge_app/services/skills/skill_agency_importer.dart';
import 'package:bridge_app/services/skills/skill_catalog.dart';
import 'package:bridge_app/services/slots/slot_registry.dart';

final String defaultSource =
    Platform.environment['AGENCY_AGENTS_JSON'] ?? Platform.environment['HOME']! + '/.hermes/plugins/agency-agents-router/data/agents.json';

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final sourcePath = args
      .where((a) => a.startsWith('--source='))
      .map((a) => a.substring('--source='.length))
      .firstOrNull ??
      defaultSource;

  final home = Platform.environment['BRIDGE_APP_HOME'];
  if (home == null || home.isEmpty) {
    stderr.writeln('''
用法：
  BRIDGE_APP_HOME=<App 資料根目錄> dart run tool/import_agency_agents.dart [--dry-run] [--source=<agents.json 路徑>]

BRIDGE_APP_HOME 未設定——不猜路徑（誠實鐵則）。App 容器內的
skillsDir = <BRIDGE_APP_HOME>/skills、slots = <BRIDGE_APP_HOME>/slots。
''');
    exit(2);
  }

  final skillsDir = Directory('$home/skills');
  await skillsDir.create(recursive: true);

  final registry = SlotRegistry.instance;
  SlotRegistry.init(Directory(home));
  await registry.ensureLoaded();

  final catalog = SkillCatalog.instance;
  catalog.setSkillsDir(skillsDir.path);
  await catalog.reload();

  final importer = SkillAgencyImporter(
    skillsDir: skillsDir,
    registry: registry,
    catalog: catalog,
  );

  stdout.writeln(
      '來源：$sourcePath\n入庫：${skillsDir.path}/agency-agents/\n模式：${dryRun ? 'DRY RUN（只安檢不寫入）' : '真匯入'}\n');

  final report = await importer.importFromJson(sourcePath, dryRun: dryRun);

  stdout.writeln('''
═══ 匯入報告 ═══
總計 ${report.total}：🟢 GREEN ${report.green}｜🟡 YELLOW ${report.yellow}｜🔴 RED ${report.red}
入庫 ${report.imported}｜已存在跳過 ${report.skippedExisting}
${report.errors.isEmpty ? '' : '錯誤 ${report.errors.length} 筆：\n${report.errors.take(10).join('\n')}'}
${dryRun ? '\n（dry run——未寫入任何檔案、未建卡。數字過目後拿掉 --dry-run 真匯入。）' : '\n完成：skills/agency-agents/ ＋ 插槽總卡「${SkillAgencyImporter.libraryLabel}」'}
''');

  // RED 明細落檔（人工複審用）
  final redFiles = report.files.where((f) => f.verdict == 'RED').toList();
  if (redFiles.isNotEmpty) {
    final outFile = File('${skillsDir.path}/agency-agents-import-red-report.md');
    final buf = StringBuffer('# agency-agents 匯入安檢 RED 明細\n\n');
    buf.writeln('時間：${DateTime.now()}｜RED 共 ${redFiles.length}\n');
    for (final r in redFiles) {
      buf.writeln('- **${r.slug}**（${r.division}，${r.contentChars} 字）');
      for (final finding in r.findings) {
        buf.writeln('  - $finding');
      }
    }
    await outFile.writeAsString(buf.toString());
    stdout.writeln('RED 明細：${outFile.path}');
  }
}
