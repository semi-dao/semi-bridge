// Context Store — CLM 形狀的 context 管理核心（spike 002 落地版）
//
// 起源：spikes/002-clm-contextbench（commit ab7d74cb）。
// agent_loop.dart 舊 L624 硬截斷在 ContextBench kv_store 上 recall 100%→0%
// （64/64 全滅：值 ~150字/筆 vs 截斷只留工具名+80字）。CLM 形狀
// （封存+指針+按需讀回）在 spike 實測 E4B=65.1%、GLM-5.3=90.1%。
//
// 設計（借 CLM 論文 arXiv 2609.37725 的形狀，非抄 code——CC BY-NC 4.0）：
// - 截斷不再「銷毀」訊息——被壓縮的訊息全文進 store，摘要帶指針留在 context
// - store 永不刪除（記憶鐵律：永不刪）
// - context_recall 工具：LLM 按需讀回封存全文（含原文查詢）
// - 機械保底：不需模型自覺，截斷時機械式封存

import 'agent_tool.dart';

/// 一筆封存紀錄
class ContextStoreEntry {
  final int id; // 封存序號（指針）
  final String role;
  final String content; // 全文（永不銷毀）
  final String summary; // 留在 context 的摘要行

  const ContextStoreEntry({
    required this.id,
    required this.role,
    required this.content,
    required this.summary,
  });
}

/// 每次 run 一個實例。非持久化——store 生命週期 = 單次任務。
/// （跨輪持久記憶另有 memory/ledger 體系，此處不重疊職責。）
class ContextStore {
  final List<ContextStoreEntry> _entries = [];
  final Map<String, int> _hashToId = {}; // 冪等：同內容回同指針
  int _nextId = 1;
  int _charsStored = 0;

  ContextStore();

  List<ContextStoreEntry> get entries => List.unmodifiable(_entries);
  int get entryCount => _entries.length;
  int get charsStored => _charsStored;

  /// 封存一則訊息，回傳帶指針的摘要行（放回 context 用）。
  /// 冪等：同 role+content 重複封存（跨輪重送常見）回傳既有指針，不重複入庫。
  String archive(String role, String content, {String? manualSummary}) {
    final key = '$role\u0000$content';
    final existing = _hashToId[key];
    if (existing != null) {
      final e = byId(existing);
      if (e != null) return '〔已封存 #${e.id}〕${e.summary}';
    }
    final id = _nextId++;
    final summary = manualSummary ?? _summarize(content);
    _entries.add(ContextStoreEntry(
      id: id,
      role: role,
      content: content,
      summary: summary,
    ));
    _hashToId[key] = id;
    _charsStored += content.length;
    return '〔已封存 #$id〕$summary';
  }

  /// 摘要規則（向後相容舊截斷的長度限制，但多留指針）：
  /// - 工具結果：工具名 + 前 120 字（舊版 80 字實測蒸發關鍵值，加寬）
  /// - 其他訊息：前 80 字
  static String _summarize(String content) {
    if (content.startsWith('工具 ') && content.contains('執行結果')) {
      final m = RegExp(r'工具 (\w+) 的執行結果').firstMatch(content);
      final name = m?.group(1) ?? 'unknown';
      final body = content.length > 120 ? content.substring(0, 120) : content;
      return '[$name 結果: $body...]';
    }
    final body = content.length > 80 ? content.substring(0, 80) : content;
    return '[${body}...]';
  }

  /// 依指針讀回全文
  ContextStoreEntry? byId(int id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// 依關鍵詞搜尋封存內容（LLM context_recall 用）
  List<ContextStoreEntry> search(String query, {int limit = 5}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final scored = <ContextStoreEntry, double>{};
    for (final e in _entries) {
      final lower = e.content.toLowerCase();
      // 命中次數 × 首現位置加權（早出現的相關性高）
      int hits = 0, idx = 0;
      while ((idx = lower.indexOf(q, idx)) != -1) {
        hits++;
        idx += q.length;
      }
      if (hits > 0) {
        final first = lower.indexOf(q);
        final posWeight = 1.0 / (1.0 + first / 1000.0);
        scored[e] = hits.toDouble() * posWeight;
      }
    }
    final ranked = scored.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(limit).map((x) => x.key).toList();
  }

  /// [跨輪層] 合併視圖——context_recall 同時搜尋 run store + session store。
  /// id 定址：1-9999 = run store，10000+ = session store（offset）。
  static const int _sessionIdOffset = 10000;
  ContextStore? _linkedSession;

  /// 給 AgentLoop 接線：run 的 store 建立時連到 session store
  void linkSession(ContextStore session) => _linkedSession = session;

  bool get hasLinkedSession => _linkedSession != null;

  @override
  String toString() => 'ContextStore($entryCount entries, $charsStored chars)';

  /// 合併搜尋（run + linked session）
  List<ContextStoreEntry> searchAll(String query, {int limit = 5}) {
    final own = search(query, limit: limit);
    if (_linkedSession == null) return own;
    final sessionHits = _linkedSession!.search(query, limit: limit);
    // 合併去重（同 id 空間可能碰撞——session 條目 id 從 offset 起虛擬編號）
    final merged = <ContextStoreEntry>[...own];
    for (final h in sessionHits) {
      if (merged.length >= limit) break;
      if (!merged.any((m) => identical(m, h) || m.content == h.content)) {
        merged.add(h);
      }
    }
    return merged;
  }

  /// 合併 byId：run store 先查，miss 時查 session store（id 減 offset）
  ContextStoreEntry? byIdAny(int id) {
    final own = byId(id);
    if (own != null) return own;
    if (_linkedSession == null) return null;
    return _linkedSession!.byId(id - _sessionIdOffset);
  }

  /// [跨輪層 2026-10-13] 雲端模式對話歷史壓縮——CLM 形狀延伸到跨輪層。
  ///
  /// 病因：chat_controller 每輪把完整 conversationHistory 打包進 userMessage
  /// 重送（L1890-1903），token 隨輪數線性膨脹——這是使用者得手動開新對話
  /// （/reset /new）省 token 的根因。
  /// 形狀：超過 keepTurns 時，舊輪全文進 store（永不刪），保留區前端放
  /// 指針摘要塊；LLM 需要細節時 context_recall 讀回。
  /// 回傳壓縮後的 history（可直接當 conversationHistory 用）。
  static List<Map<String, String>> compactHistory(
    ContextStore store,
    List<Map<String, String>> history, {
    int keepTurns = 6,
    int triggerTurns = 10,
  }) {
    if (history.length <= triggerTurns) return history;
    final old = history.sublist(0, history.length - keepTurns);
    final pointers = <String>[];
    for (final m in old) {
      final content = m['content'] ?? '';
      if (content.trim().isEmpty) continue;
      pointers.add(store.archive(m['role'] ?? 'user', content));
    }
    if (pointers.isEmpty) return history;
    return <Map<String, String>>[
      {
        'role': 'user',
        'content': '〔更早對話已封存——需要細節時呼叫 context_recall 工具讀回〕\n'
            '${pointers.join('\n')}',
      },
      ...history.sublist(history.length - keepTurns),
    ];
  }
}

/// context_recall 工具——LLM 按需讀回被截斷封存的訊息全文。
///
/// [spike 002 harness 教訓] 輸出預算必須夠大（舊 1200 tokens 截斷 READ_STORE
/// → 2.8%；4000 → 90%）。回傳上限 6000 字/次，防單次讀回塞爆 context。
class ContextRecallTool extends AgentTool {
  final ContextStore store;
  ContextRecallTool(this.store);

  @override
  String get name => 'context_recall';

  @override
  String get description =>
      '讀回被壓縮封存的舊訊息全文。context 裡的〔已封存 #N〕標記可用 id 讀回；'
      '或用 query 關鍵詞搜尋封存內容。長任務中需要舊工具結果細節（ID、路徑、'
      '參數值）時必用。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'id',
          description: '〔已封存 #N〕的 N。指定時直接讀回該則全文',
        ),
        AgentToolParamSpec(
          name: 'query',
          description: '關鍵詞。不指定 id 時以此搜尋封存內容（回傳前 5 筆含全文）',
        ),
        AgentToolParamSpec(
          name: 'max_chars',
          description: '單次回傳上限（預設 6000）',
          defaultValue: '6000',
        ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final maxChars =
        int.tryParse('${args['max_chars'] ?? 6000}')?.clamp(500, 12000) ?? 6000;
    final id = int.tryParse('${args['id'] ?? ''}');
    if (id != null) {
      final e = store.byIdAny(id);
      if (e == null) {
        return AgentToolResult.failure(
            '找不到 #$id（本輪 range: #1-#${store.entryCount}'
            '${store.hasLinkedSession ? '；跨輪封存: #10000+' : ''}）',
            toolName: name);
      }
      final text = e.content.length > maxChars
          ? '${e.content.substring(0, maxChars)}\n…（截斷，全文 ${e.content.length} 字，改用 query 搜）'
          : e.content;
      return AgentToolResult.success('#${e.id} [${e.role}] 全文：\n$text');
    }
    final query = '${args['query'] ?? ''}'.trim();
    if (query.isEmpty) {
      return AgentToolResult.failure('需帶 id 或 query 至少一項', toolName: name);
    }
    final hits = store.searchAll(query);
    if (hits.isEmpty) {
      return AgentToolResult.success(
          '「$query」在封存中無命中（本輪 ${store.entryCount} 筆'
          '${store.hasLinkedSession ? '＋跨輪封存' : ''}）。'
          '換個關鍵詞試試。');
    }
    final sb = StringBuffer('「$query」命中 ${hits.length} 筆：\n');
    var used = 0;
    for (final h in hits) {
      final remain = maxChars - used;
      if (remain < 200) {
        sb.write('\n#${h.id}（略——單次上限，改帶 id 再呼叫一次拿這筆）');
        break;
      }
      final body =
          h.content.length > remain ? h.content.substring(0, remain) : h.content;
      sb.write('#${h.id} [${h.role}] $body\n---\n');
      used += body.length;
    }
    return AgentToolResult.success(sb.toString());
  }
}
