# 橋樑 App 手機版重整設計交接檔

> **建立日期**：2026-08-02  
> **作者**：教練 Agent（AI Agent）  
> **審查範圍**：481 個 .dart 檔案（services 292, screens 72, widgets 68, models 38）  
> **用途**：作為未來手機版重新統整設計的起點

---

## 一、專案現狀概覽

### 程式碼規模

| 類型 | 數量 |
|---|---|
| services/ | 292 個 |
| screens/ | 72 個 |
| widgets/ | 68 個 |
| models/ | 38 個 |
| **合計** | **481 個 .dart** |

### 核心架構

```
App
├── 桌面版（macOS）← 目前主力，功能最完整
├── 手機版（iOS/Android）← 配對模式，需桌面端 Gateway
└── Web 版 ← kIsWeb 條件分支，基本框架
```

---

## 二、重複功能 & 死程式碼清查

### 2.1 需要收斂的重複

| # | 重複群組 | 問題 | 建議 |
|---|---|---|---|
| 1 | brain_container/ (22檔) vs brain_pipeline/ (42檔) vs second_brain_* (4檔) | 三套「第二大腦」系統，命名和職責有交疊 | 明確分層：brain_container = 持久化+API門面 / brain_pipeline = 七層分析 / second_brain = 檔案索引+展示 |
| 2 | memory_store.dart vs brain_container/persistence/memory_writer.dart | 舊版 SharedPreferences vs 新版 SQLite 向量 | memory_store.dart 標記 deprecated，逐步遷移到 brain_container |
| 3 | 7 組 _ai.dart + _rule.dart + mixed_*.dart | 同一功能三版本（規則優先→觸發詞命中才跑 AI） | **保持現狀** — 這是正確的設計（觸發詞是省 token 的保護閥） |

### 2.2 死程式碼（建議清理）

| 檔案 | 狀態 | 處理 |
|---|---|---|
| `door_drift_detector.dart` | 0 imports，已無引用 | 可刪 |
| `local_model_version_service.dart` | 0 imports | 可刪或補入口 |
| `context_transfer_service.dart` | 0 imports | 可刪或補入口 |

### 2.3 平台實作（不可刪）

| 檔案 | 用途 |
|---|---|
| `js_bridge_stub.dart` | 非 Web 平台的 JS Bridge 分發 |
| `js_bridge_web.dart` | Web 平台的 JS Bridge 實作 |

---

## 三、UI 層功能分類

### 3.1 桌面專用（手機版不需要）

| Screen | 功能 |
|---|---|
| `bridge_desktop_screen.dart` | 桌面主視窗 |
| `desktop_welcome_screen.dart` | 桌面歡迎頁 |
| `desktop_summon_screen.dart` | 桌面召喚 |
| `desktop_homepage_screen.dart` | 桌面首頁 |
| `desktop_chat_panel.dart` | 桌面聊天面板（側邊欄式） |
| `desktop_file_page.dart` | 桌面檔案總管 |
| `desktop_organize_handler.dart` | 桌面整理報告 |

**桌面 widgets**：canvas/ (20+ 檔), project/ (看板/關係圖), bridge_cards/

### 3.2 手機版需要

| Screen | 功能 | 完成度 |
|---|---|---|
| `chat_screen.dart` | 主聊天介面 | ✅ 完整 |
| `companion_list_screen.dart` | 夥伴列表 | ✅ 完整 |
| `companion_create_screen.dart` | 創建夥伴 | ✅ 完整 |
| `companion_appearance_screen.dart` | 夥伴外觀 | ✅ 完整 |
| `companion_soul_screen.dart` | 夥伴靈魂設定 | ✅ 完整 |
| `lock_screen.dart` | 密碼鎖定 | ✅ 完整 |
| `mobile_bridge_pairing_screen.dart` | 掃 QR 配對桌面 | ✅ 完整 |
| `summon_screen.dart` | 星空召喚動畫 | ✅ 完整 |
| `first_summon_screen.dart` | 首次使用引導 | ✅ 完整 |

**手機版 widgets**：voice/ (語音按鈕), companion 藝術渲染

### 3.3 跨平台共用

| Screen | 功能 |
|---|---|
| `settings_screen.dart` | 設定頁 |
| `golden_keys_screen.dart` | API Key 管理 |
| `capability_center_screen.dart` | 能力中心 |
| `vault_screen.dart` | 向量資料庫 |
| `brain_container_screen.dart` | 大腦容器 |
| `achievement_collection_screen.dart` | 成就 |
| `semi_dao_review_screen.dart` | SemiDAO 審核 |
| `master_folder_manager_screen.dart` | 主資料夾管理 |
| `blind_box_screen.dart` | 盲盒 |

### 3.4 平台判斷策略

目前用「非桌面」推斷手機：
```dart
// 桌面：Platform.isMacOS || Platform.isWindows || Platform.isLinux
// 手機：!isDesktop（不直接檢查 Platform.isIOS）
// Web：kIsWeb 獨立處理
```

29 個檔案有 Platform 條件分支。

---

## 四、Service 層功能完成度

### 4.1 ✅ 已接通（正常運作）

| Service | 完成度 | 說明 |
|---|---|---|
| api_service.dart | ✅ 100% | 雲端 LLM 呼叫（OpenAI/ZAI/MiniMax/Kimi/Anthropic） |
| provider_registry.dart | ✅ 100% | **唯一 endpoint 配置源**（已收斂） |
| storage_service.dart | ✅ 100% | API Key + provider + gateway（已簡化） |
| brain_database.dart | ✅ 100% | SQLite 向量 DB（已加啟動驗證） |
| brain_container_service.dart | ✅ 100% | 大腦門面服務 |
| embedding_service.dart | ✅ 100% | Gemma-300m 嵌入 |
| asset_index_service.dart | ✅ 100% | 檔案索引+嵌入（已修復 SVG/程式碼） |
| hybrid_search_service.dart | ✅ 100% | 混合搜尋（向量+關鍵字） |
| agent_loop | ✅ 100% | Agent 工具鏈 |
| memory_recall_service.dart | ✅ 100% | 對話歷史回溯 |
| canvas_mcp_server.dart | ✅ 100% | MCP Server (port 8420) |
| tray_service.dart | ✅ 100% | macOS 系統列 |
| local_model_runtime_service.dart | ✅ 100% | llama.cpp 管理 |
| voice_engine.dart | ✅ 95% | 語音引擎（三層回應架構） |

### 4.2 ✅ 手機版配對通訊（已接通）

| Service | 完成度 | 說明 |
|---|---|---|
| mobile_bridge_client.dart | ✅ 95% | WebSocket client（connect/hello/reconnect/push） |
| desktop_bridge_local_gateway.dart | ✅ 95% | Desktop Gateway（追蹤已連線手機） |
| desktop_bridge_gateway_protocol.dart | ✅ 100% | 通訊協議定義（taskRun/taskPush/長任務） |
| companion_broadcaster.dart | ✅ 100% | 夥伴狀態廣播 |
| companion_runtime_outlet.dart | ✅ 100% | Runtime 狀態輸出 |

### 4.3 ⚠️ 框架完成但需外部配置

| Service | 缺什麼 |
|---|---|
| wallet_service.dart | WalletConnect projectId |
| semidao_onchain_service.dart | RPC URL + 合約地址（目前預設 Base Sepolia） |
| browser_automation_service.dart | 需確認 Chrome + Puppeteer Dart 套件 |
| pinata_ipfs_service.dart | Pinata API Key |

### 4.4 Singleton 數量

42 個 singleton 檔案。大多數合理（service 層），但需注意初始化順序依賴。

---

## 五、架構收斂已完成（2026-08-02）

| 收斂項 | 之前 | 之後 |
|---|---|---|
| Endpoint URL | ProviderRegistry + ServiceRegistry 兩份表 | ProviderRegistry 唯一源（11 處改動態查詢） |
| DB 路徑 | 3 個位置 + unicode escape bug | 啟動驗證 + fallback + symlink |
| API Key | 三層 fallback（macOS） | 單層讀取 + saveProviderConfig() |
| 嵌入系統 | manifest 驅動 + SVG 走 VisionPipeline | DB pending 驅動 + SVG 走文字路徑 |
| 外接碟權限 | 每次重簽都彈 | Full Disk Access 一次性授權 |

---

## 六、手機版重整建議

### 6.1 手機版的核心定位

手機版不是獨立 App，是**桌面端的衛星**：
- 透過 WebSocket 連接桌面 Gateway
- 桌面端做重活（LLM 推理、向量搜尋、嵌入）
- 手機端負責：聊天、語音、夥伴互動、通知接收

### 6.2 手機版應保留的功能清單

**核心（必須）**：
- 聊天介面（chat_screen.dart）
- 語音輸入/輸出（voice/ 16 檔）
- 夥伴系統（companion_* 8 service + 4 screen）
- 橋樑配對（mobile_bridge_client + QR 掃描）
- 設定頁（API Key 輸入、provider 選擇）
- 密碼鎖定

**增強（可選）**：
- 向量資料庫瀏覽（vault_screen 簡化版）
- 成就系統
- SemiDAO 審核
- 盲盒

**不需要**：
- Canvas 工作區（桌面專用）
- 專案看板/關係圖（桌面專用）
- 系統列（桌面專用）
- 檔案總管（桌面專用）
- llama.cpp 本地推理（桌面做）
- 向量嵌入（桌面做）

### 6.3 手機版重整步驟建議

1. **第一步：清理**
   - 刪除 3 個死程式碼檔案
   - 把桌面專用 screen 標記 `// @desktop-only`
   - memory_store.dart 標記 `@deprecated`

2. **第二步：路由分離**
   - 建立手機版專用路由表
   - 桌面/手機共用 screen 提取到 `shared/`

3. **第三步：通訊層測試**
   - 手機版配對桌面端做端對端測試
   - 確認 WebSocket 長任務（taskRun/taskPush）正常

4. **第四步：UI 精簡**
   - 手機版 chat_screen 去掉桌面依賴（如 sidebar）
   - 夥伴系統確認離線可用
   - 語音引擎確認 iOS 權限正常

5. **第五步：獨立能力**
   - 評估手機版是否需要獨立 LLM 呼叫（不經桌面 Gateway）
   - 如果需要：api_service + provider_registry + storage_service 可以直接共用

---

## 七、Service 依賴熱點

被最多檔案 import 的 service（改動風險最高）：

| Service | 被 import 次數 |
|---|---|
| companion_store | 20 |
| bridge_action_executor | 17 |
| brain_database | 17 |
| memory_store | 14 |
| entity_graph_service | 14 |
| digital_asset_registry_store | 14 |
| brain_container_service | 14 |
| project_door_store | 13 |
| storage_service | 11 |
| conversation_store | 11 |

> 改這些檔案前要特別小心影響範圍。

---

## 八、已解決的歷史問題

| 問題 | 根因 | 修復 |
|---|---|---|
| DB 找不到（空 DB） | vault_db_directory unicode escape | PlistBuddy + symlink |
| 嵌入秒說完成 | manifest（21K）不完整，沒查 DB pending（14K） | generateEmbeddings 改用 DB pending |
| SVG 顯示 error | SVG 被歸為圖片送 VisionPipeline | 改走文字嵌入路徑 |
| MiniMax 401 | endpoint api.minimax.chat（錯） | api.minimaxi.chat |
| 外接碟權限每次彈 | ad-hoc 簽名 TCC 不記住 | Full Disk Access |
| Local model 超慢 | 嵌入+聊天搶 llama-server | 確認嵌入用獨立 gemma-300m |
| 進度條不顯示 | 只有按按鈕才顯示 | 始終顯示 + 5秒刷新 |
| cp -R 不覆蓋 | macOS cp -R 行為 | 先 rm -rf 再 cp -R |

---

## 九、檔案索引

### 核心服務（修改頻率最高）
- `lib/services/api_service.dart` — LLM 呼叫
- `lib/services/storage_service.dart` — Key/provider/gateway
- `lib/services/provider_registry.dart` — endpoint 唯一源
- `lib/services/brain_container/brain_database.dart` — 向量 DB
- `lib/services/vector_db/asset_index_service.dart` — 嵌入系統

### Build 相關
- `macos/Runner/Release.entitlements` — 已移除 removable-volumes
- `scripts/post_build_sign.sh` — ad-hoc 簽名
- Build 指令見 `BUILD_SOP.md`

### 手機版配對
- `lib/services/mobile_bridge_client.dart` — 手機端 client
- `lib/services/desktop_bridge_local_gateway.dart` — 桌面端 gateway
- `lib/screens/mobile_bridge_pairing_screen.dart` — QR 配對

---

> **下次手機版重整從這份文件開始。**  
> **Commit**: `6272e50` (架構收斂)  
> **DB**: 25,902 files indexed, 100%  
> **狀態**: 全部服務正常運行
