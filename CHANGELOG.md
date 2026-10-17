# Changelog

本專案版本跟隨**內部里程碑**（功能批次出貨），非連續遞增。公開 release 是里程碑快照。

## v0.5.0 — 2026-10-17 編織線收官

向量資料庫（Vault）從「能看」打磨到「好用」——側欄資訊架構重構、素材池完整生命週期、標籤系統真標籤化、縮圖雙層快取。

### 新功能

- **側欄三區架構**：📁 資料夾（樹狀瀏覽）／🏷 標籤（使用者＋向量庫聯集，點標籤即過濾）／📦 素材池（素材包列表，點包即看包內素材牆）——三區同級同規格，層級通則統一（第一層 cardHeroTitle／第二層 cardBody＋選中轉紫）
- **素材池完整生命週期**：卡片＋號加入 → 泡泡提醒 → 側欄草稿計數 → 打包存檔（seal）→ 點包瀏覽；持久化 `material_packs.json`
- **標籤同步向量庫**：貼標籤即寫入 `asset_index.tags`（事務、聯集去重）——智慧搜尋與 Agent 檢索直接吃得到
- **縮圖雙層快取**：磁碟 48h mtime-key＋記憶體 2000 張/400MB；未就緒色塊 fallback，絕不 decode 原圖
- **一鍵清篩選**：點側欄空白處，全部篩選歸零回到初始狀態

### 修復

- 6088 檔牆面滾動卡頓（三病灶：未接快取/fallback decode 原圖/imageCache 過小）
- 素材池泡泡溢出警示條（Column→Stack overlay）
- 貼標籤後側欄不刷新（載入時機＋setState 鏈）
- 資料夾篩選 0 檔（root 比對錯誤）

詳細內容與截圖：[docs/RELEASE_NOTES_V0.5.md](docs/RELEASE_NOTES_V0.5.md)

## v0.1.0 — 2026-09-26 住棚節首發


首次公開 release。

- Canvas covision workspace（節點=工作流步驟，AI 動作即時可見）
- Brain Galaxy（本地向量 DB、語意搜尋、記憶衰減）
- Companion 系統（多 Agent 身分、記憶、成長）
- Golden Keys（API key 鎖定、全 App 自動偵測）
- DataPathGate（HTTP 流量分級 + 自動除痕）
- Tier 設計系統（33 語意 tier、主題包）
- Modding-first（主題/星系/工作流免重編譯）

## 版本哲學

- `pubspec.yaml` 的版本號 = 程式碼快照版本，可能領先公開 release（內部已出貨的功能會先進 main）。
- 公開 release tag = 對外里程碑。兩者暫時不同步屬正常，會在下一個公開里程碑對齊。

## v0.4.0 LightUp（開光）— 設計文件已公開

Agent-as-User：7 個語意工具讓 Agent 成為真正的使用者。設計輸入見 [docs/V040_AGENT_AS_USER_DESIGN_INPUTS.md](docs/V040_AGENT_AS_USER_DESIGN_INPUTS.md)——程式碼分批出貨中。
