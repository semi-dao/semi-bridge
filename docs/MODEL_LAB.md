# Model Lab——本地模型的一鍵 A/B 實驗室

> 起源：semi-bridge 的照片索引依賴本地視覺模型。開源模型月月出新，
> 「哪個最適合我的照片」不該靠別人的 benchmark——於是做了 Lab：
> **用自己的資料盲測、在 App 裡一鍵跑完、結果直接變成現役**。

## 設計

1. **快測**（≥3 張）：主線引擎自動讓路（stop → 獨佔 GPU）→ lab server（18799）起測試引擎 → 跑完自動復活主線。使用者無感切換。
2. **全測**（20 張）：快測 ≥3/5 命中後，App 主動詢問是否跑全測。
3. **採用**：測完一鍵「設為現役」——stopServer → startServer(modelId)，產品路徑不走 CLI。

## 硬體紀律（16GB 機器）

- 主線（12B, 7.1GB）+ lab（E4B, 5.3GB）**不可同時**——Lab 的 B' 方案自動處理
- context 依模型大小自動調整：12B 強制 ≤4096（32768 會 Jetsam OOM）
- thinking 模型 max_tokens ≥1500

## 換測試引擎

`models/recommended-models.json` 加一筆（gguf + mmproj 配對），App 自動出現選項。
mmproj 必配——沒有它 vision 請求會静默失敗（教訓：E2B 測試時踩過）。

## 盲測方法

見 [benchmarks/](benchmarks/VISION_MODEL_BENCHMARK_2026-09.md)——hint 關鍵詞命中判分，
腳本可重演，素材是使用者自己的照片。
