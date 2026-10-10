# 向量大腦（Vector Brain）— App 的記憶器官

![向量大腦 — 你的資料變成 3D 星系](screenshots/brain-galaxy.webp)

![星系節點詳情 — 點擊任一星點，右側展開完整節點資訊，檔案、照片、記憶都能直接開啟](screenshots/heart-galaxy-detail.webp)

> v1.0 · 2026-09-26 · 橋樑（Bridge）— The Bridge Between Humans and AI
>
> 橋樑不是一個「聊天 App 加了搜尋」。對話流過去就流過去了；
> **向量大腦把流過去的一切變成可檢索的身體記憶**——對話、檔案、圖片、
> 畫布上的工作流、Agent 的教訓，全部同一顆大腦收納。

---

## 1. 一句話

**大腦容器（brain_container）= 一顆 SQLite，裝下 App 的一生：
結構化記憶 + 向量嵌入 + 全文檢索 + 圖譜關係，四合一，本地跑。**

---

## 2. 為什麼需要它

| 沒有向量大腦 | 有向量大腦 |
|---|---|
| 「上次聊到那個方案是什麼？」→ Agent 兩手一攤 | 混合檢索一發命中，連當時的脈絡一起撈回 |
| 檔案丟進資料夾後就死了 | 自動分類、切塊、嵌入——檔案變成可問的 |
| Agent 每次撞牆都像第一次 | 撞過的坑變成坑卡（羅盤），教訓長期記住 |
| 換個對話視窗，一切歸零 | 跨對話、跨資料夾、跨時間的全域記憶 |

---

## 3. 四種記憶形態（一顆 DB 的四張臉）

### 3.1 agent_memories — Agent 的長期記憶

```
id / title / content / tags / memory_type / embedding(BLOB) / owner_companion_id
```

`memory_type` 實例：`milestone`（戰役里程碑）、`lesson`（教訓）、
`persona_card`（人格卡）、`skill`、`pattern`、`import_marker`。
每條帶 768 維 f32 BLOB 嵌入（`_sqliteai_vector` 虛擬表做向量鄰近搜尋）。

### 3.2 memories — 分房間的生活記憶

帶 `room` / `sub_category` / `agent` / `importance(1-5)` / `expires_at` / 分塊欄位
（`chunk_index` / `total_chunks` / `parent_memory_id`）——
**會過期的是提醒，不過期的是記憶**；重要性分級讓檢索有先後。

### 3.3 asset_index + asset_chunks — 檔案資產的內容索引

使用者丟進來的檔案（文件/圖片/程式碼）→ `file_classifier` 分類 →
切塊（chunk）→ 嵌入入庫。**檔案不再是路徑，是可問的內容。**
`folder_origin_service` 記住每個資產從哪個資料夾來——資料主權的账本。

### 3.4 圖譜關係 — 記憶之間的線

`wiki_links` / `topic_terms` / `memory_intentions` / `asset_causal_links`——
記憶不是平的清單，是網。大腦圖譜（3D 星系）把這張網渲染成可導航的空間。

---

## 4. 檢索：混合搜尋（Hybrid Search）

`hybrid_search_service.dart` — 一個查詢，三路合擊：

```
口語查詢「開光 心手眼」
   ├─ 向量鄰近（語意相似：意思近的就算用詞不同也命中）
   ├─ 全文檢索 FTS5（關鍵詞精確命中）
   └─ 五因子重排（five_factor_rerank：語意+關鍵詞+新鮮度+重要性+來源加權）
        ↓
   合併排序 → 記憶命中 + 檔案命中，一包回傳
```

實測（2026-09-26，v0.4.0 LightUp 戰役期間）：查「開光 心手眼」
→ 6 條記憶 + 5 個檔案命中——**跨形態、跨來源，同一個查詢入口**。

## 5. 嵌入管線（Embedding Pipeline）

```
新記憶/新檔案
   ├─ incremental_ingest_service   增量導入（檔案系統掛鈎，media_ingest_hook）
   ├─ identity_embed_text          文字 → 嵌入文本（記憶的「身分證文字」）
   ├─ embedding 服務（本地模型優先，fallback 雲端）
   │    本地引擎：LocalModelRuntime @ http://127.0.0.1:18789（llama-server 常駐）
   ├─ vision_embedding_pipeline    圖片 → 視覺嵌入（mmproj 多模態）
   └─ asset_chunk_backfill_service 歷史資產回填 / identity_reembed_service 重嵌
```

**嵌入一律本地可跑**（本地模型是優先路徑不是備援）——
這是資料主權宣言的直接實現：**你的記憶的指紋，不出你的機器也能算。**

---

## 6. 與其他系統的接線

| 接線 | 方向 | 內容 |
|---|---|---|
| 對話（Agent Loop） | 對話 → 大腦 | 每輪可向量檢索注入脈絡；對話歷史匯入器無損入庫 |
| 畫布 | 畫布 ⇄ 大腦 | 畫布工作流存檔入庫；vector_sketch_service 蒸餾畫布狀態 |
| 大腦圖譜（3D 星系） | 大腦 → 圖譜 | galaxy_data_service 從 brain_container 餵養節點——圖譜是大腦的皮質投影 |
| 羅盤 | 羅盤 ⇄ 大腦 | 羅盤意圖索引供口語檢索；羅盤卡片本身入向量庫 |
| 金鑰匙/主權系統 | 大腦 → 主權 | 除痕 ≠ 刪除：清暫存**絕不動**對話記憶與向量庫一個位元組 |
| 本地模型 | 大腦 → 18789 | 嵌入與蒸餾走本地 llama-server；斷網大腦照樣活 |
| MCP 層 | 大腦 → 外部 Agent | `vector_search` 工具——外部 Agent 直查這顆大腦 |

---

## 7. 設計鐵律

- **永不刪記憶**：`memories` 衰減可、`agent_memories` 永不刪——記憶鐵律
- **除痕 ≠ 刪除**：自動清理只清可再生暫存，向量庫一個位元組不動
- **單一真相源**：搜尋統一走 `VaultSearchFacade`，禁另建搜尋路徑
- **本地優先**：嵌入本地可算（18789），雲端是加值不是依賴
- **相對路徑必配 folder_root**：`file_path` 相對路徑必須與 `folder_root` 組絕對路徑（防搬家斷鏈）

---

## 8. 原始碼地圖

```
lib/services/brain_container/    大腦容器（DB 本體 + 匯入器 + 圖譜資料服務）
lib/services/vector_db/          檢索與嵌入全家（hybrid_search / rerank / ingest / vision）
lib/services/local_model_runtime_service.dart   本地模型引擎管理（18789）
```
