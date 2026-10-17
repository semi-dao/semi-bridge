// smart_memory_extractor.dart
// LLM 語意記憶提取服務 — 在正則快車道之外的第二軌
// 建立日期: 2026-07-03 by 教練 Agent (CEO)
//
// 設計理念（使用者 2026-07-03）：
// 「記憶提取邏輯應該是要了解語意、瞭解使用者的意圖來決定儲存跟提取記憶，
//  不能只靠關鍵字，這樣點太不智慧了。」
//
// 雙軌架構：
// 1. 快車道（MemoryStore.extractFromMessage 的正則）— 處理「記住：」「我叫」等明確指令
// 2. 慢車道（本服務）— LLM 語意理解，抓隱含的、無前綴詞的記憶
//
// 慢車道特點：
// - 不阻塞對話（背景並行）
// - 用 app 現有 provider/token/model（不需新 API key）
// - 本地模型友善（Ollama 在本地跑，隱私零外洩）
// - 去重：與已提取記憶做 embedding 相似度比對
// - 失敗靜默（不影響主對話流程）

import 'dart:async';

import 'package:dio/dio.dart';

import '../../sovereignty/data_path_gate.dart';
import '../../sovereignty/data_path_interceptor.dart';
import 'package:flutter/foundation.dart';

import 'extraction_prompt.dart';
import 'memory_guard.dart';
import '../brain_container_service.dart';
import '../../memory_guard_service.dart';
import '../../../models/brain_container/memory_source.dart';
import '../../api_service.dart';
import '../../storage_service.dart';

/// 提取結果。
class ExtractionResult {
  final List<ExtractedFact> facts;
  final bool skipped;
  final String? error;

  const ExtractionResult({
    required this.facts,
    this.skipped = false,
    this.error,
  });

  bool get hasFacts => facts.isNotEmpty;
}

/// 智慧記憶提取服務（單例）。
///
/// 使用方式：
/// ```dart
/// final result = await SmartMemoryExtractor.instance.extract(userMessage);
/// // result.facts 包含 LLM 提取的記憶
/// // result.alreadyExtracted 是正則已抓到的（用於去重）
/// ```
class SmartMemoryExtractor {
  SmartMemoryExtractor._();
  static final SmartMemoryExtractor instance = SmartMemoryExtractor._();

  static final Dio _dio = _createDio();

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 120),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    // [資料主權 P0-b 2026-09-14] 記憶提取流量過 DataPathGate（text/memory_extract）
    dio.interceptors.add(SovereigntyInterceptor(
      dataClass: DataPathClass.text,
      purpose: DataPathPurpose.memoryExtract,
    ));
    return dio;
  }

  /// 去重閾值：cosine similarity > 此值則視為重複。
  static const double _dedupThreshold = 0.85;

  /// 單次提取最多保留幾筆（防止 LLM 過度提取）。
  static const int _maxFactsPerMessage = 5;

  /// 訊息最短長度（太短不值得送 LLM）。
  // P1 修復：8→4，允許「我叫建新」(4字) 等短身份宣告觸發 LLM 提取。
  // 1~3 字的訊息（「嗨」「好」）仍被攔截，不浪費 API token。
  static const int _minMessageLength = 4;

  /// 從使用者訊息中提取記憶。
  ///
  /// [userMessage] 使用者的原始訊息
  /// [alreadyExtracted] 正則快車道已提取的記憶（用於去重）
  ///
  /// 回傳提取結果。若訊息太短、API 不可用、或提取失敗，
  /// 回傳空結果（skipped=true 或 error 不為 null）。
  Future<ExtractionResult> extract({
    required String userMessage,
    List<String> alreadyExtracted = const [],
  }) async {
    // 1. 訊息太短 — 不值得送 LLM
    if (userMessage.trim().length < _minMessageLength) {
      return ExtractionResult(facts: [], skipped: true);
    }

    // [教練 Agent 2026-07-22] #4 L1: 黃燈時暫停 LLM 提取（省 RAM + API token）
    if (MemoryGuardService.instance.smartMemoryExtractionPaused) {
      return ExtractionResult(facts: [], skipped: true);
    }

    // 2. 取得 API 配置
    final config = await _getApiConfig();
    if (config == null) {
      return ExtractionResult(facts: [], skipped: true);
    }

    // 3. 呼叫 LLM 提取
    List<ExtractedFact> facts;
    try {
      facts = await _callLlm(userMessage, config);
    } catch (e) {
      debugPrint('[SmartMemoryExtractor] LLM 呼叫失敗: $e');
      return ExtractionResult(facts: [], error: e.toString());
    }

    if (facts.isEmpty) return ExtractionResult(facts: []);

    // 4. 限制數量
    if (facts.length > _maxFactsPerMessage) {
      facts = facts.sublist(0, _maxFactsPerMessage);
    }

    // 5. 去重 — 與正則已提取的記憶比對
    final filtered = await _deduplicate(facts, alreadyExtracted);

    debugPrint('[SmartMemoryExtractor] 提取 ${facts.length} 筆，去重後 ${filtered.length} 筆');
    return ExtractionResult(facts: filtered);
  }

  /// [小葵 2026-09-22 偷學令③ Dreaming] 批次抽取——多則訊息一起做夢。
  ///
  /// 與 extract() 同規格，但一次分析整批訊息：跨訊息的修正/補充/
  /// 因果（「我換手機了」推翻三則前的「我用 iPhone」）只有批次看
  /// 才抓得到。上限放寬：批次 5→12 筆（一次夢涵蓋整批）。
  Future<ExtractionResult> extractBatch({
    required List<String> messages,
    List<String> alreadyExtracted = const [],
  }) async {
    final valid = messages
        .where((m) => m.trim().length >= _minMessageLength)
        .toList();
    if (valid.isEmpty) {
      return ExtractionResult(facts: [], skipped: true);
    }

    if (MemoryGuardService.instance.smartMemoryExtractionPaused) {
      return ExtractionResult(facts: [], skipped: true);
    }

    final config = await _getApiConfig();
    if (config == null) {
      return ExtractionResult(facts: [], skipped: true);
    }

    List<ExtractedFact> facts;
    try {
      facts = await _callLlmBatch(valid, config);
    } catch (e) {
      debugPrint('[SmartMemoryExtractor] 批次做夢 LLM 失敗: $e');
      return ExtractionResult(facts: [], error: e.toString());
    }

    if (facts.isEmpty) return ExtractionResult(facts: []);

    const batchMax = 12;
    if (facts.length > batchMax) {
      facts = facts.sublist(0, batchMax);
    }

    final filtered = await _deduplicate(facts, alreadyExtracted);
    debugPrint('[SmartMemoryExtractor] 批次做夢: ${valid.length} 則訊息 → '
        '${facts.length} 筆，去重後 ${filtered.length} 筆');
    return ExtractionResult(facts: filtered);
  }

  /// 將提取的事實寫入大腦容器（含向量去重）。
  ///
  /// 這是 extract() 之後的第二步，分開是為了讓呼叫端可以
  /// 先決定是否真的要寫入（例如 UI 確認後才寫）。
  Future<List<ExtractedFact>> writeToBrainContainer({
    required List<ExtractedFact> facts,
    required String agent,
    String companionId = '',
  }) async {
    final brain = BrainContainerService.instance;
    if (!brain.isInitialized) return [];

    final written = <ExtractedFact>[];

    for (final fact in facts) {
      // Hermes 風格安全掃描 — 防止 LLM 提取到注入內容
      final guard = MemoryGuard.scan(fact.content);
      if (!guard.isSafe) {
        debugPrint('[MemoryGuard] 阻擋 LLM 提取: ${guard.reason} ← ${fact.content}');
        continue;
      }

      // 向量去重：檢查是否已有相似記憶
      if (brain.isModelAvailable) {
        final existing = await brain.retrieveMemories(
          query: fact.content,
          limit: 3,
        );
        final isDuplicate = existing.any(
          (r) => r.similarity >= _dedupThreshold,
        );
        if (isDuplicate) {
          debugPrint('[SmartMemoryExtractor] 跳過重複記憶: ${fact.content}');
          continue;
        }
      }

      // 寫入大腦容器
      final success = await brain.writeMemory(
        content: fact.content,
        agent: agent,
        companionId: companionId,
        source: MemorySource.chat,
        speaker: MemorySpeaker.user, // [出處戳] 慢車道提取自使用者訊息=使用者說的
        importance: fact.importance,
      );

      if (success) {
        written.add(fact);
        debugPrint('[SmartMemoryExtractor] 寫入: ${fact.content} (${fact.category}, imp=${fact.importance})');
      }
    }

    return written;
  }

  // ===== 內部方法 =====

  /// [小葵 2026-09-22 偷學令③] 批次 LLM 呼叫（做夢用）。
  Future<List<ExtractedFact>> _callLlmBatch(
    List<String> messages,
    _ApiConfig config,
  ) async {
    // 與 _callLlm 同款結構，只換 prompt
    final systemPrompt = ExtractionPrompt.buildSystemPrompt();
    final userPrompt = ExtractionPrompt.buildBatchUserPrompt(messages);

    final dio = Dio(BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Content-Type': 'application/json',
        if (config.token.isNotEmpty) 'Authorization': 'Bearer ${config.token}',
      },
    ));

    final resp = await dio.post(
      '/chat/completions',
      data: {
        'model': config.model,
        'temperature': 0.1,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      },
    );

    if (resp.statusCode != 200) {
      throw Exception('LLM 回應 ${resp.statusCode}');
    }
    final content =
        resp.data['choices'][0]['message']['content'] as String;
    return ExtractionPrompt.parseResponse(content);
  }

  /// 取得 API 配置。
  ///
  /// [教練 Agent 2026-07-30] 記憶提取是背景任務，不應搶主回覆的雲端 API 額度。
  /// 若本地 Ollama server 可用，優先用本地模型做記憶提取；
  /// 本地不可用才 fallback 到使用者的雲端 provider。
  Future<_ApiConfig?> _getApiConfig() async {
    // [教練 Agent 2026-07-30] 先檢查本地 Ollama server 是否可用（3 秒 timeout）
    final localAvailable = await _checkLocalServer();
    // [T7④ 2026-10-16 盲測 401 根治] localOnly（斷網血管）：
    // 本地不可用時直接放棄萃取（背景記憶可丟），絕不打雲。
    // 病例：E4B 推論佔滿 llama-server → /v1/models 3 秒 timeout →
    // fallback 打 gateway（z.ai）＋過期 openai token → 401 錯誤
    // 冒泡成主回覆（Q1/Q5/Q7/Q13 四題全滅的根因）。
    if (!localAvailable && await StorageService.getLocalOnly()) {
      debugPrint('[SmartMemoryExtractor] localOnly 且本地不可用——跳過萃取（不打雲）');
      return null;
    }
    if (localAvailable) {
      final localModel = await StorageService.getLocalModelName();
      debugPrint('[SmartMemoryExtractor] 使用本地模型做記憶提取: ${localModel ?? "llama3.1:8b"}');
      return _ApiConfig(
        baseUrl: 'http://127.0.0.1:18789/v1',
        token: 'ollama',
        model: (localModel != null && localModel.trim().isNotEmpty)
            ? localModel.trim()
            : 'llama3.1:8b',
        provider: 'local',
      );
    }

    // [教練 Agent 2026-07-30] 本地不可用——fallback 到原邏輯（使用者的雲端 provider）
    final baseUrl = await StorageService.getGatewayUrl();
    final token = await StorageService.getToken();
    final provider = await StorageService.getProvider() ?? 'openai';

    if (baseUrl == null || baseUrl.isEmpty) return null;
    if (token == null || token.isEmpty) {
      // 本地模型可能不需要 token
      if (provider != 'local') return null;
    }

    final model = await _resolveModel(provider);
    final resolvedUrl = _resolveBaseUrl(baseUrl, provider);

    return _ApiConfig(
      baseUrl: resolvedUrl,
      token: token?.isNotEmpty == true ? token! : 'ollama',
      model: model,
      provider: provider,
    );
  }

  /// [教練 Agent 2026-07-30] 檢查本地 Ollama server 是否可用。
  /// 送 GET /v1/models，3 秒 timeout——回傳 true 代表可用。
  /// [T7④ 2026-10-16 盲測 401 根治] 三處支援：
  /// ① 優先 local_model_endpoint（18789 llama-server——我們不是 Ollama）
  /// ② localOnly 模式：本地不可用直接 return null（斷網血管不打雲）
  static Future<bool> _checkLocalServer() async {
    try {
      final probeDio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 3),
      ));
      final resp = await probeDio.get('http://127.0.0.1:18789/v1/models');
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 解析模型名稱。
  Future<String> _resolveModel(String provider) async {
    if (provider == 'local') {
      final localModel = await StorageService.getLocalModelName();
      if (localModel != null && localModel.trim().isNotEmpty) {
        return localModel.trim();
      }
      return 'llama3.1:8b';
    }

    // 優先使用使用者實際配置的模型（與主對話相同），避免硬編碼模型名不存在導致 400
    // [教練 Agent修正 2026-07-19] 曾用 ApiService.currentModel 但該成員不存在，
    // 改用 ApiService.defaultModelFor(provider) — static 方法，回傳 provider 預設模型
    final activeModel = ApiService.defaultModelFor(provider);
    if (activeModel.trim().isNotEmpty) {
      return activeModel.trim();
    }

    const defaults = {
      'openai': 'gpt-4o-mini',
      'claude': 'claude-sonnet-4-6',
      'gemini': 'gemini-3.5-flash',
      'minimax': 'MiniMax-M2.5',
      'glm': 'glm-4-flash',
      'kimi': 'kimi-k2.6',
    };

    return defaults[provider] ?? 'gpt-4o-mini';
  }

  /// 統一處理 Base URL。
  String _resolveBaseUrl(String baseUrl, String provider) {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    // GLM 用 /v4，其他用 /v1；若已含版本路徑則不重複加
    if (RegExp(r'/v\d+$').hasMatch(url)) return url;
    if (provider == 'glm') return '$url/v4';
    return '$url/v1';
  }

  /// 呼叫 LLM 做記憶提取。
  Future<List<ExtractedFact>> _callLlm(
    String userMessage,
    _ApiConfig config,
  ) async {
    final response = await _dio.post(
      '${config.baseUrl}/chat/completions',
      options: Options(
        headers: {'Authorization': 'Bearer ${config.token}'},
      ),
      data: {
        'model': config.model,
        'messages': [
          {
            'role': 'system',
            'content': ExtractionPrompt.buildSystemPrompt(),
          },
          {
            'role': 'user',
            'content': ExtractionPrompt.buildUserPrompt(userMessage),
          },
        ],
        // [教練 Agent 2026-07-30] 不硬編碼 temperature——reasoning model（kimi-k3, gpt-5.4）
        // 只接受固定值，硬編碼 0.3 會被 API 拒絕。讓各 provider 用自己的預設值。
        'stream': false,
        'max_tokens': 1000, // 提取結果不需要太長
      },
    );

    final data = response.data as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) return [];

    final content = choices[0]['message']?['content']?.toString() ?? '';
    if (content.isEmpty) return [];

    return ExtractionPrompt.parseResponse(content);
  }

  /// 去重 — 與正則已提取的記憶做文字比對。
  ///
  /// 這是輕量級去重（文字相似度），向量去重在 writeToBrainContainer 中做。
  ///
  /// P4 修復（2026-07-03）：原本用 bigram Jaccard，但 LLM 將記憶改寫為
  /// 第三人稱（「使用者...」）後，bigram Jaccard 降至 0.50 以下，去重失效。
  /// 改用「有意義 token 重疊率」：去除常見停用詞後，計算關鍵詞的重疊比例。
  /// 例如「使用者的女兒叫小星星」vs「我女兒叫小星星」→ 關鍵詞 {女兒,叫,小星星}
  /// 完全重疊 → 重疊率 1.0 → 正確判定為重複。
  Future<List<ExtractedFact>> _deduplicate(
    List<ExtractedFact> facts,
    List<String> alreadyExtracted,
  ) async {
    if (alreadyExtracted.isEmpty) return facts;

    final filtered = <ExtractedFact>[];
    for (final fact in facts) {
      bool isDup = false;
      for (final existing in alreadyExtracted) {
        if (_tokenOverlap(fact.content, existing) >= 0.5) {
          isDup = true;
          break;
        }
      }
      if (!isDup) {
        filtered.add(fact);
      }
    }

    return filtered;
  }

  /// 計算兩段文字的有意義 token 重疊率。
  ///
  /// 策略：
  /// 1. 去除停用詞（我、的、是、使用者、本人...）
  /// 2. 剩餘文字切成 2~3 字的 token
  /// 3. 計算重疊率 = 交集數量 / 較短列表的長度
  ///
  /// 這比 bigram Jaccard 更能處理第三人稱改寫的情況：
  /// 「使用者的女兒叫小星星」→ tokens: {女兒,叫,小星星}
  /// 「我女兒叫小星星」→ tokens: {女兒,叫,小星星}
  /// 重疊率 = 3/3 = 1.0
  double _tokenOverlap(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;

    final tokensA = _extractMeaningfulTokens(a);
    final tokensB = _extractMeaningfulTokens(b);

    if (tokensA.isEmpty || tokensB.isEmpty) return 0.0;

    final intersection = tokensA.intersection(tokensB);
    final shorterLen = tokensA.length < tokensB.length ? tokensA.length : tokensB.length;

    return intersection.length / shorterLen;
  }

  /// 從文字中提取有意義的 token。
  ///
  /// 去除停用詞後，將連續的非空白字元切成 2~3 字的片段。
  static final RegExp _stopwordPattern = RegExp(
    r'使用者|本人|我|的|是|在|有|個|一|了|也|都|就|會|能|要|想|覺得|覺|最近|正在|現在|一直|已經|今天|昨天|明天',
  );

  Set<String> _extractMeaningfulTokens(String text) {
    // 去停用詞
    var cleaned = text.replaceAll(_stopwordPattern, '');
    // 去除多餘空白
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), '').trim();
    if (cleaned.length < 2) return {};

    final tokens = <String>{};
    // 切成 2 字 token（中文 bigram 但已去停用詞）
    for (var i = 0; i < cleaned.length - 1; i++) {
      final token = cleaned.substring(i, i + 2);
      if (token.trim().isNotEmpty) {
        tokens.add(token);
      }
    }
    return tokens;
  }
}

/// API 配置載體。
class _ApiConfig {
  final String baseUrl;
  final String token;
  final String model;
  final String provider;

  const _ApiConfig({
    required this.baseUrl,
    required this.token,
    required this.model,
    required this.provider,
  });
}
