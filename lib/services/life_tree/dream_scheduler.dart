// dream_scheduler.dart
// [小葵 2026-09-22 Blue 規格] 夢境自動排程——掛在冷門時段。
//
// CompassHeartbeat 每分鐘 tick；本排程器在其內檢查：
// - 冷門時段（02:00-05:00 本地）且今天還沒做過淺眠夢 → 跑夢
// - 夢的種類由 DreamRhythm.planTonight 決定（呼吸感節律）
// - 淺眠夢（規則版）天天跑（0 成本對帳）；深夢/詩夢按節律
//
// 冷門時段=動態（Blue 2026-09-20 設計「不固定 23:00」）——
// v1 取 02:00-05:00 窗口，未來可依使用數據調整。

import 'package:flutter/foundation.dart';

import '../agent_loop/agent_loop_tools/dream_once_tool.dart';
import 'dream_service.dart';
import '../compass/compass_self_gauge.dart';
import 'dream_rhythm.dart';
import 'life_tree_store.dart';

class DreamScheduler {
  DreamScheduler._();
  static final DreamScheduler instance = DreamScheduler._();

  String? _lastShallowNight; // 最近一次淺眠夢的日期（yyyy-mm-dd）
  bool _inFlight = false; // [2026-10-05 雙 tick 修復] 重入鎖

  /// 每分鐘被 heartbeat 呼叫；只在冷門窗口行動
  Future<void> tick() async {
    // [小葵 2026-10-05] 02:00 實測：兩場夢同毫秒寫入（session 6773/6780
    // 差 7ms）——上游 heartbeat/probe 註冊疑似重複（app.dart initState
    // 可能重入）。夢一晚一場是規格：這裡加鎖治本，上游幾隻手都一樣。
    if (_inFlight) return;
    _inFlight = true;
    try {
      final now = DateTime.now();
      // 冷門窗口 02:00–05:00
      if (now.hour < 2 || now.hour >= 5) return;

      final today = _dayKey(now);
      if (_lastShallowNight == today) return; // 今晚已做過

      // 標記先佔（防重入；失敗明晚再試）
      _lastShallowNight = today;

      // ── 淺眠夢（規則版，天天跑）──
      final gauge = CompassSelfGauge.instance;
      final metrics = gauge.compute();
      final regrets = LifeTreeStore.instance.unrevisitedBranches(limit: 10);
      final result = DreamService.instance.runDream(
        redFlags: metrics.redFlags(),
        metrics: metrics,
        regrets: regrets,
        pendingWounds: const [],
        dreamers: const ['semiwasabi'],
      );
      debugPrint('[DreamScheduler] 淺眠夢完成（${result.sessionId}，'
          '${result.conclusions} 卡）');

      // ── 節律決定是否深夢/詩夢 ──
      final newWounds = metrics.pendingWounds;
      final plan = await DreamRhythm.instance.planTonight(
        newWounds: newWounds,
        unvisitedRegrets: regrets.length,
        hadPositiveEvents: result.conclusions > 0,
      );
      switch (plan) {
        case 'deep':
          // 深夢由 dream_once 工具完整邏輯跑（含向量選材+LLM）
          final tool = DreamOnceTool();
          await tool.execute(const {'deep': true});
          DreamRhythm.instance.deepDreamDone();
          debugPrint('[DreamScheduler] 深夢（REM）完成');
          break;
        case 'poem':
          final poem = await DreamRhythm.instance.writePoemDream();
          debugPrint('[DreamScheduler] 詩夢：${poem ?? "（無素材）"}');
          break;
        default:
          debugPrint('[DreamScheduler] 平靜夜——只淺眠，安睡');
      }
    } catch (e) {
      debugPrint('[DreamScheduler] tick 失敗（fail-open）: $e');
    } finally {
      _inFlight = false;
    }
  }

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
