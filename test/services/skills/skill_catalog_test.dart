// SkillCatalog 測試——metadata-only 輕量索引（插槽輕量化 Task 1）
//
// 測試範圍：
// 1. 遞迴掃描 skillsDir（含子目錄）——修 117 死檔案
// 2. 每檔只解析 frontmatter，body 不進記憶體（只記 filePath + bodyOffset）
// 3. 冪等 reload；單檔失敗跳過不炸全部
// 4. 單例＋測試隔離（SkillCatalog.test(Directory)，不 import path_provider）
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/skills/skill.dart';
import 'package:bridge_app/services/skills/skill_catalog.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('skill_catalog_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  Future<void> writeFixture() async {
    final skillsDir = Directory('${tmp.path}/skills');
    await Directory('${skillsDir.path}/hermes/sub').create(recursive: true);

    // 平面層
    await File('${skillsDir.path}/flat-skill.md').writeAsString('''---
name: flat-skill
description: 平面層 skill
trigger_keywords: [晨報, 簡報]
priority: high
---

FLAT_BODY_SENTINEL 這是平面層的內容。
''');

    // 子目錄（SkillStore 舊世界掃不到的死檔案）
    await File('${skillsDir.path}/hermes/hermes-skill.md').writeAsString('''---
name: hermes-skill
description: Hermes 子目錄 skill
trigger_keywords: [測試]
---

HERMES_BODY_SENTINEL 這是子目錄的內容，很長很長很長。
''');

    // 更深層
    await File('${skillsDir.path}/hermes/sub/deep-skill.md').writeAsString('''---
name: deep-skill
description: 深層 skill
trigger_patterns:
  - "深.*層"
priority: low
---

DEEP_BODY_SENTINEL。
''');

    // 無 trigger 條目（agency 人格形態：進目錄、永不主動匹配）
    await File('${skillsDir.path}/hermes/no-trigger.md').writeAsString('''---
name: no-trigger
description: 沒有觸發條件的條目
---

NO_TRIGGER_BODY_SENTINEL。
''');

    // 壞檔（單檔失敗跳過）
    await File('${skillsDir.path}/hermes/broken.md').writeAsString('普通文字檔');

    // 非 .md（應被忽略）
    await File('${skillsDir.path}/ignore.txt').writeAsString('not markdown');
  }

  group('SkillCatalog 掃描', () {
    test('遞迴掃描含子目錄，只算 .md', () async {
      await writeFixture();
      final catalog = SkillCatalog.test(Directory('${tmp.path}/skills'));
      await catalog.reload();

      // 4 個 .md 條目；broken.md 無 frontmatter = 不是 skill，跳過
      expect(catalog.all.length, 4);
      final names = catalog.all.map((e) => e.name).toSet();
      expect(names, containsAll(['flat-skill', 'hermes-skill', 'deep-skill']));
      expect(names, isNot(contains('unnamed')));
    });

    test('category = 頂層目錄名（平面層為空字串）', () async {
      await writeFixture();
      final catalog = SkillCatalog.test(Directory('${tmp.path}/skills'));
      await catalog.reload();

      final flat = catalog.find('flat-skill')!;
      final hermes = catalog.find('hermes-skill')!;
      final deep = catalog.find('deep-skill')!;

      expect(flat.category, '');
      expect(hermes.category, 'hermes');
      expect(deep.category, 'hermes');
    });

    test('frontmatter metadata 解析正確', () async {
      await writeFixture();
      final catalog = SkillCatalog.test(Directory('${tmp.path}/skills'));
      await catalog.reload();

      final flat = catalog.find('flat-skill')!;
      expect(flat.description, '平面層 skill');
      expect(flat.triggerKeywords, containsAll(['晨報', '簡報']));
      expect(flat.priority, SkillPriority.high);

      final deep = catalog.find('deep-skill')!;
      expect(deep.triggerPatterns, ['深.*層']);
      expect(deep.priority, SkillPriority.low);
    });

    test('body 不存在於條目（metadata-only 鐵證）＋ bodyOffset 記錄', () async {
      await writeFixture();
      final catalog = SkillCatalog.test(Directory('${tmp.path}/skills'));
      await catalog.reload();

      final flat = catalog.find('flat-skill')!;
      // 條目序列化後不含 body 內容
      final serialized = jsonEncode(flat.toJson());
      expect(serialized, isNot(contains('FLAT_BODY_SENTINEL')));
      // bodyOffset 指向 body 起始（>0，frontmatter 存在）
      expect(flat.bodyOffset, greaterThan(0));

      // 用 bodyOffset 從磁碟讀回 body（懶載入機制本體）
      final body = await catalog.loadBody(flat);
      expect(body, contains('FLAT_BODY_SENTINEL'));
    });
  });

  group('SkillCatalog 冪等與容錯', () {
    test('冪等 reload：重掃不重複', () async {
      await writeFixture();
      final catalog = SkillCatalog.test(Directory('${tmp.path}/skills'));
      await catalog.reload();
      final first = catalog.all.length;
      await catalog.reload();
      expect(catalog.all.length, first);
    });

    test('reload 反映檔案增刪', () async {
      await writeFixture();
      final catalog = SkillCatalog.test(Directory('${tmp.path}/skills'));
      await catalog.reload();
      final before = catalog.all.length;

      await File('${tmp.path}/skills/new-skill.md').writeAsString('''---
name: new-skill
description: 新來的
---

NEW。
''');
      await catalog.reload();
      expect(catalog.all.length, before + 1);
      expect(catalog.find('new-skill'), isNotNull);
    });

    test('目錄不存在不炸', () async {
      final catalog =
          SkillCatalog.test(Directory('${tmp.path}/nonexistent'));
      await catalog.reload();
      expect(catalog.all, isEmpty);
    });
  });
}
