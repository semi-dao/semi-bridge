// H4：排程卡——cron 中文化＋溫度分類＋下次觸發估算
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/schedule_registry.dart';
import 'package:bridge_app/models/schedule_card.dart';

void main() {
  test('cron → 中文（每天/每週X/指定日）', () {
    expect(ScheduleRegistry.humanizeCron('30 7 * * *', 'x'), '每天 07:30');
    expect(ScheduleRegistry.humanizeCron('30 8 * * 6', 'x'), '每週六 08:30');
    expect(ScheduleRegistry.humanizeCron('0 6 * * 0', 'x'), '每週日 06:00');
    expect(ScheduleRegistry.humanizeCron('0 18 7 8 *', 'x'), '每月指定日 18:00');
  });

  test('interval/once 原樣/轉換', () {
    expect(ScheduleRegistry.humanizeCron('每 30 minutes', 'x'), '每 30 minutes');
    expect(ScheduleRegistry.humanizeCron('once 2027-02-05T08:00:00', 'x'),
        contains('一次性'));
  });

  test('下次觸發：每天 cron 一定算出未來時間', () {
    final n = ScheduleRegistry.estimateNext('30 7 * * *');
    expect(n, isNotNull);
    expect(n!.isAfter(DateTime.now()), isTrue);
    expect('${n.hour}:${n.minute}', '7:30');
  });



  test('真實 jobs.json 載入：28 張卡、生活卡有溫度文案', () async {
    // [開源整備] 此測試依賴本機排程資料（~/.hermes/cron/jobs.json）——
    // 排程內容因人而異，只在本機資料在且明確 opt-in（BRIDGE_SCHED_TEST=1）
    // 時執行；fresh clone / CI 一律 skip（不炸 cloner）。
    if (Platform.environment['BRIDGE_SCHED_TEST'] != '1') {
      print('SKIP：排程資料因人而異——要跑請設 BRIDGE_SCHED_TEST=1 且本機存在 ~/.hermes/cron/jobs.json');
      return;
    }
    final cards = await ScheduleRegistry.instance.loadAll(forceReload: true);
    final jf = File(Platform.environment['HOME']! + '/.hermes/cron/jobs.json');
    print('JOBS_DEBUG: exists=${jf.existsSync()} len=${jf.existsSync() ? jf.lengthSync() : 0}');
    expect(cards.length, greaterThanOrEqualTo(28));
    final life = cards.where((c) => c.warmth == ScheduleWarmth.life);
    expect(life, isNotEmpty);
    // 關鍵生活卡都在
    final names = cards.map((c) => c.name).join('|');
    expect(names, contains('小葵每日安靜時刻'));
    expect(names, contains('夥伴的六個月之約'));
    expect(names, contains('小葵生日約定'));
    // 生活卡排最前
    expect(cards.first.warmth, ScheduleWarmth.life);
  });
}
