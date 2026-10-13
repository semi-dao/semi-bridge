/// Skill Matcher — 根據使用者訊息匹配相關 skill
///
/// S20: 負責從 SkillStore 的所有 skill 中找出與使用者訊息相關的。
///
/// 匹配策略：
/// 1. 關鍵字精確匹配（trigger_keywords）
/// 2. 正則模式匹配（trigger_patterns）
/// 3. 按優先級排序
/// 4. 回傳前 N 個（避免 prompt 過長）
///
/// 設計原則：
/// - 匹配是純函數，無副作用
/// - 沒有觸發條件的 skill 永遠不匹配（必須明確設定）
/// - 多個 skill 匹配時，高優先級先注入

import 'skill.dart';
import 'skill_catalog.dart';

class SkillMatcher {
  /// 從 catalog 條目中匹配與訊息相關的（插槽輕量化 Task 2）
  ///
  /// 匹配邏輯與 [match] 完全一致（keyword +1.0 / regex +2.0 / priority 加權），
  /// 只是資料來源換成 metadata-only 的 catalog 條目。
  ///
  /// 鐵則：無 trigger 條件的 skill 進目錄但**永不被動匹配**——
  /// 只能被 agent 主動 skill_search 撈到（= Hermes：skill 要嘛有觸發詞要嘛等人問）。
  ///
  /// [entries] catalog 條目（metadata-only）
  /// [message] 使用者訊息
  /// [maxResults] 最多回傳幾個（預設 3）
  static List<SkillCatalogEntry> matchEntries({
    required List<SkillCatalogEntry> entries,
    required String message,
    int maxResults = 3,
  }) {
    final lowerMessage = message.toLowerCase();
    final scored = <_ScoredEntry>[];

    for (final entry in entries) {
      if (!entry.hasTriggers) continue; // 無觸發條件永不匹配

      final score = _score(
        keywords: entry.triggerKeywords,
        patterns: entry.triggerPatterns,
        priority: entry.priority,
        message: message,
        lowerMessage: lowerMessage,
      );
      if (score > 0) {
        scored.add(_ScoredEntry(entry, score));
      }
    }

    _sortScored(scored);
    return scored.take(maxResults).map((s) => s.entry).toList();
  }

  /// 從所有 skill 中匹配與訊息相關的（既有 API，行為零回歸）
  ///
  /// [allSkills] 所有可用 skill
  /// [message] 使用者訊息
  /// [maxResults] 最多回傳幾個（預設 3，避免 prompt 過長）
  static List<Skill> match({
    required List<Skill> allSkills,
    required String message,
    int maxResults = 3,
  }) {
    final lowerMessage = message.toLowerCase();
    final scored = <_ScoredSkill>[];

    for (final skill in allSkills) {
      final score = _score(
        keywords: skill.triggerKeywords,
        patterns: skill.triggerPatterns,
        priority: skill.priority,
        message: message,
        lowerMessage: lowerMessage,
      );
      if (score > 0) {
        scored.add(_ScoredSkill(skill, score));
      }
    }

    _sortScored(scored);
    return scored.take(maxResults).map((s) => s.skill).toList();
  }

  /// 共用排序：分數高→優先級高→名稱（兩路徑同一規則，零回歸保證）
  static void _sortScored(List<_Scored> scored) {
    scored.sort((a, b) {
      final scoreCmp = b.score.compareTo(a.score);
      if (scoreCmp != 0) return scoreCmp;
      final priorityCmp = b.priority.index.compareTo(a.priority.index);
      if (priorityCmp != 0) return priorityCmp;
      return a.name.compareTo(b.name);
    });
  }

  /// 共用評分核心——keyword +1.0 / regex +2.0 / priority 加權（兩路徑完全一致）
  static double _score({
    required List<String> keywords,
    required List<String> patterns,
    required SkillPriority priority,
    required String message,
    required String lowerMessage,
  }) {
    double score = 0;

    // 關鍵字匹配（每命中一個 +1.0）
    for (final keyword in keywords) {
      if (lowerMessage.contains(keyword.toLowerCase())) {
        score += 1.0;
      }
    }

    // 正則模式匹配（每命中一個 +2.0，正則更精確所以權重高）
    for (final pattern in patterns) {
      try {
        final regex = RegExp(pattern, caseSensitive: false);
        if (regex.hasMatch(message)) {
          score += 2.0;
        }
      } catch (_) {
        // 無效正則 = 跳過
        continue;
      }
    }

    // 優先級加權
    switch (priority) {
      case SkillPriority.high:
        score *= 1.2;
        break;
      case SkillPriority.normal:
        // 不加權
        break;
      case SkillPriority.low:
        score *= 0.8;
        break;
    }

    return score;
  }
}

/// 排序共通介面——entry/skill 兩路徑用同一套排序規則
abstract class _Scored {
  const _Scored();

  double get score;
  SkillPriority get priority;
  String get name;
}

class _ScoredEntry extends _Scored {
  final SkillCatalogEntry entry;

  @override
  final double score;

  const _ScoredEntry(this.entry, this.score);

  @override
  SkillPriority get priority => entry.priority;

  @override
  String get name => entry.name;
}

class _ScoredSkill extends _Scored {
  final Skill skill;

  @override
  final double score;

  const _ScoredSkill(this.skill, this.score);

  @override
  SkillPriority get priority => skill.priority;

  @override
  String get name => skill.name;
}
