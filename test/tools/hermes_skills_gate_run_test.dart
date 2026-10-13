// 安檢跑批（test harness 包裝——dart run 被 flutter 汙染，借 test runner 跑）
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/slots/hermes_skills_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Hermes skills 入境安檢跑批', () async {
    // [開源整備] 此測試掃描本機 Hermes skills（~/.hermes/skills 與 ~/Documents/skills）
    // ——內容因人而異，僅 opt-in（HERMES_GATE_TEST=1）時執行；CI / fresh clone skip。
    if (Platform.environment['HERMES_GATE_TEST'] != '1' ||
        !Directory(Platform.environment['HOME']! + '/.hermes/skills').existsSync()) {
      // ignore: avoid_print
      print('SKIP：安檢跑批需要本機 Hermes skills 資料（HERMES_GATE_TEST=1）');
      return;
    }
    final home = Platform.environment['HOME']!;
    final localSkills = Directory('$home/Documents/skills')
        .listSync()
        .whereType<File>()
        .map((f) => f.path.split('/').last.replaceAll('.md', ''))
        .toSet();

    final reports = await HermesSkillsGate.audit(
      hermesSkillsDir: '$home/.hermes/skills',
      existingSkillNames: localSkills,
    );

    await HermesSkillsGate.writeReport(
        reports, '/tmp/hermes_skills_audit_report.md');

    final green = reports.where((r) => r.verdict == 'GREEN').length;
    final yellow = reports.where((r) => r.verdict == 'YELLOW').length;
    final red = reports.where((r) => r.verdict == 'RED').length;
    final skip = reports.where((r) => r.verdict == 'SKIP_LOCAL').length;
    // ignore: avoid_print
    print('RESULT 總計 ${reports.length}：GREEN=$green YELLOW=$yellow RED=$red SKIP=$skip');
    expect(reports, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
