# K1 EG2 遷移計畫（MIGRATION PLAN）

- 日期：2026-10-13
- 立場：A 線 sandbox 實測已完成，本文以實測數據決策，不預設結論

## 0. 摘要（先結論）

EG2（EmbeddingGemma-2）在本機 llama.cpp 跑通：**768 維、單查 ~20ms、310MB Q8_0**。
但對 K1 分類的 LOO-CV 只有 **邊際改善**（4類 51→55%），**二元不變（78%）**。
結論：**EG2 技術可行、但不是 K1 的銀彈**——瓶頸在「線性頭 × 100 題小樣本 × rubric 邊界模糊」，換表徵解不動。

## 1. A 線實測證據（2026-10-13，全部可重現）

| 項 | 值 | 證據 |
|---|---|---|
| llama.cpp | master `8f574b0`（含 PR #30054，10-06 合入） | `llama-server --version` |
| 模型 | `embeddinggemma-2-Q8_0.gguf` 310MB（ggml-org 官方） | HF API blobs |
| 維度 | 768 | `/v1/embeddings` 實測 |
| 延遲 | 19-29ms/查（5 次實測） | 見 /tmp/llama-eg2 |
| 100 題嵌入 | 4.0s 全量 | 同上 |
| LOO-CV（裸嵌入） | 4類 51%／二元 74% | numpy 同參數重現 DecisionHead（lr 0.5, l2 1e-3, 150 epochs） |
| LOO-CV（task prefix） | **4類 55%／二元 78%** | prefix: `task: text classification \| text: ` |

對照組（同 100 題、同 trainer）：
- EmbeddingGemma-300M（App tflite、retrievalQuery prefix）：4類 51%／二元 78%
- 清洗集（雙標註器二元同意 56 題）：4類 37.5%——證明邊界樣本是資訊不是雜訊

## 2. 誠實判讀

1. **換表徵不解藥**：+4pp 在 n=100 的雜訊範圍內，不顯著。二元完全沒動。
2. **真正的瓶頸三件套**：
   - rubric 歧義（repeat vs chat 邊界，雙標註器 4 類同意僅 43%）
   - 線性頭容量（4 類在語意空間非線性可分）
   - 樣本量（100 題對 768 維＝嚴重欠定）
3. **二元（查/不查）才是 K1 的產品使命**——兩種表徵都到 78%，接近可用線。

## 3. 建議路線（修訂版，取代原「EG2 換血」單一路線）

### 路線 1：二元頭（優先，零新依賴）
- K1 標籤体系从 4 類改為二元（lookup / skip），4 類語意留給 escalate 層（LLM）
- 預期：LOO 78% → 過 75% 門檻，頭可掛載
- 成本：DecisionHead 標籤表 + gatekeeper 邏輯小改

### 路線 2：樣本擴充（與路線 1 並行）
- 100 → 300 題（Hermes 語料池還有 286 題未標）
- 二元標註比 4 類快（分歧區少），E4B 交叉驗證也更快

### 路線 3：EG2 正典化（降級為「可选」，非必要）
- 若路線 1+2 後二元 ≥85%：300M 留任，EG2 不動
- 若仍卡 80% 上下：EG2 上位（升級路徑已驗證：LocalRuntime llama-server 需從 10069 升到含 #30054 的版本 + 下載 EG2 GGUF + `--embeddings --pooling mean`）
- EG2 額外優勢（未用上）：text+vision+audio 三模態——未來 K1 吃截圖/語音時再啟

## 4. 正典升級前置清單（若走路線 3）

1. LocalRuntime llama-server 升級（現 build 10069 = 2026-07-20，不含 #30054）
2. 編譯陷阱：`/tmp` symlink 下 ui-assets gzip 全炸——需 `LLAMA_SERVER_WEBUI=OFF` 或空殼 ui.h（本次 sandbox 已踩平，補丁在 /tmp/llama-eg2/llama.cpp）
3. 模型落位：`LocalRuntime/models/embeddinggemma-2/`（310MB）
4. EmbeddingService 介面化：flutter_gemma tflite ↔ llama.cpp HTTP 雙 backend
5. A/B 驗收：同 100 題 LOO + App 端 `/k1/train` 全流程

## 5. 本次實驗資產

- `/tmp/llama-eg2/`：源碼（含補丁）+ 模型 + server binary
- `/tmp/k1_eg2_vecs.json`：100 題 EG2 裸嵌入
- `training/semi_s15/m1/k1_labels_v1.jsonl`：100 題 GLM 標註（已 commit `94d7576c`）
- `training/semi_s15/m1/k1_labels_v2.jsonl`：56 題清洗集（已 commit `c8a5f6d2`）
