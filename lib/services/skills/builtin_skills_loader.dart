/// Builtin Skills Loader — 從 assets 載入內建 skills 到使用者目錄
///
/// [教練 Agent 2026-07-23] 靈感來自 Matt Pocock 的 skills 完整包。
/// App 首次啟動或 skill 版本更新時，把 assets/skills/ 裡的 .md 檔案
/// 複製到 Documents/skills/ 目錄，讓 SkillStore 可以載入。
///
/// 策略：
/// - 每個內建 skill 檔案都有 version 欄位
/// - 如果使用者目錄裡沒有這個 skill，或版本比內建的舊，就覆蓋
/// - 使用者自訂的 skill（不在內建清單裡的）不會被動到

import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'skill.dart';
import 'skill_store.dart';

class BuiltinSkillsLoader {
  /// 內建 skill 檔案清單
  static const List<String> _builtinSkillFiles = [
    'grill-me.md',
    'to-spec.md',
    'handoff.md',
    'diagnose-bugs.md',
    'code-review.md',
    'codebase-design.md',
    // [小葵 2026-10-04 Blue 令「不教而殺謂之虐」] 視覺問題先看畫面再查 log
    'observe-first.md',
  ];

  /// 載入內建 skills 到指定目錄
  ///
  /// 回傳載入了幾個 skill
  static Future<int> loadTo(String skillsDir) async {
    int loaded = 0;

    final dir = Directory(skillsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    for (final filename in _builtinSkillFiles) {
      try {
        // 從 assets 讀取
        final content = await rootBundle.loadString('assets/skills/$filename');

        // 解析看版本
        final builtinSkill = Skill.fromMarkdown(content, filePath: '$skillsDir/$filename');

        // 檢查使用者目錄是否已有這個 skill
        final existingFile = File('$skillsDir/$filename');
        if (await existingFile.exists()) {
          final existingContent = await existingFile.readAsString();
          final existingSkill = Skill.fromMarkdown(existingContent, filePath: '$skillsDir/$filename');

          // 使用者版本 >= 內建版本，跳過（不覆蓋使用者的修改）
          if (existingSkill.version >= builtinSkill.version) {
            continue;
          }
        }

        // 寫入（新 skill 或更新舊版本）
        await existingFile.writeAsString(content);
        loaded++;
      } catch (e) {
        // 單個 skill 載入失敗不影響其他
        debugPrint('[BuiltinSkills] 載入 $filename 失敗: $e');
      }
    }

    // 重新載入 SkillStore
    await SkillStore.instance.reload();

    return loaded;
  }
}
