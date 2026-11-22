// relay_server_core.dart
// 橋樑第 3 層中繼核心（SPEC §6.3）——純 dart:io，無 Flutter 依賴。
// tools/relay/bridge_relay.dart（CLI）與 test/relay/（測試）共用。
//
// 哲學：TCP 盲轉——不解讀、不落地、不終結 TLS。
//
// 陷阱筆記（2026-11-12 e2e 抓包 ×2）：
// 1. hello 行與首批資料常同 TCP 段送達——\n 後殘餘 bytes 要保留補送
// 2. Socket 是單訂閱流——hello 讀完不可 cancel 重聽，須同一訂閱熱插拔
//    onData/onError/onDone

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const Duration helloTimeout = Duration(seconds: 30);
const int maxHelloBytes = 1024;
const int maxHttpHelloBytes = 8192; // HTTP peek：upgrade 請求 headers 上限
const Duration hostIdleTimeout = Duration(minutes: 5);

class _HelloRead {
  final Map<String, dynamic> hello;
  final List<int> leftover;
  final StreamSubscription<Uint8List> sub;
  _HelloRead(this.hello, this.leftover, this.sub);
}

class _Session {
  final String hostId;
  final String secret;
  final Socket socket;
  final StreamSubscription<Uint8List> sub;
  final DateTime startedAt = DateTime.now();
  final List<int> pendingFromHost = [];
  Socket? peer;
  Timer? timeout;

  _Session({
    required this.hostId,
    required this.secret,
    required this.socket,
    required this.sub,
  });

  bool get isPaired => peer != null;
}

/// 中繼伺服器核心：start() 起 listener，close() 收池。
class RelayServerCore {
  final int port;
  ServerSocket? _server;
  final Map<String, _Session> _hostWaiting = {};
  final Map<String, _Session> _activePairs = {};
  final void Function(String line)? onLog;

  RelayServerCore({this.port = 8791, this.onLog});

  void _log(String msg) => onLog?.call(msg);

  static Future<RelayServerCore> start({
    int port = 8791,
    void Function(String line)? onLog,
  }) async {
    final core = RelayServerCore(port: port, onLog: onLog);
    core._server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    core._server!.listen(
      (socket) {
        socket.setOption(SocketOption.tcpNoDelay, true);
        core._handleConnection(socket);
      },
      onError: (e) => core._log('server error: $e'),
    );
    core._log('listening on :$port');
    return core;
  }

  Future<void> close() async {
    // 快照迭代——destroy 回呼會同步觸發 cleanup 改 map（併發修改炸點）
    for (final s in List.of(_hostWaiting.values)) {
      s.timeout?.cancel();
      s.socket.destroy();
      s.peer?.destroy();
    }
    for (final s in List.of(_activePairs.values)) {
      s.socket.destroy();
      s.peer?.destroy();
    }
    _hostWaiting.clear();
    _activePairs.clear();
    await _server?.close();
  }

  Future<void> _handleConnection(Socket socket) async {
    final read = await _readHello(socket);
    if (read == null) {
      socket.destroy();
      return;
    }

    switch (read.hello['role']) {
      case 'host':
        _onHost(socket, read);
      case 'client':
        _onClient(socket, read);
      default:
        _log('unknown role: ${read.hello['role']}');
        socket.destroy();
    }
  }

  /// 讀 hello——雙模式（訂閱保持存活 pause，交給角色 handler 熱插拔）：
  /// ① JSON 行：{"role":"host|client",...}\n（host 連接器／raw client）
  /// ② HTTP peek：GET /bridge HTTP/1.1 + x-bridge-host-id/x-bridge-secret
  ///    headers（手機 WebSocket.connect 直連中繼）——配對後整個 HTTP 請求
  ///    （含 headers）原封不動盲轉，gateway 照常 101 升級。
  ///    ⚠️ leftover 必須含完整原始 bytes（buffer 本身），一個都不能吞。
  Future<_HelloRead?> _readHello(Socket socket) {
    final completer = Completer<_HelloRead?>();
    final buffer = <int>[];
    late final Timer timer;
    late final StreamSubscription<Uint8List> sub;

    void done(_HelloRead? value) {
      timer.cancel();
      if (!completer.isCompleted) completer.complete(value);
    }

    timer = Timer(helloTimeout, () {
      sub.cancel();
      done(null);
    });

    void tryParse() {
      // 模式判別：HTTP 方法開頭？
      final head = utf8.decode(buffer.take(8).toList(), allowMalformed: true);
      const httpVerbs = ['GET ', 'POST ', 'PUT ', 'OPTI', 'HEAD'];
      final isHttp = httpVerbs.any(head.startsWith);

      if (isHttp) {
        // 等 headers 結束（\r\n\r\n）再解析
        final hdrEnd = _findHeaderEnd(buffer);
        if (hdrEnd < 0) {
          if (buffer.length > maxHttpHelloBytes) {
            sub.cancel();
            done(null);
          }
          return; // 繼續收
        }
        final text = utf8.decode(buffer.take(hdrEnd).toList(),
            allowMalformed: true);
        final hostId = _headerValue(text, 'x-bridge-host-id');
        final secret = _headerValue(text, 'x-bridge-secret');
        if (hostId == null || secret == null) {
          sub.cancel();
          done(null);
          return;
        }
        sub.pause();
        done(_HelloRead(
          {'role': 'client', 'hostId': hostId, 'secret': secret},
          buffer, // 完整原始 bytes（HTTP 請求本體）——全量保留
          sub,
        ));
        return;
      }

      // JSON 行模式
      final nl = buffer.indexOf(10);
      if (nl < 0) {
        if (buffer.length > maxHelloBytes) {
          sub.cancel();
          done(null);
        }
        return;
      }
      final line =
          utf8.decode(buffer.take(nl).toList(), allowMalformed: true);
      try {
        final json = jsonDecode(line);
        if (json is Map<String, dynamic>) {
          sub.pause();
          done(_HelloRead(json, buffer.skip(nl + 1).toList(), sub));
        } else {
          sub.cancel();
          done(null);
        }
      } catch (_) {
        sub.cancel();
        done(null);
      }
    }

    sub = socket.listen(
      (data) {
        buffer.addAll(data);
        tryParse();
      },
      onError: (_) {
        sub.cancel();
        done(null);
      },
      onDone: () {
        sub.cancel();
        done(null);
      },
    );

    return completer.future;
  }

  /// 找 \r\n\r\n（HTTP headers 結尾）位置；回傳「headers 結尾 index」
  /// （=首次出現位置+4），未找到回 -1。
  static int _findHeaderEnd(List<int> bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 && bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 && bytes[i + 3] == 10) {
        return i + 4;
      }
    }
    return -1;
  }

  /// 從 HTTP 請求文本抽 header 值（大小寫不敏感；null=無此 header）。
  static String? _headerValue(String text, String name) {
    for (final line in text.split('\r\n')) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      if (line.substring(0, idx).trim().toLowerCase() == name) {
        return line.substring(idx + 1).trim();
      }
    }
    return null;
  }

  void _onHost(Socket socket, _HelloRead read) {
    final hello = read.hello;
    final hostId = hello['hostId'] as String? ?? '';
    final secret = hello['secret'] as String? ?? '';
    if (hostId.isEmpty || secret.isEmpty) {
      read.sub.cancel();
      return socket.destroy();
    }

    // 同 hostId 重連：清舊 session（host 重啟常態）
    _hostWaiting.remove(hostId)?.socket.destroy();
    _activePairs.remove(hostId)?.socket.destroy();

    final session = _Session(
        hostId: hostId, secret: secret, socket: socket, sub: read.sub);
    session.pendingFromHost.addAll(read.leftover);
    _hostWaiting[hostId] = session;
    _log('host registered: $hostId');

    session.timeout = Timer(hostIdleTimeout, () {
      if (!session.isPaired && identical(_hostWaiting[hostId], session)) {
        _hostWaiting.remove(hostId);
        session.sub.cancel();
        socket.destroy();
      }
    });

    // 熱插拔：hello 後的 host→client 資料流
    session.sub
      ..onData((data) {
        final peer = session.peer;
        if (peer != null) {
          try {
            peer.add(data);
          } catch (_) {
            _cleanupHost(hostId, session);
          }
        } else {
          session.pendingFromHost.addAll(data); // 未配對先囤
        }
      })
      ..onError((_) => _cleanupHost(hostId, session))
      ..onDone(() => _cleanupHost(hostId, session))
      ..resume();
  }

  void _cleanupHost(String hostId, _Session session) {
    if (identical(_hostWaiting[hostId], session)) _hostWaiting.remove(hostId);
    if (identical(_activePairs[hostId], session)) _activePairs.remove(hostId);
    session.peer?.destroy();
    session.socket.destroy();
  }

  void _onClient(Socket socket, _HelloRead read) {
    final hello = read.hello;
    final hostId = hello['hostId'] as String? ?? '';
    final secret = hello['secret'] as String? ?? '';
    final sub = read.sub;

    final session = _hostWaiting[hostId];
    if (session == null) {
      _log('client for unknown host: $hostId → 斷線');
      sub.cancel();
      return socket.destroy();
    }
    if (session.secret != secret) {
      _log('secret mismatch for $hostId → 斷線（寧斷不轉錯）');
      sub.cancel();
      return socket.destroy();
    }

    session.timeout?.cancel();
    session.peer = socket;
    _hostWaiting.remove(hostId);
    _activePairs[hostId] = session;
    _log('pair established: $hostId');

    // 補送：hello 同段殘餘（host→client）＋未配對期間囤積
    try {
      if (read.leftover.isNotEmpty) session.socket.add(read.leftover);
      if (session.pendingFromHost.isNotEmpty) {
        socket.add(session.pendingFromHost);
        session.pendingFromHost.clear();
      }
    } catch (_) {
      _cleanupHost(hostId, session);
      return;
    }

    // 熱插拔：client→host 盲轉
    sub
      ..onData((data) {
        try {
          session.socket.add(data);
        } catch (_) {
          _cleanupHost(hostId, session);
        }
      })
      ..onError((_) => _cleanupHost(hostId, session))
      ..onDone(() => _cleanupHost(hostId, session))
      ..resume();
  }
}
