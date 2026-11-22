// 連線狀態機（Home State Machine）——手機版離線行為的連線狀契約
// [T4 2026-11-09] 依據 BRIDGE_MOBILE_SPEC.md v0.5 §7 離線行為拍板（Blue 2026-10-30）
//
// SPEC 條款 5 原文：「連線狀態只有 online/offline 兩態（不偽裝第三態）」
//
// ★ 設計紀律：狀態只有兩個值。任何 loading / reconnecting / unknown 皆為
//   偽裝第三態——一旦允許，UI 就會出現「假裝活著」的轉圈畫面，違反 §7 誠實鐵則。
//   重連過程屬於「事件」（[HomeConnectionEvent.reconnect]），不是狀態。
//
// 轉移規則（非法轉移拒絕並記錄，不靜默吞掉）：
//   online  ＋ disconnect → offline（合法）
//   online  ＋ timeout   → offline（合法）
//   offline ＋ reconnect  → online （合法）
//   online  ＋ reconnect  → 拒絕（已在線上，不需重連）
//   offline ＋ disconnect → 拒絕（已離線，不重複斷）
//   offline ＋ timeout   → 拒絕（已離線，不重複逾時）
//
// 純函數核心：無 UI、無網路、無 DB。

/// 連線狀態——只有兩態（SPEC §7 條款 5）。
enum HomeConnectionState {
  /// 已連線。
  online,

  /// 已離線。
  offline,
}

/// 連線事件——驅動狀態機轉移。
enum HomeConnectionEvent {
  /// 主動斷線／通道關閉。
  disconnect,

  /// 心跳逾時。
  timeout,

  /// 重連握手成功。
  reconnect,
}

/// 一次狀態轉移的結果記錄（合法與非法皆留痕）。
class HomeTransitionRecord {
  /// 事件發生前的狀態。
  final HomeConnectionState from;

  /// 事件發生後的狀態（被拒時 == [from]）。
  final HomeConnectionState to;

  /// 觸發事件。
  final HomeConnectionEvent event;

  /// 此轉移是否被接受。
  final bool accepted;

  /// 被拒時的原因說明（接受時為 null）。
  final String? reason;

  const HomeTransitionRecord({
    required this.from,
    required this.to,
    required this.event,
    required this.accepted,
    this.reason,
  });

  @override
  String toString() => 'HomeTransitionRecord(${event.name}: '
      '${from.name}→${to.name}, accepted: $accepted'
      '${reason == null ? '' : ', reason: $reason'})';
}

/// 首頁連線狀態機——兩態、明確轉移、非法轉移留痕。
class HomeStateMachine {
  final List<HomeTransitionRecord> _history = [];

  HomeConnectionState _state;

  /// 建立狀態機。[initial] 預設 online。
  HomeStateMachine({
    HomeConnectionState initial = HomeConnectionState.online,
  }) : _state = initial;

  /// 目前狀態。
  HomeConnectionState get state => _state;

  /// 是否已連線。
  bool get isOnline => _state == HomeConnectionState.online;

  /// 是否已離線。
  bool get isOffline => _state == HomeConnectionState.offline;

  /// 全部轉移記錄（含被拒者，依時間順序）。
  List<HomeTransitionRecord> get history => List.unmodifiable(_history);

  /// 被拒的轉移記錄（只含被拒者，依時間順序）。
  List<HomeTransitionRecord> get rejectedTransitions =>
      List.unmodifiable(_history.where((r) => !r.accepted));

  /// 送入事件；回傳是否被接受。
  ///
  /// 非法轉移：狀態不變、記錄進 [rejectedTransitions]。
  bool dispatch(HomeConnectionEvent event) {
    final from = _state;
    final target = _targetFor(from, event);

    if (target == null) {
      _history.add(HomeTransitionRecord(
        from: from,
        to: from,
        event: event,
        accepted: false,
        reason: _rejectReason(from, event),
      ));
      return false;
    }

    _state = target;
    _history.add(HomeTransitionRecord(
      from: from,
      to: target,
      event: event,
      accepted: true,
    ));
    return true;
  }

  /// 事件在目前狀態下的合法目標；null 代表非法轉移。
  HomeConnectionState? _targetFor(
    HomeConnectionState from,
    HomeConnectionEvent event,
  ) {
    switch (from) {
      case HomeConnectionState.online:
        switch (event) {
          case HomeConnectionEvent.disconnect:
          case HomeConnectionEvent.timeout:
            return HomeConnectionState.offline;
          case HomeConnectionEvent.reconnect:
            return null; // 已在線上，不需重連
        }
      case HomeConnectionState.offline:
        switch (event) {
          case HomeConnectionEvent.reconnect:
            return HomeConnectionState.online;
          case HomeConnectionEvent.disconnect:
          case HomeConnectionEvent.timeout:
            return null; // 已離線，不重複斷
        }
    }
  }

  /// 被拒原因（可讀字串，測試以 contains 斷言）。
  String _rejectReason(HomeConnectionState from, HomeConnectionEvent event) {
    final stateName = from.name;
    switch (event) {
      case HomeConnectionEvent.reconnect:
        return 'reconnect 事件在 $stateName 態非法：'
            '已連線時不得偽裝重連（SPEC §7 條款 5 只有兩態）';
      case HomeConnectionEvent.disconnect:
        return 'disconnect 事件在 $stateName 態非法：'
            '已離線時不重複斷線';
      case HomeConnectionEvent.timeout:
        return 'timeout 事件在 $stateName 態非法：已離線時不重複逾時';
    }
  }
}
