# 開源範圍建議表（2026-09-21 掃描 → 9/25 住棚節首日公開；**2026-09-24 Blue 拍板更新＋clean tree 執行完畢**）

> **執行結果（2026-09-24）**：clean tree 建立於 `~/Developer/covision-bridge`，單一 initial commit `176aeb5`，1197 檔。四域終驗全零（密鑰/家庭成員名/開發機路徑/人格檔/DB 向量資料/真實立繪/私人對話衍生資料）。flutter analyze 0 error、測試全綠、build ✓。家人剝除實際範圍=lib 7 處+test 5 處+docs 3 處（掃全 repo）；benchmark 人名虛構化（小夏→小夏/小菲→小菲/阿川→阿川）；LiteRtLm dylib 缺席時 benchmark skip 守門。

> 原則：public repo 全新起點（單一 initial commit），內部 1,632 commits 歷史留本地私有。
> 圖示：✅ 保留　🟡 改寫後保留　❌ 移除（留本地）

## A. 整包移除（絕不進 public）

| 項目 | 理由 |
|---|---|
| `spikes/001-provenance-stamp/`（含 brain_copy.db 911MB×2） | 私人記憶資料庫本體 |
| `python/`（27,379 檔，879MB，含 .venv/torch） | 虛擬環境與 site-packages，不屬於 repo |
| `morning-tea/` + `docs/specs/2026-09-21-morning-tea-web.md` | 9/25 一口一次性活動（記憶：Morning Tea=一次性），過期素材 |
| 全部 `HANDOFF_*.md`（root，10 檔） | Agent 間交接文件＝私人工作對話紀錄 |
| `docs/handoff/`（4 檔） | **[2026-09-24 補列]** 對話補遺＝私人對話紀錄 |
| `docs/FIVE_MODES_SESSION_LOG.md` | **[2026-09-24 補列]** 開發對話全記錄（Blue 欽定存檔，留本地） |
| `docs/HANDOFF_2026-08-08.md` | **[2026-09-24 補列]** 交接文件 |
| `.hermes/CHECKPOINT.md`、`.hermes/checkpoint-2026-07-17.md` | Hermes session checkpoint＝私人對話紀錄 |
| `docs/benchmarks/vision-blind-*.json`（6 檔） | 內含農場照片完整路徑（Blue陽台/阿川陽台、辣椒/鹿角蕨）＝個資 |
| `11880`、`12672`（root 兩個 PNG） | 無名截圖檔（截圖內容未驗證） |
| `CONTEXT.md` | 開發期共享語言文件，含內部人格細節（小橋） |
| `NODE_EXECUTION_DEEP_ANALYSIS_20260815.md`、`SOGO_LIGHT_THEME.md`、`design_improvement_plan.md` | 內部分析筆記 |
| `tmp_recon/`、`.github/`、`migrate_working_dir/` | 內部工具/CI 待議 |
| `tools/specs/xiaokui_hermes.agent-import.json` | **[2026-09-24 Blue 拍板：不公開]** agent 人格檔——「立繪/agent人格檔不公開」令（含 Blue（CEO）、HKDiscord #檢查哨、2026-08-27 相遇等私人對話座標） |
| `docs/pov_snapshots/` | **[2026-09-24 補列]** POV snapshot＝agent 人格檔（同上令） |
| `assets/companions/`（小橋/MimeMi 立繪 png） | **[2026-09-24 Blue 拍板：立繪不授權]** 開源版不放真實立繪——放佔位素材（placeholder，同尺寸切層），rig 幾何程式碼照舊；開發者可自帶素材替換 |
| `test/fixtures/compression_ground_truth.json` + `test/compression_round_trip_test.dart` | **[2026-09-24 補列]** 私人對話衍生資料（「排程任務測試」179 則對話的 QA 基準，含 commit 號碼/內部語彙）＝向量資料庫內容的同源資料，絕不進 public |

## B. 改寫後保留（🟡）

| 項目 | 改法 |
|---|---|
| 24 處 hardcode `<HOME>`（17 檔） | 環境變數/設定檔化（roadmap 已列） |
| 「家人」7 處 code comment（album_screen/bridge_desktop_screen×2/chat_controller/time_sense_service/agent_loop_prompt_builder×2） | **[2026-09-24 Blue 拍板：開源版移除，本地保留]** clean tree 時剝除人名，概念出處可保留（如「家庭田野提案 L4」） |
| `assets/skills/*.md`（11 檔） | 內部 skill 檔，內容多為通用 workflow——抽驗無密鑰，保留（樣本：handoff.md、grill-me.md） |
| `docs/` 大部分 .md | 保留（宣言、設計規範、Phase 文件）——純設計/架構文件 |
| `tools/switch-to-glm-coding-plan.sh` | 保留（placeholder key 無慮） |
| `android/.../MainActivity.kt`（path: farm.semiwasabi） | 保留——bundle id 是歷史命名，非個資（見說明） |

## C. 正常保留（✅）

- `lib/`（8.9MB Dart 原始碼）、`test/`、`macos/`、`ios/`、`windows/`、`linux/`、`web/`、`android/`（platform runners）
- `assets/companions/`（小橋/MimeMi 立繪——產品角色，公開是產品定位）⚠️ 立繪授權確認見附註
- `assets/galaxy/`（three.js 星系）＋ vendor 檔案
- `assets/fonts/NotoSansTC-*.ttf`（OFL 授權，可公開）✓ **[2026-09-24] 商用 Arial Unicode MS 已退休 `_retired/`＋gitignore 封鎖**
- `pubspec.yaml`、`Makefile`、`.gitignore`、`DESIGN.md`、`AGENTS.md`、`README.md`（重寫）
- `docs/`（除 A 區排除者）：COVISION_MANIFESTO、DATA_SOVEREIGNTY_MANIFESTO、BRIDGE_* 設計規範、PHASE_G_TIMELINE、APP_ARCHITECTURE_MAP 等
- `tool/`、`tools/`（除 A 區排除者）、`scripts/`、`compass_store.db`（0B 空 SQLite，建議排除但非阻塞）

## 安全設計修復（2026-09-24 Blue 拍板，已實作）

| 項目 | 修法 | 狀態 |
|---|---|---|
| LAN Gateway（8790）無連線驗證 | `_PairingGate` 連線層閘門——升級後第一訊息必須帶正確 pairingCode 的 hello，否則 error+斷線；過閘才進 push 廣播清單 | ✅ 測試 4/4 綠 |
| 配對碼可預測（runtimeChannel 確定性雜湊） | `_pairingCodeFor` 改 `Random.secure()` 真隨機（BRIDGE-XXXXXX 格式不變） | ✅ |
| MCP token fail-open | fail-close：`_tokenInitFailed` 時 `start()` 直接 return 不 serve；修復路徑寫明（刪 mcp_token 重啟） | ✅ |

## 待 Blue 拍板的三件事（2026-09-24 更新）

1. ~~立繪授權~~ → **仍待最終點頭**：`assets/companions/`（小橋、MimeMi）公開 = 任何人可下載。立繪是 AI 生成（rig 封存決策），請確認可公開。
2. ~~BridgeCJK.ttf~~ → **✅ 已解決（2026-09-23）**：字型已換 Noto Sans TC（OFL），商用字型已退休。
3. ~~LICENSE 選擇~~ → **✅ 已拍板（2026-09-24）：Apache-2.0** |

## 附註：bundle id「farm.semiwasabi」

Android bundle path `farm.semiwasabi.bridge_app` 是開發歷史命名（農場起源）。公開無個資風險（semiwasabi 是公開 GitHub 帳號名）。但若你想開源版換個乾淨的 namespace（如 `org.semidao.covision`），9/25 前改 bundle id 有 signing 風險，建議開源後再議。

> 本表為 9/21 掃描快照。開源前重跑掃描指令 = 最新體檢。
