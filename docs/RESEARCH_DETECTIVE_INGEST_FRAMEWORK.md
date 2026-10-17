# 偵探式資料導入框架 — 研究報告

> **文件性質**：純研究文件，無程式碼修改。
> **專案**：橋樑 App（Flutter macOS 桌面 App，`<HOME>/Developer/bridge_app`）
> **對象**：千千萬萬使用者的「個人第二大腦」資料導入設計
> **作者**：研究子代理（指派於 2026-08-19）
> **狀態**：設計參考；待主代理裁示後才能進入實作

---

## 0. 為什麼需要這份研究

**現況盤點**（誠實紀錄）：

- 向量資料庫的 `asset_index` 表已累積 **26,022 筆檔案 + embedding**，`memories` 表 **219 條**。
- `AssetRecord` 模型的 `title` 欄位直接拿 `fileName`（如 `inspection-record-1783...`），沒有語意化重命名。
- `FileClassifier` 只做「副檔名 → 六大房間」的規則對應（`bridges.dart` 第 110-182 行），沒有：
  - 命名模式識別（`inspection-record-1783` → 「2026 年的某個檢驗紀錄」？）
  - 資料夾結構語意分析（深度、分組暗示）
  - 時間聚類（活躍期、沈寂期、爆發期）
  - 使用者畫像推斷（這個人是做什麼的？）
  - 分層處理（熱/溫/冷檔案；抽樣分析）
- `OnboardingFlow` 只有「選 DB 位置」一步，沒有任何「導入 → 判讀 → 呈現」的偵探式引導（`onboarding_flow.dart` 第 30-45 行 `OnboardingStep` enum 只有 4 步：選路徑 / 初始化 / 完成 / 錯誤）。
- 過去在圖譜端嘗試「修補」標題與分類，但屬於事後整容，無法處理根本的「沒有 metadata 可用」問題。

**核心假設**：一個檔案被 ingest 後，metadata 必須一次到位地涵蓋「人類可讀的語意」、「圖譜視覺化的形狀線索」、「agent RAG 檢索的特徵向量」三種消費者；事後補丁只是把爛資料餵進圖譜，讓雜訊無限放大。

---

## 1. 研究框架與限制

### 1.1 本研究做了什麼

- **業界研究**（9 次 web 查詢，涵蓋檔案分類、檔案命名偵測、資料分層、schema.org、Obsidian properties、Graph RAG、EXIF、duplicate detection、user onboarding UX 等）。
- **現有程式碼盤點**（讀完 `asset_index_service.dart` 1621 行、`file_classifier.dart` 312 行、`asset_sandbox.dart` 183 行、`onboarding_flow.dart` 497 行 — 全檔）。
- **現有文件參照**（`docs/` 44 份文件、`AGENTS.md` 已確認本尊路徑）。

### 1.2 本研究**沒做**什麼（誠實標註）

- **沒跑實際 ingest benchmark**：沒有對 26,022 筆真實資料做模擬導入，所以「每檔耗時 / token 成本 / GPU 預算」等數字只能引用業界經驗值，不可作為橋樑 App 的實測承諾。
- **沒做使用者訪談**：所有「使用者畫像推斷」維度來自業界研究 + 對現有 26,022 筆檔案結構的觀察推測，不是基於目標使用者的真實田野。
- **沒做向量檢索實驗**：metadata schema 設計基於 schema.org / Obsidian / Para 慣例與 Graph RAG 文獻，沒在 26,022 筆真實資料上跑 A/B 測試。
- **沒寫程式碼**：本文件**純研究**，禁止修改任何 `.dart` 檔，僅本文件可寫入。

### 1.3 設計約束（取自現有專案）

- **平台**：macOS 桌面（手機版已刪除，2026-08-10）。
- **本地模型**：Gemma-4-e4b（`http://127.0.0.1:18789`）已用於蒸餾（`asset_index_service.dart` 第 836 行）。
- **資源預算**：GPU ≤ 5% / CPU ≤ 8% / 記憶體 ≤ 200MB（取自 `BRIDGE_ATMOSPHERE_LANGUAGE.md`）。
- **沙盒安全**：使用者檔案位置不動、結構不動，系統只在 `.bridge/` 裡整理索引（`asset_sandbox.dart` 註解）。
- **無孤兒原則**：任何檔案都必須歸入一個房間（`file_classifier.dart` 第 10 行），這條原則會延伸到「每個檔案都必須有完整 metadata」。

---

## 2. 業界如何做「未知資料夾的自動分析」

### 2.1 三大主流路徑

| 流派 | 代表產品 / 標準 | 核心手法 | 借鑑價值 |
|---|---|---|---|
| **NAS 自動歸檔** | QNAP Qfiling | 副檔名 + 規則模板（預設照片/影片/音樂/文件/email 五類） | 提供「最小可行分類骨架」；複雜度低，但只到第二層 |
| **企業資料治理** | NetApp Data Classification、Komprise、PII Detection | Magic Bytes 內容掃描 + ML 自動標籤 + 合規風險評等 | 提供「分層掃描 + 抽樣標註」的工業級範式；token / 計算成本估算成熟 |
| **雲端個資偵測** | Google Cloud DLP、Azure PII、Sensitive Data Protection | 預訓練 NER + 規則 + 信賴度閾值；分頁流式處理 | 提供「內容分析 → 結構化標籤」的可信度評分模型 |

### 2.2 檔案類型統計（深度優先、第一道關卡）

**業界共識**：先做「副檔名分布」+「Magic Bytes 抽樣驗證」。

- **副檔名**：極快、極便宜，可過濾掉 80% 雜訊（系統檔、build artifact、快取）。
- **Magic Bytes**：讀前 16-byte header，驗證副檔名是否說謊。常見特徵：
  - `89 50 4E 47 0D 0A 1A 0A` = PNG
  - `FF D8 FF` = JPEG
  - `25 50 44 46` = PDF
  - `50 4B 03 04` = ZIP（注意：.docx / .xlsx 也是 ZIP，容易誤判，需進一步 sniff）
  - `MZ` = Windows PE（執行檔）
  - 來源：[textslashplain.com](https://textslashplain.com/2023/04/05/file-types)、[npmjs.com/package/mimetics](https://www.npmjs.com/package/mimetics)

**橋樑應用建議**：在 `AssetIndexService._inferAssetKind()` 之外，新增一個 `_sniffMagicBytes()` 助手；當副檔名說「.pdf」但 magic bytes 說「ZIP」時標記 `kind_mismatch` 警告（而非直接拒絕，因為 .docx 本質就是合法 ZIP）。

### 2.3 命名模式識別（命名偵探）

**業界研究來源**：
- [Sortio Glossary — Filename Pattern Matching](https://www.getsortio.com/glossary/filename-pattern-matching)
- [Harvard Data Management — File Naming Conventions](https://datamanagement.hms.harvard.edu/plan-design/file-naming-conventions)
- [StackOverflow — Parsing file names using regular expressions](https://medium.com/@jamestjw/parsing-file-names-using-regular-expressions-3e85d64deb69)

**常見命名 pattern 與訊號**：

| Pattern | Regex 範例 | 訊號意義 |
|---|---|---|
| **ISO 日期前綴** | `^\d{4}-\d{2}-\d{2}_` 或 `^\d{8}_` | YYYYMMDD 是學術/工程界最常用排序法 |
| **專案代號** | `^[A-Z]{2,5}-\d{3,5}` | 暗示多檔案屬於同一專案 |
| **序號** | `_\d{3,6}(\.|$)` | 暗示序列（照片 burst、文件版本） |
| **狀態前綴** | `^(WIP\|DONE\|DRAFT\|FINAL)_` | 軟體開發常見 |
| **作者縮寫** | `^[A-Z]{2,4}_\d{8}` | 協作環境常見（如 `JD_20240315.docx`） |
| **版本後綴** | `_v\d+\|\.v\d+\|_final\|_FINAL` | 提醒重複檔案 |
| **平台/客戶前綴** | `^(IG\|YT\|ClientA\|FB)_` | 自媒體經營者常見 |

**橋樑應用建議**：新增 `NamingPatternDetector` 服務，產出 `NamingHint { datePrefix?, projectCode?, sequence?, status?, author?, version? }`。當偵測到 `projectCode` + 跨資料夾一致時，自動建議「這批檔案構成一個專案」並在 metadata 標 `linked_project`。

### 2.4 資料夾結構語意

**業界研究來源**：
- [MDPI 2024 — Mapping Hierarchical File Structures to Semantic Data Models](https://www.mdpi.com/2306-5729/9/2/24)
- [aosmith.rbind.io — Analysis essentials: An example directory structure](https://aosmith.rbind.io/2018/10/29/an-example-directory-structure)

**觀察維度**：

1. **深度**：扁平（≤2 層）通常意味「個人隨手放」；深巢狀（>5 層）意味「結構化歸檔者」（開發者、設計師、研究者）。
2. **命名暗示**：資料夾名稱含 `archive/`、`backup/`、`old/`、`_deprecated/`、`__pycache__/`、`node_modules/` → 通常是「冷資料」/「可排除」。
3. **分組暗示**：`YYYY/`、`YYYY-MM/`、`YYYY-MM-DD/` → 時間軸分類法（攝影師、記者、日記寫作者）；`client_<name>/` → 客戶/專案導向（設計師、顧問）；`topic/` 或 `theme/` → 主題導向（研究者、知識工作者）。
4. **特殊目錄**：`.git/`、`node_modules/`、`__pycache__/`、`venv/`、`.venv/`、`build/`、`dist/`、`target/` → 工具產物，預設排除。

**橋樑應用建議**：在 `_scanDirectory()` 之上加一個 `DirectoryProfile`，對每個根資料夾產出：
- `depthHistogram`（層 1 / 2 / 3+ 各幾個）
- `namingConvention`（時間軸 / 客戶 / 主題 / 扁平）
- `siblingCount`（平均每資料夾有幾個檔案）
- `hotnessHint`（最後修改時間中位數 → 判定活躍度）

### 2.5 時間聚類（活躍期偵測）

**業界研究來源**：
- [Science.gov — Temporal clustering analysis](https://www.science.gov/topicpages/t/temporal+clustering+analysis)
- [Sleuth Kit Autopsy — Timeline Analysis](https://www.sleuthkit.org/autopsy/timeline.php)
- [Towards Data Science — Time Series Clustering](https://towardsdatascience.com/time-series-clustering-deriving-trends-and-archetypes-from-sequential-data-bb87783312b4)

**演算法建議**：

1. **K-means on month buckets**：把所有檔案的最後修改時間以「月份」分桶，跑 K-means 找 K=3~5 個聚類，產出「活躍期 / 沈寂期 / 爆發期」。
2. **Burst detection**（Kleinberg 2002）：找「突然大量產出」的事件；自媒體經營者的「週三排程日」、記者的「採訪週」、研究者的「論文 deadline 前一週」都會表現為 burst。
3. **Life stage clustering**：觀察「明顯的長沈寂期」（>6 個月沒有任何檔案）→ 推斷「這個使用者曾經中斷這個工作領域 X 年」。

**橋樑應用建議**：`TimeClusterDetector` 服務產出 `TimeProfile { activeBursts: List<Burst>, dormantPeriods: List<Range>, lifeStages: List<Stage> }`，寫入 metadata `temporal_profile`。

---

## 3. 使用者畫像推斷（從檔案組成推斷工作類型）

### 3.1 訊號維度表

| 維度 | 強訊號 | 弱訊號 | 推斷職業 |
|---|---|---|---|
| **程式碼比例** | `.py` / `.dart` / `.ts` / `.go` > 30% | 5-15% | 軟體工程師 |
| **照片比例 + EXIF** | `.jpg` + EXIF 完整（光圈/快門/ISO）+ `.xmp` sidecar | 大量截圖 | 攝影師 |
| **設計檔** | `.sketch` / `.fig` / `.psd` / `.ai` + 大量 `.png` | 偶爾 `.fig` | UI 設計師 / 平面設計師 |
| **筆記比例** | `.md` / `.txt` > 40% 且長度中位數 > 500 字 | 短篇筆記為主 | 知識工作者 / 研究者 / 作家 |
| **影片比例** | `.mp4` / `.mov` > 20% + `.srt` / `.vtt` 字幕檔 | 偶爾短片 | 影像創作者 / YouTuber / 剪輯師 |
| **資料檔比例** | `.csv` / `.xlsx` / `.parquet` + `notebooks/` 資料夾 | 偶爾 `.csv` | 資料分析師 / 量化研究員 |
| **平台檔案** | 大量 `IG_` `YT_` `FB_` `小紅書_` 前綴檔案 + 排程稿 | 平台前綴 < 5% | 自媒體經營者 |
| **客戶/案件檔** | `client_<name>/` 或 `<年份>_<客戶代號>/` 結構 | 偶爾有客戶資料夾 | 顧問 / 接案設計師 / 律師 / 會計師 |
| **學術檔** | `.bib` / `.tex` / `.pdf` + `paper` `journal` 關鍵字 | 偶爾 PDF | 學術研究者 / 研究生 |
| **音訊比例** | `.mp3` / `.wav` / `.flac` > 20% + `.lrc` 歌詞 | 偶爾音檔 | 音樂人 / DJ / Podcast 製作 |
| **專案檔** | `.bridge-project` 或命名統一前綴 + `PRD.md` `spec.md` | 結構鬆散 | 產品經理 / 軟體 PM |
| **個人日記** | `日記/` `journal/` `diary/` 資料夾 + 日期前綴命名 | 偶爾有日期檔名 | 自我反思者 / 心理記錄者 |
| **學習教材** | 大量 `.pdf` + `coursera` `udemy` `課程` 關鍵字 + 截圖 | PDF 中等 | 學生 / 終身學習者 |

### 3.2 推斷方法

**兩階段**：

1. **規則啟發（Rule-based Heuristic）**：上面 13 個維度，每個維度給一個 score（依比例與強度），加總取最高分。
2. **本機模型驗證（Local Model Verification）**：把「檔案類型分布 + 命名樣本 + 資料夾名稱 top 20」餵給 Gemma-4-e4b，要求輸出 JSON `{ "primary_role": "...", "secondary_roles": [...], "confidence": 0.X, "evidence": "..." }`。規則 score 與模型 confidence 加權平均。

**橋樑應用建議**：產出 `UserPersona { primaryRole, secondaryRoles[], confidence, evidenceSignals[] }`，存於 `asset_index_summary` 或單獨的 `user_persona` 資料表（後者較佳，方便歷史追蹤 persona 演化）。

### 3.3 persona 對元資料的後果

- **攝影師**：自動偏好 EXIF-based metadata（光圈/ISO/焦段），UI 顯示照片優先用「光圈模式」群組。
- **自媒體經營者**：自動偵測排程稿（檔名含 `schedule` `排程` `草稿` `scheduled`），與平台分析報表（`.csv` from Meta Business Suite / YouTube Studio）建立交叉連結。
- **軟體工程師**：自動辨識 `repo` 結構（`.git/` 標記），與 commit history 連結；程式碼不蒸餾（無法 RAG），改為「符號索引 + 依賴圖」。
- **知識工作者**：自動把筆記（`.md`）轉成 Obsidian-compatible frontmatter，雙向連結優先。

---

## 4. metadata schema 設計

### 4.1 設計目標

一個 metadata 必須同時服務三種消費者：

1. **人類閱讀**：在 UI 上看圖譜時，節點標籤要語意化、要美觀。
2. **圖譜視覺化**：節點大小、顏色、邊線、群組由 metadata 驅動。
3. **Agent RAG 檢索**：embedding 與結構化查詢都能用。

### 4.2 業界標準盤點

| 標準 | 來源 | 借鑑點 | 限制 |
|---|---|---|---|
| **schema.org / CreativeWork** | [schema.org/CreativeWork](https://schema.org/CreativeWork)、[DigitalDocument](https://schema.org/DigitalDocument) | 標準化欄位：`dateCreated`、`dateModified`、`author`、`keywords`、`genre`、`isPartOf`、`mentions` | 偏 web/SEO，個人知識管理不夠細 |
| **Obsidian Properties** | [Obsidian Rocks — Properties](https://obsidian.rocks/an-introduction-to-obsidian-properties)、[Complete Guide to Obsidian Properties](https://www.dsebastien.net/the-complete-guide-to-obsidian-properties) | YAML frontmatter 結構、可嵌套、type-system 友善（text/list/date/number） | 只服務筆記類檔案；圖片/影片需另尋 |
| **OKF (Open Knowledge Format)** | [Google Cloud OKF](https://okf.md/faq) | 「每個 .md 都有 YAML frontmatter + `type` 必填」這條規則極簡 | 仍是 Markdown-only |
| **Basic Memory** | [docs.basicmemory.com/concepts/knowledge-format](https://docs.basicmemory.com/concepts/knowledge-format) | 強調「AI 自動填寫 + schema 強制」閉環 | 偏筆記觀察 |
| **DataBooks (Markdown as Semantic Infrastructure)** | [ontologist.substack.com](https://ontologist.substack.com/p/databooks-markdown-as-semantic-infrastructure) | YAML + Turtle/RDF 混合；graph metadata 直接嵌檔 | 複雜度偏高 |
| **EXIF / IPTC / XMP** | [picdefense.io EXIF guide](https://picdefense.io/blog/ultimate-guide-to-exif-metadata-analysis)、[photographylife.com](https://photographylife.com/what-is-exif-data) | 影像專屬 metadata：光圈/ISO/焦段/GPS/camera model | 限影像 |
| **ID3 (音訊)** | 業界標準 | 音訊 metadata：artist/album/genre/year/lyrics | 限音訊 |

### 4.3 完整 schema 欄位定義表（提案）

> **設計原則**：區分**核心（每個檔案都有）**、**類型專屬（圖片/音訊/文件/程式碼/影片各加）**、**衍生的（透過分析產生）**三層。

#### A. 核心欄位（必填）

| 欄位 | 型別 | 消費者 | 說明 | 對應 schema.org |
|---|---|---|---|---|
| `id` | string (UUIDv7) | 所有 | 唯一識別，UUIDv7 內含時間序 | `identifier` |
| `path` | string | 所有 | 相對於根資料夾的路徑 | `url` |
| `root_folder` | string | 所有 | 來源根資料夾 | — |
| `file_name` | string | 所有 | 原始檔名 | `name` |
| `file_ext` | string | 所有 | 副檔名（小寫，含 `.`） | `encodingFormat` |
| `file_size` | int (bytes) | 圖譜 | 圖譜節點大小可映射 | `contentSize` |
| `file_hash` | string (SHA256) | 增量 | 內容指紋，用於去重與變更偵測 | `sha256` |
| `kind` | enum | 所有 | `image/video/audio/document/code/data/other` | `@type` |
| `kind_mismatch` | bool | 偵錯 | magic bytes ≠ 副檔名時 true | — |
| `created_at` | ISO 8601 | 所有 | 檔案建立時間（從 EXIF 或檔案系統） | `dateCreated` |
| `modified_at` | ISO 8601 | 所有 | 最後修改時間 | `dateModified` |
| `indexed_at` | ISO 8601 | 偵錯 | 進入橋樑資料庫的時間 | — |
| `tier` | enum (`hot/warm/cold/frozen`) | 圖譜 + 效能 | 熱/溫/冷/凍資料分層 | — |
| `source_type` | enum (`imported/system/agent`) | 圖譜 | 來源類型（沿用現有） | — |

#### B. 人類可讀語意欄位

| 欄位 | 型別 | 消費者 | 說明 |
|---|---|---|---|
| `display_title` | string | **UI 主標題** | **取代檔名的語意化標題**（例：`inspection-record-1783` → `2026-Q1 屋頂檢驗紀錄 #1783`） |
| `display_summary` | string (<=200 字) | UI 卡片副標、tooltip | 一行摘要，由 Gemma 蒸餾產出 |
| `description` | string (<=2000 字) | UI 詳情面板 | 完整描述，多來源彙整（檔案 metadata + 內容摘要 + persona 註解） |
| `tags` | list<string> | 圖譜 + RAG | 5-15 個關鍵字，含中文/英文 |
| `human_categories` | list<string> | 圖譜分組 | 人類友善分類（如：`專案 / 2026 / 客戶A`） |

#### C. 六大房間 / 主題分類

| 欄位 | 型別 | 消費者 | 說明 |
|---|---|---|---|
| `room` | enum | 圖譜（節點顏色） | 沿用 `FileRoom`：stream/doors/pendulums/heartMind/fraile/bridges |
| `topic_cluster` | string | 圖譜（群組） | 主題群集 ID（如 `project_alpha`、`client_B_logs`） |
| `linked_project` | string? | 圖譜（邊） | 若偵測到命名 pattern 含 project code，指向 `projects` 節點 ID |
| `classification_confidence` | float (0-1) | 偵錯 | 規則 + LLM 加權後的信心分 |
| `classification_source` | enum (`rule/llm/human`) | 偵錯 | 分類來源 |

#### D. 時間軸欄位

| 欄位 | 型別 | 消費者 | 說明 |
|---|---|---|---|
| `event_date` | ISO 8601? | 圖譜（時間軸） | 若是事件型檔案（照片/會議記錄），事件本身發生的時間（≠ 檔案 modified） |
| `temporal_cluster` | string? | 圖譜（時間軸群組） | 從時間聚類得到的 burst ID（例：`burst_2026Q1_week3`） |
| `life_stage` | string? | persona | 此檔案所屬的人生階段（如 `career_2024_2026`） |

#### E. 連結線索欄位（給 RAG 與圖譜）

| 欄位 | 型別 | 消費者 | 說明 |
|---|---|---|---|
| `mentions` | list<string> | RAG + 圖譜 | 提到的實體（人名/專案/概念），用 NER 抽取 |
| `mentioned_by` | list<string> | 圖譜（反向邊） | 反向索引：哪些檔案提到了這個檔案 |
| `co_occurs_with` | list<string> | 圖譜（邊權重） | 在同一 burst / 同一資料夾 / 同一專案中共同出現 |
| `supersedes` | string? | 偵錯 + 圖譜 | 若偵測到此檔案是某檔案的新版，指向舊版 |
| `duplicates` | list<string> | 偵錯 | 內容 hash 相同的其他檔案（備份碟/匯出複本） |

#### F. 內容萃取欄位（蒸餾產物）

| 欄位 | 型別 | 消費者 | 說明 |
|---|---|---|---|
| `summary_one_liner` | string | RAG | Gemma 蒸餾的一行摘要 |
| `keywords` | list<string> | RAG | Gemma 萃取 3-5 個關鍵詞 |
| `resolution` | string? | RAG | 若為問答/教學文件，提取的解決方案 |
| `related_systems` | list<string> | RAG | 相關工具/系統 |
| `embedding_text` | string (derived) | RAG | 用於 embedding 的合併文字：`summary + keywords + resolution` |
| `embedding_model` | string | 偵錯 | 哪個模型產生的 embedding |

#### G. 圖片專屬（EXIF/IPTC/XMP）

| 欄位 | 型別 | 消費者 | 說明 |
|---|---|---|---|
| `width` / `height` | int | 圖譜節點大小 | 像素 |
| `camera_make` / `camera_model` | string | 圖譜群組 | 相機廠牌/型號 |
| `lens` | string | 圖譜群組 | 鏡頭型號 |
| `aperture` / `shutter` / `iso` | float | 圖譜群組 | 光圈/快門/ISO |
| `focal_length` | float | 圖譜群組 | 焦段 |
| `gps_lat` / `gps_lng` | float? | 地圖視圖（未來） | 經緯度（**注意隱私：預設不啟用聚合地圖**） |
| `taken_at` | ISO 8601? | 時間軸 | 拍攝時間（≠ 檔案 modified） |
| `color_palette` | list<hex> | 圖譜節點顏色 | 5 個主色，用 k-means 抽 |

#### H. 音訊專屬（ID3 + 其他）

| 欄位 | 型別 | 消費者 | 說明 |
|---|---|---|---|
| `artist` / `album` / `title` | string | 圖譜分組 | ID3 |
| `duration_sec` | float | UI | 長度 |
| `bpm` / `key` | string? | 進階分析 | 若為音樂 |

#### I. 文件/程式碼專屬

| 欄位 | 型別 | 消費者 | 說明 |
|---|---|---|---|
| `language` | string | UI | 程式語言 / 自然語言 |
| `word_count` | int | 統計 | 純文字檔案 |
| `heading_count` / `section_count` | int | 圖譜 | Markdown 結構化指標 |
| `links_out` | list<string> | 圖譜邊 | Markdown / HTML 超連結 |
| `symbols` | list<string> | 程式碼專屬 | 函式/類別名稱（如有 AST 解析） |

### 4.4 與現有 AssetRecord 對照

| 現有欄位 | 新 schema 對應 | 處理建議 |
|---|---|---|
| `id` | `id` | 保留 |
| `filePath` | `path` | 保留 |
| `folderRoot` | `root_folder` | 保留 |
| `fileName` | `file_name` | 保留 |
| `fileExt` | `file_ext` | 保留 |
| `fileSize` | `file_size` | 保留 |
| `fileModified` | `modified_at` | 保留 |
| `indexStatus` | （改為 `indexed_at`） | 重命名 |
| `indexedAt` | `indexed_at` | 保留 |
| `title` | **拆為 `file_name` + `display_title`** | `title` 仍存檔名，`display_title` 為新欄位 |
| `summary` | `display_summary` | 重新命名（更語意化） |
| `contentText` | 內嵌於 `embedding_text` | 不直接外露 |
| `assetKind` | `kind` | 保留（值不變） |
| `tags` | **保留並擴展** | 同名但內容更豐富 |
| `source` | **改為 `source_type`** | 重命名（與新 schema 對齊） |
| `room` | `room` | 保留 |
| `projectId` | `linked_project` | 重命名 |
| `classificationConfidence` | `classification_confidence` | 保留 |
| `sourceType` | （與 `source` 合併） | 移除 |
| `fileHash` | `file_hash` | 保留 |

**結論**：現有 `AssetRecord` 已是良好基礎，但需要**新增 14 個核心欄位 + 18 個衍生欄位**，並把「檔名 = 標題」這個錯誤徹底改掉。

---

## 5. 大規模 ingest 的分層策略

### 5.1 業界經驗值

| 規模 | 全量深度處理時間 | 全量 LLM 蒸餾時間 | 來源 |
|---|---|---|---|
| 1,000 檔案 | 1-3 分鐘 | 30-90 分鐘 | 經驗值（取自企業導入） |
| 10,000 檔案 | 10-30 分鐘 | 5-15 小時 | 同上 |
| 100,000 檔案 | 1-5 小時 | 50-150 小時 | 同上 |
| 1,000,000 檔案 | 半天-2 天 | 500-1500 小時 | [Komprise Data Management](https://www.komprise.com/glossary_terms/pii-detection) 提到 |

**橋樑現況**：26,022 筆，若全量跑 Gemma 蒸餾 → 約 13-65 小時（假設每筆 30 秒），**這違反 GPU ≤ 5% / CPU ≤ 8% / 記憶體 ≤ 200MB 的預算**（取自 `BRIDGE_ATMOSPHERE_LANGUAGE.md`）。

**結論**：必須分層。

### 5.2 熱/溫/冷/凍四層設計

| Tier | 定義 | 處理策略 | RAG 檢索 | 圖譜顯示 |
|---|---|---|---|---|
| **Hot** | 過去 90 天被修改 + 大於 1KB | 立即全量處理：副檔名 + magic bytes + 命名 pattern + Gemma 蒸餾 + embedding | 全功能 | 預設顯示，節點彩色 |
| **Warm** | 過去 90 天-2 年被修改 | 抽樣 10-20% 蒸餾，其餘只 metadata 標 `awaiting_distill` | 全功能 | 預設顯示，節點低飽和度 |
| **Cold** | 2 年以上未動 + `archive/` `backup/` `old/` 路徑 | 只做副檔名 + 路徑分類，蒸餾按需觸發 | 全文搜尋可達；向量查詢需手動 trigger | 預設隱藏（使用者展開才出現），灰色 |
| **Frozen** | `node_modules/` `__pycache__/` `.git/` `build/` 等工具產物 | **不進入 asset_index**（沿用 `AssetSandbox.defaultExcludedDirs`） | 不適用 | 完全不可見 |

### 5.3 抽樣分析再全量標註

借鑑 [Active Learning with AutoML](https://pmc.ncbi.nlm.nih.gov/articles/PMC12550062) 與 [Snorkel AI 自動標註](https://snorkel.ai/blog/automated-data-labeling) 的方法論：

1. **Phase 1 — 全量 metadata 掃描**（快速，純規則）：所有檔案寫入 `asset_index`，`tier` 標記、`kind` 標記、命名 pattern 標記。
2. **Phase 2 — 抽樣 LLM 蒸餾**（耗時，僅 warm+hot）：
   - 每個資料夾隨機抽 5-10 個檔案
   - 跑 Gemma 蒸餾 + persona 驗證
   - 結果用於「訓練規則」：發現新命名 pattern → 寫入 `_nameRules`
3. **Phase 3 — 全量套用新規則**（再次快速）：用 Phase 2 學到的新規則重新跑 metadata 掃描。
4. **Phase 4 — 漸進式全量蒸餾**（背景）：對 warm 層剩餘檔案，**在 App 閒置時**（CPU/GPU idle）一個個蒸餾；使用者完全無感。

**觸發條件**：
- App 啟動 5 分鐘後
- CPU < 20% 且 GPU < 3% 連續 10 分鐘
- 使用者進入「沈睡模式」（無鍵盤滑鼠活動 > 15 分鐘）
- 充電中（筆電情境，避免吃電）

### 5.4 增量更新策略

借鑑 [rsync incremental recursion](https://linux.die.net/man/1/rsync) 與 [Resilio 大檔案同步](https://www.resilio.com/blog/rsync-large-number-of-files)：

| 變更類型 | 偵測方法 | 處理 |
|---|---|---|
| **檔案新增** | 出現在目錄但 manifest 沒有 | 走 hot 流程（立即處理） |
| **檔案修改** | `modified_at` 變更 或 `file_hash` 不一致 | 重新蒸餾 + 重 embed |
| **檔案刪除** | manifest 有但目錄沒有 | `is_present=false`，保留 metadata 但 RAG 排除；UI 顯示「已離線」 |
| **檔案搬移** | path 變更但 hash 不變 | 更新 `path`，保留蒸餾結果 |
| **資料夾新增** | 目錄新增但 manifest 沒有 | 走 fullScan 流程（Phase 1+2+3+4） |

### 5.5 去重與備份碟副本處理

借鑑 [Micro Focus Content Hash Duplicate](https://www.microfocus.com/documentation/file-reporter/24.1/guides/content/custom-query/scenarios/content-hash-duplicate-file-reports.htm)：

**現況問題**（提問中明示）：「一堆雜訊（Icon\r 污染、**備份碟副本**）」。

**提案**：

1. **Content hash dedup**：
   - 計算所有檔案的 SHA256（已實作於 `_computeFileHash`，第 1010 行）
   - 偵測 hash 相同 + path 不同的群組 → 標記為 `duplicate_group`
   - 自動選擇「最佳代表」：路徑最短、最早修改、不在 `archive/` `backup/` 目錄下的版本
   - 非代表檔案：`tier=frozen`，圖譜上以「半透明分身」顯示

2. **系統檔過濾**（已部分實作）：
   - `Icon\r` 是 macOS finder 自動產生的 metadata 檔 → 應加入排除清單
   - `.DS_Store`、`Thumbs.db` 已排除（`asset_sandbox.dart` 第 47-57 行）— 好
   - **建議新增**：`Icon\r`、`._*`（macOS resource fork）、`~$*`（Office lock file）

3. **備份碟 vs 主碟辨識**：
   - 偵測路徑包含 `/Volumes/*` → 視為外接碟副本，預設 `tier=cold`
   - 偵測路徑包含 `/Backup*/` 或 `/Archive*/` → 同上
   - 提供 UI 開關：「將外接碟視為主要資料來源 vs 副本」

---

## 6. 偵探式導入 SOP

### 6.1 完整流程（5 個階段）

```
[Phase 0: 安裝精靈]
   ↓ 使用者授權資料夾
[Phase 1: 快速掃描 + 分層]
   ↓ 全量 metadata 入庫（純規則）
[Phase 2: 抽樣分析]
   ↓ Warm+Hot 抽 5-10%/資料夾跑 LLM 蒸餾
[Phase 3: 背景漸進式處理]
   ↓ App 閒置時慢慢消化剩餘檔案
[Phase 4: 呈現 + 互動校正]
   ↓ 圖譜首秀 + 使用者微調 → 持續進化
```

### 6.2 Phase 0 — 安裝精靈（Onboarding）

**目前**：`OnboardingStep` 只有 4 步（`onboarding_flow.dart` 第 30-45 行）。

**提案**：擴充為 7 步。

| Step | 名稱 | 互動 | 預計時間 |
|---|---|---|---|
| 0.1 | 歡迎畫面 | 顯示「偵探式導入」動畫概念 | 5 秒 |
| 0.2 | 選擇向量資料庫位置 | 沿用現有 `FilePicker` | 10-30 秒 |
| 0.3 | **選擇要導入的資料夾**（可多選） | 多選 FilePicker，提示「建議選你最混亂的資料夾，越亂偵探越準」 | 30-60 秒 |
| 0.4 | **隱私與資源預算設定** | 三選項 slider：<br>① 輕量（只 metadata，不蒸餾）<br>② 平衡（hot 蒸餾，warm 抽樣）<br>③ 完整（全部蒸餾，吃資源） | 15 秒 |
| 0.5 | 顯示「偵探準備中」動畫 + 處理預覽 | 顯示預估檔案數、預估時間、預估磁碟空間 | 5 秒被跳過 |
| 0.6 | 初始化（DB 建立） | 沿用現有初始化邏輯 | 10-30 秒 |
| 0.7 | 完成 → 進入 Phase 1 掃描 | 顯示進度條，可關閉讓背景跑 | 立即 |

**UX 原則**（取自 [Userpilot — Why Onboarding Wizard Falls Short](https://userpilot.com/blog/onboarding-wizard)、[CXL — 6 User Onboarding Examples](https://cxl.com/blog/6-user-onboarding-flows)）：
- **必填項目最少化**：0.2 和 0.3 是必填；其他都可跳過用預設。
- **「I'll do this later」永遠可選**：避免使用者被 wizard 卡住流失。
- **透明預估**：處理 5 萬檔要多久？預設告訴他，不要讓他乾等。

### 6.3 Phase 1 — 快速掃描 + 分層（純規則，目標 < 30 秒/萬檔）

**輸入**：使用者授權的根資料夾清單。

**流程**：

1. **目錄枚舉**：沿用 `_scanDirectory()`（第 630 行），但**加上 magic bytes 抽樣驗證**（每個副檔名至少抽 3 個檔案）。
2. **副檔名分布統計**：產出 `ExtensionStats { ext: count }`，用於 persona 推斷。
3. **命名 pattern 偵測**：對每個檔名跑 `NamingPatternDetector`，產出 `NamingHint`。
4. **資料夾 profile**：對每個根資料夾跑 `DirectoryProfile`，產出 `depthHistogram`、`namingConvention`、`hotnessHint`。
5. **時間聚類（粗）**：把所有檔案按月份分桶，跑簡單的 burst detection。
6. **分層標記**：依 `modified_at` + 路徑啟發，標 `tier=hot/warm/cold/frozen`。
7. **去重群組**：依 `file_hash` 分組，標 `duplicate_group_id`。
8. **寫入 asset_index**（status=indexed）：所有 metadata 寫入，`embedding` 留 `null`。
9. **回報統計給 UI**：「掃描完成：52,103 檔，熱 1,204，溫 8,902，冷 41,997，凍 0；重複 8,201 個群組」。

**輸出 schema**：`AssetIndexScanSummary { totalFiles, byKind, byTier, byRoom, duplicates, estimatedDistillTime, primaryPersonaGuess }`。

**不做的事**：不做 LLM 蒸餾；不做 embedding；不做精細的內容分析。

### 6.4 Phase 2 — 抽樣分析（目標 < 5 分鐘/萬檔）

**輸入**：Phase 1 產出的 hot + warm 檔案清單。

**流程**：

1. **抽樣策略**：
   - 每個資料夾隨機抽 5-10 個檔案（最少 5，最多 20）
   - 對 hot 層加權 2x
   - 確保每種副檔名至少有 1 個樣本
2. **本地 Gemma 蒸餾**（每檔約 15-30 秒）：
   - 用現有 `_distillStructured()`（第 885 行）產出 `summary` + `keywords` + `resolution` + `systems`
   - 對圖片：呼叫 `vision_embedding_pipeline.dart` 提取視覺描述
   - 對音訊：未來版本支援；目前略過
3. **Persona 驗證**：
   - 把副檔名分布 + 命名樣本 + 資料夾名稱 top 20 + 抽樣摘要 → Gemma
   - 輸出 `UserPersona`
4. **規則強化**：
   - 從抽樣摘要中發現新關鍵字 → 更新 `_contentKeywords`
   - 從抽樣命名中發現新 pattern → 更新 `NamingPatternDetector` 的 regex 庫
5. **再跑 Phase 1 的規則掃描**：套用新規則，全量 metadata 重新整理。

**輸出 schema**：`SamplingAnalysisResult { sampledFiles: [...], personaHypothesis, newRulesLearned }`。

### 6.5 Phase 3 — 背景漸進式處理（Idle-time processing）

**觸發條件**（同時滿足）：
- App 已運行 > 5 分鐘
- CPU < 20%（連續 10 分鐘）
- GPU < 3%（連續 10 分鐘）
- 記憶體可用 > 500MB
- 沒有進行中的對話（chat_screen 在背景）
- 筆電在充電中（可選）

**處理**：
- 從 `asset_index` 撈 `tier IN (warm) AND display_summary IS NULL ORDER BY modified_at DESC LIMIT 10`
- 對每個檔案跑蒸餾（圖片跑 vision pipeline）
- 寫回 metadata
- 廣播進度給 UI（讓圖譜節點漸漸「亮起來」）

**預算控制**：
- 每分鐘最多 5 個檔案（避免背景吃資源）
- 每個檔案 timeout 60 秒
- 失敗重試 3 次後標 `distill_status=failed`，不再嘗試

### 6.6 Phase 4 — 呈現 + 互動校正

**首秀**（Phase 1 完成後立即觸發）：

1. **圖譜概覽**：
   - 中心節點：「你的第二大腦」（asset_index 總數）
   - 第一層：六大房間（依現有 FileRoom）
   - 第二層：主題群集（topic_cluster top 10）
   - 第三層：個別檔案節點（限 100 個高亮）
2. **Persona 卡片**：「我覺得你是⋯⋯」（顯示 UserPersona + 信心度 + 證據）
3. **驚喜發現**：
   - 「你有 8,201 個備份碟副本，要不要我幫你隱藏？」
   - 「你 2024 年有一段 6 個月沒寫任何東西，是怎麼了嗎？」（取自 dormantPeriods）
   - 「你的照片集中在三個 burst：2026-01-15 過年、2026-03-22 出差、2026-07-08 家庭旅行」
4. **微調工具**：
   - 「這個檔案我分錯房間了嗎？」→ 提供房間切換器
   - 「這些（重複檔案）要全部保留還是只留一份？」→ 提供批量處理
   - 「要忽略某個資料夾嗎？」→ 加入排除清單

**持續進化**：
- 使用者每次手動校正（移動房間、改標題、加 tag）→ 學習到新規則，下次自動套用
- 每週一次「回顧模式」：自動摘要本週新增、活躍期變化、persona 漂移

### 6.7 失敗模式與防呆

| 失敗模式 | 防呆設計 |
|---|---|
| LLM 蒸餾 timeout / OOM | 60s timeout + fallback 到檔名截斷；status=failed |
| Magic bytes 與副檔名不一致 | 不拒絕，但 `kind_mismatch=true`，UI 顯示警覺圖示 |
| 同一檔案被重複掃描 | 用 `file_hash` 判定，第二次只更新 `modified_at` |
| 整個資料夾都無法存取（權限不足） | 顯示「X 個資料夾無法讀取，是否繼續？」 |
| 使用者在背景處理時關 App | 進度寫 SQLite，下次開 App 從中斷點繼續 |
| 圖譜節點太多（> 10000）塞爆 UI | 預設只顯示 hot + warm；cold 預設收合；提供「全展開」按鈕但有警告 |
| Persona 推斷錯誤 | UI 永遠顯示「這是我的猜測，你可以修正」+ 提供「重新推斷」按鈕 |

---

## 7. 整合藍圖 — 與現有架構對接

### 7.1 新增的服務模組（建議）

```
lib/services/detective/
├── naming_pattern_detector.dart   # 命名 pattern regex 庫
├── directory_profiler.dart        # 資料夾結構分析
├── time_cluster_detector.dart     # 時間聚類
├── user_persona_detector.dart     # persona 推斷（規則 + LLM）
├── magic_bytes_sniffer.dart       # 內容類型驗證
├── duplicate_group_detector.dart  # hash 去重群組
├── tier_assigner.dart             # 熱溫冷凍分層
├── metadata_extractor.dart        # EXIF/ID3/MP4 抽取
├── onboarding_detective.dart      # 7 步驟安裝精靈
└── background_distill_scheduler.dart  # Idle-time 排程
```

### 7.2 改動的現有檔案

| 檔案 | 改動 |
|---|---|
| `lib/services/vector_db/asset_index_service.dart` | 1. `AssetRecord` 擴展 14 個新欄位；2. `_buildRecord()` 加入命名 pattern / 時間聚類 / tier 標記；3. `fullScan()` 改為呼叫 `DirectoryProfiler` + `TierAssigner` + `DuplicateGroupDetector` |
| `lib/services/vector_db/file_classifier.dart` | 1. `classify()` 加入 `projectId` → `linkedProject` 的自動偵測；2. `_nameRules` 擴展為由 `NamingPatternDetector` 動態生成；3. 加入 `human_categories` 欄位 |
| `lib/services/vector_db/asset_sandbox.dart` | 1. `defaultExcludedDirs` 新增 `Icon\r`、`._*`、`~$*`；2. 偵測路徑是否為外接碟/備份碟 |
| `lib/services/onboarding/onboarding_flow.dart` | 1. `OnboardingStep` 從 4 步擴為 7 步；2. 整合 `OnboardingDetective` |
| `lib/services/brain_container/brain_schema_sql.dart` | 1. `asset_index` 表 schema 擴展；2. 新增 `user_persona` 表 |
| `docs/APP_ARCHITECTURE_MAP.md` | 同步更新架構圖 |

### 7.3 改動的 UI 元素（建議，非本研究範圍）

- **VaultScreen**：新增「偵探報告」tab（Persona 卡片 + 驚喜發現 + 微調工具）。
- **BrainCanvas**：節點 hover 顯示 `display_title` + `display_summary`，而非檔名。
- **OnboardingFlow**：新增步驟 0.3（多選資料夾）+ 0.4（隱私預算 slider）。

---

## 8. 開放問題與後續研究

下列問題本研究**無法回答**，需後續實驗或與 使用者 確認：

1. **本地模型選擇**：現有 Gemma-4-e4b 是否足以做 persona 推斷？是否要改用更大的模型（如 Phi-3-medium）？需實測 confidence。
2. **26,022 筆歷史資料怎麼辦**：要不要做一次性「歷史回填」？還是標 `legacy=true`，只對未來新檔案套用新 schema？
3. **多使用者情境**：未來是否支援多用戶（家庭共享一台 Mac）？目前的 schema 假設單一使用者，需要加 `user_id`。
4. **隱私邊界**：GPS / 聯絡人 / 行事曆等敏感 metadata 要不要偵測？要的話如何脫敏？
5. **跨平台**：未來若出 iOS 版，Onboarding 流程怎麼對接 iOS 的「檔案 App」與「照片 App」權限模型？
6. **匯出 / 遷移**：使用者從 Evernote / Notion / Apple Notes 匯入時的 metadata 對應規則要單獨研究。
7. **效能實測**：26,022 筆實際跑 Phase 1 + Phase 2 的時間 / token / 磁碟 IO 數字，必須等實作後才能填入。
8. **規則學習閉環**：使用者手動校正 metadata 後，模型要多久才能學到？這牽涉到 Active Learning 的 iteration 設計，需另開研究。

---

## 9. 來源 URL 彙整

### 業界檔案分類與管理

- [QNAP Qfiling](https://www.qnap.com/zh-hk/software/qfiling) — NAS 自動歸檔
- [NetApp Data Classification](https://www.netapp.com/zh-hant/data-services/classification) — 企業 AI 資料分類
- [Microsoft Document Intelligence Custom Classifier](https://learn.microsoft.com/zh-tw/azure/ai-services/document-intelligence/how-to-guides/build-a-custom-classifier) — 自訂文件分類器
- [Google Cloud Sensitive Data Protection](https://docs.cloud.google.com/sensitive-data-protection/docs/supported-file-types) — 支援檔案類型與掃描模式
- [Reddit r/datacurator — Folder Structure Visualization](https://www.reddit.com/r/datacurator/comments/1dzqtlp/what_tool_to_visualise_folder_structure) — 資料夾視覺化
- [Microsoft Azure PII Detection](https://learn.microsoft.com/en-us/azure/ai-services/language-service/personally-identifiable-information/overview) — PII 偵測
- [Netwrix — PII Detection Guide](https://netwrix.com/en/resources/blog/pii-detection) — PII 偵測產業實務
- [BigID — What is Data Profiling](https://bigid.com/blog/what-is-data-profiling) — 資料剖析
- [Komprise — PII Detection Glossary](https://www.komprise.com/glossary_terms/pii-detection) — PII 偵測定義
- [ComplyDog — PII Data Protection Guide](https://complydog.com/blog/pii-data-protection-guide-personally-identifiable-information-management) — PII 管理指南

### 檔案命名 pattern 偵測

- [Sortio — Filename Pattern Matching](https://www.getsortio.com/glossary/filename-pattern-matching) — 命名 pattern 總覽
- [Visier — File Naming Best Practices](https://docs.visier.com/developer/Studio/data/sources/file-naming-best-practices.htm) — 命名最佳實踐
- [Harvard Data Management — File Naming Conventions](https://datamanagement.hms.harvard.edu/plan-design/file-naming-conventions) — 學術命名慣例
- [Medium James — Parsing File Names with Regex](https://medium.com/@jamestjw/parsing-file-names-using-regular-expressions-3e85d64deb69) — regex 解析檔名

### 資料夾結構與 Hierarchical Clustering

- [MDPI 2024 — Mapping Hierarchical File Structures to Semantic Data Models](https://www.mdpi.com/2306-5729/9/2/24) — 資料夾語意對應研究
- [aosmith.rbind.io — Analysis Directory Structure](https://aosmith.rbind.io/2018/10/29/an-example-directory-structure) — R 分析專案結構
- [Programming Historian — Clustering Word Embeddings](https://programminghistorian.org/en/lessons/clustering-visualizing-word-embeddings) — 文本 hierarchical clustering
- [IBM — Hierarchical Clustering](https://www.ibm.com/think/topics/hierarchical-clustering) — 演算法總覽
- [UC Business Analytics — Hierarchical Cluster Analysis](https://uc-r.github.io/hc_clustering) — R 實作

### metadata schema 標準

- [schema.org CreativeWork](https://schema.org/CreativeWork) — CreativeWork 標準
- [schema.org DigitalDocument](https://schema.org/DigitalDocument) — DigitalDocument 標準
- [schema.org Blog](https://schema.org/Blog) — Blog 標準
- [schema.org Text](https://schema.org/Text) — Text 資料型別
- [Duke Bitstreams — Schema.org & Google Local Discovery](https://blogs.library.duke.edu/bitstreams/2014/03/27/schema-org-and-google-for-local-discovery-some-key-takeaways) — 學術機構 schema 應用

### Obsidian / Knowledge Management

- [Obsidian Rocks — Properties Introduction](https://obsidian.rocks/an-introduction-to-obsidian-properties) — Obsidian properties
- [Dsebastien — Complete Guide to Obsidian Properties](https://www.dsebastien.net/the-complete-guide-to-obsidian-properties) — 進階 properties 設計
- [Obsidian Forum — File Metadata vs Properties](https://forum.obsidian.md/t/make-file-metadata-and-properties-separate-concepts/75664) — metadata 概念分離討論
- [Obsidian Forum — Nested Properties Editor](https://forum.obsidian.md/t/plugin-template-architecture-and-nested-properties-editor-for-complex-metadata-structures/110843) — 嵌套 metadata 編輯器
- [James Croft — Machine-Readable Knowledge Base with Obsidian](https://www.jamescroft.co.uk/designing-a-machine-readable-knowledge-base-with-obsidian) — PARA + Obsidian 模板
- [Ontologist Substack — DataBooks](https://ontologist.substack.com/p/databooks-markdown-as-semantic-infrastructure) — Markdown + RDF 混合
- [Basic Memory — Knowledge Format](https://docs.basicmemory.com/concepts/knowledge-format) — AI-first 筆記格式
- [Obsidian Forum — Personal Knowledge Graphs](https://forum.obsidian.md/t/personal-knowledge-graphs/69264) — 個人知識圖譜
- [OKF — Open Knowledge Format](https://okf.md/faq) — Google Cloud OKF

### 資料分層策略

- [Elastic Blog — Data Tiering Strategy](https://www.elastic.co/blog/elastic-data-tiering-strategy) — Elasticsearch 熱溫冷分層
- [SAP HANA Cloud — Data Tiering](https://learning.sap.com/courses/provisioning-and-administering-databases-in-sap-hana-cloud/identifying-data-tiering-options-in-sap-hana-cloud_befd6f04-a556-4995-8aae-337e281c834e) — 企業分層
- [CrateDB — Data Tiering](https://cratedb.com/storage/data-tiering) — 時序資料庫分層
- [Backup Education — Tiered Storage Cost-Benefit](https://backup.education/showthread.php?tid=1563) — 備份分層經濟學
- [Logz.io Docs — Data Storage Tiers](https://docs.logz.io/docs/user-guide/admin/data-tiers/data-tiers-intro) — 三層分層

### 使用者畫像 / Profiling

- [BigID — Data Profiling Techniques](https://bigid.com/blog/what-is-data-profiling) — 資料剖析技術
- [Snorkel AI — Automated Data Labeling](https://snorkel.ai/blog/automated-data-labeling) — 自動標註
- [Airbus Acubed — Auto Labeling for Vision](https://acubed.airbus.com/blog/wayfinder/automatic-data-labeling-strategies-for-vision-based-machine-learning-and-ai) — 影像自動標註策略
- [PMC — Active Learning Benchmark](https://pmc.ncbi.nlm.nih.gov/articles/PMC12550062) — Active Learning 基準
- [Superb AI — Data Labeling Approaches](https://superb-ai.com/en/resources/blog/a-primer-on-data-labeling-approaches-to-building-real-world-machine-learning-applications) — 標註方法總覽

### 時間聚類 / Timeline

- [Science.gov — Temporal Clustering Analysis](https://www.science.gov/topicpages/t/temporal+clustering+analysis) — 時間聚類研究
- [Sleuth Kit Autopsy — Timeline Analysis](https://www.sleuthkit.org/autopsy/timeline.php) — 鑑識 timeline 工具
- [Nature Scientific Reports — TASC Framework](https://www.nature.com/articles/s41598-024-63669-6) — 時間分段聚類
- [Nature Scientific Reports — Spatial-Temporal Cluster Evolution](https://www.nature.com/articles/s41598-024-72504-x) — 時空聚類演化
- [Towards Data Science — Time Series Clustering](https://towardsdatascience.com/time-series-clustering-deriving-trends-and-archetypes-from-sequential-data-bb87783312b4) — DTW 聚類

### Magic Bytes / MIME 偵測

- [textslashplain.com — File Types](https://textslashplain.com/2023/04/05/file-types) — 檔案類型與 magic bytes
- [npmjs mimetics](https://www.npmjs.com/package/mimetics) — JS magic bytes 函式庫
- [Ben Nadel — Magic Numbers in ColdFusion](https://www.bennadel.com/blog/2490-detecting-file-type-using-magic-numbers-in-coldfusion.htm) — Magic numbers 實務
- [Medium Fate Walker — File Upload Bypass Magic Bytes](https://medium.com/@opabravo/file-upload-bypass-fuzz-magic-bytes-mime-types-with-ffuf-b218171533d4) — 攻擊面（反面教材）

### EXIF / 影像 metadata

- [PicDefense — EXIF Metadata Analysis](https://picdefense.io/blog/ultimate-guide-to-exif-metadata-analysis) — EXIF 完整指南
- [Photography Life — What is EXIF](https://photographylife.com/what-is-exif-data) — EXIF 入門
- [Pics.io — Image Metadata Viewer](https://pics.io/photo-metadata-viewer) — 線上 EXIF 工具

### Duplicate Detection

- [Micro Focus — Content Hash Duplicate Reports](https://www.microfocus.com/documentation/file-reporter/24.1/guides/content/custom-query/scenarios/content-hash-duplicate-file-reports.htm) — 企業級去重
- [PeaZip — Duplicate Detection](https://peazip.github.io/duplicates-hash-checksum.html) — hash 去重工具
- [Reddit r/DataHoarder — Hashing for Duplicates](https://www.reddit.com/r/DataHoarder/comments/kujxoa/using_hashing_to_identify_duplicate_or_similar) — 雜談實務
- [Python.org — Identifying Duplicate Files](https://discuss.python.org/t/identifying-duplicate-files-where-speed-is-a-concern/44534) — Python 效能討論

### 增量更新 / 檔案系統鑑識

- [Resilio — Rsync Large Files](https://www.resilio.com/blog/rsync-large-number-of-files) — 增量同步
- [Linux man page rsync](https://linux.die.net/man/1/rsync) — rsync 文件
- [AskUbuntu — Rsync Decision Logic](https://askubuntu.com/questions/970573/how-exactly-does-rsync-decide-what-to-sync) — rsync 行為
- [Unix Stack Exchange — Rsync Compare](https://unix.stackexchange.com/questions/57305/rsync-compare-directories) — 目錄比對
- [Admin Magazine — Incremental Backups Linux](https://www.admin-magazine.com/Articles/Using-rsync-for-Backups) — 增量備份

### Forensic File Analysis

- [Vaia — Forensic File Analysis](https://www.vaia.com/en-us/explanations/law/forensic-science/forensic-file-analysis) — 鑑識分析
- [ScienceDirect — File System Analysis](https://www.sciencedirect.com/topics/computer-science/file-system-analysis) — 學術綜述
- [BlueVoyant — Open Source Forensics Tools](https://www.bluevoyant.com/knowledge-center/get-started-with-these-9-open-source-tools) — 開源鑑識工具
- [FRSecure — File System Forensic Timeline](https://frsecure.com/blog/file-system-forensic-analysis) — timeline 鑑識
- [PMC — Photo/Video Manipulation Detection](https://pmc.ncbi.nlm.nih.gov/articles/PMC8321380) — 多媒體鑑識

### Graph RAG 與檢索

- [Instaclustr — Graph RAG Components](https://www.instaclustr.com/education/retrieval-augmented-generation/understanding-graph-rag-components-use-cases-and-best-practices) — Graph RAG 總覽
- [ArXiv — Graphs RAG at Scale](https://arxiv.org/html/2603.22340v1) — LPG + RDF 設計
- [DataRobot — Graph Database RAG Pipeline](https://www.datarobot.com/blog/how-to-integrate-graph-database-rag-pipeline) — 整合實務
- [Neo4j — RAG Tutorial](https://neo4j.com/blog/developer/rag-tutorial) — Neo4j GraphRAG
- [Memgraph — GraphRAG](https://memgraph.com/docs/ai-ecosystem/graph-rag) — Memgraph GraphRAG

### Onboarding UX

- [Userpilot — Onboarding Wizard Limits](https://userpilot.com/blog/onboarding-wizard) — wizard 反思
- [CXL — 6 User Onboarding Examples](https://cxl.com/blog/6-user-onboarding-flows) — 案例分析
- [RudderStack — Data Onboarding](https://www.rudderstack.com/blog/data-onboarding) — 資料 onboarding
- [EULE Institute — User Onboarding](https://euleinstitute.com/en/blog/user-onboarding) — 設計原則
- [DesignerUp — 200 Onboarding Flows Study](https://designerup.co/blog/i-studied-the-ux-ui-of-over-200-onboarding-flows-heres-everything-i-learned) — 大規模分析

### Apple Photos / 跨平台參考

- [Google Support — Apple Photos Metadata Backup](https://support.google.com/photos/thread/1559430/backup-and-sync-apple-photos-library-metadata) — Apple ↔ Google Photos 互通
- [Henry Leach — Export Apple Photos](https://www.henryleach.com/2021/03/exporting-my-photo-library-from-apple-photos) — ExifTool 整合
- [MacRumors — Apple Photos Export Metadata](https://forums.macrumors.com/threads/export-photos-from-apple-photos-and-keep-metadata.2329210/) — 社群討論
- [Apple Discussions — Exporting Photos Metadata](https://discussions.apple.com/thread/254807616) — Apple 官方討論

---

## 10. 結論與下一步

### 10.1 核心論點

1. **現有系統缺的是「為圖譜服務」的 ingest 設計**，不是事後補丁的圖譜渲染。
2. **偵探式導入的本質是「先快掃、再抽樣、再漸進、再學習」**，不是「一次把所有檔案都 LLM 化」。
3. **metadata schema 必須服務三種消費者**：UI 人類、圖譜視覺、Agent RAG。現有 `AssetRecord` 只有 11 個欄位，遠遠不夠。
4. **分層是硬需求**：26,022 筆全量 LLM 化違反資源預算；熱/溫/冷/凍四層加上 Idle-time 處理是唯一可行路徑。
5. **persona 推斷讓 UI 主動服務使用者**，而非讓使用者手動整理。

### 10.2 下一步建議（給主代理決策）

| 選項 | 範圍 | 工作量 | 建議優先 |
|---|---|---|---|
| **A. 先做 MagicBytes 驗證 + 排除 Icon\r / .DS_Store** | 小 | 0.5 天 | **★★★★★** 先做，立即解決現有「Icon\r 污染」問題 |
| **B. 先做命名 pattern 偵測 + `display_title` 取代 `title`** | 中 | 2-3 天 | ★★★★ 立即解決「inspection-record-1783」這類髒標題 |
| **C. 擴充 OnboardingFlow 為 7 步** | 中 | 3-5 天 | ★★★ 影響新使用者第一印象，但等 A+B 完成再做更好 |
| **D. 實作熱/溫/冷分層 + Idle-time scheduler** | 大 | 1-2 週 | ★★★ 解決資源預算問題，但要小心動到現有 ingest pipeline |
| **E. 實作 UserPersonaDetector** | 大 | 1-2 週 | ★★ 等規則成熟後再做 |
| **F. 全套偵探式導入 SOP 一次做完** | 巨大 | 1+ 月 | ★ 風險高，建議拆解 |

### 10.3 不建議一次做完的理由

- 26,022 筆歷史資料的回填是**不可逆動作**，schema 改了就要 migration。
- 建議先做 A + B（小型、可逆、立竿見影），拿到使用者回饋再決定是否做 C-F。
- 若主代理決定要全做，建議先**建立 staging 環境**（用 fixture 或子集 1,000 檔案）驗證再上正式資料。

### 10.4 給未來實作者的提醒

- **永遠保留舊 metadata**：新增欄位用 nullable + default，不要砍欄位。`title` 仍存檔名，`display_title` 才是新標題。
- **規則優先，LLM 殿後**：先用 regex + 啟發式標 80% 檔案，只有低信心分（< 0.5）才送 LLM。
- **預算永遠第一**：GPU ≤ 5% / CPU ≤ 8% / 記憶體 ≤ 200MB 是硬限制，不要為「品質」犧牲穩定性。
- **去重永遠在背景**：不要讓使用者看到「我有 8 千個重複檔案」這種驚嚇數字，改用「我們幫你隱藏了 8 千個重複檔案」。
- **Persona 是猜測，不是定論**：永遠提供「我猜你是 X，Y 也可能」的表達，永遠給「重新推斷」按鈕。

---

**研究完成**。

本文件由研究子代理於 2026-08-19 依藍（主代理）派工生成。所有引用來源 URL 詳見第 9 節。所有設計建議為「研究輸出」，未經主代理與 使用者 裁示前不可進入實作。