// canvas_chat_panel.dart
// F4 右側聊天面板 — Agent 共視對話
// B2 Phase 1.5 Open Canvas 統一設計
//
// 設計文件: open-canvas-unified-design.md §3.3
//
// 職責：
// 1. 顯示當前對話訊息（精簡版，無卡片系統）
// 2. 輸入並發送訊息
// 3. 顯示 Companion Avatar + 名稱
//
// 這是 DesktopChatPanel 的精簡版 — 移除 pasteboard watcher、語音輸入、
// Agent Loop 進度條、卡片系統。只保留：訊息列表 + 輸入框 + 發送。

import 'package:bridge_app/services/vault/template_tutorial_service.dart';
import 'package:bridge_app/services/agent_loop/mcp_canvas_tools.dart'; // [v212] McpCanvasExecutor
import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:bridge_app/controllers/chat_controller.dart';
import 'package:bridge_app/models/chat_card_data.dart';
import 'package:bridge_app/models/companion.dart';
import 'package:bridge_app/models/conversation.dart';
import 'package:bridge_app/services/companion_store.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/widgets/chat/agent_model_selector.dart';
// ── Voice AI 引擎 + handler ──
import 'package:bridge_app/screens/chat/handlers/chat_tts_handler.dart';
import 'package:bridge_app/screens/chat/handlers/voice_speech_handler.dart'; // [教練 Agent 2026-07-28] Voice AI 語音辨識
import 'package:bridge_app/services/voice/voice_engine.dart';
import 'package:bridge_app/services/voice/native_audio_bytes_player.dart';

import 'package:bridge_app/services/voice/voice_live_controller.dart';
// [教練 Agent 2026-08-03] C4: 載入夥伴語音設定
import 'package:bridge_app/services/voice/companion_voice_settings_store.dart';
import 'package:bridge_app/services/voice/companion_voice_settings.dart';
import 'package:bridge_app/services/voice/voice_state_machine.dart' show VoiceState;
import '../../widgets/common/hover_glow_circle_button.dart';
import '../../widgets/voice/voice_button.dart';
import '../../widgets/voice/voice_status_indicator.dart';
import '../../widgets/chat/message_context_menu.dart';
import '../../services/bridge_action_progress.dart';
import '../../services/local_model_runtime_service.dart'; // [教練 Agent 2026-08-14] resolveShortModelName
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // [教練 Agent 2026-07-29] HardwareKeyboard / LogicalKeyboardKey / KeyEvent
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../../services/chat_modes.dart'; // [聊天模式 B 線 2026-10-21] 畫布對話欄模式下拉（上傳右邊，Blue 指定）
import '../../theme/bridge_design_system.dart';

/// Open Canvas 第四欄 — 精簡聊天面板。
///
/// 建立自己的 [ChatController] 實例，只負責訊息顯示和發送。
/// 不含 pasteboard watcher、語音輸入、Agent Loop 進度條、卡片系統。
class CanvasChatPanel extends StatefulWidget {
  /// D11-6: 允許父層透過 key 存取 state，觸發執行計畫
  const CanvasChatPanel({super.key, this.onControllerReady, this.selfCaptureKey, this.canvasId, this.onCanvasImport, this.mcpCanvasExecutor});

  /// D11-6: 當 ChatController 初始化完成後呼叫，讓父層可以拿到引用
  final void Function(ChatController controller)? onControllerReady;

  /// [v212 小葵 2026-09-02] MCP 畫布執行器——畫布對話的 Agent 靠這個
  /// 拿到 canvas_add_node/canvas_connect 等畫布主控工具。
  /// 之前沒接：executor=null → 工具整批不註冊 → Agent 只能看不能動
  /// （Blue 測試抓包：Agent 自陳「沒有建節點/連線的工具」）。
  final McpCanvasExecutor? mcpCanvasExecutor;

  /// [2026-07-20] App 自拍 key——讓 screen_capture 走 FlutterSelfCaptureExecutor
  /// 不傳則 fallback 到 MacScreenCaptureExecutor（會截桌面而非 App）
  final GlobalKey? selfCaptureKey;

  /// [教練 Agent 2026-07-23] 綁定的畫布 ID——載入此畫布的 projectCanvas 對話
  final String? canvasId;

  /// B系列: Agent 發出畫布匯入卡片時，使用者點擊按鈕後觸發。
  final void Function(String summary, String suggestedTitle)? onCanvasImport;

  @override
  State<CanvasChatPanel> createState() => _CanvasChatPanelState();
}

class _CanvasChatPanelState extends State<CanvasChatPanel> {
  late final ChatController _controller;
  final _inputController = TextEditingController();
  final _focusNode = FocusNode(debugLabel: 'canvas-chat-input');
  final _scrollController = ScrollController();
  Companion? _companion;

  // [教練 Agent 2026-07-22] Phase H — 回覆指定訊息的目標
  Message? _replyTargetMessage;

  // ── Voice AI handler + 引擎 ──
  late final ChatTtsHandler _tts;
  late VoiceEngine _voiceEngine;
  late final NativeAudioBytesPlayer _audioPlayer;

  // [教練 Agent 2026-08-03] C4: 當前夥伴的語音設定（建構 _voiceEngine 時載入）
  CompanionVoiceSettings? _voiceSettings;

  // [教練 Agent 2026-07-28] Voice AI 專用語音辨識 — 只驅動 VoiceEngine，不碰輸入框
  late final VoiceSpeechHandler _voiceSpeech;

  // [教練 Agent 2026-08-03] 雙向溝通中央控制器
  VoiceLiveController? _voiceLive;

  /// [教練 Agent 2026-08-03] STT 狀態 → VoiceMode
  /// 純 STT 語音輸入：按下開始 → 講話 → 再按停止 → 文字送出
  /// - idle → 沒在錄音
  /// - listening → 正在錄音（按下變紅 + 波形動）
  /// - thinking/speaking → 不會觸發（純 STT 模式）
  VoiceMode get _voiceMode => _voiceSpeech.isListening ? VoiceMode.listening : VoiceMode.idle;

  /// [教練 Agent 2026-08-03] 麥克風真實音量（0.0~1.0）— 從 voice_speech_handler 訂閱
  /// 用 ValueNotifier — stream.listen 直接寫 value，不 setState（避免整個 panel 重建）
  final ValueNotifier<double> _micVolume = ValueNotifier<double>(0.0);
  StreamSubscription<double>? _micVolumeSub;

  /// [教練 Agent 2026-08-03] 語音開始前輸入框已有的文字（語音中 partial 會疊加上去）
  String _draftBeforeVoice = '';
  StreamSubscription<String>? _partialTextSub;

  @override
  void initState() {
    super.initState();

    _controller = ChatController();
    // [v212] 注入 MCP 畫布執行器——讓 agent loop 註冊畫布主控工具
    _controller.mcpCanvasExecutor = widget.mcpCanvasExecutor;

    // ── Voice AI handler 初始化 ──
    _tts = ChatTtsHandler(onError: _showError);
    _tts.init();
    _audioPlayer = NativeAudioBytesPlayer();

    // ── Voice AI 引擎初始化 ──
    // VoiceEngine 接上既有的 ChatTtsHandler 做朗讀，
    // 並透過 AgentLoopTrigger 啟動背景運算（新三層回應架構）。
    _loadVoiceSettingsAndBuild();  // [教練 Agent 2026-08-03] C4: 異步載入
  // [教練 Agent 2026-08-03] C4: _voiceEngine 在 _loadVoiceSettingsAndBuild 內建構
  // 暫時建構一個 fallback（會被 async 載入覆蓋）
  _voiceEngine = VoiceEngine(
      onSpeak: (text) => _tts.speak(text),
      onStopSpeaking: () => _tts.stop(),
      onPlayAudioBytes: (bytes) => _audioPlayer.play(bytes),
      onAgentLoopTrigger: ({
        required userText,
        required onProgress,
        required onComplete,
      }) {
        _triggerAgentLoopForVoice(
          userText: userText,
          onProgress: onProgress,
          onComplete: onComplete,
        );
      },
    );
    // VoiceEngine 狀態變化時更新 UI
    _voiceEngine.state.addListener(_onVoiceStateChanged);

    // [教練 Agent 2026-07-28] Voice AI 專用語音辨識 — 只驅動 VoiceEngine
    // onError 時顯示麥克風權限提示 SnackBar
    _voiceSpeech = VoiceSpeechHandler(
      voiceEngine: _voiceEngine,
      onError: (msg) {
        debugPrint('[CanvasChatPanel] VoiceSpeech: $msg');
        // 麥克風權限相關錯誤 → 顯示權限提示
        if (msg.contains('麥克風') || msg.contains('權限') || msg.contains('permission')) {
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
      if (!_inputController.text.contains(text) || _draftBeforeVoice.isNotEmpty) {
        // 保留語音前文字 + 當前 partial
        _inputController.text = _draftBeforeVoice.isEmpty
            ? text
            : '$_draftBeforeVoice$text';
        // 游標移到末尾
        _inputController.selection = TextSelection.collapsed(
          offset: _inputController.text.length,
        );
      }
    });

    // [2026-07-20] 注入 App 自拍 key——讓 screen_capture 走 FlutterSelfCaptureExecutor
    if (widget.selfCaptureKey != null) {
      _controller.setSelfCaptureKey(widget.selfCaptureKey!);
    }

    // [教練 Agent 2026-08-08] 統一 stage callback——三個對話框行為一致
    String? agentLoopStage;
    String? agentLoopStageDetail;
    _controller.onAgentLoopStage =
        (stage, {toolName, detail}) {
          if (!mounted) return;
          setState(() {
            agentLoopStage = stage;
            agentLoopStageDetail = detail;
          });
        };

    // [教練 Agent 2026-07-28] onControllerReady 上報
    widget.onControllerReady?.call(_controller);

    // ── ChatController callbacks ──
    _controller.onGetMessageText = () => _inputController.text;
    _controller.onSetMessageText = (text) =>
        setState(() => _inputController.text = text);
    _controller.onClearMessageInput = () => _inputController.clear();
    _controller.onFocusMessageInput = () {
      if (mounted) _focusNode.requestFocus();
    };
    _controller.onScrollToBottom = _scrollToBottom;

    _controller.addListener(_onControllerChanged);

    _loadCompanion();
    // [教練 Agent 2026-07-23] 畫布對話系統 — 有 canvasId 時只載入此畫布的對話
    if (widget.canvasId != null) {
      _controller.loadConversationsForCanvas(widget.canvasId!).then((_) {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      });
    } else {
      _controller.loadConversations().then((_) {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      });
    }
  }

  // [教練 Agent 2026-07-24] 切換畫布時重新載入對應的對話
  @override
  void didUpdateWidget(covariant CanvasChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.canvasId != oldWidget.canvasId) {
      if (widget.canvasId != null) {
        _controller.loadConversationsForCanvas(widget.canvasId!).then((_) {
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
          }
        });
      } else {
        _controller.loadConversations().then((_) {
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    // ── Voice AI 引擎清理 ──
    _voiceEngine.state.removeListener(_onVoiceStateChanged);
    _voiceLive?.dispose();  // [教練 Agent 2026-08-03] 釋放 voice live
    _voiceSpeech.dispose(); // [教練 Agent 2026-07-28] 語音辨識 handler 清理
    _micVolumeSub?.cancel();  // [教練 Agent 2026-08-03] 取消音量訂閱
    _partialTextSub?.cancel();  // [教練 Agent 2026-08-03] 取消 partial 訂閱
    _micVolume.dispose();  // [教練 Agent 2026-08-03] 釋放 ValueNotifier
    unawaited(_voiceEngine.stopConversation());
    _voiceEngine.dispose();
    unawaited(_audioPlayer.dispose());
    unawaited(_tts.dispose());
    _inputController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Lifecycle helpers ──

  void _loadCompanion() {
    try {
      _companion = CompanionStore().activeCompanion;
      // [2026-08-26 身份污染追根] controller 也必須載入——
      // 舊碼只更新本 widget 的 _companion（頭像/名稱顯示），
      // controller._activeCompanion 一直 null → system prompt 的人格注入
      // 是空的 → 畫布夥伴失憶失格（與對話頁同款病根）。
      _controller.loadActiveCompanion();
      _companion = _controller.activeCompanionInstance ?? _companion;
    } catch (e) {
      debugPrint('[CanvasChatPanel] loadCompanion error: $e');
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    // controller 更新後捲到最新訊息
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    // [教練 Agent 2026-08-17 使用者 抓包] 畫布對話也要會彈夥伴選擇器——
    // 之前只有主對話頁監聽這個 flag，畫布對話框觸發換人偵測後
    // flag 卡死，後續每一則訊息都被靜默吞掉（發文消失元兇）。
    if (_controller.pendingCompanionPickerRequest) {
      _controller.clearCompanionPickerRequest();
      _showCanvasCompanionPicker();
    }
  }

  /// [教練 Agent 2026-08-17 使用者 抓包] 畫布對話原生的夥伴選擇 sheet——
  /// 按鈕點擊與 NLU 換人偵測 flag 共用同一個入口
  void _showCanvasCompanionPicker() {
    final companions = CompanionStore().all;
    if (companions.isEmpty) return;
    final companion = _companion ?? CompanionStore().activeCompanion;
    // [2026-08-27 共視修復] 與對話頁同款錨定選單——錨在夥伴按鈕正下方彈出
    // （bottom sheet 跑中央、字級過大，Blue 2026-08-27 要求兩頁一致）。
    // 教訓：findRenderObject 必須用「按鈕自己」的 context（state context
    // = 整個 panel 的 box，座標會歪）。
    final RenderBox? box = _companionBtnKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        pos.dx,
        pos.dy + box.size.height + 4,
        overlay.size.width - pos.dx - box.size.width,
        overlay.size.height - pos.dy,
      ),
      items: [
        for (final c in companions)
          PopupMenuItem(
            value: c.id,
            height: 44,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: BridgeDSColors.of(context).surfaceHover,
                  child: Text(c.name.isNotEmpty ? c.name[0] : '?',
                      style: TierStyle.of(context, Tier.cardCaption).toTextStyle()),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.name,
                          style: TierStyle.of(context, Tier.listItemTitle).toTextStyle()),
                      Text('${c.mbtiCode} · ${c.roleName}',
                          style: TierStyle.of(context, Tier.cardCaption).toTextStyle()),
                    ],
                  ),
                ),
                if (companion != null && c.id == companion.id)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.check_circle,
                        size: 16, color: BridgeDSColors.of(context).accentGreen),
                  ),
              ],
            ),
          ),
      ],
    ).then((selected) {
      if (selected == null) return;
      if (companion != null && selected == companion.id) return;
      // controller 正規切換：泡泡 + 交接簡報 + 廣播同步
      _controller.switchToCompanionByRequest(selected, '畫布對話切換夥伴');
      setState(() {
        _companion = CompanionStore().getById(selected);
      });
    });
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      // 再加一幀確保非同步內容渲染後位置正確
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    });
  }

  // ── Voice AI 引擎方法 ──

  /// 顯示錯誤訊息
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
    _voiceSettings = settings;
    if (!mounted) return;
    _voiceEngine.state.removeListener(_onVoiceStateChanged);
    unawaited(_voiceEngine.stopConversation());
    _voiceEngine.dispose();

    // 重建 VoiceEngine 使用 settings
    final engine = VoiceEngine(
      onSpeak: (text) => _tts.speak(text),
      onStopSpeaking: () => _tts.stop(),
      onPlayAudioBytes: (bytes) => _audioPlayer.play(bytes),
      onAgentLoopTrigger: ({
        required userText,
        required onProgress,
        required onComplete,
      }) {
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

  Future<void> _toggleVoiceConversation() async {
    // [教練 Agent 2026-08-03] 雙向溝通模式 — 按一次進入持續對話
    if (_voiceEngine.isConversationActive || _voiceSpeech.isListening) {
      // 正在對話中 → 停止
      await _voiceLive?.stop();
      _voiceLive = null;
      await _voiceSpeech.stop();
      await _voiceEngine.stopConversation();
      _draftBeforeVoice = '';
    } else {
      // 沒在對話 → 啟動雙向溝通
      _voiceLive = VoiceLiveController(
        speechHandler: _voiceSpeech,
        voiceEngine: _voiceEngine,
        chatController: _controller,
      );
      try {
        await _voiceLive!.start();
        debugPrint('[CanvasChatPanel] 雙向溝通已啟動');
      } catch (e) {
        debugPrint('[CanvasChatPanel] 雙向溝通啟動失敗: $e');
        _voiceLive = null;
      }
    }
    if (mounted) setState(() {});
  }

  // [教練 Agent 2026-08-03] 長按 = 語音輸入文字（iMessage 風格）
  // 按住 → 開始錄音 + partial 寫入 controller
  // 放開 → 停止錄音 + 自動送出
  Future<void> _startVoiceInput() async {
    if (_voiceEngine.isConversationActive || _voiceSpeech.isListening) return;
    debugPrint('[CanvasChatPanel] 長按：語音輸入模式開始');
    // 1. 啟動 STT
    await _voiceSpeech.start();
    if (mounted) setState(() {});
  }

  Future<void> _stopVoiceInput() async {
    if (!_voiceSpeech.isListening) return;
    debugPrint('[CanvasChatPanel] 長按放開：語音輸入模式結束');
    // 1. 停止 STT
    await _voiceSpeech.stop();
    // 2. 自動送出當前文字
    if (mounted && _inputController.text.trim().isNotEmpty) {
      await _sendMessage();
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
    final messagesBefore = _controller.currentConversation?.messages.length ?? 0;

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
    _controller.sendMessage().then((_) {
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
                .replaceAll(RegExp(r'<think>[\s\S]*?</think>',
                    caseSensitive: false), '')
                .trim();
            onComplete(reply);
            return;
          }
        }
      }
      // fallback：如果找不到 assistant 訊息
      onComplete('（已完成）');
    }).catchError((error) {
      // 恢復原本的 getter/setter/進度回調
      _controller.onGetMessageText = originalGetter;
      _controller.onSetMessageText = originalSetter;
      _controller.onAgentLoopProgress = originalProgress;
      onComplete('處理時發生錯誤：$error');
    });
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
          await _controller.sendMessage(imagePath: file.path);
        }
      }
    } catch (e) {
      debugPrint('[CanvasChatPanel] 圖片選擇失敗: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    // [教練 Agent 2026-07-22] Phase H — 帶上回覆目標
    if (_replyTargetMessage != null) {
      _controller.setReplyTarget(_replyTargetMessage);
      _replyTargetMessage = null;
    }
    await _controller.sendMessage();
  }

  // [教練 Agent 2026-07-29] 攔截鍵盤事件：
  // - Enter（無修飾鍵）→ 新增行（不攔截，讓 TextField 自然換行）
  // - Cmd+Enter 或 Shift+Enter → 送出訊息
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter && key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }

    final isCmd = HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isCmd || isShift) {
      _sendMessage();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Container(
      // [教練 Agent 2026-08-16 使用者回饋] 寬度交給外層 SizedBox(chatWidth) 控制——
      // 原本寫死 320，外層拖到 240 時內容被壓出黃黑警示條。
      width: double.infinity,
      color: BridgeDSColors.of(context).canvas,
      child: Column(
        children: [
          _buildHeader(),
          Container(height: 1, color: BridgeDSColors.of(context).borderSubtle),
          Expanded(child: _buildMessageList()),
          if (_controller.isLoading && _controller.imageProgressEvents.isNotEmpty)
            _buildImageProgressTimeline(),
          if (_controller.isLoading) _buildTypingIndicator(),
          _buildInputBar(),
        ],
      ),
    );
  }

  // ── Header ──

  Widget _buildHeader() {
    // [教練 Agent 2026-08-17 使用者 提案] 多 agent 共視列——
    // 對話裡有誰發過言，頭部就列出誰（每個 agent 一個圓圈+名字）。
    // 切換到新 agent 後他加入列隊，代表「兩個 agent 一起看這個問題」。
    // 「Agent 共視」字樣移到綠燈旁。
    final conversation = _controller.currentConversation;
    final speakerIds = <String>{};
    for (final m in conversation?.messages ?? const <Message>[]) {
      if (m.role == 'assistant' && m.speakerId != null) {
        speakerIds.add(m.speakerId!);
      }
    }
    // 當前 active 夥伴一定在列（就算還沒發過言）
    final activeId = _companion?.id ?? CompanionStore().activeCompanion?.id;
    if (activeId != null) speakerIds.add(activeId);

    // 依序：active 在前，其他按加入順序
    final ordered = <String?>[activeId, ...speakerIds.where((id) => id != activeId)];

    return Padding(
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      child: Row(
        children: [
          // 多 agent 頭像列
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // [邊界動態鐵則 2026-10-21] Row→Wrap：agent chips 數量隨夥伴
                // 增加，320px 面板下寫死單行會溢出——動態換行。
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < ordered.length; i++) ...[
                      _buildHeaderAgentChip(ordered[i], isActive: ordered[i] == activeId),
                    ],
                  ],
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    // Online indicator dot（綠燈）
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: BridgeDSColors.of(context).accentGreen,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Agent 共視',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                        color: BridgeDSColors.of(context).textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [教練 Agent 2026-08-17] 頭部 agent chip——小圓圈頭像 + 名字，active 高亮
  Widget _buildHeaderAgentChip(String? companionId, {required bool isActive}) {
    final companion = companionId != null ? CompanionStore().getById(companionId) : null;
    final name = companion?.name ?? 'Agent';
    final initial = name.isNotEmpty ? name.characters.first : 'A';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.15)
            : BridgeDSColors.of(context).surfaceHover,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(
          color: isActive
              ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.6)
              : BridgeDSColors.of(context).borderSubtle,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.8),
                  BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.6),
                ],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                color: BridgeDSColors.of(context).textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
          SizedBox(width: 6),
          Text(
            name,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
              color: BridgeDSColors.of(context).textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ── Message list ──

  Widget _buildMessageList() {
    final conversation = _controller.currentConversation;
    // [教練 Agent 2026-07-22] Phase D — 過濾靜默 messages（畫布狀態注入）
    final messages = conversation?.messages
            .where((m) => m.metadata?['silent'] != true)
            .toList() ??
        const [];

    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(BridgeDS.spaceLG),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                color: BridgeDSColors.of(context).textMuted,
                size: 32,
              ),
              SizedBox(height: 8),
              Text(
                '開始與 Agent 對話',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: BridgeDS.spaceMD,
        vertical: BridgeDS.spaceSM,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final isUser = msg.role == 'user';
        return _buildMessageBubble(msg, isUser);
      },
    );
  }

  Widget _buildMessageBubble(Message msg, bool isUser) {
    // [2026-08-27 共視修復] 切換夥伴系統條——與對話頁同款置中藍條
    if (msg.metadata != null && msg.metadata!['kind'] == 'companion_switch') {
      final toId = msg.metadata!['toCompanionId'] as String?;
      final toName =
          toId != null ? (CompanionStore().getById(toId)?.name ?? '') : '';
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
    // D11: 攔截系統卡片 — 可折疊顯示
    if (!isUser && msg.content.contains(':')) {
      final cardPrefixes = [
        digitalAssetResultCardPrefix,
        digitalAssetInvocationCardPrefix,
        digitalAssetReusePlanCardPrefix,
        projectDoorCardPrefix,
        projectContextTransferCardPrefix,
        projectForkCompleteCardPrefix,
        projectForkIntroCardPrefix,
        capabilityCardPrefix,
        capabilityAdvisorCardPrefix,
        managedFolderRulePickerCardPrefix,
      ];
      for (final prefix in cardPrefixes) {
        if (msg.content.startsWith(prefix)) {
          return _buildCollapsibleCard(msg.content);
        }
      }
      // B系列: 攔截畫布匯入卡片 — 自訂渲染含按鈕
      if (msg.content.startsWith(canvasImportCardPrefix)) {
        return _buildCanvasImportCard(msg.content);
      }
    }

    final content = isUser
        ? msg.content
        : _filterThinkTags(msg.content);

    final displayContent = content.trim();
    if (displayContent.isEmpty) return const SizedBox.shrink();

    // [教練 Agent 2026-07-22] 時間格式化
    final timeStr = _formatMessageTime(msg.timestamp);

    // [教練 Agent 2026-07-22] 回覆引用
    final replySnippet = msg.replyToSnippet;

    // 建立訊息氣泡 widget
    Widget bubbleWidget;

    if (isUser) {
      bubbleWidget = Container(
        margin: const EdgeInsets.only(bottom: BridgeDS.spaceSM),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (replySnippet != null && replySnippet.isNotEmpty)
                    _buildReplyQuote(replySnippet, isUser: true),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.15),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(BridgeDS.roundComfortable),
                        topRight: Radius.circular(BridgeDS.roundComfortable),
                        bottomLeft: Radius.circular(BridgeDS.roundComfortable),
                        bottomRight: Radius.circular(4),
                      ),
                      border: Border.all(
                        color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: SelectableText(
                      displayContent,
                      style: TextStyle(
                        color: BridgeDSColors.of(context).textPrimary,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          timeStr,
                          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                        ),
                        // [教練 Agent 2026-07-29] user 不顯示模型名 — 只 Agent 回覆顯示
                        const SizedBox(width: 4),
                        _buildReplyButton(msg),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      // Assistant message — left aligned with avatar
      // [教練 Agent 2026-08-17 使用者 抓包] 頭像跟「誰講的話」走——
      // 用 msg.speakerId 解析發言者，不是當前 active 夥伴。
      // 之前切換夥伴後整串歷史泡泡的頭像全都變成新人（驢唇不對馬嘴）。
      final speaker = msg.speakerId != null
          ? CompanionStore().getById(msg.speakerId!)
          : null;
      final name = speaker?.name ?? _companion?.name ?? 'Agent';
      final initial = name.isNotEmpty ? name.characters.first : 'A';

      bubbleWidget = Container(
        margin: const EdgeInsets.only(bottom: BridgeDS.spaceSM),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar circle
            Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.8),
                    BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.6),
                  ],
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                  fontWeight: FontWeight.w600,),
              ),
            ),
            SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (replySnippet != null && replySnippet.isNotEmpty)
                    _buildReplyQuote(replySnippet, isUser: false),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: BridgeDSColors.of(context).surfaceElevated,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(BridgeDS.roundComfortable),
                        bottomLeft: Radius.circular(BridgeDS.roundComfortable),
                        bottomRight: Radius.circular(BridgeDS.roundComfortable),
                      ),
                      border: Border.all(
                        color: BridgeDSColors.of(context).borderSubtle,
                        width: 1,
                      ),
                    ),
                    child: SelectableText(
                      displayContent,
                      style: TextStyle(
                        color: BridgeDSColors.of(context).textPrimary,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ),
                  // [2026-08-27 B 方案] 教學動作按鈕——metadata.actions 渲染
                  if (msg.metadata != null &&
                      msg.metadata!['actions'] is List)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final act in (msg.metadata!['actions'] as List))
                            _buildTutorialActionButton(
                              (act as Map)['label'] as String? ?? '繼續',
                              act['action'] as String? ?? 'tutorial_next',
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          timeStr,
                          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                        ),
                        // [教練 Agent 2026-07-29] Agent 回覆顯示模型名稱 — 畫布側欄
                        if (msg.model != null && msg.model!.isNotEmpty) ...[
                          Text(
                            ' · ${resolveShortModelName(msg.model) ?? msg.model}',
                            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                          ),
                        ],
                        _buildReplyButton(msg),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 包上 GestureDetector 提供長按選單
    return GestureDetector(
      onLongPress: () {
        MessageContextMenu.show(
          context: context,
          message: msg,
          showExtendTopic: false,
          onReply: () {
            // [教練 Agent 2026-08-03] 同步兩個 store — banner 顯示需要 _replyTargetMessage
            _controller.setReplyTarget(msg);
            setState(() {
              _replyTargetMessage = msg;
            });
            _focusNode.requestFocus();
          },
          onDelete: () {
            // [教練 Agent 2026-08-18] 走正式 deleteMessage——先存檔再更新，
            // 舊寫法 switchConversation(updated) 會被 store 舊版蓋掉
            _controller.deleteMessage(msg.id);
          },
        );
      },
      child: bubbleWidget,
    );
  }

  /// [教練 Agent 2026-07-22] 格式化訊息時間 — [教練 Agent 2026-07-23] 統一為日期+時間
  String _formatMessageTime(DateTime timestamp) {
    final mo = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$mo/$d $h:$m';
  }

  /// [教練 Agent 2026-07-22] 回覆引用框
  Widget _buildReplyQuote(String snippet, {required bool isUser}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
      ),
      constraints: BoxConstraints(maxWidth: 200),
      child: Text(
        snippet.length > 60 ? '${snippet.substring(0, 60)}...' : snippet,
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
          fontStyle: FontStyle.italic,),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// [教練 Agent 2026-07-22] Phase H — 回覆按鈕
  /// [教練 Agent 2026-08-15 使用者 提案] 改為三點選單——長按選單只有我們自己知道，
  /// 使用者看不到入口。統一介面：時間旁三個點 → 回覆/刪除/延伸話題。
  /// [2026-08-27 B 方案] 教學動作按鈕
  /// [Blue 2026-08-27 定案] 黑底＋紫框凸顯＋白字清楚＋字級微縮——
  /// 藍底太突兀、白字看不清。紫框＝提示，黑底＝融入深色版面。
  Widget _buildTutorialActionButton(String label, String action) {
    final isPrimary = action != 'tutorial_cancel';
    final colors = BridgeDSColors.of(context);
    return OutlinedButton(
      onPressed: () => TemplateTutorialService.instance
          .performAction(action)
          .then((_) => setState(() {})),
      style: OutlinedButton.styleFrom(
        backgroundColor: colors.canvas,
        foregroundColor: BridgeDSColors.of(context).textPrimary,
        side: BorderSide(
          color: isPrimary
              ? colors.accentPurple
              : colors.borderDefault,
          width: isPrimary ? 1.5 : 1,
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPrimary) ...[
            Icon(Icons.play_arrow_rounded,
                size: 14, color: colors.accentPurple),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TierStyle.of(context, Tier.cardCaption)
                .toTextStyle()
                .copyWith(
                  color: isPrimary
                      ? colors.textPrimary
                      : colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyButton(Message msg) {
    return GestureDetector(
      onTap: () => _showMessageMenu(msg),
      child: Icon(
        Icons.more_horiz,
        size: 14,
        color: BridgeDSColors.of(context).textMuted,
      ),
    );
  }

  /// [教練 Agent 2026-08-15 使用者 提案] 三點選單——與長按選單同內容
  void _showMessageMenu(Message msg) {
    MessageContextMenu.show(
      context: context,
      message: msg,
      showExtendTopic: false,
      onReply: () {
        _controller.setReplyTarget(msg);
        setState(() {
          _replyTargetMessage = msg;
        });
        _focusNode.requestFocus();
      },
      onDelete: () {
        // [教練 Agent 2026-08-18] 走正式 deleteMessage——switchConversation 會把刪除吞掉
        _controller.deleteMessage(msg.id);
      },
    );
  }

  /// [教練 Agent 2026-08-03] 回覆預覽 bar — 簡潔一行版（跟 chat_screen 與 desktop chat panel 統一）
  Widget _buildReplyPreviewBar() {
    if (_replyTargetMessage == null) return const SizedBox.shrink();
    final content = _replyTargetMessage!.content;
    final isUser = _replyTargetMessage!.role == 'user';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, size: 14, color: BridgeDSColors.of(context).accentBlue),
          const SizedBox(width: 6),
          Text(
            isUser ? '回覆 你的訊息' : '回覆 AI 訊息',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
              color: BridgeDSColors.of(context).accentBlue,),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              content.length > 50 ? '${content.substring(0, 50)}...' : content,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                fontStyle: FontStyle.italic,),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _replyTargetMessage = null;
              });
              _controller.clearReplyTarget(); // [教練 Agent 2026-08-03] 同步 ChatController
            },
            child: Icon(Icons.close, size: 14, color: BridgeDSColors.of(context).textMuted),
          ),
        ],
      ),
    );
  }

  // ── Typing indicator ──

  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BridgeDS.spaceMD,
        vertical: 6,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.7),
            ),
          ),
          SizedBox(width: 8),
          Text(
            // [教練 Agent 2026-08-17 使用者 微調] 顯示夥伴名稱——「MimeMi 思考中」比「Agent 思考中」直覺
            '${_companion?.name ?? 'Agent'} 思考中...',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
          ),
        ],
      ),
    );
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

  // ── Input bar ──

  // [2026-08-27 共視修復] 夥伴按鈕的錨點 key——選單錨按鈕彈出
  final GlobalKey _companionBtnKey = GlobalKey();

  // [教練 Agent 2026-08-11] 畫布夥伴切換按鈕——跟左下角箭頭一樣的行為
  Widget _buildCompanionSelectorButton() {
    final companion = _companion ?? CompanionStore().activeCompanion;
    final name = companion?.name ?? '夥伴';

    return Tooltip(
      message: '切換夥伴',
      child: GestureDetector(
        // [教練 Agent 2026-08-17 使用者 抓包] 抽成共用方法——flag 觸發時也叫同一個
        onTap: _showCanvasCompanionPicker,
        child: Container(
          // [2026-08-27] 錨點 key——選單錨這顆按鈕彈出
          key: _companionBtnKey,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).surfaceHover,
            borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
            border: Border.all(color: BridgeDSColors.of(context).borderSubtle, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline, size: 14, color: BridgeDSColors.of(context).textSecondary),
              const SizedBox(width: 4),
              Text(name, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                fontSize: 13, color: BridgeDSColors.of(context).textSecondary)),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 16, color: BridgeDSColors.of(context).textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        border: Border(
          top: BorderSide(color: BridgeDSColors.of(context).borderSubtle, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // [教練 Agent 2026-07-22] Phase H — 回覆預覽 bar
          _buildReplyPreviewBar(),
          // [教練 Agent 2026-07-28] VoiceStatusIndicator（對談中才顯示，不影響按鈕位置）
          if (_voiceEngine.isConversationActive)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: VoiceStatusIndicator(mode: _voiceMode),
              ),
            ),
          // ── 夥伴選擇 + Agent 模型選擇器 + 上傳 + 模式 ──
          // [邊界動態鐵則 2026-10-21 Blue 令] Row→Wrap：空間不足自動換行，
          // 元件照內容動態擴張，永不溢出（根治黑黃警示條）。
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              // [教練 Agent 2026-08-11] 夥伴切換按鈕
              _buildCompanionSelectorButton(),
              AgentModelSelector(
                onProviderChanged: () {
                  // 通知 ChatController 重新載入 provider 設定
                  _controller.refreshLocalModelState();
                },
              ),
              // 上傳圖片/檔案
              Tooltip(
                message: '上傳圖片或檔案',
                child: IconButton(
                  icon: Icon(Icons.attach_file_outlined,
                      size: 16, color: BridgeDSColors.of(context).textTertiary),
                  onPressed: _pickImage,
                ),
              ),
              // [聊天模式 B 線 2026-10-21 Blue 指定] 模式下拉——上傳檔案右邊，
              // 桌面對話 tab 輸入列同款（_buildChatModePicker 語彙）。
              _buildChatModePicker(),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(context).surfaceElevated,
                    borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
                    border: Border.all(
                      color: BridgeDSColors.of(context).borderSubtle,
                      width: 1,
                    ),
                  ),
                  child: Focus(
                        // [教練 Agent 2026-07-29] 用 Focus 攔截鍵盤事件
                        // Focus 不持有 focusNode，只做事件攔截；TextField 保留自己的 focusNode
                        canRequestFocus: false,
                        onKeyEvent: _handleKeyEvent,
                        child: TextField(
                      controller: _inputController,
                      focusNode: _focusNode,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: '輸入訊息...',
                        hintStyle: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),  // [教練 Agent 2026-08-03] 縮小間距 8→4 讓按鈕貼齊
              // [教練 Agent 2026-07-22] loading 時允許發訊息（插嘴）+ 停止鍵
              if (_controller.isLoading)
                _buildChatSendButton(
                  icon: Icons.stop_circle,
                  color: BridgeDSColors.of(context).accentRed,
                  tooltip: '停止',
                  onPressed: () => _controller.stopAgent(),
                ),
              const SizedBox(width: 4),  // [教練 Agent 2026-08-03] 等距 4px
              _buildChatSendButton(
                icon: Icons.send_rounded,
                color: BridgeDSColors.of(context).accentBlue,
                tooltip: '送出',
                onPressed: _sendMessage,
              ),
              const SizedBox(width: 4),  // [教練 Agent 2026-08-03] 等距 4px
              // [教練 Agent 2026-08-03] VoiceButton 在最右邊，固定位置不跳位
              // [教練 Agent 2026-08-03] 短按 = 雙向對話，長按 = 語音輸入文字（iMessage 風格）
              VoiceButton(
                mode: _voiceMode,
                onToggle: _toggleVoiceConversation,  // 短按
                onLongPressStart: _startVoiceInput,  // 長按開始
                onLongPressEnd: _stopVoiceInput,    // 長按結束
                volume: _micVolume,  // [教練 Agent 2026-08-03] 傳 ValueNotifier（不重建 panel）
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// [教練 Agent 2026-08-03] 對話發射鈕 — 圓形 + hover 顯著發光 + 背景
  /// 跟 chat_screen.dart 的 FloatingActionButton.small 一樣互動感覺
  // [聊天模式 B 線 2026-10-21 Blue 指定] 畫布對話欄模式下拉——
  // 上傳檔案右邊；桌面對話 tab（desktop_chat_panel）同款語彙。
  Widget _buildChatModePicker() {
    final ds = BridgeDSColors.of(context);
    final current = ChatModeService.instance.currentMode;
    return PopupMenuButton<String>(
      tooltip: '選擇聊天模式',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 260),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(current.icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              current.name,
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: ds.textSecondary),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: ds.textTertiary),
          ],
        ),
      ),
      itemBuilder: (context) => chatModes
          .map((mode) => PopupMenuItem(
                value: mode.id,
                child: Row(
                  children: [
                    Text(mode.icon, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Text(
                      mode.name,
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            color: mode.id == current.id
                                ? ds.accentBlue
                                : ds.textPrimary,
                          ),
                    ),
                    if (mode.id == current.id) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.check, size: 14, color: ds.accentBlue),
                    ],
                  ],
                ),
              ))
          .toList(),
      onSelected: (modeId) async {
        await ChatModeService.instance.setMode(modeId);
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildChatSendButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
    bool disabled = false,
  }) {
    // 對話頁 FAB 是實心背景 (alpha 1.0) — 這裡用 0.18 當預設（跟輸入框背景對比）
    // hover 變 0.3 → 對話頁 hover 是 elevation
    return HoverGlowCircleButton(
      icon: icon,
      color: color,
      tooltip: tooltip,
      onPressed: disabled ? null : onPressed,
      disabled: disabled,
    );
  }

  // ── Helpers ──

  /// 系統卡片標籤
  static const _cardLabels = {
    digitalAssetResultCardPrefix: '資產結果',
    digitalAssetInvocationCardPrefix: '資產引用',
    digitalAssetReusePlanCardPrefix: '資產重用',
    projectDoorCardPrefix: '專案門',
    projectContextTransferCardPrefix: '專案轉移',
    projectForkCompleteCardPrefix: '專案分叉',
    projectForkIntroCardPrefix: '專案分叉',
    capabilityCardPrefix: '能力資訊',
    capabilityAdvisorCardPrefix: '能力顧問',
    managedFolderRulePickerCardPrefix: '資料夾規則',
    canvasImportCardPrefix: '畫布匯入',
  };

  /// B系列: 畫布匯入卡片 — Agent 摘要 + 建議名稱 + 按鈕
  Widget _buildCanvasImportCard(String rawContent) {
    final jsonStr = rawContent.substring(canvasImportCardPrefix.length);
    CanvasImportCardData? card;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        card = CanvasImportCardData.fromJson(decoded);
      }
    } catch (_) {}

    if (card == null) {
      return _buildCollapsibleCard(rawContent);
    }
    final data = card;

    return Padding(
      padding: const EdgeInsets.only(bottom: BridgeDS.spaceSM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.15),
            child: Icon(Icons.account_tree_outlined, size: 14, color: BridgeDSColors.of(context).accentPurple),
          ),
          SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.3), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline, size: 12, color: BridgeDSColors.of(context).accentPurple),
                      SizedBox(width: 4),
                      Text(
                        'Agent 建議匯入畫布',
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple,
                          fontWeight: FontWeight.w600,),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  if (data.summary.isNotEmpty)
                    SelectableText(
                      data.summary,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                        height: 1.4,),
                    ),
                  if (data.suggestedTitle.isNotEmpty) ...[
                    SizedBox(height: 4),
                    Text(
                      '建議名稱：${data.suggestedTitle}',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textTertiary,),
                    ),
                  ],
                  if (widget.onCanvasImport != null) ...[
                    SizedBox(height: 8),
                    InkWell(
                      onTap: () => widget.onCanvasImport!(data.summary, data.suggestedTitle),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.3), width: 1),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline, size: 14, color: BridgeDSColors.of(context).accentGreen),
                            SizedBox(width: 4),
                            Text('新建畫布', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentGreen, fontWeight: FontWeight.w500)),
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

  /// 可折疊系統卡片 — 預設只顯示標題，點擊展開內容
  Widget _buildCollapsibleCard(String rawContent) {
    String cardType = '系統訊息';
    for (final entry in _cardLabels.entries) {
      if (rawContent.startsWith(entry.key)) {
        cardType = entry.value;
        break;
      }
    }

    String summary = '';
    String fullJson = '';
    final colonIdx = rawContent.indexOf(':');
    if (colonIdx >= 0) {
      final jsonPart = rawContent.substring(colonIdx + 1);
      try {
        final decoded = jsonDecode(jsonPart);
        if (decoded is Map<String, dynamic>) {
          summary = decoded['title']?.toString() ??
              decoded['status']?.toString() ??
              decoded['statusMessage']?.toString() ??
              decoded['ideaSummary']?.toString() ??
              decoded['planSummary']?.toString() ??
              decoded['summary']?.toString() ??
              '';
          fullJson = const JsonEncoder.withIndent('  ').convert(decoded);
        }
      } catch (_) {
        fullJson = jsonPart;
      }
    }

    // [v214b 小葵 2026-09-02 Blue 抓包] 能力顧問卡展開不要 JSON 裸奔——
    // 轉成人話：缺口是什麼、目前進度、下一步。使用者體驗優先，
    // JSON 只在必要時保留尾端。
    if (rawContent.startsWith(capabilityAdvisorCardPrefix)) {
      try {
        final decoded = jsonDecode(rawContent.substring(
            rawContent.indexOf(':') + 1)) as Map<String, dynamic>;
        final lines = <String>[
          '📋 缺口：${decoded['gapLabel'] ?? '未命名能力'}',
          '🎯 你的需求：${decoded['userRequest'] ?? '—'}',
          '⏱ 狀態：${_advisorStepLabel(decoded['currentStep']?.toString())}',
          if ((decoded['statusMessage'] as String?)?.isNotEmpty == true)
            '💬 ${decoded['statusMessage']}',
        ];
        fullJson = lines.join('\n\n');
      } catch (_) {}
    }

    return _CollapsibleCard(
      cardType: cardType,
      summary: summary,
      fullContent: fullJson,
    );
  }

  /// [v214b] advisor 狀態機步驟轉人話
  String _advisorStepLabel(String? step) {
    switch (step) {
      case 'checkingBrowse':
        return '檢查既有能力中…';
      case 'browseGapDetected':
        return '發現能力缺口';
      case 'searching':
        return '正在搜尋市集方案…';
      case 'analyzing':
        return '分析候選方案中…';
      case 'presentingComparison':
        return '方案比較準備好了';
      case 'awaitingSelection':
        return '等你挑選方案';
      case 'solutionSelected':
        return '已選定方案';
      case 'verifying':
        return '驗證中…';
      case 'verified':
        return '✅ 能力已開通';
      case 'returningToTask':
        return '回到原本的任務';
      case 'failed':
        return '❌ 這次沒成功';
      case 'cancelled':
        return '已取消';
      default:
        return '待命中';
    }
  }

  /// 過濾 assistant 訊息中的系統內容，只留使用者必要的資訊。
  /// 與 DesktopChatPanel 保持一致的過濾邏輯。
  String _filterThinkTags(String content) {
    return content
        .replaceAll(
          RegExp(r'<<<tool_call>>>[\s\S]*?<<<tool_call_end>>>'),
          '',
        )
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        // 隱藏搜尋證據等系統內部文字
        .replaceAll(RegExp(r'\n*搜尋證據：[\s\S]*$'), '')
        .replaceAll(RegExp(r'\n*圖片辨識證據：[\s\S]*$'), '')
        .replaceAll(RegExp(r'\n*文件產出證據：[\s\S]*$'), '')
        .replaceAll(RegExp(r'\n*桌面整理證據：[\s\S]*$'), '')
        .trim();
  }
}

/// 可折疊系統卡片 — 預設只顯示標題，點擊展開完整內容
class _CollapsibleCard extends StatefulWidget {
  final String cardType;
  final String summary;
  final String fullContent;

  const _CollapsibleCard({
    required this.cardType,
    required this.summary,
    required this.fullContent,
  });

  @override
  State<_CollapsibleCard> createState() => _CollapsibleCardState();
}

class _CollapsibleCardState extends State<_CollapsibleCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: BridgeDS.spaceSM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BridgeDSColors.of(context).surfaceHover,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.memory, size: 14, color: BridgeDSColors.of(context).textTertiary),
          ),
          SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BridgeDSColors.of(context).borderSubtle, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: widget.fullContent.isEmpty
                        ? null
                        : () => setState(() => _expanded = !_expanded),
                    child: Row(
                      children: [
                        Text(
                          widget.cardType,
                          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textTertiary,
                            fontWeight: FontWeight.w500,),
                        ),
                        if (widget.summary.isNotEmpty) ...[
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.summary,
                              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
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
                            size: 14,
                            color: BridgeDSColors.of(context).textQuaternary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_expanded && widget.fullContent.isNotEmpty) ...[
                    SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: BridgeDSColors.of(context).canvas,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: BridgeDSColors.of(context).borderSubtle, width: 0.5),
                      ),
                      child: SelectableText(
                        widget.fullContent,
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textTertiary,
                          fontFamily: 'monospace',
                          height: 1.3,),
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
