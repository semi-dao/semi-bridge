// [小葵 2026-10-14 大腦圖譜橘星二波段] build 產物 junk 判定
// 04-備份/_ARCHIVED_semi-bridge/build/macos（.pcm/.dia/.d/.scan 共 1.7 萬檔）
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/vector_db/vector_sketch_service.dart';

void main() {
  test('封存 repo 的 build/macos 產物是 junk', () {
    expect(
        VectorSketchService.isJunkFolder(
            '04-備份/_ARCHIVED_semi-bridge_20261011_0152/build/macos/Build/Products/x.pcm'),
        isTrue);
  });

  test('Build/Products 組合是 junk', () {
    expect(
        VectorSketchService.isJunkFolder('any/build/products/Debug/app.d'),
        isTrue);
  });

  test('正常資料夾路徑不誤判', () {
    expect(
        VectorSketchService.isJunkFolder('01_現況紀錄/照片紀錄/黛粉芋_1.jpg'),
        isFalse);
    expect(VectorSketchService.isJunkFolder('06_AI協作與知識庫/筆記.md'),
        isFalse);
  });
}
