// 裝置 token 機制（主機端簽發/驗證 ＋ 手機端儲存）
// [S1 收尾 2026-11-08] 依據 BRIDGE_MOBILE_SPEC.md v0.5 §2 #6（紅隊 #8 補全）：
// - 配對成功後主機發長期裝置 token（手機存 Keychain/Keystore）
// - 重連憑 token 自動握手；token 失效才要求重新掃 QR
// - token 是 256-bit 隨機值（非 pairingCode 本身、非主機密鑰衍生物可逆推）
//
// 兩個使用者：
// - 主機端：DeviceTokenService（簽發/驗證/撤銷，掛 gateway）
// - 手機端：MobileDeviceTokenStore（介面＋Memory 實現；Keychain 實現接 S4 真機）

import 'dart:convert';
import 'dart:math';

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────
// 主機端：token 簽發/驗證服務
// ─────────────────────────────────────────────────────────

/// token 的持久化介面（主機端）——測試注入 MemoryTokenStore，
/// 正式環境用 [SharedPrefsTokenStore]（SharedPreferences 桌面版等同檔案）。
abstract class DeviceTokenPersistence {
  Future<void> saveToken(String token);
  Future<bool> containsToken(String token);
  Future<void> removeToken(String token);

  /// [2026-11-11 一機一證] deviceId↔token 綁定（重配對時撤舊用）。
  Future<void> bindDevice(String deviceId, String token);
  Future<String?> loadTokenForDevice(String deviceId);
}

/// 主機端裝置 token 服務。
class DeviceTokenService {
  final DeviceTokenPersistence _store;
  final Random _random;

  DeviceTokenService({required DeviceTokenPersistence store, Random? random})
      : _store = store,
        _random = random ?? Random.secure();

  /// 配對碼正確時簽發新裝置 token；配對碼錯誤回 null。
  ///
  /// [presentedCode] 手機送來的配對碼
  /// [expectedCode] 主機當前配對碼（BRIDGE-XXXXXX）
  /// [deviceId] 手機穩定識別碼（2026-11-11 Blue 令：同一支手機只留一顆
  /// 憑證——同 deviceId 重配對＝撤舊簽新，桌上不再累積憑證）
  Future<String?> issueForPairing(
    String presentedCode,
    String expectedCode, {
    String? deviceId,
  }) async {
    if (presentedCode != expectedCode) return null;
    // 同一支手機重配對：先撤舊憑證再簽新——永遠一機一證
    if (deviceId != null && deviceId.isNotEmpty) {
      final old = await _store.loadTokenForDevice(deviceId);
      if (old != null) await _store.removeToken(old);
    }
    final token = _generateToken();
    await _store.saveToken(token);
    if (deviceId != null && deviceId.isNotEmpty) {
      await _store.bindDevice(deviceId, token);
    }
    return token;
  }

  /// 驗證 token（重連握手用）。
  Future<bool> validate(String token) => _store.containsToken(token);

  /// 撤銷（手機被偷/重鑄儀式用）。
  Future<void> revoke(String token) => _store.removeToken(token);

  String _generateToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes); // 43 字元，256-bit 熵
  }
}

/// 記憶體實現（測試用；也當「重啟後仍有效」語義的對照組）。
class MemoryTokenStore implements DeviceTokenPersistence {
  final Set<String> _tokens = {};
  final Map<String, String> _bindings = {};

  @override
  Future<void> saveToken(String token) async => _tokens.add(token);

  @override
  Future<bool> containsToken(String token) async => _tokens.contains(token);

  @override
  Future<void> removeToken(String token) async => _tokens.remove(token);

  @override
  Future<void> bindDevice(String deviceId, String token) async =>
      _bindings[deviceId] = token;

  @override
  Future<String?> loadTokenForDevice(String deviceId) async =>
      _bindings[deviceId];
}

/// SharedPreferences 實現（主機端正式環境）。
class SharedPrefsTokenStore implements DeviceTokenPersistence {
  static const _keyPrefix = 'bridge_device_tokens_v1';

  /// [2026-11-13 Blue 報案「重啟後離線要重新配對」] 兩層病根：
  /// ① 沙箱 SharedPreferences 讀容器域，但歷史 token 在 host 域——聯集讀
  /// ② [教訓同 StorageService golden_keys.json 2026-08-11] macOS 沙箱下
  ///    SharedPreferences 寫入不保證落盤（cfprefcd 快取蒸發——實證：容器
  ///    plist mtime 停在 11/11，其後簽發的 token 全部失蹤）——token 鏡射
  ///    到 Application Support JSON 檔，重啟必存活。
  static const _mirrorFile = 'device_tokens_v1.json';

  Future<String?> _mirrorPath() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return '${dir.path}/$_mirrorFile';
    } catch (_) {
      return null;
    }
  }

  Future<Set<String>> _load() async {
    final tokens = <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      tokens.addAll(prefs.getStringList(_keyPrefix) ?? []);
    } catch (_) {}
    // JSON 鏡射檔（真相源——寫入必落盤）
    try {
      final path = await _mirrorPath();
      if (path != null) {
        final f = File(path);
        if (await f.exists()) {
          final list = jsonDecode(await f.readAsString());
          if (list is List) tokens.addAll(list.whereType<String>());
        }
      }
    } catch (_) {}
    // host 域 fallback（歷史 token）
    try {
      final proc = await Process.run('defaults', [
        'read', 'farm.semiwasabi.bridgeApp', 'flutter.$_keyPrefix',
      ]);
      final out = proc.stdout.toString().trim();
      if (out.isNotEmpty) {
        tokens.addAll(RegExp(r'"([^"]+)"')
            .allMatches(out)
            .map((m) => m.group(1)!));
      }
    } catch (_) {}
    return tokens;
  }

  Future<void> _save(Set<String> tokens) async {
    // ① JSON 鏡射（必落盤——真相源）
    try {
      final path = await _mirrorPath();
      if (path != null) {
        await File(path).writeAsString(jsonEncode(tokens.toList()));
      }
    } catch (_) {}
    // ② SharedPreferences（盡力——可能蒸發但不影響正確性）
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyPrefix, tokens.toList());
    } catch (_) {}
  }

  @override
  Future<void> saveToken(String token) async {
    final tokens = await _load();
    tokens.add(token);
    await _save(tokens);
  }

  @override
  Future<bool> containsToken(String token) async =>
      (await _load()).contains(token);

  @override
  Future<void> removeToken(String token) async {
    final tokens = await _load();
    tokens.remove(token);
    await _save(tokens);
  }

  /// [S4 2026-11-11] 全部已簽發 token（桌面「已綁定手機」清單用；
  /// 一個 token = 一支配對過的手機）。
  Future<Set<String>> allTokens() async => _load();

  // [2026-11-11 一機一證] deviceId↔token 綁定表（key: bridge_device_bindings_v1）
  static const _bindingKey = 'bridge_device_bindings_v1';

  static const _bindingMirrorFile = 'device_bindings_v1.json';

  Future<Map<String, String>> _loadBindings() async {
    final entries = <String>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      entries.addAll(prefs.getStringList(_bindingKey) ?? []);
    } catch (_) {}
    // JSON 鏡射（同 _save 教訓——bindings 必落盤）
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/$_bindingMirrorFile');
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString());
        if (list is List) entries.addAll(list.whereType<String>());
      }
    } catch (_) {}
    // [2026-11-13 兩域聯集] host 域 fallback（同 _load——歷史綁定在 host 域）
    try {
      final proc = await Process.run('defaults', [
        'read', 'farm.semiwasabi.bridgeApp', 'flutter.$_bindingKey',
      ]);
      final out = proc.stdout.toString().trim();
      if (out.isNotEmpty) {
        entries.addAll(RegExp(r'"([^"=]+=[^"]*)"')
            .allMatches(out)
            .map((m) => m.group(1)!));
      }
    } catch (_) {}
    final m = <String, String>{};
    for (final e in entries) {
      if (e.contains('=')) {
        m[e.substring(0, e.indexOf('='))] = e.substring(e.indexOf('=') + 1);
      }
    }
    return m;
  }

  Future<void> _saveBindings(Map<String, String> m) async {
    final entries = [for (final e in m.entries) '${e.key}=${e.value}'];
    try {
      final dir = await getApplicationSupportDirectory();
      await File('${dir.path}/$_bindingMirrorFile')
          .writeAsString(jsonEncode(entries));
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_bindingKey, entries);
    } catch (_) {}
  }

  @override
  Future<void> bindDevice(String deviceId, String token) async {
    final m = await _loadBindings();
    m[deviceId] = token;
    await _saveBindings(m);
  }

  @override
  Future<String?> loadTokenForDevice(String deviceId) async =>
      (await _loadBindings())[deviceId];

  /// [2026-11-11 Blue 令] 指定刪除：撤某顆憑證（含綁定關係）。
  /// 回傳是否真的有刪到。
  Future<bool> revokeToken(String token) async {
    final tokens = await _load();
    final removed = tokens.remove(token);
    if (removed) await _save(tokens);
    final m = await _loadBindings();
    m.removeWhere((_, t) => t == token);
    await _saveBindings(m);
    return removed;
  }

  /// [2026-11-11 Blue 令] 已綁定裝置清單（deviceId→token 摘要，
  /// 供桌面逐顆指定刪除的 UI）。
  Future<Map<String, String>> deviceBindings() async => _loadBindings();
}

// ─────────────────────────────────────────────────────────
// 手機端：token 儲存（介面＋實現）
// ─────────────────────────────────────────────────────────

/// 手機端裝置 token 儲存介面。
/// iOS 正式環境走 Keychain（S4 真機階段接 swift_security storage）；
/// 先以 SharedPreferences 檔（沙箱內）與 Memory 版本支撐 S1 模擬器驗收。
abstract class MobileDeviceTokenStore {
  /// 存某主機（host:port key）的 token。
  Future<void> save(String hostKey, String token);

  /// 讀某主機的 token；無則 null。
  Future<String?> load(String hostKey);

  /// 清除（解綁/重鑄用）。
  Future<void> clear(String hostKey);
}

/// 記憶體版（測試）。
class MemoryMobileTokenStore implements MobileDeviceTokenStore {
  final Map<String, String> _map = {};

  @override
  Future<void> save(String hostKey, String token) async =>
      _map[hostKey] = token;

  @override
  Future<String?> load(String hostKey) async => _map[hostKey];

  @override
  Future<void> clear(String hostKey) async => _map.remove(hostKey);
}

/// SharedPreferences 版（S1 模擬器；S4 換 Keychain）。
class SharedPrefsMobileTokenStore implements MobileDeviceTokenStore {
  static const _keyPrefix = 'bridge_paired_token_';

  @override
  Future<void> save(String hostKey, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyPrefix$hostKey', token);
  }

  @override
  Future<String?> load(String hostKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_keyPrefix$hostKey');
  }

  @override
  Future<void> clear(String hostKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$hostKey');
  }
}
