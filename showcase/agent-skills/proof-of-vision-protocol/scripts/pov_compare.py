#!/usr/bin/env python3
"""
PoV Consensus Comparator v0.1
Compares multiple AI observer JSON snapshots and produces a consensus verdict.

Usage:
  python3 pov_compare.py snapshot1.json snapshot2.json [snapshot3.json ...]

Or place JSON files in the same directory and run without args.
"""
import json
import sys
import os

def load_snapshots(args):
    """Load JSON snapshots from args or current directory."""
    snapshots = []
    if args:
        for path in args:
            with open(path) as f:
                snapshots.append(json.load(f))
    else:
        # Load all *_v0.1.json from ../json/ or current dir
        search_dirs = [
            os.path.join(os.path.dirname(__file__), '..', 'json'),
            os.path.join(os.path.dirname(__file__), '..', '..', 'docs', 'pov_snapshots', 'json'),
            '.',
        ]
        for d in search_dirs:
            if os.path.isdir(d):
                for fname in sorted(os.listdir(d)):
                    if fname.endswith('.json') and '_v0.' in fname:
                        with open(os.path.join(d, fname)) as f:
                            snapshots.append(json.load(f))
                if snapshots:
                    break
    return snapshots

# Node alias mapping — different AIs name the same concept differently
# Extend this as more experiments reveal new synonyms
NODE_ALIASES = {
    "token": {"token"},
    "tokenKey": {"tokenkey", "token_key"},
    "setString": {"setstring", "set_string"},
    "prefs_object": {"prefs", "preferences"},
    "memory_storage": {"memory_map", "storage_layer", "persistent_storage", "storage"},
    "async_control": {"async_flow", "await"},
    "future_result": {"future_result", "result"},
    "cfprefsd": {"cfprefsd", "daemon"},
    "plist": {"plist", "file", "disk"},
}

def canonicalize(node_id):
    """Map a raw node ID to its canonical name."""
    lower = node_id.lower()
    for canonical, aliases in NODE_ALIASES.items():
        if lower in aliases:
            return canonical
    return lower  # unknown nodes pass through as-is

def compare_snapshots(snapshots):
    """Run full consensus comparison."""
    observer_names = [s["observer"] for s in snapshots]
    n = len(snapshots)

    print("=" * 70)
    print("📸 PoV Consensus Report")
    print(f"   Target: {snapshots[0].get('target', 'N/A')}")
    print(f"   Observers: {', '.join(observer_names)}")
    print(f"   POV Version: {snapshots[0].get('pov_version', '?')}")
    print("=" * 70)

    # ═══════════════════════════════════════
    # ① Shape
    # ═══════════════════════════════════════
    print(f"\n【① Shape — 形狀】")
    print("-" * 50)

    # Collect canonical nodes
    all_canonical = set()
    for s in snapshots:
        for node in s["shape"]["nodes"]:
            all_canonical.add(canonicalize(node["id"]))

    print("\n節點共識：")
    confirmed = 0
    partial = 0
    for canonical in sorted(all_canonical):
        seen_by = []
        for s in snapshots:
            obs_nodes = {canonicalize(n["id"]) for n in s["shape"]["nodes"]}
            if canonical in obs_nodes:
                seen_by.append(s["observer"])
        if len(seen_by) == n:
            status = f"✅ 確定態"
            confirmed += 1
        elif seen_by:
            status = f"⚠️ 部分見證"
            partial += 1
        else:
            status = "❌ 未觀測"
        print(f"  {canonical:25s} → {status} ({len(seen_by)}/{n}: {', '.join(seen_by) if seen_by else 'none'})")

    # Edges
    print("\n連線拓撲共識：")
    all_edges = set()
    for s in snapshots:
        for e in s["shape"]["edges"]:
            all_edges.add((canonicalize(e["from"]), canonicalize(e["to"])))

    for from_n, to_n in sorted(all_edges):
        seen_by = []
        for s in snapshots:
            obs_edges = {(canonicalize(e["from"]), canonicalize(e["to"])) for e in s["shape"]["edges"]}
            if (from_n, to_n) in obs_edges:
                seen_by.append(s["observer"])
        status = "✅" if len(seen_by) == n else ("⚠️" if seen_by else "❌")
        print(f"  {status} {from_n:25s} → {to_n:25s}  ({len(seen_by)}/{n})")

    # ═══════════════════════════════════════
    # ② Flow
    # ═══════════════════════════════════════
    print(f"\n【② Flow — 流動】")
    print("-" * 50)

    carriers = set(s["flow"]["carrier"] for s in snapshots)
    directions = set(s["flow"]["direction"] for s in snapshots)
    print(f"\n載體：{carriers} → {'✅ 一致' if len(carriers) == 1 else '⚠️ 不一致'}")
    print(f"方向：{directions} → {'✅ 一致' if len(directions) == 1 else '⚠️ 不一致'}")

    # ═══════════════════════════════════════
    # ③ Mutation
    # ═══════════════════════════════════════
    print(f"\n【③ Mutation — 變異】")
    print("-" * 50)

    types = set(s["mutation"]["type"] for s in snapshots)
    print(f"\n變異類型：{types} → {'✅ 一致' if len(types) == 1 else '⚠️ 不一致'}")
    print("\nBefore → After：")
    for s in snapshots:
        m = s["mutation"]
        print(f"  {s['observer']:12s}: {m['before']:25s} → {m['after']}")

    # ═══════════════════════════════════════
    # ④ Risk
    # ═══════════════════════════════════════
    print(f"\n【④ Risk — 風險】")
    print("-" * 50)

    risk_layers = set()
    for s in snapshots:
        for r in s["risk"]:
            risk_layers.add(r["layer"])
            print(f"  {s['observer']:12s} [{r['severity']:6s}] {r['layer']:12s}: {r['point'][:60]}")

    overlap = len(risk_layers) < len(snapshots)
    print(f"\n風險覆蓋角度：{risk_layers}")
    print(f"  {'⚠️ 有重疊' if overlap else '✅ 完全互補——不同角度，零重疊'}")

    # ═══════════════════════════════════════
    # Resolution
    # ═══════════════════════════════════════
    print(f"\n【解析度】")
    print("-" * 50)
    for s in snapshots:
        print(f"  {s['observer']:12s}: depth {s.get('resolution_depth', '?')}")

    # ═══════════════════════════════════════
    # Verdict
    # ═══════════════════════════════════════
    total_nodes = len(all_canonical)
    print(f"\n{'=' * 70}")
    print(f"🏆 共識判定")
    print(f"{'=' * 70}")
    print(f"\n  ① Shape:   {confirmed}/{total_nodes} 節點為確定態（{n}/{n} 見證）")
    print(f"             {partial}/{total_nodes} 節點為部分見證（需更多觀測者）")
    flow_ok = len(carriers) == 1 and len(directions) == 1
    print(f"  ② Flow:    {'✅ 確定態' if flow_ok else '⚠️ 歧異'}（載體+方向 {'一致' if flow_ok else '不一致'}）")
    mutation_ok = len(types) == 1
    print(f"  ③ Mutation: {'✅ 確定態' if mutation_ok else '⚠️ 歧異'}（變異類型 {'一致' if mutation_ok else '不一致'}）")
    print(f"  ④ Risk:    {'✅ 互補態' if not overlap else '⚠️ 有重疊'}（{len(risk_layers)} 個{'不重疊' if not overlap else ''}角度）")
    print(f"\n  量子比特狀態：")
    print(f"    結構骨架 → {'塌陷為確定態 ✅' if confirmed > 0 else '疊加態 ⚠️'}")
    print(f"    深層管線 → {'疊加態（部分觀測者看到） ⚠️' if partial > 0 else '確定態 ✅'}")
    print(f"    風險地圖 → {'完整覆蓋 ✅' if not overlap else '需更多角度 ⚠️'}")


if __name__ == "__main__":
    args = sys.argv[1:]
    snapshots = load_snapshots(args)
    if len(snapshots) < 2:
        print("Need at least 2 snapshots for comparison.")
        print("Usage: python3 pov_compare.py snapshot1.json snapshot2.json [snapshot3.json ...]")
        sys.exit(1)
    compare_snapshots(snapshots)
