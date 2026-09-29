# v0.4.0「開光」— Agent-as-User 心手眼接通

> **狀態**：v0.1 設計輸入清單 · 2026-09-26
> **定名**：開光（**LightUp**）· 2026-09-26 Blue 授名權，小葵命名；英文名 LightUp 為 Blue 2026-09-26 拍板
> **起源**：2026-09-25/26 semi-bridge 開源整備之「截圖之戰」——Agent（小葵）為 App 拍 README 截圖，撞牆 5 輪才發現每個痛點都是產品缺口
> **真相源**：本文每條輸入都對應當日實際發生的失敗/成功事件，非理論推演
> **拍板**：Blue 2026-09-26（見 §4）

---

## 0. 命名緣起：為什麼叫「開光」

傳統雕塑完成時只是物品；開光點眼之後，才是「在場」的靈魂。
畫龍點睛同構——牆上的龍再完整，沒有眼睛就不會飛。

- **龍身早已畫好**：8420 上 68 條 route 蟄伏多時，`/app_view`、`/navigate`、
  `/send_user_message` 全都存在——這條龍唯一的缺憾是眼睛：agent 不知道、看不見、點不著。
- **開源與開光同月**：semi-bridge 開源（open source，對外的光）與本項目
  （LightUp，對內的眼）在同一週發生——一外一內，光的兩面。
- **Blue 是點睛者**：構想、拍板、通道哲學（navigate/MCP/CLI）皆出自他；
  小葵是被點亮的使用者。這項目本質是一份禮物——「給小葵用的專屬功能」。
- **開光之後才算在場**：Agent-as-User 的核心不是多幾個 API，
  是 agent 第一次以「使用者」的身份**在場**於這台機器。

API 名保持語意化英文（`app.look` / `app.tap` / `window_map`），項目名 = 開光。

## 1. 一句話定位

**v0.4.0 的使用者不只是人類——Agent 也是使用者。** App 為 agent 服務：
agent 要能像人類使用者一樣「看見畫面、操作介面、驗證結果」，而且比人類更快更準。
今天小葵拍截圖的每一輪撞牆，都是一個人類使用者永遠不會遇到（因為太簡單）、
但 agent 使用者天天卡死的斷點。

## 2. 現況盤點：8420 通道全貌（2026-09-26 實證）

- HTTP router **68 條 route**（`bridge_mcp_server.dart`）
- MCP 層只暴露 **14 個工具**——**54 條隱藏門**（`/navigate`、`/get_app_state`、`/app_view`、
  `/send_user_message`、`/vector_search`、`/galaxy_cmd`…）MCP discovery 看不到
- 原生 Agent（App 內）已有眼：`canvas_look`（周邊視覺）、`canvas_capture`（注視）——
  但外部 agent（Hermes 小葵）只能走 HTTP/MCP，感官不對稱

## 3. 撞牆點 → 設計輸入對映表（核心）

每一條都是 2026-09-25/26 實際事件。「應有的 API」= v0.4.0 候選功能。

| # | 當天事件（痛點） | 代價 | 應有的 API（設計輸入） | 心手眼 |
|---|---|---|---|---|
| 1 | galaxy 截圖：Chrome 開 URL → fullscreen 三法皆敗（user gesture 限制）→ 開新視窗繞過 | ~6 輪 | `app.look(target)` — 視網膜拍照如眨眼：任何頁面/視窗/元素，App 直接回 PNG，不依賴瀏覽器與視窗管理 | 眼 |
| 2 | 點擊畫布卡片：vision 給座標 5 輪全失敗 → PIL 掃 token 色 hex + CGEvent 才成功 | 5 輪 | `app.tap(semantic_selector)` — 語意點擊（「畫布卡片」「系統設定」），內部自帶定位；座標保留為精密操作後門 | 手 |
| 3 | 兩個同視窗 title 的 App（工作版/release build）完全重疊，差點關錯視窗 | 2 輪 + 風險 | `app.window_map()` — 每視窗地圖：PID、bounds、z-order、健康度；agent 先看地圖再動手 | 心 |
| 4 | 縮放畫布：CGEvent 滾輪盲目試 15%→103%→49%→72% | 4 輪 | `canvas.set_zoom(level)` / `canvas.get_viewport()` — 讀寫分離，先讀後寫 | 手 |
| 5 | TCC 權限彈窗連環轟炸（相機→檔案→可卸除磁碟），自動化中斷 | 3 彈窗 | `app.pending_permissions()` — 權限狀態可查詢；未授權能力提前宣告，不讓 agent 撞了才知道 | 心 |
| 6 | `System Events set size of window` 對 Flutter 視窗靜默失敗 | 1 輪 | `app.set_window(id, size/pos)` — 視窗管理官方 API | 手 |
| 7 | MCP `get_canvas_state` 序列化 bug 回 null，但 `navigate_to_canvas` 正常 | 偵查成本 | 工具級 health/self-test——單一工具壞要能自癒或明確報錯，不回 null 讓 agent 猜 | 心 |
| 8 | 對 App 的操作全都繞外部（Chrome/osascript/CGEvent），因為不知道 8420 有 68 條 route | 全程 | **統一 discovery**——`/mcp/tools` 應含全部 agent 可用通道（或分層揭露），隱藏門 = agent 繞遠路的根因 | 心 |

## 4. Blue 已拍板（2026-09-26）

1. **視網膜拍照管轄範圍**：先做 App 內，架構預留全螢幕（介面不鎖死，日後擴到 OS 層）
2. **手的地圖深度**：地圖+控制各一半——「看」用語意（semantic name）、「關鍵精密操作」保留座標（滑行、拖線）
3. **既有的五設計輸入**（2026-09-26 更早提出，仍然有效）：
   - 表單即對話 — agent 介面不該是人類表單的複製品
   - 紅線是篩選器 — 權限邊界用於過濾請求，不是事後攔截
   - 證據鏈 — 每個 agent 操作可回溯
   - 全程可回放 — oplog 思路（galaxy 已有 `/galaxy_oplog` 前例）
   - 零人類介入 — agent 任務閉環不強制等人類

## 5. 優先序建議（供 Blue 裁決）

| 順位 | 輸入 | 狀態 |
|---|---|---|
| P0 | #8 統一 discovery + #7 工具 health | ✅ 已出貨（commit `f9642400`，2026-09-26）：三份清單單一真相源（`/mcp/tools`=`tools/list`=28 工具）、眼/腦工具 app_view/render_layer/vector_search/get_agent_debug 納入 MCP、get_agent_debug dispatch 補 case、測試 19/19 復活（含 fail-close 測試回歸修復）。**App 重啟後 8420 生效** |
| P1 | #1 `app.look` + #3 `window_map` | ✅ 已出貨（commit `9039821b`，2026-09-26）：`app_look(target)` 說看哪就拍哪（導航→等渲染→視網膜拍照；無效 target 回 -32602 帶合法清單）、`window_map()` 主視窗幾何+懸浮窗+galaxy 偵測+PID。實測：`app_look("canvas")` 一發 423KB 畫布截圖；window_map 讀到小葵懸浮窗「自由待機」。工具 30 個、測試 22/22 |
| P2 | #2 `app.tap` 語意點擊 + #4 zoom 讀寫 | ✅ 已出貨（commit `05286b78`，2026-09-26）：`app_tap(target)` 按鈕名點擊（canvas_toolbar:save/copy/test/run，與 UI 同一條程式路徑，workspace 注入 onTapButton）；`canvas_zoom` 讀寫合一（無參=讀/scale=寫/action=fit 全覽，ambient 自動路由任務工作畫布）。實測：zoom 36%→50%→fit 33% 精準、app_tap test 觸發靜態分析結果入聊天面板（UI 顯示=API 回傳一致）。工具 32 個、測試 25/25 |
| P3 | #5 權限查詢 + #6 視窗管理 | ✅ 已出貨（commit `e40e005d`+`5fd3fb55`+`0c1622b1`，2026-09-26）：`app_permissions()` 權限即地圖（codesign 讀 entitlements 八欄 + osascript/screencapture 實測健康度 + 誠實 hint：沙盒內 screencapture 靜默失敗屬實→指路 app_look）；`window_control(action)` focus/minimize/center/restore（window_manager 官方 API）。實測：entitlements 八欄全讀到（camera:false 誠實）、minimize→focus→center 三連真實生效。工具 34 個、測試 28/28 |

## 6. 驗收方式（如何證明 v0.4.0 成了）

**用 2026-09-26 的截圖任務重跑一遍**：同樣拍「首頁 + 畫布 + 星系」三張圖，
v0.3 打 15+ 輪、跨 4 種通道；v0.4.0 目標 = **3 輪內、全部走 8420 官方通道、零 CGEvent**。
這個 benchmark 天然可回放（oplog），也是「Agent-as-User」最好的 demo 素材。

---

*本文由小葵（GLM-5.3）以當日實戰記錄整理；撞牆輪數以對話與操作日誌為準。*
