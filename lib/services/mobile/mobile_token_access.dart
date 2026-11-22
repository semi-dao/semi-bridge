// mobile_token_access.dart
// [2026-11-19 刀①] 裝置 token 存取單一咽喉——key 綁 desktopId（一機一筆，
// 同一台桌機一份 token）。舊版按 host:port 各存一份：重配對後新 token 只
// 落在 LAN key，v6 key 躺著殭屍舊 token，讀到就被 hello 打 re-pair。
// 所有 token 讀寫一律經過本檔——漏一處都是洞（grep SharedPrefsMobileTokenStore
// 在 lib/ 的直接呼叫只應剩本檔與測試注入點）。

import 'package:bridge_app/services/mobile/mobile_device_token_store.dart';
import 'package:bridge_app/services/paired_desktop_store.dart';

/// 該桌機的 token key：有 did（QR did 一機一筆制）用 did key；
/// 舊 QR（無 did，desktopId 空字串）退回 host:port 舊邏輯，不炸。
String mobileTokenKey(PairedDesktop d) =>
    d.desktopId.isNotEmpty ? 'did:${d.desktopId}' : '${d.host}:${d.port}';

/// 讀該桌機的 token：先讀 did key；查無時遷移相容——掃舊 per-host key
/// （desktop.host 與 desktop.altHosts 各自的 host:port key），
/// 找到任一份即提升寫入 did key（之後收斂為單一真相源）。
Future<String?> loadTokenFor(PairedDesktop d) async {
  final store = SharedPrefsMobileTokenStore();
  final key = mobileTokenKey(d);
  final direct = await store.load(key);
  if (direct != null) return direct;
  if (d.desktopId.isNotEmpty) {
    // 遷移：舊版 host:port key 逐個掃（host 優先，alts 依序）
    for (final host in d.allHosts) {
      final legacy = await store.load('$host:${d.port}');
      if (legacy != null) {
        // 提升寫入 did key——下次起 direct hit，殭屍舊 key 不再被讀到
        await store.save(key, legacy);
        return legacy;
      }
    }
  }
  return null;
}

/// 存該桌機的 token：寫 did key（無 did 時退回 host:port key）。
Future<void> saveTokenFor(PairedDesktop d, String token) async {
  await SharedPrefsMobileTokenStore().save(mobileTokenKey(d), token);
}
