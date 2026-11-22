import '../models/conversation.dart';

/// [SPEC §9.2 對話頁v2 步驟2] 對話樹狀排序（桌面側欄＋手機小隊卡共用）
///
/// 性質（由 test/desktop_conversation_tree_test.dart 鎖定）：
/// 1. 子對話緊跟其母對話之後（DFS 前序）
/// 2. 孤兒（parentConversationId 指向不存在對話）視為頂層，不丟失
/// 3. parent 指向自己 = 頂層（防自環）
/// 4. 循環 parent 鏈不死鎖（深度上限防護由 depthOf 處理）
class ConversationTree {
  /// 樹狀展開：頂層依原順序，各自帶著自己的子孫。
  static List<Conversation> order(List<Conversation> conversations) {
    final byId = {for (final c in conversations) c.id: c};
    final childrenOf = <String, List<Conversation>>{};
    final roots = <Conversation>[];
    for (final c in conversations) {
      final pid = c.parentConversationId;
      if (pid != null && byId.containsKey(pid) && pid != c.id) {
        childrenOf.putIfAbsent(pid, () => []).add(c);
      } else {
        roots.add(c);
      }
    }
    final out = <Conversation>[];
    void walk(Conversation node) {
      out.add(node);
      for (final child in childrenOf[node.id] ?? const <Conversation>[]) {
        walk(child);
      }
    }

    for (final r in roots) {
      walk(r);
    }
    // 防丟失：循環 parent 鏈（a→b→a）的成員不屬於任何 root 子樹——
    // 保證輸出（當頂層處理）。對話記憶絕不因樹排序而消失（主權鐵則）。
    if (out.length < conversations.length) {
      final emitted = out.map((c) => c.id).toSet();
      for (final c in conversations) {
        if (!emitted.contains(c.id)) out.add(c);
      }
    }
    return out;
  }

  /// [SPEC §9 小隊狀態燈] 小隊子對話的即時狀態字串（純函式，無 IO）。
  ///
  /// 判定（由 test/squad_status_test.dart 鎖定）：
  /// - 非小隊（parent null 或 id 不以 `squad-` 開頭）→ 空字串（UI 不顯示燈）
  /// - messages ≤ 1（只有開小隊指令，尚無產出）→『待命』
  /// - 最後一則 role=user（指令進去了、AI 還沒回）→『待回覆』
  /// - 最後 assistant 且 metadata['kind'] 為 squad_report_card 類 →『已回報』
  /// - 其餘 assistant →『已回覆』
  static String squadStatus(Conversation c) {
    if (c.parentConversationId == null || !c.id.startsWith('squad-')) {
      return '';
    }
    if (c.messages.length <= 1) return '待命';
    final last = c.messages.last;
    if (last.role == 'user') return '待回覆';
    // assistant（含其他 role 的防禦性收尾）：看是不是小隊回報卡
    final kind = last.metadata?['kind'];
    if (kind is String && kind.contains('squad_report_card')) return '已回報';
    return '已回覆';
  }

  /// 對話在樹中的深度（頂層=0）。防環：上限 8。
  static int depthOf(
      Conversation conv, List<Conversation> conversations) {
    final byId = {for (final c in conversations) c.id: c};
    var depth = 0;
    var cur = conv;
    while (depth < 8) {
      final pid = cur.parentConversationId;
      if (pid == null || !byId.containsKey(pid) || pid == cur.id) break;
      cur = byId[pid]!;
      depth++;
    }
    return depth;
  }
}
