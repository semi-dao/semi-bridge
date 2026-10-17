# 設計稿：收據搜尋（Receipts Search）— 優化七刀 · 第 3 刀

> 日期：2026-09-08 ｜ 狀態：✅ Blue 已授權連續開工（「繼續開工」）
> 來源報告：`docs/specs/2026-09-08-buzz-grokbot-optimization-report.md`（刀 3，P0.5）
> 一句話定位：**一個搜尋框涵蓋對話/資產/記憶/任務——搜尋結果不是連結，是空間座標（點開跳到圖譜那顆星、畫布那個節點、對話那則訊息）。**

---

## 1. TL;DR

Blue 打「鹿角蕨」→ 一個入口同時看到：相關對話、大腦資產、記憶、（未來）任務。點結果直接**跳到現場**——對話跳到那則訊息（並高亮）、資產跳大腦圖譜那顆星、任務跳工作畫布。這是 Buzz「one event log」的價值，但我們的 receipt 是空間座標不只是文字連結。

## 2. 設計理念三句話

1. **North Star**：個人第二大腦的價值在「找得到」——26k 資產的 App 沒有全局搜尋等於圖書館沒有目錄。
2. **護城河**：Buzz 搜文字事件流；我們的搜尋結果可跳進 3D 星系、畫布節點、對話原句——搜尋是空間導航，不是列表檢索。
3. **vanity 風險自首**：五域全搜若每次都全開，效能風險（26k 資產 FTS）。設計上分域並行＋即時防抖，且語義嵌入只在 hybrid 模式跑（EmbeddingService 可用時）。

## 3. 現有基礎（實掃）

| 資產 | 位置 | 狀態 |
|---|---|---|
| HybridSearchService | `services/vector_db/hybrid_search_service.dart`（1423 行）——記憶+資產、FTS/semantic/hybrid+RRF 融合 | ✅ 直接用 |
| 對話全文 | `ConversationStore.getAll()`（記憶體 JSON） | ✅ 加一層 in-memory 掃描 |
| 任務 | `TaskSessionStore.getAll()`（刀 1 產物） | ✅ 直接用 |
| 大腦圖譜導航 | MCP `navigate {target:brain,sub:"mode:N"}`（brain-galaxy skill） | ✅ 結果跳轉用 |
| 畫布導航 | `CanvasMcpRegistry.onLoadCanvas`＋`onNavigateToCanvas` | ✅ 結果跳轉用 |

## 4. 設計

### 4.1 服務層：ReceiptsSearchService（新）

```dart
class ReceiptsSearchService {
  static final instance = ReceiptsSearchService._();

  /// 聯合搜尋——五域並行，防抖 250ms，各域上限 8 筆
  Future<ReceiptsResults> search(String query, {ReceiptsSearchMode mode});
  // 內部：
  // 1. memories+assets → HybridSearchService.instance.search（既有引擎）
  // 2. conversations → in-memory 掃描（title+messages content，含 task-delivery 卡）
  // 3. tasks → TaskSessionStore.getAll() 過濾（title/instruction/summary）
}

class ReceiptsResults {
  final List<ConversationHit> conversations; // 對話（含命中訊息 excerpt+messageId）
  final List<MemoryHit> memories;            // 記憶（HybridSearchService 的型別）
  final List<AssetHit> assets;               // 資產（同上）
  final List<TaskHit> tasks;                 // 任務（TaskSession 包裝）
  bool get isEmpty => ...;
}

/// 跳轉座標——「搜尋結果是空間座標」的實體
class ReceiptHop {
  final ReceiptDomain domain; // conversation / memory / asset / task
  final String targetId;      // conversationId / memoryId / assetId / taskId
  final String? messageId;    // 對話域：跳到那則訊息
  final String? workCanvasId; // 任務域：跳工作畫布
}
```

### 4.2 UI：全局搜尋 overlay（Cmd+Shift+F 或頂部搜尋鈕）

- Raycast 風格命令面板：輸入框 + 分域結果列（💬 對話 / 🧠 記憶 / 📁 資產 / 🚀 任務）
- 點結果 → hop 執行：對話域 `switchConversation + scrollToMessage`；資產域 `navigate brain`（asset 節點 focus）；任務域 `loadCanvasById(workCanvasId)`
- 防抖 250ms + 各域上限 8，避免 UI 洪流

### 4.3 跳轉執行（空間座標落實）

| 域 | 跳轉動作 |
|---|--- Chat Sidebar switch + scroll |
| memory | 大腦圖譜 navigate（sub:mode focus） |
| asset | 大腦圖譜 navigate + asset focus |
| task | `onLoadCanvas(workCanvasId)` + `onNavigateToCanvas()` |

## 5. Commit 計畫（3 commits）

| # | 範圍 | 驗收 |
|---|---|---|
| RC1 | ReceiptsSearchService（五域聯合+測試） | 單元測試：mock ConversationStore/TaskSessionStore → 查「鹿角蕨」五域命中正確 |
| RC2 | 全局搜尋 overlay UI（防抖+分域列表+hop 執行） | widget 測試＋真實 App 搜「鹿角蕨」→ 點結果跳轉正確 |
| RC2.5 | 入口接線（頂部搜尋鈕＋快捷鍵） | 真人驗收：Cmd+Shift+F 開面板 |
| RC3 | Receipt chip 慣例推廣（agent 回答附出處） | 抽查 3 個 recall 命中顯示出處 chip |

## 6. 風險

| 風險 | 級 | 對策 |
|---|---|---|
| in-memory 對話掃描慢（大量對話） | 中 | 只掃 title+messages content 的 contains；未來移 FTS |
| 語義嵌入延遲 | 中 | 防抖+hybrid 模式才跑；fallback fullText |
| overlay 與既有 BridgeShortcuts 衝突 | 低 | Cmd+Shift+F 未被佔用（查過 keyboard-shortcuts skill） |

## 7. 待拍板（Blue 已授權建議值開工）

- 入口：頂部搜尋鈕＋Cmd+Shift+F（建議值，已採）
- 預設模式：hybrid（建議值，已採）
