# Dark Mode Design Systems Research
## Flutter Desktop App AI Agent Knowledge Base

**Version:** 1.0  
**Last Updated:** 2026-07-18  
**Target:** BridgeDS Flutter macOS Desktop App  
**Current Palette:** Canvas #07080A, Surface #101111, Accent Miro #5B76FE, Fonts: Geist Mono + Inter

---

## 1. Dark Mode Best Practices

### Core Principles

**Never Use Pure Black (#000000)**
- Pure black (#000000) causes eye strain and makes OLED screens show smearing
- Recommended dark backgrounds: #0D0D0D to #1A1A1A (3-10% lightness)
- BridgeDS canvas #07080A (2.7% lightness) is acceptable, surface #101111 (6.3% lightness) is ideal for elevation

**Surface Elevation Through Lighter Colors**
- Base surface: #101111 (current BridgeDS surface)
- Elevated +1: #181818 (9.4% lightness) - cards, panels
- Elevated +2: #202020 (12.5% lightness) - modals, tooltips
- Elevated +3: #282828 (15.7% lightness) - dropdowns, context menus
- Rule: Add 3-4% lightness per elevation level, never exceed 20% for dark mode

**Avoid High Saturation**
- Max saturation for dark mode: 60-70%
- BridgeDS accentMiro #5B76FE has 99% saturation - **reduce to #6B82FF (78% sat) for large surfaces**
- Use full saturation only for: primary CTAs, active states, selection highlights (<5% screen area)
- Desaturate by 30-50% for: backgrounds, disabled states, secondary actions

**Text Colors**
- Primary text: #E8E8E8 to #F0F0F0 (91-94% lightness), not pure white
- Secondary text: #A0A0A0 to #B8B8B8 (63-72% lightness)
- Tertiary/hint text: #707070 to #808080 (44-50% lightness)
- Never use pure white (#FFFFFF) except for: badges, emphasis spans (<1% screen area)
- Contrast ratios: 7:1 for body text, 4.5:1 for large text (18px+)

**Border Opacity (Critical Rule)**
- White borders at 6-20% opacity: `rgba(255, 255, 255, 0.06)` to `rgba(255, 255, 255, 0.20)`
- Default dividers: 8% opacity (#FFFFFF14)
- Focused/hover borders: 16% opacity (#FFFFFF28)
- Active/selected borders: 20% opacity (#FFFFFF33)
- Never use solid gray (#808080) - opacity adapts to any background

**Color Inversion Pitfalls**
- Don't auto-invert images/icons - they lose meaning
- Don't invert brand colors - adjust luminance instead
- Don't invert shadows - use lighter shadows or elevation layers
- Do invert charts/graphs if they use light backgrounds
- Do provide dark variants for logos/illustrations

---

## 2. Material Design 3 (M3)

### Dynamic Color System

**Tonal Palettes**
- Each color has 13 tones: 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 100
- Dark scheme uses: tone 80 (primary), tone 30 (onPrimary), tone 20 (primaryContainer)
- Light scheme uses: tone 40 (primary), tone 100 (onPrimary), tone 90 (primaryContainer)

**Color Roles (Dark Mode Mapping)**
```
Primary: tone 80          // #5B76FE → lighter variant
OnPrimary: tone 20        // Text on primary
PrimaryContainer: tone 30 // Subdued primary backgrounds
OnPrimaryContainer: 90    // Text on containers

Secondary: tone 80
OnSecondary: tone 20
SecondaryContainer: tone 30
OnSecondaryContainer: tone 90

Tertiary: tone 80
OnTertiary: tone 20
TertiaryContainer: tone 30
OnTertiaryContainer: tone 90

Error: tone 80 (#FF8A80 range)
OnError: tone 20
ErrorContainer: tone 30
OnErrorContainer: tone 90

Surface: tone 6           // #101111 ≈ tone 6
SurfaceDim: tone 6
SurfaceBright: tone 24
SurfaceContainerLowest: tone 4
SurfaceContainerLow: tone 10
SurfaceContainer: tone 12
SurfaceContainerHigh: tone 17
SurfaceContainerHighest: tone 22

OnSurface: tone 90
OnSurfaceVariant: tone 80
Outline: tone 60
OutlineVariant: tone 30
```

**Elevation in Dark Mode (M3 Tonal Elevation)**
- M3 uses tonal elevation, not shadows
- 0dp: tone 6 (base surface)
- 1dp: +1 tone (tone 7) - subtle lift
- 2dp: +2 tones (tone 8)
- 3dp: +3 tones (tone 9)
- 4dp: +4 tones (tone 10)
- 5dp: +5 tones (tone 11)
- Max elevation uses tone 24 (surfaceBright)

**Shape System**
- None: 0dp corner radius
- Extra Small: 4dp - chips, small buttons
- Small: 8dp - cards, inputs
- Medium: 12dp - dialogs, date pickers
- Large: 16dp - bottom sheets, nav drawers
- Extra Large: 28dp - FAB, special emphasis

**Motion Principles**
- Duration tokens: short1 (50ms), short2 (100ms), short3 (150ms), short4 (200ms), medium1 (250ms), medium2 (300ms), medium3 (350ms), medium4 (400ms), long1 (450ms), long2 (500ms), long3 (550ms), long4 (600ms)
- Emphasized easing: cubic-bezier(0.2, 0.0, 0, 1.0) - material enters
- Standard easing: cubic-bezier(0.4, 0.0, 0.2, 1) - general use
- Decelerate easing: cubic-bezier(0.0, 0.0, 0.2, 1) - exits

---

## 3. Apple HIG for macOS

### Materials (NSVisualEffectView)

**Material Types**
- Ultra-thin: Most transparent, subtle tint
- Thin: Light tint, minimal blur
- Medium (Regular): Default material, balanced blur
- Thick: Heavy blur, strong tint
- Use thin/ultra-thin for: HUD overlays, in-window popovers
- Use medium for: sidebars, toolbars, standard panels
- Use thick for: window backgrounds in transparency mode

**Vibrancy**
- System applies automatic contrast to text/icons over materials
- Label colors: primary, secondary, tertiary, quaternary
- Fill colors: primary (10% opacity), secondary (5%), tertiary (3%)
- Separator: 10% opacity in light, 19% in dark
- Always use system semantic colors with vibrancy - never hardcode

**Accent Colors**
- System accent: blue, purple, pink, red, orange, yellow, green, graphite
- User controls accent via System Preferences
- Use `AccentColor` asset or `NSColor.controlAccentColor`
- BridgeDS accentMiro #5B76FE should adapt to user's accent when possible

### Sidebar Patterns

**Layout**
- Min width: 140pt, max width: 300pt, default: 180-220pt
- Top padding: 20pt from window top
- Item height: 20-24pt for icons, 22-28pt for text-only
- Section headers: 16-18pt tall, 8pt top margin
- Selected item: full-width rounded rect, 6pt corner radius

**Colors**
- Background: systemGray6 (light), systemGray5 (dark) or use materials
- Selected background: use accent color at 15-20% opacity
- Hover: accent at 8-10% opacity
- Icon tint: secondary label color (67% opacity of primary)

### Toolbar Patterns

**Unified Toolbar**
- Height: 52pt (standard), 28pt (compact)
- Item spacing: 12-16pt between items
- Icon size: 16x16pt for toolbar glyphs
- Title: centered or inline with controls
- Background: use thick material or solid with 80% opacity

**Toolbar Item Types**
- Icon button: 16x16pt SF Symbol, 28x28pt hit target
- Segmented control: 28-32pt tall
- Search field: 140pt min width, 200pt ideal
- Title: San Francisco 13pt regular

### Window Anatomy

**Title Bar**
- Height: 28pt (compact), 38pt (standard), 52pt (unified toolbar)
- Traffic lights: 12pt from left edge, vertically centered
- Title: 13pt San Francisco, 66% opacity when inactive

**Content Area**
- Safe area insets: account for title bar, toolbars, sidebars
- Bottom bar (if any): 32-40pt tall
- Minimum window size: 400x300pt typical, adjust per use case

**Resize Behavior**
- Preserve aspect ratio for: media viewers, canvases
- Flexible for: data tables, text editors
- Minimum content size: define per-view to prevent unusable states

---

## 4. Design Token Systems

### Token Structure (Three-Tier Hierarchy)

**Primitive Tokens (Raw Values)**
```
color.neutral.0: #000000
color.neutral.50: #07080A    // BridgeDS canvas
color.neutral.100: #101111   // BridgeDS surface
color.neutral.200: #181818
color.neutral.900: #E8E8E8
color.neutral.1000: #FFFFFF

color.blue.500: #5B76FE      // BridgeDS accentMiro
color.blue.400: #6B82FF
color.blue.600: #4A5FE8

spacing.xs: 4
spacing.sm: 8
spacing.md: 12
spacing.lg: 16
spacing.xl: 24

font.family.mono: 'Geist Mono'
font.family.sans: 'Inter'
font.size.xs: 11
font.size.sm: 13
font.size.md: 15
font.size.lg: 18
```

**Semantic Tokens (Purpose-Based)**
```
background.canvas: {$color.neutral.50}
background.surface: {$color.neutral.100}
background.elevated: {$color.neutral.200}

text.primary: {$color.neutral.900}
text.secondary: {$color.neutral.700}
text.tertiary: {$color.neutral.500}

border.default: rgba(255, 255, 255, 0.08)
border.hover: rgba(255, 255, 255, 0.16)
border.focus: {$color.blue.500}

action.primary.background: {$color.blue.500}
action.primary.text: {$color.neutral.1000}
action.secondary.background: {$color.neutral.200}
```

**Component Tokens (Specific Use)**
```
button.primary.background: {$action.primary.background}
button.primary.background.hover: {$color.blue.400}
button.primary.text: {$action.primary.text}
button.primary.padding.horizontal: {$spacing.lg}
button.primary.padding.vertical: {$spacing.sm}
button.primary.corner.radius: {$spacing.sm}

card.background: {$background.surface}
card.border: {$border.default}
card.padding: {$spacing.lg}
card.shadow: 0 2px 8px rgba(0, 0, 0, 0.3)
```

### Naming Conventions

**Category-Type-Item-State Pattern**
```
{category}.{type}.{item}.{variant}.{state}

Examples:
color.background.surface.elevated
color.text.primary
color.border.default.hover
spacing.component.card.padding
typography.heading.h1.weight
```

**Avoid**
- Color names: "blue", "red" (use semantic: "primary", "error")
- Vague terms: "light", "dark" (use "subtle", "emphasis")
- Implementation details: "hex", "rgba" (abstract)

### Token Interpolation & Single Source of Truth

**Token Files**
```json
// tokens/primitives.json
{
  "color": {
    "neutral": {
      "50": { "value": "#07080A", "type": "color" },
      "100": { "value": "#101111", "type": "color" }
    },
    "blue": {
      "500": { "value": "#5B76FE", "type": "color" }
    }
  }
}

// tokens/semantic.json
{
  "background": {
    "canvas": { "value": "{color.neutral.50}", "type": "color" },
    "surface": { "value": "{color.neutral.100}", "type": "color" }
  }
}
```

**Build Pipeline**
1. Define primitives in JSON/YAML
2. Reference primitives in semantic tokens using `{token.path}`
3. Generate platform-specific code: Dart, Swift, CSS, Kotlin
4. Never hardcode values in components - always reference tokens

**Tools**
- Style Dictionary (Amazon) - token transformation
- Tokens Studio (Figma plugin) - design integration
- Specify - design-to-code token sync

---

## 5. Flutter Theming

### ThemeData Setup

**Basic Dark Theme**
```dart
import 'package:flutter/material.dart';

final darkTheme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  
  // ColorScheme from seed
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF5B76FE), // accentMiro
    brightness: Brightness.dark,
  ),
  
  // Override specific colors
  scaffoldBackgroundColor: const Color(0xFF07080A), // canvas
  
  // Typography
  fontFamily: 'Inter',
  textTheme: const TextTheme(
    displayLarge: TextStyle(fontFamily: 'Inter'),
    bodyLarge: TextStyle(fontFamily: 'Inter'),
    bodyMedium: TextStyle(fontFamily: 'Inter'),
    labelLarge: TextStyle(fontFamily: 'Inter'),
  ),
  
  // Component themes
  cardTheme: CardTheme(
    color: const Color(0xFF101111), // surface
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: Colors.white.withOpacity(0.08),
        width: 1,
      ),
    ),
  ),
  
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF101111),
    elevation: 0,
    centerTitle: false,
  ),
);
```

### ColorScheme.fromSeed Dark Mode

**How It Works**
```dart
// Generate tonal palette from single seed color
final scheme = ColorScheme.fromSeed(
  seedColor: Color(0xFF5B76FE),
  brightness: Brightness.dark,
);

// Generated colors (approximate):
// primary: tone 80 (lighter variant of seed)
// primaryContainer: tone 30
// secondary: tone 80 (analogous hue)
// tertiary: tone 80 (complementary hue)
// surface: tone 6
// background: tone 6
// error: Material default red tone 80
```

**BridgeDS Custom Scheme**
```dart
final bridgeDarkScheme = ColorScheme.dark(
  // Core palette
  primary: const Color(0xFF6B82FF),           // Slightly lighter accentMiro
  onPrimary: const Color(0xFF0D1333),         // Dark blue for text on primary
  primaryContainer: const Color(0xFF2A3A80),  // Muted container
  onPrimaryContainer: const Color(0xFFDAE2FF), // Light text on container
  
  // Surfaces
  surface: const Color(0xFF101111),           // BridgeDS surface
  surfaceDim: const Color(0xFF07080A),        // BridgeDS canvas
  surfaceBright: const Color(0xFF282828),     // Elevated surfaces
  onSurface: const Color(0xFFE8E8E8),         // Primary text
  onSurfaceVariant: const Color(0xFFA0A0A0),  // Secondary text
  
  // Borders & outlines
  outline: const Color(0xFF3D3D3D),           // ~24% white
  outlineVariant: const Color(0xFF1A1A1A),    // ~10% white
  
  // Secondary/Tertiary (neutral scheme for BridgeDS)
  secondary: const Color(0xFF8891A5),
  onSecondary: const Color(0xFF0F1419),
  secondaryContainer: const Color(0xFF2C3340),
  
  // Error
  error: const Color(0xFFFF8A80),
  onError: const Color(0xFF5E0F0F),
  errorContainer: const Color(0xFF93000A),
  onErrorContainer: const Color(0xFFFFDAD6),
);
```

### ThemeData Extensions for Custom Tokens

**Define Extension**
```dart
// lib/theme/bridge_tokens.dart
@immutable
class BridgeTokens extends ThemeExtension<BridgeTokens> {
  const BridgeTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceElevated1,
    required this.surfaceElevated2,
    required this.accentMiro,
    required this.borderDefault,
    required this.borderHover,
    required this.borderFocus,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.monoFont,
    required this.sansFont,
  });
  
  final Color canvas;
  final Color surface;
  final Color surfaceElevated1;
  final Color surfaceElevated2;
  final Color accentMiro;
  final Color borderDefault;
  final Color borderHover;
  final Color borderFocus;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final String monoFont;
  final String sansFont;
  
  @override
  BridgeTokens copyWith({
    Color? canvas,
    Color? surface,
    // ... all properties
  }) {
    return BridgeTokens(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      // ... all properties
    );
  }
  
  @override
  BridgeTokens lerp(BridgeTokens? other, double t) {
    if (other is! BridgeTokens) return this;
    return BridgeTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      // ... all properties
    );
  }
  
  static const dark = BridgeTokens(
    canvas: Color(0xFF07080A),
    surface: Color(0xFF101111),
    surfaceElevated1: Color(0xFF181818),
    surfaceElevated2: Color(0xFF202020),
    accentMiro: Color(0xFF5B76FE),
    borderDefault: Color(0x14FFFFFF), // 8% white
    borderHover: Color(0x28FFFFFF),   // 16% white
    borderFocus: Color(0xFF5B76FE),
    textPrimary: Color(0xFFE8E8E8),
    textSecondary: Color(0xFFA0A0A0),
    textTertiary: Color(0xFF707070),
    monoFont: 'Geist Mono',
    sansFont: 'Inter',
  );
}
```

**Add to ThemeData**
```dart
final theme = ThemeData(
  brightness: Brightness.dark,
  colorScheme: bridgeDarkScheme,
  extensions: const <ThemeExtension<dynamic>>[
    BridgeTokens.dark,
  ],
);
```

**Use in Widgets**
```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<BridgeTokens>()!;
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      color: tokens.surface,
      decoration: BoxDecoration(
        border: Border.all(color: tokens.borderDefault),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Hello',
        style: TextStyle(
          color: tokens.textPrimary,
          fontFamily: tokens.sansFont,
        ),
      ),
    );
  }
}
```

### Design Tokens in Flutter Widgets

**Token Access Patterns**
```dart
// 1. Via Theme Extension (Recommended for custom tokens)
final tokens = Theme.of(context).extension<BridgeTokens>()!;
final bgColor = tokens.surface;

// 2. Via ColorScheme (For M3 semantic colors)
final scheme = Theme.of(context).colorScheme;
final primary = scheme.primary;

// 3. Via TextTheme (For typography)
final textTheme = Theme.of(context).textTheme;
final headline = textTheme.headlineMedium;

// 4. Direct from ThemeData (For specific overrides)
final cardColor = Theme.of(context).cardTheme.color;
```

**Component Token Composition**
```dart
// lib/components/bridge_button.dart
class BridgeButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  
  const BridgeButton({
    required this.label,
    this.onPressed,
    this.isPrimary = true,
  });
  
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<BridgeTokens>()!;
    final scheme = Theme.of(context).colorScheme;
    
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: isPrimary ? tokens.accentMiro : tokens.surface,
        foregroundColor: isPrimary ? Colors.white : tokens.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: isPrimary 
            ? BorderSide.none 
            : BorderSide(color: tokens.borderDefault),
        ),
        textStyle: TextStyle(
          fontFamily: tokens.sansFont,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: Text(label),
    );
  }
}
```

---

## 6. Anti-Patterns & AI Design Slop

### Gradient Abuse

**Avoid**
- Rainbow gradients (5+ colors)
- Harsh diagonal gradients (45°-135°) with high contrast
- Animated/moving gradients for static UI
- Gradients on text (except headings <10% of screen)
- Mesh gradients as primary backgrounds

**Use Sparingly**
- Subtle 2-color gradients for CTAs (10-15° angle, 5-10% lightness delta)
- Radial gradients for spotlight effects (20% opacity max)
- Noise texture overlays (2-4% opacity) instead of gradients

### Glassmorphism Overuse

**Danger Signs**
- Backdrop blur on >30% of UI elements
- Blur radius >20px (causes performance issues)
- Stacking 3+ blurred layers (compounds readability issues)
- Blur on critical content (forms, data tables, code editors)

**Safe Usage**
- Modal overlays: 10-16px blur, 40-60% background opacity
- Floating toolbars: 8px blur, 70% opacity
- macOS materials: use system materials, not custom blur
- Always test with complex backgrounds - ensure text remains 4.5:1 contrast

### Emoji Icons 🚫

**Never Use**
- Emoji as primary navigation icons (🏠 🔍 ⚙️)
- Emoji in professional toolbars
- Emoji for status indicators (use proper icons/colors)

**Acceptable (Sparingly)**
- User-generated content
- Casual messaging features
- Onboarding illustrations (if brand allows)

### Generic SaaS Card Grids

**The Slop Pattern**
```
┌─────────┐ ┌─────────┐ ┌─────────┐
│  Icon   │ │  Icon   │ │  Icon   │
│  Title  │ │  Title  │ │  Title  │
│  Text   │ │  Text   │ │  Text   │
│ [Button]│ │ [Button]│ │ [Button]│
└─────────┘ └─────────┘ └─────────┘
```

**Better Alternatives**
- List view with rich inline actions
- Sidebar navigation + detail pane
- Command palette for quick access
- Table view for data-heavy content
- Cards only when content is truly modular and equal-priority

### Left-Border Callout Cards

**Overused**
```
┃ Title
┃ This is important information
┃ with a colored left border
```

**Use Maximum Once Per Screen**
- Reserve for: alerts, warnings, errors
- Better alternatives: toast notifications, inline validation, status badges
- If you must: 3px border max, use semantic colors, ensure 4px+ border radius

### Fake Dashboards

**Red Flags**
- Metrics with no data source
- Charts that never update
- "Analytics" that show static examples
- Percentage changes with no timeframe
- Revenue/user counts in demos (unless real)

**Real Dashboards**
- Show loading states
- Display "no data" gracefully
- Update in real-time or show last-updated timestamp
- Allow filtering and date ranges
- Export and drill-down capabilities

### Rainbow Palettes

**Don't**
- Use 7+ distinct hues in one interface
- Assign random colors to categories
- Use full-saturation rainbow for data visualization

**Do**
- Stick to 2-3 semantic colors (primary, error, success)
- Use tonal variations of one hue for multi-level data
- Colorblind-safe palettes: blue/orange, purple/green (avoid red/green alone)

### Stock SVG Illustrations

**Avoid**
- Generic "team collaboration" scenes
- Floating 3D shapes with gradient fills
- People illustrations with impossible body proportions
- Illustrations that duplicate text content (show, don't tell)

**Better**
- App-specific screenshots
- Simple line icons (Lucide, Heroicons)
- Data visualizations
- No illustration (often best)

### Vague Labels

**Bad**
- "Learn More" (about what?)
- "Settings" (which settings?)
- "Dashboard" (what data?)
- "More" (more what?)
- "Info" (what info?)

**Good**
- "View Account Settings"
- "Manage Team Members"
- "Sales Overview"
- "View 12 More Comments"
- "API Documentation"

### Unnecessary Icons

**Slop Pattern**
- Icon next to every list item (visual noise)
- Icon in every button (redundant)
- Decorative icons that don't convey meaning

**Use Icons When**
- They clarify ambiguous text (🔒 for locked items)
- Standard patterns (✓ for success, ⚠ for warning)
- Navigation is icon-only (with tooltips)
- Improving scannability in dense UIs

**Skip Icons When**
- Text is already clear
- Screen space is limited
- Icons would be inconsistent across items

### Decorative Motion

**Useless Animations**
- Page transitions >500ms
- Hover effects with >200ms delay
- Parallax scrolling (desktop apps)
- Animated backgrounds (continuous motion causes distraction)
- Loading spinners that rotate during instant operations

**Functional Motion**
- Confirm user action (button press feedback)
- Show relationship (expanding accordion)
- Guide attention (new item highlight)
- Preserve continuity (shared element transitions)

---

## 7. Motion Design

### Duration Standards

**Base Durations**
- Micro (50-100ms): Hover states, focus rings, tooltips
- Short (150-200ms): Button presses, checkbox toggles, switch animations
- Standard (200-300ms): Card expansion, dropdown menus, modal open/close
- Medium (300-400ms): Page transitions, drawer slide-in, tab switching
- Complex (400-500ms): Multi-step animations, stagger groups, morphing shapes
- Never exceed 500ms for UI feedback (feels sluggish)

**Context-Specific**
```dart
// Flutter constants
const kMicroDuration = Duration(milliseconds: 100);
const kShortDuration = Duration(milliseconds: 200);
const kStandardDuration = Duration(milliseconds: 300);
const kMediumDuration = Duration(milliseconds: 400);
const kComplexDuration = Duration(milliseconds: 500);
```

### Easing Curves

**Flutter Curves**
```dart
// Enter (element appearing)
Curves.easeOut         // Decelerating, starts fast
Curves.easeOutCubic    // Smooth deceleration
Curves.easeOutQuart    // Sharp deceleration

// Exit (element disappearing)  
Curves.easeIn          // Accelerating, ends fast
Curves.easeInCubic     // Smooth acceleration
Curves.easeInQuart     // Sharp acceleration

// Move/Transform (element changing position)
Curves.easeInOut       // Smooth both ends
Curves.easeInOutCubic  // Balanced motion
Curves.fastOutSlowIn   // Material standard (emphasize end)

// Bounce/Elastic (use sparingly)
Curves.elasticOut      // Overshoot then settle
Curves.bounceOut       // Physical bounce
```

**When to Use Each**
- `easeOut` - Dialogs opening, items appearing, growing elements
- `easeIn` - Dialogs closing, items disappearing, shrinking elements
- `easeInOut` - Moving items, sliding panels, scrolling
- `fastOutSlowIn` - Material Design default, safe choice
- `elasticOut` / `bounceOut` - Success confirmations, playful interactions (not professional tools)

**Custom Cubic Bezier**
```dart
// Material emphasized (enter)
const emphasizedEasing = Cubic(0.2, 0.0, 0, 1.0);

// Material standard  
const standardEasing = Cubic(0.4, 0.0, 0.2, 1.0);

// Material decelerate (exit)
const decelerateEasing = Cubic(0.0, 0.0, 0.2, 1.0);
```

### Staggered Animations

**List Item Stagger**
```dart
class StaggeredList extends StatelessWidget {
  final List<Widget> items;
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final delay = index * 0.05; // 50ms per item
            final progress = Curves.easeOut.transform(
              ((_controller.value - delay) / (1 - delay)).clamp(0.0, 1.0),
            );
            
            return Opacity(
              opacity: progress,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - progress)),
                child: items[index],
              ),
            );
          },
        );
      },
    );
  }
}
```

**Stagger Rules**
- Delay between items: 30-80ms (50ms ideal)
- Max stagger group: 8-10 items (otherwise feels laggy)
- Direction: top-to-bottom (primary), left-to-right (secondary)
- Total duration: stagger delay × items + base duration (should not exceed 800ms total)

### Prefers-Reduced-Motion

**Respect User Preferences**
```dart
// Check system preference
import 'dart:ui' as ui;

bool get prefersReducedMotion {
  return ui.window.accessibilityFeatures.disableAnimations;
}

// Apply in animations
final duration = prefersReducedMotion 
  ? Duration.zero 
  : kStandardDuration;

AnimatedContainer(
  duration: duration,
  curve: Curves.easeOut,
  // ...
);
```

**Reduced Motion Guidelines**
- Disable: Page transitions, decorative animations, parallax, autoplay
- Keep: Focus indicators, loading states, essential feedback (use opacity/scale changes instead of motion)
- Instant: Use Duration.zero for non-essential animations
- Crossfade: Replace slide/scale transitions with opacity fades

**Flutter Implementation**
```dart
class ResponsiveAnimation extends StatelessWidget {
  final Widget child;
  
  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    
    if (reduceMotion) {
      return child; // No animation wrapper
    }
    
    return AnimatedSwitcher(
      duration: kStandardDuration,
      child: child,
    );
  }
}
```

---

## BridgeDS-Specific Recommendations

### Palette Adjustments

**Current vs Recommended**
```
Current:
- canvas: #07080A (2.7% lightness) ✓ Good
- surface: #101111 (6.3% lightness) ✓ Good
- accentMiro: #5B76FE (99% saturation) ⚠ Too saturated for large areas

Recommended:
- canvas: #07080A ✓ Keep
- surface: #101111 ✓ Keep
- surfaceElevated1: #181818 (add for cards)
- surfaceElevated2: #202020 (add for modals)
- accentMiro: #5B76FE ✓ Keep for CTAs
- accentMiroSoft: #6B82FF (add for backgrounds, ~78% saturation)
- textPrimary: #E8E8E8 (add)
- textSecondary: #A0A0A0 (add)
- textTertiary: #707070 (add)
- borderDefault: rgba(255, 255, 255, 0.08) (add)
- borderHover: rgba(255, 255, 255, 0.16) (add)
```

### Typography Scale

**Using Inter + Geist Mono**
```dart
const bridgeTextTheme = TextTheme(
  // Display (marketing, headers)
  displayLarge: TextStyle(
    fontFamily: 'Inter',
    fontSize: 57,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
    height: 1.12,
  ),
  
  // Headings
  headlineLarge: TextStyle(
    fontFamily: 'Inter',
    fontSize: 32,
    fontWeight: FontWeight.w600,
    height: 1.25,
  ),
  headlineMedium: TextStyle(
    fontFamily: 'Inter',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.33,
  ),
  headlineSmall: TextStyle(
    fontFamily: 'Inter',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.4,
  ),
  
  // Body
  bodyLarge: TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0.15,
  ),
  bodyMedium: TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.43,
    letterSpacing: 0.25,
  ),
  bodySmall: TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.33,
    letterSpacing: 0.4,
  ),
  
  // Labels (buttons, inputs)
  labelLarge: TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  ),
  
  // Code/Mono
  labelSmall: TextStyle(
    fontFamily: 'Geist Mono',
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
  ),
);
```

### Component Library Priorities

**Build These First**
1. **BridgeButton** - Primary/secondary/tertiary variants, proper tokens
2. **BridgeCard** - With elevation system, border tokens
3. **BridgeInput** - Text fields with focus states
4. **BridgeAppBar** - macOS-style toolbar with proper materials
5. **BridgeSidebar** - Navigation with selection states
6. **BridgeModal** - Dialog/sheet with backdrop blur
7. **BridgeToast** - Notifications with proper timing

**Token Reference Pattern**
Every component should:
- Pull colors from `BridgeTokens` extension, never hardcode
- Use semantic tokens (e.g., `tokens.borderDefault`) not primitives
- Support light/dark themes via token swaps
- Include hover/focus/active states
- Respect `prefers-reduced-motion`

---

## Quick Reference Card

### Color Values
```
Canvas: #07080A
Surface: #101111
Elevated +1: #181818
Elevated +2: #202020
Accent: #5B76FE
Text Primary: #E8E8E8
Text Secondary: #A0A0A0
Border Default: #FFFFFF14 (8% opacity)
Border Hover: #FFFFFF28 (16% opacity)
```

### Spacing Scale
```
4px  - xs  - tight spacing
8px  - sm  - default spacing
12px - md  - comfortable
16px - lg  - section spacing
24px - xl  - major sections
32px - 2xl - page margins
```

### Animation Timing
```
100ms - Hover, focus
200ms - Buttons, toggles
300ms - Dropdowns, cards
400ms - Drawers, modals
500ms - Page transitions (max)
```

### Easing
```
Enter:  Curves.easeOut
Exit:   Curves.easeIn
Move:   Curves.easeInOut / fastOutSlowIn
```

### Border Radius
```
4px  - Chips, small buttons
8px  - Cards, inputs, buttons
12px - Modals, dropdowns
16px - Bottom sheets
```

---

---

## Sources & Further Reading

**Material Design 3 (M3)**
- Official docs: https://m3.material.io/
- Dynamic color: https://m3.material.io/styles/color/dynamic-color/overview
- Elevation: https://m3.material.io/styles/elevation/overview
- Motion: https://m3.material.io/styles/motion/overview

**Apple Human Interface Guidelines**
- macOS HIG: https://developer.apple.com/design/human-interface-guidelines/macos
- Materials: https://developer.apple.com/design/human-interface-guidelines/materials
- Color: https://developer.apple.com/design/human-interface-guidelines/color

**Flutter Documentation**
- ThemeData: https://api.flutter.dev/flutter/material/ThemeData-class.html
- ColorScheme: https://api.flutter.dev/flutter/material/ColorScheme-class.html
- Material 3 migration: https://docs.flutter.dev/ui/design/material

**Design Token Resources**
- Style Dictionary: https://amzn.github.io/style-dictionary/
- Tokens Studio: https://tokens.studio/
- Design Tokens W3C spec: https://design-tokens.github.io/community-group/format/

**Anti-patterns & Design Critique**
- Refactoring UI (Adam Wathan & Steve Schoger) - practical design principles
- Laws of UX (Jon Yablonski) - https://lawsofux.com/
- Can't Unsee (design game for developing taste) - https://cantunsee.space/

---

**End of Research Document**

**Compiled:** 2026-07-18  
**For:** BridgeDS Flutter macOS Desktop App AI Agent  
**Next Steps:** Integrate into agent's design decision-making system, validate against existing BridgeDS implementation, create component library checklist.
