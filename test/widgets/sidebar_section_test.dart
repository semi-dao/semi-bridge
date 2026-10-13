// 側欄十層區 widget 測試：點固定列展開→點 L1→onLayerTap 收到 L1
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/memory_layer_service.dart';
import 'package:bridge_app/screens/vault/memory_layer_sidebar_section.dart';

void main() {
  // 不初始化 DB——usage() fail-quiet 回空 → section 顯示 SizedBox.shrink
  testWidgets('DB 未開時安靜退場', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: MemoryLayerSidebarSection(
        selectedLayer: null,
        onLayerTap: (_) {},
      ),
    )));
    await tester.pump();
    expect(find.text('記憶十層'), findsNothing);
  });
}
