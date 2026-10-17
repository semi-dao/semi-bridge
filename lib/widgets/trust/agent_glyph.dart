// agent_glyph.dart
// [刀 2 2026-09-08 Blue 概念令] Agent 程序化指紋縮圖——獨一無二的臉。
//
// 「小葵跟小喬如果都是一個圓圈寫『小』那就重複了」——所以臉的主體是
// 數學圖案（identicon），不是文字。文字只是輔助。
//
// 五層：底色(200) × 外框(4) × 圖案(2^32) × 光點(~200) ≈ 10^14 組合空間。
// 確定性：純函式——同 ID 永遠同一張臉（跨裝置跨時間）。
// 設計稿：docs/specs/2026-09-08-agent-glyph.md

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Agent 指紋種子——從 ID+名字算出 5 個獨立偽隨機通道
class AgentGlyphSeed {
  final int h1, h2, h3, h4; // 各層獨立 hash 通道
  final String name;

  const AgentGlyphSeed(this.h1, this.h2, this.h3, this.h4, this.name);

  /// 同 ID+name 永遠同 seed（FNV-1a 變體，4 通道不同初始值）
  factory AgentGlyphSeed.of(String id, String name) {
    int fnv(int init, String s) {
      var h = init;
      for (final c in s.codeUnits) {
        h = (h ^ c) * 0x01000193 & 0x7fffffff;
      }
      return h;
    }

    final base = '$id::$name';
    return AgentGlyphSeed(
      fnv(0x811c9dc5, base),
      fnv(0x0d192a77, base),
      fnv(0x27d4eb2f, base),
      fnv(0x165667b1, base),
      name,
    );
  }

  /// ① 底色——HSL 色輪（避開過暗 S<30%、過亮 L>75%、過髒）
  Color get bg {
    // [指紋定律 2026-10-16 Blue 令] 原生 Agent 底色鎖品牌紫
    // （accentPurple 0xFF533AFD——大腦/向量專用紫）。圖案仍由 seed
    // 決定（唯一性不變），色相在紫域 250-280° 內微調，飽和度亮度
    // 對齊品牌紫的 HSL（249°, 98%, 60%），保證一眼認出「這是原生 Agent」
    if (isNative) {
      const brandPurple = Color(0xFF533AFD);
      final bp = HSLColor.fromColor(brandPurple);
      final hue = (250.0 + (h1 % 31).toDouble()).clamp(250.0, 280.0); // 250-280° 紫域
      // 亮度在品牌紫 ±4% 內微調（單位是 0-1）
      final light = (bp.lightness - 0.04 + ((h1 >> 12) % 9) / 100)
          .clamp(0.30, 0.62);
      return HSLColor.fromAHSL(1, hue, bp.saturation, light).toColor();
    }
    final hue = (h1 % 360).toDouble();
    final sat = 45.0 + (h1 >> 9) % 35; // 45-80%
    final light = 38.0 + (h1 >> 14) % 22; // 38-60%
    return HSLColor.fromAHSL(1, hue, sat / 100, light / 100).toColor();
  }

  /// [指紋定律] native-agent 系列（原生 Agent 身份）——品牌紫指紋
  bool get isNative =>
      name == '原生 Agent' || name.startsWith('native');

  /// ② 外框形狀
  AgentGlyphFrame get frame => AgentGlyphFrame.values[h2 % AgentGlyphFrame.values.length];

  /// ③ 圖案 bits（32 bits = 8×4 左右鏡像，identicon 本體）
  int get patternBits => h3;

  /// ④ 光點數（0-3）與位置
  int get sparkCount => (h4 >> 28) % 4;
  Offset sparkPos(int i) => Offset(
        ((h4 >> (i * 8)) & 0xff) / 255,
        ((h4 >> (i * 8 + 4)) & 0xff) / 255,
      );

  /// ⑤ 首字（顯示用——支援中文/emoji 的完整 code point）
  String get initial {
    final runes = name.runes.toList();
    if (runes.isEmpty) return '?';
    return String.fromCharCode(runes.first);
  }
}

enum AgentGlyphFrame { circle, squircle, hex, petal }

/// AgentGlyph 縮圖 widget——身份卡大圖與對話列表小圖同源。
class AgentGlyph extends StatelessWidget {
  final String companionId;
  final String name;
  final double size;
  final bool showInitial; // 大圖顯示首字輔助；小圖（<24px）省略

  const AgentGlyph({
    super.key,
    required this.companionId,
    required this.name,
    this.size = 40,
    this.showInitial = true,
  });

  @override
  Widget build(BuildContext context) {
    final seed = AgentGlyphSeed.of(companionId, name);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AgentGlyphPainter(seed, showInitial && size >= 24),
      ),
    );
  }
}

class _AgentGlyphPainter extends CustomPainter {
  final AgentGlyphSeed seed;
  final bool showInitial;
  _AgentGlyphPainter(this.seed, this.showInitial);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // ① 底色（圓形裁切內）
    final bgPaint = Paint()..color = seed.bg;
    final Path clip = _framePath(seed.frame, rect);
    canvas.clipPath(clip);
    canvas.drawRect(rect, bgPaint);

    // ③ 圖案本體——8×4 左右鏡像 identicon（淺色，與底色對比）
    final pattern = Paint()
      ..color = Colors.white.withValues(alpha: 0.85);
    final anti = Paint()
      ..color = Colors.black.withValues(alpha: 0.25);
    final cell = s / 8;
    final bits = seed.patternBits;
    for (var col = 0; col < 4; col++) {
      for (var row = 0; row < 8; row++) {
        final bitIndex = col * 8 + row;
        if ((bits >> bitIndex) & 1 == 1) {
          // 左半 + 鏡像右半
          for (final c in [col, 7 - col]) {
            canvas.drawRect(
              Rect.fromLTWH(c * cell, row * cell, cell + 0.5, cell + 0.5),
              (row + c) % 2 == 0 ? pattern : anti,
            );
          }
        }
      }
    }

    // ④ 光點——accent 亮點（畫在圖案上，像星星）
    final spark = Paint()
      ..color = Colors.white.withValues(alpha: 0.9);
    for (var i = 0; i < seed.sparkCount; i++) {
      final p = seed.sparkPos(i);
      canvas.drawCircle(
        Offset(p.dx * size.width, p.dy * size.height),
        s * 0.035,
        spark,
      );
    }

    // ⑤ 首字（右下角小字——輔助辨識非主體）
    if (showInitial) {
      final tp = TextPainter(
        text: TextSpan(
          text: seed.initial,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: s * 0.22,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          size.width - tp.width - s * 0.08,
          size.height - tp.height - s * 0.08,
        ),
      );
    }
  }

  Path _framePath(AgentGlyphFrame f, Rect r) {
    switch (f) {
      case AgentGlyphFrame.circle:
        return Path()..addOval(r);
      case AgentGlyphFrame.squircle:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(r.width / 3.2)));
      case AgentGlyphFrame.hex:
        final p = Path();
        final cx = r.center.dx, cy = r.center.dy;
        final rad = r.width / 2;
        for (var i = 0; i < 6; i++) {
          final a = math.pi / 3 * i - math.pi / 6;
          final x = cx + rad * math.cos(a);
          final y = cy + rad * math.sin(a);
          i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
        }
        p.close();
        return p;
      case AgentGlyphFrame.petal:
        final p = Path();
        final cx = r.center.dx, cy = r.center.dy;
        final rad = r.width / 2;
        // 四花瓣（貝茲）
        p.moveTo(cx, cy - rad);
        p.quadraticBezierTo(cx + rad, cy - rad, cx + rad * 0.85, cy);
        p.quadraticBezierTo(cx + rad, cy + rad, cx, cy + rad);
        p.quadraticBezierTo(cx - rad, cy + rad, cx - rad * 0.85, cy);
        p.quadraticBezierTo(cx - rad, cy - rad, cx, cy - rad);
        p.close();
        return p;
    }
  }

  @override
  bool shouldRepaint(covariant _AgentGlyphPainter old) =>
      old.seed.h3 != seed.h3 || old.showInitial != showInitial;
}
