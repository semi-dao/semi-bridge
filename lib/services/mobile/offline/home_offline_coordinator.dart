// 離線行為協調器（Home Offline Coordinator）——狀態機＋佇列＋快照的黏合層
// [T4 2026-11-09] 依據 BRIDGE_MOBILE_SPEC.md v0.5 §7 離線行為拍板（Blue 2026-10-30）
//
// SPEC 條款 4 原文：「離線排隊的訊息，重連後依序自動送出、不吞訊息」
//
// 流程：
// - 離線時 [enqueue] → 進佇列（不吞、不假送）。
// - 收到 [HomeConnectionEvent.reconnect] → 轉為 online → 自動 flush 佇列（依序）。
// - flush 失敗 → 該則留在佇列（下次重連再送）。
//
// 純函數核心：無 UI、無網路、無 DB。

import 'package:bridge_app/services/mobile/offline/home_snapshot.dart';
import 'package:bridge_app/services/mobile/offline/home_state_machine.dart';
import 'package:bridge_app/services/mobile/offline/home_view_state.dart';
import 'package:bridge_app/services/mobile/offline/offline_message_queue.dart';

/// 離線行為協調器。
class HomeOfflineCoordinator {
  /// 連線狀態機。
  final HomeStateMachine machine;

  /// 離線訊息佇列。
  final OfflineMessageQueue queue;

  /// 送出回呼（離線期間不被呼叫；重連 flush 時才呼叫）。
  final MessageSender? sender;

  /// 上次快照（可事後更新）。
  HomeSnapshot? snapshot;

  HomeOfflineCoordinator({
    HomeStateMachine? machine,
    OfflineMessageQueue? queue,
    this.sender,
    this.snapshot,
  })  : machine = machine ?? HomeStateMachine(),
        queue = queue ?? OfflineMessageQueue();

  /// 目前的誠實視圖狀態。
  HomeViewState get viewState => HomeViewState(
        connection: machine.state,
        snapshot: snapshot,
      );

  /// 離線時把訊息排進佇列（不吞、不假送）。
  ///
  /// 已連線時回傳 false（此時應直接走正常送出路徑）。
  bool enqueue(String text) {
    if (machine.isOnline) return false;
    queue.enqueue(text);
    return true;
  }

  /// 送入連線事件；若轉為 online → 自動依序 flush 佇列。
  ///
  /// 回傳 flush 結果；未觸發 flush 時回傳 [FlushResult.none]
  /// （[sent] 為空、[failed] 為 null、[remaining] 為當下佇列殘留）。
  Future<FlushResult> handleEvent(HomeConnectionEvent event) async {
    final accepted = machine.dispatch(event);
    if (!accepted) return FlushResult.none(remaining: queue.pending);
    if (machine.state != HomeConnectionState.online) {
      return FlushResult.none(remaining: queue.pending);
    }

    final send = sender;
    if (send == null) return FlushResult.none(remaining: queue.pending);
    if (queue.isEmpty) return FlushResult.none();

    return queue.flush(send);
  }
}
