// Golden Test PoC — 手機版 UI 改動驗收演示
//
// 用途：證明「UI 改動 → 無頭 golden diff → 紅字報告」機制
//
// 執行流程：
//   1. 確保 kSimulateChange = false，跑 `flutter test --update-goldens` 產 baseline
//   2. 改成 kSimulateChange = false，跑 `flutter test` 應失敗（紅字）
//   3. 改回 false，確認重新綠燈
//
// 注意：
//   - 此檔**不**會 commit，只用 PoC 驗證
//   - failures/ 目錄會自動產生 diff 圖（如果測試失敗）
//   - baseline 放在 test/golden/goldens/mobile_poc_goldens/card_v1.png

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ============================================================
// ⚠️ 控制開關：把這個設成 true 會「模擬 UI 改動」
// ============================================================
const bool kSimulateChange = false;

// ============================================================
// 手機版 UI 卡片 widget（模擬真實 App 內卡片）
// ============================================================
class PocCard extends StatelessWidget {
  const PocCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSimulateChange ? const Color(0xFF2E7D32) : const Color(0xFF1E1E1E), // 改動點：背景色
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題
          Text(
            '測試卡片',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // 副標
          Text(
            '這是一個模擬的手機版 UI 卡片，用於驗證 golden test 機制。',
            style: TextStyle(
              color: const Color(0xFFCECECE),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          // 按鈕
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: kSimulateChange ? const Color(0xFFEF5350) : const Color(0xFF55B3FF), // 改動點：按鈕顏色
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              '點擊測試',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 測試套件
// ============================================================
void main() {
  group('PoC - 手機版 UI 改動驗收', () {
    testWidgets('卡片 baseline 測試', (tester) async {
      // 設定 iPhone 14 Pro 尺寸（390×844）
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: PocCard(),
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(PocCard),
        matchesGoldenFile('mobile_poc_goldens/card_v1.png'),
      );
    });
  });
}
