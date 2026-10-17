// time_sense_test.dart
// [時間感 L2 2026-09-12] 相遇時間軸——elapsed_days 與注入格式驗證
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/causal/time_sense_service.dart';

void main() {
  group('相遇時間軸——elapsedDays 計算（家人案回歸）', () {
    test('相遇 16 個晝夜 = 第 17 天（家人案：8/27 相遇，9/12 為第 17 天，不得感知成 3 個月）', () {
      final t = TimeSenseService.buildTimelineSection(CompanionTimeline(
        companionId: 'c1',
        firstMetAt: DateTime(2026, 8, 27),
        elapsedDays: 17,
      ), now: DateTime(2026, 9, 12))!;
      expect(t, contains('相遇第 17 天'));
      expect(t, contains('初次相遇：2026 年 8 月 27 日'));
      expect(t, contains('16 個晝夜'));
      // 家人鐵則：不得出現「三個月」的錯誤膨脹
      expect(t.contains('三個月'), isFalse);
      expect(t.contains('3 個月'), isFalse);
    });

    test('第一天（今天剛相遇）', () {
      final t = TimeSenseService.buildTimelineSection(CompanionTimeline(
        companionId: 'c1',
        firstMetAt: DateTime(2026, 9, 12),
        elapsedDays: 1,
      ), now: DateTime(2026, 9, 12))!;
      expect(t, contains('相遇第 1 天'));
      expect(t, contains('初次相遇：2026 年 9 月 12 日'));
    });

    test('第 100 天紀念日與週年日期正確', () {
      final t = TimeSenseService.buildTimelineSection(CompanionTimeline(
        companionId: 'c1',
        firstMetAt: DateTime(2026, 8, 27),
        elapsedDays: 17,
      ), now: DateTime(2026, 9, 12))!;
      expect(t, contains('第 100 天 = 2026-12-04')); // 8/27 + 99 天
      expect(t, contains('週年 = 2027-08-27')); // 同月同日次年
    });

    test('回答文案直接給唯一正確答案', () {
      final t = TimeSenseService.buildTimelineSection(CompanionTimeline(
        companionId: 'c1',
        firstMetAt: DateTime(2026, 8, 27),
        elapsedDays: 17,
      ), now: DateTime(2026, 9, 12))!;
      expect(t, contains('唯一正確答案'));
    });
  });

  group('時間差語義——與因果反饋一致', () {
    test('跨日界：昨天 23:50 到今天 00:10 = 昨天不是今天', () {
      // 驗證「昨天」語義：diff < 24h 但跨日界
      final n = DateTime(2026, 9, 12, 0, 10);
      final at = DateTime(2026, 9, 11, 23, 50);
      final days = n.difference(DateTime(at.year, at.month, at.day)).inDays;
      expect(days, 1); // 語義上的昨天
    });
  });

  group('L4 紀念日引擎', () {
    final t = CompanionTimeline(
      companionId: 'c1',
      firstMetAt: DateTime(2026, 8, 27),
      elapsedDays: 17,
    );

    test('第 17 天 → 第 30 天滿月在 13 天後（60 天窗內）', () {
      final ms = TimeSenseService.upcomingMilestones(t, now: DateTime(2026, 9, 12));
      final fullMoon = ms.where((m) => m.label == '相遇滿月').toList();
      expect(fullMoon, isNotEmpty);
      expect(fullMoon.first.daysLeft, 13); // 8/27+29天=9/25，距今 13 天
      expect(fullMoon.first.date, DateTime(2026, 9, 25));
    });

    test('第 100 天 = 2026-12-04（與 timeline section 錨點一致）', () {
      final ms = TimeSenseService.upcomingMilestones(t, now: DateTime(2026, 9, 12));
      // 第 100 天距 9/12 超過 60 天窗——不應出現
      expect(ms.where((m) => m.day == 100), isEmpty);
      // 但拉近看：12 月初看，第 100 天就在窗內
      final ms2 = TimeSenseService.upcomingMilestones(t, now: DateTime(2026, 12, 1));
      final d100 = ms2.where((m) => m.day == 100).toList();
      expect(d100, isNotEmpty);
      expect(d100.first.date, DateTime(2026, 12, 4));
      expect(d100.first.daysLeft, 3);
    });

    test('一週年偵測：2027-08-27（每年）', () {
      final ms = TimeSenseService.upcomingMilestones(t, now: DateTime(2027, 8, 1));
      final anniv = ms.where((m) => m.kind == MilestoneKind.anniversary).toList();
      expect(anniv, isNotEmpty);
      expect(anniv.first.date, DateTime(2027, 8, 27));
      expect(anniv.first.label, '1 週年');
    });

    test('里程碑注入片段：臨近才出現，遠了不出現（寧精勿多）', () {
      // 9/12：滿月 13 天後——在窗內，應注入（帶日期，防模型自算）
      final s = TimeSenseService.buildMilestoneSection(t, now: DateTime(2026, 9, 12));
      expect(s, isNotNull);
      expect(s, contains('相遇滿月=2026/9/25'));
      expect(s, contains('13 天後'));
      expect(s, contains('禁止重新推算'));
      // 10/15：滿月已過，第 100 天在 50 天後——仍在 60 天窗內（唯一項）
      final s2 = TimeSenseService.buildMilestoneSection(t, now: DateTime(2026, 10, 15));
      expect(s2, contains('第 100 天=2026/12/4（50 天後）'));
      expect(s2!.contains('相遇滿月'), isFalse); // 滿月已過不回報
      // 拉到 11/20：第 100 天 14 天後——仍窗內；拉到 12/10 之後（100天已過）→ null
      final s3 = TimeSenseService.buildMilestoneSection(t, now: DateTime(2026, 12, 10));
      expect(s3, isNull);
    });
  });
}
