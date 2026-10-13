// SkillMatcher × SkillCatalog 測試——匹配邏輯零回歸（插槽輕量化 Task 2）
//
// 匹配策略不變：keyword +1.0 / regex +2.0 / priority 加權。
// 新增：直接吃 catalog 條目（matchEntries）；無 trigger 條目永不匹配。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/skills/skill.dart';
import 'package:bridge_app/services/skills/skill_catalog.dart';
import 'package:bridge_app/services/skills/skill_matcher.dart';

void main() {
  late Directory tmp;
  late SkillCatalog catalog;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('skill_matcher_test_');
    final skillsDir = Directory('${tmp.path}/skills');
    await Directory('${skillsDir.path}/hermes').create(recursive: true);

    await File('${skillsDir.path}/daily-briefing.md').writeAsString('''---
name: daily-briefing
description: 晨間簡報
trigger_keywords: [晨報, 簡報]
priority: high
---

簡報步驟。
''');
    await File('${skillsDir.path}/hermes/web-search.md').writeAsString('''---
name: web-search
description: 網路搜尋
trigger_keywords: [搜尋, 查]
trigger_patterns:
  - "搜尋.*資料"
  - "查.*一下"
---

搜尋步驟。
''');
    await File('${skillsDir.path}/hermes/image-gen.md').writeAsString('''---
name: image-gen
description: 生成圖片
trigger_keywords: [畫, 生成圖片]
priority: low
---

圖片生成步驟。
''');
    await File('${skillsDir.path}/hermes/no-trigger.md').writeAsString('''---
name: no-trigger
description: 沒有觸發條件
---

永遠不該被匹配。
''');

    catalog = SkillCatalog.test(skillsDir);
    await catalog.reload();
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('關鍵字精確匹配（catalog 條目）', () async {
    final matched = SkillMatcher.matchEntries(
      entries: catalog.all,
      message: '幫我做個晨報',
    );
    expect(matched, isNotEmpty);
    expect(matched.first.name, 'daily-briefing');
  });

  test('正則模式匹配（catalog 條目）', () async {
    final matched = SkillMatcher.matchEntries(
      entries: catalog.all,
      message: '幫我搜尋一些資料',
    );
    expect(matched, isNotEmpty);
    expect(matched.first.name, 'web-search');
  });

  test('無 trigger 條目的 skill 永遠不被動匹配', () async {
    final matched = SkillMatcher.matchEntries(
      entries: catalog.all,
      message: 'no-trigger 永遠不該出現',
    );
    expect(matched.where((e) => e.name == 'no-trigger'), isEmpty);
  });

  test('maxResults 限制回傳數量', () async {
    final matched = SkillMatcher.matchEntries(
      entries: catalog.all,
      message: '搜尋 查 畫 簡報 晨報 生成圖片',
      maxResults: 2,
    );
    expect(matched.length, lessThanOrEqualTo(2));
  });

  test('無匹配時回傳空列表', () async {
    final matched = SkillMatcher.matchEntries(
      entries: catalog.all,
      message: '今天天氣真好',
    );
    expect(matched, isEmpty);
  });

  test('既有 match(List<Skill>) 行為零回歸', () {
    final skills = [
      Skill(
        name: 'daily-briefing',
        description: '晨間簡報',
        triggerKeywords: ['晨報', '簡報'],
        priority: SkillPriority.high,
        body: '簡報步驟',
      ),
      Skill(
        name: 'no-trigger',
        description: '沒有觸發條件',
        body: 'x',
      ),
    ];
    final matched = SkillMatcher.match(
      allSkills: skills,
      message: '幫我做個晨報',
    );
    expect(matched.first.name, 'daily-briefing');
  });
}
