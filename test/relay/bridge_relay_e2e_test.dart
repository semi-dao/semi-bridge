// bridge_relay_e2e_test.dart
// 第 3 層中繼端對端測試（SPEC §6.3）：
// host+client 配對 → 盲轉位元組 → 斷線清理 → secret 不匹配拒絕
//
// 跑法：dart test tools/relay/bridge_relay_e2e_test.dart
// （在 tools/relay 獨立 Dart 環境；不進 Flutter test 樹）

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/relay/relay_server_core.dart';

// 直接 import 被測檔（純 dart:io，無 Flutter 依賴）

void main() {
  test('配對成立後位元組盲轉（雙向）', () async {
    final port = await _freePort();
    final server = await RelayServerCore.start(port: port);
    await _waitListen(port);

    // host 連上註冊
    final host = await Socket.connect('127.0.0.1', port);
    host.write('${jsonEncode({
      'role': 'host',
      'hostId': 'test-host-1',
      'secret': 's3cret',
    })}\n');
    await host.flush();
    await Future.delayed(const Duration(milliseconds: 200));

    // client 連上配對
    final client = await Socket.connect('127.0.0.1', port);
    client.write('${jsonEncode({
      'role': 'client',
      'hostId': 'test-host-1',
      'secret': 's3cret',
    })}\n');
    await client.flush();
    await Future.delayed(const Duration(milliseconds: 300));

    // client → host 資料
    final hostGot = BytesBuilder();
    final hostDone = Completer<void>();
    host.listen(hostGot.add, onDone: hostDone.complete);
    client.write('PING-FROM-CLIENT');
    await client.flush();
    await Future.delayed(const Duration(milliseconds: 300));
    expect(utf8.decode(hostGot.takeBytes()).contains('PING-FROM-CLIENT'), true);

    // host → client 資料
    final clientGot = BytesBuilder();
    final clientDone = Completer<void>();
    client.listen(clientGot.add, onDone: clientDone.complete);
    host.write('PONG-FROM-HOST');
    await host.flush();
    await Future.delayed(const Duration(milliseconds: 300));
    expect(utf8.decode(clientGot.takeBytes()).contains('PONG-FROM-HOST'), true);

    host.destroy();
    client.destroy();
    await server.close();
  });

  test('secret 不匹配 → client 被斷線（寧斷不轉錯）', () async {
    final port = await _freePort();
    final server = await RelayServerCore.start(port: port);
    await _waitListen(port);

    final host = await Socket.connect('127.0.0.1', port);
    host.write('${jsonEncode({
      'role': 'host', 'hostId': 'h2', 'secret': 'right',
    })}\n');
    await host.flush();
    await Future.delayed(const Duration(milliseconds: 200));

    final bad = await Socket.connect('127.0.0.1', port);
    final closed = Completer<void>();
    bad.listen((_) {}, onDone: closed.complete);
    bad.write('${jsonEncode({
      'role': 'client', 'hostId': 'h2', 'secret': 'WRONG',
    })}\n');
    await bad.flush();

    await closed.future.timeout(const Duration(seconds: 5));
    expect(closed.isCompleted, true);

    host.destroy();
    await server.close();
  });
}

Future<int> _freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}

Future<void> _waitListen(int port) async {
  for (var i = 0; i < 50; i++) {
    try {
      final s = await Socket.connect('127.0.0.1', port);
      s.destroy();
      return;
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }
  fail('relay 沒起來');
}
