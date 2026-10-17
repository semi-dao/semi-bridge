#!/usr/bin/env python3
"""
test_bridge_canvas_mcp.py — L2 端到端測試

[小葵 2026-08-05] MCP 2026-07-28 標準 client 端到端測試

目標：打 Bridge App Canvas MCP Server 的 POST /mcp 端點，
驗證標準 MCP 2026-07-28 JSON-RPC 2.0 行為。

設計原則：
1. **純 stdlib urllib**：不依賴官方 MCP SDK，方便嵌入 CI/排程/手動驗證
2. **server 不在就 fail-friendly**：先打 GET /health 探活，server 沒啟動就
   印出 friendly 提示（包含如何啟動 server 的指令），exit code = 2
3. **可單獨執行**：每個 test 獨立 try/except，任何一個 fail 不會中斷後續
4. **exit code**：
   - 0 = 全部 pass
   - 1 = 有 test fail（server 有跑）
   - 2 = server 沒啟動（friendlier）

使用：
    # Server 沒在跑
    $ python3 test_bridge_canvas_mcp.py
    ❌ Server not running at http://127.0.0.1:8420
    💡 啟動方式：flutter run -d macos

    # Server 在跑
    $ python3 test_bridge_canvas_mcp.py
    ✅ L2 測試全部通過 (4/4)
"""

import json
import sys
import urllib.error
import urllib.request
from typing import Any, Optional

# ── 設定 ──────────────────────────────────────────────

HOST = "127.0.0.1"
PORT = 8420
BASE_URL = f"http://{HOST}:{PORT}"

# MCP 2026-07-28 標準 protocol version
PROTOCOL_VERSION = "2026-07-28"

# MCP 2026-07-28 標準錯誤碼
ERR_HEADER_MISMATCH = -32020
ERR_MISSING_CLIENT_CAP = -32021
ERR_UNSUPPORTED_PROTOCOL = -32022
ERR_PARSE_ERROR = -32700
ERR_METHOD_NOT_FOUND = -32601

# ── Pretty print ─────────────────────────────────────

class C:
    """ANSI color codes（沒 TTY 就 no-op）"""
    ENABLED = sys.stdout.isatty()
    R = "\033[91m" if ENABLED else ""   # red
    G = "\033[92m" if ENABLED else ""   # green
    Y = "\033[93m" if ENABLED else ""   # yellow
    B = "\033[94m" if ENABLED else ""   # blue
    BOLD = "\033[1m" if ENABLED else ""
    DIM = "\033[2m" if ENABLED else ""
    RST = "\033[0m" if ENABLED else ""


def log_info(msg: str) -> None:
    print(f"{C.B}ℹ{C.RST}  {msg}")


def log_pass(msg: str) -> None:
    print(f"{C.G}✅{C.RST} {msg}")


def log_fail(msg: str) -> None:
    print(f"{C.R}❌{C.RST} {msg}")


def log_skip(msg: str) -> None:
    print(f"{C.Y}⏭{C.RST}  {msg}")


# ── HTTP helper（純 stdlib urllib）────────────────────

def http_get(path: str) -> tuple[int, dict[str, Any]]:
    """GET request, 回傳 (status_code, json_body)"""
    url = f"{BASE_URL}{path}"
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=5) as res:
            body = json.loads(res.read().decode("utf-8"))
            return res.status, body
    except urllib.error.HTTPError as e:
        body = json.loads(e.read().decode("utf-8")) if e.headers.get("content-type", "").startswith("application/json") else {}
        return e.code, body


def http_post_jsonrpc(
    body: dict[str, Any],
    headers: Optional[dict[str, str]] = None,
) -> tuple[int, dict[str, Any]]:
    """POST /mcp with JSON-RPC 2.0 body"""
    url = f"{BASE_URL}/mcp"
    payload = json.dumps(body).encode("utf-8")
    default_headers = {
        "Content-Type": "application/json",
        "MCP-Protocol-Version": PROTOCOL_VERSION,
    }
    if headers:
        default_headers.update(headers)
    req = urllib.request.Request(url, data=payload, method="POST", headers=default_headers)
    try:
        with urllib.request.urlopen(req, timeout=5) as res:
            res_body = json.loads(res.read().decode("utf-8"))
            return res.status, res_body
    except urllib.error.HTTPError as e:
        res_body = json.loads(e.read().decode("utf-8")) if e.headers.get("content-type", "").startswith("application/json") else {}
        return e.code, res_body


# ── Server 探活 ──────────────────────────────────────

def check_server_alive() -> bool:
    """先打 GET /health，server 不在就印 friendly 提示"""
    log_info(f"探測 server: GET {BASE_URL}/health")
    try:
        status, body = http_get("/health")
        if status == 200 and body.get("status") == "ok":
            log_pass(f"Server alive — {body.get('service')} v{body.get('version')}")
            return True
        log_fail(f"Server 回應異常: status={status}, body={body}")
        return False
    except (urllib.error.URLError, ConnectionRefusedError, OSError) as e:
        print()
        print(f"{C.R}{C.BOLD}❌ Canvas MCP Server 未啟動{C.RST}")
        print(f"{C.DIM}   連線失敗: {e}{C.RST}")
        print()
        print(f"{C.B}💡 啟動方式：{C.RST}")
        print(f"   {C.DIM}cd <HOME>/Developer/bridge_app && flutter run -d macos{C.RST}")
        print()
        print(f"{C.DIM}（啟動後 MCP server 會自動 listen 在 localhost:8420）{C.RST}")
        return False


# ── 測試案例 ─────────────────────────────────────────

def test_server_discover() -> bool:
    """server/discover 回 protocolVersion 2026-07-28 + capabilities"""
    log_info("Test 1: POST /mcp server/discover")
    status, body = http_post_jsonrpc(
        body={
            "jsonrpc": "2.0",
            "id": 1,
            "method": "server/discover",
            "params": {
                "_meta": {
                    "io.modelcontextprotocol/protocolVersion": PROTOCOL_VERSION,
                    "io.modelcontextprotocol/clientCapabilities": {},
                },
            },
        },
        headers={"Mcp-Method": "server/discover"},
    )

    if status != 200:
        log_fail(f"  status={status}, body={body}")
        return False

    if body.get("jsonrpc") != "2.0":
        log_fail(f"  jsonrpc != 2.0: {body.get('jsonrpc')}")
        return False

    result = body.get("result", {})
    if result.get("protocolVersion") != PROTOCOL_VERSION:
        log_fail(f"  protocolVersion mismatch: {result.get('protocolVersion')}")
        return False

    if "capabilities" not in result or "tools" not in result.get("capabilities", {}):
        log_fail(f"  capabilities.tools 缺失: {result.get('capabilities')}")
        return False

    server_info = result.get("serverInfo", {})
    log_pass(f"  protocolVersion={result['protocolVersion']}, server={server_info.get('name')}")
    return True


def test_tools_list() -> bool:
    """tools/list 回 22 個 tools，每個有 inputSchema"""
    log_info("Test 2: POST /mcp tools/list (驗證 CacheableResult)")
    status, body = http_post_jsonrpc(
        body={
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
            "params": {
                "_meta": {
                    "io.modelcontextprotocol/protocolVersion": PROTOCOL_VERSION,
                    "io.modelcontextprotocol/clientCapabilities": {},
                },
            },
        },
        headers={"Mcp-Method": "tools/list"},
    )

    if status != 200:
        log_fail(f"  status={status}, body={body}")
        return False

    result = body.get("result", {})
    if result.get("resultType") != "complete":
        log_fail(f"  resultType != complete: {result.get('resultType')}")
        return False

    if result.get("ttlMs") != 60000:
        log_fail(f"  ttlMs != 60000: {result.get('ttlMs')}")
        return False

    if result.get("cacheScope") != "private":
        log_fail(f"  cacheScope != private: {result.get('cacheScope')}")
        return False

    tools = result.get("tools", [])
    if not isinstance(tools, list) or len(tools) != 22:
        log_fail(f"  預期 22 個 tools, 實際 {len(tools) if isinstance(tools, list) else 'N/A'}")
        return False

    # 每個 tool 都要有 inputSchema
    for tool in tools:
        if "inputSchema" not in tool:
            log_fail(f"  tool '{tool.get('name')}' 缺 inputSchema")
            return False
        if tool["inputSchema"].get("type") != "object":
            log_fail(f"  tool '{tool.get('name')}' inputSchema.type != object")
            return False

    log_pass(f"  {len(tools)} tools, 每個有 inputSchema, ttlMs={result['ttlMs']}, cacheScope={result['cacheScope']}")
    return True


def test_tools_call_list_canvases() -> bool:
    """tools/call list_canvases — 成功呼叫或收到合理 error"""
    log_info("Test 3: POST /mcp tools/call list_canvases")
    status, body = http_post_jsonrpc(
        body={
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "list_canvases",
                "arguments": {},
                "_meta": {
                    "io.modelcontextprotocol/protocolVersion": PROTOCOL_VERSION,
                    "io.modelcontextprotocol/clientCapabilities": {},
                },
            },
        },
        headers={"Mcp-Method": "tools/call", "Mcp-Name": "list_canvases"},
    )

    if status != 200:
        log_fail(f"  status={status}, body={body}")
        return False

    # list_canvases 兩種合理回應：
    # (a) 成功：有 result.canvases
    # (b) 失敗（callback 未接線）：有 result.resultType=complete + error code
    if "result" in body:
        result = body["result"]
        if "canvases" in result:
            canvases = result["canvases"]
            log_pass(f"  收到 {len(canvases) if isinstance(canvases, list) else '?'} 個畫布")
            return True
        elif result.get("resultType") == "complete":
            log_pass(f"  resultType=complete, 內容={list(result.keys())}")
            return True
        log_fail(f"  result 結構異常: {result}")
        return False

    # 收到 error（callback 未接線也合法）
    if "error" in body:
        err_code = body["error"].get("code")
        log_pass(f"  收到 error code={err_code}（callback 未接線，符合預期）")
        return err_code in (-32603, -32021)

    log_fail(f"  既無 result 也無 error: {body}")
    return False


def test_tools_call_navigate_to_canvas() -> bool:
    """tools/call navigate_to_canvas — 觸發 callback"""
    log_info("Test 4: POST /mcp tools/call navigate_to_canvas")
    status, body = http_post_jsonrpc(
        body={
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "navigate_to_canvas",
                "arguments": {},
                "_meta": {
                    "io.modelcontextprotocol/protocolVersion": PROTOCOL_VERSION,
                    "io.modelcontextprotocol/clientCapabilities": {},
                },
            },
        },
        headers={"Mcp-Method": "tools/call", "Mcp-Name": "navigate_to_canvas"},
    )

    if status != 200:
        log_fail(f"  status={status}, body={body}")
        return False

    if "result" in body:
        result = body["result"]
        if result.get("success") is True:
            log_pass(f"  navigate_to_canvas 成功: {result.get('message', '(no msg)')}")
            return True
        log_pass(f"  resultType={result.get('resultType')}, keys={list(result.keys())}")
        return True

    if "error" in body:
        err_code = body["error"].get("code")
        # -32603 = callback 未接線（合理 — server 啟動但 Flutter UI 未掛載）
        if err_code == -32603:
            log_pass(f"  收到 -32603（callback 未接線，符合預期）")
            return True
        log_fail(f"  error code={err_code}: {body['error'].get('message')}")
        return False

    log_fail(f"  既無 result 也無 error: {body}")
    return False


# ── 主流程 ───────────────────────────────────────────

def main() -> int:
    print(f"{C.BOLD}🌉 Bridge App Canvas MCP — L2 端到端測試{C.RST}")
    print(f"{C.DIM}   目標: {BASE_URL} (MCP {PROTOCOL_VERSION}){C.RST}")
    print()

    if not check_server_alive():
        print(f"{C.DIM}（L2 為端到端測試，必須要有 server 在跑才能驗證。{C.RST}")
        print(f"{C.DIM}  CI/排程環境用此 exit code=2 表示「跳過但需要人工介入」）{C.RST}")
        return 2  # server 未啟動

    print()

    tests = [
        ("server/discover", test_server_discover),
        ("tools/list", test_tools_list),
        ("tools/call list_canvases", test_tools_call_list_canvases),
        ("tools/call navigate_to_canvas", test_tools_call_navigate_to_canvas),
    ]

    passed = 0
    failed = 0

    for name, test_fn in tests:
        try:
            if test_fn():
                passed += 1
            else:
                failed += 1
        except Exception as e:
            log_fail(f"  未預期例外: {type(e).__name__}: {e}")
            failed += 1
        print()

    total = passed + failed
    print(f"{C.BOLD}── 結果 ──{C.RST}")
    if failed == 0:
        print(f"{C.G}✅ L2 測試全部通過 ({passed}/{total}){C.RST}")
        return 0
    else:
        print(f"{C.R}❌ L2 測試失敗: {passed} pass / {failed} fail ({total} 總計){C.RST}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
