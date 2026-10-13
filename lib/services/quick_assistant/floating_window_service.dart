// Quick Assistant 懸浮窗服務 — 主引擎端
// [無限插槽 C1 2026-10-06] spec: docs/specs/2026-10-04-infinite-slot-system.md
//
// 職責：
// 1. 用 desktop_multi_window 建立/管理系統級子視窗（黑底、無邊框、置頂、可拖曳）
// 2. 主端 relay handler：收子視窗的 user_message → 餵進主引擎的
//    QuickAssistant ChatController（enterQuickAssistantMode + sendAssistantMessage），
//    並把 assistant 回覆/狀態推回子視窗
// 3. toggle/show/hide——給 QuickAssistantManager、Cmd+K、全域 Cmd+Shift+K 呼叫
//
// 所有對話邏輯都在主引擎；子視窗只有 UI（見 lib/quick_assistant_window.dart）。
//
// Relay 協議（雙向 WindowChannel 'bridge.quick_assistant.relay.v1'，method='relay'）：
//   子 → 主：{"type":"user_message","text":String} | {"type":"window_ready"} |
//            {"type":"hide_request"}
//   主 → 子：{"type":"assistant_reply","text":String,"done":bool} |
//            {"type":"status","text":String} |
//            {"type":"history","messages":[{"role","content"},...]}

import 'dart:async';
import 'dart:io' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../controllers/chat_controller.dart';
import '../../quick_assistant_window.dart'
    show kQuickAssistantRelayChannel, kQuickAssistantWindowArg;
import '../../widgets/quick_assistant_panel.dart' show QuickAssistantManager;
import 'quick_assistant_context.dart';

/// Quick Assistant 系統級懸浮窗（主引擎端）。
///
/// 用法：
/// ```dart
/// final qa = FloatingWindowService.instance;
/// await qa.toggle();          // Cmd+Shift+K / Cmd+K
/// final ok = await qa.isAvailable; // 平台支援檢查（不支援 → fallback overlay）
/// ```
class FloatingWindowService {
  FloatingWindowService._();
  static final FloatingWindowService instance = FloatingWindowService._();

  WindowController? _controller;
  bool _creating = false;
  Future<void>? _creatingFuture;
  StreamSubscription<void>? _windowsChangedSub;
  bool _ready = false;

  /// [無限插槽 2026-10-06] 當前聚焦的插槽（grill-me 脈絡；null=一般對話）
  String? _activeSlotLabel;
  String? _activeSlotRepoUrl;
  Completer<void>? _childReadyCompleter;  // [2026-10-06 C1 驗屍] 子視窗握手閘門

  /// 平台支援（kIsWeb 或非桌面 → false，呼叫端走舊 OverlayEntry fallback）。
  bool get isPlatformSupported =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  Future<bool> get isAvailable async =>
      isPlatformSupported && _controller != null;

  /// 懸浮窗目前可見（建立中一律視為不可見，避免 toggle 競態）。
  bool get isVisible => _ready && !_creating;

  /// 初始化主端 relay handler（main.dart 啟動時呼叫一次；冪等）。
  Future<void> init() async {
    if (!isPlatformSupported) return;
    await _installMainRelayHandler();
    // 子視窗被真正銷毀（ App 結束等）時清引用，下次 toggle 重建。
    _windowsChangedSub ??= onWindowsChanged.listen((_) {
      _syncExistingController();
    });
  }

  Future<void> _syncExistingController() async {
    try {
      final all = await WindowController.getAll();
      final mine = all.where((c) => c.arguments == kQuickAssistantWindowArg);
      if (mine.isEmpty) {
        // 子視窗已不存在（外部關閉）→ 清狀態，下次 toggle 重建。
        _controller = null;
        _ready = false;
      } else {
        _controller = mine.first;
      }
    } catch (_) {}
  }

  /// 切換顯示/隱藏（全域熱鍵 Cmd+Shift+K 與應用內 Cmd+K 都走這裡）。
  Future<void> toggle() async {
    if (!isPlatformSupported) return;
    if (isVisible) {
      await hide();
    } else {
      await showOrCreate();
    }
  }

  /// 開啟（或喚起已存在的）懸浮窗。
  Future<void> showOrCreate() async {
    if (!isPlatformSupported) return;
    final controller = await _ensureWindow();
    if (controller == null) return;
    await _showViaWindowMethod(controller);
  }

  /// [無限插槽 C2→C3 橋 2026-10-06] 帶著插槽脈絡開懸浮窗＋自動 grill-me 開場。
  ///
  /// Blue 抓包（問題1）：登記插槽後只開空窗，使用者不知道要聊什麼、
  /// agent 也不知道使用者在問哪個插槽。修法：把 SlotRecord 帶進來——
  /// 開窗後直接以「使用者名義」送出開場訊息給主引擎 controller，
  /// 走同一條 sendAssistantMessage 管線（QuickAssistant 模式 context
  /// 附帶 slot 資訊，agent loop 自然看得到）。
  Future<void> showOrCreateForSlot({
    required String slotId,
    required String userLabel,
    required String sourceRepo,
  }) async {
    // [無限插槽 2026-10-06] 記住插槽脈絡——後續 _handleUserMessage 建
    // context 時帶上，system prompt 注入 grill-me 人格；也供開場訊息用。
    _activeSlotLabel = userLabel;
    _activeSlotRepoUrl = sourceRepo;
    await showOrCreate();
    // 開場白以使用者訊息送進管線——agent 回覆會流回懸浮窗（_watchReplies
    // 已掛）。等 window_ready 握手完成（showOrCreate 內部已 await）。
    final kickoff = '我剛把 GitHub 專案加進「插槽」：$userLabel（$sourceRepo）。'
        '請開始 grill-me：先一句話介紹這個專案能做什麼，然後用 2-3 個問題'
        '搞清楚我想用它完成什麼任務，再依答案建議權限等級（綠自動/黃謹慎/紅高風險）'
        '與貼近我工作流的用法。';
    try {
      await _handleUserMessage(kickoff);
    } catch (e) {
      debugPrint('[FloatingWindow] slot grill-me 開場失敗（窗已開，可手動聊）: $e');
    }
  }

  Future<void> _showViaWindowMethod(WindowController controller) async {
    // [2026-10-06 C1 驗屍] 修競態：子引擎註冊 handler 需要時間，直接呼叫
    // window_show 會吃 CHANNEL_UNREGISTERED（視窗建立成功但永遠隱藏）。
    // 等子視窗的 window_ready 握手；逾時 8 秒仍硬試一次（plugin 預設
    // handler 也會 show），雙保險。
    final gate = _childReadyCompleter;
    if (gate != null && !gate.isCompleted) {
      try {
        await gate.future.timeout(const Duration(seconds: 8));
      } on TimeoutException {
        debugPrint('[FloatingWindow] 等待子視窗握手逾時——改用 plugin 預設 show');
      }
    }
    try {
      await controller.invokeMethod('window_show');
    } catch (e) {
      debugPrint('[FloatingWindow] window_show failed: $e');
    }
    _ready = true;
  }

  /// 隱藏（不銷毀——對話持續留在主引擎）。
  Future<void> hide() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.invokeMethod('window_hide');
    } catch (e) {
      debugPrint('[FloatingWindow] window_hide failed: $e');
    }
    _ready = false;
    // 隱藏時退出 quick assistant mode（同 overlay close 行為）。
    QuickAssistantManager.exitModes();
  }

  Future<WindowController?> _ensureWindow() async {
    if (_controller != null) return _controller;
    if (_creating) return _creatingFuture?.then((_) => _controller);
    _creating = true;
    _creatingFuture = _doCreate();
    try {
      await _creatingFuture;
      return _controller;
    } finally {
      _creating = false;
    }
  }

  Future<void> _doCreate() async {
    _childReadyCompleter = Completer<void>();
    try {
      final controller = await WindowController.create(
        const WindowConfiguration(
          arguments: kQuickAssistantWindowArg,
          hiddenAtLaunch: true,
        ),
      );
      _controller = controller;
      debugPrint('[FloatingWindow] 子視窗已建立 id=${controller.windowId}');
    } catch (e) {
      debugPrint('[FloatingWindow] 建立子視窗失敗（fallback overlay）: $e');
      _controller = null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // Relay — 主引擎端 handler
  // ══════════════════════════════════════════════════════════════

  bool _initializedRelay = false;

  Future<void> _installMainRelayHandler() async {
    if (_initializedRelay) return;
    _initializedRelay = true;
    await const WindowMethodChannel(kQuickAssistantRelayChannel)
        .setMethodCallHandler((call) async {
      if (call.method != 'relay') return null;
      final data = (call.arguments as Map).cast<String, dynamic>();
      switch (data['type'] as String?) {
        case 'window_ready':
          // 子視窗 UI 就緒握手——解開 showOrCreate 的等待閘門。
          final gate = _childReadyCompleter;
          if (gate != null && !gate.isCompleted) gate.complete();
          await _pushHistory();
          return null;
        case 'hide_request':
          await hide();
          return null;
        case 'user_message':
          final text = data['text'] as String? ?? '';
          if (text.isNotEmpty) unawaited(_handleUserMessage(text));
          return null;
        default:
          return null;
      }
    });
  }

  /// 子視窗訊息 → 主引擎 QuickAssistant ChatController。
  Future<void> _handleUserMessage(String text) async {
    // 1) 取得/建立 Quick Assistant 專用 controller（沿用 QuickAssistantManager
    //    的 accessor 慣例：active → fallback 獨立 controller）。
    ChatController? ctrl;
    try {
      ctrl = QuickAssistantManager.activeControllerAccessor?.call();
    } catch (_) {
      ctrl = null;
    }
    ctrl ??= QuickAssistantManager.ensureFallbackController();

    // 2) 進入 Quick Assistant 模式（若尚未在模式中）。
    if (!ctrl.isQuickAssistantMode) {
      ctrl.enterQuickAssistantMode(QuickAssistantContext(
        currentPage: 'floating_window',
        // [無限插槽 2026-10-06] 帶 slot → system prompt 注入 grill-me 人格
        slotLabel: _activeSlotLabel,
        slotRepoUrl: _activeSlotRepoUrl,
        appDiagnostics: {
          'entry': 'system_floating_window',
          'os': Platform.operatingSystem,
        },
      ));
    }

    // 3) 推狀態給子視窗（子視窗會顯示 spinner 佔位）。
    await _pushToChild({'type': 'status', 'text': '思考中…'});

    // 4) 訂閱 controller 通知——回覆落地（訊息數增加 / isLoading 變 false）
    //    時把最新 assistant 訊息推回子視窗。
    _watchReplies(ctrl);

    // 5) 送出（同一條 ChatController.sendAssistantMessage 管線——含截圖、
    //    Agent Loop、context 注入，全部留在主引擎）。
    try {
      await ctrl.sendAssistantMessage(text);
    } catch (e) {
      await _pushToChild({
        'type': 'assistant_reply',
        'text': '抱歉，訊息送出失敗：$e',
        'done': true,
      });
      await _pushHistory();
      return;
    }
    // sendAssistantMessage 完成後的最終同步（含多步 Agent Loop 之後的全文）。
    await _pushLatestAssistantReply(done: true);
    await _pushHistory();
  }

  // 訂閱 controller（ChangeNotifier）——回覆過程中把新 assistant 內容
  // 流式推給子視窗。同一 controller 只掛一次 listener。
  ChatController? _watchedController;
  int _lastPushedCount = 0;

  void _watchReplies(ChatController ctrl) {
    _lastPushedCount = ctrl.currentConversation?.messages.length ?? 0;
    if (identical(_watchedController, ctrl)) return;
    _watchedController?.removeListener(_onControllerChanged);
    _watchedController = ctrl;
    ctrl.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final ctrl = _watchedController;
    if (ctrl == null) return;
    final messages = ctrl.currentConversation?.messages;
    if (messages == null || messages.isEmpty) return;
    if (messages.length <= _lastPushedCount) {
      // 沒有新訊息——可能是 isLoading 翻轉等內部狀態，不推。
      if (!ctrl.isLoading) {
        // 任務結束（可能中途有 step 更新）→ 補推最終全文。
        _pushLatestAssistantReply(done: true);
      }
      return;
    }
    _lastPushedCount = messages.length;
    final last = messages.last;
    if (last.role == 'assistant' && last.content.isNotEmpty) {
      _pushToChild({
        'type': 'assistant_reply',
        'text': last.content,
        'done': ctrl.isLoading ? false : true,
      });
    }
  }

  Future<void> _pushLatestAssistantReply({bool done = true}) async {
    final messages = _watchedController?.currentConversation?.messages;
    if (messages == null || messages.isEmpty) return;
    for (final m in messages.reversed) {
      if (m.role == 'assistant') {
        if (m.content.isNotEmpty) {
          await _pushToChild({
            'type': 'assistant_reply',
            'text': m.content,
            'done': done,
          });
        }
        return;
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 子視窗 → 主引擎的推送 helpers
  // ══════════════════════════════════════════════════════════════

  Future<void> _pushToChild(Map<String, dynamic> payload) async {
    try {
      await const WindowMethodChannel(kQuickAssistantRelayChannel)
          .invokeMethod('relay', payload);
    } catch (e) {
      debugPrint('[FloatingWindow] push to child failed: $e');
    }
  }

  Future<void> _pushHistory() async {
    final conv = _watchedController?.currentConversation;
    final messages = conv?.messages ?? const [];
    final recent = messages.length > 20
        ? messages.sublist(messages.length - 20)
        : messages;
    await _pushToChild({
      'type': 'history',
      'messages': [
        for (final m in recent)
          {'role': m.role, 'content': m.content},
      ],
    });
  }
}
