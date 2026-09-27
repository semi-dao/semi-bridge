# 橋樑 App UI Sprint 待辦清單

> 來源：2026-06-30 七人實測 → 50 項缺陷修復
> 這些項目需要結構性重構，不適合在 P0-P2 批次中快速處理

---

## Sprint 1：AppBar 結構重構（3-2-1 分層）

> 依據：Material Design 3 官方規範「AppBar 最多 2 個 action」+ NN/g「icon 必須有可見文字標籤」
> 來源研究：/tmp/ux_research_result.txt（路加 MiniMax-M3 報告）

### P1-4: companions AppBar 4 icon-only → 2 icon + PopupMenu
- **現況**：4 個 icon-only（山門徽章、匯入角色包、SemiDAO預審池、設定）
- **目標**：保留「設定」+ 三點選單收其餘 3 個
- **檔案**：`lib/screens/companion_list_screen.dart` L44-79

### P1-5: chat AppBar 5~6 icon → 2 icon + PopupMenu
- **現況**：切換模型、判斷線索、工具箱、趨勢、三點選單 + 條件 badge（本地模型、用量）
- **目標**：保留「切換模型」+ 三點選單；用量 chip 移到 Drawer；本地模型 badge 併入工作狀態 bottom sheet
- **檔案**：`lib/screens/chat_screen.dart` L2936-3136

### P2-36: desktop_companion AppBar 6 icon-only
- **現況**：透明小窗、漫遊/停靠、播放/暫停、HUD、連接、Shell
- **目標**：AppBar 只留返回 + HUD + 連接；其餘移到 body
- **檔案**：`lib/screens/desktop_companion_mock_screen.dart` L77-115

---

## Sprint 2：頁面結構重構

### P2-12: chat 長期記憶 AlertDialog → BottomSheet
- **現況**：`_showMemoriesDialog()` 用 `showDialog` + `AlertDialog`
- **問題**：記憶是長期資產會增長，Dialog 容易 overflow
- **目標**：改 `showModalBottomSheet`，內容用 SingleChildScrollView
- **檔案**：`lib/screens/chat_screen.dart` L6932+

### P2-16: companion_create 改分步驟 Stepper
- **現況**：4544 行單頁，手機需大量滾動
- **目標**：拆成 Stepper（基本資料 → 個性 → 造型 → 預覽）
- **檔案**：`lib/screens/companion_create_screen.dart`

### P2-20: settings 進階面板加 TabBar
- **現況**：ExpansionTile 展開後 7 個子區塊一次全塞
- **目標**：改 TabBar 或二級分頁
- **檔案**：`lib/screens/settings_screen.dart` L1841+

### P2-35: first-connect 控制面板簡化
- **現況**：像 dev panel（複製配對碼、啟動 gateway、smoke test、demo call）
- **目標**：簡化為掃碼 + 確認，dev 工具收進 kDebugMode
- **檔案**：`lib/screens/first_connect_screen.dart`

### P2-11: chat 漢堡 vs 三點「專案門」語意重疊
- **現況**：漢堡選單有專案門，三點選單也有專案門
- **目標**：區分為「瀏覽專案」（漢堡）vs「新增專案」（三點），或合併
- **檔案**：`lib/screens/chat_screen.dart`

---

## P3 視覺細節（15 項，待處理）

| ID | 畫面 | 問題 |
|----|------|------|
| P3-1 | companion_list | FAB.extended「＋」與 label「鍊成新夥伴」冗餘 |
| P3-2 | chat | 漢堡 vs 三點「專案門」icon 語意未區分 |
| P3-3 | chat 輸入區 | 圖片附件按鈕可合併到「+」PopupMenu |
| P3-4 | chat 輸入區 | 清除草稿按鈕 size:18 偏小 |
| P3-5 | companion_soul | AppBar 英文 vs 中文（已修 P1-13，確認無殘留） |
| P3-6 | 跨畫面 | AppBar action 全 icon-only 依賴 tooltip（→ Sprint 1 解決） |
| P3-7 | 跨畫面 | 桌面畫面導航按鈕位置不一致（→ Sprint 1 解決） |
| P3-8 | desktop_hud | 950ms demo Timer 正式環境需關閉 |
| P3-9 | desktop_hud | download_outlined trailing icon 用途不明確 |
| P3-10 | 多畫面 | kDebugMode 條件區塊正式版確認處理 |
| P3-11 | golden-keys | 本地模型卡片無展開/收起控制 |
| P3-12 | companion_soul | 確認按鈕無 icon，風格不統一（已修 P1-13 標題，按鈕待補 icon） |
| P3-13 | companion_list | 對話 tile 沒有重新命名捷徑 |
| P3-14 | achievements | 卡片間距 8px 偏密 |
| P3-15 | 跨畫面 | 字體 11px 出現頻率高，建議 12-13px |

---

## 修復進度總覽

| 等級 | 總數 | 已修 | 移至Sprint | 評估保留 |
|------|------|------|-----------|---------|
| P0 | 4 | 4 | 0 | 0 |
| P1 | 16 | 13 | 2 | 1 |
| P2 | 43 | 20 | 5 | 3 |
| P3 | 15 | 待處理 | — | — |

**Commit 歷史：**
- `aaa635a` P0 修復
- `12e8f93` P1 批次（12項）
- `3b1975a` P1-14 全域觸控區 48pt
- `6937af5` P2 批次 B+C
- `864c81d` P2 剩餘
