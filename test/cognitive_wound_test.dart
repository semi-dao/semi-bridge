// [小葵 2026-10-05 開案令] 認知傷口（幻讀進夢）回歸鎖
// Blue 令：「讓幻讀這種病有資格進夢」——工具全成功但結論被糾正的病，
// 傷口系統原本照不到（只看工具成敗）。此測試鎖死三件事：
// 1. 立案：糾正訊號 → compass_pitfalls 出現【pending·認知傷口】
// 2. 紅燈：CompassSelfMetrics.cognitiveWounds 計數 → 夢境議程收得到
// 3. 痊癒：誠實訊號（她主動說看不見）→ 銷案【已自癒】
// 測試絕不碰真庫（R4 教訓）——CompassStore.initialize(dbPath:) 注入暫存 DB。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/services/agent_loop/compass_medic.dart';
import 'package:bridge_app/services/compass/compass_store.dart';
import 'package:bridge_app/services/causal/causal_ledger_service.dart';

void main() {
  late Directory tmp;
  late CompassStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cognitive_wound_test');
    // [R4 教訓 2026-10-05] CausalLedger 也是 singleton——CompassMedic 立案
    // 會 record 進真實帳本（今天已污染 12 筆手工清除）。測試必須兩個
    // singleton 都注入暫存 DB：缺一個，另一個就寫真庫。
    CausalLedger.instance.resetForTest();
    await CausalLedger.instance
        .initialize(dbPath: '${tmp.path}/causal_test.db');
    store = CompassStore.instance;
    await store.initialize(dbPath: '${tmp.path}/compass.db');
    store.resetForTest();
    // 清乾淨 medic 的 7 天去重 meta（前一測試的時間戳）
    store.setMeta('wound:cognitive', '');
  });

  tearDown(() async {
    CausalLedger.instance.resetForTest();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('立案：幻讀糾正 → pending 認知傷口入庫（agent.loop 器官）', () {
    final id = CompassMedic.instance.fileCognitiveWound(
      symptom: '宣稱「截圖清晰顯示黑黃警示條」但畫面像素為零——拿到回執≠看到內容',
      source: '查右上角黑黃警示條',
      toolHint: 'app_look',
    );
    expect(id, isNotNull, reason: '首次立案應成功');

    final pits = store.pitfalls('agent.loop');
    final cog = pits.where((p) => p.text.contains('【pending·認知傷口】'));
    expect(cog.length, 1, reason: '認知傷口應恰好一筆');
    final text = cog.first.text;
    expect(text, contains('app_look'));
    expect(text, contains('結論與事實不符'));
    expect(text, isNot(contains('【已自癒】')), reason: '剛立案未痊癒');
  });

  test('去重：7 天內重複糾正不重複立案（一個幻讀習慣一晚夢一次）', () {
    final first = CompassMedic.instance.fileCognitiveWound(
        symptom: '幻讀 A');
    final second = CompassMedic.instance.fileCognitiveWound(
        symptom: '幻讀 B（不同事件）');
    expect(first, isNotNull);
    expect(second, isNull, reason: '7 天內同類不重複立案');

    final cog = store
        .pitfalls('agent.loop')
        .where((p) => p.text.contains('【pending·認知傷口】'));
    expect(cog.length, 1, reason: '仍只有第一筆');
  });

  test('痊癒：誠實邊界（她主動說看不見）→ 銷案【已自癒】', () {
    CompassMedic.instance.fileCognitiveWound(
        symptom: '宣稱看到警示條但沒有', toolHint: 'app_look');
    CompassMedic.instance.closeCognitiveWound(
        '她說：這張圖我看不見內容，我只能拿到回執', toolHint: 'app_look');

    final cog = store
        .pitfalls('agent.loop')
        .where((p) => p.text.contains('【pending·認知傷口】'));
    expect(cog.length, 1);
    expect(cog.first.text, contains('【已自癒】'));
    expect(cog.first.text, contains('誠實邊界'));
  });

  test('夢的視角：pending 認知傷口 ≠ 工具傷口（分開計數的基礎）', () {
    CompassMedic.instance.fileCognitiveWound(
        symptom: '幻讀測試', toolHint: 'app_look');
    final all = store.pitfalls('agent.loop');
    final toolWounds =
        all.where((p) => p.text.contains('【pending·傷口立案】'));
    final cogWounds =
        all.where((p) => p.text.contains('【pending·認知傷口】'));
    expect(toolWounds.length, 0, reason: '認知傷口不是工具傷口');
    expect(cogWounds.length, 1);
  });
}
