# EG2（EmbeddingGemma-2）三模態 sandbox 實測戰報
日期：2026-10-15 · 環境：/tmp/llama-eg2 自編 llama.cpp（8f574b0, 10-13）· 埠 18800 · Q8_0 主模型+mmproj

## 實測數字
| 模態 | 延遲 | 維度 | 品質證據 |
|---|---|---|---|
| 文字（中/英） | 20ms / 9ms | 768 | 跨語同義 0.796 vs 無關 0.609 |
| 影像（農場真實照片） | 1,343-1,743ms 首次 | 768 | 鹿角蕨照↔「鹿角蕨」0.731 / 辣椒照↔「辣椒」0.768；錯配 0.63（正確配對全勝） |
| 語音（wav） | 37ms | 768 | 音檔↔「提示音效」0.805 vs 無關 0.607 |

## 接線坑（App 整合必讀）
1. llama.cpp server 的 media marker 預設「每次啟動隨機」（get_media_marker()）——
   必須設 `LLAMA_MEDIA_MARKER='<__media__>'` 環境變數釘死，否則 mtmd_tokenize 報
   marker mismatch 500
2. 多模態 API 格式（新版）：POST /embeddings，content=[{prompt_string, multimodal_data:[b64]}]
3. mmproj 檔必要（vision+audio）：Q8_0 530MB；主模型 Q8_0 296MB；總佔 ~830MB+記憶體
4. audio 官方標「experimental」（server log 警告：may have reduced quality）
5. image_max_tokens 被 n_ubatch 上限壓縮（256）——正式環境要 -ub 1024+

## 升級路線（K1_EG2_MIGRATION_PLAN.md 之外補充）
App 正典 llama.cpp 是 2026-07 版——不含 #30054。上線需：
①升級 LocalRuntime llama-server（系統層，Blue 拍板）
②EmbeddingService 介面化（multimodal_data 格式＋marker env）
③全量重嵌入 67,724 檔 + K1 決策頭 768→768 替換 + A/B 評測
