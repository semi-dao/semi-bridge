// [教練 Agent 2026-08-08] Stream Confluence Overlay — Layer C 沉浸層
//
// 水流匯入動畫：多條光帶從畫面邊緣匯聚到中心，
// 凝聚成一個發光點，留下成果的標題，然後自然退場。
//
// 設計語言對應：
// - Active Theory「可沉浸」：事件發生時整個畫面成為有情緒的場域
// - GPU ≤ 5%：只使用 8 條光帶 + 1 個發光點，不使用大規模粒子
// - 有明確進場和退場：2.5 秒後自動消失
//
// 技術：CustomPainter + AnimationController，不引入第三方套件

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../services/brain_container/transurfing_event.dart';
import '../../../theme/bridge_design_system.dart';

/// 水流匯入沉浸層 overlay
///
/// 監聽 TransurfingEventBroadcaster，當收到 streamConfluence 事件時
/// 自動播放動畫，結束後自動退場。
class StreamConfluenceOverlay extends StatefulWidget {
  const StreamConfluenceOverlay({super.key});

  @override
  State<StreamConfluenceOverlay> createState() =>
      _StreamConfluenceOverlayState();
}

class _StreamConfluenceOverlayState extends State<StreamConfluenceOverlay>
    with TickerProviderStateMixin {
  AnimationController? _controller;
  String _titleText = '';
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    TransurfingEventBroadcaster.instance.addListener(_onEvent);
  }

  @override
  void dispose() {
    TransurfingEventBroadcaster.instance.removeListener(_onEvent);
    _controller?.dispose();
    super.dispose();
  }

  void _onEvent() {
    final event = TransurfingEventBroadcaster.instance.lastEvent;
    if (event == null) return;
    if (event.type != TransurfingEventType.streamConfluence &&
        event.type != TransurfingEventType.streamResumed &&
        event.type != TransurfingEventType.doorOpened) {
      return;
    }

    // 根據事件類型設定標題
    _titleText = switch (event.type) {
      TransurfingEventType.streamConfluence => '✓ ${event.title}',
      TransurfingEventType.streamResumed => '🌊 ${event.title}',
      TransurfingEventType.doorOpened => '🚪 ${event.title}',
      _ => event.title,
    };

    _controller?.dispose();
    _controller = AnimationController(
      duration: Duration(milliseconds: event.durationMs),
      vsync: this,
    );

    setState(() => _visible = true);

    _controller!.forward().then((_) {
      if (mounted) {
        setState(() => _visible = false);
        TransurfingEventBroadcaster.instance.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _controller == null) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller!,
          builder: (context, child) {
            return CustomPaint(
              painter: _ConfluencePainter(
                progress: _controller!.value,
                title: _titleText,
                colors: BridgeDSColors.of(context),
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

/// 水流匯入的視覺效果 painter
///
/// 動畫分三段：
/// 1. 進場（0.0 - 0.3）：8 條光帶從邊緣向中心延伸
/// 2. 凝聚（0.3 - 0.6）：光帶匯聚成發光點 + 標題淡入
/// 3. 退場（0.6 - 1.0）：光點擴散淡出，標題上浮消失
class _ConfluencePainter extends CustomPainter {
  final double progress;
  final String title;
  final BridgeDSColors colors;

  _ConfluencePainter({
    required this.progress,
    required this.title,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = Offset(size.width, size.height).distance / 2;

    // 背景暗化（只在進場和凝聚階段）
    final bgOpacity = progress < 0.6
        ? (progress < 0.3 ? progress / 0.3 : 1.0) * 0.3
        : (1.0 - (progress - 0.6) / 0.4) * 0.3;
    if (bgOpacity > 0.01) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = colors.canvas.withValues(alpha: bgOpacity),
      );
    }

    // 8 條光帶
    const bandCount = 8;
    for (var i = 0; i < bandCount; i++) {
      final angle = (i / bandCount) * pi * 2;
      final startDistance = maxRadius * 1.2;

      // 光帶長度根據進場退場變化
      double bandExtension;
      if (progress < 0.3) {
        bandExtension = (progress / 0.3); // 0→1
      } else if (progress < 0.6) {
        bandExtension = 1.0; // 完全展開
      } else {
        bandExtension = 1.0 - ((progress - 0.6) / 0.4); // 1→0
      }

      if (bandExtension <= 0.01) continue;

      final outerPoint = Offset(
        center.dx + cos(angle) * startDistance,
        center.dy + sin(angle) * startDistance,
      );
      final innerPoint = Offset(
        center.dx + cos(angle) * startDistance * (1.0 - bandExtension * 0.9),
        center.dy + sin(angle) * startDistance * (1.0 - bandExtension * 0.9),
      );

      // 光帶顏色：交錯藍綠
      final bandColor = i % 2 == 0
          ? colors.accentBlue.withValues(alpha: 0.4 * bandExtension)
          : colors.accentGreen.withValues(alpha: 0.35 * bandExtension);

      canvas.drawLine(
        outerPoint,
        innerPoint,
        Paint()
          ..color = bandColor
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
    }

    // 中心發光點
    double glowRadius;
    double glowOpacity;
    if (progress < 0.3) {
      glowRadius = 4.0;
      glowOpacity = progress / 0.3 * 0.5;
    } else if (progress < 0.6) {
      glowRadius = 4.0 + (progress - 0.3) / 0.3 * 20.0;
      glowOpacity = 0.5 + (progress - 0.3) / 0.3 * 0.3;
    } else {
      glowRadius = 24.0 + (progress - 0.6) / 0.4 * 40.0;
      glowOpacity = 0.8 - (progress - 0.6) / 0.4 * 0.8;
    }

    if (glowOpacity > 0.01) {
      // 外層光暈
      canvas.drawCircle(
        center,
        glowRadius * 2.5,
        Paint()..color = colors.accentBlue.withValues(alpha: glowOpacity * 0.15),
      );
      // 核心光點
      canvas.drawCircle(
        center,
        glowRadius,
        Paint()..color = colors.accentGreen.withValues(alpha: glowOpacity * 0.6),
      );
    }

    // 標題文字（凝聚階段淡入，退場階段上浮）
    if (progress > 0.35) {
      double textOpacity;
      double textYOffset;
      if (progress < 0.6) {
        textOpacity = (progress - 0.35) / 0.25;
        textYOffset = 0;
      } else {
        textOpacity = 1.0 - (progress - 0.6) / 0.4;
        textYOffset = -(progress - 0.6) / 0.4 * 30;
      }

      if (textOpacity > 0.01 && title.isNotEmpty) {
        final textSpan = TextSpan(
          text: title,
          style: TextStyle(
            color: colors.textPrimary.withValues(alpha: textOpacity),
            fontSize: 14,
            fontFamily: 'Geist Mono',
            fontWeight: FontWeight.w400,
            letterSpacing: 0.3,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        textPainter.layout(maxWidth: size.width * 0.6);
        textPainter.paint(
          canvas,
          Offset(
            center.dx - textPainter.width / 2,
            center.dy + glowRadius + 16 + textYOffset,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConfluencePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.title != title;
  }
}
