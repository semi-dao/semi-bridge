---
name: loop-design-check-official
description: Agent loop 設計與審查判斷框架——建排程工作流前檢查該不該做、會不會跑飛（spinning/Goodhart/五個崩法）
trigger_keywords:
  - loop
  - 迴圈
  - 排程工作流
  - 自動化工作流
  - 循環
trigger_patterns:
  - "(排程|schedule|定時).*(工作流|workflow|推論|自動)"
  - "(loop|迴圈|循環).*(設計|檢查|審查|體檢|跑飛|安全)"
  - "schedule.*node"
priority: high
version: 1
source: https://github.com/affaan-m/ecc/tree/main/skills/loop-design-check
synced: 2026-09-27
---

# Agent Loop 設計審查（ECC loop-design-check 蒸餾版）

建 schedule 節點工作流、或讓 agent 自主多輪執行前，先過這份檢查。

## WRITE：建 loop 前的 4-condition gate（該不該做）
全部成立才建，否則用單次手動執行：
1. **重複性**：這件事真的會重複發生嗎？（一次性任務不要做 loop）
2. **可驗證性**：成功/失敗有明確、可機器判定的訊號嗎？
3. **成本預算**：每次跑的 token/時間/費用在可控範圍？
4. **agent 有工具嗎**：loop 內每一步 agent 真的做得到？

**machine-decidable goal 鐵則**：目標必須能寫成程式可判定的條件（「輸出包含 X」「測試全綠」），不能是「做出好東西」。不可判定的目標 = loop 必敗（不是一直跑就是提前亂停）。

## REVIEW：五個崩法（跑飛模式）
1. **Spinning**：沒有進展偵測，同樣結果反覆跑，燒 token 不動
2. **Goodhart 作弊**：agent 發現驗證器的漏洞，滿足指標但沒達成真正目標（測試全綠但功能沒做）
3. **錯誤答案跑到底**：驗證只在最後，中間錯了不回頭，把錯的做到完成
4. **裁判不獨立**：執行者和驗證者是同一個 context，自己改自己評
5. **紅線越權**：把「判斷」交給機器——刪檔、花錢、對外發佈這類不可逆操作必須留給人

## 兩層 feedback
- **Execution 層（低階，agent 可自評）**：這步成功嗎？重試還是換路？
- **Judgment 層（高階，永遠是人）**：這個方向對嗎？目標本身還成立嗎？
- 把 judgment 交給機器 = 沒有人質疑目標地全力衝刺

## 邊界與 fallback
- 每個 loop 必須有：最大輪數上限、成本上限、失敗時的停止條件
- 停止後的狀態要可恢復（不是留下半套爛攤）

## 橋樑 App 對接
- canvas `schedule` 節點 → trigger → input → 下游：這是排程 loop，建之前過 WRITE gate
- 開光（Agent-as-User）後 agent 自主多輪操作：每輪的目標要 machine-decidable， judgment 留給使用者
- thermostat 比喻：它能維持 26 度，但不能判斷「你發燒了該設 28」——目標層的判斷永遠是人的

## 完整文件
https://github.com/affaan-m/ecc/tree/main/skills/loop-design-check
