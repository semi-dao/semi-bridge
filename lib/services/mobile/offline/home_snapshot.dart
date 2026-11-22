// 離線快照（Home Snapshot）——手機版首頁「上次快照」契約
// [T4 2026-11-09] 依據 BRIDGE_MOBILE_SPEC.md v0.5 §7 離線行為拍板（Blue 2026-10-30）
//
// SPEC 條款 2 原文：「首頁顯示上次快照＋時間戳（誠實標灰不裝活著）」
//
// ★ 語意鐵則：capturedAt 屬於「快照本身」，不是「當下時間」。
//   離線時 UI 顯示的是這份快照被拍下來的時刻——不得偷換成 DateTime.now()，
//   否則就是「裝活著」（假裝資料是現在的），違反 §7 誠實鐵則。
//
// 純函數核心：無 UI、無網路、無 DB——可獨立測試（對照 lib/services/mobile/carousel/domino_engine.dart）。

/// 首頁離線快照——一組在 [capturedAt] 那一刻被拍下的首頁內容。
class HomeSnapshot {
  /// 快照內容（鍵值對；值型別不限，測試用 String/num 皆可）。
  final Map<String, dynamic> content;

  /// 快照被拍下的時刻（屬於快照，非當前時間）。
  final DateTime capturedAt;

  const HomeSnapshot({
    required this.content,
    required this.capturedAt,
  });

  /// 內容為空 → 沒有任何東西可顯示。
  bool get isEmpty => content.isEmpty;

  /// 內容非空 → 有東西可顯示。
  bool get isNotEmpty => content.isNotEmpty;

  /// 快照年齡＝[now] 與 [capturedAt] 的差距。
  ///
  /// [now] 早於快照時刻時回傳 [Duration.zero]（不得回負數）。
  Duration ageAt(DateTime now) {
    final diff = now.difference(capturedAt);
    return diff.isNegative ? Duration.zero : diff;
  }

  /// 快照是否過期（年齡**嚴格大於** [staleAfter] 才算過期）。
  ///
  /// 邊界語意：年齡恰好等於 [staleAfter] → 尚未過期。
  bool isStale(Duration staleAfter, {DateTime? now}) {
    return ageAt(now ?? DateTime.now()) > staleAfter;
  }

  /// 快照時間戳的可讀字串（YYYY-MM-DD HH:mm）。
  ///
  /// ★ 顯示的是快照自己的時刻——不是今天、不是當下。
  String get capturedAtLabel {
    final y = capturedAt.year.toString().padLeft(4, '0');
    final m = capturedAt.month.toString().padLeft(2, '0');
    final d = capturedAt.day.toString().padLeft(2, '0');
    final hh = capturedAt.hour.toString().padLeft(2, '0');
    final mm = capturedAt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  String toString() =>
      'HomeSnapshot(capturedAt: $capturedAtLabel, ${content.length} keys)';
}
