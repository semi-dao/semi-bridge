// 手機主畫面（Mobile Shell）——Tab 3+1 骨架
// [S4 2026-11-10 Blue 令] 「此刻」滿版＋Tab 骨架：
//   🏠 此刻（滿版骨牌）｜💬 對話｜🗂 任務面板｜🔗 配對
//   - 快照呈現於「配對」；對話呈現於「對話」（Blue 令 2026-11-10）
//   - 符號單色極簡（Blue 令）
//   - 對話↔任務綁定雙向連動（SPEC §8，2026-11-10 Blue 拍板）
//
// 設計鐵則：Tier 系統、離線不空白不轉圈、寧紅字不假成功。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';

import '../widgets/mobile/mobile_chat_three_tier.dart';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';

import '../services/mobile/carousel/domino_engine.dart';
// [2026-11-20 此刻頁三刀·刀②進階] 手機端里程碑純函數（複製自桌面 time_sense_service）
import '../services/mobile/carousel/moment_milestone.dart';
import '../services/mobile/offline/home_offline_coordinator.dart';
import '../services/mobile/offline/home_snapshot.dart';
import '../services/mobile/offline/home_state_machine.dart';
import '../services/mobile/offline/home_view_state.dart';
import '../services/mobile/offline/offline_home_view.dart';
import '../services/mobile/offline/offline_message_queue.dart'
    show QueuedMessage;
import '../services/mobile/auto_reconnect_bootstrap.dart';
import '../main.dart' show kMobileBuildStamp;
import '../services/mobile_bridge_client.dart';
import '../widgets/mobile/domino_wall.dart';
import '../services/paired_desktop_store.dart';
import '../services/mobile/mobile_token_access.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

/// 手機版主畫面——Tab 骨架＋各頁容器。
class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  int _tabIndex = 0;

  /// 骨牌輪播引擎的當下格。
  DominoSlot? _currentSlot;

  /// 跨格切換計時器（每 30 秒對時）。
  Timer? _slotTimer;

  /// 離線協調器（狀態機＋佇列＋快照）——快照資料源（配對 tab 消費）。
  late final HomeOfflineCoordinator _coordinator;

  final TextEditingController _chatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // [SPEC §7 誠實鐵則] 狀態機初始值必須反映 client 真實狀態
    final client = MobileBridgeClient.instance;
    _coordinator = HomeOfflineCoordinator(
      machine: HomeStateMachine(
        initial: client.isConnected
            ? HomeConnectionState.online
            : HomeConnectionState.offline,
      ),
      sender: _sendQueuedMessage,
    );
    client.addListener(_onClientChanged);
    _currentSlot = DominoEngine.currentSlot();
    _slotTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _currentSlot = DominoEngine.currentSlot());
    });
    // [S4 2026-11-11 Blue 抓包] 配對過一次＝永久綁定——App 啟動即憑
    // token 自動回家（reconnectWithToken），不要求重掃 QR。
    // client 已連線（前景恢復）才跳過；token 失效則誠實留離線。
    if (!client.isConnected) {
      bootstrapAutoReconnect().then((started) {
        if (started && mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _slotTimer?.cancel();
    MobileBridgeClient.instance.removeListener(_onClientChanged);
    _chatController.dispose();
    super.dispose();
  }

  void _onClientChanged() {
    if (!mounted) return;
    final client = MobileBridgeClient.instance;
    if (client.isConnected) {
      _coordinator.handleEvent(HomeConnectionEvent.reconnect);
    } else if (client.state == BridgeConnectionState.disconnected) {
      _coordinator.handleEvent(HomeConnectionEvent.disconnect);
    }
    // [S4 2026-11-10] 桌面 runtime snapshot → 協調器（配對 tab 快照區真相源）
    // 協議層 payload 是巢狀 {schema, runtimePayload:{...}}——拆封取內層
    var snap = client.lastSnapshot;
    if (snap != null && snap.isNotEmpty) {
      final inner = snap['runtimePayload'];
      if (inner is Map<String, dynamic>) snap = inner;
    }
    if (snap != null && snap.isNotEmpty) {
      _coordinator.snapshot = HomeSnapshot(
        content: snap,
        capturedAt: DateTime.now(),
      );
    }
    setState(() {});
  }

  /// 重連 flush 的送出回呼（佇列依序呼叫；回 true=送達移除、false=保留）。
  Future<bool> _sendQueuedMessage(QueuedMessage message) async {
    final client = MobileBridgeClient.instance;
    if (!client.isConnected) return false;
    final taskId = await client.sendTaskRun(
      taskType: 'chat.send',
      payload: {'text': message.text},
    );
    return taskId != null;
  }

  // ignore: unused_element
  void _onChatSubmit(String text) {
    if (text.trim().isEmpty) return;
    if (!_coordinator.enqueue(text.trim())) {
      _sendQueuedMessage(
        QueuedMessage(
          text: text.trim(),
          queuedAt: DateTime.now(),
          sequence: -1,
        ),
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final viewState = _coordinator.viewState;

    return Scaffold(
      backgroundColor: BridgeDSColors.of(context).canvas,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tabIndex,
          children: [
            _NowPage(slot: _currentSlot, greyedOut: viewState.isGreyedOut),
            // [SPEC §8.2 2026-11-13] 對話 tab＝三層結構（mockup 圖B）
            const MobileChatThreeTierPage(),
            const _RemotePage(),
            const _VaultPage(),
            _PairingPage(state: viewState),
          ],
        ),
      ),
      // [S4 2026-11-10 Blue 令] 單色極簡 Tab——線性 icon、無底色塊
      bottomNavigationBar: _MonoTabBar(
        index: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 🏠 此刻——滿版骨牌（Blue 令：快照/對話移出、滿版呼吸感）
// ═══════════════════════════════════════════════════
class _NowPage extends StatefulWidget {
  final DominoSlot? slot;
  final bool greyedOut;

  const _NowPage({required this.slot, required this.greyedOut});

  @override
  State<_NowPage> createState() => _NowPageState();
}

class _NowPageState extends State<_NowPage> {
  /// [SPEC §8.8b] 輪播池：圖文混排清單（最新在前）——每頁吃 5 個素材
  List<Map<String, dynamic>> _pool = [];
  /// [此刻頁 v2] 縮圖快取（path → bytes）——LRU，上限 60 筆清最舊
  final _imageCache = <String, Uint8List>{};
  /// [此刻頁 v2] 文字全文快取（path → text）＋ truncated 標記
  final _textCache = <String, String>{};
  final _textTruncated = <String, bool>{};
  /// 抓取中除重（path）
  final _inflight = <String>{};
  // [2026-11-21 斷線風暴根治·刀B] 縮圖串行佇列：fire-and-forget 全併發改為
  // 併發上限排隊——一次最多 2 張在途，其餘依序候位，防重連後縮圖風暴打爆
  // gateway event loop。
  final _thumbQueue = <String>[];
  int _thumbActive = 0;
  /// 失敗冷卻表（path → 失敗時刻）：30s 內不重發同一失敗檔
  final _thumbFailedAt = <String, DateTime>{};
  static const _thumbMaxConcurrent = 2;
  static const _thumbBackfillWindow = 8;
  bool _loadingPool = true;

  int _poolAttempts = 0;
  int _page = 0;
  final PageController _pageController = PageController();

  /// [2026-11-20 此刻頁三刀·刀②] 最新配對時刻（PairedDesktopStore.pairedAt）——
  /// 「相伴第 N 天」與里程碑判斷的起算原點。null＝無配對記錄（不顯示天數，誠實）。
  DateTime? _pairedAt;

  /// [此刻頁 v2] 每頁素材數：hero 圖 1＋文字磚 1＋strip 圖 1＋minis 圖 2
  static const _itemsPerPage = 5;
  static const _imageCacheCap = 60;
  static const _textExts = {
    'md', 'txt', 'json', 'jsonl', 'log', 'csv', 'yaml', 'yml', 'html', 'rtf'
  };

  @override
  void initState() {
    super.initState();
    _loadPool();
    // [2026-11-20 此刻頁三刀·刀②] 讀最新配對時刻（相伴第 N 天起算原點）。
    // reduce 取 pairedAt 最新者（同 mobile_bridge_client.dart L844 慣例）。
    PairedDesktopStore.getAll().then((d) {
      if (!mounted || d.isEmpty) return;
      final latest =
          d.reduce((a, b) => a.pairedAt.isAfter(b.pairedAt) ? a : b);
      setState(() => _pairedAt = latest.pairedAt);
    });
    // [2026-11-12 Blue 報案「資產零」] 連線變 ready → 補抓（initState 時可能還沒連上）
    MobileBridgeClient.instance.addListener(_onConnForPool);
  }

  @override
  void dispose() {
    _pageController.dispose();
    MobileBridgeClient.instance.removeListener(_onConnForPool);
    super.dispose();
  }

  void _onConnForPool() {
    final client = MobileBridgeClient.instance;
    // [2026-11-13 Blue 報案「配對後黑屏」] 離線期退避重試耗光 attempt 上限 →
    // 連上後永遠不重抓。修：連線事件重置計數（防風暴由 pool 空條件守）
    if (client.isConnected && _pool.isEmpty) {
      _poolAttempts = 0;
      _loadPool();
      _lastPoolVaultVersion = client.vaultVersion;
      return;
    }
    // [SPEC §8.5c] 桌面 vault 變動（新素材進來）→ 牆自動換新內容
    if (client.isConnected && client.vaultVersion != _lastPoolVaultVersion) {
      _lastPoolVaultVersion = client.vaultVersion;
      _loadPool();
    }
  }

  int _lastPoolVaultVersion = 0; // [§8.5c]

  Future<void> _loadPool() async {
    _poolAttempts++;
    final res = await MobileBridgeClient.instance
        .sendVaultList(limit: 60, forWall: true);
    if (!mounted) return;
    if (res != null && res['ok'] == true) {
      final payload = res['payload'] as Map<String, dynamic>;
      final files = (payload['files'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _pool = files;
        _loadingPool = false;
      });
      // [此刻頁 v2] 池到位 → 預載前 3 頁（起點由當前頁算）
      if (files.isNotEmpty) _prefetchFrom(_page);
      // [2026-11-21 此刻頁收尾·修1加強] hero 保底：池已按 modified 新→舊排序，
      // 全池前 8 筆圖一律列入縮圖請求（不受「向後 30 筆」窗口限制）——第一頁
      // 切片若全無圖，hero 仍有全池最新的已快取圖可補（同步掃描＋此預抓雙保險）。
      if (files.isNotEmpty) {
        var imgBudget = 8;
        for (final f in files) {
          if (imgBudget <= 0) break;
          if (_isTextFile(f)) continue;
          final path = f['path'] as String? ?? '';
          if (path.isEmpty) continue;
          imgBudget--;
          _ensureThumb(path);
        }
      }
    } else {
      setState(() => _loadingPool = false);
      // 離線/逾時——退避重試（4s → 10s）
      if (_poolAttempts < 5) {
        Future.delayed(
            Duration(seconds: _poolAttempts < 2 ? 4 : 10), _loadPool);
      }
    }
  }

  // ── [此刻頁 v2] 分頁＋預載 ──────────────────────

  /// 頁數＝池有幾頁給幾頁（向上去整；空池留 1 頁誠實空牆）。
  int get _pageCount =>
      _pool.isEmpty ? 1 : (_pool.length / _itemsPerPage).ceil();

  List<Map<String, dynamic>> _slice(int p) => _pool
      .skip(p * _itemsPerPage)
      .take(_itemsPerPage)
      .toList();

  /// 素材類型：優先 gateway kind 欄位，沒有就副檔名 fallback。
  bool _isTextFile(Map<String, dynamic> f) {
    final k = f['kind'] as String?;
    if (k == 'text') return true;
    if (k == 'image') return false;
    final name = (f['path'] as String? ?? '').split('/').last;
    return _textExts.contains(name.toLowerCase().split('.').last);
  }

  /// 預載 from 起連續 3 頁（含 current）：圖抓縮圖 thumb720、文字抓全文。
  /// [2026-11-20 此刻頁三刀·刀①] 切片圖不足（<3 張）→ 向切片之後的池範圍
  /// （下 30 筆）掃 image 檔一併預載縮圖（補圖走既有 forWall 池，敏感過濾不破）。
  void _prefetchFrom(int from) {
    final last = min(from + 3, _pageCount) - 1;
    for (var p = from; p <= last; p++) {
      for (final f in _slice(p)) {
        final path = f['path'] as String? ?? '';
        if (path.isEmpty) continue;
        if (_isTextFile(f)) {
          _ensureText(path);
        } else {
          _ensureThumb(path);
        }
      }
      // [刀①] 本頁圖不足 3 張 → 向後掃圖補進請求集
      // [2026-11-21 斷線風暴根治·刀B] 窗口 30→8：補圖窗砍小，防一次暴走
      // 幾十張縮圖請求打爆 gateway（hero 保底另有 8 發、走同一佇列）。
      if (_slice(p).where((f) => !_isTextFile(f)).length < 3) {
        for (final f in _pool
            .skip((p + 1) * _itemsPerPage)
            .take(_thumbBackfillWindow)) {
          if (_isTextFile(f)) continue;
          final path = f['path'] as String? ?? '';
          if (path.isNotEmpty) _ensureThumb(path);
        }
      }
    }
  }

  /// 縮圖（thumb:true maxPx:720）→ LRU 快取。失敗靜默（磚顯示圖示＝誠實降級）。
  /// [2026-11-17 修] inflight 移除移到快取落地之後——回應處理中（await 回來
  /// 到 setState 之間）別的呼叫會通過除重檢查造成重抓（測試抓包 Actual=2）。
  /// [2026-11-21 斷線風暴根治·刀B] 由直接 fire-and-forget 改為串行佇列：
  /// 呼叫只入佇列（除重靠 _inflight），實際抓取由 _pumpThumbQueue 以併發
  /// 上限 2 依序放行；失敗進 30s 冷卻不立刻重發（防重連後全量重發風暴）。
  Future<void> _ensureThumb(String path) async {
    if (_imageCache.containsKey(path) || _inflight.contains(path)) return;
    // 失敗冷卻：30s 內不重發同一檔（超過冷卻期放行＝允許自然重試）。
    final failedAt = _thumbFailedAt[path];
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < const Duration(seconds: 30)) {
      return;
    }
    // 入佇列（同檔已在佇列候位就不重複排）。
    _inflight.add(path);
    _thumbQueue.add(path);
    _pumpThumbQueue();
  }

  /// 佇列放行器：在途未達上限就取下一檔開抓；完成後續泵。
  void _pumpThumbQueue() {
    while (_thumbActive < _thumbMaxConcurrent && _thumbQueue.isNotEmpty) {
      final path = _thumbQueue.removeAt(0);
      _thumbActive++;
      _fetchThumb(path);
    }
  }

  /// 單檔縮圖實際抓取（由佇列串行呼叫，非 fire-and-forget 直發）。
  Future<void> _fetchThumb(String path) async {
    final res = await MobileBridgeClient.instance
        .sendVaultFile(path, thumb: true, maxPx: 720);
    if (!mounted) {
      _inflight.remove(path);
      _thumbActive--;
      _pumpThumbQueue();
      return;
    }
    final b64 = (res?['payload'] as Map?)?['base64'] as String?;
    if (res?['ok'] == true && b64 != null) {
      try {
        final bytes = base64Decode(b64);
        setState(() => _imageCachePut(path, bytes));
        _thumbFailedAt.remove(path);
      } catch (_) {
        _thumbFailedAt[path] = DateTime.now();
      }
    } else {
      _thumbFailedAt[path] = DateTime.now();
    }
    _inflight.remove(path);
    _thumbActive--;
    _pumpThumbQueue();
  }

  /// 全文 → 快取（含 truncated 標記）。失敗靜默（磚只顯檔名＝誠實）。
  Future<void> _ensureText(String path) async {
    if (_textCache.containsKey(path) || _inflight.contains(path)) return;
    _inflight.add(path);
    final res =
        await MobileBridgeClient.instance.sendVaultFile(path, thumb: false);
    if (!mounted) {
      _inflight.remove(path);
      return;
    }
    if (res?['ok'] == true) {
      final payload =
          (res?['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
      final text = payload['text'] as String?;
      if (text != null) {
        setState(() {
          _textCache[path] = text;
          _textTruncated[path] = payload['truncated'] == true;
        });
      }
    }
    _inflight.remove(path);
  }

  /// LRU 插入：命中重複先撿回尾部；超過上限從最舊清。
  void _imageCachePut(String path, Uint8List bytes) {
    _imageCache.remove(path);
    _imageCache[path] = bytes;
    while (_imageCache.length > _imageCacheCap) {
      _imageCache.remove(_imageCache.keys.first);
    }
  }

  String _nameOf(Map<String, dynamic> f) =>
      (f['path'] as String? ?? '').split('/').last;

  /// [此刻頁 v2] 組一面牆：池切片 → hero 圖＋文字磚（真內容）＋strip 圖＋minis 圖。
  /// 切片內圖文位由 _isTextFile 決定：第 1 個文字檔進文字磚，
  /// 圖依序填 hero→strip→minis。全沒有圖時 hero 留空（磚顯示圖示＝誠實）。
  DominoWallContent _contentForPage(int p, DominoSlot s, String label) {
    final items = _slice(p);
    Uint8List? hero;
    Uint8List? strip;
    final minis = <Uint8List>[];
    final miniPaths = <String>[];
    String heroPath = '';
    String stripPath = '';
    Map<String, dynamic>? textItem;

    for (final f in items) {
      final path = f['path'] as String? ?? '';
      if (path.isEmpty) continue;
      if (_isTextFile(f)) {
        // 文字磚：頁內最新文字檔（池已按時間排序，第一個即最新）
        textItem ??= f;
        continue;
      }
      final img = _imageCache[path];
      if (hero == null) {
        hero = img;
        heroPath = path;
      } else if (strip == null) {
        strip = img;
        stripPath = path;
      } else if (minis.length < 2) {
        minis.add(img ?? Uint8List(0));
        miniPaths.add(path);
      }
    }
    // 注：heroPath/stripPath 即使在快取未到時也要記錄（點開才抓原圖）
    // ——上面的賦值在 img null 時 path 也記了，這裡補 minis 的 null 佔位已做。

    // [2026-11-21 此刻頁收尾·修1前置] 正規化：切片迴圈可能把「bytes 空但 slot
    // 佔位」（hero/strip=null、minis=Uint8List(0) 佔位）留下來——空 bytes 送
    // Image.memory 會解碼失敗變破圖磚。先撤掉空佔位，讓下方補圖掃得以重補。
    if (hero != null && hero!.isEmpty) {
      hero = null;
      heroPath = '';
    }
    if (strip != null && strip!.isEmpty) {
      strip = null;
      stripPath = '';
    }
    for (var mi = minis.length - 1; mi >= 0; mi--) {
      if (minis[mi].isEmpty) {
        minis.removeAt(mi);
        if (mi < miniPaths.length) miniPaths.removeAt(mi);
      }
    }

    // [2026-11-21 此刻頁收尾·修1] 補圖判定改問「有沒有圖 bytes」而非「有沒有圖
    // slot」——病根：上面切片迴圈對「slot 是圖但縮圖未回」的檔會把 null 指派給
    // hero（slot 佔了位、bytes 卻是空），舊閘門 `hero == null` 因此永不觸發，
    // 第一頁 hero 就永遠灰佔位。且舊補圖只向切片「之後」（下 30 筆）掃——第一頁
    // 切片在池最前段、之後若全是文字檔就一張都不抓；向後預抓集同樣只往後，
    // 往前零請求。後面的頁因為翻頁前滾動已觸發 _prefetchFrom、縮圖早已落地，
    // 所以「往後滑有圖、第一頁永遠灰」。（Blue build 1120.1620 實測）
    // 修：① hero/strip 只收「真有 bytes」的圖；② 補掃改為全池掃描（池已按
    // modified 新→舊排序＝自然優先命中最新已快取圖），只收 _imageCache 已落地
    // 者——誠實不佔假路徑；補圖一律走既有 forWall 池，敏感過濾不破。
    final usedNames = <String>{
      if (heroPath.isNotEmpty) _nameOf({'path': heroPath}),
      if (stripPath.isNotEmpty) _nameOf({'path': stripPath}),
      for (final mp in miniPaths) _nameOf({'path': mp}),
    };
    bool slotOpen() => hero == null || strip == null || minis.length < 2;
    void fillWith(Uint8List bytes, String path) {
      if (hero == null) {
        hero = bytes;
        heroPath = path;
      } else if (strip == null) {
        strip = bytes;
        stripPath = path;
      } else {
        minis.add(bytes);
        miniPaths.add(path);
      }
      usedNames.add(_nameOf({'path': path})); // 同圖不重複補兩個磚位
    }

    if (slotOpen()) {
      for (final f in _pool) {
        if (!slotOpen()) break;
        if (_isTextFile(f)) continue;
        final path = f['path'] as String? ?? '';
        if (path.isEmpty || usedNames.contains(_nameOf(f))) continue;
        // 已指派 slot 但 bytes 未回的（heroPath/stripPath 已記）→ 跳過不重複佔位
        if (path == heroPath || path == stripPath) continue;
        final cached = _imageCache[path];
        if (cached == null) continue; // 快取未到不補位（誠實）
        fillWith(cached, path);
      }
    }
    // 補到 minis 不超過 2 格（骨架 §8.8a 小方格上限）
    while (minis.length > 2) {
      minis.removeLast();
      miniPaths.removeLast();
    }

    // 文字磚真內容：全文快取命中→前兩行；未命中→顯示檔名（誠實，非罐頭句）
    final textPath =
        textItem == null ? '' : textItem['path'] as String? ?? '';
    final textName = textItem == null ? '' : _nameOf(textItem);
    final fullText = _textCache[textPath];
    final isMoment = s.source == CarouselSource.moment;
    final quote = fullText != null && fullText.trim().isNotEmpty
        ? fullText.trim()
        : (textName.isNotEmpty
            ? textName
            : (isMoment ? '時針與分針又相遇了一次。' : ''));
    final heroName = heroPath.isEmpty ? '' : _nameOf({'path': heroPath});

    // [2026-11-21 此刻頁收尾·C] VAULT 資料磚縮圖：hero 之外的第一張「已快取」
    // 縮圖（全池掃，池已按 modified 新→舊＝自然最新優先）；全無→null＝
    // _DataBrick fallback 原 value/label 文字模式（誠實不佔假路徑）。
    // 放在補圖之後＝heroPath 已定案，排除條件才正確。
    Uint8List? dataThumb;
    for (final f in _pool) {
      if (_isTextFile(f)) continue;
      final path = f['path'] as String? ?? '';
      if (path.isEmpty || path == heroPath) continue;
      final cached = _imageCache[path];
      if (cached == null || cached.isEmpty) continue;
      dataThumb = cached;
      break;
    }

    // [2026-11-20 此刻頁三刀·刀②] 時刻卡接真內容（取代 hardcode 罐頭句）。
    // 相遇數學：格 k＝今日第 k 次時針分針相遇（domino_engine.dart 720/11 分鐘身份）。
    // 相伴天數：PairedDesktopStore 最新 pairedAt 起算（含當天=第 1 天，
    //   moment_milestone.dart 複製自桌面 time_sense_service）。
    // 里程碑命中（滿月/第 100 天/週年）→ momentTitle 顯示里程碑標籤。
    // [2026-11-21 此刻頁收尾·A] 時刻磚永遠顯示時刻內容：刪除 isMoment=false
    // 的「第 k 格 · 第 N 頁」else 分支（格數/頁數資訊 _SlotInfoBrick 已有，
    // 不該在時刻磚重複）。所有格一律相遇數學＋相伴天數。里程碑邏輯保留。
    String momentTitle = '時 刻';
    final companionDays = _pairedAt == null ? null : elapsedDaysSince(_pairedAt!);
    if (isMoment) {
      final milestone =
          _pairedAt == null ? null : momentMilestoneLabel(_pairedAt!);
      if (milestone != null) momentTitle = milestone;
    }
    final momentDetail = '本格 k＝今日第 ${s.k} 次時針分針相遇'
        '${companionDays != null ? ' · 相伴第 $companionDays 天' : ''}';

    return DominoWallContent(
      heroImage: hero,
      heroCaption: heroName,
      quote: quote,
      quoteSource: textPath.isNotEmpty ? textName : '時刻 · 第 ${s.k} 格',
      quotePath: textPath,
      stripImage: strip,
      stripPath: stripPath,
      heroPath: heroPath,
      minis: minis,
      miniPaths: miniPaths,
      momentTitle: momentTitle,
      momentDetail: momentDetail,
      dataValue: '${_pool.length}',
      dataLabel: 'VAULT 素材池 · $_pageCount 頁',
      dataThumb: dataThumb,
      onImageTap: _openImageView,
      onTextTap: _openTextView,
    );
  }

  // ── [此刻頁 v2] 點開檢視 ────────────────────────

  /// 圖磚點開：全圖檢視（黑底＋InteractiveViewer，點關閉；原圖點開時才抓）。
  Future<void> _openImageView(String path) async {
    final res = await MobileBridgeClient.instance
        .sendVaultFile(path, thumb: false);
    if (!mounted) return;
    final b64 = (res?['payload'] as Map?)?['base64'] as String?;
    Uint8List? bytes;
    if (res?['ok'] == true && b64 != null) {
      try {
        bytes = base64Decode(b64);
      } catch (_) {}
    }
    // 原圖抓失敗降級用縮圖快取（誠實：連縮圖都沒有才顯示錯誤）
    bytes ??= _imageCache[path];
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('無法開啟原圖：${res?['error'] ?? '連線中？'}'),
      ));
      return;
    }
    // [此刻頁 v2] mounted 已守（上方）——直接經 State.context 推全圖檢視
    final full = bytes;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullImageView(bytes: full, name: _nameOf({'path': path})),
      ),
    );
  }

  /// 文字磚點開：全文 bottom sheet（圓角上緣＋SafeArea＋可滾動＋檔名＋truncated 標註）。
  Future<void> _openTextView(String path) async {
    if (!_textCache.containsKey(path)) {
      await _ensureText(path);
    }
    if (!mounted) return;
    final text = _textCache[path];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _TextSheet(
        name: _nameOf({'path': path}),
        text: text,
        error: text == null
            ? '抓不到全文：可能是連線中，或檔案讀取失敗。'
            : null,
        truncated: _textTruncated[path] == true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.slot;
    if (s == null) return const SizedBox.shrink();

    final colors = BridgeDSColors.of(context);
    final label = switch (s.source) {
      CarouselSource.asset => '資產',
      CarouselSource.moment => '時刻',
      CarouselSource.perfectAlignment => '完美對齊',
    };

    // [此刻頁 v2] 牆從單面改為縱向 PageView：池有多少頁給多少頁，
    // 每頁一面 DominoWall（hero 圖 1＋文字磚 1＋strip 圖 1＋minis 圖 2）。
    final pageCount = _pageCount;

    return Opacity(
      opacity: widget.greyedOut ? HomeViewState.dimOpacityFactor : 1.0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 頂部輕條：格序＋來源＋頁碼＋連線燈（縮成一行——牆才是主角）
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '第 ${s.k} / 22 格 · $label',
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(color: colors.textSecondary, letterSpacing: 2),
                  ),
                  Row(children: [
                    if (pageCount > 1) ...[
                      Text(
                        '${_page + 1}/$pageCount 頁 ',
                        style: TierStyle.of(context, Tier.cardCaption)
                            .toTextStyle()
                            .copyWith(color: colors.textSecondary),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: MobileBridgeClient.instance.isConnected
                            ? colors.accentGreen
                            : colors.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _loadingPool ? '載入中' : '${_pool.length} 則',
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(color: colors.textTertiary),
                    ),
                  ]),
                ],
              ),
            ),
            // 🀫 骨牌牆縱向輪播（Blue 令：手指上滑滾出下一頁）
            // [2026-11-17 v2 修] RefreshIndicator 從每頁牆內移到 PageView 外層
            // ——牆內 SingleChildScrollView(AlwaysScrollable) 會吃掉縱向手勢，
            // 手指上滑滾的是牆自己（牆高=視口高永不真的滾）→ PageView 翻不了頁。
            // 外掛 RefreshIndicator：PageView 頂部下拉才觸發重抓，上滑翻頁不受搶。
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadPool,
                child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                itemCount: pageCount,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  // [此刻頁 v2] 換頁 → 非同步預載當前起前方 3 頁素材
                  _prefetchFrom(i);
                },
                itemBuilder: (context, p) {
                  final content = _contentForPage(p, s, label);
                  final dateKey =
                      '${s.startAt.year}${s.startAt.month.toString().padLeft(2, '0')}${s.startAt.day.toString().padLeft(2, '0')}';
                  return DominoWall(
                    slot: DominoSlotInfo(
                      k: s.k,
                      total: 22,
                      sourceLabel: label,
                      windowLabel: _formatWindow(s),
                      dateKey: '$dateKey-p$p',
                      // [2026-11-20 此刻頁三刀·刀③] 此格時間窗內資產數（池 modified 計數）
                      slotAssetCount: _pool.isEmpty
                          ? null
                          : countPoolInWindow(_pool, s.startAt, s.endAt),
                    ),
                    content: content,
                  );
                },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatWindow(DominoSlot s) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(s.startAt.hour)}:${two(s.startAt.minute)} – '
        '${two(s.endAt.hour)}:${two(s.endAt.minute)}';
  }

  /// [2026-11-20 此刻頁三刀·刀③] 純函數：池內 modified（epoch ms）落在
  /// 時間窗 [startAt, endAt) 的資產件數。放 _formatWindow 旁（時間窗家族）。
  static int countPoolInWindow(
    List<Map<String, dynamic>> pool,
    DateTime startAt,
    DateTime endAt,
  ) {
    final lo = startAt.millisecondsSinceEpoch;
    final hi = endAt.millisecondsSinceEpoch;
    return pool.where((f) {
      final m = (f['modified'] as num?)?.toInt();
      return m != null && m >= lo && m < hi;
    }).length;
  }
}

/// [此刻頁 v2] 全圖檢視——黑底＋InteractiveViewer 縮放手勢，點任意處關閉。
class _FullImageView extends StatelessWidget {
  final Uint8List bytes;
  final String name;

  const _FullImageView({required this.bytes, required this.name});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              maxScale: 6,
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                errorBuilder: (ctx, e, st) => Center(
                  child: Icon(Icons.broken_image_outlined,
                      size: 48, color: Colors.white38),
                ),
              ),
            ),
            // 頂部檔名＋關閉提示（小字，不干擾圖）
            // [2026-11-21 大圖檔名置中 bug] StackFit.expand 會把非定位子項撐滿
            // 整個 Stack，Row 在撐滿容器中垂直置中＝檔名浮在畫面中央。
            // 用 Align(topCenter) 讓檔名列固定在頂端。
            Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    const Icon(Icons.close, color: Colors.white70, size: 20),
                  ],
                ),
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [此刻頁 v2] 全文檢視 bottom sheet——圓角上緣＋SafeArea＋可滾動全文
/// ＋檔名＋truncated 標註。抓不到誠實顯示錯誤（寧紅字不假成功）。
class _TextSheet extends StatelessWidget {
  final String name;
  final String? text;
  final String? error;
  final bool truncated;

  const _TextSheet({
    required this.name,
    required this.text,
    this.error,
    this.truncated = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 標題列：拖把手＋檔名＋truncated 標註
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(context, Tier.listItemTitle)
                          .toTextStyle(),
                    ),
                  ),
                  if (truncated)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.accentYellow.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color:
                                colors.accentYellow.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        '節錄',
                        style: TierStyle.of(context, Tier.cardCaption)
                            .toTextStyle()
                            .copyWith(color: colors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: SelectableText(
                  text ?? error ?? '',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.6,
                    color: error != null ? colors.accentRed : colors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 💬 對話——對話輸入＋最近對話（Blue 令：對話在「對話」呈現）
// ═══════════════════════════════════════════════════
// ignore: unused_element
// [2026-11-13 暫存] 舊平面對話頁——三層頁的對話視圖（第3層）將復用其氣泡樣式後移除
class _ChatPage extends StatelessWidget {
  final HomeViewState state;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmit;

  const _ChatPage({
    required this.state,
    this.controller,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    final recentChat = state.snapshot?.content['recentChat'];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: (recentChat is List && recentChat.isNotEmpty)
                ? ListView.builder(
                    itemCount: recentChat.length,
                    itemBuilder: (context, i) {
                      final item = recentChat[i];
                      if (item is! Map) return const SizedBox.shrink();
                      final isAssistant = item['role'] == 'assistant';
                      return Align(
                        alignment: isAssistant
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          constraints: const BoxConstraints(maxWidth: 300),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(14),
                              topRight: const Radius.circular(14),
                              bottomLeft: Radius.circular(
                                  isAssistant ? 4 : 14),
                              bottomRight: Radius.circular(
                                  isAssistant ? 14 : 4),
                            ),
                          ),
                          child: Text(
                            '${item['text'] ?? ''}',
                            style: TierStyle.of(context, Tier.cardBody)
                                .toTextStyle()
                                .copyWith(color: colors.textPrimary),
                          ),
                        ),
                      );
                    },
                  )
                : Center(
                    child: Text(
                      state.isOffline ? '離線中——重連後顯示最近對話' : '尚無對話',
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(color: colors.textSecondary),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          ChatInputSection(
            state: state,
            controller: controller,
            onSubmit: onSubmit,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// 🗂 任務面板——同桌面專案任務面板（Blue 拍板 2026-11-10：
// 「遙控」廢除，改為任務面板；對話↔任務卡雙向連動詳 SPEC §8）
// ═══════════════════════════════════════════════
class _RemotePage extends StatefulWidget {
  const _RemotePage();

  @override
  State<_RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<_RemotePage> {
  List<Map<String, dynamic>> _tasks = [];
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _lastPayload;

  @override
  void initState() {
    super.initState();
    _load();
    MobileBridgeClient.instance.addListener(_onConn);
  }

  @override
  void dispose() {
    MobileBridgeClient.instance.removeListener(_onConn);
    super.dispose();
  }

  void _onConn() {
    if (MobileBridgeClient.instance.isConnected) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await MobileBridgeClient.instance.sendTaskList();
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _loading = false;
        _error = '無回應——桌面 gateway 連線中？';
      });
      return;
    }
    if (res['ok'] != true) {
      setState(() {
        _loading = false;
        _error = (res['error'] ?? '載入失敗').toString();
      });
      return;
    }
    final payload = res['payload'] as Map<String, dynamic>? ?? {};
    final tasks = (payload['tasks'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (mounted) {
      setState(() {
        _tasks = tasks;
        _lastPayload = payload;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    // (tier 直接用 TierStyle.of(context, Tier.xxx))

    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 40,
              width: 40,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 12),
            Text(
              '載入任務中…',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colors.accentRed, size: 40),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.accentRed),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(
                '重試',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 40, color: colors.textTertiary),
            const SizedBox(height: 12),
            Text(
              '還沒有排程任務',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tasks.length,
      itemBuilder: (context, index) {
        final task = _tasks[index];
        return _TaskCard(task: task, colors: colors);
      },
    );
  }
}

// 任務卡（SPEC §8.3：id/name/schedule/warmth/lastRunOk/lastRunError/nextRunAt）
class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final BridgeDSColors colors;

  const _TaskCard({
    required this.task,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final warmth = task['warmth'] as String? ?? 'work';
    final warmthColor = warmth == 'life'
        ? const Color(0xFFFFB74D)
        : const Color(0xFF90A4AE);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: warmthColor.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  task['lastRunOk'] != false
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: task['lastRunOk'] != false
                      ? const Color(0xFF66BB6A)
                      : const Color(0xFFEF5350),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task['name'] as String? ?? 'Unknown',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: colors.textTertiary),
                  onSelected: (value) {
                    if (value == 'details') {
                      _showDetails(context);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'details',
                      child: Text('查看詳情'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              task['schedule'] as String? ?? '',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textSecondary, fontSize: 13),
            ),
            if (task['warmLine'] != null && (task['warmLine'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task['warmLine'] as String,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textSecondary.withOpacity(0.8),
                  fontStyle: FontStyle.italic,
                  fontSize: 12,
                ),
              ),
            ],
            if (task['lastRunError'] != null && (task['lastRunError'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF5350).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '上次失敗：${task['lastRunError']}',
                  style: TextStyle(
                    color: const Color(0xFFEF5350),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(task['name'] as String? ?? ''),
        content: SingleChildScrollView(
          child: ListBody(
            children: [
              _DetailRow(label: '排程', value: task['schedule'] ?? '-'),
              if (task['nextRunAt'] != null)
                _DetailRow(
                  label: '下次執行',
                  value: task['nextRunAt'] as String,
                ),
              if (task['lastRunOk'] != null)
                _DetailRow(
                  label: '上次成敗',
                  value: task['lastRunOk'] == true ? '成功' : '失敗',
                ),
              if (task['lastRunAt'] != null)
                _DetailRow(
                  label: '上次執行',
                  value: task['lastRunAt'] as String,
                ),
              if (task['lastRunError'] != null && (task['lastRunError'] as String).isNotEmpty)
                _DetailRow(
                  label: '失敗原因',
                  value: task['lastRunError'] as String,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 🔗 配對——快照＋配對管理（Blue 令：快照在「配對」呈現）
// ═══════════════════════════════════════════════════
// ═══════════════════════════════════════════════════
// 🗄️ 向量資料庫——SPEC §8.5（2026-11-12 Blue 拍板第五鈕）
// 清單（分頁+搜尋）→ 點檔案 → 預覽器（text/image/binary 全類型）
// ═══════════════════════════════════════════════════
class _VaultPage extends StatefulWidget {
  const _VaultPage();

  @override
  State<_VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<_VaultPage> {
  List<Map<String, dynamic>> _files = [];
  int _total = 0;
  bool _loading = false;
  String? _error;
  final _searchCtl = TextEditingController();

  // [2026-11-13 Blue 令：桌面簡化版鏡射] 素材牆/列表雙模式（同桌面 VaultViewMode）
  bool _wallMode = true; // 素材牆為預設——同桌面
  final Map<String, Uint8List> _thumbCache = {};
  final Set<String> _thumbLoading = {};

  // [SPEC §8.5b] 搜尋模式（同桌面三模式：語意/全文/標籤）＋標籤清單
  String _searchMode = 'hybrid'; // hybrid（向量搜尋，預設）| semantic | fullText | tag
  List<Map<String, dynamic>> _tags = [];
  String? _activeTag;

  int _autoFetchCount = 0;
  Timer? _autoFetchDebounce; // [11-15] 連線補抓防抖 // [2026-11-13 Blue 令] 連線→自動重抓（防風暴上限）
  int _lastSeenVaultVersion = 0; // [§8.5c] 上次處理的 vault 版本

  @override
  void initState() {
    super.initState();
    _load();
    _loadTags();
    // [2026-11-13 Blue 報案] 連線一建立全頁面自動更新（initState 時未連線會抓空）
    // [SPEC §8.5c] ＋vaultChanged 推播（桌面新檔案→版本+1→自動重抓）
    MobileBridgeClient.instance.addListener(_onConnForVault);
  }

  @override
  void dispose() {
    _autoFetchDebounce?.cancel();
    MobileBridgeClient.instance.removeListener(_onConnForVault);
    super.dispose();
  }

  void _onConnForVault() {
    final client = MobileBridgeClient.instance;
    // ① 連線建立 → 補抓 [11-15 Blue 報案「向量庫要手動下拉」]
    // 舊上限 5 次：App 生命週期用完後永遠不自動抓。改：連線事件一律補抓，
    // 防風暴由下方 1s debounce 防抖承擔（同秒多事件只抓一次）。
    if (client.isConnected) {
      _autoFetchDebounce?.cancel();
      _autoFetchDebounce = Timer(const Duration(seconds: 1), () {
        if (mounted && MobileBridgeClient.instance.isConnected) {
          _lastSeenVaultVersion = MobileBridgeClient.instance.vaultVersion;
          _load(query: _searchCtl.text);
          _loadTags();
        }
      });
      return;
    }
    if (false) {
      _lastSeenVaultVersion = client.vaultVersion;
      _load(query: _searchCtl.text);
      _loadTags();
      return;
    }
    // ② [§8.5c] 桌面 vault 變動推播（newFiles/updatedFiles>0）→ 自動重抓
    if (client.isConnected && client.vaultVersion != _lastSeenVaultVersion) {
      _lastSeenVaultVersion = client.vaultVersion;
      _load(query: _searchCtl.text);
      _loadTags();
    }
  }

  Future<void> _loadTags() async {
    final res = await MobileBridgeClient.instance.sendVaultTags();
    if (res == null || res['ok'] != true) return;
    final tags = ((res['payload'] as Map?)?['tags'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (mounted) setState(() => _tags = tags);
  }

  /// 搜尋入口：tag 模式走標籤；其他走 vaultSearch；空查詢回全清單。
  Future<void> _runSearch() async {
    final q = _searchCtl.text.trim();
    if (_searchMode == 'tag') {
      if (_activeTag == null) return;
      await _load(tag: _activeTag);
      return;
    }
    if (q.isEmpty) {
      await _load();
      return;
    }
    setState(() { _loading = true; _error = null; });
    final res = await MobileBridgeClient.instance
        .sendVaultSearch(query: q, mode: _searchMode);
    if (!mounted) return;
    if (res == null) {
      setState(() { _loading = false; _error = '無回應——桌面 gateway 連線中？'; });
      return;
    }
    if (res['ok'] != true) {
      setState(() { _loading = false; _error = (res['error'] ?? '搜尋失敗').toString(); });
      return;
    }
    final payload = res['payload'] as Map<String, dynamic>;
    setState(() {
      _files = (payload['files'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _total = (payload['total'] as num?)?.toInt() ?? 0;
      _loading = false;
    });
  }

  /// 標籤模式載入（tag 名直查）。
  Future<void> _load({String query = '', String? tag}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // 標籤模式：走 vaultSearch(tag)；一般：vaultList
    final res = tag != null
        ? await MobileBridgeClient.instance
            .sendVaultSearch(query: '', mode: 'tag', tag: tag)
        : await MobileBridgeClient.instance
            .sendVaultList(offset: 0, limit: 200, query: query);
    if (!mounted) return;
    if (res == null) {
      setState(() {
        _loading = false;
        _error = '無回應——桌面 gateway 連線中？';
      });
      return;
    }
    if (res['ok'] != true) {
      setState(() {
        _loading = false;
        _error = (res['error'] ?? 'vaultList 失敗').toString();
      });
      return;
    }
    final payload = res['payload'] as Map<String, dynamic>;
    setState(() {
      _files = (payload['files'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _total = (payload['total'] as num?)?.toInt() ?? 0;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('向量資料庫',
                        style: TierStyle.of(context, Tier.cardHeroTitle)
                            .toTextStyle()),
                  ),
                  // 模式切換——同桌面（素材牆 dashboard / 列表 list）
                  _SegmentedIconToggle(
                    wallMode: _wallMode,
                    onChanged: (v) => setState(() => _wallMode = v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text('$_total 個檔案 · 桌面同步',
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: colors.textTertiary)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
              child: TextField(
                controller: _searchCtl,
                onSubmitted: (_) => _runSearch(),
                textInputAction: TextInputAction.search,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
                decoration: InputDecoration(
                  hintText: _searchMode == 'tag' ? '標籤：從下方標籤列選擇…' : (_searchMode == 'hybrid' ? '向量搜尋——全文＋語意＋智慧排序…' : (_searchMode == 'semantic' ? '語意搜尋——描述你想找的內容…' : '全文搜尋檔名/內容…')),
                  hintStyle: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: colors.textTertiary),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colors.borderSubtle),
                  ),
                ),
              ),
            ),
            // [§8.5b] 搜尋模式膠囊——同桌面三模式
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Row(
                children: [
                  _modeChip(colors, '向量搜尋', 'hybrid'),
                  const SizedBox(width: 6),
                  _modeChip(colors, '語意', 'semantic'),
                  const SizedBox(width: 6),
                  _modeChip(colors, '全文', 'fullText'),
                  const SizedBox(width: 6),
                  _modeChip(colors, '標籤', 'tag'),
                ],
              ),
            ),
            // 標籤 chips（tag 模式顯示；有標籤才顯示）
            if (_searchMode == 'tag' && _tags.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  itemCount: _tags.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final t = _tags[i];
                    final active = _activeTag == t['name'];
                    return GestureDetector(
                      onTap: () {
                        setState(() => _activeTag = t['name'] as String?);
                        _runSearch();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: active
                              ? colors.accentPurple.withValues(alpha: 0.2)
                              : colors.surfaceElevated,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: active
                                ? colors.accentPurple
                                : colors.borderSubtle,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          '${t['label']}（${t['count']}）',
                          style: TierStyle.of(context, Tier.cardCaption)
                              .toTextStyle()
                              .copyWith(
                                color: active
                                    ? colors.accentPurple
                                    : colors.textSecondary,
                              ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(_error!,
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(color: colors.accentRed)),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _load(query: _searchCtl.text),
                      child: _wallMode
                          ? _buildWall(colors)
                          : ListView.builder(
                              itemCount: _files.length,
                              itemBuilder: (_, i) => _fileTile(colors, _files[i]),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeChip(BridgeDSColors colors, String label, String mode) {
    final active = _searchMode == mode;
    return GestureDetector(
      onTap: () => setState(() { _searchMode = mode; if (mode != 'tag') _runSearch(); }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? colors.accentBlue.withValues(alpha: 0.18)
              : colors.surfaceElevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? colors.accentBlue : colors.borderSubtle,
            width: 1,
          ),
        ),
        child: Text(label,
            style: TierStyle.of(context, Tier.cardCaption)
                .toTextStyle()
                .copyWith(
                  color: active ? colors.accentBlue : colors.textSecondary,
                )),
      ),
    );
  }

  // ── 素材牆（桌面鏡射簡化版）────────────────────────────
  // 2 列瀑布格：圖檔=縮圖滿格；非圖=圖示+檔名卡。點擊=同清單（開預覽器）。
  Widget _buildWall(BridgeDSColors colors) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.92,
      ),
      itemCount: _files.length,
      itemBuilder: (_, i) => _wallTile(colors, _files[i]),
    );
  }

  Widget _wallTile(BridgeDSColors colors, Map<String, dynamic> f) {
    final path = f['path'] as String? ?? '';
    final name = path.split('/').last;
    final ext = name.toLowerCase().split('.').last;
    final isImg =
        const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'}.contains(ext);
    return GestureDetector(
      onTap: () => _openPreview(path, name),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.borderSubtle, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: isImg
            ? _thumbCell(colors, path, name)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_extIcons[ext] ?? Icons.insert_drive_file_outlined,
                      size: 40, color: colors.textTertiary),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TierStyle.of(context, Tier.cardCaption)
                            .toTextStyle()),
                  ),
                ],
              ),
      ),
    );
  }

  /// 縮圖格：優先快取；載入中 placeholder；失敗退圖示（寧降級不空白）。
  Widget _thumbCell(BridgeDSColors colors, String path, String name) {
    final cached = _thumbCache[path];
    if (cached != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(cached, fit: BoxFit.cover),
          // 底部漸層檔名條（素材牆語意）
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.65)],
                ),
              ),
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ),
        ],
      );
    }
    _loadThumb(path);
    return Center(
      child: Icon(Icons.image_outlined, size: 32, color: colors.textTertiary),
    );
  }

  Future<void> _loadThumb(String path) async {
    if (_thumbLoading.contains(path)) return;
    _thumbLoading.add(path);
    final res = await MobileBridgeClient.instance
        .sendVaultFile(path, thumb: true, maxPx: 360);
    _thumbLoading.remove(path);
    if (res == null || res['ok'] != true) return;
    final b64 = (res['payload'] as Map?)?['base64'] as String?;
    if (b64 == null) return;
    try {
      final bytes = base64Decode(b64);
      if (mounted) setState(() => _thumbCache[path] = bytes);
    } catch (_) {}
  }

  static const _extIcons = {
    'md': Icons.description_outlined,
    'txt': Icons.notes_outlined,
    'json': Icons.data_object_outlined,
    'log': Icons.receipt_long_outlined,
    'csv': Icons.table_chart_outlined,
    'pdf': Icons.picture_as_pdf_outlined,
  };

  Widget _fileTile(BridgeDSColors colors, Map<String, dynamic> f) {
    final path = f['path'] as String? ?? '';
    final name = path.split('/').last;
    final ext = name.toLowerCase().split('.').last;
    final img = const {'png', 'jpg', 'jpeg', 'gif', 'webp'}.contains(ext);
    final icon = img
        ? Icons.image_outlined
        : (_extIcons[ext] ?? Icons.insert_drive_file_outlined);
    final size = (f['size'] as num?)?.toInt() ?? 0;
    final indexed = f['indexed'] == true;
    return ListTile(
      leading: Icon(icon, color: colors.textTertiary),
      title: Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TierStyle.of(context, Tier.listItemTitle).toTextStyle()),
      subtitle: Text(
        '${_fmtSize(size)} · ${(f['folder'] as String? ?? '').isEmpty ? "根目錄" : f['folder']}${indexed ? " · 已索引" : ""}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TierStyle.of(context, Tier.cardCaption)
            .toTextStyle()
            .copyWith(color: colors.textTertiary),
      ),
      onTap: () => _openPreview(path, name),
    );
  }

  static String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _openPreview(String path, String name) async {
    final res = await MobileBridgeClient.instance.sendVaultFile(path);
    if (!mounted) return;
    if (res == null || res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('無法開啟：${res?['error'] ?? '連線中？'}'),
      ));
      return;
    }
    final payload = res['payload'] as Map<String, dynamic>;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _VaultFilePreview(
        name: name,
        payload: payload,
      ),
    ));
  }
}

/// 檔案預覽器——text 全文（等寬）/ image base64 / binary 摘要。
/// SPEC §8.5 鐵則：vault 內檔案點開不可空白。
class _VaultFilePreview extends StatefulWidget {
  final String name;
  final Map<String, dynamic> payload;

  const _VaultFilePreview({required this.name, required this.payload});

  @override
  State<_VaultFilePreview> createState() => _VaultFilePreviewState();
}

class _VaultFilePreviewState extends State<_VaultFilePreview> {
  Map<String, dynamic> get payload => widget.payload;
  String get name => widget.name;

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    final kind = payload['kind'] as String? ?? 'binary';
    final body = switch (kind) {
      'text' => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            payload['text'] as String? ?? '（空檔案）',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              height: 1.6,
              color: colors.textSecondary,
            ),
          ),
        ),
      'image' => InteractiveViewer(
          maxScale: 6,
          child: Image.memory(
            base64Decode(payload['base64'] as String? ?? ''),
            errorBuilder: (ctx, e, st) => _fallback(ctx, colors, '圖片解碼失敗'),
          ),
        ),
      'binary' => _binaryFallback(colors),
      _ => Builder(
          builder: (ctx) => _fallback(
                ctx,
                colors,
                '二位元檔（${_VaultPageState._fmtSize((payload['size'] as num?)?.toInt() ?? 0)}）——手機不支援預覽',
              ),
        ),
    };
    final truncated = payload['truncated'] == true;
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        title: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(context, Tier.listItemTitle).toTextStyle()),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (truncated)
            Container(
              color: colors.accentYellow.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text('檔案過大——僅顯示前 256KB',
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: colors.accentYellow)),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _fallback(BuildContext context, BridgeDSColors colors, String msg) =>
      Center(
        child: Text(msg,
            style: TierStyle.of(context, Tier.cardBody)
                .toTextStyle()
                .copyWith(color: colors.textTertiary)),
      );

  /// binary 檔：說明＋「用其他 App 開啟」按鈕（系統 ShareSheet）。
  Widget _binaryFallback(BridgeDSColors colors) {
    final shareable = payload['shareable'] == true;
    final size = (payload['size'] as num?)?.toInt() ?? 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined,
                size: 56, color: colors.textTertiary),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.cardTitle)
                  .toTextStyle()
                  .copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              shareable
                  ? '${_VaultPageState._fmtSize(size)}——App 內不支援此格式，交給其他 App 開啟'
                  : '${_VaultPageState._fmtSize(size)}——檔案過大（>20MB），請回桌面版開啟',
              textAlign: TextAlign.center,
              style: TierStyle.of(context, Tier.cardBody)
                  .toTextStyle()
                  .copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: 20),
            if (shareable)
              FilledButton.icon(
                onPressed: _openExternally,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('用其他 App 開啟'),
              ),
          ],
        ),
      ),
    );
  }

  /// 存暫存檔 → 呼叫 iOS ShareSheet（使用者選 PDF 專家/Safari/Files…）。
  Future<void> _openExternally() async {
    final b64 = payload['base64'] as String?;
    if (b64 == null) return;
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(base64Decode(b64));
      await SharePlus.instance.share(
        ShareParams(files: [XFile(f.path)], text: name),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法開啟：$e')),
        );
      }
    }
  }
}

class _PairingPage extends StatefulWidget {
  final HomeViewState state;

  const _PairingPage({required this.state});

  @override
  State<_PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<_PairingPage> {
  List<PairedDesktop> _paired = [];

  @override
  void initState() {
    super.initState();
    PairedDesktopStore.getAll().then((d) {
      if (mounted) setState(() => _paired = d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    final client = MobileBridgeClient.instance;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // [S4 2026-11-11 Blue 報] 綁定狀態要一眼可見——已配對桌面卡（鎖圖示＋桌面名＋端點）
          if (_paired.isNotEmpty) ...[
            for (final d in _paired)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: client.isConnected
                        ? colors.accentGreen.withValues(alpha: 0.5)
                        : colors.borderDefault,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 20,
                      color: client.isConnected
                          ? colors.accentGreen
                          : colors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.desktopName,
                            style: TierStyle.of(context, Tier.cardTitle)
                                .toTextStyle()
                                .copyWith(color: colors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${d.host}:${d.port}・已綁定${client.isConnected ? '・連線中' : '・離線（啟動時自動重連）'}',
                            style: TierStyle.of(context, Tier.cardCaption)
                                .toTextStyle()
                                .copyWith(color: colors.textSecondary),
                          ),
                          // [2026-11-13 連線驗屍] 離線時顯示 client 真實狀態+錯誤
                          // ——寧紅字不假成功；加上 build 標記辨識新舊
                          if (!client.isConnected) ...[
                            const SizedBox(height: 4),
                            Text(
                              '狀態：${client.state.name}'
                              '${client.lastError != null ? '\n錯誤：${client.lastError}' : ''}',
                              style: TierStyle.of(context, Tier.cardCaption)
                                  .toTextStyle()
                                  .copyWith(color: colors.accentRed, fontSize: 11),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'build $kMobileBuildStamp',
                            style: TierStyle.of(context, Tier.cardCaption)
                                .toTextStyle()
                                .copyWith(color: colors.textTertiary, fontSize: 10),
                          ),
                          // [2026-11-14 三天自動連線終局驗屍] paired 與 token 落地狀態
                          // [刀① 2026-11-19] 改走 did key 咽喉（loadTokenFor）——
                          // 除錯顯示必須跟 bootstrap 讀同一顆 key，否則顯示與實況打架
                          FutureBuilder<bool>(
                            future: _paired.isNotEmpty
                                ? loadTokenFor(_paired.last).then((t) => t != null)
                                : Future.value(false),
                            builder: (context, snap) => Text(
                              '配對：${_paired.isNotEmpty ? '${_paired.last.host}:${_paired.last.port}' : '無'}'
                              ' · token：${snap.data == true ? '✓已存' : snap.hasData ? '✗缺失' : '…'}',
                              style: TierStyle.of(context, Tier.cardCaption)
                                  .toTextStyle()
                                  .copyWith(color: colors.textTertiary, fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
          ],
          // [2026-11-12 Blue 令] 配對頁只留配對資訊＋按鈕——快照/最近對話移除（太雜）
          const SizedBox(height: 16),
          // [S4 2026-11-10] 配對管理——push 進既有配對頁（QR/掃碼/綁定管理複用）
          OutlinedButton.icon(
            onPressed: () => context.push('/mobile-pairing'),
            icon: Icon(Icons.qr_code_scanner,
                size: 18, color: colors.textPrimary),
            label: Text(
              '配對管理（QR／掃碼）',
              style: TierStyle.of(context, Tier.cardBody)
                  .toTextStyle()
                  .copyWith(color: colors.textPrimary),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colors.borderDefault),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 單色極簡 Tab Bar（Blue 令：符號單色更簡約）
// ═══════════════════════════════════════════════════
class _MonoTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _MonoTabBar({required this.index, required this.onTap});

  static const _items = [
    (Icons.circle_outlined, '此刻'),
    (Icons.chat_bubble_outline, '對話'),
    (Icons.dashboard_outlined, '任務面板'),
    (Icons.storage_outlined, '向量庫'), // [SPEC §8.5 2026-11-12] 第五鈕
    (Icons.link, '配對'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return BottomAppBar(
      color: colors.canvas,
      elevation: 0,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onTap(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _items[i].$1,
                      size: 22,
                      color: i == index
                          ? colors.textPrimary
                          : colors.textTertiary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _items[i].$2,
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(
                            color: i == index
                                ? colors.textPrimary
                                : colors.textTertiary,
                            letterSpacing: 2,
                          ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 素材牆/列表 切換鈕（桌面 VaultViewMode 的手機鏡射——圖示雙切換）。
class _SegmentedIconToggle extends StatelessWidget {
  final bool wallMode;
  final ValueChanged<bool> onChanged;

  const _SegmentedIconToggle({required this.wallMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    Widget seg(IconData icon, bool active, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active ? colors.accentBlue.withValues(alpha: 0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon,
                size: 18,
                color: active ? colors.accentBlue : colors.textTertiary),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.borderSubtle, width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(Icons.dashboard_customize, wallMode, () => onChanged(true)),
        seg(Icons.list, !wallMode, () => onChanged(false)),
      ]),
    );
  }
}
