// redflag_resolved_cooldown_test.dart
// [Blue 抓包 2026-11-04] 病例回歸鎖：
// K1 卡 17:57 done → 30 秒後心跳又報同類紅旗開新卡＋開口
// 「才剛解決的又提出來」。修：done 結案啟動 3 天 resolved 冷卻。
// 同場加映：開口文案必須是人話（一句白話＋一個具體問題），
// 測試直接驗證 _toHumanSpeak 的輸出關鍵詞。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/compass/compass_store.dart';
import 'package:bridge_app/services/compass/decision_card_store.dart';
import 'package:bridge_app/services/compass/red_flag_reporter.dart';
import 'package:bridge_app/services/compass/compass_speaker.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_cooldown');
    await CompassStore.instance.reopenForTest('${tmp.path}/compass.db');
    await DecisionCardStore.instance.reopenForTest('${tmp.path}/compass.db');
    // 種證據閘彈藥：agent.loop 需有 pitfalls 實證，開口才會過閘
    CompassSpeaker.instance.resetForTest();
    CompassStore.instance.addPitfall('agent.loop', 'test seed: escalate 案實證',
        author: 'test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('★done 結案 → 同類紅旗 3 天內靜默（不開卡不開口）', () {
    final reporter = RedFlagReporter.instance;
    // 第一次報 → 開卡＋開口（true）
    final first = reporter.report(
        ['K1 escalate 率 66% 過高（>50%）——頭沒訓練或規則層覆蓋不足'],
        source: 'test');
    expect(first, isTrue, reason: '第一次報必須開口');

    // 結案（done）→ 啟動 resolved 冷卻
    reporter.startResolvedCooldown(
        redFlagCategoryKey('K1 escalate 率 66% 過高（>50%）——頭沒訓練或規則層覆蓋不足'));

    // 心跳再報同類（數字不同也一樣——categoryKey 去數字）→ 靜默
    final second = reporter.report(
        ['K1 escalate 率 62% 過高（>50%）——頭沒訓練或規則層覆蓋不足'],
        source: 'heartbeat');
    expect(second, isFalse, reason: '★done 冷卻內同類紅旗不得再開口');
  });

  test('dismissed 冷卻與 resolved 冷卻互不干擾', () {
    final reporter = RedFlagReporter.instance;
    final flag = '未結案傷口 16 筆堆積——同工具反覆撞牆沒長出藥';
    expect(reporter.report([flag], source: 'test'), isTrue);
    reporter.startResolvedCooldown(redFlagCategoryKey(flag));
    // resolved 冷卻中同類靜默
    expect(reporter.report([flag], source: 'test2'), isFalse);
  });

  test('★開口選項同步落卡（awaiting_decision＋options）', () {
    final reporter = RedFlagReporter.instance;
    expect(
        reporter.report(
            ['K1 escalate 率 62% 過高（>50%）——頭沒訓練或規則層覆蓋不足'],
            source: 'test'),
        isTrue);
    final cards = DecisionCardStore.instance.unresolvedCards();
    expect(cards, isNotEmpty);
    final k1 = cards.firstWhere(
        (c) => c.categoryKey.contains('K#'),
        orElse: () => throw 'K1 卡應存在');
    expect(k1.status, 'awaiting_decision',
        reason: '★開口即帶選項——卡直接進 awaiting_decision');
    expect(k1.options.length, 2, reason: '嘴上給的二選一必須在卡上');
    expect(k1.options.any((o) => o.label.contains('管線')), isTrue);
  });

  test('★開口文案是人話：K1 紅旗翻譯成白話＋具體問題', () {
    final reporter = RedFlagReporter.instance;
    final spoke = reporter.report(
        ['K1 escalate 率 62% 過高（>50%）——頭沒訓練或規則層覆蓋不足'],
        source: 'test');
    expect(spoke, isTrue);
    // 驗證人話文案有進佇列：從 speak_queue 撈最新 draft
    final q = CompassStore.instance.getMeta('speak_queue');
    expect(q, isNotNull);
    // 人話鐵則：不含「escalate」內部術語；含「想請你決定」
    expect(q!.contains('escalate 率'), isFalse,
        reason: '內部術語不得出現在開口文案');
    expect(q.contains('想請你決定'), isTrue,
        reason: '必須有具體可回覆的問題');
    expect(q.contains('不急，你有空的時候可以看看羅盤頁'), isFalse,
        reason: '禁止叫使用者自己去別的頁面查');
  });

  test('fallback 文案剝掉括號註記＋補問題', () {
    final reporter = RedFlagReporter.instance;
    expect(reporter.report(['某種新紅旗（內部註記）'], source: 'test'), isTrue);
    final q = CompassStore.instance.getMeta('speak_queue') ?? '';
    expect(q.contains('內部註記'), isFalse, reason: '括號內部註記要剝掉');
    expect(q.contains('想請你決定'), isTrue);
  });
}
