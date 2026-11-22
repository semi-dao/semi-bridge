// relay_host_connector.dart
// 橋樑第 3 層中繼——桌面端出站連接器（SPEC §6.3 第二哩）
//
// 職責：Mac 主機「往外連」到自架中繼，註冊 hostId；手機經中繼配對後，
// 隧道位元組在本機轉發到 gateway（127.0.0.1:8790）。手機的 WebSocket
// 握手以原始 HTTP 位元組穿隧，gateway 的 HttpServer 照常升級——零協議改動。
//
// 生命週期：
//   while (!stop) {
//     connect relay → send host hello → 等第一個位元組（=手機來了）
//     → 開本機 TCP 到 gateway → 雙向 pipe → 斷了就重連註冊
//   }
//
// v1 限制（SPEC §6.3）：一次一對——隧道進行中，新手機連不上（host 不在
// waiting map）；隧道關閉後自動重掛註冊。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RelayHostConnectorConfig {
  final String relayHost;
  final int relayPort;
  final String hostId;
  final String secret;
  final int gatewayPort; // 本機 gateway（預設 8790）

  const RelayHostConnectorConfig({
    required this.relayHost,
    this.relayPort = 8791,
    required this.hostId,
    required this.secret,
    this.gatewayPort = 8790,
  });
}

class RelayHostConnector {
  RelayHostConnector();

  RelayHostConnector._internal();

  static final RelayHostConnector shared = RelayHostConnector._internal();

  RelayHostConnectorConfig? _config;
  Socket? _relaySocket;
  Socket? _localTunnel;
  bool _stopping = false;
  void Function(String line)? onLog;

  void setLogger(void Function(String line)? logger) => onLog = logger;

  void _log(String msg) => onLog?.call(msg);

  bool get isRunning => _relaySocket != null && !_stopping;

  Future<void> start(RelayHostConnectorConfig config) async {
    if (_config != null) await stop();
    _config = config;
    _stopping = false;
    unawaited(_run());
  }

  Future<void> stop() async {
    _stopping = true;
    try {
      _localTunnel?.destroy();
      _relaySocket?.destroy();
    } catch (_) {}
    _localTunnel = null;
    _relaySocket = null;
    _config = null;
  }

  Future<void> _run() async {
    final config = _config;
    if (config == null) return;

    var backoff = const Duration(seconds: 2);
    while (!_stopping) {
      try {
        final relay = await Socket.connect(
          config.relayHost,
          config.relayPort,
          timeout: const Duration(seconds: 10),
        );
        relay.setOption(SocketOption.tcpNoDelay, true);
        relay.write('${jsonEncode({
          'role': 'host',
          'hostId': config.hostId,
          'secret': config.secret,
        })}\n');
        await relay.flush();
        _relaySocket = relay;
        backoff = const Duration(seconds: 2); // 連上重置退避
        _log('registered on relay ${config.relayHost}:${config.relayPort} '
            'as ${config.hostId}');

        // 單一訂閱：等第一個位元組（=client 配對後的 WS 握手）→ 開隧道
        final tunnelOpened = Completer<void>();
        late final StreamSubscription<List<int>> sub;
        sub = relay.listen(
          (data) {
            if (_localTunnel == null) {
              _openTunnel(relay, sub, data, tunnelOpened);
            } else {
              try {
                _localTunnel?.add(data);
              } catch (_) {
                _teardownPair(relay);
              }
            }
          },
          onError: (_) => _teardownPair(relay),
          onDone: () => _teardownPair(relay),
        );

        // 等這條註冊連線結束（idle 逾時或隧道斷線）再重掛
        await relay.done.catchError((_) {});
        await sub.cancel().catchError((_) {});
        _relaySocket = null;
        _log('relay connection closed → 重新註冊');
      } catch (e) {
        _log('relay connect failed: $e → ${backoff.inSeconds}s 後重試');
      }
      if (_stopping) break;
      await Future.delayed(backoff);
      backoff = backoff.inSeconds >= 30
          ? const Duration(seconds: 30)
          : backoff * 2;
    }
  }

  /// 手機流量到了：開本機 TCP 到 gateway，第一包直接灌入（通常是 WS upgrade）。
  Future<void> _openTunnel(
    Socket relay,
    StreamSubscription<List<int>> relaySub,
    List<int> firstBytes,
    Completer<void> tunnelOpened,
  ) async {
    final config = _config;
    if (config == null) return;
    try {
      final local = await Socket.connect(
        InternetAddress.loopbackIPv4,
        config.gatewayPort,
        timeout: const Duration(seconds: 5),
      );
      local.setOption(SocketOption.tcpNoDelay, true);
      _localTunnel = local;
      _log('tunnel open → 127.0.0.1:${config.gatewayPort}');
      tunnelOpened.complete();

      local.add(firstBytes);

      local.listen(
        (data) {
          try {
            relay.add(data);
          } catch (_) {
            _teardownPair(relay);
          }
        },
        onError: (_) => _teardownPair(relay),
        onDone: () => _teardownPair(relay),
      );
    } catch (e) {
      _log('gateway tunnel failed: $e');
      _teardownPair(relay);
    }
  }

  void _teardownPair(Socket relay) {
    try {
      _localTunnel?.destroy();
    } catch (_) {}
    _localTunnel = null;
    try {
      relay.destroy();
    } catch (_) {}
    // relay 斷線 → _run() 迴圈重掛註冊
  }
}
