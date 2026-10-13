/// Agent Loop — Tool Call 解析器
///
/// 從 LLM 回覆中提取 tool call JSON。
/// 格式：`<<<tool_call>>>{...json...}<<<tool_call_end>>>`
/// 與 brain pipeline L3 prompt-based JSON 模式一致。
///
/// 安全設計：
/// - 分隔符轉義防注入（使用者訊息裡的分隔符會被替換）
/// - JSON 解析用 safeJsonParse（try-catch + strict=false）
/// - 沒有 tool call 的回覆 = 自然結束（LLM 自主決定完成）

import 'dart:convert';
import 'agent_tool.dart';

class AgentToolCallParser {
  static const String _startMarker = '<<<tool_call>>>';
  static const String _endMarker = '<<<tool_call_end>>>';

  // 寬鬆正則：容忍 LLM 輸出 <<<tool_call>> (2個>) 或 <<<tool_call>>> (3個>)
  // 也容忍 tool_call 和 > 之間有空白
  static final RegExp _startPattern = RegExp(r'<<<tool_call\s*>>+');
  static final RegExp _endPattern = RegExp(r'<<<tool_call_end\s*>>+');

  /// 從 LLM 回覆中解析出所有 tool call
  /// 如果沒有 tool call = 回傳空 list（代表 LLM 自主結束）
  static List<AgentToolCall> parse(String llmOutput) {
    final calls = <AgentToolCall>[];

    int searchStart = 0;
    while (true) {
      final startMatch = _startPattern.firstMatch(llmOutput.substring(searchStart));
      if (startMatch == null) break;

      final jsonStart = searchStart + startMatch.end;
      final endMatch = _endPattern.firstMatch(llmOutput.substring(jsonStart));
      if (endMatch == null) break;

      final jsonStr = llmOutput.substring(jsonStart, jsonStart + endMatch.start).trim();
      final call = _parseSingle(jsonStr);
      if (call != null) {
        calls.add(call);
      }

      searchStart = jsonStart + endMatch.end;
    }

    return calls;
  }

  /// 判斷 LLM 回覆是否包含 tool call
  static bool hasToolCall(String llmOutput) {
    return _startPattern.hasMatch(llmOutput);
  }

  /// [教練 Agent 2026-08-16 使用者 抓包] 判斷是否有「被截斷的 tool call」——
  /// 有 start marker 但沒有配對的 end marker。
  /// 這種情況代表串流中途斷掉（截斷、超時、斷線），
  /// 不是 LLM 自主結束——AgentLoop 必須重試而不是退出。
  static bool hasTruncatedToolCall(String llmOutput) {
    var searchStart = 0;
    while (true) {
      final startMatch =
          _startPattern.firstMatch(llmOutput.substring(searchStart));
      if (startMatch == null) return false;
      final jsonStart = searchStart + startMatch.end;
      final rest = llmOutput.substring(jsonStart);
      final endMatch = _endPattern.firstMatch(rest);
      if (endMatch == null) return true; // 有頭無尾 = 截斷
      searchStart = jsonStart + endMatch.end;
    }
  }

  /// [教練 Agent 2026-08-16] 判斷回覆是否以「懸空期待」結尾——
  /// 例如「重跑一次：」「接下來執行」等，後面應該要有 tool call 卻沒有。
  /// 這是 LLM 打算繼續但串流被斷的另一種病徵。
  static bool endsWithDanglingColon(String llmOutput) {
    final text = extractText(llmOutput).trim();
    if (text.isEmpty) return false;
    return text.endsWith(':') || text.endsWith('：');
  }

  /// [小葵 2026-09-15 Blue 抓包] 判斷回覆是否宣告了行動意圖卻沒行動——
  /// 「我先看現狀再動手。」「接下來我來檢查。」「讓我先查一下。」
  /// 這些句子的語意是「本輪結束後還有工具動作」，若無 tool call
  /// = 說了不做，loop 不應退出。
  static bool endsWithStatedIntent(String llmOutput) {
    final text = extractText(llmOutput).trim();
    if (text.isEmpty) return false;
    // 取結尾最後兩句（最後 60 字元——「下一步：找…」病例顯示 40 會把意圖詞切掉）
    final tail = text.length > 60 ? text.substring(text.length - 60) : text;
    const intentMarkers = [
      '再動手', '先看', '先查', '先檢查', '先確認', '先讀', '先掃',
      '再執行', '再繼續', '接下來我', '馬上來', '這就來', '我來查',
      '我來看', '我來檢查', '我來確認', '我去', '開始動手', '動手做',
      // [小葵 2026-09-15 二輪抓包] 「下一步：找 onGetState 的注入處。」停手——
      // 「找/搜/翻/定位」也是行動動詞。詞表法永遠追不完（capability advisor 教訓），
      // 正解是結構性判斷（任務未完成+無工具=質詢），詞表先補常見漏網。
      '下一步', '接著找', '接著查', '來找', '來搜', '去搜', '去找', '去讀', '去查',
      '搜一下', '查一下', '看一下', '讀一下', '找出来', '找出來', '定位',
    ];
    return intentMarkers.any((m) => tail.contains(m));
  }

  /// 提取 tool call 之外的文字（LLM 可能同時輸出文字 + tool call）
  /// [小葵 2026-10-01 Blue 抓包] `<think>` 思考過程不得洩漏給使用者——
  /// 病例：閒聊對話 assistant 訊息開頭整段 `<think>` 直接顯示。
  /// 完整區塊移除；未閉合（截斷）則 `<think>` 之後全砍（後面都是思考）。
  static String extractText(String llmOutput) {
    // 移除所有 tool call 區塊，保留其餘文字
    String result = _stripThink(llmOutput);
    while (true) {
      final startMatch = _startPattern.firstMatch(result);
      if (startMatch == null) break;
      final afterStart = startMatch.end;
      final endMatch = _endPattern.firstMatch(result.substring(afterStart));
      if (endMatch == null) {
        // 有 start 但沒有 end → 移除 start marker 和之後所有內容
        result = result.substring(0, startMatch.start);
        break;
      }
      result = result.substring(0, startMatch.start) +
          result.substring(afterStart + endMatch.end);
    }
    return result.trim();
  }

  /// [小葵 2026-10-01] 剝除思考區塊——`<think>`…`</think>` 是模型的推理過程，
  /// 不是給使用者的回覆。未閉合視為截斷，從 `<think>` 起全部丟棄。
  static final RegExp _thinkBlock =
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false);
  static final RegExp _thinkOpen = RegExp(r'<think>', caseSensitive: false);

  static String _stripThink(String s) {
    var out = s.replaceAll(_thinkBlock, '');
    final open = _thinkOpen.firstMatch(out);
    if (open != null) out = out.substring(0, open.start);
    return out;
  }

  /// 轉義使用者訊息中的分隔符（防注入）
  /// 在把使用者訊息組進 prompt 前呼叫
  static String sanitize(String userMessage) {
    return userMessage
        .replaceAll(_startMarker, '[已過濾]')
        .replaceAll(_endMarker, '[已過濾]');
  }

  static AgentToolCall? _parseSingle(String jsonStr) {
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final name = json['name']?.toString() ?? '';
      if (name.isEmpty) return null;
      final args = (json['args'] as Map<String, dynamic>?) ?? {};
      return AgentToolCall(name: name, args: args);
    } catch (_) {
      // JSON 解析失敗 = LLM 格式錯誤，跳過這個 call
      // AgentLoop 引擎會看到空 list = 當作自然結束
      return null;
    }
  }
}

/// 安全 JSON 解析（與 brain pipeline safeJsonParse 一致）
Map<String, dynamic>? safeJsonParse(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  try {
    final result = jsonDecode(text);
    if (result is Map<String, dynamic>) return result;
    return null;
  } catch (_) {
    // 嘗試提取 JSON 片段（LLM 可能包在 markdown code fence 裡）
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (jsonMatch != null) {
      try {
        final result = jsonDecode(jsonMatch.group(0)!);
        if (result is Map<String, dynamic>) return result;
      } catch (_) {}
    }
    return null;
  }
}
