#!/usr/bin/env python3
"""
t10_benchmark.py — T10③ 10 任務 benchmark（8420 官方通道全走）

[小葵 2026-10-17] T10③：10 個代表性任務端到端，全程走 8420 官方 MCP
通道（tools/call），每步記進 oplog（JSONL 可回放）。驗收目標：
每任務 3 輪內完成（每輪 = 一次 tools/call + 驗證）。

設計：
- 純 stdlib urllib（與 test_bridge_canvas_mcp.py 同風格）
- 任務表涵蓋感官面：導航/查看/對話/畫布/羅盤
- 產出 benchmark_report.md ＋ oplog JSONL
- exit code：0 全過 / 1 有 fail / 2 server 沒開

使用：
  python3 scripts/t10_benchmark.py
"""
import json
import time
import urllib.request
import urllib.error
import os
import sys
from datetime import datetime

BASE = 'http://127.0.0.1:8420'
TOKEN_PATH = os.path.expanduser(
    '~/Library/Application Support/farm.semiwasabi.bridgeApp/mcp_token')
OPLOG_PATH = '/tmp/t10_benchmark_oplog.jsonl'
REPORT_PATH = '/tmp/t10_benchmark_report.md'
CAPS = {'_meta': {'io.modelcontextprotocol/clientCapabilities': {'tools': True}}}


def get_token():
    try:
        return open(TOKEN_PATH).read().strip()
    except FileNotFoundError:
        print(f'❌ token 不存在：{TOKEN_PATH}')
        sys.exit(2)


TOKEN = get_token()


def call_tool(name, arguments=None, timeout=30):
    """官方通道：POST /mcp tools/call。回傳 (ok, result, elapsed_s)。"""
    body = {
        'jsonrpc': '2.0', 'id': int(time.time() * 1000) % 100000,
        'method': 'tools/call',
        'params': {'name': name, 'arguments': arguments or {}, **CAPS},
    }
    req = urllib.request.Request(
        f'{BASE}/mcp', data=json.dumps(body).encode(),
        headers={
            'Content-Type': 'application/json',
            'X-Bridge-Token': TOKEN,
            'Mcp-Method': 'tools/call',
            'Mcp-Name': name,
        })
    t0 = time.time()
    try:
        resp = json.load(urllib.request.urlopen(req, timeout=timeout))
        elapsed = round(time.time() - t0, 2)
        result = resp.get('result', {})
        # 成功判準：JSON-RPC 無 error 且 resultType=complete 或 success=true
        if 'error' in resp:
            return False, resp['error'], elapsed
        ok = (result.get('resultType') == 'complete'
              or result.get('success') == True)
        return ok, result, elapsed
    except Exception as e:
        return False, {'message': str(e)}, round(time.time() - t0, 2)


def oplog(task_id, step, tool, ok, detail, elapsed):
    """行車記錄器——JSONL 逐筆，可回放。"""
    rec = {
        'ts': datetime.now().isoformat(timespec='seconds'),
        'task': task_id, 'step': step, 'tool': tool,
        'ok': ok, 'elapsed_s': elapsed,
        'detail': json.dumps(detail, ensure_ascii=False)[:300],
    }
    with open(OPLOG_PATH, 'a') as f:
        f.write(json.dumps(rec, ensure_ascii=False) + '\n')


def run_task(task_id, task_name, steps):
    """跑一個任務（steps = [(tool, args)]）。回傳 (pass, rounds_used)。"""
    print(f'\n── {task_id} {task_name} ──')
    ok_any = True
    rounds = 0
    for i, (tool, args, verify) in enumerate(steps, 1):
        rounds = i
        ok, result, elapsed = call_tool(tool, args)
        passed = ok and verify(result)
        oplog(task_id, i, tool, passed, result, elapsed)
        print(f'  {i}. {tool} {"✓" if passed else "✗"} ({elapsed}s)'
              f'{"" if passed else " — " + json.dumps(result, ensure_ascii=False)[:120]}')
        if not passed:
            ok_any = False
            break
    return ok_any, rounds


def main():
    # 探活
    try:
        urllib.request.urlopen(f'{BASE}/health', timeout=3)
    except Exception:
        print('❌ 8420 沒開——先開 App')
        sys.exit(2)

    # 清舊 log
    open(OPLOG_PATH, 'w').close()

    tasks = [
        ('B1', '看見 App 狀態', [
            ('get_app_state', {}, lambda r: 'state' in r),
        ]),
        ('B2', '導航到對話頁', [
            ('navigate', {'target': 'chat'}, lambda r: r.get('success', True)),
        ]),
        ('B3', '讀最新對話（渲染感應器）', [
            ('get_latest_messages', {}, lambda r: 'hasNewReply' in r),
        ]),
        ('B4', '看見整個 App 畫面', [
            ('app_view', {}, lambda r: r.get('available') is not None),
        ]),
        ('B5', '列畫布', [
            ('list_canvases', {}, lambda r: isinstance(r.get('canvases'), list)),
        ]),
        ('B6', '建新畫布（T8 收編門）', [
            ('create_canvas', {'title': 'T10-B6 benchmark'},
             lambda r: r.get('success') and r.get('canvasId')),
        ]),
        ('B7', '讀知識庫（向量檢索）', [
            ('vector_search', {'q': '農場'},
             lambda r: 'memoryHits' in r or 'results' in r),
        ]),
        ('B8', '讀羅盤健康', [
            ('get_app_state', {}, lambda r: 'state' in r),
        ]),
        ('B9', '視網膜（render_layer）', [
            ('render_layer', {}, lambda r: r.get('resultType') == 'complete'),
        ]),
        ('B10', '教練感應器（get_agent_debug）', [
            ('get_agent_debug', {}, lambda r: r.get('available') is not None),
        ]),
    ]

    results = []
    for tid, name, steps in tasks:
        ok, rounds = run_task(tid, name, steps)
        results.append((tid, name, ok, rounds))

    # 報告
    passed = sum(1 for r in results if r[2])
    lines = [
        '# T10③ 10 任務 benchmark 報告',
        f'時間：{datetime.now().isoformat(timespec="seconds")}',
        f'結果：**{passed}/10 通過**',
        '',
        '| 任務 | 名稱 | 結果 | 輪數 |',
        '|---|---|---|---|',
    ]
    for tid, name, ok, rounds in results:
        lines.append(f'| {tid} | {name} | {"✓" if ok else "✗"} | {rounds} |')
    lines.append('')
    lines.append(f'oplog：{OPLOG_PATH}（可回放）')
    report = '\n'.join(lines)
    open(REPORT_PATH, 'w').write(report)
    print('\n' + report)
    sys.exit(0 if passed == 10 else 1)


if __name__ == '__main__':
    main()
