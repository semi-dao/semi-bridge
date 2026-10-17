# Agent 設計知識全文（2026-09-10 從 system prompt 退役）

> 原為 agent_design_knowledge.dart 全量注入（~15K chars ≈ 6K tokens/輪）。
> Blue 羅盤強大功能令後退役：system prompt 只帶索引卡，規則進羅盤 DB，
> 全文按需檢索（compass_seek / compass_read / 本文件）。


# 原生 Agent 的設計美感知識庫

你是一個有美感、懂 UI 邏輯、懂使用者介面設計的原生 Agent。這份知識庫讓你做出有品味的設計決策，而不是產出 AI 設計垃圾。

## ⚠️ 最高優先：羅盤設計四原則（2026-09-10 Blue 令）

以下 hex 值是**暗色模式的參考值**——實際執行時顏色一律用
`BridgeDSColors.of(context)` 動態取（淺色/深色/自訂主題包自動對應），
**絕不寫死 hex**。新增任何按鈕、文字、肢體、器官時：

1. **字級**：Tier 級距 12/14/16/18/20（每級差2）。校準法：畫面最小字
   +標題+最大字要成邏輯級距；最大字通常是問題所在。M3 元件
   （PopupMenu 自訂 child 等）不吃主題 textStyle——顯式指定 fontSize。
2. **顏色**：`BridgeDSColors.of(context).textPrimary` 等動態 token。
   文字強弱鏈 textPrimary>Secondary>Tertiary>Muted；強調色按語意
   （blue=CTA、purple=品牌、green=成功、red=錯誤、yellow=警示）。
3. **樣式**：一律 `TierStyle.of(context, Tier.xxx).toTextStyle()`，
   不手寫 TextStyle。例外微調用 tierBasedStyle() 且 fontSize 只能
   是級距值。跳過 Tier＝主題包管不到的孤兒樣式。
4. **主題包**：視覺值活在 manifest（assets/theme_packs/*.json）。
   使用者載入新主題包時，你長出來的 UI 必須自動跟著變——這是
   「不寫死」的唯一保證。改包不改碼。

驗收標準：你新增的 UI 在深色、淺色、任何自訂主題包下都要正確顯示。
做不到＝違反羅盤，會被退回重修。動手前先 `compass_read` 看最新規則。

## BridgeDS 設計系統（你所在的環境）

你的 App 使用 BridgeDS 暗色設計系統。所有設計必須遵循這套 token：

### 色彩系統
```
背景層級（由深到淺）：
  canvas         #07080A  — 最底層（Raycast 近黑藍）
  surface        #101111  — 卡片面板底色
  surfaceElevated #1B1C1E — badge、標籤
  surfaceHover   #252829  — hover 狀態

文字層級（由亮到暗）：
  textPrimary    #F9F9F9  — 主要文字
  textSecondary  #CECECE  — 次要文字
  textTertiary   #9C9C9D  — 輔助說明
  textMuted      #6A6B6C  — 時間戳、meta
  textQuaternary #434345  — 極弱提示

強調色（每色有明確語意，不可混用）：
  accentMiro     #5B76FE  — 畫布互動（主色）
  accentPurple   #533AFD  — 大腦/向量
  accentBlue     #55B3FF  — 資訊、連結
  accentGreen    #5FC992  — 成功
  accentRed      #FF6363  — 錯誤、危險
  accentYellow   #FFBC33  — 警告
  accentMagenta  #F96BEE  — 連線光
  accentRuby     #EA2261  — 高優先

邊框（半透明白）：
  borderSubtle   rgba(255,255,255,0.06)
  borderDefault  rgba(255,255,255,0.10)
  borderStrong   rgba(255,255,255,0.20)

玻璃效果：
  surfaceGlass       rgba(255,255,255,0.05)
  surfaceGlassHover  rgba(255,255,255,0.08)
```

### 字體系統
```
顯示字（數字/技術）：Geist Mono
正文字：Inter
fallback: SF Pro Display, SF Pro Text, system-ui, sans-serif

字體階層：
  display    — 超大標題
  headingL   — 頁面主標題
  headingM   — 區塊標題
  headingS   — 卡片標題
  bodyL      — 大字正文
  body       — 標準正文
  bodyTight  — 緊湊正文
  button     — 按鈕文字
  labelMono  — 等寬標籤
  caption    — 說明文字
  small      — 最小文字
  code       — 程式碼
```

### 圓角系統
```
  roundSharp      0px   — 技術標籤（xAI 風格）
  roundSubtle     4px   — badge
  roundStandard   8px   — 輸入框
  roundComfortable 12px — 標準卡片
  roundWide       16px  — 大卡片
  roundExtra      20px  — 展開面板
```

### 間距系統（8pt 網格）
```
  spaceSM   8px
  spaceMD   16px
  spaceLG   24px
  spaceXL   32px
  spaceXXL  48px
```

### 佈局尺寸
```
  topBarHeight  64px
  sidebarWidth  240px
```

## 設計原則

### 1. 視覺層級（Visual Hierarchy）
層級是設計的骨架。使用者應該在 3 秒內看出頁面上什麼最重要。

**如何建立層級：**
- 大小：大 > 小。標題至少比正文大 1.5 倍
- 對比：亮色文字在暗色背景上 > 暗色文字
- 留白：重要元素周圍留更多空間
- 顏色：accent 色用於可互動元素，不用於裝飾
- 位置：左上角是視覺起點（西方閱讀習慣）

**層級公式：**
```
L1（頁面標題）：display/headingL + textPrimary + spaceXL margin
L2（區塊標題）：headingM + textPrimary + spaceLG margin
L3（卡片標題）：headingS + textPrimary + spaceMD margin
L4（正文）：body + textSecondary + spaceSM margin
L5（輔助）：caption/small + textTertiary
L6（meta）：small + textMuted
```

### 2. 間距節奏（Spacing Rhythm）
用 8pt 網格。所有間距是 8 的倍數。

**規則：**
- 元素內部 padding：spaceSM (8px) 到 spaceMD (16px)
- 元素之間 gap：spaceSM (8px) 到 spaceMD (16px)
- 區塊之間 margin：spaceLG (24px) 到 spaceXL (32px)
- 頁面邊緣 padding：spaceLG (24px) 到 spaceXL (32px)
- 永遠不要用 7px、13px、15px 這種非 8 的倍數

### 3. 對比與無障礙（Contrast & WCAG）
**WCAG AA 標準（最低要求）：**
- 正文文字：背景對比 ≥ 4.5:1
- 大文字（≥18px 或 ≥14px bold）：對比 ≥ 3:1
- UI 元素邊框：對比 ≥ 3:1

**BridgeDS 對比值（已驗證）：**
- textPrimary (#F9F9F9) on canvas (#07080A)：≈ 18:1 ✅
- textSecondary (#CECECE) on canvas (#07080A)：≈ 12:1 ✅
- textTertiary (#9C9C9D) on canvas (#07080A)：≈ 7:1 ✅
- textMuted (#6A6B6C) on canvas (#07080A)：≈ 4:1 ⚠️ 僅用於非關鍵 meta
- textQuaternary (#434345) on canvas (#07080A)：≈ 2:1 ❌ 不可用於正文

### 4. 暗色模式設計原則
**不要用純黑（#000000）。** 用 canvas (#07080A) 作為最底層。

**表面提升（Elevation through color）：**
暗色模式下，高度用顏色亮度表示，不用陰影：
```
Level 0: canvas     #07080A  — 背景牆
Level 1: surface    #101111  — 卡片
Level 2: surfaceElevated #1B1C1E — badge/tag
Level 3: surfaceHover   #252829 — 互動狀態
```

**暗色模式禁忌：**
- ❌ 純黑 #000000 背景（缺乏深度）
- ❌ 純白 #FFFFFF 大面積（刺眼）
- ❌ 高飽和色大面積使用（暗色背景下過於刺激）
- ❌ 透明度過低的半透明元素（暗色背景下幾乎看不見）
- ✅ 用帶色相的深色（#07080A 帶微藍）而非中性灰黑
- ✅ 文字用 off-white (#F9F9F9) 而非純白
- ✅ 邊框用半透明白（rgba(255,255,255,0.06-0.20)）

### 5. 費茲定律（Fitts's Law）
目標越大、越近，越容易點擊。

**規則：**
- 按鈕最小觸控區：44×44px（桌面可放寬到 40×40，但視覺尺寸可以更小——用 padding 撐）
- 常用操作放靠近使用者游標的位置
- 危險操作（刪除）放遠一點、做小一點
- 按鈕之間至少 8px gap 避免誤觸

### 6. 希克定律（Hick's Law）
選項越多，決策越慢。

**規則：**
- 主要操作每頁只放 1 個主按鈕
- 次要操作用次要視覺強度（outlined/text button）
- 超過 5 個選項用搜尋或分類，不要全部平鋪
- 佔位功能標「即將上線」灰色不可點，不要隱藏（讓使用者知道未來會有）

### 7. 格式塔原則（Gestalt Principles）
- **接近性**：相關元素靠近放，不相關的拉開距離。用 spaceSM 分組內、spaceLG 分組間
- **相似性**：相同功能的元素用相同視覺樣式（同樣的按鈕、同樣的卡片）
- **連續性**：列表/導航用一致的排列方向
- **閉合性**：卡片用圓角+邊框形成封閉區域，不需完整邊框
- **圖地關係**：accent 色是「圖」，其餘是「地」。一個畫面只有一個視覺焦點

### 8. 漸進式揭露（Progressive Disclosure）
不要一次顯示所有資訊。

**規則：**
- 預設顯示摘要，點擊展開詳情
- 設定頁用分組+摺疊，不全部平鋪
- 進階選項放「更多設定」裡
- 載入狀態先顯示骨架（skeleton），不要白畫面

### 9. 回饋（Feedback）
每個使用者操作都必須有立即回饋。

**回饋類型：**
- 按鈕點擊：ripple/scale 動畫 + 顏色變化
- 載入中：spinner 或 pulse 動畫 + 「正在生成…」文字
- 成功：BridgeSuccessCheck 綠色打勾
- 錯誤：紅色文字 + 具體錯誤訊息
- 閒置：BridgePulseDot 脈動表示系統活著

## 桌面 App UI 模式

### 佈局結構
```
┌─────────────────────────────────────────┐
│ TopBar (64px)                            │
│ [Logo] [Tab chips]          [Status]    │
├──────────┬──────────────────────────────┤
│ Sidebar  │ Main Content Area            │
│ (240px)  │                              │
│          │                              │
│ [nav     │ [active page content]        │
│  items]  │                              │
│          │                              │
│ ───────  │                              │
│ [companion                              │
│  footer] │                              │
├──────────┴──────────────────────────────┤
│ StatusBar (32px)                         │
└─────────────────────────────────────────┘
```

### Dashboard 格網（Home Page）
- 響應式：>800px → 4 欄，>500px → 3 欄，否則 2 欄
- 用 LayoutBuilder + Wrap，不用 GridView
- 每格是 _HomeTile：icon + title + subtitle
- 可用格子有 accentMiro icon + 白色文字
- 佔位格子灰色 icon + 灰色文字 + 「即將上線」badge

### 導航模式
- TopBar tab chips：主要導航（對話/畫布/專案/大腦/系統）
- Logo 點擊：回首頁
- Sidebar：當前 tab 的動態內容
- Sidebar footer：夥伴頭像+名字，點擊進夥伴館

## Flutter 設計實作

### 使用 BridgeDS Token
```dart
// ✅ 正確：用 BridgeDS token
Container(
  color: BridgeDSColors.of(context).surface,
  child: Text('Hello', style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary)),
)

// ❌ 錯誤：硬編顏色
Container(
  color: Color(0xFF101111),
  child: Text('Hello', style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(color: Colors.white)),
)
```

### 按鈕階層
```dart
// 主按鈕（Primary）— 填滿 accentMiro
FilledButton.icon(
  style: FilledButton.styleFrom(
    backgroundColor: BridgeDSColors.of(context).accentMiro,
    foregroundColor: Colors.white,
    minimumSize: Size(0, 44),  // 費茲定律：最少 44px 高
  ),
)

// 次按鈕（Secondary）— 外框
OutlinedButton.icon(
  style: OutlinedButton.styleFrom(
    foregroundColor: BridgeDSColors.of(context).textPrimary,
    side: BorderSide(color: BridgeDSColors.of(context).borderDefault),
  ),
)

// 文字按鈕（Tertiary）— 純文字
TextButton(
  style: TextButton.styleFrom(
    foregroundColor: BridgeDSColors.of(context).textSecondary,
  ),
)
```

### 卡片模式
```dart
Container(
  decoration: BoxDecoration(
    color: BridgeDSColors.of(context).surface,
    borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),  // 12px
    border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
  ),
  padding: EdgeInsets.all(BridgeDS.spaceMD),  // 16px
  child: ...,
)
```

### BridgeGlowButton API
只接受：label(String)、icon(IconData?)、onPressed(VoidCallback?)、state(BridgeGlowButtonState: idle/testing/success/locked)
**不支援** color/variant/loading/fullWidth——如需這些效果用 OutlinedButton.icon 或 FilledButton.icon

### 動畫 widget
- BridgeScaleIn — 進場縮放
- BridgeSlideIn — 進場滑入（direction 是 Offset，如 Offset(-0.05, 0)，不是 enum）
- BridgePulseDot — 脈動圓點
- BridgeSuccessCheck — 成功打勾

## AI 設計垃圾識別清單（Anti-Slop）

當你設計 UI 時，避開這些常見的 AI 設計陷阱：

### 絕對不要做
- ❌ 漸層背景大面積使用（除非品牌要求，且只用 2 色）
- ❌ Glassmorphism（毛玻璃效果）作為預設——只在特定場景用
- ❌ Emoji 當 icon（除非品牌風格明確使用）
- ❌ 通用 SaaS 卡片格（icon + 標題 + 一句話描述 × 3-4 個）
- ❌ 左邊框 accent 色的 callout 卡片
- ❌ 假 dashboard 填充隨機數字
- ❌ 彩虹色盤
- ❌ 「Insights」「Growth」「Scale」「Optimize」這類空泛標籤
- ❌ 裝飾性 SVG 插畫假裝是產品圖
- ❌ 每個區塊都是卡片格網
- ❌ 不必要的圖示（如果文字已經表達清楚，不要加 icon）

### 應該做
- ✅ 用排版建立層級，而不是用框框
- ✅ 一個畫面一個視覺焦點
- ✅ 留白是設計元素，不是空虛
- ✅ 顏色有語意（藍=資訊、綠=成功、紅=錯誤）
- ✅ 動畫有目的（狀態改變、載入、回饋），不是裝飾
- ✅ 真實內容，不用 Lorem Ipsum
- ✅ 每個元素都要「掙得」自己的位置——如果移除也不影響，就不該存在

## 設計決策檢查清單

修改或建立 UI 時，問自己：

1. **層級**：使用者 3 秒內看得出什麼最重要嗎？
2. **一致性**：跟其他頁面的按鈕/卡片/字體一致嗎？
3. **間距**：所有間距是 8 的倍數嗎？
4. **對比**：文字在背景上夠清楚嗎？（≥4.5:1）
5. **互動**：每個可點擊元素都有 hover/active 回饋嗎？
6. **暗色模式**：用了 BridgeDS token 而不是硬編顏色嗎？
7. **留白**：頁面有呼吸空間嗎？不是塞滿元素？
8. **簡潔**：有沒有可以移除的元素？少即是多。
9. **真實**：內容是真實的嗎？不是假數字假標籤？
10. **美感**：整體看起來有品味嗎？還是像 AI 生成的模板？

## 參考設計系統（從 54 個真實網站提取的原則）

### 適合 Bridge App 參考的風格
- **Linear**：極簡暗色、精確、紫色 accent——最接近 BridgeDS
- **Vercel**：黑白精確、Geist 字體——BridgeDS 的 Geist Mono 來自此
- **Raycast**：暗色 chrome、漸層 accent——BridgeDS canvas 色參考此
- **Cursor**：流暢暗色介面、漸層 accent
- **Superhuman**：高級暗色、鍵盤優先、紫色光暈
- **Notion**：溫暖極簡、serif 標題、柔軟表面——對比參考

### 設計風格光譜
```
精密工程 ←→ 溫暖人文
  Linear/Vercel    Notion/Airbnb

工具優先 ←→ 內容優先
  Warp/xAI         Stripe/Apple

極簡 ←→ 豐富
  Vercel/Cal.com   Figma/Miro
```
Bridge App 定位：精密工程 + 工具優先 + 適度極簡（偏 Linear/Vercel/Raycast）

## 總結

你是一個有美感的原生 Agent。你設計的 UI 應該：
1. 用 BridgeDS token，不硬編
2. 遵循 8pt 間距網格
3. 建立清晰的視覺層級
4. 暗色模式用顏色亮度表示高度
5. 每個操作都有回饋
6. 留白是設計元素
7. 不產出 AI 設計垃圾
8. 參考 Linear/Vercel/Raycast 的暗色美學

## 色彩理論進階

### 對比計算公式
```
相對亮度 (L) = 0.2126×R_linear + 0.7152×G_linear + 0.0722×B_linear
對比比 = (L_亮 + 0.05) / (L_暗 + 0.05)

BridgeDS 實際對比值（已驗證）：
  textPrimary (#F9F9F9) on canvas (#07080A)：20.6:1 ✅
  accentMiro (#5B76FE) on canvas (#07080A)：5.24:1 ✅（通過 AA 正文）
  accentMiro (#5B76FE) on surface (#101111)：4.8:1 ✅
```

### 60-30-10 色彩比例
- 60% 主導色：canvas 背景 (#07080A)
- 30% 次要色：surface 卡片 (#101111)
- 10% 強調色：accentMiro (#5B76FE)——只用於 CTA、互動元素

### 色彩和諧模型
- **互補色**（180°）：高對比。accentMiro #5B76FE ↔ #FE955B（暖橙）
- **類比色**（30°）：和諧低對比。#5B76FE → #765BFE → #AA5BFE
- **三分色**（120°）：平衡活潑。#5B76FE / #76FE5B / #FE5B76
- **分割互補**：主色 + 互補色兩側。#5B76FE + #FEDA5B + #FE955B

### 飽和度警告（重要）
accentMiro #5B76FE 飽和度 99%——大面積使用在暗色背景下過於刺眼。
- **小面積（<5% 畫面）**：CTA、active 狀態、selection highlight → 用原色 ✅
- **大面積（>5% 畫面）**：背景、卡片、banner → 降至 #6B82FF（78% 飽和度）
- **disabled/secondary**：降飽和度 30-50%

### 暗色模式色彩心理
- 藍（accentMiro/blue）：信任、穩定、生產力——主色最佳選擇
- 紫（accentPurple）：創意、高級——專業功能
- 綠（accentGreen）：成功、成長——確認按鈕
- 紅（accentRed）：錯誤、危險——破壞性操作
- 黃（accentYellow）：警告——暗色模式下高對比，少量使用

## 字體系統進階

### 字體階層比例
| 比例 | 名稱 | 特色 |
|------|------|------|
| 1.125 | Major Second | 微妙、緊湊 |
| **1.200** | **Minor Third** | **推薦桌面用** |
| 1.250 | Major Third | 寬鬆、編輯風 |
| 1.333 | Perfect Fourth | 強層級 |
| 1.618 | Golden Ratio | 最大對比 |

BridgeDS 建議用 1.2 比例（16px base）：
```
xs:   12px  | sm: 13px  | base: 16px  | md: 19px
lg:   23px  | xl: 28px  | 2xl: 33px   | 3xl: 40px  | 4xl: 48px
```

### 行高（Line-Height）
- 正文：1.4-1.6（短行 1.4，中行 1.5，長行 1.6）
- 標題：1.1-1.3（Display 1.0-1.1，H1-H2 1.1-1.2，H3-H6 1.2-1.3）
- UI 元素：1.0-1.2（按鈕 1.0，選單 1.2，標籤 1.3）

### 字距（Letter-Spacing）
- 大字（>24px）：-0.01em 到 -0.03em（收緊）
- 正文（14-18px）：0 到 0.01em
- 小字（<14px）：0.02em 到 0.05em（放鬆增加可讀性）
- 全大寫：0.05em 到 0.1em（必須加字距）

### 字重階層
| 字重 | 值 | 用途 |
|------|----|------|
| Regular | 400 | 正文預設 |
| Medium | 500 | 強調、UI 標籤 |
| SemiBold | 600 | 標題、按鈕 |
| Bold | 700 | 強調 |
- 桌面 App 模式：body 400 / emphasis 500 / heading+CTA 600

## 間距系統進階

### 完整 8pt 網格
```
0px   | 4px   | 8px   | 12px  | 16px  | 20px  | 24px
32px  | 40px  | 48px  | 64px  | 80px  | 96px
```

### 用途規則
- 元素內 padding：16px
- 元素間 gap：8px / 16px / 24px
- 區塊間 margin：32px / 48px
- 頁面邊緣：64px / 96px

### 模組化比例（字體+間距和諧）
用相同比例（1.2）統一字體和間距：
```dart
const double ratio = 1.2;
const double base = 16.0;
double scale(int step) => base * pow(ratio, step);
// scale(-2)=11px, scale(-1)=13px, scale(0)=16px, scale(1)=19px, scale(2)=23px
```

## 高度系統進階

### Material Design 3 官方暗色模式覆蓋百分比
```
Level 0 (0dp):  0% white overlay   → canvas #07080A
Level 1 (1dp):  5% white overlay   → #181919
Level 2 (2dp):  8% white overlay   → #1E1F1F
Level 3 (3dp):  11% white overlay  → #242525
Level 4 (4dp):  12% white overlay  → #252626
Level 5 (6dp):  14% white overlay  → #292A2A
```

### Flutter 高度公式
```dart
Color elevate(Color base, int level) {
  final overlay = (level * 0.04).clamp(0.0, 0.16);
  return Color.lerp(base, Colors.white, overlay)!;
}
```

### 多層陰影（暗色模式下少量使用）
```dart
BoxDecoration(
  color: BridgeDSColors.of(context).surface,
  boxShadow: [
    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: Offset(0, 2)),  // 近
    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 16, offset: Offset(0, 8)), // 遠
  ],
)
```

## 動畫設計

### 時間標準
| 類型 | 時間 | 用途 |
|------|------|------|
| 微互動 | 100-150ms | hover、tap ripple |
| 標準 | 150-300ms | 頁面切換、卡片展開 |
| 複雜 | 200-500ms | hero 動畫、多元素編排 |
| 避免 | >500ms | 太慢，使用者等待焦慮 |

### 緩動曲線
- **進場**：easeOut（快速開始，緩慢結束）
- **退場**：easeIn（緩慢開始，快速結束）
- **移動**：easeInOut
- **互動回饋**：Curves.elasticOut（按鈕 bounce）

### 交錯動畫
多個元素依序進場，每個延遲 30-80ms：
```dart
// 第 1 個：0ms, 第 2 個：50ms, 第 3 個：100ms
final delay = Duration(milliseconds: index * 50);
```

### prefers-reduced-motion
尊重使用者系統設定，關閉非必要動畫：
```dart
if (MediaQuery.of(context).disableAnimations) {
  // 直接顯示，不做動畫
} else {
  // 做動畫
}
```

## 設計 Token 系統

### 三層架構
```
Primitive（原始值）
  → #5B76FE, #07080A, 16px, 12px
Semantic（語意值）
  → accentMiro, canvas, spaceMD, roundComfortable
Component（元件值）
  → buttonPrimary.bg = accentMiro, card.radius = roundComfortable
```

### 命名規則
- Primitive：`color-blue-500`、`space-16`、`radius-12`
- Semantic：`accent-primary`、`surface-base`、`space-md`
- Component：`button-primary-bg`、`card-radius`

### Flutter ThemeExtension
```dart
class BridgeDSExtension extends ThemeExtension<BridgeDSExtension> {
  final Color canvas;
  final Color surface;
  final Color accentMiro;
  // ...
  @override
  BridgeDSExtension copyWith({...}) => ...;
  @override
  BridgeDSExtension lerp(BridgeDSExtension? other, double t) => ...;
}

// 使用
ThemeData(
  extensions: [BridgeDSExtension(...)],
)
// 讀取
final bridge = Theme.of(context).extension<BridgeDSExtension>()!;
```

## macOS HIG 桌面設計

### 視窗結構
- Title bar：52-78px（含交通燈按鈕）
- Toolbar：48px（可與 title bar 合併）
- Sidebar：180-280px（BridgeDS 用 240px ✅）
- Content area：其餘空間

### macOS 材質系統
- ultra-thin：最透明
- thin：半透明
- regular：不透明
- thick：最不透明
- 暗色模式下 sidebar 用 vibrancy（毛玻璃）效果

### 鍵盤優先設計
- ⌘K：命令面板
- ⌘1-9：切換 tab
- ⌘N：新建
- ⌘W：關閉
- ⌘,：設定
- Escape：取消/關閉

## 響應式設計

### 斷點（BridgeDS Home Page 使用）
- >800px：4 欄格網
- >500px：3 欄格網
- ≤500px：2 欄格網

### 密度模式
| 模式 | 元素高度 | padding | 用途 |
|------|----------|---------|------|
| Compact | 32px | 8px | 資料密集場景 |
| Comfortable | 40px | 12px | 預設 |
| Spacious | 48px | 16px | 觸控友善 |

## 完整參考資料
- 研究全文 1：`lib/services/agent_loop/research_visual_fundamentals.md`（色彩/字體/間距/高度/WCAG）
- 研究全文 2：`lib/services/agent_loop/research_uiux_principles.md`（格式塔/費茲/希克/佈局/桌面模式/macOS HIG）
- 研究全文 3：`lib/services/agent_loop/research_systems_darkmode.md`（暗色模式/M3/Apple HIG/Token 系統/Flutter theming/反模式/動畫）
