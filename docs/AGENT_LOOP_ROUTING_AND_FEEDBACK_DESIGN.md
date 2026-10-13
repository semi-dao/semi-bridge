# Agent Loop 模型路由與回饋 — 使用者 設計意圖 (2026-08-07)

## 設計目標

Bridge App 的 Agent Loop 要做到：

1. **指定模型模式**：使用者選了具體 provider → 整個對話鎖定該 provider，**不分派子代理、不換模型、不切換本地/雲端**。除非該 provider 額度耗盡，否則一路走到底。
2. **預設模式**：使用者選了「預設」 → 走 Agent Loop 自由調配（多模型協同、本地優先、分派 sub-agent 等等），這是「雞尾酒模式」，是 Bridge App 的智慧結晶。
3. **兩種模式都不能卡住**：必須有即時進度回饋，使用者隨時知道 Agent 在幹嘛。
4. **明確失敗**：模型沒額度 → 立即回報「額度耗盡，請到設定換 provider 或加額度」，不要默默 retry。

## 三個關鍵修正

### 修正 1：預設模式不要卡住（最高優先）

**現狀問題**：
- Agent Loop 內部派 sub-agent → sub-agent 用本地模型 → 本地 server 沒回應 → 120 秒 timeout
- Gemini response 慢 + sub-agent timeout 累積 → 整體卡 3 分鐘沒結果
- 使用者看著黑箱等，沒有任何回饋

**修正方向**：
- 加 timeout 防護：每個 LLM 呼叫獨立 timeout，超時立即回報
- Agent Loop 進度必須即時 stream 到 UI：「正在分派 sub-agent...」「子代理用本地模型搜尋中...」「sub-agent 1/3 完成」
- 卡住時主動說「目前卡在 X，請問要繼續等待還是切換策略？」

### 修正 2：指定模型模式嚴格執行

**現狀問題**：
- 使用者選 Gemini → Agent 根據 prompt 自動分派 sub-agent → sub-agent 跑本地模型 → 違反使用者意圖

**修正方向**：
- 「指定模型」session：Agent 不分派 sub-agent，所有 LLM 呼叫都走指定 provider
- 「指定模型」session：使用者可以主動切換 provider（同一對話內換模型），換了之後從下一輪起鎖定新 provider
- Provider 額度耗盡：立即回報，不默默 fallback

### 修正 3：測試驅動開發

**現狀問題**：
- 每次實機測試要 3 分鐘 → 失敗 → 回報 → 修 → 再實機測試 → 浪費時間

**修正方向**：
- 在 Bridge App 程式碼內建立**模擬對話環境**：可以在背景跑 Agent Loop，不需要使用者互動
- 自動跑一系列測試場景：
  - 「選 Gemini → web search → 生圖」完整流程
  - 「選預設 → 多模型協同」雞尾酒模式
  - 「指定本地模型 → 額度耗盡 → 回報」
- 跑完產出測試報告：哪些通過、哪些卡住、哪裡 timeout
- 主 agent 看報告再決定要不要讓 使用者 實機測試

## 工程任務清單

### P0.5c：測試環境（最高優先）

建立 `tool/test_agent_loop.dart` 或 `test/integration/agent_loop_test.dart`：
- 可在背景執行 Agent Loop
- 模擬使用者輸入
- 捕獲所有 sub-agent 呼叫、timeout、進度事件
- 產出結構化測試報告

### P1：Agent Loop 進度回饋

- 修改 `AgentLoop.run()`：每輪開始時 emit 進度事件
- 修改 `DelegateSubagentTool.execute()`：開始/結束時 emit 進度
- 訂閱進度事件到 UI（腦反射面板或底部狀態列）

### P2：指定模型模式鎖定

- 在 `ChatController` 加 `providerLock` 概念
- 傳到 `AgentLoop.run()` → 限制 `delegate_subagent` / `delegate_batch` 的可用 provider
- 修改 prompt builder：根據 `providerLock` 動態調整「省 token 原則」

### P3：雞尾酒模式優化

- 預設模式保留 sub-agent 編排
- 但加 timeout 防護 + 進度回饋
- 失敗時優雅降級而不是默默卡住

## 驗收標準

| 場景 | 預期結果 |
|---|---|
| 選 Gemini → 說「生一張圖」 | Gemini 圖片生成，全程不走本地 |
| 選 Gemini → 說「上網查資料再生成圖」 | Gemini 完成網搜（透過 Gemini 自帶 web search）+ Gemini 生圖 |
| 選預設 → 說「上網查資料再生成圖」 | 多模型協同：本地搜尋 + Gemini 生圖（有效率） |
| 選預設 → 任意任務 | 最多 30 秒內必須有進度回饋 |
| 任何場景遇到 timeout | 立即回報「X 卡住了」，不默默 retry |
| 指定 provider 額度耗盡 | 立即回報，不 fallback 到其他 provider |

## 設計哲學

> 簡單的事情簡單做：選誰就走誰。
> 複雜的事情交給雞尾酒：選「預設」就是相信 Agent 的智慧調配。
> 不論哪種，使用者永遠看得到當下在做什麼。
