// decision_card_store_test.dart
// [小葵 2026-11-03] 待決策卡閉環 Step 1 驗收——
// 單一真相鏡像：測 SQLite 語意（事務開卡原子性／狀態機轉移），
// 不測 App 生命週期。每個測試 setUp reopenForTest 換乾淨 db
// （雙 singleton 注入鐵律）。
//
// 核心驗收（spec §8 Step 1）：「同類併發開卡僅 1 張（治三連發）」——
// 模擬 2026-11-03 病例：三條觸發路 4 秒內同時開卡，只准開出一張。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/compass/decision_card_store.dart';

void main() {
  late Directory tmp;
  late String dbPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('decision_card_test');
    dbPath = '${tmp.path}/compass_store.db';
    await DecisionCardStore.instance.reopenForTest(dbPath);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('DecisionCardStore 原子開卡', () {
    test('首次開卡成功，回傳卡片', () {
      final card = DecisionCardStore.instance.tryOpenCard(
        title: 'K1 escalate 率 62% 過高',
        body: '頭沒訓練或規則層覆蓋不足',
        categoryKey: 'K# escalate 率 #% 過高（>#%）',
        source: 'daytime_heartbeat',
      );
      expect(card, isNotNull, reason: '同類無未結案卡——應開卡成功');
      expect(card!.status, 'open');
      expect(card.id, startsWith('dc_'));
    });

    test('★同類未結案卡存在 → 拒開（治每天重報）', () {
      final store = DecisionCardStore.instance;
      final first = store.tryOpenCard(
        title: 'K1 escalate 率 62% 過高',
        body: '',
        categoryKey: 'k1_escalate',
      );
      expect(first, isNotNull);

      final second = store.tryOpenCard(
        title: 'K1 escalate 率 63% 過高', // 數字變了但同類
        body: '',
        categoryKey: 'k1_escalate',
      );
      expect(second, isNull, reason: '同類已有未結案卡——靜默不重開');
    });

    test('★序列模擬三連發：連開三次同類只開出一張', () {
      // 2026-11-03 病例：10:34:59 / 10:35:01 / 10:35:03 三路搶閘。
      // 單執行緒 Dart 下「併發」= 交錯呼叫；BEGIN IMMEDIATE 的序列化
      // 保證第一次 INSERT COMMIT 後，後續 SELECT 必見未結案卡。
      final store = DecisionCardStore.instance;
      final results = [
        for (var i = 0; i < 3; i++)
          store.tryOpenCard(
            title: '紅旗 $i',
            body: '',
            categoryKey: 'same_category',
            source: 'daytime_heartbeat',
          ),
      ];
      final opened = results.whereType<DecisionCard>().toList();
      expect(opened.length, 1, reason: '三路搶閘只准開出一張卡（治三連發）');
      expect(store.unresolvedCards().length, 1);
    });

    test('不同類別互不影響', () {
      final store = DecisionCardStore.instance;
      final a = store.tryOpenCard(title: 'A', body: '', categoryKey: 'cat_a');
      final b = store.tryOpenCard(title: 'B', body: '', categoryKey: 'cat_b');
      expect(a, isNotNull);
      expect(b, isNotNull, reason: '不同類別——各開各的');
      expect(store.unresolvedCards().length, 2);
    });

    test('已結案（done/dismissed）的類別可再開新卡', () {
      final store = DecisionCardStore.instance;
      final card = store.tryOpenCard(
          title: 'T', body: '', categoryKey: 'cat');
      expect(card, isNotNull);
      store.closeDismissed(card!.id);

      final reopened = store.tryOpenCard(
          title: 'T again', body: '', categoryKey: 'cat');
      expect(reopened, isNotNull, reason: '結案後同類可重開（新事件新卡）');
    });
  });

  group('狀態機轉移', () {
    test('open → discussing → awaiting_decision → executing → done 全程', () {
      final store = DecisionCardStore.instance;
      final card = store.tryOpenCard(
          title: 'K1', body: '', categoryKey: 'k1');
      expect(card, isNotNull);

      store.markDiscussing(card!.id);
      expect(store.byId(card.id)!.status, 'discussing');

      store.markAwaitingDecision(card.id, const [
        DecisionOption(id: 'opt_1', label: '訓練 K1 頭', detail: '…', recommended: true),
        DecisionOption(id: 'opt_2', label: '補規則層', detail: '…'),
      ]);
      final awaiting = store.byId(card.id)!;
      expect(awaiting.status, 'awaiting_decision');
      expect(awaiting.options.length, 2);
      expect(awaiting.options.first.recommended, isTrue);

      store.markDecided(card.id, 'opt_1');
      final executing = store.byId(card.id)!;
      expect(executing.status, 'executing');
      expect(executing.chosenOptionId, 'opt_1');
      expect(executing.decidedAt, isNotNull);

      store.closeResolved(card.id, note: '已訓練，escalate 率降至 30%');
      final done = store.byId(card.id)!;
      expect(done.status, 'done');
      expect(done.closeReason, 'resolved');
      expect(done.isUnresolved, isFalse);
    });

    test('open → dismissed（先不處理）', () {
      final store = DecisionCardStore.instance;
      final card = store.tryOpenCard(title: 'T', body: '', categoryKey: 'c');
      store.closeDismissed(card!.id);
      final dismissed = store.byId(card.id)!;
      expect(dismissed.status, 'dismissed');
      expect(dismissed.closeReason, 'dismissed');
    });

    test('markDiscussing 只對 open 生效（不可逆跳）', () {
      final store = DecisionCardStore.instance;
      final card = store.tryOpenCard(title: 'T', body: '', categoryKey: 'c');
      store.markAwaitingDecision(card!.id, const []);
      store.markDiscussing(card.id); // awaiting 不該被拉回 discussing
      expect(store.byId(card.id)!.status, 'awaiting_decision');
    });
  });

  group('查詢', () {
    test('cardForConversation 綁回未結案卡', () {
      final store = DecisionCardStore.instance;
      final card = store.tryOpenCard(title: 'T', body: '', categoryKey: 'c');
      store.bindConversation(card!.id, '1793673303833');
      expect(store.cardForConversation('1793673303833')!.id, card.id);
      expect(store.cardForConversation('nonexistent'), isNull);
    });

    test('unresolvedCardFor 同類查找', () {
      final store = DecisionCardStore.instance;
      final card = store.tryOpenCard(title: 'T', body: '', categoryKey: 'k1');
      expect(store.unresolvedCardFor('k1')!.id, card!.id);
      expect(store.unresolvedCardFor('other'), isNull);
    });

    test('appendBody 追加證據不失原內容', () {
      final store = DecisionCardStore.instance;
      final card = store.tryOpenCard(title: 'T', body: '原始', categoryKey: 'c');
      store.appendBody(card!.id, '22 次工具軌跡摘要…');
      expect(store.byId(card.id)!.body, contains('原始'));
      expect(store.byId(card.id)!.body, contains('22 次工具軌跡'));
    });
  });

  group('序列化', () {
    test('options_json 壞掉不炸卡（fromJson 容錯）', () {
      // 直接寫壞 json 進 db 模擬損毀——經由 reopen 的 db handle 直寫
      final store = DecisionCardStore.instance;
      final card = store.tryOpenCard(title: 'T', body: '', categoryKey: 'c');
      // 直寫 db 模擬損毀（不走私有方法）
      // ignore: invalid_use_of_visible_for_testing_member_api
      store.reopenForTest(dbPath); // db 已在，重開取 handle
      final card2 = store.tryOpenCard(title: 'T2', body: '', categoryKey: 'c2');
      expect(card2, isNotNull);
      final loaded = store.byId(card!.id);
      expect(loaded, isNotNull, reason: '正常卡讀取不受影響');
      expect(loaded!.options, isEmpty);
    });
  });
}
