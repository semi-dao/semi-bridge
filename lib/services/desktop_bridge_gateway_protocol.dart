import 'desktop_bridge_pairing_contract.dart';

/// Gateway 訊息類型。
///
/// Sprint 14 基礎：hello / runtimeSnapshot / capabilityList / error
/// Sprint 19a 擴充：taskRun / taskCancel / taskProgress / taskComplete / taskAwaitingConfirmation
enum DesktopBridgeGatewayMessageType {
  // --- Sprint 14: 同步 request-response ---
  hello,
  runtimeSnapshot,
  capabilityList,
  error,

  // --- Sprint 19a: 長任務生命週期 ---
  /// 手機 → 桌面：啟動一個長任務（瀏覽器操作、檔案下載等）
  taskRun,
  /// 手機 → 桌面：取消進行中的任務
  taskCancel,
  /// 桌面 → 手機（push）：任務進度更新
  taskProgress,
  /// 桌面 → 手機（push）：任務完成（成功或失敗）
  taskComplete,
  /// 桌面 → 手機（push）：任務暫停，等待使用者確認（如偵測到登入頁）
  taskAwaitingConfirmation,
  /// 手機 → 桌面：回覆拍板請求（approve / reject）。
  /// [S1 2026-10-31 補鏈] 任務暫停等待確認後，手機端拍板結果經此訊息回傳，
  /// 桌面喚醒暫停中的任務繼續執行（approve）或終止（reject）。
  /// 對 taskAwaitingConfirmation 的每個 taskId，_confirmationResponders 持有喚醒器。
  confirmationRespond,

  // --- [SPEC §8.3 2026-11-14] 手機任務面板 ---
  /// 手機 → 桌面：列出任務卡（排程任務）
  taskList,
  // --- [SPEC §8.5 2026-11-12] 手機向量資料庫 tab ---
  /// 手機 → 桌面：列出 vault 檔案（ManifestFile 摘要，含 junk 過濾）
  vaultList,
  /// 手機 → 桌面：讀單一檔案內容（預覽器用——文字類全文/圖片 base64）
  vaultFile,
  /// [SPEC §8.5b 2026-11-13] 手機 → 桌面：語意/全文/標籤搜尋（同桌面 facade）
  vaultSearch,
  /// [SPEC §8.5b] 手機 → 桌面：標籤清單（FileTagStore 聯集）
  vaultTags,
  /// [SPEC §8.5c 2026-11-13] 桌面 → 手機推播：vault 內容變動（新檔/更新）
  /// ——手機收到即自動重抓（免重啟免下拉；Blue 令「縮小不關」情境）
  vaultChanged,
  /// [SPEC 開光手機版 2026-11-13] 桌面 → 手機推播：請手機拍視網膜
  /// （AppRetina.capture 全域 RepaintBoundary）——手機回 retinaResponse
  retinaRequest,
  /// [SPEC 開光手機版] 手機 → 桌面 request：視網膜照片回傳
  /// （payload: {requestId, base64|null}）
  retinaResponse,
  /// [SPEC §8.2 2026-11-13 對話三層] 手機 → 桌面 request：
  /// 對話清單（左欄三類型圓標的糧道——回所有 conversation 元資料）
  conversationList,
  /// [SPEC §8.2] 手機 → 桌面 request：單一對話歷史
  /// （payload: {conversationId, limit}）
  conversationHistory,
  /// [SPEC §8.2] 手機 → 桌面 request：發送訊息到對話
  /// （payload: {conversationId, role, content}）
  conversationAppend,
  /// [SPEC §8.6 2026-11-14] 手機 → 桌面 request：軟刪除對話
  /// （payload: {conversationId}）
  conversationDelete,

  // --- 小隊動態推播 2026-11-17 ---
  /// 桌面 → 手機（push）：小隊動態變動（成員開工/回報）。
  /// payload: {parentId, event('spawned'|'reported'), squadId, at}
  /// ——手機收到即重抓對話清單（小隊節點出現在樹上）。
  squadChanged,
}

/// 桌面端長任務處理器介面。
///
/// 由 S19b BrowserAutomationService 和 S19c TaskQueue 實作。
/// Gateway 收到 `taskRun` 請求時呼叫 [startTask]，立即回傳 taskId，
/// 任務在背景非同步執行，透過 callback 推播進度/結果到手機。
abstract class GatewayTaskHandler {
  /// 啟動一個長任務，回傳唯一 taskId。
  ///
  /// [taskType] 任務類型，如 "browser.navigate"、"browser.fillForm"
  /// [payload] 任務參數
  /// [onProgress] 推播進度更新 (0.0–1.0)
  /// [onComplete] 推播最終結果
  /// [onAwaitingConfirmation] 推播「需要使用者確認」（如偵測到登入/付款頁）
  String startTask({
    required String taskType,
    required Map<String, dynamic> payload,
    required void Function(double progress, String message) onProgress,
    required void Function(bool success, Map<String, dynamic> result, String? error) onComplete,
    required void Function(String reason, Map<String, dynamic> context) onAwaitingConfirmation,
  });

  /// 取消進行中的任務。回傳 true 代表找到並已取消。
  bool cancelTask(String taskId);
}

/// 桌面主動推播給手機的訊息（非 request-response）。
///
/// 與 [DesktopBridgeGatewayResponse] 的區別：
/// - Response 有 `requestId`，是對手機請求的回應
/// - Push 沒有 `requestId`，是桌面主動發起
class DesktopBridgeGatewayPush {
  final DesktopBridgeGatewayMessageType type;
  final Map<String, dynamic> payload;

  const DesktopBridgeGatewayPush({
    required this.type,
    this.payload = const {},
  });

  Map<String, Object?> toJson() {
    return {
      'schema': 'bridge.desktop.gateway.push.v1',
      'type': type.name,
      'payload': payload,
    };
  }
}

// ─────────────────────────────────────────────────────────
// Request / Response（Sprint 14 既有，S19a 不改結構）
// ─────────────────────────────────────────────────────────

class DesktopBridgeGatewayRequest {
  final String id;
  final DesktopBridgeGatewayMessageType type;
  final Map<String, dynamic> payload;

  const DesktopBridgeGatewayRequest({
    required this.id,
    required this.type,
    this.payload = const {},
  });

  factory DesktopBridgeGatewayRequest.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'];
    final type = DesktopBridgeGatewayMessageType.values.firstWhere(
      (item) => item.name == typeName,
      orElse: () => DesktopBridgeGatewayMessageType.error,
    );
    return DesktopBridgeGatewayRequest(
      id: json['id'] is String ? json['id'] as String : 'unknown',
      type: type,
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schema': 'bridge.desktop.gateway.request.v1',
      'id': id,
      'type': type.name,
      'payload': payload,
    };
  }
}

class DesktopBridgeGatewayResponse {
  final String requestId;
  final DesktopBridgeGatewayMessageType type;
  final bool ok;
  final Map<String, dynamic> payload;
  final String? error;

  const DesktopBridgeGatewayResponse({
    required this.requestId,
    required this.type,
    required this.ok,
    this.payload = const {},
    this.error,
  });

  Map<String, Object?> toJson() {
    return {
      'schema': 'bridge.desktop.gateway.response.v1',
      'requestId': requestId,
      'type': type.name,
      'ok': ok,
      if (payload.isNotEmpty) 'payload': payload,
      if (error != null) 'error': error,
    };
  }
}

/// 同步請求處理器（hello / runtimeSnapshot / capabilityList）。
///
/// taskRun / taskCancel 由 Gateway 直接處理（需要 push 機制），
/// 不走這裡。push 類型（taskProgress / taskComplete / taskAwaitingConfirmation）
/// 是桌面 → 手機單向，也不走這裡。
class DesktopBridgeGatewayProtocol {
  const DesktopBridgeGatewayProtocol();

  DesktopBridgeGatewayResponse handleRequest({
    required DesktopBridgeGatewayRequest request,
    required DesktopBridgePairingContract pairingContract,
    required Map<String, dynamic> runtimePayload,
  }) {
    return switch (request.type) {
      DesktopBridgeGatewayMessageType.hello => _hello(request, pairingContract),
      DesktopBridgeGatewayMessageType.runtimeSnapshot => _runtimeSnapshot(
          request,
          runtimePayload,
        ),
      DesktopBridgeGatewayMessageType.capabilityList => _capabilityList(
          request,
          pairingContract,
        ),
      // Task 請求由 Gateway 直接處理，走到這裡代表程式邏輯錯誤
      DesktopBridgeGatewayMessageType.taskRun ||
      DesktopBridgeGatewayMessageType.taskCancel =>
        _error(request, 'Task requests are handled by the gateway, not the protocol.'),
      // [SPEC §8.3 2026-11-14] taskList 同樣由 gateway 直接處理
      DesktopBridgeGatewayMessageType.taskList =>
        _error(request, 'Task list requests are handled by the gateway, not the protocol.'),
      // Push 類型是桌面 → 手機單向，手機不應發送
      DesktopBridgeGatewayMessageType.taskProgress ||
      DesktopBridgeGatewayMessageType.taskComplete ||
      DesktopBridgeGatewayMessageType.taskAwaitingConfirmation ||
      // [SPEC §8.5c] vaultChanged 同為 push-only（桌面→手機）
      DesktopBridgeGatewayMessageType.vaultChanged ||
      // [小隊動態 2026-11-17] squadChanged 同為 push-only（桌面→手機）
      DesktopBridgeGatewayMessageType.squadChanged ||
      // [SPEC 開光] retinaRequest 同為 push-only
      DesktopBridgeGatewayMessageType.retinaRequest =>
        _error(request, 'Push-only message type cannot be sent from mobile.'),
      // [S1] confirmationRespond 由 Gateway 直接處理（需要喚醒暫停任務），不走同步 protocol
      DesktopBridgeGatewayMessageType.confirmationRespond =>
        _error(request, 'Confirmation responses are handled by the gateway, not the protocol.'),
      DesktopBridgeGatewayMessageType.error => _error(
          request,
          'Unsupported gateway request type.',
        ),
      // [SPEC 開光] retinaResponse 由 Gateway 直接處理（存檔），不走同步 protocol
      DesktopBridgeGatewayMessageType.retinaResponse =>
        _error(request, 'Retina responses are handled by the gateway, not the protocol.'),
      // [SPEC §8.2] conversationList/conversationHistory/conversationDelete/conversationAppend 由 Gateway 直接處理
      DesktopBridgeGatewayMessageType.conversationList ||
      DesktopBridgeGatewayMessageType.conversationHistory ||
      DesktopBridgeGatewayMessageType.conversationDelete ||
      DesktopBridgeGatewayMessageType.conversationAppend =>
        _error(request, 'Conversation requests are handled by the gateway, not the protocol.'),
      // [SPEC §8.5] vault 請求由 Gateway 直接處理（讀磁碟），不走同步 protocol
      DesktopBridgeGatewayMessageType.vaultList ||
      DesktopBridgeGatewayMessageType.vaultFile ||
      DesktopBridgeGatewayMessageType.vaultSearch ||
      DesktopBridgeGatewayMessageType.vaultTags =>
        _error(request, 'Vault requests are handled by the gateway, not the protocol.'),
    };
  }

  DesktopBridgeGatewayResponse _hello(
    DesktopBridgeGatewayRequest request,
    DesktopBridgePairingContract pairingContract,
  ) {
    final code = request.payload['pairingCode'];
    if (code != pairingContract.pairingCode) {
      return _error(request, 'Pairing code does not match.');
    }
    return DesktopBridgeGatewayResponse(
      requestId: request.id,
      type: DesktopBridgeGatewayMessageType.hello,
      ok: true,
      payload: {
        'schema': 'bridge.desktop.gateway.hello.v1',
        'desktopName': pairingContract.desktopName,
        'runtimeChannel': pairingContract.runtimeChannel,
        'readyForMobilePairing': pairingContract.readyForMobilePairing,
        'capabilities': [
          for (final capability in pairingContract.capabilities)
            capability.toJson(),
        ],
      },
    );
  }

  DesktopBridgeGatewayResponse _runtimeSnapshot(
    DesktopBridgeGatewayRequest request,
    Map<String, dynamic> runtimePayload,
  ) {
    if (runtimePayload.isEmpty) {
      return _error(request, 'Runtime payload is not available.');
    }
    return DesktopBridgeGatewayResponse(
      requestId: request.id,
      type: DesktopBridgeGatewayMessageType.runtimeSnapshot,
      ok: true,
      payload: {
        'schema': 'bridge.desktop.gateway.runtime_snapshot.v1',
        'runtimePayload': runtimePayload,
      },
    );
  }

  DesktopBridgeGatewayResponse _capabilityList(
    DesktopBridgeGatewayRequest request,
    DesktopBridgePairingContract pairingContract,
  ) {
    return DesktopBridgeGatewayResponse(
      requestId: request.id,
      type: DesktopBridgeGatewayMessageType.capabilityList,
      ok: true,
      payload: {
        'schema': 'bridge.desktop.gateway.capabilities.v1',
        'capabilities': [
          for (final capability in pairingContract.capabilities)
            capability.toJson(),
        ],
      },
    );
  }

  DesktopBridgeGatewayResponse _error(
    DesktopBridgeGatewayRequest request,
    String message,
  ) {
    return DesktopBridgeGatewayResponse(
      requestId: request.id,
      type: DesktopBridgeGatewayMessageType.error,
      ok: false,
      error: message,
    );
  }
}
