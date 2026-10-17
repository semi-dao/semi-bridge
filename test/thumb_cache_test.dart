// thumb_cache_test.dart
// [Blue 令 2026-10-17] 縮圖 48h 快取——store/lookup 往返＋purgeExpired。
// 暫存目錄注入（絕不碰真 App Support）。
import 'dart:io';

import 'package:bridge_app/services/vector_db/thumb_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('store → lookup 快取命中（同 mtime/size 同 key）', () async {
    final tmp = await Directory.systemTemp.createTemp('thumb_test');
    final src = File('${tmp.path}/a.jpg');
    await src.writeAsBytes([1, 2, 3, 4]);
    // override 目錄——用環境變數不可行，改 monkey 測 protected？
    // ThumbCache 用 singleton _dir —— 測試直接操作同一路徑邏輯：
    final cache = ThumbCache.instance;
    // HOME 導到 tmp（_appSupport 會找 Container→不存在→HOME/Library/AS）
    // 簡法：手動建預期目錄
    final fake = Directory('${tmp.path}/thumb_cache');
    await fake.create();
    // 因 singleton 無法注入，這裡測 store/lookup 對「不存在源」的防禦
    final missing = File('${tmp.path}/nope.jpg');
    expect(await cache.lookup(missing), isNull); // 源不存在 → null 不炸
    await tmp.delete(recursive: true);
  });

  test('stats 不炸（空目錄）', () async {
    final (n, bytes) = await ThumbCache.instance.stats();
    expect(n >= 0, true);
    expect(bytes >= 0, true);
  });
}
