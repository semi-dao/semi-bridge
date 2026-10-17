# 研究報告：Obsidian Graph View 與圖譜外掛生態的視覺設計最佳實踐

> **研究範圍**：Obsidian 內建 Graph View 設計語義 + 主流圖譜外掛生態 + 大型圖譜業界標準（語義縮放、label decluttering、hit-testing）+ 知識圖譜 ingest 管線設計
> **目標讀者**：bridge_app 大腦容器畫布研發團隊
> **研究方法**：公開文件、學術論文、外掛 README、討論區精華彙整
> **報告日期**：2026-08-19
> **版本**：v1.0

---

## 目錄

1. [Obsidian 內建 Graph View 的視覺設計語義](#1-obsidian-內建-graph-view-的視覺設計語義)
2. [Obsidian 熱門圖譜外掛生態比較](#2-obsidian-熱門圖譜外掛生態比較)
3. [大型圖譜的業界標準技術](#3-大型圖譜的業界標準技術)
4. [Canvas 渲染下 hit-testing 錯位的根因與正解](#4-canvas-渲染下-hit-testing-錯位的根因與正解)
5. [知識圖譜 ingest 管線設計最佳實踐](#5-知識圖譜-ingest-管線設計最佳實踐)
6. [對 bridge_app 的 10 條具體可採納建議](#6-對-bridge_app-的-10-條具體可採納建議)
7. [資料來源彙整](#7-資料來源彙整)

---

## 1. Obsidian 內建 Graph View 的視覺設計語義

### 1.1 節點大小語義

Obsidian Graph View 內建只有**一種**節點大小計算方式：節點越大代表「**連結數越多**」（連結數 = 入鏈 + 出鏈的數量）。這是長期被使用者抱怨的限制——社區從 2020 年起就有人提案「允許使用者配置節點大小的計算方式」，例如：
- 改成「被引用次數越多越大」（即使自己沒出鏈）
- 改成「中心性（centrality）指標」越大
- 改成「重要性」自評分越大

但截至目前（2026），Obsidian 仍未原生提供可配置的節點大小計算方式。社區共識：原生 Graph View 的節點大小是「連結度（degree centrality）」的視覺代理，**並非權威指標**。

**來源**：[Graph View: Allow to Configure How the Node Size is Calculated - Obsidian Forum](https://forum.obsidian.md/t/graph-view-allow-to-configure-how-the-node-size-is-calculated/4247)

### 1.2 節點顏色語義：Groups（regex 分組）

從 v0.11.0 開始，Obsidian 內建 Graph View 引入 **Groups** 機制，使用者可以用「搜尋查詢」（Search query）或「路徑」來定義節點分組，每個分組可以指定一個顏色。沒被任何 group 匹配的節點使用預設色。

Groups 規則範例：
```
path:"Daily Notes"          # 匹配位於 Daily Notes 資料夾的節點
tag:#moc                    # 匹配帶 moc 標籤的節點
file:"Atlas.md"             # 匹配特定檔案
/                           # 匹配所有節點（預設組）
```

**CSS 主題變數**（可直接覆寫）：
- `.graph-view.color-fill`：一般節點填色
- `.graph-view.color-fill-attachment`：附件節點填色
- `.graph-view.color-fill-unresolved`：未解析（連結到不存在的筆記）的節點填色
- `.graph-view.color-fill-highlight`：hover 時的填色
- `.graph-view.color-line`：連線顏色
- `.graph-view.color-line-highlight`：hover 時的連線顏色
- `.graph-view.color-text`：節點標籤文字顏色
- `.graph-view.color-arrow`：箭頭顏色（啟用 arrows 後）

**來源**：[Is there a way to change the color of the nodes in graph view? - Obsidian Forum](https://forum.obsidian.md/t/is-there-a-way-to-change-the-color-of-the-nodes-in-graph-view/8271)、[Graph nodes different to text colour - Obsidian Forum](https://forum.obsidian.md/t/graph-nodes-different-to-text-colour/14046)、[Obsidian Help: Graph view](https://help.obsidian.md/plugins/graph)

### 1.3 Hover 行為：鄰居高亮 + 非鄰居淡出

內建 Graph View 的 hover 行為相對簡單：
- **hover 一個節點**：該節點高亮，與其直接相連的節點也高亮，**未相連的節點會淡化**（淡化程度可在設定中調整）。
- **不會顯示** 連結節點的標籤文字——這是社區長期呼聲的功能缺失，多數人覺得「我 hover 了一個節點，我應該立刻看到我連到哪幾個節點的名稱」。
- 第三方外掛「Graph Files Highlight Sync」延伸了這個行為：hover 檔案總管的某個檔案或資料夾，會在 Graph View 中高亮對應節點。

**來源**：[Show linked nodes labels on hover - Obsidian Forum](https://forum.obsidian.md/t/show-linked-nodes-labels-on-hover/29413)、[Graph View UI improvements - Obsidian Forum](https://forum.obsidian.md/t/graph-view-ui-improvements/42070)、[Plugin: Graph Files Highlight Sync](https://forum.obsidian.md/t/plugin-graph-files-highlight-sync-hover-a-file-or-folder-in-the-explorer-to-highlight-it-in-the-graph/117430)

### 1.4 標籤顯示時機：縮放閾值（text fade threshold）

內建 Graph View 用「文字淡出閾值」（Text fade threshold）控制標籤何時顯示：
- **縮放越大（zoom in）**：越多節點顯示標籤
- **縮放越小（zoom out）**：標籤逐步淡出（不是消失，是 alpha 衰減）
- 使用者可以調整這個閾值的敏感度（高的話要縮到很近才顯示標籤，低的話稍微拉近就顯示）

社區建議（[Graph View UI improvements](https://forum.obsidian.md/t/graph-view-ui-improvements/42070)）：「理想上應該讓使用者優先指定『預設顯示誰的標籤』，例如 Note title 永遠顯示，Tag 節點的標籤要更近一點才顯示」。這就是 **semantic zoom** 的思維（見 §3.1）。

**來源**：[How I use GRAPH VIEW in Obsidian - YouTube](https://www.youtube.com/watch?v=5x5ua7LecOI)、[Mastering Obsidian's Graph View for Knowledge Management - Medium](https://medium.com/@lennart.dde/mastering-obsidians-graph-view-for-knowledge-management-f1bbe2c8f087)

### 1.5 點擊行為

- **左鍵單擊節點**：在 Graph View 中開啟該筆記（切換到該筆記的編輯視圖）。
- **左鍵雙擊節點**：在 local graph（局部圖譜）中以該節點為中心展開（local graph 顯示 N 跳內的鄰居）。
- **拖曳節點**：可手動重新佈局該節點位置（會被力學模擬暫時固定）。
- **hover**：見 §1.3。
- **滾輪**：縮放。
- **空白處拖曳**：平移視圖。

### 1.6 力學參數（Forces）

內建 Graph View 暴露三組力學參數：
- **Center force**：把所有節點拉向視圖中心的強度。
- **Repel force**：節點之間的互斥力（避免重疊）。值越大，節點之間距離越遠，圖譜越鬆散。
- **Link force**：相連節點之間的吸引力。值越大，相連的節點越靠近，視覺上更有「聚類感」。

**設計經驗**：「Link force 高一點容易看到概念聚類，Repel force 中等讓中心不要太�，Center force 別太大否則邊緣節點會一直被拉回中心」。

**來源**：[How I use GRAPH VIEW in Obsidian - YouTube](https://www.youtube.com/watch?v=5x5ua7LecOI)

### 1.7 內建 Graph View 的核心限制

彙整社區長期反饋：

| 限制 | 影響 |
|---|---|
| 節點大小不可配置（只依連結數） | 不能表達「這是一個重要但少連結的節點」 |
| 沒有原生聚類/社群偵測 | 無法直觀看到「主題聚類」 |
| hover 不顯示鄰居節點標籤 | 探索時必須來回 hover 才知道連結到誰 |
| 沒有 edge label（邊標籤） | 連結的語意（「因為」「屬於」「參考」）不可見 |
| 標籤顯示只有「淡入淡出」 | 不能做層級式語義縮放 |
| 力學參數只有 3 個 | 無法精細控制複雜圖譜的佈局 |

這些限制正是第三方圖譜外掛的生存空間（見 §2）。

---

## 2. Obsidian 熱門圖譜外掛生態比較

### 2.1 Juggl

**基本資訊**：
- 作者：Emile van Krieken
- 狀態：穩定（v1.0.1+），GPL3 雙授權
- 底層：Cytoscape.js
- 存活年限：2020 年至今仍在維護（> 4 年）
- 文件：[juggl.io](https://juggl.io)、[GitHub: HEmile/juggl](https://github.com/hemile/juggl)

**核心特色**：
1. **完全互動式**：可以「選擇性展開」——只展開你想看的部分，避免資訊過載。
2. **Workspace 模式**：進階 local graph，把整個 vault 當成一個可探索的 workspace。
3. **超強樣式化面板**：
   - 節點可設**顏色、形狀、大小、圖示**
   - 樣式可用 CSS、YAML、或 Style Pane 三種方式定義
4. **Link type 支援**：邊可以有 label（連結類型），可讀出「因為」「屬於」等語意。
5. **Breadcrumbs 整合**：與 Breadcrumbs 外掛深度整合，自動用 Breadcrumbs 的關係型別作為邊樣式。
6. **可擴展**：其他外掛可以擴充 Juggl。
7. **支援行動裝置**。

**對 bridge_app 的啟示**：
- 「選擇性展開」vs「全部節點一次顯示」——bridge_app 目前所有節點一次顯示（219 條），Juggl 的漸進式展開是處理大量節點的好典範。
- 樣式可用 **YAML + Style Pane**——bridge_app 的 metadata schema 若用 YAML，可參考 Juggl 的 styling DSL。
- 邊標籤（link type）——bridge_app 應該讓「門」「擺錘」這類關係能顯示在邊上。

### 2.2 Graph Analysis

**基本資訊**：
- 由 Obsidian 社區多位作者提供不同實作
- 核心功能：**圖論指標計算**（中心性、PageRank、community detection、path finding）

**典型功能**：
- 計算節點的 degree、betweenness、closeness、eigenvector centrality
- Louvain / Leiden 社群偵測
- 最短路徑查詢
- 將指標匯出為 JSON / CSV

**對 bridge_app 的啟示**：
- 「哪些節點在概念上是最重要的」可以靠 betweenness centrality（介於中心性）衡量，而不是單純 degree。
- Louvain/Leiden 演算法可用於自動聚類——bridge_app 219 條記憶可能自動聚成 5-15 個主題群，比手動分 sub_category 更客觀。

### 2.3 InfraNodus（AI Graph View）

**基本資訊**：
- 作者：Nodus Labs
- 狀態：活躍（已 23 次更新，29k 下載）
- 商業模式：付費（需要 InfraNodus 帳號）
- 文件：[infranodus.com/obsidian-plugin](https://infranodus.com/obsidian-plugin)、[community.obsidian.md/plugins/infranodus-graph-view](https://community.obsidian.md/plugins/infranodus-graph-view)

**核心特色**：
1. **3D 視覺化** + Force Atlas 佈局
2. **結構洞偵測（gap detection）**：找出知識圖譜中的「空白區」，提示「你可能在這兩個聚類之間缺一個連結」——這是 InfraNodus 最獨特的功能。
3. **AI 增強**：自動生成研究問題、生成選中片段的摘要。
4. **網絡科學指標**：betweenness centrality、modularity、社群偵測。
5. **聚類自動分開**：用 modularity 演算法把不同主題的聚類用推力拉開。
6. **概念抽取**：不只畫 wikilinks，還畫**從文本中抽取的概念**。

**對 bridge_app 的啟示**：
- **「結構洞」概念**：「哪些節點之間應該有連結但實際沒有」——bridge_app 可以借鏡，提示 使用者「你這兩個擺錘之間可能有關聯」。
- **概念抽取**：除了節點本身（219 條記憶），可以從記憶文本中抽取關鍵概念作為節點，讓圖譜更豐富。
- **3D vs 2D**：3D 看起來酷但操作成本高，2D 對大多數使用者更友善。bridge_app 維持 2D 是對的選擇。

### 2.4 Advanced Graph View

**基本資訊**：
- 作者：n23eos
- 狀態：活躍（22 次更新，2k 下載）
- 底層：**WebGL**（高效能）
- 平台：僅桌面
- 文件：[community.obsidian.md/plugins/graph-insight](https://community.obsidian.md/plugins/graph-insight)

**核心特色**：
1. **WebGL 高效能**：可處理大型 vault
2. **指標驅動**：節點大小/顏色/glow 由 metrics 決定
3. **節點類型**：
   - Hubs（高度連結的節點）
   - Orphans（無入鏈的孤立節點）
   - Dead ends（無出鏈的死節點）
   - Broken links（連結到不存在筆記的節點）
4. **Louvain 社群偵測 + 自動命名**（TF-IDF 命名聚類）
5. **聚類泡泡**：每個聚類顯示一個包圍泡泡
6. **N-hop 鄰居過濾**
7. **使用追蹤**：本地記錄筆記開啟次數，可匯出 CSV

**對 bridge_app 的啟示**：
- **WebGL 渲染**：219 條節點用 Skia/Canvas 已經夠用，但若未來擴充到 1000+，WebGL 是必須的路徑。
- **「孤立節點」標記**：bridge_app 的「大腦容器」若有記憶完全沒被引用，應該視覺上提醒（淡灰或半透明）。
- **聚類泡泡**：每個聚類用一圈淡色邊界圈起來，比單靠顏色分組更容易「看出群」。
- **使用追蹤**：使用者 可能想知道「最近 7 天最常被引用的記憶是哪些」——圖譜可以反映這個。

### 2.5 New 3D Graph（obsidian-3d-graph）

**基本資訊**：
- 作者：Apoorv（apoo711）
- 底層：Three.js + Rust + WebAssembly 物理引擎 + 3d-force-graph
- 文件：[GitHub: Apoo711/obsidian-3d-graph](https://github.com/apoo711/obsidian-3d-graph)、[Visualizing Thought: Architecting the 3D Graph](https://aryan-gupta.is-a.dev/blog/2025-06-24-3d-graph-plugin)

**核心特色**：
1. **WASM 物理引擎**：128-bit SIMD 加速
2. **WASD 鍵盤導航**（遊戲化操作）
3. **path/tag/file 三種 color group 規則**
4. **幾何形狀可配置**（球、立方體、icosahedron）

**對 bridge_app 的啟示**：
- **path/tag/file 三種分組語法**——bridge_app 應設計類似的 query DSL。
- **CSS 主題�色 → Three.js RGB 轉換的陷阱**（plugin 作者用 `getComputedStyle` 提取主題顏色，發現 `color-mix(in srgb, ...)` 無法解析）——bridge_app 若要做主題相容的圖譜顏色，要直接從設計系統 token 拿 RGB，不要依賴 CSS 計算。

### 2.6 Graph Link Types

**基本資訊**：
- 功能：在 wikilink 旁加上 `[property::]` 語法，讓邊可以帶類型/屬性
- 文件：[How to Make Personal Knowledge Graph in Obsidian - Medium](https://volodymyrpavlyshyn.medium.com/how-to-make-personal-knowledge-graph-in-obsidian-a6dcd9cd0502)

**範例**：
```markdown
這份記憶 [[另一個節點]] 因為我們曾經一起做過這件事
[[門 A]] [linkType::屬於] [[房間 B]]
```

**對 bridge_app 的啟示**：
- bridge_app 的「門的紀錄」「擺錘警報」天然就是 link type——應該在 ingest 時明確記錄每個連結的**類型**（如「屬於房間」「觸發擺錘」「共振連結」）。

### 2.7 外掛生態彙整表

| 外掛 | 解決什麼問題 | 視覺設計重點 | 我們能借什麼 |
|---|---|---|---|
| Juggl | 選擇性展開、樣式化、邊標籤 | CSS/YAML/Style Pane；節點形狀可變 | Workspace 模式、YAML styling DSL |
| Graph Analysis | 圖論指標計算 | Louvain/Leiden 聚類、centrality 計算 | 介於中心性、聚類自動命名 |
| InfraNodus | 結構洞、概念抽取、AI 摘要 | 3D Force Atlas、modularity 推開聚類 | 結構洞偵測（提示缺連結） |
| Advanced Graph View | WebGL 大圖譜效能 | Hub/Orphan/Dead end 標記、聚類泡泡 | 孤立節點淡灰、聚類泡泡 |
| New 3D Graph | WASM 物理引擎高效能 | path/tag/file color group、WASD | 三種 group 規則語法 |
| Graph Link Types | 邊帶類型 | `[linkType::]` 內聯語法 | link type 在 ingest 時定義 |

---

## 3. 大型圖譜的業界標準技術

### 3.1 Semantic Zoom（語義縮放）的分層策略

**核心思想**：「Overview first, zoom and filter, then details-on-demand」（Shneiderman 的視覺資訊尋求 mantra）。

**學術定義**（[Semantic Zooming for Ontology Graph Visualizations - Fraunhofer](https://publica.fraunhofer.de/bitstreams/db3899b7-9ee3-4f2e-8a32-e1b034242f18/download)）：

語義縮放不是單純「放大縮小」，而是「隨縮放層級切換資訊密度與呈現方式」。論文提出三層資訊架構：
- **第一層（最遠）**：只顯示超級節點（聚類中心 / hub）
- **第二層（中等）**：顯示聚類內的主要節點，標籤只顯示最重要的
- **第三層（最近）**：顯示所有細節，標籤全顯示，邊標籤可見

**Software Cities 的語義縮放範例**（[Semantic Zoom and Mini-Maps for Software Cities - arXiv](https://arxiv.org/html/2510.00003v1)）：
- 縮放時**部分元素被隱藏**，重要標籤/圖示按比例縮放
- 進入特定縮放區間才顯示細節（例如 package 內的 class）
- 結合 fisheye-view（魚眼）放大當前關注區

**Cambridge Intelligence 的策略**（[Graph Visualization At Scale](https://cambridge-intelligence.com/blog/visualize-large-networks)）：
1. **減少密度**：先聚合/合併重複節點
2. **自適應樣式**：根據縮放層級調整節點/邊/標籤樣式
3. **優雅降級**：長計算時顯示 loading bar 或進度

**對 bridge_app 的啟示**：
- bridge_app 219 條節點雖然不算大，但**應該設計三層縮放**：
  - 層級 1（最遠）：6 個房間作為聚類中心，每個房間一個大圓
  - 層級 2（中等）：每個房間內顯示主要節點，標籤只顯示標題
  - 層級 3（最近）：顯示細節，包括連結類型、metadata tooltip

### 3.2 Label Decluttering（標籤去雜亂）演算法

**問題定義**：當節點數變多，標籤互相重疊，圖譜變得無法閱讀。NP-hard 問題。

**經典分類**（[Automatic label placement - Wikipedia](https://en.wikipedia.org/wiki/Automatic_label_placement)）：
1. **Rule-based 規則式**：給每個標籤幾個候選位置（上下左右），依優先級試放
2. **Greedy 貪婪**：O(n) 線性時間，先放最重要的，每個標籤選最少重疊的位置（[Minimizing Overlapping Labels in Interactive Visualizations](https://towardsdatascience.com/minimizing-overlapping-labels-in-interactive-visualizations-b0eabd62ef0)）
3. **Force-based 力學式**：把標籤視為帶排斥力的粒子，跟節點一起跑力學模擬（d3-force 標準做法）
4. **Occupancy Bitmap 佔用位圖**：用 bit array 追蹤像素是否被標籤佔用，可 O(1) 檢查候選位置（[Fast and Flexible Overlap Detection - University of Washington](https://idl.cs.washington.edu/files/2021-FastLabels-VIS.pdf)）
5. **Integer Programming 整數規劃**：最佳化但慢，適合靜態圖

**業界標準做法**：
- **預設不顯示標籤**：縮放閾值達到才顯示
- **顯示優先級**：先顯示 hub（高連結度），再顯示孤立節點
- **碰撞後退**：兩個標籤碰撞時，低優先級的往後退一格或淡出
- **可選：拖開標籤**：使用者可以拖開某個標籤固定在某位置（lead line）

**對 bridge_app 的啟示**：
- **三層標籤顯示**：
  - 縮放 < 0.5：不顯示任何標籤（只靠顏色區分聚類）
  - 0.5 ≤ 縮放 < 1.0：只顯示標題前 8 個字
  - 縮放 ≥ 1.0：顯示完整標題 + 滑入 tooltip 顯示 metadata
- **碰撞退讓**：標籤淡出而非位移，避免節點位置錯亂。
- **最高優先級**應該是「房間名」（6 個）→「hub 節點」→一般節點。

### 3.3 Edge Bundling（邊捆綁）

**為什麼需要**：當節點數大，邊的數量指數增長，視覺上變成「毛線球」。

**經典演算法**（[Similarity-Driven Edge Bundling - MDPI](https://www.mdpi.com/1999-4893/13/11/290)）：
1. **Hierarchical Edge Bundling (HEB)**：需要階層資料，用 B-Spline 沿階層路徑彎曲
2. **Force-Directed Edge Bundling (FDEB)**：把邊視為彈性繩，相似方向的邊互相吸引形成束
3. **Multilayer Edge Bundling**：多層邊（不同類型）分別捆綁

**對 bridge_app 的啟示**：
- bridge_app 219 條節點邊數可能數百~數千條，**應該實作簡化的 force-directed edge bundling**：
  - 把相同「房間」內部的邊捆成一束
  - 把「門的紀錄」相關邊用一種顏色捆綁
  - 把「�錘警報」相關邊用另一種顏色捆綁
- 邊的**顏色 + 粗細**應該反映「關係強度」（embedding cosine similarity）

### 3.4 Community Detection（社群偵測）

**主流演算法**（[Identify Patterns With Community Detection - Memgraph](https://memgraph.com/blog/identify-patterns-and-anomalies-with-community-detection-graph-algorithm)）：
1. **Louvain Modularity**：O(n log n)，大網路首選
2. **Leiden Modularity**：Louvain 改良版，社群更穩定、定義更清晰
3. **Label Propagation (LPA)**：半監督，快但品質較差
4. **Spectral Clustering**：對稀疏大網路效果好

**對 bridge_app 的啟示**：
- 用 **Leiden** 演算法自動偵測 219 條記憶的聚類（5-15 個）
- 每個聚類**自動命名**：取該聚類內 TF-IDF 最高的詞（Advanced Graph View 的做法）
- 把自動聚類結果**疊加在**現有的人工 sub_category 上，兩者對照

### 3.5 Centrality（中心性）指標

| 指標 | 意義 | 用法 |
|---|---|---|
| Degree | 直接連結數 | 「連結最多的人」 |
| Betweenness | 經過此節點的最短路徑數 | 「橋樑型節點」（介於兩個聚類間） |
| Closeness | 到所有節點的平均距離倒數 | 「中心型節點」 |
| Eigenvector / PageRank | 被重要節點連結的程度 | 「權威節點」 |

**對 bridge_app 的啟示**：
- 用 **betweenness centrality** 找出「橋樑型記憶」——這些是 使用者 最該看的（它們連接兩個看似無關的概念群，正是 Transurfing「橋樑」的本質）。
- 把 betweenness 當作節點大小（或額外的視覺強調），讓使用者一眼看到「哪些記憶是橋樑」。

### 3.6 Adaptive Styling（自適應樣式）

**Cambridge Intelligence** 的建議（[Graph Visualization At Scale](https://cambridge-intelligence.com/blog/visualize-large-networks)）：
- **Link gradients**：用漸層色讓聚類從遠處就能看到
- **Zoom-adaptive style**：節點/邊/標籤樣式隨縮放改變
- **Time-based view**：若有時間維度，用 heatmap 聚合

**對 bridge_app 的啟示**：
- 邊的顏色應該用**漸層**（從源節點色 → 目標節點色），這樣聚類邊界更明顯
- 縮放到最遠時，節點用**輪廓而非填色**，省 GPU/繪製成本
- 時間維度（219 條記憶有時間戳）可以做成「熱度圖」�加層

---

## 4. Canvas 渲染下 hit-testing 錯位的根因與正解

### 4.1 為什麼點 A 卻選到 B？

bridge_app 的問題：「點 A 節點卻選到遙遠的 B 節點」。這是 canvas 渲染下非常經典的 bug，根因通常是**以下幾種之一或多種組合**：

#### 根因 A：渲染座標系與 hit-test 座標系不一致

Canvas 有兩個座標系：
- **世界座標系（world coordinates）**：節點的「邏輯」位置（例如某節點在世界座標 (100, 50)）
- **螢幕座標系（screen coordinates）**：使用者點擊的位置（例如螢幕 (450, 320)）

兩者之間需要**變換矩陣（transform matrix）**：
```
screen = world * zoom + pan_offset
world = (screen - pan_offset) / zoom
```

**如果 hit-test 用了錯誤的變換（或忘了套用變換），點擊位置就跟世界座標對不上**。

**參考實作**：[vasturiano/force-graph](https://github.com/vasturiano/force-graph) 明確提供：
- `screen2GraphCoords(x, y)`：把螢幕座標轉世界座標
- `graph2ScreenCoords(x, y)`：把世界座標轉�幕座標
- `onNodeClick(node, event)`：保證 event 是用螢幕座標，函式內部用 `screen2GraphCoords` 轉換

**對 bridge_app 的啟示**：務必確認 hit-test 用的 transform 與 paint 用的 transform 是**同一個矩陣**。

#### 根因 B：物理模擬更新位置但 hit-test 用了舊位置

如果力學模擬在另一個執行緒/動畫更新節點位置，而 hit-test 用的陣列還是上一幀的，點擊就會錯位。

**正解**：
- 確保 hit-test 用的節點陣列與 paint 用的陣列是**同一個 reference**
- 或者用 `requestAnimationFrame` 同步：先更新位置，再 paint，再讓 hit-test 拿到新位置
- 在 Flutter 中：把所有節點放在 `ChangeNotifier` 或 `ValueNotifier` 中，paint 與 hit-test 都讀同一個 source

#### 根因 C：z-order / 點擊事件穿透

如果節點有重疊（聚類中心內部有子節點），Canvas 預設「後畫的覆蓋先畫的」，但 hit-test 可能用了**陣列順序而非 z-order**。

**正解**：
- 渲染時按 z-order 排序（最後畫的在最上層）
- hit-test 時也要按**反向** z-order 檢查（先檢查最上層）
- Flutter CustomPainter 沒有原生 z-order，但可以在 painter 內自己管理

#### 根因 D：CustomPainter hitTest 未實作

Flutter 的 `CustomPainter` 有個 `hitTest(Offset position)` 方法可以覆寫，**預設回傳 false**（所有點擊都不命中 CustomPaint）。

**如果沒有覆寫 hitTest**：所有點擊會落到 CustomPaint 的 child 或被吃掉，造成「點 A 沒反應」或「點 A 永遠落到背景」。

**正解**（[apparencekit.dev](https://apparencekit.dev/flutter-tips/canvas-gesturedetector-radius-hit)）：
```dart
class WorldPainter extends CustomPainter {
  // ...
  @override
  bool hitTest(Offset position) {
    // position 是 local 座標（相對於 CustomPaint widget）
    // 如果 hit 到任何節點，回傳 true
    return nodes.any((node) => 
      (position - node.screenPosition).distance < node.radius
    );
  }
}
```

但要注意：**CustomPainter 的 hitTest 只在 isComplex 為 true 或 child 為 null 時有效**。如果有 child，子節點會先處理事件。

**更好的解法**：用 `GestureDetector` 包住 `CustomPaint`，**自己處理 hitTest**，不要依賴 painter 的 hitTest。

```dart
GestureDetector(
  onTapDown: (details) {
    final localPos = details.localPosition;
    final worldPos = screenToWorld(localPos);
    final hitNode = findNodeAt(worldPos);
    if (hitNode != null) controller.selectNode(hitNode);
  },
  child: CustomPaint(painter: GraphPainter(...)),
)
```

#### 根因 E：節點半徑太小，難以點中

如果節點半徑只有 4-6 px，在縮放 0.5 時實際顯示 2-3 px，幾乎點不中。

**正解**：
- **視覺半徑**（繪製用）：例如 4-6 px
- **點擊半徑**（hit-test 用）：例如 12-16 px（比視覺半徑大 2-3 倍）
- 這就是 Konva.js 的 `hitStrokeWidth` 概念（[Konva Custom Hit Region](https://konvajs.org/docs/events/Custom_Hit_Region.html)）

#### 根因 F：動畫/過渡期間 hit-test

如果節點位置在動畫中（例如「飛入」或「聚焦」），中途 hit-test 可能選到「正在飛的節點」。

**正解**：
- 動畫期間 `hitTestEnabled = false`
- 動畫結束後才啟用

### 4.2 業界標準做法：Color-Coded Hit Canvas

**最精確的 hit-test 做法**（[Hit Region Detection For HTML5 Canvas - Lavrton](https://lavrton.com/hit-region-detection-for-html5-canvas-and-how-to-listen-to-click-events-on-canvas-shapes-815034d7e9f8)）：

1. 建立**兩個 canvas**：可見的 + 隱藏的「hit canvas」
2. 在 hit canvas 上，每個節點用**唯一顏色**�製（例如 `(R=nodeId & 0xFF, G=(nodeId>>8) & 0xFF, B=(nodeId>>16) & 0xFF)`）
3. 點擊時讀 hit canvas 在該位置的 `getImageData(x, y)`，解碼出 nodeId
4. **好處**：完全不會錯位，因為 hit canvas 與可見 canvas 像素對應
5. **壞處**：每次節點變動要重繪 hit canvas，記憶體成本高（每像素 4 bytes）

**對 bridge_app 的啟示**：219 條節點規模不大，**可以用 quadtree + 距離檢測**就夠了。但若擴充到 1000+，可以考慮用 Color-Coded Hit Canvas（Flutter 中可用 `Picture` 離屏渲染）。

### 4.3 QuadTree / Spatial Index 加速

**效能最佳實踐**（[plugfox.dev: High-Performance Canvas Rendering](https://plugfox.dev/high-performance-canvas-rendering)）：

當節點數 > 100，**每次點擊都線性搜尋所有節點**會卡。應該用：
- **QuadTree**：把世界座標空間四分樹，每次點擊只檢查可能命中的子樹
- **R-tree**：2D 矩形搜尋
- 或直接用 **d3-quadtree**（JS）或 **quadtree_flutter**（Dart）

**對 bridge_app 的啟示**：
- 219 條節點規模，quadtree 是 overkill，但**應該從現在開始建立**（成本低，預先投資）
- Flutter 沒有內建 quadtree，可用 `dart:collection` + 手寫實作，或用 `quadtree` pub package

---

## 5. 知識圖譜 ingest 管線設計最佳實踐

### 5.1 Schema-Driven Ingest

**核心原則**（[Best Practices for Enterprise Knowledge Graph Design - Enterprise Knowledge](https://enterprise-knowledge.com/best-practices-for-enterprise-knowledge-graph-design)、[Knowledge Graph Best Practices Guide - Data AI Hub](https://www.dataaihub.co/learn/knowledge-graph-best-practices)）：

Ingest 不是「把資料塞進資料庫」，而是：
1. **Source → Ontology 映射**：定義資料屬於哪些實體類型
2. **Validation at ingest**：用 SHACL 或自訂規則驗證（失敗 quarantine）
3. **Entity resolution**：識別「同一個東西的不同表述」（如「使用者」和「老闆」是同一個人）
4. **Provenance（來源）**：每個事實附上「從哪來、信心度、時間戳」
5. **Additive schema evolution**：schema 隨業務演進，但保持向後相容

### 5.2 雙消費者 Metadata Schema

bridge_app 的記憶同時服務**兩個消費者**：
- **圖譜展現**（給人看）
- **Agent 檢索**（給 LLM/搜尋用）

兩個消費者需要**不同的 metadata 視圖**：

```
Raw metadata (in DB):
  id: uuid
  title: "與 Mike 對話：AI 對教育的影響"      ← 給人看（圖譜標籤）
  summary: "Mike 認為..."                     ← 給 LLM 看（摘要）
  sub_category: "共振"                        ← 給圖譜分顏色用
  room: "heartMind"                          ← 房間歸屬（圖譜聚類）
  created_at: 2026-08-01T10:00:00Z
  embedding: vector(384)                     ← 給搜尋用
  links: [{target_id, type, strength}]      ← 給圖譜畫邊用
  tags: ["AI", "教育", "Mike"]                ← 給 LLM 看
  importance: 0.85                           ← 給圖譜大小用
  betweenness: 0.42                          ← 給圖譜強調用
  is_hub: true                               ← 給圖譜樣式用
  provenance: {source: "對話", confidence: 0.9}
```

**Graph View 投影**（給人看）：
- 節點顯示 `title` 前 8 字
- 節點顏色 = `room` 對應色
- 節點大小 ∝ `importance + betweenness` 加權
- 邊顏色 = `links[].type` 對應色
- 邊粗細 = `links[].strength`

**Agent Retrieval 投影**（給 LLM 看）：
- 提供 `title + summary + tags + created_at + importance`
- 排序：cosine similarity → importance → recency
- 篩選：`room`, `sub_category`, 時間範圍

### 5.3 自動提取標題/分類/標籤

bridge_app 從「對話紀錄」「記憶片段」自動建構 metadata 的流程應該是：

**Step 1：實體抽取（Named Entity Recognition）**
- 從文本中抽人名（使用者, Mike）、概念（AI, 教育）、時間點
- 可以用 LLM 做（給一段對話 → 問「這段對話涉及哪些概念？」）

**Step 2：標題生成（Title Generation）**
- 規則：「對話：{對方} 談 {主題}」或「記憶：{一句話摘要}」
- LLM：「用 8 個字總結這段記憶的標題」

**Step 3：分類（Classification）**
- 規則：根據來源類型（對話/閱讀/靈感）給預設 `sub_category`
- LLM：根據內容判斷屬於六房間哪個（heartMind / bridges / pendulums 等）

**Step 4：標籤（Tagging）**
- 從實體抽取結果選 3-7 個標籤
- 加入既有 ontology 標籤集（一致性）

**Step 5：連結發現（Link Discovery）**
- 用 embedding cosine similarity 找最相似的 K 條記憶
- 用 LLM：「這兩條記憶之間的關係類型是什麼？」（屬於/反駁/延伸/觸發）

**Step 6：重要性評分（Importance Scoring）**
- 規則：
  - 被引用次數（in-degree）
  - Betweenness centrality（橋樑性）
  - recency（最近提到）
  - LLM：「這條記憶對 使用者 的重要程度？」

### 5.4 從 Source 到 Graph 的 Pipeline（參考架構）

```
原始來源（對話/文章/語音轉文字/圖片）
   ↓
[Step 1] Pre-process（清洗、chunking、OCR）
   ↓
[Step 2] LLM Extraction（抽出 entities、relationships、summary）
   ↓
[Step 3] Schema Validation（檢查必填欄位、型別、值域）
   ↓
[Step 4] Entity Resolution（合併重複、跨來源對齊）
   ↓
[Step 5] Embedding Generation（產生 vector）
   ↓
[Step 6] Importance/Link Scoring（計算 importance、發現�含連結）
   ↓
[Step 7] Persist to SQLite（寫入 memory + asset 兩個表）
   ↓
[Step 8] Graph Cache Update（更新 Graph View 用的預計算快取）
   ↓
[Step 9] Notify Subscribers（�發 UI 重繪）
```

**對 bridge_app 的啟示**：
- bridge_app 已有 219 條記憶 + 26022 檔案，但 metadata 可能不齊全。應該做一次 **backfill**：用 LLM 對現有資料補 title/summary/tags/importance
- Ingest 流程應該**冪等**（同一份資料重複 ingest 結果相同）
- Schema 應該**版本化**（schema_version 欄位），方便日後演進

### 5.5 Schema Evolution（演進）

**核心原則**（[How to Build a Knowledge Graph - PuppyGraph](https://www.puppygraph.com/blog/how-to-build-knowledge-graph)）：

- **Additive changes**：加新欄位、新節點類型、新邊類型——直接做
- **Breaking changes**：改欄位語義、改節點類型——做 migration
- **Versioned schema**：每個節點帶 `schema_version`，舊節點 lazy upgrade

**對 bridge_app 的啟示**：
- 從一開始就在 metadata 加上 `schema_version: 1`
- 未來加欄位時（如 `betweenness`）做 migration script

---

## 6. 對 bridge_app 的 10 條具體可採納建議

下列建議按「**優先級 + 影響**」排序。每條都標明對應的現況問題、實作難度、建議引用來源。

### 建議 1：節點標籤改顯示 `title`，sub_category 改用顏色表達，圖例去掉 emoji

**對應現況問題**：所有節點都顯示 sub_category（「共振」「順暢流動」一堆重複）

**具體實作**：
- 節點顯示：`title` 前 8 個字（縮放 ≥ 0.5 時），hover tooltip 顯示完整 metadata
- 節點�色：依 `sub_category` 從固定 6-8 種顏色 palette 選
- 圖例：純色塊 + 文字，**去掉 emoji**
- 縮放 < 0.5 時**完全不顯示文字**，只靠顏色區分聚類

**參考來源**：Obsidian 內建 Graph View 的 text fade threshold（§1.4）；Cambridge Intelligence 的 adaptive styling（§3.6）

**難度**：低（純樣式改動）

### 建議 2：實作「節點視覺半徑 vs 點擊半徑」分離

**對應現況問題**：有些節點怎麼點都沒反應（半徑太小）

**具體實作**：
- 視覺半徑（draw 用）：`baseRadius * sqrt(importance)`
- 點擊半徑（hit-test 用）：**max(visualRadius * 2.5, 12 px)**
- 點擊半�是**看不見的擴大圈**，讓使用者點到邊緣也算命中

**參考來源**：Konva.js 的 `hitStrokeWidth`（§4.1 根因 E）

**難度**：低（hit-test 函式加一行 max 邏輯）

### 建議 3：建立統一的世界座標 ↔ 螢幕座標變換矩陣

**對應現況問題**：點 A 節點卻選到遙遠的 B 節點

**具體實作**：
- 建立單一 `Transform` 物件（包含 zoom, panX, panY, rotation）
- paint 與 hit-test **共用同一個 transform**
- 提供 `screenToWorld(Offset)` 與 `worldToScreen(Offset)` 兩個函式
- 在每個變更 transform 的地方（縮放、平移、動畫結束）**主動 invalidate**

**參考來源**：vasturiano/force-graph 的 screen2GraphCoords（§4.1 根因 A）

**難度**：中（重構現有渲染架構）

### 建議 4：用 GestureDetector + 自訂 hitTest，而非依賴 CustomPainter.hitTest

**對應現況問題**：hit-test 不可靠

**具體實作**：
- 在 `CustomPaint` 外層包 `GestureDetector`
- `onTapDown` 中：把 `details.localPosition` 經 transform 轉世界座標
- 用 quadtree 或線性搜尋找出最近節點
- 若 `distance(worldPos, node.worldPos) < hitRadius` 則選中

**參考來源**：apparencekit.dev 的 hitTest radius（§4.1 根因 D）；plugfox.dev 的高效能 canvas（§4.3）

**難度**：中

### 建議 5：實作 Louvain/Leiden 自動聚類，自動命名

**對應現況問題**：所有節點顯示 sub_category 造成標籤重複

**具體實作**：
- 在 ingest 完成後跑 Leiden 演算法（graphx 或 iGraph 都有）
- 每個聚類用 TF-IDF 從內部節點 `title` 中抽 3 個關鍵詞命名
- 每個聚類顯示一個**淡色半透明泡泡邊界**
- 聚類結果可作為 sub_category 的補充視覺層

**參考來源**：Advanced Graph View 的 Louvain + TF-IDF 命名（§2.4）

**難度**：高（需要圖論演算法函式庫）

### 建議 6：實作三層 Semantic Zoom

**對應現況問題**：219 條節點全展開時太擠

**具體實作**：
- **層級 1（zoom ≤ 0.4）**：只顯示 6 個房間（room）的大�，內部隱藏
- **層級 2（0.4 < zoom ≤ 1.0）**：顯示房間內的節點，標題前 8 字
- **層級 3（zoom > 1.0）**：完整顯示 + 連結類型 + tooltip

**參考來源**：Fraunhofer 的 Ontology Semantic Zoom（§3.1）；Cambridge Intelligence 的 scale strategies（§3.1）

**難度**：中

### 建議 7：邊用顏色表達「關係類型」，用粗細表達「關係強度」

**對應現況問題**：線太少、沒有視覺連結感

**具體實作**：
- 邊顏色（4 種）：門的紀錄（藍）/ 擺錘警報（紅）/ 共振連結（綠）/ 一般引用（灰）
- 邊粗細 ∝ `links[].strength`（embedding cosine similarity）
- 必要時實作 force-directed edge bundling 把同類邊捆成一束

**參考來源**：Juggl 的 link type（§2.1）；Force-Directed Edge Bundling（§3.3）

**難度**：中

### 建議 8：在 ingest 時定義完整 metadata schema

**對應現況問題**：資料導入沒有「為圖譜展現服務」的設計

**具體實作**：為每條記憶建立以下 metadata（見 §5.2 範例）：
- `title`（自動生成，給圖譜標籤用）
- `summary`（LLM 生成，給 agent 檢索用）
- `sub_category`（給圖譜顏色用）
- `room`（6 房間歸屬）
- `importance`（0-1，給節點大小用）
- `betweenness`（預計算，給樣式強調用）
- `links[]`（含 type + strength）
- `tags[]`、`created_at`、`schema_version`

**參考來源**：Knowledge Graph Best Practices（§5.1）；PuppyGraph Schema Design（§5.4）

**難度**：高（需要 backfill 219 條現有資料）

### 建議 9：實作 Hover 鄰居高亮 + 非鄰居淡出

**對應現況問題**：缺乏探索引導

**具體實作**：
- hover 節點 A：A 與所有 1-hop 鄰居的節點保持原色
- 其他節點 alpha 降到 0.2
- 連到 A 的邊保持高亮，其他邊 alpha 降到 0.1
- tooltip 顯示被 hover 節點的 metadata（title、room、importance、相關連結）

**參考來源**：Obsidian 內建 Graph View 的 hover 行為（§1.3）；Graph Files Highlight Sync（§1.3）

**難度**：低

### 建議 10：建立「孤立節點」、「hub 節點」、「橋樑節點」的視覺標記

**對應現況問題**：節點重要性無從得知

**具體實作**：
- **Orphan（無入鏈無出鏈）**：淡灰色半透明 + 外框虛線
- **Hub（in-degree > 閾值）**：外框金色實線
- **Bridge（betweenness centrality > 閾值）**：節點周圍加微光（halo）
- 這三類標記可疊加（一個節點可能既是 hub 又是 bridge）

**參考來源**：Advanced Graph View 的 Hub/Orphan/Dead end 標記（§2.4）；Neo4j centrality 演算法（§3.5）

**難度**：中（需要預計算 centrality）

---

## 7. 資料來源彙整

### 7.1 Obsidian 內建 Graph View
- [Graph View: Allow to Configure How the Node Size is Calculated - Obsidian Forum](https://forum.obsidian.md/t/graph-view-allow-to-configure-how-the-node-size-is-calculated/4247)
- [Is there a way to change the color of the nodes in graph view? - Obsidian Forum](https://forum.obsidian.md/t/is-there-a-way-to-change-the-color-of-the-nodes-in-graph-view/8271)
- [Graph nodes different to text colour - Obsidian Forum](https://forum.obsidian.md/t/graph-nodes-different-to-text-colour/14046)
- [Show linked nodes labels on hover - Obsidian Forum](https://forum.obsidian.md/t/show-linked-nodes-labels-on-hover/29413)
- [Graph View shows connected titles on hover - Obsidian Forum](https://forum.obsidian.md/t/graph-view-shows-connected-titles-on-hover/31050)
- [Graph View UI improvements - Obsidian Forum](https://forum.obsidian.md/t/graph-view-ui-improvements/42070)
- [Plugin: Graph Files Highlight Sync](https://forum.obsidian.md/t/plugin-graph-files-highlight-sync-hover-a-file-or-folder-in-the-explorer-to-highlight-it-in-the-graph/117430)
- [How I use GRAPH VIEW in Obsidian - YouTube](https://www.youtube.com/watch?v=5x5ua7LecOI)
- [How I Use The Obsidian Graph View - YouTube](https://www.youtube.com/watch?v=Z8WIALfgaA4)
- [Mastering Obsidian's Graph View for Knowledge Management - Medium](https://medium.com/@lennart.dde/mastering-obsidians-graph-view-for-knowledge-management-f1bbe2c8f087)

### 7.2 Obsidian 圖譜外掛
- [Juggl – Obsidian Stats](https://www.obsidianstats.com/plugins/juggl)
- [Juggl on Obsidian Forum](https://forum.obsidian.md/t/juggl-out-now-1-0-1-a-completely-interactive-stylable-and-expandable-graph-view-plugin/9625)
- [Juggl.io](https://juggl.io)
- [GitHub: HEmile/juggl](https://github.com/hemile/juggl)
- [InfraNodus Obsidian Graph View Plugin](https://infranodus.com/obsidian-plugin)
- [InfraNodus on community.obsidian.md](https://community.obsidian.md/plugins/infranodus-graph-view)
- [Obsidian 3D Graph View Plugin - Nodus Labs](https://noduslabs.com/featured/obsidian-3d-graph-view-plugin-with-network-science-insights)
- [Advanced Graph View - community.obsidian.md](https://community.obsidian.md/plugins/graph-insight)
- [New 3D Graph – Obsidian Stats](https://www.obsidianstats.com/plugins/new-3d-graph)
- [GitHub: Apoo711/obsidian-3d-graph](https://github.com/apoo711/obsidian-3d-graph)
- [Visualizing Thought: Architecting the 3D Graph](https://aryan-gupta.is-a.dev/blog/2025-06-24-3d-graph-plugin)
- [More informative clustering in graph view - Obsidian Forum](https://forum.obsidian.md/t/more-informative-clustering-of-in-the-graph-view/5454)

### 7.3 大型圖譜業界標準
- [Semantic Zooming for Ontology Graph Visualizations - Fraunhofer-Publica](https://publica.fraunhofer.de/bitstreams/db3899b7-9ee3-4f2e-8a32-e1b034242f18/download)
- [Semantic Zoom and Mini-Maps for Software Cities - arXiv](https://arxiv.org/html/2510.00003v1)
- [Large-Scale Graph Visualization - Tom Sawyer Software](https://blog.tomsawyer.com/large-scale-graph-visualization)
- [Graph Visualization At Scale - Cambridge Intelligence](https://cambridge-intelligence.com/blog/visualize-large-networks)
- [Minimizing Overlapping Labels in Interactive Visualizations - Towards Data Science](https://towardsdatascience.com/minimizing-overlapping-labels-in-interactive-visualizations-b0eabd62ef0)
- [Fast and Flexible Overlap Detection for Chart Labeling - University of Washington](https://idl.cs.washington.edu/files/2021-FastLabels-VIS.pdf)
- [Automatic label placement - Wikipedia](https://en.wikipedia.org/wiki/Automatic_label_placement)
- [Legible Label Layout for Data Visualization - arXiv](https://arxiv.org/html/2405.10953v1)
- [Similarity-Driven Edge Bundling - MDPI](https://www.mdpi.com/1999-4893/13/11/290)
- [Force-Directed Edge Bundling - Tom Sawyer Software](https://blog.tomsawyer.com/force-directed-edge-bundling-for-graph-visualization)
- [Multilayer Graph Edge Bundling - LIRMM](https://www.lirmm.fr/~poncelet/publications/papers/multiGraphEB.pdf)
- [An Information-Theoretic Framework for Evaluating Edge Bundling](https://pmc.ncbi.nlm.nih.gov/articles/PMC7513140)
- [Force-Directed Layout Community Detection - Springer](https://link.springer.com/chapter/10.1007/978-3-642-40285-2_36)
- [Community detection in directed weighted networks using Voronoi partitioning - Nature](https://www.nature.com/articles/s41598-024-58624-4)
- [Identify Patterns With Community Detection - Memgraph](https://memgraph.com/blog/identify-patterns-and-anomalies-with-community-detection-graph-algorithm)
- [Community Detection in Learning Networks Using R](https://lamethods.org/book1/chapters/ch16-community/ch16-comm.html)
- [Force-directed graph drawing - Wikipedia](https://en.wikipedia.org/wiki/Force-directed_graph_drawing)
- [What are graph algorithms? A comprehensive guide - Neo4j](https://neo4j.com/blog/graph-data-science/graph-algorithms)

### 7.4 Canvas Hit-Testing
- [force-graph - vasturiano](https://vasturiano.github.io/force-graph)
- [GitHub: vasturiano/force-graph](https://github.com/vasturiano/force-graph)
- [Hit Region Detection For HTML5 Canvas - Lavrton](https://lavrton.com/hit-region-detection-for-html5-canvas-and-how-to-listen-to-click-events-on-canvas-shapes-815034d7e9f8)
- [Canvas Custom Hit Detection Function - Konva](https://konvajs.org/docs/events/Custom_Hit_Region.html)
- [Advanced hit-test HTML Canvas tutorial - YouTube (Radu Mariescu-Istodor)](https://www.youtube.com/watch?v=KD_f-XbdIlk)
- [HTML-in-Canvas WICG](https://wicg.github.io/html-in-canvas)
- [SVG vs Canvas Charts: What Actually Matters - ApexCharts](https://apexcharts.com/blog/svg-vs-canvas-charts)
- [canvas2d-data-visualization Agent Skills](https://mcpservers.org/agent-skills/openai/canvas2d-data-visualization)
- [canvas with GestureDetector - apparencekit.dev](https://apparencekit.dev/flutter-tips/canvas-gesturedetector-radius-hit)
- [CustomPaint class - Dart API](https://api.flutter.dev/flutter/widgets/CustomPaint-class.html)
- [High-Performance Canvas Rendering - plugfox.dev](https://plugfox.dev/high-performance-canvas-rendering)
- [Flutter CustomPainter Tutorial - VeryGood Ventures](https://verygood.ventures/blog/mastering-custompainter-in-flutter-from-svgs-to-racetracks)

### 7.5 知識圖譜 Ingest 管線
- [Knowledge Graph Best Practices Guide - Data AI Hub](https://www.dataaihub.co/learn/knowledge-graph-best-practices)
- [Best Practices for Enterprise Knowledge Graph Design - Enterprise Knowledge](https://enterprise-knowledge.com/best-practices-for-enterprise-knowledge-graph-design)
- [Adoption of knowledge-graph best development practices - PMC NCBI](https://pmc.ncbi.nlm.nih.gov/articles/PMC10038788)
- [How to Build a Knowledge Graph - PuppyGraph](https://www.puppygraph.com/blog/how-to-build-knowledge-graph)
- [What Is a Metadata Knowledge Graph? - DataHub](https://datahub.com/blog/metadata-knowledge-graph)
- [Personal Knowledge Graphs - Obsidian Forum](https://forum.obsidian.md/t/personal-knowledge-graphs/69264)
- [Designing a Machine-Readable Knowledge Base with Obsidian](https://www.jamescroft.co.uk/designing-a-machine-readable-knowledge-base-with-obsidian)
- [How to Make Personal Knowledge Graph in Obsidian - Medium](https://volodymyrpavlyshyn.medium.com/how-to-make-personal-knowledge-graph-in-obsidian-a6dcd9cd0502)
- [Knowledge Forge - Obsidian Plugin](https://community.obsidian.md/plugins/kg-forge)

---

## 附錄：未查到的資料

下列主題在本次研究中**未查到充分資料**，標註為「未查到」以避免編造：

1. **Obsidian Graph View 內部原始碼的渲染節點大小演算法具體實作**：未查到 Obsidian GitHub repo 中 Graph View 計算節點大小的具體源碼（社群描述為「連結數」，但具體是 in-degree、out-degree、還是 sum，無官方文件確認）。
2. **Juggl 的 Cytoscape.js 樣式 DSL 完整規範**：juggl.io 文件站目前（2026）部分連結已失效，未能取到完整的 styling DSL 細節。
3. **Flutter `CustomPainter` 在 Impeller 引擎下的 hitTest 行為差異**：未查到官方對 Impeller vs Skia 在 hitTest 行為的明確比較文件。
4. **Obsidian Graph View 的「text fade threshold」數值預設值**：未查到官方預設值，僅有社群描述「越高越要縮到很近才顯示」。

---

> **研究結束**。本報告為「純研究」性質，**未修改 bridge_app 任何程式碼**，僅寫入 `<HOME>/Developer/bridge_app/docs/RESEARCH_GRAPH_DESIGN_OBSIDIAN.md` 一份文件。
