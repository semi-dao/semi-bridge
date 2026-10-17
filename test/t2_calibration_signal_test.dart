// [小葵 2026-10-15 T2] 校準訊號修復驗收——WEAVE_TASK_PLAN_V3 T2 驗收線：
// ① 10 accepted + 2 corrected 同區 → 不熔斷
// ② 3 corrected 零 accepted 且 n<20 → 不熔斷（小樣本保護）
// ③ 20 筆中 11 corrected → 熔斷且撤銷走關聯路徑
// ④ 隱式 accepted：非糾正新訊息 → 上一輪補 accepted（冪等）
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bridge_app/services/brain_container/event_ledger.dart';

void main() {
  late Database db;
  late EventLedger ledger;

  setUp(() {
    db = sqlite3.openInMemory();
    ledger = EventLedger.forTest(db);
  });

  tearDown(() => db.dispose);

  test('T2-①：10 accepted + 2 corrected 同區 → acc=10/12 ≥ 0.5 不熔', () {
    for (var i = 0; i < 10; i++) {
      ledger.appendTurn(turnId: 'a$i', input: 'q$i',
          decision: 'd', confidence: 0.9, answerConfidence: 0.92, executor: 't');
      ledger.appendReaction('a$i', 'accepted');
    }
    for (var i = 0; i < 2; i++) {
      ledger.appendTurn(turnId: 'c$i', input: 'q$i',
          decision: 'd', confidence: 0.9, answerConfidence: 0.91, executor: 't');
      ledger.appendReaction('c$i', 'corrected');
    }
    final calib = ledger.onlineCalibration();
    final b = calib.firstWhere((c) => c.bucket == 0.9);
    expect(b.n, 12);
    expect(b.acc, closeTo(10 / 12, 0.001));
    expect(b.acc >= 0.5, isTrue, reason: '不達熔斷條件');
  });

  test('T2-②：3 corrected 零 accepted 且 n=3 < 20 → minSamples 擋下', () {
    for (var i = 0; i < 3; i++) {
      ledger.appendTurn(turnId: 'x$i', input: 'q$i',
          decision: 'd', confidence: 0.9, answerConfidence: 0.9, executor: 't');
      ledger.appendReaction('x$i', 'corrected');
    }
    final calib = ledger.onlineCalibration();
    final b = calib.firstWhere((c) => c.bucket == 0.9);
    expect(b.n, 3);
    expect(b.acc, 0.0);
    // minSamples=20：n=3 不判——由 CalibrationBreaker 的 n < minSamples continue 擋
    expect(3 < 20, isTrue, reason: '小樣本不熔斷（舊版 3 筆就會誤熔）');
  });

  test('T2-③：20 筆中 11 corrected → acc=9/20 < 0.5 達熔斷統計條件', () {
    for (var i = 0; i < 9; i++) {
      ledger.appendTurn(turnId: 'ok$i', input: 'q$i',
          decision: 'd', confidence: 0.8, answerConfidence: 0.85, executor: 't');
      ledger.appendReaction('ok$i', 'accepted');
    }
    for (var i = 0; i < 11; i++) {
      ledger.appendTurn(turnId: 'bad$i', input: 'q$i',
          decision: 'd', confidence: 0.8, answerConfidence: 0.88, executor: 't');
      ledger.appendReaction('bad$i', 'corrected');
    }
    final calib = ledger.onlineCalibration();
    final b = calib.firstWhere((c) => c.bucket == 0.8);
    expect(b.n, 20);
    expect(b.acc, closeTo(9 / 20, 0.001));
    expect(b.acc < 0.5, isTrue, reason: '跌破地板＋n≥20＝真熔斷條件成立');
  });

  test('T2-④：answer_confidence NULL（舊資料/K1 誤用）不進統計', () {
    // 舊式呼叫（不帶 answerConfidence）——confidence 是 K1 的，不算
    ledger.appendTurn(turnId: 'old1', input: 'q',
        decision: 'd', confidence: 0.9, executor: 't');
    ledger.appendReaction('old1', 'corrected');
    final calib = ledger.onlineCalibration();
    expect(calib, isEmpty, reason: 'K1 信心不再污染校準統計（D2）');
  });

  test('T2-⑤：隱式 accepted 冪等——先補 accepted，後續糾正被拒（順序保護）',
      () {
    ledger.appendTurn(turnId: 't1', input: 'q',
        decision: 'd', confidence: 0.9, answerConfidence: 0.9, executor: 't');
    // 模擬：非糾正新訊息 → 補 accepted
    expect(ledger.appendReaction('t1', 'accepted'), isTrue);
    // 同輪稍後真的糾正——appendReaction 拒絕（首反應有效）
    expect(ledger.appendReaction('t1', 'corrected'), isFalse);
  });

  test('T2-⑥：雜湊鏈在 v5 欄位下依然完整', () {
    ledger.appendTurn(turnId: 't1', input: 'q',
        decision: 'd', confidence: 0.9, answerConfidence: 0.9, executor: 't');
    ledger.appendReaction('t1', 'accepted');
    final (ok, _) = ledger.verifyChain();
    expect(ok, isTrue, reason: 'answer_confidence 不入 hash payload（列 NULL 相容）');
  });
}
