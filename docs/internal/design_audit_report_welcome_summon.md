# Design Audit Report: Welcome + Summon Screens
**Bridge App Desktop · BridgeDS Design System Compliance**  
Generated: 2026-07-18  
Auditor: Hermes Agent (Design Sub-Agent)

---

## Executive Summary

This audit examined **desktop_welcome_screen.dart** (799 lines) and **desktop_summon_screen.dart** (3777 lines) against the BridgeDS design system specification. Both screens implement dark-themed macOS desktop layouts with comprehensive BridgeDS token usage.

**Overall Status:**
- ✅ **Welcome Screen**: Strong adherence to design system (6 issues, mostly minor)
- ⚠️ **Summon Screen**: Good foundation with notable spacing and hierarchy issues (14 issues, 3 critical)

**Critical Issues Found:** 3  
**Major Issues Found:** 6  
**Minor Issues Found:** 11

---

## 1. Desktop Welcome Screen (`desktop_welcome_screen.dart`)

### 1.1 Visual Hierarchy Issues

#### Issue #1: Hero Title Size Off 8pt Grid
**Lines:** 330-335  
**Severity:** Minor  
**Current Code:**
```dart
Text(
  '橋樑',
  style: BridgeDS.display.copyWith(
    fontSize: 64,  // ❌ Not on 8pt grid
    color: BridgeDS.textPrimary,
  ),
),
```
**Problem:** `fontSize: 64` creates 64px title, which doesn't align to 8pt grid (8, 16, 24, 32, 40, 48, 56, **64** is technically on grid, but this is actually correct). **Correction: This is NOT an issue.**

**Recommended Fix:** No change needed.

---

#### Issue #2: Inconsistent Spacing Between Hero Elements
**Lines:** 328, 336, 348  
**Severity:** Minor  
**Current Code:**
```dart
const SizedBox(height: BridgeDS.spaceLG),  // Line 328: 24
Text('橋樑', ...),
const SizedBox(height: BridgeDS.spaceSM),  // Line 336: 8
Text('你的 AI 夥伴住在這裡', ...),
const SizedBox(height: BridgeDS.spaceMD),  // Line 348: 16
Text('設定 AI 服務後...', ...),
```
**Problem:** Spacing progression (24→8→16) lacks clear hierarchy logic. Should follow consistent rhythm (e.g., 24→16→24 or 16→12→16).

**Recommended Fix:**
```dart
const SizedBox(height: BridgeDS.spaceLG),   // 24: dot to title
Text('橋樑', ...),
const SizedBox(height: BridgeDS.spaceMD),   // 16: title to subtitle
Text('你的 AI 夥伴住在這裡', ...),
const SizedBox(height: BridgeDS.spaceLG),   // 24: subtitle to body
Text('設定 AI 服務後...', ...),
```

---

### 1.2 Input Field Design

#### Issue #3: TextField Border Radius Inconsistency
**Lines:** 521-530, 549-558  
**Severity:** Minor  
**Current Code:**
```dart
border: OutlineInputBorder(
  borderRadius: BorderRadius.circular(BridgeDS.roundComfortable), // 12
  borderSide: BorderSide(color: BridgeDS.borderSubtle),
),
```
**Problem:** Uses `roundComfortable` (12) for input fields, but step cards use `roundWide` (16). Input fields should typically use `roundStandard` (8) or `roundComfortable` (12) for tighter form density.

**Recommended Fix:** **Current implementation is acceptable** — 12px is appropriate for desktop input fields. No change needed unless design system specifies `roundStandard` for all inputs.

---

#### Issue #4: Insufficient Label-to-Field Contrast
**Lines:** 516-517, 544-545  
**Severity:** Minor  
**Current Code:**
```dart
labelText: 'API URL',
labelStyle: BridgeDS.small.copyWith(color: BridgeDS.textMuted),
```
**Problem:** `textMuted` may not provide sufficient contrast on `canvas` background (#07080A). Should verify WCAG AA contrast ratio ≥ 4.5:1.

**Recommended Fix:**
```dart
labelStyle: BridgeDS.small.copyWith(color: BridgeDS.textSecondary), // Better contrast
```

---

### 1.3 Button & Interactive States

#### Issue #5: Lock Icon Size Not on 8pt Grid
**Lines:** 600, 784  
**Severity:** Minor  
**Current Code:**
```dart
Icon(Icons.lock, color: BridgeDS.accentGreen, size: 16), // Line 600 ✅ OK
Icon(Icons.lock, size: 12, color: BridgeDS.accentGreen), // Line 784 ❌ 12 not ideal
```
**Problem:** Line 784 uses `size: 12` which is technically on 4pt grid but creates tiny icon that may be hard to see on dark background.

**Recommended Fix:**
```dart
Icon(Icons.lock, size: 16, color: BridgeDS.accentGreen), // Consistent 16px
```

---

#### Issue #6: Provider Chip Padding Off Grid
**Lines:** 768  
**Severity:** Minor  
**Current Code:**
```dart
padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
```
**Problem:** `horizontal: 14` is not on 8pt grid (should be 12 or 16).

**Recommended Fix:**
```dart
padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Align to 8pt grid
```

---

### 1.4 Typography

✅ **No Issues Found**  
- Display, headings, body, caption, and code styles correctly use BridgeDS tokens
- Font weights and color hierarchy follow design system

---

### 1.5 Color & Theme

✅ **No Issues Found**  
- All colors reference BridgeDS tokens (canvas, surface, surfaceElevated, accentBlue, etc.)
- No hardcoded color values detected
- Dark mode consistency maintained throughout

---

## 2. Desktop Summon Screen (`desktop_summon_screen.dart`)

### 2.1 Critical Issues

#### Issue #7: Hardcoded White Text in Placeholder Preview
**Lines:** 622-633, 649-654, 658-660  
**Severity:** **CRITICAL**  
**Current Code:**
```dart
Text(
  '形象預覽',
  style: TextStyle(
    color: Colors.white,  // ❌ Hardcoded color
    fontSize: 18,
    fontWeight: FontWeight.w900,
  ),
),
// ...
Text(
  previewName,
  style: const TextStyle(
    color: Colors.white,  // ❌ Hardcoded color
    fontSize: 26,
    fontWeight: FontWeight.w900,
  ),
),
```
**Problem:** Multiple hardcoded `Colors.white` and `Colors.white70` break dark theme consistency. These sit on gradient backgrounds but should still use semantic tokens.

**Recommended Fix:**
```dart
Text(
  '形象預覽',
  style: BridgeDS.headingS.copyWith(
    color: BridgeDS.textPrimary, // On gradient, textPrimary (#F9F9F9) works
    fontWeight: FontWeight.w900,
  ),
),
Text(
  previewName,
  style: BridgeDS.headingL.copyWith(
    color: BridgeDS.textPrimary,
    fontWeight: FontWeight.w900,
  ),
),
Text(
  '等待線索凝聚',
  style: BridgeDS.small.copyWith(color: BridgeDS.textSecondary),
),
```

---

#### Issue #8: Inline Text Sizes Not Using Typography Scale
**Lines:** 570-575, 816, 861-864, 942-956  
**Severity:** **CRITICAL**  
**Current Code:**
```dart
Text(
  '正在生成主形象，請保持螢幕開啟。\n不要讓電腦休眠或切換應用程式，以免中斷。',
  style: TextStyle(
    fontSize: 12,  // ❌ Hardcoded size
    color: Colors.orange,  // ❌ Hardcoded color
    height: 1.3,
    fontWeight: FontWeight.w600
  ),
),
```
**Problem:** Inline `TextStyle` with hardcoded `fontSize: 12` and `Colors.orange` bypasses design system. Creates maintenance burden and inconsistent typography.

**Recommended Fix:**
```dart
Text(
  '正在生成主形象，請保持螢幕開啟。\n不要讓電腦休眠或切換應用程式，以免中斷。',
  style: BridgeDS.small.copyWith(
    color: BridgeDS.accentYellow, // Use system yellow for warnings
    height: 1.3,
    fontWeight: FontWeight.w600,
  ),
),
```
**Apply to all instances at lines:** 816, 861-864, 942-956, 1222-1225, 1273-1277, 1388-1392.

---

#### Issue #9: Sheet Pose Tile Uses Hardcoded Colors Throughout
**Lines:** 1181-1213, 1216, 1221-1225, 1238, 1242-1246, 1248-1254  
**Severity:** **CRITICAL**  
**Current Code:**
```dart
gradient: LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Colors.transparent,
    Colors.black.withValues(alpha: 0.6),  // ❌ Hardcoded gradient
  ],
),
// ...
Icon(pose.icon, size: 16, color: Colors.white),  // ❌ Hardcoded white
Text(
  pose.label,
  style: const TextStyle(
    fontSize: 13,  // ❌ Hardcoded size
    fontWeight: FontWeight.w800,
    color: Colors.white,  // ❌ Hardcoded white
  ),
),
```
**Problem:** Entire overlay gradient and text system uses hardcoded colors. Should use scrim overlay token or surface elevated with opacity.

**Recommended Fix:**
```dart
gradient: LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Colors.transparent,
    BridgeDS.canvas.withValues(alpha: 0.85), // Use canvas for dark overlay
  ],
),
// ...
Icon(pose.icon, size: 16, color: BridgeDS.textPrimary),
Text(
  pose.label,
  style: BridgeDS.small.copyWith(
    fontWeight: FontWeight.w800,
    color: BridgeDS.textPrimary,
  ),
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
),
```

---

### 2.2 Major Issues

#### Issue #10: Section Header Accent Bar Non-Standard
**Lines:** 522-528  
**Severity:** Major  
**Current Code:**
```dart
Container(
  width: 4,
  height: 20,
  decoration: BoxDecoration(
    color: BridgeDS.accentMiro,
    borderRadius: BorderRadius.circular(2),
  ),
),
```
**Problem:** Custom accent bar (4×20, radius 2) not documented in BridgeDS. Creates visual inconsistency across screens.

**Recommended Fix:** Either (1) add to design system as standard section header pattern, or (2) use icon-based header like other sections.

---

#### Issue #11: Button Minimum Height Inconsistency
**Lines:** 710, 2010, 2022  
**Severity:** Major  
**Current Code:**
```dart
FilledButton.styleFrom(
  backgroundColor: ...,
  minimumSize: const Size.fromHeight(48), // Line 710, 2010, 2022
),
```
vs. **Welcome screen buttons have no explicit height** (rely on default padding).

**Problem:** 48px button height doesn't align to 8pt grid (should be 40 or 48). Additionally, inconsistent with Welcome screen which uses default heights.

**Recommended Fix:**
```dart
minimumSize: const Size.fromHeight(48), // 48 is 6×8, acceptable
```
**But standardize across all screens** — either all buttons get explicit height or none.

---

#### Issue #12: Excessive Vertical Spacing in Form
**Lines:** 456, 460, 472, 480, 490, 503  
**Severity:** Major  
**Current Code:**
```dart
const SizedBox(height: BridgeDS.spaceLG),    // 24
_buildArchetypePresets(),
const SizedBox(height: BridgeDS.spaceLG),    // 24
OutlinedButton.icon(...),                     // Random button
const SizedBox(height: BridgeDS.spaceXL),    // 32
_buildSectionHeader('基本資料'),
const SizedBox(height: BridgeDS.spaceMD),    // 16
_buildTextField(...),
// ...
const SizedBox(height: BridgeDS.spaceXL),    // 32
_buildSectionHeader('個性設定'),
```
**Problem:** Frequent use of `spaceXL` (32) creates excessively loose form. Desktop forms should be denser. Use `spaceLG` (24) between sections, `spaceMD` (16) between fields.

**Recommended Fix:**
```dart
const SizedBox(height: BridgeDS.spaceLG),    // 24: section to element
_buildArchetypePresets(),
const SizedBox(height: BridgeDS.spaceMD),    // 16: element to button
OutlinedButton.icon(...),
const SizedBox(height: BridgeDS.spaceLG),    // 24: button to section
_buildSectionHeader('基本資料'),
const SizedBox(height: BridgeDS.spaceMD),    // 16: header to fields
_buildTextField(...),
// ...
const SizedBox(height: BridgeDS.spaceLG),    // 24: section break
_buildSectionHeader('個性設定'),
```

---

#### Issue #13: Widget Width Calculations Break Responsive Layout
**Lines:** 1081, 1763, 1837  
**Severity:** Major  
**Current Code:**
```dart
width: (MediaQuery.of(context).size.width * 0.4 - 80) / 2,  // Line 1081
width: (MediaQuery.of(context).size.width * 0.5 - 100) / 3, // Line 1763
width: (MediaQuery.of(context).size.width * 0.5 - 150) / 3, // Line 1837
```
**Problem:** Hard-coded magic numbers (80, 100, 150) and inconsistent screen width multipliers (0.4, 0.5) create fragile responsive behavior. These will break at different screen sizes.

**Recommended Fix:**
```dart
// Use LayoutBuilder and consistent logic
LayoutBuilder(
  builder: (context, constraints) {
    final availableWidth = constraints.maxWidth;
    final itemWidth = (availableWidth - (spacing * (columns - 1))) / columns;
    return SizedBox(width: itemWidth, child: ...);
  },
)
```

---

#### Issue #14: Progress Bar Color Lacks Context
**Lines:** 1059-1064, 2042-2047  
**Severity:** Major  
**Current Code:**
```dart
LinearProgressIndicator(
  minHeight: 6,
  value: ...,
  backgroundColor: BridgeDS.borderSubtle,
  valueColor: AlwaysStoppedAnimation(BridgeDS.accentMiro), // ✅ OK
),
```
**Problem:** `minHeight: 6` not on 8pt grid (should be 4 or 8). Also, `BridgeDS.borderSubtle` as background is semantically incorrect — should use `surface` or dedicated progress track color.

**Recommended Fix:**
```dart
LinearProgressIndicator(
  minHeight: 8, // Align to 8pt grid
  value: ...,
  backgroundColor: BridgeDS.surfaceElevated, // Semantic bg
  valueColor: AlwaysStoppedAnimation(BridgeDS.accentMiro),
),
```

---

#### Issue #15: Circular Icon Containers Use Non-Standard Sizes
**Lines:** 1629-1640, 1792-1803, 1877-1888  
**Severity:** Major  
**Current Code:**
```dart
Container(
  width: 36,
  height: 36,
  decoration: BoxDecoration(
    color: BridgeDS.accentMiro.withValues(alpha: 0.10),
    borderRadius: BorderRadius.circular(12),
  ),
  child: const Icon(Icons.move_to_inbox_outlined, size: 19),  // ❌ size: 19
),
```
vs. Line 1792:
```dart
Container(
  width: 38,  // ❌ Different from 36
  height: 38,
  decoration: BoxDecoration(
    color: BridgeDS.accentMiro.withValues(alpha: 0.12),
    shape: BoxShape.circle,
  ),
  child: const Icon(Icons.tune_outlined, size: 20),
),
```
**Problem:** Inconsistent icon container sizes (36 vs 38) and icon sizes (19 vs 20). Should standardize to 32 or 40 (8pt grid), with icon sizes 16, 20, or 24.

**Recommended Fix:**
```dart
Container(
  width: 40, // Standardize to 40 (5×8)
  height: 40,
  decoration: BoxDecoration(
    color: BridgeDS.accentMiro.withValues(alpha: 0.10),
    borderRadius: BorderRadius.circular(12), // Or use shape: BoxShape.circle
  ),
  child: const Icon(Icons.move_to_inbox_outlined, size: 20), // Standardize to 20
),
```

---

### 2.3 Minor Issues

#### Issue #16: AppBar Icon Size Not Standard
**Lines:** 397  
**Severity:** Minor  
**Current Code:**
```dart
IconButton(
  icon: const Icon(Icons.arrow_back, size: 20),
  color: BridgeDS.textPrimary,
  tooltip: '返回',
  onPressed: ...,
),
```
**Problem:** `size: 20` is OK, but Flutter Material default is 24. Verify this matches design system icon scale.

**Recommended Fix:** If design system specifies 24 for action icons, change to `size: 24`. Otherwise, document 20 as standard for compact layouts.

---

#### Issue #17: TextField ContentPadding Inconsistent
**Lines:** 532, 560, 1471, 1585  
**Severity:** Minor  
**Current Code:**
```dart
contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), // Line 532 ❌
contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 10),                 // Line 1585 ✅
contentPadding: const EdgeInsets.fromLTRB(8, 18, 8, 8),                   // Line 1471 ❌
```
**Problem:** Three different padding schemes for text fields. Welcome screen uses `(14, 12)`, Summon form uses `(12, 20, 12, 10)`, Summon sheet fields use `(8, 18, 8, 8)`. Should standardize.

**Recommended Fix:**
```dart
// For standard text fields:
contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
// For compact fields (sheet editor):
contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
```

---

#### Issue #18: Placeholder Preview Gradient Not Using Tokens
**Lines:** 601-605  
**Severity:** Minor  
**Current Code:**
```dart
decoration: BoxDecoration(
  gradient: const LinearGradient(
    colors: [BridgeDS.accentMiro, BridgeDS.accentGreen],  // ✅ Uses tokens
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  borderRadius: BorderRadius.circular(BridgeDS.roundWide),
  boxShadow: [...],
),
```
**Problem:** **Actually not an issue** — gradient correctly uses BridgeDS accent colors. No change needed.

---

#### Issue #19: Button Icon Sizes Inconsistent
**Lines:** 465, 778, 785, 962, 1038, 1050, 1671, 1917, 2006, 2017  
**Severity:** Minor  
**Current Code:**
```dart
Icon(Icons.casino_outlined, size: 16),      // Line 465
Icon(Icons.tune, size: 16),                  // Line 778
Icon(Icons.refresh, size: 16),               // Line 785
Icon(Icons.fact_check_outlined, size: 17),   // Line 962 ❌ Odd number
Icon(Icons.auto_awesome_motion, size: 16),   // Line 1038
Icon(Icons.add_photo_alternate_outlined, size: 16), // Line 1050
Icon(Icons.auto_awesome, size: 18),          // Line 2006 ❌ Different
Icon(Icons.check_circle, size: 18),          // Line 2017 ❌ Different
```
**Problem:** Button icon sizes vary between 16, 17 (odd!), and 18. Should standardize to 16 for small buttons, 20 or 24 for large CTAs.

**Recommended Fix:**
```dart
// Small buttons (OutlinedButton, secondary actions)
Icon(Icons.tune, size: 16),
// Large buttons (FilledButton, primary CTAs)
Icon(Icons.auto_awesome, size: 20),
Icon(Icons.check_circle, size: 20),
```

---

#### Issue #20: Dialog Background Color Hardcoded
**Lines:** 1374  
**Severity:** Minor  
**Current Code:**
```dart
Dialog(
  backgroundColor: Colors.black87,  // ❌ Hardcoded
  insetPadding: const EdgeInsets.all(16),
  child: ...,
)
```
**Problem:** `Colors.black87` hardcoded for full-screen image dialog. Should use `BridgeDS.surface` or create dedicated scrim token.

**Recommended Fix:**
```dart
Dialog(
  backgroundColor: BridgeDS.canvas, // Or BridgeDS.surface if lighter needed
  insetPadding: const EdgeInsets.all(16),
  child: ...,
)
```

---

### 2.4 Typography

#### Issue #21: Flopping Between BridgeDS and Inline TextStyle
**Lines:** 1574-1600 (uses BridgeDS), vs 570-575, 816, 1222-1225 (inline TextStyle)  
**Severity:** Minor  
**Problem:** Inconsistent — some components use `BridgeDS.small.copyWith(...)`, others use raw `TextStyle(fontSize: 12, ...)`.

**Recommended Fix:** **Always start from BridgeDS token** and use `.copyWith()` for overrides:
```dart
// Bad
style: TextStyle(fontSize: 12, color: Colors.orange, ...)
// Good
style: BridgeDS.small.copyWith(color: BridgeDS.accentYellow, ...)
```

---

### 2.5 Color & Theme

✅ **Mostly Good**, but see Critical Issue #7, #8, #9 for hardcoded color violations.

---

## Summary Table

| Issue # | Severity | Screen  | Category          | Line(s)        | Description                                      |
|---------|----------|---------|-------------------|----------------|--------------------------------------------------|
| 2       | Minor    | Welcome | Spacing           | 328, 336, 348  | Inconsistent hero spacing rhythm                |
| 4       | Minor    | Welcome | Contrast          | 516-517        | Label color may lack WCAG contrast              |
| 5       | Minor    | Welcome | Icon Grid         | 784            | Lock icon size 12 → should be 16                |
| 6       | Minor    | Welcome | Padding Grid      | 768            | Chip padding 14 → should be 16                  |
| 7       | **CRITICAL** | Summon | Hardcoded Colors | 622-660   | Multiple `Colors.white` in placeholder preview  |
| 8       | **CRITICAL** | Summon | Typography       | 570-575, 816, 861-864 | Inline `TextStyle` with hardcoded sizes |
| 9       | **CRITICAL** | Summon | Hardcoded Colors | 1181-1254 | Sheet tile gradient & text use `Colors.white/black` |
| 10      | Major    | Summon  | Components        | 522-528        | Custom accent bar not in design system          |
| 11      | Major    | Summon  | Button Hierarchy  | 710, 2010      | Button height inconsistent across screens       |
| 12      | Major    | Summon  | Spacing           | 456-503        | Excessive vertical spacing in form              |
| 13      | Major    | Summon  | Responsive        | 1081, 1763     | Fragile width calculations with magic numbers   |
| 14      | Major    | Summon  | Progress Bar      | 1059-1064      | Progress bar height off grid (6 → 8)            |
| 15      | Major    | Summon  | Icon Containers   | 1629, 1792     | Inconsistent icon container sizes (36 vs 38)    |
| 16      | Minor    | Summon  | Icon Grid         | 397            | AppBar icon size 20 → verify with system        |
| 17      | Minor    | Summon  | Input Fields      | 532, 1471      | Three different text field padding schemes      |
| 19      | Minor    | Summon  | Icon Sizes        | 465-2017       | Button icon sizes vary (16, 17, 18)             |
| 20      | Minor    | Summon  | Dialog            | 1374           | Dialog background uses `Colors.black87`         |
| 21      | Minor    | Summon  | Typography        | 570-1600       | Inconsistent TextStyle vs BridgeDS token usage  |

---

## Recommendations Priority

### 🔴 Immediate (Critical)
1. **Fix all hardcoded colors** in Summon screen (Issues #7, #9) — replace with BridgeDS tokens
2. **Remove inline TextStyle** with hardcoded sizes (Issue #8) — use BridgeDS typography tokens

### 🟡 High Priority (Major)
3. **Standardize button heights** across Welcome + Summon (Issue #11)
4. **Fix responsive width calculations** — remove magic numbers (Issue #13)
5. **Reduce excessive spacing** in Summon form (Issue #12)
6. **Standardize icon container sizes** to 40px (Issue #15)

### 🟢 Medium Priority (Minor)
7. **Align all sizes to 8pt grid** — padding, icon sizes, progress bars
8. **Standardize text field padding** across all screens
9. **Document or remove custom accent bar** pattern (Issue #10)

---

## Design System Gaps Identified

These patterns appeared in code but are **not specified in BridgeDS**:

1. **Section header accent bar** (4×20, radius 2) — add to design system or deprecate
2. **Icon container sizes** — design system should specify standard sizes (32, 40, 48)
3. **Button heights** — should desktop use explicit `minimumSize: Size.fromHeight(48)` or rely on default padding?
4. **Progress bar styling** — needs dedicated tokens for track/background colors
5. **Overlay gradients** — need scrim tokens for image overlays (currently using `Colors.black.withOpacity`)

---

## Positive Observations

✅ **Welcome Screen:**
- Clean, focused layout with clear visual hierarchy
- Strong use of BridgeDS motion components (BridgeScaleIn, BridgeSlideIn, BridgePulseDot)
- Correct semantic token usage for backgrounds and borders
- BridgeGlowButton state management is excellent

✅ **Summon Screen:**
- Comprehensive feature parity with mobile version
- Well-structured dual-pane desktop layout
- Good separation of concerns (form column + preview column)
- Sophisticated state management for multi-step workflow

---

## Conclusion

Both screens demonstrate strong understanding of the BridgeDS design system with isolated violations primarily in the Summon screen's overlay UI components. The Welcome screen is production-ready with minor spacing tweaks. The Summon screen requires a focused pass to eliminate hardcoded colors and standardize spacing before production release.

**Estimated Remediation Time:**
- Critical issues: 4-6 hours (search-replace + testing)
- Major issues: 6-8 hours (refactor responsive logic)
- Minor issues: 2-4 hours (polish)

**Total: 12-18 hours of focused design system compliance work.**
