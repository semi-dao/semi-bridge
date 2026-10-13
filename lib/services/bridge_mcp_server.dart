// bridge_mcp_server.dart
// Bridge App 內建 MCP Server — 讓 Agent 直接讀取和操作畫布狀態。
// 這是「人機共視」的技術實現。
//
// 設計:
// - shelf HTTP server，跑在 localhost:8420
// - 暴露 REST 端點，供 Hermes MCP client 或 App 內建 Agent 呼叫
// - 直接讀取 CanvasController 的 state，零延遲同步
// - 支援讀取（get_canvas_state）和操作（add_node, connect, execute）

import 'dart:async';
import 'dart:convert';
import 'package:bridge_app/services/app_retina.dart'; // [教練 Agent 2026-08-22] 全域視網膜
import '../core/dev_paths.dart'; // [開源整備] 開發機路徑泛化
import 'package:bridge_app/services/macos_desktop_shell_channel.dart'; // [開光 P1] window_map 懸浮窗狀態
import 'dart:io';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'life_tree/global_notice_channel.dart'; // [小葵 2026-09-21] 全域對話佇列
import '../widgets/canvas/v2/canvas_mcp_registry.dart'; // [教練 Agent 2026-07-20] 渲染感應器
import 'canvas_store.dart'; // [W4.5] create_canvas 用
import 'package:shelf_router/shelf_router.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show Offset, Size; // [開光 P2/P3] canvas_zoom focal + window_control restore
import 'package:flutter/services.dart' show rootBundle;
import 'package:window_manager/window_manager.dart'; // [開光 P1] window_map 主視窗幾何
import 'package:path_provider/path_provider.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/brain_container/brain_container_service.dart';
import 'package:bridge_app/services/vector_db/hybrid_search_service.dart';
import 'package:bridge_app/services/vector_db/identity_reembed_service.dart';
import 'package:bridge_app/services/vector_db/vector_sketch_service.dart';
import 'package:bridge_app/services/vector_db/incremental_ingest_service.dart';
import 'package:bridge_app/services/vector_db/asset_chunk_backfill_service.dart';
import 'package:bridge_app/services/brain_container/brain_database.dart';
import 'package:bridge_app/services/brain_container/injection_preparer.dart'; // [M1] 注入單一入口
import 'package:bridge_app/services/brain_container/galaxy_data_service.dart'; // [小葵 2026-08-27] 3D 星系模式
import 'package:bridge_app/services/schedule_registry.dart'; // [H5 2026-10-08] 戰爭模式任務面板
import 'package:bridge_app/services/project_door_store.dart'; // [H5]
import 'package:bridge_app/services/collab/swarm_recorder.dart' show SwarmCampaignAssets, swarmEventBus; // [TRIO M5b] 戰役資產+LIVE 匯流排
import 'package:bridge_app/services/brain_container/design_file_thumbnail_service.dart'; // [小葵 2026-08-28] 設計檔縮圖嵌入
import 'package:bridge_app/services/vector_db/agent_memory_backfill_service.dart';
// [小葵 2026-10-13 K1 修復線] K1 頭訓練引導 + 守門員
import 'package:bridge_app/services/decision/k1_bootstrapper.dart';
import 'package:bridge_app/services/decision/k1_gatekeeper.dart';

/// 畫布 MCP Server — 暴露畫布狀態和操作給 Agent。
///
/// 啟動後監聽 localhost:8420，提供以下端點：
/// - GET  /state        — 取得完整畫布狀態（節點 + 連線 + viewport）
/// - GET  /screenshot   — 截圖（base64 PNG，從 RenderRepaintBoundary）
/// - POST /add_node     — 新增節點
/// - POST /connect      — 建立連線
/// - POST /remove_node  — 刪除節點
/// - POST /execute      — 執行工作流
/// - GET  /health       — 健康檢查
class BridgeMcpServer {
  late final Router _router; // [開光 P1.5]
  final Set<String> _dispatchedTools = {}; // [tools_health] 已 dispatch 過的工具
  static const int defaultPort = 8420;

  /// [教練 Agent 2026-08-05] Server 版本——/health 跟 _meta.serverInfo 共用這個常數，
  /// 避免升版時不一致（之前是 /health=1.0.0 但 _meta.serverInfo=2.0.0 的窘境）。
  /// 升級時只改這一行。
  static const String serverVersion = '2.0.0';

  static BridgeMcpServer? _instance;
  static BridgeMcpServer get instance => _instance ??= BridgeMcpServer._();
  BridgeMcpServer._({this.port = defaultPort});

  /// [教練 Agent 2026-08-05] 工廠 — 允許測試環境用不同 port 建立獨立實例
  ///
  /// 原本 factory 會 cache singleton 鎖死 port 8420，這讓單元測試無法用隨機 port。
  /// 改成「port 不一致時 reset instance」，正式環境仍會拿到 8420 的唯一 instance。
  factory BridgeMcpServer({int port = defaultPort}) {
    if (_instance == null || _instance!.port != port) {
      _instance = BridgeMcpServer._(port: port);
    }
    return _instance!;
  }

  /// [教練 Agent 2026-08-05] 測試專用 — 建立不污染 singleton 的獨立 instance
  /// 給 unit test 用，避免撞到執行中的 Flutter App 佔用的 8420 port
  ///
  /// [開光 P0 · 小葵 2026-09-26] 補 _skipTokenInit——9/24 開源安全域引入
  /// fail-close 後，token 初始化（getApplicationSupportDirectory）在無
  /// platform binding 的測試環境必失敗 → server 靜默不啟動 → 這組 L1 測試
  /// 整組 Connection refused 變紅。測試 instance 跳過 token init：
  /// _authToken 維持 null（門禁 middleware 對 null 放行），走隨機 port，
  /// 不影響正式 8420 的 fail-close 安全語意。
  @visibleForTesting
  static BridgeMcpServer createForTesting({required int port}) {
    final s = BridgeMcpServer._(port: port);
    s._skipTokenInit = true;
    return s;
  }

  /// [開光 P0] 測試專用旗標——見 createForTesting 註解
  bool _skipTokenInit = false;

  HttpServer? _server;
  final int port;

  // [教練 Agent 2026-08-21] 開源安全——localhost token 門禁。
  // 背景：MCP 8420 綁 loopback，但本機任何程序（瀏覽器頁面的 JS、
  // 其他 app）都能打。25 個端點裡有 navigate/send_chat/inject_message
  // 這類能「代替使用者行動」的能力，等於自律體系的城牆上沒鎖的門。
  //
  // 設計（不擾人不惱人三原則）：
  // 1. 零設定——App 啟動時自動生成隨機 token 寫到 App Support 的
  //    mcp_token 檔（0600），外部客戶端（Hermes 腳本）讀同一個檔
  //    帶 X-Bridge-Token header，使用者完全無感。
  // 2. /health 不鎖——監控/探活永遠可用（本來就只回版本資訊）。
  // 3. 缺 token 或錯 token 一律 401——不透露原因，跟錯的一樣。
  String? _authToken;

  /// token 檔路徑（外部客戶端契約：<appSupport>/mcp_token）
  static Future<String> _tokenFilePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/mcp_token';
  }

  /// 啟動時確保 token 存在（不存在則生成）。每次 App 重啟不輪替——
  /// 輪替會讓多客戶端同時失效，穩定性優先；洩漏時手動刪檔即重置。
  Future<void> _ensureAuthToken() async {
    try {
      final path = await _tokenFilePath();
      final file = File(path);
      if (await file.exists()) {
        final t = (await file.readAsString()).trim();
        if (t.length >= 32) {
          _authToken = t;
          return;
        }
      }
      // 生成 64 hex（32 bytes 隨機）
      final rnd = Random.secure();
      final t = List.generate(32, (_) => rnd.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await file.writeAsString(t, flush: true);
      // 0600——只有本使用者可讀
      await Process.run('chmod', ['600', path]);
      _authToken = t;
      debugPrint('[MCP] 已生成 localhost 門禁 token（$path）');
    } catch (e) {
      // [小葵 2026-09-24 開源安全域] fail-close：token 初始化失敗 = 服務不啟動。
      // 舊版「寧可暫時無鎖」在開源後等於公告攻擊路徑（讓 token 初始化失敗即可無鎖）。
      // 現在：失敗即拒絕服務，log 說清楚，讓使用者能看到並修復（刪 mcp_token 重啟即重置）。
      _authToken = null;
      _tokenInitFailed = true;
      debugPrint('[MCP] token 初始化失敗——MCP 服務 fail-close 不啟動（修復：刪除 mcp_token 檔後重啟 App）: $e');
    }
  }

  /// [小葵 2026-09-24 開源安全域] token 初始化是否失敗（fail-close 判定用）
  bool _tokenInitFailed = false;

  /// 門禁 middleware——/health 之外全部要求 X-Bridge-Token
  Middleware _tokenGate() {
    return (inner) {
      return (request) async {
        if (request.url.path == 'health' ||
            request.url.path == 'three.module.js' || // [v58] three.js vendor 是靜態資源——module import 不帶 token，放行（頁面本身仍有門禁）
            request.url.path == 'three.core.js' || // [v63] 同上——three 內部依賴
            request.url.path.startsWith('avatar_state/') || // [小葵 2026-09-24] 影片 fetch 不帶 token header——比照 vendor 放行（頁面本身仍有門禁）
            request.url.path == 'avatar_engine.js' || // 同上
            _authToken == null) {
          return await inner(request);
        }
        final provided = request.headers['x-bridge-token'];
        if (provided == _authToken) {
          return await inner(request);
        }
        // [小葵 2026-08-27] 3D 星系 webview：頁面 URL 以 ?token= 帶入
        // （webview 初次載入無法帶 header；localhost only）
        final qToken = request.url.queryParameters['token'];
        if (qToken != null && qToken == _authToken) {
          return await inner(request);
        }
        debugPrint('[MCP] 401 拒絕: ${request.method} /${request.url.path}');
        return Response(401,
            body: jsonEncode({'error': 'unauthorized'}),
            headers: _jsonHeaders);
      };
    };
  }

  /// 由外部提供的回調 — 讓 server 能存取 CanvasController
  Future<Map<String, dynamic>> Function()? onGetState;
  /// [教練 Agent 2026-08-22 渲染層視網膜] 外部（教練 Agent/Hermes）也能直讀
  /// ActualSizeCache 真實渲染尺寸——與原生 Agent canvas_look 同源對稱
  Future<Map<String, dynamic>> Function()? onGetRenderLayer;
  Future<String> Function()? onScreenshot;
  Future<String> Function(WorkflowNodeType type, double x, double y)? onAddNode;
  Future<void> Function(String fromNodeId, String fromPort, String toNodeId, String toPort)? onConnect;
  Future<void> Function(String nodeId)? onRemoveNode;
  Map<String, dynamic> Function()? onAutoLayout; // [教練 Agent 2026-08-26] 一鍵排版
  Future<void> Function()? onExecute;

  // [教練 Agent 2026-08-01] 新增 callback — 節點參數控制 + 畫布管理
  Future<Map<String, dynamic>> Function(String nodeId, Map<String, dynamic> params)? onSetNodeParams;
  Future<Map<String, dynamic>> Function(String direction, double? pixels)? onAppScroll; // [開光 P1] 頁面捲動
  Future<Map<String, dynamic>> Function({String? selector, double? x, double? y, bool confirm})? onAppTap; // [開光 v0.4.0] 語意點擊
  Future<String?> Function()? onScreenCapture; // [開光 v0.4.x] OS 層視網膜（Swift CGWindowList）
  Future<Map<String, dynamic>> Function(String nodeId)? onGetNodeParams;
  Future<void> Function()? onClearCanvas;
  Future<void> Function(String templateId)? onLoadTemplate;

  /// 共視操作 — Agent 主動打開畫布 tab
  void Function()? onNavigateToCanvas;
  /// 共視操作 — Agent 在對話框發送訊息
  void Function(String message, {String? role})? onSendChat;
  /// 列出所有畫布
  List<Map<String, dynamic>> Function()? onListCanvases;
  /// 載入指定畫布
  void Function(String canvasId)? onLoadCanvas;

  /// 取得塗鴉標注
  List<Map<String, dynamic>> Function()? onGetAnnotations;
  // ── [開光 P2 · 小葵 2026-09-26] app_tap：語意點擊 callback ──────
  /// 回傳 null=未接線（-32603）；Map{success, message}=結果
  Map<String, dynamic>? Function(String target)? onTap;

  /// [教練 Agent 2026-07-19] 模擬使用者在聊天框打字——觸發完整 sendMessage 流程
  /// 跟 onSendChat 不同：onSendChat 只顯示訊息，這個觸發 IntentSpine → 反問/AgentLoop
  /// 回傳值：true = 已觸發，false = controller 未就緒
  bool Function(String message)? onSendUserMessage;

  /// [教練 Agent 2026-07-19] 派任務到畫布對話框——打到 CanvasChatPanel 的 ChatController
  /// 跟 onSendUserMessage 不同：這個打到畫布頁的 chat，讓 Agent 在畫布當下環境工作
  /// 人機共視的正確入口——原生 Agent看著當下畫面，不需要「切頁面截圖」
  /// 回傳值：true = 已觸發，false = canvas chat controller 未就緒
  bool Function(String message)? onSendCanvasMessage;

  /// [教練 Agent 2026-07-19] 統一導航——切到任何頁面
  /// target: home | companion | chat | canvas | brain | system
  /// sub: model | pairing | files | settings (僅 system tab 有子頁面)
  void Function(String target, String? sub)? onNavigate;

  /// [教練 Agent 2026-07-19] 取得當前 App 狀態
  /// 回傳：{page, systemSub, canvasIndex, isHomepage, isCompanionHall}
  Map<String, dynamic> Function()? onGetAppState;

  /// [教練 Agent 2026-07-19] 使用者插嘴——原生 Agent工作時注入訊息
  /// 回傳值：true = 已注入，false = AgentLoop 未運行或未就緒
  bool Function(String message)? onInjectMessage;

  /// [教練 Agent 2026-08-08] 教練模式——取得原生 Agent最後回覆
  /// 回傳：最近一條 assistant 訊息的內容，null = 沒有
  String? Function()? onGetLastAgentReply;

  /// [教練 Agent 2026-08-08] 教練模式——取得 Agent Loop 偵錯狀態
  /// 回傳：{provider, model, turn, isLocal} 或 null
  Map<String, dynamic>? Function()? onGetAgentDebugInfo;

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;

    final router = Router();
    _router = router; // [開光 P1.5] 保存供 _proxyGet 同進程分派

    router.get('/health', _handleHealth);
    router.get('/state', _handleGetState);
    // [教練 Agent 2026-08-22] 渲染層視網膜——外部共視對稱端點
    router.get('/render_layer', _handleGetRenderLayer);
    // [教練 Agent 2026-08-22] 全域視網膜——整個 App 畫面（任何頁面）
    router.get('/app_view', _handleGetAppView);
    router.get('/screenshot', _handleScreenshot);
    router.post('/add_node', _handleAddNode);
    router.post('/connect', _handleConnect);
    router.post('/remove_node', _handleRemoveNode);
    router.post('/auto_layout', _handleAutoLayout); // [教練 Agent 2026-08-26] 一鍵排版
    router.post('/execute', _handleExecute);
    router.post('/navigate_to_canvas', _handleNavigateToCanvas);
    router.post('/send_chat', _handleSendChat);
    router.post('/send_user_message', _handleSendUserMessage); // [教練 Agent 2026-07-19] 模擬使用者打字
    router.get('/global_notice', _handleGlobalNoticeClaim); // [小葵 2026-09-21] 全域對話佇列認領
    router.post('/send_canvas_message', _handleSendCanvasMessage); // [教練 Agent 2026-07-19] 派任務到畫布對話框
    router.post('/inject_message', _handleInjectMessage); // [教練 Agent 2026-07-19] 原生 Agent工作時插嘴
    router.post('/navigate', _handleNavigate); // [教練 Agent 2026-07-19] 統一導航
    router.post('/app_scroll', _handleAppScroll); // [開光 P1 2026-10-01] 頁面捲動（隱藏門收編）
    router.post('/brain_search_focus', _handleBrainSearchFocus); // [教練 Agent 2026-08-20] 搜尋放大對焦
    router.get('/vector_search', _handleVectorSearch); // [教練 Agent 2026-08-21] 檢索鏈實測端點
    router.post('/inject/enrich', _handleInjectEnrich); // [小葵 2026-10-10 M1] 注入管線單一入口（評測+線上同路徑）
    // [小葵 2026-10-13 K1 修復線] K1 頭訓練引導：POST /k1/train（body=標註 JSONL）
    router.post('/k1/train', _handleK1Train);
    router.get('/k1/head', _handleK1Head); // 查詢頭掛載狀態
  router.get('/identity_reembed', _handleIdentityReembed); // [小葵 2026-09-09] 身份重嵌進度/觸發
  router.get('/vector_sketch', _handleVectorSketch); // [小葵 2026-09-09] 向量資料素描
  router.get('/rescan', _handleRescan); // [小葵 2026-09-09] 手動重掃（重匯入模擬）
    router.get('/import_progress', _handleImportProgress); // [教練 Agent 2026-08-21] #10 背景導入進度
    router.get('/get_app_state', _handleGetAppState); // [教練 Agent 2026-07-19] 取得當前頁面狀態
    router.post('/brain_reindex', _handleBrainReindex); // [教練 Agent 2026-07-19] 重新嵌入 mock-fallback 記憶
    router.post('/design_thumb_reindex', _handleDesignThumbReindex); // [小葵 2026-08-28] 手動觸發設計檔縮圖嵌入
    // [教練 Agent 2026-08-01] 新增 4 個 MCP 端點
    router.post('/set_node_params', _handleSetNodeParams);
    router.get('/get_node_params', _handleGetNodeParams);
    router.post('/clear_canvas', _handleClearCanvas);
    router.post('/load_template', _handleLoadTemplate);
    router.get('/list_canvases', _handleListCanvases);
    router.post('/load_canvas', _handleLoadCanvas);
    // [W4.5 小葵 2026-10-09] 建新畫布——排程測試專案用（H6 移轉也要用）
    router.post('/create_canvas', _handleCreateCanvas);
    router.get('/annotations', _handleGetAnnotations);
    router.get('/get_latest_messages', _handleGetLatestMessages); // [教練 Agent 2026-07-20] 渲染感應器
    router.get('/get_agent_debug', _handleGetAgentDebug); // [教練 Agent 2026-08-08] 教練模式

    router.get('/galaxy', _handleGetGalaxyPage); // [小葵 2026-08-27] 3D 星系模式頁
    router.post('/galaxy_cmd', _handleGalaxyCmd); // [小葵 2026-09-24 出道令] Agent 操控星系
    router.get('/galaxy_cmd_poll', _handleGalaxyCmdPoll); // [小葵 2026-09-24] 頁面輪詢拉指令
    router.get('/galaxy_data', _handleGetGalaxyData); // [小葵 2026-08-27] 星系資料包
    router.get('/galaxy_swarm_layer', _handleGetSwarmLayer); // [TRIO M5a] 戰爭層 JS
    router.get('/galaxy_swarm_campaigns', _handleGetSwarmCampaigns); // [TRIO M5b] 戰役列表
    router.get('/galaxy_swarm_events', _handleGetSwarmEvents); // [TRIO M5b] 事件流（重播）
    router.get('/galaxy_swarm_live', _handleSwarmLiveSse); // [M5b LIVE] 事件驅動推送（SSE）
    router.get('/galaxy_missions', _handleGetGalaxyMissions); // [H5 2026-10-08] 戰爭模式任務面板（排程卡＋專案門）
    router.get('/galaxy_open', _handleGetGalaxyOpen); // [小葵 2026-08-28] 雙擊星點開檔
    router.get('/galaxy_thumb', _handleGetGalaxyThumb); // [小葵 2026-08-28 v28] 資料框縮圖預覽
    router.post('/galaxy_oplog', _handlePostGalaxyOplog); // [小葵 2026-08-29 v32] 行車記錄器上傳
    router.get('/galaxy_version', _handleGetGalaxyVersion); // [小葵 2026-08-29 v52] 快取自癒指紋
    router.get('/galaxy_params', _handleGetGalaxyParams); // [v232 小葵 2026-09-03] 星系參數設定窗
    router.post('/galaxy_params', _handlePostGalaxyParams); // [v232] 寫入+持久化
    router.post('/galaxy_edit', _handlePostGalaxyEdit); // [v308 Blue 五動作令] 星系內編輯：刪除/開資料夾/標籤/改名/圖示
    router.get('/galaxy_icons', _handleGetGalaxyIcons); // [v308] 十個預設圖示清單
    router.get('/three.module.js', _handleGetThreeModule); // [小葵 2026-08-29 v56] three.js 本地 vendor
    router.get('/avatar_engine.js', _handleGetAvatarEngine); // [小葵 2026-09-24 出道令] 懸浮小葵引擎
    router.get('/avatar_state/<name>', _handleGetAvatarStateVideo); // [小葵 2026-09-24] 16 段狀態影片
    router.get('/three.core.js', _handleGetThreeCore); // [v63] three r167+ 拆雙檔——module 內部 import three.core.js
    router.get('/galaxy_ping', _handleGetGalaxyPing); // [小葵 2026-08-29 v54] 監視器：頁面心跳
    router.get('/galaxy_note', _handleGetGalaxyNote); // [小葵 2026-09-25 開面板咚修] Flutter UI→頁面帶外通知（uiMute 靜音窗）
    router.get('/fps_probe', _handleGetFpsProbe); // [小葵 2026-08-29 v85] rAF 純測試頁——80FPS 是面板/系統還是場景？

    // MCP tools/list 端點 — 讓 Hermes MCP client 能發現工具
    router.get('/mcp/tools', _handleMcpToolsList);
    // [教練 Agent 2026-08-05] MCP 2026-07-28 標準 JSON-RPC 端點
    router.post('/mcp', _handleJsonRpc);
    router.get('/mcp/discover', _handleMcpDiscover);

    // [開光 P0 · 小葵 2026-09-26] 測試 instance 跳過 token init（見 createForTesting）
    if (!_skipTokenInit) {
      await _ensureAuthToken();
    }
    if (!_skipTokenInit && _tokenInitFailed) {
      // [小葵 2026-09-24 開源安全域] fail-close：token 不存在 = 不 serve。
      debugPrint('[MCP] fail-close：門禁 token 未就緒，MCP 服務不啟動');
      return;
    }

    final handler = const Pipeline()
        .addMiddleware(logRequests(logger: (msg, isError) => debugPrint('[MCP] $msg')))
        .addMiddleware(_tokenGate())
        .addHandler(router.call);

    try {
      _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, port);
      debugPrint('[MCP] Canvas MCP Server 啟動於 http://localhost:$port');
    } catch (e) {
      debugPrint('[MCP] 啟動失敗: $e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    debugPrint('[MCP] Canvas MCP Server 已停止');
  }

  // ── 端點處理 ──────────────────────────────────────────

  Response _handleHealth(Request request) {
    return Response.ok(jsonEncode({
      'status': 'ok',
      'service': 'bridge-mcp',
      'version': serverVersion,
      'protocolVersion': _protocolVersion,
      'port': port,
      'canvasConnected': onGetState != null,
    }), headers: _jsonHeaders);
  }

  /// [教練 Agent 2026-08-22] 全域視網膜——整個 App 畫面（base64 PNG）
  /// 無論使用者停在哪頁：首頁/畫布/大腦/設定/對話
  Future<Response> _handleGetAppView(Request request) async {
    try {
      final b64 = await AppRetina.capture();
      if (b64 == null) {
        return Response(503,
            body: jsonEncode({'error': 'App 尚未渲染'}),
            headers: _jsonHeaders);
      }
      return Response.ok(
        jsonEncode({
          'success': true,
          'image': b64,
          'capturedAt': DateTime.now().toIso8601String(),
        }),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return Response(500,
          body: jsonEncode({'error': e.toString()}), headers: _jsonHeaders);
    }
  }

  /// [教練 Agent 2026-08-22] 渲染層視網膜——ActualSizeCache 真實渲染尺寸
  /// 與 canvas_look（agent tool）同源，外部客戶端對稱可讀
  Future<Response> _handleGetRenderLayer(Request request) async {
    if (onGetRenderLayer == null) {
      return Response(503,
          body: jsonEncode({'error': 'Render layer not available'}),
          headers: _jsonHeaders);
    }
    try {
      final data = await onGetRenderLayer!();
      return Response.ok(jsonEncode(data), headers: _jsonHeaders);
    } catch (e) {
      return Response(500,
          body: jsonEncode({'error': e.toString()}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleGetState(Request request) async {
    if (onGetState == null) {
      return Response(503, body: jsonEncode({'error': 'Canvas controller not connected'}),
          headers: _jsonHeaders);
    }
    try {
      final state = await onGetState!();
      return Response.ok(jsonEncode(state), headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  Future<Response> _handleScreenshot(Request request) async {
    if (onScreenshot == null) {
      return Response(503, body: jsonEncode({'error': 'Screenshot not available'}),
          headers: _jsonHeaders);
    }
    try {
      final base64Png = await onScreenshot!();
      return Response.ok(jsonEncode({
        'image': base64Png,
        'format': 'png',
        'encoding': 'base64',
      }), headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  Response _handleGetAnnotations(Request request) {
    if (onGetAnnotations == null) {
      return Response(503, body: jsonEncode({'error': 'Annotations not available'}),
          headers: _jsonHeaders);
    }
    final annotations = onGetAnnotations!();
    return Response.ok(jsonEncode({
      'annotations': annotations,
      'count': annotations.length,
    }), headers: _jsonHeaders);
  }

  /// [教練 Agent 2026-07-20] 渲染感應器——回傳原生 Agent最新回覆
  Response _handleGetLatestMessages(Request request) {
    final reg = CanvasMcpRegistry.instance;
    final reply = reg.lastAgentReply;
    if (reply.isEmpty) {
      return Response.ok(jsonEncode({
        'hasNewReply': false,
        'message': 'No agent reply yet',
      }), headers: _jsonHeaders);
    }
    return Response.ok(jsonEncode({
      'hasNewReply': true,
      'content': reply,
      'length': reply.length,
      'timestamp': DateTime.now().toIso8601String(),
    }), headers: _jsonHeaders);
  }

  /// [教練 Agent 2026-08-08] 教練模式——Agent Loop debug 資訊
  Response _handleGetAgentDebug(Request request) {
    if (onGetAgentDebugInfo == null) {
      return Response.ok(jsonEncode({
        'available': false,
        'message': 'Debug handler not connected',
      }), headers: _jsonHeaders);
    }
    final info = onGetAgentDebugInfo!();
    if (info == null) {
      return Response.ok(jsonEncode({
        'available': false,
        'message': 'Agent Loop not running',
      }), headers: _jsonHeaders);
    }
    return Response.ok(jsonEncode({
      'available': true,
      ...info,
      'timestamp': DateTime.now().toIso8601String(),
    }), headers: _jsonHeaders);
  }

  Future<Response> _handleAddNode(Request request) async {
    if (onAddNode == null) {
      return Response(503, body: jsonEncode({'error': 'Canvas controller not connected'}),
          headers: _jsonHeaders);
    }
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final typeStr = body['type'] as String;
      final x = (body['x'] as num).toDouble();
      final y = (body['y'] as num).toDouble();

      final type = WorkflowNodeType.values.byName(typeStr);
      final nodeId = await onAddNode!(type, x, y);

      return Response.ok(jsonEncode({
        'success': true,
        'nodeId': nodeId,
      }), headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  // [教練 Agent 2026-08-26 使用者 基礎規則] 一鍵自動排版端點
  Future<Response> _handleAutoLayout(Request request) async {
    if (onAutoLayout == null) {
      return Response(503, body: jsonEncode({'error': 'Canvas controller not connected'}),
          headers: _jsonHeaders);
    }
    try {
      final result = onAutoLayout!();
      return Response.ok(jsonEncode(result), headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  Future<Response> _handleConnect(Request request) async {
    if (onConnect == null) {
      return Response(503, body: jsonEncode({'error': 'Canvas controller not connected'}),
          headers: _jsonHeaders);
    }
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      await onConnect!(
        body['fromNodeId'] as String,
        body['fromPort'] as String,
        body['toNodeId'] as String,
        body['toPort'] as String,
      );
      return Response.ok(jsonEncode({'success': true}),
          headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  Future<Response> _handleRemoveNode(Request request) async {
    if (onRemoveNode == null) {
      return Response(503, body: jsonEncode({'error': 'Canvas controller not connected'}),
          headers: _jsonHeaders);
    }
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      await onRemoveNode!(body['nodeId'] as String);
      return Response.ok(jsonEncode({'success': true}),
          headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  Future<Response> _handleExecute(Request request) async {
    if (onExecute == null) {
      return Response(503, body: jsonEncode({'error': 'Executor not connected'}),
          headers: _jsonHeaders);
    }
    try {
      await onExecute!();
      return Response.ok(jsonEncode({'success': true}),
          headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  // ── 共視端點 — Agent 主動操作 App ─────────────────────

  /// [教練 Agent 2026-08-20] 大腦搜尋放大對焦：query → 大腦頁→搜尋→Enter 飛
  /// （複用 brain_canvas 的 _onSearchChanged + _onSearchSubmitted）。
  Future<Response> _handleBrainSearchFocus(Request request) async {
    final cb = CanvasMcpRegistry.instance.onBrainSearchFocus;
    if (cb == null) {
      return Response(503, body: jsonEncode({'error': 'Search focus not available'}), headers: _jsonHeaders);
    }
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final query = body['query'] as String? ?? '';
    if (query.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'query required'}), headers: _jsonHeaders);
    }
    cb(query);
    return Response.ok(jsonEncode({'success': true, 'query': query, 'message': '搜尋放大中'}), headers: _jsonHeaders);
  }

  /// [教練 Agent 2026-08-21] 讀 brain_meta 單值（無表/無值回 null）
  String? _readBrainMeta(String key) {
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        "SELECT value FROM brain_meta WHERE key = ?",
        [key],
      );
      if (rows.isEmpty) return null;
      return rows.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// [教練 Agent 2026-08-21] #10 背景導入進度：GET /import_progress
  /// 回傳 chunk 回填 + agent_memories 補嵌的即時進度（遠端一行查）。
  Future<Response> _handleImportProgress(Request request) async {
    final chunk = AssetChunkBackfillService.instance;
    final agentMem = AgentMemoryBackfillService.instance;
    return Response.ok(
      jsonEncode({
        'chunkBackfill': {
          'running': chunk.isRunning,
          'progress': chunk.progress.value,
          'chunksWritten': chunk.chunkCount,
          'assetsProcessed': chunk.assetsProcessed,
        },
        'agentMemoryBackfill': {
          'running': agentMem.isRunning,
          'progress': agentMem.progress.value,
        },
        'autoIngest': _readBrainMeta('auto_ingest_status'),
        'timestamp': DateTime.now().toIso8601String(),
      }),
      headers: _jsonHeaders,
    );
  }

  /// [小葵 2026-09-09] GET /rescan → 全根重掃＋補嵌＋自動素描（背景）
  Future<Response> _handleRescan(Request request) async {
    IncrementalIngestService.instance.requestFullRescan();
    return Response.ok(
      jsonEncode({'status': 'rescan-started'}),
      headers: _jsonHeaders,
    );
  }

  /// [小葵 2026-09-09] GET /vector_sketch?run=1 執行素描；無參數=查狀態
  Future<Response> _handleVectorSketch(Request request) async {
    final md = await VectorSketchService.instance.run();
    return Response.ok(
      jsonEncode({'status': 'done', 'length': md.length, 'preview': md.substring(0, md.length > 400 ? 400 : md.length)}),
      headers: _jsonHeaders,
    );
  }

  /// [小葵 2026-09-09] GET /identity_reembed?start=1 觸發；無參數=查進度
  Future<Response> _handleIdentityReembed(Request request) async {
    final start = (request.url.queryParameters['start'] ?? '') == '1';
    if (start) {
      IdentityReembedService.instance.start(); // 背景跑，立即回
    }
    return Response.ok(
      jsonEncode(IdentityReembedService.instance.progress()),
      headers: _jsonHeaders,
    );
  }

  /// [教練 Agent 2026-08-21] 檢索鏈實測：GET /vector_search?q=...&limit=N
  /// 走 HybridSearchService（memories + asset_index + asset_chunks
  /// 三軌），回傳命中清單——遠端可直接驗證語義搜尋品質。
  Future<Response> _handleVectorSearch(Request request) async {
    final q = request.url.queryParameters['q'] ?? '';
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '10') ?? 10;
    // [小葵 2026-09-09] mode=hybrid 走 UI 同款完整管線（FTS擴展+五因素+類型分層）
    final useHybrid = (request.url.queryParameters['mode'] ?? '') == 'hybrid';
    // [小葵 2026-09-09 Blue 分層令] tech=1 → 含 technical 層（工程師模式）
    final includeTechnical =
        (request.url.queryParameters['tech'] ?? '') == '1';
    if (q.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'q required'}), headers: _jsonHeaders);
    }
    try {
      final results = await HybridSearchService.instance.search(
        query: q,
        mode: useHybrid ? SearchMode.hybrid : SearchMode.semantic,
        limit: limit,
        includeTechnical: includeTechnical,
      );
      return Response.ok(
        jsonEncode({
          'query': q,
          'memoryHits': results.memoryHits
              .map((h) => {
                    'id': h.id,
                    'room': h.room,
                    'score': h.score.toStringAsFixed(4),
                    'content': h.content.length > 80
                        ? '${h.content.substring(0, 80)}…'
                        : h.content,
                  })
              .toList(),
          'assetHits': results.assetHits
              .map((h) => {
                    'id': h.id,
                    'file': h.fileName,
                    'path': h.filePath, // [小葵 2026-09-09] 分組檢索需要完整路徑
                    'title': h.title,
                    'summary': h.summary,
                    'kind': h.assetKind,
                    'score': h.score.toStringAsFixed(4),
                  })
              .toList(),
        }),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return Response(500, body: jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Response _handleNavigateToCanvas(Request request) {
    if (onNavigateToCanvas == null) {
      return Response(503, body: jsonEncode({'error': 'Navigate not available'}),
          headers: _jsonHeaders);
    }
    onNavigateToCanvas!();
    return Response.ok(jsonEncode({'success': true, 'message': '已切換到畫布 tab'}),
        headers: _jsonHeaders);
  }

  /// [小葵 2026-10-10 M1] 注入管線單一入口——評測與線上同路徑。
  /// Fable delta：評測條件必須等於線上條件（digest/K1 合併/embedding 觀測）。
  /// logSample 恆為 false：評測 600 題不得灌爆 CausalLedger。
  /// [小葵 2026-10-13 K1 修復線] POST /k1/train——標註 JSONL → 嵌入 → LOO-CV → 訓練 → 落盤 → 掛載
Future<Response> _handleK1Train(Request request) async {
  try {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final labelsJson = body['labels'] as String? ?? '';
    if (labelsJson.isEmpty) {
      return Response(400,
          body: jsonEncode({'error': 'labels required (JSONL)'}),
          headers: _jsonHeaders);
    }
    final report =
        await K1Bootstrapper.instance.bootstrapFromLabels(labelsJson);
    return Response.ok(jsonEncode(report), headers: _jsonHeaders);
  } catch (e) {
    return Response(500,
        body: jsonEncode({'error': e.toString()}), headers: _jsonHeaders);
  }
}

/// [小葵 2026-10-13 K1 修復線] GET /k1/head——頭掛載狀態查詢
Future<Response> _handleK1Head(Request request) async {
  final head = K1Gatekeeper.instance.head;
  return Response.ok(
    jsonEncode({
      'mounted': head != null,
      'sample_count': head?.sampleCount,
      'holdout_acc': head?.holdoutAcc,
      'trained_at_ms': head?.trainedAtMs,
    }),
    headers: _jsonHeaders,
  );
}

Future<Response> _handleInjectEnrich(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final q = body['q'] as String? ?? '';
      if (q.isEmpty) {
        return Response(400,
            body: jsonEncode({'error': 'q required'}),
            headers: _jsonHeaders);
      }
      final useK1 = body['k1'] as bool? ?? true;
      final outcome = await InjectionPreparer.instance.prepare(
        q,
        k1: useK1,
        logSample: false,
      );
      return Response.ok(
        jsonEncode({
          'q': q,
          'input_digest': outcome.inputDigest,
          'input_hash': outcome.inputHash,
          'block': outcome.block,
          'injected_ids': outcome.ids,
          'latency_ms': outcome.latencyMs,
          'dropped_count': outcome.droppedCount,
          'k1_hits_n': outcome.k1MergedN,
          'k1_kept_n': outcome.k1KeptN,
          'embedding_ok': outcome.embeddingOk,
          'k1_label': outcome.k1Label,
          'k1_confidence': outcome.k1Confidence,
          'k1_escalated': outcome.k1Escalated,
          'k1_source': outcome.k1Source,
          if (outcome.failureReason != null)
            'failure_reason': outcome.failureReason,
        }),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return Response(500,
          body: jsonEncode({'error': e.toString()}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleSendChat(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final message = body['message'] as String;
      final role = body['role'] as String?;
      // [教練 Agent 2026-08-08] 優先觸發完整 Agent Loop，fallback 到 UI 注入
      if (onSendUserMessage != null) {
        final triggered = onSendUserMessage!(message);
        if (triggered) {
          return Response.ok(jsonEncode({'success': true, 'message': 'Message sent (full Agent Loop)'}),
              headers: _jsonHeaders);
        }
      }
      if (onSendChat != null) {
        onSendChat!(message, role: role);
        return Response.ok(jsonEncode({'success': true, 'message': 'Message injected to UI'}),
            headers: _jsonHeaders);
      }
      return Response(503, body: jsonEncode({'error': 'No chat handler available'}),
          headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  // [教練 Agent 2026-07-19] 模擬使用者在聊天框打字
  // 跟 /send_chat 不同：這個觸發完整 sendMessage 流程（IntentSpine → 反問/AgentLoop）
  Future<Response> _handleSendUserMessage(Request request) async {
    if (onSendUserMessage == null) {
      return Response(503, body: jsonEncode({'error': 'User message handler not available'}),
          headers: _jsonHeaders);
    }
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final message = body['message'] as String;
      final triggered = onSendUserMessage!(message);
      if (!triggered) {
        return Response(503, body: jsonEncode({'error': 'Chat controller not ready. Make sure the chat tab is active.'}),
            headers: _jsonHeaders);
      }
      return Response.ok(jsonEncode({'success': true, 'message': 'Message sent to chat controller'}),
          headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  // [小葵 2026-09-21] 全域對話佇列認領——UI（Quick Assistant/主畫面）輪詢，
  // 把她要確認的事（夢境 escalate 卡等）推進全域對話，不打擾工作對話窗口。
  // GET /global_notice → 未送達訊息一次認領（認領即標記 delivered）
  Future<Response> _handleGlobalNoticeClaim(Request request) async {
    try {
      final pending = GlobalNoticeChannel.instance.claimPending();
      return Response.ok(
          jsonEncode({'success': true, 'notices': pending}),
          headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}), headers: _jsonHeaders);
    }
  }

  // [教練 Agent 2026-07-19] 派任務到畫布對話框——人機共視的正確入口
  // 跟 /send_user_message 不同：這個打到 CanvasChatPanel 的 ChatController
  // 讓 Agent 在畫布當下環境工作，看著當下畫面，不需要「切頁面截圖」
  Future<Response> _handleSendCanvasMessage(Request request) async {
    if (onSendCanvasMessage == null) {
      return Response(503, body: jsonEncode({'error': 'Canvas message handler not available'}),
          headers: _jsonHeaders);
    }
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final message = body['message'] as String;
      final triggered = onSendCanvasMessage!(message);
      if (!triggered) {
        return Response(503, body: jsonEncode({'error': 'Canvas chat controller not ready. Make sure the canvas tab is active.'}),
            headers: _jsonHeaders);
      }
      return Response.ok(jsonEncode({'success': true, 'message': 'Message sent to canvas chat controller'}),
          headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  // [教練 Agent 2026-07-19] 使用者插嘴——原生 Agent工作時注入訊息（不中斷，下一輪 LLM 呼叫前會看到）
  Future<Response> _handleInjectMessage(Request request) async {
    if (onInjectMessage == null) {
      return Response(503, body: jsonEncode({'error': 'Inject handler not available'}),
          headers: _jsonHeaders);
    }
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final message = body['message'] as String;
      final injected = onInjectMessage!(message);
      return Response.ok(jsonEncode({
        'success': injected,
        'message': injected
            ? 'Message injected to AgentLoop'
            : 'AgentLoop not running or not ready',
      }), headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  // [教練 Agent 2026-07-19] 統一導航——切到任何頁面
  // target: home | companion | chat | canvas | brain | system
  // sub: model | pairing | files | settings (僅 system tab)
  Future<Response> _handleNavigate(Request request) async {
    if (onNavigate == null) {
      return Response(503, body: jsonEncode({'error': 'Navigation not available'}),
          headers: _jsonHeaders);
    }
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final target = body['target'] as String? ?? 'home';
      final sub = body['sub'] as String?;
      onNavigate!(target, sub);
      return Response.ok(jsonEncode({
        'success': true,
        'message': 'Navigated to $target${sub != null ? ' > $sub' : ''}',
      }), headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  // [教練 Agent 2026-07-19] 取得當前 App 狀態——回傳當前頁面、系統子頁面、MCP 版本
  Response _handleGetAppState(Request request) {
    if (onGetAppState == null) {
      return Response(503, body: jsonEncode({'error': 'App state not available'}),
          headers: _jsonHeaders);
    }
    final state = onGetAppState!();
    return Response.ok(jsonEncode(state), headers: _jsonHeaders);
  }

  /// [教練 Agent 2026-07-19] 重新嵌入所有 mock-fallback 記憶。
  ///
  /// EmbeddingGemma 模型修復後，舊記憶仍用零向量。
  /// 呼叫 BrainContainerService.reindexFallbackMemories() 重算。
  Future<Response> _handleBrainReindex(Request request) async {
    try {
      final count = await BrainContainerService.instance.reindexFallbackMemories();
      return Response.ok(
        jsonEncode({
          'success': true,
          'reindexed': count,
          'model': 'gemma-300m-v1',
        }),
        headers: _jsonHeaders,
      );
    } catch (e) {
      return Response(500,
          body: jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  Response _handleListCanvases(Request request) {
    if (onListCanvases == null) {
      return Response(503, body: jsonEncode({'error': 'List not available'}),
          headers: _jsonHeaders);
    }
    final canvases = onListCanvases!();
    return Response.ok(jsonEncode({'canvases': canvases}),
        headers: _jsonHeaders);
  }

  /// [W4.5] 建新畫布——CanvasStore.create 持久化 + onLoadCanvas 切換前景
  Future<Response> _handleCreateCanvas(Request request) async {
    if (onLoadCanvas == null) {
      return Response(503,
          body: jsonEncode({'error': 'Load not available'}),
          headers: _jsonHeaders);
    }
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final title = (body['title'] as String?) ?? '未命名畫布';
      final canvas = await CanvasStore.create(title: title);
      onLoadCanvas!(canvas.id);
      return Response.ok(
          jsonEncode({'success': true, 'canvasId': canvas.id, 'title': title}),
          headers: _jsonHeaders);
    } catch (e) {
      return Response(500,
          body: jsonEncode({'error': e.toString()}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleLoadCanvas(Request request) async {
    if (onLoadCanvas == null) {
      return Response(503, body: jsonEncode({'error': 'Load not available'}),
          headers: _jsonHeaders);
    }
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      onLoadCanvas!(body['canvasId'] as String);
      return Response.ok(jsonEncode({'success': true}),
          headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  /// MCP tools/list — 描述可用工具（讓 Hermes MCP client 發現）
  ///
  /// [教練 Agent 2026-08-05] 升級到 MCP 2026-07-28：
  /// - 每個 tool 帶 `inputSchema`（JSON Schema 2020-12）
  /// - result 帶 `ttlMs` + `cacheScope`（CacheableResult 介面，SEP-2549）
  /// - 推薦 `_meta.serverInfo` 在 result._meta
  // ── [開光 P0 · 小葵 2026-09-26] 單一真相源手術 ─────────────
  // 三份清單各自漂移（GET /mcp/tools 14 個殘留子集 / tools/list 22 /
  // dispatch 24+ case）是「隱藏門」根因。手術後：
  //   - GET /mcp/tools 與 tools/list 同源（_toolSchemas）
  //   - dispatch 補 get_agent_debug case（get_last_response 9/23 同款 bug 的姐妹案）
  //   - dispatch 新增眼/腦工具：app_view / render_layer / vector_search
  Response _handleMcpToolsList(Request request) {
    return Response.ok(
      jsonEncode(_buildToolsListResult()),
      headers: _jsonHeaders,
    );
  }
  static const _jsonHeaders = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
  };

  // ═══════════════════════════════════════════════════════
  //  [教練 Agent 2026-08-01] 新增 4 個 MCP 端點 handler
  // ═══════════════════════════════════════════════════════

  /// [開光 v0.4.0] 語意點擊核心：找「文字符合 selector 的可點元件」回報座標；
  /// confirm=true 才執行真正的 tap（GestureBinding）——兩段式安全設計。
  Future<Map<String, dynamic>> _handleAppTapCore(Map<String, dynamic> params) async {
    final selector = params['selector'] as String?;
    final x = (params['x'] as num?)?.toDouble();
    final y = (params['y'] as num?)?.toDouble();
    if (onAppTap == null) {
      return {'success': false, 'message': '點擊控制未連接（App 層未掛 callback）'};
    }
    return await onAppTap!(
        selector: selector, x: x, y: y,
        confirm: (params['confirm'] as bool?) ?? false);
  }

  /// [tools_health] canvas state 活性探針（#7 慘案：回 null 讓 agent 猜）
  Future<Map<String, dynamic>?> _getCanvasStateSafe() async {
    if (onGetState == null) return null;
    try {
      final state = await onGetState!();
      return (state as Map?)?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// [開光 P1.5] 隱藏門代理——同進程直呼 handler（不走 loopback HTTP）
  Future<Map<String, dynamic>> _proxyGet(String route) async {
    final req = Request('GET', Uri.parse('http://127.0.0.1:8420$route'));
    final res = await _router(req); // shelf router 直接分派
    final body = await res.readAsString();
    try {
      return (jsonDecode(body) as Map).cast<String, dynamic>();
    } catch (_) {
      return {'raw': body};
    }
  }

  /// [開光 P1 2026-10-01] 頁面捲動核心——隱藏門收編（截圖驗證頁面深處的基礎感官）
  Future<Map<String, dynamic>> _handleAppScrollCore(Map<String, dynamic> params) async {
    final direction = (params['direction'] as String?) ?? 'down';
    final pixels = (params['pixels'] as num?)?.toDouble();
    if (onAppScroll == null) {
      return {'success': false, 'message': '捲動控制未連接（App 層未掛 callback）'};
    }
    return await onAppScroll!(direction, pixels);
  }

  Future<Response> _handleAppScroll(Request request) async {
    final body = jsonDecode(await request.readAsString());
    return Response.ok(
        jsonEncode(await _handleAppScrollCore(
            (body as Map).cast<String, dynamic>())),
        headers: _jsonHeaders);
  }

  Future<Response> _handleSetNodeParams(Request request) async {
    if (onSetNodeParams == null) {
      return Response.ok('{"error": "Set params handler not connected"}', headers: _jsonHeaders);
    }
    final body = jsonDecode(await request.readAsString());
    final nodeId = body['nodeId'] as String;
    final params = (body['params'] as Map<String, dynamic>?) ?? {};
    final result = await onSetNodeParams!(nodeId, params);
    return Response.ok(jsonEncode({'success': true, 'nodeId': nodeId, 'params': result}), headers: _jsonHeaders);
  }

  Future<Response> _handleGetNodeParams(Request request) async {
    if (onGetNodeParams == null) {
      return Response.ok('{"error": "Get params handler not connected"}', headers: _jsonHeaders);
    }
    final nodeId = request.url.queryParameters['nodeId'] ?? '';
    final params = onGetNodeParams!(nodeId);
    return Response.ok(jsonEncode({'nodeId': nodeId, 'params': params}), headers: _jsonHeaders);
  }

  Future<Response> _handleClearCanvas(Request request) async {
    if (onClearCanvas == null) {
      return Response.ok('{"error": "Clear canvas handler not connected"}', headers: _jsonHeaders);
    }
    await onClearCanvas!();
    return Response.ok(jsonEncode({'success': true, 'message': '畫布已清空'}), headers: _jsonHeaders);
  }

  Future<Response> _handleLoadTemplate(Request request) async {
    if (onLoadTemplate == null) {
      return Response.ok('{"error": "Load template handler not connected"}', headers: _jsonHeaders);
    }
    final body = jsonDecode(await request.readAsString());
    final templateId = body['templateId'] as String;
    await onLoadTemplate!(templateId);
    return Response.ok(jsonEncode({'success': true, 'message': '模板已載入: $templateId'}), headers: _jsonHeaders);
  }

  // ═══════════════════════════════════════════════════════
  //  [教練 Agent 2026-08-05] MCP 2026-07-28 標準 JSON-RPC 端點
  //
  //  設計目標：
  //  - 與舊 REST 端點並存（向後相容 Hermes 12 個 hardcode 工具）
  //  - 新增 POST /mcp：JSON-RPC 2.0，dispatch server/discover、tools/list、tools/call
  //  - 新增 GET /mcp/discover：對應 server/discover RPC（方便不熟 JSON-RPC 的 client）
  //  - 所有結果符合 MCP 2026-07-28：resultType=complete + _meta.serverInfo + ttlMs/cacheScope
  //
  //  規格來源：
  //  - https://modelcontextprotocol.io/specification/2026-07-28/changelog
  //  - https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http
  //  - SEP-2575（拿掉 initialize / 改用每 request _meta）
  //  - SEP-2322（resultType 必填 + MRTR 模式）
  // ═══════════════════════════════════════════════════════

  /// MCP 2026-07-28 支援的 protocol 版本（從 changelog 拿到的最新）
  static const String _protocolVersion = '2026-07-28';

  /// MCP 2026-07-28 保留的錯誤碼（per spec/basic/index#error-codes）
  /// -32020 = HeaderMismatch
  /// -32021 = MissingRequiredClientCapability
  /// -32022 = UnsupportedProtocolVersion
  static const int _errHeaderMismatch = -32020;
  static const int _errUnsupportedProtocolVersion = -32022;
  static const int _errMissingRequiredClientCapability = -32021;

  /// POST /mcp — 標準 MCP 2026-07-28 JSON-RPC 2.0 端點
  ///
  /// 必要 header（per spec）：
  /// - `MCP-Protocol-Version: 2026-07-28` （若未帶或帶錯版本，回 400 + -32022）
  /// - `Mcp-Method: <method>` （必填，必須跟 JSON body 的 method 一致；不一致回 400 + -32020）
  /// - `Mcp-Name: <name>`   （僅 tools/call 必填，等於 params.name）
  ///
  /// JSON-RPC body：
  /// {
  ///   "jsonrpc": "2.0",
  ///   "id": 1,
  ///   "method": "tools/call",
  ///   "params": {
  ///     "name": "add_node",
  ///     "arguments": {"type": "llm", "x": 100, "y": 200},
  ///     "_meta": {
  ///       "io.modelcontextprotocol/protocolVersion": "2026-07-28",
  ///       "io.modelcontextprotocol/clientCapabilities": {}
  ///     }
  ///   }
  /// }
  Future<Response> _handleJsonRpc(Request request) async {
    try {
      // 1. Header 驗證（HeaderMismatch = -32020）
      final headerMethod = request.headers['Mcp-Method'];
      final headerName = request.headers['Mcp-Name'];
      final headerProtocolVersion = request.headers['MCP-Protocol-Version'];

      if (headerProtocolVersion != null && headerProtocolVersion != _protocolVersion) {
        return _jsonRpcError(
          null,
          _errUnsupportedProtocolVersion,
          'Unsupported protocol version: $headerProtocolVersion (server: $_protocolVersion)',
        );
      }

      // 2. Parse JSON-RPC body
      final raw = await request.readAsString();
      Map<String, dynamic> body;
      try {
        body = jsonDecode(raw) as Map<String, dynamic>;
      } catch (e) {
        return _jsonRpcError(
          null,
          -32700, // JSON-RPC Parse error
          'Parse error: $e',
        );
      }

      final id = body['id'];
      final method = body['method'] as String?;
      final params = (body['params'] as Map<String, dynamic>?) ?? {};

      // Mcp-Method header 必須與 body method 一致
      if (headerMethod != null && headerMethod != method) {
        return _jsonRpcError(
          id,
          _errHeaderMismatch,
          "Header mismatch: Mcp-Method '$headerMethod' does not match body '$method'",
        );
      }

      if (method == null) {
        return _jsonRpcError(id, -32600, 'Invalid Request: method required');
      }

      // 3. 驗證 params._meta.io.modelcontextprotocol/protocolVersion（per spec，required）
      final paramMeta = (params['_meta'] as Map<String, dynamic>?) ?? {};
      final paramProtocolVersion = paramMeta['io.modelcontextprotocol/protocolVersion'] as String?;
      if (paramProtocolVersion != null && paramProtocolVersion != _protocolVersion) {
        return _jsonRpcError(
          id,
          _errUnsupportedProtocolVersion,
          'Unsupported protocol version in _meta: $paramProtocolVersion',
        );
      }
      // clientCapabilities 是 required（可為空物件）
      if (!paramMeta.containsKey('io.modelcontextprotocol/clientCapabilities')) {
        return _jsonRpcError(
          id,
          _errMissingRequiredClientCapability,
          'Missing required _meta.io.modelcontextprotocol/clientCapabilities',
          data: {'requiredCapabilities': ['clientCapabilities']},
        );
      }

      // 4. Dispatch
      switch (method) {
        case 'server/discover':
          return _jsonRpcResult(id, _buildDiscoverResult());
        case 'tools/list':
          return _jsonRpcResult(id, _buildToolsListResult());
        case 'tools/call':
          final name = (params['name'] as String?) ?? '';
          _dispatchedTools.add(name); // [tools_health] 活性記錄
          // Mcp-Name header 必填且等於 params.name
          if (headerName != null && headerName != name) {
            return _jsonRpcError(
              id,
              _errHeaderMismatch,
              "Header mismatch: Mcp-Name '$headerName' does not match params.name '$name'",
            );
          }
          return await _dispatchToolCall(id, name, params);
        default:
          // JSON-RPC standard: Method not found
          return Response.ok(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'error': {'code': -32601, 'message': 'Method not found: $method'},
            }),
            headers: _jsonHeaders,
          );
      }
    } catch (e, st) {
      debugPrint('[MCP/JSON-RPC] unhandled error: $e\n$st');
      return Response(500,
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32603, 'message': 'Internal error: $e'},
        }),
        headers: _jsonHeaders,
      );
    }
  }

  /// GET /mcp/discover — 對應 server/discover RPC
  /// 給不懂 JSON-RPC 的 client 一個直接 GET 的入口
  Response _handleMcpDiscover(Request request) {
    return Response.ok(
      jsonEncode(_buildDiscoverResult()),
      headers: _jsonHeaders,
    );
  }

  /// 建立 server/discover 結果
  ///
  /// per spec：server 必傳 protocol version + capabilities + identity
  Map<String, dynamic> _buildDiscoverResult() {
    return {
      'resultType': 'complete',
      '_meta': {
        'io.modelcontextprotocol/serverInfo': {
          'name': 'bridge-mcp',
          'version': serverVersion,
          'title': 'Bridge App Canvas MCP Server',
        },
      },
      'protocolVersion': _protocolVersion,
      'supportedVersions': [_protocolVersion],
      'capabilities': {
        'tools': {'listChanged': false},
        // 我們目前不提供 resources / prompts
      },
      'serverInfo': {
        'name': 'bridge-mcp',
        'version': serverVersion,
      },
    };
  }

  /// 建立 tools/list 結果（符合 MCP 2026-07-28 CacheableResult）
  Map<String, dynamic> _buildToolsListResult() {
    return {
      'resultType': 'complete',
      'ttlMs': 60000,
      'cacheScope': 'private',
      '_meta': {
        'io.modelcontextprotocol/serverInfo': {
          'name': 'bridge-mcp',
          'version': serverVersion,
          'title': 'Bridge App Canvas MCP Server', // [開光 P0 2026-09-26] 對齊 discover——舊版 GET /mcp/tools 有 title，RPC 版漏了
        },
      },
      'tools': _toolSchemas,
    };
  }

  /// 工具 schema 定義（JSON Schema 2020-12）
  ///
  /// 這是 MCP 2026-07-28 的 inputSchema 規範：
  /// - 必須是合法 JSON Schema
  /// - tool 描述 + 結構化參數，client 端 LLM 可直接讀懂
  /// - 對應到舊 REST 端點，但用標準 JSON-RPC dispatch
  List<Map<String, dynamic>> get _toolSchemas => [
    {
      'name': 'get_canvas_state',
      'description': '取得完整畫布狀態：所有節點、連線、viewport、選取狀態。讓 Agent 看見畫布上的一切。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'screenshot',
      'description': '拍照：畫布目前畫面（畫布 RepaintBoundary 層，base64 PNG）。用於視覺理解。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'add_node',
      'description': '在畫布上新增一個工作流節點。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'type': {
            'type': 'string',
            'enum': ['input','llm','tool','imageGen','videoGen','musicGen','tts','condition','merge','output','subWorkflow'],
            'description': '節點類型',
          },
          'x': {'type': 'number', 'description': '世界座標 X'},
          'y': {'type': 'number', 'description': '世界座標 Y'},
        },
        'required': ['type', 'x', 'y'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'connect',
      'description': '建立兩個節點之間的連線（output port → input port）。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'fromNodeId': {'type': 'string', 'description': '來源節點 ID'},
          'fromPort': {'type': 'string', 'description': '來源 port 名稱（如 output）'},
          'toNodeId': {'type': 'string', 'description': '目標節點 ID'},
          'toPort': {'type': 'string', 'description': '目標 port 名稱（如 input）'},
        },
        'required': ['fromNodeId', 'fromPort', 'toNodeId', 'toPort'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'remove_node',
      'description': '刪除畫布上的一個節點（含相關連線）。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'nodeId': {'type': 'string', 'description': '要刪除的節點 ID'},
        },
        'required': ['nodeId'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'execute',
      'description': '執行畫布上的工作流。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'navigate_to_canvas',
      'description': 'Agent 主動打開畫布 tab，讓使用者看到畫布。這是「共視」的核心——Agent 不再是盲人摸象，而是跟使用者看同一個畫面。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'send_chat',
      'description': 'Agent 在畫布對話框發送訊息，主動跟使用者互動。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'message': {'type': 'string', 'description': '訊息內容'},
          'role': {'type': 'string', 'enum': ['assistant', 'user'], 'description': '角色（預設 assistant）'},
        },
        'required': ['message'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'send_user_message',
      'description': '模擬使用者在聊天框打字——觸發完整 sendMessage 流程（IntentSpine → 反問 or AgentLoop）。此工具經 sendDirectMessage 送出，不經 UI 輸入框。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'message': {'type': 'string', 'description': '訊息內容'},
        },
        'required': ['message'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'send_canvas_message',
      'description': '派任務到畫布對話框——打到 CanvasChatPanel 的 ChatController，讓 Agent 在畫布當下環境工作（人機共視正確入口）。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'message': {'type': 'string', 'description': '訊息內容'},
        },
        'required': ['message'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'inject_message',
      'description': '使用者插嘴——Agent 工作時注入訊息（不中斷，下一輪 LLM 呼叫前會看到）。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'message': {'type': 'string', 'description': '訊息內容'},
        },
        'required': ['message'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'navigate',
      'description': '統一導航——切到任何頁面。target: home | companion | chat | canvas | brain | vault | system。sub: model | pairing | files | settings（僅 system）。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'target': {
            'type': 'string',
            'enum': ['home', 'companion', 'chat', 'canvas', 'brain', 'vault', 'system'],
            'description': '目標頁面',
          },
          'sub': {'type': 'string', 'description': '系統子頁面（僅 system）'},
        },
        'required': ['target'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'get_app_state',
      'description': '取得當前 App 狀態——回傳當前頁面、系統子頁面、畫布索引。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'list_canvases',
      'description': '列出所有可用畫布。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'load_canvas',
      'description': '載入指定畫布並顯示給使用者。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'canvasId': {'type': 'string', 'description': '畫布 ID'},
        },
        'required': ['canvasId'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'get_annotations',
      'description': '取得使用者塗鴉標注（手繪圈、箭頭、文字）。每個標注有座標、bounds、顏色。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'get_latest_messages',
      'description': '取得 Agent 最新回覆（渲染感應器）——讓外部觀察者知道 Agent 已經回應。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'brain_reindex',
      'description': '重新嵌入所有 mock-fallback 記憶（EmbeddingGemma 模型修復後，舊記憶仍用零向量，需要重算）。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'set_node_params',
      'description': '設定節點參數。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'nodeId': {'type': 'string', 'description': '節點 ID'},
          'params': {
            'type': 'object',
            'description': '節點參數（鍵值對）',
            'additionalProperties': true,
          },
        },
        'required': ['nodeId'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'get_node_params',
      'description': '取得節點參數。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'nodeId': {'type': 'string', 'description': '節點 ID'},
        },
        'required': ['nodeId'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'clear_canvas',
      'description': '清空畫布。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'load_template',
      'description': '一鍵載入範本。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'templateId': {'type': 'string', 'description': '範本 ID'},
        },
        'required': ['templateId'],
        'additionalProperties': false,
      },
    },
    // ── [開光 P0 · 小葵 2026-09-26] 補齊三份清單漂移 ─────────────
    // auto_layout：dispatch 有 case（1601 行舊址）但 tools/list 從未收錄
    {
      'name': 'auto_layout',
      'description': '一鍵自動排版：依連線拓撲分層排開所有節點，消除重疊。人看的故事線=左到右。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    // get_last_response：dispatch 有 case（2026-09-23 修）但 tools/list 未收錄
    {
      'name': 'get_last_response',
      'description': '教練模式：取得 App Agent Loop 最後一條回覆內容。讓外部 Agent 能看見 App 內 Agent 的回答。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    // ── [開光 P0 · 小葵 2026-09-26] 眼/腦工具首次納入 MCP 層 ─────────
    // app_view：App 視網膜拍照（AppRetina.capture 全域 RepaintBoundary），
    // 任何頁面都拍得到——視網膜拍照的 MCP 正名版
    {
      'name': 'app_view',
      'description': '拍照（低解析快照）：拍下整個 App 目前畫面（base64 PNG），不限畫布頁。App 尚未渲染時回 available:false。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'pixelRatio': {
            'type': 'number',
            'description': '拍照解析度倍率（預設 1.5）',
          },
        },
        'additionalProperties': false,
      },
    },
    // render_layer：渲染層場景語言（ActualSizeCache）——canvas_look 對稱版
    {
      'name': 'render_layer',
      'description': '讀場景：畫布渲染層周邊視覺——真實渲染尺寸的節點/重疊/連線場景語言（與原生 Agent canvas_look 同源對稱）。零截圖。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    // vector_search：語意/混合檢索——外部 agent 的大腦查詢通道
    {
      'name': 'vector_search',
      'description': '語意檢索 App 大腦（記憶/知識）。mode=semantic 純語意，mode=hybrid 走 UI 同款完整管線（FTS 擴展+五因素+類型分層）。tech=1 含工程師技術層。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'q': {'type': 'string', 'description': '查詢語句'},
          'limit': {'type': 'number', 'description': '回傳筆數上限（預設 10）'},
          'mode': {
            'type': 'string',
            'description': 'semantic（預設）或 hybrid',
          },
          'tech': {'type': 'number', 'description': '1 = 含 technical 層（工程師模式）'},
        },
        'required': ['q'],
        'additionalProperties': false,
      },
    },
    // inject_enrich：注入管線單一入口——評測與線上同路徑 [小葵 2026-10-10 M1]
    {
      'name': 'inject_enrich',
      'description': 'M1 記憶注入管線單一入口：digest→K1→候選合併→四槽位+預算→注入塊。名詞註冊：四槽位=core/task/episodic/scratch；K1=守門員篩選。與 agent_loop 線上注入同路徑（評測條件=線上條件）。回 input_digest/input_hash/block/injected_ids/latency_ms/dropped_count/k1_hits_n(命中數)/k1_kept_n(進塊數)/embedding_ok/failure_reason。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'q': {'type': 'string', 'description': '使用者訊息（完整原文）'},
          'k1': {'type': 'boolean', 'description': '是否跑 K1 守門員（預設 true）'},
        },
        'required': ['q'],
        'additionalProperties': false,
      },
    },
    // get_agent_debug：教練模式偵錯——provider/model/第幾輪/是否本地
    {
      'name': 'get_agent_debug',
      'description': '教練模式：Agent Loop 偵錯資訊——目前 provider、model、第幾輪、是否本地。用於觀察路由行為。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    // ── [開光 P1 · 小葵 2026-09-26] app.look 語意化視網膜 ─────────
    {
      'name': 'tools_health',
      'description': '[開光 v0.4.0 #7] 工具級自檢：對照 _toolSchemas 與 dispatch case 清單（幽靈工具=有 schema 無 dispatch 立即現形）+ callback 接線狀態彙總。任何工具要嘛正常要嘛明確報錯，不允許優雅地回 null。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'verbose': {'type': 'boolean', 'description': 'true=逐工具明細'},
        },
      },
    },
    // ── [S1 合併 · 2026-10-12] app_look 雙 schema（頁名導航版 vs enum app/screen 版）
    // 合併為一份：target 同時支援導航頁名 / app / screen；保留 region 與 pixelRatio。
    {
      'name': 'app_look',
      'description': '拍照（語意導航版）：說出想看哪裡，就拍到哪裡。target=home/chat/canvas/companion/training/vault/system → 導航後等渲染再拍照（base64 PNG），回傳所在頁面；target=app（預設，不導航）拍 App 當下畫面；target=screen 拍 OS 全螢幕。差異：screenshot=畫布層截圖、app_view=低解析快照、app_look=語意導航拍照、render_layer=圖層隔離、canvas_capture=畫布區域。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'target': {
            'type': 'string',
            'description': '想看的畫面：home/chat/canvas/brain/vault/system/companion/training（導航後拍照）、app=App 當下畫面不導航（預設）、screen=OS 全螢幕',
          },
          'region': {
            'type': 'object',
            'description': '可選裁切 {x,y,w,h}（邏輯像素）',
            'properties': {
              'x': {'type': 'number'}, 'y': {'type': 'number'},
              'w': {'type': 'number'}, 'h': {'type': 'number'},
            },
          },
          'pixelRatio': {
            'type': 'number',
            'description': '拍照解析度倍率（預設 1.5）',
          },
        },
        'additionalProperties': false,
      },
    },
    // ── [開光 P1 · 小葵 2026-09-26] window_map 心之地圖 ───────────
    {
      'name': 'window_map',
      'description': '每視窗地圖：主視窗幾何（window_manager）+ 懸浮夥伴窗狀態（NSPanel）+ 大腦圖譜視窗偵測 + App PID。雙 App 重疊/關錯視窗事故的解藥——先看地圖再動手。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    // ── [開光 P2 · 小葵 2026-09-26] app_tap 語意點擊 ───────────────
    // [S2 合併 · 2026-10-12] 舊 canvas_toolbar 專屬 schema 已刪除——
    // 單一份 app_tap schema 在「54 條隱藏門收編」區（selector/x/y/confirm + target 相容）。
    // ── [開光 P2 · 小葵 2026-09-26] canvas_zoom 讀寫合一 ───────────
    {
      'name': 'canvas_zoom',
      'description': '畫布縮放讀寫合一：不帶參數=讀目前 scale；帶 scale=設定（自動 clamp）；帶 action=fit 全覽畫布內容。回傳 before/after scale。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'scale': {
            'type': 'number',
            'description': '目標縮放（自動 clamp 至合法範圍）。1.0=100%。省略=唯讀',
          },
          'action': {
            'type': 'string',
            'description': 'fit=縮放到看見全部內容（不重排節點）',
          },
        },
        'additionalProperties': false,
      },
    },
    // ── [開光 P3 · 小葵 2026-09-26] app_permissions 權限即地圖 ─────
    {
      'name': 'app_permissions',
      'description': '權限即地圖（紅線是篩選器）：回報 App 能力邊界——sandbox entitlements 聲明（網路/檔案/麥克風/AppleScript）、外部依賴健康度（osascript 可用性）。agent 行動前先看這張圖，不撞了才知道。',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    // ── [開光 P3 · 小葵 2026-09-26] window_control 視窗管理 ────────
    {
      'name': 'window_control',
      'description': '視窗管理官方 API：action=focus（聚焦主視窗）/minimize（最小化）/center（置中）/restore（還原預設大小 1440x900 置中）。先 window_map 看地圖再動手。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'description': 'focus | minimize | center | restore',
          },
        },
        'required': ['action'],
        'additionalProperties': false,
      },
    },
    // ── [開光 P1 · 小葵 2026-10-01] 54 條隱藏門收編 ──
    // 今日實證：截圖驗證「選擇模型」按鈕色，因清單在頁面深處需捲動而卡死
    // ——scroll 這類基礎感官竟不在 discovery。此批收編 agent 高頻隱藏門。
    // [S1 合併 · 2026-10-12] 舊 enum app/screen 版 app_look schema 已刪除——
    // 單一份 schema 在上方（target 支援導航頁名 / app / screen）。
    // ── [S2 合併 · 2026-10-12] app_tap 雙 schema（canvas_toolbar 版 vs selector/x/y 版）
    // 合併為一份：selector/x/y/confirm 為主，target=canvas_toolbar:... 相容舊用法。
    {
      'name': 'app_tap',
      'description': '點擊（語意目標）：selector=按鈕/連結上的文字（如「設為現役」「下載」），或 x/y 座標精密後門。內部自帶定位（key/text 搜尋），不需要視覺辨識。target=canvas_toolbar:save/copy/test/run 為畫布工具列語意點擊（相容舊用法）。confirm=true 才真點擊。點擊後可用 app_look 複核結果。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'selector': {'type': 'string', 'description': '語意選擇器：按鈕/連結上的文字（如「設為現役」「下載」）'},
          'x': {'type': 'number', 'description': '精密後門：App 邏輯座標 x'},
          'y': {'type': 'number', 'description': '精密後門：App 邏輯座標 y'},
          'confirm': {'type': 'boolean', 'description': 'true=執行真點擊（預設 false 只定位回報）'},
          'target': {
            'type': 'string',
            'description': 'canvas_toolbar:save | canvas_toolbar:copy | canvas_toolbar:test | canvas_toolbar:run（畫布工具列語意點擊，相容舊用法）',
          },
        },
        'additionalProperties': false,
      },
    },
    {
      'name': 'app_scroll',
      'description': '捲動目前頁面：direction=up/down/top/bottom，pixels=可選精確量。看見頁面深處的內容（如「選擇模型」清單尾端）。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'direction': {'type': 'string', 'enum': ['up', 'down', 'top', 'bottom'], 'description': '捲動方向'},
          'pixels': {'type': 'number', 'description': '精確捲動像素（與 direction 二選一）'},
        },
        'required': ['direction'],
      },
    },
    {
      'name': 'galaxy_view',
      'description': '大腦星系視圖：galaxy_data 取星系圖資料、galaxy_open 開啟特定節點。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'enum': ['data', 'open', 'ping', 'version'], 'description': 'data=圖資料/open=開節點/ping=活性/version=版本'},
          'nodeId': {'type': 'string', 'description': 'action=open 時的節點 ID'},
        },
        'required': ['action'],
      },
    },
    {
      'name': 'identity_reembed',
      'description': '身份重嵌入進度查詢/觸發（向量資料庫的 identity 嵌入狀態）。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'enum': ['status', 'trigger'], 'description': 'status=查進度/trigger=啟動'},
        },
        'required': ['action'],
      },
    },
    {
      'name': 'vector_sketch',
      'description': '向量素描（VectorSketch）：素描生成進度與狀態查詢。',
      'inputSchema': {
        'type': 'object',
        'properties': {},
      },
    },
    {
      'name': 'import_progress',
      'description': '資料匯入進度（記憶匯入器等長任務的進度查詢）。',
      'inputSchema': {
        'type': 'object',
        'properties': {},
      },
    },
    {
      'name': 'global_notice',
      'description': '全域對話佇列認領（App 有話要對 agent 說時，agent 認領訊息）。',
      'inputSchema': {
        'type': 'object',
        'properties': {},
      },
    },
    {
      'name': 'rescan',
      'description': '手動觸發資料夾重掃（檔案巡邏）。',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'root': {'type': 'string', 'description': '要掃的根目錄路徑（空=全部）'},
        },
      },
    },
  ];

  /// tools/call dispatch — 對應到舊的 callback
  ///
  /// 注意：所有 callback 接到 null 都回 -32603，與舊 REST 端點的 503 行為對齊
  Future<Response> _dispatchToolCall(dynamic id, String name, Map<String, dynamic> params) async {
    final args = (params['arguments'] as Map<String, dynamic>?) ?? {};

    Future<Response> error(String message) async {
      return _jsonRpcError(id, -32603, message);
    }

    try {
      switch (name) {
        case 'get_canvas_state':
          if (onGetState == null) return error('Canvas controller not connected');
          final state = await onGetState!();
          return _jsonRpcResult(id, {'resultType': 'complete', 'state': state, 'ttlMs': 5000, 'cacheScope': 'private'});

        case 'screenshot':
          if (onScreenshot == null) return error('Screenshot not available');
          final base64Png = await onScreenshot!();
          return _jsonRpcResult(id, {
            'resultType': 'complete',
            'image': base64Png,
            'format': 'png',
            'encoding': 'base64',
          });

        case 'add_node':
          if (onAddNode == null) return error('Canvas controller not connected');
          final typeStr = args['type'] as String;
          final x = (args['x'] as num).toDouble();
          final y = (args['y'] as num).toDouble();
          final type = WorkflowNodeType.values.byName(typeStr);
          final nodeId = await onAddNode!(type, x, y);
          return _jsonRpcResult(id, {'resultType': 'complete', 'success': true, 'nodeId': nodeId});

        case 'connect':
          if (onConnect == null) return error('Canvas controller not connected');
          await onConnect!(
            args['fromNodeId'] as String,
            args['fromPort'] as String,
            args['toNodeId'] as String,
            args['toPort'] as String,
          );
          return _jsonRpcResult(id, {'resultType': 'complete', 'success': true});

        case 'remove_node':
          if (onRemoveNode == null) return error('Canvas controller not connected');
          await onRemoveNode!(args['nodeId'] as String);
          return _jsonRpcResult(id, {'resultType': 'complete', 'success': true});

        case 'auto_layout':
          if (onAutoLayout == null) return error('Canvas controller not connected');
          return _jsonRpcResult(id, {'resultType': 'complete', ...onAutoLayout!()});

        case 'execute':
          if (onExecute == null) return error('Executor not connected');
          await onExecute!();
          return _jsonRpcResult(id, {'resultType': 'complete', 'success': true});

        case 'navigate_to_canvas':
          if (onNavigateToCanvas == null) return error('Navigate not available');
          onNavigateToCanvas!();
          return _jsonRpcResult(id, {'resultType': 'complete', 'success': true, 'message': '已切換到畫布 tab'});

        case 'send_chat':
          final message = args['message'] as String;
          final role = args['role'] as String?;
          // [教練 Agent 2026-08-08] send_chat 現在觸發完整 sendMessage 流程，
          // 不只是 UI 注入。優先嘗試 onSendUserMessage（Agent Loop），
          // fallback 到 onSendChat（至少顯示在 UI）。
          if (onSendUserMessage != null) {
            final triggered = onSendUserMessage!(message);
            if (triggered) {
              return _jsonRpcResult(id, {'resultType': 'complete', 'success': true, 'message': 'Message sent (full Agent Loop)'});
            }
          }
          // fallback：至少注入 UI
          if (onSendChat != null) {
            onSendChat!(message, role: role);
            return _jsonRpcResult(id, {'resultType': 'complete', 'success': true, 'message': 'Message injected to UI (Agent Loop not available)'});
          }
          return error('No chat handler available');

        case 'send_user_message':
          if (onSendUserMessage == null) return error('User message handler not available');
          final triggered = onSendUserMessage!(args['message'] as String);
          if (!triggered) {
            return _jsonRpcError(id, -32603, 'Chat controller not ready. Make sure the chat tab is active.');
          }
          return _jsonRpcResult(id, {'resultType': 'complete', 'success': true, 'message': 'Message sent to chat controller'});

        case 'send_canvas_message':
          if (onSendCanvasMessage == null) return error('Canvas message handler not available');
          final triggered = onSendCanvasMessage!(args['message'] as String);
          if (!triggered) {
            return _jsonRpcError(id, -32603, 'Canvas chat controller not ready. Make sure the canvas tab is active.');
          }
          return _jsonRpcResult(id, {'resultType': 'complete', 'success': true, 'message': 'Message sent to canvas chat controller'});

        case 'inject_message':
          if (onInjectMessage == null) return error('Inject handler not available');
          final injected = onInjectMessage!(args['message'] as String);
          return _jsonRpcResult(id, {
            'resultType': 'complete',
            'success': injected,
            'message': injected ? 'Message injected to AgentLoop' : 'AgentLoop not running or not ready',
          });

        // ── [開光 v0.4.0 · 2026-10-01] 眼與手：app_look / app_tap ──
        case 'tools_health': {
          // [開光 v0.4.0 #7] 幽靈工具現形 + callback 接線彙總
          final verbose = (args['verbose'] as bool?) ?? false;
          final schemaNames = _toolSchemas.map((t) => t['name'] as String).toSet();
          final knownDispatched = _dispatchedTools;
          final neverDispatched = schemaNames.difference(knownDispatched).toList()..sort();
          final callbacks = <String, bool>{
            'onAppScroll': onAppScroll != null,
            'onAppTap': onAppTap != null,
            'onSetNodeParams': onSetNodeParams != null,
            'onGetNodeParams': onGetNodeParams != null,
          };
          final missingCallbacks =
              [for (final e in callbacks.entries) if (!e.value) e.key];
          // get_canvas_state 活性探針（9/23 回 null 慘案的針對性檢查）
          String? canvasStateProbe;
          if (onGetState == null) {
            canvasStateProbe = 'callback 未接線';
          } else {
            try {
              final st = await _getCanvasStateSafe();
              canvasStateProbe = st == null
                  ? 'null（序列化異常——原 #7 慘案形態）'
                  : 'ok（${(st['nodes'] as List?)?.length ?? '?'} 節點）';
            } catch (e) {
              canvasStateProbe = 'exception: $e';
            }
          }
          final healthy = missingCallbacks.isEmpty && canvasStateProbe!.startsWith('ok');
          return _jsonRpcResult(id, {
            'resultType': 'complete',
            'healthy': healthy,
            'toolsTotal': schemaNames.length,
            'dispatchedEver': knownDispatched.length,
            'neverDispatched': neverDispatched, // 曾經宣告但從未被叫過（含幽靈與冷門）
            'callbacksWired': callbacks,
            'missingCallbacks': missingCallbacks,
            'canvasStateProbe': canvasStateProbe,
            if (verbose) 'allTools': schemaNames.toList()..sort(),
            'checkedAt': DateTime.now().toIso8601String(),
            if (!healthy)
              'message': '有未接線 callback 或 canvas_state 異常——詳見各欄位',
          });
        }
        case 'app_look': {
          // [S1 合併 · 2026-10-12] 雙 case（語意導航版 vs enum app/screen 版）合併：
          // target=screen → OS 全螢幕；target=app（預設）→ 不導航拍當下；
          // 其他合法頁名 → 導航 → 等渲染 → 拍照（原語意導航版邏輯）。
          const validTargets = [
            'app', 'home', 'chat', 'canvas', 'brain', 'vault', 'system',
            'companion', 'training', 'screen',
          ];
          final target = (args['target'] as String?) ?? 'app';
          if (!validTargets.contains(target)) {
            return _jsonRpcError(id, -32602,
                'Invalid target: $target. Valid: ${validTargets.join("/")}');
          }
          if (target == 'screen') {
            // [開光 v0.4.x · 2026-10-01] OS 層視網膜——
            // 走 ScreenCaptureNative（Swift 進程內 CGWindowList，非 sandbox 子進程）
            if (onScreenCapture == null) {
              return _jsonRpcResult(id, {
                'resultType': 'complete', 'available': false,
                'message': '螢幕拍攝 callback 未接線（onScreenCapture）',
              });
            }
            try {
              final b64 = await onScreenCapture!();
              if (b64 == null || b64.isEmpty) {
                return _jsonRpcResult(id, {
                  'resultType': 'complete', 'available': false,
                  'message': 'OS 拍攝回空（可能未授螢幕錄製權限）',
                });
              }
              return _jsonRpcResult(id, {
                'resultType': 'complete', 'available': true,
                'image': b64, 'format': 'png', 'encoding': 'base64',
                'target': 'screen', 'bytes': (b64.length * 3) ~/ 4,
                'capturedAt': DateTime.now().toIso8601String(),
              });
            } catch (e) {
              return _jsonRpcResult(id, {'resultType': 'complete', 'available': false, 'message': 'OS 拍攝失敗: $e'});
            }
          }
          // 導航（brain 開獨立視窗不適用視網膜；target=app 不導航）
          if (target != 'app' && target != 'brain') {
            if (onNavigate == null) return error('Navigation not available');
            onNavigate!(target, null);
          }
          if (target == 'brain') {
            // [S1 合併 · 2026-10-12] brain 回覆改用 galaxy 指引訊息（原語意導航版語意）
            return _jsonRpcResult(id, {
              'resultType': 'complete',
              'available': false,
              'target': target,
              'message': 'brain 開獨立瀏覽器視窗，視網膜拍不到——改用 /galaxy 頁或 galaxy 截圖指令',
            });
          }
          // 等渲染（幀 Budget：300ms 導航動畫 + 200ms settle）
          await Future<void>.delayed(const Duration(milliseconds: 500));
          try {
            final b64 = await AppRetina.capture(
              pixelRatio: (args['pixelRatio'] as num?)?.toDouble() ?? 1.5,
            );
            if (b64 == null) {
              return _jsonRpcResult(id, {'resultType': 'complete', 'available': false, 'target': target, 'message': 'App 尚未渲染'});
            }
            final page = (onGetAppState != null) ? onGetAppState!()['page'] : null;
            return _jsonRpcResult(id, {
              'resultType': 'complete',
              'available': true,
              'target': target,
              'page': page,
              'image': b64,
              'format': 'png',
              'encoding': 'base64',
              'capturedAt': DateTime.now().toIso8601String(),
            });
          } catch (e) {
            return _jsonRpcResult(id, {'resultType': 'complete', 'available': false, 'target': target, 'message': '視網膜拍照失敗: $e'});
          }
        }
        case 'app_tap':
          // [S2 合併 · 2026-10-12] 雙 case（canvas_toolbar 版 vs selector/x/y 版）合併：
          // args 帶 target（且無 selector/x）→ 走 canvas_toolbar 語意點擊（相容舊用法）；
          // 否則走 selector/x/y/confirm 核心定位/點擊。
          final tapTarget = args['target'] as String?;
          final tapSelector = args['selector'] as String?;
          final tapX = args['x'] as num?;
          if (tapTarget != null && tapSelector == null && tapX == null) {
            // canvas_toolbar 舊路徑：參數驗證先於接線檢查——target 錯就是錯
            if (tapTarget.isEmpty) {
              return _jsonRpcError(id, -32602, 'target required');
            }
            const validTaps = [
              'canvas_toolbar:save', 'canvas_toolbar:copy',
              'canvas_toolbar:test', 'canvas_toolbar:run',
            ];
            if (!validTaps.contains(tapTarget)) {
              return _jsonRpcError(id, -32602,
                  'Invalid target: $tapTarget. Valid: ${validTaps.join("/")}');
            }
            if (onTap == null) return error('Tap handler not connected');
            final result = onTap!(tapTarget);
            return _jsonRpcResult(id, {'resultType': 'complete', ...?result});
          }
          return _jsonRpcResult(id, await _handleAppTapCore(args));
        // ── [開光 P1.5 · 2026-10-01] 隱藏門收編：schema+dispatch 全接線 ──
        case 'galaxy_view': {
          final action = (args['action'] as String?) ?? 'data';
          final routeMap = {
            'data': '/galaxy_data', 'open': '/galaxy_open',
            'ping': '/galaxy_ping', 'version': '/galaxy_version',
          };
          final route = routeMap[action] ?? '/galaxy_data';
          return _jsonRpcResult(id, await _proxyGet(route));
        }
        case 'galaxy_cmd':
          return _jsonRpcResult(id, await _proxyGet('/galaxy_cmd'));
        case 'galaxy_oplog':
          return _jsonRpcResult(id, await _proxyGet('/galaxy_oplog'));
        case 'galaxy_note':
          return _jsonRpcResult(id, await _proxyGet('/galaxy_note'));
        case 'galaxy_edit':
          return _jsonRpcResult(id, await _proxyGet('/galaxy_edit'));
        case 'galaxy_params':
          return _jsonRpcResult(id, await _proxyGet('/galaxy_params'));
        case 'galaxy_icons':
          return _jsonRpcResult(id, await _proxyGet('/galaxy_icons'));
        case 'galaxy_thumb':
          return _jsonRpcResult(id, await _proxyGet('/galaxy_thumb'));
        case 'galaxy_swarm':
          return _jsonRpcResult(id, await _proxyGet('/galaxy_swarm_live'));
        case 'identity_reembed':
          return _jsonRpcResult(id, await _proxyGet('/identity_reembed'));
        case 'vector_sketch':
          return _jsonRpcResult(id, await _proxyGet('/vector_sketch'));
        case 'import_progress':
          return _jsonRpcResult(id, await _proxyGet('/import_progress'));
        case 'global_notice':
          return _jsonRpcResult(id, await _proxyGet('/global_notice'));
        case 'rescan':
          return _jsonRpcResult(id, await _proxyGet('/rescan'));
        case 'annotations':
          return _jsonRpcResult(id, await _proxyGet('/annotations'));
        case 'brain_search_focus':
          return _jsonRpcResult(id, await _proxyGet('/brain_search_focus'));
        case 'design_thumb_reindex':
          return _jsonRpcResult(id, await _proxyGet('/design_thumb_reindex'));
        case 'fps_probe':
          return _jsonRpcResult(id, await _proxyGet('/fps_probe'));
        case 'app_scroll':
          // [benchmark 抓包 2026-10-01] 傳 args 而非 params——direction 藏在
          // params['arguments'] 內，傳錯層導致 bottom 永遠被當 down+600
          return _jsonRpcResult(id, await _handleAppScrollCore(args));
        case 'navigate':
          if (onNavigate == null) return error('Navigation not available');
          final target = args['target'] as String? ?? 'home';
          final sub = args['sub'] as String?;
          onNavigate!(target, sub);
          return _jsonRpcResult(id, {
            'resultType': 'complete',
            'success': true,
            'message': 'Navigated to $target${sub != null ? ' > $sub' : ''}',
          });

        case 'get_app_state':
          if (onGetAppState == null) return error('App state not available');
          return _jsonRpcResult(id, {'resultType': 'complete', 'state': onGetAppState!()});

        case 'list_canvases':
          if (onListCanvases == null) return error('List not available');
          return _jsonRpcResult(id, {'resultType': 'complete', 'canvases': onListCanvases!()});

        case 'load_canvas':
          if (onLoadCanvas == null) return error('Load not available');
          onLoadCanvas!(args['canvasId'] as String);
          return _jsonRpcResult(id, {'resultType': 'complete', 'success': true});

        case 'get_annotations':
          if (onGetAnnotations == null) return error('Annotations not available');
          final annotations = onGetAnnotations!();
          return _jsonRpcResult(id, {'resultType': 'complete', 'annotations': annotations, 'count': annotations.length});

        // [小葵 2026-09-23 修 bug] get_last_response 在工具清單虛報但
        // dispatch 沒 case——外部 Agent 呼叫一律 Unknown tool。
        // 實作＝get_latest_messages 同款（CanvasMcpRegistry.lastAgentReply）。
        case 'get_last_response':
          final reg = CanvasMcpRegistry.instance;
          final reply = reg.lastAgentReply;
          if (reply.isEmpty) {
            return _jsonRpcResult(id, {'resultType': 'complete', 'hasNewReply': false, 'message': 'No agent reply yet'});
          }
          return _jsonRpcResult(id, {
            'resultType': 'complete',
            'hasNewReply': true,
            'content': reply,
            'length': reply.length,
            'timestamp': DateTime.now().toIso8601String(),
          });

        case 'get_latest_messages':
          final reg = CanvasMcpRegistry.instance;
          final reply = reg.lastAgentReply;
          if (reply.isEmpty) {
            return _jsonRpcResult(id, {'resultType': 'complete', 'hasNewReply': false, 'message': 'No agent reply yet'});
          }
          return _jsonRpcResult(id, {
            'resultType': 'complete',
            'hasNewReply': true,
            'content': reply,
            'length': reply.length,
            'timestamp': DateTime.now().toIso8601String(),
          });

        case 'brain_reindex':
          final count = await BrainContainerService.instance.reindexFallbackMemories();
          return _jsonRpcResult(id, {'resultType': 'complete', 'success': true, 'reindexed': count, 'model': 'gemma-300m-v1'});

        case 'set_node_params':
          if (onSetNodeParams == null) return error('Set params handler not connected');
          final nodeId = args['nodeId'] as String;
          final nodeParams = (args['params'] as Map<String, dynamic>?) ?? {};
          final result = await onSetNodeParams!(nodeId, nodeParams);
          return _jsonRpcResult(id, {'resultType': 'complete', 'success': true, 'nodeId': nodeId, 'params': result});

        case 'get_node_params':
          if (onGetNodeParams == null) return error('Get params handler not connected');
          final nodeId = args['nodeId'] as String? ?? '';
          final nodeParams = onGetNodeParams!(nodeId);
          return _jsonRpcResult(id, {'resultType': 'complete', 'nodeId': nodeId, 'params': nodeParams});

        case 'clear_canvas':
          if (onClearCanvas == null) return error('Clear canvas handler not connected');
          await onClearCanvas!();
          return _jsonRpcResult(id, {'resultType': 'complete', 'success': true, 'message': '畫布已清空'});

        case 'load_template':
          if (onLoadTemplate == null) return error('Load template handler not connected');
          final templateId = args['templateId'] as String;
          await onLoadTemplate!(templateId);
          return _jsonRpcResult(id, {'resultType': 'complete', 'success': true, 'message': '模板已載入: $templateId'});

        // ── [開光 P0 · 小葵 2026-09-26] dispatch 補缺 + 眼/腦工具 ─────────
        // get_agent_debug：清單曾宣稱（GET /mcp/tools 舊版）但 dispatch 沒 case——
        // get_last_response 9/23 同款「清單有、dispatch 沒」bug 的姐妹案
        case 'get_agent_debug':
          if (onGetAgentDebugInfo == null) {
            return _jsonRpcResult(id, {'resultType': 'complete', 'available': false, 'message': 'Debug handler not connected'});
          }
          final info = onGetAgentDebugInfo!();
          if (info == null) {
            return _jsonRpcResult(id, {'resultType': 'complete', 'available': false, 'message': 'Agent Loop not running'});
          }
          return _jsonRpcResult(id, {'resultType': 'complete', 'available': true, ...info, 'timestamp': DateTime.now().toIso8601String()});

        // app_view：視網膜拍照 MCP 正名版——AppRetina 自包含，不需 callback
        // [開光] 眼的語意：看不見（未渲染/無 binding/拍照失敗）一律 available:false
        // 附原因——誠實報「看不見」，不噴 -32603 讓 agent 猜
        case 'app_view':
          try {
            final b64 = await AppRetina.capture(
              pixelRatio: (args['pixelRatio'] as num?)?.toDouble() ?? 1.5,
            );
            if (b64 == null) {
              return _jsonRpcResult(id, {'resultType': 'complete', 'available': false, 'message': 'App 尚未渲染'});
            }
            return _jsonRpcResult(id, {
              'resultType': 'complete',
              'available': true,
              'image': b64,
              'format': 'png',
              'encoding': 'base64',
              'capturedAt': DateTime.now().toIso8601String(),
            });
          } catch (e) {
            return _jsonRpcResult(id, {'resultType': 'complete', 'available': false, 'message': '視網膜拍照失敗: $e'});
          }

        // render_layer：渲染層場景語言（canvas_look 對稱）
        case 'render_layer':
          if (onGetRenderLayer == null) return error('Render layer not available');
          final data = await onGetRenderLayer!();
          return _jsonRpcResult(id, {'resultType': 'complete', ...data});

        // inject_enrich：注入管線單一入口（M1——評測與線上同路徑）
        case 'inject_enrich':
          final q = args['q'] as String? ?? '';
          if (q.isEmpty) {
            return _jsonRpcError(id, -32602, 'q required');
          }
          final useK1 = args['k1'] as bool? ?? true;
          try {
            final outcome = await InjectionPreparer.instance.prepare(
              q,
              k1: useK1,
              logSample: false,
            );
            return _jsonRpcResult(id, {
              'resultType': 'complete',
              'q': q,
              'input_digest': outcome.inputDigest,
              'input_hash': outcome.inputHash,
              'block': outcome.block,
              'injected_ids': outcome.ids,
              'latency_ms': outcome.latencyMs,
              'dropped_count': outcome.droppedCount,
              'k1_hits_n': outcome.k1MergedN,
              'k1_kept_n': outcome.k1KeptN,
              'embedding_ok': outcome.embeddingOk,
              'k1_label': outcome.k1Label,
              'k1_confidence': outcome.k1Confidence,
              'k1_escalated': outcome.k1Escalated,
              'k1_source': outcome.k1Source,
              if (outcome.failureReason != null)
                'failure_reason': outcome.failureReason,
            });
          } catch (e) {
            return _jsonRpcError(id, -32603, 'inject_enrich failed: $e');
          }

        // vector_search：大腦語意檢索
        // [開光] 序列化對齊 REST 版——HybridSearchResults 是物件不可直接 jsonEncode
        case 'vector_search':
          final q = args['q'] as String? ?? '';
          if (q.isEmpty) {
            return _jsonRpcError(id, -32602, 'q required');
          }
          final limit = (args['limit'] as num?)?.toInt() ?? 10;
          final mode = args['mode'] as String? ?? 'semantic';
          final includeTechnical = (args['tech'] as num?)?.toInt() == 1;
          try {
            final results = await HybridSearchService.instance.search(
              query: q,
              mode: mode == 'hybrid' ? SearchMode.hybrid : SearchMode.semantic,
              limit: limit,
              includeTechnical: includeTechnical,
            );
            return _jsonRpcResult(id, {
              'resultType': 'complete',
              'query': q,
              'mode': mode,
              'memoryHits': results.memoryHits
                  .map((h) => {
                        'id': h.id,
                        'room': h.room,
                        'score': h.score.toStringAsFixed(4),
                        'content': h.content.length > 80 ? '${h.content.substring(0, 80)}…' : h.content,
                      })
                  .toList(),
              'assetHits': results.assetHits
                  .map((h) => {
                        'id': h.id,
                        'file': h.fileName,
                        'path': h.filePath,
                        'score': h.score.toStringAsFixed(4),
                      })
                  .toList(),
              'crossLinks': results.crossLinks.length,
              if (results.synthesizedAnswer != null)
                'synthesizedAnswer': results.synthesizedAnswer,
            });
          } catch (e) {
            return _jsonRpcError(id, -32603, 'Vector search failed: $e');
          }

        // ── [開光 P1 · 小葵 2026-09-26] app_look 語意化視網膜 ─────────
        // [S1 合併 · 2026-10-12] 舊語意導航版 case 已刪除——
        // 單一 app_look case 在上方（screen/app/導航頁名三路合一）。
        // 「說出想看哪裡，就拍到哪裡」：導航 → 等渲染 → AppRetina 拍照。

        // ── [開光 P1 · 小葵 2026-09-26] window_map 心之地圖 ───────────
        // 主視窗幾何 + 懸浮窗 + galaxy 偵測 + PID——先看地圖再動手。
        case 'window_map':
          final map = <String, dynamic>{
            'pid': pid,
            'mcpPort': port,
            'capturedAt': DateTime.now().toIso8601String(),
          };
          try {
            final size = await windowManager.getSize();
            final position = await windowManager.getPosition();
            final isFocused = await windowManager.isFocused();
            final isVisible = await windowManager.isVisible();
            map['mainWindow'] = {
              'width': size.width.round(),
              'height': size.height.round(),
              'x': position.dx.round(),
              'y': position.dy.round(),
              'focused': isFocused,
              'visible': isVisible,
            };
          } catch (_) {
            map['mainWindow'] = {'available': false, 'reason': 'window_manager 未初始化（測試環境）'};
          }
          try {
            final companion = await const MacosDesktopShellChannel().snapshot();
            if (companion != null) {
              map['companionPanel'] = {
                'available': true,
                'visible': companion.visible,
                'paused': companion.paused,
                'alwaysOnTop': companion.alwaysOnTop,
                'width': companion.width.round(),
                'height': companion.height.round(),
                'companionName': companion.companionName,
                'statusText': companion.statusText,
              };
            } else {
              map['companionPanel'] = {'available': false};
            }
          } catch (_) {
            map['companionPanel'] = {'available': false, 'reason': 'shell channel 未連線'};
          }
          try {
            // galaxy 視窗偵測：Chrome --app 視窗標題「橋樑大腦圖譜」
            final r = Process.runSync('osascript', [
              '-e',
              'tell application "System Events" to get name of every window of every process whose name is "Google Chrome"',
            ]);
            final titles = (r.stdout as String).trim();
            map['galaxyWindow'] = {
              'detected': titles.contains('橋樑大腦圖譜'),
              'title': titles.contains('橋樑大腦圖譜') ? '橋樑大腦圖譜' : null,
            };
          } catch (_) {
            map['galaxyWindow'] = {'detected': false, 'reason': 'osascript/權限不可用'};
          }
          return _jsonRpcResult(id, {'resultType': 'complete', ...map});

        // ── [開光 P2 · 小葵 2026-09-26] app_tap 語意點擊 ───────────────
        // [S2 合併 · 2026-10-12] 舊 canvas_toolbar 專屬 case 已刪除——
        // 單一 app_tap case 在上方（target 舊路徑與 selector/x/y 核心二合一）。
        // 手的語意化：按鈕名而非座標。回呼式接線（同 auto_layout 慣例）。

        // ── [開光 P2 · 小葵 2026-09-26] canvas_zoom 讀寫合一 ───────────
        // 走 CanvasMcpRegistry.controller——ambient 覆寫時自動路由到任務工作畫布
        case 'canvas_zoom':
          final reg = CanvasMcpRegistry.instance;
          final ctrl = reg.controller;
          if (ctrl == null) return error('Canvas controller not connected');
          final before = ctrl.state.viewport.scale;
          final scaleArg = (args['scale'] as num?)?.toDouble();
          final action = args['action'] as String?;
          if (scaleArg != null) {
            // 寫：設定縮放（clamp 由 controller.zoom 內部處理）
            final size = reg.canvasPixelSize;
            final focal = size != null
                ? Offset(size.width / 2, size.height / 2)
                : const Offset(720, 450);
            ctrl.zoom(scaleArg, focal);
          } else if (action == 'fit') {
            final size = reg.canvasPixelSize;
            if (size != null) {
              ctrl.fitToContent(size, padding: 100);
            } else {
              return error('canvasPixelSize 未就緒（畫布未掛載）');
            }
          }
          final after = ctrl.state.viewport.scale;
          return _jsonRpcResult(id, {
            'resultType': 'complete',
            'before': double.parse(before.toStringAsFixed(3)),
            'after': double.parse(after.toStringAsFixed(3)),
            'percent': '${(after * 100).round()}%',
            'mode': scaleArg != null ? 'set' : (action == 'fit' ? 'fit' : 'read'),
          });

        // ── [開光 P3 · 小葵 2026-09-26] app_permissions 權限即地圖 ─────
        // 紅線是篩選器：行動前先看邊界。讀 entitlements 宣告 + 探測外部依賴。
        case 'app_permissions':
          final perms = <String, dynamic>{
            'pid': pid,
            'capturedAt': DateTime.now().toIso8601String(),
          };
          // ① sandbox entitlements——codesign 讀簽章時的 entitlements（最準）
          try {
            final exePath = Platform.resolvedExecutable;
            final appRoot = exePath.split('/Contents/MacOS/').first;
            final r = Process.runSync('codesign', [
              '-d', '--entitlements', '-', appRoot,
            ]);
            final xml = (r.stdout as String) + (r.stderr as String);
            perms['entitlements'] = {
              'appSandbox': xml.contains('com.apple.security.app-sandbox'),
              'networkClient': xml.contains('com.apple.security.network.client'),
              'networkServer': xml.contains('com.apple.security.network.server'),
              'audioInput': xml.contains('com.apple.security.device.audio-input'),
              'userSelectedFilesRead': xml.contains('user-selected.read-only'),
              'userSelectedFilesReadWrite': xml.contains('user-selected.read-write'),
              'appleEvents': xml.contains('temporary-exception.apple-events'),
              'camera': xml.contains('com.apple.security.device.camera'),
            };
          } catch (e) {
            perms['entitlements'] = {'available': false, 'reason': 'codesign 讀取失敗: $e'};
          }
          // ② 外部依賴健康度——agent 常用通道的實測可用性
          final deps = <String, dynamic>{};
          try {
            final r = Process.runSync('osascript', ['-e', 'return "ok"']);
            deps['osascript'] = r.exitCode == 0 && (r.stdout as String).trim() == 'ok';
          } catch (_) {
            deps['osascript'] = false;
          }
          try {
            // 真拍 1x1 驗證（-h 的 exit code 不可靠，會誤報 false）
            final probe = '/tmp/.bridge_perm_probe.png';
            final r = Process.runSync(
                'screencapture', ['-x', '-R0,0,1,1', probe]);
            final ok = r.exitCode == 0;
            final f = File(probe);
            if (f.existsSync()) f.deleteSync();
            deps['screencapture'] = ok;
          } catch (_) {
            deps['screencapture'] = false;
          }
          perms['dependencies'] = deps;
          // [開光 P3] 誠實語意：沙盒內 screencapture 靜默失敗是事實，
          // 給 agent 指路——App 自家視網膜（app_look/app_view）才是正道
          if (deps['screencapture'] != true) {
            perms['hint'] = '沙盒內 screencapture 不可用屬實（無 TCC 條目、外部 binary 被擋）。'
                '要拍 App 畫面請改用 app_look / app_view（App 自家視網膜，更快更穩）。';
          }
          return _jsonRpcResult(id, {'resultType': 'complete', ...perms});

        // ── [開光 P3 · 小葵 2026-09-26] window_control 視窗管理 ────────
        case 'window_control':
          final action = args['action'] as String? ?? '';
          const validActions = ['focus', 'minimize', 'center', 'restore'];
          if (!validActions.contains(action)) {
            return _jsonRpcError(id, -32602,
                'Invalid action: $action. Valid: ${validActions.join("/")}');
          }
          try {
            switch (action) {
              case 'focus':
                await windowManager.focus();
              case 'minimize':
                await windowManager.minimize();
              case 'center':
                await windowManager.center();
              case 'restore':
                await windowManager.setSize(const Size(1440, 900));
                await windowManager.center();
            }
            final size = await windowManager.getSize();
            final position = await windowManager.getPosition();
            return _jsonRpcResult(id, {
              'resultType': 'complete',
              'success': true,
              'action': action,
              'after': {
                'width': size.width.round(),
                'height': size.height.round(),
                'x': position.dx.round(),
                'y': position.dy.round(),
              },
            });
          } catch (e) {
            return _jsonRpcResult(id, {
              'resultType': 'complete',
              'success': false,
              'action': action,
              'message': 'window_manager 未初始化或操作失敗: $e',
            });
          }

        default:
          return _jsonRpcError(id, -32602, 'Unknown tool: $name');
      }
    } catch (e) {
      debugPrint('[MCP/JSON-RPC] tool=$name error: $e');
      return _jsonRpcError(id, -32603, 'Tool execution error: $e');
    }
  }

  /// 包裝 JSON-RPC success result
  Response _jsonRpcResult(dynamic id, Map<String, dynamic> result) {
    // 確保 resultType 存在（MCP 2026-07-28 必填）
    if (!result.containsKey('resultType')) {
      result['resultType'] = 'complete';
    }
    return Response.ok(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      }),
      headers: _jsonHeaders,
    );
  }

  /// 包裝 JSON-RPC error response
  Response _jsonRpcError(dynamic id, int code, String message, {dynamic data}) {
    final errorBody = <String, dynamic>{'code': code, 'message': message};
    if (data != null) errorBody['data'] = data;
    return Response.ok(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'error': errorBody,
      }),
      headers: _jsonHeaders,
    );
  }

  // ── [小葵 2026-08-27] 3D 星系模式 ──────────────────────────────

  /// GET /galaxy — 星系頁（webview 用 http://localhost:8420/galaxy 載入，
  /// 同源 fetch /galaxy_data，避開 file:// 協定限制）
// [小葵 2026-09-24 出道令] Agent 操控星系通道
// POST /galaxy_cmd {op:'spin'|'rotate'|'fly_hub'|...} → 入佇列
// GET  /galaxy_cmd_poll → 頁面 1s 輪詢認領（galaxy.html __galaxyCmdPoll 派發）
static final List<String> _galaxyCmdQueue = [];

  Future<Response> _handleGalaxyCmd(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      if (_galaxyCmdQueue.length > 50) _galaxyCmdQueue.removeRange(0, 25); // 防爆
      _galaxyCmdQueue.add(jsonEncode(body));
      return Response.ok(jsonEncode({'success': true, 'queued': _galaxyCmdQueue.length}),
          headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleGalaxyCmdPoll(Request request) async {
    final cmds = List<String>.from(_galaxyCmdQueue);
    _galaxyCmdQueue.clear();
    return Response.ok(jsonEncode({'cmds': cmds}), headers: _jsonHeaders);
  }

  Future<Response> _handleGetGalaxyPage(Request req) async {
    try {
      final html = await rootBundle.loadString('assets/galaxy/galaxy.html');
      // [小葵 2026-08-28 v10] no-cache：webview 一律吃最新版（舊版殘留=0% 全亮假象）
      // [v256 Blue 卡頓令] COOP/COEP=high-resolution timers——motion.dev 記載
      // 的 rAF 節流繞法（WebKit 100ms throttling 對 embedded view）。
      //代價：跨源資源要 CORS——本頁全 same-origin（three.js 已 inline）✓
      return Response.ok(html, headers: {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store, no-cache, must-revalidate',
        'Cross-Origin-Opener-Policy': 'same-origin',
        'Cross-Origin-Embedder-Policy': 'require-corp',
      });
    } catch (e) {
      return Response.ok('<h3>galaxy.html asset 讀取失敗: $e</h3>',
          headers: {'Content-Type': 'text/html; charset=utf-8'});
    }
  }

  /// GET /galaxy_swarm_layer — [TRIO M5a] 戰爭層 JS（same-origin 供應，COEP 合規）
  Future<Response> _handleGetSwarmLayer(Request req) async {
    try {
      final js = await rootBundle.loadString('assets/galaxy/swarm_layer.js');
      return Response.ok(js, headers: {
        'Content-Type': 'application/javascript; charset=utf-8',
        'Cache-Control': 'no-store',
      });
    } catch (e) {
      return Response.ok('console.warn("[swarm] $e");',
          headers: {'Content-Type': 'application/javascript; charset=utf-8'});
    }
  }

  /// GET /galaxy_swarm_campaigns — [M5b] 戰役資產列表（作戰模式選單）
  /// GET /galaxy_missions — [H5] 戰爭模式任務面板資料包
  /// 「同時看見要做什麼（任務）與腦內正在發生什麼（作戰事件流）」
  /// —— Phase H spec §4 獨家場景的資料側。
  Future<Response> _handleGetGalaxyMissions(Request req) async {
    try {
      // [H4] 排程卡（Hermes cron 重現——真相源只讀）
      final schedules = await ScheduleRegistry.instance.loadAll();
      // 專案門看板（進行中/等待中）
      final doors = await ProjectDoorStore().loadAll();
      return Response.ok(jsonEncode({
        'schedules': [
          for (final c in schedules)
            {
              'id': c.id,
              'name': c.name,
              'human': c.humanSchedule,
              'warmth': c.warmth.name,
              if (c.warmLine != null) 'warmLine': c.warmLine,
              if (c.nextRun != null)
                'nextRun': c.nextRun!.toIso8601String(),
            }
        ],
        'projects': [
          for (final d in doors)
            {
              'id': d.id,
              'title': d.title,
              'status': d.status,
            }
        ],
      }), headers: _jsonHeaders);
    } catch (e) {
      return Response.ok(jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  Future<Response> _handleGetSwarmCampaigns(Request req) async {
    try {
      final list = await SwarmCampaignAssets.instance.listCampaigns();
      return Response.ok(jsonEncode({'campaigns': list}),
          headers: _jsonHeaders);
    } catch (e) {
      return Response.ok(jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  /// GET /galaxy_swarm_events?id= — [M5b] 單戰役事件流（回放原料）
  Future<Response> _handleGetSwarmEvents(Request req) async {
    try {
      final id = req.url.queryParameters['id'] ?? '';
      if (id.isEmpty) {
        return Response.ok(jsonEncode({'error': 'id 必填'}),
            headers: _jsonHeaders);
      }
      final events = await SwarmCampaignAssets.instance.loadEvents(id);
      return Response.ok(jsonEncode({
        'campaignId': id,
        'events': events.map((e) => e.toJson()).toList(),
      }), headers: _jsonHeaders);
    } catch (e) {
      return Response.ok(jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  /// GET /galaxy_swarm_live — [M5b LIVE] 事件驅動推送（SSE）
  /// 每個作戰事件（spawn/success/fail/...）即時推送給星系 LIVE 層——
  /// 零輪詢。斷線自動重連（EventSource 原生）。
  Future<Response> _handleSwarmLiveSse(Request req) async {
    final controller = StreamController<List<int>>();
    Timer? keepalive;
    late StreamSubscription sub;
    sub = swarmEventBus.stream.listen((e) {
      try {
        controller.add(utf8.encode('data: ${jsonEncode(e.toJson())}\n\n'));
      } catch (_) {}
    });
    keepalive = Timer.periodic(const Duration(seconds: 15), (_) {
      try {
        controller.add(utf8.encode(': keepalive\n\n'));
      } catch (_) {
        sub.cancel();
        keepalive?.cancel();
      }
    });
    // 連線結束（shelf read into sink 完成/斷線）→ 清訂閱防洩漏
    unawaited(controller.done.then((_) {
      sub.cancel();
      keepalive?.cancel();
    }));
    return Response.ok(controller.stream, headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-store',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    });
  }

  /// POST /design_thumb_reindex — 手動觸發專業製圖檔縮圖嵌入（診斷用）
  Future<Response> _handleDesignThumbReindex(Request request) async {
    DesignFileThumbnailService.instance.start(); // fire-and-forget
    return Response.ok(
        jsonEncode({'success': true, 'message': 'design thumb reindex started'}),
        headers: _jsonHeaders);
  }

  /// GET /galaxy_open?id= — 雙擊檔案星 → 用系統預設程式開啟該檔
  /// GET /fps_probe — [小葵 2026-08-29 v85] rAF 純測試（無 WebGL、無 three.js）
  /// 同 webview 環境跑 5 秒空 rAF——若也鎖 80=面板/WebKit 層（非場景負載）
  Future<Response> _handleGetFpsProbe(Request req) async {
    const html = '''<!DOCTYPE html><html><head><meta charset="utf-8"><style>body{background:#000;color:#0f0;font:22px monospace;padding:30px}</style></head>
<body><div id="o">measuring 5s...</div><script>
const t0=performance.now();let n=0;
function loop(){n++;const d=performance.now()-t0;
  if(d<5000){requestAnimationFrame(loop);return;}
  const fps=n/(d/1000);
  document.getElementById('o').textContent='rAF FPS over 5s: '+fps.toFixed(1)+' (frames='+n+')';
  document.title='PROBE:'+fps.toFixed(1);
}
requestAnimationFrame(loop);
</script></body></html>''';
    return Response.ok(html, headers: {'Content-Type': 'text/html; charset=utf-8'});
  }

  /// GET /galaxy_ping — [小葵 2026-08-29 v54] 頁面心跳（監視器診斷用）
  Future<Response> _handleGetGalaxyPing(Request req) async {
    final q = req.url.queryParameters;
    final line = '[galaxy_ping] t=${DateTime.now().toIso8601String()} fp=${q['fp'] ?? '?'} rAF=${q['raf'] ?? '?'} fps=${q['fps'] ?? '?'} hx=${q['hx'] ?? '?'} mx=${q['mx'] ?? '?'}ms cs=${q['cs'] ?? '-'} hd=${q['hd'] ?? '-'} pan=${q['pan'] ?? '-'} pc=${q['pc'] ?? '-'} dn=${q['dn'] ?? '-'} la=${q['la'] ?? '-'} pr=${q['pr'] ?? '-'} err=${q['err'] ?? '-'}'; // [v191] hx=10s內掉幀數 mx=最長幀間隔 [v244] fps=10s 區間 rAF 幀率 [v247] cs=元兇 hd=幀間隔樣本 [v297] pr=遠端指令結果
    // ignore: avoid_print
    print(line);
    final f = File('/tmp/galaxy_ping.log');
    f.writeAsStringSync('$line\n', mode: FileMode.append);
    // [v297 遠端指令通道] 小葵診斷用：/tmp/galaxy_cmd.json 存指令 → 下輪心跳回給頁面執行
    try {
      final cmdFile = File('/tmp/galaxy_cmd.json');
      if (cmdFile.existsSync()) {
        final cmd = cmdFile.readAsStringSync();
        cmdFile.deleteSync();
        return Response.ok(cmd, headers: _jsonHeaders);
      }
    } catch (_) {}
    return Response.ok('{"ok":true}', headers: _jsonHeaders);
  }

/// GET /avatar_engine.js — [小葵 2026-09-24 出道令] 懸浮小葵 WebGL 引擎
  Future<Response> _handleGetAvatarEngine(Request req) async {
    final f = File(resolveDevPath('~/Developer/bridge_app/morning-tea/avatar_engine.js'));
    if (!await f.exists()) {
      return Response(404, body: 'avatar_engine.js not found');
    }
    return Response.ok(await f.readAsString(), headers: {
      'Content-Type': 'application/javascript',
      'Cache-Control': 'no-cache',
    });
  }

  /// GET /avatar_state/<name>.mp4 — [小葵 2026-09-24] 16 段狀態影片（去音軌版）
  Future<Response> _handleGetAvatarStateVideo(Request req) async {
    final name = req.params['name'] ?? '';
    // 白名單防路徑跳脫：只允許 [a-z_0-9].mp4
    if (!RegExp(r'^[a-z0-9_]+\.mp4$').hasMatch(name)) {
      return Response(400, body: 'bad name');
    }
    final f = File(
        resolveDevPath('~/Library/Containers/farm.semiwasabi.bridgeApp/Data/Documents/bridge_media/animations/$name'));
    if (!await f.exists()) {
      return Response(404, body: 'not found');
    }
    return Response.ok(await f.readAsBytes(), headers: {
      'Content-Type': 'video/mp4',
      'Cache-Control': 'no-cache',
    });
  }

  /// GET /three.module.js — [小葵 2026-08-29 v56] 本地 three.js（unpkg CDN 在 WKWebView 不穩）
  Future<Response> _handleGetThreeModule(Request req) async {
    File('/tmp/three_hits.log').writeAsStringSync(
        '[hit] t=${DateTime.now().toIso8601String()} ua=${req.headers['user-agent'] ?? '?'}\n',
        mode: FileMode.append);
    try {
      final f = File(resolveDevPath('~/Developer/bridge_app/assets/galaxy/vendor/three.module.js'));
      if (!f.existsSync()) return Response(404);
      return Response.ok(f.readAsStringSync(), headers: {
        'Content-Type': 'application/javascript',
        'Cache-Control': 'no-cache', // [v60] 教訓：曾把 401 快取一天=module 永遠死——vendor 一律 no-cache
      });
    } catch (e) {
      return Response(500);
    }
  }

  /// GET /three.core.js — [v63] three r167+ 的第二個檔案（module 內部 import）
  Future<Response> _handleGetThreeCore(Request req) async {
    try {
      final f = File(resolveDevPath('~/Developer/bridge_app/assets/galaxy/vendor/three.core.js'));
      if (!f.existsSync()) return Response(404);
      return Response.ok(f.readAsStringSync(), headers: {
        'Content-Type': 'application/javascript',
        'Cache-Control': 'no-cache', // [v60 教訓] 靜態 vendor 一律 no-cache
      });
    } catch (e) {
      return Response(500);
    }
  }

  /// GET /galaxy_version — [小葵 2026-08-29 v52] 抽出 galaxy.html 內嵌指紋（webview 快取自癒用）
  /// 頁面 runtime 也帶同一指紋；webview 若載到舊 DOM，兩者不符 → 頁面自動 reload
  // [v232] 星系參數——記憶體+磁碟持久化
  static Map<String, dynamic>? _galaxyParams;
  static final _galaxyParamsPath = resolveDevPath('~/Library/Application Support/farm.semiwasabi.bridgeApp/galaxy_params.json');
  Map<String, dynamic> _loadGalaxyParams() {
    if (_galaxyParams != null) return _galaxyParams!;
    try {
      final f = File(_galaxyParamsPath);
      if (f.existsSync()) _galaxyParams = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {}
    _galaxyParams ??= {};
    return _galaxyParams!;
  }

  Response _handleGetGalaxyParams(Request request) {
    // [v303 沙盒令] 支援 ?mode= 讀該模式的參數包（無 mode=全部）
    final m = request.url.queryParameters['mode'];
    final all = _loadGalaxyParams();
    if (m == null || m.isEmpty) return Response.ok(jsonEncode({'params': all, if (_uiMuteUntil != null && _uiMuteUntil!.isAfter(DateTime.now())) 'uiMuteMs': _uiMuteUntil!.difference(DateTime.now()).inMilliseconds}), headers: _jsonHeaders);
    final byMode = all['modes'] as Map<String, dynamic>?;
    final scoped = (byMode?[m] as Map<String, dynamic>?) ?? {};
    return Response.ok(jsonEncode({'params': scoped, if (_uiMuteUntil != null && _uiMuteUntil!.isAfter(DateTime.now())) 'uiMuteMs': _uiMuteUntil!.difference(DateTime.now()).inMilliseconds}), headers: _jsonHeaders);
  }

  /// GET /galaxy_note?type=uiMute&ms=1500 — [小葵 2026-09-25 開面板咚修]
  /// Flutter UI（設定面板開啟等）→ 頁面帶外通知。uiMute=設定 UI 靜音窗：
  /// 頁面端 __uiMuteUntil 前的 playTone 全吞（開面板瞬間 hover 座標落
  /// 在弦上會「咚」一聲）。頁面每秒輪詢 galaxy_params 時夾帶帶回。
  static DateTime? _uiMuteUntil;
  Response _handleGetGalaxyNote(Request request) {
    final type = request.url.queryParameters['type'] ?? '';
    if (type == 'uiMute') {
      final ms = int.tryParse(request.url.queryParameters['ms'] ?? '1500') ?? 1500;
      _uiMuteUntil = DateTime.now().add(Duration(milliseconds: ms));
    }
    return Response.ok(jsonEncode({'ok': true}), headers: _jsonHeaders);
  }

  Future<Response> _handlePostGalaxyParams(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final params = body['params'] as Map<String, dynamic>? ?? {};
      // [v261 白掉令] 合併而非取代——視窗版 pushAll 只送部分參數（GROUPS 內），
      // 取代會清掉 subColor.* 等未送參數=App 端材質重染白閃。
      // body['reset']=true 時才整份取代（原廠重置用）。
      if (body['reset'] == true) {
        _galaxyParams = params;
      } else {
        _galaxyParams = {...?_galaxyParams, ...params};
      }
      // [v303 沙盒令] body.mode 存在→寫入該模式的獨立參數包（不動其他模式）；
      // 無 mode→全域包（向後相容舊行為）
      final mode = body['mode'] as String?;
      if (mode != null && mode.isNotEmpty) {
        final scoped = _loadGalaxyParams();
        final modes = (scoped['modes'] as Map<String, dynamic>?) ?? {};
        modes[mode] = {...?modes[mode] as Map<String, dynamic>?, ...params};
        scoped['modes'] = modes;
        File(_galaxyParamsPath).writeAsStringSync(jsonEncode(scoped));
        return Response.ok(jsonEncode({'ok': true, 'saved': params.length, 'mode': mode}));
      }
      File(_galaxyParamsPath).writeAsStringSync(jsonEncode(params));
      return Response.ok(jsonEncode({'ok': true, 'saved': params.length}), headers: _jsonHeaders);
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}), headers: _jsonHeaders);
    }
  }

  /// [v308 Blue 五動作令] POST /galaxy_edit — 星系內編輯檔案/記憶
  Future<Response> _handlePostGalaxyEdit(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final op = body['op'] as String? ?? '';
      final kind = body['kind'] as String? ?? 'asset'; // asset|memory
      final id = body['id'] as String? ?? '';
      if (id.isEmpty) return Response(400, body: '{"error":"id required"}', headers: _jsonHeaders);
      final db = BrainDatabase.instance.db;

      switch (op) {
        case 'delete':
          if (kind == 'memory') {
            db.execute("UPDATE memories SET archived=1, updated_at=strftime('%s','now') WHERE id=?", [id]);
          } else {
            final row = db.select('SELECT file_path FROM asset_index WHERE id=?', [id]);
            if (row.isEmpty) return Response(404, body: '{"error":"not found"}', headers: _jsonHeaders);
            final fp = row.first['file_path'] as String;
            final f = File(fp);
            if (f.existsSync()) f.deleteSync(); // 檔案進垃圾桶前先確認存在
            db.execute('DELETE FROM memory_asset_links WHERE asset_id=?', [id]);
            db.execute('DELETE FROM asset_index WHERE id=?', [id]);
          }
          return Response.ok('{"ok":true,"op":"delete"}', headers: _jsonHeaders);

        case 'reveal': // 到所屬資料夾（Finder）
          if (kind == 'memory') return Response(400, body: '{"error":"memory has no folder"}', headers: _jsonHeaders);
          // [小葵 2026-09-10 Blue 回報沒反應] file_path 是相對路徑——
          // 必須跟 folder_root 組成絕對路徑（同 galaxy_open 的組法）
          final row = db.select(
              'SELECT file_path, folder_root FROM asset_index WHERE id=?', [id]);
          if (row.isEmpty) return Response(404, body: '{"error":"not found"}', headers: _jsonHeaders);
          final fp = '${row.first['folder_root']}/${row.first['file_path']}';
          final dir = File(fp).parent.path;
          if (!Directory(dir).existsSync()) return Response(404, body: '{"error":"folder gone"}', headers: _jsonHeaders);
          Process.runSync('open', [dir]);
          return Response.ok('{"ok":true,"op":"reveal","folder":"'+dir+'"}', headers: _jsonHeaders);

        case 'tags':
          final tags = body['tags'];
          if (tags is! List) return Response(400, body: '{"error":"tags must be list"}', headers: _jsonHeaders);
          final tjson = jsonEncode(tags);
          if (kind == 'memory') {
            db.execute("UPDATE memories SET tags=?, updated_at=strftime('%s','now') WHERE id=?", [tjson, id]);
          } else {
            db.execute('UPDATE asset_index SET tags=? WHERE id=?', [tjson, id]);
          }
          return Response.ok('{"ok":true,"op":"tags","tags":"'+tjson+'"}', headers: _jsonHeaders);

        case 'rename':
          final name = body['name'] as String? ?? '';
          if (name.trim().isEmpty) return Response(400, body: '{"error":"name required"}', headers: _jsonHeaders);
          if (kind == 'memory') {
            db.execute("UPDATE memories SET title=?, updated_at=strftime('%s','now') WHERE id=?", [name, id]);
          } else {
            db.execute('UPDATE asset_index SET display_title=? WHERE id=?', [name, id]);
          }
          return Response.ok('{"ok":true,"op":"rename","name":"'+name+'"}', headers: _jsonHeaders);

        case 'icon': // 圖示+尺寸+顏色（存 asset_index tags 相邻的自訂欄——用 brain_meta）
          final icon = body['icon'] as String? ?? '';
          final size = body['size'] as String? ?? 'mid';
          final color = body['color'] as String? ?? '';
          final key = 'galaxy_icon_'+id;
          db.execute('INSERT OR REPLACE INTO brain_meta (key,value) VALUES (?,?)',
              [key, jsonEncode({'icon': icon, 'size': size, 'color': color})]);
          return Response.ok('{"ok":true,"op":"icon"}', headers: _jsonHeaders);

        default:
          return Response(400, body: '{"error":"unknown op"}', headers: _jsonHeaders);
      }
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}), headers: _jsonHeaders);
    }
  }

  /// [v308] GET /galaxy_icons — 十個預設圖示
  Response _handleGetGalaxyIcons(Request req) {
    final db = BrainDatabase.instance.db;
    final icons = ['⭐','💎','🔥','🌊','🌿','⚡','🧠','🚀','🎯','🕯️'];
    // 讀回所有自訂圖示設定
    final rows = db.select("SELECT key,value FROM brain_meta WHERE key LIKE 'galaxy_icon_%'");
    final map = <String, dynamic>{};
    for (final r in rows) { map[(r['key'] as String).replaceFirst('galaxy_icon_', '')] = jsonDecode(r['value'] as String); }
    return Response.ok(jsonEncode({'icons': icons, 'custom': map}), headers: _jsonHeaders);
  }

  Future<Response> _handleGetGalaxyVersion(Request req) async {
    try {
      final f = File(resolveDevPath('~/Developer/bridge_app/assets/galaxy/galaxy.html'));
      if (!f.existsSync()) return Response.ok('{"fp":""}', headers: _jsonHeaders);
      final m = RegExp(r"FINGERPRINT='([^']+)'").firstMatch(f.readAsStringSync());
      return Response.ok('{"fp":"${m?.group(1) ?? ''}"}', headers: _jsonHeaders);
    } catch (e) {
      return Response.ok('{"error":"${e.toString()}"}', headers: _jsonHeaders);
    }
  }

  /// POST /galaxy_oplog — [小葵 2026-08-29 v32] 行車記錄器：接收 webview 操作 log
  Future<Response> _handlePostGalaxyOplog(Request req) async {
    try {
      final body = await req.readAsString();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final f = File('/tmp/galaxy_oplog_$stamp.json');
      await f.writeAsString(body);
      // 保留最新 20 份
      final dir = Directory('/tmp');
      final logs = dir.listSync()
          .whereType<File>()
          .where((e) => e.path.contains('galaxy_oplog_'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      while (logs.length > 20) {
        logs.first.deleteSync();
        logs.removeAt(0);
      }
      return Response.ok(jsonEncode({'ok': true, 'entries': f.lengthSync()}),
          headers: _jsonHeaders);
    } catch (e) {
      return Response.ok(jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  /// GET /galaxy_thumb?id=… — [小葵 2026-08-28 v28] 資料框縮圖預覽
  /// 讀原圖 → sips 即時縮圖（320px，/tmp 快取）→ 回傳 JPEG bytes
  Future<Response> _handleGetGalaxyThumb(Request req) async {
    try {
      final id = req.url.queryParameters['id'] ?? '';
      if (id.isEmpty) {
        return Response.ok(jsonEncode({'error': '缺少 id'}),
            headers: _jsonHeaders);
      }
      final db = BrainDatabase.instance.db;
      final row = db.select(
          'SELECT file_path, folder_root, file_ext FROM asset_index WHERE id = ?',
          [id]);
      if (row.isEmpty) {
        return Response.ok(jsonEncode({'error': '找不到資產'}),
            headers: _jsonHeaders);
      }
      final ext = (row.first['file_ext'] as String? ?? '').toLowerCase();
      const imgExts = ['.jpg', '.jpeg', '.png', '.heic', '.gif', '.webp'];
      if (!imgExts.contains(ext)) {
        return Response(404, body: 'not an image');
      }
      final fullPath =
          '${row.first['folder_root']}/${row.first['file_path']}';
      final f = File(fullPath);
      if (!f.existsSync()) {
        return Response(404, body: 'file missing');
      }
      // 快取：/tmp/galaxy_thumbs/<id>.jpg（mtime 不同才重縮）
      final dir = Directory('/tmp/galaxy_thumbs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final thumbPath = '/tmp/galaxy_thumbs/$id.jpg';
      final thumbFile = File(thumbPath);
      final srcMtime = f.lastModifiedSync();
      final needRebuild = !thumbFile.existsSync() ||
          thumbFile.lastModifiedSync().isBefore(srcMtime) ||
          thumbFile.lengthSync() == 0;
      if (needRebuild) {
        final r = await Process.run('sips', [
          '-Z', '320', // 最長邊 320px
          '-s', 'format', 'jpeg',
          '-s', 'formatOptions', '70',
          fullPath,
          '--out', thumbPath,
        ]);
        if (r.exitCode != 0 || !thumbFile.existsSync()) {
          return Response(404, body: 'sips failed');
        }
      }
      final bytes = await thumbFile.readAsBytes();
      return Response.ok(bytes, headers: {
        'Content-Type': 'image/jpeg',
        'Cache-Control': 'public, max-age=86400',
      });
    } catch (e) {
      return Response.ok(jsonEncode({'error': e.toString()}),
          headers: _jsonHeaders);
    }
  }

  Future<Response> _handleGetGalaxyOpen(Request req) async {
    try {
      final id = req.url.queryParameters['id'] ?? '';
      if (id.isEmpty) {
        return Response.ok(jsonEncode({'error': '缺少 id'}),
            headers: _jsonHeaders);
      }
      final db = BrainDatabase.instance.db;
      final row = db.select(
          'SELECT file_path, folder_root FROM asset_index WHERE id = ?', [id]);
      if (row.isEmpty) {
        return Response.ok(jsonEncode({'error': '找不到資產 $id'}),
            headers: _jsonHeaders);
      }
      final fullPath =
          '${row.first['folder_root']}/${row.first['file_path']}';
      final f = File(fullPath);
      if (!f.existsSync()) {
        return Response.ok(jsonEncode({'error': '檔案不存在: $fullPath'}),
            headers: _jsonHeaders);
      }
      // macOS：系統預設程式開啟（open 指令）
      final r = await Process.run('open', [fullPath]);
      if (r.exitCode != 0) {
        return Response.ok(
            jsonEncode({'error': '開啟失敗: ${r.stderr}'}),
            headers: _jsonHeaders);
      }
      debugPrint('[MCP] galaxy_open: $fullPath');
      return Response.ok(
          jsonEncode({'success': true, 'opened': fullPath}),
          headers: _jsonHeaders);
    } catch (e) {
      return Response.ok(jsonEncode({'error': '$e'}), headers: _jsonHeaders);
    }
  }

  /// GET /galaxy_data — 星系資料包（nodes + edges + files）
  Future<Response> _handleGetGalaxyData(Request req) async {
    try {
      // [TRIO M5a] ?swarmonly=1 → 只出戰爭層（輕量輪詢——不重查 6.6k 星 DB）
      if (req.url.queryParameters['swarmonly'] == '1') {
        return Response.ok(jsonEncode({'swarm': GalaxyDataService.swarmNow()}),
            headers: _jsonHeaders);
      }
      final data = await GalaxyDataService.getGalaxyData();
      return Response.ok(jsonEncode(data), headers: _jsonHeaders);
    } catch (e, st) {
      debugPrint('[MCP] galaxy_data 失敗: $e\n$st');
      return Response.ok(jsonEncode({'error': '$e'}),
          headers: _jsonHeaders);
    }
  }
}
