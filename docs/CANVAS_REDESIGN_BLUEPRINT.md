# V2 畫布改版工程藍圖 v1.0（2026-08-15）

> 依據：三路深度體檢（互動層/controller/節點執行）× ComfyUI 架構研究 × 使用者痛點 × 2026 節點編輯器趨勢

## 體檢發現總覽

- 互動層 12 項問題（高 1、中 6、低 5）
- controller/undo/持久化 10 項（嚴重 4、中 3、輕 3）
- 節點執行 13 項（P0 3、P1 5、P2 5）
- **合計 35 項**，其中重疊者（自連、單一連入）合併

## 五大結構性根因（不是零散 bug，是設計問題）

1. **執行狀態管理缺失** — 無 `isExecuting` 鎖定、無並發防護、無參數預驗證
2. **連線驗證在錯誤的層級** — 型別匹配函式存在但 UI 拖曳不呼叫；循環偵測只在執行時
3. **狀態變更入口不單一** — 中鍵平移繞過 controller、多選拖曳無群拖、快照時機錯誤（updateNodeParams 快照到修改後狀態）
4. **disconnect 與 DB 不同步** — 刪線後 relation 殘留 DB，重載「復活」
5. **Timer/生命週期清理不全** — _persistTimer、_scheduleSyncTimer、_entityGraph 引用

## 改版 Phase 計畫

### Phase 1 地基修復（先做，擋在所有功能前面）
1. controller 收斂所有狀態變更（中鍵平移走 controller、快照時機統一「先快照再改」）
2. disconnect 同步 removeRelation
3. dispose 清理全部 timer + 引用
4. 節點執行鎖（isExecuting）+ 並發防護 + ServiceRegistry 失敗提示
5. 連線驗證上移到 UI 層：自連拒絕、型別匹配呼叫、循環即時預警（紅虛線）
6. 節點 ID 改 UUID

### Phase 2 地板功能補完
- 複製/貼上/全選/fitToView（TODO 補完）
- 框選群拖（多選一起移動）
- 雙指縮放 focalPoint 座標修正 + 節點拖曳邊界限制
- 鍵盤：Delete/Escape 在互動層處理

### Phase 2.5 連線互動 UX 完整設計（使用者 2026-08-15 指定 ⭐）
> 「我連好好接一條線都困難，也不知道如何分離連線，什麼類型可以相連」

> **使用者 08-15 決策：操作互動直接抄 ComfyUI 規範**（不自行設計每個滑塊/連線/斷線行為）。
> 校準依據：docs.comfy.org/interface/shortcuts + lite-graph settings。

**ComfyUI 操作規範校準表**（✅=已符合 ⚠️=部分 🔴=缺）：

| 操作 | ComfyUI 標準 | 我們現況 |
|---|---|---|
| 拖曳連線 | 拉出後 release 在空處 → 彈出「相容節點快選」context menu（預設） | ✅ 已有拖曳+型別引導（2.5-B）；🔴 release 空白處的相容節點快選 |
| 斷線 | 拉開 input 端 | ✅ 已有（2.5-C） |
| 節點多選 | Ctrl/Cmd+Click 累加；框選 | ✅ Shift+Click；⚠️ Ctrl+Click 未支援 |
| 群拖 | Shift+Drag | ⚠️ 框選後群拖部分 |
| 鍵盤 | Delete/Backspace 刪除、Ctrl+Z/Y undo、Ctrl+A 全選 | ⚠️ Delete 曾因誤刪移除；🔴 Ctrl+A/Ctrl+Y |
| 執行 | Ctrl+Enter | 🔴 |
| Mute/Bypass | Ctrl+M / Ctrl+B（節點跳過執行） | 🔴 值得抄（排查工作流神器） |
| 貼上 | Ctrl+C/V（含「保留未選節點連線」變體） | 🔴 |
| 雙擊空白 | Quick search 加節點 | ✅ 已有（NodeSearchBox） |
| Space 按住 | 平移畫布 | ✅ 中鍵平移（等效體驗） |
| 縮放 | 滾輪／觸控板捏夾；`.` fit view | ✅ 滾輪；🔴 `.` fit |
| 中鍵 | 建 Reroute 節點（ComfyUI 設定） | ⚠️ 我們中鍵=平移（維持——桌面 APP 更直覺） |
| 刪節點保留連線 | Keep all links（自動 rewire） | 🔴 值得抄 |
| Ctrl+G | 群組 frame | 🔴（Phase 4+） |

**極客大神優化提案**（2026 檢閱：React Flow 12 / ComfyUI Nodes 2.0 / Figma-Miro 慣例）：

| 提案 | 來源 | 採用決定 |
|---|---|---|
| **connectionDragThreshold** | React Flow 12.8 | ✅ 抄——拖線需移動 ≥5px 才啟動，點擊 port 不再誤觸發（直接對症「點選變拖線」） |
| **Easy Connect（整節點邊緣可接線）** | React Flow 官方範例 | 📌 評估中——節點整條左/右邊都是把手，不再只有小圓點 |
| Delete Middle Node（刪中間節點自動 rewire） | React Flow 官方範例 | ✅ 已在校準表（同 ComfyUI Keep all links） |
| Helper Lines 對齊線＋吸附 | React Flow Pro | 📌 Phase 2 排隊（排版整齊感） |
| Space 按住平移（Figma/Miro 標準） | Figma 慣例 | ✅ 補進快捷鍵批次 |
| Mini Map 小地圖 | ComfyUI 2026 前端 | 📌 大畫布導航用，Phase 4 |
| Subgraph 子圖（選取打包成超級節點） | ComfyUI 穩定版 | 📌 Phase 4+（等同我們 subWorkflow 節點的 UI 化） |
| **Linear Mode 線性模式**（畫布↔清單雙視圖） | ComfyUI Nodes 2.0 路線圖 | 💡 長期——我們的 chat_panel 已是雛形，未來可做「畫布⇄對話」同步切換 |
| Connection Limit（port 連線數上限可設定） | React Flow isConnectable | ✅ 已有單一連入規則 |

**A. 型別可視化（看就知道能接什麼）** ✅ 已上線
- 5 種資料型別各有固定色彩：text/image/audio/video/any
- port 圓點、port 標籤、連線曲線**同色**——看到線的顏色就知道流的是什麼
- 節點卡片上型別 badge

**B. 連線拖曳引導（接線不困難）**
- 從 port 拖出時：**只有型別相容的目標 port 亮起，其餘變暗**（一眼看到能接哪）
- 拖曳中的臨時線即時變色：懸停相容 port = 綠、不相容 = 紅
- 鬆手在無效位置：線**動畫彈回** + 一句話提示（「image 輸出不能接 text 輸入」）
- 自連/成環：即時紅色警示，不放進去

**C. 斷線手勢（分離連線）**
- 拖曳連線的「input 端」往外拉 = 解除（業界標準，Blender/Unreal 同款）
- 點擊連線選取 → Delete 刪除
- 右鍵連線 → 選單（刪除/從此線出發新增節點）
- 連線中點 hover 顯示斷線 icon

**D. 執行流動感（工作流跑起來要有生命）**
- 連線光點流動動畫（資料正在流的視覺化，回收 canvas_effects_layer 設計）
- 節點執行狀態三段式：待執行（暗）→ 執行中（脈動光圈＋進度）→ 完成（綠勾＋結果預覽淡入）
- 錯誤節點紅色抖動 + 錯誤訊息 tooltip
- 預覽即時不卡頓：節點結果區域性更新（只 rebuild 該節點，不重繪整張畫布）

**E. Agent 定製工作流（殺手級：AI 幫你搭，你自由改）**
- 對話面板說需求 → Agent 透過 MCP 畫布工具直接生成節點+連線+預設參數
- 生成過程共視：使用者看著節點一個個落下、連線一條條接上（Agent 游標 + 放置漣漪，回收 canvas_effects_layer）
- 生成後 Agent 說明架構 + 使用者可手動微調任何部分
- 銜接 Phase 4 AppInfo：搭好的工作流 → 一鍵分享

### Phase 3 互動測試套件（改版保險）
- 自動化模擬：拖曳/連線/縮放/undo/多選/執行
- 每次改版跑一遍，防止 ComfyUI 式「更新即爆炸」

### Phase 4 Mixlab 五大功能
1. **AppInfo 式分享**：畫布 → 一鍵變 App（SemiDAO 社群殺手級）
2. **優雅降級註冊**：缺服務節點變灰＋安裝引導（Phase 1-4 順帶解決）
3. **即時觸發節點**：檔案監看、螢幕分享、事件源
4. **新節點群**：去背（BackgroundRemover service 直包）、ClipInterrogator、批量 Prompt
5. **右鍵 AI 補全**：節點參數欄位 → LLM 補全（配合夥伴人格）

## 參考文獻
- Inside ComfyUI: Architecture and Runtime Logic（2026-04）— kernel/shell 分離、partial rerun、四層表示法
- comfyui-mixlab-nodes（1.9k stars）— Workflow-to-APP、優雅降級
- React Flow build-vs-buy 演講 — 「畫布是 solved problem，差異在周圍應用」
- ComfyUI issue #12985（更新即爆炸）、ordinaryanimator 版本地獄文
- 體檢完整報告：~/.hermes/cache/delegation/subagent-summary-{0,1,2}-20260815_*.txt
- 節點執行深析：NODE_EXECUTION_DEEP_ANALYSIS_20260815.md
