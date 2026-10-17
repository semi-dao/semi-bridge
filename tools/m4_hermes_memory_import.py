#!/usr/bin/env python3
"""M4: Hermes 記憶搬入器——MEMORY.md / USER.md → brain_container.db 十層

§ = 條目分隔符。每條依關鍵字路由到對應層：
  L1 鐵則 / L2 身分 / L3 專案熱 / L4 環境 / L5 決策 / L6 教訓
  其餘 → L8 對話精華（兜底，永不丟）

冪等：以 title 為鍵，已存在（migration_id 前綴）就跳過。
"""
import sqlite3, sys, datetime

DB = '<HOME>/Library/Application Support/farm.semiwasabi.bridgeApp/brain_container.db'
OWNER = 'cmp_1789262474022_ext'  # 小葵私有（人格是私有的）

# 路由規則（先具體後一般；★開頭=高重要性，鐵則優先）
def route(text: str) -> tuple[str, str]:  # (layer, memory_type)
    if text.startswith('★') or any(k in text for k in ['鐵則', '鐵律', '禁', '紅旗', '必必', '必問']):
        return 'L1', 'hermes_rule'
    if any(k in text for k in ['Blue信仰', '小葵', '我=', '勿稱', '人格']):
        return 'L2', 'hermes_identity'
    if any(k in text for k in ['山門若水', '農場', 'IG', 'FB', 'SemiDAO', '橋樑App', '插槽', 'H2', 'H線', 'C線', 'M線']):
        return 'L3', 'hermes_project'
    if any(k in text for k in ['路徑', '埠', 'token', '@', 'Mac', '=/vm', ':/', 'GLM', 'E4B', '18789', '10核']):
        return 'L4', 'hermes_env'
    if any(k in text for k in ['拍板', '定案', '贈禮', '封卷', '治理']):
        return 'L5', 'hermes_decision'
    if any(k in text for k in ['陷阱', '教訓', '誤', '崩', '修法', '實證', '抓包']):
        return 'L6', 'hermes_lesson'
    return 'L8', 'hermes_memory'

def parse(path):
    txt = open(path, encoding='utf-8').read()
    # § 分隔；§ 可能在行首或行中——直接切
    parts = [p.strip(' \n') for p in txt.replace('\n', ' ').split('§')]
    return [p for p in parts if len(p) >= 8]  # 太短的不是條目

def main():
    conn = sqlite3.connect(DB)
    cur = conn.cursor()
    now = datetime.datetime.now().isoformat()
    stats = {}
    total_in = total_skip = 0

    for src, mtype_prefix in [('<HOME>/.hermes/memories/MEMORY.md', 'hermes_mem'),
                              ('<HOME>/.hermes/memories/USER.md', 'hermes_user')]:
        for entry in parse(src):
            layer, mtype = route(entry)
            title = entry[:40] + ('…' if len(entry) > 40 else '')
            # 冪等檢查
            cur.execute("SELECT COUNT(*) FROM agent_memories WHERE title = ? AND memory_type = ?", (title, mtype))
            if cur.fetchone()[0] > 0:
                total_skip += 1
                continue
            mid = f'mig_m4_{abs(hash(entry)) % 10**12}'
            cur.execute("""INSERT INTO agent_memories
                (id, title, content, tags, memory_type, layer, owner_companion_id, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (mid, title, entry, mtype_prefix, mtype, layer, OWNER, now))
            stats[layer] = stats.get(layer, 0) + 1
            total_in += 1

    conn.commit()
    print(f"搬入 {total_in} 條，跳過（已存在）{total_skip} 條")
    for k in sorted(stats):
        print(f"  {k}: {stats[k]}")
    # 驗證
    print('── 驗證 ──')
    for row in cur.execute("SELECT layer, COUNT(*) FROM agent_memories WHERE memory_type LIKE 'hermes_%' GROUP BY layer ORDER BY layer"):
        print(f"  {row[0]}: {row[1]}")
    conn.close()

if __name__ == '__main__':
    main()
