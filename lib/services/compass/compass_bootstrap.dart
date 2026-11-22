// compass_bootstrap.dart
// 羅盤系統啟動接線 — App 啟動時初始化 store + 種子 + 規則快取掛載。
//
// 掛載點：app.dart 初始化鏈（冪等，可重複呼叫）。
// 設計：fail-open——羅盤掛掉不擋 App（渲染端有 fallback 種子值）。

import 'dart:async';

import 'compass_rule_cache.dart';
import 'compass_seed.dart';
import 'compass_harvest.dart';
import 'compass_store.dart';
import 'decision_card_store.dart';
import 'proactive_session_gc.dart';
import '../agent_loop/agent_loop_tools/compass_seek_agent_tool.dart'
    show ensureIntentIndexSeeded;

class CompassBootstrap {
  CompassBootstrap._();
  static final CompassBootstrap instance = CompassBootstrap._();

  bool _done = false;

  Future<void> ensureInitialized() async {
    if (_done) return;
    try {
      final store = CompassStore.instance;
      await store.initialize();
      seedCompass(store);
      migrateRetired2D(store); // [2026-09-07] 2D 圖譜退役遷移（冪等）
      // [小葵 2026-09-17 W1] intent_index 啟動即 seed——
      // 解死鎖：種子不再等 compass_seek 首次呼叫（agent 從不呼叫，
      // causal_ledger 353 筆 0 次實證）。load() 冪等。
      try {
        ensureIntentIndexSeeded(store);
      } catch (_) {} // fail-open：種子失敗不擋啟動
      // [2026-09-07 三步長肉 Step1] 事實層掃描（fail-open：掃不到不擋啟動）
      try {
        harvestFacts(store);
      } catch (_) {}
      CompassRuleCache.instance.attach(store);
      // [小葵 2026-11-03 待決策卡閉環] DecisionCardStore 同顆 db——
      // 羅盤體系真相源單一（fail-open：開不了不擋啟動）。
      try {
        await DecisionCardStore.instance.initialize();
      } catch (_) {}
      _done = true;
      // [Blue 令 2026-11-03 晚場] 主動回應對話 GC——
      // 重複留新刪舊＋結案清場＋空殼清理（全走軟刪除，回收桶可救）。
      // fire-and-forget：不擋啟動。
      unawaited(ProactiveSessionGc.instance.runOnce());
    } catch (e) {
      // fail-open：羅盤初始化失敗不擋 App；渲染端用 fallback 種子值
      // （誠實鐵則：不吞——寫 stderr 供診斷）
      // ignore: avoid_print
      print('[Compass] 初始化失敗（fail-open，App 照常運作）: $e');
    }
  }
}
