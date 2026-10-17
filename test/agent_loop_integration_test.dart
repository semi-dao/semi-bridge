/// Agent Loop 整合測試 — Mock LLM client 下的控制流
///
/// [T10④ 2026-10-17] 從骨架變實作——不需要 UI、不需要 API key：
/// - mock LLM client 控制回應（正常/超時/錯誤）
/// - 驗證控制流：直通道、連續 timeout 真結束、hitTurnLimit
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/services/agent_loop/agent_loop.dart';
import 'package:bridge_app/services/agent_loop/agent_tool_registry.dart';

/// 可編劇的 mock LLM client——按序吐回應
class ScriptedLLMClient implements AgentLoopLLMClient {
  final List<Object> script; // String=正常回應 / TimeoutException=超時 / Exception=錯誤
  int callIndex = 0;
  ScriptedLLMClient(this.script);

  @override
  Future<String> complete(List<Map<String, dynamic>> messages) async {
    final i = callIndex++;
    if (i >= script.length) return '（script 用盡——直接結束）';
    final item = script[i];
    if (item is TimeoutException) throw item;
    if (item is Exception) throw item;
    return item as String;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({}); // run() 內工具讀 prefs——mock 掉
  final registry = AgentToolRegistry();

  test('T10④-1 連續 3 次 LLM timeout → 真 return（非無限重試）', () async {
    final loop = AgentLoop(
      toolRegistry: registry,
      // 前 2 槽可能被 K1 escalate→E4B 仲裁消耗（fail-open 會吞掉）——
      // 給足 timeout，連續 3 次累積必觸發真 return
      llmClient: ScriptedLLMClient(
          List.generate(8, (i) => TimeoutException('t$i'))),
    );
    final result = await loop.run(
      systemPrompt: '你是測試助手。',
      userMessage: '幫我查個東西',
      maxTurns: 100000, // Hermes 模式——不靠輪數上限
    );
    // 關鍵：不是 100000 輪燒完，而是 3 次 timeout 就回來
    expect(result.reply, contains('連續三次'));
    expect(result.hitTurnLimit, isFalse);
    expect(result.cancelled, isFalse);
  });

  test('T10④-2 timeout 後成功回應 → 計數歸零（1 timeout + 1 ok 不觸發放棄）', () async {
    final loop = AgentLoop(
      toolRegistry: registry,
      llmClient: ScriptedLLMClient([
        TimeoutException('t1'),
        '好的，我直接告訴你：答案是 42。',
      ]),
    );
    final result = await loop.run(
      systemPrompt: '你是測試助手。',
      userMessage: '生命的意義是什麼？',
    );
    expect(result.reply, contains('42'));
    expect(result.hitTurnLimit, isFalse);
  });

  test('T10④-3 isCancelled → 立即結束（Blue 保留取消權）', () async {
    final loop = AgentLoop(
      toolRegistry: registry,
      llmClient: ScriptedLLMClient(['先想想...']),
    );
    final result = await loop.run(
      systemPrompt: '你是測試助手。',
      userMessage: '任務',
      isCancelled: () => true, // 一進來就取消
    );
    expect(result.cancelled, isTrue);
  });
}
