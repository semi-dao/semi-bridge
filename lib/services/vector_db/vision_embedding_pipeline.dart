// vision_embedding_pipeline.dart
// [教練 Agent 2026-07-28] 圖片/影片向量嵌入管線
//
// 設計文件：vector-db-brain-fusion-design.md §決策 4
//
// 使用者拍板：
// - 用本地模型解析（local_vision_analyze），生成文字描述後再做向量嵌入
// - 背景慢慢做完
// - 畫面上顯示進度條並提醒使用者不要關機
//
// 圖片流程：
//   讀取 → local_vision_analyze → 描述文字 → EmbeddingGemma → embedding BLOB → UPDATE asset_index
//
// 影片流程：
//   frame_extract → 每幀 local_vision_analyze → 彙整描述 → EmbeddingGemma → embedding BLOB → UPDATE asset_index
//
// 進度條分階段：
//   「正在解析圖片內容...」「正在生成向量嵌入...」
//
// 不可中斷提醒：「嵌入中，請勿關機」

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../brain_container/brain_database.dart';
import '../brain_container/brain_container_service.dart';
import '../local_model_scheduler.dart'; // [小葵 2026-10-01] 離合器安全點標記
import '../brain_container/embedding/embedding_service.dart';
import '../sovereignty/data_path_gate.dart';
import '../sovereignty/data_path_interceptor.dart';
import '../storage_service.dart';
import '../agent_loop/agent_loop_tools/local_vision_analyze_tool.dart';
import 'asset_sandbox.dart';
import 'path_hint_extractor.dart';
import 'identity_embed_text.dart';
import '../agent_loop/agent_loop_tools/frame_extract_tool.dart';

// ═══════════════════════════════════════════════════════════
// 進度追蹤
// ═══════════════════════════════════════════════════════════

/// 管線執行階段
enum VisionPipelineStage {
  idle,           // 待命
  analyzing,      // 正在解析圖片/影片內容
  embedding,      // 正在生成向量嵌入
  done,           // 完成
  error,          // 錯誤
}

/// 管線進度事件（透過 Stream 推送給 UI）
class VisionPipelineProgress {
  final VisionPipelineStage stage;
  final int current;
  final int total;
  final String message;
  final String? currentFileName;

  const VisionPipelineProgress({
    required this.stage,
    required this.current,
    required this.total,
    required this.message,
    this.currentFileName,
  });

  /// 進度百分比 0.0 ~ 1.0
  double get fraction => total > 0 ? current / total : 0.0;

  /// 不可中斷提醒
  static const String doNotTurnOffWarning = '嵌入中，請勿關機';

  @override
  String toString() =>
      'VisionPipelineProgress($stage $current/$total $message)';
}

// ═══════════════════════════════════════════════════════════
// VisionEmbeddingPipeline
// ═══════════════════════════════════════════════════════════

/// 圖片/影片向量嵌入管線
///
/// 作為 AssetIndexService 的擴充，專門處理圖片和影片的向量嵌入。
///
/// 使用方式：
/// ```dart
/// final pipeline = VisionEmbeddingPipeline.instance;
/// pipeline.progressStream.listen((progress) {
///   // 更新 UI 進度條
/// });
/// await pipeline.processPendingVisionAssets();
/// ```
///
/// 依賴：
/// - LocalVisionAnalyzeTool（本地 Gemma 4 E4B 視覺分析）
/// - FrameExtractTool（ffmpeg 影片截圖）
/// - EmbeddingService（EmbeddingGemma 300M 向量嵌入）
/// - BrainDatabase（asset_index 表）
class VisionEmbeddingPipeline {
  /// [資料主權 09-15] 匯入泡泡的模式選擇（null=用預設雲端優先）。
  /// SovereigntyImportBubble 選「全本地」時設為 localOnly——
  /// 這批嵌入不出這台機器；run 結束由呼叫端清除。
  bool localOnlyOverride = false;

  static final VisionEmbeddingPipeline instance =
      VisionEmbeddingPipeline._();

  VisionEmbeddingPipeline._();

  // ── 工具實例 ──────────────────────────────────────────

  final LocalVisionAnalyzeTool _visionTool = LocalVisionAnalyzeTool();
  final FrameExtractTool _frameExtractTool = FrameExtractTool();
  final EmbeddingService _embedder = EmbeddingService.instance;

  // ── 進度追蹤 ──────────────────────────────────────────

  final StreamController<VisionPipelineProgress> _progressController =
      StreamController<VisionPipelineProgress>.broadcast();

  /// 進度 Stream — UI 監聽此 stream 更新進度條
  Stream<VisionPipelineProgress> get progressStream =>
      _progressController.stream;

  /// 目前是否正在執行
  bool get isRunning => _currentStage == VisionPipelineStage.analyzing ||
      _currentStage == VisionPipelineStage.embedding;

  VisionPipelineStage _currentStage = VisionPipelineStage.idle;
  VisionPipelineStage get currentStage => _currentStage;

  /// 推送進度事件
  void _emitProgress(
    VisionPipelineStage stage,
    int current,
    int total,
    String message, {
    String? currentFileName,
  }) {
    _currentStage = stage;
    _progressController.add(VisionPipelineProgress(
      stage: stage,
      current: current,
      total: total,
      message: message,
      currentFileName: currentFileName,
    ));
  }

  // ── 圖片副檔名集合 ────────────────────────────────────

  static const _imageExtensions = [
    '.jpg', '.jpeg', '.png', '.webp', '.heic', '.gif', '.svg', '.bmp',
  ];

  static const _videoExtensions = [
    '.mp4', '.mov', '.avi', '.mkv',
  ];

  /// 判斷是否為圖片
  bool _isImage(String ext) => _imageExtensions.contains(ext.toLowerCase());

  /// 判斷是否為影片
  bool _isVideo(String ext) => _videoExtensions.contains(ext.toLowerCase());

  // ═════════════════════════════════════════════════════════
  // 主要入口
  // ═════════════════════════════════════════════════════════

  /// 處理所有待嵌入的圖片/影片檔案
  ///
  /// 從 asset_index 表讀取 index_status = 'pending' 且 asset_kind 為
  /// image 或 video 的記錄，逐一做視覺分析 + 向量嵌入。
  ///
  /// [rootPath] — 限定根資料夾（null = 處理所有資料夾）
  /// 回傳成功處理的檔案數
  Future<int> processPendingVisionAssets({String? rootPath}) async {
    if (!BrainContainerService.instance.isInitialized) {
      debugPrint('[VisionPipeline] BrainContainer 未初始化，跳過');
      return 0;
    }

    // [小葵 2026-10-01 離合器步驟7] 嵌入 job 進行中標記——
    // LocalModelScheduler 據此判斷安全點（item 邊界）；
    // 使用者發話時等當前 item 做完才切回夥伴模型。
    LocalModelScheduler.instance.visionJobActive = true;

    // 確認 embedding 模型可用
    if (!_embedder.isModelAvailable) {
      debugPrint('[VisionPipeline] Embedding 模型未安裝，跳過');
      _emitProgress(VisionPipelineStage.error, 0, 0,
          'Embedding 模型未安裝，無法進行向量嵌入');
      LocalModelScheduler.instance.visionJobActive = false;
      return 0;
    }

    // 從 DB 讀取待處理的圖片/影片
    final records = _fetchPendingVisionAssets(rootPath);
    if (records.isEmpty) {
      debugPrint('[VisionPipeline] 無待處理的圖片/影片');
      _emitProgress(VisionPipelineStage.done, 0, 0, '無待處理的圖片/影片');
      LocalModelScheduler.instance.visionJobActive = false;
      return 0;
    }

    debugPrint('[VisionPipeline] 開始處理 ${records.length} 個圖片/影片檔案');

    var success = 0;
    var total = records.length;

    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      final fileName = record['file_name']?.toString() ?? '';
      final filePath = record['file_path']?.toString() ?? '';
      final folderRoot = record['folder_root']?.toString() ?? '';
      final fileExt = (record['file_ext']?.toString() ?? '').toLowerCase();

      final fullPath = '$folderRoot/$filePath';

      try {
        // ── 階段 1：解析內容 ──
        _emitProgress(
          VisionPipelineStage.analyzing,
          i,
          total,
          _isVideo(fileExt) ? '正在解析影片內容...' : '正在解析圖片內容...',
          currentFileName: fileName,
        );

        String description;
        if (_isVideo(fileExt)) {
          description = await _analyzeVideo(fullPath, fileName, i, total);
        } else {
          description = await _analyzeImage(fullPath);
        }

        if (description.isEmpty) {
          debugPrint('[VisionPipeline] 描述為空，跳過 ($fileName)');
          continue;
        }

        // ── 階段 2：生成向量嵌入 ──
        _emitProgress(
          VisionPipelineStage.embedding,
          i,
          total,
          '正在生成向量嵌入...',
          currentFileName: fileName,
        );

        final embeddingResult = await _embedder.embedOne(description);

        // 寫入 DB
        _updateAssetInDb(filePath, description, embeddingResult.vector);

        success++;
        debugPrint('[VisionPipeline] ✅ 完成 ($fileName)');
      } catch (e) {
        debugPrint('[VisionPipeline] ❌ 失敗 ($fileName): $e');
        // 標記為 error
        _markAssetError(filePath, e.toString());
      }
    }

    // ── 完成 ──
    _emitProgress(
      VisionPipelineStage.done,
      total,
      total,
      '向量嵌入完成（$success/$total 成功）',
    );

    debugPrint('[VisionPipeline] 全部完成: $success/$total 成功');
    // [小葵 2026-10-01 離合器步驟7] job 結束——安全點，Scheduler 可切回夥伴
    LocalModelScheduler.instance.visionJobActive = false;
    return success;
  }

  // ═════════════════════════════════════════════════════════
  // 圖片分析
  // ═════════════════════════════════════════════════════════

  /// 分析單張圖片，回傳文字描述
  // ═══════════════════════════════════════════════════════
  // [教練 Agent 2026-07-31] 圖片分析 — 改用 OpenAI GPT-4o-mini 雲端 API
  // 原因：本地視覺模型太慢（25秒/張）+ 吃記憶體
  // GPT-4o-mini：~1秒/張，NT$14 跑完全部 2352 張
  // ═══════════════════════════════════════════════════════

  Future<String> _analyzeImage(String imagePath) async {
    // [小葵 2026-09-14] 預設路由定案（Blue 09-14 盲測拍板）：
    // 雲端優先、本地 fallback。決策鏈——07-28 Blue 拍板本地優先 →
    // 07-31 被靜默翻案雲端優先（misalignment 活證）→ 09-14 止血翻回本地 →
    // 09-14 盲測 benchmark（20張品種級正確率 本地2/20 vs 雲端10/20、8x速度差）
    // Blue 親自盲評後拍板：雲端優先。本地保留為無網路/無金鑰/機密照片的
    // 主權選項（此註解即路由變更的明示紀錄，不是靜默翻案）。
    // 詳情：docs/benchmarks/vision-blind-2026-09-14-*

    // 雲端優先：OpenAI gpt-4o-mini（金鑰匙 + DataPathGate 黃燈記帳）
    // [主權模式 09-15] 使用者在匯入泡泡選「全本地」→ 跳過雲端直走本地
    if (!localOnlyOverride) {
    try {
      final cloudResult = await _analyzeImageWithOpenAI(imagePath);
      if (cloudResult.isNotEmpty) return cloudResult;
      debugPrint('[VisionPipeline] 雲端分析失敗，fallback 本地');
    } catch (e) {
      debugPrint('[VisionPipeline] 雲端分析異常（$e），fallback 本地');
    }
    } // !localOnlyOverride

    // Fallback: 本地視覺模型（主權選項——無金鑰/無網路/機密照片）
    final result = await _visionTool.execute({
      'image_path': imagePath,
      // [路徑提示注入 09-14] 本地 fallback 同樣注入（防幻覺護欄內建）
      'prompt': PathHintExtractor.instance.buildPrompt(
        '詳細描述這個影像畫面的內容，包括場景、物體、人物、'
            '色彩、構圖和氛圍。用於建立可搜尋的文字索引。',
        imagePath,
      ),
    });
    if (result.success && result.content.trim().isNotEmpty) {
      return result.content.trim();
    }

    throw VisionAnalysisException(
      '圖片視覺分析失敗（雲端與本地皆失敗）',
    );
  }

  /// [資料主權 P0-b 2026-09-14] key 走金鑰匙（StorageService/Keychain 鏈）。
  /// 廢除 ~/.openai_key 明文檔讀取（B1 暗管殘留）。
  /// 金鑰匙原則：鑰匙鎖定後四處通行——此處自動偵測已設金鑰。
  static Future<String?> _goldenKeyForOpenAI() async {
    final token = await StorageService.getToken(provider: 'openai');
    if (token == null || token.trim().isEmpty) return null;
    return token.trim();
  }

  /// [資料主權 P0-b 2026-09-14] 雲端視覺呼叫的統一閘道 Dio——
  /// 過 DataPathGate（image/vision），red 直接攔截。
  static final Dio _cloudDio = _createCloudDio();

  static Dio _createCloudDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 45),
      headers: {'Content-Type': 'application/json'},
    ));
    dio.interceptors.add(SovereigntyInterceptor(
      dataClass: DataPathClass.image,
      purpose: DataPathPurpose.vision,
    ));
    return dio;
  }

  /// [教練 Agent 2026-07-31] OpenAI GPT-4o-mini 圖片描述
  Future<String> _analyzeImageWithOpenAI(String imagePath) async {
    final apiKey = await _goldenKeyForOpenAI();
    if (apiKey == null) {
      throw Exception('OpenAI 金鑰未設定（金鑰匙）——照片不上雲');
    }

    // 讀取圖片 → base64
    final bytes = await File(imagePath).readAsBytes();
    final base64Image = base64Encode(bytes);
    final ext = imagePath.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
    final dataUrl = 'data:image/$ext;base64,$base64Image';

    final response = await _cloudDio.post(
      'https://api.openai.com/v1/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
      data: {
        'model': 'gpt-4o-mini',
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                // [路徑提示注入 09-14] 資料夾結構=使用者的提示（零設定），
                // 品種/專案/地點名讓模型「比對確認」而非「看圖猜謎」。
                // 基準：注入後蕨類 0/10 → 目標 10/10（答案在路徑裡）。
                'text': PathHintExtractor.instance.buildPrompt(
                  '詳細描述這個影像畫面的內容，包括場景、物體、人物、'
                      '色彩、構圖和氛圍。用於建立可搜尋的文字索引。'
                      '請用繁體中文回答，200字以內。',
                  imagePath,
                ),
              },
              {
                'type': 'image_url',
                'image_url': {'url': dataUrl, 'detail': 'low'},
              },
            ],
          },
        ],
        'max_tokens': 300,
        'temperature': 0.2,
      },
    );

    if (response.statusCode == 200) {
      final text = response.data['choices'][0]['message']['content'] as String?;
      return text?.trim() ?? '';
    }

    throw Exception('OpenAI API error: ${response.statusCode}');
  }

  // ═════════════════════════════════════════════════════════
  // 影片分析
  // ═════════════════════════════════════════════════════════

  /// 分析影片：智慧截圖（場景偵測 threshold=0.8）→ 批次分析
  /// [教練 Agent 2026-08-01] 修正：threshold 0.4→0.8（截太多幀），逐幀→批次（慢→快）
  /// 參考 skill:video-analysis 方法 B
  Future<String> _analyzeVideo(
    String videoPath,
    String fileName,
    int currentIndex,
    int total,
  ) {
    return _analyzeVideoSmart(videoPath, fileName);
  }

  /// [教練 Agent 2026-08-01] 智慧影片分析
  /// 1. ffmpeg 場景偵測 threshold=0.8（只截真正大幅切換）
  /// 2. 上限 5 幀（超過則均勻取樣）
  /// 3. 一次送所有幀給 OpenAI GPT-4o-mini（批次分析，不等逐幀）
  Future<String> _analyzeVideoSmart(String videoPath, String fileName) async {
    debugPrint('[VisionPipeline] 影片智慧截圖: $fileName');

    // Step 1: 場景偵測（threshold=0.8 = 只截大幅切換）
    final frameResult = await _frameExtractTool.execute({
      'video_path': videoPath,
      'threshold': '0.8',
    });

    if (!frameResult.success) {
      throw VisionAnalysisException('影片截幀失敗: ${frameResult.content}');
    }

    var framePaths = (frameResult.metadata?['frame_paths'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    if (framePaths.isEmpty) {
      // 至少截第 0 秒
      framePaths = ['/tmp/frame_001.jpg'];
    }

    // Step 2: 上限 5 幀（超過則均勻取樣）
    if (framePaths.length > 5) {
      final step = framePaths.length / 5;
      final sampled = <String>[];
      for (var i = 0; i < 5; i++) {
        final idx = (i * step).floor();
        sampled.add(framePaths[idx]);
      }
      framePaths = sampled;
    }

    debugPrint('[VisionPipeline] 影片 $fileName → ${framePaths.length} 張關鍵幀');

    // [小葵 2026-09-14] 資料主權止血：本地優先——逐幀本地視覺分析
    try {
      final localDescs = <String>[];
      for (final fp in framePaths.take(3)) {
        final r = await _visionTool.execute({
          'image_path': fp,
          'prompt': '詳細描述這個影像畫面的內容，包括場景、物體、人物、'
              '色彩、構圖和氛圍。用於建立可搜尋的文字索引。',
        });
        if (r.success && r.content.trim().isNotEmpty) {
          localDescs.add(r.content.trim());
        }
      }
      if (localDescs.isNotEmpty) {
        return _summarizeFrameDescriptions(fileName, localDescs);
      }
    } catch (e) {
      debugPrint('[VisionPipeline] 本地影片分析失敗，fallback 雲端: $e');
    }

    // Fallback: 批次送 OpenAI 分析所有幀（僅在本地失敗時）
    try {
      final description = await _analyzeVideoFramesWithOpenAI(videoPath, framePaths, fileName);
      if (description.isNotEmpty) return description;
    } catch (e) {
      debugPrint('[VisionPipeline] OpenAI 批次分析失敗，fallback 單幀: $e');
    }

    // Fallback: 逐幀分析（只跑第一幀）
    if (framePaths.isNotEmpty) {
      return _analyzeImageWithOpenAI(framePaths.first);
    }

    throw VisionAnalysisException('影片分析失敗：無法取得描述');
  }

  /// [教練 Agent 2026-08-01] OpenAI GPT-4o-mini 批次分析多幀
  Future<String> _analyzeVideoFramesWithOpenAI(
    String videoPath,
    List<String> framePaths,
    String fileName,
  ) async {
    final apiKey = await _goldenKeyForOpenAI();
    if (apiKey == null) {
      throw Exception('OpenAI 金鑰未設定（金鑰匙）——影片幀不上雲');
    }

    // 組裝 multimodal content：文字 prompt + 多張圖片
    final content = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': '這是影片「$fileName」的 ${framePaths.length} 張關鍵畫面截圖。'
            '請綜合分析這部影片的內容：場景、人物、動作、物件、氛圍。'
            '用於建立可搜尋的文字索引。請用繁體中文回答，200字以內。',
      },
    ];

    for (final framePath in framePaths) {
      final bytes = await File(framePath).readAsBytes();
      final base64Image = base64Encode(bytes);
      content.add({
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,$base64Image', 'detail': 'low'},
      });
    }

    final response = await _cloudDio.post(
      'https://api.openai.com/v1/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 45),
      ),
      data: {
        'model': 'gpt-4o-mini',
        'messages': [
          {'role': 'user', 'content': content},
        ],
        'max_tokens': 300,
        'temperature': 0.2,
      },
    );

    if (response.statusCode == 200) {
      final text = response.data['choices'][0]['message']['content'] as String?;
      return text?.trim() ?? '';
    }

    throw Exception('OpenAI API error: ${response.statusCode}');
  }

  /// 彙整多幀描述為一段完整文字
  String _summarizeFrameDescriptions(
    String fileName,
    List<String> descriptions,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('影片: $fileName');
    buffer.writeln('共分析 ${descriptions.length} 個關鍵幀');
    buffer.writeln('---');
    for (final desc in descriptions) {
      buffer.writeln(desc);
    }
    buffer.writeln('---');
    buffer.writeln('影片內容摘要: 以上為影片中 ${descriptions.length} 個'
        '場景變化點的畫面描述。');

    // 截斷過長的描述（embedding 模型輸入限制）
    final result = buffer.toString();
    if (result.length > 8000) {
      return result.substring(0, 8000);
    }
    return result;
  }

  // ═════════════════════════════════════════════════════════
  // DB 操作
  // ═════════════════════════════════════════════════════════

  /// 從 asset_index 表讀取待處理的圖片/影片記錄
  List<Map<String, dynamic>> _fetchPendingVisionAssets(String? rootPath) {
    final db = BrainDatabase.instance.db;

    final whereClause = rootPath != null
        ? "index_status = 'pending' AND asset_kind IN ('image', 'video') "
            "AND folder_root = ?"
        : "index_status = 'pending' AND asset_kind IN ('image', 'video')";

    final args = rootPath != null ? [rootPath] : <String>[];

    // [小葵 2026-10-01 離合器步驟7] pending 計數注入 Scheduler——
    // 系統活動中心「待辨識 N 張」與離合器評估的資料源（單一真相：DB）
    try {
      final count = db.select(
        'SELECT COUNT(*) as n FROM asset_index WHERE $whereClause',
        args,
      ).first['n'] as int;
      LocalModelScheduler.instance.updatePendingVisionCount(count);
    } catch (_) {} // 計數失敗不擋主流程

    try {
      final results = db.select(
        'SELECT id, file_path, folder_root, file_name, file_ext, asset_kind '
        'FROM asset_index WHERE $whereClause '
        'ORDER BY file_size ASC', // 小檔案先做
        args,
      );
      return results;
    } catch (e) {
      debugPrint('[VisionPipeline] 查詢待處理記錄失敗: $e');
      return [];
    }
  }

  /// 更新 asset_index：寫入 embedding + 描述文字 + 狀態
  void _updateAssetInDb(
    String filePath,
    String description,
    List<double> vector, {
    List<String>? tags,
  }) {
    final db = BrainDatabase.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    db.execute(
      "UPDATE asset_index SET "
      "  embedding = vector_as_f32(?), "
      "  content_text = ?, "
      "  summary = ?, "
      "  embed_source = 'content', "
      "  index_status = 'indexed', "
      "  indexed_at = ? "
      "${tags != null && tags.isNotEmpty ? ', tags = ?' : ''} "
      "WHERE file_path = ? "
      "  AND COALESCE(embed_source, '') != 'identity'",
      [
        jsonEncode(vector),
        description,
        description.length > 200
            ? '${description.substring(0, 200)}...'
            : description,
        now,
        if (tags != null && tags.isNotEmpty) jsonEncode(tags),
        filePath,
      ],
    );
  }

  /// 標記檔案為錯誤狀態
  void _markAssetError(String filePath, String error) {
    final db = BrainDatabase.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      db.execute(
        "UPDATE asset_index SET "
        "  index_status = 'error', "
        "  indexed_at = ? "
        "WHERE file_path = ?",
        [now, filePath],
      );
    } catch (e) {
      debugPrint('[VisionPipeline] 標記錯誤狀態失敗: $e');
    }
  }

  // ═════════════════════════════════════════════════════════
  // 便捷方法
  // ═════════════════════════════════════════════════════════

  /// 處理單個圖片/影片檔案的向量嵌入
  ///
  /// 由 AssetIndexService 的統一嵌入流程呼叫，
  /// 也可用於手動觸發重新嵌入。
  ///
  /// [filePath] — 相對於根資料夾的路徑（DB 裡的 file_path）
  /// [folderRoot] — 根資料夾路徑
  /// [fileName] — 檔名
  /// [fileExt] — 副檔名（含 '.'，如 '.jpg'）
  Future<bool> processSingleAsset({
    required String filePath,
    required String folderRoot,
    required String fileName,
    required String fileExt,
  }) async {
    if (!BrainContainerService.instance.isInitialized) {
      debugPrint('[VisionPipeline] BrainContainer 未初始化');
      return false;
    }

    if (!_embedder.isModelAvailable) {
      debugPrint('[VisionPipeline] Embedding 模型未安裝');
      return false;
    }

    final ext = fileExt.toLowerCase();
    if (!_isImage(ext) && !_isVideo(ext)) {
      debugPrint('[VisionPipeline] 非圖片/影片: $fileExt');
      return false;
    }

    final fullPath = '$folderRoot/$filePath';

    try {
      String description;
      if (_isVideo(ext)) {
        description = await _analyzeVideo(fullPath, fileName, 0, 1);
      } else {
        description = await _analyzeImage(fullPath);
      }

      if (description.isEmpty) {
        debugPrint('[VisionPipeline] 描述為空，跳過 ($fileName)');
        return false;
      }

      // [小葵 2026-09-09 Blue v2 檢索令] 身份嵌入——五因素織進向量
      // （資料夾/分類/任務/屬性/內容），IdentityEmbedText 單一真相
      final enriched = await IdentityEmbedText.instance.build(
        relPath: filePath,
        folderRoot: folderRoot,
        content: description,
      );
      final embeddingResult = await _embedder.embedOne(enriched);

      // 直接用 filePath（相對路徑）更新 DB
      _updateAssetInDb(filePath, enriched, embeddingResult.vector,
          tags: AssetSandbox.pathTags(filePath, folderRoot));

      debugPrint('[VisionPipeline] ✅ 完成 ($fileName)');
      return true;
    } catch (e) {
      debugPrint('[VisionPipeline] ❌ 失敗 ($fileName): $e');
      _markAssetError(filePath, e.toString());
      return false;
    }
  }

  /// 釋放資源
  void dispose() {
    _progressController.close();
  }
}

// ═══════════════════════════════════════════════════════════
// 例外
// ═══════════════════════════════════════════════════════════

/// 視覺分析例外
class VisionAnalysisException implements Exception {
  final String message;
  VisionAnalysisException(this.message);

  @override
  String toString() => 'VisionAnalysisException: $message';
}
