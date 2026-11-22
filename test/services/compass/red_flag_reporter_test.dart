// red_flag_reporter_test.dart
// [小葵 2026-11-03 待決策卡閉環 Step 2 驗收]
// 病例回歸：同三面紅旗 10/29–11/3 每天重報 → 開卡後同類未結案＝靜默；
// dismissed 後 7 天冷卻。speaker 佇列用真 CompassSpeaker（落同顆 db，
// enqueue 本來就走 compass_meta 持久化——不用 mock）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/compass/compass_store.dart';
import 'package:bridge_app/services/compass/compass_speaker.dart';
import 'package:bridge_app/services/compass/decision_card_store.dart';
import 'package:bridge_app/services/compass/red_flag_reporter.dart';

void main() {
  late Directory tmp;
  late String dbPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('redflag_test');
    dbPath = '${tmp.path}/compass_store.db';
    await CompassStore.instance.reopenForTest(dbPath);
    await DecisionCardStore.instance.reopenForTest(dbPath);
    CompassSpeaker.instance.resetForTest();
    // 證據閘種子——CompassSpeaker 閘② 要 agent.loop 有 pitfalls 實證
    // （乾淨 db 沒種子會被閘擋，測的是開卡邏輯不是閘）。
    CompassStore.instance.addPitfall(
        'agent.loop', 'test seed: escalate 案實證',
        author: 'test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('★同批紅旗第二次 report 全靜默（治每天重報）', () {
    final flags = [
      'K1 escalate 率 62% 過高（>50%）——頭沒訓練或規則層覆蓋不足',
      '未結案傷口 16 筆堆積——同工具反覆撞牆沒長出藥',
    ];
    final first = RedFlagReporter.instance
        .report(flags, source: 'daytime_heartbeat');
    expect(first, isTrue, reason: '首次——開卡＋入列');
    expect(DecisionCardStore.instance.unresolvedCards().length, 2);

    // 隔天同類（數字變了也算同類——redFlagCategoryKey 歸一）
    final second = RedFlagReporter.instance.report([
      'K1 escalate 率 63% 過高（>50%）——頭沒訓練或規則層覆蓋不足',
      '未結案傷口 17 筆堆積——同工具反覆撞牆沒長出藥',
    ], source: 'daytime_heartbeat');
    expect(second, isFalse, reason: '同類未結案卡存在——靜默（治重報）');
    expect(DecisionCardStore.instance.unresolvedCards().length, 2,
        reason: '沒開新卡');
  });

  test('★dismissed 後同類冷卻——冷卻期內不報，新卡不再開', () {
    final reporter = RedFlagReporter.instance;
    final flags = ['認知傷口 2 筆未結案——結論與事實不符'];
    expect(reporter.report(flags, source: 'dream'), isTrue);

    // 使用者說「先不處理」→ dismissed 結案＋啟動冷卻
    final cards = DecisionCardStore.instance.unresolvedCards();
    final catKey = redFlagCategoryKey(flags.first);
    DecisionCardStore.instance.closeDismissed(cards.first.id);
    reporter.startCooldown(catKey);

    // 冷卻期內同類再報 → 靜默
    expect(reporter.report(['認知傷口 3 筆未結案——結論與事實不符'],
        source: 'daytime_heartbeat'), isFalse);
    // 卡已 dismissed（未結案 0）——冷卻閘在擋，不是舊卡在擋
    expect(DecisionCardStore.instance.unresolvedCards(), isEmpty);
  });

  test('冷卻到期後同類可再開新卡（不永遠閉嘴）', () {
    final reporter = RedFlagReporter.instance;
    final flag = 'K1 escalate 率 62% 過高（>50%）——頭沒訓練或規則層覆蓋不足';
    final catKey = redFlagCategoryKey(flag);
    expect(reporter.report([flag], source: 'dream'), isTrue);
    final card = DecisionCardStore.instance.unresolvedCards().first;
    DecisionCardStore.instance.closeDismissed(card.id);
    // 手動把冷卻寫到過去——模擬 7 天後
    CompassStore.instance.setMeta('redflag_cooldown_$catKey',
        DateTime.now().subtract(const Duration(days: 1)).toIso8601String());
    expect(reporter.report([flag], source: 'dream'), isTrue,
        reason: '冷卻到期——新事件新卡');
    expect(DecisionCardStore.instance.unresolvedCards().length, 1);
  });
}
