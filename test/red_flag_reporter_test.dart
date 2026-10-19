// [殘件① 2026-10-19] RedFlagReporter 驗收——SelfGauge 紅旗的「嘴」。
// 病史：redFlags() 只算不說（唯一生產者=凌晨夢）。本刀補白天路＋
// 同類紅旗同日去重記帳。
// 驗收線：
//   ① 同類紅旗當日第二次 report 靜默（數字不同也算同類）
//   ② 新類紅旗當日可再報（額度內）
//   ③ 被閘擋（無證據）不記帳——下小時重試
//   ④ 類別鍵歸一：數字→#，同類紅旗數字變了仍是同類
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/compass/red_flag_reporter.dart';
import 'package:bridge_app/services/compass/compass_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CompassStore store;

  setUp(() async {
    store = CompassStore.instance;
    await store.reopenForTest(
        '/tmp/t_redflag_${DateTime.now().millisecondsSinceEpoch}'
        '_${DateTime.now().microsecond}.db');
    store.setMeta('speak_spoken_on', '');
    store.setMeta('speak_spoken_count', '0');
    store.setMeta('speak_queue', '[]');
    final today = RedFlagReporter.instance.dayKey();
    store.setMeta(today, '[]'); // 清當日記帳
  });

  test('① 同類紅旗當日第二次 report 靜默', () {
    store.addPitfall('agent.loop', '證據', author: 'test');
    final r = RedFlagReporter.instance;
    final first = r.report(['未結案傷口 7 筆堆積——同工具反覆撞牆沒長出藥'],
        source: 'test');
    expect(first, isTrue, reason: '第一次必須入列');
    final second = r.report(['未結案傷口 9 筆堆積——同工具反覆撞牆沒長出藥'],
        source: 'test');
    expect(second, isFalse, reason: '同類紅旗（數字變了）當日不得重複入列');
    final q = store.getMeta('speak_queue');
    expect(q!.contains('未結案傷口 9 筆'), isFalse,
        reason: '佇列裡只能有一則（第二次被去重擋下）');
  });

  test('② 新類紅旗當日可再報（額度內）', () {
    store.addPitfall('agent.loop', '證據', author: 'test');
    final r = RedFlagReporter.instance;
    expect(
        r.report(['K1 escalate 率 80% 過高（>50%）——頭沒訓練或規則層覆蓋不足'],
            source: 'test'),
        isTrue);
    expect(
        r.report(['認知傷口 2 筆未結案——結論與事實不符（宣稱看到沒有的東西），痊癒條件=主動說出看不見'],
            source: 'test'),
        isTrue);
  });

  test('③ 被閘擋（無 pitfalls 證據）不記帳——重試可行', () {
    // 乾淨 db：agent.loop 無 pitfalls → tryEnqueue 被證據閘擋
    final r = RedFlagReporter.instance;
    final blocked = r.report(['未結案傷口 7 筆堆積——同工具反覆撞牆沒長出藥'],
        source: 'test');
    expect(blocked, isFalse, reason: '無證據必須被擋');
    final ledger = store.getMeta(r.dayKey());
    expect(ledger == null || ledger == '[]' || !ledger.contains('未結案'),
        isTrue,
        reason: '被擋的紅旗不得記帳——否則永遠沒機會重試');
    // 補證據後重試應成功
    store.addPitfall('agent.loop', '證據', author: 'test');
    expect(
        r.report(['未結案傷口 7 筆堆積——同工具反覆撞牆沒長出藥'],
            source: 'test'),
        isTrue,
        reason: '證據補上後同類紅旗可入列（前次未記帳）');
  });

  test('④ 類別鍵歸一：數字→#', () {
    expect(redFlagCategoryKey('未結案傷口 7 筆堆積'), redFlagCategoryKey('未結案傷口 9 筆堆積'));
    expect(redFlagCategoryKey('K1 escalate 率 80% 過高') != redFlagCategoryKey('認知傷口 2 筆未結案'), isTrue);
  });
}
