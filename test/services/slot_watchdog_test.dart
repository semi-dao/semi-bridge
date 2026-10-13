// SlotResourceWatchdog 回歸測試——偽造暴食插槽被自動斷電（C4 驗收標準）
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/slots/slot_resource_watchdog.dart';
import 'package:bridge_app/services/slots/slot_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SlotRegistry registry;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('slot_wd_test_');
    registry = SlotRegistry.test(tmp);
    await registry.load();
    SlotResourceWatchdog.instance.registryOverride = registry;
    SlotResourceWatchdog.instance.debugReset();
  });

  tearDown(() async {
    SlotResourceWatchdog.instance.registryOverride = null;
    await tmp.delete(recursive: true);
  });

  test('導航風暴：短時間狂跳 → 自動斷電 + 原因記錄', () async {
    final r = await registry.addFromRepo(
        'https://github.com/example/storm-tool');
    await registry.enableWithPermissions(r.id, []);
    final w = SlotResourceWatchdog.instance;

    // 模擬 29 次被擋導航（門檻 30）——未觸發
    for (var i = 0; i < 29; i++) {
      w.reportBlockedNavigation(r.id);
    }
    expect(w.tripped.containsKey(r.id), isFalse, reason: '29 次不觸發');

    // 第 30 次 → 斷電（flush 等待斷電動作落地）
    w.reportBlockedNavigation(r.id);
    await w.flush();
    expect(w.tripped.containsKey(r.id), isTrue, reason: '30 次風暴必須觸發');
    expect(w.tripped[r.id], contains('失控'));

    // registry 已同步停用 + 原因入檔
    final rec = registry.getById(r.id);
    expect(rec?.status, SlotStatus.disabled);
    expect(rec?.watchdogReason, contains('失控'));
  });

  test('JS 錯誤風暴：單 tick > 50 錯誤 → 斷電', () async {
    final r = await registry.addFromRepo(
        'https://github.com/example/error-loop');
    await registry.enableWithPermissions(r.id, []);
    final w = SlotResourceWatchdog.instance;

    // 50 個不觸發
    expect(w.sampleBehavior(r.id, jsErrorsSinceLast: 50), isFalse);
    // 51 個觸發
    expect(w.sampleBehavior(r.id, jsErrorsSinceLast: 51), isTrue);
    await w.flush();
    await w.flush();
    expect(w.tripped[r.id], contains('錯誤風暴'));
    expect(registry.getById(r.id)?.status, SlotStatus.disabled);
    expect(registry.getById(r.id)?.watchdogReason, contains('錯誤風暴'));
  });

  test('正常使用不誤殺：少量導航攔截 + 少量 JS 錯誤 → 不斷電', () async {
    final r = await registry.addFromRepo(
        'https://github.com/example/normal-tool');
    await registry.enableWithPermissions(r.id, []);
    final w = SlotResourceWatchdog.instance;

    for (var i = 0; i < 10; i++) {
      w.reportBlockedNavigation(r.id);
    }
    expect(w.sampleBehavior(r.id, jsErrorsSinceLast: 5), isFalse);
    expect(w.tripped.containsKey(r.id), isFalse);
    expect(registry.getById(r.id)?.status, SlotStatus.running);
  });

  test('clearTrip：使用者手動重啟後可再運行', () async {
    final r = await registry.addFromRepo(
        'https://github.com/example/recover');
    await registry.enableWithPermissions(r.id, []);
    final w = SlotResourceWatchdog.instance;
    w.reportBlockedNavigation(r.id); // ×1
    w.clearTrip(r.id);
    // 清旗標後計數也歸零，重新累積
    for (var i = 0; i < 29; i++) {
      w.reportBlockedNavigation(r.id);
    }
    expect(w.tripped.containsKey(r.id), isFalse, reason: '清旗標後從零計');
  });
}
