// Bridge Motion System — 動態體感層
// 把 BridgeDS motion tokens 變成可重用的 transition widgets
// 設計來源：xAI 氛圍 × Raycast 色彩 × Stripe 粒子 × Figma 動態 × Miro 無限畫布
//
// 原則：
// - 所有動畫使用 BridgeDS 定義的 curve + duration，不散落 magic number
// - 頁面轉場有方向感（Miro 無限畫布式平移）
// - 元素入場有層次（staggered，不是全部同時出現）
// - 回饋即時且明確（按鈕亮燈、鎖定消失）
// - 動畫不阻塞使用者操作（forward 但不阻塞）

import 'dart:async';
import 'package:flutter/material.dart';
import 'bridge_design_system.dart';

/// ═══════════════════════════════════════════════════
/// Bridge Motion — 頁面轉場
/// ═══════════════════════════════════════════════════

/// Miro 式無限畫布轉場——頁面像在無限畫布上平移
/// 用於主要 tab 切換、歡迎→召喚→桌面之間的流程轉場
class BridgeCanvasTransition extends PageRouteBuilder {
  BridgeCanvasTransition({
    required Widget page,
    super.settings,
    Offset direction = const Offset(1.0, 0.0), // 預設從右側滑入
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: BridgeDS.durationCanvas,
          reverseTransitionDuration: BridgeDS.durationNormal,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // 主頁面：從方向偏移滑入 + fade
            final inOffset = Tween<Offset>(
              begin: direction,
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: BridgeDS.transitionCanvas,
            ));

            // 舊頁面：往反方向滑出 + fade
            final outOffset = Tween<Offset>(
              begin: Offset.zero,
              end: Offset(-direction.dx, -direction.dy),
            ).animate(CurvedAnimation(
              parent: secondaryAnimation,
              curve: BridgeDS.transitionCanvas,
            ));

            return SlideTransition(
              position: inOffset,
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: BridgeDS.transitionSlide,
                ),
                child: SlideTransition(
                  position: outOffset,
                  child: FadeTransition(
                    opacity: ReverseAnimation(CurvedAnimation(
                      parent: secondaryAnimation,
                      curve: BridgeDS.transitionSlide,
                    )),
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
}

/// 對話框滑入轉場——從底部滑入，用於對話/設定面板
class BridgeSlideUpTransition extends PageRouteBuilder {
  BridgeSlideUpTransition({
    required Widget page,
    super.settings,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: BridgeDS.durationSlow,
          reverseTransitionDuration: BridgeDS.durationNormal,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final offset = Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: BridgeDS.transitionSlide,
            ));
            return SlideTransition(
              position: offset,
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: BridgeDS.transitionSlide,
                ),
                child: child,
              ),
            );
          },
        );
}

/// ═══════════════════════════════════════════════════
/// Bridge Motion — 元件入場動畫
/// ═══════════════════════════════════════════════════

/// 從指定方向滑入 + fade
class BridgeSlideIn extends StatefulWidget {
  final Widget child;
  final Offset direction; // 滑入方向，預設從下方
  final Duration delay;
  final Duration duration;

  const BridgeSlideIn({
    super.key,
    required this.child,
    this.direction = const Offset(0, 0.15),
    this.delay = Duration.zero,
    this.duration = BridgeDS.durationSlow,
  });

  @override
  State<BridgeSlideIn> createState() => _BridgeSlideInState();
}

class _BridgeSlideInState extends State<BridgeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: BridgeDS.transitionSlide,
    );
    _slide = Tween<Offset>(
      begin: widget.direction,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: BridgeDS.transitionCanvas,
    ));

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

/// 縮放浮現——用於卡片、面板出現
class BridgeScaleIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double beginScale;

  const BridgeScaleIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.beginScale = 0.92,
  });

  @override
  State<BridgeScaleIn> createState() => _BridgeScaleInState();
}

class _BridgeScaleInState extends State<BridgeScaleIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: BridgeDS.durationSlow,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: BridgeDS.transitionSlide,
    );
    _scale = Tween<double>(
      begin: widget.beginScale,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: BridgeDS.transitionMorph,
    ));

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════
/// Bridge Motion — Staggered Entrance（交錯入場）
/// ═══════════════════════════════════════════════════

/// 讓子元件依序入場，每個延遲 staggerDelay
class BridgeStaggeredEntrance extends StatefulWidget {
  final List<Widget> children;
  final Duration staggerDelay;
  final Duration itemDuration;
  final Offset slideDirection;

  const BridgeStaggeredEntrance({
    super.key,
    required this.children,
    this.staggerDelay = const Duration(milliseconds: 100),
    this.itemDuration = BridgeDS.durationSlow,
    this.slideDirection = const Offset(0, 0.15),
  });

  @override
  State<BridgeStaggeredEntrance> createState() =>
      _BridgeStaggeredEntranceState();
}

class _BridgeStaggeredEntranceState extends State<BridgeStaggeredEntrance> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < widget.children.length; i++)
          BridgeSlideIn(
            direction: widget.slideDirection,
            delay: widget.staggerDelay * i,
            duration: widget.itemDuration,
            child: widget.children[i],
          ),
      ],
    );
  }
}

/// ═══════════════════════════════════════════════════
/// Bridge Motion — 互動回饋元件
/// ═══════════════════════════════════════════════════

/// 亮燈按鈕——測試成功時發光，鎖定時消失變為「已鎖定」標籤
class BridgeGlowButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final BridgeGlowButtonState state;

  const BridgeGlowButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.state = BridgeGlowButtonState.idle,
  });

  @override
  State<BridgeGlowButton> createState() => _BridgeGlowButtonState();
}

enum BridgeGlowButtonState {
  idle,       // 一般狀態
  testing,    // 測試中（脈動）
  success,    // 成功（綠光）
  locked,     // 已鎖定（消失，顯示鎖定標籤）
}

class _BridgeGlowButtonState extends State<BridgeGlowButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _glowController;
  late final Animation<double> _pulse;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: BridgeDS.durationSlow,
    );
    _pulse = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _glow = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: BridgeDS.transitionSlide),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(BridgeGlowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    switch (widget.state) {
      case BridgeGlowButtonState.testing:
        _pulseController.repeat(reverse: true);
        _glowController.reverse();
        break;
      case BridgeGlowButtonState.success:
        _pulseController.stop();
        _glowController.forward();
        break;
      case BridgeGlowButtonState.locked:
        _pulseController.stop();
        _glowController.reverse();
        break;
      case BridgeGlowButtonState.idle:
        _pulseController.stop();
        _glowController.reverse();
        break;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 已鎖定 → 顯示鎖定標籤，按鈕消失
    if (widget.state == BridgeGlowButtonState.locked) {
      return AnimatedSwitcher(
        duration: BridgeDS.durationNormal,
        child: Container(
          key: const ValueKey('locked'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).tagSuccessBg,
            borderRadius: BorderRadius.circular(BridgeDS.roundPill),
            border: Border.all(color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 14, color: BridgeDSColors.of(context).tagSuccessFg),
              SizedBox(width: 6),
              Text(
                '已鎖定',
                style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).tagSuccessFg),
              ),
            ],
          ),
        ),
      );
    }

    final glowColor = widget.state == BridgeGlowButtonState.success
        ? BridgeDSColors.of(context).accentGreen
        : BridgeDSColors.of(context).accentBlue;

    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _glow]),
      builder: (context, child) {
        return Container(
          decoration: _glow.value > 0
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(BridgeDS.roundPill),
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withValues(alpha: 0.3 * _glow.value),
                      blurRadius: 16 * _glow.value,
                      spreadRadius: 2 * _glow.value,
                    ),
                  ],
                )
              : null,
          child: Opacity(
            opacity: widget.state == BridgeGlowButtonState.testing
                ? _pulse.value
                : 1.0,
            child: child,
          ),
        );
      },
      child: FilledButton.icon(
        onPressed: widget.state == BridgeGlowButtonState.testing
            ? null
            : widget.onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: widget.state == BridgeGlowButtonState.success
              ? BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.15)
              : null,
          foregroundColor: widget.state == BridgeGlowButtonState.success
              ? BridgeDSColors.of(context).accentGreen
              : null,
        ),
        icon: widget.icon != null ? Icon(widget.icon, size: 16) : null,
        label: Text(widget.label),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════
/// Bridge Motion — 面板動態
/// ═══════════════════════════════════════════════════

/// 可滑入/滑出的面板——用於側欄、資訊面板
class BridgeAnimatedPanel extends StatelessWidget {
  final Widget child;
  final bool visible;
  final double width;
  final AxisDirection slideFrom;

  const BridgeAnimatedPanel({
    super.key,
    required this.child,
    required this.visible,
    this.width = 320,
    this.slideFrom = AxisDirection.right,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: BridgeDS.durationNormal,
      curve: BridgeDS.transitionCanvas,
      alignment: Alignment.center,
      child: visible
          ? SizedBox(
              width: width,
              child: child,
            )
          : const SizedBox.shrink(),
    );
  }
}

/// ═══════════════════════════════════════════════════
/// Bridge Motion — 狀態指示器
/// ═══════════════════════════════════════════════════

/// 脈動光點——用於「Agent 共視中」等持續狀態指示
class BridgePulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool active;

  BridgePulseDot({
    super.key,
    this.color = BridgeDS.accentBlue,
    this.size = 8,
    this.active = true,
  });

  @override
  State<BridgePulseDot> createState() => _BridgePulseDotState();
}

class _BridgePulseDotState extends State<BridgePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // [小葵 2026-10-05 節能根修] repeat(reverse:) 每幀都排 vsync——一顆小綠點
    // 60fps 是 50 倍浪費。脈動週期 1.2s、幅度僅 scale 1→2：12fps 人眼零差異。
    // 自訂低頻 ticker：每 83ms 跳一格（12fps），CPU 直接砍 1/5。
    _lowFreqTicker = Timer.periodic(const Duration(milliseconds: 83), (_) {
      if (!mounted || !widget.active) return;
      _tick = (_tick + 1) % 72; // 6 幀/單程 × 12 = 72 格循環
      _controller.value = _curveValue(_tick);
    });
    _scale = Tween<double>(begin: 1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    if (widget.active) _controller.value = 0.0;
  }

  Timer? _lowFreqTicker;
  int _tick = 0;

  /// 12fps 離散取樣 easeOut 曲線——6 個關鍵幀來回
  double _curveValue(int tick) {
    final phase = (tick % 12) / 12.0; // 0..1
    // easeOut: 1-(1-t)^2
    final eased = 1.0 - (1.0 - phase) * (1.0 - phase);
    return tick < 12 ? eased : 1.0 - ((tick - 12) % 12) / 12.0 * 0.0;
  }

  @override
  void didUpdateWidget(BridgePulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat();
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _lowFreqTicker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
      );
    }

    return SizedBox(
      width: widget.size * 2,
      height: widget.size * 2,
      // [小葵 2026-10-05 節能] RepaintBoundary 隔離——pulse 動畫只重繪這 16px 小區，
      // 不再連帶整個頂欄/首頁 PAINT。配合外層動畫是唯一活著的 ticker。
      child: RepaintBoundary(
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Transform.scale(
                  scale: _scale.value,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: _opacity.value),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════
/// Bridge Motion — 進度條（Miro 風格）
/// ═══════════════════════════════════════════════════

/// 帶有光暈的進度條——用於 API 測試、生成等待
class BridgeGlowProgress extends StatefulWidget {
  final bool active;
  final Color color;
  final double height;

  BridgeGlowProgress({
    super.key,
    required this.active,
    this.color = BridgeDS.accentBlue,
    this.height = 3,
  });

  @override
  State<BridgeGlowProgress> createState() => _BridgeGlowProgressState();
}

class _BridgeGlowProgressState extends State<BridgeGlowProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(BridgeGlowProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat();
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.height),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return LinearProgressIndicator(
              value: null, // 不定進度
              backgroundColor: widget.color.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(widget.color),
              minHeight: widget.height,
            );
          },
        ),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════
/// Bridge Motion — 測試成功標記
/// ═══════════════════════════════════════════════════

/// 成功勾選動畫——測試通過時打勾 + 光環擴散
class BridgeSuccessCheck extends StatefulWidget {
  final bool show;
  final double size;

  const BridgeSuccessCheck({
    super.key,
    required this.show,
    this.size = 24,
  });

  @override
  State<BridgeSuccessCheck> createState() => _BridgeSuccessCheckState();
}

class _BridgeSuccessCheckState extends State<BridgeSuccessCheck>
    with TickerProviderStateMixin {
  late final AnimationController _checkController;
  late final AnimationController _ringController;
  late final Animation<double> _checkScale;
  late final Animation<double> _ringScale;
  late final Animation<double> _ringOpacity;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: BridgeDS.durationNormal,
    );
    _ringController = AnimationController(
      vsync: this,
      duration: BridgeDS.durationSlow,
    );
    _checkScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _checkController, curve: BridgeDS.transitionMorph),
    );
    _ringScale = Tween<double>(begin: 0.5, end: 2.0).animate(
      CurvedAnimation(parent: _ringController, curve: BridgeDS.transitionCanvas),
    );
    _ringOpacity = Tween<double>(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeOut),
    );
    if (widget.show) _play();
  }

  void _play() {
    _checkController.forward();
    _ringController.forward();
  }

  @override
  void didUpdateWidget(BridgeSuccessCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show && !oldWidget.show) {
      _checkController.reset();
      _ringController.reset();
      _play();
    }
  }

  @override
  void dispose() {
    _checkController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.show) return const SizedBox.shrink();

    return SizedBox(
      width: widget.size * 2,
      height: widget.size * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 光環擴散
          AnimatedBuilder(
            animation: _ringController,
            builder: (context, _) {
              return Transform.scale(
                scale: _ringScale.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: BridgeDSColors.of(context).accentGreen
                          .withValues(alpha: _ringOpacity.value),
                      width: 2,
                    ),
                  ),
                ),
              );
            },
          ),
          // 勾選圖示
          ScaleTransition(
            scale: _checkScale,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).accentGreen,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                Icons.check_rounded,
                color: BridgeDSColors.of(context).canvas,
                size: widget.size * 0.7,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
