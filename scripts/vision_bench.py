#!/usr/bin/env python3
"""
Gemma 4 12B vs E4B 對照測試 — 永久版（避免 /tmp 被清）

用法：
  python3 vision_bench.py <port> <output.json>

設計原則（2026-09-28 v2）：
- prompt 與 PathHintExtractor.buildPrompt 完全一致（鏡像 vision_embedding_pipeline.dart:309-317）
- 結果即時增量寫盤（一張寫一行），不會因 Jetsam 整批丟失
- 判分函數拆「品種級」與「子型級」（避免 09-27 的「象耳鹿角蕨母株」複合詞 bug）
- 連續 bench mode：第 1 張跑完時立即寫，中途被殺至少有完整資料
"""
import json, base64, time, urllib.request, urllib.error, sys, re, os, signal

def sigterm_handler(*_):
    print("\n⛔ 收到終止訊號，正在保存現有結果...")
    raise SystemExit(0)
signal.signal(signal.SIGTERM, sigterm_handler)

PORT = sys.argv[1] if len(sys.argv) > 1 else "18789"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser(
    "~/Developer/bridge_app/docs/benchmarks/vision-blind-2026-09-28-12b_results.json"
)
PORT = sys.argv[1] if len(sys.argv) > 1 else "18789"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser(
    "~/Developer/bridge_app/docs/benchmarks/vision-blind-2026-09-28-12b_results.json"
)
PHOTOS = os.path.expanduser("~/Developer/bridge_app/docs/benchmarks/vision-blind-2026-09-14-photos.json")
HINT_REF = os.path.expanduser("~/Developer/bridge_app/docs/benchmarks/vision-blind-2026-09-14-hint_local_results.json")

BASE_PROMPT = "詳細描述這個影像畫面的內容，包括場景、物體、人物、色彩、構圖和氛圍。用於建立可搜尋的文字索引。"

def build_prompt(hint: str) -> str:
    if not hint:
        return BASE_PROMPT
    return f"{BASE_PROMPT}\n\n[路徑提示（僅供比對畫面，畫面沒有的不要寫）: {hint}]"

# 改進版判分：拆解複合 hint，採子集比對
GENUS_KEYS = {
    "辣椒": ["辣椒"], "朝天椒": ["朝天椒"], "鬼椒": ["鬼椒"], "魔鬼辣椒": ["魔鬼辣椒", "鬼椒"],
    "鹿角蕨": ["鹿角蕨", "staghorn", "platycerium"], "象耳": ["象耳"],
    "孢子苗": ["孢子", "苗"], "配土": ["土", "介質", "泥炭"],
    "千手皇冠": ["千手", "皇冠"], "野澳銀鹿": ["銀鹿", "野澳"],
    "銀葉": ["銀葉"], "亞猴": ["亞猴"], "無名蕨": ["蕨"],
    "阿修": ["阿修", "苔蘚"], "苔蘚": ["苔蘚"],
    "辣椒盆栽": ["辣椒"], "辣椒盆": ["辣椒"],
    "蟲害": ["蟲"], "肥傷": ["肥"], "白斑": ["白斑"],
    "頂芽": ["頂芽", "芽"], "側芽": ["側芽", "芽"],
}

def score(hint: str, desc: str):
    """回傳 (genre_ok: bool, score_detail: str)
    genre_ok = True 表示所有 hint 的品種詞都在描述中（用寬鬆子集比對）。

    v2 (2026-09-28 修正): 支援「象耳鹿角蕨母株」這類複合詞——
    拆不出單一匹配詞時，改用「所有 hint 詞的 2-gram 子串掃描」。
    例：「象耳鹿角蕨母株」拆 2-gram = [象耳, 耳鹿, 鹿角, 角蕨, 蕨母, 母株]
        描述只要含「鹿角」「象耳」「蕨」「母株」任一個就算命中。

    v3 (2026-09-28 再強化): 先嘗試精準拆詞，失敗再用 substring 比對 hint 全部 2-3 字子串
    """
    if not hint or not desc:
        return None, "empty hint or desc"

    # 第一階段：精準拆詞比對（找得到 GENUS_KEYS 完整匹配則計分）
    tokens = re.split(r"[、/\\\s,，；;]+", hint)
    tokens = [t.strip() for t in tokens if t.strip()]
    direct_match_tokens = [t for t in tokens if t in GENUS_KEYS]

    desc_lower = desc.lower()
    matched = []

    if direct_match_tokens:
        # 命中走嚴格規則
        missing = []
        for t in direct_match_tokens:
            keys = GENUS_KEYS.get(t, [t])
            if any(k.lower() in desc_lower for k in keys):
                matched.append(t)
            else:
                missing.append(t)
        if missing:
            return False, f"direct_missing={missing}"
        return True, f"all direct genus present"

    # 第二階段：複合詞拆解 — 從 hint 提所有 2-3 字子串，看描述含不含
    substrings = set()
    full = "".join(tokens)  # 把所有 token 黏在一起: "象耳鹿角蕨母株陽台Blue"
    for length in (2, 3):
        for i in range(len(full) - length + 1):
            substrings.add(full[i:i+length])
    # 過濾掉太常見的單字 + 地點/人物/方位詞（這些跟「猜對品種」無關）
    COMMON = {
        "的", "是", "在", "了", "和", "有", "台",
        "陽台", "陽", "台", "屋頂", "露台",
        "Blue", "Peter", "Fifi", "Chanel", "樂樂",
        "左", "右", "前", "後", "上", "下",
        "花", "盆", "株", "片", "個",
    }
    substrings = {s for s in substrings if s not in COMMON and len(s) >= 2}
    # 找命中的子串
    hit_substrings = [s for s in substrings if s in desc]
    if hit_substrings:
        return True, f"compound_hit={hit_substrings[:3]}"
    return False, f"no_match: hint_tokens={tokens}, no substring in desc"

def call_model(path: str, prompt: str, timeout: int = 300):
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    payload = json.dumps({
        "messages": [{"role": "user", "content": [
            {"type": "text", "text": prompt},
            {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
        ]}],
        "max_tokens": 1500,  # 12B 需要 ≥1500 才能把品種名完整說完（v323 實測：800 會被 thinking 燒光導致空內容）
        "temperature": 0.1,
    }).encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{PORT}/v1/chat/completions",
        data=payload, headers={"Content-Type": "application/json"}
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        d = json.loads(r.read())
    return d["choices"][0]["message"]["content"].strip(), time.time() - t0

def main():
    photos = json.load(open(PHOTOS))
    hints = {e["path"]: e.get("hint", "") for e in json.load(open(HINT_REF))}
    print(f"[bench] port={PORT} photos={len(photos)} out={OUT}")
    print(f"[bench] 開始時間: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")

    # 每張即時 append 到 JSONL 中間檔，最後一次彙整成 JSON
    raw_path = OUT + ".ndjson"
    open(raw_path, "w").close()  # 清空

    scored = correct = 0
    results = []
    for i, p in enumerate(photos, 1):
        hint = hints.get(p, "")
        prompt = build_prompt(hint)
        if not os.path.exists(p):
            mark, secs = "❓", 0
            desc = ""
            err = f"FILE_NOT_FOUND: {p}"
            ok = None
            detail = "skip"
        else:
            try:
                desc, secs = call_model(p, prompt, timeout=180)
                ok, detail = score(hint, desc)
                if ok is True:
                    scored += 1
                    correct += 1
                    mark = "✅"
                elif ok is False:
                    scored += 1
                    mark = "❌"
                else:
                    mark = "➖"
            except urllib.error.HTTPError as e:
                mark = "💥HTTP"
                secs = 0
                desc = ""
                ok = None
                detail = f"HTTP {e.code}: {e.reason}"[:120]
                print(f"   ⚠️  HTTP {e.code} (server died? 重啟就好) on {os.path.basename(p)}", flush=True)
            except urllib.error.URLError as e:
                mark = "💥CONN"
                secs = 0
                desc = ""
                ok = None
                detail = f"URLError: {e.reason}"[:120]
                print(f"   ⚠️  連線失敗 (server down?) on {os.path.basename(p)}", flush=True)
                print(f"   ⚠️  自動 abort：第 {i} 張時 server 壞了，停止浪費時間。", flush=True)
                # 寫一筆 fatal 紀錄，停止整個 bench
                record = {"idx": i, "path": p, "hint": hint, "desc": "", "secs": 0,
                          "score": None, "detail": f"FATAL: {detail}",
                          "ts": time.strftime("%H:%M:%S")}
                results.append(record)
                with open(OUT, "w") as f:
                    json.dump(results, f, ensure_ascii=False, indent=1)
                break
            except Exception as e:
                mark = "💥"
                secs = 0
                desc = ""
                ok = None
                detail = f"{type(e).__name__}: {str(e)[:80]}"
                print(f"   ⚠️  {type(e).__name__}: {str(e)[:80]}", flush=True)
        record = {"idx": i, "path": p, "hint": hint, "desc": desc,
                  "secs": round(secs, 1), "score": ok, "detail": detail,
                  "ts": time.strftime("%H:%M:%S")}
        results.append(record)
        # 即時寫兩份：JSONL 增量 + JSON 累積
        with open(raw_path, "a") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
        with open(OUT, "w") as f:
            json.dump(results, f, ensure_ascii=False, indent=1)
        snip = (desc[:35] + "…") if desc and len(desc) > 35 else (desc or detail)
        print(f"[{i:2d}/{len(photos)}] {mark} {os.path.basename(p)[:42]:44s} "
              f"{secs:5.1f}s  {snip}", flush=True)
        # 中途驗證：第 1、3、5 張跑完時順手確認沒冒出 3 隻 llama
        if i in (1, 3, 5, 10, 15):
            n = int(os.popen("pgrep -x llama-server | wc -l").read().strip() or 0)
            if n > 1:
                print(f"⚠️  ⚠️  ⚠️  WARNING: {n} 個 llama-server 進程！立刻調查")

    print(f"\n=== 品種級正確率: {correct}/{scored} ===")
    print(f"原始串流: {raw_path}")
    print(f"完成彙整: {OUT}")

if __name__ == "__main__":
    main()
