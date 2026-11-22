// 手機自動重連引導（Auto Reconnect Bootstrap）
// [S4 2026-11-11 Blue 抓包] 配對好一次就不用再配對——但 reconnectWithToken
// 寫好後沒人呼叫，App 重啟＝永遠離線。本檔補上「啟動即憑 token 回家」。
//
// 流程：
// 1. 讀 PairedDesktopStore（最近配對的桌面）
// 2. 讀該桌機的 token（[刀①] did key 單一真相源，見 mobile_token_access.dart）
// 3. 兩者皆有 → reconnectWithToken（不重掃 QR）
// 4. token 失效（桌面回錯）→ 留在離線，配對頁會引導重掃（寧紅字不假成功）
//
// 設計鐵則：誠實——回報真實結果，不裝連上。

import 'package:flutter/foundation.dart' show debugPrint; // [2026-11-20 sticky 端點直攻]
import 'package:bridge_app/services/mobile_bridge_client.dart';
import 'package:bridge_app/services/mobile/mobile_token_access.dart';
import 'package:bridge_app/services/mobile/sticky_endpoint_memory.dart'; // [2026-11-20 sticky 端點直攻]
import 'package:bridge_app/services/paired_desktop_store.dart';

/// App 啟動時呼叫一次。回 true=已發起 token 重連。
Future<bool> bootstrapAutoReconnect() async {
  final desktops = await PairedDesktopStore.getAll();
  if (desktops.isEmpty) return false;

  // 最近配對的優先
  final desktop = desktops.reduce((a, b) => a.pairedAt.isAfter(b.pairedAt) ? a : b);
  // [刀① 2026-11-19] token 綁 desktopId：did key 直讀，查無自動遷移掃舊
  // per-host key 並提升寫入 did key（mobile_token_access.loadTokenFor）。
  final token = await loadTokenFor(desktop);
  if (token == null) return false;

  // [SPEC §6.3] 先恢復中繼設定（出門通道），再 token 重連（內部自動爬樓梯）
  await MobileBridgeClient.instance.loadRelay();

  // [11-16 出門直連] 逐候選試——在家走 LAN IP，出門 4G 走 IPv6 直連。
  // [刀①] token 是 gateway 簽的裝置憑證，跨端點通用，且現在全端點同一顆
  // （did key 單一真相源）——所有候選共用同一份 token，不再按 host 各讀各的。
  // [2026-11-20 sticky 端點直攻] 上次成功端點排第一位直攻——不再每次都從
  // 死 LAN 門牌吃 8s 逾時才輪到 v6。last-good 不在候選集／已失效（連敗
  // 2 次）時原順序不動，lan→v6→tailscale 保留為 fallback。
  MobileBridgeClient.instance.setAltHosts(desktop.altHosts);
  final lastGood = await StickyEndpointMemory.loadLastGoodHost();
  final orderedHosts =
      StickyEndpointMemory.orderByLastGood(desktop.allHosts, lastGood);
  if (lastGood != null && orderedHosts.first == lastGood) {
    debugPrint('[Bootstrap] sticky 直攻上次成功端點: $lastGood');
  }
  for (final host in orderedHosts) {
    final ok = await MobileBridgeClient.instance.reconnectWithToken(
      host: host,
      port: desktop.port,
      deviceToken: token,
    );
    if (ok) {
      // 連上即確認 did key 有效（token 已由 loadTokenFor 收斂於 did key）
      return true;
    }
  }
  return false;
}
