// [小葵 2026-10-05 生命樹代謝] 三洞修復回歸鎖
// Blue 問「夢 365 天會不會擁腫」→ 量測發現三個代謝洞：
//   洞一：遺憾永遠是遺憾（markRevisited 無人呼叫）
//   洞二：夢卡只寫不讀（她的 prompt 不吃夢）
//   洞三：草稿卡無生命週期（agent_draft 永不升級）
// 本測試鎖死三個修法。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/services/life_tree/life_tree_store.dart';
import 'package:bridge_app/services/life_tree/dream_service.dart';
import 'package:bridge_app/services/compass/compass_self_gauge.dart';

void main() {
  late Directory tmp;
  late LifeTreeStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('life_tree_metabolism');
    store = LifeTreeStore.instance;
    store.dispose(); // 清掉前一測試的連線
    LifeTreeStore.dbPathOverride = '${tmp.path}/life_tree.db';
  });

  tearDown(() async {
    store.dispose();
    LifeTreeStore.dbPathOverride = null;
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  LifeTreeDream dream(String conclusion,
      {String decision = 'maintain', String type = 'agent_draft'}) {
    return LifeTreeDream(
      dreamSessionId: 's_test',
      branchType: type,
      conclusion: conclusion,
      decision: decision,
      sourceClues: const [],
      companionIds: const ['test'],
      modelUsed: 'rule-engine',
      createdAt: DateTime.now(),
    );
  }

  CompassSelfMetrics zeroMetrics() => CompassSelfMetrics(
        k1Judgments: 0,
        k1Need: 0,
        k1Escalated: 0,
        k1EscalateRate: 0,
        k1RuleShare: 0,
        selfHeals: 0,
        pendingWounds: 0,
        cognitiveWounds: 0,
        medicines: 0,
        pitfalls: 0,
        coverage: 0,
        dreams: 0,
        unrevisited: 0,
        computedAt: DateTime.now(),
      );

  test('洞一：遺憾進夢後自動結案——清單縮短，明晚不重複夢', () {
    store.addThoughtBranch(LifeTreeThoughtBranch(
      ledgerId: 1,
      thought: '曾想過把 K1 閾值做成每個 companion 獨立',
      createdAt: DateTime.now(),
    ));
    expect(store.unrevisitedBranches().length, 1);

    final result = DreamService.instance.runDream(
      redFlags: const [],
      metrics: zeroMetrics(),
      regrets: store.unrevisitedBranches(limit: 5),
    );

    // 遺憾被夢過 → 自動 markRevisited → 清單歸零
    expect(result.revisited, 1, reason: '進夢即結案');
    expect(store.unrevisitedBranches().length, 0,
        reason: '明晚不再重複夢同一條遺憾');
  });

  test('洞二：activeLessons 只撈 7 天內有料的卡（安睡卡排除）', () {
    // 有料的卡（今天的）
    store.addDream(
        dream('需要處理：未結案傷口 8 筆堆積', decision: 'escalate_to_user'));
    // 安睡卡（無資訊量——排除）
    store.addDream(dream('這場夢沒有發現問題：紅燈 0、遺憾 0。安睡。'));

    final lessons = store.activeLessons();
    expect(lessons.length, 1);
    expect(lessons.first.conclusion, contains('未結案傷口'));
  });

  test('洞三：被白天引用的草稿卡自動升級 consensus', () {
    final draftId = store.addDream(dream('需要處理：未結案傷口 8 筆堆積',
        decision: 'escalate_to_user'));
    final n = store.promoteDraftsReferenced([draftId]);
    expect(n, 1, reason: '升級成功一張');

    final after =
        store.recentDreams(limit: 5).firstWhere((d) => d.id == draftId);
    expect(after.branchType, 'agent_consensus');
    expect(after.conclusion, contains('[已用於白天·升級]'),
        reason: '升級留痕不覆寫原文');

    // 再升一次不重複計（已是 consensus）
    final n2 = store.promoteDraftsReferenced([draftId]);
    expect(n2, 0, reason: '已升級的不再重複');
  });

  test('裁決：propose 卡 adjudicate 後納入回灌、顯示已裁決', () {
    // 未裁決的 propose 卡——不是藥是議題，不回灌
    final pid = store.addDream(dream('需要處理：X 系統異常', decision: 'propose'));
    expect(store.activeLessons().where((d) => d.id == pid), isEmpty,
        reason: '未裁決 propose 不回灌');

    // 裁決
    final ok = store.adjudicate(pid, '同意，照做');
    expect(ok, isTrue);

    // 裁決後讀回——時間戳＋文字都在
    final after = store.recentDreams(limit: 5).firstWhere((d) => d.id == pid);
    expect(after.adjudicatedAt, isNotNull);
    expect(after.adjudication, '同意，照做');

    // 已裁決 propose 卡成為藥——納入回灌
    expect(store.activeLessons().where((d) => d.id == pid), isNotEmpty,
        reason: '已裁決的 propose 升級為藥');
  });
}
