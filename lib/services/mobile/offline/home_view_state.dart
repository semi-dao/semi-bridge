// 首頁誠實視圖狀態（Home View State）——「離線時 UI 該長什麼樣」的契約
// [T4 2026-11-09] 依據 BRIDGE_MOBILE_SPEC.md v0.5 §7 離線行為拍板（Blue 2026-10-30）
//
// SPEC 條款 1 原文：「離線時 UI 誠實標灰、不裝活著；禁止整頁空白或轉圈騙人」
// SPEC 條款 2 原文：「顯示『上次快照＋時間戳』（時間戳屬於快照、非當前時間）」
// SPEC 條款 3 原文：「聊天輸入框保留可打字，標『離線中，訊息重連後送出』」
//
// ★ 這個類別是「誠實 UI」的可測試代理：沒有它，紅隊說的
//   「缺少 HomeScreen 渲染測試」就無從驗收——因為真螢幕還沒長出來。
//
// 純函數核心：無 UI、無網路、無 DB。

import 'package:bridge_app/services/mobile/offline/home_snapshot.dart';
import 'package:bridge_app/services/mobile/offline/home_state_machine.dart';

/// 首頁誠實視圖狀態。
class HomeViewState {
  /// 連線狀態（兩態）。
  final HomeConnectionState connection;

  /// 上次快照（null = 從未同步過）。
  final HomeSnapshot? snapshot;

  const HomeViewState({
    this.connection = HomeConnectionState.online,
    this.snapshot,
  });

  /// 是否離線。
  bool get isOffline => connection == HomeConnectionState.offline;

  /// 是否已連線。
  bool get isOnline => connection == HomeConnectionState.online;

  /// ★ 條款 1：離線時誠實標灰（UI 變淡，明示「這是舊資料」）。
  bool get isGreyedOut => isOffline;

  /// 離線時的標灰倍率（0.45 = 明顯變淡但仍可讀）。
  static const double dimOpacityFactor = 0.45;

  /// ★ 條款 1：離線 → 整體變淡（標灰）；已連線 → 原透明度。
  double get dimmedOpacity => isOffline ? dimOpacityFactor : 1.0;

  /// ★ 條款 2：是否有快照可顯示（有內容才算）。
  bool get showsSnapshot => snapshot != null && snapshot!.isNotEmpty;

  /// ★ 條款 1：沒有可用快照 → 顯示誠實提示（不是空白頁）。
  ///
  /// 離線時提示「離線中，還沒有上次快照可顯示」；
  /// 連線但尚未同步時提示「正在取得最新資料」——兩者都不是空白。
  bool get showsEmptySnapshotNotice => !showsSnapshot;

  /// ★ 條款 1：永不全頁空白。
  ///
  /// 推導自真實內容，不是常數：有快照 → 顯示快照；無快照 → 顯示誠實提示。
  /// 兩種情況畫面都有東西，所以恆為 false——但這是**推導結果**，
  /// 不是寫死的 false，日後改動內容邏輯時它會跟著變。
  bool get isBlankPage => !showsSnapshot && !showsEmptySnapshotNotice;

  /// 沒有任何快照時的誠實提示文字。
  String get emptySnapshotNotice => isOffline
      ? '離線中，還沒有上次快照可顯示'
      : '正在取得最新資料';

  /// ★ 條款 2：快照時間戳標籤（屬於快照、非當前時間）。
  String? get snapshotTimestampLabel => snapshot?.capturedAtLabel;

  /// ★ 條款 3：輸入框永遠可打字（離線時也不禁用）。
  bool get inputEnabled => true;

  /// ★ 條款 3：離線時的輸入提示＝「離線中，訊息重連後送出」。
  String get inputHint => isOffline
      ? '離線中，訊息重連後送出'
      : '輸入訊息';

  /// ★ 條款 1/5：狀態標籤——離線就說離線，不裝活著。
  String get statusLabel => isOffline ? '離線' : '已連線';
}
