import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'desktop_bridge_gateway_protocol.dart';
import 'desktop_bridge_pairing_contract.dart';
import 'mobile/mobile_device_token_store.dart' show DeviceTokenService;
import 'mobile/mobile_task_whitelist.dart';
import 'vector_db/asset_index_service.dart';
import 'vector_db/hybrid_search_service.dart';
import 'conversation_store.dart';
import 'file_tag_store.dart';
import 'dart:typed_data';

import 'package:image/image.dart' as imglib;
import 'vector_db/asset_sandbox.dart';
import 'vector_db/vector_sketch_service.dart';
import '../models/conversation.dart';
import '../models/schedule_card.dart' show ScheduleWarmth;
import 'schedule_registry.dart' show ScheduleRegistry;

typedef DesktopBridgeRuntimePayloadProvider = Map<String, dynamic> Function();
typedef DesktopBridgeGatewayLifecycleListener = void Function();
typedef DesktopBridgeGatewayRequestListener =
    void Function(DesktopBridgeGatewayRequest request);

class DesktopBridgeLocalGatewayConfig {
  final String host;
  final int port;
  final String path;

  const DesktopBridgeLocalGatewayConfig({
    this.host = '0.0.0.0', // Sprint 15a: 綁 0.0.0.0 讓手機可以從 LAN 連入
    this.port = 8790,
    this.path = '/bridge',
  });

  Uri endpointFor(int boundPort) {
    return Uri(scheme: 'ws', host: host, port: boundPort, path: path);
  }
}

/// 已連線的 WebSocket client（手機端）。
///
/// Sprint 19a: Gateway 需要追蹤已連線的 socket 才能主動 push 訊息。
/// 每個 socket 代表一台已配對的手機。
class _ConnectedClient {
  final WebSocket socket;
  final DateTime connectedAt;

  _ConnectedClient(this.socket, this.connectedAt);

  /// 發送 push 訊息。如果 socket 已關閉則安全跳過。
  void sendPush(DesktopBridgeGatewayPush push) {
    try {
      if (socket.readyState == WebSocket.open) {
        socket.add(jsonEncode(push.toJson()));
      }
    } catch (_) {
      // socket 已關閉，安全跳過
    }
  }
}

/// Gateway 執行 handle。持有 HttpServer 和已連線 client 列表。
///
/// Sprint 19a 擴充：
/// - [pushToAll] — 向所有已連線手機 push 訊息
/// - [pushMessage] — 向特定 client push（透過 BridgePushMessage 介面）
class DesktopBridgeLocalGatewayHandle {
  final HttpServer _server;
  final Uri endpoint;

  /// 已連線的 client 列表。push 訊息時遍歷這個列表。
  final List<_ConnectedClient> _clients = [];

  DesktopBridgeLocalGatewayHandle._({
    required HttpServer server,
    required this.endpoint,
  }) : _server = server;
  int get port => _server.port;

  /// 目前已連線的 client 數量
  int get clientCount => _clients.length;

  /// 向所有已連線手機推播訊息。
  ///
  /// 用於 task 進度更新、任務完成通知等。
  void pushToAll(DesktopBridgeGatewayPush push) {
    for (final client in _clients) {
      client.sendPush(push);
    }
  }

  /// [小隊動態推播 2026-11-17] 向所有已連線手機推播小隊動態變動。
  ///
  /// [event] 僅限 'spawned'（成員開工）或 'reported'（成員回報）。
  /// 手機收到 squadChanged push 後重抓對話清單（小隊節點出現在樹上）。
  /// 機制同 vaultChanged：走 [pushToAll] 廣播全部連線。
  void pushSquadChanged({
    required String parentId,
    required String event,
    required String squadId,
  }) {
    assert(event == 'spawned' || event == 'reported',
        'squadChanged event 僅限 spawned/reported，收到 $event');
    pushToAll(DesktopBridgeGatewayPush(
      type: DesktopBridgeGatewayMessageType.squadChanged,
      payload: {
        'parentId': parentId,
        'event': event,
        'squadId': squadId,
        'at': DateTime.now().toIso8601String(),
      },
    ));
  }

  /// 向第一個已連線手機推播（v1 只支援單手機）。
  /// [2026-11-14 Blue 報案「拍照逾時」] _clients 可能含殭屍/未過閘連線
  /// （App 重開後舊 TCP 殘留）——first 是黑洞時推播全滅。修：廣播全部
  /// client，誰先回 retinaResponse 誰贏（_handleRetinaResponse 寫檔冪等）。
  void pushToFirst(DesktopBridgeGatewayPush push) {
    for (final client in List<_ConnectedClient>.from(_clients)) {
      try {
        client.sendPush(push);
      } catch (_) {
        _removeClient(client.socket);
      }
    }
  }

  /// 內部：新增已連線 client
  void _addClient(WebSocket socket) {
    _clients.add(_ConnectedClient(socket, DateTime.now()));
  }

  /// 內部：移除已斷線 client
  void _removeClient(WebSocket socket) {
    _clients.removeWhere((c) => c.socket == socket);
  }

  Future<void> close() => _server.close(force: true);
}

/// 連線層配對閘門——WebSocket 升級後、驗碼前擋下一切請求。
/// [小葵 2026-09-24 開源安全域] 未配對的 socket 不能跳過 hello 直送 taskRun。
/// [S1 2026-11-08 token 擴充] hello 可走兩條路：
///   ① 首次配對：payload 帶 pairingCode
///   ② 重連：payload 帶 deviceToken（長期 token，主機端 DeviceTokenService 驗證）
class _PairingGate {
  final String _expectedCode;
  final DeviceTokenService? _tokenService;
  bool admitted = false;

  _PairingGate(this._expectedCode, [this._tokenService]);

  /// 回 true 表示這則訊息是帶正確配對碼（或有效 token）的 hello（通過閘門）。
  bool tryAdmit(Object? raw) {
    if (admitted) return true;
    if (raw is! String) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      final typeName = decoded['type'];
      if (typeName != 'hello') return false;
      final payload = decoded['payload'];
      if (payload is! Map) return false;
      if (payload['pairingCode'] == _expectedCode) {
        admitted = true;
        return true;
      }
      // [S1] token 重連路：非同步驗證由呼叫端在 admit 後補做
      // （tryAdmit 保持同步——token 存在即先過閘，無效 token 在 hello
      //  回應階段拒絕並斷線，不留未授權連線）
      if (_tokenService != null && payload['deviceToken'] is String) {
        admitted = true;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

/// 拍板喚醒登記簿。[S1 2026-10-31 補鏈]
///
/// 任務進入 awaitingConfirmation 時呼叫 [suspend]，取得 [SuspendedConfirmation]；
/// 任務內 `await suspender.future` 暫停。Gateway 收到 confirmationRespond 時呼叫
/// [resume] 喚醒該任務（approve=true 繼續 / false 終止）。
/// 超時（未拍板）由呼叫端以 [SuspendedConfirmation.timeout] 自行處理。
class ConfirmationRegistry {
  final _suspended = <String, SuspendedConfirmation>{};

  /// 暫停任務並登記喚醒器。同一 taskId 重複登記會覆蓋（後者生效）。
  SuspendedConfirmation suspend(String taskId) {
    final previous = _suspended[taskId];
    if (previous != null && !previous.isCompleted) {
      previous.resolve(false, timeout: false); // 舊的未拍板等待視同否決
    }
    final confirmation = SuspendedConfirmation._(taskId);
    _suspended[taskId] = confirmation;
    return confirmation;
  }

  /// 手機拍板回覆。回 true 代表找到暫停中的任務並已喚醒。
  bool resume(String taskId, {required bool approve}) {
    final confirmation = _suspended.remove(taskId);
    if (confirmation == null || confirmation.isCompleted) return false;
    confirmation.resolve(approve, timeout: false);
    return true;
  }

  /// 清場（gateway 關閉時）：所有暫停任務視同否決喚醒。
  void close() {
    for (final c in _suspended.values) {
      if (!c.isCompleted) c.resolve(false, timeout: false);
    }
    _suspended.clear();
  }
}

/// 單一暫停任務的喚醒器。
class SuspendedConfirmation {
  final String taskId;
  final Completer<bool> _completer = Completer<bool>();
  Timer? _timeoutTimer;

  SuspendedConfirmation._(this.taskId);

  /// 任務端 await 此 future：true=批准繼續、false=否決/超時/被覆蓋。
  Future<bool> get future => _completer.future;

  bool get isCompleted => _completer.isCompleted;

  /// 設定拍板超時——逾時未回覆視同否決（寧可停下不等假的批准）。
  void setTimeout(Duration duration) {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(duration, () {
      if (!isCompleted) resolve(false, timeout: true);
    });
  }

  void resolve(bool approve, {required bool timeout}) {
    _timeoutTimer?.cancel();
    if (!_completer.isCompleted) {
      _completer.complete(approve);
    }
  }
}

/// 桌面端 WebSocket Gateway Server。
///
/// Sprint 14: 基礎同步 request-response（hello / runtimeSnapshot / capabilityList）
/// Sprint 19a: 擴充長任務支援
/// - 收到 `taskRun` → 委派給 [GatewayTaskHandler] 非同步執行
/// - 收到 `taskCancel` → 委派給 [GatewayTaskHandler] 取消
/// - 任務進度/完成透過 push 推播回手機
/// - `taskProgress` / `taskComplete` / `taskAwaitingConfirmation` 是 push-only，
///   手機不應發送，收到時回 error
class DesktopBridgeLocalGateway {
  // [11-15] trash 清單快取（見 _handleConversationList）
  static List<Map<String, dynamic>>? _trashCache;
  static String _trashCacheStamp = '';
  final DesktopBridgeGatewayProtocol protocol;

  /// 長任務處理器（S19b BrowserAutomationService / S19c TaskQueue 注入）。
  /// null 時 taskRun/taskCancel 回 error。
  final GatewayTaskHandler? taskHandler;

  /// [S1] 拍板喚醒登記簿——confirmationRespond 的落點。
  final ConfirmationRegistry confirmations = ConfirmationRegistry();

  /// [S1] 裝置 token 服務（可選注入）——配對成功發 token、重連驗 token。
  final DeviceTokenService? tokenService;

  /// [S2 白名單轉發層] 手機通道 taskType 白名單（SPEC L105）。
  ///
  /// - null → 不過濾（本機 Agent 行為，回溯相容）
  /// - 非 null → taskRun 先過白名單：未開放的 taskType 回
  ///   「此指令僅限 Agent 本機使用」，已開放的 in-process 轉發 taskHandler
  final MobileTaskWhitelist? mobileTaskWhitelist;

  DesktopBridgeLocalGateway({
    this.protocol = const DesktopBridgeGatewayProtocol(),
    this.taskHandler,
    this.tokenService,
    this.mobileTaskWhitelist,
  });

  Future<DesktopBridgeLocalGatewayHandle> start({
    required DesktopBridgePairingContract pairingContract,
    required DesktopBridgeRuntimePayloadProvider runtimePayloadProvider,
    DesktopBridgeLocalGatewayConfig config =
        const DesktopBridgeLocalGatewayConfig(),
    DesktopBridgeGatewayLifecycleListener? onClientConnected,
    DesktopBridgeGatewayLifecycleListener? onClientDisconnected,
    DesktopBridgeGatewayRequestListener? onRequest,
  }) async {
    // [11-16 IPv6 直連] 0.0.0.0 只聽 IPv4。改 anyIPv6 = dual-stack（v4+v6 同時聽），
    // 中華電信 CGNAT 環境下手機走 IPv6 直連公網（無 NAT 無埠轉發）。
    final server = await HttpServer.bind(
      config.host == '0.0.0.0' ? InternetAddress.anyIPv6 : InternetAddress(config.host),
      config.port,
      v6Only: false, // dual-stack：IPv4 相容不破壞
    );

    final handle = DesktopBridgeLocalGatewayHandle._(
      server: server,
      endpoint: config.endpointFor(server.port),
    );

    server.listen(
      (request) => _handleRequest(
        request,
        config: config,
        pairingContract: pairingContract,
        runtimePayloadProvider: runtimePayloadProvider,
        onClientConnected: onClientConnected,
        onClientDisconnected: onClientDisconnected,
        onRequest: onRequest,
        handle: handle,
      ),
    );

    return handle;
  }

  Future<void> _handleRequest(
    HttpRequest request, {
    required DesktopBridgeLocalGatewayConfig config,
    required DesktopBridgePairingContract pairingContract,
    required DesktopBridgeRuntimePayloadProvider runtimePayloadProvider,
    DesktopBridgeGatewayLifecycleListener? onClientConnected,
    DesktopBridgeGatewayLifecycleListener? onClientDisconnected,
    DesktopBridgeGatewayRequestListener? onRequest,
    required DesktopBridgeLocalGatewayHandle handle,
  }) async {
    if (request.uri.path != config.path) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.upgradeRequired;
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    // [小葵 2026-09-24 開源安全域] 連線層配對閘門：
    // 舊版未配對 socket 可跳過 hello 直送 taskRun/runtimeSnapshot。
    // 現在：升級後第一訊息必須是帶正確 pairingCode 的 hello，5 秒內未過閘即斷線。
    // [S1] 閘門另接受 deviceToken（重連路；有效性在 hello 回應階段驗）。
    final gate = _PairingGate(pairingContract.pairingCode, tokenService);
    onClientConnected?.call();

    try {
      await for (final raw in socket) {
        if (!gate.admitted) {
          if (!gate.tryAdmit(raw)) {
            socket.add(jsonEncode(
              DesktopBridgeGatewayResponse(
                requestId: 'unknown',
                type: DesktopBridgeGatewayMessageType.error,
                ok: false,
                error: 'Pairing required: send hello with pairingCode first.',
              ).toJson(),
            ));
            await socket.close(); // 未配對即斷線——不讓未授權連線存在
            break;
          }
          // 過閘——此時才把 client 納入 push 廣播清單
          handle._addClient(socket);
        }
        final response = await _responseFor(
          raw,
          pairingContract: pairingContract,
          runtimePayloadProvider: runtimePayloadProvider,
          onRequest: onRequest,
          handle: handle,
          socket: socket,
        );
        if (response != null) {
          socket.add(jsonEncode(response.toJson()));
        }
      }
    } finally {
      handle._removeClient(socket);
      onClientDisconnected?.call();
    }
  }

  /// 處理收到的訊息。
  ///
  /// 回傳 [DesktopBridgeGatewayResponse] 表示需要回應手機（同步 request-response）。
  /// 回傳 null 表示不需要回應（push-only 或已透過 push 機制回應）。
  Future<DesktopBridgeGatewayResponse?> _responseFor(
    Object? raw, {
    required DesktopBridgePairingContract pairingContract,
    required DesktopBridgeRuntimePayloadProvider runtimePayloadProvider,
    DesktopBridgeGatewayRequestListener? onRequest,
    required DesktopBridgeLocalGatewayHandle handle,
    required WebSocket socket,
  }) async {
    try {
      final decoded = raw is String ? jsonDecode(raw) : null;
      if (decoded is! Map<String, dynamic>) {
        return const DesktopBridgeGatewayResponse(
          requestId: 'unknown',
          type: DesktopBridgeGatewayMessageType.error,
          ok: false,
          error: 'Gateway request must be a JSON object.',
        );
      }
      final request = DesktopBridgeGatewayRequest.fromJson(decoded);
      onRequest?.call(request);

      // --- Task 請求：由 Gateway 直接處理（需要 push 機制）---
      if (request.type == DesktopBridgeGatewayMessageType.taskRun) {
        return _handleTaskRun(request, handle);
      }
      if (request.type == DesktopBridgeGatewayMessageType.taskCancel) {
        return _handleTaskCancel(request);
      }
      // [S1] 拍板回覆：喚醒暫停任務（approve 繼續 / reject 終止）
      if (request.type == DesktopBridgeGatewayMessageType.confirmationRespond) {
        return _handleConfirmationRespond(request);
      }
      // [S1] hello token 擴充：配對成功發 token；重連驗 token
      if (request.type == DesktopBridgeGatewayMessageType.hello) {
        return await _handleHelloToken(request, pairingContract);
      }
      // [SPEC §8.5 2026-11-12] vault 請求：列檔案/讀檔案（手機向量庫 tab）
      if (request.type == DesktopBridgeGatewayMessageType.retinaResponse) {
        return _handleRetinaResponse(request);
      }
      // [11-15 Blue 報案「Gateway 錯誤: Conversation requests...」] 病根：
      // 這三個 handler 回傳值沒 return——呼叫完掉到 protocol.handleRequest
      // 被退件。修：補 return（conversationAppend 本來就有）。
      if (request.type == DesktopBridgeGatewayMessageType.conversationList) {
        return _handleConversationList(request);
      }
      if (request.type == DesktopBridgeGatewayMessageType.conversationHistory) {
        return _handleConversationHistory(request);
      }
      if (request.type == DesktopBridgeGatewayMessageType.conversationDelete) {
        return _handleConversationDelete(request);
      }
      if (request.type == DesktopBridgeGatewayMessageType.conversationAppend) {
        return _handleConversationAppend(request);
      }
      if (request.type == DesktopBridgeGatewayMessageType.vaultSearch) {
        return _handleVaultSearch(request);
      }
      if (request.type == DesktopBridgeGatewayMessageType.vaultTags) {
        return _handleVaultTags(request);
      }
      if (request.type == DesktopBridgeGatewayMessageType.vaultList) {
        return await _handleVaultList(request);
      }
      if (request.type == DesktopBridgeGatewayMessageType.vaultFile) {
        return await _handleVaultFile(request);
      }
      // [SPEC §8.3 2026-11-14] 手機任務面板
      if (request.type == DesktopBridgeGatewayMessageType.taskList) {
        return _handleTaskList(request);
      }

      // --- 同步請求：委派給 protocol ---
      return protocol.handleRequest(
        request: request,
        pairingContract: pairingContract,
        runtimePayload: runtimePayloadProvider(),
      );
    } on Object catch (error) {
      return DesktopBridgeGatewayResponse(
        requestId: 'unknown',
        type: DesktopBridgeGatewayMessageType.error,
        ok: false,
        error: 'Gateway request parse failed: $error',
      );
    }
  }

  /// 處理 taskRun 請求。
  ///
  /// 立即回傳 taskId（成功啟動）或 error（啟動失敗），
  /// 任務在背景執行，進度/結果透過 push 推播。
  DesktopBridgeGatewayResponse _handleTaskRun(
    DesktopBridgeGatewayRequest request,
    DesktopBridgeLocalGatewayHandle handle,
  ) {
    final handler = taskHandler;
    if (handler == null) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.error,
        ok: false,
        error: 'No task handler registered. Browser automation not available.',
      );
    }

    final taskType = request.payload['taskType'] as String? ?? 'unknown';

    // [S2 白名單轉發層] 手機僅開放白名單子集（SPEC L105）：
    // 未開放的 taskType 一律固定文案拒絕——不洩漏白名單、不區分不存在與不開放。
    final whitelist = mobileTaskWhitelist;
    if (whitelist != null) {
      final verdict = whitelist.check(taskType);
      if (!verdict.allowed) {
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.error,
          ok: false,
          error: verdict.denyMessage ?? MobileTaskWhitelist.kDenyMessage,
        );
      }
    }

    final taskPayload = request.payload['payload'];
    final payload = taskPayload is Map<String, dynamic>
        ? taskPayload
        : <String, dynamic>{};

    try {
      // 先宣告 taskId 變數，讓 callback 可以引用
      late String taskId;
      taskId = handler.startTask(
        taskType: taskType,
        payload: payload,
        onProgress: (progress, message) {
          handle.pushToFirst(DesktopBridgeGatewayPush(
            type: DesktopBridgeGatewayMessageType.taskProgress,
            payload: {
              'taskId': taskId,
              'progress': progress,
              'message': message,
              'timestamp': DateTime.now().toIso8601String(),
            },
          ));
        },
        onComplete: (success, result, error) {
          handle.pushToFirst(DesktopBridgeGatewayPush(
            type: DesktopBridgeGatewayMessageType.taskComplete,
            payload: {
              'taskId': taskId,
              'success': success,
              'result': result,
              if (error != null) 'error': error,
              'timestamp': DateTime.now().toIso8601String(),
            },
          ));
        },
        onAwaitingConfirmation: (reason, context) {
          handle.pushToFirst(DesktopBridgeGatewayPush(
            type: DesktopBridgeGatewayMessageType.taskAwaitingConfirmation,
            payload: {
              'taskId': taskId,
              'reason': reason,
              'context': context,
              'timestamp': DateTime.now().toIso8601String(),
            },
          ));
        },
      );

      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.taskRun,
        ok: true,
        payload: {
          'taskId': taskId,
          'taskType': taskType,
          'status': 'started',
        },
      );
    } catch (e) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.error,
        ok: false,
        error: 'Failed to start task: $e',
      );
    }
  }

  /// [S1] hello token 擴充——兩條路：
  ///
  /// ① hello 帶 pairingCode（首次配對）：驗碼成功 → 簽發裝置 token 附在回應
  /// ② hello 帶 deviceToken（重連）：驗 token → ok（無效 → ok:false + 斷線由上層）
  /// tokenService 未注入時退回純 protocol 行為（向後相容）。
  Future<DesktopBridgeGatewayResponse> _handleHelloToken(
    DesktopBridgeGatewayRequest request,
    DesktopBridgePairingContract pairingContract,
  ) async {
    final svc = tokenService;
    if (svc == null) {
      return protocol.handleRequest(
        request: request,
        pairingContract: pairingContract,
        runtimePayload: const {},
      );
    }

    final presentedCode = request.payload['pairingCode'] as String?;
    final deviceToken = request.payload['deviceToken'] as String?;

    // ② token 重連路
    if (presentedCode == null && deviceToken != null) {
      final valid = await svc.validate(deviceToken);
      if (!valid) {
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.hello,
          ok: false,
          error: 'Device token invalid or revoked. Please re-pair with QR code.',
        );
      }
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.hello,
        ok: true,
        payload: {
          'schema': 'bridge.desktop.gateway.hello.v1',
          'desktopName': pairingContract.desktopName,
          'reconnected': true,
        },
      );
    }

    // ① 配對碼路：protocol 驗碼（錯碼由 protocol 回 error）
    final response = protocol.handleRequest(
      request: request,
      pairingContract: pairingContract,
      runtimePayload: const {},
    );
    if (response.ok && presentedCode != null) {
      final token = await svc.issueForPairing(
        presentedCode,
        pairingContract.pairingCode,
        // [2026-11-11 一機一證] 手機穩定識別碼——同機重配對撤舊簽新
        deviceId: request.payload['deviceId'] as String?,
      );
      if (token != null) {
        return DesktopBridgeGatewayResponse(
          requestId: response.requestId,
          type: response.type,
          ok: true,
          payload: {...response.payload, 'deviceToken': token},
        );
      }
    }
    return response;
  }

  /// [S1] 處理 confirmationRespond——手機拍板回覆。
  ///
  /// payload: {taskId, approve: bool}
  /// 喚醒對應的暫停任務；找不到（已超時/已完成/未知 taskId）回 not_found。
  DesktopBridgeGatewayResponse _handleConfirmationRespond(
    DesktopBridgeGatewayRequest request,
  ) {
    final taskId = request.payload['taskId'] as String? ?? '';
    final approve = request.payload['approve'] == true;
    final resumed = confirmations.resume(taskId, approve: approve);

    return DesktopBridgeGatewayResponse(
      requestId: request.id,
      type: DesktopBridgeGatewayMessageType.confirmationRespond,
      ok: resumed,
      payload: {
        'taskId': taskId,
        'approve': approve,
        'status': resumed ? 'resumed' : 'not_found',
      },
      error: resumed ? null : 'No suspended task awaiting confirmation for this taskId.',
    );
  }

  /// 處理 taskCancel 請求。
  DesktopBridgeGatewayResponse _handleTaskCancel(
    DesktopBridgeGatewayRequest request,
  ) {
    final handler = taskHandler;
    if (handler == null) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.error,
        ok: false,
        error: 'No task handler registered.',
      );
    }

    final taskId = request.payload['taskId'] as String? ?? '';

    final cancelled = handler.cancelTask(taskId);

    return DesktopBridgeGatewayResponse(
      requestId: request.id,
      type: DesktopBridgeGatewayMessageType.taskCancel,
      ok: cancelled,
      payload: {
        'taskId': taskId,
        'status': cancelled ? 'cancelled' : 'not_found',
      },
      error: cancelled ? null : 'Task not found or already completed.',
    );
  }

  // ── [SPEC §8.5 2026-11-12] 手機向量庫 tab：列檔案/讀檔案 ──

  /// [SPEC §8.2 2026-11-13 對話三層] 對話清單——手機左欄三類型
  /// （💬一般/⏰排程/📁專案）分桶的糧道。回每則 conversation 的元資料
  /// （不帶 messages——省流量；歷史另打 conversationHistory）。
  Future<DesktopBridgeGatewayResponse> _handleConversationList(
      DesktopBridgeGatewayRequest request) async {
    try {
      final all = await ConversationStore.getAll();
      // [Blue 11-14 報案] 回收桶——trash/ 內的軟刪除對話（只讀預覽）
      // [11-17] getApplicationSupportDirectory 在測試環境（無 plugin）會丟——
      // 回收桶是附加價值，失敗不得拖垮主清單。
      Directory trashDir;
      try {
        trashDir = Directory(
            '${(await getApplicationSupportDirectory()).path}/bridge_state/trash');
      } catch (_) {
        trashDir = Directory('/nonexistent_trash_fallback');
      }
      final trashItems = <Map<String, dynamic>>[];
      // [11-15 Blue 報案「載入久到像壞掉」] trash 186 檔同步掃描是拖累——
      // 快取：目錄 mtime 沒變（沒新刪除）直接回快取，掃描只在第一次/有變動時跑。
      final dirStat = trashDir.existsSync()
          ? trashDir.statSync().modified.toIso8601String()
          : '';
      if (dirStat == _trashCacheStamp && _trashCache != null) {
        // 用快取（下方 payload 組裝直接用 _trashCache）
      } else if (await trashDir.exists()) {
        await for (final f in trashDir.list()) {
          if (f is! File || !f.path.endsWith('.json')) continue;
          try {
            final c = jsonDecode(await f.readAsString());
            if (c is Map<String, dynamic>) {
              final msgs = (c['messages'] as List? ?? []);
              trashItems.add({
                'id': c['id'] ?? f.uri.pathSegments.last,
                'title': c['title'] ?? '未命名',
                'type': c['type'] ?? 'general',
                'deletedAt': f.lastModifiedSync().toIso8601String(),
                'messageCount': msgs.length,
              });
            }
          } catch (_) {}
        }
        trashItems.sort((a, b) =>
            (b['deletedAt'] as String).compareTo(a['deletedAt'] as String));
        _trashCache = trashItems;
        _trashCacheStamp = dirStat;
      }
      final items = all
          .map((c) => {
                'id': c.id,
                'title': c.title,
                'type': c.type.label,
                'companionId': c.companionId,
                'projectDoorId': c.projectDoorId,
                'taskBinding': c.taskBinding,
                // [SPEC §9.2 對話頁v2] 子對話樹：null=頂層；非 null=縮排於母對話下
                'parentConversationId': c.parentConversationId,
                'canvasId': c.canvasId,
                'updatedAt': c.updatedAt.toIso8601String(),
                'messageCount': c.messages.length,
                'lastPreview': c.messages.isNotEmpty
                    ? c.messages.last.content.substring(0,
                        c.messages.last.content.length > 60
                            ? 60
                            : c.messages.last.content.length)
                    : '',
              })
          .toList();
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.conversationList,
        ok: true,
        payload: {
          'total': items.length,
          'conversations': items,
          'trash': (_trashCache ?? trashItems).take(50).toList(),
        },
      );
    } catch (e) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.conversationList,
        ok: false,
        error: 'conversationList failed: $e',
      );
    }
  }

  /// [SPEC §8.2] 單一對話歷史（訊息不含 mediaAssets bytes——路徑即可）。
  Future<DesktopBridgeGatewayResponse> _handleConversationHistory(
      DesktopBridgeGatewayRequest request) async {
    try {
      final id = request.payload['conversationId'] as String? ?? '';
      final limit =
          ((request.payload['limit'] as num?)?.toInt() ?? 200).clamp(1, 1000);
      if (id.isEmpty) {
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.conversationHistory,
          ok: false,
          error: 'conversationId required',
        );
      }
      final all = await ConversationStore.getAll();
      final conv = all.where((c) => c.id == id).firstOrNull;
      if (conv == null) {
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.conversationHistory,
          ok: false,
          error: 'conversation not found',
        );
      }
      final msgs = conv.messages.length > limit
          ? conv.messages.sublist(conv.messages.length - limit)
          : conv.messages;
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.conversationHistory,
        ok: true,
        payload: {
          'id': conv.id,
          'title': conv.title,
          'parentConversationId': conv.parentConversationId,
          'taskBinding': conv.taskBinding,
          'messages': msgs
              .map((m) => {
                    'id': m.id,
                    'role': m.role,
                    'speakerId': m.speakerId,
                    'content': m.content,
                    'timestamp': m.timestamp.toIso8601String(),
                  })
              .toList(),
        },
      );
    } catch (e) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.conversationHistory,
        ok: false,
        error: 'conversationHistory failed: $e',
      );
    }
  }

  /// [SPEC §8.6 2026-11-14] 軟刪除對話。
  /// payload: {conversationId}
  Future<DesktopBridgeGatewayResponse> _handleConversationDelete(
      DesktopBridgeGatewayRequest request) async {
    try {
      final convId = request.payload['conversationId'] as String? ?? '';
      if (convId.isEmpty) {
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.conversationDelete,
          ok: false,
          error: 'conversationId required.',
        );
      }
      await ConversationStore.delete(convId);
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.conversationDelete,
        ok: true,
        payload: {'deletedId': convId},
      );
    } catch (e) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.conversationDelete,
        ok: false,
        error: 'conversationDelete failed: $e',
      );
    }
  }

  /// [SPEC §8.2] 手機 → 桌面：發送訊息到對話。
  /// payload: {conversationId, role, content}
  /// role = 'user' | 'assistant'
  Future<DesktopBridgeGatewayResponse> _handleConversationAppend(
      DesktopBridgeGatewayRequest request) async {
    try {
      final convId = request.payload['conversationId'] as String? ?? '';
      final role = request.payload['role'] as String? ?? 'user';
      final content = request.payload['content'] as String? ?? '';
      
      if (convId.isEmpty) {
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.conversationAppend,
          ok: false,
          error: 'conversationId required.',
        );
      }
      if (role != 'user' && role != 'assistant') {
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.conversationAppend,
          ok: false,
          error: 'role must be "user" or "assistant".',
        );
      }
      if (content.isEmpty) {
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.conversationAppend,
          ok: false,
          error: 'content required.',
        );
      }
      
      // 找到對話並追加訊息
      final all = await ConversationStore.getAll();
      final conv = all.where((c) => c.id == convId).firstOrNull;
      if (conv == null) {
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.conversationAppend,
          ok: false,
          error: 'conversation not found.',
        );
      }
      
      // 建立新訊息
      final newMessage = Message(
        id: '${DateTime.now().millisecondsSinceEpoch}_${_messageCounter++}',
        role: role,
        content: content,
        timestamp: DateTime.now(),
        speakerId: role == 'assistant' ? conv.companionId : null,
      );
      
      // 更新對話
      final updatedConv = conv.copyWith(
        messages: [...conv.messages, newMessage],
        updatedAt: DateTime.now(),
      );
      
      await ConversationStore.save(updatedConv);
      
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.conversationAppend,
        ok: true,
        payload: {
          'conversationId': convId,
          'messageId': newMessage.id,
        },
      );
    } catch (e) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.conversationAppend,
        ok: false,
        error: 'conversationAppend failed: $e',
      );
    }
  }

  int _messageCounter = 0;

  /// [SPEC 開光手機版 2026-11-13] 手機視網膜照片落地——base64 PNG 存
  /// App Support/phone_retina/latest.png（覆蓋式快照；Blue 不在電腦前
  /// 也能由小葵從 Mac 看手機真實畫面——開光配方：渲染層視網膜）。
  Future<DesktopBridgeGatewayResponse> _handleRetinaResponse(
      DesktopBridgeGatewayRequest request) async {
    try {
      final b64 = request.payload['base64'] as String?;
      if (b64 == null || b64.isEmpty) {
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.retinaResponse,
          ok: false,
          error: 'retina capture failed (null image)',
        );
      }
      final dir = Directory(
          '${(await getApplicationSupportDirectory()).path}/phone_retina');
      await dir.create(recursive: true);
      await File('${dir.path}/latest.png').writeAsBytes(base64Decode(b64));
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.retinaResponse,
        ok: true,
        payload: {'saved': 'phone_retina/latest.png'},
      );
    } catch (e) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.retinaResponse,
        ok: false,
        error: 'retinaResponse failed: \$e',
      );
    }
  }

  /// [SPEC §8.5b 2026-11-13] vaultSearch：手機語意/全文搜尋——同桌面
  /// HybridSearchService（asset_index 表）；tag 模式走 FileTagStore。
  /// payload: {query, mode: 'fullText'|'semantic'|'tag', tag?, limit?}
  Future<DesktopBridgeGatewayResponse> _handleVaultSearch(
      DesktopBridgeGatewayRequest request) async {
    try {
      final query = (request.payload['query'] as String? ?? '').trim();
      final mode = request.payload['mode'] as String? ?? 'semantic';
      final limit =
          ((request.payload['limit'] as num?)?.toInt() ?? 40).clamp(1, 100);
      final tagName = request.payload['tag'] as String?;

      // 標籤模式：FileTagStore 直查（同桌面 VaultSearchMode.tag）
      if (mode == 'tag' && tagName != null && tagName.isNotEmpty) {
        final all = await FileTagStore().loadAll();
        final tag = all
            .where((t) => t.name == tagName.toLowerCase())
            .firstOrNull;
        if (tag == null) {
          return DesktopBridgeGatewayResponse(
            requestId: request.id,
            type: DesktopBridgeGatewayMessageType.vaultSearch,
            ok: true,
            payload: {'files': const [], 'total': 0, 'mode': mode},
          );
        }
        // 標籤路徑 → 對回 manifest 檔案摘要
        await _vaultSandbox.ensurePrefsLoaded();
        final indexService = _vaultIndex();
        await indexService.loadManifests();
        final byPath = {
          for (final mf in indexService.allFiles) mf.path: mf,
        };
        final files = <Map<String, dynamic>>[];
        for (final fp in tag.filePaths) {
          final mf = byPath[fp] ?? byPath[fp.split('/').last];
          files.add({
            'path': mf?.path ?? fp,
            'name': fp.split('/').last,
            'folder': mf?.folder ?? '',
            'size': mf?.size ?? 0,
            'kind': 'tag',
          });
        }
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.vaultSearch,
          ok: true,
          payload: {'files': files, 'total': files.length, 'mode': mode},
        );
      }

      // fullText / semantic：HybridSearchService（asset_index）
      // [Blue 令 2026-11-13] hybrid=向量搜尋（FTS+語意+智慧排序——同桌面預設）
      final searchMode = switch (mode) {
        'fullText' => SearchMode.fullText,
        'hybrid' => SearchMode.hybrid,
        _ => SearchMode.semantic,
      };
      final results = await HybridSearchService.instance
          .search(query: query, mode: searchMode, limit: limit);
      final files = results.assetHits
          .map((h) => {
                'path': h.filePath,
                'name': h.fileName,
                'title': h.title,
                'summary': h.summary,
                'kind': h.assetKind,
                'score': h.score,
              })
          .toList();
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.vaultSearch,
        ok: true,
        payload: {
          'files': files,
          'total': files.length,
          'mode': mode,
          'memoryHits': results.memoryHits.length,
        },
      );
    } catch (e) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.vaultSearch,
        ok: false,
        error: 'vaultSearch failed: $e',
      );
    }
  }

  /// [SPEC §8.5b] vaultTags：標籤清單（FileTagStore 全量——label+count）。
  Future<DesktopBridgeGatewayResponse> _handleVaultTags(
      DesktopBridgeGatewayRequest request) async {
    try {
      final all = await FileTagStore().loadAll();
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.vaultTags,
        ok: true,
        payload: {
          'tags': [
            for (final t in all)
              {'name': t.name, 'label': t.label, 'count': t.filePaths.length},
          ],
        },
      );
    } catch (e) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.vaultTags,
        ok: false,
        error: 'vaultTags failed: $e',
      );
    }
  }

  /// vaultList：列出 vault 檔案（junk 過濾同桌面牆；offset/limit 分頁）。
  /// [forWall]=true（SPEC §8.8b＋此刻頁真內容 v2）：骨牌牆輪播池——安全圖片
  /// ＋安全文字檔（≤256KB，副檔名白名單同 vaultFile）、敏感照片/文件永不入池
  /// （身分證/護照/備份碼等 heuristic）、新修改在前（圖文混排不分組，
  /// 最新=hero 候選）。每筆附 kind: image|text 讓手機端免重算。
  Future<DesktopBridgeGatewayResponse> _handleVaultList(
    DesktopBridgeGatewayRequest request,
  ) async {
    try {
      final offset = (request.payload['offset'] as num?)?.toInt() ?? 0;
      final limit = ((request.payload['limit'] as num?)?.toInt() ?? 200)
          .clamp(1, 500);
      final query =
          (request.payload['query'] as String? ?? '').trim().toLowerCase();
      final forWall = request.payload['forWall'] == true;

      await _vaultSandbox.ensurePrefsLoaded();
      final indexService = _vaultIndex();
      await indexService.loadManifests();
      var files = indexService.allFiles
          .where((mf) => !VectorSketchService.isJunkFolder(mf.path))
          .toList();
      if (forWall) {
        // [此刻頁真內容 v2] 池＝安全圖片＋安全文字檔（≤256KB，同 vaultFile
        // 白名單）；敏感資產 heuristic 一律攔（圖文同等）。
        const imgExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
        const textExts = {
          'md', 'txt', 'json', 'yaml', 'yml', 'csv', 'log', 'xml',
          'html', 'htm', 'ts', 'js', 'dart', 'py', 'sh', 'css', 'toml',
          'ini', 'conf', 'srt', 'vtt', 'back', 'bak', 'rtf',
        };
        const maxTextBytes = 256 * 1024;
        files = files.where((mf) {
          final p = mf.path.toLowerCase();
          final ext = p.split('.').last;
          if (_isSensitiveAsset(p)) return false;
          if (imgExts.contains(ext)) return true;
          return textExts.contains(ext) && mf.size <= maxTextBytes;
        }).toList();
      }
      if (query.isNotEmpty) {
        files = files
            .where((mf) =>
                mf.path.toLowerCase().contains(query) ||
                mf.folder.toLowerCase().contains(query))
            .toList();
      }
      // 新修改在前（§8.8b 最新內容優先——hero 恆給最新）
      files.sort((a, b) => b.modified.compareTo(a.modified));
      final total = files.length;
      const imgExtsForKind = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
      final page = files
          .skip(offset)
          .take(limit)
          .map((mf) {
            final j = mf.toJson();
            // kind：副檔名判斷（手機端免重算）——圖=image 其餘=text。
            j['kind'] = imgExtsForKind
                    .contains(mf.path.toLowerCase().split('.').last)
                ? 'image'
                : 'text';
            return j;
          })
          .toList();
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.vaultList,
        ok: true,
        payload: {'total': total, 'offset': offset, 'files': page},
      );
    } catch (e) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.vaultList,
        ok: false,
        error: 'vaultList failed: $e',
      );
    }
  }

  /// [SPEC §8.8] 敏感資產 heuristic——身分證件/護照/備份碼/私鑰永不入輪播牆。
  /// 寧可錯殺（誤排除幾張圖）不可放過（證件照上牆是資安事件）。
  static bool _isSensitiveAsset(String lowerPath) {
    const patterns = [
      '身分', '身份', '護照', 'passport', 'id-card', 'idcard',
      '駕照', 'driver', 'backup-code', 'backup_code', 'backupcodes',
      '私鑰', 'secret', 'seed', '密碼', 'password', 'credential',
      '健保卡', '行照', '合约', '合同掃描',
    ];
    return patterns.any(lowerPath.contains);
  }

  /// vaultFile：讀單一檔案給預覽器。
  /// 文字類回全文（≤256KB 截斷標註）；圖片類回 base64。
  /// 路徑安全：必須存在於 manifest（防任意讀）。
  Future<DesktopBridgeGatewayResponse> _handleVaultFile(
    DesktopBridgeGatewayRequest request,
  ) async {
    try {
      final path = request.payload['path'] as String? ?? '';
      if (path.isEmpty) {
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.vaultFile,
          ok: false,
          error: 'path required.',
        );
      }
      // 路徑白名單：manifest 裡才給讀（防止手機端任意路徑讀檔）
      await _vaultSandbox.ensurePrefsLoaded();
      final indexService = _vaultIndex();
      await indexService.loadManifests();
      final entry = indexService.allFiles
          .cast<ManifestFile?>()
          .firstWhere((mf) => mf!.path == path, orElse: () => null);
      if (entry == null) {
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.vaultFile,
          ok: false,
          error: 'File not in vault manifest.',
        );
      }
      // [2026-11-13 三修「File missing on disk」] manifest 每筆自帶絕對資料夾
      // （entry.folder）——優先用它組絕對路徑（不再賭 rootPaths 兩域 prefs）；
      // 舊路（絕對 path／root 迭代）保留為後備。
      File? f;
      if (path.startsWith('/')) {
        f = File(path);
        if (!await f.exists()) f = null;
      }
      if (f == null && entry.folder.isNotEmpty) {
        final cand = File('${entry.folder}/$path');
        if (await cand.exists()) f = cand;
      }
      if (f == null) {
        for (final root in _vaultSandbox.rootPaths) {
          final cand = File('$root/$path');
          if (await cand.exists()) {
            f = cand;
            break;
          }
        }
      }
      if (f == null) {
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.vaultFile,
          ok: false,
          error: 'File missing on disk (offline drive?). path=$path',
        );
      }
      final ext = path.toLowerCase().split('.').last;
      const imgExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
      if (imgExts.contains(ext)) {
        final bytes = await f.readAsBytes();
        // [2026-11-12 Blue 令：縮圖必要] thumb 模式——服務端縮圖（長邊 maxPx、
        // JPEG q85）再回傳。骨牌牆/清單縮圖走這條；預覽器全圖走原圖。
        final wantThumb = request.payload['thumb'] == true;
        final maxPx = (request.payload['maxPx'] as num?)?.toInt() ?? 720;
        if (wantThumb) {
          try {
            final thumb = await _resizeToJpeg(bytes, maxPx);
            if (thumb != null) {
              return DesktopBridgeGatewayResponse(
                requestId: request.id,
                type: DesktopBridgeGatewayMessageType.vaultFile,
                ok: true,
                payload: {
                  'kind': 'image',
                  'mime': 'image/jpeg',
                  'base64': base64Encode(thumb),
                },
              );
            }
          } catch (_) {
            // 縮圖失敗（GIF 動畫/怪檔）→ fall through 原圖
          }
        }
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.vaultFile,
          ok: true,
          payload: {
            'kind': 'image',
            'mime': 'image/$ext',
            'base64': base64Encode(bytes),
          },
        );
      }
      const maxBytes = 256 * 1024;
      final size = await f.length();
      final bytes = await f.readAsBytes();
      // [2026-11-13 Blue 報案「中文 md/json 判二位元」] 副檔名白名單定生死——
      // 舊 heuristic（高位元組<30%）把中文 UTF-8（每字 3 高位元組）全誤殺。
      const textExts = {
        'md', 'txt', 'json', 'yaml', 'yml', 'csv', 'log', 'xml',
        'html', 'htm', 'ts', 'js', 'dart', 'py', 'sh', 'css', 'toml',
        'ini', 'conf', 'srt', 'vtt',
        // [2026-11-13 Blue 報案] 雙副檔名與備份檔：md.back/bak 也算文字；
        // rtf 雖含控制碼但主體可讀——交文字渲染
        'back', 'bak', 'rtf',
      };
      final hasExt = path.contains('.');
      final textExt = hasExt ? path.toLowerCase().split('.').last : '';
      final isText = textExts.contains(textExt) ||
          (!hasExt && _looksTextual(bytes.take(4096).toList()));
      if (!isText) {
        // [2026-11-13 Blue 令：開不了的也要能交給系統] binary 帶原始 bytes
        // （≤20MB）讓手機端可存檔→ShareSheet 交給使用者選 App 開啟；
        // 超大檔誠實降級為僅摘要（寧紅字不假成功）。
        const maxShareBytes = 20 * 1024 * 1024;
        final shareable = size <= maxShareBytes;
        return DesktopBridgeGatewayResponse(
          requestId: request.id,
          type: DesktopBridgeGatewayMessageType.vaultFile,
          ok: true,
          payload: {
            'kind': 'binary',
            'size': size,
            'name': path.split('/').last,
            if (shareable) 'base64': base64Encode(bytes),
            'shareable': shareable,
          },
        );
      }
      final truncated = size > maxBytes;
      final text = utf8.decode(truncated ? bytes.sublist(0, maxBytes) : bytes,
          allowMalformed: true);
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.vaultFile,
        ok: true,
        payload: {
          'kind': 'text',
          'text': text,
          'size': size,
          'truncated': truncated,
        },
      );
    } catch (e) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.vaultFile,
        ok: false,
        error: 'vaultFile failed: $e',
      );
    }
  }

  /// 服務端縮圖：長邊縮到 maxPx、JPEG q85。解碼失敗回 null（呼叫端 fallback 原圖）。
  /// [2026-11-21 斷線風暴根治·刀A] 整段進背景 isolate：原先解碼+縮放+編碼
  /// 純同步跑在 main isolate，4MB 照片數百 ms~秒級/張，連續多張卡死 event
  /// loop → WebSocket pong 餓死 → 手機判死斷線重連循環。跨 isolate 只傳
  /// bytes 進、JPEG bytes 出（decoder/Image 物件不跨）；例外行為不變（原樣
  /// 拋出由呼叫端 catch fallthrough 原圖 fallback）。
  static Future<List<int>?> _resizeToJpeg(List<int> bytes, int maxPx) async {
    // 收 bytes 正規化（Isolate.send 只認 transferable 的 Uint8List）。
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    // 解碼、縮放、編碼全在 Isolate.run 背景執行緒完成，主執行緒零阻塞。
    return Isolate.run<List<int>?>(() {
      final img = imglib.decodeImage(data);
      if (img == null) return null;
      var w = img.width, h = img.height;
      final longSide = w > h ? w : h;
      if (longSide > maxPx) {
        final scale = maxPx / longSide;
        w = (w * scale).round();
        h = (h * scale).round();
      }
      final resized = imglib.copyResize(img, width: w, height: h);
      return Uint8List.fromList(imglib.encodeJpg(resized, quality: 85));
    });
  }

  /// [SPEC §8.3 2026-11-14] 手機任務面板：列出排程任務
  /// 回傳 ScheduleCard 轉換的 TaskCardData（id/名稱/狀態/前次成敗/產出檔案）
  Future<DesktopBridgeGatewayResponse> _handleTaskList(
    DesktopBridgeGatewayRequest request,
  ) async {
    try {
      final cards = await ScheduleRegistry.instance.loadAll();
      final taskList = <Map<String, dynamic>>[];
      for (final card in cards) {
        taskList.add({
          'id': card.id,
          'name': card.name,
          'kind': 'scheduled',
          'schedule': card.humanSchedule,
          'nextRunAt': card.nextRun?.toIso8601String(),
          'lastRunOk': card.lastRunOk,
          'lastRunAt': card.lastRunAt?.toIso8601String(),
          'lastRunError': card.lastRunError,
          'warmth': card.warmth == ScheduleWarmth.life ? 'life' : 'work',
          'warmLine': card.warmLine,
        });
      }
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.taskList,
        ok: true,
        payload: {'tasks': taskList},
      );
    } catch (e) {
      return DesktopBridgeGatewayResponse(
        requestId: request.id,
        type: DesktopBridgeGatewayMessageType.taskList,
        ok: false,
        error: 'taskList failed: $e',
      );
    }
  }

  /// 前 4KB 掃 NUL 與高位元比重——文字檔 heuristic
  static bool _looksTextual(List<int> head) {
    if (head.isEmpty) return true;
    var suspicious = 0;
    for (final b in head) {
      if (b == 0) return false;
      if (b >= 0x80) suspicious++;
    }
    return suspicious < head.length * 0.3;
  }

  AssetIndexService _vaultIndex() {
    _vaultIndexCache ??= AssetIndexService();
    return _vaultIndexCache!;
  }

  AssetIndexService? _vaultIndexCache;
  AssetSandbox get _vaultSandbox => _vaultSandboxCache ??= AssetSandbox();
  AssetSandbox? _vaultSandboxCache;
}