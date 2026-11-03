// [2026-11-03 user.skill 順位令] user-profile-skill 回歸測試——
// Blue 拍板：user-profile-skill.md 必為內建清單第一位（先認人、再懂人）。
// 三鎖：順位第一、資產檔可被 Skill.fromMarkdown 解析、priority=high
// （本地 4B 模式只注入 high skill——認人程序不能被本地路由丟掉）。
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/skills/builtin_skills_loader.dart';
import 'package:bridge_app/services/skills/skill.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('順位鎖：user-profile-skill.md 必為內建清單第一位', () {
    expect(BuiltinSkillsLoader.builtinSkillFilesForTest.first,
        'user-profile-skill.md',
        reason: 'Blue 2026-11-03 拍板：辨識使用者 > 一切程序 skill');
  });

  test('資產鎖：assets 檔存在且 frontmatter 解析無誤', () async {
    final file = File('assets/skills/user-profile-skill.md');
    expect(await file.exists(), isTrue, reason: '資產檔案必須隨 App 打包');

    final skill = Skill.fromMarkdown(await file.readAsString());
    expect(skill.name, 'user-profile-skill');
    expect(skill.description, isNotEmpty);
    expect(skill.body, contains('兩層 × 三軌'));
    expect(skill.body, contains('三軌外交架構')); // [2026-11-03 擴充令] 外交三軌
    expect(skill.body, contains('握手檔')); // Agent 軌握手規格
    expect(skill.version, greaterThanOrEqualTo(2));
  });

  test('優先級鎖：priority=high（本地模式仍注入）', () async {
    final file = File('assets/skills/user-profile-skill.md');
    final skill = Skill.fromMarkdown(await file.readAsString());
    expect(skill.priority, SkillPriority.high,
        reason: 'localMode 只保留 high——認人程序不能被本地路由丟掉');
    expect(skill.triggerKeywords, isNotEmpty,
        reason: 'SkillMatcher 鐵則：無觸發條件的 skill 永不被動匹配');
  });
}
