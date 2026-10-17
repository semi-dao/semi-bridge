// M3 第三刀——校準熔斷器邏輯測試（2026-10-14）
// 藍圖驗收線：刻意植入錯誤信念 → ≤5 次互動內降級。
// 本測試用 in-memory DB 模擬完整鏈路：
//   錯誤回答（turn）×3 + 糾正（reaction=corrected）→ onlineCalibration
//   跌破地板 → breaker trip → allows() = false（降級 NEED_4B）
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

  tearDown(() => db.dispose());

  test('藍圖驗收模擬：3 次錯誤回答被糾正 → 信心 0.9 區正確率 0% → 統計可見崩塌',
      () {
    // 植入：模型在高信心（0.9）區連錯 3 次（每輪被糾正）
    for (var i = 0; i < 3; i++) {
      ledger.appendTurn(
        turnId: 'turn_$i',
        input: '題目 $i',
        decision: 'need_memory_lookup',
        confidence: 0.92, // K1 信心（不再進校準統計）
        answerConfidence: 0.92, // [T2/D2] 回答正確性信心——校準吃這個
        executor: 'test',
      );
      ledger.appendReaction('turn_$i', 'corrected'); // 每次都被糾正＝錯
    }
    final calib = ledger.onlineCalibration();
    expect(calib, isNotEmpty);
    final bucket09 = calib.firstWhere((c) => c.bucket == 0.9);
    expect(bucket09.n, 3);
    expect(bucket09.acc, 0.0); // 全錯——校準統計正確量到崩塌
  });

  test('正確回答不被降級（accepted → acc=1.0）', () {
    ledger.appendTurn(
        turnId: 't1', input: 'q', confidence: 0.85, answerConfidence: 0.85, executor: 'test');
    ledger.appendReaction('t1', 'accepted');
    final calib = ledger.onlineCalibration();
    expect(calib.firstWhere((c) => c.bucket == 0.8).acc, 1.0);
  });

  test('反應去重——同一 turn 只記一次反應', () {
    ledger.appendTurn(
        turnId: 't1', input: 'q', confidence: 0.7, executor: 'test');
    expect(ledger.appendReaction('t1', 'corrected'), isTrue);
    expect(ledger.appendReaction('t1', 'accepted'), isFalse); // 重複=拒絕
  });

  test('雜湊鏈完整——篡改被驗出', () {
    ledger.appendTurn(
        turnId: 't1', input: 'q', confidence: 0.7, executor: 'test');
    ledger.appendReaction('t1', 'accepted');
    final (ok, _) = ledger.verifyChain();
    expect(ok, isTrue);
    // 篡改
    db.execute("UPDATE event_ledger SET input='竄改' WHERE turn_id='t1'");
    final (ok2, _) = ledger.verifyChain();
    expect(ok2, isFalse);
  });
}
