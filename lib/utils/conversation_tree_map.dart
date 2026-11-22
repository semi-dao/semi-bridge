// [2026-11-21 章魚光呼吸樹] Map 版樹排序——手機端對話清單專用。
//
// 手機端 _conversations 是 gateway conversationList 回來的 List<Map>（非
// Conversation 物件，payload 已帶 parentConversationId——
// desktop_bridge_local_gateway.dart L772/839），故不能直接用
// ConversationTree（物件版）。本檔仿其契約（lib/utils/conversation_tree.dart）：
// 1. 子對話緊跟其母之後（DFS 前序，子依原序）
// 2. 孤兒（parent 不存在/指向自己）視為頂層，不丟失
// 3. 循環 parent 鏈不死鎖：未掛進任何根子樹的成員補發於尾（主權鐵則：
//    對話記憶絕不因樹排序而消失）
// 測試鎖定：test/mobile/mobile_conversation_tree_map_test.dart
class ConversationTreeMap {
  ConversationTreeMap._();

  static String? _pid(Map<String, dynamic> c) {
    final v = c['parentConversationId'];
    return (v is String && v.isNotEmpty) ? v : null;
  }

  static String? _id(Map<String, dynamic> c) {
    final v = c['id'];
    return (v is String && v.isNotEmpty) ? v : null;
  }

  /// 樹狀展開＋各項深度（頂層=0，防環上限 8）。
  static (List<Map<String, dynamic>>, List<int>) orderWithDepths(
      List<Map<String, dynamic>> conversations) {
    final byId = <String, Map<String, dynamic>>{
      for (final c in conversations)
        if (_id(c) != null) _id(c)!: c,
    };
    final childrenOf = <String, List<Map<String, dynamic>>>{};
    final roots = <Map<String, dynamic>>[];
    for (final c in conversations) {
      final pid = _pid(c);
      final id = _id(c);
      if (pid != null && id != pid && byId.containsKey(pid)) {
        childrenOf.putIfAbsent(pid, () => []).add(c);
      } else {
        roots.add(c);
      }
    }
    final out = <Map<String, dynamic>>[];
    final depths = <int>[];
    void walk(Map<String, dynamic> node, int depth) {
      out.add(node);
      depths.add(depth);
      for (final child in childrenOf[_id(node)] ?? const <Map<String, dynamic>>[]) {
        walk(child, depth + 1);
      }
    }
    for (final r in roots) {
      walk(r, 0);
    }
    // 循環 parent 鏈（a→b→a）成員不屬於任何根子樹——補發於尾、視為頂層，不丟失。
    if (out.length < conversations.length) {
      final emitted = <String>{};
      for (final c in out) {
        final id = _id(c);
        if (id != null) emitted.add(id);
      }
      for (final c in conversations) {
        final id = _id(c);
        final already = id != null && emitted.contains(id)
            ? true
            : out.any((e) => identical(e, c));
        if (!already) {
          out.add(c);
          depths.add(0);
        }
      }
    }
    return (out, depths);
  }

  /// 單項深度（頂層=0）。防環：上限 8（同 ConversationTree.depthOf 契約）。
  static int depthOf(
      Map<String, dynamic> conv, List<Map<String, dynamic>> conversations) {
    final byId = <String, Map<String, dynamic>>{
      for (final c in conversations)
        if (_id(c) != null) _id(c)!: c,
    };
    var depth = 0;
    var cur = conv;
    final seen = <Map<String, dynamic>>{cur};
    while (depth < 8) {
      final pid = _pid(cur);
      if (pid == null || !byId.containsKey(pid) || pid == _id(cur)) break;
      final next = byId[pid]!;
      if (seen.contains(next)) break; // 防環（同一物件重複出現即停）
      seen.add(next);
      cur = next;
      depth++;
    }
    return depth;
  }
}
