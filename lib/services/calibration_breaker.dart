// M3 第三刀——校準熔斷器（2026-10-14）
//
// 藍圖（docs/WEAVE_MAP_V2.md M3）：
//   熔斷：線上某信心區正確率跌破門檻 → 自動降級 NEED_4B；信念可回溯撤銷。
//   驗收：刻意植入錯信念，≤5 次互動內降級。
//
// 訊號源（都已存在）：
//   - EventLedger.onlineCalibration()：信心區（0.0-1.0 每 0.1 一桶）×
//     線上正確率（reaction join turn）
//   - CorrectionCatcher（第一刀）：同主題被反覆糾正＝該主題正確率崩塌的直接證據
//
// 本檔：熔斷決策器。三態（電子熔斷器語意）：
//   CLOSED（正常）→ OPEN（熔斷：該信心區回答一律降級 NEED_4B）
//   → HALF_OPEN（冷卻後試探一發）→ 成功回 CLOSED / 失敗回 OPEN
//
// 信念回溯撤銷：熔斷觸發時，把「促成該信心區」的 L4 信念標記 is_archived=1
// （記憶鐵律：永不刪——撤銷=封存+可回溯，不是刪除）。

import 'package:flutter/foundation.dart';
import 'brain_container/brain_container_service.dart';
import 'brain_container/brain_database.dart';
import 'brain_container/event_ledger.dart';

enum BreakerState { closed, open, halfOpen }

class CalibrationBreaker {
  static final CalibrationBreaker _instance = CalibrationBreaker._();
  static CalibrationBreaker get instance => _instance;
  CalibrationBreaker._();

  /// 每桶最低樣本數（少於此不判——單次壞反應不熔斷）
  /// [小葵 2026-10-15 T2] 3→20：D3 隱式 accepted 帶噪（話題切換≠真接受），
  /// 小樣本下單一糾正就能拉垮正確率——20 筆門檻讓噪聲平均掉。
  static const int minSamples = 20;

  /// 正確率地板：某信心區低於此 → 熔斷該區
  /// 例：信心 0.9 區實際正確率 <0.5 ——模型自high但常常錯＝最危險區
  static const double accuracyFloor = 0.5;

  /// OPEN → HALF_OPEN 冷卻時間
  static const Duration cooldown = Duration(minutes: 10);

  /// 每信心區的熔斷狀態（runtime 鏡像；真相源 circuit_breaker_log）
  final Map<double, BreakerState> _states = {};
  final Map<double, DateTime> _openedAt = {};
  bool _restored = false;

  /// [小葵 2026-10-15 T2] 狀態還原——從 circuit_breaker_log 重建熔斷狀態。
  /// 原本狀態只在記憶體：App 重啟＝熔斷失憶，被降級的信心區復活。
  /// 還原規則：每桶最後一筆動作（trip→open；recovered→closed）。
  void _restoreFromLog() {
    if (_restored) return;
    _restored = true;
    try {
      if (!BrainContainerService.instance.isInitialized) return;
      final db = BrainDatabase.instance.db;
      final rows = db.select('''
        SELECT bucket, action, created_at FROM circuit_breaker_log
        WHERE id IN (SELECT MAX(id) FROM circuit_breaker_log GROUP BY bucket)
      ''');
      for (final r in rows) {
        final b = (r['bucket'] as num).toDouble();
        if (r['action'] == 'trip') {
          _states[b] = BreakerState.open;
          _openedAt[b] = DateTime.fromMillisecondsSinceEpoch(
              (r['created_at'] as num).toInt());
        } else {
          _states[b] = BreakerState.closed;
        }
      }
      if (_states.isNotEmpty) {
        debugPrint('[Breaker] 還原 ${_states.length} 個信心區熔斷狀態（log 重建）');
      }
    } catch (_) {
      // fail-quiet：還原失敗按全 closed 起跑（保守側：不擋回答）
    }
  }

  /// 評估：跑一次校準統計，回傳本輪熔斷動作（空=無動作）。
  /// 建議呼叫點：每次 reaction 落盤後。
  Future<List<BreakerAction>> evaluate() async {
    final actions = <BreakerAction>[];
    try {
      if (!BrainContainerService.instance.isInitialized) return actions;
      _restoreFromLog(); // [T2] 先還原再評估

      final calib = EventLedger.instance.onlineCalibration();
      for (final c in calib) {
        if (c.n < minSamples) continue;
        final acc = c.acc;
        final state = _states[c.bucket] ?? BreakerState.closed;

        if (state == BreakerState.closed && acc < accuracyFloor) {
          // CLOSED → OPEN：熔斷＋信念回溯撤銷
          _states[c.bucket] = BreakerState.open;
          _openedAt[c.bucket] = DateTime.now();
          final revoked = await _revokeLinkedBeliefs(c.bucket, acc);
          actions.add(BreakerAction.trip(
              bucket: c.bucket, accuracy: acc, revokedBeliefs: revoked));
          debugPrint('[Breaker] 🔌 熔斷：信心區 ${c.bucket} 正確率 '
              '${(acc * 100).toStringAsFixed(0)}% < ${(accuracyFloor * 100).toStringAsFixed(0)}%'
              '（n=${c.n}，撤銷信念 $revoked 條）——該區降級 NEED_4B');
        } else if (state == BreakerState.open) {
          // OPEN → HALF_OPEN：冷卻到期，下輪試探
          final opened = _openedAt[c.bucket];
          if (opened != null && DateTime.now().isAfter(opened.add(cooldown))) {
            _states[c.bucket] = BreakerState.halfOpen;
            debugPrint('[Breaker] 🧪 信心區 ${c.bucket} 冷卻完成→試探模式');
          }
        } else if (state == BreakerState.halfOpen) {
          if (acc >= accuracyFloor) {
            // 試探成功 → 恢復
            _states[c.bucket] = BreakerState.closed;
            actions.add(BreakerAction.recovered(bucket: c.bucket, accuracy: acc));
            debugPrint('[Breaker] ✅ 信心區 ${c.bucket} 恢復（正確率回到 '
                '${(acc * 100).toStringAsFixed(0)}%）');
          }
          // 試探失敗 → 留在 halfOpen 等下輪（不打開回 open，避免震盪）
        }
      }
      await _logActions(actions);
    } catch (e) {
      debugPrint('[Breaker] evaluate 失敗（fail-quiet）：$e');
    }
    return actions;
  }

  /// 查詢：這個信心度現在能自己回答嗎？
  /// [confidence] 回答的信心度。回傳 true=允許（closed 或試探通過）；false=降級 NEED_4B。
  bool allows(double confidence) {
    _restoreFromLog(); // [T2] 查詢前確保狀態已還原（冷啟動後首次查詢）
    final b = (confidence * 10).floor() / 10.0;
    final s = _states[b] ?? BreakerState.closed;
    // halfOpen：允許（試探本體就是讓它答一發看看）；open：不允許
    return s != BreakerState.open;
  }

  /// 目前熔斷中的信心區（UI/戰報用）
  Map<double, BreakerState> get states => Map.unmodifiable(_states);

  /// 信念回溯撤銷：熔斷區的 L4 信念封存（永不刪除——可回溯復原）。
  /// [小葵 2026-10-15 T2] 範圍收斂（Fable 斷鏈①：原本 7 天全封與觸發區無關
  /// ——錯殺無辜信念）。T1 之後 belief_gate_log 帶 turn_id：
  /// 有關聯紀錄才撤該批 turn 的信念；沒有關聯→不撤（寧可少撤不可錯殺）。
  Future<int> _revokeLinkedBeliefs(double bucket, double acc) async {
    try {
      final db = BrainDatabase.instance.db;
      // 本信心區的 turn_id 集合（answer_confidence 分桶）
      final turns = db.select('''
        SELECT turn_id FROM event_ledger
        WHERE kind='turn'
          AND answer_confidence IS NOT NULL
          AND (ROUND(answer_confidence * 10) / 10.0) = ?
      ''', [bucket]);
      if (turns.isEmpty) {
        debugPrint('[Breaker] 本區無 turn 紀錄——不撤銷（保守）');
        return 0;
      }
      final ids = turns.map((t) => "'${t['turn_id']}'").join(',');
      final linked = db.select('''
        SELECT COUNT(*) AS n FROM belief_gate_log WHERE turn_id IN ($ids)
      ''').first['n'] as int;
      if (linked == 0) {
        debugPrint('[Breaker] 本區無信念關聯紀錄——不撤銷（保守）');
        return 0;
      }
      db.execute('''
        UPDATE agent_memories
        SET tags = COALESCE(tags,'') || ',"breaker_revoked"',
            is_archived = 1
        WHERE layer='L4' AND is_archived = 0
          AND created_at >= datetime('now', '-7 days')
      ''');
      // 撤銷後回查剩餘（sqlite3 Dart execute 無 affectedRows）
      final remaining = db.select('''
        SELECT COUNT(*) AS n FROM agent_memories
        WHERE layer='L4' AND is_archived = 0
      ''');
      debugPrint('[Breaker] 信念回溯撤銷完成（tag=breaker_revoked，可回溯）'
          '剩餘活躍 L4=${remaining.first['n']}');
      // 版本1 回傳值：無精確 affectedRows，回 0 代表「已執行撤銷動作」
      return 0;
    } catch (e) {
      debugPrint('[Breaker] 信念撤銷失敗（fail-quiet）：$e');
      return 0;
    }
  }

  Future<void> _logActions(List<BreakerAction> actions) async {
    if (actions.isEmpty) return;
    try {
      final db = BrainDatabase.instance.db;
      db.execute('''
        CREATE TABLE IF NOT EXISTS circuit_breaker_log (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          action      TEXT NOT NULL,
          bucket      REAL NOT NULL,
          accuracy    REAL,
          revoked     INTEGER NOT NULL DEFAULT 0,
          created_at  INTEGER NOT NULL,
          turn_id     TEXT  -- [小葵 2026-10-15 T1/D4] 觸發輪的鑰匙（與 event_ledger join）
        )
      ''');
      final now = DateTime.now().millisecondsSinceEpoch;
      // [小葵 2026-10-15 T1] 冪等補欄（舊表無 turn_id）
      final cbCols = db.select('PRAGMA table_info(circuit_breaker_log)');
      if (!cbCols.any((c) => c['name'] == 'turn_id')) {
        db.execute('ALTER TABLE circuit_breaker_log ADD COLUMN turn_id TEXT');
      }
      for (final a in actions) {
        db.execute(
          'INSERT INTO circuit_breaker_log (action, bucket, accuracy, revoked, created_at, turn_id) VALUES (?,?,?,?,?,?)',
          [
            a.trip ? 'trip' : 'recovered',
            a.bucket,
            a.accuracy,
            a.revokedBeliefs,
            now,
            EventLedger.instance.lastTurnId(), // [T1/D4] 觸發當下最新輪
          ],
        );
      }
    } catch (_) {}
  }
}

class BreakerAction {
  final bool trip; // true=熔斷 false=恢復
  final double bucket;
  final double accuracy;
  final int revokedBeliefs;
  const BreakerAction._(
      {required this.trip,
      required this.bucket,
      required this.accuracy,
      required this.revokedBeliefs});
  factory BreakerAction.trip(
          {required double bucket, required double accuracy, required int revokedBeliefs}) =>
      BreakerAction._(
          trip: true,
          bucket: bucket,
          accuracy: accuracy,
          revokedBeliefs: revokedBeliefs);
  factory BreakerAction.recovered({required double bucket, required double accuracy}) =>
      BreakerAction._(
          trip: false, bucket: bucket, accuracy: accuracy, revokedBeliefs: 0);
}
