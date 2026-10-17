# 開源整備 Roadmap（按表操課版）

> 目的：所有功能寫完、準備開源時，照這份表逐項打勾即可完成整備。
> 本文件是**活文件**：每項附「重掃指令」，開源前重跑 = 最新體檢報告。
> 基準掃描日：2026-09-17。數字會過期，指令不會。

---

## 總原則

1. **低風險整備先做，高風險拆遷等降溫**——拆大山會跟每週新功能對撞，等功能節奏慢下來（freeze 期）再動刀。
2. **羅盤是保護者不是受害者**——規則是資料不是程式碼，重組程式碼時規則照活，拆完更新檔案錨點即可。
3. **隱私紅線零妥協**——個人路徑、金鑰、內部域名，任何一項漏掉都不能推上 public。

---

## Phase 0：開源標配（任何時候可做，零功能衝突）

- [ ] **LICENSE** — 目前 missing。SemiDAO 生態定位建議與宣言文件對齊後拍板（MIT / Apache-2.0 / AGPL 待 Blue 決）。
  - 重掃：`ls LICENSE CONTRIBUTING.md CHANGELOG.md`
- [ ] **README.md 英文化/雙語化** — 已存在，需審視是否含內部資訊。
- [ ] **CONTRIBUTING.md** — 目前 missing（commit 紀律、測試要求、設計稿工作流）。
- [ ] **CHANGELOG.md** — 目前 missing（1,582 commits 的歷史可從 git log 生草稿）。
- [ ] **架構總覽圖** — 從 `docs/APP_ARCHITECTURE_MAP.md` 萃取公開版（內部細節剝離）。

## Phase 1：隱私與可攜性（開源紅線，提早做、反覆掃）

- [ ] **清除 24 處 hardcode `<HOME>`**（17 檔，性質=開發機路徑：galaxy html、工具、服務）。改法：環境變數或設定檔 + 開發者本機 fallback。
  - 基準：24 處 / 17 檔（2026-09-17）
  - 重掃：`grep -rn '<HOME>' lib --include='*.dart' | wc -l`
  - 熱點：`galaxy_settings_panel.dart`(4)、`bridge_mcp_server.dart`(4)、`restart_app_tool.dart`(2)
- [ ] **兩條 Application Support 路徑統一**（`bridge_app/` vs `farm.semiwasabi.bridgeApp/`，後者 14 檔前者 1 檔）。歷史教訓：驗 DB 前要先 grep 服務寫哪條（09-12、09-14 踩過兩次）。
  - 重掃：`grep -rln "bridge_app/'" lib | wc -l` + `grep -rln 'farm.semiwasabi' lib | wc -l`
- [ ] **掃描 git 歷史中的 secrets** — 目前工作樹無 inline key ✓，但**歷史 commits 可能藏過**。用 `gitleaks` 或 `trufflehog` 全史掃描。若命中：rotate key + `git filter-repo` 洗史（破壞性，Blue 拍板才做）。
  - 工作樹重掃：`grep -rn 'sk-[A-Za-z0-9]\{20,\}' lib scripts -r | wc -l`
- [ ] **內部域名/服務端點盤點** — `api.z.ai`、`localhost:8420` 等寫進 provider 政策表（本来就是主權賣點，公開是加分）。
- [ ] **`.gitignore` 審視** — 確認 `golden_keys.json`、DB、conversations、benchmarks 原始資料（農場照片描述檔如 `docs/benchmarks/vision-blind-*.json`）不在公開範圍或已脫敏。

## Phase 2：程式碼門面（freeze 期做，按風險排序）

- [ ] **拆 `companion_create_screen.dart`（6,663 行）** — 影響半徑 3 檔引用，🟢 最先拆。
  - 活躍度：8 月後 46 commits
- [ ] **拆 `chat_controller.dart`（8,327 行）** — 23 檔引用，🟡 中風險，建議按職責切（對話流/工具調度/記憶寫入/語音）。
  - 活躍度：8 月後 56 commits
- [ ] **拆 `bridge_desktop_screen.dart`（6,728 行）** — 14 檔引用，🔴 **最活躍（8 月後 108 commits）→ 最後拆、等 freeze**。
  - 降溫指標：月 commit 數 < 15 再動刀
- [ ] **debugPrint 治理（1,024 處）** — 不必全刪；建立分級：錯誤留（改統一 logger）、開發期雜訊包 `kDebugMode`。
  - 重掃：`grep -rn 'debugPrint(' lib --include='*.dart' | wc -l`
- [ ] **TODO/FIXME 清算（28 處）** — 開源前逐條：做掉 / 開 issue / 刪除。
  - 重掃：`grep -rn 'TODO\|FIXME\|HACK' lib --include='*.dart' | wc -l`

## Phase 3：品質底線（freeze 期，自動化驗收）

- [ ] `flutter analyze` 全綠（含平行 WIP 清零後）。
- [ ] `flutter test` 全綠（138 測試檔基準）。
- [ ] 全新機器冷啟動驗證：clone → build → run，零個人路徑依賴、零外接碟依賴（離線韌性 09-12 已建，驗證它在乾淨環境成立）。
- [ ] Onboarding 全流程真人走一遍（Welcome 主權字卡 → 金鑰匙 → 首對話）。
- [ ] 效能基準留檔：26K 資產圖譜、搜尋 0.5s、記憶體地墊 570MB（已有數據，寫進文件當賣點）。

## Phase 4：發布工程

- [ ] 決定 repo 名與託管（GitHub org：SemiDAO？）。
- [ ] Release tag + binary 產物（macOS dmg；Windows/Linux 評估）。
- [ ] 宣言文件（open-bridge-oasis-manifesto）連結進 README 首屏。
- [ ] 社群入口：issues 模板、討論區、roadmap 公開版。

---

## 拆大山的共同手法（屆時照用）

1. 先 `grep -rl '<檔名>' lib` 列引用面 → 畫依賴圖。
2. 按職責切子模組，**公開 API 簽名不變**（引用檔零改動為目標）。
3. 每切一塊：`flutter analyze` + 相關測試綠 + App 手動煙霧測試。
4. 更新羅盤 `compass_meta.intent_index` 檔案錨點（拆遷後 agent 地圖不迷路）。
5. commit 紀律：explicit 路徑清單（防平行 session WIP 混入）。

## 決策待拍板（累積給 Blue）

| # | 問題 | 選項 |
|---|------|------|
| D1 | License | MIT / Apache-2.0 / AGPL-3.0 |
| D2 | repo 託管 | SemiDAO org 下 / 個人 org 起手再轉移 |
| D3 | 公開範圍 | 全開 / 先開核心引擎（canvas+vector+compass）漸進開 |
| D4 | git 歷史 | 若 gitleaks 命中：洗史（重寫 hash）vs 從乾淨點重新開始 |
