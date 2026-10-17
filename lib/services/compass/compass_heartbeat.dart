// compass_heartbeat.dart
// 羅盤心跳層——器官健康狀態輪詢。
//
// 證據三源（服務狀態端點會說謊，mtime 是地面真相）：
// 1. 端點回應（HTTP /health）
// 2. process 存活（pgrep / NSRunningApplication）
// 3. 關鍵 mtime（runtime-state.json 的最後修改時間）
//
// 三源任一為紅 → 器官轉紅；任一為琥珀 → 琥珀；其餘綠。

import 'dart:async';
import 'dart:io';

import 'compass_models.dart';
import 'compass_store.dart';

/// 心跳檢查器（給特定器官用的健康探針）
abstract class OrganHealthProbe {
  String get organId;
  Future<OrganHealthEvidence> probe();
}

/// 端點探針（HTTP GET /health）
class HttpEndpointProbe implements OrganHealthProbe {
  @override
  final String organId;
  final String url;
  final Duration timeout;
  HttpEndpointProbe(this.organId, this.url,
      {this.timeout = const Duration(seconds: 3)});

  @override
  Future<OrganHealthEvidence> probe() async {
    try {
      final client = HttpClient()..connectionTimeout = timeout;
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('Accept', 'application/json');
      final resp = await req.close().timeout(timeout);
      final ok = resp.statusCode == 200;
      client.close();
      return OrganHealthEvidence(
        status: ok ? CompassHealth.green : CompassHealth.amber,
        summary: ok ? '端點 OK' : '端點 ${resp.statusCode}',
        checkedAt: DateTime.now(),
      );
    } catch (e) {
      return OrganHealthEvidence(
        status: CompassHealth.red,
        summary: '端點失敗: $e',
        checkedAt: DateTime.now(),
      );
    }
  }
}

/// 程序存活探針（macOS pgrep 簡化版）
class ProcessAliveProbe implements OrganHealthProbe {
  @override
  final String organId;
  final String processName;
  ProcessAliveProbe(this.organId, this.processName);

  @override
  Future<OrganHealthEvidence> probe() async {
    try {
      final result = await Process.run('pgrep', ['-f', processName]);
      final alive = result.exitCode == 0;
      return OrganHealthEvidence(
        status: alive ? CompassHealth.green : CompassHealth.red,
        summary: alive ? 'process alive' : 'process missing',
        checkedAt: DateTime.now(),
      );
    } catch (e) {
      return OrganHealthEvidence(
        status: CompassHealth.amber,
        summary: 'pgrep failed: $e',
        checkedAt: DateTime.now(),
      );
    }
  }
}

/// 心跳服務（背景排程）
class CompassHeartbeat {
  final CompassStore store;
  final Map<String, List<OrganHealthProbe>> _probes = {};
  final Map<String, OrganHealthEvidence> _last = {};
  Timer? _timer;

  CompassHeartbeat(this.store);

  void register(OrganHealthProbe probe) {
    _probes.putIfAbsent(probe.organId, () => []).add(probe);
  }

  void start({Duration interval = const Duration(seconds: 60)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
    // 啟動時先跑一次
    _tick();
  }

  Future<void> _tick() async {
    for (final entry in _probes.entries) {
      final results = await Future.wait(entry.value.map((p) => p.probe()));
      final red = results.any((r) => r.status == CompassHealth.red);
      final amber =
          results.any((r) => r.status == CompassHealth.amber);
      final merged = OrganHealthEvidence(
        status: red
            ? CompassHealth.red
            : amber
                ? CompassHealth.amber
                : CompassHealth.green,
        summary: results.map((r) => r.summary).join(' / '),
        checkedAt: DateTime.now(),
      );
      _last[entry.key] = merged;
      // [T9① 2026-10-17] 心跳結果落 store（D9：不落 store 的觀測不算觀測）
      try {
        store.recordHealth(
          entry.key,
          merged.status.name,
          merged.summary.length > 300
              ? merged.summary.substring(0, 300)
              : merged.summary,
        );
      } catch (_) {}
    }
  }

  OrganHealthEvidence? last(String organId) => _last[organId];

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// 預設探針註冊（首播用）
void registerDefaultProbes(CompassHeartbeat hb) {
  hb.register(HttpEndpointProbe('local.engine', 'http://127.0.0.1:18789/health'));
  hb.register(HttpEndpointProbe('local.kokoro', 'http://127.0.0.1:18900/health'));
  hb.register(ProcessAliveProbe('local.engine', 'llama-server'));
  hb.register(ProcessAliveProbe('local.kokoro', 'kokoro'));
}
