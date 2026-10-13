// H1：origin 欄（出身標注）序列化回環
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/slots/slot_registry.dart';

void main() {
  test('origin 序列化回環：寫入 → 讀回', () {
    final rec = SlotRecord(
      id: 't1',
      userLabel: 'arxiv',
      sourceRepo: 'https://github.com/x/arxiv',
      category: '研究調查',
      status: SlotStatus.disabled,
      origin: 'Hermes',
      createdAt: DateTime(2026, 10, 8),
    );
    final json = rec.toJson();
    expect(json['origin'], 'Hermes');
    final back = SlotRecord.fromJson(json);
    expect(back.origin, 'Hermes');
    expect(back.category, '研究調查');
  });

  test('origin 為 null 時（舊資料）不寫入 JSON、讀回 null', () {
    final rec = SlotRecord(
      id: 't2',
      userLabel: 'mermview',
      sourceRepo: '',
      category: '網頁工具',
      status: SlotStatus.disabled,
      createdAt: DateTime(2026, 10, 8),
    );
    final json = rec.toJson();
    expect(json.containsKey('origin'), false);
    expect(SlotRecord.fromJson(json).origin, isNull);
  });
}
