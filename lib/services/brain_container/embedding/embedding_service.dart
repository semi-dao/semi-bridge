// embedding_service.dart
// EmbeddingGemma 嵌入服務（P1-4: TFLite via flutter_gemma_embeddings）
// 建立日期: 2026-07-02
// 修改日期: 2026-10-15 — EG2（EmbeddingGemma-2）backend 接線
//   [小葵 2026-10-15 Blue 令：EG2 三線上線]
//   新增 llama-server EG2 backend（POST /embeddings）：initialize() 時探測
//   18789 是否掛著 EG2 模型（GGUF arch gemma-embedding2），可用則優先走它，
//   否則 fallback flutter_gemma 300M（行為完全不變）。
//   介面（embedOne/embedBatch/embedQuery 簽名）不變——下游 8+ 檔案零改動。
//   EG2 實測戰報見 docs/EG2_MULTIMODAL_TEST_REPORT.md

import 'dart:async'; // [T6⑤] Timer
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'eg2_backend.dart';

/// EmbeddingGemma 嵌入服務。
///
/// 雙 backend：
/// 1. [Eg2Backend]——llama-server EG2（768 維，text+vision+audio），優先
/// 2. flutter_gemma 300M（TFLite on-device）——fallback
///
/// - 推論後自動 L2 正規化（cosine similarity 友善）
/// - 若都不可用，fallback 為零向量（讓管線不中斷）
class EmbeddingService {
  static final EmbeddingService instance = EmbeddingService._();
  EmbeddingService._();

  static const String currentModelVersion = 'gemma-300m-v1';

  /// [小葵 2026-10-15] EG2 版本標籤——重嵌入跑批後 DB 中的向量以此為 modelVersion
  static const String eg2ModelVersion = 'eg2-300m-v1';

  /// llama-server EG2 端點——獨立埠 18890（launchd 常駐 farm.semiwasabi.bridgeApp.eg2）
  /// 不跟 18789 主生產線（E4B 生成）搶 server：EG2 是 300MB 小模型，獨立常駐無壓力。
  /// [小葵 2026-10-15] 18789 只掛一個模型（App 選的主模型），EG2 共用會 probe 到 E4B。
  static const String eg2Endpoint = 'http://127.0.0.1:18890';

  static const int vectorDimension = 768;

  bool _initialized = false;
  EmbeddingModel? _model;

  /// EG2 backend 可用性（initialize 時探測一次，之後快取）
  Eg2Backend? _eg2;

  /// 初始化嵌入服務。
  Future<void> initialize() async {
    if (_initialized) return;
    await _tryProbeEg2();
    await _tryGetActiveModel();
    _initialized = true;
  }

  /// 探測 llama-server EG2：health ok + 載入的模型是 gemma-embedding2 架構。
  Future<void> _tryProbeEg2() async {
    _eg2 = await Eg2Backend.probe(eg2Endpoint);
    _scheduleEg2Recheck(); // [T6⑤] EG2 掛掉後週期重探——斷線自癒
  }

  /// [T6⑤ 2026-10-17] EG2 重探——_eg2 為 null 時每 5 分鐘 probe 一次
  /// 18890（launchd 常駐；App 啟動早於 llama-server 就緒的情境也覆蓋）。
  /// probe 成功即停（下次斷線再啟動）。全域零額外開銷：EG2 在線時無 timer。
  Timer? _eg2RecheckTimer;
  void _scheduleEg2Recheck() {
    _eg2RecheckTimer?.cancel();
    if (_eg2 != null) return; // 在線——不需重探
    _eg2RecheckTimer = Timer(const Duration(minutes: 5), () async {
      try {
        _eg2 = await Eg2Backend.probe(eg2Endpoint);
        if (_eg2 != null) {
          debugPrint('[EmbeddingService] EG2 重探成功——斷線自癒');
        } else {
          _scheduleEg2Recheck(); // 再等 5 分鐘
        }
      } catch (_) {
        _scheduleEg2Recheck();
      }
    });
    if (_eg2 != null) {
      debugLogEG2('EG2 backend 上線（${_eg2!.modelKey}）——嵌入走 llama-server');
    }
  }

  /// 嘗試取得已安裝的 embedding model。
  Future<void> _tryGetActiveModel() async {
    try {
      if (FlutterGemma.hasActiveEmbedder()) {
        _model = await FlutterGemma.getActiveEmbedder();
      }
    } catch (_) {
      _model = null;
    }
  }

  /// 模型安裝完成後呼叫，熱載入 embedding model。
  Future<void> reload() async {
    await _model?.close();
    _model = null;
    await _tryProbeEg2();
    await _tryGetActiveModel();
  }

  /// 嵌入單段文字（用於記憶寫入，使用 document 前綴）。
  Future<EmbeddingResult> embedOne(String text) async {
    if (!_initialized) throw StateError('EmbeddingService 未初始化');

    // EG2 優先
    if (_eg2 != null) {
      final vec = await _eg2!.embedTexts([text]);
      if (vec != null && vec.isNotEmpty) {
        return EmbeddingResult(
          modelVersion: eg2ModelVersion,
          chunkIndex: 0,
          vector: _l2Normalize(vec[0]),
          computedAt: DateTime.now(),
        );
      }
      // EG2 暫時失敗 → 落回 300M（不中斷）
    }

    if (_model != null) {
      try {
        final vector = await _model!.generateEmbedding(
          text,
          taskType: TaskType.retrievalDocument,
        );
        return EmbeddingResult(
          modelVersion: currentModelVersion,
          chunkIndex: 0,
          vector: _l2Normalize(vector),
          computedAt: DateTime.now(),
        );
      } catch (_) {
        // 推論失敗 → fallback
      }
    }

// Fallback: 零向量
    return EmbeddingResult(
      modelVersion: 'mock-fallback',
      chunkIndex: 0,
      vector: List.filled(vectorDimension, 0.0),
      computedAt: DateTime.now(),
    );
  }

  /// 批次嵌入多段文字（用於記憶寫入，使用 document 前綴）。
  Future<List<EmbeddingResult>> embedBatch(List<String> texts) async {
    if (!_initialized) throw StateError('EmbeddingService 未初始化');

    // EG2 優先（批次一次請求，比逐條快）
    if (_eg2 != null) {
      final vecs = await _eg2!.embedTexts(texts);
      if (vecs != null && vecs.length == texts.length) {
        return vecs.asMap().entries.map((e) => EmbeddingResult(
              modelVersion: eg2ModelVersion,
              chunkIndex: e.key,
              vector: _l2Normalize(e.value),
              computedAt: DateTime.now(),
            )).toList();
      }
    }

    if (_model != null) {
      try {
        final vectors = await _model!.generateEmbeddings(
          texts,
          taskType: TaskType.retrievalDocument,
        );
        return vectors.asMap().entries.map((e) => EmbeddingResult(
              modelVersion: currentModelVersion,
              chunkIndex: e.key,
              vector: _l2Normalize(e.value),
              computedAt: DateTime.now(),
            )).toList();
      } catch (_) {
        // 推論失敗 → fallback
      }
    }

    // Fallback: 批次零向量
    return texts.asMap().entries.map((e) => EmbeddingResult(
      modelVersion: 'mock-fallback',
      chunkIndex: e.key,
      vector: List.filled(vectorDimension, 0.0),
      computedAt: DateTime.now(),
    )).toList();
  }

  /// 嵌入查詢文字（用於記憶檢索，使用 query 前綴）。
  /// [小葵 2026-10-15 T6/D1] 查詢向量血型鐵則：
  /// 庫向量已 100% eg2-300m-v1——查詢也必須 eg2。EG2 失敗時 throw
  /// （不再 fallback gemma-300M：gemma 查詢向量打 eg2 庫＝跨血型比對，
  /// 距離無意義——Fable 斷鏈④）。呼叫端（HybridSearch._searchSemantic）
  /// 的 catch 會轉全文搜尋（FTS 無血型問題）＝正確降級路徑。
  Future<List<double>> embedQuery(String query) async {
    if (!_initialized) throw StateError('EmbeddingService 未初始化');

    // EG2 唯一路徑（查詢與文件同量綱）
    if (_eg2 != null) {
      final vec = await _eg2!.embedTexts([query]);
      if (vec != null && vec.isNotEmpty) {
        return _l2Normalize(vec[0]);
      }
      // [T6] EG2 失敗＝本輪沒有同血型查詢向量——throw 給上層轉全文
      throw StateError('EG2 query embed 失敗（T6：不 fallback 異血型）');
    }

    throw StateError('EG2 backend 未掛載（T6：查詢不再走 fallback 模型）');
  }

  /// 對向量做 L2 正規化。
  ///
  /// EmbeddingGemma 的原始輸出未正規化。
  /// L2 正規化後 cosine similarity = dot product，
  /// 與 sqlite_vector 的 vector_full_scan distance 計算一致。
  List<double> _l2Normalize(List<double> vector) {
    var sumSq = 0.0;
    for (final v in vector) {
      sumSq += v * v;
    }
    final norm = sqrt(sumSq);
    if (norm == 0.0) return vector;

    return vector.map((v) => v / norm).toList();
  }

  /// 釋放資源。
  Future<void> dispose() async {
    await _model?.close();
    _model = null;
    _initialized = false;
  }

  /// 目前是否使用真實模型（非 fallback）。
  bool get isModelAvailable => _eg2 != null || _model != null;

  /// 目前生效的模型版本標籤（EG2 優先）——UI 顯示用。
  String get activeModelVersion =>
      _eg2 != null ? eg2ModelVersion : currentModelVersion;
}

/// [小葵 2026-10-15] EG2 探測/接線紀錄（filter 開發觀察用）
void debugLogEG2(String msg) => debugPrint('[EG2] $msg');

/// 嵌入結果。
class EmbeddingResult {
  final String modelVersion;
  final int chunkIndex;
  final List<double> vector;
  final DateTime computedAt;

  const EmbeddingResult({
    required this.modelVersion,
    required this.chunkIndex,
    required this.vector,
    required this.computedAt,
  });
}
