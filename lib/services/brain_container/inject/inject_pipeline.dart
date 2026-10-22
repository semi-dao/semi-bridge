import '../../vector_db/hybrid_search_service.dart';
import 'budget_controller.dart';
import 'slot_filter.dart';

/// M0 交付物 2 主流程：記憶注入管線 v2
///
/// 輸入輪次 → 檢索 top-20 → 次線補充 → 槽位過濾 → 預算控制 → 注入區塊
/// v2（Fable 驗收修正）：
///   - BudgetResult 結構化回傳（不用字串 contains 反推 injected_ids）
///   - elapsed 回傳給呼叫端（接線時落 event_ledger，不只 print）
///
/// v3 [小葵 2026-10-10 M1]（Fable 全貌 delta）：
///   - enrichWith：M0 單一入口升級——接受 extraCandidates（K1 命中候選）
///     併入槽位過濾與預算；droppedCount 同步回傳（不再用單例欄位——
///     兩條 AgentLoop 迴圈共用本單例，欄位會互相覆寫）
///   - enrich（v2 舊簽名）保留為薄包裝，向後相容
///   - type 解析（[type] title — body）抽成靜態 helper 供 K1 候選共用
class InjectResult {
  InjectResult({
    required this.inputDigest,
    required this.block,
    required this.ids,
    required this.latencyMs,
    required this.droppedCount,
    this.k1KeptN = 0,
  });

  /// 全空結果（enrich 拋例外時的保守回傳）
  const InjectResult.empty(String digest)
      : inputDigest = digest,
        block = '',
        ids = const [],
        latencyMs = 0,
        droppedCount = 0,
        k1KeptN = 0;

  final String inputDigest;
  final String block; // '' = 無注入
  final List<String> ids;
  final int latencyMs;
  final int droppedCount;

  /// K1 候選真正進注入塊的數量（kept 中 source=k1）。
  /// [Fable 🟡] 評測歸因用：k1MergedN（命中數）≠ k1KeptN（存活數）。
  final int k1KeptN;
}

class InjectPipeline {
  InjectPipeline._();
  static final InjectPipeline instance = InjectPipeline._();

  final SlotFilter _slotFilter = SlotFilter();
  final BudgetController _budget = BudgetController();

  /// v3 主入口：M0 semantic top20 ＋ extraCandidates（K1）合併 → 槽位 → 預算。
  /// droppedCount 同步回傳（不用單例欄位）。
  Future<InjectResult> enrichWith(
    String turnInput, {
    List<MemoryCandidate> extraCandidates = const [],
  }) async {
    final sw = Stopwatch()..start();
    final results = await HybridSearchService.instance.search(
      query: _clipQuery(turnInput),
      mode: SearchMode.semantic,
      limit: 20,
    );

    final m0Candidates = <MemoryCandidate>[];
    for (final hit in results.memoryHits.take(20)) {
      final parsed = parseMemoryHit(hit);
      if (parsed == null) continue;
      m0Candidates.add(parsed);
    }
    // K1 候選併入：mergeCandidates（同 id 撞號 K1 版勝出——靜態方法）
    final candidates = mergeCandidates(m0Candidates, extraCandidates);

    final picked = _slotFilter.apply(candidates);
    final result = _budget.assemble(picked);
    final ids = result.kept.map((c) => c.id).toList();

    sw.stop();
    final elapsed = sw.elapsedMilliseconds;
    if (elapsed > 150) {
      // M0 驗收線 150ms。慢警告（接線後 elapsed 落 event_ledger 觀測）。
      // ignore: avoid_print
      print('[InjectPipeline] 慢警告: ${elapsed}ms (預算 150ms)');
    }

    if (result.kept.isEmpty) {
      return InjectResult(
        inputDigest: turnInput,
        block: '',
        ids: const [],
        latencyMs: elapsed,
        droppedCount: candidates.length,
        k1KeptN: 0,
      );
    }
    return InjectResult(
      inputDigest: turnInput,
      block: result.block,
      ids: ids,
      latencyMs: elapsed,
      droppedCount: candidates.length - result.kept.length,
      k1KeptN: result.kept.where((c) => c.source == 'k1').length,
    );
  }

  /// v2 舊簽名薄包裝（向後相容）——agent_loop 已改走 InjectionPreparer，
  /// 僅測試與過渡期使用。
  Future<(String, List<String>, int)> enrich(String turnInput) async {
    final r = await enrichWith(turnInput);
    if (r.ids.isEmpty) return (turnInput, <String>[], r.latencyMs);
    return ('$turnInput\n${r.block}', r.ids, r.latencyMs);
  }

  /// K1 候選併入：依 id 去重——同 id 撞號時「K1 版本勝出」。
  /// [Fable 🔴2] 舊邏輯保留 M0 版（無 floorExempt），K1 明確命中的
  /// 記憶若 M0 相似度低於地板就會被丟；K1 是 need 判定的明確檢索，
  /// 理應覆蓋 M0 的模糊命中。
  /// 抽成靜態方法供單測（[Fable 複驗 🟡3]——dedup 邏輯原零測試覆蓋）。
  static List<MemoryCandidate> mergeCandidates(
    List<MemoryCandidate> m0Candidates,
    List<MemoryCandidate> k1Candidates,
  ) {
    final k1Ids = k1Candidates.map((c) => c.id).toSet();
    final out = m0Candidates.where((c) => !k1Ids.contains(c.id)).toList()
      ..addAll(k1Candidates);
    return out;
  }

  /// 記憶命中 → 候選（type 解析：'[type] title — body' 前綴）。
  /// 抽出共用：M0 semantic 命中與 K1 hybrid 命中走同一條解析。
  static MemoryCandidate? parseMemoryHit(MemoryHit hit) {
    final m = RegExp(r'^\[([^\]]+)\]\s*([^\n—]*?)(?:\s+—\s+|\n|$)')
        .firstMatch(hit.content);
    final memoryType = m?.group(1);
    final title = m?.group(2) ?? '';
    final slot = SlotFilter.slotOf(
      memoryType: memoryType,
      title: title.trim().isNotEmpty ? title.trim() : null,
    );
    if (slot == null) return null;
    return MemoryCandidate(
      id: hit.id,
      text: hit.content,
      similarity: hit.score,
      slot: slot,
      // [指紋章 2026-10-21 ②刀1] 檢索帶出的出處章傳遞到注入層
      fingerprint: (hit.speakerName == null || hit.speakerName == 'shared')
          ? null
          : (hit.createdAtLabel == null
              ? hit.speakerName
              : '${hit.speakerName}·${hit.createdAtLabel}'),
    );
  }

  /// 檢索 query 用前 60 字（rune 安全）
  String _clipQuery(String s) {
    final runes = s.runes.toList();
    return runes.length <= 60 ? s : String.fromCharCodes(runes.sublist(0, 60));
  }
}
