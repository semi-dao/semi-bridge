import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/schedule_registry.dart';
import 'package:bridge_app/models/conversation.dart';

void main() {
  test('ScheduleRegistry 讀真 jobs.json：前次成敗有值', () async {
    final cards = await ScheduleRegistry.instance.loadAll(forceReload: true);
    expect(cards, isNotEmpty);
    // 至少能區分：有成功卡也有失敗卡（真實資料有 402 錯誤）
    final ok = cards.where((c) => c.lastRunOk);
    final bad = cards.where((c) => !c.lastRunOk);
    expect(ok, isNotEmpty);
    // print('ok=${ok.length} bad=${bad.length}');
    for (final c in bad.take(3)) {
      expect(c.lastRunError, isNotNull);
    }
  });

  test('ScheduleCard → TaskCardData → Conversation 出生自綁', () async {
    final cards = await ScheduleRegistry.instance.loadAll();
    final card = cards.first;
    final task = card.toTaskCardData();
    final conv = Conversation.createTaskBound(task);
    expect(conv.isTaskBound, isTrue);
    expect(conv.boundTaskName, card.name);
    expect(conv.taskBinding!['lastRunOk'], card.lastRunOk);
  });
}
