// Skill Tools 測試——skill_search / skill_load（插槽輕量化 Task 4）
//
// 測試範圍：
// 1. skillSearch：評分排序、category 過濾、limit 上限 25
// 2. skillLoad：懶載入全文、失敗誠實回 {success:false, error}
// 3. 停用的插槽（SlotRegistry disabled）→ skillSearch/skillLoad 排除（管理接線）
// 4. AgentTool 版本（SkillSearchTool/SkillLoadTool）回 JSON 給 LLM
//
// 鐵則：絕不空內容裝成功。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/skills/skill_catalog.dart';
import 'package:bridge_app/services/skills/skill_tools.dart';
import 'package:bridge_app/services/slots/slot_registry.dart';

void main() {
  late Directory tmp;
  late Directory skillsDir;
  late SkillCatalog catalog;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('skill_tools_test_');
    skillsDir = Directory('${tmp.path}/skills');
    await Directory('${skillsDir.path}/hermes').create(recursive: true);
    await Directory('${skillsDir.path}/agency-agents').create(recursive: true);

    await File('${skillsDir.path}/hermes/marketing.md').writeAsString('''---
name: marketing-guru
description: 行銷專家，教社群成長與品牌定位
trigger_keywords: [行銷]
priority: high
---

MARKETING_BODY_SENTINEL 行銷全文內容。
''');

    await File('${skillsDir.path}/hermes/writer.md').writeAsString('''---
name: zen-writer
description: 極簡寫作教練，幫你把話說清楚
trigger_keywords: [寫作]
---

WRITER_BODY_SENTINEL 寫作全文內容。
''');

    // 無 trigger（agency 人格形態）——搜尋要找得到（vs 被動匹配不會）
    await File('${skillsDir.path}/agency-agents/anthropologist.md')
        .writeAsString('''---
name: anthropologist
description: Expert in cultural systems and ethnographic method
---

ANTHRO_BODY_SENTINEL 人類學家人格全文。
''');

    catalog = SkillCatalog.test(skillsDir);
    await catalog.reload();
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('skillSearch', () {
    test('關鍵字命中 description 的條目排最前', () async {
      final result = await SkillTools.search(
        catalog,
        '行銷',
        disabledNames: const {},
      );
      expect(result.success, isTrue);
      final results =
          (result.toJson()['results'] as List).cast<Map<String, dynamic>>();
      expect(results, isNotEmpty);
      expect(results.first['name'], 'marketing-guru');
      expect((results.first['score'] as num), greaterThan(0));
    });

    test('回傳欄位齊：slug+name+description+category+score', () async {
      final result = await SkillTools.search(
        catalog,
        '寫作',
        disabledNames: const {},
      );
      final results =
          (result.toJson()['results'] as List).cast<Map<String, dynamic>>();
      expect(results.first['name'], 'zen-writer');
      for (final key in ['slug', 'name', 'description', 'category', 'score']) {
        expect(results.first.containsKey(key), isTrue, reason: '缺 $key');
      }
    });

    test('無關查詢 → 空結果（誠實，不硬湊）', () async {
      final result = await SkillTools.search(
        catalog,
        '量子糾纏表情符號',
        disabledNames: const {},
      );
      expect(result.success, isTrue);
      expect((result.toJson()['results'] as List).isEmpty, isTrue);
    });

    test('category 過濾——只回該分類', () async {
      final result = await SkillTools.search(
        catalog,
        'cultural systems',
        disabledNames: const {},
        category: 'agency-agents',
      );
      final results =
          (result.toJson()['results'] as List).cast<Map<String, dynamic>>();
      expect(results, isNotEmpty);
      for (final r in results) {
        expect(r['category'], 'agency-agents');
      }
    });

    test('limit 上限 25（超過自動裁到 25）', () async {
      final bulk = Directory('${skillsDir.path}/bulk');
      await bulk.create();
      for (var i = 0; i < 30; i++) {
        await File('${bulk.path}/skill-$i.md').writeAsString('''---
name: bulk-skill-$i
description: 批量條目 $i 內容測試
---

BULK $i。
''');
      }
      await catalog.reload();
      final result = await SkillTools.search(
        catalog,
        '批量',
        disabledNames: const {},
        limit: 100,
      );
      expect((result.toJson()['results'] as List).length, 25);
    });

    test('停用的插槽卡從結果排除——統一管理接線', () async {
      final result = await SkillTools.search(
        catalog,
        '行銷',
        disabledNames: const {'marketing-guru'},
      );
      final results =
          (result.toJson()['results'] as List).cast<Map<String, dynamic>>();
      expect(results.map((r) => r['name']),
          isNot(contains('marketing-guru')));
    });

    test('空 catalog 查詢回空但 success=true', () async {
      final emptyCatalog = SkillCatalog.test(Directory('${tmp.path}/nope'));
      await emptyCatalog.reload();
      final result = await SkillTools.search(
        emptyCatalog,
        '行銷',
        disabledNames: const {},
      );
      expect(result.success, isTrue);
      expect((result.toJson()['results'] as List).isEmpty, isTrue);
    });
  });

  group('skillLoad', () {
    test('懶載入回全文（不含 frontmatter）', () async {
      final result = await SkillTools.load(
        catalog,
        'marketing-guru',
        disabledNames: const {},
      );
      expect(result.success, isTrue);
      final body = result.toJson()['body'] as String;
      expect(body, contains('MARKETING_BODY_SENTINEL'));
      expect(body, isNot(contains('description:')));
    });

    test('slug 不存在 → success:false + error（誠實鐵則）', () async {
      final result = await SkillTools.load(
        catalog,
        'no-such-skill',
        disabledNames: const {},
      );
      expect(result.success, isFalse);
      expect((result.toJson()['error'] as String), isNotEmpty);
    });

    test('停用的 skill 不能 load', () async {
      final result = await SkillTools.load(
        catalog,
        'marketing-guru',
        disabledNames: const {'marketing-guru'},
      );
      expect(result.success, isFalse);
      expect(result.toJson()['error'], contains('停用'));
    });
  });

  group('AgentTool 版本（AgentToolRegistry 接線用）', () {
    test('SkillSearchTool 註冊名 skill_search、回 JSON 字串', () async {
      final tool = SkillSearchTool(catalog);
      expect(tool.name, 'skill_search');
      final r = await tool.execute({'query': '行銷'});
      expect(r.success, isTrue);
      final decoded = jsonDecode(r.content) as Map<String, dynamic>;
      expect((decoded['results'] as List), isNotEmpty);
      expect(decoded['results'][0]['name'], 'marketing-guru');
    });

    test('SkillSearchTool limit>25 裁到 25、query 缺漏回 failure', () async {
      final bulk = Directory('${skillsDir.path}/bulk');
      await bulk.create();
      for (var i = 0; i < 27; i++) {
        await File('${bulk.path}/skill-$i.md').writeAsString('''---
name: bulk-skill-$i
description: 批量條目 $i 內容測試
---

BULK $i。
''');
      }
      await catalog.reload();
      final tool = SkillSearchTool(catalog);
      final r = await tool.execute({'query': '批量', 'limit': 100});
      expect(
          ((jsonDecode(r.content) as Map<String, dynamic>)['results'] as List)
              .length,
          25);

      final bad = await tool.execute({});
      expect(bad.success, isFalse);
    });

    test('SkillLoadTool 註冊名 skill_load、成功回全文、找不到回 failure', () async {
      final tool = SkillLoadTool(catalog);
      expect(tool.name, 'skill_load');
      final ok = await tool.execute({'slug': 'marketing-guru'});
      expect(ok.success, isTrue);
      expect(ok.content, contains('MARKETING_BODY_SENTINEL'));

      final ghost = await tool.execute({'slug': 'ghost'});
      expect(ghost.success, isFalse);
    });
  });

  group('SlotRegistry 整合（管理接線——disabled 卡即時反映）', () {
    test('SlotRegistry 停用 → skillSearch 排除', () async {
      final appRoot = Directory('${tmp.path}/app');
      await appRoot.create(recursive: true);
      final registry = SlotRegistry.test(appRoot);
      await registry.ensureLoaded();
      final card = await registry.addFromRepo(
        'skill://hermes__marketing-guru',
        label: 'marketing-guru',
        category: 'Hermes 移民',
      );
      await registry.disable(card.id);

      final disabledNames = SkillTools.disabledSkillNames(registry);
      expect(disabledNames, contains('marketing-guru'));

      final result = await SkillTools.search(
        catalog,
        '行銷',
        disabledNames: disabledNames,
      );
      final results =
          (result.toJson()['results'] as List).cast<Map<String, dynamic>>();
      expect(results.map((r) => r['name']),
          isNot(contains('marketing-guru')));
    });
  });
}
