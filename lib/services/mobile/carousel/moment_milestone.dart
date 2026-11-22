// moment_milestone.dart
// [2026-11-20 此刻頁三刀·刀②進階] 手機端里程碑純函數。
//
// 出處：lib/services/causal/time_sense_service.dart（桌面端 L4 紀念日引擎，
// upcomingMilestones L195-242 / _mkTimeline elapsed 算法 L137）。桌面檔帶
// sqlite3+path_provider DB 依賴，非純邏輯檔，手機端禁直接依賴——故在此複製
// 同款純判斷並註明出處（判讀規則與桌面一致：相遇當天=第 1 天；週年用日曆
// 年月日計算，禁 +365 天跨閏歪一天）。
//
// 純函數模組：無 UI、無網路、無 DB（domino_engine.dart 同款紀律）。

/// 相伴第幾天（含當天=第 1 天）——同 time_sense_service._mkTimeline 算法。
int elapsedDaysSince(DateTime firstMetAt, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final fm = DateTime(firstMetAt.year, firstMetAt.month, firstMetAt.day);
  return DateTime(n.year, n.month, n.day).difference(fm).inDays + 1;
}

/// 今天是否命中里程碑——命中回標籤（「相遇滿月」「第 100 天」「N 週年」），
/// 未命中回 null（誠實：不命中不硬貼標籤）。
///
/// 里程碑日集合與標籤規則複製自桌面 upcomingMilestones：
/// 滿月=第 30 天；整數里程碑 100/200/500/730/1000/1095/1825/3650；
/// 週年用日曆同月同日（years≥1）——教訓：+365 天跨閏年歪一天。
String? momentMilestoneLabel(DateTime firstMetAt, {DateTime? now}) {
  final n0 = now ?? DateTime.now();
  final n = DateTime(n0.year, n0.month, n0.day);
  final fm = DateTime(firstMetAt.year, firstMetAt.month, firstMetAt.day);

  // 1. 週年——純日曆判斷（同月同日且至少滿 1 年），優先於整數日表
  if (n.month == fm.month && n.day == fm.day && n.year > fm.year) {
    return '${n.year - fm.year} 週年';
  }

  // 2. 整數里程碑日（含相遇滿月=30）——今天恰好是第 d 天
  final elapsed = n.difference(fm).inDays + 1;
  for (final d in [30, 100, 200, 365, 500, 730, 1000, 1095, 1825, 3650]) {
    if (elapsed == d) {
      if (d == 30) return '相遇滿月';
      if (d % 365 == 0 && d >= 365) return '${d ~/ 365} 週年';
      return '第 $d 天';
    }
  }
  return null;
}
