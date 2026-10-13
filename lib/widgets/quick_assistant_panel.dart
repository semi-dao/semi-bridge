// Quick Assistant Panel — Cmd+K 召喚的隨身小幫手
// [教練 Agent 2026-08-02] Phase 1 UI
//
// 設計理念：
// - 不管使用者在哪個 tab，按 Cmd+K 浮出簡易對話框
// - 延續最近的 conversation session（不開新對話）
// - 輸入框左側：模型選型 → 新增對話（+對話泡泡）→ 上傳檔案（+）
// - 送出後用 ChatController.sendDirectMessage() 發訊息
// - 按 Esc 或點遮罩關閉

import 'dart:io' show Platform;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/chat_controller.dart';
import '../models/conversation.dart';
import '../theme/bridge_design_system.dart';
import 'chat/agent_model_selector.dart';
import 'dart:async' show unawaited;
import '../services/quick_assistant/quick_assistant_context.dart';
import '../services/quick_assistant/floating_window_service.dart'; // [無限插槽 C1 2026-10-06 移植]
import '../screens/bridge_desktop_screen.dart';
import '../app.dart' show appRouter;

/// 全域 Quick Assistant 管理器 — 控制 懸浮窗（優先）與 OverlayEntry 的顯示/隱藏
///
/// [無限插槽 C1 2026-10-06 移植] 桌面平台優先走系統級懸浮窗
/// （FloatingWindowService，不受主視窗邊界限制、全域 Cmd+Shift+K 可呼出）；
/// kIsWeb 或非桌面平台 fallback 到原本的 OverlayEntry in-window overlay
/// （程式碼完整保留——含 10-05 隨身小幫手 v2/v3 進化）。
class QuickAssistantManager {
  static OverlayEntry? _entry;
  static ChatController? _fallbackController;  // [教練 Agent 2026-08-03] 獨立 controller fallback

  static bool get isOpen =>
      _entry != null || FloatingWindowService.instance.isVisible;

  /// 開啟 Quick Assistant
  /// [controller] 桌面主聊天的 ChatController（可選 — 沒傳會自己取或創建）
  /// [currentPage] 當前頁面名稱（給 Agent 知道你在哪）
  static void open(BuildContext context, [ChatController? controller, String currentPage = 'unknown']) {
    if (isOpen) return; // 已開啟就不重複

    // [無限插槽 C1 2026-10-06 移植] 桌面 → 系統級懸浮窗（fire-and-forget，
    // 建立是 async）。建立失敗（plugin 不可用等）→ fallback 到 overlay。
    // async gap 之後不解引用傳入的 context——fallback 一律改用全域
    // navigatorKey 的 context（同步取好傳入，避免 use_build_context_synchronously）。
    if (FloatingWindowService.instance.isPlatformSupported) {
      final navContext = appRouter.routerDelegate.navigatorKey.currentContext;
      unawaited(
        FloatingWindowService.instance.showOrCreate().then((_) {
          if (FloatingWindowService.instance.isVisible) return;
          if (navContext != null && navContext.mounted) {
            _openOverlay(navContext, controller, currentPage);
          }
        }),
      );
      return;
    }
    _openOverlay(context, controller, currentPage);
  }

  /// [無限插槽 C1 2026-10-06 移植] 原 OverlayEntry 路徑（Web/不支援平台 fallback）
  static void _openOverlay(BuildContext context, [ChatController? controller, String currentPage = 'unknown']) {
    if (_entry != null) return; // 已開啟就不重複

    // [教練 Agent 2026-08-03] 自動取 controller
    // 1. 優先用傳入的
    // 2. 從 BridgeDesktopScreen.activeChatController 取
    // 3. 真的沒有 — 自己建獨立 controller（任何 tab 都能開）
    ChatController? ctrl = controller;
    ctrl ??= _findActiveController(context);
    ctrl ??= ensureFallbackController();

    // [教練 Agent 2026-08-03] 進入 Quick Assistant 模式
    // 創建 context（含當前頁面、App 診斷資訊）
    final ctx = QuickAssistantContext(
      currentPage: currentPage,
      appDiagnostics: {
        'app_version': '0.1.0',  // TODO: 從 package_info 取
        'os': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
      },
    );
    ctrl.enterQuickAssistantMode(ctx);

    _entry = OverlayEntry(
      builder: (ctx) => QuickAssistantOverlay(
        controller: ctrl!,
        onClose: close,
      ),
    );
    // [教練 Agent 2026-08-18 使用者 抓包] 修 Cmd+K 無反應：
    // BridgeShortcuts 包在 MaterialApp.router 外面，其 context 頂上沒有
    // Overlay，Overlay.of 直接 null crash（快捷鍵其實有觸發，只是開面板時炸）。
    // 修法：优先用傳入的 context；拿不到 Overlay 就 fallback 到
    // GoRouter navigatorKey 的 context（MaterialApp 內部，一定有 Overlay）。
    OverlayState? overlay;
    try {
      overlay = Overlay.maybeOf(context, rootOverlay: true);
    } catch (_) {
      overlay = null;
    }
    overlay ??= appRouter.routerDelegate.navigatorKey.currentState?.overlay;
    if (overlay == null) {
      debugPrint('[QuickAssistant] 找不到 Overlay——Cmd+K 開啟失敗（請回報）');
      ctrl.exitQuickAssistantMode();
      return;
    }
    overlay.insert(_entry!);
  }

  /// 嘗試從全域取得 active controller
  static ChatController? _findActiveController(BuildContext context) {
    try {
      return activeControllerAccessor?.call();
    } catch (e) {
      return null;
    }
  }

  /// 註冊全域 controller accessor（bridge_shortcuts 設定）
  static ChatController? Function()? activeControllerAccessor;

  /// 取得/建立 fallback controller
  /// [無限插槽 C1 2026-10-06 移植] 改 public——FloatingWindowService 的 relay
  /// 也要用同一條 fallback controller 慣例（active → 獨立 fallback）。
  static ChatController ensureFallbackController() {
    _fallbackController ??= ChatController();
    // [2026-08-26 身份污染追根] fallback controller 也要載入 active companion——
    // 人格注入鏈依賴 controller._activeCompanion（全系統同款病根，一次修完）。
    _fallbackController!.loadActiveCompanion();
    return _fallbackController!;
  }

  /// [無限插槽 C1 2026-10-06 移植] 退出所有 controller 的 Quick Assistant 模式
  /// （不動 overlay——FloatingWindowService.hide() 用；overlay fallback 的
  /// close() 仍走原本路徑）。
  static void exitModes() {
    if (_fallbackController != null && _fallbackController!.isQuickAssistantMode) {
      _fallbackController!.exitQuickAssistantMode();
    }
    final active = activeControllerAccessor?.call();
    if (active != null && active.isQuickAssistantMode) {
      active.exitQuickAssistantMode();
    }
  }

  static void close() {
    // [無限插槽 C1 2026-10-06 移植] 桌面懸浮窗優先關（hide，不銷毀）。
    if (FloatingWindowService.instance.isPlatformSupported &&
        FloatingWindowService.instance.isVisible) {
      unawaited(FloatingWindowService.instance.hide());
      return;
    }
    // [教練 Agent 2026-08-03] 關閉時退出 quick assistant mode
    if (_fallbackController != null && _fallbackController!.isQuickAssistantMode) {
      _fallbackController!.exitQuickAssistantMode();
    }
    // 同時清掉 active controller 的 mode
    final active = activeControllerAccessor?.call();
    if (active != null && active.isQuickAssistantMode) {
      active.exitQuickAssistantMode();
    }
    _entry?.remove();
    _entry = null;
  }
}

/// Quick Assistant 遮罩層
class QuickAssistantOverlay extends StatefulWidget {
  final ChatController controller;
  final VoidCallback onClose;

  const QuickAssistantOverlay({
    super.key,
    required this.controller,
    required this.onClose,
  });

  @override
  State<QuickAssistantOverlay> createState() => _QuickAssistantOverlayState();
}

class _QuickAssistantOverlayState extends State<QuickAssistantOverlay> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  bool _isSending = false;

  // 最近訊息（顯示用）
  List<Message> _recentMessages = [];

  // [小葵 2026-10-05 Blue 抓包] 思考中狀態跨面板重建存活——
  // 切頁面再切回來，轉圈圈不見、失去觀察線索。
  // 修法：面板直接聽 ChatController（持久層）——她還在想，
  // 面板重建後仍然顯示「思考中」。本地引擎每步 2 分鐘，
  // 觀察線索就是共視的眼睛，不能丟。
  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {
      _loadRecentMessages();
    });
  }

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _focusNode = FocusNode();
    widget.controller.addListener(_onControllerChanged);
    // 自動聚焦輸入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    _loadRecentMessages();
  }

  void _loadRecentMessages() {
    final conv = widget.controller.currentConversation;
    if (conv != null && conv.messages.isNotEmpty) {
      // [小葵 2026-10-05 Blue 抓包] 舊值 take(3)——對話歷史看不到、
      // 滾輪無東西可滾。載最近 40 則，可滾動回顧。
      _recentMessages =
          conv.messages.reversed.take(40).toList().reversed.toList();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    // [教練 Agent 2026-08-03] 退出 quick assistant mode（保險起見）
    if (widget.controller.isQuickAssistantMode) {
      widget.controller.exitQuickAssistantMode();
    }
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      // [教練 Agent 2026-08-03] 改用 sendAssistantMessage — 自動注入 context + 截圖
      await widget.controller.sendAssistantMessage(text);
      _textController.clear();
      _loadRecentMessages();
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _focusNode.requestFocus();
      }
    }
  }

  Future<void> _newConversation() async {
    await widget.controller.createNewConversation();
    setState(_loadRecentMessages);
    _focusNode.requestFocus();
  }

  Future<void> _attachFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: kIsWeb,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (!kIsWeb && file.path != null) {
          // Desktop: 直接用路徑送出
          await widget.controller.sendDirectMessage(
            _textController.text.trim().isNotEmpty
                ? _textController.text.trim()
                : '請分析這張圖片',
            imagePath: file.path,
          );
          _textController.clear();
          _loadRecentMessages();
        }
      }
    } catch (e) {
      debugPrint('[QuickAssistant] 檔案選擇失敗: $e');
    }
    if (mounted) _focusNode.requestFocus();
  }

  // [教練 Agent 2026-08-03] 浮動雲狀態
  Offset _panelPosition = const Offset(20, 80);  // 預設右上角
  bool _isDragging = false;
  bool _isCollapsed = false;  // 摺疊模式（只顯示標題列）

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final panelWidth = isDesktop ? 480.0 : MediaQuery.of(context).size.width * 0.9;
    final screenSize = MediaQuery.of(context).size;

    // 限制在畫面範圍內
    _panelPosition = Offset(
      _panelPosition.dx.clamp(0, screenSize.width - panelWidth - 20),
      _panelPosition.dy.clamp(0, screenSize.height - 200),
    );

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
        }
      },
      // [小葵 2026-09-24 Blue 抓包] 紅屏修復——本 overlay 掛在 root Overlay，
      // 祖先鏈上沒有任何 Material，面板內的 InkWell（_iconButton/_sendButton）
      // 需要 Material 祖先渲染水波紋 → "No Material widget found" 紅屏。
      // 修：根部包透明 Material（不影響視覺、不擋 hit-test）。
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
          // Panel（浮動、可拖曳、可摺疊）
          Positioned(
            left: _panelPosition.dx,
            top: _panelPosition.dy,
            child: GestureDetector(
              // [教練 Agent 2026-08-03] 拖曳整個 panel
              onPanStart: (details) {
                setState(() => _isDragging = true);
              },
              onPanUpdate: (details) {
                setState(() {
                  _panelPosition = _panelPosition + details.delta;
                });
              },
              onPanEnd: (details) {
                setState(() => _isDragging = false);
              },
              child: MouseRegion(
                cursor: _isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: panelWidth,
                  constraints: BoxConstraints(
                    // [小葵 2026-10-05 Blue 抓包] 摺疊溢出修復——
                    // 折疊時 header（padding 24 + IconButton 最小互動高 48）
                    // 需要約 72px，舊值 60 每次摺疊都 BOTTOM OVERFLOWED 6px
                    // 黑黃警示條。放寬到 88 安全餘裕。
                    maxHeight: _isCollapsed ? 88 : screenSize.height * 0.7,
                  ),
                  decoration: BoxDecoration(
                    color: ds.surface.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ds.borderDefault, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 標題列（可拖、可摺疊、可關）
                      _buildHeader(ds),
                      // [教練 Agent 2026-08-03] 摺疊時不顯示內容
                      if (!_isCollapsed) ...[
                        // [小葵 2026-10-05 Blue 抓包] 她在想——跨面板重建的
                        // 觀察線索（切頁回來也看得到她在動）。controller
                        // 持久，_isSending 只是本面板的輸入鎖。
                        if (widget.controller.isLoading || _isSending)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _isSending
                                      ? '思考中…（本地引擎較慢，每步約 2 分鐘）'
                                      : '還在想…（工具循環進行中，離開頁面也不會中斷）',
                                  style: BridgeDS.small
                                      .copyWith(color: ds.textTertiary),
                                ),
                              ],
                            ),
                          ),
                        // 最近訊息預覽
                        if (_recentMessages.isNotEmpty) _buildRecentMessages(ds),
                        // 輸入區
                        _buildInputArea(ds),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BridgeDSColors ds) {
    final conv = widget.controller.currentConversation;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: ds.accentMiro),
          const SizedBox(width: 8),
          Text(
            '隨身小幫手',
            style: BridgeDS.headingS.copyWith(color: ds.textPrimary),
          ),
          const SizedBox(width: 8),
          if (conv != null)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ds.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  conv.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BridgeDS.small.copyWith(color: ds.textTertiary),
                ),
              ),
            ),
          const Spacer(),
          // [教練 Agent 2026-08-03] 摺疊/展開按鈕
          IconButton(
            icon: Icon(
              _isCollapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded,
              size: 18,
            ),
            iconSize: 18,
            tooltip: _isCollapsed ? '展開' : '摺疊',
            onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            iconSize: 18,
            tooltip: '關閉 (Esc)',
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentMessages(BridgeDSColors ds) {
    return Flexible(
      child: Container(
        // [小葵 2026-10-05 Blue 抓包] 舊值 200——擠成三行摘要。
        // 放寬讓歷史有空間展開（外層 maxHeight 0.7 螢幕高約束仍在）。
        constraints: const BoxConstraints(maxHeight: 420),
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: ds.canvas,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          reverse: true,
          itemCount: _recentMessages.length,
          itemBuilder: (context, index) {
            final msg = _recentMessages[_recentMessages.length - 1 - index];
            final isUser = msg.role == 'user';
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isUser ? Icons.person_outline : Icons.smart_toy_outlined,
                    size: 14,
                    color: isUser ? ds.accentBlue : ds.accentGreen,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      // [小葵 2026-10-05 Blue 抓包] 舊 maxLines:2 截斷——
                      // 回應內容沒有完整顯示。全文顯示。
                      msg.content,
                      style:
                          BridgeDS.small.copyWith(color: ds.textSecondary),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInputArea(BridgeDSColors ds) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        children: [
          // 工具列
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(
              children: [
                // 模型選型
                AgentModelSelector(
                  floating: true,
                  onProviderChanged: () {
                    widget.controller.refreshLocalModelState();
                  },
                ),
                const SizedBox(width: 4),
                // 新增對話（＋對話泡泡）
                _iconButton(
                  icon: Icons.add_comment_outlined,
                  tooltip: '新增對話',
                  color: ds.textTertiary,
                  onTap: _newConversation,
                ),
                const SizedBox(width: 4),
                // 上傳檔案（＋）
                _iconButton(
                  icon: Icons.attach_file_outlined,
                  tooltip: '上傳圖片或檔案',
                  color: ds.textTertiary,
                  onTap: _attachFile,
                ),
                const Spacer(),
                // 送出按鈕
                if (_textController.text.trim().isNotEmpty || _isSending)
                  _sendButton(ds),
              ],
            ),
          ),
          // 輸入框
          TextField(
            controller: _textController,
            focusNode: _focusNode,
            maxLines: 4,
            minLines: 1,
            textInputAction: TextInputAction.send,
            style: BridgeDS.body.copyWith(color: ds.textPrimary),
            decoration: InputDecoration(
              hintText: '問任何問題…',
              hintStyle: BridgeDS.body.copyWith(color: ds.textMuted),
              filled: true,
              fillColor: ds.canvas,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: ds.accentMiro, width: 1.5),
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _send(),
          ),
        ],
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _sendButton(BridgeDSColors ds) {
    return Semantics(
      label: '發送訊息',
      button: true,
      child: InkWell(
        onTap: _isSending ? null : _send,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: ds.accentMiro,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _isSending
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(ds.textPrimary),
                  ),
                )
              : Icon(Icons.send_rounded, size: 16, color: ds.textPrimary),
        ),
      ),
    );
  }
}
