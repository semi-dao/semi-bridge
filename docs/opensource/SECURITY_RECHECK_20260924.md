# 開源前安全複檢報告（2026-09-24）

> Blue 令：開源上傳前「再一次重新檢討隱私安全、數位資產安全、資訊安全、金鑰匙系統安全」。
> 基準掃描日：2026-09-24。重掃指令見 OPEN_SOURCE_READINESS_ROADMAP.md。

## 掃描結論總覽

| 域 | 狀態 | 發現 |
|---|---|---|
| 金鑰匙/密鑰 | ✅ 乾淨 | 工作樹無真實 key；唯一命中=測試用假 key |
| 隱私 | ⚠️ 3 項待拍板 | 家人出處標註×7、xiaokui 人格檔、docs/handoff 補遺 |
| 數位資產 | ✅ 基本就緒 | 字型已換 Noto；立繪待最終授權點頭 |
| 資訊安全 | ⚠️ 2 項待拍板 | LAN gateway 無連線驗證；MCP fail-open 設計 |

---

## 域 4：金鑰匙系統安全（✅ 通過）

- `sk-` / `ghp_` / `AKIA` / `AIza` / `PRIVATE KEY` 全工作樹掃描：**0 真實命中**
  （唯一 `ghp_AB...1234` 在 `test/sensitive_content_scanner_test.dart`＝測試假 key，範圍表已列排除）
- `golden_keys.json` 不在 repo 內（實體在 Application Support，repo 外）✓
- 所有 provider key 走 `StorageService.getToken()` 金鑰匙系統，無 inline key ✓
- `.gitignore` 封鎖：`assets/fonts/_retired/`（22MB 商用字型退休區）、`native/litert_lm/prebuilt/`、`migrate_working_dir/` ✓
- **既有 DB 檔案**：`compass_store.db`（0 bytes 空 SQLite）被 git 追蹤——無內容無風險，開源版建議排除（觀感）

## 域 1：隱私安全（⚠️ 三項待 Blue 拍板）

1. **「家人」出現 7 處**（code comment 出處標註：album/time_sense/prompt_builder）——家人是家庭成員暱稱。雖是工程慣例的「提案來源」標註，公開 repo 會讓陌生人看到家庭脈絡。選項：(a) 保留（脈絡誠實）(b) 改成代號（如「家庭顧問 L」）(c) 移除名字留概念。
2. **`tools/specs/xiaokui_hermes.agent-import.json`**——9/21 範圍表拍板「保留」（IG 出道公開人格檔），但檔案含「Blue（CEO）」「HKDiscord #檢查哨」「2026-08-27 相遇」等私人對話座標 + 9/22 記憶令「立繪/agent人格檔不公開」。**兩個令衝突，需重新拍板**。
3. **`docs/handoff/`（橋樑計畫_對話補遺與未寫入文件概念.md 等 4 檔）+ `docs/FIVE_MODES_SESSION_LOG.md` + `docs/HANDOFF_2026-08-08.md`**——A 區清單漏列！內容是開發對話紀錄/交接文件。**建議全數移入 A 區（絕不進 public）**。
   - 另 root `HANDOFF_*.md` 10 檔在 A 區 ✓ 但 `docs/` 底下同名性質檔案漏了。
4. 24 處 `<HOME>` hardcode（17 檔）＋12 處 `/Volumes/DATA`——範圍表已列 🟡 改寫，fresh-start 前要完成。
5. test 檔內 `semiwasabi`/`Blue`＝公開帳號名+工程出處標註，低風險 ✓。

## 域 2：數位資產安全（✅ 基本就緒，1 項待點頭）

- **字型**：已換 Noto Sans TC（OFL 授權，可公開）✓；商用 Arial Unicode MS 已退休到 `_retired/`＋gitignore 封鎖 ✓；git 追蹤清單已無 BridgeCJK ✓
- **立繪**：小橋/MimeMi 切層 rig（AI 生成）——9/21 待拍板項，尚未最終點頭。公開=任何人可下載商用。
- **galaxy/ 三方件**：2.6MB，vendor 檔案授權待最終確認（three.js MIT 預期）。
- assets 總量 40MB→實際公開 ~14MB（扣除 _retired 22MB）✓ 無 >100MB 單檔 ✓

## 域 3：資訊安全（⚠️ 兩項待 Blue 拍板——開源後全世界看得到設計）

1. **LAN Gateway（8790 埠）無連線驗證**——`desktop_bridge_local_gateway.dart` 綁 `0.0.0.0`（手機 LAN 連入設計），WebSocket upgrade 前**沒有 pairingCode/token 驗證**（pairingCode 只出現在 QR 碼/UI 展示）。同 LAN 任何裝置可連線呼叫 task。**建議**：fresh-start 前加 handshake 驗證（升級前帶 token header 或第一訊息驗 pairingCode），或至少 README 誠實揭露此限制。
2. **MCP token fail-open**——`bridge_mcp_server.dart` 註明「token 機制失敗時不擋服務（寧可暫時無鎖）」。本地優先的權衡可以理解，但開源後攻擊者知道「讓 token 初始化失敗即可無鎖」。**建議**：改 fail-close（token 失敗=服務不啟動+UI 紅字），或至少限定 loopback 介面預設。
3. MCP 8420 綁 loopbackIPv4 ✓（非 0.0.0.0）；token 64 hex 隨機+0600+401 不洩露原因 ✓；`/health` 無鎖回版本=可接受 ✓。
4. `data_path_gate.dart` 的 0.0.0.0 是本地白名單判定用（非綁定）——誤報排除 ✓。

## 與 9/21 範圍表的差異（本輪新增）

| 項目 | 動作 |
|---|---|
| `docs/handoff/`（4 檔） | **新增 A 區**（對話補遺=私人紀錄） |
| `docs/FIVE_MODES_SESSION_LOG.md` | **新增 A 區**（開發對話全記錄） |
| `docs/HANDOFF_2026-08-08.md` | **新增 A 區** |
| `compass_store.db`（0B） | 建議排除（觀感） |
| `xiaokui_hermes.agent-import.json` | **升降級待拍板**（9/21 保留令 vs 9/22 不公開令衝突） |

## 文件三件套現況

- LICENSE：**missing**（Apache-2.0 建議中，待拍板）
- README_DRAFT.md：已備（WIP 誠實告示 ✓）
- MANIFESTO_DRAFT.md：已備
- CONTRIBUTING.md / CHANGELOG.md：missing（非阻塞，可開源後補）

---

*掃描執行者：小葵 2026-09-24。所有結論基於當日指令輸出，重掃=重跑 roadmap 指令。*
