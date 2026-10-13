// Bridge Design System — 五套融合設計 token
// 來源：xAI 氛圍 × Raycast 色彩 × Stripe 粒子 × Figma 動態 × Miro 無限畫布
// 正本：bridge_app/DESIGN.md
//
// 此檔案是桌面端設計系統的唯一 token 來源。
// 手機端 AppTheme 不動——手機版未來再統一。

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../state/typography_scale_provider.dart';
import 'tier_style.dart'; // [教練 Agent 2026-08-05] Step 3c — TierTheme 接到 themeFrom

/// ═══════════════════════════════════════════════════
/// Bridge Design Tokens
/// ═══════════════════════════════════════════════════

/// ═══════════════════════════════════════════════════
/// BridgeDSColors — ThemeExtension for light/dark mode
/// ═══════════════════════════════════════════════════
///
/// 漸進遷移策略：
/// - 舊的 static const 保持不動（仍對應暗色值）
/// - 新的 widget 用 BridgeDS.of(context).canvas 等存取
/// - 遷移完成後可移除 static const
@immutable
class BridgeDSColors extends ThemeExtension<BridgeDSColors> {
  const BridgeDSColors({
    required this.canvas,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHover,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textMuted,
    required this.textQuaternary,
    required this.accentRed,
    required this.accentBlue,
    required this.accentGreen,
    required this.accentYellow,
    required this.accentPurple,
    required this.accentNavy,
    required this.accentMagenta,
    required this.accentRuby,
    required this.accentMiro,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderStrong,
    required this.surfaceGlass,
    required this.surfaceGlassHover,
    required this.tagSuccessBg,
    required this.tagSuccessFg,
    required this.tagErrorBg,
    required this.tagErrorFg,
    required this.tagInfoBg,
    required this.tagInfoFg,
    required this.tagBrainBg,
    required this.tagBrainFg,
    required this.tagWarnBg,
    required this.tagWarnFg,
  });

  // ── Canvas & Surface ──────
  final Color canvas;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceHover;

  // ── 文字層級 ──────
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textMuted;
  final Color textQuaternary;

  // ── 互動色 ──────
  final Color accentRed;
  final Color accentBlue;
  final Color accentGreen;
  final Color accentYellow;
  final Color accentPurple;
  final Color accentNavy;
  final Color accentMagenta;
  final Color accentRuby;
  final Color accentMiro;

  // ── 透明度疊層 ──────
  final Color borderSubtle;
  final Color borderDefault;
  final Color borderStrong;
  final Color surfaceGlass;
  final Color surfaceGlassHover;

  // ── 狀態標籤 ──────
  final Color tagSuccessBg;
  final Color tagSuccessFg;
  final Color tagErrorBg;
  final Color tagErrorFg;
  final Color tagInfoBg;
  final Color tagInfoFg;
  final Color tagBrainBg;
  final Color tagBrainFg;
  final Color tagWarnBg;
  final Color tagWarnFg;

  /// 暗色 token（與舊 static const 完全一致）
  static const dark = BridgeDSColors(
    canvas: Color(0xFF1D1E20),         // 原 #151617 → 再提亮
    surface: Color(0xFF27282A),         // 原 #1F2022 → 再提亮
    surfaceElevated: Color(0xFF323335), // 原 #2A2B2D → 再提亮
    surfaceHover: Color(0xFF3D3E40),    // 原 #343537 → 再提亮
    textPrimary: Color(0xFFD8DCE0),      // [教練 Agent 2026-08-12] 原 #F9F9F9 → 灰白
    textSecondary: Color(0xFFB8B8B8),
    textTertiary: Color(0xFF8E8E8F),
    textMuted: Color(0xFF6A6B6C),
    textQuaternary: Color(0xFF434345),
    accentRed: Color(0xFFFF6363),
    accentBlue: Color(0xFF55B3FF),
    accentGreen: Color(0xFF5FC992),
    accentYellow: Color(0xFFFFBC33),
    accentPurple: Color(0xFF533AFD),
    accentNavy: Color(0xFF061B31),
    accentMagenta: Color(0xFFF96BEE),
    accentRuby: Color(0xFFEA2261),
    accentMiro: Color(0xFF5B76FE),
    borderSubtle: Color(0x0FFFFFFF),
    borderDefault: Color(0x1AFFFFFF),
    borderStrong: Color(0x33FFFFFF),
    surfaceGlass: Color(0x0DFFFFFF),
    surfaceGlassHover: Color(0x14FFFFFF),
    tagSuccessBg: Color(0xFF0E1B12),
    tagSuccessFg: Color(0xFFB8E8CC),
    tagErrorBg: Color(0xFF1B0E0E),
    tagErrorFg: Color(0xFFFFADAD),
    tagInfoBg: Color(0xFF0E151B),
    tagInfoFg: Color(0xFFB3DCFF),
    tagBrainBg: Color(0xFF0E0A1B),
    tagBrainFg: Color(0xFFB9B9F9),
    tagWarnBg: Color(0xFF1B160E),
    tagWarnFg: Color(0xFFFFD580),
  );

  /// 淺色 token — 不是簡單反轉，每個色值重新設計層級感
  static const light = BridgeDSColors(
    canvas: Color(0xFFE8E9ED),          // 淺灰畫布底
    surface: Color(0xFFFFFFFF),          // 純白卡片
    surfaceElevated: Color(0xFFF4F5F6),  // 淺灰提升
    surfaceHover: Color(0xFFECEDEE),     // hover 灰
    textPrimary: Color(0xFF1A1B1E),      // 近黑
    textSecondary: Color(0xFF3A3B3D),    // 深灰（加深，原 #4A4B4D，使用者 看不清）
    textTertiary: Color(0xFF525355),     // 中灰（加深，原 #6A6B6D）
    textMuted: Color(0xFF6A6B6D),        // 中深灰（加深，原 #8A8B8D — 對比度 < 4.5:1 過低）
    textQuaternary: Color(0xFF8A8B8D),   // 中淺灰（加深，原 #A0A1A3 — 對比度 < 3:1 過低）
    // 互動色：淺色模式要更深更飽和
    accentRed: Color(0xFFE53E3E),
    accentBlue: Color(0xFF0066CC),
    accentGreen: Color(0xFF2E9D5F),
    accentYellow: Color(0xFFD4A017),
    accentPurple: Color(0xFF4B2FBF),
    accentNavy: Color(0xFF1B3A5C),
    accentMagenta: Color(0xFFD43AB5),
    accentRuby: Color(0xFFC4154E),
    accentMiro: Color(0xFF4051CC),
    // 透明度：白底用黑色透明度
    borderSubtle: Color(0x0F000000),     // rgba(0,0,0,0.06)
    borderDefault: Color(0x1A000000),    // rgba(0,0,0,0.10)
    borderStrong: Color(0x33000000),     // rgba(0,0,0,0.20)
    surfaceGlass: Color(0x0D000000),     // rgba(0,0,0,0.05)
    surfaceGlassHover: Color(0x14000000),// rgba(0,0,0,0.08)
    // 標籤：淺色底+深色字
    tagSuccessBg: Color(0xFFE8F5ED),
    tagSuccessFg: Color(0xFF1B6B3F),
    tagErrorBg: Color(0xFFFDEAEA),
    tagErrorFg: Color(0xFFB91C1C),
    tagInfoBg: Color(0xFFE8F2FC),
    tagInfoFg: Color(0xFF1B5A9C),
    tagBrainBg: Color(0xFFEDE8F7),
    tagBrainFg: Color(0xFF4B2FBF),
    tagWarnBg: Color(0xFFFDF3E0),
    tagWarnFg: Color(0xFF9C6B0F),
  );

  static BridgeDSColors of(BuildContext context) =>
      Theme.of(context).extension<BridgeDSColors>() ?? dark;

  // ── 動態 TextStyle getter（跟隨暗/淺色切換）──────
  // 取代 static const TextStyle，這些會根據當前模式的 textPrimary 等值變色
  
  TextStyle get headingL => TextStyle(
    fontFamily: BridgeDS.fontDisplay, fontSize: 32, fontWeight: FontWeight.w400,
    height: 1.20, letterSpacing: -0.02 * 32, color: textPrimary,
  );
  TextStyle get headingM => TextStyle(
    fontFamily: BridgeDS.fontBody, fontSize: 24, fontWeight: FontWeight.w500,
    height: 1.30, letterSpacing: 0.2, color: textPrimary,
  );
  TextStyle get headingS => TextStyle(
    fontFamily: BridgeDS.fontBody, fontSize: 20, fontWeight: FontWeight.w500,
    height: 1.40, letterSpacing: 0.2, color: textPrimary,
  );
  TextStyle get bodyL => TextStyle(
    fontFamily: BridgeDS.fontBody, fontSize: 18, fontWeight: FontWeight.w400,
    height: 1.50, letterSpacing: 0.2, color: textPrimary,
  );
  TextStyle get body => TextStyle(
    fontFamily: BridgeDS.fontBody, fontSize: 16, fontWeight: FontWeight.w500,
    height: 1.60, letterSpacing: 0.2, color: textPrimary,
  );
  TextStyle get bodyTight => TextStyle(
    fontFamily: BridgeDS.fontBody, fontSize: 16, fontWeight: FontWeight.w400,
    height: 1.15, letterSpacing: 0.1, color: textPrimary,
  );
  TextStyle get button => TextStyle(
    fontFamily: BridgeDS.fontDisplay, fontSize: 14, fontWeight: FontWeight.w500,
    height: 1.15, letterSpacing: 0.3, color: textPrimary,
  );
  TextStyle get labelMono => TextStyle(
    fontFamily: BridgeDS.fontDisplay, fontSize: 12, fontWeight: FontWeight.w500,
    height: 1.60, letterSpacing: 0.6, color: textTertiary,
  );
  TextStyle get caption => TextStyle(
    fontFamily: BridgeDS.fontBody, fontSize: 14, fontWeight: FontWeight.w500,
    height: 1.14, letterSpacing: 0.2, color: textSecondary,
  );
  TextStyle get small => TextStyle(
    fontFamily: BridgeDS.fontBody, fontSize: 12, fontWeight: FontWeight.w600,
    height: 1.33, color: textTertiary,
  );
  TextStyle get code => TextStyle(
    fontFamily: BridgeDS.fontDisplay, fontSize: 14, fontWeight: FontWeight.w500,
    height: 1.60, letterSpacing: 0.3, color: textPrimary,
  );
  TextStyle get display => TextStyle(
    fontFamily: BridgeDS.fontDisplay, fontSize: 48, fontWeight: FontWeight.w300,
    height: 1.10, letterSpacing: -0.04 * 48, color: textPrimary,
  );

  @override
  BridgeDSColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceHover,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textMuted,
    Color? textQuaternary,
    Color? accentRed,
    Color? accentBlue,
    Color? accentGreen,
    Color? accentYellow,
    Color? accentPurple,
    Color? accentNavy,
    Color? accentMagenta,
    Color? accentRuby,
    Color? accentMiro,
    Color? borderSubtle,
    Color? borderDefault,
    Color? borderStrong,
    Color? surfaceGlass,
    Color? surfaceGlassHover,
    Color? tagSuccessBg,
    Color? tagSuccessFg,
    Color? tagErrorBg,
    Color? tagErrorFg,
    Color? tagInfoBg,
    Color? tagInfoFg,
    Color? tagBrainBg,
    Color? tagBrainFg,
    Color? tagWarnBg,
    Color? tagWarnFg,
  }) {
    return BridgeDSColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textMuted: textMuted ?? this.textMuted,
      textQuaternary: textQuaternary ?? this.textQuaternary,
      accentRed: accentRed ?? this.accentRed,
      accentBlue: accentBlue ?? this.accentBlue,
      accentGreen: accentGreen ?? this.accentGreen,
      accentYellow: accentYellow ?? this.accentYellow,
      accentPurple: accentPurple ?? this.accentPurple,
      accentNavy: accentNavy ?? this.accentNavy,
      accentMagenta: accentMagenta ?? this.accentMagenta,
      accentRuby: accentRuby ?? this.accentRuby,
      accentMiro: accentMiro ?? this.accentMiro,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderDefault: borderDefault ?? this.borderDefault,
      borderStrong: borderStrong ?? this.borderStrong,
      surfaceGlass: surfaceGlass ?? this.surfaceGlass,
      surfaceGlassHover: surfaceGlassHover ?? this.surfaceGlassHover,
      tagSuccessBg: tagSuccessBg ?? this.tagSuccessBg,
      tagSuccessFg: tagSuccessFg ?? this.tagSuccessFg,
      tagErrorBg: tagErrorBg ?? this.tagErrorBg,
      tagErrorFg: tagErrorFg ?? this.tagErrorFg,
      tagInfoBg: tagInfoBg ?? this.tagInfoBg,
      tagInfoFg: tagInfoFg ?? this.tagInfoFg,
      tagBrainBg: tagBrainBg ?? this.tagBrainBg,
      tagBrainFg: tagBrainFg ?? this.tagBrainFg,
      tagWarnBg: tagWarnBg ?? this.tagWarnBg,
      tagWarnFg: tagWarnFg ?? this.tagWarnFg,
    );
  }

  @override
  BridgeDSColors lerp(BridgeDSColors? other, double t) {
    if (other == null) return this;
    return BridgeDSColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textQuaternary: Color.lerp(textQuaternary, other.textQuaternary, t)!,
      accentRed: Color.lerp(accentRed, other.accentRed, t)!,
      accentBlue: Color.lerp(accentBlue, other.accentBlue, t)!,
      accentGreen: Color.lerp(accentGreen, other.accentGreen, t)!,
      accentYellow: Color.lerp(accentYellow, other.accentYellow, t)!,
      accentPurple: Color.lerp(accentPurple, other.accentPurple, t)!,
      accentNavy: Color.lerp(accentNavy, other.accentNavy, t)!,
      accentMagenta: Color.lerp(accentMagenta, other.accentMagenta, t)!,
      accentRuby: Color.lerp(accentRuby, other.accentRuby, t)!,
      accentMiro: Color.lerp(accentMiro, other.accentMiro, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      surfaceGlass: Color.lerp(surfaceGlass, other.surfaceGlass, t)!,
      surfaceGlassHover: Color.lerp(surfaceGlassHover, other.surfaceGlassHover, t)!,
      tagSuccessBg: Color.lerp(tagSuccessBg, other.tagSuccessBg, t)!,
      tagSuccessFg: Color.lerp(tagSuccessFg, other.tagSuccessFg, t)!,
      tagErrorBg: Color.lerp(tagErrorBg, other.tagErrorBg, t)!,
      tagErrorFg: Color.lerp(tagErrorFg, other.tagErrorFg, t)!,
      tagInfoBg: Color.lerp(tagInfoBg, other.tagInfoBg, t)!,
      tagInfoFg: Color.lerp(tagInfoFg, other.tagInfoFg, t)!,
      tagBrainBg: Color.lerp(tagBrainBg, other.tagBrainBg, t)!,
      tagBrainFg: Color.lerp(tagBrainFg, other.tagBrainFg, t)!,
      tagWarnBg: Color.lerp(tagWarnBg, other.tagWarnBg, t)!,
      tagWarnFg: Color.lerp(tagWarnFg, other.tagWarnFg, t)!,
    );
  }
}

class BridgeDS {
  BridgeDS._();

  // ── Canvas & Surface (xAI 氛圍 → Raycast 質感) ──────
  // 舊的 static const 保持暗色值，漸進遷移到 ThemeExtension
  static const Color canvas = Color(0xFF07080A);          // Raycast 近黑藍
  static const Color surface = Color(0xFF101111);          // 卡片面板底色
  static const Color surfaceElevated = Color(0xFF1B1C1E);  // badge、標籤
  static const Color surfaceHover = Color(0xFF252829);     // hover 提升

  // ── 文字層級 (xAI 白階 + Raycast 灰階) ──────────────
  static const Color textPrimary = Color(0xFFF9F9F9);
  static const Color textSecondary = Color(0xFFCECECE);
  static const Color textTertiary = Color(0xFF9C9C9D);
  static const Color textMuted = Color(0xFF6A6B6C);
  static const Color textQuaternary = Color(0xFF434345);

  // ── 互動色 (Raycast 語意 + Stripe 數據) ─────────────
  static const Color accentRed = Color(0xFFFF6363);
  static const Color accentBlue = Color(0xFF55B3FF);
  static const Color accentGreen = Color(0xFF5FC992);
  static const Color accentYellow = Color(0xFFFFBC33);
  static const Color accentPurple = Color(0xFF533AFD);     // 大腦/向量專用
  static const Color accentNavy = Color(0xFF061B31);
  static const Color accentMagenta = Color(0xFFF96BEE);
  static const Color accentRuby = Color(0xFFEA2261);
  static const Color accentMiro = Color(0xFF5B76FE);       // 無限畫布互動

  // ── 透明度疊層 ──────────────────────────────────────
  static const Color borderSubtle = Color(0x0FFFFFFF);     // rgba(255,255,255,0.06)
  static const Color borderDefault = Color(0x1AFFFFFF);    // rgba(255,255,255,0.10)
  static const Color borderStrong = Color(0x33FFFFFF);     // rgba(255,255,255,0.20)
  static const Color surfaceGlass = Color(0x0DFFFFFF);     // rgba(255,255,255,0.05)
  static const Color surfaceGlassHover = Color(0x14FFFFFF);// rgba(255,255,255,0.08)

  // ── 大腦可視化粒子色 ────────────────────────────────
  static const Color particle1 = Color(0xFF533AFD);        // 紫 — 核心節點
  static const Color particle2 = Color(0xFFF96BEE);        // 洋紅 — 連線光
  static const Color particle3 = Color(0xFF55B3FF);        // 藍 — 活躍路徑
  static const Color particle4 = Color(0xFF5FC992);        // 綠 — 成功觸發
  static const Color particleGlow = Color(0x40533AFD);     // 紫光暈

  // ── 狀態標籤專用底色 ────────────────────────────────
  static const Color tagSuccessBg = Color(0xFF0E1B12);
  static const Color tagSuccessFg = Color(0xFFB8E8CC);
  static const Color tagErrorBg = Color(0xFF1B0E0E);
  static const Color tagErrorFg = Color(0xFFFFADAD);
  static const Color tagInfoBg = Color(0xFF0E151B);
  static const Color tagInfoFg = Color(0xFFB3DCFF);
  static const Color tagBrainBg = Color(0xFF0E0A1B);
  static const Color tagBrainFg = Color(0xFFB9B9F9);
  static const Color tagWarnBg = Color(0xFF1B160E);
  static const Color tagWarnFg = Color(0xFFFFD580);

  // ── 階段 C 新增 (2026-08-05) — UI 寫死 hex 顏色收斂 ─────────────

  /// 柔和綠（agent_loop_progress 成功色）
  static const Color softGreen = Color(0xFF81C784);

  /// 工具紫（agent_loop 強調色）
  static const Color toolPurple = Color(0xFF7C4DFF);

  /// 淺紫文字（agent_loop 提示）
  static const Color toolPurpleLight = Color(0xFFB388FF);

  /// 錯誤紅（Material red 500）
  static const Color errorRed = Color(0xFFEF5350);

  /// 藍色（Material blue 400）
  static const Color lightBlue = Color(0xFF42A5F5);

  /// 青綠色（節點顏色）
  static const Color teal = Color(0xFF4ECDC4);

  /// 灰藍色（節點預設）
  static const Color slate = Color(0xFF8E9AAF);

  /// 深紫（自定義節點顏色）
  static const Color deepPurple = Color(0xFF7C89FF);

  /// 藍色（節點 — 檔案類）
  static const Color fileBlue = Color(0xFF4A9EFF);

  /// 橙黃（SOP 節點色）
  static const Color sopOrange = Color(0xFFFFB454);

  /// 粉紅（子分析節點色）
  static const Color pinkAccent = Color(0xFFFF6B9D);

  /// 深色面板（CanvasDoodle 等深色 overlay）
  static const Color darkPanel = Color(0xFF323335);   // [教練 Agent 2026-08-12] 原 #1E1E2E → #2A2B2E → 再提亮

  /// 深色畫布（agent_loop 深背景）
  static const Color darkCanvas = Color(0xFF1D1E20);    // [教練 Agent 2026-08-12] 原 #0D0D1A → #151617 → 再提亮

  /// 沉靜綠（頂部 success 標記）
  static const Color successGreen = Color(0xFF6B8E6B);

  /// 淡紫（提示）
  static const Color hintPurple = Color(0xFF8888AA);

  /// 淡紫粉（背景裝飾）
  static const Color hintPink = Color(0xFFCE93D8);

  /// 深綠（成功強調）
  static const Color successDark = Color(0xFF2E7D32);

  /// 純亮藍（強調）
  static const Color brightCyan = Color(0xFF00D4FF);

  /// Google 藍（特殊鏈結）
  static const Color googleBlue = Color(0xFF1A73E8);

  /// 金色（特殊高亮）
  static const Color goldAccent = Color(0xFFFFD700);

  /// 紅色強調（嚴重警告）
  static const Color alertRed = Color(0xFFFF1744);

  /// 資訊藍（status bar）
  static const Color infoBlue = Color(0xFF4A90D9);

  /// 紅色（Material red 700）
  static const Color red700 = Color(0xFFD32F2F);

  /// 柏林紅（Material red 800）
  static const Color berlinRed = Color(0xFFC8102E);

  /// 淡紅背景（失敗背景 tag）
  static const Color bgLightRed = Color(0xFFFFF3F2);

  /// 淡綠背景（成功背景 tag）
  static const Color bgLightGreen = Color(0xFFF1F8E9);

  /// 極淡紅背景（hover/低飽和失敗）
  static const Color bgVeryLightRed = Color(0xFFFFF8F7);

  /// 淺灰（次要文字）
  static const Color lightGray = Color(0xFFE0E0E0);

  /// 橙色（Material orange 500）
  static const Color orange500 = Color(0xFFFF9800);

  /// 淺橙（Material orange 300）
  static const Color orange300 = Color(0xFFFFB74D);

  /// 深藍紫（divider/分隔線）
  static const Color dividerIndigo = Color(0xFF2A2A4A);

  // ── 階段 D 新增 (2026-08-05) — Material Colors 收斂 ─────────────

  /// 純白（按鈕前景/文字）
  static const Color textOnAccent = Color(0xFFFFFFFF);

  /// 灰階 600（次要文字 - 對應 Colors.grey.shade600）
  static const Color grey600 = Color(0xFF757575);

  /// 灰階 700（再次要文字 - 對應 Colors.grey.shade700）
  static const Color grey700 = Color(0xFF616161);

  /// 灰階 800（深灰 - 對應 Colors.grey.shade800）
  static const Color grey800 = Color(0xFF424242);

  /// 灰階 400（淺灰 - 對應 Colors.grey.shade400）
  static const Color grey400 = Color(0xFFBDBDBD);

  /// 灰階 300（很淺灰 - 對應 Colors.grey.shade300）
  static const Color grey300 = Color(0xFFE0E0E0);

  /// 紅色 500（標準錯誤色）
  static const Color red500 = Color(0xFFF44336);

  /// 紅色 400（淺紅警告）
  static const Color red400 = Color(0xFFEF5350);

  /// 紅色 700（深紅嚴重錯誤）
  static const Color red700mat = Color(0xFFD32F2F);

  /// 綠色 500（標準成功色）
  static const Color green500 = Color(0xFF4CAF50);

  /// 綠色 700（深綠強調）
  static const Color green700 = Color(0xFF388E3C);

  /// 綠色 400（淺綠提示）
  static const Color green400 = Color(0xFF66BB6A);

  /// 藍色 500（標準資訊色）
  static const Color blue500 = Color(0xFF2196F3);

  /// 藍色 700（深藍強調）
  static const Color blue700 = Color(0xFF1976D2);

  /// 橙色 500（標準警告色）
  static const Color orangeStd = Color(0xFFFF9800);

  /// 橙色 700（深橙強調）
  static const Color orange700 = Color(0xFFF57C00);

  // ═══════════════════════════════════════════════════
  // Typography
  // ═══════════════════════════════════════════════════

  static const String fontDisplay = 'Geist Mono';
  static const String fontBody = 'Inter';

  static const List<String> fontFallback = [
    'Geist Mono',
    'Inter',
    'BridgeCJK',
    'Arial Unicode MS',
    'PingFang TC',
    'PingFang SC',
    'Heiti TC',
    'Noto Sans TC',
    'Noto Sans CJK TC',
    'Microsoft JhengHei',
  ];

  // Display — Geist Mono weight 300
  static const TextStyle display = TextStyle(
    fontFamily: fontDisplay,
    fontSize: 48,
    fontWeight: FontWeight.w300,
    height: 1.10,
    letterSpacing: -0.04 * 48, // -0.04em
    color: textPrimary,
  );

  // Heading L — Geist Mono weight 400
  static const TextStyle headingL = TextStyle(
    fontFamily: fontDisplay,
    fontSize: 32,
    fontWeight: FontWeight.w400,
    height: 1.20,
    letterSpacing: -0.02 * 32,
    color: textPrimary,
  );

  // Heading M — Inter weight 500
  static const TextStyle headingM = TextStyle(
    fontFamily: fontBody,
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.30,
    letterSpacing: 0.2,
    color: textPrimary,
  );

  // Heading S — Inter weight 500
  static const TextStyle headingS = TextStyle(
    fontFamily: fontBody,
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1.40,
    letterSpacing: 0.2,
    color: textPrimary,
  );

  // Body L — Inter weight 400
  static const TextStyle bodyL = TextStyle(
    fontFamily: fontBody,
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: 1.50,
    letterSpacing: 0.2,
    color: textPrimary,
  );

  // Body — Inter weight 500 (暗底 baseline 500)
  static const TextStyle body = TextStyle(
    fontFamily: fontBody,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.60,
    letterSpacing: 0.2,
    color: textPrimary,
  );

  // Body Tight — Inter weight 400
  static const TextStyle bodyTight = TextStyle(
    fontFamily: fontBody,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.15,
    letterSpacing: 0.1,
    color: textPrimary,
  );

  // Button — Geist Mono weight 500 uppercase
  static const TextStyle button = TextStyle(
    fontFamily: fontDisplay,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.15,
    letterSpacing: 0.3,
    color: textPrimary,
  );

  // Label Mono — Geist Mono weight 500 uppercase
  static const TextStyle labelMono = TextStyle(
    fontFamily: fontDisplay,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.60,
    letterSpacing: 0.6,
    color: textTertiary,
  );

  // Caption — Inter weight 500
  static const TextStyle caption = TextStyle(
    fontFamily: fontBody,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.14,
    letterSpacing: 0.2,
    color: textSecondary,
  );

  // Small — Inter weight 600
  static const TextStyle small = TextStyle(
    fontFamily: fontBody,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.33,
    color: textTertiary,
  );

  // Code — Geist Mono weight 500
  static const TextStyle code = TextStyle(
    fontFamily: fontDisplay,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.60,
    letterSpacing: 0.3,
    color: textPrimary,
  );

  // ════════════════════════════════════════════════════════════════════
  // ⭐ 視覺設計指導原則（最高原則 — 新增/調整 UI 必讀）
  // ════════════════════════════════════════════════════════════════════
  //
  // 📐 一、文字大小（Type Scale）
  // ───────────────────────────────────────────────────────────────
  // 標準級距只有 8 個，必須用 token，禁止用魔術數字：
  //
  //   48  display     頁面 hero 數字（dashboard KPI）
  //   32  headingL    區塊大標題
  //   24  headingM    子區塊標題
  //   20  headingS    卡片標題
  //   18  bodyL       重要內文（alert 重點）
  //   16  body        對話泡泡主文、輸入框
  //   14  button / caption / small  ⭐ 最小限度 — 按鈕標籤、metadata、tag、狀態文字
  //
  // ❌ 禁用：fontSize: 10, 11, 12, 13, 15, 17, 19, 21, 22, 23, 25, 26, 27, 28, 29, 30, 31
  // 原因：非設計級距、視覺上會感覺「散亂」、對最小可讀性也不友好。
  // 最低限度：fontSize: 14 — 桌機不應小於此（2026-08-03 用戶決策：設計指導原則最小不能低於 14）。
  // 對話泡泡主文：fontSize: 16（body）— 升級自之前的 13/14 混亂。
  //
  // ───────────────────────────────────────────────────────────────
  // 🎯 二、圖示大小（Icon Size）
  // ───────────────────────────────────────────────────────────────
  // 標準級距只有 6 個，必須用 token：
  //
  //   24  iconHero  標題區 icon、頁面級 icon
  //   20  iconXL    主動作按鈕（送出、新增節點）
  //   18  iconLg    工具列按鈕、側邊選單
  //   16  iconMd    ⭐ 預設按鈕 icon、行內 icon
  //   14  iconSm    標籤內 icon、輔助 icon
  //   12  iconXs    內嵌標記、狀態點
  //
  // ❌ 禁用：size: 4, 6, 8, 10, 11, 13, 15, 17, 19, 22, 26, 28, 32 以上特殊尺寸
  // 最低限度：size: 12（iconXs）— 桌機不應小於此。
  //
  // ───────────────────────────────────────────────────────────────
  // 🎨 三、顏色（Color）
  // ───────────────────────────────────────────────────────────────
  // 必須用 BridgeDSColors.of(context) 來存取，禁用：
  //   ❌ Color(0xFFXXXXXX) — 硬編碼 hex
  //   ❌ Colors.white / Colors.black / Colors.red — Material 預設
  //   ❌ 主題變數外 inline 寫死顏色
  // 例外：陰影/shadow 的 Color(0xFFXXXXXX) 允許（已在 ringShadow / level1 等內）。
  //
  // 文字 4 個層級：
  //   textPrimary    主要文字（high-emphasis）
  //   textSecondary  次要文字（medium-emphasis）
  //   textTertiary   輔助文字（disabled / low-emphasis）
  //   textMuted      最低強調（純背景標記）
  //
  // 表面 4 個層級：
  //   canvas            最底層（畫布背景）
  //   surface           一般卡片
  //   surfaceElevated   浮動視窗、modal
  //   surfaceHover      hover 狀態（互動反饋）
  //
  // Accent 7 色（語意化）：
  //   accentBlue / Green / Red / Yellow / Purple / Navy / Magenta
  //   用途：狀態、節點類型、提示。不要把 accent 當文字色用。
  //
  // ───────────────────────────────────────────────────────────────
  // ⚡ 四、互動狀態（Interaction State）
  // ───────────────────────────────────────────────────────────────
  // 每個可點擊 widget 必須有 4 狀態：
  //
  //   default  →  標準顯示
  //   hover    →  背景色 +6-8% alpha、cursor pointer
  //   pressed  →  背景色 +12% alpha、輕微內縮
  //   disabled →  透明度 0.4、文字 textTertiary
  //
  // 互動反饋時間：150ms（快）— 200ms（標準）— 300ms（強調）
  //
  // ───────────────────────────────────────────────────────────────
  // 📏 五、间距（Spacing）
  // ───────────────────────────────────────────────────────────────
  // 8px 基準，僅允許 8 / 16 / 24 / 32 / 48 五級。
  // 特殊：4 = 微型間距（icon 跟 label 中間），2 = 內嵌極緊。
  // 不要用 6, 10, 12, 14, 18, 20, 22, 26, 28 等中間值。
  //
  // ───────────────────────────────────────────────────────────────
  // 🔘 六、圓角（Rounding）
  // ───────────────────────────────────────────────────────────────
  //  0  roundSharp       技術標籤、狀態 badge
  //  4  roundSubtle      tag chip
  //  8  roundStandard    輸入框、小卡片
  // 12  roundComfortable 標準卡片、button
  // 16  roundWide        大卡片、modal
  // 20  roundExtra       展開面板、drawer
  // 50  roundPill        pill button、tab
  // ∞  roundCircle      圓形頭像、icon button
  //
  // ───────────────────────────────────────────────────────────────
  // ☢️ 七、檢查清單（每次新增 UI 必跑）
  // ───────────────────────────────────────────────────────────────
  // [ ] 文字用 token（display/headingL/.../button/caption/small）
  // [ ] icon 用 token（iconHero/iconXL/.../iconXs）
  // [ ] 顏色用 BridgeDSColors.of(context)
  // [ ] 間距用 spaceSM/MD/LG/XL/XXL
  // [ ] 圓角用 roundStandard/... 等 token
  // [ ] 互動 widget 有 4 狀態
  // [ ] 沒有魔術數字（無 11, 13, 15, 17 等混亂值）
  //
  // ════════════════════════════════════════════════════════════════════

  // ════════════════════════════════════════════════════════════════════
  // Icon Size（6 級—— 對應上面的指導原則）
  // ════════════════════════════════════════════════════════════════════

  static const double iconHero = 24;  // 標題區 icon、頁面級 icon
  static const double iconXL = 20;    // 主動作按鈕
  static const double iconLg = 18;    // 工具列、side menu
  static const double iconMd = 16;    // ⭐ 預設按鈕、行內 icon
  static const double iconSm = 14;    // 標籤內 icon
  static const double iconXs = 12;    // 內嵌標記、狀態點

  // 對齊字級的 icon 標準（給「icon + text」並排時用）
  static const double iconMatchBody = 16;     // 配 body (16)
  static const double iconMatchSmall = 14;   // 配 small (12-14)
  static const double iconMatchTitle = 18;   // 配 headingS (20)

  // ════════════════════════════════════════════════════════════════════
  // Interactive State Tokens（互動狀態 alpha 值）
  // ════════════════════════════════════════════════════════════════════

  // Hover 背景 — 從 base color 疊加
  static const double hoverOverlay = 0.06;    // 6%
  static const double pressedOverlay = 0.12; // 12%
  static const double selectedOverlay = 0.10; // 10%
  static const double disabledOpacity = 0.4;  // 40%

  // 反饋時間（毫秒）
  static const int feedbackFast = 150;        // hover
  static const int feedbackStandard = 200;    // 切換
  static const int feedbackEmphasized = 300;  // 開關、modal

  // ════════════════════════════════════════════════════════════════════
  // 最小可點擊區（macOS HIG：44pt）
  // ════════════════════════════════════════════════════════════════════

  static const double tapTargetMin = 44;  // 44pt 最小可點擊區
  static const double tapTargetComfortable = 36; // 36pt 舒適

  // ════════════════════════════════════════════════════════════════════
  // Rounding (混合系統)
  // ════════════════════════════════════════════════════════════════════

  static const double roundSharp = 0;       // xAI — 技術標籤
  static const double roundSubtle = 4;      // badge
  static const double roundStandard = 8;    // 輸入框
  static const double roundComfortable = 12;// 標準卡片
  static const double roundWide = 16;       // 大卡片
  static const double roundExtra = 20;      // 展開面板
  static const double roundPill = 50;       // 按鈕、tab
  static const double roundCircle = 999;    // 圓形圖示

  // ═══════════════════════════════════════════════════
  // Spacing (8px 基準)
  // ═══════════════════════════════════════════════════

  static const double spaceSM = 8;
  static const double spaceMD = 16;
  static const double spaceLG = 24;
  static const double spaceXL = 32;
  static const double spaceXXL = 48;

  // ═══════════════════════════════════════════════════
  // Shadows (Raycast 雙環 + Stripe 藍調)
  // ═══════════════════════════════════════════════════

  // Raycast 雙環陰影 — 卡片、面板
  static List<BoxShadow> get ringShadow => [
    BoxShadow(
      color: const Color(0xFF1B1C1E).withValues(alpha: 1),
      blurRadius: 0,
      spreadRadius: 1,
    ),
    BoxShadow(
      color: const Color(0xFF07080A).withValues(alpha: 0.5),
      blurRadius: 0,
      spreadRadius: 1,
      offset: const Offset(0, 0),
    ),
  ];

  // Level 1 — 微弱浮起
  static List<BoxShadow> get level1 => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.28),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
  ];

  // Floating — 浮動面板
  static List<BoxShadow> get floating => [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.5),
      blurRadius: 0,
      spreadRadius: 2,
    ),
    BoxShadow(
      color: const Color(0xFFFFFFFF).withValues(alpha: 0.19),
      blurRadius: 14,
    ),
  ];

  // Stripe 藍調陰影 — 大腦/數據可視化
  static List<BoxShadow> get dataElevated => [
    BoxShadow(
      color: const Color(0xFF32325D).withValues(alpha: 0.25),
      blurRadius: 45,
      offset: const Offset(0, 30),
    ),
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.1),
      blurRadius: 36,
      offset: const Offset(0, 18),
    ),
  ];

  // 紫光暈 — 粒子節點
  static List<BoxShadow> get glowPurple => [
    BoxShadow(
      color: const Color(0xFF533AFD).withValues(alpha: 0.15),
      blurRadius: 20,
      spreadRadius: 5,
    ),
  ];

  // 藍光暈
  static List<BoxShadow> get glowBlue => [
    BoxShadow(
      color: const Color(0xFF55B3FF).withValues(alpha: 0.15),
      blurRadius: 20,
      spreadRadius: 5,
    ),
  ];

  // ═══════════════════════════════════════════════════
  // Motion (Figma 活潑 + Miro 無限畫布)
  // ═══════════════════════════════════════════════════

  // ease-out-expo — 畫布平移
  static const Curve transitionCanvas = Curves.easeOutExpo;

  // ease-out-back — 形狀變形
  static const Curve transitionMorph = Cubic(0.34, 1.56, 0.64, 1);

  // ease-out-quad — 面板滑入
  static const Curve transitionSlide = Curves.easeOutQuad;

  // Spring — 按鈕回饋
  static final Curve transitionSpring = _SpringCurve(
    mass: 1,
    stiffness: 280,
    damping: 24,
  );

  // Duration
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 300);
  static const Duration durationSlow = Duration(milliseconds: 500);
  static const Duration durationCanvas = Duration(milliseconds: 600);

  // ═══════════════════════════════════════════════════
  // Type Scale 層級表（嚴格使用規範）
  //
  // 層級金字塔（大到小）：
  //   L1 Display    48px w300  — 僅用於全頁標題、配對碼等 hero 級展示
  //   L2 Heading-L  32px w400  — 區域主標題（如「桌面控制台」）
  //   L3 Heading-M  24px w500  — 卡片標題、面板標題
  //   L4 Heading-S  20px w500  — 小標題、分區標題
  //   L5 Body-L     18px w400  — 大段描述文字（少用）
  //   L6 Body       16px w500  — 一般內容文字（baseline）
  //   L7 Body-Tight 16px w400  — 表格行、緊湊內容
  //   L8 Caption    14px w500  — 輔助說明、按鈕內附文字
  //   L9 Small      12px w600  — 數據值、metadata
  //   L10 Label     12px w500  — mono uppercase 標籤、分類名
  //   L11 Code      14px w500  — mono 技術值、log、endpoint
  //   L12 Button    14px w500  — mono uppercase 按鈕文字
  //
  // 鐵則：
  // - 數值/技術值（port, endpoint, timestamp）一律用 L9 Small 或 L11 Code
  // - 卡片標題用 L3 Heading-M，不用 L2
  // - Sidebar 項目用 L8 Caption
  // - 分類標籤用 L10 Label（mono uppercase）
  // - 正文不用 L5 Body-L（太大），用 L6 Body
  // ═══════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════
  // Layout 常數
  // ═══════════════════════════════════════════════════

  static const double sidebarWidth = 240;
  static const double contextPanelWidth = 320;
  static const double topBarHeight = 64;
  static const double statusBarHeight = 32;

  // ═══════════════════════════════════════════════════
  // ThemeData (桌面暗色主題)
  // ═══════════════════════════════════════════════════

  /// [教練 Agent 2026-08-04] 從任意 BridgeDSColors 構造 ThemeData
  /// 用於 ThemePack 主題包動態切換（支援社群主題）
  // [教練 Agent 2026-08-04] Phase E+ v1.1：支援 typography scale
  static ThemeData themeFrom(
    BridgeDSColors colors, {
    double textScale = 1.0,
    TierTheme? tierTheme, // [教練 Agent 2026-08-05] Step 3c — 傳入 tier manifest
  }) {
    final isDark = colors == BridgeDSColors.dark ||
        _isApproximatelyDark(colors.canvas);
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final invertedBg = isDark ? Colors.white : Colors.black;

    // 套用 scale（最小字 14）
    double s(double original) {
      final scaled = original * textScale;
      return scaled < 14.0 ? 14.0 : scaled;
    }

    TextStyle st(TextStyle base) =>
        base.copyWith(fontSize: s(base.fontSize ?? 14.0));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontBody,
      fontFamilyFallback: fontFallback,
      scaffoldBackgroundColor: colors.canvas,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.accentBlue,
        onPrimary: colors.canvas,
        secondary: colors.accentPurple,
        onSecondary: colors.surface,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        error: colors.accentRed,
        onError: colors.canvas,
      ),
      textTheme: TextTheme(
        displayLarge: st(display).copyWith(color: colors.textPrimary),
        displayMedium: st(headingL).copyWith(color: colors.textPrimary),
        headlineMedium: st(headingM).copyWith(color: colors.textPrimary),
        headlineSmall: st(headingS).copyWith(color: colors.textPrimary),
        bodyLarge: st(bodyL).copyWith(color: colors.textPrimary),
        bodyMedium: st(body).copyWith(color: colors.textPrimary),
        bodySmall: st(small).copyWith(color: colors.textSecondary),
        labelLarge: st(button).copyWith(color: colors.textPrimary),
        labelSmall: st(labelMono).copyWith(color: colors.textSecondary),
      ),
      // [2026-08-27 共視修復] AlertDialog 字級統一——
      // Material3 預設偏大（title 24/content 14 但 padding 太鬆）；
      // 對齊 tier 規範：title 用 headingS（19）、content 用 body（14）。
      // 緊湊 padding（24/20/16）取代預設 40+40，讓對話框不再搶版面。
      // [v208 Blue 抓包 2026-09-02] SnackBar 爆大字修復——
      // SnackBar 不吃 dialogTheme，字級落到 Material 預設 display 級
      // （*1.8 TypographyScale 後 = 50-60px 巨字）且背景白色沒主題化。
      // 修：明確 snackBarTheme——字 14px*scale、深色底、緊湊高度。
      // [v209 Blue 指定 2026-09-02] SnackBar——從底部浮上來的感覺（fixed）
      // + 字級 14 同 GATEWAY RUNNING 狀態列。
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: st(body).copyWith(color: colors.textPrimary, fontSize: 14),
        backgroundColor: colors.surfaceElevated,
        behavior: SnackBarBehavior.fixed,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceElevated,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        titleTextStyle: headingS.copyWith(color: colors.textPrimary),
        contentTextStyle: body.copyWith(color: colors.textPrimary),
      ),
      // [v208b Blue 抓包] 彈出類元件全面統一深色——
      // PopupMenu（下拉選單）跟 Tooltip 之前沒主題=白色突兀塊。
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
          side: BorderSide(color: colors.borderDefault),
        ),
        // [小葵 2026-09-09 Blue 抓包] 選單選項字原本吃 body(16)——
        // 比其他元件大一級。對齊 button(14)：搜尋模式四選項等。
        textStyle: button.copyWith(
            color: colors.textPrimary, fontWeight: FontWeight.w500),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          border: Border.all(color: colors.borderDefault),
        ),
        textStyle: small.copyWith(color: colors.textPrimary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.canvas,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: headingS.copyWith(color: colors.textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: invertedBg,
          foregroundColor: colors.canvas,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundPill),
          ),
          textStyle: button.copyWith(color: colors.canvas),
        ),
      ),
      // [小葵 2026-09-01 Blue 定案] FilledButton 全域歸範——
      // 黑底＋紫框＋白字（教學按鈕/素材池按鈕已定案的視覺語言）。
      // 舊：Material3 預設 primary 實心藍底——突兀、搶版面。
      // 此後所有 FilledButton 不帶自訂 style 都自動走這套，
      // 個別 hardcode backgroundColor 者另行清理。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.canvas,
          foregroundColor: colors.textPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roundStandard),
            side: BorderSide(color: colors.accentPurple, width: 1.5),
          ),
          textStyle: button.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // [小葵 2026-09-09 Blue 抓包] OutlinedButton 歸範——
      // 「加入素材池」按鈕字比旁邊「關閉」大一截的元兇：
      // themeFrom 漏了 outlinedButtonTheme，吃到 M3 預設 labelLarge
      // 還被 textScale 放大。統一 14（同 TextButton/FilledButton）。
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          minimumSize: const Size(40, 36),
          textStyle: button.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // [小葵 2026-09-09 Blue 抓包] ListTile/SwitchListTile——用預設
      // titleLarge(16)/bodyMedium 的列（語音設定等）對齊 14/12
      listTileTheme: ListTileThemeData(
        titleTextStyle: body.copyWith(
            color: colors.textPrimary, fontWeight: FontWeight.w500),
        subtitleTextStyle: small.copyWith(color: colors.textSecondary),
      ),
      // [小葵 2026-09-01] TextButton 次要動作——亮字不搶戲
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.textSecondary,
          textStyle: button.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(roundStandard),
          borderSide: BorderSide(color: colors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(roundStandard),
          borderSide: BorderSide(color: colors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(roundStandard),
          borderSide: BorderSide(color: colors.accentBlue, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        // [教練 Agent 2026-08-05 Step 3b] 用 colors.textPrimary 動態查（跟主題聯動）
        // light theme 近黑、dark theme 近白 — 不寫死黑色避免 dark theme 黑底黑字
        labelStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        floatingLabelStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        hintStyle: TextStyle(color: colors.textPrimary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(roundComfortable),
        ),
      ),
      extensions: tierTheme != null ? <ThemeExtension<dynamic>>[colors, tierTheme] : [colors],
    );
  }

  static bool _isApproximatelyDark(Color c) {
    final l = c.computeLuminance();
    return l < 0.5;
  }

  static ThemeData get darkTheme => themeFrom(BridgeDSColors.dark);

  // ═══════════════════════════════════════════════════
  // ThemeData (桌面淺色主題)
  // ═══════════════════════════════════════════════════

  static ThemeData get lightTheme => themeFrom(BridgeDSColors.light);

  // [教練 Agent 2026-08-04] Typography scale 整合
  /// 把所有字體 token 套用 TypographyScaleProvider.scale
  /// 並確保不會小於 14（使用者 規定）
  static _ScaledBridgeDS scaled(BuildContext context) =>
      _ScaledBridgeDS(TypographyScaleProvider.instance.scale);
}

// [教練 Agent 2026-08-04] 套用 scale 後的字體 token
// 用法：BridgeDS.scaled(context).bodyL (取代 BridgeDS.bodyL)
class _ScaledBridgeDS {
  _ScaledBridgeDS(this._scale);
  final double _scale;
  static const double _minFontSize = 14.0;

  double _apply(double original) {
    final scaled = original * _scale;
    return scaled < _minFontSize ? _minFontSize : scaled;
  }

  TextStyle _applyStyle(TextStyle base) {
    final newSize = _apply(base.fontSize ?? _minFontSize);
    return base.copyWith(fontSize: newSize);
  }

  TextStyle get display => _applyStyle(BridgeDS.display);
  TextStyle get headingL => _applyStyle(BridgeDS.headingL);
  TextStyle get headingM => _applyStyle(BridgeDS.headingM);
  TextStyle get headingS => _applyStyle(BridgeDS.headingS);
  TextStyle get bodyL => _applyStyle(BridgeDS.bodyL);
  TextStyle get body => _applyStyle(BridgeDS.body);
  TextStyle get bodyTight => _applyStyle(BridgeDS.bodyTight);
  TextStyle get button => _applyStyle(BridgeDS.button);
  TextStyle get labelMono => _applyStyle(BridgeDS.labelMono);
  TextStyle get caption => _applyStyle(BridgeDS.caption);
  TextStyle get small => _applyStyle(BridgeDS.small);
}

/// 自定義 Spring Curve（模擬 Figma spring 參數）
class _SpringCurve extends Curve {
  final double mass;
  final double stiffness;
  final double damping;

  const _SpringCurve({
    required this.mass,
    required this.stiffness,
    required this.damping,
  });

  @override
  double transformInternal(double t) {
    // 簡化 spring 模擬：欠阻尼振盪衰減
    final omega0 = (stiffness / mass).abs() <= 0
        ? 0.0
        : (stiffness / mass).abs();
    final zeta = omega0 <= 0 ? 1.0 : damping / (2 * omega0 * mass);
    if (zeta >= 1.0) {
      // 過阻尼 — 緩慢趨近
      return 1 - (1 - t).abs() * (1 - t).abs();
    }
    final wd = omega0 * (1 - zeta * zeta).abs();
    // 欠阻尼振盪
    final envelope = (1 - zeta * t).abs();
    final oscillation = math.cos(t * wd);
    return 1 - envelope * oscillation.abs();
  }
}
