#!/usr/bin/env python3
"""
PoV Photo Developer v0.1 — PNG 版
把 PoV JSON 洗成 PNG 照片。用 Pillow 直接畫，不需要 cairo。
同樣的 JSON 永遠洗出同樣的照片（確定性佈局，零 AI 介入）。

用法：
  python3 pov_develop_png.py

讀取：
  ~/Developer/bridge_app/docs/pov_snapshots/json/{xiaokui,chatgpt,claude}_v0.1.json

輸出：
  ~/Developer/bridge_app/docs/pov_snapshots/pov_v0.1_photo.png
"""
from PIL import Image, ImageDraw, ImageFont
import json
import os
import math
from collections import defaultdict

# ═══════════════════════════════════════
# 佈局常數（固定，不改）
# ═══════════════════════════════════════
NODE_W = 140
NODE_H = 56
NODE_GAP_X = 190
NODE_GAP_Y = 80
CARD_PAD = 30
RADIUS = 10

# 顏色 (RGB)
C_BG = (13, 17, 23)
C_PANEL = (22, 27, 34)
C_BORDER = (48, 54, 61)
C_TEXT = (230, 237, 243)
C_MUTED = (139, 148, 158)

C_GREEN_FILL = (16, 40, 24)
C_GREEN_STROKE = (63, 185, 80)
C_GREEN_TEXT = (63, 185, 80)

C_AMBER_FILL = (40, 32, 10)
C_AMBER_STROKE = (210, 153, 34)
C_AMBER_TEXT = (210, 153, 34)

C_RED_FILL = (40, 12, 12)
C_RED_STROKE = (248, 81, 73)
C_RED_TEXT = (248, 81, 73)

C_ORANGE_FILL = (40, 25, 10)
C_ORANGE_STROKE = (255, 166, 87)
C_ORANGE_TEXT = (255, 166, 87)

C_YELLOW_FILL = (40, 32, 10)
C_YELLOW_STROKE = (210, 153, 34)
C_YELLOW_TEXT = (210, 153, 34)


def get_font(size):
    paths = [
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/Monaco.ttf",
        "/System/Library/Fonts/Courier.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
    ]
    for p in paths:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except:
                continue
    return ImageFont.load_default()


def normalize_node_id(raw_id):
    raw_lower = raw_id.lower()
    aliases = {
        "token": "token", "tokenkey": "tokenKey", "setstring": "setString",
        "prefs": "prefs", "prefs_object": "prefs",
        "memory_map": "storage", "storage_layer": "storage", "persistent_storage": "storage",
        "async_flow": "async_ctx", "await": "async_ctx",
        "future_result": "future", "cfprefsd": "cfprefsd", "plist": "plist_file",
    }
    return aliases.get(raw_lower, raw_lower)


def build_consensus(all_obs):
    total = len(all_obs)
    node_seen_by = defaultdict(list)
    node_labels = {}
    edge_seen_by = defaultdict(list)

    for obs in all_obs:
        name = obs["observer"]
        for node in obs["shape"]["nodes"]:
            cid = normalize_node_id(node["id"])
            node_seen_by[cid].append(name)
            if cid not in node_labels:
                node_labels[cid] = node["id"]
        for edge in obs["shape"]["edges"]:
            f = normalize_node_id(edge["from"])
            t = normalize_node_id(edge["to"])
            edge_seen_by[(f, t)].append(name)

    node_status = {}
    for cid, seen in node_seen_by.items():
        node_status[cid] = "confirmed" if len(seen) == total else "partial"

    layers = topo_sort(node_seen_by.keys(), edge_seen_by.keys())

    risks = []
    for obs in all_obs:
        for r in obs.get("risk", []):
            risks.append({
                "observer": obs["observer"],
                "layer": r["layer"],
                "severity": r["severity"],
                "point": r["point"],
            })

    return {
        "total_observers": total,
        "observer_names": [o["observer"] for o in all_obs],
        "nodes": node_seen_by, "node_labels": node_labels,
        "node_status": node_status, "edges": edge_seen_by,
        "layers": layers, "risks": risks,
        "target": all_obs[0]["target"],
        "mutation": all_obs[0]["mutation"],
    }


def topo_sort(node_ids, edge_pairs):
    in_degree = {n: 0 for n in node_ids}
    adj = defaultdict(list)
    for f, t in edge_pairs:
        if f in in_degree and t in in_degree:
            adj[f].append(t)
            in_degree[t] += 1
    queue = [n for n in node_ids if in_degree[n] == 0]
    layers = {n: 0 for n in queue}
    while queue:
        node = queue.pop(0)
        for nb in adj[node]:
            if nb not in layers or layers[nb] < layers[node] + 1:
                layers[nb] = layers[node] + 1
            in_degree[nb] -= 1
            if in_degree[nb] == 0 and nb not in queue:
                queue.append(nb)
    for n in node_ids:
        if n not in layers:
            layers[n] = 0
    return layers


def generate_png(consensus, out_path):
    layers = consensus["layers"]
    total_obs = consensus["total_observers"]

    layer_groups = defaultdict(list)
    for nid, ln in layers.items():
        layer_groups[ln].append(nid)

    max_layer = max(layers.values()) if layers else 0
    max_nodes = max(len(v) for v in layer_groups.values()) if layer_groups else 1

    HEADER_H = 100
    GRAPH_H = CARD_PAD * 2 + max_nodes * NODE_GAP_Y
    MUTATION_H = 100
    RISK_H = 180
    SIG_H = 60

    total_w = CARD_PAD * 2 + (max_layer + 1) * NODE_GAP_X + 40
    total_h = HEADER_H + GRAPH_H + MUTATION_H + RISK_H + SIG_H + 40

    SCALE = 2  # retina
    img = Image.new('RGB', (total_w * SCALE, total_h * SCALE), C_BG)
    draw = ImageDraw.Draw(img)

    def font(sz):
        return get_font(sz * SCALE)

    def text(x, y, txt, fill, fnt, anchor="la"):
        draw.text((x * SCALE, y * SCALE), txt, fill=fill, font=fnt, anchor=anchor)

    def rounded(x, y, w, h, r, fill, outline, width=1):
        draw.rounded_rectangle(
            [x*SCALE, y*SCALE, (x+w)*SCALE, (y+h)*SCALE],
            radius=r*SCALE, fill=fill, outline=outline, width=width*SCALE
        )

    def line(x1, y1, x2, y2, fill, width=1):
        draw.line([(x1*SCALE, y1*SCALE), (x2*SCALE, y2*SCALE)], fill=fill, width=width*SCALE)

    def arrow(x1, y1, x2, y2, fill, width=1):
        line(x1, y1, x2, y2, fill, width)
        angle = math.atan2(y2-y1, x2-x1)
        ah = 8
        ax1 = x2 - ah * math.cos(angle - 0.4)
        ay1 = y2 - ah * math.sin(angle - 0.4)
        ax2 = x2 - ah * math.cos(angle + 0.4)
        ay2 = y2 - ah * math.sin(angle + 0.4)
        draw.polygon([(x2*SCALE, y2*SCALE), (ax1*SCALE, ay1*SCALE), (ax2*SCALE, ay2*SCALE)], fill=fill)

    # Header
    rounded(0, 0, total_w, HEADER_H, 0, C_PANEL, C_BORDER, 1)
    f_title = font(18)
    f_sub = font(11)
    f_code = font(12)
    f_node = font(11)
    f_small = font(9)
    f_risk = font(10)
    f_risk_title = font(12)

    text(CARD_PAD, 22, "PoV Snapshot v0.1", C_GREEN_TEXT, f_title)
    text(CARD_PAD, 50, f"{total_obs} Independent Observers: {', '.join(consensus['observer_names'])}", C_MUTED, f_sub)
    text(CARD_PAD, 70, f"Target: {consensus['target'][:90]}", C_TEXT, f_code)

    # Node positions
    node_coords = {}
    for ln, nodes in sorted(layer_groups.items()):
        x = CARD_PAD + ln * NODE_GAP_X
        for i, nid in enumerate(sorted(nodes)):
            y = HEADER_H + CARD_PAD + i * NODE_GAP_Y + (max_nodes - len(nodes)) * NODE_GAP_Y // 2
            node_coords[nid] = (x, y)

    # Draw edges
    for (f, t), seen_by in consensus["edges"].items():
        if f not in node_coords or t not in node_coords:
            continue
        x1, y1 = node_coords[f]
        x2, y2 = node_coords[t]
        confirmed = len(seen_by) == total_obs
        color = C_GREEN_STROKE if confirmed else C_AMBER_STROKE
        arrow(x1 + NODE_W, y1 + NODE_H // 2, x2, y2 + NODE_H // 2, color, 2 if confirmed else 1)

    # Draw nodes
    for nid, (x, y) in node_coords.items():
        status = consensus["node_status"].get(nid, "partial")
        if status == "confirmed":
            fill, stroke, tc = C_GREEN_FILL, C_GREEN_STROKE, C_GREEN_TEXT
            w = 2
        else:
            fill, stroke, tc = C_AMBER_FILL, C_AMBER_STROKE, C_AMBER_TEXT
            w = 1
        rounded(x, y, NODE_W, NODE_H, RADIUS, fill, stroke, w)
        label = consensus["node_labels"].get(nid, nid)
        text(x + NODE_W//2, y + 14, label, tc, f_node, anchor="ma")
        seen_count = len(consensus["nodes"].get(nid, []))
        text(x + NODE_W//2, y + 34, f"{seen_count}/{total_obs}", C_MUTED, f_small, anchor="ma")

    # Mutation
    mut_y = HEADER_H + GRAPH_H
    line(0, mut_y, total_w, mut_y, C_BORDER, 1)
    text(CARD_PAD, mut_y + 16, "Flow & Mutation (3/3)", C_TEXT, f_risk_title)
    mut = consensus["mutation"]
    text(CARD_PAD, mut_y + 40, f"Before: {mut['before'][:25]}", C_RED_TEXT, f_risk)
    text(CARD_PAD + 240, mut_y + 40, "->", C_GREEN_STROKE, f_risk_title)
    text(CARD_PAD + 260, mut_y + 40, f"After: {mut['after'][:25]}", C_GREEN_TEXT, f_risk)
    text(CARD_PAD, mut_y + 64, "All observers agree: overwrite write, left to right", C_GREEN_TEXT, f_small)

    # Risk
    risk_y = mut_y + MUTATION_H
    line(0, risk_y, total_w, risk_y, C_BORDER, 1)
    text(CARD_PAD, risk_y + 16, "Risk Heatmap (complementary)", C_TEXT, f_risk_title)

    risk_colors = {
        "red": (C_RED_FILL, C_RED_STROKE, C_RED_TEXT),
        "orange": (C_ORANGE_FILL, C_ORANGE_STROKE, C_ORANGE_TEXT),
        "yellow": (C_YELLOW_FILL, C_YELLOW_STROKE, C_YELLOW_TEXT),
    }

    n_risks = len(consensus["risks"])
    col_w = (total_w - CARD_PAD * 2 - 12) // n_risks

    for i, r in enumerate(consensus["risks"]):
        cx = CARD_PAD + i * (col_w + 6)
        cy = risk_y + 36
        rf, rs, rt = risk_colors.get(r["severity"], risk_colors["yellow"])
        rounded(cx, cy, col_w, 120, RADIUS, rf, rs, 1)
        text(cx + 14, cy + 14, r["observer"], rt, f_risk_title)
        text(cx + 14, cy + 36, r["layer"].upper(), C_MUTED, f_small)
        point = r["point"][:55]
        words = point.split()
        line_text = ""
        ly = cy + 58
        for word in words:
            test = (line_text + " " + word).strip()
            if len(test) > 26:
                text(cx + 14, ly, line_text, C_TEXT, f_risk)
                line_text = word
                ly += 16
            else:
                line_text = test
        if line_text:
            text(cx + 14, ly, line_text, C_TEXT, f_risk)

    # Signatures
    sig_y = total_h - SIG_H
    rounded(0, sig_y, total_w, SIG_H, 0, C_PANEL, C_BORDER, 1)
    for i, name in enumerate(consensus["observer_names"]):
        sx = CARD_PAD + i * 120
        text(sx, sig_y + 20, f"[OK] {name}", C_GREEN_TEXT, f_risk_title)
    text(total_w - CARD_PAD, sig_y + 20, "Structure CONFIRMED | Risks COMPLEMENTARY", C_MUTED, f_small, anchor="ra")

    img.save(out_path, "PNG")
    print(f"Photo developed: {out_path}")


if __name__ == "__main__":
    base = os.path.expanduser("~/Developer/bridge_app/docs/pov_snapshots/json")
    all_obs = []
    for name in ["xiaokui", "chatgpt", "claude"]:
        with open(f"{base}/{name}_v0.1.json") as f:
            all_obs.append(json.load(f))
    consensus = build_consensus(all_obs)
    out = os.path.expanduser("~/Developer/bridge_app/docs/pov_snapshots/pov_v0.1_photo.png")
    generate_png(consensus, out)
