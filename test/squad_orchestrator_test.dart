// [SPEC §9.2 對話頁v2 步驟3] 「開小隊」編排器契約測試
// 鎖定：①指令解析（明示制，零誤觸）②子對話血統（parent+context brief）
// ③出動卡/回報卡 ④countMismatch 提醒
import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/models/conversation.dart';
import 'package:bridge_app/services/squad_orchestrator.dart';

Conversation _parent({List<Message> messages = const []}) => Conversation(
      id: 'mom',
      title: '週間便當計畫',
      createdAt: DateTime(2026, 11, 17),
      updatedAt: DateTime(2026, 11, 17),
      messages: messages,
    );

void main() {
  group('parseDirective（明示指令制）', () {
    test('「開小隊：A、B、C」→ 三隊', () {
      final d = SquadOrchestrator.parseDirective('開小隊：菜單、採買、預算')!;
      expect(d.squadNames, ['菜單', '採買', '預算']);
      expect(d.claimedCount, isNull);
      expect(d.countMismatch, isFalse);
    });

    test('「開三個小隊：A,B,C」→ 宣稱3實名3，無衝突', () {
      final d = SquadOrchestrator.parseDirective('開三個小隊：菜單,採買,預算');
      expect(d, isNull); // 「三」是中文數字——v1 只支援阿拉伯數字
    });

    test('「開3個小隊：A、B、C」→ 宣稱3實名3', () {
      final d = SquadOrchestrator.parseDirective('開3個小隊：菜單、採買、預算')!;
      expect(d.claimedCount, 3);
      expect(d.squadNames.length, 3);
      expect(d.countMismatch, isFalse);
    });

    test('宣稱數≠實名數 → countMismatch（以實名為準）', () {
      final d = SquadOrchestrator.parseDirective('開5個小隊：A、B')!;
      expect(d.countMismatch, isTrue);
      expect(d.squadNames, ['A', 'B']);
    });

    test('非指令文字 → null（零誤觸鐵則）', () {
      for (final t in [
        '幫我開個小隊好嗎',
        '我今天想開小隊',
        '小隊開起來！',
        '開會：討論選單、採買',
        '你好',
        '',
      ]) {
        expect(SquadOrchestrator.parseDirective(t), isNull, reason: '「$t」不應被誤判為指令');
      }
    });

    test('指令但空隊名 → 不可執行', () {
      final d = SquadOrchestrator.parseDirective('開小隊：');
      expect(d, isNotNull);
      expect(SquadOrchestrator.isExecutable(d!), isFalse);
    });

    test('換行分隔也吃', () {
      final d = SquadOrchestrator.parseDirective('開小隊：\n菜單\n採買\n預算')!;
      expect(d.squadNames, ['菜單', '採買', '預算']);
    });
  });

  group('buildSquadConversations（血統）', () {
    test('子對話 parent 挂母、brief 注入隊名與母摘要', () {
      final parent = _parent(messages: [
        Message(
          id: 'm1',
          role: 'user',
          content: '我要規劃五天便當，預算兩千，不要香菜',
          timestamp: DateTime(2026, 11, 17),
        ),
      ]);
      final squads = SquadOrchestrator.buildSquadConversations(
        parent: parent,
        squadNames: ['菜單', '採買'],
      );
      expect(squads.length, 2);
      for (final s in squads) {
        expect(s.parentConversationId, 'mom');
        expect(s.companionId, parent.companionId);
        expect(s.messages, hasLength(1));
        expect(s.messages.first.content, contains('【小隊任務：'));
        expect(s.messages.first.content, contains('只負責'));
        expect(s.messages.first.content, contains('母對話摘要'));
      }
      expect(squads[0].title, '菜單');
      expect(squads[1].title, '採買');
      // 母摘要真的帶到母對話內容
      expect(squads[0].messages.first.content, contains('預算兩千'));
      // id 不互撞
      expect(squads[0].id, isNot(squads[1].id));
    });

    test('空母對話 → 摘要有兜底字', () {
      final squads = SquadOrchestrator.buildSquadConversations(
        parent: _parent(),
        squadNames: ['A'],
      );
      expect(squads.single.messages.first.content, contains('母對話尚無內容'));
    });
  });

  group('系統卡', () {
    test('出動卡：隊數＋各隊名', () {
      final now = DateTime(2026, 11, 17, 12);
      final squads = SquadOrchestrator.buildSquadConversations(
        parent: _parent(),
        squadNames: ['菜單', '採買'],
      );
      final card = SquadOrchestrator.buildSpawnCard(squads: squads, at: now);
      expect(card.metadata?['kind'], 'squad_spawn_card');
      expect(card.content, contains('已開 2 個小隊'));
      expect(card.content, contains('菜單'));
      expect(card.content, contains('採買'));
    });

    test('回報卡：帶 squadId 追溯', () {
      final now = DateTime(2026, 11, 17, 12);
      final card = SquadOrchestrator.buildReportCard(
        squad: _parent(), // 任意 conversation 充當
        summary: '預算抓 1,850，達標',
        at: now,
      );
      expect(card.metadata?['kind'], 'squad_report_card');
      expect(card.content, contains('回報：預算抓 1,850'));
    });
  });
}
