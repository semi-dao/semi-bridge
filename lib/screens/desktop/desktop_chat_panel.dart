/// DesktopChatPanel — 桌面原生聊天面板
///
/// S22: 桌面 App 的對話 tab 專用。
/// 不依賴 ChatScreen，直接用 ChatController + 訊息氣泡 + 輸入框。
/// 支援：對話列表、訊息顯示、輸入發送、Agent Loop 進度條。
///
/// 設計原則：
/// - 桌面原生體驗（寬螢幕佈局、鍵盤快捷鍵）
/// - 使用 BridgeDS 設計系統
/// - 最小依賴，不引入手機版 handler 複雜度
/// - Agent Loop 進度條（S21d 相同設計）

import 'dart:async';
import '../../services/agent_activity_store.dart';
import '../../models/agent_activity.dart';
import '../../services/companion_runtime_store.dart';
import '../../widgets/trust/agent_glyph.dart'; // [小葵 2026-09-15] 指紋章頭像
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/chat_controller.dart';
import '../../models/conversation.dart';
import '../../models/companion.dart';
import '../../models/chat_card_data.dart';
import '../../models/capability_advisor.dart';
import '../../services/bridge_action_progress.dart';
import '../../services/companion_store.dart';
import '../../services/conversation_store.dart';
import '../../services/asset_action_service.dart'; // P0.6a 資產操作
import '../../services/onboarding_detector.dart';
import '../../services/agent_loop/mcp_canvas_tools.dart'; // [Phase 0 Track A 2026-07-17]
import '../../services/local_model_runtime_service.dart'; // [教練 Agent 2026-08-14] resolveShortModelName
import '../../theme/bridge_design_system.dart';
import '../../widgets/chat/agent_model_selector.dart';
// ── Voice AI 引擎 + handler ──
import '../chat/handlers/chat_tts_handler.dart';
import '../chat/handlers/voice_speech_handler.dart'; // [教練 Agent 2026-07-28] Voice AI 語音辨識
import '../../services/voice/voice_engine.dart';
import '../../services/voice/voice_live_controller.dart';
import '../../services/brain_container/brain_container_service.dart'; // [小葵 2026-09-24] 毫秒決策令——快軌語意記憶閃現
import '../../services/api_service.dart'; // [小葵 2026-09-24] 總結令——語音沉澱 LLM 總結
// [小葵 2026-08-30] 即時語音——快答慢想雙軌協調器
import '../../services/voice/realtime_voice_orchestrator.dart';
import '../../services/tts/kokoro_tts_service.dart';
import '../../services/voice/native_audio_bytes_player.dart';

import '../../services/voice/companion_voice_settings.dart';
import '../../services/voice/companion_voice_settings_store.dart';
import '../../services/voice/voice_state_machine.dart' show VoiceState;
import '../../widgets/common/hover_glow_circle_button.dart';
import '../../widgets/voice/voice_button.dart';
import '../../widgets/voice/voice_status_indicator.dart';
import '../../widgets/chat/message_context_menu.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

class DesktopChatPanel extends StatefulWidget {
  final void Function()? onNavigateToSettings;
  final McpCanvasExecutor? mcpCanvasExecutor; // [Phase 0 Track A 2026-07-17]
  final GlobalKey? selfCaptureKey; // [教練 Agent 2026-07-19] App 自拍 key
  final void Function(ChatController controller)?
  onControllerReady; // [教練 Agent 2026-07-19] 暴露 controller 給外層
  /// B系列: Agent 發出畫布匯入卡片時，使用者點擊按鈕後觸發。
  /// 傳入 Agent 的摘要 + 建議名稱，由 bridge_desktop_screen 執行匯入流程。
  final void Function(String summary, String suggestedTitle)? onCanvasImport;

  /// [教練 Agent 2026-08-03] 新對話同步：當 ChatController 內部建立新對話時
  /// （點「+對話泡泡」或「延伸話題」），通知父層刷新左側 sidebar。
  /// 因為左側 sidebar 顯示的是 BridgeDesktopScreen 的 `_conversations` 變量，
  /// 跟 ChatController 內存是兩條獨立列表，必須手動同步。
  final VoidCallback? onConversationCreated;

  const DesktopChatPanel({
    super.key,
    this.onNavigateToSettings,
    this.mcpCanvasExecutor,
    this.selfCaptureKey,
    this.onControllerReady,
    this.onCanvasImport,
    this.onConversationCreated,
  });

  @override
  State<DesktopChatPanel> createState() => _DesktopChatPanelState();
}

class _DesktopChatPanelState extends State<DesktopChatPanel> {
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode(debugLabel: 'desktop-chat-input');
  final _scrollController = ScrollController();

  // [教練 Agent 2026-07-29] 攔截鍵盤事件（直接掛在 FocusNode 上）：
  // - Enter（無修飾鍵）→ 新增行（不攔截，讓 TextField 自然換行）
  // - Cmd+Enter 或 Shift+Enter → 送出訊息
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }

    final isCmd = HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // [教練 Agent 2026-08-03] Cmd+Enter 或 Shift+Enter → 送出（loading 時也可送：插嘴）
    if (isCmd || isShift) {
      _controller.sendMessage();
      return KeyEventResult.handled;
    }

    // 純 Enter → 讓 TextField 處理換行（不攔截）
    return KeyEventResult.ignored;
  }

  late final ChatController _controller;

  // ── Voice AI handler + 引擎 ──
  late final ChatTtsHandler _tts;
  late VoiceEngine _voiceEngine;
  late final NativeAudioBytesPlayer _audioPlayer;

  // [教練 Agent 2026-07-28] Voice AI 專用語音辨識 — 只驅動 VoiceEngine，不碰輸入框
  late final VoiceSpeechHandler _voiceSpeech;

  // [教練 Agent 2026-08-03] 雙向溝通
  VoiceLiveController? _voiceLive;

  /// [教練 Agent 2026-08-03] STT 狀態 → VoiceMode
  /// 純 STT 語音輸入：按下開始 → 講話 → 再按停止 → 文字送出
  /// - idle → 沒在錄音
  /// - listening → 正在錄音（按下變紅 + 波形動）
  /// - thinking/speaking → 不會觸發（純 STT 模式）
  VoiceMode get _voiceMode =>
      _voiceSpeech.isListening ? VoiceMode.listening : VoiceMode.idle;

  /// [小葵 2026-09-24 Blue 抓包③] 全雙工模式判定——orchestrator 活著
  /// 表示短按的「即時語音（快答慢想）」進行中，此時 partial 不寫輸入框
  /// （字幕走 _realtimeSubtitle 通道），避免「感覺像語音打字」。
  bool get _isRealtimeConversationActive => _realtimeVoice != null;

  /// [教練 Agent 2026-08-03] 麥克風真實音量（0.0~1.0）— 從 voice_speech_handler 訂閱
  /// 用 ValueNotifier — stream.listen 直接寫 value，不 setState（避免整個 panel 重建）
  final ValueNotifier<double> _micVolume = ValueNotifier<double>(0.0);
  StreamSubscription<double>? _micVolumeSub;

  /// [教練 Agent 2026-08-03] 語音開始前輸入框已有的文字（partial 會疊加上去）
  String _draftBeforeVoice = '';
  StreamSubscription<String>? _partialTextSub;

  // Agent Loop 進度（只留使用者可理解的工具狀態）
  int? _agentLoopTurn;
  String? _agentLoopToolName;
  String? _agentLoopToolStatus;

  /// [小葵 2026-09-18] 思路+動作日誌——Hermes 式透明化（環形 200 行）
  final List<String> _agentLoopLog = [];
  void _pushLoopLog(String line) {
    if (line.isEmpty) return;
    _agentLoopLog.add(line);
    if (_agentLoopLog.length > 200) _agentLoopLog.removeAt(0);
    // [小葵 2026-09-19 過程直播] 同步推播全域 store——懸浮窗狀態文字即時更新
    AgentActivityStore.instance.pushLoopStatus(line);
  }

  // [小葵 2026-09-19 過程直播] 近況條目——關鍵近況（非工程流水帳），完成後收合可點開
  bool _agentLoopDetailExpanded = false;
  bool get _agentLoopFinished =>
      !_controller.isLoading && _agentLoopLog.isNotEmpty;

  // [教練 Agent 2026-08-07] 即時階段回饋——thinking / tool_start / timeout 等
  String? _agentLoopStage;
  String? _agentLoopStageDetail;

  // [小葵 2026-10-05 Blue 令] 上一次進泡泡的觀察文字（防同輪重複推送）
  String? _lastBubbleSnippet;

  // [小葵 2026-09-19 過程直播] 上一輪 loading 狀態（偵測任務邊界用）
  bool _prevLoadingState = false;
  // [小葵 2026-09-22 修 Bug] 完成卡自動收回計時器——完成後 5 秒無人展開
  // 細節就溫柔收起（Blue：不看細節的話幾秒後自動收回去）。
  Timer? _agentLoopAutoDismissTimer;

  void _scheduleAgentLoopAutoDismiss() {
    _agentLoopAutoDismissTimer?.cancel();
    _agentLoopAutoDismissTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      // 使用者已展開細節＝想看，不打擾
      if (_agentLoopDetailExpanded) return;
      if (!_controller.isLoading && _agentLoopLog.isNotEmpty) {
        setState(() => _agentLoopLog.clear());
      }
    });
  }

  // Companion
  Companion? _activeCompanion;
  // [小葵 2026-09-24 Blue 三修之三] 追蹤 controller loading 邊緣——true→false 即一輪完成
  bool? _lastControllerLoading;

  @override
  void initState() {
    super.initState();
    _controller = ChatController();
    // [教練 Agent P0.5b-fix 2026-08-07] Desktop 不注入 executor，要手動確保訂閱 progressStream
    _controller.ensureProgressSubscription();
    _controller.mcpCanvasExecutor =
        widget.mcpCanvasExecutor; // [Phase 0 Track A 2026-07-17]

    // [教練 Agent 2026-07-29] 在 FocusNode 上直接設定 onKeyEvent，
    // 比用 Focus widget wrapper 更可靠 — 確保事件在 TextField 處理前被攔截。
    // - Enter（無修飾鍵）→ 不攔截，讓 TextField 自然換行
    // - Cmd+Enter 或 Shift+Enter → 送出訊息
    _messageFocusNode.onKeyEvent = _handleKeyEvent;

    // ── Voice AI handler 初始化 ──
    _tts = ChatTtsHandler(onError: _showError);
    _tts.init();
    _audioPlayer = NativeAudioBytesPlayer();

    // ── Voice AI 引擎初始化 ──
    _voiceEngine = VoiceEngine(
      onSpeak: (text) => _tts.speak(text),
      onStopSpeaking: () => _tts.stop(),
      onPlayAudioBytes: (bytes) => _audioPlayer.play(bytes),
      onAgentLoopTrigger:
          ({required userText, required onProgress, required onComplete}) {
            _triggerAgentLoopForVoice(
              userText: userText,
              onProgress: onProgress,
              onComplete: onComplete,
            );
          },
    );
    _voiceEngine.state.addListener(_onVoiceStateChanged);
    _loadVoiceSettingsAndBuild();

    // [教練 Agent 2026-07-28] Voice AI 專用語音辨識 — 只驅動 VoiceEngine
    _voiceSpeech = VoiceSpeechHandler(
      voiceEngine: _voiceEngine,
      onError: (msg) {
        debugPrint('[DesktopChatPanel] VoiceSpeech: $msg');
        // 麥克風權限相關錯誤 → 顯示權限提示
        if (msg.contains('麥克風') ||
            msg.contains('權限') ||
            msg.contains('permission')) {
          _showError('麥克風權限未開啟，請到系統設定 > 隱私與安全 > 麥克風允許橋樑');
        } else {
          _showError(msg);
        }
      },
    );
    // [教練 Agent 2026-08-03] 訂閱 STT 真實音量
    _micVolumeSub = _voiceSpeech.amplitudeStream.listen((v) {
      // [教練 Agent 2026-08-03] 直接寫 ValueNotifier，不 setState 避免 panel 重建
      _micVolume.value = v;
    });
    // [教練 Agent 2026-08-03] 訂閱 STT 即時 partial 文字 → 直接寫入輸入框（像一般打字）
    _partialTextSub = _voiceSpeech.partialTextStream.listen((text) {
      // [小葵 2026-09-24 Blue 抓包③] 全雙工模式中 partial 不寫輸入框——
      // 短按=即時語音對談（字幕走 _realtimeSubtitle），寫框會變成「語音打字」
      // 的錯覺+殘留。只有長按（語音輸入文字）模式才寫框。
      if (_isRealtimeConversationActive) {
        // 使用者語音即時字幕——顯示「她聽到的字」而不是寫進輸入框
        if (mounted) setState(() => _realtimeSubtitle = text);
        // [小葵 2026-09-24 業界對齊] Speculative prefill——partial 一到，
        // 快軌 LLM 立刻開跑（業界 interim-first 模式）。VAD 判停口時
        // LLM 已經跑大半，final 只是 commit——第一聲顯著提前。
        // 注意：先剝除已送出前綴（macOS dictation 的 partial 跨句累積，
        // 不剝會把前幾句也餵進 prefill）。
        final fresh = _voiceSpeech.stripDispatchedPrefix(text);
        if (fresh.trim().isNotEmpty) {
          _realtimeVoice?.onPartialTranscript(fresh);
        }
        return;
      }
      // [小葵 2026-09-24 Blue 抓包④] 長按模式：每輪重置基準——
      // 手打草稿快取進 _draftBeforeVoice（疊加保留），STT 累積殘留則由
      // handler 的 markDispatched 裱除。規格：一句一句、零殘留。
      if (_draftBeforeVoice.isEmpty && _messageController.text.isNotEmpty) {
        _draftBeforeVoice = _messageController.text;
      }
      _messageController.text = _draftBeforeVoice.isEmpty
          ? text
          : '$_draftBeforeVoice$text';
      _messageController.selection = TextSelection.collapsed(
        offset: _messageController.text.length,
      );
    });

    // [教練 Agent 2026-07-19] 傳入 App 自拍 key，讓聊天路徑的 AgentLoop 也能截 App 畫面
    if (widget.selfCaptureKey != null) {
      _controller.setSelfCaptureKey(widget.selfCaptureKey!);
    }
    // [教練 Agent 2026-07-19] 通知外層 controller 已就緒
    if (widget.onControllerReady != null) {
      widget.onControllerReady!(_controller);
    }
    _controller.onScrollToBottom = _scrollToBottom;
    // [2026-08-27 共視修復] 空白髮話自動建對話 → 通知父層刷新側欄
    _controller.onConversationAutoCreated = () {
      widget.onConversationCreated?.call();
    };
    _controller.addListener(_syncFromController);
    _controller.onShowError = _showError;
    _controller.onAgentLoopProgress =
        (turnIndex, maxTurns, toolName, toolStatus, llmSnippet) {
          if (!mounted) return;
          setState(() {
            _agentLoopTurn = turnIndex + 1;
            _agentLoopToolName = toolName;
            _agentLoopToolStatus = toolStatus;
            // [小葵 2026-09-18] 思路+動作進日誌——Blue 要能看到 agent 在想什麼
            final snippet = llmSnippet.trim();
            if (snippet.isNotEmpty) {
              _pushLoopLog('💭 ${snippet.replaceAll('\n', ' ')}');
              // [小葵 2026-10-05 Blue 令] 中間觀察直進對話泡泡——
              // 「使用者看到這樣的文字會很高興，而且會想要繼續看下去」。
              // 過程即內容：不用等全部結論，分析邊跑邊讀。
              // 防重複：內容夠長（>24 字）才值得進泡泡；同一輪只推一次。
              if (snippet.length > 24 && snippet != _lastBubbleSnippet) {
                _lastBubbleSnippet = snippet;
                _controller.injectAssistantMessage(
                  snippet,
                  metadata: {
                    'kind': 'loop_observation',
                    'turn': turnIndex + 1,
                  },
                );
              }
            }
            if (toolName != null) {
              _pushLoopLog(
                  '🔧 ${_translateToolName(toolName)}${toolStatus == 'failed' ? ' ✗' : ' ✓'}');
            }
          });
        };
    // [教練 Agent 2026-08-07] 即時階段回饋——不再讓使用者看著黑箱
    _controller.onAgentLoopStage =
        (stage, {toolName, detail}) {
          if (!mounted) return;
          setState(() {
            _agentLoopStage = stage;
            _agentLoopStageDetail = detail;
          });
        };
    _controller.onFocusMessageInput = _focusMessageInput;
    _controller.onClearMessageInput = () => _messageController.clear();
    _controller.onGetMessageText = () => _messageController.text;
    _controller.onSetMessageText = (text) =>
        setState(() => _messageController.text = text);
    _loadActiveCompanion();
    _init();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusMessageInput());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncFromController);
    // ── Voice AI 引擎清理 ──
    _voiceEngine.state.removeListener(_onVoiceStateChanged);
    _voiceLive?.dispose(); // [教練 Agent 2026-08-03]
    _voiceSpeech.dispose(); // [教練 Agent 2026-07-28] 語音辨識 handler 清理
    _micVolumeSub?.cancel(); // [教練 Agent 2026-08-03] 取消音量訂閱
    _agentLoopAutoDismissTimer?.cancel(); // [小葵 2026-09-22] 完成卡計時器清理
    _talkingFallbackTimer?.cancel(); // [小葵 2026-09-24] 講話回落計時器清理
    _partialTextSub?.cancel(); // [教練 Agent 2026-08-03] 取消 partial 訂閱
    _micVolume.dispose(); // [教練 Agent 2026-08-03] 釋放 ValueNotifier
    // [小葵 2026-08-30] 即時語音協調器清理
    _realtimeEventSub?.cancel();
    _realtimeVoice?.dispose();
    unawaited(_voiceEngine.stopConversation());
    _voiceEngine.dispose();
    unawaited(_audioPlayer.dispose());
    unawaited(_tts.dispose());
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadActiveCompanion() async {
    try {
      final companion = CompanionStore().activeCompanion;
      if (mounted) {
        setState(() => _activeCompanion = companion);
      }
    } catch (e) {
      debugPrint('[DesktopChatPanel] loadActiveCompanion error: $e');
    }
  }

  Future<void> _init() async {
    // [2026-08-26 身份污染追根] controller 必須先載入 active companion——
    // 否則 loadGeneralConversations 用 null companionId 混載全部對話，
    // 且 system prompt 的 companionPersona 注入是 null → 夥伴失憶失格。
    // 舊碼只更新本 widget 的 _activeCompanion（UI 顯示用），
    // controller._activeCompanion 一直是 null——MimeMi 自稱無名的根因。
    _controller.loadActiveCompanion();
    _controller.onNavigateToSetting =
        ({required String target, String? provider}) {
          // 桌面版：透過 callback 通知父畫面切到系統 tab 設定頁
          // 或 fallback 到 GoRouter
          if (widget.onNavigateToSettings != null) {
            widget.onNavigateToSettings!.call();
          }
        };
    // [教練 Agent 2026-07-23] 畫布對話系統 — 桌面對話頁面只載入一般對話，不混入畫布對話
    await _controller.loadGeneralConversations();
    // P0a: 桌面版 Agent 對話式 onboarding — 偵測空白狀態，注入歡迎訊息
    await _maybeShowOnboardingWelcome();
    // P2-r2: 載入完成後預設捲到最新訊息（force=true，切換對話強制捲到底）
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottom(force: true),
    );
  }

  /// 偵測空白狀態：如果沒有任何 provider token 且尚未展示過 onboarding，
  /// 在當前對話注入一條 Agent 歡迎引導訊息。
  Future<void> _maybeShowOnboardingWelcome() async {
    final status = await OnboardingDetector.detect();
    if (!status.shouldShowWelcome) return;

    // 確保有一個對話可以放歡迎訊息
    if (_controller.currentConversation == null) return;

    final welcomeMessage = OnboardingDetector.buildWelcomeMessage(status);
    final conv = _controller.currentConversation!;
    final msg = Message(
      id: 'onboarding_welcome_${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      content: welcomeMessage,
      timestamp: DateTime.now(),
      metadata: {'type': 'onboarding_welcome'},
    );
    final updatedConv = conv.copyWith(
      messages: [...conv.messages, msg],
      updatedAt: DateTime.now(),
    );
    await ConversationStore.save(updatedConv);
    _controller.setCurrentConversation(updatedConv);
    await OnboardingDetector.markShown();
  }

  /// [教練 Agent 2026-08-03] 對話發射鈕 — 圓形 + hover 顯著發光
  /// 跟 chat_screen.dart 的 FloatingActionButton.small 一樣互動感覺
  Widget _buildChatSendButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return HoverGlowCircleButton(
      icon: icon,
      color: color,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  void _syncFromController() {
    if (!mounted) return;
    // [2026-08-26 身份污染追根] UI 顯示名與 controller 同步——
    // controller 切換夥伴時，本 panel 的頭像/名稱即時跟上。
    _activeCompanion = _controller.activeCompanionInstance ?? _activeCompanion;
    // [小葵 2026-09-24 Blue 三修之三] loading 結束＝一輪對話完成——通知外層
    // 刷新 sidebar（指紋章/標題/訊息數即時更新，不用切頁才看到）。
    final wasLoading = _lastControllerLoading;
    _lastControllerLoading = _controller.isLoading;
    if (wasLoading == true && !_controller.isLoading) {
      widget.onConversationCreated?.call();
    }
    // loading 結束時清即時指標（近況記錄保留為完成卡——點開可看全程）
    if (!_controller.isLoading) {
      _agentLoopTurn = null;
      _agentLoopToolName = null;
      _agentLoopToolStatus = null;
      _agentLoopStage = null;
      _agentLoopStageDetail = null;
      // [小葵 2026-09-22 修 Bug] 進入完成態——啟動自動收回計時器
      if (_agentLoopLog.isNotEmpty) {
        _scheduleAgentLoopAutoDismiss();
      }
    }
    // [小葵 2026-09-19 過程直播] 新任務開始（loading 從閒置轉活躍）→ 清上一輪近況
    if (_controller.isLoading && !_agentLoopDetailExpanded) {
      final lastWasIdle = _prevLoadingState == false;
      if (lastWasIdle && _agentLoopLog.isNotEmpty) {
        _agentLoopLog.clear();
      }
    }
    _prevLoadingState = _controller.isLoading;
    setState(() {});
    // [教練 Agent 2026-08-03] 智慧滾動：只有使用者已經在底部時才自動滾
    // 避免使用者正在看歷史時被強制拉回底部
    _scrollToBottom(force: false);
  }

  /// [教練 Agent 2026-08-03] 智慧滾動：
  /// - force = true：強制（切換對話、初始化）→ 一律到底
  /// - force = false：只有「使用者已經在底部附近」才自動滾
  ///   這樣使用者捲上去看歷史時不會被強制拉回底部
  void _scrollToBottom({bool force = false}) {
    if (!_scrollController.hasClients) return;
    if (!force) {
      final pos = _scrollController.position;
      // [教練 Agent 2026-08-03] 使用者捲到距離底部 200px 以上時，跳過自動滾動
      if (pos.pixels < pos.maxScrollExtent - 200) {
        return;
      }
    }
    // 用 jumpTo 而非 animateTo，確保即使 frame 尚未完成也能到位
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      // 再加一幀確保圖片等非同步內容渲染後位置正確
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    });
  }

  void _focusMessageInput() {
    if (mounted) _messageFocusNode.requestFocus();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: BridgeDSColors.of(context).accentRed,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Voice AI 引擎方法 ──

  /// VoiceEngine 狀態變化 → 更新 UI
  void _onVoiceStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Toggle Voice AI 對談（VoiceButton onToggle）
  ///
  /// [教練 Agent 2026-07-28] 如果 start() 失敗（權限問題等），
  /// 回復 VoiceEngine 狀態，onError 會透過 SnackBar 顯示權限提示。
  // [教練 Agent 2026-08-03] C4: 異步載入夥伴語音設定 + 重建 VoiceEngine
  Future<void> _loadVoiceSettingsAndBuild() async {
    final activeId = CompanionStore().activeCompanionId;
    if (activeId == null) return;

    final settings = await CompanionVoiceSettingsStore.load(activeId);
    if (!mounted) return;
    final oldEngine = _voiceEngine;
    oldEngine.state.removeListener(_onVoiceStateChanged);
    unawaited(oldEngine.stopConversation());
    oldEngine.dispose();
    final engine = VoiceEngine(
      onSpeak: (text) => _tts.speak(text),
      onStopSpeaking: () => _tts.stop(),
      onPlayAudioBytes: (bytes) => _audioPlayer.play(bytes),
      onAgentLoopTrigger:
          ({required userText, required onProgress, required onComplete}) {
            _triggerAgentLoopForVoice(
              userText: userText,
              onProgress: onProgress,
              onComplete: onComplete,
            );
          },
      settings: settings,
    );
    _voiceEngine = engine;
    engine.state.addListener(_onVoiceStateChanged);
    if (mounted) setState(() {});
  }

  VoiceEngine get _currentVoiceEngine => _voiceEngine;

  Future<void> _toggleVoiceConversation() async {
    final engine = _currentVoiceEngine;
    if (engine.isConversationActive || _voiceSpeech.isListening) {
      // [小葵 2026-09-24 Blue 抓包②] 停止分支漏了 _realtimeVoice——
      // orchestrator 沒停，TTS 佇列繼續播 =「停止後一直自言自語」。
      await _realtimeVoice?.stop();
      // [小葵 2026-09-24 Blue 乒乓模型] 沉澱——語音聊的內容不蒸發：
      // 對談窗口（最近 6 球）存成一條摘要訊息進對話，後續打字對話
      // 能接著這個主軸繼續（「剛剛語音聊到…」成為可引用上下文）。
      final talked = _realtimeVoice?.exportDialogue() ?? const <String>[];
      _realtimeVoiceRaw = _realtimeVoice?.exportSessionLog(); // [總結令] 完整原料
      _realtimeVoice = null;
      await _voiceLive?.stop();
      _voiceLive = null;
      await _voiceSpeech.stop();
      await engine.stopConversation();
      _draftBeforeVoice = '';
      _realtimeSubtitle = '';
      if (talked.length >= 2) {
        await _depositVoiceSummary(talked);
      }
    } else {
      // [小葵 2026-08-30] 即時模式升級——RealtimeVoiceOrchestrator
      // （快答慢想雙軌 + 逐句串流 TTS）接管「短按」；
      // VoiceLiveController 保留為 fallback（orchestrator 啟動失敗時）。
      final started = await _startRealtimeVoice();
      if (!started) {
        _voiceLive = VoiceLiveController(
          speechHandler: _voiceSpeech,
          voiceEngine: engine,
          chatController: _controller,
        );
        try {
          await _voiceLive!.start();
          debugPrint('[DesktopChatPanel] 雙向溝通已啟動（fallback）');
        } catch (e) {
          debugPrint('[DesktopChatPanel] 雙向溝通啟動失敗: $e');
          _voiceLive = null;
        }
      }
    }
    if (mounted) setState(() {});
  }

  /// [小葵 2026-09-24 Blue 乒乓模型·沉澱＋總結令] 語音對談的內容存回對話——
  /// LLM 真總結：主題主軸＋啟發＋後續要執行的事。失敗退回精簡流水帳。
  Future<void> _depositVoiceSummary(List<String> talked) async {
    final raw = _realtimeVoiceRaw;
    _realtimeVoiceRaw = null;
    List<String> source = raw ?? talked;
    if (source.length < 2) return;
    try {
      // 先試 LLM 總結（完整 session log 是原料）
      final summarized = await ApiService.complete(
        systemPrompt: '你是一段語音對談的總結器。輸入是「user:/agent:」逐輪記錄。'
            '輸出一份繁中總結，格式：\n'
            '🎙️ 語音對談總結\n'
            '【主題主軸】一到兩句——這場對話累積出的核心話題。\n'
            '【啟發亮點】條列最多 3 點——對話中冒出的想法或洞察。\n'
            '【後續可執行】條列最多 3 點——聊到一半說「這個之後要做」的事；'
            '沒有就寫「（無）」。\n'
            '規則：只根據記錄總結，禁止發明不存在的事；口吻精簡，'
            '像真人為自己寫的筆記。',
        userPrompt: source.join('\n'),
      );
      final clean = summarized.trim();
      if (clean.isNotEmpty) {
        await _controller.injectAssistantMessage(
          clean,
          metadata: const {'kind': 'voice_session_summary'},
        );
        debugPrint('[DesktopChatPanel] 語音沉澱完成（LLM 總結）');
        return;
      }
    } catch (e) {
      debugPrint('[DesktopChatPanel] LLM 總結失敗，退回精簡記錄: $e');
    }
    // Fallback：精簡流水帳（原 v1 行為）
    try {
      final sb = StringBuffer('🎙️ 語音對談記錄（主軸）\n');
      for (final line in source) {
        if (line.startsWith('user: ')) {
          sb.writeln('• ${line.substring(6)}');
        } else if (line.startsWith('agent: ')) {
          sb.writeln('  ↳ ${line.substring(7)}');
        }
      }
      await _controller.injectAssistantMessage(
        sb.toString().trimRight(),
        metadata: const {'kind': 'voice_session_summary'},
      );
      debugPrint('[DesktopChatPanel] 語音沉澱完成（精簡記錄 fallback）');
    } catch (e) {
      debugPrint('[DesktopChatPanel] 語音沉澱失敗（不影響停止）: $e');
    }
  }

  // ──────────────────────────────────────────────────────
  // [小葵 2026-08-30] 即時語音（快答慢想雙軌）
  // ──────────────────────────────────────────────────────

  RealtimeVoiceOrchestrator? _realtimeVoice;
  StreamSubscription<RealtimeVoiceEvent>? _realtimeEventSub;
  String _realtimeSubtitle = ''; // 快軌重點字幕（視覺第二通道）
  /// [小葵 2026-09-24 總結令] 停止時撈完整 session log——LLM 總結原料。
  /// 在 orchestrator stop 前先抓（stop 後仍可讀，但語意上先抓先贏）。
  List<String>? _realtimeVoiceRaw;

  /// 啟動即時語音模式。成功回 true（caller 不啟動 fallback）。
  ///
  /// 架構：VoiceLiveController 當「耳朵+時鐘」（VAD/final/fallback 是它），
  /// orchestrator 當「腦+嘴」（快慢雙軌 + 逐句 TTS）。兩者用
  /// onExternalTurn / onExternalBargeIn hook 連接。
  Future<bool> _startRealtimeVoice() async {
    try {
      // [小葵 2026-08-31] 夥伴語音設定+人格接通——鍊成頁選的聲音/語速/
      // 情緒真正生效；快軌說話的是這隻夥伴，不是泛用助理
      final activeId = CompanionStore().activeCompanionId;
      CompanionVoiceSettings? voiceSettings;
      String? persona;
      if (activeId != null) {
        voiceSettings = await CompanionVoiceSettingsStore.load(activeId);
        final c = CompanionStore().activeCompanion;
        if (c != null) {
          // 組裝人格卡：名字 + 口說最相關的欄位（說話風格/個性/習慣/關係）
          final parts = <String>[
            '名字：${c.name}',
            if (c.speakingStyle.trim().isNotEmpty) '說話風格：${c.speakingStyle}',
            if (c.personality.trim().isNotEmpty) '個性：${c.personality}',
            if (c.habit.trim().isNotEmpty) '習慣：${c.habit}',
            if (c.relationship.trim().isNotEmpty) '與使用者的關係：${c.relationship}',
          ];
          persona = parts.join('；');
        }
      }

      final orch = RealtimeVoiceOrchestrator(
        player: _audioPlayer,
        // 面板沒有自己的 Kokoro 實例（VoiceEngine 內部管理）——
        // orchestrator 自帶，port-reuse 原則下與既有 server 共存
        kokoro: KokoroTtsService(),
        settings: voiceSettings,
        companionPersona: persona,
        // [小葵 2026-09-24 Blue 毫秒決策令] 語意記憶閃現——
        // 接球前問向量大腦「我們聊過這個嗎」（768 維本地，毫秒級）。
        // 失敗回 null：快軌照跑，只是沒靈感。
        memoryFlash: (userText) async {
          try {
            final hits = await BrainContainerService.instance
                .retrieveMemories(query: userText, limit: 3);
            if (hits.isEmpty) return null;
            return hits.map((r) => r.content).toList();
          } catch (_) {
            return null;
          }
        },
      );
      await orch.start();
      _realtimeVoice = orch;

      _realtimeEventSub?.cancel();
      _realtimeEventSub = orch.events.listen(_onRealtimeEvent);

      // 耳朵：VoiceLiveController（VAD 時鐘）+ 雙軌 hook
      final engine = _currentVoiceEngine;
      await engine.startConversation();
      _voiceLive = VoiceLiveController(
        speechHandler: _voiceSpeech,
        voiceEngine: engine,
        chatController: _controller,
        onExternalTurn: (turnText) => orch.onUserTurnComplete(
          turnText,
          onSlowLane: _slowLaneSend,
        ),
        onExternalBargeIn: orch.onBargeIn,
        // [小葵 2026-09-24 Blue 插嘴令] 真相源接線——orchestrator 的 TTS
        // 不經 VoiceEngine，插嘴判定要用 orchestrator.isSpeaking。
        isExternalAgentSpeaking: () => orch.isSpeaking,
      );
      await _voiceLive!.start();
      await _voiceSpeech.start();

      debugPrint('[DesktopChatPanel] 即時語音已啟動（快答慢想雙軌）');
      return true;
    } catch (e) {
      debugPrint('[DesktopChatPanel] 即時語音啟動失敗（退回舊模式）: $e');
      await _realtimeVoice?.stop();
      _realtimeVoice = null;
      return false;
    }
  }

  /// 慢軌委派——走既有 sendMessage（人格/工具/記憶全保留），回傳完整回覆
  Future<String?> _slowLaneSend(String userText) async {
    final messagesBefore =
        _controller.currentConversation?.messages.length ?? 0;
    final originalGetter = _controller.onGetMessageText;
    final originalSetter = _controller.onSetMessageText;
    _controller.onGetMessageText = () => userText;
    _controller.onSetMessageText = (_) {};
    try {
      await _controller.sendMessage();
    } finally {
      _controller.onGetMessageText = originalGetter;
      _controller.onSetMessageText = originalSetter;
    }
    final messages = _controller.currentConversation?.messages ?? [];
    if (messages.length <= messagesBefore) return null;
    // 找 messagesBefore 之後第一條 assistant 訊息
    for (final m in messages.skip(messagesBefore).toList().reversed) {
      if (m.role == 'assistant') return m.content;
    }
    return null;
  }

  void _onRealtimeEvent(RealtimeVoiceEvent e) {
    if (!mounted) return;
    switch (e.type) {
      case RealtimeVoiceEventType.fastReplyReady:
        // 快軌重點出爐——字幕同步顯示（視覺第二通道）
        setState(() => _realtimeSubtitle = e.text ?? '');
        break;
      case RealtimeVoiceEventType.bargeIn:
        setState(() => _realtimeSubtitle = '');
        break;
      case RealtimeVoiceEventType.fullReplyReady:
        // 完整回答已進聊天面板（慢軌走 sendMessage）——清字幕
        setState(() => _realtimeSubtitle = '');
        break;
      // [小葵 2026-09-24 Blue 令·出道前] 講話狀態驅動——Agent 出聲的時段
      // 懸浮窗切到「講話」狀態短片（talk 池隨機），講完回落。
      // 9/25 演示大量講話，畫面上的她要跟著開口。
      case RealtimeVoiceEventType.ttsSegmentStarted:
        _driveTalkingState();
        break;
      case RealtimeVoiceEventType.ttsSegmentDone:
        // 每句講完不立即回落——等佇列全空（orchestrator 沒有 queueEmpty
        // 事件，用 0.6s 緩衝：下一句 Started 會再刷新）
        _scheduleTalkingFallback();
        break;
      default:
        break;
    }
  }

  /// 講話狀態——從 talk_* 池隨機挑一段短片推送（懂快門狗在 2s 後接管回落）
  void _driveTalkingState() {
    _talkingFallbackTimer?.cancel();
    final companion = _activeCompanion;
    if (companion == null) return;
    final talkPool = companion.stateAnimationPaths.entries
        .where((e) => e.key.startsWith('talk_') && e.value.endsWith('.mp4'))
        .map((e) => e.value)
        .toList();
    if (talkPool.isEmpty) return;
    talkPool.shuffle();
    AgentActivityStore.instance.update(
      stage: AgentActivityStage.composing,
      mood: AgentCompanionMood.proud,
      action: AgentCompanionAction.bouncing,
      active: false,
    );
    // 直接把 talk 片推給懸浮窗（繞過 stage 映射——講話就是講話）
    // 透過 runtime store 讓面板層重推。
    CompanionRuntimeStore.instance.updateActivity(
      AgentActivityStore.instance.current,
    );
    debugPrint('[DesktopChatPanel] 講話狀態驅動: ${talkPool.first.split('/').last}');
  }

  Timer? _talkingFallbackTimer;
  void _scheduleTalkingFallback() {
    _talkingFallbackTimer?.cancel();
    _talkingFallbackTimer = Timer(const Duration(milliseconds: 600), () {
      // 沒有下一句接續——講話結束，回待機（看門狗也會兜底）
      AgentActivityStore.instance.idle();
    });
  }

  // [教練 Agent 2026-08-03] 長按 = 語音輸入文字（iMessage 風格）
  Future<void> _startVoiceInput() async {
    final engine = _currentVoiceEngine;
    if (engine.isConversationActive || _voiceSpeech.isListening) return;
    debugPrint('[DesktopChatPanel] 長按：語音輸入模式開始');
    await _voiceSpeech.start();
    if (mounted) setState(() {});
  }

  Future<void> _stopVoiceInput() async {
    if (!_voiceSpeech.isListening) return;
    debugPrint('[DesktopChatPanel] 長按放開：語音輸入模式結束');
    await _voiceSpeech.stop();
    if (mounted && _messageController.text.trim().isNotEmpty) {
      await _controller.sendMessage();
    }
    // [小葵 2026-09-24 Blue 抓包④] 語音打字殘留——Blue 規格：一句一句、零殘留。
    // 送出後主動清框（macOS dictation 的 recognizedWords 會跨句累積，
    // 若 STT 在 stop 前又推一次含舊句的 partial 進框，這裡把它清掉）。
    if (mounted) {
      _messageController.clear();
      _draftBeforeVoice = '';
    }
    if (mounted) setState(() {});
  }

  /// 將使用者語音輸入轉發到 ChatController 的 AgentLoop
  ///
  /// VoiceEngine 的 onAgentLoopTrigger 回調會呼叫此方法。
  /// 使用 onGetMessageText 暫存模式直接送出語音文字，不寫入輸入框，
  /// 避免與 Open Whisper 的貼上操作衝突導致文字重複。
  void _triggerAgentLoopForVoice({
    required String userText,
    required void Function(String intermediateText) onProgress,
    required void Function(String finalReply) onComplete,
  }) {
    // [教練 Agent 2026-07-28] 不寫入輸入框，改用 onGetMessageText 暫存模式直接送出
    final originalGetter = _controller.onGetMessageText;
    final originalSetter = _controller.onSetMessageText;
    _controller.onGetMessageText = () => userText;
    _controller.onSetMessageText = (_) {}; // 暫時忽略 setter，不寫入輸入框

    // 記錄送出前的訊息數量，用於偵測 Agent 回覆
    final messagesBefore =
        _controller.currentConversation?.messages.length ?? 0;

    // 監聽 controller 的 Agent Loop 進度
    void onProgressCallback(
      int turnIndex,
      int maxTurns,
      String? toolName,
      String? toolStatus,
      String? llmSnippet,
    ) {
      // 第三層現況回報 — 工具執行進度
      if (toolName != null && toolStatus != null) {
        onProgress('$toolName：$toolStatus');
      }
    }

    // 暫存原本的進度回調，送出後恢復
    final originalProgress = _controller.onAgentLoopProgress;
    _controller.onAgentLoopProgress = onProgressCallback;

    // 送出訊息
    _controller
        .sendMessage()
        .then((_) {
          // 恢復原本的 getter/setter/進度回調
          _controller.onGetMessageText = originalGetter;
          _controller.onSetMessageText = originalSetter;
          _controller.onAgentLoopProgress = originalProgress;

          // 取得最終回覆（最後一條 assistant 訊息）
          final messages = _controller.currentConversation?.messages ?? [];
          if (messages.length > messagesBefore) {
            for (var i = messages.length - 1; i >= messagesBefore; i--) {
              if (messages[i].role == 'assistant') {
                final reply = messages[i].content
                    .replaceAll(
                      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
                      '',
                    )
                    .trim();
                onComplete(reply);
                return;
              }
            }
          }
          // fallback：如果找不到 assistant 訊息
          onComplete('（已完成）');
        })
        .catchError((error) {
          // 恢復原本的 getter/setter/進度回調
          _controller.onGetMessageText = originalGetter;
          _controller.onSetMessageText = originalSetter;
          _controller.onAgentLoopProgress = originalProgress;
          onComplete('處理時發生錯誤：$error');
        });
  }

  /// 簡易訊息氣泡 — 桌面版不依賴 MessageBubbleConfig 的龐大 callback 體系
  /// 但會攔截帶有 card prefix 的系統訊息，渲染為人類可讀的進度卡。
  Widget _buildMessageBubble(Message msg) {
    final isUser = msg.role == 'user';

    // [2026-08-27 共視修復] 靜默訊息不渲染（切換觸發泡泡、系統事件等）
    if (msg.metadata != null &&
        (msg.metadata!['silent'] == true ||
            msg.metadata!['kind'] == 'canvas_snapshot' ||
            msg.metadata!['kind'] == 'canvas_event')) {
      return const SizedBox.shrink();
    }

    // [2026-08-27 共視修復] 切換夥伴系統條——置中顯示，與一般泡泡區分
    if (msg.metadata != null && msg.metadata!['kind'] == 'companion_switch') {
      final toId = msg.metadata!['toCompanionId'] as String?;
      final toName = toId != null
          ? (CompanionStore().getById(toId)?.name ?? '')
          : '';
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz_rounded,
                size: 14, color: BridgeDSColors.of(context).accentBlue),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                toName.isNotEmpty ? '已切換夥伴為 $toName' : msg.content,
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(
                      color: BridgeDSColors.of(context).accentBlue,
                      fontWeight: FontWeight.w600,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // [教練 Agent 2026-07-23] 過濾靜默訊息（畫布狀態快照、系統事件等）
    if (msg.metadata != null &&
        (msg.metadata!['silent'] == true ||
            msg.metadata!['kind'] == 'canvas_snapshot' ||
            msg.metadata!['kind'] == 'canvas_event')) {
      return const SizedBox.shrink();
    }

    // ── 非 user 訊息：檢查是否為 card-prefix 系統訊息 ──
    if (!isUser) {
      // 攔截 CapabilityAdvisor 卡片
      if (msg.content.startsWith(capabilityAdvisorCardPrefix)) {
        return _buildAdvisorCardBubble(msg.content);
      }
      // 攔截 CapabilityGap 卡片
      if (msg.content.startsWith(capabilityCardPrefix)) {
        return _buildCapabilityGapBubble(msg.content);
      }
      // 攔截 ProjectDoor 相關卡片
      if (msg.content.startsWith(projectDoorCardPrefix) ||
          msg.content.startsWith(projectContextTransferCardPrefix) ||
          msg.content.startsWith(projectForkCompleteCardPrefix) ||
          msg.content.startsWith(projectForkIntroCardPrefix) ||
          msg.content.startsWith(digitalAssetInvocationCardPrefix) ||
          msg.content.startsWith(digitalAssetReusePlanCardPrefix) ||
          msg.content.startsWith(digitalAssetResultCardPrefix) ||
          msg.content.startsWith(managedFolderRulePickerCardPrefix)) {
        return _buildSystemCardBubble(msg.content);
      }
      // B系列: 攔截畫布匯入卡片 — 自訂渲染含按鈕
      if (msg.content.startsWith(canvasImportCardPrefix)) {
        return _buildCanvasImportBubble(msg.content);
      }
    }

    final cleanContent = isUser
        ? msg.content
        : msg.content
              .replaceAll(
                RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
                '',
              )
              // P5: 隱藏搜尋證據等系統內部文字（桌面版不顯示）
              // 證據文字可能含多行 system prompt，用 [\s\S]*$ 匹配到字串結尾
              .replaceAll(RegExp(r'\n*搜尋證據：[\s\S]*$'), '')
              .replaceAll(RegExp(r'\n*圖片辨識證據：[\s\S]*$'), '')
              .replaceAll(RegExp(r'\n*文件產出證據：[\s\S]*$'), '')
              .replaceAll(RegExp(r'\n*桌面整理證據：[\s\S]*$'), '')
              .trim();

    // 空內容（被 think 標籤佔滿的）不顯示
    if (!isUser && cleanContent.isEmpty) {
      return const SizedBox.shrink();
    }

    // ── 圖片附件：優先讀 Message.imagePath；舊訊息才從文字內的路徑遷移 ──
    if (!isUser) {
      final legacyImageMatch = RegExp(
        r'(/[\w/.\- ]+bridge_media/images/[\w.\-]+\.png)',
      ).firstMatch(cleanContent);
      final imagePath = msg.imagePath ?? legacyImageMatch?.group(1);
      if (imagePath != null && imagePath.isNotEmpty) {
        final imageExecution =
            msg.metadata?['imageExecution'] as Map<String, dynamic>?;
        final imageProvider = imageExecution?['provider']?.toString();
        final imageModel = imageExecution?['model']?.toString();
        final textWithoutPath = legacyImageMatch == null
            ? cleanContent
            : cleanContent
                  .replaceAll(legacyImageMatch.group(1)!, '')
                  .replaceAll(RegExp(r'📷\s*'), '')
                  .trim();
        return GestureDetector(
          onTap: () => AssetActionService.instance.openWithDefaultApp(imagePath),
          onLongPress: () {
            MessageContextMenu.show(
              context: context,
              message: msg,
              showExtendTopic: true,
              onReply: () {
                _controller.setReplyTarget(msg);
                setState(() {});
              },
              onDelete: () {
                _controller.deleteMessage(msg.id);
              },
              onExtendTopic: () {
                _extendTopic(msg);
              },
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(builder: (context) {
                  // [2026-08-26 共視修復] 頭像跟「誰講的話」走——
                  // 用 msg.speakerId 解析發言者（與畫布頁同款正解）。
                  // 之前全部泡泡用當前 active 夥伴 → 切換時歷史泡泡集體變臉。
                  final speaker = msg.speakerId != null
                      ? CompanionStore().getById(msg.speakerId!)
                      : null;
                  // [2026-08-26 共視修復] 舊訊息無 speakerId——標「AI」不冒名
                  // （fallback 當前夥伴會讓切換後歷史泡泡集體變臉）。
                  // [指紋定律 2026-10-16 Blue] native-agent 具名＋品牌紫
                  final name = msg.speakerId == 'native-agent'
                      ? '原生 Agent'
                      : (speaker?.name ?? 'AI');
                  // [小葵 2026-09-15 Blue 令] 指紋章頭像——AgentGlyph 取代首字圓圈
                  // （刀 2 D2.5 的指紋縮圖：同 ID 永遠同一張臉，身份的簽名在場）
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AgentGlyph(
                        companionId: msg.speakerId ?? '',
                        name: name,
                        size: 36,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        style: TierStyle.of(context, Tier.cardCaption)
                            .toTextStyle()
                            .copyWith(color: BridgeDSColors.of(context).textTertiary),
                      ),
                    ],
                  );
                }),
                SizedBox(width: 12),
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.65,
                    ),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: BridgeDSColors.of(context).surfaceElevated,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: const Radius.circular(2),
                        bottomRight: const Radius.circular(12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(imagePath),
                            fit: BoxFit.contain,
                            errorBuilder: (_, error, ___) => Container(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                '🖼️ 圖片載入失敗：$imagePath',
                                style: BridgeDSColors.of(context).caption
                                    .copyWith(
                                      color: BridgeDSColors.of(
                                        context,
                                      ).textSecondary,
                                    ),
                              ),
                            ),
                          ),
                        ),
                        if (textWithoutPath.isNotEmpty) ...[
                          SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: SelectableText(
                              textWithoutPath,
                              style: TierStyle.of(context, Tier.cardBody)
                                  .toTextStyle()
                                  .copyWith(
                                    color: BridgeDSColors.of(
                                      context,
                                    ).textPrimary,
                                    height: 1.5,
                                  ),
                            ),
                          ),
                        ],
                        // 時間 + 真實 execution receipt（文字與圖片分開，不能用設定猜測）
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatMessageTime(msg.timestamp),
                                    style: TierStyle.of(context, Tier.cardBody)
                                        .toTextStyle()
                                        .copyWith(
                                          color: BridgeDSColors.of(
                                            context,
                                          ).textTertiary,
                                        ),
                                  ),
                                  if (msg.model != null &&
                                      msg.model!.isNotEmpty)
                                    Text(
                                      ' · 文字：${resolveShortModelName(msg.model) ?? msg.model}',
                                      style:
                                          TierStyle.of(
                                            context,
                                            Tier.cardBody,
                                          ).toTextStyle().copyWith(
                                            color: BridgeDSColors.of(
                                              context,
                                            ).textMuted,
                                          ),
                                    ),
                                ],
                              ),
                              if (imageProvider != null && imageModel != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '圖片：$imageProvider · $imageModel',
                                    style: TierStyle.of(context, Tier.cardBody)
                                        .toTextStyle()
                                        .copyWith(
                                          color: BridgeDSColors.of(
                                            context,
                                          ).textMuted,
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
              ],
            ),
          ),
        );
      }
    }

    return GestureDetector(
      onLongPress: () {
        MessageContextMenu.show(
          context: context,
          message: msg,
          showExtendTopic: true,
          onReply: () {
            _controller.setReplyTarget(msg);
            // [教練 Agent 2026-08-03] 不需要 setState — ChatController 會 notifyListeners 觸發 rebuild
          },
          onDelete: () {
            _controller.deleteMessage(msg.id);
          },
          onExtendTopic: () {
            _extendTopic(msg);
          },
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisAlignment: isUser
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Builder(builder: (context) {
                // [2026-08-26 共視修復] 頭像跟發言者走（msg.speakerId），
                // 不跟當前 active 夥伴——切換時歷史泡泡不再集體變臉。
                final speaker = msg.speakerId != null
                    ? CompanionStore().getById(msg.speakerId!)
                    : null;
                // [2026-08-26 共視修復] 同上——無 speakerId 標「AI」不冒名
                // [指紋定律 2026-10-16 Blue] native-agent 具名＋品牌紫
                final name = msg.speakerId == 'native-agent'
                    ? '原生 Agent'
                    : (speaker?.name ?? 'AI');
                // [小葵 2026-09-15 Blue 令] 指紋章頭像——AgentGlyph 取代首字圓圈
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AgentGlyph(
                      companionId: msg.speakerId ?? '',
                      name: name,
                      size: 36,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(color: BridgeDSColors.of(context).textTertiary),
                    ),
                  ],
                );
              }),
              SizedBox(width: 12),
            ],
            // [教練 Agent 2026-08-15 使用者回饋] 泡泡+三點包成內層 Row——底部對齊，
            // 三點落在泡泡「右下角」（視覺焦點=訊息結尾處）。icon 14→28 放大一倍。
            Expanded(
              child: Row(
                mainAxisAlignment: isUser
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.65,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isUser
                      ? BridgeDSColors.of(
                          context,
                        ).accentBlue.withValues(alpha: 0.12)
                      : BridgeDSColors.of(context).surfaceElevated,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft: isUser
                        ? const Radius.circular(12)
                        : const Radius.circular(2),
                    bottomRight: isUser
                        ? const Radius.circular(2)
                        : const Radius.circular(12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText(
                      cleanContent,
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textPrimary,
                            height: 1.5,
                          ),
                    ),
                    // [教練 Agent 2026-07-29] 日期 + 模型名稱
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatMessageTime(msg.timestamp),
                            style: TierStyle.of(context, Tier.cardBody)
                                .toTextStyle()
                                .copyWith(
                                  color: BridgeDSColors.of(
                                    context,
                                  ).textTertiary,
                                ),
                          ),
                          // [教練 Agent 2026-07-29] Agent 回覆顯示模型名稱
                          if (!isUser &&
                              msg.model != null &&
                              msg.model!.isNotEmpty) ...[
                            Text(
                              ' · ${resolveShortModelName(msg.model) ?? msg.model}',
                              style: TierStyle.of(context, Tier.cardBody)
                                  .toTextStyle()
                                  .copyWith(
                                    color: BridgeDSColors.of(context).textMuted,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // [教練 Agent 2026-08-15 使用者 提案] 三點選單——泡泡外面旁邊。
            // 時間旁已有模型名稱，更多操作放泡泡外側（視覺不打擾泡泡內容）。
            // 與長按選單同內容：回覆/刪除/延伸話題。
            // [教練 Agent 2026-08-15 使用者回饋] 移進內層 Row（泡泡右下角）、28px。
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: GestureDetector(
                      onTap: () {
                        MessageContextMenu.show(
                          context: context,
                          message: msg,
                          showExtendTopic: true,
                          onReply: () {
                            _controller.setReplyTarget(msg);
                          },
                          onDelete: () {
                            _controller.deleteMessage(msg.id);
                          },
                          onExtendTopic: () {
                            _extendTopic(msg);
                          },
                        );
                      },
                      child: Icon(
                        Icons.more_horiz,
                        size: 28,
                        color: BridgeDSColors.of(context).textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 圖片附件預覽：先在對話中打開，使用者再決定是否另存或刪除。
  /// 延伸話題：以訊息為中心，取上下文建立新對話
  void _extendTopic(Message centerMsg) {
    final conv = _controller.currentConversation;
    if (conv == null) return;

    // 取上下文 5 則
    final contextMessages = MessageContextMenu.extractContextMessages(
      allMessages: conv.messages,
      centerMsg: centerMsg,
    );

    // 取標題
    final title = MessageContextMenu.extractTopicTitle(centerMsg.content);

    // [教練 Agent 2026-08-03] 修復：原本 createNewConversation().then(...) 流程會被
    // switchConversation 開頭的「先保存當前對話」覆蓋，導致 context 沒注入。
    // 改為：既有 controller 新增的 extendTopicWithContext() 直接建立帶 context 的對話。
    // 順帶：完成後通知父層刷新左側 sidebar。
    _controller
        .extendTopicWithContext(
          sourceConv: conv,
          contextMessages: contextMessages,
          title: title,
        )
        .then((_) {
          widget.onConversationCreated?.call();
        });
  }

  /// [教練 Agent 2026-07-23] 格式化訊息時間 — 日期+時間
  String _formatMessageTime(DateTime timestamp) {
    final mo = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$mo/$d $h:$m';
  }

  /// CapabilityAdvisor 進度卡 — 人類可讀的狀態訊息
  Widget _buildAdvisorCardBubble(String rawContent) {
    final jsonStr = rawContent.substring(capabilityAdvisorCardPrefix.length);
    CapabilityAdvisorCardData? card;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        card = CapabilityAdvisorCardData.fromJson(decoded);
      }
    } catch (_) {
      // JSON 解析失敗，fallback 顯示簡短提示
    }

    if (card == null) {
      return _buildSystemCardBubble(rawContent);
    }

    // 根據步驟決定圖示和顏色
    final (icon, color, label) = switch (card.currentStep) {
      CapabilityAdvisorStep.searching => (
        Icons.search,
        BridgeDSColors.of(context).accentBlue,
        '搜尋中',
      ),
      CapabilityAdvisorStep.analyzing => (
        Icons.auto_awesome,
        BridgeDSColors.of(context).accentPurple,
        '分析中',
      ),
      CapabilityAdvisorStep.presentingComparison ||
      CapabilityAdvisorStep.awaitingSelection => (
        Icons.compare_arrows,
        BridgeDSColors.of(context).accentYellow,
        '方案比較',
      ),
      CapabilityAdvisorStep.solutionSelected => (
        Icons.check_circle,
        BridgeDSColors.of(context).accentGreen,
        '已選方案',
      ),
      CapabilityAdvisorStep.verifying => (
        Icons.verified,
        BridgeDSColors.of(context).accentBlue,
        '驗證中',
      ),
      CapabilityAdvisorStep.verified => (
        Icons.verified,
        BridgeDSColors.of(context).accentGreen,
        '已驗證',
      ),
      CapabilityAdvisorStep.returningToTask => (
        Icons.arrow_back,
        BridgeDSColors.of(context).accentBlue,
        '返回任務',
      ),
      CapabilityAdvisorStep.failed => (
        Icons.error_outline,
        BridgeDSColors.of(context).accentRed,
        '失敗',
      ),
      CapabilityAdvisorStep.cancelled => (
        Icons.cancel_outlined,
        BridgeDSColors.of(context).textTertiary,
        '已取消',
      ),
      CapabilityAdvisorStep.browseGapDetected => (
        Icons.info_outline,
        BridgeDSColors.of(context).accentYellow,
        '需要設定',
      ),
      _ => (
        Icons.lightbulb_outline,
        BridgeDSColors.of(context).accentBlue,
        '能力顧問',
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, size: 18, color: color),
          ),
          SizedBox(width: 10),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.55,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: color.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 標題列
                  Row(
                    children: [
                      Icon(icon, size: 14, color: color),
                      SizedBox(width: 6),
                      Text(
                        label,
                        style: TierStyle.of(context, Tier.cardBody)
                            .toTextStyle()
                            .copyWith(
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  // 狀態訊息（人話）
                  if (card.statusMessage.isNotEmpty)
                    Text(
                      card.statusMessage,
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textSecondary,
                            height: 1.4,
                          ),
                    ),
                  // 使用者請求
                  if (card.userRequest.isNotEmpty) ...[
                    SizedBox(height: 6),
                    Text(
                      '請求：${card.userRequest}',
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textTertiary,
                          ),
                    ),
                  ],
                  // 搜尋結果
                  if (card.candidates.isNotEmpty) ...[
                    SizedBox(height: 10),
                    Text(
                      '找到 ${card.candidates.length} 個方案：',
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    SizedBox(height: 4),
                    ...card.candidates
                        .take(5)
                        .map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  c.isRecommended
                                      ? Icons.star
                                      : Icons.circle_outlined,
                                  size: 12,
                                  color: c.isRecommended
                                      ? BridgeDSColors.of(context).accentYellow
                                      : BridgeDSColors.of(
                                          context,
                                        ).textQuaternary,
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.name,
                                        style:
                                            TierStyle.of(
                                              context,
                                              Tier.cardBody,
                                            ).toTextStyle().copyWith(
                                              color: BridgeDSColors.of(
                                                context,
                                              ).textPrimary,
                                              fontWeight: c.isRecommended
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                            ),
                                      ),
                                      if (c.provider.isNotEmpty)
                                        Text(
                                          c.provider,
                                          style:
                                              TierStyle.of(
                                                context,
                                                Tier.cardBody,
                                              ).toTextStyle().copyWith(
                                                color: BridgeDSColors.of(
                                                  context,
                                                ).textTertiary,
                                              ),
                                        ),
                                      if (c.aiNote.isNotEmpty)
                                        Text(
                                          c.aiNote,
                                          style:
                                              TierStyle.of(
                                                context,
                                                Tier.cardBody,
                                              ).toTextStyle().copyWith(
                                                color: BridgeDSColors.of(
                                                  context,
                                                ).textTertiary,
                                                height: 1.3,
                                              ),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                  // 驗證結果
                  if (card.verificationResult != null &&
                      card.verificationResult!.isNotEmpty) ...[
                    SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: (card.verificationPassed ?? false)
                            ? BridgeDSColors.of(
                                context,
                              ).accentGreen.withValues(alpha: 0.1)
                            : BridgeDSColors.of(
                                context,
                              ).accentRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        card.verificationResult!,
                        style: TierStyle.of(context, Tier.cardBody)
                            .toTextStyle()
                            .copyWith(
                              color: (card.verificationPassed ?? false)
                                  ? BridgeDSColors.of(context).accentGreen
                                  : BridgeDSColors.of(context).accentRed,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// CapabilityGap 卡片 — 顯示缺少的能力和引導
  Widget _buildCapabilityGapBubble(String rawContent) {
    final jsonStr = rawContent.substring(capabilityCardPrefix.length);
    CapabilityGapCardData? card;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        card = CapabilityGapCardData.fromJson(decoded);
      }
    } catch (_) {}

    if (card == null) return _buildSystemCardBubble(rawContent);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: BridgeDSColors.of(
              context,
            ).accentYellow.withValues(alpha: 0.15),
            child: Icon(
              Icons.info_outline,
              size: 18,
              color: BridgeDSColors.of(context).accentYellow,
            ),
          ),
          SizedBox(width: 10),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.55,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: BridgeDSColors.of(
                    context,
                  ).accentYellow.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    style: TierStyle.of(context, Tier.cardBody)
                        .toTextStyle()
                        .copyWith(
                          color: BridgeDSColors.of(context).textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  SizedBox(height: 6),
                  if (card.status.isNotEmpty)
                    Text(
                      card.status,
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textSecondary,
                          ),
                    ),
                  if (card.missing.isNotEmpty) ...[
                    SizedBox(height: 4),
                    Text(
                      '缺少：${card.missing}',
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).accentYellow,
                          ),
                    ),
                  ],
                  if (card.steps.isNotEmpty) ...[
                    SizedBox(height: 8),
                    ...card.steps.map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.arrow_right,
                              size: 14,
                              color: BridgeDSColors.of(context).textTertiary,
                            ),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                s,
                                style: TierStyle.of(context, Tier.cardBody)
                                    .toTextStyle()
                                    .copyWith(
                                      color: BridgeDSColors.of(
                                        context,
                                      ).textTertiary,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// B系列: 畫布匯入卡片 — Agent 摘要 + 建議名稱 + 按鈕
  Widget _buildCanvasImportBubble(String rawContent) {
    final jsonStr = rawContent.substring(canvasImportCardPrefix.length);
    CanvasImportCardData? card;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        card = CanvasImportCardData.fromJson(decoded);
      }
    } catch (_) {}

    if (card == null) {
      return _buildSystemCardBubble(rawContent);
    }
    final data = card;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: BridgeDSColors.of(
              context,
            ).accentPurple.withValues(alpha: 0.15),
            child: Icon(
              Icons.account_tree_outlined,
              size: 16,
              color: BridgeDSColors.of(context).accentPurple,
            ),
          ),
          SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: BridgeDSColors.of(
                    context,
                  ).accentPurple.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 標題列
                  Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 14,
                        color: BridgeDSColors.of(context).accentPurple,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Agent 建議匯入畫布',
                        style: TierStyle.of(context, Tier.cardBody)
                            .toTextStyle()
                            .copyWith(
                              color: BridgeDSColors.of(context).accentPurple,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  // Agent 摘要
                  if (data.summary.isNotEmpty)
                    SelectableText(
                      data.summary,
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textSecondary,
                            height: 1.4,
                          ),
                    ),
                  if (data.suggestedTitle.isNotEmpty) ...[
                    SizedBox(height: 6),
                    Text(
                      '建議名稱：${data.suggestedTitle}',
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textTertiary,
                          ),
                    ),
                  ],
                  SizedBox(height: 10),
                  // 按鈕列
                  if (widget.onCanvasImport != null)
                    Row(
                      children: [
                        Expanded(
                          child: _canvasImportButton(
                            icon: Icons.add_circle_outline,
                            label: '新建畫布',
                            color: BridgeDSColors.of(context).accentGreen,
                            onTap: () => widget.onCanvasImport!(
                              data.summary,
                              data.suggestedTitle,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _canvasImportButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            SizedBox(width: 6),
            Text(
              label,
              style: TierStyle.of(context, Tier.cardBody)
                  .toTextStyle()
                  .copyWith(color: color, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  /// 通用系統卡片 — 對於尚未客製渲染的 card prefix，顯示標題 + 可展開內容
  Widget _buildSystemCardBubble(String rawContent) {
    // 嘗試找出 card 類型名稱
    String cardType = '系統訊息';
    for (final entry in _cardTypeLabels.entries) {
      if (rawContent.startsWith(entry.key)) {
        cardType = entry.value;
        break;
      }
    }

    // 嘗試從 JSON 中提取有意義的摘要和完整內容
    String summary = '';
    String fullJson = '';
    final colonIdx = rawContent.indexOf(':');
    if (colonIdx >= 0) {
      final jsonPart = rawContent.substring(colonIdx + 1);
      try {
        final decoded = jsonDecode(jsonPart);
        if (decoded is Map<String, dynamic>) {
          // 嘗試常見的摘要欄位
          summary =
              decoded['title']?.toString() ??
              decoded['status']?.toString() ??
              decoded['statusMessage']?.toString() ??
              decoded['ideaSummary']?.toString() ??
              decoded['planSummary']?.toString() ??
              decoded['summary']?.toString() ??
              '';
          // 完整 JSON 用於展開顯示
          fullJson = const JsonEncoder.withIndent('  ').convert(decoded);
        }
      } catch (_) {
        fullJson = jsonPart;
      }
    }

    return _SystemCardBubble(
      cardType: cardType,
      summary: summary,
      fullContent: fullJson,
    );
  }

  /// Card prefix → 人類可讀標籤
  static const _cardTypeLabels = {
    capabilityCardPrefix: '能力資訊',
    capabilityAdvisorCardPrefix: '能力顧問',
    projectDoorCardPrefix: '專案門',
    projectContextTransferCardPrefix: '專案轉移',
    digitalAssetInvocationCardPrefix: '資產引用',
    digitalAssetReusePlanCardPrefix: '資產重用',
    digitalAssetResultCardPrefix: '資產結果',
    projectForkCompleteCardPrefix: '專案分叉',
    projectForkIntroCardPrefix: '專案分叉',
    managedFolderRulePickerCardPrefix: '資料夾規則',
    canvasImportCardPrefix: '畫布匯入',
  };

  /// [教練 Agent 2026-07-29] 工具名中文翻譯
  static const _toolNameTranslations = {
    'read_source_file': '讀取檔案',
    'patch_source_file': '修改檔案',
    'run_terminal': '執行指令',
    'restart_app': '重啟 App',
    'canvas_get_state': '查看畫布',
    'canvas_place': '放置節點',
    'canvas_connect': '連接節點',
    'canvas_remove_node': '移除節點',
    'canvas_remove': '移除節點',
    'canvas_send_chat': '畫布對話',
    'canvas_get_annotations': '查看標注',
    'canvas_execute': '執行工作流',
    'screen_capture': '截取畫面',
    'generate_image': '生成圖片',
    'browse': '瀏覽網頁',
    'vision': '視覺分析',
    'document': '文件處理',
    'local_vision_analyze': '本地視覺分析',
    'local_code_generate': '本地程式碼生成',
    'video_download': '下載影片',
    'frame_extract': '影片截幀',
    'audio_transcribe': '語音轉文字',
    'delegate_subagent': '分派子代理',
    'delegate_batch': '批次分派',
  };

  static String _translateToolName(String? name) {
    if (name == null || name.isEmpty) return '';
    return _toolNameTranslations[name] ?? name;
  }

  /// [教練 Agent P0.5b 2026-08-08] 圖片任務進度時間線
  /// 顯示 adapter_selected → request_about_to_send → response_received → media_persisted
  /// 每個事件一行，帶 ✓ 或 spinner，使用者可以看到真實執行邊界
  Widget _buildImageProgressTimeline() {
    final events = _controller.imageProgressEvents;
    final isLastEvent = (BridgeActionProgressEvent event) =>
        events.indexOf(event) == events.length - 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 標題
          Row(
            children: [
              Icon(Icons.image_outlined,
                  size: 14, color: BridgeDSColors.of(context).textTertiary),
              SizedBox(width: 6),
              Text(
                '圖片任務',
                style: TierStyle.of(context, Tier.cardBody)
                    .toTextStyle()
                    .copyWith(
                      color: BridgeDSColors.of(context).textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          SizedBox(height: 6),
          // 事件序列
          ...events.map((event) {
            final isLast = isLastEvent(event);
            final isDone = !isLast;
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  // 狀態 icon
                  if (isDone)
                    Icon(Icons.check_circle,
                        size: 12, color: BridgeDSColors.of(context).accentGreen)
                  else
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: BridgeDSColors.of(context).accentBlue,
                      ),
                    ),
                  SizedBox(width: 8),
                  // 事件文字
                  Expanded(
                    child: Text(
                      event.userLabel,
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            color: isLast
                                ? BridgeDSColors.of(context).textSecondary
                                : BridgeDSColors.of(context).textTertiary,
                            fontSize: 12,
                          ),
                    ),
                  ),
                  // provider/model 標籤
                  if (event.provider != null)
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: BridgeDSColors.of(context).surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        event.model ?? event.provider!,
                        style: TextStyle(
                          fontSize: 10,
                          color: BridgeDSColors.of(context).textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAgentLoopProgress() {
    final toolName = _agentLoopToolName;
    final toolStatus = _agentLoopToolStatus;
    final stage = _agentLoopStage;
    final stageDetail = _agentLoopStageDetail;

    // [教練 Agent 2026-08-07] 根據 stage 決定顯示文字
    // stage 優先於舊的 toolName/toolStatus 邏輯
    String actionLabel;
    String statusLabel;
    Color statusColor;

    if (stage == 'thinking') {
      actionLabel = stageDetail ?? '正在思考...';
      statusLabel = '';
      statusColor = BridgeDSColors.of(context).textSecondary;
    } else if (stage == 'tool_start') {
      actionLabel = stageDetail ?? '正在執行：${_translateToolName(toolName)}';
      statusLabel = '執行中';
      statusColor = BridgeDSColors.of(context).textSecondary;
    } else if (stage == 'tool_done') {
      actionLabel = _translateToolName(toolName);
      statusLabel = stageDetail ?? '完成';
      statusColor = stageDetail == '失敗'
          ? BridgeDSColors.of(context).accentRed
          : BridgeDSColors.of(context).accentGreen;
    } else if (stage == 'timeout') {
      actionLabel = stageDetail ?? '等待超時，正在調整...';
      statusLabel = '超時';
      statusColor = BridgeDSColors.of(context).accentYellow;
    } else if (stage == 'error') {
      actionLabel = stageDetail ?? '發生錯誤';
      statusLabel = '錯誤';
      statusColor = BridgeDSColors.of(context).accentRed;
    } else {
      // fallback：舊邏輯
      // [小葵 2026-09-22 修 Bug] 任務完成後 toolName/toolStatus 已被清空，
      // 舊邏輯會永遠顯示「正在整理回應／處理中」——完成態改顯示已完成。
      if (_agentLoopFinished) {
        actionLabel = '回應完成';
        statusLabel = '已完成';
        statusColor = BridgeDSColors.of(context).accentGreen;
      } else {
        actionLabel = toolName == null
            ? '正在整理回應'
            : _translateToolName(toolName);
        statusLabel = toolStatus == 'failed'
            ? '未完成'
            : toolStatus == 'success'
            ? '完成'
            : '處理中';
        statusColor = toolStatus == 'failed'
            ? BridgeDSColors.of(context).accentRed
            : toolStatus == 'success'
            ? BridgeDSColors.of(context).accentGreen
            : BridgeDSColors.of(context).textSecondary;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
          // [教練 Agent 2026-08-07] icon 也根據 stage 變化
          if (stage == 'thinking')
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: statusColor,
              ),
            )
          else
            Icon(
              stage == 'error'
                  ? Icons.error_outline
                  : stage == 'timeout'
                  ? Icons.schedule_outlined
                  : toolStatus == 'failed'
                  ? Icons.error_outline
                  : toolName == null
                  ? Icons.auto_awesome_outlined
                  : Icons.build_outlined,
              size: 16,
              color: statusColor,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              actionLabel,
              style: TierStyle.of(context, Tier.cardBody)
                  .toTextStyle()
                  .copyWith(
                    color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (statusLabel.isNotEmpty)
            Text(
            statusLabel,
            style: TierStyle.of(
              context,
              Tier.cardBody,
            ).toTextStyle().copyWith(color: statusColor),
          ),
            ],
          ),
          // [小葵 2026-09-22 修 Bug] 移除重複的舊 log 渲染段（與下方
        // 「看細節」段重複渲染導致面板混亂、點擊無效的視覺干擾）。
        // [小葵 2026-09-19 過程直播] 最近近況——關鍵動態，非工程流水帳
        if (_agentLoopLog.isNotEmpty) ...[
          const SizedBox(height: 6),
          if (!_agentLoopDetailExpanded) ...[
            // 收合：最近 3 條
            ..._agentLoopLog.length <= 3
                ? _agentLoopLog.map(_buildLoopLogLine)
                : _agentLoopLog.sublist(_agentLoopLog.length - 3)
                    .map(_buildLoopLogLine),
          ] else ...[
            // 展開：全部（捲動區）
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                shrinkWrap: true,
                children: _agentLoopLog.map(_buildLoopLogLine).toList(),
              ),
            ),
          ],
          const SizedBox(height: 4),
          // 點開/收起切換
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => setState(
                  () => _agentLoopDetailExpanded = !_agentLoopDetailExpanded),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _agentLoopDetailExpanded ? '收起細節' : '看細節',
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(color: BridgeDSColors.of(context).textTertiary),
                  ),
                  Icon(
                    _agentLoopDetailExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 14,
                    color: BridgeDSColors.of(context).textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ],
        ],
      ),
    );
  }

  /// [小葵 2026-09-19 過程直播] 單行近況
  Widget _buildLoopLogLine(String line) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        line,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TierStyle.of(context, Tier.cardCaption)
            .toTextStyle()
            .copyWith(color: BridgeDSColors.of(context).textSecondary),
      ),
    );
  }

  /// 選擇圖片並發送
  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (!kIsWeb && file.path != null) {
          final text = _messageController.text.trim();
          if (text.isNotEmpty) {
            _messageController.clear();
            await _controller.sendMessage(imagePath: file.path);
          } else {
            await _controller.sendMessage(imagePath: file.path);
          }
        }
      }
    } catch (e) {
      debugPrint('[DesktopChatPanel] 圖片選擇失敗: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final conv = _controller.currentConversation;
    final messages = conv?.messages ?? [];

    // P4-r2: 移除內部對話列表 sidebar，對話列表已統一在左側 sidebar
    return Column(
      children: [
        // 訊息列表
        Expanded(
          child: messages.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return _buildMessageBubble(msg);
                  },
                ),
        ),
        // Loading 指示
        if (_controller.isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      BridgeDSColors.of(context).accentBlue,
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  _activeCompanion?.name ?? '夥伴',
                  style: TierStyle.of(context, Tier.cardBody)
                      .toTextStyle()
                      .copyWith(color: BridgeDSColors.of(context).textTertiary),
                ),
                SizedBox(width: 4),
                Text(
                  _controller.imageProgressLabel ?? '正在思考…',
                  style: TierStyle.of(context, Tier.cardBody)
                      .toTextStyle()
                      .copyWith(color: BridgeDSColors.of(context).textTertiary),
                ),
              ],
            ),
          ),
        // [教練 Agent P0.5b 2026-08-08] 圖片任務進度序列
        if (_controller.isLoading && _controller.imageProgressEvents.isNotEmpty)
          _buildImageProgressTimeline(),
        // Agent Loop 進度條
        // [教練 Agent 2026-08-09] 修正：thinking 階段也要顯示
        // 舊條件 _agentLoopTurn != null 只在 tool call 時觸發，
        // 但 LLM 思考階段沒有 tool call → 進度條消失
        if ((_controller.isLoading &&
                (_agentLoopTurn != null || _agentLoopStage != null)) ||
            _agentLoopFinished)
          _buildAgentLoopProgress(),
        // 輸入框（含 VoiceStatusIndicator + VoiceButton）
        _buildInputBar(),
      ],
    );
  }

  /// 左側對話列表
  Widget _buildConversationSidebar() {
    final conversations = _controller.conversations;
    final currentId = _controller.currentConversation?.id;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        border: Border(
          right: BorderSide(color: BridgeDSColors.of(context).borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題 + 新增按鈕
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
            child: Row(
              children: [
                Text(
                  '對話',
                  style: TierStyle.of(
                    context,
                    Tier.appHeadline,
                  ).toTextStyle().copyWith(fontSize: 18),
                ),
                Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  color: BridgeDSColors.of(context).textTertiary,
                  tooltip: '新對話',
                  onPressed: () => _controller.createNewConversation(),
                ),
              ],
            ),
          ),
          // 對話列表
          Expanded(
            child: conversations.isEmpty
                ? Center(
                    child: Text(
                      '沒有對話',
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textMuted,
                          ),
                    ),
                  )
                : ListView.builder(
                    itemCount: conversations.length + 1, // +1 = 回收桶列
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemBuilder: (context, index) {
                      if (index == conversations.length) {
                        return _buildTrashEntry(); // [小葵 2026-09-21] 回收桶（Blue 選 A）
                      }
                      final conv = conversations[index];
                      final isActive = conv.id == currentId;
                      return _buildConversationItem(conv, isActive);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationItem(Conversation conv, bool isActive) {
    final lastMsg = conv.messages.isNotEmpty
        ? conv.messages.last.content
        : '（空對話）';
    final lastMsgPreview = lastMsg.length > 40
        ? '${lastMsg.substring(0, 40)}…'
        : lastMsg;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _controller.switchConversation(conv),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? BridgeDSColors.of(context).surfaceElevated
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                conv.title.isNotEmpty ? conv.title : '未命名對話',
                style: TierStyle.of(context, Tier.cardBody)
                    .toTextStyle()
                    .copyWith(
                      color: isActive
                          ? BridgeDSColors.of(context).textPrimary
                          : BridgeDSColors.of(context).textSecondary,
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 2),
              Text(
                lastMsgPreview,
                style: TierStyle.of(context, Tier.cardBody)
                    .toTextStyle()
                    .copyWith(color: BridgeDSColors.of(context).textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [小葵 2026-09-21] 回收桶入口（Blue 選 A：對話列表最底）——
  /// 點開看被刪對話、逐則還原。刪除≠銷毀（主權鐵則：絕不刪對話記憶）。
  Widget _buildTrashEntry() {
    return ExpansionTile(
      leading: Icon(
        Icons.delete_outline,
        size: 18,
        color: BridgeDSColors.of(context).textTertiary,
      ),
      title: Text(
        '回收桶',
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
              color: BridgeDSColors.of(context).textSecondary,
            ),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      children: [
        FutureBuilder<List<Conversation>>(
          future: ConversationStore.listTrash(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final trash = snapshot.data!;
            if (trash.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '回收桶是空的',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                        color: BridgeDSColors.of(context).textMuted,
                      ),
                ),
              );
            }
            return Column(
              children: [
                for (final conv in trash)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(
                      conv.title.isNotEmpty ? conv.title : '未命名對話',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textSecondary,
                          ),
                    ),
                    subtitle: Text(
                      '${conv.messages.length} 則訊息',
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            fontSize: 11,
                            color: BridgeDSColors.of(context).textMuted,
                          ),
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final ok = await ConversationStore.restore(conv.id);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok
                                ? '已還原「${conv.title}」'
                                : '還原失敗（回收桶找不到此對話）'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        if (ok) setState(() {}); // 觸發列表刷新
                      },
                      child: const Text('還原'),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: BridgeDSColors.of(context).surfaceElevated,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 28,
              color: BridgeDSColors.of(context).accentBlue,
            ),
          ),
          SizedBox(height: BridgeDS.spaceLG),
          Text(
            '開始一段新對話',
            style: TierStyle.of(context, Tier.appHeadline)
                .toTextStyle()
                .copyWith(color: BridgeDSColors.of(context).textSecondary),
          ),
          SizedBox(height: BridgeDS.spaceSM),
          Text(
            '在下方輸入訊息，或從左側選擇對話',
            style: BridgeDSColors.of(
              context,
            ).body.copyWith(color: BridgeDSColors.of(context).textTertiary),
          ),
        ],
      ),
    );
  }

  /// 底部輸入框 — 桌面原生風格
  ///
  /// [教練 Agent 2026-07-28] VoiceButton 在輸入框右側，不跳位、不遮擋發送鍵。
  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        border: Border(
          top: BorderSide(color: BridgeDSColors.of(context).borderSubtle),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // VoiceStatusIndicator（對談中才顯示，不影響按鈕位置）
          if (_currentVoiceEngine.isConversationActive)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: VoiceStatusIndicator(mode: _voiceMode),
              ),
            ),
          // [小葵 2026-08-30] 快軌重點字幕——語音即時模式的視覺第二通道：
          // 快軌重點出聲的同時顯示文字，慢軌完整回答進面板後清除。
          if (_realtimeSubtitle.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context)
                    .accentBlue
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: BridgeDSColors.of(context)
                      .accentBlue
                      .withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.bolt,
                    size: 16,
                    color: BridgeDSColors.of(context).accentBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _realtimeSubtitle,
                      style: TierStyle.of(context, Tier.listItemSubtitle)
                          .toTextStyle(),
                    ),
                  ),
                ],
              ),
            ),
          // [教練 Agent 2026-08-03] 回覆指定 banner — 獨立一行（在輸入框 Row 上方）
          if (_controller.replyTarget != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(
                  context,
                ).accentBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: BridgeDSColors.of(
                    context,
                  ).accentBlue.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.reply_rounded,
                    size: 14,
                    color: BridgeDSColors.of(context).accentBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _controller.replyTarget!.role == 'user'
                        ? '回覆 你的訊息'
                        : '回覆 AI 訊息',
                    style: TierStyle.of(context, Tier.cardBody)
                        .toTextStyle()
                        .copyWith(
                          fontWeight: FontWeight.w600,
                          color: BridgeDSColors.of(context).accentBlue,
                        ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _controller.replyTarget!.content.length > 50
                          ? '${_controller.replyTarget!.content.substring(0, 50)}...'
                          : _controller.replyTarget!.content,
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _controller.clearReplyTarget(),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: BridgeDSColors.of(context).textMuted,
                    ),
                  ),
                ],
              ),
            ),
          // 輸入框 Row（原本結構）
          Row(
            children: [
              // Agent 模型選擇器
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AgentModelSelector(
                  onProviderChanged: () {
                    _controller.refreshLocalModelState();
                  },
                ),
              ),
              if (_controller.isUsingLocalModel)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.memory,
                    size: 16,
                    color: BridgeDSColors.of(context).accentPurple,
                  ),
                ),
              // 新增對話
              // [教練 Agent 2026-08-03] 修復：原本用外層 Tooltip widget 包覆 IconButton，
              // 內含 GestureDetector(longPress) 跟 IconButton 內建的 tap 手勢競爭，
              // 在快速點擊時 onPressed 不觸發。改用 IconButton 自帶的 `tooltip:` 參數。
              // [教練 Agent 2026-08-03] 順帶：完成後通知父層刷新左側 sidebar。
              IconButton(
                tooltip: '新增對話',
                icon: Icon(
                  Icons.add_comment_outlined,
                  size: 18,
                  color: BridgeDSColors.of(context).textTertiary,
                ),
                onPressed: () async {
                  await _controller.createNewConversation();
                  widget.onConversationCreated?.call();
                },
              ),
              // 上傳圖片/檔案
              // [教練 Agent 2026-08-03] 同一個 anti-pattern 修正：去掉外層 Tooltip 包覆。
              IconButton(
                tooltip: '上傳圖片或檔案',
                icon: Icon(
                  Icons.attach_file_outlined,
                  size: 18,
                  color: BridgeDSColors.of(context).textTertiary,
                ),
                onPressed: _pickImage,
              ),
              // [教練 Agent 2026-08-03] 改成像畫布頁一樣的格式：送出按鈕在輸入欄外面
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(context).surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: BridgeDSColors.of(context).borderSubtle,
                    ),
                  ),
                  // [教練 Agent 2026-08-03] Stack 包 TextField + 浮層（語音 partial 文字）
                  child: Stack(
                    children: [
                      TextField(
                        key: const ValueKey('desktop-chat-message-input'),
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        autofocus: true,
                        enabled: true,
                        style: TierStyle.of(context, Tier.cardBody)
                            .toTextStyle()
                            .copyWith(
                              color: BridgeDSColors.of(context).textPrimary,
                            ),
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: '輸入訊息…',
                          hintStyle: BridgeDSColors.of(context).caption
                              .copyWith(
                                color: BridgeDSColors.of(context).textMuted,
                              ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4), // [教練 Agent 2026-08-03] 縮小間距 8→4
              // [教練 Agent 2026-08-03] 送出按鈕在輸入欄外面（跟畫布頁格式一致）
              // - 發送：永遠可用
              // - 停止：只在 isLoading 時顯示
              if (_controller.isLoading)
                _buildChatSendButton(
                  icon: Icons.stop_circle,
                  color: BridgeDSColors.of(context).accentRed,
                  tooltip: '停止',
                  onPressed: () => _controller.stopAgent(),
                ),
              const SizedBox(width: 4), // [教練 Agent 2026-08-03] 等距 4px
              _buildChatSendButton(
                icon: Icons.send,
                color: BridgeDSColors.of(context).accentBlue,
                tooltip: '送出',
                onPressed: () => _controller.sendMessage(),
              ),
              const SizedBox(width: 4), // [教練 Agent 2026-08-03] 等距 4px
              // VoiceButton 永遠在最右邊
              // [教練 Agent 2026-08-03] 短按 = 雙向對話，長按 = 語音輸入文字（iMessage 風格）
              VoiceButton(
                mode: _voiceMode,
                onToggle: _toggleVoiceConversation, // 短按
                onLongPressStart: _startVoiceInput, // 長按開始
                onLongPressEnd: _stopVoiceInput, // 長按結束
                volume:
                    _micVolume, // [教練 Agent 2026-08-03] 傳 ValueNotifier（不重建 panel）
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// D11: 可折疊的系統卡片 — 預設只顯示標題，點擊可展開完整內容
class _SystemCardBubble extends StatefulWidget {
  final String cardType;
  final String summary;
  final String fullContent;

  _SystemCardBubble({
    required this.cardType,
    required this.summary,
    required this.fullContent,
  });

  @override
  State<_SystemCardBubble> createState() => _SystemCardBubbleState();
}

class _SystemCardBubbleState extends State<_SystemCardBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: BridgeDSColors.of(context).surfaceHover,
            child: Icon(
              Icons.memory,
              size: 16,
              color: BridgeDSColors.of(context).textTertiary,
            ),
          ),
          SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: BridgeDSColors.of(context).borderSubtle,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 標題列 + 展開按鈕
                  GestureDetector(
                    onTap: widget.fullContent.isEmpty
                        ? null
                        : () => setState(() => _expanded = !_expanded),
                    child: Row(
                      children: [
                        Text(
                          widget.cardType,
                          style: TierStyle.of(context, Tier.cardBody)
                              .toTextStyle()
                              .copyWith(
                                color: BridgeDSColors.of(context).textTertiary,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        if (widget.summary.isNotEmpty) ...[
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.summary,
                              style: TierStyle.of(context, Tier.cardBody)
                                  .toTextStyle()
                                  .copyWith(
                                    color: BridgeDSColors.of(
                                      context,
                                    ).textSecondary,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        if (widget.fullContent.isNotEmpty) ...[
                          SizedBox(width: 4),
                          Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 16,
                            color: BridgeDSColors.of(context).textQuaternary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 展開內容
                  if (_expanded && widget.fullContent.isNotEmpty) ...[
                    SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: BridgeDSColors.of(context).canvas,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: BridgeDSColors.of(context).borderSubtle,
                          width: 0.5,
                        ),
                      ),
                      child: SelectableText(
                        widget.fullContent,
                        style: TierStyle.of(context, Tier.cardBody)
                            .toTextStyle()
                            .copyWith(
                              color: BridgeDSColors.of(context).textTertiary,
                              fontFamily: 'monospace',
                              height: 1.3,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
