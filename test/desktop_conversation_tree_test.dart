// [SPEC §9.2 對話頁v2 步驟2] 對話樹排序契約測試
// 鎖定：①子對話緊跟母對話之後（DFS 前序）②孤兒不丟失（視為頂層）
// ③自環（parent=自己）視為頂層 ④循環 parent 鏈不死鎖（depth 上限 8）
import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/utils/conversation_tree.dart';
import 'package:bridge_app/models/conversation.dart';

Conversation _conv(String id, {String? parent, String title = ''}) {
  return Conversation(
    id: id,
    title: title,
    createdAt: DateTime(2026, 11, 17),
    updatedAt: DateTime(2026, 11, 17),
    messages: const [],
    parentConversationId: parent,
  );
}

void main() {
  test('子對話緊跟母對話之後（DFS 前序）', () {
    final a = _conv('a');
    final a1 = _conv('a1', parent: 'a');
    final a2 = _conv('a2', parent: 'a');
    final a1x = _conv('a1x', parent: 'a1');
    final b = _conv('b');
    // 故意亂序輸入。契約：母之後緊跟其子（子依 conversations 原順序）
    final ordered = ConversationTree.order([a1x, b, a2, a, a1]).map((c) => c.id).toList();
    // a 的 children=[a2,a1]（原輸入序）；a1 的 child=[a1x]
    expect(ordered, ['b', 'a', 'a2', 'a1', 'a1x']);
    // 性質斷言（不依賴具體順序）：每個子對話的直接母就在它前面的祖先鏈上
    final pos = {for (final id in ordered) id: ordered.indexOf(id)};
    expect(pos['a1']! > pos['a']!, isTrue);
    expect(pos['a1x']! > pos['a1']!, isTrue);
    expect(pos['a2']! > pos['a']!, isTrue);
  });

  test('孤兒（parent 不存在）視為頂層，不丟失', () {
    final a = _conv('a');
    final orphan = _conv('ghost-child', parent: 'nonexistent');
    final ordered = ConversationTree.order([orphan, a]).map((c) => c.id).toList();
    expect(ordered, containsAll(['a', 'ghost-child']));
    expect(ordered.length, 2);
  });

  test('自環（parent=自己）視為頂層', () {
    final selfRef = _conv('loop', parent: 'loop');
    final ordered = ConversationTree.order([selfRef]);
    expect(ordered.single.id, 'loop');
    expect(ConversationTree.depthOf(selfRef, [selfRef]), 0);
  });

  test('循環 parent 鏈不死鎖（a→b→a）', () {
    final a = _conv('a', parent: 'b');
    final b = _conv('b', parent: 'a');
    final ordered = ConversationTree.order([a, b]);
    // 循環鏈上兩則互指：都不會成為「有效母的子」→ 都當頂層（順序保持輸入序）
    expect(ordered.length, 2); // 不丟失
    // depthOf 有上限保護，正常返回
    expect(ConversationTree.depthOf(a, [a, b]), lessThanOrEqualTo(8));
  });

  test('depthOf：頂層=0、子=1、孫=2', () {
    final a = _conv('a');
    final a1 = _conv('a1', parent: 'a');
    final a1x = _conv('a1x', parent: 'a1');
    final all = [a, a1, a1x];
    expect(ConversationTree.depthOf(a, all), 0);
    expect(ConversationTree.depthOf(a1, all), 1);
    expect(ConversationTree.depthOf(a1x, all), 2);
  });

  test('空清單與全頂層（現網 21 對話現況）向後相容', () {
    expect(ConversationTree.order(const []), isEmpty);
    final flats = [_conv('1'), _conv('2'), _conv('3')];
    expect(ConversationTree.order(flats).map((c) => c.id), ['1', '2', '3']);
  });
}
