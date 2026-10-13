// Agency Agents 匯入器測試——282 人格入住管線（插槽輕量化 Task 5）
//
// 用 fixture 小樣本驗證管線正確；真實 282 筆匯入由 Blue 親自驗收後跑
// `dart run tool/import_agency_agents.dart`。
//
// 鐵則：
// - RED 拒絕、GREEN/YELLOW 入庫但分類一律「顧問模式」
// - frontmatter 不加 trigger_keywords（顧問模式不被動觸發，只能 skillSearch 找）
// - 不逐個開 282 張插槽卡——一張總卡「顧問模式・Agency 人格庫」＋origin 標記批次
// - 冪等：重跑 0 新增
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/skills/skill_agency_importer.dart';
import 'package:bridge_app/services/skills/skill_catalog.dart';
import 'package:bridge_app/services/skills/skill_tools.dart';
import 'package:bridge_app/services/slots/slot_registry.dart';

void main() {
  late Directory tmp;
  late Directory skillsDir;
  late SlotRegistry registry;
  late SkillCatalog catalog;

  /// 造假 agents.json fixture
  Future<File> writeFixture(List<Map<String, dynamic>> agents) async {
    final f = File('${tmp.path}/agents.json');
    await f.writeAsString(jsonEncode(agents));
    return f;
  }

  Map<String, dynamic> makeAgent(
    String slug, {
    String division = 'academic',
    String body = 'Body text for testing.',
    String? leak,
  }) =>
      {
        'slug': slug,
        'name': slug.replaceAll('-', ' ').toUpperCase(),
        'description': 'Test expert $slug',
        'division': division,
        'emoji': '🌍',
        'vibe': 'test vibe',
        'source_path': '$division/$division-$slug.md',
        'body': leak ?? body,
      };

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('agency_import_test_');
    skillsDir = Directory('${tmp.path}/skills');
    await Directory('${skillsDir.path}/hermes').create(recursive: true);

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

  group('安檢（HermesSkillsGate 同款規則）', () {
    test('含內部路徑 /Users/alice → RED 拒絕', () async {
      await writeFixture([
        makeAgent('leaky-agent', leak: 'Read files from /Users/alice/dev'),
      ]);
      final importer = SkillAgencyImporter(
        skillsDir: skillsDir,
        registry: registry,
        catalog: catalog,
      );
      final report = await importer.importFromJson(
        '${tmp.path}/agents.json',
        dryRun: false,
      );
      expect(report.red, 1);
      expect(report.imported, 0);
      expect(report.files.any((f) => f.verdict == 'RED'), isTrue);
    });

    test('含 API key 明文 → RED', () async {
      await writeFixture([
        makeAgent('key-agent', leak: 'api_key: sk-1234567890abcdef1234'),
      ]);
      final importer = SkillAgencyImporter(
        skillsDir: skillsDir,
        registry: registry,
        catalog: catalog,
      );
      final report = await importer.importFromJson(
        '${tmp.path}/agents.json',
        dryRun: false,
      );
      expect(report.red, 1);
      expect(report.imported, 0);
    });

    test('乾淨內容 → GREEN 入庫', () async {
      await writeFixture([makeAgent('clean-agent')]);
      final importer = SkillAgencyImporter(
        skillsDir: skillsDir,
        registry: registry,
        catalog: catalog,
      );
      final report = await importer.importFromJson(
        '${tmp.path}/agents.json',
        dryRun: false,
      );
      expect(report.green + report.yellow, 1);
      expect(report.imported, 1);
    });
  });

  group('入庫形狀', () {
    test('轉 .md：frontmatter 帶 name/description、無 trigger_keywords、body=人格全文',
        () async {
      await writeFixture([
        makeAgent('anthropologist', body: 'ANTHRO_FULL_BODY_TEXT'),
      ]);
      final importer = SkillAgencyImporter(
        skillsDir: skillsDir,
        registry: registry,
        catalog: catalog,
      );
      await importer.importFromJson('${tmp.path}/agents.json', dryRun: false);

      final md = File(
          '${skillsDir.path}/agency-agents/anthropologist.md');
      expect(await md.exists(), isTrue);
      final content = await md.readAsString();
      expect(content, contains('name: anthropologist'));
      expect(content, contains('description: Test expert anthropologist'));
      // 鐵則：不加 trigger_keywords——顧問模式不被動觸發
      expect(content, isNot(contains('trigger_keywords')));
      // body = 人格全文
      expect(content, contains('ANTHRO_FULL_BODY_TEXT'));
    });

    test('分類一律「顧問模式」、總卡一張（不逐個開卡）、origin=agency-agents',
        () async {
      await writeFixture([
        makeAgent('agent-a', division: 'academic'),
        makeAgent('agent-b', division: 'marketing'),
        makeAgent('agent-c', division: 'engineering'),
      ]);
      final importer = SkillAgencyImporter(
        skillsDir: skillsDir,
        registry: registry,
        catalog: catalog,
      );
      final report = await importer.importFromJson(
        '${tmp.path}/agents.json',
        dryRun: false,
      );
      expect(report.imported, 3);

      // 3 人格 → 只 1 張總卡（不淹沒管理頁）
      expect(registry.all.length, 1);
      final card = registry.all.first;
      expect(card.category, '顧問模式');
      expect(card.origin, 'agency-agents');
      expect(card.isRunning, isTrue);
    });

    test('冪等：重跑第二次 imported=0、卡不重複', () async {
      await writeFixture([
        makeAgent('agent-a'),
        makeAgent('agent-b'),
      ]);
      final importer = SkillAgencyImporter(
        skillsDir: skillsDir,
        registry: registry,
        catalog: catalog,
      );
      final first = await importer.importFromJson(
        '${tmp.path}/agents.json',
        dryRun: false,
      );
      expect(first.imported, 2);

      final second = await importer.importFromJson(
        '${tmp.path}/agents.json',
        dryRun: false,
      );
      expect(second.imported, 0);
      expect(registry.all.length, 1); // 總卡冪等
    });

    test('入庫後 skillSearch 找得到（人格無 trigger 也能被主動搜尋）', () async {
      await writeFixture([
        makeAgent('marketing-strategist',
            body: 'Growth marketing and brand positioning playbook.'),
      ]);
      final importer = SkillAgencyImporter(
        skillsDir: skillsDir,
        registry: registry,
        catalog: catalog,
      );
      await importer.importFromJson('${tmp.path}/agents.json', dryRun: false);

      final result = await SkillTools.search(
        catalog,
        'marketing',
        disabledNames: SkillTools.disabledSkillNames(registry),
      );
      final names = ((result.toJson()['results'] as List)
              .cast<Map<String, dynamic>>())
          .map((r) => r['name'] as String)
          .toList();
      expect(names, contains('marketing-strategist'));

      // load 拿得到人格全文
      final load = await SkillTools.load(
        catalog,
        'marketing-strategist',
        disabledNames: SkillTools.disabledSkillNames(registry),
      );
      expect(load.success, isTrue);
      expect(load.toJson()['body'], contains('Growth marketing'));
    });
  });

  group('dryRun', () {
    test('dryRun 只安檢不寫檔不建卡', () async {
      await writeFixture([
        makeAgent('agent-a'),
        makeAgent('leaky', leak: '/Users/alice/secret'),
      ]);
      final importer = SkillAgencyImporter(
        skillsDir: skillsDir,
        registry: registry,
        catalog: catalog,
      );
      final report = await importer.importFromJson(
        '${tmp.path}/agents.json',
        dryRun: true,
      );
      expect(report.green + report.yellow + report.red, 2);
      expect(report.imported, 0);
      expect(registry.all.isEmpty, isTrue);
      expect(await Directory('${skillsDir.path}/agency-agents').exists(),
          isFalse);
    });
  });

  test('來源 JSON 不存在 → 匯入 0（不炸）', () async {
    final importer = SkillAgencyImporter(
      skillsDir: skillsDir,
      registry: registry,
      catalog: catalog,
    );
    final report = await importer.importFromJson(
      '${tmp.path}/nope.json',
      dryRun: false,
    );
    expect(report.total, 0);
    expect(report.imported, 0);
  });
}
