# 橋樑設計基礎（Bridge Design Foundation）

> **版本**：v1.0
> **建立**：2026-08-10
> **作者**：教練 Agent × 使用者
> **狀態**：🏛️ 地基文件——所有 UI 設計決策的權威來源
>
> **📱 手機版刪除宣告（2026-08-10）**：
> - 手機版已正式宣告刪除，不再干擾桌面 APP 開發進度
> - 未來手機版將重新設計，目前專案專注於桌面版體驗
> - 手機版相關檔案已封存至 `_ARCHIVED_bridge_app_MOBILE_20260810/`：
>   - `mobile_bridge_pairing_screen.dart`
>   - `mobile_design_showcase_screen.dart`
>   - `services/mobile_bridge_client.dart`
>   - `widgets/mobile/` 目錄

> 本文件是橋樑 App 設計系統的**組裝說明書**。
> 零件（token、tier、常數）的定義在各自的源碼和文件中，
> 本文件定義的是**如何把零件組裝成畫面**。

---

## 目錄

1. [設計哲學](#1-設計哲學)
2. [邊界系統（Boundary System）](#2-邊界系統)
3. [標題層級（Hierarchy System）](#3-標題層級)
4. [Token 關係圖（Token Relationship Map）](#4-token-關係圖)
5. [元件規範（Component Specs）](#5-元件規範)
6. [互動狀態規範（Interaction States）](#6-互動狀態規範)
7. [陰影與深度規範（Shadow & Elevation）](#7-陰影與深度規範)
8. [圖示使用規範（Icon Guidelines）](#8-圖示使用規範)
9. [動畫規範（Motion Guidelines）](#9-動畫規範)
10. [頁面結構範本（Page Templates）](#10-頁面結構範本)
11. [設計審核清單（Design Checklist）](#11-設計審核清單)
12. [附錄：完整查詢表](#12-附錄完整查詢表)

---

## 1. 設計哲學

### 五套融合
| 來源 | 貢獻 | 體現在哪 |
|---|---|---|
| **xAI** | 暗色科技氛圍 | canvas 深黑、accent 飽和色 |
| **Raycast** | 雙環陰影、鍵盤優先 | ringShadow、command palette |
| **Stripe** | 數據視覺化深度 | dataElevated 藍調陰影 |
| **Figma** | 動態色彩系統 | ThemeExtension + Tier 系統 |
| **Miro** | 無限畫布不跳頁 | 畫布 tab、區域切換動畫 |

### 核心鐵則
1. **無限連續**——不跳頁，區域切換用動畫過渡
2. **token 先行**——所有顏色走 `BridgeDSColors.of(context)`，所有文字走 `TierStyle.of(context, tier)`
3. **牽一髮動全身**——改一個 token，全 App 自動跟著變
4. **14px 下限**——任何文字不小於 14px，任何 icon 不小於 12px

---

## 2. 邊界系統

### 2.1 畫面分層

橋樑 App 的畫面從外到內分 **5 層**：

```
┌─────────────────────────────────────────────┐
│ Layer 0: Canvas                              │  App 最外層背景
│   ┌─────────────────────────────────────┐   │
│   │ Layer 1: Screen                     │   │  整個功能頁面
│   │   ┌─────────────────────────────┐   │   │
│   │   │ Layer 2: Panel              │   │   │  側欄、內容區、右側面板
│   │   │   ┌─────────────────────┐   │   │   │
│   │   │   │ Layer 3: Card        │   │   │   │  卡片、列表項
│   │   │   │   ┌─────────────┐    │   │   │   │
│   │   │   │   │ Layer 4:    │    │   │   │   │  按鈕、輸入框、標籤
│   │   │   │   │ Element     │    │   │   │   │
│   │   │   │   └─────────────┘    │   │   │   │
│   │   │   └─────────────────────┘   │   │   │
│   │   └─────────────────────────────┘   │   │
│   └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### 2.2 每層的邊界規則

| 層級 | 背景色 Token | 邊框 | 圓角 | 內距 (padding) | 外距 (margin) |
|---|---|---|---|---|---|
| **L0 Canvas** | `canvas` | 無 | 無 | 無 | 無 |
| **L1 Screen** | 透明（透出 canvas） | 無 | 無 | 無 | 無 |
| **L2 Panel** | `canvas`（跟 L0 同色，用邊框區分） | `borderSubtle` | 無 | `spaceMD` (16) | 無 |
| **L3 Card** | `surface` | `borderSubtle` | `roundComfortable` (12) | `spaceMD` (16) | `spaceSM` (8) |
| **L4 Element** | `surfaceElevated` 或透明 | `borderDefault`（focus 時 `borderStrong`） | `roundStandard` (8) | 依元件類型 | 依元件類型 |

### 2.3 間距系統

| Token | 值 | 用途 |
|---|---|---|
| `spaceSM` | 8px | Card 內元件間距、icon 與文字間距 |
| `spaceMD` | 16px | Card 內距、Panel 內距、列表項間距 |
| `spaceLG` | 24px | 區塊間距、Card 間距 |
| `spaceXL` | 32px | Panel 間距、大區塊分隔 |
| `spaceXXL` | 48px | 頁面 hero 區域上下留白 |

**鐵則**：間距只能用這 5 個值。禁止 4px、10px、20px 等非標準值。

### 2.4 圓角系統

| Token | 值 | 適用層級 | 具體用途 |
|---|---|---|---|
| `roundSharp` | 0px | L4 | 技術標籤、狀態 badge |
| `roundSubtle` | 4px | L4 | tag chip |
| `roundStandard` | 8px | L4 | 輸入框、小卡片、按鈕 |
| `roundComfortable` | 12px | L3 | **標準卡片**（預設圓角） |
| `roundWide` | 16px | L3 | 大卡片、modal、dialog |
| `roundExtra` | 20px | L2 | 展開面板、drawer |
| `roundPill` | 50px | L4 | pill button、tab 指示器 |
| `roundCircle` | 999px | L4 | 圓形頭像、icon button |

**鐵則**：Card 一律 `roundComfortable` (12)。Dialog 一律 `roundWide` (16)。除非設計明確要求特殊形狀，否則不偏离。

---

## 3. 標題層級

### 3.1 Tier → 畫面區域對應表

每一個畫面區域，都有**對應的 Tier**。不要猜，查表。

| 你在哪裡 | 用什麼 Tier | Typography 級 | 範例 |
|---|---|---|---|
| 頁面 H1（系統頁、大腦頁標題） | `Tier.appDisplayLarge` | L2 (32/w400) | 「系統」「大腦」 |
| 頁面 H2 / 區塊大標題 | `Tier.appHeadline` | L3 (24/w500) | 「快速上手」 |
| 儀式場景大標題 | `Tier.ceremonyHeroTitle` | 特殊 (28/w700) | 召喚夥伴成功 |
| 卡片標題 | `Tier.cardTitle` | L4 (20/w500) | 夥伴卡名稱 |
| 卡片英雄標題 | `Tier.cardHeroTitle` | L4 (20/w500) | 首頁入口卡片 |
| 卡片內文 | `Tier.cardBody` | L6 (16/w500) | 夥伴描述 |
| 主要內文（大段） | `Tier.bodyPrimary` | L5 (18/w400) | 說明文字（少用） |
| Sidebar 項目標題 | `Tier.sidebarRowTitle` | L8 (14/w500) | 對話列表 |
| Sidebar 項目副標 | `Tier.sidebarRowSubtitle` | L9 (12/w600) | 時間、摘要 |
| Sidebar 項目 metadata | `Tier.sidebarRowMeta` | L9 (12/w600) | 未讀數、tag |
| 列表項標題 | `Tier.listItemTitle` | L6 (16/w500) | 畫布列表 |
| 列表項副標 | `Tier.listItemSubtitle` | L8 (14/w500) | 狀態 |
| 表單 label | `Tier.formLabel` | L8 (14/w500) | API URL |
| 表單輸入 | `Tier.formInput` | L6 (16/w500) | 輸入框 |
| 表單 helper | `Tier.formHelper` | L9 (12/w600) | 提示文字 |
| 對話框標題 | `Tier.dialogTitle` | L4 (20/w500) | D002 確認框 |
| 對話框內文 | `Tier.dialogBody` | L6 (16/w500) | 確認框參數 |
| 主按鈕 | `Tier.buttonPrimary` | L12 (14/w500) | 「確認執行」 |
| 次按鈕 | `Tier.buttonSecondary` | L8 (14/w500) | 「取消」 |
| 數字強調 | `Tier.numericEmphasis` | L9 (12/w900) | 夥伴計數 |
| 分類標籤 | (用 `labelMono`) | L10 (12/w500 mono) | 「SYSTEM」 |
| 技術值 | (用 `code`) | L11 (14/w500 mono) | port 號、endpoint |
| 卡片註腳 | `Tier.cardCaption` | L8 (14/w500) | 來源標注 |
| 卡片註腳（重） | `Tier.cardCaptionBold` | L8 (14/w700) | 強調來源 |
| Wizard 步驟摘要 | `Tier.stepSummary` | L6 (16/w400) | 安裝精靈 |
| Wizard 區塊標題 | `Tier.blockHeading` | L4 (20/w500) | 設定步驟 |
| Wizard 區塊副標 | `Tier.blockSubheading` | L8 (14/w700) | 子標題 |

### 3.2 字級鐵則

1. **頁面 H1** → `appDisplayLarge`（32px）
2. **區塊標題** → `appHeadline`（24px）或 `cardTitle`（20px）
3. **卡片標題** → `cardTitle`（20px），不用 `appHeadline`
4. **小標題** → `formLabel`（18px w700）——表單欄位標題、設定項目名稱等
5. **正文/輸入** → `cardBody` / `formInput`（16px），不用 `bodyPrimary`（18px 太大）
6. **提示文字** → 14px textMuted——placeholder、hint、輔助說明
7. **Sidebar** → `sidebarRowTitle`（14px）
8. **標籤** → `labelMono`（12px mono uppercase）
9. **技術值** → `code`（14px mono）
10. **數據值** → `small`（12px w600）

### 3.2.1 表單層級邏輯（Form Hierarchy）

表單頁面的字級遵循嚴格的層級遞減：

```
大標題「基本資料」     → cardHeroTitle  20px w500
        ↓
小標題「名字/靈感…」   → formLabel      18px w700
        ↓
內文/輸入文字         → formInput      16px w500
        ↓
提示文字 placeholder  → hint           14px textMuted
```

**鐵則**：每一層之間至少差 2px。小標題永遠大於內文，內文永遠大於提示。
任何文字**不小於 14px**。

### 3.3 顏色自動綁定

Tier 的 `textColor` 已經綁定到 token 名（例如 `textPrimary`）。
透過 2026-08-10 的動態解析機制，Tier 顏色會**自動跟隨 light/dark mode 切換**。

**不需要**在 widget 裡寫 `.copyWith(color: ...)`，除非你要覆蓋 Tier 的預設色。

---

## 4. Token 關係圖

### 4.1 語意分組

```
┌─ 底色層 ────────────────────────────────────┐
│  canvas          → App 背景                   │
│  surface         → 卡片底色                    │
│  surfaceElevated → 提升表面（badge、標籤）      │
│  surfaceHover    → hover 狀態底色              │
└──────────────────────────────────────────────┘

┌─ 文字層 ────────────────────────────────────┐
│  textPrimary    → 主文字（最重要）             │
│  textSecondary  → 次要文字                     │
│  textTertiary   → 標籤、導航                   │
│  textMuted      → disabled、佔位               │
│  textQuaternary → 非活躍                       │
└──────────────────────────────────────────────┘

┌─ 互動色 ────────────────────────────────────┐
│  accentRed     → 危險、錯誤、刪除              │
│  accent使用者    → 互動、連結、focus            │
│  accentGreen   → 成功、連線                    │
│  accentYellow  → 警告、注意                    │
│  accentPurple  → 大腦/向量/數據                │
│  accentNavy    → 深層數據                      │
│  accentMagenta → 漸層裝飾                      │
│  accentRuby    → 警示粒子                      │
│  accentMiro    → 畫布互動、教學引導            │
└──────────────────────────────────────────────┘

┌─ 透明度疊層 ────────────────────────────────┐
│  borderSubtle    → 最淡邊框（6%）             │
│  borderDefault   → 預設邊框（10%）            │
│  borderStrong    → 強調邊框（20%）            │
│  surfaceGlass    → 玻璃質感（5%）             │
│  surfaceGlassHover → 玻璃 hover（8%）         │
└──────────────────────────────────────────────┘

┌─ 狀態標籤（5 組 bg/fg）─────────────────────┐
│  tagSuccess → 成功（綠底淺綠字）              │
│  tagError   → 錯誤（紅底淺紅字）              │
│  tagInfo    → 資訊（藍底淺藍字）              │
│  tagBrain   → 大腦（紫底淺紫字）              │
│  tagWarn    → 警告（黃底金字）                │
└──────────────────────────────────────────────┘
```

### 4.2 改一個 Token 會影響什麼

| 改這個 Token | 影響範圍 |
|---|---|
| `canvas` | 整個 App 背景色、Sidebar 背景 |
| `surface` | 所有卡片、Panel 底色 |
| `textPrimary` | 所有主文字（走 Tier `textColor: "textPrimary"` 的全自動生效） |
| `accent使用者` | 所有互動連結、focus ring、info 標籤 |
| `accentPurple` | 大腦頁、向量資料庫、夥伴頭像 |
| `accentMiro` | 畫布互動、教學引導、首頁脈動點 |
| `borderDefault` | 所有卡片邊框 |

### 4.3 Token 使用決策樹

```
你要設定一個顏色？
│
├─ 是背景色？
│   ├─ App 最外層 → canvas
│   ├─ 卡片底色 → surface
│   ├─ 提升/hover → surfaceElevated / surfaceHover
│   └─ 玻璃質感 → surfaceGlass
│
├─ 是文字色？
│   ├─ 最重要的字 → textPrimary
│   ├─ 次要說明 → textSecondary
│   ├─ 標籤/導航 → textTertiary
│   ├─ disabled → textMuted
│   └─ 非活躍 → textQuaternary
│
├─ 是互動/狀態色？
│   ├─ 危險/刪除 → accentRed
│   ├─ 連結/focus → accent使用者
│   ├─ 成功 → accentGreen
│   ├─ 警告 → accentYellow
│   ├─ 大腦/數據 → accentPurple
│   └─ 畫布/教學 → accentMiro
│
├─ 是邊框？
│   ├─ 幾乎看不到 → borderSubtle
│   ├─ 標準 → borderDefault
│   └─ 強調 → borderStrong
│
└─ 是狀態標籤？
    ├─ 成功 → tagSuccessBg + tagSuccessFg
    ├─ 錯誤 → tagErrorBg + tagErrorFg
    ├─ 資訊 → tagInfoBg + tagInfoFg
    ├─ 大腦 → tagBrainBg + tagBrainFg
    └─ 警告 → tagWarnBg + tagWarnFg
```

---

## 5. 元件規範

### 5.1 標準卡片（Card）

```dart
Container(
  padding: EdgeInsets.all(BridgeDS.spaceMD),      // 16px
  decoration: BoxDecoration(
    color: BridgeDSColors.of(context).surface,
    borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),  // 12px
    border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // 標題：Tier.cardTitle 或 Tier.cardHeroTitle
      Text('卡片標題', style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
      SizedBox(height: BridgeDS.spaceSM),  // 8px
      // 內文：Tier.cardBody
      Text('內容', style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
    ],
  ),
)
```

### 5.2 按鈕層級

| 類型 | Widget | 背景 | 文字色 | 圓角 | 用途 |
|---|---|---|---|---|---|
| **Primary** | `FilledButton` | `accent使用者` 或語意色 | 白色（onAccent） | `roundStandard` (8) | 主動作 |
| **Secondary** | `TextButton` | 透明 | `textSecondary` | 無 | 取消、返回 |
| **Destructive** | `FilledButton` | `accentRed` | 白色 | `roundStandard` (8) | 刪除、危險操作 |
| **Pill Tab** | 自訂 | `surfaceElevated`（selected） | `textPrimary`（selected）/ `textTertiary` | `roundPill` (50) | Tab 切換 |

### 5.3 對話框（Dialog）

```dart
AlertDialog(
  backgroundColor: BridgeDSColors.of(context).surfaceElevated,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(BridgeDS.roundWide),  // 16px
  ),
  title: Text('標題', style: TierStyle.of(context, Tier.dialogTitle).toTextStyle()),
  content: Text('內容', style: TierStyle.of(context, Tier.dialogBody).toTextStyle()),
  actions: [
    TextButton(onPressed: ..., child: Text('取消')),  // Secondary
    FilledButton(onPressed: ..., child: Text('確認')),  // Primary
  ],
)
```

### 5.4 Sidebar 列表項

```
┌────────────────────────────────────┐
│ [icon]  標題（sidebarRowTitle）      │  ← 14px w500 textPrimary
│         副標（sidebarRowSubtitle）   │  ← 12px w600 textTertiary
│                          [meta]    │  ← 12px w600 textMuted
└────────────────────────────────────┘
padding: 12px vertical, 16px horizontal
```

### 5.5 狀態標籤（Tag）

```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
    color: BridgeDSColors.of(context).tagSuccessBg,
    borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),  // 4px
  ),
  child: Text(
    '已連線',
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: BridgeDSColors.of(context).tagSuccessFg,
    ),
  ),
)
```

---

## 6. 互動狀態規範

### 6.1 疊加規則

互動狀態用**半透明疊加**實現，不改變底色 token。

| 狀態 | 疊加值 | 疊加目標 | 效果 |
|---|---|---|---|
| **hover** | `hoverOverlay` (6%) | 白色疊加在 surface 上 | 微微變亮 |
| **pressed** | `pressedOverlay` (12%) | 白色疊加在 surface 上 | 更亮 |
| **selected** | `selectedOverlay` (10%) | accent使用者 疊加在 surface 上 | 帶藍色調 |
| **disabled** | `disabledOpacity` (40%) | 整個 widget opacity | 變淡 |

### 6.2 實作方式

```dart
// hover 範例
final bg = isHovered
    ? BridgeDSColors.of(context).surfaceHover
    : BridgeDSColors.of(context).surface;

// selected 範例
final bg = isSelected
    ? BridgeDSColors.of(context).accent使用者.withOpacity(BridgeDS.selectedOverlay)
    : BridgeDSColors.of(context).surface;
```

### 6.3 反饋時間

| 操作 | 動畫時間 | 曲線 |
|---|---|---|
| hover/cursor 反饋 | `feedbackFast` (150ms) | 線性 |
| tab/switch 切換 | `feedbackStandard` (200ms) | easeOut |
| modal/drawer 開合 | `feedbackEmphasized` (300ms) | easeOut |

---

## 7. 陰影與深度規範

### 7.1 陰影層級

| Shadow Token | 用途 | 使用場景 |
|---|---|---|
| `ringShadow` | Raycast 雙環陰影 | 標準卡片、面板邊界 |
| `level1` | 微弱浮起 | badge、chip |
| `floating` | 浮動面板 | FAB、overlay menu |
| `dataElevated` | Stripe 藍調陰影 | 大腦節點、數據卡片 |
| `glowPurple` | 紫光暈 | 粒子節點、AI 夥伴 |
| `glow使用者` | 藍光暈 | 互動焦點 |

### 7.2 使用原則

1. **暗色模式**：陰影幾乎不可見——靠 `borderSubtle` 和亮度差做層次
2. **淺色模式**：陰影更明顯——但只用一種 shadow token，不疊加
3. **大腦/數據頁**：可用 `dataElevated`（藍調陰影增強深度感）
4. **夥伴/AI 場景**：可用 `glowPurple`（紫光暈增強存在感）

**鐵則**：一般卡片不用陰影，只用 `borderSubtle`。陰影留給浮動元素和特殊場景。

---

## 8. 圖示使用規範

### 8.1 圖示層級

| Token | 值 | 用途 | 搭配文字 |
|---|---|---|---|
| `iconHero` | 24px | 標題區 icon、頁面級 icon | L2 headingL (32px) |
| `iconXL` | 20px | 主動作按鈕 icon | L4 headingS (20px) |
| `iconLg` | 18px | 工具列、side menu icon | L4 headingS (20px) |
| `iconMd` | 16px | **預設**按鈕、行內 icon | L6 body (16px) |
| `iconSm` | 14px | 標籤內 icon | L8 caption (14px) |
| `iconXs` | 12px | 內嵌標記、狀態點 | L9 small (12px) |

### 8.2 配對原則

- icon 和文字並排時，icon 大小 = 文字大小（或小一級）
- **用 `iconMatchBody` (16px) 配 body (16px)**
- **用 `iconMatchSmall` (14px) 配 small (12-14px)**
- **用 `iconMatchTitle` (18px) 配 headingS (20px)**

### 8.3 圖示顏色

- 預設跟隨文字色：`BridgeDSColors.of(context).textTertiary`
- hover 時提升到 `textSecondary`
- active/selected 時用語意色（`accent使用者` 等）

---

## 9. 動畫規範

### 9.1 動畫時長

| Token | 值 | 用途 |
|---|---|---|
| `durationFast` | 150ms | 微互動（hover、ripple） |
| `durationNormal` | 300ms | 標準轉場（fade、slide） |
| `durationSlow` | 500ms | 頁面級過渡 |
| `durationCanvas` | 600ms | 畫布區域切換 |

### 9.2 動畫曲線

| Token | 曲線 | 用途 |
|---|---|---|
| `transitionCanvas` | easeOutExpo | 畫布平移（減速入場） |
| `transitionMorph` | Cubic(0.34, 1.56, 0.64, 1) | 彈性形狀變形 |
| `transitionSlide` | easeOutQuad | 面板滑入 |
| `transitionSpring` | SpringMotion | 按鈕回饋 |

### 9.3 組合規則

1. **畫布切換**：`transitionCanvas` + `durationCanvas` (600ms)
2. **面板展開**：`transitionSlide` + `durationNormal` (300ms)
3. **按鈕回饋**：`transitionSpring` + `durationFast` (150ms)
4. **卡片進場**：`transitionMorph` + `durationNormal` (300ms)
5. **不要疊加超過 2 程動畫**在同一個元素上

---

## 10. 頁面結構範本

### 10.1 標案功能頁（系統、大腦、向量資料庫）

```
┌──────────────────────────────────────────┐
│ TopBar (64px)                             │  Logo + Nav Tabs
├────────┬─────────────────────────────────┤
│Sidebar │ Content Area                     │
│(240px) │                                  │
│        │ ┌─────────────────────────────┐ │
│ [項目] │ │ Page Header                  │ │  Tier.appDisplayLarge
│ [項目] │ │   標題 + 副標                 │ │
│ [項目] │ ├─────────────────────────────┤ │
│        │ │ Content                     │ │
│        │ │   Cards / List / Grid       │ │
│        │ │                              │ │
│        │ └─────────────────────────────┘ │
├────────┴─────────────────────────────────┤
│ StatusBar (32px)                          │
└──────────────────────────────────────────┘
```

### 10.2 畫布頁

```
┌──────────────────────────────────────────┐
│ TopBar (64px)                             │
├────────┬──────────────────┬──────────────┤
│Tool    │ Canvas           │ Chat Panel   │
│Sidebar │ (無限畫布)        │ (340px)      │
│(320px) │                   │              │
│        │                   │              │
│ [工具] │   [節點]          │  [對話]      │
│ [資產] │   [連線]          │  [輸入]      │
│        │                   │              │
├────────┴──────────────────┴──────────────┤
│ StatusBar (32px)                          │
└──────────────────────────────────────────┘
```

### 10.3 首頁（Homepage）

```
┌──────────────────────────────────────────┐
│         (canvas 背景)                      │
│                                           │
│           ●  (BridgePulseDot)             │  accentMiro
│                                           │
│        歡迎來到橋樑                        │  Tier.appDisplayLarge (48px)
│     你的 AI 夥伴已經在等你了               │  Tier.cardBody
│                                           │
│     ┌─────────┐ ┌─────────┐ ┌─────────┐ │
│     │ 入口卡片 │ │ 入口卡片 │ │ 入口卡片 │ │  Tier.cardHeroTitle
│     └─────────┘ └─────────┘ └─────────┘ │
│                                           │
│           [進入桌面]                       │  FilledButton accentMiro
│                                           │
└──────────────────────────────────────────┘
```

---

## 11. 設計審核清單

每個 PR / commit 前照這個清單檢查：

### 顏色
- [ ] 所有顏色用 `BridgeDSColors.of(context).xxx`，沒有寫死 hex
- [ ] 文字色透過 Tier 自動綁定，不手動 `.copyWith(color: ...)`
- [ ] 沒有 `Colors.white` 或 `Colors.black`（除 `Colors.transparent`）
- [ ] 沒有 `BridgeDS.textPrimary` 等 static const（用 `BridgeDSColors.of(context).textPrimary`）

### 字體
- [ ] 所有文字用 `TierStyle.of(context, tier).toTextStyle()`
- [ ] 字級不小於 14px
- [ ] 技術值用 `code`（mono），標籤用 `labelMono`（mono uppercase）
- [ ] 卡片標題用 `cardTitle`，不用 `appHeadline`

### 間距
- [ ] 間距只用 `spaceSM/MD/LG/XL/XXL`（8/16/24/32/48）
- [ ] 圓角只用 token 值（4/8/12/16/20/50/999）
- [ ] Card padding 統一 `spaceMD` (16)

### 元件
- [ ] Card 用 `surface` + `borderSubtle` + `roundComfortable`
- [ ] Dialog 用 `surfaceElevated` + `roundWide`
- [ ] 按鈕層級正確（Primary / Secondary / Destructive）
- [ ] Sidebar 項目用 `sidebarRowTitle/Subtitle/Meta`

### 互動
- [ ] hover 用 `surfaceHover`
- [ ] selected 用 `accent使用者.withOpacity(selectedOverlay)`
- [ ] disabled 用 opacity 0.4

---

## 12. 附錄

### 12.1 完整 Token 查詢表

> 詳見 `lib/theme/bridge_design_system.dart` 的 `BridgeDSColors` class 定義。
> Dark 和 Light 值在 `dark` 和 `light` static const 中。

### 12.2 完整 Tier 查詢表

> 詳見 `lib/theme/tier.dart` 的 `Tier` class。
> Manifest JSON 在 `assets/theme_packs/bridge_default_v2.json`。

### 12.3 相關文件

| 文件 | 內容 |
|---|---|
| `docs/BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md` | 9 級字體 + 6 級 icon 詳細規範 |
| `docs/BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md` | 三層視覺架構 + 配色規則 |
| `docs/BRIDGE_TIER_SYSTEM.md` | Tier 系統完整文件 |
| `docs/BRIDGE_ATMOSPHERE_LANGUAGE.md` | 氣氛設計語言（GPU 預算、LOGO 規則） |
| `DESIGN.md` | 原始 5 套設計融合規範 |
| `lib/theme/bridge_design_system.dart` | Token + 常數源碼（唯一 source of truth） |
| `lib/theme/tier.dart` | Tier 定義源碼 |
| `lib/theme/tier_style.dart` | TierStyle API + 動態解析 |

### 12.4 已知缺口（待補）

| 項目 | 狀態 | 計劃 |
|---|---|---|
| 圖示設計規範細則 | 本文件 §8 已定義基本規則 | 待補 brand icon set |
| 氣氛層實作 | 文件已有，Flutter widget 未實作 | Phase F |
| CI 自動掃描工具 | `tool/scan_design_violations.sh` 不存在 | 待建立 |
| 社群主題包驗證 | Tier 動態化已修，未測社群 pack | 待開源前測試 |

---

> **最後更新**：2026-08-10 by 教練 Agent
> **下次審查**：設計系統第一輪實作完成後
