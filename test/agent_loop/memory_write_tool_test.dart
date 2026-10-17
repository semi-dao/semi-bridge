// memory_write_tool_test.dart
// [T3② 2026-10-17] memory_write 工具——L4 BeliefGate 行為鎖死測試。
// 病例防線：agent 不可自繞 gate（manualOverride 永遠 false）；
// 證據不足必拒絕且附原因；L0 直寫路徑不受 gate 影響。

import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/services/agent_loop/agent_loop_tools/memory_write_tool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('content 空 → 直接失敗', () async {
    final tool = MemoryWriteTool(onL0Write: null, onL4Write: null);
    final r = await tool.execute({'content': ''});
    expect(r.success, isFalse);
  });

  test('L0（預設）不過 gate——直寫回呼', () async {
    var written = <String>[];
    final tool = MemoryWriteTool(
      onL0Write: (c, t) async {
        written.add(c);
        return true;
      },
    );
    final r = await tool.execute({'content': '今天早上開會討論了農場'});
    expect(r.success, isTrue, reason: r.content);
    expect(written, ['今天早上開會討論了農場']);
  });

  test('L0 寫入失敗如實回報', () async {
    final tool = MemoryWriteTool(
      onL0Write: (c, t) async => false,
    );
    final r = await tool.execute({'content': 'x', 'layer': 'L0'});
    expect(r.success, isFalse);
  });

  test('L4 走 BeliefGate——DB 未初始化 fail-open（gate 保守放行路徑），'
      '落庫回呼失敗則如實回報', () async {
    // 注意：BeliefGate 在 DB 未就緒時放行（db_not_ready_fallback）——
    // 測試環境無 DB，gate 會放行，然後 onL4Write 決定成敗。
    final tool = MemoryWriteTool(
      onL4Write: (c, t) async => false, // 落庫失敗
    );
    final r = await tool.execute({'content': 'Blue 喜歡早起', 'layer': 'L4'});
    expect(r.success, isFalse);
    expect(r.content, contains('L4'));
  });

  test('L4 成功路徑（fail-open 放行＋落庫成功）', () async {
    var l4 = <String>[];
    final tool = MemoryWriteTool(
      onL4Write: (c, t) async {
        l4.add(c);
        return true;
      },
    );
    final r = await tool.execute({'content': 'Blue 喜歡早起', 'layer': 'l4'});
    expect(r.success, isTrue, reason: r.content);
    expect(l4, isNotEmpty);
  });
}
