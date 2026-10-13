/// Skill 優先級——從 skill.dart 抽出，讓 SkillCatalog 免拖 body 欄位依賴
///
/// 權威定義仍在 skill.dart（`export` 相容）：SkillCatalog / SkillMatcher /
/// SkillPromptInjector 引此檔，skill.dart 保留同名 enum 供既有 API 使用。
///
/// ⚠️ 兩處必須同義：low < normal < high，fromString 規則一致。
enum SkillPriority {
  low,
  normal,
  high;

  static SkillPriority fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'high':
        return SkillPriority.high;
      case 'low':
        return SkillPriority.low;
      default:
        return SkillPriority.normal;
    }
  }
}
