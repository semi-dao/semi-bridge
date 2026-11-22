import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/models/conversation.dart';

void main() {
  group('taskBinding 地基（SPEC §8.3/8.6）', () {
    test('createTaskBound：出生自綁任務 JSON', () {
      final task = TaskCardData(
        id: 't-001', name: '晨間拾穗', kind: 'scheduled',
        schedule: '每天 08:00', nextRunAt: '2026-11-13T08:00',
        lastRunOk: true, artifacts: ['拾穗日誌_1112.md'],
      );
      final conv = Conversation.createTaskBound(task);
      expect(conv.isTaskBound, isTrue);
      expect(conv.boundTaskName, '晨間拾穗');
      expect(conv.taskBinding!['schedule'], '每天 08:00');
      expect(conv.id.startsWith('task-t-001-'), isTrue);
    });

    test('序列化往返：taskBinding 不丟', () {
      final task = TaskCardData(
        id: 't-002', name: 'IG 晚間發佈', kind: 'scheduled',
        schedule: '每天 18:00', lastRunOk: false,
        lastRunError: 'API 402 餘額不足', artifacts: ['發佈失敗_1111.log'],
      );
      final conv = Conversation.createTaskBound(task);
      final back = Conversation.fromJson(conv.toJson());
      expect(back.isTaskBound, isTrue);
      expect(back.boundTaskName, 'IG 晚間發佈');
      // TaskCardData 往返
      final t2 = TaskCardData.fromJson(back.taskBinding!);
      expect(t2.lastRunOk, isFalse);
      expect(t2.lastRunError, 'API 402 餘額不足');
      expect(t2.artifacts, ['發佈失敗_1111.log']);
    });

    test('舊資料相容：無 taskBinding 的 json 照常載入', () {
      final conv = Conversation.create(title: '一般對話');
      final back = Conversation.fromJson(conv.toJson());
      expect(back.isTaskBound, isFalse);
      expect(back.boundTaskName, isNull);
    });

    test('copyWith 更新任務綁定（任務變更→綁定同步）', () {
      final task = TaskCardData(
        id: 't-003', name: '晨間拾穗', kind: 'scheduled',
        schedule: '每天 08:00', lastRunOk: true,
      );
      final conv = Conversation.createTaskBound(task);
      final changed = TaskCardData(
        id: 't-003', name: '晨間拾穗', kind: 'scheduled',
        schedule: '每天 07:30', lastRunOk: true,
      );
      final updated = conv.copyWith(taskBinding: changed.toJson());
      expect(updated.taskBinding!['schedule'], '每天 07:30');
      expect(conv.taskBinding!['schedule'], '每天 08:00'); // 原本不動
    });
  });
}
