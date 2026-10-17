Write 工具不在此 session 可用，記憶落檔略過，直接交報告。

# 橋樑 App 生命體理解報告 v1

日期 2026-10-10。本尊路徑 `<HOME>/Developer/bridge_app`。讀碼範圍與未讀範圍見第五節。

## 一、生命體總覽

**一句話**：這是一個住在使用者 Mac 裡的 Flutter 生命體。每一句使用者的話都先過守門員 K1 分流，再帶著四槽記憶與因果帳本進入 AgentLoop 這顆心臟跳動的迴圈，由雲端或本地 LLM 決策、用五十多把工具動手，所有動手都記進因果帳本與事件日誌，傷口交給軍醫，反思交給夢境，而資料從不出機器除非走過主權閘門。

**文字版器官圖**

```
                    ┌──────────── 骨架：app.dart (GoRouter) → bridge_desktop_screen.dart (8151 行) ────────────┐
                    │  tabs: home / chat / canvas / project / brain / vault / system / companion / compass      │
                    └──────────────────────────────────────────┬────────────────────────────────────────────────┘
                                                               │ 皮膚：Tier → BridgeDS token（theme/）
   使用者一句話 ──► chat_controller.sendMessage() (L6974)
                        │ 插嘴 → _agentLoop.injectUserMessage()
                        ▼
                 _runAgentLoopIfNeeded() (L1682)
                   ├─ BrainContainerService.getFormattedContext()   ← 語意相關記憶
                   ├─ MemoryLayerService.buildInjectionSection()    ← L1 鐵則/L2 身分/L3 專案熱 全量
                   ├─ companion.systemPrompt（SOUL → MBTI → 角色 → 標籤 → 求真 → 紅線）
                   └─ AgentLoopPromptBuilder.build()               ← 身份+人格+工具手冊+鐵律+羅盤+夢卡
                        ▼
   ┌──────────────── 大腦：AgentLoop._runInner() (agent_loop.dart) ──────────────────┐
   │  ① _maybeFileCognitiveWound（糾正訊號 → 認知傷口）                              │
   │  ② K1Gatekeeper.classify（正則 → 線性頭 → escalate）→ need 時 HybridSearch top3 │
   │  ③ M0 InjectPipeline.enrich（semantic top20 → 四槽位 → 400 token）→ EventLedger │
   │  ④ CausalLedger.recallSimilar（因果反饋注入 user 訊息）                          │
   │  ⑤ 輕裝路徑 / 對話模式（K1=general_chat 免收工協議）                            │
   │  ⑥ for turn: drain 插嘴 → drain 軍醫藥卡 → 截斷歷史 → LLM.complete()           │
   │       → parse tool_call → D002 確認 → tool.execute()                            │
   │       → CausalLedger.record → CompassMedic 傷口/藥方 → 結果回填 messages         │
   └─────────────────────────────────────────────────────────────────────────────────┘
          │                                   │
          ▼ 血液                              ▼ 感官/手
   brain_container.db (schema v19)      AgentToolRegistry.withDefaults（50+ 工具）
   memories / agent_memories(layer)     ├─ canvas_* (MCP executor)   ├─ app_look/app_tap/app_scroll
   asset_index / event_ledger           ├─ read/patch_source_file    ├─ compass_read/seek/propose
   + compass_store.db                   ├─ delegate_subagent/batch   ├─ dream_once / swarm_* / intel_*
   + causal_ledger / time_sense.db      └─ generate_image …          └─ run_terminal / restart_app
   + sovereignty_ledger.db
          │
          ▼ 免疫
   DataPathGate（green 本機 / yellow 金鑰匙 provider / red 攔截）掛在 7 個 Dio 客戶端的 SovereigntyInterceptor
   AgentSafetyConstraints（D002 確認、付費工具閘、危險終端指令）
          │
          ▼ 心臟與離合器
   LocalModelScheduler（runChat ⇄ switching ⇄ runVision，faulted 罷手）
   BrainRevivalService（llama-server 看門狗，30s poll，死兩次救一次，10 分鐘冷卻）
   NativeAgentLoop（第二條迴圈：事件驅動 + 60s idle 兜底，bridge_desktop_screen L1706 啟動）
   MCP 8420（shelf，token 門禁，43 個 tool schema）← 外部 Hermes / 同進程 _proxyGet
```

## 二、器官逐論

### 2.1 骨架（導航殼層）

- **職責**：`main.dart` (164 行) 做視窗、tray、TrustLoop、TraceScrubber、全域熱鍵 Cmd+Shift+K、`LocalModelScheduler.start()`。`app.dart` (737 行) 用 GoRouter 定路由，`/settings` redirect 到 `/`。`bridge_desktop_screen.dart` (8151 行) 是一切入口，`case 'chat'|'canvas'|'project'|'brain'|'vault'|'system'` 在 L936 至 L952，另有 `home`/`companion`/`compass`。
- **依賴誰**：ThemeProvider、StorageService、BrainContainerService、CompassBootstrap。
- **餵養誰**：注入 MCP server 的 onAppScroll/onAppTap callbacks、啟動 NativeAgentLoop、掛 BrainRevivalService。
- **健康度**：功能齊全但單檔過肥。主對話 tab 實際掛的是 `DesktopChatPanel` (L5274)，`ChatScreen` 只在 `/chat` 路由出現。三份聊天面板副本的陷阱仍在。

### 2.2 血液（資料流與 DB）

- **職責**：`BrainDatabase` 單例開 `brain_container.db`，WAL，schema v19，sqlite_vector 擴充，四組 vector_init（memories、asset、chunk、agent_memories）。`agent_memories` 表帶 `layer` 欄，`MemoryLayerService` 定義兩域十層，L1 至 L3 有軟上限且走升降溫不刪除。`event_ledger` 表由 `EventLedger` 自建，append-only hash chain，v3 加 `input_hash`。
- **寫入鏈**：正則快車道 `MemoryStore.add`（SharedPreferences）→ `DreamBuffer` 積批 10 則或閒置 5 分鐘 → `SmartMemoryExtractor.extractBatch`（LLM）→ `writeToBrainContainer`。`MemoryLayerService.write` 直接寫 agent_memories。
- **讀取鏈**：`HybridSearchService.search` 三模式。hybrid 是 FTS 與語意各跑再 RRF 融合，LLM rerank 與 synthesis 都關閉，五因素重排收尾。memories 與 agent_memories 兩表都掃。
- **分散的小帳本**：compass_store.db、causal_ledger、time_sense.db、sovereignty_ledger.db 各自獨立 SQLite，都在 Application Support。
- **健康度**：主幹穩，但記憶有三套並存的真相（SharedPreferences 字串清單、memories 表、agent_memories 表），M0 的 InjectPipeline 只吃 HybridSearch 的 memoryHits，槽位判定靠 content 前綴 `[type]` 正則，舊表記憶沒有 type 前綴時只能靠標題關鍵字退路，否則被丟棄。

### 2.3 大腦（決策鏈）

- **AgentLoop**（1564 行，全讀）：Hermes 模式，無輪數上限（hardMaxTurns 100000），完成訊號唯一是 `[[TASK_DONE]]`。防護層豐富：空回應兩次誠實報錯、reasoning 洩漏回收、截斷重試三次、同工具連呼五次 nudge 十次強制結束、A→B 交替 pattern 偵測、截圖 eviction、生圖短路。
- **K1Gatekeeper**：三層設計，但正式路徑只有兩層在跑。`loadHead` 全 repo 只在 `test/k1_gatekeeper_test.dart:96` 被呼叫，lib/ 內零呼叫，`DecisionStore` 也只在測試建構。意思是：正式 App 中，命中正則就 need（conf 1.0），沒命中一律 escalate（conf 0.0）。`CompassSelfGauge` 的紅燈「K1 escalate 率過高，頭沒訓練」描述的正是這個狀態。
- **M0 注入**：`InjectPipeline.enrich` 走 semantic top20 → `SlotFilter`（慣例 2 偏好 1 信念 1 近期 1）→ `BudgetController`（400 token，相似度地板 0.55，每槽保一）。結果與 K1 命中、因果反饋三者都附在 user 訊息尾端。`EventLedger.appendTurn` 每輪落盤，但 `output` 欄位永遠沒填（appendTurn 呼叫時未傳），`appendReaction` 在 lib/ 內零呼叫。M3 回饋閉環的資料源目前只有半邊。
- **因果引擎**：`CausalLedger.record` 在工具咽喉點記帳並判證據等級（0 推測 1 觀測 2 干預 3 反事實）。`recallSimilar` 回灌。`CausalForkService` 做畫布快照分叉。`TimeSenseService` 供「相遇第 N 天」。
- **LLM 客戶端**：`ProductionAgentLoopLLMClient._resolveModel` 每次呼叫動態解析：使用者鎖定 provider 優先，否則品牌階梯從最便宜起步。本地模式超時放寬到 300 秒。
- **健康度**：大腦結構完整且防呆經驗豐富，但「自訓練守門員」這條神經實際斷線，決策層目前是純正則加 LLM。

### 2.4 感官（MCP 8420 與本地模型）

- **MCP**：shelf server 綁 localhost:8420，token 門禁 fail-close，tools/list 內 43 個 schema（我用 `'name':` 計數，app_look/app_tap 各出現兩次，去重後約 41 個獨立工具名）。同進程 `_proxyGet` 直呼 router。`tools_health` 追蹤從未 dispatch 的工具。
- **本地模型**：Swift 端 `startLocalRuntimeServer` (L1505) spawn llama-server 18789，Dart 端 `_withBridgeRuntimeHealth` (L514) 健康輪詢。EmbeddingGemma 300M 走 flutter_gemma 在進程內，不搶 18789。
- **內建感官**：`app_senses_tools.dart` 讓內建 loop 直呼 MCP callbacks，不走 HTTP。
- **健康度**：開光 v0.4 系列把眼手接齊了。隱藏門仍有 galaxy_* 家族只有 HTTP 直連。

### 2.5 心臟（排程與離合器）

- **LocalModelScheduler**（全讀）：四態機，30 秒評估，閒置 90 秒且有待辨識才切 vision，切換等安全點，失敗一次罷手。
- **BrainRevivalService**：30 秒 poll，連續兩次失敗判死，救一次後冷卻 10 分鐘，使用者手動關閉時不救，閒置 10 分鐘自動卸載。
- **NativeAgentLoop**：第二條獨立 AgentLoop 實例，事件驅動加 60 秒 idle 兜底加任務信箱，有 checkpoint 恢復。
- **CompassHeartbeat**：端點、pgrep、mtime 三源探針，60 秒一輪。
- **排程 W 線**：`services/semicanvas/schedule_engine.dart`、`app_schedule_engine.dart`、`schedule_registry.dart` 存在，未讀內容。
- **健康度**：三個定時器各自獨立（30s、30s、60s）加 DreamBuffer 的 5 分鐘閒置計時，沒有統一節律器。這正是 SEMI_SOUL_ARCHITECTURE §4 說的松果體缺口。

### 2.6 皮膚（UI 與 Tier）

- **職責**：`Tier` 是 const class 不是 enum（tier.dart L21，註解仍寫「Tier enum」）。`bridge_ds_tokens.dart` 自述為 85 個 BridgeDS token 的分組索引，實際定義在 `bridge_design_system.dart`。
- **健康度**：Tier 系統有防呆，但 token 數字文件與程式自述不一致（見第三節）。

### 2.7 免疫（安全閘門）

- **DataPathGate**（全讀）：確定性分級，紅燈先記帳再 throw，環形 90 天。白名單來源是 ProviderRegistry 官方網域、BillingModes 全部 URL、使用者 gateway_url。`SovereigntyInterceptor` 掛在 api_service、smart_memory_extractor、vision_embedding_pipeline、openai_visual_review_adapter、delegate_subagent、delegate_batch 六處加本體一處。
- **AgentSafetyConstraints**（全讀）：確認清單含 canvas_execute、canvas_remove、clear_canvas、restart_app、generate_image；機器輪次禁付費工具；危險終端 pattern；interrupt-safe 工具集。
- **MemoryGuard**：記憶寫入前掃 prompt injection。
- **MCP token 門禁**：fail-close。
- **健康度**：這是全身最紮實的器官。唯一缺口是 Dio 之外的 HTTP 路徑（例如 `BrainRevivalService` 自建 Dio 打本機、`CompassHeartbeat` 用 HttpClient）不過閘，但目標都是 localhost。

## 三、文件 vs 實況差異清單

| # | 文件位置 | 文件說 | 實況 | 嚴重度 |
|---|---|---|---|---|
| 1 | AGENTS.md「專案規模索引」與 subagent 驗證指令 | chat_screen.dart 約 8765 行，行數不符就停 | 實為 2052 行。照此指令派工的 subagent 會誤判本尊為舊副本而停工 | 高 |
| 2 | AGENTS.md「尚未完成」節 | `lib/core/responsive.dart`、`adaptive_scaffold.dart`、`adaptive_card.dart`、`spacing.dart` 全部不存在 | 四個檔案都存在 | 中 |
| 3 | AGENTS.md「已知死代碼」與地圖 §9 | `_showModeSelector`、`_showMemoryOverlay` 是死代碼 | 兩者在 chat_screen.dart 已不存在。`_showSkillPanel` 現為 bool 欄位且 L1478 有使用，不是死方法 | 低 |
| 4 | 地圖 L10 | 524 個 Dart 檔 | lib/ 下約 687 個（438 services + 246 其他 + 3 根） | 低 |
| 5 | 地圖 L100、L105 | main.dart 36 行、app.dart 605 行 | 164 行、737 行 | 低 |
| 6 | 地圖 L120、L137 | bridge_desktop_screen 6102 行 | 8151 行 | 低 |
| 7 | 地圖 L175 | chat_controller 約 7847 行 | 8543 行 | 低 |
| 8 | 地圖 L31、L178 | `sendMessage()` L6355，呼叫 ApiService L7372 | L6974，ApiService.sendMessage 呼叫在 L8064 | 中 |
| 9 | 地圖 L25、L26、L27、L30 | api_service `sendMessage` L186、`completeWithReceipt` L709、`completeWithMessagesRaw` L1306、`_streamChatCompletion` L848 | L259、L801、L1412、L979 | 中 |
| 10 | 地圖 L22、L24 | `_withBridgeRuntimeHealth` L476、`resolveShortModelName` L692 | L514；`resolveShortModelName` 在該檔 grep 不到定義，位置未驗證 | 中 |
| 11 | 地圖 L360、§5.2 整表 | MainFlutterWindow.swift 約 2741 行；startLocalRuntimeServer 1401、restoreLocalRuntimeState 2103、isPort18789Alive 2128、configure(panel) 2321、applyRuntimeOnly 2235、applyLocalRuntime 506、preflight 1911、removeQuarantine 1934、minSize L47 | 3746 行；1505、2362、2387、2596、2502、555、2170、2193、L55 | 中 |
| 12 | 地圖 L19、§2.4 | 模型名在 message_bubble L542、canvas_chat_panel L859、desktop_chat_panel L765 與 L910 | L609、L1076、L1225 與 L1393 | 低 |
| 13 | 地圖 L32 | `detectCapabilityGap` L4547 | L4624；`preEmptiveCapabilityGapEnabled` 在 L7316 | 低 |
| 14 | 地圖 L66 | companion.dart `systemPrompt` L460、`_personaCluesPrompt` L507；注入點 chat_controller L7248 | L466、L548；注入點 L7927 且 H3 的 soulMd 已插在最前段，地圖未記 | 中 |
| 15 | 地圖 L68 | `_buildCompanionSubPage('create')` L2700 至 2710 | 該方法名在 bridge_desktop_screen.dart grep 不到 | 中 |
| 16 | 地圖 L122 | tab 0 對話 → chat_screen.dart | 主畫面對話 tab 掛 DesktopChatPanel (L5274)；ChatScreen 只在 /chat 路由 | 中 |
| 17 | 地圖 L44、AGENTS.md | 33 個 BridgeDSColors token | bridge_ds_tokens.dart L4 自述 85 個；33 是 Tier 數量 | 低 |
| 18 | 地圖 L139、L267 | desktop_homepage_screen.dart 首頁 | app.dart L267 註明該路由 2026-10-06 封存至 `_archived/` | 低 |
| 19 | 地圖 L610、L619 | MCP tools 41 與 43 | tools/list 內 43 個 schema 項、約 41 個獨立名（app_look/app_tap 重複登記） | 低 |
| 20 | K1_DECISION_GATEKEEPER_DESIGN 與 agent_loop 註解「三層閘門」 | 規則 → 線性頭 → escalate | 線性頭正式環境從未載入（`loadHead` 只在測試） | 高 |
| 21 | WEAVE_MAP_V2 M0 規格 | 事件日誌每輪記「輸出／使者反應」 | `appendTurn` 呼叫未傳 output；`appendReaction` 無任何生產呼叫處 | 高 |
| 22 | 地圖整體「最後更新 2026-08-14」 | 之後只在檔尾附加章節 | 快速導航表與 §1 至 §5 的行號全面過期 | 中 |

## 四、規劃 M2 至 M6 需要的認知前提

**M2 語氣層要接哪條神經**
- 人格目前由三段拼接：`companion.systemPrompt`（SOUL → MBTI → 角色 → 標籤 → 8 欄 clues → 求真 → 紅線）、`PersonaInferenceService` 人格卡（僅非本地）、`AgentLoopPromptBuilder` 的「你的人格覆蓋前述一切」段。本地模式走 `_buildLocalPrompt`，人格卡與多數段落被剪。
- 語氣層的落點應是 `companion.systemPrompt` 的 soulClause 之後、basePrompt 之前，因為那是唯一在雲端與本地兩條 prompt 路徑都會出現的位置。要先驗證 `_buildLocalPrompt` 確實帶 companionPersona（未讀）。
- 「換供應商風格變化 ≤10%」的量測前提：`EventLedger` 要開始記 output 與 executor 的模型名，目前 output 為空。

**M3 回饋閉環要動哪塊肌肉**
- 反應通道缺口：`appendReaction` 沒有 UI 入口。糾正訊號目前走 `_maybeFileCognitiveWound` 的詞表，產出是羅盤傷口不是 ledger reaction。M3 第一刀應是把這個詞表命中同時寫成 `appendReaction(turnId, 'corrected')`，而 turnId 現在是 `turn_<ms>` 沒有回傳到 chat_controller，需要把 turn_id 帶回 Message metadata。
- 校準熔斷的資料源 `onlineCalibration()` 已寫好，但它 join 的 confidence 來自 K1，而 K1 正式環境只有 1.0 與 0.0 兩個值。沒有線性頭上線，ECE 這個指標沒有意義。
- 信念寫入證據門檻：L4 在 `MemoryLayerService` 是「環境」層，與 WEAVE_MAP 的「L4 ≥3 次一致證據」語意對應需要確認是指 belief 槽還是 layer L4。

**M4 主動性要動哪塊肌肉**
- 「對使者說話」通道已存在：`GlobalNoticeChannel.push` 入 compass_meta 佇列，UI 起來 `claimPending`。夢境 `DreamService.runDream` 已是規則引擎版，議程三源來自 `CompassSelfGauge`。
- 但觸發器是 `DreamOnceTool`（agent 自己呼叫）與 `dream_scheduler.dart`（未讀）。「每日 ≤3 則、信心 >0.7」這兩個閘需要一個節律器，目前四個獨立計時器沒有共同時鐘。這就是 S2 松果體，而 S2 開工閘是 W5 加 S1 驗收。

**M5 與 M6 的大腦手術風險**
- 兩條 AgentLoop 實例（chat_controller 與 NativeAgentLoop）共用 K1、M0、CausalLedger 單例但各自持有 `_lastK1Decision`、`_medicFailStreak`。語氣層與主動性如果以單例狀態實作，會被兩條迴圈互相覆寫。
- `EventLedger` 單寫者假設在同 isolate 內成立，但兩條迴圈若同時 appendTurn，hash chain 的 `_lastHash` 讀寫之間沒有鎖，理論上可斷鏈。M3 上線前要加測試。
- 斷網模式（M6）：K1 線性頭依賴 EmbeddingService，InjectPipeline 依賴 semantic 搜尋，兩者都要 EmbeddingGemma 在進程內可用。本地 ctx 4096 已逼得 prompt 走輕裝，四槽注入 400 token 加 L1 至 L3 全量注入加歷史 2200 字是否擠得下，需要實測一次。

**最重要的前提**：WEAVE_MAP 把 M1 畢業標準建立在「注入條件下的 K1」。而今天 K1 的線性頭根本沒在線上跑。M1 的量測協定若不先把 `DecisionStore.load → K1Gatekeeper.loadHead` 接進啟動鏈，量到的會是正則層的數字。

## 五、誠實邊界

**全文讀完**：APP_ARCHITECTURE_MAP.md、WEAVE_MAP_V2.md、PHASE_LINES_MAP.md、SEMI_S0_BASELINE_REPORT.md、main.dart、agent_loop.dart、k1_gatekeeper.dart、decision_head.dart、inject_pipeline.dart、slot_filter.dart、budget_controller.dart、event_ledger.dart、local_model_scheduler.dart、data_path_gate.dart、agent_safety.dart、compass_bootstrap.dart、global_notice_channel.dart 前 70 行。

**讀了頭段或關鍵段**：brain_database.dart、brain_schema_sql.dart、brain_container_service.dart、hybrid_search_service.dart（前 420 行）、causal_ledger_service.dart、causal_fork_service.dart、time_sense_service.dart、bridge_mcp_server.dart（前 200 行加工具名 grep）、compass_medic.dart、compass_store.dart、compass_heartbeat.dart、compass_self_gauge.dart、memory_layer_service.dart、smart_memory_extractor.dart、dream_buffer.dart、dream_service.dart、brain_revival_service.dart、memory_store.dart、agent_tool_registry.dart、agent_loop_prompt_builder.dart、production_agent_loop_llm_client.dart、native_agent_loop.dart、companion.dart systemPrompt 段、chat_controller 的 L1420 至 L1930、L6974 至 L7053、L7660 至 L7960、bridge_desktop_screen L1700 至 L1780、app.dart 路由段、SEMI_SOUL_ARCHITECTURE.md 前 120 行。

**完全沒讀**：chat_screen.dart 本體（只看 import 與 grep）、desktop_chat_panel.dart、canvas 整個 v2 目錄、brain_pipeline（Transurfing 分析管線）、voice 與 tts、collab 蜂群、semicanvas 排程引擎、schedule_registry、life_tree_store、dream_scheduler、api_service 本體、MainFlutterWindow.swift 本體（只 grep 函式行號）、所有 test 內容、docs 中其餘 60 餘份文件、`.hermes/plans/`。

**抽樣推斷而非驗證的結論**：主對話 tab 掛 DesktopChatPanel（只憑一處 grep）；MCP 獨立工具數約 41（計數方式粗糙）；Tier 數量 33 未逐一數；`resolveShortModelName` 定義位置未找到；`_buildLocalPrompt` 是否帶人格未讀；兩條 AgentLoop 同時 appendTurn 的斷鏈風險是推理，沒有實測；DataPathGate 之外的 HTTP 路徑是否全為 localhost 只看了兩個檔。

**可直接驗證的高嚴重度發現**：
```
grep -rn "loadHead(" lib/        # 應為零命中
grep -rn "appendReaction(" lib/  # 應只有 event_ledger.dart 定義處
wc -l lib/screens/chat_screen.dart   # 2052
```
EXIT=$?
