# 橋樑 App V0.5 — 編織線收官版

> 2026-10-17 · Blue（CEO）令 · 小葵執行
> 版本：`0.5.0+1` · 基準 commit：`3264b32c` 起

## 這個版本做了什麼

V0.5 是「編織線任務集」的收官版本。這段時間的主軸：**向量資料庫頁（vault）從「能看」打磨到「好用」**——側欄資訊架構重構、素材池完整生命周期、標籤系統真標籤化、縮圖雙層快取。

## ✨ 新功能

### 側欄三區資訊架構（📁 資料夾／🏷 標籤／📦 素材池）

| 區塊 | 功能 | 截圖 |
|---|---|---|
| 📁 資料夾（藍） | 樹狀瀏覽向量庫範圍內的資料夾 | `vault_sidebar_levels.png` |
| 🏷 標籤（橘黃） | 使用者貼的標籤＋向量庫既有標籤聯集；點標籤=主區過濾 | `vault_tag_sidebar.png` |
| 📦 素材池（紫） | 打包存檔的素材包列表；點包=主區顯示該包素材牆 | `vault_pack_wall.png` |

三區同級同規格（cardHeroTitle 標題、cardBody 節點、選中轉紫）——層級通則：
- **第一層**（區標題）：cardHeroTitle＋18px icon
- **第二層**（節點）：cardBody＋14px icon＋藍色常亮 icon、選中轉紫

### 素材池完整生命周期

1. 牆上每張卡的白圈＋號＝加入素材池（再點=移出）
2. 大預覽 dialog 按鈕隨池狀態切換「加入／取消加入素材池」
3. 加入時徽章上方冒紫色對話泡泡「素材池有 N 件——在這裡打包素材」（3 秒）
4. 側欄即時顯示「草稿 N 件待打包」
5. 打包存檔（seal）→ 素材包進側欄列表（包名・N件・時間）
6. 點包＝主區顯示該包素材預覽牆（與點資料夾同款體驗）
7. 持久化 `material_packs.json`

### 標籤系統真標籤化

- 標籤 bar：自由輸入標籤（Enter 套用所有選取檔）＋既有標籤 chips
- **貼標同步向量庫**：`AssetIndexService.batchAddTags`——標籤寫進
  `asset_index.tags`（JSON 聯集去重、事務）——智慧搜尋與 Agent
  向量檢索直接吃得到（原本只存 FileTagStore，搜尋看不到）
- 標籤模式下點卡＝選取檔案（一般模式點卡＝大預覽）

### 縮圖雙層快取（6088 檔牆面絲滑）

- 磁碟層：`ThumbCache` 240px 48h，key 綁 mtime（檔案變更自動重生）
- 記憶體層：全域 imageCache 2000 張/400MB＋同 session 記憶體 Map 回滑零磁碟查詢
- 未就緒顯示色塊——**絕不 decode 4000px 原圖**（v1 教訓）
- 主牆/資料夾小卡/搜尋結果卡/詳情面板全部接線

### 互動細節

- **點側欄空白處＝一鍵清除全部篩選**（資料夾/包/標籤/房間/記憶層/搜尋字全歸零）
- 資安邊界入口（盾牌）搬進側欄——App 只碰登錄的資料夾
- 打包（seal）後側欄即時刷新

## 🔧 重要修復

| 問題 | 根因 | 修復 |
|---|---|---|
| 滾輪滑動 lag＋重讀 | 主牆卡未接快取/fallback decode 原圖/imageCache 太小 | 三病灶全修 `108b5bd9` |
| 泡泡冒出時 top bar 溢出（黑黃警示條） | Column 佔高度撐爆 40px top bar | 改 Stack overlay `852ee6e0` |
| 貼了標籤側欄仍「尚無標籤」 | ① 只在進標籤模式才載標籤 ② `_dbTags` 更新後沒 setState | 開頁即載＋通知 UI `3264b32c` |
| 出道包 icon/文字小一號 | ① 字級用 cardCaption ② icon 用 textMuted 灰 | 統一 cardBody＋accentBlue `5015883d`+`318aff58` |
| 標籤模式下點卡誤觸預覽/加入池 | 模式判別缺失 | 標籤模式點卡=選取 `c6b4ae5d` |
| 資料夾 0 檔（6088 對帳） | `folder == root` 比對錯誤 | `160c4a89` |

## 🧹 V0.5 清理

- 刪除：`eval_m1_v1.injected.jsonl.bak`、`galaxy.html.v1.bak`（死碼）
- `.gitignore` 新增 `/training/`（3.9GB 訓練資產）、`/skills/`（agent 私人知識庫）——不進開源 repo

## 📊 實證數據

- 檔案真相：農場資料庫 5174／Downloads 40／bridge_media 874＝**6088 檔**
- asset_index：67,726 筆 · 嵌入就緒 6411 筆 · asset_chunks（EG2）18,231
- 縮圖快取實證：28 張 ~150KB/張（48h 過期自動清）
- 每項 UI 變更均以 cliclick＋screencapture 實機驗證（非宣稱）

## 🗺 下一步（醞釀期）

- Agent-as-User「開光」（v0.4.0 設計輸入已就緒 → 併入 V0.5 後續）
- T11 斷網實測（localOnly）＋連用 7 天觀察
- 手機版 companion 重設計（方向已定：共視口袋版）

---

*指紋定律：本文件由小葵（GLM-5.3）執行，Blue 驗收。所有宣稱附 commit/截圖證據。*
