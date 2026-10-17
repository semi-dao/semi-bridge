# 模型下載頁四卡真實性審計報告

- 日期：2026-10-16
- 範圍：bridge_desktop_screen.dart `_activeSystemPage == 'model'`（L5164-5249）四張卡
- HEAD：c0d73121（已用 `pwd && git log --oneline -1` 確認在本尊 ~/Developer/bridge_app）
- 判分：**活**＝綁真實引擎、操作有真實效果；**半活**＝綁了但條件失效時靜默/顯示過時；**死**＝寫死字串、無綁定；**假**＝顯示系統沒有的狀態
- 方法：逐元素追蹤 Widget → service → 真實系統（llama-server 18789/18890/18799、launchd plist、檔案系統、Swift MethodChannel `bridge.desktop_shell.macos.v1`）；關鍵路徑另以 curl / ls / launchctl 實測。

---

## 卡 1：LocalLlmRuntimeCard（lib/widgets/local_llm_runtime_card.dart，1953 行）

資料流主幹：Card → `LocalModelRuntimeService`（local_model_runtime_service.dart）→ MethodChannel `localRuntime`（macos_desktop_shell_channel.dart L128-130）→ MainFlutterWindow.swift `applyLocalRuntime`（L562 起）→ Process 直起 llama-server 18789。狀態非寫死：`inspectBridgeRuntime()` 先問 Swift native state，native 不可用時 fallback 直接 HTTP 探測 18789 `/v1/models`（L297-314）——本機實測 18789 確有 llama-server 應答，鏈路真實。

| 元素 | 資料流 | 判分 | 證據 |
|---|---|---|---|
| 狀態標籤（運行中/已安裝…） | `_runtimeState.phase.label`；來源＝Swift `localRuntimeState` 或 18789 即時 HTTP 探測 | **活** | local_llm_runtime_card.dart L273-276；local_model_runtime_service.dart L286-320 |
| 硬體資訊列 | `MacosDesktopShellChannel.hardwareProfile()` → Swift 原生回報 | **活** | L84、L352；MainFlutterWindow.swift L200-201 |
| Primary 按鈕（啟動/下載） | `primaryCommand` switch → prepareRuntime/downloadModel/startServer/stopServer，全部落 Swift case | **活** | L160-223；MainFlutterWindow.swift L572-658 |
| 下載進度條＋% | Swift URLSession delegate 回寫 `progress` 0-1，Dart 3s 輪詢 | **活** | L471-540（0-1 直用）；MainFlutterWindow.swift L1120-1127 |
| 「已下載」＋實際檔案大小 | Swift `listInstalledLocalModels()` 掃 models/ 目錄實測 bytes | **活** | L810-816、L1320-1380；MainFlutterWindow.swift L2037 起 |
| 「現役模型」標籤/紫色框 | `runtimeState.modelId == modelId`；Swift status 輪詢有「真相自癒」把 title 拉回 activeModelName | **活** | L592、L821-825、L1617-1620；MainFlutterWindow.swift L566-576 |
| 「設為現役」按鈕 | `startServer(modelId:)` → Swift 停舊載新 + 健康檢查 8×3s + `activateBridgeRuntimeAsBrain` 寫 provider | **活** | L827-851、L1591-1610；local_model_runtime_service.dart L467-512 |
| 「測試」按鈕/已驗證標籤 | Swift `testLocalModel`：18799 臨時 server + 真 chat prompt；結果存 manifest.json，掃描時讀回 | **活** | L855-946、L1383-1442；MainFlutterWindow.swift L1740-1861 |
| 「刪除」按鈕 | Swift `deleteLocalModel(modelId:)` | **活** | L950-967、L1666-1682；MainFlutterWindow.swift L649-651 |
| 角色配置雙下拉（夥伴/辨識） | `LocalModelScheduler.setRoles` → StorageService 持久化 | **活** | L643-665；local_model_scheduler.dart L145-157 |
| HuggingFace 熱門模型區 | 直呼 `huggingface.co/api/models`（即時 API，非寫死），依 RAM 過濾 | **活** | L1687-1744 |
| 模型搜尋框 | 同上 API `search=` 即時查詢 | **活** | L1147-1183、L1746-1776 |
| 「多模型並行運算」開關 | **純前端 setState**，無任何 service/engine 綁定；重 build 即重置 false | **死** | L49（`_parallelModeEnabled = false`）、L1512-1519（onTap 只改本地 bool） |
| 「Agent 將可同時使用最多 N 個模型並行處理任務」提示文字 | 隨開關顯示，但後面沒有任何並行調度實作——顯示了系統沒有的承諾 | **假** | L1563-1584 |
| `_getActionColor()`（L454-469） | 定義後全檔無人呼叫（grep 僅定義處） | **死**（死代碼，不影響 UI） | L454-469 |
| `_buildHeader()`（L286-309） | 同上，全檔無呼叫 | **死**（死代碼） | L286-309 |

---

## 卡 2：ModelLabCard（lib/widgets/model_lab_card.dart，620 行）

| 元素 | 資料流 | 判分 | 證據 |
|---|---|---|---|
| 測試引擎 chips | `listInstalledModels()` 掃硬碟動態生成，預設選最小檔；不寫死（僅顯示名 map 有 fallback 原樣顯示 modelId） | **活** | L32-62、L64-72、L420-432 |
| 「開始快測（5 張）」按鈕 | pickRecentPhotos（讀 asset_index DB 實檔）→ B' 案先停主線 18789 釋 GPU → startLabServer(18799) → /health 輪詢 60s → 逐張 `/v1/chat/completions` vision 描述 → 熔斷（連2敗）→ 存報告 → 復活主線 | **活** | L112-171、L182-264；model_lab_service.dart L27-56、L60-103 |
| 進度條/階段文字 | session 靜態欄位跨頁生存，attach/detach | **活** | L88-101、L338-357、L582-620 |
| 「報告（N）」計數 | `loadReports()` 讀磁碟報告檔 | **活** | L302、L106-110 |
| 報告 tile（命中率/速度/RAM） | 由快測實測值算出 | **活** | L475-515 |
| 「採用為現役」按鈕 | stopServer → startServer(modelId) 真實切換 18789 | **活** | L531-540 |
| ⚠️ 「採用」按鈕的 modelId 反推 | 從報告名稱字串猜 id：`name.contains('12B') / contains('E4B')`，其餘（Qwen3.5-4B 等）回 `null` → 按鈕**不渲染** | **半活** | L518-529 |
| 「跑全測」dialog 按鈕 | onPressed 只跳 SnackBar「全測引擎下一版上線」＋ TODO 註解 | **死**（按鈕有意義但功能未接——已明示，屬誠實佔位） | L361-386 |
| `_QuickTestSession._aborted` | session 有 `isAborted` 回呼參數，但 `_runQuickTestBody` 全程**從不檢查** `isAborted()`——中止機制接了線沒通電 | **死**（死參數） | L122（參數宣告）、L616（唯一傳遞處，body 內零使用） |

---

## 卡 3：BrainModelDownloadCard（lib/widgets/brain_model_download_card.dart，484 行）

| 元素 | 資料流 | 判分 | 證據 |
|---|---|---|---|
| 狀態 chip（已安裝/未安裝/下載中） | `FlutterGemma.hasActiveEmbedder()`；進度聽全域 `EmbeddingProgressTracker.downloadStream`（頁面切換不丟） | **活** | L51-79、L94；embedding_model_manager.dart L102 |
| HF Token 欄＋「下載並安裝模型」 | `installModel()` → flutter_gemma installEmbedder().modelFromNetwork(tflite) → 存檔＋熱載入 EmbeddingService | **活** | L108-154；embedding_model_manager.dart L115-154；tflite 實測存在於 ~/Library/Application Support/farm.semiwasabi.bridgeApp/flutter_gemma/ |
| 進度條兩條（模型/分詞器）＋% | onModelProgress/onTokenizerProgress 即時回呼 + tracker stream | **活** | L323-407；tracker L120-132 |
| 「模型版本: gemma-300m-v1」 | `EmbeddingService.currentModelVersion` 寫死常數——但系統實際雙 backend，**EG2 上線時真版本是 `eg2-300m-v1`** | **半活→偏假** | L314；embedding_service.dart L33（300m 常數）、L38（eg2 版本）、L220-221（activeModelVersion 才是真話） |
| 「向量維度: 768 維」 | 常數，與 flutter_gemma/EG2 實際輸出一致 | **活**（巧合地正確） | L315；embedding_service.dart L43 |
| 「模型大小約 192 MB」/「~187 MB」 | 寫死字串，無法得知實際 | **半活**（資訊性，不下載無感） | L331、L476 |

---

## 卡 4：EmbeddingModelStoreCard（lib/widgets/settings/embedding_model_store_card.dart，308 行）＋ EmbeddingModelCatalogService（339 行，昨日新上）

| 元素 | 資料流 | 判分 | 證據 |
|---|---|---|---|
| 「現役：xxx.gguf」標籤 | 讀 launchd plist `farm.semiwasabi.bridgeApp.eg2` 的 -m gguf 路徑（真檔案真 regex），10s setState 刷新 | **活** | card L54-57、L147-159；service L196-207；plist 實測存在且 regex 命中 |
| 目錄五檔 | catalog 常數列表，下載 URL 已逐一 curl 驗證全部 206 可下載 | **活** | service L54-125 |
| 「已下載」判定 | `File(modelsDir/fileName).existsSync()` 檢查**主檔＋mmproj 兩個都在** | **活** | service L132-134 |
| 下載按鈕＋進度條 | `curl -L --fail --retry 3 -C -`（真續傳）寫 models/ | **活** | service L161-193 |
| 測試按鈕（測已下載檔） | 18899 起臨時 llama-server（真 binary 路徑 `models/../runtime/bin/llama-server`）跑 3 組中文同義對 cosine | **活** | service L242-296 |
| 測試按鈕（未下載→測現役 18890） | 直打 18890 `/embeddings`（實測應答正常） | **活** | service L267、L298-312 |
| ⚠️ quickTest 18899 啟動失敗路徑 | `for i in 0..29`：health 失敗會在最後一圈 `i==29` 回傳失敗——但**臨時 server 沒人在迴圈外 kill**（只有 `finally { p?.kill() }` 救得回來；若卡在 health 迴圈 return，`p` 非 null，finally 會 kill——此路 OK）。**真問題**：`llama-server` binary 不存在時 `Process.start` 拋例外 → catch 回「測試失敗」，OK；但 **18899 埠被佔**時 health 會通過（別人的 server），測的是未知引擎 | **半活** | service L257-265（迴圈）、L293-295（finally kill） |
| ⚠️ mmproj 選擇邏輯 | `modelPath.contains('Q8_0') ? mmproj-Q8_0 : mmproj-F16`——**Q6/Q5/Q4_K_XL 檔名字串不含 "Q8_0"**，走 F16，OK；但若未來有 "Q8" 以外變體會誤配。且 F16 測試條目要求下載 955MB mmproj 才算「已下載」（mmproj 實測 980,895,232 bytes ≈ 935MB） | **半活** | service L247-250 |
| ⚠️ switchPrimary plist regex | `RegExp(r'(<string>)([^<]*embeddinggemma[^<]*\.gguf)(</string>)')` 只換**第一個** embeddinggemma 字串——實測 plist 第一個 embeddinggemma 字串確實是 -m 路徑（Label 是 farm.semiwasabi.bridgeApp.eg2 不含 embeddinggemma）→ 目前 plist 結構下正確；但 `[^<]*` 遇到含空格路徑沒問題、遇 plist 重排（Label 改名）即靜默失敗回 false（有 SnackBar 提示，非靜默） | **活（脆弱）** | service L219-227；plist 實測 |
| ⚠️ switchPrimary 後 UI | 只 SnackBar；無全庫重嵌自動觸發（dialog 有誠實告知要手動去向量頁觸發） | **半活** | card L118-128、L94-99 |
| 「設為主力」按鈕 | `launchctl kickstart -k gui/$(id -u)/farm.semiwasabi.bridgeApp.eg2`（實測 launchctl list 有此服務，PID 15521） | **活** | service L229-233；launchctl list 實測 |
| 「現役主力 ✓」標籤 | `activeFile == e.fileName` 比對 plist 真路徑 | **活** | card L179、L276-280 |
| 下載中 % | curl stderr regex `(\d+)%`——curl 非互動模式下**不輸出 % 進度**（無 `-#`），stderr 進度表預設關閉 → **進度條實際上幾乎不動，直接 0% 跳 100%** | **半活（接近死）** | service L178-186（無 `--progress-bar` 旗標） |
| `_testResults` 測試結果文字 | `r.detail` 真實數值（cosine 平均） | **活** | card L228-237；service L284-290 |

---

## 總結：死/假/半活清單＋修復建議

### 🔴 假（顯示系統沒有的狀態）— 1 項
1. **LocalLlmRuntimeCard「多模型並行運算」開關＋「Agent 將可並行處理任務」提示**
   - 證據：local_llm_runtime_card.dart L49、L1512-1519、L1563-1584
   - 修法：短期移除整個 `_buildParallelModeSwitch` 區塊（或加「實驗性（未接線）」標籤並預設隱藏）；長期接 LocalModelScheduler 或 ProviderRouter 真並行調度。

### 🔴 死（寫死/無綁定）— 3 項
2. **同上開關本身**（與假一體兩面）——onTap 只 setState 本地 bool。
3. **ModelLabCard `_QuickTestSession._aborted` / `isAborted`**：中止旗標從未被消費。證據：model_lab_card.dart L122、L616。修法：在 `_runLabTest` 每張照片迴圈開頭 `if (isAborted()) break;`，並提供 UI 中止鈕；否則刪參數。
4. **ModelLabCard「跑全測」按鈕**：只有 SnackBar＋TODO（L361-386）。屬已宣告佔位——建議按鈕加「（未開放）」disabled 樣式，避免使用者期待。
5. **（死代碼，非 UI 風險）**`_getActionColor()` L454-469、`_buildHeader()` L286-309 無人呼叫，可刪。

### 🟡 半活 — 6 項
6. **EmbeddingModelStoreCard 下載進度條**：curl 進度 regex 抓不到輸出（stderr 進度表預設關閉）→ 進度恆 0，完成直接消失。修法：curl 加 `--progress-bar`，或改讀 `-o` 檔案已寫入 bytes / total（`curl -w` 或 stat 檔案）。證據：embedding_model_catalog_service.dart L171-188。
7. **BrainModelDownloadCard「模型版本: gemma-300m-v1」**：EG2 優先時這是謊報（真值 `eg2-300m-v1`）。修法：改用 `EmbeddingService.instance.activeModelVersion`（embedding_service.dart L220-221 已備好真話 getter）。證據：brain_model_download_card.dart L314。
8. **ModelLabCard「採用為現役」只認 12B/E4B 字串**：Qwen3.5-4B 快測報告不會出現採用鈕。修法：report 物件加 `challengerModelId` 欄位，取代名稱字串反推。證據：model_lab_card.dart L518-529。
9. **quickTest 18899 埠碰撞**：埠被佔時 health 通過，測到未知引擎。修法：起 server 前先確認 18899 無人聽，或 health 後加 `props` 檢查 model path 含預期檔名。證據：embedding_model_catalog_service.dart L243-265。
10. **switchPrimary regex 脆弱**：依賴「第一個含 embeddinggemma 的 <string> 即 -m 路徑」的 plist 排版慣例。修法：改逐行解析 ProgramArguments array（定位 `-m` 後一個 <string>），或整段重寫 array。證據：embedding_model_catalog_service.dart L219-226。
11. **switchPrimary 不觸發重嵌**：血型不一致窗口靠使用者手動去向量頁補（dialog 有講，但容易忘）。修法：switch 成功後直接叫 Eg2ReembedService 排程（或至少發通知）。證據：embedding_model_store_card.dart L118-128。

### 其他觀察（不計分）
- BrainModelDownloadCard（tflite 備援）與 EmbeddingModelStoreCard（GGUF 主力）並列會讓使用者困惑「已安裝」兩套模型的關係——card 註解已自承「保留給 tflite 備援」（embedding_model_store_card.dart L3），建議在 UI 上標明主/備。
- 卡 1~4 的狀態來源全部是**即時探測或磁碟/plist 真讀取**，沒有發現寫死的「運行中」狀態標籤；「半活」集中在上列條件性失效場景。

### 最緊急修的三件事
1. 移除/隱藏「多模型並行運算」假開關（唯一「假」級，直接誤導使用者）。
2. EmbeddingModelStoreCard 下載進度條修 curl 進度（新功能昨日上線，進度條現在是擺設）。
3. BrainModelDownloadCard 版本標籤改 `activeModelVersion`（一行修，消除版本謊報）。
