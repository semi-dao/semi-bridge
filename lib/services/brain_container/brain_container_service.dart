// brain_container_service.dart
// 大腦容器門面服務 — 統一入口，封裝寫入/檢索管線
// 建立日期: 2026-07-03 by 教練 Agent (CEO)
//
// 這是 app 與大腦容器之間的唯一介面。
// chat_controller 和其他服務只需要呼叫 BrainContainerService，
// 不需要知道內部的 pipeline / repository / detector 結構。

import 'dart:async';
import 'dart:convert';

import 'package:bridge_app/services/vector_db/incremental_ingest_service.dart';
import 'package:flutter/foundation.dart';

import '../activity/background_task_registry.dart';

import 'package:bridge_app/models/brain_container/brain_room.dart';
import 'package:bridge_app/models/brain_container/connection.dart';
import 'package:bridge_app/models/brain_container/memory.dart';
import 'persistence/memory_file_backfill_service.dart';
// [小葵 2026-10-13 K1 修復線] K1 頭還原
import '../decision/k1_bootstrapper.dart';
import 'package:bridge_app/models/brain_container/memory_source.dart';
import 'package:bridge_app/services/brain_container/brain_database.dart';
import 'package:bridge_app/services/brain_container/asset_reembed_service.dart';
import 'package:bridge_app/services/brain_container/asset_content_reembed_service.dart'; // [小葵 2026-08-28] 內容重嵌
import 'package:bridge_app/services/brain_container/asset_file_backfill_service.dart'; // [小葵 2026-08-28] 落網文字檔補嵌
import 'package:bridge_app/services/brain_container/design_file_thumbnail_service.dart'; // [小葵 2026-08-28] 專業製圖檔
import 'package:bridge_app/services/brain_container/pdf_content_backfill_service.dart'; // [小葵 2026-08-28] PDF 解析器
import 'package:bridge_app/services/brain_container/ingest_backfill_service.dart';
import 'package:bridge_app/services/brain_container/memory_asset_link_backfill_service.dart';
import 'package:bridge_app/services/vector_db/agent_memory_backfill_service.dart';
import 'package:bridge_app/services/vector_db/folder_origin_service.dart'; // [小葵 2026-09-09] 資料夾身份
import 'package:bridge_app/services/vector_db/identity_reembed_service.dart'; // [小葵 2026-09-09] 身份重嵌
import 'package:bridge_app/services/vector_db/asset_chunk_backfill_service.dart';
import 'package:bridge_app/services/brain_container/connections/connection_detector.dart';
import 'package:bridge_app/services/brain_container/connections/connection_repository.dart';
import 'package:bridge_app/services/vector_db/cross_reference_service.dart';
import 'package:bridge_app/services/brain_container/decay/memory_decay_service.dart';
import 'package:bridge_app/services/brain_container/embedding/embedding_service.dart';
import 'package:bridge_app/services/brain_container/growth/room_growth_updater.dart';
import 'package:bridge_app/services/brain_container/persistence/memory_writer.dart';
import 'package:bridge_app/services/brain_container/persistence/memory_draft.dart';
import 'package:bridge_app/services/brain_container/transurfing_engine.dart';
import 'package:bridge_app/services/brain_container/pipeline/memory_retrieval_pipeline.dart';
import 'package:bridge_app/services/brain_container/pipeline/memory_write_pipeline.dart';
import 'package:bridge_app/services/brain_container/preprocessing/content_preprocessor.dart';
import 'package:bridge_app/services/brain_container/profile/user_profile_service.dart';

/// 大腦容器門面服務（單例）。
///
/// 負責：
/// 1. 在 app 啟動時初始化所有大腦容器元件
/// 2. 提供 `writeMemory()` 寫入記憶（經完整管線：預處理→嵌入→分類→寫入→連結→生長）
/// 3. 提供 `retrieveMemories()` 檢索記憶（向量搜尋→關聯展開→理由標記）
/// 4. 提供 `getFormattedContext()` 取得格式化記憶上下文（供 system prompt 注入）
/// 5. 所有操作都有 try-catch，不會讓大腦容器故障導致 app 崩潰
class BrainContainerService {
  BrainContainerService._();
  static final BrainContainerService instance = BrainContainerService._();

  // --- 內部元件 ---
  late final BrainDatabase _database;
  late final EmbeddingService _embedder;
  late final ContentPreprocessor _preprocessor;
  late final MemoryWriter _writer;
  late final ConnectionRepository _connectionRepo;
  late final ConnectionDetector _connectionDetector;
  late final RoomGrowthUpdater _growthUpdater;
  late final MemoryDecayService _decayService;
  late final MemoryWritePipeline _writePipeline;
  late final MemoryRetrievalPipeline _retrievalPipeline;

  /// [教練 Agent 2026-08-08] Transurfing Engine 的持久化 key
  static const _transurfingMetaKey = 'transurfing_state';

  bool _initialized = false;
  Future<void>? _initializing;

  /// 是否已初始化完成
  bool get isInitialized => _initialized;

  /// embedding 模型是否可用（非 fallback）
  bool get isModelAvailable => _embedder.isModelAvailable;

  /// 初始化大腦容器。
  ///
  /// 在 app 啟動時呼叫一次。冪等——重複呼叫不會出錯。
  /// 任何環節失敗都會被 catch，不會讓 app 啟動失敗。
  Future<void> initialize() async {
    if (_initialized) return;

    // 與 BrainDatabase 相同：所有 caller 共用同一輪非同步初始化，
    // 不能同時建立多組 pipeline / native SQLite handle。
    final inFlight = _initializing;
    if (inFlight != null) return inFlight;

    final future = _initializeOnce();
    _initializing = future;
    try {
      await future;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initializeOnce() async {
    if (_initialized) return;

    try {
      // 1. 資料庫
      _database = BrainDatabase.instance;
      await _database.initialize();

      // 2. Embedding 服務
      _embedder = EmbeddingService.instance;
      await _embedder.initialize();

      // 2.5 [小葵 2026-10-13 K1 修復線] 還原 K1 決策頭（權重檔在
      // brain_state/k1_head.json；無檔時 K1 走規則層+escalate 不阻擋啟動）
      K1Bootstrapper.instance.restoreFromStore();

      // 3. 管線元件
      _preprocessor = ContentPreprocessor();
      _writer = MemoryWriter(database: _database);
      _connectionRepo = ConnectionRepository(database: _database);
      _connectionDetector = ConnectionDetector(
        repo: _connectionRepo,
        database: _database,
      );
      _growthUpdater = RoomGrowthUpdater(database: _database);
      _decayService = MemoryDecayService(database: _database);

      // 4. 管線
      _writePipeline = MemoryWritePipeline(
        preprocessor: _preprocessor,
        embedder: _embedder,
        writer: _writer,
        connectionDetector: _connectionDetector,
      );
      _retrievalPipeline = MemoryRetrievalPipeline(
        embedder: _embedder,
        connectionRepo: _connectionRepo,
      );

      _initialized = true;
      // [教練 Agent 2026-08-08] 恢復 Transurfing 水流狀態
      loadTransurfingState();

      // [教練 Agent 2026-08-20] P1-4 背景導入（使用者：APP 24/7 開機、利用
      // 閒置時機慢慢崁入）——v10 三欄位回填（純規則推導，不燒 LLM），
      // 500 筆/批＋200ms 讓出，不搶前景資源。冪等：無待辦即靜默。
      Future.delayed(const Duration(seconds: 1), () {
        IngestBackfillService.instance.start();
      });
      // [小葵 2026-09-09 Blue v2 檢索令] 資料夾身份回填（純規則推導，
      // 冪等——已存在的 folder_path 跳過）。身份嵌入與分組檢索的資料源。
      Future.delayed(const Duration(seconds: 5), () {
        FolderOriginService.instance.backfillFromAssetIndex();
      });
      // [小葵 2026-09-09 Blue v2 檢索令] 全量身份重嵌（冪等——只處理
      // 還不是 identity 的筆數）。延遲 120s：等 folder_origin 先回填。
      // [小葵 2026-09-30 金礦1] 掛牌系統活動中心——背景任務不再是隱形的
      Future.delayed(const Duration(seconds: 120), () {
        IdentityReembedReporter.attach();
        IdentityReembedService.instance.start();
      });
      // [教練 Agent 2026-08-20] 鐵三角 #6——memory_asset_links 回填。
      // 前置：#3 asset_vector_init 已在同一 initialize() 內完成（同步）。
      // 延遲 30 秒：等 IngestBackfill（display_title 等）先跑，且避開
      // 啟動尖峰；vector_full_scan 全掃較重，放更閒的時機。
      Future.delayed(const Duration(seconds: 30), () {
        MemoryAssetLinkBackfillService.instance.start();
      });
      // [教練 Agent 2026-08-20] 鐵三角 #2+#4——22484 假向量重嵌（中繼文字）。
      // 延遲 60 秒：等 links 回填先跑完（它吃舊向量建立基準邊），
      // 重嵌後的向量品質更好，之後重跑 links 回填會得到更好的邊。
      // 冪等：embed_source 標記守門；模型 fallback 時靜默跳過。
      Future.delayed(const Duration(seconds: 60), () {
        AssetReembedService.instance.start();
      });
      // [小葵 2026-08-28] Blue 開工 A——內容重嵌：embed_source='metadata' 但
      // content_text 有真內容的，用內容重嵌（治本）。冪等：'content' 標記守門。
      Future.delayed(const Duration(seconds: 120), () {
        AssetContentReembedService.instance.start();
      });
      // [小葵 2026-08-28] 不擠牙膏二期：落網文字檔（content_text 空）補讀補嵌。
      // 排在內容重嵌之後（150s）——它處理的是 content_text 為空的批次。
      Future.delayed(const Duration(seconds: 150), () {
        AssetFileBackfillService.instance.start();
      });
      // [小葵 2026-08-28] 專業製圖檔（.skp/.dwg/.psd）縮圖→Vision→嵌入
      Future.delayed(const Duration(seconds: 180), () {
        DesignFileThumbnailService.instance.start();
      });
      // [小葵 2026-08-28] PDF 文字抽取補嵌（Blue：未來使用者主力格式）
      Future.delayed(const Duration(seconds: 200), () {
        PdfContentBackfillService.instance.start();
      });
      // [教練 Agent 2026-08-21] 鐵三角二期 #1——asset_chunks 切片回填。
      // 延遲 90 秒：排在 reembed 之後（長文件重嵌完再切片，切片
      // 內容與 asset_index 一致）。冪等：有 chunk 的資產跳過。
      Future.delayed(const Duration(seconds: 90), () {
        AssetChunkBackfillService.instance.start();
      });
      // [教練 Agent 2026-08-21] 二期 #10——agent_memories 補嵌入（15 筆級
      // 別，一次 batch）。守門員：模型版本不符中止。
      Future.delayed(const Duration(seconds: 95), () {
        AgentMemoryBackfillService.instance.start();
      });
      // [教練 Agent 2026-08-21] 鐵三角 #7+#9——事件驅動髒標記（Directory.watch）
      // + 30 分鐘週期兜底重掃。延遲 120 秒：排在所有回填 worker 之後，
      // 啟動補掃才不會跟 chunk/reembed 搶 DB 寫鎖。
      Future.delayed(const Duration(seconds: 120), () {
        IncrementalIngestService.instance.start();
      });
      // [教練 Agent 2026-08-21] 記憶落檔存量回填——DB 既有 memories 一次性
      // 補成 md（冪等）。新記憶由 MemoryFileExporter 即時落檔。
      Future.delayed(const Duration(seconds: 125), () {
        MemoryFileBackfillService.instance.start();
      });
      // [小葵 2026-09-22] 衰減服務接線——runDecayCycle 此前零呼叫點（寫好
      // 沒插電）。照 decay service 設計註解「每日一次」：啟動 130 秒後跑
      // 第一次（避開回填 worker 搶 DB 寫鎖），之後每 24 小時一次。
      // 冪等、catch 全包、失敗只 log 不影響其他服務。
      Future.delayed(const Duration(seconds: 130), () {
        _scheduleDecayCycle();
      });
      debugPrint(
        '[BrainContainer] 初始化完成。模型: ${_embedder.isModelAvailable ? "已安裝" : "fallback(零向量)"}',
      );
    } catch (e, st) {
      debugPrint('[BrainContainer] 初始化失敗: $e\n$st');
      // 不 rethrow——大腦容器故障不應阻擋 app 啟動
    }
  }

  /// [小葵 2026-09-22] 每日記憶衰減循環。
  ///
  /// runDecayCycle() 內部已 try/catch（失敗回傳全零 DecayResult），
  /// 這裡再包一層防 Timer 回呼拋例外。軟刪（archived=1）——絕不物理刪除，
  /// user_marked 連結免疫休眠，md 檔案副本永久留存（記憶鐵律）。
  Timer? _decayTimer;

  void _scheduleDecayCycle() {
    runDecayCycle();
    // [小葵 2026-09-22 偷學令②] 使用者檔案同時脈刷新——static/dynamic
    // 視圖與衰減共用每日節奏（同一批寫鎖時窗，不另開時脈）
    UserProfileService.instance.refresh(_database.db);
    _decayTimer?.cancel();
    _decayTimer = Timer.periodic(const Duration(days: 1), (_) {
      runDecayCycle();
      UserProfileService.instance.refresh(_database.db);
    });
  }

  /// 寫入記憶。
  ///
  /// [content] 記憶內容（自然語言）
  /// [agent] 來源 agent 名稱（例如 '教練 Agent'）
  /// [source] 記憶來源類型
  /// [project] 可選，關聯專案
  /// [tags] 可選，標籤列表
  /// [importance] 1-5，預設 3
  ///
  /// 回傳 true 表示寫入成功。
  /// 若大腦容器未初始化或寫入失敗，回傳 false（不 throw）。
  /// [Step 6 2026-08-18 復活] 把最後寫入的記憶改到指定房間
  ///
  /// BridgeService 寫橋記憶時，extraction pipeline 未必會分到 bridges 房間，
  /// 這裡手動覆寫，讓 ConnectionDetector 的 bridgeTie 偵測能看到。
  Future<void> overrideLatestMemoryRoom(BrainRoom room) async {
    try {
      await _database.overrideLatestMemoryRoom(room.name);
    } catch (e) {
      debugPrint('[BrainContainer] overrideLatestMemoryRoom 失敗: $e');
    }
  }

  Future<bool> writeMemory({
    required String content,
    required String agent,
    String companionId = '',
    MemorySource source = MemorySource.chat,
    MemorySpeaker speaker = MemorySpeaker.unknown, // [出處戳] 架構層填（user/agent/external）
    String project = '',
    List<String> tags = const [],
    int importance = 3,
  }) async {
    if (!_initialized) return false;

    try {
      final result = await _writePipeline.write(
        content: content,
        agent: agent,
        companionId: companionId,
        source: source,
        speaker: speaker, // [出處戳]
        project: project,
        tags: tags,
        importance: importance,
      );

      // [小葵 2026-09-22 v18 矛盾消解] 寫入後：同主題舊事實標 superseded
      // （新事實取代舊事實——舊的指向新ID，留審計不刪、不進檢索）。
      // 失敗靜默——消解失敗不影響寫入結果。
      if (result.memories.isNotEmpty && _embedder.isModelAvailable) {
        final mem = result.memories.first;
        _resolveContradictionsPostWrite(
          newMemoryId: mem.id,
          newContent: mem.content,
        ).catchError((e) {
          debugPrint('[BrainContainer] 矛盾消解失敗（靜默）: $e');
        });
      }

      // 房間生長更新
      if (result.memories.isNotEmpty) {
        await _growthUpdater.onMemoryAdded(result.memories.first.room);

        // [教練 Agent 2026-08-08] Transurfing：記憶寫入後觸發水流追蹤
        _onMemoryWritten(result.memories.first);

        // [教練 Agent 2026-07-28] Phase 5 決策 5：記憶↔檔案向量自動關聯
        // fire-and-forget — 不阻塞寫入流程
        final mem = result.memories.first;
        CrossReferenceService.instance
            .autoLinkByVector(memoryId: mem.id, memoryContent: mem.content)
            .catchError((e) {
              debugPrint('[BrainContainer] autoLinkByVector 失敗（靜默）: $e');
              return 0;
            });
      }

      return !result.partialSuccess;
    } catch (e) {
      debugPrint('[BrainContainer] writeMemory 失敗: $e');
      return false;
    }
  }

  /// [小葵 2026-09-22 v18 矛盾消解] 寫入後處理：新事實取代同主題舊事實。
  ///
  /// 判定邏輯（借鏡 supermemory updates 邊，本地零 LLM 實作）：
  /// 1. 向量找回語意相近的既有記憶（retrieve 閾值 0.5、cosine 高分者；
  ///    比去重閾值 0.85 略寬——寧可多消解不漏消解，取代是軟標記可逆）
  /// 2. 字面 token 重疊率 < 0.5 → 不同說法的同一主題 → 舊事實被取代
  ///    （例：「我住台北」vs「我搬到台中去了」——語意近、字面遠）
  /// 3. 字面重疊 ≥ 0.5 → 純重複，不是矛盾 → 不動（去重由寫入端既有
  ///    邏輯處理）
  ///
  /// 被取代的舊記憶：superseded_by = 新ID（不刪、不進檢索、可審計）。
  Future<void> _resolveContradictionsPostWrite({
    required String newMemoryId,
    required String newContent,
  }) async {
    final similar = await _retrievalPipeline.retrieve(query: newContent);
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final r in similar) {
      // 不跟自己、不重複標記（已是 superseded 的不二度標）
      if (r.memoryId == newMemoryId) continue;

      final overlap = _tokenOverlapRate(newContent, r.content);
      if (overlap >= 0.5) continue; // 純重複→不動

      // 語意近+字面遠 → 矛盾取代
      final db = _database.db;
      db.execute(
        'UPDATE memories SET superseded_by = ?, updated_at = ? '
        'WHERE id = ? AND superseded_by IS NULL AND archived = 0',
        [newMemoryId, now, r.memoryId],
      );
      debugPrint(
        '[BrainContainer] 矛盾消解: 舊記憶 ${r.memoryId} 被取代 '
        '（overlap=$overlap）→ $newMemoryId',
      );
    }
  }

  /// 字面 token 重疊率（0~1）。與 SmartMemoryExtractor._tokenOverlap 同源
  /// 概念：去除停用詞後的關鍵詞重疊比例。
  double _tokenOverlapRate(String a, String b) {
    Set<String> tokens(String s) => s
        .replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 2)
        .toSet();
    final ta = tokens(a);
    final tb = tokens(b);
    if (ta.isEmpty || tb.isEmpty) return 1.0; // 無法判定→視為重複（保守）
    return ta.intersection(tb).length / ta.union(tb).length;
  }

  /// [教練 Agent 2026-08-16 教練模式] 輕量直寫——跳過嵌入管線。
  ///
  /// 使用場景：canvas_place 建工作流節點。工作流節點只需要一個
  /// entity ID 掛 CanvasProps，不需要語意向量、也不需要完整
  /// 大腦管線（嵌入→分類→寫入→連結→生長）。
  ///
  /// 之前：writeMemory 走完整管線，任何一步安靜失敗
  /// （partialSuccess 靜默吞錯）→ canvas_place 整個 reject →
  /// 原生 Agent永遠建不出節點。
  ///
  /// 這裡：零向量 + 直寫 DB（transaction 跟 writeMany 相同），
  /// 回傳新記憶的 ID。失敗會 throw（不靜默）。
  Future<String> writeMemoryFast({
    required String content,
    required String agent,
    MemorySource source = MemorySource.idea,
    MemorySpeaker speaker = MemorySpeaker.agent, // [出處戳] 快寫=系統產出，預設 agent
    List<String> tags = const [],
    int importance = 3,
  }) async {
    if (!_initialized) {
      throw StateError('BrainContainer 未初始化（writeMemoryFast）');
    }

    final draft = MemoryDraft(
      content: content,
      room: BrainRoom.stream,
      subCategory: 'workflow_node',
      agent: agent,
      companionId: '',
      source: source,
      speaker: speaker, // [出處戳]
      project: '',
      tags: tags,
      importance: importance,
      vector: List.filled(EmbeddingService.vectorDimension, 0.0),
      vectorModelVersion: 'fast-write',
      chunkIndex: 0,
      totalChunks: 1,
    );

    final memories = await _writer.writeMany([draft]);
    if (memories.isEmpty) {
      throw StateError('writeMemoryFast：writeMany 回傳空');
    }
    return memories.first.id;
  }

  /// [教練 Agent 2026-08-08] Transurfing：記憶寫入後觸發水流追蹤
  ///
  /// 根據記憶所在的 BrainRoom，更新 TransurfingEngine 的水流狀態：
  /// - stream 記憶 → 如果沒有活躍水流，開一條新的
  /// - doors 記憶 → 從當前水流開一扇門
  /// - bridges 記憶 → 記錄跨水流連結
  /// - 其他 room → 更新當前水流的 lastActiveAt
  void _onMemoryWritten(Memory memory) {
    final engine = TransurfingEngine.instance;
    switch (memory.room) {
      case BrainRoom.stream:
        if (engine.activeStream == null) {
          engine.startStream(
            title: _deriveStreamTitle(memory.content),
            topicKeywords: memory.tags,
          );
        }
        break;
      case BrainRoom.doors:
        engine.openDoor(title: _deriveStreamTitle(memory.content));
        break;
      case BrainRoom.bridges:
        // 橋的記憶不需要改變水流狀態，只靠 ConnectionDetector 建立連結
        break;
      case BrainRoom.pendulums:
      case BrainRoom.heartMind:
      case BrainRoom.fraile:
        // 這些不直接影響水流狀態
        break;
    }
  }

  /// 從記憶內容提取簡短標題
  String _deriveStreamTitle(String content) {
    final trimmed = content.trim();
    if (trimmed.length <= 40) return trimmed;
    return '${trimmed.substring(0, 37)}...';
  }

  /// [教練 Agent 2026-08-08] 持久化 Transurfing 狀態到 brain_meta
  void persistTransurfingState() {
    if (!_initialized) return;
    try {
      final json = TransurfingEngine.instance.toJson();
      final encoded = jsonEncode(json);
      _database.db!.execute(
        'INSERT OR REPLACE INTO brain_meta (key, value, updated_at) VALUES (?, ?, ?)',
        [_transurfingMetaKey, encoded, DateTime.now().toIso8601String()],
      );
    } catch (e) {
      debugPrint('[BrainContainer] persistTransurfingState 失敗: $e');
    }
  }

  /// [教練 Agent 2026-08-08] 從 brain_meta 恢復 Transurfing 狀態
  void loadTransurfingState() {
    if (!_initialized) return;
    try {
      final rows = _database.db!.select(
        'SELECT value FROM brain_meta WHERE key = ?',
        [_transurfingMetaKey],
      );
      if (rows.isNotEmpty) {
        final value = rows.first['value'] as String?;
        if (value != null && value.isNotEmpty) {
          final json = jsonDecode(value) as Map<String, dynamic>;
          TransurfingEngine.instance.fromJson(json);
        }
      }
    } catch (e) {
      debugPrint('[BrainContainer] loadTransurfingState 失敗: $e');
    }
  }

  /// 檢索記憶。
  ///
  /// [query] 自然語言查詢
  /// [roomFilter] 可選，只搜特定房間
  /// [limit] 最大結果數
  ///
  /// 回傳檢索結果列表。若未初始化或模型不可用，回傳空列表。
  Future<List<RetrievalResult>> retrieveMemories({
    required String query,
    BrainRoom? roomFilter,
    int limit = 5,
  }) async {
    if (!_initialized || !_embedder.isModelAvailable) return [];

    try {
      final results = await _retrievalPipeline.retrieve(
        query: query,
        roomFilter: roomFilter,
      );
      final limited = results.take(limit).toList();

      // [教練 Agent 2026-07-03] 衰減管理：被檢索命中的記憶強化存取計數
      for (final r in limited) {
        if (r.isDirectHit) {
          await _decayService.onMemoryAccessed(r.memoryId);
        }
        if (r.isConnectionExpansion && r.connectionPath != null) {
          // 強化被走過的連結
          // 這裡用 connectionPath（fromMemoryId）找到對應連結
          // 簡化：只刷 access_count，連結強化留給下次寫入時的自然偵測
        }
      }

      return limited;
    } catch (e) {
      debugPrint('[BrainContainer] retrieveMemories 失敗: $e');
      return [];
    }
  }

  /// 取得格式化記憶上下文（供 system prompt 注入）。
  ///
  /// 用使用者最近一條訊息做查詢，檢索相關記憶，
  /// [時間感 L3 2026-09-12] 回憶以時間軸為主敘事線：
  /// 按時間排序（舊→新）、每條帶算好的時間差（「3 天前」），
  /// 意義相似度只決定哪些記憶被召回（亮度），不決定敘事順序（位置）。
  ///
  /// 若沒有相關記憶或模型不可用，回傳空字串。
  Future<String> getFormattedContext(String recentUserMessage) async {
    if (!_initialized || !_embedder.isModelAvailable) return '';

    try {
      final results = await retrieveMemories(
        query: recentUserMessage,
        limit: 5,
      );
      if (results.isEmpty) return '';

      // [時間感 L3] 時間軸重排：舊→新（回憶的敘事方向）
      final ordered = results.where((r) => r.content.isNotEmpty).toList()
        ..sort((a, b) {
          final at = a.createdAt;
          final bt = b.createdAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return at.compareTo(bt);
        });

      final now = DateTime.now();
      final buffer = StringBuffer();
      for (var i = 0; i < ordered.length; i++) {
        final r = ordered[i];
        if (r.content.isEmpty) continue;
        final when = r.createdAt == null
            ? '時間未知'
            : _relativeTime(now.difference(r.createdAt!).inDays);
        // [出處戳 2026-09-15] speaker= 前綴為必要語法（spike 001 實測：
        // 無前綴的裸值會被模型忽略，導致錯誤歸屬復發）
        buffer.write('記憶 ${i + 1}（$when｜speaker=${r.speaker.name}）: ${r.content}');
        if (i < ordered.length - 1) buffer.write(' | ');
      }
      return buffer.toString();
    } catch (e) {
      debugPrint('[BrainContainer] getFormattedContext 失敗: $e');
      return '';
    }
  }

  /// [時間感 L3] 相對時間語義——與 TimeSenseService/CausalLedger 一致
  static String _relativeTime(int days) {
    if (days <= 0) return '今天';
    if (days == 1) return '昨天';
    if (days < 7) return '$days 天前';
    if (days < 30) return '${(days / 7).round()} 週前';
    if (days < 365) return '${(days / 30).round()} 個月前';
    return '${(days / 365).round()} 年前';
  }

  /// 取得所有記憶內容（供舊版 MemoryStore 相容介面）。
  ///
  /// 注意：這是全表掃描，只用於除錯或遷移。
  /// 正常檢索應使用 [retrieveMemories]。
  Future<List<String>> getAllMemoryContents() async {
    if (!_initialized) return [];

    try {
      final db = _database.db;
      final rows = db.select(
        'SELECT content FROM memories WHERE archived = 0 '
        'AND chunk_index = 0 ORDER BY created_at DESC LIMIT 100',
      );
      return rows.map((r) => r['content'] as String).toList();
    } catch (e) {
      debugPrint('[BrainContainer] getAllMemoryContents 失敗: $e');
      return [];
    }
  }

  /// 取得各房間的記憶統計。
  Future<Map<BrainRoom, int>> getRoomStats() async {
    if (!_initialized) return {};

    try {
      final db = _database.db;
      final rows = db.select(
        'SELECT room, memory_count FROM rooms ORDER BY room',
      );
      return {
        for (final r in rows)
          BrainRoom.tryParse(r['room'] as String?) ?? BrainRoom.stream:
              r['memory_count'] as int? ?? 0,
      };
    } catch (e) {
      debugPrint('[BrainContainer] getRoomStats 失敗: $e');
      return {};
    }
  }

  /// 重新嵌入所有 mock-fallback 記憶。
  ///
  /// [教練 Agent 2026-07-19] EmbeddingGemma 模型修復後，舊記憶仍用零向量。
  /// 此方法找出所有 vector_model_version='mock-fallback' 的記憶，
  /// 用真實模型重新嵌入並更新 DB。
  ///
  /// 回傳重新嵌入的記憶數量。
  Future<int> reindexFallbackMemories() async {
    if (!_initialized || !_embedder.isModelAvailable) {
      debugPrint('[BrainContainer] reindex: 模型不可用，跳過');
      return 0;
    }

    try {
      final db = _database.db;
      final rows = db.select(
        "SELECT id, content FROM memories "
        "WHERE vector_model_version = 'mock-fallback' AND archived = 0",
      );

      if (rows.isEmpty) {
        debugPrint('[BrainContainer] reindex: 無 mock-fallback 記憶');
        return 0;
      }

      debugPrint('[BrainContainer] reindex: 重新嵌入 ${rows.length} 筆記憶...');
      var count = 0;

      for (final row in rows) {
        final id = row['id'] as String;
        final content = row['content'] as String;

        try {
          final result = await _embedder.embedOne(content);
          db.execute(
            "UPDATE memories SET embedding = vector_as_f32(?), "
            "vector_model_version = ? WHERE id = ?",
            [
              Memory.vectorToJson(result.vector),
              EmbeddingService.currentModelVersion,
              id,
            ],
          );
          count++;
          debugPrint('[BrainContainer] reindex: ✅ $id');
        } catch (e) {
          debugPrint('[BrainContainer] reindex: ❌ $id 失敗: $e');
        }
      }

      debugPrint('[BrainContainer] reindex: 完成，$count/${rows.length} 筆重新嵌入');
      return count;
    } catch (e) {
      debugPrint('[BrainContainer] reindex 失敗: $e');
      return 0;
    }
  }

  /// 取得所有記憶（未封存，供畫布可視化用）。
  ///
  /// 回傳 Memory 列表（含 id/content/room/tags/importance 等）。
  /// 若未初始化或失敗，回傳空列表。
  Future<List<Memory>> getAllMemories({int limit = 200}) async {
    if (!_initialized) return [];

    try {
      final db = _database.db;
      final rows = db.select(
        'SELECT * FROM memories WHERE archived = 0 '
        'AND chunk_index = 0 ORDER BY importance DESC, created_at DESC LIMIT ?',
        [limit],
      );
      return rows.map((r) => Memory.fromMap(r)).toList();
    } catch (e) {
      debugPrint('[BrainContainer] getAllMemories 失敗: $e');
      return [];
    }
  }

  /// 取得所有連結（供畫布可視化用）。
  ///
  /// 回傳 Connection 列表。若未初始化或失敗，回傳空列表。
  Future<List<Connection>> getAllConnections({int limit = 300}) async {
    if (!_initialized) return [];

    try {
      final db = _database.db;
      final rows = db.select(
        'SELECT * FROM connections WHERE dormant = 0 '
        'ORDER BY strength DESC LIMIT ?',
        [limit],
      );
      return rows.map((r) => Connection.fromMap(r)).toList();
    } catch (e) {
      debugPrint('[BrainContainer] getAllConnections 失敗: $e');
      return [];
    }
  }

  /// 取得特定夥伴的記憶列表（跨 Agent 共享大腦 — 夥伴 provenance 查詢）。
  ///
  /// [companionId] 夥伴 ID。空字串回傳無夥伴標記的舊記憶。
  /// [limit] 最大結果數。
  Future<List<Memory>> getMemoriesByCompanion({
    required String companionId,
    int limit = 100,
  }) async {
    if (!_initialized) return [];

    try {
      final db = _database.db;
      final rows = db.select(
        'SELECT * FROM memories WHERE archived = 0 '
        'AND chunk_index = 0 AND companion_id = ? '
        'ORDER BY importance DESC, created_at DESC LIMIT ?',
        [companionId, limit],
      );
      return rows.map((r) => Memory.fromMap(r)).toList();
    } catch (e) {
      debugPrint('[BrainContainer] getMemoriesByCompanion 失敗: $e');
      return [];
    }
  }

  /// 取得所有有貢獻記憶的夥伴 ID + 記憶數量。
  ///
  /// 用於 UI 顯示「哪些夥伴共建了這個大腦」。
  Future<Map<String, int>> getCompanionMemoryCounts() async {
    if (!_initialized) return {};

    try {
      final db = _database.db;
      final rows = db.select(
        'SELECT companion_id, COUNT(*) as cnt FROM memories '
        'WHERE archived = 0 AND chunk_index = 0 '
        'GROUP BY companion_id ORDER BY cnt DESC',
      );
      return {
        for (final r in rows)
          (r['companion_id'] as String?) ?? '': r['cnt'] as int? ?? 0,
      };
    } catch (e) {
      debugPrint('[BrainContainer] getCompanionMemoryCounts 失敗: $e');
      return {};
    }
  }

  /// 取得格式化的共享大腦上下文（跨夥伴記憶注入）。
  ///
  /// 與 [getFormattedContext] 類似，但附帶來源夥伴名稱。
  /// 讓當前夥伴知道「其他夥伴記得什麼」。
  ///
  /// [query] 自然語言查詢
  /// [companionNameMap] companionId → 夥伴名稱的映射
  Future<String> getSharedBrainContext(
    String query,
    Map<String, String> companionNameMap,
  ) async {
    if (!_initialized || !_embedder.isModelAvailable) return '';

    try {
      final results = await retrieveMemories(query: query, limit: 8);
      if (results.isEmpty) return '';

      // 補查 companion_id
      final db = _database.db;
      final buffer = StringBuffer();
      var written = 0;

      for (final r in results) {
        if (r.content.isEmpty) continue;

        // 查來源夥伴
        String companionLabel = '';
        try {
          final row = db.select(
            'SELECT companion_id FROM memories WHERE id = ?',
            [r.memoryId],
          );
          if (row.isNotEmpty) {
            final cid = row.first['companion_id'] as String? ?? '';
            if (cid.isNotEmpty && companionNameMap.containsKey(cid)) {
              companionLabel = '（${companionNameMap[cid]} 記得）';
            }
          }
        } catch (_) {}

        buffer.write('記憶 ${written + 1}: ${r.content}$companionLabel');
        if (written < results.length - 1) buffer.write(' | ');
        written++;
      }
      return buffer.toString();
    } catch (e) {
      debugPrint('[BrainContainer] getSharedBrainContext 失敗: $e');
      return '';
    }
  }

  /// 執行記憶衰減週期。
  ///
  /// 應定期呼叫（例如每天一次，可透過 cron 或 app 啟動時）。
  /// 回傳衰減結果摘要。若未初始化則跳過。
  Future<DecayResult?> runDecayCycle() async {
    if (!_initialized) return null;

    try {
      return await _decayService.runDecayCycle();
    } catch (e) {
      debugPrint('[BrainContainer] runDecayCycle 失敗: $e');
      return null;
    }
  }
}
