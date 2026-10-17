# STE-80% 合規稽核——bridge_app「AI↔程式互動面」盤點（稽核任務 A）

- 日期：2026-10-12
- 稽核基準：`docs/WEAVE_HANDOFF_SPEC.md` 六條規則（R1 一句一動作、R2 動詞統一、R3 名詞先註冊、R4 禁歧義代名詞、R5 數字帶單位來源、R6 宣稱附證據）
- 範圍：只稽核「AI 讀的指令層」。機器↔機器（純 JSON schema 傳輸層）與 Agent↔人（UI 文案）不計瑕疵。
- 性質：**find-only，未改任何檔案**。本檔為本次唯一新建檔案。
- 基準 commit：`59b5debc`（docs(AGENTS): 驗收鐵則新增 STE-80% 交接令）

---

## 一、瑕疵清單（21 項：嚴重 3、輕微 18）

### 嚴重瑕疵（3）

| # | 位置 | 違反 | 問題 | 修法建議 |
|---|---|---|---|---|
| S1 | `lib/services/bridge_mcp_server.dart:1693-1709` 與 `1785-1798` | R3 | `app_look` schema **註冊兩次且語意衝突**：第一版 `target`=7 個頁面名（home/chat/…，導航式拍照）；第二版 `target`=enum `[app,screen]`（不導航）。外部 LLM 收到兩份矛盾契約。dispatch 也有兩個 case（`2037`、`2347`），後者永遠走不到 | 刪除舊 schema，合併為一份（target 同時收頁面名與 app/screen），dispatch 只留一個 case |
| S2 | `lib/services/bridge_mcp_server.dart:1722-1735` 與 `1800-1811` | R3＋R2 | `app_tap` 同樣雙 schema：第一版參數=`target`（canvas_toolbar:save/copy/test/run）；第二版=`selector`/`x`/`y`/`confirm`。dispatch 雙 case（`2083` target 版遮蔽 `2454` selector 版） | 合併 schema（target 與 selector 並列為兩種用法並寫明差異），或拆成 `app_tap_toolbar` / `app_tap_ui` 兩個名字分別註冊 |
| S3 | `lib/services/agent_loop/agent_loop_tools/delegate_subagent_tool.dart:293` vs `311`（檔頭註解 `22` 同） | R5＋R6 | 指定 provider 路徑 `.timeout(Duration(seconds: 60))`，但逾時錯誤文案寫「**120 秒**」——數字與事實不符，主 Agent 會基于錯誤時間預算做決策 | 文案改「60 秒」，或把 timeout 統一為 120 秒；檔頭註解同步修正 |

### 輕微瑕疵（18）

| # | 位置 | 違反 | 問題 | 修法建議 |
|---|---|---|---|---|
| M1 | `lib/services/agent_loop/agent_loop_tools/compass_seek_agent_tool.dart:147,149` | R1（版面） | 描述字串寫 `'第一步。\\n'`——Dart 轉義失誤，LLM 實際收到**字面反斜線 n**，版面破碎 | 改真實換行 `'\n'`（去掉一層反斜線） |
| M2 | `lib/services/agent_loop/task_prompt_enhancer.dart:162,206` | R1（版面） | 同上：`'之前的對話上下文：\\n$previousContext\\n\\n'` 與 fallback 文案含字面 `\n` | 同上，改單層 `\n` |
| M3 | `lib/services/agent_loop/agent_loop_prompt_builder.dart:191` | R1 | 「畫布自動修復」一行塞 5 個動作（收到警示→確認→修正→再驗證→報告→再檢查） | 拆成編號清單 1-5，一步一句 |
| M4 | `lib/services/agent_loop/agent_loop_prompt_builder.dart:198` | R1 | 「畫布感知三層」①②③擠同一段，尾句「看見問題就修，修完再看一次確認」又是三動作連寫 | ③獨立成句並編號；尾句拆兩句 |
| M5 | `lib/services/agent_loop/agent_loop_prompt_builder.dart:204` | R1＋R4b | App 畫面感知鐵則一行三條；「filter "error" **會漏掉** warning 級」否定藏在括號裡 | 否定句獨立並加粗：「**不可**只用 filter "error"」 |
| M6 | `lib/services/agent_loop/agent_loop_prompt_builder.dart:24` | R5 | 「60 秒 idle 兜底感知」有單位無來源 | 補「（來源：NativeAgentLoop 常數）」或刪數字 |
| M7 | `lib/services/quick_assistant/quick_assistant_system_prompt.dart:54` | R4 | 「拿到錯誤訊息 — **它**通常直接指向根因」代名詞 | 改「錯誤訊息通常直接指向根因」 |
| M8 | `lib/services/quick_assistant/quick_assistant_system_prompt.dart:137-138,144` | R4＋R4a | grill-me 段「**它**的 README」「**它**怎麼進入你的日常工作」——「它」跨句距離遠 | 重述「這個專案（${slotLabel}）」 |
| M9 | `lib/services/quick_assistant/quick_assistant_system_prompt.dart:33-88` | R3 | 章節編號 1、2、3、**3.5**、4、5 跳號——編號即索引，插入段破壞可引用性 | 重排為連續 1-6 |
| M10 | `lib/services/bridge_mcp_server.dart:1347,1616,1631,1786` | R2 | 「看畫面」動作家族五工具五種詞：screenshot「截取」／app_view「視網膜拍照」／app_look「視網膜拍照·眨眼」／render_layer「周邊視覺」／canvas_capture「注視」——同域動詞未統一、差異未註冊 | 各描述開頭統一動詞「拍照／讀場景」，並在 app_look 描述內註冊一行差異表 |
| M11 | `lib/services/bridge_mcp_server.dart:1432` | R4＋R3 | send_user_message：「**用 sendDirectMessage** 不依賴 UI text field」主語省略＋內部 API 名未註冊 | 「此工具經 sendDirectMessage 送出，**不經** UI 輸入框」 |
| M12 | `lib/services/bridge_mcp_server.dart:1660` | R3 | inject_enrich：「四槽位+預算」「K1」內部名詞句內未註冊 | 補一句對照：「四槽位（core/task/episodic/scratch）、K1（守門員篩選）」 |
| M13 | `lib/services/capability_advisor_service.dart:240` | R6 | 「搜尋結果為空，請根據你的知識提供三家主流方案」——要模型憑空生成卻未要求標「未驗證」 | 加：「並在 aiNote 標註『未驗證：來自模型知識』」 |
| M14 | `lib/services/computer_use/computer_use_agent.dart:205` | R1 | 「不確定時寧可再觀察一步（action 用 click 點無害處），不要亂點」——一句兩指令且有矛盾風險（觀察≠點擊） | 拆兩句：「不確定時先回觀察步驟。**不可**亂點。」 |
| M15 | `lib/services/agent_loop/agent_tool.dart:49` | R3 | `AgentToolResult.failure` 統一前綴「工具執行失敗：」不含工具名——多工具輪次的錯誤文本難歸屬 | 工廠方法帶入 name：`'工具 $name 執行失敗：…'` |
| M16 | `lib/services/vector_db/path_hint_extractor.dart:57` | R4b | 「畫面沒有的不要寫」否定縮寫在括號內 | 「僅描述畫面可見內容。**不可**寫畫面外項目。」 |
| M17 | `lib/services/paid_action_gate.dart:134-135` | R5＋R4b | 「近期失敗率 30%」未標來源（BudgetLedger）；「別重試」否定縮寫 | 「近期失敗率 30%（來源：BudgetLedger）」＋「**不可**直接重試，先換策略」 |
| M18 | `lib/services/semicanvas/app_schedule_engine.dart:203-211` | R6 | `_errorSummary` 截斷 120 字只加「…」未標「已截斷」；fallback「執行失敗」無任何根因指向——排隊卡病歷缺證據 handle | 截斷加「…（截斷，全訊息見 app log）」；fallback 改「執行失敗（無錯誤訊息，見 log）」 |

### 觀察備註（不計瑕疵）

- `bridge_mcp_server.dart:1768` window_control「還原預設大小 1440x900」未標單位（邏輯 px）——單一點位，併入 R5 教育宣導。
- `task_evidence.dart` 的 headline/summary 文本最終渲染給人看（Agent↔人層），依 spec §0 不套 STE，未計瑕疵。
- `schedule_card.dart` 的 `humanSchedule`/`warmLine` 為人類可讀欄位，同上豁免；model 本身不含 AI 指令文本。
- `agent_task_inbox.dart` / `task_chain_controller.dart` 的 prompt 欄位為 pass-through（使用者原文），無固定模板可稽。

---

## 二、合規互動面清單（21 個）

| # | 互動面 | 位置 | 備註 |
|---|---|---|---|
| 1 | 核心身份 `_coreIdentity` | agent_loop_prompt_builder.dart:19-40 | 路徑/邊界名詞註冊清楚（除 M6 一處數字） |
| 2 | 工具使用鐵律 | agent_loop_prompt_builder.dart:110-134 | 編號＋格式範例＋否定加粗，模範等級 |
| 3 | 白話鐵則 | agent_loop_prompt_builder.dart:125-134 | 附對照例與自檢句 |
| 4 | 鎖定 provider 指令 | agent_loop_prompt_builder.dart:140-150 | 五條編號、覆蓋關係明示 |
| 5 | 證據等級（因果誠實鐵則） | agent_loop_prompt_builder.dart:290-304 | 四級定義＋「寧標推測不假裝」——R6 官方實踐，模範 |
| 6 | 出處戳（話語歸屬） | agent_loop_prompt_builder.dart:331-346 | speaker 四值註冊＋查證程序編號，模範 |
| 7 | 時間感＋相遇時間軸 | agent_loop_prompt_builder.dart:316-326, 350-352 | 「唯一時間真相」宣稱與機制一致 |
| 8 | 決策引導守則＋成功驗證鐵則 | agent_loop_prompt_builder.dart:242-272 | 編號、JSON 格式正誤對照 |
| 9 | 對話衛生守則 | agent_loop_prompt_builder.dart:277-286 | 三條編號 |
| 10 | 本地輕量 prompt `_buildLocalPrompt` | agent_loop_prompt_builder.dart:406-465 | 工具格式範例＋邊界明示 |
| 11 | 畫布健康警示文本 `_checkCanvasHealth` | agent_loop_prompt_builder.dart:505-511 | 坐標/節點名如實帶出（除 M 類座標單位小節） |
| 12 | 輕裝 system prompt `_buildLiteSystemPrompt` | agent_loop.dart:1275-1293 | 〔K1 記憶命中〕標記註冊＋白話鐵則 |
| 13 | 對話模式宣告 | agent_loop.dart:537-546 | 禁止事項列表（R4b 合規） |
| 14 | 結構性 nudge 文本（含僵局升級版） | agent_loop.dart:866-880 | 「二選一」結構＋格式範例＋後果明示 |
| 15 | 輕裝升級系統註記 | agent_loop.dart:913 | 單句單動作 |
| 16 | 派工任務 prompt `_buildTaskSystemPrompt` | chat_controller.dart:6899-6927 | session.id/畫布名註冊、誠實條款 |
| 17 | 對話歷史組裝＋摘要 prompt＋會議主持人 | chat_controller.dart:1893-1903, 1181-1186, 6704 | [使用者]/[夥伴] 標籤註冊、RESOLUTION\| 格式註冊 |
| 18 | delegate_subagent 描述/參數＋【上下文】【任務目標】模板 | delegate_subagent_tool.dart:126-147, 340-346 | 模板本身合規（錯誤文案見 S3） |
| 19 | 記憶提取 prompt 全檔 | brain_container/extraction/extraction_prompt.dart | 六類 category 註冊、importance 量表附判準——模範 |
| 20 | brain_pipeline 七個 analyzer prompt | analyzers/*_ai.dart（如 door_flow_detector_ai.dart:13-55） | enum 註冊＋few-shot 範例附完整回應——模範 |
| 21 | 其餘：heart_mind 整合器、dream_reflection、l3_llm_engine 七 prompts、openai_visual_review、canvas_place 參數說明、toPromptSection/tool_help、skill_prompt_injector、budgetEye、bridge_mcp_server 多數 schema（navigate/window_map/app_permissions/galaxy_view/tools_health 等） | 見各檔 | 結構化、名詞註冊到位、數字帶單位 |

---

## 三、總結

| 指標 | 值 |
|---|---|
| 互動面總數 | **42**（①系統提示/prompt 組裝 20、②MCP 與 AgentTool 工具描述 14、③任務卡/模板 4、④執行史/病歷/錯誤文本 4） |
| 合規 | 21（50%） |
| 輕微瑕疵 | 18（43%） |
| 嚴重瑕疵 | 3（7%） |
| **合規率（合規＋輕微）** | **93%**；嚴格口徑（僅完全合規）50% |

三個最急迫修的：
1. **S1+S2（bridge_mcp_server.dart）**：`app_look`／`app_tap` 雙 schema 雙 dispatch——同名詞兩份矛盾契約，是 tools/list 直接餵給外部 LLM 的第一手文本，誤讀成本最高。
2. **S3（delegate_subagent_tool.dart:311）**：逾時文案 120 秒 vs 實際 60 秒——唯一「數字說謊」等級的 R5 違規。
3. **M1+M2（字面 `\n` 轉義失誤）**：兩個高頻工具（compass_seek、task_prompt_enhancer）的描述帶字面反斜線 n，一分鐘可修、即刻改善所有下游 prompt 品質。

整體觀察：新寫的區塊（證據等級、出處戳、nudge、extraction prompt、brain analyzers）已自覺實踐「名詞註冊＋編號＋否定加粗＋寧標推測」，與 spec 精神一致；瑕疵集中於 **2026-09 以前的舊 MCP schema 層**（重複註冊、隱喻式動詞）與**字串轉義細節**。建議下一棒以 S1/S2 為起點做 schema 收斂。
