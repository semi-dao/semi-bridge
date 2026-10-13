// galaxy_webview.dart
// 大腦圖譜 3D 星系模式 — three.js 星系的 App 內載體
// [小葵 2026-08-27] 路線 A：WebView 包已驗證的 three.js 星系頁。
// 資料從 App 內 MCP server（localhost:8420）同源供應——
// /galaxy 出頁面、/galaxy_data 出資料，避開 file:// 協定限制。
//
// ⚠️ 共視斷層聲明（對齊 canvas-covision skill）：webview 是 PlatformView，
// /app_view 拍此頁可能黑塊。星系頁自帶 screenshot 能力（toDataURL）
// 是下一步；先以「3D 模式下 /app_view 不可用」為已知限制交付。

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/dev_paths.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'galaxy_settings_panel.dart'; // [v232]
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

class GalaxyWebView extends StatefulWidget {
  const GalaxyWebView({super.key});

  @override
  State<GalaxyWebView> createState() => _GalaxyWebViewState();
}

class _GalaxyWebViewState extends State<GalaxyWebView> {
  InAppWebViewController? _controller;
  int? _lastHoverPush; // [v242] hover 注入節流
  // [小葵 2026-09-25 Blue 靜止撥弦令] App 心跳——滑鼠在 webview 內時
  // 每 500ms 戳一次頁面 __appHoverAlive（即使完全不動）。頁面端拿它
  // 判定「使用者在場」：macOS 在滑鼠靜止後把 key focus 收回 Flutter
  // 層，WKWebView hasFocus() 變 false → 撥弦全啞（Blue 實測「焦點被
  // 奪走」）。心跳新鮮＝視為活躍，靜止也能持續撥弦。
  bool _mouseInside = false;
  Offset? _lastMousePos;
  Timer? _hoverHeartbeat;
  int _lowFpsStreak = 0; // [v252] 卡頓連續計數（自動重載觸發器）
  Key _webviewKey = UniqueKey(); // [v252b] 重建 webview 用（reload 不重置系統節流）
  Timer? _fpsWatchTimer;
  bool _loaded = false;
  bool _failed = false;
  String _failMsg = '';
  String? _url; // token 備齊後才建 webview

  @override
  void initState() {
    super.initState();
    _init();
    // [v252] 卡頓自動重載——WebKit 嵌入式節流（約 2 分鐘後 100ms 抽幀）
    // 今日已排除 10+ 理論（JS/快取/輪詢/音訊/alpha/AppNap/前後台/獨立視窗）
    // 皆無效——屬系統級政策。止血：每 30 秒問頁面 fps，連續 6 次（3 分鐘）
    // <85 → 靜默 reload（重載=重置節流計時器，再賺 ~2 分 10 秒絲滑期；
    // 音訊/參數自動恢復，畫面閃一下即回）
    _fpsWatchTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final c = _controller;
      if (c == null || !_loaded) return;
      try {
        final r = await c.evaluateJavascript(source:
          '(window.__fpsHist&&window.__fpsHist.length?window.__fpsHist[window.__fpsHist.length-1]:100)');
        final fps = (r is num) ? r.toInt() : 100;
        if (fps < 85) {
          _lowFpsStreak++;
          if (_lowFpsStreak >= 6) {
            _lowFpsStreak = 0;
            // [v252c] 實測：reload/重建 webview 都不重置節流（綁在 App 行程
            // 的 WebKit assertion）——唯一解=App 重啟。這裡只記錄不動作。
            debugPrint('[v252] WebKit 節流確認（6×30s<85fps）——App 重啟可重置');
          }
        } else {
          _lowFpsStreak = 0;
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _fpsWatchTimer?.cancel();
    _hoverHeartbeat?.cancel();
    super.dispose();
  }

  // [小葵 2026-09-25 Blue 靜止撥弦令] 滑鼠進入 webview → 啟動 500ms
  // 心跳（用最後已知座標持續戳頁面，滑鼠不動也照戳）；離開 → 停止。
  // 頁面端 __appHoverAlive 新鮮（<2s）＝使用者還在，拾取不休眠、
  // 撥弦不被 hasFocus 一票否決。離開 2 秒後心跳過期自然恢復舊行為
  // （真的離開＝靜音，正確）。
  void _startHeartbeat() {
    _mouseInside = true;
    _hoverHeartbeat?.cancel();
    _hoverHeartbeat = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final c = _controller;
      if (c == null || !_mouseInside) return;
      final pos = _lastMousePos;
      if (pos == null) return;
      c.evaluateJavascript(source:
          'window.__appHoverAlive = performance.now();'
          '${pos.dx.toInt() >= 0 ? "if(window.__mouseLastMove===undefined || performance.now()-window.__mouseLastMove>600){ window.__mouseLastMove=performance.now(); }" : ""}');
    });
  }

  void _stopHeartbeat() {
    _mouseInside = false;
    _hoverHeartbeat?.cancel();
    _hoverHeartbeat = null;
  }

  Future<void> _init() async {
    final token = await _mcpToken();
    if (!mounted) return;
    setState(() {
      // token 走 query → 頁內 fetch 帶 x-bridge-token header 過 MCP 閘門
      // [v85b] probe 模式開關：~/galaxy_probe 檔存在時帶 ?probe=1（零場景 rAF 測試）
      var probe = '';
      try { final pf = File(resolveDevPath('~/galaxy_probe')); if (pf.existsSync()) probe = '&probe=' + pf.readAsStringSync().trim(); } catch (_) {}
      _url = 'http://localhost:8420/galaxy?token=$token$probe&app=1&cb=${DateTime.now().millisecondsSinceEpoch}'; // [v53] 時間戳破快取——WKWebView 舊頁=律動/FPS 修復沒生效的根因
    });
  }

  /// MCP token（與 server 同一份檔案）
  static Future<String> _mcpToken() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/mcp_token');
      return (await f.readAsString()).trim();
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌌 星系載入失敗', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(_failMsg,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => setState(() {
                _failed = false;
                _loaded = false;
              }),
              child: const Text('重試'),
            ),
          ],
        ),
      );
    }
    if (_url == null) {
      return const Center(child: Text('🌌 連線中…'));
    }
    // [v242 Blue hover 令] WKWebView 不轉發「純移動」滑鼠事件給網頁——
// CSS :hover / JS mousemove 在 App 內都收不到。外層 MouseRegion（Flutter 原生）
// 收到後把座標注入頁面，頁面 __flutterHover() 手動開關 tooltip。
return MouseRegion(
      opaque: false,
      onEnter: (_) => _startHeartbeat(),
      onExit: (_) => _stopHeartbeat(),
      onHover: (e) {
        final c = _controller;
        if (c == null) return;
        final pos = e.localPosition;
        _lastMousePos = pos;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (_lastHoverPush != null && now - _lastHoverPush! < 40) return;
        _lastHoverPush = now;
        c.evaluateJavascript(source:
            'window.__flutterHover && window.__flutterHover(${pos.dx.toInt()}, ${pos.dy.toInt()});');
      },
      child: Stack(
      children: [
        // [v243 Blue 圖例令] Flutter 原生記憶性質圖例——hover 由 Flutter 處理，
        // 完全繞過 webview 事件層（App 內 :hover 收不到滑鼠移動的斷根法）
        Positioned(
          top: 8, left: 0, right: 0,
          child: Align(alignment: Alignment.topCenter, child: const _SubLegendBar()),
        ),
        InAppWebView(
          key: _webviewKey,
          initialSettings: InAppWebViewSettings(
            // macOS WKWebView：允許本地 server fetch、允許 WebGL
            javaScriptEnabled: true,
            // [v248 卡頓令] transparentBackground=false——alpha 合成是每幀貼圖
            // 拷貝的額外負擔；頁面底色本來就是黑（不透明）。A/B：拔掉看 100ms 卡頓是否消失
            transparentBackground: false,
            // [v225 Blue 無聲令 2026-09-02] 音訊打通——
            // 1) mediaPlaybackRequiresUserAction=false：
            //    WebAudio/媒體不需手勢即可出聲（程式觸發的撥弦音直出）
            // 2) allowsInlineMediaPlayback=true：媒體行內播放
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
          ),
          initialUrlRequest: URLRequest(url: WebUri(_url!)),
          // [小葵 2026-08-28 v13] webview 全權接管手勢——修「左鍵無法旋轉/選取」：
          // 沒設 gestureRecognizers 時拖曳手勢會被 Flutter 爭走（macOS WKWebView 尤甚）
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(
              () => EagerGestureRecognizer(),
            ),
          },
          onWebViewCreated: (c) {
            _controller = c;
            // [v253 Blue 令] 互動續命——拖曳放開時頁面通知：重置低 fps 計數
            c.addJavaScriptHandler(handlerName: 'galaxyInteract', callback: (_) {
              _lowFpsStreak = 0;
            });
          },
          onLoadStop: (c, url) async {
            setState(() => _loaded = true);
            // [v55 監視器令] 載入完成即從 Dart 端問頁面指紋——完全繞過頁面 JS 自主性
            try {
              final fp = await c.evaluateJavascript(source:
                  "(function(){try{return document.querySelector('script[type=module]')?'HAS_MODULE':'NO_MODULE'}catch(e){return 'ERR:'+e.message}})()");
              final pig = await c.evaluateJavascript(source:
                  "fetch('/galaxy_ping?fp=onload&rAF=0&cb='+Date.now(),{cache:'no-store'}).then(()=>'pinged').catch(e=>'ERR')");
              File('/tmp/galaxy_webview_diag.log').writeAsStringSync(
                '[onLoadStop] t=${DateTime.now().toIso8601String()} url=$url module=$fp ping=$pig\n',
                mode: FileMode.append);
              // ignore: avoid_print
              print('[galaxy_webview] onLoadStop url=$url module=$fp ping=$pig');
              // [v223c 音訊診斷] 3 秒後查音訊環境+撥弦資料（頁面穩定後）
              Future.delayed(const Duration(seconds: 3), () async {
                try {
                  final audioState = await c.evaluateJavascript(source:
                    "(function(){var r={};try{r.hasAC=!!(window.AudioContext||window.webkitAudioContext);}catch(e){r.hasAC='ERR';}"
                    "try{r.lensLen=(window.__threadLens||[]).length;}catch(e){r.lensLen='ERR';}"
                    "try{r.plucks=(window.__plucks||[]).length;}catch(e){r.plucks='ERR';}"
                    "try{r.vizMode=(typeof VIZ!=='undefined')?VIZ.mode:'NO_VIZ';}catch(e){r.vizMode='ERR';}try{r.colThread=window.GPARAMS?String(window.GPARAMS.colThread):'NO_GP';}catch(e){r.colThread='ERR';}try{r.hasRebuild=window.__rebuildColors?1:0;}catch(e){r.hasRebuild=-1;}"
                    // [v223e] 直接播音（同步觸發，播完不管）——聽得到=WebAudio 通，問題在撥弦邏輯；聽不到=系統層擋音
                    "try{"
                    " var ac=new (window.AudioContext||window.webkitAudioContext)();"
                    " if(ac.state==='suspended')ac.resume();"
                    " var o=ac.createOscillator(),g=ac.createGain();"
                    " o.frequency.value=660; g.gain.value=0.1;"
                    " o.connect(g); g.connect(ac.destination);"
                    " o.start(); o.stop(ac.currentTime+0.5); r.toneSent=true;"
                    "}catch(e){r.toneErr=e.message;}"
                    "return JSON.stringify(r)})()");
                  File('/tmp/galaxy_webview_diag.log').writeAsStringSync(
                    '[audio-diag] t=${DateTime.now().toIso8601String()} $audioState\n',
                    mode: FileMode.append);
                  // ignore: avoid_print
                  print('[galaxy_webview audio-diag] $audioState');
                } catch (e) {
                  File('/tmp/galaxy_webview_diag.log').writeAsStringSync(
                    '[audio-diag ERR] $e\n', mode: FileMode.append);
                }
              });
              // [v223d] 12 秒後二段診斷：VIZ 狀態+直接播音測試（WebAudio 全路徑）
              Future.delayed(const Duration(seconds: 12), () async {
                try {
                  final r = await c.evaluateJavascript(source:
                    "(async function(){var r={};"
                    "try{r.vizMode=(typeof VIZ!=='undefined')?VIZ.mode:'NO_VIZ';}catch(e){r.vizMode='ERR';}"
                    "try{r.lensLen=(window.__threadLens||[]).length;}catch(e){}"
                    "try{r.suspended=null;"
                    " const ac=new (window.AudioContext||window.webkitAudioContext)();"
                    " r.suspended=ac.state;"
                    " const o=ac.createOscillator(),g=ac.createGain();"
                    " o.frequency.value=440; g.gain.value=0.08;"
                    " o.connect(g); g.connect(ac.destination);"
                    " o.start(); o.stop(ac.currentTime+0.3);"
                    " await new Promise(res=>setTimeout(res,400));"
                    " r.afterPlay=ac.state; r.heard='tone-sent';"
                    "}catch(e){r.acErr=e.message;}"
                    "return JSON.stringify(r)})()");
                  File('/tmp/galaxy_webview_diag.log').writeAsStringSync(
                    '[audio-diag2] t=${DateTime.now().toIso8601String()} $r\n',
                    mode: FileMode.append);
                  // ignore: avoid_print
                  print('[galaxy_webview audio-diag2] $r');
                } catch (e) {
                  File('/tmp/galaxy_webview_diag.log').writeAsStringSync(
                    '[audio-diag2 ERR] $e\n', mode: FileMode.append);
                }
              });
            } catch (e) {
              File('/tmp/galaxy_webview_diag.log').writeAsStringSync(
                '[onLoadStop ERR] t=${DateTime.now().toIso8601String()} e=$e\n',
                mode: FileMode.append);
            }
            // [v68 律動診斷] 5s 後讀 uTime 兩次（間隔 2s）——App webview 內律動時鐘死活
            Future.delayed(const Duration(seconds: 5), () async {
              try {
                final t1 = await c.evaluateJavascript(source:
                    'window.__causalMat?.uniforms?.uTime?.value ?? "no-mat"');
                await Future.delayed(const Duration(seconds: 2));
                final t2 = await c.evaluateJavascript(source:
                    'window.__causalMat?.uniforms?.uTime?.value ?? "no-mat"');
                File('/tmp/galaxy_webview_diag.log').writeAsStringSync(
                  '[uTime] t1=$t1 t2=$t2\n',
                  mode: FileMode.append);
              } catch (e) {
                File('/tmp/galaxy_webview_diag.log').writeAsStringSync(
                  '[uTime ERR] $e\n',
                  mode: FileMode.append);
              }
            });
          },
          onReceivedError: (c, req, err) {
            if (req.url.toString().contains('galaxy')) {
              setState(() {
                _failed = true;
                _failMsg = err.description;
              });
            }
          },
        ),
        if (!_loaded)
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('🌌', style: TextStyle(fontSize: 42)),
                SizedBox(height: 10),
                Text('星系生成中…',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
          ),
        // [v232 Blue 設定窗令 2026-09-03] 星系視覺/聽覺參數設定窗
        // （左側可收折、36 參數、全彩 RGB、可隱藏列、持久化）
        const GalaxySettingsPanel(),
        // [小葵 2026-08-31 v180 星系獨立視窗鈕] WebKit 對嵌入 webview 深度節流
        // （鐵證：同頁面獨立視窗 3.5 分鐘 0 凍結 vs App 內 7/11）。
        // 開獨立 NSWindow=頁面成視窗主人=絲滑保證。
        // [v187 Blue 移位令] 右上→最左下角（Blue 定案位置）
        Positioned(
          left: 16, bottom: 16,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _openStandaloneWindow,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xCC0E1626),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x66F0CE5E)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.open_in_new, size: 14, color: Color(0xFFF0CE5E)),
                  SizedBox(width: 6),
                  Text('獨立視窗',
                      style: TextStyle(fontSize: 12, color: Color(0xFFE8F0E8))),
                ]),
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }

  /// [v180→v255] 開星系獨立視窗。
  /// v180 Swift NSWindow+WKWebView：實測（2026-09-04）與 App 同行程→同步節流。
  /// v255 改開 Chrome App 模式視窗（--app=URL）：真瀏覽器引擎，Chrome 的
  /// 渲染不受 WebKit 嵌入節流——Blue 記憶中「不會卡的網頁視窗」=這個。
  /// 無 Chrome 時 fallback 回 Swift 視窗。
  Future<void> _openStandaloneWindow() async {
    if (_url == null) return;
    // [v258] 拔 cb 時間戳——Chrome 視窗永遠吃最新版頁面（no-cache）
    final url = _url!.replaceAll('&app=1', '').replaceAll(RegExp(r'&cb=\d+'), '');
    try {
      final r = Process.runSync('open', ['-na', 'Google Chrome', '--args', '--app=$url']);
      if (r.exitCode == 0) return;
    } catch (_) {}
    const channel = MethodChannel('bridge.desktop_shell.macos.v1');
    try {
      await channel.invokeMethod('openGalaxyWindow', {'url': url});
    } catch (e) {
      debugPrint('[v255] 開獨立視窗失敗: $e');
    }
  }
}


// ═══ [v243] Flutter 原生記憶性質圖例（15 項）═══
class _SubLegendBar extends StatelessWidget {
  const _SubLegendBar();

  static const List<(int, String, String)> _items = [
    (0xFFFFF3C4, '讓我發光', '接觸到讓自己發光的事物——創作、熱情、屬於我的風格。出現時你會感到興奮、眼睛發亮。'),
    (0xFF4ECDC4, '共鳴', '與內心深深共振的相遇——「對，就是這個」。不是分析出來的，是認出來的。'),
    (0xFFFF6B9D, '心動', '心裡真實的聲音：想要、喜歡、直覺上的「有感覺」。心先動，理由後補。'),
    (0xFFB98AFF, '心語', '理性的聲音：分析、判斷、「覺得應該」。權衡利弊後得出的結論。'),
    (0xFF7FD894, '順流', '一切自然流動、不費力的時刻。沒有卡住、沒有勉強，事情自己長出來。'),
    (0xFFFFD166, '必須時刻', '「必須、不得不」驅動的行動。義務感大於意願——做完往往鬆一口氣而非滿足。'),
    (0xFF5FD8E8, '同步性', '巧合與同步：剛好、同時、意外地對上。世界好像在跟你對頻的瞬間。'),
    (0xFFFF9E6B, '焦慮源', '擔心與害怕的來源：「怕」「完了」「怎麼辦」。焦慮被記下來，是為了被照顧。'),
    (0xFFC3F584, '主動橋接', '主動把兩件不相干的事連起來：「這好像跟那個有關」。聯想與橋接的瞬間。'),
    (0xFFFF8FAB, '邀請現身', '機會與邀約出現的時刻：收到、被問、看到可能性。門還沒開，但門出現了。'),
    (0xFF9D8BFF, '入門', '真正跨進門檻：開始做、下一步、執行。從想變成做的轉換點。'),
    (0xFFFFC09F, '分裂時刻', '心與理的拉扯：「可是」「但是」、矛盾與掙扎。兩個聲音同時在場。'),
    (0xFF84DCFF, '工作流', '工作流程的節點——任務與步驟的骨架記憶。'),
    (0xFFD8B6FF, '整合結果', '整合完成：想通了、確定了、決定了。拉扯過後長出來的答案。'),
    (0xFFD8B6FF, '其他', '尚未歸類的記憶——等待被理解的那一顆。'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 880),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xE6080C10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x38F0CE5E)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 9, runSpacing: 2,
        children: [for (final it in _items) _LegendItem(label: it.$2, color: Color(it.$1), desc: it.$3)],
      ),
    );
  }
}

class _LegendItem extends StatefulWidget {
  final String label; final Color color; final String desc;
  const _LegendItem({required this.label, required this.color, required this.desc});
  @override
  State<_LegendItem> createState() => _LegendItemState();
}

class _LegendItemState extends State<_LegendItem> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      opaque: false,
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: _hov ? const Color(0x1AF0CE5E) : null,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 9, height: 9,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.7), blurRadius: 5)])),
              const SizedBox(width: 3),
              Text(widget.label, style: const TextStyle(fontSize: 11, color: Color(0x9EFFFFFF))),
            ]),
          ),
          if (_hov)
            Positioned(
              top: 26, left: 0,
              child: Container(
                width: 290,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xF20A0E14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x61F0CE5E)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(widget.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: widget.color)),
                  ]),
                  const SizedBox(height: 4),
                  Text(widget.desc, style: const TextStyle(fontSize: 12, height: 1.6, color: Color(0xBDFFFFFF))),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
