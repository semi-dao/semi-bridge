import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
// [小葵 2026-10-05 4-AED] unawaited + BrainRevival（需求驅動復活）
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'storage_service.dart';
import 'brain_revival_service.dart';
import 'provider_router.dart'; // [教練 Agent 2026-07-29] 读取路由结果
import 'provider_registry.dart'; // [教練 Agent 2026-07-30] 動態 provider/模型探測
import 'api_usage_tracker.dart'; // [教練 Agent 2026-07-29] API 額度追蹤
import 'memory_store.dart';
import 'agent_loop/llm_retry_utils.dart';
import 'local_model_runtime_service.dart'; // [教練 Agent 2026-08-05] resolveShortModelName 用
import 'sovereignty/data_path_gate.dart'; // [資料主權 P0-b] DataPathGrade/Class/Purpose
import 'sovereignty/data_path_interceptor.dart'; // [資料主權 P0-b] 主幹 Dio 咽喉 interceptor
import 'agent_loop/agent_provider_profile.dart'; // [教練 Agent 2026-07-18] Provider 能力適配
import 'agent_loop/agent_profile_store.dart'; // [教練 Agent 2026-07-18] 自進化 ProviderProfileStore
import 'brain_container/brain_container_service.dart'; // [教練 Agent 2026-07-03]
import 'intent_classifier.dart';
import 'persona_prompt.dart';
import 'context_compressor.dart';
import 'companion_store.dart';
import '../models/bridge_action.dart';
import '../models/project_door.dart';
import 'billing_modes.dart'; // [教練 Agent 2026-08-16] billing mode 糾偏用
import '../models/transurfing_brain.dart';
import '../models/second_brain_trace.dart';
import 'package:bridge_app/services/brain_container/profile/user_profile_service.dart';

/// [2026-07-29] 精確的 API 錯誤分類 enum
/// 放在檔案頂層（Dart 不允許 enum 宣告在 class 內）。
/// 區分 401/429/timeout/connection/quota/other，每種給對應的準確訊息。
/// 之前：401 和 429 一律當作「token 額度用完」自動切本地，導致使用者以為
///   是 quota 問題但其實是 key 失效或速率限制。
enum ApiErrorCategory {
  /// 401 / 403（無 token、無效 key、過期 token、權限不足）
  auth,

  /// 429（速率限制 / 請求太頻繁）
  rateLimit,

  /// 真正的額度/帳單問題（402 或訊息含 billing/quota/insufficient_balance）
  quota,

  /// TimeoutException（連線或讀取逾時）
  timeout,

  /// 連線錯誤（Connection refused、SocketException、DNS failure 等）
  connection,

  /// 其他（5xx、4xx 未知、parse error 等）
  other,
}

class ApiCompletionReceipt {
  final String text;
  final String provider;
  final String model;
  final bool usedLocalFallback;

  const ApiCompletionReceipt({
    required this.text,
    required this.provider,
    required this.model,
    this.usedLocalFallback = false,
  });
}

/// [小葵 2026-09-21 收尾驗收] 串流真值載體——provider 在最後 chunk
/// 回的真實 token 數（區別於 chars÷4 估算）
class RealStreamUsage {
  final int promptTokens;
  final int completionTokens;
  const RealStreamUsage({required this.promptTokens, required this.completionTokens});
}

class ApiService {
  // [小葵 2026-09-21 收尾驗收] 串流真值——_doStreamRequest 攔到的 usage
  // （stream_options.include_usage 最後 chunk 回的真實 token 數）
  static RealStreamUsage? _lastStreamUsage;
  static final Dio _dio = _createDio();

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        // [教練 Agent 2026-06-28] 修復：分析跑很久會 timeout — 60s → 120s
        // [2026-07-18] multimodal vision (glm-4.6v) 處理截圖需要更久 — 120s → 300s
        receiveTimeout: const Duration(seconds: 300),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    // [資料主權 P0-b 2026-09-14] 主對話所有對外流量過 DataPathGate 咽喉點。
    // red（白名單外網域）直接攔截，請求不發出；green/yellow 記帳放行。
    // 詳情：docs/specs/2026-09-14-data-sovereignty-design.md §4.1
    dio.interceptors.add(SovereigntyInterceptor(
      dataClass: DataPathClass.text,
      purpose: DataPathPurpose.mainChat,
    ));
    return dio;
  }

  // 自動化測試用：允許外部直接注入配置
  static String? _overrideBaseUrl;
  static String? _overrideToken;

  static void setOverrideConfig({String? baseUrl, String? token}) {
    _overrideBaseUrl = baseUrl;
    _overrideToken = token;
  }

  /// [教練 Agent 2026-07-30] 統一解析 provider——'default' 轉成路由結果的實際 provider
  static Future<String> _effectiveProvider() async {
    // [T7④ 補刀2 2026-10-16] localOnly 一票否決——第三處側門：
    // stored=openai 直接返回，繞過路由層。斷網血管：一律 local。
    if (await StorageService.getLocalOnly()) return 'local';
    final stored =
        await StorageService.getProvider() ??
        await StorageService.detectAvailableProvider() ??
        'openai';
    if (stored == 'default') {
      return ProviderRouter.instance.current?.providerId ?? 'openai';
    }
    return stored;
  }

  /// 取得目前設定的 Base URL
  /// [教練 Agent 2026-07-29] 優先使用 ProviderRouter 的路由結果，避免覆蓋使用者選的 provider
  /// [教練 Agent 2026-07-30] 'default' 預設選型模式：用 ProviderRouter.routedBaseUrl
  static Future<String?> _getBaseUrl() async {
    if (_overrideBaseUrl != null) return _overrideBaseUrl;
    // [T7④ 補刀3 2026-10-16 深夜] localOnly 直接回本地 endpoint——
    // 不吃 routedBaseUrl（殘留雲端）也不 fallback storage（openai）
    if (await StorageService.getLocalOnly()) {
      debugPrint('[T7④TRACE] _getBaseUrl localOnly → 本地 endpoint');
      return await StorageService.getLocalModelEndpoint() ?? 'http://127.0.0.1:18789';
    }
    // [T7① 2026-10-16 編織線 D7] 分流只有一個腦——一律先吃 ProviderRouter
    // 路由結果（chat_controller 每輪 setCurrent；使用者明選 provider 時
    // setCurrent 也會設成使用者選的雲端 URL），刪除 provider=='default'
    // 特例判斷。routedBaseUrl 是記憶體值，永不覆蓋使用者 storage。
    final routedUrl = ProviderRouter.instance.routedBaseUrl;
    if (routedUrl != null && routedUrl.isNotEmpty) return routedUrl;
    final provider = await StorageService.getProvider();
    // [教練 Agent 2026-08-16 使用者 抓包] billing mode 糾偏——存起來的 gateway_url
    // 可能跟 billing mode 脫鉤（歷史 bug：切計費模式沒寫回 URL）。
    // 這裡當場比對：billing mode 說的 URL 跟存的 URL 不同 provider 網域
    // 就以 billing mode 為準（使用者選計費模式 = 授權用那個 endpoint）。
    if (provider != null && provider != 'local' && provider != 'default') {
      final billingUrl = await BillingModes.getBaseUrl(provider);
      final stored = await StorageService.getGatewayUrl();
      final hostMismatch = billingUrl.isNotEmpty &&
          stored != null &&
          stored.isNotEmpty &&
          _hostOf(stored) != _hostOf(billingUrl);
      if (hostMismatch) {
        debugPrint('[ApiService] gateway_url 與 billing mode 脫鉤，自動糾正 → $billingUrl');
        await StorageService.saveGatewayUrl(billingUrl);
        return billingUrl;
      }
    }
    return await StorageService.getGatewayUrl();
  }

  /// [教練 Agent 2026-08-16] 取 URL 的 host（比對網域用）
  static String _hostOf(String url) {
    final m = RegExp(r'https?://([^/]+)').firstMatch(url.trim());
    return m?.group(1)?.toLowerCase() ?? url.toLowerCase();
  }

  /// 取得 Bearer Token
  /// [教練 Agent 2026-07-30] 'default' 預設選型模式：用路由結果的 provider 查 token
  static Future<String?> _getToken() async {
    if (_overrideToken != null) return _overrideToken;
    // [T7④ 補刀3] localOnly 回本地 token（'ollama'/'bridge-local-runtime'）——
    // 不因 storage provider=openai 而拿過期雲 token
    if (await StorageService.getLocalOnly()) {
      debugPrint('[T7④TRACE] _getToken localOnly → ollama');
      return 'ollama';
    }
    final provider = await StorageService.getProvider();
    if (provider == 'default') {
      final routedProvider = ProviderRouter.instance.current?.providerId;
      if (routedProvider != null && routedProvider != 'local') {
        return await StorageService.getToken(provider: routedProvider);
      }
      // local 不需要 token
      if (routedProvider == 'local') return 'ollama';
    }
    return await StorageService.getToken();
  }

  /// 測試連線（使用已儲存設定）
  static Future<List<String>> testConnection() async {
    final baseUrl = await _getBaseUrl();
    final token = await _getToken();

    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('Gateway URL 未設定');
    }
    if (token == null || token.isEmpty) {
      throw Exception('API Token 未設定');
    }

    return testConnectionWith(baseUrl, token);
  }

  /// 統一處理 Base URL（移除尾部斜線，自動補 /v1）
  /// GLM 用 /v4，若 URL 已含版本路徑（/v1, /v4 等）則不重複加。
  static String _resolveBaseUrl(String baseUrl) {
    var url = baseUrl.trim();
    // 移除尾部斜線
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    // 如果已經包含版本路徑（/v1, /v2, ... /v9, /v1beta/openai），不要重複加
    if (RegExp(r'/v\d+(/openai)?$').hasMatch(url)) {
      return url;
    }
    return '$url/v1';
  }

  /// 測試連線（使用指定 URL + Token）
  static Future<List<String>> testConnectionWith(
    String baseUrl,
    String token,
  ) async {
    final resolvedUrl = _resolveBaseUrl(baseUrl);
    try {
      final response = await _dio.get(
        '$resolvedUrl/models',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final data = response.data;
      if (data['data'] != null) {
        return (data['data'] as List)
            .map((m) => m['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .map((id) => id.startsWith('models/') ? id.substring(7) : id)
            .toList();
      }
      return [];
    } catch (e) {
      // [教練 Agent 2026-08-17 使用者 抓包] 測試連線的錯誤要分級——
      // 401/403 = token 無效，這是真的測試失敗，必須拋錯讓 UI 顯示失敗。
      // 之前所有錯誤都吞成空列表 → UI 把空列表當成功走 fallback，
      // 「刪掉 token 測試還顯示測試成功」的元兇。
      // 404 / 其他 = 端點不支援（如 Claude 無 /models）→ 空列表走 fallback。
      if (e is DioException && e.response?.statusCode != null) {
        final status = e.response!.statusCode!;
        if (status == 401 || status == 403) {
          debugPrint('[ApiService] testConnectionWith: 認證失敗 ($status)——token 無效');
          throw Exception('API Token 無效或未授權（HTTP $status）');
        }
        if (status == 404) {
          debugPrint('[ApiService] testConnectionWith: 端點不支援 /models (404) → 空列表走 fallback');
          return [];
        }
        // 其他 HTTP 錯誤（500/429...）也是真失敗
        debugPrint('[ApiService] testConnectionWith: HTTP $status 失敗');
        throw Exception('連線失敗（HTTP $status）');
      }
      // 網路層錯誤（timeout / DNS）也是真失敗
      debugPrint('[ApiService] testConnectionWith: 網路錯誤: $e');
      throw Exception('網路連線失敗：${e.toString().split('(').first.trim()}');
    }
  }

  /// 發送聊天訊息：POST /v1/chat/completions
  /// [overrideIntent] 允許手動覆蓋自動分類的意圖
  static Future<ChatResponse> sendMessage(
    List<Map<String, String>> messages, {
    String? model,
    UserIntent? overrideIntent,
    BrainReflection? brainReflection,
    List<String> recalledTransurfingInsights = const [],
    ProjectDoor? activeProjectDoor,
    List<SecondBrainMemoryTrace> secondBrainMemories = const [],
    String?
    pendingHandoffNote, // [以利沙 P0 修復十七輪 2026-06-27] 交接說明注入 system prompt
    String? memoryRecallNote, // [教練 Agent 2026-07-25] 記憶回溯 — 失憶抱怨時注入找回的內容
  }) async {
    final baseUrl = await _getBaseUrl();
    final token = await _getToken();
    debugPrint(
      '[ApiService.sendMessage] baseUrl=$baseUrl, token=${token?.substring(0, 10)}...',
    );

    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('Gateway URL 未設定');
    }
    // [以利沙 P1 修復二十一輪 2026-06-27] 本地模型豁免 token 檢查
    final provider = await _effectiveProvider();
    final isLocalModel =
        provider == 'local' ||
        baseUrl.toLowerCase().contains('127.0.0.1') ||
        baseUrl.toLowerCase().contains('localhost') ||
        baseUrl.toLowerCase().contains('18789') ||
        baseUrl.toLowerCase().contains('11434') ||
        baseUrl.toLowerCase().contains('ollama') ||
        baseUrl.toLowerCase().contains('192.168.') ||
        baseUrl.toLowerCase().contains('10.');
    // 本地模型模式 token 為空時用 'ollama' 預設值
    final effectiveToken = (token == null || token.isEmpty)
        ? (isLocalModel ? 'ollama' : token)
        : token;
    if (effectiveToken == null || effectiveToken.isEmpty) {
      throw Exception('API Token 未設定');
    }

    final selectedModel = model ?? await _defaultModelFor(provider);

    final resolvedUrl = _resolveBaseUrl(baseUrl);

    // 識別使用者意圖（支援手動覆蓋）
    final UserIntent intent;
    if (overrideIntent != null) {
      intent = overrideIntent;
    } else {
      final lastUserMessage = messages.isNotEmpty
          ? messages.lastWhere(
                  (m) => m['role'] == 'user',
                  orElse: () => {'content': ''},
                )['content'] ??
                ''
          : '';
      intent = IntentClassifier.classify(lastUserMessage);
    }
    final intentName = IntentClassifier.intentName(intent);
    final intentIcon = IntentClassifier.intentIcon(intent);

    // 載入長期記憶
    final memories = await MemoryStore.getFormattedMemories();

    // [小葵 2026-09-22 偷學令②] 使用者檔案（static/dynamic 分層常駐）——
    // 該全程知道的事不靠搜尋（名字/偏好跟任意查詢語意不相近，向量永遠
    // 搜不到），靠檔案每輪掛上。快取讀取零 DB 查詢。
    final userProfile = UserProfileService.instance.getFormattedProfile();
    final memoriesWithProfile = userProfile.isEmpty
        ? memories
        : (memories.isEmpty ? userProfile : '$memories\n\n$userProfile');

    // [教練 Agent 2026-07-03] 大腦容器向量記憶檢索
    // 用最後一條使用者訊息做語意搜尋，找相關記憶注入 system prompt
    var allMemories = memories;
    final lastUserMsg = messages.isNotEmpty
        ? messages.lastWhere(
                (m) => m['role'] == 'user',
                orElse: () => {'content': ''},
              )['content'] ??
              ''
        : '';
    if (lastUserMsg.isNotEmpty) {
      final brainContext = await BrainContainerService.instance
          .getFormattedContext(lastUserMsg);
      if (brainContext.isNotEmpty) {
        allMemories = memoriesWithProfile.isEmpty
            ? '\n\n【關聯記憶（向量檢索）】\n$brainContext'
            : '$memoriesWithProfile\n\n【關聯記憶（向量檢索）】\n$brainContext';
      }
    }

    // 根據意圖取得對應 persona
    final persona = PersonaPrompt.getPersonaByIntent(intentName);

    // 組合 system prompt（加入自動搭橋能力說明）
    final bridgeCapabilities = _buildBridgeCapabilities();
    final companionPrompt = _buildActiveCompanionPrompt();
    final projectDoorPrompt = _buildProjectDoorPrompt(activeProjectDoor);

    final systemContent =
        '''${PersonaPrompt.build(memories: allMemories, intentName: intentName, intentIcon: intentIcon)}

$persona

$companionPrompt

$projectDoorPrompt

$bridgeCapabilities''';

    final compressedContext = await _compressContextForChat(
      messages,
      provider: provider,
      resolvedUrl: resolvedUrl,
      token: effectiveToken, // [以利沙 P1 修復二十一輪 2026-06-27] 本地模型豁免
      model: selectedModel,
    );
    final brainNotes = brainReflection == null
        ? null
        : ContextCompressor.buildTransurfingBrainNotes(brainReflection);
    final insightRecallNotes =
        ContextCompressor.buildTransurfingInsightRecallNotes(
          recalledTransurfingInsights,
        );
    final secondBrainMemoryNotes =
        ContextCompressor.buildSecondBrainMemoryNotes(secondBrainMemories);
    final modelIdentityNote = provider == 'local'
        ? '\n\n【當前推論引擎】你正在以本地模型「$selectedModel」的身份運行，使用者的資料完全留在本機。若被問到「你跑在哪個模型上」，請回答：我目前是以本地模型 $selectedModel 運行，資料不會上傳雲端。'
        : '\n\n【當前推論引擎】你正在使用 $provider 雲端服務（模型：$selectedModel）。';
    // [以利沙 P0 修復十七輪 2026-06-27] 若有交接說明，附加到 system prompt（只注入一次）
    final handoffNote = pendingHandoffNote != null
        ? '\n\n【交接說明】$pendingHandoffNote'
        : '';
    final finalSystemContent = [
      systemContent + modelIdentityNote + handoffNote,
      ?compressedContext.systemNote,
      ?insightRecallNotes,
      ?secondBrainMemoryNotes,
      ?brainNotes,
      ?memoryRecallNote, // [教練 Agent 2026-07-25] 記憶回溯
    ].join('\n\n');

    final messagesWithSystem = [
      {'role': 'system', 'content': finalSystemContent},
      ...compressedContext.messages,
    ];

    final requestBody = {
      'model': selectedModel,
      'messages': messagesWithSystem,
      'temperature': 1,
      'stream': false,
      // [教練 Agent 2026-07-22] Qwen3.5-4B thinking mode 修復
      if (provider == 'local')
        'chat_template_kwargs': {'enable_thinking': false},
    };

    try {
      final response = await _dio.post(
        '$resolvedUrl/chat/completions',
        options: Options(
          headers: {'Authorization': 'Bearer $effectiveToken'},
        ), // [以利沙 P1 修復二十一輪 2026-06-27] 本地模型豁免
        data: requestBody,
      );

      return ChatResponse.fromJson(response.data);
    } catch (e) {
      // [教練 Agent 2026-07-31] 模型不存在 (404) → 自動修復並重試
      if (e.toString().contains('404') ||
          e.toString().contains('not_found_error')) {
        debugPrint('[ApiService] sendMessage: 偵測到 404，嘗試 autoHealModel...');
        final healed = await autoHealModel(
          provider: provider,
          baseUrl: baseUrl,
          token: effectiveToken,
          failedModel: selectedModel,
        );
        if (healed != null) {
          debugPrint('[ApiService] sendMessage: 用修復後的模型 $healed 重試');
          final retryResponse = await _dio.post(
            '$resolvedUrl/chat/completions',
            options: Options(
              headers: {'Authorization': 'Bearer $effectiveToken'},
            ),
            data: {...requestBody, 'model': healed},
          );
          return ChatResponse.fromJson(retryResponse.data);
        }
      }
      // [小葵 2026-10-05 Blue 令 4-AED] 本地引擎連線失敗 → 需求驅動復活。
      // 她「需要腦」的訊號要在這裡被聽見——不能只靠看門狗輪詢
      // （會被閒置卸載/冷卻擋住）。fire-and-forget：喚醒不擋原本的
      // 錯誤路徑，loop 的重試機制會在引擎回來後接手。
      if (isLocalModel && e is DioException && e.response == null) {
        debugPrint('[ApiService] 本地引擎無回應（AED 觸發）: ${e.type}');
        unawaited(BrainRevivalService.instance
            .demandRevive(LocalModelRuntimeService()));
      }
      rethrow;
    }
  }

  static Future<ContextCompressionResult> _compressContextForChat(
    List<Map<String, String>> messages, {
    required String provider,
    required String resolvedUrl,
    required String token,
    required String model,
  }) async {
    final enabled = await StorageService.isContextCompressionEnabled();
    final draft = ContextCompressor.createDraft(messages, enabled: enabled);

    if (!draft.shouldCompress) {
      return ContextCompressionResult(
        systemNote: null,
        messages: draft.recentMessages,
        compressedCount: 0,
      );
    }

    final localFallback = ContextCompressor.compressMessagesSync(
      messages,
      enabled: enabled,
    );

    if (!_supportsOpenAiCompatibleChat(provider)) {
      return localFallback;
    }

    try {
      final summary = await _generateSemanticContextSummary(
        draft.olderMessages,
        resolvedUrl: resolvedUrl,
        token: token, // 接收端已傳入 effectiveToken
        model: model,
      );
      return ContextCompressor.buildResultFromDraft(
        draft,
        systemNote: ContextCompressor.buildSemanticSystemNote(summary),
        strategy: 'semantic',
      );
    } catch (error) {
      debugPrint('[ContextCompressor] semantic fallback: $error');
      return localFallback;
    }
  }

  static bool _supportsOpenAiCompatibleChat(String provider) {
    return provider == 'openai' ||
        provider == 'kimi' ||
        provider == 'minimax' ||
        provider == 'local' ||
        provider == 'glm';
  }

  static Future<String> _generateSemanticContextSummary(
    List<Map<String, String>> olderMessages, {
    required String resolvedUrl,
    required String token,
    required String model,
  }) async {
    final transcript = ContextCompressor.buildSemanticTranscript(olderMessages);
    if (transcript.trim().isEmpty) {
      throw Exception('沒有可壓縮的上下文');
    }

    // [教練 Agent 2026-07-30] reasoning model（kimi-k3 等）只接受 temperature=1
    final response = await _dio.post(
      '$resolvedUrl/chat/completions',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
      data: {
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content': [
              '你是對話摘要助手。請將較早的對話壓縮成簡潔摘要，保留關鍵資訊和決定。',
              '不要加入橋樑動作標記，不要輸出程式碼區塊外框。',
              '如果對話中有出現具體數字（薪資、價格、日期、百分比）或瀏覽查詢結果，請以「【數據保留】」區塊明確保留原始數字，不要模糊化或省略。',
            ].join('\n'),
          },
          {'role': 'user', 'content': '請壓縮以下較早對話：\n\n$transcript'},
        ],
        if (!model.toLowerCase().startsWith('kimi-k3') &&
            !model.toLowerCase().startsWith('gpt-5'))
          'temperature': 0.2,
        'stream': false,
      },
    );

    final summary = ChatResponse.fromJson(response.data).cleanContent.trim();
    if (summary.isEmpty) {
      throw Exception('語意壓縮結果為空');
    }
    return _stripMarkdownFences(summary);
  }

  /// 使用目前選擇的 OpenAI-compatible provider 生成 Markdown 文件內容。
  static Future<String> generateDocumentMarkdown(
    String prompt, {
    String? model,
  }) async {
    final provider = await _effectiveProvider();
    if (provider != 'openai' &&
        provider != 'kimi' &&
        provider != 'minimax' &&
        provider != 'local' &&
        provider != 'glm') {
      throw UnsupportedError('$provider 尚未支援文件生成');
    }

    final baseUrl = await _getBaseUrl();
    final token = await _getToken();
    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('Gateway URL 未設定');
    }
    // [以利沙 P1 修復二十一輪 2026-06-27] 本地模型豁免 token 檢查
    final isLocal =
        provider == 'local' ||
        baseUrl.toLowerCase().contains('127.0.0.1') ||
        baseUrl.toLowerCase().contains('localhost') ||
        baseUrl.toLowerCase().contains('18789') ||
        baseUrl.toLowerCase().contains('11434') ||
        baseUrl.toLowerCase().contains('ollama');
    if (token == null || token.isEmpty) {
      if (!isLocal) {
        throw Exception('API Token 未設定');
      }
    }
    final effectiveToken = (token == null || token.isEmpty)
        ? (isLocal ? 'ollama' : token!)
        : token;

    final selectedModel = model ?? await _defaultModelFor(provider);
    final resolvedUrl = _resolveBaseUrl(baseUrl);
    final response = await _dio.post(
      '$resolvedUrl/chat/completions',
      options: Options(headers: {'Authorization': 'Bearer $effectiveToken'}),
      data: {
        'model': selectedModel,
        'messages': [
          {
            'role': 'system',
            'content': [
              '你是橋樑計畫的文件生成代理。',
              '請根據使用者需求產出完整、可直接儲存的 Markdown 文件。',
              '只輸出 Markdown 內容，不要輸出程式碼區塊外框，不要插入橋樑標記。',
              '文件要有清楚標題、段落、條列與下一步建議。',
            ].join('\n'),
          },
          {'role': 'user', 'content': '請根據以下需求產出 Markdown 文件：\n\n$prompt'},
        ],
        // [教練 Agent 2026-07-30] reasoning model 不支援自訂 temperature
        if (!selectedModel.toLowerCase().startsWith('kimi-k3') &&
            !selectedModel.toLowerCase().startsWith('gpt-5'))
          'temperature': 0.7,
        'stream': false,
      },
    );

    final markdown = ChatResponse.fromJson(response.data).cleanContent.trim();
    if (markdown.isEmpty) {
      throw Exception('文件生成結果為空');
    }
    return _stripMarkdownFences(markdown);
  }

  @visibleForTesting
  static String stripMarkdownFencesForTest(String markdown) {
    return _stripMarkdownFences(markdown);
  }

  static String _stripMarkdownFences(String markdown) {
    final trimmed = markdown.trim();
    final fenceMatch = RegExp(
      r'^```(?:markdown|md)?\s*\n([\s\S]*?)\n```$',
      caseSensitive: false,
    ).firstMatch(trimmed);

    return fenceMatch == null ? trimmed : fenceMatch.group(1)!.trim();
  }

  /// [2026-07-29] 自動 fallback 的提醒訊息（只在 timeout/connection 觸發時用）
  /// 之前的版本誤把所有 fallback 都標成「token 額度用完」，但 401≠quota、429≠quota。
  static const _localFallbackWarning =
      '\n\n⚠️ 外部 API 連不上（逾時/連線錯誤），已自動改用本地模型完成，'
      '結果可能不如平時準確。請檢查網路或 endpoint 設定。';

  /// [2026-07-29] 精確分類 API 錯誤類型
  @visibleForTesting
  static ApiErrorCategory classifyApiError(Object e) {
    // 從 DioException 抽取 status code + error body
    int? statusCode;
    String errorBody = '';
    if (e is DioException) {
      statusCode = e.response?.statusCode;
      // [教練 Agent 2026-07-30] 修復：streaming 模式下 response.data 是 ResponseBody 物件，
      // toString() 只印 'Instance of ResponseBody'，使用者看不到真正的錯誤原因。
      final data = e.response?.data;
      if (data is String) {
        errorBody = data.toLowerCase();
      } else if (data is ResponseBody) {
        // streaming 模式的錯誤回應——讀 statusMessage 作為 fallback
        // 完整 body 在 _wrapApiError 裡 async 讀取
        errorBody = (e.response?.statusMessage ?? e.message ?? '')
            .toLowerCase();
      } else {
        errorBody = (data?.toString() ?? e.message ?? '').toLowerCase();
      }
    }
    final msg = e.toString().toLowerCase();

    // 1. Timeout（最先判斷：HTTP 層次優先於 status code）
    if (msg.contains('timeoutexception') ||
        msg.contains('receivetimeout') ||
        msg.contains('sendtimeout') ||
        msg.contains('connectiontimeout') ||
        e.toString().contains('TimeoutException')) {
      return ApiErrorCategory.timeout;
    }

    // 2. 連線錯誤（沒 status code，純網路問題）
    if (msg.contains('socketexception') ||
        msg.contains('connection refused') ||
        msg.contains('connectionerror') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection closed') ||
        msg.contains('handshakeexception')) {
      return ApiErrorCategory.connection;
    }

    // 3. 真正的 quota / billing（必須有明確 billing 線索，不能亂猜）
    final isQuotaKeyword =
        errorBody.contains('insufficient') ||
        errorBody.contains('quota') ||
        errorBody.contains('billing') ||
        errorBody.contains('balance') ||
        errorBody.contains('payment') ||
        errorBody.contains('credit') ||
        errorBody.contains('额度') ||
        errorBody.contains('餘額') ||
        errorBody.contains('配额');
    if (statusCode == 402 ||
        (isQuotaKeyword && statusCode != 401 && statusCode != 403)) {
      return ApiErrorCategory.quota;
    }

    // 4. Auth（401/403，沒 quota 線索才算）
    if (statusCode == 401) return ApiErrorCategory.auth;
    if (statusCode == 403 && !isQuotaKeyword) return ApiErrorCategory.auth;

    // 5. Rate limit（429）
    if (statusCode == 429) return ApiErrorCategory.rateLimit;

    return ApiErrorCategory.other;
  }

  /// [2026-07-29] 給使用者看的人話錯誤訊息
  @visibleForTesting
  static String userFriendlyApiErrorMessage(
    ApiErrorCategory category, {
    String? rawDetail,
  }) {
    switch (category) {
      case ApiErrorCategory.auth:
        return '⚠️ API 金鑰無效或已過期，請到設定檢查 provider 的 token。';
      case ApiErrorCategory.rateLimit:
        return '⚠️ 請求太頻繁（rate limit），請稍後再試，或考慮降低並發量。';
      case ApiErrorCategory.quota:
        return '⚠️ API 額度可能已用完，請檢查 provider 帳戶的計費狀態。';
      case ApiErrorCategory.timeout:
        return '⚠️ 連線逾時，請檢查網路或稍後再試。';
      case ApiErrorCategory.connection:
        return '⚠️ 無法連線到 API，請檢查網路狀態或 endpoint 設定。';
      case ApiErrorCategory.other:
        if (rawDetail != null && rawDetail.isNotEmpty) {
          return '⚠️ API 錯誤：$rawDetail';
        }
        return '⚠️ API 發生未分類錯誤，請查看 log 取得細節。';
    }
  }

  /// [2026-07-29] 判斷錯誤是否為「連線/逾時」這種可恢復的暫時性錯誤
  /// 只有這類錯誤才適合自動 fallback 到本地模型——其他錯誤（401/429/quota）
  /// 是確定性的使用者問題，切本地只會掩蓋事實。
  static bool _isTransientFallbackWorthy(Object e) {
    final cat = classifyApiError(e);
    return cat == ApiErrorCategory.timeout ||
        cat == ApiErrorCategory.connection;
  }

  /// [2026-07-29] 把已分類的錯誤包成 Exception 給上層用
  /// （保留原始 exception 以便 debug，但訊息用人話版本）
  /// [教練 Agent 2026-07-30] 改為 async——streaming 模式下需 async 讀取 ResponseBody
  static Future<Exception> _wrapApiError(
    Object e,
    ApiErrorCategory category,
  ) async {
    String raw;
    if (e is DioException) {
      final data = e.response?.data;
      if (data is ResponseBody) {
        // streaming 模式——async 讀取真正的錯誤 body
        try {
          final bytes = <int>[];
          await for (final chunk in data.stream) {
            bytes.addAll(chunk);
          }
          raw = utf8.decode(bytes);
        } catch (_) {
          raw = e.response?.statusMessage ?? e.message ?? e.toString();
        }
      } else {
        raw = data?.toString() ?? e.message ?? e.toString();
      }
    } else {
      raw = e.toString();
    }
    final friendly = userFriendlyApiErrorMessage(category, rawDetail: raw);
    return Exception(friendly);
  }

  /// [Sprint 11 Part B 以利沙] 輕量 LLM 呼叫——給 pipeline analyzer 用
  /// 只送 system + user prompt，拿純文字回來，不帶 persona/memory/bridge。
  /// 共用既有的 _dio / _getBaseUrl / _getToken / _resolveBaseUrl / _defaultModelFor。
  static Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
    String? model,
    Map<String, dynamic>? extraApiParams,
  }) async => (await completeWithReceipt(
    systemPrompt: systemPrompt,
    userPrompt: userPrompt,
    model: model,
    extraApiParams: extraApiParams,
  )).text;

  /// 與 [complete] 相同，但保留這一輪實際執行的 provider / model。
  /// UI provenance 必須以此 receipt 為準，絕不能回讀 Settings 推測。
  static Future<ApiCompletionReceipt> completeWithReceipt({
    required String systemPrompt,
    required String userPrompt,
    String? model,
    Map<String, dynamic>? extraApiParams,
  }) async {
    final baseUrl = await _getBaseUrl();
    final token = await _getToken();

    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('Gateway URL 未設定');
    }

    // [教練 Agent 2026-07-29] 聊天對話優先使用使用者選的 provider，
    // 不讀 ProviderRouter 路由結果（路由結果僅供 Agent Loop 使用）
    final provider = await _effectiveProvider();
    final isLocalModel =
        provider == 'local' ||
        baseUrl.toLowerCase().contains('127.0.0.1') ||
        baseUrl.toLowerCase().contains('localhost') ||
        baseUrl.toLowerCase().contains('18789') ||
        baseUrl.toLowerCase().contains('11434') ||
        baseUrl.toLowerCase().contains('ollama') ||
        baseUrl.toLowerCase().contains('192.168.') ||
        baseUrl.toLowerCase().contains('10.');
    final effectiveToken = (token == null || token.isEmpty)
        ? (isLocalModel ? 'ollama' : token)
        : token;
    if (effectiveToken == null || effectiveToken.isEmpty) {
      throw Exception('API Token 未設定');
    }

    final selectedModel = model ?? await _defaultModelFor(provider);
    // [教練 Agent 2026-08-17 診斷] 模型解析鏈追蹤（5.3 升級驗收用，之後可留）
    debugPrint('[ApiService][診斷] receipt provider=$provider '
        '傳入model=${model ?? "null"} → selectedModel=$selectedModel '
        'prefsApiModel=${await StorageService.getApiModel(provider: provider) ?? "null"}');
    final resolvedUrl = _resolveBaseUrl(baseUrl);

    // [教練 Agent 2026-07-18] 依 ProviderProfile 動態組 API 參數
    // 處理各 provider 的參數差異：gpt-5 不支援 temperature、要用 max_completion_tokens 等
    // [教練 Agent 2026-07-18] 改用 ProviderProfileStore（自進化版本），取代舊的硬編碼 forModel
    // [教練 Agent 2026-07-30 v2] 改用 apiParamsForHttp 取代直接 addAll(apiParams)——
    // apiParamsForHttp 會過濾掉 max_tokens / max_completion_tokens，全面開通。
    final profile = await ProviderProfileStore.instance.getProfile(
      provider,
      selectedModel,
    );
    final apiData = <String, dynamic>{
      'model': selectedModel,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      'stream': true, // [教練 Agent 2026-07-19] 對齊 Hermes：永遠走 streaming
      '_provider': provider, // [教練 Agent 2026-07-29] 記錄用於 ApiUsageTracker
    };
    // [教練 Agent 2026-07-30 v2] 注入 apiParams（已過濾掉 max_tokens / max_completion_tokens）
    // 保留：temperature、chat_template_kwargs 等技術／性格參數。
    apiData.addAll(profile.apiParamsForHttp);
    // [小葵 2026-09-24 快軌提速] 呼叫端指定額外參數（如 thinking disabled）
    // 覆寫在 profile 之後——快軌要的是「秒回」不是「深思」。
    if (extraApiParams != null) {
      apiData.addAll(extraApiParams);
    }
    // [小葵 2026-09-25 OpenAI 400 修復] 'thinking' 是 GLM/MiniMax 家族參數，
    // OpenAI 不認識會整包 400（Unknown parameter: 'thinking'）。
    // 按 provider 白名單過濾——模型完全跟隨使用者所選，選誰都能用。
    const thinkingAwareProviders = {'glm', 'minimax'};
    if (apiData.containsKey('thinking') &&
        !thinkingAwareProviders.contains(apiData['_provider'])) {
      apiData.remove('thinking');
    }

    debugPrint(
      '[ApiService] complete: model=$selectedModel, stream=true, '
      'apiParams=${profile.apiParams}',
    );
    // [教練 Agent 2026-08-02] 診斷：記錄 system prompt + user prompt 大小
    debugPrint(
      '[ApiService] prompt sizes: system=${systemPrompt.length} chars, '
      'user=${userPrompt.length} chars, total=~${(systemPrompt.length + userPrompt.length) ~/ 4} tokens',
    );

    // [教練 Agent 2026-07-19] 純文字路徑也走 streaming——對齊 Hermes
    // 原生 Agent讀完原始碼後走這條路，non-streaming 會 hang，必須改 streaming
    // [2026-07-27] 修復：必須 await 才能讓 try/catch 捕獲 streaming 中的 429/401
    // _streamChatCompletion 雖然回傳 Future<String>，但內部用 await for 消耗 stream，
    // 錯誤是在 stream 消費期間非同步拋出。沒有 await 的話 try/catch 只包住 Future 建立，
    // 捕不到後續的非同步錯誤，fallback 永遠不會觸發。
    try {
      final text = await _streamChatCompletion(
        resolvedUrl: resolvedUrl,
        token: effectiveToken,
        apiData: apiData,
        profile: profile,
      );
      return ApiCompletionReceipt(
        text: text,
        provider: provider,
        model: selectedModel,
      );
    } catch (e) {
      // [2026-07-29] 精確錯誤處理：只對 timeout/connection 這種暫時性錯誤
      // 才自動 fallback 到本地；401/429/quota 等確定性錯誤必須 throw 出去，
      // 用人話訊息告訴使用者真正的問題，不要再誤標「token 額度用完」。
      final category = classifyApiError(e);
      if (!isLocalModel && _isTransientFallbackWorthy(e)) {
        debugPrint('[ApiService] ⚠️ 外部 API 暫時無法連線 ($category)，切換本地模型');
        final localResult = await _callLocalModelWithFallback(
          apiData: apiData,
          originalProvider: provider,
        );
        return ApiCompletionReceipt(
          text: '$localResult$_localFallbackWarning',
          provider: 'local',
          model: await _defaultModelFor('local'),
          usedLocalFallback: true,
        );
      }
      // 確定性錯誤——用人話訊息包起來，讓上游 (ChatController) 直接顯示。
      throw await _wrapApiError(e, category);
    }
  }

  /// [2026-07-27] API token fallback 共用方法——用本地模型重跑相同請求
  /// 只在 timeout/connection 暫時性錯誤時被呼叫，注入提醒訊息到 system prompt
  static Future<String> _callLocalModelWithFallback({
    required Map<String, dynamic> apiData,
    required String originalProvider,
  }) async {
    final localBaseUrl = 'http://127.0.0.1:18789';
    final localResolvedUrl = _resolveBaseUrl(localBaseUrl);
    final localModel = await _defaultModelFor('local');
    final localProfile = await ProviderProfileStore.instance.getProfile(
      'local',
      localModel,
    );

    // 複製 apiData 並切換到本地模型
    final fallbackApiData = Map<String, dynamic>.from(apiData);
    fallbackApiData['model'] = localModel;

    // 在 messages 的 system prompt 注入提醒訊息
    final messages = fallbackApiData['messages'] as List;
    if (messages.isNotEmpty && messages[0] is Map<String, dynamic>) {
      final systemMsg = messages[0] as Map<String, dynamic>;
      if (systemMsg['role'] == 'system') {
        systemMsg['content'] = '${systemMsg['content']}$_localFallbackWarning';
      }
    }

    debugPrint(
      '[ApiService] fallback: provider=$originalProvider → local, '
      'model=$localModel, url=$localResolvedUrl',
    );

    return _streamChatCompletion(
      resolvedUrl: localResolvedUrl,
      token: 'ollama',
      apiData: fallbackApiData,
      profile: localProfile,
    );
  }

  /// [2026-07-19] Streaming SSE 共用方法——對齊 Hermes conversation_loop.py:1262
  ///
  /// Hermes 註解：「Streaming gives us fine-grained health checking
  /// (90s stale-stream detection, 60s read timeout) that the non-streaming
  /// path lacks. Without this, callers can hang indefinitely when the
  /// provider keeps the connection alive with SSE pings but never
  /// delivers a response.」
  ///
  /// complete() 和 completeWithMessages() 都走這條路。
  ///
  /// [2026-07-20] 加入 retry + jittered backoff——移植 Hermes retry_utils.py
  /// 可重試：5xx、429（含 Z.AI GLM-5.2 overload 特殊 backoff）、connection error、stale timeout
  /// 不可重試：400/401/403
  static Future<String> _streamChatCompletion({
    required String resolvedUrl,
    required String token,
    required Map<String, dynamic> apiData,
    required ProviderProfile profile,
  }) async {
    final model = (apiData['model'] as String?) ?? 'unknown';
    // [教練 Agent 2026-07-30] kimi-k3 是 reasoning model，每次請求慢。
    // 429 時不要重試太多次——3 次嘗試已足夠，退避太久會讓對話卡 7 分鐘。
    // 其他 model 保持原來的 3 次 retry（共 4 次嘗試）。
    final maxRetries = model.toLowerCase().contains('kimi') ? 2 : 3;
    final zaiCeiling = zaiCodingOverloadRetryCeiling();
    final effectiveMaxRetries = math.max(maxRetries, zaiCeiling);

    for (int attempt = 0; attempt <= effectiveMaxRetries; attempt++) {
      try {
        return await _doStreamRequest(
          resolvedUrl: resolvedUrl,
          token: token,
          apiData: apiData,
          profile: profile,
        );
      } catch (e) {
        // 最後一次嘗試 → 直接丟出
        if (attempt == effectiveMaxRetries) {
          debugPrint('[ApiService] retry 累計 $attempt 次仍失敗，放棄: $e');
          rethrow;
        }

        // 解析錯誤資訊
        int? statusCode;
        String errorBody = '';
        if (e is DioException) {
          statusCode = e.response?.statusCode;
          errorBody = e.response?.data?.toString() ?? e.message ?? '';
        }

        // 判斷是否可重試
        // [2026-07-20] Vision 模型 timeout 不重試——glm-4.6v timeout 是模型太慢不是暫時錯誤，
        // 重試只會浪費另一個 90s。AgentLoop 的 eviction 機制會接手處理。
        final isVisionTimeout =
            e.toString().contains('TimeoutException') &&
            (model.contains('4.6v') ||
                model.contains('vision') ||
                model.contains('vl'));
        if (isVisionTimeout) {
          debugPrint('[ApiService] Vision 模型 timeout 不重試 ($model): $e');
          rethrow;
        }

        // [小葵 2026-09-19 小橋復活手術] temperature unsupported_value →
        // 部分 reasoning/相容層模型只支援預設 temperature，帶 0.3 整包 400。
        // 偵測到就標記模型 + 從本次請求剔除，立即重試（不浪費 retry 名額）。
        final errFullText = errorBody.isNotEmpty ? errorBody : e.toString();
        if (errFullText.contains('unsupported_value') &&
            errFullText.contains('temperature')) {
          debugPrint(
              '[ApiService] temperature 不支援 ($model)——剔除後重試');
          ProviderProfile.markTemperatureUnsupported(model);
          apiData.remove('temperature');
          continue;
        }

        if (!isRetryableError(statusCode, e)) {
          // [教練 Agent 2026-07-31] 模型不存在 (404) → 自動修復並重試
          if (statusCode == 404 ||
              e.toString().contains('404') ||
              errorBody.contains('not_found') ||
              errorBody.contains('no longer available')) {
            debugPrint(
              '[ApiService] _streamChatCompletion: 偵測到 404，嘗試 autoHealModel...',
            );
            final provider = apiData['_provider'] as String? ?? '';
            final healed = await autoHealModel(
              provider: provider,
              baseUrl: resolvedUrl,
              token: token,
              failedModel: model,
            );
            if (healed != null) {
              debugPrint(
                '[ApiService] _streamChatCompletion: 用修復後的模型 $healed 重試',
              );
              final healedApiData = Map<String, dynamic>.from(apiData);
              healedApiData['model'] = healed;
              return await _doStreamRequest(
                resolvedUrl: resolvedUrl,
                token: token,
                apiData: healedApiData,
                profile: profile,
              );
            }
          }
          debugPrint('[ApiService] 不可重試的錯誤 ($statusCode): $e');
          rethrow;
        }

        // 計算 backoff
        final isOverload = isZaiCodingOverloadError(
          baseUrl: resolvedUrl,
          model: model,
          statusCode: statusCode ?? 0,
          errorBody: errorBody,
        );

        final backoffResult = adaptiveRateLimitBackoff(
          baseUrl: resolvedUrl,
          model: model,
          statusCode: statusCode ?? 0,
          errorBody: errorBody,
          attempt: attempt + 1,
          defaultWait: jitteredBackoff(attempt + 1),
        );

        final delaySeconds = backoffResult.delay;
        final reason =
            backoffResult.reason ?? (isOverload ? 'overload' : 'transient');

        debugPrint(
          '[ApiService] retry ${attempt + 1}/$effectiveMaxRetries '
          '(${reason}, ${delaySeconds.toStringAsFixed(1)}s): $e',
        );

        await Future.delayed(
          Duration(milliseconds: (delaySeconds * 1000).toInt()),
        );
      }
    }

    // 不應該走到這裡
    throw Exception('retry loop exhausted');
  }

  /// 實際的 streaming 請求——被 _streamChatCompletion 的 retry loop 包住
  static Future<String> _doStreamRequest({
    required String resolvedUrl,
    required String token,
    required Map<String, dynamic> apiData,
    required ProviderProfile profile,
  }) async {
    // [教練 Agent 2026-07-30] 修復：移除自訂欄位 _provider，不能送進 HTTP request body
    // OpenAI/Kimi 會回 400 "Unknown parameter: '_provider'"
    // 保留在 apiData 供 _streamChatCompletion 的 usage tracker 讀取，送出前才移除
    final httpRequestData = Map<String, dynamic>.from(apiData)
      ..remove('_provider');
    // [小葵 2026-09-21 收尾驗收] 攔 usage 真值——stream_options.include_usage
    // 讓 provider 在最後一個 chunk 回真實 token 數（OpenAI 相容介面支援）。
    // 舊路徑只能 chars÷4 估算，中文低估 2-6 倍，不能當測試依據。
    // 保守送法：只在請求沒設過 stream_options 時補上（不覆寫既有設定）。
    httpRequestData['stream_options'] ??= {'include_usage': true};
    final response = await _dio.post(
      '$resolvedUrl/chat/completions',
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: ResponseType.stream,
      ),
      data: httpRequestData, // [教練 Agent 2026-07-30] 用移除 _provider 後的 data
    );

    final stream = response.data.stream as Stream<List<int>>;
    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    final lineBuf = StringBuffer();

    // [教練 Agent 2026-07-19] 用 utf8.decoder stream transformer 處理 chunk 邊界
    // 逐 chunk utf8.decode 會在中文多位元組中間斷裂（FormatException）
    // transformer 讓 decoder 跨 chunk 累積未完成的 byte sequence
    // 注意：Dio stream 是 Stream<Uint8List>，要 cast 成 Stream<List<int>> 才能配 utf8.decoder
    final decodedStream = stream.cast<List<int>>().transform(utf8.decoder);

    // [2026-07-20] Stale-stream detection — 對齊 Hermes reasoning_timeouts.py
    // stream 開了但 N 秒沒新 chunk（SSE ping 保活但不吐 data）→ TimeoutException
    // 這是 streaming 模式下的「活 timeout」：每收到一個 chunk 就重置計時器
    // 舊的 Future.timeout(90s) 在 streaming 模式下是 dead code（Future 在連線建立時就 complete）
    // Hermes 預設 180s，原生 Agent先用 90s（GLM-5.2 正常 token 間隔遠小於此）
    // [教練 Agent 2026-07-21] 本地模型 prompt processing 可能需要 200s+（46K tokens）
    // 用 300s 給本地模型足夠時間
    final streamTimeout = (await StorageService.getProvider() ?? '') == 'local'
        ? const Duration(seconds: 300)
        : const Duration(seconds: 90);
    await for (final decoded in decodedStream.timeout(streamTimeout)) {
      lineBuf.write(decoded);

      // SSE 以 \n\n 分隔 event，以 \n 分隔 line
      final raw = lineBuf.toString();
      final events = raw.split('\n\n');
      // 最後一段可能不完整，保留
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
            // [小葵 2026-09-21 收尾驗收] 攔 usage 真值——帶 include_usage
            // 時 provider 會在最後 chunk 回 usage（choices 為空陣列，
            // 舊代碼會 continue 掉——先撈再放行）
            final usage = json['usage'] as Map<String, dynamic>?;
            if (usage != null) {
              final pt = usage['prompt_tokens'] as int?;
              final ct = usage['completion_tokens'] as int?;
              if (pt != null && ct != null && (pt > 0 || ct > 0)) {
                _lastStreamUsage =
                    RealStreamUsage(promptTokens: pt, completionTokens: ct);
              }
            }
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
            debugPrint('[ApiService] SSE parse skip: $e');
          }
        }
      }
    }

    final content = contentBuf.toString();

    // [小葵 2026-09-21 收尾驗收] 真值優先記帳——有攔到 usage 用真值並標
    // estimated=false；沒有才退回 chars÷4 估算（中文低估但同方向）。
    if (content.isNotEmpty || reasoningBuf.isNotEmpty) {
      final modelName = apiData['model']?.toString() ?? 'unknown';
      final providerName = apiData['_provider']?.toString() ??
          (_isLocalModel(modelName) ? 'local' : 'cloud');
      final isLocal = _isLocalModel(modelName) || providerName == 'local';
      final real = _lastStreamUsage;
      _lastStreamUsage = null; // 用後即清，不跨請求污染
      if (real != null) {
        ApiUsageTracker.instance.recordUsage(
          inputTokens: real.promptTokens,
          outputTokens: real.completionTokens,
          model: modelName,
          provider: isLocal ? 'local' : providerName,
          estimated: false,
        );
      } else {
        final estimatedInputTokens =
            (apiData['messages'] as List? ?? []).fold(
              0,
              (sum, msg) => sum + (msg['content']?.toString().length ?? 0),
            ) ~/
            4;
        final estimatedOutputTokens =
            (content.length + reasoningBuf.length) ~/ 4;
        ApiUsageTracker.instance.recordUsage(
          inputTokens: estimatedInputTokens,
          outputTokens: estimatedOutputTokens,
          model: modelName,
          provider: isLocal ? 'local' : providerName,
        );
      }
    }

    if (content.isNotEmpty) return content;

    // [小葵 2026-10-01 Blue 令] 本地 reasoning fallback——content 空但
    // reasoning 有料時，退回 reasoning 文字（寧可給思考過程也不給空）。
    // 適用：enable_thinking 未生效的本地模型／模板不支援 kwargs 的引擎。
    // reasoning 裡通常已含完整回答，剝 <think> 標籤後即為可用文字。
    final reasoning = reasoningBuf.toString();
    if (reasoning.isNotEmpty) {
      final cleaned = reasoning
          .replaceAll(RegExp(r'<think>|</think>', caseSensitive: false), '')
          .trim();
      if (cleaned.isNotEmpty) return cleaned;
    }

    if (profile.supportsReasoningContent) {
      if (reasoning.isNotEmpty) return reasoning;
    }

    return '';
  }

  /// [小葵 2026-09-20] 判斷是否為本地模型
  static bool _isLocalModel(String model) {
    final lower = model.toLowerCase();
    return lower.contains('gemma') ||
        lower.contains('local') ||
        lower.contains('18789') ||
        lower.contains('ollama');
  }

  /// [2026-07-18] multimodal vision API — 送完整 messages array
  ///
  /// 支援 OpenAI vision 格式的 image_url content block。
  /// 當 AgentLoop 的 messages 含圖片（screen_capture 截圖）時走此路徑。
  /// messages 格式：[{role, content}] 其中 content 可以是 String 或 List<Map>
  /// List 格式：[{type: 'text', text: '...'}, {type: 'image_url', image_url: {url: 'data:...'}}]
  static Future<String> completeWithMessages({
    required List<Map<String, dynamic>> messages,
    String? model,
  }) async {
    final baseUrl = await _getBaseUrl();
    final token = await _getToken();

    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('Gateway URL 未設定');
    }

    // [教練 Agent 2026-07-29] 聊天對話優先使用使用者選的 provider，
    // 不讀 ProviderRouter 路由結果（路由結果僅供 Agent Loop 使用）
    final provider = await _effectiveProvider();
    final isLocalModel =
        provider == 'local' ||
        baseUrl.toLowerCase().contains('127.0.0.1') ||
        baseUrl.toLowerCase().contains('localhost') ||
        baseUrl.toLowerCase().contains('18789') ||
        baseUrl.toLowerCase().contains('11434') ||
        baseUrl.toLowerCase().contains('ollama') ||
        baseUrl.toLowerCase().contains('192.168.') ||
        baseUrl.toLowerCase().contains('10.');
    final effectiveToken = (token == null || token.isEmpty)
        ? (isLocalModel ? 'ollama' : token)
        : token;
    if (effectiveToken == null || effectiveToken.isEmpty) {
      throw Exception('API Token 未設定');
    }

    final selectedModel = model ?? await _defaultModelFor(provider);
    final resolvedUrl = _resolveBaseUrl(baseUrl);

    final profile = await ProviderProfileStore.instance.getProfile(
      provider,
      selectedModel,
    );

    // [2026-07-18] Vision fallback：如果主模型不支援 image_url 但有 visionModel，
    // 且 messages 含圖片，自動切換到 vision 模型
    //
    // [2026-07-19 修復] hasImages 判斷從「content is List」改為「content 含 image_url part」
    // 根因：截圖 eviction 後 content 仍是 List（只含 text parts），
    // 但舊邏輯只要 content 是 List 就判定有圖片 → 永遠走 vision fallback。
    // 正確判斷：檢查 List 裡有沒有 type='image_url' 的 part。
    final hasImages = messages.any((m) {
      final content = m['content'];
      if (content is List) {
        return content.any(
          (part) => part is Map<String, dynamic> && part['type'] == 'image_url',
        );
      }
      return false;
    });
    String effectiveModel = selectedModel;
    if (hasImages && profile.visionModel != null) {
      effectiveModel = profile.visionModel!;
      debugPrint(
        '[ApiService] Vision fallback: $selectedModel → $effectiveModel',
      );
    }

    final apiData = <String, dynamic>{
      'model': effectiveModel,
      'messages': messages,
      'stream': true, // [教練 Agent 2026-07-19] 對齊 Hermes：永遠走 streaming
      '_provider': provider, // [教練 Agent 2026-07-29] 記錄用於 ApiUsageTracker
      // [小葵 2026-10-01 Blue 令] 本地模型關思考——AgentLoop 路徑漏了這刀。
      // 病例：本地 gemma 生成 345 tokens 全進 reasoning_content、content 空
      // → AgentLoop 收到空字串 → 誠實報錯（但明明模型有想有講）。
      // sendMessage 路徑早有此修復（07-22），completeWithMessages 漏接。
      if (isLocalModel)
        'chat_template_kwargs': {'enable_thinking': false},
    };
    // [教練 Agent 2026-07-30 v2] 注入 apiParams（已過濾掉 max_tokens / max_completion_tokens）
    apiData.addAll(profile.apiParamsForHttp);

    debugPrint(
      '[ApiService] completeWithMessages: ${messages.length} messages, '
      'model=$effectiveModel, multimodal=$hasImages, stream=true, '
      'apiParams=${profile.apiParams}',
    );

    // [2026-07-27] 修復：必須 await 才能讓 try/catch 捕獲 streaming 中的 429/401
    // 同 complete() 的修復——_streamChatCompletion 內部用 await for 消耗 stream，
    // 錯誤是在 stream 消費期間非同步拋出，沒有 await 的話 try/catch 捕不到。
    try {
      return await _streamChatCompletion(
        resolvedUrl: resolvedUrl,
        token: effectiveToken,
        apiData: apiData,
        profile: profile,
      );
    } catch (e) {
      // [2026-07-29] 精確錯誤處理：同 complete() 的策略——
      // 只對 timeout/connection 暫時性錯誤 fallback 本地，
      // 401/429/quota 等確定性錯誤用人話訊息 throw 給上層。
      final category = classifyApiError(e);
      if (!isLocalModel && _isTransientFallbackWorthy(e)) {
        debugPrint(
          '[ApiService] ⚠️ 外部 API 暫時無法連線 ($category)，切換本地模型 (completeWithMessages)',
        );
        final localResult = await _callLocalModelWithFallback(
          apiData: apiData,
          originalProvider: provider,
        );
        return '$localResult$_localFallbackWarning';
      }
      throw await _wrapApiError(e, category);
    }
  }

  /// [小葵 2026-09-20 cache 工程解耦] 多輪裸送——只修 cache 前綴穩定性，
  /// 不收 usage、不過帳（計程車表暫不上）。
  ///
  /// 存在理由：cache 命中率的關鍵在「真多輪 messages array」——
  /// 每輪只在尾部 append 新訊息，system prompt 與舊對話是穩定 prefix，
  /// provider 端 prompt cache 才有機會命中。舊路徑把整串歷史壓扁成
  /// 單條 user message 重送（production_agent_loop_llm_client.dart），
  /// 格式重組+中途截斷會反覆破壞 prefix——9/19 astra cache writes $35 元兇。
  ///
  /// 與計程車表的關係：本路徑不返回 receipt（純字串），因此計程車表
  /// 暫時無法介入。計程車表復活（未來 L3 自我校準上線）時再串接。
  static Future<String> completeWithMessagesRaw({
    required List<Map<String, dynamic>> messages,
    String? model,
  }) async {
    final baseUrl = await _getBaseUrl();
    final token = await _getToken();

    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('Gateway URL 未設定');
    }

    final provider = await _effectiveProvider();
    final isLocalModel = provider == 'local' ||
        baseUrl.toLowerCase().contains('127.0.0.1') ||
        baseUrl.toLowerCase().contains('localhost') ||
        baseUrl.toLowerCase().contains('18789') ||
        baseUrl.toLowerCase().contains('11434') ||
        baseUrl.toLowerCase().contains('ollama') ||
        baseUrl.toLowerCase().contains('192.168.') ||
        baseUrl.toLowerCase().contains('10.');
    final effectiveToken = (token == null || token.isEmpty)
        ? (isLocalModel ? 'ollama' : token)
        : token;
    if (effectiveToken == null || effectiveToken.isEmpty) {
      throw Exception('API Token 未設定');
    }

    final selectedModel = model ?? await _defaultModelFor(provider);
    final resolvedUrl = _resolveBaseUrl(baseUrl);
    final profile = await ProviderProfileStore.instance.getProfile(
      provider,
      selectedModel,
    );

    final apiData = <String, dynamic>{
      'model': selectedModel,
      'messages': messages,
      'stream': true,
      '_provider': provider,
    };
    apiData.addAll(profile.apiParamsForHttp);

    try {
      return await _streamChatCompletion(
        resolvedUrl: resolvedUrl,
        token: effectiveToken,
        apiData: apiData,
        profile: profile,
      );
    } catch (e) {
      // [小葵 2026-10-05 修] MiniMax-M3 1210 暫態——「该模型始终思考，
      // 不支持关闭思考」。服務端偶發拒絕 thinking:disabled（同參數下一分鐘
      // 又收，實測重現不了=服務端灰度）。modelFollowUser 原則：參數只減法——
      // 去掉 thinking 同模型重試，絕不換模型。
      if (apiData.containsKey('thinking') && _isThinkingParamError(e)) {
        debugPrint('[ApiService] thinking 參數被拒（1210 類）→ 移除 thinking 同模型重試');
        final retryData = Map<String, dynamic>.from(apiData)..remove('thinking');
        try {
          return await _streamChatCompletion(
            resolvedUrl: resolvedUrl,
            token: effectiveToken,
            apiData: retryData,
            profile: profile,
          );
        } catch (_) {
          // 重試也失敗——走原本錯誤處理（不吞錯）
        }
      }
      final category = classifyApiError(e);
      if (!isLocalModel && _isTransientFallbackWorthy(e)) {
        final localResult = await _callLocalModelWithFallback(
          apiData: apiData,
          originalProvider: provider,
        );
        return '$localResult$_localFallbackWarning';
      }
      throw await _wrapApiError(e, category);
    }
  }

  /// [小葵 2026-10-05 修] 偵測「thinking 參數不被模型接受」的錯誤
  /// （MiniMax 1210「该模型始终思考」、GLM/Kimi 類似語意）
  static bool _isThinkingParamError(Object e) {
    final msg = e.toString();
    final body = e is DioException ? (e.response?.data?.toString() ?? '') : '';
    final hay = '$msg $body'.toLowerCase();
    if (hay.contains('1210') ||
        hay.contains('始终思考') ||
        hay.contains('不支持关闭思考') ||
        hay.contains('不支持关闭') ||
        hay.contains('invalid thinking.type')) {
      return true;
    }
    return hay.contains('thinking') && hay.contains('not supported');
  }

  /// [教練 Agent 2026-07-30] 公開版預設模型查詢——同步版本，只有 fallback
  ///
  /// 動態版本請用 ProviderRegistry.instance.selectBestModel()。
  /// 此方法保留給不能 await 的呼叫端作為最終 fallback。
  static String defaultModelFor(String provider) =>
      _legacyFallbackModel(provider);

  /// [教練 Agent 2026-07-30] 舊版硬編碼 brand→model 映射——保留為 private fallback
  ///
  /// 只有在 ProviderRegistry 動態探測失敗時才會用到。
  static String _legacyFallbackModel(String provider) {
    // 測試基準報告見 docs/provider_benchmark_report.md
    switch (provider) {
      case 'openai':
        return 'gpt-5.4'; // Tier 1：完整多步驟工具使用（07-18 升級，表現天差地別）
      case 'claude':
        return 'claude-sonnet-4-6';
      case 'gemini':
        return 'gemini-3.5-flash';
      case 'minimax':
        return 'MiniMax-M2.5';
      case 'local':
        // [小葵 2026-10-01 模型鐵則正名] 機器上沒有 llama3.1:8b——舊值是
        // 謊報（llama-server 不看 model 名，服務當前載入的模型，但 meta
        // 帳本全記錯人）。本地 fallback 一律回報「實際載入」的模型。
        return activeLocalModelName();
      case 'glm':
        return 'glm-5.2'; // Tier 1：reasoning 模型，農場任務驗證OK（07-18）
      case 'kimi':
      default:
        return 'kimi-k3'; // Tier 2：需拆分小任務
    }
  }

  /// [小葵 2026-10-01] 本地實際載入模型名——真相源 LocalRuntime/runtime-state.json
  /// （activeModelName，如 "gemma-4-12b-it-Q4_K_M"）。讀不到退 'local-model'。
  /// 同步讀檔（小 JSON）＋ 10 秒記憶體快取——避免每輪 LLM 呼叫都打磁碟。
  static String? _activeLocalModelCache;
  static DateTime _activeLocalModelCacheAt = DateTime(2000);
  static String activeLocalModelName() {
    try {
      final now = DateTime.now();
      if (_activeLocalModelCache != null &&
          now.difference(_activeLocalModelCacheAt).inSeconds < 10) {
        return _activeLocalModelCache!;
      }
      final home = io.Platform.environment['HOME'] ?? '';
      if (home.isEmpty) return 'local-model';
      final f = io.File(
          '$home/Library/Application Support/Bridge/LocalRuntime/runtime-state.json');
      if (!f.existsSync()) return 'local-model';
      final json = jsonDecode(f.readAsStringSync());
      final name = (json['activeModelName'] ?? '').toString();
      final result = name.isNotEmpty ? name : 'local-model';
      _activeLocalModelCache = result;
      _activeLocalModelCacheAt = now;
      return result;
    } catch (_) {
      return 'local-model';
    }
  }

  static Future<String> _defaultModelFor(String provider) async {
    // [教練 Agent 2026-07-31] 優先讀使用者已儲存的模型（自動修復後會更新此值）
    final storedModel = await StorageService.getApiModel(provider: provider);
    if (storedModel != null && storedModel.trim().isNotEmpty) {
      return storedModel.trim();
    }

    if (provider == 'local') {
      final localModel = await StorageService.getLocalModelName();
      if (localModel != null && localModel.trim().isNotEmpty) {
        return localModel.trim();
      }
      return _legacyFallbackModel('local');
    }
    // [教練 Agent 2026-07-30] 'default' 預設選型——用路由結果的 provider
    if (provider == 'default') {
      final routedProvider =
          ProviderRouter.instance.current?.providerId ?? 'openai';
      if (routedProvider == 'local') {
        final localModel = await StorageService.getLocalModelName();
        return localModel?.trim().isNotEmpty == true
            ? localModel!.trim()
            : _legacyFallbackModel('local');
      }
      final model = await ProviderRegistry.instance.selectBestModel(
        routedProvider,
      );
      return model ?? _legacyFallbackModel(routedProvider);
    }
    // [教練 Agent 2026-07-30] 委派 ProviderRegistry——動態選最佳模型
    final model = await ProviderRegistry.instance.selectBestModel(provider);
    if (model != null) return model;
    // 最終 fallback——用舊版硬編碼
    return _legacyFallbackModel(provider);
  }

  /// [教練 Agent 2026-07-31] 從可用模型列表中挑選最佳模型
  /// 過濾掉非 chat 模型（embedding、image、tts 等），優先選能力強的
  static String? pickBestModel(String provider, List<String> models) {
    if (models.isEmpty) return null;

    // 過濾掉非 chat/completion 模型
    final chatModels = models.where((m) {
      final lower = m.toLowerCase();
      if (lower.contains('embedding')) return false;
      if (lower.contains('tts')) return false;
      if (lower.contains('whisper')) return false;
      if (lower.contains('moderation')) return false;
      if (lower.contains('davinci')) return false;
      if (lower.contains('babbage')) return false;
      if (lower.contains('imagen')) return false;
      if (lower.contains('veo')) return false;
      if (lower.contains('lyria')) return false;
      if (lower.contains('aqa')) return false;
      if (lower.contains('computer-use')) return false;
      if (lower.contains('robotics')) return false;
      if (lower.contains('live')) return false;
      if (lower.contains('deep-research')) return false;
      if (lower.contains('antigravity')) return false;
      return true;
    }).toList();

    if (chatModels.isEmpty) return models.first;

    switch (provider) {
      case 'gemini':
        for (final preferred in [
          'gemini-3.5-flash',
          'gemini-3.1-flash',
          'gemini-3.1-flash-lite',
          'gemini-2.5-flash',
        ]) {
          if (chatModels.contains(preferred)) return preferred;
        }
        final flashes = chatModels
            .where((m) => m.contains('flash') && m.startsWith('gemini'))
            .toList();
        if (flashes.isNotEmpty) return flashes.first;
        final geminis = chatModels
            .where((m) => m.startsWith('gemini') && !m.contains('gemma'))
            .toList();
        if (geminis.isNotEmpty) return geminis.first;
        break;

      case 'claude':
        for (final preferred in [
          'claude-sonnet-4-6',
          'claude-haiku-4-5',
          'claude-sonnet-4-5',
        ]) {
          if (chatModels.contains(preferred)) return preferred;
        }
        final claudes = chatModels
            .where((m) => m.startsWith('claude'))
            .toList();
        if (claudes.isNotEmpty) return claudes.first;
        break;

      case 'openai':
        for (final preferred in ['gpt-5.4', 'gpt-5', 'gpt-4o', 'gpt-4o-mini']) {
          if (chatModels.contains(preferred)) return preferred;
        }
        final gpts = chatModels.where((m) => m.startsWith('gpt')).toList();
        if (gpts.isNotEmpty) return gpts.first;
        break;

      case 'glm':
        // [教練 Agent 2026-08-17] 5.3 上線後優先序更新（使用者 升級指示）。
        // 此清單同時是 refreshProviderModel/autoHealModel 的「自動修復」
        // 目標——之前首選 5.2，會把使用者選的 5.3「修」回 5.2。
        for (final preferred in [
          'glm-5.3',
          'glm-5.2',
          'glm-5',
          'glm-5-turbo',
          'glm-4.7',
          'glm-4.6',
          'glm-4.5',
        ]) {
          if (chatModels.contains(preferred)) return preferred;
        }
        final glms = chatModels.where((m) => m.startsWith('glm')).toList();
        if (glms.isNotEmpty) return glms.first;
        break;

      case 'kimi':
        for (final preferred in ['kimi-k3', 'kimi-k2.5', 'kimi-k2.6']) {
          if (chatModels.contains(preferred)) return preferred;
        }
        final kimis = chatModels.where((m) => m.startsWith('kimi')).toList();
        if (kimis.isNotEmpty) return kimis.first;
        break;

      case 'minimax':
        for (final preferred in ['MiniMax-M2.5', 'minimax-m2.5']) {
          if (chatModels.contains(preferred)) return preferred;
        }
        final mms = chatModels
            .where((m) => m.toLowerCase().contains('minimax'))
            .toList();
        if (mms.isNotEmpty) return mms.first;
        break;
    }

    return chatModels.first;
  }

  /// [教練 Agent 2026-07-31] 為沒有 /models endpoint 的 provider 取得 fallback 模型列表
  static List<String> fallbackModelList(String provider) {
    switch (provider) {
      case 'claude':
        return ['claude-sonnet-4-6', 'claude-haiku-4-5', 'claude-opus-4-8'];
      case 'gemini':
        return [
          'gemini-3.5-flash',
          'gemini-3.1-flash',
          'gemini-3.1-flash-lite',
        ];
      default:
        return [];
    }
  }

  /// [教練 Agent 2026-07-31] 啟動時自動刷新已鎖定 provider 的模型
  /// 回傳 true 表示模型有更新
  static Future<bool> refreshProviderModel({
    required String provider,
    required String baseUrl,
    required String token,
  }) async {
    try {
      var models = await testConnectionWith(baseUrl, token);
      if (models.isEmpty) {
        models = fallbackModelList(provider);
      }
      if (models.isEmpty) return false;

      final best = pickBestModel(provider, models);
      if (best == null) return false;

      // [教練 Agent 2026-08-17 使用者 指示] 尊重使用者已選的模型——
      // 啟動刷新只在「沒有已存模型」或「已存模型已下架」時才覆寫。
      // 之前無條件把使用者選的模型「修」成偏好清單首選
      //（5.3 被改回 5.2 的元兇）。
      final current = await StorageService.getApiModel(provider: provider);
      if (current != null && current.isNotEmpty && models.contains(current)) {
        // 使用者的選擇仍在清單中 → 不動
        return false;
      }
      if (current != best) {
        debugPrint(
          '[ApiService] refreshProviderModel: $provider $current → $best '
          '（原模型不在清單或未設定）',
        );
        await StorageService.saveApiModel(best, provider: provider);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[ApiService] refreshProviderModel: $provider 刷新失敗: $e');
      return false;
    }
  }

  /// [教練 Agent 2026-07-31] 自動修復模型：如果當前模型失敗（404），
  /// 自動拉取可用模型列表，挑選最佳替代，儲存並回傳。
  /// 回傳 null 表示無需修復或修復失敗。
  static Future<String?> autoHealModel({
    required String provider,
    required String baseUrl,
    required String token,
    required String failedModel,
  }) async {
    debugPrint(
      '[ApiService] autoHealModel: $provider 的 $failedModel 失敗，嘗試自動修復...',
    );
    try {
      var models = await testConnectionWith(baseUrl, token);

      // 如果 /models 失敗（如 Claude），用 fallback 列表
      if (models.isEmpty) {
        models = fallbackModelList(provider);
      }
      if (models.isEmpty) {
        debugPrint('[ApiService] autoHealModel: 無法取得模型列表，用 hardcoded fallback');
        final fallback = _legacyFallbackModel(provider);
        if (fallback != failedModel) {
          await StorageService.saveApiModel(fallback, provider: provider);
          return fallback;
        }
        return null;
      }

      final best = pickBestModel(provider, models);
      if (best != null && best != failedModel) {
        debugPrint('[ApiService] autoHealModel: $failedModel → $best');
        await StorageService.saveApiModel(best, provider: provider);
        return best;
      }
    } catch (e) {
      debugPrint('[ApiService] autoHealModel 例外: $e');
    }
    return null;
  }

  static String _buildBridgeCapabilities() {
    return '\n\n'
        '【你是橋樑——連接各種能力的入口】\n\n'
        '你不只是聊天，你是一座橋，連接用戶與各種 AI 能力。\n\n'
        '當用戶需要時，你可以：\n'
        '- 生成圖片：在回覆中插入標記 [GENERATE_IMAGE: 詳細描述]\n'
        '- 生成音樂：插入標記 [GENERATE_MUSIC: 風格描述]\n'
        '- 生成影片：插入標記 [GENERATE_VIDEO: 場景描述]\n'
        '- 瀏覽網頁：插入標記 [BROWSE: 網址或搜尋詞]\n'
        '- 產出文件：插入標記 [DOCUMENT: 文件類型|內容摘要]\n\n'
        '使用規則：\n'
        '1. 不要問用戶「要不要生成圖片」，直接在適當時候做\n'
        '2. 標記會被自動解析並執行，用戶看不到標記本身\n'
        '3. 生成後，在標記前後用自然語言描述生成的內容\n'
        '4. 如果一次需要多種能力，可以插入多個標記\n'
        '5. 如果能力尚未開通，不要假裝已經完成；請用使用者語言說明缺少哪一把金鑰或哪個桌面橋樑，並引導使用者前往「金鑰匙中心」或「第一次召喚／Bridge Desktop」完成開通。\n'
        '6. 查新聞、瀏覽網頁、讀取本機檔案與整理桌面，都需要 Bridge Desktop 或對應服務真正接上後才能執行。若尚未接上，請把需求整理成待開通任務，並告訴使用者下一步。\n\n'
        '7. 【初始設定引導】如果使用者還沒有設定任何 AI 服務金鑰，或者問你「怎麼開始」「怎麼設定」「需要什麼」，請引導他們完成初始設定：\n'
        '   - 推薦 MiniMax（https://platform.minimaxi.com/）— 有免費額度，台灣可直接註冊使用\n'
        '   - 其他選項：OpenAI（https://platform.openai.com/，功能最完整但需付費）、Kimi（https://platform.moonshot.cn/，中文能力強）、GLM（https://open.bigmodel.cn/，智譜 AI）\n'
        '   - 設定步驟：到「系統 → 設定」→ 選 provider → 貼上 API Key → 測試連線 → 存檔\n'
        '   - 你不碰使用者的金鑰內容，只引導他們自己去設定頁貼上\n'
        '   - 設定完成後，使用者回來跟你說一聲，你就可以正常運作\n\n'
        '8. 【資產發佈引導】當使用者想要「發佈資產」「上鏈」「分享工作流」「賣資產包」時，你需要引導他們完成進階設定：\n'
        '   - 上鏈需要兩把鑰匙：Pinata JWT（IPFS 存證用）+ Reown projectId（錢包連接用）\n'
        '   - Pinata：到 pinata.cloud 註冊（免費 1GB），取得 JWT → 在「設定 → 4. IPFS 存證」貼上\n'
        '   - 錢包：到 cloud.reown.com 註冊（免費），取得 projectId → 在「設定 → 5. 錢包連接」貼上 → 連接 MetaMask\n'
        '   - 下載/匯入資產不需要任何設定 — 只需公開 IPFS gateway 即可讀取\n'
        '   - 上鏈前需部署合約到 Base Sepolia 測試網（免費 testETH）\n'
        '   - 你不碰使用者的任何金鑰，只引導他們到設定頁自行操作\n\n'
        '範例：\n'
        '「我幫你畫了幾個參考圖：[GENERATE_IMAGE: 北歐風格客廳，淺灰色沙發，大窗戶，自然採光，溫暖木質地板，簡約設計]\n\n'
        '這個風格你覺得如何？如果需要調整顏色或擺設告訴我。」\n';
  }

  static String _buildActiveCompanionPrompt() {
    final companion = CompanionStore().activeCompanion;
    if (companion == null) return '';
    return '''
【目前啟用的替身夥伴】
${companion.systemPrompt}

這段設定優先於任何預設人格。你現在必須以「${companion.name}」的身份回答，使用他的語氣、專長、角色關係與長期設定。
如果使用者問「你是誰」，請回答你是「${companion.name}」——永遠以當前夥伴的名字自稱。
''';
  }

  /// 輕量單次 chat completion，給 CapabilityAdvisorService 等
  /// 內部流程使用。不帶記憶、不帶 persona、不帶 context compression。
  static Future<String> chatCompletion(
    String systemPrompt,
    String userPrompt, {
    String? model,
    double temperature = 0.3,
  }) async {
    final baseUrl = await _getBaseUrl();
    final token = await _getToken();
    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('Gateway URL 未設定');
    }
    final provider = await _effectiveProvider();
    // [以利沙 P1 修復二十一輪 2026-06-27] 本地模型豁免 token 檢查
    final isLocal =
        provider == 'local' ||
        baseUrl.toLowerCase().contains('127.0.0.1') ||
        baseUrl.toLowerCase().contains('localhost') ||
        baseUrl.toLowerCase().contains('18789') ||
        baseUrl.toLowerCase().contains('11434') ||
        baseUrl.toLowerCase().contains('ollama');
    if (token == null || token.isEmpty) {
      if (!isLocal) {
        throw Exception('API Token 未設定');
      }
    }
    final effectiveToken = (token == null || token.isEmpty)
        ? (isLocal ? 'ollama' : token!)
        : token;

    final selectedModel = model ?? await _defaultModelFor(provider);
    final resolvedUrl = _resolveBaseUrl(baseUrl);

    // [教練 Agent 2026-07-30] Kimi reasoning model 只接受 temperature=1 (int)
    final effectiveTemp = provider == 'kimi' ? 1 : temperature;
    final response = await _dio.post(
      '$resolvedUrl/chat/completions',
      options: Options(headers: {'Authorization': 'Bearer $effectiveToken'}),
      data: {
        'model': selectedModel,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': effectiveTemp,
        'stream': false,
      },
    );

    final content = ChatResponse.fromJson(response.data).cleanContent.trim();
    if (content.isEmpty) {
      throw Exception('AI 回應為空');
    }
    return content;
  }

  static String _buildProjectDoorPrompt(ProjectDoor? door) {
    if (door == null) return '';
    final questions = door.intakeQuestions
        .asMap()
        .entries
        .map((entry) => '${entry.key + 1}. ${entry.value}')
        .join('\n');
    final bridges = door.requiredBridges.join('、');
    return '''
【目前正在推進的專案門】
專案：${door.title}
目前水流：${door.currentFlow}
原始意圖：${door.sourceIntent}
可能需要的橋：$bridges

【顧問式推進規則】
你現在不是一般聊天回答器，而是陪使用者把模糊構想落地的 AI 顧問與專案夥伴。
你的核心任務是守住使用者的原始意圖，逐步把想法變成可執行專案。

請遵守：
1. 不要只列完整大綱後用「有需要告訴我」收尾。
2. 每一輪最多推進一個主問題；必要時附 2 到 3 個白話選項或例子，幫使用者容易回答。
3. 使用者如果說「開始」「第一步」「帶我做」，請進入問診，不要直接跳去開通單一能力。
4. 先釐清目標、產品/服務、受眾、成功標準、限制條件，再談能力橋與工具。
5. 不要使用讓一般使用者卡住的專業字，例如 KPI；若必須使用，先用白話解釋。
6. 回答最後必須落在一個清楚的下一步提問，讓使用者可以直接回答。
7. 如果使用者已經逐條回答了目標、產品/服務、受眾、成功標準、資源或限制，不要只是重述後問「合理嗎 / 正確嗎」。請把它整理成「專案設定稿」，指出最應先開始的一步，然後直接問那一步所需的下一個具體問題。
8. 只有當使用者回答互相矛盾、缺少關鍵資訊，或你真的不確定時，才請使用者確認；否則要往下一個水流推進。

目前這個專案門的待釐清問題：
$questions

建議回覆格式：
- 先用 1 到 2 句確認你理解的專案方向。
- 如果使用者還沒回答待釐清問題：告訴使用者「我們先釐清第一件事」，問一個具體問題。
- 如果使用者已經回答待釐清問題：整理成「目前專案設定」，接著說「我們從 X 開始」，並問下一個執行問題。
- 給簡短範例，例如「你可以回答：我想賣 A，客群是 B，第一版只要做到 C」。
''';
  }
}

/// [小葵 2026-09-20 計程車表暫不上]（待費率自我校準機制）
/// 此 class 保留為 9/20 設計錨點；目前無呼叫端。
/// 啟用條件：實作 L3 自我校準（從 OpenAI 帳單反推費率）後復活。
class StreamCompletionResult {
  final String content;
  final int? inputTokens;
  final int? outputTokens;
  final int? cachedInputTokens;

  const StreamCompletionResult({
    required this.content,
    this.inputTokens,
    this.outputTokens,
    this.cachedInputTokens,
  });
}

class ChatResponse {
  final String content;
  final int inputTokens;
  final int outputTokens;
  final String model;
  final List<BridgeAction> bridgeActions;
  final List<String> quickReplies; // [教練 Agent 2026-06-29] AI 提問時的快速選項

  ChatResponse({
    required this.content,
    required this.inputTokens,
    required this.outputTokens,
    required this.model,
    this.bridgeActions = const [],
    this.quickReplies = const [],
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    final choice = json['choices']?[0];
    final message = choice?['message'];
    final usage = json['usage'] ?? {};
    final content = message?['content']?.toString() ?? '（無回應）';

    final actions = _parseBridgeActions(content);
    final replies = _parseQuickReplies(content);

    return ChatResponse(
      content: content,
      inputTokens: usage['prompt_tokens'] ?? usage['input_tokens'] ?? 0,
      outputTokens: usage['completion_tokens'] ?? usage['output_tokens'] ?? 0,
      // [教練 Agent 2026-08-05] llama-server 的 OpenAI response 會把完整 GGUF 檔案路徑塞進 model 欄位
      // 用 resolveShortModelName 解析成 catalog 的短 id（例如 "gemma-4-e4b-q4"）
      // 這樣對話泡泡底下會顯示短名而不是整個路徑
      model: resolveShortModelName(json['model']?.toString()) ?? 'unknown',
      bridgeActions: actions,
      quickReplies: replies,
    );
  }

  static List<BridgeAction> _parseBridgeActions(String content) {
    final actions = <BridgeAction>[];
    for (final match in BridgeAction.tagPattern.allMatches(content)) {
      actions.add(BridgeAction.fromTagMatch(match));
    }
    return actions;
  }

  /// [教練 Agent 2026-06-29] 解析 [QUICK_REPLIES]opt1|opt2|opt3[/QUICK_REPLIES]
  static final _quickReplyPattern = RegExp(
    r'\[QUICK_REPLIES\](.*?)\[/QUICK_REPLIES\]',
    dotAll: true,
  );

  static List<String> _parseQuickReplies(String content) {
    final match = _quickReplyPattern.firstMatch(content);
    if (match == null) return const [];
    final raw = match.group(1)?.trim();
    if (raw == null || raw.isEmpty) return const [];
    final parts = raw
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.length > 4 ? parts.sublist(0, 4) : parts; // 最多 4 個
  }

  String get cleanContent {
    return content
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        .replaceAllMapped(BridgeAction.tagPattern, (match) => '')
        .replaceAll(_quickReplyPattern, '') // [教練 Agent 2026-06-29] 移除快速選項標記
        .trim();
  }

  int get totalTokens => inputTokens + outputTokens;
}
