// chat_mode_injection_test.dart
// [聊天模式 B 線 2026-10-20 Blue 拍板] 注入行為回歸鎖——
// 雲端與本地兩條 prompt 組裝路徑都必須吃到模式紀律。
// 跑法：flutter test test/agent_loop/chat_mode_injection_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/agent_loop_prompt_builder.dart';
import 'package:bridge_app/services/agent_loop/agent_tool_registry.dart';
import 'package:bridge_app/services/chat_modes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    // 每個測試結束重置回預設自由對話，避免測試間互相污染
    await ChatModeService.instance.setMode('chat');
  });

  group('聊天模式紀律注入（雲端路徑）', () {
    test('engineering 模式：紀律 prompt 必須出現在 system prompt 尾部', () async {
      await ChatModeService.instance.setMode('engineering');
      final prompt = AgentLoopPromptBuilder.build(
        toolRegistry: makeRegistry(),
        chatModePrompt: ChatModeService.instance.currentPrompt,
      );
      expect(prompt, contains('# 聊天模式紀律'));
      expect(prompt, contains('工程開發'));
      expect(prompt, contains('動任何程式碼前先讀現況'));
      // 注入位置必須在最後一段（離 user 訊息最近＝模型必讀）
      expect(prompt.endsWith('禁止只描述要做什麼而不動手。'), isTrue);
    });

    test('自由對話（預設）：完全不注入，零回歸', () async {
      await ChatModeService.instance.setMode('chat');
      final prompt = AgentLoopPromptBuilder.build(
        toolRegistry: makeRegistry(),
        chatModePrompt: ChatModeService.instance.currentPrompt,
      );
      expect(prompt, isNot(contains('# 聊天模式紀律')));
    });

    test('六模式全掃：非 chat 模式全部注入、chat 不注入', () async {
      for (final mode in chatModes) {
        await ChatModeService.instance.setMode(mode.id);
        final prompt = AgentLoopPromptBuilder.build(
          toolRegistry: makeRegistry(),
          chatModePrompt: ChatModeService.instance.currentPrompt,
        );
        if (mode.id == 'chat') {
          expect(prompt, isNot(contains('# 聊天模式紀律')),
              reason: '自由對話不應注入');
        } else {
          expect(prompt, contains('# 聊天模式紀律'),
              reason: '${mode.name} 應注入');
          expect(prompt, contains(mode.name), reason: '${mode.name} 名稱應在');
        }
      }
    });
  });

  group('聊天模式紀律注入（本地路徑）', () {
    test('本地輕量路徑同樣吃模式紀律（時好時壞病防護）', () async {
      await ChatModeService.instance.setMode('engineering');
      final prompt = AgentLoopPromptBuilder.build(
        toolRegistry: makeRegistry(),
        isLocalProvider: true,
        chatModePrompt: ChatModeService.instance.currentPrompt,
      );
      expect(prompt, contains('# 聊天模式紀律'));
      expect(prompt, contains('工程開發'));
    });

    test('本地路徑 + 自由對話：不注入，零回歸', () async {
      await ChatModeService.instance.setMode('chat');
      final prompt = AgentLoopPromptBuilder.build(
        toolRegistry: makeRegistry(),
        isLocalProvider: true,
        chatModePrompt: ChatModeService.instance.currentPrompt,
      );
      expect(prompt, isNot(contains('# 聊天模式紀律')));
    });
  });
}

/// 工具註冊表——用真 AgentToolRegistry（e2e 測試同款建法）
AgentToolRegistry makeRegistry() => AgentToolRegistry();
