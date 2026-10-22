// [以利沙 Sprint 8 Step 1 2026-06-24]
// ChatController 骨架 — 只宣告業務 State 變數，不移任何業務邏輯。
// 所有變數從 chat_screen.dart _ChatScreenState 原樣複製，
// 等後續 Step 逐步搬移邏輯過來。
// ignore_for_file: unused_field, prefer_final_fields

import 'dart:async';
import 'dart:convert'; // [以利沙 Sprint 8 Step 3 2026-06-24]
import 'dart:developer' as developer; // [以利沙 Sprint 8 Step 4 2026-06-24]
import 'dart:io'; // [以利沙 Sprint 8 Step 6 2026-06-24]
// [教練 Agent 2026-08-03] Quick Assistant mode
import '../services/quick_assistant/quick_assistant_context.dart';

import 'package:dio/dio.dart'; // [以利沙 Sprint 8 Step 6 2026-06-24]
import 'package:file_picker/file_picker.dart'; // [以利沙 Sprint 8 Step 6 2026-06-24]
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'; // [以利沙 P1 修復十五輪 2026-06-27] WidgetsBinding.addPostFrameCallback

import '../models/agent_activity.dart';
import '../models/bridge_action.dart'; // [以利沙 Sprint 8 Step 3 2026-06-24]
import '../models/capability_catalog.dart';
import '../models/chat_card_data.dart';
import '../models/capability_advisor.dart'; // [以利沙 Capability Advisor 2026-06-25]
import '../models/companion.dart';
import '../models/conversation.dart';
import '../models/task_evidence.dart'; // P0.5 對話任務證據
import '../services/tasks/task_dispatcher.dart'; // [隊友訊息流 C2]
import '../services/chat_modes.dart'; // [聊天模式 B 線 2026-10-20 Blue 拍板]
import '../services/memory_layer_service.dart'; // [H2/M3 2026-10-07] 記憶2域10層分層注入
import '../services/collab/meeting_layer.dart'; // [TRIO M3.5 2026-09-22] 會議接線
import '../services/collab/intel_pool.dart'; // [TRIO M3.5] 情報池（會議紀錄入池）
import '../services/tasks/task_session.dart'; // [隊友訊息流 C2]
import '../services/trust/trust_loop.dart'; // [刀 6 K6.6]
import '../models/canvas/canvas_metadata.dart';
import '../models/digital_asset.dart'; // [以利沙 Sprint 8 Step 3 2026-06-24]
import '../models/entity_graph/entity.dart';
import '../models/flow_step.dart';
import '../models/intent_spine.dart'; // [以利沙 Sprint 8 Step 6 2026-06-24]
import '../models/project_door.dart';
import '../models/second_brain_file_index.dart';
import '../models/second_brain_trace.dart';
import '../models/transurfing_brain.dart';
import '../services/agent_activity_store.dart'; // [以利沙 Sprint 8 Step 5 2026-06-24]
import '../widgets/bridge_cards/companion_status_helper.dart'; // [教練 Agent 2026-07-03] 關鍵字觸發
import '../services/agent_motivation_engine.dart';
import '../services/api_service.dart'; // [以利沙 Sprint 8 Step 6 2026-06-24]
import '../services/brain_progress_store.dart'; // [以利沙 Sprint 8 Step 6 2026-06-24]
import '../services/brain_reflection_store.dart'; // [以利沙 Sprint 8 Step 3 2026-06-24]
import '../services/bridge_consciousness.dart'; // [以利沙 Sprint 8 Step 6 2026-06-24]
import '../services/brain_container/brain_container_service.dart'; // [教練 Agent 2026-07-03]
import '../services/brain_container/transurfing_engine.dart'; // [教練 Agent 2026-08-08] Transurfing 水流追蹤
import '../services/brain_container/extraction/smart_memory_extractor.dart'; // [教練 Agent 2026-07-03] 慢車道 LLM 提取
import '../services/brain_container/extraction/dream_buffer.dart'; // [小葵 2026-09-22 偷學令③] Dreaming 緩衝層
import '../services/memory_guard_service.dart'; // [教練 Agent 2026-07-22] #4 L1 記憶體自管
import '../services/brain_pipeline/brain_container.dart'; // [教練 Agent Sprint 2 2026-07-04]
import '../services/brain_pipeline/intention_router.dart'; // [教練 Agent Sprint 2 2026-07-04]
import '../services/brain_pipeline/audit/audit_store.dart'; // [教練 Agent 2026-07-05] 擺錘週報
import '../services/brain_pipeline/heart_mind/heart_mind_dialogue.dart'; // [教練 Agent 2026-07-05] 心腦合一
import '../services/brain_pipeline/heart_mind/heart_mind_store.dart'; // [教練 Agent 2026-07-05] 心腦合一 store
import '../services/brain_pipeline/pipeline/transurfing_pipeline.dart'; // [以利沙 Sprint 11 Part B] pipeline 接入
import '../services/brain_pipeline/pipeline_result.dart'; // [以利沙 Sprint 11 Part B] PipelineResult 型別
import '../services/brain_pipeline/production_pipeline_llm_client.dart'; // [以利沙 Sprint 11 Part B] 生產 LLM client
import '../services/semantic_intent/semantic_intent_service.dart'; // [教練 Agent Sprint 1.2] 語意理解服務
import '../services/semantic_intent/semantic_result.dart'; // [Phase 2] RoutingIntentResult
import '../services/semantic_intent/conversation_history_provider.dart'; // [教練 Agent Sprint 1.2] 歷史提取
import '../models/brain_container/memory_source.dart'; // [教練 Agent 2026-07-03]
import '../services/companion_runtime_store.dart'; // [以利沙 Sprint 8 Step 5 2026-06-24]
import '../services/vault/template_tutorial_service.dart'; // [教練 Agent 2026-07-22] Phase 5+ 教學攔截
import '../services/vault/canvas_snapshot_service.dart'; // [教練 Agent 2026-07-22] Phase B 畫布快照
import '../services/companion_store.dart'; // [以利沙 Sprint 8 Step 5 2026-06-24]
import '../services/bridge_action_execution_decision_service.dart'; // [以利沙 Sprint 8 Step 6 2026-06-24]
import '../services/bridge_action_execution_evidence.dart';
import '../services/bridge_action_executor.dart';
import '../services/bridge_action_progress.dart';
import '../services/capability_catalog_service.dart';
import '../services/capability_health_service.dart';
import '../services/capability_advisor_service.dart'; // [以利沙 Capability Advisor 2026-06-25]
import '../services/chat_intent_router.dart'; // [以利沙 Sprint 8 Step 6 2026-06-24]
import '../services/digital_asset_registry_store.dart';
import '../services/door_decision_store.dart';
import '../services/intent_spine_service.dart'; // [以利沙 Sprint 8 Step 6 2026-06-24]
import '../services/managed_folder_guard_store.dart';
import '../services/managed_folder_rule_namer.dart';
import '../services/managed_folder_rule_store.dart';
import '../services/bridge_adapters/local_desktop_files_adapter.dart'; // [以利沙 Sprint 8 Step 4 2026-06-24]
import '../services/conversation_store.dart'; // [以利沙 Sprint 8 Step 2 2026-06-24]
import '../services/memory_store.dart';
import '../services/pending_bridge_task_store.dart';
import '../services/project_door_signal_service.dart'; // [以利沙 Sprint 8 Step 3 2026-06-24]
import '../services/project_door_store.dart';
import '../services/second_brain_file_index_store.dart';
import '../services/second_brain_folder_import_service.dart';
import '../services/second_brain_trace_service.dart';
import '../services/transurfing_brain_service.dart';
import '../services/intent_classifier.dart';
import '../services/storage_service.dart'; // [以利沙 P0 修復十一輪 2026-06-27]
import '../services/provider_router.dart'; // [教練 Agent 2026-07-22] 動態 Agent 路由
import '../services/memory_recall_service.dart'; // [教練 Agent 2026-07-25] 記憶回溯
import '../services/agent_loop/agent_knowledge_service.dart'; // [教練 Agent 2026-07-22] Phase E
import '../services/agent_loop/persona_inference_service.dart'; // [教練 Agent 2026-07-22] Phase H 人格推理
import '../services/onboarding/folder_scanner_service.dart'; // [教練 Agent 2026-07-22] Phase H 資料夾掃描
import '../services/brain_container/brain_database.dart'; // [教練 Agent 2026-07-22] Phase H DB 路徑
import '../services/brain_container/embedding/embedding_service.dart'; // [教練 Agent 2026-07-22] embedding for knowledge retrieval
import 'package:shared_preferences/shared_preferences.dart'; // [以利沙 修復二十輪 2026-06-27] _unlockedCapabilities 持久化

// [教練 Agent S21] Agent Loop
import '../services/agent_loop/agent_loop.dart';
import '../services/agent_loop/agent_tool_registry.dart';
import '../services/agent_loop/mcp_canvas_tools.dart'; // [Phase 0 Track A 2026-07-17]
import '../widgets/canvas/v2/canvas_mcp_registry.dart'; // [教練 Agent 2026-07-20] 渲染感應器
import '../services/agent_loop/agent_tool_call_parser.dart';
import '../services/agent_loop/agent_loop_tools/delegate_subagent_tool.dart' as delegate_subagent_tool;
import '../services/agent_loop/agent_loop_tools/entity_graph_canvas_place_executor.dart';
import '../services/agent_loop/agent_loop_tools/open_setting_field_tool.dart';
import '../services/canvas_store.dart';
import '../services/entity_graph/entity_graph_service.dart';
import '../services/agent_loop/agent_loop_tools/flutter_self_capture_executor.dart';
import '../services/agent_loop/agent_loop_tools/mac_screen_capture_executor.dart'; // 保留 import 避免 breaking，但不再使用
import '../services/agent_loop/agent_loop_prompt_builder.dart';
import '../services/agent_loop/m2_persona_service.dart'; // [T4②] M2 語氣層
import '../services/agent_loop/production_agent_loop_llm_client.dart';

// [教練 Agent 2026-07-30 Phase 4] 自訂調用原則
import '../services/agent_loop/policy_generator.dart';
import '../services/agent_loop/custom_routing_policy.dart';
import '../services/agent_loop/agent_profile_store.dart';
import '../widgets/policy_confirm_dialog.dart';

// [教練 Agent S20] Skills 系統
import '../services/skills/skill_prompt_injector.dart';
import '../services/paid_action_gate.dart';
import '../services/causal/causal_ledger_service.dart'; // [因果引擎 L2] 證據等級
import '../services/causal/time_sense_service.dart'; // [時間感 L2] 相遇時間軸
import '../services/life_tree/life_tree_store.dart'; // [2026-10-05] 對話自動裁決夢卡
import '../services/agent_loop/agent_loop_tools/tool_seek_tool.dart'
    show CompassToolSeekTool; // [小葵 2026-10-01] 本地士兵配備
import '../services/correction_catcher.dart'; // [小葵 2026-10-14 M3] 修正捕手
import '../services/calibration_breaker.dart'; // [小葵 2026-10-14 M3] 校準熔斷
import '../services/brain_container/event_ledger.dart'; // [小葵 2026-10-14 M3] reaction 落盤

/// [以利沙 Sprint 8 Step 1 2026-06-24]
/// ChatController 骨架。
///
/// 目前只包含從 _ChatScreenState 複製過來的業務 State 變數宣告。
/// 不含任何方法、不含任何邏輯。
/// 後續 Step 會逐步把 initState、業務方法搬移到此處。
class ChatController extends ChangeNotifier {
  // [教練 Agent 2026-08-03] Quick Assistant 模式 — Cmd+K 開啟時填入，關閉時清空
  QuickAssistantContext? _quickAssistantContext;

  /// 取得當前 Quick Assistant context（給 system prompt builder 用）
  QuickAssistantContext? get quickAssistantContext => _quickAssistantContext;

  /// 是否在 Quick Assistant 模式
  bool get isQuickAssistantMode => _quickAssistantContext != null;

  /// 進入 Quick Assistant 模式
  void enterQuickAssistantMode(QuickAssistantContext context) {
    _quickAssistantContext = context;
    notifyListeners();
  }

  /// 離開 Quick Assistant 模式
  void exitQuickAssistantMode() {
    _quickAssistantContext = null;
    notifyListeners();
  }

  // [教練 Agent 2026-07-19] App 自拍 key——由外層傳入，用於 FlutterSelfCaptureExecutor
  GlobalKey? _selfCaptureKey;

  /// 設定 App 自拍的 RepaintBoundary key。
  /// 必須在使用者發訊息前（initState 後）由 UI 層呼叫。
  void setSelfCaptureKey(GlobalKey key) {
    _selfCaptureKey = key;
  }
  // ──────────────────────────────────────────────
  // 對話與基本狀態
  // ──────────────────────────────────────────────

  // [以利沙 Sprint 8 Step 1 2026-06-24]
  List<Conversation> _conversations = [];
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  Conversation? _currentConversation;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _isLoading = false;
  // [教練 Agent 2026-07-22] Phase H — 回覆指定訊息的目標
  Message? _replyTarget;

  /// [教練 Agent 2026-08-03] 公開 getter — UI 讀取目前回覆目標用於 banner
  Message? get replyTarget => _replyTarget;

  /// UI 設定回覆目標（chat_screen / desktop_chat_panel 點擊「回覆」按鈕時呼叫）
  void setReplyTarget(Message? msg) {
    _replyTarget = msg;
    notifyListeners(); // [教練 Agent 2026-08-03] 通知桌面/行動 banner 重建
  }

  /// UI 取消回覆
  void clearReplyTarget() {
    _replyTarget = null;
    notifyListeners(); // [教練 Agent 2026-08-03] 同步通知
  }

  // [教練 Agent 2026-06-28] 修復：API 失敗自動重試計數器
  int _retryCount = 0;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _showSidebar = false;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _showCompanionStatusTest = false;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  int _totalTokens = 0;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  String _currentMode = '💬 閒聊';
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  UserIntent? _manualIntent; // 手動覆蓋自動分類
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _showSkillPanel = false; // 顯示 Skill 快捷面板
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _showCompanionPresence = true;

  // [以利沙 P1 修復二十一輪 2026-06-27] 本地模型狀態快取（供 AppBar badge 同步讀取）
  String? _cachedGatewayUrl;

  /// 是否正在使用本地模型（依 Gateway URL 判斷）。
  /// build() 同步呼叫，使用 _cachedGatewayUrl 快取；由 refreshLocalModelState() 更新。
  bool get isUsingLocalModel {
    final base = (_cachedGatewayUrl ?? '').toLowerCase();
    if (base.isEmpty) return false;
    // 取出 host 部分（去掉 scheme 與 path），避免 path/版本號誤判私有網段
    final host = base
        .replaceFirst(RegExp(r'^https?://'), '')
        .split('/')
        .first
        .split(':')
        .first;
    if (base.contains('127.0.0.1') ||
        base.contains('localhost') ||
        base.contains('18789') ||
        base.contains('11434') ||
        base.contains('ollama')) {
      return true;
    }
    // 私有網段（RFC1918）精確前綴判斷
    return host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2[0-9]|3[0-1])\.').hasMatch(host);
  }

  /// [以利沙 P1 修復二十一輪 2026-06-27] 重新讀取 Gateway URL 並更新本地模型快取。
  /// 應在畫面初始化與切換模型後呼叫。
  Future<void> refreshLocalModelState() async {
    final url = await StorageService.getGatewayUrl();
    if (url != _cachedGatewayUrl) {
      _cachedGatewayUrl = url;
      notifyListeners();
    }
  }

  // ──────────────────────────────────────────────
  // 語音輸入
  // ──────────────────────────────────────────────

  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _speechAvailable = false;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _speechInitializing = false;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _speechListening = false;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  int? _speechReplaceStart;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  int? _speechReplaceEnd;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  String? _speechContinuationPrefix;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  String _speechLastRecognizedWords = '';
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _applyingSpeechResult = false;

  // ──────────────────────────────────────────────
  // 夥伴選擇器請求
  // ──────────────────────────────────────────────

  // [以利沙 第十六輪修復 2026-06-27]
  bool _pendingCompanionPickerRequest = false;
  bool get pendingCompanionPickerRequest => _pendingCompanionPickerRequest;
  void clearCompanionPickerRequest() {
    _pendingCompanionPickerRequest = false;
    notifyListeners();
  }

  // [以利沙 P0 修復十七輪 2026-06-27] 交接說明暫存，下次 sendMessage 時注入 system prompt（只注入一次）
  String? _pendingHandoffNote;

  // [以利沙 P0 修復十九輪 2026-06-27] 跨 Agent 記憶橋接：前一位 companion 的 id
  String? _prevCompanionId;

  // [以利沙 P1 修復十九輪 2026-06-27] 直接點名切換的預選目標
  String? _pendingAutoSwitchTarget;
  String? get pendingAutoSwitchTarget => _pendingAutoSwitchTarget;
  void clearPendingAutoSwitchTarget() => _pendingAutoSwitchTarget = null;

  // ──────────────────────────────────────────────
  // Memory Flash
  // ──────────────────────────────────────────────

  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _showMemoryFlash = false;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  String? _memoryFlashText;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  Timer? _memoryFlashTimer;

  // ──────────────────────────────────────────────
  // 大腦脈動 / 思考動畫
  // ──────────────────────────────────────────────

  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _brainPulse = false;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  AgentActivityStage? _thoughtStage;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  Timer? _thoughtPulseTimer;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _thoughtPulse = false;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  AgentActivityTelemetry _thoughtTelemetry = const AgentActivityTelemetry();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  AgentActivityStage? _lastBrainActionStage;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  AgentActivityTelemetry _lastBrainActionTelemetry =
      const AgentActivityTelemetry();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  String? _activeBridgeActionLabel;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  String? _lastBridgeActionLabel;
  // [教練 Agent P0.5b 2026-08-07] 圖片任務真實進度 label
  String? _imageProgressLabel;
  // [教練 Agent P0.5b 2026-08-08] 圖片任務進度事件序列——讓 UI 可以顯示完整流程
  final List<BridgeActionProgressEvent> _imageProgressEvents = [];
  List<BridgeActionProgressEvent> get imageProgressEvents =>
      List.unmodifiable(_imageProgressEvents);

  // ──────────────────────────────────────────────
  // Service 實例
  // ──────────────────────────────────────────────

  // [以利沙 Sprint 8 Step 1 2026-06-24]
  // [教練 Agent 2026-07-04] 改為可注入，讓測試 mock 能接通
  BridgeActionExecutor _bridgeActionExecutor = BridgeActionExecutor();

  /// 由 ChatScreen initState 注入，確保 Screen 和 Controller 共用同一個 instance。
  set bridgeActionExecutor(BridgeActionExecutor value) {
    _bridgeActionExecutor = value;
    _subscribeImageProgress(value);
  }

  /// 讓 ChatScreen 的 auto-resume 路徑也能使用同一個 instance。
  BridgeActionExecutor get bridgeActionExecutor => _bridgeActionExecutor;

  // [教練 Agent P0.5b 2026-08-07] 訂閱 executor 的 progressStream，
  // 把圖片任務真實進度事件轉成 UI 可讀 label。
  StreamSubscription<BridgeActionProgressEvent>? _imageProgressSub;
  void _subscribeImageProgress(BridgeActionExecutor executor) {
    _imageProgressSub?.cancel();
    _imageProgressSub = executor.progressStream.listen((event) {
      _imageProgressLabel = event.userLabel;
      _imageProgressEvents.add(event);
      // 保留最近 8 個事件，避免無限增長
      if (_imageProgressEvents.length > 8) {
        _imageProgressEvents.removeAt(0);
      }
      notifyListeners();
    });
  }

  /// [教練 Agent P0.5b-fix 2026-08-07] 確保 default executor 也訂閱 progressStream。
  /// Desktop Chat Panel 不注入 executor，用 default instance 時也需要進度事件。
  void ensureProgressSubscription() {
    if (_imageProgressSub == null) {
      _subscribeImageProgress(_bridgeActionExecutor);
    }
  }
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  final _bridgeActionEvidence = const BridgeActionExecutionEvidence();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  final _pendingBridgeTaskStore = const PendingBridgeTaskStore();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  final _doorDecisionStore = const DoorDecisionStore();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  final _projectDoorStore = const ProjectDoorStore();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  final _digitalAssetRegistry = const DigitalAssetRegistryStore();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  final _managedFolderRuleStore = const ManagedFolderRuleStore();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  final _managedFolderGuardStore = const ManagedFolderGuardStore();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  final _managedFolderRuleNamer = const ManagedFolderRuleNamer();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  final _transurfingBrain = const TransurfingBrainService();
  // [教練 Agent Sprint 2 2026-07-04] 宣告/確認/行動閉環路由器
  IntentionRouter? _intentionRouter;
  IntentionRouter? get intentionRouter => _intentionRouter;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  final _secondBrainFileIndexStore = const SecondBrainFileIndexStore();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  final _secondBrainTraceService = const SecondBrainTraceService();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  final _secondBrainFolderImportService =
      const SecondBrainFolderImportService();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  final _agentMotivationEngine = const AgentMotivationEngine();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  late final _capabilityCatalog = CapabilityCatalogService();
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  late final _capabilityHealth = CapabilityHealthService();
  // [以利沙 Capability Advisor 2026-06-25]
  late final _capabilityAdvisor = CapabilityAdvisorService(
    healthService: _capabilityHealth,
  );
  // [以利沙 Capability Advisor 2026-06-25]
  CapabilityAdvisorCardData? _activeAdvisorCard;
  // [以利沙 P2 修復 2026-06-27] advisor 完成後無限循環防護
  bool _skipNextCapabilityGapDetect = false;
  // [以利沙 P0 修復十一輪 2026-06-27] 已永久開通的能力類型快取
  // [以利沙 修復二十輪 2026-06-27] 改為非 final，支援 _loadUnlockedCapabilities 重新賦值
  Set<String> _unlockedCapabilities = {};

  // ──────────────────────────────────────────────
  // 大腦反思 / 第二大腦
  // ──────────────────────────────────────────────

  // [以利沙 Sprint 8 Step 1 2026-06-24]
  BrainReflection? _brainReflection;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _showBrainReflectionPanel = false;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  DoorDecisionPendingReturn? _pendingDoorReturn;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  List<String> _recalledBrainInsights = [];
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  SecondBrainTrace? _secondBrainTrace;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  BrainSkillRegistrySnapshot? _brainSkillRegistry;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  AgentMotivationSnapshot? _agentMotivation;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  Map<String, TransurfingInsightFeedback> _insightFeedbacks = {};
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  Map<String, SecondBrainMemoryFeedback> _secondBrainMemoryFeedbacks = {};
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  Map<String, SecondBrainAssociationFeedback> _secondBrainAssociationFeedbacks =
      {};
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  Map<String, SecondBrainRoom> _secondBrainMemoryRoomOverrides = {};
  // [教練 Agent 2026-07-05] 擺錘審計 store + 心腦合一對話
  final AuditStore _auditStore = AuditStore();
  // [教練 Agent 2026-07-05] 心腦合一對話（延遲初始化，需 PipelineLLMClient）
  HeartMindDialogue? _heartMindDialogue;

  // [以利沙 Sprint 11 Part B] Pipeline 接入
  TransurfingPipeline? _pipeline;
  ProductionPipelineLLMClient? _pipelineLlmClient;
  bool _pipelineEnabled =
      true; // feature flag（SharedPreferences key: pipeline_enabled）——預設開啟（Sprint 12）

  // [教練 Agent Sprint 1.2] 語意理解服務（延遲初始化，共用 pipeline 的 LLM client）
  SemanticIntentService? _semanticIntentService;
  bool _semanticIntentInited = false;

  // ── [教練 Agent S21] Agent Loop 接入 ──────────────────────
  AgentLoop? _agentLoop;
  AgentToolRegistry? _agentToolRegistry;
  bool _agentLoopEnabled =
      false; // feature flag（SharedPreferences key: agent_loop_enabled）
  bool _agentLoopInited = false;
  String? _agentLoopInitError; // [教練 Agent 2026-08-09] init 失敗原因

  /// Agent Loop 進度回調（UI 層設定，用來顯示每輪工具呼叫）
  void Function(
    int turnIndex,
    int maxTurns,
    String? toolName,
    String? toolStatus,
    String llmSnippet,
  )?
  onAgentLoopProgress;

  /// [教練 Agent 2026-08-07] 即時階段回饋——Agent Loop 的 thinking/tool_start/timeout 等
  void Function(
    String stage, {
    String? toolName,
    String? detail,
  })?
  onAgentLoopStage;

  /// [D002 2026-08-10] 工具確認回調——破壞性操作前暫停等使用者確認
  /// UI 層設定此回調，收到時顯示確認對話框（破壞性操作加紅字警告）
  /// 回傳 true = 確認執行；false = 拒絕
  /// [D002 2026-08-10] 使用 setter 同步到 _agentLoop 實例欄位
  Future<bool> Function({
    required String toolName,
    required Map<String, dynamic> args,
  })? _onToolConfirmation;

  Future<bool> Function({
    required String toolName,
    required Map<String, dynamic> args,
  })? get onToolConfirmation => _onToolConfirmation;

  set onToolConfirmation(Future<bool> Function({
    required String toolName,
    required Map<String, dynamic> args,
  })? value) {
    _onToolConfirmation = value;
    _agentLoop?.onToolConfirmation = value;
  }

  /// P0b: Agent 導航回調 — 讓 Agent 能帶使用者到設定頁
  /// UI 層（DesktopChatPanel / ChatScreen）設定此回調來接收導航請求。
  OnNavigateToSetting? onNavigateToSetting;

  /// [Phase 0 Track A 2026-07-17] MCP 畫布執行器 — 讓 Agent Loop 能操作畫布
  /// 由 UI 層設定，傳入 McpCanvasExecutor 實作。
  McpCanvasExecutor? mcpCanvasExecutor;

  // ──────────────────────────────────────────────
  // 專案門 / Bridge Action
  // ──────────────────────────────────────────────

  // [以利沙 Sprint 8 Step 1 2026-06-24]
  ProjectDoorCardData? _lastProjectDoorJudgement;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  AgentCompanionMood? _companionMoodOverride;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  AgentCompanionAction? _companionActionOverride;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  PendingBridgeTask? _pendingBridgeTask;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  ProjectDoor? _activeProjectDoor;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  List<ProjectDoor> _projectDoors = const [];
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  List<ManagedFolderRule> _managedFolderRules = const [];
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _managedFolderGuardChecking = false;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  bool _autoResumingPendingTask = false;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  String? _selectedMessageId;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  String? _selectedMessageText;
  // [以利沙 Sprint 8 Step 1 2026-06-24]
  final Set<String> _completedDocumentWorkflowActions = {};

  // ──────────────────────────────────────────────
  // Companion
  // ──────────────────────────────────────────────

  // [以利沙 Sprint 8 Step 1 2026-06-24]
  Companion? _activeCompanion;

  /// [2026-08-27 共視修復] 自動建對話通知——sendMessage 在空白狀態兜底
  /// 建立新對話時通知 UI 層（側欄即時刷新）。手動新增本就有通知，
  /// 這裡補的是「直接發話自動建對話」這條路。
  VoidCallback? onConversationAutoCreated;

  // ──────────────────────────────────────────────
  // 記憶回溯 — [教練 Agent 2026-07-25] 方案 A
  // ──────────────────────────────────────────────
  MemoryRecallSession _recallSession = const MemoryRecallSession();

  /// [2026-08-26 身份污染追根] 公開唯讀——UI 同步顯示用
  Companion? get activeCompanionInstance => _activeCompanion;

  /// 記憶回溯：偵測失憶抱怨，搜尋完整歷史，回傳 system note（或 null）
  String? _checkMemoryRecall(String userMessage, List<Message> allMessages) {
    final now = DateTime.now();

    // 檢查回溯 session 是否過期（5 分鐘無新抱怨 = 結束）
    if (_recallSession.isActive && _recallSession.lastActiveAt != null) {
      final elapsed = now.difference(_recallSession.lastActiveAt!);
      if (elapsed.inMinutes > 5) {
        _recallSession = const MemoryRecallSession();
      }
    }

    final isComplaint = MemoryRecallService.isMemoryComplaint(userMessage);
    final isIteration = MemoryRecallService.isIterationComplaint(userMessage);

    if (!isComplaint && !isIteration) {
      // 不是抱怨也不是迭代 — 如果之前在回溯中，結束它
      if (_recallSession.isActive) {
        _recallSession = const MemoryRecallSession();
      }
      return null;
    }

    // 對話太短不觸發（還沒被壓縮，不會失憶）
    if (allMessages.length <= 12) {
      return null;
    }

    // 萃取關鍵字（迭代時保留舊的）
    final keywords = MemoryRecallService.extractKeywords(
      userMessage,
      previousKeywords: _recallSession.accumulatedKeywords,
    );

    // 搜尋
    final fragments = MemoryRecallService.search(
      allMessages: allMessages,
      keywords: keywords,
      excludedMessageIds: _recallSession.excludedMessageIds,
    );

    // 更新 session
    _recallSession = MemoryRecallSession(
      accumulatedKeywords: [
        ..._recallSession.accumulatedKeywords,
        ...keywords.map((k) => k.word),
      ].toSet().toList(), // 去重
      excludedMessageIds: {
        ..._recallSession.excludedMessageIds,
        ...fragments.map((f) => f.messageId),
      },
      iterationCount: _recallSession.iterationCount + 1,
      isActive: true,
      lastActiveAt: now,
    );

    debugPrint(
      '[MemoryRecall] iteration=${_recallSession.iterationCount}, '
      'keywords=${keywords.map((k) => k.word).join(',')}, '
      'fragments=${fragments.length}',
    );

    return MemoryRecallService.buildRecallNote(fragments);
  }

  // ──────────────────────────────────────────────
  // 對話管理方法 — [以利沙 Sprint 8 Step 2 2026-06-24]
  // ──────────────────────────────────────────────

  /// 滾動到底部的回呼，由 _ChatScreenState 注入。
  /// [以利沙 Sprint 8 Step 2 2026-06-24]
  void Function()? onScrollToBottom;

  /// 對話管理完成後的通知回呼（例如 rename dialog 完成後需要 rebuild）。
  /// [以利沙 Sprint 8 Step 2 2026-06-24]
  void Function()? onConversationsChanged;

  // ── Getters ──────────────────────────────────
  // [以利沙 Sprint 8 Step 2 2026-06-24]
  List<Conversation> get conversations => _conversations;
  Conversation? get currentConversation => _currentConversation;
  // [以利沙 Sprint 8 Step 2 2026-06-24]
  bool get showSidebar => _showSidebar;

  /// 載入所有對話，並設定當前對話。
  /// 只載入屬於目前 activeCompanion 的對話（companionId 篩選）。
  /// [以利沙 Sprint 8 Step 2 2026-06-24]
  Future<void> loadConversations() async {
    // [以利沙 P1 修復二十一輪 2026-06-27] 改為依序 await，消除競態
    await loadUnlockedCapabilities();
    await _loadUnlockedCapabilities();
    final companionId = _activeCompanion?.id;
    final all = await ConversationStore.getAll();
    // [以利沙 P1 修復十七輪 2026-06-27] 改用 getByCompanionId 直接查詢，減少記憶體消耗
    // [2026-08-27 共視修復] 多人格過濾（同 loadGeneralConversations）：
    // 歸屬夥伴 OR 內含該夥伴發言 OR 無歸屬——切換後對話不消失。
    final conversations = companionId == null
        ? all
        : all.where((c) {
            if (c.companionId == null) return true;
            if (c.companionId == companionId) return true;
            return c.messages.any((m) => m.speakerId == companionId);
          }).toList();
    final currentId = await ConversationStore.getCurrentId();

    _conversations = conversations;
    notifyListeners();

    if (currentId != null) {
      final current = await ConversationStore.getById(currentId);
      if (current != null &&
          (companionId == null ||
              current.companionId == companionId ||
              current.companionId == null ||
              current.messages.any((m) => m.speakerId == companionId))) {
        _currentConversation = current;
        notifyListeners();
        onScrollToBottom?.call();
        return;
      }
    }

    if (conversations.isNotEmpty) {
      _currentConversation = conversations.first;
      notifyListeners();
      await ConversationStore.setCurrentId(conversations.first.id);
      onScrollToBottom?.call();
    } else {
      await createNewConversation();
    }
  }

  // [以利沙 P0 修復十一輪 2026-06-27] 從持久化讀取已開通能力，填入 _unlockedCapabilities 快取
  Future<void> loadUnlockedCapabilities() async {
    const gapTypes = ['browse', 'schedule_reminder', 'local_model'];
    for (final gapType in gapTypes) {
      final unlocked = await StorageService.isCapabilityUnlocked(gapType);
      if (unlocked) {
        _unlockedCapabilities.add(gapType);
      }
    }
  }

  // [以利沙 修復二十輪 2026-06-27] 從 SharedPreferences 載入整合清單
  // [以利沙 P1 修復二十一輪 2026-06-27] 改為合併（Set 聯集）而非覆蓋，避免丟失 loadUnlockedCapabilities 的結果
  Future<void> _loadUnlockedCapabilities() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('unlocked_capabilities') ?? [];
    _unlockedCapabilities = _unlockedCapabilities.union(
      Set<String>.from(saved),
    );
  }

  // [以利沙 修復二十輪 2026-06-27] 每次新增能力後同步儲存整合清單至 SharedPreferences
  Future<void> _saveUnlockedCapabilities() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'unlocked_capabilities',
      _unlockedCapabilities.toList(),
    );
  }

  /// 建立新對話，會先保存當前對話。
  /// 新對話帶入目前 activeCompanion 的 id 作為 companionId。
  /// [以利沙 Sprint 8 Step 2 2026-06-24]
  Future<void> createNewConversation() async {
    // 先保存當前對話
    if (_currentConversation != null) {
      await ConversationStore.save(_currentConversation!);
    }
    final companionId = _activeCompanion?.id;
    // 重新載入列表確保狀態同步（只取當前 companion 的對話）
    final all = await ConversationStore.getAll();
    final conversations = companionId == null
        ? all
        : all.where((c) => c.companionId == companionId).toList();
    final conv = await ConversationStore.createNew(companionId: companionId);
    _conversations = [conv, ...conversations];
    _currentConversation = conv;
    _showSidebar = false;
    // [教練 Agent 2026-07-05] 修復：新對話只清記憶體，不清 SharedPreferences。
    // 原因：專案門存全局 prefs，不綁 conversationId。清 prefs 會害舊對話也丟門。
    // 正解是未來讓 Conversation 帶 projectDoorId（Sprint 11+ 範圍）。
    _activeProjectDoor = null;
    _lastProjectDoorJudgement = null;
    _brainReflection = null; // [Sprint 11 修復] 清思維面板，否則新對話還顯示舊門名
    onConversationAutoCreated?.call();
    notifyListeners();
    onScrollToBottom?.call();
  }

  /// [T4③ 2026-10-16 編織線] 開乾淨新對話（盲測/評測用）——
  /// 空白 conversation、重置 session store，回傳新對話 id
  Future<String> startFreshConversation({String? title}) async {
    // [2026-10-16 盲測事故防呆] 不信任記憶體 list——先從磁碟拉最新
    // （controller 剛啟動未 loadConversations 時 _conversations 是空的）
    try {
      final all = await ConversationStore.getAll();
      if (all.length > _conversations.length) {
        _conversations = all;
      }
    } catch (_) {}
    final now = DateTime.now();
    final newConv = Conversation(
      id: '${now.millisecondsSinceEpoch}',
      title: title ?? '對話 ${now.month}/${now.day}',
      createdAt: now,
      updatedAt: now,
      messages: const [],
      companionId: _activeCompanion?.id,
    );
    await ConversationStore.save(newConv);
    await ConversationStore.setCurrentId(newConv.id);
    _conversations = [newConv, ..._conversations];
    _currentConversation = newConv;
    _agentLoop?.resetSessionStore();
    _brainReflection = null;
    notifyListeners();
    onScrollToBottom?.call();
    return newConv.id;
  }

  /// [教練 Agent 2026-08-03] 延伸話題專用：建立新對話並注入指定上下文，不會被覆蓋。
  /// 流程：直接建立帶 messages 的新 Conversation → 存 → 設為 currentConversation。
  /// 與 switchConversation 不同：本方法不透過「先保存當前對話」邏輯，確保新對話
  /// 寫入的 context 不會被當前對話的「空對話」覆蓋。
  Future<void> extendTopicWithContext({
    required Conversation sourceConv,
    required List<Message> contextMessages,
    required String title,
  }) async {
    final companionId = sourceConv.companionId ?? _activeCompanion?.id;

    // 重新載入列表確保狀態同步
    final all = await ConversationStore.getAll();
    final conversations = companionId == null
        ? all
        : all.where((c) => c.companionId == companionId).toList();

    // 直接建立帶 context 的新對話
    final now = DateTime.now();
    final newConv = Conversation(
      id: '${now.millisecondsSinceEpoch}',
      title: title,
      createdAt: now,
      updatedAt: now,
      messages: contextMessages,
      companionId: companionId,
    );

    // 存到磁碟：先存 sourceConv（持久化原始對話），再存 newConv（帶 context）
    await ConversationStore.save(sourceConv);
    await ConversationStore.save(newConv);
    await ConversationStore.setCurrentId(newConv.id);

    // 更新 controller 內存狀態
    _conversations = [newConv, ...conversations];
    _currentConversation = newConv;
    // [跨輪層 2026-10-13] 新對話 = session store 重置（同 switchConversation）
    _agentLoop?.resetSessionStore();
    _showSidebar = false;
    _activeProjectDoor = null;
    _lastProjectDoorJudgement = null;
    _brainReflection = null;
    notifyListeners();
    onScrollToBottom?.call();
  }

  // [教練 Agent 2026-07-23] 畫布對話系統 — 載入指定畫布的對話
  Future<void> loadConversationsForCanvas(String canvasId) async {
    await loadUnlockedCapabilities();
    await _loadUnlockedCapabilities();
    final companionId = _activeCompanion?.id;
    final all = await ConversationStore.getAll();
    var conversations = all
        .where(
          (c) =>
              c.type == ConversationType.projectCanvas &&
              c.canvasId == canvasId,
        )
        .toList();
    if (companionId != null) {
      conversations = conversations
          .where((c) => c.companionId == companionId)
          .toList();
    }
    _conversations = conversations;
    notifyListeners();

    if (conversations.isNotEmpty) {
      _currentConversation = conversations.first;
      await ConversationStore.setCurrentId(conversations.first.id);
      notifyListeners();
      onScrollToBottom?.call();
    } else {
      await createProjectCanvasConversation(canvasId);
    }
  }

  // [教練 Agent 2026-07-23] 畫布對話系統 — 只載入一般對話（排除畫布對話）
  Future<void> loadGeneralConversations() async {
    await loadUnlockedCapabilities();
    await _loadUnlockedCapabilities();
    final companionId = _activeCompanion?.id;
    final all = await ConversationStore.getAll();
    var conversations = all
        .where((c) =>
            c.type == ConversationType.general ||
            c.type == ConversationType.proactive)
        .toList();
    // [2026-08-27 共視修復] 多人格時代：對話不再只屬於一位夥伴。
    // 過濾條件改為「對話歸屬夥伴 OR 對話內有該夥伴發言 OR 無歸屬」——
    // 切換夥伴後對話不再從列表消失（每人格都看得到共同參與的對話）。
    if (companionId != null) {
      conversations = conversations.where((c) {
        if (c.companionId == null) return true; // 早期對話無歸屬——保留顯示
        if (c.companionId == companionId) return true;
        return c.messages.any((m) => m.speakerId == companionId);
      }).toList();
    }
    final currentId = await ConversationStore.getCurrentId();

    _conversations = conversations;
    notifyListeners();

    if (currentId != null) {
      final current = await ConversationStore.getById(currentId);
      // [2026-08-27 共視修復] 恢復條件放寬（同列表過濾）——
      // 否則切換夥伴後重進對話頁，current 恢復不了 → sendMessage
      // 兜底另建新對話 → 內容重複的雙生對話（Blue 01/未命名事件）。
      bool _belongsToActive(Conversation c) {
        if (companionId == null) return true;
        if (c.companionId == null) return true;
        if (c.companionId == companionId) return true;
        return c.messages.any((m) => m.speakerId == companionId);
      }

      if (current != null &&
          current.type == ConversationType.general &&
          _belongsToActive(current)) {
        _currentConversation = current;
        notifyListeners();
        onScrollToBottom?.call();
        return;
      }
    }

    if (conversations.isNotEmpty) {
      _currentConversation = conversations.first;
      await ConversationStore.setCurrentId(conversations.first.id);
      notifyListeners();
      onScrollToBottom?.call();
    } else {
      await createNewConversation();
    }
  }

  // [教練 Agent 2026-07-23] 畫布對話系統 — 建立新的畫布對話
  // [教練 Agent 2026-07-24] 修復：建立對話後回填 CanvasMetadata.conversationId，
  // 確保三者（Canvas ↔ Conversation ↔ ProjectDoor）永遠同步
  Future<void> createProjectCanvasConversation(
    String canvasId, {
    String? title,
  }) async {
    if (_currentConversation != null) {
      await ConversationStore.save(_currentConversation!);
    }
    final companionId = _activeCompanion?.id;
    final conv = Conversation.createProjectCanvas(
      canvasId: canvasId,
      title: title ?? '專案畫布對話',
      companionId: companionId,
    );
    await ConversationStore.save(conv);
    await ConversationStore.setCurrentId(conv.id);

    // [教練 Agent 2026-07-24] 回填 conversationId 到 CanvasMetadata
    final canvas = await CanvasStore.getById(canvasId);
    if (canvas != null &&
        (canvas.conversationId == null || canvas.conversationId != conv.id)) {
      final updatedCanvas = canvas.copyWith(
        conversationId: conv.id,
        updatedAt: DateTime.now(),
      );
      await CanvasStore.save(updatedCanvas);
    }

    // [教練 Agent 2026-07-24] 如果 Canvas 有 projectDoorId，同步綁定到 Conversation
    if (canvas?.projectDoorId != null) {
      final updatedConv = conv.copyWith(projectDoorId: canvas!.projectDoorId);
      await ConversationStore.save(updatedConv);
      _currentConversation = updatedConv;
    } else {
      _currentConversation = conv;
    }

    // 重新載入列表（只含此畫布的對話）
    final all = await ConversationStore.getAll();
    var conversations = all
        .where(
          (c) =>
              c.type == ConversationType.projectCanvas &&
              c.canvasId == canvasId,
        )
        .toList();
    if (companionId != null) {
      conversations = conversations
          .where((c) => c.companionId == companionId)
          .toList();
    }
    _conversations = conversations;
    _showSidebar = false;
    _activeProjectDoor = null;
    _lastProjectDoorJudgement = null;
    _brainReflection = null;
    notifyListeners();
    onScrollToBottom?.call();
  }

  /// 切換到指定對話，會先保存當前對話。
  /// [Sprint 11] 門綁對話：用對話的 projectDoorId 找門，null 時不 fallback 到 prefs
  /// [教練 Agent P0.6 2026-08-07] 刪除單則訊息——先更新記憶體 + persist，再刷新 UI。
  /// 之前的 bug：呼叫端用 switchConversation 刪訊息，但 switchConversation
  /// 會先 save 舊 conversation 再 reload，等於把刪掉的訊息又存回去。
  Future<void> deleteMessage(String messageId) async {
    final conv = _currentConversation;
    if (conv == null) return;
    final updatedMessages = conv.messages.where((m) => m.id != messageId).toList();
    final updated = conv.copyWith(messages: updatedMessages);
    _currentConversation = updated;
    await ConversationStore.save(updated);
    notifyListeners();
  }

  Future<void> switchConversation(Conversation conv) async {
    if (_currentConversation != null) {
      await ConversationStore.save(_currentConversation!);
    }
    // [跨輪層 2026-10-13] 切對話 = session store 重置——
    // 舊對話的封存指針不能洩漏到新對話（context_recall 查不到跨對話內容）。
    _agentLoop?.resetSessionStore();
    final latest = await ConversationStore.getById(conv.id);
    await ConversationStore.setCurrentId(conv.id);
    _currentConversation = latest ?? conv;
    _showSidebar = false;

    // [Sprint 11] 門綁對話：用對話的 projectDoorId 找門
    _lastProjectDoorJudgement = null;
    _brainReflection = null; // [Sprint 11 修復] 清思維面板，避免顯示上一個對話的門
    if (_currentConversation?.projectDoorId != null) {
      final door = await _projectDoorStore.loadByConversationId(
        _currentConversation!.projectDoorId!,
      );
      // 如果 loadByConversationId 找不到，試 loadAll 裡找 id
      _activeProjectDoor =
          door ??
          _projectDoors
              .where((d) => d.id == _currentConversation!.projectDoorId)
              .firstOrNull;
    } else {
      _activeProjectDoor = null; // 不 fallback 到 prefs
    }

    notifyListeners();
    onScrollToBottom?.call();
  }

  /// 刪除指定對話。
  /// [以利沙 Sprint 8 Step 2 2026-06-24]
  Future<void> deleteConversation(String id) async {
    await ConversationStore.delete(id);
    final companionId = _activeCompanion?.id;
    final all = await ConversationStore.getAll();
    final conversations = companionId == null
        ? all
        : all.where((c) => c.companionId == companionId).toList();
    _conversations = conversations;
    if (_currentConversation?.id == id) {
      if (conversations.isNotEmpty) {
        _currentConversation = conversations.first;
      } else {
        _currentConversation = null;
      }
    }
    notifyListeners();
    if (_currentConversation == null) {
      await createNewConversation();
    } else {
      onScrollToBottom?.call();
    }
  }

  /// 清除當前對話的所有訊息。
  /// [以利沙 Sprint 8 Step 2 2026-06-24]
  Future<void> clearCurrentChat() async {
    if (_currentConversation != null) {
      final cleared = _currentConversation!.copyWith(messages: []);
      await ConversationStore.save(cleared);
      _currentConversation = cleared;
      notifyListeners();
      onScrollToBottom?.call();
    }
  }

  /// 同步更新 conversations 列表（從 store 重新讀取）。
  /// 供 _sendMessage 等其他方法在更新對話後呼叫。
  /// [以利沙 Sprint 8 Step 2 2026-06-24]
  Future<void> refreshConversations() async {
    final companionId = _activeCompanion?.id;
    final all = await ConversationStore.getAll();
    _conversations = companionId == null
        ? all
        : all.where((c) => c.companionId == companionId).toList();
    notifyListeners();
  }

  /// 儲存當前對話到 store。
  /// [以利沙 Sprint 8 Step 2 2026-06-24]
  Future<void> saveCurrentConversation() async {
    if (_currentConversation != null) {
      // [教練 Agent 2026-08-02] 未命名對話 → 5 則訊息後自動命名
      _maybeAutoTitle();
      await ConversationStore.save(_currentConversation!);
      // D11-7: 自動摘要產生（跨 session 連續性）
      _maybeGenerateSummary();
    }
  }

  /// [教練 Agent 2026-08-03] 包裝：save 對話時自動套用命名規則。
  /// 所有 `ConversationStore.save(_currentConversation!)` 應該改用這個方法。
  Future<void> _persistCurrentConversation() async {
    if (_currentConversation != null) {
      // 自動命名未命名對話
      _maybeAutoTitle();
      await ConversationStore.save(_currentConversation!);
    }
  }

  /// [教練 Agent 2026-08-02] 未命名對話在 5 則訊息後自動命名（≤7字）
  /// [教練 Agent 2026-08-03] 簡化：3 則內就命名，從【用戶訊息】抓關鍵字
  /// [教練 Agent 2026-08-02] 未命名對話自動命名
  /// [教練 Agent 2026-08-03] 簡化：3 則內就命名，從【用戶訊息】抓關鍵字
  /// [小葵 2026-09-21 Blue 令] 命名提早到第 1 則 user 訊息、上限放寬到 12 字——
  /// 「標題要讓使用者知道這個對話是做什麼的」，列表不該出現未命名對話。
  bool _maybeAutoTitle() {
    final conv = _currentConversation;
    if (conv == null) return false;
    if (conv.title != '未命名對話') return false;
    if (conv.messages.isEmpty) return false;

    // 策略：取前 3 則用戶訊息（用戶訊息通常最清楚主題）
    final userMsgs = conv.messages
        .where((m) => m.role == 'user' && m.content.trim().isNotEmpty)
        .take(3)
        .map((m) => m.content.trim())
        .toList();
    if (userMsgs.isEmpty) return false;

    final combined = userMsgs.join(' ');
    final title = extractTitleFromText(combined);
    if (title == '未命名對話' || title.isEmpty) return false;
    _currentConversation = conv.copyWith(title: title);
    return true;
  }

  /// 從文字擷取標題
  /// [教練 Agent 2026-08-03] 簡化：去掉 thought 過濾（已是 user 訊息），純粹：去前綴 + 截斷
  /// [小葵 2026-09-21] 上限 7 → 12 字（Blue 令：標題要讓使用者知道對話用途）
  @visibleForTesting
  String extractTitleFromText(String text) {
    var t = text
        .trim()
        .replaceAll(RegExp(r'\n+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.isEmpty) return '未命名對話';

    // 取開頭第一個有意義詞，從中找 <=7 字
    // 過濾掉開頭助詞
    final prefix = RegExp(
      r'^(?:請問|請[問教]?|那|那麼|這個|這樣|那個|那樣|現在|接下來|所以|然後|因為|如果|不過|由於|另外|此外|除了|首先|至於)',
    );
    t = t.replaceFirst(prefix, '').trim();

    // 找到第一個有意義的子句（斷句點切割）
    final sentenceEnd = RegExp(r'[，。！？；\n]');
    final match = sentenceEnd.firstMatch(t);
    String firstSentence = match != null
        ? t.substring(0, match.start).trim()
        : t.length > 14
        ? t.substring(0, 14)
        : t;

    // 過濾問句詞尾
    if (firstSentence.endsWith('嗎') ||
        firstSentence.endsWith('呢') ||
        firstSentence.endsWith('？') ||
        firstSentence.endsWith('?')) {
      var fs = firstSentence;
      while (fs.isNotEmpty &&
          (fs.endsWith('嗎') ||
              fs.endsWith('呢') ||
              fs.endsWith('？') ||
              fs.endsWith('?'))) {
        fs = fs.substring(0, fs.length - 1).trim();
      }
      firstSentence = fs;
    }

    if (firstSentence.isEmpty) return '未命名對話';
    // [小葵 2026-09-21 Blue 令] ≤7 字太短看不出主題，放寬到 12 字
    return firstSentence.length <= 12
        ? firstSentence
        : firstSentence.substring(0, 12);
  }

  /// D11-7: 當專案畫布對話訊息超過 30 則且摘要過期時，自動產生摘要
  void _maybeGenerateSummary() {
    final conv = _currentConversation;
    if (conv == null || !conv.isProjectCanvas) return;
    if (conv.messages.length < 30) return;

    final lastSummarized = conv.lastSummaryIndex ?? 0;
    final newMessageCount = conv.messages.length - lastSummarized;
    if (newMessageCount < 15) return; // 不夠新訊息，跳過

    _generateSummaryAsync(conv);
  }

  /// D11-7: 非同步產生摘要並存入 Conversation
  Future<void> _generateSummaryAsync(Conversation conv) async {
    try {
      final lastSummarized = conv.lastSummaryIndex ?? 0;
      final messagesToSummarize = conv.messages.sublist(lastSummarized);

      final conversationText = messagesToSummarize
          .where((m) => m.content.trim().isNotEmpty)
          .map(
            (m) =>
                '${m.role == 'user' ? '使用者' : 'Agent'}: ${m.content.length > 200 ? '${m.content.substring(0, 200)}...' : m.content}',
          )
          .join('\n');

      if (conversationText.isEmpty) return;

      final existingSummary = conv.summary ?? '';
      final systemPrompt = existingSummary.isEmpty
          ? '你是對話摘要助手。請將以下對話摘要成重點條列，保留關鍵決策、計畫和待辦事項。使用繁體中文，不超過 500 字。'
          : '你是對話摘要助手。以下是之前的摘要和新對話內容。請更新摘要，保留關鍵決策、計畫和待辦事項。使用繁體中文，不超過 500 字。\n\n之前的摘要：\n$existingSummary';

      final summary = await ApiService.complete(
        systemPrompt: systemPrompt,
        userPrompt: '對話內容：\n$conversationText',
      );

      if (summary.trim().isEmpty) return;

      final updated = conv.copyWith(
        summary: summary.trim(),
        lastSummaryIndex: conv.messages.length,
      );
      _currentConversation = updated;
      await ConversationStore.save(updated);
      notifyListeners();
    } catch (e) {
      debugPrint('[D11-7] 摘要產生失敗: $e');
    }
  }

  /// 更新當前對話（記憶體中），不自動儲存。
  /// 供 _sendMessage 等方法使用。
  /// [以利沙 Sprint 8 Step 2 2026-06-24]
  void updateCurrentConversation(Conversation conv) {
    _currentConversation = conv;
    notifyListeners();
  }

  /// 重新命名對話。需要 BuildContext 來顯示 dialog。
  /// [以利沙 Sprint 8 Step 2 2026-06-24]
  // TODO: needs context — dialog 邏輯暫時由 _ChatScreenState 委派處理
  Future<void> renameConversation(
    Conversation conv,
    Future<String?> Function() showRenameDialog,
  ) async {
    final newTitle = await showRenameDialog();
    if (newTitle != null && newTitle.isNotEmpty) {
      final updated = conv.copyWith(title: newTitle);
      await ConversationStore.save(updated);
      await loadConversations();
    }
  }

  // ════════════════════════════════════════════════════════════════
  // 專案門 (ProjectDoor) 邏輯 — [以利沙 Sprint 8 Step 3 2026-06-24]
  // ════════════════════════════════════════════════════════════════

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  /// 由 _ChatScreenState 注入的回呼。
  void Function(String)? onAppendLocalSystemMessage;
  void Function(Conversation)? onSetCurrentConversation;
  void Function()? onConversationsReloaded;

  /// [以利沙 Sprint 8 Step 4 2026-06-24]
  /// 由 _ChatScreenState 注入：把 BridgeActionResult 附加到對話訊息。
  /// _appendBridgeResultMessage 依賴 BuildContext / setState，保留在 State 層。
  Future<void> Function(BridgeActionResult)? onAppendBridgeResult;

  // ── Getters (ProjectDoor) ──────────────────────
  // [以利沙 Sprint 8 Step 3 2026-06-24]
  ProjectDoor? get activeProjectDoor => _activeProjectDoor;
  // [以利沙 Sprint 8 Step 3 2026-06-24]
  List<ProjectDoor> get projectDoors => _projectDoors;
  // [以利沙 Sprint 8 Step 3 2026-06-24]
  DoorDecisionPendingReturn? get pendingDoorReturn => _pendingDoorReturn;
  // [以利沙 Sprint 8 Step 3 2026-06-24]
  ProjectDoorCardData? get lastProjectDoorJudgement =>
      _lastProjectDoorJudgement;
  // [以利沙 Sprint 8 Step 3 2026-06-24]
  BrainReflection? get brainReflection => _brainReflection;
  // [以利沙 Sprint 8 Step 3 2026-06-24]
  SecondBrainTrace? get secondBrainTrace => _secondBrainTrace;
  // [教練 Agent 2026-07-05] 擺錘週報 + 心腦合一 getter
  PendulumAuditSummary? get auditSummary {
    try {
      return _auditStore.getAuditLast7Days();
    } catch (_) {
      return null;
    }
  }

  HeartMindDialogue? get heartMindDialogue => _heartMindDialogue;

  // ── [以利沙 Sprint 11 Part B] Pipeline 接入 ──────────

  /// lazy 初始化 pipeline（第一次使用時呼叫）。
  /// pipeline_enabled feature flag 預設 true（Sprint 12 開啟）。
  Future<void> _ensurePipelineInitialized() async {
    if (_pipeline != null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _pipelineEnabled = prefs.getBool('pipeline_enabled') ?? true;

      if (!_pipelineEnabled) return;

      _pipelineLlmClient = ProductionPipelineLLMClient();
      await _pipelineLlmClient!.refreshAvailability();

      _heartMindDialogue = HeartMindDialogue(
        store: HeartMindStore(),
        llmClient: _pipelineLlmClient,
      );

      _pipeline = TransurfingPipeline(
        llmClient: _pipelineLlmClient,
        auditStore: _auditStore,
        heartMindDialogue: _heartMindDialogue,
      );
    } catch (e) {
      // pipeline 初始化失敗不 crash，fallback 到規則版
      _pipeline = null;
    }
  }

  /// [教練 Agent Sprint 1.2] 語意理解服務延遲初始化。
  /// 共用 pipeline 的 LLM client（若 pipeline 已初始化）。
  /// feature flag 預設 false → service 回傳 null，走舊正則。
  Future<void> _ensureSemanticIntentInited() async {
    if (_semanticIntentInited) return;
    _semanticIntentInited = true;

    try {
      // 確保 pipeline client 已初始化（共用 LLM client）
      await _ensurePipelineInitialized();
      _semanticIntentService = SemanticIntentService(
        llmClient: _pipelineLlmClient,
      );
    } catch (_) {
      _semanticIntentService = null;
    }
  }

  // ── [教練 Agent 2026-07-22] Phase H 人格機制 ──────────────────────

  /// 檢查是否為此 companion 的首次對話
  ///
  /// 透過 ConversationStore 查詢——如果沒有任何對話記錄，就是首次。
  bool isFirstConversationForCompanion(String companionId) {
    try {
      // 用 companion 的 totalConversations 判斷（更輕量）
      final companion = CompanionStore().getById(companionId);
      return companion?.totalConversations == 0;
    } catch (_) {
      return false;
    }
  }

  /// 建構首次出場指令
  ///
  /// 人格卡已就緒時，在 system prompt 中加入出場結構指令。
  String _buildFirstConversationDirective(PersonaCard card) {
    final scanReport = card.scanReportForOpening;
    return '''## 首次出場指令

這是你和使用者的第一次對話。請按照以下結構出場：

1. **掃描報告**：告訴使用者你看到了什麼${scanReport.isNotEmpty ? '（引用掃描結果的具體數字）' : ''}
2. **人格展現**：用你的風格說話——${card.voiceStyle}
3. **驚喜反饋**：如果使用者的資料夾有內容，告訴他們那些東西有價值
4. **任務提案**：提案做四個練習，最後一個會把前面做的全部組合起來
5. **等使用者回應**

你的第一句話應該是：「${card.firstLine}」

不要一次講完所有範本的細節。先建立關係，再逐步引導。
建議範本順序：${card.suggestedTemplateOrder.join(' → ')}''';
  }

  /// 非同步觸發人格推理（不阻塞當前對話）
  ///
  /// 首次對話時人格卡不存在 → 跑掃描 + 推理 → 存入知識庫。
  /// 下次對話時 getCard() 就能取回。
  void _triggerPersonaInferenceAsync(String companionId) async {
    debugPrint('[PersonaInference] 非同步觸發人格推理 — companion: $companionId');
    try {
      final companion = CompanionStore().getById(companionId);
      if (companion == null) return;

      // 取得 DB 路徑
      final dbPath = await BrainDatabase.getCustomDbDirectory();
      if (dbPath == null || dbPath.isEmpty) {
        // 沒有設定資料夾 → 只用召喚提示詞推理
        await PersonaInferenceService.instance.infer(
          companion: companion,
          summonPrompt: companion.appearancePrompt,
        );
        return;
      }

      // Phase 1 掃描（秒出）
      final phase1 = await FolderScannerService.instance.scanMetadata(dbPath);

      // Phase 2 掃描（背景，不阻塞）
      // 先用 Phase 1 結果推理，Phase 2 完成後靜默更新
      final card = await PersonaInferenceService.instance.infer(
        companion: companion,
        summonPrompt: companion.appearancePrompt,
        scanResult: phase1,
      );
      debugPrint('[PersonaInference] 人格卡推理完成: ${card.archetype}');

      // 背景跑 Phase 2（不 await）
      FolderScannerService.instance
          .scanContent(dbPath, maxFiles: 50, phase1Result: phase1)
          .then((fullResult) {
            // Phase 2 完成後用更豐富的線索重新推理
            PersonaInferenceService.instance
                .infer(
                  companion: companion,
                  summonPrompt: companion.appearancePrompt,
                  scanResult: fullResult,
                )
                .then((updatedCard) {
                  debugPrint(
                    '[PersonaInference] Phase 2 更新完成: ${updatedCard.archetype}',
                  );
                })
                .catchError((e) {
                  debugPrint('[PersonaInference] Phase 2 更新失敗: $e');
                });
          })
          .catchError((e) {
            debugPrint('[FolderScanner] Phase 2 失敗: $e');
          });
    } catch (e) {
      debugPrint('[PersonaInference] 非同步觸發失敗: $e');
    }
  }

  // ── [教練 Agent S21] Agent Loop 初始化 ──────────────────────

  /// lazy 初始化 Agent Loop。
  /// agent_loop_enabled feature flag 預設 false——不開不接，零回歸。
  Future<void> _ensureAgentLoopInitialized() async {
    if (_agentLoopInited) return;
    _agentLoopInited = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      _agentLoopEnabled = prefs.getBool('agent_loop_enabled') ?? true;
      debugPrint('[AgentLoop] _agentLoopEnabled = $_agentLoopEnabled');
      if (!_agentLoopEnabled) return;

      // [教練 Agent 2026-07-19] screen_capture 預設改 true——原生 Agent在聊天路徑也需要眼睛
      final screenCaptureEnabled =
          prefs.getBool('screen_capture_enabled') ?? true;

      // [教練 Agent 2026-07-19] 統一用 FlutterSelfCaptureExecutor（App 自拍），
      // 對齊任務注入通道 + 使用者要求「截 App 自己畫面，不截全螢幕」。
      // 如果 _selfCaptureKey 未設定（手機版等），fallback 到 MacScreenCaptureExecutor。
      final screenCaptureExecutor = _selfCaptureKey != null
          ? FlutterSelfCaptureExecutor(boundaryKey: _selfCaptureKey!)
          : MacScreenCaptureExecutor();

      _agentToolRegistry = AgentToolRegistry.withDefaults(
        bridgeActionExecutor: _bridgeActionExecutor,
        brainContainerService: BrainContainerService.instance,
        screenCaptureEnabled: screenCaptureEnabled,
        screenCaptureExecutor: screenCaptureExecutor,
        onNavigateToSetting: onNavigateToSetting,
        mcpCanvasExecutor: mcpCanvasExecutor, // [Phase 0 Track A 2026-07-17]
      );

      _agentLoop = AgentLoop(
        toolRegistry: _agentToolRegistry!,
        llmClient: ProductionAgentLoopLLMClient(),
      );
      // [身份保護 2026-10-21] 同步活躍夥伴名給 AgentLoop（直通道用真名）
      _agentLoop!.companionName = _activeCompanion?.name;
      // [D002 2026-08-10] 將 onToolConfirmation 橋接到 AgentLoop 實例欄位
      _agentLoop!.onToolConfirmation = onToolConfirmation;
    } catch (e, stack) {
      _agentLoopInitError = '$e\n$stack';
      debugPrint('[AgentLoop] ❌ init 失敗: $e');
      debugPrint('[AgentLoop] stack: $stack');
      _agentLoop = null;
    }
  }

  /// Agent Loop 是否啟用
  bool get isAgentLoopEnabled => _agentLoopEnabled;

  /// 執行 Agent Loop（如果啟用），回傳結果或 null（未啟用）
  /// D11-7: 組裝畫布上下文（跨 session 連續性）
  ///
  /// 如果當前對話是專案畫布對話，注入：
  /// - 畫布標題和狀態
  /// - 對話摘要（如果有）
  /// - 來源對話資訊（如果有 parentConversationId）
  String? _buildCanvasContext() {
    final conv = _currentConversation;
    if (conv == null || !conv.isProjectCanvas) return null;

    final parts = <String>[];

    parts.add('你正在協助使用者進行專案畫布「${conv.title}」的討論。');
    parts.add('這是一個封閉的專案畫布對話 thread，討論內容應聚焦於此專案。');

    // [教練 Agent 2026-07-22] Phase B — 注入畫布快照
    final snapshotDesc = CanvasSnapshotService.instance.describeFullState();
    if (snapshotDesc.isNotEmpty && !snapshotDesc.contains('未連接')) {
      parts.add('\n### 畫布即時狀態\n$snapshotDesc');
    }

    if (conv.summary != null && conv.summary!.isNotEmpty) {
      parts.add('\n### 前次對話摘要\n${conv.summary}');
    }

    if (conv.parentConversationId != null) {
      parts.add(
        '\n### 來源\n此畫布對話從一般對話匯入而來（來源對話 ID: ${conv.parentConversationId}）。',
      );
    }

    parts.add('\n### 注意事項');
    parts.add('- 如果使用者討論的內容適合變成計畫，建議匯入畫布節點。');
    parts.add('- 回覆時使用繁體中文。');
    parts.add('- 畫布狀態會自動推送給你，不需要每次呼叫 canvas_get_state。');
    // [2026-08-27 Blue 指示] 畫布能力宣告——Agent 必須知道：
    // 1. 回話前先看畫布現況（上面的即時狀態就是你的視網膜）
    // 2. 你有能力控制/操作畫布（建節點、連線、改參數、執行）
    // 3. 不要對已有進度的畫布假裝是空白重來
    parts.add('\n### 你的畫布能力');
    parts.add('- 你看得到畫布即時狀態（上面的「畫布即時狀態」區塊）——'
        '回話前務必先讀它，你的回應要符合畫布目前的進度與內容。');
    parts.add('- 你可以操作畫布：建立/刪除節點、連線、修改參數、執行工作流。'
        '需要時直接行動或提出建議，不要只當旁觀者。');
    parts.add('- 畫布上已有半成品的東西＝進行中的工作——'
        '續上它，不要建議從零重來。');

    return parts.join('\n');
  }

  /// D12: 偵測 Agent 回覆中的步驟完成標記，更新 flowStep + 畫布節點狀態
  ///
  /// 標記格式：
  /// - `<<STEP_DONE:1>>` → 第 1 步完成
  /// - `<<STEP_BLOCKED:2:原因>>` → 第 2 步受阻
  /// - `<<ALL_DONE>>` → 全部完成
  ///
  /// 回傳過濾後的乾淨文字（標記移除）。
  Future<String> _processStepMarkers(String reply) async {
    String cleaned = reply;

    // [教練 Agent 2026-07-30] 移除 LLM 內部元資料標籤——不應顯示給使用者
    // <emotion>neutral</emotion>、<confidence>0.9</confidence> 等
    cleaned = cleaned
        .replaceAll(
          RegExp(r'<emotion>\s*\w*\s*</emotion>\s*', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'<confidence>\s*[\d.]*\s*</confidence>\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (cleaned.isEmpty) return reply; // 避免清空後回傳空字串

    reply = cleaned;

    // 偵測 STEP_DONE
    final donePattern = RegExp(r'<<STEP_DONE:(\d+)>>');
    final doneMatches = donePattern.allMatches(reply);

    // 偵測 STEP_BLOCKED
    final blockedPattern = RegExp(r'<<STEP_BLOCKED:(\d+):([^>]*)>>');
    final blockedMatches = blockedPattern.allMatches(reply);

    // 偵測 ALL_DONE
    final allDone = reply.contains('<<ALL_DONE>>');

    if (doneMatches.isEmpty && blockedMatches.isEmpty && !allDone) {
      return reply; // 沒有標記，直接回傳
    }

    // 取得當前畫布的 flowStepMapping
    final conv = _currentConversation;
    if (conv == null || !conv.isProjectCanvas || conv.canvasId == null) {
      // 不是畫布對話，只過濾標記
      return reply
          .replaceAll(donePattern, '')
          .replaceAll(blockedPattern, '')
          .replaceAll('<<ALL_DONE>>', '')
          .trim();
    }

    try {
      final canvases = await CanvasStore.getAll();
      final canvas = canvases.where((c) => c.id == conv.canvasId).firstOrNull;
      if (canvas == null || canvas.projectDoorId == null) {
        return reply
            .replaceAll(donePattern, '')
            .replaceAll(blockedPattern, '')
            .replaceAll('<<ALL_DONE>>', '')
            .trim();
      }

      final doorStore = ProjectDoorStore();
      final doors = await doorStore.loadAll();
      final door = doors.where((d) => d.id == canvas.projectDoorId).firstOrNull;
      if (door == null) return reply.replaceAll(donePattern, '').trim();

      final mapping = canvas.flowStepMapping; // nodeId → stepId
      final nodeList = mapping.keys.toList();
      final entityGraph = EntityGraphService.withSqliteCanvasStore(
        memoryStore: MemoryStore(),
        doorStore: doorStore,
        assetStore: DigitalAssetRegistryStore(),
      );

      // 處理完成的步驟
      for (final match in doneMatches) {
        final stepNum = int.parse(match.group(1)!);
        if (stepNum < 1 || stepNum > nodeList.length) continue;

        final nodeId = nodeList[stepNum - 1];
        final stepId = mapping[nodeId]!;

        // 更新 flowStep 狀態為 done
        await doorStore.updateFlowStep(
          door.id,
          stepId,
          status: FlowStep.statusDone,
        );

        // 更新畫布節點視覺狀態為 done
        await entityGraph.updateCanvasVisualState(
          nodeId,
          CanvasVisualState.done,
        );

        debugPrint('[D12] 步驟 $stepNum 完成: $nodeId → $stepId');
      }

      // 處理受阻的步驟
      for (final match in blockedMatches) {
        final stepNum = int.parse(match.group(1)!);
        final reason = match.group(2) ?? '未知原因';
        if (stepNum < 1 || stepNum > nodeList.length) continue;

        final nodeId = nodeList[stepNum - 1];
        final stepId = mapping[nodeId]!;

        await doorStore.updateFlowStep(
          door.id,
          stepId,
          status: FlowStep.statusBlocked,
        );
        await entityGraph.updateCanvasVisualState(
          nodeId,
          CanvasVisualState.blocked,
        );

        debugPrint('[D12] 步驟 $stepNum 受阻: $reason');
      }

      // 處理全部完成
      if (allDone) {
        // 更新畫布狀態為 completed
        final updatedCanvas = canvas.copyWith(status: CanvasStatus.completed);
        await CanvasStore.save(updatedCanvas);

        // 更新所有未完成步驟為 done
        for (final entry in mapping.entries) {
          final step = door.flowSteps
              .where((s) => s.id == entry.value)
              .firstOrNull;
          if (step != null && !step.isDone) {
            await doorStore.updateFlowStep(
              door.id,
              entry.value,
              status: FlowStep.statusDone,
            );
            await entityGraph.updateCanvasVisualState(
              entry.key,
              CanvasVisualState.done,
            );
          }
        }

        debugPrint('[D12] 畫布 ${canvas.id} 全部完成');
      }
    } catch (e) {
      debugPrint('[D12] 步驟標記處理失敗: $e');
    }

    // 過濾標記，回傳乾淨文字
    cleaned = reply
        .replaceAll(donePattern, '')
        .replaceAll(blockedPattern, '')
        .replaceAll('<<ALL_DONE>>', '')
        .trim();

    return cleaned;
  }

  Future<AgentLoopResult?> _runAgentLoopIfNeeded({
    required String userMessage,
    String? companionPersona,
    String? contextMemory,
    List<Map<String, String>>? conversationHistory,
    String? memoryRecallNote, // [教練 Agent 2026-07-25] 記憶回溯
    bool prohibitPaidTools = false, // [教練 Agent 2026-08-20] 機器輪次禁用付費工具
  }) async {
    await _ensureAgentLoopInitialized();
    if (!_agentLoopEnabled ||
        _agentLoop == null ||
        _agentToolRegistry == null) {
      return null;
    }

    // [因果引擎 L1] 歸人——本輪所有介入記帳歸屬當前夥伴
    CausalLedger.instance.ambientCompanionId = _activeCompanion?.id;
    unawaited(CausalLedger.instance.initialize());

    // [2026-07-20] 如果上層沒帶 contextMemory（shouldDeferBrainInstrumentation 跳過了），
    // 用 BrainContainerService 做語意搜尋注入。對齊 Hermes——記憶是自動的，不需原生 Agent主動 memory_search。
    contextMemory ??= await BrainContainerService.instance.getFormattedContext(
      userMessage,
    );
    if (contextMemory.isNotEmpty) {
      debugPrint('[AgentLoop] 記憶注入: ${contextMemory.length} 字');
    }

    // [H2/M3 小葵 2026-10-07 Blue 贈禮] 記憶2域10層——分層全量注入。
    // 語意檢索（上面）管「相關性」，分層快照管「身分連續」：
    // L1 鐵則＋L2 身分＋L3 專案熱每次隨身（窗口 ~8K tokens），
    // L4-L10 永不全量注入、只走上面檢索引用。超窗口走升降溫不刪除。
    try {
      final (layerSection, overCap) =
          MemoryLayerService.instance.buildInjectionSection();
      if (layerSection.isNotEmpty) {
        contextMemory = layerSection + (contextMemory.isEmpty ? '' : '\n$contextMemory');
        debugPrint(
            '[MemoryLayer] L1-L3 注入: ${layerSection.length} 字'
            '${overCap.isEmpty ? '' : '（${overCap.length} 條超窗口＝降溫候選）'}');
      }
    } catch (e) {
      debugPrint('[MemoryLayer] 分層注入失敗（fail-quiet 不擋對話）: $e');
    }

    // [教練 Agent 2026-07-22] 動態 Agent 路由——根據意圖模式決定本地或雲端
    // 取代原本靜態的 isLocal = (provider == 'local') 判斷
    // 路由層會根據 IntentSpineMode + MemoryGuard + server 狀態動態決定
    //
    // [教練 Agent 2026-07-30] 使用者指定模型優先——直接讀 StorageService 判斷 isLocal
    // 之前只讀 ProviderRouter.instance.current，如果 current 是 null（例如
    //   route() 還沒被呼叫或被其他流程清空），會 fallback 到 isLocal = false，
    //   導致 Agent Loop 以為在雲端模式但實際上該走本地。
    // 現在：先讀使用者選的 provider，如果使用者選了雲端 → isLocal = false；
    //   如果使用者沒選或選 local → 才看 ProviderRouter.instance.current。
    final userProvider = await StorageService.getProvider();
    // [T7④ 補刀 2026-10-16] localOnly（斷網血管）一票否決「明選雲端」——
    // 盲測實證：使用者 storage 存 provider=openai（token 已失效），
    // userWantsCloud 分支跳過 ProviderRouter 直取 openai → localOnly 被繞過。
    // 斷網模式的精神：沒有雲，明選也要 fallback 本地（告知 reason）。
    final localOnlyMode = await StorageService.getLocalOnly();
    final userWantsCloud =
        !localOnlyMode &&
        userProvider != null &&
        userProvider != 'local' &&
        userProvider != 'default';

    // [教練 Agent 2026-08-07] 把鎖定的 provider 注入 DelegateSubagentTool，
    // 讓子代理在被指定模式時也被鎖定（不只 prompt 層）
    if (userWantsCloud) {
      delegate_subagent_tool.setSubagentLockedProvider(userProvider);
    } else {
      delegate_subagent_tool.setSubagentLockedProvider(null);
    }
    final routedProvider = ProviderRouter.instance.current;
    // [小葵 2026-10-01 補刀] 使用者存的 provider='local' 時 prompt 也必須走
    // 本地輕量路徑——否則全裝 prompt（~6K chars）打進 ctx=4096 的 llama-server
    // 直接爆掉（病例：activateBridgeRuntimeAsBrain 存了 provider='local'，但
    // ProviderRouter.current=null → isLocal=false → 全裝 prompt + 本地端點 =
    // 空回應）。
    final isLocal = userWantsCloud
        ? false // 使用者指定雲端 → 不是 local
        : (userProvider == 'local' ||
            routedProvider?.isLocal ==
                true); // 沒指定雲端 → 看 Router 路由結果
    final routeReason = routedProvider?.reason ?? 'default';
    debugPrint('[AgentLoop] 路由: ${isLocal ? "local" : "cloud"} — $routeReason');

    // [教練 Agent 2026-07-21] 本地模式截斷對話歷史——只帶最近 3 輪，避免 prompt 過大
    // [小葵 2026-10-01 補刀] 則數截斷不夠——本地 ctx=4096，中文一字≈1 token，
    // 一則舊的 [[TASK_DONE]] 巨無霸報告就能單獨爆掉預算（病例：閒聊對話
    // 歷史打包 1548 tokens 仍超）。改雙重截斷：則數 ≤6 且總字數 ≤2200
    // （中文 chars≈tokens 保守估）。從最新往回收，收滿為止。
    List<Map<String, String>>? effectiveHistory = conversationHistory;
    // [跨輪層 2026-10-13 Spike 002 延伸] 雲端模式歷史壓縮——CLM 形狀。
    // 病因：完整歷史每輪重送，token 線性膨脹（使用者得手動 /reset /new 的根因）。
    // 形狀：>10 輪時舊輪全文封存進 session store（永不刪）、保留最近 6 輪＋
    // 指針摘要塊；LLM 需要細節時 context_recall 工具讀回。冪等：跨輪重送
    // 的同內容回同指針，不重複入庫。本地模式走下方既有雙重截斷不變。
    if (!isLocal && conversationHistory != null && conversationHistory.isNotEmpty) {
      final compacted = _agentLoop!.compactHistoryForSession(conversationHistory);
      if (compacted.length != conversationHistory.length) {
        debugPrint(
          '[AgentLoop] 雲端歷史壓縮：${conversationHistory.length} → '
          '${compacted.length} 則（session store 封存）',
        );
      }
      effectiveHistory = compacted;
    }
    if (isLocal && conversationHistory != null && conversationHistory.isNotEmpty) {
      const maxTurns = 6;
      const maxChars = 2200;
      final recent = conversationHistory.length > maxTurns
          ? conversationHistory.sublist(conversationHistory.length - maxTurns)
          : conversationHistory;
      final kept = <Map<String, String>>[];
      var budget = maxChars;
      for (final m in recent.reversed) {
        final len = (m['content'] ?? '').length;
        if (len > budget) break;
        budget -= len;
        kept.insert(0, m);
      }
      effectiveHistory = kept;
      debugPrint(
        '[AgentLoop] 本地模式：截斷對話歷史 ${conversationHistory.length} → '
        '${kept.length} 則（字數預算 $maxChars）',
      );
    }

    // [小葵 2026-09-22 Blue 令] KnowledgeIndexer 退役——設計知識改由
    // agent_search_knowledge 工具按需查，chat 路徑不再預載檢索。
    // [教練 Agent 2026-07-22] Phase E — 查詢 Agent 本地知識庫
    String? agentKnowledgeContext;
    try {
      agentKnowledgeContext = AgentKnowledgeService.instance.getRelevantContext(
        userMessage,
      );
    } catch (e) {
      debugPrint('[AgentKnowledge] 查詢本地知識庫失敗: $e');
    }

    // [教練 Agent 2026-07-22] Phase H — 人格卡注入 + 首次出場偵測
    String? personaCardText;
    String? firstConversationDirective;

    final companionId = _activeCompanion?.id;
    if (companionId != null && !isLocal) {
      // 取回已推理的人格卡
      final card = PersonaInferenceService.instance.getCard(companionId);
      if (card != null) {
        personaCardText = card.toPromptText();

        // 偵測首次對話：companion 的 totalConversations == 0
        final isFirstConversation = _activeCompanion!.totalConversations == 0;
        if (isFirstConversation) {
          firstConversationDirective = _buildFirstConversationDirective(card);
          debugPrint(
            '[PersonaInference] 首次出場指令已注入 — companion: ${_activeCompanion!.name}',
          );
        }
      } else if (isFirstConversationForCompanion(companionId)) {
        // 人格卡不存在且是首次對話 → 觸發掃描 + 推理（非阻塞，不卡住這次回覆）
        _triggerPersonaInferenceAsync(companionId);
      }
    }

    // [教練 Agent 2026-08-21] 自律 Phase A——預算之眼（非同步先取，失敗不擋對話）
    String? budgetEyeText;
    try {
      budgetEyeText = await PaidActionGate.instance.budgetEye();
    } catch (e) {
      debugPrint('[BudgetEye] 注入失敗（不擋對話）: $e');
    }

    // [小葵 2026-10-01 Blue 令] 本地士兵配備——精靈依任務挑 compact 工具組。
    // 戰術：本地 ctx 只有 4096，塞不下全工具手冊；用語意檢索挑 2-4 把
    // 最相關的工具（toFullDescription 精簡描述），聊天題配備為空 = 純聊天。
    // 未來作戰模式：本地 subagent 軍團以此為标配——輕裝上陣、按需領工具。
    String? localToolKit;
    if (isLocal) {
      try {
        final toolSeek = _agentToolRegistry?.get('compass_toolseek');
        if (toolSeek != null && toolSeek is CompassToolSeekTool) {
          final kit = await toolSeek.topToolsFor(userMessage, threshold: 0.55);
          if (kit.isNotEmpty) {
            final buf = StringBuffer();
            for (final t in kit.take(4)) {
              buf.writeln('- ${t.toFullDescription()}');
            }
            localToolKit = buf.toString();
            debugPrint('[AgentLoop] 本地士兵配備 ${kit.take(4).length} 把工具');
          }
        }
      } catch (e) {
        debugPrint('[AgentLoop] 本地士兵配備失敗（fail-open 純對話）: $e');
      }
    }

    // [T4② 2026-10-16 編織線] M2 語氣層注入——companionPersona 之後掛
    // 語氣資產（cloud 85K / e4b 12K 依 ProviderRouter 路由結果選版）。
    // fail-open：資產載入失敗不擋對話。local 走 _buildLocalPrompt 不吃這段。
    String personaWithTone = companionPersona ?? '';
    // [T4②] local 也注入——e4b 版只有 12K（32K ctx 塞得下），靈魂不分雲端本地
    final m2 = await M2PersonaService.instance.personaForCurrentRoute();
    if (m2 != null && m2.isNotEmpty) {
      personaWithTone = personaWithTone.isEmpty
          ? m2
          : '$personaWithTone\n\n---\n$m2';
    }
    // [身份保護 2026-10-21 Blue 令] 三 Agent 身份互不污染——
    // M2 語氣資產是小葵的聲音（含 71 條小葵範例），語氣可借、身份不可借。
    // 病例：小橋被問名字自稱「小葵」。修：注入最尾（近因最強）加身份覆蓋，
    // 範例中的名字一律降級為「風格示範者」。
    final companionName = _activeCompanion?.name;
    if (companionName != null && companionName.isNotEmpty) {
      personaWithTone =
          '$personaWithTone\n\n---\n\n# 身份覆蓋（本段優先於上方語氣規格中的一切身份描述）\n'
          '你的名字是「$companionName」。上方語氣規格（含其中所有範例）是**風格參考**——'
          '範例中出現的「小葵」只是語氣的示範者，不是你。'
          '自稱「$companionName」或「我」，絕不自稱小葵、絕不借用其他夥伴的名字。';
    }

    final systemPrompt = AgentLoopPromptBuilder.build(
      budgetEye: budgetEyeText,
      timelineSection: await _buildTimelineSection(),
      companionPersona: personaWithTone,
      toolRegistry: _agentToolRegistry!,
      contextMemory: contextMemory,
      activeProjectDoorTitle: _activeProjectDoor?.title,
      skillsSection: isLocal
          ? SkillPromptInjector.buildSkillSection(
              userMessage: userMessage,
              localMode: true,
            )
          : SkillPromptInjector.buildSkillSection(userMessage: userMessage),
      canvasContext: _buildCanvasContext(),
      isLocalProvider: isLocal,
      localToolKit: localToolKit,
      agentKnowledgeContext: agentKnowledgeContext,
      personaCard: personaCardText,
      firstConversationDirective: firstConversationDirective,
      memoryRecallNote: memoryRecallNote, // [教練 Agent 2026-07-25] 記憶回溯
      quickAssistantContext:
          _quickAssistantContext, // [教練 Agent 2026-08-03] Quick Assistant 模式
      lockedProvider: userWantsCloud ? userProvider : null, // [教練 Agent 2026-08-07] 指定模式鎖定
      // [聊天模式 B 線 2026-10-20 Blue 拍板] 每輪注入當前模式的紀律 prompt
      // （自由對話模式 prompt 為 null＝不注入，零回歸）
      chatModePrompt: ChatModeService.instance.currentPrompt,
    );

    final sanitizedMessage = AgentToolCallParser.sanitize(userMessage);

    // 組裝含歷史對話的 user message（讓 AI 有上下文）
    String fullUserMessage = sanitizedMessage;
    if (effectiveHistory != null && effectiveHistory.isNotEmpty) {
      final historyParts = <String>[];
      for (final m in effectiveHistory) {
        final role = m['role'] ?? 'user';
        if (role == 'system') continue;
        final content = m['content'] ?? '';
        if (content.trim().isEmpty) continue;
        final label = role == 'assistant' ? '夥伴' : '使用者';
        historyParts.add('[$label]\n$content');
      }
      if (historyParts.isNotEmpty) {
        fullUserMessage =
            '以下是之前的對話歷史：\n\n${historyParts.join('\n\n---\n\n')}\n\n---\n\n使用者最新訊息：\n$sanitizedMessage';
      }
    }

    final result = await _agentLoop!.run(
      systemPrompt: systemPrompt,
      userMessage: fullUserMessage,
      conversationId: _currentConversation?.id, // [T12-④] 對話歸屬落輪
      maxTurns: AgentLoop.hardMaxTurns, // [2026-09-18] Hermes 模式——無輪數限制（Blue 拍板對齊小葵）
      prohibitPaidTools: prohibitPaidTools, // [教練 Agent 2026-08-20] 機器輪次禁用付費工具
      onProgress: (turnIndex, maxTurns, toolCall, toolResult, llmOutput) {
        onAgentLoopProgress?.call(
          turnIndex,
          maxTurns,
          toolCall?.name,
          toolResult?.success == true
              ? 'success'
              : (toolResult?.success == false ? 'failed' : null),
          // [小葵 2026-09-18] 透明化——用 extractText 清掉 tool_call 區塊後傳出
          // 自然語言思路（可能為空字串，UI 端空則不顯示）。原始 output 不外流。
          AgentToolCallParser.extractText(llmOutput).trim(),
        );
      },
      onStage: (stage, {toolName, detail}) {
        // [教練 Agent 2026-08-07] 即時進度回饋——讓使用者看到 Agent 在幹嘛
        onAgentLoopStage?.call(stage, toolName: toolName, detail: detail);
      },
      isCancelled: () => _isLoading == false, // 如果 loading 被取消
      onUserMessage: (message) {
        // [2026-07-19] 使用者插嘴——把訊息加到對話歷史，UI 顯示
        if (_currentConversation != null) {
          final injectMsg = Message(
            id: '${DateTime.now().millisecondsSinceEpoch}_inject',
            role: 'user',
            content: message,
            timestamp: DateTime.now(),
          );
          final conv = _currentConversation!;
          _currentConversation = conv.copyWith(
            messages: [...conv.messages, injectMsg],
            updatedAt: DateTime.now(),
          );
          notifyListeners();
        }
      },
    );

    return result;
  }

  /// [2026-07-19] 使用者插嘴——AgentLoop 運行中注入訊息
  /// 讓使用者可以在原生 Agent工作時中途修正方向
  void injectUserMessage(String message) {
    if (_agentLoop != null && _isLoading) {
      _agentLoop!.injectUserMessage(message);
      debugPrint('[ChatController] 插嘴訊息已注入 AgentLoop: ${message.length} 字');
    }
  }

  /// [教練 Agent 2026-07-22] Phase 5 互動式教學
  /// 直接在對話框注入一條 assistant 訊息（不經過 LLM）。
  /// 用於範本引導教學——Agent 一步步帶領使用者。
  /// [Blue 令 2026-10-17] 主動回應頻道——羅盤/夢的主動發話住獨立 session。
  /// 切到（或建立）proactive 類型對話；不混入使用者當前的對話討論串。
  /// 建立後 _currentConversation 指向它，injectAssistantMessage 落在同一
  /// 個 session；使用者的其他對話不受影響。
  Future<void> openOrCreateProactiveSession() async {
    try {
      // [Blue 令 2026-10-17] 每次主動開話＝一個新對話——回覆後使用者
      // 可能展開新的討論串，共用 session 會洗板。不復用舊的。
      final now = DateTime.now();
      final conv = Conversation.create(
        title: '主動回應 ${now.month}/${now.day}',
        companionId: _activeCompanion?.id,
      ).copyWith(type: ConversationType.proactive, updatedAt: now);
      await ConversationStore.save(conv);
      // [Blue 病例 2026-10-17] 必須加進 _conversations——只設
      // _currentConversation 的話，使用者一點其他對話 reload 列表，
      // proactive session 從 UI 消失（磁碟在但看不到＝丟了）。
      if (!_conversations.any((c) => c.id == conv.id)) {
        _conversations = [conv, ..._conversations];
      }
      _currentConversation = conv;
      notifyListeners();
    } catch (e) {
      debugPrint('[ChatController] proactive session 建立失敗（fail-open '
          '退回當前對話）: $e');
    }
  }

  Future<void> injectAssistantMessage(
    String content, {
    Map<String, dynamic>? metadata,
  }) async {
    if (_currentConversation == null) {
      await createNewConversation();
    }
    if (_currentConversation == null) return;

    // [指紋定律 2026-10-16 Blue] 中間觀察泡泡也簽名——
    // 病例：18:42「我好累」回覆 kind=loop_observation 無 speaker 無 model，
    // 對話列表指紋消失、回覆自稱 AI、無模型署名——三違規一次修。
    final routed = ProviderRouter.instance.current;
    final routedModel = routed == null
        ? null
        : await ApiService.defaultModelFor(routed.providerId);
    final msg = Message(
      id: 'tutorial-${DateTime.now().microsecondsSinceEpoch}',
      role: 'assistant',
      content: content,
      timestamp: DateTime.now(),
      speakerId: _activeCompanion?.id ?? 'native-agent',
      model: routedModel, // 簽名：這則觀察由哪個模型說的
      metadata: metadata ?? {'kind': 'tutorial'},
    );

    final conv = _currentConversation!;
    _currentConversation = conv.copyWith(
      messages: [...conv.messages, msg],
      updatedAt: DateTime.now(),
    );
    await ConversationStore.save(_currentConversation!);
    notifyListeners();
    onScrollToBottom?.call();
  }

  /// [教練 Agent 2026-07-22] Phase 5 互動式教學
  /// 直接在對話框注入一條 user 訊息（不觸發 LLM）。
  /// 用於記錄使用者在教學中的回應。
  Future<void> injectUserMessageSilent(String content) async {
    if (_currentConversation == null) {
      await createNewConversation();
    }
    if (_currentConversation == null) return;

    final msg = Message(
      id: 'tutorial-user-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      content: content,
      timestamp: DateTime.now(),
      metadata: {'kind': 'tutorial'},
    );

    final conv = _currentConversation!;
    _currentConversation = conv.copyWith(
      messages: [...conv.messages, msg],
      updatedAt: DateTime.now(),
    );
    await ConversationStore.save(_currentConversation!);
    notifyListeners();
    onScrollToBottom?.call();
  }

  /// [教練 Agent 2026-07-22] Phase B — 畫布狀態自動注入
  ///
  /// 把畫布快照注入對話歷史。
  /// Agent 不需要主動呼叫 canvas_get_state——畫布狀態會自動推送進來。
  ///
  /// 使用 role: 'user' + [畫布狀態] 前綴，因為 AgentLoop 送 API 時
  /// 只保留 user/assistant messages（L6006 的 .where 過濾）。
  /// UI 透過 metadata.kind 判斷不顯示。
  ///
  /// 兩種模式：
  /// - isFull=true：全量注入（載入畫布時），帶完整節點/連線/拓撲
  /// - isFull=false：增量注入（畫布變化時），只帶變更描述 + 當前概況
  Future<void> injectCanvasSystemMessage(
    String description, {
    required bool isFull,
  }) async {
    if (_currentConversation == null) return;
    // [教練 Agent 2026-07-23] 只注入到畫布對話，不污染一般對話
    if (!_currentConversation!.isProjectCanvas) return;

    final msg = Message(
      id: 'canvas-event-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user', // 用 user role 才能通過 AgentLoop 的 user/assistant 過濾
      content: '[畫布狀態] $description',
      timestamp: DateTime.now(),
      metadata: {
        'kind': isFull ? 'canvas_snapshot' : 'canvas_event',
        'silent': true, // UI 據此不顯示
      },
    );

    // [教練 Agent 2026-08-17 使用者 抓包] 快照堆積治理——
    // 之前每次載入畫布都追加一份全量快照，歷史裡躺著多份新舊矛盾
    // 的快照（舊的說有判斷節點、新的說沒有），LLM 每輪都看到，
    // 只能自己判斷「那是舊訊息不用理」（MimeMi 抓到的現象）。
    // 上線給一般使用者就是 bug。治理規則：
    // - 全量快照（canvas_snapshot）永遠只留最新一份
    // - 增量事件（canvas_event）保留最近 20 則
    final conv = _currentConversation!;
    var kept = List<Message>.from(conv.messages);
    if (isFull) {
      kept = kept
          .where((m) => m.metadata?['kind'] != 'canvas_snapshot')
          .toList();
    }
    final eventIdx = <int>[];
    for (var i = 0; i < kept.length; i++) {
      if (kept[i].metadata?['kind'] == 'canvas_event') eventIdx.add(i);
    }
    if (eventIdx.length >= 20) {
      final removeIds = eventIdx
          .sublist(0, eventIdx.length - 19)
          .map((i) => kept[i].id)
          .toSet();
      kept = kept.where((m) => !removeIds.contains(m.id)).toList();
    }
    _currentConversation = conv.copyWith(
      messages: [...kept, msg],
      updatedAt: DateTime.now(),
    );
    await ConversationStore.save(_currentConversation!);
    // 不呼叫 notifyListeners()——靜默注入，不打擾使用者
    debugPrint(
      '[ChatController] 畫布狀態注入 (${isFull ? "全量" : "增量"}): ${description.length} chars（快照治理：全量留一份、增量留 20 則）',
    );
  }

  /// [2026-07-20] 停止 AgentLoop——使用者按下停止鍵時呼叫
  /// 設 _isLoading=false 讓 isCancelled callback 在下一輪觸發取消
  /// 搭配 stale-stream detection（90s），即使卡在 LLM stream 也能在 90s 內取消
  void stopAgent() {
    if (_isLoading) {
      debugPrint('[ChatController] 使用者按下停止鍵，AgentLoop 將在下一輪取消');
      _isLoading = false;
      _thoughtStage = null;
      _thoughtPulse = false;
      notifyListeners();
      AgentActivityStore.instance.idle();
    }
  }

  /// 統一分析入口——pipeline 優先，fallback 到規則版。
  /// 兩處 analyze 呼叫都走這裡，確保 timeout + fallback 一致。
  Future<BrainReflection> analyzeOrFallback(
    String text, {
    String? activeCompanionRole,
    DoorDecisionContext doorContext = const DoorDecisionContext(),
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await _ensurePipelineInitialized();

    if (_pipeline != null && _pipelineLlmClient?.isAvailable == true) {
      try {
        PipelineResult? result;
        try {
          result = await _pipeline!
              .analyzeAsync(
                text,
                activeCompanionRole: activeCompanionRole,
                doorContext: doorContext,
              )
              .timeout(timeout);
        } on TimeoutException {
          result = null;
        }
        if (result != null) {
          return result.reflection;
        }
      } catch (e) {
        // pipeline 失敗，fallback
      }
    }

    // Fallback：規則版
    return _transurfingBrain.analyze(
      text,
      activeCompanionRole: activeCompanionRole,
      doorContext: doorContext,
    );
  }

  /// [教練 Agent S21e 2026-07-09] 背景跑 LLM 版 brain reflection，不阻塞 Agent Loop
  /// 用於直接執行指令場景（生成圖片、搜尋等），先給規則版結果讓 UI 即時更新，
  /// LLM 版完成後再更新一次。
  /// [教練 Agent 2026-07-22] #4 L1: 黃燈時跳過 LLM brain reflection（省 RAM + API token）
  void _runBrainReflectionBackground({
    required String text,
    required BridgeAction? preliminaryBridgeAction,
  }) {
    if (MemoryGuardService.instance.brainReflectionPaused) {
      debugPrint('[MemoryGuard] L1: 跳過背景 brain reflection');
      return;
    }
    analyzeOrFallback(
          text,
          activeCompanionRole: _activeCompanion?.name,
          doorContext: DoorDecisionContext(
            currentMainlineLabel: '聊天與任務主線',
            activeProjectTitle: _activeProjectDoor?.title,
            activeProjectFlow: _activeProjectDoor?.currentFlow,
            pendingBridgeTaskTitle: _pendingBridgeTask?.title,
            pendingBridgeTaskMissing: _pendingBridgeTask?.missing,
            pendingReturnLabel: _pendingDoorReturn?.deferredLabel,
            requestedCapabilityLabel:
                preliminaryBridgeAction?.type == BridgeActionType.unknown
                ? null
                : preliminaryBridgeAction?.type.displayLabel,
          ),
          timeout: const Duration(seconds: 3),
        )
        .then((result) {
          BrainReflectionStore.instance.update(result);
          _brainReflection = result;
          _thoughtStage = stageForBrainReflection(result);
          notifyListeners();
        })
        .catchError((e) {
          debugPrint('[ChatController] background brain reflection failed: $e');
        });
  }

  // ── Getters (ManagedFolderGuard) ───────────────
  // [以利沙 Sprint 8 Step 4 2026-06-24]
  List<ManagedFolderRule> get managedFolderRules => _managedFolderRules;
  // [以利沙 Sprint 8 Step 4 2026-06-24]
  bool get managedFolderGuardChecking => _managedFolderGuardChecking;

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  /// 讓 _ChatScreenState 直接設定 currentConversation（供 _sendMessage 等使用）。
  void setCurrentConversation(Conversation conv) {
    _currentConversation = conv;
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  /// 讓 _ChatScreenState 直接設定 conversations 列表。
  void setConversations(List<Conversation> convs) {
    _conversations = convs;
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  /// 讓 _ChatScreenState 設定 lastProjectDoorJudgement。
  void setLastProjectDoorJudgement(ProjectDoorCardData? card) {
    _lastProjectDoorJudgement = card;
    notifyListeners();
  }

  // ── State loading ──────────────────────────────

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  Future<void> loadPendingDoorReturn() async {
    final pending = await _doorDecisionStore.loadPendingReturn();
    _pendingDoorReturn = pending;
    notifyListeners();
  }

  /// [Sprint 11 修復] 載入門列表 + 用當前對話的 projectDoorId 決定 active 門
  /// 不再從全局 prefs 讀 active 門——門已綁對話，用對話找門。
  Future<void> loadActiveProjectDoor() async {
    final doors = await _projectDoorStore.loadAll();
    _projectDoors = doors;
    // 用當前對話的 projectDoorId 找門，不 fallback 到全局 prefs
    if (_currentConversation?.projectDoorId != null) {
      _activeProjectDoor = doors
          .where((d) => d.id == _currentConversation!.projectDoorId)
          .firstOrNull;
    } else {
      _activeProjectDoor = null;
    }
    notifyListeners();
  }

  // ── DoorDecision listener ──────────────────────

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  /// 由 DoorDecisionStore.pendingReturn listener 呼叫。
  void handlePendingDoorReturn() {
    _pendingDoorReturn = DoorDecisionStore.pendingReturn.value;
    notifyListeners();
  }

  // ── DoorDecision actions ───────────────────────

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  /// TODO: needs context — ScaffoldMessenger / SnackBar 需要 BuildContext。
  Future<void> chooseDoorDecision(
    DoorDecision decision,
    DoorDecisionChoice choice,
  ) async {
    final pending = decision.defer(choice);
    await _doorDecisionStore.savePendingReturn(pending);
    _pendingDoorReturn = pending;
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  /// TODO: needs context — SnackBar 需要 BuildContext。
  /// 呼叫 onSetMessageInputText 回呼讓 State 層處理輸入框。
  DoorDecisionPendingReturn? get currentPendingDoorReturn => _pendingDoorReturn;

  // ── Pure helpers (no BuildContext dependency) ──

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  bool containsAny(String text, List<String> needles) {
    return needles.any(text.contains);
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  bool isInternalCardMessage(String content) {
    return content.startsWith(capabilityCardPrefix) ||
        content.startsWith(projectDoorCardPrefix) ||
        content.startsWith(projectContextTransferCardPrefix) ||
        content.startsWith(digitalAssetInvocationCardPrefix) ||
        content.startsWith(managedFolderRulePickerCardPrefix) ||
        content.startsWith(projectForkCompleteCardPrefix) ||
        content.startsWith(projectForkIntroCardPrefix) ||
        content.startsWith(digitalAssetResultCardPrefix);
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  String compactProjectDoorTitle(String title) {
    final normalized = title.trim();
    if (normalized.isEmpty) return '專案中';
    if (normalized.length <= 10) return normalized;
    return '${normalized.substring(0, 10)}...';
  }

  /// [Sprint 11 修復 v3] 正則全面重寫
  /// 優先序：引號明確命名 > 叫做/叫/命名為/取名為 > 純引號 > 動詞+名稱+後綴
  /// 關鍵修正：① 「叫」要單獨匹配（不只「叫做」）② 動詞模式排除「名字叫」前綴
  String? explicitProjectDoorTitleFromText(String text) {
    // 模式 1（最高優先）：叫做/叫/命名為/取名為 + 引號
    final namedQuoteMatch = RegExp(
      r'(?:叫做|叫|命名為|取名為)\s*[「『\"]([^」』\"]{2,40})[」』\"]',
    ).firstMatch(text);
    final namedQuoted = namedQuoteMatch?.group(1)?.trim();
    if (namedQuoted != null && namedQuoted.isNotEmpty) return namedQuoted;

    // 模式 2：叫做/叫/命名為/取名為 + 無引號
    final namedMatch = RegExp(
      r'(?:叫做|叫|命名為|取名為)\s*([A-Za-z0-9_\-\u4e00-\u9fff ]{2,40})',
    ).firstMatch(text);
    final named = namedMatch?.group(1)?.trim();
    if (named != null && named.isNotEmpty) {
      return named
          .replaceAll(RegExp(r'(的)?專案門.*$'), '')
          .replaceAll(RegExp(r'(的)?專案.*$'), '')
          .trim();
    }

    // 模式 3：純引號
    final quoteMatch = RegExp(r'[「『\"]([^」』\"]{2,40})[」』\"]').firstMatch(text);
    final quoted = quoteMatch?.group(1)?.trim();
    if (quoted != null && quoted.isNotEmpty) return quoted;

    // 模式 4（最低優先）：動詞 + 名稱 + 後綴
    // 只匹配明確的動詞前綴，排除「名字叫」「一個名字叫」這種
    final verbPrefixPattern = r'(?:建立|創建|開一個|做一個|我要做|啟動一個|新開|另開)';
    final suffixPattern = r'(?:的)?(?:專案|計畫|項目)';
    final extractPattern = RegExp(
      '${verbPrefixPattern}\\s*(.+?)\\s*${suffixPattern}',
    );
    final extractMatch = extractPattern.firstMatch(text.trim());
    if (extractMatch != null) {
      final extracted = extractMatch.group(1)?.trim();
      // 過濾泛詞 + 過濾包含「名字叫」的提取（應該被模式 2 捕獲）
      const genericExtracted = {'個新', '新', '一個新', '個', '新的', '一個'};
      if (extracted != null &&
          extracted.length >= 2 &&
          extracted.length <= 40 &&
          !genericExtracted.contains(extracted) &&
          !extracted.contains('名字叫') &&
          !extracted.contains('名叫')) {
        return extracted;
      }
    }

    return null;
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  bool looksLikeProjectDoorFork(String normalized) {
    if (normalized.isEmpty) return false;
    final asksForNewDoor = containsAny(normalized, const [
      '拉出來',
      '分出來',
      '另開',
      '另外開',
      '新開',
      '創建一個',
      '建立一個',
      '再創一個',
      '再開一個',
      '獨立專案',
      '新的專案',
      '新專案',
      '專案門',
      '叫做',
      '命名為',
    ]);
    final mentionsProject = containsAny(normalized, const [
      '專案',
      '計畫',
      'project',
      'semidao',
      'semi dao',
    ]);
    return asksForNewDoor && mentionsProject;
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  bool shouldAutoCreateProjectDoor(ProjectDoorCardData card, String text) {
    if (!card.forkFromConversation) return false;
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    final hasExplicitTitle = explicitProjectDoorTitleFromText(text) != null;
    final hasCreationVerb = containsAny(normalized, const [
      '創建',
      '建立',
      '開一個',
      '另開',
      '新開',
      '再創',
      '再開',
      '拉出來',
      '分出來',
      '獨立',
    ]);
    final hasProjectDoorTarget = containsAny(normalized, const [
      '專案門',
      '專案',
      'project',
      '計畫',
    ]);
    return card.confidence >= 0.86 &&
        hasExplicitTitle &&
        hasCreationVerb &&
        hasProjectDoorTarget;
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  double projectDoorIntentConfidence(
    String text, {
    required bool shouldForkFromActiveDoor,
    required String? explicitTitle,
  }) {
    final normalized = text.trim().toLowerCase();
    var score = shouldForkFromActiveDoor ? 0.64 : 0.58;
    if (explicitTitle != null && explicitTitle.trim().isNotEmpty) score += 0.14;
    if (containsAny(normalized, const ['專案門', '專案', 'project', '計畫'])) {
      score += 0.10;
    }
    if (containsAny(normalized, const ['拉出來', '分出來', '另開', '新開', '創建', '建立'])) {
      score += 0.10;
    }
    if (containsAny(normalized, const ['先', '獨立', '另外', '分岔'])) {
      score += 0.06;
    }
    if (containsAny(normalized, const ['叫做', '命名為', '取名為'])) {
      score += 0.05;
    }
    return score.clamp(0.0, 0.98).toDouble();
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  List<String> projectDoorConfidenceSignals(
    String text, {
    required bool shouldForkFromActiveDoor,
    required String? explicitTitle,
  }) {
    final normalized = text.trim().toLowerCase();
    return [
      if (shouldForkFromActiveDoor) '目前已有專案，且語意像是在分岔新門',
      if (explicitTitle != null && explicitTitle.trim().isNotEmpty)
        '偵測到明確專案名稱：$explicitTitle',
      if (containsAny(normalized, const ['拉出來', '分出來', '另開', '新開'])) '偵測到分流動詞',
      if (containsAny(normalized, const ['專案門', '專案', 'project', '計畫']))
        '偵測到專案目標',
    ];
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  String normalizeProjectDoorTitle(String title) {
    return title
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('專案門', '專案');
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  List<String> buildProjectTransferContextLines(List<Message> messages) {
    return messages
        .where(
          (message) => message.role == 'user' || message.role == 'assistant',
        )
        .where((message) => !isInternalCardMessage(message.content))
        .toList()
        .reversed
        .take(6)
        .toList()
        .reversed
        .map((message) {
          final speaker = message.role == 'user' ? '使用者' : '夥伴';
          final content = message.content
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          final clipped = content.length > 160
              ? '${content.substring(0, 160)}...'
              : content;
          return '$speaker：$clipped';
        })
        .where((line) => line.trim().length > 4)
        .toList();
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  String summarizeProjectTransferIdea(
    String request,
    List<String> contextLines,
  ) {
    final cleaned = request.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= 90) return cleaned;
    return '${cleaned.substring(0, 90)}...';
  }

  // ── Detection methods ─────────────────────────

  /// [教練 Agent Sprint 1.2 / Sprint 12] async 版門偵測——三層瀑布：
  /// 1. 同步正則版 detectProjectDoorProposal() 取得 base card
  /// 2. 若正則版命中：用 SemanticIntentService.extractDoorTitle() 覆寫 title
  /// 3. 若正則版未命中：用 SemanticIntentService.detectDoorIntent() 讓 LLM 判斷
  /// feature flag false 時直接走同步版（零回歸）。
  Future<ProjectDoorCardData?> detectProjectDoorProposalAsync(
    String text,
    List<Message> messages,
  ) async {
    // 先跑同步版取得 base card（含 signal/metadata）
    final baseCard = detectProjectDoorProposal(text, messages);

    await _ensureSemanticIntentInited();
    final history = ConversationHistoryProvider.extract(messages);

    // 正則版命中 → 嘗試用 SemanticIntentService 取得更好的 title
    if (baseCard != null) {
      if (_semanticIntentService != null) {
        try {
          final titleResult = await _semanticIntentService!.extractDoorTitle(
            message: text,
            history: history,
            activeDoorTitle: _activeProjectDoor?.title,
          );
          if (titleResult?.title != null && titleResult!.title!.isNotEmpty) {
            // 用語意結果覆寫 title（ProjectDoorCardData 沒有 copyWith，手動建構）
            return ProjectDoorCardData(
              title: titleResult.title!,
              sourceIntent: baseCard.sourceIntent,
              firstFlow: baseCard.firstFlow,
              intakeQuestions: baseCard.intakeQuestions,
              requiredBridges: baseCard.requiredBridges,
              confidence: baseCard.confidence,
              confidenceSignals: baseCard.confidenceSignals,
              forkFromConversation: baseCard.forkFromConversation,
              sourceConversationId: baseCard.sourceConversationId,
              sourceConversationTitle: baseCard.sourceConversationTitle,
              contextLines: baseCard.contextLines,
            );
          }
        } catch (_) {
          // 語意服務失敗，用 baseCard 的 title
        }
      }
      return baseCard;
    }

    // [Sprint 12] 正則版未命中 → 讓 LLM 判斷是否要建門（取代 #2 detect() 和 #4 _looksLikeProjectDoor）
    if (_semanticIntentService != null) {
      try {
        final intentResult = await _semanticIntentService!.detectDoorIntent(
          message: text,
          history: history,
          activeDoorTitle: _activeProjectDoor?.title,
        );
        if (intentResult != null && intentResult.shouldCreateDoor) {
          final llmTitle = intentResult.projectName;
          if (llmTitle != null && llmTitle.isNotEmpty) {
            // [Phase 2 #6] 使用 LLM 推斷的 requiredBridges，若空則 fallback
            final bridges = intentResult.requiredBridges.isNotEmpty
                ? intentResult.requiredBridges
                : const ['第二大腦專案索引'];
            return ProjectDoorCardData(
              title: llmTitle,
              sourceIntent: text,
              firstFlow: '目標定義',
              intakeQuestions: const [
                '你要銷售或推進的核心產品/服務是什麼？',
                '目標受眾是誰？他們目前最痛的問題是什麼？',
                '你希望 AI 角色扮演什麼定位：專家、陪伴、娛樂、銷售，還是混合？',
                '第一版成功標準是什麼：成交、名單、觀看數、內容產出，還是品牌曝光？',
                '你希望第一版 MVP 在幾天內完成？',
              ],
              requiredBridges: bridges,
              confidence: intentResult.confidence,
              confidenceSignals: ['LLM 判斷：${intentResult.reasoning}'],
              forkFromConversation: true,
              sourceConversationId: _currentConversation?.id,
              sourceConversationTitle: _currentConversation?.title,
              contextLines: const [],
            );
          }
        }
      } catch (_) {
        // LLM 門偵測失敗，return null
      }
    }

    return null;
  }

  /// [Sprint 12] 門漂移偵測——用 SemanticIntentService.detectDoorDrift() 取代 DoorDriftDetector。
  /// feature flag false 時回傳 null（不偵測）。
  /// 呼叫點：sendMessage 流程中，當有 active door 時背景檢查。
  Future<void> _checkDoorDriftIfNeeded({
    required String currentMessage,
    required List<Message> messages,
  }) async {
    final activeDoor = _activeProjectDoor;
    if (activeDoor == null) return;

    await _ensureSemanticIntentInited();
    if (_semanticIntentService == null) return;

    try {
      final history = ConversationHistoryProvider.extract(messages);
      final recentMessages = messages
          .where((m) => m.role == 'user')
          .take(5)
          .map((m) => m.content)
          .toList();

      final driftResult = await _semanticIntentService!.detectDoorDrift(
        doorTitle: activeDoor.title,
        history: history,
        currentMessage: currentMessage,
        recentMessages: recentMessages,
      );

      if (driftResult != null &&
          driftResult.isDrifting &&
          driftResult.confidence >= 0.7) {
        // 漂移偵測結果存入 brain reflection 供 UI 顯示
        // 不攔截使用者操作——只記錄觀察
        debugPrint(
          '[DoorDrift] 偵測到漂移：${driftResult.reasoning} 建議：${driftResult.suggestion}',
        );
      }
    } catch (_) {
      // 漂移偵測失敗不影響流程
    }
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  ProjectDoorCardData? detectProjectDoorProposal(
    String text,
    List<Message> messages,
  ) {
    final normalized = text.trim().toLowerCase();
    final shouldForkFromActiveDoor =
        _activeProjectDoor != null && looksLikeProjectDoorFork(normalized);
    if (_activeProjectDoor != null && !shouldForkFromActiveDoor) return null;
    final signal = const ProjectDoorSignalService().detect(
      text: text,
      conversationTitle: _currentConversation?.title,
      conversationContext: messages
          .where(
            (message) => message.role == 'user' || message.role == 'assistant',
          )
          .map((message) => message.content),
    );
    if (signal == null) return null;
    final explicitTitle = explicitProjectDoorTitleFromText(text);
    final confidence = projectDoorIntentConfidence(
      text,
      shouldForkFromActiveDoor: shouldForkFromActiveDoor,
      explicitTitle: explicitTitle,
    );
    return ProjectDoorCardData(
      title: explicitTitle ?? signal.title,
      sourceIntent: signal.sourceIntent,
      firstFlow: signal.firstFlow,
      intakeQuestions: signal.intakeQuestions,
      requiredBridges: signal.requiredBridges,
      confidence: confidence,
      confidenceSignals: projectDoorConfidenceSignals(
        text,
        shouldForkFromActiveDoor: shouldForkFromActiveDoor,
        explicitTitle: explicitTitle,
      ),
      forkFromConversation: shouldForkFromActiveDoor,
      sourceConversationId: shouldForkFromActiveDoor
          ? _currentConversation?.id
          : null,
      sourceConversationTitle: shouldForkFromActiveDoor
          ? _currentConversation?.title
          : null,
      contextLines: shouldForkFromActiveDoor
          ? buildProjectTransferContextLines(messages)
          : const [],
    );
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  ProjectDoor? matchProjectDoorForTransfer(String normalizedText) {
    final normalizedDoors = _projectDoors
        .map((door) => MapEntry(door, normalizeProjectDoorTitle(door.title)))
        .where((entry) => entry.value.isNotEmpty)
        .toList();
    for (final entry in normalizedDoors) {
      if (normalizedText.contains(entry.value)) return entry.key;
    }
    for (final entry in normalizedDoors) {
      final tokens = entry.value
          .split(RegExp(r'[\s_/／・:：,，。-]+'))
          .where((token) => token.length >= 3);
      if (tokens.any(normalizedText.contains)) return entry.key;
    }
    if (_activeProjectDoor != null &&
        containsAny(normalizedText, const ['這個專案', '目前專案', '現在專案', '剛才專案'])) {
      return _activeProjectDoor;
    }
    if (_projectDoors.length == 1) return _projectDoors.first;
    return null;
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  ProjectContextTransferCardData? detectProjectContextTransfer(
    String text,
    List<Message> messages,
  ) {
    if (_currentConversation == null || _projectDoors.isEmpty) return null;
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final wantsTransfer = containsAny(normalized, const [
      '放到',
      '放進',
      '放入',
      '歸到',
      '歸入',
      '加到',
      '加進',
      '移到',
      '移進',
      '納入',
      '收進',
      '整理到',
      '記到',
      '寫進',
      '併入',
    ]);
    if (!wantsTransfer || !normalized.contains('專案')) return null;

    final targetDoor = matchProjectDoorForTransfer(normalized);
    if (targetDoor == null) return null;
    if (targetDoor.title.trim() == _currentConversation!.title.trim()) {
      return null;
    }

    final contextLines = buildProjectTransferContextLines(messages);
    if (contextLines.isEmpty) return null;
    return ProjectContextTransferCardData(
      targetProjectId: targetDoor.id,
      targetProjectTitle: targetDoor.title,
      sourceConversationId: _currentConversation!.id,
      sourceConversationTitle: _currentConversation!.title,
      ideaSummary: summarizeProjectTransferIdea(text, contextLines),
      contextLines: contextLines,
    );
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  bool looksLikeProjectContextTransferText(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty || !normalized.contains('專案')) return false;
    return containsAny(normalized, const [
      '放到',
      '放進',
      '放入',
      '歸到',
      '歸入',
      '加到',
      '加進',
      '移到',
      '移進',
      '納入',
      '收進',
      '整理到',
      '記到',
      '寫進',
      '併入',
    ]);
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  bool projectSemanticRouteShouldOverrideBridge(
    String text,
    BridgeAction? action,
  ) {
    if (action == null) return false;
    return looksLikeProjectContextTransferText(text);
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  Future<ProjectSemanticRoute> routeProjectSemanticIntent(
    String text,
    List<Message> messages,
  ) async {
    final projectDoorProposal = await detectProjectDoorProposalAsync(
      text,
      messages,
    );
    if (projectDoorProposal != null) {
      return ProjectSemanticRoute.projectDoor(projectDoorProposal);
    }

    final projectContextTransferProposal = detectProjectContextTransfer(
      text,
      messages,
    );
    if (projectContextTransferProposal != null) {
      return ProjectSemanticRoute.contextTransfer(
        projectContextTransferProposal,
        signals: [
          '偵測到歸檔或移植語意',
          '命中既有專案：${projectContextTransferProposal.targetProjectTitle}',
          '帶入上下文 ${projectContextTransferProposal.contextLines.length} 則',
        ],
      );
    }

    return const ProjectSemanticRoute.none();
  }

  // ── Door action methods ────────────────────────

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  /// 建立專案門卡片（只 append message，不含建立邏輯）。
  Future<void> appendProjectDoorCard(ProjectDoorCardData card) async {
    onAppendLocalSystemMessage?.call(
      '$projectDoorCardPrefix${jsonEncode(card.toJson())}',
    );
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  Future<void> appendProjectContextTransferCard(
    ProjectContextTransferCardData card,
  ) async {
    onAppendLocalSystemMessage?.call(
      '$projectContextTransferCardPrefix${jsonEncode(card.toJson())}',
    );
  }

  /// [Sprint 11 修復 v3] 改專案門名稱，同步更新 store + 清快取 + 清思維面板
  Future<void> renameProjectDoor(String doorId, String newTitle) async {
    final all = await _projectDoorStore.loadAll();
    final index = all.indexWhere((d) => d.id == doorId);
    if (index < 0) return;
    final renamed = all[index].copyWith(
      title: newTitle,
      updatedAt: DateTime.now(),
    );
    await _projectDoorStore.saveActive(renamed);
    _activeProjectDoor = renamed;
    _projectDoors = [renamed, ..._projectDoors.where((d) => d.id != doorId)];
    _lastProjectDoorJudgement = null;
    _brainReflection = null; // [Sprint 11 修復] 清思維面板，否則門名不會同步
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  /// 完整建立專案門流程（含 store、second brain、digital asset、fork）。
  /// TODO: needs context — _appendLocalSystemMessage 需要 State 層注入。
  Future<void> createProjectDoorFromCard(ProjectDoorCardData card) async {
    _lastProjectDoorJudgement = card;
    final door = ProjectDoor.create(
      title: card.title,
      sourceIntent: card.sourceIntent,
      intakeQuestions: card.intakeQuestions,
      requiredBridges: card.requiredBridges,
    );
    final saved = await _projectDoorStore.saveActive(door);

    final now = DateTime.now();
    await _secondBrainFileIndexStore.upsert(
      SecondBrainFileEntry(
        id: saved.secondBrainEntryId,
        title: saved.title,
        path: 'local://project-doors/${saved.id}',
        room: SecondBrainRoom.projects,
        summary:
            '專案門：${saved.title}。目前水流：${saved.currentFlow}。來源意圖：${saved.sourceIntent}',
        contentDigest:
            '使用者已決定啟動一個可落地專案。系統先進入「${saved.currentFlow}」水流，透過引導式提問把模糊構想整理成清楚目標、成功標準與能力橋需求。',
        contentExcerpt:
            '待釐清：${saved.intakeQuestions.take(3).join(' / ')}。需要橋樑：${saved.requiredBridges.join('、')}。',
        tags: ['專案門', saved.currentFlow, ...saved.requiredBridges.take(4)],
        keywords: [
          saved.title,
          saved.sourceIntent,
          saved.currentFlow,
          ...saved.requiredBridges,
        ],
        indexedAt: now,
        trustScore: 82,
        pinned: true,
        agentId: _activeCompanion?.id, // [以利沙 P0 修復十八輪 2026-06-27]
      ),
    );
    final registeredAsset = await _digitalAssetRegistry
        .registerProjectDoorAsset(
          saved,
          sourceConversationId: card.sourceConversationId ?? '',
          sourceLabel:
              card.sourceConversationTitle ?? _currentConversation?.title ?? '',
          contextLines: card.contextLines,
        );

    final reflection = await analyzeOrFallback(
      saved.sourceIntent,
      doorContext: DoorDecisionContext(
        activeProjectTitle: saved.title,
        activeProjectFlow: saved.currentFlow,
      ),
      timeout: const Duration(seconds: 5),
    );
    BrainReflectionStore.instance.update(reflection);

    _activeProjectDoor = saved;
    _projectDoors = [
      saved,
      ..._projectDoors.where((door) => door.id != saved.id),
    ];
    // [Sprint 11] 綁定門與當前對話
    if (_currentConversation != null) {
      final bound = await _projectDoorStore.bindConversation(
        saved.id,
        _currentConversation!.id,
      );
      if (bound != null) {
        _activeProjectDoor = bound;
      }
      final updated = _currentConversation!.copyWith(projectDoorId: saved.id);
      _currentConversation = updated;
      await ConversationStore.save(updated);
    }
    _brainReflection = reflection;
    _secondBrainTrace = SecondBrainTrace(
      agentName: _activeCompanion?.name,
      recalledMemories: [
        SecondBrainMemoryTrace(
          content:
              '專案門：${saved.title}。目前水流：${saved.currentFlow}。接下來先完成目標定義，再逐步回到能力橋與執行任務。',
          room: SecondBrainRoom.projects.label,
          sourceLabel: saved.title,
          sourcePath: 'local://project-doors/${saved.id}',
          reason: '使用者已確認要把這個大目標變成可追蹤專案，因此寫入計畫房間並釘選。',
          retrievalSignals: ['專案門', saved.currentFlow, '使用者確認'],
          freshnessLabel: '剛建立',
          sourcePreview: saved.sourceIntent,
          tags: ['計畫房間', saved.currentFlow, ...saved.requiredBridges.take(2)],
          trustScore: 82,
        ),
      ],
      newInsights: [
        SecondBrainNewInsightTrace(
          content: '使用者正在啟動「${saved.title}」，之後回答應優先掛回這條主線。',
          room: SecondBrainRoom.projects.label,
          tags: ['專案門', '主線', saved.currentFlow],
        ),
        SecondBrainNewInsightTrace(
          content: '已把「${registeredAsset.title}」登錄為可跨專案與多 Agent 調用的數位資產。',
          room: registeredAsset.kind.defaultRoom.label,
          tags: [
            '數位資產',
            registeredAsset.kind.label,
            ...registeredAsset.tags.take(2),
          ],
        ),
      ],
      associations: ['${saved.title} ↔ ${saved.requiredBridges.join(' ↔ ')}'],
    );
    notifyListeners();

    if (card.forkFromConversation) {
      final sourceConversationId = card.sourceConversationId;
      final sourceConversation = sourceConversationId == null
          ? _currentConversation
          : await ConversationStore.getById(sourceConversationId);
      final sourceTitle =
          card.sourceConversationTitle ?? sourceConversation?.title ?? '目前對話';
      final introCard = ProjectForkIntroCardData(
        projectTitle: saved.title,
        sourceProjectTitle: sourceTitle,
        forkReason: saved.sourceIntent,
        contextLines: card.contextLines,
        currentFlow: saved.currentFlow,
        intakeQuestions: saved.intakeQuestions,
        requiredBridges: saved.requiredBridges,
        assetTitle: registeredAsset.title,
      );
      final assetResultCard = digitalAssetResultCardFromAsset(
        registeredAsset,
        sourceProjectTitle: saved.title,
      );
      final projectConversation = Conversation.create(title: saved.title).copyWith(
        updatedAt: DateTime.now(),
        messages: [
          Message(
            id: 'project-fork-${DateTime.now().microsecondsSinceEpoch}',
            role: 'assistant',
            content:
                '$projectForkIntroCardPrefix${jsonEncode(introCard.toJson())}',
            timestamp: DateTime.now(),
            metadata: {
              'kind': 'project_door_fork',
              'projectDoorId': saved.id,
              'sourceConversationId': sourceConversation?.id,
            },
          ),
          Message(
            id: 'project-asset-result-${DateTime.now().microsecondsSinceEpoch}',
            role: 'assistant',
            content:
                '$digitalAssetResultCardPrefix${jsonEncode(assetResultCard.toJson())}',
            timestamp: DateTime.now(),
            metadata: {
              'kind': 'digital_asset_result',
              'assetId': registeredAsset.id,
              'projectDoorId': saved.id,
            },
          ),
        ],
      );
      await ConversationStore.save(projectConversation);
      await ConversationStore.setCurrentId(projectConversation.id);

      if (sourceConversation != null) {
        final forkDoneCard = ProjectForkCompleteCardData(
          targetProjectId: projectConversation.id,
          targetProjectTitle: saved.title,
          sourceProjectId: sourceConversation.id,
          sourceProjectTitle: sourceConversation.title,
          contextCount: card.contextLines.length,
          assetTitle: registeredAsset.title,
        );
        final sourceUpdated = sourceConversation.copyWith(
          updatedAt: DateTime.now(),
          messages: [
            ...sourceConversation.messages,
            Message(
              id: 'project-fork-marker-${DateTime.now().microsecondsSinceEpoch}',
              role: 'assistant',
              content:
                  '$projectForkCompleteCardPrefix${jsonEncode(forkDoneCard.toJson())}',
              timestamp: DateTime.now(),
              metadata: {
                'kind': 'project_door_fork_marker',
                'projectDoorId': saved.id,
                'targetConversationId': projectConversation.id,
              },
            ),
          ],
        );
        await ConversationStore.save(sourceUpdated);
      }

      final all = await ConversationStore.getAll();
      _currentConversation = projectConversation;
      _conversations = all;
      notifyListeners();
      onScrollToBottom?.call();
      return;
    }

    if (_currentConversation != null) {
      final renamed = _currentConversation!.copyWith(
        title: saved.title,
        updatedAt: DateTime.now(),
      );
      await ConversationStore.save(renamed);
      final all = await ConversationStore.getAll();
      _currentConversation = renamed;
      _conversations = all;
      notifyListeners();
      onScrollToBottom?.call();
    }

    onAppendLocalSystemMessage?.call(
      [
        '已建立專案門：${saved.title}',
        '',
        '目前水流：${saved.currentFlow}',
        '',
        '我們先像顧問一樣把模糊目標收斂成可執行任務。請先回答：',
        for (final entry in saved.intakeQuestions.asMap().entries)
          '${entry.key + 1}. ${entry.value}',
        '',
        '需要的橋我也先放進能力清單：${saved.requiredBridges.join('、')}。',
        '',
        '已同步成數位資產：${registeredAsset.title}',
        '之後其他專案或 Agent 可以在第二大腦裡調用這包資產。',
      ].join('\n'),
    );
    onAppendLocalSystemMessage?.call(
      '$digitalAssetResultCardPrefix${jsonEncode(digitalAssetResultCardFromAsset(registeredAsset, sourceProjectTitle: saved.title).toJson())}',
    );
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  DigitalAssetResultCardData digitalAssetResultCardFromAsset(
    DigitalAsset asset, {
    required String sourceProjectTitle,
  }) {
    final projectTitles = _projectDoors
        .map((door) => door.title.trim())
        .where(
          (title) => title.isNotEmpty && title != sourceProjectTitle.trim(),
        )
        .take(5)
        .toList();
    return DigitalAssetResultCardData(
      assetId: asset.id,
      assetTitle: asset.title,
      assetKind: asset.kind.label,
      assetSummary: asset.summary,
      sourceProjectTitle: sourceProjectTitle,
      capabilities: asset.capabilities,
      reusableScenes: asset.reusableScenes,
      availableProjects: projectTitles,
    );
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  /// TODO: needs context — _appendLocalSystemMessage 需要 State 層注入。
  Future<void> startProjectDoorFromCurrentConversation({
    required String draftText,
    required Future<void> Function() ensureConversation,
  }) async {
    if (_activeProjectDoor != null) {
      onAppendLocalSystemMessage?.call(
        '目前已經有專案門：${_activeProjectDoor!.title}\n目前水流：${_activeProjectDoor!.currentFlow}\n我會優先把接下來的回答掛回這條主線。',
      );
      return;
    }

    await ensureConversation();
    final currentText = draftText.trim();
    final messages = [
      ...?_currentConversation?.messages,
      if (currentText.isNotEmpty)
        Message(
          id: 'draft-${DateTime.now().millisecondsSinceEpoch}',
          role: 'user',
          content: currentText,
          timestamp: DateTime.now(),
        ),
    ];
    final joined = messages
        .where(
          (message) => message.role == 'user' || message.role == 'assistant',
        )
        .map((message) => message.content)
        .join('\n');
    final sourceIntent = currentText.isNotEmpty
        ? currentText
        : joined.trim().isNotEmpty
        ? joined.trim().split('\n').last
        : '使用者想把目前對話整理成可執行專案。';
    final context = joined.trim().isEmpty ? sourceIntent : joined;
    final contextLower = context.toLowerCase();
    const signalService = ProjectDoorSignalService();
    final card =
        await detectProjectDoorProposalAsync(sourceIntent, messages) ??
        ProjectDoorCardData(
          title: signalService.titleForContext(contextLower),
          sourceIntent: sourceIntent,
          firstFlow: '目標定義',
          intakeQuestions: const [
            '你想完成的最終畫面是什麼？請用一句話描述。',
            '這個專案第一版要服務誰？他們遇到什麼問題？',
            '你希望第一版先產出什麼可驗證成果？',
            '你目前已經有什麼素材、帳號、工具或限制？',
            '你希望我先幫你規劃、查資料、產出文件，還是拆任務？',
          ],
          requiredBridges: signalService.bridgesForContext(contextLower),
        );

    await appendProjectDoorCard(card);
  }

  // ── Card parsers ───────────────────────────────

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  ProjectDoorCardData? tryParseProjectDoorCard(String content) {
    if (!content.startsWith(projectDoorCardPrefix)) return null;
    try {
      final jsonText = content.substring(projectDoorCardPrefix.length);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return null;
      return ProjectDoorCardData.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  ProjectContextTransferCardData? tryParseProjectContextTransferCard(
    String content,
  ) {
    if (!content.startsWith(projectContextTransferCardPrefix)) return null;
    try {
      final jsonText = content.substring(
        projectContextTransferCardPrefix.length,
      );
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return null;
      return ProjectContextTransferCardData.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  ProjectForkCompleteCardData? tryParseProjectForkCompleteCard(String content) {
    if (!content.startsWith(projectForkCompleteCardPrefix)) return null;
    try {
      final jsonText = content.substring(projectForkCompleteCardPrefix.length);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return null;
      return ProjectForkCompleteCardData.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  ProjectForkIntroCardData? tryParseProjectForkIntroCard(String content) {
    if (!content.startsWith(projectForkIntroCardPrefix)) return null;
    try {
      final jsonText = content.substring(projectForkIntroCardPrefix.length);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return null;
      return ProjectForkIntroCardData.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  // ── Context transfer ───────────────────────────

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  /// TODO: needs context — _appendLocalSystemMessage 需要 State 層注入。
  Future<void> transferContextToProject(
    ProjectContextTransferCardData card,
  ) async {
    final now = DateTime.now();
    final all = await ConversationStore.getAll();
    Conversation? targetConversation;
    for (final conv in all) {
      if (conv.title.trim() == card.targetProjectTitle.trim()) {
        targetConversation = conv;
        break;
      }
    }
    final target =
        targetConversation ??
        Conversation.create(title: card.targetProjectTitle);
    final importedContent = [
      '已從「${card.sourceConversationTitle}」移植一段想法到本專案。',
      '',
      '移植摘要：${card.ideaSummary}',
      '',
      '相關上下文：',
      for (final line in card.contextLines) '- $line',
      '',
      '下一步：把這段素材放進目前專案水流，判斷是否要形成任務、素材、腳本或待辦。',
    ].join('\n');
    final targetUpdated = target.copyWith(
      updatedAt: now,
      messages: [
        ...target.messages,
        Message(
          id: 'project-import-${now.microsecondsSinceEpoch}',
          role: 'assistant',
          content: importedContent,
          timestamp: now,
          metadata: {
            'kind': 'project_context_import',
            'sourceConversationId': card.sourceConversationId,
            'targetProjectId': card.targetProjectId,
          },
        ),
      ],
    );
    await ConversationStore.save(targetUpdated);

    await _secondBrainFileIndexStore.upsert(
      SecondBrainFileEntry(
        id: 'project-context-${card.targetProjectId}-${now.microsecondsSinceEpoch}',
        title: '移植想法：${card.ideaSummary}',
        path:
            'local://project-doors/${card.targetProjectId}/imported-context/${now.microsecondsSinceEpoch}',
        room: SecondBrainRoom.projects,
        summary:
            '從「${card.sourceConversationTitle}」移植到「${card.targetProjectTitle}」。',
        contentDigest: importedContent,
        contentExcerpt: card.contextLines.take(3).join(' / '),
        tags: ['專案門', '上下文移植', card.targetProjectTitle],
        keywords: [
          card.targetProjectTitle,
          card.ideaSummary,
          ...card.contextLines.take(4),
        ],
        indexedAt: now,
        trustScore: 76,
        pinned: false,
        agentId: _activeCompanion?.id, // [以利沙 P0 修復十八輪 2026-06-27]
      ),
    );

    final source = await ConversationStore.getById(card.sourceConversationId);
    if (source != null) {
      final sourceUpdated = source.copyWith(
        updatedAt: DateTime.now(),
        messages: [
          ...source.messages,
          Message(
            id: 'project-transfer-${DateTime.now().microsecondsSinceEpoch}',
            role: 'assistant',
            content:
                '「${card.ideaSummary}」已移到「${card.targetProjectTitle}」專案中。\n你可以留在這裡繼續聊天，也可以到專案門裡繼續深入。',
            timestamp: DateTime.now(),
            metadata: {
              'kind': 'project_context_transfer_done',
              'targetProjectId': card.targetProjectId,
            },
          ),
        ],
      );
      await ConversationStore.save(sourceUpdated);
      if (_currentConversation?.id == sourceUpdated.id) {
        _currentConversation = sourceUpdated;
        notifyListeners();
      }
    }

    final refreshed = await ConversationStore.getAll();
    _conversations = refreshed;
    notifyListeners();
    onScrollToBottom?.call();
  }

  /// [以利沙 Sprint 8 Step 3 2026-06-24]
  SecondBrainRoom documentAssetRoomForCurrentContext() {
    return _activeProjectDoor == null
        ? SecondBrainRoom.files
        : SecondBrainRoom.projects;
  }

  // ════════════════════════════════════════════════════════════════
  // ManagedFolderGuard 邏輯 — [以利沙 Sprint 8 Step 4 2026-06-24]
  // ════════════════════════════════════════════════════════════════

  /// [以利沙 Sprint 8 Step 4 2026-06-24]
  /// 載入受管資料夾規則，並觸發守門檢查。
  Future<void> loadManagedFolderRules({String trigger = '進入聊天'}) async {
    await _managedFolderRuleStore.ensureBuiltInRules();
    final rules = await _managedFolderRuleStore.loadAll();
    _managedFolderRules = rules;
    notifyListeners();
    unawaited(checkManagedFolderGuard(trigger: trigger));
  }

  /// [以利沙 Sprint 8 Step 4 2026-06-24]
  /// 檢查受管資料夾是否有新檔案，若有則透過回呼附加提醒卡片。
  Future<void> checkManagedFolderGuard({required String trigger}) async {
    if (_managedFolderGuardChecking || _currentConversation == null) return;
    final userRules = _managedFolderRules
        .where((rule) => rule.isValid && !rule.isBuiltIn)
        .toList(growable: false);
    if (userRules.isEmpty) return;
    _managedFolderGuardChecking = true;
    notifyListeners();
    try {
      final checks = await _managedFolderGuardStore.checkRules(userRules);
      if (_currentConversation == null) return;
      final alerts = checks.where((check) => check.hasNewFiles).toList();
      for (final check in alerts.take(3)) {
        await _appendManagedFolderGuardCard(check, trigger: trigger);
        if (_currentConversation == null) return;
      }
    } catch (error) {
      developer.log(
        'Managed folder guard check failed',
        name: 'Bridge.ManagedFolderGuard',
        error: error,
      );
    } finally {
      _managedFolderGuardChecking = false;
      notifyListeners();
    }
  }

  /// [以利沙 Sprint 8 Step 4 2026-06-24]
  /// 組裝守門提醒 BridgeActionResult，透過 onAppendBridgeResult 回呼交給 State 層附加。
  Future<void> _appendManagedFolderGuardCard(
    ManagedFolderGuardCheck check, {
    required String trigger,
  }) async {
    final newCount = check.newFiles.length;
    final categorySummary = _guardCategorySummary(check.newFiles);
    final result = BridgeActionResult(
      status: BridgeActionStatus.completed,
      message: [
        '受管資料夾守門提醒。',
        '我在「${check.rule.folderLabel}」發現 $newCount 個新檔案，尚未搬移或改名。',
        '你可以先讓我依目前規則產生整理計畫，再決定是否執行。',
      ].join('\n'),
      metadata: {
        'type': BridgeActionType.desktopFiles.legacyType,
        'kind': 'managed_folder_guard',
        'provider': 'bridge_desktop',
        'adapter': '受管資料夾守門',
        'trigger': trigger,
        'folderPath': check.rule.folderPath,
        'folderLabel': check.rule.folderLabel,
        'ruleTitle': check.rule.ruleTitle,
        'rulePath': check.rule.rulePath,
        'mode': check.rule.modeLabel,
        'newFileCount': newCount,
        'fileCount': check.fileCount,
        'knownFileCount': check.knownFileCount,
        'categorySummary': categorySummary,
        'samples': [for (final file in check.newFiles.take(12)) file.toJson()],
        'scanPrompt': LocalDesktopFilesAdapter.scanPrompt(
          rootPath: check.rule.folderPath,
          taskPrompt: '依受管資料夾規則「${check.rule.ruleTitle}」檢查新增檔案，先列出整理計畫，不要搬移檔案',
        ),
      },
    );
    await onAppendBridgeResult?.call(result);
  }

  /// [以利沙 Sprint 8 Step 4 2026-06-24]
  /// 把新檔案依 kind 分類計數，取前 5 名做摘要。
  String _guardCategorySummary(List<ManagedFolderGuardFile> files) {
    if (files.isEmpty) return '尚無新檔案';
    final counts = <String, int>{};
    for (final file in files) {
      counts[file.kind] = (counts[file.kind] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(5)
        .map((entry) => '${entry.key} ${entry.value}')
        .join('、');
  }

  // ════════════════════════════════════════════════════════════════
  // Brain / Companion 邏輯 — [以利沙 Sprint 8 Step 5 2026-06-24]
  // ════════════════════════════════════════════════════════════════

  // ── Getters (Brain / Companion) ───────────────────
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  bool get showMemoryFlash => _showMemoryFlash;
  String? get memoryFlashText => _memoryFlashText;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  bool get brainPulse => _brainPulse;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  AgentActivityStage? get thoughtStage => _thoughtStage;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  bool get thoughtPulse => _thoughtPulse;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  AgentActivityTelemetry get thoughtTelemetry => _thoughtTelemetry;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  AgentActivityStage? get lastBrainActionStage => _lastBrainActionStage;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  AgentActivityTelemetry get lastBrainActionTelemetry =>
      _lastBrainActionTelemetry;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  String? get activeBridgeActionLabel => _activeBridgeActionLabel;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  String? get lastBridgeActionLabel => _lastBridgeActionLabel;
  // [教練 Agent P0.5b 2026-08-07] 圖片任務真實進度 label，供 UI 監聽顯示。
  String? get imageProgressLabel => _imageProgressLabel;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  bool get showBrainReflectionPanel => _showBrainReflectionPanel;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  List<String> get recalledBrainInsights => _recalledBrainInsights;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  BrainSkillRegistrySnapshot? get brainSkillRegistry => _brainSkillRegistry;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  AgentMotivationSnapshot? get agentMotivation => _agentMotivation;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  Map<String, TransurfingInsightFeedback> get insightFeedbacks =>
      _insightFeedbacks;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  Map<String, SecondBrainMemoryFeedback> get secondBrainMemoryFeedbacks =>
      _secondBrainMemoryFeedbacks;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  Map<String, SecondBrainAssociationFeedback>
  get secondBrainAssociationFeedbacks => _secondBrainAssociationFeedbacks;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  Map<String, SecondBrainRoom> get secondBrainMemoryRoomOverrides =>
      _secondBrainMemoryRoomOverrides;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  AgentCompanionMood? get companionMoodOverride => _companionMoodOverride;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  AgentCompanionAction? get companionActionOverride => _companionActionOverride;
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  Companion? get activeCompanion => _activeCompanion;

  // ── Setters for State-layer delegation ────────────
  // [以利沙 Sprint 8 Step 5 2026-06-24]
  set showBrainReflectionPanel(bool value) {
    _showBrainReflectionPanel = value;
    notifyListeners();
  }

  // ── Brain reflection snapshot restore ─────────────

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 從 BrainReflectionStore 恢復快照。
  void restoreBrainReflectionSnapshot() {
    final snapshot = BrainReflectionStore.instance.current;
    if (snapshot == null || _brainReflection != null) return;
    _brainReflection = snapshot;
    notifyListeners();
  }

  // ── Thought stage / pulse ─────────────────────────

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 設定思考階段，同步更新 AgentActivityStore。
  void setThoughtStage(AgentActivityStage stage) {
    _thoughtStage = stage;
    _lastBrainActionStage = stage;
    notifyListeners();
    AgentActivityStore.instance.update(
      stage: stage,
      telemetry: _thoughtTelemetry,
      pulse: _thoughtPulse,
      mood: _companionMoodOverride,
      action: _companionActionOverride,
    );
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 啟動思考脈動 Timer。
  void startThoughtPulse() {
    _thoughtPulseTimer?.cancel();
    _thoughtPulse = true;
    AgentActivityStore.instance.update(
      stage: _thoughtStage ?? AgentActivityStage.understanding,
      telemetry: _thoughtTelemetry,
      pulse: true,
      mood: _companionMoodOverride,
      action: _companionActionOverride,
    );
    _thoughtPulseTimer = Timer.periodic(const Duration(milliseconds: 850), (_) {
      _thoughtPulse = !_thoughtPulse;
      notifyListeners();
      AgentActivityStore.instance.update(
        stage: _thoughtStage ?? AgentActivityStage.understanding,
        telemetry: _thoughtTelemetry,
        pulse: _thoughtPulse,
        mood: _companionMoodOverride,
        action: _companionActionOverride,
      );
    });
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 更新思考遙測數據。
  void updateThoughtTelemetry({
    int? messages,
    int? chars,
    int? memories,
    int? bridgeActions,
    int? attachments,
    int? tokens,
  }) {
    _thoughtTelemetry = _thoughtTelemetry.copyWith(
      messages: messages,
      chars: chars,
      memories: memories,
      bridgeActions: bridgeActions,
      attachments: attachments,
      tokens: tokens,
    );
    _lastBrainActionTelemetry = _thoughtTelemetry;
    notifyListeners();
    AgentActivityStore.instance.update(
      stage: _thoughtStage ?? AgentActivityStage.understanding,
      telemetry: _thoughtTelemetry,
      pulse: _thoughtPulse,
      mood: _companionMoodOverride,
      action: _companionActionOverride,
    );
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 停止思考脈動，重載相關狀態。
  void stopThinking() {
    _thoughtPulseTimer?.cancel();
    _isLoading = false;
    _thoughtStage = null;
    _thoughtPulse = false;
    _thoughtTelemetry = const AgentActivityTelemetry();
    _companionMoodOverride = null;
    _companionActionOverride = null;
    _imageProgressLabel = null;
    _imageProgressEvents.clear();
    notifyListeners();
    AgentActivityStore.instance.idle();
  }

  // ── Memory flash ──────────────────────────────────

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 觸發記憶閃現，2 秒後自動關閉。
  void triggerMemoryFlash(String text) {
    _memoryFlashText = text;
    _showMemoryFlash = true;
    _brainPulse = true;
    notifyListeners();

    _memoryFlashTimer?.cancel();
    _memoryFlashTimer = Timer(const Duration(seconds: 2), () {
      _showMemoryFlash = false;
      notifyListeners();
    });

    Future.delayed(const Duration(milliseconds: 1500), () {
      _brainPulse = false;
      notifyListeners();
    });
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 設定 memory flash 狀態（含 brainPulse + timer），用於多處 feedback 場景。
  void setMemoryFlash({required String text, bool pulse = true}) {
    _memoryFlashText = text;
    _showMemoryFlash = true;
    _brainPulse = pulse;
    notifyListeners();

    _memoryFlashTimer?.cancel();
    _memoryFlashTimer = Timer(const Duration(seconds: 2), () {
      _showMemoryFlash = false;
      notifyListeners();
    });

    Future.delayed(const Duration(milliseconds: 1500), () {
      _brainPulse = false;
      notifyListeners();
    });
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 設定 memory flash 狀態（由 _sendMessage 內 inline 設定時使用）。
  void setMemoryFlashState({
    required String? text,
    required bool show,
    required bool pulse,
  }) {
    _memoryFlashText = text;
    _showMemoryFlash = show;
    _brainPulse = pulse;
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 啟動 memory flash auto-hide timer（_sendMessage 內 inline 用）。
  void startMemoryFlashTimer() {
    _memoryFlashTimer?.cancel();
    _memoryFlashTimer = Timer(const Duration(seconds: 2), () {
      _showMemoryFlash = false;
      notifyListeners();
    });
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 延遲關閉 brainPulse（_sendMessage 內 inline 用）。
  void scheduleBrainPulseOff() {
    Future.delayed(const Duration(milliseconds: 1500), () {
      _brainPulse = false;
      notifyListeners();
    });
  }

  // ── Smart Memory Extraction (慢車道) ──────────────

  /// [教練 Agent 2026-07-03]
  /// LLM 語意記憶提取 — 背景並行，不阻塞對話。
  ///
  /// 正則快車道（extractFromMessage）只抓「記住：」「我叫」等明確前綴。
  /// 此方法用 LLM 理解語意，抓隱含的、無前綴詞的記憶。
  ///
  /// 設計要點：
  /// - 不 await（fire-and-forget）— 不阻塞 _sendMessage
  /// - 失敗靜默 — 只 debugPrint，不影響主流程
  /// - 去重 — 與正則已提取的記憶做文字比對 + 向量去重
  /// - 寫入 BrainContainerService（含向量、分類、重要性）
  // ── Companion ─────────────────────────────────────

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 載入活躍夥伴。
  void loadActiveCompanion() {
    _activeCompanion = CompanionStore().activeCompanion;
    // [身份保護 2026-10-21] 夥伴名同步 AgentLoop（直通道用真名）
    _agentLoop?.companionName = _activeCompanion?.name;
    // [2026-08-26 共視修復] 訂閱換人廣播——任何入口（切換 sheet/控制中心/外觀頁）
    // 換夥伴時，本 controller 即時跟上，人格注入不再卡在前一位。
    if (!_companionChangedHooked) {
      _companionChangedHooked = true;
      CompanionStore().addCompanionChangedListener((companion) {
        _activeCompanion = companion;
        // [身份保護 2026-10-21] 換夥伴＝換靈魂——直通道真名跟著換
        _agentLoop?.companionName = companion?.name;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  bool _companionChangedHooked = false;

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 同步 BridgeActionResult 的證據到 CompanionRuntimeStore。
  void syncBridgeEvidenceToCompanion(BridgeActionResult result) {
    final evidence = _bridgeActionEvidence.describe(result);
    if (evidence == null) return;
    CompanionRuntimeStore.instance.reportBridgeEvidence(
      summary: evidence,
      completed: result.status == BridgeActionStatus.completed,
    );
  }

  // ── Brain reflection batch update ─────────────────

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 批次更新 brain 反思相關欄位（_sendMessage 內 setState 的 brain 部分）。
  void updateBrainReflectionBatch({
    required BrainReflection? brainReflection,
    required List<String> recalledBrainInsights,
    required SecondBrainTrace? secondBrainTrace,
    required BrainSkillRegistrySnapshot? brainSkillRegistry,
    required AgentMotivationSnapshot? agentMotivation,
    required Map<String, TransurfingInsightFeedback> insightFeedbacks,
    required Map<String, SecondBrainAssociationFeedback>
    secondBrainAssociationFeedbacks,
    required AgentActivityStage thoughtStage,
    required AgentActivityTelemetry thoughtTelemetry,
    required AgentCompanionMood? companionMoodOverride,
    required AgentCompanionAction? companionActionOverride,
    String? activeBridgeActionLabel,
    String? lastBridgeActionLabel,
    String? memoryFlashText,
    bool? showMemoryFlash,
    bool? brainPulse,
  }) {
    _brainReflection = brainReflection;
    _recalledBrainInsights = recalledBrainInsights;
    _secondBrainTrace = secondBrainTrace;
    _brainSkillRegistry = brainSkillRegistry;
    _agentMotivation = agentMotivation;
    _insightFeedbacks = insightFeedbacks;
    _secondBrainAssociationFeedbacks = secondBrainAssociationFeedbacks;
    _thoughtStage = thoughtStage;
    _thoughtTelemetry = thoughtTelemetry;
    _lastBrainActionStage = thoughtStage;
    _lastBrainActionTelemetry = thoughtTelemetry;
    _companionMoodOverride = companionMoodOverride;
    _companionActionOverride = companionActionOverride;
    if (activeBridgeActionLabel != null) {
      _activeBridgeActionLabel = activeBridgeActionLabel;
    }
    if (lastBridgeActionLabel != null) {
      _lastBridgeActionLabel = lastBridgeActionLabel;
    }
    if (memoryFlashText != null) {
      _memoryFlashText = memoryFlashText;
    }
    if (showMemoryFlash != null) {
      _showMemoryFlash = showMemoryFlash;
    }
    if (brainPulse != null) {
      _brainPulse = brainPulse;
    }
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 更新第二大腦記憶回饋 map。
  void updateSecondBrainMemoryFeedbacks(
    String key,
    SecondBrainMemoryFeedback feedback,
  ) {
    _secondBrainMemoryFeedbacks = {
      ..._secondBrainMemoryFeedbacks,
      key: feedback,
    };
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 更新第二大腦房間覆寫 map。
  void updateSecondBrainMemoryRoomOverrides(String key, SecondBrainRoom room) {
    _secondBrainMemoryRoomOverrides = {
      ..._secondBrainMemoryRoomOverrides,
      key: room,
    };
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 撤回第二大腦記憶校正。
  void revertSecondBrainMemoryFeedbacks(String key) {
    _secondBrainMemoryFeedbacks = {..._secondBrainMemoryFeedbacks}..remove(key);
    _secondBrainMemoryRoomOverrides = {..._secondBrainMemoryRoomOverrides}
      ..remove(key);
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 更新第二大腦關聯回饋 map。
  void updateSecondBrainAssociationFeedbacks(
    String key,
    SecondBrainAssociationFeedback feedback,
  ) {
    _secondBrainAssociationFeedbacks = {
      ..._secondBrainAssociationFeedbacks,
      key: feedback,
    };
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 更新 agentMotivation。
  void setAgentMotivation(AgentMotivationSnapshot? motivation) {
    _agentMotivation = motivation;
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 更新 _lastProjectDoorJudgement（feedback 為 muted 時設 null）。
  void setLastProjectDoorJudgementForFeedback(ProjectDoorCardData? card) {
    _lastProjectDoorJudgement = card;
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 更新 secondBrainTrace + lastBridgeActionLabel（bridge action 完成後）。
  void setSecondBrainTraceAndBridgeLabel({
    required SecondBrainTrace? trace,
    required String? label,
  }) {
    _secondBrainTrace = trace;
    _lastBridgeActionLabel = label;
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 重載 loading 思考相關狀態（_sendMessage 回應完成後）。
  void resetThoughtStateAfterResponse() {
    _thoughtPulseTimer?.cancel();
    AgentActivityStore.instance.idle();
    _isLoading = false;
    _thoughtStage = null;
    _thoughtPulse = false;
    _thoughtTelemetry = const AgentActivityTelemetry();
    _activeBridgeActionLabel = null;
    _imageProgressLabel = null;
    _imageProgressEvents.clear();
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 設定 loading + thought 相關狀態（_executeBridgeAction 開始時）。
  void setBridgeActionThinkingState({
    required AgentActivityStage stage,
    required String? activeBridgeActionLabel,
    required SecondBrainTrace? secondBrainTrace,
    required AgentActivityTelemetry thoughtTelemetry,
  }) {
    _isLoading = true;
    _thoughtStage = stage;
    _activeBridgeActionLabel = activeBridgeActionLabel;
    _lastBridgeActionLabel = activeBridgeActionLabel;
    _secondBrainTrace = secondBrainTrace;
    _thoughtTelemetry = thoughtTelemetry;
    notifyListeners();
  }

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 更新第二腦關聯 feedback（build 方法內 inline 用）。
  void setSecondBrainAssociationFeedbacks(
    Map<String, SecondBrainAssociationFeedback> feedbacks,
  ) {
    _secondBrainAssociationFeedbacks = feedbacks;
    notifyListeners();
  }

  // ════════════════════════════════════════════════════════════════
  // Sprint 8 Step 6 — _sendMessage / _executeBridgeAction 及輔助方法
  // [以利沙 Sprint 8 Step 6 2026-06-24]
  // ════════════════════════════════════════════════════════════════

  // ── 新增 callback（由 _ChatScreenState 注入）──────────
  // [以利沙 Sprint 8 Step 6 2026-06-24]
  void Function(String)? onShowError;
  void Function(BridgeActionResult)? onShowBridgeResultSnackBar;
  void Function()? onFocusMessageInput;
  void Function()? onClearMessageInput;
  String Function()? onGetMessageText;
  void Function(String)? onSetMessageText; // [以利沙 P1 任務延續 2026-06-26]
  void Function(List<Observation>)? onShowConsciousnessObservation;

  // [教練 Agent 2026-07-30 Phase 4] 自訂調用原則——由 _ChatScreenState 注入 context 顯示 dialog
  Future<bool?> Function(CustomRoutingPolicy draft)? onShowPolicyConfirmDialog;

  // ── 新增 getters ──────────────────────────────────
  // [以利沙 Sprint 8 Step 6 2026-06-24]
  bool get isLoading => _isLoading;
  // [教練 Agent 2026-08-08] 教練模式 debug 暴露
  bool get isLoadingForDebug => _isLoading;
  dynamic get agentLoopForDebug => _agentLoop;
  dynamic get currentConversationForDebug => _currentConversation;
  bool get agentLoopEnabledForDebug => _agentLoopEnabled;
  bool get agentLoopInitedForDebug => _agentLoopInited;
  String? get agentLoopInitErrorForDebug => _agentLoopInitError;
  int get totalTokens => _totalTokens;
  String get currentMode => _currentMode;
  UserIntent? get manualIntent => _manualIntent;
  PendingBridgeTask? get pendingBridgeTask => _pendingBridgeTask;
  // [以利沙 第九輪修復 2026-06-27]
  CapabilityAdvisorCardData? get activeAdvisorCard => _activeAdvisorCard;

  // ── Setters for State-layer delegation ────────────
  // [以利沙 Sprint 8 Step 6 2026-06-24]
  // [S18] State 重構：讓 State 層直接寫入 controller，取代影子欄位
  set manualIntent(UserIntent? value) {
    _manualIntent = value;
    notifyListeners();
  }

  set currentMode(String value) {
    _currentMode = value;
    notifyListeners();
  }

  set currentConversation(Conversation? value) {
    _currentConversation = value;
    notifyListeners();
  }

  set conversations(List<Conversation> value) {
    _conversations = value;
    notifyListeners();
  }

  set activeCompanion(Companion? value) {
    _activeCompanion = value;
    notifyListeners();
  }

  set pendingBridgeTask(PendingBridgeTask? value) {
    _pendingBridgeTask = value;
    notifyListeners();
  }

  set secondBrainTrace(SecondBrainTrace? value) {
    _secondBrainTrace = value;
    notifyListeners();
  }

  // [S18] onFlash callback 直接寫入 controller
  set agentMotivation(AgentMotivationSnapshot? value) {
    _agentMotivation = value;
    notifyListeners();
  }

  set showMemoryFlash(bool value) {
    _showMemoryFlash = value;
    notifyListeners();
  }

  set memoryFlashText(String? value) {
    _memoryFlashText = value;
    notifyListeners();
  }

  set brainPulse(bool value) {
    _brainPulse = value;
    notifyListeners();
  }

  // [S18] ChatMemoryHandler 回饋欄位直接寫入 controller
  set recalledBrainInsights(List<String> value) {
    _recalledBrainInsights = value;
    notifyListeners();
  }

  set insightFeedbacks(Map<String, TransurfingInsightFeedback> value) {
    _insightFeedbacks = value;
    notifyListeners();
  }

  set secondBrainMemoryFeedbacks(Map<String, SecondBrainMemoryFeedback> value) {
    _secondBrainMemoryFeedbacks = value;
    notifyListeners();
  }

  set secondBrainAssociationFeedbacks(
    Map<String, SecondBrainAssociationFeedback> value,
  ) {
    _secondBrainAssociationFeedbacks = value;
    notifyListeners();
  }

  set secondBrainMemoryRoomOverrides(Map<String, SecondBrainRoom> value) {
    _secondBrainMemoryRoomOverrides = value;
    notifyListeners();
  }

  set lastProjectDoorJudgement(ProjectDoorCardData? value) {
    _lastProjectDoorJudgement = value;
    notifyListeners();
  }

  // ── 純邏輯輔助方法（無 BuildContext 依賴）──────────

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  AgentActivityTelemetry telemetryFromMessages(
    List<Message> messages, {
    int memories = 0,
    int attachments = 0,
  }) {
    return AgentActivityTelemetry(
      messages: messages.length,
      chars: messages.fold<int>(
        0,
        (total, message) => total + message.content.length,
      ),
      memories: memories,
      attachments: attachments,
    );
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<BrainSkillRegistrySnapshot> buildBrainSkillRegistrySafely(
    String text, {
    BridgeAction? bridgeAction,
  }) async {
    try {
      return await _capabilityCatalog.buildBrainSkillRegistry(
        text,
        bridgeAction: bridgeAction,
      );
    } catch (error) {
      debugPrint('[CapabilityCatalog] skipped: $error');
      return const BrainSkillRegistrySnapshot(
        summary: '能力目錄暫時無法讀取；聊天與橋樑執行仍會照常進行。',
      );
    }
  }

  /// [小葵 2026-10-14 M3-第三刀] 糾正→reaction→熔斷評估 接線。
  /// appendReaction 原本在生產環境從未被呼叫（校準訊號源死線）——
  /// 糾正＝明確負反應，落 'corrected' reaction；隨後評估熔斷。
  /// [小葵 2026-10-15 T2/D3] 隱式接受接線——上一輪 turn 補 accepted reaction。
  /// 條件：上一輪尚無任何 reaction（appendReaction 冪等去重）＋非糾正訊息。
  /// 之後若使用者真的糾正（同輪稍後 detect 到），appendReaction 會因
  /// accepted 先佔而拒絕——糾正訊號不可被隱式接受吞掉，順序設計：
  /// detect 先跑、hit==null 才補 accepted。
  Future<void> _wireImplicitAccept() async {
    try {
      // [T12-④] 帶對話歸屬——多對話並行時不再指錯輪
      final turnId = EventLedger.instance
          .lastTurnId(conversationId: _currentConversation?.id);
      if (turnId != null) {
        EventLedger.instance.appendReaction(turnId, 'accepted');
      }
    } catch (_) {
      // fail-quiet：隱式訊號失敗絕不影響對話
    }
  }

  Future<void> _wireCorrectionToBreaker() async {
    try {
      // [T12-④] 帶對話歸屬
      final turnId = EventLedger.instance
          .lastTurnId(conversationId: _currentConversation?.id);
      if (turnId != null) {
        final ok = EventLedger.instance.appendReaction(turnId, 'corrected');
        if (ok) {
          debugPrint('[M3] 糾正落 reaction（turn=$turnId）→ 熔斷評估');
          await CalibrationBreaker.instance.evaluate();
        }
      }
    } catch (e) {
      debugPrint('[M3] 接線失敗（fail-quiet）: $e');
    }
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  AgentMotivationSnapshot fallbackAgentMotivationSnapshot() {
    final agentName = _activeCompanion?.name.trim();
    return AgentMotivationSnapshot(
      agentName: agentName == null || agentName.isEmpty ? '夥伴' : agentName,
      driveXp: 0,
      driveLevel: 1,
      accuracyScore: 60,
      resonanceScore: 60,
      autonomyScore: 60,
      usefulFeedbackCount: 0,
      correctionCount: 0,
      mutedCount: 0,
      learningFocus: '等待校準',
      lastSignal: '能力橋優先執行',
    );
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  String? activeVisionImagePath(String? imagePath) {
    final current = imagePath?.trim();
    if (current != null && current.isNotEmpty) return current;
    final messages = _currentConversation?.messages.reversed;
    if (messages == null) return null;
    for (final message in messages) {
      if (message.role != 'user') continue;
      final previous = message.imagePath?.trim();
      if (previous != null && previous.isNotEmpty) return previous;
    }
    return null;
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<BridgeAction?> prepareDesktopFilesAction(BridgeAction action) async {
    if (action.type != BridgeActionType.desktopFiles) return action;
    final prompt = action.prompt.trim();
    if (prompt.startsWith(LocalDesktopFilesAdapter.applyPlanPrefix) ||
        prompt.startsWith(
          LocalDesktopFilesAdapter.scanAuthorizedFolderPrefix,
        )) {
      return action;
    }
    if (kIsWeb) return action;

    final folderPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '選擇要讓 Bridge 只讀掃描的資料夾',
    );
    final normalizedPath = folderPath?.trim();
    if (normalizedPath == null || normalizedPath.isEmpty) return null;

    return BridgeAction(
      type: action.type,
      prompt: LocalDesktopFilesAdapter.scanPrompt(
        rootPath: normalizedPath,
        taskPrompt: prompt.isEmpty ? '整理授權資料夾' : prompt,
      ),
      provider: 'local_desktop_files',
      model: action.model,
      imageQuality: action.imageQuality,
      referenceImagePaths: action.referenceImagePaths,
      requiresConfirmation: action.requiresConfirmation,
      runStatus: action.runStatus,
      statusMessage: action.statusMessage,
    );
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  AgentActivityStage stageForBrainReflection(BrainReflection reflection) {
    switch (reflection.recommendedMove) {
      case RecommendedMove.convertToOutput:
        return AgentActivityStage.context;
      case RecommendedMove.reduceImportance:
        return AgentActivityStage.understanding;
      case RecommendedMove.routeBridge:
        return AgentActivityStage.routing;
      case RecommendedMove.takeNextAction:
        return AgentActivityStage.routing;
      case RecommendedMove.askClarifyingQuestion:
        return AgentActivityStage.understanding;
      case RecommendedMove.answerDirectly:
        if (reflection.needsAttentionGate) return AgentActivityStage.context;
        return AgentActivityStage.understanding;
      case RecommendedMove.declareIntention:
        return AgentActivityStage.understanding;
      case RecommendedMove.recordWaterAction:
        return AgentActivityStage.routing;
    }
  }

  // [教練 Agent Sprint 2 2026-07-04] 宣告/確認/行動閉環路由
  /// 在 pipeline 跑完後呼叫，偵測宣告/確認/完成觸發詞，
  /// 回傳路由結果（可能覆寫 recommendedMove）。
  /// 如果沒命中任何觸發詞，回傳 null（不覆寫）。
  Future<IntentionRouterResult?> _handleIntentionRouting(
    String text,
    BrainReflection reflection,
  ) async {
    // 延遲初始化 IntentionRouter（需要 BrainContainerService 已初始化）
    if (_intentionRouter == null) {
      try {
        final adapter = BrainContainerServiceAdapter();
        _intentionRouter = IntentionRouter(adapter);
      } catch (e) {
        return null;
      }
    }

    final result = await _intentionRouter!.handleMove(
      message: text,
      pipelineMove: reflection.recommendedMove,
      contextSnapshot: 'move=${reflection.recommendedMove.name}',
    );

    // 如果 move 沒被覆寫，回傳 null（不影響原 reflection）
    if (result.move == reflection.recommendedMove &&
        result.statusMessage == null) {
      return null;
    }
    return result;
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  String? bridgeInsightLabel(BridgeAction? action) {
    if (action == null) return null;
    switch (action.type) {
      case BridgeActionType.browse:
        return '新聞與網頁搜尋橋：查詢最新網頁資料，整理重點與來源。';
      case BridgeActionType.vision:
        return '圖片辨識橋：讀取圖片內容，整理可見線索。';
      case BridgeActionType.generateMusic:
        return '音樂生成橋：需要音樂服務才能產出音訊。';
      case BridgeActionType.generateImage:
        return '圖片生成橋：依照提示詞產生角色或素材圖。';
      case BridgeActionType.generateVideo:
        return '影片生成橋：需要影片服務才能產出影片。';
      case BridgeActionType.generateAnimation:
        return '角色動態接口：目前保留給未來穩定動畫功能模組。';
      case BridgeActionType.document:
        return '文件生成橋：把內容整理成可保存文件。';
      case BridgeActionType.desktopFiles:
        return '桌面整理橋：先只讀掃描授權資料夾，產生分類與整理計畫。';
      case BridgeActionType.unknown:
        return null;
    }
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  String? bridgeInsightLabelForResult(
    BridgeAction action,
    BridgeActionResult result,
  ) {
    final base = bridgeInsightLabel(action);
    if (action.type != BridgeActionType.browse) return base;
    final metadata = result.metadata;
    final query = metadata?['query']?.toString().trim();
    final count = metadata?['sourceCount']?.toString().trim();
    final health = metadata?['sourceHealth']?.toString();
    final parts = <String>[
      if (query != null && query.isNotEmpty) '查詢「$query」',
      if (count != null && count.isNotEmpty) '來源 $count 筆',
      if (health == 'sources_missing') '需要補來源',
    ];
    if (parts.isEmpty) return base;
    return '新聞與網頁搜尋橋：${parts.join('，')}。';
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  String bridgeStatusLabel(BridgeActionStatus status) {
    switch (status) {
      case BridgeActionStatus.completed:
        return '完成';
      case BridgeActionStatus.needsProvider:
        return '缺少能力';
      case BridgeActionStatus.needsConfirmation:
        return '等待確認';
      case BridgeActionStatus.unsupported:
        return '未完成';
    }
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  List<Map<String, dynamic>> searchSourceMaps(Map<String, dynamic>? metadata) {
    final rawSources = metadata?['searchSources'];
    if (rawSources is! List) return const [];
    return rawSources
        .whereType<Map>()
        .map((source) => Map<String, dynamic>.from(source))
        .toList();
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  String documentAssetTraceTitle(BridgeActionResult result) {
    final title = result.metadata?['title']?.toString().trim();
    if (title != null && title.isNotEmpty) return '文件資產：$title';
    return '文件資產';
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  String? documentAssetPrimaryPath(BridgeActionResult result) {
    final metadataPath = result.metadata?['path']?.toString().trim();
    if (metadataPath != null && metadataPath.isNotEmpty) return metadataPath;
    final mediaUrl = result.mediaUrl?.trim();
    if (mediaUrl != null && mediaUrl.isNotEmpty) return mediaUrl;
    return null;
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  String? desktopFilesPrimaryPath(BridgeActionResult result) {
    final recordPath = result.metadata?['recordPath']?.toString().trim();
    if (recordPath != null && recordPath.isNotEmpty) return recordPath;
    final rootPath = result.metadata?['rootPath']?.toString().trim();
    if (rootPath != null && rootPath.isNotEmpty) return rootPath;
    return null;
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  String? basename(String? path) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final normalized = trimmed.replaceAll('\\', Platform.pathSeparator);
    final parts = normalized
        .split(Platform.pathSeparator)
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return trimmed;
    return parts.last;
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  String desktopFilesAssetTraceTitle(BridgeActionResult result) {
    final root = desktopFilesPrimaryPath(result);
    final rootName = basename(root);
    final executed = result.metadata?['executed'] == true;
    if (rootName == null || rootName.isEmpty) {
      return executed ? '桌面整理紀錄' : '桌面整理計畫';
    }
    return executed ? '桌面整理紀錄：$rootName' : '桌面整理計畫：$rootName';
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  String dioErrorMessage(DioException e) {
    if (e.response != null) {
      return '伺服器回應 ${e.response?.statusCode}: ${e.response?.data?['error']?['message'] ?? e.message}';
    }
    return e.message ?? '未知錯誤';
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  String bridgeActionLabel(String type) {
    switch (type) {
      case 'browse':
        return '瀏覽網頁';
      case 'vision':
        return '圖片辨識';
      case 'document':
        return '產出文件';
      case 'desktop_files':
        return '桌面整理';
      default:
        return type;
    }
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  String bridgeResultStatusMessage(BridgeActionResult result) {
    final evidence = _bridgeActionEvidence.describe(result);
    if (evidence == null) return result.message;
    return '${result.message}\n$evidence';
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  bool shouldAutoExecuteAssistantAction(BridgeAction action) {
    switch (action.type) {
      case BridgeActionType.browse:
      case BridgeActionType.vision:
      case BridgeActionType.document:
      case BridgeActionType.desktopFiles:
        return true;
      case BridgeActionType.generateImage:
      case BridgeActionType.generateAnimation:
      case BridgeActionType.generateMusic:
      case BridgeActionType.generateVideo:
      case BridgeActionType.unknown:
        return false;
    }
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<AgentMotivationChange?> applyInsightFeedback(
    String insight,
    TransurfingInsightFeedback feedback,
  ) async {
    return _agentMotivationEngine.applyInsightFeedback(
      agentName: _activeCompanion?.name,
      insight: insight,
      feedback: feedback,
    );
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  TransurfingInsightFeedback? inferRecalledInsightFeedback(String reply) {
    final normalized = reply.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    const muteSignals = [
      '完全不對',
      '整個不對',
      '根本不對',
      '不是我的意思',
      '先別用',
      '不要再引用',
      '不要用',
      '別採用',
      '胡說',
      '亂講',
      '離題',
    ];
    const inaccurateSignals = [
      '不太對',
      '有點不對',
      '不是很準',
      '不準',
      '我懷疑',
      '有疑問',
      '怪怪的',
      '可能不是',
      '不確定',
      '再想想',
    ];
    const accurateSignals = [
      '沒錯',
      '正確',
      '準確',
      '很準',
      '合理',
      '同意',
      '就是這樣',
      '對的',
      '很好',
      '太好了',
      '我喜歡',
    ];

    if (containsAny(normalized, muteSignals)) {
      return TransurfingInsightFeedback.muted;
    }
    if (containsAny(normalized, inaccurateSignals)) {
      return TransurfingInsightFeedback.inaccurate;
    }
    if (containsAny(normalized, accurateSignals)) {
      return TransurfingInsightFeedback.accurate;
    }
    return null;
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<void> applyImplicitRecalledInsightFeedback(String reply) async {
    final feedback = inferRecalledInsightFeedback(reply);
    if (feedback == null || _recalledBrainInsights.isEmpty) return;

    for (final insight in _recalledBrainInsights.take(3)) {
      if (_insightFeedbacks[insight] == feedback) continue;
      await applyInsightFeedback(insight, feedback);
    }
  }

  // ════════════════════════════════════════════════════════════════
  // [小葵 2026-10-05 Blue 令] 對話中討論夢境議題後自動裁決
  //
  // Blue：「我希望未來我在對話中跟他討論他需要我裁決的事情，
  // 討論好後確定裁決方案後。他可以自動的在這邊把未裁決的事情
  // 變成已裁決，並且在已裁決的列表中顯示我裁決的內容＋日期。」
  //
  // v1 偵測（Blue 2026-10-05 擴權令）：不只是「裁決」二字——
  // 「我要」「我決定」「我想要」「我覺得…才對」「好就…做」
  // 「好就依你的決定做」——只要是認可的語氣而且有結論，都算。
  // 誤判防護：必須有未裁決卡存在；訊息非疑問收尾；一則裁一張。
  // ════════════════════════════════════════════════════════════════
  static final RegExp _affirmativeDecision = RegExp(
    r'裁決|我決定|決定[:：]|就依你的|就照你|就這樣(做|辦|定了)?|'
    r'我(要|想要).{2,}|我覺得.{2,}(才對|比較好|好了)|'
    r'好[，, ]?.{0,12}(做|辦|走|改|上)',
  );

  Future<void> applyImplicitDreamAdjudication(String reply) async {
    try {
      final text = reply.trim();
      if (text.isEmpty) return;

      final store = LifeTreeStore.instance;
      // 最新一張未裁決的 propose/escalate 卡
      final pending = store.recentDreams(limit: 60).where((d) =>
          (d.decision == 'propose' || d.decision == 'escalate_to_user') &&
          d.adjudicatedAt == null);
      if (pending.isEmpty) return;

      // 疑問收尾＝還在討論，不是裁決（「這樣做好嗎？」不算）
      final isQuestion =
          text.endsWith('?') || text.endsWith('？') || text.endsWith('嗎');
      if (isQuestion) return;

      // 認可語氣＋有結論（v1 語感詞庫）
      if (!_affirmativeDecision.hasMatch(text)) return;

      final target = pending.first;
      // 裁決內容＝使用者整則訊息（回憶用；原始脈絡在對話史裡）
      final ok = store.adjudicate(target.id!, text);
      if (ok) {
        debugPrint('[DreamAdjudication] 對話裁決已入帳：夢卡 #${target.id}');
      }
    } catch (e) {
      // fail-open：自動裁決失敗不擋對話
      debugPrint('[DreamAdjudication] 失敗（不擋對話）: $e');
    }
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<void> applyImplicitProjectDoorJudgementFeedback(String reply) async {
    final card = _lastProjectDoorJudgement;
    if (card == null) return;
    final feedback = inferRecalledInsightFeedback(reply);
    if (feedback == null) return;

    final signal =
        '專案門判斷｜${card.title}｜${card.sourceIntent}｜信心 ${(card.confidence * 100).round()}%';
    final progressChange = await applyInsightFeedback(signal, feedback);
    final motivation = await _agentMotivationEngine.getSnapshot(
      _activeCompanion?.name,
    );
    _agentMotivation = motivation;
    _lastProjectDoorJudgement = feedback == TransurfingInsightFeedback.muted
        ? null
        : card;
    _memoryFlashText = switch (feedback) {
      TransurfingInsightFeedback.accurate =>
        '專案門判斷 +${progressChange?.brainProgressChange?.awardedXp ?? 0} XP：這次分流被確認',
      TransurfingInsightFeedback.inaccurate => '專案門判斷已校正：下次會更保守',
      TransurfingInsightFeedback.muted => '專案門判斷已收斂：先別沿用這次分流',
    };
    _showMemoryFlash = true;
    _brainPulse = feedback == TransurfingInsightFeedback.accurate;
    notifyListeners();
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  CapabilityGapCardData capabilityGapFromBridgeResult(
    BridgeActionResult result, {
    BridgeAction? bridgeAction,
  }) {
    final type = result.metadata?['type']?.toString() ?? '';
    final prompt =
        result.metadata?['prompt']?.toString() ??
        bridgeAction?.prompt ??
        result.message;
    final route =
        result.metadata?['setupRoute']?.toString().trim().isNotEmpty == true
        ? result.metadata!['setupRoute'].toString().trim()
        : '/golden-keys?returnTo=/chat';
    final desktopRoute = routeWithReturnTo(route);
    switch (type) {
      case 'generate_music':
        return CapabilityGapCardData(
          title: '開通音樂生成能力',
          request: prompt,
          missing: '音樂生成服務 / SemiDAO 音樂生成功能模組',
          status: '橋樑已理解你的音樂任務，但目前沒有可執行的音樂生成服務。',
          route: route,
          routeLabel: '設定生成能力',
          iconName: 'music_note',
          steps: const [
            '到 API Key 申請頁面新增支援音樂生成的服務。',
            '貼上官方 API Key 並完成連線測試。',
            '回到這段對話，重新執行已保留的音樂任務。',
          ],
          providerHints: const ['音樂生成服務官方入口', 'SemiDAO 音樂生成額外功能'],
        );
      case 'vision':
        return CapabilityGapCardData(
          title: '開通圖片識別能力',
          request: prompt,
          missing: '圖片理解服務 / 圖像理解額外功能',
          status: '橋樑已理解你的圖片分析任務，但目前尚未接上可用 Vision 能力。',
          route: route,
          routeLabel: '設定圖片理解能力',
          iconName: 'image_search',
          steps: const [
            '到服務設定頁確認支援 Vision 的服務。',
            '完成 API Key 開通測試。',
            '回到這段對話，我會接續分析原本那張圖片。',
          ],
          providerHints: const ['OpenAI Vision', '支援圖像理解的雲端模型'],
        );
      case 'browse':
        return CapabilityGapCardData(
          title: '開通新聞與網頁搜尋能力',
          request: prompt,
          missing: 'OpenAI 網頁搜尋 / 搜尋橋服務',
          status: '橋樑已理解你的搜尋任務，但目前尚未接上可用的網頁搜尋金鑰。',
          route: route,
          routeLabel: '設定搜尋能力',
          iconName: 'travel_explore',
          steps: const [
            '到服務設定頁確認 OpenAI 或其他搜尋服務已設定。',
            '貼上官方 API Key 並完成連線測試。',
            '完成後回到原任務，我會繼續查找、整理來源與摘要。',
          ],
          providerHints: const ['OpenAI Web Search', 'Bridge Desktop 搜尋功能模組'],
        );
      case 'desktop_files':
        return CapabilityGapCardData(
          title: '開啟桌面整理橋',
          request: prompt,
          missing: 'Bridge Desktop 檔案讀取器 / 本機資料夾授權',
          status:
              '橋樑已理解你要整理本機檔案；目前這個畫面是開發預覽，不能直接讀取你的桌面。請改用桌面 App 測試，讓 Bridge Desktop 在本機安全掃描。',
          route: desktopRoute,
          routeLabel: '檢查桌面橋',
          iconName: 'desktop_windows',
          steps: const [
            '開啟 Bridge 桌面 App，確認桌面橋狀態為可用。',
            '授權要整理的桌面、下載或文件資料夾。',
            '回到這段任務，我會先只讀掃描並列出整理計畫；你確認後才會搬移檔案。',
          ],
          providerHints: const ['Bridge Desktop', '本機資料夾授權', '只讀掃描優先'],
        );
      case 'generate_image':
      case 'generate_animation':
      case 'generate_video':
        return CapabilityGapCardData(
          title: '開通生成能力',
          request: prompt,
          missing: result.metadata?['provider']?.toString() ?? '生成服務',
          status: result.message,
          route: route,
          routeLabel: '設定生成能力',
          iconName: 'auto_awesome',
          steps: const [
            '到服務設定頁確認對應生成服務已設定。',
            '貼上官方 API Key 並完成連線測試。',
            '回到這段對話，重新執行已保留的生成任務。',
          ],
          providerHints: const ['圖像 / 影片 / 動態生成官方服務', 'SemiDAO 額外功能'],
        );
      case 'document':
      default:
        return CapabilityGapCardData(
          title: '開通橋樑能力',
          request: prompt,
          missing: result.metadata?['provider']?.toString() ?? '橋樑服務',
          status: result.message,
          route:
              result.metadata?['setupRoute']?.toString() ??
              '/settings?returnTo=/chat',
          routeLabel: '檢查設定',
          iconName: 'hub',
          steps: const [
            '檢查主腦金鑰、Gateway 與能力服務狀態。',
            '完成連線測試。',
            '回到這段對話，重新執行已保留的任務。',
          ],
          providerHints: const ['主腦服務', 'Bridge Gateway', '本地文件引擎'],
        );
    }
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  /// [小葵 2026-09-15 Blue 抓包] 記憶/偏好類請求判定。
  /// 使用者要夥伴「記住」事情（偏好、事實、習慣描述）——這是夥伴
  /// 當下就能完成的記憶寫入（大腦容器），不是任何外部能力缺口。
  /// 病例：「請記住：我喜歡喝咖啡，每天早上都要來一杯」被「每天」
  /// 誤判成排程需求去搜市面提醒方案。
  /// 判定準則（寧可漏判也不誤傷——真排程請求通常含明確時間+動作動詞）：
  /// - 記憶動詞（記住/請記住/幫我記/remember）開頭或出現
  /// - 自我偏好陳述（我喜歡/我偏好/我愛/我討厭/我不喜歡/my favorite）
  /// 且不含明確排程指令動詞（提醒我/通知我/鬧鐘/remind me）
  bool _looksLikeMemoryPreferenceRequest(String normalized) {
    final memoryVerbs = [
      '請記住', '記住', '幫我記', '幫我記住', '請帮我记得', 'remember', 'remember that',
    ];
    final preferencePatterns = [
      '我喜歡', '我偏好', '我愛', '我討厭', '我不喜歡', '我不要', 'my favorite', 'i like', 'i prefer',
    ];
    final scheduleActionVerbs = [
      '提醒我', '通知我', '叫我起床', '鬧鐘', 'remind me', 'notify me', 'wake me',
    ];
    final hasScheduleAction = scheduleActionVerbs.any((v) => normalized.contains(v));
    if (hasScheduleAction) return false; // 明確排程動作 → 不豁免
    final hasMemoryVerb = memoryVerbs.any((v) => normalized.contains(v));
    final hasPreference = preferencePatterns.any((v) => normalized.contains(v));
    return hasMemoryVerb || hasPreference;
  }

  CapabilityGapCardData? detectCapabilityGap(String text, {String? imagePath}) {
    // [以利沙 P2 修復 2026-06-27] advisor 完成後一次性跳過，防止無限循環
    if (_skipNextCapabilityGapDetect) {
      _skipNextCapabilityGapDetect = false;
      return null;
    }
    // [v214 小葵 2026-09-02 Blue 抓包] 畫布對話不做能力顧問——
    // 排程/提醒在畫布有原生解法（schedule 節點+trigger 接頭+Agent
    // 建節點工具）。畫布裡喊「排程」是要 Agent 建排程節點，
    // 不是要去市集找方案。跳過 advisor，讓 agent loop 直接動手，
    // 進度不卡。
    final _cv = _currentConversation;
    if (_cv != null && _cv.isProjectCanvas) {
      return null;
    }
    // [以利沙 P0 修復十一輪 2026-06-27] 檢查此 gapType 是否已永久開通（用快取同步判斷）
    if (_unlockedCapabilities.isNotEmpty) {
      final normalizedCheck = text.trim().toLowerCase();
      if (_unlockedCapabilities.contains('browse') &&
          (normalizedCheck.contains('最新') ||
              normalizedCheck.contains('查一下') ||
              normalizedCheck.contains('搜尋') ||
              normalizedCheck.contains('幫我查') ||
              normalizedCheck.contains('新聞'))) {
        return null;
      }
      // [以利沙 P0 修復十二輪 2026-06-27] 泛化豁免：schedule_reminder、local_model
      if (_unlockedCapabilities.contains('schedule_reminder') &&
          (normalizedCheck.contains('提醒') ||
              normalizedCheck.contains('通知') ||
              normalizedCheck.contains('排程') ||
              normalizedCheck.contains('每天') ||
              normalizedCheck.contains('定時') ||
              normalizedCheck.contains('鬧鐘') ||
              normalizedCheck.contains('待辦') ||
              normalizedCheck.contains('任務清單') ||
              normalizedCheck.contains('清單') ||
              normalizedCheck.contains('記事') ||
              normalizedCheck.contains('備忘') ||
              normalizedCheck.contains('定期') ||
              normalizedCheck.contains('習慣') ||
              normalizedCheck.contains('打卡') ||
              normalizedCheck.contains('remind') ||
              normalizedCheck.contains('reminder') ||
              normalizedCheck.contains('schedule') ||
              normalizedCheck.contains('notify') ||
              normalizedCheck.contains('alarm'))) {
        return null;
      }
      if (_unlockedCapabilities.contains('local_model') &&
          (normalizedCheck.contains('本地模型') ||
              normalizedCheck.contains('本地部署') ||
              normalizedCheck.contains('離線模型') ||
              normalizedCheck.contains('ollama') ||
              normalizedCheck.contains('llama') ||
              normalizedCheck.contains('自己的模型') ||
              normalizedCheck.contains('不用雲端') ||
              normalizedCheck.contains('不需要網路') ||
              normalizedCheck.contains('本地 ai 模型') ||
              normalizedCheck.contains('自架模型') ||
              normalizedCheck.contains('私有模型') ||
              normalizedCheck.contains('不上傳') ||
              normalizedCheck.contains('隱私模型') ||
              normalizedCheck.contains('不上雲') ||
              normalizedCheck.contains('不要雲端') ||
              normalizedCheck.contains('資料不外傳') ||
              normalizedCheck.contains('在我電腦上跑') ||
              normalizedCheck.contains('本地執行') ||
              normalizedCheck.contains('離線執行'))) {
        return null;
      }
    }
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    if (!shouldShowCapabilityGapForRequest(text, imagePath: imagePath)) {
      return null;
    }
    // [小葵 2026-09-15 Blue 抓包] 記憶/偏好類請求豁免——
    // 「請記住：我喜歡喝咖啡，每天早上都要來一杯」裡的「每天」誤觸發
    // schedule_reminder 分支，去搜市面提醒方案。但使用者意圖是「記住」
    // （夥伴當下就能做，記憶寫入大腦容器），不是要外部排程服務。
    // 修法：意圖含「記住/偏好」時直接跳過能力顧問——記憶不是能力缺口。
    // 真正要排程的情況（「每天早上 7 點提醒我澆水」）不含記憶動詞，
    // 不受此豁免影響。
    if (_looksLikeMemoryPreferenceRequest(normalized)) {
      return null;
    }
    if (isAnalysisOrFeasibilityQuestion(normalized) &&
        !isRealtimeLookupQuestion(normalized)) {
      return null;
    }
    final mentionsImage =
        normalized.contains('圖像') ||
        normalized.contains('圖片') ||
        normalized.contains('照片') ||
        normalized.contains('影像') ||
        normalized.contains('image') ||
        normalized.contains('vision');
    final asksRecognition =
        normalized.contains('識別') ||
        normalized.contains('辨識') ||
        normalized.contains('看得懂') ||
        normalized.contains('看一下') ||
        normalized.contains('分析') ||
        normalized.contains('recognize') ||
        normalized.contains('describe');
    // [以利沙 P1 修復 2026-06-27] 排除搜尋圖片意圖（找圖片 / 搜尋圖片），避免誤觸 vision gap
    final isImageSearchIntent =
        (normalized.contains('找') && normalized.contains('圖片')) ||
        (normalized.contains('搜尋') && normalized.contains('圖片')) ||
        (normalized.contains('搜索') && normalized.contains('圖片'));
    if (mentionsImage && asksRecognition && !isImageSearchIntent) {
      final hasImage = imagePath != null && imagePath.trim().isNotEmpty;
      if (hasImage) return null;
      return CapabilityGapCardData(
        title: '開通圖片識別能力',
        request: text,
        missing: '圖片理解服務 / 圖片識別橋',
        status: hasImage ? '已收到圖片，但尚未接上 Vision 能力。' : '需要先上傳圖片，並確認已有支援圖片理解的服務。',
        route: '/golden-keys?returnTo=/chat',
        routeLabel: '設定圖片理解能力',
        iconName: 'image_search',
        steps: const [
          '到服務設定頁確認主腦或圖片服務支援 Vision / 圖像理解。',
          '測試通過後回到這段對話，我會接續分析同一張圖。',
        ],
        providerHints: const ['OpenAI Vision', '支援圖像理解的雲端模型'],
      );
    }

    if (containsAny(normalized, [
      '音樂',
      '作曲',
      '配樂',
      '歌曲',
      '生成音',
      'music',
      'song',
      'soundtrack',
    ])) {
      return CapabilityGapCardData(
        title: '開通音樂生成能力',
        request: text,
        missing: '音樂生成服務 / SemiDAO 音樂生成功能模組',
        status: '我已理解這是一個音樂生成任務，但目前還沒有可執行的音樂生成服務。',
        route: '/golden-keys?returnTo=/chat',
        routeLabel: '設定生成能力',
        iconName: 'music_note',
        steps: const [
          '到 API Key 申請頁面新增支援音樂生成的服務。',
          '貼上官方 API Key 並完成連線測試。',
          '回到這段對話，我會自動接續原本的音樂任務。',
        ],
        providerHints: const ['音樂生成服務官方入口', 'SemiDAO 音樂生成額外功能'],
      );
    }

    if (containsAny(normalized, ['影片', '短片', '分鏡', 'video', 'movie', '動畫影片'])) {
      return CapabilityGapCardData(
        title: '開通影片生成能力',
        request: text,
        missing: '影片生成服務 / SemiDAO 影片生成功能模組',
        status: '我已理解這是一個影片生成任務，但目前還沒有可執行的影片生成服務。',
        route: '/golden-keys?returnTo=/chat',
        routeLabel: '設定影片能力',
        iconName: 'movie_creation',
        steps: const [
          '到 API Key 申請頁面新增支援影片生成的服務。',
          '確認素材權利、預估成本與 API Key。',
          '回到這段對話，我會接續原本的影片任務。',
        ],
        providerHints: const ['影片生成服務官方入口', 'SemiDAO 影片生成額外功能'],
      );
    }

    if (containsAny(normalized, [
      '桌面',
      '檔案',
      '資料夾',
      '本機',
      '整理資料',
      '下載資料',
      '找檔案',
      'desktop',
      'folder',
      'local file',
    ])) {
      return CapabilityGapCardData(
        title: '開通桌面檔案操作能力',
        request: text,
        missing: 'Bridge Desktop 檔案讀取器 / 本機權限',
        status: '目前聊天只能理解需求，還不能直接讀取或整理你的本機檔案。',
        route: desktopBridgeSetupRoute(),
        routeLabel: '檢查桌面能力',
        iconName: 'desktop_windows',
        steps: [
          '確認桌面 APP 已啟動，且 Bridge Desktop 已連上。',
          '開通檔案讀取與整理權限，讓夥伴能看見指定資料夾。',
          '回到原任務，我會接續幫你分類、命名、搬移或整理資料。',
        ],
        providerHints: const ['Bridge Desktop', '本機資料夾授權'],
      );
    }

    if (containsAny(normalized, [
      '新服務',
      '新的 ai',
      '新的ai',
      '建立橋',
      '自訂能力',
      '接 api',
      '接api',
      'plugin',
      'adapter',
    ])) {
      return CapabilityGapCardData(
        title: '建立自訂能力橋',
        request: text,
        missing: '能力描述 / 服務 / 執行橋接線',
        status: '這看起來是一個新功能需求。我會先把它登錄成能力卡，未來再接 API。',
        route: '/golden-keys?returnTo=/chat',
        routeLabel: '建立能力橋',
        iconName: 'add_link',
        steps: const [
          '在服務設定頁填入服務名稱、用途與觸發情境。',
          '把官方 API、登入方式或功能模組需求補進能力卡。',
          '保存後同步寫入第二大腦 Bridges 房間，未來任務命中時會主動提醒。',
        ],
        providerHints: const ['官方服務頁', 'SemiDAO 社群額外功能', '自訂執行橋'],
      );
    }

    // [以利沙 2026-06-26] 修復一：定時提醒偵測
    // [以利沙 P1 修復十輪 2026-06-27] 補入待辦、清單、習慣相關詞庫
    if (containsAny(normalized, [
      '提醒',
      '通知',
      '排程',
      '每天',
      '定時',
      '鬧鐘',
      '記得提醒',
      '幫我提醒',
      'remind',
      'reminder',
      'schedule',
      'notify',
      'alarm',
      '待辦',
      '任務清單',
      '清單',
      '記事',
      '備忘',
      '定期',
      '習慣',
      '打卡',
    ])) {
      return CapabilityGapCardData(
        title: '開通定時提醒能力',
        request: text,
        missing: '定時提醒功能 / 排程通知服務',
        status: '我已理解這是一個定時提醒任務，但目前還沒有可執行的定時提醒功能。',
        route: '/golden-keys?returnTo=/chat',
        routeLabel: '設定提醒能力',
        iconName: 'alarm',
        steps: const [
          '設定好 AI 服務，就可以幫你定時提醒。', // [以利沙 修復七 2026-06-27] 去術語
          '設定提醒時間、頻率與通知方式。',
          '回到這段對話，我會自動接續原本的提醒任務。',
        ],
        providerHints: const [
          '手機內建提醒 App',
          'Google Calendar',
          'LINE Notify',
        ], // [以利沙 修復七 2026-06-27]
      );
    }

    // [以利沙 P1 修復十輪 2026-06-27] browse gap 偵測（網頁搜尋能力）
    if (containsAny(normalized, [
      '搜尋',
      '查一下',
      '查詢',
      '找資料',
      '最新',
      '新聞',
      '查看',
      'search',
      'browse',
      'news',
      'web',
      '上網',
    ])) {
      return CapabilityGapCardData(
        title: '開通網頁搜尋能力',
        request: text,
        missing: '網頁搜尋服務 / Browse Bridge',
        status: '我已理解你想搜尋網路上的最新資訊，但目前還沒有接上網頁搜尋服務。',
        route: '/golden-keys?returnTo=/chat',
        routeLabel: '設定搜尋能力',
        iconName: 'travel_explore',
        steps: const [
          '到服務設定頁開通網頁搜尋（Browse）能力。',
          '確認 API Key 已填入並通過連線測試。',
          '回到這段對話，我會接續幫你搜尋最新資訊。',
        ],
        providerHints: const [
          'Brave Search API',
          'Serper API',
          'Tavily Search',
        ],
      );
    }

    // [以利沙 修復四 2026-06-27] 本地模型偵測
    if (containsAny(normalized, [
      '本地模型', '本地部署', '離線模型', 'ollama', 'llama', '自己的模型', '不用雲端', '不需要網路',
      '本地 ai 模型', '自架模型', '私有模型', '不上傳', '隱私模型', // [以利沙 修復八 2026-06-27] 詞庫補充
      '不上雲',
      '不要雲端',
      '資料不外傳',
      '在我電腦上跑',
      '本地執行',
      '離線執行', // [以利沙 修復八 第二輪 2026-06-27]
    ])) {
      return CapabilityGapCardData(
        title: '開通本地 AI 模型能力',
        request: text,
        missing: '本地模型執行環境 / Ollama 或相容執行環境',
        status: '我已理解你想使用本地 AI 模型，但目前還沒有設定本地模型執行環境。',
        route: '/golden-keys?returnTo=/chat', // [以利沙 P1 修復 2026-06-27] 改為直達金鑰匙
        routeLabel: '前往金鑰匙設定', // [以利沙 P1 修復 2026-06-27]
        iconName: 'memory',
        steps: const [
          '點擊下方「前往金鑰匙設定」進入金鑰匙中心。',
          '在「本地 AI 模型」區塊點「偵測本地模型」，系統自動連接 Ollama。',
          '偵測成功後點「啟用為本地主腦」，完成切換。',
        ],
        providerHints: const ['Ollama 官方入口', 'LM Studio', 'llama.cpp'],
      );
    }

    return null;
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  BridgeAction? inferBridgeActionFromRequest(String text, {String? imagePath}) {
    return inferChatBridgeActionForRequest(text, imagePath: imagePath);
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  SecondBrainTrace projectSemanticRouteTrace(
    ProjectSemanticRoute route, {
    required SecondBrainTrace fallback,
  }) {
    final routeTarget =
        route.projectDoor?.title ??
        route.contextTransfer?.targetProjectTitle ??
        route.digitalAssetInvocation?.assetTitle ??
        route.label;
    final sourceIntent =
        route.projectDoor?.sourceIntent ??
        route.contextTransfer?.ideaSummary ??
        route.digitalAssetInvocation?.request ??
        route.label;
    final sourcePath = switch (route.kind) {
      ProjectSemanticRouteKind.createProjectDoor =>
        route.projectDoor?.forkFromConversation == true
            ? 'local://project-route/fork'
            : 'local://project-route/new-door',
      ProjectSemanticRouteKind.transferContext =>
        'local://project-route/context-transfer/${route.contextTransfer?.targetProjectId ?? ''}',
      ProjectSemanticRouteKind.invokeDigitalAsset =>
        'brain://digital-assets/${route.digitalAssetInvocation?.assetId ?? ''}',
      ProjectSemanticRouteKind.none => 'local://project-route/none',
    };
    return SecondBrainTrace(
      agentName: _activeCompanion?.name ?? fallback.agentName,
      recalledMemories: [
        SecondBrainMemoryTrace(
          content: '專案門語意路由：${route.label} → $routeTarget',
          room: SecondBrainRoom.projects.label,
          sourceLabel: '專案門語意路由',
          sourcePath: sourcePath,
          reason: '這輪不是普通問答，系統先判斷要開新專案、移植上下文，或引用可共享資產。',
          retrievalSignals: [
            ...route.signals,
            '信心 ${(route.confidence * 100).round()}%',
          ],
          freshnessLabel: '剛判斷',
          sourcePreview: sourceIntent,
          tags: const ['專案門', '語意路由', '水流'],
          trustScore: (route.confidence * 100).round().clamp(50, 92).toInt(),
        ),
        ...fallback.recalledMemories,
      ],
      newInsights: [
        SecondBrainNewInsightTrace(
          content: '本輪已走「${route.label}」水流，後續回覆應掛回「$routeTarget」。',
          room: SecondBrainRoom.projects.label,
          tags: const ['專案路由', '主線水流'],
        ),
        ...fallback.newInsights,
      ],
      outputs: fallback.outputs,
      associations: [
        '使用者意圖 ↔ ${route.label} ↔ $routeTarget',
        ...route.signals.map((signal) => '路由線索 ↔ ${route.label} ↔ $signal'),
        ...fallback.associations,
      ],
    );
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  SecondBrainTrace bridgeSecondBrainTrace(
    BridgeAction action, {
    BridgeActionResult? result,
    CapabilityGapCardData? capabilityGap,
  }) {
    final label = bridgeInsightLabel(action) ?? action.type.displayLabel;
    final query =
        result?.metadata?['query']?.toString().trim().isNotEmpty == true
        ? result!.metadata!['query'].toString().trim()
        : action.prompt.trim();
    final status = result?.status;
    final bridgeRoom = action.type == BridgeActionType.browse
        ? 'Bridges'
        : 'Capabilities';
    final sourceMaps = searchSourceMaps(result?.metadata);
    final recalled = <SecondBrainMemoryTrace>[
      SecondBrainMemoryTrace(
        content: action.type == BridgeActionType.browse
            ? '正在用新聞與網頁搜尋橋查詢「$query」，完成後會整理摘要、來源與時間敏感提醒。'
            : '正在使用「$label」處理這輪任務。',
        room: bridgeRoom,
        sourceLabel: label,
        sourcePath: 'local://bridge/${action.type.legacyType}',
        reason: capabilityGap != null
            ? '這輪命中能力缺口，因此先保留任務並引導到服務設定頁。'
            : result == null
            ? '這輪需求已命中正式橋能力，思維儀表先追蹤橋樑執行狀態。'
            : '橋樑已回傳結果，思維儀表同步整理查詢、來源與下一步。',
        retrievalSignals: [
          '使用者請求：$query',
          '使用橋：$label',
          if (status != null) '執行狀態：${bridgeStatusLabel(status)}',
          if (capabilityGap != null) '缺口：${capabilityGap.missing}',
        ],
        freshnessLabel: result == null ? '執行中' : '剛完成',
        sourcePreview: result?.message.trim().isNotEmpty == true
            ? result!.message.trim()
            : query,
        tags: const ['正式橋', '能力路由', '思維儀表'],
        trustScore: result?.status == BridgeActionStatus.completed ? 82 : 64,
      ),
      ...sourceMaps.take(3).map((source) {
        final title = source['title']?.toString().trim().isNotEmpty == true
            ? source['title'].toString().trim()
            : source['url']?.toString().trim().isNotEmpty == true
            ? source['url'].toString().trim()
            : '搜尋來源';
        final url = source['url']?.toString().trim();
        return SecondBrainMemoryTrace(
          content: title,
          room: 'Bridges',
          sourceLabel: title,
          sourcePath: url == null || url.isEmpty ? null : url,
          reason: '這是搜尋橋回傳的可追查來源，使用者可以用它驗證回答。',
          retrievalSignals: [
            '查詢：$query',
            if (url != null && url.isNotEmpty) '可點證據：$url',
          ],
          freshnessLabel: '剛查到',
          sourcePreview: url ?? title,
          tags: const ['來源', '證據', '新聞與網頁搜尋橋'],
          trustScore: 76,
        );
      }),
    ];
    final outputs = <SecondBrainOutputTrace>[
      if (result != null)
        SecondBrainOutputTrace(
          title: action.type == BridgeActionType.browse
              ? '搜尋摘要與來源卡'
              : action.type == BridgeActionType.document
              ? documentAssetTraceTitle(result)
              : action.type == BridgeActionType.desktopFiles
              ? desktopFilesAssetTraceTitle(result)
              : '橋樑執行結果',
          kind: action.type.displayLabel,
          path: action.type == BridgeActionType.document
              ? documentAssetPrimaryPath(result)
              : action.type == BridgeActionType.desktopFiles
              ? desktopFilesPrimaryPath(result)
              : sourceMaps.isNotEmpty
              ? sourceMaps.first['url']?.toString()
              : 'local://conversation/latest-bridge-result',
        ),
    ];
    return SecondBrainTrace(
      agentName: _activeCompanion?.name,
      recalledMemories: recalled,
      newInsights: [
        if (action.type == BridgeActionType.browse && result != null)
          SecondBrainNewInsightTrace(
            content: '搜尋結果已寫入「橋樑房間」，之後可以回查查詢字、來源、擷取時間與摘要。',
            room: SecondBrainRoom.bridges.label,
            tags: const ['搜尋結果', '可點證據', '新聞與網頁搜尋橋'],
          ),
        if (action.type == BridgeActionType.vision && result != null)
          SecondBrainNewInsightTrace(
            content: '圖片辨識結果已寫入「檔案房間」，之後可以回查圖片來源、辨識目的與畫面線索。',
            room: SecondBrainRoom.files.label,
            tags: const ['圖片辨識', '圖片線索', 'Vision橋'],
          ),
        if (action.type == BridgeActionType.document && result != null)
          SecondBrainNewInsightTrace(
            content:
                '文件資產已產出，將依目前情境掛到「${documentAssetRoomForCurrentContext().zhLabel}」，之後可從第二大腦調閱或接續改寫。',
            room: documentAssetRoomForCurrentContext().label,
            tags: const ['文件資產', '資料地圖', '文件產出橋'],
          ),
        if (action.type == BridgeActionType.desktopFiles && result != null)
          SecondBrainNewInsightTrace(
            content: '桌面整理結果已寫入「檔案房間」，之後可以回查掃描位置、分類建議與整理紀錄。',
            room: SecondBrainRoom.files.label,
            tags: const ['桌面整理', '檔案地圖', '桌面整理橋'],
          ),
      ],
      outputs: outputs,
      associations: [
        '使用者需求 ↔ $label ↔ ${result == null ? '等待執行' : '結果整理'}',
        if (sourceMaps.isNotEmpty) '搜尋橋 ↔ ${sourceMaps.length} 個來源 ↔ 可點證據',
        if (action.type == BridgeActionType.browse && result != null)
          '新聞與網頁搜尋橋 ↔ 橋樑房間 ↔ ${query.isEmpty ? '搜尋結果' : query}',
        if (action.type == BridgeActionType.vision && result != null)
          '圖片辨識橋 ↔ 檔案房間 ↔ ${result.metadata?['imageSource']?.toString() ?? '已附加圖片'}',
        if (action.type == BridgeActionType.document && result != null)
          '文件產出橋 ↔ 第二大腦索引 ↔ ${_activeProjectDoor?.title ?? '檔案房間'}',
        if (action.type == BridgeActionType.desktopFiles && result != null)
          '桌面整理橋 ↔ 檔案房間 ↔ ${desktopFilesPrimaryPath(result) ?? '授權資料夾'}',
        if (capabilityGap != null) '能力缺口 ↔ 服務設定頁 ↔ 回到原任務',
      ],
    );
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  String compactIndexExcerpt(String value, {int maxChars = 240}) {
    final clean = value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[#*_`]+'), '')
        .trim();
    if (clean.length <= maxChars) return clean;
    return '${clean.substring(0, maxChars).trim()}...';
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  List<String> stringListFromMetadata(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  List<String> desktopSampleNames(Object? samples) {
    if (samples is! List) return const <String>[];
    return samples
        .whereType<Map>()
        .map((item) => item['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  bool isReuseDrivenDocumentTitle(String title) {
    final normalized = title.toLowerCase();
    return normalized.contains('資產重用') ||
        normalized.contains('digital asset') ||
        normalized.contains('reuse');
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  bool isReuseDrivenDesktopPrompt(String? prompt) {
    final normalized = prompt?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return false;
    return normalized.contains('依照「') ||
        normalized.contains('已引用') ||
        normalized.contains('資產重用') ||
        normalized.contains('整理規則') ||
        normalized.contains('digital asset') ||
        normalized.contains('reuse');
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  String desktopCategorySummary(Map<String, dynamic> metadata) {
    final summary = metadata['categorySummary']?.toString().trim();
    if (summary != null && summary.isNotEmpty) return summary;
    final counts = metadata['categoryCounts'];
    if (counts is! Map || counts.isEmpty) return '尚無分類';
    final entries =
        counts.entries
            .map((entry) => MapEntry(entry.key.toString(), entry.value))
            .where((entry) => entry.value is num)
            .toList()
          ..sort(
            (a, b) =>
                (b.value as num).toInt().compareTo((a.value as num).toInt()),
          );
    return entries
        .take(4)
        .map((entry) => '${entry.key} ${(entry.value as num).toInt()}')
        .join('、');
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  List<String> creativeTagsForAssetText(
    String value, {
    required String fallback,
  }) {
    final text = value.toLowerCase();
    final tags = <String>{};
    if (text.contains('直播') || text.contains('銷售') || text.contains('帶貨')) {
      tags.add('內容商務');
    }
    if (text.contains('角色') || text.contains('agent')) {
      tags.add('角色創作');
    }
    if (text.contains('企劃') || text.contains('報告') || text.contains('文件')) {
      tags.add('知識整理');
    }
    if (text.contains('流程') || text.contains('規則') || text.contains('整理')) {
      tags.add('流程創意');
    }
    if (tags.isEmpty) tags.add(fallback);
    return tags.toList(growable: false);
  }

  // ── 含 setState 轉 notifyListeners 的方法 ──────────

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  void clearSpeechInsertionState() {
    _speechReplaceStart = null;
    _speechReplaceEnd = null;
    _speechContinuationPrefix = null;
    _speechLastRecognizedWords = '';
    _applyingSpeechResult = false;
    notifyListeners();
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<void> appendLocalSystemMessage(
    String content, {
    Map<String, dynamic>? metadata,
  }) async {
    final conv = _currentConversation;
    if (conv == null) return;
    final message = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      content: content,
      timestamp: DateTime.now(),
      // [以利沙 P0 修復十四輪 2026-06-27] 記錄發言者 companion.id
      speakerId: _activeCompanion?.id ?? 'native-agent', // [指紋定律 2026-10-16 Blue] 原生 Agent 也有指紋，永不匿名
      metadata: metadata,
    );
    final updated = conv.copyWith(
      messages: [...conv.messages, message],
      updatedAt: DateTime.now(),
    );
    await ConversationStore.save(updated);
    final all = await ConversationStore.getAll();
    _currentConversation = updated;
    _conversations = all;
    // [教練 Agent 2026-07-20] 渲染感應器——通知 stdout 讓外部觀察者知道原生 Agent回覆了
    final preview = content.length > 120
        ? '${content.substring(0, 120)}...'
        : content;
    debugPrint('[AgentReply] $preview');
    final reg = CanvasMcpRegistry.instance;
    reg.setLastAgentReply(content);
    reg.onAgentReply?.call(content);
    notifyListeners();
    onScrollToBottom?.call();
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<void> appendImageIntentMessage(String imagePath) async {
    final conv = _currentConversation;
    if (conv == null) return;
    final trimmedPath = imagePath.trim();
    final message = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      content: '我收到你的圖片了，你想讓我怎麼處理？\n\n你可以選擇下方其中一個動作，或直接告訴我你想做什麼。',
      timestamp: DateTime.now(),
      bridgeActions: [
        BridgeAction(
          type: BridgeActionType.vision,
          prompt: '請描述這張圖片的內容，並指出畫面中重要的細節。',
          referenceImagePaths: [trimmedPath],
        ),
        BridgeAction(
          type: BridgeActionType.vision,
          prompt: '請辨識這張圖片中可以讀到的文字，整理成清楚段落；不確定的字請標註。',
          referenceImagePaths: [trimmedPath],
        ),
        BridgeAction(
          type: BridgeActionType.vision,
          prompt: '請檢查這張圖片是否有畫面、介面、排版、錯誤訊息或可疑問題，並列出優先處理事項。',
          referenceImagePaths: [trimmedPath],
        ),
        BridgeAction(
          type: BridgeActionType.vision,
          prompt: '請把這張圖片作為接下來任務的視覺參考，先摘要可用線索，等我下一步指令。',
          referenceImagePaths: [trimmedPath],
        ),
      ],
    );
    final updated = conv.copyWith(
      messages: [...conv.messages, message],
      updatedAt: DateTime.now(),
    );
    await ConversationStore.save(updated);
    final all = await ConversationStore.getAll();
    _currentConversation = updated;
    _conversations = all;
    notifyListeners();
    onScrollToBottom?.call();
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  // [教練 Agent 2026-07-20] vagueAesthetic 時用更精準的反問
  Future<void> appendIntentClarificationMessage(IntentSpine intentSpine) async {
    final options = intentSpine.clarificationOptions
        .where((option) => option.trim().isNotEmpty)
        .take(3)
        .toList();
    final optionText = options.isEmpty
        ? ''
        : '\n\n你可以直接回我其中一種：\n${options.asMap().entries.map((entry) => '${entry.key + 1}. ${entry.value}').join('\n')}';

    // 感覺/風格描述——反問具體方向
    final isVagueAesthetic = intentSpine.signals.any(
      (s) => s.contains('感覺/風格描述'),
    );
    if (isVagueAesthetic) {
      await appendLocalSystemMessage(
        '你說的感覺我大致理解，但我想先釐清再動手，避免改錯方向。\n\n'
        '具體來說：\n'
        '- 是哪個區域讓你有這個感覺？（整體畫面、節點、工具列、對話框？）\n'
        '- 你說的感覺是指什麼？（間距太近、色調太重、圓角太尖、字級太小？）\n'
        '- 有沒有你喜歡的 App 或畫面可以參考？\n\n'
        '你隨意講，不用很精確，我會幫你翻譯成具體的改動。',
      );
      return;
    }

    await appendLocalSystemMessage(
      '我先確認一下你的意思，避免我直接走錯下一步。\n\n'
      '我理解到的是：${intentSpine.normalizedGoal}\n'
      '你想先把方向聊清楚，還是要我開始執行？'
      '$optionText',
    );
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<void> appendCapabilityGapCard(
    CapabilityGapCardData card, {
    BridgeAction? bridgeAction,
  }) async {
    if (!shouldShowCapabilityGapForRequest(card.request)) {
      return appendLocalSystemMessage(
        '我先不急著開通能力，避免偏離你的原始意圖。\n\n'
        '我理解你這一輪比較像是在釐清、討論或詢問原則；如果你要我真的開始執行或開通能力，可以直接說「照這個開始」或「幫我開通這個能力」。',
      );
    }
    final task = await _pendingBridgeTaskStore.save(
      PendingBridgeTask.create(
        title: card.title,
        request: card.request,
        missing: card.missing,
        route: card.route,
        routeLabel: card.routeLabel,
        iconName: card.iconName,
        conversationId: _currentConversation?.id,
        bridgeAction: bridgeAction,
      ),
    );
    _pendingBridgeTask = task;
    notifyListeners();
    final cardWithTask = card.copyWith(pendingTaskId: task.id);
    return appendLocalSystemMessage(
      '$capabilityCardPrefix${jsonEncode(cardWithTask.toJson())}',
    );
  }

  // [以利沙 Capability Advisor 2026-06-25]
  // 從 CapabilityGapCardData 推斷 gapType
  String _detectGapTypeFromCard(CapabilityGapCardData card) {
    final value =
        '${card.title} ${card.missing} ${card.iconName} ${card.routeLabel}'
            .toLowerCase();
    if (value.contains('音樂') || value.contains('music'))
      return 'generate_music';
    if (value.contains('影片') || value.contains('video'))
      return 'generate_video';
    if (value.contains('搜尋') ||
        value.contains('網頁') ||
        value.contains('browse'))
      return 'browse';
    if (value.contains('圖片識別') || value.contains('vision')) return 'vision';
    if (value.contains('桌面') || value.contains('desktop'))
      return 'desktop_files';
    if (value.contains('圖片') || value.contains('image'))
      return 'generate_image';
    if (value.contains('文件') || value.contains('document')) return 'document';
    // [以利沙 2026-06-26] 修復一：定時提醒 gapType 辨識
    if (value.contains('提醒') || value.contains('alarm') || value.contains('排程'))
      return 'schedule_reminder';
    // [以利沙 修復九 2026-06-27] 本地模型 gapType 辨識
    if (value.contains('本地') ||
        value.contains('ollama') ||
        value.contains('llama') ||
        value.contains('自架') ||
        value.contains('私有') ||
        value.contains('隱私') ||
        value.contains('雲端') ||
        value.contains('離線')) {
      // [以利沙 修復八 第二輪 2026-06-27] 補充邊緣詞
      return 'local_model';
    }
    // [以利沙 修復二十輪 2026-06-27] 補 local_model title 精確比對，防止 card.title 已含關鍵字但文字轉小寫後漏掉（如 Ollama 大寫）
    if (card.title.contains('本地') ||
        card.title.contains('Ollama') ||
        card.missing.contains('local_model')) {
      return 'local_model';
    }
    return 'unknown';
  }

  // [以利沙 Capability Advisor 2026-06-25]
  // 啟動能力顧問流程：優先嘗試 advisor，失敗則 fallback 到靜態卡。
  Future<void> handleCapabilityGapWithAdvisor({
    required BridgeActionResult result,
    BridgeAction? bridgeAction,
  }) async {
    final gapType = result.metadata?['type']?.toString() ?? '';
    final userRequest =
        result.metadata?['prompt']?.toString() ??
        bridgeAction?.prompt ??
        result.message;

    try {
      final card = await _capabilityAdvisor.startFlow(
        gapType: gapType,
        userRequest: userRequest,
        originalAction: bridgeAction,
      );
      _activeAdvisorCard = card;

      // 執行 browse 先決檢查
      final afterCheck = await _capabilityAdvisor.checkBrowsePrerequisite(card);
      _activeAdvisorCard = afterCheck;
      await appendLocalSystemMessage(
        '$capabilityAdvisorCardPrefix${jsonEncode(afterCheck.toJson())}',
      );

      // 如果 browse 已開通且不需要子流程，自動繼續搜尋
      if (afterCheck.currentStep == CapabilityAdvisorStep.searching) {
        await _advanceAdvisorFlow(afterCheck);
      }
    } catch (e) {
      // fallback 到靜態卡
      developer.log(
        'CapabilityAdvisor failed, falling back to static card: $e',
      );
      await appendCapabilityGapCard(
        capabilityGapFromBridgeResult(result, bridgeAction: bridgeAction),
        bridgeAction: bridgeAction,
      );
    }
  }

  // [以利沙 Capability Advisor 2026-06-25]
  // 推進顧問流程（自動執行 searching → analyzing）
  Future<void> _advanceAdvisorFlow(CapabilityAdvisorCardData card) async {
    try {
      var current = card;
      // [以利沙 P1 修復 2026-06-27] browseGapDetected 靜默卡死防護
      // searchSolutions 內部有 browseGapDetected → searching 的切換邏輯
      // [以利沙 修復七 2026-06-27] 改為 else if，防止 browseGapDetected 執行後再次進入 searching 分支
      if (current.currentStep == CapabilityAdvisorStep.browseGapDetected) {
        final afterSearch = await _capabilityAdvisor.searchSolutions(current);
        current = afterSearch;
        _activeAdvisorCard = current;
        await _updateAdvisorCard(current);
      } else if (current.currentStep == CapabilityAdvisorStep.searching) {
        final afterSearch = await _capabilityAdvisor.searchSolutions(current);
        current = afterSearch;
        _activeAdvisorCard = current;
        await _updateAdvisorCard(current);
      }
      if (current.currentStep == CapabilityAdvisorStep.analyzing) {
        final afterAnalyze = await _capabilityAdvisor.analyzeCandidates(
          current,
        );
        current = afterAnalyze;
        _activeAdvisorCard = current;
        await _updateAdvisorCard(current);
      }
    } catch (e) {
      developer.log('CapabilityAdvisor flow advance failed: $e');
    }
  }

  // [以利沙 Capability Advisor 2026-06-25]
  Future<void> _updateAdvisorCard(CapabilityAdvisorCardData card) async {
    await appendLocalSystemMessage(
      '$capabilityAdvisorCardPrefix${jsonEncode(card.toJson())}',
    );
  }

  // [以利沙 Capability Advisor 2026-06-25]
  // UI 回呼：確認意圖
  Future<void> advisorConfirmIntent() async {
    final card = _activeAdvisorCard;
    if (card == null) return;
    final intent = card.inferredIntent ?? card.userRequest;
    final updated = _capabilityAdvisor.confirmIntent(card, intent);
    _activeAdvisorCard = updated;
    await _updateAdvisorCard(updated);
  }

  // [以利沙 P1 修復 2026-06-26]
  // UI 回呼：browseGapDetected → 啟動子流程（searching → analyzing → presentingComparison）
  // 不呼叫 confirmIntent（此時 candidates 為空），直接推進搜尋子流程。
  Future<void> advisorStartBrowseSubFlow() async {
    final card = _activeAdvisorCard;
    if (card == null) return;
    if (card.currentStep != CapabilityAdvisorStep.browseGapDetected) return;
    await _advanceAdvisorFlow(card);
  }

  // [以利沙 Capability Advisor 2026-06-25]
  // UI 回呼：修正意圖
  Future<void> advisorCorrectIntent(String correctedIntent) async {
    final card = _activeAdvisorCard;
    if (card == null) return;
    final updated = _capabilityAdvisor.confirmIntent(card, correctedIntent);
    _activeAdvisorCard = updated;
    await _updateAdvisorCard(updated);
    if (updated.currentStep == CapabilityAdvisorStep.analyzing) {
      await _advanceAdvisorFlow(updated);
    }
  }

  // [以利沙 Capability Advisor 2026-06-25]
  // UI 回呼：選擇方案
  Future<void> advisorSelectSolution(String candidateId) async {
    final card = _activeAdvisorCard;
    if (card == null) return;
    final updated = await _capabilityAdvisor.selectSolution(card, candidateId);
    _activeAdvisorCard = updated;
    await _updateAdvisorCard(updated);
  }

  // [以利沙 Capability Advisor 2026-06-25]
  // UI 回呼：驗證能力
  Future<void> advisorVerify() async {
    final card = _activeAdvisorCard;
    if (card == null) return;
    var verifying = card.copyWith(
      currentStep: CapabilityAdvisorStep.verifying,
      statusMessage: '正在驗證能力是否已開通...',
    );
    _activeAdvisorCard = verifying;
    await _updateAdvisorCard(verifying);

    final verified = await _capabilityAdvisor.verifyCapability(verifying);
    _activeAdvisorCard = verified;
    await _updateAdvisorCard(verified);

    // 如果驗證通過且恢復了原始 gap，繼續搜尋原始 gap 的方案
    if (verified.currentStep == CapabilityAdvisorStep.searching) {
      await _advanceAdvisorFlow(verified);
    }
  }

  // [以利沙 Capability Advisor 2026-06-25]
  // UI 回呼：重試
  Future<void> advisorRetry() async {
    final card = _activeAdvisorCard;
    if (card == null) return;
    // 回到失敗前的步驟重新嘗試
    if (card.suspendedGap != null) {
      // browse 子流程失敗，從 searching 重試
      final retry = card.copyWith(
        currentStep: CapabilityAdvisorStep.searching,
        statusMessage: '正在重新搜尋...',
      );
      _activeAdvisorCard = retry;
      await _updateAdvisorCard(retry);
      await _advanceAdvisorFlow(retry);
    } else {
      // 一般失敗，從 checkingBrowse 重試
      final retry = card.copyWith(
        currentStep: CapabilityAdvisorStep.checkingBrowse,
        statusMessage: '正在重新確認...',
      );
      _activeAdvisorCard = retry;
      await _updateAdvisorCard(retry);
      final afterCheck = await _capabilityAdvisor.checkBrowsePrerequisite(
        retry,
      );
      _activeAdvisorCard = afterCheck;
      await _updateAdvisorCard(afterCheck);
      if (afterCheck.currentStep == CapabilityAdvisorStep.searching) {
        await _advanceAdvisorFlow(afterCheck);
      }
    }
  }

  // [以利沙 Capability Advisor 2026-06-25]
  // UI 回呼：取消
  Future<void> advisorCancel() async {
    final card = _activeAdvisorCard;
    if (card == null) return;
    // [教練 Agent 2026-06-29] 取消後直接清除卡片，不留下「已取消」訊息
    // 同時移除對話中所有能力顧問卡片訊息
    _activeAdvisorCard = null;
    final conv = _currentConversation;
    if (conv != null) {
      final cleanedMessages = conv.messages
          .where((m) => !m.content.startsWith(capabilityAdvisorCardPrefix))
          .toList();
      final updated = conv.copyWith(
        messages: cleanedMessages,
        updatedAt: DateTime.now(),
      );
      await ConversationStore.save(updated);
      _currentConversation = updated;
      final all = await ConversationStore.getAll();
      _conversations = all;
    }
    notifyListeners();
  }

  // [以利沙 Capability Advisor 2026-06-25]
  // UI 回呼：回到主線任務
  // [以利沙 P1 修復 2026-06-27] 回傳 bool：true = 重新執行任務，false = 填回輸入框
  Future<bool> advisorReturnToTask() async {
    final card = _activeAdvisorCard;
    if (card == null) return false;
    final returning = card.copyWith(
      currentStep: CapabilityAdvisorStep.returningToTask,
      statusMessage: '正在回到主線任務...',
    );
    _activeAdvisorCard = returning;
    await _updateAdvisorCard(returning);
    // 重新執行原始 action
    if (card.originalAction != null) {
      await executeBridgeAction(card.originalAction!);
    }
    // [以利沙 P0 修復十九輪 2026-06-27] 收緊條件：只有真正選定方案或完成驗證才寫入記憶
    if (card.selectedCandidateId != null ||
        card.currentStep == CapabilityAdvisorStep.verified) {
      final selectedCandidate = card.candidates
          .cast<SolutionCandidate?>()
          .firstWhere(
            (c) => c?.id == card.selectedCandidateId,
            orElse: () => null,
          );
      final advisorEntryId =
          'advisor-${card.gapType}-${DateTime.now().millisecondsSinceEpoch}';
      await _secondBrainFileIndexStore.upsert(
        SecondBrainFileEntry(
          id: advisorEntryId,
          title: '已開通能力：${card.gapLabel}',
          path: 'local://capabilities/${card.gapType}',
          room: SecondBrainRoom.bridges,
          summary:
              '透過顧問引導開通「${card.gapLabel}」，選用方案：${selectedCandidate?.name ?? '已設定'}',
          tags: ['能力設定', '已開通', card.gapType],
          keywords: [
            card.gapLabel,
            if (card.userRequest.isNotEmpty) card.userRequest,
          ],
          indexedAt: DateTime.now(),
          trustScore: 80,
          agentId: _activeCompanion?.id, // [以利沙 P0 修復十七輪 2026-06-27]
        ),
      );
    }
    _activeAdvisorCard = null;
    // [以利沙 P1 任務延續 2026-06-26]
    // 若無 originalAction，將原始 userRequest 填入輸入框，讓使用者一鍵重送
    if (card.originalAction == null && card.userRequest.isNotEmpty) {
      onSetMessageText?.call(card.userRequest);
    }
    // [以利沙 P2 修復 2026-06-27] advisor 完成後下一次 detectCapabilityGap 跳過，防止無限循環
    _skipNextCapabilityGapDetect = true;
    // [以利沙 P0 修復十四輪 2026-06-27] advisor 完成後聚焦輸入框
    // [以利沙 P1 修復十五輪 2026-06-27] 改為 addPostFrameCallback，避免 setState 期間觸發
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onFocusMessageInput?.call();
    });
    // [以利沙 P0 修復十一輪 2026-06-27] 持久化能力已開通，防止次輪再觸發 gap 卡
    if (card.gapType.isNotEmpty) {
      _unlockedCapabilities.add(card.gapType);
      unawaited(StorageService.setCapabilityUnlocked(card.gapType));
      // [以利沙 修復二十輪 2026-06-27] 同步儲存整合清單
      unawaited(_saveUnlockedCapabilities());
    }
    return card.originalAction != null; // true = 已重新執行任務
  }

  // [以利沙 Capability Advisor 2026-06-25]
  CapabilityAdvisorCardData? tryParseCapabilityAdvisorCard(String content) {
    if (!content.startsWith(capabilityAdvisorCardPrefix)) return null;
    try {
      final jsonText = content.substring(capabilityAdvisorCardPrefix.length);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return null;
      return CapabilityAdvisorCardData.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<void> appendDigitalAssetInvocationCard(
    DigitalAssetInvocationCardData card,
  ) async {
    return appendLocalSystemMessage(
      '$digitalAssetInvocationCardPrefix${jsonEncode(card.toJson())}',
    );
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<void> appendManagedFolderRulePickerCard(
    String request, {
    String? targetFolderPath,
    String? targetFolderLabel,
  }) async {
    await loadManagedFolderRules();
    final userRules = _managedFolderRules
        .where((rule) => !rule.isBuiltIn)
        .toList();
    final candidateRules = userRules.isNotEmpty
        ? userRules
        : _managedFolderRules;
    final rules = candidateRules
        .take(8)
        .map(
          (rule) => ManagedFolderRulePickerItem(
            id: rule.id,
            ruleTitle: rule.ruleTitle,
            folderLabel: rule.folderLabel,
            folderPath: rule.folderPath,
            rulePath: rule.rulePath,
            modeLabel: rule.modeLabel,
            categorySummary: rule.categorySummary,
            builtIn: rule.isBuiltIn,
          ),
        )
        .toList();
    return appendLocalSystemMessage(
      '$managedFolderRulePickerCardPrefix${jsonEncode(ManagedFolderRulePickerCardData(request: request, rules: rules, targetFolderPath: targetFolderPath, targetFolderLabel: targetFolderLabel).toJson())}',
    );
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<void> appendBridgeConfirmationMessage(
    BridgeAction action,
    BridgeActionResult result,
  ) async {
    if (_currentConversation == null) return;
    final confirmationMsg = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      content: '這次橋樑動作需要你確認。',
      timestamp: DateTime.now(),
      speakerId: _activeCompanion?.id ?? 'native-agent', // [指紋定律 2026-10-16 Blue] 原生 Agent 也有指紋，永不匿名（原以利沙 P0）
      bridgeActions: [
        action.copyWith(
          requiresConfirmation: true,
          runStatus: BridgeActionRunStatus.pending,
          statusMessage: result.message,
        ),
      ],
    );

    final updated = _currentConversation!.copyWith(
      messages: [..._currentConversation!.messages, confirmationMsg],
      updatedAt: DateTime.now(),
    );

    await ConversationStore.save(updated);
    final all = await ConversationStore.getAll();
    _currentConversation = updated;
    _conversations = all;
    notifyListeners();
    onScrollToBottom?.call();
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<void> updateBridgeActionStatus(
    String messageId,
    int actionIndex,
    BridgeActionRunStatus status, {
    String? statusMessage,
    bool? requiresConfirmation,
  }) async {
    final conv = _currentConversation;
    if (conv == null) return;

    final messages = [...conv.messages];
    final messagePosition = messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (messagePosition < 0) return;

    final targetMessage = messages[messagePosition];
    final actions = targetMessage.bridgeActions;
    if (actions == null || actionIndex < 0 || actionIndex >= actions.length) {
      return;
    }

    final updatedActions = [...actions];
    updatedActions[actionIndex] = updatedActions[actionIndex].copyWith(
      runStatus: status,
      statusMessage: statusMessage,
      requiresConfirmation: requiresConfirmation,
    );
    messages[messagePosition] = targetMessage.copyWith(
      bridgeActions: updatedActions,
    );

    final updated = conv.copyWith(
      messages: messages,
      updatedAt: DateTime.now(),
    );

    await ConversationStore.save(updated);
    final all = await ConversationStore.getAll();
    _currentConversation = updated;
    _conversations = all;
    notifyListeners();
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<void> appendBridgeResultMessage(BridgeActionResult result) async {
    if (_currentConversation == null) return;
    final evidence = _bridgeActionEvidence.describe(result);
    final resultMsg = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      content: evidence == null
          ? result.message
          : '${result.message}\n\n$evidence',
      timestamp: DateTime.now(),
      speakerId: _activeCompanion?.id ?? 'native-agent', // [指紋定律 2026-10-16 Blue] 原生 Agent 也有指紋，永不匿名（原以利沙 P0）
      imagePath: result.metadata?['kind'] == 'document'
          ? null
          : result.mediaUrl,
      attachmentKind: result.metadata?['kind'] == 'document'
          ? 'document'
          : null,
      attachmentPath: result.metadata?['kind'] == 'document'
          ? result.mediaUrl
          : null,
      metadata: result.metadata,
    );

    final archivedAssets = [
      await indexDocumentAssetResult(result, resultMsg),
      await indexDesktopFilesResult(result, resultMsg),
      await indexBrowseResult(result, resultMsg),
      await indexVisionResult(result, resultMsg),
    ].whereType<DigitalAsset>().toList();
    final assetMessages = archivedAssets.map((asset) {
      final card = digitalAssetResultCardFromAsset(
        asset,
        sourceProjectTitle: _activeProjectDoor?.title ?? asset.sourceLabel,
      );
      return Message(
        id: 'asset-result-${DateTime.now().microsecondsSinceEpoch}-${asset.id}',
        role: 'assistant',
        content: '$digitalAssetResultCardPrefix${jsonEncode(card.toJson())}',
        timestamp: DateTime.now(),
        metadata: {
          'kind': 'digital_asset_result',
          'assetId': asset.id,
          'sourceBridgeResultId': resultMsg.id,
        },
      );
    }).toList();

    final updated = _currentConversation!.copyWith(
      messages: [
        ..._currentConversation!.messages,
        resultMsg,
        ...assetMessages,
      ],
      updatedAt: DateTime.now(),
    );

    await ConversationStore.save(updated);
    final all = await ConversationStore.getAll();
    _currentConversation = updated;
    _conversations = all;
    notifyListeners();
    onScrollToBottom?.call();
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<DigitalAsset?> indexBrowseResult(
    BridgeActionResult result,
    Message resultMsg,
  ) async {
    if (result.metadata?['kind'] != 'web_search') return null;

    final metadata = result.metadata ?? const <String, dynamic>{};
    final query = metadata['query']?.toString().trim();
    if (query == null || query.isEmpty) return null;

    final searchQueries = stringListFromMetadata(metadata['searchQueries']);
    final sourceMaps = searchSourceMaps(metadata);
    final primarySource = sourceMaps.isNotEmpty ? sourceMaps.first : null;
    final primaryTitle =
        primarySource?['title']?.toString().trim().isNotEmpty == true
        ? primarySource!['title'].toString().trim()
        : null;
    final primaryUrl =
        primarySource?['url']?.toString().trim().isNotEmpty == true
        ? primarySource!['url'].toString().trim()
        : 'local://bridge/web-search/${_currentConversation!.id}/${resultMsg.id}';
    final fetchedAt = metadata['fetchedAt']?.toString().trim();
    final sourceCount = metadata['sourceCount']?.toString().trim();
    final sourceHealth = metadata['sourceHealth']?.toString().trim();
    final projectTitle = _activeProjectDoor?.title;
    final projectFlow = _activeProjectDoor?.currentFlow;
    final now = DateTime.now();

    await _secondBrainFileIndexStore.upsert(
      SecondBrainFileEntry(
        id: 'web-search-${_currentConversation!.id}-${resultMsg.id}',
        title: '搜尋結果：$query',
        path: primaryUrl,
        room: SecondBrainRoom.bridges,
        summary: '新聞與網頁搜尋橋查詢「$query」，已整理摘要、時間線索與可點來源。',
        contentDigest: [
          '來源橋：新聞與網頁搜尋橋',
          '原始查詢：$query',
          if (searchQueries.isNotEmpty)
            '實際搜尋：${searchQueries.take(3).join(' / ')}',
          if (fetchedAt != null && fetchedAt.isNotEmpty) '擷取時間：$fetchedAt',
          if (sourceCount != null && sourceCount.isNotEmpty)
            '來源數量：$sourceCount',
          if (sourceHealth != null && sourceHealth.isNotEmpty)
            '來源狀態：$sourceHealth',
          if (primaryTitle != null) '主要來源：$primaryTitle',
          '主要連結：$primaryUrl',
          if (projectTitle != null) '關聯專案門：$projectTitle',
          if (projectFlow != null && projectFlow.isNotEmpty)
            '目前水流：$projectFlow',
        ].join('。'),
        contentExcerpt: compactIndexExcerpt(result.message),
        tags: [
          '搜尋結果',
          '新聞與網頁搜尋橋',
          '可點證據',
          if (metadata['timeSensitive'] == true) '時間敏感',
          if (projectTitle != null) '專案門',
          ?projectTitle,
          ?projectFlow,
        ],
        keywords: [
          query,
          ...searchQueries.take(5),
          '搜尋',
          '新聞',
          '網頁',
          '來源',
          ?primaryTitle,
          ?projectTitle,
          ?projectFlow,
        ],
        indexedAt: now,
        trustScore: sourceMaps.isEmpty ? 66 : 82,
        agentId: _activeCompanion?.id, // [以利沙 P0 修復十八輪 2026-06-27]
      ),
    );

    return _digitalAssetRegistry.registerAsset(
      id: 'digital-web-search-${_currentConversation!.id}-${resultMsg.id}',
      title: '搜尋知識包：$query',
      kind: DigitalAssetKind.knowledgePack,
      summary: '新聞與網頁搜尋橋整理出的可重用知識包，包含查詢、摘要、時間線索與可點來源。',
      sourceProjectDoorId: _activeProjectDoor?.id ?? '',
      sourceConversationId: _currentConversation!.id,
      sourceLabel: projectTitle ?? '搜尋任務',
      capabilities: const ['新聞與網頁搜尋橋'],
      reusableScenes: const ['資料查證', '報告引用', '任務背景資料', '跨專案研究'],
      tags: [
        '數位資產',
        '搜尋結果',
        '知識包',
        '新聞與網頁搜尋橋',
        if (metadata['timeSensitive'] == true) '時間敏感',
      ],
      purposeTags: const ['資料查證', '知識整理', 'Agent 可調用'],
      locationTags: [
        '主要連結：$primaryUrl',
        if (projectTitle != null) '來源專案：$projectTitle',
        SecondBrainRoom.bridges.zhLabel,
      ],
      propertyTags: [
        '搜尋摘要',
        '可點證據',
        if (sourceCount != null && sourceCount.isNotEmpty) '來源數：$sourceCount',
      ],
      creativeTags: creativeTagsForAssetText(
        '$query $projectTitle $projectFlow',
        fallback: '知識整理',
      ),
    );
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<DigitalAsset?> indexVisionResult(
    BridgeActionResult result,
    Message resultMsg,
  ) async {
    if (result.metadata?['kind'] != 'vision') return null;

    final metadata = result.metadata ?? const <String, dynamic>{};
    final prompt = metadata['prompt']?.toString().trim();
    final imageSource = metadata['imageSource']?.toString().trim();
    final imageCount = metadata['imageCount']?.toString().trim();
    final model = metadata['model']?.toString().trim();
    final provider = metadata['provider']?.toString().trim();
    final projectTitle = _activeProjectDoor?.title;
    final projectFlow = _activeProjectDoor?.currentFlow;
    final path = imageSource != null && imageSource.isNotEmpty
        ? imageSource
        : 'local://bridge/vision/${_currentConversation!.id}/${resultMsg.id}';
    final title = prompt == null || prompt.isEmpty
        ? '圖片辨識結果'
        : '圖片辨識：${compactIndexExcerpt(prompt, maxChars: 28)}';
    final now = DateTime.now();

    await _secondBrainFileIndexStore.upsert(
      SecondBrainFileEntry(
        id: 'vision-${_currentConversation!.id}-${resultMsg.id}',
        title: title,
        path: path,
        room: SecondBrainRoom.files,
        summary: '圖片辨識橋已分析圖片，整理可見線索、可讀文字與問題清單。',
        contentDigest: [
          '來源橋：圖片辨識橋',
          if (prompt != null && prompt.isNotEmpty) '辨識目的：$prompt',
          if (imageSource != null && imageSource.isNotEmpty)
            '圖片來源：$imageSource',
          if (imageCount != null && imageCount.isNotEmpty) '圖片數量：$imageCount',
          if (model != null && model.isNotEmpty) '使用模型：$model',
          if (provider != null && provider.isNotEmpty) 'Provider：$provider',
          if (projectTitle != null) '關聯專案門：$projectTitle',
          if (projectFlow != null && projectFlow.isNotEmpty)
            '目前水流：$projectFlow',
        ].join('。'),
        contentExcerpt: compactIndexExcerpt(result.message),
        tags: [
          '圖片辨識',
          '圖片線索',
          'Vision橋',
          if (projectTitle != null) '專案門',
          ?projectTitle,
          ?projectFlow,
        ],
        keywords: [
          if (prompt != null && prompt.isNotEmpty) prompt,
          '圖片',
          '辨識',
          'vision',
          ?imageSource,
          ?projectTitle,
          ?projectFlow,
        ],
        indexedAt: now,
        trustScore: 80,
        agentId: _activeCompanion?.id, // [以利沙 P0 修復十八輪 2026-06-27]
      ),
    );

    return _digitalAssetRegistry.registerAsset(
      id: 'digital-vision-${_currentConversation!.id}-${resultMsg.id}',
      title: title,
      kind: DigitalAssetKind.knowledgePack,
      summary: '圖片辨識橋產生的可重用知識包，包含辨識目的、畫面線索與可讀文字。',
      sourceProjectDoorId: _activeProjectDoor?.id ?? '',
      sourceConversationId: _currentConversation!.id,
      sourceLabel: projectTitle ?? '圖片辨識任務',
      capabilities: const ['圖片辨識橋'],
      reusableScenes: const ['畫面分析', '文字擷取', '問題檢查', '視覺參考'],
      tags: ['數位資產', '圖片辨識', '知識包', 'Vision橋', if (projectTitle != null) '專案門'],
      purposeTags: const ['畫面分析', '知識整理', 'Agent 可調用'],
      locationTags: [
        '圖片位置：$path',
        if (projectTitle != null) '來源專案：$projectTitle',
        SecondBrainRoom.files.zhLabel,
      ],
      propertyTags: [
        '圖片辨識',
        '可讀文字',
        if (imageCount != null && imageCount.isNotEmpty) '圖片數：$imageCount',
      ],
      creativeTags: const ['知識整理'],
    );
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<DigitalAsset?> indexDocumentAssetResult(
    BridgeActionResult result,
    Message resultMsg,
  ) async {
    if (result.metadata?['kind'] != 'document') return null;

    final metadata = result.metadata ?? const <String, dynamic>{};
    final title = metadata['title']?.toString().trim();
    final documentTitle = title == null || title.isEmpty ? '橋樑文件' : title;
    final documentType = metadata['documentType']?.toString().trim();
    final format = metadata['format']?.toString().trim();
    final generationMode = metadata['generationMode']?.toString().trim();
    final provider = metadata['provider']?.toString().trim();
    final path = documentAssetPrimaryPath(result);
    if (path == null || path.isEmpty) return null;
    final reuseDriven = isReuseDrivenDocumentTitle(documentTitle);

    final exportPaths = metadata['exportPaths'];
    final exportSummary = exportPaths is Map
        ? exportPaths.entries
              .map((entry) => '${entry.key}：${entry.value}')
              .join(' / ')
        : path;
    final projectTitle = _activeProjectDoor?.title;
    final projectFlow = _activeProjectDoor?.currentFlow;
    final room = documentAssetRoomForCurrentContext();
    final now = DateTime.now();

    await _secondBrainFileIndexStore.upsert(
      SecondBrainFileEntry(
        id: 'document-asset-${_currentConversation!.id}-${resultMsg.id}',
        title: documentTitle,
        path: path,
        room: room,
        summary:
            '文件資產：$documentTitle。${projectTitle == null ? '目前未掛專案門，先存入檔案房間。' : '掛在專案門「$projectTitle」。'}',
        contentDigest: [
          '來源橋：文件產出橋',
          if (documentType != null && documentType.isNotEmpty)
            '文件類型：$documentType',
          if (format != null && format.isNotEmpty) '格式：$format',
          if (generationMode != null && generationMode.isNotEmpty)
            '產出方式：$generationMode',
          if (provider != null && provider.isNotEmpty) 'Provider：$provider',
          if (projectFlow != null && projectFlow.isNotEmpty)
            '目前水流：$projectFlow',
          if (reuseDriven) '資產重用：由已引用數位資產推進產生',
          '實際位置：$path',
        ].join('。'),
        contentExcerpt: exportSummary,
        tags: [
          '文件資產',
          '文件產出橋',
          if (documentType != null && documentType.isNotEmpty) documentType,
          if (format != null && format.isNotEmpty) ...format.split('/'),
          if (reuseDriven) '資產重用成果',
          if (reuseDriven) '不重新造輪子',
          if (projectTitle != null) '專案門',
          ?projectTitle,
          ?projectFlow,
        ],
        keywords: [
          documentTitle,
          '文件',
          '報告',
          '輸出',
          ?projectTitle,
          ?projectFlow,
          if (documentType != null && documentType.isNotEmpty) documentType,
        ],
        indexedAt: now,
        trustScore: 78,
        agentId: _activeCompanion?.id, // [以利沙 P0 修復十八輪 2026-06-27]
      ),
    );

    return _digitalAssetRegistry.registerAsset(
      id: 'digital-document-asset-${_currentConversation!.id}-${resultMsg.id}',
      title: documentTitle,
      kind: DigitalAssetKind.documentAsset,
      summary: reuseDriven
          ? '資產重用閉環產生的文件資產，代表既有數位資產已推進成目前專案的下一步成果。'
          : '文件產出橋產生的文件資產，可被後續專案、Agent 或任務收尾流程引用。',
      sourceProjectDoorId: _activeProjectDoor?.id ?? '',
      sourceConversationId: _currentConversation!.id,
      sourceLabel: projectTitle ?? '聊天任務',
      capabilities: const ['文件產出橋'],
      reusableScenes: const ['任務收尾歸檔', '報告再加工', '跨專案文件引用'],
      tags: [
        '數位資產',
        '文件資產',
        '文件產出橋',
        if (reuseDriven) '資產重用成果',
        if (reuseDriven) '不重新造輪子',
        if (documentType != null && documentType.isNotEmpty) documentType,
        if (format != null && format.isNotEmpty) ...format.split('/'),
      ],
      purposeTags: [
        '任務收尾',
        '文件再利用',
        'Agent 可調用',
        if (reuseDriven) '資產重用',
        if (reuseDriven) '下一步任務草案',
      ],
      locationTags: [
        '檔案位置：$path',
        if (projectTitle != null) '來源專案：$projectTitle',
        if (room.zhLabel.isNotEmpty) room.zhLabel,
      ],
      propertyTags: [
        '文件',
        if (reuseDriven) '資產重用成果',
        if (documentType != null && documentType.isNotEmpty) documentType,
        if (format != null && format.isNotEmpty) ...format.split('/'),
      ],
      creativeTags: creativeTagsForAssetText(
        '$documentTitle $documentType $projectTitle $projectFlow',
        fallback: '知識整理',
      ),
    );
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<DigitalAsset?> indexDesktopFilesResult(
    BridgeActionResult result,
    Message resultMsg,
  ) async {
    if (result.metadata?['kind'] != 'desktop_file_plan') return null;

    final metadata = result.metadata ?? const <String, dynamic>{};
    final rootPath = metadata['rootPath']?.toString().trim();
    if (rootPath == null || rootPath.isEmpty) return null;

    final executed = metadata['executed'] == true;
    final recordPath = metadata['recordPath']?.toString().trim();
    final path = executed && recordPath != null && recordPath.isNotEmpty
        ? recordPath
        : rootPath;
    final rootName = basename(rootPath) ?? '授權資料夾';
    final title = executed ? '桌面整理紀錄：$rootName' : '桌面整理計畫：$rootName';
    final categorySummary = desktopCategorySummary(metadata);
    final suggestions = stringListFromMetadata(metadata['suggestions']);
    final samples = desktopSampleNames(metadata['samples']);
    final prompt = metadata['prompt']?.toString().trim();
    final projectTitle = _activeProjectDoor?.title;
    final now = DateTime.now();
    final reuseDriven = isReuseDrivenDesktopPrompt(prompt);

    await _secondBrainFileIndexStore.upsert(
      SecondBrainFileEntry(
        id: 'desktop-files-${_currentConversation!.id}-${resultMsg.id}',
        title: title,
        path: path,
        room: SecondBrainRoom.files,
        summary: executed
            ? '桌面整理橋已完成整理紀錄：$rootName。'
            : '桌面整理橋已只讀掃描：$rootName，等待使用者確認是否執行。',
        contentDigest: [
          '來源橋：桌面整理橋',
          if (prompt != null && prompt.isNotEmpty) '原始任務：$prompt',
          '掃描位置：$rootPath',
          '檔案數：${metadata['fileCount'] ?? 0}',
          '資料夾數：${metadata['folderCount'] ?? 0}',
          '主要分類：$categorySummary',
          if (executed) ...[
            '已建立資料夾：${metadata['createdFolderCount'] ?? 0}',
            '已移動檔案：${metadata['movedCount'] ?? 0}',
            if (recordPath != null && recordPath.isNotEmpty) '整理紀錄：$recordPath',
          ] else ...[
            '預計建立資料夾：${metadata['plannedFolderCount'] ?? 0}',
            '預計移動檔案：${metadata['plannedMoveCount'] ?? 0}',
            '保留原處：${metadata['skippedCount'] ?? 0}',
            '安全狀態：只讀掃描，尚未搬移、改名或刪除',
          ],
          if (projectTitle != null) '關聯專案門：$projectTitle',
          if (reuseDriven) '資產重用：依既有整理規則或數位資產推進',
        ].join('。'),
        contentExcerpt: [
          if (suggestions.isNotEmpty) '建議：${suggestions.take(3).join(' / ')}',
          if (samples.isNotEmpty) '樣本：${samples.take(8).join('、')}',
        ].join('\n'),
        tags: [
          '桌面整理',
          '檔案地圖',
          '桌面整理橋',
          executed ? '整理紀錄' : '整理計畫',
          if (reuseDriven) '資產重用成果',
          if (reuseDriven) '套用既有規則',
          rootName,
          if (categorySummary != '尚無分類') ...categorySummary.split('、'),
          ?projectTitle,
        ],
        keywords: [
          rootName,
          rootPath,
          '桌面',
          '整理',
          '檔案',
          '分類',
          '掃描',
          if (executed) '整理紀錄' else '整理計畫',
          ?projectTitle,
          ...samples.take(12),
        ],
        indexedAt: now,
        trustScore: executed ? 84 : 74,
        agentId: _activeCompanion?.id, // [以利沙 P0 修復十八輪 2026-06-27]
      ),
    );

    return _digitalAssetRegistry.registerAsset(
      id: 'digital-desktop-files-${_currentConversation!.id}-${resultMsg.id}',
      title: title,
      kind: executed
          ? DigitalAssetKind.documentAsset
          : DigitalAssetKind.workflowEngine,
      summary: executed
          ? '桌面整理橋產生的整理紀錄，可供之後追蹤與回顧。'
          : reuseDriven
          ? '由既有數位資產或整理規則推進出的桌面整理計畫，可作為這次任務的安全核對基礎。'
          : '桌面整理橋產生的整理計畫，可作為受管資料夾規則或後續整理流程的基礎。',
      sourceProjectDoorId: _activeProjectDoor?.id ?? '',
      sourceConversationId: _currentConversation!.id,
      sourceLabel: projectTitle ?? rootName,
      capabilities: const ['桌面整理橋', '文件產出橋'],
      reusableScenes: const ['資料夾整理', '受管資料夾規則', '任務收尾歸檔'],
      tags: [
        '數位資產',
        '桌面整理',
        '檔案地圖',
        executed ? '整理紀錄' : '整理計畫',
        if (reuseDriven) '資產重用成果',
        if (reuseDriven) '套用既有規則',
        rootName,
      ],
      purposeTags: [
        '檔案整理',
        '任務收尾',
        'Agent 可調用',
        if (reuseDriven) '資產重用',
        if (reuseDriven) '受管資料夾規則候選',
      ],
      locationTags: [
        '掃描位置：$rootPath',
        if (projectTitle != null) '來源專案：$projectTitle',
      ],
      propertyTags: [
        executed ? '整理紀錄' : '整理計畫',
        if (reuseDriven) '套用既有規則',
        '資料夾規則候選',
        ...(categorySummary == '尚無分類'
            ? const <String>[]
            : categorySummary.split('、')),
      ],
      creativeTags: const ['流程創意', '資料整理'],
    );
  }

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<void> autoExecuteAssistantBridgeActions(Message message) async {
    final actions = message.bridgeActions;
    if (actions == null || actions.isEmpty) return;
    for (var index = 0; index < actions.length; index++) {
      final action = actions[index];
      if (!shouldAutoExecuteAssistantAction(action)) continue;
      await executeBridgeAction(
        action,
        messageId: message.id,
        actionIndex: index,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════
  // [教練 Agent 2026-07-30 Phase 4] 自訂調用原則——自然語言觸發
  // ════════════════════════════════════════════════════════════════

  /// 嘗試將使用者訊息解析為調用原則請求
  ///
  /// 流程（設計文件 §C）：
  /// 1. PolicyGenerator.shouldTrigger 已通過（呼叫前檢查）
  /// 2. 取得當前 provider/model
  /// 3. 生成草稿；如果太模糊回 null → 回覆引導訊息
  /// 4. 顯示確認 dialog
  /// 5. 使用者確認 → createPolicy + activatePolicy（dialog 內部完成）
  /// 6. 回覆「已生效」
  Future<bool> _tryHandlePolicyRequest(String text) async {
    final provider = await StorageService.getProvider() ?? 'openai';

    final generator = PolicyGenerator.instance;
    final draft = await generator.generateDraft(text, provider, null);

    if (draft == null) {
      // 解析失敗——列出現況，反問使用者
      await _replyPolicyParseFailed(provider, null);
      onClearMessageInput?.call();
      return true;
    }

    // 顯示確認 dialog（如果 callback 未注入，退回文字訊息）
    if (onShowPolicyConfirmDialog != null) {
      final confirmed = await onShowPolicyConfirmDialog!(draft);
      if (confirmed == true) {
        await _replyPolicyActivated(draft);
      }
    } else {
      // fallback：没有 dialog callback，用文字訊息告知
      await _replyPolicyDraftWithoutDialog(draft);
    }

    onClearMessageInput?.call();
    return true;
  }

  /// 回覆「已生效」訊息
  Future<void> _replyPolicyActivated(CustomRoutingPolicy draft) async {
    if (_currentConversation == null) await createNewConversation();
    final msg = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      content: '✅ ${draft.name} 已生效，內建調用模式已自動棄用。',
      timestamp: DateTime.now(),
      speakerId: _activeCompanion?.id ?? 'native-agent', // [指紋定律 2026-10-16 Blue] 原生 Agent 也有指紋，永不匿名
    );
    final conv = _currentConversation!;
    _currentConversation = conv.copyWith(
      messages: [...conv.messages, msg],
      updatedAt: DateTime.now(),
    );
    await ConversationStore.save(_currentConversation!);
    notifyListeners();
    onScrollToBottom?.call();
  }

  /// 解析失敗——列出現況，反問使用者想改的方向
  Future<void> _replyPolicyParseFailed(String provider, String? model) async {
    final store = ProviderProfileStore.instance;
    await store.initialize();
    final profile = await store.getProfile(provider, model ?? provider);

    if (_currentConversation == null) await createNewConversation();
    final modelLabel = model ?? '預設';
    final msg = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      content:
          '我找到 $provider / $modelLabel 目前的設定：\n'
          '• 能力分層：${profile.tierName}\n'
          '• 建議最大輪數：${profile.suggestedMaxTurns ?? '不設限'}\n'
          '• 建議任務拆分：${profile.suggestedTaskChunkSize ?? '不設限'}\n'
          '• 無限制模式：${profile.unlimited ? '是' : '否'}\n\n'
          '你想調整哪個方向？例如：\n'
          '- 「太慢了，少跑幾輪」\n'
          '- 「回答太長了」\n'
          '- 「要有創意一點」',
      timestamp: DateTime.now(),
      speakerId: _activeCompanion?.id ?? 'native-agent', // [指紋定律 2026-10-16 Blue] 原生 Agent 也有指紋，永不匿名
    );
    final conv = _currentConversation!;
    _currentConversation = conv.copyWith(
      messages: [...conv.messages, msg],
      updatedAt: DateTime.now(),
    );
    await ConversationStore.save(_currentConversation!);
    notifyListeners();
    onScrollToBottom?.call();
  }

  /// 無 dialog callback 時的文字回覆
  Future<void> _replyPolicyDraftWithoutDialog(CustomRoutingPolicy draft) async {
    if (_currentConversation == null) await createNewConversation();
    final msg = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      content:
          '我幫你準備了一個自訂原則：\n'
          '📋 ${draft.name}\n'
          '📝 ${draft.description}\n\n'
          '（確認對話框未注入，請到設定頁面手動啟用）',
      timestamp: DateTime.now(),
      speakerId: _activeCompanion?.id ?? 'native-agent', // [指紋定律 2026-10-16 Blue] 原生 Agent 也有指紋，永不匿名
    );
    final conv = _currentConversation!;
    _currentConversation = conv.copyWith(
      messages: [...conv.messages, msg],
      updatedAt: DateTime.now(),
    );
    await ConversationStore.save(_currentConversation!);
    notifyListeners();
    onScrollToBottom?.call();
  }

  // ════════════════════════════════════════════════════════════════
  // sendMessage — 主方法（原 _sendMessage）
  // [以利沙 Sprint 8 Step 6 2026-06-24]
  // ════════════════════════════════════════════════════════════════

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  // [教練 Agent 2026-07-19] 直接發送訊息——不經過 UI text field
  // 用於 MCP /send_user_message 端點，讓外部能像使用者一樣觸發 sendMessage 流程
  /// [時間感 L2 2026-09-12] 相遇時間軸注入——「我陪了你 N 天」骨架。
  /// 歸人：優先 ambient companionId，退而當前 active companion。
  /// fail-open：失敗返回 null（絕不讓時間感拖垮對話）。
  Future<String?> _buildTimelineSection() async {
    try {
      final cid = CausalLedger.instance.ambientCompanionId ??
          _activeCompanion?.id;
      if (cid == null || cid.isEmpty) return null;
      final t = await TimeSenseService.instance.timelineFor(cid);
      if (t == null) return null;
      // [時間感 L4] 相遇軸＋臨近紀念日（時間從 bug 變 feature——樂樂提案 L4）
      final base = TimeSenseService.buildTimelineSection(t);
      final milestones = TimeSenseService.buildMilestoneSection(t);
      if (base == null) return milestones;
      return milestones == null ? base : '$base$milestones';
    } catch (e) {
      debugPrint('[TimeSense] timeline 注入失敗（不擋對話）: $e');
      return null;
    }
  }

  Future<void> sendDirectMessage(
    String text, {
    String? imagePath,
    // [教練 Agent 2026-08-19] 機器產生訊息（節點結果/畫布事件）不得走意圖分類與橋樑動作執行
    // 根因：節點輸出含「波西米亞」等字眼被語意分類成 generateMusic → needsProvider modal
    bool isSystemEvent = false,
  }) async {
    // 暫時設定 onSetMessageText 的文字，讓 sendMessage 能讀到
    final originalSetter = onSetMessageText;
    final originalGetter = onGetMessageText;
    onSetMessageText = (_) {};
    onGetMessageText = () => text;
    _systemEventMessage = isSystemEvent;
    _lastMessageWasSystemEvent = isSystemEvent; // [教練 Agent 2026-08-20] 付費閘門用
    try {
      await sendMessage(imagePath: imagePath);
    } finally {
      _systemEventMessage = false;
      onSetMessageText = originalSetter;
      onGetMessageText = originalGetter;
    }
  }

  /// [教練 Agent 2026-08-19] 系統事件訊息標記——節點結果等機器訊息不觸發橋樑動作
  bool _systemEventMessage = false;

  /// [隊友訊息流 C2 2026-09-08] 派工——白話指令 → 背景任務。
  ///
  /// 設計稿 §6：dispatch 不走 sendMessage 主鏈（不觸發意圖分類/橋樑動作），
  /// 派工訊息以 user 訊息入列（記錄），AgentLoop 由 TaskDispatcher 編排——
  /// 完成後交付訊息以系統事件通道注入（injectAssistantMessage + kind:task）
  /// 不會喚醒另一輪 Loop（$33 防迴路鐵則）。
  ///
  /// 回傳 dispatch 後立即（不等任務完成）。
  Future<void> dispatchTask(String instruction, {String? title}) async {
    if (_currentConversation == null) {
      await createNewConversation();
    }
    final conv = _currentConversation;
    if (conv == null) return;

    final companionId =
        CompanionStore().activeCompanion?.id ?? 'default-companion';

    // [刀 2 D2.2] Ambient companionId——派工期間所有付費動作記帳自動歸屬
    // 這個夥伴（PaidActionGate.checkAndReserve 讀取；任務結束 try/finally 清）。
    PaidActionGate.instance.ambientCompanionId = companionId;

    // 派工指令入列（user 訊息，真實記錄使用者說了什麼）
    final msg = Message(
      id: 'task-dispatch-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      content: instruction,
      timestamp: DateTime.now(),
      metadata: {'kind': 'task-dispatch'},
    );
    _currentConversation = conv.copyWith(
      messages: [...conv.messages, msg],
      updatedAt: DateTime.now(),
    );
    await ConversationStore.save(_currentConversation!);
    notifyListeners();
    onScrollToBottom?.call();

    // 引擎注入（冪等——只注一次）
    _ensureTaskAgentRunner();

    // 背景派出——不 await 完成（dispatch 內部自己 transition + 廣播）
    unawaited(
      TaskDispatcher.instance.dispatch(
        conversationId: conv.id,
        companionId: companionId,
        instruction: instruction,
        title: title,
      ),
    );
  }

  /// [TRIO M3.5 2026-09-22] 舉行團隊會議——真 runner 接線版。
  ///
  /// 流程：注入引擎 runner → hold()（四段議程 sequenced）→
  /// 決議派工 → 會議紀錄注入對話。
  /// 白話觸發：使用者說「開個會」「開會」「團隊會議」等（chat_screen 偵測）。
  /// 不切活躍夥伴——臨時 setActive 讓工具身份正確，會後還原。
  Future<void> holdTrioMeeting({String? agendaExtra}) async {
    if (_currentConversation == null) {
      await createNewConversation();
    }
    final conv = _currentConversation;
    if (conv == null) return;

    await _ensureAgentLoopInitialized();
    if (_agentLoop == null) {
      await injectAssistantMessage(
          '会议室：Agent Loop 未初始化，無法開會（$_agentLoopInitError）');
      return;
    }

    _ensureTaskAgentRunner(); // 冪等——會議派工出口共用 dispatcher runner

    final engine = TrioMeetingEngine.instance;

    // 真發言 runner：以指定夥伴身份跑一輪 loop
    engine.speakerRunner ??= (agentId, meetingPrompt) async {
      // 臨時切身份（不動前台——工具的 intel_share 等要知道自己是誰）
      final prev = CompanionStore().activeCompanionId;
      try {
        await CompanionStore().setActive(agentId);
        final companion = CompanionStore().getById(agentId);
        final systemPrompt = await _buildTaskSystemPrompt(TaskSession.create(
          conversationId: conv.id,
          companionId: agentId,
          workCanvasId: '',
          title: '會議發言',
          instruction: meetingPrompt,
        ));
        final personaPrompt = companion?.systemPrompt;
        final merged = personaPrompt == null
            ? systemPrompt
            : '$systemPrompt\n\n## 會議模式\n你是與會者，發言簡短誠實。'
                '回覆會直接成為會議紀錄的一段，不要寒暄。\n$meetingPrompt';
        final result = await _agentLoop!.run(
          systemPrompt: merged,
          userMessage: meetingPrompt,
          maxTurns: 6, // 會議發言短輪——不需要 30 輪
        );
        return result.reply;
      } finally {
        if (prev != null) await CompanionStore().setActive(prev);
      }
    };

    // 主持人 runner：直接用主模型跑（不用工具——只彙整）
    engine.moderatorRunner ??= (transcript) async {
      final result = await _agentLoop!.run(
        systemPrompt: '你是會議主持人。只輸出會議紀錄與 RESOLUTION| 決議行，'
            '格式嚴格：\nRESOLUTION|執行者id或ME|決議內容\n沒有決議寫 NONE',
        userMessage: transcript,
        maxTurns: 1, // 主持人不呼叫工具
      );
      return result.reply;
    };

    // 開會通知（會議進行中看得見）
    await injectAssistantMessage(
        '📋 團隊會議開始——與會者輪流回報 → 紅隊挑戰 → 情報處置 → 決議。'
        '會議結束後紀錄會注入這裡。');

    try {
      final meeting = await engine.hold(
        conversationId: conv.id,
        agendaExtra: agendaExtra,
      );

      // 決議派工（會議的出口）
      await engine.dispatchResolutions(meeting, conversationId: conv.id);

      // 會議紀錄入情報池（會議本身也是情報——下次會議可回顧）
      await IntelPool.instance.share(
        fromAgent: 'moderator',
        kind: IntelKind.external,
        content: '會議 ${meeting.id} 完成：'
            '${meeting.turns.length} 輪發言、${meeting.resolutions.length} 項決議',
        relatedSession: meeting.id,
      );

      // 會議紀錄注入對話
      final buf = StringBuffer('📋 **團隊會議紀錄**（${meeting.id}）\n\n');
      for (final t in meeting.turns) {
        final name = CompanionStore().getById(t.agentId)?.name ?? t.agentId;
        buf.writeln('**【$name · ${t.phase.label}】**');
        buf.writeln(t.content);
        buf.writeln();
      }
      if (meeting.resolutions.isNotEmpty) {
        buf.writeln('---');
        buf.writeln('**決議（已派工）：**');
        for (final r in meeting.resolutions) {
          final name = r.assigneeId == null
              ? '主持人'
              : (CompanionStore().getById(r.assigneeId!)?.name ?? r.assigneeId!);
          buf.writeln('- $name：${r.text}');
        }
      }
      await injectAssistantMessage(buf.toString(), metadata: {
        'kind': 'meeting-minutes',
        'meetingId': meeting.id,
      });
    } catch (e) {
      await injectAssistantMessage('會議失敗：$e（誠實回報，不假裝開過）');
    }
  }

  /// [隊友訊息流 C2] 把 AgentLoop 執行器接給 TaskDispatcher（冪等）。
  /// runner 內部：
  /// 1. 用主對話的 system prompt 組裝器（persona/記憶/能力全保留）
  /// 2. AgentLoop.run 帶 onProgress → 每輪工具呼叫寫入 TaskStep（直播）
  /// 3. 結束回 summary（reply）→ dispatcher 轉 delivered + 交付訊息注入
  void _ensureTaskAgentRunner() {
    final d = TaskDispatcher.instance;
    if (d.agentRunner != null) return;

    d.agentRunner = (session) async {
      await _ensureAgentLoopInitialized();
      if (_agentLoop == null) {
        throw StateError('Agent Loop 未初始化——無法執行派工（$_agentLoopInitError）');
      }

      final systemPrompt = await _buildTaskSystemPrompt(session);

      final result = await _agentLoop!.run(
        systemPrompt: systemPrompt,
        userMessage: session.instruction,
        maxTurns: AgentLoop.hardMaxTurns,
        onProgress: (turnIndex, maxTurns, toolCall, toolResult, llmOutput) {
          if (toolCall == null) return;
          final ok = toolResult?.success == true;
          _appendTaskStep(
            session,
            tool: toolCall.name,
            summary: ok
                ? (toolResult?.content ?? '完成')
                : '失敗：${toolResult?.content ?? "未知原因"}',
          );
        },
        onStage: (stage, {toolName, detail}) {
          if (stage == 'tool_start' && toolName != null) {
            _appendTaskStep(
              session,
              tool: toolName,
              summary: detail ?? '正在執行 $toolName',
            );
          }
        },
      );

      // [C4] 收集產出物——掃 turn 結果的 mediaUrl（圖）+ 工作畫布節點產出
      final deliverables = <TaskDeliverable>[
        // 工具產出媒體（生圖等）
        ...result.turns
            .where((t) =>
                t.toolResult != null &&
                t.toolResult!.success &&
                t.toolResult!.mediaUrl != null)
            .map((t) => TaskDeliverable(
                  kind: 'image',
                  ref: t.toolResult!.mediaUrl!,
                  caption: t.toolCall?.name ?? '產出',
                )),
        // 工作畫布本身也是一個 deliverable（過程可追溯）
        const TaskDeliverable(
          kind: 'canvas',
          ref: '', // ref 由 dispatcher 端補 workCanvasId
          caption: '工作畫布（過程紀錄）',
        ),
      ];

      // [刀 6 K6.6 2026-09-08] 付費生成→人點頭；純文字→直接交付。
      // Blue 拍板 A ②：awaitingReview 語意＝「付費動作產出等審」。
      final hasPaidOutput = deliverables
          .any((d) => d.kind == 'image' || d.kind == 'video' || d.kind == 'music');

      // [刀 2 D2.2] 派工結束——清 ambient companionId（記帳歸屬還原）
      PaidActionGate.instance.ambientCompanionId = null;

      if (hasPaidOutput) {
        // 付費生成：轉 awaitingReview（不注入「任務完成」——交付卡走審核三鈕）
        final latest = TaskDispatcher.instance.activeSessions
                .where((s) => s.id == session.id)
                .firstOrNull ??
            session;
        await TaskDispatcher.instance.updateSession(
            latest.copyWith(status: TaskStatus.awaitingReview));
        await injectAssistantMessage(
          '🔍 任務完成，等待確認：${session.title}\n\n有付費生成內容（圖/影/音），請審核後交付。\n\n${result.reply}',
          metadata: {'kind': 'task-delivery', 'taskId': session.id},
        );
        // [K6.4 loop] 回報事件——使用者看得到「做了什麼、在等什麼」
        TrustLoop.instance.report('🔍 付費生成完成，等待 Blue 確認：${session.title}');
        return result.reply;
      }

      // 交付訊息注入主對話（系統事件通道——不喚醒 Loop）
      if (_currentConversation?.id == session.conversationId) {
        await injectAssistantMessage(
          '✅ 任務完成：${session.title}\n\n${result.reply}',
          metadata: {'kind': 'task-delivery', 'taskId': session.id},
        );
      } else {
        // 使用者已切到別的對話——仍寫入該任務的對話（跨對話可靠交付）
        final target = await ConversationStore.getById(session.conversationId);
        if (target != null) {
          final msg = Message(
            id: 'task-delivery-${DateTime.now().microsecondsSinceEpoch}',
            role: 'assistant',
            content: '✅ 任務完成：${session.title}\n\n${result.reply}',
            timestamp: DateTime.now(),
            metadata: {'kind': 'task-delivery', 'taskId': session.id},
          );
          await ConversationStore.save(target.copyWith(
            messages: [...target.messages, msg],
            updatedAt: DateTime.now(),
          ));
        }
      }

      // [C4] deliverables 寫回 session（交付卡縮圖列資料源）
      {
        final latest = TaskDispatcher.instance.activeSessions
                .where((s) => s.id == session.id)
                .firstOrNull ??
            session;
        await TaskDispatcher.instance.updateSession(latest.copyWith(
          deliverables: [
            ...deliverables.where((d) => d.kind != 'canvas'),
            TaskDeliverable(
              kind: 'canvas',
              ref: latest.workCanvasId,
              caption: '工作畫布（過程紀錄）',
            ),
          ],
        ));
      }

      return result.reply;
    };
  }

  /// [隊友訊息流 C2] 派工專用 system prompt——沿用 AgentLoopPromptBuilder，
  /// 加派工鐵則。只帶穩定參數（persona/記憶/工具清單），不依賴單輪對話狀態。
  Future<String> _buildTaskSystemPrompt(TaskSession session) async {
    final companionPersona = _activeCompanion?.systemPrompt;
    // [T12-⑧ 2026-10-17] M2 語氣層注入派工路徑——Fable V3 斷鏈③：
    // 聊天路徑有 M2、派工沒有＝「有個性」只在一半的嘴上。
    // 與聊天路徑同款：personaForCurrentRoute 選版、fail-open 不擋派工。
    String personaWithTone = companionPersona ?? '';
    try {
      final m2 = await M2PersonaService.instance.personaForCurrentRoute();
      if (m2 != null && m2.isNotEmpty) {
        personaWithTone = personaWithTone.isEmpty
            ? m2
            : '$personaWithTone\n\n---\n$m2';
      }
    } catch (e) {
      debugPrint('[TaskPrompt] M2 注入失敗（不擋派工）: $e');
    }
    String budgetEyeText = '';
    try {
      budgetEyeText = await PaidActionGate.instance.budgetEye();
    } catch (e) {
      debugPrint('[TaskPrompt] BudgetEye 注入失敗（不擋派工）: $e');
    }

    final base = AgentLoopPromptBuilder.build(
      budgetEye: budgetEyeText,
      timelineSection: await _buildTimelineSection(),
      companionPersona: personaWithTone, // [T12-⑧] M2 語氣層
      toolRegistry: _agentToolRegistry!,
      skillsSection: SkillPromptInjector.buildSkillSection(
          userMessage: session.instruction),
      // [聊天模式 B 線 2026-10-20 Blue 拍板] 派工路徑也吃模式紀律
      // （自主長跑模式與派工場景天然重疊；自由對話不注入零回歸）
      chatModePrompt: ChatModeService.instance.currentPrompt,
    );

    return '''
$base

## 派工任務模式
你正在執行一項背景派工任務（TaskSession ${session.id}）。
- 任務：${session.instruction}
- 你的工作畫布：〔任務〕${session.title}（canvas_* 工具已自動路由到這張畫布）
- 完成後明確總結：做了什麼、產出了什麼、任何需要使用者注意的事
- 若無法完成，誠實說明原因——不假裝成功
''';
  }

  /// [隊友訊息流 C2] AgentLoop turn → TaskStep（直播視圖資料源）
  void _appendTaskStep(TaskSession session,
      {required String tool, required String summary}) {
    // dispatcher 的 session 是 memory 態最新版——直接讀
    final latest = TaskDispatcher.instance.activeSessions
        .firstWhere((s) => s.id == session.id, orElse: () => session);
    final updated = latest.copyWith(
      steps: [
        ...latest.steps,
        TaskStep(
          id: 'step-${DateTime.now().microsecondsSinceEpoch}',
          tool: tool,
          summary: summary,
          at: DateTime.now(),
        ),
      ],
    );
    // fire-and-forget——step 更新不阻塞 Loop
    unawaited(TaskDispatcher.instance.updateSession(updated));
  }

  /// [教練 Agent 2026-08-20] 記住本輪是否為系統事件——sendMessage 是 async 長鏈，
  /// _systemEventMessage 在 finally 已重置，Agent Loop 啟動點（7285）需要
  /// 讀取當時的值決定是否禁用付費工具。
  bool _lastMessageWasSystemEvent = false;

  // [教練 Agent 2026-08-03] Quick Assistant 專用送出方法
  // 自動附加 Quick Assistant context（含 App 自拍路徑）到訊息
  // 確保 Agent 知道這是除 bug 對話（已自帶完整裝備）
  Future<void> sendAssistantMessage(String text, {String? imagePath}) async {
    // 若有 context 且 context 還沒截圖 → 自動觸發截圖
    String? finalImagePath = imagePath;
    if (_quickAssistantContext != null) {
      final ctx = _quickAssistantContext!;
      if (ctx.appScreenshot != null && !ctx.isScreenshotStale) {
        // 已有截圖且未過期 → 優先使用（user 也可附加自己的截圖）
        finalImagePath = finalImagePath ?? ctx.appScreenshot!.path;
      }
    }

    // 暫時把 quick assistant context 標記到當前對話（給 system prompt builder 用）
    // 透過 _quickAssistantContext getter 自動注入
    await sendDirectMessage(text, imagePath: finalImagePath);
  }

  Future<void> sendMessage({String? imagePath}) async {
    final text = (onGetMessageText?.call() ?? '').trim();
    if (text.isEmpty && imagePath == null) {
      developer.log(
        '[ChatController] sendMessage: text is empty',
        name: 'ChatController',
      );
      return;
    }
    // [教練 Agent 2026-08-20] 使用者親自發言 → 解除付費工具禁令
    // （sendDirectMessage 走這裡時 _lastMessageWasSystemEvent 已先設定好）
    if (!_systemEventMessage) {
      _lastMessageWasSystemEvent = false;
    }

    // [教練 Agent 2026-07-22] Phase H — 插嘴功能
    // [教練 Agent 2026-08-03] 升級 Hermes 風格：插嘴時立即插入「收到～我整合思考一下」placeholder
    // Agent 正在回覆中時，把訊息注入 AgentLoop queue，不開新對話
    if (_isLoading && _agentLoop != null) {
      developer.log('[ChatController] 插嘴: $text', name: 'ChatController');
      if (_currentConversation == null) await createNewConversation();
      final conv = _currentConversation!;
      final now = DateTime.now();

      // 1. 加插嘴訊息（標 interruptions 樣式）
      final injectMsg = Message(
        id: '${now.millisecondsSinceEpoch}_inject',
        role: 'user',
        content: text,
        timestamp: now,
        metadata: {'kind': 'interrupt'},
      );

      // 2. 加 ambient placeholder「收到～我整合思考一下再回覆喔⋯⋯」
      final placeholderId = '${now.millisecondsSinceEpoch}_ambient';
      final placeholderMsg = Message(
        id: placeholderId,
        role: 'assistant',
        content: '收到～我整合思考一下再回覆喔⋯⋯',
        timestamp: now.add(const Duration(milliseconds: 200)),
        metadata: {'kind': 'ambient_placeholder', 'triggeredByInterrupt': true},
      );

      _currentConversation = conv.copyWith(
        messages: [...conv.messages, injectMsg, placeholderMsg],
        updatedAt: now,
      );
      onClearMessageInput?.call();
      notifyListeners();
      onScrollToBottom?.call();

      // 注入到 AgentLoop queue（AgentLoop 會在下一輪前整合）
      _agentLoop!.injectUserMessage(text);
      return;
    }

    // [教練 Agent 2026-07-22] Phase 5+ 互動式教學攔截
    // 教學進行中時，先讓教學服務處理使用者回應
    // [教練 Agent 2026-08-03] skipTutorial=true 時跳過（語音輸入專用，不被教學攔截）
    if (text.isNotEmpty) {
      final handled = await TemplateTutorialService.instance.handleUserResponse(
        text,
      );
      if (handled) {
        onClearMessageInput?.call();
        return;
      }
    }

    // [教練 Agent 2026-07-30 Phase 4] 自訂調用原則觸發偵測
    // 在正常訊息流程之前，先檢查是否為調用原則相關請求
    if (text.isNotEmpty && PolicyGenerator.shouldTrigger(text)) {
      final handled = await _tryHandlePolicyRequest(text);
      if (handled) return;
    }

    final normalized = text.toLowerCase();

    // [小葵 2026-10-14 M3] 修正捕手——Blue 的糾正信號自動落盤成標籤
    // （回饋閉環地基：寧漏勿誤、只記不動、冪等。失敗不影響對話主流程）
    if (text.isNotEmpty) {
      String? prevAssistant;
      final msgs = _currentConversation?.messages.toList() ?? <Message>[];
      for (final m in msgs.reversed) {
        if (m.role == 'assistant' && m.content.trim().isNotEmpty) {
          prevAssistant = m.content;
          break;
        }
      }
      final hit = CorrectionCatcher.detect(text, prevAssistant);
      // [小葵 2026-10-15 T2/D3] 隱式接受——非糾正的新一輪＝對上一輪的 accepted。
      // 沒有這個訊號源，onlineCalibration 只看得到 corrected，每桶 acc 恆 0 →
      // 必誤熔（Fable V3 斷鏈①）。隱式訊號可能誤差（話題切換≠接受），
      // 但「零 accepted 來源」比「帶噪 accepted」更糟——D3 原則。
      if (hit == null) {
        unawaited(_wireImplicitAccept());
      }
      if (hit != null) {
        final convId = _currentConversation?.id ?? 'unknown';
        final msgId =
            '${DateTime.now().millisecondsSinceEpoch}_correction';
        unawaited(CorrectionCatcher.instance.record(
          conversationId: convId,
          messageId: msgId,
          userText: text,
          assistantContext: prevAssistant ?? '',
          kind: hit.kind,
          hitPattern: hit.hit,
          refTurnId: EventLedger.instance.lastTurnId(
              conversationId: convId), // [T12-④] 本對話最後一輪
        ));
        // [小葵 2026-10-14 M3-第三刀] 糾正＝負反應——接活校準訊號源：
        // appendReaction 落 event_ledger（原本生產環境從未呼叫，死線）→
        // CalibrationBreaker.evaluate()（信心區正確率跌破地板→熔斷降級）
        unawaited(_wireCorrectionToBreaker());
      }
    }

    // [教練 Agent 2026-08-08] Transurfing：偵測話題切換 + 自動恢復
    if (text.isNotEmpty) {
      final engine = TransurfingEngine.instance;
      final shift = engine.detectTopicShift(text);
      if (shift != null) {
        // 偏離了——暫停當前水流
        engine.pauseActiveStream(bridgeNote: shift.suggestedBridgeNote);
        debugPrint('[Transurfing] 水流暫停：${shift.currentStream.title}');
      }

      // 檢查是否匹配到暫停的水流——自動恢復
      final resumed = engine.detectResume(text);
      if (resumed != null && resumed.id != engine.activeStream?.id) {
        engine.resumeStream(resumed.id);
        debugPrint('[Transurfing] 水流恢復：${resumed.title}');
      }
    }

    if (normalized.isEmpty && imagePath != null) {
      if (_currentConversation == null) await createNewConversation();
      onClearMessageInput?.call();
      await appendImageIntentMessage(imagePath);
      return;
    }
    // [以利沙 P0 修復十三輪 2026-06-27] NLU Agent 切換偵測：偵測「我想找 XXX」並切換 companion
    final companionSwitchId = await _tryDetectCompanionSwitch(text);
    if (companionSwitchId != null) {
      if (_currentConversation == null) await createNewConversation();
      // [以利沙 P1 修復十九輪 2026-06-27] 改為先彈 sheet 預選，補充確認步驟
      _pendingCompanionPickerRequest = true;
      _pendingAutoSwitchTarget = companionSwitchId;
      onClearMessageInput?.call();
      notifyListeners();
      return;
    }
    // [以利沙 P0 修復十八輪 2026-06-27] 模糊切換已觸發選擇器，提前 return 避免 LLM 和 sheet 雙重觸發
    if (_pendingCompanionPickerRequest) {
      if (_currentConversation == null) await createNewConversation();
      onClearMessageInput?.call();
      notifyListeners();
      return;
    }
    // [教練 Agent 2026-06-28] 修復：專案門自然語言退回 — 偵測「退回/取消/不是這個意思/重新來」
    // 當有活躍專案門且使用者意圖撤銷時，清除專案門並回覆確認訊息
    if (_activeProjectDoor != null) {
      final undoKeywords = [
        '退回',
        '取消專案',
        '撤銷',
        '不是這個意思',
        '重新來',
        '重新來過',
        '回去',
        '回到上一步',
        '上一動',
        '誤觸',
        '不小心',
        '搞錯了',
        '不要這個專案',
        '刪除專案',
        '取消這個專案',
        '重來',
      ];
      if (undoKeywords.any((k) => text.contains(k))) {
        final undoneTitle = _activeProjectDoor!.title;
        await _projectDoorStore.clearActive(id: _activeProjectDoor!.id);
        _activeProjectDoor = null;
        _lastProjectDoorJudgement = null;
        // [Sprint 11] 清對話的 projectDoorId
        if (_currentConversation != null &&
            _currentConversation!.projectDoorId != null) {
          final cleared = _currentConversation!.clearProjectDoorId();
          _currentConversation = cleared;
          await ConversationStore.save(cleared);
        }
        notifyListeners();
        if (_currentConversation == null) await createNewConversation();
        final undoMsg = Message(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          role: 'assistant',
          content: '已取消專案「$undoneTitle」。我們回到刚才的對話，你可以重新描述你想做的事，我會幫你正確建立。',
          timestamp: DateTime.now(),
          speakerId: _activeCompanion?.id ?? 'native-agent', // [指紋定律 2026-10-16 Blue] 原生 Agent 也有指紋，永不匿名
        );
        final conv = _currentConversation!;
        final updatedConv = conv.copyWith(
          messages: [...conv.messages, undoMsg],
          updatedAt: DateTime.now(),
        );
        _currentConversation = updatedConv;
        await ConversationStore.save(updatedConv);
        onClearMessageInput?.call();
        notifyListeners();
        onScrollToBottom?.call();
        return;
      }
    }
    final normalizedText = text.toLowerCase();

    // [2026-07-20] #5 修復：提前顯示用戶訊息 + 清空輸入框 + loading
    // 原本用戶訊息要到下方 L5585 才建立，中間卡了 classifyRoutingIntent +
    // inferBridgeAction + analyzeOrFallback 等 async LLM 呼叫（300ms~3s）
    // 現在：按送出 → 立刻看到訊息 + loading → 分析鏈背景跑 → AgentLoop 啟動
    if (_currentConversation == null) await createNewConversation();
    final _earlyUserMsg = Message(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      role: 'user',
      content: text.isEmpty && imagePath != null ? '已上傳圖片' : text,
      timestamp: DateTime.now(),
      imagePath: imagePath,
      // [教練 Agent 2026-07-22] Phase H — 帶上回覆目標
      replyToId: _replyTarget?.id,
      replyToSnippet: _replyTarget?.content,
    );
    // 消費回覆目標——用完即清
    _replyTarget = null;
    _currentConversation = _currentConversation!.copyWith(
      messages: [..._currentConversation!.messages, _earlyUserMsg],
      updatedAt: DateTime.now(),
    );
    // [2026-08-27 共視修復] user 訊息即時落地——不等 AI 回覆。
    // 舊行為：只更新記憶體，回覆完成才 save；中間頁面切走/流程中斷
    // → 訊息蒸發、對話空殼（Blue 回報「按新增按鈕後才看到」的根因之一）。
    // [小葵 2026-09-21] 命名掛進主鏈——UI 打字與 MCP /send_user_message 都走
    // 這裡，之前 _maybeAutoTitle 只在 saveCurrentConversation（幾乎沒人走），
    // 導致新對話停在「未命名對話」（9/21 實測抓包）。
    _maybeAutoTitle();
    unawaited(ConversationStore.save(_currentConversation!));
    onClearMessageInput?.call();
    clearSpeechInsertionState();
    _isLoading = true;
    notifyListeners();
    onScrollToBottom?.call();

    await applyImplicitRecalledInsightFeedback(text);
    await applyImplicitProjectDoorJudgementFeedback(text);
    // [小葵 2026-10-05 Blue 令] 對話中討論夢境議題後自動裁決——
    // 「討論好後確定裁決方案後，他可以自動的把未裁決的事情變成已裁決」
    await applyImplicitDreamAdjudication(text);

    // [Phase 2 #4] 先跑 async 語意路由分類，結果注入 IntentSpineService
    await _ensureSemanticIntentInited();
    RoutingIntentResult? routingSemantic;
    if (_semanticIntentService != null) {
      try {
        final convMessages =
            _currentConversation?.messages ?? const <Message>[];
        final history = ConversationHistoryProvider.extract(convMessages);
        routingSemantic = await _semanticIntentService!.classifyRoutingIntent(
          message: text,
          history: history,
        );
      } catch (_) {
        // 語意路由失敗，fallback 到純正則
      }
    }

    final intentSpine = const IntentSpineService().analyzeWithSemantic(
      text,
      hasImage: imagePath != null,
      semanticResult: routingSemantic,
    );
    final shouldTreatAsAnalysisIntent =
        intentSpine.shouldAnalyzeBeforeBridge &&
        !isRealtimeLookupQuestion(normalizedText);
    if (shouldTreatAsAnalysisIntent && _pendingBridgeTask != null) {
      await _pendingBridgeTaskStore.clear(taskId: _pendingBridgeTask!.id);
      _pendingBridgeTask = null;
      notifyListeners();
    }

    final autoIntent = IntentClassifier.classify(text);
    final visionImagePath = activeVisionImagePath(imagePath);
    // [教練 Agent 2026-08-19] 系統事件訊息（節點結果/畫布事件）不做意圖分類——
    // 機器輸出的文字不是使用者意圖，不得觸發橋樑動作（含 needsProvider modal）
    final directBridgeAction = _systemEventMessage
        ? null
        : (intentSpine.shouldSelectManagedFolderRuleFirst
            ? null
            : BridgeAction.tryParseDirectCommand(text));
    // [Phase 2 #13] 使用語意版 inferBridgeAction——L1 正則先跑，未命中走 L3 LLM
    BridgeAction? preliminaryBridgeAction = directBridgeAction;
    if (preliminaryBridgeAction == null && !_systemEventMessage) {
      final convMessages = _currentConversation?.messages ?? const <Message>[];
      final history = ConversationHistoryProvider.extract(convMessages);
      preliminaryBridgeAction = await inferChatBridgeActionForRequestSemantic(
        text,
        imagePath: visionImagePath,
        semanticService: _semanticIntentService,
        history: history,
      );
    }

    // [教練 Agent S21e 2026-07-09] 並行優化：明確執行指令時，brain reflection 不阻塞主流程
    // 之前：brain reflection (LLM 1-3s) → 記憶讀寫 → 語意路由 → Agent Loop（串行）
    // 現在：明確執行指令 → brain reflection 背景跑，Agent Loop 直接啟動
    // 安全性：非執行指令仍走完整串行流程（閒聊/分析/釐清需要 brain reflection 路由）
    //
    // [教練 Agent 2026-07-21] 本地輕量路徑——local provider 跳過 brain reflection LLM 層
    // 4B 模型不適合跑 5 個並行子分析（Transurfing/頻率共振/心腦合一/門與水流/專案門）
    // local 模式直接走 Agent Loop，用規則層的 brain reflection 即可
    // [教練 Agent 2026-07-22] 動態 Agent 路由——根據意圖模式決定本地或雲端
    // 場景 A（模糊/分析/閒聊）→ 本地 4B 輕量釐清
    // 場景 B（明確執行/專案/資產）→ 雲端 LLM 重算力
    //
    // [教練 Agent 2026-07-30] 使用者指定模型優先——不讓 ProviderRouter 覆蓋使用者選擇
    // 問題：ProviderRouter._cachedCloudProvider 是啟動時檢測的，如果使用者之後切換
    //   provider，cached 值會跟 StorageService 不同步，導致 route() 的
    //   「使用者明確選了外部 provider」檢查（L154-163）因 cloudProvider != storedProvider
    //   而 fail，最終路由到錯的 provider（例如使用者選 kimi 但路由到 local）。
    // 修復：在呼叫 route() 之前先檢查——如果使用者已經明確選了雲端 provider，
    //   直接建構 RoutedProvider，跳過 ProviderRouter.route() 的快取邏輯。
    final userProvider = await StorageService.getProvider();
    // [教練 Agent 2026-07-30] 「預設」模式 → 走動態路由，不算使用者指定雲端
    final userWantsCloud =
        userProvider != null &&
        userProvider != 'local' &&
        userProvider != 'default';
    final userWantsDefault = userProvider == 'default' || userProvider == null;
    final RoutedProvider routed;
    if (userWantsDefault) {
      // [Blue 令 2026-10-20 活預設] 先查用途角色映射——意圖→角色→鑰匙。
      // 設了對應角色（如 chat=glm、coding=claude）→ 直接用該鑰匙；
      // 沒設 → 走 resolveDefault()（本地優先＋自動雲端）。
      final roleForMode = switch (intentSpine.mode) {
        IntentSpineMode.execute => 'coding',
        IntentSpineMode.project => 'coding',
        IntentSpineMode.capabilitySetup => 'reasoning',
        IntentSpineMode.analyze => 'reasoning',
        IntentSpineMode.clarify => 'chat',
        IntentSpineMode.casual => 'chat',
        IntentSpineMode.assetReuse => 'chat',
      };
      final roleProvider = await StorageService.getRoleProvider(roleForMode);
      final roleToken = roleProvider != null
          ? await StorageService.getToken(provider: roleProvider)
          : null;
      if (roleProvider != null &&
          roleToken != null &&
          roleToken.trim().isNotEmpty) {
        routed = RoutedProvider(
          target: RoutedTarget.cloud,
          providerId: roleProvider,
          reason: '活預設：$roleForMode → $roleProvider（意圖：${intentSpine.mode.name}）',
        );
        ProviderRouter.instance.setCurrent(routed);
        debugPrint('[ChatController] 活預設 $roleForMode → $roleProvider');
      } else {
        // [教練 Agent 2026-07-30] 「預設」選型——走 resolveDefault() 依預設選型原則動態選模型
        routed = await ProviderRouter.instance.resolveDefault();
        debugPrint(
          '[ChatController] 預設選型 → ${routed.providerId}（${routed.reason}）',
        );
      }
    } else if (userWantsCloud) {
      // 使用者指定的直接用——不經過 ProviderRouter 的快取檢測
      routed = RoutedProvider(
        target: RoutedTarget.cloud,
        providerId: userProvider,
        reason: '使用者已選 $userProvider——跳過路由，直接使用（意圖：${intentSpine.mode.name}）',
      );
      ProviderRouter.instance.setCurrent(routed);
      debugPrint(
        '[ChatController] 使用者指定 provider: $userProvider（跳過 ProviderRouter）',
      );
    } else {
      // 沒指定（local 或 null）才走路由——讓 Router 依意圖動態決定
      routed = await ProviderRouter.instance.route(intentSpine);
    }
    final isLocalProvider = routed.isLocal;

    final isDirectExecution =
        intentSpine.shouldExecuteImmediately ||
        preliminaryBridgeAction != null ||
        isLocalProvider; // local 模式一律走快車道
    // [小葵 2026-09-15 Blue 架構令] 能力顧問從「前置攔截」翻轉為「後置救援」。
    //
    // 舊世界（2026-06）：App 剛起步，聊天=正則猜意圖+單次 LLM 呼叫，
    // 「做不了的事」只能前置引導開通。earlyCapabilityGap 在 agent 動手前
    // 用關鍵詞搶先攔截是當時唯一手段。
    //
    // 新世界（2026-09）：agent loop 有 30+ 工具（terminal/browser/canvas/
    // memory/vision/delegate）、畫布有 schedule 節點、本地 Gemma 常駐、
    // 金鑰匙一插四處通行。關鍵詞猜「能力缺口」的知識已過時——每次誤判
    // （畫布排程 v214、咖啡記憶 09-15）都是攔截順序顛倒的必然產物。
    //
    // 正確順序：先讓 agent 試（它有工具、有記憶、有判斷力），真執行
    // 真失敗（needsProvider）才由 handleCapabilityGapWithAdvisor 救援
    // （該路徑已存在於 7670/8238——真實失敗帶真實缺口類型，不是猜的）。
    //
    // 前置攔截保留程式碼但永久關閉（kill switch）——歷史脈絡供考古，
    // 若未來需要（例如 onboarding 場景）可重新打開。
    const preEmptiveCapabilityGapEnabled = false;
    final earlyCapabilityGap = !preEmptiveCapabilityGapEnabled
        ? null
        : (isDirectExecution
            ? null
            : (intentSpine.shouldAnalyzeBeforeBridge &&
                          !isRealtimeLookupQuestion(normalizedText) ||
                      intentSpine.shouldAskClarifyingQuestion ||
                      preliminaryBridgeAction?.type ==
                          BridgeActionType.desktopFiles
                  ? null
                  : detectCapabilityGap(text, imagePath: visionImagePath)));

    // brain reflection：直接執行指令時背景跑，否則阻塞（後續路由需要）
    BrainReflection brainReflection;
    if (isDirectExecution) {
      // 背景跑，不阻塞——結果用於 UI 狀態更新，不影響 Agent Loop
      brainReflection = _transurfingBrain.analyze(
        text,
        activeCompanionRole: _activeCompanion?.name,
        doorContext: DoorDecisionContext(
          currentMainlineLabel: '聊天與任務主線',
          activeProjectTitle: _activeProjectDoor?.title,
          activeProjectFlow: _activeProjectDoor?.currentFlow,
          pendingBridgeTaskTitle: _pendingBridgeTask?.title,
          pendingBridgeTaskMissing: _pendingBridgeTask?.missing,
          pendingReturnLabel: _pendingDoorReturn?.deferredLabel,
          requestedCapabilityLabel:
              preliminaryBridgeAction?.type == BridgeActionType.unknown
              ? null
              : preliminaryBridgeAction?.type.displayLabel,
        ),
      );
      // LLM 版背景跑，完成後更新 UI
      _runBrainReflectionBackground(
        text: text,
        preliminaryBridgeAction: preliminaryBridgeAction,
      );
    } else {
      // [教練 Agent 2026-07-22] #4 L1: 黃燈時跳過 LLM brain reflection，只用規則版
      if (MemoryGuardService.instance.brainReflectionPaused) {
        brainReflection = _transurfingBrain.analyze(
          text,
          activeCompanionRole: _activeCompanion?.name,
          doorContext: DoorDecisionContext(
            currentMainlineLabel: '聊天與任務主線',
            activeProjectTitle: _activeProjectDoor?.title,
            activeProjectFlow: _activeProjectDoor?.currentFlow,
            pendingBridgeTaskTitle: _pendingBridgeTask?.title,
            pendingBridgeTaskMissing: _pendingBridgeTask?.missing,
            pendingReturnLabel: _pendingDoorReturn?.deferredLabel,
            requestedCapabilityLabel:
                preliminaryBridgeAction?.type == BridgeActionType.unknown
                ? null
                : preliminaryBridgeAction?.type.displayLabel,
          ),
        );
        debugPrint('[MemoryGuard] L1: 跳過 LLM brain reflection（黃燈）');
      } else {
        brainReflection = await analyzeOrFallback(
          text,
          activeCompanionRole: _activeCompanion?.name,
          doorContext: DoorDecisionContext(
            currentMainlineLabel: '聊天與任務主線',
            activeProjectTitle: _activeProjectDoor?.title,
            activeProjectFlow: _activeProjectDoor?.currentFlow,
            pendingBridgeTaskTitle: _pendingBridgeTask?.title,
            pendingBridgeTaskMissing: _pendingBridgeTask?.missing,
            pendingReturnLabel: _pendingDoorReturn?.deferredLabel,
            requestedCapabilityLabel:
                preliminaryBridgeAction?.type == BridgeActionType.unknown
                ? null
                : preliminaryBridgeAction?.type.displayLabel,
          ),
          timeout: const Duration(
            seconds: 3,
          ), // [以利沙 Sprint 11 Part B] sendMessage 用更短 timeout
        );
        BrainReflectionStore.instance.update(brainReflection);
      }
    }
    // [教練 Agent Sprint 2 2026-07-04] 宣告/確認/行動閉環：pipeline 跑完後路由
    final intentionResult = await _handleIntentionRouting(
      text,
      brainReflection,
    );
    final finalReflection = intentionResult != null
        ? BrainReflection(
            userIntent: brainReflection.userIntent,
            attentionState: brainReflection.attentionState,
            pendulumSignals: brainReflection.pendulumSignals,
            importanceLevel: brainReflection.importanceLevel,
            heartMindAlignment: brainReflection.heartMindAlignment,
            fraileResonance: brainReflection.fraileResonance,
            doorCandidates: brainReflection.doorCandidates,
            doorDecision: brainReflection.doorDecision,
            flowState: brainReflection.flowState,
            recommendedMove: intentionResult.move,
            companionExpression: brainReflection.companionExpression,
            guidance: brainReflection.guidance,
            guidanceHint: brainReflection.guidanceHint,
            layerResults: brainReflection.layerResults,
          )
        : brainReflection;
    // earlyCapabilityGap 已在上方 isDirectExecution 分支定義
    final shouldDeferBrainInstrumentation =
        preliminaryBridgeAction != null || earlyCapabilityGap != null;
    var recalledBrainInsights = <String>[];
    var insightFeedbacks = <String, TransurfingInsightFeedback>{};
    var brainInsights = <String>[];
    var secondBrainTrace = preliminaryBridgeAction == null
        ? SecondBrainTrace(agentName: _activeCompanion?.name)
        : bridgeSecondBrainTrace(
            preliminaryBridgeAction,
            capabilityGap: earlyCapabilityGap,
          );
    var secondBrainAssociationFeedbacks =
        <String, SecondBrainAssociationFeedback>{};
    var agentMotivation = fallbackAgentMotivationSnapshot();
    var brainSkillRegistry = const BrainSkillRegistrySnapshot();

    try {
      if (!shouldDeferBrainInstrumentation) {
        recalledBrainInsights = await MemoryStore.recallTransurfingInsights(
          brainReflection,
        );
        if (recalledBrainInsights.isNotEmpty) {
          await BrainProgressStore.awardXp(
            (recalledBrainInsights.length * 5).clamp(0, 15).toInt(),
          );
        }
        insightFeedbacks = await MemoryStore.getTransurfingInsightFeedbacks(
          recalledBrainInsights,
        );
        brainInsights = await MemoryStore.rememberTransurfingInsights(
          brainReflection,
        );
        secondBrainTrace = await _secondBrainTraceService.build(
          reflection: brainReflection,
          recalledInsights: recalledBrainInsights,
          newInsights: brainInsights,
          feedbacks: insightFeedbacks,
          activeCompanionName: _activeCompanion?.name,
          activeCompanionId: _activeCompanion?.id, // [以利沙 P0 修復十八輪 2026-06-27]
          activeBridgeActionLabel: bridgeInsightLabel(preliminaryBridgeAction),
        );
        secondBrainAssociationFeedbacks =
            await MemoryStore.getSecondBrainAssociationFeedbacks(
              secondBrainTrace.associations,
            );
        agentMotivation = await _agentMotivationEngine.getSnapshot(
          _activeCompanion?.name,
        );
        brainSkillRegistry = await buildBrainSkillRegistrySafely(
          text,
          bridgeAction: preliminaryBridgeAction,
        );
      } else {
        // [以利沙 2026-06-26] shouldDeferBrainInstrumentation == true 時，
        // 仍執行一次 build() 取得 Second Brain 記憶，再合併進 bridgeSecondBrainTrace。
        final baseBrainTrace = await _secondBrainTraceService.build(
          reflection: brainReflection,
          recalledInsights: const [],
          newInsights: const [],
          feedbacks: const {},
          activeCompanionName: _activeCompanion?.name,
          activeCompanionId: _activeCompanion?.id, // [以利沙 P0 修復十八輪 2026-06-27]
          activeBridgeActionLabel: bridgeInsightLabel(preliminaryBridgeAction),
        );
        secondBrainTrace = SecondBrainTrace(
          agentName: secondBrainTrace.agentName,
          brainName: secondBrainTrace.brainName,
          recalledMemories: [
            ...baseBrainTrace.recalledMemories,
            ...secondBrainTrace.recalledMemories,
          ],
          newInsights: [
            ...baseBrainTrace.newInsights,
            ...secondBrainTrace.newInsights,
          ],
          outputs: secondBrainTrace.outputs,
          associations: [
            ...baseBrainTrace.associations,
            ...secondBrainTrace.associations,
          ],
        );
      }
    } catch (error) {
      debugPrint('[ChatController] brain instrumentation skipped: $error');
    }
    final displayIntent = _manualIntent ?? autoIntent;
    _currentMode =
        '${IntentClassifier.intentIcon(displayIntent)} ${IntentClassifier.intentName(displayIntent)}';
    notifyListeners();

    List<String> extractedMemories = [];
    if (text.isNotEmpty && !shouldDeferBrainInstrumentation) {
      extractedMemories = await MemoryStore.extractFromMessage(text);
      if (extractedMemories.isNotEmpty) {
        // [教練 Agent Bug#7 修復 2026-07-03] 快車道成功時觸發 UI flash
        setMemoryFlash(text: '記住了：${extractedMemories.first}');
        if (kIsWeb) {
          debugPrint('[Memory] extracted: ${extractedMemories.length} items');
        }
      }
    } else if (text.isNotEmpty && shouldDeferBrainInstrumentation) {
      // [以利沙 修復三 2026-06-27] 橋樑輪次也要提取記憶，不能跳過
      extractedMemories = await MemoryStore.extractFromMessage(text);
      // [以利沙 P1 修復 2026-06-27] defer 路徑補 UI flash
      // [教練 Agent Bug#7 修復 2026-07-03] 統一用 setMemoryFlash，含 text + timer
      if (extractedMemories.isNotEmpty) {
        setMemoryFlash(text: '記住了：${extractedMemories.first}');
      }
    }

    // [教練 Agent 2026-07-03] 同步寫入大腦容器（向量記憶）
    // 平行寫入，不阻塞主流程；失敗不影響 MemoryStore
    // P5 修復：寫入前先做向量去重，避免重複記憶灌爆 DB
    if (extractedMemories.isNotEmpty) {
      final agentName = _activeCompanion?.name ?? '夥伴';
      final companionId = _activeCompanion?.id ?? '';
      final brain = BrainContainerService.instance;
      for (final memory in extractedMemories) {
        // P5 修復：向量去重 — 若已有相似記憶則跳過
        if (brain.isInitialized && brain.isModelAvailable) {
          final existing = await brain.retrieveMemories(
            query: memory,
            limit: 3,
          );
          final isDuplicate = existing.any((r) => r.similarity >= 0.85);
          if (isDuplicate) {
            debugPrint('[記憶] 跳過重複（快車道→BrainContainer）: $memory');
            continue;
          }
        }
        await brain.writeMemory(
          content: memory,
          agent: agentName,
          companionId: companionId,
          source: MemorySource.chat,
          speaker: MemorySpeaker.user, // [出處戳] 快車道提取自使用者訊息=使用者說的
        );
      }
    }

    // [教練 Agent 2026-07-03] 慢車道：LLM 語意記憶提取（背景並行，不阻塞對話）
    // 正則快車道只抓「記住：」「我叫」等明確前綴；
    // LLM 慢車道理解語意，抓隱含的、無前綴詞的記憶。
    // [小葵 2026-09-22 偷學令③ Dreaming] 慢車道改走 DreamBuffer——
    // 積 10 則或閒置 5 分鐘一次批次做夢（跨訊息因果才看得到），
    // 不再逐則 fire-and-forget。P1 的 4 字門檻由 buffer 內過濾。
    if (text.isNotEmpty && text.trim().length >= 4) {
      final agentName = _activeCompanion?.name ?? '夥伴';
      final companionId = _activeCompanion?.id ?? '';
      DreamBuffer.instance.add(
        text,
        agentName: agentName,
        companionId: companionId,
        alreadyExtracted: extractedMemories,
      );
    }

    // [2026-07-20] #5 修復：用戶訊息已在上方提前建立，這裡只更新狀態
    final conv = _currentConversation!;
    final updatedMessages = conv.messages; // 已含提前加入的 userMsg

    final shouldPrioritizeProjectSemanticRoute =
        intentSpine.shouldCreateOrRouteProject ||
        intentSpine.shouldCheckReusableAssets ||
        projectSemanticRouteShouldOverrideBridge(text, preliminaryBridgeAction);
    final projectSemanticRoute =
        shouldPrioritizeProjectSemanticRoute ||
            (preliminaryBridgeAction == null && earlyCapabilityGap == null)
        ? await routeProjectSemanticIntent(text, updatedMessages)
        : const ProjectSemanticRoute.none();
    if (projectSemanticRoute.hasRoute) {
      secondBrainTrace = projectSemanticRouteTrace(
        projectSemanticRoute,
        fallback: secondBrainTrace,
      );
      secondBrainAssociationFeedbacks =
          await MemoryStore.getSecondBrainAssociationFeedbacks(
            secondBrainTrace.associations,
          );
    }
    final projectDoorProposal = projectSemanticRoute.projectDoor;
    final projectContextTransferProposal = projectDoorProposal == null
        ? projectSemanticRoute.contextTransfer
        : null;
    final digitalAssetInvocationProposal =
        projectDoorProposal == null && projectContextTransferProposal == null
        ? projectSemanticRoute.digitalAssetInvocation
        : null;
    var updatedConv = conv.copyWith(
      messages: updatedMessages,
      updatedAt: DateTime.now(),
    );

    _currentConversation = updatedConv;
    // [2026-07-20] #5: onClearMessageInput/clearSpeechInsertionState/_isLoading
    // 已在上方提前執行，這裡不重複
    _thoughtStage = stageForBrainReflection(finalReflection);
    _brainReflection = finalReflection;
    _recalledBrainInsights = recalledBrainInsights;
    _secondBrainTrace = secondBrainTrace;
    _brainSkillRegistry = brainSkillRegistry;
    _agentMotivation = agentMotivation;
    _insightFeedbacks = insightFeedbacks;
    _secondBrainAssociationFeedbacks = secondBrainAssociationFeedbacks;
    // [教練 Agent 2026-07-03] 方案 C 快車道：先掃描使用者訊息關鍵字
    // 命中時覆蓋 brain reflection 的 mood/action，讓狀態圖即時反應
    final activeCompanion = CompanionStore().activeCompanion;
    final keywordSpec = CompanionStatusHelper.scanTextForState(
      text: text,
      companion: activeCompanion,
    );
    if (keywordSpec != null) {
      _companionMoodOverride = keywordSpec.mood;
      _companionActionOverride = keywordSpec.action;
    } else {
      _companionMoodOverride = finalReflection.companionExpression.mood;
      _companionActionOverride = finalReflection.companionExpression.action;
    }
    _thoughtTelemetry = telemetryFromMessages(
      updatedMessages,
      memories: extractedMemories.length + brainInsights.length,
      attachments: visionImagePath == null ? 0 : 1,
    );
    _lastBrainActionStage = _thoughtStage;
    _lastBrainActionTelemetry = _thoughtTelemetry;
    _activeBridgeActionLabel = bridgeInsightLabel(preliminaryBridgeAction);
    _lastBridgeActionLabel = _activeBridgeActionLabel;
    if (extractedMemories.isNotEmpty) {
      _memoryFlashText = extractedMemories.length > 1
          ? '已記住 ${extractedMemories.length} 條'
          : '已記住: ${extractedMemories.first}';
      _showMemoryFlash = true;
      _brainPulse = true;
    }
    notifyListeners();
    onFocusMessageInput?.call();
    startThoughtPulse();

    await ConversationStore.save(updatedConv);
    final all = await ConversationStore.getAll();
    _conversations = all;
    notifyListeners();
    onScrollToBottom?.call();

    if (text.isEmpty && imagePath != null) {
      stopThinking();
      await appendImageIntentMessage(imagePath);
      return;
    }
    // [教練 Agent 2026-08-09] Agent Loop 優先於 IntentSpine 反問
    // 問題：IntentSpine.shouldAskClarifyingQuestion 攔截了訊息，
    // 導致 Agent Loop 從未被觸發，使用者只看到罐頭反問文字。
    // 修法：先嘗試 init Agent Loop，如果啟用 → 跳過反問直接進 Loop。
    await _ensureAgentLoopInitialized();
    
    if (!_agentLoopEnabled || _agentLoop == null) {
      // Agent Loop 沒啟用 → 走舊路徑（反問 / 罐頭）
      if (intentSpine.shouldAskClarifyingQuestion) {
        stopThinking();
        await appendIntentClarificationMessage(intentSpine);
        return;
      }
    }
    if (projectDoorProposal != null) {
      stopThinking();
      _lastProjectDoorJudgement = projectDoorProposal;
      notifyListeners();
      if (shouldAutoCreateProjectDoor(projectDoorProposal, text)) {
        await createProjectDoorFromCard(projectDoorProposal);
        return;
      }
      await appendProjectDoorCard(projectDoorProposal);
      return;
    }
    if (projectContextTransferProposal != null) {
      stopThinking();
      await appendProjectContextTransferCard(projectContextTransferProposal);
      return;
    }
    if (intentSpine.shouldSelectManagedFolderRuleFirst) {
      stopThinking();
      await appendManagedFolderRulePickerCard(text);
      return;
    }
    if (digitalAssetInvocationProposal != null) {
      stopThinking();
      await appendDigitalAssetInvocationCard(digitalAssetInvocationProposal);
      return;
    }

    // [以利沙 P0 修復十三輪 2026-06-27] API Key 未設定時，不顯示錯誤，改為引導
    final hasToken = await StorageService.hasToken();
    if (!hasToken) {
      if (_currentConversation == null) await createNewConversation();
      onClearMessageInput?.call();
      // 先將使用者訊息加入對話，讓畫面顯示正確
      final conv0 = _currentConversation!;
      final userMsg0 = Message(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        role: 'user',
        content: text,
        timestamp: DateTime.now(),
      );
      _currentConversation = conv0.copyWith(
        messages: [...conv0.messages, userMsg0],
        updatedAt: DateTime.now(),
      );
      await ConversationStore.save(_currentConversation!);
      notifyListeners();
      await handleCapabilityGapWithAdvisor(
        result: BridgeActionResult(
          status: BridgeActionStatus.needsProvider,
          message: '還沒設定 AI 服務密碼',
          metadata: const {'type': 'api_key', 'prompt': '設定好服務密碼，夥伴就能開始幫你了'},
        ),
      );
      return;
    }

    try {
      setThoughtStage(AgentActivityStage.context);
      // [以利沙 2026-06-26] 修復二：若處於 advisor 流程且訊息含求助詞彙，注入 advisor 脈絡前綴
      final advisorContextPrefix = () {
        if (_activeAdvisorCard == null) return null;
        const helpKeywords = [
          '不知道', '怎麼設定', '什麼意思', '看不懂', '不懂', '怎麼辦', 'help', 'how',
          // [以利沙 P2 詞庫擴充 2026-06-26] 補充常見口語求助詞
          '哪裡', '如何', '在哪', '怎麼找', '找到', '取得', '申請', '要去', '該怎麼',
        ];
        final lc = text.toLowerCase();
        final hasHelpKeyword = helpKeywords.any((kw) => lc.contains(kw));
        if (!hasHelpKeyword) return null;
        // [以利沙 修復三 2026-06-27] awaitingSelection 時注入 candidates 概要；其他 step 維持 setupSteps
        final activeCard = _activeAdvisorCard!;
        String stepsHint;
        if (activeCard.currentStep == CapabilityAdvisorStep.awaitingSelection) {
          final candidatesSummary = activeCard.candidates
              .map((c) {
                final tag = c.isRecommended ? '（推薦）' : '';
                return '${c.name}$tag';
              })
              .join('、');
          stepsHint = candidatesSummary.isNotEmpty
              ? '\n目前可選方案：$candidatesSummary'
              : '';
        } else {
          final currentSteps = activeCard.selectedCandidate?.setupSteps ?? [];
          stepsHint = currentSteps.isNotEmpty
              ? '\n目前的開通步驟是：${currentSteps.join("、")}'
              : '';
        }
        return '[使用者正在進行能力開通流程，他對以下步驟有疑問，請用簡單白話說明：]$stepsHint ';
      }();
      // [小葵 2026-09-22 打鐵趁熱] 歷史瘦身——全量歷史塞 user message 是
      // token 大戶主因（194 則對話逐輪重送，每輪成本線性上漲）。
      // 修法：最近 12 則、每則截 1200 字（保留完整近語境）；
      // 更早歷史由 K1 記憶檢索按需供給——記得的部分不必重送。
      final _allHistory = updatedMessages
          .where((m) => m.role == 'user' || m.role == 'assistant')
          .map((m) {
            if (advisorContextPrefix != null &&
                m.role == 'user' &&
                m.content == text) {
              return {
                'role': m.role,
                'content': '$advisorContextPrefix${m.content}',
              };
            }
            return {'role': m.role, 'content': m.content};
          })
          .toList();
      // 排除本輪剛加入的 userMsg（稍後以「使用者最新訊息」單獨呈現）
      final _histSrc = _allHistory.length > 1
          ? _allHistory.sublist(0, _allHistory.length - 1)
          : _allHistory;
      const _keepCount = 12;
      const _maxHistChars = 1200;
      final _recentSrc = _histSrc.length > _keepCount
          ? _histSrc.sublist(_histSrc.length - _keepCount)
          : _histSrc;
      final history = _recentSrc.map((m) {
        final c = (m['content'] ?? '').length > _maxHistChars
            ? '${(m['content'] as String).substring(0, _maxHistChars)}…（過長已截斷）'
            : (m['content'] as String? ?? '');
        return {'role': (m['role'] as String? ?? 'user'), 'content': c};
      }).toList();
      updateThoughtTelemetry(
        messages: history.length,
        chars: history.fold<int>(
          0,
          (total, message) => total + (message['content']?.length ?? 0),
        ),
      );

      setThoughtStage(AgentActivityStage.routing);
      var bridgeAction = preliminaryBridgeAction;
      final capabilityGap = earlyCapabilityGap;
      if (capabilityGap != null) {
        stopThinking();
        // [以利沙 Capability Advisor 2026-06-25]
        // 優先啟動顧問流程，fallback 到靜態卡
        try {
          final gapType = _detectGapTypeFromCard(capabilityGap);
          await handleCapabilityGapWithAdvisor(
            result: BridgeActionResult(
              status: BridgeActionStatus.needsProvider,
              message: capabilityGap.status,
              metadata: {
                'type': gapType,
                'prompt': capabilityGap.request,
                'setupRoute': capabilityGap.route,
              },
            ),
            bridgeAction: bridgeAction,
          );
        } catch (_) {
          await appendCapabilityGapCard(
            capabilityGap,
            bridgeAction: bridgeAction,
          );
        }
        return;
      }

      // [教練 Agent 2026-07-19] AgentLoop 優先——當 AgentLoop 啟用時，跳過 bridgeAction
      // 因為 AgentLoop 本身有 browse/vision/desktop_files 等工具，能做 bridgeAction 能做的事
      // 而且更聰明（多輪工具呼叫 + LLM 推理）
      // 只有 AgentLoop 未啟用或訊息明確是快捷指令（如「整理桌面」直接命中）才走 bridgeAction
      await _ensureAgentLoopInitialized();
      final skipBridgeActionForAgentLoop =
          _agentLoopEnabled &&
          _agentLoop != null &&
          _agentToolRegistry != null &&
          !intentSpine.shouldSelectManagedFolderRuleFirst;

      if (bridgeAction != null && !skipBridgeActionForAgentLoop) {
        final executableBridgeAction = await prepareDesktopFilesAction(
          bridgeAction,
        );
        if (executableBridgeAction == null) {
          stopThinking();
          await appendLocalSystemMessage(
            '桌面整理橋已暫停：你還沒有選擇要掃描的資料夾。\n\n我不會直接讀取你的桌面；等你選擇資料夾後，我會先只讀掃描並列出整理計畫。',
          );
          return;
        }
        setThoughtStage(AgentActivityStage.bridge);
        updateThoughtTelemetry(bridgeActions: 1);
        final result = await _bridgeActionExecutor.execute(
          executableBridgeAction,
        );

        stopThinking();
        syncBridgeEvidenceToCompanion(result);
        // [以利沙 P2 UI trace 合併 2026-06-26] 改覆蓋為合併，保留已累積的使用者記憶
        final bridgeTrace0 = bridgeSecondBrainTrace(
          executableBridgeAction,
          result: result,
        );
        _secondBrainTrace = SecondBrainTrace(
          agentName: _secondBrainTrace?.agentName ?? bridgeTrace0.agentName,
          recalledMemories: [
            ...(_secondBrainTrace?.recalledMemories ?? []),
            ...bridgeTrace0.recalledMemories,
          ],
          newInsights: [
            ...(_secondBrainTrace?.newInsights ?? []),
            ...bridgeTrace0.newInsights,
          ],
          outputs: bridgeTrace0.outputs,
          associations: [
            ...(_secondBrainTrace?.associations ?? []),
            ...bridgeTrace0.associations,
          ],
        );
        _lastBridgeActionLabel = bridgeInsightLabelForResult(
          executableBridgeAction,
          result,
        );
        notifyListeners();
        if (result.status == BridgeActionStatus.completed) {
          await appendBridgeResultMessage(result);
        } else if (result.status == BridgeActionStatus.needsConfirmation) {
          await appendBridgeConfirmationMessage(bridgeAction, result);
        } else if (result.status == BridgeActionStatus.needsProvider) {
          // [以利沙 Capability Advisor 2026-06-25]
          await handleCapabilityGapWithAdvisor(
            result: result,
            bridgeAction: bridgeAction,
          );
        }
        if (result.status != BridgeActionStatus.completed &&
            result.status != BridgeActionStatus.needsProvider) {
          onShowBridgeResultSnackBar?.call(result);
        }
        return;
      }

      setThoughtStage(AgentActivityStage.waiting);

      // [教練 Agent 2026-07-25] 記憶回溯 — 偵測失憶抱怨，搜尋完整歷史
      final recallNote = _checkMemoryRecall(text, updatedMessages);

      // [教練 Agent S21c] Agent Loop 分支——啟用時走 AgentLoop，否則走原本的 ApiService
      final agentLoopReply = await _runAgentLoopIfNeeded(
        userMessage: text,
        companionPersona: _activeCompanion?.systemPrompt,
        contextMemory: recalledBrainInsights.isNotEmpty
            ? recalledBrainInsights.join('\n')
            : null,
        conversationHistory: history.cast<Map<String, String>>(),
        memoryRecallNote: recallNote, // [教練 Agent 2026-07-25] 記憶回溯
        prohibitPaidTools: _lastMessageWasSystemEvent, // [教練 Agent 2026-08-20] 機器輪次禁用付費工具
      );

      if (agentLoopReply != null) {
        // Agent Loop 路線
        setThoughtStage(AgentActivityStage.composing);

        // [教練 Agent 2026-08-21] 死命令——所有生成的數位資產必須讓使用者看見。
        // 收集「全部」媒體（不只第一個）：批量生成 N 張 = N 張全部送出。
        String? mediaUrl;
        final allMediaAssets = <String>[];
        for (final turn in agentLoopReply.turns) {
          final mu = turn.toolResult?.mediaUrl;
          if (mu != null && mu.isNotEmpty) {
            mediaUrl ??= mu; // 第一個仍進 imagePath（單圖行為不變）
            allMediaAssets.add(mu);
          }
        }

        // 媒體是 assistant message 的附件，不是回覆文字的一部分。
        // 不把本機絕對路徑暴露到使用者閱讀的句子裡。
        final rawReplyText = agentLoopReply.reply;

        // D12: 偵測步驟完成標記，更新畫布進度，過濾標記
        final cleanReplyText = await _processStepMarkers(rawReplyText);

        // P0.5 provenance：模型標示必須來自這輪真正的 execution receipt，
        // 不能回讀 Settings 的預設 provider。多模態還沒帶 receipt 時保持 null，
        // 寧可不顯示也不顯示錯誤 Kimi/GLM 標示。
        final loopClient = _agentLoop?.llmClient;
        final textReceipt = loopClient is ProductionAgentLoopLLMClient
            ? loopClient.lastReceipt
            : null;
        final imageTurn = agentLoopReply.turns
            .where(
              (turn) =>
                  turn.toolCall?.name == 'generate_image' &&
                  turn.toolResult?.success == true,
            )
            .lastOrNull;
        final imageMeta = imageTurn?.toolResult?.metadata;
        final textProvenance = textReceipt == null
            ? null
            : <String, dynamic>{
                'provider': textReceipt.provider,
                'model': textReceipt.model,
                if (textReceipt.usedLocalFallback) 'fallback': 'local',
              };
        final imageProvenance = imageMeta == null
            ? null
            : <String, dynamic>{
                'provider': imageMeta['provider'],
                'model': imageMeta['model'],
                'adapter': imageMeta['adapter'],
                'mode': imageMeta['mode'],
                'quality': imageMeta['quality'],
              };
        imageProvenance?.removeWhere((_, value) => value == null);

        // P0.5: 從 Agent Loop turns 萃取安全版的任務證據，寫進 assistant message metadata。
        // 不暴露 raw tool args、不寫絕對路徑、不寫 token／cookie。
        final tasks = TaskEvidenceBuilder.build(agentLoopReply.turns);
        // [因果引擎 L2 2026-09-11] 證據等級——確定性計算：
        // 本輪有成功改變型工具=2 干預驗證；只有觀察型=1 觀測；純文字=0 推測。
        // 不是 LLM 自評——「知道自己正在推測還是已驗證」由結構判定。
        final evidenceGrade = CausalLedger.gradeForTurns([
          for (final t in agentLoopReply.turns)
            (t.toolCall?.name, t.toolResult?.success),
        ]);
        final assistantMetadata = TaskEvidenceBuilder.patchAssistantMetadata(
          existing: {
            if (textProvenance != null) 'textExecution': textProvenance,
            if (imageProvenance != null) 'imageExecution': imageProvenance,
            'evidenceGrade': evidenceGrade.level,
            'evidenceGradeLabel': evidenceGrade.label,
          },
          tasks: tasks,
        );

        final assistantMsg = Message(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          role: 'assistant',
          content: cleanReplyText,
          timestamp: DateTime.now(),
          model: textReceipt?.model, // P0.5：僅顯示這輪實際 LLM receipt
          speakerId: _activeCompanion?.id ?? 'native-agent', // [指紋定律 2026-10-16 Blue] 原生 Agent 也有指紋，永不匿名
          imagePath: mediaUrl,
          mediaAssets: allMediaAssets, // [教練 Agent 2026-08-21] 死命令——全部資產送出
          metadata: assistantMetadata,
        );

        updatedConv = updatedConv.copyWith(
          messages: [...updatedMessages, assistantMsg],
          updatedAt: DateTime.now(),
        );

        // [2026-07-20] 渲染感應器——AgentLoop 回覆也要通知 MCP /get_latest_messages
        // 根因：AgentLoop 路徑直接建 Message 不走 appendLocalSystemMessage，
        // setLastAgentReply 從未被觸發，導致 get_latest_messages 永遠回 false。
        final preview = cleanReplyText.length > 120
            ? '${cleanReplyText.substring(0, 120)}...'
            : cleanReplyText;
        debugPrint('[AgentReply] $preview');
        CanvasMcpRegistry.instance.setLastAgentReply(cleanReplyText);
        CanvasMcpRegistry.instance.onAgentReply?.call(cleanReplyText);

        _thoughtPulseTimer?.cancel();
        _currentConversation = updatedConv;
        _isLoading = false;
        _thoughtStage = null;
        _thoughtPulse = false;
        _thoughtTelemetry = const AgentActivityTelemetry();
        _activeBridgeActionLabel = null;
        _retryCount = 0;
        notifyListeners();
        await ConversationStore.save(updatedConv);
        final allConvsAgent = await ConversationStore.getAll();
        _conversations = allConvsAgent;
        notifyListeners();
        onScrollToBottom?.call();
        return;
      }

      // [教練 Agent 2026-07-25] 記憶回溯 — 偵測失憶抱怨，搜尋完整歷史
      // 注意：recallNote 在 Agent Loop 路徑上方已計算，這裡重用
      // 如果走 ApiService 路徑（Agent Loop 未啟用），recallNote 為 null（未計算）
      // 所以這裡只在 recallNote 尚未計算時才計算
      final effectiveRecallNote =
          recallNote ?? _checkMemoryRecall(text, updatedMessages);

      // 原本路線——ApiService.sendMessage
      final response = await ApiService.sendMessage(
        history,
        overrideIntent: _manualIntent,
        brainReflection: brainReflection,
        recalledTransurfingInsights: recalledBrainInsights,
        activeProjectDoor: _activeProjectDoor,
        secondBrainMemories: secondBrainTrace.recalledMemories,
        pendingHandoffNote: _pendingHandoffNote, // [以利沙 P0 修復十七輪 2026-06-27]
        memoryRecallNote: effectiveRecallNote, // [教練 Agent 2026-07-25] 記憶回溯
      );
      _pendingHandoffNote = null; // [以利沙 P0 修復十七輪 2026-06-27] 用完即清除，只注入一次
      setThoughtStage(AgentActivityStage.composing);
      updateThoughtTelemetry(
        bridgeActions: response.bridgeActions.length,
        tokens: response.totalTokens,
      );

      final assistantMsg = Message(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        role: 'assistant',
        content: response.cleanContent,
        timestamp: DateTime.now(),
        tokens: response.totalTokens,
        model: response.model,
        bridgeActions: response.bridgeActions,
        speakerId: _activeCompanion?.id ?? 'native-agent', // [指紋定律 2026-10-16 Blue] 原生 Agent 也有指紋，永不匿名（原以利沙 P0）
        quickReplies: response.quickReplies, // [教練 Agent 2026-06-29] 快速選項
      );

      updatedConv = updatedConv.copyWith(
        messages: [...updatedMessages, assistantMsg],
        updatedAt: DateTime.now(),
      );

      _thoughtPulseTimer?.cancel();
      // [教練 Agent 2026-07-03] AI 回覆也掃描關鍵字，命中時顯示對應狀態圖
      final replyKeywordSpec = CompanionStatusHelper.scanTextForState(
        text: response.cleanContent,
        companion: _activeCompanion,
      );
      if (replyKeywordSpec != null) {
        AgentActivityStore.instance.update(
          stage: AgentActivityStage.composing,
          mood: replyKeywordSpec.mood,
          action: replyKeywordSpec.action,
          pulse: false,
          active: false,
        );
      } else {
        AgentActivityStore.instance.idle();
      }
      _currentConversation = updatedConv;
      _totalTokens += response.totalTokens;
      _isLoading = false;
      _thoughtStage = null;
      _thoughtPulse = false;
      _thoughtTelemetry = const AgentActivityTelemetry();
      _activeBridgeActionLabel = null;
      _retryCount = 0; // [教練 Agent 2026-06-28] 成功回應，重置重試計數
      // [教練 Agent 2026-08-03] 中文對話的回覆前自動命名（5 則訊息後）
      _maybeAutoTitle();
      notifyListeners();
      // 如果命名後 _currentConversation 已經更新（標題被改），用最新的寫入
      await ConversationStore.save(_currentConversation ?? updatedConv);
      final allConvs = await ConversationStore.getAll();
      _conversations = allConvs;
      notifyListeners();
      onScrollToBottom?.call();

      await autoExecuteAssistantBridgeActions(assistantMsg);

      final observations = await BridgeConsciousness.observeConversation(
        text,
        response.content,
        semanticService: _semanticIntentService,
        history: ConversationHistoryProvider.extract(
          _currentConversation?.messages ?? const [],
        ),
      );
      if (observations.isNotEmpty) {
        onShowConsciousnessObservation?.call(observations);
      }
    } on DioException catch (e) {
      stopThinking();
      // [教練 Agent 2026-06-28] 修復：API 失敗自動重試一次
      final isRetryable =
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown;
      if (isRetryable && _retryCount < 1) {
        _retryCount++;
        onShowError?.call('連線不穩，正在自動重試...');
        await Future.delayed(const Duration(seconds: 2));
        await sendMessage(imagePath: imagePath);
        return;
      }
      _retryCount = 0;
      final message = '連線失敗: ${dioErrorMessage(e)}';
      onShowError?.call(message);
      await appendLocalSystemMessage(
        '$message\n\n目前主腦連線被中斷，這通常是 provider、Gateway 或網路暫時斷線。你可以直接重試，或按「設定」檢查主腦金鑰與 Gateway 連線。',
      );
    } catch (e) {
      stopThinking();
      // [教練 Agent 2026-06-28] 修復：未知錯誤也自動重試一次
      if (_retryCount < 1) {
        _retryCount++;
        onShowError?.call('發生錯誤，正在自動重試...');
        await Future.delayed(const Duration(seconds: 2));
        await sendMessage(imagePath: imagePath);
        return;
      }
      _retryCount = 0;
      final message = '發生錯誤: $e';
      onShowError?.call(message);
      await appendLocalSystemMessage('$message\n\n我先保留這次對話，你可以調整設定後重試。');
    }
  }

  // [以利沙 P0 修復十三輪 2026-06-27] NLU Agent 切換偵測
  // 偵測「我想找 XXX」、「換成 XXX」等，返回 companion ID；找不到回傳 null
  Future<String?> _tryDetectCompanionSwitch(String text) async {
    // 模糊換夥伴偵測（不需要具體名字）
    const fuzzySwitch = [
      '換個夥伴', '換一個夥伴', '換夥伴', '換個人幫我', '換人幫我', '換個 AI',
      // [以利沙 P0 修復十七輪 2026-06-27] 擴充觸發詞庫
      '找另一位', '找其他夥伴', '找別的夥伴', '換一位', '換另一位',
      '切換夥伴', '換個助手', '讓別人幫我',
      '換人看看', '找另一個 AI', '找其他 AI', '找別人',
    ];
    if (fuzzySwitch.any((k) => text.contains(k))) {
      _pendingCompanionPickerRequest = true;
      notifyListeners();
      return null; // UI 層監聽 _pendingCompanionPickerRequest 並顯示選擇器
    }
    // [教練 Agent 2026-08-17 使用者 指示] 名字匹配整段移除——
    // 使用者會打錯字，且「嗨原生 Agent」+「幫我」這種自然稱呼會誤觸發
    // 換人偵測（訊息被彈選擇器攔走、甚至被吞掉）。
    // 要換人請用模糊觸發詞（換夥伴/換人幫我…）或直接點選擇器按鈕。
    return null;
  }

  // [以利沙 P0 修復十三輪 2026-06-27] 切換 companion 並顯示確認訊息
  Future<void> _switchToCompanion(
    String companionId,
    String originalText,
  ) async {
    // [以利沙 P0 修復十九輪 2026-06-27] 記錄前一位 companion，供跨 Agent 記憶橋接使用
    _prevCompanionId = _activeCompanion?.id;
    try {
      await CompanionStore().setActive(companionId);
      final companion = CompanionStore().getById(companionId);
      final name = companion?.name ?? '夥伴';
      _activeCompanion = companion;
      // 先記錄使用者訊息
      final conv = _currentConversation;
      if (conv != null) {
        final userMsg = Message(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          role: 'user',
          content: originalText,
          timestamp: DateTime.now(),
          // [2026-08-27 共視修復] 靜默——Blue：藍色切換條已記錄切換，
          // 「（切換夥伴）」空泡泡視覺多餘，兩頁都不顯示。
          metadata: {'silent': true, 'kind': 'companion_switch_trigger'},
        );
        // [2026-08-27 共視修復] 不再改寫 conversation.companionId——
        // 對話是多人格共視容器（切夥伴續聊＝常態操作），
        // 若把 companionId 蓋成最新夥伴，換回原夥伴時列表過濾掉這個對話＝「對話消失」。
        // 發言者由每則訊息的 speakerId 記錄（頭像已正確顯示）。
        _currentConversation = conv.copyWith(
          messages: [...conv.messages, userMsg],
          updatedAt: DateTime.now(),
        );
        await ConversationStore.save(_currentConversation!);
        notifyListeners();
      }
      // [以利沙 P0 修復十四輪 2026-06-27] 切換時加入交接簡報
      // [教練 Agent 2026-08-17 使用者 微調] 對話泡泡只顯示一行「已切換到 XXX」——
      // 交接脈絡內文太佔版面。完整脈絡仍走 _pendingHandoffNote 注入
      // 給新夥伴的 system prompt（新夥伴照樣知道前情，版面乾淨）。
      final handoffNote = await _buildHandoffContext(
        _currentConversation?.messages ?? [],
      );
      await appendLocalSystemMessage(
        '✅ 已切換夥伴為 $name',
        metadata: {
          'kind': 'companion_switch',
          'toCompanionId': companionId,
          'fromCompanionId': _prevCompanionId,
        },
      );
      // [以利沙 P0 修復十七輪 2026-06-27] 改為注入 system prompt 而非 conversation history
      // 只保存 handoffContext，下次 sendMessage 時才注入（只注入一次）
      // [2026-08-27 共視修復] 多 Agent 共事認知——對話中出現其他人格的
    // 發言是「切換夥伴」造成，不是你口誤、不是幻覺。你要知道：
    // 這是兩個以上 AI 與人類一起看同一件事的共視對話。
    _pendingHandoffNote = '使用者剛從上一位夥伴切換過來。$handoffNote '
        '重要：這是一個多位 Agent 共同參與的對話——對話歷史中風格不同的發言'
        '來自其他夥伴（不是你說的，也不是你口誤）。請接續協助使用者，'
        '用你自己的名字與人格回應，也可以參考前面夥伴的觀點。';
    } catch (e) {
      developer.log(
        '[ChatController] _switchToCompanion failed: $e',
        name: 'ChatController',
      );
      await appendLocalSystemMessage('切換夥伴時發生問題，請稍後再試。');
    }
    notifyListeners();
  }

  // [以利沙 第十六輪修復 2026-06-27] public wrapper，供 UI 層呼叫
  Future<void> switchToCompanionByRequest(
    String companionId,
    String text,
  ) async {
    await _switchToCompanion(companionId, text);
  }

  // ════════════════════════════════════════════════════════════════
  // [以利沙 P1 修復十五輪 2026-06-27]
  // [以利沙 P0 修復十九輪 2026-06-27] 改為 async，加入跨 Agent 記憶橋接；截斷字數 30→80
  // ════════════════════════════════════════════════════════════════
  Future<String> _buildHandoffContext(List<Message> messages) async {
    final userMsgs = messages.where((m) => m.role == 'user').toList();
    if (userMsgs.isEmpty) return '';
    final recent = userMsgs.length > 3
        ? userMsgs.sublist(userMsgs.length - 3)
        : userMsgs;
    final recentUserMessages = recent
        .map(
          (m) => m.content.length > 80
              ? '${m.content.substring(0, 80)}...'
              : m.content,
        )
        .toList();
    final summary = recentUserMessages.join('、');
    final parts = <String>['📋 交接脈絡：使用者近期談到「$summary」'];
    // [以利沙 P0 修復十九輪 2026-06-27] 跨 Agent 記憶橋接：查詢前一位 companion 的相關記憶
    if (_prevCompanionId != null) {
      final crossMemories = await _secondBrainFileIndexStore.search(
        recentUserMessages.isNotEmpty ? recentUserMessages.first : '',
        agentId: _prevCompanionId,
        limit: 3,
      );
      if (crossMemories.isNotEmpty) {
        final memTitles = crossMemories.map((m) => m.title).join('、');
        parts.add('📚 前一位夥伴留下的相關記憶：$memTitles');
      }
    }
    return '\n\n${parts.join('\n')}';
  }

  // ════════════════════════════════════════════════════════════════
  // executeBridgeAction — 主方法（原 _executeBridgeAction）
  // [以利沙 Sprint 8 Step 6 2026-06-24]
  // ════════════════════════════════════════════════════════════════

  // [以利沙 Sprint 8 Step 6 2026-06-24]
  Future<void> executeBridgeAction(
    BridgeAction action, {
    String? messageId,
    int? actionIndex,
    bool confirmed = false,
    BridgeActionExecutionOverride executionOverride =
        BridgeActionExecutionOverride.none,
    Future<void> Function(BridgeActionResult result)? onCompleted,
  }) async {
    _isLoading = true;
    _thoughtStage = AgentActivityStage.bridge;
    _activeBridgeActionLabel = bridgeInsightLabel(action);
    _lastBridgeActionLabel = _activeBridgeActionLabel;
    // [以利沙 P2 UI trace 合併 2026-06-26] 方法起始時合併，保留前序使用者記憶
    final bridgeTrace1 = bridgeSecondBrainTrace(action);
    _secondBrainTrace = SecondBrainTrace(
      agentName: _secondBrainTrace?.agentName ?? bridgeTrace1.agentName,
      recalledMemories: [
        ...(_secondBrainTrace?.recalledMemories ?? []),
        ...bridgeTrace1.recalledMemories,
      ],
      newInsights: [
        ...(_secondBrainTrace?.newInsights ?? []),
        ...bridgeTrace1.newInsights,
      ],
      outputs: bridgeTrace1.outputs,
      associations: [
        ...(_secondBrainTrace?.associations ?? []),
        ...bridgeTrace1.associations,
      ],
    );
    _thoughtTelemetry = AgentActivityTelemetry(
      messages: _currentConversation?.messages.length ?? 0,
      chars:
          _currentConversation?.messages.fold<int>(
            0,
            (total, message) => total + message.content.length,
          ) ??
          0,
      bridgeActions: 1,
    );
    notifyListeners();
    startThoughtPulse();
    if (messageId != null && actionIndex != null) {
      await updateBridgeActionStatus(
        messageId,
        actionIndex,
        BridgeActionRunStatus.running,
        statusMessage: '執行中...',
      );
    }

    final type = action.type.legacyType;
    onShowBridgeResultSnackBar?.call(
      BridgeActionResult(
        status: BridgeActionStatus.completed,
        message: '正在${bridgeActionLabel(type)}...',
        metadata: {'_snackOnly': true, 'type': type},
      ),
    );

    try {
      final result = await _bridgeActionExecutor.execute(
        action,
        confirmed: confirmed || action.requiresConfirmation,
        executionOverride: executionOverride,
      );
      // [以利沙 P2 UI trace 合併 2026-06-26] 執行完成後合併，保留前序使用者記憶
      final bridgeTrace2 = bridgeSecondBrainTrace(action, result: result);
      _secondBrainTrace = SecondBrainTrace(
        agentName: _secondBrainTrace?.agentName ?? bridgeTrace2.agentName,
        recalledMemories: [
          ...(_secondBrainTrace?.recalledMemories ?? []),
          ...bridgeTrace2.recalledMemories,
        ],
        newInsights: [
          ...(_secondBrainTrace?.newInsights ?? []),
          ...bridgeTrace2.newInsights,
        ],
        outputs: bridgeTrace2.outputs,
        associations: [
          ...(_secondBrainTrace?.associations ?? []),
          ...bridgeTrace2.associations,
        ],
      );
      _lastBridgeActionLabel = bridgeInsightLabelForResult(action, result);
      notifyListeners();

      if (result.status == BridgeActionStatus.completed) {
        if (messageId != null && actionIndex != null) {
          await updateBridgeActionStatus(
            messageId,
            actionIndex,
            BridgeActionRunStatus.completed,
            statusMessage: bridgeResultStatusMessage(result),
            requiresConfirmation: false,
          );
        }
        await appendBridgeResultMessage(result);
        // [以利沙 P0 修復 2026-06-27] 橋樑完成結果通用寫入 Second Brain
        // 讓跨輪對話記得橋樑執行的摘要，不限 web_search kind
        final kind = result.metadata?['kind']?.toString() ?? action.type.name;
        if (kind != 'web_search' && // web_search 已由 indexBrowseResult 處理
            result.message.isNotEmpty &&
            _currentConversation != null) {
          final now = DateTime.now();
          final actionLabel = bridgeActionLabel(action.type.legacyType);
          await _secondBrainFileIndexStore.upsert(
            SecondBrainFileEntry(
              id: 'bridge-${action.type.name}-${_currentConversation!.id}-${now.millisecondsSinceEpoch}',
              title: '橋樑結果：$actionLabel',
              path:
                  'local://bridge/${action.type.name}/${_currentConversation!.id}',
              room: SecondBrainRoom.bridges,
              summary:
                  '$actionLabel橋樑執行完成。任務：${action.prompt.trim().isNotEmpty ? action.prompt.trim() : "（無描述）"}',
              contentDigest: '橋樑類型：$actionLabel。執行時間：${now.toIso8601String()}。',
              contentExcerpt: compactIndexExcerpt(result.message),
              tags: ['橋樑結果', actionLabel, action.type.name],
              keywords: [actionLabel, action.type.name, action.prompt.trim()],
              indexedAt: now,
              trustScore: 72,
              agentId: _activeCompanion?.id, // [以利沙 P0 修復十八輪 2026-06-27]
            ),
          );
        }
        if (onCompleted != null) {
          await onCompleted(result);
        }
      } else if (result.status == BridgeActionStatus.needsConfirmation &&
          messageId != null &&
          actionIndex != null) {
        await updateBridgeActionStatus(
          messageId,
          actionIndex,
          BridgeActionRunStatus.pending,
          statusMessage: bridgeResultStatusMessage(result),
          requiresConfirmation: true,
        );
      } else if (messageId != null && actionIndex != null) {
        await updateBridgeActionStatus(
          messageId,
          actionIndex,
          BridgeActionRunStatus.failed,
          statusMessage: bridgeResultStatusMessage(result),
          requiresConfirmation: false,
        );
      }

      if (result.status == BridgeActionStatus.needsProvider) {
        // [以利沙 Capability Advisor 2026-06-25]
        await handleCapabilityGapWithAdvisor(
          result: result,
          bridgeAction: action,
        );
      }

      if (result.status != BridgeActionStatus.needsProvider) {
        onShowBridgeResultSnackBar?.call(result);
      }
      syncBridgeEvidenceToCompanion(result);
    } catch (error) {
      final result = BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: '橋樑動作執行失敗：$error',
        metadata: {
          'type': action.type.legacyType,
          'kind': 'bridge_execution_error',
          'prompt': action.prompt,
          'provider': action.provider,
          'error': error.toString(),
        },
      );
      // [以利沙 P2 UI trace 合併 2026-06-26] catch 錯誤時合併，保留前序使用者記憶
      final bridgeTrace3 = bridgeSecondBrainTrace(action, result: result);
      _secondBrainTrace = SecondBrainTrace(
        agentName: _secondBrainTrace?.agentName ?? bridgeTrace3.agentName,
        recalledMemories: [
          ...(_secondBrainTrace?.recalledMemories ?? []),
          ...bridgeTrace3.recalledMemories,
        ],
        newInsights: [
          ...(_secondBrainTrace?.newInsights ?? []),
          ...bridgeTrace3.newInsights,
        ],
        outputs: bridgeTrace3.outputs,
        associations: [
          ...(_secondBrainTrace?.associations ?? []),
          ...bridgeTrace3.associations,
        ],
      );
      _lastBridgeActionLabel = bridgeInsightLabelForResult(action, result);
      notifyListeners();
      if (messageId != null && actionIndex != null) {
        await updateBridgeActionStatus(
          messageId,
          actionIndex,
          BridgeActionRunStatus.failed,
          statusMessage: bridgeResultStatusMessage(result),
          requiresConfirmation: false,
        );
      }
      onShowBridgeResultSnackBar?.call(result);
      syncBridgeEvidenceToCompanion(result);
    } finally {
      stopThinking();
    }
  }

  // ── Dispose ───────────────────────────────────────

  /// [以利沙 Sprint 8 Step 5 2026-06-24]
  /// 釋放 Timer 資源。
  @override
  void dispose() {
    _memoryFlashTimer?.cancel();
    _thoughtPulseTimer?.cancel();
    super.dispose();
  }
}
