// mobile_bridge_client.dart
// 手機端 WebSocket client — 連接 Bridge Desktop Gateway。
// 負責：connect / hello 握手 / 自動重連 / 收發訊息 / 狀態廣播 / push 訊息接收
// Sprint 15a by 教練 Agent (CEO)
// Sprint 19a: 加 push 訊息接收 + sendTaskRun / sendTaskCancel

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:bridge_app/services/paired_desktop_store.dart';

import 'app_retina.dart';
import 'desktop_bridge_gateway_protocol.dart';
import 'mobile/sticky_endpoint_memory.dart'; // [2026-11-20 sticky 端點直攻]

/// 連線狀態
enum BridgeConnectionState {
  disconnected,
  connecting,
  connected,
  handshaking,
  ready,
  error,
}

/// 連線狀態變化事件
class BridgeConnectionEvent {
  final BridgeConnectionState state;
  final String? message;

  const BridgeConnectionEvent(this.state, {this.message});
}

/// 桌面端 push 訊息（task 進度、完成通知等）
class BridgePushEvent {
  final DesktopBridgeGatewayMessageType type;
  final Map<String, dynamic> payload;

  const BridgePushEvent({required this.type, this.payload = const {}});

  String? get taskId => payload['taskId'] as String?;
  double? get progress => (payload['progress'] as num?)?.toDouble();
  String? get message => payload['message'] as String?;
  bool? get success => payload['success'] as bool?;
  String? get error => payload['error'] as String?;
  String? get reason => payload['reason'] as String?;
}

/// 手機端 Bridge Desktop WebSocket client。
///
/// **Singleton** — 連線生命週期跟 App 綁定，不跟畫面綁定。
/// 配對畫面只引用 instance，不 dispose 它。
///
/// 生命週期：
/// 1. connect() → connecting
/// 2. WebSocket 連上 → handshaking
/// 3. hello 握手成功 → ready
/// 4. 斷線 → disconnected → 自動重連（如果 enabled）
///
/// Sprint 19a: 加 [pushStream] — 桌面主動推播的 task 訊息透過此 stream 廣播。
/// UI 層 listen pushStream 即可收到任務進度/完成通知。
class MobileBridgeClient with ChangeNotifier {
  // Singleton — App 層級生命週期
  static final MobileBridgeClient instance = MobileBridgeClient._();
  MobileBridgeClient._();

  WebSocket? _socket;
  StreamSubscription? _socketSub;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  BridgeConnectionState _state = BridgeConnectionState.disconnected;
  String? _lastError;
  String? _connectedEndpoint;

  // 連線目標
  String? _host;
  int? _port;
  String? _pairingCode;
  // [S1] 裝置 token（重連路；hello 成功後由主機簽發覆寫）
  String? _deviceToken;

  // [S4 2026-11-09] 最近一次 runtime snapshot（首頁快照區真相源）
  Map<String, dynamic>? _lastSnapshot;

  // [SPEC §8.5c 2026-11-13] vault 資料版本——桌面 vaultChanged 推播即 +1；
  // 頁面比較版本變化自動重抓（新檔案進來 → 此刻/向量庫自動更新）
  int _vaultVersion = 0;
  int get vaultVersion => _vaultVersion;

  // 重連
  bool _autoReconnect = true;
  int _reconnectAttempts = 0;
  // [11-15] 5→30：gateway 重啟（~30s）+網路閃斷都該覆蓋；指數退避 2*N 秒，
  // 30 次=最後一次延遲 60s，總涵蓋 ~15 分鐘——足夠等 Mac App 重啟完成。
  static const int _maxReconnectAttempts = 30;
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  // --- Sprint 19a: push 訊息 stream ---
  final StreamController<BridgePushEvent> _pushController =
      StreamController<BridgePushEvent>.broadcast();

  /// 桌面主動推播訊息 stream。
  ///
  /// 收到 taskProgress / taskComplete / taskAwaitingConfirmation 時透過此 stream 廣播。
  /// UI 層用 `client.pushStream.listen((event) { ... })` 接收。
  Stream<BridgePushEvent> get pushStream => _pushController.stream;

  /// 目前連線狀態
  BridgeConnectionState get state => _state;
  String? get lastError => _lastError;
  String? get connectedEndpoint => _connectedEndpoint;
  bool get isConnected =>
      _state == BridgeConnectionState.ready ||
      _state == BridgeConnectionState.connected;

  /// 連線到指定桌面端。
  ///
  /// [host] 桌面端 LAN IP
  /// [port] Gateway port（以 QR payload 為真相源——禁 hardcode，SPEC v0.5 §6.1）
  /// [pairingCode] 配對碼（BRIDGE-XXXXXX，首次配對用）
  Future<bool> connect({
    required String host,
    required int port,
    required String pairingCode,
  }) async {
    _host = host;
    _port = port;
    _pairingCode = pairingCode;
    _deviceToken = null; // 首次配對路：不帶舊 token
    _autoReconnect = true;
    _reconnectAttempts = 0;
    _stickyTried = false; // [2026-11-20 sticky 端點直攻] 新連線週期重設
    _viaRelay = false; // [§6.3] 配對在家進行——直連優先，失敗爬樓梯

    return _doConnect();
  }

  /// [S1 2026-11-09 token 重連路] 憑裝置 token 重連（不重掃 QR）。
  ///
  /// 手機端流程：connect() 拿到 token 後存起來（MobileDeviceTokenStore），
  /// 之後 App 重啟/斷線 → 先試 [reconnectWithToken]，失敗才引導重掃 QR。
  Future<bool> reconnectWithToken({
    required String host,
    required int port,
    required String deviceToken,
  }) async {
    _host = host;
    _port = port;
    _pairingCode = null;
    _deviceToken = deviceToken;
    _autoReconnect = true;
    _reconnectAttempts = 0;
    _stickyTried = false; // [2026-11-20 sticky 端點直攻] 新連線週期重設
    // [2026-11-20 sticky 端點直攻] 標記本發可直攻 last-good 端點（若在其候選集內）。
    _stickyPreferred = true;
    // [§6.3 爬樓梯] 重連優先直連（回家快）；失敗自動翻中繼（出門）
    _viaRelay = false;

    return _doConnect();
  }

  /// hello 成功後主機發的裝置 token（null = 尚未配對成功）。
  String? get deviceToken => _deviceToken;

  // ── [SPEC §6.3 第三哩] 中繼端點（第 3 層出門通道）──
  String? _relayHost;
  int? _relayPort;
  String? _relayHostId;
  String? _relaySecret;

  static const _relayPrefsKey = 'bridge_mobile_relay_v1';

  /// 設定中繼（配對 QR 的 relay 參數或設定頁輸入）。null = 清除（純直連）。
  /// 自動持久化——App 重啟後 [loadRelay] 恢復。
  Future<void> setRelay({
    String? host,
    int? port,
    String? hostId,
    String? secret,
  }) async {
    _relayHost = host;
    _relayPort = port;
    _relayHostId = hostId;
    _relaySecret = secret;
    final prefs = await SharedPreferences.getInstance();
    if (host == null || port == null) {
      await prefs.remove(_relayPrefsKey);
    } else {
      await prefs.setString(_relayPrefsKey,
          jsonEncode({
            'host': host,
            'port': port,
            'hostId': hostId,
            'secret': secret,
          }));
    }
  }

  /// 啟動時恢復中繼設定（bootstrapAutoReconnect 前呼叫）。
  Future<bool> loadRelay() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_relayPrefsKey);
    if (raw == null) return false;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _relayHost = m['host'] as String?;
      _relayPort = (m['port'] as num?)?.toInt();
      _relayHostId = m['hostId'] as String?;
      _relaySecret = m['secret'] as String?;
      return _relayHost != null && _relayPort != null;
    } catch (_) {
      return false;
    }
  }

  /// 中繼是否已設定。
  bool get hasRelay => _relayHost != null && _relayPort != null;

  /// 本次連線是否走中繼（爬樓梯狀態）。
  bool _viaRelay = false;

  /// 目前是否經中繼連線（UI 顯示用）。
  bool get isViaRelay => _viaRelay;

  /// [2026-11-11 一機一證] 手機穩定識別碼——SharedPreferences 持久化，
  /// 重裝 App 才換。主機憑此辨認「同一支手機」，重配對撤舊證。
  static const _deviceIdKey = 'bridge_mobile_device_id_v1';
  String? _cachedDeviceId;
  Future<String> _deviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_deviceIdKey, id);
    }
    _cachedDeviceId = id;
    return id;
  }

  /// [S4] 最近一次桌面 runtime snapshot（null = 尚未收到）。
  Map<String, dynamic>? get lastSnapshot => _lastSnapshot;

  Completer<bool>? _helloCompleter;

  /// hello 10 秒未回＝失敗（防止 _doConnect 永久掛起）。
  Future<void> _helloTimeout(Completer<bool> c) async {
    await Future.delayed(const Duration(seconds: 10));
    if (!c.isCompleted) c.complete(false);
  }

  Future<bool> _doConnect() async {
    // [S1] 兩條路：pairingCode（首次）或 deviceToken（重連）——至少一項
    if (_host == null || _port == null || (_pairingCode == null && _deviceToken == null)) {
      _setError('連線參數不完整');
      return false;
    }

    // [2026-11-20 sticky 端點直攻] 重連先直攻上次成功端點——不再撞死 LAN
    // 門牌吃 8s 逾時才輪到 v6。觸發時機：重連計時器路（attempts>0）或
    // bootstrap 直攻路（_stickyPreferred，每輪 attempts=0）。只認當前候選集
    // （_host＋_altHosts）內的 sticky。本輪直攻一發，失敗退回既有輪替順序。
    final stickyEligible =
        !_viaRelay && (_reconnectAttempts > 0 || _stickyPreferred);
    var stickyAttack = false;
    String? stickyHostTried;
    if (stickyEligible) {
      _stickyPreferred = false; // 一次性：僅認 reconnectWithToken 那一發
      final sticky = await StickyEndpointMemory.loadLastGoodHost();
      final alreadyCurrent = sticky != null && sticky == _host;
      final inAlts = sticky != null && _altHosts.contains(sticky);
      // 計時器路：一輪一發（_stickyTried）；bootstrap 路：每輪都是第一發。
      if (sticky != null && (alreadyCurrent || inAlts) &&
          (_reconnectAttempts == 0 || !_stickyTried)) {
        _stickyTried = true;
        stickyAttack = true;
        stickyHostTried = sticky;
        if (!alreadyCurrent) {
          debugPrint('[MobileBridge] sticky 直攻上次成功端點: $sticky');
          _host = sticky;
        }
      }
    }

    // [11-16 出門直連] 候選輪替：重連時（_reconnectAttempts>0）換下一個候選 host。
    // 在家 LAN IP 先通就停；出門 4G 時 LAN 不通，幾輪後輪到 IPv6 直連。
    // [2026-11-20 sticky 端點直攻] sticky 直攻那一輪跳過輪替，順序保留為 fallback。
    if (!stickyAttack && _reconnectAttempts > 0 && _altHosts.isNotEmpty) {
      final next = _altHosts[_altIndex % _altHosts.length];
      _altIndex++;
      if (next != _host) {
        debugPrint('[MobileBridge] 輪替候選端點: $next');
        _host = next;
      }
    }

    // [SPEC §6.3 第三哩] 端點選擇：_viaRelay 旗標決定直連或中繼。
    // 爬樓梯：connect() 先試直連，失敗翻中繼；reconnectWithToken 直攻中繼
    // （出門情境優先）。WebSocket 協議零改動——中繼 HTTP peek 原樣盲轉。
    // [11-16 v6] IPv6 host 在 URL 需 [ ] 包裹
    final hostInUrl = _host!.contains(':') ? '[$_host]' : _host!;
    var endpoint = 'ws://$hostInUrl:$_port/bridge';
    Map<String, String>? relayHeaders;
    if (_viaRelay && _relayHost != null && _relayPort != null) {
      endpoint = 'ws://$_relayHost:$_relayPort/bridge';
      relayHeaders = {
        'x-bridge-host-id': _relayHostId ?? '',
        'x-bridge-secret': _relaySecret ?? '',
      };
    }
    _setState(BridgeConnectionState.connecting,
        message: _relayHost != null ? '中繼連線中…' : '連線中…');

    try {
      // [11-16 輪替] connect 8s 硬逾時——iOS 對不可達位址的系統級 timeout 長達 75s，
      // 沒有自己的逾時的話 LAN IP 卡一次就把輪替鎖死（Blue 4G 實測 errno 60 卡死）。
      _socket = await WebSocket.connect(endpoint,
              headers: relayHeaders)
          .timeout(const Duration(seconds: 8), onTimeout: () {
        throw TimeoutException('connect 逾時（8s）：$endpoint');
      });
      _connectedEndpoint = endpoint;
      // [11-15 Blue 報案「手機不會自動重連」] 協議層 keepalive：
      // TCP 半死（gateway 重啟/網路斷）時 iOS 不會主動通知——pingInterval
      // 讓底層定期 ping，斷線會觸發 onDone → _onDisconnect → 自動重連。
      // 5s ping、10s 無回應判定斷線（WebSocket 標準行為）。
      (_socket as dynamic).pingInterval = const Duration(seconds: 5);

      _setState(BridgeConnectionState.handshaking, message: '握手中…');

      // 發送 hello——帶 pairingCode（首次）或 deviceToken（重連）
      // [2026-11-14 三天自動連線病根] 舊版這裡直接 return true＝「socket 連上」
      // 而非「配對成功」——配對畫面讀 deviceToken 時 hello 回應還沒到（競態），
      // token 永遠存不到 → bootstrap 永遠離線。修：等 hello 回應才回 true。
      final helloDone = Completer<bool>();
      _helloCompleter = helloDone;
      unawaited(_helloTimeout(helloDone));
      _socket!.add(jsonEncode(
        DesktopBridgeGatewayRequest(
          id: 'mobile-hello',
          type: DesktopBridgeGatewayMessageType.hello,
          payload: _deviceToken != null
              ? {'deviceToken': _deviceToken}
              // [2026-11-11 一機一證] 配對碼路帶 deviceId——主機撤舊簽新
              : {
                  'pairingCode': _pairingCode,
                  'deviceId': await _deviceId(),
                },
        ).toJson(),
      ));

      // 監聽回應
      _socketSub = _socket!.listen(
        _onMessage,
        onError: (e) {
          if (!helloDone.isCompleted) helloDone.complete(false);
          _onDisconnect('WebSocket error: $e');
        },
        onDone: () {
          if (!helloDone.isCompleted) helloDone.complete(false);
          _onDisconnect('連線已關閉');
        },
        cancelOnError: true,
      );

      _startHeartbeat();
      // hello 回應（ok）到齊才算成功——_onMessage hello 分支會 complete
      final helloOk = await helloDone.future;
      if (helloOk) {
        // [2026-11-20 sticky 端點直攻] hello 成功＝真成功，記下這個端點。
        await StickyEndpointMemory.recordSuccess(_host!);
      } else if (stickyHostTried != null) {
        // [2026-11-20 sticky 端點直攻] sticky 那發握手失敗（hello 被拒/超時）
        // 同樣計帳——連敗達封頂自動失效，退回既有輪替順序。
        await StickyEndpointMemory.recordFailure(stickyHostTried);
      }
      return helloOk;
    } catch (e) {
      // [2026-11-20 sticky 端點直攻] sticky 直攻失敗（連不上/8s 逾時）→ 計帳，
      // 連敗達封頂自動失效，之後退回既有輪替順序。
      if (stickyHostTried != null) {
        await StickyEndpointMemory.recordFailure(stickyHostTried);
      }
      // [SPEC §6.3 第三哩 爬樓梯] 直連失敗且有中繼可用 → 切中繼再試一次
      // （出門場景：區網 IP 不通，翻第 3 層）
      if (!_viaRelay &&
          _relayHost != null &&
          _relayPort != null &&
          _reconnectAttempts == 0) {
        debugPrint('[MobileBridge] 直連失敗（$e）→ 爬樓梯改走中繼');
        _viaRelay = true;
        return _doConnect();
      }
      _setError('連線失敗：$e');
      _scheduleReconnect();
      return false;
    }
  }

  // [SPEC §8.5 2026-11-12] 同步 request-response（vaultList/vaultFile）
  /// requestId → Completer。_onMessage 收到帶 requestId 的 response 就完成。
  final _pendingVault = <String, Completer<Map<String, dynamic>>>{};

  /// vault 請求 id 防呆序號（同 ms 連發防撞 id，見 _requestVaultResponse）。
  int _vaultSeq = 0;

  /// 發同步請求等回應（10s 逾時）。回 null=未連線或逾時。
  Future<Map<String, dynamic>?> _requestVaultResponse(
    DesktopBridgeGatewayMessageType type,
    Map<String, dynamic> payload,
  ) async {
    if (_socket == null || !isConnected) return null;
    // [測試特攻C 2026-11-17] id 加單調遞增序號——同一毫秒連發（預載一頁
    // 多檔必同 ms）純時間戳會撞 id：_pendingVault 互相蓋掉→回應錯配→
    // 多數請求吊死到 10s 逾時。時間戳＋序號保證唯一。
    final id = 'vault-${DateTime.now().millisecondsSinceEpoch}-${++_vaultSeq}';
    final completer = Completer<Map<String, dynamic>>();
    _pendingVault[id] = completer;
    _socket!.add(jsonEncode(
      DesktopBridgeGatewayRequest(
        id: id,
        type: type,
        payload: payload,
      ).toJson(),
    ));
    // [2026-11-17] 逾時改可取消 Timer——Future.timeout 回應已回仍吊 10s 殭屍
    // Timer（每請求一個），widget 測試炸「Timer is still pending」、App 內也髒。
    final timer = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.completeError(
            TimeoutException('vault request timeout'));
      }
    });
    try {
      return await completer.future;
    } on TimeoutException {
      return null;
    } finally {
      timer.cancel();
      _pendingVault.remove(id);
    }
  }

  // [11-15 Blue 報案「都太慢」] 大回應 jsonDecode 卡 UI thread——
  // >8KB 的訊息丟背景 isolate 解碼（compute），小訊息照舊同步解。
  Future<void> _onMessage(dynamic data) async {
    try {
      final rawStr = data as String;
      Map<String, dynamic>? decoded;
      if (rawStr.length > 8192) {
        decoded = await compute(_decodeJsonMap, rawStr);
      } else {
        final d = jsonDecode(rawStr);
        decoded = d is Map<String, dynamic> ? d : null;
      }
      if (decoded == null) return;
    // [2026-11-17 修復] 斷頭合併殘屍：此處原本又 jsonDecode(data) 重解一次——
    // 外層的 compute 大訊息解碼結果被丟棄、大訊息照樣同步重解（11-15
    // 「大回應卡 UI thread」修復被整個廢掉）。直接用外層 decoded。
    try {

      final type = decoded['type'] as String?;
      final ok = decoded['ok'] as bool?;
      final payload = decoded['payload'] is Map
          ? Map<String, dynamic>.from(decoded['payload'] as Map)
          : <String, dynamic>{};

      // --- 同步 response（hello / runtimeSnapshot / capabilityList / error）---
      if (type == 'hello' && ok == true) {
        // [S1] 配對成功——主機簽發的裝置 token 落地（UI 層負責存 store）
        final issuedToken = payload['deviceToken'];
        if (issuedToken is String && issuedToken.isNotEmpty) {
          _deviceToken = issuedToken;
        }
        // 握手成功
        _setState(BridgeConnectionState.ready,
            message: '已連線到 ${payload['desktopName'] ?? 'Bridge Desktop'}');
        // [2026-11-14] hello 完成——解除 _doConnect 的 await
        final c = _helloCompleter;
        if (c != null && !c.isCompleted) c.complete(true);
      } else if (type == 'hello' && ok == false) {
        // hello 明確失敗——立刻解除（false）
        final c = _helloCompleter;
        if (c != null && !c.isCompleted) c.complete(false);
        final err = decoded['error'] ?? 'unknown';
        final isRepair = err.toString().contains('re-pair');
        // [刀③ 2026-11-19] 單端點 token 被拒 ≠ 憑證全局失效——原版
        // _autoReconnect=false + disconnect() 一刀全線停機是誤殺。
        // 「還有未試過的候選」=_altIndex 尚未走完一輪 altHosts；
        // 防呆：每次被拒 _scheduleReconnect 仍 +1 次，30 發封頂不可能無限迴圈。
        if (isRepair &&
            _deviceToken != null &&
            _altIndex < _altHosts.length) {
          // 續輪替：不清 token、不停機，關掉這條 socket 交給既有輪替機制
          // 換下一個候選端點（_onDisconnect → _scheduleReconnect → 換 host）。
          _socketSub?.cancel();
          _socket?.close();
          _socket = null;
          _socketSub = null;
          _onDisconnect('此端點拒絕裝置 token（re-pair）→ 輪替下一候選');
        } else {
          // 所有候選都被 re-pair 拒（或配對碼錯）——[S1] 此时才認定憑證失效：
          // 紅字引導重配對 + 清 token（寧紅字不假成功，行為同舊版）
          _deviceToken = null;
          _setError(isRepair
              ? '裝置 token 已失效，請重新掃描 QR Code 配對'
              : '配對碼錯誤：$err');
          _autoReconnect = false; // 憑證錯誤不重連（重連也不會過）
          disconnect();
        }
      } else if (type == 'vaultChanged') {
        // [SPEC §8.5c] 桌面 vault 變動推播——bump version + notify
        _vaultVersion++;
        notifyListeners();
      } else if (type == 'vaultList' ||
          type == 'vaultFile' ||
          type == 'vaultSearch' ||
          type == 'vaultTags' ||
          type == 'conversationList' ||
          type == 'conversationHistory' ||
          type == 'conversationAppend' ||
          // [2026-11-21 對話tab速勝 刀1] conversationDelete 漏掛白名單——
          // 回應無 completer 完成→10s timeout→回 false→UI 誤報「刪除失敗」
          // （實際已刪）。補上後 sendConversationDelete 收得到 ok:true。
          type == 'conversationDelete' ||
          // [SPEC §8.3 2026-11-14] 任務面板
          type == 'taskList') {
        // [2026-11-14 Blue 報案「載入中卡死/無回應」] 同步回應白名單漏了
        // search/tags/conversation*——completer 永不完成→10s timeout→null。
        // 修：全部同步回應統一走 _pendingVault 完成。
        // [SPEC §8.5] vault 同步回應——完成對應 completer
        final reqId = decoded['requestId'] as String?;
        if (reqId != null && _pendingVault.containsKey(reqId)) {
          _pendingVault[reqId]!.complete({
            'ok': ok == true,
            'payload': payload,
            'error': decoded['error'],
          });
        }
      } else if (type == 'runtimeSnapshot') {
        // [S4 2026-11-09] 快照落地——通知 UI 層（首頁快照區）
        _lastSnapshot = payload;
        if (payload.isNotEmpty) _setState(BridgeConnectionState.ready);
      } else if (type == 'taskRun' && ok == true) {
        // taskRun 同步回應 — 任務已啟動，taskId 在 payload 裡
        debugPrint('[MobileBridge] task started: ${payload['taskId']}');
      } else if (type == 'taskCancel') {
        // taskCancel 同步回應
        debugPrint('[MobileBridge] task cancel: ${payload['taskId']} status=${payload['status']}');
      } else if (type == 'error') {
        _setError('Gateway 錯誤：${decoded['error'] ?? 'unknown'}');
      }

      // [SPEC 開光手機版 2026-11-13] 桌面請求視網膜照片 → 拍 → 回傳
      if (type == 'retinaRequest') {
        _handleRetinaRequest(payload);
        return;
      }

      // --- push 訊息（桌面主動推播）---
      // push 訊息沒有 requestId 和 ok 欄位，只有 type + payload
      // [小隊動態 2026-11-17] squadChanged 同為 push（桌面→手機）——經
      // pushStream 廣播，頁面 listen 後重抓對話清單（接線留給指揮官）。
      if (type == 'taskProgress' ||
          type == 'taskComplete' ||
          type == 'taskAwaitingConfirmation' ||
          type == 'squadChanged') {
        final msgType = DesktopBridgeGatewayMessageType.values.firstWhere(
          (m) => m.name == type,
          orElse: () => DesktopBridgeGatewayMessageType.error,
        );
        _pushController.add(BridgePushEvent(
          type: msgType,
          payload: payload,
        ));
        debugPrint('[MobileBridge] push: $type taskId=${payload['taskId']}');
      }
    } catch (e) {
      debugPrint('[MobileBridge] 訊息解析失敗: $e');
    }

    } catch (e) {
      debugPrint('[MobileBridge] 訊息解析失敗: $e');
    }
  }

  static Map<String, dynamic>? _decodeJsonMap(String raw) {
    try {
      final d = jsonDecode(raw);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  /// [SPEC 開光手機版] 視網膜拍照回傳——AppRetina.capture（全域
  /// RepaintBoundary，任何頁面都能拍）。失敗回 null（寧紅字不假成功）。
  Future<void> _handleRetinaRequest(Map<String, dynamic> payload) async {
    final reqId = payload['requestId'] as String? ?? 'retina-${DateTime.now().millisecondsSinceEpoch}';
    String? b64;
    try {
      // App 在背景時 toImage 可能永不完成——6 秒硬上限，逾時回 null
      // （寧紅字不假成功；桌面端點點亮時手機在前景即可）
      b64 = await AppRetina.capture(pixelRatio: 1.0)
          .timeout(const Duration(seconds: 6), onTimeout: () => null);
    } catch (_) {
      b64 = null;
    }
    if (_socket == null) return;
    _socket!.add(jsonEncode(DesktopBridgeGatewayRequest(
      id: 'retina-resp-$reqId',
      type: DesktopBridgeGatewayMessageType.retinaResponse,
      payload: {'requestId': reqId, 'base64': b64},
    ).toJson()));
  }

  /// 發送 runtimeSnapshot 請求
  Future<void> requestRuntimeSnapshot() async {
    if (_socket == null || !isConnected) return;
    _socket!.add(jsonEncode(
      const DesktopBridgeGatewayRequest(
        id: 'mobile-runtime',
        type: DesktopBridgeGatewayMessageType.runtimeSnapshot,
      ).toJson(),
    ));
  }

  /// 發送 capabilityList 請求
  Future<void> requestCapabilityList() async {
    if (_socket == null || !isConnected) return;
    _socket!.add(jsonEncode(
      const DesktopBridgeGatewayRequest(
        id: 'mobile-capabilities',
        type: DesktopBridgeGatewayMessageType.capabilityList,
      ).toJson(),
    ));
  }

  // --- Sprint 19a: 長任務 API ---

  /// 啟動一個長任務。
  ///
  /// [taskType] 任務類型，如 "browser.navigate"
  /// [payload] 任務參數（如 url, selector, value 等）
  ///
  /// 回傳 taskId（成功啟動）或 null（啟動失敗）。
  /// 任務進度/結果透過 [pushStream] 推播。
  Future<String?> sendTaskRun({
    required String taskType,
    Map<String, dynamic> payload = const {},
  }) async {
    if (_socket == null || !isConnected) return null;

    final requestId = 'task-${DateTime.now().millisecondsSinceEpoch}';
    _socket!.add(jsonEncode(
      DesktopBridgeGatewayRequest(
        id: requestId,
        type: DesktopBridgeGatewayMessageType.taskRun,
        payload: {
          'taskType': taskType,
          'payload': payload,
        },
      ).toJson(),
    ));

    // 同步回應會在 _onMessage 處理，taskId 從 response payload 取得
    // 但因為 _onMessage 是 callback 模式，這裡不等待。
    // UI 層應該 listen pushStream 等待 taskProgress/taskComplete。
    // v1 簡化：回傳一個本地生成的暫時 ID，真實 taskId 從 push 訊息取得
    return requestId;
  }

  /// 取消進行中的任務。
  Future<bool> sendTaskCancel(String taskId) async {
    if (_socket == null || !isConnected) return false;

    _socket!.add(jsonEncode(
      DesktopBridgeGatewayRequest(
        id: 'cancel-${DateTime.now().millisecondsSinceEpoch}',
        type: DesktopBridgeGatewayMessageType.taskCancel,
        payload: {'taskId': taskId},
      ).toJson(),
    ));
    return true;
  }

  /// [S1] 拍板——回覆 taskAwaitingConfirmation。
  ///
  /// [taskId] 暫停中任務的 ID（來自 push 的 taskAwaitingConfirmation payload）
  /// [approve] true=批准繼續 / false=否決終止
  /// 回 true 代表已送出（結果由同步回應確認；逾時由主機端 5 分鐘否決）。
  Future<bool> sendConfirmationRespond({
    required String taskId,
    required bool approve,
  }) async {
    if (_socket == null || !isConnected) return false;

    _socket!.add(jsonEncode(
      DesktopBridgeGatewayRequest(
        id: 'confirm-${DateTime.now().millisecondsSinceEpoch}',
        type: DesktopBridgeGatewayMessageType.confirmationRespond,
        payload: {'taskId': taskId, 'approve': approve},
      ).toJson(),
    ));
    return true;
  }

  // --- [SPEC §8.5 2026-11-12] 向量資料庫 ---

  /// 列 vault 檔案（分頁＋路徑/資料夾關鍵字過濾）。
  /// 回 null=離線/逾時；payload: {total, offset, files:[ManifestFile...]}
  Future<Map<String, dynamic>?> sendVaultList({
    int offset = 0,
    int limit = 200,
    String query = '',
    bool forWall = false, // [SPEC §8.8b] 骨牌牆輪播池（安全圖片＋最新優先）
  }) =>
      _requestVaultResponse(
        DesktopBridgeGatewayMessageType.vaultList,
        {
          'offset': offset,
          'limit': limit,
          'query': query,
          if (forWall) 'forWall': true,
        },
      );

  /// [SPEC §8.5b] 語意/全文/標籤搜尋（同桌面 facade）。
  Future<Map<String, dynamic>?> sendVaultSearch({
    required String query,
    String mode = 'semantic', // fullText | semantic | tag
    String? tag,
    int limit = 40,
  }) =>
      _requestVaultResponse(
        DesktopBridgeGatewayMessageType.vaultSearch,
        {
          'query': query,
          'mode': mode,
          if (tag != null) 'tag': tag,
          'limit': limit,
        },
      );

  /// [SPEC §8.5b] 標籤清單（FileTagStore）。
  Future<Map<String, dynamic>?> sendVaultTags() =>
      _requestVaultResponse(
        DesktopBridgeGatewayMessageType.vaultTags,
        const {},
      );

  /// 讀單一檔案（預覽器）。
  /// payload: {kind: text|image|binary, text?, base64?, size, truncated?}
  Future<Map<String, dynamic>?> sendVaultFile(
    String path, {
    bool thumb = false, // [Blue 令] 牆/清單用縮圖（720px q85）；預覽器用原圖
    int maxPx = 720,
  }) =>
      _requestVaultResponse(
        DesktopBridgeGatewayMessageType.vaultFile,
        {
          'path': path,
          if (thumb) 'thumb': true,
          if (thumb) 'maxPx': maxPx,
        },
      );

  /// [SPEC §8.2 對話三層] 對話清單（左欄三類型分桶糧道）。
  Future<Map<String, dynamic>?> sendConversationList() =>
      _requestVaultResponse(
        DesktopBridgeGatewayMessageType.conversationList,
        const {},
      );

  /// [SPEC §8.2] 單一對話歷史。
  Future<Map<String, dynamic>?> sendConversationHistory(
    String conversationId, {
    int limit = 200,
  }) =>
      _requestVaultResponse(
        DesktopBridgeGatewayMessageType.conversationHistory,
        {'conversationId': conversationId, 'limit': limit},
      );

  /// [SPEC §8.6 2026-11-14] 軟刪除對話。
  Future<bool> sendConversationDelete(String conversationId) async {
    if (_socket == null || !isConnected) return false;

    final id = 'delete-${DateTime.now().millisecondsSinceEpoch}';
    _socket!.add(jsonEncode(
      DesktopBridgeGatewayRequest(
        id: id,
        type: DesktopBridgeGatewayMessageType.conversationDelete,
        payload: {'conversationId': conversationId},
      ).toJson(),
    ));

    // 同步回應會在 _onMessage 處理
    try {
      final res = await _requestVaultResponse(
        DesktopBridgeGatewayMessageType.conversationDelete,
        {'conversationId': conversationId},
      );
      return res?['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// [SPEC §8.2] 手機 → 桌面：發送訊息到對話。
  /// payload: {conversationId, role, content}
  Future<Map<String, dynamic>?> sendConversationAppend({
    required String conversationId,
    required String role,
    required String content,
  }) =>
      _requestVaultResponse(
        DesktopBridgeGatewayMessageType.conversationAppend,
        {
          'conversationId': conversationId,
          'role': role,
          'content': content,
        },
      );

  /// [SPEC §8.3 2026-11-14] 手機任務面板：列出排程任務
  Future<Map<String, dynamic>?> sendTaskList() =>
      _requestVaultResponse(
        DesktopBridgeGatewayMessageType.taskList,
        const {},
      );

  /// 主動斷線
  void disconnect() {
    _autoReconnect = false;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _socketSub?.cancel();
    _socket?.close();
    _socket = null;
    _setState(BridgeConnectionState.disconnected);
  }

  void _onDisconnect(String reason) {
    _heartbeatTimer?.cancel();
    _socket = null;
    _socketSub = null;

    if (_autoReconnect) {
      _setState(BridgeConnectionState.disconnected, message: reason);
      // [11-17 輪替斷點] _altHosts 只在 bootstrap 設過——App 不重啟就永遠空清單，
      // 30 次重連全打同一個 LAN IP（Blue 4G 實測）。每次斷線從已配對桌面重新載入。
      _reloadAltHostsFromStore();
      _scheduleReconnect();
    } else {
      _setState(BridgeConnectionState.disconnected, message: reason);
    }
  }

  void _scheduleReconnect() {
    if (!_autoReconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _setError('已達最大重連次數（$_maxReconnectAttempts），請手動重連');
      return;
    }

    _reconnectAttempts++;
    // [11-16 輪替] 2s/4s/4s... 封頂——多候選輪替要快（v6 在後面排隊）
    final delay = Duration(seconds: _reconnectAttempts == 1 ? 2 : 4);
    debugPrint('[MobileBridge] ${delay.inSeconds}s 後重連（第 $_reconnectAttempts 次）');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_autoReconnect && _host != null) {
        _doConnect();
      }
    });
  }

  // [11-16 出門直連] 候選位址（含 IPv6）——host 連不上時輪替。
  List<String> _altHosts = [];
  int _altIndex = 0;

  // [2026-11-20 sticky 端點直攻] 本輪重連是否已打過 sticky（一輪一發，
  // 失敗即退回輪替，不重複直攻）。每次新連線週期（connect/reconnectWithToken）重設。
  bool _stickyTried = false;

  // [2026-11-20 sticky 端點直攻] reconnectWithToken 路標記「這一發是直攻」——
  // bootstrap 逐 host 呼叫時 attempts=0，靠此旗標讓 _doConnect 認得第一發。
  bool _stickyPreferred = false;

  /// [11-17] 斷線時從 PairedDesktopStore 重新載入候選（含當下最新的 v6）。
  Future<void> _reloadAltHostsFromStore() async {
    try {
      final desktops = await PairedDesktopStore.getAll();
      if (desktops.isEmpty) return;
      final d = desktops.reduce((a, b) => a.pairedAt.isAfter(b.pairedAt) ? a : b);
      if (d.altHosts.isNotEmpty) _altHosts = d.altHosts;
    } catch (_) {}
  }

  /// 設定候選位址（配對/重連時由上層帶入）。每次連線失敗換下一個。
  void setAltHosts(List<String> alts) {
    _altHosts = alts;
    _altIndex = 0;
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_socket != null && _socket!.readyState == WebSocket.open) {
        // 發一個 runtimeSnapshot 當 heartbeat
        requestRuntimeSnapshot();
      }
    });
  }

  void _setState(BridgeConnectionState state, {String? message}) {
    _state = state;
    if (message != null) _lastError = message;
    debugPrint('[MobileBridge] state=$state, msg=$message');
    notifyListeners();
  }

  void _setError(String error) {
    _lastError = error;
    _setState(BridgeConnectionState.error, message: error);
  }

  /// 解析 QR payload: bridge://pair?host=192.168.1.5&port=8787&code=BRIDGE-123456
  static ({String host, int port, String code})? parseQrPayload(String payload) {
    if (!payload.startsWith('bridge://pair?')) return null;
    final query = payload.substring('bridge://pair?'.length);
    final params = <String, String>{};
    for (final pair in query.split('&')) {
      final kv = pair.split('=');
      if (kv.length == 2) params[kv[0]] = kv[1];
    }
    var host = params['host'] ?? '';
    final port = int.tryParse(params['port'] ?? '');
    final code = params['code'];
    // [11-16 v6] host 可能是 [v6] 包裹格式——還原成裸 v6（URI 用）
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    if (host.isEmpty || port == null || code == null) return null;
    return (host: host, port: port, code: code);
  }
}
