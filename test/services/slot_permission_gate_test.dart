// SlotPermissionGate 回歸測試——權限執行閘（C4）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/slots/slot_permission_gate.dart';
import 'package:bridge_app/services/slots/slot_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SlotRegistry registry;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('slot_perm_test_');
    registry = SlotRegistry.test(tmp);
    await registry.load();
    SlotPermissionGate.instance.debugReset();
    SlotPermissionGate.instance.registryOverride = registry;
  });

  tearDown(() async {
    SlotPermissionGate.instance.registryOverride = null;
    await tmp.delete(recursive: true);
  });

  test('🟢 純本地插槽（無 network 權限）：對外導航被攔截', () async {
    final r = await registry.addFromRepo('https://github.com/example/local-tool');
    await registry.enableWithPermissions(r.id, []); // 綠燈

    final allowed = await SlotPermissionGate.instance.checkNavigation(
      slotId: r.id,
      url: 'https://evil.example.com/steal',
    );
    expect(allowed, isFalse, reason: '零權限插槽不得對外導航');
  });

  test('🟡 網路唯讀插槽：對外導航放行（記帳）', () async {
    final r = await registry.addFromRepo('https://github.com/example/net-tool');
    await registry.enableWithPermissions(r.id, ['network']); // 黃燈

    final allowed = await SlotPermissionGate.instance.checkNavigation(
      slotId: r.id,
      url: 'https://api.example.com/data',
    );
    expect(allowed, isTrue, reason: '有 network 權限可對外');
  });

  test('插槽內 file:// 導航一律放行（沙箱內自由走動）', () async {
    final r = await registry.addFromRepo('https://github.com/example/local-tool');
    await registry.enableWithPermissions(r.id, []);

    final allowed = await SlotPermissionGate.instance.checkNavigation(
      slotId: r.id,
      url: 'file:///tmp/anything/index.html',
    );
    expect(allowed, isTrue, reason: 'file:// 不是對外請求');
  });

  test('不存在的插槽 → 不放行（fail-closed）', () async {
    final allowed = await SlotPermissionGate.instance.checkNavigation(
      slotId: 'ghost-id',
      url: 'https://api.example.com/data',
    );
    expect(allowed, isFalse);
  });
}
