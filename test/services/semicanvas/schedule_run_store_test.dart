// schedule_run_store_test.dart
// [W2 2026-10-08] 排程執行落盤 + 產出記錄歸位測試
// 測試隔離鐵則：臨時目錄（不碰 App 沙箱真檔）

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/semicanvas/schedule_run_store.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('w2_runstore_test');
    // path_provider 注入臨時目錄
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('append → jsonl 一行一筆、欄位完整', () async {
    final path = '${tmp.path}/schedule_runs.jsonl';
    final f = File(path);
    await f.create();

    final rec = ScheduleRunRecord(
      jobId: 'wf-123',
      jobTitle: '早安咖啡提醒',
      canvasId: 'canvas-abc',
      firedAt: DateTime(2026, 10, 8, 9, 0, 1),
      success: true,
      duration: const Duration(seconds: 12),
      outputType: 'voice',
      outputPaths: ['/Users/x/bridge_media/tts/coffee.aiff'],
      summary: '語音 3 節點',
    );

    await f.writeAsString('${jsonEncode(rec.toJson())}\n', mode: FileMode.append);

    final lines = await f.readAsLines();
    expect(lines.length, 1);
    final back = ScheduleRunRecord.fromJson(jsonDecode(lines.first));
    expect(back.jobId, 'wf-123');
    expect(back.jobTitle, '早安咖啡提醒');
    expect(back.success, true);
    expect(back.outputType, 'voice');
    expect(back.outputPaths, ['/Users/x/bridge_media/tts/coffee.aiff']);
    expect(back.summary, '語音 3 節點');
    expect(back.firedAt, DateTime(2026, 10, 8, 9, 0, 1));
  });

  test('失敗紀錄 round-trip（error 帶原因、success=false）', () async {
    final rec = ScheduleRunRecord(
      jobId: 'wf-456',
      jobTitle: '週報圖卡',
      canvasId: 'canvas-def',
      firedAt: DateTime(2026, 10, 8, 14, 0),
      success: false,
      error: 'API 逾時（120000ms）',
    );
    final back = ScheduleRunRecord.fromJson(jsonDecode(jsonEncode(rec.toJson())));
    expect(back.success, false);
    expect(back.error, 'API 逾時（120000ms）');
    expect(back.outputPaths, isEmpty);
  });

  group('ScheduleOutputResolver（產出記錄歸位——原位置如實記錄，不搬不移）', () {
    test('音檔路徑萃取 → type=voice', () {
      final r = ScheduleOutputResolver.resolve([
        const NodeExecutionResultLite(
          nodeId: 'n1',
          success: true,
          output: 'TTS 完成：/Users/x/bridge_media/tts/coffee-0809.aiff',
        ),
      ]);
      expect(r.type, 'voice');
      expect(r.paths, ['/Users/x/bridge_media/tts/coffee-0809.aiff']);
      expect(r.summary, '語音');
    });

    test('圖片 + http URL 萃取', () {
      final r = ScheduleOutputResolver.resolve([
        const NodeExecutionResultLite(
          nodeId: 'n2',
          success: true,
          output: '生成 https://cdn.example.com/img.png 完成',
        ),
      ]);
      expect(r.type, 'image');
      expect(r.paths, ['https://cdn.example.com/img.png']);
    });

    test('多結果去重、無產出 → type=null paths=[]', () {
      final r = ScheduleOutputResolver.resolve([
        const NodeExecutionResultLite(nodeId: 'n3', success: true, output: '純文字輸出，沒有檔案'),
        const NodeExecutionResultLite(
          nodeId: 'n4',
          success: true,
          output: '同一張 /tmp/a.png 和 /tmp/a.png',
        ),
      ]);
      expect(r.paths, ['/tmp/a.png']);
      final empty = ScheduleOutputResolver.resolve([
        const NodeExecutionResultLite(nodeId: 'n5', success: true, output: 'ok'),
      ]);
      expect(empty.type, isNull);
      expect(empty.paths, isEmpty);
    });
  });
}
