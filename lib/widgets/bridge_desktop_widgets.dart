// Bridge Desktop Widgets — 設計系統元件庫
// 依據 DESIGN.md component spec 實作
// 五套融合：xAI 氛圍 × Raycast 色彩 × Stripe 粒子 × Figma 動態 × Miro 無限畫布

import 'package:flutter/material.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

// ═══════════════════════════════════════════════════
// Pill Button — Figma pill 50px + Raycast opacity hover + xAI mono uppercase
// ═══════════════════════════════════════════════════

enum BridgeButtonType { primary, accent, ghost, brain }

class BridgePillButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final BridgeButtonType type;
  final IconData? icon;
  final bool expanded;

  const BridgePillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.type = BridgeButtonType.primary,
    this.icon,
    this.expanded = false,
  });

  @override
  State<BridgePillButton> createState() => _BridgePillButtonState();
}

class _BridgePillButtonState extends State<BridgePillButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;

    Color bgColor;
    Color textColor;
    Border? border;

    switch (widget.type) {
      case BridgeButtonType.primary:
        bgColor = BridgeDSColors.of(context).textPrimary;
        textColor = BridgeDSColors.of(context).canvas;
        border = null;
        break;
      case BridgeButtonType.accent:
        bgColor = BridgeDSColors.of(context).accentBlue;
        textColor = BridgeDSColors.of(context).canvas;
        border = null;
        break;
      case BridgeButtonType.ghost:
        bgColor = Colors.transparent;
        textColor = BridgeDSColors.of(context).textPrimary;
        border = Border.all(color: BridgeDSColors.of(context).borderDefault, width: 1);
        break;
      case BridgeButtonType.brain:
        bgColor = BridgeDSColors.of(context).accentPurple;
        textColor = BridgeDSColors.of(context).textPrimary;
        border = null;
        break;
    }

    // hover opacity transition (Raycast 簽名互動)
    final hoverOpacity = _hovering && !isDisabled
        ? (widget.type == BridgeButtonType.primary ? 0.6 : 0.8)
        : 1.0;

    return MouseRegion(
      cursor: isDisabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: BridgeDS.durationFast,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor.withValues(alpha: bgColor.a * hoverOpacity),
            borderRadius: BorderRadius.circular(BridgeDS.roundPill),
            border: border,
            boxShadow: widget.type == BridgeButtonType.brain
                ? BridgeDS.glowPurple
                : null,
          ),
          child: Row(
            mainAxisSize: widget.expanded
                ? MainAxisSize.max
                : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 16, color: textColor),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label.toUpperCase(),
                style: BridgeDSColors.of(context).button.copyWith(color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Bridge Card — Raycast 雙環陰影 + xAI 透明邊框
// ═══════════════════════════════════════════════════

class BridgeCard extends StatefulWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double? width;
  final bool isBrain; // 大腦卡片用紫調邊框 + 藍調陰影
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  const BridgeCard({
    super.key,
    required this.child,
    this.padding,
    this.width,
    this.isBrain = false,
    this.onTap,
    this.borderRadius,
  });

  @override
  State<BridgeCard> createState() => _BridgeCardState();
}

class _BridgeCardState extends State<BridgeCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ??
        BorderRadius.circular(
          widget.isBrain ? BridgeDS.roundWide : BridgeDS.roundComfortable,
        );

    // 所有圖卡邊框統一用紫色（與第一張召喚夥伴一致），hover 加粗
    final borderColor = _hovering
        ? BridgeDSColors.of(context).accentPurple
        : BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.3);
    final borderWidth = _hovering ? 2.0 : 1.0;

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: BridgeDS.durationFast,
          width: widget.width,
          padding: widget.padding ?? const EdgeInsets.all(BridgeDS.spaceLG),
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).surface,
            borderRadius: radius,
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Status Tag — xAI mono + Raycast 語意色
// ═══════════════════════════════════════════════════

enum BridgeTagType { success, error, info, brain, warn }

class BridgeStatusTag extends StatefulWidget {
  final String label;
  final BridgeTagType type;
  final bool active;

  const BridgeStatusTag({
    super.key,
    required this.label,
    required this.type,
    this.active = true,
  });

  @override
  State<BridgeStatusTag> createState() => _BridgeStatusTagState();
}

class _BridgeStatusTagState extends State<BridgeStatusTag>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );
    // [教練 Agent 2026-07-28] 移除 repeat 動畫 — 5 個 BridgeStatusTag 同時 repeat 會吃 40%+ CPU
    // 改為只在 active 時顯示靜態 glow（用 value=0.5）
    if (widget.active) _glowController.value = 0.5;
  }

  @override
  void didUpdateWidget(BridgeStatusTag oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _glowController.value = 0.5;
    } else if (!widget.active && oldWidget.active) {
      _glowController.stop();
      _glowController.value = 0;
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Color _fgColor() => switch (widget.type) {
    BridgeTagType.success => BridgeDSColors.of(context).tagSuccessFg,
    BridgeTagType.error => BridgeDSColors.of(context).tagErrorFg,
    BridgeTagType.info => BridgeDSColors.of(context).tagInfoFg,
    BridgeTagType.brain => BridgeDSColors.of(context).tagBrainFg,
    BridgeTagType.warn => BridgeDSColors.of(context).tagWarnFg,
  };

  Color _bgColor() => switch (widget.type) {
    BridgeTagType.success => BridgeDSColors.of(context).tagSuccessBg,
    BridgeTagType.error => BridgeDSColors.of(context).tagErrorBg,
    BridgeTagType.info => BridgeDSColors.of(context).tagInfoBg,
    BridgeTagType.brain => BridgeDSColors.of(context).tagBrainBg,
    BridgeTagType.warn => BridgeDSColors.of(context).tagWarnBg,
  };

  @override
  Widget build(BuildContext context) {
    final bgColor = _bgColor();
    final fgColor = _fgColor();

    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final glowAlpha = widget.active
            ? 0.05 + _glowController.value * 0.2
            : 0.0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
            border: Border.all(
                color: fgColor.withValues(alpha: 0.2), width: 1),
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: fgColor.withValues(alpha: glowAlpha),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: Text(
        widget.label.toUpperCase(),
        style: BridgeDSColors.of(context).labelMono.copyWith(color: fgColor, fontSize: 14),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Active Glow — 通用呼吸發光 wrapper
// 原則：當前狀態/當前頁面提示 = 呼吸發光
// ═══════════════════════════════════════════════════

class BridgeActiveGlow extends StatefulWidget {
  final bool active;
  final Color color;
  final Widget child;
  final BorderRadius? borderRadius;

  const BridgeActiveGlow({
    super.key,
    this.active = false,
    required this.color,
    required this.child,
    this.borderRadius,
  });

  @override
  State<BridgeActiveGlow> createState() => _BridgeActiveGlowState();
}

class _BridgeActiveGlowState extends State<BridgeActiveGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );
    if (widget.active) _controller.value = 0.5;
  }

  @override
  void didUpdateWidget(BridgeActiveGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.value = 0.5;
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 呼吸發光：0.05 → 0.25 → 0.05
        final glowAlpha = 0.05 + _controller.value * 0.2;
        return Container(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: glowAlpha),
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ═══════════════════════════════════════════════════
// Bridge Input — Raycast dark input + xAI focus ring
// ═══════════════════════════════════════════════════

class BridgeInput extends StatefulWidget {
  final String? placeholder;
  final String? value;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;
  final bool obscureText;
  final TextEditingController? controller;
  final Widget? suffix;

  const BridgeInput({
    super.key,
    this.placeholder,
    this.value,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.controller,
    this.suffix,
  });

  @override
  State<BridgeInput> createState() => _BridgeInputState();
}

class _BridgeInputState extends State<BridgeInput> {
  bool _focused = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ??
        TextEditingController(text: widget.value ?? '');
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
      child: AnimatedContainer(
        duration: BridgeDS.durationFast,
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).canvas,
          borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
          border: Border.all(
            color: _focused ? BridgeDSColors.of(context).accentBlue : BridgeDSColors.of(context).borderSubtle,
            width: _focused ? 1.5 : 1,
          ),
          boxShadow: _focused ? BridgeDS.glowBlue : null,
        ),
        child: TextField(
          controller: _controller,
          obscureText: widget.obscureText,
          style: BridgeDSColors.of(context).body,
          onChanged: widget.onChanged,
          onSubmitted: (_) => widget.onSubmitted?.call(),
          decoration: InputDecoration(
            hintText: widget.placeholder,
            hintStyle: BridgeDSColors.of(context).body.copyWith(color: BridgeDSColors.of(context).textMuted),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            suffixIcon: widget.suffix,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Quick Action Chip — spring hover 動畫
// ═══════════════════════════════════════════════════

class BridgeChip extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool active;

  const BridgeChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.active = false,
  });

  @override
  State<BridgeChip> createState() => _BridgeChipState();
}

class _BridgeChipState extends State<BridgeChip>
    with TickerProviderStateMixin {
  bool _hovering = false;
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );
    if (widget.active) _glowController.value = 0.5;
  }

  @override
  void didUpdateWidget(BridgeChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _glowController.value = 0.5;
    } else if (!widget.active && oldWidget.active) {
      _glowController.stop();
      _glowController.value = 0;
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            final glowAlpha = widget.active
                ? 0.05 + _glowController.value * 0.2
                : 0.0;
            return AnimatedContainer(
              duration: BridgeDS.durationFast,
              curve: BridgeDS.transitionSpring,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: widget.active
                    ? ds.accentBlue.withValues(alpha: 0.15)
                    : (_hovering
                        ? ds.surfaceGlassHover
                        : ds.surfaceGlass),
                borderRadius: BorderRadius.circular(BridgeDS.roundPill),
                border: Border.all(
                  color: widget.active
                      ? ds.accentBlue.withValues(alpha: 0.4)
                      : ds.borderSubtle,
                  width: 1,
                ),
                boxShadow: widget.active
                    ? [
                        BoxShadow(
                          color: ds.accentBlue
                              .withValues(alpha: glowAlpha),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: child,
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 14,
                    color: widget.active
                        ? ds.accentBlue
                        : ds.textTertiary),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: BridgeDSColors.of(context).caption.copyWith(
                  fontSize: 16,
                  color: widget.active
                      ? ds.accentBlue
                      : ds.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Glow Divider — 區塊間的呼吸感亮線
// ═══════════════════════════════════════════════════

class BridgeGlowDivider extends StatefulWidget {
  final bool vertical;
  final Color color;

  BridgeGlowDivider({
    super.key,
    this.vertical = true,
    this.color = BridgeDS.accentPurple, // fallback; build() uses ds.accentPurple if null
  });

  @override
  State<BridgeGlowDivider> createState() => _BridgeGlowDividerState();
}

class _BridgeGlowDividerState extends State<BridgeGlowDivider>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 7000),
      vsync: this,
    )..value = 0.5;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 呼吸曲線：7 秒週期，單向循環
        // 前 30% 勻速亮起 → 中間 50% 維持最亮 → 後 20% 緩暗
        final t = _controller.value;
        double intensity;
        if (t < 0.3) {
          // 勻速亮起：0.1 → 0.7
          intensity = 0.1 + (t / 0.3) * 0.6;
        } else if (t < 0.8) {
          // 維持最亮：0.7
          intensity = 0.7;
        } else {
          // 緩暗：0.7 → 0.1
          intensity = 0.7 - ((t - 0.8) / 0.2) * 0.6;
        }
        return Container(
          width: widget.vertical ? 1 : double.infinity,
          height: widget.vertical ? double.infinity : 1,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: intensity),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: intensity * 0.7),
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ],
          ),
        );
      },
    );
  }
}

class BridgeStatusDot extends StatefulWidget {
  final bool active;
  final double size;

  const BridgeStatusDot({
    super.key,
    required this.active,
    this.size = 8,
  });

  @override
  State<BridgeStatusDot> createState() => _BridgeStatusDotState();
}

class _BridgeStatusDotState extends State<BridgeStatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    if (widget.active) _controller.value = 0.5;
  }

  @override
  void didUpdateWidget(BridgeStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.value = 0.5;
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
    final ds = BridgeDSColors.of(context);
    final color = widget.active ? ds.accentGreen : ds.textMuted;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = widget.active
            ? 1.0 + _controller.value * 0.3
            : 1.0;
        final glowOpacity = widget.active
            ? 0.15 + _controller.value * 0.15
            : 0.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: widget.active
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: glowOpacity),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      },
    );
  }
}
