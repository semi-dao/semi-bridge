// [蜂群演習二 Wave 2·工蜂E] T1 骨牌 hash —— 紅隊視角加固測試
// 綁正式實作：lib/services/mobile/carousel/domino_engine.dart（DominoEngine）
//
// 紅隊 issues 主軸（docs/drill2/SUMMARY.md；T1 review 檔不存在 → 依指揮官指定三軸加固）：
//   ① hero/降級衝突未測 → k=11 完美對齊格 × 空池降級的交互
//   ② 時間窗規格未驗   → 邊界成對（11:59:59.999 / 12:00:00.000 / 12:00:00.001）＋跨日格
//   ③ 配比 13:8 未驗   → 30 連日恆成立（含「非樸素 %2 抽籤」反證）
//
// ⚠️ 索引對位（紅隊抓到的草稿 vs 正式實作落差）：
//    正式實作為 1-indexed（k=1..22）：k=11 = 正午完美對齊格、k=22 = 跨日格。
//    草稿 docs/drill2/T1_骨牌hash_test.dart 為 0-indexed（k=11 hero、k=21 跨日），
//    與正式實作差一格 —— 本檔一律以正式實作的 1-indexed 為準。
//
// 品質範本：test/mobile/domino_engine_test.dart（SPEC 條款原文錨進 reason、成對邊界、重跑驗證）

import 'package:bridge_app/services/mobile/carousel/domino_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// 測試用基準日（與範本對齊）。
final DateTime _day = DateTime(2026, 11, 8);

/// 一天格長（微秒）—— 720/11 分鐘。
double get _slotMicros => DominoEngine.slotMinutes * 60 * 1e6;

/// 取某格的來源。
CarouselSource _sourceOf(List<DominoSlot> plan, int k) =>
    plan.firstWhere((s) => s.k == k).source;

/// 統計一張計畫的三類格數（缺項回 0，不回 null —— 避免「0 格」與「沒這類」混淆）。
Map<CarouselSource, int> _tally(List<DominoSlot> plan) {
  final tally = <CarouselSource, int>{
    for (final source in CarouselSource.values) source: 0,
  };
  for (final slot in plan) {
    tally[slot.source] = (tally[slot.source] ?? 0) + 1;
  }
  return tally;
}

void main() {
  group('① 完美對齊格 × 空池降級（hero/降級衝突）', () {
    test('k=11 在四種池狀態下永遠是 perfectAlignment（降級不得吃掉 hero 格）', () {
      final states = <String, ({bool assets, bool moments})>{
        'both': (assets: true, moments: true),
        'no-assets': (assets: false, moments: true),
        'no-moments': (assets: true, moments: false),
        'neither': (assets: false, moments: false),
      };

      for (final entry in states.entries) {
        final plan = DominoEngine.planForDay(
          _day,
          hasAssets: entry.value.assets,
          hasMoments: entry.value.moments,
        );
        expect(
          _sourceOf(plan, 11),
          CarouselSource.perfectAlignment,
          reason: '池狀態「${entry.key}」下 k=11 仍必須是完美對齊格'
              '（SPEC §7：完美對齊格不參與配比抽籤，空池降級不得影響它）',
        );
      }
    });

    test('空池降級只換 source、不得移動 k=11 的時間窗（降級是內容層非時間層）', () {
      final normal = DominoEngine.planForDay(_day);
      final degraded = DominoEngine.planForDay(_day, hasAssets: false);
      final normalNoon = normal.firstWhere((s) => s.k == 11);
      final degradedNoon = degraded.firstWhere((s) => s.k == 11);

      expect(degradedNoon.startAt, normalNoon.startAt);
      expect(degradedNoon.endAt, normalNoon.endAt);
      expect(degradedNoon.startAt, DateTime(2026, 11, 8, 10, 54, 32, 727, 273));
      expect(degradedNoon.endAt, DateTime(2026, 11, 8, 12, 0, 0, 0));
    });

    test('資產池空 → 21 格全降級為 moment，無任何 asset 格，仍有 1 格完美對齊', () {
      final plan = DominoEngine.planForDay(_day, hasAssets: false);
      final tally = _tally(plan);

      expect(tally[CarouselSource.asset], 0,
          reason: '空池降級：不得出現任何資產格（無素材不假裝有）');
      expect(tally[CarouselSource.moment], 21);
      expect(tally[CarouselSource.perfectAlignment], 1);
      expect(plan.length, 22, reason: '降級不得改變格數（不開天窗、格子不縮水）');
    });

    test('時刻池空 → 21 格全降級為 asset，無任何 moment 格，仍有 1 格完美對齊', () {
      final plan = DominoEngine.planForDay(_day, hasMoments: false);
      final tally = _tally(plan);

      expect(tally[CarouselSource.moment], 0,
          reason: '空池降級：不得出現任何時刻格');
      expect(tally[CarouselSource.asset], 21);
      expect(tally[CarouselSource.perfectAlignment], 1);
      expect(plan.length, 22);
    });

    test('兩池皆空 → 22 格全部仍有明確來源（不開天窗），k=11 仍完美對齊', () {
      final plan = DominoEngine.planForDay(_day, hasAssets: false, hasMoments: false);

      expect(plan.length, 22);
      expect(
        plan.where((s) => s.source == CarouselSource.perfectAlignment).length,
        1,
        reason: '兩池皆空時完美對齊格仍存在（那是「今天正午兩圓交會」的事實，不依賴素材）',
      );
      // 每格都必須落在三種合法來源之內 —— 不得出現 null/unknown 讓 UI 開天窗
      for (final slot in plan) {
        expect(
          slot.source,
          anyOf(
            CarouselSource.asset,
            CarouselSource.moment,
            CarouselSource.perfectAlignment,
          ),
          reason: 'k=${slot.k} 的來源必須合法',
        );
      }
      expect(
        plan.where((s) => s.source != CarouselSource.perfectAlignment).length,
        21,
        reason: '非正午的 21 格仍要有內容來源（不開天窗）',
      );
    });

    test('兩池皆空的降級結果仍是決定性的（重跑一致）', () {
      final first = DominoEngine.planForDay(_day, hasAssets: false, hasMoments: false)
          .map((s) => '${s.k}:${s.source.name}')
          .join(',');
      for (var i = 0; i < 20; i++) {
        expect(
          DominoEngine.planForDay(_day, hasAssets: false, hasMoments: false)
              .map((s) => '${s.k}:${s.source.name}')
              .join(','),
          first,
          reason: '兩池皆空時不得退化為隨機（deterministic 是整個模組的底線）',
        );
      }
    });

    test('降級後格序仍完整 1..22（不重複、不遺漏）', () {
      for (final flags in [
        (assets: true, moments: true),
        (assets: false, moments: true),
        (assets: true, moments: false),
        (assets: false, moments: false),
      ]) {
        final plan = DominoEngine.planForDay(
          _day,
          hasAssets: flags.assets,
          hasMoments: flags.moments,
        );
        expect(plan.map((s) => s.k).toList(),
            List<int>.generate(22, (i) => i + 1),
            reason: '池狀態(${flags.assets},${flags.moments}) 下格序必須完整');
      }
    });
  });

  group('② 時間窗規格（邊界成對 + 跨日格）', () {
    test('正午邊界成對：11:59:59.999 / 12:00:00.000 同屬 k=11，12:00:00.001 已進 k=12', () {
      // 11:59:59.999 —— 距正午尚差 1 毫秒，仍在第 11 格內
      expect(
        DominoEngine.slotForTime(DateTime(2026, 11, 8, 11, 59, 59, 999)),
        11,
        reason: 'k=11 為右閉格（(10·sm, 11·sm]），11:59:59.999 必須仍在第 11 格',
      );
      // 12:00:00.000 —— 恰好落在格界上，右閉語義歸第 11 格
      expect(
        DominoEngine.slotForTime(DateTime(2026, 11, 8, 12, 0, 0, 0)),
        11,
        reason: '12:00:00.000 = 11 × (720/11) 恰在右邊界 → 歸 k=11（完美對齊格）',
      );
      // 12:00:00.001 —— 越過右邊界 1 毫秒，進第 12 格
      expect(
        DominoEngine.slotForTime(DateTime(2026, 11, 8, 12, 0, 0, 1)),
        12,
        reason: '12:00:00.001 已越過 11·sm → 進 k=12',
      );
    });

    test('午夜邊界成對：00:00:00.000 屬 k=1，23:59:59.999 屬 k=22（跨日格）', () {
      expect(DominoEngine.slotForTime(DateTime(2026, 11, 8, 0, 0, 0, 0)), 1,
          reason: '一天的起點歸第 1 格（ceil(0)=0 → clamp 到 1）');
      expect(DominoEngine.slotForTime(DateTime(2026, 11, 8, 23, 59, 59, 999)), 22,
          reason: '一天最後一毫秒屬第 22 格（跨日格）');
    });

    test('跨日格 k=22：起於 22:54:32.727273、止於次日 00:00:00.000，涵蓋 23:59:59.999', () {
      final plan = DominoEngine.planForDay(_day);
      final last = plan.firstWhere((s) => s.k == 22);
      final lastInstant = DateTime(2026, 11, 8, 23, 59, 59, 999);

      expect(last.startAt, DateTime(2026, 11, 8, 22, 54, 32, 727, 273));
      expect(last.endAt, DateTime(2026, 11, 9, 0, 0, 0, 0),
          reason: 'k=22 是跨日格：結束時刻落在隔天 00:00');
      expect(last.startAt.isBefore(lastInstant), isTrue);
      expect(lastInstant.isBefore(last.endAt), isTrue,
          reason: '23:59:59.999 必須被 k=22 的時間窗涵蓋');
      expect(last.endAt.day, 9, reason: '確實跨到隔日');
      expect(DominoEngine.slotForTime(lastInstant), 22);
    });

    test('相鄰格首尾相接，22 格切滿 1440 分鐘（無空洞、無重疊）', () {
      final plan = DominoEngine.planForDay(_day);
      for (var k = 1; k < 22; k++) {
        expect(plan.firstWhere((s) => s.k == k + 1).startAt,
            plan.firstWhere((s) => s.k == k).endAt,
            reason: 'k=$k 與 k=${k + 1} 必須首尾相接');
      }
      expect(plan.firstWhere((s) => s.k == 1).startAt, _day,
          reason: '第 1 格自 00:00:00.000 起算');
      expect(
        plan.firstWhere((s) => s.k == 22).endAt.difference(_day).inMinutes,
        1440,
        reason: '22 格切滿一整天（1440 分鐘）',
      );
    });

    test('每格長度皆為 720/11 分鐘（±1 微秒浮點容差）', () {
      final plan = DominoEngine.planForDay(_day);
      for (final slot in plan) {
        final micros = slot.endAt.difference(slot.startAt).inMicroseconds;
        expect(micros, closeTo(_slotMicros, 1),
            reason: 'k=${slot.k} 的格長必須是 720/11 分鐘');
      }
    });

    test('一天之內 slotForTime 單調不減，且恆落在 1..22', () {
      var previous = 1;
      for (var minute = 0; minute < 24 * 60; minute++) {
        final slot = DominoEngine.slotForTime(
          DateTime(2026, 11, 8).add(Duration(minutes: minute)),
        );
        expect(slot, inInclusiveRange(1, 22));
        expect(slot, greaterThanOrEqualTo(previous),
            reason: '時刻推進時格序不得回退（minute=$minute）');
        previous = slot;
      }
    });
  });

  group('③ 配比 13:8:1 恆成立（30 連日）', () {
    test('連續 30 天，每天精確 13 資產 + 8 時刻 + 1 完美對齊 = 22 格', () {
      for (var d = 0; d < 30; d++) {
        final date = DateTime(2026, 11, 1).add(Duration(days: d));
        final tally = _tally(DominoEngine.planForDay(date));
        expect(tally[CarouselSource.asset], 13,
            reason: '$date 的資產格必須恰 13（SPEC §7 拍板 13:8 配比）');
        expect(tally[CarouselSource.moment], 8,
            reason: '$date 的時刻格必須恰 8');
        expect(tally[CarouselSource.perfectAlignment], 1);
        expect(DominoEngine.planForDay(date).length, 22);
      }
    });

    test('30 連日的排列互不相同（hash 必須吃日期，換日全變）', () {
      final patterns = <String>{};
      for (var d = 0; d < 30; d++) {
        final date = DateTime(2026, 11, 1).add(Duration(days: d));
        final plan = DominoEngine.planForDay(date);
        patterns.add(plan.map((s) => s.source.index).join());
      }
      expect(patterns.length, 30,
          reason: 'hash(YYYYMMDD‖k) 必須讓 30 天產生 30 種不同排列');
    });

    test('反證：配比是「hash 排序取前 13」而非樸素 %2 或固定位置抽籤', () {
      // 樸素 sha256%2 抽籤在 21 格上只會得到約 10/11（偶/奇），絕不可能穩穩 13/8；
      // 位置抽籤（把非正午 21 個 k 的前 13 個當資產）則與日期無關。
      // 兩者都被下列斷言排除。
      final nonNoon = <int>[
        for (var k = 1; k <= 22; k++)
          if (k != 11) k,
      ];
      final positionalAssetSet = nonNoon.take(13).toSet();

      var differedFromPositional = 0;
      for (var d = 0; d < 30; d++) {
        final date = DateTime(2026, 11, 1).add(Duration(days: d));
        final plan = DominoEngine.planForDay(date);
        final assetKs = plan
            .where((s) => s.source == CarouselSource.asset)
            .map((s) => s.k)
            .toSet();
        expect(assetKs.length, 13);
        if (!_sameIntSet(assetKs, positionalAssetSet)) differedFromPositional++;
      }
      expect(differedFromPositional, 30,
          reason: '資產格必須由日期 hash 決定（位置抽籤與 %2 抽籤都不會 30/30 全中）');
    });

    test('同一天不同時刻 → 同一份排列（hash 輸入只有 YYYYMMDD，不吃時分秒）', () {
      final morning = DominoEngine.planForDay(DateTime(2026, 11, 8, 3, 17, 42));
      final night = DominoEngine.planForDay(DateTime(2026, 11, 8, 22, 41, 9));
      expect(
        morning.map((s) => s.source.name).join(),
        night.map((s) => s.source.name).join(),
        reason: '同一天的格線排列必須一致（只有日期進 hash）',
      );
    });
  });

  group('④ 決定性與 API 契約', () {
    test('同日重跑 50 次排列完全不變（deterministic）', () {
      final first = DominoEngine.planForDay(_day)
          .map((s) => '${s.k}:${s.source.name}')
          .join(',');
      for (var i = 0; i < 50; i++) {
        expect(
          DominoEngine.planForDay(_day).map((s) => '${s.k}:${s.source.name}').join(','),
          first,
        );
      }
    });

    test('currentSlot 回傳的格序 == slotForTime(now)，且來源合法', () {
      final now = DateTime.now();
      final slot = DominoEngine.currentSlot();
      expect(slot.k, DominoEngine.slotForTime(now));
      expect(slot.k, inInclusiveRange(1, 22));
      expect(slot.startAt.isBefore(slot.endAt), isTrue);
      expect(
        slot.source,
        anyOf(
          CarouselSource.asset,
          CarouselSource.moment,
          CarouselSource.perfectAlignment,
        ),
      );
    });

    test('slotStart/slotEnd 對每個 k 都回傳合法且首尾相接的時間窗', () {
      for (var k = 1; k <= 22; k++) {
        final start = DominoEngine.slotStart(_day, k);
        final end = DominoEngine.slotEnd(_day, k);
        expect(start.isBefore(end), isTrue, reason: 'k=$k 必須有正向時間窗');
        if (k > 1) {
          expect(start, DominoEngine.slotEnd(_day, k - 1),
              reason: 'k=$k 起點必須等於 k=${k - 1} 終點');
        }
      }
    });
  });
}

/// 集合相等（避免依賴 flutter_test 內部 matcher 的具名匯出）。
bool _sameIntSet(Set<int> a, Set<int> b) {
  if (a.length != b.length) return false;
  return a.containsAll(b);
}
