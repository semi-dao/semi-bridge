// vector_sketch_junk_filter_test.dart
// [小葵 2026-10-14 Blue 拍板「素描浪費修復」] TDD——junk filter＋蒸餾指紋
// 純邏輯測試：不碰 BrainDatabase singleton、不碰真庫。
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/vector_db/vector_sketch_service.dart';

void main() {
  group('isJunkFolder——依賴樹/建置產物過濾', () {
    test('venv 與 site-packages 是垃圾', () {
      expect(
        VectorSketchService.isJunkFolder(
            '04-備份/_laya-bench_20261011_0153/venv311/lib/python3.11/site-packages'),
        isTrue,
      );
      expect(
        VectorSketchService.isJunkFolder('04-備份/x/venv/lib/site-packages/httpx'),
        isTrue,
      );
    });

    test('Xcode/Flutter/CocoaPods 建置產物是垃圾', () {
      expect(VectorSketchService.isJunkFolder('04-備份/app/macos/Runner.xcodeproj'), isTrue);
      expect(VectorSketchService.isJunkFolder('04-備份/app/macos/Runner.xcworkspace'), isTrue);
      expect(VectorSketchService.isJunkFolder('04-備份/app/macos/Pods'), isTrue);
      expect(VectorSketchService.isJunkFolder('04-備份/app/.dart_tool'), isTrue);
      expect(VectorSketchService.isJunkFolder('04-備份/app/macos/Flutter/ephemeral'), isTrue);
      expect(VectorSketchService.isJunkFolder('04-備份/app/node_modules'), isTrue);
      expect(VectorSketchService.isJunkFolder('04-備份/repo/.git'), isTrue);
      expect(VectorSketchService.isJunkFolder('04-備份/repo/__pycache__'), isTrue);
    });

    test('真實農場/知識庫資料夾不是垃圾', () {
      expect(VectorSketchService.isJunkFolder('01_現況紀錄/照片紀錄/營本部/苔蘚麵包盒'), isFalse);
      expect(VectorSketchService.isJunkFolder('04_農務研究/每日判讀'), isFalse);
      expect(VectorSketchService.isJunkFolder('07_對外素材與輸出/農場日記/2026'), isFalse);
      // 備份根層的專案本體（非依賴樹）也不該誤殺
      expect(VectorSketchService.isJunkFolder('04-備份/2026-09-05_v266-卡頓畢業'), isFalse);
    });
  });

  group('distillFingerprint——輸入沒變就跳過 LLM', () {
    test('同清單同指紋', () {
      final a = VectorSketchService.distillFingerprint(['b', 'a', 'c'], 100);
      final b = VectorSketchService.distillFingerprint(['c', 'a', 'b'], 100);
      expect(a, b);
    });

    test('清單變（新增未分類）→ 指紋變', () {
      final a = VectorSketchService.distillFingerprint(['a', 'b'], 100);
      final b = VectorSketchService.distillFingerprint(['a', 'b', 'new'], 101);
      expect(a, isNot(b));
    });

    test('清單不變但總資產數變 → 指紋變（新照片要重掃規則層）', () {
      final a = VectorSketchService.distillFingerprint(['a'], 100);
      final b = VectorSketchService.distillFingerprint(['a'], 67708);
      expect(a, isNot(b));
    });

    test('空清單也有穩定指紋', () {
      expect(
        VectorSketchService.distillFingerprint([], 0),
        VectorSketchService.distillFingerprint([], 0),
      );
    });
  });
}
