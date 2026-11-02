# PoV Render Spec v0.2

## Instructions for the observing AI

Copy-paste the block below to any AI (ChatGPT, Claude, Gemini, etc.) to have it "photograph" a piece of code.

---

對以下代碼拍照：```
[paste code here]
```

用這個格式回答（不寫散文，只填欄位）：

【① 形狀 Shape】——這段代碼的靜態結構
節點：[列出所有實體（函數、變數、物件、檔案、服務等）]
連線：A → B, C → D（用箭頭表示關係）

【② 流動 Flow】——什麼在動，從哪到哪
流動：[什麼東西從哪到哪，標明類型（data/control/signal）。如果沒有東西在動，標記「靜態」]

【③ 變異 Mutation】——執行前後，什麼改變了
Before → After：[什麼改變了。如果不執行（config/schema），標記「無變異」]

【④ 風險 Risk】——哪裡不確定，哪裡可能壞
✅ 確定：[列出你 100% 確定會發生的事]
⚠️ 不確定：[列出有歧義的部分]
🔴 斷裂點：[列出最可能壞的地方，或「無」]

**規則：**
- 不寫散文解釋
- 不寫「我覺得」「我認為」
- 只記錄結構感知，不詮釋好壞
- 如果你不確定某個節點是否存在，把它放在 ⚠️ 不確定 裡，不要放在節點列表

---

## Notes for the experiment runner

- Give each AI the EXACT same code and the EXACT same spec
- Do NOT provide context about what the code does or any prior debugging
- Each AI must observe independently — no sharing of results between observers
- After all observations are collected, convert each to JSON using `pov-snapshot-schema.json`, then run `scripts/pov_compare.py`
- Node name normalization: different AIs will name the same concept differently. Build an alias table before comparison.
