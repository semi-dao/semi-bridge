// 匯入器 test harness——CLI 驅動 App 內部邏輯唯一正解（dart run 在 flutter 專案內 SDK 汙染）
// 跑法：
//   dry-run：flutter test test/tools/run_agency_import_test.dart --plain-name "匯入器"
//   真匯入：AGENCY_IMPORT_LIVE=1 flutter test test/tools/run_agency_import_test.dart --plain-name "匯入器"
// BRIDGE_APP_HOME 指向 App 資料根目錄（含 skills/ 與 slots/）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/skills/skill_agency_importer.dart';
import 'package:bridge_app/services/skills/skill_catalog.dart';
import 'package:bridge_app/services/slots/slot_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('匯入器', () async {
    final home = Platform.environment['BRIDGE_APP_HOME'];
    final live = Platform.environment['AGENCY_IMPORT_LIVE'] == '1';
    // [開源整備] 匯入測試需要本機 agency-agents 資料——未設環境時 skip。
    if (home == null) {
      print('SKIP：需要 BRIDGE_APP_HOME 指向 App 資料根目錄');
      return;
    }
    final source = Platform.environment['AGENCY_IMPORT_SOURCE'] ?? '';
    expect(home, isNotNull,
        reason: '必須設 BRIDGE_APP_HOME（不猜路徑——誠實鐵則）');

    final registry = SlotRegistry.test(Directory('$home/slots'));
    await registry.ensureLoaded();
    final catalog = SkillCatalog.test(Directory('$home/skills'));

    final importer = SkillAgencyImporter(
      skillsDir: Directory('$home/skills'),
      registry: registry,
      catalog: catalog,
    );
    final result = await importer.importFromJson(source, dryRun: !live);
    // RESULT 標記讓 CLI 抓輸出
    print('RESULT ${live ? "LIVE" : "DRY-RUN"} '
        'total=${result.total} green=${result.green} yellow=${result.yellow} '
        'red=${result.red} imported=${result.imported} '
        'skippedExisting=${result.skippedExisting} '
        'errors=${result.errors.length}');
    expect(result.errors, isEmpty, reason: result.errors.take(3).join('; '));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
