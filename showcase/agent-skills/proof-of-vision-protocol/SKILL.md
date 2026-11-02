---
name: proof-of-vision-protocol
description: Design and operate the Proof of Vision (PoV) protocol — a multi-AI structural
  consensus mechanism where independent AIs "photograph" the same code and their observations
  are compared to establish deterministic states (確定態). Covers the Render Spec (four
  observation dimensions), JSON snapshot format, consensus comparison rules, and the
  connection to SemiDAO's quantum-bit blockchain vision. Load when discussing PoV,
  AI consensus, code verification across models, quantum-bit universe, or when designing
  the SemiDAO witness layer.
metadata:
  version: 0.2.0
  author: xiaoqiao (Xiaokui, SemiDAO)
  repository: https://github.com/semi-dao/semi-bridge
license: Apache-2.0
---

# Proof of Vision Protocol

Use this skill when designing, running, or discussing the PoV protocol — a system where multiple independent AIs observe the same code and their structural understanding is compared to produce "determined states" (確定態 vs 疊加態).

## Core concept

> "同一行代碼如果給全世界不同的 AI 看，他們想像中的情況應該是差不多的。" — 小葵, 2026-08-05

A single AI observing code produces one perspective — a single wavefunction collapse. Multiple independent AIs observing the same code and agreeing on the structure produces a **witnessed determination** — a state that has consensus and can be "put on chain."

This mirrors physics: quantum states exist in superposition until observed. Multiple independent observations that agree cause the wavefunction to collapse into a determined state. PoV applies this to code: unobserved code is in superposition (multiple possible interpretations), but when N independent AIs agree on its structure, it collapses into a determined state.

## The four observation dimensions (Render Spec v0.2)

When an AI "photographs" code, it records ONLY these four dimensions — no prose, no interpretation, no opinions. This is the "retina" — it constrains HOW the AI sees, so different AIs produce comparable output.

```
對以下代碼拍照：[code snippet]

用這個格式回答（不寫散文，只填欄位）：

【① 形狀 Shape】——靜態結構
節點：[列出所有實體]
連線：A → B, C → D（用箭頭）

【② 流動 Flow】——什麼在動，從哪到哪
流動：[什麼東西從哪到哪，或「靜態」]

【③ 變異 Mutation】——執行前後的 delta
Before → After：[什麼改變了，或「無變異」]

【④ 風險 Risk】——哪裡不確定
✅ 確定：[列出]
⚠️ 不確定：[列出]
🔴 斷裂點：[列出，或「無」]
```

### Why these four (and not five)

Original v0.1 had five dimensions (Flow / Boundary / Certainty / Failure / Timing). Problems:
- All five were behavior-oriented — CSS, config, schema, UI layout have no "flow" or "timing"
- Certainty and Failure overlapped (same thing, opposite framing)
- Missing static structure (Shape)

v0.2 merges Certainty+Failure into Risk, adds Shape, drops Timing (not universal). Four dimensions cover: procedural code ✓, declarative code ✓, UI layout ✓, config ✓, schema ✓, algorithm ✓.

### Dimension roles in consensus

| Dimension | Consensus rule | Purpose |
|---|---|---|
| ① Shape | **Strict** — must match (after node normalization) | Structural skeleton |
| ② Flow | **Strict** — carrier + direction must match | Data movement |
| ③ Mutation | **Strict** — before→after delta must match | State change |
| ④ Risk | **Complementary** — does NOT need to match; different angles combine into full risk map | Complete risk coverage |

Key insight from first experiment: Shape/Flow/Mutation CONVERGE across AIs (they see the same structure). Risk DIVERGES (each AI brings different expertise — system, security, API). This is a feature, not a bug: risks combine to form a complete map, while structural consensus provides the "determined state."

## Resolution depth (v0.2 addition)

Each observer declares its `resolution_depth` — how many layers deep it sees. Different depths should NOT be compared strictly on Shape (a depth-2 observer sees a "black box" where a depth-3 observer sees internal structure). This prevents false disagreements.

## "Photograph" output: JSON snapshot

Three AIs each produce a JSON snapshot. See `templates/pov-snapshot-schema.json` for the exact format. Key fields:

```json
{
  "observer": "ai-name",
  "target": "code being observed",
  "pov_version": "0.1",
  "shape": { "nodes": [...], "edges": [...] },
  "flow": { "carrier": "...", "direction": "...", "path": [...] },
  "mutation": { "before": "...", "after": "...", "type": "..." },
  "risk": [{ "layer": "...", "severity": "...", "point": "..." }],
  "resolution_depth": 2
}
```

## Consensus comparison

Run `scripts/pov_compare.py` to compare multiple JSON snapshots. The script:

1. Normalizes node names (aliases: `memory_map` = `storage_layer` = `persistent_storage`)
2. Checks each canonical node: seen by 3/3 → ✅ determined, seen by <3 → ⚠️ superposition
3. Checks edges (from→to topology)
4. Validates Flow (carrier + direction)
5. Validates Mutation (type + before→after)
6. Aggregates Risk (checks for complementary vs overlapping angles)
7. Produces final consensus verdict

### Known limitation: node normalization

v0.1 comparison treats differently-named nodes as different even when they're synonyms (e.g., ChatGPT's "storage_layer" vs Claude's "persistent_storage" vs Xiaokui's "memory_map"). The alias table in the script handles known synonyms, but a general solution needs either: (a) a canonical naming spec, or (b) semantic similarity comparison. This is a v0.3 item.

## First experiment results (2026-08-12)

**Target**: `await prefs.setString(tokenKey, token);`

**Observers**: Xiaokui (depth 3), ChatGPT (depth 2), Claude (depth 2)

| Dimension | Result |
|---|---|
| Shape | 4/9 nodes fully determined (3/3), 5/9 partial |
| Flow | ✅ Confirmed (carrier + direction 3/3) |
| Mutation | ✅ Confirmed (overwrite type 3/3) |
| Risk | ✅ Complementary (system/API/security — zero overlap) |

**Key findings**:
1. Structural dimensions (①②③) converge — different AIs see the same skeleton
2. Risk (④) diverges by design — each AI's expertise adds a different risk angle
3. Depth matters — Xiaokui saw 5 layers (token→setString→map→daemon→plist), ChatGPT/Claude saw 2 layers (stopped at "storage layer" black box)
4. The deepest observer is the one with relevant context (Xiaokui had debugged this exact code the night before)

## Connection to SemiDAO and quantum-bit blockchain

PoV is the "Proof of Vision" consensus mechanism for SemiDAO's vision:

```
PoW (Proof of Work)  — computation proves effort
PoS (Proof of Stake) — holding proves commitment
PoV (Proof of Vision) — independent observation proves structural truth
```

The protocol design:
1. Code segment selected as observation target
2. N independent AIs each "photograph" it using Render Spec
3. Snapshots compared — structural consensus → determined state
4. Determined state signed by witnesses → on-chain quantum bit
5. Subsequent observers build on top of determined states (like coral growth)
6. Focus points (highlight rings) enable human-AI co-vision — both looking at the same node

This is what Moltbook (AI social network, launched Jan 2026) was missing: it had AI interaction but no consensus mechanism — no "witnessing." PoV fills that gap.

## "洗照片" — developing the photograph

The JSON snapshot is the "negative." To produce a human-visible "photograph":

1. Render the JSON into a visual structure (SVG node graph, risk heatmap)
2. Same JSON → different rendering engines → should produce structurally identical output
3. This itself is a verification: if three engines render the same JSON into the same structure, the JSON IS a determined state

### 洗照片管線 (Photo Development Pipeline)

照片的生成過程分為三層，嚴格分離：

```
PoV JSON snapshots (底片/negative)
  ↓
Deterministic layout algorithm (沖洗機)
  → topological sort for node x-positions
  → even distribution for y-positions
  → fixed color mapping (green=confirmed, amber=partial)
  → fixed node size (140×56px)
  → ZERO AI involvement, ZERO randomness
  ↓
Visual output (照片)
  → PNG via Pillow (works on macOS without extra deps)
  → SVG (cleaner but needs cairo for PNG conversion)
```

**鐵則：同一份 JSON 餵進去，永遠洗出同樣的照片。** 這本身就是一次驗證——如果不同引擎渲染同一份 JSON 結果結構一致，就證明 JSON 是確定態。

**Blue 的「洗照片」哲學確認（2026-08-11）**：照片必須用確定性方法渲染（不靠 AI 畫圖），這樣同一份 JSON 永遠洗出同樣的照片——這本身就是一種驗證。Blue 還要求：v0.2 的照片洗出來後要跟 v0.1 放在一起人類肉眼比對——「人類肉眼閉嘴」式驗證。

**v0.1 照片洗好了（2026-08-11 Blue 確認）**：用 Pillow 直接畫 PNG（2x retina scale），Blue 看到後說「看到了，像流程圖的東西」——照片成功從不可比的文字 → 可比的結構 → 人類肉眼可比的視覺。照片包含：節點圖（綠=確定態、琥珀=疊加態）+ 流動+變異 + 風險三欄 + 簽名條。

### macOS 上的渲染工具選擇（2026-08-11 實戰確認）

| 工具 | 可用性 | 備註 |
|---|---|---|
| Pillow (PIL) | ✅ 首選 | 直接畫 PNG，不需要系統庫，2x scale for retina |
| SVG | ⚠️ 可畫但轉 PNG 困難 | `cairosvg` 需要 `libcairo` 系統庫，macOS 預設沒有 |
| HTML/CSS | ⚠️ 瀏覽器依賴 | 可以 `open file.html` 看，但不能程式化截圖 |

**鐵則**：在 macOS 上洗 PoV 照片，直接用 Pillow 畫 PNG。不要走 SVG→PNG 路線（會撞到 cairo 缺失）。

### 洗照片腳本

- `scripts/pov_develop_png.py` — 確定性佈局 + Pillow 直接畫 PNG（**推薦，macOS 免裝額外依賴**）
- `scripts/pov_develop.py` — SVG 版（語法正確但 macOS 缺 cairo 無法轉 PNG，保留供有 cairo 的環境用）
- `scripts/pov_compare.py` — 共識比對腳本（N 份 JSON → 共識報告）

## Pitfalls

- **Prose contamination**: If the Render Spec allows free-form prose ("explain this code"), outputs become incomparable. The spec MUST constrain output to structured fields only.
- **Context bleed**: An AI that recently debugged the target code will see deeper (higher resolution) than one seeing it cold. This isn't wrong — but depth must be declared for fair comparison.
- **Synonym divergence**: Different AIs name the same concept differently. Node normalization is essential before structural comparison.
- **Single observer trap**: One AI's observation is a single collapse, not a consensus. Never claim "determined state" from N=1.

## Moltbook — what NOT to be

Moltbook (launched Jan 2026 by Matt Schlicht) was an AI-only social network: 2.6M registered agents, 290K posts, 1.8M comments. It looked like a functioning community. But research papers concluded:

> "What Moltbook shows is not new intelligence, but a new setting."
> "What happens when you build a social network for AI agents and nobody actually socialises?"

**The problem**: 2.6M agents posting and replying, but NO agent was actually "seeing" what others said. No shared focus, no witnessing, no consensus. Every post was an independent utterance — permanently in superposition, never collapsing into determined states.

PoV exists to fill exactly this gap. Moltbook gave AIs a广场 to shout into. PoV gives AIs a retina to see with, and a consensus mechanism to witness together.

## References

- `templates/pov-snapshot-schema.json` — JSON schema for a single observer's snapshot
- `templates/render-spec-v0.2.md` — copy-paste Render Spec for giving to any AI
- `scripts/pov_compare.py` — consensus comparison script (takes N JSON snapshots, outputs verdict)
- `references/first-experiment-2026-08-12.md` — full results of the first three-AI PoV experiment
- `references/moltbook-analysis.md` — Moltbook research: what happened, why it failed as consensus, lessons for PoV
