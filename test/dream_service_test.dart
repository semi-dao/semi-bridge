// [小葵 2026-09-21] R5 夢境沉思回歸鎖
// 夢境寫生命樹——用 dbPathOverride 注入暫存 DB（R4 教訓：測試絕不碰真庫）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/compass/compass_self_gauge.dart';
import 'package:bridge_app/services/life_tree/dream_service.dart';
import 'package:bridge_app/services/life_tree/life_tree_store.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dream_test');
    LifeTreeStore.dbPathOverride = '${tmp.path}/causal_ledger.db';
  });

  tearDown(() {
    LifeTreeStore.instance.dispose();
    LifeTreeStore.dbPathOverride = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  CompassSelfMetrics metrics({
    int judgments = 0,
    int need = 0,
    int escalated = 0,
    int heals = 0,
    int pending = 0,
    int cognitive = 0,
  }) =>
      CompassSelfMetrics(
        k1Judgments: judgments,
        k1Need: need,
        k1Escalated: escalated,
        k1EscalateRate: judgments > 0 ? escalated / judgments : 0,
        k1RuleShare: 0,
        selfHeals: heals,
        pendingWounds: pending,
        cognitiveWounds: cognitive,
        medicines: 78,
        pitfalls: 40,
        coverage: 1.0,
        dreams: 0,
        unrevisited: 0,
        computedAt: DateTime(2026, 9, 21, 23, 0),
      );

  test('有紅燈有遺憾的夢：結論卡入生命樹＋白話摘要', () {
    // 先種一條遺憾
    final store = LifeTreeStore.instance;
    final rid = store.addThoughtBranch(LifeTreeThoughtBranch(
      ledgerId: 1,
      thought: '當時想過先寫測試再動手，但時間壓力選了先衝',
      createdAt: DateTime(2026, 9, 20),
    ));
    expect(rid, greaterThan(0));

    final result = DreamService.instance.runDream(
      redFlags: ['未結案傷口 5 筆堆積——同工具反覆撞牆沒長出藥'],
      metrics: metrics(judgments: 20, need: 12, escalated: 3),
      regrets: store.unrevisitedBranches(),
      dreamers: ['semiwasabi'],
    );

    expect(result.conclusions, greaterThanOrEqualTo(3),
        reason: '紅燈 1 + K1 統計 1 + 遺憾 1');
    expect(result.summary.any((s) => s.contains('撞牆')), isTrue);
    expect(result.summary.any((s) => s.contains('守門員')), isTrue,
        reason: '20 次判斷 escalate 15% → 健康維持');

    // 夢境主幹真的有卡
    final dreams = store.recentDreams();
    expect(dreams.length, result.conclusions);
    expect(dreams.every((d) => d.branchType == 'agent_draft'), isTrue,
        reason: 'MVP 草稿卡——不冒充共識');
    expect(dreams.any((d) => d.decision == 'propose'), isTrue);
    expect(dreams.any((d) => d.decision == 'escalate_to_user'), isTrue);
    expect(dreams.first.dreamSessionId, result.sessionId);
  });

  test('無事可夢：安睡卡也要留痕（迴路活著的證明）', () {
    final result = DreamService.instance.runDream(
      redFlags: [],
      metrics: metrics(judgments: 3), // 不足 10 → 不出統計卡
      regrets: [],
    );
    expect(result.conclusions, 1);
    final dreams = LifeTreeStore.instance.recentDreams();
    expect(dreams.single.conclusion, contains('安睡'));
    expect(dreams.single.decision, 'maintain');
  });

  test('K1 escalate 率過高 → propose 卡（回饋閾值的線索）', () {
    DreamService.instance.runDream(
      redFlags: [],
      metrics: metrics(judgments: 12, escalated: 9), // 75% 過高
      regrets: [],
    );
    final dreams = LifeTreeStore.instance.recentDreams();
    expect(dreams.single.decision, 'propose');
    expect(dreams.single.conclusion, contains('重新訓練'));
  });

  test('夢境收尾：痊癒的舊傷口自動銷案＋結論卡說清楚 [Blue 2026-09-21 拍板]', () {
    final closed = <int>[];
    final result = DreamService.instance.runDream(
      redFlags: [],
      metrics: metrics(judgments: 3),
      regrets: [],
      pendingWounds: [
        const PendingWound(
          pitfallId: 38,
          toolName: 'compass_read',
          text: '【pending·傷口立案】compass_read 失敗：器官 agent.mind 不存在於羅盤',
        ),
      ],
      woundHealer: (w) {
        closed.add(w.pitfallId);
        return true; // agent.mind 現在存在 → 痊癒
      },
    );

    expect(closed, [38], reason: '傷口驗證器有被叫');
    expect(result.summary.any((s) => s.contains('銷案')), isTrue);
    final dreams = LifeTreeStore.instance.recentDreams();
    final healCard = dreams.firstWhere((d) =>
        d.conclusion.contains('痊癒') || d.conclusion.contains('銷案'));
    expect(healCard.sourceClues.first, contains('#38'));
    expect(healCard.decision, 'maintain');
  });

  test('夢境收尾：未痊癒的傷口只觀察、不銷案、不產結論卡', () {
    final result = DreamService.instance.runDream(
      redFlags: [],
      metrics: metrics(judgments: 3),
      regrets: [],
      pendingWounds: [
        const PendingWound(
          pitfallId: 99,
          toolName: 'run_terminal',
          text: '【pending·傷口立案】run_terminal 失敗：指令不在白名單內',
        ),
      ],
      woundHealer: (w) => false, // 還沒好
    );
    expect(result.summary.any((s) => s.contains('還沒好')), isTrue);
    // 不產銷案卡——只有安睡卡（無紅燈無遺憾無統計）
    final dreams = LifeTreeStore.instance.recentDreams();
    expect(dreams.where((d) => d.conclusion.contains('銷案')), isEmpty);
  });
}
