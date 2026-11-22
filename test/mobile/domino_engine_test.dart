// [S3 提前·蜂群演習二示範卡] 22 格骨牌輪播引擎測試
// 依據：BRIDGE_MOBILE_SPEC.md v0.5 §7 團隊版首頁輪播（Blue 2026-10-31 拍板）
// 蜂群演習二（MOBILE_SWARM_DRILL2.md）以本檔為品質範本（對照組）。
//
// 拍板數學（SPEC 原文錨定）：
// - 一天 22 格（1440 ÷ (720/11) = 22；21 次重疊 + 1 跨日格）
// - 每格 = 720/11 ≈ 65.4545 分鐘
// - 正午 12:00:00.000（k=11）固定「今日完美對齊」
// - 其餘 21 格：sha256(YYYYMMDD‖k) 決定資產或時刻，配比 13:8
// - 任一池為空 → 整格降級時刻卡
import 'package:bridge_app/services/mobile/carousel/domino_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('格線數學（SemiMaker 時刻表移植）', () {
    test('一天總格數 = 22（1440 ÷ 720/11）', () {
      expect(DominoEngine.totalSlotsPerDay, 22);
    });

    test('格長 = 720/11 分鐘（無理數間隔，65.4545...）', () {
      expect(DominoEngine.slotMinutes, closeTo(720 / 11, 1e-9));
      expect(DominoEngine.slotMinutes, closeTo(65.4545, 0.0001));
    });

    test('正午 12:00:00.000 落在 k=11 格（右閉邊界）', () {
      final noon = DateTime(2026, 11, 8, 12, 0, 0, 0);
      expect(DominoEngine.slotForTime(noon), 11);
    });

    test('午夜 00:00 屬第 1 格；一天最後一刻屬第 22 格（跨日格）', () {
      expect(DominoEngine.slotForTime(DateTime(2026, 11, 8, 0, 0, 0)), 1);
      expect(DominoEngine.slotForTime(DateTime(2026, 11, 8, 23, 59, 59)), 22);
    });

    test('k=11 格的邊界時刻 11:59:59 → 仍第 11 格；12:00:00.001 → 第 12 格', () {
      expect(DominoEngine.slotForTime(DateTime(2026, 11, 8, 11, 59, 59)), 11);
      expect(
          DominoEngine.slotForTime(DateTime(2026, 11, 8, 12, 0, 0, 1)), 12);
    });

    test('格 k 的結束時刻 = k × 720/11 分鐘（k=22 → 24:00 整，無空洞）', () {
      final day = DateTime(2026, 11, 8);
      final endOf22 = DominoEngine.slotEnd(day, 22);
      expect(endOf22.difference(day).inMinutes, 1440); // 一天恰好切滿
    });
  });

  group('deterministic 配比（sha256 骨牌）', () {
    test('同一天：資產格恰 13、時刻格恰 8、完美對齊格 1（13+8+1=22）', () {
      final plan = DominoEngine.planForDay(DateTime(2026, 11, 8));
      final assets = plan.where((s) => s.source == CarouselSource.asset).length;
      final moments = plan.where((s) => s.source == CarouselSource.moment).length;
      final noon = plan
          .where((s) => s.source == CarouselSource.perfectAlignment)
          .length;
      expect(assets, 13, reason: 'SPEC 拍板配比 13:8（資產:時刻）');
      expect(moments, 8);
      expect(noon, 1);
      expect(plan.length, 22);
    });

    test('k=11 永遠是 perfectAlignment（不參與配比抽籤）', () {
      for (final date in [
        DateTime(2026, 1, 1),
        DateTime(2026, 6, 15),
        DateTime(2026, 12, 31),
      ]) {
        final slot = DominoEngine.planForDay(date).firstWhere((s) => s.k == 11);
        expect(slot.source, CarouselSource.perfectAlignment,
            reason: '$date 的 k=11 應固定完美對齊');
      }
    });

    test('deterministic：同日同 k 永遠同結果（重跑 100 次不變）', () {
      final first = DominoEngine.planForDay(DateTime(2026, 11, 8));
      for (var i = 0; i < 100; i++) {
        final again = DominoEngine.planForDay(DateTime(2026, 11, 8));
        expect(again.map((s) => '${s.k}:${s.source.name}').join(','),
            first.map((s) => '${s.k}:${s.source.name}').join(','));
      }
    });

    test('換日全變：30 個連續日不出現單一排列重複壟斷', () {
      final patterns = <String>{};
      for (var d = 0; d < 30; d++) {
        final plan = DominoEngine.planForDay(DateTime(2026, 11, 1).add(Duration(days: d)));
        patterns.add(plan.map((s) => s.source.index).join());
      }
      expect(patterns.length, greaterThan(1),
          reason: 'hash(日期,k) 必須讓不同日期產生不同排列');
    });
  });

  group('空池降級（新用戶不開天窗）', () {
    test('資產池為空 → 全部原資產格降級為時刻卡', () {
      final plan = DominoEngine.planForDay(
        DateTime(2026, 11, 8),
        hasAssets: false,
      );
      expect(
          plan.where((s) => s.source == CarouselSource.asset), isEmpty,
          reason: '空池降級：不出現任何資產格');
      // 完美對齊格不受降級影響
      expect(
          plan.where((s) => s.source == CarouselSource.perfectAlignment).length,
          1);
    });

    test('時刻池為空 → 全部原時刻格降級為資產卡（對稱處理）', () {
      final plan = DominoEngine.planForDay(
        DateTime(2026, 11, 8),
        hasMoments: false,
      );
      expect(plan.where((s) => s.source == CarouselSource.moment), isEmpty);
      expect(
          plan.where((s) => s.source == CarouselSource.perfectAlignment).length,
          1);
    });
  });

  group('當下格查詢（首頁呼吸中樞）', () {
    test('currentSlot 回傳現在時刻所在的格', () {
      final now = DateTime.now();
      final slot = DominoEngine.currentSlot();
      expect(slot.k, DominoEngine.slotForTime(now));
      expect(slot.k, inInclusiveRange(1, 22));
    });
  });
}
