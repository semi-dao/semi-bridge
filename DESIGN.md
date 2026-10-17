---
version: alpha
name: Bridge Design System
description: >
  xAI 科技氛圍 × Raycast 色彩質感 × Stripe 向量粒子 × Figma 動態活潑 × Miro 無限畫布連續感 × Active Theory 可沉浸。
  六套設計系統融合，核心靈魂：無限連續，不斷不跳。

> **📐 重要更新（2026-08-04）**
> 本檔 v0.x 已被正式拆分為兩層：
> - **本檔（DESIGN.md）**：保留 — 5 套設計系統融合的原始靈魂與精神（永恆不變）
> - **[Bridge 統合設計語言 v0.1](docs/BRIDGE_UNIFIED_DESIGN_LANGUAGE.md)**：新裁決層 — 將五個來源蒸餾為 Bridge 的五種能力、三層介面與衝突裁決順序。
> - **[橋樑排版設計原則 v1.0](docs/BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md)**：新規則 — 字體級距、圖示級距、顏色 token、主題包擴充介面
>
> 所有新 UI 程式碼必須遵守「橋樑排版設計原則」。本檔的精神與新規則的規則**互補**，前者是「為什麼」，後者是「怎麼做」。

> **📱 手機版刪除宣告（2026-08-10）**
> - 手機版已正式宣告刪除，本設計系統專注於桌面版體驗
> - 未來手機版將重新設計，可能調整某些設計原則以適應行動裝置

---
  # 基礎：xAI 深色科技 + Raycast 色彩質感
  canvas: "#07080a"          # Raycast 近黑藍 — 比 xAI 的 #1f2228 更深更冷，桌面技術工具感
  surface: "#101111"          # Raycast Surface 100 — 卡片、面板底色
  surface-elevated: "#1b1c1e" # Raycast 卡片表面 — badge、標籤
  surface-hover: "#252829"    # Raycast border 色 — hover 提升

  # 文字層級（xAI 的 white-on-dark + Raycast 灰階）
  text-primary: "#f9f9f9"     # Raycast near-white — 主文字
  text-secondary: "#cecece"   # Raycast 次要文字
  text-tertiary: "#9c9c9d"    # Raycast 灰 — 標籤、導航
  text-muted: "#6a6b6c"       # Raycast 暗灰 — disabled、佔位
  text-quaternary: "#434345"  # Raycast 最暗 — 非活躍

  # 互動色（Raycast 系 + Stripe 數據紫）
  accent-red: "#FF6363"       # Raycast Red — 品牌 punctuate、危險、錯誤
  accent-blue: "#55b3ff"      # Raycast 使用者 — 互動、連結、focus
  accent-green: "#5fc992"     # Raycast Green — 成功、連線
  accent-yellow: "#ffbc33"    # Raycast Yellow — 警告、注意
  accent-purple: "#533afd"    # Stripe Purple — 大腦/向量/數據可視化專用
  accent-navy: "#061b31"      # Stripe Navy — 深層數據文字、圖表標題
  accent-magenta: "#f96bee"   # Stripe Magenta — 漸層裝飾、粒子特效
  accent-ruby: "#ea2261"      # Stripe Ruby — 漸層裝飾、警示粒子
  accent-miro: "#5b76fe"      # Miro 使用者 450 — 無限畫布互動、教學引導

  # 透明度疊層（xAI opacity 系統 + Raycast 互動）
  border-subtle: "rgba(255,255,255,0.06)"   # Raycast — 卡片邊界
  border-default: "rgba(255,255,255,0.10)"  # xAI — 標準邊框
  border-strong: "rgba(255,255,255,0.20)"   # xAI — 活躍/hover
  surface-glass: "rgba(255,255,255,0.05)"   # xAI — 微弱提升
  surface-glass-hover: "rgba(255,255,255,0.08)" # xAI — hover

  # 大腦可視化專用（Stripe 向量粒子）
  particle-1: "#533afd"       # 紫 — 核心節點
  particle-2: "#f96bee"       # 洋紅 — 連線光
  particle-3: "#55b3ff"       # 藍 — 活躍路徑
  particle-4: "#5fc992"       # 綠 — 成功觸發
  particle-glow: "rgba(83,58,253,0.25)"  # 紫光暈 — 節點發光

typography:
  # 字體：xAI monospace display + Raycast Inter body + Stripe 精準權重
  display:
    fontFamily: Geist Mono
    fontSize: 48px
    fontWeight: 300
    lineHeight: 1.10
    letterSpacing: "-0.04em"
  heading-l:
    fontFamily: Geist Mono
    fontSize: 32px
    fontWeight: 400
    lineHeight: 1.20
    letterSpacing: "-0.02em"
  heading-m:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: 500
    lineHeight: 1.30
    letterSpacing: "0.2px"
  heading-s:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: 500
    lineHeight: 1.40
    letterSpacing: "0.2px"
  body-l:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: 400
    lineHeight: 1.50
    letterSpacing: "0.2px"
  body:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: 500
    lineHeight: 1.60
    letterSpacing: "0.2px"
  body-tight:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: 400
    lineHeight: 1.15
    letterSpacing: "0.1px"
  button:
    fontFamily: Geist Mono
    fontSize: 14px
    fontWeight: 500
    lineHeight: 1.15
    letterSpacing: "0.3px"
    textTransform: uppercase
  label-mono:
    fontFamily: Geist Mono
    fontSize: 12px
    fontWeight: 500
    lineHeight: 1.60
    letterSpacing: "0.6px"
    textTransform: uppercase
  caption:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: 500
    lineHeight: 1.14
    letterSpacing: "0.2px"
  small:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: 600
    lineHeight: 1.33
    letterSpacing: "0px"
  code:
    fontFamily: Geist Mono
    fontSize: 14px
    fontWeight: 500
    lineHeight: 1.60
    letterSpacing: "0.3px"

rounded:
  # 圓角：xAI 銳利 + Figma pill + Miro 寬圓 — 混合系統
  sharp: 0px           # xAI — 邊框、技術標籤
  subtle: 4px          # xAI/Raycast — badge
  standard: 8px        # Raycast — 輸入框、小元件
  comfortable: 12px    # Raycast — 標準卡片
  wide: 16px           # Raycast/Miro — 大卡片、面板
  extra: 20px          # Miro — 展開面板
  pill: 50px           # Figma — 按鈕、tab
  circle: 999px        # Figma — 圓形圖示按鈕（CSS full-circle trick）

spacing:
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  xxl: 48px

# 陰影系統（Raycast macOS 多層 + Stripe 藍調色染）
shadows:
  # Raycast macOS-native 深度
  level-0: "none"
  level-1: "rgba(0,0,0,0.28) 0px 1px 2px"
  level-2-ring: "rgb(27,28,30) 0px 0px 0px 1px, rgb(7,8,10) 0px 0px 0px 1px inset"
  level-3-button: "rgba(255,255,255,0.05) 0px 1px 0px inset, rgba(255,255,255,0.25) 0px 0px 0px 1px, rgba(0,0,0,0.2) 0px -1px 0px inset"
  level-5-floating: "rgba(0,0,0,0.5) 0px 0px 0px 2px, rgba(255,255,255,0.19) 0px 0px 14px"
  # Stripe 藍調陰影（大腦/數據可視化用）
  data-elevated: "rgba(50,50,93,0.25) 0px 30px 45px -30px, rgba(0,0,0,0.1) 0px 18px 36px -18px"
  data-deep: "rgba(3,3,39,0.25) 0px 14px 21px -14px, rgba(0,0,0,0.1) 0px 8px 17px -8px"
  # 光暈（粒子/大腦）
  glow-purple: "rgba(83,58,253,0.15) 0px 0px 20px 5px"
  glow-blue: "rgba(85,179,255,0.15) 0px 0px 20px 5px"
  glow-red: "rgba(255,99,99,0.15) 0px 0px 20px 5px"

# 動態系統（Figma 活潑 + Miro 無限畫布連續感）
motion:
  # Miro 無限連續 — 所有轉場的核心
  transition-canvas: "cubic-bezier(0.22, 1, 0.36, 1)"    # ease-out-expo — 畫布平移
  transition-spring: "spring(mass: 1, stiffness: 280, damping: 24)"  # Figma 彈簧 — 按鈕回饋
  transition-morph: "cubic-bezier(0.34, 1.56, 0.64, 1)"   # ease-out-back — 形狀變形
  transition-slide: "cubic-bezier(0.25, 0.46, 0.45, 0.94)" # ease-out-quad — 面板滑入
  duration-fast: 150ms
  duration-normal: 300ms
  duration-slow: 500ms
  duration-canvas: 600ms    # 畫布級轉場

components:
  # 按鈕（Figma pill + Raycast opacity transition + xAI mono uppercase）
  button-primary:
    backgroundColor: "#ffffff"
    textColor: "#07080a"
    rounded: "{rounded.pill}"
    typography: "{typography.button}"
    padding: "12px 24px"
    transition: "opacity 0.15s"
    hover: "opacity 0.6"

  button-accent:
    backgroundColor: "{colors.accent-blue}"
    textColor: "#07080a"
    rounded: "{rounded.pill}"
    typography: "{typography.button}"
    padding: "12px 24px"
    transition: "opacity 0.15s"
    hover: "opacity 0.8"

  button-ghost:
    backgroundColor: transparent
    textColor: "{colors.text-primary}"
    rounded: "{rounded.pill}"
    typography: "{typography.button}"
    padding: "12px 24px"
    border: "1px solid {colors.border-default}"
    transition: "opacity 0.15s"
    hover: "opacity 0.6"

  button-brain:
    backgroundColor: "{colors.accent-purple}"
    textColor: "#ffffff"
    rounded: "{rounded.pill}"
    typography: "{typography.button}"
    padding: "12px 24px"

  # 卡片（Raycast 雙環陰影 + xAI 透明邊框）
  card-standard:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.comfortable}"
    padding: "{spacing.lg}"

  card-brain:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.wide}"
    padding: "{spacing.lg}"

  # 輸入框（Raycast dark input + xAI focus ring）
  input-standard:
    backgroundColor: "{colors.canvas}"
    border: "1px solid {colors.border-subtle}"
    rounded: "{rounded.standard}"
    textColor: "{colors.text-primary}"
    placeholder: "{colors.text-muted}"
    focus-border: "{colors.accent-blue}"
    focus-glow: "rgba(85,179,255,0.15)"
    typography: "{typography.body}"

  # 狀態標籤（xAI mono tag + Raycast semantic colors）
  tag-success:
    backgroundColor: "#0e1b12"
    textColor: "#b8e8cc"
    rounded: "{rounded.subtle}"
    typography: "{typography.label-mono}"
    padding: "4px 8px"

  tag-error:
    backgroundColor: "#1b0e0e"
    textColor: "#ffadad"
    rounded: "{rounded.subtle}"
    typography: "{typography.label-mono}"
    padding: "4px 8px"

  tag-info:
    backgroundColor: "#0e151b"
    textColor: "#b3dcff"
    rounded: "{rounded.subtle}"
    typography: "{typography.label-mono}"
    padding: "4px 8px"

  tag-brain:
    backgroundColor: "#0e0a1b"
    textColor: "#b9b9f9"
    rounded: "{rounded.subtle}"
    typography: "{typography.label-mono}"
    padding: "4px 8px"

  # 無限畫布面板（Miro ring border + 連續滑入）
  canvas-panel:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.wide}"
---

# Bridge Design System

## Overview

Bridge 的設計融合五套世界級設計系統，核心靈魂是**無限連續**——使用者從打開 App 到關閉，
每一個按鈕、每一個表單、每一個轉場，都不斷裂、不跳頁，像在一張無限畫布上滑動。

### 五套融合策略

| 來源 | 借鑑維度 | 具體取用 |
|------|---------|---------|
| **xAI** | 基礎氛圍 | 深色科技感、monospace display 字體、銳利邊角、高對比白-on-dark、opacity 互動 |
| **Raycast** | 色彩質感 | 近黑藍底色 `#07080a`、多層 macOS 陰影、正面 letter-spacing +0.2px、weight 500 baseline、opacity hover |
| **Stripe** | 大腦/圖表 | 藍調陰影 `rgba(50,50,93)`、紫 `#533afd` 粒子、navy 深文、ruby/magenta 漸層 |
| **Figma** | 按鈕動態 | pill 50px 圓角、彩色漸層慶祝、variable font 精細權重、dashed focus ring |
| **Miro** | 轉場/教學 | 無限畫布連續感、ring shadow 邊框、Framer 級 spring 動畫、面板滑入不跳頁 |

## Colors

### 畫布層（xAI 氛圍 → Raycast 質感）

- **Canvas (`#07080a`)**：Raycast 近黑藍。比 xAI 的 `#1f2228` 更深更冷，桌面技術工具的「內部空間」感。所有畫面的底層。
- **Surface (`#101111`)**：卡片、面板的底色。比 canvas 略亮一階，創造微弱浮起感。
- **Surface Elevated (`#1b1c1e`)**：badge、標籤、二級面板。

### 文字層級（xAI 白階 + Raycast 灰階）

- **Primary (`#f9f9f9`)**：主文字。Raycast 近白，不純白以減少暗底刺眼。
- **Secondary (`#cecece`)**：描述文字、次要內容。
- **Tertiary (`#9c9c9d`)**：標籤、導航連結預設色。
- **Muted (`#6a6b6c`)**：佔位符、disabled。

### 互動色（Raycast 語意 + Stripe 數據）

- **Red (`#FF6363`)**：品牌 punctuate、危險、錯誤、Gateway 停止。
- **使用者 (`#55b3ff`)**：互動、連結、focus ring、配對連線中。
- **Green (`#5fc992`)**：成功、連線建立、Gateway 運行。
- **Yellow (`#ffbc33`)**：警告、注意。
- **Purple (`#533afd`)**：大腦/向量/記憶可視化專用。不是一般 accent，是「智慧」的色彩語言。
- **Miro 使用者 (`#5b76fe`)**：無限畫布互動、教學引導、連續轉場的視覺線索。

### 大腦可視化粒子色（Stripe 向量）

- `particle-1` 紫 `#533afd` — 核心節點
- `particle-2` 洋紅 `#f96bee` — 連線光
- `particle-3` 藍 `#55b3ff` — 活躍路徑
- `particle-4` 綠 `#5fc992` — 成功觸發
- 節點發光用 `rgba(83,58,253,0.25)` 紫光暈

## Typography

### 字體策略

- **Geist Mono**：display 標題、按鈕文字、技術標籤。xAI 的 monospace-as-luxury 哲學——固定寬度在極端尺度下有節奏感。
- **Inter**：body、heading-m/s、caption。Raycast 的 +0.2px letter-spacing + weight 500 baseline 在暗底上更易讀。

### 字體替代

| 原始 | Google Fonts 替代 | 角色 |
|------|-------------------|------|
| Geist Mono | Geist Mono（直接可用） | Display, Button, Label |
| Inter | Inter（直接可用） | Body, Heading, Caption |

```html
<link href="https://fonts.googleapis.com/css2?family=Geist+Mono:wght@300;400;500&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
```

### 原則

- **Monospace for impact**：Geist Mono 用在 display 和 button，製造技術權威感。
- **+0.2px tracking on dark**：Raycast 獨門——暗底正面 letter-spacing 讓文字更透氣。
- **Weight 500 baseline**：body 用 500 不用 400，暗底更清晰。
- **Weight 300 for display**：xAI 哲學——輕量級大字 = 自信不喊叫。

## Layout

### 無限畫布佈局（Miro 核心 + xAI 結構）

桌面端不使用傳統的「頁面」概念，而是**單一畫布上的區域切換**：

```
┌─────────────────────────────────────────────────────┐
│  TopBar (fixed, 64px)                                │
│  [Logo]  [Canvas Nav: 對話 | 大腦 | 檔案 | 設定]     │
├──────────┬──────────────────────────┬───────────────┤
│          │                          │               │
│ Sidebar  │  Active Canvas Area      │  Context      │
│ (240px)  │  (flex-grow)             │  Panel        │
│          │                          │  (320px,      │
│ 對話列表  │  ← 無限畫布區域           │  可收合)      │
│ 記憶索引  │     所有內容在此連續滑入   │               │
│ 標籤     │     不跳頁                │  當前狀態     │
│          │                          │  記憶詳情     │
│          │                          │  快捷操作     │
│          │                          │               │
├──────────┴──────────────────────────┴───────────────┤
│  StatusBar (fixed, 32px)                             │
│  [Gateway: ●running] [配對碼: BRIDGE-XXXXXX]         │
└─────────────────────────────────────────────────────┘
```

### 間距系統

8px 基準，刻度：`8 / 16 / 24 / 32 / 48`

### 圓角混合策略

| 圓角 | 用途 | 來源 |
|------|------|------|
| 0px (sharp) | 技術標籤、代碼塊、數據表格邊框 | xAI |
| 4px (subtle) | badge、tag | xAI/Raycast |
| 8px (standard) | 輸入框、小元件 | Raycast |
| 12px (comfortable) | 標準卡片、訊息氣泡 | Raycast |
| 16px (wide) | 大卡片、展開面板 | Miro |
| 20px (extra) | 全螢幕面板、教學面板 | Miro |
| 50px (pill) | 按鈕、tab | Figma |
| 50% (circle) | 圓形圖示按鈕、頭像 | Figma |

## Elevation & Depth

### 三層深度系統

| 層級 | 手法 | 用途 | 來源 |
|------|------|------|------|
| **Void** | 無陰影，canvas 底色 | 頁面背景 | xAI |
| **Ring** | 雙環陰影（outer + inset） | 卡片、面板 | Raycast |
| **Floating** | 重陰影 + 白光暈 | 浮動面板、命令面板 | Raycast |
| **Data** | 藍調多層陰影 | 大腦可視化、圖表 | Stripe |
| **Glow** | 色彩光暈 | 粒子節點、活躍狀態 | Stripe |

### 原則

- **不用單層 flat shadow**：Raycast 哲學——陰影永遠成對（outer + inset）。
- **深度 = opacity 不是 shadow**：xAI 哲學——邊框透明度 0.06→0.10→0.20 創造層次。
- **數據用藍調陰影**：Stripe 哲學——`rgba(50,50,93,0.25)` 讓陰影本身有品牌色。

## Motion — 無限連續的核心

### 轉場原則（Miro 無限畫布）

**所有畫面切換都是畫布的平移或縮放，不是路由跳轉。**

| 操作 | 傳統做法 | Bridge 做法 | 動畫 |
|------|---------|------------|------|
| 切換對話 | push 新頁面 | 畫布向左滑，新對話從右滑入 | `transition-canvas` 600ms |
| 開新對話 | 跳轉新頁面 | 畫布向右滑出新空白區，游標自動聚焦 | `transition-canvas` 600ms |
| 下拉選單 | overlay popup | 從觸發點展開，周圍內容 morph 讓位 | `transition-morph` 300ms spring |
| 收起面板 | 頁面重排跳動 | 面板向側邊滑出，主區域 smooth resize | `transition-slide` 500ms |
| 表單提交 | loading → 跳轉結果 | 按鈕 morph → 進度條 in-place → 結果展開 | `transition-morph` + spring |
| 下一步/教學 | 換頁 | 畫布向左平移，下一步從右連續滑入 | `transition-canvas` 600ms |
| 開啟設定 | modal overlay | 畫布向右滑，設定面板從左滑入覆蓋 | `transition-slide` 500ms |
| 訊息送出 | 列表 append | 訊息從輸入框位置 morph 飛出到列表 | `transition-morph` 300ms spring |
| 角色召喚 | 彈窗動畫 | 粒子從畫布邊緣匯聚 → 角色漸顯 + scale | `transition-spring` + glow |

### Flutter 實作策略

```dart
// 核心路由器：不用 PageView，用 AnimatedSwitcher + 自定義 transition
// 所有「頁面」都是同一個畫布上的不同區域

// 1. 對話切換 — 水平平移不淡入
PageTransitionsTheme(
  builders: {
    TargetPlatform.macOS: CanvasSlideTransitionBuilder(),
  },
)

// 2. 面板展開 — AnimatedContainer + 自定義 curve
AnimatedContainer(
  duration: Duration(milliseconds: 500),
  curve: Curves.easeOutQuad,  // transition-slide
  width: _expanded ? 320 : 0,
)

// 3. 按鈕回饋 — ScaleTransition + spring
ScaleTransition(
  scale: Tween(begin: 1.0, end: 0.95).animate(
    CurvedAnimation(curve: Curves.easeOutBack),  // transition-morph
  ),
)

// 4. 訊息飛出 — Hero + flightShuttleBuilder
Hero(
  tag: 'message-${id}',
  flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
    return ScaleTransition(scale: animation);  // morph from input to list
  },
)

// 5. 滾動物理 — BouncingScrollPhysics 模擬畫布慣性
ScrollPhysics: BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
```

### 禁止事項

- ❌ 不用 `Navigator.push` 做頁面跳轉（除非是系統級強制如 share sheet）
- ❌ 不用 `showDialog` 做 overlay（用 in-place morph）
- ❌ 不用 `FadeTransition` 做畫面切換（用 slide/morph 保持空間連續）
- ❌ 不用 `SnackBar` 做回饋（用 inline expansion card）
- ❌ 不用硬切 `setState` 重建畫面（用 `AnimatedSwitcher` 帶 transition）

## Brain Visualization

### 大腦結構可視化（Stripe 向量粒子風格）

大腦可視化是 Bridge 的視覺高潮，使用 Stripe 的粒子美學：

```
節點 = 發光圓點
  - 核心：particle-1 紫 #533afd + glow-purple 20px
  - 活躍：particle-3 藍 #55b3ff + glow-blue 20px
  - 成功：particle-4 綠 #5fc992
  - 警示：accent-ruby #ea2261

連線 = 漸層線段
  - 預設：rgba(255,255,255,0.1) 1px
  - 活躍路徑：particle-2 洋紅 → particle-3 藍 漸層
  - 觸發中：particle-1 紫 → particle-4 綠 漸層 + 流動動畫

佈局 = 力導向圖（force-directed graph）
  - 節點間斥力 + 連線彈力
  - 用 CustomPainter 繪製
  - 60fps AnimationBuilder 驅動
```

### Flutter 實作

```dart
class BrainGraph extends StatelessWidget {
  // CustomPainter 繪製力導向圖
  // 每個節點：RadialGradient + BlurMask (glow)
  // 連線：LinearGradient + 流動 dash animation
  // 互動：GestureDetector 拖拽節點 → 重新計算力學
}
```

## Components

### 按鈕系統（Figma pill + Raycast opacity + xAI mono）

所有按鈕：
- Geist Mono 14px uppercase +0.3px tracking
- Pill 50px 圓角
- hover 用 opacity 0.6 transition（不是改色）
- 四種類型：Primary(白底)、Accent(藍底)、Ghost(透明框)、Brain(紫底+glow)

### 卡片系統（Raycast 雙環 + xAI 透明邊框）

- 標準卡片：surface 底 + 雙環陰影 + 12px 圓角
- 大腦卡片：紫調邊框 + 藍調陰影 + 16px 圓角
- hover：邊框 opacity 0.06→0.20

### 輸入框（Raycast dark + xAI focus）

- canvas 底色 + subtle border
- focus：邊框轉藍 + 藍光暈 ring
- 無圓角過度，8px 標準

### 狀態標籤（xAI mono + Raycast 語意色）

- 全部用 Geist Mono 12px uppercase
- 四色：success(green) / error(red) / info(blue) / brain(purple)
- 半透明背景 + 對應色邊框 + 對應色文字

## Do's and Don'ts

### Do

- 用 `#07080a` 不用 `#000000`——藍冷色調是 Raycast 的靈魂
- body text 用 weight 500 + letter-spacing +0.2px——暗底必須比 light mode 重
- 陰影用雙層（outer + inset）——單層看起來扁平
- 按鈕 hover 用 opacity 不用改色——Raycast 簽名互動
- 所有轉場用 slide/morph 不用 fade——空間連續性
- 大腦/數據可視化用 Stripe 藍調陰影——品牌一致性
- display 字用 Geist Mono weight 300——monospace 即品牌

### Don't

- 不用純黑 `#000000` 底色——永遠用 `#07080a`
- 不用 weight 400 做 body——暗底太薄
- 不用 `Navigator.push` 跳頁——破壞無限畫布連續感
- 不用 `showDialog` overlay——用 in-place morph
- 不用 `FadeTransition` 切換——用 slide 保持空間感
- 不用單層 shadow——永遠配對 outer + inset
- 不用 positive letter-spacing 在 display 字上——display 用 -0.04em
- 不在大腦可視化外用紫色——紫色 = 智慧專屬語言
- 不用 Material 預設圓角——用 Bridge 的混合圓角系統

---

## 🛠 實作狀態（Implementation Status）

> **最後更新：2026-08-04**

### ✅ 已實作
- **`ThemePackService` MVP**（`lib/services/theme_pack_service.dart`）
  - `importFromZip` / `exportToZip` / `install` / `uninstall` / `listInstalled`
  - ZIP 結構：`manifest.json` + `fonts/*` + `preview.png`
  - 驗證 33 個 token 完整性 + 字型檔案存在性
  - WCAG AA 對比度檢查（textPrimary/canvas ≥ 4.5:1）
  - 存到 `~/Library/Application Support/farm.semiwasabi.bridgeApp/themes/{packId}/`
- **`ThemePack` 資料模型**（`lib/models/theme_pack.dart`）
- **`ThemeProvider` ChangeNotifier**（`lib/state/theme_provider.dart`）
- **4 個端到端測試**（`test/theme_pack_service_test.dart`）全通過
- **33 個 BridgeDSColors token** 已正式落地

### 🚧 待實作
- ~~3 套官方主題包~~ — **2026-08-04 取消**（使用者 決定：內建只 2 套，深淺×N 指數增長不可維護。社群主題包自己一套配色的設計）
- **問題 1 待修**：自動掃描工具（偵測違規字體/顏色）+ 掃描問題頁（夥伴館、召喚夥伴）
- **問題 3 待做**：蒸餾 5 套設計精髓（不是抄作業）

### 📐 內建主題原則（v1.1，2026-08-04）
- 內建只 **2 個**：dark + light
- 主題包不再「自動深淺翻倍」—— 一個主題包就是一份完整配色
- 切換主題：頂部工具列按鈕（輪播模式），不再有「深/淺」單獨按鈕
- 移除 ThemeController，統一由 ThemeProvider 管理

### 📊 顏色 token 總覽（33 個）
- **Canvas & Surface**：4 個（canvas / surface / surfaceElevated / surfaceHover）
- **文字層級**：5 個（textPrimary / textSecondary / textTertiary / textMuted / textQuaternary）
- **互動色**：9 個（accentRed/使用者/Green/Yellow/Purple/Navy/Magenta/Ruby/Miro）
- **透明度疊層**：5 個（borderSubtle/Default/Strong + surfaceGlass/GlassHover）
- **狀態標籤**：10 個（tagSuccessBg/Fg + tagErrorBg/Fg + tagInfoBg/Fg + tagBrainBg/Fg + tagWarnBg/Fg）

**合計：4 + 5 + 9 + 5 + 10 = 33 token**
