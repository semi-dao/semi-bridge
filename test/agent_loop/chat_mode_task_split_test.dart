// [小葵 2026-10-01] 對話模式分流回歸測試——鎖死兩個鐵則：
// ① 聊天不被 nudge 逼成 [[TASK_DONE]] 任務報告（工程文體綁架人格）
// ② <think> 思考過程不洩漏給使用者
// ③ 本地空回應誠實報錯，不無限空轉
// 病例：2026-10-01 11:43 閒聊對話（見 conversations.json id=1790821673571）

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/agent_tool_call_parser.dart';

void main() {
  group('extractText：<think> 洩漏防護', () {
    test('完整 think 區塊被剝除', () {
      const raw = '<think>這是內部推理，使用者不該看到</think>\n\n嗨！我在聽～';
      expect(AgentToolCallParser.extractText(raw), '嗨！我在聽～');
    });

    test('未閉合 think（截斷）之後全砍', () {
      const raw = '嗨！我在聽～<think>還沒想完就被截斷';
      expect(AgentToolCallParser.extractText(raw), '嗨！我在聽～');
    });

    test('多個 think 區塊全部剝除', () {
      const raw =
          '<think>第一段思考</think>正文一<think>第二段思考</think>正文二';
      expect(AgentToolCallParser.extractText(raw), '正文一正文二');
    });

    test('沒有 think 時原樣輸出（零影響）', () {
      const raw = '普通回覆，沒有思考區塊';
      expect(AgentToolCallParser.extractText(raw), raw);
    });

    test('think + tool call 混合——兩者都清乾淨', () {
      const raw =
          '<think>我需要工具</think>我來查一下\n<<<tool_call>>>\n{"name":"web_search","args":{"query":"x"}}\n<<<tool_call_end>>>';
      final out = AgentToolCallParser.extractText(raw);
      expect(out, '我來查一下');
      expect(out.contains('<think>'), isFalse);
    });

    test('大小寫變體 <THINK> 也攔', () {
      const raw = '<THINK>internal</THINK>visible reply';
      expect(AgentToolCallParser.extractText(raw), 'visible reply');
    });
  });
}
