/// Agent Loop — Tool Call 協定核心型別
///
/// S21a: 定義 LLM 輸出的 tool call 格式、解析器、工具介面。
/// 設計決策（使用者 2026-07-08 拍板）：
/// - prompt-based JSON（不走 OpenAI function calling）
/// - 格式與 brain pipeline L3 一致：分隔符 `<<<tool_call>>>...<<<tool_call_end>>>`
/// - 預設 15 輪，硬上限 30 輪
/// - 到上限時 graceful termination（強制最後一次 LLM 回覆，不再呼叫工具）

/// 單一工具呼叫（從 LLM 回覆中解析出來）
class AgentToolCall {
  final String name;
  final Map<String, dynamic> args;

  const AgentToolCall({required this.name, required this.args});

  @override
  String toString() => 'AgentToolCall($name, $args)';
}

/// 工具執行結果（餵回給 LLM 當下一輪的 context）
class AgentToolResult {
  final bool success;
  final String content; // 餵給 LLM 的文字摘要
  final String? mediaUrl; // 媒體 URL（圖片等），不餵給 LLM 但 UI 可用
  final Map<String, dynamic>? metadata;

  const AgentToolResult({
    required this.success,
    required this.content,
    this.mediaUrl,
    this.metadata,
  });

  factory AgentToolResult.success(String content, {String? mediaUrl, Map<String, dynamic>? metadata}) {
    return AgentToolResult(success: true, content: content, mediaUrl: mediaUrl, metadata: metadata);
  }

  /// [小葵 2026-10-12 M15] 失敗前綴帶工具名——LLM 與使用者一看就知道
  /// 哪個工具壞了。`toolName` 選填：未帶時維持舊文案（向下相容，
  /// 呼叫端可漸進補上）。
  factory AgentToolResult.failure(String error, {String? toolName}) {
    final prefix = toolName != null && toolName.isNotEmpty
        ? '工具執行失敗（$toolName）：'
        : '工具執行失敗：';
    return AgentToolResult(success: false, content: '$prefix$error');
  }
}

/// 工具參數規格（注入 system prompt 讓 LLM 知道怎麼呼叫）
class AgentToolParamSpec {
  final String name;
  final String description;
  final bool required;
  final String? defaultValue;

  const AgentToolParamSpec({
    required this.name,
    required this.description,
    this.required = false,
    this.defaultValue,
  });
}

/// 工具介面——每個工具實作此介面
abstract class AgentTool {
  /// 工具名稱（LLM 呼叫時用的 identifier，snake_case）
  String get name;

  /// 簡短描述（注入 system prompt）
  String get description;

  /// 參數規格列表
  List<AgentToolParamSpec> get paramSpecs;

  /// 執行工具
  Future<AgentToolResult> execute(Map<String, dynamic> args);

  /// 產生給 system prompt 的工具描述文字
  ///
  /// [教練 Agent 2026-08-17 Token 樹精簡] 分層說明書——prompt 內只放
  /// 一句話簡介＋參數名（必填者標 *），完整參數說明由 tool_help
  /// 工具隨需查詢。LLM 依然知道每個工具的存在與用途（能力不減），
  /// 細節不佔常駐 context（速度提升）。
  String toPromptDescription() {
    final params = paramSpecs.map((p) {
      final star = p.required ? '*' : '';
      final def = p.defaultValue != null ? '=${p.defaultValue}' : '';
      return '${p.name}$star$def';
    }).join(', ');
    final paramLine = params.isEmpty ? '' : '（$params）';
    return '- $name：$description$paramLine';
  }

  /// [教練 Agent 2026-08-17 Token 樹精簡] 完整版說明（tool_help 用）
  String toFullDescription() {
    final params = paramSpecs.map((p) {
      final req = p.required ? '（必填）' : '（選填）';
      final def = p.defaultValue != null ? '，預設：${p.defaultValue}' : '';
      return '  - ${p.name}$req：${p.description}$def';
    }).join('\n');
    return '### $name\n$description\n參數：\n$params';
  }
}

/// Agent Loop 的一輪紀錄
class AgentLoopTurn {
  final int turnIndex;
  final AgentToolCall? toolCall; // null = 最終回覆輪（無工具呼叫）
  final AgentToolResult? toolResult; // null = 最終回覆輪
  final String llmRawOutput; // LLM 原始回覆
  final String? finalReply; // 最終回覆（僅最後一輪有值）

  const AgentLoopTurn({
    required this.turnIndex,
    this.toolCall,
    this.toolResult,
    required this.llmRawOutput,
    this.finalReply,
  });

  bool get isFinalTurn => toolCall == null;
}
