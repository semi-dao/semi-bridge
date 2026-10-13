// Slot Permission Gate — C4 權限執行閘
//
// [Spec C4] 權限系統接 DataPathGate：綠自動放行／黃紅全域對話點頭。
// 插槽的 permissions（[] = 純本地 / [network] = 網路唯讀 /
// [network, file] = 完整）在「執行層」真正生效——不是記錄好看的。
//
// 執行模型（Tier 1 WebView 沙箱）：
// - 插槽內部導航（file://）→ 一律放行（沙箱邊界另由 SlotRunner 導航閘管）
// - 對外請求（http/https）→ 依權限：
//     無 network 權限 → 攔截（回傳 deny）＋記一筆主權帳（red）
//     有 network 權限 → 記帳（yellow：第三方網域）後放行
// - 每插槽帳本走 DataPathGate.record（SovereigntyEntry）——
//   使用者在主權總覽看得到「哪個插槽、對外抓了什麼」
//
// 誠實鐵則：WebView 的子資源請求（XHR/fetch/img）在 WKWebView 無法逐條
// 攔截（只有主導航 shouldOverrideUrlLoading）——v1 能擋的是「頁面跳轉級」
// 請求；XHR 級靠紅隊掃描（安裝時）＋靜態權限標記的「知情」層。
// 未來 Tier 2（WASM）才能能力制逐條攔截。此邊界誠實標明。

import 'package:flutter/foundation.dart';

import '../sovereignty/data_path_gate.dart';
import 'slot_registry.dart';

class SlotPermissionGate {
  SlotPermissionGate._();
  static final instance = SlotPermissionGate._();

  /// 檢查一條即將發生的請求（導航級）。回傳 true = 放行。
  Future<bool> checkNavigation({
    required String slotId,
    required String url,
  }) async {
    final slot = (registryOverride ?? SlotRegistry.instance).getById(slotId);
    if (slot == null) return false;

    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    // 檔案系統（插槽內）→ 沙箱導航閘管，這裡放行
    if (!uri.hasScheme || uri.isScheme('file')) return true;

    // 對外請求 → 看 network 權限
    final hasNetwork = slot.permissions.contains('network');
    if (!hasNetwork) {
      debugPrint('[SlotPermGate] 🔴 攔截對外導航（無 network 權限）：$url');
      await _record(slot, url, blocked: true);
      return false;
    }

    // 有權限 → 記帳後放行（yellow：插槽第三方流量）
    await _record(slot, url, blocked: false);
    return true;
  }

  Future<void> _record(SlotRecord slot, String url, {required bool blocked}) async {
    try {
      final gate = DataPathGate.instance;
      await gate.record(SovereigntyEntry(
        endpointHost: Uri.tryParse(url)?.host ?? url,
        dataClass: DataPathClass.webTraffic,
        payloadBytes: 0,
        purpose: DataPathPurpose.slotWeb,
        keySource: blocked ? 'none' : 'slot_grant',
        grade: blocked ? DataPathGrade.red : DataPathGrade.yellow,
        ts: DateTime.now(),
      ));
      debugPrint('[SlotPermGate] 已記主權帳（${blocked ? "red 攔截" : "yellow 放行"}）：'
          '${slot.userLabel} → $url');
    } catch (e) {
      // 記帳失敗不放行失敗——fail-closed 對攔截、fail-open 對記帳
      debugPrint('[SlotPermGate] 主權記帳失敗（fail-open）: $e');
    }
  }

  /// 測試注入（隔離鐵則）
  SlotRegistry? registryOverride;

  @visibleForTesting
  void debugReset() {
    registryOverride = null;
  }
}
