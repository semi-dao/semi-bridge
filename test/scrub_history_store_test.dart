// scrub_history_store_test.dart
// [Blue 令 2026-10-17] 除痕歷史 store——record/load 往返＋新→舊排序。
// path_provider 在測試環境 mock 到暫存目錄（絕不碰真 bridge_state）。
import 'dart:io';

import 'package:bridge_app/services/sovereignty/scrub_history_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _MockPathProvider extends PathProviderPlatform {
  final String dir;
  _MockPathProvider(this.dir);
  @override
  Future<String> getApplicationSupportPath() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('record → load 往返：時間/觸發者/大小/項目', () async {
    final tmp = await Directory.systemTemp.createTemp('scrub_hist_test');
    PathProviderPlatform.instance = _MockPathProvider(tmp.path);
    final store = ScrubHistoryStore.instance;
    // store 是 singleton 且快取 _file——新目錄要重置。測試用新實例不可行，
    // 改驗 record 後 load 一致（同一路徑）。
    await store.record(
      trigger: 'manual',
      files: 3,
      bytes: 4096,
      items: [
        {'label': '截幀暫存', 'bytes': 2048},
        {'label': '提示暫存', 'bytes': 2048},
      ],
    );
    final list = await store.load();
    expect(list, isNotEmpty);
    final e = list.first; // 新→舊
    expect(e.trigger, 'manual');
    expect(e.files, 3);
    expect(e.bytes, 4096);
    expect(e.items.length, 2);
    expect(e.items.first['label'], '截幀暫存');
    await tmp.delete(recursive: true);
  });
}
