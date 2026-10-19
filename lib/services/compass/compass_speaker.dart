// compass_speaker.dart
// [小葵 2026-10-17 T9②③] 羅盤開口 M4——羅盤精靈對使用者說話。
// 走既有注入通道（D9）：ChatController.injectAssistantMessage 承接，
// 不另建聊天路徑。
//
// [T12-③ 2026-10-17] 投遞六修（Fable V3 器官八：有嘴但接的是測試線）：
//   1. 佇列落 compass_store（compass_meta key=speak_queue）——原本只在
//      記憶體：App 持續運行時入列的訊息永遠不沖、重啟即蒸發
//   2. 前景 flush——WidgetsBindingObserver resumed 時沖（不只開機 45 秒）
//   3. 證據閘通電——enqueue 帶 organId，pitfalls 有實證才排隊
//      （_hasEvidence 原本定義了從未被呼叫）
//   4. 真信心——dream 入列信心改從紅旗數推導（dream_scheduler 端），
//      測試路徑 0.99 只走 test_fire（debug 旗保護）
//   5. 額度改當日累計（原本看佇列當下長度＝額度永遠夠）
//   6. test_fire debug 旗——BRIDGE_TEST_FIRE=1 才通（原本是正式路由上
//      任意文字注入注入口——Fable V3 安全紅旗）
//
// 開口閘（三條全過才開口，缺一閉嘴）：
//   1. 信心 > 0.7
//   2. 證據：compass_store pitfalls 有實證（organ 級）
//   3. 每日 ≤3 則（當日落帳累計，不是佇列長度）
// 零不可逆：開口只注入對話訊息，不做任何系統動作。
//
// 事件：compass.speak 帶 turn_id 入 event_ledger（驗收要求）。

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../brain_container/event_ledger.dart';
import 'compass_store.dart';

/// 一則羅盤開口訊息（等待注入）
class CompassSpeakDraft {
  final String content;
  final String reason; // 開口理由（compass.speak 事件記录用）
  final double confidence;
  /// [T12-③] 證據主體——紅旗屬於哪個 organ（pitfalls 查證用）。
  /// null＝免證據（僅 test_fire）。
  final String? organId;
  const CompassSpeakDraft(this.content, this.reason, this.confidence,
      {this.organId});
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

  /// [T12-③] 當日落帳累計（額度真相源：compass_meta key=speak_spoken_today）
  String get _todayKey {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  int _spokenToday() {
    try {
      final meta = CompassStore.instance.getMeta('speak_spoken_on');
      if (meta != _todayKey) return 0; // 跨日重置
      final n = CompassStore.instance.getMeta('speak_spoken_count');
      return n == null ? 0 : int.tryParse(n) ?? 0;
    } catch (_) {
      return 0; // store 未開——保守 0（不擋第一次）
    }
  }

  void _bumpSpoken() {
    try {
      final store = CompassStore.instance;
      store.setMeta('speak_spoken_on', _todayKey);
      store.setMeta('speak_spoken_count', '${_spokenToday() + 1}');
    } catch (_) {} // fail-quiet
  }

  // ── 佇列持久化（compass_meta key=speak_queue）─────────────────
  void _persistQueue() {
    try {
      final j = jsonEncode([
        for (final d in _queue)
          {
            'content': d.content,
            'reason': d.reason,
            'confidence': d.confidence,
            if (d.organId != null) 'organ_id': d.organId,
          }
      ]);
      CompassStore.instance.setMeta('speak_queue', j);
    } catch (_) {} // fail-quiet：落盤失敗不擋記憶體佇列
  }

  /// 啟動時載回上次沒沖完的佇列（冪等：只在記憶體佇列空時載）
  void _restoreQueue() {
    if (_queue.isNotEmpty) return;
    try {
      final j = CompassStore.instance.getMeta('speak_queue');
      if (j == null || j.isEmpty) return;
      final list = jsonDecode(j) as List;
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        _queue.add(CompassSpeakDraft(
          m['content'] as String,
          m['reason'] as String,
          (m['confidence'] as num).toDouble(),
          organId: m['organ_id'] as String?,
        ));
      }
      if (_queue.isNotEmpty) {
        debugPrint('[CompassSpeaker] 佇列還原 ${_queue.length} 則（跨重啟）');
      }
    } catch (_) {} // fail-quiet
  }

  /// 產生開口草稿（CompassSelfGauge 紅旗 / DreamScheduler 產出呼叫）。
  /// [T12-③] 三閘全在這裡：信心、證據（organId→pitfalls）、當日額度。
  /// 過閘才入列＋落盤；不過閘靜默丟棄（log 留痕）。
  void enqueue(CompassSpeakDraft draft) {
    // 閘①：信心
    if (draft.confidence <= minConfidence) {
      debugPrint('[CompassSpeaker] 靜默——信心不足（${draft.confidence}）');
      return;
    }
    // 閘②：證據（organ 級 pitfalls 實證；null＝僅 test_fire 免證據）
    final organ = draft.organId;
    if (organ != null && !_hasEvidence(organ)) {
      debugPrint('[CompassSpeaker] 靜默——organ $organ 無 pitfalls 實證');
      return;
    }
    // 閘③：當日額度（落帳累計，非佇列長度）
    if (_spokenToday() >= dailyLimit) {
      debugPrint('[CompassSpeaker] 靜默——今日額度滿（$dailyLimit）');
      return;
    }
    _queue.add(draft);
    _persistQueue(); // [T12-③] 立即落盤——重啟不蒸發
  }

  /// [殘件① 2026-10-19] 帶回值的 enqueue——回 true=真的入列、
  /// false=被閘擋下（呼叫端據此決定要不要記帳重試）。
  bool tryEnqueue(CompassSpeakDraft draft) {
    // 與 enqueue 同閘；為避免兩份閘邏輯漂移，這裡只做「預檢＋委託」：
    // 先驗三閘（與 enqueue 逐條對應），過了才呼叫 enqueue。
    if (draft.confidence <= minConfidence) return false;
    final organ = draft.organId;
    if (organ != null && !_hasEvidence(organ)) return false;
    if (_spokenToday() >= dailyLimit) return false;
    enqueue(draft);
    return true;
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

  /// 沖出佇列。呼叫時機（T12-③ 擴充）：
  ///   - App 啟動後 45 秒（app.dart 原有）
  ///   - **前景 resumed**（WidgetsBindingObserver——主動訊息等的就是使用者
  ///     回來看，開機 45 秒唯一窗口的病根修復）
  /// [limitHours] 限頻：正式沖出 12h 一次；[force] true 時忽略限頻（前景
  /// resumed 用 1h 較短限頻——頻繁切換不轟炸）。
  Future<void> flushQueue({bool force = false}) async {
    _restoreQueue(); // 先還原（冷啟動後首次沖出前）
    final now = DateTime.now();
    if (!force && now.difference(_lastFlush).inHours < 12) return; // 天然限頻
    if (force && now.difference(_lastFlush).inHours < 1) return; // 前景短限頻
    _lastFlush = now;

    while (_queue.isNotEmpty) {
      final draft = _queue.removeAt(0);
      _persistQueue(); // 沖一則存一次——中途崩潰不重複注入
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
        _bumpSpoken(); // 注入成功才計額度
      } catch (e) {
        debugPrint('[CompassSpeaker] 注入失敗（fail-quiet）: $e');
      }
      // 每則間隔 2 秒——不連環轟炸
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  /// [T12-③ test] 測試隔離用——清空記憶體佇列與限頻時鐘。
  /// singleton 跨測試殘留佇列會讓後續測試沖到別則的 draft。
  @visibleForTesting
  void resetForTest() {
    _queue.clear();
    _lastFlush = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// [Blue 令 2026-10-17] 測試機制——手動注入紅旗 draft 走完整開口
  /// 管線（樣本不足的環境也能驗證頻道落地）。
  /// [T12-③] debug 旗保護——BRIDGE_TEST_FIRE=1 才通（launchctl setenv /
  /// flutter run --dart-define 皆可）。原本無保護＝正式路由上的注入口
  /// （Fable V3 安全紅旗：任意文字以 assistant 身分注入）。
  Future<void> testFire({String? content, String reason = 'test_fire'}) async {
    if (!kDebugMode &&
        Platform.environment['BRIDGE_TEST_FIRE'] != '1') {
      debugPrint('[CompassSpeaker] test_fire 拒絕——非 debug 環境且未設 '
          'BRIDGE_TEST_FIRE=1（T12-③ 注入口上鎖）');
      return;
    }
    enqueue(CompassSpeakDraft(
      content ?? '（測試）這是一則羅盤測試訊息——如果你看到這則，'
          '代表主動回應頻道是通的。',
      reason,
      0.99, // 測試值——繞過信心閘只為驗證管線（僅 debug/旗標環境）
    ));
    _lastFlush = DateTime.fromMillisecondsSinceEpoch(0); // 解除限頻
    await flushQueue();
  }

}
