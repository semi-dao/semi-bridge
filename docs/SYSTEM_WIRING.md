# 八大系統串聯縱覽（System Wiring）— 一個念頭如何流過整顆大腦

> v1.0 · 2026-09-26 · 橋樑（Bridge）— The Covision App for Humans and AI
>
> 單看每個系統都是器官；這份文件畫的是**神經系統**——
> 一句話從嘴巴進來，怎麼被記住、被看見、被把關、被算力餵養，
> 最後變成畫布上的一條連線。八個器官，一條動脈。

---

## 1. 全景圖

```
                    ┌──────────────────────────────────────────┐
                    │              金鑰匙系統（Golden Key）      │
                    │  DataPathGate：所有對外請求的唯一咽喉點     │
                    │  使用者自己的 API key 直連 provider        │
                    └───────▲──────────────────────▲───────────┘
                            │ 攔截/放行              │ 嵌入/推理
     人類                     │                      │
      │ 說                    │                      │
      ▼                       │                      │
 ┌─────────┐  注入脈絡  ┌───────────┐         ┌─────────────┐
 │  對話    │◄──────────│ 向量大腦   │◄────────│  本地模型    │
 │ (chat)  │──────────►│ (vector   │  嵌入    │  (18789)    │
 └────┬────┘  存記憶    │  brain)   │─────────►│ llama-server│
      │                 └─────┬─────┘  蒸餾    └─────────────┘
      │ 人機共視                │ 餵養
      ▼                        ▼
 ┌─────────┐   工作流    ┌───────────┐   規則卡    ┌──────────┐
 │  畫布    │───────────►│ 大腦圖譜   │◄───────────│  羅盤     │
 │ (canvas)│            │ (galaxy)  │───────────►│ (compass)│
 └────┬────┘            └───────────┘  器官健康    └────┬─────┘
      │ MCP 語意工具                                    │ 藥方/規則
      ▼                                                ▼
 ┌────────────────────────────────────────────────────────────┐
 │        向量嵌入（embedding）—— 一切的指紋工廠                │
 │        文字/圖片/畫布 → 768 維向量 → 進大腦容器              │
 └────────────────────────────────────────────────────────────┘
```

---

## 2. 八器官職責卡

| # | 器官 | 一句話職責 | 本體位置 |
|---|---|---|---|
| 1 | **對話（Chat）** | 人與 Agent 的交談面；Agent Loop 的主舞台 | `lib/screens/chat_screen.dart`、`lib/controllers/` |
| 2 | **畫布（Canvas）** | 可視化工作流——節點即指令，連線即資料流；MCP 語意操作（LightUp 的手） | `lib/widgets/canvas/v2/` |
| 3 | **向量大腦（Vector Brain）** | 一切的記憶：對話/檔案/教訓/人格 → 嵌入 → 可檢索 | `lib/services/brain_container/`、`lib/services/vector_db/` |
| 4 | **大腦圖譜（Galaxy）** | 記憶的 3D 星系投影——節點是記憶/資產，飛進去看你的大腦 | `assets/galaxy/`、`galaxy_data_service` |
| 5 | **向量嵌入（Embedding）** | 指紋工廠：文字/圖片 → 向量；本地 18789 優先 | `vision_embedding_pipeline`、`identity_embed_text`、18789 |
| 6 | **羅盤（Compass）** | 人機共視決策中樞：器官地圖+規則中心+軍醫藥箱 | `lib/services/compass/` |
| 7 | **金鑰匙系統（Golden Key / Sovereignty）** | 主權咽喉：你的 key、白名單之外寸步不出、除痕≠刪除 | `lib/services/sovereignty/` |
| 8 | **本地模型（Local Model）** | 本地算力心臟：llama-server 常駐，斷網大腦照活 | `local_model_runtime_service` @ 127.0.0.1:18789 |

![本地 LLM 引擎 · 模型管理](screenshots/local-llm-engine.webp)

<sub>本地模型引擎實機：硬體規格自動偵測、候選模型標「很適合」、下載→驗證→啟用一條龍。記憶的指紋不出機器。</sub>

---

## 3. 一句話的旅程（walkthrough）

使用者輸入：**「幫我把上週討論的施肥方案畫成工作流」**

### 第 1 站：對話（入口）
`chat_controller` 收話 → Agent Loop 啟動。
Agent 動手前，**羅盤軍醫出診**：高風險操作自動 seek 藥方注入 context。

### 第 2 站：向量大腦（回憶）
Agent 查「施肥方案」→ hybrid_search 三路合擊（向量+FTS+五因子重排）
→ 命中上週對話與相關檔案 → 脈絡注入本輪。

### 第 3 站：本地模型（算力）
嵌入與蒸餾走本地 18789 llama-server——**記憶的指紋不出機器**。
需要重型推理時，請求交給金鑰匙。

### 第 4 站：金鑰匙（把關）
DataPathGate 檢查：目標網域在白名單？key 是使用者的？
不在白名單 → **請求根本送不出去**（不是事後通知）。
red 記錄、green 放行——每一筆對外流量都有帳。

### 第 5 站：畫布（動手）
Agent 用 MCP 語意工具蓋工作流（v0.4.0 LightUp 的手）：
`add_node` 建節點、`connect` 連線、`app_tap` 按測試、
`canvas_zoom(fit)` 全覽——**零座標模擬，與 UI 按鈕同一條程式路徑**。

### 第 6 站：向量大腦（再入庫）
工作流存檔 → 增量導入 → 嵌入 → 入庫。
畫布的產出（`vector_sketch_service` 蒸餾）也變成可檢索的記憶。

### 第 7 站：大腦圖譜（投影）
新記憶入庫 → `galaxy_data_service` 餵養 → 3D 星系多一顆星。
使用者飛進 galaxy，**親眼看見自己的大腦今早長了什麼**。

### 第 8 站：羅盤（記帳）
整個過程的工具呼叫成敗入因果帳本；撞牆自動立案坑卡；
器官健康狀態 harvest 更新。**人打開羅盤，看見 Agent 今天做了什麼、
撞了什麼、學了什麼藥。**

一句話，八站，閉環。**沒有一站是旁路——每站都寫回大腦。**

---

## 4. 三條鐵律貫穿全身

### 鐵律一：唯一真相源
- MCP 工具清單 = `_toolSchemas`（v0.4.0 LightUp P0）
- 搜尋 = `VaultSearchFacade` 單一入口
- 規則 = 羅盤 store 唯一寫手，渲染端只讀
- **兩份清單 = 遲早漂移 = 系統對 Agent 說謊**

### 鐵律二：誠實降級
- 眼工具看不見 → `available:false` + 原因（不噴 -32603）
- 沙盒 screencapture 不可用 → 回 hint 指路 `app_look`
- 羅盤錨點過期 → 琥珀色待重新驗證（絕不假裝新鮮）
- UI 壞 token → 紅字失敗（寧紅字不假成功）

### 鐵律三：主權在使用者
- 金鑰是你的，帳目關係就是你的（直連 provider，App 不代管）
- 白名單之外寸步不出（DataPathGate 咽喉點）
- 除痕 ≠ 刪除（清暫存，記憶與向量庫一個位元組不動）
- 破壞性操作權力在使用者（dry-run 預覽 + 確認才執行）

---

## 5. 各系統深入文件

| 文件 | 內容 |
|---|---|
| [COMPASS_SYSTEM.md](COMPASS_SYSTEM.md) | 羅盤：三層所有權、軍醫三件套、人機共視雙向道 |
| [LIFE_TREE.md](LIFE_TREE.md) | 生命樹：歷史樹+反思樹雙幹、精靈儀表、做夢節律——失敗即數位資產 |
| [VECTOR_BRAIN.md](VECTOR_BRAIN.md) | 向量大腦：四種記憶形態、混合搜尋、嵌入管線 |
| [DATA_SOVEREIGNTY_MANIFESTO.md](DATA_SOVEREIGNTY_MANIFESTO.md) | 資料主權宣言：金鑰匙三原則的完整論述 |
| [COVISION_MANIFESTO.md](COVISION_MANIFESTO.md) | 共視宣言：產品定位錨點 |
| [V040_AGENT_AS_USER_DESIGN_INPUTS.md](V040_AGENT_AS_USER_DESIGN_INPUTS.md) | v0.4.0 開光（LightUp）：Agent-as-User 八撞牆點 → API |
| [APP_ARCHITECTURE_MAP.md](APP_ARCHITECTURE_MAP.md) | 人工架構地圖（羅盤的自動版本見 COMPASS_SYSTEM.md） |
