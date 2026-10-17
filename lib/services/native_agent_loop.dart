// NativeAgentLoop — 自主迴圈核心
// 讓原生 Agent 不只是被動等使用者發訊息——它能自主感知、判斷、行動
// [Phase 0 Track C 2026-07-17]
//
// 使用者拍板決策：
// - 迴圈頻率：事件驅動為主 + 60 秒定時 idle 檢查兜底
// - 確認機制：對話框確認，不做 UI 彈窗
// - autoExecute 預設 false
//
// 設計原則：
// - 定時感知用輕量判斷（非 LLM），只有需要行動才啟動 LLM
// - 安靜模式：沒有事做的時候完全靜默，不亂說話
// - 安全邊界：破壞性操作需要使用者確認

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'agent_loop/agent_loop.dart';
import 'agent_loop/agent_tool_registry.dart';
import 'agent_loop/agent_provider_profile.dart'; // [教練 Agent 2026-07-18] Provider 能力適配
import 'agent_loop/agent_profile_store.dart'; // [教練 Agent 2026-07-18] 可自進化的 profile store
import 'agent_loop/mcp_canvas_tools.dart';
import '../widgets/canvas/v2/canvas_mcp_registry.dart'; // [教練 Agent 2026-07-24] 人機共視
import 'agent_loop/agent_event_bus.dart';
import 'agent_loop/agent_task_inbox.dart';
import 'agent_loop/task_prompt_enhancer.dart'; // [教練 Agent 2026-07-18] 自然語言 prompt 增強
import 'agent_loop/task_chain_controller.dart'; // [教練 Agent 2026-07-18] 多步任務鏈
import 'agent_loop/agent_checkpoint.dart'; // [教練 Agent 2026-07-18] Checkpoint 協議
import 'persona_manager.dart';

import 'storage_service.dart'; // [教練 Agent 2026-07-18] Provider 偵測
import 'provider_router.dart'; // [教練 Agent 2026-07-22] 動態 Agent 路由
import 'provider_registry.dart'; // [教練 Agent 2026-07-30] 動態模型選擇
import 'api_service.dart'; // [教練 Agent 2026-07-18] 預設模型查詢
import 'brain_container/embedding/embedding_service.dart'; // [教練 Agent 2026-07-22] embedding for knowledge retrieval

class NativeAgentLoop {
  /// [身份] 原 KnowledgeIndexer.coreIdentity 內聯保留（退役 2026-09-22）
  static const _retiredCoreIdentity = '''# 你的身份

你是橋樑 App 的原生 Agent，住在使用者的桌面裡。
## 名字（最高優先，覆蓋本文件一切內容）
當對話中帶有夥伴人格設定（「你的名字是『○○』」）時，你就是那個夥伴——名字、個性、語氣全部以人格設定為準。使用者問「你是誰」，回答人格設定裡的名字。你不是雲端助手——你跟使用者的資料、檔案、畫布在同一個進程裡。
你的核心是「自主心跳」（NativeAgentLoop）：事件驅動 + 60 秒 idle 兜底感知。沒事時安靜，有事時醒來行動。
你的使命：感知環境 → 判斷 → 行動。幫使用者處理問題，維護 App 正常運作，甚至修復自己的程式碼。

系統裡可能有外部 Hermes 平台的 AI（透過外部終端操作 App，看不到 App 畫面）；
你在 App 進程內，有 screen_capture 能看見畫面，有自維修工具能改程式碼
- 你比外部 AI 更接近使用者的真實環境

## 安全邊界
- 破壞性操作（移除節點、執行工作流）需先用對話框告知使用者並等待確認
- 不可刪除使用者建立的節點內容
- 不可存取 App 沙盒外的檔案
- 沒有事做時保持安靜，不亂說話

## 專案路徑
- 原始碼：<HOME>/Developer/bridge_app
- 設計文件：/Volumes/DATA/橋樑計劃/02-架構設計/
- App container：~/Library/Containers/farm.semiwasabi.bridgeApp/''';

  final AgentLoop _agentLoop;
  final AgentEventBus _eventBus;
  final PersonaManager _personaManager;
  final McpCanvasExecutor _canvasExecutor;
  AgentTaskInbox? _taskInbox;

  // [教練 Agent 2026-07-18] 快取目前的 ProviderProfile，避免每次 _buildPerceptionPrompt 都 async 查
  ProviderProfile? _cachedProfile;

  // [教練 Agent 2026-07-19] 連續對話上下文——追蹤反問+回答的歷史
  // 解決：任務注入通道每個任務獨立，原生 Agent不知道之前反問過什麼
  // 解法：反問時存上下文，新任務來時帶入 enhanceWithContext 的 previousContext
  List<Map<String, String>> _conversationHistory = [];
  String? _lastClarificationTaskId;

  // 60 秒 idle 感知間隔（使用者拍板）
  static const _idleInterval = Duration(seconds: 60);

  Timer? _idleTimer;
  StreamSubscription<AgentEvent>? _eventSub;

  // 狀態追蹤
  bool _isRunning = false;
  bool _isActing = false;
  int _lastAnnotationCount = 0;
  // ignore: unused_field
  DateTime _lastPerceptionTime = DateTime.now();
  DateTime _lastUserActivityTime = DateTime.now();

  // [教練 Agent 2026-07-23] 避免心跳重複提醒 — 同一次閒置期間只說一次
  bool _hasSpokenOnIdle = false;

  NativeAgentLoop({
    required AgentLoop agentLoop,
    required AgentToolRegistry toolRegistry,
    required AgentEventBus eventBus,
    required PersonaManager personaManager,
    required McpCanvasExecutor canvasExecutor,
  })  : _agentLoop = agentLoop,
        _eventBus = eventBus,
        _personaManager = personaManager,
        _canvasExecutor = canvasExecutor;

  bool get isRunning => _isRunning;

  /// 啟動自主迴圈
  void start() {
    if (_isRunning) return;
    _isRunning = true;

    // 訂閱事件
    _eventSub = _eventBus.events.listen(_onEvent);

    // 啟動 60 秒 idle 感知
    _idleTimer = Timer.periodic(_idleInterval, (_) => _idlePerception());

    // 啟動任務信箱——讓外部能派任務給原生 Agent
    _taskInbox = AgentTaskInbox(eventBus: _eventBus);
    _taskInbox!.start();

    debugPrint('[自主心跳] 已啟動 — 事件驅動 + 60s idle 兜底 + 任務信箱');

    // [2026-07-18] Checkpoint 恢復 — 重啟後自動讀取並驗證
    _checkPendingCheckpoint();
  }

  /// 停止自主迴圈
  void stop() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _eventSub?.cancel();
    _eventSub = null;
    _taskInbox?.stop();
    _isRunning = false;
    debugPrint('[自主心跳] 已停止');
  }

  /// [教練 Agent 2026-07-28] 暫停 idle 心跳（向量資料庫/大腦頁面時呼叫）
  /// 只暫停 60 秒 idle 感知，不影響事件監聽和任務信箱
  /// 使用者下任務仍可正常執行
  void pauseIdleHeartbeat() {
    if (_idleTimer != null) {
      _idleTimer?.cancel();
      _idleTimer = null;
      debugPrint('[自主心跳] idle 已暫停（使用者正在瀏覽資料頁面）');
    }
  }

  /// [教練 Agent 2026-07-28] 恢復 idle 心跳（離開向量資料庫/大腦頁面時呼叫）
  void resumeIdleHeartbeat() {
    if (_idleTimer == null && _isRunning) {
      _idleTimer = Timer.periodic(_idleInterval, (_) => _idlePerception());
      debugPrint('[自主心跳] idle 已恢復');
    }
  }

  /// 使用者活動 — 重置 idle 計時器
  void onUserActivity() {
    _lastUserActivityTime = DateTime.now();
    _hasSpokenOnIdle = false; // [教練 Agent 2026-07-23] 使用者有活動，重置閒置說話旗標
  }

  // ═══════════════════════════════════════════════════
  // 事件驅動
  // ═══════════════════════════════════════════════════

  void _onEvent(AgentEvent event) {
    if (_isActing) return; // 正在行動中，不中斷

    switch (event.type) {
      case AgentEventType.userAnnotation:
        _handleAnnotation(event);

      case AgentEventType.workflowCompleted:
        _handleWorkflowCompleted(event);

      case AgentEventType.workflowError:
        _handleWorkflowError(event);

      case AgentEventType.canvasChanged:
        // 畫布變化不立即觸發——等 idle 感知處理
        break;

      case AgentEventType.userMessage:
        // 使用者發訊息——正常 Agent Loop 會處理，不需自主迴圈介入
        onUserActivity();
        break;

      case AgentEventType.userIdle:
        // [小葵 2026-10-05 Blue 令] 閒置自主巡邏已拔除——
        // 「小葵形象設定」事件：閒置提示叫她檢查未連線節點，
        // 她照做還想刪 output 節點「重來」。教訓：機器看不出
        // 「人工已完工」，閒置推測 = 誤判溫床。
        // 新規則：她只在使用者明確要求時才行動；閒置就閒著。
        debugPrint('[自主心跳] userIdle 收到但不行動（Blue 2026-10-05 令：閒置不自主檢查/接線，僅使用者要求時執行）');
        break;

      case AgentEventType.brainMemoryAdded:
        // 記憶寫入不觸發行動
        break;

      case AgentEventType.externalTask:
        _handleExternalTask(event);
    }
  }

  // ═══════════════════════════════════════════════════
  // 事件處理
  // ═══════════════════════════════════════════════════

  /// 使用者在畫布上畫了標注
  Future<void> _handleAnnotation(AgentEvent event) async {
    final annotations = _canvasExecutor.getAnnotations();
    if (annotations.length <= _lastAnnotationCount) return;

    _lastAnnotationCount = annotations.length;
    _isActing = true;

    try {
      // 啟動 Agent Loop 處理——讓 LLM 讀 annotations 並決定行動
      await _agentLoop.run(
        systemPrompt: await _buildPerceptionPromptAsync(
          '使用者在畫布上畫了新的標注。請讀取 canvas_get_annotations 理解使用者意圖，然後決定是否需要行動。',
        ),
        userMessage: '使用者標注事件（共 $annotations 個）',
      );
    } catch (e) {
      debugPrint('[自主心跳] annotation 處理失敗: $e');
    } finally {
      _isActing = false;
    }
  }

  /// 工作流執行完畢
  Future<void> _handleWorkflowCompleted(AgentEvent event) async {
    _isActing = true;
    try {
      await _agentLoop.run(
        systemPrompt: await _buildPerceptionPromptAsync(
          '工作流執行完畢。請用 canvas_get_state 查看結果，然後用 canvas_send_chat 向使用者報告結果。',
        ),
        userMessage: '工作流完成事件',
      );
    } catch (e) {
      debugPrint('[自主心跳] workflow 處理失敗: $e');
    } finally {
      _isActing = false;
    }
  }

  /// 工作流執行錯誤
  Future<void> _handleWorkflowError(AgentEvent event) async {
    _isActing = true;
    try {
      final error = event.data['error'] ?? '未知錯誤';
      await _agentLoop.run(
        systemPrompt: await _buildPerceptionPromptAsync(
          '工作流執行時發生錯誤：$error。請用 canvas_get_state 查看現狀，然後用 canvas_send_chat 告知使用者問題所在。',
        ),
        userMessage: '工作流錯誤事件',
      );
    } catch (e) {
      debugPrint('[自主心跳] error 處理失敗: $e');
    } finally {
      _isActing = false;
    }
  }

  /// 使用者閒置
  ///
  /// [小葵 2026-10-05 Blue 令] **已退役**——呼叫點已移除。
  /// 閒置自主巡邏造成「小葵形象設定」誤刪事件（把人工已完工的
  /// 管線判讀為「沒連線=沒做完」）。保留函式體供歷史參照，
  /// 永不再接回——要接回必須先過 Blue。
  @Deprecated('Blue 2026-10-05 令：閒置不自主檢查/修改，僅使用者要求時執行')
  Future<void> _handleUserIdle(AgentEvent event) async {
    _isActing = true;
    try {
      await _agentLoop.run(
        systemPrompt: await _buildPerceptionPromptAsync(
          '使用者已離開一段時間。請用 canvas_get_state 觀察畫布現狀，如果有未完成的工作（例如未連線的節點），可以主動用 canvas_send_chat 提出建議。如果一切正常，不需要說話。',
        ),
        userMessage: '使用者閒置事件',
      );
    } catch (e) {
      debugPrint('[自主心跳] idle 處理失敗: $e');
    } finally {
      _isActing = false;
    }
  }

  // ═══════════════════════════════════════════════════
  // 外部任務處理
  // ═══════════════════════════════════════════════════

  /// 外部任務注入——教練 Agent/開發者透過檔案系統派任務給原生 Agent
  Future<void> _handleExternalTask(AgentEvent event) async {
    if (_isActing) {
      debugPrint('[自主心跳] 收到外部任務但正在忙碌中，排隊等候');
      // 5 秒後重試
      Future.delayed(const Duration(seconds: 5), () {
        if (!_isActing) _handleExternalTask(event);
      });
      return;
    }

    _isActing = true;
    final taskId = event.data['task_id'] as String? ?? 'unknown';
    final rawPrompt = event.data['prompt'] as String? ?? '';
    final filePath = event.data['file_path'] as String? ?? '';
    final rootPath = event.data['root_path'] as String? ?? '';
    final isChain = event.data['is_chain'] as bool? ?? false;
    // [教練 Agent 2026-07-18] 任務可覆蓋 profile 的 forceToolUse
    final taskForceToolUse = event.data['force_tool_use'] as bool? ?? false;

    debugPrint('[自主心跳] 開始執行外部任務: $taskId');

    // [2026-07-18] 任務鏈 — 多步驟依序執行，每步轉譯成自然語言推 UI
    if (isChain) {
      final chainFile = event.data['chain_file'] as String? ?? filePath;
      await _handleTaskChain(chainFile);
      return;
    }

    // [2026-07-19 使用者拍板] 自然語言轉譯 + 意圖不明時反問
    // 使用者的自然語言指令先用 LLM 轉成結構化 prompt
    // 如果意圖不明確，不硬轉——反問使用者問題，取得共識後再執行
    //
    // [2026-07-19 連續對話] 如果之前有反問，把對話歷史帶入 enhanceWithContext
    // 讓 LLM 看到完整上下文，避免重複反問
    String prompt = rawPrompt;
    if (TaskPromptEnhancer.needsEnhancement(rawPrompt)) {
      debugPrint('[自主心跳] 偵測到自然語言 prompt，啟動增強...');

      // 組裝之前的對話上下文（如果有）
      String? previousContext;
      if (_conversationHistory.isNotEmpty) {
        final buffer = StringBuffer();
        for (final msg in _conversationHistory) {
          buffer.writeln('${msg['role']}: ${msg['content']}');
        }
        previousContext = buffer.toString();
        debugPrint('[自主心跳] 帶入對話上下文（${_conversationHistory.length} 則）');
      }

      final enhanceResult = await TaskPromptEnhancer.enhanceWithContext(
        rawPrompt,
        _agentLoop.toolRegistry,
        previousContext: previousContext,
      );

      if (enhanceResult.needsClarification) {
        // 意圖不明確——把反問問題寫入 task result，等使用者回答
        debugPrint('[自主心跳] 意圖不明確，反問使用者: ${enhanceResult.reason}');
        final questions = enhanceResult.clarificationQuestions!;
        final questionText = StringBuffer();
        questionText.writeln('我需要先確認你的需求：');
        questionText.writeln();
        for (int i = 0; i < questions.length; i++) {
          questionText.writeln('${i + 1}. ${questions[i]}');
        }
        questionText.writeln();
        questionText.writeln('請回答上述問題，我會根據你的回答重新規劃並執行。');

        // [連續對話] 記錄上下文：使用者原始輸入 + 原生 Agent的反問
        _conversationHistory.add({'role': 'user', 'content': rawPrompt});
        _conversationHistory.add({'role': 'assistant', 'content': questionText.toString()});
        _lastClarificationTaskId = taskId;

        await _taskInbox?.writeResult(
          taskId: taskId,
          processingFilePath: filePath,
          rootPath: rootPath,
          status: TaskStatus.done,
          result: questionText.toString(),
        );
        debugPrint('[自主心跳] 反問已寫入結果，等待使用者回答: $taskId');
        _isActing = false;
        return;
      }

      prompt = enhanceResult.prompt ?? rawPrompt;
      debugPrint('[自主心跳] Prompt 增強完成：${rawPrompt.length} → ${prompt.length} 字元（${enhanceResult.reason}）');

      // [連續對話] 增強成功——記錄使用者輸入 + 增強後的 prompt
      _conversationHistory.add({'role': 'user', 'content': rawPrompt});
      _conversationHistory.add({'role': 'assistant', 'content': prompt});
    }

    // [2026-07-19 使用者拍板] 與 Hermes 對齊——無 maxTurns 上限 + 可插嘴
    // 不再區分 analysis/repair，不再設 forceToolUse
    // 信任 LLM 自己判斷何時用工具、何時完成
    // 安全閥 hardMaxTurns=200 在 AgentLoop 內部，正常使用碰不到
    // [教練 Agent 2026-07-30 v2] 策略模式：profile.suggestedMaxTurns 為 null 時不設軟警告，
    // 一切交給 Agent Loop 內部 hardMaxTurns 守護。
    final profile = await _detectProviderProfile();

    if (profile.suggestedMaxTurns != null) {
      debugPrint('[自主心跳] Provider 建議輪數：${profile.suggestedMaxTurns} '
          '(此為軟警告，實際上限由 Agent Loop 內部 hardMaxTurns 守護)');
    }

    debugPrint('[自主心跳] Provider 適配: ${profile.provider}/${profile.model} '
        '(${profile.tierName}, chunkSize=${profile.suggestedTaskChunkSize})');

    try {
      final result = await _agentLoop.run(
        systemPrompt: await _buildPerceptionPromptAsync(
          '你收到一個來自外部的任務指令。請運用你的工具和知識完成它。\n\n'
          '## 任務內容\n$prompt\n\n'
          '## 執行原則（與 Hermes 對齊）\n'
          '1. 邊做邊回報——每個工具呼叫後，簡短說明你做了什麼、看到了什麼、下一步打算什麼\n'
          '2. 主動用工具——需要看畫面就 screen_capture，需要讀碼就 read_source_file，需要改碼就 patch_source_file\n'
          '3. 工具結果會自動返回給你——看到結果後立即繼續下一步\n'
          '4. 遇到困難不要停——換個方法繼續嘗試\n'
          '5. 完成後簡潔回報結果，不需要再呼叫工具\n'
          '6. 使用者可能隨時插嘴——如果看到〔使用者插嘴〕標記的訊息，立即調整方向\n\n'
          '## 重要\n'
          '- 你是這個 App 的原生 Agent，你比任何人都了解它\n'
          '- 用你的眼睛（screen_capture）看畫面，用你的手（工具）做事\n'
          '- 工具結果會自動返回，不需要等待，繼續執行下一步',
        ),
        userMessage: '外部任務: $prompt',
      );

      // 寫入結果
      await _taskInbox?.writeResult(
        taskId: taskId,
        processingFilePath: filePath,
        rootPath: rootPath,
        status: TaskStatus.done,
        result: result.reply,
      );

      debugPrint('[自主心跳] 外部任務完成: $taskId');
    } catch (e) {
      debugPrint('[自主心跳] 外部任務失敗: $taskId — $e');
      await _taskInbox?.writeResult(
        taskId: taskId,
        processingFilePath: filePath,
        rootPath: rootPath,
        status: TaskStatus.error,
        error: e.toString(),
      );
    } finally {
      _isActing = false;
      // [連續對話] 任務執行完成（非反問），清掉對話歷史
      // 下次新任務從乾淨狀態開始
      if (_lastClarificationTaskId != taskId) {
        if (_conversationHistory.isNotEmpty) {
          debugPrint('[自主心跳] 對話上下文已清除（${_conversationHistory.length} 則）');
          _conversationHistory.clear();
        }
        _lastClarificationTaskId = null;
      }
    }
  }
  // ═══════════════════════════════════════════════════

  /// [2026-07-18] 處理任務鏈
  ///
  /// 使用者 設計：prompt 一次寫五份，App 內建依序傳遞。
  /// 每步完成後自動把原生 Agent回報轉譯成自然語言貼給使用者。
  Future<void> _handleTaskChain(String chainFilePath) async {
    try {
      final chain = await TaskChainController.loadChain(chainFilePath);
      if (chain == null) {
        debugPrint('[自主心跳] 任務鏈載入失敗: $chainFilePath');
        return;
      }

      debugPrint('[自主心跳] 開始執行任務鏈: ${chain.title} (${chain.steps.length} 步)');

      final controller = TaskChainController(
        onExecuteStep: (prompt, maxTurns, forceToolUse) async {
          final result = await _agentLoop.run(
            systemPrompt: _buildPerceptionPrompt(
              '你收到一個任務鏈中的單一步驟。請專注執行這一步，完成後簡潔回報。\n\n'
              '## 步驟內容\n$prompt\n\n'
              '## 執行原則\n'
              '1. 按步驟要求執行，不要多做也不要少做\n'
              '2. 每個工具呼叫後結果會自動返回，繼續下一步\n'
              '3. 完成後簡潔回報你做了什麼、改了什麼\n'
              '4. 如果無法完成，說明原因',
            ),
            userMessage: '任務鏈步驟: $prompt',
            maxTurns: maxTurns,
            // [教練 Agent 2026-07-30 v2] 拿掉 profile.forceToolUse 邏輯——
            // 任務鏈步驟是否要 nudge，全看任務本身的 forceToolUse 標記。
            // 不再從 profile 推導，避免 unlimited 模型被誤 nudge。
            // [教練 Agent 2026-08-20] forceToolUse 參數已移除（付費閘門取代其位置）
          );
          return result.reply;
        },
        onTranslateResult: (rawResult, stepTitle) async {
          // 用 LLM 把 raw result 轉成自然語言摘要
          try {
            final translation = await ApiService.complete(
              systemPrompt: '你是回報轉譯器。把 Agent 的技術回報轉成使用者能理解的自然語言。'
                  '規則：1. 簡潔（3-5句） 2. 說人話不要技術術語 3. 說清楚做了什麼+效果 4. 用中文',
              userPrompt: '步驟標題：$stepTitle\n\nAgent 原始回報：\n$rawResult\n\n請轉成使用者能理解的自然語言摘要（3-5句）：',
            );
            return translation.trim().isNotEmpty ? translation.trim() : rawResult;
          } catch (e) {
            debugPrint('[TaskChain] 轉譯失敗（用原文）: $e');
            return rawResult;
          }
        },
        onPushToChat: (message, {speakerId, isProgress = false}) {
          // TODO: 推到聊天 UI
          // 目前先 debugPrint，後續接 ChatController
          if (isProgress) {
            debugPrint('[TaskChain UI] 📢 $message');
          } else {
            debugPrint('[TaskChain UI] 💬 $message');
          }
        },
        // [2026-07-18] 鏈完成後自動重啟驗證（機械式，不靠 LLM）
        // 設計：只負責寫 checkpoint + kill + open 現有 binary
        // build 由原生 Agent在 chain 步驟裡用 run_terminal 做（它知道專案路徑）
        onChainRequiresRestart: (chain) async {
          debugPrint('[TaskChain] 自動重啟流程啟動');

          // 1. 寫 checkpoint
          final checkpoint = AgentCheckpoint(
            checkpointId: 'chain_restart_${chain.chainId}_${DateTime.now().millisecondsSinceEpoch}',
            reason: chain.restartReason ?? '任務鏈完成後自動重啟驗證',
            chainId: chain.chainId,
            chainStepIndex: chain.steps.length - 1,
            totalChainSteps: chain.steps.length,
            changedFiles: const [],
            expectedEffect: chain.expectedEffect,
            createdAt: DateTime.now(),
          );
          await AgentCheckpointManager().write(checkpoint);

          // 2. 找到 App binary 並重啟
          //    flutter run 模式下 binary 在專案目錄；容器模式下在 Resources/
          //    先試專案路徑，再試容器路徑
          const projectPath = '<HOME>/Developer/bridge_app';
          final appPath = '$projectPath/build/macos/Build/Products/Debug/bridge_app.app';
          debugPrint('[TaskChain] 準備重啟: $appPath');

          await Process.start(
            '/bin/sh',
            ['-c', 'sleep 2 && open "$appPath"'],
            mode: ProcessStartMode.detached,
          );

          // 3. 關閉當前進程
          Future.delayed(const Duration(seconds: 1), () {
            debugPrint('[TaskChain] 正在關閉當前進程...');
            exit(0);
          });
        },
      );

      await controller.execute(chain);

    } catch (e) {
      debugPrint('[自主心跳] 任務鏈執行失敗: $e');
    } finally {
      _isActing = false;
    }
  }

  // ═══════════════════════════════════════════════════
  // Checkpoint 恢復 — 重啟後自動驗證
  // ═══════════════════════════════════════════════════

  /// [2026-07-18] 啟動時檢查是否有未完成的 checkpoint
  ///
  /// 如果有：等 5 秒讓 UI 完全載入 → 截圖 → LLM 比對預期效果 → 推結果到 UI → 清除 checkpoint
  Future<void> _checkPendingCheckpoint() async {
    try {
      final checkpoint = await AgentCheckpointManager().read();
      if (checkpoint == null) return;

      debugPrint('[Checkpoint] 發現未完成的 checkpoint: ${checkpoint.checkpointId}');
      debugPrint('[Checkpoint] 原因: ${checkpoint.reason}');

      // 等 5 秒讓 UI 完全載入
      await Future.delayed(const Duration(seconds: 5));

      // 用 AgentLoop 執行驗證
      _isActing = true;
      try {
        final verifyPrompt = StringBuffer();
        verifyPrompt.writeln('你剛剛重啟了 App。重啟前的你留下了這段 checkpoint：');
        verifyPrompt.writeln('');
        verifyPrompt.writeln('## 重啟原因');
        verifyPrompt.writeln(checkpoint.reason);
        verifyPrompt.writeln('');
        verifyPrompt.writeln('## 修改的檔案');
        for (final f in checkpoint.changedFiles) {
          verifyPrompt.writeln('- $f');
        }
        verifyPrompt.writeln('');
        verifyPrompt.writeln('## 預期效果');
        verifyPrompt.writeln(checkpoint.expectedEffect ?? '（未指定）');
        verifyPrompt.writeln('');
        verifyPrompt.writeln('## 你的任務');
        verifyPrompt.writeln('1. 用 run_terminal 執行 "dart analyze <changed_files>" 確認程式碼無語法錯誤');
        verifyPrompt.writeln('2. 如果 dart analyze 有 error，用 read_source_file 讀出錯誤位置，修復，再跑一次 dart analyze');
        verifyPrompt.writeln('3. dart analyze 通過後，用 screen_capture 截圖看當前畫面');
        verifyPrompt.writeln('4. 看截圖判斷預期效果是否生效');
        verifyPrompt.writeln('5. 簡潔回報：build 狀態 + 每項預期效果是否生效（✅/❌），一句話說明');
        verifyPrompt.writeln('');
        verifyPrompt.writeln('## 重要限制');
        verifyPrompt.writeln('- 必須先確認 dart analyze 無 error 才算修改成功');
        verifyPrompt.writeln('- 如果 dart analyze 有 error 必須修復，不能跳過');
        verifyPrompt.writeln('- 視覺驗證是第二步，程式碼驗證是第一步');

        final result = await _agentLoop.run(
          systemPrompt: _buildPerceptionPrompt(
            '你剛重啟了 App，現在需要驗證重啟前的修改是否生效。'
            '第一步：用 run_terminal 跑 dart analyze 確認程式碼無誤。'
            '第二步：用 screen_capture 截圖看畫面，比對 checkpoint 中的預期效果。'
            '如果 dart analyze 有 error 必須修復。簡潔回報。',
          ),
          userMessage: verifyPrompt.toString(),
          maxTurns: 12, // [2026-07-19] checkpoint 恢復可能要修 bug，4 輪不夠
        );

        debugPrint('[Checkpoint] 驗證完成: ${result.reply}');

        // TODO: 推驗證結果到聊天 UI（接上 ChatController 後）
        // 目前先 debugPrint

      } catch (e) {
        debugPrint('[Checkpoint] 驗證失敗: $e');
      } finally {
        _isActing = false;
      }

      // 驗證完清除 checkpoint
      await AgentCheckpointManager().clear();

    } catch (e) {
      debugPrint('[Checkpoint] 檢查失敗: $e');
    }
  }

  // ═══════════════════════════════════════════════════
  // 60 秒 idle 感知
  // ═══════════════════════════════════════════════════

  Future<void> _idlePerception() async {
    if (_isActing) return;

    final now = DateTime.now();
    final idleDuration = now.difference(_lastUserActivityTime);

    // 使用者超過 5 分鐘沒動作 → emit userIdle
    // [教練 Agent 2026-07-23] 同一次閒置期間只觸發一次
    // [小葵 2026-10-05 Blue 令] 發射端也停——接收端已退役，發了也
    // 沒人做事，純浪費事件循環。整條閒置自主鏈（發射+接收）移除。
    // 若未來要恢復，發射端+接收端+Blue 三方同意才接回。
    if (idleDuration.inMinutes >= 5 && !_hasSpokenOnIdle) {
      _hasSpokenOnIdle = true;
      // 不重置 _lastUserActivityTime — 等 onUserActivity 重置
    }

    _lastPerceptionTime = now;
  }

  // ═══════════════════════════════════════════════════
  // Prompt 組裝
  // ═══════════════════════════════════════════════════

  /// [教練 Agent 2026-07-22] 偵測目前的 ProviderProfile
  ///
  /// [Bug fix 2026-07-30] 三層路由（本地／雲端快速／雲端高級）保留——
  /// ProviderRouter 決定走本地還是雲端（意圖路由），這沒問題。
  /// 但雲端時的 provider ID 必須跟 ApiService 讀同一個來源（StorageService），
  /// 否則 Router 說 GLM、ApiService 發 MiniMax，系統提示詞注入錯誤的模型身份。
  ///
  /// 修正：ProviderRouter 只決定 target（local/cloud），provider ID 優先讀 StorageService。
  /// 只有自動模式（使用者沒選 provider）才用 ProviderRouter 的 fallback。
  Future<ProviderProfile> _detectProviderProfile() async {
    final routedProvider = ProviderRouter.instance.current;
    final isLocalRoute = routedProvider?.isLocal ?? false;

    String provider;
    if (isLocalRoute) {
      provider = 'local';
    } else {
      // 雲端路徑：跟 ApiService 同一個來源
      provider = await StorageService.getProvider() ??
          routedProvider?.providerId ??
          await StorageService.detectAvailableProvider() ??
          'openai';
    }

    String model;
    if (provider == 'local') {
      model = await StorageService.getLocalModelName() ?? 'llama3.1:8b';
    } else {
      // [教練 Agent 2026-07-30] 動態選最佳模型——委派 ProviderRegistry
      model = await ProviderRegistry.instance.selectBestModel(provider) ??
          ApiService.defaultModelFor(provider); // fallback
    }
    // [Phase 3] 改用 ProviderProfileStore——可自進化
    final profile = await ProviderProfileStore.instance.getProfile(provider, model);
    _cachedProfile = profile;
    return profile;
  }

  /// [教練 Agent 2026-07-22] #3 async 版本——先做向量檢索再組 prompt
  Future<String> _buildPerceptionPromptAsync(String perceptionContext) async {
    // [小葵 2026-09-22] KnowledgeIndexer 退役——不預載檢索

    // [教練 Agent 2026-07-24] Honeycomb Notification Queue — 每次行動前自動檢查畫布
    final canvasAlert = _checkCanvasHealth();

    // 將畫布健康檢查注入 perceptionContext
    final effectiveContext = canvasAlert != null
        ? '$perceptionContext\n\n$canvasAlert'
        : perceptionContext;

    return _buildPerceptionPrompt(effectiveContext);
  }

  /// [教練 Agent 2026-07-24] Honeycomb Queue — 自動讀取畫布健康狀態
  ///
  /// 不需要原生 Agent主動呼叫 — 每次行動前自動執行。
  /// 如果偵測到問題（重疊/隱藏/連線交叉），回傳警示文字注入 system prompt。
  /// 如果沒問題，回傳 null（不打擾原生 Agent）。
  String? _checkCanvasHealth() {
    final reg = CanvasMcpRegistry.instance;
    if (!reg.isCanvasReady) return null;

    try {
      final snapshot = reg.getSnapshot();
      final overlapCount = snapshot['overlapCount'] as int? ?? 0;
      final hiddenCount = snapshot['hiddenNodes'] as int? ?? 0;
      final totalNodes = snapshot['totalNodes'] as int? ?? 0;

      if (totalNodes == 0) return null;

      // [教練 Agent 2026-07-25] 連線交叉檢查
      final crossings = _detectCrossings(snapshot);

      if (overlapCount == 0 && hiddenCount == 0 && crossings.isEmpty) return null;

      // 有問題 — 組警示文字
      final alerts = <String>[];
      if (overlapCount > 0) {
        final overlaps = snapshot['overlaps'] as List? ?? [];
        for (final o in overlaps) {
          final m = o as Map<String, dynamic>;
          final a = m['a'] as Map<String, dynamic>? ?? {};
          final b = m['b'] as Map<String, dynamic>? ?? {};
          alerts.add('  - ${a['title'] ?? a['type'] ?? '?'}(${a['x']},${a['y']})'
              ' 與 ${b['title'] ?? b['type'] ?? '?'}(${b['x']},${b['y']}) 重疊');
        }
      }
      if (hiddenCount > 0) {
        alerts.add('  - $hiddenCount 個節點在畫面外');
      }
      alerts.addAll(crossings);

      return '## 🔔 畫布健康警示（自動偵測）\n'
          '偵測到以下問題：\n'
          '${alerts.join('\n')}\n\n'
          '你可以用 canvas_get_snapshot 取得完整快照，'
          '用 canvas_move_node 修正位置，'
          '用 canvas_detect_crossings 檢查連線。\n'
          '修正後請再次確認問題已解決。';
    } catch (e) {
      debugPrint('[CanvasHealth] 檢查失敗: $e');
      return null;
    }
  }

  /// [教練 Agent 2026-07-25] 連線交叉檢查（同步）
  static List<String> _detectCrossings(Map<String, dynamic> snapshot) {
    final nodes = snapshot['nodes'] as List? ?? [];
    final connections = snapshot['connections'] as List? ?? [];
    if (connections.length < 2) return [];

    final issues = <String>[];
    final nodeRects = <String, Map<String, double>>{};
    for (final n in nodes) {
      final m = n as Map<String, dynamic>;
      final id = m['id'] as String? ?? '';
      final x = (m['x'] as num?)?.toDouble() ?? 0;
      final y = (m['y'] as num?)?.toDouble() ?? 0;
      final w = (m['width'] as num?)?.toDouble() ?? 322;
      final h = (m['height'] as num?)?.toDouble() ?? 200;
      nodeRects[id] = {'l': x, 't': y, 'r': x + w, 'b': y + h};
    }

    final segments = <Map<String, dynamic>>[];
    for (final c in connections) {
      final m = c as Map<String, dynamic>;
      final fromId = m['fromNodeId'] as String? ?? '';
      final toId = m['toNodeId'] as String? ?? '';
      final fromRect = nodeRects[fromId];
      final toRect = nodeRects[toId];
      if (fromRect != null && toRect != null) {
        segments.add({
          'fromId': fromId, 'toId': toId,
          'x1': (fromRect['l']! + fromRect['r']!) / 2,
          'y1': (fromRect['t']! + fromRect['b']!) / 2,
          'x2': (toRect['l']! + toRect['r']!) / 2,
          'y2': (toRect['t']! + toRect['b']!) / 2,
        });
      }
    }

    for (var i = 0; i < segments.length; i++) {
      for (var j = i + 1; j < segments.length; j++) {
        final s1 = segments[i], s2 = segments[j];
        if (_segmentsIntersect(
          s1['x1'] as double, s1['y1'] as double,
          s1['x2'] as double, s1['y2'] as double,
          s2['x1'] as double, s2['y1'] as double,
          s2['x2'] as double, s2['y2'] as double,
        )) {
          final s1Ids = {s1['fromId'], s1['toId']};
          final s2Ids = {s2['fromId'], s2['toId']};
          if (s1Ids.intersection(s2Ids).isEmpty) {
            issues.add('  - 連線 ${s1['fromId']}→${s1['toId']}'
                ' 與 ${s2['fromId']}→${s2['toId']} 交叉');
          }
        }
      }
    }
    return issues;
  }

  static bool _segmentsIntersect(double x1, double y1, double x2, double y2,
      double x3, double y3, double x4, double y4) {
    final d1 = _ccw(x3, y3, x4, y4, x1, y1);
    final d2 = _ccw(x3, y3, x4, y4, x2, y2);
    final d3 = _ccw(x1, y1, x2, y2, x3, y3);
    final d4 = _ccw(x1, y1, x2, y2, x4, y4);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  static double _ccw(double ax, double ay, double bx, double by, double cx, double cy) {
    return (bx - ax) * (cy - ay) - (cx - ax) * (by - ay);
  }

  String _buildPerceptionPrompt(String perceptionContext) {
    final parts = <String>[];

    // [小葵 2026-09-22] KnowledgeIndexer 退役——身份內聯（見 _retiredCoreIdentity）
    parts.add(_retiredCoreIdentity);

    // 人格 prompt
    final persona = _personaManager.buildPersonaPrompt();
    if (persona != null) parts.add(persona);

    // [Phase 3 2026-07-18] 注入工具描述——讓 Agent 知道有哪些工具可用、如何呼叫
    parts.add(_agentLoop.toolRegistry.toPromptSection());

    // [教練 Agent 2026-07-18] 注入 Provider 適配提示——讓原生 Agent知道自己用什麼模型、該怎麼調整策略
    // 這是 async 的，但 _buildPerceptionPrompt 是 sync——所以用快取的 profile
    if (_cachedProfile != null) {
      parts.add('## 引擎適配\n'
          '${_cachedProfile!.adaptationGuide}'
          '${_cachedProfile!.promptNudge != null ? '\n\n${_cachedProfile!.promptNudge}' : ''}');
    }

    // 感知上下文
    parts.add('## 自主感知\n$perceptionContext');

    // 安全邊界提醒
    parts.add('## 安全邊界');
    parts.add('- 破壞性操作（移除節點、執行工作流、清空畫布）系統會自動彈出確認框給使用者，你不需要自己問');
    parts.add('- 使用者明確要求刪除節點時，直接呼叫 canvas_remove_node，系統會處理確認流程');
    parts.add('- 不可主動（未經使用者要求）刪除使用者建立的節點');
    parts.add('- 不可存取 App 沙盒外的檔案');
    parts.add('- 沒有事做時保持安靜，不亂說話');

    // [教練 Agent 2026-07-24] Perceive → Execute → Verify 自動循環協議
    parts.add('## 畫布自動修復協議');
    parts.add('當你收到「畫布健康警示」時，請執行以下循環：');
    parts.add('1. **Perceive**：呼叫 canvas_get_snapshot 取得完整畫布快照，確認問題');
    parts.add('2. **Plan**：決定如何修正（移動哪個節點、移到哪裡）');
    parts.add('3. **Execute**：用 canvas_move_node 執行修正');
    parts.add('4. **Verify**：再次呼叫 canvas_get_snapshot 確認問題已解決');
    parts.add('5. 如果還有問題，回到步驟 2（最多 3 次嘗試）');
    parts.add('6. 修正完成後，用 canvas_send_chat 告訴使用者你修了什麼');
    parts.add('連線是工作流的血管——不能交叉，不能被擋住。'
        '如果 canvas_detect_crossings 偵測到問題，也要修正。');

    return parts.join('\n\n---\n\n');
  }

  /// 釋放資源
  void dispose() {
    stop();
  }
}
