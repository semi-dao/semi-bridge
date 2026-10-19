// app_schedule_engine.dart
// [W1 2026-10-08 小葵·第二刀 UX] App 層級排程引擎
//
// 起源：ScheduleEngine 原本活在 CanvasV2Workspace 裡（2026-07-24 教練 Agent），
// canvasId 綁「當前開啟的畫布」——使用者沒開那張畫布，排程就沉默。
// 第二刀 UX（docs/SCHEDULE_UX_DESIGN_SECOND_CUT.md）把排程升級為專案公民：
// 排程是替使用者工作的獨立節奏，不依附於「人現在看哪張畫布」。
//
// 手術（W1）：引擎搬遷到 App 層級 singleton，canvasId = null 掃全庫。
// - 前景畫布（workspace 註冊的 canvasId）→ 路由到 workspace 的 _executeNode
//   （真相回寫節點 + onFired 行為全保留）
// - 非前景畫布 → headless 執行（WorkflowAdapterInjector 注入 App 服務，
//   與 TaskDispatcher 工作畫布同配方，零 UI 依賴）
//
// 與舊 ScheduleEngine 的關係：ScheduleEngine 保留純掃描/觸發邏輯（本檔不改），
// 本類別是它的 App 層宿主＋執行分派器。W2 將在此掛 schedule_runs 落盤＋產出歸位。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/project_door_store.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/services/bridge_action_executor.dart';
import 'package:bridge_app/services/agent_loop/agent_tool_registry.dart';
import 'package:bridge_app/services/brain_container/brain_container_service.dart';
import 'package:bridge_app/services/semicanvas/schedule_engine.dart';
import 'package:bridge_app/services/semicanvas/schedule_run_store.dart';
import 'package:bridge_app/services/semicanvas/workflow_adapter_injector.dart';
import 'package:bridge_app/services/semicanvas/workflow_executor.dart';

/// App 層級排程引擎 — singleton，App 啟動即活，掃全庫 schedule 節點。
///
/// 生命週期：BridgeDesktopScreen initState 呼叫 [start]，dispose 呼叫 [stop]。
/// 前景畫布 executor 由 CanvasV2Workspace 註冊/解註冊（[registerForeground]）。
class AppScheduleEngine {
  AppScheduleEngine._();
  static final AppScheduleEngine instance = AppScheduleEngine._();

  /// [T10② W5 2026-10-17] 排程觸發結果廣播——App 層監聽後彈 toast。
  /// ValueNotifier：不依賴 BuildContext，引擎層零 UI 依賴。
  /// payload: {'jobTitle': String, 'success': bool, 'summary': String?}
  static final ValueNotifier<Map<String, dynamic>?> lastRunDone =
      ValueNotifier<Map<String, dynamic>?>(null);

  EntityGraphService? _entityGraph;
  ScheduleEngine? _engine;

  /// 前景畫布 id → workspace 的節點執行器（真相回寫用）
  String? _foregroundCanvasId;
  NodeExecutor? _foregroundExecutor;
  void Function(String nodeId, String? output)? _onForegroundNodeResult;
  void Function(String nodeId, String nodeTitle, List<NodeExecutionResult>)?
      _onForegroundFired;

  /// 引擎正在觸發的畫布 id（_fire 分派期間有效；headless 時為 null）
  String? _currentFiringCanvasId;

  NodeExecutor? _headless;

  /// 目前是否運行中
  bool get isRunning => _engine?.isRunning ?? false;

  /// 前景畫布 id（workspace 註冊；null = 無前景畫布）
  String? get foregroundCanvasId => _foregroundCanvasId;

  /// 啟動引擎（冪等）。App 層（BridgeDesktopScreen initState）呼叫一次。
  void start() {
    if (_engine != null) return;
    _entityGraph = EntityGraphService.withSqliteCanvasStore(
      memoryStore: MemoryStore(),
      doorStore: ProjectDoorStore(),
      assetStore: DigitalAssetRegistryStore(),
    );
    _engine = ScheduleEngine(
      entityGraph: _entityGraph!,
      nodeExecutor: _dispatchExecute,
      canvasId: null, // null = 掃全庫（W1 核心改動）
      // [W1] 真相回寫轉發——前景觸發時交還 workspace 寫 params._lastOutput
      // （headless 觸發走 W2 schedule_runs 落盤，不留真空）。
      onNodeResult: (nodeId, output) {
        if (_engine?.firingCanvasId != null &&
            _engine?.firingCanvasId == _foregroundCanvasId) {
          _onForegroundNodeResult?.call(nodeId, output);
        }
      },
      onFired: _onFired,
    );
    _engine!.start();
    debugPrint('[AppScheduleEngine] 啟動（App 層級，掃全庫）');
  }

  /// 停止引擎
  void stop() {
    _engine?.dispose();
    _engine = null;
    debugPrint('[AppScheduleEngine] 停止');
  }

  // ─────────────────────────────────────────────────────────────
  // 前景畫布註冊（CanvasV2Workspace 生命週期）
  // ─────────────────────────────────────────────────────────────

  /// [W1] 前景畫布註冊 — CanvasV2Workspace initState 呼叫。
  ///
  /// 註冊後，該畫布的排程觸發路由到 workspace 的 _executeNode，
  /// 保留完整的真相回寫（params._lastOutput）與前景 onFired 行為。
  void registerForeground({
    required String canvasId,
    required NodeExecutor executor,
    void Function(String nodeId, String? output)? onNodeResult,
    void Function(String nodeId, String nodeTitle, List<NodeExecutionResult>)?
        onFired,
  }) {
    _foregroundCanvasId = canvasId;
    _foregroundExecutor = executor;
    _onForegroundNodeResult = onNodeResult;
    _onForegroundFired = onFired;
    // 註冊後立即重掃——引擎內部不清 _lastFiredMap，不會二次開槍
    _engine?.rescan();
    debugPrint('[AppScheduleEngine] 前景畫布註冊: $canvasId');
  }

  /// [W1] 前景畫布解註冊 — workspace dispose 時呼叫。
  /// 之後該畫布排程觸發改走 headless 執行（不留真空）。
  void unregisterForeground({String? canvasId}) {
    if (canvasId != null && canvasId != _foregroundCanvasId) return;
    debugPrint('[AppScheduleEngine] 前景畫布解註冊: $_foregroundCanvasId');
    _foregroundCanvasId = null;
    _foregroundExecutor = null;
    _onForegroundNodeResult = null;
    _onForegroundFired = null;
  }

  /// [W1] 前景畫布切換 — workspace didUpdateWidget 呼叫。
  /// 只換路由 id；新畫布的觸發若 executor 尚未註冊，走 headless。
  void updateForegroundCanvasId(String? newCanvasId) {
    if (_foregroundCanvasId == newCanvasId) return;
    _foregroundCanvasId = newCanvasId;
    _engine?.rescan();
    debugPrint('[AppScheduleEngine] 前景畫布 id 更新為 $newCanvasId');
  }

  /// 取得指定節點下次觸發時間（W3 排隊 UI 用）
  DateTime? getNextFireTime(String nodeId) =>
      _engine?.getNextFireTime(nodeId);

  // ─────────────────────────────────────────────────────────────
  // 執行分派：前景 → workspace；非前景 → headless
  // ─────────────────────────────────────────────────────────────

  /// [W4.5] ▶ 立即執行——轉發到引擎 fireNow（前景分派＋headless 退路照常）
  Future<void> fireNow(String nodeId, String nodeTitle, String canvasId) async {
    await _engine?.fireNow(nodeId, nodeTitle, canvasId);
  }

  /// [W1] 節點執行分派。
  Future<NodeExecutionResult> _dispatchExecute(
    String nodeId,
    WorkflowNodeType? nodeType,
    Map<String, dynamic> params,
    UpstreamData upstreamData,
  ) async {
    final firingCanvas = _currentFiringCanvasId;
    if (firingCanvas != null &&
        firingCanvas == _foregroundCanvasId &&
        _foregroundExecutor != null) {
      return _foregroundExecutor!(nodeId, nodeType, params, upstreamData);
    }
    return _headlessExecute(nodeId, nodeType, params, upstreamData);
  }

  /// [W1] headless 執行 — 與 TaskDispatcher 工作畫布同配方。
  ///
  /// 不做付費檢查點暫停（背景無 UI 可承載——與舊 ScheduleEngine._fire 的
  /// 自律原則一致：首個付費資產完成即停止本次觸發，成果保留）。
  Future<NodeExecutionResult> _headlessExecute(
    String nodeId,
    WorkflowNodeType? nodeType,
    Map<String, dynamic> params,
    UpstreamData upstreamData,
  ) async {
    _headless ??= _buildHeadlessExecutor();
    return _headless!(nodeId, nodeType, params, upstreamData);
  }

  NodeExecutor _buildHeadlessExecutor() {
    final adapters = WorkflowAdapterInjector.create(
      bridgeActionExecutor: BridgeActionExecutor(),
      agentToolRegistry: AgentToolRegistry.withDefaults(
        bridgeActionExecutor: BridgeActionExecutor(),
        brainContainerService: BrainContainerService.instance,
      ),
    );
    return adapters.createNodeExecutor();
  }

  // ─────────────────────────────────生命周期回調 ─────────────────────────────

  /// [W2] 失敗摘要——多節點失敗取第一個有訊息的（UI 一行放不下長錯誤堆疊）
  static String _errorSummary(List<NodeExecutionResult> failed) {
    for (final r in failed) {
      final msg = r.errorMessage?.trim();
      if (msg != null && msg.isNotEmpty) {
        return msg.length > 120 ? '${msg.substring(0, 120)}…（截斷，全訊息見 app log）' : msg;
      }
    }
    return '執行失敗（無錯誤訊息，見 log）';
  }

  /// [W1] onFired 統一處理 — TTS 自動播放上移到 App 層。
  ///
  /// [W2] 執行結果落盤——schedule_runs.jsonl（排隊卡「上次」行與 W4 歷史
  /// 時間線的資料源）。產出路徑如實記錄原位置（位置主權鐵則：不搬不移）。
  void _onFired(
      String nodeId, String nodeTitle, List<NodeExecutionResult> results) {
    final firedAt = DateTime.now();
    final canvasId = _engine?.firingCanvasId ?? '';

    // [W2] 落盤（async 不等待——紀錄不能阻塞引擎）
    final ok = results.isNotEmpty && results.every((r) => r.success);
    final failed = results.where((r) => !r.success).toList();
    final resolved = ScheduleOutputResolver.resolve([
      for (final r in results)
        NodeExecutionResultLite(
            nodeId: r.nodeId, success: r.success, output: r.output),
    ]);
    unawaited(ScheduleRunStore.instance.append(ScheduleRunRecord(
      jobId: nodeId,
      jobTitle: nodeTitle,
      canvasId: canvasId,
      firedAt: firedAt,
      success: ok,
      outputType: resolved.type,
      outputPaths: resolved.paths,
      summary: ok
          ? (resolved.summary != null
              ? '${resolved.summary} ${results.length} 節點'
              : '${results.length} 節點完成')
          : null,
      error: ok
          ? null
          : _errorSummary(failed),
    )));

    // [T10② W5] 廣播——App 層 toast（成功/失敗都報，誠實原則）
    lastRunDone.value = {
      'jobTitle': nodeTitle,
      'success': ok,
      'summary': ok
          ? (resolved.summary ?? '${results.length} 節點完成')
          : _errorSummary(failed),
      'firedAt': firedAt.toIso8601String(),
    };

    for (final r in results) {
      final out = r.output ?? '';
      if (out.contains('.aiff') || out.contains('.mp3') || out.contains('.wav')) {
        final m =
            RegExp(r'[\s]([^\s]+\.(?:aiff|mp3|wav|mp4|m4a))').firstMatch(out);
        final audioPath = m?.group(1);
        if (audioPath != null) {
          debugPrint('[AppScheduleEngine] 自動播放: $audioPath');
          Process.run('afplay', [audioPath]); // 不 await——播放不阻塞引擎
        }
        break;
      }
    }
    if (_currentFiringCanvasId != null &&
        _currentFiringCanvasId == _foregroundCanvasId) {
      _onForegroundFired?.call(nodeId, nodeTitle, results);
    }
  }
}
