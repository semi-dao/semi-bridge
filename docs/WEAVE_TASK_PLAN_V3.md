# 編織線任務計劃 V3

> 日期：2026-10-15 ｜ 依據：生命體理解報告 V2（上文）× `WEAVE_MAP_V2.md` M0-M6 ｜ 套用 `WEAVE_HANDOFF_SPEC`（任務卡＝brief 骨架）
> 動詞表：修復、接線、驗證、量測、封存、拍板

## 0. 以終為始

M6 的定義（`WEAVE_MAP_V2.md:39-41`）：Mac App 打包、斷網可用（EG2＋Laya＋E4B）、Blue 連用 7 天、雲端率 ≤30%、修正率逐週下降、Blue 說「這是它」。

從 M6 倒推，今天缺的不是能力，是五條血管：
1. 一把鑰匙（turn_id）貫穿五本記錄 → 沒有它，M3 熔斷、K1 自訓練、修正率統計都是瞎的。
2. 一個向量空間 → 沒有它，檢索、K1、M1.5 評測都不可信。
3. 一個分流真相源＋local-only 開關 → 沒有它，雲端率與斷網模式無法控。
4. 語氣層進 runtime → 沒有它，「這是它」判定的對象不在產品裡。
5. 羅盤到聊天的開口通道 → 沒有它，M4 主動性無處落地。

V3 與 V2 的差別：V2 按能力排（M0→M6），V3 先修血管再長器官。T0-T3 是血管，T4-T8 是器官接回主幹，T9-T11 是 V2 原本的 M4-M6。

## 1. 任務序列 T0-T11

### T0 真相源校正（1 天）
- **目標**：讓代碼與 live DB、文件與代碼一致。
- **內容**：① `asset_index` 加 `embed_model_version` 進 `brainMigrations`（對齊 `memories.vector_model_version` 的既有手法 `brain_schema_sql.dart:656`）；② `/eg2_reembed` 回應加 `error` 欄，`eg2_reembed_service.dart:59` 的 catch 不再吞；③ 進度報告與 V040 文件的「14 工具」改 43，「25 端點」註解改 68；④ `APP_ARCHITECTURE_MAP` 的 Swift 行號（1401→1505、2103/2120→2362）更新。
- **依賴**：無。
- **驗收**：新建空 DB 跑 `/eg2_reembed?start=1` 不拋 no such column；`flutter analyze` 0 error；`git grep "MCP 14"` 零命中。
- **風險**：migration 對已手動 ALTER 的 live DB 要 `IF NOT EXISTS` 語意（用 PRAGMA 檢查，比照 `event_ledger.dart:71-75`）。

### T1 單一鑰匙：turn_id 貫穿五本記錄（2 天）
- **目標**：事件日誌、因果帳本、糾正事件、信念門日誌、熔斷日誌共用同一 `turn_id`。
- **內容**：① `CausalEntry` 加 `turnId`，`agent_loop.dart:1134` 與 `:285` 填入本輪 id；② `K1Gatekeeper.logSample` 帶 turn_id；③ `CorrectionCatcher.record` 加 `ref_turn_id`（用 `EventLedger.lastTurnId()`）；④ `belief_gate_log`、`circuit_breaker_log` 加 `turn_id`；⑤ `CausalLedger.initialize()` 在 `_runInner` 內 await（`agent_loop.dart:408`）；⑥ `agent_perf` 與 `k1_gatekeeper` 移出 2000 筆環形（獨立表或獨立上限）。
- **依賴**：T0。
- **驗收**：單一 SQL 以 turn_id join 五表回一列；`causal_ledger_test` 新增「DB 未開時 record 不丟」測試綠。
- **風險**：`_newTurnId()` 撞號問題（`agent_loop.dart:130` 已註記）要同時解。

### T2 校準訊號修復（2 天）
- **目標**：熔斷器吃到真正的「回答正確性 × 使用者反應」訊號。
- **內容**：① `accepted` 來源：下一輪使用者訊息非糾正且非重問 → 對上一輪 append `accepted`（隱式接受）；UI 👍 為顯式；② `event_ledger` 加 `answer_confidence` 欄，`confidence` 改名或註記為 `k1_confidence`；`onlineCalibration` 改吃 `answer_confidence`；③ 熔斷撤銷改為「本信心區且 turn_id 關聯的 L4」，不再 7 天全封；④ `minSamples` 3→20；⑤ breaker 狀態持久化（現在只在記憶體 `calibration_breaker.dart:42-43`）。
- **依賴**：T1。
- **驗收**：植入 10 筆 accepted + 2 筆 corrected 於同區 → 不熔斷；3 筆 corrected 零 accepted 且 n<20 → 不熔斷；20 筆中 11 筆 corrected → 熔斷且只封存關聯 L4。
- **風險**：answer_confidence 的來源要定義（LLM 自評或 Laya 三路輸出的 softmax），這是 D2 的設計決定。

### T3 L4 信念寫入通道（1.5 天）
- **目標**：`MemoryLayerService.write` 有生產呼叫者，BeliefGate 有流量。
- **內容**：① `DreamReflection` 或 `MemoryWritePipeline` 在偵測到「環境/事實型」記憶時走 `write(layer: L4)`；② agent 工具 `memory_write` 加 `layer` 參數（L4 必過 BeliefGate，`manualOverride` 只給 UI）；③ 跑 M3 實證輪：刻意植入錯信念，驗 ≤5 次互動降級。
- **依賴**：T2（否則實證輪的降級是①的假陽性）。
- **驗收**：`belief_gate_log` 一週內有 ≥10 筆非測試來源；實證輪報告附 turn_id 鏈。
- **風險**：BeliefGate fail-open（`belief_gate.dart:95-99`）在 `correction_events` 表不存在時放行，T3 前先讓 CorrectionCatcher 的建表移到 migration。

### T4 M2 語氣層接進 runtime（1.5 天）
- **目標**：App 送出的 system prompt 含 M2 編譯產物。
- **內容**：① `m2_compile_prompt.py` 輸出改落 `assets/persona/`（或寫進 companion `soulMd` 的指定區段）；② `AgentLoopPromptBuilder.build` 依 `ProviderRouter` 結果選 cloud 版或 e4b 版；③ 盲測腳本改打 8420 `/send_user_message` 走真路徑，不再自組 prompt。
- **依賴**：T7 的分流真相源（選哪版 prompt 要看分流結果）；可先用 saved provider 暫代。
- **驗收**：`/tmp/agent_prompt_dump.txt`（T5 移除前）或 `get_agent_debug` 顯示 persona 區段；盲選 15 題在真路徑重跑 ≥11。
- **風險**：persona_cloud 41,420 字元會把 system prompt 推更深（「33K 海底」教訓，`agent_loop.dart:498`），可能要走 M0 塊附 user 訊息的同款手法。

### T5 K1 真守門（3 天）
- **目標**：escalate 有去處，自訓練迴路可 join。
- **內容**：① escalate 路徑：conf 低時以 E4B 一次 zero-shot 判 lookup/skip，結果記 `source=escalate_llm`；② 自訓練樣本 = `k1_gatekeeper` 記帳 × 同 turn_id 的 `accepted/corrected`，≥200 筆觸發 `/k1/train`；③ K1 標註 100→300（`k1_pool_unlabeled.json` 286 題）；④ M1.5 記憶相依題評測集（從 brain_container 反推 60 題）；⑤ 移除 `/tmp/agent_prompt_dump.txt` 寫入（`agent_loop.dart:249-252`）改為 opt-in debug flag。
- **依賴**：T1、T6（M1.5 要在單一向量空間下測）。
- **驗收**：M1.5 注入臂 vs 無注入臂 McNemar p<0.05；K1 頭版本號遞增且 LOO ≥0.78 不降。
- **風險**：M1 封卷 §4 列的五條死路不得重走；表徵換 EG2 後頭需重訓（T6 後一次性）。

### T6 檢索單一空間（2 天）
- **目標**：任何一次搜尋只在一個模型的向量空間內打分。
- **內容**：① `HybridSearchService` 四表查詢加 `WHERE model_version = ?`（query 用哪個模型就濾哪個）；② `EmbeddingService` fallback 時回傳帶 `modelVersion` 的結果，呼叫端寫入對應欄；③ `asset_index` 寫入拒收 `mock-fallback`；④ `reindexFallbackMemories` 用實際版本標籤；⑤ EG2 launchd plist 進 repo（`scripts/launchd/`），`EmbeddingService` 每 5 分鐘重探 18890；⑥ 重嵌完成後 K1 頭以 EG2 表徵重訓一次。
- **依賴**：T0。
- **驗收**：`SELECT model_version, COUNT(*)` 四表全為單一值；混空間回歸測試（EG2 query 對 300M rows 回空）綠。
- **風險**：重嵌跑批未完前過濾會讓 asset_index 命中數暫降（67,721 → 已重嵌數）；要在 UI 標示「重嵌中 N%」。

### T7 分流器收斂（2 天）
- **目標**：ProviderRouter 的決定 = ApiService 的執行。
- **內容**：① `ApiService` 永遠吃 `ProviderRouter.routedBaseUrl`，刪 provider=default 的特例 (`api_service.dart:134-137`)；② ladder 表只留 `brand_ladder_router.dart` 一份，`advance()` 接到 LLM client 的失敗回呼；③ clutch 的 `startServer` 不得呼叫 `saveProvider`（拆 `activateBridgeRuntimeAsBrain`）；④ 新增 `localOnly` 設定：true 時 `resolveDefault` 不得回 cloud，MemoryGuard red 改為「拒答」而非「上雲」；⑤ fallback 預設統一為一處常數。
- **依賴**：無（可與 T1-T3 並行）。
- **驗收**：`provider_router_test` 新建：local 掛掉＋雲端可用 → 請求打雲端 URL；localOnly=true → 永不出現非 127.0.0.1 的 base URL。
- **風險**：改 ApiService 影響所有非 agent 路徑（TTS、vision），要全路徑回歸。

### T8 8420 感官補全（1.5 天）
- **目標**：route、schema、dispatch 三方一致，由測試鎖死。
- **內容**：① 26 條無 tool 路由：收編為 tool 或標 `internal: true` 從 discovery 排除；② `_proxyGet` 改 `_proxy(method, args)` 支援 POST 與 query；③ 測試：schema 名集合 == dispatch case 集合 == 非 internal route 集合；④ `start()` 守衛改用 `_starting` flag，`_router` 改非 late final 可重建；⑤ 帶副作用的 GET 改 POST。
- **依賴**：無。
- **驗收**：`bridge_mcp_server_test` 新增三方一致測試綠；連按兩次 `start()` 無 LateInitializationError。
- **風險**：Hermes 端 MCP client 若硬編 GET 路徑，②⑤ 會破壞相容，要先盤點 `scripts/mcp2026_test/`。

### T9 羅盤開口 M4（2 天）
- **目標**：羅盤精靈能對使者說話，每日 ≤3 則，零不可逆。
- **內容**：① heartbeat 結果落 `compass_store`（新表 `compass_health`），`hb` 提升為 app 級單例可 `stop()`；② `CompassSelfGauge` 紅旗 + `DreamScheduler` 產出 → 新事件 `compass.speak`；③ chat_controller 既有 `injectAssistantMessage(kind: 'compass')` 承接，不另建聊天路徑；④ 開口閘：answer_confidence >0.7（T2）且信念有 BeliefGate 證據（T3）；⑤ 刪 `compass/compass_tools.dart` 死碼、接 `bootBriefing()`。
- **依賴**：T2、T3。
- **驗收**：Blue 評有用率 ≥50%（10 則樣本）；`compass.speak` 事件帶 turn_id 入 event_ledger。
- **風險**：02:00-05:00 的 dream 窗口與使用者作息錯開，開口時機要走「下次開 App 時」佇列。

### T10 Agent-as-User M5 + W4/W5（4 天）
- **目標**：10 個代表性任務端到端，畫布全程可見。
- **內容**：① headless 執行器（W4 卡點）；② W4 歷史時間線、W5 toast；③ 10 任務 benchmark 走 8420 官方通道，oplog 可回放；④ `AgentLoop` 強制結束真 `return`、timeout 計數上限、mock client 下的控制流測試（`agent_loop_integration_test.dart` 從骨架變實作）。
- **依賴**：T8、T7。
- **驗收**：10/10 任務 3 輪內完成；e2e 報告在無 API key 下至少 mock 路徑全綠。
- **風險**：`hardMaxTurns=100000` 的 Hermes 模式是 Blue 拍板，改「真結束」要保留取消權而非輪數上限。

### T11 M6 第一個有靈魂版本（3 天）
- **目標**：打包、斷網、7 天。
- **內容**：① `localOnly=true` 斷網模式全路徑（EG2 18890 + Laya + E4B 18789 + K1 頭）；② 雲端率儀表（event_ledger executor 統計）；③ 修正率週報（correction_events / turns）；④ Blue 連用 7 天。
- **依賴**：T4、T5、T6、T7、T9、T10。
- **驗收**：雲端率 ≤30%；修正率三週遞減；Blue 主觀判定。
- **風險**：7 天中任一血管回退（例如 clutch 又改 provider）會讓數字作廢，T7 的回歸測試是守門。

**骨牌圖**：T0 → T1 → T2 → T3 → T9；T0 → T6 → T5；T7 → T4；T8 → T10；全部 → T11。T7、T8 可從今天並行。

## 2. 九項設計修正 D1-D9

- **D1 K1 定位改寫**：K1 是路由旗（chat mode / lite path）加「加菜」，不是守門員。文件 `K1_DECISION_GATEKEEPER_DESIGN.md §0` 的「第一道閘門」改為「第一個路由訊號」；注入產量不再是 K1 的 KPI（M1 封卷 §3 實證）。
- **D2 信心分兩種**：`k1_confidence`（要不要查）與 `answer_confidence`（答得對不對）是兩個欄位。熔斷、校準、M6 的「修正率」只吃後者。
- **D3 反應訊號必須雙向**：沒有 `accepted` 來源的系統不得熔斷。隱式接受（下一輪非糾正）是最低限度的來源。
- **D4 單一 turn_id**：五本記錄（event_ledger、causal_ledger、correction_events、belief_gate_log、circuit_breaker_log）以 turn_id 為外鍵。新增任何記錄表必帶 turn_id，否則 PR 不可 merge。
- **D5 向量空間單一真相**：`model_version` 是一等欄位，四表皆有；搜尋強制過濾；fallback 不得靜默，零向量不得入庫。換模型 = migration + 重嵌 + 頭重訓三件套，缺一不上線。
- **D6 語氣層是 App 資產不是訓練產物**：M2 編譯輸出進 `assets/` 或 companion 檔，runtime 讀；盲測必走 8420 真路徑。訓練目錄的 prompt 只是中間物。
- **D7 分流只有一個腦**：ProviderRouter 決定 = ApiService 執行；ladder 表一份；背景程序（clutch、vision、重嵌）禁改使用者 provider；`localOnly` 是 M6 的一等設定。
- **D8 8420 三方一致由測試鎖死**：route/schema/dispatch 集合相等；隱藏門清零或標 internal；GET 無副作用。新 route 不經測試不可 merge（補 `e584c387` 那種漏插的根因）。
- **D9 羅盤主動性走既有注入通道**：`injectAssistantMessage(kind: compass)` 承接，不另建聊天路徑；開口前置 = D2 的 answer_confidence + T3 的信念證據；heartbeat 結果必落 store，不落 store 的觀測不算觀測。

## 3. 十二項可復用資產

1. **InjectionPreparer 單一入口**（`injection_preparer.dart`）：線上與評測同路徑，含 failure_reason 歸因。T5 直接沿用。
2. **EventLedger hash chain v4**（`event_ledger.dart`）：append-only、meta 欄、verifyChain。T1 只加欄不改鏈。
3. **CausalLedger + EvidenceGrade + buildFeedbackSection**：四級證據與反饋注入格式可直接給 T9 的開口訊息用。
4. **K1 訓練管線**：`/k1/train` → 嵌入 → LOO-CV 0.75 門檻 → 單調落盤 → `loadHead`（`k1_bootstrapper.dart`）。T5/T6 的頭重訓零新碼。
5. **EVAL-M1 凍結題庫**（361 + CAL 78）與 `eval_m1.py`：M1.5 加題即可，兩臂比較框架現成。
6. **M2 71 條凍結範例 + 編譯器 + 盲測防污染三件套**（`fb21fe22`）：T4 只改輸出路徑與呼叫路徑。
7. **CorrectionCatcher + correction_events**（`e41f30f4`）：T2 的 corrected 來源已在。
8. **CalibrationBreaker 三態機**（`calibration_breaker.dart:47-91`）：狀態機正確，換訊號源即可用。
9. **EG2 雙 backend + Eg2ReembedService 冪等模式**（`0e503c16`、`fccc20e0`）：補 migration 與 error 欄即成熟。
10. **8420 BridgeMcpServer 43 工具 + 開光八件**（app_look / app_tap / window_map / canvas_zoom / app_permissions / window_control / tools_health / 統一 discovery）：T10 的 benchmark 通道已齊。
11. **CompassMedic 傷口機制 + compass_store 規則史**：T9 的「有證據才開口」可直接讀 pitfalls 與 wound 狀態。
12. **ContextStore / context_recall（CLM）+ AgentToolRegistry 60+ 工具 + W1-W3.5 排隊系統**：T10 的 headless 執行器站在這上面。

## 4. 兩項等待 Blue 拍板

**拍板一：M2 盲選 15 題的時機。** 建議「先 T4 接線，再盲選」。理由：今天盲選判定的 prompt 不在 App 裡（整合問題③）。若 Blue 要先盲選，結果只能算「規格有效」不能算「M2 畢業」，M2 畢業線要在 T4 後重跑一次真路徑。代價：T4 約 1.5 天。

**拍板二：EG2 重嵌入跑批要不要暫停。** 建議「讓它跑完，但在 T0 + T6 落地前，禁止任何評測或 K1 重訓以它為基礎」。理由：跑批本身冪等且不損資料（`eg2_reembed_service.dart:5-11`），暫停只會延後單一空間的到來；但跑批期間所有檢索都在混空間（整合問題④），此時做 M1.5 或頭重訓會得到不可重現的數字。代價：T0 一天內可做，T6 兩天；跑批剩 79% 以目前速率約需一至兩天，兩者接近同時完成。

附帶：進度報告問的「M3 熔斷實證輪要不要排本週」，依本計劃它是 T3 的最後一步，前置是 T1、T2。在訊號修好前跑，通過也是假陽性（整合問題①），建議不單獨排程。
