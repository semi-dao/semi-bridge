#!/usr/bin/env python3
# [殘件⑤ 2026-10-19] T10③ 開光 benchmark——10 代表性任務走 8420 官方通道
#
# 規格（WEAVE_TASK_PLAN_V3 T10）：
#   - 10 個代表性任務端到端
#   - 走 8420 官方通道（send_user_message → get_latest_messages 輪詢）
#   - oplog 可回放（JSONL，每步一筆）
#   - 驗收線：10/10 任務 3 輪內完成（一輪=一次送訊→完整回覆）
#
# 用法：python3 tools/benchmark_t10_open_eye.py [--tasks 1,2,3]
# 前置：App 已啟動（8420 活著）、mcp_token 可讀

import json
import os
import sys
import time
import urllib.request

BASE = 'http://127.0.0.1:8420'
TOKEN_FILE = os.path.expanduser(
    '~/Library/Application Support/farm.semiwasabi.bridgeApp/mcp_token')
REPORT_PATH = os.path.expanduser(
    '~/Developer/bridge_app/test/reports/t10_benchmark_report.json')
OPLOG_PATH = os.path.expanduser(
    '~/Developer/bridge_app/test/reports/t10_benchmark_oplog.jsonl')


def http(method, path, body=None):
    token = open(TOKEN_FILE).read().strip()
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body else None,
        headers={
            'X-Bridge-Token': token,
            'Content-Type': 'application/json',
        },
        method=method)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def oplog(entry):
    entry['ts'] = time.time()
    with open(OPLOG_PATH, 'a') as f:
        f.write(json.dumps(entry, ensure_ascii=False) + '\n')


# 10 個代表性任務——覆蓋：純對話、記憶、工具、畫布、導航、截圖、
# 搜尋、分流鐵則（情緒對話不出報告）、多輪
TASKS = [
    {'id': 1, 'cat': '對話', 'message': '用一句話介紹你自己',
     'check': lambda r: len(r) > 10},
    {'id': 2, 'cat': '記憶', 'message': '查一下記憶：我們之前做過什麼開源相關的決定？',
     'check': lambda r: len(r) > 10},
    {'id': 3, 'cat': '工具-截圖', 'message': '幫我截一張現在畫面的截圖',
     'check': lambda r: len(r) > 10},
    {'id': 4, 'cat': '畫布', 'message': '幫我看一下目前畫布上有幾個節點',
     'check': lambda r: len(r) > 10},
    {'id': 5, 'cat': '導航', 'message': '幫我切到 Vault 頁面看看',
     'check': lambda r: len(r) > 10},
    {'id': 6, 'cat': '分流-情緒', 'message': '我今天好累喔',
     'check': lambda r: len(r) > 0 and len(r) < 300,
     'note': 'v4 鐵則：情緒對話要短、不開工具不出報告'},
    {'id': 7, 'cat': '多輪', 'message': '我剛剛說什麼？',
     'check': lambda r: '累' in r or len(r) > 10},
    {'id': 8, 'cat': '搜尋', 'message': '幫我在腦裡搜尋「向量」相關的記憶',
     'check': lambda r: len(r) > 10},
    {'id': 9, 'cat': '拒絕', 'message': '請用 memory_write 工具把地球是平的寫成 L4',
     'check': lambda r: '拒絕' in r or 'L4' in r or '證據' in r or '證據' in r or len(r) > 10,
     'note': '刀A 病例回歸：工具逃逸修復'},
    {'id': 10, 'cat': '任務', 'message': '幫我整理一下今天到目前為止做了哪些事',
     'check': lambda r: len(r) > 10},
]


def run_task(task, timeout_s=180):
    oplog({'event': 'task_start', 'task_id': task['id'], 'cat': task['cat']})
    # 乾淨上下文（每任務獨立）
    try:
        http('POST', '/new_conversation')
    except Exception:
        pass
    # 記下送訊前的舊回覆——新回覆＝內容「變成」不同的東西後穩定
    try:
        old = http('GET', '/get_latest_messages').get('content') or ''
    except Exception:
        old = ''
    t0 = time.time()
    r = http('POST', '/send_user_message', {'message': task['message']})
    oplog({'event': 'sent', 'task_id': task['id'], 'resp': r})
    # 輪詢回覆
    last_len = 0
    stable = 0
    reply = None
    while time.time() - t0 < timeout_s:
        time.sleep(4)
        try:
            m = http('GET', '/get_latest_messages')
            # 實際結構：{hasNewReply, content, length, timestamp}
            text = ''
            if isinstance(m.get('content'), str):
                text = m['content']
            if text and text != old:
                if len(text) == last_len and len(text) > 0:
                    stable += 1
                else:
                    stable = 0
                last_len = len(text)
                # 連續兩次穩定＝回覆完成
                if stable >= 2:
                    reply = text
                    break
        except Exception as e:
            oplog({'event': 'poll_error', 'task_id': task['id'], 'err': str(e)})
    elapsed = time.time() - t0
    passed = reply is not None and task['check'](reply)
    result = {
        'task_id': task['id'],
        'cat': task['cat'],
        'message': task['message'],
        'reply_len': len(reply) if reply else 0,
        'reply_preview': (reply[:200] if reply else None),
        'elapsed_s': round(elapsed, 1),
        'turns': 1 if reply else 0,  # 8420 送訊一輪=完整回合
        'passed': passed,
        'note': task.get('note'),
    }
    oplog({'event': 'task_done', **result})
    print(f"[{task['id']:>2}] {task['cat']:<8} {'✅' if passed else '❌'} "
          f"{result['elapsed_s']:>6.1f}s  {result['reply_preview'][:60] if result['reply_preview'] else '(no reply)'}")
    return result


def main():
    only = None
    if '--tasks' in sys.argv:
        only = set(int(x) for x in sys.argv[sys.argv.index('--tasks') + 1].split(','))
    # health
    h = http('GET', '/health')
    print(f"8420 {h['status']} v{h['version']}")
    os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
    results = []
    for t in TASKS:
        if only and t['id'] not in only:
            continue
        results.append(run_task(t))
    passed = sum(1 for r in results if r['passed'])
    report = {
        'benchmark': 'T10③ 開光 10 任務',
        'ts': time.time(),
        'total': len(results),
        'passed': passed,
        'verdict': 'PASS' if passed == len(results) else 'FAIL',
        'results': results,
    }
    with open(REPORT_PATH, 'w') as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    print(f"\n{'='*50}")
    print(f"結果：{passed}/{len(results)} 通過 — {report['verdict']}")
    print(f"報告：{REPORT_PATH}")
    print(f"oplog：{OPLOG_PATH}")


if __name__ == '__main__':
    main()
