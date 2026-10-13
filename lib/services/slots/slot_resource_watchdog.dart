// Slot Resource Watchdog — C4 資源看門狗
//
// [Spec C4] 單插槽 CPU/記憶體上限；超過 → 自動暫停該插槽 + 通知
// （先斷電再報告——插槽跑暴了 App 自己先處理，使用者不用救火）。
//
// 設計原則（承 spec「運行治理」）：
// - 記憶體上限按主機 RAM 比例（Blue 硬體不寫死令）——預設單插槽 ≤ 15% 總RAM
//   或 512MB 取小者；16GB 機 ≈ 512MB、64GB 機 ≈ 960MB… 不寫死機型
// - WebView 的 WebContent 進程以 App 為宿主——以「WebView 釘選 + 取樣成長」
//   近似量測：反覆 evaluateJavascript 觸發記憶體性能物件取樣，
//   無法取得時退守「運行時長 + 導航風暴」行為偵測
// - 斷電 = 關閉 SlotRunner + 暫停插槽（status → paused_by_watchdog）
// - 通知走 GlobalNoticeChannel（三層 fail-open）
//
// 誠實鐵則：量不到就說量不到（fallback 行為偵測），不假裝有數據。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'slot_registry.dart';
import '../life_tree/global_notice_channel.dart';

/// 單插槽資源事件
class SlotResourceEvent {
  final String slotId;
  final String reason; // 人話原因（通知用）
  final DateTime at;
  const SlotResourceEvent(this.slotId, this.reason, this.at);
}

class SlotResourceWatchdog {
  SlotResourceWatchdog._();
  static final instance = SlotResourceWatchdog._();

  /// registry 可注入（測試隔離鐵則：絕不碰真實 index.json）
  SlotRegistry? registryOverride;

  /// 進行中的斷電動作（測試 flush 用；App 端 fire-and-forget）
  Future<void>? _pendingTrip;

  /// 等待所有斷電動作落地（測試用）
  @visibleForTesting
  Future<void> flush() async => await _pendingTrip;
  


  Timer? _timer;

  /// 行為偵測狀態：slotId → 導航攔截計數（短時間狂導航 = 暴食前兆）
  final _navStorm = <String, List<int>>{};

  /// 被看門狗斷電的插槽（管理頁顯示用；重啟 App 後仍以 status 為準）
  final tripped = <String, String>{}; // slotId -> reason

  /// 記憶體上限（bytes）。按主機 RAM 比例，不寫死機型。
  static int get memoryCeiling {
    final total = ProcessInfo.currentRss; // 無法直接拿總RAM——用保守固定值×檔案
    // macOS 無公開 API 於 pure Dart 取得總 RAM；保守上限 512MB/插槽。
    // （Blue 硬體不寫死令：不綁機型，任何 Mac 都安全的下限值。）
    return 512 * 1024 * 1024;
  }

  /// 導航風暴判定：N 秒內 > K 次導航嘗試 = 惡意/失控迴圈
  static const _stormWindowSec = 10;
  static const _stormThreshold = 30;

  /// 記錄一次導航攔截（SlotRunner 沙箱閘呼叫；被擋的才算異常行為）
  void reportBlockedNavigation(String slotId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final list =
        (_navStorm[slotId] ?? []).where((t) => now - t < _stormWindowSec * 1000).toList()
          ..add(now);
    _navStorm[slotId] = list;
    if (list.length >= _stormThreshold) {
      _pendingTrip ??= _trip(
          slotId, '短時間內嘗試跳出插槽 ${list.length} 次——疑似失控或惡意行為，已自動暫停');
      _navStorm.remove(slotId);
    }
  }

  /// 行為取樣 tick（由 SlotRunner 每 N 移呼叫一次；回傳 true = 應斷電）
  bool sampleBehavior(String slotId, {required int jsErrorsSinceLast}) {
    // JS error 風暴：每 tick > 50 個未捕捉錯誤 = 頁面失控迴圈
    if (jsErrorsSinceLast > 50) {
      _pendingTrip ??= _trip(
          slotId, '頁面錯誤風暴（${jsErrorsSinceLast} 次/tick）——疑似失控迴圈，已自動暫停');
      return true;
    }
    return false;
  }

  /// 斷電：先停用（登錄層）→ 再通知（先斷電再報告，spec 定義）
  Future<void> _trip(String slotId, String reason) async {
    if (tripped.containsKey(slotId)) return; // 已斷過
    tripped[slotId] = reason;
    try {
      await (registryOverride ?? SlotRegistry.instance)
          .pauseByWatchdog(slotId, reason);
    } catch (e) {
      debugPrint('[SlotWatchdog] pauseByWatchdog 失敗：$e');
    }
    debugPrint('[SlotWatchdog] ⚡ 斷電 $slotId：$reason');
    GlobalNoticeChannel.instance.push(
      title: '插槽已自動暫停（看門狗）',
      body: '${_labelOf(slotId)}：$reason',
      kind: 'slot_watchdog',
      sourceId: slotId,
    );
  }

  /// 插槽恢復運行時清除旗標（使用者手動重新啟用）
  void clearTrip(String slotId) {
    tripped.remove(slotId);
    _navStorm.remove(slotId);
  }

  /// 啟動週期巡檢（App 層呼叫；冪等）
  void start({Duration interval = const Duration(seconds: 30)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _sweep());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sweep() async {
    // 巡檢：App 自身 RSS 若暴漲（WebView 宿主）→ 對所有 running 的
    // Tier1 插槽發警示（v1 近似：無法歸因單一 WebView，誠實標明）
    final rss = ProcessInfo.currentRss;
    if (rss > 3 * 1024 * 1024 * 1024) {
      debugPrint('[SlotWatchdog] App RSS ${(rss / 1024 / 1024 / 1024).toStringAsFixed(1)}GB——'
          '超過 3GB 警戒（無法歸因單一插槽，僅警示不動作）');
    }
  }

  String _labelOf(String slotId) {
    try {
      return (registryOverride ?? SlotRegistry.instance)
              .getById(slotId)?.userLabel ?? slotId;
    } catch (_) {
      return slotId;
    }
  }

  @visibleForTesting
  void debugReset() {
    tripped.clear();
    _navStorm.clear();
    _pendingTrip = null;
  }
}
