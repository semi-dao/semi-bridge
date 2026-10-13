// canvas_mcp_registry.dart
// 共視層的全域接點 — 讓 MCP Server 能存取畫布狀態和操作 App。
//
// 設計：
// - Desktop screen 在 initState 時註冊 navigate 和 chat 回調
// - CanvasV2Workspace 建構時注入 controller
// - MCP Server 透過這個 registry 間接呼叫，不直接持有任何 widget

import 'package:flutter/material.dart';
import 'package:bridge_app/models/entity_graph/open_canvas_node.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'canvas_controller.dart';
import 'canvas_state.dart';

/// 全域共視 registry — MCP Server 和 App 之間的橋樑
class CanvasMcpRegistry {
  CanvasMcpRegistry._();
  static final CanvasMcpRegistry instance = CanvasMcpRegistry._();

  /// [隊友訊息流 C1 2026-09-08] 前景 controller（CanvasV2Workspace 注入）
  CanvasController? _foregroundController;

  /// [隊友訊息流 C1 2026-09-08] ambient 覆寫堆疊——派工任務的工作畫布。
  ///
  /// 派工期間 canvas_* 工具呼叫自動路由到任務自己的 headless 工作畫布，
  /// 不污染使用者正在看的畫布（不中斷鐵則 + 工作畫布機制，設計稿 §4.2/§5.2）。
  /// 堆疊式而非單值：多任務並行時先進後出，任務結束 pop 還原。
  final List<CanvasController> _ambientOverrides = [];

  /// 由 CanvasV2Workspace 注入（前景畫布）
  set controller(CanvasController? ctrl) => _foregroundController = ctrl;

  /// canvas_* 工具讀取點——ambient 有覆寫走任務工作畫布，否則走前景畫布。
  /// 所有既有讀取點零改動即獲得工作畫布路由能力。
  CanvasController? get controller =>
      _ambientOverrides.isNotEmpty ? _ambientOverrides.last : _foregroundController;

  /// [隊友訊息流 C1] 派工開始——推入任務工作畫布（headless CanvasController）
  void pushAmbientCanvas(CanvasController taskController) {
    _ambientOverrides.add(taskController);
  }

  /// [隊友訊息流 C1] 派工結束——彈出工作畫布。必須與 push 成對；
  /// 傳入的 controller 不是堆疊頂端時仍移除該實例（防洩漏優先於順序純潔）。
  void popAmbientCanvas(CanvasController taskController) {
    _ambientOverrides.remove(taskController);
  }

  /// [隊友訊息流 C1] 目前是否在任務工作畫布模式（診斷用）
  bool get hasAmbientOverride => _ambientOverrides.isNotEmpty;

  /// [隊友訊息流 C1] 前景畫布原體——workspace dispose 判斷用。
  /// （ambient 覆寫期間 controller getter 回傳任務畫布，若拿它比對會漏清前景）
  CanvasController? get foregroundController => _foregroundController;

  /// 由 BridgeDesktopScreen 注入 — 切到畫布 tab
  void Function()? onNavigateToCanvas;

  /// [教練 Agent 2026-08-20] 由 BridgeDesktopScreen 注入 — 大腦搜尋放大對焦
  void Function(String query)? onBrainSearchFocus;

    /// 由 BridgeDesktopScreen 注入 — 在對話框發送訊息
  void Function(String message, {String? role})? onSendChatMessage;

  /// 由 BridgeDesktopScreen 注入 — 取得所有畫布列表
  List<Map<String, dynamic>> Function()? onListCanvases;

  /// 由 BridgeDesktopScreen 注入 — 載入指定畫布
  void Function(String canvasId)? onLoadCanvas;

  /// 由 CanvasV2Workspace 注入 — 截圖（base64 PNG）
  Future<String> Function()? onScreenshot;

  /// 由 CanvasV2Workspace 注入 — 取得塗鴉標注
  List<Map<String, dynamic>> Function()? onGetAnnotations;

  /// 由 CanvasV2Workspace 注入 — 執行工作流
  Future<void> Function()? onExecute;

  /// [開光 P2 · 小葵 2026-09-26] app_tap——畫布工具列語意點擊
  /// 由 CanvasV2Workspace 注入：save/copy(另存)/test(靜態測試)/run(執行)
  Map<String, dynamic> Function(String button)? onTapButton;

  /// [教練 Agent 2026-07-20] 渲染感應器——原生 Agent回覆時觸發，讓外部觀察者知道
  void Function(String content)? onAgentReply;

  /// [教練 Agent 2026-07-20] 快取最新回覆——供 MCP /get_latest_messages 端點讀取
  String? _lastAgentReply;
  String get lastAgentReply => _lastAgentReply ?? '';
  void setLastAgentReply(String content) => _lastAgentReply = content;

  /// [小葵 2026-09-16 Blue 令] 跨頁面行動日誌——解決「兩個小橋互不相識」。
  /// 病例：chat 頁小橋幫 Blue 建了排程節點 → Blue 切到 canvas 頁，
  /// 同一個 agent 卻說「注意到一個沒見過的節點」——它不知道那是自己建的。
  /// 修：所有 canvas 寫操作成功後記入 ring buffer（最近 30 條），
  /// canvas 對話組 context 前注入，讓 agent 帶著自己的行動記憶。
  final List<String> _canvasActionLog = [];
  static const int _canvasActionLogMax = 30;

  /// [小葵 2026-09-16 Blue 令] 操作者標記——agent 工具入口操作前設 true，
  /// CanvasSnapshotService 據此人稱（「你（小橋）」vs「使用者」），用完即清。
  bool _lastActorIsAgent = false;
  bool consumeLastActorIsAgent() {
    final v = _lastActorIsAgent;
    _lastActorIsAgent = false;
    return v;
  }
  void markNextEventFromAgent() => _lastActorIsAgent = true;

  void logCanvasAction(String action) {
    final ts = DateTime.now().toString().substring(11, 19);
    _canvasActionLog.add('[$ts] $action');
    if (_canvasActionLog.length > _canvasActionLogMax) {
      _canvasActionLog.removeAt(0);
    }
  }

  /// 最近行動日誌（供 prompt 注入）。max=null 全部。
  String recentCanvasActions({int? max}) {
    if (_canvasActionLog.isEmpty) return '';
    final list = max == null
        ? _canvasActionLog
        : _canvasActionLog.sublist(
            ( _canvasActionLog.length - max).clamp(0, _canvasActionLog.length));
    return '你（小橋）最近的畫布操作：\n${list.join('\n')}';
  }


  bool get isCanvasReady => controller != null;

  /// 取得畫布狀態 JSON
  Map<String, dynamic> getCanvasState() {
    final ctrl = controller;
    if (ctrl == null) {
      return {'error': 'Canvas not ready', 'canvasConnected': false};
    }
    final state = ctrl.state;
    return {
      'nodes': state.nodes.values.map((n) {
        final props = n.entity.canvasProps;
        return {
          'id': n.id,
          'title': props?.nodeType != null
              ? workflowNodeTypeLabel(props!.nodeType!)
              : n.entity.title,
          'type': n.entity.type.name,
          'nodeType': props?.nodeType?.name,
          'position': {'x': n.position.dx, 'y': n.position.dy},
          'size': {'width': n.width, 'height': n.height},
          'params': props?.params ?? {},
          // [MimeMi 自修復 2026-09-02] ports 即時化——用 NodeTypePorts.portsFor 覆蓋持久化舊快照，
          // 與前台 canvas_v2_workspace.dart 同一份真相（v213 加的 input.trigger 才會出現在 MCP 端）
          'ports': (props?.nodeType != null
                  ? NodeTypePorts.portsFor(props!.nodeType!)
                  : (props?.ports ?? []))
              .map((p) => {
            'name': p.name,
            'dataType': p.dataType.name,
            'isOutput': p.isOutput,
          }).toList(),
          'visualState': props?.visualState.name ?? 'idle',
          'isSelected': state.selectedNodeIds.contains(n.id),
        };
      }).toList(),
      'connections': state.connections.map((c) => {
        'id': c.id,
        'from': {'nodeId': c.fromNodeId, 'port': c.fromPortId},
        'to': {'nodeId': c.toNodeId, 'port': c.toPortId},
      }).toList(),
      'viewport': {
        'offsetX': state.viewport.offset.dx,
        'offsetY': state.viewport.offset.dy,
        'scale': state.viewport.scale,
      },
      'selectedNodeIds': state.selectedNodeIds.toList(),
      'activeTool': state.activeTool.name,
      'nodeCount': state.nodes.length,
      'connectionCount': state.connections.length,
      // [教練 Agent 2026-08-22] 場景感知——canvas_look 要算 viewport 可見範圍
      if (canvasPixelSize != null)
        'canvasPixelSize': {
          'width': canvasPixelSize!.width,
          'height': canvasPixelSize!.height,
        },
      'canvasConnected': true,
    };
  }

  /// Agent 主動打開畫布 tab + 在對話框說話
  void navigateToCanvas() {
    onNavigateToCanvas?.call();
  }

  /// [收據搜尋 S3 2026-09-08] 把資產匯入畫布——放置 output 節點（帶 asset 引用）。
  /// [canvasId] null=開新畫布（onCanvasCreated 回報新 ID）。
  /// 實作：走 ambient controller 堆疊頂（目前打開的畫布）——與 canvas_place_node
  /// MCP 工具同一條正宮路徑，不開旁門。
  Future<void> importAssetToCanvas({
    required String assetId,
    String? canvasId,
    void Function(String canvasId)? onCanvasCreated,
  }) async {
    // 有指定 canvasId → 先載入該畫布（loadCanvas 是 async 完成後才放置）
    if (canvasId != null) {
      onLoadCanvas?.call(canvasId);
      // 等 workspace 完成載入（loadCanvas 內部 swap controller；給短暫時間）
      await Future.delayed(const Duration(milliseconds: 400));
    }
    final ctrl = controller;
    if (ctrl == null) {
      debugPrint('[S3] importAssetToCanvas：無可用 controller（畫布未開）');
      return;
    }
    await ctrl.addWorkflowNode(
      WorkflowNodeType.output,
      const Offset(480, 360),
    ).then((nodeId) {
      ctrl.updateNodeParams(nodeId, WorkflowNodeType.output, {
        'label': '搜尋結果匯入',
        '_isAssetResult': true,
        '_assetId': assetId,
      });
    });
  }

  /// Agent 在對話框發送訊息
  void sendChatMessage(String message, {String? role}) {
    onSendChatMessage?.call(message, role: role);
  }

  /// 列出所有畫布
  List<Map<String, dynamic>> listCanvases() {
    return onListCanvases?.call() ?? [];
  }

  /// 載入指定畫布
  void loadCanvas(String canvasId) {
    onLoadCanvas?.call(canvasId);
  }

  /// 截圖 — 回傳 base64 PNG
  Future<String?> screenshot() async {
    return await onScreenshot?.call();
  }

  /// 取得塗鴉標注
  List<Map<String, dynamic>> getAnnotations() {
    return onGetAnnotations?.call() ?? [];
  }

  // ── [教練 Agent 2026-07-22] Phase C — Agent 快捷操作 ──────────

  /// 一鍵載入範本
  void Function(String templateName)? onLoadTemplate;
  void loadTemplate(String templateName) {
    onLoadTemplate?.call(templateName);
  }

  /// 高亮節點（閃爍）
  void Function(String nodeId)? onHighlightNode;
  void highlightNode(String nodeId) {
    onHighlightNode?.call(nodeId);
  }

  /// 平移畫布到節點
  void Function(String nodeId)? onPanToNode;
  void panToNode(String nodeId) {
    onPanToNode?.call(nodeId);
  }

  // ── [教練 Agent 2026-07-24] 人機共視 — CanvasSnapshot ──────────

  /// 畫布像素大小（由 CanvasV2Workspace 注入）
  Size? canvasPixelSize;

  /// 取得 CanvasSnapshot JSON
  Map<String, dynamic> getSnapshot() {
    final ctrl = controller;
    if (ctrl == null) {
      return {'error': 'Canvas not ready', 'canvasConnected': false};
    }
    final size = canvasPixelSize ?? const Size(1060, 772);
    final snapshot = ctrl.getSnapshot(size);
    return snapshot.toJson();
  }

  /// 取得 CanvasSnapshot 文字報告
  String getSnapshotReport() {
    final ctrl = controller;
    if (ctrl == null) return 'Canvas not ready';
    final size = canvasPixelSize ?? const Size(1060, 772);
    return ctrl.getSnapshot(size).toReport();
  }

  /// 移動節點
  bool moveNode(String nodeId, double x, double y) {
    final ctrl = controller;
    if (ctrl == null) return false;
    ctrl.moveNode(nodeId, Offset(x, y));
    return true;
  }

  /// [教練 Agent 2026-08-26 使用者 基礎規則] 一鍵自動排版——
  /// 依連線拓撲分層：無上游=第 0 層，其餘=最長上游路徑+1。
  /// 層內垂直均分、層間水平 340 間距。人看的故事線=左到右。
  Map<String, dynamic> autoLayout() {
    final ctrl = controller;
    if (ctrl == null) return {'moved': 0, 'error': 'controller 未連接'};

    final nodes = ctrl.state.nodes;
    final conns = ctrl.state.connections;

    // 建鄰接：from → to
    final downstream = <String, Set<String>>{};
    final upstream = <String, Set<String>>{};
    for (final c in conns) {
      downstream.putIfAbsent(c.fromNodeId, () => {}).add(c.toNodeId);
      upstream.putIfAbsent(c.toNodeId, () => {}).add(c.fromNodeId);
    }

    // 計算每節點深度（最長路徑），防環
    final depth = <String, int>{};
    int calcDepth(String id, Set<String> visiting) {
      if (depth.containsKey(id)) return depth[id]!;
      if (visiting.contains(id)) return 0; // 環保護
      visiting.add(id);
      var d = 0;
      for (final up in upstream[id] ?? const <String>{}) {
        final ud = calcDepth(up, visiting);
        if (ud + 1 > d) d = ud + 1;
      }
      visiting.remove(id);
      depth[id] = d;
      return d;
    }

    for (final id in nodes.keys) {
      calcDepth(id, <String>{});
    }

    // 分層
    final layers = <int, List<String>>{};
    for (final entry in depth.entries) {
      layers.putIfAbsent(entry.value, () => []).add(entry.key);
    }
    final sortedLayers = layers.keys.toList()..sort();

    // [v220 Blue 美感令] 乾淨對稱的分層排版（Sugiyama 風格簡化版）——
    // 人看的故事線=清晰的左到右，層內垂直對齊，連線不交叉不壓節點：
    // 1) 層內排序按下游質心（下游節點在哪層排哪，連線自然少交叉）
    // 2) x 間距自適應：前一層最寬節點 + 呼吸空間 160
    // 3) 層內 y 等距 240，區塊垂直置中於畫布質心，節點中心線對齊
    // 4) 排完垂直置中一次到位（每層獨立置中=層間也對稱）
    var moved = 0;
    final center = nodes.isEmpty
        ? 300.0
        : nodes.values.map((n) => n.position.dy).reduce((a, b) => a + b) /
            nodes.length;

    // 先按下游質心決定每層內部順序（barycenter，兩輪強化）
    for (var pass = 0; pass < 2; pass++) {
      final directionDown = pass == 0;
      final layerIdx = {for (var i = 0; i < sortedLayers.length; i++) sortedLayers[i]: i};
      for (var li = 0; li < sortedLayers.length; li++) {
        final key = sortedLayers[directionDown ? li : sortedLayers.length - 1 - li];
        final layerNodes = layers[key]!;
        // 質心 = 鄰層（下游或上游）節點在該鄰層的索引平均
        final neighborOrder = <String, double>{};
        for (var ni = 0; ni < layerNodes.length; ni++) {
          final id = layerNodes[ni];
          final neighbors = directionDown
              ? (downstream[id] ?? const <String>{})
              : (upstream[id] ?? const <String>{});
          final indices = <double>[];
          for (final nb in neighbors) {
            final nbLayer = layers.entries
                .firstWhere((e) => e.value.contains(nb),
                    orElse: () => const MapEntry(-1, <String>[]))
                .value;
            final idx = nbLayer.indexOf(nb);
            if (idx >= 0) indices.add(idx.toDouble());
          }
          neighborOrder[id] = indices.isEmpty
              ? ni.toDouble()
              : indices.reduce((a, b) => a + b) / indices.length;
        }
        layerNodes.sort((a, b) => neighborOrder[a]!.compareTo(neighborOrder[b]!));
      }
    }

    // x 座標：等距柵欄（全域統一欄寬=最寬節點+180 呼吸空間），
    // 全部節點排在等距垂直欄上——視覺節奏一致，不因節點寬度歪斜。
    final layerX = <int, double>{};
    var globalMaxW = 200.0;
    for (final key in sortedLayers) {
      for (final id in layers[key]!) {
        final w = nodes[id]?.width ?? 200.0;
        if (w > globalMaxW) globalMaxW = w;
      }
    }
    final colStep = globalMaxW + 180.0;
    for (var li = 0; li < sortedLayers.length; li++) {
      layerX[sortedLayers[li]] = 120.0 + li * colStep;
    }

    // y 座標：層內等距 240、整體置中於質心
    for (var li = 0; li < sortedLayers.length; li++) {
      final layerNodes = layers[sortedLayers[li]]!;
      final totalH = (layerNodes.length - 1) * 240.0;
      final y0 = center - totalH / 2;
      for (var ni = 0; ni < layerNodes.length; ni++) {
        final id = layerNodes[ni];
        final target = Offset(layerX[sortedLayers[li]]!, y0 + ni * 240.0);
        final cur = nodes[id]?.position;
        if (cur == null || (cur - target).distance > 1) {
          ctrl.moveNode(id, target);
          moved++;
        }
      }
    }
    // [v220c] 排版後自動 fit view——節點排好但跑出畫布外=白排。
    // 使用者視角：按「排版」就要看到完整整齻的結果。
    if (canvasPixelSize != null) {
      controller?.fitToContent(canvasPixelSize!, padding: 100);
    }
    return {'moved': moved, 'layers': sortedLayers.length};
  }
}
