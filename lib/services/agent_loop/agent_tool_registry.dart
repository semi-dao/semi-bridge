/// Agent Loop — Tool Registry
///
/// 管理所有可被 AgentLoop 呼叫的工具。
/// 工具來源：
/// 1. BridgeAction adapter（browse/vision/image/document/desktopFiles）
/// 2. BrainContainer 檢索（memory_search）
/// 3. S19 瀏覽器自動化（browser_navigate/browser_screenshot/browser_click）
///
/// 設計原則：
/// - 工具用 name 註冊，LLM 透過 name 呼叫
/// - 未註冊的工具名 = 解析器跳過，AgentLoop 繼續（不 crash）
/// - 工具可以動態新增（未來 Skill 系統可以註冊自訂工具）

import 'agent_tool.dart';
import 'agent_loop_tools/tool_seek_tool.dart'; // [小葵 2026-09-22] 工具櫃檯
// [小葵 2026-09-22] unawaited + debugPrint（櫃檯預熱用）
import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart' show debugPrint;
import 'agent_loop_tools/bridge_action_tool.dart';
import 'agent_loop_tools/memory_search_tool.dart';
import 'agent_loop_tools/use_move_tool.dart'; // [Blue 拍板] 招式工具
import 'agent_loop_tools/compass_tools_agent.dart';
import 'agent_loop_tools/compass_seek_agent_tool.dart';
import 'agent_loop_tools/dream_once_tool.dart'; // [小葵 2026-09-21 R5] 夢境沉思
import 'agent_loop_tools/browser_automation_tool.dart';
import 'agent_loop_tools/screen_capture_tool.dart';
import 'agent_loop_tools/canvas_capture_tool.dart'; // [教練 Agent 2026-08-21] 兩個意識——原生 Agent看見畫布
import 'agent_loop_tools/canvas_look_tool.dart'; // [教練 Agent 2026-08-22] 周邊視覺——場景直感
import 'agent_loop_tools/local_vision_analyze_tool.dart'; // [向量工作流] 本地 Gemma 視覺分析
import 'agent_loop_tools/video_download_tool.dart'; // [影片分析] yt-dlp 下載影片
import 'agent_loop_tools/frame_extract_tool.dart'; // [影片分析] ffmpeg 場景偵測截圖
import 'agent_loop_tools/audio_transcribe_tool.dart'; // [影片分析] Whisper 語音轉文字
import 'agent_loop_tools/local_code_generate_tool.dart'; // [向量工作流] 本地模型程式碼生成
import 'agent_loop_tools/delegate_subagent_tool.dart'; // [向量工作流維度1] 多模型協同——派子代理用外部 LLM
import 'agent_loop_tools/delegate_batch_tool.dart'; // [向量工作流維度1] 批次平行派多個子代理
import 'agent_loop_tools/canvas_remove_tool.dart';
import 'agent_loop_tools/canvas_find_nodes_tool.dart';
import 'agent_loop_tools/check_capability_status_tool.dart';
import 'agent_loop_tools/open_setting_field_tool.dart';
// [Phase 1 2026-07-17] 自維修工具
import 'agent_loop_tools/read_source_file_tool.dart';
import 'agent_loop_tools/patch_source_file_tool.dart';
import 'agent_loop_tools/run_terminal_tool.dart';
import 'agent_loop_tools/read_app_log_tool.dart';
import 'agent_loop_tools/restart_app_tool.dart';
import 'agent_loop_tools/ui_automation_tool.dart';
import 'agent_loop_tools/app_senses_tools.dart'; // [開光 v0.4] 內建感官
import 'mcp_canvas_tools.dart'; // [Phase 0 Track A 2026-07-17] — 不衝突，MCP 版已改名 Mcp 前綴
import 'vault_agent_tools.dart'; // [教練 Agent 2026-07-22] Phase 4 Agent Vault 工具
import 'agent_knowledge_tools.dart'; // [教練 Agent 2026-07-22] Phase E Agent 本地知識庫工具
import 'agent_get_script_tool.dart'; // [搬遷 2026-09-13] 招式全文讀取
import 'agent_workflow_tools.dart'; // [教練 Agent 2026-07-22] Phase F 控制面板整合工具
import '../causal/causal_fork_tool.dart'; // [因果引擎 L4 2026-09-12] 狀態分叉工具
import '../collab/intel_tools.dart'; // [TRIO M2 2026-09-22] 共享情報池工具
import '../collab/swarm_tools.dart'; // [TRIO M4 2026-09-22] 蜂群作戰六關工具
import '../skills/skill_catalog.dart'; // [插槽輕量化 T4 2026-10-13] skill 搜尋/載入工具
import '../skills/skill_tools.dart';
import '../slots/slot_registry.dart'; // [插槽輕量化 T4] 停用卡名單

class AgentToolRegistry {
  final Map<String, AgentTool> _tools = {};

  AgentToolRegistry({List<AgentTool>? tools}) {
    if (tools != null) {
      for (final tool in tools) {
        register(tool);
      }
    }
  }

  /// 預設工具集——使用所有已實作的工具
  ///
  /// [screenCaptureEnabled] — screen_capture feature flag（預設 false，隱私優先）
  /// [screenCaptureExecutor] — screen_capture 執行器（不傳則用 stub）
  factory AgentToolRegistry.withDefaults({
    required dynamic bridgeActionExecutor,
    required dynamic brainContainerService,
    dynamic browserAutomationService,
    bool screenCaptureEnabled = false,
    ScreenCaptureExecutor? screenCaptureExecutor,
    OnNavigateToSetting? onNavigateToSetting,
    McpCanvasExecutor? mcpCanvasExecutor, // [Phase 0 Track A 2026-07-17]
    UiActionExecutor? uiActionExecutor, // [Phase 2 2026-07-18] UI 操作工具
    void Function(String vaultId, String content, String source)?
        vaultSendToCanvasCallback, // [教練 Agent 2026-07-22] Phase 4
  }) {
    final tools = <AgentTool>[];

    // BridgeAction 工具
    tools.add(BrowseTool(bridgeActionExecutor));
    tools.add(VisionTool(bridgeActionExecutor));
    tools.add(GenerateImageTool(bridgeActionExecutor));
    tools.add(DocumentTool(bridgeActionExecutor));
    tools.add(DesktopFilesTool(bridgeActionExecutor));

    // 大腦容器檢索
    tools.add(MemorySearchTool(brainContainerService));
    // 🥋 [Blue 拍板 2026-09-12] 招式工具——對話中使出/查詢訓練AI夥伴錄的招式
    tools.add(UseMoveTool());
    tools.add(ListMovesTool());

    // [三步長肉 Step 3 · 小葵 2026-09-07] 羅盤系統——
    // Agent 動系統前必讀羅盤；規則修改走 propose（白名單制治理）
    tools.add(CompassReadTool());
    tools.add(CompassProposeTool());
    tools.add(CompassSeekTool()); // [小葵 2026-09-10 Blue 令] 目的導向檢索+滾動升級

    // [小葵 2026-09-21 R5] 夢境沉思——反思入生命樹（迴路閉環最後一塊）
    tools.add(DreamOnceTool());

    // [TRIO M2 2026-09-22] 共享情報池——甲踩過的坑乙不用再踩
    tools.add(IntelShareTool());
    tools.add(IntelReadTool());
    tools.add(IntelRefuteTool());

    // [TRIO M4 2026-09-22] 蜂群作戰六關——以終為始＋打破砂鍋＋成本評估
    tools.add(SwarmMusterTool()); // [M5b] 羅盤出陣登記
    tools.add(SwarmOpenTool());
    tools.add(SwarmGatePassTool());
    tools.add(SwarmCommitTool());
    tools.add(SwarmAbortTool());
    tools.add(SwarmCloseTool()); // [M5b] 收兵——AAR+入樹+結案
    tools.add(SwarmStatusTool());

    // 瀏覽器自動化（S19，如果可用）
    if (browserAutomationService != null) {
      tools.add(BrowserNavigateTool(browserAutomationService));
      tools.add(BrowserScreenshotTool(browserAutomationService));
      tools.add(BrowserClickTool(browserAutomationService));
    }

    // Phase 1.5 A3：螢幕感知 + 畫布協作
    // screen_capture 受 feature flag 保護（預設 false，隱私優先）
    tools.add(ScreenCaptureTool(
      executor: screenCaptureExecutor ?? StubScreenCaptureExecutor(),
      enabled: screenCaptureEnabled,
    ));

    // [向量工作流] 本地視覺分析——呼叫本地 Gemma 4 E4B 做圖片分析
    tools.add(LocalVisionAnalyzeTool());

    // [影片分析] 影片下載 + 場景截圖 + 語音轉文字——讓原生 Agent具備完整影片分析能力
    tools.add(VideoDownloadTool());
    tools.add(FrameExtractTool());
    tools.add(AudioTranscribeTool());

    // [向量工作流] 本地模型程式碼生成——原生 Agent寫指令，本地模型寫程式碼，原生 Agent校對修正
    tools.add(LocalCodeGenerateTool());

    // [向量工作流維度1] 多模型協同——派子代理用不同外部 LLM 執行任務
    tools.add(DelegateSubagentTool());

    // [向量工作流維度1] 批次平行派多個子代理——一次派多個子代理同時執行
    tools.add(DelegateBatchTool());

    // [教練 Agent 2026-08-21] 畫布能力盤點整頓——
    // (a) canvas_place 是永遠失敗的 stub（B1 未實作），佔工具名額只會誤導 LLM → 拔。
    // (b) EntityGraph 版 canvas_connect 與 MCP 版同名撞名（參數簽名還不同：
    //     sourceId/targetId vs fromNodeId/fromPort/toNodeId/toPort），後註冊的
    //     蓋掉前面的——agent 呼叫行為取決於註冊順序，不可靠 → 拔 EntityGraph 版，
    //     畫布連線一律走 MCP（= UI 真實顯示狀態）。
    // [教練 Agent 2026-08-18 雙系統修正] canvas_remove 走混合 executor：
    // 精確刪走 MCP（= UI 顯示狀態），模糊查詢仍走 EntityGraph。
    // 避免「建節點走 MCP / 刪節點走 prefs」分裂——原生 Agent刪的 ≠ 你看到的。
    final entityExecForRemove = EntityGraphCanvasRemoveExecutor();
    if (mcpCanvasExecutor != null) {
      tools.add(CanvasRemoveTool.hybrid(mcpCanvasExecutor,
          entityExec: entityExecForRemove));
      tools.add(CanvasFindNodesTool(entityExecForRemove));
      // [教練 Agent 2026-08-21] 兩個意識的橋樑——雙向視覺。
      // 原生 Agent拍畫布→存檔→mediaUrl→agent loop 自動嵌 image_url→
      // vision LLM 看見像素。放好節點後可親眼驗證視覺呈現。
      tools.add(CanvasCaptureTool(executor: mcpCanvasExecutor));
      // [教練 Agent 2026-08-22 使用者洞察] 三層感官——原生 Agent在 App 裡面，
      // 視覺感受應比外部截圖更直接。canvas_look＝周邊視覺：
      // 直接讀畫布狀態組成空間場景描述，零截圖零延遲。
      // canvas_capture＝注視（看生成圖內容才用）。
      tools.add(CanvasLookTool(executor: mcpCanvasExecutor));
    } else {
      tools.add(CanvasRemoveTool(entityExecForRemove));
      tools.add(CanvasFindNodesTool(entityExecForRemove));
    }

    // P0b: Onboarding 引導工具 — 讓 Agent 能查詢設定狀態 + 帶使用者到設定頁
    tools.add(CheckCapabilityStatusTool());
    tools.add(OpenSettingFieldTool(onNavigate: onNavigateToSetting));

    // [Phase 1 2026-07-17] 自維修工具 — 讓 Agent 能讀程式碼、修改、build、重啟
    tools.add(ReadSourceFileTool());
    tools.add(PatchSourceFileTool());
    tools.add(RunTerminalTool());
    tools.add(ReadAppLogTool());
    tools.add(RestartAppTool());

    // [Phase 2 2026-07-18] UI 操作工具 — 讓 Agent 能看見按鈕、使用按鈕、切換頁面
    final uiExecutor = uiActionExecutor ?? StubUiActionExecutor();
    tools.add(UiGetStateTool(uiExecutor));
    tools.add(UiInspectTool(uiExecutor));
    tools.add(UiNavigateTool(uiExecutor));
    tools.add(UiTapTool(uiExecutor));
    // [開光 v0.4 最後一哩 2026-10-01] 內建 loop 直掛開光感官——
    // 同進程直呼 MCP callbacks（app_scroll/語意 app_tap/app_look）
    tools.add(AppScrollSenseTool());
    tools.add(AppTapSenseTool());
    tools.add(AppLookSenseTool());

    // [Phase 0 Track A 2026-07-17] MCP 畫布工具 — 12 端點直接註冊
    // [教練 Agent 2026-07-19] 暫時移除 CanvasGetStateTool——GLM-5.2 在收到其回傳後穩定 hang
    // [教練 Agent 2026-08-17] GLM-5.3 已穩定，重新啟用 canvas_get_state——原生 Agent「先看現狀」的關鍵能力
    // 配合 canvas_find_nodes（模糊查詢）＋ canvas_remove（模糊刪除）三件一組
    if (mcpCanvasExecutor != null) {
      tools.add(CanvasGetStateTool(mcpCanvasExecutor));
      tools.add(CanvasScreenshotTool(mcpCanvasExecutor));
      tools.add(CanvasGetAnnotationsTool(mcpCanvasExecutor));
      tools.add(CanvasAddNodeTool(mcpCanvasExecutor));
      tools.add(McpCanvasConnectTool(mcpCanvasExecutor));
      tools.add(McpCanvasRemoveTool(mcpCanvasExecutor));
      tools.add(CanvasExecuteTool(mcpCanvasExecutor));
      tools.add(CanvasNavigateTool(mcpCanvasExecutor));
      tools.add(CanvasSendChatTool(mcpCanvasExecutor));
      tools.add(CanvasListTool(mcpCanvasExecutor));
      tools.add(CanvasLoadTool(mcpCanvasExecutor));
      // [教練 Agent 2026-07-22] Phase C — Agent 畫布快捷工具
      tools.add(CanvasGetTopologyTool(mcpCanvasExecutor));
      tools.add(CanvasBatchConnectTool(mcpCanvasExecutor));
      tools.add(CanvasLoadTemplateTool(mcpCanvasExecutor));
      tools.add(CanvasHighlightNodeTool(mcpCanvasExecutor));
      tools.add(CanvasPanToNodeTool(mcpCanvasExecutor));
      // [教練 Agent 2026-07-24] 人機共視工具 — CanvasSnapshot
      tools.add(CanvasGetSnapshotTool(mcpCanvasExecutor));
      tools.add(CanvasMoveNodeTool(mcpCanvasExecutor));
      // [教練 Agent 2026-08-26 使用者 基礎規則] 一鍵自動排版——發現重疊直接修
      tools.add(CanvasAutoLayoutTool(mcpCanvasExecutor));
      // [因果引擎 L4 2026-09-12] 狀態分叉——可執行的反事實（快照→干預→diff→還原）
      tools.add(CausalForkTool(mcpCanvasExecutor));
      tools.add(CanvasDetectCrossingsTool(mcpCanvasExecutor));
      // [教練 Agent 2026-08-16 使用者要求 3] 畫布操盤工具——
      // 白話指令 → 原生 Agent改既有節點內容（改 prompt/label/選項）
      tools.add(CanvasUpdateNodeTool(mcpCanvasExecutor));
      tools.add(CanvasGetNodeParamsTool(mcpCanvasExecutor));
    }

    // [教練 Agent 2026-07-22] Phase 4 — Agent Vault 工具
    tools.add(VaultSearchTool());
    tools.add(VaultGetTagsTool());
    // VaultSendToCanvasTool 需要畫布回呼，在桌面畫面層級注入
    if (vaultSendToCanvasCallback != null) {
      tools.add(VaultSendToCanvasTool(onSendToCanvas: vaultSendToCanvasCallback));
    }

    // [教練 Agent 2026-07-22] Phase E — Agent 本地知識庫工具
    tools.add(AgentSearchKnowledgeTool());
    tools.add(AgentSaveScriptTool());
    tools.add(AgentSaveMemoryTool());
    // [搬遷 2026-09-13] 招式全文讀取——搜得到還要讀得到（兩階段檢索第二階）
    tools.add(AgentGetScriptTool());

    // [教練 Agent 2026-07-22] Phase F — 控制面板整合工具
    tools.add(AgentApplyWorkflowTool());
    tools.add(CanvasListTemplatesTool());

    // [插槽輕量化 Task 4 2026-10-13] skill_search/skill_load——
    // 「需要時會想起」本體：metadata 目錄常駐、body 磁碟懶載入。
    // 停用接線：SlotRegistry 非 running 的 skill 卡 → 搜尋/載入一律排除。
    final skillCatalog = SkillCatalog.instance;
    Set<String> disabledSkillNames() =>
        SkillTools.disabledSkillNames(SlotRegistry.instance);
    tools.add(SkillSearchTool(skillCatalog,
        disabledNamesProvider: disabledSkillNames));
    tools.add(SkillLoadTool(skillCatalog,
        disabledNamesProvider: disabledSkillNames));

    // [教練 Agent 2026-08-17 Token 樹精簡] tool_help 隨需查詢——註冊後自引用
    final registry = AgentToolRegistry(tools: tools);
    registry.register(ToolHelpTool(registry));
    // [小葵 2026-09-22 Blue 設計] 工具櫃檯——向量遞工具（prompt 工具區
    // 從 8.5K 型錄縮成一行指引）
    final toolSeek = CompassToolSeekTool(registry);
    registry.register(toolSeek);
    unawaited(_warmToolSeek(toolSeek));
    return registry;
  }

  /// [小葵 2026-09-22] 預熱工具向量快取——embedding 模型沒就緒時
  /// 靜默跳過（櫃檯退關鍵字比對，能力不滅只是精度降）
  static Future<void> _warmToolSeek(CompassToolSeekTool toolSeek) async {
    try {
      await toolSeek.warmup();
    } catch (e) {
      debugPrint('[ToolSeek] 預熱跳過: $e');
    }
  }

  void register(AgentTool tool) {
    _tools[tool.name] = tool;
  }

  AgentTool? get(String name) => _tools[name];

  bool has(String name) => _tools.containsKey(name);

  List<AgentTool> get all => _tools.values.toList();

  /// 產生給 system prompt 的工具描述列表
  ///
  /// [教練 Agent 2026-08-17 Token 樹精簡] 分層說明書——常駐 prompt 只放
  /// 工具名＋一句話用途＋參數名（* = 必填）。參數細節呼叫 tool_help 查。
  String toPromptSection() {
    // [小葵 2026-09-22 Blue 設計] 工具區從型錄變櫃檯——
    // 舊：36 工具一句話簡介全塞（8.5K chars/輪）。
    // 新：一行指引，Agent 帶意圖問 compass_toolseek（本地向量，零 token），
    // 精靈遞完整用法。tool_help 保留為 fallback（embedding 不可用時）。
    return '''
## 工具
格式：<<<tool_call>>>{"name":"工具名","args":{...}}<<<tool_call_end>>>。可文字+工具呼叫並行；看結果後可繼續呼叫；任務完成直接回覆（不嵌 tool_call）。

你不預載工具清單。要做事時：先呼叫 compass_toolseek 帶上你想做的事（intent），精靈會遞給你最相關的工具與完整用法（含參數）。遞的不合用就換個說法再問——每次遞送都有記錄，拿錯的經驗會變成精靈調校的養分。embedding 不可用時改用 tool_help 查清單。

常用快捷（免查）：canvas_place（放節點）／canvas_look（看畫布）／compass_read（讀羅盤器官）／generate_image（畫圖）／web_search（搜尋）。
''';
  }
}


/// [教練 Agent 2026-08-17 Token 樹精簡] tool_help——隨需查詢工具完整說明。
/// prompt 常駐區只放一句話簡介，LLM 需要參數細節時呼叫此工具，
/// 回傳該工具的 toFullDescription()。
class ToolHelpTool extends AgentTool {
  final AgentToolRegistry registry;
  ToolHelpTool(this.registry);

  @override
  String get name => 'tool_help';

  @override
  String get description => '查詢某工具的完整參數說明。呼叫任何工具前如果不確定參數格式，先用這個查。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'tool_name',
          description: '工具名稱，例如 canvas_place',
          required: true,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final toolName = args['tool_name'] as String?;
    if (toolName == null || toolName.trim().isEmpty) {
      return AgentToolResult.failure(
        '請提供 tool_name 參數。可用工具：${registry.all.map((t) => t.name).join(", ")}',
      );
    }
    final tool = registry.get(toolName.trim());
    if (tool == null) {
      return AgentToolResult.failure(
        '找不到工具「$toolName」。可用工具：${registry.all.map((t) => t.name).join(", ")}',
      );
    }
    return AgentToolResult.success(tool.toFullDescription());
  }
}
