// schedule_engine.dart
// SemiCanvas Phase 2c: 排程引擎
// 定時掃描畫布上的 schedule 節點，符合條件就觸發下游 DAG 執行
//
// 設計參考: Hermes cron scheduler（jobs.json + Timer.periodic + deliver）
// 差異: 排程定義從 JSON 升級為畫布上的視覺化節點
//
// P1: 前台模式（App 開著才跑）
// P2: 搬進 daemon（launchd 託管，24/7）

import 'dart:async';

import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/services/semicanvas/dag_engine.dart';
import 'package:bridge_app/services/semicanvas/workflow_executor.dart';
import 'package:flutter/foundation.dart';

/// 排程觸發回調 — 當排程節點觸發時呼叫
///
/// [nodeId] 觸發的排程節點 ID
/// [nodeTitle] 節點標題
/// [results] DAG 執行結果
typedef ScheduleFiredCallback = void Function(
  String nodeId,
  String nodeTitle,
  List<NodeExecutionResult> results,
);

/// 排程引擎 — 定時掃描畫布上的 schedule 節點，符合條件就觸發執行。
///
/// 使用方式：
/// 1. 注入 [EntityGraphService] 和 [NodeExecutor]
/// 2. 呼叫 [start] 啟動引擎
/// 3. 引擎每 60 秒掃描所有 schedule 節點
/// 4. 符合條件的節點 → 自動執行下游 DAG
/// 5. 呼叫 [stop] 停止引擎
///
/// 防重複觸發：每個節點記錄最後觸發時間，同分鐘不重複觸發。
class ScheduleEngine {
  final EntityGraphService entityGraph;
  final NodeExecutor nodeExecutor;

  /// 排程觸發時的回調（用於 UI 通知、log 等）
  final ScheduleFiredCallback? onFired;

  /// [小葵 2026-09-19 W0.5] 真相回寫——節點執行結果交還 UI 層寫回節點 entity。
  /// 沒有這條，排程執行完畫布上還顯示舊檔名（Single Source of Truth 破口，
  /// Blue 2026-09-19 驗收發現：10:42 跑完，節點還顯示昨天 19:37 的檔名）。
  final void Function(String nodeId, String? output)? onNodeResult;

  /// 掃描間隔（預設 60 秒）
  final Duration scanInterval;

  /// 是否只掃描指定畫布（null = 掃描所有畫布）
  /// 可透過 updateCanvasId() 更新（App 重啟恢復正確畫布 id 後同步）
  String? canvasId;

  Timer? _timer;
  bool _running = false;

  /// 每個節點最後觸發的 DateTime（防重複）
  final Map<String, DateTime> _lastFiredMap = {};

  /// 每個節點下次預計觸發的 DateTime（用於 UI 顯示）
  final Map<String, DateTime> _nextFireMap = {};

  ScheduleEngine({
    required this.entityGraph,
    required this.nodeExecutor,
    this.onFired,
    this.onNodeResult,
    this.scanInterval = const Duration(seconds: 60),
    this.canvasId,
  });

  /// 引擎是否正在運行
  bool get isRunning => _running;

  /// 更新掃描的畫布 id（null = 掃全庫），更新後立即重掃一次
  /// 供 workspace 在 didUpdateWidget 恢復正確畫布 id 後同步引擎
  void updateCanvasId(String? newCanvasId) {
    if (canvasId == newCanvasId) return;
    canvasId = newCanvasId;
    debugPrint('[ScheduleEngine] canvasId 更新為 $newCanvasId，立即重掃');
    // 注意：不清 _lastFiredMap——保留同分鐘防重觸發，切畫布不會二次開槍
    _scanAndFire();
  }

  /// [W1 2026-10-08 小葵] 手動重掃 — App 層宿主（AppScheduleEngine）在
  /// 前景畫布註冊/切換後呼叫，立即恢復正確的執行路由。
  /// 不清 _lastFiredMap（同 updateCanvasId 慣例，不會二次開槍）。
  void rescan() => _scanAndFire();

  /// [W1] 引擎當下正在觸發的畫布 id（_fire 期間有效；掃描間隙為 null）。
  /// AppScheduleEngine 用它分派節點執行：== 前景畫布 → workspace executor。
  String? get firingCanvasId => _firingCanvasId;
  String? _firingCanvasId;

  /// 取得指定節點下次預計觸發時間（給 UI 顯示用）
  DateTime? getNextFireTime(String nodeId) => _nextFireMap[nodeId];

  /// [W3 2026-10-08] 靜態版下次觸發計算——UI（排隊卡）不持引擎實例也能算。
  /// 與實例方法 calculateNextFire 同邏輯（純函數，無狀態）。
  static DateTime? calcNextFirePublic(
          Map<String, dynamic> params, DateTime now) =>
      _calcNextFire(params, now);

  /// 啟動排程引擎
  void start() {
    if (_running) return;
    _running = true;
    debugPrint('[ScheduleEngine] 引擎啟動，掃描間隔 ${scanInterval.inSeconds}s');

    // 立即掃描一次
    _scanAndFire();

    // 啟動定期 Timer
    _timer = Timer.periodic(scanInterval, (_) => _scanAndFire());
  }

  /// 停止排程引擎
  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    debugPrint('[ScheduleEngine] 引擎停止');
  }

  /// 釋放資源
  void dispose() {
    stop();
    _lastFiredMap.clear();
    _nextFireMap.clear();
  }

  /// 主掃描迴圈 — 每次 tick 執行
  Future<void> _scanAndFire() async {
    try {
      final entries = await entityGraph.getCanvasNodes(canvasId: canvasId);
      final now = DateTime.now();

      for (final entry in entries) {
        final props = entry.props;
        if (props.nodeType != WorkflowNodeType.schedule) continue;

        final nodeId = entry.entity.id;
        final params = props.params;

        // 計算下次觸發時間（給 UI 用）
        final next = calculateNextFire(params, now);
        if (next != null) {
          _nextFireMap[nodeId] = next;
        }

        // 檢查是否該觸發
        if (!shouldFire(params, now, nodeId)) continue;

        // 防重複：同分鐘不重複觸發
        final lastFired = _lastFiredMap[nodeId];
        if (lastFired != null) {
          if (_isSameMinute(lastFired, now)) continue;
        }

        // 觸發！
        _lastFiredMap[nodeId] = now;
        debugPrint(
            '[ScheduleEngine] 觸發排程: ${entry.entity.title} ($nodeId) at $now');

        // [W1] 觸發期間回填該節點所屬畫布——宿主以此分派執行路徑，
        // _fire 內的 DagEngine 也用同值（絕不 null——超級 DAG 是
        // 2026-08-26 28 幽靈圖事件根因，DagEngine 註釋明載）。
        final nodeCanvasId = props.canvasId ?? canvasId;
        if (nodeCanvasId == null) {
          debugPrint('[ScheduleEngine] 節點 $nodeId 無所屬畫布——跳過（'
              '排程節點必須活在某張畫布上）');
          continue;
        }
        _firingCanvasId = nodeCanvasId;
        await _fire(nodeId, entry.entity.title, canvasId: nodeCanvasId);
        _firingCanvasId = null;
      }
    } catch (e, stack) {
      debugPrint('[ScheduleEngine] 掃描錯誤: $e\n$stack');
    }
  }

  /// 判斷排程節點是否應該在 [now] 觸發
  @visibleForTesting
  bool shouldFire(Map<String, dynamic> params, DateTime now, String nodeId) {
    final scheduleType = params['scheduleType']?.toString() ?? 'daily';
    final timeStr = params['time']?.toString() ?? '09:00';

    // 解析時間（HH:MM）
    final timeParts = timeStr.split(':');
    if (timeParts.length != 2) return false;
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    if (hour == null || minute == null) return false;

    switch (scheduleType) {
      case 'daily':
        // 每天 hour:minute 觸發
        return now.hour == hour && now.minute == minute;

      case 'weekly':
        final weekday = params['weekday'] as int? ?? 1;
        // DateTime.weekday: 1=Monday..7=Sunday（跟 params 一致）
        return now.weekday == weekday &&
            now.hour == hour &&
            now.minute == minute;

      case 'monthly':
        final dayOfMonth = params['dayOfMonth'] as int? ?? 1;
        return now.day == dayOfMonth &&
            now.hour == hour &&
            now.minute == minute;

      case 'once':
        final dateStr = params['date']?.toString() ?? '';
        if (dateStr.isEmpty) return false;
        // 格式: YYYY-MM-DD
        final dateParts = dateStr.split('-');
        if (dateParts.length != 3) return false;
        final year = int.tryParse(dateParts[0]);
        final month = int.tryParse(dateParts[1]);
        final day = int.tryParse(dateParts[2]);
        if (year == null || month == null || day == null) return false;

        return now.year == year &&
            now.month == month &&
            now.day == day &&
            now.hour == hour &&
            now.minute == minute;

      case 'cron':
        // 自訂 cron 語法（P2 擴充）
        final cronExpr = params['cronExpr']?.toString() ?? '';
        if (cronExpr.isEmpty) return false;
        return matchCron(cronExpr, now);

      default:
        return false;
    }
  }

  /// 計算下次觸發時間（給 UI 顯示用）
  @visibleForTesting
  DateTime? calculateNextFire(Map<String, dynamic> params, DateTime now) =>
      _calcNextFire(params, now);

  /// 純函數實作——實例方法與靜態公開版共用
  static DateTime? _calcNextFire(Map<String, dynamic> params, DateTime now) {
    final scheduleType = params['scheduleType']?.toString() ?? 'daily';
    final timeStr = params['time']?.toString() ?? '09:00';

    final timeParts = timeStr.split(':');
    if (timeParts.length != 2) return null;
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    if (hour == null || minute == null) return null;

    switch (scheduleType) {
      case 'daily':
        // 今天這個時間還沒到 → 今天；否則明天
        var target = DateTime(now.year, now.month, now.day, hour, minute);
        if (!target.isAfter(now)) {
          target = target.add(const Duration(days: 1));
        }
        return target;

      case 'weekly':
        final weekday = params['weekday'] as int? ?? 1;
        var target = DateTime(now.year, now.month, now.day, hour, minute);
        // 找到下一個符合 weekday 的日期
        int daysUntil = (weekday - now.weekday) % 7;
        if (daysUntil < 0) daysUntil += 7;
        if (daysUntil == 0 && !target.isAfter(now)) {
          daysUntil = 7;
        }
        return target.add(Duration(days: daysUntil));

      case 'monthly':
        final dayOfMonth = params['dayOfMonth'] as int? ?? 1;
        var target = DateTime(now.year, now.month, dayOfMonth, hour, minute);
        if (!target.isAfter(now)) {
          // 下個月
          var nextMonth = now.month + 1;
          var nextYear = now.year;
          if (nextMonth > 12) {
            nextMonth = 1;
            nextYear++;
          }
          target = DateTime(nextYear, nextMonth, dayOfMonth, hour, minute);
        }
        return target;

      case 'once':
        final dateStr = params['date']?.toString() ?? '';
        if (dateStr.isEmpty) return null;
        final dateParts = dateStr.split('-');
        if (dateParts.length != 3) return null;
        final year = int.tryParse(dateParts[0]);
        final month = int.tryParse(dateParts[1]);
        final day = int.tryParse(dateParts[2]);
        if (year == null || month == null || day == null) return null;
        return DateTime(year, month, day, hour, minute);

      default:
        return null;
    }
  }

  /// 觸發排程 — 執行該節點的下游 DAG
  ///
  /// [W1] canvasId 由 _scanAndFire 回填（節點所屬畫布）——掃全庫模式下
  /// 不能用 this.canvasId（null）建 DagEngine（超級 DAG 危險）。
  /// [W4.5 Blue 令 2026-10-09] 手動立即執行——▶ 鈕用。
  /// 走與排程觸發完全相同的 _fire 管線（DagEngine 限該畫布、自律保險絲、
  /// onFired 回呼）——唯一差別是不看 shouldFire。
  Future<void> fireNow(String nodeId, String nodeTitle, String canvasId) async {
    _lastFiredMap[nodeId] = DateTime.now();
    _firingCanvasId = canvasId;
    try {
      await _fire(nodeId, nodeTitle, canvasId: canvasId);
    } finally {
      _firingCanvasId = null;
    }
  }

  Future<void> _fire(String nodeId, String nodeTitle,
      {String? canvasId}) async {
    try {
      // [教練 Agent 2026-08-26 跨畫布洩漏修復] 排程也只跑自己畫布
      final dagEngine = DagEngine(entityGraph: entityGraph, canvasId: canvasId);
      final executor = WorkflowExecutor(
        entityGraph: entityGraph,
        dagEngine: dagEngine,
        nodeExecutor: nodeExecutor,
        canvasId: canvasId,
        // [教練 Agent 2026-08-21] 自律——排程是無人值守，更要保守：
        // 首個付費資產完成即停止本次觸發（不彈窗——背景環境無 UI 可承載；
        // 成果保留，下次觸發前使用者會在畫布看到）。
        // 保險絲（PaidActionGate）仍然是最後一道牆。
        onFirstPaidCheckpoint: (reason, _, __, ___) async {
          debugPrint(
              '[ScheduleEngine] 首個付費資產($reason)已產出——自律停止本次觸發，成果保留');
          return false;
        },
      );

      final results = await executor.execute(
        onProgress: (id, state, output, {imageData, imageUrl, extraParams}) {
          debugPrint('[ScheduleEngine] 節點 $id → ${state.name}'
              '${output != null ? ': $output' : ''}');
          // [小葵 2026-09-19 W0.5] 真相回寫——執行結果不能只進 log，要進節點
          if (output != null && output.isNotEmpty) {
            onNodeResult?.call(id, output);
          }
        },
      );

      debugPrint('[ScheduleEngine] DAG 完成: ${results.length} 個節點執行完畢');

      // 通知外部
      onFired?.call(nodeId, nodeTitle, results);
    } catch (e, stack) {
      debugPrint('[ScheduleEngine] 觸發失敗 ($nodeId): $e\n$stack');
    }
  }

  /// 比較兩個 DateTime 是否在同一分鐘
  bool _isSameMinute(DateTime a, DateTime b) {
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day &&
        a.hour == b.hour &&
        a.minute == b.minute;
  }

  /// 簡易 cron 語法比對（P2 擴充用）
  ///
  /// 支援格式: `分 時 日 月 週`
  /// 每個欄位可以是: `*` | 數字 | `*/N` | `A-B` | `A,B,C`
  @visibleForTesting
  bool matchCron(String expr, DateTime now) {
    final parts = expr.trim().split(RegExp(r'\s+'));
    if (parts.length != 5) return false;

    if (!_matchCronField(parts[0], now.minute, 0, 59)) return false;
    if (!_matchCronField(parts[1], now.hour, 0, 23)) return false;
    if (!_matchCronField(parts[2], now.day, 1, 31)) return false;
    if (!_matchCronField(parts[3], now.month, 1, 12)) return false;
    // cron 週: 0=Sunday..6=Saturday; DateTime.weekday: 1=Monday..7=Sunday
    final cronWeekday = now.weekday == 7 ? 0 : now.weekday;
    if (!_matchCronField(parts[4], cronWeekday, 0, 7)) return false;

    return true;
  }

  /// 比對 cron 單一欄位
  bool _matchCronField(String field, int value, int min, int max) {
    // 萬用字元
    if (field == '*') return true;

    // 列表 (A,B,C)
    if (field.contains(',')) {
      for (final part in field.split(',')) {
        if (_matchCronField(part, value, min, max)) return true;
      }
      return false;
    }

    // 步進 (*/N)
    if (field.startsWith('*/')) {
      final step = int.tryParse(field.substring(2));
      if (step == null || step == 0) return false;
      return (value - min) % step == 0;
    }

    // 範圍 (A-B)
    if (field.contains('-')) {
      final range = field.split('-');
      if (range.length != 2) return false;
      final start = int.tryParse(range[0]);
      final end = int.tryParse(range[1]);
      if (start == null || end == null) return false;
      return value >= start && value <= end;
    }

    // 單一數字
    final num = int.tryParse(field);
    if (num == null) return false;
    return value == num;
  }
}
