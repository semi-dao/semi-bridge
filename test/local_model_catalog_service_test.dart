import 'package:bridge_app/services/local_model_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = LocalModelCatalogService();

  // [2026-09-22] catalog 已改版：3 個模型
  // （Qwen3.5-4B / Gemma 4 E4B / Llama 3.2 3B），size class 4B/4B/3B。
  // 舊測試斷言 0.5B/3B/7B/14B 四級距已過期。

  test('local model plan waits for desktop hardware profile', () {
    final plan = service.buildPlan();

    expect(plan.hardware.desktopConnected, isFalse);
    expect(plan.summary, contains('尚未連接 Bridge Desktop'));
    expect(plan.recommendations, hasLength(4)); // [2026-10-13] 12B 登基後 catalog=4（Qwen3.5-4B/Gemma-4-E4B/Llama-3.2-3B/Gemma4-12B）
    expect(
      plan.recommendations.map((item) => item.model.sizeClass),
      containsAll(['4B', '3B']),
    );
    expect(
      plan.recommendations.every((item) => item.fit == LocalModelFit.unknown),
      isTrue,
    );
  });

  test('local model plan evaluates hardware fit by RAM', () {
    final plan = service.buildPlan(
      hardware: const LocalHardwareProfile(
        source: 'desktop',
        ramGb: 32,
        vramGb: 8,
        chipLabel: 'Apple Silicon / 32GB',
        desktopConnected: true,
      ),
    );

    // 32GB RAM：全部模型都 fits（minRamGb 最高 8）
    for (final item in plan.recommendations) {
      expect(
        item.fit,
        anyOf(LocalModelFit.excellent, LocalModelFit.good),
        reason: '${item.model.name}（minRam ${item.model.minRamGb}）在 32GB 應可執行',
      );
    }
    expect(plan.recommendations, isNotEmpty);
  });

  test('local model plan blocks models below minimum RAM', () {
    final plan = service.buildPlan(
      hardware: const LocalHardwareProfile(
        source: 'desktop',
        ramGb: 5,
        vramGb: 0,
        chipLabel: '入門筆電 / 5GB',
        desktopConnected: true,
      ),
    );

    // 5GB RAM：全部模型都低於 minRamGb（最低 6）
    for (final item in plan.recommendations) {
      expect(
        item.fit,
        LocalModelFit.unsupported,
        reason: '${item.model.name}（minRam ${item.model.minRamGb}）在 5GB 不應執行',
      );
    }
  });
}
