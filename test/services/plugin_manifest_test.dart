// PluginManifest 測試——真 pstack JSON 餵解析＋寬容解析鐵則（A線 刀1）
//
// 真實 schema 來源：cursor/plugins pstack/.cursor-plugin/plugin.json
// （2026-10-22 實抓 v0.15.29，逐欄位照抄）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/plugins/plugin_manifest.dart';

/// 真 pstack plugin.json（逐欄位照抄 2026-10-22 實抓，含未知欄位 $schema）
const pstackJson = '''
{
  "\$schema": "https://example.com/some-unknown-schema.json",
  "name": "pstack",
  "displayName": "pstack",
  "version": "0.15.29",
  "description": "if you want to go fast, go deep first. pstack helps you write less, but higher quality code. rigorous agent workflows you can parallelize with confidence.",
  "author": { "name": "Lauren Tan" },
  "homepage": "https://github.com/cursor/plugins/tree/main/pstack",
  "repository": "https://github.com/cursor/plugins",
  "license": "MIT",
  "logo": "assets/logo.png",
  "keywords": ["pstack", "poteto-mode", "workflow", "principles", "agent-style", "subagents", "unslop"],
  "category": "developer-tools",
  "tags": ["workflow", "principles", "review", "planning"],
  "skills": "./skills/",
  "agents": "./agents/"
}
''';

void main() {
  late Directory tmp;
  late Directory pluginRoot;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('plugin_manifest_test_');
    pluginRoot = Directory('${tmp.path}/pstack');
    await Directory('${pluginRoot.path}/.cursor-plugin')
        .create(recursive: true);
    await Directory('${pluginRoot.path}/skills/deep').create(recursive: true);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> writeManifest(String content) async {
    await File('${pluginRoot.path}/.cursor-plugin/plugin.json')
        .writeAsString(content);
  }

  test('真 pstack JSON：全欄位解析正確', () {
    final m = PluginManifest.parse(pstackJson, pluginRoot.path);
    expect(m, isNotNull);
    expect(m!.name, 'pstack');
    expect(m.displayName, 'pstack');
    expect(m.version, '0.15.29');
    expect(m.authorName, 'Lauren Tan');
    expect(m.license, 'MIT');
    expect(m.repository, 'https://github.com/cursor/plugins');
    expect(m.category, 'developer-tools');
    expect(m.keywords, contains('unslop'));
    expect(m.tags, contains('planning'));
    // 未知欄位（$schema）忽略——寬容解析
    expect(m.label, 'pstack');
  });

  group('相對路徑 resolve（測試鎖死）', () {
    test('skillsDir 相對路徑以 plugin root resolve 成絕對路徑', () {
      final m = PluginManifest.parse(pstackJson, pluginRoot.path)!;
      expect(m.skillsDirPath, '${pluginRoot.path}/skills');
      expect(m.agentsDirPath, '${pluginRoot.path}/agents');
    });

    test('未宣告 skills 欄 → 預設 <root>/skills', () {
      final m = PluginManifest.parse(
          '{"name":"x","version":"1.0"}', pluginRoot.path)!;
      expect(m.skillsDirPath, '${pluginRoot.path}/skills');
    });

    test('../ 逃脫 root → null（紅隊基本功）', () {
      final m = PluginManifest.parse(
          '{"name":"x","version":"1.0","skills":"../../etc"}',
          pluginRoot.path)!;
      expect(m.skillsDirPath, isNull);
    });
  });

  group('寧拒不誤裝（缺 name/version → null）', () {
    test('缺 name → null', () {
      expect(
          PluginManifest.parse('{"version":"1.0"}', pluginRoot.path), isNull);
    });

    test('缺 version → null', () {
      expect(PluginManifest.parse('{"name":"x"}', pluginRoot.path), isNull);
    });

    test('壞 JSON → null', () {
      expect(PluginManifest.parse('{not json', pluginRoot.path), isNull);
    });

    test('JSON 不是物件（array）→ null', () {
      expect(PluginManifest.parse('[1,2,3]', pluginRoot.path), isNull);
    });
  });

  group('未知欄位與形狀寬容', () {
    test('完全未知欄位忽略不炸', () {
      final m = PluginManifest.parse(
          '{"name":"x","version":"1","futureField":{"a":1},"another":42}',
          pluginRoot.path);
      expect(m, isNotNull);
      expect(m!.name, 'x');
    });

    test('author 給字串（非物件）也收', () {
      final m = PluginManifest.parse(
          '{"name":"x","version":"1","author":"Somebody"}', pluginRoot.path)!;
      expect(m.authorName, 'Somebody');
    });
  });

  group('檔案路徑解析（IO）', () {
    test('parseFile 吃 .cursor-plugin/plugin.json', () async {
      await writeManifest(pstackJson);
      final m = await PluginManifest.parseFile(
          '${pluginRoot.path}/.cursor-plugin/plugin.json');
      expect(m, isNotNull);
      expect(m!.name, 'pstack');
      expect(m.version, '0.15.29');
      // root 是 .cursor-plugin 的上層
      expect(m.skillsDirPath, '${pluginRoot.path}/skills');
    });

    test('parsePluginRoot 探根目錄', () async {
      await writeManifest(pstackJson);
      final m = await PluginManifest.parsePluginRoot(pluginRoot.path);
      expect(m, isNotNull);
      expect(m!.name, 'pstack');
    });

    test('檔案不存在 → null', () async {
      expect(await PluginManifest.parsePluginRoot('${tmp.path}/nope'), isNull);
    });

    test('檔案內容壞 JSON → null（不炸）', () async {
      await writeManifest('{{{broken');
      expect(await PluginManifest.parsePluginRoot(pluginRoot.path), isNull);
    });
  });
}
