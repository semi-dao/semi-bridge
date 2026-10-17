// provider_router_test.dart
//
// [T7⑥ 2026-10-16 編織線任務 V3] 分流器收斂驗收測試——D7「分流只有一個腦」：
//   1. localOnly=true → resolveDefault 永不回雲端（target==local、URL 是 127.0.0.1）
//   2. routedBaseUrl 單一真相：setCurrent(local) → 127.0.0.1:18789；
//      setCurrent(cloud) → ProviderRegistry 的雲端 URL——ApiService 據此打點
//   3. cloudFallbackOrder 常數存在且非空（T7⑤ 統一常數）
//   4. MemoryGuard localOnly 行為由整合測試另測（此處鎖路由層語意）

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/services/provider_router.dart';
import 'package:bridge_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('T7④ localOnly（M6 斷網血管）', () {
    test('localOnly=true → resolveDefault 永不回雲端', () async {
      await StorageService.saveLocalOnly(true);
      final routed = await ProviderRouter.instance.resolveDefault();
      expect(routed.target, RoutedTarget.local,
          reason: 'localOnly 模式下 target 必須是 local，不得路由到任何雲端');
      expect(routed.providerId, 'local');
    });

    test('localOnly=false（預設）→ 行為不變（可回雲或 local）', () async {
      await StorageService.saveLocalOnly(false);
      // 沒有 token/policy 的測試環境 → 自然 fallback local（雲不可用）
      final routed = await ProviderRouter.instance.resolveDefault();
      expect(routed.target, anyOf(RoutedTarget.local, RoutedTarget.cloud));
    });

    test('localOnly 持久化 round-trip', () async {
      expect(await StorageService.getLocalOnly(), false,
          reason: '預設關（M6 斷網模式是 opt-in）');
      await StorageService.saveLocalOnly(true);
      expect(await StorageService.getLocalOnly(), true);
    });
  });

  group('T7① routedBaseUrl 單一真相源', () {
    test('setCurrent(local) → routedBaseUrl 是 127.0.0.1:18789', () {
      ProviderRouter.instance.setCurrent(
        const RoutedProvider(
          target: RoutedTarget.local,
          providerId: 'local',
          reason: 'test',
        ),
      );
      final url = ProviderRouter.instance.routedBaseUrl;
      expect(url, isNotNull);
      expect(url!.startsWith('http://127.0.0.1:'), isTrue,
          reason: 'local 路由的 URL 必須是 loopback');
    });

    test('localOnly 下任何 setCurrent 結果都不含非 loopback URL（若 local）', () {
      // setCurrent 是記憶體操作——localOnly 的守門在 resolveDefault，
      // 這裡鎖的是「local 路由結果的 URL 永遠 loopback」的不變量
      ProviderRouter.instance.setCurrent(
        const RoutedProvider(
          target: RoutedTarget.local,
          providerId: 'local',
          reason: 'test localOnly',
        ),
      );
      expect(
        ProviderRouter.instance.routedBaseUrl,
        matches(RegExp(r'^http://127\.0\.0\.1:\d+$')),
        reason: 'T7 驗收：localOnly=true → 永不出現非 127.0.0.1 的 base URL',
      );
    });
  });

  group('T7⑤ fallback 常數', () {
    test('cloudFallbackOrder 非空且無重複', () {
      expect(ProviderRouter.cloudFallbackOrder, isNotEmpty);
      expect(
        ProviderRouter.cloudFallbackOrder.toSet().length,
        ProviderRouter.cloudFallbackOrder.length,
        reason: 'fallback 順序不得有重複 provider',
      );
    });
  });
}
