# Semi Bridge — Agent Working Guide

歡迎 AI 夥伴（Claude Code / Codex / Hermes / 任何 agent）加入這個 repo。這份文件是你的工作守則。

> 本專案由人類（Blue）與 AI（小葵）協作開發。協作史與決策日誌屬內部紀錄，不在 repo 內。

## 專案結構快速導覽

```
lib/screens/chat_screen.dart   ~8765 行 — 對話主畫面（最大檔案）
lib/controllers/chat_controller.dart  ~4700 行
```

- 大檔案務必 grep + 分段讀取，不要一次全讀。
- `lib/` 內不引用 `tool/`、`tools/`（工具目錄獨立，見下）。

## 工具目錄

| 目錄 | 內容 | 慣例 |
|------|------|------|
| `tool/` | Dart 工具（design system 掃描、token 匯出、benchmark） | Flutter 標準慣例 |
| `tools/` | Python 工具（記憶匯入器、PDF 抽取、縮圖 worker） | Python 腳本慣例 |

兩者並存是刻意的：Dart 工具走 `dart run tool/…`，Python 工具直接 `python3 tools/…`。合併會破壞 Flutter 工具鏈自動發現 `tool/`，不建議。

## 已知死代碼（畫架構圖/設計時排除）

- `chat_screen.dart` `_showSkillPanel`（7 chip）— 無 UI 觸發點
- `chat_screen.dart` `_showModeSelector`（5 靈魂模式）— 無呼叫處（舊「靈魂切換」殘骸，概念已演進為多 Agent 切換）
- `chat_screen.dart` `_showMemoryOverlay` — 死代碼
- `lib/widgets/canvas/open_canvas_workspace.dart` (2139 行) — 已由 V2 取代

## 手機版狀態

**手機版已正式宣告刪除（2026-08-10）。** 未來將以「companion」形態重新設計：出門時能看見 Agent 在畫布上做什麼 + 丟 follow-up——不是另一個桌面，不是被動遙控器。

相關檔案保留但不再被路由觸發：
- `lib/screens/mobile_bridge_pairing_screen.dart`
- `lib/screens/mobile_design_showcase_screen.dart`
- `lib/services/mobile_bridge_client.dart`
- `lib/widgets/mobile/`（app_bar_mobile.dart, mobile_navigation.dart）
- `_isDesktopPlatform` 永遠為 `true`——所有平台一律走桌面流程

## settings_screen.dart 已刪除（2026-08-11）

`lib/screens/settings_screen.dart` 已不存在。設定已遷移：
- API key 管理 → `bridge_desktop_screen.dart` 主腦 API 設定（鎖定/測試/解除鎖定）；`capability_center_screen.dart` 能力中心也可管理
- DB 路徑設定 → `lib/widgets/settings/db_location_card.dart`
- SemiDAO 三項（審查金鑰/Pinata/錢包）→ `lib/screens/desktop/settings/semidao_settings_page.dart`（placeholder，SemiDAO 啟動時填充）
- 向量 DB 設定 → `vault_screen.dart`（向量資料庫 tab）
- `/settings` 路由保留但 redirect 到 `/`（向後相容）

## 設計原則索引（必讀）

- **[共視宣言 (Covision Manifesto)](docs/COVISION_MANIFESTO.md)** — 產品定位錨點：人機共視是全球 open-source 生態中的空白位。共視三層：共同看見 → 共同感覺 → 共同建造。
- **[資料主權宣言 (Data Sovereignty Manifesto)](docs/DATA_SOVEREIGNTY_MANIFESTO.md)** — 金鑰匙/DataPathGate/除痕≠刪除三原則；五層主權動線。
- **[橋樑排版設計原則 (Bridge Typography Design Principles)](docs/BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md)** — 9 級距字體 token、6 級距圖示 token、33 個 BridgeDSColors token。**所有新 UI 程式碼必須遵守，違規 PR 不可 merge**。
- **[DESIGN.md](DESIGN.md)** — 設計系統的原始規範
- **[橋樑統合設計語言 (Bridge Unified Design Language)](docs/BRIDGE_UNIFIED_DESIGN_LANGUAGE.md)** — 六源蒸餾 → 六種 Bridge 能力 → 第七個結果：共視。三層不反轉：功能骨架(A) → 關係推演(B) → 事件氣氛(C)。
- **[橋樑色塊設計規範 (Bridge Color Block Design Guide)](docs/BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md)** — 三層視覺架構、配色規則、卡片標準結構。**所有 UI 必須照這個做，違規 PR 不可 merge**。
- **[橋樑 Tier 系統 (Bridge Tier System)](docs/BRIDGE_TIER_SYSTEM.md)** — 33 個語意化 tier、三層架構、三大防呆。**未來開源社群改主題包就能一鍵對齊全 App，不用碰 widget 程式碼**。新元件（AlertDialog/彈窗/SnackBar）文字層級必走 Tier、顏色必走 BridgeDSColors——禁 `Theme.of(context).textTheme` 與 Material 預設。
- **[橋樑氣氛設計語言 (Bridge Atmosphere Design Language)](docs/BRIDGE_ATMOSPHERE_LANGUAGE.md)** — LOGO 形狀規則、主題包架構（社群設計者可獨立設計氣氛主題包，不影響功能層）。GPU 預算 ≤ 5% / CPU ≤ 8% / 記憶體 ≤ 200MB（硬性紀律）。
- **[Phase G Timeline](docs/PHASE_G_TIMELINE.md)** — 現行主線：時間感（L2-L4）/ 因果引擎 / Agent 平台。

## 架構地圖（必讀）

**[docs/APP_ARCHITECTURE_MAP.md](docs/APP_ARCHITECTURE_MAP.md) — 每次修改前必讀**

- 「想改 X → 去哪改」索引表（最快定位）
- 啟動鏈、API 呼叫鏈、本地模型啟動鏈
- Swift↔Dart 橋接點（含兩端都要改的陷阱）
- 已知陷阱清單

**規則**：修改/修復/重構前，先查地圖的「快速導航」表。找不到再 grep，找到了就在地圖上補一筆——地圖過期 = 下次改錯地方。改完程式碼後，如果行號變了或新增了檔案/功能/陷阱，必須同步更新地圖。

## 環境路徑覆寫（BRIDGE_APP_HOME）

本 App 預設將資料存於 `~/Library/Application Support/farm.semiwasabi.bridgeApp/`。開發/測試/CI 環境可用環境變數 `BRIDGE_APP_HOME` 覆寫根路徑，避免污染使用者資料。

## 驗收鐵則

- `flutter analyze 2>&1 | tail -20` 零錯誤才算完成
- agent 宣稱「建檔/改檔完成」必須由主 session 親自 `ls`/`wc`/`grep` 驗證，不可僅憑宣稱
