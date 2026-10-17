# 七金礦收穫計劃（Seven Mines Harvest Plan）

> 日期：2026-09-30 深夜定稿
> 起源：Blue 一句「電腦很遲鈍連打字都難」（2026-09-29）→ 兩天偵查 → 七座金礦
> 本文件 = 收穫的**體現計劃**：實質功能 / 系統架構 / UI-UX / 羅盤對應 / 改裝指南，五位一體。
> 原則：**只述已存在之物 + 已定案之工項**（§Blue產品律 09-29）。

---

## 0. 礦脈總表（一案一礦，全部實證）

| # | 金礦 | 一句話 | 根修 commit | 狀態 |
|---|------|--------|------------|------|
| 1 | 系統活動中心 | 背景任務從隱形變可視 | `feat: 金礦1+2` | ✅ 已上線 |
| 2 | 嵌入任務互踩 | identity 終態契約（WHERE 守門） | `fix: identity 終態保護` | ✅ 已上線 |
| 3 | CVDisplayLink 洩漏 | 114 殭屍渲染 thread 清零 | `fix: CVDisplayLink 洩漏根修` | ✅ 已上線 |
| 4 | 快測引擎 B' | 獨佔 GPU 測試→測完復活主線 | `feat: 金礦2 收尾` | ✅ 已上線 |
| 5 | 掃描架構債 | 指紋快取不落盤→重啟全量 hash | （定位報告在案卷） | 📋 待優化 |
| 6 | 懸浮窗殭屍復活 | 推送不得擅自開窗 | `fix: 懸浮窗關了又自己開` | ✅ 已上線（Blue 驗證） |
| 7 | embed_source 狀態機 | DB trigger 強制 identity 不可逆 | `feat: 第七金礦` | ✅ 終局 7096 筆 |

---

## 1. 實質功能（使用者可感知的）

### 1.1 已落地（本計劃只確認，不重做）
- **模型實驗室閉環**：選引擎（動態偵測本機模型）→ 快測 5 張 → 報告 → 一鍵「採用為現役」
- **系統活動中心卡**：系統頁頂部，任務進度即時可見，無任務自動隱形
- **懸浮窗尊重使用者**：關了就關了（6 秒輪播不再強制復活）
- **檢索升級 v2 全量到位**：identity 7096 筆、DB 層不可逆——搜「晨間拾穗」直接命中身份脈絡

### 1.2 待做功能（依優先序）
| 工項 | 來源礦 | 規格 | 驗收 |
|------|--------|------|------|
| **F1 指紋快取落盤** | #5 | tree fingerprint 存 brain_meta；啟動時載入比對，指紋一致跳過全量掃描 | App 重啟後 fullScan 秒跳（原 1 小時→<5 秒）；CPU 啟動峰值 <150% |
| **F2 活動中心全員掛牌** | #1 | AutoIngest / generateEmbeddings / VisionPipeline / ContentReembed 全接入 Registry；每任務顯示 名稱+進度+當前對象 | 任何背景任務執行時，活動中心卡可見其進度；「電腦為什麼忙」一眼可答 |
| **F3 hash 統一層** | #5 | file_hash 為唯一真相：fingerprint=stat、fullScan 與 generateEmbeddings 共用 hashCache，消除三重計算 | 同一輪掃描中每檔案只讀一次內容 |
| **F4 活動中心「暫停」** | #1 | 進行中任務可暫停/繼續（Registry 加 pause 訊號，任務在批次邊界檢查） | 重嵌進行中按暫停 → 5 秒內停止推進、狀態顯示⏸、恢復無重做 |
| **F5 本地大腦自動復活 v2（引擎級）** | （案卷） | llama-server 死亡偵測（health poll 失敗 2 次）→ 掛牌「重啟大腦中」→ 以**現役 modelId**（狀態讀取，不寫死型號）自動恢復。**適用所有開源模型**——任何 GGUF 登基都受同套保護（Blue 2026-09-30 令：不限定 12B） | 任何現役模型無聲死後 ≤2 分鐘自動回，UI 如實顯示，不再 stale「運行中」 |

---

## 2. 系統架構（結構性遺產）

### 2.1 已立架構
```
BackgroundTaskRegistry（單一真相源）
  ├── 任務掛牌/進度/收牌——UI 只是訂閱者
  └── 接入指南 → APP_ARCHITECTURE_MAP.md「embed_source 狀態機」節

embed_source 狀態機（DB 層）
  ├── trg_identity_guard：identity→其他 = ABORT（不可逆鐵律）
  ├── trg_embed_watch：所有變化留痕 embed_audit
  └── 應用層三規：UPDATE 帶守門 / 禁 INSERT OR REPLACE / 升級只走 IdentityReembedService

lab server 隔離（18799）
  └── 快測引擎與主生產線（18789）完全獨立；B' 快測流程自動停/復主線
```

### 2.2 待做架構（F1-F5 對應）
- **A1（配 F1）**：fingerprint 持久化介面 `TreeFingerprintStore`（brain_meta KV），fullScan 讀寫
- **A2（配 F2）**：Registry 標準 Reporter 介面——各 Service 注入 reporter 而非直接呼叫 UI
- **A3（配 F5）**：LocalRuntime 生命週期狀態（running/dead/restarting）單一真相源——引擎級抽象（llama-server 進程層，模型無關），UI 徽章不再 stale

---

## 3. UI / UX 介面

### 3.1 已落地
- 系統活動中心卡（無任務隱形＝安靜綠燈原則）
- 模型實驗室：引擎 chip 選擇器（帶檔案大小）＋快測進度跨頁生存＋報告「採用為現役」
- 測試引擎 UI 不寫死任何模型（動態掃描）

### 3.2 待做 UI
| 工項 | 規格 | Tier/DS 合規 |
|------|------|--------------|
| U1 活動中心展開視圖 | 點卡展開：任務清單（名稱/進度條/當前檔案/暫停鈕）；F2 完成後才有內容 | tier: card.body / list.item.* |
| U2 引擎健康徽章改革 | LocalRuntime 徽章反映真實生命週期（A3）：運行中=綠/死亡=紅「重啟大腦中」/離線=灰 | badge tier 既有 |
| U3 快測進度釘選 | 快測進行中，活動中心卡同步顯示「模型快測 N/5」（掛牌已接，驗證顯示） | 既有 |

### 3.3 UX 原則（本礦脈確立）
1. **安靜=綠燈**：無事發生時 UI 不佔空間（活動中心自動隱形）
2. **忙碌必可見**：任何 >30 秒的背景工作必須掛牌——「電腦為什麼忙」永遠一眼可答
3. **使用者意志神聖**：關閉的窗不復活、暫停的任務不偷跑
4. **狀態永不說謊**：UI 徽章只反映真實狀態（stale 寧可顯示未知）

---

## 4. 羅盤對應（compass_seed.dart）

### 已掛器官
| 器官 id | 名稱 | 對應礦 | 狀態 |
|---------|------|--------|------|
| `system.activity` | 系統活動中心 | #1 | ✅ 已實現 2026-09-30 |
| `model.lab` | 模型實驗室（選型閉環） | #4 | ✅ 已實現 |

### 待補器官（F 工項落地時同步掛）
| 器官 id（建議） | 名稱 | 觸發條件 |
|------------------|------|----------|
| `system.fingerprint` | 樹指紋快取（重啟不重掃） | F1 完成當下 |
| `runtime.autorevive` | 大腦自動復活 v2 | F5 完成當下 |

> 羅盤鐵律：長新器官前先查羅盤、完成後回寫——本表即回寫計劃。

---

## 5. 改裝指南（Modding Guide——開源社群视角）

### 5.1 給想加「背景任務」的改裝者
```dart
// 1. 任務開始時掛牌
final reporter = BackgroundTaskRegistry.instance;
reporter.update(BackgroundTask(
  id: 'my.task', title: '我的任務',
  progress: (done, total) => 'done/total', currentFile: path,
));
// 2. 過程中 update()；3. 結束 finish('my.task')
```
- 卡片自動出現在系統頁頂部；無任務自動隱形——零 UI 代碼
- **鐵律：>30 秒的工作必須掛牌**（本案動機：隱形任務=未來的 CPU 懸案）

### 5.2 給想動「向量資料庫」的改裝者
三條規則（違反 = 資料損毀或被 trigger ABORT）：
1. UPDATE asset_index 一律帶 `AND COALESCE(embed_source,'') != 'identity'`
2. **禁 `INSERT OR REPLACE`**——用 `ON CONFLICT(file_path) DO UPDATE` 且不碰 embed_source/embedding/content_text
3. 想升級嵌入到 identity → 只走 `IdentityReembedService`（唯一合法入口）
- 偵錯：`SELECT * FROM embed_audit ORDER BY ts DESC` 看誰動了 embed_source

### 5.3 給想換「測試引擎」的改裝者
- lab server（18799）與主線（18789）永遠隔離——快測崩潰不傷生產線
- 換任何 GGUF：丟進 models 目錄 → 實驗室選單自動出現（動態掃描）
- **帶 mmproj**（視覺模型必備，本案 HTTP 500 教訓）；`-ngl 99` GPU 卸載

### 5.4 給想改「懸浮夥伴窗」的改裝者
- 狀態推送永不開窗（`orderFrontRegardless` 只在 lifecycle('show') 路徑）
- CVDisplayLink：弱引用 callback + 換片立刻停舊 link（114 殭屍 thread 之鑒）

---

## 6. 執行順序（明天起）

```
D1: F1 指紋落盤（最大痛點：重啟 1 小時掃描）→ 羅盤掛 system.fingerprint
D2: F2 活動中心全員掛牌 → U1 展開視圖
D3: F5 大腦自動復活 v2（引擎級，所有開源模型通用）+ A3 狀態真相源 → U2 徽章改革 → 羅盤掛 runtime.autorevive
D4: F3 hash 統一層（順手 F4 暫停鈕）
D5: semi-dao/semi-bridge 上傳（原 covision-bridge 已正式更名；bench 數據+實驗室文件+本改裝指南節選）
```

驗收鐵則：每項 `flutter analyze` 零錯誤 + 實機驗證 + commit + 羅盤/地圖同步回寫。

---

## 7. 案卷索引（證據鏈）
- 偵查方法論：skill `bridge-app-cpu-forensics`
- 架構鐵律：`docs/APP_ARCHITECTURE_MAP.md` §embed_source 狀態機
- 時間線證據：git log 2026-09-29~30（12 commits）；embed_audit 表 2947 筆留痕
- 終局數據：identity=7096 / content=0 / audit 零異動 / 12B health ok @18789
