// [2026-11-21 章魚光呼吸樹] Map 版樹排序契約測試——手機端對話清單專用。
// 契約鏡像 test/desktop_conversation_tree_test.dart（物件版 ConversationTree）：
// ①子對話緊跟母對話之後（DFS 前序，子依原序）②孤兒不丟失（視為頂層）
// ③自環（parent=自己）視為頂層 ④循環 parent 鏈不死鎖、成員補發不丟失
// ⑤orderWithDepths 深度與 depthOf 一致
import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/utils/conversation_tree_map.dart';

Map<String, dynamic> _conv(String id, {String? parent, String title = ''}) =>
    {'id': id, 'title': title, if (parent != null) 'parentConversationId': parent};

void main() {
  group('ConversationTreeMap（Map 版樹排序）', () {
    test('子對話緊跟母對話之後（DFS 前序）', () {
      final list = [
        _conv('a1x', parent: 'a1'),
        _conv('b'),
        _conv('a2', parent: 'a'),
        _conv('a'),
        _conv('a1', parent: 'a'),
      ];
      // a 的 children=[a2,a1]（原輸入序）；a1 的 child=[a1x]
      final (ordered, depths) = ConversationTreeMap.orderWithDepths(list);
      expect(ordered.map((c) => c['id']).toList(),
          ['b', 'a', 'a2', 'a1', 'a1x']);
      expect(depths, [0, 0, 1, 1, 2]);
    });

    test('孤兒（parent 不存在）視為頂層，不丟失', () {
      final list = [_conv('x', parent: 'ghost'), _conv('y')];
      final (ordered, depths) = ConversationTreeMap.orderWithDepths(list);
      expect(ordered.map((c) => c['id']).toList(), ['x', 'y']);
      expect(depths, [0, 0]);
    });

    test('自環（parent=自己）視為頂層', () {
      final list = [_conv('s', parent: 's')];
      final (ordered, depths) = ConversationTreeMap.orderWithDepths(list);
      expect(ordered.map((c) => c['id']).toList(), ['s']);
      expect(depths, [0]);
      expect(ConversationTreeMap.depthOf(list.first, list), 0);
    });

    test('循環 parent 鏈（a→b→a）不死鎖，成員補發不丟失', () {
      final list = [_conv('a', parent: 'b'), _conv('b', parent: 'a')];
      final (ordered, depths) = ConversationTreeMap.orderWithDepths(list);
      expect(ordered.length, 2);
      expect(ordered.map((c) => c['id']).toSet(), {'a', 'b'});
      // 循環鏈無根可掛——補發於尾視為頂層
      expect(depths, [0, 0]);
      // 防環：深度上限不死鎖
      expect(ConversationTreeMap.depthOf(list.first, list), lessThanOrEqualTo(8));
    });

    test('orderWithDepths 深度與 depthOf 一致（深鏈）', () {
      final list = [
        _conv('r'),
        _conv('c1', parent: 'r'),
        _conv('c2', parent: 'c1'),
        _conv('c3', parent: 'c2'),
      ];
      final (ordered, depths) = ConversationTreeMap.orderWithDepths(list);
      expect(ordered.map((c) => c['id']).toList(), ['r', 'c1', 'c2', 'c3']);
      for (var i = 0; i < ordered.length; i++) {
        expect(ConversationTreeMap.depthOf(ordered[i], list), depths[i],
            reason: '深度一致性：${ordered[i]['id']}');
      }
      expect(depths, [0, 1, 2, 3]);
    });

    test('parentConversationId null/空字串皆視為頂層', () {
      final list = [
        {'id': 'n1', 'parentConversationId': null},
        {'id': 'n2', 'parentConversationId': ''},
      ];
      final (ordered, depths) = ConversationTreeMap.orderWithDepths(list);
      expect(ordered.map((c) => c['id']).toList(), ['n1', 'n2']);
      expect(depths, [0, 0]);
    });
  });
}
