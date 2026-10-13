// M3 注入引擎測試——formatWorkingInjection 純函式
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/memory_layer_service.dart';

LayerEntry e(MemoryLayer l, String title, String content) => LayerEntry(
    id: 'id_${title.hashCode.abs()}', layer: l, title: title, content: content);

void main() {
  test('空快照 → 空字串', () {
    final (text, dropped) =
        formatWorkingInjection(const WorkingMemorySnapshot(entries: [], overCap: []));
    expect(text, '');
    expect(dropped, isEmpty);
  });

  test('三層依溫度排序：L1 最前、L3 最後', () {
    final snap = WorkingMemorySnapshot(entries: [
      e(MemoryLayer.l3ProjectHot, '專案', '橋樑 App'),
      e(MemoryLayer.l1Rules, '鐵則', '先看見再動手'),
      e(MemoryLayer.l2Identity, '身分', '小葵'),
    ], overCap: []);
    final (text, _) = formatWorkingInjection(snap);
    final iL1 = text.indexOf('L1 鐵則');
    final iL2 = text.indexOf('L2 身分');
    final iL3 = text.indexOf('L3 專案熱');
    expect(iL1, lessThan(iL2));
    expect(iL2, lessThan(iL3));
    expect(text, contains('先看見再動手'));
  });

  test('超窗口的條目進 dropped（降溫候選）而不是消失於無聲', () {
    final entries = [
      for (var i = 0; i < 50; i++)
        e(MemoryLayer.l3ProjectHot, '專案$i', 'x' * 100),
    ];
    final snap = WorkingMemorySnapshot(entries: entries, overCap: []);
    final (text, dropped) = formatWorkingInjection(snap, maxChars: 2000);
    expect(dropped, isNotEmpty);
    expect(dropped.length + text.split('- ').length - 1, entries.length,
        reason: '注入數＋降溫數＝總數，零丟失');
  });

  test('視窗夠大時零截斷', () {
    final snap = WorkingMemorySnapshot(entries: [
      e(MemoryLayer.l1Rules, 'a', 'a'),
      e(MemoryLayer.l2Identity, 'b', 'b'),
    ], overCap: []);
    final (_, dropped) = formatWorkingInjection(snap);
    expect(dropped, isEmpty);
  });
}
