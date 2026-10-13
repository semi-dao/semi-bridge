// Quick Assistant 懸浮窗 — 系統級子視窗 entrypoint
// [無限插槽 C1 2026-10-06] spec: docs/specs/2026-10-04-infinite-slot-system.md
//
// 架構：
// - 本檔是「子視窗」的 Flutter engine 進入點。desktop_multi_window（macOS fork
//   0.3.1，WindowChannel 雙向通訊版）在建立子視窗時會以
//   dartEntrypointArguments = ["multi_window", windowId, arguments] 啟動新引擎，
//   並呼叫 main(args)。main.dart 依 args[0]=='multi_window' 把執行流導到這裡。
// - 子視窗是「遙控器」：只有 UI。所有對話邏輯（ChatController、Agent Loop、
//   API key、記憶）都留在主引擎——子視窗絕不實例化 ChatController。
// - 通訊走 WindowChannel（雙向，主/子兩端都 setMethodCallHandler）：
//
//   子 → 主：
//     {"type":"user_message","text": String}
//     {"type":"window_ready"}            // 子視窗 UI 就緒
//     {"type":"hide_request"}            // 子視窗自請隱藏（Esc / ✕）
//
//   主 → 子：
//     {"type":"assistant_reply","text": String, "done": bool}
//     {"type":"status","text": String}
//     {"type":"history","messages":[{"role":String,"content":String}, ...]}
//
//   methods: invokeMethod('relay', jsonMap)；控制流走 WindowController 的
//   window_show / window_hide（plugin 內建，主端呼叫，子端 handler 轉發給
//   window_manager——子引擎的 window_manager 绑定的是子視窗自己）。
//
// 視覺規格（Blue 鐵律）：黑底、無邊框、白字黑陰影，與既有懸浮 companion 窗同款。

import 'dart:io' show File, FileMode;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'theme/bridge_design_system.dart';
import 'theme/tier.dart';
import 'theme/tier_style.dart';
import 'widgets/chat/agent_model_selector.dart'; // [Blue 抓包 2026-10-06 問題2] 模型選擇器

/// 主引擎 ↔ 子視窗共用的 relay channel 名稱。
const String kQuickAssistantRelayChannel = 'bridge.quick_assistant.relay.v1';

/// 子視窗 arguments 標記（主端建立視窗時傳入，子端比對用）。
const String kQuickAssistantWindowArg = 'quick_assistant';

/// 是否為 Quick Assistant 子視窗啟動（main.dart 的 entry routing 用）。
///
/// [2026-10-06 C1 驗屍] fork 版 desktop_multi_window 把 arguments 以 JSON
/// 編碼傳入——args[2] 可能是 `"quick_assistant"`（帶引號）而非裸字串。
/// 精確比對失敗時子引擎會跑成完整主 App（實測症狀：TCC 檔案權限彈窗＋
/// 500x500 隱藏視窗）。改為「剝引號後精確比對」，並把每次啟動 args
/// 落地 /tmp/qa_args.log 供驗屍。
bool isQuickAssistantWindowLaunch(List<String> args) {
  if (args.length < 3 || args[0] != 'multi_window') return false;
  final raw = args[2];
  try {
    File('/tmp/qa_args.log').writeAsStringSync(
      '[${DateTime.now()}] args=$args\n',
      mode: FileMode.append,
    );
  } catch (_) {}
  final stripped = raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')
      ? raw.substring(1, raw.length - 1)
      : raw;
  return stripped == kQuickAssistantWindowArg;
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final controller = await WindowController.fromCurrentEngine();

  // [2026-10-06 C1 驗屍 #2] 原本在這裡 await windowManager.ensureInitialized()
  // 直接炸 MissingPluginException——子引擎沒註冊 window_manager plugin，
  // main 中止 → relay handler 永遠沒註冊 → 主引擎握手永遠逾時。
  // 修法：
  // 1) 先註冊 window controller handler（show/hide 走 plugin 原生
  //    makeKeyAndOrderFront/orderOut，完全不依賴 window_manager）
  // 2) window_manager 的樣式設定全部包 try-catch（有註冊就套、沒有就跳過）
  // 3) relay handler 註冊完才 runApp——握手順序保證
  await controller.setWindowMethodHandler((call) async {
    switch (call.method) {
      // [C1 驗屍 #4] 攔截就必須真的做事——只 return null 等於把視窗
      // 悄悄吞掉（native default handler 不會再接手）。
      // window_manager 已透過 AppDelegate 的 setOnWindowCreatedCallback
      // 對子引擎註冊，這裡可以安全呼叫。
      case 'window_show':
        await windowManager.show();
        await windowManager.focus();
        return null;
      case 'window_hide':
      case 'window_close_and_hide':
        await windowManager.hide();
        return null;
      default:
        return null;
    }
  });

  // 子視窗規格：黑底、無邊框、浮動、可拖曳（樣式盡力而為——
  // 子引擎環境有 window_manager 就套用，沒有就不擋 main）。
  try {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(420, 560),
        minimumSize: Size(320, 380),
        // [Blue 令 2026-10-06 問題3] 可縮放——使用者依需要自由調整大小，
        // 320x380 下限防縮到不見，最大不設限。
        maximumSize: Size(2000, 2000),
        titleBarStyle: TitleBarStyle.hidden,
        backgroundColor: Color(0xFF07080A),
        skipTaskbar: true,
      ),
      () async {
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setPreventClose(true);
        await windowManager.setResizable(true); // [問題3] 拖邊框自由縮放
        await windowManager.setSize(const Size(420, 560));
        await windowManager.setAlignment(Alignment.bottomRight);
      },
    );
    // 隱藏 ≠ 關閉：訊息歷史留在主引擎，子視窗 engine 常駐。
    windowManager.addListener(_ChildWindowLifecycleHandler());
  } catch (e) {
    debugPrint('[QAWindow] window_manager 樣式套用失敗（子引擎無此 plugin）: $e');
  }

  runApp(_QuickAssistantWindowApp(controller: controller));
}

/// 子視窗關閉鈕 → 隱藏（conversation 持續留在主引擎）。
class _ChildWindowLifecycleHandler extends WindowListener {
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }
}

class _QuickAssistantWindowApp extends StatelessWidget {
  const _QuickAssistantWindowApp({required this.controller});

  final WindowController controller;

  // [C1 驗屍 #3] app.dart 同款快取——FutureBuilder 裡每次 build 都呼叫
  // loadDefaultTierTheme() 會在過渡幀拿到 null 走 spinner 分支，行為
  // 難以預期；模組內部雖有 cache，這裡再顯式快取一次對齊 app.dart。
  static Future<TierTheme>? _tierThemeFuture;

  @override
  Widget build(BuildContext context) {
    // Tier manifest 必須載入後才能建功能 UI——TierStyle.of 沒註冊 TierTheme
    // 會直接 throw（app.dart 同款鐵律）。
    return FutureBuilder<TierTheme>(
      future: _tierThemeFuture ??= loadDefaultTierTheme(),
      builder: (context, snapshot) {
        final tierTheme = snapshot.data;
        if (tierTheme == null) {
          // 載入中的佔位頁（同 app.dart 慣例：ThemeData.dark()，不屬正式 UI）。
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(),
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        // 黑底子視窗固定用 dark token（Blue 懸浮窗規格）。
        // [C1 驗屍 #3] theme 與 darkTheme 都給——themeMode 預設 system，
        // 系統深色時走 darkTheme（若只給 theme 理論上會 fallback，但
        // 顯式給雙份消除任何不確定性。
        final themeData = BridgeDS.themeFrom(
          BridgeDSColors.dark,
          tierTheme: tierTheme,
        );
        debugPrint(
          '[QAWindow] themeData extensions: tierTheme='
          '${themeData.extension<TierTheme>() != null} '
          'colors=${themeData.extension<BridgeDSColors>() != null}',
        );
        return MaterialApp(
          title: 'Bridge 隨身小幫手',
          debugShowCheckedModeBanner: false,
          theme: themeData,
          darkTheme: themeData,
          // [C1 驗屍 #3] 顯式再包一層 Theme——MaterialApp 內部主題解析
          // 在子引擎環境下丟失 ThemeExtension（實測 themeData 內
          // tierTheme=true 但 TierStyle.of 仍拿不到）；直接把帶 extension
          // 的 Theme 壓在 panel 頭上，繞過任何中介。
          home: Theme(
            data: themeData,
            child: QuickAssistantFloatingPanel(controller: controller),
          ),
        );
      },
    );
  }
}

/// 子視窗主體：訊息列表 + 輸入框 + 送出鈕。
///
/// 狀態只有「畫面用的訊息鏡像」——真相源永遠在主引擎的 ChatController。
class QuickAssistantFloatingPanel extends StatefulWidget {
  const QuickAssistantFloatingPanel({super.key, required this.controller});

  final WindowController controller;

  @override
  State<QuickAssistantFloatingPanel> createState() =>
      _QuickAssistantFloatingPanelState();
}

class _QuickAssistantFloatingPanelState
    extends State<QuickAssistantFloatingPanel> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scroll = ScrollController();

  final List<_Bubble> _messages = [];
  String? _statusText;
  bool _busy = false;
  Future<dynamic> Function(MethodCall call)? _relayHandler;

  @override
  void initState() {
    super.initState();
    _installRelayHandler();
    // UI 就緒 → 通知主引擎推歷史回來（hide 不 destroy，重開續接對話）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _invokeMain({'type': 'window_ready'});
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    // 移除 relay handler（engine 收掉時 ChannelRegistry 弱引用本就會清，
    // 但顯式移除更乾淨）。
    if (_relayHandler != null) {
      const WindowMethodChannel(kQuickAssistantRelayChannel)
          .setMethodCallHandler(null);
    }
    super.dispose();
  }

  Future<void> _installRelayHandler() async {
    final handler = _relayHandler = (MethodCall call) async {
      if (call.method != 'relay') return null;
      final data = (call.arguments as Map).cast<String, dynamic>();
      switch (data['type'] as String?) {
        case 'history':
          final list = (data['messages'] as List? ?? const [])
              .cast<Map>()
              .map((m) => _Bubble(
                    isUser: m['role'] == 'user',
                    text: m['content'] as String? ?? '',
                  ))
              .toList();
          if (!mounted) return null;
          setState(() {
            _messages
              ..clear()
              ..addAll(list);
            _statusText = null;
          });
          _scrollToBottom();
          return null;
        case 'assistant_reply':
          if (!mounted) return null;
          final text = data['text'] as String? ?? '';
          setState(() {
            if (_messages.isNotEmpty && !_messages.last.isUser && _busy) {
              _messages.last = _Bubble(isUser: false, text: text);
            } else {
              _messages.add(_Bubble(isUser: false, text: text));
            }
            _statusIsLive = false;
            if (data['done'] == true) {
              _busy = false;
              _statusText = null;
              _inputFocus.requestFocus();
            }
          });
          _scrollToBottom();
          return null;
        case 'status':
          if (!mounted) return null;
          setState(() {
            _statusText = data['text'] as String?;
            _busy = true;
            // 佔位泡泡（空文字 + spinner）：只在還沒有活著的佔位時加一顆。
            if (!_statusIsLive) {
              _messages.add(const _Bubble(isUser: false, text: ''));
              _statusIsLive = true;
            }
          });
          _scrollToBottom();
          return null;
        default:
          return null;
      }
    };
    await const WindowMethodChannel(kQuickAssistantRelayChannel)
        .setMethodCallHandler(handler);
  }

  bool _statusIsLive = false;

  Future<void> _invokeMain(Map<String, dynamic> payload) async {
    try {
      await const WindowMethodChannel(kQuickAssistantRelayChannel)
          .invokeMethod('relay', payload);
    } catch (e) {
      debugPrint('[QAWindow] relay to main failed: $e');
    }
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _messages.add(_Bubble(isUser: true, text: text));
      _busy = true;
      _statusText = '思考中…';
      _statusIsLive = false;
    });
    _input.clear();
    _scrollToBottom();
    _invokeMain({'type': 'user_message', 'text': text});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // 子視窗有自己的 MaterialApp（BridgeDS.darkTheme），BridgeDSColors.of /
    // TierStyle.of 都能正確解析——禁止任何硬編碼顏色。
    final ds = BridgeDSColors.of(context);
    final tierTitle = TierStyle.of(context, Tier.dialogTitle).toTextStyle();
    final tierBody = TierStyle.of(context, Tier.dialogBody).toTextStyle();

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _hide();
        }
      },
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          // 黑底 + 黑陰影（Blue 懸浮窗鐵律）；文字陰影吃 theme 層的白字黑影。
          decoration: BoxDecoration(
            color: ds.canvas,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 36,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(ds, tierTitle),
              Container(height: 1, color: ds.borderSubtle),
              Expanded(child: _buildMessageList(ds, tierBody)),
              if (_statusText != null) _buildStatusBar(ds),
              Container(height: 1, color: ds.borderSubtle),
              _buildInputArea(ds),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BridgeDSColors ds, TextStyle titleStyle) {
    return GestureDetector(
      // 無邊框視窗的拖曳把手：整條標題列都是拖曳區。
      onPanStart: (_) => windowManager.startDragging(),
      child: Padding(
        // [Blue 2026-10-06 抓包] 左側讓位系統交通燈（紅黃綠三圓鈕）——
        // TitleBarStyle.hidden 在 macOS 仍會保留 overlay 式交通燈（約 70px），
        // 原本 14px 起跳導致標題與圓鈕重疊。標題移到右側起點 = 圓鈕右邊。
        padding: const EdgeInsets.fromLTRB(78, 10, 8, 8),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: ds.accentMiro),
            const SizedBox(width: 8),
            Text('隨身小幫手', style: titleStyle),
            const Spacer(),
            InkWell(
              onTap: _hide,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(Icons.close_rounded, size: 16, color: ds.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(BridgeDSColors ds, TextStyle bodyStyle) {
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '問任何問題…\n Cmd+Shift+K 隨時呼出／收起',
            textAlign: TextAlign.center,
            style: bodyStyle.copyWith(
              color: ds.textMuted,
              shadows: [const Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final empty = m.text.isEmpty;
        if (empty && _statusText != null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(ds.accentMiro),
                  ),
                ),
                const SizedBox(width: 8),
                Text(_statusText!, style: bodyStyle.copyWith(color: ds.textSecondary)),
              ],
            ),
          );
        }
        return Align(
          alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            constraints: const BoxConstraints(maxWidth: 330),
            decoration: BoxDecoration(
              color: m.isUser ? ds.surfaceElevated : ds.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ds.borderSubtle),
            ),
            child: SelectableText(
              m.text,
              style: bodyStyle.copyWith(
                // 白字黑影（Blue 懸浮窗規格）——文字色跟主題 token，陰影固定黑。
                color: ds.textPrimary,
                shadows: [const Shadow(color: Colors.black, blurRadius: 3)],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBar(BridgeDSColors ds) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _statusText!,
          style: BridgeDS.small.copyWith(
            color: ds.textTertiary,
            shadows: [const Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea(BridgeDSColors ds) {
    return Padding(
      // [Blue 抓包 2026-10-06 問題2] 模型選擇器回歸——懸浮窗版是新寫的，
      // 漏放了舊 overlay 版有的 AgentModelSelector。floating 模式
      // （OverlayPortal+LayerLink）本來就是為隨身小幫手這種面板設計的。
      // 子引擎只改 StorageService（SharedPreferences，主引擎同 process
      // 共用）；切換後主引擎的 controller 下一輪 getProvider 自然生效。
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Row(
              children: [
                AgentModelSelector(floating: true),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _inputFocus,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              style: BridgeDS.body.copyWith(
                color: ds.textPrimary,
                shadows: [const Shadow(color: Colors.black, blurRadius: 3)],
              ),
              decoration: InputDecoration(
                hintText: '問任何問題…',
                hintStyle: BridgeDS.body.copyWith(color: ds.textMuted),
                filled: true,
                fillColor: ds.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: ds.accentMiro, width: 1.5),
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _busy ? null : _send,
            borderRadius: BorderRadius.circular(9),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: ds.accentMiro,
                borderRadius: BorderRadius.circular(9),
              ),
              child: _busy
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
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _hide() async {
    await _invokeMain({'type': 'hide_request'});
    await windowManager.hide();
  }
}

/// 畫面用的訊息鏡像（真相源在主引擎）。
class _Bubble {
  const _Bubble({required this.isUser, required this.text});
  final bool isUser;
  final String text;
}
