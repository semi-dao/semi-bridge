// [SPEC §9.2 觸發線 2026-11-17] 小隊回報卡觸發線的純函式契約測試
// 鎖定：①shouldReport 三條件（squad- 前綴＋掛母＋最後一則 assistant）
// ②reportCardId 穩定性（同回覆同 id＝防重複插卡的鍵）
import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/models/conversation.dart';
import 'package:bridge_app/services/squad_orchestrator.dart';

Message _msg(String id, String role) => Message(
      id: id,
      role: role,
      content: '內容_$id',
      timestamp: DateTime(2026, 11, 17),
    );

Conversation _squad({
  String id = 'squad-mom-0-1000',
  String? parentConversationId = 'mom',
  List<Message> messages = const [],
}) =>
    Conversation(
      id: id,
      title: '菜單',
      createdAt: DateTime(2026, 11, 17),
      updatedAt: DateTime(2026, 11, 17),
      messages: messages,
      parentConversationId: parentConversationId,
    );

void main() {
  group('shouldReport', () {
    test('①小隊（squad- 前綴＋掛母）最後一則 assistant → true', () {
      final s = _squad(messages: [
        _msg('u1', 'user'),
        _msg('a1', 'assistant'),
      ]);
      expect(SquadOrchestrator.shouldReport(s), isTrue);
    });

    test('②一般對話（無 squad- 前綴）→ false，即使最後一則 assistant', () {
      final c = Conversation(
        id: '1730000000000',
        title: '一般對話',
        createdAt: DateTime(2026, 11, 17),
        updatedAt: DateTime(2026, 11, 17),
        messages: [_msg('a1', 'assistant')],
      );
      expect(SquadOrchestrator.shouldReport(c), isFalse);
    });

    test('③id 有 squad- 但 parentConversationId 為 null → false', () {
      final s = _squad(
        parentConversationId: null,
        messages: [_msg('a1', 'assistant')],
      );
      expect(SquadOrchestrator.shouldReport(s), isFalse);
    });

    test('最後一則不是 assistant（還在等人回／空對話）→ false', () {
      expect(
        SquadOrchestrator.shouldReport(
          _squad(messages: [_msg('a1', 'assistant'), _msg('u2', 'user')]),
        ),
        isFalse,
      );
      expect(SquadOrchestrator.shouldReport(_squad()), isFalse);
    });
  });

  group('reportCardId', () {
    test('④穩定：同一對話（同最後 assistant）兩次呼叫同值', () {
      final s = _squad(messages: [
        _msg('u1', 'user'),
        _msg('a1', 'assistant'),
      ]);
      expect(SquadOrchestrator.reportCardId(s),
          SquadOrchestrator.reportCardId(s));
      expect(SquadOrchestrator.reportCardId(s), 'squad-report-${s.id}-a1');
    });

    test('不同最後 assistant 訊息 → 不同 id（新回覆＝新卡鍵）', () {
      final s1 = _squad(messages: [_msg('a1', 'assistant')]);
      final s2 = s1.copyWith(messages: [...s1.messages, _msg('u2', 'user'),
          _msg('a2', 'assistant')]);
      expect(SquadOrchestrator.reportCardId(s1),
          isNot(SquadOrchestrator.reportCardId(s2)));
    });
  });

  group('buildReportCard 與去重鍵銜接', () {
    test('傳入 id 時卡 id＝reportCardId；metadata 帶 kind+squadId', () {
      final s = _squad(messages: [_msg('a1', 'assistant')]);
      final card = SquadOrchestrator.buildReportCard(
        squad: s,
        summary: '菜單結論前三菜',
        at: DateTime(2026, 11, 17, 12),
        id: SquadOrchestrator.reportCardId(s),
      );
      expect(card.id, 'squad-report-${s.id}-a1');
      expect(card.metadata?['kind'], 'squad_report_card');
      expect(card.metadata?['squadId'], s.id);
    });
  });
}
