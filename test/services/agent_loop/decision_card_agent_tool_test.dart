// decision_card_agent_tool_test.dart
// [小葵 2026-11-03 待決策卡閉環 Step 3 驗收]
// 拍板流三件套：查卡 → 提案（2-3 選項恰一個建議）→ 結案
// （done 必附證據／dismiss 啟動 7 天冷卻）。
// 工具錯誤訊息當教材：壞 JSON 附正確格式範例。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/compass/compass_store.dart';
import 'package:bridge_app/services/compass/decision_card_store.dart';
import 'package:bridge_app/services/compass/red_flag_reporter.dart';
import 'package:bridge_app/services/agent_loop/agent_loop_tools/decision_card_agent_tool.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('decision_tool_test');
    await CompassStore.instance
        .reopenForTest('${tmp.path}/compass_store.db');
    await DecisionCardStore.instance
        .reopenForTest('${tmp.path}/compass_store.db');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  DecisionCard seedCard() {
    final c = DecisionCardStore.instance.tryOpenCard(
      title: 'K1 escalate 率 62% 過高',
      body: '證據：22 次工具軌跡',
      categoryKey: 'K# escalate 率 #% 過高',
      source: 'daytime_heartbeat',
    );
    expect(c, isNotNull);
    return c!;
  }

  group('decision_cards 查卡', () {
    test('空清單誠實回報；有卡列 id/status/body', () async {
      final tool = DecisionCardsTool();
      final empty = await tool.execute({});
      expect(empty.success, isTrue);
      expect(empty.content, contains('沒有未結案'));

      seedCard();
      final res = await tool.execute({});
      expect(res.content, contains('dc_'));
      expect(res.content, contains('K1 escalate'));
      expect(res.content, contains('status: open'));
    });
  });

  group('decision_propose 提案', () {
    test('合法提案 → awaiting_decision＋選項入卡', () async {
      final card = seedCard();
      final tool = DecisionProposeTool();
      final res = await tool.execute({
        'card_id': card.id,
        'options':
            '[{"id":"opt_1","label":"訓練K1頭","detail":"重訓","recommended":true},'
            '{"id":"opt_2","label":"補規則層","detail":"寫硬規則"}]',
      });
      expect(res.success, isTrue);
      final updated = DecisionCardStore.instance.byId(card.id)!;
      expect(updated.status, 'awaiting_decision');
      expect(updated.options.length, 2);
      expect(updated.options.first.label, '訓練K1頭');
    });

    test('★壞 JSON 錯誤訊息附正確格式範例（教材式）', () async {
      final card = seedCard();
      final tool = DecisionProposeTool();
      final res = await tool.execute({
        'card_id': card.id,
        'options': 'opt_1 訓練, opt_2 規則', // 不是 JSON
      });
      expect(res.success, isFalse);
      expect(res.content, contains('JSON'), reason: '錯誤訊息要教格式');
      expect(res.content, contains('label'), reason: '範例要照抄得動');
    });

    test('json 圍籬容錯——```json 包裹也吃得下', () async {
      final card = seedCard();
      final res = await DecisionProposeTool().execute({
        'card_id': card.id,
        'options':
            '```json\n[{"label":"A","detail":"a","recommended":true},{"label":"B","detail":"b"}]\n```',
      });
      expect(res.success, isTrue, reason: '模型常用圍籬——loose 解析要吃');
      expect(DecisionCardStore.instance.byId(card.id)!.options.length, 2);
    });

    test('恰一個 recommended 鐵則', () async {
      final card = seedCard();
      final res = await DecisionProposeTool().execute({
        'card_id': card.id,
        'options':
            '[{"label":"A","recommended":true},{"label":"B","recommended":true}]',
      });
      expect(res.success, isFalse);
      expect(res.content, contains('恰一個'));
    });
  });

  group('decision_resolve 結案', () {
    test('done 帶證據 → resolved；缺 note 擋下', () async {
      final card = seedCard();
      final tool = DecisionResolveTool();
      final noNote = await tool.execute(
          {'card_id': card.id, 'action': 'done', 'chosen_option_id': 'opt_1'});
      expect(noNote.success, isFalse, reason: '「已完成」不算證據');
      expect(noNote.content, contains('證據'));

      final ok = await tool.execute({
        'card_id': card.id,
        'action': 'done',
        'chosen_option_id': 'opt_1',
        'note': '已重訓 K1 頭，escalate 率 62%→38%（compass_read 回讀驗證）',
      });
      expect(ok.success, isTrue);
      final done = DecisionCardStore.instance.byId(card.id)!;
      expect(done.status, 'done');
      expect(done.chosenOptionId, 'opt_1');
      expect(done.closeReason, 'resolved');
    });

    test('★dismiss → 結案＋同類紅旗冷卻 7 天', () async {
      final card = seedCard();
      final res = await DecisionResolveTool()
          .execute({'card_id': card.id, 'action': 'dismiss'});
      expect(res.success, isTrue);
      expect(DecisionCardStore.instance.byId(card.id)!.status, 'dismissed');
      // 冷卻生效：同類再報 → 靜默
      final reReport = RedFlagReporter.instance.report(
          ['K1 escalate 率 65% 過高（>50%）——頭沒訓練或規則層覆蓋不足'],
          source: 'daytime_heartbeat');
      expect(reReport, isFalse, reason: 'dismissed 冷卻期內同類不重報');
    });

    test('非法 action 教材式擋下', () async {
      final card = seedCard();
      final res = await DecisionResolveTool()
          .execute({'card_id': card.id, 'action': 'maybe'});
      expect(res.success, isFalse);
      expect(res.content, contains('done 或 dismiss'));
    });
  });
}
