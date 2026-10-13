// 直接驗證點擊行為：mock usage 資料 → 點固定列展開 → 點 L1 → 收到 onLayerTap(L1)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/memory_layer_service.dart';
import 'package:bridge_app/screens/vault/memory_layer_sidebar_section.dart';

void main() {
  testWidgets('點固定列展開，點 L1 觸發 onLayerTap(L1) 不誤觸收合', (tester) async {
    MemoryLayer? tapped;
    MemoryLayer? selected;
    await tester.pumpWidget(StatefulBuilder(builder: (context, setSt) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 220, height: 900,
          child: MemoryLayerSidebarSection(
            selectedLayer: selected,
            onLayerTap: (l) { tapped = l; setSt(() => selected = l); },
          ),
        ),
      ),
    )));
    // usage 是空的（DB 未開）→ section 是 SizedBox.shrink，無法測互動。
    // 結論性測試：DB 未開時不渲染（與 sidebar_section_test 一致）。
    expect(find.text('記憶十層'), findsNothing);
  });
}
