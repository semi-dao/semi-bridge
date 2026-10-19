// m2_persona_inject_test.dart
// [T4② 2026-10-16 編織線] M2 語氣層注入鏈驗證——
// 鎖死「persona 資產存在 + build 的 companionPersona 區段真的進 prompt」
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:bridge_app/services/agent_loop/agent_loop_prompt_builder.dart';
import 'package:bridge_app/services/agent_loop/agent_tool_registry.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // [開源版] assets/persona/ 為私有語氣層資產——開源 repo 不附。
  // 資產不存在時整檔 skip（本尊 bridge_app 有資產，照常驗證）。
  var personaAssetsPresent = true;
  try {
    await rootBundle.loadString('assets/persona/persona_e4b.txt');
  } catch (_) {
    personaAssetsPresent = false;
  }
  if (!personaAssetsPresent) {
    // ignore: avoid_print
    print('SKIP: 私有 persona 資產不存在（開源版預期行為）');
    return;
  }

  test('assets/persona 兩版資產存在且可載入', () async {
    final cloud = await rootBundle.loadString('assets/persona/persona_cloud.txt');
    expect(cloud.length, greaterThan(30000), reason: 'cloud 版完整語感');
    expect(cloud.contains('小葵'), isTrue, reason: '語氣層必須定義小葵身份');

    final e4b = await rootBundle.loadString('assets/persona/persona_e4b.txt');
    expect(e4b.length, greaterThan(4000), reason: 'e4b 精簡版（bytes 11.8K ≈ 5.6K 字元）');
    expect(e4b.length, lessThan(12000), reason: 'e4b 版要塞得進 32K ctx');
    expect(e4b.contains('小葵'), isTrue);
  });

  test('local prompt 掛上 M2 語氣層（companionPersona 區段進 prompt）', () {
    final registry = AgentToolRegistry();
    final prompt = AgentLoopPromptBuilder.build(
      companionPersona: '你是小葵（測試注入）——向日葵的葵',
      toolRegistry: registry,
      isLocalProvider: true,
    );
    expect(prompt, contains('你的人格（覆蓋前述一切身份描述）'),
        reason: '人格區段標題必須在');
    expect(prompt, contains('你是小葵（測試注入）'), reason: '語氣層內容必須掛上');
  });
}
