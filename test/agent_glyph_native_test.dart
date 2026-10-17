// agent_glyph_native_test.dart
// [指紋定律 2026-10-16 Blue 令] 原生 Agent 指紋＝品牌紫——鎖死色相域
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/widgets/trust/agent_glyph.dart';

void main() {
  test('native-agent 指紋底色落在品牌紫域（250-280°）', () {
    final seed = AgentGlyphSeed.of('native-agent', '原生 Agent');
    expect(seed.isNative, isTrue);
    final hsl = HSLColor.fromColor(seed.bg);
    expect(hsl.hue, inInclusiveRange(249, 282),
        reason: '原生 Agent 指紋必須是品牌紫（accentPurple 0xFF533AFD 家族）');
    // 飽和度對齊品牌紫（98%）
    expect(hsl.saturation, greaterThan(0.7));
  });

  test('同一 native-agent 永遠同指紋（seed 穩定）', () {
    final a = AgentGlyphSeed.of('native-agent', '原生 Agent');
    final b = AgentGlyphSeed.of('native-agent', '原生 Agent');
    expect(a.bg, equals(b.bg));
    expect(a.patternBits, equals(b.patternBits));
  });

  test('一般夥伴指紋不受影響（非紫域鎖定）', () {
    final seed = AgentGlyphSeed.of('cmp_test', '小測試');
    expect(seed.isNative, isFalse);
    // 一般夥伴照舊全色輪——只要不是 isNative 分支即可
    expect(seed.bg, isNotNull);
  });
}
