# 改裝指南（Modding Guide）——給想改 Semi Bridge 的人

## 1. 加一個背景任務（3 行掛牌）

所有背景任務統一走 `BackgroundTaskRegistry`（活動中心單一真相源）：

```dart
BackgroundTaskRegistry.instance.update(BackgroundTask(
  id: 'my_task', name: '我的任務', detail: '做什麼',
  progress: 0.5, current: '當前檔案', startedAt: DateTime.now(),
));
// 結束時
BackgroundTaskRegistry.instance.finish('my_task', note: '完成 N 筆');
```

使用者會在系統活動中心看到它（忙碌必可見），還能 ⏸ 溫和暫停
（任務在批次邊界檢查 `isPauseRequested(id)`，不打斷當前筆）。

## 2. 動向量資料庫（asset_index）三鐵律

1. `embed_source` 的 `identity` 是**終態**——DB trigger 強制（翻案直接 ABORT）
2. 任何 UPDATE 必帶 `AND embed_source != 'identity'`
3. 禁 `INSERT OR REPLACE`（整 row 重建會丟嵌入成果）——用 `ON CONFLICT DO UPDATE`

偵錯三寶：audit trigger 留痕（embed_audit 表）、`sqlite3 ... "SELECT embed_source, COUNT(*) ... GROUP BY 1"`、時間戳分佈（indexed_at 找翻案波）。

## 3. 換本地模型

`models/recommended-models.json` 加一筆 → App UI 自動出現。
引擎級看門狗自動守護任何 GGUF（health poll + 自動復活），不用為新模型寫救援代碼。

## 4. 改懸浮夥伴窗（Companion Panel）

Swift 層的 CVDisplayLink 有「雙緩衝換片」設計——若改動影片渲染，記得：
- 換片時**立刻**停舊 display link（不要等首幀——鏈條斷了就是洩漏，我們修過 114 個殭屍 thread 的事故）
- 狀態推送**絕不擅自開窗**（`orderFrontRegardless` 是罪魁——使用者關閉是神聖意志）
