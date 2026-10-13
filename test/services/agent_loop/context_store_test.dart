// Spike 002 落地測試——CLM 形狀 context 管理（ContextStore + 截斷封存）
//
// 鎖死行為：
// 1. 截斷後被壓縮訊息全文仍在 store（永不銷毀）
// 2. 摘要帶指針〔已封存 #N〕留在 context
// 3. context_recall 工具：id 讀回全文、query 搜尋、失敗誠實
// 4. store per-run 重建（第二次 run 拿不到第一次的封存）
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/context_store.dart';

void main() {
  group('ContextStore', () {
    test('archive 回傳帶指針摘要，全文保留在 store', () {
      final s = ContextStore();
      const longToolResult =
          '工具 web_search 的執行結果：\nK00122 = fathom lattice orbit cobble harbor lattice harbor indigo '
          'thistle ember marble fathom lantern zebra lantern falcon zebra russet lattice '
          'auburn willow nimbus zebra onyx #8104400c 加了很多很多字';
      final p = s.archive('user', longToolResult);
      expect(p, startsWith('〔已封存 #1〕'));
      expect(p, contains('web_search')); // 摘要含工具名
      expect(s.entryCount, 1);
      expect(s.charsStored, longToolResult.length);
      expect(s.byId(1)!.content, longToolResult); // 全文未損
    });

    test('截斷形狀：中間訊息進 store、context 留指針、首尾保留', () {
      final s = ContextStore();
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': '你是橋樑 App 的 Agent。'},
        {'role': 'user', 'content': '最初任務：維護鍵值庫'},
        for (var i = 0; i < 12; i++)
          {
            'role': 'user',
            'content': '工具 kv_exec 的執行結果：\nSET K00$i = value$i #hash$i'
                ' padding padding padding padding padding padding padding padding',
          },
        {'role': 'user', 'content': '請回答 K003 的值'},
      ];
      // 套用 agent_loop 同形截斷
      final middle = messages.sublist(2, messages.length - 8);
      final parts = <String>[];
      for (final m in middle) {
        parts.add(s.archive('${m['role']}', '${m['content']}'));
      }
      final kept = [messages[0], messages[1],
        {'role': 'user', 'content': '〔歷史摘要〕\n${parts.join('\n')}'},
        ...messages.sublist(messages.length - 8)];
      // 首尾保留
      expect(kept.first['content'], '你是橋樑 App 的 Agent。');
      expect(kept[1]['content'], '最初任務：維護鍵值庫');
      expect(kept.last['content'], '請回答 K003 的值');
      // 指針在 context
      expect('${kept[2]['content']}', contains('〔已封存 #1〕'));
      // 全文在 store——K003 的值讀得回來
      expect(s.search('K003'), isNotEmpty);
      expect(s.search('K003').first.content, contains('value3'));
    });

    test('search 關鍵詞命中與排序', () {
      final s = ContextStore();
      s.archive('user', 'alpha beta gamma');
      s.archive('user', 'beta beta delta');
      s.archive('user', 'epsilon zeta');
      final hits = s.search('beta');
      expect(hits.length, 2);
      expect(hits.first.content, 'beta beta delta'); // 命中 2 次排前
      expect(s.search('zzz'), isEmpty);
    });

    test('byId 讀回、不存在誠實失敗', () {
      final s = ContextStore();
      s.archive('assistant', 'hello world');
      expect(s.byId(1)!.content, 'hello world');
      expect(s.byId(99), isNull);
    });

    test('archive 冪等：同 role+content 跨輪重送回同指針', () {
      final s = ContextStore();
      final p1 = s.archive('user', '重要路徑 /x/y/z.dart');
      final p2 = s.archive('user', '重要路徑 /x/y/z.dart');
      expect(p1, p2);
      expect(s.entryCount, 1); // 不重複入庫
      expect(s.charsStored, '重要路徑 /x/y/z.dart'.length);
    });

    test('compactHistory：>10 輪壓縮、全文進 store、保留近 6 輪＋指針塊', () {
      final session = ContextStore();
      final history = <Map<String, String>>[
        for (var i = 0; i < 14; i++)
          {'role': i.isEven ? 'user' : 'assistant', 'content': '第 $i 輪的內容，關鍵值 VALUE_$i'},
      ];
      final out = ContextStore.compactHistory(session, history);
      expect(out.length, 7); // 1 指針塊 + 6 保留輪
      expect(out.first['content'], contains('context_recall'));
      expect(out.first['content'], contains('〔已封存 #1〕'));
      // 最近 6 輪原樣保留
      expect(out.last['content'], contains('VALUE_13'));
      expect(out[1]['content'], contains('VALUE_8'));
      // 舊輪全文在 store 讀得回
      expect(session.search('VALUE_2'), isNotEmpty);
      // 冪等：再壓一次（模擬下一輪重送）不膨脹
      final out2 = ContextStore.compactHistory(session, history);
      expect(out2.length, 7);
      expect(session.entryCount, 8); // 14-6=8 筆，不重複入庫
    });

    test('compactHistory：≤10 輪不動', () {
      final session = ContextStore();
      final history = <Map<String, String>>[
        for (var i = 0; i < 9; i++) {'role': 'user', 'content': 'm$i'},
      ];
      final out = ContextStore.compactHistory(session, history);
      expect(out, same(history));
      expect(session.entryCount, 0);
    });

    test('linkSession：context_recall 跨層搜尋＋byIdAny 定址', () {
      final runStore = ContextStore();
      final sessionStore = ContextStore();
      sessionStore.archive('user', '跨輪的舊路徑 /Users/x.dart');
      runStore.archive('user', '本輪工具結果 canvas_look');
      runStore.linkSession(sessionStore);

      // searchAll 兩層都搜得到
      expect(runStore.searchAll('/Users/x.dart'), isNotEmpty);
      expect(runStore.searchAll('canvas_look'), isNotEmpty);
      // byIdAny：session 條目 #1 + offset = 10001
      expect(runStore.byIdAny(1)!.content, contains('canvas_look'));
      expect(runStore.byIdAny(10001)!.content, contains('/Users/x.dart'));
      expect(runStore.byIdAny(99999), isNull);
    });

    test('跨層 context_recall（工具層）', () async {
      final runStore = ContextStore();
      final sessionStore = ContextStore();
      sessionStore.archive('user', '三輪前使用者說過：把報告存到 /tmp/report.md');
      runStore.linkSession(sessionStore);
      final tool = ContextRecallTool(runStore);
      final r = await tool.execute({'query': 'report.md'});
      expect(r.success, isTrue);
      expect(r.content, contains('/tmp/report.md'));
    });
  });

  group('ContextRecallTool', () {
    test('id 讀回全文', () async {
      final s = ContextStore();
      s.archive('user', 'SECRET_VALUE_8104400c with long tail ' * 20);
      final tool = ContextRecallTool(s);
      final r = await tool.execute({'id': 1});
      expect(r.success, isTrue);
      expect(r.content, contains('SECRET_VALUE_8104400c'));
      expect(r.content, contains('#1'));
    });

    test('query 搜尋命中', () async {
      final s = ContextStore();
      s.archive('user', '路徑：/Users/alice/Developer/bridge_app/lib/x.dart');
      s.archive('user', '別的訊息');
      final tool = ContextRecallTool(s);
      final r = await tool.execute({'query': 'bridge_app'});
      expect(r.success, isTrue);
      expect(r.content, contains('x.dart'));
    });

    test('無參數誠實失敗（寧紅字不假成功）', () async {
      final tool = ContextRecallTool(ContextStore());
      final r = await tool.execute({});
      expect(r.success, isFalse);
      expect(r.content, contains('context_recall')); // 失敗前綴帶工具名
    });

    test('id 不存在誠實失敗', () async {
      final tool = ContextRecallTool(ContextStore());
      final r = await tool.execute({'id': 5});
      expect(r.success, isFalse);
      expect(r.content, contains('找不到'));
    });

    test('回傳上限截斷並提示改用 query', () async {
      final s = ContextStore();
      s.archive('user', 'A' * 20000);
      final tool = ContextRecallTool(s);
      final r = await tool.execute({'id': 1, 'max_chars': 1000});
      expect(r.success, isTrue);
      expect(r.content.length, lessThan(1500));
      expect(r.content, contains('改用 query'));
    });

    test('工具描述與參數規格完整（compass_toolseek 可搜到）', () {
      final tool = ContextRecallTool(ContextStore());
      expect(tool.name, 'context_recall');
      expect(tool.paramSpecs.length, 3);
      expect(tool.toPromptDescription(), contains('context_recall'));
      expect(tool.toFullDescription(), contains('id'));
    });
  });
}
