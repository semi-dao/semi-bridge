// galaxy_screensaver_overlay.dart
// 橋樑星系保護模式 — App 內自帶螢幕保護程式
//
// [小葵 2026-09-01 Blue 拍板 A 路線]：
// 系統級 .saver 被 macOS 26 Gatekeeper 靜默封鎖（adhoc 簽名 rejected）。
// 改走 App 內路線：只要 App 開著，閒置 N 分鐘 → 滿屏 3D 大腦星系；
// 動一下滑鼠/鍵盤即退出。使用者可把 Apple 內建螢幕保護程式關掉，
// 由橋樑 App 全權負責這台機器的「待機之美」。
//
// 設計：
// - Listener 攔截全域指標事件重置 idle 計時（鍵盤由 Focus 系統觸發的
//   指標移動/文字輸入也會伴隨指標事件； macOS 桌面 App 鍵盤輸入時
//   通常游標也在動，此近似對保護程式場景夠用）
// - 觸發：全螢幕黑色 Stack 蓋最上層 + GalaxyWebView（自帶 token 取用
//   + localhost:8420/galaxy 三.js 星系）
// - 退出：任何 pointer down/move（超過小閾值防誤觸）
// - 隱藏游標：進入時 SystemChrome 隱藏（macOS 上 MouseCursor.defer）

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/dev_paths.dart';
import 'brain/galaxy_webview.dart';

/// 星系保護模式 controller——掛在 App root
class GalaxyScreensaverController extends ChangeNotifier {
  GalaxyScreensaverController({this.idleTimeout = const Duration(minutes: 3)});

  /// 閒置多久觸發（預設 3 分鐘）
  final Duration idleTimeout;

  bool _active = false;
  bool get isActive => _active;

  /// 功能總開關（false = 完全不觸發）
  bool enabled = true;

  Timer? _idleTimer;

  /// 任何使用者活動呼叫——重置計時器
  void reportActivity() {
    if (_active) return; // 保護中：退出邏輯由 overlay 處理
    if (!enabled) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, _trigger);
  }

  void _trigger() {
    if (!enabled || _active) return;
    _active = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    notifyListeners();
  }

  /// 退出保護模式
  void dismiss() {
    if (!_active) return;
    _active = false;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, _trigger); // 重新計時
    notifyListeners();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }
}

/// 星系保護 overlay——用 AnimatedBuilder 掛在 root Stack 最上層
class GalaxyScreensaverOverlay extends StatefulWidget {
  const GalaxyScreensaverOverlay({
    super.key,
    required this.controller,
    required this.child,
  });

  final GalaxyScreensaverController controller;
  final Widget child;

  @override
  State<GalaxyScreensaverOverlay> createState() =>
      _GalaxyScreensaverOverlayState();
}

class _GalaxyScreensaverOverlayState extends State<GalaxyScreensaverOverlay> {
  Offset? _lastPointerPos;
  bool _chromeSaverAvailable = false; // [v263] Chrome 保護視窗是否成功開啟

  // [v263 Blue 令] 保護畫面改 Chrome 全螢幕（絲滑保證——嵌入式引擎會被
  // macOS 節流）。失敗（無 Chrome）→ fallback 嵌入式 GalaxyWebView。
  // [v264 Blue 令] 三級偵測鏈：Chrome App 模式 → 系統預設瀏覽器 → 嵌入式
  void _openSaverChromeWindow() {
    _chromeSaverAvailable = false;
    String? token;
    try {
      final f = File(resolveDevPath('~/Library/Application Support/farm.semiwasabi.bridgeApp/mcp_token'));
      if (f.existsSync()) token = f.readAsStringSync().trim();
    } catch (_) {}
    final url = 'http://localhost:8420/galaxy?token=$token&saver=1';
    // [v269 穩修] 判斷 Chrome 在不在改用 pgrep（免 TCC 權限——System Events
    // 查詢可能被擋=誤判沒在跑→走錯分支→--args 丟失→saver 開不成→fallback 嵌入式）
    final chromeRunning = Process.runSync('pgrep', ['-x', 'Google Chrome']).exitCode == 0;
    _slog('chromeRunning=$chromeRunning');
    if (chromeRunning) {
      // Chrome 在跑 → AppleScript make new window + 設 URL + 置前
      try {
        _slog('branch A: make new window...');
        final mk = Process.runSync('osascript', ['-e',
          'tell application "Google Chrome" to make new window']);
        _slog('make window exit=${mk.exitCode} err=${mk.stderr.toString().trim()}');
        Process.runSync('osascript', ['-e',
          'tell application "Google Chrome"'
          ' to set URL of active tab of front window to "' + url + '"']);
        // [v270] activate 帶 Chrome+saver 視窗到前景（切 Space）。
        // 競態對策：App 黑幕剛蓋上時 activate 可能被埋——1.2 秒後補一次。
        Process.runSync('osascript', ['-e',
          'tell application "Google Chrome" to activate']);
        Future.delayed(const Duration(milliseconds: 1200), () {
          try {
            Process.runSync('osascript', ['-e',
              'tell application "Google Chrome" to activate']);
          } catch (_) {}
        });
        _chromeSaverAvailable = true;
        debugPrint('[v270] 保護視窗: Chrome 新視窗（activate 雙保險）');
        if (mounted) setState(() {});
        return;
      } catch (e) {
        _slog('branch A EXCEPTION: $e');
      }
    } else {
      // Chrome 沒跑 → open -na 直接帶 URL（不帶 --args——參數才不會丟）
      try {
        _slog('branch B: open -na new instance...');
        final r = Process.runSync('open', ['-na', 'Google Chrome', url]);
        if (r.exitCode == 0) {
          _chromeSaverAvailable = true;
          debugPrint('[v269] 保護視窗: Chrome 新 instance');
          if (mounted) setState(() {});
          return;
        }
      } catch (_) {}
    }
    _slog('reached default-browser branch (A/B both failed or skipped)');
    // ② 系統預設瀏覽器（open 不帶 -a = macOS 自动用預設瀏覽器開）
    try {
      final r = Process.runSync('open', [url]);
      if (r.exitCode == 0) {
        _chromeSaverAvailable = true;
        debugPrint('[v264] 保護視窗: 系統預設瀏覽器');
        return;
      }
    } catch (_) {}
    // ③ 都失敗 → fallback 嵌入式 GalaxyWebView（App 內建，會被節流但堪用）
    debugPrint('[v264] 保護視窗: 嵌入式 fallback');
    _slog('FALLBACK embedded (all browser branches failed)');
  }

  void _closeSaverChromeWindow() {
    // 對常見瀏覽器逐一嘗試關「星系保護模式」視窗（不知道預設是哪個就全試）
    const apps = [
      'Google Chrome', 'Microsoft Edge', 'Brave Browser', 'Arc',
      'Safari', 'Firefox', 'Dia', 'Orion',
    ];
    for (final a in apps) {
      try {
        Process.runSync('osascript', ['-e',
          'tell application "$a" to close (every window whose title contains "星系保護模式")']);
      } catch (_) {}
    }
    _chromeSaverAvailable = false;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSaverStateChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSaverStateChanged);
    super.dispose();
  }

  // [v271 診斷令] 黑盒子——App 自動觸發時到底發生什麼（Blue 三次查證：
  // 手動跑=網頁版成功、App 自動=App 版——中間必有一步沒走到，不再猜）
  void _slog(String msg) {
    try {
      File('/tmp/galaxy_saver.log').writeAsStringSync(
          '${DateTime.now().toIso8601String()} $msg\n', mode: FileMode.append);
    } catch (_) {}
  }

  void _onSaverStateChanged() {
    _slog('saver state changed, active=${widget.controller.isActive}');
    if (widget.controller.isActive) {
      try {
        _openSaverChromeWindow();
      } catch (e) {
        _slog('openSaver EXCEPTION: $e');
      }
      if (mounted) setState(() {}); // 刷新 fallback 顯示
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.controller.reportActivity(),
      onPointerMove: (e) {
        // 活動偵測：任何移動都算活動；保護中要超過閾值才退出（防手抖）
        if (widget.controller.isActive) {
          if (_lastPointerPos != null) {
            final d = (e.position - _lastPointerPos!).distance;
            if (d > 12) {
              widget.controller.dismiss();
            }
          }
          _lastPointerPos = e.position;
        } else {
          widget.controller.reportActivity();
        }
      },
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (ctx, child) {
          return Stack(
            children: [
              child!,
              if (widget.controller.isActive)
                _buildSaver(ctx),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }

  Widget _buildSaver(BuildContext ctx) {
    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 800),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          cursor: SystemMouseCursors.none, // 隱藏游標
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              // [v263] 退出時順手關 Chrome 保護視窗（若還開著）
              _closeSaverChromeWindow();
              widget.controller.dismiss();
            },
            // [v263 Blue 令] 保護畫面改 Chrome 全螢幕（絲滑）；
            // 嵌入式 GalaxyWebView 降為 Chrome 不存在時的 fallback
            child: _chromeSaverAvailable
                ? const ColoredBox(color: Colors.black)
                : const GalaxyWebView(),
          ),
        ),
      ),
    );
  }
}
