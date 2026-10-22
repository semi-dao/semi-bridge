// SlotInstaller plugin 分支測試——合成 plugin tarball 全流程（A線 刀2）
//
// 抄 test/services/slot_installer_test.dart 既有模式（離線自造 tarball）：
// installFromBytes 餵 .cursor-plugin/plugin.json + skills/（2 個 SKILL.md）
// → 驗：安裝成功、skills 複製到 skillsDir 帶前綴、catalog reload 後 find 得到、
// SlotRegistry 一張卡 version 正確、冪等重裝不重複、卸載掃除雙向通。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/plugins/plugin_slot_service.dart';
import 'package:bridge_app/services/skills/skill_catalog.dart';
import 'package:bridge_app/services/skills/skill_store.dart';
import 'package:bridge_app/services/slots/slot_installer.dart';
import 'package:bridge_app/services/slots/slot_registry.dart';

void main() {
  late Directory tmp;
  late Directory skillsDir;
  late SlotRegistry registry;
  late SkillCatalog catalog;

  const pluginJson = '''
{
  "name": "testplug",
  "displayName": "Test Plugin",
  "version": "1.2.3",
  "description": "合成測試 plugin",
  "author": {"name": "Tester"},
  "category": "developer-tools",
  "skills": "./skills/",
  "agents": "./agents/"
}
''';

  Uint8List buildTarball(Map<String, String> files) {
    final archive = Archive();
    files.forEach((path, content) {
      // UTF-8 編碼——既有測試的 codeUnits 是 UTF-16，中文內容會爛掉
      final bytes = utf8.encode(content);
      archive.addFile(
          ArchiveFile('owner-repo-abc1234/$path', bytes.length, bytes));
    });
    return Uint8List.fromList(
        GZipEncoder().encode(TarEncoder().encode(archive)));
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('slot_plugin_test_');
    skillsDir = Directory('${tmp.path}/skills');
    await skillsDir.create(recursive: true);

    final appRoot = Directory('${tmp.path}/app');
    await appRoot.create(recursive: true);
    registry = SlotRegistry.test(appRoot);
    await registry.ensureLoaded();

    catalog = SkillCatalog.test(skillsDir);
    await catalog.reload();

    // production 分支吃 SkillStore.instance.skillsDirPath、
    // SkillCatalog.instance、SlotRegistry.instance 三個單例——全部指到
    // 測試臨時夾。斷言用注入式 registry/catalog（= 測試隔離）；
    // 單例與注入物件共用同一根目錄，資料真相一致。
    SkillStore.instance.setSkillsDirForTest(skillsDir.path);
    SkillCatalog.instance.setSkillsDir(skillsDir.path);
    await SkillCatalog.instance.reload();
    SlotRegistry.instance.setRootOverride(appRoot);
    await SlotRegistry.instance.ensureLoaded();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Uint8List pluginTarball() => buildTarball({
        '.cursor-plugin/plugin.json': pluginJson,
        'skills/alpha/SKILL.md': '---\nname: alpha\ndescription: 技能 A\n---\n\nALPHA_BODY。\n',
        'skills/beta/SKILL.md': '---\nname: beta\ndescription: 技能 B\n---\n\nBETA_BODY。\n',
        'README.md': '# readme',
      });

  // ── [A線 通用機制] monorepo 支援——plugin 住子目錄（如 cursor/plugins 的 pstack）──
  // 測試用合成 plugin 名（anyplugin），證明機制通用非 pstack 特調。
  Uint8List monorepoTarball() => buildTarball({
        'marketplace-root/README.md': '# marketplace monorepo',
        'marketplace-root/anyplugin/.cursor-plugin/plugin.json': pluginJson
            .replaceAll('testplug', 'anyplugin'),
        'marketplace-root/anyplugin/skills/mono/SKILL.md':
            '---\nname: mono\ndescription: monorepo skill\n---\n\nMONO_BODY。\n',
      });

  test('monorepo plugin（plugin.json 在子目錄）也能安裝——通用機制', () async {
    final slotDir = Directory('${tmp.path}/slot_mono');
    final r = await SlotInstaller.instance.installFromBytes(
        monorepoTarball(), slotDir,
        pluginRegistry: registry,
        pluginCatalog: catalog,
        pluginSkillsDir: skillsDir);
    expect(r.ok, isTrue, reason: r.error);
    // skills 進庫：skillsDir/agent-plugins.org/<plugin>__<skill>.md
    final f = File('${skillsDir.path}/agent-plugins.org/anyplugin__mono.md');
    expect(await f.exists(), isTrue, reason: 'monorepo skill 未複製進庫');
    // catalog 找得到
    await catalog.reload();
    expect(catalog.find('mono'), isNotNull);
    // 一張卡 label 正確
    final cards = registry.all.where((s) =>
        s.userLabel.contains('Test Plugin'));
    expect(cards.length, greaterThanOrEqualTo(1));
  });

  test('monorepo 偵測（runPluginIntake=false）不建卡不複製——防幽靈卡', () async {
    final slotDir = Directory('${tmp.path}/slot_mono2');
    final r = await SlotInstaller.instance.installFromBytes(
        monorepoTarball(), slotDir,
        runPluginIntake: false);
    expect(r.ok, isTrue, reason: r.error);
    expect(registry.all.where((s) => s.sourceRepo == 'skill://anyplugin'),
        isEmpty,
        reason: '純偵測模式不該建卡');
    expect(await File('${skillsDir.path}/agent-plugins.org/anyplugin__mono.md').exists(),
        isFalse,
        reason: '純偵測模式不該複製 skills');
  });

  test('plugin tarball 安裝成功：無 HTML 入口也過（短路生效）', () async {
    final slotDir = Directory('${tmp.path}/slot1');
    final r = await SlotInstaller.instance
        .installFromBytes(pluginTarball(), slotDir,
        pluginRegistry: registry,
        pluginCatalog: catalog,
        pluginSkillsDir: skillsDir);
    expect(r.ok, isTrue, reason: r.error ?? '');
    expect(r.version, '1.2.3', reason: 'version 帶 manifest 版本');
    expect(r.redTeam, isNotNull, reason: '紅隊掃描照跑');
  });

  test('skills 複製到 skillsDir 帶 <plugin>__ 前綴＋catalog find 得到', () async {
    final slotDir = Directory('${tmp.path}/slot2');
    final r = await SlotInstaller.instance
        .installFromBytes(pluginTarball(), slotDir,
        pluginRegistry: registry,
        pluginCatalog: catalog,
        pluginSkillsDir: skillsDir);
    expect(r.ok, isTrue, reason: r.error ?? '');

    // 檔案複製到位：skillsDir/agent-plugins.org/testplug__alpha.md（拍平）
    final alpha = File(
        '${skillsDir.path}/${PluginSlotService.origin}/testplug__alpha.md');
    expect(await alpha.exists(), isTrue, reason: 'flat: ${alpha.path}');
    expect(await alpha.readAsString(), contains('ALPHA_BODY'));

    // catalog reload 後 find 得到（service reload 的是單例；測試隔離的
    // 注入式 catalog 自己重掃同根目錄，條目應一致）
    await catalog.reload();
    expect(catalog.find('alpha'), isNotNull);
    expect(catalog.find('beta'), isNotNull);
    expect(catalog.find('alpha')!.category, PluginSlotService.origin);
  });

  test('SlotRegistry 一張卡（不逐檔建卡）：version/origin/分類正確', () async {
    final slotDir = Directory('${tmp.path}/slot3');
    final r = await SlotInstaller.instance
        .installFromBytes(pluginTarball(), slotDir,
        pluginRegistry: registry,
        pluginCatalog: catalog,
        pluginSkillsDir: skillsDir);
    expect(r.ok, isTrue);

    final cards = registry.all
        .where((s) => s.sourceRepo == 'skill://testplug')
        .toList();
    expect(cards.length, 1, reason: '一個 plugin 一張卡（skills 有 2 個也不多建）');
    expect(cards.first.userLabel, 'Test Plugin'); // displayName 優先
    expect(cards.first.version, '1.2.3');
    expect(cards.first.origin, PluginSlotService.origin);
    expect(cards.first.category, '開發技能'); // developer-tools 映射
    expect(cards.first.isRunning, isTrue); // 零權限直接啟用
    expect(cards.first.permissions, isEmpty);
  });

  test('冪等重裝：檔案不重複、卡不重複', () async {
    final slotDir = Directory('${tmp.path}/slot4');
    final first = await SlotInstaller.instance
        .installFromBytes(pluginTarball(), slotDir,
        pluginRegistry: registry,
        pluginCatalog: catalog,
        pluginSkillsDir: skillsDir);
    expect(first.ok, isTrue);

    final second = await SlotInstaller.instance
        .installFromBytes(pluginTarball(), slotDir,
        pluginRegistry: registry,
        pluginCatalog: catalog,
        pluginSkillsDir: skillsDir);
    expect(second.ok, isTrue);

    final dest = Directory(
        '${skillsDir.path}/${PluginSlotService.origin}');
    final mdCount =
        dest.listSync().whereType<File>().where((f) => f.path.endsWith('.md')).length;
    expect(mdCount, 2, reason: '重裝不重複複製（已存在跳過）');

    final cards = registry.all
        .where((s) => s.sourceRepo == 'skill://testplug')
        .toList();
    expect(cards.length, 1, reason: '重裝不重複建卡');
    expect(cards.first.version, '1.2.3');
  });

  test('缺 version 的 plugin.json → 誠實失敗（寧拒不誤裝）', () async {
    final slotDir = Directory('${tmp.path}/slot5');
    final tar = buildTarball({
      '.cursor-plugin/plugin.json': '{"name": "broken"}',
      'skills/a.md': 'x',
    });
    final r = await SlotInstaller.instance.installFromBytes(tar, slotDir);
    expect(r.ok, isFalse);
    expect(r.error, contains('plugin.json'));
  });

  test('無 plugin.json → 續走 HTML 流程（原本行為不變）', () async {
    final slotDir = Directory('${tmp.path}/slot6');
    final tar = buildTarball({'main.py': 'print(1)'});
    final r = await SlotInstaller.instance.installFromBytes(tar, slotDir);
    expect(r.ok, isFalse);
    expect(r.error, contains('HTML 入口'));
  });

  test('runPluginIntake=false（wizard 預掃描）：不建卡不入庫', () async {
    final slotDir = Directory('${tmp.path}/slot7');
    final r = await SlotInstaller.instance
        .installFromBytes(pluginTarball(), slotDir, runPluginIntake: false);
    expect(r.ok, isTrue);
    expect(r.version, '1.2.3', reason: '偵測照樣回報版本');
    expect(
        registry.all.where((s) => s.sourceRepo == 'skill://testplug'), isEmpty,
        reason: '預掃描絕不留幽靈卡');
    final dest = Directory(
        '${skillsDir.path}/${PluginSlotService.origin}');
    expect(dest.existsSync(), isFalse, reason: '預掃描不入庫');
  });

  test('卸載掃除：前綴檔消失、catalog 搜不到', () async {
    final slotDir = Directory('${tmp.path}/slot8');
    final r = await SlotInstaller.instance
        .installFromBytes(pluginTarball(), slotDir,
        pluginRegistry: registry,
        pluginCatalog: catalog,
        pluginSkillsDir: skillsDir);
    expect(r.ok, isTrue);
    final card = registry.all
        .firstWhere((s) => s.sourceRepo == 'skill://testplug');

    final svc = PluginSlotService(
        catalog: catalog, skillsDir: skillsDir);
    final removed = await svc.removePluginSkills('testplug');
    expect(removed, 2);

    final dest = Directory(
        '${skillsDir.path}/${PluginSlotService.origin}');
    final remaining = dest.existsSync()
        ? dest.listSync().whereType<File>().length
        : 0;
    expect(remaining, 0, reason: '前綴檔全掃');
    expect(catalog.find('alpha'), isNull, reason: 'catalog reload 後搜不到');
    expect(catalog.find('beta'), isNull);

    // 走 registry.uninstall 也不炸（真卸載路徑——SkillStore 已注入會真掃）
    await registry.uninstall(card.id, deleteData: true);
    expect(registry.all.where((s) => s.sourceRepo == 'skill://testplug'),
        isEmpty);
  });
}
