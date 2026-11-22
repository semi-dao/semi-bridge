// proactive_gc_and_tombstone_test.dart
// [小葵 2026-11-03 晚場 Blue 令] 主動回應消除機制驗收：
// ① 墓碑：刪除後殘影 save 不得復活；restore 撤墓碑可救回
// ② GC1 同日重複：留新刪舊（軟刪除進回收桶）
// ③ GC2 結案清場：綁定卡全部 done → 對話退場
// ④ GC3 空殼：msgs≤1 且 >3 天 → 回收桶
// 病例標本：「主動回應 10/29」×5、「11/3」×3（race 屍體洗板）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/services/conversation_store.dart';
import 'package:bridge_app/models/conversation.dart';
import 'package:bridge_app/services/compass/compass_store.dart';
import 'package:bridge_app/services/compass/decision_card_store.dart';
import 'package:bridge_app/services/compass/proactive_session_gc.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('gc_test');
    ConversationStore.debugSetStorageDirectory(tmp);
    await CompassStore.instance.reopenForTest('${tmp.path}/compass.db');
    await DecisionCardStore.instance.reopenForTest('${tmp.path}/compass.db');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Conversation makeProactive(String id, String title, DateTime updatedAt,
      {int msgs = 1}) {
    final conv = Conversation.create(title: title).copyWith(
      type: ConversationType.proactive,
      updatedAt: updatedAt,
    );
    // 測試用固定 id：直接以目標 id 重建（create 產生隨機 id）
    return Conversation(
      id: id,
      title: title,
      createdAt: updatedAt,
      updatedAt: updatedAt,
      type: ConversationType.proactive,
      messages: List.generate(
          msgs, (i) => Message(
              id: 'm$i', role: 'assistant', content: 'x', timestamp: updatedAt)),
    );
  }

  group('① 墓碑：刪除不復活', () {
    test('★刪除後殘影 save 被墓碑攔截', () async {
      final conv = makeProactive('conv_del', '主動回應 11/3', DateTime.now());
      await ConversationStore.save(conv);
      expect((await ConversationStore.getAll()).length, 1);

      await ConversationStore.delete('conv_del');
      expect((await ConversationStore.getAll()).length, 0,
          reason: '刪除後列表清空');

      // 殘影寫入（懸浮窗記憶體殘影情境）
      await ConversationStore.save(conv);
      expect((await ConversationStore.getAll()).length, 0,
          reason: '墓碑必須攔下殘影復活寫入');
    });

    test('★restore 撤墓碑——後悔藥可用', () async {
      final conv = makeProactive('conv_restore', '主動回應 11/2', DateTime.now());
      await ConversationStore.save(conv);
      await ConversationStore.delete('conv_restore');

      final ok = await ConversationStore.restore('conv_restore');
      expect(ok, isTrue);
      expect((await ConversationStore.getAll()).length, 1,
          reason: '救回後對話回列表');
      // 救回後再 save 不該被攔
      await ConversationStore.save(conv);
      expect((await ConversationStore.getAll()).length, 1);
    });

    test('墓碑跨 session——重載後仍攔（模擬 App 重啟記憶體清空）', () async {
      final conv = makeProactive('conv_tomb', '主動回應 11/1', DateTime.now());
      await ConversationStore.save(conv);
      await ConversationStore.delete('conv_tomb');
      // 模擬重啟：tombstone persisted 在 SharedPreferences（mock），
      // _explicitlyDeleted 靠 _loadTombstones 於 save 時重載。
      // 這裡無法清 static set，但驗證 persist 有寫入：
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('bridge_deleted_tombstones') ?? [];
      expect(saved, contains('conv_tomb'), reason: '墓碑必須落盤');
    });
  });

  group('②③④ GC 三刀', () {
    test('★GC1 同標題留新刪舊', () async {
      final now = DateTime.now();
      await ConversationStore.save(makeProactive('a1', '主動回應 10/29',
          now.subtract(const Duration(hours: 1))));
      await ConversationStore.save(
          makeProactive('a2', '主動回應 10/29', now)); // 最新
      await ConversationStore.save(makeProactive('a3', '主動回應 10/29',
          now.subtract(const Duration(hours: 2))));

      // 手動觸發 GC（繞過 _done 冪等：直接新實例不行——改用未跑過的狀態）
      final gc = ProactiveSessionGc.instance;
      final report = await gc.runOncePublic();
      final all = await ConversationStore.getAll();
      final titles = all.map((c) => c.id).toList();
      expect(titles, contains('a2'), reason: '最新的留');
      expect(titles, isNot(contains('a1')));
      expect(titles, isNot(contains('a3')));
      expect(report['dedup'], 2);
      // 回收桶有救
      expect((await ConversationStore.listTrash()).length, greaterThanOrEqualTo(2));
    });

    test('★GC2 綁定卡全結案 → 對話清場', () async {
      final now = DateTime.now();
      final convId = 'conv_k1';
      await ConversationStore.save(makeProactive(convId, '主動回應 11/3', now, msgs: 5));
      final card = DecisionCardStore.instance.tryOpenCard(
          title: 'K1', body: '', categoryKey: 'k1', source: 'test')!;
      DecisionCardStore.instance.bindConversation(card.id, convId);
      DecisionCardStore.instance.markDiscussing(card.id);
      // 未結案 → 不清
      var gc = ProactiveSessionGc.instance;
      await gc.runOncePublic();
      expect((await ConversationStore.getAll()).length, 1);
      // 結案 → 清
      DecisionCardStore.instance.markDecided(card.id, 'opt_1');
      DecisionCardStore.instance.closeResolved(card.id, note: '完成');
      gc = ProactiveSessionGc.instance;
      await gc.runOncePublic();
      expect((await ConversationStore.getAll()).length, 0,
          reason: '卡全結案 → 對話退場');
    });

    test('GC3 空殼 >3 天清、新空殼留', () async {
      final now = DateTime.now();
      await ConversationStore.save(makeProactive('old_shell', '主動回應 10/20',
          now.subtract(const Duration(days: 5)))); // 舊空殼
      await ConversationStore.save(makeProactive('new_shell', '主動回應 10/21',
          now.subtract(const Duration(days: 1)))); // 新空殼（今天 race 的）

      final gc = ProactiveSessionGc.instance;
      await gc.runOncePublic();
      final ids = (await ConversationStore.getAll()).map((c) => c.id);
      expect(ids, contains('new_shell'), reason: '1 天的空殼先留（可能還在談）');
      expect(ids, isNot(contains('old_shell')), reason: '5 天空殼=race 屍體，收');
    });
  });
}
