# 橋樑 App 架構地圖 (Architecture Map)

> **使用規則：每次修改或修復程式前，必須先讀此地圖。**
> **修改後必須同步更新此地圖**——行號變了要改、新增檔案要加、新陷阱要記錄。
> 未來手機版初稿完成後，手機版地圖也要加入本檔案。
> 如果地圖缺少你要改的功能，先 grep 確認位置，**改完後更新此地圖**。
> 地圖过期 = 下次改錯地方。保持更新是所有人的責任。

> 最後更新：2026-08-14 by 教練 Agent
> 專案規模：524 個 Dart 檔案，~19.5 萬行

---

## 0. 快速導航 — 「想改 X → 去哪改」

| 我想改… | 去這個檔案 | 備註 |
|---|---|---|
| 對話泡泡內容/樣式 | `screens/chat/widgets/message_bubble.dart` | 主對話視窗 |
| 對話泡泡模型名稱 | `message_bubble.dart` L542 + `canvas_chat_panel.dart` L859 + `desktop_chat_panel.dart` L765, L910 | **三個地方都要改**，用 `resolveShortModelName()` |
| 視窗最小尺寸 | `main.dart` L21 (`window_manager`) + `MainFlutterWindow.swift` L47 (`self.minSize`) | **兩端都要改**，Dart 端會覆蓋 Swift |
| 本地模型 server 啟動 | `MainFlutterWindow.swift` `startLocalRuntimeServer()` L1401 | spawn llama-server 的地方 |
| 本地模型健康檢查 | `local_model_runtime_service.dart` `_withBridgeRuntimeHealth()` L476 | Dart 端輪詢 |
| 本地模型狀態恢復 | `MainFlutterWindow.swift` `restoreLocalRuntimeState()` L2103 | APP 啟動時讀 `runtime-state.json` |
| 模型名稱精簡邏輯 | `local_model_runtime_service.dart` `resolveShortModelName()` L692 | 所有模型名解析的源頭 |
| API 呼叫（對話） | `api_service.dart` `sendMessage()` L186 | non-streaming，`stream: false` |
| API 呼叫（輕量） | `api_service.dart` `completeWithReceipt()` L709 | 定義在 L709（不是 L701 那是呼叫處） |
| API 多輪裸送（cache 工程專用） | `api_service.dart` `completeWithMessagesRaw()` L1306 | 小葵 2026-09-20：保持 messages 陣列結構直送，prefix 凍結 → prompt cache 命中率提升。不收 usage（計程車表 9/20 暫不上，待 L3 自我校準復活） |
| 品牌階梯路由 | `brand_ladder_router.dart` | 小葵 2026-09-20：default 模式從品牌最便宜起步，信號（連敗≥2）升一階、≥5 直接旗艦；user_locked 模式不動。**廣播事件 stream**：`events` StreamController + `recentEvents()`，UI 訂閱即可看到「📈 階梯起點/升一階/直衝旗艦/你鎖定了」狀態彈出 |
| Agent Loop LLM 客戶端 | `agent_loop/production_agent_loop_llm_client.dart` `complete()` L150 | 小葵 2026-09-20 改：不再壓扁歷史為單條 user message（破壞 cache prefix），改用 `completeWithMessagesRaw` 直送多輪 array |
| API retry 邏輯 | `api_service.dart` `_streamChatCompletion()` L848 | 定義在 L848；L778/782 是呼叫處 |
| 發送訊息流程 | `chat_controller.dart` `sendMessage()` L6355（入口），L7372（呼叫 ApiService） | 組 Message、呼叫 ApiService |
| 能力顧問（Capability Advisor） | `chat_controller.dart` L7098（kill switch）+ `services/capability_advisor_service.dart` | **2026-09-15 翻轉為後置救援**：前置攔截已關閉（`preEmptiveCapabilityGapEnabled=false`），只有真執行真失敗（needsProvider）才啟動；搜尋改本地優先三層（內建→已開通→外部標主權等級）。攔截詞表 `detectCapabilityGap` L4547 保留供考古，畫布（v214）與記憶請求（09-15）的豁免都在裡面 |
| 頂部導航列 | `bridge_desktop_screen.dart` `_buildTopBar()` | 5 tab + 大腦圖譜/羅盤/懸浮窗/深色/API 按鈕 |
| 2D 大腦圖譜 | **已退役（2026-09-07 Blue 令）** | `brain_canvas.dart`/`infinite_canvas.dart` 已刪除；羅盤 2D 規則標 retired；3D 星系不受影響 |
| 羅盤系統（人機共視） | `screens/compass_screen.dart` + `services/compass/` | 器官地圖 + 規則中心（雙層所有權 + 白名單制） |
| 規則層（顯示規則） | `services/compass/compass_store.dart` | 唯一真相源；visual 即時生效/behavioral 需人 apply |
| 軍醫（傷口系統） | `services/agent_loop/compass_medic.dart` | 工具失敗→【pending·傷口立案】→自癒藥方；**認知傷口（2026-10-05 開案）**：糾正訊號（`agent_loop.dart` `_maybeFileCognitiveWound`）→【pending·認知傷口】→紅燈（`compass_self_gauge.dart` cognitiveWounds）→夢境議程；痊癒=誠實邊界（她主動說看不見） |
| 模型選擇器 | `widgets/chat/agent_model_selector.dart` | top bar 裡的 provider 切換 |
| 懸浮夥伴視窗 | `MainFlutterWindow.swift` `configure(panel:state:)` + `floating_companion.dart` | NSPanel，Swift 原生視窗 |
| 懸浮窗縮放被重置 | `MainFlutterWindow.swift` `syncRuntime` handler → 用 `applyRuntimeOnly()` | 不要用 `apply()` 會重設 size |
| APP 主畫面骨架 | `bridge_desktop_screen.dart` | 所有 tab 路由、首頁、夥伴大廳 |
| Provider 設定（API key） | `widgets/settings/brain_api_config_card.dart` | 在系統設定頁 |
| SharedPreferences key | `storage_service.dart` | 所有持久化資料的讀寫 |
| 設計 token（顏色） | `theme/bridge_design_system.dart` + `theme/bridge_ds_tokens.dart` | 33 個 BridgeDSColors token |
| Tier 系統 | `theme/tier.dart` + `theme/tier_registry.dart` + `theme/tier_style.dart` | widget → tier → color 三層 |
| 載入畫面/首啟 | `screens/desktop_welcome_screen.dart` → `first_summon_screen.dart` | 第一次使用流程 |
| 語音輸入 | `screens/chat/handlers/voice_speech_handler.dart` + `services/voice/` | Voice AI 完整模組 |
| TTS 語音合成 | `screens/chat/handlers/chat_tts_handler.dart` + `services/tts/` | 文字轉語音 |
| 畫布（無限畫布） | `widgets/canvas/v2/canvas_v2_workspace.dart` | V2 畫布主畫面 |
| 畫布聊天面板 | `widgets/canvas/canvas_chat_panel.dart` | 畫布右側對話框 |
| 大腦容器（知識圖譜） | `services/brain_container/` + `screens/brain_container_screen.dart` | 向量記憶 +圖譜 |
| 向量資料庫頁面 | `screens/vault_screen.dart` | Vault tab |
| **搜尋引擎（任何入口）** | `services/vault/vault_search_facade.dart` | **單一真相**——全域搜尋/vault/未來新入口都打它；禁另建搜尋路徑（羅盤規則 `search.singleEngine`）。fullText=memories(LIKE)∥assets(FTS)；hybrid 每查詢跑嵌入推理=慢，只留使用者明確切換 |
| 全域搜尋（面板+服務） | `widgets/search/receipts_search_overlay.dart` + `services/search/receipts_search_service.dart` | 常駐 Overlay（QuickAssistant 同款）；大腦域走 facade；四動作 vault/galaxy/畫布/對話 |
| 專案門系統 | `screens/desktop/project_door_page.dart` + `services/project_door_store.dart` | kanban + 專案管理 |
| SemiDAO 審查 | `services/semi_dao/` + `services/semi_dao_review_store.dart` | IPFS + 審查流程 |
| Agent Loop（自主循環） | `services/agent_loop/agent_loop.dart` | AI 自主任務循環 |
| Agent 工具註冊 | `services/agent_loop/agent_tool_registry.dart` | 所有 agent 可用工具 |
| MCP Server | `services/bridge_mcp_server.dart` | 畫布共視 MCP |
| 系統列圖示 | `services/system/tray_service.dart` | tray icon |
| macOS 原生通道 | `MainFlutterWindow.swift` | 所有 Swift↔Dart 橋接 |
| BackgroundRemover（去背） | `services/background_remover.dart` | 全域純白清除 |
| 夥伴狀態圖 | `widgets/companion_presence_layer.dart` | 懸浮窗裡的頭像顯示 |
| 夥伴清單/建立 | `screens/companion_list_screen.dart` + `companion_create_screen.dart` | 夥伴管理 |
| 夥伴設定文字快速存檔 | `companion_create_screen.dart` `_confirmCandidate()` L4797 | 編輯模式下只改文字不走生成，直接 `copyWith` 存檔 |
| 夥伴人格 → Agent 行為 | `companion.dart` `systemPrompt` getter L460 + `_personaCluesPrompt` L507 | 10 個設定欄位中 8 個非空者注入 system prompt；注入點在 `chat_controller.dart` L7248 `_activeCompanion?.systemPrompt` |
| 夥伴設定文字欄位 onChanged | `companion_create_screen.dart` L2059 | 編輯模式保留 candidate 不清空；新建模式清 candidate 強制重新生成 |
| 夥伴設定頁面入口 | `bridge_desktop_screen.dart` L2700-2710 `_buildCompanionSubPage('create')` | 載入 `CompanionCreateScreen(editingCompanionId: id)` |
| 夥伴館列表 | `bridge_desktop_screen.dart` L2800+ `_buildCompanionHall()` | 夥伴卡片列表 + 編輯/語音入口 |
| 夥伴控制中心 | `screens/companion_control_center_screen.dart` | 夥伴詳情（MBTI、能力、記憶） |
| 夥伴外觀設定 | `screens/companion_appearance_screen.dart` | 外觀設定頁 |
| 夥伴靈魂設定 | `screens/companion_soul_screen.dart` | 靈魂/性格設定 |
| 語音設定 | `screens/companion_settings/voice_settings_screen.dart` | 夥伴語音 |
| 密碼鎖畫面 | `screens/lock_screen.dart` | APP 鎖定畫面 |
| 盲盒系統 | `screens/blind_box_screen.dart` | 驚喜盲盒 |
| 成就系統 | `screens/achievement_collection_screen.dart` | 成就收集 |
| 金鑰匙系統 | `screens/golden_keys_screen.dart` | 金鑰匙 |
| 召喚精靈 | `screens/summon_screen.dart` + `desktop_summon_screen.dart` | 夥伴生成引擎 |
| 首次召喚引導 | `screens/first_summon_screen.dart` | 第一次使用的引導流程 |
| SemiDAO 審查（即將上線） | `screens/semi_dao_review_coming_soon_screen.dart` | placeholder 頁面 |
| 桌面首頁 | `screens/desktop_homepage_screen.dart` | 精選動態首頁 |
| 桌面召喚 | `screens/desktop_summon_screen.dart` | 桌面版夥伴生成（完整版，5884行） |
| 桌面歡迎 | `screens/desktop_welcome_screen.dart` | 首次歡迎 + provider 引導 |
| 檔案總管 | `screens/desktop/desktop_file_page.dart` | 桌面檔案瀏覽 |
| 專案門詳情 | `screens/desktop/project_door_detail.dart` | 專案門卡片詳情 |
| 專案門看板 | `screens/desktop/project_door_kanban.dart` | kanban 面板 |
| 專案門頁面 | `screens/desktop/project_door_page.dart` | 專案門主頁 |
| 專案關係圖 | `screens/desktop/project_relation_graph.dart` | 專案關係視覺化 |
| 還原歷史 | `screens/desktop/system_pages/restore_history_page.dart` | 系統還原歷史 |
| 主題設定 | `screens/desktop/settings/theme_settings_page.dart` | 主題包切換 |
| 記憶系統 | `services/memory_store.dart` + `services/memory_recall_service.dart` | 長期記憶 |
| Bridge Action 執行 | `services/bridge_action_executor.dart` | 動作卡片執行 |
| 預審/Vision 審查 | `services/semi_dao_visual_review_service.dart` + `openai_visual_review_adapter.dart` | 圖片安全審查 prompt 在 adapter 的 `_systemPrompt()` |

---

## 1. 專案入口與啟動鏈

```
main.dart (36行)
  └─ window_manager 初始化（視窗大小、minSize）
  └─ TrayService.init()（系統列圖示）
  └─ runApp(BridgeApp())

app.dart (605行)
  └─ BridgeApp：路由表、全域主題、生命週期
  └─ 監聯 window_manager 事件
  └─ 初始化各 Service（ProviderRegistry、CompanionStore、BrainContainer 等）
```

**啟動順序：** `main()` → `window_manager` → `TrayService` → `BridgeApp` → 路由 → `BridgeDesktopScreen`

---

## 2. 畫面結構（screens/）

### 2.1 主畫面骨架

```
bridge_desktop_screen.dart (6102行) — APP 的一切入口
  ├─ _buildTopBar() — 頂部 6 tab 導航
  │   tab 0: 對話 → chat_screen.dart
  │   tab 1: 畫布 → canvas_v2_workspace.dart
  │   tab 2: 專案 → project_door_page.dart
  │   tab 3: 大腦 → brain_container_screen.dart
  │   tab 4: 向量資料庫 → vault_screen.dart
  │   tab 5: 系統 → 系統設定頁面群
  ├─ 首頁模式 (_isHomepage=true)
  ├─ 夥伴大廳 (_isCompanionHall=true)
  └─ 右側：深色/懸浮窗/API 儀表板
```

### 2.2 畫面清單（按行數排序）

| 檔案 | 行數 | 職責 |
|---|---|---|
| `bridge_desktop_screen.dart` | 6102 | 主畫面骨架、tab 路由、首頁、夥伴大廳 |
| `chat_screen.dart` | ~8765 | 對話主畫面（最大檔案） |
| `desktop_homepage_screen.dart` | — | 首頁（精選動態） |
| `brain_container_screen.dart` | 665 | 大腦容器知識圖譜 |
| `desktop_welcome_screen.dart` | — | 首次歡迎畫面 |
| `vault_screen.dart` | — | 向量資料庫 tab |
| `capability_center_screen.dart` | 567 | 金鑰匙系統 |
| `companion_list_screen.dart` | — | 夥伴清單 |
| `companion_create_screen.dart` | — | 夥伴建立 |
| `lock_screen.dart` | — | 密碼鎖畫面 |
| `first_summon_screen.dart` | — | 第一次召喚夥伴 |

### 2.3 系統設定子頁面

| 檔案 | 職責 |
|---|---|
| `desktop/settings/semidao_settings_page.dart` | SemiDAO 三項設定 |
| `desktop/settings/theme_settings_page.dart` | 主題設定 |
| `desktop/system_pages/restore_history_page.dart` | 還原歷史 |
| `widgets/settings/brain_api_config_card.dart` | 主腦 API 設定 |
| `widgets/settings/db_location_card.dart` | 資料庫路徑 |

### 2.4 桌面聊天面板（三個版本，改一個要全改）

| 檔案 | 用途 | 改模型名要動 |
|---|---|---|
| `screens/chat/widgets/message_bubble.dart` | 主對話視窗訊息泡泡 | ✅ L540 |
| `widgets/canvas/canvas_chat_panel.dart` | 畫布右側聊天面板 | ✅ L858 |
| `screens/desktop/desktop_chat_panel.dart` | 桌面獨立聊天面板 | ✅ L764 + L909 |

> ⚠️ **這三個檔案是「同一個功能的三個副本」**。任何訊息顯示相關的改動都要三個全改。

---

## 3. 控制器（controllers/）

| 檔案 | 行數 | 職責 |
|---|---|---|
| `chat_controller.dart` | ~7847 | 對話核心控制器：發送訊息、管理對話、意圖分類、記憶注入、回應處理 |

**關鍵方法：**
- `sendMessage()` L6355 — 發送訊息入口
- `ApiService.sendMessage()` L7372 — 實際 API 呼叫
- `Message(model: response.model)` L7395 — 組裝回應訊息

---

## 4. 服務層（services/）

### 4.1 API 與模型

| 檔案 | 行數 | 職責 |
|---|---|---|
| `api_service.dart` | 1712 | 所有 API 呼叫的入口；sendMessage、complete、streaming |
| `api_usage_tracker.dart` | 244 | API 額度追蹤 singleton |
| `local_model_runtime_service.dart` | 720 | 本地模型管理：啟動、健康檢查、模型名稱解析 |
| `local_model_catalog_service.dart` | — | 本地模型目錄（推薦模型清單） |
| `provider_registry.dart` | — | Provider singleton，allMetas() 同步 |
| `provider_router.dart` | — | Provider 路由（Agent Loop 用） |
| `storage_service.dart` | — | SharedPreferences 封裝（所有持久化） |
| `context_compressor.dart` | — | 對話壓縮 |

**API 呼叫鏈：**
```
ChatController.sendMessage()
  └─ ApiService.sendMessage() L186
      ├─ _defaultModelFor(provider) L1264 — 選模型
      ├─ ContextCompressor — 壓縮歷史
      ├─ Dio.post('/chat/completions', stream:false) L337
      ├─ ChatResponse.fromJson(response.data) L345
      │   └─ resolveShortModelName(json['model']) L1667 — 模型名解析
      └─ return ChatResponse(model: ..., content: ...)
  └─ Message(model: response.model) L7395
      └─ 泡泡顯示：resolveShortModelName(msg.model) — 再解析一次（保險）
```

### 4.2 本地模型（llama-server）

**啟動鏈：**
```
APP 啟動
  └─ Flutter 端呼叫 MethodChannel("bridge_desktop_shell") action:"status"
      └─ Swift: applyLocalRuntimeAction(action:"status")
          └─ restoreLocalRuntimeState() L2120
              ├─ 讀 runtime-state.json
              ├─ 如果 phase=running → isPort18789Alive() socket 檢查
              │   └─ 如果 port 死了 → 降級為 installed
              └─ 回傳狀態給 Flutter

用戶點「啟動」或 auto-start
  └─ action:"startServer"
      └─ startLocalRuntimeServer(modelId:) L1401
          ├─ removeQuarantineFromBin() — 移除 quarantine
          ├─ localRuntimePreflight() — 找 llama-server binary + model
          ├─ Process.run(llama-server, -m model --port 18789 -ngl 99 ...)
          │   ├─ stdout/stderr → log 檔案（不用 Pipe！）
          │   └─ DYLD_LIBRARY_PATH = bin dir
          └─ 更新 runtime-state.json

健康檢查（Dart 端）
  └─ LocalModelRuntimeService._withBridgeRuntimeHealth() L476
      └─ GET http://127.0.0.1:18789/v1/models
      └─ 最多重試 8 次，每次間隔 3 秒
```

**關鍵檔案：**
| 檔案 | 職責 |
|---|---|
| `MainFlutterWindow.swift` L1401 | `startLocalRuntimeServer()` — spawn |
| `MainFlutterWindow.swift` L2103 | `restoreLocalRuntimeState()` — 啟動時恢復 |
| `local_model_runtime_service.dart` | Dart 端管理 + 健康檢查 |
| `runtime-state.json` | 持久化狀態（phase, modelId, running） |

**runtime-state.json 位置：**
```
~/Library/Application Support/Bridge/LocalRuntime/runtime-state.json
```

**自動離合器（2026-10-01 新增，Blue 拍板）：**
```
雙角色槽：夥伴模型（聊天+任務）/ 辨識模型（照片嵌入）
  ├─ 設定處：模型下載頁「角色配置」（local_llm_runtime_card.dart）
  ├─ 持久化：StorageService local_companion_model / local_vision_model
  └─ 未設辨識槽 → 行為退回現狀（零強迫）

狀態機（runChat → switching → runVision，faulted 罷手）：
  ├─ 核心：lib/services/local_model_scheduler.dart（LocalModelScheduler 單例）
  ├─ App 啟動掛載：main.dart → LocalModelScheduler.instance.start()
  ├─ 聊天優先權：AgentLoop.run() 開跑 → markUserActivity()
  │   └─ 辨識模式中 → 等安全點（嵌入 item 邊界）切回夥伴
  ├─ 安全點標記：vision_embedding_pipeline.processPendingVisionAssets()
  │   進場 set visionJobActive=true / 完工 set false
  ├─ pending 計數：_fetchPendingVisionAssets() → updatePendingVisionCount()
  └─ 失敗一次罷手回手動（09-29 鐵律）——UI 故障區塊可手動重試

UI 顯示：
  ├─ 系統活動中心（system_activity_card.dart）「照片辨識」常駐區塊
  │   └─ 待辨識 N 張 + 〔現在辨識〕手動按鈕（不等閒置直接切）
  └─ 模型卡角色徽章：💬 夥伴 / 📷 辨識（角色教育）
```

進程拓撲註記：EmbeddingGemma 走 flutter_gemma 在 App 進程內（不搶
18789）；18789 只有照片描述生成（local_vision_analyze）在搶——離合器
只調度這個。

### 4.3 Agent Loop（自主循環）

| 檔案 | 職責 |
|---|---|
| `agent_loop/agent_loop.dart` | 主循環引擎 |
| `agent_loop/agent_tool_registry.dart` | 工具註冊表 |
| `agent_loop/agent_loop_prompt_builder.dart` | prompt 組裝 |
| `agent_loop/production_agent_loop_llm_client.dart` | LLM 客戶端 |
| `agent_loop/agent_profile_store.dart` | Agent 模型設定 |
| `agent_loop/llm_retry_utils.dart` | retry 工具 |
| `agent_loop/agent_tool_call_parser.dart` | 工具呼叫解析 |

### 4.4 大腦容器（知識圖譜 + 向量記憶）

| 子目錄 | 職責 |
|---|---|
| `brain_container/` | 圖譜服務、DB、schema、分類、連結、衰變、嵌入、提取、增長、持久化、管線 |
| `brain_pipeline/` | 分析管線（Reality Transurfing）：attention gate、door flow、pendulum、heart-mind |
| `vector_db/` | 向量搜尋、資產索引、混合搜尋、視覺嵌入 |

**[小葵 2026-09-22] 記憶衰減已接線**：`BrainContainerService._scheduleDecayCycle()`（初始化後 130s 首跑 + 每 24h 週期）喚起 `MemoryDecayService.runDecayCycle()`——此前該服務寫好但全 repo 零呼叫點。軟刪（archived=1）不物理刪；user_marked 連結免疫休眠；md 副本永久留存。

**[小葵 2026-09-22 v18] 矛盾消解 + temporal filtering**（schema 17→18，借鏡 supermemory）：`memories.superseded_by`——寫入後同主題舊事實（語意近+字面 token 重疊<0.5）被新事實取代（軟標記留審計）；`expires_at` 啟用——過期臨時事實自然退場。所有檢索入口（findSimilarMemories/HybridSearch FTS+語意/MemoryStore.search）一律過濾 `superseded_by IS NULL AND (expires_at IS NULL OR > now)`。回歸測試：`test/brain_container/contradiction_resolution_test.dart`（6 條）。

**[小葵 2026-10-10 M0 記憶注入管線 + EventLedger]**（commit `1910c958`，測試 10/10）：
- `brain_container/embedding/embedding_service.dart` — 768 維向量化入口（flutter_gemma 載 300M EmbeddingGemma tflite，in-process 不搶 18789）
- `brain_container/inject/inject_pipeline.dart` — 注入主漏斗：`enrichWith(query, extraCandidates)` 回傳 `InjectResult(ids, content, droppedCount)`
  - `mergeCandidates(m0, extra)` 靜態方法：同 id 撞號保留 K1 版（靜態可測試）
  - 結果欄：`ids[]` / `content` / `similarities[]` / `droppedCount` / `k1KeptN`
- `brain_container/inject/slot_filter.dart` — 四槽位分類（recent/fact/habit/skill）。**K1 獨立通道**：`MemoryCandidate.source=='k1'` 不進四槽分類，依 hybrid 名次取前 `k1Quota=3` 獨立上限
- `brain_container/inject/budget_controller.dart` — 400 token 預算組裝。**K1 全列保證項排 M0 之前**；超預算淘汰序：M0 非保證→M0 保證→K1 尾端（kept[3]、kept[2]）；K1 kept[0] 由 length<=1 防護永不丟
- `brain_container/injection_preparer.dart` — 線上注入漏斗：digest→K1 守門→候選合併→四槽+預算→`InjectResult`+`InjectionOutcome`（含 `failureReason` 四態：embedding_model_unavailable/all_filtered/embedding_probe_zero_vector/no_candidates + `k1KeptN`）
- `brain_container/event_ledger.dart` — v4 schema：每輪對話 `turn_id` + `meta TEXT`（k1_hits_n/k1_kept_n/latency_ms/dropped_count/embedding_ok/failure_reason），`rebind()` 重置 `_ensuredV4` 旗標
- `services/bridge_mcp_server.dart` — 新增 `POST /inject/enrich` REST + MCP tool `inject_enrich`（線上注入條件＝評測條件，InjectPipeline 單一漏斗）
- `services/vector_db/hybrid_search_service.dart` — `search` 加 `bool expand=true` 參數，預設線上不變；K1 通道傳 `expand:false` 跳過 `_expandGraph`/`_expandContext`（Fable 🟡1 排序閘：圖譜展開命中 0.2~0.5 vs RRF 上限 0.033＝噪音壓真命中）

**[小葵 2026-10-10 M1 三道閘驗收（commit `66c66b1a`，19/19 全綠）]**
- 排序閘：K1 `_k1Candidates` 走 `expand:false` + 名次分數 1.0/0.9/0.8 + `take(3)` 硬上限 + `floorExempt=true` 免地板
- 槽位閘：`slot_filter` K1 不佔 M0 四槽、獨立上限 3 條；M0 四槽規則一字不動
- 預算閘：`budget_controller` K1 全列保證項排 M0 之前、K1 kept[0] 永不丟
- 預期效果：`k1_kept_n` 從 0~1 變 0~3；非記憶題行為完全不變
- **誠實揭露**：App 評測條件＝線上條件（單一漏斗 InjectionPreparer），過去 63% precision 是訓練集數字、M1 評測用 held-out `eval_m1_v1.jsonl`；雲端 ≤25% 不可達，採 ≤40% 暫行線（route_policy.json P1）

### 4.5 Bridge Adapters（能力介面卡）

| 檔案 | 職責 |
|---|---|
| `bridge_adapters/openai_image_adapter.dart` | OpenAI 圖片生成 |
| `bridge_adapters/minimax_image_adapter.dart` | MiniMax 圖片 |
| `bridge_adapters/minimax_video_adapter.dart` | MiniMax 影片 |
| `bridge_adapters/minimax_tts_adapter.dart` | MiniMax TTS |
| `bridge_adapters/gemini_image_adapter.dart` | Gemini 圖片 |
| `bridge_adapters/replicate_image_adapter.dart` | Replicate 圖片 |
| `bridge_adapters/openai_vision_adapter.dart` | OpenAI 視覺 |
| `bridge_adapters/openai_browse_adapter.dart` | OpenAI 瀏覽 |
| `bridge_adapters/local_desktop_files_adapter.dart` | 本地檔案操作 |
| `bridge_adapters/local_document_adapter.dart` | 本地文件 |
| `services/api_audit_log.dart` | [小葵 2026-09-14] API 調用審計日誌（`api_audit_log.jsonl`，5MB 輪替×3）——每次 adapter 調用本地記帳，數位主權基礎建設 |

**⚠️ 已知陷阱（2026-09-14 $3 事件修復）：**
- `BridgeActionExecutor` 的 adapter fallback：使用者**明確指定 provider**（`action.provider` 非空）時**禁止靜默 fallback** 到其他家（否則選 MiniMax 帳單卻給 OpenAI）。只有自動選擇情境才 fallback，且會在 result message + metadata（`fallbackOccurred`）標記。
- `openai_image_adapter._resolveImageQuality`：gpt-image-2 預設畫質 **low**（探索期省錢），定稿由 UI 明確指定 high。改動時注意 `image_provider_resolver.dart` 的 `_providerConfig` 也帶 quality，兩處同步。
- `minimax_image_adapter._buildSubjectReference`：參考圖檔案不存在時**直接拋錯**（舊行為安靜送出無參考圖請求 → 失敗 → 上游 fallback 換家背黑鍋）。

### 4.5b Computer Use — 接管電腦三件套（2026-09-05 Phase 0）

Spec：`docs/specs/2026-09-05-bridge-computer-use.md`

| 檔案 | 職責 |
|---|---|
| `macos/Runner/ComputerUseNative.swift` | 安全狀態機（TakeoverGate：idle→armed→active→suspended）+ Esc 長按 1.5s 急停事件 tap + 真人在場偵測（Agent 事件帶 sourceID 0x62726964 6765 區分）+ AX 樹序列化（限深6/限寬200，密碼欄值不上拋）+ CGEvent 注入（click/drag 曲線插值/typeText 中文 Unicode/scroll/key），全部注入必經 `canInject` 單點檢查 |
| `lib/services/computer_use/computer_use_service.dart` | Dart 端：狀態輪詢 stream、arm/activate/suspend/disarm、TCC 權限查詢/請求、AX windowTree、注入轉發（判斷不重複實作，Swift 單點強制） |

Channel：`bridge.computer_use.macos.v1`（在 MainFlutterWindow.swift awakeFromNib 註冊，比照 screenChannel 模式）

⚠️ 陷阱：
- 此 Swift 版本（Xcode 26）`as?`/`as!` 轉 CF 型別（AXUIElement/AXValue）會報錯，要嘛 `unsafeBitCast` 要嘛直接用 `var x: AXUIElement?` 接 out 參數（後者乾淨）
- `CGEvent.tapCreate` 參數順序是 `tap:place:options:eventsOfInterest:callback:userInfo:`（tap 在第一個）
- `keyboardSetUnicodeString` 需 `UnsafePointer<UniChar>`：`Array(text.utf16).withUnsafeBufferPointer` 是正解，String 直傳不行
- 事件 tap 沒有 TCC Accessibility 權限時 `tapCreate` 回 nil——這是預期行為，arm() 會擋
- pbxproj 是舊式（objectVersion 54，非 synchronized group）：新增 Swift 檔要手動註冊 4 處（PBXBuildFile/PBXFileReference/Runner group/Sources phase）

### 4.6 語音

| 檔案 | 職責 |
|---|---|
| `voice/voice_engine.dart` | 語音引擎入口 |
| `voice/voice_live_controller.dart` | 即時語音控制 |
| `voice/voice_state_machine.dart` | 語音狀態機 |
| `voice/voice_vad.dart` | 語音活動偵測 |
| `voice/voice_streaming_tts.dart` | 串流 TTS |
| `tts/kokoro_tts_service.dart` | Kokoro TTS |

---

## 5. macOS 原生層（Swift ↔ Dart 橋接）

**檔案：** `macos/Runner/MainFlutterWindow.swift` (~2741行)

### 5.1 MethodChannel

| Channel | handler | 職責 |
|---|---|---|
| `bridge_desktop_shell` | `applyLocalRuntimeAction()` | 本地模型生命週期 |
| `bridge_desktop_shell` | `applyDesktopShellState()` | 懸浮窗控制 |
| `bridge_desktop_shell` | `syncRuntime` | 懸浮窗 runtime 更新 |

### 5.2 關鍵 Swift 方法

| 方法 | 行 | 職責 |
|---|---|---|
| `setupWindow()` | ~40 | 視窗初始化、minSize |
| `startLocalRuntimeServer()` | 1401 | spawn llama-server |
| `restoreLocalRuntimeState()` | 2103 | APP 啟動時恢復狀態 + port 驗證 |
| `isPort18789Alive()` | 2128 | socket 檢查 port 18789 |
| `configure(panel:state:)` | 2321 | 懸浮窗 NSPanel 設定 |
| `applyRuntimeOnly()` | 2235 | 只更新 runtime 不碰 panel size |
| `applyLocalRuntimeAction()` | 506 | 本地模型 action dispatcher（注意：方法名是 `applyLocalRuntime` 不是 `applyLocalRuntimeAction`） |
| `localRuntimePreflight()` | 1911 | 找 llama-server + model |
| `removeQuarantineFromBin()` | 1934 | 移除 quarantine 屬性 |

### 5.3 視窗大小 — 兩端都要改
> ⚠️ [Blue 令 2026-10-05 · 以終為始] 現在有了第三層：**WindowAutoFitService**（`lib/services/window_autofit_service.dart`）
> 頂列內容（`_TopBarAutoFit` 影子量尺，`bridge_desktop_screen.dart` 檔尾）實測自然寬 → 上報 →
> **動態 minimumSize + 自動撐大視窗**。未來加按鈕視窗自動長大，不寫死尺寸。
> 寫死的 `Size(1440, 900)` / `Size(1280, 720)` 只是初始值，真正的下限由內容決定。
> log 前綴 `[WindowAutoFit]`。
>
> 🔬 [小葵 2026-10-05 影子量尺演進] 量「自然寬」的三個死巷（實測鐵證）：
> ① 直接量本體 RenderBox → 拿到約束寬（視窗寬），非需求寬
> ② OverflowBox(maxWidth: double.infinity) → `mainAxisSize.max` 在 unbounded
>    約束下 NEEDS-LAYOUT 永凍，量不到 size（run21）
> ③ IntrinsicWidth / left→right 跨距 → 頂列有 `Spacer`，在超大寬約束下
>    撐到 100000，量出 100024 假值（run24/run28）
> ✅ 正解：**連續群組法**——影子 Row 以有限超大寬（100000）layout，
> 走 RenderFlex children：非 flex children 依 offset 分群（間距 <300 同群），
> Σ 各群寬 + 群間 spaceLG + 外層 Container padding。Spacer 群組切開歸零。
> 實測：1440 視窗爆 7.1px → 量得 1447 → 視窗自動撐到 1496 → 警示條絕跡。

```
Dart 端：main.dart L21
  WindowOptions(minimumSize: Size(1280, 720))
  → window_manager 在 APP 啟動時設定

Swift 端：MainFlutterWindow.swift L47
  self.minSize = NSSize(width: 1280, height: 720)
  → NSWindow 初始化時設定

⚠️ Dart 端會覆蓋 Swift 端！兩端必須同步。
```

---

## 6. UI 元件（widgets/）

### 6.1 對話相關

| 檔案 | 職責 |
|---|---|
| `chat/agent_model_selector.dart` | Provider 切換按鈕（top bar 裡） |
| `chat/chat_input_bar.dart` | 訊息輸入框 |
| `chat/chat_sidebar.dart` | 對話列表側欄 |
| `chat/message_context_menu.dart` | 訊息右鍵選單 |

### 6.2 畫布相關

| 檔案 | 職責 |
|---|---|
| `canvas/v2/canvas_v2_workspace.dart` | V2 畫布主畫面 |
| `canvas/v2/canvas_controller.dart` | 畫布控制器 |
| `canvas/v2/canvas_state.dart` | 畫布狀態 |
| `canvas/v2/graph_canvas.dart` | 圖形畫布渲染 |
| `canvas/v2/node_widget.dart` | 節點 widget |
| `canvas/canvas_chat_panel.dart` | 畫布聊天面板 |

#### ♻️ 未來可回收的設計要點（2026-08-14 死代碼清理時保留）

> 來源檔案已刪，但這些設計創意值得未來在 V2 畫布上重實作：

1. **節點結果展開動畫**（原 `node_result_overlay.dart`，447 行，SemiCanvas 視覺 P3）
   - 圖片 blur→sharp 漸變、多圖 stagger 交錯出場
   - 影片進度條+預覽、音樂波形圖、文字打字機效果
   - 疊在節點下方展開結果卡片，展示 `lastOutput`
   - 回收時機：V2 節點執行結果的華麗展示

2. **畫布動態效果層**（原 `canvas_effects_layer.dart`，386 行，SemiCanvas 視覺 P2）
   - **Agent 游標**：顯示 Agent 正在畫布上的操作位置（共視場景必備）
   - 放置漣漪：節點放下時的擴散動畫
   - 連線資料流光點：資料沿連線流動的視覺化
   - 執行電流：節點執行時的電流效果
   - 疊在 CustomPaint 上方不干擾渲染；回收時機：MCP 共視 + 節點執行視覺化

### 6.3 夥伴相關

| 檔案 | 職責 |
|---|---|
| `floating_companion.dart` | Flutter 側懸浮窗（已改為 NSPanel） |
| `companion_presence_layer.dart` | 夥伴狀態圖層（StatelessWidget） |
| `companion_avatar_image.dart` | 頭像圖片 |
| `companion_art.dart` | 夥伴美術資源 |

---

## 7. 設計系統（theme/）

| 檔案 | 職責 |
|---|---|
| `bridge_design_system.dart` | 設計系統入口（顏色、字體、間距） |
| `bridge_ds_tokens.dart` | 33 個 BridgeDSColors token |
| `tier.dart` | Tier enum（33 個語意化 tier） |
| `tier_registry.dart` | Tier → Color 映射 |
| `tier_style.dart` | Tier → TextStyle 映射 |
| `app_theme.dart` | ThemeData |
| ~~`theme_controller.dart`~~ | **已刪除（2026-08-18）**——舊深淺切換，被 `state/theme_provider.dart` 主題包系統完全取代；Cmd+D 走 `ThemeProvider.instance.cycleToNext()` |
| `bridge_motion.dart` | 動畫曲線 |

**設計原則文件：**
- `docs/BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md` — 排版原則
- `docs/BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md` — 色塊規範
- `docs/BRIDGE_TIER_SYSTEM.md` — Tier 系統
- `docs/BRIDGE_ATMOSPHERE_LANGUAGE.md` — 氣氛語言
- `DESIGN.md` — 原始設計規範

---

## 8. 資料模型（models/）

主要模型：

| 檔案 | 職責 |
|---|---|
| `conversation.dart` | 對話 + 訊息模型（Message class） |
| `companion.dart` | 夥伴模型 |
| `companion_runtime.dart` | 夥伴運行時狀態 |
| `bridge_action.dart` | Bridge Action 標籤解析 |
| `project_door.dart` | 專案門模型 |
| `brain_container/` | 大腦容器資料模型群 |
| `canvas/` | 畫布資料模型 |
| `theme_pack.dart` | 主題包模型 |

---

## 9. 死代碼（不要參考、不要 grep 進來）

| 檔案/方法 | 狀態 |
|---|---|
| `chat_screen.dart` `_showSkillPanel` | 死代碼，無 UI 觸發點 |
| `chat_screen.dart` `_showModeSelector` | 死代碼（舊靈魂切換殘骸） |
| `chat_screen.dart` `_showMemoryOverlay` | 死代碼 |
| `screens/mobile_bridge_pairing_screen.dart` | 手機版遺留，不再路由觸發 |
| `screens/mobile_design_showcase_screen.dart` | 手機版遺留 |
| `services/mobile_bridge_client.dart` | 手機版遺留 |
| `widgets/mobile/` | 手機版遺留 |
| `screens/settings_screen.dart` | 已刪除（導航 redirect 到 `system`） |

---

## 10. 常用 grep 起點

想找一個功能但不知道在哪？從這裡開始：

```
# 找 UI 元素
grep -rn "你想找的文字" lib/screens/ lib/widgets/

# 找服務邏輯
grep -rn "function名" lib/services/

# 找 Swift 原生
grep -rn "method名" macos/Runner/MainFlutterWindow.swift

# 找持久化 key
grep -rn "key名" lib/services/storage_service.dart

# 找 MethodChannel
grep -rn "channel名" macos/ lib/

# 找誰呼叫了某方法
grep -rn "方法名(" lib/
```

---

## 11. 已知陷阱（踩過的坑）

| 陷阱 | 原因 | 解法 |
|---|---|---|
| 改 Swift minSize 沒效果 | `window_manager` (Dart) 在啟動時覆蓋 | main.dart + Swift 兩端都改 |
| 對話泡泡改一個沒效果 | 三個檔案有副本 | message_bubble + canvas_chat_panel + desktop_chat_panel 全改 |
| APP 說 server 已啟動但 port 空 | runtime-state.json 存了假 running 狀態 | restoreLocalRuntimeState 加 port 驗證 |
| llama-server 啟動後秒死 | Pipe buffer 64KB 滿了 block write | 改用 log 檔案，不用 Pipe |
| 懸浮窗縮放被重置 | syncRuntime → configure → setContentSize | 用 applyRuntimeOnly() 跳過 size |
| SharedPreferences 寫了讀不到 | macOS sandbox 殘留 container 路徑 | 確認 APP 是 sandbox=false |
| gateway_url 不匹配 | saveProviderConfig 不清舊 url | 手動修 plist 或修 saveProviderConfig |
| 編輯夥伴改文字→形象圖消失 | onChanged 回調清 _candidate=null | 編輯模式跳過清 candidate（L2059） |
| 編輯夥伴改文字→存檔後沒更新 | Companion model 缺 inspiration/specialFunction 欄位，用 roleName getter 填入 | 新增持久化欄位（companion.dart L339-340） |
| 預審紅燈誤判成人內容 | Vision API prompt 沒有明確判定標準，太敏感 | prompt 加嚴格標準：只有明確裸露才算 true |
| 預審 typo「長寬比例過端」 | typo（應為「過度偏斜」）+ 閾值 0.42/2.4 太嚴 | 改 typo + 放寬到 0.3/3.5 |
| 地圖缺少頁面 | 初版只寫了核心模組 | 補完所有 screens/ 頁面條目 |
| vault 樹扁平化＋選資料夾右側恆空 | 多授權根合併時 `buildFileTree` 只吃相對路徑丟掉根層；樹節點 key（相對）與篩選端（絕對 `folder/path`）路徑空間不同源 | `groupByRoot:true` 第一層=根節點；節點 path 一律絕對路徑（`rootPrefix` 貫穿 `_insertIntoTree`）。改任何樹/篩選前先確認三方（樹 key/篩選/檔案系統）同一空間（vault_file_tree.dart，2026-09-09） |
| Icon\r 檔清了又回來 / migration 清不掉 | 檔名含歸位字元 `\r`，SQL `= 'Icon'` 比對不到；掃描器排除規則漏了它 | SQL 用 `LIKE 'Icon%'`；`AssetSandbox.isJunkFile` 排除 `Icon\r`＋`._*`（asset_sandbox.dart，2026-09-09） |
| 全量重嵌成果被蓋掉（identity 2680→愈跑愈少） | 7 個背景 backfill 服務把 `embed_source` 蓋回 `'content'`——多寫入者對同一欄位所有權沒定 | embed_source 單調升級鏈：NULL/filename→metadata→content→identity；backfill 守門 `NOT IN ('content','identity')`。新增任何會寫 embed_source 的服務必須遵守（2026-09-09, 42c3b995） |
| 語意搜尋 SQL 參數順序錯→掃描 0 筆 | `vector_full_scan(vec, k)` 的 k 吃到 bool 旗標變 0；SQL `?` 順序≠參數列順序 | 參數序＝SQL 文字中 ? 出現順序：vector→k→旗標→LIMIT（hybrid_search_service.dart，2026-09-09） |
| 搬家記憶語意搜尋永遠 0 筆（embedding 在但查不到） | 三斷點疊加：① `vector_init` 沒 init `agent_memories`（per-connection，與鐵三角 #3 同死法）② HybridSearchService 只掃 memories 表 ③ agent_memories.id 是 TEXT 不能 `ON m.id = v.rowid` | ① kAgentVectorInitSql 每連線必跑 ② `_searchAgentMemoriesSemantic` 接進 semantic+hybrid 兩路 ③ `ON m.rowid = v.rowid`。**新表要被 vector_full_scan 掃，三件事都要做**（hybrid_search_service.dart + brain_schema_sql.dart，2026-09-21, 1a59387a） |

---

## 12. 變更日誌

| 日期 | 變更 | 作者 |
|---|---|---|
| 2026-09-08 | **搜尋引擎統一（S4 Blue 統一令）**：新增 `VaultSearchFacade` 單一真相，全域搜尋與 vault 全模式改打它；羅盤新增規則 `search.singleEngine`（禁另建搜尋路徑）。全域搜尋 S1-S3：常駐面板＋狀態保留＋四動作（vault/galaxy/畫布/對話） | 小葵 |
| 2026-08-14 | 初版建立 | 教練 Agent |
| 2026-08-14 | 補完夥伴設定頁面 + 全部 screens/ 頁面到快速導航 | 教練 Agent |
| 2026-08-14 | 新增陷阱：編輯夥伴改文字→形象圖消失 | 教練 Agent |


## 系統活動中心（2026-09-30 金礦1）
- 想看背景任務狀態 → `lib/services/activity/background_task_registry.dart`（Registry 單例）
- 新任務接入：`BackgroundTaskRegistry.instance.update(BackgroundTask(...))` + 結束 `finish(id)`
- UI 卡 → `lib/widgets/system_activity_card.dart`（系統頁頂部，無任務隱形）
- 已掛牌：IdentityReembed（identity_reembed）、模型實驗室快測（model_lab_quicktest）
- 教訓源起：2026-09-29 IdentityReembed 隱形燒 200% CPU 懸案


## embed_source 狀態機（2026-09-30 第七金礦）
- **identity = 終態，DB trigger 強制不可逆**（trg_identity_guard：identity→其他一律 ABORT）
- trg_embed_watch：所有 embed_source 變化自動留痕 embed_audit 表（誰/從哪/到哪）
- 寫 asset_index 的規則：
  - UPDATE 帶 `AND COALESCE(embed_source,'') != 'identity'`（四處已示範）
  - **禁 INSERT OR REPLACE**（整 row 重建丟失嵌入成果）→ 用 ON CONFLICT(file_path) DO UPDATE 且不碰 embed_source/embedding/content_text
  - 想把檔案升級到 identity → 只走 IdentityReembedService（唯一合法入口）
- 歷史案卷：2026-09-29/30 兩次互踩慘案（content 嵌入翻掉 identity，每天重做 3000 筆）

## 大腦看門狗（2026-10-01 F5）
- 想改「引擎死了沒人救」→ `lib/services/brain_revival_service.dart`（App 級，掛在 bridge_desktop_screen initState）
- URL 真相源 = `StorageService.getLocalModelEndpoint()`（**不是** gateway_url——那是雲端主腦的）
- 生命週期真相源 = `BrainLifecycle` stream（U2 徽章只訂閱不自行判斷）
- 冷卻語意：嘗試節流（成敗都計時 10 分鐘），不是死亡鎖
- ⚠️ 陷阱：看門狗不得掛任何 UI 依賴（card initState 教訓：沒逛頁=沒保母）

## 掃描管線（2026-09-30 F1）
- 指紋快取：brain_meta `tree_fp:<FNV-1a>`（String.hashCode 每啟動隨機化，禁用於持久 key）
- _persistRecords 已批次化（禁逐筆 SELECT+debugPrint 的寫法）
- embed_source 狀態機：identity=終態（DB trigger ABORT 強制；應用層 UPDATE 必帶 !=identity；禁 INSERT OR REPLACE）

## 開光 P1（2026-10-01 隱藏門收編）
- MCP tools 34→41：app_scroll（新感官：頁面捲動）+ galaxy_view/identity_reembed/vector_sketch/import_progress/global_notice/rescan schemas
- app_scroll 鏈路：tools/call → _handleAppScrollCore → onAppScroll callback（bridge_desktop_screen 注入）→ extent 擇大法找主內容 Scrollable
- ⚠️ tools/list 的 _meta 格式：`{"io.modelcontextprotocol/clientCapabilities": {}}`（key 即能力名）
- 隱藏門剩餘：galaxy_* 系列多為 HTTP 直連（schema 用 galaxy_view 聚合）；health/mcp/state/fps_probe 內部用不收編

## 開光 v0.4.0 眼與手（2026-10-01）
- **app.look**：target=app→AppRetina.capture；target=screen→架構預留（誠實回 notSupported，Blue 拍板介面不鎖死）
- **app.tap**：onAppTap callback（bridge_desktop_screen）→ selector 全域收集 Text/SelectableText → 找最近可點祖先（GestureDetector/InkWell/Button×8 層）→ 視野內優先+文字最短=最佳候選。v1=定位回報制（不真點），x/y 座標後門同規
- ⚠️ 陷阱：visitChildElements 閉包內 return 只跳單層——全域收集後再擇優，不要 early-return
- 隱藏門收編 P1.5：_proxyGet 同進程直呼 shelf router（_router 欄位化）；tools 43；galaxy_view 聚合 galaxy_* 家族

## tools_health（開光 #7，2026-10-01）
- 工具級自檢：_dispatchedTools 活性 Set（dispatch 入口記錄）→ neverDispatched = 從未被叫過的工具
- callback 接線彙總 + get_canvas_state 活性探針（ok/nodes 數/null 異常/callback 未接線 分流）
- healthy=false 帶明確 message——設計鐵則：任何工具要嘛正常要嘛明確報錯，禁優雅回 null


## 開光 v0.4.x 完全體（2026-10-01 下午）
- app_tap confirm=true 真點：**handlePointerEvent** 完整 lifecycle（hitTest→pointer router→gesture arena）。
  ⚠️ 陷阱：直接 handleEvent 給 hit path 繞過 arena——42 層收到事件但 GestureDetector.onTap 不響
- app_look target=screen：Swift captureScreen（CGWindowListCreateImage CGRect.null 全螢幕）
  → 暫存 → Dart base64 → 即刪。⚠️ sandbox 內 screencapture 子進程被 TCC 擋（app_permissions 可查）
- 實測：真點 nav「畫布」tab → page home→canvas ✓；screen 3440x1440 ✓

## app_scroll 擇靶八代史（2026-10-01 benchmark 淬鍊——重要陷阱）
- 頁面快取層用 **Offstage**：離屏頁的 scrollable pixels 會動、layout 會變、**但不渲染**
- 任何「幾何/像素」擇靶法都會被騙；v8 兩輪制（先非 Offstage→fallback 全收+實證）為當前解
- args vs params：MCP dispatch 傳參要傳 `params['arguments']`（傳錯層=direction 丟失被當 down）
- jumpTo 後需等一幀（120ms）再拍照，否則拍到捲動前畫面

## 開光最後一哩——內建 agent loop 感官（2026-10-01 傍晚）
- app_senses_tools.dart：內建 loop 工具直呼 `BridgeMcpServer.instance` 的
  onAppScroll/onAppTap callbacks + AppRetina.capture（同進程，不走 8420）
- 註冊點：AgentToolRegistry.withDefaults 一處改，chat_controller（1435）與
  bridge_desktop（1697）兩個 loop 全覆盖
- Quick Assistant system prompt §3.5：口語「你看畫面中的 X」→ look→scroll→tap 循環
- get_agent_debug 顯示 hasAgentLoop=false 屬正常——對話 tab 走 desktopController
  （工具同樣由 withDefaults 提供）

## 幽靈進度條案（2026-10-01 傍晚，Blue 通報）
- BackgroundTaskRegistry sweeper 只清 done——running 任務若異常路徑沒走到
  finish 就永生（UI 進度條永凍）。修：progressAt 戳+30min 殭屍清理
- 診斷三板斧：import_progress（後台真相）+ DB 直查（index_status 分佈）
  + app_look（UI 現場）——三邊對照即知「UI 謊報 vs 工作真掛」
