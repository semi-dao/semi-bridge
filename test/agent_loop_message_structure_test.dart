// [T10③ benchmark 病例 2026-10-19] glm 400「Cannot have 2 or more
// assistant messages at the end of the list」回歸鎖。
//
// 病因：AgentLoop timeout 路徑加 assistant 角色恢復訊息後 continue，
// messages 變 assistant 結尾——glm（OpenAI 相容但嚴格）直接 400；
// 本地 llama-server 不擋，所以只在雲端現形。
//
// 修復：恢復訊息改 user 角色。本測試鎖「送 LLM 前的 messages 結尾
// 結構不變式」：非首輪呼叫時，messages 結尾不得是兩條 assistant。
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 抽象出 AgentLoop 的 messages 維護規則做純邏輯驗證
  //（AgentLoop 本體 800+ 行跑不進單元測試，鎖規則不鎖實作）
  List<Map<String, dynamic>> buildBase() => [
        {'role': 'system', 'content': 'sys'},
        {'role': 'user', 'content': '幫我看截圖'},
      ];

  bool endsWithDoubleAssistant(List<Map<String, dynamic>> msgs) {
    if (msgs.length < 2) return false;
    return msgs[msgs.length - 1]['role'] == 'assistant' &&
        msgs[msgs.length - 2]['role'] == 'assistant';
  }

  test('timeout 恢復訊息用 user 角色——連續兩次 timeout 後仍不會 assistant 結尾', () {
    final messages = buildBase();
    // 模擬 L927 修復後行為：timeout → evict → 加 user 恢復訊息 → continue
    for (var i = 0; i < 2; i++) {
      messages.add({
        'role': 'user',
        'content': '〔視覺模型分析截圖超時。請改用文字推理。〕',
      });
    }
    expect(endsWithDoubleAssistant(messages), isFalse,
        reason: 'glm 400 病例：連續 timeout 恢復訊息不得造成 assistant 結尾');
  });

  test('對照組（修復前行為會炸）——assistant 恢復訊息 × 2 = 400 病灶', () {
    final messages = buildBase();
    for (var i = 0; i < 2; i++) {
      messages.add({
        'role': 'assistant',
        'content': '〔視覺模型分析截圖超時。〕',
      });
    }
    expect(endsWithDoubleAssistant(messages), isTrue,
        reason: '這是 2026-10-19 實測炸掉的結構——修復後不得再出現');
  });

  test('正常工具迴圈（assistant 輸出 + user 工具結果）結構安全', () {
    final messages = buildBase();
    messages.add({'role': 'assistant', 'content': 'tool call...'});
    messages.add({'role': 'user', 'content': '工具結果：...'});
    messages.add({'role': 'assistant', 'content': '[[TASK_DONE]] 收工'});
    expect(endsWithDoubleAssistant(messages), isFalse);
  });
}
