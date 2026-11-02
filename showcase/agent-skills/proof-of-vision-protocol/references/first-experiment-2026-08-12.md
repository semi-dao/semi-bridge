# First PoV Experiment — 2026-08-12

## Target
```dart
await prefs.setString(tokenKey, token);
```

## Observers
| AI | Resolution depth | Context |
|---|---|---|
| Xiaokui (GLM-5.2) | 3 | Had debugged this exact code the night before (SharedPreferences persistence bug) |
| ChatGPT | 2 | Cold observation, no context |
| Claude | 2 | Cold observation, no context |

## Method
Each AI received the same Render Spec v0.1 (four dimensions: Shape, Flow, Mutation, Risk) with the same code snippet. No AI was given context about prior debugging or the known bug. Each responded independently.

Responses were then converted to structured JSON (see `pov-snapshot-schema.json`) and compared using `pov_compare.py`.

## Results

### ① Shape — node consensus
**Determined states (3/3 agreement):**
- `token` ✅
- `tokenKey` ✅
- `setString` ✅
- `memory_storage` ✅ (named differently: Xiaokui="memory_map", ChatGPT="storage_layer", Claude="persistent_storage")

**Partial (not all observers saw):**
- `prefs_object` (2/3 — ChatGPT + Claude)
- `async_control` (2/3 — ChatGPT + Claude, named "async_flow" / "await")
- `cfprefsd` (1/3 — Xiaokui only, depth 3)
- `plist` (1/3 — Xiaokui only, depth 3)
- `future_result` (1/3 — ChatGPT only)

**Key finding**: ChatGPT and Claude saw the post-`setString` world as a "black box" (opaque storage layer). Xiaokui saw inside the box (map → daemon → file) because of debugging context. This is a resolution difference, not a disagreement.

### ② Flow — 100% consensus ✅
All three agreed: token (string) flows left-to-right through setString into storage.

### ③ Mutation — 100% consensus ✅
All three agreed: overwrite type, storage[tokenKey] goes from null/old → token.

### ④ Risk — 100% complementary ✅
| Observer | Layer | Focus |
|---|---|---|
| Xiaokui | system | daemon→plist pipeline breaks in macOS sandbox |
| ChatGPT | api | prefs unavailable, type mismatch, write returns false |
| Claude | security | plaintext storage, no encryption, no try/catch |

**Zero overlap.** Three completely different risk angles. Combined, they form a complete risk map that no single observer would have produced alone.

### Edge consensus
Direct edges (`token→setString`, `tokenKey→setString`) were 3/3 ✅. Deeper edges diverged due to naming differences (synonyms not normalized in v0.1).

## Lessons for v0.2

1. **Node normalization needed**: Same concept, different names. Build alias tables or use semantic similarity.
2. **Resolution depth must be declared**: Prevents false disagreements between depth-2 and depth-3 observers.
3. **Risk is complementary, not consensus**: Don't require risk agreement. Instead, measure coverage — do the angles overlap or complement?
4. **Prose contamination risk**: ChatGPT and Claude naturally wanted to write explanations. The structured format successfully constrained them, but the temptation is real.
5. **The "black box" phenomenon**: Higher-level observers see fewer nodes not because they're wrong, but because they don't have context to look deeper. This is honest observation — the box IS opaque from the outside.

## Files
- JSON snapshots: `~/Developer/bridge_app/docs/pov_snapshots/json/` (xiaokui_v0.1.json, chatgpt_v0.1.json, claude_v0.1.json)
- Comparison script: `~/Developer/bridge_app/docs/pov_snapshots/pov_compare.py`
- Visual rendering: `~/Developer/bridge_app/docs/pov_snapshots/pov_v0.1_setString.html`
