// MemoryLayerService 測試——2域10層（H2/M2）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/memory_layer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 用真實 sqlite3 開臨時 DB（不碰 brain_container.db——測試隔離鐵則）
  late MemoryLayerService svc;
  late Directory tmp;

  setUp(() {
    // 直接驗證層定義與純邏輯（DB 整合測試需要 BrainDatabase 初始化鏈，
    // 留給 App 層驗證——migration 在啟動時自動跑）
  });

  test('十層定義完整：碼不重複、域分佈正確', () {
    final codes = MemoryLayer.values.map((l) => l.code).toSet();
    expect(codes.length, 10, reason: '剛好十層');
    final working = MemoryLayer.values.where((l) => l.domain == Domain.working);
    expect(working.length, 3, reason: '工作域三層 L1-L3');
    final longTerm = MemoryLayer.values.where((l) => l.domain == Domain.longTerm);
    expect(longTerm.length, 7, reason: '長期域七層 L4-L10');
  });

  test('軟上限只有工作域有；長期域全部 0（無上限）', () {
    for (final l in MemoryLayer.values) {
      if (l.domain == Domain.longTerm) {
        expect(l.softCapBytes, 0, reason: '${l.code} 不設上限');
      } else {
        expect(l.softCapBytes, greaterThan(0), reason: '${l.code} 有軟上限');
      }
    }
  });

  test('Blue 拍板數值：L1=3KB / L2=2KB / L3=2KB', () {
    expect(MemoryLayer.l1Rules.softCapBytes, 3 * 1024);
    expect(MemoryLayer.l2Identity.softCapBytes, 2 * 1024);
    expect(MemoryLayer.l3ProjectHot.softCapBytes, 2 * 1024);
  });

  test('fromCode 解析＋未知層容錯', () {
    expect(MemoryLayer.fromCode('L1'), MemoryLayer.l1Rules);
    expect(MemoryLayer.fromCode('L10'), MemoryLayer.l10Reflection);
    expect(MemoryLayer.fromCode(null), isNull);
    expect(MemoryLayer.fromCode('L99'), isNull);
  });

  test('層碼排序＝溫度排序（L1 最熱 → L10 最冷）', () {
    final codes = MemoryLayer.values.map((l) => l.code).toList();
    expect(codes.first, 'L1');
    expect(codes.last, 'L10');
  });
}
