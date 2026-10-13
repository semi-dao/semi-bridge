/// Skill Store — 檔案系統存儲
///
/// S20: 管理 skill markdown 檔案的讀取/寫入/列舉。
/// 存儲位置：app Documents Directory /skills/
///
/// 設計：
/// - 啟動時掃描 /skills/ 目錄載入所有 .md 檔
/// - 支援內建 skill（assets 隨 app 打包）+ 使用者自訂 skill
/// - 熱重載：監聽檔案變化（v2）
/// - 容錯：單個 skill 解析失敗不影響其他

import 'dart:io';
import 'skill.dart';
import 'skill_catalog.dart';

class SkillStore {
  static SkillStore? _instance;
  static SkillStore get instance => _instance ??= SkillStore._();

  SkillStore._();

  final List<Skill> _skills = [];
  bool _loaded = false;

  /// skill 目錄路徑（由呼叫方設定）
  String? _skillsDir;

  /// 設定 skill 目錄並載入
  Future<void> initialize({String? skillsDir}) async {
    if (_loaded) return;

    _skillsDir = skillsDir;
    await reload();
  }

  /// 重新載入所有 skill
  Future<void> reload() async {
    _skills.clear();

    if (_skillsDir == null) return;

    final dir = Directory(_skillsDir!);
    if (!await dir.exists()) {
      _loaded = true;
      return;
    }

    final files = dir
        .listSync()
        .where((e) => e is File && e.path.endsWith('.md'))
        .cast<File>();

    for (final file in files) {
      try {
        final content = await file.readAsString();
        final skill = Skill.fromMarkdown(content, filePath: file.path);
        _skills.add(skill);
      } catch (e) {
        // 單個 skill 解析失敗不影響其他
        continue;
      }
    }

    _loaded = true;

    // 委派 catalog 重掃（metadata-only、遞迴含子目錄）——插槽輕量化 Task 2。
    // SkillStore 維持平面全載（find()/save()/delete() 相容不變）；
    // catalog 負責「看得到吃不到」的子目錄死檔案索引。
    if (_skillsDir != null) {
      try {
        SkillCatalog.instance.setSkillsDir(_skillsDir!);
        await SkillCatalog.instance.reload();
      } catch (_) {
        // catalog 失敗不影響 SkillStore 既有行為
      }
    }
  }

  /// 所有已載入的 skill
  List<Skill> get all => List.unmodifiable(_skills);

  /// 按 name 查找
  Skill? find(String name) {
    for (final s in _skills) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// 寫入一個 skill 到檔案系統
  Future<void> save(Skill skill) async {
    if (_skillsDir == null) return;

    final dir = Directory(_skillsDir!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File('${_skillsDir!}/${skill.name}.md');
    await file.writeAsString(skill.toMarkdown());

    // 更新記憶體
    final idx = _skills.indexWhere((s) => s.name == skill.name);
    if (idx >= 0) {
      _skills[idx] = skill;
    } else {
      _skills.add(skill);
    }
  }

  /// 刪除一個 skill
  Future<void> delete(String name) async {
    if (_skillsDir == null) return;

    final file = File('$_skillsDir/$name.md');
    if (await file.exists()) {
      await file.delete();
    }

    _skills.removeWhere((s) => s.name == name);
  }

  /// 是否已載入
  bool get isLoaded => _loaded;
}
