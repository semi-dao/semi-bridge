// H5：/galaxy_missions 資料包——排程卡＋專案門
// （service-level 測試：ScheduleRegistry 已有專測；此處驗 JSON 形狀組裝邏輯）
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/models/schedule_card.dart';

void main() {
  test('ScheduleCard 溫度維度與 warmLine 序列化形狀（galaxy_missions 契約）', () {
    final life = ScheduleCard(
      id: 'j1',
      name: '小葵每日安靜時刻',
      rawSchedule: '0 22 * * *',
      humanSchedule: '每天 22:00',
      warmth: ScheduleWarmth.life,
      warmLine: '一天的最後，留一段安靜給自己',
    );
    // galaxy_missions JSON 契約：warmth 用 name（'life'/'work'）、warmLine 可 null
    expect(life.warmth.name, 'life');
    expect(life.warmLine, isNotNull);

    final work = ScheduleCard(
      id: 'j2',
      name: 'Session自動清理',
      rawSchedule: '0 3 * * *',
      humanSchedule: '每天 03:00',
      warmth: ScheduleWarmth.work,
    );
    expect(work.warmth.name, 'work');
    expect(work.warmLine, isNull); // 不帶 warmLine → JS 端 undefined → 不渲染心意行
  });
}
