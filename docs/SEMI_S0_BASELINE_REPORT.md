# Semi S0 基線報告——五器官體檢（2026-10-09/10）

> S 緣起：2026-10-09 Blue 命名 Semi（五器官一靈魂）。本報告是 S0 基線量測的完整存檔——所有數字來自真實執行，題庫 `test/semi/fixture_s0_20cases.json`（20 題真實決策案例：農場 cron／App 決策服務／真實對話）。

## 總表——三個模型候選人 × 20 題標準題庫

| 指標 | Gemma 300M（現任海馬迴） | EmbeddingGemma 2 | Laya（杏仁核候選） |
|---|---|---|---|
| 可作答 | 10/20（檢索型） | 10/20（同題集） | 20/20（全題型） |
| 正確率 | 7/10 | **8/10** | 9/20（45%） |
| Brier | 0.373 | **0.150** | 0.357 |
| 延遲 | 32ms（llama-server Q8） | 356ms（PyTorch BF16 CPU†） | 31ms（MPS／MLX 可到 13ms‡） |
| 信心形狀 | 天花板 0.4 過謙 | 0.65-0.75 且校準 | **高信心錯誤**（97% 信心錯答） |
| 判決 | 現任續職 | **升級候選**（S1.6） | 待微調畢業（S1.5） |

† llama.cpp 尚未支援 `gemma-embedding2` 架構（模型發布 3 天）——GGUF 通道開啟後延遲預期回到 ~50ms。
‡ 見下方「兩專案比對」——`laya-mlx` 原生 MLX 移植在 M3 Max 實測 13.4ms。

## S0.1 反思帳閱讀率（松果體缺口實證）

| 決策路徑 | 讀反思帳？ | 邊數 |
|---|---|---|
| analyzer_router（層路由） | ❌ | 0 |
| execution_decision（本地/雲分流） | ❌ | 0 |
| prompt 注入層 | ✅ 僅夢結論 | 1（10-05 夢的藥回灌） |

**決策層閱讀率 0/2**——松果體白晝相位（反思帳→決策加權）的接線目標就此鎖定。

## S0.2 注入肥肉帳

- 工作域 L1-L3 實測：**48 條／3,770 chars ≈ 2K tokens**——離 16K cap 很遠
- 「1,891 條 L8 全量注入」的擔憂不成立（L8 走 FTS＋CJK bigram 檢索，只注入引用）
- **結論：注入側無肥肉可割，S1 價值重心在訊號協定**（已由 Task 1.1/1.2 落地）

## S0.3 Laya zero-shot 屍檢（Blue 記憶「效果不好」驗證）

- 9/20（45%）、Brier 0.357、choice 7/13／noul 2/5／**score 0/2**
- 最危險：id=6 用 97.2% 信心答錯——zero-shot 的高信心不可信
- 共同盲點：300M 與 Laya 同錯 id=6（困難題標記，微調敏感指標）
- 官方情報：180 筆合成資料微調 → 0.496→0.921——S1.5 依此設計

## S0.3b EmbeddingGemma 2 體檢（記憶器官升級候選）

- 8/10 勝過 300M 的 7/10（同題集同方法）；**Brier 0.150 大幅改善**
- 答對 300M 錯的 id=1（8K context 功勞）；兩者同錯 id=13
- 踩坑記錄（供未來人）：① llama.cpp 不認 `gemma-embedding2` ② 官方 tokenizer_config `extra_special_tokens` 寫成 list（transformers 期待 dict，快取層已修）③ 需 Python 3.11＋transformers git 主分支
- 規格：740M 全模態（文字 270M＋視覺 170M＋聽覺 300M）、Apache 2.0、MRL 可截 256/512d

## 附錄：兩開源比對專案的情報（2026-10-10 Blue 指定調查）

### virajbhartiya/laya-vs-jev（110 ⭐）
- **`laya-mlx`：Laya 的原生 MLX 移植**——13.4ms（英文 checkpoint）/ 7.4ms（multilingual）median 端到端，M3 Max 實測；零 PyTorch/Transformers runtime 依賴
- 移植忠實度：63/63 驗證題與上游完全一致（FP32/FP16 皆然）
- 記憶體：943MB（421M）/ 688MB（322M multilingual）
- 對我們的意義：**Task 1.3 直覺槽的推理通道從 `laya`（PyTorch 31ms）換成 `laya-mlx`（13ms 級）**——Apple Silicon 原生，跟 App 同機共存更省

### abcdmku/Laya-vs-Jev（測試台架構）
- 五測試設計：井字對局／ trivia 競速／**inbox gauntlet（100 封手工標註 email × 3 題：choice 分派＋score 緊急度＋noul 釣魚，對答案計分＋延遲）**／Ask both／Live read
- **inbox gauntlet = 我們 S1.5 的同構設計**——手工標註真實案例＋分題型計分＋延遲並列，驗證我們方向正確
- ⚠️ Laya 預設 checkpoint 每題 512 token 預算，其中問題＋選項只有 192 token（每選項截 48）——**2026-10-10 重考證實：本題庫 state 夠短未受影響**（typed-decisions 1024ctx 重考＝9/20 逐位相同，截斷冤案不成立，45% 為真實 zero-shot 實力；詳見 `/tmp/semi_s0_laya_td_retest.md`）。但擴充 200 題時長 state 案例仍需逐題監控
- laya-server（FastAPI 包裝 POST /v1/systemone）= App 整合的参考架構
