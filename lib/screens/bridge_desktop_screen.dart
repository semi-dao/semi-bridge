// ignore_for_file: dead_code, dead_null_aware_expression
// Bridge Desktop 主畫面 — Sprint 14.5 設計系統版
// 佈局：TopBar(64) + Sidebar(240) + Canvas(flex) + ContextPanel(320) + StatusBar(32)
// 設計：xAI 氛圍 × Raycast 色彩 × Stripe 粒子 × Figma 動態 × Miro 無限畫布

import '../app.dart'; // [D002 2026-08-10] appNavigatorKey
import '../core/dev_paths.dart'; // [開源整備] 開發機路徑泛化
import 'package:bridge_app/models/brain_container/memory_source.dart';
import '../services/brain_revival_service.dart';
import '../services/window_autofit_service.dart'; // [Blue 令 2026-10-05] 視窗自動適裝
import '../services/local_model_runtime_service.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderBox, RenderFlex, FlexParentData;

import '../widgets/breathing_image.dart'; // [小葵 2026-09-13] 呼吸感預覽
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart'; // [開光 v0.4.x] GestureBinding 真點
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/companion_rig.dart';
import '../widgets/companion_rig_animator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/chat_controller.dart';
import '../models/brain_container/brain_room.dart';
import '../models/entity_graph/open_canvas_node.dart' show ActualSizeCache; // [教練 Agent 2026-08-22] 渲染層視網膜
import '../models/canvas/canvas_metadata.dart';
import '../widgets/adaptive_scaffold.dart';
import '../models/conversation.dart';
import '../services/api_service.dart';
import '../services/capability/service_registry.dart'; // [教練 Agent 2026-08-01] 能力中心
import '../services/capability/capability_models.dart';
import '../services/brain_container/brain_container_service.dart';
import '../services/brain_container/brain_database.dart';
import '../services/brain_container/embedding/embedding_service.dart';
import '../services/hermes_lossless_importer.dart';
import '../services/canvas_store.dart';
import '../services/tasks/task_dispatcher.dart'; // [隊友訊息流 C5]
import '../services/search/receipts_search_service.dart'; // [收據搜尋 RC2]
import '../widgets/search/receipts_search_overlay.dart'; // [收據搜尋 RC2.5]
import '../services/semicanvas/canvas_gravekeeper.dart'; // [教練 Agent 2026-08-26] 殭屍清掃
import '../services/companion_store.dart';
import '../widgets/collab/agent_status_dot.dart'; // [TRIO M1] 夥伴頭像狀態點
import '../services/system/tray_service.dart' show TrayService; // [Blue 拍板] 訓練頁導航 callback
import '../screens/companion_create_screen.dart'; // [教練 Agent 2026-08-04 Phase E+] 夥伴館子頁面內嵌
import '../screens/training_screen.dart'; // [Blue 拍板 2026-09-12] 訓練AI夥伴
import '../screens/companion_soul_screen.dart';
import '../screens/companion_appearance_screen.dart';
import '../screens/companion_settings/voice_settings_screen.dart';
import '../screens/companion_control_center_screen.dart';
import '../services/conversation_store.dart';
import '../services/canvas_state_store_sqlite.dart';
import '../services/digital_asset_registry_store.dart';
import '../services/entity_graph/entity_graph_service.dart';
import '../services/semicanvas/app_schedule_engine.dart'; // [W1] App 層排程引擎
import '../widgets/project/schedule_queue_section.dart'; // [W3] 排隊分區
import '../widgets/project/project_door_grid.dart'; // [W3.5] 專案卡下區
import '../widgets/project/task_list_sidebar.dart'; // [W3.5] 左欄任務清單
import '../widgets/project/schedule_task_detail_drawer.dart'; // [W4] 任務詳情抽屜
import '../services/memory_store.dart';
import '../models/project_door.dart';
import '../services/project_door_store.dart';
import '../services/project_trash_store.dart';
import '../services/desktop_bridge_local_gateway.dart';
import '../services/desktop_bridge_pairing_contract.dart';
import '../services/desktop_companion_shell_config.dart';
import '../services/desktop_companion_shell_config_store.dart';
import '../services/desktop_shell_environment_report.dart';
import '../services/desktop_shell_environment_report_store.dart';
import '../services/lan_ip_detector.dart';
import '../services/storage_service.dart';
import '../services/slots/slot_registry.dart'; // [無限插槽 C2 2026-10-06 移植] 首頁插槽卡
import '../services/agent_loop/mcp_canvas_tools.dart'; // [Phase 0 Track A 2026-07-17]
import '../services/agent_loop/agent_event_bus.dart'; // [Phase 1 2026-07-17] NativeAgentLoop 接線
import '../services/macos_desktop_shell_channel.dart'; // [教練 Agent 2026-08-11] NSPanel 浮動夥伴
import '../services/agent_activity_store.dart'; // [教練 Agent 2026-08-11] 推送即時狀態到 NSPanel
import '../services/companion_runtime_store.dart';
import '../services/desktop_companion_shell_commands.dart';
import '../models/companion_runtime.dart';
import '../models/agent_activity.dart';
import '../screens/compass_screen.dart'; // [羅盤 2026-09-06]
import 'desktop/settings/hermes_migration_screen.dart'; // [WS-3 2026-09-13] 大搬家
import '../widgets/bridge_cards/companion_status_helper.dart';
import '../services/agent_loop/agent_tool_registry.dart';
import '../services/agent_loop/agent_loop.dart';
import '../services/agent_loop/agent_safety.dart'; // [D002] 安全確認
import '../services/agent_loop/production_agent_loop_llm_client.dart';
import '../services/agent_loop/agent_loop_tools/mac_screen_capture_executor.dart';
import '../services/agent_loop/agent_loop_tools/flutter_self_capture_executor.dart';
import '../services/agent_loop/agent_loop_tools/ui_automation_tool.dart';
import '../services/bridge_action_executor.dart';
import '../services/native_agent_loop.dart';
import '../services/agent_loop/agent_profile_store.dart'; // [教練 Agent 2026-07-18] Provider profile store 初始化
import '../services/agent_loop/custom_routing_policy.dart'; // [教練 Agent 2026-07-30] 預設選型原則
import '../services/persona_manager.dart';
import '../theme/bridge_design_system.dart';
import '../theme/bridge_motion.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../widgets/bridge_desktop_widgets.dart';
import '../models/companion.dart';
import '../widgets/brain_model_download_card.dart';
import '../widgets/local_llm_runtime_card.dart';
import '../widgets/model_lab_card.dart';
import '../widgets/system_activity_card.dart';
import '../widgets/brain/galaxy_webview.dart'; // [小葵 2026-08-27] 3D 星系模式
import '../widgets/galaxy_screensaver_overlay.dart'; // [小葵 2026-09-01] 星系保護模式
import '../widgets/canvas/asset_library_panel.dart';
import '../widgets/canvas/canvas_toolbar.dart';

import '../widgets/canvas/v2/canvas_v2_workspace.dart';
import '../widgets/canvas/v2/canvas_state.dart' show CanvasTool2;
import '../widgets/embedding_progress_bar.dart'; // [教練 Agent 2026-07-28] 全域嵌入進度條
import '../widgets/api_usage_dashboard.dart'; // [教練 Agent 2026-07-29] API 額度儀表板
import '../models/entity_graph/entity.dart'; // [Phase 0 Track A 2026-07-17] WorkflowNodeType
import '../services/bridge_mcp_server.dart';
import '../services/memory_guard_service.dart'; // [教練 Agent 2026-07-21] 記憶體監控
import '../widgets/memory_pressure_dialog.dart'; // [教練 Agent 2026-07-22] #4 L2 記憶體壓力對話框
import '../services/provider_router.dart'; // [教練 Agent 2026-07-22] 動態 Agent 路由
import '../services/provider_registry.dart'; // [教練 Agent 2026-07-30] 動態 Provider 探測
import '../services/brain_container/embedding/embedding_service.dart'; // [教練 Agent 2026-07-22] embedding for knowledge indexing
import '../services/brain_container/brain_container_service.dart'; // [教練 Agent 2026-07-22] wait for brain init
import '../widgets/canvas/v2/canvas_controller.dart';
import '../widgets/canvas/v2/canvas_mcp_registry.dart';
import '../screens/vault_screen.dart'; // [教練 Agent 2026-07-22] Phase 2 ④ 資料庫頁面
import '../services/vault/vault_templates.dart'; // [教練 Agent 2026-07-23] 範本下拉選單

import 'desktop/desktop_file_page.dart';
import 'desktop/desktop_chat_panel.dart'; // [教練 Agent S22] 桌面原生聊天面板
import 'desktop/settings/theme_settings_page.dart'; // [教練 Agent 2026-08-04] Phase E+：主題包設定
import '../state/theme_provider.dart'; // [教練 Agent 2026-08-04] Phase E+：主題包 singleton
import '../services/agent_loop/workflow_inspector.dart';
import '../widgets/settings/db_location_card.dart';
import '../widgets/settings/watchdog_toggle_card.dart';
import '../widgets/settings/data_path_overview_card.dart'; // [教練 Agent 2026-08-10] DB 路徑設定（從 settings_screen 抽出）
import '../widgets/settings/brain_api_config_card.dart'; // [教練 Agent 2026-08-11] 主腦 API 設定（搬到金鑰匙系統）
import 'album_screen.dart'; // [時間感 L4 2026-09-13] 相簿視圖——按日子翻頁
import '../widgets/trust/agent_glyph.dart'; // [小葵 2026-09-15] 參與者指紋章（刀 2 D2.5 接線桌面側欄）
// [教練 Agent 2026-08-11] FloatingCompanion 已改為 NSPanel 桌面懸浮窗

class BridgeDesktopScreen extends StatefulWidget {
  const BridgeDesktopScreen({super.key});

  /// [教練 Agent 2026-07-28] Phase 5: 跨頁面跳轉 — 全域 ValueNotifier
  /// 其他頁面呼叫 BridgeDesktopScreen.navigateTo('brain' / 'vault') 即可切換 tab
  static final ValueNotifier<String?> navigateToTab = ValueNotifier<String?>(null);

  /// [教練 Agent 2026-08-02] Quick Assistant — 全域 ChatController 共享
  /// bridge_desktop_screen 建立後上報，app.dart 層級可存取
  static final ValueNotifier<ChatController?> activeChatController =
      ValueNotifier<ChatController?>(null);

  /// 跳轉到指定 tab（'chat'=對話, 'canvas'=畫布, 'project'=專案, 'brain'=大腦, 'vault'=向量資料庫, 'system'=系統）
  static void navigateTo(String tab) {
    navigateToTab.value = tab;
  }

  /// [羅盤 2026-09-06] 羅盤快捷鍵 callback（Cmd+Shift+C）
  static VoidCallback? navigateToCompass;

  /// [收據搜尋 RC2.5 2026-09-08] 全局搜尋快捷鍵 callback（Cmd+Shift+F）
  static VoidCallback? navigateToReceiptsSearch;

  @override
  State<BridgeDesktopScreen> createState() => _BridgeDesktopScreenState();
}

/// [教練 Agent 2026-08-16 使用者 提案] 折疊窄軌的方向
enum _RailSide { left, right }

class _BridgeDesktopScreenState extends State<BridgeDesktopScreen> {
  /// [v183] 星系螢幕保護。
  /// [v272 雙螢保案偵結] 系統裡有兩套螢保並存搶觸發：
  ///   Swift 版（v183 WKWebView 全螢幕）——in-process=注定被 macOS 節流
  ///   Dart overlay 版（v263+ Chrome 視窗）——絲滑
  /// Blue 三次查證「自動觸發還是 App 版」=Swift 版先搶。停用 Swift 版，
  /// Chrome 版獨佔。Swift 代碼保留（configure(enabled:false) 即休眠）。
  Future<void> _enableGalaxySaver() async {
    try {
      const channel = MethodChannel('bridge.desktop_shell.macos.v1');
      await channel.invokeMethod('setGalaxySaver',
          {'enabled': false, 'idleMinutes': 5, 'url': null});
    } catch (e) {
      debugPrint('[v272] setGalaxySaver 停用失敗: $e');
    }
  }

  // [教練 Agent 2026-08-20] MCP 大腦搜尋放大對焦用 GlobalKey

  // --- Gateway ---
  DesktopBridgeLocalGatewayHandle? _gatewayHandle;
  bool _gatewayRunning = false;
  int? _gatewayPort;
  String? _gatewayError;

  // --- Pairing ---
  DesktopBridgePairingContract? _pairingContract;
  String _pairingCode = '';
  String? _lanIp;
  List<String> _allLanIps = [];

  // --- Connection ---
  bool _mobileConnected = false;
  int _connectCount = 0;

  // --- Message log ---
  final List<_GatewayLogEntry> _log = [];
  static const int _maxLogEntries = 100;

  // --- Timer for gateway health ---
  Timer? _healthTimer;
  // [小葵 2026-09-24 出道令] 待機輪播定時器：idle 狀態每 ~6s 重抽一支片
  Timer? _idleRotateTimer;

  // [小葵 2026-09-24 Blue 三修之一] 非待機狀態看門狗——工作狀態（writing/大笑/…）
  // 停留在非 idle 超過時限後自動回待機，形成循環。上游（chat_controller 的
  // 回覆關鍵字掃描）會把 stage 留在 composing 且無人收尾，這裡兜底。
  // 分層時限：慶祝/大笑類情感狀態 8s；編寫/閱讀等工作狀態 15s（約播 1-2 次）。
  Timer? _stateWatchdogTimer;

  // --- Canvas nav ---
  // 5 tab（0=對話 1=畫布 2=專案 3=大腦 4=系統）
  int _activeCanvasIndex = 0;

  // 首頁模式：啟動時/按 Logo 時顯示首頁，不顯示 sidebar + canvas
  bool _isHomepage = true;

  // 夥伴館子頁面（從首頁進入）
  bool _isCompanionHall = false;

  // [Blue 拍板 2026-09-12] 訓練AI夥伴——唯一入口在首頁
  bool _isTrainingPage = false;

  // [教練 Agent 2026-08-04 Phase E+] 夥伴館內子頁面狀態（不切出去，全在 BridgeDesktop 內）
  // null = 在夥伴館列表
  String? _activeCompanionId; // 當前選中的角色 ID
  String? _activeCompanionSubPage; // null = 列表; 'control', 'soul', 'appearance', 'voice', 'create', 'achievements', 'semi-dao'
  final List<String> _companionPageStack = []; // 返回堆疊

  // --- 系統頁面 ---
  // 當 _activeCanvasIndex == 5 時，_activeSystemPage 決定顯示哪個系統頁面
  // null = 顯示系統選單，'files'/'settings'/'model'/'pairing' = 對應頁面
  String? _activeSystemPage;

  // --- 右側資訊欄收合 ---
  bool _contextPanelVisible = false; // 預設隱藏

  // --- 畫布 tab 可拖移寬度 ---
  double _canvasSidebarWidth = 320; // 工具列+資產庫
  double _canvasChatWidth = 340; // 對話框

  // [W4.7 Blue 令 2026-10-09] 對話頁/專案頁 sidebar 可拖寬度
  double _chatSidebarWidth = 260; // 對話頁 sidebar（預設=BridgeDS.sidebarWidth 量級）
  double _projectSidebarWidth = 240; // 專案頁任務清單欄

  // [教練 Agent 2026-08-16 使用者 提案] 畫布頁左右區塊折疊
  bool _canvasSidebarCollapsed = false; // 左側資產庫收合
  bool _canvasChatCollapsed = false; // 右側對話框收合
  // SemiCanvas #4: workspace GlobalKey — 供資產庫載入工作流
  final GlobalKey<CanvasV2WorkspaceState> _workspaceKey = GlobalKey();
  int? _canvasGhostCount; // [v204] 幽靈重建計數（診斷用）

  // App 自拍 — 包覆整個 Scaffold body 的 RepaintBoundary key
  // [2026-07-18 使用者 提議] App 自己截圖，不靠系統截圖
  final GlobalKey _selfCaptureKey = GlobalKey();

  // 工具列外部渲染狀態
  CanvasTool _canvasTool = CanvasTool.select;
  bool _canvasDoodleVisible = true;

  // 追蹤當前畫布 ID（跨 tab 切換時保留，供 workspace 恢復用）
  String? _activeCanvasId;

  // --- 對話列表 ---
  List<Conversation> _conversations = [];
  String? _currentConversationId; // P4-r2: 追蹤當前選中的對話

  // D11: 畫布列表
  List<CanvasMetadata> _canvases = [];

  // D11-6: 畫布對話的 ChatController（由 CanvasChatPanel 回報）
  ChatController? _canvasChatController;
  // [教練 Agent 2026-07-19] 桌面主聊天面板的 ChatController——由 DesktopChatPanel 回報
  // 用途：MCP /send_user_message 端點透過它觸發 sendMessage，模擬使用者在聊天框打字
  ChatController? _desktopChatController;
  // [教練 Agent 2026-08-08] Persistent ChatController——不依賴 DesktopChatPanel widget lifecycle
  // 當使用者在其他 tab（畫布、設定等）時，DesktopChatPanel 不會被 build，
  // 但 MCP 仍然需要能觸發 Agent Loop。
  late final ChatController _persistentChatController;

  // [Phase 0 Track A 2026-07-17] MCP 工具執行器
  McpCanvasExecutor? _mcpCanvasExecutor;

  // [Phase 1 2026-07-17] NativeAgentLoop — 自主迴圈接線
  AgentEventBus? _agentEventBus;
  PersonaManager? _personaManager;
  NativeAgentLoop? _nativeAgentLoop;

  // [教練 Agent 2026-07-28] 切換 tab 時控制 idle 心跳
  // [教練 Agent 2026-08-18 使用者 定調] 大腦/vault 頁「心跳維持」——逛大腦時看見 Agent
  // 持續寫入才是共視：使用者看到的不是死的資料庫，是活的大腦在做事。
  void _onTabChanged(int newIndex) {
    final oldIndex = _activeCanvasIndex;
    if (oldIndex == newIndex) return;
    _activeCanvasIndex = newIndex;
    // [Blue 抓包 2026-09-13 幽靈疊層] 切任何 tab 統一離開訓練頁——
    // 之前只重設 homepage/companionHall，_isTrainingPage 殘留 true，
    // 訓練頁 KeyedSubtree 疊在每個頁面上。
    _isTrainingPage = false;
    // [2026-08-27 共視修復] 切到對話 tab 時刷新側欄列表——
    // 不依賴事件鏈（雙 controller 競態下事件可能漏），
    // 進對話頁看到的永遠是 store 最新狀態。
    if (newIndex == 0) {
      _loadConversations();
    }
    // 心跳全 tab 維持——不再因切到資料頁而暫停
  }

  // --- 大腦容器 ---
  Map<BrainRoom, int> _roomStats = {};
  // [教練 Agent 2026-07-25] 大腦圖譜七種模式 — Reality Transurfing 儀表板
  // [小葵 2026-08-28 Blue 拍板] 2D 圖譜模式收起（代碼保留不刪），3D 星系自成一套系統
  // （五呈現模式在 galaxy.html 內切換：星系全景/時間之河/粒子流動/衛星軌道/影響力脈動）
  // [小葵 2026-09-01 Blue 拍板 A 路線] 星系保護模式——App 開著就接管待機畫面
  final GalaxyScreensaverController _galaxySaver =
      GalaxyScreensaverController(
          idleTimeout: const Duration(minutes: 5));
  bool _brainInitialized = false;
  bool _brainModelAvailable = false;
  bool _brainInitFailed = false;

  // --- Agent Loop (S21) + Skills (S20) ---
  bool _agentLoopEnabled = false;
  bool _screenCaptureEnabled = false;

  /// [隊友訊息流 C5 2026-09-08] 任務狀態變化 → 刷新 sidebar（〔任務〕標記）
  /// ＋任務完成時重載畫布列表（新工作畫布入列）
  void _onTaskChanged() {
    if (!mounted) return;
    setState(() {});
    // 新工作畫布要進列表（dispatch 建的）——背景補載不阻塞 UI
    _loadCanvases();
  }

  /// [無限插槽 C2 2026-10-06 移植] 插槽註冊表變動 → 首頁統計刷新
  void _onSlotRegistryChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // [小葵 2026-10-01 F5] 大腦看門狗升級 App 級——不依賴逛到 model 頁
    // （原掛 LocalLlmRuntimeCard.initState：沒逛頁=沒看門狗=殺了不復活，實驗抓包）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BrainRevivalService.instance
          .startWatch(LocalModelRuntimeService());
    });
    // [隊友訊息流 C5 2026-09-08] 監聽任務狀態——派工/完成時刷新 sidebar
    // （〔任務〕畫布標記+活躍狀態）與恢復持久化任務
    TaskDispatcher.instance.addListener(_onTaskChanged);
    TaskDispatcher.instance.restoreFromStore();
    // [無限插槽 C2 2026-10-06 移植] 首頁插槽卡即時統計——註冊表變動即刷新
    SlotRegistry.instance.addListener(_onSlotRegistryChanged);
    SlotRegistry.instance.ensureLoaded();
    // [小葵 2026-09-01] 星系保護——閒置 3 分鐘觸發計時啟動
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _galaxySaver.reportActivity();
    });
    // [小葵 2026-09-24 Blue 大搬家·完整匯入] 啟動時跑一次 lossless importer
    // 把 hermes 對話歷史（38,430 則 → ~1,300 個有意義 session）寫進
    // agent_memories（含 768 維 embedding）——memoryFlash 才能查到「你們的對話」。
    // idempotent：marker 存在就跳過。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runLosslessImport());
    });
    // [教練 Agent 2026-08-08] Persistent ChatController——MCP 不依賴 tab 狀態
    _persistentChatController = ChatController();
    // 讓 persistent controller 的 Agent Loop 回應可以被 MCP get_latest_messages 讀到
    _persistentChatController.onAgentLoopProgress = (
      turnIndex, maxTurns, toolName, toolStatus, llmSnippet
    ) {
      // 當 LLM 有輸出時，寫到 MCP registry 讓外部可以讀取
      if (llmSnippet != null && llmSnippet.isNotEmpty) {
        CanvasMcpRegistry.instance.setLastAgentReply(llmSnippet);
      }
    };
    // [教練 Agent P0.5b 2026-08-08] persistent controller 也要訂閱圖片進度
    _persistentChatController.ensureProgressSubscription();
    // [2026-08-26 身份污染追根] persistent controller 同樣要載入 active companion——
    // MCP 注入訊息走的也是這條 controller，人格注入同樣依賴 _activeCompanion。
    _persistentChatController.loadActiveCompanion();
    // [小葵 2026-09-01 v183 星系螢保令] 閒置 5 分鐘 → 全螢幕即時星系
    // （?saver=1 純淨模式+30 秒重抓 galaxy_data——大腦長新東西螢幕就長新星）
    _enableGalaxySaver();
    // [D002 2026-08-10] 安全確認——使用全域 Overlay，不依賴 widget context
    _persistentChatController.onToolConfirmation =
        ({required toolName, required args}) async {
      final needsConfirm =
          AgentSafetyConstraints.needsToolConfirmation(toolName, args);
      if (!needsConfirm) return true;
      return showD002ConfirmationDialog(toolName: toolName, args: args);
    };
    // [教練 Agent 2026-07-25] 移除 _onApiInputChanged listener（回歸 7/12 簡潔邏輯）
    _initializeDesktop();
    _loadConversations();
    _loadCanvases();
    _loadBrainStats();
    _loadAgentLoopFlag();
    _autoRefreshAllModels();
    // 啟動畫布 MCP Server — App 啟動即刻共視
    _registerMcpRegistry();
    BridgeMcpServer.instance.start();
    // [W1 2026-10-08 小葵·第二刀 UX] 排程引擎升級 App 層級——
    // 掃全庫（不綁「人現在看哪張畫布」），前景畫布由 workspace 註冊路由。
    AppScheduleEngine.instance.start();
    // [教練 Agent 2026-07-21] 啟動記憶體監控——保護系統不崩潰
    MemoryGuardService.instance.start();
    // [教練 Agent 2026-08-26 使用者 三刀之一] 殭屍節點清掃——
    // 比對 CanvasStore 活畫布，清掉孤兒節點（冪等，背景跑不擋啟動）。
    // 2026-08-26 事件：24 死畫布累積 182 殭屍 → 4 imageGen 被洩漏執行燒 28 張。
    unawaited(CanvasGravekeeper.instance.sweep(EntityGraphService.withSqliteCanvasStore(
      memoryStore: MemoryStore(),
      doorStore: ProjectDoorStore(),
      assetStore: DigitalAssetRegistryStore(),
    )));
    // [教練 Agent 2026-07-22] 初始化動態 Agent 路由——偵測可用雲端 provider
    ProviderRouter.instance.init();
    // [教練 Agent 2026-07-30] 動態探測可用 provider + 模型——啟動時掃描金鑰 + 拉取模型列表
    ProviderRegistry.instance.discoverAll();
    // [教練 Agent 2026-07-22] #3 按需知識檢索——索引知識庫到向量
    _indexKnowledgeBase();
    // [教練 Agent 2026-07-22] #4 L2: 監聯紅燈事件 → 彈出記憶體壓力對話框
    MemoryGuardService.instance.pressureDialogRequests.listen((_) {
      if (!mounted) return;
      MemoryPressureDialog.show(context, MemoryGuardService.instance);
    });
    // [教練 Agent 2026-07-28] Phase 5: 跨頁面跳轉監聽
    BridgeDesktopScreen.navigateToTab.addListener(_onNavigateToTab);

    // [羅盤 2026-09-06] 註冊快捷鍵 callback
    BridgeDesktopScreen.navigateToCompass = _openCompass;
    // [Blue 拍板 2026-09-12] 訓練頁導航——掛給托盤（service 不反向依賴 screen）
    TrayService.onOpenTrainingPage = _openTrainingPage;
    // [收據搜尋 RC2.5 2026-09-08] 註冊全局搜尋 callback（Cmd+Shift+F）
    BridgeDesktopScreen.navigateToReceiptsSearch = _openReceiptsSearch;

    // [教練 Agent 2026-08-11] NSPanel 浮動夥伴實驗——啟動面板 + 監聽狀態推送
    _initFloatingCompanionPanel();
  }

  /// [收據搜尋 RC2.5] 開啟全局搜尋 overlay
  void _openReceiptsSearch() {
    ReceiptsSearchManager.open(context, onAction: _executeHop);
  }

  /// [小葵 2026-09-24 Blue 大搬家·完整匯入] 把 hermes 對話歷史讀進
  /// agent_memories（含 768 維向量），idempotent。
  /// 約 1,300 個有意義對話 session，預估 7-8 分鐘（embedding + DB 寫入）。
  /// 不阻塞 UI——背景跑。
  Future<void> _runLosslessImport() async {
    try {
      // 等 EmbeddingService 就緒（App 啟動鏈會 init，這裡保險等一下）
      // 用 isModelAvailable 當 proxy——model 載好就代表可用。
      if (!EmbeddingService.instance.isModelAvailable) {
        // 給 3 秒時間，超過就跳過這次（下次啟動再跑）
        await EmbeddingService.instance.initialize().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
      }
      if (!EmbeddingService.instance.isModelAvailable) {
        debugPrint('[LosslessImport] EmbeddingService 未就緒，跳過');
        return;
      }
      final companionId = CompanionStore().activeCompanionId ?? 'shared';
      final importer = HermesLosslessImporter(
        database: BrainDatabase.instance,
        embedder: EmbeddingService.instance,
        companionId: companionId,
      );
      final report = await importer.run();
      debugPrint('[LosslessImport] 結果：$report');
    } catch (e, st) {
      debugPrint('[LosslessImport] 失敗：$e\n$st');
    }
  }

  /// [收據搜尋 S3 2026-09-08] 執行四動作分派
  void _executeHop(ReceiptHop hop, ReceiptAction action) {
    switch (action) {
      case ReceiptAction.galaxy:
        // 大腦圖譜域 → 開星系並聚焦該星（?focus= → 飛近+圓心自轉+預覽卡）
        if (hop.domain == ReceiptDomain.conversation) {
          // 對話域誤用星系動作 → 退回對話開啟
          _switchConversationById(hop.targetId);
        } else {
          _openBrainGalaxyWindow(focusAssetId: hop.targetId);
        }
      case ReceiptAction.vault:
        // 向量資料庫開啟——切 tab 3 並帶查詢字
        setState(() {
          _isHomepage = false;
          _isCompanionHall = false;
          _activeCanvasIndex = 3;
        });
        VaultScreen.externalSearchQuery.value =
            ReceiptsSearchManager.lastQuery;
      case ReceiptAction.canvas:
        // 匯入畫布——跳畫布 tab + 選畫布對話框（選既有或開新）
        _importAssetToCanvas(hop);
      case ReceiptAction.chat:
        if (hop.domain == ReceiptDomain.conversation) {
          // 對話域=開啟該對話
          setState(() {
            _isHomepage = false;
            _isCompanionHall = false;
            _activeCanvasIndex = 0;
          });
          _switchConversationById(hop.targetId);
        } else {
          // 記憶/資產域=匯入對話——跳對話 tab + 選對話對話框
          _importAssetToChat(hop);
        }
    }
  }

  /// [S3] 匯入畫布：跳畫布頁 → 詢問要匯入哪個畫布（或開新畫布）
  Future<void> _importAssetToCanvas(ReceiptHop hop) async {
    setState(() {
      _isHomepage = false;
      _isCompanionHall = false;
      _activeCanvasIndex = 1;
    });
    final canvases = await CanvasStore.getAll();
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('匯入到哪個畫布？'),
        children: [
          for (final c in canvases.take(12))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, c.id),
              child: Text(c.title.isNotEmpty ? c.title : '（未命名畫布）'),
            ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__new__'),
            child: const Text('➕ 開新畫布匯入'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final canvasId = choice == '__new__' ? null : choice;
    // [S3] 匯入=放置資產節點到畫布（透過 registry ambient——工作流 executor 路徑）
    await CanvasMcpRegistry.instance.importAssetToCanvas(
      assetId: hop.targetId,
      canvasId: canvasId,
      onCanvasCreated: (newId) => _switchCanvas(newId),
    );
    if (canvasId != null) _switchCanvas(canvasId);
  }

  /// [S3] 匯入對話：跳對話頁 → 詢問要匯入哪個對話（或開新對話）
  Future<void> _importAssetToChat(ReceiptHop hop) async {
    setState(() {
      _isHomepage = false;
      _isCompanionHall = false;
      _activeCanvasIndex = 0;
    });
    final convs = await ConversationStore.getAll();
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('匯入到哪個對話？'),
        children: [
          for (final c in convs.take(12))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, c.id),
              child: Text(c.title.isNotEmpty ? c.title : '（未命名對話）'),
            ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, '__new__'),
            child: const Text('➕ 開新對話匯入'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == '__new__') {
      // 開新對話：save 一個新 Conversation 再 setCurrentId
      final now = DateTime.now();
      final conv = Conversation(
        id: 'conv_${now.microsecondsSinceEpoch}',
        title: '匯入搜尋結果',
        createdAt: now,
        updatedAt: now,
        messages: const [],
      );
      await ConversationStore.save(conv);
      await ConversationStore.setCurrentId(conv.id);
    } else {
      await ConversationStore.setCurrentId(choice);
    }
    final curId = await ConversationStore.getCurrentId();
    if (mounted) setState(() => _currentConversationId = curId);
    // 注入資產到對話（走既有 chat 訊息附件路徑——以 receipt 卡形式）
    // TODO[RC4]: 真正的附件注入需要 ChatController.attachAsset——本刀先跳 tab+提示
  }

  /// [收據搜尋 RC2] 依對話 ID 切換（搜尋結果跳對話）
  Future<void> _switchConversationById(String conversationId) async {
    final conv = await ConversationStore.getById(conversationId);
    if (conv == null || !mounted) return;
    await ConversationStore.setCurrentId(conv.id);
    setState(() => _currentConversationId = conv.id);
    // 主對話頁掛著 persistent controller 的話由它接手；
    // 沒掛（使用者不在對話 tab）→ 導航過去後 ChatScreen 自己會讀 currentId
  }

  /// [羅盤 2026-09-06] 切到羅盤系統
  void _openCompass() {
    setState(() {
      _isHomepage = false;
      _isCompanionHall = false;
      _activeCanvasIndex = 4; // 系統 tab
      _activeSystemPage = 'compass';
    });
  }

  /// [時間感 L4 2026-09-13] 相簿視圖——家的記憶按日子翻頁（家庭提案 L4）
  void _openAlbum() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: BridgeDSColors.of(context).surface,
        insetPadding: const EdgeInsets.all(48),
        child: const ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          child: AlbumScreen(),
        ),
      ),
    );
  }

  /// [Blue 拍板 2026-09-12] 切到訓練AI夥伴頁（托盤入口收斂）
  void _openTrainingPage() {
    setState(() {
      _isHomepage = false;
      _isCompanionHall = false;
      _isTrainingPage = true;
    });
  }

  /// [教練 Agent 2026-08-11] 啟動 NSPanel 浮動夥伴 + 接上即時狀態
  void _initFloatingCompanionPanel() {
    const shell = MacosDesktopShellChannel();
    // 延遲 2 秒讓 App 完全啟動後再開面板
    Future.delayed(const Duration(seconds: 2), () async {
      // [小葵 2026-09-12] rig 素材複製到 App Support/bridge_rig/<name>/
      // （NSPanel 原生端讀不到 Flutter assets，用檔案系統當橋）
      await _exportRigAssets();

      // 推送初始狀態（含夥伴圖片路徑）
      _pushCompanionToPanel(shell);

      // 設為 alwaysOnTop + 透明 + 顯示
      await shell.apply(const DesktopShellCommandQueue([
        DesktopShellCommand(
          id: 'window.always-on-top',
          label: 'always on top',
          detail: 'float above all windows',
          requiresNative: true,
          payload: {'alwaysOnTop': true},
        ),
        DesktopShellCommand(
          id: 'window.shape',
          label: 'transparent frameless',
          detail: 'transparent + frameless panel',
          requiresNative: true,
          payload: {
            'transparent': true,
            'frameless': true,
            'width': 320.0,
            'height': 400.0,
          },
        ),
      ]));
      await shell.lifecycle('show');

      // 監聯 AgentActivityStore——狀態變化時推送
      AgentActivityStore.instance.snapshot.addListener(() {
        _pushCompanionToPanel(shell);
      });

      // [小葵 2026-09-24 出道令] 待機輪播：idle 持續時每 6s 重推一次（換片+彩蛋骰）
      _idleRotateTimer?.cancel();
      _idleRotateTimer = Timer.periodic(const Duration(seconds: 6), (_) {
        final snap = AgentActivityStore.instance.current;
        if (!snap.active) _pushCompanionToPanel(shell);
      });

      // [教練 Agent 2026-08-12] 監聽夥伴切換——切換時立即更新懸浮窗
      CompanionStore().addListener(() {
        _pushCompanionToPanel(shell);
      });
    });
  }

  /// [小葵 2026-09-12] rig 素材匯出——assets → App Support/bridge_rig/<name>/
  Future<void> _exportRigAssets() async {
    try {
      final support = await getApplicationSupportDirectory();
      final root = Directory('${support.path}/bridge_rig');
      if (!await root.exists()) await root.create(recursive: true);
      const rigs = {
        '小橋': 'xiaoqiao',
        'MimeMi': 'mimemi',
      };
      for (final entry in rigs.entries) {
        final dir = Directory('${root.path}/${entry.value}');
        if (!await dir.exists()) await dir.create(recursive: true);
        for (final f in ['body_full.png', 'head.png', 'arm_R.png', 'arm_L.png']) {
          final src = 'assets/companions/${entry.value}/$f';
          final dst = File('${dir.path}/$f');
          final data = await rootBundle.load(src);
          if (!await dst.exists() || await dst.length() != data.lengthInBytes) {
            await dst.writeAsBytes(data.buffer.asUint8List(), flush: true);
          }
        }
      }
      debugPrint('[rig] assets exported to ${root.path}');
    } catch (e) {
      debugPrint('[rig] export failed: $e');
    }
  }

  /// [教練 Agent 2026-08-11] 推送夥伴狀態 + 圖片到 NSPanel
  void _pushCompanionToPanel(MacosDesktopShellChannel shell) {
    final companion = CompanionStore().activeCompanion;
    final snap = AgentActivityStore.instance.current;

    // 根據 Agent stage 直接映射狀態 ID
    String stateId = 'idle';
    if (snap.active) {
      switch (snap.stage) {
        case AgentActivityStage.understanding:
          stateId = snap.mood == AgentCompanionMood.curious ? 'wandering' : 'reading';
          break;
        case AgentActivityStage.context:
          stateId = 'reading';
          break;
        case AgentActivityStage.routing:
          stateId = 'pointing';
          break;
        case AgentActivityStage.waiting:
          stateId = 'reading';
          break;
        case AgentActivityStage.composing:
          stateId = snap.mood == AgentCompanionMood.proud ? 'idea' : 'writing';
          break;
        case AgentActivityStage.bridge:
          stateId = 'bridging';
          break;
        default:
          stateId = 'reading';
      }
    }

    // 決定要顯示的圖片路徑——優先用對應狀態圖
    // [小葵 2026-09-24 出道令] 影片優先：狀態動畫 mp4 > 主動畫 mp4 > 靜態圖鏈
    // [小葵 2026-10-05 去背版直通] _alphaMovFor：同目錄若有同名 .mov（ProRes 4444
    // 預去背版）優先改用它——Swift 端 .mov 走 AVPlayerLayer 硬解，CPU 從 200% 級
    // 降到近 0（CIContext 逐幀去背完全跳過）。.mp4 舊素材向後相容。
    String? _alphaMovFor(String? mp4Path) {
      if (mp4Path == null || !mp4Path.endsWith('.mp4')) return mp4Path;
      final mov = '${mp4Path.substring(0, mp4Path.length - 4)}.mov';
      return File(mov).existsSync() ? mov : mp4Path;
    }
    String? imagePath;
    String? videoPath;
    if (companion != null) {
      final spec = CompanionStatusHelper.statusSpecById(stateId);
      videoPath = _alphaMovFor(
          CompanionStatusHelper.stateAnimationPathFor(companion, spec));
      videoPath ??= (companion.avatarAnimationPath?.trim().isNotEmpty == true &&
              companion.avatarAnimationPath!.endsWith('.mp4'))
          ? _alphaMovFor(companion.avatarAnimationPath)
          : null;
      // [小葵 2026-09-24 出道令] 待機輪播：idle 狀態且有多段 idle_*.mp4 時，
      // 每次推送隨機挑一段（Swift 端 setRuntime 換檔即重播）。
      // [小葵 2026-09-24 出道令] 彩蛋舞：idle 時 ~15% 機率播 dance.mp4 驚喜一下
      if (stateId == 'idle') {
        final dancePath = companion.stateAnimationPaths['dance'];
        if (dancePath != null &&
            dancePath.endsWith('.mp4') &&
            Random().nextDouble() < 0.15) {
          videoPath = _alphaMovFor(dancePath);
        } else {
          final idlePool = <String>[
            if (videoPath != null && videoPath.contains('/idle')) videoPath,
            for (final p in companion.stateAnimationPaths.values)
              if (p.contains('/idle_') && p.endsWith('.mp4')) p,
          ];
          final unique = idlePool.toSet().toList();
          if (unique.length > 1) {
            unique.shuffle();
            videoPath = _alphaMovFor(unique.first);
          }
        }
      } else if (snap.action == AgentCompanionAction.bouncing) {
        // [小葵 2026-09-24 Blue 令·講話狀態驅動] Agent 出聲時段——完整 talk 池
        // （talk_a~g + c2 八段）隨機跳選，演示時她講起話來畫面活起來。
        final talkPool = companion.stateAnimationPaths.entries
            .where((e) =>
                (e.key.startsWith('talk_')) &&
                e.value.endsWith('.mp4'))
            .map((e) => e.value)
            .toSet()
            .toList();
        if (talkPool.isNotEmpty) {
          talkPool.shuffle();
          videoPath = _alphaMovFor(talkPool.first);
        }
      } else {
        // [小葵 2026-09-24 出道令++] 工作狀態輪播池：狀態主片 + talk 環繞片隨機交替，
        // 長任務時畫面更生動。映射：talk_f(寫)/talk_e(講)/talk_g(俏皮)/talk_c2(好奇)
        final workPool = <String?>[
          if (videoPath != null) videoPath,
          companion.stateAnimationPaths['talk_f'],
          companion.stateAnimationPaths['talk_e'],
          companion.stateAnimationPaths['talk_g'],
          companion.stateAnimationPaths['talk_c2'],
        ].whereType<String>().where((p) => p.endsWith('.mp4')).toSet().toList();
        if (workPool.length > 1) {
          workPool.shuffle();
          videoPath = _alphaMovFor(workPool.first);
        }
      }
      imagePath = CompanionStatusHelper.stateImagePathFor(companion, spec);
      imagePath ??= companion.avatarImagePath;
      // [小葵 2026-09-13] 小橋類夥伴（無 avatar、有狀態圖組）——fallback 第一張狀態圖，
      // 讓懸浮窗也有立繪可呼吸（三帶 rigmap 已為全圖組生成）
      imagePath ??= companion.stateImagePaths?.values.firstWhere(
        (p) => p.trim().isNotEmpty,
        orElse: () => '',
      );
    }

    // [教練 Agent 2026-08-11 debug] 確認推送
    print('[FloatingPanel] push: stateId=$stateId imagePath=$imagePath active=${snap.active}');

    // [小葵 2026-09-24 Blue 三修之一 v2] 非待機看門狗——2 秒規格（Blue 令）。
    // v1 教訓：依賴 !active 判斷會漏——Agent loop 結束時 active 可能殘留 true
    // （上游沒走 idle() 收尾路徑），看門狗永遠不出手。
    // v2：非 idle 狀態一律 2 秒後回待機。Agent 真的工作中會持續推新快照
    // （每個 stage 變化都會 push），每次 push 重置看門狗——工作不停就永不回落；
    // 但同一狀態停滯超過 2 秒（stage 沒變＝Agent 沒在動）就回待機呼吸。
    _stateWatchdogTimer?.cancel();
    if (stateId != 'idle') {
      _stateWatchdogTimer = Timer(const Duration(seconds: 2), () {
        // 殘留狀態收尾。真偽判斷用 controller.isLoading（snap.active 會殘留）：
        // LLM 還在生成（isLoading）就不動；不是在跑＝殘留，回待機呼吸。
        if (_desktopChatController?.isLoading == true) {
          // 還在忙——5 秒後再檢查一次（生成期間持續看著）
          _stateWatchdogTimer =
              Timer(const Duration(seconds: 5), _recheckWatchdog);
          return;
        }
        AgentActivityStore.instance.idle();
      });
    }

    shell.syncRuntime({
      'runtime': {
        'activeCompanionName': companion?.name ?? 'Bridge',
        'activeCompanionRole': companion?.roleName ?? '夥伴',
        'statusText': snap.active
            ? '${snap.stage.shortLabel} · ${spec_labelFor(stateId)}'
            : '自由待機',
        'companionImagePath': imagePath ?? '',
        'companionVideoPath': videoPath ?? '',
        // [小葵 2026-09-12] 活體 rig——狀態直傳，NSPanel 端參數插值動畫
        'rigStateId': stateId,
      },
    });
  }

  /// [小葵 2026-09-24 三修之一 v2] 看門狗複檢——生成期間每 5s 巡一次，
  /// isLoading 落地那一刻（真回覆完成）立即回待機。
  void _recheckWatchdog() {
    if (_desktopChatController?.isLoading == true) {
      _stateWatchdogTimer = Timer(const Duration(seconds: 5), _recheckWatchdog);
      return;
    }
    AgentActivityStore.instance.idle();
  }

  /// [教練 Agent 2026-08-11] 狀態 ID → 中文標籤
  static String spec_labelFor(String stateId) {
    switch (stateId) {
      case 'idle': return '待機';
      case 'reading': return '閱讀';
      case 'writing': return '編寫中';
      case 'pointing': return '指路';
      case 'bridging': return '橋接';
      case 'idea': return '有好點子';
      case 'wandering': return '漫遊';
      case 'celebrating': return '慶祝';
      case 'stuck': return '卡住了';
      default: return stateId;
    }
  }

  /// 跨頁面跳轉處理
  void _onNavigateToTab() {
    final tab = BridgeDesktopScreen.navigateToTab.value;
    if (tab == null || !mounted) return;
    setState(() {
      _isHomepage = false;
      _isCompanionHall = false;
      _isTrainingPage = false; // [Blue 拍板] 離開訓練頁
      switch (tab) {
        case 'chat':
          _onTabChanged(0);
          break;
        case 'canvas':
          _onTabChanged(1);
          break;
        case 'project':
          _onTabChanged(2);
          break;
        case 'brain':
          // [v262] 大腦 tab 已除——改開網頁版獨立視窗
          _openBrainGalaxyWindow();
          break;
        case 'vault':
          _onTabChanged(3);
          break;
        case 'system':
          _onTabChanged(4);
          break;
        case 'training':
          // [Blue 拍板 2026-09-12] 訓練AI夥伴——首頁入口的頁面
          _isTrainingPage = true;
          break;
      }
    });
    // 清空，避免重複觸發
    BridgeDesktopScreen.navigateToTab.value = null;
  }

  /// 索引知識庫——等 BrainContainer（含 embedding model）初始化完成後執行
  Future<void> _indexKnowledgeBase() async {
    // [小葵 2026-09-22 Blue 令] KnowledgeIndexer 全面退役——
    // 知識職責已歸位（工具櫃檯/agent_search_knowledge/羅盤），
    // 啟動索引管線刪除。此方法保留為 no-op（呼叫點不動）。
  }

  /// 註冊共視 registry 回調
  void _registerMcpRegistry() {
    final mcp = BridgeMcpServer.instance;
    final reg = CanvasMcpRegistry.instance;

    // Desktop screen 注入：切 tab、發訊息、列畫布
    reg.onNavigateToCanvas = () {
      setState(() {
        _isHomepage = false;
        _isCompanionHall = false;
        _onTabChanged(1);
      });
    };

    // [小葵 2026-09-07] 2D 圖譜正式退役——搜尋對焦（GlobalKey 通道）隨之退役，
    // 保留開 3D 星系視窗行為
    reg.onBrainSearchFocus = (query) {
      _openBrainGalaxyWindow();
    };

    reg.onSendChatMessage = (message, {role}) {
      // 在畫布對話框顯示 Agent 訊息 — 接到 ChatController
      final controller = _canvasChatController;
      if (controller != null) {
        controller.appendLocalSystemMessage(message);
      }
    };

    reg.onListCanvases = () {
      return _canvases.map((c) => {
        'id': c.id,
        'title': c.title,
      }).toList();
    };

    reg.onLoadCanvas = (canvasId) {
      _activeCanvasId = canvasId;
      _workspaceKey.currentState?.loadCanvasById(canvasId);
    };

    // MCP server 端點 — 透過 registry 存取
    mcp.onGetState = () async {
      final live = reg.getCanvasState();
      // [小橋 自修 2026-09-16 Bug A] 畫布未開啟時 fallback 讀持久層唯讀快照
      if (!live.containsKey('error') && live.isNotEmpty) return live;
      try {
        final canvases = await CanvasStore.getAll();
        if (canvases.isEmpty) {
          return <String, dynamic>{'error': 'Canvas not ready (no persisted canvas)'};
        }
        final canvasId = canvases.first.id;
        final entityGraph = EntityGraphService.withSqliteCanvasStore(
          memoryStore: MemoryStore(),
          doorStore: ProjectDoorStore(),
          assetStore: DigitalAssetRegistryStore(),
        );
        final nodes = await entityGraph.getCanvasNodes(canvasId: canvasId);
        final nodeMaps = nodes
            .map((e) => <String, dynamic>{
                  'id': e.entity.id,
                  'type': e.entity.type,
                  'label': e.entity.title,
                  'x': e.props.x,
                  'y': e.props.y,
                })
            .toList();
        return <String, dynamic>{
          'source': 'persisted',
          'nodes': nodeMaps,
          'edges': <Map<String, dynamic>>[],
          'description': '畫布未開啟，這是持久層唯讀快照',
        };
      } catch (err) {
        return <String, dynamic>{
          'error': 'Canvas not ready (persisted fallback failed): $err',
        };
      }
    };

    // [教練 Agent 2026-08-22 渲染層視網膜] 外部共視對稱——ActualSizeCache 直讀
    mcp.onGetRenderLayer = () async {
      final ctrl = reg.controller;
      if (ctrl == null) return {};
      final out = <String, dynamic>{};
      for (final id in ctrl.state.nodes.keys) {
        final actual = ActualSizeCache.get(id);
        out[id] = {
          'width': actual?.width,
          'height': actual?.height,
          'measured': actual != null,
        };
      }
      return out;
    };

    mcp.onAddNode = (type, x, y) async {
      final ctrl = reg.controller;
      if (ctrl == null) throw Exception('Canvas not ready');
      reg.markNextEventFromAgent(); // [小葵 2026-09-16] 標記接下來的事件來自 agent
      final nodeId = await ctrl.addWorkflowNode(type, Offset(x, y));
      // [小葵 2026-09-16 Blue 令] 跨頁面行動日誌——建節點必記
      reg.logCanvasAction('你新增了節點（type=$type, id=$nodeId, 位置=($x,$y)）');
      return nodeId;
    };

    mcp.onConnect = (fromNodeId, fromPort, toNodeId, toPort) async {
      final ctrl = reg.controller;
      if (ctrl == null) throw Exception('Canvas not ready');
      // [教練 Agent 2026-08-21] connect 回傳錯誤字串（null=成功）。
      // 舊碼丟棄回傳值 → agent 連線被拒也收到「成功」＝又一個靜默失敗。
      reg.markNextEventFromAgent(); // [小葵 2026-09-16] 標記接下來的事件來自 agent
      final err = await ctrl.connect(fromNodeId, fromPort, toNodeId, toPort);
      if (err != null) throw Exception(err);
      // [小葵 2026-09-16 Blue 令] 跨頁面行動日誌——連線必記
      reg.logCanvasAction('你連接了節點（$fromNodeId → $toNodeId）');
    };

    // [教練 Agent 2026-08-26 使用者 基礎規則] 一鍵自動排版
    mcp.onAutoLayout = () {
      return CanvasMcpRegistry.instance.autoLayout();
    };

    mcp.onRemoveNode = (nodeId) async {
      final ctrl = reg.controller;
      if (ctrl == null) throw Exception('Canvas not ready');
      reg.markNextEventFromAgent(); // [小葵 2026-09-16] 標記接下來的事件來自 agent
      await ctrl.removeNode(nodeId);
      // [小葵 2026-09-16 Blue 令] 跨頁面行動日誌——刪節點必記
      reg.logCanvasAction('你刪除了節點（id=$nodeId）');
    };

    // 共視端點 — Agent 主動操作 App
    mcp.onNavigateToCanvas = () {
      reg.navigateToCanvas();
    };

    mcp.onSendChat = (message, {role}) {
      // [教練 Agent 2026-08-08] 統一 sendMessage：desktop → canvas → persistent
      // 不再只注入 UI，每層都觸發完整 Agent Loop
      final dc = _desktopChatController;
      if (dc != null) {
        dc.sendDirectMessage(message);
        return;
      }
      final cc = _canvasChatController;
      if (cc != null) {
        cc.sendDirectMessage(message);
        return;
      }
      _persistentChatController.sendDirectMessage(message);
    };

    // [教練 Agent 2026-07-19] 模擬使用者在聊天框打字——觸發完整 sendMessage 流程
    // 外部（教練 Agent透過 HTTP）可以像使用者一樣發訊息給原生 Agent
    mcp.onSendUserMessage = (message) {
      // [教練 Agent 2026-08-08] 統一鏈：desktop → canvas → persistent
      final dc = _desktopChatController;
      if (dc != null) {
        dc.sendDirectMessage(message);
        return true;
      }
      final cc = _canvasChatController;
      if (cc != null) {
        cc.sendDirectMessage(message);
        return true;
      }
      _persistentChatController.sendDirectMessage(message);
      return true;
    };

    // [教練 Agent 2026-07-19] 派任務到畫布對話框——人機共視的正確入口
    // 打到 CanvasChatPanel 的 ChatController，讓原生 Agent在畫布當下環境工作
    mcp.onSendCanvasMessage = (message) {
      final controller = _canvasChatController;
      if (controller == null) return false;
      controller.sendDirectMessage(message);
      return true;
    };

    // [教練 Agent 2026-07-19] 統一導航——MCP 可切到任何頁面
    mcp.onNavigate = (target, sub) {
      setState(() {
        switch (target) {
          case 'home':
            _isHomepage = true;
            _isCompanionHall = false;
            _isTrainingPage = false; // [Blue 抓包] 幽靈疊層
            break;
          case 'companion':
            _isHomepage = false;
            _isCompanionHall = true;
            _isTrainingPage = false; // [Blue 抓包] 幽靈疊層
            break;
          case 'chat':
            _isHomepage = false;
            _isCompanionHall = false;
            _isTrainingPage = false; // [Blue 抓包] 幽靈疊層
            _onTabChanged(0);
            break;
          case 'canvas':
            _isHomepage = false;
            _isCompanionHall = false;
            _isTrainingPage = false; // [Blue 抓包] 幽靈疊層
            _onTabChanged(1);
            break;
          case 'brain':
            // [v262] 大腦 tab 已除——改開網頁版獨立視窗（mode 參數略過）
            _openBrainGalaxyWindow();
            break;
          case 'vault':
            _isHomepage = false;
            _isCompanionHall = false;
            _isTrainingPage = false; // [Blue 抓包] 幽靈疊層
            _onTabChanged(3);
            break;
          case 'system':
            _isHomepage = false;
            _isCompanionHall = false;
            _isTrainingPage = false; // [Blue 抓包] 幽靈疊層
            _onTabChanged(4);
            _activeSystemPage = sub; // model | pairing | files | settings | null
            break;
        }
      });
    };

    // [教練 Agent 2026-07-19] 取得當前 App 狀態
    mcp.onGetAppState = () {
      String page;
      if (_isHomepage) {
        page = 'home';
      } else if (_isTrainingPage) {
        page = 'training'; // [Blue 拍板 2026-09-12] 訓練AI夥伴頁
      } else if (_isCompanionHall) {
        page = 'companion';
      } else {
        switch (_activeCanvasIndex) {
          case 0: page = 'chat'; break;
          case 1: page = 'canvas'; break;
          case 3: page = 'brain'; break;
          case 4: page = 'vault'; break;
          case 5: page = 'system'; break;
          default: page = 'unknown'; break;
        }
      }
      return {
        'page': page,
        'systemSub': _activeSystemPage,
        'canvasIndex': _activeCanvasIndex,
        'isHomepage': _isHomepage,
        'isCompanionHall': _isCompanionHall,
      };
    };

    // [教練 Agent 2026-07-19] 使用者插嘴——原生 Agent工作時注入訊息
    mcp.onInjectMessage = (message) {
      if (_desktopChatController != null) {
        _desktopChatController!.injectUserMessage(message);
        return true;
      }
      return false;
    };

    // [教練 Agent 2026-08-08] 教練模式——取得原生 Agent最後回覆
    mcp.onGetLastAgentReply = () {
      final reply = CanvasMcpRegistry.instance.lastAgentReply;
      return reply.isEmpty ? null : reply;
    };

    // [教練 Agent 2026-08-08] 教練模式——取得 Agent Loop debug 資訊
    mcp.onGetAgentDebugInfo = () {
      // 優先 desktop → persistent
      final ctrl = _desktopChatController ?? _persistentChatController;
      if (ctrl == null) return null;
      final loop = ctrl.agentLoopForDebug;
      final turnCount = loop?.turnsForDebug.length ?? -1;
      String? provider;
      String? model;
      bool isLocal = false;
      if (loop != null) {
        final client = loop.llmClient;
        if (client is ProductionAgentLoopLLMClient) {
          provider = client.lastReceipt?.provider;
          model = client.lastReceipt?.model;
          isLocal = provider == 'local';
        }
      }
      return {
        'turn': turnCount,
        'provider': provider ?? 'unknown',
        'model': model ?? 'unknown',
        'isLocal': isLocal,
        'isLoading': ctrl.isLoadingForDebug,
        'hasAgentLoop': loop != null,
        'agentLoopEnabled': ctrl.agentLoopEnabledForDebug,
        'agentLoopInited': ctrl.agentLoopInitedForDebug,
        'agentLoopInitError': ctrl.agentLoopInitErrorForDebug ?? 'none',
        'usingDesktopController': _desktopChatController != null,
        'conversationId': ctrl.currentConversationForDebug?.id ?? 'none',
        'messageCount': ctrl.currentConversationForDebug?.messages.length ?? 0,
        'lastRouteDebug': ctrl.bridgeActionExecutor.lastRouteDebug,
      };
    };

    mcp.onListCanvases = () {
      return reg.listCanvases();
    };

    mcp.onLoadCanvas = (canvasId) {
      reg.loadCanvas(canvasId);
    };

    // 截圖 — 透過 registry 呼叫 workspace 的 RepaintBoundary
    mcp.onScreenshot = () async {
      return await reg.screenshot() ?? '';
    };

    // 塗鴉標注
    mcp.onGetAnnotations = () {
      return reg.getAnnotations();
    };

    // [開光 P2 · 小葵 2026-09-26] app_tap——語意點擊走 registry（workspace 注入）
    mcp.onTap = (target) {
      // target 格式：canvas_toolbar:save → 剝前綴
      final button = target.contains(':') ? target.split(':')[1] : target;
      final handler = reg.onTapButton;
      if (handler == null) return null;
      return handler(button);
    };

    // 執行工作流 — 透過 registry 呼叫 workspace 的 WorkflowExecutor
    mcp.onExecute = () async {
      if (reg.onExecute != null) {
        await reg.onExecute!();
      }
    };

    // [教練 Agent 2026-08-01] 設定節點參數 — merge params 到現有
    // [開光 v0.4.x] OS 層視網膜——Swift CGWindowList 拍整個螢幕
    mcp.onScreenCapture = () async {
      try {
        const channel = MethodChannel('bridge.screen_capture.macos.v1');
        final result = await channel
            .invokeMethod<Map>('captureScreen', {})
            .timeout(const Duration(seconds: 5));
        if (result == null) return null;
        final path = result['screenshotPath'] as String?;
        if (path == null || path.isEmpty) return null;
        final f = File(path);
        if (!await f.exists()) return null;
        final bytes = await f.readAsBytes();
        await f.delete(); // 讀完即刪
        return base64Encode(bytes);
      } catch (_) {
        return null;
      }
    };
    // [開光 v0.4.0 2026-10-01] 語意點擊——手的誕生
    // selector→找 Text widget（文字含關鍵詞）→ 取 RenderBox 中心座標
    // confirm=true 才真點（TapGesture）——安全兩段式
    mcp.onAppTap = ({selector, x, y, confirm = false}) async {
      try {
        Offset? target;
        String? hit;
        if (selector != null) {
          // 收集候選（全域掃，不 early-return——閉包 return 只跳單層的陷阱），
          // 之後取「y 座標在視野內且最短文字」的最佳候選（短=按鈕而非標題）
          final candidates = <Map<String, dynamic>>[];
          void findText(Element el) {
            el.visitChildElements((child) {
              final w = child.widget;
              String? data;
              if (w is Text) data = w.data ?? '';
              if (w is SelectableText) data = w.data ?? '';
              if (data != null && data.contains(selector)) {
                final ro = child.findRenderObject();
                if (ro is RenderBox && ro.hasSize && ro.size != Size.zero) {
                  // 找最近可點祖先
                  Element? clickable = child;
                  Offset? best;
                  for (int i = 0; i < 8 && clickable != null; i++) {
                    final pw = clickable.widget;
                    if (pw is GestureDetector ||
                        pw is InkWell ||
                        pw is TextButton ||
                        pw is ElevatedButton ||
                        pw is OutlinedButton ||
                        pw is IconButton) {
                      final cro = clickable.findRenderObject();
                      if (cro is RenderBox && cro.hasSize) {
                        best = cro.localToGlobal(cro.size.center(Offset.zero));
                        break;
                      }
                    }
                    Element? next;
                    clickable.visitAncestorElements((anc) {
                      next = anc;
                      return false;
                    });
                    clickable = next;
                  }
                  best ??= ro.localToGlobal(ro.size.center(Offset.zero));
                  candidates.add({'text': data.trim(), 'offset': best!});
                }
              }
              findText(child);
            });
          }
          context.visitChildElements(findText);
          if (candidates.isNotEmpty) {
            // 視野內優先（y 0..視窗高），再取文字最短（按鈕精準於標題）
            final winH = MediaQuery.of(context).size.height;
            Map<String, dynamic>? best;
            for (final c in candidates) {
              final off = c['offset'] as Offset;
              if (best == null) { best = c; continue; }
              final bOff = best!['offset'] as Offset;
              final cVis = off.dy >= 0 && off.dy <= winH;
              final bVis = bOff.dy >= 0 && bOff.dy <= winH;
              if (cVis != bVis) { if (cVis) best = c; continue; }
              final cText = (c['text'] as String).length;
              final bText = (best!['text'] as String).length;
              if (cText < bText) best = c;
            }
            target = best!['offset'] as Offset;
            hit = best!['text'] as String;
          }
        } else if (x != null && y != null) {
          target = Offset(x, y);
          hit = '(座標後門)';
        }
        if (target == null) {
          return {
            'success': false,
            'message': selector != null ? '找不到「$selector」可點元件' : '需提供 selector 或 x/y',
          };
        }
        if (!confirm) {
          return {
            'success': true,
            'found': hit,
            'x': target!.dx,
            'y': target!.dy,
            'note': '座標已定位（confirm=false 回報制）。加 confirm=true 執行點擊',
          };
        }
        // [開光 v0.4.x] 真點執行——hitTest → 派發 PointerDown/Up 事件流
        try {
          final pos = target!;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          final gesture = GestureBinding.instance;
          // 2) down → up（同一 pointer id，80ms 間隔=輕點）
          const pid = 991001; // 專用 pointer id（避開真實輸入）
          // [開光 v0.4.x] 正規入口：handlePointerEvent——完整 pointer lifecycle
          // （hitTest→pointer router→gesture arena），GestureDetector.onTap 才會觸發。
          // 直接 handleEvent 繞過 arena（42 targets 收到事件但 onTap 不響的實證）。
          gesture.handlePointerEvent(PointerDownEvent(pointer: pid, position: pos));
          await Future<void>.delayed(const Duration(milliseconds: 80));
          gesture.handlePointerEvent(PointerUpEvent(pointer: pid, position: pos));
          return {
            'success': true,
            'tapped': true,
            'found': hit,
            'x': pos.dx,
            'y': pos.dy,
            'via': 'handlePointerEvent',
            'note': '已執行點擊',
          };
        } catch (e) {
          return {'success': false, 'message': '點擊執行失敗: $e'};
        }
      } catch (e) {
        return {'success': false, 'message': '定位失敗: $e'};
      }
    };
    // [開光 P1 2026-10-01] 頁面捲動感官——agent 看見頁面深處（選擇模型清單尾部等）
    mcp.onAppScroll = (direction, pixels) async {
      try {
        final ctx = context;
        ScrollableState? target;
        // [v6 實證法 2026-10-01] benchmark 六代教訓收斂：
        // 擇靶五法全被騙（離屏/兄弟頁/惰性 extent/hit-miss/viewport 面積）。
        // 正解=實證：收集全部候選→逐個試捲 60px→pixels 真的動的那隻=活的；
        // 離屏 scrollable 的 jumpTo 會被夾回（position 不變）。
        final candidates = <ScrollableState>[];
        void collect(Element el) {
          el.visitChildElements((child) {
            final s = Scrollable.maybeOf(child);
            if (s != null &&
                s.position.axis == Axis.vertical &&
                s.position.maxScrollExtent > 0) {
              candidates.add(s);
            }
            collect(child);
          });
        }
        ctx.visitChildElements(collect);
        if (candidates.isNotEmpty) {
          final seen = <ScrollPosition>{};
          candidates.retainWhere((s) => seen.add(s.position));
          // [v7] pixels 會動不夠——離屏 scrollable 的 pixels 也動。
          // 加「畫面真實位移」驗證：捲 60px 前後，記錄固定子節點的
          // localToGlobal 變化；真的在畫面上的，內容會滑。
          for (var pass = 0; pass < 2 && target == null; pass++) {
            final secondPass = pass == 1;
          for (final s in candidates) {
            // [v8 世紀謎底] Offstage 祖先=離屏但保持 state（頁面快取）——
            // pixels 會動、layout 會變，但不渲染。直接排除。
            bool offstage = false;
            s.context?.visitAncestorElements((a) {
              if (a.widget is Offstage) {
                offstage = true;
                return false;
              }
              return true;
            });
            // [v8.2 兩輪制] 第一輪跳過 Offstage；第二輪（fallback）全收
            if (offstage && !secondPass) {
              continue;
            }
            final ctx2 = s.context;
            final ro0 = ctx2?.findRenderObject();
            Offset? contentPos0;
            if (ro0 is RenderBox && ro0.attached) {
              contentPos0 = ro0.localToGlobal(Offset.zero);
            }
            final p0 = s.position.pixels;
            try {
              s.position.jumpTo(
                  (p0 + 60).clamp(0.0, s.position.maxScrollExtent));
            } catch (_) {
              continue;
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
            final moved = (s.position.pixels - p0).abs() > 1;
            Offset? contentPos1;
            final ro1 = ctx2?.findRenderObject();
            if (ro1 is RenderBox && ro1.attached) {
              contentPos1 = ro1.localToGlobal(Offset.zero);
            }
            final visuallyMoved = contentPos0 != null &&
                contentPos1 != null &&
                (contentPos0 - contentPos1).distance > 1;
            try {
              s.position.jumpTo(p0);
            } catch (_) {}
            if (moved && visuallyMoved) {
              target = s;
              debugPrint('[app_scroll v8] pass$pass 命中: ${s.widget.runtimeType} extent=${s.position.maxScrollExtent}');
              break;
            }
          }
          }
        }
        if (target == null) {
          return {'success': false, 'message': '当前頁面無可捲動區域'};
        }
        // [診斷] 回報選中的 scrollable 身分
        final pickedType = target!.widget.runtimeType.toString();
        var pickedCtx = '(no ctx)';
        BuildContext? c = target!.context;
        if (c != null) {
          pickedCtx = c.widget?.runtimeType.toString() ?? '?';
          // 向上三層
          for (int i = 0; i < 8; i++) {
            String? up;
            c?.visitAncestorElements((a) {
              up = a.widget?.runtimeType.toString();
              return false;
            });
            if (up == null) break;
            pickedCtx = '$pickedCtx <- $up';
            Element? next;
            c?.visitAncestorElements((a) { next = a; return false; });
            c = next;
          }
        }
        final pos = target!.position;
        if (!pos.maxScrollExtent.isFinite || pos.maxScrollExtent == 0) {
          return {'success': false, 'message': '頁面無捲動空間'};
        }
        switch (direction) {
          case 'top':
            pos.jumpTo(0);
            break;
          case 'bottom':
            pos.jumpTo(pos.maxScrollExtent);
            break;
          case 'up':
          case 'down':
            final delta = pixels ?? 600;
            pos.jumpTo((pos.pixels + (direction == 'down' ? delta : -delta))
                .clamp(0.0, pos.maxScrollExtent));
            break;
          default:
            return {'success': false, 'message': '未知 direction: $direction'};
        }
        // [v4 幀同步] jumpTo 後等一幀——否則「立即拍照」拍到捲動前的 repaint cache
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return {
          'success': true,
          'position': target!.position.pixels,
          'maxScrollExtent': target!.position.maxScrollExtent,
          'reachedBottom': target!.position.pixels >= target!.position.maxScrollExtent - 1,
          'picked': '$pickedType @$pickedCtx',
        };
      } catch (e) {
        return {'success': false, 'message': '捲動失敗: $e'};
      }
    };
    mcp.onSetNodeParams = (nodeId, newParams) async {
      final ctrl = reg.controller;
      if (ctrl == null) throw Exception('Canvas not ready');

      // 讀取現有 params
      final node = ctrl.state.nodes[nodeId];
      if (node == null) throw Exception('Node not found: $nodeId');

      final oldProps = node.entity.canvasProps;
      final oldParams = oldProps?.params ?? {};
      final mergedParams = <String, dynamic>{
        ...oldParams,
        ...newParams, // 新的覆蓋舊的
      };

      // 用 updateNodeParams 更新
      final nodeType = oldProps?.nodeType;
      ctrl.updateNodeParams(nodeId, nodeType, mergedParams);
      // [小葵 2026-09-16 Blue 令] 跨頁面行動日誌——改參數必記
      reg.logCanvasAction('你更新了節點參數（id=$nodeId, params=${mergedParams.keys.join(",")}）');

      return mergedParams;
    };

    // [教練 Agent 2026-08-01] 取得節點參數
    // [小橋 自修 2026-09-16] async 化 + 持久層 fallback（與 onGetState 同構）
    mcp.onGetNodeParams = (nodeId) async {
      final ctrl = reg.controller;
      if (ctrl != null) {
        final node = ctrl.state.nodes[nodeId];
        if (node == null) throw Exception('Node not found: $nodeId');
        return <String, dynamic>{
          ...?node.entity.canvasProps?.params,
        };
      }
      // 畫布未開啟——讀持久層
      try {
        final canvases = await CanvasStore.getAll();
        if (canvases.isEmpty) {
          throw Exception('Canvas not ready (no persisted canvas)');
        }
        final canvasId = canvases.first.id;
        final entityGraph = EntityGraphService.withSqliteCanvasStore(
          memoryStore: MemoryStore(),
          doorStore: ProjectDoorStore(),
          assetStore: DigitalAssetRegistryStore(),
        );
        final nodes = await entityGraph.getCanvasNodes(canvasId: canvasId);
        for (final e in nodes) {
          if (e.entity.id == nodeId) {
            return <String, dynamic>{
              'source': 'persisted',
              ...?e.props.params,
            };
          }
        }
        throw Exception('Node not found in persisted store: $nodeId');
      } catch (err) {
        if (err is Exception) rethrow;
        throw Exception('Canvas not ready (persisted fallback failed): $err');
      }
    };

    // [教練 Agent 2026-08-01] 清空畫布
    mcp.onClearCanvas = () async {
      final ctrl = reg.controller;
      if (ctrl == null) throw Exception('Canvas not ready');
      final nodeIds = ctrl.state.nodes.keys.toList();
      for (final id in nodeIds) {
        await ctrl.removeNode(id);
      }
    };

    // [教練 Agent 2026-08-01] 載入工作流模板
    mcp.onLoadTemplate = (templateId) async {
      // 透過 registry 的 onLoadTemplate callback（已接線到 workspace）
      reg.onLoadTemplate?.call(templateId);
    };

    // [Phase 0 Track A 2026-07-17] 建立 MCP 工具執行器，注入 ChatController
    _mcpCanvasExecutor = _DesktopMcpCanvasExecutor(
      mcp: mcp,
      reg: reg,
      // [小葵 2026-09-15] 跨頁移交——當前畫布 ID（同 sourceCanvasId 邏輯）
      activeCanvasIdGetter: () => _activeCanvasId,
    );

    // [Phase 1 2026-07-17] 啟動 NativeAgentLoop — 讓 Agent 活起來
    _startNativeAgentLoop();
  }

  @override
  void dispose() {
    // [隊友訊息流 C5] 解綁任務監聽
    TaskDispatcher.instance.removeListener(_onTaskChanged);
    // [無限插槽 C2 2026-10-06 移植] 解綁插槽註冊表監聽
    SlotRegistry.instance.removeListener(_onSlotRegistryChanged);
    _nativeAgentLoop?.stop();
    _agentEventBus?.dispose();
    _healthTimer?.cancel();
    _idleRotateTimer?.cancel();
    _stateWatchdogTimer?.cancel();
    _gatewayHandle?.close();
    // [教練 Agent 2026-07-22] #4: 停止記憶體監控
    MemoryGuardService.instance.stop();
    // [W1 2026-10-08] App 層排程引擎停止（引擎生命周期跟著 App 走）
    AppScheduleEngine.instance.stop();
    BridgeMcpServer.instance.stop();
    // [教練 Agent 2026-07-28] Phase 5: 移除跨頁面跳轉監聽
    BridgeDesktopScreen.navigateToTab.removeListener(_onNavigateToTab);
    // [羅盤 2026-09-06] 釋放快捷鍵 callback
    BridgeDesktopScreen.navigateToCompass = null;
    TrayService.onOpenTrainingPage = null; // [Blue 拍板] 訓練頁 callback 清理
    // [收據搜尋 RC2.5] 釋放快捷鍵 callback
    BridgeDesktopScreen.navigateToReceiptsSearch = null;
    _galaxySaver.dispose();
    super.dispose();
  }

  /// [Phase 1 2026-07-17] 啟動 NativeAgentLoop
  ///
  /// 建立 AgentEventBus + PersonaManager + NativeAgentLoop，
  /// 讓原生 Agent 能自主感知環境、判斷、行動。
  void _startNativeAgentLoop() {
    try {
      // [教練 Agent 2026-07-18] 初始化 ProviderProfileStore（可自進化的分層系統）
      ProviderProfileStore.instance.initialize();

      // [教練 Agent 2026-07-18] 觸發 macOS TCC 螢幕錄製權限請求
      // [2026-07-20] 已停用——App 自拍 (FlutterSelfCaptureExecutor) 不需要系統螢幕錄製權限。
      // 舊設計用 CGWindowListCreateImage 截全螢幕需要 TCC 授權，但現在截圖走 RepaintBoundary，
      // 每次重新 build 都會因 binary 簽章變化而重新彈權限視窗，造成使用者困擾。
      // _triggerScreenCapturePermission();

      _agentEventBus = AgentEventBus();
      _personaManager = PersonaManager();

      // 建立輕量 AgentLoop（含 MCP canvas tools + screen_capture + 自維修工具 + UI 操作工具）
      final uiExecutor = _DesktopUiActionExecutor(this);
      // [2026-07-18 使用者 提議] App 自拍取代系統截圖
      // FlutterSelfCaptureExecutor 用 RepaintBoundary 截 App 自己的畫面
      // 不需要螢幕錄製權限，不受前景/背景影響，截圖自動 ring buffer 清理
      final selfCaptureExecutor = FlutterSelfCaptureExecutor(
        boundaryKey: _selfCaptureKey,
        maxScreenshots: 20,
      );
      final toolRegistry = AgentToolRegistry.withDefaults(
        bridgeActionExecutor: BridgeActionExecutor(),
        brainContainerService: BrainContainerService.instance,
        mcpCanvasExecutor: _mcpCanvasExecutor,
        screenCaptureEnabled: true,
        screenCaptureExecutor: selfCaptureExecutor,
        uiActionExecutor: uiExecutor,
      );

      final agentLoop = AgentLoop(
        toolRegistry: toolRegistry,
        llmClient: ProductionAgentLoopLLMClient(),
      );

      // [D002 2026-08-10] 安全確認——NativeAgentLoop 的 AgentLoop 也要掛上
      // 這是畫布頁面原生 Agent跑的 AgentLoop，之前漏掛導致 canvas_remove 直接跳過確認
      agentLoop.onToolConfirmation = ({required toolName, required args}) async {
        final needsConfirm =
            AgentSafetyConstraints.needsToolConfirmation(toolName, args);
        if (!needsConfirm) return true;
        return showD002ConfirmationDialog(toolName: toolName, args: args);
      };

      _nativeAgentLoop = NativeAgentLoop(
        agentLoop: agentLoop,
        toolRegistry: toolRegistry,
        eventBus: _agentEventBus!,
        personaManager: _personaManager!,
        canvasExecutor: _mcpCanvasExecutor!,
      );
      _nativeAgentLoop!.start();
      debugPrint('[Phase 1] NativeAgentLoop 已啟動 ✅');
    } catch (e) {
      debugPrint('[Phase 1] NativeAgentLoop 啟動失敗: $e');
    }
  }

  /// [教練 Agent 2026-07-18] 觸發 macOS TCC 螢幕錄製權限請求
  /// 直接呼叫 MethodChannel，不靠原生 Agent——確保 App 啟動就觸發
  /// 注意：CGWindowListCreateImage 可能在 merged thread 上短暫阻塞，
  /// 用 5 秒延遲讓 UI 先渲染完再觸發
  void _triggerScreenCapturePermission() {
    Future.delayed(const Duration(seconds: 5), () async {
      try {
        const channel = MethodChannel('bridge.screen_capture.macos.v1');
        await channel.invokeMethod<Map>('captureWindow', {}).timeout(
          const Duration(seconds: 3),
        );
        debugPrint('[TCC] screen_capture 已觸發——請到系統設定授權');
      } catch (e) {
        debugPrint('[TCC] screen_capture 觸發完成（權限未授權屬正常）: $e');
      }
    });
  }

  // ═══════════════════════════════════════════════════
  // UI 導航方法 — 供 _DesktopUiActionExecutor 呼叫
  // [Phase 2 2026-07-18] 讓原生 Agent能切換頁面
  // ═══════════════════════════════════════════════════

  void _goHome() {
    if (!mounted) return;
    setState(() {
      _isHomepage = true;
      _isCompanionHall = false;
    });
  }

  void _goCompanionHall() {
    if (!mounted) return;
    setState(() {
      _isHomepage = false;
      _isCompanionHall = true;
    });
  }

  void _switchTab(int index) {
    if (!mounted) return;
    setState(() {
      _isHomepage = false;
      _isCompanionHall = false;
      _onTabChanged(index);
    });
  }

  void _goSummon() {
    context.go('/desktop-summon');
  }

  /// 使用者修改了 URL 或 Token，清除目前 provider 的「已儲存」和「已測試」狀態
  // [教練 Agent 2026-07-25] 移除 _onApiInputChanged listener
  // 7/12 版本沒有這個 listener，它只會造成狀態被意外清除
  // 用戶編輯 URL/Token 時不需要清除測試狀態 — 測試按鈕自己會管理

  Future<void> _initializeDesktop() async {
    try {
      await _detectLanIp();
      await _buildPairingContract();
      await _startGateway();
    } catch (e) {
      setState(() => _gatewayError = '初始化失敗：$e');
    }
  }

  Future<void> _detectLanIp() async {
    const detector = LanIpDetector();
    final allIps = await detector.detectAllLanIps();
    if (mounted) {
      setState(() {
        _allLanIps = allIps;
        _lanIp = allIps.isNotEmpty ? allIps.first : null;
      });
    }
  }

  Future<void> _buildPairingContract() async {
    const configStore = DesktopCompanionShellConfigStore();
    const envReportStore = DesktopShellEnvironmentReportStore();
    const pairingService = DesktopBridgePairingContractService();

    final config = await configStore.load();
    final envReport = await envReportStore.load();

    final nativeShellConnected = Platform.isMacOS || Platform.isWindows;

    final contract = pairingService.buildContract(
      config: config ?? const DesktopCompanionShellConfig(),
      environmentReport: envReport ??
          const DesktopShellEnvironmentReport(
            items: [],
            summary: 'Desktop environment ready',
          ),
      nativeShellConnected: nativeShellConnected,
      localGatewayReady: true,
      localGatewayEndpoint: 'ws://127.0.0.1:8790/bridge',
    );

    setState(() {
      _pairingContract = contract;
      _pairingCode = contract.pairingCode;
    });
  }

  Future<void> _startGateway() async {
    if (_pairingContract == null) {
      setState(() => _gatewayError = '無法啟動 Gateway：配對合約尚未建立。請先回到系統頁面初始化配對。');
      _addLog('Gateway 啟動失敗：配對合約為 null', _LogType.error);
      return;
    }

    try {
      final gateway = DesktopBridgeLocalGateway();
      final handle = await gateway.start(
        pairingContract: _pairingContract!,
        runtimePayloadProvider: _runtimePayload,
        onClientConnected: () {
          setState(() {
            _mobileConnected = true;
            _connectCount++;
          });
          _addLog('手機已連線', _LogType.connected);
        },
        onClientDisconnected: () {
          setState(() => _mobileConnected = false);
          _addLog('手機已斷線', _LogType.disconnected);
        },
        onRequest: (request) {
          _addLog(
            '${request.type.name} (id: ${request.id})',
            _LogType.request,
          );
        },
      );

      setState(() {
        _gatewayHandle = handle;
        _gatewayRunning = true;
        _gatewayPort = handle.port;
        _gatewayError = null;
      });
      _addLog('Gateway 已啟動 (port ${handle.port})', _LogType.system);
    } catch (e) {
      setState(() => _gatewayError = 'Gateway 啟動失敗：$e');
      _addLog('Gateway 啟動失敗：$e', _LogType.error);
    }
  }

  Future<void> _stopGateway() async {
    await _gatewayHandle?.close();
    setState(() {
      _gatewayHandle = null;
      _gatewayRunning = false;
      _gatewayPort = null;
      _mobileConnected = false;
    });
    _addLog('Gateway 已關閉', _LogType.system);
  }

  Future<void> _restartGateway() async {
    await _stopGateway();
    await Future.delayed(const Duration(milliseconds: 500));
    await _startGateway();
  }

  Map<String, dynamic> _runtimePayload() {
    return {
      'platform': Platform.operatingSystem,
      'desktopName': _pairingContract?.desktopName ?? 'Bridge Desktop',
      'gatewayRunning': _gatewayRunning,
      'gatewayPort': _gatewayPort,
      'mobileConnected': _mobileConnected,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  void _addLog(String message, _LogType type) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, _GatewayLogEntry(message, type, DateTime.now()));
      if (_log.length > _maxLogEntries) _log.removeLast();
    });
  }

  void _clearLog() => setState(() => _log.clear());

  // ═══════════════════════════════════════════════════
  // 數據加載
  // ═══════════════════════════════════════════════════

  Future<void> _loadConversations() async {
    try {
      final convs = await ConversationStore.getAll();
      final currentId = await ConversationStore.getCurrentId();
      if (mounted) setState(() {
        _conversations = convs;
        _currentConversationId = currentId;
      });
    } catch (e) {
      debugPrint('載入對話失敗: $e');
    }
  }

  /// D11: 載入畫布列表
  Future<void> _loadCanvases() async {
    try {
      final canvases = await CanvasStore.getAll();
      if (mounted) {
        setState(() => _canvases = canvases);
        // [v199 Blue 畫布失蹤令 2026-09-01] App 重啟後畫布頁空白（無畫布無
        // 對話框）——因為 _activeCanvasId=null 時 CanvasV2Workspace 不載入
        // 任何東西。修：自動恢復最近編輯的畫布（getAll 已按 updatedAt 排序）。
        if (_activeCanvasId == null && canvases.isNotEmpty) {
          _activeCanvasId = canvases.first.id;
          debugPrint('[v199] 自動恢復最近畫布: ${canvases.first.id}');
          // workspace 可能已用 'default' 初始化（Offstage 保活提早安裝）——
          // 主動同步，不依賴 build postFrame 的時序
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ws = _workspaceKey.currentState;
            if (ws != null && ws.canvasId != canvases.first.id) {
              debugPrint('[v199] workspace 同步載入: ${canvases.first.id}');
              ws.loadCanvasById(canvases.first.id);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('載入畫布失敗: $e');
    }
  }

  /// D11: 新建畫布 + 對話 thread + 專案門
  /// [教練 Agent 2026-07-24] 三者同時建立，一開始就綁定在一起
  Future<void> _createNewCanvas() async {
    final title = await _showTextInputDialog('新增專案', '輸入專案名稱');
    if (title == null || title.isEmpty) return;

    final companionId = CompanionStore().activeCompanion?.id;

    // 1. 建立專案門 (ProjectDoor)
    final door = ProjectDoor.create(
      title: title,
      sourceIntent: 'canvas',
    ).copyWith(status: 'active');
    await ProjectDoorStore().save(door);

    // 2. 建立對話 thread — 綁定 projectDoorId
    final conv = Conversation.createProjectCanvas(
      canvasId: '', // 暫時空，建立畫布後回填
      title: title,
      companionId: companionId,
    ).copyWith(projectDoorId: door.id);
    await ConversationStore.save(conv);

    // 3. 建立畫布 — 綁定 conversationId + projectDoorId
    final canvas = await CanvasStore.create(
      title: title,
      conversationId: conv.id,
    );
    // 回填 projectDoorId 到畫布
    final canvasWithDoor = canvas.copyWith(projectDoorId: door.id);
    await CanvasStore.save(canvasWithDoor);

    // 4. 回填 canvasId 到對話
    final updatedConv = conv.copyWith(canvasId: canvasWithDoor.id);
    await ConversationStore.save(updatedConv);

    await _loadCanvases();
    await _loadConversations();

    // 切換到畫布 tab
    setState(() {
      _onTabChanged(1);
      _activeCanvasId = canvasWithDoor.id;
      _currentConversationId = conv.id;
    });
    await ConversationStore.setCurrentId(conv.id);
    // 新建畫布要清空舊的視覺節點
    _workspaceKey.currentState?.loadCanvasById(canvasWithDoor.id, clearCanvas: true);

    // 切換聊天對話到新建的 conversation
    if (_canvasChatController != null) {
      await _canvasChatController!.switchConversation(updatedConv);
    }
  }

  /// [教練 Agent 2026-08-16 使用者要求 2] 中斷 agent 確認對話框——
  /// 要停就要明說，不讓「不小心停掉」發生。
  Future<bool> _confirmInterruptAgent() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(context).surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
          side: BorderSide(color: BridgeDSColors.of(context).accentYellow),
        ),
        title: Text('🤖 Agent 正在工作中', style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
        content: Text(
          '切換專案會中斷 Agent 目前的任務。\n\n要中斷嗎？（留在此頁＝任務繼續跑）',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('讓他繼續'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: BridgeDSColors.of(context).accentRed,
            ),
            child: const Text('中斷任務'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// D11: 切換到指定畫布的對話
  /// [教練 Agent 2026-07-24] 修復：conversationId 找不到時用 canvasId 反查 Conversation，
  /// 確保三者同步。也同步 ProjectDoor 綁定。
  // ── [W4.3] 排程卡四行動鈕 ──────────────────────────────

  /// 📂 開產出資料夾（Finder）——無路徑時開預設輸出根目錄
  Future<void> _openScheduleFolder(ScheduleQueueEntry entry) async {
    final raw = entry.params['outputFolder'] as String? ?? '';
    Directory dir;
    if (raw.startsWith('/')) {
      dir = Directory(raw);
    } else {
      final base = await getApplicationSupportDirectory();
      dir = Directory(
          '${base.path}/schedule_outputs/${raw.isEmpty ? entry.nodeId : raw}');
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    await Process.run('open', [dir.path]);
  }

  /// ▶ 立即執行——[W4.5 Blue 令] 走引擎 fireNow（與排程觸發同一條管線）。
  /// [W4.5b Blue 令 2026-10-09] 誤觸保險：按 ▶ 先確認——排程可能觸發
  /// 付費產出任務（生圖等），跟使用者再確認一次才真的扣板機。
  Future<void> _runScheduleNow(ScheduleQueueEntry entry) async {
    if (entry.canvasId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('「${entry.title}」沒有所屬畫布——無法執行'),
            duration: const Duration(seconds: 3)),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(ctx).surfaceElevated,
        title: Text('立即執行「${entry.title}」？',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: BridgeDSColors.of(ctx).textPrimary)),
        content: Text(
          '這會馬上跑一次這個排程的工作流。\n'
          '如果工作流會產生付費內容（例如生圖），\n'
          '這次執行就會真的扣款產出。',
          style: TextStyle(
              fontSize: 13, color: BridgeDSColors.of(ctx).textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消',
                style: TextStyle(
                    color: BridgeDSColors.of(ctx).textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('執行',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: BridgeDSColors.of(ctx).accentBlue)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('▶ 正在執行「${entry.title}」…'),
        duration: const Duration(seconds: 2),
      ),
    );
    await AppScheduleEngine.instance
        .fireNow(entry.nodeId, entry.title, entry.canvasId);
    // 執行完刷新排隊卡（歷史/上次紀錄）
    scheduleQueueRev.value++;
  }

  /// [W4.3] 排隊區刷新訊號——暫停切換後立刻通知卡片重載
  static final ValueNotifier<int> scheduleQueueRev =
      ValueNotifier<int>(0);

  /// [W4.4] 資訊欄狀態——目前開啟的任務（null=關閉）。
  /// 單一欄位：點其他卡只換內容不疊新彈窗；自己按 ✕ 才關。
  final ValueNotifier<ScheduleQueueEntry?> _drawerEntry =
      ValueNotifier<ScheduleQueueEntry?>(null);

  /// ⏸/續跑——寫回節點 params.paused（正規管線 setCanvasProps）
  Future<void> _toggleSchedulePause(
      ScheduleQueueEntry entry, bool paused) async {
    try {
      final graph = EntityGraphService.withSqliteCanvasStore(
        memoryStore: MemoryStore(),
        doorStore: ProjectDoorStore(),
        assetStore: DigitalAssetRegistryStore(),
      );
      final nodes = await graph.getCanvasNodes(canvasId: null);
      final target =
          nodes.where((n) => n.entity.id == entry.nodeId).firstOrNull;
      if (target == null) throw StateError('找不到節點 ${entry.nodeId}');
      final newParams = Map<String, dynamic>.from(entry.params);
      newParams['paused'] = paused;
      final newProps = target.props.copyWith(params: newParams);
      await graph.setCanvasProps(entry.nodeId, newProps);
      // [W4.3] 立刻重載排隊卡（不用等 60s tick）
      scheduleQueueRev.value++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                paused ? '已暫停「${entry.title}」' : '「${entry.title}」恢復排隊'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('切換失敗：$e'),
              duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  Future<void> _switchCanvas(String canvasId) async {
    final canvas = _canvases.where((c) => c.id == canvasId).firstOrNull;
    if (canvas == null) return;

    // [教練 Agent 2026-08-16 使用者要求 2] agent 忙線時切畫布＝中斷任務——
    // 必須明確確認，不能讓使用者不小心停掉還以為它在背景跑。
    if (_canvasChatController?.isLoading == true && _activeCanvasId != canvasId) {
      final confirmed = await _confirmInterruptAgent();
      if (!confirmed) return;
    }

    // [教練 Agent 2026-07-24] 嘗試用 canvas.conversationId 找對話；
    // 找不到時用 canvasId 反查 Conversation.canvasId
    String? effectiveConvId = canvas.conversationId;
    if (effectiveConvId != null) {
      final conv = await ConversationStore.getById(effectiveConvId);
      if (conv == null) {
        // conversationId 指向幽靈對話，用 canvasId 反查
        final allConvs = await ConversationStore.getAll();
        final match = allConvs.where(
            (c) => c.canvasId == canvasId && c.type == ConversationType.projectCanvas
        ).firstOrNull;
        effectiveConvId = match?.id;
      }
    } else {
      // 沒有 conversationId，用 canvasId 反查
      final allConvs = await ConversationStore.getAll();
      final match = allConvs.where(
          (c) => c.canvasId == canvasId && c.type == ConversationType.projectCanvas
      ).firstOrNull;
      effectiveConvId = match?.id;
    }

    setState(() {
      _onTabChanged(1);
      _activeCanvasId = canvasId;
      if (effectiveConvId != null) {
        _currentConversationId = effectiveConvId;
      }
    });

    if (effectiveConvId != null) {
      await ConversationStore.setCurrentId(effectiveConvId);
    }

    // 讓 workspace 載入這個畫布的節點和 canvasId
    _workspaceKey.currentState?.loadCanvasById(canvasId);

    // 切換聊天對話到對應的 conversation
    if (effectiveConvId != null && _canvasChatController != null) {
      final conv = await ConversationStore.getById(effectiveConvId);
      if (conv != null) {
        // [教練 Agent 2026-07-24] 如果對話缺少 projectDoorId，回填
        if (conv.projectDoorId == null && canvas.projectDoorId != null) {
          final patched = conv.copyWith(projectDoorId: canvas.projectDoorId);
          await ConversationStore.save(patched);
          await _canvasChatController!.switchConversation(patched);
        } else {
          await _canvasChatController!.switchConversation(conv);
        }
      }
    }

    // [教練 Agent 2026-07-24] 如果 Canvas 的 conversationId 是斷的，回填修復
    if ((canvas.conversationId == null || canvas.conversationId != effectiveConvId) && effectiveConvId != null) {
      final fixedCanvas = canvas.copyWith(conversationId: effectiveConvId, updatedAt: DateTime.now());
      await CanvasStore.save(fixedCanvas);
      await _loadCanvases();
    }
  }

  /// 改名畫布
  Future<void> _renameCanvas(String canvasId, String newTitle) async {
    final canvas = await CanvasStore.getById(canvasId);
    if (canvas == null) return;
    final updated = canvas.copyWith(title: newTitle, updatedAt: DateTime.now());
    await CanvasStore.save(updated);
    // 同步改名關聯的對話
    if (canvas.conversationId != null) {
      final conv = await ConversationStore.getById(canvas.conversationId!);
      if (conv != null) {
        await ConversationStore.save(conv.copyWith(title: newTitle, updatedAt: DateTime.now()));
      }
    }
    // 同步改名 ProjectDoor
    if (canvas.projectDoorId != null) {
      final doorStore = ProjectDoorStore();
      final doors = await doorStore.loadAll();
      final door = doors.where((d) => d.id == canvas.projectDoorId).firstOrNull;
      if (door != null) {
        await doorStore.save(door.copyWith(title: newTitle, updatedAt: DateTime.now()));
      }
    }
    await _loadCanvases();
    await _loadConversations();
    setState(() {});
  }

  /// 顯示改名對話框（通用，適用畫布）
  void _showCanvasRenameDialog(String canvasId, String currentTitle) {
    final controller = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(context).surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
          side: BorderSide(color: BridgeDSColors.of(context).borderDefault),
        ),
        title: Text('修改專案名稱', style: TierStyle.of(context, Tier.bodyPrimary).toTextStyle()),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
          decoration: InputDecoration(
            hintText: '輸入新名稱',
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 06),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: BridgeDSColors.of(context).textTertiary),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) _renameCanvas(canvasId, newTitle);
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: BridgeDSColors.of(context).accentBlue),
            child: const Text('確認'),
          ),
        ],
      ),
    );
  }

  /// 刪除畫布（含關聯對話）
  Future<void> _deleteCanvas(String canvasId) async {
    final canvas = _canvases.where((c) => c.id == canvasId).firstOrNull;
    if (canvas == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(context).surfaceElevated,
        title: Text('刪除畫布', style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,)),
        content: Text('確定要刪除「${canvas.title}」？\n相關對話也會一併刪除。',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: BridgeDSColors.of(context).textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('刪除', style: TextStyle(color: BridgeDSColors.of(context).accentRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // [小葵 2026-09-21 Blue 令] 專案回收桶——刪畫布前整包快照（保護傘）。
    // 五件套：metadata + 節點 + 綁定對話 + 門。刪錯專案要撈得回來。
    try {
      final nodes = await EntityGraphService.withSqliteCanvasStore(
        memoryStore: MemoryStore(),
        doorStore: ProjectDoorStore(),
        assetStore: DigitalAssetRegistryStore(),
      ).getCanvasNodes(canvasId: canvasId);
      ProjectDoor? door;
      if (canvas.projectDoorId != null) {
        final doors = await ProjectDoorStore().loadAll();
        door = doors
            .where((d) => d.id == canvas.projectDoorId)
            .firstOrNull;
      }
      await ProjectTrashStore.backup(
        canvasJson: canvas.toJson(),
        nodes: nodes,
        door: door,
        conversationId: canvas.conversationId,
      );
    } catch (e) {
      debugPrint('[專案回收桶] 備份失敗（不阻擋刪除主流程）: $e');
    }

    await CanvasStore.delete(canvasId);
    // [教練 Agent 2026-08-26 使用者 三刀之二] 刪畫布＝級聯刪節點——
    // 之前只刪清單記錄，節點（CanvasProps）留在 SharedPreferences 變殭屍。
    // 2026-08-26 事件：24 個死畫布累積 182 殭屍節點，
    // 4 個 imageGen 殭屍被跨畫布洩漏執行 → 28 張幽靈圖片燒光 OpenAI 額度。
    await EntityGraphService.withSqliteCanvasStore(
      memoryStore: MemoryStore(),
      doorStore: ProjectDoorStore(),
      assetStore: DigitalAssetRegistryStore(),
    ).clearCanvas(canvasId);
    if (canvas.conversationId != null) {
      await ConversationStore.delete(canvas.conversationId!);
    }
    // 一併刪除關聯的 ProjectDoor（避免孤兒門殘留）
    if (canvas.projectDoorId != null) {
      final doorStore = ProjectDoorStore();
      final doors = await doorStore.loadAll();
      final door = doors.where((d) => d.id == canvas.projectDoorId).firstOrNull;
      if (door != null) {
        await doorStore.deleteDoor(door.id);
      }
    }
    await _loadCanvases();
    await _loadConversations();

    // 清空當前畫布畫面和聊天
    _activeCanvasId = null;
    _currentConversationId = null;
    _workspaceKey.currentState?.clearWorkspace();

    // 如果還有其他畫布，切換到第一個
    if (_canvases.isNotEmpty) {
      await _switchCanvas(_canvases.first.id);
    } else {
      setState(() {});
    }
  }

  /// 複製畫布（建立副本）
  Future<void> _duplicateCanvas(String canvasId) async {
    final canvas = _canvases.where((c) => c.id == canvasId).firstOrNull;
    if (canvas == null) return;

    final companionId = CompanionStore().activeCompanion?.id;
    final conv = Conversation.createProjectCanvas(
      canvasId: '',
      title: '${canvas.title}（副本）',
      companionId: companionId,
    );
    await ConversationStore.save(conv);

    final newCanvas = await CanvasStore.create(
      title: '${canvas.title}（副本）',
      conversationId: conv.id,
    );

    final updatedConv = conv.copyWith(canvasId: newCanvas.id);
    await ConversationStore.save(updatedConv);

    await _loadCanvases();
    await _loadConversations();
    setState(() {
      _onTabChanged(1);
      _activeCanvasId = newCanvas.id;
      _currentConversationId = conv.id;
    });
    await ConversationStore.setCurrentId(conv.id);
    _workspaceKey.currentState?.loadCanvasById(newCanvas.id, clearCanvas: true);

    // 切換聊天對話
    if (_canvasChatController != null) {
      await _canvasChatController!.switchConversation(updatedConv);
    }
  }

  /// D11-6: 執行畫布計畫 — 透過 CanvasChatPanel 的 ChatController 觸發 Agent Loop
  Future<void> _executeCanvasPlan(List<String> stepTitles) async {
    final controller = _canvasChatController;
    if (controller == null) {
      debugPrint('[D11-6] CanvasChatController 未就緒');
      return;
    }

    // 組裝執行指令，透過 ChatController 發送
    final plan = stepTitles.asMap().entries.map((e) {
      return '${e.key + 1}. ${e.value}';
    }).join('\n');

    final message = '請執行以下畫布計畫，依序完成每個步驟，完成後回報結果：\n\n$plan';

    // ChatController.sendMessage 從 onGetMessageText callback 取文字
    // 先設定 controller 的 onGetMessageText 回傳執行指令
    final originalGetter = controller.onGetMessageText;
    controller.onGetMessageText = () => message;
    await controller.sendMessage();
    // 恢復原本的 getter
    controller.onGetMessageText = originalGetter;
  }

  /// D11-4: 匯入對話到畫布 — 選擇新建或既有畫布
  void _showImportToCanvasDialog(Conversation sourceConv) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(context).surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
          side: BorderSide(color: BridgeDSColors.of(context).borderDefault),
        ),
        title: Text('匯入到畫布', style: TierStyle.of(context, Tier.bodyPrimary).toTextStyle()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 新建畫布
            _importOption(
              icon: Icons.add_circle_outline,
              color: BridgeDSColors.of(context).accentGreen,
              title: '新建專案畫布',
              subtitle: '建立新畫布 + 對話 thread，\n對話總結寫成畫布節點',
              onTap: () {
                Navigator.pop(ctx);
                _importToNewCanvas(sourceConv);
              },
            ),
            SizedBox(height: 8),
            // 既有畫布
            if (_canvases.isNotEmpty)
              _importOption(
                icon: Icons.folder_open,
                color: BridgeDSColors.of(context).accentBlue,
                title: '匯入既有畫布',
                subtitle: '對話 append 到原畫布 thread，\n總結寫成新節點',
                onTap: () {
                  Navigator.pop(ctx);
                  _showExistingCanvasPicker(sourceConv);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _importOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary, fontWeight: FontWeight.w500)),
                  SizedBox(height: 0),
                  Text(subtitle, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// D11-4: 匯入到新畫布
  /// [教練 Agent 2026-07-24] 同時建立 ProjectDoor，三者綁定
  Future<void> _importToNewCanvas(Conversation sourceConv) async {
    final title = await _showTextInputDialog('新增專案', '輸入專案名稱');
    if (title == null || title.isEmpty) return;

    final companionId = CompanionStore().activeCompanion?.id;

    // 1. 建立專案門
    final door = ProjectDoor.create(
      title: title,
      sourceIntent: 'canvas',
    ).copyWith(status: 'active');
    await ProjectDoorStore().save(door);

    // 2. 建立專案畫布對話 thread — 綁定 projectDoorId
    final conv = Conversation.createProjectCanvas(
      canvasId: '',
      title: title,
      companionId: companionId,
      parentConversationId: sourceConv.id, // 串接來源對話
    ).copyWith(projectDoorId: door.id);
    await ConversationStore.save(conv);

    // 3. 建立畫布 — 綁定 conversationId + projectDoorId
    final canvas = await CanvasStore.create(
      title: title,
      conversationId: conv.id,
    );
    final canvasWithDoor = canvas.copyWith(projectDoorId: door.id);
    await CanvasStore.save(canvasWithDoor);

    // 4. 回填 canvasId
    final updatedConv = conv.copyWith(canvasId: canvasWithDoor.id);
    await ConversationStore.save(updatedConv);

    // 將來源對話的摘要寫成記憶 → 放到畫布
    await _createSummaryMemoryAndPlaceOnCanvas(sourceConv, canvasWithDoor.id);

    await _loadCanvases();
    await _loadConversations();

    setState(() {
      _onTabChanged(1);
      _activeCanvasId = canvasWithDoor.id;
      _currentConversationId = conv.id;
    });
    await ConversationStore.setCurrentId(conv.id);

    _addLog('已匯入到新畫布「$title」', _LogType.system);
  }

  /// B系列: 使用 Agent 產生的摘要匯入到新畫布（不再機械截取最後 10 則訊息）
  /// [教練 Agent 2026-07-24] 同時建立 ProjectDoor，三者綁定
  Future<void> _importToNewCanvasWithSummary(
    Conversation sourceConv,
    String agentSummary,
    String suggestedTitle,
  ) async {
    final title = await _showTextInputDialog(
      '新增專案',
      '輸入專案名稱',
      defaultValue: suggestedTitle,
    );
    if (title == null || title.isEmpty) return;

    final companionId = CompanionStore().activeCompanion?.id;

    // 1. 建立專案門
    final door = ProjectDoor.create(
      title: title,
      sourceIntent: 'canvas',
    ).copyWith(status: 'active');
    await ProjectDoorStore().save(door);

    // 2. 建立專案畫布對話 thread — 綁定 projectDoorId
    final conv = Conversation.createProjectCanvas(
      canvasId: '',
      title: title,
      companionId: companionId,
      parentConversationId: sourceConv.id,
    ).copyWith(projectDoorId: door.id);
    await ConversationStore.save(conv);

    // 3. 建立畫布 — 綁定 conversationId + projectDoorId
    final canvas = await CanvasStore.create(
      title: title,
      conversationId: conv.id,
    );
    final canvasWithDoor = canvas.copyWith(projectDoorId: door.id);
    await CanvasStore.save(canvasWithDoor);

    // 4. 回填 canvasId
    final updatedConv = conv.copyWith(canvasId: canvasWithDoor.id);
    await ConversationStore.save(updatedConv);

    // B系列: 使用 Agent 產生的摘要寫成記憶 → 放到畫布
    await _placeSummaryOnCanvas(agentSummary, sourceConv.title, canvasWithDoor.id);

    await _loadCanvases();
    await _loadConversations();

    setState(() {
      _onTabChanged(1);
      _activeCanvasId = canvasWithDoor.id;
      _currentConversationId = conv.id;
    });
    await ConversationStore.setCurrentId(conv.id);

    _addLog('已匯入到新畫布「$title」', _LogType.system);
  }
  void _showExistingCanvasPicker(Conversation sourceConv) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(context).surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
          side: BorderSide(color: BridgeDSColors.of(context).borderDefault),
        ),
        title: Text('選擇畫布', style: TierStyle.of(context, Tier.bodyPrimary).toTextStyle()),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _canvases.length,
            itemBuilder: (context, index) {
              final canvas = _canvases[index];
              return ListTile(
                leading: Icon(Icons.account_tree_outlined, color: BridgeDSColors.of(context).accentPurple, size: 20),
                title: Text(canvas.title, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,)),
                subtitle: Text(canvas.status.displayName,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,)),
                onTap: () {
                  Navigator.pop(ctx);
                  _importToExistingCanvas(sourceConv, canvas);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// D11-4: 匯入到既有畫布 — append 到原對話 thread
  Future<void> _importToExistingCanvas(Conversation sourceConv, CanvasMetadata canvas) async {
    if (canvas.conversationId == null) return;

    // 將來源對話的摘要寫成記憶 → 放到畫布
    await _createSummaryMemoryAndPlaceOnCanvas(sourceConv, canvas.id);

    await _loadCanvases();
    await _loadConversations();

    setState(() {
      _onTabChanged(1);
      _currentConversationId = canvas.conversationId;
    });
    await ConversationStore.setCurrentId(canvas.conversationId!);

    _addLog('已匯入到畫布「${canvas.title}」', _LogType.system);
  }

  /// D11-4: 從來源對話產生摘要記憶 → 放到畫布上
  Future<void> _createSummaryMemoryAndPlaceOnCanvas(Conversation sourceConv, String canvasId) async {
    // 簡易摘要：取最後 10 則訊息的文字，組成摘要
    final recentMessages = sourceConv.messages.length > 10
        ? sourceConv.messages.sublist(sourceConv.messages.length - 10)
        : sourceConv.messages;

    final summaryParts = recentMessages
        .where((m) => m.content.trim().isNotEmpty)
        .map((m) => '${m.role == 'user' ? '使用者' : 'Agent'}: ${m.content.length > 100 ? '${m.content.substring(0, 100)}...' : m.content}')
        .toList();

    if (summaryParts.isEmpty) return;

    final summary = '從對話「${sourceConv.title}」匯入：\n${summaryParts.join('\n')}';

    await _placeSummaryOnCanvas(summary, sourceConv.title, canvasId);
  }

  /// B系列: 使用 Agent 產生的摘要放到畫布上
  Future<void> _placeSummaryOnCanvas(String summary, String sourceTitle, String canvasId) async {
    final fullSummary = summary.startsWith('從對話') || summary.startsWith('從對話「')
        ? summary
        : '從對話「$sourceTitle」匯入：\n$summary';

    // 寫入大腦記憶
    final brain = BrainContainerService.instance;
    if (brain.isInitialized) {
      await brain.writeMemory(
        content: fullSummary,
        agent: 'canvas_import',
        tags: ['canvas_import', 'project_canvas'],
        importance: 4,
        speaker: MemorySpeaker.agent, // [出處戳] AI 摘要匯入=agent 產出（內容雖源自對話，摘要本身非使用者原話）
      );

      // 查最新記憶拿 ID → 放到畫布
      final recent = await brain.getAllMemories(limit: 1);
      if (recent.isNotEmpty) {
        final entityGraph = EntityGraphService.withSqliteCanvasStore(
          memoryStore: MemoryStore(),
          doorStore: ProjectDoorStore(),
          assetStore: DigitalAssetRegistryStore(),
        );
        await entityGraph.addToCanvas(recent.first.id, x: 100.0, y: 100.0);
      }
    }
  }

  /// [小葵 2026-09-21 Blue 令] 專案回收桶 UI——刪錯專案的撈回入口。
  /// 還原五件套：metadata 回 canvases.json、節點回 SQLite、
  /// 對話從 trash/ 救回、門重存。日期分組＋永久刪除警示同一般回收桶。
  Future<void> _showProjectTrashDialog() async {
    final snapshots = await ProjectTrashStore.listAll();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => _ProjectTrashDialog(
        snapshots: snapshots,
        onRestored: () async {
          await _loadCanvases();
          await _loadConversations();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  /// P4: 刪除對話
  Future<void> _deleteConversation(String id) async {
    await ConversationStore.delete(id);
    await _loadConversations();
    _addLog('對話已刪除', _LogType.system);
  }

  /// [小葵 2026-09-21] 回收桶——被刪對話的清單與還原（後悔藥 UI）。
  /// 刪除＝軟刪除進 trash/（ConversationStore.delete 已落地），
  /// 這裡只是把「看得到、救得回」的入口放在對話列表最底。
  /// [小葵 2026-09-21 Blue 令] ①統一回收桶：一般對話/畫布對話/全域對話
  /// （+未來手機版）刪除全部進這裡撈；②以刪除日期分組顯示；
  /// ③可單則永久刪除，先警示「刪除後無法恢復」由使用者自己決定。
  Future<void> _showTrashDialog() async {
    final trash = await ConversationStore.listTrashDetailed();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => _TrashDialog(trash: trash, onRestored: () async {
        await _loadConversations();
        if (mounted) setState(() {});
      }),
    );
  }

  /// P4-r2: 新增對話
  Future<void> _createNewConversation() async {
    final conv = await ConversationStore.createNew(title: '');
    await _loadConversations();
    setState(() => _currentConversationId = conv.id);
    await ConversationStore.setCurrentId(conv.id);
    _addLog('新對話已建立', _LogType.system);
  }

  /// [教練 Agent 2026-08-03] 從 DesktopChatPanel 內部建立新對話後通知的 callback。
  /// 從 ChatController 已新建的對話（可能是「+對話泡泡」或「延伸話題」產出），
  /// 同步左側 sidebar 的 `_conversations` 與 `_currentConversationId`。
  Future<void> _syncNewConversationFromController() async {
    final controller = _desktopChatController;
    final newConv = controller?.currentConversation;
    if (newConv == null) return;
    await _loadConversations();
    if (mounted) {
      setState(() => _currentConversationId = newConv.id);
    }
    await ConversationStore.setCurrentId(newConv.id);
    _addLog(
      newConv.title.isEmpty ? '新對話已建立' : '新對話已建立：${newConv.title}',
      _LogType.system,
    );
  }

  /// P4-r2: 切換對話
  Future<void> _switchConversation(String id) async {
    setState(() => _currentConversationId = id);
    await ConversationStore.setCurrentId(id);
  }

  /// D11: 通用文字輸入對話框
  Future<String?> _showTextInputDialog(String title, String hint, {String? defaultValue}) {
    final controller = TextEditingController(text: defaultValue ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(context).surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
          side: BorderSide(color: BridgeDSColors.of(context).borderDefault),
        ),
        title: Text(title, style: TierStyle.of(context, Tier.bodyPrimary).toTextStyle()),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: hint,
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 06),
          ),
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('取消', style: TextStyle(color: BridgeDSColors.of(context).textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text('確定', style: TextStyle(color: BridgeDSColors.of(context).accentBlue)),
          ),
        ],
      ),
    );
  }

  /// P4-r2: 重新命名對話（彈出 dialog，BridgeDS 暗色風格）
  void _showRenameDialog(String id, String currentTitle) {
     final controller = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(context).surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
          side: BorderSide(color: BridgeDSColors.of(context).borderDefault),
        ),
        title: Text(
          '修改對話標題',
          style: TierStyle.of(context, Tier.bodyPrimary).toTextStyle(),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
          decoration: InputDecoration(
            hintText: '輸入新標題',
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 06),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: BridgeDSColors.of(context).textTertiary,
            ),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                _renameConversation(id, newTitle);
              }
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(
              foregroundColor: BridgeDSColors.of(context).accentBlue,
            ),
            child: const Text('確認'),
          ),
        ],
      ),
    );
  }

  /// P4-r2: 重新命名對話
  Future<void> _renameConversation(String id, String newTitle) async {
    final conv = await ConversationStore.getById(id);
    if (conv == null) return;
    final updated = Conversation(
      id: conv.id,
      title: newTitle,
      messages: conv.messages,
      companionId: conv.companionId,
      projectDoorId: conv.projectDoorId,
      createdAt: conv.createdAt,
      updatedAt: DateTime.now(),
    );
    await ConversationStore.save(updated);
    await _loadConversations();
    _addLog('對話標題已更新', _LogType.system);
  }

  Future<void> _loadBrainStats() async {
    try {
      final brain = BrainContainerService.instance;
      if (!brain.isInitialized) {
        // 等 initialize 完成，最多等 3 秒
        for (var i = 0; i < 30; i++) {
          if (brain.isInitialized) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      if (!brain.isInitialized) {
        // macOS desktop 上 sqlite-vec 載不入，BrainContainer 初始化會失敗
        // 不轉圈——標記為失敗，UI 顯示原因而非永遠 loading
        if (mounted) {
          setState(() {
            _brainInitialized = false;
            _brainInitFailed = true;
          });
        }
        _addLog('大腦容器初始化失敗（schema migration 或 sqlite-vec 載入問題）',
            _LogType.error);
        return;
      }
      final stats = await brain.getRoomStats();
      if (mounted) {
        setState(() {
          _brainInitialized = true;
          _brainInitFailed = false;
          _brainModelAvailable = brain.isModelAvailable;
          _roomStats = stats;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _brainInitialized = false;
          _brainInitFailed = true;
        });
      }
      _addLog('讀取大腦統計失敗：$e', _LogType.error);
    }
  }

  /// [教練 Agent S20/S21] 載入 Agent Loop feature flag
  Future<void> _loadAgentLoopFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _agentLoopEnabled = prefs.getBool('agent_loop_enabled') ?? true;
          _screenCaptureEnabled = prefs.getBool('screen_capture_enabled') ?? false;
        });
      }
    } catch (_) {}
  }

  /// [教練 Agent B4] 切換螢幕感知開關
  Future<void> _toggleScreenCapture(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('screen_capture_enabled', value);
    setState(() => _screenCaptureEnabled = value);
    _addLog(
      value ? '螢幕感知已啟用（Agent 可截取指定視窗）' : '螢幕感知已關閉',
      _LogType.system,
    );
  }

  /// [教練 Agent S20/S21] 切換 Agent Loop 開關
  Future<void> _toggleAgentLoop(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('agent_loop_enabled', value);
    setState(() => _agentLoopEnabled = value);
    _addLog(
      value ? 'Agent Loop 已啟用（多輪工具呼叫）' : 'Agent Loop 已關閉',
      _LogType.system,
    );
  }



  /// [教練 Agent 2026-07-31] 啟動時自動刷新所有已鎖定 provider 的模型
  /// 在背景執行，不阻擋 UI
  Future<void> _autoRefreshAllModels() async {
    const providers = ['kimi', 'openai', 'glm', 'minimax', 'claude', 'gemini'];
    int updated = 0;
    for (final p in providers) {
      try {
        final token = await StorageService.getToken(provider: p);
        if (token == null || token.isEmpty) continue;

        // Local helper for default URLs
        String defaultUrl(String provider) {
          switch (provider) {
            case 'openai': return 'https://api.openai.com/v1';
            case 'kimi': return 'https://api.moonshot.cn/v1';
            case 'minimax': return 'https://api.minimax.io/v1';
            case 'claude': return 'https://api.anthropic.com/v1';
            case 'gemini': return 'https://generativelanguage.googleapis.com/v1beta/openai';
            case 'glm': return 'https://open.bigmodel.cn/api/paas/v4';
            default: return '';
          }
        }

        final baseUrl = defaultUrl(p);
        if (await ApiService.refreshProviderModel(
          provider: p,
          baseUrl: baseUrl,
          token: token,
        )) {
          updated++;
        }
        // 靜默更新，不打擾使用者
      } catch (e) {
        debugPrint('[Settings] 自動刷新 $p 模型失敗: $e');
      }
    }
    if (updated > 0) {
      debugPrint('[Settings] 自動刷新完成，$updated 個 provider 模型已更新');
    }
  }

  void _copyPairingCode() {
    if (_pairingCode.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _pairingCode));
    _addLog('配對碼已複製到剪貼簿', _LogType.system);
  }

  // ═══════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // [D002 2026-08-10] 捕獲全域 Overlay 供安全確認 dialog 使用
    // 只捕獲一次，避免每次 rebuild 都觸發 setState
    if (d002Overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        d002Overlay = Overlay.of(context);
        debugPrint('[D002] Overlay 已捕獲: $d002Overlay');
      });
    }
    // [v280 Blue 令 2026-09-06] 螢幕保護模式刪除——overlay 拔除
    // （idle 計時仍在但無 listener；Swift 版 v272 已停用=雙保險）
    return RepaintBoundary(
      key: _selfCaptureKey,
      child: Scaffold(
      backgroundColor: BridgeDSColors.of(context).canvas,
      body: Stack(
        children: [
          Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: AnimatedSwitcher(
              duration: BridgeDS.durationSlow,
              switchInCurve: BridgeDS.transitionCanvas,
              switchOutCurve: BridgeDS.transitionSlide,
              transitionBuilder: (child, animation) {
                // [Phase 0 2026-07-17] Miro 無限畫布風格轉場
                // 進場：scale + fade + slide（從右下微滑入）
                // 退場：fade + slide（往左上微滑出）
                final isIn = animation.value < 0.5;
                final fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
                    .animate(CurvedAnimation(
                        parent: animation, curve: BridgeDS.transitionCanvas));
                final scaleAnim = Tween<double>(begin: 0.94, end: 1.0)
                    .animate(CurvedAnimation(
                        parent: animation, curve: BridgeDS.transitionCanvas));
                final slideAnim = Tween<Offset>(
                  begin: isIn ? const Offset(0.03, 0.03) : const Offset(-0.03, -0.03),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                    parent: animation, curve: BridgeDS.transitionCanvas));
                return FadeTransition(
                  opacity: fadeAnim,
                  child: SlideTransition(
                    position: slideAnim,
                    child: ScaleTransition(
                      scale: scaleAnim,
                      alignment: Alignment.center,
                      child: child,
                    ),
                  ),
                );
              },
              child: KeyedSubtree(
              // [v206 畫布失蹤終結令] X 光+GlobalKey 衝突堆疊定罪：
              // 切頁動畫期間 AnimatedSwitcher 保留新舊兩份 child，
              // 兩份都含 CanvasV2Workspace(同 _workspaceKey) →
              // GlobalKey 衝突 → workspace 被丟棄 → 畫布永遠消失。
              // 修：Stack 包固定 key 的 KeyedSubtree，並關閉過場雙份。
              key: const ValueKey('main_switcher_child'),
              child: Stack(children: [
                // 保活 Stack 開始
                // [教練 Agent 2026-08-16 使用者要求 2] 畫布 tab 永遠保活（Offstage）——
                // agent 在畫布做事時切到別頁不會 dispose workspace、不會中斷任務。
                // [小葵 2026-10-05 TickerMode 開火] Offstage 只是不畫，不會停 ticker——
                // 保活 tab 裡的 repeat 動畫（node halo 等）在別頁時照樣每幀震動 vsync
                // = 62% CPU 空轉的元兇。TickerMode(enabled:false) 一行讓不可見 tab 的
                // 所有 AnimationController 靜音。可見時自動恢復，零行為改變。
                Offstage(
                  offstage: !(_isHomepage == false &&
                      _isCompanionHall == false &&
                      _isTrainingPage == false && // [Blue 抓包] 訓練頁時 canvas 不該在場
                      _activeCanvasIndex == 1),
                  child: TickerMode(
                    enabled: (_isHomepage == false &&
                        _isCompanionHall == false &&
                        _isTrainingPage == false &&
                        _activeCanvasIndex == 1),
                    child: KeyedSubtree(
                      key: const ValueKey('canvas_tab'),
                      child: _buildCanvasTabLayout(),
                    ),
                  ),
                ),
                // [小葵 2026-09-01 Blue 抓包] 對話 tab 同款保活——
                // Agent 在對話頁工作（LLM 回覆/工具執行中）切到系統頁再切回來，
                // 舊結構 widget dispose → 回覆腰斬。現在對話頁常駐 Offstage，
                // 切頁只是看不見，controller 與任務照跑。
                // [v207 畫布失蹤終結令 2] 根因：chat_tab 保活的
                // _buildChatTabLayout→_buildCanvasArea 在 index==1 時
                // 也會 build 一份 CanvasV2Workspace（同 _workspaceKey）
                // → GlobalKey 衝突 → 兩份都被丟 → 畫布消失。
                // 修：index==1 時 chat_tab 只留空殼（不 build chat layout）。
                Offstage(
                  offstage: !(_isHomepage == false &&
                      _isCompanionHall == false &&
                      _isTrainingPage == false && // [Blue 抓包] 訓練頁時 chat 不該在場
                      _activeCanvasIndex == 0),
                  // [小葵 2026-10-05 TickerMode 開火] 同 canvas tab——不可見時停 ticker
                  child: TickerMode(
                    enabled: (_isHomepage == false &&
                        _isCompanionHall == false &&
                        _isTrainingPage == false &&
                        _activeCanvasIndex == 0),
                    child: KeyedSubtree(
                      key: const ValueKey('chat_tab'),
                      child: _activeCanvasIndex == 1
                          ? const SizedBox.shrink()
                          : _buildChatTabLayout(),
                    ),
                  ),
                ),
                if (_isHomepage)
                  KeyedSubtree(
                    key: const ValueKey('homepage'),
                    child: _buildHomepage(),
                  )
                else if (_isCompanionHall)
                  KeyedSubtree(
                    key: ValueKey('companion_${_activeCompanionSubPage ?? "hall"}_${_activeCompanionId ?? "none"}'),
                    child: _buildCompanionHallOrSubPage(),
                  )
                else if (_isTrainingPage)
                  KeyedSubtree(
                    key: const ValueKey('training'),
                    child: TrainingScreen(
                      onBack: () => setState(() {
                        _isTrainingPage = false;
                        _isHomepage = true;
                      }),
                    ),
                  )
                else if (_activeCanvasIndex != 1 && _activeCanvasIndex != 0)
                  KeyedSubtree(
                    key: ValueKey('tab_$_activeCanvasIndex'),
                    child: _buildChatTabLayout(),
                  ),
              ]),
              ),  // [v206] KeyedSubtree 閉合
            ),
          ),
          _buildStatusBar(),
        ],
      ),
          // [教練 Agent 2026-07-31] 移除全域浮動進度條
          // 進度只顯示在向量資料庫頁面（vault_screen.dart 內）

          // [教練 Agent 2026-08-11] 浮動夥伴已改為 NSPanel 桌面懸浮窗
        ],
      ), // Stack 閉合（body）
      ), // [小葵 2026-09-01] Scaffold 閉合（= overlay 的 child 結束）
    ); // [小葵 2026-09-01] RepaintBoundary 閉合 [v280 overlay 已拔]
  }

  /// [小葵 2026-09-01] 對話 tab 佈局（保活版共用）——sidebar | canvasArea
  /// [W4.7 Blue 令 2026-10-09] 分割線改可拖曳（紫色把手）——
  /// 對話頁與畫布頁同一種手感
  Widget _buildChatTabLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSidebar(),
        _buildDragHandle(
          onDrag: (delta) {
            setState(() {
              _chatSidebarWidth = (_chatSidebarWidth + delta).clamp(200.0, 460.0);
            });
          },
        ),
        Expanded(child: _buildCanvasArea()),
        // P10-a: 右側資訊欄可收合，預設隱藏
        if (_contextPanelVisible) ...[
          BridgeGlowDivider(),
          _buildContextPanel(),
        ],
      ],
    );
  }

  /// 畫布 tab 專屬佈局 — toolbar | sidebar | drag | canvas+chat
  /// [教練 Agent 2026-08-16 使用者 提案] 左右兩大區塊可折疊——
  /// sidebar 收到左邊、對話框收到右邊，只留窄軌＋展開鈕。
  Widget _buildCanvasTabLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 工具列（最左側）— [教練 Agent 2026-07-23] AnimatedBuilder 讓 undo/redo 按鈕即時更新
        _buildCanvasToolbar(),
        // Sidebar（資產庫）— 折疊時只留 32px 窄軌貼左
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.centerLeft,
          child: _canvasSidebarCollapsed
              ? _buildCollapsedRail(
                  side: _RailSide.left,
                  icon: Icons.chevron_right,
                  tooltip: '展開資產庫',
                  onTap: () => setState(() => _canvasSidebarCollapsed = false),
                )
              : _buildCanvasSidebar(),
        ),
        // Drag handle — 調整 sidebar 寬度（折疊時隱藏）
        if (!_canvasSidebarCollapsed)
          _buildDragHandle(
            onDrag: (delta) {
              setState(() {
                _canvasSidebarWidth = (_canvasSidebarWidth + delta).clamp(200.0, 500.0);
              });
            },
          ),
        // 畫布主體 + 對話框
        Expanded(child: _buildCanvasArea()),
      ],
    );
  }

  /// 折疊後的窄軌（32px）——貼著螢幕邊緣，點擊展開
  Widget _buildCollapsedRail({
    required _RailSide side,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final ds = BridgeDSColors.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 400),
          child: Container(
            width: 32,
            color: ds.canvas,
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: ds.textMuted),
          ),
        ),
      ),
    );
  }

  /// [教練 Agent 2026-07-23] 畫布左側工具列
  /// 用 postFrameCallback 確保 workspace state 存在後接上 controller listenable
  Widget _buildCanvasToolbar() {
    // 如果 currentState 還沒好，先建一個空 toolbar，下一幀再接上
    final ws = _workspaceKey.currentState;
    // [小葵 2026-10-05 無限 build 迴圈根修] ws==null 的 retry 只在「畫布 tab 真的
    // 活躍」時排——保活 Offstage 的 canvas_tab 在首頁/其他頁也會 build 本方法，
    // 而 workspace（index==1 才掛）永遠不存在 → 舊邏輯每幀排 postFrame setState
    // → root dirty → rebuild → 又 ws==null → 377 BUILD/s 風暴（~13 萬 widget
    // builds/s，CPU 65-100%）。非畫布頁直接啞火，零行為改變（畫面上本來就看不到）。
    final canvasTabActive = !_isHomepage && !_isCompanionHall && !_isTrainingPage && _activeCanvasIndex == 1;
    if (ws == null) {
      if (canvasTabActive) {
        // schedule rebuild for next frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
      return const SizedBox(width: 52);
    }
    return ListenableBuilder(
      listenable: ws.controller,
      builder: (context, _) {
        return CanvasToolbar(
          activeTool: _canvasTool,
          onToolChanged: (tool) {
            setState(() => _canvasTool = tool);
            ws.handleToolChanged(tool);
          },
          onAddNode: () => ws.addNodeAtCenter(),
          onConnectMode: () => ws.setTool(CanvasTool2.connect),
          onAnnotation: () => ws.setTool(CanvasTool2.select),
          onDoodle: () => ws.toggleDoodle(),
          onToggleDoodleVisible: () {
            ws.toggleDoodleVisible();
            setState(() => _canvasDoodleVisible = !_canvasDoodleVisible);
          },
          onScreenshot: () => ws.handleScreenshot(),
          onImport: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('匯入功能開發中'), duration: Duration(seconds: 2)),
            );
          },
          onExport: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('匯出功能開發中'), duration: Duration(seconds: 2)),
            );
          },
          doodleVisible: _canvasDoodleVisible,
          onClear: () => ws.showClearCanvasConfirm(context),
          onUndo: ws.controller.canUndo ? () => ws.controller.undo() : null,
          onRedo: ws.controller.canRedo ? () => ws.controller.redo() : null,
          canUndo: ws.controller.canUndo,
          canRedo: ws.controller.canRedo,
        );
      },
    );
  }

  /// 可拖移的分隔條——[W4.7c Blue 令 2026-10-09] 全 App 統一：
  /// 常態灰色細線；抓取拖曳中整條變紫發光（PurpleDragHandle 共用元件）。
  Widget _buildDragHandle({required void Function(double delta) onDrag}) {
    final ds = BridgeDSColors.of(context);
    return PurpleDragHandle(
      color: ds.accentPurple,
      trackColor: ds.borderSubtle,
      onDrag: onDrag,
    );
  }

  // ── TopBar (64px) ──────────────────────────────────
  // 文字層級：BRIDGE = L4 Heading-S / DESKTOP = L10 Label

  Widget _buildTopBar() {
    // 6 tab：對話 / 畫布 / 專案 / 大腦 / 向量資料庫 / 系統
    // [教練 Agent 2026-07-25] 「資料庫」正名為「向量資料庫」
    // [v262 Blue 重構令 2026-09-04] 大腦 tab 移除——星系圖譜全面改網頁版
    // （Chrome 獨立視窗），入口移右側按鈕群「大腦圖譜」
    final navItems = ['對話', '畫布', '專案', '向量資料庫', '系統'];
    final navIcons = [
      Icons.chat_bubble_outline,
      Icons.account_tree_outlined,
      Icons.door_sliding_outlined,
      Icons.auto_awesome_motion_outlined, // 向量資料庫
      Icons.settings_outlined,
    ];

    // [Blue 腦頁沉浸令 2026-09-01] 大腦頁時頂欄透明——星系直達螢幕頂，
    // Logo 與選單浮在星空上（其他頁面維持原背景）
    // [v262] 大腦 tab 已除——頂欄永遠不透明（沉浸模式隨嵌入式星系退役）
    return Container(
      height: BridgeDS.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceLG),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas,
        border: Border(
          bottom: BorderSide(
            color: BridgeDSColors.of(context).borderSubtle,
            width: 1,
          ),
        ),
      ),
      child: _TopBarAutoFit(
        child: Row(
        children: [
          // Logo — 點擊回首頁
          GestureDetector(
            onTap: () => setState(() {
              _isHomepage = true;
              _isCompanionHall = false;
              _isTrainingPage = false; // [Blue 抓包] Logo 回首頁也要離開訓練頁
            }),
            child: Tooltip(
              message: '回到首頁',
              child: Row(
                children: [
                  Icon(Icons.hub, color: BridgeDSColors.of(context).accentPurple, size: 22),
                  SizedBox(width: 8),
                  SelectableText('BRIDGE', style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(
                    fontFamily: BridgeDS.fontDisplay,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 2,
                    fontSize: 18,
                  )),
                  SizedBox(width: 8),
                  SelectableText('DESKTOP', style: BridgeDSColors.of(context).labelMono.copyWith(
                    color: BridgeDSColors.of(context).textMuted,
                    fontSize: 14,
                  )),
                ],
              ),
            ),
          ),
          const SizedBox(width: BridgeDS.spaceLG), // [Blue 開光 2026-10-05] 頂列太擠——收窄

          // Canvas Nav — 5 tab
          ...List.generate(navItems.length, (i) {
            final active = !_isHomepage && !_isCompanionHall &&
                _activeCanvasIndex == i &&
                (i != 5 || _activeSystemPage == null);
            return Padding(
              padding: const EdgeInsets.only(right: 5),
              child: BridgeChip(
                label: navItems[i],
                icon: navIcons[i],
                active: active,
                onTap: () => setState(() {
                  _isHomepage = false;
                  _isCompanionHall = false;
                  _isTrainingPage = false; // [Blue 抓包] 幽靈疊層——nav 統一離開訓練頁
                  _onTabChanged(i);
                  if (i != 5) {
                    _activeSystemPage = null;
                  }
                }),
              ),
            );
          }),

          Spacer(),

          // [v262 Blue 重構令] 大腦圖譜按鈕——開網頁版獨立視窗（絲滑保證）
          Tooltip(
            message: '開啟獨立視窗',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: BridgeChip(
                label: '大腦圖譜',
                icon: Icons.psychology_outlined,
                active: false,
                onTap: _openBrainGalaxyWindow,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // [收據搜尋 RC2.5 2026-09-08] 頂部新按鈕——全局搜尋
          // （一個框搜對話/記憶/資產/任務，結果是空間座標）
          Tooltip(
            message: '全局搜尋（Cmd+Shift+F）',
            child: BridgeChip(
              label: '搜尋',
              icon: Icons.search,
              active: false,
              onTap: _openReceiptsSearch,
            ),
          ),
          const SizedBox(width: 6),

          // [羅盤 2026-09-06] 頂部新按鈕——羅盤系統（人機共視：器官地圖 + 規則中心）
          Tooltip(
            message: '開啟羅盤系統（器官地圖 + 規則中心）',
            child: BridgeChip(
              label: '羅盤',
              icon: Icons.explore_outlined,
              active: !_isHomepage && !_isCompanionHall &&
                  _activeCanvasIndex == 4 && _activeSystemPage == 'compass',
              onTap: () => setState(() {
                _isHomepage = false;
                _isCompanionHall = false;
                _activeCanvasIndex = 4; // 系統 tab
                _activeSystemPage = 'compass';
              }),
            ),
          ),
          const SizedBox(width: 8),

          // [Blue 令 2026-10-05] 本地模型開關——左鍵：開/關；右鍵：設定（閒置自動卸載）
          _buildLocalModelChip(),
          const SizedBox(width: 6),

          // [教練 Agent 2026-08-11] 懸浮窗開關按鈕
          Tooltip(
            message: '開啟/關閉懸浮夥伴視窗',
            child: BridgeChip(
              label: '懸浮窗',
              icon: Icons.picture_in_picture_alt_outlined,
              active: false,
              onTap: () {
                const shell = MacosDesktopShellChannel();
                shell.snapshot().then((snap) {
                  if (snap?.visible == true) {
                    shell.lifecycle('hide');
                  } else {
                    shell.lifecycle('show');
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          // [v262 Blue 令] 順序調整：大腦圖譜→懸浮窗→深色/淺色→API 監視器
          // [教練 Agent 2026-08-04] Phase E+ v1.1：主題輪播按鈕（取代原本的深淺切換）
          // 按一下切到下一個主題（內建 dark/light + 已安裝的社群主題包）
          ListenableBuilder(
            listenable: ThemeProvider.instance,
            builder: (context, _) {
              final activePack = ThemeProvider.instance.activePack;
              final packs = ThemeProvider.instance.installedPacks;
              final idx = packs.indexWhere((p) => p.id == (activePack?.id ?? ''));
              final isDark = ThemeProvider.instance.activePack?.id.contains('dark') ?? false;
              return Tooltip(
                message: activePack == null
                    ? '切換主題'
                    : '${activePack.name} (${idx + 1}/${packs.length}) — 點擊切換下一個',
                child: BridgeChip(
                  label: isDark ? '深色' : '淺色',
                  icon: Icons.palette_outlined,
                  active: false,
                  onTap: () => ThemeProvider.instance.cycleToNext(),
                ),
              );
            },
          ),
          const SizedBox(width: 10),

          // [教練 Agent 2026-07-29] API 額度儀表板（取代原本的資訊欄 + Gateway 燈號）
          // Gateway 燈號已移至左下角，這裡留給 API 儀表板
          const ApiUsageDashboard(),
        ],
      ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 首頁 — Home Page
  // ═══════════════════════════════════════════════════

  Widget _buildHomepage() {
    final companions = CompanionStore().all;
    final activeCompanion = CompanionStore().activeCompanion;

    return Container(
      color: BridgeDSColors.of(context).canvas,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(BridgeDS.spaceXXL),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 歡迎語 ──
                Text(
                  activeCompanion != null ? '歡迎回來' : '歡迎來到 Bridge',
                  style: TierStyle.of(context, Tier.appDisplayLarge).toTextStyle().copyWith(
                    color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                // ── 狀態列 ──
                Row(
                  children: [
                    BridgePulseDot(
                      color: BridgeDSColors.of(context).accentGreen,
                      size: 8,
                      active: true,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '系統運行中',
                      style: BridgeDSColors.of(context).caption.copyWith(color: BridgeDSColors.of(context).textSecondary),
                    ),
                    SizedBox(width: 16),
                    if (activeCompanion != null) ...[
                      Text(
                        '· 目前夥伴：${activeCompanion.name}',
                        style: BridgeDSColors.of(context).caption.copyWith(color: BridgeDSColors.of(context).textTertiary),
                      ),
                    ],
                    Spacer(),
                    Text(
                      '${companions.length} 位夥伴',
                      style: BridgeDSColors.of(context).caption.copyWith(color: BridgeDSColors.of(context).textTertiary),
                    ),
                  ],
                ),
                SizedBox(height: BridgeDS.spaceXL),

                // ── 功能格網 ──
                LayoutBuilder(
                  builder: (context, constraints) {
                    // 響應式：寬度 >800 → 4 欄，>500 → 3 欄，否則 2 欄
                    int columns = 2;
                    if (constraints.maxWidth > 800) columns = 4;
                    else if (constraints.maxWidth > 500) columns = 3;
                    final spacing = BridgeDS.spaceMD;
                    final tileW = (constraints.maxWidth - spacing * (columns - 1)) / columns;
                    final tileH = tileW * 0.95;

                    final tiles = <_HomeTile>[];

                    // ── 功能區 ──
                    tiles.add(_HomeTile(
                      icon: Icons.auto_awesome,
                      iconColor: BridgeDSColors.of(context).accentMiro,
                      title: '召喚夥伴',
                      subtitle: '創造新的 AI 夥伴',
                      onTap: () => context.go('/desktop-summon'),
                      isPrimary: true, // [改善3] 主操作突出
                    ));
                    tiles.add(_HomeTile(
                      icon: Icons.group_outlined,
                      iconColor: BridgeDSColors.of(context).accentMiro,
                      title: '夥伴館',
                      subtitle: '${companions.length} 位夥伴在這裡',
                      onTap: () => setState(() {
                        _isHomepage = false;
                        _isCompanionHall = true;
                      }),
                    ));
                    // [Blue 拍板 2026-09-12] 訓練AI夥伴——唯一入口在首頁
                    tiles.add(_HomeTile(
                      icon: Icons.school_outlined,
                      iconColor: BridgeDSColors.of(context).accentPurple,
                      title: '訓練AI夥伴',
                      subtitle: '你做一遍，夥伴學會代操作',
                      onTap: () => setState(() {
                        _isHomepage = false;
                        _isCompanionHall = false;
                        _isTrainingPage = true;
                      }),
                    ));
                    tiles.add(_HomeTile(
                      icon: Icons.chat_bubble_outline,
                      iconColor: BridgeDSColors.of(context).accentBlue,
                      title: '對話',
                      subtitle: '與夥伴聊天',
                      onTap: () => setState(() {
                        _isHomepage = false;
                        _isCompanionHall = false;
                        _onTabChanged(0);
                      }),
                    ));
                    tiles.add(_HomeTile(
                      icon: Icons.account_tree_outlined,
                      iconColor: BridgeDSColors.of(context).accentGreen,
                      title: '畫布',
                      subtitle: '視覺化思考',
                      onTap: () => setState(() {
                        _isHomepage = false;
                        _isCompanionHall = false;
                        _onTabChanged(1);
                      }),
                    ));
                    tiles.add(_HomeTile(
                      icon: Icons.psychology_outlined,
                      iconColor: BridgeDSColors.of(context).accentPurple,
                      title: '大腦圖譜',
                      subtitle: '獨立視窗開啟 · 網頁版絲滑',
                      onTap: () {
                        setState(() {
                          _isHomepage = false;
                          _isCompanionHall = false;
                        });
                        _openBrainGalaxyWindow(); // [v262]
                      },
                    ));
                    tiles.add(_HomeTile(
                      icon: Icons.settings_outlined,
                      iconColor: BridgeDSColors.of(context).textSecondary,
                      title: '系統',
                      subtitle: '設定與管理',
                      onTap: () => setState(() {
                        _isHomepage = false;
                        _isCompanionHall = false;
                        _onTabChanged(4);
                      }),
                    ));

                    // ── [無限插槽 C2 2026-10-06 移植] 插槽卡（spec：社群卡旁）──
                    // 有插槽：即時統計（N 運行中・M 已停用）；空：教學式引導。
                    // [Blue 2026-10-06 抓包修復] 空狀態點卡 = 「試一個範例」——
                    // prefill 必須真的帶 sampleRepoUrl（原移植漏帶＝空字串，
                    // 進管理頁後對話框是空的，使用者不知從何開始）。
                    final _slotReg = SlotRegistry.instance;
                    final _slotRunning = _slotReg.runningCount;
                    final _slotDisabled = _slotReg.disabledCount;
                    final _hasSlots = _slotRunning + _slotDisabled > 0;
                    tiles.add(_HomeTile(
                      icon: Icons.extension_outlined,
                      iconColor: BridgeDSColors.of(context).accentBlue,
                      title: '插槽',
                      subtitle: _hasSlots
                          ? '$_slotRunning 運行中・$_slotDisabled 已停用'
                          : '貼上 GitHub 連結，讓開源程式住進來',
                      onTap: () => context.go(_hasSlots
                          ? '/slots'
                          : '/slots?prefill=${Uri.encodeComponent(SlotRegistry.sampleRepoUrl)}'),
                    ));

                    // ── 佔位區（未來功能）──
                    tiles.add(_HomeTile.placeholder(
                      icon: Icons.campaign_outlined,
                      title: '社群動態',
                      subtitle: '即將上線',
                    ));
                    tiles.add(_HomeTile.placeholder(
                      icon: Icons.inventory_2_outlined,
                      title: '資產包',
                      subtitle: '即將上線',
                    ));
                    tiles.add(_HomeTile.placeholder(
                      icon: Icons.storefront_outlined,
                      title: '市集',
                      subtitle: '即將上線',
                    ));
                    tiles.add(_HomeTile.placeholder(
                      icon: Icons.school_outlined,
                      title: '學習',
                      subtitle: '即將上線',
                    ));

                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: tiles.map((t) {
                        return SizedBox(
                          width: tileW,
                          height: tileH,
                          child: _buildHomeTile(t),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTile(_HomeTile tile) {
    final isPlaceholder = tile.onTap == null;
    final isPrimary = tile.isPrimary;
    return BridgeCard(
      padding: const EdgeInsets.all(BridgeDS.spaceLG),
      isBrain: isPrimary, // [改善5] 主操作用邊框突出（複用 isBrain 機制）
      onTap: tile.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isPlaceholder
                  ? BridgeDSColors.of(context).textMuted.withValues(alpha: 0.08)
                  : tile.iconColor.withValues(alpha: isPrimary ? 0.20 : 0.12), // [改善5] 主操作 icon 背景更亮
              borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
            ),
            child: Icon(
              tile.icon,
              color: isPlaceholder ? BridgeDSColors.of(context).textMuted : tile.iconColor,
              size: 24,
            ),
          ),
          // Text
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tile.title,
                style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(
                  color: isPlaceholder ? BridgeDSColors.of(context).textMuted : BridgeDSColors.of(context).textPrimary,
                  fontWeight: isPlaceholder ? FontWeight.w400 : FontWeight.w600, // [改善3] 標題 SemiBold
                ),
              ),
              SizedBox(height: 4), // [改善3] 間距 8→4
              Text(
                tile.subtitle,
                style: BridgeDSColors.of(context).caption.copyWith(
                  fontSize: 14,
                  color: isPlaceholder ? BridgeDSColors.of(context).textQuaternary : BridgeDSColors.of(context).textTertiary, // [改善3] 對比度
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 夥伴館 — Companion Hall（桌面深色版）
  // ═══════════════════════════════════════════════════

  Widget _buildCompanionHall() {
    final companions = CompanionStore().all;
    final activeId = CompanionStore().activeCompanionId;

    return Container(
      color: BridgeDSColors.of(context).canvas,
      child: Column(
        children: [
          // 標題列
          Container(
            padding: const EdgeInsets.all(BridgeDS.spaceLG),
            child: Row(
              children: [
                Semantics(
                  label: '回到首頁',
                  button: true,
                  child: IconButton(
                    onPressed: () => setState(() {
                      _isHomepage = true;
                      _isCompanionHall = false;
                    }),
                    icon: const Icon(Icons.arrow_back, size: 20),
                    color: BridgeDSColors.of(context).textSecondary,
                    tooltip: '回到首頁',
                  ),
                ),
                SizedBox(width: BridgeDS.spaceSM),
                Icon(Icons.group_outlined, color: BridgeDSColors.of(context).accentPurple, size: 24),
                SizedBox(width: BridgeDS.spaceMD),
                Text('夥伴館', style: TierStyle.of(context, Tier.appDisplayLarge).toTextStyle()),
                Spacer(),
                BridgeChip(
                  label: '召喚新夥伴',
                  icon: Icons.add_rounded,
                  active: false,
                  onTap: () => context.go('/desktop-summon'),
                ),
              ],
            ),
          ),
          BridgeGlowDivider(vertical: false),
          // 夥伴列表
          Expanded(
            child: companions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: BridgeDSColors.of(context).surfaceElevated,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.person_add_outlined, size: 36, color: BridgeDSColors.of(context).accentPurple),
                        ),
                        SizedBox(height: BridgeDS.spaceLG),
                        Text('還沒有夥伴', style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary)),
                        SizedBox(height: BridgeDS.spaceSM),
                        Text('召喚你的第一位 AI 夥伴吧', style: BridgeDSColors.of(context).body.copyWith(color: BridgeDSColors.of(context).textTertiary)),
                        SizedBox(height: BridgeDS.spaceLG),
                        FilledButton.icon(
                          onPressed: () => context.go('/desktop-summon'),
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('開始召喚'),
                          style: FilledButton.styleFrom(
                            backgroundColor: BridgeDSColors.of(context).accentPurple,
                            foregroundColor: BridgeDSColors.of(context).textPrimary,
                            minimumSize: const Size(0, 44),
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(BridgeDS.spaceMD),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 560, // [教練 Agent 2026-08-04 Phase E+] 280 → 560（放大兩倍）
                      childAspectRatio: 1.0,
                      crossAxisSpacing: BridgeDS.spaceMD,
                      mainAxisSpacing: BridgeDS.spaceMD,
                    ),
                    itemCount: companions.length,
                    itemBuilder: (context, index) {
                      final c = companions[index];
                      final isActive = c.id == activeId;
                      return _buildCompanionCard(c, isActive);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // [教練 Agent 2026-08-04 Phase E+] 夥伴館內容分發器：列表 or 子頁面
  Widget _buildCompanionHallOrSubPage() {
    final sub = _activeCompanionSubPage;
    final id = _activeCompanionId;
    if (sub == null) {
      // 在夥伴館列表
      return _buildCompanionHall();
    }
    if (id == null) {
      // 沒選角色 — 回列表
      return _buildCompanionHall();
    }
    // 子頁面路由
    switch (sub) {
      case 'control':
        return _wrapCompanionSubPage(
          title: '角色控制中心',
          child: CompanionControlCenterScreen(
            companionId: id,
            returnTo: null,
            hideAppBar: true,
            // [教練 Agent 2026-08-04 Phase E+] 內嵌模式用 callback，不用 context.go
            onBack: _handleCompanionSubPageBack,
            onNavigateTo: (page) => _navigateToCompanionSubPage(page, companionId: id),
          ),
        );
      case 'soul':
        return _wrapCompanionSubPage(
          title: '靈魂設定',
          child: CompanionSoulScreen(
            companionId: id,
            returnTo: null,
            hideAppBar: true,
            onBack: _handleCompanionSubPageBack,
            onNavigateTo: (page) => _navigateToCompanionSubPage(page, companionId: id),
          ),
        );
      case 'appearance':
        return _wrapCompanionSubPage(
          title: '主形象設定',
          child: CompanionAppearanceScreen(
            companionId: id,
            returnTo: null,
            hideAppBar: true,
            onBack: _handleCompanionSubPageBack,
            onNavigateTo: (page) => _navigateToCompanionSubPage(page, companionId: id),
          ),
        );
      case 'voice':
        return _wrapCompanionSubPage(
          title: '語音設定',
          child: VoiceSettingsScreen(
            companionId: id,
            returnTo: null,
            hideAppBar: true,
            onBack: _handleCompanionSubPageBack,
          ),
        );
      case 'create':
        return _wrapCompanionSubPage(
          // [教練 Agent 2026-08-05] 改回傳 title — 因為現在 companion_create_screen 的
          // hideAppBar=true 會真的隱藏內部 AppBar，外殼必須顯示標題
          title: '調整夥伴設定',
          child: CompanionCreateScreen(
            editingCompanionId: id,
            returnTo: null,
            hideAppBar: true,
            onBack: _handleCompanionSubPageBack,
          ),
        );
      default:
        return _buildCompanionHall();
    }
  }

  // [教練 Agent 2026-08-04 Phase E+] 包一個 AppBar 在子頁面頂部（含返回鍵）
  Widget _wrapCompanionSubPage({required String title, required Widget child}) {
    return Container(
      color: BridgeDSColors.of(context).canvas,
      child: Column(
        children: [
          // 子頁面 AppBar（含返回鍵）— 不污染六大按鈕
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: BridgeDSColors.of(context).canvas,
              border: Border(
                bottom: BorderSide(
                  color: BridgeDSColors.of(context).borderSubtle,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: BridgeDSColors.of(context).textPrimary),
                  tooltip: '返回',
                  onPressed: _handleCompanionSubPageBack,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(
                    color: BridgeDSColors.of(context).textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  // [教練 Agent 2026-08-04 Phase E+] 處理子頁面返回
  void _handleCompanionSubPageBack() {
    if (_companionPageStack.isEmpty) {
      // 直接回夥伴館列表
      setState(() {
        _activeCompanionSubPage = null;
        _activeCompanionId = null;
      });
    } else {
      // 退回上一頁
      final prev = _companionPageStack.removeLast();
      setState(() {
        _activeCompanionSubPage = prev;
        // _activeCompanionId 保持不變
      });
    }
  }

  // [教練 Agent 2026-08-04 Phase E+] 進入夥伴館子頁面 helper
  void _navigateToCompanionSubPage(String page, {required String companionId}) {
    setState(() {
      if (_activeCompanionSubPage != null) {
        _companionPageStack.add(_activeCompanionSubPage!);
      }
      _activeCompanionSubPage = page;
      _activeCompanionId = companionId;
    });
  }

  Widget _buildCompanionCard(Companion c, bool isActive) {
    return BridgeCard(
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      isBrain: isActive,
      onTap: () {
        // [教練 Agent 2026-08-04 Phase E+] 按角色卡 → 進 CompanionCreateScreen 編輯模式（截圖想要的版本）
        debugPrint('[BridgeDesktop] 開啟角色編輯: ${c.name} (${c.id})');
        setState(() {
          _activeCompanionId = c.id;
          _activeCompanionSubPage = 'create';
          _companionPageStack.clear();
        });
      },
      child: Stack(
        children: [
          Column(
            children: [
              // 夥伴圖像 — [教練 Agent 2026-08-04 Phase E+] 撐滿整個空間，用 BoxFit.contain 不裁切
              // [小葵 2026-09-13] 角色卡預覽呼吸感（與懸浮窗/設定頁同一套呼吸語彙）
              Expanded(
                child: BreathingImage(
  anchor: const Alignment(0, 0.15),  // 胸口呼吸
                  child: _buildCompanionAvatar(c, 120, fillContainer: true),
                ),
              ),
              SizedBox(height: BridgeDS.spaceMD),
              // 名字
              Text(
                c.name,
                style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(
                  color: BridgeDSColors.of(context).textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: BridgeDS.spaceSM),
              // 角色
              Text(
                c.roleName,
                style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textTertiary),
              ),
            ],
          ),
          // 活躍標記 — 右上角綠色光點
          if (isActive)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(context).accentGreen,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          // [教練 Agent 2026-08-14] 刪除夥伴按鈕 — 左上角
          Positioned(
            top: 0,
            left: 0,
            child: _buildDeleteCompanionButton(c),
          ),
        ],
      ),
    );
  }

  /// [教練 Agent 2026-08-14] 刪除夥伴按鈕 — 帶確認對話框
  Widget _buildDeleteCompanionButton(Companion c) {
    return IconButton(
      icon: Icon(Icons.delete_outline, size: 18, color: BridgeDSColors.of(context).textTertiary),
      tooltip: '刪除夥伴',
      onPressed: () {
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: BridgeDSColors.of(context).surfaceElevated,
            title: Text(
              '刪除夥伴',
              style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(
                color: BridgeDSColors.of(context).textPrimary,
              ),
            ),
            content: Text(
              '確定要刪除「${c.name}」嗎？\n\n夥伴的形象圖、狀態圖、設定資料都會永久刪除，無法復原。',
              style: BridgeDSColors.of(context).body.copyWith(
                color: BridgeDSColors.of(context).textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('取消', style: TextStyle(color: BridgeDSColors.of(context).textSecondary)),
              ),
              TextButton(
                onPressed: () async {
                  await CompanionStore().delete(c.id);
                  if (!mounted) return;
                  Navigator.of(dialogContext).pop();
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已刪除夥伴「${c.name}」')),
                  );
                },
                child: Text('刪除', style: TextStyle(color: BridgeDSColors.of(context).accentRed)),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 夥伴頭像 — 優先顯示生成的圖片，沒有則用 icon fallback
  // [教練 Agent 2026-08-04 Phase E+] fillContainer=true 時撐滿父容器（用於角色卡）
  Widget _buildCompanionAvatar(Companion c, double size, {bool fillContainer = false}) {
    // [小葵 2026-09-13] rig 動畫分支封存（Blue 拍板回歸靜態圖+呼吸感——僅懸浮窗有呼吸，
    // 夥伴館卡片回歸原始靜態頭像渲染。重啟動態=恢復上面 kRigByCompanion 分支）
    final path = c.avatarImagePath?.trim();
    Widget imageWidget;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        // [教練 Agent 2026-08-04 Phase E+] 撐滿模式用 BoxFit.contain（完整顯示，不裁切）
        imageWidget = ClipRRect(
          borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
          child: Image.file(
            file,
            fit: fillContainer ? BoxFit.contain : BoxFit.cover,
            alignment: Alignment.topCenter,
            width: fillContainer ? null : size,
            height: fillContainer ? null : size,
            errorBuilder: (_, error, __) => _avatarFallback(c, size),
          ),
        );
      } else {
        imageWidget = _avatarFallback(c, size);
      }
    } else {
      imageWidget = _avatarFallback(c, size);
    }

    if (fillContainer) {
      // [教練 Agent 2026-08-04 Phase E+] 撐滿整個 Expanded 空間
      return SizedBox.expand(child: imageWidget);
    }
    return imageWidget;
  }

  Widget _avatarFallback(Companion c, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
      ),
      child: Center(
        child: Text(
          c.name.isNotEmpty ? c.name.characters.first : '?',
          style: TierStyle.of(context, Tier.appDisplayLarge).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // Sidebar 底部夥伴圖像
  // ═══════════════════════════════════════════════════

  Widget _buildSidebarCompanionFooter() {
    final companion = CompanionStore().activeCompanion;
    if (companion == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(BridgeDS.spaceSM),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: BridgeDSColors.of(context).borderSubtle, width: 1)),
      ),
      // [2026-08-27 共視修復] Builder 包裹——onTap 必須用「夥伴列自己」的
      // context 算座標。之前誤用 State 的 context（= 整個畫面的 box，
      // 位置 ≈ 0,0），選單座標全歪（飛到右上角蓋 Logo 的根因）。
      child: Builder(
        builder: (rowContext) => GestureDetector(
        onTap: () async {
          final companions = CompanionStore().all;
          if (companions.isEmpty) return;
          final RenderBox box = rowContext.findRenderObject() as RenderBox;
          final pos = box.localToGlobal(Offset.zero);
          final overlay =
              Overlay.of(context).context.findRenderObject() as RenderBox;
          // [2026-08-27 共視修復] 錨在夥伴列正上方彈出——
          // top 用選單「底部」貼頭像頂（pos.dy 是頭像列頂部），
          // 選單自然往上長，不會飛到頂部蓋 Logo。
          final menuHeight = companions.length * 56.0 + 16;
          final selected = await showMenu<String>(
            context: context,
            position: RelativeRect.fromLTRB(
              pos.dx + 8,
              pos.dy - menuHeight,
              overlay.size.width - pos.dx - box.size.width - 8,
              overlay.size.height - pos.dy,
            ),
            items: [
              for (final c in companions)
                PopupMenuItem(
                  value: c.id,
                  height: 44,
                  child: Row(
                    children: [
                      // [TRIO M1] 選單 item 同樣掛狀態點——與底部夥伴列一致
                      AvatarWithStatus(
                        agentId: c.id,
                        dotSize: 8,
                        avatar: _buildCompanionAvatar(c, 24),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(c.name,
                                style: TierStyle.of(context, Tier.listItemTitle)
                                    .toTextStyle()),
                            Text('${c.mbtiCode} · ${c.roleName}',
                                style: TierStyle.of(context, Tier.cardCaption)
                                    .toTextStyle()),
                          ],
                        ),
                      ),
                      if (c.id == companion.id)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(Icons.check_circle,
                              size: 16,
                              color: BridgeDSColors.of(context).accentGreen),
                        ),
                    ],
                  ),
                ),
            ],
          );
          if (selected == null || selected == companion.id) return;
          // 正路切換：泡泡 + 交接簡報 + 廣播同步一次到位
          await _desktopChatController
              ?.switchToCompanionByRequest(selected, '（切換夥伴）');
          if (_desktopChatController == null) {
            // 對話 tab 未開過（controller 還沒建）——fallback setActive，
            // 等下次進對話頁 loadActiveCompanion 會跟上
            await CompanionStore().setActive(selected);
          }
          setState(() {});
        },
        child: Row(
          children: [
            // [TRIO M1] 頭像掛狀態點——AgentStatusStore 訂閱（D1 讀取端）
            AvatarWithStatus(
              agentId: companion.id,
              avatar: _buildCompanionAvatar(companion, 36),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    companion.name,
                    style: BridgeDSColors.of(context).labelMono.copyWith(fontSize: 14, color: BridgeDSColors.of(context).textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    companion.roleName,
                    style: BridgeDSColors.of(context).caption.copyWith(fontSize: 14, color: BridgeDSColors.of(context).textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: BridgeDSColors.of(context).textMuted),
          ],
        ),
      ),
      ),
    );
  }

  // ── Sidebar (240px) ────────────────────────────────
  // P10 重構：上方動態（依 tab 切換）+ 下方固定系統區

  Widget _buildSidebar() {
    // 系統 tab（index 4）不顯示 sidebar
    // 資料庫 tab（index 3）有自己的側欄，不顯示通用 sidebar
    // [v262] 大腦 tab 已除
    // [W3.5 2026-10-09 Blue 令] 專案 tab（index 2）不顯示通用 sidebar——
    // 任務清單欄由主區 TaskListSidebar 提供，外層再畫一欄會多出空白欄＋夥伴選項
    if (_activeCanvasIndex == 4 || _activeCanvasIndex == 3 ||
        _activeCanvasIndex == 2) {
      return const SizedBox.shrink();
    }

    // 畫布 tab（index 1）— 工具列 + 資產庫，不走 scroll wrapper
    if (_activeCanvasIndex == 1) {
      return _buildCanvasSidebar();
    }

    return Container(
      // [W4.7] 對話頁 sidebar 寬度可拖曳調整（drag handle 在 _buildChatTabLayout）
      width: _activeCanvasIndex == 0 ? _chatSidebarWidth : BridgeDS.sidebarWidth,
      color: BridgeDSColors.of(context).canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 動態區（依 tab 切換內容）
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BridgeDS.spaceMD),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildDynamicSidebarContent(),
              ),
            ),
          ),
          // 底部夥伴圖像（左下角）
          _buildSidebarCompanionFooter(),
        ],
      ),
    );
  }

  /// 畫布 tab 專用 sidebar — 畫布專案列表
  /// [教練 Agent 2026-08-16 使用者決策] 資產庫退役——Finder 拖檔直接進畫布
  /// （desktop_drop），檔案瀏覽/預覽/搜尋交給 Finder 這個專業工具。
  /// sidebar 職責收斂為純粹的畫布專案列表。
  Widget _buildCanvasSidebar() {
    final ds = BridgeDSColors.of(context);
    return Container(
      width: _canvasSidebarWidth,
      color: ds.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [教練 Agent 2026-08-16 使用者 提案] 頂部折疊鈕——收到左邊
          Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: '收起資產庫',
              waitDuration: const Duration(milliseconds: 400),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _canvasSidebarCollapsed = true),
                  child: Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(top: 4, right: 4),
                    decoration: BoxDecoration(
                      color: ds.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: ds.borderSubtle),
                    ),
                    child: Icon(Icons.chevron_left,
                        size: 16, color: ds.textMuted),
                  ),
                ),
              ),
            ),
          ),
          // 畫布列表（填滿剩餘空間，可滾動）
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BridgeDS.spaceSM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildCanvasListItems(),
              ),
            ),
          ),
          // [教練 Agent 2026-08-16 使用者 提案] 底部提示：Finder 拖檔進畫布
          Container(
            padding: const EdgeInsets.all(BridgeDS.spaceSM),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: ds.borderSubtle, width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.upload_file_outlined, size: 14, color: ds.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '從 Finder 拖檔案進畫布即可加入',
                    style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(
                      color: ds.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 畫布列表項（供畫布 tab sidebar 使用）
  List<Widget> _buildCanvasListItems() {
    return [
      _sidebarSection('專案畫布', [
        _sidebarItem('新增專案', Icons.add_rounded, false,
            onTap: _createNewCanvas),
        // [教練 Agent 2026-07-24] 示範工作流下拉選單 — 1-4 直接載入, 5 觸發教學
        PopupMenuButton<String>(
          onSelected: (templateId) {
            final templates = VaultTemplateService.instance.getBuiltinTemplates();
            final template = templates.where((t) => t.id == templateId).firstOrNull;
            if (template == null) return;

            if (template.isTutorialEntry) {
              // 完整互動教學 — 重新啟動教學流程
              _workspaceKey.currentState?.startInteractiveTutorial(isFirstVisit: false);
            } else {
              // 一般範本 — 直接載入到畫布
              _workspaceKey.currentState?.loadTemplate(template);
            }
          },
          itemBuilder: (context) {
            final templates = VaultTemplateService.instance.getBuiltinTemplates();
            return templates.map((t) {
              // [教練 Agent 2026-07-24] 教學入口加分隔線 + 特殊樣式
              return PopupMenuItem<String>(
                value: t.id,
                child: Row(
                  children: [
                    Text(t.icon, style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.name, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w500,
                            color: BridgeDSColors.of(context).textPrimary,)),
                          Text(t.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,)),
                        ],
                      ),
                    ),
                    if (t.isTutorialEntry)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(Icons.school, size: 14, color: BridgeDSColors.of(context).accentPurple),
                      ),
                  ],
                ),
              );
            }).toList();
          },
          child: _sidebarItem('示範工作流', Icons.auto_awesome, false),
        ),
        ..._canvases.map((canvas) {
          // [教練 Agent 2026-08-16 使用者 抓包] 亮塊判定改掛 _activeCanvasId——
          // 舊掛 conv.id == _currentConversationId，會被 _loadConversations()
          // 從 DB 重讀 currentId 覆寫沖掉（亮一下就滅的元兇）。
          // 畫布列表的活躍語意本來就該掛畫布 id。
          final isActive = _activeCanvasId == canvas.id;
          // [隊友訊息流 C5 2026-09-08] 〔任務〕工作畫布標記——
          // 活躍任務的工作畫布用火箭圖標+脈動點，一眼區分「這是夥伴的工地」
          final taskCanvas = TaskDispatcher.instance.activeSessions
              .where((s) => s.workCanvasId == canvas.id)
              .firstOrNull;
          final isTaskCanvas = taskCanvas != null;
          return _sidebarItem(
            canvas.title.isEmpty ? '（未命名畫布）' : canvas.title,
            isTaskCanvas
                ? Icons.rocket_launch_outlined
                : Icons.account_tree_outlined,
            isActive,
            onTap: () => _switchCanvas(canvas.id),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // [教練 Agent 2026-08-16 使用者決策] 「計畫中」等狀態標籤暫時下架——
                // 狀態機只有 planning→completed 兩態有效（executing/paused
                // 無觸發點），資訊量低。等狀態機補完再回來。
                if (canvas != null) ...[
                  GestureDetector(
                    onTap: () => _showCanvasRenameDialog(canvas.id, canvas.title),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.edit_outlined, size: 13,
                          color: BridgeDSColors.of(context).textTertiary),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _duplicateCanvas(canvas.id),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.copy, size: 13,
                          color: BridgeDSColors.of(context).textTertiary),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _deleteCanvas(canvas.id),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.close, size: 14,
                          color: BridgeDSColors.of(context).textTertiary),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
        // [小葵 2026-09-21 Blue 令] 畫布頁鏡像也要有——畫布列表與專案頁
        // 是同一份資料的兩個入口，兩邊都要能撈回刪錯的專案。
        _sidebarItem('專案回收桶', Icons.delete_outline, false,
            onTap: _showProjectTrashDialog),
      ]),
    ];
  }

  /// 依目前 tab 動態生成 sidebar 內容
  /// [小葵 2026-09-15] speakerId → 夥伴名（反查失敗退 '未知夥伴'——顯示不炸，
  /// 同 chat_sidebar._companionNameOf 邏輯）
  String _companionNameOf(String speakerId) {
    try {
      final c = CompanionStore().getById(speakerId);
      return c?.name ?? '未知夥伴';
    } catch (_) {
      return '未知夥伴';
    }
  }

  List<Widget> _buildDynamicSidebarContent() {
    // 系統 tab 的 sidebar 由 _buildSystemSidebar 處理
    if (_activeCanvasIndex == 4) {
      return _buildSystemSidebar();
    }

    switch (_activeCanvasIndex) {
      case 0: // 對話 — [教練 Agent 2026-08-16 使用者決策] 只留一般對話。
        // 專案畫布區段自對話頁 sidebar 退役——專案列表的家在畫布頁 sidebar，
        // 對話頁專心當對話列表，職責分明不再重複。
        final generalConvs = _conversations.where((c) => !c.isProjectCanvas).toList();

        return [
          // 💬 一般對話
          _sidebarSection('一般對話', [
            _sidebarItem('新增對話', Icons.add_rounded, false,
                onTap: _createNewConversation),
            // [時間感 L4 2026-09-13] 相簿——家的記憶按日子翻頁（家庭提案 L4）
            _sidebarItem('相簿', Icons.auto_stories_outlined, false,
                onTap: _openAlbum),
            ...generalConvs.map((c) {
              final isActive = c.id == _currentConversationId;
              // [小葵 2026-09-15 Blue 令] 參與者指紋章 glyph 列——刀 2 D2.5 的
              // chat_sidebar 版本沒帶到桌面側欄（兩套 sidebar 各自演化漏接）。
              // 掃訊息 speakerId 去重（同 chat_sidebar 邏輯），trailing 顯示。
              final speakerIds = c.messages
                  .map((m) => m.speakerId)
                  .whereType<String>()
                  .toSet()
                  .take(4)
                  .toList();
              return _sidebarItem(
                c.title.isEmpty ? '（未命名）' : c.title,
                Icons.chat_bubble_outline,
                isActive,
                onTap: () => _switchConversation(c.id),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 參與者指紋章：tooltip 帶名字，掃一眼就知道誰講過話
                    for (final sid in speakerIds)
                      Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Tooltip(
                          message: _companionNameOf(sid),
                          waitDuration: const Duration(milliseconds: 400),
                          child: AgentGlyph(
                            companionId: sid,
                            name: _companionNameOf(sid),
                            size: 18,
                            showInitial: false,
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: () => _showRenameDialog(c.id, c.title),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(Icons.edit_outlined, size: 13,
                            color: BridgeDSColors.of(context).textTertiary),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _deleteConversation(c.id),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(Icons.close, size: 14,
                            color: BridgeDSColors.of(context).textTertiary),
                      ),
                    ),
                  ],
                ),
              );
            }),
            // [小葵 2026-09-21] 回收桶——刪除≠銷毀（Blue 主權鐵則：絕不刪對話記憶）。
            // 點開彈出清單、逐則還原。位置：對話列表最底。
            _sidebarItem('回收桶', Icons.delete_outline, false,
                onTap: _showTrashDialog),
          ]),
        ];

      case 1: // 畫布 — sidebar 由 _buildCanvasSidebar 處理，此處不會到達
        return [];

      case 2: // 專案 — [W3.5] sidebar 退役，任務清單由主區 TaskListSidebar 提供
        return [];

      case 3: // 大腦
        // [Blue 滿屏令 2026-08-29] 左欄移除——大腦頁一進來就是滿屏 3D 星系
        return [];

      default:
        return [];
    }
  }

  /// 系統 tab 的 sidebar
  List<Widget> _buildSystemSidebar() {
    return [
      _sidebarSection('系統', [
        _sidebarItem('金鑰匙系統', Icons.bolt_outlined,
            _activeSystemPage == 'capabilities',
            onTap: () => setState(() {
              _activeSystemPage =
                  _activeSystemPage == 'capabilities' ? null : 'capabilities';
            }),
            isPrimary: true),
        _sidebarItem('模型下載', Icons.download_outlined,
            _activeSystemPage == 'model',
            onTap: () => setState(() {
              _activeSystemPage =
                  _activeSystemPage == 'model' ? null : 'model';
            })),
        _sidebarItem('配對管理', Icons.phonelink_outlined,
            _activeSystemPage == 'pairing',
            onTap: () => setState(() {
              _activeSystemPage =
                  _activeSystemPage == 'pairing' ? null : 'pairing';
            })),
        _sidebarItem('檔案總管', Icons.folder_outlined,
            _activeSystemPage == 'files',
            onTap: () => setState(() {
              _activeSystemPage =
                  _activeSystemPage == 'files' ? null : 'files';
            })),
        _sidebarItem('設定', Icons.settings_outlined,
            _activeSystemPage == 'settings',
            onTap: () => setState(() {
              _activeSystemPage =
                  _activeSystemPage == 'settings' ? null : 'settings';
            })),
      ]),
    ];
  }

  /// 系統子頁面標題列 — 含返回按鈕
  // [小葵 2026-09-30 F2] 系統子頁共用頭部——活動中心卡全子頁可見（不挑頁面）
  Widget _buildSystemPageHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _systemPageHeaderBase(title, subtitle),
        const SizedBox(height: BridgeDS.spaceMD),
        const SystemActivityCard(),
        const SizedBox(height: BridgeDS.spaceXL),
      ],
    );
  }

  Widget _systemPageHeaderBase(String title, String subtitle) {
    return Row(
      children: [
        Semantics(
          label: '返回系統',
          button: true,
          child: IconButton(
            onPressed: () => setState(() => _activeSystemPage = null),
            icon: const Icon(Icons.arrow_back, size: 20),
            color: BridgeDSColors.of(context).textSecondary,
            tooltip: '返回系統',
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(title, style: TierStyle.of(context, Tier.appDisplayLarge).toTextStyle()),
              SizedBox(height: 8),
              SelectableText(subtitle,
                  style: BridgeDSColors.of(context).body.copyWith(
                      color: BridgeDSColors.of(context).textMuted, fontWeight: FontWeight.w400)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSystemCard(String title, String subtitle, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BridgeDS.spaceMD),
      child: BridgeCard(
        padding: const EdgeInsets.all(BridgeDS.spaceMD),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: BridgeDSColors.of(context).accentBlue, size: 20),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary)),
                  Text(subtitle, style: BridgeDSColors.of(context).body.copyWith(color: BridgeDSColors.of(context).textTertiary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: BridgeDSColors.of(context).textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _sidebarSection(String title, List<Widget> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BridgeDS.spaceXL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(title, style: BridgeDSColors.of(context).labelMono.copyWith(fontSize: 14)),
          SizedBox(height: BridgeDS.spaceSM),
          ...items,
        ],
      ),
    );
  }

  Widget _sidebarItem(String label, IconData icon, bool active,
      {VoidCallback? onTap, Widget? trailing, bool isPrimary = false}) {
    // 主要操作（isPrimary）用 accentMiro + w600 突出；次要項維持原樣降權
    final Color iconColor = isPrimary
        ? BridgeDSColors.of(context).accentMiro
        : active
            ? BridgeDSColors.of(context).accentBlue
            : BridgeDSColors.of(context).textTertiary;
    final Color textColor = isPrimary
        ? BridgeDSColors.of(context).accentMiro
        : active
            ? BridgeDSColors.of(context).textPrimary
            : BridgeDSColors.of(context).textSecondary;
    final FontWeight weight = (isPrimary || active) ? FontWeight.w600 : FontWeight.w400;
    return _ActiveGlowItem(
      active: active,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                // [教練 Agent 2026-08-16 使用者回饋] 灰色亮塊→發亮細框——
                // 整塊底色影響文字辨識，改用藍色細框＋微光暈標示選中。
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
                border: active
                    ? Border.all(
                        color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.7),
                        width: 1,
                      )
                    : Border.all(
                        color: Colors.transparent,
                        width: 1, // 維持同寬，避免切換時抖動
                      ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.25),
                          blurRadius: 6,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 14, color: iconColor),
                  const SizedBox(width: 8),
                  // 按鈕區用 Text 不用 SelectableText，避免搶走點擊
                  Expanded(
                    child: Text(
                      label,
                      style: BridgeDSColors.of(context).body.copyWith(
                        color: textColor,
                        fontWeight: weight,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trailing != null) trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Canvas Area (flex) ─────────────────────────────
  // 文字層級：頁標題 = L2 Heading-L / 卡片標題 = L3 Heading-M / 描述 = L8 Caption

  Widget _buildCanvasArea() {
    // 資料庫 tab（index 3）— Vault 頁面
    if (_activeCanvasIndex == 3) {
      return const VaultScreen();
    }
    // 系統 tab（index 4）
    if (_activeCanvasIndex == 4) {
      if (_activeSystemPage == null) {
        // 系統選單頁
        return Container(
          color: BridgeDSColors.of(context).canvas,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BridgeDS.spaceLG),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('系統', style: TierStyle.of(context, Tier.appDisplayLarge).toTextStyle()),
                SizedBox(height: 8),
                SelectableText('macOS · 系統設定與管理',
                    style: BridgeDSColors.of(context).caption.copyWith(
                        fontSize: 14, color: BridgeDSColors.of(context).textMuted)),
                SizedBox(height: BridgeDS.spaceXL),
                // [小葵 2026-09-30 金礦1→F2] 活動中心——總覽頁也看得到
                const SystemActivityCard(),
                const SizedBox(height: BridgeDS.spaceMD),
                // 系統功能卡片列表
                // [教練 Agent 2026-08-01] 能力中心排最上面（最常用）
                _buildSystemCard('金鑰匙系統', 'API 金鑰、主腦設定與服務管理', Icons.bolt_outlined,
                    () => setState(() => _activeSystemPage = 'capabilities')),
                _buildSystemCard('模型下載', '嵌入模型管理', Icons.download_outlined,
                    () => setState(() => _activeSystemPage = 'model')),
                _buildSystemCard('配對管理', '手機配對與 Gateway', Icons.phonelink_outlined,
                    () => setState(() => _activeSystemPage = 'pairing')),
                _buildSystemCard('檔案總管', '檔案與資料夾管理', Icons.folder_outlined,
                    () => setState(() => _activeSystemPage = 'files')),
                _buildSystemCard('系統設定', 'Gateway、DB 路徑與外觀', Icons.settings_outlined,
                    () => setState(() => _activeSystemPage = 'settings')),
                // [WS-3 2026-09-13] 大搬家——Hermes → 橋樑 App 遷移精靈
                _buildSystemCard('大搬家', 'Hermes 排程、對話史與分身搬到橋樑', Icons.home_work_outlined,
                    () => setState(() => _activeSystemPage = 'migration')),
              ],
            ),
          ),
        );
      }
      switch (_activeSystemPage) {
        case 'compass':
          return const CompassScreen();
        case 'files':
          return Container(
            color: BridgeDSColors.of(context).canvas,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSystemPageHeader('檔案總管', 'macOS · 檔案與資料夾管理'),
                Expanded(child: DesktopFilePage()),
              ],
            ),
          );
        case 'capabilities':
          return Container(
            color: BridgeDSColors.of(context).canvas,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BridgeDS.spaceLG),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSystemPageHeader('金鑰匙系統', 'API 金鑰 · 主腦設定 · 服務管理'),
                  SizedBox(height: BridgeDS.spaceXL),
                  // [教練 Agent 2026-08-01] 嵌入 CapabilityCenterScreen 的 body
                  _CapabilityCenterContent(),
                ],
              ),
            ),
          );
        case 'settings':
          return Container(
            color: BridgeDSColors.of(context).canvas,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BridgeDS.spaceLG),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSystemPageHeader('系統設定', 'Gateway · 模型 · 系統管理'),
                  SizedBox(height: BridgeDS.spaceXL),
                  // [教練 Agent 2026-08-01] 引導到能力中心管理 API Key
                  _buildCapabilityCenterHint(),
                  SizedBox(height: BridgeDS.spaceMD),
                  _buildSettingsTab(),
                ],
              ),
            ),
          );
        // [WS-3 2026-09-13] 大搬家——Hermes → 橋樑 App 遷移精靈
        case 'migration':
          return Container(
            color: BridgeDSColors.of(context).canvas,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSystemPageHeader('大搬家', 'Hermes → 橋樑 App'),
                Expanded(child: HermesMigrationScreen()),
              ],
            ),
          );
        case 'model':
          return Container(
            color: BridgeDSColors.of(context).canvas,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BridgeDS.spaceLG),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSystemPageHeader('模型下載', 'macOS · 本地模型管理'),
                  SizedBox(height: BridgeDS.spaceXL),
                  // [教練 Agent 2026-07-20] 本地 LLM 引擎卡片（優先顯示）
                  BridgeCard(
                    child: Padding(
                      padding: const EdgeInsets.all(BridgeDS.spaceMD),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.memory,
                                  color: BridgeDSColors.of(context).accentPurple, size: 16),
                              const SizedBox(width: 8),
                              SelectableText('本地 LLM 引擎',
                                  style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
                            ],
                          ),
                          SizedBox(height: BridgeDS.spaceMD),
                          // [小葵 2026-10-01 F2b] 舊卡移除——wrapper _buildSystemPageHeader 已全子頁注入（雙卡 bug）
                          const LocalLlmRuntimeCard(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: BridgeDS.spaceMD),
                  // 模型實驗室（新器官 2026-09-29）：告知 → 測試 → 替換選型的完整 LOOP
                  const ModelLabCard(),
                  const SizedBox(height: BridgeDS.spaceMD),
                  BridgeCard(
                    child: Padding(
                      padding: const EdgeInsets.all(BridgeDS.spaceMD),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.psychology,
                                  color: BridgeDSColors.of(context).accentPurple, size: 16),
                              const SizedBox(width: 8),
                              SelectableText('大腦容器',
                                  style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
                              const Spacer(),
                              BridgeStatusTag(
                                label: _brainInitialized
                                    ? (_brainModelAvailable ? '模型已安裝' : 'Fallback')
                                    : '未初始化',
                                type: _brainInitialized && _brainModelAvailable
                                    ? BridgeTagType.success
                                    : BridgeTagType.warn,
                              ),
                            ],
                          ),
                          SizedBox(height: BridgeDS.spaceMD),
                          BrainModelDownloadCard(
                            onInstalled: () async {
                              final brain = BrainContainerService.instance;
                              final stats = await brain.getRoomStats();
                              if (mounted) {
                                setState(() {
                                  _brainModelAvailable = brain.isModelAvailable;
                                  _roomStats = stats;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        case 'pairing':
          return Container(
            color: BridgeDSColors.of(context).canvas,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(BridgeDS.spaceLG),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSystemPageHeader('配對管理', 'macOS · 手機配對與 Gateway'),
                  const SizedBox(height: BridgeDS.spaceXL),
                  _buildPairingCard(),
                  const SizedBox(height: BridgeDS.spaceMD),
                  _buildGatewayCard(),
                  const SizedBox(height: BridgeDS.spaceMD),
                  // Gateway 控制按鈕
                  Row(
                    children: [
                      BridgePillButton(
                        label: _gatewayRunning ? '停止 GATEWAY' : '啟動 GATEWAY',
                        icon: _gatewayRunning ? Icons.stop : Icons.play_arrow,
                        type: _gatewayRunning
                            ? BridgeButtonType.ghost
                            : BridgeButtonType.accent,
                        onPressed: _gatewayRunning ? _stopGateway : _startGateway,
                      ),
                      SizedBox(width: 16),
                      BridgePillButton(
                        label: '重啟',
                        icon: Icons.refresh,
                        type: BridgeButtonType.ghost,
                        onPressed: _restartGateway,
                      ),
                    ],
                  ),
                  SizedBox(height: BridgeDS.spaceMD),
                  _buildConnectionCard(),
                  if (_gatewayError != null) ...[
                    SizedBox(height: BridgeDS.spaceMD),
                    BridgeCard(
                      padding: const EdgeInsets.all(BridgeDS.spaceMD),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: BridgeDSColors.of(context).accentRed, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(_gatewayError!,
                              style: BridgeDSColors.of(context).caption.copyWith(
                                fontSize: 14,
                                color: BridgeDSColors.of(context).accentRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
      }
    }

    // 對話 tab（index 0）
    if (_activeCanvasIndex == 0) {
      return Container(
        color: BridgeDSColors.of(context).canvas,
        child: DesktopChatPanel(
          key: ValueKey('chat-$_currentConversationId'),
          onNavigateToSettings: () => setState(() {
            _onTabChanged(4);
            _activeSystemPage = 'settings';
          }),
          mcpCanvasExecutor: _mcpCanvasExecutor, // [Phase 0 Track A 2026-07-17]
          selfCaptureKey: _selfCaptureKey, // [教練 Agent 2026-07-19] 共用 App 自拍 key
          onControllerReady: (controller) {
            _desktopChatController = controller;
            // [v205] initState 期間同步 set value 會在 build 中 notify→
            // markNeedsBuild 競態（GlobalKey 連環衝突的源頭）。defer。
            WidgetsBinding.instance.addPostFrameCallback((_) {
              BridgeDesktopScreen.activeChatController.value = controller;
            });
          },
          // B系列: Agent 畫布匯入卡片按鈕 → 觸發匯入流程
          onCanvasImport: (summary, suggestedTitle) {
            final conv = _desktopChatController?.currentConversation;
            if (conv != null) {
              _importToNewCanvasWithSummary(conv, summary, suggestedTitle);
            }
          },
          // [教練 Agent 2026-08-03] ChatController 內建立新對話時同步刷新左側 sidebar。
          onConversationCreated: _syncNewConversationFromController,
        ),
      );
    }
    // 畫布 tab（index 1）— 畫布工作區
    if (_activeCanvasIndex == 1) {
      // [v204 畫布失蹤終章] X 光實錘：workspace State 被 GlobalKey 保活但
      // element 沒掛回樹（切頁動畫競態的犧牲者）——State 活著畫面卻沒有。
      // 修：State 存在但 context 沒了=幽靈→棄用舊 State，換新 key 重建。
      final ghost = _workspaceKey.currentState != null &&
          _workspaceKey.currentContext == null;
      if (ghost) {
        debugPrint('[v204] 🚨 幽靈 workspace State 偵測——重建（舊 State 釋放）');
        _canvasGhostCount = (_canvasGhostCount ?? 0) + 1;
      }
      // 切回畫布 tab 時，如果 workspace state 存在但 canvasId 未設定，自動恢復
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ws = _workspaceKey.currentState;
        if (ws != null && _activeCanvasId != null && ws.canvasId != _activeCanvasId) {
          ws.loadCanvasById(_activeCanvasId!);
        }
      });
      return CanvasV2Workspace(
        key: ghost ? GlobalKey<CanvasV2WorkspaceState>() : _workspaceKey,
        initialCanvasId: _activeCanvasId,
        mcpCanvasExecutor: _mcpCanvasExecutor, // [v212] 畫布對話 Agent 的主控工具
        chatWidth: _canvasChatWidth,
        onChatWidthChanged: (w) => setState(() => _canvasChatWidth = w),
        // [教練 Agent 2026-08-16 使用者 提案] 右側對話框折疊收右
        chatCollapsed: _canvasChatCollapsed,
        onChatCollapseToggle: () => setState(() => _canvasChatCollapsed = !_canvasChatCollapsed),
        onExecutePlan: (stepTitles) => _executeCanvasPlan(stepTitles),
        onChatControllerReady: (controller) {
          _canvasChatController = controller as ChatController;
          debugPrint('[MCP] CanvasChatController 就緒 ✅');
          // [D002 2026-08-10] 畫布聊天的安全確認——跟 persistent controller 用同一個 callback
          _canvasChatController!.onToolConfirmation =
              _persistentChatController.onToolConfirmation;
          // [教練 Agent 2026-08-02] 接上節點結果推送 callback
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ws = _workspaceKey.currentState;
            if (ws != null && ws.controller != null) {
              ws.controller.onNodeResult = (nodeId, nodeTitle, result) {
                // [教練 Agent 2026-08-19] 標記系統事件——節點結果不做意圖分類
                // [小葵 2026-09-24 Blue 令·修衝突回話] 舊路徑 sendDirectMessage
                // 仍會喚醒 AgentLoop 跑一輪 LLM——Agent 對機器訊息長篇解讀，
                // 跟實際工作流狀態打架（「未選服務」「管線通了」滿天飛）。
                // 改走 injectAssistantMessage：純顯示、不觸發任何推論——
                // 節點結果是「事實播報」不是「問題」，不需要 AI 回答。
                controller.injectAssistantMessage(
                  '📍 節點「$nodeTitle」執行完成：$result',
                  metadata: const {'kind': 'nodeResult'},
                );
              };
            }
          });
        },
        showToolbar: true, // [教練 Agent 2026-07-22] 修復：工具列必須顯示，否則刪除/塗鴉/連線/新增按鈕全消失
        onToolChanged: (tool) => setState(() => _canvasTool = tool),
        onDoodleVisibleChanged: (visible) =>
            setState(() => _canvasDoodleVisible = visible),
        selfCaptureKey: _selfCaptureKey, // [2026-07-20] 畫布頁也走 App 自拍
        onSaved: (canvasId, conversationId) async {
          // [教練 Agent 2026-07-23] 存檔後刷新 sidebar + 切換到新對話
          await _loadCanvases();
          await _loadConversations();
          if (conversationId != null) {
            final conv = await ConversationStore.getById(conversationId);
            if (conv != null) {
              setState(() {
                _activeCanvasId = canvasId;
                _currentConversationId = conv.id;
              });
              await ConversationStore.setCurrentId(conv.id);
              if (_canvasChatController != null) {
                await _canvasChatController!.switchConversation(conv);
              }
            }
          }
        },
      );
    }
    // 專案 tab（index 2）
    if (_activeCanvasIndex == 2) {
      // [W3.5 2026-10-09] 整頁改版——Blue 拍板定案圖：
      // 左＝任務清單欄（排程上/專案下）；右上 ~57%＝排隊卡；右下＝畫布專案卡。
      // 舊 kanban 三欄＋H4「28 個約定」欄退役。
      return Stack(children: [
        Container(
        color: BridgeDSColors.of(context).canvas,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左欄：任務清單（[W4.7] 寬度可拖曳——紫色把手同畫布頁）
            SizedBox(
              width: _projectSidebarWidth,
              child: TaskListSidebar(
                onOpenCanvas: (canvasId) => _switchCanvas(canvasId),
              ),
            ),
            _buildDragHandle(
              onDrag: (delta) {
                setState(() {
                  _projectSidebarWidth =
                      (_projectSidebarWidth + delta).clamp(180.0, 420.0);
                });
              },
            ),
            // 右側主區：上排隊（57%）＋下專案卡
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 上區 ~57%：自動排程任務排隊
                    Expanded(
                      flex: 57,
                      child: SingleChildScrollView(
                        // [W4] 點卡→任務詳情抽屜（可編輯任務內容＋執行歷史）
                        child: ScheduleQueueSection(
                          revNotifier: scheduleQueueRev,
                          onOpenFolder: (entry) => _openScheduleFolder(entry),
                          onRunNow: (entry) => _runScheduleNow(entry),
                          onTogglePause: (entry, paused) =>
                              _toggleSchedulePause(entry, paused),
                          onOpenDetail: (entry) {
                            // [W4.4 Blue 令 2026-10-09] 單一資訊欄（頁內覆蓋）：
                            // 點卡＝開欄/換內容；背景卡片完全可互動；
                            // 按 ✕ 才關（抽屜 onClose）
                            _drawerEntry.value = entry;
                          },
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    // 下區：畫布專案卡（被動容器）
                    Expanded(
                      flex: 43,
                      child: SingleChildScrollView(
                        child: ProjectDoorGrid(
                          onOpenCanvas: (canvasId) => _switchCanvas(canvasId),
                          onCreateProject: _createNewCanvas,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
        // [W4.4 Blue 令 2026-10-09] 頁內覆蓋資訊欄——背景完全可互動：
        // 開著欄位時點背景其他卡＝直接換內容（不用關再開）；
        // 按 ✕ 才收起
        ValueListenableBuilder<ScheduleQueueEntry?>(
          valueListenable: _drawerEntry,
          builder: (_, entry, __) {
            if (entry == null) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.centerRight,
              child: ScheduleTaskDetailDrawer(
                key: ValueKey(entry.nodeId),
                entry: entry,
                onSaved: (_, __) {},
                onOpenCanvas: (canvasId) {
                  _drawerEntry.value = null;
                  if (canvasId.isNotEmpty) _switchCanvas(canvasId);
                },
                onClose: () => _drawerEntry.value = null,
              ),
            );
          },
        ),
      ]);
    }
    // [小葵 2026-09-07] 2D 大腦圖譜退役——3=vault/4=system 已在上面
    // 攔截，0/1/2 也已攔截；此 fallback 理論上不可達，防禦性返回對話 tab
    return Container(
      color: BridgeDSColors.of(context).canvas,
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  String _canvasTitle() => switch (_activeCanvasIndex) {
        0 => '對話',
        1 => '畫布',
        2 => '專案',
        3 => '向量資料庫',
        _ => '',
      };

  String _canvasSubtitle() => switch (_activeCanvasIndex) {
        0 => 'macOS · ${_conversations.length} 個對話',
        1 => 'macOS · 無限畫布工作區',
        2 => 'macOS · 專案看板與水流追蹤',
        3 => 'macOS · 向量資料庫 — 檔案索引與搜尋',
        _ => '',
      };

  // [v262 Blue 重構令] 開大腦圖譜網頁版（Chrome App 視窗——絲滑保證）
  // [v265 Blue 唯一視窗令] 已有開啟 → 浮到最上層（不重開）；
  // 標題鎖定「橋樑大腦圖譜」——永遠只有一個。
  // [收據搜尋 RC3] focusAssetId——全局搜尋跳轉：帶 ?focus= 開（既有視窗時
  // 直接 navigate 既有視窗到 focus URL——唯一視窗令不破壞）。
  Future<void> _openBrainGalaxyWindow({String? focusAssetId}) async {
    String? token;
    try {
      final f = File(resolveDevPath('~/Library/Application Support/farm.semiwasabi.bridgeApp/mcp_token'));
      if (f.existsSync()) token = f.readAsStringSync().trim();
    } catch (_) {}
    var url = 'http://localhost:8420/galaxy?token=$token';
    if (focusAssetId != null && focusAssetId.isNotEmpty) {
      // [S2 快取真兒修] focus 跳轉必帶 cache-buster——Chrome 快取舊 galaxy.html
      // 會讓 RC3b 新行為（開卡+圓心自轉）不生效（Blue 實測抓包）
      url += '&focus=${Uri.encodeComponent(focusAssetId)}'
          '&_cb=${DateTime.now().millisecondsSinceEpoch}';
    }

    // ① 唯一性檢查：既有「橋樑大腦圖譜」視窗 → 若帶 focus 用 JS navigate
    //    既有視窗（觸發 galaxy 端 focus 邏輯），否則只 activate+浮頂
    if (_focusExistingGalaxyWindow()) {
      if (focusAssetId != null && focusAssetId.isNotEmpty) {
        _navigateGalaxyWindow(url);
      }
      return;
    }

    // ② 三級鏈開新視窗：Chrome App → 系統預設瀏覽器 → Swift 視窗
    try {
      final r = Process.runSync('open', ['-na', 'Google Chrome', '--args', '--app=$url']);
      if (r.exitCode == 0) return;
    } catch (_) {}
    try {
      final r = Process.runSync('open', [url]);
      if (r.exitCode == 0) return;
    } catch (_) {}
    try {
      const channel = MethodChannel('bridge.desktop_shell.macos.v1');
      await channel.invokeMethod('openGalaxyWindow', {'url': url});
    } catch (e) {
      debugPrint('[v262] 開大腦圖譜視窗失敗: $e');
    }
  }

  /// [收據搜尋 RC3 2026-09-08] 讓既有星系視窗導航到 focus URL。
  /// Chrome 系用 AppleScript execute（其他瀏覽器靜默跳過——
  /// 退路是使用者手動重開，不炸）。
  void _navigateGalaxyWindow(String url) {
    try {
      Process.runSync('osascript', ['-e', '''
        tell application "Google Chrome"
          set w to first window whose title contains "大腦圖譜"
          set URL of active tab of w to "$url"
        end tell
      ''']);
    } catch (e) {
      debugPrint('[RC3] 星系視窗 navigate 失敗（不阻塞跳轉）: $e');
    }
  }

  /// [v265] 找既有的星系視窗並浮到最上層。回傳 true=找到並處理。
  /// AppleScript 支援的瀏覽器逐一試（Chrome/Edge/Brave/Arc/Dia）；
  /// 視窗標題含「大腦圖譜」就算（galaxy.html title=橋樑大腦圖譜）。
  bool _focusExistingGalaxyWindow() {
    const apps = [
      'Google Chrome', 'Microsoft Edge', 'Brave Browser', 'Arc', 'Dia',
    ];
    for (final a in apps) {
      try {
        // 檢查該 App 是否在跑+有沒有星系視窗
        final check = Process.runSync('osascript', ['-e', '''
          tell application "System Events"
            set _p to (name of processes) contains "$a"
          end tell
          if _p then
            tell application "$a"
              set _w to count of (every window whose title contains "大腦圖譜")
              if _w > 0 then return "found"
            end tell
          end if
          return "none"
        ''']);
        if (check.exitCode == 0 && check.stdout.toString().trim() == 'found') {
          // activate：App 帶到前景+該視窗循環到最前
          // [v266 Blue 修正令] ①activate 只帶 App 前景——會推「別的網頁視窗」
          // 上來；正解：先把星系視窗 set index to 1（成為 App 最前視窗）
          // 再 activate。②最小化叫不出來——set minimized to false 先還原。
          Process.runSync('osascript', ['-e', '''
            tell application "$a"
              set w to first window whose title contains "大腦圖譜"
              set minimized of w to false
              set index of w to 1
              activate
            end tell
          ''']);
          debugPrint('[v266] 既有星系視窗已還原+浮頂 ($a)');
          return true;
        }
      } catch (_) {}
    }
    return false;
  }


  // ── 檔案 Tab（Sprint 16 預留）─────────────────────

  Widget _buildViewToggle() {
    return Container(
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle, width: 1),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
        ],
      ),
    );
  }

  Widget _toggleButton(
      IconData icon, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          border: active
              ? Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.5), width: 1)
              : Border.all(color: Colors.transparent, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active ? BridgeDSColors.of(context).accentPurple : BridgeDSColors.of(context).textMuted),
            SizedBox(width: BridgeDS.spaceSM),
            Text(
              label,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: active ? BridgeDSColors.of(context).textPrimary : BridgeDSColors.of(context).textMuted,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,),
            ),
          ],
        ),
      ),
    );
  }

  // ── 設定 Tab ────────────────────────────────────────

  /// [教練 Agent 2026-08-01] 能力中心引導卡片
  Widget _buildCapabilityCenterHint() {
    return BridgeCard(
      child: InkWell(
        onTap: () => setState(() => _activeSystemPage = 'capabilities'),
        borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
        child: Padding(
          padding: const EdgeInsets.all(BridgeDS.spaceMD),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.bolt_outlined,
                    color: BridgeDSColors.of(context).accentMiro, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('管理 API 金鑰與服務',
                        style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
                    Text('前往金鑰匙系統開通圖片生成、影片、音樂等能力',
                        style: BridgeDSColors.of(context).body
                            .copyWith(color: BridgeDSColors.of(context).textTertiary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: BridgeDSColors.of(context).textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [教練 Agent 2026-08-04] Phase E+：主題包入口（顯示在第一個，最顯眼）
        _buildThemePackCard(),
        SizedBox(height: BridgeDS.spaceMD),
        // Gateway 設定
        _buildGatewayCard(),
        const SizedBox(height: BridgeDS.spaceMD),
        // Gateway 控制按鈕
        Row(
          children: [
            BridgePillButton(
              label: _gatewayRunning ? '停止 GATEWAY' : '啟動 GATEWAY',
              icon: _gatewayRunning ? Icons.stop : Icons.play_arrow,
              type: _gatewayRunning
                  ? BridgeButtonType.ghost
                  : BridgeButtonType.accent,
              onPressed: _gatewayRunning ? _stopGateway : _startGateway,
            ),
            SizedBox(width: 16),
            BridgePillButton(
              label: '重啟',
              icon: Icons.refresh,
              type: BridgeButtonType.ghost,
              onPressed: _restartGateway,
            ),
          ],
        ),
        SizedBox(height: BridgeDS.spaceMD),

        // 系統資訊卡
        BridgeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.computer,
                      color: BridgeDSColors.of(context).accentBlue, size: 16),
                  SizedBox(width: 8),
                  SelectableText('系統資訊', style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
                ],
              ),
              SizedBox(height: BridgeDS.spaceMD),
              _infoRow('Platform', Platform.operatingSystem),
              _infoRow('OS Version', Platform.operatingSystemVersion),
              _infoRow('CPU Cores', '${Platform.numberOfProcessors}'),
              _infoRow('Dart Version', Platform.version.split(' ').first),
            ],
          ),
        ),
        SizedBox(height: BridgeDS.spaceMD),

        // 大腦模型設定
        BridgeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology,
                      color: BridgeDSColors.of(context).accentPurple, size: 16),
                  const SizedBox(width: 8),
                  SelectableText('大腦容器',
                      style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
                  const Spacer(),
                  BridgeStatusTag(
                    label: _brainInitialized
                        ? (_brainModelAvailable ? '模型已安裝' : 'Fallback')
                        : '未初始化',
                    type: _brainInitialized && _brainModelAvailable
                        ? BridgeTagType.success
                        : BridgeTagType.warn,
                  ),
                ],
              ),
              const SizedBox(height: BridgeDS.spaceMD),
              _infoRow('狀態', _brainInitFailed
                  ? '初始化失敗（sqlite-vec）'
                  : _brainInitialized ? '已初始化' : '初始化中'),
              _infoRow('嵌入模型',
                  _brainModelAvailable ? 'EmbeddingGemma' : '零向量 fallback'),
              _infoRow('記憶總數',
                  '${_roomStats.values.fold(0, (a, b) => a + b)} 條'),
              const SizedBox(height: BridgeDS.spaceMD),
              // EmbeddingGemma 模型下載卡片
              BrainModelDownloadCard(
                onInstalled: () async {
                  // 模型安裝完成 → 刷新大腦容器狀態
                  final brain = BrainContainerService.instance;
                  final stats = await brain.getRoomStats();
                  if (mounted) {
                    setState(() {
                      _brainModelAvailable = brain.isModelAvailable;
                      _roomStats = stats;
                    });
                  }
                },
              ),
            ],
          ),
        ),

        SizedBox(height: BridgeDS.spaceMD),

        // [小葵 2026-10-02] 自我喚醒（防崩潰看門狗）開關——Watchdog v3 搭檔（Blue 案 10-01）
        const WatchdogToggleCard(),
        SizedBox(height: BridgeDS.spaceMD),

        // [教練 Agent 2026-08-10] 大腦資料庫位置設定（從 settings_screen.dart 搬來）
        const DbLocationCard(),
        SizedBox(height: BridgeDS.spaceMD),

        // [資料主權 P0-c 2026-09-14] 資料路徑總覽——ledger 攤給使用者看（人機共視）
        const DataPathOverviewCard(),
        SizedBox(height: BridgeDS.spaceMD),

        // Agent Loop + Skills 設定 (S21+S20)
        BridgeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.loop,
                      color: BridgeDSColors.of(context).accentGreen, size: 16),
                  const SizedBox(width: 8),
                  SelectableText('Agent Loop 與 Skills',
                      style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
                  Spacer(),
                  BridgeStatusTag(
                    label: _agentLoopEnabled ? '已啟用' : '關閉',
                    type: _agentLoopEnabled
                        ? BridgeTagType.success
                        : BridgeTagType.info,
                  ),
                ],
              ),
              SizedBox(height: BridgeDS.spaceMD),
              _infoRow('Agent Loop',
                  _agentLoopEnabled ? '啟用（多輪工具呼叫）' : '關閉（一般對話）'),
              _infoRow('最大輪數', '15（硬上限 30）'),
              _infoRow('可用工具', '9 個（搜尋/記憶/圖片/文件/瀏覽器…）'),
              _infoRow('Skills 系統', '已整合（程序記憶自動匹配）'),
              SizedBox(height: BridgeDS.spaceMD),
              Row(
                children: [
                  SelectableText('啟用 Agent Loop',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
                  Spacer(),
                  Switch(
                    value: _agentLoopEnabled,
                    onChanged: _toggleAgentLoop,
                    activeThumbColor: BridgeDSColors.of(context).accentGreen,
                  ),
                ],
              ),
              SizedBox(height: 8),
              SelectableText(
                _agentLoopEnabled
                    ? '已啟用 — AI 會自動判斷是否使用工具（搜尋、記憶、圖片等），無需手動切換。'
                    : '已關閉 — AI 僅進行一般對話，不呼叫任何工具。如需 AI 自主查詢或操作，請開啟。',
                style: BridgeDSColors.of(context).small.copyWith(
                  color: _agentLoopEnabled
                      ? BridgeDSColors.of(context).accentGreen
                      : BridgeDSColors.of(context).textMuted,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: BridgeDS.spaceMD),
              // B4: 螢幕感知開關
              Row(
                children: [
                  SelectableText('螢幕感知（screen_capture）',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
                  Spacer(),
                  Switch(
                    value: _screenCaptureEnabled,
                    onChanged: _toggleScreenCapture,
                    activeThumbColor: BridgeDSColors.of(context).accentYellow,
                  ),
                ],
              ),
              SizedBox(height: 8),
              SelectableText(
                _screenCaptureEnabled
                    ? '已啟用 — Agent 可截取指定視窗的螢幕截圖，用於觀察與理解您正在看的內容。'
                    : '已關閉 — 預設關閉以保護隱私。啟用後 Agent 可自主截取指定視窗（非全螢幕）。',
                style: BridgeDSColors.of(context).small.copyWith(
                  color: _screenCaptureEnabled
                      ? BridgeDSColors.of(context).accentYellow
                      : BridgeDSColors.of(context).textMuted,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: BridgeDS.spaceMD),

        // [教練 Agent 2026-07-30] 預設選型原則
        BridgeCard(
          child: Padding(
            padding: const EdgeInsets.all(BridgeDS.spaceMD),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.policy_outlined, color: BridgeDSColors.of(context).accentPurple, size: 16),
                    const SizedBox(width: 8),
                    SelectableText('預設選型原則', style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(
                  '在對話中說「太慢了，少跑幾輪」或「要有創意一點」就可以建立原則。\n選擇「預設」時會自動套用。',
                  style: BridgeDSColors.of(context).small.copyWith(fontSize: 14, color: BridgeDSColors.of(context).textMuted),
                ),
                const SizedBox(height: BridgeDS.spaceMD),
                _buildDefaultPolicyPanel(),
              ],
            ),
          ),
        ),

        SizedBox(height: BridgeDS.spaceXXL),
        _buildLogSection(),
      ],
    );
  }

  /// [教練 Agent 2026-07-30] 預設選型原則面板——從 ProviderProfileStore 讀取 policies
  Widget _buildDefaultPolicyPanel() {
    return FutureBuilder<List<CustomRoutingPolicy>>(
      future: ProviderProfileStore.instance.getAllPolicies(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final policies = snapshot.data!;
        final ds = BridgeDSColors.of(context);

        if (policies.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Icon(Icons.inbox_outlined, color: ds.textTertiary, size: 24),
                const SizedBox(width: 8),
                Text('尚無預設選型原則', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textSecondary)),
              ],
            ),
          );
        }

        return Column(
          children: policies.map((p) {
            final modelLabel = p.model ?? '全部模型';
            return Card(
              color: ds.surfaceElevated,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: p.isActive ? ds.accentGreen.withValues(alpha: 0.4) : ds.borderSubtle,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                leading: Icon(
                  p.isActive ? Icons.check_circle : Icons.circle_outlined,
                  color: p.isActive ? ds.accentGreen : ds.textTertiary,
                  size: 20,
                ),
                title: Text(
                  p.name,
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w700, color: ds.textPrimary),
                ),
                subtitle: Text(
                  '${p.provider} / $modelLabel',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textTertiary),
                ),
                trailing: p.isActive
                    ? TextButton(
                        onPressed: () async {
                          await ProviderProfileStore.instance.deactivatePolicy(p.id);
                          setState(() {});
                        },
                        child: Text('停用', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.accentRed)),
                      )
                    : TextButton(
                        onPressed: () async {
                          await ProviderProfileStore.instance.activatePolicy(p.id);
                          setState(() {});
                        },
                        child: Text('啟用', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.accentGreen)),
                      ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ── 卡片標題 = L3 Heading-M (24px) ─────────────────

  Widget _buildPairingCard() {
    final qrPayload = (_lanIp != null && _pairingCode.isNotEmpty)
        ? 'bridge://pair?host=$_lanIp&port=${_gatewayPort ?? 8790}&code=$_pairingCode'
        : '';

    return BridgeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.qr_code, color: BridgeDSColors.of(context).accentBlue, size: 16),
              const SizedBox(width: 8),
              SelectableText('配對碼', style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(
                fontSize: 24,
              )),
              const Spacer(),
              BridgeStatusTag(
                label: _pairingCode.isNotEmpty ? '就緒' : '產生中',
                type: _pairingCode.isNotEmpty
                    ? BridgeTagType.success
                    : BridgeTagType.warn,
              ),
            ],
          ),
          SizedBox(height: BridgeDS.spaceMD),
          if (_pairingCode.isEmpty)
            SizedBox(height: 24)
          else ...[
            // 配對碼 = L1 Display (hero)
            SelectableText(
              _pairingCode,
              style: BridgeDSColors.of(context).display.copyWith(
                fontSize: 28,
                fontWeight: FontWeight.w400,
                letterSpacing: 4,
                color: BridgeDSColors.of(context).textPrimary,
              ),
            ),
            SizedBox(height: 8),
            // LAN endpoint
            SelectableText(
              _lanIp != null
                  ? 'ws://$_lanIp:${_gatewayPort ?? 8790}/bridge'
                  : '偵測 LAN IP 中…',
              style: BridgeDSColors.of(context).caption.copyWith(
                fontSize: 14,
                color: _lanIp != null
                    ? BridgeDSColors.of(context).textSecondary
                    : BridgeDSColors.of(context).textMuted,
              ),
            ),
            // 多 IP 時顯示其他選項
            if (_allLanIps.length > 1) ...[
              SizedBox(height: 8),
              SelectableText(
                '其他 IP: ${_allLanIps.skip(1).join(', ')}',
                style: BridgeDSColors.of(context).small.copyWith(
                  fontSize: 14,
                  color: BridgeDSColors.of(context).textQuaternary,
                ),
              ),
            ],
            // QR Code
            if (qrPayload.isNotEmpty) ...[
              SizedBox(height: BridgeDS.spaceMD),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(context).surfaceElevated,
                    borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
                  ),
                  child: QrImageView(
                    data: qrPayload,
                    version: QrVersions.auto,
                    size: 180,
                    gapless: true,
                  ),
                ),
              ),
              SizedBox(height: 8),
              // 說明 = L8 Caption
              SelectableText(
                '手機掃描 QR 碼連線，或手動輸入配對碼',
                style: BridgeDSColors.of(context).caption.copyWith(
                  fontSize: 14,
                  color: BridgeDSColors.of(context).textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ],
      ),
    );
  }

  // [教練 Agent 2026-08-04] Phase E+：主題包入口卡片
  Widget _buildThemePackCard() {
    final ds = BridgeDSColors.of(context);
    return BridgeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined,
                  color: ds.accentBlue, size: 16),
              SizedBox(width: 8),
              SelectableText('主題包',
                  style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(color: ds.textPrimary)),
            ],
          ),
          SizedBox(height: BridgeDS.spaceMD),
          SelectableText(
            '主題包是一份可下載的設計資產，內含 33 個色彩 token。'
            '切換主題可一鍵改變整個 App 的配色。',
            style: ds.body.copyWith(color: ds.textSecondary),
          ),
          SizedBox(height: BridgeDS.spaceMD),
          Row(
            children: [
              BridgePillButton(
                label: '設定',
                icon: Icons.tune,
                type: BridgeButtonType.accent,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ThemeSettingsPage(
                        themeProvider: ThemeProvider.instance,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGatewayCard() {
    return BridgeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.router, color: BridgeDSColors.of(context).accentGreen, size: 16),
              const SizedBox(width: 8),
              SelectableText('本機 Gateway', style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(
                fontSize: 24,
              )),
              const Spacer(),
              BridgeStatusTag(
                label: _gatewayRunning ? '運行中' : '已停止',
                type: _gatewayRunning
                    ? BridgeTagType.success
                    : BridgeTagType.warn,
              ),
            ],
          ),
          const SizedBox(height: BridgeDS.spaceMD),
          _infoRow('端點',
              _gatewayPort != null
                  ? 'ws://127.0.0.1:$_gatewayPort/bridge'
                  : 'ws://127.0.0.1:8790/bridge（待啟動）'),
          _infoRow('Port', _gatewayPort?.toString() ?? '—'),
          _infoRow('協議', 'WebSocket (dart:io HttpServer)'),
        ],
      ),
    );
  }

  Widget _buildConnectionCard() {
    return BridgeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.phone_android,
                  color: BridgeDSColors.of(context).accentBlue, size: 16),
              const SizedBox(width: 8),
              SelectableText('手機連線', style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(
                fontSize: 24,
              )),
              const Spacer(),
              BridgeStatusTag(
                label: _mobileConnected ? '已連線' : '等待中',
                type: _mobileConnected
                    ? BridgeTagType.success
                    : BridgeTagType.info,
              ),
            ],
          ),
          SizedBox(height: BridgeDS.spaceMD),
          _infoRow('狀態',
              _mobileConnected ? '手機已連接' : '尚未有手機連線'),
          _infoRow('連線次數', '$_connectCount'),
        ],
      ),
    );
  }

  // InfoRow — label = L9 Small / value = L11 Code
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BridgeDS.spaceSM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: SelectableText(label, style: BridgeDSColors.of(context).caption.copyWith(
              color: BridgeDSColors.of(context).textMuted,
            )),
          ),
          Expanded(
            child: SelectableText(value, style: BridgeDSColors.of(context).code.copyWith(
              color: BridgeDSColors.of(context).textSecondary,
            )),
          ),
        ],
      ),
    );
  }

  // ── Log Section ────────────────────────────────────
  // 標題 = L3 Heading-M / log = L11 Code

  Widget _buildLogSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SelectableText('訊息記錄', style: TierStyle.of(context, Tier.appHeadline).toTextStyle()),
            Spacer(),
            if (_log.isNotEmpty)
              BridgePillButton(
                label: '清除',
                icon: Icons.clear_all,
                type: BridgeButtonType.ghost,
                onPressed: _clearLog,
              ),
          ],
        ),
        SizedBox(height: BridgeDS.spaceMD),
        Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).surface,
            borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
            border: Border.all(color: BridgeDSColors.of(context).borderSubtle, width: 1),
          ),
          child: _log.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox,
                        color: BridgeDSColors.of(context).textQuaternary, size: 40),
                      SizedBox(height: 8),
                      SelectableText('尚無訊息',
                        style: BridgeDSColors.of(context).body.copyWith(
                          color: BridgeDSColors.of(context).textMuted,
                          fontWeight: FontWeight.w400)),
                      SizedBox(height: 8),
                      SelectableText('手機連線後，請求會顯示在這裡',
                        style: BridgeDSColors.of(context).caption.copyWith(
                          color: BridgeDSColors.of(context).textQuaternary)),
                    ],
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: _log.length,
                  itemBuilder: (context, index) {
                    final entry = _log[index];
                    return _LogTile(entry: entry, isLatest: index == 0);
                  },
                ),
        ),
      ],
    );
  }

  // ── Context Panel (320px) ──────────────────────────
  // 文字層級：分類標題 = L10 Label / 值 = L9 Small

  Widget _buildContextPanel() {
    return Container(
      width: BridgeDS.contextPanelWidth,
      color: BridgeDSColors.of(context).canvas,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(BridgeDS.spaceMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _contextSection('系統資訊', [
              _contextInfoRow('Platform', Platform.operatingSystem),
              _contextInfoRow('OS', Platform.operatingSystemVersion),
              _contextInfoRow('Cores', '${Platform.numberOfProcessors}'),
            ]),
            _contextSection('快捷操作', [
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  BridgeChip(
                    label: '重啟 Gateway',
                    icon: Icons.refresh,
                    onTap: _restartGateway,
                  ),
                  BridgeChip(
                    label: '清除記錄',
                    icon: Icons.clear_all,
                    onTap: _clearLog,
                  ),
                  BridgeChip(
                    label: '複製配對碼',
                    icon: Icons.copy,
                    onTap: _copyPairingCode,
                  ),
                ],
              ),
            ]),
            _contextSection('大腦記憶', [
              if (_brainInitFailed)
                SelectableText(
                  'macOS desktop 不支援\nsqlite-vec（Sprint 17 修復）',
                  style: BridgeDSColors.of(context).small.copyWith(
                    fontSize: 14,
                    color: BridgeDSColors.of(context).accentYellow,
                  ),
                )
              else if (!_brainInitialized)
                SelectableText(
                  '初始化中…',
                  style: BridgeDSColors.of(context).small.copyWith(
                    fontSize: 14,
                    color: BridgeDSColors.of(context).textMuted,
                  ),
                )
              else if (_roomStats.isEmpty)
                SelectableText(
                  '尚無記憶\n六房均為空',
                  style: BridgeDSColors.of(context).small.copyWith(
                    fontSize: 14,
                    color: BridgeDSColors.of(context).textMuted,
                  ),
                )
              else
                ...BrainRoom.values.map((room) {
                  final count = _roomStats[room] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 0),
                    child: Row(
                      children: [
                        SelectableText(room.icon, style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
                        SizedBox(width: 8),
                        SelectableText(
                          room.displayName,
                          style: BridgeDSColors.of(context).small.copyWith(
                            fontSize: 14,
                            color: BridgeDSColors.of(context).textSecondary,
                          ),
                        ),
                        Spacer(),
                        SelectableText(
                          '$count',
                          style: BridgeDSColors.of(context).small.copyWith(
                            fontSize: 14,
                            color: count > 0
                                ? BridgeDSColors.of(context).accentGreen
                                : BridgeDSColors.of(context).textQuaternary,
                            fontFamily: BridgeDS.fontDisplay,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _contextSection(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BridgeDS.spaceXL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(title, style: BridgeDSColors.of(context).labelMono.copyWith(fontSize: 14)),
          SizedBox(height: BridgeDS.spaceSM),
          ...children,
        ],
      ),
    );
  }

  Widget _contextInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: SelectableText(label, style: BridgeDSColors.of(context).small.copyWith(
              fontSize: 14,
              color: BridgeDSColors.of(context).textMuted,
              fontFamily: BridgeDS.fontDisplay,
            )),
          ),
          Expanded(
            child: SelectableText(value, style: BridgeDSColors.of(context).small.copyWith(
              fontSize: 14,
              color: BridgeDSColors.of(context).textSecondary,
            )),
          ),
        ],
      ),
    );
  }

  // ── Status Bar (32px) ──────────────────────────────
  // 文字 = L10 Label mono (10px)

  /// [Blue 令 2026-10-05] 頂部「本地模型」晶片按鈕
  /// 左鍵：開/關本地模型；右鍵（secondaryTap）：設定選單——閒置 10 分鐘自動卸載開關
  Widget _buildLocalModelChip() {
    return StreamBuilder<bool>(
      stream: BrainRevivalService.instance.powerStream,
      initialData: BrainRevivalService.instance.userEnabled,
      builder: (context, snap) {
        final on = snap.data ?? true;
        final svc = BrainRevivalService.instance;
        return GestureDetector(
          onSecondaryTapUp: (details) {
            final overlay =
                Overlay.of(context).context.findRenderObject() as RenderBox;
            final position = RelativeRect.fromLTRB(
              details.globalPosition.dx,
              details.globalPosition.dy,
              overlay.size.width - details.globalPosition.dx,
              overlay.size.height - details.globalPosition.dy,
            );
            showMenu<String>(
              context: context,
              position: position,
              items: [
                CheckedPopupMenuItem<String>(
                  value: 'toggle_idle',
                  checked: svc.idleUnloadEnabled,
                  child: const Text('閒置 10 分鐘自動卸載'),
                ),
              ],
            ).then((v) {
              if (v == 'toggle_idle') {
                svc.setIdleUnloadEnabled(!svc.idleUnloadEnabled);
                setState(() {}); // 刷新勾選狀態
              }
            });
          },
          child: Tooltip(
            message: svc.idleUnloadEnabled
                ? (on ? '本地模型運行中——點擊休眠（釋放 ~6GB）；右鍵設定自動卸載' : '本地模型已休眠——點擊啟動；右鍵設定自動卸載')
                : (on ? '本地模型運行中（自動卸載已停用）——點擊休眠；右鍵可開啟自動卸載' : '本地模型已休眠——點擊啟動；右鍵可開啟自動卸載'),
            child: BridgeChip(
              label: on ? '本地模型' : '本地模型 · 休眠',
              icon: on
                  ? (svc.idleUnloadEnabled ? Icons.psychology : Icons.psychology_alt)
                  : Icons.bedtime_outlined,
              active: on,
              onTap: () {
                if (svc.userEnabled) {
                  svc.powerOff(LocalModelRuntimeService());
                } else {
                  svc.powerOn(LocalModelRuntimeService());
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: BridgeDS.statusBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceLG),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas,
        border: Border(
          top: BorderSide(color: BridgeDSColors.of(context).borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          BridgeStatusDot(active: _gatewayRunning, size: 6),
          SizedBox(width: 8),
          SelectableText(
            _gatewayRunning ? 'GATEWAY RUNNING' : 'GATEWAY STOPPED',
            style: BridgeDSColors.of(context).labelMono.copyWith(
              fontSize: 14,
              color: _gatewayRunning
                  ? BridgeDSColors.of(context).accentGreen
                  : BridgeDSColors.of(context).textMuted,
            ),
          ),
          SizedBox(width: BridgeDS.spaceLG),
          if (_pairingCode.isNotEmpty)
            SelectableText(
              '配對碼: $_pairingCode',
              style: BridgeDSColors.of(context).labelMono.copyWith(
                fontSize: 14,
                color: BridgeDSColors.of(context).textMuted,
              ),
            ),
          Spacer(),
          SelectableText(
            '${Platform.operatingSystem} · ${DateTime.now().year}',
            style: BridgeDSColors.of(context).labelMono.copyWith(
              fontSize: 14,
              color: BridgeDSColors.of(context).textQuaternary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Helper classes
// ═══════════════════════════════════════════════════

enum _LogType { system, connected, disconnected, request, error }

class _GatewayLogEntry {
  final String message;
  final _LogType type;
  final DateTime time;
  _GatewayLogEntry(this.message, this.type, this.time);
}

class _LogTile extends StatefulWidget {
  final _GatewayLogEntry entry;
  final bool isLatest;

  const _LogTile({required this.entry, this.isLatest = false});

  @override
  State<_LogTile> createState() => _LogTileState();
}

class _LogTileState extends State<_LogTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );
    if (widget.isLatest) {
      _glowController.value = 0.5;
    }
  }

  @override
  void didUpdateWidget(_LogTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLatest && !oldWidget.isLatest) {
      _glowController.value = 0.5;
    } else if (!widget.isLatest && oldWidget.isLatest) {
      _glowController.stop();
      _glowController.value = 0;
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Color _color() => switch (widget.entry.type) {
    _LogType.system => BridgeDSColors.of(context).accentBlue,
    _LogType.connected => BridgeDSColors.of(context).accentGreen,
    _LogType.disconnected => BridgeDSColors.of(context).accentYellow,
    _LogType.request => BridgeDSColors.of(context).accentPurple,
    _LogType.error => BridgeDSColors.of(context).accentRed,
  };

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final timeStr =
        '${entry.time.hour.toString().padLeft(2, '0')}:'
        '${entry.time.minute.toString().padLeft(2, '0')}:'
        '${entry.time.second.toString().padLeft(2, '0')}';

    final baseColor = _color();

    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        // 最新一條微微呼吸發光：0 → 0.25 → 0
        final glowAlpha = widget.isLatest
            ? 0.05 + _glowController.value * 0.2
            : 0.0;

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          margin: const EdgeInsets.only(bottom: 0),
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).surfaceGlass,
            borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
            border: widget.isLatest
                ? Border.all(
                    color: baseColor.withValues(alpha: glowAlpha),
                    width: 1,
                  )
                : null,
            boxShadow: widget.isLatest
                ? [
                    BoxShadow(
                      color: baseColor.withValues(alpha: glowAlpha * 0.8),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              SelectableText(timeStr, style: BridgeDSColors.of(context).code.copyWith(
                fontSize: 14,
                color: BridgeDSColors.of(context).textMuted,
              )),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(entry.message, style: BridgeDSColors.of(context).code.copyWith(
                  fontSize: 14,
                  color: baseColor,
                )),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════
// Active Glow Item — sidebar 項目呼吸發光
// ═══════════════════════════════════════════════════

class _ActiveGlowItem extends StatefulWidget {
  final bool active;
  final Widget child;

  const _ActiveGlowItem({this.active = false, required this.child});

  @override
  State<_ActiveGlowItem> createState() => _ActiveGlowItemState();
}

class _ActiveGlowItemState extends State<_ActiveGlowItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );
    if (widget.active) _controller.value = 0.5;
  }

  @override
  void didUpdateWidget(_ActiveGlowItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.value = 0.5;
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glowAlpha = 0.05 + _controller.value * 0.2;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
            boxShadow: [
              BoxShadow(
                color: BridgeDSColors.of(context).accentBlue.withValues(alpha: glowAlpha),
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// [Phase 0 Track A 2026-07-17] 桌面版 MCP 工具執行器
/// 直接包裝 BridgeMcpServer 的 callback，不走 HTTP
class _DesktopMcpCanvasExecutor implements McpCanvasExecutor {
  final BridgeMcpServer mcp;
  final CanvasMcpRegistry reg;
  // [小葵 2026-09-15] 當前畫布 ID getter——跨頁移交需要知道節點落在哪張畫布
  final String? Function()? activeCanvasIdGetter;

  _DesktopMcpCanvasExecutor({
    required this.mcp,
    required this.reg,
    this.activeCanvasIdGetter,
  });

  @override
  Future<Map<String, dynamic>> getState() async {
    if (mcp.onGetState != null) return await mcp.onGetState!();
    return {};
  }

  /// [教練 Agent 2026-08-22 渲染層視網膜] ActualSizeCache 直讀真實渲染尺寸
  @override
  Future<Map<String, dynamic>> getRenderLayerData() async {
    final ctrl = reg.controller;
    if (ctrl == null) return {};
    final out = <String, dynamic>{};
    for (final id in ctrl.state.nodes.keys) {
      final actual = ActualSizeCache.get(id);
      out[id] = {
        'width': actual?.width,
        'height': actual?.height,
        'measured': actual != null,
      };
    }
    return out;
  }

  /// [教練 Agent 2026-08-21] 自律——工作流體檢（執行前品質檢查）
  /// 掃 DAG：付費節點盤點、未設定 prompt、重複、孤兒產出。
  @override
  Future<Map<String, dynamic>> inspectWorkflow() async {
    final ctrl = reg.controller;
    if (ctrl == null) return {'hasSevereWarnings': false, 'warnings': [], 'briefing': ''};

    final nodes = ctrl.state.nodes;
    final edges = <String>[];
    for (final node in nodes.values) {
      for (final rel in node.entity.relations) {
        edges.add('${rel.sourceId}>${rel.targetId}');
      }
    }

    final inspection = WorkflowInspector.inspect(nodes: nodes, edges: edges);
    return {
      'hasSevereWarnings': inspection.hasSevereWarnings,
      'warnings': inspection.warnings,
      'briefing': inspection.briefing,
      'imageNodes': inspection.imageNodes,
      'videoNodes': inspection.videoNodes,
      'musicNodes': inspection.musicNodes,
      'totalNodes': inspection.totalNodes,
    };
  }

  @override
  Future<Map<String, dynamic>> getSnapshot() async {
    final snap = reg.getSnapshot();
    // 加入文字報告方便工具直接用
    snap['report'] = reg.getSnapshotReport();
    return snap;
  }

  @override
  Future<void> moveNode(String nodeId, double x, double y) async {
    reg.moveNode(nodeId, x, y);
  }

  // [教練 Agent 2026-08-26 使用者 基礎規則] 一鍵自動排版——
  // 依連線拓撲分層（來源在左、消費者在右），層內垂直均分。
  @override
  Future<Map<String, dynamic>> autoLayout() async {
    return reg.autoLayout();
  }

  // [教練 Agent 2026-08-16 使用者要求 3] 畫布操盤——改既有節點參數
  @override
  Future<Map<String, dynamic>> updateNodeParams(
      String nodeId, Map<String, dynamic> params) async {
    if (mcp.onSetNodeParams == null) throw Exception('onSetNodeParams 未接線');
    return await mcp.onSetNodeParams!(nodeId, params);
  }

  @override
  Future<Map<String, dynamic>> getNodeParams(String nodeId) async {
    if (mcp.onGetNodeParams == null) throw Exception('onGetNodeParams 未接線');
    return mcp.onGetNodeParams!(nodeId);
  }

  @override
  Future<String> screenshot() async {
    if (mcp.onScreenshot != null) return await mcp.onScreenshot!();
    return '';
  }

  @override
  List<Map<String, dynamic>> getAnnotations() {
    if (mcp.onGetAnnotations != null) return mcp.onGetAnnotations!();
    return [];
  }

  @override
  Future<String> addNode(String type, double x, double y) async {
    if (mcp.onAddNode == null) return '';
    // 將 String 轉為 WorkflowNodeType
    final nodeType = _parseWorkflowNodeType(type);
    final nodeId = await mcp.onAddNode!(nodeType, x, y);
    // [小葵 2026-09-15 Blue 令] 跨頁任務移交——
    // 對話頁的 agent 建了畫布節點，但畫布頁的對話完全不知道：
    // 使用者切過去看到的是教學/空白，任務上下文斷在兩頁之間。
    // 修：addNode 成功後，把移交訊息寫進綁定此畫布的 project
    // conversation（找不到就建一個）——畫布頁打開時第一眼是任務續篇。
    if (nodeId.isNotEmpty) {
      await _writeCanvasHandoff(type, nodeId);
    }
    return nodeId;
  }

  /// [小葵 2026-09-15] 跨頁移交訊息——寫進畫布綁定的 project conversation。
  /// 一行事實：誰、在哪個畫布、建了什麼節點。LLM 對話續篇由畫布頁的
  /// controller 接手（它讀到這條就有完整上下文）。
  Future<void> _writeCanvasHandoff(String nodeType, String nodeId) async {
    try {
      // executor 不直接持有 state——透過 getter 拿當前畫布 ID
      final currentId = activeCanvasIdGetter?.call();
      if (currentId == null || currentId.isEmpty) return;
      final canvas = await CanvasStore.getById(currentId);
      final canvasTitle = canvas?.title ?? '畫布';
      // 找綁定此畫布的 project conversation
      final convs = await ConversationStore.getAll();
      var proj = convs
          .where((c) => c.isProjectCanvas && c.canvasId == currentId)
          .firstOrNull;
      final now = DateTime.now();
      if (proj == null) {
        proj = Conversation.createProjectCanvas(
          canvasId: currentId,
          title: canvasTitle,
        ).copyWith(updatedAt: now);
      }
      final msg = Message(
        id: 'handoff-${now.microsecondsSinceEpoch}',
        role: 'assistant',
        content: '［任務移交］我在對話頁幫你於畫布「$canvasTitle」建立了 '
            '$nodeType 節點（ID: $nodeId）。切到畫布頁可以看到它。'
            '要繼續這個任務直接跟我說，我接著做。',
        timestamp: now,
        metadata: {
          'kind': 'canvas_handoff',
          'canvasId': currentId,
          'nodeId': nodeId,
        },
      );
      await ConversationStore.save(
        proj.copyWith(messages: [...proj.messages, msg], updatedAt: now),
      );
      debugPrint('[小葵 09-15] 跨頁移交已寫入: $nodeType → $canvasTitle');
    } catch (e) {
      debugPrint('[小葵 09-15] 移交寫入失敗（不擋節點）: $e');
    }
  }

  @override
  Future<void> connect(
      String fromNodeId, String fromPort, String toNodeId, String toPort) async {
    if (mcp.onConnect != null) {
      await mcp.onConnect!(fromNodeId, fromPort, toNodeId, toPort);
    }
  }

  @override
  Future<void> removeNode(String nodeId) async {
    if (mcp.onRemoveNode != null) {
      await mcp.onRemoveNode!(nodeId);
    }
  }

  @override
  Future<void> execute() async {
    if (mcp.onExecute != null) {
      await mcp.onExecute!();
    }
  }

  @override
  void navigateToCanvas() {
    reg.onNavigateToCanvas?.call();
  }

  @override
  void sendChat(String message, {String? role}) {
    reg.onSendChatMessage?.call(message, role: role);
  }

  @override
  List<Map<String, dynamic>> listCanvases() {
    if (reg.onListCanvases != null) return reg.onListCanvases!();
    return [];
  }

  @override
  void loadCanvas(String canvasId) {
    reg.onLoadCanvas?.call(canvasId);
  }

  /// 將字串轉為 WorkflowNodeType
  WorkflowNodeType _parseWorkflowNodeType(String type) {
    return WorkflowNodeType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => WorkflowNodeType.llm,
    );
  }
}

/// Home Page 格子資料
class _HomeTile {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isPrimary; // [改善3] 主操作卡片標記

  const _HomeTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isPrimary = false,
  });

  /// 佔位格子（未來功能，不可點擊）
  const _HomeTile.placeholder({
    required this.icon,
    required this.title,
    required this.subtitle,
  })  : iconColor = Colors.transparent,
        onTap = null,
        isPrimary = false;
}

/// ═══════════════════════════════════════════════════
/// UI 操作執行器 — 讓原生 Agent能看見首頁、使用按鈕、切換頁面
/// [Phase 2 2026-07-18]
/// ═══════════════════════════════════════════════════
class _DesktopUiActionExecutor implements UiActionExecutor {
  final _BridgeDesktopScreenState _screen;

  _DesktopUiActionExecutor(this._screen);

  @override
  Map<String, dynamic> getState() {
    String page;
    List<String> tappable = [];
    String pageSummary = '';

    if (_screen._isHomepage) {
      page = 'home';
      tappable = ['召喚夥伴', '夥伴館', '對話', '畫布', '大腦', '系統']; // 大腦=開網頁版視窗（v262 保留導航名）
      pageSummary = '首頁 — 歡迎畫面';
    } else if (_screen._isCompanionHall) {
      page = 'companion_hall';
      try {
        final companions = CompanionStore().all;
        for (final c in companions) {
          tappable.add(c.name);
        }
        tappable.add('返回首頁');
        pageSummary = '夥伴館 — ${companions.length} 個夥伴';
      } catch (_) {}
    } else {
      // 一般 tab 畫面 — 導航按鈕每頁都有
      tappable = ['首頁', '對話', '畫布', '專案', '大腦', '資料庫', '系統']; // 同上

      switch (_screen._activeCanvasIndex) {
        case 0:
          page = 'chat';
          tappable.addAll(['新增對話', '側邊欄']);
          final conv = _screen._desktopChatController?.currentConversation;
          if (conv != null) {
            final msgCount = conv.messages.length;
            pageSummary = '對話頁 — 「${conv.title}」($msgCount 則訊息)';
          } else {
            pageSummary = '對話頁 — 尚無對話';
          }
          break;
        case 1:
          page = 'canvas';
          pageSummary = '畫布頁';
          break;
        case 2:
          page = 'project';
          pageSummary = '專案頁';
          break;
        case 3:
          page = 'vault';
          pageSummary = '向量資料庫頁';
          break;
        case 5:
          page = 'system';
          if (_screen._activeSystemPage == null) {
            tappable.addAll(['模型下載', '配對管理', '檔案總管', '設定', '金鑰匙系統']);
            pageSummary = '系統選單';
          } else {
            tappable.add('返回系統');
            pageSummary = '系統 — ${_screen._activeSystemPage}';
          }
          break;
        default:
          page = 'unknown';
      }
    }

    // 夥伴資訊
    String? companionName;
    bool hasCompanion = false;
    try {
      final ac = CompanionStore().activeCompanion;
      if (ac != null) {
        companionName = ac.name;
        hasCompanion = true;
      }
      hasCompanion = hasCompanion || CompanionStore().all.isNotEmpty;
    } catch (_) {}

    return {
      'page': page,
      'activeTab': _screen._activeCanvasIndex,
      'hasCompanion': hasCompanion,
      'companionName': companionName,
      'tappable': tappable,
      'pageSummary': pageSummary,
    };
  }

  @override
  Map<String, dynamic> inspect() {
    final state = getState();
    final page = state['page'] as String;
    String details = '';

    switch (page) {
      case 'chat':
        final controller = _screen._desktopChatController;
        final conv = controller?.currentConversation;
        if (conv != null) {
          final recent = conv.messages.reversed.take(5).toList().reversed.toList();
          final msgLines = recent.map((m) {
            final role = m.role == 'user' ? '使用者' : 'Agent';
            final content = m.content.length > 100
                ? '${m.content.substring(0, 100)}...'
                : m.content;
            return '  [$role] $content';
          }).join('\n');
          details = '對話標題: ${conv.title}\n'
              '訊息總數: ${conv.messages.length}\n'
              '最近 5 則:\n$msgLines';
        } else {
          details = '目前沒有活躍對話';
        }
        break;

      case 'system':
        final subPage = _screen._activeSystemPage;
        if (subPage == 'settings') {
          details = '系統設定頁\n'
              '注意：API Token 和金鑰內容已隱藏，Agent 無法讀取。\n'
              '可查看：provider 配置狀態、Gateway URL、模型設定。';
        } else if (subPage == 'model') {
          details = '模型下載頁';
        } else if (subPage == null) {
          details = '系統選單 — 四個功能入口 + 金鑰匙系統';
        } else {
          details = '系統子頁面: $subPage';
        }
        break;

      case 'brain':
        details = '大腦圖譜（3D 星系獨立視窗）\n'
            '用 ui_tap("大腦圖譜") 開啟獨立視窗';
        break;

      case 'vault':
        details = '向量資料庫頁面\n'
            '使用 ui_get_state 查看可點擊元素';
        break;

      case 'home':
        details = '首頁 — 歡迎畫面，可從此導航到各功能';
        break;

      case 'companion_hall':
        try {
          final companions = CompanionStore().all;
          final names = companions.map((c) => '${c.name} (${c.id})').join(', ');
          details = '夥伴館 — ${companions.length} 個夥伴: $names';
        } catch (_) {
          details = '夥伴館';
        }
        break;

      default:
        details = '頁面: $page — 使用 ui_get_state 查看可點擊元素';
    }

    return {
      'page': page,
      'details': details,
    };
  }

  @override
  bool navigate(String target) {
    switch (target) {
      case 'home':
        _screen._goHome();
        return true;
      case 'companion_hall':
        _screen._goCompanionHall();
        return true;
      case 'chat':
        _screen._switchTab(0);
        return true;
      case 'canvas':
        _screen._switchTab(1);
        return true;
      case 'project':
        _screen._switchTab(2);
        return true;
      case 'brain':
        _screen._switchTab(3);
        return true;
      case 'vault':
        _screen._switchTab(4);
        return true;
      case 'system':
        _screen._switchTab(5);
        return true;
      case 'summon':
        _screen._goSummon();
        return true;
      case 'settings':
        _screen._switchTab(5);
        _screen.setState(() => _screen._activeSystemPage = 'settings');
        return true;
      case 'golden_keys':
        _screen._switchTab(5);
        _screen.setState(() => _screen._activeSystemPage = 'settings');
        return true;
      case 'capabilities':
        _screen._switchTab(5);
        _screen.setState(() => _screen._activeSystemPage = null);
        return true;
      default:
        return false;
    }
  }

  @override
  bool tap(String label) {
    final state = getState();
    final page = state['page'] as String;
    final tappable = state['tappable'] as List;

    if (!tappable.contains(label)) return false;

    // 導航類按鈕（全域）
    switch (label) {
      case '召喚夥伴':
        _screen._goSummon();
        return true;
      case '夥伴館':
        _screen._goCompanionHall();
        return true;
      case '對話':
        _screen._switchTab(0);
        return true;
      case '畫布':
        _screen._switchTab(1);
        return true;
      case '專案':
        _screen._switchTab(2);
        return true;
      case '大腦':
        _screen._switchTab(3);
        return true;
      case '資料庫':
        _screen._switchTab(4);
        return true;
      case '系統':
        _screen._switchTab(5);
        return true;
      case '首頁':
      case '返回首頁':
        _screen._goHome();
        return true;
      case '新增對話':
        _screen._desktopChatController?.createNewConversation();
        return true;
      case '側邊欄':
        // TODO: 開啟對話側邊欄
        return true;
    }

    // 夥伴館：點夥伴名
    if (page == 'companion_hall') {
      try {
        final companions = CompanionStore().all;
        for (final c in companions) {
          if (c.name == label) {
            CompanionStore().setActive(c.id);
            _screen._switchTab(0);
            return true;
          }
        }
      } catch (_) {}
    }

    // 系統頁面
    if (page == 'system') {
      switch (label) {
        case '模型下載':
          _screen.setState(() => _screen._activeSystemPage = 'model');
          return true;
        case '配對管理':
          _screen.setState(() => _screen._activeSystemPage = 'pairing');
          return true;
        case '檔案總管':
          _screen.setState(() => _screen._activeSystemPage = 'files');
          return true;
        case '設定':
          _screen.setState(() => _screen._activeSystemPage = 'settings');
          return true;
        case '金鑰匙系統':
          _screen.setState(() => _screen._activeSystemPage = null);
          return true;
        case '返回系統':
          _screen.setState(() => _screen._activeSystemPage = null);
          return true;
      }
    }

    return false;
  }
}

// ═══════════════════════════════════════════════════
// _CapabilityCenterContent — 金鑰匙系統嵌入式 widget
// [教練 Agent 2026-08-01] 在系統 tab 裡顯示能力卡片
// ═══════════════════════════════════════════════════

class _CapabilityCenterContent extends StatefulWidget {
  @override
  State<_CapabilityCenterContent> createState() => _CapabilityCenterContentState();
}

class _CapabilityCenterContentState extends State<_CapabilityCenterContent> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await ServiceRegistry.instance.initialize();
    if (mounted) setState(() => _initialized = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(40),
        child: CircularProgressIndicator(),
      ));
    }

    final groups = ServiceRegistry.instance.capabilityGroups;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [教練 Agent 2026-08-11] 主腦 API 設定——金鑰匙系統最重要的區塊
        const BrainApiConfigCard(),
        const SizedBox(height: 16),
        // 能力分類卡片
        ...groups.map((group) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _CapabilityCard(group: group),
        )),
      ],
    );
  }
}

/// 單一能力卡片（桌面版）
class _CapabilityCard extends StatefulWidget {
  final CapabilityGroup group;
  const _CapabilityCard({required this.group});

  @override
  State<_CapabilityCard> createState() => _CapabilityCardState();
}

class _CapabilityCardState extends State<_CapabilityCard> {
  bool _expanded = false;
  bool _checking = true;
  bool _activated = false;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final activated = await ServiceRegistry.instance.activatedServicesFor(widget.group.capability);
    if (mounted) setState(() {
      _count = activated.length;
      _activated = activated.isNotEmpty;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final cap = widget.group.capability;

    return BridgeCard(
      child: Padding(
        padding: const EdgeInsets.all(BridgeDS.spaceMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Icon(cap.icon, size: 24, color: cap.color(context)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cap.displayName, style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
                        Text(cap.description, style: ds.caption.copyWith(color: ds.textTertiary)),
                      ],
                    ),
                  ),
                  if (_checking)
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _activated ? ds.accentGreen.withValues(alpha: 0.12) : ds.textMuted.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _activated ? '$_count 開通' : '未開通',
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: _activated ? ds.accentGreen : ds.textMuted, fontWeight: FontWeight.w500),
                      ),
                    ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: ds.textTertiary),
                ],
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 20),
              ...widget.group.services.map((s) => _ServiceTile(service: s, onChanged: _check)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 服務行（桌面版簡化）
class _ServiceTile extends StatefulWidget {
  final ServiceDefinition service;
  final VoidCallback onChanged;
  const _ServiceTile({required this.service, required this.onChanged});

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    _checkKey();
  }

  Future<void> _checkKey() async {
    if (widget.service.keyRequirement.type == KeyType.none) {
      setState(() => _hasKey = true);
      return;
    }
    final sk = widget.service.keyRequirement.storageKey;
    if (sk == null) return;
    final token = await StorageService.getToken(provider: sk);
    if (mounted) setState(() => _hasKey = token != null && token.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final s = widget.service;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hasKey ? ds.accentGreen : ds.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s.providerName} · ${s.serviceName}', style: ds.body.copyWith(fontSize: 14)),
                if (s.note != null)
                  Text(s.note!, style: ds.small.copyWith(color: ds.textTertiary)),
              ],
            ),
          ),
          if (_hasKey && s.keyRequirement.type != KeyType.none)
            TextButton(
              onPressed: () => _showKeyDialog(context),
              child: Text('管理', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textSecondary)),
            )
          else if (s.keyRequirement.type != KeyType.none)
            FilledButton.tonal(
              onPressed: () => _showKeyDialog(context),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                textStyle: TierStyle.of(context, Tier.cardBody).toTextStyle(),
              ),
              child: Text('設定 ${s.keyRequirement.label}'),
            )
          else
            Text('已就緒', style: ds.small.copyWith(color: ds.accentGreen)),
        ],
      ),
    );
  }

  void _showKeyDialog(BuildContext context) {
    final controller = TextEditingController();
    final keyReq = widget.service.keyRequirement;
    final isUrl = keyReq.type == KeyType.url;

    if (keyReq.storageKey != null) {
      StorageService.getToken(provider: keyReq.storageKey).then((t) {
        if (t != null && mounted) controller.text = t;
      });
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(keyReq.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              obscureText: !isUrl,
              decoration: InputDecoration(
                labelText: keyReq.label,
                hintText: keyReq.hint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => ctx.pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final v = controller.text.trim();
              if (v.isEmpty) return;
              if (keyReq.storageKey != null) {
                await StorageService.saveToken(v, provider: keyReq.storageKey);
              }
              if (ctx.canPop()) ctx.pop();
              _checkKey();
              widget.onChanged();
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }
}

/// [小葵 2026-09-21 Blue 令] 回收桶對話框——統一回收所有刪除的對話
/// （一般對話/畫布對話/全域對話/+未來手機版）。
/// 以刪除日期分組；可還原；可永久刪除（先警示「刪除後無法恢復」）。
class _TrashDialog extends StatefulWidget {
  final List<TrashItem> trash;
  final Future<void> Function() onRestored;

  const _TrashDialog({required this.trash, required this.onRestored});

  @override
  State<_TrashDialog> createState() => _TrashDialogState();
}

class _TrashDialogState extends State<_TrashDialog> {
  late List<TrashItem> _trash;

  @override
  void initState() {
    super.initState();
    _trash = List.of(widget.trash);
  }

  Future<void> _refresh() async {
    _trash = await ConversationStore.listTrashDetailed();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // 依刪除日期分組（新的日期在前）
    final groups = <String, List<TrashItem>>{};
    for (final item in _trash) {
      final key = _dateLabel(item.deletedAt);
      groups.putIfAbsent(key, () => []).add(item);
    }
    final dayKeys = groups.keys.toList();

    return AlertDialog(
      backgroundColor: BridgeDSColors.of(context).surfaceElevated,
      title: Row(
        children: [
          Icon(Icons.delete_outline, size: 20,
              color: BridgeDSColors.of(context).textPrimary),
          const SizedBox(width: 8),
          Text('回收桶',
              style: TierStyle.of(context, Tier.dialogTitle)
                  .toTextStyle()
                  .copyWith(
                      color: BridgeDSColors.of(context).textPrimary)),
          const Spacer(),
          Text('${_trash.length} 個對話',
              style: TierStyle.of(context, Tier.listItemMeta)
                  .toTextStyle()),
        ],
      ),
      content: SizedBox(
        width: 460,
        height: 480,
        child: _trash.isEmpty
            ? Center(
                child: Text(
                  '回收桶是空的\n（刪除的對話會保留在這裡，除非你永久刪除）',
                  textAlign: TextAlign.center,
                  style: TierStyle.of(context, Tier.dialogBody)
                      .toTextStyle()
                      .copyWith(color: BridgeDSColors.of(context).textMuted),
                ),
              )
            : ListView.builder(
                itemCount: dayKeys.length,
                itemBuilder: (ctx, dayIdx) {
                  final day = dayKeys[dayIdx];
                  final items = groups[day]!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dayIdx > 0) const SizedBox(height: 8),
                      // 日期標題——層級低於列表項（list.item.meta 12/mono）
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Text(
                          day,
                          style: TierStyle.of(context, Tier.listItemMeta)
                              .toTextStyle()
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      for (final item in items)
                        _buildTrashRow(item),
                    ],
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('關閉',
              style: TierStyle.of(context, Tier.buttonSecondary)
                  .toTextStyle()),
        ),
      ],
    );
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return '今天';
    if (d == today.subtract(const Duration(days: 1))) return '昨天';
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  Widget _buildTrashRow(TrashItem item) {
    final conv = item.conversation;
    return ListTile(
      dense: true,
      leading: Icon(Icons.chat_bubble_outline, size: 18,
          color: BridgeDSColors.of(context).textTertiary),
      title: Text(
        conv.title.isEmpty ? '（未命名）' : conv.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TierStyle.of(context, Tier.listItemTitle).toTextStyle(),
      ),
      subtitle: Text(
        '${conv.messages.length} 則訊息 · ${item.deletedAt.hour.toString().padLeft(2, '0')}:${item.deletedAt.minute.toString().padLeft(2, '0')} 刪除',
        style: TierStyle.of(context, Tier.listItemMeta).toTextStyle(),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () async {
              final ok = await ConversationStore.restore(conv.id);
              if (ok) await widget.onRestored();
              await _refresh();
            },
            child: Text('還原',
                style: TierStyle.of(context, Tier.buttonSecondary)
                    .toTextStyle()),
          ),
          // [Blue 令] 永久刪除——先警示，由使用者自己決定
          IconButton(
            icon: Icon(Icons.delete_forever_outlined,
                size: 18, color: BridgeDSColors.of(context).accentRed),
            tooltip: '永久刪除',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor:
                      BridgeDSColors.of(context).surfaceElevated,
                  title: Text('永久刪除？',
                      style: TierStyle.of(context, Tier.dialogTitle)
                          .toTextStyle()
                          .copyWith(
                              color:
                                  BridgeDSColors.of(context).textPrimary)),
                  content: Text(
                    '「${conv.title.isEmpty ? '（未命名）' : conv.title}」刪除後無法恢復。',
                    style: TierStyle.of(context, Tier.dialogBody)
                        .toTextStyle(),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text('取消',
                          style: TierStyle.of(context, Tier.buttonSecondary)
                              .toTextStyle()),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('永久刪除'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ConversationStore.purge(conv.id);
                await _refresh();
              }
            },
          ),
        ],
      ),
    );
  }
}

/// [小葵 2026-09-21 Blue 令] 專案回收桶對話框——日期分組、逐項還原、永久刪除警示。
class _ProjectTrashDialog extends StatefulWidget {
  final List<ProjectTrashSnapshot> snapshots;
  final Future<void> Function() onRestored;

  const _ProjectTrashDialog({required this.snapshots, required this.onRestored});

  @override
  State<_ProjectTrashDialog> createState() => _ProjectTrashDialogState();
}

class _ProjectTrashDialogState extends State<_ProjectTrashDialog> {
  late List<ProjectTrashSnapshot> _snapshots;

  @override
  void initState() {
    super.initState();
    _snapshots = List.of(widget.snapshots);
  }

  Future<void> _refresh() async {
    _snapshots = await ProjectTrashStore.listAll();
    if (mounted) setState(() {});
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return '今天';
    if (d == today.subtract(const Duration(days: 1))) return '昨天';
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _restore(ProjectTrashSnapshot snap) async {
    try {
      // 1. metadata 回 canvases.json（id 已存在則跳過——現行為準）
      final existing = await CanvasStore.getAll();
      final alreadyBack =
          existing.any((c) => c.id == snap.canvasId);
      if (!alreadyBack) {
        await CanvasStore.save(
            CanvasMetadata.fromJson(snap.canvas));
      }

      // 2. 節點回 SQLite（CanvasProps 逐節點 set）
      final nodeStore = SqliteCanvasStateStore();
      final restored = await ProjectTrashStore.restoreNodes(
        snap.canvasId,
        writeNode: (entityId, propsJson) async {
          await nodeStore.set(
              entityId, CanvasProps.fromJson(propsJson));
        },
      );

      // 3. 對話從一般回收桶救回（若還在）
      if (snap.conversationId != null) {
        await ConversationStore.restore(snap.conversationId!);
      }

      // 4. 門重存（若快照有）
      if (snap.door != null) {
        try {
          final door = ProjectDoor.fromJson(snap.door!);
          await ProjectDoorStore().save(door);
        } catch (_) {}
      }

      await widget.onRestored();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已還原「${snap.canvas['title'] ?? '（未命名）'}」（$restored 個節點）')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('還原失敗：$e')),
        );
      }
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<ProjectTrashSnapshot>>{};
    for (final snap in _snapshots) {
      groups.putIfAbsent(_dateLabel(snap.deletedAt), () => []).add(snap);
    }
    final dayKeys = groups.keys.toList();

    return AlertDialog(
      backgroundColor: BridgeDSColors.of(context).surfaceElevated,
      title: Row(
        children: [
          Icon(Icons.delete_outline, size: 20,
              color: BridgeDSColors.of(context).textPrimary),
          const SizedBox(width: 8),
          Text('專案回收桶',
              style: TierStyle.of(context, Tier.dialogTitle)
                  .toTextStyle()
                  .copyWith(
                      color: BridgeDSColors.of(context).textPrimary)),
          const Spacer(),
          Text('${_snapshots.length} 個專案',
              style: TierStyle.of(context, Tier.listItemMeta)
                  .toTextStyle()),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: 480,
        child: _snapshots.isEmpty
            ? Center(
                child: Text(
                  '專案回收桶是空的\n（刪除的專案（畫布）會連同節點、\n對話、專案門一起保留在這裡）',
                  textAlign: TextAlign.center,
                  style: TierStyle.of(context, Tier.dialogBody)
                      .toTextStyle()
                      .copyWith(color: BridgeDSColors.of(context).textMuted),
                ),
              )
            : ListView.builder(
                itemCount: dayKeys.length,
                itemBuilder: (ctx, dayIdx) {
                  final day = dayKeys[dayIdx];
                  final items = groups[day]!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dayIdx > 0) const SizedBox(height: 8),
                      // 日期標題——層級低於列表項（list.item.meta 12/mono）
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Text(
                          day,
                          style: TierStyle.of(context, Tier.listItemMeta)
                              .toTextStyle()
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      for (final snap in items)
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.account_tree_outlined,
                              size: 18,
                              color:
                                  BridgeDSColors.of(context).textTertiary),
                          title: Text(
                            (snap.canvas['title'] as String?)?.isEmpty ?? true
                                ? '（未命名畫布）'
                                : snap.canvas['title'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TierStyle.of(context, Tier.listItemTitle)
                                .toTextStyle(),
                          ),
                          subtitle: Text(
                            '${snap.nodes.length} 個節點'
                            '${snap.conversationId != null ? ' · 含對話' : ''}'
                            ' · ${snap.deletedAt.hour.toString().padLeft(2, '0')}:${snap.deletedAt.minute.toString().padLeft(2, '0')} 刪除',
                            style: TierStyle.of(context, Tier.listItemMeta)
                                .toTextStyle(),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _restore(snap),
                                child: Text('還原',
                                    style: TierStyle.of(
                                            context, Tier.buttonSecondary)
                                        .toTextStyle()),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_forever_outlined,
                                    size: 18,
                                    color: BridgeDSColors.of(context)
                                        .accentRed),
                                tooltip: '永久刪除',
                                onPressed: () async {
                                  final confirmed =
                                      await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor:
                                          BridgeDSColors.of(context)
                                              .surfaceElevated,
                                      title: Text('永久刪除專案？',
                                          style: TierStyle.of(
                                                  context, Tier.dialogTitle)
                                              .toTextStyle()
                                              .copyWith(
                                                  color:
                                                      BridgeDSColors.of(
                                                              context)
                                                          .textPrimary)),
                                      content: Text(
                                        '整個專案（畫布節點、對話、專案門）'
                                        '刪除後無法恢復。',
                                        style: TierStyle.of(
                                                context, Tier.dialogBody)
                                            .toTextStyle(),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(false),
                                          child: Text('取消',
                                              style: TierStyle.of(context,
                                                      Tier.buttonSecondary)
                                                  .toTextStyle()),
                                        ),
                                        TextButton(
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                BridgeDSColors.of(context)
                                                    .accentRed,
                                          ),
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(true),
                                          child: Text('永久刪除',
                                              style: TierStyle.of(context,
                                                      Tier.buttonSecondary)
                                                  .toTextStyle()
                                                  .copyWith(
                                                      color:
                                                          BridgeDSColors.of(
                                                                  context)
                                                              .accentRed)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    await ProjectTrashStore.purge(
                                        snap.canvasId);
                                    await _refresh();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('關閉',
              style: TierStyle.of(context, Tier.buttonSecondary)
                  .toTextStyle()),
        ),
      ],
    );
  }
}

/// [Blue 令 2026-10-05 · 以終為始] 頂列自動適裝量尺
///
/// 量出頂列內容的「自然寬度」（不受視窗約束的需求寬），
/// 上報給 [WindowAutoFitService]——視窗預設＋最小尺寸跟著內容自動長大。
/// 未來按鈕加更多 → 量出的寬更大 → 視窗自動變大 → 警示條絕跡。
class _TopBarAutoFit extends StatefulWidget {
  final Widget child;
  const _TopBarAutoFit({required this.child});

  @override
  State<_TopBarAutoFit> createState() => _TopBarAutoFitState();
}

class _TopBarAutoFitState extends State<_TopBarAutoFit> {
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // 本體：正常畫（受視窗約束）
      widget.child,
      // [小葵 2026-10-05 修] 影子量尺——同一份頂列內容包進 IntrinsicWidth
      // （強迫算 natural width；RenderFlex 支援 computeMinIntrinsicWidth），
      // 量完上報。0 高 + ClipRect = 視覺零成本。
      // 之前 OverflowBox(無限寬) 版本失敗：mainAxisSize.max 在 unbounded
      // 約束下 NEEDS-LAYOUT 永凍（run21 鐵證）。
      Positioned(
        left: 0,
        top: 0,
        child: ClipRect(
          child: SizedBox(
            width: 1,
            height: 1,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              maxWidth: 100000, // 有限超大值——合法佈局，Row 不會 unbounded error
              minHeight: 0,
              maxHeight: 1000,
              child: _ShadowMeasure(
                onChange: (w) => WindowAutoFitService.instance
                    .reportRequiredWidth('top_bar', w),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// 影子量尺——把 child 以無限寬 layout，量出自然寬回呼。
class _ShadowMeasure extends StatefulWidget {
  final Widget child;
  final void Function(double width) onChange;
  const _ShadowMeasure({required this.child, required this.onChange});

  @override
  State<_ShadowMeasure> createState() => _ShadowMeasureState();
}

class _ShadowMeasureState extends State<_ShadowMeasure> {
  final _key = GlobalKey();

  // ★每次 build 後重量（API 儀表板 label 會變寬）——reportRequiredWidth
  // 有 <0.5 防抖 + 800ms debounce，不會造成視窗抖動。
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    return KeyedSubtree(key: _key, child: widget.child);
  }

  void _report() {
    final ctx = _key.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    // ★不走 box.size.width——Row 含 Spacer 時寬度=約束寬（污染值）。
    // 走 RenderFlex children walk：第一個 child 左緣 → 最後 child 右緣，
    // 跳過 zero-size 的 Spacer 佔位（它們在自然寬下=0，左右緣抵銷）。
    double? natural;
    if (box is RenderFlex) {
      // ★自然寬 = Σ 各「連續群組」的寬度。群組 = 相鄰非 flex children
      // （間距 < 300 視為連續）；Spacer/Expanded 撐開的大縫隙（≈100000）
      // 群組切開歸零——run28 鐵證：跨距版把 Spacer 推遠的按鈕算成自然寬。
      // 頂列語意：左群組 + Spacer + 右群組 → 自然寬 = 兩群組寬之和。
      final spans = <double>[]; // 每組 (right - left)
      double? gl; // 組左緣
      double? gr; // 組右緣
      double prevRight = 0;
      RenderBox? child = box.firstChild;
      while (child != null) {
        final ps = child.parentData as FlexParentData?;
        if (ps?.flex == null && child.hasSize && ps?.offset != null) {
          final l = ps!.offset.dx;
          final r2 = l + child.size.width;
          if (gl == null) {
            gl = l; gr = r2;
          } else if (l - prevRight < 300) {
            gr = r2 > gr! ? r2 : gr; // 同組延伸
          } else {
            spans.add(gr! - gl!);
            gl = l; gr = r2;
          }
          prevRight = r2;
        }
        final next = ps?.nextSibling;
        child = next is RenderBox ? next : null;
      }
      if (gl != null && gr != null) spans.add(gr - gl);
      if (spans.isNotEmpty) {
        final sum = spans.reduce((a, b) => a + b);
        // 群組間在自然寬下應有的縫隙：用「非超大」常識值（組間至少留
        // spaceLG）。保守 +spaceLG×(組數−1) 避免貼邊。
        final groupGaps = BridgeDS.spaceLG * (spans.length - 1);
        natural = sum + groupGaps + BridgeDS.spaceLG * 2;
      }
    }
    widget.onChange(natural ?? box.size.width);
  }
}

