import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

import '../decision/k1_gatekeeper.dart';
import '../decision/decision_head.dart' show K1Decision;
import '../vector_db/hybrid_search_service.dart';
import 'embedding/embedding_service.dart';
import 'inject/inject_pipeline.dart';
import 'inject/slot_filter.dart';

/// M1 交付物：注入預備單一入口（InjectionPreparer）v1
///
/// [小葵 2026-10-10 M1] Fable 全貌 delta 指定：線上（agent_loop）與評測
/// （8420 /inject/enrich 路由）必須走同一條注入準備路徑，解決
/// 「評測條件 ≠ 線上條件」的三處不等：
///   ① 線上 enrich 吃 digest（>320 字截頭 150 尾 150），路由吃原始 q
///   ② 線上有 K1 正則命中的 top3 合併，路由沒有
///   ③ embedding 失敗時靜默回零向量——分不清「真無記憶」與「嵌入掛了」
///
/// 職責（單向漏斗）：digest → K1 classify（可選）→ K1 候選合併 →
/// enrichWith → 結構化 InjectionOutcome。
///
/// 紀律（Fable delta）：
///   - K1 候選：歸不進槽預設 recent、免相似度地板（floorExempt）、source=k1
///   - 評測呼叫必須 logSample: false（防 600 題灌爆 CausalLedger）
///   - droppedCount 由 enrichWith 同步回傳，不用單例欄位（兩條 AgentLoop
///     迴圈共用 InjectPipeline 單例，欄位會互相覆寫）
class InjectionPreparer {
  InjectionPreparer._();
  static final InjectionPreparer instance = InjectionPreparer._();

  /// digest 閾值：與 agent_loop._causalContextDigest 同款。
  static const int kDigestMax = 320;
  static const int kDigestHead = 150;
  static const int kDigestTail = 150;

  /// 單一入口。fail-open：任何子步驟掛了都回保守結果，不擋任務。
  ///
  /// [k1] false 時跳過 K1（例如評測純 M0 臂）。[logSample] false 時
  /// K1 判斷不寫 CausalLedger（評測路由用）。
  Future<InjectionOutcome> prepare(
    String userMessage, {
    bool k1 = true,
    bool logSample = true,
  }) async {
    final sw = Stopwatch()..start();
    final digest = digestOf(userMessage);
    final inputHash =
        crypto.sha256.convert(utf8.encode(userMessage)).toString();

    var k1MergedN = 0;
    List<MemoryCandidate> k1Candidates = const [];
    K1Decision? k1Decision;
    String? failureReason; // [Fable 🟡] 空塊率歸因：embedding_fail vs no_candidates vs enrich 崩潰
    if (k1) {
      try {
        final decision = await K1Gatekeeper.instance.classify(
          digest,
          onSample: logSample
              ? (d, msg) => K1Gatekeeper.instance.logSample(msg, d)
              : null,
        );
        k1Decision = decision;
        if (decision.needMemory && !decision.escalated) {
          k1Candidates = await _k1Candidates(digest);
          k1MergedN = k1Candidates.length;
        }
      } catch (e) {
        debugPrint('[M1 InjectionPreparer] K1 失敗（fail-open 跳過）: $e');
      }
    }
    bool embeddingOk = true;
    InjectResult r;
    try {
      r = await InjectPipeline.instance.enrichWith(
        digest,
        extraCandidates: k1Candidates,
      );
      if (r.ids.isEmpty) {
        if (!EmbeddingService.instance.isModelAvailable) {
          embeddingOk = false;
          failureReason = 'embedding_model_unavailable';
        } else if (r.droppedCount > 0) {
          // [Fable 複驗 🟡2] 候選存在但全被槽位/預算濾掉——不是「無記憶」，
          // 不跑探針（search 已成功，探針多餘且汙染延遲）。
          failureReason = 'all_filtered';
        } else {
          // 模型在但零命中：embedQuery 對失敗靜默回零向量——用探針區分
          // embedding_fail（嵌入掛了）與 no_candidates（真無記憶）。
          // [Fable 🟡] 探針計時不進 latency_ms——觀測值不可被診斷行為汙染。
          // 探針自身拋例外歸零向量處理（enrich 本身已成功，不算崩潰）。
          sw.stop();
          List<double>? probe;
          try {
            probe = await EmbeddingService.instance.embedQuery('探針');
          } catch (_) {
            probe = const [];
          }
          if (probe.every((v) => v == 0.0)) {
            embeddingOk = false;
            failureReason = 'embedding_probe_zero_vector';
          } else {
            failureReason = 'no_candidates';
          }
          sw.start();
        }
      }
    } catch (e) {
      debugPrint('[M1 InjectionPreparer] enrich 失敗（fail-open 保守結果）: $e');
      sw.stop();
      return InjectionOutcome(
        inputDigest: digest,
        inputHash: inputHash,
        block: '',
        ids: const [],
        latencyMs: sw.elapsedMilliseconds,
        droppedCount: 0,
        k1MergedN: k1MergedN,
        embeddingOk: false,
        k1Label: k1Decision?.label,
        k1Confidence: k1Decision?.confidence,
        k1Escalated: k1Decision?.escalated ?? false,
        k1Source: k1Decision?.source,
        failureReason: 'enrich_exception',
      );
    }
    sw.stop();
    return InjectionOutcome(
      inputDigest: digest,
      inputHash: inputHash,
      block: r.block,
      ids: r.ids,
      latencyMs: sw.elapsedMilliseconds,
      droppedCount: r.droppedCount,
      k1MergedN: k1MergedN,
      embeddingOk: embeddingOk,
      k1Label: k1Decision?.label,
      k1Confidence: k1Decision?.confidence,
      k1Escalated: k1Decision?.escalated ?? false,
      k1Source: k1Decision?.source,
      failureReason: failureReason,
      k1KeptN: r.k1KeptN,
    );
  }

  /// digest：與 agent_loop._causalContextDigest 同款截斷
  ///（指令在尾端，ZETA-77 教訓——頭 150 ＋ 尾 150）。
  static String digestOf(String s) {
    if (s.length <= kDigestMax) return s;
    return '${s.substring(0, kDigestHead)}'
        '…'
        '${s.substring(s.length - kDigestTail)}';
  }

  /// K1 need 時的 hybrid top3 → MemoryCandidate（source=k1）。
  /// [M1 K1 獨立通道 2026-10-10 Fable 拍板] 三項紀律：
  ///   ① expand:false——只要 RRF 直接命中。展開命中分數固定 0.2~0.5，
  ///     RRF 真命中上限 ~0.033，混入即「噪音壓過真命中」。
  ///   ② 名次分數（rank score）——1.0/0.9/0.8 依 hybrid 名次，不再帶
  ///     RRF 原值進排序（與 M0 semantic 量綱統一，排序閘根除）。
  ///   ③ take(3)——_fuseMemoriesRRF 已 take(limit)（dedup 只減不增），
  ///     此處硬上限是純防禦（參數改名/重構時的保險），非依賴。
  /// K1 候選免地板（floorExempt）、不佔四槽 quota（獨立上限 3）、
  /// 歸不進槽預設 recent。
  Future<List<MemoryCandidate>> _k1Candidates(String digest) async {
    final results = await HybridSearchService.instance.search(
      query: digest,
      mode: SearchMode.hybrid,
      limit: 3,
      expand: false, // [M1] 只要直接命中，跳過圖譜/上下文展開
    );
    final out = <MemoryCandidate>[];
    for (final (i, hit) in results.memoryHits.take(3).indexed) {
      final parsed = InjectPipeline.parseMemoryHit(hit);
      out.add(MemoryCandidate(
        id: hit.id,
        text: hit.content,
        // 名次分數：與 M0 semantic 量綱同級（1.0~0.8），純排序用途
        similarity: 1.0 - i * 0.1,
        slot: parsed?.slot ?? MemorySlot.recent,
        source: 'k1',
        floorExempt: true,
      ));
    }
    return out;
  }
}

/// 結構化注入結果——線上（agent_loop）與評測（/inject/enrich 路由）共用。
class InjectionOutcome {
  InjectionOutcome({
    required this.inputDigest,
    required this.inputHash,
    required this.block,
    required this.ids,
    required this.latencyMs,
    required this.droppedCount,
    required this.k1MergedN,
    required this.embeddingOk,
    this.k1Label,
    this.k1Confidence,
    this.k1Escalated = false,
    this.k1Source,
    this.failureReason,
    this.k1KeptN = 0,
  });

  final String inputDigest;
  final String inputHash; // 完整 userMessage 的 SHA-256（M3 歸因鍵）
  final String block; // '' = 無注入
  final List<String> ids;
  final int latencyMs;
  final int droppedCount;
  final int k1MergedN;
  final bool embeddingOk;
  final String? k1Label;
  final double? k1Confidence;
  final bool k1Escalated;
  final String? k1Source;
  final String? failureReason;

  /// K1 候選「真正進注入塊」的數量（kept 中 source=k1）。
  /// [Fable 🟡] k1MergedN 記的是 hybrid 命中數——評測判斷「K1 是否有貢獻」
  /// 必須用這個，否則 K1 全被擠掉時會誤判有增益。
  final int k1KeptN;
}
