/// Skill Prompt Injector — 把匹配到的 skill 注入 Agent Loop system prompt
///
/// S20: 負責把 SkillMatcher 匹配到的 skill 轉成 prompt 區塊。
/// 在 AgentLoopPromptBuilder.build() 裡呼叫。
///
/// 插槽輕量化 Task 3 注入分級（雲端 agent 給釣竿、本地 agent 給魚）：
/// - 雲端模式：top-1 注入完整 body，其餘只注摘要卡
///   （name + description + 一句「完整內容用 skill_load 工具取得」）
/// - localMode：維持 1 個×800 字截斷——本地模型沒有工具呼叫能力，
///   截斷注入是它的天花板，UI 不假裝本地也能按需載入。
///
/// 注入格式（雲端）：
/// ```
/// ## 可用程序記憶（Skills）
/// 以下程序可能與使用者的請求相關，請參考但不強制遵循：
///
/// ### skill-name
/// <完整 body（僅 top-1）>
///
/// ### skill-name-2
/// description 摘要卡
/// （完整內容用 skill_load 工具取得：skill_load("skill-name-2")）
/// ```

import 'dart:io';

import 'skill_priority.dart';
import 'skill_matcher.dart';
import 'skill_catalog.dart';
import 'skill_store.dart';

class SkillPromptInjector {
  /// 從使用者訊息匹配 skill 並產生 prompt 區塊
  ///
  /// 回傳 null = 沒有匹配到任何 skill（不注入）
  ///
  /// [catalog] — metadata-only 索引。給了就走 catalog 路徑（分級注入）；
  /// 省略則 fallback 走 SkillStore 全載路徑（既有行為，零回歸）。
  ///
  /// [localMode] — 本地 4B 模型精簡模式：
  ///   只取 priority >= high 的 skill，最多 1 個，body 截斷至 800 字。
  ///   4B 模型 prompt 太長會影響品質，所以只注入最關鍵的追問程序。
  static String? buildSkillSection({
    required String userMessage,
    int maxResults = 3,
    bool localMode = false,
    SkillCatalog? catalog,
  }) {
    if (catalog != null && catalog.isLoaded) {
      return _buildFromCatalog(
        catalog: catalog,
        userMessage: userMessage,
        maxResults: maxResults,
        localMode: localMode,
      );
    }

    // ── 既有路徑（SkillStore 全載；行為零回歸）──
    final store = SkillStore.instance;
    if (!store.isLoaded || store.all.isEmpty) return null;

    var matched = SkillMatcher.match(
      allSkills: store.all,
      message: userMessage,
      maxResults: localMode ? 1 : maxResults,
    );

    if (matched.isEmpty) return null;

    // 本地模式：只保留高優先級 skill
    if (localMode) {
      matched = matched.where((s) => s.priority == SkillPriority.high).toList();
      if (matched.isEmpty) return null;
    }

    final buf = StringBuffer();
    if (localMode) {
      buf.writeln('## 追問程序');
      buf.writeln('使用者需求可能不夠明確，請參考以下程序自然地反問釐清：');
    } else {
      buf.writeln('## 可用程序記憶（Skills）');
      buf.writeln('以下程序可能與使用者的請求相關，請參考但不強制遵循：');
    }

    for (final skill in matched) {
      buf.writeln();
      buf.writeln('### ${skill.name}');
      var body = skill.body;
      if (localMode && body.length > 800) {
        body = '${body.substring(0, 800)}…';
      }
      buf.writeln(body);
    }

    return buf.toString();
  }

  /// catalog 路徑——metadata 匹配 + 分級注入（Task 3 本體）
  ///
  /// top-1 的 body 由 catalog 從磁碟懶載入（用到才讀），
  /// 其餘只注摘要卡——常駐記憶體只有 metadata，注入的 token 也只有 top-1 body。
  static String? _buildFromCatalog({
    required SkillCatalog catalog,
    required String userMessage,
    required int maxResults,
    required bool localMode,
  }) {
    final entries = SkillMatcher.matchEntries(
      entries: catalog.all,
      message: userMessage,
      maxResults: localMode ? 1 : maxResults,
    );

    if (entries.isEmpty) return null;

    // 本地模式：只保留高優先級
    if (localMode) {
      final high =
          entries.where((e) => e.priority == SkillPriority.high).toList();
      if (high.isEmpty) return null;

      final buf = StringBuffer();
      buf.writeln('## 追問程序');
      buf.writeln('使用者需求可能不夠明確，請參考以下程序自然地反問釐清：');
      buf.writeln();
      buf.writeln('### ${high.first.name}');
      var body = _loadBodySync(catalog, high.first);
      if (body.length > 800) {
        body = '${body.substring(0, 800)}…';
      }
      buf.writeln(body);
      return buf.toString();
    }

    // 雲端模式：top-1 完整 body，其餘摘要卡
    final buf = StringBuffer();
    buf.writeln('## 可用程序記憶（Skills）');
    buf.writeln('以下程序可能與使用者的請求相關，請參考但不強制遵循：');

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      buf.writeln();
      buf.writeln('### ${entry.name}');
      if (i == 0) {
        buf.writeln(_loadBodySync(catalog, entry));
      } else {
        buf.writeln('description: ${entry.description}');
        buf.writeln(
            '（完整內容用 skill_load 工具取得：skill_load("${entry.name}")）');
      }
    }

    return buf.toString();
  }
}

/// 同步讀 body——chat_controller 以同步鏈呼叫本 injector，
/// catalog 的懶載入在此用 File.readAsStringSync 從磁碟按需讀取。
/// （body 永遠留磁碟、只讀 top-1 那一份；Task 4 skill_load 工具改走 async。）
String _loadBodySync(SkillCatalog catalog, SkillCatalogEntry entry) {
  try {
    final file = File(entry.filePath);
    final content = file.readAsStringSync();
    final offset = entry.bodyOffset;
    if (offset <= 0 || offset >= content.length) return content;
    return content.substring(offset).trim();
  } catch (_) {
    // 讀檔失敗誠實降級：只給摘要卡，不裝成功
    return '（body 讀取失敗：${entry.description}）';
  }
}
