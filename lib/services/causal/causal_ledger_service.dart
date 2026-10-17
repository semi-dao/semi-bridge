// causal_ledger_service.dart
// [因果引擎 Phase 0 2026-09-11] L1 介入帳本 + L2 證據等級
// 提案：docs/specs/2026-09-11-causal-reasoning-architecture.md
// 羅盤：agent.causality 器官（agent.causality.ledger / evidenceGrade / ledgerFeedback）
//
// 核心洞察：模型的因果能力是租來的，環境的因果能力是蓋出來的。
// 第 2 階（干預）的本體是「凍結其他變數、只動一個、看到結果」——
// AgentLoop 的每次工具執行正是這個動作，本服務把它強制記帳：
// do(工具+參數摘要) @ 情境 → 觀測(結果摘要) + 證據等級 + 歸人。
//
// 設計鐵則（沿用 BudgetLedger / CompassStore 慣例）：
// - singleton + sqlite3 同步 API + WAL
// - fail-open：記帳失敗絕不影響工具執行，但必留錯誤痕跡（debugPrint + lastError）
// - 歸人：companionId（ambient 模式，同 PaidActionGate）
// - 誠實：等級判定是確定性計算（哪些工具真的執行成功），不是 LLM 自評

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'dart:io';

/// 證據等級（L2）——Pearl 因果階梯的誠實標籤
///
/// 等級判定是確定性的：
/// - 2 干預驗證：本輪有「改變型工具」成功執行（真的動了一個變數並看到結果）
/// - 1 觀測：本輪只有「觀察型工具」成功（讀到真實狀態但未改變）
/// - 0 推測：純文字回覆，沒動手（不是禁止猜測，是強制標價）
enum EvidenceGrade {
  speculated(0, '推測'),
  observed(1, '觀測'),
  intervened(2, '干預驗證'),
  counterfactual(3, '反事實模擬'); // Phase 2 狀態分叉後才會出現

  const EvidenceGrade(this.level, this.label);
  final int level;
  final String label;

  static EvidenceGrade fromLevel(int? level) {
    switch (level) {
      case 3:
        return EvidenceGrade.counterfactual;
      case 2:
        return EvidenceGrade.intervened;
      case 1:
        return EvidenceGrade.observed;
      default:
        return EvidenceGrade.speculated;
    }
  }
}

/// 改變型工具——執行成功即構成「干預」（第 2 階證據）
/// [2026-09-12 修正] 以 AgentToolRegistry 實際註冊名為準
/// （教訓：canvas_place 檔名存在但註冊名是 canvas_add_node——清單必須對註冊表，不對檔名）
const _mutatingTools = <String>{
  // 程式碼/系統
  'patch_source_file', // 改程式碼
  'run_terminal', // 執行命令
  'local_code_generate', // 產生程式碼檔
  'restart_app', // 重啟 App
  'open_setting', // 開設定欄位
  // 因果引擎 L4——反事實分叉（等級 3：干預+diff，高於一般干預）
  'causal_fork',
  // 畫布（MCP 註冊名 mcp_canvas_tools.dart）
  'canvas_add_node', // 建節點
  'canvas_connect', // 連線
  'canvas_remove_node', // 刪節點
  'canvas_move_node', // 移動節點
  'canvas_update_node', // 改節點內容/參數
  'canvas_batch_connect', // 批次連線
  'canvas_auto_layout', // 一鍵排版
  'canvas_execute', // 執行工作流
  'canvas_load', // 載入畫布
  'canvas_load_template', // 套範本
  'canvas_place', // agent_loop_tools 註冊路徑（兩條註冊鏈都涵蓋）
  'canvas_send_chat', // 發訊息進對話（改變對話狀態）
  // 瀏覽器/UI
  'browser_navigate', // 導航
  'browser_click', // 點擊
  'ui_navigate', // UI 導航
  'ui_tap', // UI 點擊
  // 生成/媒體
  'generate_image', // 生成圖
  'video_download', // 下載媒體
  'frame_extract', // 抽幀產檔
  'audio_transcribe', // 轉錄產檔
  'use_move', // 使出招式（操作序列）
  'compass_propose', // 提案入羅盤
};

/// 觀察型工具——成功只構成「觀測」（第 1 階證據）
const _observingTools = <String>{
  'screen_capture',
  'canvas_screenshot',
  'canvas_look',
  'canvas_get_state',
  'canvas_get_snapshot',
  'canvas_get_topology',
  'canvas_get_annotations',
  'canvas_get_node_params',
  'canvas_detect_crossings',
  'canvas_find_nodes',
  'canvas_list',
  'canvas_navigate', // 視口操作，不改資料
  'canvas_pan_to_node', // 視口操作
  'canvas_highlight_node', // 暫態高亮，不改資料
  'read_source_file',
  'read_app_log',
  'memory_search',
  'compass_seek',
  'compass_read',
  'check_capability_status',
  'local_vision_analyze',
  'browser_screenshot',
  'ui_get_state',
  'ui_inspect',
  'list_moves',
};

/// 一筆介入帳本條目
class CausalEntry {
  final int? id;
  final String toolName;
  final String intervention; // do(什麼)：參數摘要
  final String contextDigest; // 情境摘要（任務/對話開頭）
  final String observedOutcome; // 觀測結果摘要
  final bool success;
  final String? companionId;
  final DateTime at;
  final String? turnId; // [小葵 2026-10-15 T1/D4] 五本記錄共同鑰匙

  const CausalEntry({
    this.id,
    required this.toolName,
    required this.intervention,
    required this.contextDigest,
    required this.observedOutcome,
    required this.success,
    this.companionId,
    required this.at,
    this.turnId,
  });
}

/// [因果引擎 L1] 介入帳本服務
///
/// 掛載點：AgentLoop 工具執行完成點（agent_loop.dart 咽喉）。
/// 執行即記，不靠 agent 自覺。
class CausalLedger {
  CausalLedger._();
  static final CausalLedger instance = CausalLedger._();

  Database? _db;

  /// [測試用] 重置 singleton（同 BudgetLedger.resetForTest 慣例）
  @visibleForTesting
  void resetForTest() {
    _db?.dispose();
    _db = null;
    lastError = null;
  }

  /// [歸人] ambient companionId——對話/派工期間由 ChatController 設定，
  /// 同 PaidActionGate.ambientCompanionId 模式
  String? ambientCompanionId;

  /// fail-open 但留痕——素描服務前車之鑑：靜默腐爛比失敗可怕
  String? lastError;

  Future<void> initialize({String? dbPath}) async {
    if (_db != null) return;
    try {
      final path = dbPath ?? await defaultDbPath();
      _db = sqlite3.open(path);
      _db!.execute('PRAGMA journal_mode = WAL');
      _db!.execute('''
        CREATE TABLE IF NOT EXISTS agent_causal_ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tool_name TEXT NOT NULL,
          intervention TEXT NOT NULL,
          context_digest TEXT NOT NULL,
          observed_outcome TEXT NOT NULL,
          success INTEGER NOT NULL,
          companion_id TEXT,
          created_at TEXT NOT NULL,
          turn_id TEXT  -- [小葵 2026-10-15 T1/D4] 五本記錄共同鑰匙
        )
      ''');
      // [小葵 2026-10-15 T1] 舊表冪等補欄（live DB 已存在表——CREATE IF NOT EXISTS 不會加新欄）
      final causalCols =
          _db!.select('PRAGMA table_info(agent_causal_ledger)');
      if (!causalCols.any((c) => c['name'] == 'turn_id')) {
        _db!.execute(
            'ALTER TABLE agent_causal_ledger ADD COLUMN turn_id TEXT');
      }
      _db!.execute(
          'CREATE INDEX IF NOT EXISTS idx_causal_turn ON agent_causal_ledger(turn_id)');
      _db!.execute(
          'CREATE INDEX IF NOT EXISTS idx_causal_tool ON agent_causal_ledger(tool_name)');
      _db!.execute(
          'CREATE INDEX IF NOT EXISTS idx_causal_at ON agent_causal_ledger(created_at)');
      // 環形緩衝——同 BudgetLedger：足夠反哺、不無限長大
      // [小葵 2026-10-15 T1／Fable V3 因果風險2] agent_perf 與 k1_gatekeeper
      // 是每輪必記的「心跳帳」——不佔 2000 筆工具史環形名額（原本每輪 2 筆
      // 會把真工具史推出環外）。心跳帳只留 500 筆。
      _db!.execute(
          'DELETE FROM agent_causal_ledger WHERE tool_name IN (\'agent_perf\',\'k1_gatekeeper\') '
          'AND id <= (SELECT MAX(id) FROM agent_causal_ledger) - 500');
      _db!.execute('DELETE FROM agent_causal_ledger WHERE id <= '
          '(SELECT MAX(id) FROM agent_causal_ledger) - 2000');
    } catch (e) {
      lastError = 'initialize: $e';
      debugPrint('[CausalLedger] init 失敗（fail-open，工具照常執行）: $e');
    }
  }

  static Future<String> defaultDbPath() async {
    final home = Platform.environment['HOME'] ?? '/';
    final dir = '$home/Library/Application Support/bridge_app';
    await Directory(dir).create(recursive: true);
    return '$dir/causal_ledger.db';
  }

  /// 記一筆干預。fail-open：絕不 throw、絕不影響呼叫端。
  void record(CausalEntry entry) {
    final db = _db;
    if (db == null) {
      // 未初始化——背景補初始化一次，本筆不阻塞不丟
      unawaitedInit();
      return;
    }
    try {
      db.execute(
        'INSERT INTO agent_causal_ledger '
        '(tool_name, intervention, context_digest, observed_outcome, success, companion_id, created_at, turn_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          entry.toolName,
          entry.intervention.substring(0, entry.intervention.length > 500 ? 500 : entry.intervention.length),
          entry.contextDigest.substring(0, entry.contextDigest.length > 300 ? 300 : entry.contextDigest.length),
          entry.observedOutcome.substring(0, entry.observedOutcome.length > 500 ? 500 : entry.observedOutcome.length),
          entry.success ? 1 : 0,
          entry.companionId,
          entry.at.toIso8601String(),
          entry.turnId, // [T1/D4] 與 event_ledger/correction_events 等可 join
        ],
      );
    } catch (e) {
      lastError = 'record: $e';
      debugPrint('[CausalLedger] 記帳失敗（fail-open留痕）: $e');
    }
  }

  void unawaitedInit() {
    Future(() async {
      await initialize();
    });
  }

  /// [小葵 2026-10-05 開案令] 最近一筆指定工具的紀錄（認知傷口偵測用：
  /// 上一輪 agent_perf 的完成時間——判斷「剛被罵的任務」）。
  /// 回 null = 無紀錄或 DB 不可用（fail-open）。
  CausalEntry? lastEntry({String? toolName}) {
    final db = _db;
    if (db == null) return null;
    try {
      final rows = toolName == null
          ? db.select(
              'SELECT * FROM agent_causal_ledger ORDER BY id DESC LIMIT 1')
          : db.select(
              'SELECT * FROM agent_causal_ledger WHERE tool_name = ? '
              'ORDER BY id DESC LIMIT 1',
              [toolName]);
      if (rows.isEmpty) return null;
      return _rowToEntry(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// [小葵 2026-10-05] 最近 N 筆紀錄（生命樹觀景窗「戰役」tab 用）。
  /// fail-open：未初始化或失敗回空列表。
  List<CausalEntry> recentEntries({int limit = 150}) {
    final db = _db;
    if (db == null) return const [];
    try {
      final rows = db.select(
          'SELECT * FROM agent_causal_ledger ORDER BY id DESC LIMIT ?',
          [limit]);
      return [for (final r in rows) _rowToEntry(r)];
    } catch (_) {
      return const [];
    }
  }

  /// [L3 預留 Phase 1] 反饋查詢——按工具名+情境關鍵詞檢索歷史干預。
  /// Phase 0 先用關鍵詞 LIKE（單跳、零嵌入成本）；Phase 1 升級向量檢索。
  Future<List<CausalEntry>> recallSimilar(
    String contextDigest, {
    int limit = 5,
  }) async {
    await initialize();
    final db = _db;
    if (db == null) return const [];
    try {
      // 取情境中的顯著詞（>=2字的連續中文/英文字段），單跳查詢避免噪音放大
      // [修正] 偏好取「尾部」關鍵詞——chat/canvas 路徑會把對話歷史包在
      // userMessage 前段，使用者真實指令在末端；取頭部會被歷史內容
      // 擠掉真問題（KAPPA-99 教訓）。短訊息頭尾同體，不受影響。
      final all = _keywordsOf(contextDigest);
      final seen = <String>{};
      final dedup = [for (final w in all) if (seen.add(w)) w];
      final keywords = (dedup.length <= 5 ? dedup : dedup.sublist(dedup.length - 5))
          .toList();
      if (keywords.isEmpty) return const [];
      final stmt = db.prepare(
        'SELECT * FROM agent_causal_ledger WHERE ' +
            keywords.map((_) => 'context_digest LIKE ?').join(' OR ') +
            ' ORDER BY id DESC LIMIT ?',
      );
      final rows = stmt.select([
        for (final k in keywords) '%$k%',
        limit,
      ]);
      stmt.dispose();
      return [for (final r in rows) _rowToEntry(r)];
    } catch (e) {
      lastError = 'recallSimilar: $e';
      debugPrint('[CausalLedger] 檢索失敗（fail-open回空）: $e');
      return const [];
    }
  }

  /// 統計：某工具的歷史成功率（Trust 公式可消費）
  Future<double> successRateFor(String toolName) async {
    await initialize();
    final db = _db;
    if (db == null) return -1;
    try {
      final r = db.select(
        'SELECT AVG(CAST(success AS REAL)) AS rate, COUNT(*) AS n '
        'FROM agent_causal_ledger WHERE tool_name = ?',
        [toolName],
      );
      final n = r.first['n'] as int;
      if (n == 0) return -1;
      return (r.first['rate'] as double) * 100;
    } catch (e) {
      lastError = 'successRateFor: $e';
      return -1;
    }
  }

  int get entryCount {
    final db = _db;
    if (db == null) return 0;
    try {
      final r = db.select('SELECT COUNT(*) AS n FROM agent_causal_ledger');
      return r.first['n'] as int;
    } catch (_) {
      return 0;
    }
  }

  /// [L3] 帳本是否已有條目——空帳本直接跳過檢索（省 IO，誠實不注入）
  bool get hasAnyEntries => entryCount > 0;

  CausalEntry _rowToEntry(Row r) => CausalEntry(
        id: r['id'] as int,
        toolName: r['tool_name'] as String,
        intervention: r['intervention'] as String,
        contextDigest: r['context_digest'] as String,
        observedOutcome: r['observed_outcome'] as String,
        success: (r['success'] as int) == 1,
        companionId: r['companion_id'] as String?,
        at: DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  // ─────────────────────────────────────────────
  // L2 證據等級——確定性計算（非 LLM 自評）
  // ─────────────────────────────────────────────

  /// 判定工具屬性：2=改變型 1=觀察型 0=其他（生成文本類等）
  static int toolTier(String? name) {
    if (name == null) return 0;
    // [因果引擎 L4] causal_fork = 等級 3（反事實模擬）——高於一般干預
    if (name == 'causal_fork') return 3;
    if (_mutatingTools.contains(name)) return 2;
    if (_observingTools.contains(name)) return 1;
    return 0;
  }

  /// 從本輪 turns 計算訊息的證據等級。
  /// 輸入：(工具名, 成功?) 序列——純函式，可測試。
  static EvidenceGrade gradeForTurns(List<(String?, bool?)> turns) {
    var best = 0;
    for (final (name, ok) in turns) {
      if (ok != true) continue; // 失敗的工具不構成證據
      final tier = toolTier(name);
      if (tier > best) best = tier;
      if (best >= 3) break; // [L4] 最高等級已達——反事實模擬
    }
    return EvidenceGrade.fromLevel(best);
  }

  /// 參數摘要——do(什麼) 的安全版（不記完整參數，避免 token/路徑洩漏進帳本）
  static String digestArgs(Map<String, dynamic>? args) {
    if (args == null || args.isEmpty) return '(無參數)';
    final keys = args.keys.take(3).toList();
    final buf = StringBuffer();
    for (final k in keys) {
      final v = args[k]?.toString() ?? 'null';
      buf.write('$k=${v.length > 80 ? '${v.substring(0, 80)}…' : v}; ');
    }
    return buf.toString().trim();
  }

  /// 結果摘要——安全版（截斷，只留成敗與前段內容）
  static String digestResult(String? content, bool success) {
    final head = (content ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final truncated = head.length > 300 ? head.substring(0, 300) : head;
    return '[${success ? '成功' : '失敗'}] $truncated';
  }

  static List<String> _keywordsOf(String text) {
    final matches =
        RegExp(r'[A-Za-z0-9_]{3,}|[\u4e00-\u9fff]{2,}').allMatches(text);
    return matches.map((m) => m.group(0)!).where((w) => w.length >= 2).toList();
  }

  /// [因果引擎 L3] 反饋注入格式——把歷史干預條目排成 prompt 區塊。
  /// 純函式可測試；最多 3 筆（寧精勿多——誤反哺比漏反哺毒）。
  /// [時間感合體 2026-09-12] 條目帶時間差（「3 天前」）——時鐘先行，
  /// 讓 agent 引用歷史時同時獲得正確的時間座標（骨架與血肉一起給）。
  static String? buildFeedbackSection(List<CausalEntry> entries, {DateTime? now}) {
    if (entries.isEmpty) return null;
    final n = now ?? DateTime.now();
    final buf = StringBuffer('\n# 歷史干預記錄（因果帳本自動檢索——與本任務相關）\n');
    buf.writeln('以下是你過去在類似情境真實執行過的干預與結果（可信事實，非猜測）：');
    for (final e in entries.take(3)) {
      final days = n.difference(e.at).inDays;
      final when = days <= 0
          ? '今天'
          : days == 1 ? '昨天' : days < 30 ? '$days 天前' : '${(days / 30).round()} 個月前';
      buf.writeln('- [$when｜${e.success ? '成功' : '失敗'}] ${e.toolName}'
          '（do: ${e.intervention.length > 60 ? '${e.intervention.substring(0, 60)}…' : e.intervention}）'
          '→ ${e.observedOutcome.length > 80 ? '${e.observedOutcome.substring(0, 80)}…' : e.observedOutcome}');
    }
    buf.writeln('使用規則：'
        '① 使用者問的內容若出現在上述記錄中，直接引用作答（這是你親身執行的證據，'
        '優先於記憶庫搜尋）；引用時同時說明時間（「3 天前我…」——時間差已算好，直接用）；'
        '② 同類問題優先採用成功記錄的工具與做法，不要重蹈失敗路徑；'
        '③ 記錄未涵蓋的部分仍需自行判斷——引用時註明「歷史記錄」。');
    return buf.toString();
  }
}
