// [pushSquadChanged 觸發線 2026-11-17] 小隊動態推播接線（fail-open wrapper）
//
// gateway 的 pushSquadChanged()（desktop_bridge_local_gateway.dart）已存在，
// 本檔是 controller 層→gateway 的唯一咽喉：
//   chat_controller 開小隊建檔完成 → pushSquadSpawned（每隊一推）
//   chat_controller 回報卡插入母對話成功 → pushSquadReported
//
// handle 取得方式同 vaultChanged 桌面端推播精神、並採 bridge_mcp_server.dart
// 取 latestGatewayHandle 同款接法（非 UI 檔案經 BridgeDesktopScreen 靜態欄位
// 拿 gateway handle，不引入 chat_controller→screens 直接依賴）。
//
// 鐵則：推播失敗絕不拖垮主流程——全程 try-catch，吞exception只 debugPrint。
// gateway 未啟動（latestGatewayHandle==null，無手機連線的本機開發情境）→
// `?.` 靜默跳過，不視為錯誤。
import 'package:flutter/foundation.dart';

import '../screens/bridge_desktop_screen.dart' show BridgeDesktopScreen;

/// 開小隊建檔完成 → 推 'spawned'（呼叫端每隊推一次）。
void pushSquadSpawned({required String parentId, required String squadId}) {
  _pushSquadChanged(parentId: parentId, event: 'spawned', squadId: squadId);
}

/// 回報卡插入母對話成功 → 推 'reported'。
void pushSquadReported({required String parentId, required String squadId}) {
  _pushSquadChanged(parentId: parentId, event: 'reported', squadId: squadId);
}

void _pushSquadChanged({
  required String parentId,
  required String event,
  required String squadId,
}) {
  try {
    BridgeDesktopScreen.latestGatewayHandle?.pushSquadChanged(
      parentId: parentId,
      event: event,
      squadId: squadId,
    );
  } catch (e) {
    // fail-open：推播是旁路通知，任何異常都不許波及開小隊/插卡主流程。
    debugPrint('[SquadPushHook] squadChanged($event) 推播失敗'
        '（fail-open 不影響主流程）: $e');
  }
}
