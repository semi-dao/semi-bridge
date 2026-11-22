// 22 格骨牌輪播引擎（Domino Carousel Engine）
// [S3 提前·2026-11-08] 依據 BRIDGE_MOBILE_SPEC.md v0.5 §7（Blue 2026-10-31 拍板）
//
// 數學身份（SemiMaker 時刻表移植，ATMOSPHERE_LANGUAGE §5 鎖死層）：
// - 時針分針重疊間隔 = 720/11 分鐘 ≈ 65.4545（無理數循環小數）
// - 一天 1440 分 ÷ 720/11 = 22 格（21 次重疊 + 1 跨日格；正午 k=11 完美對齊）
// - 每格來源由 sha256(YYYYMMDD ‖ k) 決定（deterministic 隨機感：
//   同日同節奏、換日全變、永不依賴亂數種子）
// - 配比精確 13:8（資產:時刻，k=11 除外）——以 hash 排序取前 13 實現
// - 空池降級：任一池為空 → 該池全部格降級為另一池（完美對齊格不受影響）
//
// 純函數模組：無 UI、無網路、無 DB——蜂群演習二的品質範本（對照組）。

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 單格內容來源。
enum CarouselSource {
  /// 使用者的數位資產（照片/文件/創作）
  asset,

  /// 時刻卡（相遇天數/里程碑/共同完成的痕跡）
  moment,

  /// 正午完美對齊（k=11 固定，兩個半圓交會的標誌性畫面）
  perfectAlignment,
}

/// 一張骨牌（一天中的一格）。
class DominoSlot {
  /// 格序 1..22（k 對位時刻表：k=11 → 正午 12:00:00.000）
  final int k;

  /// 此格的內容來源
  final CarouselSource source;

  /// 此格起始時刻（本地時區）
  final DateTime startAt;

  /// 此格結束時刻（exclusive）
  final DateTime endAt;

  const DominoSlot({
    required this.k,
    required this.source,
    required this.startAt,
    required this.endAt,
  });

  @override
  String toString() => 'DominoSlot(k: $k, ${source.name}, '
      '$startAt → $endAt)';
}

/// 22 格骨牌輪播引擎——首頁「呼吸感」的數學心臟。
///
/// 用法：
/// ```dart
/// final plan = DominoEngine.planForDay(DateTime.now()); // 全日 22 格計畫
/// final now  = DominoEngine.currentSlot();              // 現在這一格
/// ```
class DominoEngine {
  DominoEngine._();

  /// 一天總格數：1440 ÷ (720/11) = 22（SPEC v0.5 拍板）。
  static const int totalSlotsPerDay = 22;

  /// 每格分鐘數：720/11 ≈ 65.4545（時針分針重疊間隔，無理數）。
  static const double slotMinutes = 720 / 11;

  /// 資產格數（配比 13:8，k=11 之外的 21 格中）。
  static const int assetSlots = 13;

  /// 時刻格數。
  static const int momentSlots = 8;

  /// 正午完美對齊格的 k 值（12:00:00.000 = 第 11 次重疊）。
  static const int noonSlotK = 11;

  /// 時刻 t 落在一天中的第幾格（1..22）。
  ///
  /// 邊界採左開右閉：格 k = ((k-1)·sm, k·sm]。正午 12:00:00.000 = 11·sm
  /// 恰好落在 k=11 的右邊界 → 屬第 11 格（ceil 語義）；12:00:00.001 → 第 12 格。
  /// 00:00:00.000 = 0 → ceil 為 0，clamp 為第 1 格。
  static int slotForTime(DateTime t) {
    final minutesIntoDay = t.hour * 60.0 + t.minute + t.second / 60.0
        + t.millisecond / 60000.0 + t.microsecond / 6e7;
    final k = minutesIntoDay / slotMinutes;
    // 右閉：k 為整數時屬該格（ceil）；否則次一格
    final slot = k == k.roundToDouble() ? k.round() : (k.floor() + 1);
    return slot.clamp(1, totalSlotsPerDay);
  }

  /// 格 k 的結束時刻（exclusive）。
  static DateTime slotEnd(DateTime day, int k) {
    assert(k >= 1 && k <= totalSlotsPerDay, 'k 必須在 1..22');
    final endMinutes = k * slotMinutes;
    return day
        .add(Duration(microseconds: (endMinutes * 60 * 1e6).round()));
  }

  /// 格 k 的起始時刻。
  static DateTime slotStart(DateTime day, int k) =>
      k == 1 ? day : slotEnd(day, k - 1);

  /// 產生某一天的完整 22 格計畫。
  ///
  /// [day] 任一時刻皆可（取其年月日）。
  /// [hasAssets] 資產池是否非空（預設 true）。
  /// [hasMoments] 時刻池是否非空（預設 true）。
  static List<DominoSlot> planForDay(
    DateTime day, {
    bool hasAssets = true,
    bool hasMoments = true,
  }) {
    final dateKey = _dateKey(day);
    final base = DateTime(day.year, day.month, day.day);

    // 1. 對 k=11 以外的 21 格算 deterministic 分數
    final scores = <int, BigInt>{};
    for (var k = 1; k <= totalSlotsPerDay; k++) {
      if (k == noonSlotK) continue;
      scores[k] = _score(dateKey, k);
    }

    // 2. hash 排序取前 13 為資產格（保證配比精確 13:8）
    final sorted = scores.keys.toList()
      ..sort((a, b) {
        final cmp = scores[b]!.compareTo(scores[a]!); // 分數大者在前
        if (cmp != 0) return cmp;
        return a.compareTo(b); // 平手用 k 穩定排序（不可能，sha256 無碰撞）
      });
    final assetSet = sorted.take(assetSlots).toSet();

    // 3. 組裝 22 格（含空池降級）
    final plan = <DominoSlot>[];
    for (var k = 1; k <= totalSlotsPerDay; k++) {
      final start = slotStart(base, k);
      final end = slotEnd(base, k);
      if (k == noonSlotK) {
        plan.add(DominoSlot(
          k: k, source: CarouselSource.perfectAlignment,
          startAt: start, endAt: end,
        ));
        continue;
      }
      var isAsset = assetSet.contains(k);
      // 空池降級：原定來源的池為空 → 降級為另一池
      if (isAsset && !hasAssets) isAsset = false;
      if (!isAsset && !hasMoments) isAsset = true;
      plan.add(DominoSlot(
        k: k,
        source: isAsset ? CarouselSource.asset : CarouselSource.moment,
        startAt: start, endAt: end,
      ));
    }
    return plan;
  }

  /// 現在時刻所在的格。
  static DominoSlot currentSlot() {
    final now = DateTime.now();
    final k = slotForTime(now);
    final plan = planForDay(now);
    return plan.firstWhere((s) => s.k == k);
  }

  /// YYYYMMDD 字串（本地時區）——hash 的日期輸入域。
  static String _dateKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}'
      '${day.month.toString().padLeft(2, '0')}'
      '${day.day.toString().padLeft(2, '0')}';

  /// sha256(YYYYMMDD ‖ k) 的前 16 hex 轉 BigInt 分數——deterministic。
  static BigInt _score(String dateKey, int k) {
    final digest = sha256.convert(utf8.encode('$dateKey|$k'));
    // 前 16 hex（64 bit）已足夠排序且避免 BigInt 運算開銷
    return BigInt.parse(digest.toString().substring(0, 16), radix: 16);
  }
}
