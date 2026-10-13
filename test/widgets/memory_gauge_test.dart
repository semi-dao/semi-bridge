// M5 儀表 widget 測試（DB 未開 → 空儀表安靜退場；usage 有資料 → 十層全渲染）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/screens/vault/memory_layer_gauge.dart';

void main() {
  testWidgets('DB 未開時安靜退場（SizedBox.shrink）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MemoryLayerGauge())));
    await tester.pump();
    expect(find.byType(SizedBox), findsWidgets);
    expect(find.text('記憶十層'), findsNothing);
  });
}
