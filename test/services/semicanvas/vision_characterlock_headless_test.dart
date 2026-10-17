// vision_characterlock_headless_test.dart
// [T10① 2026-10-17] headless 執行器——vision/characterLock 收編回歸鎖。
// 病例：排程路徑 vision/characterLock 直接失敗「請使用畫布原生執行器」，
// schedule_runs.jsonl 30 筆全是這個 error。收編後走 CapabilityExecutor
// 同路；本測試鎖「不再出現那句話」＋誠實失敗路徑（缺圖/缺服務）。
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/semicanvas/workflow_executor.dart';
import 'package:bridge_app/services/semicanvas/workflow_node_adapters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  test('T10①-1 vision 無上游無本圖 → 誠實失敗（不是請使用原生執行器）', () async {
    final adapters = WorkflowNodeAdapters();
    final exec = adapters.createNodeExecutor();
    final r = await exec('node_v', WorkflowNodeType.vision, {},
        const UpstreamData());
    expect(r.success, isFalse);
    // 收編核心：永遠不再出現「請使用畫布原生執行器」
    expect(r.errorMessage, isNot(contains('畫布原生執行器')));
    expect(r.errorMessage, contains('圖片輸入'));
  });

  test('T10①-2 vision 帶本圖無服務 → 原圖直通成功', () async {
    // tmp PNG（1x1）
    final f = File(
        '${Directory.systemTemp.path}/t10_vision_test_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    addTearDown(() => f.deleteSync());

    final adapters = WorkflowNodeAdapters();
    final exec = adapters.createNodeExecutor();
    final r = await exec('node_v', WorkflowNodeType.vision,
        {'image': f.path}, const UpstreamData());
    expect(r.success, isTrue, reason: '原圖直通：無服務也該把圖往下傳');
    expect(r.output, contains('原圖直通'));
    expect(r.imageData, isNotNull);
  });

  test('T10①-3 characterLock 無參考圖 → 誠實失敗（不是請使用原生執行器）', () async {
    final adapters = WorkflowNodeAdapters();
    final exec = adapters.createNodeExecutor();
    final r = await exec('node_cl', WorkflowNodeType.characterLock,
        {'prompt': '一隻貓'}, const UpstreamData());
    expect(r.success, isFalse);
    expect(r.errorMessage, isNot(contains('畫布原生執行器')));
    expect(r.errorMessage, contains('參考圖片'));
  });
}
