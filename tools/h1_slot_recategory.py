# H1 插槽分類改制：功能分類＋出身標注
# 一次性遷移腳本（冪等）：
# 1) 114 張「Hermes 移民」+ 8 張「核心技能」按功能關鍵字重新歸類
# 2) 每卡標注 origin（履歷不是戶籍）
# 3)「網頁工具」保持
import json, re, shutil, sys
from pathlib import Path

INDEX = Path('<HOME>/Developer/bridge_app/slots/index.json')
# 備份
bak = Path('/tmp/slots_index_h1_backup.json')
shutil.copy2(INDEX, bak)
print(f'備份 → {bak}')

# 功能分類規則（按特異度排序——先匹配先贏）
RULES = [
    ('開發技能', [
        r'flutter|dart|godot|node-inspect|debugpy|python|debug|mcp|llama-cpp|vllm|serving-llm|code|codex|claude-code|opencode|github|skill-library|refactor|test-driven|architecture|comfyui|segment-anything|jupyter|systematic|simplify|spike|unnamed|dogfood|bridge-|tier-migration|godmode|write-file|harness|mcp-server',
    ]),
    ('內容創作', [
        r'design|sketch|excalidraw|manim|p5js|touchdesigner|ascii|image|photo|gif|video|audio|music|song|infographic|powerpoint|novel|plot|songwriting|humanizer|pretext|blogwatcher|youtube-content|baoyu|heartmula|lara|bead|alpha-cleanup|openai-image|audiocraft|cad',
    ]),
    ('研究調查', [
        r'arxiv|research|paper|wiki|llm-wiki|current-events|verification|polymarket|evaluating|proof-of-vision|codebase-inspection|popular-web|distillation|anti-wasted|interrupt-pattern|model-fallback|plan|petdex|ocr|pdf|nano-pdf',
    ]),
    ('生活助理', [
        r'apple-notes|apple-reminders|imessage|findmy|maps|google-workspace|obsidian|teams|discord-voice|openhue|yuanbao|ig-|computer-use|macos-computer|himalaya|mail',
    ]),
]
FALLBACK = '開發技能'  # 兜底：這批 skill 多數是工程用

d = json.loads(INDEX.read_text())
slots = d if isinstance(d, list) else d.get('slots')
moved, origins = 0, {}
for s in slots:
    cat = s.get('category')
    if cat in ('Hermes 移民', '核心技能'):
        origin = 'Hermes' if cat == 'Hermes 移民' else '內建'
        label = (s.get('userLabel') or s.get('sourceRepo') or '').lower()
        new_cat = FALLBACK
        for cat_name, pats in RULES:
            if any(re.search(p, label) for p in pats):
                new_cat = cat_name
                break
        s['category'] = new_cat
        s['origin'] = origin
        moved += 1
        origins[new_cat] = origins.get(new_cat, 0) + 1

if isinstance(d, list):
    INDEX.write_text(json.dumps(slots, ensure_ascii=False, indent=2))
else:
    d['slots'] = slots
    INDEX.write_text(json.dumps(d, ensure_ascii=False, indent=2))

print(f'改類 {moved} 張：')
from collections import Counter
all_cats = Counter(s.get('category') for s in slots)
for c, n in all_cats.most_common():
    print(f'  {c}: {n}')
print(f'出身標注：{sum(1 for s in slots if s.get("origin"))} 張')
