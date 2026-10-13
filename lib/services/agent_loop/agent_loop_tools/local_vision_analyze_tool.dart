/// local_vision_analyze 工具——呼叫本地 Gemma 4 E4B 做視覺分析
///
/// 向量工作流核心能力：原生 Agent用外部 LLM 當主大腦（指揮官），
/// 需要看圖分析時呼叫本地模型做視覺分析（執行者）。
///
/// 技術迴路：
/// 1. 讀取圖片檔案 → base64 編碼
/// 2. 組 OpenAI vision multimodal messages
/// 3. POST 到本地 llama-server (http://127.0.0.1:18789/v1/chat/completions)
/// 4. 回傳 Gemma 的分析結果
///
/// 錯誤處理：
/// - 本地 server 未啟動 → 提示使用者啟動
/// - 圖片不存在 → 回傳錯誤
/// - 120 秒 timeout

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../agent_tool.dart';

/// 本地視覺分析 server 的預設端點
const String _kLocalVisionBaseUrl = 'http://127.0.0.1:18789';

/// 預設分析指令
const String _kDefaultPrompt = '詳細描述這個影像畫面的內容';

/// local_vision_analyze AgentTool
///
/// 讓 LLM 能呼叫本地 Gemma 4 E4B 模型做視覺分析。
/// 這是向量工作流的核心——外部 LLM 指揮，本地模型執行視覺任務。
class LocalVisionAnalyzeTool extends AgentTool {
  final Dio _dio;

  /// [baseUrl] — 本地 llama-server 的 base URL（預設 http://127.0.0.1:18789）
  /// [dio] — 可注入 Dio 實例（測試用）
  LocalVisionAnalyzeTool({
    String baseUrl = _kLocalVisionBaseUrl,
    Dio? dio,
  }) : _dio = dio ?? Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 300),
          sendTimeout: const Duration(seconds: 30),
          headers: {'Content-Type': 'application/json'},
        ));

  @override
  String get name => 'local_vision_analyze';

  @override
  String get description =>
      '呼叫本地 Gemma 4 E4B 模型分析圖片內容。用於視覺理解——描述畫面、辨識物體、'
      '回答關於圖片的問題。支援任何常見圖片格式（PNG、JPEG 等）。'
      '這是向量工作流的執行者：你（主大腦）指揮，本地模型做視覺分析。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'image_path',
          description: '圖片檔案路徑（如 /tmp/screenshot.png）或 data URI（data:image/png;base64,...）',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'prompt',
          description: '分析指令，告訴本地模型要看什麼、分析什麼',
          defaultValue: _kDefaultPrompt,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final imagePath = args['image_path']?.toString();
    if (imagePath == null || imagePath.isEmpty) {
      return AgentToolResult.failure('image_path 為必填參數');
    }

    final prompt = (args['prompt']?.toString().isNotEmpty == true)
        ? args['prompt'].toString()
        : _kDefaultPrompt;

    try {
      // 取得 data URI——可能是 data:... 或檔案路徑
      final dataUri = await _resolveImageToDataUri(imagePath);

      // 查詢本地 server 可用模型
      final model = await _resolveModelName();

      // 組 OpenAI vision multimodal messages
      final requestBody = {
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {'url': dataUri},
              },
            ],
          },
        ],
        // [小葵 2026-09-28] 1024 → 1500：12B thinking 模型會先把 token 燒在
        // 推理段，1024 不足時 content 為空（bench 09-28 實測：800 全空、1500 穩定）
        'max_tokens': 1500,
        'temperature': 0.4,
      };

      // POST 到本地 llama-server
      final response = await _dio.post(
        '/v1/chat/completions',
        data: jsonEncode(requestBody),
      );

      final data = response.data as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        return AgentToolResult.failure('本地模型回應格式異常：choices 為空');
      }

      final message = (choices[0] as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
      var content = message?['content']?.toString() ?? '';
      // [小葵 2026-08-28] thinking 模型（Gemma-4 Uncensored）輸出在
      // reasoning_content，content 空——fallback 讀推理文本（視覺描述夠用）
      if (content.trim().isEmpty) {
        final reasoning = message?['reasoning_content']?.toString() ?? '';
        if (reasoning.trim().isNotEmpty) content = reasoning.trim();
      }

      if (content.isEmpty) {
        return AgentToolResult.failure('本地模型回應內容為空');
      }

      return AgentToolResult.success(
        content,
        metadata: {
          'model': model,
          'prompt': prompt,
          'image_path': imagePath,
        },
      );
    } on DioException catch (e) {
      // 連線被拒 = server 沒在跑
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return AgentToolResult.failure(
          '無法連接到本地視覺分析 server（http://127.0.0.1:18789）。'
          '請確認本地 llama-server 已啟動。\n'
          '啟動方式：在 Bridge App 的「本地模型」卡片中啟動 server，'
          '或手動執行 llama-server --port 18789 --model <gemma模型路徑>。\n'
          '詳細錯誤：${e.message}',
        );
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        return AgentToolResult.failure(
          '本地視覺分析逾時（120 秒）。模型可能正在載入或推理中，請稍後再試。',
        );
      }
      // HTTP 錯誤（4xx/5xx）
      final statusCode = e.response?.statusCode;
      final respBody = e.response?.data?.toString() ?? '';
      return AgentToolResult.failure(
        '本地視覺分析 server 回傳錯誤（HTTP $statusCode）：$respBody',
      );
    } on FileSystemException catch (e) {
      return AgentToolResult.failure('圖片檔案不存在或無法讀取：${e.path ?? imagePath}');
    } catch (e) {
      return AgentToolResult.failure('本地視覺分析失敗：$e');
    }
  }

  /// 將 image_path 解析為 data URI
  ///
  /// 支援兩種輸入：
  /// 1. data URI（data:image/...;base64,...）— 直接回傳
  /// 2. 檔案路徑— 讀取檔案、轉 base64、推斷 MIME type
  Future<String> _resolveImageToDataUri(String imagePath) async {
    // 已經是 data URI
    if (imagePath.startsWith('data:')) {
      return imagePath;
    }

    // 檔案路徑— 讀取並轉 base64
    final file = File(imagePath);
    if (!await file.exists()) {
      throw FileSystemException('圖片檔案不存在', imagePath);
    }

    final bytes = await file.readAsBytes();
    final base64Str = base64Encode(bytes);
    final mimeType = _inferMimeType(imagePath);

    return 'data:$mimeType;base64,$base64Str';
  }

  /// 從副檔名推斷 MIME type
  String _inferMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    // 預設用 PNG
    return 'image/png';
  }

  /// 查詢本地 server 取得可用模型名稱
  ///
  /// 呼叫 /v1/models，取第一個模型。
  /// 失敗時使用預設名稱 "gemma-3-e4b"（llama-server 通常接受任意 model 名稱）。
  Future<String> _resolveModelName() async {
    try {
      final response = await _dio.get('/v1/models');
      final data = response.data as Map<String, dynamic>;
      final models = data['data'] as List?;
      if (models != null && models.isNotEmpty) {
        final firstModel = models[0] as Map<String, dynamic>;
        final id = firstModel['id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    } catch (_) {
      // 查詢失敗不阻斷——用預設值繼續
    }
    return 'gemma-4-e4b';
  }
}
