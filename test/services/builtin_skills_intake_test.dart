// BuiltinSkillsIntake 回歸測試——收編語義（首啟收編、冪等、卸載不還魂）
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/slots/builtin_skills_intake.dart';
import 'package:bridge_app/services/slots/slot_registry.dart';
import 'package:bridge_app/services/skills/skill.dart';
import 'package:bridge_app/services/skills/skill_store.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('builtin_intake_test_');
    final skillsDir = Directory('${tmp.path}/skills');
    await skillsDir.create(recursive: true);
    await File('${skillsDir.path}/grill-me.md').writeAsString('''
---
name: grill-me
description: 測試用 skill
version: 1
---
內容
''');
    SlotRegistry.instance.resetForTest();
    SlotRegistry.instance.setRootOverride(tmp);
    resetBuiltinSkillsIntakeForTest();
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('首啟收編：skill:// 來源、核心技能分類、🟢零權限、認證', () async {
    await SkillStore.instance.initialize(skillsDir: '${tmp.path}/skills');
    await BuiltinSkillsIntake.instance.runIfNeeded();

    final slots = SlotRegistry.instance.all;
    expect(slots.length, 1);
    final s = slots.first;
    expect(s.sourceRepo, 'skill://grill-me');
    expect(s.category, '核心技能');
    expect(s.permissions, isEmpty); // 🟢 零權限
    // 除錯：印出實際值
    expect(s.certified, isTrue);
    expect(s.isRunning, isTrue);
  });

  test('冪等：第二次 run 不重複收編', () async {
    await SkillStore.instance.initialize(skillsDir: '${tmp.path}/skills');
    await BuiltinSkillsIntake.instance.runIfNeeded();
    await BuiltinSkillsIntake.instance.runIfNeeded();

    expect(SlotRegistry.instance.all.length, 1);
  });

  test('卸載不還魂：使用者刪光 builtin 後 run 不再收編', () async {
    await SkillStore.instance.initialize(skillsDir: '${tmp.path}/skills');
    await BuiltinSkillsIntake.instance.runIfNeeded();

    // 使用者卸載全部
    for (final s in List.of(SlotRegistry.instance.all)) {
      await SlotRegistry.instance.uninstall(s.id, deleteData: true);
    }
    expect(SlotRegistry.instance.all, isEmpty);

    // 重啟 App（新 intake instance）——不還魂
    final idxContent = await File('${tmp.path}/slots/index.json').readAsString();
    resetBuiltinSkillsIntakeForTest();
    await BuiltinSkillsIntake.instance.runIfNeeded();
    final after = SlotRegistry.instance.all;
    expect(after, isEmpty, reason: '使用者已卸載，不得還魂');
  });
}
