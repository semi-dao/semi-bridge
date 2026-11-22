// [SPEC §9 小隊狀態燈] squadStatus 純函式契約測試
// 鎖定五態：待命／待回覆／已回覆／已回報／非 squad 空字串
import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/utils/conversation_tree.dart';
import 'package:bridge_app/models/conversation.dart';

Message _msg(String role, {Map<String, dynamic>? metadata}) {
  return Message(
    id: 'm-$role-${DateTime.now().microsecondsSinceEpoch}',
    role: role,
    content: '內容',
    timestamp: DateTime(2026, 11, 17),
    metadata: metadata,
  );
}

Conversation _squad(String id, List<Message> messages, {String? parent}) {
  return Conversation(
    id: id,
    title: '小隊成員',
    createdAt: DateTime(2026, 11, 17),
    updatedAt: DateTime(2026, 11, 17),
    messages: messages,
    parentConversationId: parent ?? 'mother',
  );
}

void main() {
  test('待命：squad 對話只有開小隊指令一則（messages≤1）', () {
    final c = _squad('squad-m-0-1', [_msg('user')]);
    expect(ConversationTree.squadStatus(c), '待命');
  });

  test('待回覆：最後一則 role=user（指令已進入、AI 尚未回覆）', () {
    final c = _squad(
      'squad-m-0-1',
      [_msg('assistant'), _msg('user')],
    );
    expect(ConversationTree.squadStatus(c), '待回覆');
  });

  test('已回覆：最後 assistant 且非回報卡', () {
    final c = _squad(
      'squad-m-0-1',
      [_msg('user'), _msg('assistant')],
    );
    expect(ConversationTree.squadStatus(c), '已回覆');
  });

  test('已回報：最後 assistant 且 metadata.kind=squad_report_card', () {
    final c = _squad(
      'squad-m-0-1',
      [
        _msg('user'),
        _msg('assistant', metadata: {
          'kind': 'squad_report_card',
          'squadId': 'sq1',
        }),
      ],
    );
    expect(ConversationTree.squadStatus(c), '已回報');
  });

  test('非 squad（無 parent 或 id 不帶 squad- 前綴）→ 空字串', () {
    // 一般對話：無 parent
    final noParent = Conversation(
      id: '123',
      title: '一般',
      createdAt: DateTime(2026, 11, 17),
      updatedAt: DateTime(2026, 11, 17),
      messages: [_msg('user'), _msg('assistant')],
    );
    expect(ConversationTree.squadStatus(noParent), '');
    // 有 parent 但 id 非 squad- 開頭（匯入串接等其它 parent 用途）
    final imported = Conversation(
      id: 'imported-1',
      title: '匯入',
      createdAt: DateTime(2026, 11, 17),
      updatedAt: DateTime(2026, 11, 17),
      messages: [_msg('user'), _msg('assistant')],
      parentConversationId: 'mother',
    );
    expect(ConversationTree.squadStatus(imported), '');
  });
}
