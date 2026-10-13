// lib/services/capability_advisor_service.dart
// [以利沙 Capability Advisor 2026-06-25]
// 顧問流程的編排核心 (orchestrator)。
// 狀態機驅動：startFlow → checkBrowsePrerequisite → searchSolutions
// → analyzeCandidates → presentingComparison → awaitingSelection
// → solutionSelected → verifying → verified → returningToTask

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/bridge_action.dart';
import '../models/capability_advisor.dart';
import 'api_service.dart';
import 'bridge_action_executor.dart';
import 'capability_health_service.dart';

class CapabilityAdvisorService {
  CapabilityAdvisorService({
    BridgeActionExecutor? executor,
    CapabilityHealthService? healthService,
    Uuid? uuid,
  }) : _executor = executor ?? BridgeActionExecutor(),
       _health = healthService ?? CapabilityHealthService(),
       _uuid = uuid ?? const Uuid();

  final BridgeActionExecutor _executor;
  final CapabilityHealthService _health;
  final Uuid _uuid;

  // ── gapType → 人類可讀標籤 ──

  static const _gapLabels = <String, String>{
    'generate_music': '音樂生成能力',
    'generate_video': '影片生成能力',
    'generate_image': '圖片生成能力',
    'browse': '網頁搜尋能力',
    'vision': '圖片辨識能力',
    'document': '文件產出能力',
    'desktop_files': '桌面整理能力',
    // [以利沙 2026-06-26] 修復一：定時提醒能力標籤
    'schedule_reminder': '定時提醒能力',
    // [以利沙 修復四 2026-06-27] 本地模型能力標籤
    'local_model': '本地 AI 模型',
  };

  String _gapLabel(String gapType) =>
      _gapLabels[gapType] ?? '橋樑能力';

  // ── startFlow ──

  Future<CapabilityAdvisorCardData> startFlow({
    required String gapType,
    required String userRequest,
    BridgeAction? originalAction,
  }) async {
    return CapabilityAdvisorCardData(
      id: _uuid.v4(),
      gapType: gapType,
      gapLabel: _gapLabel(gapType),
      userRequest: userRequest,
      originalAction: originalAction,
      currentStep: CapabilityAdvisorStep.checkingBrowse,
      statusMessage: '正在確認搜尋能力...',
      createdAt: DateTime.now(),
    );
  }

  // ── checkBrowsePrerequisite ──

  Future<CapabilityAdvisorCardData> checkBrowsePrerequisite(
    CapabilityAdvisorCardData current,
  ) async {
    try {
      // 如果原始 gap 就是 browse，不需要堆疊
      if (current.gapType == 'browse') {
        return current.copyWith(
          currentStep: CapabilityAdvisorStep.searching,
          statusMessage: '正在搜尋市面方案...',
        );
      }

      // [以利沙 P1 修復十二輪 2026-06-27] 豁免清單：不需要 browse 支援的 gapType，不應被打斷
      const browseFreeGapTypes = ['schedule_reminder', 'local_model'];
      if (browseFreeGapTypes.contains(current.gapType)) {
        // 直接跳到 AI 知識庫 fallback，不堆疊 browse gap
        return current.copyWith(
          currentStep: CapabilityAdvisorStep.searching,
          statusMessage: '正在搜尋市面方案...',
        );
      }

      final browseReady = await _health.isBrowseReady();
      if (browseReady) {
        return current.copyWith(
          currentStep: CapabilityAdvisorStep.searching,
          statusMessage: '正在搜尋市面方案...',
        );
      }

      // browse 未開通，需要堆疊
      final suspendedGap = AdvisorGapContext(
        gapType: current.gapType,
        gapLabel: current.gapLabel,
        userRequest: current.userRequest,
        originalActionJson: current.originalAction?.toJson() != null
            ? jsonEncode(current.originalAction!.toJson())
            : null,
        suspendedAtStep: CapabilityAdvisorStep.searching,
      );

      return current.copyWith(
        gapType: 'browse',
        gapLabel: '網頁搜尋能力',
        currentStep: CapabilityAdvisorStep.browseGapDetected,
        statusMessage:
            '要幫你找方案，我需要先能上網搜尋。'
            '目前搜尋能力還沒開通，我們先處理這個。',
        suspendedGap: suspendedGap,
      );
    } catch (e) {
      return current.copyWith(
        currentStep: CapabilityAdvisorStep.failed,
        statusMessage: '確認搜尋能力時發生錯誤：$e',
      );
    }
  }

  // ── searchSolutions ──

  Future<CapabilityAdvisorCardData> searchSolutions(
    CapabilityAdvisorCardData current,
  ) async {
    try {
      // 如果處於 browseGapDetected，先切到 searching
      var card = current;
      if (card.currentStep == CapabilityAdvisorStep.browseGapDetected) {
        card = card.copyWith(
          currentStep: CapabilityAdvisorStep.searching,
          statusMessage: '正在搜尋市面方案...',
        );
      }

      final searchPrompt = _buildSearchPrompt(card.gapType, card.userRequest);
      final result = await _executor.execute(
        BridgeAction(type: BridgeActionType.browse, prompt: searchPrompt),
      );

      if (result.status == BridgeActionStatus.completed) {
        // 搜尋成功，直接進入分析（搜尋結果文字會在 analyzeCandidates 中使用）
        return card.copyWith(
          currentStep: CapabilityAdvisorStep.analyzing,
          statusMessage: '搜尋完成，正在分析貼合度...',
          metadata: {
            ...card.metadata,
            'searchResult': result.message,
            'searchSources': result.metadata?['searchSources'],
          },
        );
      }

      // 搜尋失敗 → fallback：繼續呼叫 analyzeCandidates，傳入空 searchResult，讓 AI 根據知識提供建議
      return analyzeCandidates(
        card.copyWith(
          currentStep: CapabilityAdvisorStep.analyzing,
          statusMessage: '正在為你整理可用方案...',
          metadata: {
            ...card.metadata,
            'searchResult': '',
          },
        ),
      );
    } catch (e) {
      return current.copyWith(
        currentStep: CapabilityAdvisorStep.failed,
        statusMessage: '搜尋時發生錯誤：$e',
      );
    }
  }

  // ── analyzeCandidates ──

  Future<CapabilityAdvisorCardData> analyzeCandidates(
    CapabilityAdvisorCardData current, {
    String? correctedIntent,
  }) async {
    try {
      final searchResult = current.metadata['searchResult']?.toString() ?? '';
      final intent = correctedIntent ?? current.userRequest;

      final systemPrompt = [
        '你是橋樑系統的能力顧問分析引擎。',
        '以下是針對指定缺口搜尋到的解法資訊（可能包含橋樑內建方案與外部方案）。',
        '請從五個維度分析每個方案的貼合度：',
        '1. 預算（免費額度、付費定價）',
        '2. 中文支援度',
        '3. 使用頻率適配性（輕度 vs 重度）',
        '4. 與使用者需求意圖的貼合度',
        '5. 資料主權（資料是否離開本機；內建/本地方案同分下優先推薦）',
        '同時推斷使用者的真實意圖，並標記推薦首選。',
        '',
        '⚠️ 重要：你必須只輸出 JSON，不要輸出任何其他文字、解釋、問候或 markdown。',
        '不要說「嗨」「你好」或任何開場白。',
        '直接以 { 開頭，以 } 結尾。',
        '',
        'JSON 格式如下：',
        '',
        '{',
        '  "inferredIntent": "一句話描述使用者真實意圖",',
        '  "candidates": [',
        '    {',
        '      "id": "方案唯一識別碼（如 solution_1）",',
        '      "name": "方案名稱",',
        '      "provider": "提供商",',
        '      "officialUrl": "官方網址",',
        '      "deploymentType": "cloud|local|hybrid",',
        '      "budgetSummary": "預算摘要",',
        '      "hasFreeTier": true,',
        '      "paidPricingNote": "付費定價說明",',
        '      "chineseSupportLevel": "中文支援度描述",',
        '      "chineseSupportScore": 80,',
        '      "usageFrequencyFit": "使用頻率適配性",',
        '      "usageFrequencyScore": 75,',
        '      "intentFitNote": "意圖貼合度說明",',
        '      "intentFitScore": 85,',
        '      "setupSteps": ["步驟1", "步驟2"],',
        '      "aiNote": "AI 綜合評語",',
        '      "overallScore": 82,',
        '      "isRecommended": true',
        '    }',
        '  ]',
        '}',
        '',
        '請提供正好三家方案。分數範圍 0-100。',
        'isRecommended 只能有一家為 true。',
        '再次強調：只輸出 JSON，不要輸出任何其他內容。',
      ].join('\n');

      final userPrompt = [
        '缺口類型：${current.gapType}（${current.gapLabel}）',
        '使用者需求：$intent',
        if (correctedIntent != null) '使用者修正後的意圖：$correctedIntent',
        '',
        '以下是搜尋到的市面方案資訊：',
        searchResult.isEmpty
            ? '（搜尋結果為空，請根據你的知識提供三家主流方案，並在 aiNote 標註「未驗證：來自模型知識」）'
            : searchResult,
      ].join('\n');

      final chatResponse = await ApiService.sendMessage([
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ]);
      final aiResponse = chatResponse.cleanContent;

      // [debug] 印出 AI 回應前 500 字，排查解析失敗原因
      debugPrint('[CapabilityAdvisor] AI response length=${aiResponse.length}');
      debugPrint('[CapabilityAdvisor] AI response preview: ${aiResponse.length > 500 ? aiResponse.substring(0, 500) : aiResponse}');

      final parsed = _parseAnalysisResponse(aiResponse);
      if (parsed == null || parsed.candidates.isEmpty) {
        debugPrint('[CapabilityAdvisor] Parse FAILED. Full response: $aiResponse');

        // Fallback：如果 AI 回應是自然語言（非 JSON），直接把回應顯示給使用者
        // 而不是顯示「解析失敗」——AI 其實回答了問題，只是沒遵守 JSON 格式
        if (aiResponse.isNotEmpty && aiResponse.length > 20) {
          return current.copyWith(
            currentStep: CapabilityAdvisorStep.verified,
            statusMessage: aiResponse,
          );
        }

        return current.copyWith(
          currentStep: CapabilityAdvisorStep.failed,
          statusMessage: 'AI 分析結果解析失敗，請重試。',
        );
      }

      return current.copyWith(
        currentStep: CapabilityAdvisorStep.presentingComparison,
        statusMessage: '分析完成，請確認以下推斷是否符合你的需求。',
        inferredIntent: parsed.inferredIntent,
        candidates: parsed.candidates,
        confirmedIntent: correctedIntent,
      );
    } catch (e) {
      return current.copyWith(
        currentStep: CapabilityAdvisorStep.failed,
        statusMessage: '分析時發生錯誤：$e',
      );
    }
  }

  // ── selectSolution ──

  Future<CapabilityAdvisorCardData> selectSolution(
    CapabilityAdvisorCardData current,
    String candidateId,
  ) async {
    return current.copyWith(
      currentStep: CapabilityAdvisorStep.solutionSelected,
      selectedCandidateId: candidateId,
      statusMessage: '已選定方案，請依照步驟開通。',
    );
  }

  // ── verifyCapability ──

  Future<CapabilityAdvisorCardData> verifyCapability(
    CapabilityAdvisorCardData current,
  ) async {
    try {
      final gapType = current.gapType;
      final actionType = _actionTypeFromGapType(gapType);

      if (actionType == null) {
        // 無對應橋接類型（如 schedule_reminder），以使用者自報模式通過
        return current.copyWith(
          currentStep: CapabilityAdvisorStep.verified,
          verificationPassed: true,
          verificationResult: '${current.gapLabel}已登記完成，你可以實際測試看看效果！',
          statusMessage: '完成！你可以回到對話，繼續你原本的任務。',
        );
      }

      // 如果是 browse 且有 suspendedGap，browse 驗證通過後要恢復原始 gap
      final isBrowseSubFlow =
          current.suspendedGap != null && gapType == 'browse';

      final isReady = await _health.isBrowseReady();
      if (!isReady && actionType == BridgeActionType.browse) {
        // browse 驗證失敗，回到 solutionSelected 讓使用者重試
        return current.copyWith(
          currentStep: CapabilityAdvisorStep.solutionSelected,
          verificationPassed: false,
          verificationResult: '搜尋能力尚未開通，請確認 API Key 已正確設定。',
          statusMessage: '驗證未通過，請重新檢查步驟後再試。',
        );
      }

      // 對非 browse 的能力，用 inspect 來確認
      if (actionType != BridgeActionType.browse) {
        final items = await _health.inspect();
        final matched = items.where((item) => item.type == actionType).toList();
        if (matched.isEmpty ||
            matched.first.status != CapabilityHealthStatus.ready) {
          return current.copyWith(
            currentStep: CapabilityAdvisorStep.solutionSelected,
            verificationPassed: false,
            verificationResult: '${current.gapLabel}尚未開通，請確認步驟已完成。',
            statusMessage: '驗證未通過，請重新檢查步驟後再試。',
          );
        }
      }

      // 驗證通過
      if (isBrowseSubFlow) {
        // browse 子流程通過，恢復原始 gap 並進入 searching
        final suspended = current.suspendedGap!;
        BridgeAction? restoredAction;
        if (suspended.originalActionJson != null) {
          try {
            final actionJson = jsonDecode(suspended.originalActionJson!);
            if (actionJson is Map<String, dynamic>) {
              restoredAction = BridgeAction.fromJson(actionJson);
            }
          } catch (_) {}
        }
        return current.copyWith(
          gapType: suspended.gapType,
          gapLabel: suspended.gapLabel,
          userRequest: suspended.userRequest,
          originalAction: restoredAction,
          suspendedGap: null,
          currentStep: CapabilityAdvisorStep.searching,
          verificationPassed: true,
          verificationResult: '搜尋能力已開通，現在開始搜尋原始缺口的方案。',
          statusMessage: '搜尋能力已開通，正在搜尋原始缺口的方案...',
        );
      }

      // 一般驗證通過
      return current.copyWith(
        currentStep: CapabilityAdvisorStep.verified,
        verificationPassed: true,
        verificationResult: '${current.gapLabel}驗證通過！',
        statusMessage: '驗證通過！可以回到主線任務。',
      );
    } catch (e) {
      return current.copyWith(
        currentStep: CapabilityAdvisorStep.failed,
        statusMessage: '驗證時發生錯誤：$e',
      );
    }
  }

  // ── confirmIntent ──

  CapabilityAdvisorCardData confirmIntent(
    CapabilityAdvisorCardData current,
    String confirmedOrCorrectedIntent,
  ) {
    // 如果使用者修正了意圖，需要重新分析
    final wasCorrected =
        current.inferredIntent != null &&
        current.inferredIntent != confirmedOrCorrectedIntent;

    if (wasCorrected) {
      return current.copyWith(
        currentStep: CapabilityAdvisorStep.analyzing,
        statusMessage: '意圖已修正，正在重新分析...',
        confirmedIntent: confirmedOrCorrectedIntent,
      );
    }

    return current.copyWith(
      currentStep: CapabilityAdvisorStep.awaitingSelection,
      statusMessage: '意圖已確認，請選擇方案。',
      confirmedIntent: confirmedOrCorrectedIntent,
    );
  }

  // ── cancel ──

  CapabilityAdvisorCardData cancel(CapabilityAdvisorCardData current) {
    return current.copyWith(
      currentStep: CapabilityAdvisorStep.cancelled,
      statusMessage: '能力顧問流程已取消。',
    );
  }

  // ── 內部方法 ──

  String _buildSearchPrompt(String gapType, String userRequest) {
    final label = _gapLabel(gapType);
    // [小葵 2026-09-15 Blue 架構令] 搜尋順序翻轉——本地優先。
    // 舊 prompt 直接找外部 SaaS（把使用者往外推），與資料主權宣言
    // （docs/DATA_SOVEREIGNTY_MANIFESTO.md）和全本地路線（DGX Spark）
    // 背道而馳。新順序：
    // 1. 橋樑系統內建解法（畫布節點/agent 工具/本地模型）——零外流
    // 2. 使用者已有的服務（金鑰匙已開通的）
    // 3. 真的需要外部方案才搜市面（明確標註資料會離開本機）
    return [
      '使用者的任務遇到「$label」能力缺口，請分層搜尋解法，至少三個選項：',
      '',
      '【第一層：橋樑系統內建】優先檢查——',
      '- 畫布工作流節點（排程 schedule 節點、email 發送、觸發器等）',
      '- Agent 既有工具（terminal、browser automation、記憶、delegate）',
      '- 本地模型（Gemma 等已部署的）',
      '若任務能用內建組合解決，這是首選（免費、資料不出本機）。',
      '',
      '【第二層：使用者已開通的服務】金鑰匙系統已設定的 provider——',
      '用已有的，不新增外部依賴。',
      '',
      '【第三層：外部方案】以上兩層都不可行才搜市面主流方案，並且：',
      '- 明確標註「資料會離開這台機器」',
      '- 標註資料主權等級（本地優/可接受/需謹慎）',
      '- 免費額度、付費定價、中文支援度、官方網站',
      '',
      '使用者原始需求：$userRequest',
      '',
      '請以結構化方式整理搜尋結果，方便後續分析。',
    ].join('\n');
  }

  BridgeActionType? _actionTypeFromGapType(String gapType) {
    switch (gapType) {
      case 'generate_music':
        return BridgeActionType.generateMusic;
      case 'generate_video':
        return BridgeActionType.generateVideo;
      case 'generate_image':
        return BridgeActionType.generateImage;
      case 'browse':
        return BridgeActionType.browse;
      case 'vision':
        return BridgeActionType.vision;
      case 'document':
        return BridgeActionType.document;
      case 'desktop_files':
        return BridgeActionType.desktopFiles;
      // [以利沙 2026-06-26] 修復一：定時提醒無對應 BridgeActionType，回傳 null 讓顧問流程以通用模式進行
      case 'schedule_reminder':
        return null;
      // [以利沙 修復四 2026-06-27] 本地模型暫無橋接，回傳 null 以通用模式進行
      case 'local_model':
        return null;
      default:
        return null;
    }
  }

  _AnalysisResult? _parseAnalysisResponse(String aiResponse) {
    try {
      // 嘗試從 markdown code block 中提取 JSON
      var jsonText = aiResponse.trim();
      final fenceMatch = RegExp(
        r'```(?:json)?\s*\n([\s\S]*?)\n```',
      ).firstMatch(jsonText);
      if (fenceMatch != null) {
        jsonText = fenceMatch.group(1)!.trim();
      }

      // 如果不是純 JSON，嘗試找到第一個 { 到最後一個 } 之間的內容
      // （LLM 可能在 JSON 前後加了解釋文字）
      if (!jsonText.startsWith('{')) {
        final firstBrace = jsonText.indexOf('{');
        final lastBrace = jsonText.lastIndexOf('}');
        if (firstBrace >= 0 && lastBrace > firstBrace) {
          jsonText = jsonText.substring(firstBrace, lastBrace + 1);
        }
      }

      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return null;

      final inferredIntent = decoded['inferredIntent']?.toString() ?? '';
      final candidatesJson = decoded['candidates'];
      if (candidatesJson is! List) return null;

      final candidates = <SolutionCandidate>[];
      for (final item in candidatesJson) {
        if (item is Map<String, dynamic>) {
          final candidate = SolutionCandidate.fromJson(item);
          if (candidate != null) candidates.add(candidate);
        }
      }

      if (candidates.isEmpty) return null;

      return _AnalysisResult(
        inferredIntent: inferredIntent,
        candidates: candidates,
      );
    } catch (_) {
      return null;
    }
  }
}

class _AnalysisResult {
  final String inferredIntent;
  final List<SolutionCandidate> candidates;

  const _AnalysisResult({
    required this.inferredIntent,
    required this.candidates,
  });
}
