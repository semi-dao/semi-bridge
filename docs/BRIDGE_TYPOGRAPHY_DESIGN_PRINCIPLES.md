# 橋樑排版設計原則 (Bridge Typography Design Principles)

> **版本**：v1.1 · 2026-08-05
> **作者**：使用者 + 教練 Agent（共同定稿）
> **狀態**：正式啟用
> **更新**：v1.1 新增 48 個 BridgeDS color token、12 個 Tier token（階段 A/B/C/D 收斂成果）
> **取代**：DESIGN.md v0.x 散落在 lib/theme/bridge_design_system.dart 內的 inline 註解
> **適用範圍**：橋樑 App 桌面版（macOS / Windows / Linux）

> **📱 手機版刪除宣告（2026-08-10）**：
> - 手機版已正式宣告刪除，本設計原則專注於桌面版體驗
> - 未來手機版將重新設計，可能調整級距以適應行動裝置
> - 手機版相關檔案已封存，不影響桌面版開發

---

## 📜 緣起

橋樑 App 從 2026-04 開始，已累積 5 套設計系統的混血：
- **xAI** 深色科技氛圍
- **Raycast** 色彩質感
- **Stripe** 向量粒子
- **Figma** 動態活潑
- **Miro** 無限畫布連續感

過去這些規則散落在 `lib/theme/bridge_design_system.dart` 註解裡，沒有正式名稱，也沒有可被外部社群擴充的介面。

經過畫布頁（`brain_canvas.dart`）的實戰驗證後，使用者 於 2026-08-04 決定：

> 「畫布頁面裡面的文字大小跟配色原則以及主題的切換，是我目前覺得最舒服的模式。我們要把這個模式**正式命名**為**橋樑排版設計原則**，並且**設計成可以讓未來開源社群下載主題包**。」

本文檔就是這個決策的正式記錄。

---

## 🎯 一、字體大小（Font Scale）

> **核心精神**：視覺節奏感，**禁止散亂尺寸**。

只有 **9 個級距**，全部必須從這 9 個選，禁用其他任何尺寸。

| Token | 數值 | 用途 |
|---|---|---|
| `display` | 48 | 頁面 hero 數字（dashboard KPI） |
| `headingL` | 32 | 區塊大標題 |
| `headingM` | 24 | 子區塊標題 |
| `headingS` | 20 | 卡片標題 |
| `bodyL` | 18 | 重要內文（alert 重點、畫布節點標題） |
| `body` | 16 | 對話泡泡主文、輸入框、表單欄位 |
| `button` | 14 | 按鈕標籤 |
| `caption` | 14 | metadata、tag、狀態文字 |
| `small` | 14 | 同 caption，用於 metadata |

### ❌ 禁用字體大小

```
10, 11, 12, 13, 15, 17, 19, 21, 22, 23, 25, 26, 27, 28, 29, 30, 31
```

**原因**：
1. 非設計級距、視覺上會感覺「散亂」
2. 對最小可讀性也不友好
3. 桌機不應小於 14（2026-08-03 用戶決策：最小不能低於 14）

### ✅ 對應表

| 使用場景 | Token |
|---|---|
| 對話泡泡主文 | `body` (16) |
| 輸入框文字 | `body` (16) |
| 按鈕標籤 | `button` (14) |
| 表單欄位標題 | `body` (16) |
| 表單欄位說明 | `caption` (14) |
| 卡片標題 | `headingS` (20) |
| 區塊大標題 | `headingM` (24) |
| 頁面 hero 數字 | `display` (48) |
| 畫布節點標題 | `bodyL` (18) |

### 📊 視覺層級圖（Visual Hierarchy）

從最大（頁面級）到最小（元件級）的層級關係：

```
頁面級 ────────── display  (48)  ← 頁面 hero 數字，整頁只出現 1-2 個
                  │
                  ├── 區塊級 ── headingL (32)  ← 區塊大標題（如「設計原則」標題）
                  │            │
                  │            ├── 子區塊級 ── headingM (24)  ← 子區塊標題（如「字體大小」）
                  │            │              │
                  │            │              ├── 卡片級 ── headingS (20)  ← 卡片標題
                  │            │              │           │
                  │            │              │           ├── 重要內文 ── bodyL (18)  ← alert、畫布節點
                  │            │              │           │              │
                  │            │              │           │              ├── 主要內文 ── body (16)  ← 對話、輸入框、表單
                  │            │              │           │              │            │
                  │            │              │           │              │            ├── 元件級 ── button (14)  ← 按鈕
                  │            │              │           │              │            │           ├── caption (14)  ← metadata、tag
                  │            │              │           │              │            │           └── small  (14)  ← 同 caption
```

#### 🎯 選字體的決策流程（以畫布頁 brain_canvas.dart 為 reference）

> **畫布頁參考模式**：整個 brain_canvas.dart 只有 3 種字體 — `14` (18 處) / `18` (1 處) / `20` (1 處)。
> 這個極簡模式證明：**不需要用到 9 級距，3 級距就能撐起完整頁面**。
> 但 9 級距是為全 App 預備的（hero KPI、大標題等場景仍需要 display/headingL 等）。

**畫布頁的真實語意對應**：

| 畫布頁實際用法 | Token | 數值 | 為什麼 |
|---|---|---|---|
| 節點 emoji（`Text(node.icon)`） | `headingS` | 20 | emoji 是視覺 icon，獨立級距 |
| 空狀態主標題（`大腦圖譜尚無記憶`） | `bodyL` | 18 | 空狀態 hero，但用 w500 不加粗 |
| loading 文字（`載入大腦記憶...`） | `caption` | 14 | 暫態文字，跟 metadata 同級 |
| 副標題、說明文字（`開始與夥伴對話...`） | `caption` | 14 | 輔助說明 |
| metadata、tag、狀態點、按鈕 label | `caption` / `small` | 14 | 元件級 |

---

#### 🌳 全 App 完整決策樹（9 級距版）

```
開始：我要寫一段文字，要選什麼 fontSize？
  ↓
Q1: 這是整頁 hero 數字嗎？(整頁只出現 1-2 個)
    ex: dashboard KPI、遊戲化分數
  → 是 → display (48)
  → 否 ↓

Q2: 這是頁面頂部的大標題嗎？
    ex: 「設定」「角色」「畫布」
  → 是 → headingL (32)
  → 否 ↓

Q3: 這是區塊標題嗎？(頁面內的「字體」「圖示」「顏色」)
  → 是 → headingM (24)
  → 否 ↓

Q4: 這是卡片標題嗎？(角色卡上的名字、設定項的左側標籤)
  → 是 → headingS (20)
  → 否 ↓

Q5: 這是「重要但不是標題」的內文嗎？(alert 重點、空狀態 hero)
    ★ 畫布頁的「大腦圖譜尚無記憶」就是這個
  → 是 → bodyL (18)
  → 否 ↓

Q6: 這是主要內文嗎？(對話泡泡、表單欄位、輸入框、卡片內描述)
  → 是 → body (16)
  → 否 ↓

Q7: 這是 button label 嗎？
  → 是 → button (14)
  → 否 ↓

Q8: 這是輔助說明 / metadata / 狀態 / tag / loading 文字嗎？
    ★ 畫布頁大部分文字（18/20 處）就是這個
  → 是 → caption (14) 或 small (14)
  → 否 → 🚨 不應該寫死 fontSize，回去重看 Q1
```

**規則**：
- **同一 widget 樹層級，禁止跳級**（`headingM` 卡片內不能用 `display`，必須用 `headingL`）
- **找不到 token 就停下來重看 Q1**，不要隨便挑一個數字
- **畫布頁 = 3 級距最低限度**（14/18/20），其他頁面最多 5 級距就足夠

---

## 🎯 二、圖示大小（Icon Size）

只有 **6 個級距**，必須用 token。

| Token | 數值 | 用途 |
|---|---|---|
| `iconHero` | 24 | 標題區 icon、頁面級 icon |
| `iconXL` | 20 | 主動作按鈕（送出、新增節點） |
| `iconLg` | 18 | 工具列按鈕、側邊選單 |
| `iconMd` | 16 | ⭐ 預設按鈕 icon、行內 icon |
| `iconSm` | 14 | 標籤內 icon、輔助 icon |
| `iconXs` | 12 | 內嵌標記、狀態點 |

### ❌ 禁用 Icon Size

```
4, 6, 8, 10, 11, 13, 15, 17, 19, 22, 26, 28, 32 以上
```

**最低限度**：12（iconXs）— 桌機不應小於此。

---

## 🎨 三、顏色（Color）

### 3.1 核心規則

**必須用 `BridgeDSColors.of(context)` 來存取**。禁用：

- ❌ `Color(0xFFXXXXXX)` — 硬編碼 hex
- ❌ `Colors.white` / `Colors.black` / `Colors.red` — Material 預設色
- ❌ 主題變數外 inline 寫死顏色
- ❌ `AppTheme.xxx` 散落呼叫（v1.0 之後所有新程式碼必須用 `BridgeDSColors`）

### 3.2 顏色 Token 結構

`BridgeDSColors` 是一個 `ThemeExtension`，提供 **33 個語意化 token**：

#### Canvas & Surface（畫布與層級）
| Token | 用途 |
|---|---|
| `canvas` | App 最外層背景 |
| `surface` | 卡片、面板底色 |
| `surfaceElevated` | badge、標籤、彈出層 |
| `surfaceHover` | hover 提升效果 |

#### 文字層級（5 級）
| Token | 用途 |
|---|---|
| `textPrimary` | 主文字（最重要） |
| `textSecondary` | 次要文字 |
| `textTertiary` | 標籤、導航 |
| `textMuted` | disabled、佔位 |
| `textQuaternary` | 非活躍 |

#### 互動色（9 色）
| Token | 用途 |
|---|---|
| `accentRed` | 品牌 punctuate、危險、錯誤 |
| `accent使用者` | ⭐ 互動、連結、focus |
| `accentGreen` | 成功、連線 |
| `accentYellow` | 警告、注意 |
| `accentPurple` | 大腦/向量/數據可視化 |
| `accentNavy` | 深層數據文字、圖表標題 |
| `accentMagenta` | 漸層裝飾、粒子特效 |
| `accentRuby` | 漸層裝飾、警示粒子 |
| `accentMiro` | 畫布互動、教學引導 |

#### 透明度疊層
| Token | 用途 |
|---|---|
| `borderSubtle` | 最淡邊框（6% 不透明） |
| `borderDefault` | 預設邊框（10% 不透明） |
| `borderStrong` | 強調邊框（20% 不透明） |
| `surfaceGlass` | 玻璃質感（5% 不透明） |
| `surfaceGlassHover` | 玻璃 hover（8% 不透明） |

#### 狀態標籤（5 組 bg/fg）
| Token | 用途 |
|---|---|
| `tagSuccessBg` / `tagSuccessFg` | 成功狀態 |
| `tagErrorBg` / `tagErrorFg` | 錯誤狀態 |
| `tagInfoBg` / `tagInfoFg` | 資訊 |
| `tagBrainBg` / `tagBrainFg` | 大腦節點 |
| `tagWarnBg` / `tagWarnFg` | 警告 |

---

## 🌓 四、主題模式（Theme Modes）

橋樑原生提供 **2 個內建主題模式**（永遠隨 App 打包，不可卸載）：

| Mode | 用途 |
|---|---|
| `BridgeDSColors.dark` | 預設（暗色 xAI 科技氛圍） |
| `BridgeDSColors.light` | 淺色（純白卡片、淺灰畫布底） |

每個模式**必須實作所有 33 個 token**，不允許 token 在某個模式下是 null。

---

## 📦 五、主題包（Theme Pack）— 開源社群擴充介面

### 5.1 設計目標

未來開源社群可下載「主題包」，一鍵改變橋樑 App 的配色與字型。

### 5.2 ThemePackService 設計藍圖

```dart
// lib/services/theme_pack_service.dart
class ThemePackService {
  /// 從 ZIP 匯入主題包（manifest.json + 字型檔案 + 圖示）
  Future<ThemePack> importFromZip(List<int> zipBytes);
  
  /// 匯出主題包為 ZIP
  Future<List<int>> exportToZip(ThemePack pack);
  
  /// 套用主題包到整個 App（重新發 ThemeExtension）
  Future<void> applyTheme(String packId);
  
  /// 列出所有已安裝的主題包
  Future<List<ThemePack>> listInstalled();
  
  /// 卸載主題包（恢復到內建 dark 模式）
  Future<void> uninstall(String packId);
}
```

### 5.3 ThemePack manifest.json 結構

```json
{
  "type": "theme-pack",
  "version": "1.0",
  "id": "theme.midnight.aurora",
  "name": "極光午夜",
  "author": "社群作者 @xxx",
  "license": "MIT",
  "description": "極光漸層主題，適合夜間使用",
  "engine": {
    "min_bridge_version": "1.0",
    "target_modes": ["dark"]
  },
  "colors": {
    "canvas": "#050810",
    "surface": "#0D1117",
    "surfaceElevated": "#161B22",
    "textPrimary": "#E6EDF3",
    "accent使用者": "#58A6FF",
    "accentPurple": "#A371F7"
    // ... 全部 33 個 token
  },
  "typography": {
    "fontFamilyBase": "Inter",
    "fontFamilyMono": "JetBrains Mono",
    "fontFile": "fonts/Inter-Regular.ttf"
    // 可覆寫但仍受 9 級距規則限制
  },
  "preview": {
    "image": "preview.png",
    "background": "#050810"
  }
}
```

### 5.4 主題包安裝流程

```
[使用者] → [設定頁 → 主題] → [匯入主題包 ZIP]
                                     ↓
                            [ThemePackService.importFromZip]
                                     ↓
                            [驗證 33 個 token 完整性]
                                     ↓
                            [驗證字型檔案存在]
                                     ↓
                            [存到 ~/.bridge/themes/{packId}/]
                                     ↓
                            [註冊到 SharedPreferences 主題清單]
                                     ↓
                            [ThemeProvider.notifyListeners]
                                     ↓
                            [整個 App rebuild，所有 widget 拿到新顏色]
```

### 5.5 主題包市場（MVP）

- **MVP（2026 Q3）**：本機 ZIP 匯入，無雲端
- **v2**：橋樑官方主題庫（GitHub repo 分發）
- **v3**：社群主題市集（in-app 瀏覽、下載、評分）

### 5.6 主題包設計鐵則

| 規則 | 說明 |
|---|---|
| **必須 33 個 token 全填** | 不允許 token 是 null 或省略 |
| **必須有 preview.png** | 主題市場需要縮圖 |
| **必須 MIT 或相容授權** | 不能封閉商業授權 |
| **必須通過 9 級距驗證** | 即使自訂字型，字體大小仍受規則限制 |
| **可選字型檔案** | 不附字型時 fallback 到系統字型 |
| **不可破壞無障礙** | 文字與背景對比必須 ≥ WCAG AA (4.5:1) |

---

## 🏗 六、實作範本

### 6.1 Widget 內正確用法

```dart
// ✅ 正確
@override
Widget build(BuildContext context) {
  final ds = BridgeDSColors.of(context);
  return Container(
    color: ds.surface,
    child: Text(
      '標題',
      style: ds.headingS.copyWith(color: ds.textPrimary),
    ),
  );
}

// ❌ 錯誤：硬編碼字體大小
Text('標題', style: TextStyle(fontSize: 22));

// ❌ 錯誤：硬編碼顏色
Text('標題', style: TextStyle(color: Color(0xFF1A1B1E)));

// ❌ 錯誤：用 Material 預設色
Text('標題', style: TextStyle(color: Colors.black));
```

### 6.2 ThemeExtension 套用範本

```dart
// 在 MaterialApp.theme 內
theme: ThemeData(
  extensions: [BridgeDSColors.light],
  // ...其他
),
darkTheme: ThemeData(
  extensions: [BridgeDSColors.dark],
  // ...其他
),
themeMode: ThemeMode.dark,
```

### 6.3 動態主題切換範本（給 ThemePack 套用用）

```dart
// ThemeProvider extends ChangeNotifier
class ThemeProvider extends ChangeNotifier {
  BridgeDSColors _currentColors = BridgeDSColors.dark;
  
  BridgeDSColors get colors => _currentColors;
  
  void applyTheme(BridgeDSColors colors) {
    _currentColors = colors;
    notifyListeners();  // 所有 MaterialApp rebuild
  }
}
```

---

## ✅ 七、驗收鐵則

任何 PR 提交時，**必須**通過以下檢查：

```bash
# 1. 禁用字體大小掃描（CI 自動跑）
flutter analyze 2>&1 | grep "fontSize:"  # 應該只看到 14/16/18/20/24/32/48

# 2. 禁用顏色掃描（CI 自動跑）
flutter analyze 2>&1 | grep -E "Color\(0x|Colors\.(white|black|red|blue|green)"  # 應該零輸出

# 3. AppTheme 殘留掃描（CI 自動跑）
grep -rn "AppTheme\." lib/screens lib/widgets  # 應該零輸出
```

---

## 🗓 八、Roadmap

| 時間 | 項目 |
|---|---|
| 2026-08-04 | v1.0 啟用（本文件） |
| 2026-08-04 | ThemePackService MVP + ThemeProvider UI 整合 + 主題設定頁 |
| 2026-08-04 | **v1.1 簡化**：移除 3 套內建官方主題、移除 ThemeController、改輪播切換 |
| 2026-08-04 | **問題 1 待修**：自動掃描工具 + 掃描問題頁 |
| 2026-Q4 | 蒸餾設計精髓（不是抄作業）+ 社群主題市集上線 |

> **2026-08-04 修正（使用者）**：取消「官方主題包」路線。理由：5 主題 × 2 深淺 = 10 種組合，
> 維護成本指數級增長；社群設計者也只會設計一套配色。內建只保留 dark + light，
> 主題包按設計者原意一套完整使用。

---

## 📎 附錄 A：完整 token 對照表（dark mode）

```yaml
# 基礎
canvas:        "#07080a"
surface:       "#101111"
surfaceElevated: "#1b1c1e"
surfaceHover:  "#252829"

# 文字
textPrimary:   "#f9f9f9"
textSecondary: "#cecece"
textTertiary:  "#9c9c9d"
textMuted:     "#6a6b6c"
textQuaternary: "#434345"

# 互動色
accentRed:     "#FF6363"
accent使用者:    "#55b3ff"
accentGreen:   "#5fc992"
accentYellow:  "#ffbc33"
accentPurple:  "#533afd"
accentNavy:    "#061b31"
accentMagenta: "#f96bee"
accentRuby:    "#ea2261"
accentMiro:    "#5b76fe"

# 透明度
borderSubtle:   "#0FFFFFFF"
borderDefault:  "#1AFFFFFF"
borderStrong:   "#33FFFFFF"
surfaceGlass:   "#0DFFFFFF"
surfaceGlassHover: "#14FFFFFF"

# 狀態標籤
tagSuccessBg: "#0E1B12"   tagSuccessFg: "#B8E8CC"
tagErrorBg:   "#1B0E0E"   tagErrorFg:   "#FFADAD"
tagInfoBg:    "#0E151B"   tagInfoFg:    "#B3DCFF"
tagBrainBg:   "#0E0A1B"   tagBrainFg:   "#B9B9F9"
tagWarnBg:    "#1B160E"   tagWarnFg:    "#FFD580"

# ── 階段 B/C/D 新增 (2026-08-05) ──
# 狀態語意
softGreen:       "#81C784"   # agent_loop 成功
toolPurple:      "#7C4DFF"   # agent_loop 強調
toolPurpleLight: "#B388FF"   # agent_loop 提示
successGreen:    "#6B8E6B"   # 沉靜綠
successDark:     "#2E7D32"   # 深綠強調
errorRed:        "#EF5350"   # Material red 400
alertRed:        "#FF1744"   # 嚴重警告

# 背景
bgLightRed:      "#FFF3F2"   # 失敗背景
bgLightGreen:    "#F1F8E9"   # 成功背景
bgVeryLightRed:  "#FFF8F7"   # hover 失敗
darkPanel:       "#1E1E2E"   # CanvasDoodle 深色
darkCanvas:      "#0D0D1A"   # agent_loop 深背景
dividerIndigo:   "#2A2A4A"   # divider 分隔線

# 節點配色
file使用者:        "#4A9EFF"   # 檔案節點
sopOrange:       "#FFB454"   # SOP 節點
pinkAccent:      "#FF6B9D"   # 子分析節點
slate:           "#8E9AAF"   # 預設節點
teal:            "#4ECDC4"   # 感知節點
deepPurple:      "#7C89FF"   # 記憶節點

# 強調
light使用者:       "#42A5F5"   # Material blue 400
brightCyan:      "#00D4FF"   # 純亮藍
hintPurple:      "#8888AA"   # 淡紫
hintPink:        "#CE93D8"   # 淡紫粉
google使用者:      "#1A73E8"   # Google 藍
goldAccent:      "#FFD700"   # 金色高亮
info使用者:        "#4A90D9"   # 資訊藍
orange500:       "#FF9800"   # Material orange 500
orange300:       "#FFB74D"   # Material orange 300

# 灰階（對應 Material grey.shadeXXX）
grey300: "#E0E0E0"
grey400: "#BDBDBD"
grey600: "#757575"
grey700: "#616161"
grey800: "#424242"
lightGray: "#E0E0E0"

# Material 標準色
red500:    "#F44336"
red400:    "#EF5350"
red700mat: "#D32F2F"
green500:  "#4CAF50"
green700:  "#388E3C"
green400:  "#66BB6A"
blue500:   "#2196F3"
blue700:   "#1976D2"
orangeStd: "#FF9800"
orange700: "#F57C00"
berlinRed: "#C8102E"

# 文字層
textOnAccent: "#FFFFFF"  # 純白（按鈕前景）
```

---

## 📎 附錄 B：參考案例

### ✅ 畫布頁（驗證過的最佳實踐）

`lib/widgets/canvas/brain_canvas.dart`

```dart
// 整個檔案只用 fontSize: 14 / 18 / 20，全部用 BridgeDSColors
// 完全符合 v1.0 設計原則
```

### ❌ 反例：CompanionCreateScreen v0.x

```dart
// 違規：fontSize: 10, 11, 12, 13, 15, 22, 26（已於 2026-08-04 修正）
// 違規：AppTheme.textPrimary → 改為 BridgeDSColors.of(context).textPrimary
```

---

**文件結束。橋樑排版設計原則 v1.0 — 啟用日期 2026-08-04。**