// sticky_endpoint_memory.dart
// [2026-11-20 sticky 端點直攻] 上次成功端點記憶——解鎖/啟動重連先直攻
// last-good host，不再每次都從死 LAN 門牌吃 8s 逾時才輪到 v6。
// 失敗計數封頂自動失效（WiFi 環境變換後不會永遠直攻死門牌）。
// 失敗退回既有 lan→v6→tailscale 輪替順序，本檔不改動那個順序。
//
// 持久化走專案鏡射慣例（mobile_device_token_store.dart 2026-11-13 教訓：
// macOS 沙箱 SharedPreferences 可能被 cfprefsd 蒸發）——JSON 鏡射到
// Application Support 當真相源，SharedPreferences 盡力寫。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [2026-11-20 sticky 端點直攻] 上次成功端點記憶。
class StickyEndpointMemory {
  /// SharedPreferences key（專案慣例：bridge_*_v1）。
  static const prefsKey = 'bridge_last_good_host_v1';

  /// [2026-11-20 sticky 端點直攻] cfprefsd 蒸發防——Application Support 鏡射檔。
  static const _mirrorFile = 'last_good_host_v1.json';

  /// [2026-11-20 sticky 端點直攻] 連攻失敗達此數即失效（任務書指定：2 次）。
  static const failThreshold = 2;

  static String? _cachedHost;
  static int _cachedFails = 0;

  static Future<String?> _mirrorPath() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return '${dir.path}/$_mirrorFile';
    } catch (_) {
      return null;
    }
  }

  /// 讀上次成功 host（無則 null）。
  static Future<String?> loadLastGoodHost() async {
    if (_cachedHost != null) return _cachedHost;
    var host = _cachedHost;
    try {
      final prefs = await SharedPreferences.getInstance();
      host = prefs.getString(prefsKey);
    } catch (_) {}
    // JSON 鏡射檔（真相源——寫入必落盤，鏡射 device_tokens_v1.json 模式）
    try {
      if (host == null) {
        final path = await _mirrorPath();
        if (path != null) {
          final f = File(path);
          if (await f.exists()) {
            final m = jsonDecode(await f.readAsString());
            if (m is Map) host = m['host'] as String?;
          }
        }
      }
    } catch (_) {}
    _cachedHost = host;
    return host;
  }

  /// 記一個成功端點：覆蓋 last-good 並清零失敗計數。
  static Future<void> recordSuccess(String host) async {
    _cachedHost = host;
    _cachedFails = 0;
    await _persist(host, 0);
  }

  /// 記一次直攻失敗：計數 +1，達封頂（2 次）失效清除。回傳是否失效。
  static Future<bool> recordFailure(String host) async {
    final cur = await loadLastGoodHost();
    if (cur != host) return false; // 失敗的不是当前 sticky——不記帳
    _cachedFails++;
    if (_cachedFails >= failThreshold) {
      _cachedHost = null;
      _cachedFails = 0;
      await _clear();
      debugPrint('[StickyEndpoint] $host 連敗 $failThreshold 次→失效，退回預設輪替');
      return true;
    }
    await _persist(host, _cachedFails);
    return false;
  }

  /// 純函數：last-good 若在候選集內排到第一位，否則原順序不動。
  static List<String> orderByLastGood(List<String> candidates, String? lastGood) {
    if (lastGood == null || !candidates.contains(lastGood)) return candidates;
    return [lastGood, ...candidates.where((h) => h != lastGood)];
  }

  static Future<void> _persist(String host, int fails) async {
    final payload = jsonEncode({'host': host, 'fails': fails});
    // ① JSON 鏡射（必落盤——真相源）
    try {
      final path = await _mirrorPath();
      if (path != null) await File(path).writeAsString(payload);
    } catch (_) {}
    // ② SharedPreferences（盡力——可能蒸發但不影響正確性）
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, host);
    } catch (_) {}
  }

  static Future<void> _clear() async {
    try {
      final path = await _mirrorPath();
      if (path != null) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey);
    } catch (_) {}
  }

  /// 測試注入點：清記憶體快取（不碰持久層）。
  @visibleForTesting
  static void resetCacheForTest() {
    _cachedHost = null;
    _cachedFails = 0;
  }
}
