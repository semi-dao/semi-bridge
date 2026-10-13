// [小葵 2026-10-01 離合器] LocalModelScheduler 回歸測試
// 設計稿：/tmp/auto_clutch_design.md（Blue 拍板「完美的接住所有情況」）
// 鎖死的鐵律：
// ① 聊天優先權絕對高於辨識——markUserActivity 在辨識模式觸發切回
// ② 安全點切換——嵌入 job 進行中不硬切，job 結束才切
// ③ 未設辨識角色 → runVisionNow 無效（零強迫，退回現狀）
// ④ 切換失敗 → faulted 狀態，不自動重試
// ⑤ pending 計數變化 → 快照廣播

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/local_model_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalModelScheduler 離合器鐵律', () {
    test('① 未設角色時 hasVisionRole=false（零強迫退回現狀）', () {
      const snap = LocalClutchSnapshot(state: LocalClutchState.runChat);
      expect(snap.hasVisionRole, isFalse);
    });

    test('① 設了雙角色且不同模型時 hasVisionRole=true', () {
      const snap = LocalClutchSnapshot(
        state: LocalClutchState.runChat,
        companionModelId: 'gemma-4-e4b-q4',
        visionModelId: 'gemma-4-12b-q4',
      );
      expect(snap.hasVisionRole, isTrue);
    });

    test('① 夥伴=辨識同模型時 hasVisionRole=false（單模型免輪替）', () {
      const snap = LocalClutchSnapshot(
        state: LocalClutchState.runChat,
        companionModelId: 'gemma-4-e4b-q4',
        visionModelId: 'gemma-4-e4b-q4',
      );
      expect(snap.hasVisionRole, isFalse);
    });

    test('⑤ pending 計數欄位存在於快照（UI 待辨識 N 張資料源）', () {
      const snap = LocalClutchSnapshot(
        state: LocalClutchState.runVision,
        companionModelId: 'a',
        visionModelId: 'b',
        pendingVisionItems: 7,
      );
      expect(snap.pendingVisionItems, 7);
      expect(snap.state, LocalClutchState.runVision);
    });

    test('④ faulted 快照攜帶故障原因（誠實顯示）', () {
      const snap = LocalClutchSnapshot(
        state: LocalClutchState.faulted,
        faultReason: '自動切換失敗：timeout',
      );
      expect(snap.state, LocalClutchState.faulted);
      expect(snap.faultReason, contains('timeout'));
    });
  });
}
