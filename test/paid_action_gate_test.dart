// paid_action_gate_test.dart
// [小葵 2026-08-21] $33 根治驗證——閘門邏輯實測（mock prefs，零成本）
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/services/paid_action_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('上限內放行並計數', () async {
    SharedPreferences.setMockInitialValues({});
    final v = await PaidActionGate.instance.checkAndReserve(PaidActionKind.image);
    expect(v.allowed, true);
    final v2 = await PaidActionGate.instance.checkAndReserve(PaidActionKind.image);
    expect(v2.allowed, true);
  });

  test('拆牆後仍放行且計數照記（帳要看，牆不擋）[Blue 令 2026-09-24]', () async {
    SharedPreferences.setMockInitialValues({});
    // 上限牆已拆（commit 2a8e2216）：防失控由智慧閘門接管，日上限只剩摩擦。
    // 本測試鎖死拆牆後的守門行為：放行不擋＋計數誠實。
    for (var i = 0; i < 30; i++) {
      final v = await PaidActionGate.instance.checkAndReserve(PaidActionKind.image);
      expect(v.allowed, true, reason: '第 ${i + 1} 發應放行（無日上限）');
    }
    final v31 = await PaidActionGate.instance.checkAndReserve(PaidActionKind.image);
    expect(v31.allowed, true, reason: '第 31 發也放行——牆已拆，防失控在智慧閘門');
    expect(v31.reason, contains('31'), reason: '計數照記（帳要看）');
    expect(v31.reason, contains('無上限'), reason: '理由誠實標明無上限');
  });

  test('跨日自動重置', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('paid_gate.date', '2000-01-01');
    await prefs.setInt('paid_gate.count_image', 999);
    final v = await PaidActionGate.instance.checkAndReserve(PaidActionKind.image);
    expect(v.allowed, true); // 舊日計數歸零
  });

  test('拆牆後 video/music 各自獨立計數（互不影響放行）', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('paid_gate.cap_video', 0);
    await prefs.setString('paid_gate.date',
        DateTime.now().toIso8601String().substring(0, 10));
    final video = await PaidActionGate.instance.checkAndReserve(PaidActionKind.video);
    final music = await PaidActionGate.instance.checkAndReserve(PaidActionKind.music);
    expect(video.allowed, true); // 牆已拆：cap=0 不再擋，僅 budgetEye 顯示
    expect(music.allowed, true); // music 不受 video 計數影響
  });
}
