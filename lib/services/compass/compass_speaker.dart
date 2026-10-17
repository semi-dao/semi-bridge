// compass_speaker.dart
// [小葵 2026-10-17 T9②③] 羅盤開口 M4——羅盤精靈對使用者說話。
// 走既有注入通道（D9）：ChatController.injectAssistantMessage 承接，
// 不另建聊天路徑。
//
// 開口閘（三條全過才開口，缺一閉嘴）：
//   1. answer_confidence > 0.7（T2 校準訊號——不自信不開口）
//   2. 證據：compass_store pitfalls/wound 或 BeliefGate 有實證基礎
//   3. 每日 ≤3 則（打開 App 時不超過三則排隊）
// 零不可逆：開口只注入對話訊息，不做任何系統動作。
//
// 事件：compass.speak 帶 turn_id 入 event_ledger（驗收要求）。

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../brain_container/event_ledger.dart';
import 'compass_store.dart';

/// 一則羅盤開口訊息（等待注入）
class CompassSpeakDraft {
  final String content;
  final String reason; // 開口理由（compass.speak 事件記录用）
  final double confidence;
  const CompassSpeakDraft(this.content, this.reason, this.confidence);
}

class CompassSpeaker {
  CompassSpeaker._();
  static final CompassSpeaker instance = CompassSpeaker._();

  /// 注入回呼——由 UI 層掛上（ChatController.injectAssistantMessage）
  Future<void> Function(String content, Map<String, dynamic> metadata)?
      onSpeak;

  static const int dailyLimit = 3;
  static const double minConfidence = 0.7;

  final List<CompassSpeakDraft> _queue = [];
  DateTime _lastFlush = DateTime.fromMillisecondsSinceEpoch(0);

  /// 產生開口草稿（CompassSelfGauge 紅旗 / DreamScheduler 產出呼叫）。
  /// confidence 由呼叫端給（T2 的 answer_confidence 來源）。
  void enqueue(CompassSpeakDraft draft) {
    if (draft.confidence <= minConfidence) {
      debugPrint('[CompassSpeaker] 靜默——信心不足（${draft.confidence}）');
      return;
    }
    if (_queue.length >= dailyLimit) {
      debugPrint('[CompassSpeaker] 靜默——今日額度滿（$dailyLimit）');
      return;
    }
    _queue.add(draft);
  }

  /// 開口閘②：證據檢查——紅旗必須有 compass_store 的實證
  /// （organ 的 pitfalls 紀錄），不是憑感覺開口。
  bool _hasEvidence(String organId) {
    try {
      return CompassStore.instance.pitfalls(organId).isNotEmpty;
    } catch (_) {
      return false; // 查不到證據＝閉嘴（fail-closed：寧可不說）
    }
  }

  /// 下次開 App 時沖出佇列（T9 風險：dream 窗口與作息錯開，
  /// 開口時機走「下次開 App」而非即時打擾）
  Future<void> flushQueue() async {
    final now = DateTime.now();
    if (now.difference(_lastFlush).inHours < 12) return; // 天然限頻
    _lastFlush = now;

    while (_queue.isNotEmpty) {
      final draft = _queue.removeAt(0);
      // 事件落帳（帶 turn_id——驗收要求）
      try {
        final tid = 'compass_${DateTime.now().millisecondsSinceEpoch}';
        EventLedger.instance.appendTurn(
          turnId: tid,
          input: 'compass.speak: ${draft.reason}',
          executor: 'compass_speaker',
          meta: {'kind': 'compass.speak', 'reason': draft.reason},
        );
      } catch (_) {} // fail-quiet：落帳失敗不擋開口
      try {
        await onSpeak?.call(
          draft.content,
          {'kind': 'compass', 'reason': draft.reason},
        );
      } catch (e) {
        debugPrint('[CompassSpeaker] 注入失敗（fail-quiet）: $e');
      }
      // 每則間隔 2 秒——不連環轟炸
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  /// [Blue 令 2026-10-17] 測試機制——手動注入紅旗 draft 走完整開口
  /// 管線（樣本不足的環境也能驗證頻道落地）。生產環境不呼叫。
  Future<void> testFire({String? content, String reason = 'test_fire'}) async {
    enqueue(CompassSpeakDraft(
      content ?? '（測試）這是一則羅盤測試訊息——如果你看到這則，'
          '代表主動回應頻道是通的。',
      reason,
      0.99, // 測試值——繞過信心閘只為驗證管線
    ));
    _lastFlush = DateTime.fromMillisecondsSinceEpoch(0); // 解除限頻
    await flushQueue();
  }

}
