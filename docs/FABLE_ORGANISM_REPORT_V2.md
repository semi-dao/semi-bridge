# 橋樑 App 生命體理解報告 V2

> 日期：2026-10-15 ｜ 真相源：HEAD `62dfae1a`（2,024 commits）｜ 方法：grep 證據級，每條宣稱附 `檔案:行號`
> 輸入材料：`docs/WEAVE_PROGRESS_REPORT_20261015.md`、`training/semi_s15/m1/REPORT_M1_FINAL.md`、`docs/K1_DECISION_GATEKEEPER_DESIGN.md`、`docs/K1_EG2_MIGRATION_PLAN.md`、`docs/V040_AGENT_AS_USER_DESIGN_INPUTS.md`、`docs/WEAVE_MAP_V2.md`

## 0. 一句話診斷

八個器官各自都活著，而且各自都有測試。壞的是血管：五本記錄沒有共同鑰匙、兩個向量空間混在一個搜尋裡、M2 的靈魂沒有裝進身體、M3 的熔斷器吃的是錯的訊號、分流器的決定沒有人執行。Blue 說的「各自為政」在代碼裡有七條可指到行號的證據（第 9 節）。

## 1. 一則訊息的血液循環（實際接線）

```
使用者訊息
 │ chat_controller.sendMessage (:7015)
 ├─ CorrectionCatcher.detect (:7104) → correction_events → appendReaction('corrected') (:4062) → CalibrationBreaker.evaluate (:4065)
 ├─ 分流：saved provider → ProviderRouter.resolveDefault / setCurrent / route (:7336-7364)
 └─ _runAgentLoopIfNeeded (:1690)
      ├─ BrainContainerService.getFormattedContext (:1711) ＋ MemoryLayerService.buildInjectionSection L1-L3 (:1724) → system prompt
      └─ AgentLoop.run (agent_loop.dart:213) → _runInner (:380)
           ├─ InjectionPreparer.prepare (:419) → K1Gatekeeper.classify (injection_preparer:59) → HybridSearch top3 (:168) → InjectPipeline.enrichWith (:77) → 〔背景記憶〕塊附 user 訊息 (:615)
           ├─ EventLedger.appendTurn (:456)  [decision=K1 label, confidence=K1 conf]
           ├─ CausalLedger.recallSimilar 反饋附 user 訊息 (:503-507)
           ├─ lite path / chat mode 由 K1 label 決定 (:489, :525)
           ├─ CalibrationBreaker.allows(K1 conf) 否決 lite (:564)
           ├─ for turn < 100000 (:623) → ProductionAgentLoopLLMClient.complete → ApiService.completeWithMessagesRaw
           │     每次工具呼叫：CompassMedic.preFlight (:1063) → 執行 → CausalLedger.record (:1134) → 傷口開/關 (:1156-1169)
           └─ finally CausalLedger.record('agent_perf') (:285)
```

## 2. 器官一：agent_loop

**職責**：唯一的迴圈引擎 `AgentLoop`（`lib/services/agent_loop/agent_loop.dart:124`）。工具呼叫以 prompt 內 JSON 表達，非原生 function calling（`:14-17`）。`NativeAgentLoop`（`lib/services/native_agent_loop.dart:38`）不是第二個迴圈，是事件匯流排觸發層，包著同一個 `AgentLoop`（`:63, :96`）。

**健康度證據**
- 建構點兩處：`chat_controller.dart:1456`（聊天）與 `bridge_desktop_screen.dart:1742-1745`（畫布，交給 NativeAgentLoop `:1756`）。
- 最近 commit：`3de6fb03`（熔斷）、`9004237c`（CLM context）、`808aee43`（M1 單一注入）、`1910c958`（M0）。
- 測試：`test/agent_loop/` 9 檔多為工具與 store；`test/agent_loop_integration_test.dart:19` 是空骨架（「這個測試還沒實作」）；唯一建構 AgentLoop 的 e2e 需 `GEMINI_API_KEY`。`test/reports/agent_loop_e2e_report.json` 0 pass / 2 fail，理由皆「GEMINI_API_KEY 未設定」，turnCount 0，時間戳 2026-10-14T22:38:55（未 commit）。**迴圈控制流從未在 mock client 下跑過。**

**實際接線**
- K1：不直接呼叫，透過 `InjectionPreparer.prepare` (`:419`)；label 決定對話模式 (`:489-491`) 與輕裝路徑 (`:525-529`)。
- 記憶：`InjectionPreparer` 走 `HybridSearchService`（`injection_preparer.dart:168`）；`MemoryRetrievalPipeline` 只在工具 `memory_search_tool.dart:127` 可達。**兩條檢索路徑。**
- 因果：每次註冊工具呼叫記一筆 (`:1134-1143`)、每輪 `agent_perf` 一筆 (`:285-295`)、反饋查詢 (`:503-507`)、認知傷口判定讀 `lastEntry` (`:317`)。
- 羅盤：只接 `CompassMedic`（`:272, :322, :1063, :1156, :1159, :1169`）與工具 `compass_toolseek` (`:535`)。不接 heartbeat。

**風險**
1. 「強制結束」不結束：同工具 ≥10 次 (`:1001-1009`) 與 A→B 交替 ≥4 次 (`:1032-1041`) 只注入訊息，無 `return`；`hardMaxTurns = 100000` (`:147`)。實際停止條件只剩模型自願停或使用者取消。
2. timeout 無限重試 (`:752-767`)，每輪等 90s / 本地 300s (`:739-742`)。
3. 每次 run 把完整 system prompt 與 user prompt 寫到 `/tmp/agent_prompt_dump.txt` (`:249-252`)。資料主權宣言下這是漏洞。
4. 兩層截斷互打：LLM client 原地改共用 `messages` (`production_agent_loop_llm_client.dart:288-297, :384-386, :415-417`)，本地分支丟歷史不歸檔，抵銷 CLM 的 archive-and-pointer 設計 (`agent_loop.dart:663-667`)。
5. 實例狀態 (`_medicFailStreak`、`_contextStore`、`_currentTurns`，`:169-196`) 不耐並行；聊天實例無 `_isActing` 守衛。
6. 死碼：`CanvasPlaceTool`/`CanvasConnectTool` 從未建構；`NativeAgentLoop._handleUserIdle` (`:278`) 不可達，60 秒 idle timer 仍在跑 (`:117`)。

## 3. 器官二：K1 決策頭

**職責**：`K1Gatekeeper` 單例（`lib/services/decision/k1_gatekeeper.dart:14-16`），三層：正則規則 (`:47-57`) → 線性頭 (`:59-93`，conf < 0.7 或 margin < 0.2 即 escalate，`:19-20`) → fallback `general_chat` + `escalated:true` (`:95-104`)。表徵來自 `EmbeddingService.embedQuery` (`:64`)，純 Dart softmax 頭 (`decision_head.dart:88-105`)。已改二元 lookup/skip (`decision_head.dart:32-42`)。

**健康度證據**
- 頭有掛上：`BrainContainerService._initializeOnce` 步驟 2.5 呼叫 `K1Bootstrapper.instance.restoreFromStore()`（`brain_container_service.dart:121`，本 session 親驗）；`POST /k1/train`、`GET /k1/head` 在 `bridge_mcp_server.dart:290-291`。commit `9639e205`：LOO-CV 0.78 過 0.75 門檻，`brain_state/k1_head.json` 34KB。
- M1 封卷（`REPORT_M1_FINAL.md`）：注入配對差 -1、McNemar p=1.0、coverage@0.7 4.7-5.5%、空塊率 89.2%；K1 頭掛載前後注入塊逐字節相同 0/361。結論「K1 是加菜非守門」(`§3`)。
- 測試 `test/k1_gatekeeper_test.dart` 4 項，無二元標籤、無 Bootstrapper、無 InjectionPreparer K1 分支測試。

**實際接線**：唯一生產呼叫點 `injection_preparer.dart:59`；`decision.needMemory && !decision.escalated` 時合併 hybrid top3 (`:66-69`)。`logSample` 寫 `CausalLedger` toolName `k1_gatekeeper` (`k1_gatekeeper.dart:108-120`)。

**風險**
1. escalate 是空操作：設計稿 `§2` 的「escalate 給 LLM 完整推理」路徑不存在，escalate 只等於「跳過 K1 候選」。
2. 自訓練迴路（設計稿 `§5`）無法落地：`CausalEntry` 無 `turn_id` 欄 (`causal_ledger_service.dart:120-140`)，`logSample` 一律 `success: true`，判斷與事後結果無法 join。
3. 規則正則過寬（`多少|什麼時候|歷史`，`k1_gatekeeper.dart:26`）。
4. `DecisionHead.fromJson` 的 `.cast<double>()` (`decision_head.dart:119-121`) 遇 int 序列化會 lazy throw，`DecisionStore.load` 吞掉回 null (`:211-213`)。
5. K1 品質跟著 EG2 走：EG2 掛了 query 落到 300M，與訓練頭時的表徵不同（`K1_EG2_MIGRATION_PLAN.md:59` 的 A/B 驗收尚未做）。

## 4. 器官三：腦容器

**職責**：`BrainContainerService` 單例 facade（`brain_container_service.dart:58-72`），一個 SQLite 檔 `brain_container.db` + sqlite_vector 擴展（`brain_database.dart:39, :113, :120`），schema v19（`brain_schema_sql.dart:20`）。主表 `memories`、`agent_memories`、`asset_index`、`asset_chunks`。十層記憶在 `agent_memories.layer`（遷移 `from_v18_to_v19`，`brain_schema_sql.dart:516-530`）。同名陷阱：`lib/services/brain_pipeline/brain_container.dart` 是抽象介面＋adapter，無儲存。

**健康度證據**：PHASE_LINES_MAP M1-M5 ✅；`test/brain_container/` 8 檔含 `vector_join_regression_test`、`provenance_stamp_test`；`test/services/memory_layer_test.dart`。最近 commit `0e503c16`、`78bca10d`（地板 0.40）、`59d53e09`。

**實際接線**：注入有三條路：① `getFormattedContext` 進 system prompt (`chat_controller.dart:1711-1713` → `:1889`)；② L1-L3 全量 (`:1723-1726`，上限約 16,000 字，`memory_layer_service.dart:270`)；③ M0/M1 塊附 user 訊息 (`agent_loop.dart:615-616`)。三條可重疊。

**風險**
1. `InjectPipeline.parseMemoryHit` 需 `[type]` 前綴且不傳 `layer`，無前綴的 `memories` 命中被 slot_filter 丟掉 (`inject_pipeline.dart:134-143`, `slot_filter.dart:48-85`)。空塊率 89% 的另一個嫌犯。
2. `MemoryRetrievalPipeline.retrieve` 的 `roomFilter` 參數未使用 (`memory_retrieval_pipeline.dart:64-68`)。
3. `agent_memories` 無向量模型版本欄 (`brain_schema_sql.dart:206`)；`reindexFallbackMemories` 一律蓋 `gemma-300m-v1` 即使向量來自 EG2 (`brain_container_service.dart:695`)。
4. **L4 信念唯一寫入函式 `MemoryLayerService.write` (`:94`) 在 lib 內零生產呼叫者**（本 session grep 親驗）；現存 L4 全來自 v19 遷移的 backfill (`brain_schema_sql.dart:524, :528`)。

## 5. 器官四：因果引擎

**職責**：`CausalLedger`（`lib/services/causal/causal_ledger_service.dart`，注意無 `CausalLedgerService` 類）獨立 DB `causal_ledger.db` (`:198-203`)，表 `agent_causal_ledger` 八欄 (`:174-183`)，2000 筆環形但只在 `initialize` 修剪 (`:190-191`)。`EvidenceGrade` 四級由手維工具清單決定 (`:54-117`)。`CausalForkService.run` 快照→改→diff→還原→記帳 (`causal_fork_service.dart:85-125`)；`CausalForkTool` 只對畫布加一節點再移除 (`causal_fork_tool.dart:64-79`)。

**健康度證據**：`test/services/causal_ledger_test.dart` 16 項、`causal_fork_test.dart` 3 項；無 `CausalForkTool` 與 agent_loop 記帳點測試。PHASE_G 列的四個 commit 全在。

**實際接線**：寫者七處（agent_loop 工具 `:1134` 與 agent_perf `:285`、k1_gatekeeper `:110`、compass_medic `:192/:230/:267`、tool_seek_tool `:99`、swarm_harvest `:347`、causal_fork_service `:118`）。讀者：agent_loop 反饋 (`:503-507`)、認知傷口 (`:316-317`)、life_tree_screen `:59-61`、compass_self_gauge `:125-136`（直接 `sqlite3.open` 同一檔）。`causal_fork` 註冊在 `agent_tool_registry.dart:235`，無 8420 路由。

**風險**
1. DB 未開前 `record` 靜默丟棄 (`:208-211`)，而 `initialize()` 不被 await (`agent_loop.dart:408`)：啟動後首批工具呼叫可能消失。
2. 每輪 `agent_perf` + `k1_gatekeeper` 兩筆記帳擠環形，真工具史被推出。
3. fork 無 `try/finally` 還原 (`causal_fork_service.dart:98-104`)，`_activeForks` 只增不減 (`:67, :116`)；fork 直接改使用者正在看的畫布 (`causal_fork_tool.dart:64`)。fork 同一呼叫記兩筆。
4. `recallSimilar` 是末 5 關鍵詞 LIKE (`:290-304`)，結果以「可信事實」注入 (`:419`)。
5. 帳本無 memory id、無 turn_id；`life_tree_thought_branches.ledger_id` 外鍵存在但無生產寫者。

## 6. 器官五：檢索向量庫

**職責**：`EmbeddingService` 768 維 L2 正規化 (`embedding_service.dart:29-43`)，雙 backend：EG2 `http://127.0.0.1:18890` (`:41`) 優先，300M tflite 次之，再掛回零向量標 `mock-fallback` (`:101-127`)。`HybridSearchService` 以 `vector_full_scan` 掃四表 (`hybrid_search_service.dart:736, :794, :844, :884`)。`Eg2ReembedService` 冪等重嵌 (`eg2_reembed_service.dart`)。

**健康度證據**：asset_index 67,721 筆，重嵌 14,156 筆 @17:55（進度報告）。`test/eg2_backend_test.dart` 3 項離線；無 EmbeddingService 切換、無 Eg2ReembedService、無 schema 測試。最近 commit `0e503c16`、`fccc20e0`、`e584c387`。

**實際接線**：`embedQuery` 呼叫者含 `memory_retrieval_pipeline:55`、`hybrid_search_service:236/:693`、`k1_gatekeeper:64`、`k1_bootstrapper:105`、`tool_seek_tool:69/:127/:159`、`dream_reflection:85-117`。EG2 探測只在 `initialize()` 與 `reload()` 各一次 (`:52-65, :79-84`)。

**風險**
1. `asset_index.embed_model_version` 欄在 `lib/` 內無 CREATE 也無 ALTER；`git log -S embed_model_version` 只命中 `fccc20e0`（service 本身）。live DB 的欄位是手動 ALTER 的（進度報告「今天才 ALTER」）。新裝機或換 DB 路徑時 `SELECT` 拋 no such column，`:59` 的 catch 吞掉，連 `memories` 重嵌 (`:58`) 都跳過；`/eg2_reembed` 回應無 error 欄 (`bridge_mcp_server.dart:690-703`)。（live DB PRAGMA 讀取本 session 未獲准，標未驗證。）
2. 搜尋不按模型過濾 (`hybrid_search_service.dart:733-745, :840-853, :878-893`)：維度同為 768 不會炸，但 EG2 query 對 300M rows 的 cosine 無意義。per-call fallback 讓新 300M 向量持續寫入。
3. `asset_index_service.dart:1544-1553` 不檢查 `mock-fallback`，零向量入庫無標記。
4. EG2 query 無 task prefix (`embedding_service.dart:178-181`)，300M 有 `retrievalQuery` (`:189`)；兩空間連 prefix 慣例都不同。
5. 18890 的 launchd 啟動器不在 repo（註解稱 `farm.semiwasabi.bridgeApp.eg2`，`:38-41`）；App 先起、EG2 後起則整個 session 用 300M。

## 7. 器官六：8420 HTTP 服務

**職責**：`BridgeMcpServer`（`lib/services/bridge_mcp_server.dart:58`），loopback (`:360`)，`X-Bridge-Token` 中介層 (`:161-188`)，token 32 bytes 0600 (`:119-145`)。

**健康度證據**：路由 68 條（`grep -cE "^\s*router\.(get|post|put|delete|all)\("`），全在 `:266-342`。MCP 工具 43 個 (`_toolSchemas :1392-1929`)，非文件所說 14。`test/services/bridge_mcp_server_test.dart` 28 項；無 eg2/K1/inject_enrich/create_canvas 測試。`/eg2_reembed` 在 `:293`（`e584c387` 補插）。

**實際接線**：`send_user_message`/`inject_message` → chat (`:854, :943`，接在 `bridge_desktop_screen.dart:1127, :1231`)；`/k1/train`、`/k1/head`、`/inject/enrich` → K1 與 InjectionPreparer (`:782, :792, :815`)；`identity_reembed`/`eg2_reembed`/`rescan`/`vector_search` → 向量庫。羅盤零引用。

**風險**
1. 26 條路由無對應 tool（k1/train、k1/head、eg2_reembed、create_canvas、galaxy 系列…）；12 條 hidden dispatch 中至少 6 條因 `_proxyGet` 只發無參數 GET (`:1112-1121`) 永遠打不通（POST-only 路由）。
2. 雙啟動：`app.dart:401` 與 `bridge_desktop_screen.dart:422` 都呼叫 `start()`；守衛看 `_server` (`:261`) 但 `_server` 在 awaits 之後才賦值 (`:360`)；`late final Router _router` (`:59, :264`) 二次賦值會 throw 在 unawaited future 裡。`stop()` 後無法重啟。
3. 註冊採字串插入（`:292, :294, :295` 縮排 2 格，鄰行 4 格），`tools_health` 只比 schema↔dispatch 不比 route (`:2044-2046`)，漏插靜默。
4. GET 帶副作用：`/rescan` (`:660`)、`/vector_sketch` (`:668`)、`?start=1` (`:679, :691`)、`/galaxy_open` 執行 `open <path>` (`:3205, :3227`)。
5. `Access-Control-Allow-Origin: *` (`:1079`) 且 token 可走 URL query (`:178`)。

## 8. 器官七：本地雲端分流

**職責**：七個「router」只有三個選供應商：`ProviderRouter`（`provider_router.dart:51`）、`BrandLadderRouter`（`:183`）、以及 `ProductionAgentLoopLLMClient._resolveModel` 自己的品牌迴圈 (`:89-181`)。離合器 `LocalModelScheduler` 管 18789 上跑 chat 還是 vision (`local_model_scheduler.dart:14-15`)。

**健康度證據**：ProviderRouter、BrandLadderRouter、CapabilityRouter 無直接測試；clutch 5 項、analyzer_router 8 項、intention 24 項。最近 commit `3902058e`（Auto Clutch）、`f8691f54`（brand ladder）。

**實際接線**：`sendMessage` (`chat_controller.dart:7015`) → 模式由 saved provider 決定 (`:7336-7364`) → `_runAgentLoopIfNeeded` 的 isLocal 看 saved provider (`:1765-1769`) → `ApiService.completeWithMessagesRaw` (`api_service.dart:1412`)，base URL 只在 provider=`default` 時用 `routedBaseUrl` (`:134-137`)。本地 18789 由 Swift `startLocalRuntimeServer` 起 (`MainFlutterWindow.swift:1505, :1686`)。

**風險**
1. `ProviderRouter.route()` 的決定沒人執行：只在 provider=local 時跑，此時 ApiService 不吃 `routedBaseUrl`，route 判 cloud 的請求仍打 18789。
2. `BrandLadderRouter.advance()`/`forceStepUp()` 零呼叫者 (`:235, :304`)，default 模式永遠最便宜一階；階梯表複製兩份 (`brand_ladder_router.dart:61-97` vs `production_agent_loop_llm_client.dart:196-226`)。
3. clutch 背景 `startServer` → `activateBridgeRuntimeAsBrain` → `saveProvider('local')` (`local_model_runtime_service.dart:474-477, :503-504`)：使用者選雲端可被 vision 切換後悄悄改成本地。
4. 無 local-only 開關：default 模式有任一雲端 key 就上雲 (`provider_router.dart:332-336`)；M6 斷網模式缺根基。
5. fallback 預設不一致：`kimi` (`capability_router.dart:43`) vs `openai` (`api_service.dart:120`) vs `llama3.1:8b` 硬寫 (`native_agent_loop.dart:699`)。

## 9. 器官八：compass 羅盤

**職責**：11 檔。`CompassStore` 獨立 DB `compass_store.db` (`compass_store.dart:54`)，七表 (`:68-132`)。`CompassHeartbeat` 60s probe (`compass_heartbeat.dart:96-98`，預設 18789/18900 `:131-135`)。`CompassSelfGauge` 讀 K1 計數、傷口、規則覆蓋 (`:127-165`)。`CompassMedic`（在 `agent_loop/` 目錄）是迴圈的軍醫，用羅盤當藥櫃 (`compass_medic.dart:2-17`)。

**健康度證據**：`test/compass_store_test.dart` 9 項；heartbeat/harvest/self_gauge/galaxy_bridge/medic 零測試。最近 commit 多為生命樹與傷口，非羅盤核心。

**實際接線**：`app.dart:491` bootstrap；`:494-504` 一次性 60s timer 內建 heartbeat 與 galaxy bridge，並掛 `_DreamTickerProbe` 每分鐘 `DreamScheduler.tick()`（只在 02:00-05:00 做事，`dream_scheduler.dart:37`）。**heartbeat 與 dream 都不呼叫 chat_controller 或 AgentLoop，羅盤今天不能開口。**

**風險**
1. heartbeat 結果只存在閉包內的本地變數 `hb` (`app.dart:496`)，`last()` 無人可達；store 無健康欄位。實務上 heartbeat 只是 dream 計時器。
2. timer 永不 `stop()`；`dream_scheduler.dart:29-32` 已記錄一次 initState 重入導致雙寫。
3. 無消費者：`CompassRuleCache.changes` 無 listener；`galaxy_rules.json` 無讀者；`self_gauge_last` 無讀者；`bootBriefing()` (`compass_medic.dart:105`) 無呼叫者。
4. `compass/compass_tools.dart`（`CompassAgentTools`）零 importer，是死碼；活的是 `compass_tools_agent.dart`。
5. `compass_seek` 是關鍵字子串比對 (`compass_medic.dart:314-330`)，與向量庫無關。

## 10. 七條跨模組整合問題（本 session 複驗）

**① 熔斷器吃錯訊號，且會錯殺信念（M3 × EventLedger × K1 × L4）**
- `appendReaction` 全 lib 唯一生產寫者是 `chat_controller.dart:4062`，只寫 `'corrected'`；沒有任何 `'accepted'` 來源。
- `EventLedger.onlineCalibration` 以 `reaction == 'accepted'` 算正確 (`event_ledger.dart:248`)，故每個信心區 acc 恆為 0。
- `CalibrationBreaker.minSamples = 3`、`accuracyFloor = 0.5` (`calibration_breaker.dart:32, :36`)：任一信心區累積 3 筆糾正就熔斷。
- 熔斷動作封存「近 7 天全部 L4」(`:115-121`)，與觸發的信心區無關聯。
- `turn.confidence` 欄填的是 K1「要不要查記憶」的信心 (`agent_loop.dart:461-462`)，不是回答正確性信心。熔斷的語意基礎本身是錯配的。
- 後果：M3「≤5 次互動內降級」的驗收，今天會以錯誤理由通過。

**② BeliefGate 守的是沒人走的門（M3 × 腦容器）**
- `BeliefGate.checkL4` 只掛在 `MemoryLayerService.write()` L4 分支 (`memory_layer_service.dart:105-113`)。
- `MemoryLayerService.write` 在 lib 零呼叫者（grep `MemoryLayerService.instance.write`、`.write(` 皆空；`l4Environment` 只在該檔本身出現）。
- 現存 L4 全來自 v19 遷移 backfill (`brain_schema_sql.dart:524, :528`)。
- 後果：M3 第二刀代碼與測試都綠，但生產環境無信念寫入通道，門沒有流量。

**③ M2 語氣層沒有裝進身體（M2 × agent_loop prompt）**
- `persona_cloud.txt`/`persona_e4b.txt` 只由 `training/semi_s15/m2/m2_compile_prompt.py:133-134` 寫到 `dist/`；`lib/` 內對 `persona_e4b`、`persona_cloud`、`semi_s15` 零引用。
- runtime 人格來源是 `companion.soulMd` (`companion.dart:355, :521-526`) 與 `AgentLoopPromptBuilder.build(personaCard:)` (`agent_loop_prompt_builder.dart:58, :97-98`)。
- 後果：盲測 14/15 畢業的是 python 腳本組出來的 prompt，不是 App 送出去的 prompt。Blue 盲選 15 題在接線前做，判定的對象不存在於產品中。

**④ 向量空間的 schema 漂移與混空間搜尋（EG2 × 腦容器 × 檢索）**
- `embed_model_version` 無 migration（第 6 節風險 1）；live DB 靠手動 ALTER。
- 搜尋四表不按模型過濾；per-call fallback 持續寫入 300M 向量；`reindexFallbackMemories` 貼錯標籤；零向量入庫無標記。
- 後果：重嵌跑批期間（現 21%）所有檢索、K1、tool_seek、dream_reflection 都在混空間裡打分。M1.5 若此時評測，結果不可信。

**⑤ K1 的 escalate 是空操作，自訓練迴路無鑰匙可接（K1 × 因果帳本 × 事件日誌）**
- escalate 只等於跳過 K1 候選 (`injection_preparer.dart:66`)；無 LLM 裁決路徑。
- `CausalEntry` 無 `turn_id` (`causal_ledger_service.dart:120-140`)；`EventLedger` 有 `decision` 無 outcome；`correction_events` 以 `message_id`/`conversation_id` 鍵。三本記錄無共同鍵，設計稿 `§5` 的「K1 判斷 × 事後結果」無法 join。
- 後果：K1 永遠停在規則＋100 題頭，「越用越懂」不會發生。

**⑥ 五本記錄、兩個 DB、零共同鑰匙（因果 × 腦容器 × M3）**
- `causal_ledger.db`（7 個寫者，2000 筆環形，`initialize` 未 await 首批丟失）、`event_ledger`（brain_container.db）、`correction_events`、`belief_gate_log`、`circuit_breaker_log`。
- 每輪 `agent_perf` + `k1_gatekeeper` 兩筆記帳擠走工具史；`compass_self_gauge` 與 `life_tree_store` 直接開同一 DB 檔，schema 一改即斷。
- 後果：「誠實歸因 baseline」無法跨本追溯；K5 夢境議程、M3 回溯撤銷都沒有可靠索引。

**⑦ 分流器的決定沒有人執行（ProviderRouter × ApiService × clutch）**
- `route()` 只在 provider=local 跑，`ApiService` 只在 provider=default 吃 `routedBaseUrl` (`api_service.dart:134-137`)；兩者互斥，route 的 cloud 判定從未送出。
- ladder 從不升階；clutch 可背景改寫使用者 provider。
- 後果：M6「雲端呼叫率 ≤30%」與「斷網可用」兩個指標，今天沒有任何一個開關能控。

---
