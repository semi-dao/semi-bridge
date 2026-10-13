/// delegate_subagent 工具——派子代理用不同外部 LLM 執行任務
///
/// 向量工作流維度 1 的核心：多模型協同。
/// App Agent（主大腦）能派子代理用指定的外部 LLM 執行任務，
/// 收集所有子代理結果後綜合回覆。
///
/// 使用情境：
/// - 用 GPT-5.5 做視覺分析
/// - 用 Kimi K2.6 做文字創作
/// - 用 GLM-5.2 做推理
/// - App Agent 收集所有子代理結果，綜合回覆
///
/// 技術迴路：
/// 1. 解析 provider（不指定則用當前主大腦的 provider）
/// 2. 取得該 provider 的 base URL + token + 預設模型
/// 3. 組 system prompt + user message
/// 4. 呼叫 OpenAI-compatible chat completions API（streaming）
/// 5. 回傳子代理的結果
///
/// 錯誤處理：
/// - provider 不可用（無 token）→ 回傳錯誤提示
/// - timeout 60 秒
/// - 回傳空內容 → 報錯

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../api_service.dart';
import '../../storage_service.dart';
import '../agent_provider_profile.dart';
import '../agent_profile_store.dart';
import '../agent_tool.dart';
import '../../sovereignty/data_path_gate.dart';
import '../../sovereignty/data_path_interceptor.dart';

/// [教練 Agent 2026-08-07] 使用者鎖定的 provider——指定模式時不允許 delegate 給其他 provider
/// 從 ChatController 透過靜態變數注入，整個 Agent Loop 生命週期內有效。
String? _kLockedProvider;

/// 從外部注入使用者鎖定的 provider（指定模式）
void setSubagentLockedProvider(String? provider) {
  _kLockedProvider = provider;
}

/// [教練 Agent 2026-08-08] 取得目前鎖定的 provider（給 delegate_batch 共用）
String? getSubagentLockedProvider() => _kLockedProvider;

/// 子代理的 system prompt
const String _kSubAgentSystemPrompt =
    '你是一個子代理。專注完成以下任務，不要做其他事。用繁體中文回答。';

/// 支援的 provider 列表
const Set<String> _kSupportedProviders = {
  'glm',
  'openai',
  'kimi',
  'claude',
  'gemini',
};

/// 各 provider 的雲端 base URL
String _providerBaseUrl(String provider) {
  switch (provider) {
    case 'glm':
      return 'https://open.bigmodel.cn/api/paas/v4';
    case 'openai':
      return 'https://api.openai.com/v1';
    case 'kimi':
      return 'https://api.moonshot.cn/v1';
    case 'claude':
      return 'https://api.anthropic.com/v1';
    case 'gemini':
      return 'https://generativelanguage.googleapis.com/v1beta/openai';
    default:
      return 'https://open.bigmodel.cn/api/paas/v4';
  }
}

/// 統一處理 base URL（移除尾部斜線，已有版本路徑則不重複加 /v1）
String _resolveBaseUrl(String baseUrl) {
  var url = baseUrl.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (RegExp(r'/v\d+$').hasMatch(url)) {
    return url;
  }
  return '$url/v1';
}

/// delegate_subagent AgentTool
///
/// 讓 App Agent 能派子代理用不同外部 LLM 執行任務。
/// 這是向量工作流維度 1（多模型協同）的核心工具。
class DelegateSubagentTool extends AgentTool {
  final Dio _dio;

  /// [dio] — 可注入 Dio 實例（測試用）
  DelegateSubagentTool({Dio? dio})
      : _dio = dio ?? createSovereigntyDio();


  /// [資料主權 P0-b 2026-09-14] 委派流量過 DataPathGate（text/delegate）——
  /// 靜態工具，兩個 delegate tool 共用。
  static Dio createSovereigntyDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      sendTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    dio.interceptors.add(SovereigntyInterceptor(
      dataClass: DataPathClass.text,
      purpose: DataPathPurpose.delegate,
    ));
    return dio;
  }

  @override
  String get name => 'delegate_subagent';

  @override
  String get description =>
      '派子代理用指定的外部 LLM 執行任務。這是向量工作流維度 1（多模型協同）的核心——'
      '你（主大腦）指揮，子代理用不同 LLM 執行任務，你收集結果後綜合回覆。'
      '可指定不同的 provider 來利用各模型的優勢（如 GLM 推理、GPT 視覺、Kimi 文字創作）。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'goal',
          description: '子代理要完成的任務目標。要清楚具體，讓子代理知道做什麼。',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'provider',
          description: '指定用哪個 LLM provider（glm/openai/kimi/claude/gemini）。'
              '不指定則用當前主大腦的 provider。',
        ),
        AgentToolParamSpec(
          name: 'context',
          description: '給子代理的上下文資訊。相關背景、參考資料、已有結果等。',
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final goal = args['goal']?.toString();
    if (goal == null || goal.isEmpty) {
      return AgentToolResult.failure('goal 為必填參數');
    }

    final requestedProvider = args['provider']?.toString().trim();
    final context = args['context']?.toString();

    // [教練 Agent 2026-08-07] 使用者鎖定的 provider——指定模式時禁止 delegate 給其他 provider
    if (_kLockedProvider != null && _kLockedProvider!.isNotEmpty) {
      final effectiveProvider =
          (requestedProvider != null && requestedProvider.isNotEmpty)
              ? requestedProvider
              : (await StorageService.getProvider() ?? '');
      if (effectiveProvider != _kLockedProvider) {
        return AgentToolResult.failure(
          '使用者已鎖定 provider「${_kLockedProvider}」，不允許派子代理給「$effectiveProvider」。'
          '請直接使用 $_kLockedProvider 完成任務，或請使用者到設定切換 provider。',
        );
      }
    }

    // 判斷要使用哪個 provider
    // 不指定 → 用當前主大腦的 provider（走 ApiService.completeWithMessages）
    // 指定 → 用該 provider 的獨立 base URL + token
    if (requestedProvider == null || requestedProvider.isEmpty) {
      return _delegateWithCurrentProvider(goal: goal, context: context);
    }

    // 驗證 provider 是否支援
    if (!_kSupportedProviders.contains(requestedProvider)) {
      return AgentToolResult.failure(
        '不支援的 provider「$requestedProvider」。'
        '支援的 provider：${_kSupportedProviders.join('、')}',
      );
    }

    return _delegateWithSpecifiedProvider(
      goal: goal,
      context: context,
      provider: requestedProvider,
    );
  }

  /// 用當前主大腦的 provider 呼叫子代理
  ///
  /// 走 ApiService.completeWithMessages()，使用全域儲存的 provider/gateway/token。
  Future<AgentToolResult> _delegateWithCurrentProvider({
    required String goal,
    String? context,
  }) async {
    try {
      final provider = await StorageService.getProvider() ?? 'glm';
      debugPrint('[DelegateSubagent] provider=$provider goal=${goal.substring(0, goal.length.clamp(0, 60))}…');

      // 組 messages
      final userContent = _buildUserContent(goal: goal, context: context);
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': _kSubAgentSystemPrompt},
        {'role': 'user', 'content': userContent},
      ];

      debugPrint(
        '[DelegateSubagent] 用當前 provider=$provider 呼叫子代理',
      );

      final result = await ApiService.completeWithMessages(
        messages: messages,
      ).timeout(const Duration(seconds: 60));

      if (result.trim().isEmpty) {
        return AgentToolResult.failure(
          '子代理（provider=$provider）回傳空內容',
        );
      }

      return AgentToolResult.success(
        result.trim(),
        metadata: {
          'provider': provider,
          'goal': goal,
        },
      );
    } on TimeoutException {
      return AgentToolResult.failure(
        '子代理執行逾時（60 秒）。任務可能太複雜或模型回應太慢。',
      );
    } catch (e) {
      return AgentToolResult.failure('子代理執行失敗：$e');
    }
  }

  /// 用指定的 provider 呼叫子代理
  ///
  /// 直接用該 provider 的雲端 base URL + 對應 token 呼叫 API。
  Future<AgentToolResult> _delegateWithSpecifiedProvider({
    required String goal,
    String? context,
    required String provider,
  }) async {
    try {
      // 取得該 provider 的 token
      final token = await StorageService.getToken(provider: provider);
      if (token == null || token.trim().isEmpty) {
        return AgentToolResult.failure(
          'Provider「$provider」未設定 API Token。'
          '請到「系統 → 設定」中設定該 provider 的金鑰。',
        );
      }

      // 取得 base URL 和預設模型
      final baseUrl = _providerBaseUrl(provider);
      final resolvedUrl = _resolveBaseUrl(baseUrl);
      final model = ApiService.defaultModelFor(provider);

      // 取得 ProviderProfile（處理各 provider 的 API 參數差異）
      final profile = await ProviderProfileStore.instance
          .getProfile(provider, model);

      // 組 messages
      final userContent = _buildUserContent(goal: goal, context: context);
      final apiData = <String, dynamic>{
        'model': model,
        'messages': [
          {'role': 'system', 'content': _kSubAgentSystemPrompt},
          {'role': 'user', 'content': userContent},
        ],
        'stream': true,
      };
      // 加入 profile 定義的參數（temperature, max_tokens 等）
      apiData.addAll(profile.apiParams);

      debugPrint(
        '[DelegateSubagent] 用指定 provider=$provider, model=$model 呼叫子代理',
      );

      // 呼叫 streaming API
      final result = await _streamChatCompletion(
        resolvedUrl: resolvedUrl,
        token: token,
        apiData: apiData,
        profile: profile,
      ).timeout(const Duration(seconds: 60));

      if (result.trim().isEmpty) {
        return AgentToolResult.failure(
          '子代理（provider=$provider, model=$model）回傳空內容',
        );
      }

      return AgentToolResult.success(
        result.trim(),
        metadata: {
          'provider': provider,
          'model': model,
          'goal': goal,
        },
      );
    } on TimeoutException {
      return AgentToolResult.failure(
        '子代理執行逾時（60 秒）。provider=$provider，任務可能太複雜或模型回應太慢。',
        toolName: name,
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final respBody = e.response?.data?.toString() ?? '';

      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return AgentToolResult.failure(
          '無法連接到 provider「$provider」的 API server。'
          '請確認網路連線正常。詳細錯誤：${e.message}',
        );
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        return AgentToolResult.failure(
          '子代理執行逾時（60 秒）。provider=$provider。',
          toolName: name,
        );
      }
      return AgentToolResult.failure(
        'provider「$provider」API 回傳錯誤（HTTP $statusCode）：$respBody',
      );
    } catch (e) {
      return AgentToolResult.failure(
        '子代理執行失敗（provider=$provider）：$e',
      );
    }
  }

  /// 組 user message——有 context 和沒 context 用不同模板
  String _buildUserContent({required String goal, String? context}) {
    final hasContext = context != null && context.isNotEmpty;
    if (hasContext) {
      return '【上下文】\n$context\n\n【任務目標】\n$goal';
    }
    return goal;
  }

  /// Streaming SSE 請求——與 ApiService._doStreamRequest 相同邏輯
  ///
  /// 逐 chunk 讀取 SSE stream，組合 content。
  /// 支援 reasoning_content fallback（某些模型只回 reasoning_content）。
  Future<String> _streamChatCompletion({
    required String resolvedUrl,
    required String token,
    required Map<String, dynamic> apiData,
    required ProviderProfile profile,
  }) async {
    final response = await _dio.post(
      '$resolvedUrl/chat/completions',
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: ResponseType.stream,
      ),
      data: apiData,
    );

    final stream = response.data.stream as Stream<List<int>>;
    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    final lineBuf = StringBuffer();

    // 用 utf8.decoder stream transformer 處理 chunk 邊界
    final decodedStream = stream.cast<List<int>>().transform(utf8.decoder);

    await for (final decoded in decodedStream.timeout(
      const Duration(seconds: 90),
    )) {
      lineBuf.write(decoded);

      final raw = lineBuf.toString();
      final events = raw.split('\n\n');
      lineBuf.clear();
      if (!raw.endsWith('\n\n')) {
        lineBuf.write(events.removeLast());
      }

      for (final event in events) {
        for (final line in event.split('\n')) {
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload == '[DONE]') continue;
          if (payload.isEmpty) continue;

          try {
            final json = jsonDecode(payload) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;
            final delta =
                (choices[0] as Map<String, dynamic>)['delta']
                    as Map<String, dynamic>?;
            if (delta == null) continue;

            final contentDelta = delta['content'] as String?;
            if (contentDelta != null && contentDelta.isNotEmpty) {
              contentBuf.write(contentDelta);
            }

            final reasoningDelta = delta['reasoning_content'] as String?;
            if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
              reasoningBuf.write(reasoningDelta);
            }
          } catch (e) {
            // 單行 parse 失敗不中斷串流
            debugPrint('[DelegateSubagent] SSE parse skip: $e');
          }
        }
      }
    }

    final content = contentBuf.toString();
    if (content.isNotEmpty) return content;

    // fallback：如果 content 為空但 reasoning_content 有值
    if (profile.supportsReasoningContent) {
      final reasoning = reasoningBuf.toString();
      if (reasoning.isNotEmpty) return reasoning;
    }

    return '';
  }
}
