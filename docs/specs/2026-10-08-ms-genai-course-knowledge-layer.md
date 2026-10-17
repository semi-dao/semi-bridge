# 微軟生成式AI課程 → H2 知識層接合（Phase H2 知識支線）

> 日期：2026-10-08｜拍板：Blue（本 thread）
> 定位：**課本，不是房客**——不進插槽系統，進夥伴的知識層（H2 記憶 2域10層）。
> 由來：Blue 找到 microsoft/generative-ai-for-beginners，問如何接合橋樑App；
> 小葵提三案，Blue 拍板「走夥伴的知識層」，並指示由 H1 session 順路接線——
> 本 spec 即為該 session 的施工藍圖。

## 1. 來源盤點（2026-10-08 實查）

- **Repo**：https://github.com/microsoft/generative-ai-for-beginners
  （121k ⭐、63.7k fork、MIT License、2,497 commits）
- **內容**：21 課 markdown 課文 + Python/TypeScript 範例 + 作業 + 測驗 +
  影片連結；另有 `presentations/`（PPT）與 `translations/`（~50 語言）
- **授權**：MIT——允許改編、再製、商業使用，**只需保留版權聲明**。
  我們做「橋樑視角改編版」合法且被鼓勵
- **zh-TW 版現況**：存在（`translations/zh-TW/`），但由 Co-op Translator
  （微軟自家 AI 翻譯工具）產出，檔尾自帶免責聲明「自動翻譯可能包含錯誤」。
  實讀第 16 課樣本：術語正確（開放原始碼模型/專家混合/微調）、行文流暢，
  屬「中上機翻」等級——**可作底稿，重點課需人工校**

## 2. 為什麼不是插槽（決策紀錄）

插槽准入準則（Blue 定）：必須**幫助橋樑運行或加強功能**，是
「agent 產出→插槽渲染→人看見」的共視工具。本課程是給人讀的知識、
不是可執行網頁 App（無 index.html 成品屋），硬塞插槽＝獨立於橋樑的成品
＝重蹈 exif-viewer 被否路線。**知識走記憶，工具走插槽，各歸其位。**

## 3. 價值對位：Azure 課本 vs 橋樑立場

課程主視角 = Azure + OpenAI 雲端中心；橋樑立場 = 本地模型主權、
Token 自由、數位資產主權。**有張力但可利用**：吸收策略是
「挑選＋補觀點」，不是整包搬——每張知識卡帶一段「橋樑視角」註解，
把微軟教的通用概念錨到本地主權語境。這是差異化機會：市面上教 AI 的
教材都在教「怎麼依賴大廠」，橋樑可以教「怎麼擁有自己的 AI」。

## 4. 21 課對齊度分級（選材依據）

### A 級（高對齊，優先入庫＋人工校）

| 課 | 主題 | 對齊點 |
|---|---|---|
| 04 | Prompt 工程基礎 | 夥伴對話品質的地基 |
| 05 | 進階 Prompt | 同上 |
| 15 | RAG 與向量資料庫 | 橋樑 vault/向量檢索正是 RAG 實作 |
| 16 | 開源模型 | 本地模型主權核心課 |
| 17 | AI Agents | 夥伴系統的理論框架 |
| 19 | SLM 小模型 | 本地 E4B/12B 分工的學理背書 |

### B 級（概念有用，需橋樑視角註解）

01 入門、02 比較 LLM、03 負責任使用、11 function calling（→MCP 前身）、
12 AI 應用 UX（→共視宣言可對話）、18 微調、13 安全（→DataPathGate 對話素材）

### C 級（雲端味重，概念稀釋後取精華）

06/07/08/09/10（各類應用實作，Azure 服務綁定）、14 生命週期、
20 Mistral、21 Meta 課

## 5. 入庫設計（H2 對接）

### 5.1 資料位置

- 表：`agent_memories`（brain_container.db）
- `memory_type = 'course_knowledge'`（新類型，同 lesson/pattern 命名風格）
- `layer = 'L4'`（B 長期域：檢索命中、無上限）——知識不進 L1-L3
  工作域，**注入窗口大小不變**（H2 的核心承諾不被破壞）
- `tags = ['course', 'ms-genai', 'L<n>課號']`；`title = '[AI課程] <課題>'`
- `owner_companion_id = 'shared'`——所有夥伴共享這位 AI 老師

### 5.2 知識卡格式（每課一卡，非全文入庫）

```
<課程標題 zh-TW>
核心觀念：3-5 條精華（非逐段摘要）
橋樑視角：本地主權語境的對位註解（小葵執筆）
實作線索：對應橋樑的模組名（vault/夥伴/DataPathGate…）
出處：microsoft/generative-ai-for-beginners 第N課（MIT）+ 原文連結
```

- 全文太大且 FTS 檢索粒度差；卡 = 檢索命中點，卡內連結指向完整原文
  （原文另存檔案層，見 5.4）
- embedding 照 agent_memories 既有 768 維 f32 BLOB 慣例

### 5.3 攝取管線（給 H1 session 的施工圖）

1. **抓取**：codeload tarball 或 sparse-checkout（README 自述 translations
   佔大量體積——用 `git sparse-checkout` 排除其他語言，只取
   `translations/zh-TW/**` 與英文原文）
2. **清洗**：去 `WT.mc_id` 追蹤碼、徽章圖片、行銷連結、Co-op Translator
   免責聲明尾段
3. **產卡**：A 級課逐課產知識卡（人工校）；B/C 級先入英文要點卡，
   zh-TW 校稿排後批次
4. **入庫**：冪等寫入（title+memory_type 查重），模板抄
   `tools/m4_hermes_memory_import.py`（§ 分段/關鍵字路由/冪等三層防護
   都已驗證過）
5. **驗收**：
   - `MemoryLayerService.search('RAG')` 命中第 15 課卡（注意 CJK bigram
     LIKE 路徑——FTS5 unicode61 不分詞中文，第三次踩同款坑別再踩）
   - `workingSnapshot()` bytes 與入庫前相同（知識零注入，只有檢索命中）
   - M5 容量儀表 L4 計數 +21 左右、無超額徽章
   - 動 DB 前備份（H2 慣例：`/tmp/brain_backup_<階段>.db`）

### 5.4 原文保存

清洗後 zh-TW 課文 + 英文原文存
`{BRIDGE_APP_HOME}/knowledge/ms-genai-course/`（檔案層，不進 DB）——
卡是索引，原文是書。未來做「教材閱讀器」UI 時直接讀這裡。

## 6. 授權義務（開源紀律）

MIT 要求保留版權與授權聲明：知識卡「出處」欄 + 原文保存夾內放
LICENSE 副本與來源 repo 連結。橋樑視角註解是我們的原創內容，無衍生
義務問題（MIT 允許改編）。

## 7. 開放問題（H1 session 施工時順路回報）

1. `memory_type` 新值是否需要 UI 端 enum 擴充（比照 DataPathClass
   enum 擴充法：附加尾端＋全 switch 補 case＋analyze 掃）——施工時 grep
   `memory_type` 的 switch 消費點確認
2. 課程影片（YouTube 連結）不入卡——離線主權原則，卡內只留文字知識
3. 未來其他課本（如 ML-for-Beginners）沿用同管線：memory_type 用
   'course_knowledge' 共用、tags 區分來源
