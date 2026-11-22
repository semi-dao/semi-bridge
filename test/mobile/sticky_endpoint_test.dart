// [2026-11-20 sticky 端點直攻] sticky 排序測試——鎖兩條行為：
// 1. last-good 在候選集內 → 排第一位直攻（解鎖冷啟動不再先撞死 LAN 門牌）
// 2. last-good 不在候選集／尚未記錄 → 原順序不動（lan→v6→tailscale 保留 fallback）
// 加計數失效：連敗 2 次 → 清除（WiFi 環境變換後不會永遠直攻死門牌）。
import 'package:bridge_app/services/mobile/sticky_endpoint_memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StickyEndpointMemory.resetCacheForTest();
  });

  group('orderByLastGood（候選排序純函數）', () {
    test('last-good 在候選集內 → 排第一位直攻', () {
      // 典型場景：allHosts = [死LAN, v6, tailscale]，上次成功的是 v6
      final ordered = StickyEndpointMemory.orderByLastGood(
        ['192.168.1.5', '2001:db8::1', '100.64.0.2'],
        '2001:db8::1',
      );
      expect(ordered.first, '2001:db8::1',
          reason: '上次成功端點必須排第一，不再先吃 LAN 8s 逾時');
      // 其餘相對順序保留（fallback 链不動）
      expect(ordered.sublist(1), ['192.168.1.5', '100.64.0.2']);
    });

    test('last-good = 第一位（LAN 本来就通）→ 順序完全不動', () {
      final ordered = StickyEndpointMemory.orderByLastGood(
        ['192.168.1.5', '2001:db8::1'],
        '192.168.1.5',
      );
      expect(ordered, ['192.168.1.5', '2001:db8::1']);
    });

    test('last-good 不在候選集（換了 WiFi）→ 原順序不動退回預設', () {
      final ordered = StickyEndpointMemory.orderByLastGood(
        ['192.168.50.1', '2001:db8::9'],
        '192.168.1.5', // 舊家網殘影，新候選集沒有它
      );
      expect(ordered, ['192.168.50.1', '2001:db8::9']);
    });

    test('last-good null（首配對/已失效）→ 原順序不動', () {
      final ordered =
          StickyEndpointMemory.orderByLastGood(['a', 'b', 'c'], null);
      expect(ordered, ['a', 'b', 'c']);
    });
  });

  group('失敗計數失效（防永遠直攻死門牌）', () {
    test('recordSuccess → loadLastGoodHost 讀得到（prefs + 鏡射）', () async {
      await StickyEndpointMemory.recordSuccess('2001:db8::1');
      expect(await StickyEndpointMemory.loadLastGoodHost(), '2001:db8::1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(StickyEndpointMemory.prefsKey), '2001:db8::1');
    });

    test('連敗 2 次 → 失效清除，之後退回預設輪替', () async {
      await StickyEndpointMemory.recordSuccess('192.168.1.5');
      expect(await StickyEndpointMemory.recordFailure('192.168.1.5'), isFalse,
          reason: '第 1 敗還給一次機會');
      expect(await StickyEndpointMemory.loadLastGoodHost(), '192.168.1.5');
      expect(await StickyEndpointMemory.recordFailure('192.168.1.5'), isTrue,
          reason: '第 2 敗達封頂 → 宣告失效');
      expect(await StickyEndpointMemory.loadLastGoodHost(), isNull,
          reason: '失效後不得再直攻死門牌');
    });

    test('成功清零計數（中途連上過就不算連敗）', () async {
      await StickyEndpointMemory.recordSuccess('h');
      await StickyEndpointMemory.recordFailure('h'); // 1 敗
      await StickyEndpointMemory.recordSuccess('h'); // 連上了→清零
      expect(await StickyEndpointMemory.recordFailure('h'), isFalse,
          reason: '計數已被成功清零，重新從 1 敗算');
      expect(await StickyEndpointMemory.recordFailure('h'), isTrue,
          reason: '再兩敗才失效');
    });

    test('失敗的 host ≠ sticky（輪替路的失敗）→ 不誤傷 sticky 帳', () async {
      await StickyEndpointMemory.recordSuccess('2001:db8::1');
      expect(await StickyEndpointMemory.recordFailure('192.168.1.5'), isFalse);
      expect(await StickyEndpointMemory.loadLastGoodHost(), '2001:db8::1',
          reason: '輪替打到 LAN 失敗不該扣 sticky(v6) 的信用');
    });
  });
}
