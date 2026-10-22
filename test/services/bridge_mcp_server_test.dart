// canvas_mcp_server_test.dart
// L1 驗證 — Bridge App Canvas MCP Server (MCP 2026-07-28 標準)
//
// [小葵 2026-08-05] MCP 2026-07-28 升級驗證測試
//
// 測試範圍：
// 1. 舊 REST 端點向後相容：GET /health, GET /state
// 2. 升級後的 tools/list：resultType=complete + ttlMs + cacheScope + _meta.serverInfo
// 3. 升級後的 /mcp/discover：protocolVersion: 2026-07-28
// 4. POST /mcp JSON-RPC 2.0 dispatch：server/discover, tools/list, tools/call
// 5. 標準錯誤碼：-32020 HeaderMismatch、-32022 UnsupportedProtocolVersion、
//                 -32021 MissingRequiredClientCapability
//
// 實作策略：
// 用 `createForTesting(port: 0)` 建立獨立 instance，server 啟動後 shelf 會把 OS 分配的
// 實際 port 寫回 `_server.port`。測試結束後 stop() 釋放。
//
// 為什麼用 E2E (HTTP) 而非直接呼叫 handler？
// BridgeMcpServer 的 handler 都是 library-private (`_` 開頭)，外部無法 import 訪問。
// 透過 HttpClient 打真實 endpoint 是最真實的驗證路徑，且 port=0 確保不撞 8420。

import 'dart:convert';
import 'dart:io';

import 'package:bridge_app/services/bridge_mcp_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('BridgeMcpServer — L1 MCP 2026-07-28 驗證', () {
    late BridgeMcpServer server;
    late int actualPort;

    setUpAll(() async {
      // 用一個短暫 HttpServer 探測 OS 分配的 free port，再關掉
      // 這避免 port 8420（Flutter App 佔用）衝突
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final freePort = probe.port;
      await probe.close(force: true);

      server = BridgeMcpServer.createForTesting(port: freePort);
      await server.start();
      actualPort = freePort;
    });

    tearDownAll(() async {
      await server.stop();
    });

    // ── 舊 REST 端點（向後相容）──────────────────────
    test('GET /health → 200 + status: ok', () async {
      final res = await _httpGet('http://127.0.0.1:$actualPort/health');
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['status'], 'ok');
      expect(body['service'], 'bridge-mcp');
    });

    test('GET /state → callback 未接線時 503', () async {
      final res = await _httpGet('http://127.0.0.1:$actualPort/state');
      expect(res.statusCode, 503);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error'], contains('Canvas controller not connected'));
    });

    test('GET /state → 接線 onGetState callback 後回傳 state', () async {
      server.onGetState = () async => {
            'nodes': [
              {'id': 'n1', 'type': 'llm', 'x': 100, 'y': 200},
            ],
            'connections': <Map<String, dynamic>>[],
            'viewport': {'x': 0, 'y': 0, 'zoom': 1.0},
          };
      final res = await _httpGet('http://127.0.0.1:$actualPort/state');
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['nodes'], isA<List<dynamic>>());
      expect((body['nodes'] as List).length, 1);
      expect((body['nodes'] as List).first['id'], 'n1');
      // 清掉 callback 避免污染後續測試
      server.onGetState = null;
    });

    // ── 升級後的 tools/list（CacheableResult）──────────
    test('GET /mcp/tools → 帶 resultType=complete + ttlMs + cacheScope + _meta.serverInfo', () async {
      final res = await _httpGet('http://127.0.0.1:$actualPort/mcp/tools');
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      // MCP 2026-07-28 必填欄位
      expect(body['resultType'], 'complete');
      expect(body['ttlMs'], 60000);
      expect(body['cacheScope'], 'private');

      // _meta.serverInfo（SEP-2549）
      final meta = body['_meta'] as Map<String, dynamic>;
      expect(meta, isNotNull);
      final serverInfo = meta['io.modelcontextprotocol/serverInfo'] as Map<String, dynamic>;
      expect(serverInfo['name'], 'bridge-mcp');
      expect(serverInfo['version'], '2.0.0');
      expect(serverInfo['title'], 'Bridge App Canvas MCP Server');

      // 至少要有 tools 列表（持續新增工具；2026-09-22 實際 14）
      final tools = body['tools'] as List<dynamic>;
      expect(tools.length, greaterThanOrEqualTo(11));
    });

    // ── GET /mcp/discover（MCP 2026-07-28）────────────
    test('GET /mcp/discover → 帶 protocolVersion: 2026-07-28', () async {
      final res = await _httpGet('http://127.0.0.1:$actualPort/mcp/discover');
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['resultType'], 'complete');
      expect(body['protocolVersion'], '2026-07-28');
      expect(body['supportedVersions'], ['2026-07-28']);
      expect(body['capabilities'], isA<Map<String, dynamic>>());
      expect((body['capabilities'] as Map)['tools'], isNotNull);
      expect(body['serverInfo']['name'], 'bridge-mcp');
    });

    // ── POST /mcp JSON-RPC 2.0 dispatch ─────────────
    test('POST /mcp server/discover → 回 protocolVersion + capabilities', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'server/discover',
          'params': {
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'server/discover',
        },
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['jsonrpc'], '2.0');
      expect(body['id'], 1);
      final result = body['result'] as Map<String, dynamic>;
      expect(result['protocolVersion'], '2026-07-28');
    });

    // [開光 P0 2026-09-26] 22 → 28：app_view/render_layer/vector_search/get_agent_debug
    // 首次納入 + auto_layout/get_last_response 補收錄。發現新工具時更新此數字。
    // [開光 P1 2026-09-26] 28 → 30：app_look（語意化視網膜）+ window_map（心之地圖）。
    // [開光 P2 2026-09-26] 30 → 32：app_tap（語意點擊）+ canvas_zoom（縮放讀寫）
    // [開光 P3 2026-09-26] 32 → 34：app_permissions（權限即地圖）+ window_control（視窗管理）
    // [S1+S2 合併 2026-10-12] 48（app_look/app_tap 雙 schema 重複註冊）→ 43：
    // app_look 與 app_tap 各自雙 schema 合併為一份，重複註冊終結。
    test('POST /mcp tools/list → 49 tools + 每個有 inputSchema (JSON Schema 2020-12)', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/list',
          'params': {
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/list',
        },
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>;
      expect(result['resultType'], 'complete');
      expect(result['ttlMs'], 60000);
      expect(result['cacheScope'], 'private');
      final tools = result['tools'] as List<dynamic>;
      // [開光 P0 2026-09-26] 22 → 28（見 test 名稱註解）
      // [開光 P1 2026-09-26] 28 → 30：app_look + window_map
      // [開光 P3 2026-09-26] 32 → 34：app_permissions + window_control
      // [S1+S2 合併 2026-10-12] 48 → 43：app_look/app_tap 雙 schema 合併
      expect(tools.length, 49); // [A線 1022] app_type 收編 48→49

      // 每個 tool 都必須有 inputSchema（JSON Schema 2020-12 結構）
      for (final t in tools) {
        final tool = t as Map<String, dynamic>;
        expect(tool['name'], isA<String>());
        expect(tool['inputSchema'], isA<Map<String, dynamic>>());
        expect((tool['inputSchema'] as Map)['type'], 'object');
      }
    });

    test('POST /mcp tools/call list_canvases → 接線 callback 後回 canvases', () async {
      server.onListCanvases = () => [
            {'id': 'c1', 'name': '主畫布', 'tabIndex': 0},
            {'id': 'c2', 'name': '測試畫布', 'tabIndex': 1},
          ];
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'tools/call',
          'params': {
            'name': 'list_canvases',
            'arguments': <String, dynamic>{},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'list_canvases',
        },
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>;
      expect(result['resultType'], 'complete');
      final canvases = result['canvases'] as List<dynamic>;
      expect(canvases.length, 2);
      expect(canvases.first['id'], 'c1');
      server.onListCanvases = null;
    });

    test('POST /mcp tools/call navigate_to_canvas → 觸發 callback', () async {
      var triggered = false;
      server.onNavigateToCanvas = () {
        triggered = true;
      };
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 4,
          'method': 'tools/call',
          'params': {
            'name': 'navigate_to_canvas',
            'arguments': <String, dynamic>{},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'navigate_to_canvas',
        },
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['result']['success'], true);
      expect(body['result']['message'], contains('畫布'));
      expect(triggered, isTrue);
    });

    // ── [開光 P0 · 小葵 2026-09-26] 單一真相源 + 眼/腦工具 ──────────
    test('開光：GET /mcp/tools 與 tools/list 同源（單一真相源）', () async {
      final restRes = await _httpGet('http://127.0.0.1:$actualPort/mcp/tools');
      final rpcRes = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 100,
          'method': 'tools/list',
          'params': {
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/list',
        },
      );
      final restBody = jsonDecode(restRes.body) as Map<String, dynamic>;
      final rpcBody = jsonDecode(rpcRes.body) as Map<String, dynamic>;
      final restNames = (restBody['tools'] as List<dynamic>).map((t) => t['name']).toSet();
      final rpcNames = (rpcBody['result']['tools'] as List<dynamic>).map((t) => t['name']).toSet();
      expect(restNames.length, greaterThanOrEqualTo(26)); // 22 + 開光新增 4（等於 tools/list 同步）
      expect(restNames, equals(rpcNames)); // 同源鐵則：兩份清單完全一致
    });

    test('開光：dispatch schema 全收錄——清單列出的每個工具都必須有 case（反 get_last_response 蟲）', () async {
      final res = await _httpGet('http://127.0.0.1:$actualPort/mcp/tools');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final names = (body['tools'] as List<dynamic>).map((t) => t['name'] as String).toList();
      // 2026-09-26 開光後：27 個工具全部收錄
      expect(names, containsAll(<String>[
        'get_canvas_state', 'screenshot', 'add_node', 'connect', 'remove_node',
        'execute', 'navigate_to_canvas', 'send_chat', 'send_user_message',
        'send_canvas_message', 'inject_message', 'navigate', 'get_app_state',
        'list_canvases', 'load_canvas', 'get_annotations', 'get_latest_messages',
        'brain_reindex', 'set_node_params', 'get_node_params', 'clear_canvas',
        'load_template', 'auto_layout', 'get_last_response', 'app_view',
        'render_layer', 'vector_search', 'get_agent_debug',
        'app_look', 'window_map',
        'app_tap', 'canvas_zoom',
        'app_permissions', 'window_control',
        'create_canvas', // [T8①] 收編
        'app_type', // [A線 2026-10-22] 文字注入收編
      ]));
      expect(names.length, 49); // [A線 1022] app_type 收編（48→49）——長度鎖每次收編更新
    });

    test('開光：app_view（無 UI 測試環境）→ available:false 不炸', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 101,
          'method': 'tools/call',
          'params': {
            'name': 'app_view',
            'arguments': <String, dynamic>{},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'app_view',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['result']['resultType'], 'complete');
      // 無渲染環境 AppRetina.capture 回 null → available:false（不是 throw）
      expect(body['result']['available'], false);
    });

    // ── [開光 P1 · 2026-09-26] app_look / window_map 專屬測試 ──────
    test('開光 P1：app_look 給無效 target → -32602 帶合法清單（不猜）', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 201,
          'method': 'tools/call',
          'params': {
            'name': 'app_look',
            'arguments': {'target': '不存在的頁面'},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'app_look',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], -32602);
      expect(body['error']['message'], contains('home'));
      expect(body['error']['message'], contains('canvas'));
    });

    test('開光 P1：app_look target=app（不導航，拍當下）→ 測試環境 available:false', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 202,
          'method': 'tools/call',
          'params': {
            'name': 'app_look',
            'arguments': {'target': 'app'},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'app_look',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      // 測試環境無 UI：導航不觸發（target=app），拍照優雅降級 available:false
      expect(body['result']['resultType'], 'complete');
      expect(body['result']['available'], false);
      expect(body['result']['target'], 'app');
    });

    test('開光 P1：window_map（無 window_manager 測試環境）→ 地圖優雅降級不炸', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 203,
          'method': 'tools/call',
          'params': {
            'name': 'window_map',
            'arguments': <String, dynamic>{},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'window_map',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['result']['resultType'], 'complete');
      // 測試環境：window_manager 未初始化 → available:false 帶原因（誠實降級）
      expect(body['result']['mainWindow']['available'], false);
      // PID 必須有——地圖的基本盤
      expect(body['result']['pid'], isA<int>());
    });

    // ── [開光 P2 · 2026-09-26] app_tap / canvas_zoom 專屬測試 ──────
    test('開光 P2：app_tap 給無效 target → -32602 帶合法按鈕清單', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 301,
          'method': 'tools/call',
          'params': {
            'name': 'app_tap',
            'arguments': {'target': 'canvas_toolbar:爆炸按鈕'},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'app_tap',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], -32602);
      expect(body['error']['message'], contains('canvas_toolbar:save'));
      expect(body['error']['message'], contains('canvas_toolbar:run'));
    });

    test('開光 P2：app_tap 未接線（測試環境無 workspace）→ -32603 誠實降級', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 302,
          'method': 'tools/call',
          'params': {
            'name': 'app_tap',
            'arguments': {'target': 'canvas_toolbar:save'},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'app_tap',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      // 測試環境 onTap == null → -32603（不是 crash）
      expect(body['error']['code'], -32603);
      expect(body['error']['message'], contains('not connected'));
    });

    test('開光 P2：canvas_zoom 未接畫布（測試環境）→ -32603 誠實降級', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 303,
          'method': 'tools/call',
          'params': {
            'name': 'canvas_zoom',
            'arguments': <String, dynamic>{},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'canvas_zoom',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      // 測試環境無前景 controller → -32603（誠實，不假成功）
      expect(body['error']['code'], -32603);
      expect(body['error']['message'], contains('Canvas controller not connected'));
    });

    // ── [開光 P3 · 2026-09-26] app_permissions / window_control 測試 ──
    test('開光 P3：app_permissions → 必含 entitlements 八欄 + dependencies 探測', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 401,
          'method': 'tools/call',
          'params': {
            'name': 'app_permissions',
            'arguments': <String, dynamic>{},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'app_permissions',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final r = body['result'];
      expect(r['resultType'], 'complete');
      // entitlements 八欄齊全（codesign 在 CI 可能失敗→available:false 也是合法，但欄位必在）
      expect(r['entitlements'], isA<Map<String, dynamic>>());
      expect(r['dependencies'], isA<Map<String, dynamic>>());
      expect(r['dependencies'].containsKey('osascript'), true);
      expect(r['pid'], isA<int>());
    });

    test('開光 P3：window_control 無效 action → -32602 帶合法清單', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 402,
          'method': 'tools/call',
          'params': {
            'name': 'window_control',
            'arguments': {'action': '爆炸'},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'window_control',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], -32602);
      expect(body['error']['message'], contains('focus'));
      expect(body['error']['message'], contains('restore'));
    });

    test('開光 P3：window_control focus（測試環境 window_manager 未初始化）→ success:false 誠實降級', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 403,
          'method': 'tools/call',
          'params': {
            'name': 'window_control',
            'arguments': {'action': 'focus'},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'window_control',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final r = body['result'];
      expect(r['resultType'], 'complete');
      // 測試環境 window_manager 未初始化 → success:false 帶原因（UI 誠實鐵則）
      expect(r['success'], false);
      expect(r['message'], contains('window_manager'));
    });

    test('開光：vector_search 缺 q → -32602（參數驗證不靠撞）', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 102,
          'method': 'tools/call',
          'params': {
            'name': 'vector_search',
            'arguments': <String, dynamic>{},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'vector_search',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], -32602);
      expect(body['error']['message'], contains('q required'));
    });

    test('開光：get_agent_debug（callback 未接線）→ available:false', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 103,
          'method': 'tools/call',
          'params': {
            'name': 'get_agent_debug',
            'arguments': <String, dynamic>{},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'get_agent_debug',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['result']['resultType'], 'complete');
      expect(body['result']['available'], isFalse);
    });

    // ── 標準錯誤碼 ──────────────────────────────────
    test('POST /mcp HeaderMismatch (Mcp-Method 跟 body method 不一致) → -32020', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 5,
          'method': 'tools/list', // body 說 tools/list
          'params': {
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call', // header 說 tools/call → 不一致！
        },
      );
      expect(res.statusCode, 200); // JSON-RPC error 仍回 200
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], -32020);
      expect(body['error']['message'], contains('Header mismatch'));
    });

    test('POST /mcp UnsupportedProtocolVersion (header 帶 2025-11-25) → -32022', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 6,
          'method': 'tools/list',
          'params': {
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2025-11-25', // 不支援的舊版
          'Mcp-Method': 'tools/list',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], -32022);
      expect(body['error']['message'], contains('Unsupported protocol version'));
    });

    test('POST /mcp MissingRequiredClientCapability (_meta 沒帶 clientCapabilities) → -32021', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 7,
          'method': 'tools/list',
          'params': {
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              // 故意不帶 clientCapabilities
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/list',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], -32021);
      expect(body['error']['message'], contains('Missing required'));
      expect(body['error']['data']['requiredCapabilities'], contains('clientCapabilities'));
    });

    test('POST /mcp 不合法 JSON → -32700 (Parse error)', () async {
      final res = await _httpPostRaw(
        'http://127.0.0.1:$actualPort/mcp',
        '{ not json',
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/list',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], -32700);
    });

    test('POST /mcp Method not found → -32601', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 8,
          'method': 'nonexistent/method',
          'params': {
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'nonexistent/method',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], -32601);
    });
  });
}

// ── HTTP helpers（stdlib dart:io HttpClient）──────────

Future<_HttpResponse> _httpGet(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return _HttpResponse(res.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

Future<_HttpResponse> _httpPost(
  String url, {
  required Map<String, dynamic> body,
  Map<String, String>? headers,
}) async {
  return _httpPostRaw(
    url,
    jsonEncode(body),
    headers: {
      'Content-Type': 'application/json',
      ...?headers,
    },
  );
}

Future<_HttpResponse> _httpPostRaw(
  String url,
  String body, {
  Map<String, String>? headers,
}) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse(url));
    // [開光 P1 2026-09-26] ContentType.json 預設 charset=latin-1，req.write(中文) 會炸
    // （Invalid argument (string): Contains invalid characters.）——JSON 一律 UTF-8 bytes。
    req.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    headers?.forEach((k, v) => req.headers.set(k, v));
    req.add(utf8.encode(body));
    final res = await req.close();
    final resBody = await res.transform(utf8.decoder).join();
    return _HttpResponse(res.statusCode, resBody);
  } finally {
    client.close(force: true);
  }
}

class _HttpResponse {
  final int statusCode;
  final String body;
  _HttpResponse(this.statusCode, this.body);
}

// 確保 shelf import 沒被 lint 抱怨（測試不需要直接用 Response）
// ignore: unused_element
Response _unusedShelfImport() => Response.ok('{}');
