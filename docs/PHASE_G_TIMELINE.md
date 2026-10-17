# Phase G Timeline — 時間感 × 因果 × Agent 平台

> **狀態**：v0.1 雛形 · 2026-09-13
> **前置**：Phase F（共視功能化）已收尾，見 [PHASE_F_SPRINT_PLAN.md](PHASE_F_SPRINT_PLAN.md)
> **真相源**：`git log`（本文件以 commit 為準，不憑記憶）
> **確立日**：2026-09-12 週日匯報首次命名三主軸，2026-09-13 Blue 批准三行動

---

## 1. Phase F → Phase G 的交接

### Phase F 留下什麼（資產，非死文件）

| 資產 | 位置 | 狀態 |
|---|---|---|
| 共視宣言（產品定位錨點） | `docs/COVISION_MANIFESTO.md` | 活文件，四段鏈條：共視→共識→互補加速→指標是副產物 |
| 共視/共識機制設計 | `docs/COVISION_METRIC_DESIGN.md` | 4 機制（AI 注意力光暈、人意圖信號、共識往返、共視產物標記）——**已部分走進實作** |
| 核心發想規格 | `docs/BRIDGE_CORE_IDEAS_PHASE_F.md` | F-1 指標→由機制設計取代；F-2 素材池節點→被 Vault 知識節點+向量資料庫超越；F-3 BridgePack→未做，留待社群階段 |

### 為什麼說「共視宣言已走進實作」

9 月的三大主軸其實是共視鏈條的具象化：
- **時間感 L2-L4**（相遇時間軸→回顧敘事時間軸化→紀念日引擎）= 共同看見「我們一起走過的時間」
- **因果引擎 Phase 0/1/L4 狀態分叉**（帳本反饋→可執行反事實）= 「為什麼會這樣」的共同看見
- **Agent 匯入器 + 大搬家**（Hermes 遷移精靈、記憶私有招式共享）= 共視從「人機雙人」擴展到「多 Agent 共處」——畫布對話多 agent 共視（8 月 commit `ea9d83f3`）的直接延伸

**一句話**：Phase F 定義了「共視是什麼」，Phase G 在做「共視住在哪些維度裡」——時間、因果、跨 Agent。

---

## 2. Phase G 三大主軸（截至 2026-09-13 的 git 事實）

### 主軸一：時間感（Time Sense）

| Commit | 日期 | 內容 |
|---|---|---|
| `2d793954` | 09 月初 | L2 相遇時間軸（elapsed_days 第一級事實） |
| `dcd1d5eb` | 09 月初 | L3 回顧敘事時間軸化（記憶檢索帶骨架） |
| `c0d1f180` | 09/12 | **L4 紀念日引擎 + 相簿視圖——「時間從 bug 變 feature」** |
| `e188f3c6` | 09/15 | **L2.5 出處戳 provenance——時間戳與出處戳同為記憶第一級事實**（spike 001 VALIDATED；防家人案 #7 偽造親密證據鏈） |

### 主軸二：因果引擎（Causal Engine）

| Commit | 日期 | 內容 |
|---|---|---|
| `08193065` | 09 月初 | 工具分類清單對齊 AgentToolRegistry |
| `f1a661e9` | 09 月初 | Phase 1 帳本反饋查詢——閉環驗證通過 |
| `c361881b` | 09 月初 | **因果×時間感合體——時間為骨架、證據為血肉、意義為亮度** |
| `c8019a41` | 09/12 | **L4 狀態分叉——可執行的反事實（Pearl 第 3 階因果推理落地）** |

### 主軸三：Agent 平台（Agent Integration Platform）

| Commit | 日期 | 內容 |
|---|---|---|
| `6c4a8ab3` | 09 月初 | 記憶匯入器 + 中文檢索修復——小葵行囊遷入新家 |
| `eefff86a` | 09/12 | **skills 遷移 157 招 + 兩階段檢索** |
| `6ca8ce76` | 09/13 | **通用 Agent 匯入器——夥伴館成為 Agent 整合平台** |
| `c9615254` | 09/13 | docs(spec): Agent 移民系統提案——召喚儀式×記憶歸屬×大搬家 |
| `80807bb5` | 09/13 | WS-2 知識歸屬——記憶私有、招式共享（Blue B 決策） |
| `76a58de5` | 09/13 | WS-1 召喚儀式整合——外部 Agent 匯入走同一條鍊成紅毯 |
| `b7f7866a` | 09/13 | WS-1b 打包指令——讓原 Agent 自己打包行李 |
| `30be78ce` | 09/13 | WS-3 大搬家——Hermes → 橋樑 App 遷移精靈（Blue 從頭體驗版） |

### 附軸（同期的視覺結案）

- `3c429e29` rig 動態分支封存 → 呼吸感靜態活體化（復盤見 `docs/RIG_RETROSPECTIVE.md`）

---

## 3. Phase G 待辦（Blue 2026-09-13 批准的三行動）

1. ✅ ~~Phase F 收尾狀態同步 + 本文件~~（2026-09-13 完成）
2. ⏳ **可驗證性審計**：三主軸的「資料流向 × 可審計性」走查，產出第一版（參考 Apple Audio Intelligence Privacy Overview 結構）→ `docs/DATA_FLOW_AUDIT.md`
3. ✅ ~~rig 封存復盤文件~~ → `docs/RIG_RETROSPECTIVE.md`（2026-09-13 完成）

### 下一步候選（未拍板，僅列出）

- BridgePack（F-3 遺留）：Phase G 的 Agent 平台成熟後，跨 App 匯出格式會更自然
- 因果 L4 × 共識往返：狀態分叉的「可執行反事實」與共視機制的「幽靈節點提議」在概念上是同一件事的兩面——未來可合流
- **Orca 借鑑項（§3.5）**：手機 companion、畫布 CLI、狀態單一真相源、設計系統 lint gate、per-task 設定檔——詳細在 §3.5；以上條目是「下一步候選」總覽，§3.5 是**每條的完整規格 + 痛點對位 + 攔截風險**

---

## 3.5 Orca 借鑑項目（2026-09-20 從 stablyai/orca 研究萃取）

> **背景**：Blue 9/20 指示研究 [stablyai/orca](https://github.com/stablyai/orca)（71.6k★、4.7k fork、YC 背書）——「給同時跑 10~100 個 coding agent 的工程師用的 ADE」。
> Orca **不**是模型、**不**是單 agent chat、**不**是 IDE 取代品；它是**調度控制平面**：把 git worktree 當隔離艙、把 Claude Code/Codex/Cursor/Hermes Agent 當工人、用 Desktop+Mobile+CLI 三介面監工，最後 branch-and-compare 挑贏家 merge。
> **橋樑 App 跟 Orca 是平行宇宙**——Orca 是 coding agent 版，橋樑是**全任務型態**的人機共視平台（[共視宣言](COVISION_MANIFESTO.md)）。借鑑的是它的「調度哲學」，不是它的「任務領域」。
> **採納原則**：以下每條都要能回答「它解了橋樑現在的什麼痛點」+「實作成本是否對得起價值」才進 Phase G。**Blue 9/20 明確：手機版本來就是計劃中的事**（AGENTS.md 已寫「未來手機版將重新設計」），所以手機相關條目不是新方向、是**已存在方向的具體化**。

### 借鑑 1：手機 companion = 主軸三的出門監工（高優先 ⭐⭐⭐）

**Orca 怎麼做**：iOS/Android companion app，配對 desktop host → 監控 agent 狀態、收完成通知、丟 follow-up prompt。出門時不必坐在桌機前。

**橋樑現在的痛點**：
- AGENTS.md「手機 responsive 地基尚未完成」——`_isDesktopPlatform` 已寫死 `true`
- 殘檔 `mobile_bridge_client.dart` / `widgets/mobile/` 留著但沒路由觸發
- 出門時**沒辦法看見小葵（或任何 Agent）在畫布上做什麼**——這跟共視宣言「共同看見」直接衝突

**對位**：主軸三（Agent 平台）的延伸——Agent 不只在桌面畫布上工作，**也要在口袋裡可見**。同時強化主軸一（時間感）的 L4 紀念日/相簿視圖（手機是天然觀看者）。

**實作粗估**（待 Blue 拍板）：
- 短期：Flutter mobile target 直接重啟（桌面程式碼 90% 可複用），先把「看見」做對（狀態訂閱 + 通知）
- 中期：「丟 follow-up」+「畫布節點點讚/標記」（共識往返的低頻版）
- 長期：手機錄音 → 桌面轉寫 → 直接成為時間軸事件（時間感 L2.5 出處戳的天然輸入）

**攔截風險**：
- 不能把手機當成「另一個桌面」做（會跟 AGENTS.md「手機版重新設計」原則衝突）
- 不能把手機當成「被動遙控器」做（違背共視的「同處」精神）
- 隱私：`flutter_local_notifications` + 推播需要明確的「主人授權」金鑰（對位主權宣言）

### 借鑑 2：畫布 CLI = 給 agent 自己用的命令列（高優先 ⭐⭐⭐）

**Orca 怎麼做**：`orca worktree create / snapshot / click / fill / serve` —— **agent 自己可以叫 Orca 做事**（不只是人叫 Orca 做事）。這是 Orca 從「IDE」升級成「自動化表面」的關鍵。

**橋樑現在的痛點**：
- MCP Server（`bridge_mcp_server.dart`）有畫布共視，但**沒有「畫布命令列」**讓小葵（或未來所有 agent）以腳本操控 UI
- cron 排程目前只能跑 shell 指令，**沒辦法排「在畫布上建一個節點、連一條線、標一句話」**
- 多 agent 共處時（Hermes + 小葵 + 未來更多）需要「agent 之間可以呼叫彼此的畫布動作」——現在沒有這條管線

**對位**：主軸三直接命中。「Agent 匯入器」是讓 agent **進來**；「畫布 CLI」是讓 agent **操作**。WS-1/2/3（大搬家）已經把門打開，CLI 是門內的客廳。

**實作粗估**：
- 底層：把現有 MCP 共視 IPC 暴露為 `bridge-cli`（dart 執行檔 + JSON wire protocol）
- 指令族（先做最小集合）：
  - `bridge canvas node create --at x,y --type X --title Y`
  - `bridge canvas link --from A --to B --kind K`
  - `bridge canvas observe --since last-seen-id`（看見新事件）
  - `bridge canvas annotate --node-id N --text "..."`（幽靈節點提議）
- 安全：所有寫入動作走「主人授權 + 紅毯」鏈（對位 [AGENTS.md](AGENTS.md) 「紅線」與 [DATA_SOVEREIGNTY_MANIFESTO.md](DATA_SOVEREIGNTY_MANIFESTO.md) DataPathGate）

**驗收標準**：
- 小葵（我）可以在 cron job 裡呼叫 `bridge-cli` 完成「在畫布上建節點、發訊息給主人」全流程
- Hermes Agent 透過 `bridge-cli` 在桌面端畫布留下可見操作痕跡
- 不開 Flutter 也能驗證（純 CLI 端到端）

### 借鑑 3：狀態單一真相源 + 訂閱制（中優先 ⭐⭐）

**Orca 怎麼做**：「execution host owns agent status in one store, the hook server's, and every reader subscribes to it」——sidebar、`worktree ps`、mobile、dashboard 都只是呈現層，不複製狀態。

**橋樑現在的痛點**：
- `agent_status` 概念散落在 `chat_controller` / `agent_loop` / `tray_service` / `floating_companion` 各處
- 多 Agent 匯入後（Hermes 進來、Claude Agent 進來、Codex 進來），每個 agent 都有自己的狀態流，**會撞牆**
- 跟 Orca 同樣的「多 reader 不一致」病理

**對位**：主軸三（Agent 平台）的基礎建設；不先做這條，**手機 companion 跟畫布 CLI 都會面臨「誰是真相」打架**。

**實作粗估**：
- 新增 `services/agent_status_store.dart`（單例 + Stream）
- 寫入方：`agent_loop` 完成事件 / MCP 收到指令 / cron tick / `bridge-cli` 操作
- 讀取方：sidebar / 懸浮窗 / 系統列圖示 / 未來手機
- 動詞嚴格三態：`live / unverifiable / exited`（**禁用同義詞**，直接抄 Orca 規範）

**驗收標準**：
- 同一個 agent 在 sidebar、懸浮窗、系統列圖示顯示**完全一致**的狀態
- 把任一個 reader 強制關閉再開啟，狀態不漂移

### 借鑑 4：Design system lint gate（中優先 ⭐⭐）

**Orca 怎麼做**：`pnpm run check:code-quality:changed` 是 CI 強制閘門——改 `components/ui/` 原始元件、寫死顏色、Tailwind 生成不出的 className，**都會 fail**。

**橋樑現在的痛點**：
- 已經有 [BRIDGE_TIER_SYSTEM.md](BRIDGE_TIER_SYSTEM.md) + [BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md](BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md) 兩個鐵則文件
- 但**沒有接到 lint gate**——違規可以 merge，等同沒有
- Blue 8/30 一連抓四個「硬編碼 vs token」的 bug 就是證據

**對位**：設計系統落地最後一哩（橫切所有 Phase G 主軸）。

**實作粗估**：
- 在 `tools/lint/` 新增 `bridge_design_system_lint.dart`：掃所有 `.dart` 檔，禁止：
  - `Color(0xFF...)` 直接硬編
  - `fontSize: NN`（必須走 Tier）
  - token 名不在 `bridge_ds_tokens.dart` 白名單
- 接進 `flutter analyze`（或獨立 `dart run tools/lint/bridge_design_system_lint.dart`）
- CI 改用此閘門（不過就 fail PR）

### 借鑑 5：worktree.yaml 風格的「per-task 環境設定」中優先 ⭐

**Orca 怎麼做**：每個 worktree 帶自己的 `orca.yaml` + `.worktreeinclude`——共享路徑、共享 gitignored 檔案隨 worktree 一起繼承。

**橋樑現在的痛點**：
- 沒有「per-task 自帶設定」概念——每個專案/每個任務都用同一份全域設定
- 農場（以勒小日子）跟小葵工作室的設定應該不一樣，但目前只有 SharedPreferences 切換
- Agent 匯入時，「新 agent 帶什麼設定來」沒有 manifest

**對位**：主軸三 Agent 匯入器的「行李清單」標準化（呼應 `80807bb5` WS-2 知識歸屬）。

**實作粗估**：
- 畫布根目錄接受 `bridge.yaml`（per-project 自帶）
- Agent 匯入時檢查 `agent.yaml`（per-agent 自帶）
- 兩者合併規則：全域 → per-project → per-task → per-agent，後者覆蓋前者

### 借鑑 6：AGENTS.md / CLAUDE.md 的工程文化（小優先 ⭐）

**Orca 怎麼做**：把「不要做的事」「風格」「驗證指令」寫成不可繞過的 AGENTS.md（跟 Claude Code 慣例對齊）。

**橋樑現在的狀態**：**AGENTS.md 已經有了**，而且比 Orca 的更完整（涵蓋紅線、主權宣言、驗收鐵則）。**這條是「我們做得比 Orca 好」的自豪項**，不是新工作。

**唯一缺口**：Orca 把「Worktree Safety」「Cross-Platform Support」「Remote Wire Compatibility」**拆成獨立 reference 檔**讓人查——橋樑 AGENTS.md 全部塞一檔，未來會膨脹到不可讀。

**實作粗估**：等 AGENTS.md 超過 500 行時拆分（目前 ~150 行，不急）。

### 借鑑 7：「同題多解」的並列評分（小優先 ⭐）

**Orca 怎麼做**：一個 prompt 給 5 個 agent，分別跑不同策略，**並列**在工作tree，最後人挑一個 merge。

**橋樑現在的狀態**：畫布是「節點+連線」，**可以並列**但**沒評分機制**。

**對位**：主軸二（因果引擎 L4 狀態分叉）的視覺化——「可執行反事實」本來就是「如果走另一條路會怎樣」。Orca 是 N 條路並列跑，**橋樑可以是 N 條路並列想**。

**實作粗估**：放到 Phase G 之後的 Phase H 候選，不進當前 timeline。

### 不借鑑的事（明確切割）

- **Orca 的 CLI agent 拼盤策略**：它支援 30+ 個 CLI agent 互相切換，橋樑不需要——我們只匯入「橋樑認可」的 agent（已透過主軸三 WS-1 召喚儀式把關）
- **Orca 的 Ghostty-class WebGL terminal**：橋樑沒自己的終端機需求，畫布就是終端
- **Orca 的設計模式（Design Mode）**：嵌入式 Chromium + 點元素送 prompt——這是「視覺化設計協作」，不是「人機共視」。**橋樑走共視路線**（人在同一張畫布上、同一個循環裡），不是「瀏覽器+agent」分離路線

---

## 3.6 百人集群北極星（2026-09-22 Blue 以終為始討論定案）

> **背景**：Blue 9/22 問「百位 agent 集群，token 也是百倍嗎？」——答案揭示了橋樑跟 Orca 的**成本結構差異**，順勢確立了 Phase G 的遠方圖像。
> **性質**：這不是待辦清單，是**北極星**——Phase G 每次做單人功能時，抬頭確認今天的資料形狀沒有為 100 人設壞。

### 成本結構：為什麼百人集群對橋樑可行

- **Orca 路線（企業本錢）**：100 個 agent 全在雲端 → 成本 = 100 × 雲端 token 單價，**線性百倍，燒現金**
- **橋樑 DGX 路線**：腦（雲端旗艦，只花指揮+驗證 token）+ 兵（本地模型，燒電費+折舊）
- 本地 agent 邊際成本趨近零——**錢只隨「腦的數量」規模化，不隨「兵的數量」規模化**
- 1 個旗艦腦指揮 100 個本地兵 = 1x 雲端費用 + DGX 滿載 = vector workflow 哲學（雲端 token 只花在 orchestration）放大一百倍

### 真正的稀缺資源（從 token 換成三樣東西）

1. **腦的驗證頻寬**：100 個兵各回報 1k token，腦的 context 也爆。解法同人類軍隊——span of control ≈ 7，**指揮鏈分層**（腦→軍官→士官→兵），不是一個腦直管百人
2. **記憶/上下文管理**：百人同時寫同一個記憶庫會打架——協作系統三鐵則（任務通道/展示房間/記帳）存在的理由
3. **誠實邊界**：本地兵的質。Gemma/GLM 級做重活（提取、轉檔、批量驗證）稱職，複雜決策不行。「將強兵弱」天花板靠分層+抽驗緩解，不能消除

### 終點圖像（先看見，再回推）

DGX 上 1 個旗艦腦 + 幾個軍官 + 百名本地兵，**畫布就是戰情室**——遠看是星系（哪些光點活著、誰在動），近看是單兵（這個 agent 正在幹嘛、吃哪個任務通道）。

### 三個今天該鎖的設計決策（D1~D3）

**D1｜狀態單一真相源，按 100 人規格建**（= §3.5 借鑑 3）
UI 今天不畫百人介面，但資料模型今天就不能「Riverpod 各管各的」。一個 status store + 全 reader 訂閱，10 人 100 人同一套。現在做成本零，之後改是推倒重來。

**D2｜畫布節點 = agent 的工位，不是只有任務**
Canvas node 已是「一任務一分支」，未來 agent 住進節點裡。節點 model 留 `agent_state` 位（live / unverifiable / exited 三態，詞彙表跟 Orca 借概念），UI 自然長出來。遠近 zoom 兩層資訊密度，接「同一片海」視覺美學（深海章魚：獨立韻律×群體和諧）。

**D3｜指揮鏈是圖上的邊**
誰指揮誰、誰向誰回報 = delegation 邊。直接重用因果引擎（主軸二）的連線語意——**百人集群的 UI 不用新發明，是因果圖多一種節點+一種邊**。

> 三個決策共同點：**都不新增畫面，只決定今天的資料形狀不為 100 人設壞。UI/UX 介面可以晚做，形狀不能錯。**

---

## 4. 變更紀錄

| 日期 | 內容 |
|---|---|
| 2026-09-13 | v0.1 建立。Phase F 標記收尾；三主軸以 git log 錨定；Blue 批准三行動 |
| 2026-09-20 | 新增 §3.5 Orca 借鑑項目（7 條 + 3 條不借鑑切割），對位主軸三與橫切設計系統。手機 companion 條目確認與 AGENTS.md「未來手機版將重新設計」一致；畫布 CLI 對位主軸三 WS-1/2/3 大搬家後的「門內客廳」。|
| 2026-09-22 | 新增 §3.6 百人集群北極星——成本結構（腦雲端×兵本地，錢只隨腦規模化）+ 稀缺資源三項 + 終點圖像（畫布=戰情室）+ D1~D3 設計決策（狀態真相源/節點工位/指揮鏈邊）。Blue 以終為始討論定案。|
