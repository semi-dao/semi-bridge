# 橋樑 App — 設計系統演進報告

> **作者**：教練 Agent（整理）+ 使用者（決策）
> **日期**：2026-08-05
> **版本範圍**：v0.1 (2026-04) → v1.1 (2026-08-05)
> **適用對象**：所有設計師、工程師、開源貢獻者

---

## 📜 為什麼需要演進史？

橋樑 App 的設計系統不是一天建成的。
它是從混亂、寫死、零散，逐漸收斂到 **三層架構** 的過程。

本文件記錄這條演進路徑，
幫助：
- 新進工程師理解「為什麼這樣設計」
- 開源貢獻者遵守收斂原則
- 設計師知道每個 token 怎麼來的

---

## 🌱 階段 0 — 混亂期（2026-04 ～ 2026-06）

### 狀態
- 5 套設計系統混合（xAI / Raycast / Stripe / Figma / Miro）
- 各頁面獨立開發，配色散落
- 字級、間距、圓角全是 magic number
- 改一個顏色要 grep 全 codebase

### 問題
- `fontSize: 14` 出現 813 次，誰知道哪裡對應哪裡？
- `Color(0xFF...)` 出現 532 次，硬編碼無語意
- `Colors.grey.shade600` 出現 18 次，分散無統一

### 觸發事件
**使用者 親自畫 V2 Canvas**（2026-06）
- 找到眼睛舒服的配色標準
- 但這標準只在 V2 Canvas，其他頁面都跑掉

---

## 🎨 階段 1 — Token 誕生（2026-07）

### 動作
- `lib/theme/bridge_design_system.dart` 建立
- 38 個 BridgeDS static const Color token
- 33 個 Tier（語意化字級）

### 成果
- 設計師找到「顏色住的地方」
- 但仍有大量 UI 沒跟進

---

## 🚀 階段 2 — 大規模收斂（2026-08）

### 階段 A — Tier 殘留清理
| 指標 | 數值 |
|---|---|
| 處理前 | 74 處 |
| 處理後 | **0 處** |
| 新增 Tier | +12 個 |

**為什麼重要**：所有 UI 用 `TierStyle.of(context, Tier.xxx)` 取得統一字級，設計師只改 1 處影響全 App。

### 階段 B — 寫死 TextStyle 清掉
| 指標 | 數值 |
|---|---|
| 處理前 | 813 處 |
| 處理後 | 20 處（CustomPainter/PDF 合法場景）|
| flutter analyze errors | 270 → 0 |

**為什麼重要**：
- 修復了大量 `const TextStyle(...TierStyle.of...)` 結構錯誤
- 修復 sibling agent 造成的 `.5,` 殘留、`AnimatedDefaultTierStyle` 假語法、`* s` 殘留等

### 階段 C — 寫死 hex 清掉
| 指標 | 數值 |
|---|---|
| 處理前 | 532 處 |
| 處理後 | **0 處** |
| 新增 BridgeDS tokens | +31 個 |

**為什麼重要**：
- 所有 UI 顏色必須透過 BridgeDS.xxx
- 找到 `BridgeDSColors`（ThemeExtension）和 `BridgeDS`（static const class）兩個 class — 設計師犯的關鍵錯誤就是把 token 加到錯誤的 class

### 階段 D — Material Colors 收斂
| 指標 | 數值 |
|---|---|
| 處理前 | 185 處 |
| 已替換 | 79 處 + 89 處合法保留（Colors.transparent + Colors.xxx.withValues）|
| 新增 BridgeDS tokens | +17 個 |

**為什麼重要**：
- 灰階、紅綠藍橙等狀態色全部語意化
- 設計師不用記 Material red 400 vs 500 的差別

---

## 🏗️ 三層架構正式確立

```
┌─────────────────────────────────────────┐
│ Layer 3: Widget UI 程式碼               │
│ Text('Hello', style: TierStyle          │
│   .of(context, Tier.cardBody)            │
│   .toTextStyle().copyWith(              │
│     color: BridgeDS.textPrimary,        │
│   ))                                    │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│ Layer 2: Tier Manifest（45 個）         │
│ Tier.cardBody → fontSize: 14,           │
│   fontWeight: FontWeight.w400,          │
│   letterSpacing: 0.2                    │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│ Layer 1: BridgeDS Tokens（85 個）       │
│ static const Color textPrimary          │
│   = Color(0xFFF9F9F9)                   │
└─────────────────────────────────────────┘
```

### 設計師工作流改變

**Before（傳統）**：
```
設計師：把這個字級改一下
工程師：grep 全 codebase，找到 813 處 → 改 813 次 → 風險高
```

**After（現在）**：
```
設計師：改 Tier.cardBody 的 fontSize
整個 App 13 處自動跟著變 → 零風險
```

---

## 🛡️ 階段 3 — 保護層建立（2026-08-05）

### BridgeDSTokenGroups 分組（85 → 12 個語意組）

```dart
BridgeDSTokenGroups.groups：
  - Surface (6) / Text (6) / Border (6)
  - Accent (12) / Status (14) / Tag (10)
  - Background (3) / Node (7) / Particle (5)
  - Grey (6) / MaterialStandard (6) / Hint (4)
```

**為什麼重要**：設計師按用途找 token，而不是面對 85 個無組織的列表。

### 單元測試（18 個）
- `test/bridge_ds_tokens_test.dart`
- 確保 12 個分組完整、token 不重複

### 視覺回歸測試（5 個 PNG）
- `test/golden/design_system_golden_test.dart`
- 5 個 baseline PNG（palette_surface, palette_status, palette_accent, palette_node, text_hierarchy）
- 設計師改 token，CI 立刻發現視覺變化

### CI 自動掃描（tool/check_design_system.dart）
- 自動檢查違規（寫死 hex、Material Colors）
- 整合到 GitHub Actions
- PR 違規不可 merge

---

## 📱 階段 4 — 響應式地基（AGENTS.md 待辦）

sibling agent 建立的 4 個地基檔案（已驗證可用）：

| 檔案 | 行數 | 用途 |
|---|---|---|
| `lib/core/responsive.dart` | 99 | `Responsive.isMobile/Tablet/Desktop` + extension |
| `lib/core/spacing.dart` | 78 | `AppSpacing` (xs/sm/md/lg/xl/xxl) + `AppGap` |
| `lib/widgets/adaptive_scaffold.dart` | 66 | `AdaptiveScaffold` (自動 SafeArea + 最大寬度) |
| `lib/widgets/adaptive_card.dart` | 118 | `AdaptiveCard` + `AdaptiveText` |

### 已改造的 widget（示範）
- `lib/screens/lock_screen.dart` — Scaffold → AdaptiveScaffold
- `lib/screens/companion_control_center_screen.dart` — Scaffold + SafeArea → AdaptiveScaffold

**為什麼重要**：手機/平板/桌面自動切換，手機滿版、桌面最大 900px。

---

## 📊 整體演進數據

### 程式碼品質

| 指標 | v0.1 (混亂期) | v1.1 (2026-08-05) |
|---|---|---|
| 寫死 hex | ~532 處 | **0 處** |
| 寫死 TextStyle | ~813 處 | 20 處（合法） |
| 寫死 Material Colors | ~185 處 | 89 處（合法保留） |
| flutter analyze errors | 270+ | **0** |
| 測試覆蓋率 | 0 個設計系統測試 | **23 個** |

### 設計系統規模

| 類型 | 數量 |
|---|---|
| Tier tokens | 45 個 |
| BridgeDS color tokens | 85 個 |
| 文件 | 4 個（Typography + Color Block + Sprint + Evolution） |
| 單元測試 | 18 個 |
| Golden test baselines | 5 個 PNG |
| CI 工具 | 1 個 CLI + 1 個 GitHub Actions workflow |

---

## 🎯 下一步（已計劃但尚未執行）

### 短期（接下來 1-2 週）
- ✅ 完成：所有寫死收斂階段 A/B/C/D
- ✅ 完成：85 token 分組索引
- ✅ 完成：23 個測試 + CI 工具

### 中期（接下來 1-2 月）
- [ ] 把現有 32 個 Scaffold 全部改 AdaptiveScaffold
- [ ] 主題包 (Theme Pack) 自動生成工具
- [ ] 把 45 個 Tier 加上字重/行高/字距設定
- [ ] Figma plugin 與 BridgeDS token 雙向同步

### 長期（接下來半年）
- [ ] 開源社群可下載 Bridge 主題包
- [ ] 設計師自助維護 token（透過視覺化工具）
- [ ] 把設計系統變成獨立 npm/pub package
- [ ] 多品牌支援（不同 App 用同一設計系統）

---

## 🏆 演進原則（不可妥協）

### 1. 三層不可破壞
任何 UI 程式碼都必須走三層（Widget → Tier → BridgeDS），不可跳過。

### 2. 寫死 token 是技術債
凡 `Color(0xFF...)`、`TextStyle(fontSize: NN)`、`Colors.xxx.shadeNN` 都是違規。
可加 token，不可直接寫。

### 3. 必跑 CI
所有 PR 必須通過 `dart run tool/check_design_system.dart`、`flutter analyze`、`flutter test`。

### 4. 設計師是 token 管理員
工程師可動 token（極少數情況），但默認規則是「設計師改 token → 工程師不動 widget」。

### 5. 文件同步更新
新增 token 必須同步更新 BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md + BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md。

---

## 🎬 結語

從 v0.1 到 v1.1，我們把一個混亂的 codebase 收斂成：
- **131 個語意化 token**（Tier + BridgeDS）
- **5 層保護鏈**（定義 → 分組 → 單元測試 → 視覺回歸 → CI 工具）
- **0 個 flutter analyze errors**

這是一個 milestone，但不該停下。

設計系統會繼續演進——因為 UI 會進、主題會換、需求會變。
但**三層架構不可變**，因為它是核心承諾：

> **改一個 token → 全 App 跟著變**

---

**撰寫**：教練 Agent（semiwasabi）— 2026-08-05
**Commit history**：
- `feat(design-system): 階段 A/B/C/D 設計系統收斂`
- `feat: 響應式地基 + token 分組 + golden test`
- `feat: AdaptiveScaffold 採用 + CI 自動檢查 + 演進報告`
