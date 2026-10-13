// SkillPromptInjector 注入分級測試（插槽輕量化 Task 3）
//
// 雲端模式：top-1 注入完整 body，其餘注摘要卡（name+description+skill_load 提示）。
// localMode：維持 1×800 字截斷（本地模型無工具呼叫，截斷是天花板）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/skills/skill_catalog.dart';
import 'package:bridge_app/services/skills/skill_prompt_injector.dart';

void main() {
  late Directory tmp;
  late SkillCatalog catalog;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('skill_injector_test_');
    final skillsDir = Directory('${tmp.path}/skills');
    await Directory('${skillsDir.path}/hermes').create(recursive: true);

    // 高優先級：雲端模式應成為 top-1（完整 body）
    await File('${skillsDir.path}/daily-briefing.md').writeAsString('''---
name: daily-briefing
description: 晨間簡報
trigger_keywords: [晨報, 簡報]
priority: high
---

${'簡報完整步驟。' * 50}
''');
    // 一般：雲端模式只進摘要卡
    await File('${skillsDir.path}/hermes/web-search.md').writeAsString('''---
name: web-search
description: 網路搜尋步驟
trigger_keywords: [搜尋]
---

${'搜尋完整步驟。' * 50}
''');

    catalog = SkillCatalog.test(skillsDir);
    await catalog.reload();
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('雲端模式注入分級', () {
    test('top-1 注入完整 body', () {
      final section = SkillPromptInjector.buildSkillSection(
        userMessage: '晨報 搜尋',
        localMode: false,
        catalog: catalog,
      );
      expect(section, isNotNull);
      expect(section, contains('簡報完整步驟'));
      expect(section, contains('### daily-briefing'));
    });

    test('top-2 以後只注摘要卡：有 name+description+skill_load 提示，無 body', () {
      final section = SkillPromptInjector.buildSkillSection(
        userMessage: '晨報 搜尋',
        localMode: false,
        catalog: catalog,
      );
      expect(section, isNotNull);
      // 摘要卡：name + description 在
      expect(section, contains('web-search'));
      expect(section, contains('網路搜尋步驟'));
      // skill_load 提示在
      expect(section, contains('skill_load'));
      // 但 web-search 的 body 不該被注入
      expect(section, isNot(contains('搜尋完整步驟')));
    });

    test('無匹配回傳 null', () {
      final section = SkillPromptInjector.buildSkillSection(
        userMessage: '今天天氣真好',
        catalog: catalog,
      );
      expect(section, isNull);
    });
  });

  group('localMode（本地 4B）維持現狀', () {
    test('只注入 1 個×800 字截斷，且只收高優先級', () {
      final section = SkillPromptInjector.buildSkillSection(
        userMessage: '晨報 搜尋',
        localMode: true,
        catalog: catalog,
      );
      expect(section, isNotNull);
      // 只收 high priority → daily-briefing
      expect(section, contains('daily-briefing'));
      expect(section, isNot(contains('web-search')));
      // 截斷至 800 字
      expect(section!.length, lessThan(1200));
    });
  });
}
