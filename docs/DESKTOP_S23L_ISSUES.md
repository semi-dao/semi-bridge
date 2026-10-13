# 橋樑 App 桌面版 S23l 問題清單

> **基準 commit**: `83b3049`
> **主檔案**: `lib/screens/bridge_desktop_screen.dart`（2114 行）
> **建立日期**: 2026-07-10
> **來源**: 使用者 實測桌面 App 後逐項列出

---

## 目前佈局結構（現況）

```
TopBar(64px) — 6 tab: 對話 / 大腦 / 畫布 / 檔案 / 專案 / 設定
├─ Sidebar(240px) — 三區塊寫死：對話列表 / 記憶索引 / 系統
├─ Canvas(flex) — 依 tab 切換內容
├─ ContextPanel(320px) — 系統資訊 + 快捷操作，永遠顯示
└─ StatusBar(32px)
```

---

## 問題清單

### P1 — 文字框選複製（全域）
- **問題**：APP 裡所有文字都要能框選複製
- **現況**：聊天卡片、證據卡等已用 `SelectableText`；但 Sidebar、TopBar、Tab 標題、狀態列、設定頁等多處仍用一般 `Text` 無法選取
- **修改範圍**：全域檢查 `bridge_desktop_screen.dart` 及子元件，所有使用者可見文字改用 `SelectableText`
- **檔案**：`bridge_desktop_screen.dart` 全檔 + `desktop_chat_panel.dart` + 各 tab 子頁面

### P2 — 語音輸入法無法填入對話框
- **問題**：macOS 語音輸入法無法將文字填入 APP 的訊息輸入框
- **現況**：桌面聊天輸入框可能用了 `TextField` 或 `TextFormField`，需確認是否攔截了系統輸入法事件
- **修改範圍**：檢查 `desktop_chat_panel.dart` 的輸入框實作，確認 `FocusNode` / `TextEditingController` 不阻擋 IME
- **檔案**：`lib/screens/desktop/desktop_chat_panel.dart`

### P3 — 對話列表第一項英文改中文
- **問題**：左邊對話列表第一項顯示 `New Conversation`，應改中文
- **現況**：`bridge_desktop_screen.dart` L591：`_sidebarItem('New Conversation', ...)`
- **修改**：改為「新增對話」或「新對話」
- **檔案**：`bridge_desktop_screen.dart` L591

### P4 — 對話列表只能新增不能刪除
- **問題**：對話列表沒有刪除功能
- **現況**：Sidebar 對話列表只有「New Conversation」按鈕，無刪除入口
- **修改**：每個對話項目加刪除手勢（滑動刪除或右鍵選單或 hover 顯示刪除按鈕），需對接 ChatController 的刪除方法
- **檔案**：`bridge_desktop_screen.dart` Sidebar 區 + `lib/controllers/chat_controller.dart`

### P5 — 「記憶索引」與「標籤」按鈕無反應
- **問題**：對話列表下方的「記憶索引」「標籤」按鈕點擊無反應
- **現況**：L593-594：`_sidebarItem('記憶索引', ..., false)` 和 `_sidebarItem('標籤', ..., false)` — 沒有 `onTap`
- **修改**：待 P10 佈局重構後，這兩項移到「大腦」tab 的 sidebar 動態區域，屆時接上行為
- **檔案**：`bridge_desktop_screen.dart` L593-594

### P6 — 記憶索引列表「擺錘」與「心腦」按鈕無反應
- **問題**：記憶索引列表中 Pendulums 擺錘、Heart-Mind 心腦 點擊無反應
- **現況**：L603-604：`_sidebarItem('Pendulums 擺錘', ..., false)` 和 `_sidebarItem('Heart-Mind 心腦', ..., false)` — 沒有 `onTap`
- **修改**：待 P10 佈局重構後，接上對應頁面或 tab 切換
- **檔案**：`bridge_desktop_screen.dart` L603-604

### P7 — 「門」對應專案頁面，專案只能新增不能刪除
- **問題**：Doors 門 → 專案頁面，專案只能新增無法刪除
- **現況**：L600-602：Doors 門 → `_activeCanvasIndex == 4`（專案 tab）。需檢查 `project_door_page.dart` 是否有刪除功能
- **修改**：專案列表加刪除功能（同 P4 模式）
- **檔案**：`lib/screens/desktop/project_door_page.dart` + `lib/services/project_door_store.dart`

### P8 — 「模型下載」按鈕無反應
- **問題**：系統區「模型下載」按鈕點擊無反應
- **現況**：L607：`_sidebarItem('模型下載', ..., false)` — 沒有 `onTap`
- **修改**：接上模型下載頁面（`brain_model_download_card.dart` 已存在），或跳轉到設定頁的模型下載區塊
- **檔案**：`bridge_desktop_screen.dart` L607 + `lib/widgets/brain_model_download_card.dart`

### P9 — 「配對管理」與「檔案總管」同時亮起，「配對管理」無反應
- **問題**：點「配對管理」和「檔案總管」都會同時高亮（因為都指向 index 3），且「配對管理」實際上沒有獨立頁面
- **現況**：
  - L608-610：配對管理 → `_activeCanvasIndex == 3`，onTap 設為 3
  - L611-613：檔案總管 → `_activeCanvasIndex == 3`，onTap 設為 3
  - 兩者共用同一 index，所以同時亮
- **修改**：待 P10 佈局重構後，配對管理需獨立頁面或併入設定。短期可先讓配對管理跳 dialog 或獨立 index
- **檔案**：`bridge_desktop_screen.dart` L608-613

### P10 — 三大區塊佈局重構（核心架構變更）

> 這是整體面板結構性的重新設計，影響最大。

#### P10-a 右側資訊欄可收合
- **需求**：右側 ContextPanel(320px) 平常不需要顯示，要能收合到邊緣
- **現況**：`_buildContextPanel()` 永遠顯示，固定寬度 320px
- **修改**：加收合按鈕 / 動畫展開收合，預設收合
- **檔案**：`bridge_desktop_screen.dart` L494, L1731-1760+

#### P10-b 系統選項移到左側底部固定
- **需求**：系統四項（模型下載、配對管理、檔案總管、設定）移到左 sidebar 最底部並固定
- **現況**：系統區跟其他區塊一起在 `SingleChildScrollView` 裡，會滾動
- **修改**：Sidebar 改為 Column(動態區 + 固定系統區)，系統區用 `Column` 固定底部不滾動

#### P10-c 移除上方 tab 的「檔案」「設定」
- **需求**：因為左 sidebar 底部已有檔案總管和設定，上方 tab 不需要重複
- **現況**：TopBar 6 tab：對話/大腦/畫布/檔案/專案/設定
- **修改**：改為 4 tab：對話/大腦/畫布/專案
- **注意**：tab index 需重新對應，`_activeCanvasIndex` 的 switch case 全部要更新

#### P10-d 左側列表動態切換（依上方 tab 選擇）
- **需求**：左 sidebar 上方區域依目前選的 tab 動態顯示對應列表
- **現況**：三區塊（對話列表/記憶索引/系統）全部寫死同時顯示
- **修改**：
  - 選「對話」→ sidebar 上方顯示對話列表（含新增/刪除）
  - 選「大腦」→ sidebar 上方顯示記憶索引（水流/門/擺錘/心腦 + 標籤作為第五項）
  - 選「畫布」→ sidebar 上方顯示畫布功能按鈕（待 P11 定義）
  - 選「專案」→ sidebar 上方顯示專案列表（含新增/刪除）
- **檔案**：`bridge_desktop_screen.dart` `_buildSidebar()` L581-622 整段重構

### P11 — 畫布 tab 初始位置與 sidebar 按鈕
- **問題**：
  1. 選「畫布」時左 sidebar 應出現畫布功能按鈕
  2. 畫布初始顯示位置偏移，使用者點進來看到空白，需手動移動才能找到第一個水流軌跡
- **現況**：L706-710：畫布 tab 只是一個置中佔位文字。`BrainCanvas` 在大腦 tab 的圖譜模式才有實際 canvas
- **修改**：
  - 畫布 tab 的 sidebar 按鈕待功能定義
  - 畫布初始 viewport 要計算所有節點的 bounding box 並置中（`canvas_viewport.dart` 已有 viewport model）
- **檔案**：`bridge_desktop_screen.dart` L705-710 + `lib/widgets/canvas/brain_canvas.dart` + `lib/models/canvas/canvas_viewport.dart`

---

## 修正狀態總覽

| 項目 | 狀態 | commit | 說明 |
|------|------|--------|------|
| P1 文字框選 | ✅ r2 修正 | `19bd173` → `e04768f` | 61 處 Text→SelectableText；r2: 按鈕區改回 Text 不搶點擊 |
| P2 語音輸入 | ✅ r2 修正 | `7edbb74` → `e04768f` | maxLines: null→5；r2: 載入後預設捲到最新訊息 |
| P3 英文改中文 | ✅ | `19bd173` | New Conversation → 新增對話 |
| P4 對話列表刪除 | ✅ r2 重做 | `7edbb74` → `e04768f` | r2: 移除內部 sidebar，統一左側；新增/刪除/改標題三功能齊全 |
| P5 記憶索引按鈕 | ✅ | `7edbb74` | 全部接上 onTap |
| P6 擺錘/心腦按鈕 | ✅ | `7edbb74` | →圖譜模式 |
| P7 專案刪除 | ✅ | `7edbb74` | deleteDoor + Kanban × 按鈕 |
| P8 模型下載 | ✅ | `19bd173` | 系統區接上 _activeSystemPage |
| P9 配對/檔案衝突 | ✅ | `19bd173` | 獨立 _activeSystemPage |
| P10 佈局重構 | ✅ | `19bd173` | 4 tab + 動態 sidebar + 固定系統區 + 收合資訊欄 |
| P11 畫布初始置中 | ✅ | `7edbb74` | fitToBounds + bbox 計算 |
| P1-r3 dialog 風格 | ✅ | (待 commit) | 全域 dialogTheme + textButtonTheme teal 色系 |

---

## 未來階段（待專門設計）

### F1 — 大腦容器六大房間完整設計
- **狀態**：待設計
- **範圍**：
  - 擺錘（Pendulums）— 功能與頁面待定義
  - 心腦（Heart-Mind）— 功能與頁面待定義
  - 標籤（Tags）— 功能與頁面待定義
  - 水流（Stream）— 已有記憶圖譜，需持續完善
  - 門（Doors）— 已接專案看板，需評估是否獨立房間頁面
- **前置依賴**：知識編譯（資料結構定義後才能設計 UI）
- **使用者 指示**：2026-07-10 確認「之後再專門單獨來進行設計」

### F2 — 專案頁面重新設計
- **狀態**：待設計
- **問題**：
  - 三列看板 + 左側新增按鈕擠在一起，桌面寬度下空間分配不均
  - 選中門後右側詳情面板壓縮看板空間
  - 使用者不知道怎麼開始用（沒有引導）
- **設計方向建議**：
  - 看板改為全寬度，新增門按鈕移到頂部 toolbar
  - 門的詳情用彈出面板（overlay）而非擠壓看板
  - 空狀態加引導文字（「建立你的第一個專案門」）
- **使用者 指示**：2026-07-10 確認「之後再專門單獨來進行設計」

---

## 關鍵檔案索引

| 檔案 | 用途 |
|------|------|
| `lib/screens/bridge_desktop_screen.dart` | 桌面版主畫面（2114 行），佈局 + sidebar + tab + context panel |
| `lib/screens/desktop/desktop_chat_panel.dart` | 桌面聊天面板（含輸入框） |
| `lib/widgets/canvas/brain_canvas.dart` | 大腦圖譜畫布 |
| `lib/models/canvas/canvas_viewport.dart` | 畫布 viewport model |
| `lib/screens/desktop/project_door_page.dart` | 專案門頁面 |
| `lib/services/project_door_store.dart` | 專案資料存取 |
| `lib/widgets/brain_model_download_card.dart` | 模型下載卡片（已存在） |
| `lib/controllers/chat_controller.dart` | 對話控制器 |
| `UI_SPRINT_BACKLOG.md` | 歷史 UI sprint 待辦 |
