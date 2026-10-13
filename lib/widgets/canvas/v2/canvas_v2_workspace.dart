// canvas_v2_workspace.dart
// v2 畫布整合層 — 把新的 GraphCanvas 接到桌面主畫面。
// 建立日期: 2026-07-15
//
// 設計: 保留 OpenCanvasWorkspace 的對外 API，內部改用 CanvasController + GraphCanvas。
// 舊的 workspace 改名為 legacy，保留為 fallback。

import 'package:bridge_app/services/agent_loop/mcp_canvas_tools.dart'; // [v212] McpCanvasExecutor
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cross_file/cross_file.dart'; // [教練 Agent 2026-08-16] XFile — Finder 拖放
import 'dart:typed_data'; // [教練 Agent 2026-08-01] Uint8List for image data
import 'dart:ui' as ui;
import 'package:dio/dio.dart'; // [教練 Agent 2026-08-01] Vision/CharacterLock 下載圖片用
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'; // [教練 Agent 2026-07-22] LogicalKeyboardKey
import '../canvas_chat_panel.dart'; // [教練 Agent 2026-07-19] 人機共視對話框
import 'package:flutter/rendering.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bridge_app/models/canvas/canvas_metadata.dart';
import 'package:bridge_app/models/flow_step.dart';
import 'package:bridge_app/services/canvas_store.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/project_door_store.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/services/semicanvas/canvas_tts_service.dart'; // [教練 Agent 2026-07-22] Phase G TTS
import 'package:bridge_app/services/semicanvas/canvas_sub_workflow_runner.dart'; // [教練 Agent 2026-07-22] Phase G SubWorkflow
import 'package:bridge_app/services/semicanvas/dag_engine.dart';
import 'package:bridge_app/services/semicanvas/workflow_executor.dart';
import 'package:bridge_app/services/capability/service_registry.dart'; // [教練 Agent 2026-08-01] 能力中心
import 'package:bridge_app/services/capability/capability_executor.dart'; // [教練 Agent 2026-08-01] 能力執行器
import 'package:bridge_app/services/capability/capability_models.dart';
import 'package:bridge_app/services/semicanvas/app_schedule_engine.dart';
import 'package:bridge_app/services/semicanvas/schedule_sync_service.dart';
import 'package:bridge_app/services/vault/canvas_event_bus.dart'; // [教練 Agent 2026-07-22] Phase A
import 'package:bridge_app/services/vault/canvas_snapshot_service.dart'; // [教練 Agent 2026-07-22] Phase B
import 'package:bridge_app/models/entity_graph/open_canvas_node.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/vault/vault_templates.dart'; // [教練 Agent 2026-07-22] Phase 5 WorkflowTemplate
import 'package:bridge_app/services/routines/routine_recorder.dart'; // [刀 5] 示範錄製
import 'package:bridge_app/services/vault/template_tutorial_service.dart'; // [教練 Agent 2026-07-22] Phase 5+ 互動式教學
import 'package:bridge_app/widgets/canvas/v2/workflow_static_analyzer.dart'; // [教練 Agent 2026-08-15 使用者 提案] 測試按鈕
import 'package:bridge_app/controllers/chat_controller.dart';
import 'package:bridge_app/widgets/canvas/canvas_doodle_layer.dart';
import 'package:bridge_app/services/api_service.dart';
import 'package:bridge_app/services/bridge_action_executor.dart';
import 'package:bridge_app/models/bridge_action.dart';
import 'package:go_router/go_router.dart'; // [教練 Agent 2026-07-23] 能力引導導航
import 'canvas_controller.dart';
import 'canvas_mcp_registry.dart';
import 'canvas_state.dart';
import 'graph_canvas.dart';
import 'node_search_box.dart';
import 'node_widget.dart';
import 'node_detail_panel.dart';
import 'node_connection.dart'; // [教練 Agent 2026-08-15 Phase 2.5-B] isPortTypeMatch
import 'template_picker_dialog.dart'; // [教練 Agent 2026-07-22] Phase 5 範本選擇
import 'package:bridge_app/services/conversation_store.dart'; // [教練 Agent 2026-07-23] 存檔建立對話
import 'package:bridge_app/models/conversation.dart'; // [教練 Agent 2026-07-23] 專案畫布對話
import 'package:bridge_app/services/companion_store.dart'; // [教練 Agent 2026-07-23] 取得 active companion
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';
import '../../../services/agent_loop/workflow_inspector.dart';
import 'canvas_responsive_helper.dart'; // [教練 Agent 2026-08-06] 響應式 helper
import 'package:bridge_app/services/vault/vault_service.dart'; // [教練 Agent 2026-08-16] knowledge 節點檢索

/// v2 畫布工作區 — 對外 API 與舊 OpenCanvasWorkspace 相容。
class CanvasV2Workspace extends StatefulWidget {
  final double chatWidth;
  final ValueChanged<double>? onChatWidthChanged;
  // [教練 Agent 2026-08-16 使用者 提案] 右側對話框折疊——收右邊
  final bool chatCollapsed;
  final VoidCallback? onChatCollapseToggle;
  final ValueChanged<List<String>>? onExecutePlan;
  final ValueChanged<dynamic>? onChatControllerReady;
  final bool agentObserving;
  final ValueChanged<dynamic>? onToolChanged;
  final ValueChanged<String?>? onCanvasChanged;
  /// [教練 Agent 2026-07-23] 存檔完成後通知外層刷新（傳入 canvasId + conversationId）
  final void Function(String canvasId, String? conversationId)? onSaved;
  final bool showToolbar;
  final ValueChanged<bool>? onDoodleVisibleChanged;
  final GlobalKey? selfCaptureKey;
  /// [教練 Agent 2026-07-23] 初始畫布 ID——每個專案用自己的 canvasId
  final String? initialCanvasId;
  /// [v212 小葵 2026-09-02] MCP 畫布執行器——下傳 CanvasChatPanel，
  /// 讓畫布對話的 Agent 拿到建節點/連線等主控工具。
  final McpCanvasExecutor? mcpCanvasExecutor;

  const CanvasV2Workspace({
    super.key,
    this.chatWidth = 340,
    this.onChatWidthChanged,
    this.chatCollapsed = false,
    this.onChatCollapseToggle,
    this.onExecutePlan,
    this.onChatControllerReady,
    this.agentObserving = true,
    this.onToolChanged,
    this.onCanvasChanged,
    this.onSaved,
    this.showToolbar = true,
    this.onDoodleVisibleChanged,
    this.selfCaptureKey,
    this.initialCanvasId,
    this.mcpCanvasExecutor,
  });

  @override
  State<CanvasV2Workspace> createState() => CanvasV2WorkspaceState();
}

class CanvasV2WorkspaceState extends State<CanvasV2Workspace> {
  late CanvasController _controller;

  /// [教練 Agent 2026-07-23] 暴露 controller 供外層 AnimatedBuilder 使用
  CanvasController get controller => _controller;
  EntityGraphService? _entityGraph;

  /// [W1 2026-10-08] 排程引擎已搬遷至 AppScheduleEngine（App 層級
  /// singleton，掃全庫）——見 initState 的 registerForeground。

  /// [教練 Agent 2026-07-24] 同步排程到 daemon，包含 DAG 定義
  void _syncWithCanvas() {
    final state = _controller.state;
    _scheduleSync?.sync(
      canvasNodes: state.nodes.map((k, v) => MapEntry(k, v)),
      canvasConnections: state.connections,
    );
  }

  /// [教練 Agent 2026-07-24] 排程同步服務 — 把 schedule 節點同步到 schedule_jobs.json
  ScheduleSyncService? _scheduleSync;
  Timer? _scheduleSyncTimer;

  bool _isLoading = true;
  String? _canvasId;

  /// 畫布 MCP Server — singleton，在 desktop screen 層級管理生命週期

  /// 截圖用 — RepaintBoundary
  final _repaintKey = GlobalKey();
  // [教練 Agent 2026-07-22] 鍵盤焦點——攔截 Delete 鍵刪除選中節點
  final _canvasFocusNode = FocusNode(debugLabel: 'canvas-keyboard');

  /// [教練 Agent 2026-07-22] 鍵盤事件處理
  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    // [教練 Agent 2026-07-23] Cmd+Z = undo, Cmd+Shift+Z = redo
    final isCmd = HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    if (isCmd && key == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        _controller.redo();
      } else {
        _controller.undo();
      }
      return;
    }

    // [教練 Agent 2026-07-25] 移除 Delete/Backspace 刪除節點功能
    // 原因：在文字框（節點輸入框、聊天框）打字時按 Delete 會誤刪選中節點
    // 節點上已有叉叉按鈕可以刪除，不需要鍵盤快捷鍵

    // Escape 取消選取
    if (key == LogicalKeyboardKey.escape) {
      _controller.clearSelection();
    }
  }

  /// 塗鴉層狀態
  final List<DoodleStroke> _doodleStrokes = [];
  final List<DoodleText> _doodleTexts = [];
  bool _doodleEnabled = false;
  bool _doodleVisible = true;
  DoodleMode _doodleMode = DoodleMode.draw;
  Color _doodleColor = BridgeDS.accentYellow;
  double _doodleWidth = 2.5;


  /// [教練 Agent 2026-07-23] 歡迎引導覆蓋層 — 使用者按「空白畫布」或開始教學後關閉
  /// [教練 Agent 2026-08-10] 改為 static：整個 App session 只顯示一次
  static bool _welcomeShownThisSession = false;
  bool _guideDismissed = false;
  bool _routineRecording = false; // [刀 5] 示範錄製中旗標（浮動小條顯示用）

  /// [教練 Agent 2026-08-15 使用者回饋] Inspector 詳情面板開關——
  /// 預設關閉，雙擊節點才開啟（單擊選取不再意外觸發幽靈面板）。
  bool _inspectorEnabled = false;

  /// [教練 Agent 2026-08-15 使用者 提案] 測試按鈕用——對話框 controller
  /// （onControllerReady 存入，_runStaticTest 注入測試報告）
  ChatController? _chatController;

  /// [教練 Agent 2026-07-23] 聊天框高亮動畫 — Agent 發話時亮一下
  final ValueNotifier<bool> _chatHighlight = ValueNotifier<bool>(false);

  /// 存檔/執行狀態
  bool _isSaving = false;
  bool _isExecuting = false;

  @override
  void initState() {
    super.initState();
    // EntityGraphService 需要依賴注入
    try {
      _entityGraph = EntityGraphService.withSqliteCanvasStore(
        memoryStore: MemoryStore(),
        doorStore: ProjectDoorStore(),
        assetStore: DigitalAssetRegistryStore(),
      );
    } catch (e) {
      debugPrint('CanvasV2: EntityGraphService 初始化失敗: $e');
    }
    _controller = CanvasController(
      entityGraph: _entityGraph,
      canvasId: widget.initialCanvasId ?? 'default',
    );
    // [W1 2026-10-08 小葵·引擎搬遷] 排程引擎升級 App 層級（AppScheduleEngine
    // singleton，掃全庫）——workspace 不再自建引擎，退位為「前景畫布註冊」：
    // 註冊自己的 _executeNode（真相回寫 params._lastOutput 保留）。
    // afplay 自動播放已上移到 AppScheduleEngine（前景/背景都播），此處不重複。
    if (_entityGraph != null) {
      AppScheduleEngine.instance.registerForeground(
        canvasId: widget.initialCanvasId ?? 'default',
        executor: _executeNode,
        // [小葵 2026-09-19 W0.5] 真相回寫——排程執行結果寫回節點 params._lastOutput
        onNodeResult: (nodeId, output) {
          final node = _controller.state.nodes[nodeId];
          if (node == null) return;
          final props = node.entity.canvasProps;
          if (props == null) return;
          final updated = Map<String, dynamic>.from(props.params);
          updated['_lastOutput'] = output;
          _controller.updateNodeParams(nodeId, props.nodeType, updated);
        },
      );
      // [教練 Agent 2026-07-24] 排程同步服務 — 把 schedule 節點同步給 daemon
      _scheduleSync = ScheduleSyncService(entityGraph: _entityGraph!);
      _syncWithCanvas(); // 初次同步
      // 每 30 秒定時同步（兜底，確保 daemon 拿到最新排程）
      _scheduleSyncTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _syncWithCanvas(),
      );
    }
    // [教練 Agent 2026-07-23] 如果已有 initialCanvasId（非 default），表示不是首次空白畫布，跳過歡迎覆蓋層
    if (widget.initialCanvasId != null && widget.initialCanvasId != 'default') {
      _guideDismissed = true;
    }
    // [教練 Agent 2026-08-10] 整個 App session 只顯示一次歡迎彈窗
    if (_welcomeShownThisSession) {
      _guideDismissed = true;
    }
    _loadCanvas();
    _startMcpServer();
    _checkFirstVisit(); // [教練 Agent 2026-07-22] Phase 5+ 首次進入觸發教學
  }

  /// [v199c 畫布失蹤根因] App 啟動順序：workspace（Offstage 保活）在
  /// _loadCanvases 恢復 _activeCanvasId 之前就 initState（吃 null→'default'）。
  /// initialCanvasId 之後才變成正確 id——但 workspace 只在 initState 讀一次！
  /// 修：initialCanvasId 變更時自動切換載入（didUpdateWidget）。
  @override
  void didUpdateWidget(covariant CanvasV2Workspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCanvasId != null &&
        widget.initialCanvasId != oldWidget.initialCanvasId &&
        widget.initialCanvasId != _canvasId) {
      debugPrint('[v199c] initialCanvasId 變更 → 重載: ${widget.initialCanvasId}');
      loadCanvasById(widget.initialCanvasId!);
      // [小橋 2026-09-18] 排程引擎同步跟隨畫布切換（修 canvasId 錯定 bug）
      // [W1 2026-10-08] 改向 AppScheduleEngine 更新前景畫布路由
      AppScheduleEngine.instance
          .updateForegroundCanvasId(widget.initialCanvasId);
    }
  }

  // 塗鴉層 viewport 同步：由 CanvasDoodleLayer 內部 AnimatedBuilder 處理，
  // 不在 workspace 層用 listener（避免 build 過程中 setState 造成崩潰）

  /// [教練 Agent 2026-07-22] Phase 5+
  /// 檢查是否為首次進入畫布，若是則觸發互動式教學。
  Future<void> _checkFirstVisit() async {
    // 延遲 2 秒讓畫布完全載入後再觸發
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    // [小葵 2026-09-15 Blue 令] 教學只留給真新手——
    // 1) 先讀回持久化完成標記（重啟不失憶）
    // 2) 畫布已有節點 = 老手（自己建過東西的人不需要被教），
    //    靜默離開。教學只從明確入口（按鈕/選單）啟動。
    // 病例：Blue 排咖啡提醒任務切到畫布，等到的卻是
    // 「哈囉！歡迎來到畫布工作區」＋兩次「歡迎回來」——
    // 任務上下文被教學廢話淹沒，被迫在兩頁間反覆切換。
    await TemplateTutorialService.instance.loadCompletedFlag();
    if (mounted &&
        _controller.state.nodes.isNotEmpty &&
        !TemplateTutorialService.instance.hasCompletedTutorial) {
      // 有節點但沒完成過教學：標記完成（用行為證明的老手），
      // 從此不再打擾。想學的人隨時能從入口按鈕重啟教學。
      TemplateTutorialService.instance.markCompleted();
      debugPrint('[小葵 09-15] 畫布已有節點＝老手，教學標記完成，靜默');
      return;
    }
    if (!TemplateTutorialService.instance.hasCompletedTutorial) {
      // [2026-08-27 Blue 抓包·二輪] 等節點載入穩定——
      // EntityGraph 非同步載入：2 秒時 nodes 可能還空，
      // 誤判「空畫布」→ 走 greeting（裝失憶）。
      // 輪詢至節點數穩定（連續兩次相同且非零，或 8 秒逾時）。
      var lastCount = _controller.state.nodes.length;
      var stable = lastCount > 0;
      for (var i = 0; i < 6 && !stable; i++) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        final c = _controller.state.nodes.length;
        if (c > 0 && c == lastCount) {
          stable = true;
        }
        lastCount = c;
      }
      if (!mounted) return;
      if (stable && lastCount > 0) {
        // [v215] 看自己在哪——綁定專案就唸專案名（不是教學用語）
        String? projectName;
        if (_canvasId != null) {
          try {
            final canvases = await CanvasStore.getAll();
            projectName = canvases
                .where((c) => c.id == _canvasId)
                .firstOrNull
                ?.title;
          } catch (_) {}
        }
        await TemplateTutorialService.instance.resumeTutorialFromCanvas(
          nodeCount: lastCount,
          snapshot: CanvasSnapshotService.instance.describeFullState(),
          projectName: (projectName != null && projectName.isNotEmpty)
              ? projectName
              : null,
        );
      } else {
        await _startInteractiveTutorial(isFirstVisit: true);
      }
    }
  }

  /// 將 controller 注入到 MCP registry，讓 Agent 能存取畫布
  void _startMcpServer() {
    final reg = CanvasMcpRegistry.instance;
    reg.controller = _controller;

    // [教練 Agent 2026-07-24] 注入畫布像素大小，給 CanvasSnapshot 用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reg.canvasPixelSize = context.size ?? const Size(1060, 772);
    });

    // 截圖 — RepaintBoundary → base64 PNG
    reg.onScreenshot = () async {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      debugPrint('[CanvasV2] screenshot: _repaintKey.currentContext=${_repaintKey.currentContext != null}, boundary=${boundary != null}');
      if (boundary == null) {
        debugPrint('[CanvasV2] screenshot: boundary is null — widget not rendered yet');
        throw Exception('Canvas not rendered (boundary is null)');
      }
      debugPrint('[CanvasV2] screenshot: boundary.size=${boundary.size}');
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        debugPrint('[CanvasV2] screenshot: byteData is null — encode failed');
        throw Exception('Failed to encode image (byteData is null)');
      }
      final pngBytes = byteData.buffer.asUint8List();
      debugPrint('[CanvasV2] screenshot: ${pngBytes.length} bytes PNG');
      if (pngBytes.isEmpty) {
        throw Exception('Screenshot encoded to 0 bytes');
      }
      return base64Encode(pngBytes);
    };

    // 塗鴉標注
    reg.onGetAnnotations = () {
      return getDoodleAnnotations();
    };

    // 執行工作流 — 接上 WorkflowExecutor
    reg.onExecute = () => _executeWorkflow();

    // [開光 P2 · 小葵 2026-09-26] app_tap——畫布工具列語意點擊。
    // 手的語意化：與 UI 按鈕同一條程式路徑，零座標模擬。
    reg.onTapButton = (button) {
      switch (button) {
        case 'save':
          _onSave();
          return {'success': true, 'button': '存檔'};
        case 'copy':
          _onSaveAs();
          return {'success': true, 'button': '另存'};
        case 'test':
          _runStaticTest();
          return {'success': true, 'button': '測試'};
        case 'run':
          _onSave();
          _executeWorkflow();
          return {'success': true, 'button': '執行'};
        default:
          return {'success': false, 'message': '未知按鈕: $button'};
      }
    };

    // [教練 Agent 2026-07-22] Phase C — Agent 快捷操作 callbacks
    reg.onLoadTemplate = (templateName) {
      _loadTemplateByName(templateName);
    };
    reg.onHighlightNode = (nodeId) {
      _controller.selectNode(nodeId);
      // TODO: 加閃爍動畫
    };
    reg.onPanToNode = (nodeId) {
      final node = _controller.state.nodes[nodeId];
      if (node != null) {
        _controller.panTo(node.position);
      }
    };
  }

  /// 執行畫布上的工作流
  /// 截圖 — 匯出當前畫布為 PNG
  Future<void> handleScreenshot() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('截圖失敗：畫布尚未就緒'), duration: Duration(seconds: 2)),
          );
        }
        return;
      }
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/canvas_screenshot_$timestamp.png');
      await file.writeAsBytes(pngBytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('截圖已儲存：${file.path}'),
            duration: const Duration(seconds: 3),
            backgroundColor: BridgeDSColors.of(context).accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('截圖失敗: $e'), backgroundColor: BridgeDSColors.of(context).accentRed),
        );
      }
    }
  }

  /// [教練 Agent 2026-08-15 使用者決策] 單節點執行——從右鍵選單「執行此節點」觸發。
  /// [小葵 2026-09-24 修 bug·需要上游圖] 舊碼傳空 UpstreamData——上游明明有圖
  /// （前輪執行的 _lastImageB64 還在）卻說「沒有上游圖」。修：從直接上游
  /// 節點的存檔 params 收集 _lastImageB64/_lastOutput/_lastImageUrl 組成
  /// UpstreamData——單跑一顆＝拿上游上次的結果當輸入，不必整條重跑。
  Future<void> _executeSingleNode(String nodeId) async {
    final node = _controller.state.nodes[nodeId];
    if (node == null) return;
    final props = node.entity.canvasProps;
    if (props?.nodeType == null) return;

    // 收集直接上游的上次執行結果
    final upstreamTexts = <String, String>{};
    final upstreamImagesB64 = <String, String>{};
    final upstreamImageUrls = <String, String>{};
    for (final conn in _controller.state.connections) {
      if (conn.toNodeId != nodeId) continue;
      final upNode = _controller.state.nodes[conn.fromNodeId];
      if (upNode == null) continue;
      final upProps = upNode.entity.canvasProps;
      if (upProps == null) continue;
      final b64 = upProps.params['_lastImageB64']?.toString();
      if (b64 != null && b64.isNotEmpty) {
        upstreamImagesB64[conn.fromNodeId] = b64;
      }
      final url = upProps.params['_lastImageUrl']?.toString();
      if (url != null && url.isNotEmpty) {
        upstreamImageUrls[conn.fromNodeId] = url;
      }
      final out = upProps.params['_lastOutput']?.toString();
      if (out != null && out.isNotEmpty) {
        upstreamTexts[conn.fromNodeId] = out;
      }
    }

    // [小葵 2026-09-24 Blue 令·單跑也要有回饋] 舊碼從頭到尾無聲——
    // 沒 active 光暈、沒「開始運算」推播、沒完成推播。
    // 修：執行前設 active（呼吸光暈＋節點顯示 ⚡）、對話框推播開始；
    // 結束設 done/blocked、推播結果（成功帶路徑、失敗帶 ❌ 原因）。
    final nodeTitle = node.entity.title.isNotEmpty
        ? node.entity.title
        : (props!.nodeType != null
            ? workflowNodeTypeLabel(props.nodeType!)
            : '節點');
    final liveProps = props!;
    await _entityGraph?.updateCanvasVisualState(
        nodeId, CanvasVisualState.active);
    _controller.updateNodeParams(nodeId, liveProps.nodeType,
        {...liveProps.params, '_lastOutput': '⚡ 運算中…'});
    _controller.onNodeResult?.call(nodeId, nodeTitle, '⚡ 開始運算…');

    final result = await _executeNode(
      nodeId,
      props!.nodeType,
      props.params,
      UpstreamData(
        texts: upstreamTexts,
        base64Images: upstreamImagesB64,
        imageUrls: upstreamImageUrls,
      ),
    );
    if (result.success) {
      final updatedParams = Map<String, dynamic>.from(props.params);
      updatedParams['_lastOutput'] = result.output;
      if (result.imageData != null) {
        updatedParams['_lastImageB64'] = base64.encode(result.imageData!);
      }
      if (result.imageUrl != null) {
        updatedParams['_lastImageUrl'] = result.imageUrl;
      }
      _controller.updateNodeParams(nodeId, props.nodeType, updatedParams);
      await _entityGraph?.updateCanvasVisualState(
          nodeId, CanvasVisualState.done);
      _controller.onNodeResult?.call(nodeId, nodeTitle,
          '✅ 執行完成：${result.output ?? '成功'}');
    } else if (result.errorMessage != null) {
      // [小葵 2026-09-24 Blue 令·失敗要顯示] 失敗結果也寫進節點 params
      // （_lastOutput 帶 ❌）——畫布上直接看到原因，不只靠 SnackBar。
      final updatedParams = Map<String, dynamic>.from(props.params);
      updatedParams['_lastOutput'] = '❌ ${result.errorMessage}';
      _controller.updateNodeParams(nodeId, props.nodeType, updatedParams);
      await _entityGraph?.updateCanvasVisualState(
          nodeId, CanvasVisualState.blocked);
      _controller.onNodeResult?.call(nodeId, nodeTitle,
          '❌ 執行失敗：${result.errorMessage}');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('執行失敗: ${result.errorMessage}'),
            backgroundColor: BridgeDSColors.of(context).accentRed,
          ),
        );
      }
    }
  }

  /// [教練 Agent 2026-08-15 使用者 提案] 測試——零 token 靜態分析，結果進對話框。
  /// 找斷流/孤兒/無出口/循環/懸空分支，使用者看報告調整後才按「執行」燒 token。
  void _runStaticTest() {
    final state = _controller.state;

    // 組 nodesData：nodeId -> {nodeType, params, label}
    final nodesData = <String, dynamic>{};
    for (final entry in state.nodes.entries) {
      final props = entry.value.entity.canvasProps;
      if (props?.nodeType == null) continue; // 標注/塗鴉跳過
      nodesData[entry.key] = {
        'nodeType': props!.nodeType!.name,
        'params': props.params,
        'label': props.params['label']?.toString() ?? entry.value.entity.title,
      };
    }

    final report = WorkflowStaticAnalyzer.analyze(
      nodesData: nodesData,
      connections: state.connections,
      // [教練 Agent 2026-08-15] 全部節點名單（含標注等非 workflow 節點）——
      // 殘留連線檢查才不會誤報
      allNodeIds: state.nodes.keys.toSet(),
    );

    // 注入對話框——讓 agent 跟使用者互動解讀（onControllerReady 存的 controller）
    // [教練 Agent 2026-08-15 修正] injectCanvasSystemMessage 是靜默注入（silent:true
    // UI 不顯示），測試報告要使用者看到 → 改用 injectAssistantMessage（會顯示）
    if (_chatController != null) {
      _chatController!.injectAssistantMessage(
        '🧪 ${WorkflowStaticAnalyzer.toAgentMessage(report)}',
        metadata: {'kind': 'workflow_test'},
      );
      _flashChatHighlight();
    } else {
      // 沒有對話框（罕見）——SnackBar 兜底
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(WorkflowStaticAnalyzer.toAgentMessage(report)),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// 存檔 — 將畫布節點存為 CanvasMetadata + FlowSteps
  /// [教練 Agent 2026-07-23] 存檔時彈出對話框讓使用者輸入專案名稱，
  /// 同時建立/更新 專案(ProjectDoor) + 畫布(CanvasMetadata) + 對話(Conversation)
  Future<void> _onSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      // 檢查現有畫布
      CanvasMetadata? canvas;
      if (_canvasId != null) {
        canvas = await CanvasStore.getById(_canvasId!);
      }

      // [教練 Agent 2026-07-24] 已有標題的畫布直接覆蓋存檔，不再問名字
      // 只有 default/空標題時才問
      String title = canvas?.title ?? '';
      if (title.isEmpty || title == '未命名畫布' || title == 'default') {
        var input = await _showProjectNameDialog(canvas?.title);
        if (input == null || input.isEmpty) {
          // 使用者取消
          if (mounted) setState(() => _isSaving = false);
          return;
        }
        // [2026-08-27 Blue 踩坑修復] 同名偵測——
        // 舊行為：取了既有專案名想覆蓋，卻另建同名新專案（列表出現雙胞胎）。
        // 新行為：同名已存在 → 確認覆蓋 → 直接綁到該 canvas 存（真覆蓋）。
        final existing = (await CanvasStore.getAll())
            .where((c) => c.title == input)
            .toList();
        if (existing.isNotEmpty) {
          final overwrite = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: BridgeDSColors.of(context).surfaceElevated,
              title: Text('覆蓋既有專案？',
                  style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
              content: Text(
                '已有同名專案「$input」。\n覆蓋＝更新它（建議）；\n另存＝保留兩份。',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('另存新份'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('覆蓋'),
                ),
              ],
            ),
          );
          if (overwrite == true) {
            canvas = existing.first;
            _canvasId = canvas.id;
            title = input;
          } else {
            // 另存——名字加序號避免再撞
            final allTitles = (await CanvasStore.getAll()).map((c) => c.title);
            var n = 2;
            var candidate = input;
            while (allTitles.contains(candidate)) {
              candidate = '$input ($n)';
              n++;
            }
            input = candidate;
            title = candidate;
          }
        } else {
          title = input;
        }
      }

      final nodes = _controller.state.nodes.values.toList();
      final flowSteps = nodes
          .map((node) => FlowStep.create(doorId: '', title: node.entity.title))
          .toList();

      // 建立或更新畫布
      canvas ??= CanvasMetadata.create(title: title);
      canvas = canvas.copyWith(
        title: title,
        updatedAt: DateTime.now(),
        doodleStrokes: _doodleStrokes.map((s) => s.toJson()).toList(),
        doodleTexts: _doodleTexts.map((t) => t.toJson()).toList(),
      );

      // [2026-08-27 Blue 踩坑修復] 沒綁定對話時——優先綁「目前對話框的對話」，
      // 不再無腦建立空新對話。舊行為：教學在未存檔畫布進行到一半 → 存檔 →
      // 建立全新空對話 → onSaved 強制切過去 → 教學對話瞬間清空，
      // 使用者當下不知所措。
      if (canvas.conversationId == null) {
        final currentConv = _chatController?.currentConversation;
        if (currentConv != null && currentConv.messages.isNotEmpty) {
          // 現有對話有內容——綁它，對話原地保留
          canvas = canvas.copyWith(conversationId: currentConv.id);
        } else {
          final companionId = CompanionStore().activeCompanion?.id;
          final conv = Conversation.createProjectCanvas(
            canvasId: '',
            title: title,
            companionId: companionId,
          );
          await ConversationStore.save(conv);
          canvas = canvas.copyWith(conversationId: conv.id);
        }
      }

      final saved = await CanvasStore.saveCanvasToProject(
        canvas: canvas,
        flowSteps: flowSteps,
      );
      _canvasId = saved.id;
      _controller.canvasId = saved.id;

      // [教練 Agent 2026-07-24] 修復：存檔後把所有節點的 canvasId 同步到新畫布 ID
      // 否則從空白畫布載入範本後存檔，EntityGraph 裡的節點 canvasId 仍是 'default'
      // 切頁再切回時 loadCanvasById 會找不到節點 → 畫布清空
      for (final node in _controller.state.nodes.values) {
        final oldProps = node.entity.canvasProps;
        if (oldProps != null && oldProps.canvasId != saved.id) {
          final newProps = oldProps.copyWith(canvasId: saved.id);
          await _entityGraph?.setCanvasProps(node.id, newProps);
        }
      }

      // 回填 canvasId 到對話
      if (saved.conversationId != null) {
        final conv = await ConversationStore.getById(saved.conversationId!);
        if (conv != null && (conv.canvasId == null || conv.canvasId!.isEmpty)) {
          await ConversationStore.save(conv.copyWith(canvasId: saved.id));
        }
      }

      // [教練 Agent 2026-07-23] 通知外層刷新 sidebar + 切換對話
      widget.onSaved?.call(saved.id, saved.conversationId);

      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('✅ 已存檔：$title'),
            duration: const Duration(seconds: 2),
            backgroundColor: BridgeDSColors.of(context).accentGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint('[CanvasV2] 存檔失敗: $e');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('存檔失敗: $e'),
            backgroundColor: BridgeDSColors.of(context).accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// [教練 Agent 2026-07-24] 另存新檔 — 建立新畫布，複製當前節點到新畫布
  Future<void> _onSaveAs() async {
    if (_isSaving) return;
    final input = await _showProjectNameDialog(null);
    if (input == null || input.isEmpty) return;
    
    setState(() => _isSaving = true);
    try {
      final title = input;
      final companionId = CompanionStore().activeCompanion?.id;
      final conv = Conversation.createProjectCanvas(
        canvasId: '',
        title: title,
        companionId: companionId,
      );
      await ConversationStore.save(conv);

      final newCanvas = CanvasMetadata.create(title: title).copyWith(
        conversationId: conv.id,
        doodleStrokes: _doodleStrokes.map((s) => s.toJson()).toList(),
        doodleTexts: _doodleTexts.map((t) => t.toJson()).toList(),
      );

      final nodes = _controller.state.nodes.values.toList();
      final flowSteps = nodes
          .map((node) => FlowStep.create(doorId: '', title: node.entity.title))
          .toList();

      final saved = await CanvasStore.saveCanvasToProject(
        canvas: newCanvas,
        flowSteps: flowSteps,
      );

      // 把當前節點複製到新 canvas
      for (final node in nodes) {
        final props = node.entity.canvasProps;
        if (props != null) {
          final newProps = CanvasProps(
            x: props.x,
            y: props.y,
            canvasId: saved.id,
            nodeType: props.nodeType,
            params: props.params,
            ports: props.ports,
            origin: props.origin,
          );
          await _entityGraph?.setCanvasProps(node.id, newProps);
        }
      }

      _canvasId = saved.id;
      _controller.canvasId = saved.id;
      widget.onSaved?.call(saved.id, saved.conversationId);

      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('✅ 已另存新檔：$title'),
            duration: const Duration(seconds: 2),
            backgroundColor: BridgeDSColors.of(context).accentGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint('[CanvasV2] 另存新檔失敗: $e');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('另存新檔失敗: $e'),
            backgroundColor: BridgeDSColors.of(context).accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// [教練 Agent 2026-07-23] 存檔時的專案名稱輸入對話框
  Future<String?> _showProjectNameDialog(String? currentName) {
    final controller = TextEditingController(text: currentName ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(context).surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
          side: BorderSide(color: BridgeDSColors.of(context).borderDefault),
        ),
        title: Text('存檔', style: TierStyle.of(context, Tier.bodyPrimary).toTextStyle()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('輸入專案名稱', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '例如：IG發文工作流',
                hintStyle: TextStyle(color: BridgeDSColors.of(context).textMuted),
                filled: true,
                fillColor: BridgeDSColors.of(context).surface,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
                  borderSide: BorderSide(color: BridgeDSColors.of(context).borderDefault),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
                  borderSide: BorderSide(color: BridgeDSColors.of(context).accentBlue, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (value) => Navigator.of(ctx).pop(value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text('取消', style: TextStyle(color: BridgeDSColors.of(context).textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: BridgeDSColors.of(context).canvas,
              side: BorderSide(color: BridgeDSColors.of(context).accentPurple, width: 1.5),
              foregroundColor: BridgeDSColors.of(context).textPrimary,
            ),
            child: const Text('存檔'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeWorkflow() async {
    if (_entityGraph == null) return;

    // [教練 Agent 2026-08-21] 自律——執行前體檢＋產出預報（$33 根治第三層）
    // 使用者親按執行也看得到「這會產出什麼」；嚴重警告先修再跑。
    // [小葵 2026-09-23 修 bug·體檢誤報] 邊清單改用 state.connections——
    // entity.relations 是「載入時的 DB 快照」，畫布上現拉的線（connect()）
    // 只寫 state.connections 不會同步回 entity.relations。舊邏輯讓
    // 16 條連線在體檢眼裡變 0 條 → 生成節點被誤判孤兒 → 體檢擋下
    // 明明接好的工作流（Blue 實測抓包：按執行 → 紅色警示未通過）。
    final edges = <String>[];
    for (final c in _controller.state.connections) {
      edges.add('${c.fromNodeId}>${c.toNodeId}');
    }
    final inspection = WorkflowInspector.inspect(
      nodes: _controller.state.nodes,
      edges: edges,
    );
    if (inspection.hasSevereWarnings) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 10),
            backgroundColor: BridgeDSColors.of(context).accentRed,
            content: Text(
              '工作流體檢未通過：\n${inspection.warnings.join('\n')}\n'
              '請先補上 prompt／接上下游／移除重複節點。',
            ),
          ),
        );
      }
      return; // 不執行爛工作流
    }
    if (inspection.hasPaid && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(inspection.briefing),
        ),
      );
    }

    // [教練 Agent 2026-08-26 跨畫布洩漏修復] 執行範圍鎖定本畫布——
    // 不帶 canvasId 會把 SharedPreferences 裡所有歷史畫布節點
    // （含舊專案 imageGen）混成一張超級 DAG 一起執行。
    // 2026-08-26 事件：28 張幽靈圖片燒光 OpenAI 額度。
    // [小葵 2026-09-24 修 bug·工作流空轉] DagEngine 注入畫布即時連線——
    // 與 executor/體檢同真相源（state.connections）。舊路徑讀
    // relationStore（存檔才寫），現拉的線它看不見 → 12 節點孤立空轉。
    final dagEngine = DagEngine(
      entityGraph: _entityGraph!,
      canvasId: _canvasId,
      liveEdges: [
        for (final c in _controller.state.connections) (c.fromNodeId, c.toNodeId),
      ],
    );
    final executor = WorkflowExecutor(
      entityGraph: _entityGraph!,
      dagEngine: dagEngine,
      nodeExecutor: _executeNode,
      canvasId: _canvasId,
      // [教練 Agent 2026-08-21] 自律——首張檢查點
      // 第一個付費資產生成後暫停：預覽給使用者看，確認才繼續。
      // $33 教訓：批量跑完才看見全廢——第一張就要停下來。
      onFirstPaidCheckpoint: (reason, imageData, imageUrl, pendingPaidCount) async {
        if (!mounted) return false;
        final kindLabel = reason == 'image'
            ? '圖片'
            : (reason == 'video' ? '影片' : '音樂');
        // [教練 Agent 2026-08-26 使用者回饋] 預覽修復——本地檔案路徑也要能預覽。
        // 舊版只認 bytes / http URL，圖存進 bridge_media（本地路徑）
        // 時落入「無法內嵌」分支，使用者根本沒看到圖就被問品質 OK。
        Widget? preview;
        if (imageData != null) {
          preview = Image.memory(imageData, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink());
        } else if (imageUrl != null && imageUrl.startsWith('http')) {
          preview = Image.network(imageUrl, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink());
        } else if (imageUrl != null && imageUrl.isNotEmpty) {
          // data URL 或本地檔案路徑
          if (imageUrl.startsWith('data:image')) {
            try {
              final b64 = imageUrl.split(',').last;
              preview = Image.memory(base64.decode(b64), fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink());
            } catch (_) {
              preview = null;
            }
          } else {
            final f = File(imageUrl.replaceAll('file://', ''));
            if (f.existsSync()) {
              preview = Image.file(f, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink());
            }
          }
        }
        final goOn = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: BridgeDSColors.of(ctx).surfaceElevated,
            // [教練 Agent 2026-08-26 使用者回饋] 緊湊排版——舊版字太大、留白太多
            insetPadding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 24),
            contentPadding:
                const EdgeInsets.fromLTRB(20, 16, 20, 12),
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
              side: BorderSide(color: BridgeDSColors.of(ctx).borderDefault),
            ),
            title: Text(
                pendingPaidCount > 1
                    ? '首個$kindLabel已生成——本輪共 $pendingPaidCount 個'
                    : '首個$kindLabel已生成——看過再繼續？',
                style: TierStyle.of(ctx, Tier.cardTitle).toTextStyle()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (preview != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: preview,
                    ),
                  )
                else
                  Text('$kindLabel已生成（無法內嵌預覽，請點節點查看）',
                      style: TierStyle.of(ctx, Tier.cardCaption)
                          .toTextStyle()),
                const SizedBox(height: 8),
                Text(
                  pendingPaidCount > 1
                      ? '繼續＝放行本輪全部 $pendingPaidCount 個付費生成（還會再生成 ${pendingPaidCount - 1} 個）；停止＝只花這一張的錢。'
                      : '第一個付費產出。品質 OK 才繼續；不符合就停，只花這一張的錢。',
                  style: TierStyle.of(ctx, Tier.cardCaption).toTextStyle(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('停止執行'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(pendingPaidCount > 1
                    ? '品質 OK，繼續（再生成 ${pendingPaidCount - 1} 個）'
                    : '品質 OK，繼續'),
              ),
            ],
          ),
        );
        return goOn ?? false;
      },
    );

    final progressCallback = (String nodeId, CanvasVisualState state, String? output, {Uint8List? imageData, String? imageUrl, Map<String, dynamic>? extraParams}) {
        // [教練 Agent 2026-08-01] 更新節點視覺狀態 + 執行結果（文字+圖片）
        final node = _controller.state.nodes[nodeId];
        if (node != null) {
          final props = node.entity.canvasProps;
          if (props != null) {
            final updatedParams = Map<String, dynamic>.from(props.params);
            // 把執行結果寫入 _lastOutput，讓 NodeWidget 顯示
            if (output != null) {
              updatedParams['_lastOutput'] = output;
            }
            // [教練 Agent 2026-08-25 F-1] 素材池候選寫回 params（採用 UI 讀取）
            if (extraParams != null) {
              updatedParams.addAll(extraParams);
            }
            // [教練 Agent 2026-08-01] 圖片結果
            if (imageData != null) {
              updatedParams['_lastImageB64'] = base64.encode(imageData);
            }
            if (imageUrl != null) {
              updatedParams['_lastImageUrl'] = imageUrl;
            }
            _controller.updateNodeParams(
              nodeId,
              props.nodeType,
              updatedParams,
            );

            // [小葵 2026-09-24 Blue 令·退役] 自動落地「成果節點」機制移除——
            // 節點本體現在自己顯示預覽縮圖（node_widget _lastImageB64），
            // 自動長出的 output 成果節點變成冗餘（Blue 令：不需要了）。
            // 落盤依舊（bridge_media_store）；要看大圖點節點本體即可。
            // 影片/音樂/語音成果若未來需要獨立資產節點，再依需求恢復。

            // [教練 Agent 2026-08-02] 節度執行完成時推送到畫布對話框
            if (state == CanvasVisualState.done && output != null && output.isNotEmpty) {
              final nodeTitle = node.entity.title.isNotEmpty
                  ? node.entity.title
                  : (props.nodeType != null
                      ? workflowNodeTypeLabel(props.nodeType!)
                      : '節點');
              _controller.onNodeResult?.call(nodeId, nodeTitle, output);
            }
            // [小葵 2026-09-24 Blue 令·失敗要顯示] blocked 也推播——
            // 節點失敗（API 錯/金鑰問題）不再無聲，對話框直接看到原因。
            if (state == CanvasVisualState.blocked && output != null && output.isNotEmpty) {
              final nodeTitle = node.entity.title.isNotEmpty
                  ? node.entity.title
                  : (props.nodeType != null
                      ? workflowNodeTypeLabel(props.nodeType!)
                      : '節點');
              _controller.onNodeResult?.call(nodeId, nodeTitle, output);
            }
            // [小葵 2026-09-24 Blue 令·運算中要顯示] active 推播一次
            // 「開始運算」——使用者按執行後不再對著靜止畫面乾等。
            if (state == CanvasVisualState.active) {
              final nodeTitle = node.entity.title.isNotEmpty
                  ? node.entity.title
                  : (props.nodeType != null
                      ? workflowNodeTypeLabel(props.nodeType!)
                      : '節點');
              _controller.onNodeResult?.call(nodeId, nodeTitle, '⚡ 開始運算…');
            }
          }
        }
      };

    await executor.execute(
      onProgress: progressCallback,
    );
  }

  /// [教練 Agent 2026-07-23] 偵測 needsProvider 並顯示能力引導對話框。
  /// 回傳 true 表示已引導使用者（節點應回傳失敗結果），
  /// 回傳 false 表示結果不是 needsProvider，由呼叫端繼續處理。
  bool _handleCapabilityGap(BuildContext context, BridgeActionResult result) {
    if (result.status != BridgeActionStatus.needsProvider) return false;

    final setupRoute = result.metadata?['setupRoute']?.toString() ?? '/golden-keys';
    final provider = result.metadata?['provider']?.toString() ?? '';
    final providerLabel = switch (provider) {
      'minimax' || 'minimax-video' || 'minimax-music' || 'minimax-tts' => 'MiniMax',
      'openai' => 'OpenAI',
      'replicate' => 'Replicate',
      _ => provider.isNotEmpty ? provider : '服務',
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.key_off, color: BridgeDS.orange700, size: 24),
              const SizedBox(width: 8),
              const Text('需要設定 API Key'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.message.split('：').first),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(context).surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline,
                            size: 16, color: BridgeDSColors.of(context).accentPurple),
                        const SizedBox(width: 6),
                        Text('設定步驟',
                            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                              color: BridgeDSColors.of(context).textPrimary,)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. 前往 $providerLabel 平台註冊並取得 API Key\n'
                      '2. 回到 App 設定頁 → 金鑰匙中心\n'
                      '3. 貼上 API Key 並測試連線\n'
                      '4. 設定完成後回到畫布重新執行',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(height: 1.6,
                        color: BridgeDSColors.of(context).textSecondary,),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('稍後再說'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.push(setupRoute);
              },
              icon: const Icon(Icons.key, size: 16),
              label: const Text('前往設定'),
            ),
          ],
        ),
      );
    });
    return true;
  }

  /// [教練 Agent 2026-08-01] Prompt 變數替換引擎
  ///
  /// 支援的變數：
  /// - {input} — 上游文字（最常用）
  /// - {input:N} — 第 N 個上游輸出（0-indexed）
  /// - {upstream} — 同 {input}
  ///
  /// 如果模板裡沒有變數，行為等同舊版：
  /// prompt + '\n\nContext:\n' + upstreamText
  /// [教練 Agent 2026-08-21] #10 imageGen 插值 bug 修復：
  /// 媒體生成節點（imageGen/videoGen/musicGen）的 prompt 不該
  /// 無上限吞整段上游 Context——LLM 節點的長輸出直接混進生圖
  /// prompt，模型把文字渲染進圖裡 = 亂碼 infographic 溫床。
  /// maxContextChars：上游文字截斷保護（LLM 節點不設、媒體節點 800）。
  String _interpolatePrompt(String template, String upstreamText,
      {int? maxContextChars}) {
    var context = upstreamText;
    if (maxContextChars != null && context.length > maxContextChars) {
      context = '${context.substring(0, maxContextChars)}…';
    }
    // 如果模板包含 {input} 或 {upstream}，做變數替換
    if (template.contains('{input}') || template.contains('{upstream}')) {
      return template
          .replaceAll('{input}', context)
          .replaceAll('{upstream}', context);
    }
    // 沒有變數 → fallback 舊行為：模板 + Context（截斷後）
    return '$template\n\nContext:\n$context';
  }

  /// 單一節點執行器 — 處理 LLM/Tool/ImageGen 等節點
  ///
  /// [教練 Agent 2026-07-23] 當 BridgeAction 回傳 needsProvider 時，
  /// 自動顯示能力引導對話框，帶領使用者到金鑰匙中心設定 API Key。
  ///
  /// [小葵 2026-09-24 Blue 令·定案圖組] 沿畫布連線 BFS 走整條上游鏈，
  /// 收集每個節點 params 上的定稿（_lastImageB64/_lastImageUrl）。
  /// 跨輪次：整流跑的＋單跑補的都在。seen 防重複（同節點只收一張）。
  void _collectAncestorFinals(
      String nodeId,
      Set<String> seen,
      List<String> galleryB64s,
      List<String> galleryUrls) {
    final queue = <String>[nodeId];
    final visited = <String>{nodeId};
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final conn in _controller.state.connections) {
        if (conn.toNodeId != current) continue;
        final upId = conn.fromNodeId;
        if (!visited.add(upId)) continue;
        final upNode = _controller.state.nodes[upId];
        final p = upNode?.entity.canvasProps?.params;
        if (p != null && !seen.contains(upId)) {
          final b = p['_lastImageB64']?.toString();
          if (b != null && b.isNotEmpty) {
            seen.add(upId);
            galleryB64s.add(b);
          } else {
            final u = p['_lastImageUrl']?.toString();
            if (u != null && u.startsWith('http')) {
              seen.add(upId);
              galleryUrls.add(u);
            }
          }
        }
        queue.add(upId);
      }
    }
  }

  Future<NodeExecutionResult> _executeNode(
    String nodeId,
    WorkflowNodeType? nodeType,
    Map<String, dynamic> params,
    UpstreamData upstreamData,
  ) async {
    // Input 節點的內容由 params['content'] 提供
    if (nodeType == WorkflowNodeType.input) {
      final content = params['content']?.toString() ??
          params['defaultValue']?.toString() ??
          '';
      return NodeExecutionResult(nodeId: nodeId, success: true, output: content);
    }

    // Output 節點：合併上游所有輸出（文字 + 圖片 gallery）
    // [教練 Agent 2026-08-01] 收集上游圖片，存入 result 供 NodeWidget gallery 顯示
    if (nodeType == WorkflowNodeType.output) {
      final combinedText = upstreamData.combinedText;
      // 收集所有上游圖片 base64 和 URL
      final hasImages = upstreamData.base64Images.isNotEmpty ||
          upstreamData.imageUrls.values.any((u) => !u.startsWith('file_id:'));

      // [小葵 2026-09-24 Blue 令·定案圖組] 定案 output 不只看本輪執行——
      // 沿畫布連線收集「整條上游鏈所有節點上的定稿圖」（params
      // _lastImageB64/_lastImageUrl，無論哪一輪生成的），整組放進
      // _galleryB64s/_galleryUrls 給 UI 展示。情境：主圖+兩視角整流跑、
      // 肖像單跑補——四張都要出現在定案圖組。
      final galleryB64s = <String>[];
      final galleryUrls = <String>[];
      final seen = <String>{};
      // 本輪執行的直接上游圖先進場（保序）
      for (final e in upstreamData.base64Images.entries) {
        if (seen.add(e.key)) galleryB64s.add(e.value);
      }
      for (final e in upstreamData.imageUrls.entries) {
        if (e.value.startsWith('http')) galleryUrls.add(e.value);
      }
      // 整條上游鏈上任何節點的定稿
      _collectAncestorFinals(nodeId, seen, galleryB64s, galleryUrls);
      final galleryParam = <String, dynamic>{
        if (galleryB64s.isNotEmpty) '_galleryB64s': galleryB64s,
        if (galleryUrls.isNotEmpty) '_galleryUrls': galleryUrls,
      };

      if (hasImages) {
        // 回傳第一張圖給 progress callback（主要圖片預覽）
        final firstB64 = upstreamData.firstBase64Image ?? galleryB64s.firstOrNull;
        final firstUrl = upstreamData.firstImageUrl ?? galleryUrls.firstOrNull;
        return NodeExecutionResult.withImage(
          nodeId,
          combinedText,
          imageData: firstB64 != null ? base64.decode(firstB64) : null,
          imageUrl: firstUrl,
          extraParams: galleryParam.isNotEmpty ? galleryParam : null,
        );
      }

      return NodeExecutionResult(
        nodeId: nodeId,
        success: true,
        output: combinedText,
        extraParams: galleryParam.isNotEmpty ? galleryParam : null,
      );
    }

    // Merge 節點：合併上游（文字 + 圖片）
    // [教練 Agent 2026-08-01] 傳遞圖片 — first/last 取對應圖片，concat 取第一張
    if (nodeType == WorkflowNodeType.merge) {
      final mode = params['mode']?.toString() ?? 'concat';
      switch (mode) {
        case 'first':
          return NodeExecutionResult.withImage(
            nodeId,
            upstreamData.texts.values.firstOrNull ?? '',
            imageData: upstreamData.base64Images.values.firstOrNull != null
                ? base64.decode(upstreamData.base64Images.values.first)
                : null,
            imageUrl: upstreamData.imageUrls.values.firstOrNull,
          );
        case 'last':
          return NodeExecutionResult.withImage(
            nodeId,
            upstreamData.texts.values.lastOrNull ?? '',
            imageData: upstreamData.base64Images.values.lastOrNull != null
                ? base64.decode(upstreamData.base64Images.values.last)
                : null,
            imageUrl: upstreamData.imageUrls.values.lastOrNull,
          );
        default:
          return NodeExecutionResult.withImage(
            nodeId,
            upstreamData.combinedText,
            imageData: upstreamData.firstBase64Image != null
                ? base64.decode(upstreamData.firstBase64Image!)
                : null,
            imageUrl: upstreamData.firstImageUrl,
          );
      }
    }

    // 從這裡開始接上真實的 BridgeAction executor
    final upstreamText = upstreamData.combinedText;

    // [教練 Agent 2026-08-16] Knowledge 節點 — vault 向量庫檢索（畫布執行路徑）
    // query 可含 {input} 佔位；沒設 query 就拿上游全文當查詢。
    if (nodeType == WorkflowNodeType.knowledge) {
      var query = params['query']?.toString() ?? '';
      if (query.contains('{input}') && upstreamText.isNotEmpty) {
        query = query.replaceAll('{input}', upstreamText);
      }
      if (query.trim().isEmpty) query = upstreamText;
      if (query.trim().isEmpty) {
        return NodeExecutionResult(
          nodeId: nodeId,
          success: false,
          errorMessage: '知識節點需要 query 或上游輸入',
        );
      }

      final mode = params['mode']?.toString() == 'fullText'
          ? VaultSearchMode.fullText
          : VaultSearchMode.semantic;
      final topK = (params['topK'] as num?)?.toInt() ?? 5;
      final room = params['room']?.toString() ?? '';

      try {
        final vault = VaultService.instance;
        vault.markInitialized();
        final entries = await vault.search(
          mode: mode,
          query: query,
          roomFilter: room.isEmpty ? null : room,
          limit: topK,
        );
        if (entries.isEmpty) {
          return NodeExecutionResult(
            nodeId: nodeId,
            success: true,
            output: '（vault 查無結果：$query）',
          );
        }
        final buf = StringBuffer();
        buf.writeln('以下是 vault 知識庫中「$query」的相關內容（${entries.length} 筆）：');
        buf.writeln();
        for (var i = 0; i < entries.length; i++) {
          final e = entries[i];
          final source = [
            if (e.room.isNotEmpty) e.room,
            if (e.subCategory.isNotEmpty) e.subCategory,
            if (e.agent.isNotEmpty) '紀錄者:${e.agent}',
          ].join(' · ');
          buf.writeln('── 來源 ${i + 1}${source.isEmpty ? '' : '（$source）'} ──');
          buf.writeln(e.content);
          buf.writeln();
        }
        return NodeExecutionResult(nodeId: nodeId, success: true, output: buf.toString());
      } catch (e) {
        return NodeExecutionResult(
          nodeId: nodeId,
          success: false,
          errorMessage: 'vault 檢索失敗: $e',
        );
      }
    }

    try {
      // 素材池節點 — 共視 F-1：AI 產 N 條候選發想（提議）
      // [教練 Agent 2026-08-25] 共識往返的「提議」端。執行時呼叫 LLM 產候選，
      // 人後續在節點上採用/跳過（回應端在 NodeWidget inline UI）。
      if (nodeType == WorkflowNodeType.materialPool) {
        var topic = params['topic']?.toString() ?? '';
        if (topic.contains('{input}') && upstreamText.isNotEmpty) {
          topic = topic.replaceAll('{input}', upstreamText);
        }
        if (topic.trim().isEmpty) topic = upstreamText;
        if (topic.trim().isEmpty) {
          return NodeExecutionResult(
            nodeId: nodeId,
            success: false,
            errorMessage: '素材池需要 topic 或上游輸入',
          );
        }
        final count = (params['count'] as num?)?.toInt() ?? 3;
        final prompt = '你是腦力激盪夥伴。針對主題產生 $count 條「彼此方向不同」的候選發想。'
            '每條 50 字內、具體可行、一句話一條，不要編號不要前言，直接 $count 行。\n'
            '主題：$topic';
        try {
          final result = await ApiService.complete(
            systemPrompt: 'You are a creative brainstorming partner. Reply in Traditional Chinese.',
            userPrompt: prompt,
            model: params['model']?.toString() ?? 'glm-4-flash',
          );
          final candidates = result
              .split('\n')
              .map((l) => l.replaceFirst(RegExp(r'^[\s\d\-•・.]+'), '').trim())
              .where((l) => l.isNotEmpty)
              .take(count)
              .toList();
          if (candidates.isEmpty) {
            return NodeExecutionResult(
              nodeId: nodeId,
              success: false,
              errorMessage: 'AI 沒有產出候選（回應為空）',
            );
          }
          return NodeExecutionResult(
            nodeId: nodeId,
            success: true,
            output: candidates.join('\n'),
            // 候選直接寫進 params，NodeWidget 的採用 UI 讀這裡
            extraParams: {'candidates': candidates},
          );
        } catch (e) {
          return NodeExecutionResult(
            nodeId: nodeId,
            success: false,
            errorMessage: '素材池生成失敗: $e',
          );
        }
      }

      // LLM 節點 — 呼叫 LLM
      // [教練 Agent 2026-08-01] 優先走 CapabilityExecutor（新的能力中心）
      if (nodeType == WorkflowNodeType.llm) {
        final model = params['model']?.toString() ?? 'glm-4-flash';
        final promptTemplate = params['prompt']?.toString() ?? '';
        final temperature = params['temperature'] as double?;
        final maxTokens = params['maxTokens'] as int?;
        final serviceId = params['serviceId']?.toString();

        // [教練 Agent 2026-08-01] 變數替換：{input} → 上游文字
        final systemPrompt = 'You are a helpful AI assistant.';
        final userPrompt = promptTemplate.isEmpty
            ? upstreamText
            : _interpolatePrompt(promptTemplate, upstreamText);

        // [教練 Agent 2026-08-01] 如果有指定 serviceId，走 CapabilityExecutor
        if (serviceId != null && serviceId.isNotEmpty) {
          final result = await CapabilityExecutor.instance.chat(
            serviceId: serviceId,
            prompt: userPrompt,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens,
          );
          if (result.success) {
            return NodeExecutionResult(
              nodeId: nodeId,
              success: true,
              output: result.text ?? '',
            );
          } else {
            return NodeExecutionResult(
              nodeId: nodeId,
              success: false,
              errorMessage: result.error ?? 'LLM 執行失敗',
            );
          }
        }

        // Fallback: 舊路徑（ApiService.complete）
        final result = await ApiService.complete(
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          model: model,
        );

        return NodeExecutionResult(
          nodeId: nodeId,
          success: true,
          output: result,
        );
      }

      // Tool 節點 — 映射到 BridgeActionType
      if (nodeType == WorkflowNodeType.tool) {
        final toolName = params['toolName']?.toString() ?? '';
        final args = params['args']?.toString() ?? '';

        // 映射 toolName 到 BridgeActionType
        BridgeActionType? actionType;
        switch (toolName.toLowerCase()) {
          case 'browse':
          case 'web_search':
            actionType = BridgeActionType.browse;
            break;
          case 'desktop_files':
            actionType = BridgeActionType.desktopFiles;
            break;
          case 'memory_search':
            return NodeExecutionResult(
              nodeId: nodeId,
              success: false,
              errorMessage: '暫不支援 memory_search 工具',
            );
          case 'code_exec':
            return NodeExecutionResult(
              nodeId: nodeId,
              success: false,
              errorMessage: '暫不支援 code_exec 工具',
            );
          default:
            return NodeExecutionResult(
              nodeId: nodeId,
              success: false,
              errorMessage: '未知的工具名稱: $toolName',
            );
        }

        final action = BridgeAction(
          type: actionType,
          prompt: args.isEmpty ? upstreamText : '$args\n$upstreamText',
        );

        final executor = BridgeActionExecutor();
        final result = await executor.execute(action);

        if (result.status == BridgeActionStatus.completed) {
          return NodeExecutionResult(
            nodeId: nodeId,
            success: true,
            output: result.message,
          );
        } else {
          return NodeExecutionResult(
            nodeId: nodeId,
            success: false,
            errorMessage: result.message,
          );
        }
      }

      // ImageGen 節點 — 生成圖片
      // [教練 Agent 2026-08-01] 優先走 CapabilityExecutor（新的能力中心）
      // [教練 Agent 2026-08-21] 圖生圖——上游有圖（image port 接入）時走
      // generateImageWithReference（OpenAI image edit / Gemini 原生編輯），
      // 付費閘門照走；無圖走原本的純文生圖路徑。
      if (nodeType == WorkflowNodeType.imageGen) {
        final promptRaw = params['prompt']?.toString() ?? '';
        final promptText = _interpolatePrompt(promptRaw, upstreamText,
            maxContextChars: 800);
        final size = params['size']?.toString();
        final serviceId = params['serviceId']?.toString();

        // 圖生圖：上游所有 base64 圖全部送（多線接入＝多參考圖）
        // [教練 Agent 2026-08-21] 多線接入的隱式 merge 把上游圖全帶來——
        // 全部送 API。順序＝上游收集順序（DAG 拓撲序），
        // prompt 裡「第一張為主體、第二張取配色」這種描述會生效。
        // [教練 Agent 2026-08-22 使用者洞察] 標題錨定——換權重不該要重接線。
        // base64Images 的 key 是上游 nodeId → 挖出節點標題，
        // 在 prompt 附「圖↔標題」對照表。使用者寫「A為主體 B為裝飾」
        // 即以標題指揮權重，改權重＝改 prompt 一個字，線不用動。
        final refEntries = upstreamData.base64Images.entries.toList();
        final refImages = refEntries.map((e) => e.value).toList();
        String refPromptText = promptText;
        if (refEntries.length > 1) {
          final legend = <String>[];
          for (var i = 0; i < refEntries.length; i++) {
            final upNode = _controller.state.nodes[refEntries[i].key];
            final upTitle = upNode?.entity.title ?? '第${i + 1}張';
            legend.add('第${i + 1}張=「$upTitle」');
          }
          refPromptText =
              '$promptText\n\n（參考圖對照：${legend.join('、')}。'
              '提示詞中提到的名稱以此對照表為準，用名稱指定哪張為主體、哪張為裝飾。）';
        }
        final refB64 = refImages.isNotEmpty ? refImages.first : null;
        final extraRefs = refImages.length > 1 ? refImages.sublist(1) : null;
        if (refB64 != null && refPromptText.isNotEmpty) {
          // [教練 Agent 2026-08-26 使用者決策] OpenAI Key 已停用——圖片生成全面改 MiniMax。
          // 舊註解的 images/edits 路徑僅在顯式選 openai_image 時才走。
          final refService = (serviceId != null && serviceId.isNotEmpty)
              ? serviceId
              : 'minimax_image';
          final refResult =
              await CapabilityExecutor.instance.generateImageWithReference(
            serviceId: refService,
            prompt: refPromptText,
            base64ReferenceImage: refB64,
            size: size,
            extraReferenceImages: extraRefs,
          );
          if (refResult.success) {
            // [小葵 2026-09-24 落盤] 本地路徑優先入 output——重啟後仍找得到圖
            final output = refResult.localFilePath != null
                ? '圖片已生成（圖生圖）\n路徑: ${refResult.localFilePath}'
                : (refResult.imageUrl != null
                    ? '圖片已生成（圖生圖）\nURL: ${refResult.imageUrl}'
                    : '圖片已生成（圖生圖）');
            return NodeExecutionResult.withImage(
              nodeId,
              output,
              imageData: refResult.imageData,
              imageUrl: refResult.imageUrl,
            );
          } else {
            return NodeExecutionResult(
              nodeId: nodeId,
              success: false,
              errorMessage: '圖生圖失敗: ${refResult.error ?? '未知錯誤'}',
            );
          }
        }

        // [教練 Agent 2026-08-01] 如果有指定 serviceId，走 CapabilityExecutor
        if (serviceId != null && serviceId.isNotEmpty) {
          final capResult = await CapabilityExecutor.instance.generateImage(
            serviceId: serviceId,
            prompt: promptText,
            size: size,
          );
          if (capResult.success) {
            // [小葵 2026-09-24 落盤] 本地路徑優先入 output
            final output = capResult.localFilePath != null
                ? '圖片已生成\n路徑: ${capResult.localFilePath}'
                : (capResult.imageUrl != null
                    ? '圖片已生成\nURL: ${capResult.imageUrl}'
                    : '圖片已生成');
            return NodeExecutionResult.withImage(
              nodeId,
              output,
              imageData: capResult.imageData,
              imageUrl: capResult.imageUrl,
            );
          } else {
            return NodeExecutionResult(
              nodeId: nodeId,
              success: false,
              errorMessage: capResult.error ?? '圖片生成失敗',
            );
          }
        }

        // Fallback: 舊路徑（BridgeActionExecutor）
        final action = BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: promptText,
        );

        final executor = BridgeActionExecutor();
        final result = await executor.execute(action);

        if (result.status == BridgeActionStatus.completed) {
          // [教練 Agent 2026-08-01] 帶 imageUrl 到下游
          return NodeExecutionResult.withImage(
            nodeId,
            result.message,
            imageUrl: result.mediaUrl,
          );
        } else {
          // [教練 Agent 2026-07-23] 缺 key 時觸發能力引導
          if (result.status == BridgeActionStatus.needsProvider) {
            _handleCapabilityGap(context, result);
          }
          return NodeExecutionResult(
            nodeId: nodeId,
            success: false,
            errorMessage: result.message,
          );
        }
      }

      // Vision 節點 — 圖片理解
      // [教練 Agent 2026-08-01] 接收上游圖片 + prompt → 分析內容
      if (nodeType == WorkflowNodeType.vision) {
        final promptText = params['prompt']?.toString() ?? '描述這張圖片';
        final serviceId = params['serviceId']?.toString();

        // 取得上游圖片（base64 或 URL）
        final base64Image = upstreamData.firstBase64Image;
        final imageUrl = upstreamData.firstImageUrl;

        // [小葵 2026-09-22 修 bug·原圖直通] 拖檔進畫布的 vision 節點
        // 自帶 params['image']=檔案路徑——沒有上游連線時，它就是源頭。
        // 之後無論分析成功與否，「原圖」都要能往下傳（圖生圖的 reference）。
        Uint8List? passthroughImage;
        if (base64Image == null && imageUrl == null) {
          final localPath = params['image']?.toString();
          if (localPath != null && localPath.isNotEmpty) {
            try {
              passthroughImage = await File(localPath).readAsBytes();
            } catch (_) {
              passthroughImage = null;
            }
          }
        }
        if (base64Image == null && imageUrl == null && passthroughImage == null) {
          return NodeExecutionResult(
            nodeId: nodeId,
            success: false,
            errorMessage: 'Vision 節點需要上游有圖片輸入，'
                '請連接 ImageGen 或 Input 節點',
          );
        }

        // 如果有 serviceId，走 CapabilityExecutor
        if (serviceId != null && serviceId.isNotEmpty) {
          // 如果有 base64 直接用；否則需要從 URL 下載再轉 base64
          String b64 = base64Image ?? '';
          if (b64.isEmpty && imageUrl != null) {
            try {
              final imgResp = await Dio().get<List<int>>(
                imageUrl,
                options: Options(responseType: ResponseType.bytes),
              );
              b64 = base64.encode(imgResp.data ?? []);
            } catch (e) {
              return NodeExecutionResult(
                nodeId: nodeId,
                success: false,
                errorMessage: '下載圖片失敗: $e',
              );
            }
          }

          final capResult = await CapabilityExecutor.instance.analyzeImage(
            serviceId: serviceId,
            prompt: promptText,
            base64Image: b64,
          );
          if (capResult.success) {
            // [小葵 2026-09-22 原圖直通] 分析文字＋原圖一起帶走——
            // 下游 characterLock/imageGen 可直接取 reference（真·圖生圖）。
            return NodeExecutionResult.withImage(
              nodeId,
              capResult.text ?? '',
              imageData: passthroughImage,
            );
          } else {
            return NodeExecutionResult(
              nodeId: nodeId,
              success: false,
              errorMessage: capResult.error ?? '圖片理解失敗',
            );
          }
        }

        // Fallback: 無 serviceId——不分析，但原圖照樣直通（拖圖源頭
        // 不該因為沒選服務而斷流）。
        if (passthroughImage != null) {
          return NodeExecutionResult.withImage(
            nodeId,
            '（未選服務——原圖直通，未分析）',
            imageData: passthroughImage,
          );
        }
        return NodeExecutionResult(
          nodeId: nodeId,
          success: false,
          errorMessage: '請在節點設定中選擇「服務」',
        );
      }

      // CharacterLock 節點 — 角色一致性
      // [教練 Agent 2026-08-01] 接收上游參考圖 + prompt → 生成風格一致的新圖
      if (nodeType == WorkflowNodeType.characterLock) {
        final promptRaw = params['prompt']?.toString() ?? '';
        final promptText = _interpolatePrompt(promptRaw, upstreamText);
        final serviceId = params['serviceId']?.toString();
        final size = params['size']?.toString();

        // 取得上游參考圖
        final base64Ref = upstreamData.firstBase64Image;
        final imageUrl = upstreamData.firstImageUrl;

        if (base64Ref == null && imageUrl == null) {
          return NodeExecutionResult(
            nodeId: nodeId,
            success: false,
            errorMessage: '角色一致性節點需要上游有參考圖片',
          );
        }

        // 下載 URL 圖片轉 base64（如果需要）
        String b64Ref = base64Ref ?? '';
        if (b64Ref.isEmpty && imageUrl != null) {
          try {
            final imgResp = await Dio().get<List<int>>(
              imageUrl,
              options: Options(responseType: ResponseType.bytes),
            );
            b64Ref = base64.encode(imgResp.data ?? []);
          } catch (e) {
            return NodeExecutionResult(
              nodeId: nodeId,
              success: false,
              errorMessage: '下載參考圖失敗: $e',
            );
          }
        }

        if (serviceId != null && serviceId.isNotEmpty) {
          final capResult = await CapabilityExecutor.instance.generateImageWithReference(
            serviceId: serviceId,
            prompt: promptText,
            base64ReferenceImage: b64Ref,
            size: size,
          );
          if (capResult.success) {
            return NodeExecutionResult.withImage(
              nodeId,
              // [小葵 2026-09-24 落盤] output 帶本地路徑——重啟後仍找得到圖
              capResult.localFilePath != null
                  ? '角色一致性圖片已生成\n路徑: ${capResult.localFilePath}'
                  : '角色一致性圖片已生成',
              imageData: capResult.imageData,
              imageUrl: capResult.imageUrl,
            );
          } else {
            return NodeExecutionResult(
              nodeId: nodeId,
              success: false,
              errorMessage: capResult.error ?? '角色一致性生成失敗',
            );
          }
        }

        return NodeExecutionResult(
          nodeId: nodeId,
          success: false,
          errorMessage: '請在節點設定中選擇「服務」',
        );
      }

      // VideoGen 節點 — 生成影片
      // [教練 Agent 2026-08-01] 優先走 CapabilityExecutor
      if (nodeType == WorkflowNodeType.videoGen) {
        final promptRaw = params['prompt']?.toString() ?? '';
        final promptText = _interpolatePrompt(promptRaw, upstreamText,
            maxContextChars: 800);
        final duration = params['duration'] as int?;
        final serviceId = params['serviceId']?.toString();

        // [教練 Agent 2026-08-01] 如果有指定 serviceId，走 CapabilityExecutor
        if (serviceId != null && serviceId.isNotEmpty) {
          final capResult = await CapabilityExecutor.instance.generateVideo(
            serviceId: serviceId,
            prompt: promptText,
            duration: duration,
          );
          if (capResult.success) {
            return NodeExecutionResult.withImage(
              nodeId,
              '影片已生成\nURL: ${capResult.imageUrl ?? "（處理中）"}',
              imageUrl: capResult.imageUrl,
            );
          } else {
            return NodeExecutionResult(
              nodeId: nodeId,
              success: false,
              errorMessage: capResult.error ?? '影片生成失敗',
            );
          }
        }

        // Fallback: 舊路徑（BridgeActionExecutor）
        final action = BridgeAction(
          type: BridgeActionType.generateVideo,
          prompt: promptText,
        );

        final executor = BridgeActionExecutor();
        final result = await executor.execute(action);

        if (result.status == BridgeActionStatus.completed) {
          final output = result.mediaUrl != null
              ? '${result.message}\n媒體: ${result.mediaUrl}'
              : result.message;
          return NodeExecutionResult(
            nodeId: nodeId,
            success: true,
            output: output,
          );
        } else {
          // [教練 Agent 2026-07-23] 缺 key 時觸發能力引導
          if (result.status == BridgeActionStatus.needsProvider) {
            _handleCapabilityGap(context, result);
          }
          return NodeExecutionResult(
            nodeId: nodeId,
            success: false,
            errorMessage: result.message,
          );
        }
      }

      // MusicGen 節點 — 生成音樂
      // [教練 Agent 2026-08-01] 優先走 CapabilityExecutor
      if (nodeType == WorkflowNodeType.musicGen) {
        final promptRaw = params['prompt']?.toString() ?? '';
        final promptText = _interpolatePrompt(promptRaw, upstreamText,
            maxContextChars: 800);
        final serviceId = params['serviceId']?.toString();

        // [教練 Agent 2026-08-01] 如果有指定 serviceId，走 CapabilityExecutor
        if (serviceId != null && serviceId.isNotEmpty) {
          final capResult = await CapabilityExecutor.instance.generateMusic(
            serviceId: serviceId,
            prompt: promptText,
          );
          if (capResult.success) {
            return NodeExecutionResult.withImage(
              nodeId,
              '音樂已生成\nURL: ${capResult.imageUrl ?? "（處理中）"}',
              imageUrl: capResult.imageUrl,
            );
          } else {
            return NodeExecutionResult(
              nodeId: nodeId,
              success: false,
              errorMessage: capResult.error ?? '音樂生成失敗',
            );
          }
        }

        // Fallback: 舊路徑（BridgeActionExecutor）
        final action = BridgeAction(
          type: BridgeActionType.generateMusic,
          prompt: promptText,
        );

        final executor = BridgeActionExecutor();
        final result = await executor.execute(action);

        if (result.status == BridgeActionStatus.completed) {
          final output = result.mediaUrl != null
              ? '${result.message}\n媒體: ${result.mediaUrl}'
              : result.message;
          return NodeExecutionResult(
            nodeId: nodeId,
            success: true,
            output: output,
          );
        } else {
          // [教練 Agent 2026-07-23] 缺 key 時觸發能力引導
          if (result.status == BridgeActionStatus.needsProvider) {
            _handleCapabilityGap(context, result);
          }
          return NodeExecutionResult(
            nodeId: nodeId,
            success: false,
            errorMessage: result.message,
          );
        }
      }

      // TTS 節點 — 用 FlutterTts 合成語音檔
      // [教練 Agent 2026-07-22] Phase G — TTS 節點實作
      if (nodeType == WorkflowNodeType.tts) {
        final textToSpeak = params['text']?.toString() ?? upstreamText;
        final speed = params['speed'] as double?;

        if (textToSpeak.trim().isEmpty) {
          return NodeExecutionResult(
            nodeId: nodeId,
            success: false,
            errorMessage: 'TTS 節點沒有可朗讀的文字',
          );
        }

        final audioPath = await CanvasTtsService.instance.synthesizeToFile(
          text: textToSpeak,
          speed: speed,
        );

        if (audioPath != null) {
          return NodeExecutionResult(
            nodeId: nodeId,
            success: true,
            output: '語音合成完成\n音檔: $audioPath\n原始文字: $textToSpeak',
          );
        } else {
          return NodeExecutionResult(
            nodeId: nodeId,
            success: false,
            errorMessage: '語音合成失敗',
          );
        }
      }

      // Condition 節點 — 簡單條件判斷
      if (nodeType == WorkflowNodeType.condition) {
        final condition = params['condition']?.toString() ??
            params['expression']?.toString() ??
            '';

        // 簡單 eval：檢查上游文字是否包含條件字串
        final conditionMet = upstreamText.contains(condition);
        final result = conditionMet ? 'true' : 'false';

        return NodeExecutionResult(
          nodeId: nodeId,
          success: true,
          output: '$upstreamText\n條件 "$condition": $result',
        );
      }

      // SubWorkflow 節點 — 載入並執行子工作流
      // [教練 Agent 2026-07-22] Phase G — SubWorkflow 節點實作
      if (nodeType == WorkflowNodeType.subWorkflow) {
        final workflowRef = params['workflowRef']?.toString() ?? '';

        if (workflowRef.isEmpty) {
          return NodeExecutionResult(
            nodeId: nodeId,
            success: false,
            errorMessage: '未指定子工作流',
          );
        }

        try {
          final result = await CanvasSubWorkflowRunner.instance.run(
            workflowRef: workflowRef,
            upstreamOutputs: upstreamData.texts,
          );
          return NodeExecutionResult(
            nodeId: nodeId,
            success: true,
            output: result,
          );
        } catch (e) {
          return NodeExecutionResult(
            nodeId: nodeId,
            success: false,
            errorMessage: '子工作流執行失敗: $e',
          );
        }
      }

      // 其他未實作的節點類型
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '節點類型 ${nodeType?.name ?? 'unknown'} 尚未實作',
      );
    } catch (e, stackTrace) {
      debugPrint('節點執行錯誤 ($nodeId): $e\n$stackTrace');
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '執行失敗: $e',
      );
    }
  }

  Future<void> _loadCanvas() async {
    setState(() => _isLoading = true);
    try {
      // [教練 Agent 2026-07-24] 同步 workspace 的 _canvasId 與 controller，
      // 否則 _onSave 會以為是空白畫布而彈出問名稱對話框
      _canvasId = _controller.canvasId;
      await _controller.loadFromStore();

      // [教練 Agent 2026-07-24] 載入塗鴉和文字
      if (_canvasId != null && _canvasId != 'default') {
        final canvas = await CanvasStore.getById(_canvasId!);
        if (canvas != null) {
          _doodleStrokes.clear();
          _doodleStrokes.addAll(
            canvas.doodleStrokes.map((j) => DoodleStroke.fromJson(j)),
          );
          _doodleTexts.clear();
          _doodleTexts.addAll(
            canvas.doodleTexts.map((j) => DoodleText.fromJson(j)),
          );
        }
      }

      // [教練 Agent 2026-07-23] 空畫布不自動載入示範工作流
      // 改為顯示歡迎覆蓋層，讓使用者選擇「空白畫布」「選擇範本」或「互動教學」

      // 載入後自動置中，涵蓋所有節點
      if (_controller.state.nodes.isNotEmpty && mounted) {
        final size = context.size ?? const Size(800, 600);
        _controller.fitToContent(size);
      }
    } catch (e) {
      debugPrint('CanvasV2: 載入失敗: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 種示範工作流 — 讓使用者一進來就看到有內容的畫布
  /// [教練 Agent 2026-07-23] 加大節點間距配合 NodeWidget 實際渲染寬度(200-320px)
  Future<void> _seedDemoWorkflow() async {
    const spacing = 400.0;
    const startY = 100.0;
    final inputId = await _controller.addWorkflowNode(WorkflowNodeType.input, const Offset(60, startY + 60));
    await Future.delayed(const Duration(milliseconds: 10));
    final llmId = await _controller.addWorkflowNode(WorkflowNodeType.llm, Offset(60 + spacing, startY));
    await Future.delayed(const Duration(milliseconds: 10));
    final toolId = await _controller.addWorkflowNode(WorkflowNodeType.tool, Offset(60 + spacing, startY + 240));
    await Future.delayed(const Duration(milliseconds: 10));
    final mergeId = await _controller.addWorkflowNode(WorkflowNodeType.merge, Offset(60 + spacing * 2, startY + 120));
    await Future.delayed(const Duration(milliseconds: 10));
    final outputId = await _controller.addWorkflowNode(WorkflowNodeType.output, Offset(60 + spacing * 3, startY + 120));

    // 連線：input → llm, input → tool, llm → merge, tool → merge, merge → output
    await _controller.connect(inputId, 'output', llmId, 'input');
    await _controller.connect(inputId, 'output', toolId, 'input');
    await _controller.connect(llmId, 'output', mergeId, 'a');
    await _controller.connect(toolId, 'output', mergeId, 'b');
    await _controller.connect(mergeId, 'output', outputId, 'input');
  }

  /// 由外部呼叫切換畫布
  Future<void> loadCanvasById(String canvasId, {bool clearCanvas = false}) async {
    _canvasId = canvasId;
    // [教練 Agent 2026-07-23] 同步更新 controller 的 canvasId，否則 loadFromStore 會用舊的
    _controller.canvasId = canvasId;
    widget.onCanvasChanged?.call(canvasId);
    // [教練 Agent 2026-07-23] 切換畫布時清掉舊塗鴉，避免跨畫布污染
    _doodleStrokes.clear();
    _doodleTexts.clear();
    // 載入此畫布的塗鴉和文字
    final canvas = await CanvasStore.getById(canvasId);
    if (canvas != null) {
      if (canvas.doodleStrokes.isNotEmpty) {
        _doodleStrokes.addAll(
          canvas.doodleStrokes.map((j) => DoodleStroke.fromJson(j)),
        );
      }
      if (canvas.doodleTexts.isNotEmpty) {
        _doodleTexts.addAll(
          canvas.doodleTexts.map((j) => DoodleText.fromJson(j)),
        );
      }
    }
    if (clearCanvas) {
      _controller.clearSelection();
    }
    await _controller.loadFromStore();
    // [教練 Agent 2026-07-22] Phase A — 載入完成後發出事件，讓快照服務感知
    CanvasEventBus.instance.emit(CanvasEventType.canvasLoaded, data: {'canvasId': canvasId});
    // [教練 Agent 2026-07-23] 載入後自動置中
    if (mounted) {
      final size = context.size ?? const Size(800, 600);
      _controller.fitToContent(size);
    }
  }

  /// 清空工作區
  void clearWorkspace() {
    _controller.clearSelection();
  }

  /// 處理工具列變更（由桌面工具列呼叫）
  void handleToolChanged(dynamic tool) {
    // 舊 CanvasTool → 新 CanvasTool2 映射
    // 注意：doodle 由 toggleDoodle() 全權處理，此處跳過避免打架
    if (tool.toString().contains('select')) {
      _controller.setTool(CanvasTool2.select);
      if (_doodleEnabled) setState(() => _doodleEnabled = false);
    } else if (tool.toString().contains('connect')) {
      _controller.setTool(CanvasTool2.connect);
      if (_doodleEnabled) setState(() => _doodleEnabled = false);
    } else if (tool.toString().contains('pan')) {
      _controller.setTool(CanvasTool2.pan);
    }
    // doodle 不在此處處理 — onDoodle callback 會呼叫 toggleDoodle()
  }

  /// 設定工具（供桌面層直接呼叫）
  void setTool(CanvasTool2 tool) {
    _controller.setTool(tool);
  }

  /// 在畫布中央新增節點
  Future<void> addNodeAtCenter() async {
    // 切換到「新增節點」模式 — 下次在畫布點擊時彈出選單
    _controller.setTool(CanvasTool2.addNode);
  }

  /// 切換塗鴉模式
  void toggleDoodle() {
    setState(() => _doodleEnabled = !_doodleEnabled);
    if (_doodleEnabled) {
      _controller.setTool(CanvasTool2.doodle);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('塗鴉模式已啟用 — 在畫布上拖曳即可繪製'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      _controller.setTool(CanvasTool2.select);
    }
  }

  /// 切換塗鴉圖層可見性
  void toggleDoodleVisible() {
    setState(() => _doodleVisible = !_doodleVisible);
  }

  /// 取得塗鴉標注的 JSON（供 MCP 暴露給 Agent）
  List<Map<String, dynamic>> getDoodleAnnotations() {
    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < _doodleStrokes.length; i++) {
      final s = _doodleStrokes[i];
      result.add({
        'index': i,
        'type': 'stroke',
        'points': s.worldPoints.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'color': '#${s.color.toARGB32().toRadixString(16).padLeft(8, '0')}',
        'strokeWidth': s.strokeWidth,
        'bounds': _strokeBounds(s.worldPoints),
      });
    }
    for (int i = 0; i < _doodleTexts.length; i++) {
      final t = _doodleTexts[i];
      result.add({
        'index': i,
        'type': 'text',
        'x': t.worldPos.dx,
        'y': t.worldPos.dy,
        'text': t.text,
        'color': '#${t.color.toARGB32().toRadixString(16).padLeft(8, '0')}',
        'fontSize': t.fontSize,
      });
    }
    return result;
  }

  /// 計算一筆的 bounding box
  Map<String, double> _strokeBounds(List<Offset> points) {
    if (points.isEmpty) return {'minX': 0, 'minY': 0, 'maxX': 0, 'maxY': 0};
    double minX = points.first.dx, maxX = points.first.dx;
    double minY = points.first.dy, maxY = points.first.dy;
    for (final p in points) {
      minX = p.dx < minX ? p.dx : minX;
      maxX = p.dx > maxX ? p.dx : maxX;
      minY = p.dy < minY ? p.dy : minY;
      maxY = p.dy > maxY ? p.dy : maxY;
    }
    return {'minX': minX, 'minY': minY, 'maxX': maxX, 'maxY': maxY};
  }

  /// 從 JSON 載入工作流
  void loadWorkflowFromJson(String jsonStr) {
    // TODO: 解析 JSON 並建立節點+連線
  }

  /// 種示範工作流（公開方法，由桌面 sidebar 呼叫）
  Future<void> seedDemoWorkflow() async {
    await _seedDemoWorkflow();
  }

  /// [教練 Agent 2026-07-23] 直接載入完整範本到畫布（sidebar 下拉選單用）
  Future<void> loadTemplate(WorkflowTemplate template) async {
    await _loadTemplateByName(template.id);
  }

  String? get canvasId => _canvasId;

  @override
  void dispose() {
    _scheduleSyncTimer?.cancel();
    // [W1 2026-10-08] 引擎已搬 App 層——workspace 只解註冊前景畫布，
    // 不再 dispose 引擎（AppScheduleEngine 生命周期跟著 App 走）
    AppScheduleEngine.instance.unregisterForeground();
    _canvasFocusNode.dispose();
    // [隊友訊息流 C1 2026-09-08] 比對前景原體而非 controller getter——
    // ambient 覆寫期間 getter 回傳任務工作畫布，直接比對會漏清前景指標。
    if (CanvasMcpRegistry.instance.foregroundController == _controller) {
      CanvasMcpRegistry.instance.controller = null;
    }
    _controller.dispose();
    _chatHighlight.dispose();
    super.dispose();
  }

  void _onDoubleTapEmpty(Offset screenPos, Offset worldPos) {
    // [教練 Agent 2026-08-03] NodeSearchBox 已移到 graph_canvas 內部統一顯示
    // 這裡保留空實作以維持 callback 介面相容
  }

  /// [教練 Agent 2026-08-16 使用者 提案] Finder 拖檔進畫布——
  /// 於 drop 位置依檔案型別建節點：
  /// - 圖片（png/jpg/jpeg/gif/webp/heic）→ vision 節點，image 參數=檔案路徑
  /// - 文字（txt/md/json/csv/dart...）→ input 節點，content=檔案內容（截斷保護）
  /// - 其他 → input 節點，content=檔案路徑（讓 LLM 自己處理）
  /// 多檔案垂直堆疊（一大格間距），不疊在一起。
  Future<void> _onFilesDropped(List<XFile> files, Offset screenPos) async {
    if (files.isEmpty) return;
    final world = _controller.state.viewport.screenToWorld(screenPos);
    const imageExt = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.heic', '.bmp', '.tiff'};
    const textExt = {'.txt', '.md', '.json', '.csv', '.dart', '.yaml', '.yml', '.log', '.xml', '.html'};

    var i = 0;
    for (final f in files) {
      final path = f.path;
      final name = path.split('/').last;
      final dot = name.lastIndexOf('.');
      final ext = dot >= 0 ? name.substring(dot).toLowerCase() : '';

      final worldPos = world + Offset(0, i * 160); // 一大格間距，不疊卡
      i++;

      if (imageExt.contains(ext)) {
        final nodeId = await _controller.addWorkflowNode(WorkflowNodeType.vision, worldPos);
        _controller.updateNodeParams(nodeId, WorkflowNodeType.vision, {
          'label': '🖼️ $name',
          'image': path,
        });
      } else if (textExt.contains(ext)) {
        final nodeId = await _controller.addWorkflowNode(WorkflowNodeType.input, worldPos);
        // 讀檔內容（上限 4000 字，防爆 context）
        String content = '';
        try {
          final raw = await File(path).readAsString();
          content = raw.length > 4000 ? '${raw.substring(0, 4000)}\n…（已截斷）' : raw;
        } catch (_) {
          content = path; // 讀不了就放路徑
        }
        _controller.updateNodeParams(nodeId, WorkflowNodeType.input, {
          'label': '📄 $name',
          'content': content,
        });
      } else {
        // 其他型別（pdf、影片、音檔…）——先建 input 帶路徑，讓使用者決定怎麼用
        final nodeId = await _controller.addWorkflowNode(WorkflowNodeType.input, worldPos);
        _controller.updateNodeParams(nodeId, WorkflowNodeType.input, {
          'label': '📎 $name',
          'content': path,
          // [小葵 2026-09-23 Blue 令·共視] 檔案卡預覽——外部檔案
          // 拖進來要直接看到「是什麼檔、多大」，不是只看到一串路徑。
          '_filePath': path,
        });
      }
    }
    if (mounted) setState(() {});
  }

  void _onNodeDoubleTap(String nodeId) {
    // [教練 Agent 2026-08-15 使用者決策] Inspector 面板退役——
    // 標籤已上卡片、執行已進右鍵選單，面板沒有存在價值。
    // 雙擊保留給未來（例如 inline 改標籤）。
  }

  /// [教練 Agent 2026-07-22] Phase 5 互動式教學
  /// 顯示範本選擇對話框，選擇後載入範本到畫布。
  /// [教練 Agent 2026-07-23] 聊天框高亮 — Agent 發話時亮一下
  void _flashChatHighlight() {
    _chatHighlight.value = true;
    Future.delayed(const Duration(milliseconds: 1500), () {
      _chatHighlight.value = false;
    });
  }

  /// [教練 Agent 2026-07-23] 選擇範本後直接進入逐步教學模式（跳過打招呼）
  Future<void> _showTemplatePickerAndStartTutorial() async {
    final template = await showDialog<WorkflowTemplate>(
      context: context,
      builder: (context) => const TemplatePickerDialog(),
    );

    if (template == null || !mounted) return;

    // 注入動作回呼——讓教學服務能在畫布上建立節點和連線
    TemplateTutorialService.instance.onAddNode = (typeStr, x, y, params) async {
      final type = _parseWorkflowNodeType(typeStr);
      final nodeId = await _controller.addWorkflowNode(type, Offset(x, y));
      if (params != null) {
        _controller.updateNodeParams(nodeId, type, params);
      }
      return nodeId;
    };
    TemplateTutorialService.instance.onConnect = (fromId, fromPort, toId, toPort) {
      // [教練 Agent 2026-07-24] 不 await 但逐條呼叫——教學中連線量少（≤12），race 機率低
      _controller.connect(fromId, fromPort, toId, toPort);
    };

    // [教練 Agent 2026-07-23] Agent 發話時亮一下聊天框
    TemplateTutorialService.instance.onAgentSpeak = _flashChatHighlight;

    // 直接用選到的範本啟動逐步教學（跳過打招呼和範本選擇步驟）
    await TemplateTutorialService.instance.startTutorialWithTemplate(template);
  }

  /// [刀 5 D5.3/D5.4] 示範錄製流程：⏺ 開錄 → 做操作 → ■ 停止 → 快照存範本。
  /// 錄 CanvasEventBus 結構化事件（操作故事顯示用）；範本本體用最終快照法
  /// （編輯改來改去不影響範本正確性）。
  void _startRoutineRecording() {
    if (_routineRecording) {
      _stopRoutineRecording();
      return;
    }
    RoutineRecorder.instance.start(_controller.canvasId ?? 'unsaved');
    setState(() => _routineRecording = true);
    _flashChatHighlight();
  }

  Future<void> _stopRoutineRecording() async {
    final rec = RoutineRecorder.instance.stop();
    setState(() => _routineRecording = false);
    if (rec == null) return;

    if (rec.eventCount == 0) {
      // 沒錄到任何誕生事件——直接說，不開對話框（誠實鐵則）
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('沒有錄到任何節點/連線操作——範本需要至少一個操作')),
        );
      }
      return;
    }

    // D5.4 存範本對話框（名稱/描述）
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(dctx).surface,
        title: const Text('存為範本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('錄到 ${rec.eventCount} 個操作：'),
            const SizedBox(height: 4),
            ...rec.story.take(5).map((s) => Text('· $s',
                style: const TextStyle(fontSize: 12))),
            if (rec.story.length > 5)
              Text('…等 ${rec.story.length} 步', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: '範本名稱'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: '描述（選填）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('放棄'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('儲存'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      RoutineRecorder.instance.discard();
      return;
    }

    // 快照法：抓畫布當下完整 nodes+connections 存範本
    final nodes = <Map<String, dynamic>>[];
    final conns = <Map<String, dynamic>>[];
    final nodeList = _controller.state.nodes.values.toList();
    final indexById = <String, int>{};
    for (var i = 0; i < nodeList.length; i++) {
      final n = nodeList[i];
      indexById[n.id] = i;
      final p = n.entity.canvasProps;
      nodes.add({
        'type': n.entity.type.name,
        'x': p?.x ?? 0,
        'y': p?.y ?? 0,
        if (p != null && p.params.isNotEmpty) 'params': p.params,
      });
    }
    for (final e in _controller.state.connections) {
      final fromIdx = indexById[e.fromNodeId];
      final toIdx = indexById[e.toNodeId];
      if (fromIdx == null || toIdx == null) continue;
      conns.add({
        'from': fromIdx,
        'fromPort': e.fromPortId,
        'to': toIdx,
        'toPort': e.toPortId,
      });
    }

    final template = WorkflowTemplate(
      id: 'routine_${DateTime.now().millisecondsSinceEpoch}',
      name: nameCtrl.text.trim().isEmpty ? '我的示範 ${rec.startedAt.month}/${rec.startedAt.day}' : nameCtrl.text.trim(),
      description: descCtrl.text.trim().isEmpty
          ? '示範錄製（${rec.eventCount} 個操作）'
          : descCtrl.text.trim(),
      category: '我的示範',
      icon: '⏺',
      nodes: nodes,
      connections: conns,
    );
    await VaultTemplateService.instance.saveCustomTemplate(template);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('範本「${template.name}」已存——到範本庫「我的示範」分類重播')),
      );
    }
  }

  Future<void> _showTemplatePicker() async {
    final template = await showDialog<WorkflowTemplate>(
      context: context,
      builder: (context) => const TemplatePickerDialog(),
    );

    if (template == null || !mounted) return;

    // [教練 Agent 2026-08-15 批量載入] 修多重宇宙卡 3 分鐘：
    // 35 次串行 DB 寫入 → beginBatch 只動 state，endBatch 一次寫入。
    _controller.beginBatch();
    try {
    // 載入範本節點到畫布
    final nodeIdMap = <int, String>{};
    for (var i = 0; i < template.nodes.length; i++) {
      final nodeDef = template.nodes[i];
      final typeStr = nodeDef['type'] as String? ?? 'input';
      final x = (nodeDef['x'] as num?)?.toDouble() ?? 100.0 + i * 50;
      final y = (nodeDef['y'] as num?)?.toDouble() ?? 150.0;

      final type = _parseWorkflowNodeType(typeStr);
      final nodeId = await _controller.addWorkflowNode(type, Offset(x, y));
      nodeIdMap[i] = nodeId;

      // 設定節點參數
      final params = nodeDef['params'] as Map<String, dynamic>?;
      if (params != null) {
        _controller.updateNodeParams(nodeId, type, params);
      }
    }

    // 建立連線
    for (final conn in template.connections) {
      final fromIdx = conn['from'] as int;
      final toIdx = conn['to'] as int;
      final fromPort = conn['fromPort'] as String? ?? 'output';
      final toPort = conn['toPort'] as String? ?? 'input';

      final fromId = nodeIdMap[fromIdx];
      final toId = nodeIdMap[toIdx];
      if (fromId != null && toId != null) {
        await _controller.connect(fromId, fromPort, toId, toPort);
      }
    }

    // [教練 Agent 2026-07-23] 範本載入後自動置中
    if (mounted) {
      final size = context.size ?? const Size(800, 600);
      _controller.fitToContent(size);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已載入範本：${template.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    } finally {
      await _controller.endBatch();
    }
  }

  /// [教練 Agent 2026-07-22] Phase C — 依名稱載入範本（Agent 呼叫用）
  Future<void> _loadTemplateByName(String templateName) async {
    final templates = VaultTemplateService.instance.getBuiltinTemplates();
    final template = templates.where((t) => t.id == templateName).firstOrNull;
    if (template == null) {
      debugPrint('[CanvasV2] 範本不存在：$templateName');
      return;
    }

    // [教練 Agent 2026-08-15 批量載入] 同 _loadTemplate——一次寫入不卡 UI
    _controller.beginBatch();
    try {
    final nodeIdMap = <int, String>{};
    for (var i = 0; i < template.nodes.length; i++) {
      final nodeDef = template.nodes[i];
      final typeStr = nodeDef['type'] as String? ?? 'input';
      final x = (nodeDef['x'] as num?)?.toDouble() ?? 100.0 + i * 50;
      final y = (nodeDef['y'] as num?)?.toDouble() ?? 150.0;

      final type = _parseWorkflowNodeType(typeStr);
      final nodeId = await _controller.addWorkflowNode(type, Offset(x, y));
      nodeIdMap[i] = nodeId;

      final params = nodeDef['params'] as Map<String, dynamic>?;
      if (params != null) {
        _controller.updateNodeParams(nodeId, type, params);
      }
    }

    for (final conn in template.connections) {
      final fromIdx = conn['from'] as int;
      final toIdx = conn['to'] as int;
      final fromPort = conn['fromPort'] as String? ?? 'output';
      final toPort = conn['toPort'] as String? ?? 'input';

      final fromId = nodeIdMap[fromIdx];
      final toId = nodeIdMap[toIdx];
      if (fromId != null && toId != null) {
        await _controller.connect(fromId, fromPort, toId, toPort);
      }
    }

    // [教練 Agent 2026-07-24] 範本載入後自動縮放置中 + 寫入 CanvasSnapshot
    if (mounted) {
      final size = context.size ?? const Size(800, 600);
      _controller.fitToContent(size);
      // 人機共視：寫入 snapshot 到桌面，讓教練 Agent和原生 Agent都能讀到畫布狀態
      await _controller.writeSnapshotToFile(size);
    }
    } finally {
      await _controller.endBatch();
    }
  }

  /// [教練 Agent 2026-07-24] 公開方法 — 讓桌面 sidebar 呼叫啟動教學
  /// 重新顯示歡迎覆蓋層，讓使用者選擇教學模式
  Future<void> startInteractiveTutorial({bool isFirstVisit = false}) async {
    // [教練 Agent 2026-07-24] 強制重新顯示歡迎覆蓋層
    setState(() {
      _guideDismissed = false;
    });
  }

  /// [教練 Agent 2026-07-22] Phase 5+ 互動式教學
  /// 啟動教學——Agent 在對話框打招呼。
  /// [isFirstVisit] — 是否為第一次進入畫布
  Future<void> _startInteractiveTutorial({bool isFirstVisit = false}) async {
    // 注入動作回呼——讓教學服務能在畫布上建立節點和連線
    TemplateTutorialService.instance.onAddNode = (typeStr, x, y, params) async {
      final type = _parseWorkflowNodeType(typeStr);
      final nodeId = await _controller.addWorkflowNode(type, Offset(x, y));
      if (params != null) {
        _controller.updateNodeParams(nodeId, type, params);
      }
      return nodeId;
    };
    TemplateTutorialService.instance.onConnect = (fromId, fromPort, toId, toPort) {
      // [教練 Agent 2026-07-24] 不 await 但逐條呼叫——教學中連線量少（≤12），race 機率低
      _controller.connect(fromId, fromPort, toId, toPort);
    };
    // [教練 Agent 2026-07-23] Agent 發話時亮一下聊天框
    TemplateTutorialService.instance.onAgentSpeak = _flashChatHighlight;

    await TemplateTutorialService.instance.startTutorial(isFirstVisit: isFirstVisit);
  }

  /// 解析 WorkflowNodeType 字串
  WorkflowNodeType _parseWorkflowNodeType(String typeStr) {
    return switch (typeStr) {
      'input' => WorkflowNodeType.input,
      'llm' => WorkflowNodeType.llm,
      'tool' => WorkflowNodeType.tool,
      'imageGen' => WorkflowNodeType.imageGen,
      'vision' => WorkflowNodeType.vision, // [教練 Agent 2026-08-01]
      'characterLock' => WorkflowNodeType.characterLock, // [教練 Agent 2026-08-01]
      'videoGen' => WorkflowNodeType.videoGen,
      'musicGen' => WorkflowNodeType.musicGen,
      'tts' => WorkflowNodeType.tts,
      'condition' => WorkflowNodeType.condition,
      'merge' => WorkflowNodeType.merge,
      'output' => WorkflowNodeType.output,
      'subWorkflow' => WorkflowNodeType.subWorkflow,
      _ => WorkflowNodeType.input,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: BridgeDSColors.of(context).accentBlue),
      );
    }

    // [教練 Agent 2026-07-19] 人機共視：canvas（Stack）+ 對話框（CanvasChatPanel）並排
    // 對齊舊版 OpenCanvasWorkspace 的 Row 佈局，讓原生 Agent在畫布當下環境工作
    // [教練 Agent 2026-07-20] _repaintKey 移到包住整個 Row——截圖要包含畫布+工具列+對話框
    // [教練 Agent 2026-07-22] 加 KeyboardListener 攔截 Delete 鍵刪除選中節點
    return RepaintBoundary(
      key: _repaintKey,
      child: KeyboardListener(
        focusNode: _canvasFocusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Row(
      children: [
        Expanded(
          child: Stack(
            children: [
        // 主畫布
        Container(
            color: BridgeDSColors.of(context).canvas,
            child: GraphCanvas(
            controller: _controller,
            onNodeExecute: _executeSingleNode,
            nodeBuilder: (context, node, controller) {
              final props = node.entity.canvasProps;
              // [教練 Agent 2026-08-15 Phase 2.5-B] 拖曳連線中 → 計算型別相容的目標 port 集合
              Set<String>? compatiblePorts;
              final drag = controller.state.dragState;
              if (drag != null && props?.nodeType != null) {
                // 源 port 的型別（從源節點找）
                final sourceNode = controller.state.nodes[drag.fromNodeId];
                final sourcePortDef = sourceNode?.entity.canvasProps?.ports
                    .where((p) => p.name == drag.fromPortId)
                    .firstOrNull;
                if (sourcePortDef != null) {
                  // 目標方向：源是 output → 找 input port；源是 input → 找 output port
                  final wantOutput = !sourcePortDef.isOutput;
                  compatiblePorts = <String>{};
                  for (final p in (props?.ports ?? <PortDef>[])) {
                    if (p.isOutput != wantOutput) continue;
                    // 型別要匹配 + 不能是源節點自己
                    if (node.id == drag.fromNodeId) continue;
                    final match = drag.fromOutput
                        ? NodeConnection.isPortTypeMatch(sourcePortDef.dataType, p.dataType)
                        : NodeConnection.isPortTypeMatch(p.dataType, sourcePortDef.dataType);
                    if (match) {
                      compatiblePorts.add('${node.id}.${p.name}');
                    }
                  }
                }
              }
              return NodeWidget(
                nodeId: node.id,
                // [教練 Agent 2026-08-15 使用者 提案] 自訂標籤優先——
                // 「判斷風格」這種 label 直接顯示在節點卡片上，
                // 不用再點開面板才看得到。
                title: props?.params['label']?.toString().isNotEmpty == true
                    ? props!.params['label'].toString()
                    : (props?.nodeType != null
                        ? workflowNodeTypeLabel(props!.nodeType!)
                        : node.entity.title),
                nodeType: props?.nodeType,
                // [小葵 2026-09-24 Blue 令·定案圖組即時化] output 節點的
                // 圖組不再依賴「執行時寫入 params」——打開畫布就動態收集：
                // 沿連線走整條上游鏈收定稿（_lastImageB64/_lastImageUrl）。
                // 執行時寫回的 _galleryB64s 只當快取備援。
                params: () {
                  final p = Map<String, dynamic>.from(props?.params ?? {});
                  if (props?.nodeType == WorkflowNodeType.output) {
                    final b64s = <String>[];
                    final urls = <String>[];
                    _collectAncestorFinals(node.id, <String>{}, b64s, urls);
                    if (b64s.isNotEmpty) p['_galleryB64s'] = b64s;
                    if (urls.isNotEmpty) p['_galleryUrls'] = urls;
                  }
                  return p;
                }(),
                // [自維修 2026-08-27] ports 即時化——用 NodeTypePorts.portsFor 覆蓋持久化快照。
                // 舊快照是節點建立當下存的，v213+ 新增接頭（如 input.trigger）不會出現，
                // 導致前台接頭點/連線畫不出，與拓撲資料層人機共視分歧。
                ports: props?.nodeType != null
                    ? NodeTypePorts.portsFor(props!.nodeType!)
                    : (props?.ports ?? []),
                isSelected: controller.state.selectedNodeIds.contains(node.id),
                visualState: props?.visualState ?? CanvasVisualState.idle,
                onTap: () => controller.selectNode(node.id),
                onDoubleTap: () => _onNodeDoubleTap(node.id),
                onDelete: () => controller.removeNode(node.id),
                compatiblePorts: compatiblePorts,
                dimIncompatiblePorts: drag != null,
                onPortDragStart: (nodeId, portName, isInput, portKey) {
                  // [教練 Agent 2026-08-15 防雙重啟動] GraphCanvas 的 Listener 已在
                  // pointer-down 同步啟動 dragState（port 絕對優先）。
                  // 這裡只剩備援角色：dragState 已存在就什麼都不做，
                  // 否則第二次 startConnectionDrag 會洗掉 detachedConnectionId
                  // （斷線手勢會失效）。
                  if (controller.state.dragState != null) return;

                  final screenLocal = controller.portPositions['$nodeId:$portName'];
                  final worldPos = screenLocal != null
                      ? controller.state.viewport.screenToWorld(screenLocal)
                      : controller.state.viewport.screenToWorld(Offset.zero);
                  controller.startConnectionDrag(nodeId, portName, !isInput, worldPos);
                },
                onParamChanged: (key, value) {
                  final p = Map<String, dynamic>.from(props?.params ?? {});
                  p[key] = value;
                  controller.updateNodeParams(node.id, props?.nodeType, p);
                },
                // [教練 Agent 2026-08-16 使用者 抓包] inline 改標題失效——
                // 這裡一直沒接 onTitleChanged，_commitTitle 呼了 null 直接蒸發。
                // 工作流節點標題 = params['label']（顯示優先序的源頭），
                // 改標題就寫進 label。
                onTitleChanged: (newTitle) {
                  final p = Map<String, dynamic>.from(props?.params ?? {});
                  p['label'] = newTitle;
                  controller.updateNodeParams(node.id, props?.nodeType, p);
                },
              );
            },
            onDoubleTapEmpty: _onDoubleTapEmpty,
            onNodeDoubleTap: _onNodeDoubleTap,
            // [教練 Agent 2026-08-16 使用者 提案] Finder 拖檔進畫布——
            // 依副檔名分流：圖片→vision（圖片輸入）、文字/其他→input（內容注入）
            onFilesDropped: _onFilesDropped,
          ),
        ),

        // 塗鴉層 — viewport 值由 _onViewportChanged 回調更新
        if (_doodleVisible)
          Positioned.fill(
            child: CanvasDoodleLayer(
              strokes: _doodleStrokes,
              texts: _doodleTexts,
              viewportOffset: _controller.state.viewport.offset,
              viewportScale: _controller.state.viewport.scale,
              enabled: _doodleEnabled,
              visible: _doodleVisible,
              mode: _doodleMode,
              strokeColor: _doodleColor,
              strokeWidth: _doodleWidth,
              onStrokeAdded: (stroke) => setState(() => _doodleStrokes.add(stroke)),
              onStrokeRemoved: (index) => setState(() => _doodleStrokes.removeAt(index)),
              onTextAdded: (text) => setState(() => _doodleTexts.add(text)),
              onTextRemoved: (index) => setState(() => _doodleTexts.removeAt(index)),
              onColorPicked: (c) => setState(() => _doodleColor = c),
              onStrokeWidthChanged: (w) => setState(() => _doodleWidth = w),
              onScrollZoom: (scrollDelta, localPos) {
                final scale = _controller.state.viewport.scale;
                final newScale = scale * (scrollDelta > 0 ? 0.9 : 1.1);
                _controller.zoom(newScale, localPos);
              },
              onCanvasPan: (delta) {
                // 右鍵/中鍵拖曳平移畫布
                _controller.pan(delta);
              },
              onClear: () => setState(() {
                _doodleStrokes.clear();
                _doodleTexts.clear();
              }),
              onModeChanged: (mode) => setState(() => _doodleMode = mode),
              onTextMoved: (index, newWorldPos) => setState(() {
                _doodleTexts[index].worldPos = newWorldPos;
              }),
              onTextFontSizeChanged: (index, newFontSize) => setState(() {
                _doodleTexts[index].fontSize = newFontSize;
              }),
              onTextChanged: (index, newText, newFontSize) => setState(() {
                _doodleTexts[index].text = newText;
                _doodleTexts[index].fontSize = newFontSize;
              }),
              viewportListenable: _controller,
              viewportOffsetBuilder: () => _controller.state.viewport.offset,
              viewportScaleBuilder: () => _controller.state.viewport.scale,
            ),
          ),

        // 右側參數面板（舊版）
        // [教練 Agent 2026-08-15 使用者回饋] 移除顯示——與 NodeDetailPanel 資訊
        // 重複（雙擊開兩個面板左右並存）。統一由 Inspector 承擔。
        // if (_controller.state.editingNodeId != null)
        //   Positioned(
        //     right: 0,
        //     top: 0,
        //     bottom: 0,
        //     width: 300,
        //     child: _buildParamsPanel(),
        //   ),

        // 右側節點詳情面板 (Inspector Panel)
        // [教練 Agent 2026-08-15 使用者決策] 面板退役——標籤已上節點卡片
        // （params.label 優先顯示）、執行已進右鍵選單（執行此節點）、
        // 連線資訊畫布上看得到。Inspector 沒有存在價值，整段移除。

        // 工具列 — [教練 Agent 2026-07-23] 移除浮動工具列，
        // 功能已由最左側垂直 CanvasToolbar 統一提供
        // if (widget.showToolbar)
        //   Positioned(
        //     left: 16,
        //     top: 16,
        //     child: _buildToolbar(),
        //   ),

        // 底部狀態列
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          // [教練 Agent 2026-07-23] 用 AnimatedBuilder 包住，
          // 讓縮放百分比即時跟著 controller 重建
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => _buildStatusBar(),
          ),
        ),

        // 空狀態引導覆蓋層
        // [教練 Agent 2026-07-24] 放寬條件：只要 _guideDismissed=false 就顯示（讓教學入口也能觸發）
        if (!_guideDismissed)
          _buildEmptyStateGuide(context),
            ],  // Stack children
          ),  // Stack
        ),  // Expanded
        // [教練 Agent 2026-08-16 使用者 提案] 對話框折疊收右——
        // 折疊時只剩 32px 窄軌貼右（chevron 展開），畫布拿回全部空間
        if (widget.chatCollapsed)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onChatCollapseToggle,
              child: Tooltip(
                message: '展開對話框',
                waitDuration: const Duration(milliseconds: 400),
                child: Container(
                  width: 32,
                  color: BridgeDSColors.of(context).canvas,
                  alignment: Alignment.center,
                  child: Icon(Icons.chevron_left,
                      size: 18,
                      color: BridgeDSColors.of(context).textMuted),
                ),
              ),
            ),
          )
        else ...[
        // [教練 Agent 2026-08-16 使用者 提案] 對話框折疊鈕——收到右邊
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onChatCollapseToggle,
            child: Tooltip(
              message: '收起對話框',
              waitDuration: const Duration(milliseconds: 400),
              child: Container(
                width: 20,
                color: BridgeDSColors.of(context).canvas,
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 8),
                child: Icon(Icons.chevron_right,
                    size: 16,
                    color: BridgeDSColors.of(context).textMuted),
              ),
            ),
          ),
        ),
        // 拖曳分隔條 — 調整聊天框寬度
        // [W4.7c Blue 令 2026-10-09] 共用元件：常態灰色、拖曳中整條變紫
        PurpleDragHandle(
          color: BridgeDSColors.of(context).accentPurple,
          trackColor: BridgeDSColors.of(context).borderSubtle,
          onDrag: (delta) {
            // [W4.7 Blue 令 2026-10-09] 最小值 240→320——太小時輸入框元件
            // 溢出（黑黃警示條），320 是不溢出的實測下限
            final newWidth = (widget.chatWidth - delta).clamp(320.0, 600.0);
            widget.onChatWidthChanged?.call(newWidth);
          },
        ),
        // [教練 Agent 2026-07-19] 人機共視對話框——讓原生 Agent在畫布當下環境工作
        // [教練 Agent 2026-07-22] Phase 5+ 教學：攔截 onControllerReady 注入教學服務
        // [教練 Agent 2026-07-23] Agent 發話時聊天框外圍亮一下
        ValueListenableBuilder<bool>(
          valueListenable: _chatHighlight,
          builder: (context, highlight, child) {
            final ds = BridgeDSColors.of(context);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                border: highlight
                    ? Border.all(
                        color: ds.accentBlue.withValues(alpha: 0.6),
                        width: 2,
                      )
                    : Border.all(
                        color: ds.borderSubtle.withValues(alpha: 0.3),
                        width: 1,
                      ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: highlight
                    ? [
                        BoxShadow(
                          color: ds.accentBlue.withValues(alpha: 0.15),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: child!,
            );
          },
          child: SizedBox(
            width: widget.chatWidth,
            child: CanvasChatPanel(
              mcpCanvasExecutor: widget.mcpCanvasExecutor, // [v212] 畫布主控工具
              canvasId: _canvasId,
              onControllerReady: (controller) {
                // [教練 Agent 2026-08-15] 存住畫布頁對話框 controller——
                // 測試按鈕注入報告用（是畫布頁的 CanvasChatPanel，不是主對話頁）
                _chatController = controller;
                // 注入教學服務
                TemplateTutorialService.instance.setChatController(controller);
                // [教練 Agent 2026-07-22] Phase B — 接上畫布快照服務
                CanvasSnapshotService.instance.attach(_controller, canvasId: _canvasId);
                CanvasSnapshotService.instance.onInject = (description, {required isFull}) {
                  controller.injectCanvasSystemMessage(description, isFull: isFull);
                };
                widget.onChatControllerReady?.call(controller);
              },
              selfCaptureKey: widget.selfCaptureKey,
            ),
          ),
        ),
        ],  // else ...[ 折疊時的分隔條+對話框群組
      ],  // Row children
      ),  // Row
      ),  // KeyboardListener
    );  // RepaintBoundary
  }

  // ── UI 元件 ───────────────────────────────────────────

  // [教練 Agent 2026-07-23] 清空畫布確認對話框（public — 供 desktop screen 工具列呼叫）
  Future<void> showClearCanvasConfirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: BridgeDS.orange700, size: 24),
            const SizedBox(width: 8),
            const Text('清空畫布'),
          ],
        ),
        content: Text(
          '這將移除畫布上所有節點與連線（共 ${_controller.state.nodes.length} 個節點、'
          '${_controller.state.connections.length} 條連線）。\n\n此操作無法復原。',
          style: TextStyle(color: BridgeDSColors.of(context).textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('清空'),
            style: FilledButton.styleFrom(
              backgroundColor: BridgeDS.red700mat,
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _controller.clearCanvas();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: const Text('畫布已清空'),
            duration: const Duration(seconds: 2),
            backgroundColor: BridgeDSColors.of(context).accentGreen,
          ),
        );
      }
    }
  }

  // [教練 Agent 2026-08-06] 已改響應式（手機簡化），預備給未來重新啟用
  // ignore: unused_element
  Widget _buildToolbar() {
    final state = _controller.state;
    final responsive = CanvasResponsiveHelper.of(context); // [教練 Agent 2026-08-06] 響應式工具列
    final toolbarSize = responsive.toolbarButtonSize;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.isMobile ? 4 : 8,
        vertical: responsive.isMobile ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // [教練 Agent 2026-07-23] Undo / Redo — 最上方
          _ToolButton(
            icon: Icons.undo,
            label: responsive.isMobile ? '上' : '上一步',
            isActive: false,
            size: toolbarSize,
            onTap: _controller.canUndo ? () => _controller.undo() : null,
          ),
          _ToolButton(
            icon: Icons.redo,
            label: responsive.isMobile ? '下' : '下一步',
            isActive: false,
            size: toolbarSize,
            onTap: _controller.canRedo ? () => _controller.redo() : null,
          ),
          const SizedBox(width: 4),
          _ToolButton(
            icon: Icons.navigation,
            label: '選取',
            isActive: state.activeTool == CanvasTool2.select,
            size: toolbarSize,
            onTap: () => _controller.setTool(CanvasTool2.select),
          ),
          _ToolButton(
            icon: Icons.power_input,
            label: '連線',
            isActive: state.activeTool == CanvasTool2.connect,
            size: toolbarSize,
            onTap: () => _controller.setTool(CanvasTool2.connect),
          ),
          const SizedBox(width: 4),
          _ToolButton(
            icon: Icons.edit_outlined,
            label: '塗鴉',
            isActive: _doodleEnabled,
            size: toolbarSize,
            onTap: toggleDoodle,
          ),
          _ToolButton(
            icon: Icons.add_box_outlined,
            label: '新增',
            isActive: false,
            onTap: () {
              final vp = state.viewport;
              final center = vp.screenToWorld(
                Offset(MediaQuery.of(context).size.width / 2,
                    MediaQuery.of(context).size.height / 2),
              );
              _onDoubleTapEmpty(
                Offset(MediaQuery.of(context).size.width / 2,
                    MediaQuery.of(context).size.height / 2),
                center,
              );
            },
          ),
          _ToolButton(
            icon: Icons.delete_outline,
            label: '刪除',
            isActive: false,
            onTap: state.selectedNodeIds.isEmpty
                ? null
                : () {
                    // [教練 Agent 2026-07-23] 一次刪除所有選中節點
                    _controller.removeSelectedNodes();
                  },
          ),
          // [教練 Agent 2026-07-23] 清空畫布 — 帶確認對話框
          _ToolButton(
            icon: Icons.cleaning_services_outlined,
            label: '清空',
            isActive: false,
            onTap: state.nodes.isEmpty
                ? null
                : () => showClearCanvasConfirm(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final state = _controller.state;
    final responsive = CanvasResponsiveHelper.of(context); // [教練 Agent 2026-08-06] 響應式狀態列
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.isMobile ? 8 : 16,
        vertical: responsive.isMobile ? 3 : 6,
      ),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas,
        border: Border(top: BorderSide(color: BridgeDSColors.of(context).borderDefault)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: responsive.isMobile ? 6 : 8, color: BridgeDSColors.of(context).accentBlue),
          SizedBox(width: responsive.isMobile ? 4 : 8),
          Flexible(
            child: Text(
              '${state.nodes.length} 節點 · ${state.connections.length} 連線',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          // 存檔按鈕
          GestureDetector(
            onTap: _isSaving ? null : _onSave,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSaving)
                    SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(BridgeDSColors.of(context).accentGreen)))
                  else
                    Icon(Icons.save_outlined, color: BridgeDSColors.of(context).accentGreen, size: 14),
                  const SizedBox(width: 4),
                  Text('存檔', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentGreen, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 另存新檔按鈕
          GestureDetector(
            onTap: _isSaving ? null : _onSaveAs,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.save_as_outlined, color: BridgeDSColors.of(context).accentBlue, size: 14),
                  const SizedBox(width: 4),
                  Text('另存', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentBlue, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // [教練 Agent 2026-08-15 使用者 提案] 測試按鈕——零 token 靜態分析
          GestureDetector(
            onTap: _runStaticTest,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bug_report_outlined, color: BridgeDSColors.of(context).accentYellow, size: 14),
                  const SizedBox(width: 4),
                  Text('測試', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentYellow, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 執行按鈕
          GestureDetector(
            onTap: _isExecuting ? null : () async {
              setState(() => _isExecuting = true);
              try {
                // [教練 Agent 2026-08-01] 不再阻塞等存檔對話框 — 直接執行 DAG
                // 存檔改為背景執行（不 await）
                _onSave();
                // 直接執行工作流
                await _executeWorkflow();
              } catch (e) {
                debugPrint('[CanvasV2] 執行失敗: $e');
                if (mounted) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(
                      content: Text('執行失敗: $e'),
                      backgroundColor: BridgeDSColors.of(context).accentRed,
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _isExecuting = false);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isExecuting)
                    SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(BridgeDSColors.of(context).accentBlue)))
                  else
                    Icon(Icons.play_arrow_outlined, color: BridgeDSColors.of(context).accentBlue, size: 14),
                  const SizedBox(width: 4),
                  Text('執行', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentBlue, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text(
            '縮放 ${(state.viewport.scale * 100).round()}%',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
          ),
          const SizedBox(width: 16),
          if (state.selectedNodeIds.isNotEmpty)
            Text(
              '已選 ${state.selectedNodeIds.length}',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentBlue,),
            ),
        ],
      ),
    );
  }

  Widget _buildParamsPanel() {
    final node = _controller.state.nodes[_controller.state.editingNodeId];
    if (node == null) return const SizedBox.shrink();

    final props = node.entity.canvasProps;
    final nodeType = props?.nodeType;
    final params = Map<String, dynamic>.from(props?.params ?? {});

    return Container(
      color: BridgeDSColors.of(context).canvas,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題
            Row(
              children: [
                Text(
                  nodeType != null ? workflowNodeTypeLabel(nodeType) : '一般節點',
                  style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: BridgeDS.hintPurple, size: 18),
                  onPressed: () => _controller.stopEditing(),
                ),
              ],
            ),
            Divider(color: BridgeDS.dividerIndigo),
            const SizedBox(height: 8),

            // 節點資訊
            _InfoRow('ID', node.id),
            _InfoRow('類型', node.entity.type.name),
            if (nodeType != null) ...[
              _InfoRow('工作流類型', nodeType.name),
              const SizedBox(height: 16),

              // 參數編輯（根據 nodeType）
              Text('參數', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentBlue,)),
              const SizedBox(height: 8),
              ..._buildParamEditors(nodeType, params, node.id),
            ],

            const SizedBox(height: 24),

            // 埠資訊
            if (props != null && props.ports.isNotEmpty) ...[
              Text('連接埠', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentBlue,)),
              const SizedBox(height: 8),
              ...props.ports.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      p.isOutput ? Icons.arrow_forward : Icons.arrow_back,
                      size: 14,
                      color: p.isOutput ? BridgeDSColors.of(context).accentBlue : BridgeDS.orange300,
                    ),
                    const SizedBox(width: 8),
                    Text(p.name, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: Colors.white70,)),
                    const SizedBox(width: 8),
                    Text(p.dataType.name, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: Colors.white.withValues(alpha: 0.3),)),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildParamEditors(WorkflowNodeType nodeType, Map<String, dynamic> params, String nodeId) {
    final editors = <Widget>[];

    for (final entry in params.entries) {
      editors.add(_ParamEditor(
        label: _paramLabel(entry.key),
        value: entry.value,
        paramKey: entry.key,
        onChanged: (value) {
          params[entry.key] = value;
          _controller.updateNodeParams(nodeId, nodeType, params);
        },
      ));
      editors.add(const SizedBox(height: 8));
    }

    return editors;
  }

  String _paramLabel(String key) {
    const labels = {
      'model': '模型',
      'prompt': '提示詞',
      'temperature': '溫度',
      'maxTokens': '最大 Token',
      'toolName': '工具名稱',
      'args': '參數',
      'source': '來源',
      'content': '內容',
      'size': '尺寸',
      'seed': '種子',
      'duration': '時長',
      'text': '文字',
      'voice': '語音',
      'speed': '語速',
      'condition': '條件',
      'mode': '模式',
      'displayMode': '顯示模式',
      'label': '標籤',
      'workflowId': '工作流 ID',
    };
    return labels[key] ?? key;
  }

  Widget _buildEmptyStateGuide(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    
    return Positioned.fill(
      child: Container(
        color: colors.canvas.withValues(alpha: 0.85),
        child: Center(
          child: Container(
            width: 480,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
              border: Border.all(
                color: colors.borderDefault,
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 標題
                Text(
                  '畫布工作區',
                  style: TierStyle.of(context, Tier.appTitle).toTextStyle().copyWith(color: colors.textPrimary,
                    fontWeight: FontWeight.bold,),
                ),
                const SizedBox(height: 12),
                
                // 說明
                Text(
                  '雙擊空白處新增節點，或從左側 Vault 側欄搜尋條目送至畫布',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted,),
                ),
                const SizedBox(height: 24),
                
                // 三個步驟
                _buildStep('📥', '新增輸入節點', '定義資料來源', colors),
                const SizedBox(height: 16),
                _buildStep('🧠', '連接處理節點', 'LLM推論、工具呼叫等', colors),
                const SizedBox(height: 16),
                _buildStep('📤', '連接輸出節點', '收集結果', colors),
                
                const SizedBox(height: 32),
                
                // 三個選項按鈕——統一層級：Primary + Secondary×2
                // [設計基礎 §5.2] Primary = FilledButton accentBlue, Secondary = TextButton
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 預選感——淺藍底黑字，像 hover/selected 狀態
                      // [設計基礎 §6.1] accentBlue + selectedOverlay 疊加
                      FilledButton(
                        onPressed: () {
                          _welcomeShownThisSession = true;
                          setState(() => _guideDismissed = true);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.accentBlue.withOpacity(0.15),
                          foregroundColor: colors.textPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: BridgeDS.spaceLG,
                            vertical: BridgeDS.spaceMD,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
                          ),
                        ),
                        child: Text(
                          '空白畫布',
                          style: TierStyle.of(context, Tier.buttonPrimary).toTextStyle(),
                        ),
                      ),
                      const SizedBox(width: BridgeDS.spaceSM),
                      // Secondary——選擇範本
                      TextButton(
                        onPressed: () async {
                          _welcomeShownThisSession = true;
                          setState(() => _guideDismissed = true);
                          await _showTemplatePickerAndStartTutorial();
                          _flashChatHighlight();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: colors.textSecondary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: BridgeDS.spaceLG,
                            vertical: BridgeDS.spaceMD,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
                          ),
                        ),
                        child: Text(
                          '選擇範本',
                          style: TierStyle.of(context, Tier.buttonSecondary).toTextStyle(),
                        ),
                      ),
                      const SizedBox(width: BridgeDS.spaceSM),
                      // Secondary——互動教學（用 icon 區分，不用顏色）
                      TextButton.icon(
                        onPressed: () {
                          _welcomeShownThisSession = true;
                          setState(() => _guideDismissed = true);
                          _startInteractiveTutorial(isFirstVisit: false);
                          _flashChatHighlight();
                        },
                        icon: Icon(Icons.school_outlined, size: BridgeDS.iconSm),
                        label: Text(
                          '互動教學',
                          style: TierStyle.of(context, Tier.buttonSecondary).toTextStyle(),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.textSecondary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: BridgeDS.spaceLG,
                            vertical: BridgeDS.spaceMD,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
                          ),
                        ),
                      ),
                      const SizedBox(width: BridgeDS.spaceSM),
                      // [刀 5 D5.3 2026-09-08] 示範錄製——我做一遍，橋樑記住
                      TextButton.icon(
                        onPressed: _startRoutineRecording,
                        icon: Icon(
                          _routineRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                          size: BridgeDS.iconSm,
                          color: _routineRecording ? colors.accentRed : colors.textSecondary,
                        ),
                        label: Text(
                          _routineRecording ? '停止並存範本' : '錄製範本',
                          style: TierStyle.of(context, Tier.buttonSecondary).toTextStyle(),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.textSecondary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: BridgeDS.spaceLG,
                            vertical: BridgeDS.spaceMD,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(String emoji, String title, String description, BridgeDSColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          emoji,
          style: TierStyle.of(context, Tier.appHeadline).toTextStyle(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textPrimary,
                  fontWeight: FontWeight.w600,),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textTertiary,),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 小元件 ────────────────────────────────────────────────

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap; // [教練 Agent 2026-07-22] 改為 nullable 支援 disabled 狀態
  final double? size; // [教練 Agent 2026-08-06] 響應式按鈕大小

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final btnSize = size ?? 38; // [教練 Agent 2026-08-06] 預設桌面大小
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: btnSize > 38 ? 12 : 8,
          vertical: btnSize > 38 ? 8 : 4,
        ),
        decoration: BoxDecoration(
          color: isActive ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: btnSize > 38 ? 20 : 16, color: disabled
                ? BridgeDSColors.of(context).textMuted.withValues(alpha: 0.3)
                : isActive ? BridgeDSColors.of(context).accentBlue : BridgeDSColors.of(context).textMuted),
            SizedBox(height: btnSize > 38 ? 3 : 2),
            Text(label, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: isActive ? BridgeDSColors.of(context).accentBlue : BridgeDSColors.of(context).textMuted,)),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDS.hintPurple,)),
          ),
          Expanded(child: Text(value, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: Colors.white70,))),
        ],
      ),
    );
  }
}

class _ParamEditor extends StatelessWidget {
  final String label;
  final dynamic value;
  final String paramKey;
  final ValueChanged<dynamic> onChanged;

  const _ParamEditor({
    required this.label,
    required this.value,
    required this.paramKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 數字 → 數字輸入
    if (value is num) {
      return Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDS.hintPurple,))),
          Expanded(
            child: TextFormField(
              initialValue: value.toString(),
              keyboardType: TextInputType.number,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
              decoration: _inputDecoration,
              onChanged: (v) {
                final n = num.tryParse(v);
                if (n != null) onChanged(n);
              },
            ),
          ),
        ],
      );
    }

    // 布林 → 開關
    if (value is bool) {
      return Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDS.hintPurple,))),
          Switch(
            value: value as bool,
            activeColor: BridgeDSColors.of(context).accentBlue,
            onChanged: onChanged,
          ),
        ],
      );
    }

    // 字串 → 文字輸入
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDS.hintPurple,))),
        Expanded(
          child: TextFormField(
            initialValue: value?.toString() ?? '',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
            decoration: _inputDecoration,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  static final _inputDecoration = InputDecoration(
    filled: true,
    fillColor: BridgeDS.darkCanvas,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  );
}


// ─────────────────────────────────────────────────────────────
// [W4.7c Blue 令 2026-10-09] 可拖分隔條（全 App 統一）：
// 常態＝灰色細線；抓取拖曳中＝整條 4px 變紫發光（抓到線的回饋）。
// ─────────────────────────────────────────────────────────────
class PurpleDragHandle extends StatefulWidget {
  final Color color;
  final Color trackColor;
  final void Function(double delta) onDrag;

  const PurpleDragHandle({
    super.key,
    required this.color,
    required this.trackColor,
    required this.onDrag,
  });

  @override
  State<PurpleDragHandle> createState() => _PurpleDragHandleState();
}

class _PurpleDragHandleState extends State<PurpleDragHandle> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 4,
          decoration: BoxDecoration(
            color: _dragging
                ? widget.color.withValues(alpha: 0.9)
                : widget.trackColor,
            boxShadow: _dragging
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}
