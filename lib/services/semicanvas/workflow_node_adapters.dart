// workflow_node_adapters.dart
// SemiCanvas Phase 2c: 節點 Adapter
// 為每種 WorkflowNodeType 提供實際執行邏輯
//
// 設計文件: semicanvas-design.md §2.2-2.4

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/semicanvas/workflow_executor.dart';
import 'package:bridge_app/services/capability/capability_executor.dart'; // [T10①] vision/characterLock headless
import 'package:bridge_app/services/vault/vault_service.dart'; // [教練 Agent 2026-08-16] knowledge 節點檢索
import 'package:bridge_app/services/routines/system_routine_store.dart'; // [Blue 拍板] 招式
import 'package:bridge_app/services/routines/system_routine_player.dart'; // [Blue 拍板] 招式

/// LLM 呼叫介面 — 由外部注入
abstract class WorkflowLLMClient {
  /// 發送 system + user prompt 到 LLM，回傳文字
  Future<String> complete({
    required String systemPrompt,
    required String userPrompt,
    String? model,
    double? temperature,
    int? maxTokens,
  });
}

/// 工具執行介面 — 由外部注入
abstract class WorkflowToolRunner {
  /// 執行工具，回傳結果文字
  Future<String> runTool({
    required String toolName,
    required Map<String, dynamic> args,
  });
}

/// 圖片生成介面 — 由外部注入
abstract class WorkflowImageGenerator {
  /// 生成圖片，回傳 URL 或路徑
  Future<String> generateImage({
    required String prompt,
    String? model,
    String? size,
    String? style,
  });
}

/// 影片生成介面 — 由外部注入
abstract class WorkflowVideoGenerator {
  /// 生成影片，回傳 URL 或路徑
  Future<String> generateVideo({
    required String prompt,
    String? model,
    int? duration,
  });
}

/// 音樂生成介面 — 由外部注入
abstract class WorkflowMusicGenerator {
  /// 生成音樂，回傳 URL 或路徑
  Future<String> generateMusic({
    required String prompt,
    String? model,
    int? duration,
    String? genre,
  });
}

/// 語音合成介面 — 由外部注入
abstract class WorkflowTtsClient {
  /// 將文字轉為語音，回傳 URL 或路徑
  Future<String> synthesize({
    required String text,
    String? voice,
    double? speed,
  });
}

/// 條件評估介面 — 由外部注入
abstract class WorkflowConditionEvaluator {
  /// 評估條件運算式，回傳 true/false
  Future<bool> evaluate({
    required String expression,
    required Map<String, String> inputs,
  });
}

/// 子工作流執行介面 — 由外部注入
abstract class SubWorkflowRunner {
  /// 載入並執行子工作流，回傳最終輸出
  Future<String> run({
    required String workflowRef,
    required UpstreamData upstreamData
  });
}

/// 節點 Adapter — 將 WorkflowNodeType 對應到實際執行邏輯。
///
/// 使用方式：
/// 1. 注入各種 client（LLM, Tool, ImageGen, Condition）
/// 2. 呼叫 [createNodeExecutor] 取得 NodeExecutor 函數
/// 3. 傳給 WorkflowExecutor
class WorkflowNodeAdapters {
  final WorkflowLLMClient? llmClient;
  final WorkflowToolRunner? toolRunner;
  final WorkflowImageGenerator? imageGenerator;
  final WorkflowVideoGenerator? videoGenerator;
  final WorkflowMusicGenerator? musicGenerator;
  final WorkflowTtsClient? ttsClient;
  final WorkflowConditionEvaluator? conditionEvaluator;
  final SubWorkflowRunner? subWorkflowRunner;

  WorkflowNodeAdapters({
    this.llmClient,
    this.toolRunner,
    this.imageGenerator,
    this.videoGenerator,
    this.musicGenerator,
    this.ttsClient,
    this.conditionEvaluator,
    this.subWorkflowRunner,
  });

  /// 建立 NodeExecutor — 傳給 WorkflowExecutor 使用
  NodeExecutor createNodeExecutor() {
    return _executeNode;
  }

  Future<NodeExecutionResult> _executeNode(
    String nodeId,
    WorkflowNodeType? nodeType,
    Map<String, dynamic> params,
    UpstreamData upstreamData,
  ) async {
    if (nodeType == null) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: true,
        output: upstreamData.combinedText,
      );
    }

    switch (nodeType) {
      case WorkflowNodeType.llm:
        return _executeLLM(nodeId, params, upstreamData);
      case WorkflowNodeType.tool:
        return _executeTool(nodeId, params, upstreamData);
      case WorkflowNodeType.imageGen:
        return _executeImageGen(nodeId, params, upstreamData);
      case WorkflowNodeType.condition:
        return _executeCondition(nodeId, params, upstreamData);
      // input, output, merge 由 WorkflowExecutor 內部處理
      case WorkflowNodeType.input:
      case WorkflowNodeType.output:
      case WorkflowNodeType.merge:
        return NodeExecutionResult(
          nodeId: nodeId,
          success: true,
          output: upstreamData.combinedText,
        );
      // 以下尚未實作 adapter
      case WorkflowNodeType.videoGen:
        return _executeVideoGen(nodeId, params, upstreamData);
      case WorkflowNodeType.musicGen:
        return _executeMusicGen(nodeId, params, upstreamData);
      case WorkflowNodeType.tts:
        return _executeTts(nodeId, params, upstreamData);
      case WorkflowNodeType.move: // 🥋 [Blue 拍板] 招式——adapter 路徑（排程/無頭）
        return _executeMove(nodeId, params, upstreamData);
      case WorkflowNodeType.subWorkflow:
        return _executeSubWorkflow(nodeId, params, upstreamData);
      case WorkflowNodeType.knowledge: // [教練 Agent 2026-16] vault 知識檢索
        return _executeKnowledge(nodeId, params, upstreamData);
      case WorkflowNodeType.materialPool: // [教練 Agent 2026-08-25 F-1] 素材池
        // adapter 路徑（排程/無頭）：只產候選，採用 UI 是畫布端人的行為。
        return NodeExecutionResult(
          nodeId: nodeId,
          success: false,
          errorMessage: '素材池請使用畫布原生執行器（採用互動需要人）',
        );
      case WorkflowNodeType.schedule:
        // 排程節點本身不執行，只傳遞排程設定
        return NodeExecutionResult(
          nodeId: nodeId,
          success: true,
          output: '排程: ${params['scheduleType'] ?? 'daily'} ${params['time'] ?? ''}',
        );
      case WorkflowNodeType.vision:
        // [T10① 2026-10-17 headless 執行器] vision 收編——與畫布原生同路
        // （CapabilityExecutor.instance，不需 UI）。原本排程路徑直接失敗
        // 「請使用畫布原生執行器」，schedule_runs.jsonl 30 筆全是這個病。
        return _executeVision(nodeId, params, upstreamData);
      case WorkflowNodeType.characterLock:
        // [T10①] characterLock 收編——上游參考圖＋prompt 生成風格一致圖
        return _executeCharacterLock(nodeId, params, upstreamData);
    }
  }

  /// [T10①] Vision 節點 headless 執行——邏輯移植自 canvas_v2_workspace
  /// （1769-1852 行），走 CapabilityExecutor 與原生同路。
  Future<NodeExecutionResult> _executeVision(
    String nodeId,
    Map<String, dynamic> params,
    UpstreamData upstreamData,
  ) async {
    final promptText = params['prompt']?.toString() ?? '描述這張圖片';
    final serviceId = params['serviceId']?.toString();
    final base64Image = upstreamData.firstBase64Image;
    final imageUrl = upstreamData.firstImageUrl;

    // 原圖直通：無上游連線時 params['image'] 檔案路徑＝源頭
    Uint8List? passthroughImage;
    if (base64Image == null && imageUrl == null) {
      final localPath = params['image']?.toString();
      if (localPath != null && localPath.isNotEmpty) {
        try {
          passthroughImage = await File(localPath).readAsBytes();
        } catch (_) {
          passthroughImage = null;
        }
      }
    }
    if (base64Image == null && imageUrl == null && passthroughImage == null) {
      return NodeExecutionResult.failure(
          nodeId, 'Vision 節點需要上游有圖片輸入，請連接 ImageGen 或 Input 節點');
    }

    if (serviceId != null && serviceId.isNotEmpty) {
      String b64 = base64Image ?? '';
      if (b64.isEmpty && imageUrl != null) {
        try {
          final imgResp = await Dio().get<List<int>>(imageUrl,
              options: Options(responseType: ResponseType.bytes));
          b64 = base64.encode(imgResp.data ?? []);
        } catch (e) {
          return NodeExecutionResult.failure(nodeId, '下載圖片失敗: $e');
        }
      }
      final capResult = await CapabilityExecutor.instance.analyzeImage(
        serviceId: serviceId,
        prompt: promptText,
        base64Image: b64,
      );
      if (capResult.success) {
        return NodeExecutionResult.withImage(nodeId, capResult.text ?? '',
            imageData: passthroughImage);
      }
      return NodeExecutionResult.failure(
          nodeId, capResult.error ?? '圖片理解失敗');
    }

    // 無 serviceId——原圖照樣直通（與畫布原生同款 fallback）
    if (passthroughImage != null) {
      return NodeExecutionResult.withImage(
          nodeId, '（未選服務——原圖直通，未分析）', imageData: passthroughImage);
    }
    return NodeExecutionResult.failure(nodeId, '請在節點設定中選擇「服務」');
  }

  /// [T10①] CharacterLock 節點 headless 執行——上游參考圖＋prompt 圖生圖
  Future<NodeExecutionResult> _executeCharacterLock(
    String nodeId,
    Map<String, dynamic> params,
    UpstreamData upstreamData,
  ) async {
    // prompt 模板插值（{input}/{upstream} → 上游文字）
    final promptRaw = params['prompt']?.toString() ?? '';
    final upstreamText = upstreamData.combinedText;
    var promptText = promptRaw;
    if (promptRaw.contains('{input}') || promptRaw.contains('{upstream}')) {
      promptText = promptRaw
          .replaceAll('{input}', upstreamText)
          .replaceAll('{upstream}', upstreamText);
    }
    final serviceId = params['serviceId']?.toString();
    final size = params['size']?.toString();

    final base64Ref = upstreamData.firstBase64Image;
    final imageUrl = upstreamData.firstImageUrl;
    if (base64Ref == null && imageUrl == null) {
      return NodeExecutionResult.failure(nodeId, '角色一致性節點需要上游有參考圖片');
    }

    String b64Ref = base64Ref ?? '';
    if (b64Ref.isEmpty && imageUrl != null) {
      try {
        final imgResp = await Dio().get<List<int>>(imageUrl,
            options: Options(responseType: ResponseType.bytes));
        b64Ref = base64.encode(imgResp.data ?? []);
      } catch (e) {
        return NodeExecutionResult.failure(nodeId, '下載參考圖失敗: $e');
      }
    }

    if (serviceId != null && serviceId.isNotEmpty) {
      final capResult =
          await CapabilityExecutor.instance.generateImageWithReference(
        serviceId: serviceId,
        prompt: promptText,
        base64ReferenceImage: b64Ref,
        size: size,
      );
      if (capResult.success) {
        return NodeExecutionResult.withImage(
          nodeId,
          capResult.localFilePath != null
              ? '角色一致性圖片已生成\n路徑: ${capResult.localFilePath}'
              : '角色一致性圖片已生成',
          imageData: capResult.imageData,
          imageUrl: capResult.imageUrl,
        );
      }
      return NodeExecutionResult.failure(
          nodeId, capResult.error ?? '角色一致性生成失敗');
    }
    return NodeExecutionResult.failure(nodeId, '請在節點設定中選擇「服務」');
  }

  /// LLM 節點 — 呼叫 LLM 進行推論
  Future<NodeExecutionResult> _executeLLM(
    String nodeId,
    Map<String, dynamic> params,
    UpstreamData upstreamData
  ) async {
    if (llmClient == null) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: 'LLM client 未注入',
      );
    }

    final prompt = params['prompt']?.toString() ?? '';
    final model = params['model']?.toString();
    final temperature = (params['temperature'] as num?)?.toDouble();
    final maxTokens = (params['maxTokens'] as num?)?.toInt();

    // 上游輸出作為 user prompt 的 context
    final context = upstreamData.combinedText;
    final userPrompt = context.isEmpty ? prompt : '$prompt\n\n---\n輸入資料:\n$context';

    try {
      final result = await llmClient!.complete(
        systemPrompt: '你是一個工作流節點。請根據以下指示處理輸入資料。',
        userPrompt: userPrompt,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      return NodeExecutionResult(nodeId: nodeId, success: true, output: result);
    } catch (e) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: 'LLM 呼叫失敗: $e',
      );
    }
  }

  /// Tool 節點 — 呼叫 Agent 工具
  Future<NodeExecutionResult> _executeTool(
    String nodeId,
    Map<String, dynamic> params,
    UpstreamData upstreamData
  ) async {
    if (toolRunner == null) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: 'Tool runner 未注入',
      );
    }

    final toolName = params['toolName']?.toString() ?? '';
    if (toolName.isEmpty) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '未指定工具名稱',
      );
    }

    // 合併 params.args 和上游輸出
    final args = Map<String, dynamic>.from(params);
    args.remove('toolName');
    args.remove('args');
    // 如果有 args JSON 字串，合併進去
    final argsStr = params['args']?.toString();
    if (argsStr != null && argsStr.isNotEmpty) {
      // args 是上游輸出或 JSON 字串
      if (upstreamData.texts.isNotEmpty) {
        args['input'] = upstreamData.combinedText;
      } else {
        args['input'] = argsStr;
      }
    } else if (upstreamData.texts.isNotEmpty) {
      args['input'] = upstreamData.combinedText;
    }

    try {
      final result = await toolRunner!.runTool(toolName: toolName, args: args);
      return NodeExecutionResult(nodeId: nodeId, success: true, output: result);
    } catch (e) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '工具執行失敗: $e',
      );
    }
  }

  /// ImageGen 節點 — 生成圖片
  Future<NodeExecutionResult> _executeImageGen(
    String nodeId,
    Map<String, dynamic> params,
    UpstreamData upstreamData
  ) async {
    if (imageGenerator == null) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: 'Image generator 未注入',
      );
    }

    // prompt 來自 params 或上游輸出
    var prompt = params['prompt']?.toString() ?? '';
    if (prompt.isEmpty && upstreamData.texts.isNotEmpty) {
      prompt = upstreamData.combinedText;
    }
    if (prompt.isEmpty) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '圖片生成需要 prompt 或上游輸入',
      );
    }

    try {
      final imageUrl = await imageGenerator!.generateImage(
        prompt: prompt,
        model: params['model']?.toString(),
        size: params['size']?.toString(),
        style: params['style']?.toString(),
      );
      return NodeExecutionResult(
        nodeId: nodeId,
        success: true,
        output: imageUrl,
      );
    } catch (e) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '圖片生成失敗: $e',
      );
    }
  }

  /// VideoGen 節點 — 生成影片
  Future<NodeExecutionResult> _executeVideoGen(
    String nodeId,
    Map<String, dynamic> params,
    UpstreamData upstreamData
  ) async {
    if (videoGenerator == null) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: 'Video generator 未注入',
      );
    }

    var prompt = params['prompt']?.toString() ?? '';
    if (prompt.isEmpty && upstreamData.texts.isNotEmpty) {
      prompt = upstreamData.combinedText;
    }
    if (prompt.isEmpty) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '影片生成需要 prompt 或上游輸入',
      );
    }

    try {
      final videoUrl = await videoGenerator!.generateVideo(
        prompt: prompt,
        model: params['model']?.toString(),
        duration: (params['duration'] as num?)?.toInt(),
      );
      return NodeExecutionResult(
        nodeId: nodeId,
        success: true,
        output: videoUrl,
      );
    } catch (e) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '影片生成失敗: $e',
      );
    }
  }

  /// MusicGen 節點 — 生成音樂
  Future<NodeExecutionResult> _executeMusicGen(
    String nodeId,
    Map<String, dynamic> params,
    UpstreamData upstreamData
  ) async {
    if (musicGenerator == null) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: 'Music generator 未注入',
      );
    }

    var prompt = params['prompt']?.toString() ?? '';
    if (prompt.isEmpty && upstreamData.texts.isNotEmpty) {
      prompt = upstreamData.combinedText;
    }
    if (prompt.isEmpty) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '音樂生成需要 prompt 或上游輸入',
      );
    }

    try {
      final musicUrl = await musicGenerator!.generateMusic(
        prompt: prompt,
        model: params['model']?.toString(),
        duration: (params['duration'] as num?)?.toInt(),
        genre: params['genre']?.toString(),
      );
      return NodeExecutionResult(
        nodeId: nodeId,
        success: true,
        output: musicUrl,
      );
    } catch (e) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '音樂生成失敗: $e',
      );
    }
  }

  /// TTS 節點 — 語音合成
  /// 🥋 [Blue 拍板 2026-09-12] 招式執行——排程/無頭路徑
  /// 與 WorkflowExecutor 的 move 分支同邏輯：moveId 優先，moveName 模糊匹配。
  Future<NodeExecutionResult> _executeMove(
    String nodeId,
    Map<String, dynamic> params,
    UpstreamData upstreamData,
  ) async {
    final moveId = params['moveId']?.toString();
    final moveName = params['moveName']?.toString();
    final routines = await SystemRoutineStore.instance.list();
    SavedRoutine? move;
    if (moveId != null && moveId.isNotEmpty) {
      move = routines.where((r) => r.id == moveId).firstOrNull;
    }
    move ??= routines
        .where((r) => moveName != null && r.name.contains(moveName))
        .firstOrNull;
    if (move == null) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '找不到招式：${moveId ?? moveName ?? "（未指定）"}',
      );
    }
    final res = await SystemRoutinePlayer.instance.replay(move.events);
    return NodeExecutionResult(
      nodeId: nodeId,
      success: true,
      output: '招式「${move.name}」完成：${res.played} 步執行、${res.skipped} 步跳過',
    );
  }

  Future<NodeExecutionResult> _executeTts(
    String nodeId,
    Map<String, dynamic> params,
    UpstreamData upstreamData
  ) async {
    if (ttsClient == null) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: 'TTS client 未注入',
      );
    }

    var text = params['text']?.toString() ?? '';
    if (text.isEmpty && upstreamData.texts.isNotEmpty) {
      text = upstreamData.combinedText;
    }
    if (text.isEmpty) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '語音合成需要 text 或上游輸入',
      );
    }

    try {
      final audioUrl = await ttsClient!.synthesize(
        text: text,
        voice: params['voice']?.toString(),
        speed: (params['speed'] as num?)?.toDouble(),
      );
      return NodeExecutionResult(
        nodeId: nodeId,
        success: true,
        output: audioUrl,
      );
    } catch (e) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '語音合成失敗: $e',
      );
    }
  }

  /// Condition 節點 — 評估條件
  Future<NodeExecutionResult> _executeCondition(
    String nodeId,
    Map<String, dynamic> params,
    UpstreamData upstreamData
  ) async {
    final expression = params['expression']?.toString() ?? '';
    final trueLabel = params['trueLabel']?.toString() ?? 'true';
    final falseLabel = params['falseLabel']?.toString() ?? 'false';

    try {
      bool result;
      if (conditionEvaluator != null) {
        result = await conditionEvaluator!.evaluate(
          expression: expression,
          inputs: upstreamData.texts,
        );
      } else {
        // 簡易內建評估：檢查上游輸出是否包含特定字串
        final inputText = upstreamData.combinedText.toLowerCase();
        result = inputText.contains(expression.toLowerCase());
      }

      return NodeExecutionResult(
        nodeId: nodeId,
        success: true,
        output: result ? trueLabel : falseLabel,
      );
    } catch (e) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '條件評估失敗: $e',
      );
    }
  }

  /// SubWorkflow 節點 — 執行子工作流
  Future<NodeExecutionResult> _executeSubWorkflow(
    String nodeId,
    Map<String, dynamic> params,
    UpstreamData upstreamData
  ) async {
    if (subWorkflowRunner == null) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '子工作流執行器未注入',
      );
    }

    final workflowRef = params['workflowRef']?.toString() ?? '';
    if (workflowRef.isEmpty) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '未指定子工作流',
      );
    }

    try {
      final result = await subWorkflowRunner!.run(
        workflowRef: workflowRef,
        upstreamData: upstreamData,
      );
      return NodeExecutionResult(
        nodeId: nodeId,
        success: true,
        output: result,
      );
    } catch (e) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '子工作流執行失敗: $e',
      );
    }
  }

  /// [教練 Agent 2026-08-16] Knowledge 節點 — vault 向量庫檢索
  /// query（可含 {input} 佔位符帶入上游）→ VaultService.search →
  /// 命中條目組成帶來源標註的文字輸出，下游 LLM/merge 直接吃。
  Future<NodeExecutionResult> _executeKnowledge(
    String nodeId,
    Map<String, dynamic> params,
    UpstreamData upstreamData,
  ) async {
    var query = params['query']?.toString() ?? '';
    // 支援 {input} 佔位：上游有東西就帶入（動態查詢）
    if (query.contains('{input}') && upstreamData.combinedText.isNotEmpty) {
      query = query.replaceAll('{input}', upstreamData.combinedText);
    }
    if (query.trim().isEmpty) {
      query = upstreamData.combinedText; // 沒設 query 就拿上游全文當查詢
    }
    if (query.trim().isEmpty) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: '知識節點需要 query 或上游輸入',
      );
    }

    final mode = params['mode']?.toString() == 'fullText'
        ? VaultSearchMode.fullText
        : VaultSearchMode.semantic;
    final topK = (params['topK'] as num?)?.toInt() ?? 5;
    final room = params['room']?.toString() ?? '';
    final roomFilter = room.isEmpty ? null : room;

    try {
      final vault = VaultService.instance;
      vault.markInitialized(); // 若 BrainDatabase 已開就標可用，重複呼叫無害
      final entries = await vault.search(
        mode: mode,
        query: query,
        roomFilter: roomFilter,
        limit: topK,
      );

      if (entries.isEmpty) {
        return NodeExecutionResult(
          nodeId: nodeId,
          success: true,
          output: '（vault 查無結果：$query）',
        );
      }

      // 組成帶來源的知識文件
      final buf = StringBuffer();
      buf.writeln('以下是 vault 知識庫中「$query」的相關內容（${entries.length} 筆）：');
      buf.writeln();
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        final source = [
          if (e.room.isNotEmpty) e.room,
          if (e.subCategory.isNotEmpty) e.subCategory,
          if (e.agent.isNotEmpty) '紀錄者:${e.agent}',
        ].join(' · ');
        buf.writeln('── 來源 ${i + 1}${source.isEmpty ? '' : '（$source）'} ──');
        buf.writeln(e.content);
        buf.writeln();
      }
      return NodeExecutionResult(
        nodeId: nodeId,
        success: true,
        output: buf.toString(),
      );
    } catch (e) {
      return NodeExecutionResult(
        nodeId: nodeId,
        success: false,
        errorMessage: 'vault 檢索失敗: $e',
      );
    }
  }
}
