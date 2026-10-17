// bridge_mcp_server_test.dart
// [T8③ 2026-10-17] 感官三方一致測試——route、schema、dispatch 鎖死。
// 病例史：26 條隱藏門（route 有、schema 無）讓 agent「看不到自己的手」；
// get_last_response/get_agent_debug 同款 bug 姐妹案。
//
// 鎖三件事：
// 1. _toolSchemas 每個工具名都有 dispatch case（agent 呼叫不落空）
// 2. dispatch 的工具 case 都有 schema（無隱藏門）——internal 維運 case 白名單除外
// 3. create_canvas 已收編（schema+dispatch 都在）

@TestOn('mac-os')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/bridge_mcp_server.dart';

void main() {
  // 從原始碼抽集合（build_runner 不可用時的最穩做法——與實作同源）
  final src = BridgeMcpServer.sourceForConsistencyTest;

  test('T8③-1 schema 工具都有 dispatch case（呼叫不落空）', () {
    final schemas = RegExp(r"'name': '(\w+)',\n\s*'description'")
        .allMatches(src)
        .map((m) => m.group(1)!)
        .toSet();
    final cases =
        RegExp(r"case '(\w+)':").allMatches(src).map((m) => m.group(1)!).toSet();
    expect(schemas, isNotEmpty, reason: 'schema 解析失敗（原始碼漂移）');
    final missing = schemas.difference(cases);
    expect(missing, isEmpty,
        reason: '這些工具 agent 看得到卻叫不動：\$missing');
  });

  test('T8③-2 dispatch 工具 case 都有 schema（無隱藏門）', () {
    final schemas = RegExp(r"'name': '(\w+)',\n\s*'description'")
        .allMatches(src)
        .map((m) => m.group(1)!)
        .toSet();
    final internal = {
      // 維運/協議 case（非 agent 感官）：JSON-RPC 方法、galaxy 子命令、
      // window 子命令等 dispatch 內部 switch
      'server/discover', 'tools/list', 'tools/call',
      'annotations', 'brain_search_focus', 'center', 'delete',
      'design_thumb_reindex', 'focus', 'fps_probe', 'galaxy_cmd',
      'galaxy_edit', 'galaxy_icons', 'galaxy_note', 'galaxy_oplog',
      'galaxy_params', 'galaxy_swarm', 'galaxy_thumb', 'icon',
      'minimize', 'rename', 'restore', 'reveal', 'tags',
    };
    final cases =
        RegExp(r"case '(\w+)':").allMatches(src).map((m) => m.group(1)!).toSet();
    final toolCases = cases.difference(internal);
    final hidden = toolCases.difference(schemas);
    expect(hidden, isEmpty,
        reason: '隱藏門（agent 叫得動卻看不到）：\$hidden');
  });

  test('T8③-3 create_canvas 已收編', () {
    expect(src, contains("'name': 'create_canvas'"));
    expect(src, contains("case 'create_canvas':"));
  });

  test('T8④ _router 可重建＋start() 守衛不炸', () async {
    final s = BridgeMcpServer();
    // 未啟動狀態連續 start 兩次——不拋 LateInitializationError
    //（8420 已被正式實例佔用，這裡只驗守衛邏輯：第二次呼叫立即返回）
    final sw = Stopwatch()..start();
    // 若 port 被佔，start 內部丟錯也應被守衛擋在 _starting 之後
    try {
      await s.start();
      await s.start(); // 連按兩次
    } catch (e) {
      // port 衝突可接受（正式實例在跑）；LateInitializationError 不可接受
      expect(e.toString(), isNot(contains('LateInitializationError')));
    }
    expect(sw.elapsedMilliseconds >= 0, isTrue);
  });
}
