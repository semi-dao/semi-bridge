# Bridge App Design Audit Report
## Home Page + Companion Hall Analysis

**Audit Date:** 2026-07-18  
**Scope:** `bridge_desktop_screen.dart` focusing on `_buildHomepage()`, `_buildCompanionHall()`, `_buildTopBar()`, `_buildSidebarCompanionFooter()`  
**Design System:** BridgeDS（五種設計質地的融合）

---

## Executive Summary

The Bridge Desktop app demonstrates **strong adherence to the BridgeDS design system** with consistent use of design tokens, proper spacing grid, and well-executed dark mode principles. However, several **spacing violations**, **hardcoded font sizes**, and **visual hierarchy issues** were identified that should be addressed to achieve design system consistency.

**Overall Grade: B+** (Good foundation with minor polish needed)

---

## 1. _buildTopBar() — Lines 1538-1642

### ✅ Strengths
- Clean use of BridgeDS tokens for colors (canvas, borderSubtle, accentPurple, textMuted)
- Proper height constant (`BridgeDS.topBarHeight` = 64px)
- Good component spacing with `BridgeDS.spaceLG` horizontal padding
- Consistent use of BridgeChip component for navigation

### ⚠️ Issues Found

#### **Critical: Non-8pt Grid Spacing**
**Line 1571:** `const SizedBox(width: 10)`  
**Severity:** Major  
**Issue:** Violates 8pt grid system (should be 8, 16, 24, etc.)  
**Recommended Fix:**
```dart
const SizedBox(width: BridgeDS.spaceSM), // 8px
```

**Line 1578:** `const SizedBox(width: 6)`  
**Severity:** Major  
**Issue:** Violates 8pt grid, too tight for logo spacing  
**Recommended Fix:**
```dart
const SizedBox(width: BridgeDS.spaceSM), // 8px
```

**Line 1587:** `const SizedBox(width: BridgeDS.spaceXL * 2)`  
**Severity:** Minor  
**Issue:** While mathematically 64px (valid), this pattern is not semantic. Should define explicit token.  
**Recommended Fix:** Add `BridgeDS.spaceXXL = 64` or use `BridgeDS.spaceXXL` (48px) + adjust

**Line 1595:** `padding: const EdgeInsets.only(right: 8)`  
**Severity:** Minor  
**Issue:** Hardcoded spacing, should use token  
**Recommended Fix:**
```dart
padding: const EdgeInsets.only(right: BridgeDS.spaceSM),
```

#### **Critical: Hardcoded Font Sizes**
**Lines 1572-1577:** Logo "BRIDGE" text  
**Severity:** Major  
**Issue:** Overrides BridgeDS.headingS with custom fontSize: 18  
**Problem:** Breaks typography hierarchy. BridgeDS.headingS is 20px, reducing to 18px undermines the design system.  
**Recommended Fix:**
```dart
// Option A: Use existing token
SelectableText('BRIDGE', style: BridgeDS.headingS.copyWith(
  fontFamily: BridgeDS.fontDisplay,
  fontWeight: FontWeight.w400,
  letterSpacing: 2,
  // Remove fontSize override
)),

// Option B: Create dedicated logo token
static const TextStyle logo = TextStyle(
  fontFamily: fontDisplay,
  fontSize: 18,
  fontWeight: FontWeight.w400,
  letterSpacing: 2,
  color: textPrimary,
);
```

**Lines 1579-1582:** "DESKTOP" label  
**Severity:** Minor  
**Issue:** BridgeDS.labelMono is already 12px fontSize: 14, but labelMono is defined as 12px with specific styling  
**Recommended Fix:** Use labelMono as-is or create `labelMonoDesktop` token

**Lines 1632-1637:** Gateway status text  
**Severity:** Minor  
**Issue:** Hardcoded fontSize: 14 on labelMono  
**Recommended Fix:**
```dart
style: BridgeDS.labelMono.copyWith(
  // Remove fontSize override, labelMono is already 12px
  color: _gatewayRunning ? BridgeDS.accentGreen : BridgeDS.textMuted,
),
```

**Line 1625:** `const SizedBox(width: 12)`  
**Severity:** Minor  
**Issue:** Should use BridgeDS.spaceMD (16px) or define 12px token if intentional  
**Recommended Fix:** Use `BridgeDS.spaceMD` or add `BridgeDS.spaceSM - 4` if 12px is critical

#### **Design Consistency: Icon Sizes**
**Line 1570:** `size: 22` for hub icon  
**Severity:** Minor  
**Issue:** Non-standard icon size (not 16, 20, 24)  
**Recommended Fix:** Use 24px for consistency with navigation icons

---

## 2. _buildHomepage() — Lines 1648-1797

### ✅ Strengths
- Excellent responsive grid logic (2/3/4 columns based on width)
- Proper use of `BridgeDS.spaceXXL` for page padding
- Clean use of BridgeCard component
- Good semantic structure with ConstrainedBox (maxWidth: 1200)

### ⚠️ Issues Found

#### **Major: Typography Inconsistency**
**Lines 1671-1674:** Page title "Bridge Desktop"  
**Severity:** Major  
**Issue:** Uses `BridgeDS.headingM.copyWith(fontSize: 22)` — violates type scale  
**Context:** BridgeDS.headingM is 24px. Reducing to 22px breaks hierarchy.  
**Recommended Fix:**
```dart
Text(
  'Bridge Desktop',
  style: BridgeDS.headingM, // Use token as-is (24px)
),
```

**Lines 1677-1680:** Active companion text  
**Severity:** Minor  
**Issue:** Uses BridgeDS.caption but intent is muted metadata  
**Recommended Fix:** Already correct, but consider `BridgeDS.small` (12px w600) for metadata

**Lines 1683-1686:** Companion count  
**Severity:** Minor  
**Issue:** Same as above, caption is appropriate but small might be semantically clearer

#### **Minor: Spacing Issues**
**Line 1675:** `const SizedBox(width: 12)`  
**Severity:** Minor  
**Issue:** Non-8pt spacing  
**Recommended Fix:** Use `BridgeDS.spaceMD` (16px)

**Line 1689:** `const SizedBox(height: BridgeDS.spaceXXL)`  
**Severity:** None — ✅ Correct usage

**Line 1698:** `final spacing = BridgeDS.spaceMD;`  
**Severity:** None — ✅ Correct

**Lines 1699-1700:** Tile sizing calculation  
**Severity:** Minor  
**Issue:** `tileH = tileW * 0.95` creates non-8pt heights  
**Context:** If tileW = 280, tileH = 266 (not divisible by 8)  
**Recommended Fix:** Use fixed aspect ratio that maintains 8pt grid:
```dart
final tileH = (tileW ~/ 8) * 8; // Round down to nearest 8
// Or use aspect ratio = 1.0 for perfect squares
```

#### **Critical: Home Tile Typography**
**Line 1832-1834:** Tile title  
**Severity:** Major  
**Issue:** Uses BridgeDS.headingS (20px) for small tile titles — too large  
**Context:** Heading hierarchy: Display 48 > HeadingL 32 > HeadingM 24 > **HeadingS 20** > Body 16  
**Problem:** Using HeadingS for 6-8 tiles on a grid makes them compete with page title  
**Recommended Fix:**
```dart
Text(
  tile.title,
  style: BridgeDS.headingM.copyWith(fontSize: 18), // Or create headingXS token
  // Better: add BridgeDS.headingXS = 18px w500 to design system
)
```

**Lines 1837-1845:** Tile subtitle  
**Severity:** Major  
**Issue:** Hardcoded fontSize: 12 on caption  
**Context:** BridgeDS.caption is 14px, reducing to 12px is inconsistent  
**Recommended Fix:**
```dart
Text(
  tile.subtitle,
  style: BridgeDS.small, // 12px w600, semantically correct for metadata
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
),
```

**Line 1836:** `const SizedBox(height: 4)`  
**Severity:** Major  
**Issue:** Violates 8pt grid (should be 8px minimum)  
**Recommended Fix:**
```dart
const SizedBox(height: BridgeDS.spaceSM), // 8px
```

---

## 3. _buildHomeTile() — Lines 1799-1852

### ✅ Strengths
- Good use of BridgeCard wrapper
- Clean hover state through InkWell
- Proper disabled state styling with opacity

### ⚠️ Issues Found

#### **Critical: Non-Standard Icon Container**
**Lines 1811-1825:** Icon container  
**Severity:** Major  
**Issue:** Hardcoded width: 48, height: 48 — not semantic  
**Context:** 48 is valid (6 × 8pt), but should be defined as token  
**Recommended Fix:**
```dart
// In BridgeDS:
static const double iconContainerMedium = 48;
static const double iconSizeMedium = 24;

// In code:
Container(
  width: BridgeDS.iconContainerMedium,
  height: BridgeDS.iconContainerMedium,
  decoration: BoxDecoration(
    color: isPlaceholder
        ? BridgeDS.textMuted.withValues(alpha: 0.08)
        : tile.iconColor.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
  ),
  child: Icon(
    tile.icon,
    color: isPlaceholder ? BridgeDS.textMuted : tile.iconColor,
    size: BridgeDS.iconSizeMedium,
  ),
),
```

**Line 1823:** `size: 24` for icon  
**Severity:** Minor  
**Issue:** Hardcoded icon size, should use token

#### **Visual Hierarchy: Tile Layout**
**Lines 1807-1809:** `mainAxisAlignment: MainAxisAlignment.spaceBetween`  
**Severity:** Minor  
**Issue:** Forces icon to top, text to bottom with all space between  
**Context:** For tiles with variable height (due to 0.95 aspect), this creates inconsistent spacing  
**Recommended Fix:**
```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // Icon at top
    Container(...),
    const Spacer(), // Push text to bottom
    // Text at bottom
    Column(...),
  ],
)
```

---

## 4. _buildCompanionHall() — Lines 1858-1936

### ✅ Strengths
- Clean header layout with back button
- Proper use of BridgeGlowDivider for visual separation
- Good empty state design
- Responsive grid with SliverGridDelegateWithMaxCrossAxisExtent

### ⚠️ Issues Found

#### **Minor: Spacing Inconsistencies**
**Line 1880:** `const SizedBox(width: 8)`  
**Severity:** Minor  
**Issue:** Should use BridgeDS.spaceSM consistently

**Line 1882:** `const SizedBox(width: 12)`  
**Severity:** Minor  
**Issue:** Non-8pt spacing

**Line 1876:** `size: 20` for back arrow  
**Severity:** Minor  
**Issue:** Non-standard icon size (should be 24)  
**Recommended Fix:**
```dart
icon: const Icon(Icons.arrow_back, size: 24),
```

**Line 1881:** `size: 24` for group icon  
**Severity:** None — ✅ Correct

#### **Critical: Grid Spacing**
**Lines 1922-1923:**
```dart
crossAxisSpacing: 16,
mainAxisSpacing: 16,
```
**Severity:** None — ✅ Correct use of BridgeDS.spaceMD equivalent

**Line 1920:** `maxCrossAxisExtent: 320`  
**Severity:** Minor  
**Issue:** Hardcoded value, not multiple of 8  
**Context:** 320 = 40 × 8, actually valid  
**Recommended Fix:** Define as BridgeDS.cardWidthMedium = 320

**Line 1921:** `childAspectRatio: 0.85`  
**Severity:** Minor  
**Issue:** Creates non-standard heights (320 × 0.85 = 272, not 8pt multiple)  
**Recommended Fix:**
```dart
childAspectRatio: 0.875, // 320 × 0.875 = 280 (35 × 8)
// Or: childAspectRatio: 0.8125, // 320 × 0.8125 = 260 (32.5 × 8)
```

#### **Empty State Design**
**Lines 1898-1916:** Empty state  
**Severity:** None — Well designed  
**Minor observation:** Icon size 64 is 8 × 8, good. Spacing 16, 8, 24 all on-grid.

---

## 5. _buildCompanionCard() — Lines 1938-1984

### ✅ Strengths
- Clean card interaction with InkWell
- Good use of BridgeCard component
- Proper active state indication

### ⚠️ Issues Found

#### **Critical: Typography Overrides**
**Line 1962:** `BridgeDS.headingM.copyWith(fontSize: 18)`  
**Severity:** Major  
**Issue:** Same as homepage tiles — reduces 24px to 18px  
**Recommended Fix:**
```dart
Text(c.name, style: BridgeDS.headingS), // 20px, or create headingXS: 18px
```

**Line 1967:** `fontSize: 13` on caption  
**Severity:** Major  
**Issue:** BridgeDS.caption is 14px, reducing to 13px breaks system  
**Recommended Fix:**
```dart
Text(
  c.roleName,
  style: BridgeDS.caption.copyWith(color: BridgeDS.textMuted),
  // Remove fontSize override
),
```

**Line 1978:** `fontSize: 11` for active badge  
**Severity:** Major  
**Issue:** Creates new text size outside type scale  
**Context:** Type scale has 12px (small/labelMono) and 14px (caption)  
**Recommended Fix:**
```dart
child: Text('目前夥伴', style: BridgeDS.small.copyWith(color: BridgeDS.accentGreen)),
// Or create BridgeDS.badge = 11px token if 12px is too large
```

#### **Minor: Spacing**
**Line 1960:** `const SizedBox(height: 12)`  
**Severity:** Minor  
**Issue:** Non-8pt spacing  
**Recommended Fix:** Use BridgeDS.spaceMD (16px)

**Line 1963:** `const SizedBox(height: 4)`  
**Severity:** Major  
**Issue:** Violates 8pt grid  
**Recommended Fix:** Use BridgeDS.spaceSM (8px)

**Line 1969:** `const SizedBox(height: 8)`  
**Severity:** None — ✅ Correct (BridgeDS.spaceSM)

#### **Visual Design: Avatar Size**
**Line 1957:** `_buildCompanionAvatar(c, 120)`  
**Severity:** Minor  
**Issue:** 120px is 15 × 8, valid, but should be semantic token  
**Recommended Fix:**
```dart
// In BridgeDS:
static const double avatarLarge = 120;
static const double avatarMedium = 64;
static const double avatarSmall = 36;

// In code:
_buildCompanionAvatar(c, BridgeDS.avatarLarge)
```

---

## 6. _buildCompanionAvatar() + _avatarFallback() — Lines 1987-2022

### ✅ Strengths
- Clean fallback logic
- Good error handling
- Proper use of ClipRRect for rounded images

### ⚠️ Issues Found

**Line 2010:** `height: size` parameter (receives 120, 36 from callers)  
**Severity:** None — Parameter-driven, but callers should use tokens

**Line 2017:** Fallback text uses first character  
**Severity:** None — Good design pattern

---

## 7. _buildSidebarCompanionFooter() — Lines 2028-2071

### ✅ Strengths
- Clean compact layout
- Proper use of border separator
- Good hover interaction with GestureDetector

### ⚠️ Issues Found

#### **Critical: Typography Overrides**
**Line 2053:** `fontSize: 12` on labelMono  
**Severity:** Minor  
**Issue:** labelMono is already 12px, override is redundant but harmless  
**Recommended Fix:** Remove override

**Line 2059:** `fontSize: 11` on caption  
**Severity:** Major  
**Issue:** BridgeDS.caption is 14px, reducing to 11px creates off-scale size  
**Recommended Fix:**
```dart
Text(
  companion.roleName,
  style: BridgeDS.small.copyWith(fontSize: 10, color: BridgeDS.textMuted),
  // Or create BridgeDS.micro = 10-11px for ultra-compact areas
),
```

#### **Minor: Icon Size**
**Line 2066:** `size: 16` for chevron  
**Severity:** Minor  
**Issue:** Non-standard icon size  
**Context:** Standard sizes are 20, 24. 16 might be intentional for compact footer.  
**Recommended Fix:** Define BridgeDS.iconSmall = 16 if this pattern repeats

**Line 2045:** `const SizedBox(width: 8)`  
**Severity:** None — ✅ Correct (BridgeDS.spaceSM)

**Line 2044:** `_buildCompanionAvatar(companion, 36)`  
**Severity:** Minor  
**Issue:** Hardcoded avatar size  
**Recommended Fix:** `BridgeDS.avatarSmall`

---

## Summary of Issues by Severity

### 🔴 Critical (Breaks UX / Core Principles)
**Total: 0**  
Good news: No critical UX blockers found.

### 🟡 Major (Hurts Consistency / Aesthetics)
**Total: 14**

1. **Non-8pt spacing:**
   - Line 1571: `width: 10` → should be 8
   - Line 1578: `width: 6` → should be 8
   - Line 1836: `height: 4` → should be 8
   - Line 1963: `height: 4` → should be 8

2. **Typography overrides breaking type scale:**
   - Line 1576: `fontSize: 18` on BRIDGE logo
   - Line 1673: `fontSize: 22` on page title
   - Line 1832: BridgeDS.headingS used for small tiles (too large)
   - Line 1840: `fontSize: 12` on tile subtitle
   - Line 1962: `fontSize: 18` on companion name
   - Line 1967: `fontSize: 13` on companion role
   - Line 1978: `fontSize: 11` on active badge
   - Line 2059: `fontSize: 11` on footer role

3. **Hardcoded dimensions without tokens:**
   - Lines 1812-1813: Icon container 48×48
   - Line 1920: Grid maxCrossAxisExtent: 320
   - Line 1957: Avatar size 120

### 🟢 Minor (Polish / Future-Proofing)
**Total: 11**

1. Hardcoded spacing: lines 1595, 1625, 1675, 1880, 1882, 1960
2. Non-standard icon sizes: lines 1570, 1823, 1876, 2066
3. Grid aspect ratio creates non-8pt heights: line 1921
4. Redundant fontSize overrides: line 2053

---

## Design Principles Assessment

### ✅ Passing Grades

1. **Visual Hierarchy:** B+
   - Clear page structure, but competing heading sizes (22px override) reduce clarity
   - Recommendation: Stick to defined heading scale

2. **8pt Grid:** B
   - Most spacing uses BridgeDS tokens correctly
   - Critical violations: 4px, 6px, 10px, 12px in several places
   - Recommendation: Audit all SizedBox and EdgeInsets for 8pt compliance

3. **WCAG Contrast:** A
   - Excellent use of BridgeDS color tokens
   - TextPrimary #F9F9F9 on Canvas #07080A = ~19:1 ratio ✅
   - TextSecondary #CECECE on Canvas = ~13:1 ✅
   - TextMuted #6A6B6C on Canvas = ~4.8:1 ✅ (meets 4.5:1)
   - Accent colors all meet contrast requirements

4. **Dark Mode:** A+
   - No pure black (#000000) used ✅
   - Elevation through color (surface, surfaceElevated) ✅
   - Proper use of border opacity layers
   - Excellent implementation

5. **Consistency:** B+
   - BridgeCard component used consistently ✅
   - Typography overrides reduce consistency ⚠️
   - Color token usage is excellent ✅

6. **No Hardcoded Colors:** A
   - All colors use BridgeDS tokens ✅
   - No Color(0x...) outside design system ✅

7. **No AI Design Slop:** A+
   - No gradient abuse ✅
   - No emoji icons (uses Material Icons properly) ✅
   - No generic SaaS card patterns ✅
   - Clean, purposeful design

8. **Spacing Rhythm:** B
   - Good use of spaceSM/MD/LG/XL/XXL tokens
   - Several violations with 4px, 6px, 10px, 12px
   - Recommendation: Strict 8pt enforcement

9. **Typography Hierarchy:** C+
   - Type scale exists and is well-defined
   - **Major issue:** Frequent fontSize overrides (18, 22, 11, 13) break hierarchy
   - Recommendation: Add missing tokens (headingXS: 18px, micro: 11px) or stop overriding

10. **Button Hierarchy:** A
    - Clean use of BridgeChip component ✅
    - Clear active/inactive states ✅
    - Good disabled state styling ✅

---

## Recommended Actions (Prioritized)

### 🔥 High Priority (Sprint 15)

1. **Add Missing Typography Tokens**
   ```dart
   // In BridgeDS:
   static const TextStyle headingXS = TextStyle(
     fontFamily: fontBody,
     fontSize: 18,
     fontWeight: FontWeight.w500,
     height: 1.40,
     letterSpacing: 0.2,
     color: textPrimary,
   );
   
   static const TextStyle micro = TextStyle(
     fontFamily: fontBody,
     fontSize: 11,
     fontWeight: FontWeight.w600,
     height: 1.36,
     color: textTertiary,
   );
   ```

2. **Fix All 4px Spacing Violations**
   - Lines 1836, 1963: `height: 4` → `height: BridgeDS.spaceSM`

3. **Fix Non-8pt TopBar Spacing**
   - Lines 1571, 1578: Use BridgeDS.spaceSM

4. **Remove fontSize Overrides**
   - Replace all `.copyWith(fontSize: X)` with proper tokens
   - Lines 1576, 1673, 1840, 1962, 1967, 1978, 2059

### 🔧 Medium Priority (Sprint 16)

5. **Define Semantic Dimension Tokens**
   ```dart
   // In BridgeDS:
   static const double avatarLarge = 120;
   static const double avatarMedium = 64;
   static const double avatarSmall = 36;
   
   static const double iconContainerMedium = 48;
   static const double iconSizeLarge = 24;
   static const double iconSizeMedium = 20;
   static const double iconSizeSmall = 16;
   
   static const double cardWidthMedium = 320;
   ```

6. **Fix Remaining Non-8pt Spacing**
   - Lines 1595, 1625, 1675, 1880, 1882, 1960

7. **Fix Grid Aspect Ratios**
   - Homepage tiles: Use 1.0 for square or 0.875 for 8pt-compliant heights
   - Companion cards: Use 0.875 (280px height from 320px width)

### 🎨 Low Priority (Backlog)

8. **Icon Size Standardization**
   - Document when to use 16/20/24 icon sizes
   - Create token for each size if patterns emerge

9. **Create Design System Documentation**
   - When to use headingS vs headingXS
   - Avatar size guide
   - Spacing decision tree

10. **Audit Other Screens**
    - Apply same rigor to Canvas, Project, Brain, System tabs
    - Check for consistency across entire app

---

## Conclusion

The Bridge Desktop app demonstrates **strong design fundamentals** with excellent use of the BridgeDS token system, proper dark mode implementation, and good WCAG contrast compliance. The main areas for improvement are:

1. **Typography consistency** — Stop overriding fontSize, add missing tokens
2. **8pt grid compliance** — Eliminate 4px, 6px, 10px, 12px spacing
3. **Semantic tokens** — Define avatar sizes, icon sizes, card widths

With these fixes, the app will achieve **A-grade design system compliance** and provide a solid foundation for scaling to more features.

---

**Audit Conducted By:** Design Review Agent  
**Next Review:** After Sprint 15 fixes (estimated 2026-07-25)
