# CAD 線技術偵察備忘 — text-to-cad 與 cad-1000-hours

> 日期：2026-10-17 ｜ 評估者：小葵（session：評估 text-to-cad 開源項目價值）
> 性質：技術偵察（tech-scout）結論存檔——供未來 Tier 3 runtime 插槽設計與 CAD 工作線直接接手。
> 本文不改任何代碼；純登記評估結論與差距分析。

## 1. earthtojake/text-to-cad（MIT，13.7k⭐ / 1.4k fork / 970 commits）

**本體**：agent skills 函式庫（12 個 skill），不是傳統軟體。三層架構：
skills（SKILL.md 指示）→ cadgen runtime（Python + build123d + OpenCascade 幾何核心）→ CAD Viewer（瀏覽器預覽，需 Chromium）。

Skills 清單（2026-10-17 實跑 `npx skills add earthtojake/text-to-cad -l` 清點，12 個）：
cad / cad-viewer / dxf / urdf / srdf / sdf / step-parts / gcode / bambu-labs / dfam-check / implicit-cad / sendcutsend。

**關鍵定性**：走「Code-first」路線——agent 寫 Python 產生真 BREP 實體（STEP/STL/3MF/DXF/GLB），非三角網格湯。改不了商業軟體私有格式（.dwg/.rvt/.sldprt 讀不了）。

**對我們的價值**：
1. 農場加工件生成（竹構接頭、支架）——一句話出 STEP 送加工/列印
2. dxf skill × 我們的 cad-drawing-verification skill = 生成＋核對閉環（外部沒有的組合）
3. 插槽系統的教科級「未來 Tier」需求案例（見 §3）

## 2. markov-ai/cad-1000-hours（HF dataset，548 likes）

**本體**：509 任務 / ~1,018 小時真人操作商業 CAD 的螢幕錄影＋逐幀鍵鼠事件資料集。
每任務：clip.mp4 + frame_events.json + narration.json + task_desc.json + **rubrics.json**（評分標準）+ input_files + output_files。

- 軟體：AutoCAD / Revit / SolidWorks / SketchUp / CATIA / NX / V-Ray（100% Windows）
- 領域：建築製圖 55.6% / 機械 CAD 19.3% / 室內 10.9% / BIM 8.9%
- 產出：.dwg 317、.sldprt 149、.rvt 24…
- 已知問題：HF dataset viewer 壞（DatasetGenerationError）；Mac 無法重放（Windows 軟體）

**與 text-to-cad 的關係**：互補非接線。GUI-first（教 AI 開軟體點滑鼠）vs Code-first（寫 Python 產幾何）。GUI 路線唯一能碰「改既有私有格式檔」——正是 Code 路線的死角。

**對我們的輔助價值（按 CP 排序）**：
1. 驗證 computer-use-harness（Vision OCR＋cliclick 代操）的行業方向——其 schema（錄影＋逐幀事件＋rubrics）＝業界 GUI-agent 資料標準形狀，與我們同構
2. `rubrics.json` ×509 = 未來 CAD 代操驗收 rubric 的現成範本語料
3. `narration.json`/`task_desc.json` = CAD 領域知識卡候選（H2 管線，Mac 可做）
4. 不做：拿來訓練/微調模型（算力＋Windows 大工程，離主權姿勢的本地噸位太遠）

## 3. ★插槽系統差距分析（本備忘核心）

用「適配判準三分法」（10-08 Compositor 案定型）走查：**text-to-cad 不跑在瀏覽器裡 → 原生機器類 → 不是 Tier 1/2 房客**。

- repo 零 .html 入口 → Tier 1 WebView 精靈會在步驟④入口偵測紅字撞牆（= skill 登記的「剩餘①入口分流」缺口，slot_installer.dart:151——text-to-cad 是該 bug 的最佳觸發樣本）
- OpenCascade 是編譯級 C++ 核心 → C7 Tier 2 WASM 承載不了
- C5（agent 操作插槽）不解此題——它操作既有插槽，不新增執行引擎類型

**一魚三吃**（若未來要引入）：
| 組件 | 歸宿 |
|---|---|
| 12 個 SKILL.md | skill_intake 背景入庫自動建卡（已上線，冪等） |
| cadgen runtime | 需「Tier 3：受治理的本地 runtime 插槽」——Python venv 生命週期 + DataPathGate 紅線 + 資源看門狗。**此 Tier 在 C 線藍圖尚不存在** |
| CAD Viewer | 脫離 runtime 單裝無意義，不建議 |

**登記為 Tier 3 候選需求，驅動案例 = text-to-cad。**

## 4. Blue 拍板（2026-10-17）

- 現在不手動安裝、不走臨時路徑
- 等 SemiBridge 完成度更高後，用正式插槽安裝流程安裝
- 插槽精靈「入口分流」（剩餘①）優先度應拉高——真實世界會持續丟非網頁 repo 進來
