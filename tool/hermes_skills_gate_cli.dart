// Hermes Skills 入境安檢工具（開發期一次性，dart run 執行）
//
// 用法：dart run tool/hermes_skills_gate_cli.dart
// 產出：/tmp/hermes_skills_audit_report.md（Blue 過目）
//
// 不搬任何檔案——純掃描報告。放行清單確立後才由 migration 搬入。

import 'dart:io';
import '../lib/services/slots/hermes_skills_gate.dart';

Future<void> main() async {
  final hermesDir = Platform.environment['HOME']! + '/.hermes/skills';
  // 本土既有 skill 名（避免重複移民）
  final localSkills = Directory(Platform.environment['HOME']! + '/Documents/skills')
      .listSync()
      .whereType<File>()
      .map((f) => f.path.split('/').last.replaceAll('.md', ''))
      .toSet();

  final reports = await HermesSkillsGate.audit(
    hermesSkillsDir: hermesDir,
    existingSkillNames: localSkills,
  );

  await HermesSkillsGate.writeReport(
      reports, '/tmp/hermes_skills_audit_report.md');

  final green = reports.where((r) => r.verdict == 'GREEN').length;
  final yellow = reports.where((r) => r.verdict == 'YELLOW').length;
  final red = reports.where((r) => r.verdict == 'RED').length;
  final skip = reports.where((r) => r.verdict == 'SKIP_LOCAL').length;
  stdout.writeln('=== 安檢完成 ===');
  stdout.writeln('總計 ${reports.length}：🟢$green 🟡$yellow 🔴$red ⏭️$skip');
  stdout.writeln('報告：/tmp/hermes_skills_audit_report.md');
}
