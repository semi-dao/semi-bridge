// Skill Intake Service 測試——背景入庫＋冪等建卡（插槽輕量化 Task 4B）
//
// 測試範圍：
// 1. intakeFromDir：掃 .md（遞迴）→ 複製進 skillsDir/<category>/ → catalog reload
// 2. 冪等：重跑第二次 0 新增（目標 .md 已存在跳過；插槽卡已存在跳過）
// 3. SlotRegistry 建卡：skill://<origin>__<name>、category='顧問模式'、origin 標記
// 4. 入庫後 skillSearch 找得到（管線打通）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/skills/skill_catalog.dart';
import 'package:bridge_app/services/skills/skill_intake_service.dart';
import 'package:bridge_app/services/skills/skill_tools.dart';
import 'package:bridge_app/services/slots/slot_registry.dart';

void main() {
  late Directory tmp;
  late Directory skillsDir;
  late SlotRegistry registry;
  late SkillCatalog catalog;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('skill_intake_test_');
    skillsDir = Directory('${tmp.path}/skills');
    await Directory('${skillsDir.path}/hermes').create(recursive: true);
    await Directory('${skillsDir.path}/測試移民').create(recursive: true);

    final appRoot = Directory('${tmp.path}/app');
    await appRoot.create(recursive: true);
    registry = SlotRegistry.test(appRoot);
    await registry.ensureLoaded();

    catalog = SkillCatalog.test(skillsDir);
    await catalog.reload();
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  Future<SkillIntakeService> makeService() async => SkillIntakeService(
        catalog: catalog,
        skillsDir: skillsDir,
        registry: registry,
      );

  test('掃遞迴 .md → 複製進 skillsDir/<category>/ + 建卡 + catalog reload', () async {
    final source = Directory('${tmp.path}/source');
    await Directory('${source.path}/nested/deep').create(recursive: true);
    await File('${source.path}/expert-a.md').writeAsString('''---
name: expert-a
description: 測試專家 A
---

EXPERT_A_BODY。
''');
    await File('${source.path}/nested/expert-b.md').writeAsString('''---
name: expert-b
description: 測試專家 B
---

EXPERT_B_BODY。
''');
    // 非 .md 忽略
    await File('${source.path}/nested/notes.txt').writeAsString('not md');

    final svc = await makeService();
    final report = await svc.intakeFromDir(
      source.path,
      category: '測試移民',
      origin: 'test-source',
    );

    expect(report.scanned, 2);
    expect(report.imported, 2);
    expect(report.skippedExisting, 0);
    expect(report.cardsCreated, 2);

    // 檔案複製到位（子目錄拍平成 <category>/<flat-name>.md）
    final flatA = File('${skillsDir.path}/測試移民/test-source__expert-a.md');
    expect(await flatA.exists(), isTrue, reason: 'flat: ${flatA.path}');
    expect(await flatA.readAsString(), contains('EXPERT_A_BODY'));

    // 插槽卡：skill://test-source__expert-a、origin 標記
    final card =
        registry.all.where((s) => s.sourceRepo == 'skill://test-source__expert-a').toList();
    expect(card.length, 1);
    expect(card.first.userLabel, 'expert-a');
    expect(card.first.category, '測試移民');
    expect(card.first.origin, 'test-source');

    // catalog reload 過——搜尋找得到
    final result = await SkillTools.search(catalog, '專家 A',
        disabledNames: SkillTools.disabledSkillNames(registry));
    final names = ((result.toJson()['results'] as List)
            .cast<Map<String, dynamic>>())
        .map((r) => r['name'])
        .toList();
    expect(names, contains('expert-a'));
  });

  test('冪等：重跑第二次 imported=0、卡片不重複', () async {
    final source = Directory('${tmp.path}/source');
    await source.create(recursive: true);
    await File('${source.path}/expert-a.md').writeAsString('''---
name: expert-a
description: 測試專家 A
---

EXPERT_A_BODY。
''');

    final svc = await makeService();
    final first = await svc.intakeFromDir(
      source.path,
      category: '測試移民',
      origin: 'test-source',
    );
    expect(first.imported, 1);
    expect(first.cardsCreated, 1);

    final second = await svc.intakeFromDir(
      source.path,
      category: '測試移民',
      origin: 'test-source',
    );
    expect(second.scanned, 1);
    expect(second.imported, 0);
    expect(second.cardsCreated, 0);
    expect(registry.all.where((s) => s.sourceRepo == 'skill://test-source__expert-a').length, 1);
  });

  test('目標 .md 已存在（外部先放好）→ 跳過複製但補建卡', () async {
    final source = Directory('${tmp.path}/source');
    await source.create(recursive: true);
    await File('${source.path}/expert-c.md').writeAsString('''---
name: expert-c
description: 測試專家 C
---

EXPERT_C_BODY。
''');
    // 預先放好目標檔（模擬既有檔案）
    final dest = File('${skillsDir.path}/測試移民/test-source__expert-c.md');
    await dest.writeAsString('''---
name: expert-c
description: 預先存在的版本
---

PRE_EXISTING。
''');

    final svc = await makeService();
    final report = await svc.intakeFromDir(
      source.path,
      category: '測試移民',
      origin: 'test-source',
    );
    expect(report.imported, 0);
    expect(report.skippedExisting, 1);
    // 不覆寫
    expect(await dest.readAsString(), contains('PRE_EXISTING'));
    // 卡照建（檔案在庫就該有卡——管理真相源一致性）
    expect(report.cardsCreated, 1);
  });

  test('無 frontmatter 的 .md 誠實跳過（不硬搬）', () async {
    final source = Directory('${tmp.path}/source');
    await source.create(recursive: true);
    await File('${source.path}/plain.md').writeAsString('普通文字，沒有 frontmatter');

    final svc = await makeService();
    final report = await svc.intakeFromDir(
      source.path,
      category: '測試移民',
      origin: 'test-source',
    );
    expect(report.scanned, 1);
    expect(report.imported, 0);
    expect(report.failed, 1);
    expect(report.errors, isNotEmpty);
  });

  test('來源目錄不存在 → 全 0 報告（不炸）', () async {
    final svc = await makeService();
    final report = await svc.intakeFromDir(
      '${tmp.path}/nope',
      category: '測試移民',
      origin: 'test-source',
    );
    expect(report.scanned, 0);
    expect(report.imported, 0);
  });
}
