// Slot Runner Screen — C3 Tier 1 執行引擎的「運行」段
//
// WebView sandbox：載入插槽資料夾的 HTML 入口。
// 沙箱鐵則：
// - 只載本插槽資料夾（file:// 插槽目錄），不給其他檔案系統
// - JS 開（純網頁工具要跑），但外部資源載入由紅隊報告預先揭露
// - 導航限制：插槽內連結可走，跳出插槽資料夾的導航擋下
// - 崩潰隔離：webview 掛了只掛這個畫面，主程式活著（C4 看門狗補資源段）
//
// 誠實鐵則：入口檔案不存在 → 紅字，不白屏不假成功。

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/slots/slot_registry.dart';
import '../services/slots/slot_resource_watchdog.dart';
import '../services/slots/slot_permission_gate.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

class SlotRunnerScreen extends StatefulWidget {
  final String slotId;
  const SlotRunnerScreen({super.key, required this.slotId});
  @override
  State<SlotRunnerScreen> createState() => _SlotRunnerScreenState();
}

class _SlotRunnerScreenState extends State<SlotRunnerScreen> {
  InAppWebViewController? _controller;
  bool _loaded = false;
  String? _error;
  String _url = '';

  // [C4] 看門狗接線
  int _jsErrorsThisTick = 0;
  Timer? _watchdogTimer;

  @override
  void initState() {
    super.initState();
    // 每 10 秒取樣一次行為（JS 錯誤風暴）
    _watchdogTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final tripped = SlotResourceWatchdog.instance
          .sampleBehavior(widget.slotId, jsErrorsSinceLast: _jsErrorsThisTick);
      _jsErrorsThisTick = 0;
      if (tripped && mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final record = SlotRegistry.instance.getById(widget.slotId);
    if (record == null) {
      return _scaffold(ds, const Text('找不到這個插槽'));
    }

    final slotDir = Directory(
        '${SlotRegistry.instance.slotsDir.path}/${widget.slotId}');
    final entry = record.entryHtmlPath;
    if (entry == null || entry.isEmpty) {
      return _scaffold(
          ds,
          _honestError(ds,
              '這個插槽還沒安裝內容（無 HTML 入口記錄）。請先在插槽管理頁完成安裝。'));
    }
    final entryFile = File('${slotDir.path}/$entry');
    if (!entryFile.existsSync()) {
      return _scaffold(ds,
          _honestError(ds, '入口檔案不存在：slots/${widget.slotId}/$entry\n'
              '可能被手動刪除或安裝中斷。解除安裝後重裝可修。'));
    }

    // [Blue 抓包 2026-10-07] macOS 套件原始碼鐵證：initialFile/loadFile 永遠
    // 前綴 ../Frameworks/App.framework/Resources/flutter_assets/——本機檔案
    // 一律找不到（相對、絕對路徑都炸）。正解：initialUrlRequest + file:// URL。
    final absEntry = entryFile.absolute.path;
    _url = 'file://$absEntry';

    return _scaffold(
      ds,
      Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: false,
              // 沙箱：不讓 webview 開新視窗/跳外部 app
              supportZoom: true,
              allowsInlineMediaPlayback: true,
            ),
            gestureRecognizers: {
              Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
            },
            onWebViewCreated: (c) {
              _controller = c;
            },
            // 沙箱導航閘：只准插槽資料夾內導航（跳出插槽＝CANCEL）
            shouldOverrideUrlLoading: (c, req) async {
              final url = req.request.url;
              final u = url?.path ?? '';
              final inSlot = (url?.isScheme('file') ?? false) &&
                  u.startsWith(slotDir.path);
              if (!inSlot) {
                debugPrint('[SlotRunner] 跳出插槽的導航：$url');
                // [C4] 權限執行閘：對外導航看 network 權限（記主權帳）
                final allowed = await SlotPermissionGate.instance
                    .checkNavigation(
                        slotId: widget.slotId, url: url.toString());
                if (!allowed) {
                  // 餵看門狗：被權限擋下的也算異常行為（風暴計數）
                  SlotResourceWatchdog.instance
                      .reportBlockedNavigation(widget.slotId);
                  if (SlotResourceWatchdog.instance.tripped
                      .containsKey(widget.slotId)) {
                    if (mounted) Navigator.of(context).maybePop();
                  }
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              }
              return NavigationActionPolicy.ALLOW;
            },
            // [C4] JS 錯誤風暴取樣（每 tick 餵看門狗）
            onConsoleMessage: (c, msg) {
              if (msg.messageLevel == ConsoleMessageLevel.ERROR) {
                _jsErrorsThisTick++;
              }
            },
            onLoadStop: (c, url) {
              if (mounted) setState(() => _loaded = true);
              // [Blue 提議 2026-10-06] 插槽深淺色與 App 同步：
              // 業界慣例 data-theme="dark|light"（mermview 等工具遵循），
              // 沒遵循的工具不受影響（多設一個 dataset 無副作用）。
              final themeName =
                  Theme.of(context).brightness == Brightness.dark
                      ? 'dark'
                      : 'light';
              c.evaluateJavascript(source:
                  'document.documentElement.dataset.theme = "'
                  '\$themeName";');
            },
            onReceivedError: (c, req, e) {
              if (mounted && !_loaded) {
                setState(() => _error = '載入失敗：${e.description}');
              }
            },
          ),
          if (!_loaded && _error == null)
            Positioned.fill(
              child: ColoredBox(
                color: ds.surfaceElevated,
                child: Center(
                  child: CircularProgressIndicator(color: ds.accentMiro),
                ),
              ),
            ),
          if (_error != null)
            Positioned.fill(child: ColoredBox(color: ds.surfaceElevated, child: Center(child: _honestError(ds, _error!)))),
        ],
      ),
    );
  }

  Widget _scaffold(BridgeDSColors ds, Widget body) {
    final record = SlotRegistry.instance.getById(widget.slotId);
    return Scaffold(
      backgroundColor: ds.canvas,
      appBar: AppBar(
        backgroundColor: ds.surfaceElevated,
        title: Text(
          record?.userLabel ?? '插槽',
          style: TierStyle.of(context, Tier.appHeadline)
              .toTextStyle()
              .copyWith(color: ds.textPrimary, fontSize: 16),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: ds.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: body,
    );
  }

  Widget _honestError(BridgeDSColors ds, String msg) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: ds.accentRed),
          const SizedBox(height: 16),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: TierStyle.of(context, Tier.bodyPrimary)
                .toTextStyle()
                .copyWith(color: ds.accentRed, height: 1.6),
          ),
        ],
      ),
    );
  }
}
