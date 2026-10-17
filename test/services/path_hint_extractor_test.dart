// path_hint_extractor_test.dart
// [路徑提示注入 2026-09-14] 萃取器測試——零設定語意的關鍵案例
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/vector_db/path_hint_extractor.dart';

void main() {
  final ext = PathHintExtractor.instance;

  test('農場案例：品種/地點從資料夾自動萃取', () {
    const path = '/Volumes/DATA/農場資料庫/01_現況紀錄/照片紀錄/營本部/2026-04-07/'
        'Blue陽台/象耳鹿角蕨母株/IMG_1781.jpeg';
    final hint = ext.extractHint(path);
    expect(hint, contains('象耳鹿角蕨母株'));
    expect(hint, contains('陽台'));
    // 結構詞與日期不進提示
    expect(hint, isNot(contains('照片紀錄')));
    expect(hint, isNot(contains('2026')));
  });

  test('工作案例：專案資料夾名照樣萃取（形形色色內容零設定生效）', () {
    const path = '/Users/mary/Documents/工作/Q3財報簡報/公司/董事會/slide.png';
    final hint = ext.extractHint(path);
    expect(hint, contains('董事會'));
    expect(hint, contains('公司'));
  });

  test('流水號/相機前綴剔除，純數字層剔除', () {
    const path = '/media/100ANDRO/DSC_0102/2026-04-07/123456.jpg';
    final hint = ext.extractHint(path);
    expect(hint, isEmpty);
  });

  test('buildPrompt：無提示時原 prompt 不動，有提示時含護欄語', () {
    const base = '描述這張圖';
    expect(ext.buildPrompt(base, '/tmp/123.jpg'), base);
    final withHint = ext.buildPrompt(
        base, '/Volumes/DATA/農場資料庫/魔鬼辣椒/IMG_1.jpeg');
    expect(withHint, contains('路徑提示'));
    expect(withHint, contains('不可**寫畫面外項目')); // 防幻覺護欄
    expect(withHint, contains('魔鬼辣椒'));
  });
}
