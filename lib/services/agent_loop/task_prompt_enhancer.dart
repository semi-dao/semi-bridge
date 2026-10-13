// task_prompt_enhancer.dart
// 自然語言 → 精準 prompt 轉換層
//
// 問題：一般使用者不會寫結構化指令（「依序導航6頁，每頁截圖後做視覺分析」）
// 他們只會說自然語言（「幫我看看這個App好不好看」「首頁感覺很空怎麼辦」）
//
// 解法：用 LLM 把自然語言轉成原生 Agent能順暢執行的精準 prompt
// 轉換器知道原生 Agent的工具清單、能力邊界、執行原則
//
// [2026-07-19 使用者拍板] 新增「意圖不明時反問」機制：
// 當使用者語意不明確時，不硬轉，而是反問使用者問題，幫助釐清意圖跟共識
// 這樣才能確保轉譯出來的 prompt 是使用者真正想要的
//
// 2026-07-18 使用者提出：「未來在一般使用者使用真實場景的時候，
// 這就會是使用者的自然語言，我們App裡面必須要有能力內建將這個
// 自然語言轉成原生 Agent可以順暢執行的精準prompt」

import 'package:flutter/foundation.dart';
import '../api_service.dart';
import 'agent_tool_registry.dart';

/// 增強結果——可能是精準 prompt，也可能是反問問題
class EnhanceResult {
  /// 轉譯後的精準 prompt（如果意圖明確）
  final String? prompt;

  /// 反問問題（如果意圖不明確）
  final List<String>? clarificationQuestions;

  /// 判斷原因（為什麼需要反問，或為什麼直接轉譯）
  final String reason;

  bool get needsClarification => clarificationQuestions != null;

  const EnhanceResult({
    this.prompt,
    this.clarificationQuestions,
    required this.reason,
  });

  factory EnhanceResult.prompt(String p, String reason) =>
      EnhanceResult(prompt: p, reason: reason);

  factory EnhanceResult.clarification(List<String> questions, String reason) =>
      EnhanceResult(clarificationQuestions: questions, reason: reason);
}

/// 自然語言 prompt 增強器
///
/// 判斷使用者的輸入是否需要增強：
/// - 如果已經是結構化指令（含明確步驟、工具名稱）→ 不增強
/// - 如果是自然語言 → 用 LLM 轉成精準 prompt
/// - 如果意圖不明確 → 反問使用者問題，取得共識後再轉譯
class TaskPromptEnhancer {
  /// 判斷是否需要增強
  ///
  /// 以下情況不需要增強（已經是精準 prompt）：
  /// - 包含工具名稱（screen_capture, ui_get_state, ui_navigate, ui_tap...）
  /// - 包含明確步驟編號（1. 2. 3.）+ 具體文件路徑
  /// - prompt 長度 > 500 字元（通常是詳細指令）
  static bool needsEnhancement(String userInput) {
    // 已經很長 = 可能是結構化指令
    if (userInput.length > 500) return false;

    final lower = userInput.toLowerCase();

    // 包含工具名稱 = 已經是精準 prompt
    const toolNames = [
      'screen_capture', 'ui_get_state', 'ui_navigate', 'ui_tap',
      'read_source_file', 'patch_source_file', 'run_terminal',
      'read_app_log', 'restart_app', 'web_search', 'image_recognition',
      'generate_image', 'create_document',
    ];
    for (final name in toolNames) {
      if (lower.contains(name)) return false;
    }

    // 包含結構化指示詞 = 已經是精準 prompt
    const structuralHints = [
      '執行以下步驟', '依序', '步驟如下', '請依序',
      'max_steps', 'force_tool_use',
    ];
    for (final hint in structuralHints) {
      if (userInput.contains(hint)) return false;
    }

    // 短語句 + 自然語言 = 需要增強
    return true;
  }

  /// 把自然語言轉成精準 prompt，或反問使用者問題
  ///
  /// [2026-07-19] 新增意圖判斷：
  /// - 意圖明確 → 轉成精準 prompt
  /// - 意圖不明確 → 回傳反問問題，幫助使用者釐清
  ///
  /// [previousContext] — 如果是反問後的使用者回答，這裡帶上之前的對話上下文
  static Future<EnhanceResult> enhanceWithContext(
    String userInput,
    AgentToolRegistry? toolRegistry, {
    String? previousContext,
  }) async {
    if (!needsEnhancement(userInput)) {
      return EnhanceResult.prompt(userInput, '已是精準 prompt，不需增強');
    }

    final toolList = toolRegistry?.toPromptSection() ?? _defaultToolList;

    final systemPrompt = '''你是橋樑 App 的任務指令轉換器。

使用者的自然語言指令需要轉成 App 原生 Agent 可以順暢執行的精準 prompt。

## 原生 Agent 的能力
原生 Agent 擁有以下工具：
$toolList

## 原生 Agent 的特點
- 它是 App 的原生 Agent，比任何人都了解這個 App
- 它可以截圖看畫面（screen_capture），用視覺分析
- 它可以點按鈕、切換頁面（ui_get_state, ui_navigate, ui_tap）
- 它可以讀 App log、讀原始碼、修改程式碼
- 它的回覆會直接給使用者看

## 意圖判斷規則（最重要）
先判斷使用者的意圖是否明確：
- **意圖明確**：使用者說了要做什麼（看/改/查/修）、對哪個對象（哪個頁面/哪個功能）、大概的方向
- **意圖不明確**：使用者只說了模糊感受（「感覺不對」「好像有問題」「能不能弄一下」），沒有具體對象或動作

## 判斷後的行動

### 如果意圖明確：
直接轉成精準 prompt。輸出格式：
```
PROMPT:
[轉譯後的精準 prompt，包含任務目標、執行步驟、完成標準]
```

### 如果意圖不明確：
不要硬轉——反問使用者問題。問題要：
1. 具體（不要問「你想要什麼」，要問「你是想改善首頁的視覺，還是想修某個功能？」）
2. 給 2-3 個選項讓使用者選（降低認知負擔）
3. 用使用者聽得懂的語言（不要提工具名稱、技術術語）

輸出格式：
```
CLARIFY:
1. [第一個問題]
2. [第二個問題（可選）]
```

## 轉換規則（意圖明確時）
1. 如果涉及視覺/美感，一定要用 screen_capture 截圖 + 視覺分析
2. 如果涉及功能測試，用 ui_get_state → ui_tap → ui_get_state 驗證
3. 如果涉及程式修改，用 read_source_file → patch_source_file → dart analyze
4. 保持步驟精簡，不要過度拆分
5. 用中文輸出
6. 不要加 JSON 格式或 <<<tool_call>>> 標記——只輸出純文字的任務指令

不要加任何前言或解釋，直接輸出。''';

    final contextPart = previousContext != null
        ? '之前的對話上下文：\n$previousContext\n\n'
        : '';
    final userPrompt = '${contextPart}使用者說：「$userInput」';

    try {
      final result = await ApiService.complete(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      );
      final trimmed = result.trim();
      if (trimmed.isEmpty) {
        return EnhanceResult.prompt(userInput, 'LLM 回空，用原文');
      }

      // 解析 LLM 輸出——判斷是 PROMPT 還是 CLARIFY
      if (trimmed.startsWith('CLARIFY:')) {
        final questionsStr = trimmed.substring('CLARIFY:'.length).trim();
        final questions = questionsStr
            .split(RegExp(r'\n\d+\.\s*'))
            .where((q) => q.trim().isNotEmpty)
            .map((q) => q.trim())
            .toList();
        if (questions.isNotEmpty) {
          debugPrint('[PromptEnhancer] 意圖不明確，反問 ${questions.length} 個問題');
          return EnhanceResult.clarification(questions, '意圖不明確，需要反問');
        }
      }

      // PROMPT: 開頭或沒有標記 = 直接轉譯
      String prompt = trimmed;
      if (prompt.startsWith('PROMPT:')) {
        prompt = prompt.substring('PROMPT:'.length).trim();
      }

      // [Blue 令 2026-10-05] 反重複工鐵律——每次增強都附上，讓 Agent Loop 的
      // 每一輪都記得：發現重複工/無用工當場排除。極簡三行，不佔 context。
      prompt =
          '$prompt\n\n〔反重複工鐵律〕發現重複工/無用工當場排除。判準：跑兩次≠跑一次就要修；輸入沒變就跳過；輪詢能改事件就改；離線預處理勝過線上重算。';

      debugPrint('[PromptEnhancer] 增強成功：${userInput.length} → ${prompt.length} 字元');
      return EnhanceResult.prompt(prompt, '意圖明確，直接轉譯');
    } catch (e) {
      debugPrint('[PromptEnhancer] 增強失敗（fallback 原文）：$e');
      return EnhanceResult.prompt(
        '使用者指令：$userInput\n\n請先用 ui_get_state 了解當前狀態，再根據使用者意圖執行。',
        'LLM 失敗，fallback 原文',
      );
    }
  }

  /// 舊 API 向下相容——直接回傳 prompt 字串
  static Future<String> enhance(String userInput, AgentToolRegistry? toolRegistry) async {
    final result = await enhanceWithContext(userInput, toolRegistry);
    return result.prompt ?? userInput;
  }

  static const _defaultToolList = '''
- screen_capture：截取 App 畫面，用視覺分析
- ui_get_state：查詢當前頁面和可點擊元素
- ui_navigate：導航到指定頁面
- ui_tap：點擊指定元素
- read_source_file：讀取專案原始碼
- patch_source_file：修改原始碼
- run_terminal：執行白名單指令
- read_app_log：讀取 App log
- web_search：搜尋網路
- generate_image：生成圖片
''';
}
