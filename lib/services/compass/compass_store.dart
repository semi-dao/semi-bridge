// compass_store.dart
// 羅盤系統持久層 — 唯一真相源（SQLite，獨立於 brain_container.db）。
//
// 治理鐵則（docs/specs/2026-09-06-compass-system.md）：
// - 事實層只有 harvest 可寫；意義層人可寫（Agent 建議不代寫）；
//   規則層白名單制：visual 即時生效 + behavioral 需人 apply。
// - 每次規則修改 append 軌跡 {author, time, prevParams, reason}。
// - 生效的永遠只有最新值（取代不累積）；歷史完整保留。
// - DB 慣例照 brain_database.dart：sqlite3 直開 + WAL + synchronous=NORMAL。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'compass_models.dart';

/// 羅盤事件（渲染端訂閱：收到即重讀，下一幀生效）
class CompassEvent {
  final String type; // rulesChanged | organsChanged | meaningsChanged
  final Map<String, dynamic> data;
  CompassEvent(this.type, this.data);
}

/// 羅盤 store 單例
class CompassStore {
  CompassStore._();
  static final CompassStore instance = CompassStore._();

  Database? _db;
  int _version = 0;

  /// 事件流 — 羅盤 UI / galaxy 匯出器都訂閱這裡
  final _events = StreamController<CompassEvent>.broadcast();
  Stream<CompassEvent> get events => _events.stream;

  int get version => _version;
  DateTime? _lastHarvestAt;

  /// 初始化（冪等）。dbPath 傳 null = 預設位置。
  Future<void> initialize({String? dbPath}) async {
    if (_db != null) return;
    final path = dbPath ?? await defaultDbPath();
    _db = sqlite3.open(path);
    _db!.execute('PRAGMA journal_mode = WAL');
    _db!.execute('PRAGMA synchronous = NORMAL');
    _migrate();
    _loadVersion();
  }

  static Future<String> defaultDbPath() async {
    final dir = await _appSupportDir();
    return '$dir/compass_store.db';
  }

  static Future<String> _appSupportDir() async {
    // 与 brain_database 相同慣例：ApplicationSupportDirectory
    final home = Platform.environment['HOME'] ?? '/';
    final dir =
        '$home/Library/Application Support/bridge_app';
    await Directory(dir).create(recursive: true);
    return dir;
  }

  void _migrate() {
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS compass_organs (
        id TEXT PRIMARY KEY,
        system_group TEXT NOT NULL,
        name TEXT NOT NULL,
        facts_json TEXT NOT NULL,
        anchor_ok INTEGER NOT NULL DEFAULT 1,
        born_at TEXT NOT NULL
      )
    ''');
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS compass_meanings (
        organ_id TEXT NOT NULL,
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        author TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (organ_id, key)
      )
    ''');
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS compass_pitfalls (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        organ_id TEXT NOT NULL,
        text TEXT NOT NULL,
        author TEXT NOT NULL,
        at TEXT NOT NULL
      )
    ''');
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS compass_rules (
        id TEXT PRIMARY KEY,
        organ_id TEXT NOT NULL,
        description TEXT NOT NULL,
        why TEXT NOT NULL,
        params_json TEXT NOT NULL,
        kind TEXT NOT NULL DEFAULT 'visual',
        status TEXT NOT NULL DEFAULT 'active',
        updated_by TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS compass_rule_changes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rule_id TEXT NOT NULL,
        author TEXT NOT NULL,
        at TEXT NOT NULL,
        prev_params_json TEXT,
        new_params_json TEXT NOT NULL,
        reason TEXT NOT NULL
      )
    ''');
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS compass_surgeries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        organ_id TEXT,
        rule_id TEXT,
        author TEXT NOT NULL,
        at TEXT NOT NULL,
        action TEXT NOT NULL,
        detail TEXT NOT NULL
      )
    ''');
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS compass_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // [T9① 2026-10-17] 心跳結果落地——不落 store 的觀測不算觀測（D9）
    // （原本只在記憶體 _last，App 重啟＝觀測史失憶）
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS compass_health (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        organ_id TEXT NOT NULL,
        status TEXT NOT NULL,
        summary TEXT,
        checked_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_compass_health_organ_time
        ON compass_health(organ_id, checked_at DESC);
    ''');
  }

  /// [T9①] 心跳結果寫入（heartbeat 每 tick 呼叫；fail-quiet）
  void recordHealth(String organId, String status, String summary) {
    try {
      _db?.execute(
        'INSERT INTO compass_health (organ_id, status, summary, checked_at) '
        'VALUES (?, ?, ?, ?)',
        [organId, status, summary, DateTime.now().toIso8601String()],
      );
    } catch (_) {}
  }

  /// [小葵 2026-09-10 Blue 羅盤強大功能令] meta 讀寫——intent 索引等
  /// 滾動升級資料住這（compass_meta 表，key/value）
  void _bumpVersion() => _version++;

  String? getMeta(String key) {
    final row = _db!
        .select('SELECT value FROM compass_meta WHERE key = ?', [key]);
    if (row.isEmpty) return null;
    return row.first['value'] as String?;
  }

  void setMeta(String key, String value) {
    _db!.execute(
        'INSERT OR REPLACE INTO compass_meta (key, value) VALUES (?, ?)',
        [key, value]);
    _bumpVersion();
  }

  void _loadVersion() {
    final row = _db!
        .select('SELECT value FROM compass_meta WHERE key = ?', ['version'])
        .toList();
    final rawVersion = row.isEmpty ? '0' : row.first.values.first;
    _version = int.tryParse('$rawVersion') ?? 0;
    final h = _db!
        .select(
            'SELECT value FROM compass_meta WHERE key = ?', ['lastHarvestAt'])
        .toList();
    if (h.isNotEmpty) {
      _lastHarvestAt = DateTime.tryParse('${h.first.values.first}');
    }
  }

  void _bump(String author, String action, String detail,
      {String? organId, String? ruleId}) {
    _version += 1;
    _db!.execute(
        'INSERT OR REPLACE INTO compass_meta (key, value) VALUES (?, ?)',
        ['version', '$_version']);
    _db!.execute(
        'INSERT INTO compass_surgeries (organ_id, rule_id, author, at, action, detail) VALUES (?, ?, ?, ?, ?, ?)',
        [
          organId,
          ruleId,
          author,
          DateTime.now().toIso8601String(),
          action,
          detail,
        ]);
  }

  // ─────────────────────────────────────────────
  // 器官（事實層 — 只有 harvest 可寫）
  // ─────────────────────────────────────────────

  void upsertOrgan(CompassOrgan organ, {required String byHarvest}) {
    _db!.execute(
        'INSERT INTO compass_organs (id, system_group, name, facts_json, anchor_ok, born_at) VALUES (?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET system_group=excluded.system_group, name=excluded.name, facts_json=excluded.facts_json, anchor_ok=excluded.anchor_ok',
        [
          organ.id,
          organ.systemGroup,
          organ.name,
          jsonEncode(organ.facts.toJson()),
          organ.anchorOk ? 1 : 0,
          DateTime.now().toIso8601String(),
        ]);
    _bump(byHarvest, 'harvest', '器官 ${organ.id} 事實層更新', organId: organ.id);
    _events.add(CompassEvent('organsChanged', {'organId': organ.id}));
  }

  List<CompassOrgan> organs({bool includeRetired = false}) {
    if (_db == null) return [];
    final clause = includeRetired ? '' : "WHERE system_group != '已退役'";
    final rows = _db!
        .select('SELECT * FROM compass_organs $clause ORDER BY system_group, id');
    return rows.map((r) {
      final factsJson = jsonDecode(r['facts_json'] as String)
          as Map<String, dynamic>;
      return CompassOrgan(
        id: r['id'] as String,
        systemGroup: r['system_group'] as String,
        name: r['name'] as String,
        facts: OrganFacts.fromJson(factsJson),
        anchorOk: (r['anchor_ok'] as int) == 1,
      );
    }).toList();
  }

  // ─────────────────────────────────────────────
  // 意義層（人擁有）
  // ─────────────────────────────────────────────

  void setMeaning(String organId, String key, String value,
      {required String author}) {
    _db!.execute(
        'INSERT INTO compass_meanings (organ_id, key, value, author, updated_at) VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT(organ_id, key) DO UPDATE SET value=excluded.value, author=excluded.author, updated_at=excluded.updated_at',
        [
          organId,
          key,
          value,
          author,
          DateTime.now().toIso8601String(),
        ]);
    _bump(author, 'meaningEdit', '$organId.$key', organId: organId);
    _events.add(CompassEvent('meaningsChanged', {'organId': organId, 'key': key}));
  }

  /// 意義層：Agent 不許代寫——權限鐵則（拋例外由呼叫端呈現，不靜默吞）
  void assertHumanWrite(String author) {
    if (author.startsWith('agent:')) {
      throw StateError(
          'Agent 不可直接寫入意義層（$author）——請以建議方式提交給人類');
    }
  }

  Map<String, CompassMeaningField> meaningsOf(String organId) {
    if (_db == null) return {};
    final rows = _db!.select(
        'SELECT * FROM compass_meanings WHERE organ_id = ?', [organId]);
    final out = <String, CompassMeaningField>{};
    for (final r in rows) {
      final f = CompassMeaningField(
        organId: r['organ_id'] as String,
        key: r['key'] as String,
        value: r['value'] as String,
        author: r['author'] as String,
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );
      out[f.key] = f;
    }
    return out;
  }

  // ─────────────────────────────────────────────
  // 規則層（白名單制）
  // ─────────────────────────────────────────────

  /// 寫入規則參數。
  /// - visual 規則：即時生效（status=active）
  /// - behavioral 規則：進 pendingApply，等人 applyRule() 才生效
  /// Agent 與人都走這裡；差別只在 behavioral 需要人按套用。
  void updateRuleParams(
    String ruleId, {
    required Map<String, dynamic> newParams,
    required String author,
    required String reason,
  }) {
    final existing = rule(ruleId);
    if (existing == null) {
      throw StateError('規則 $ruleId 不存在——請先用 seedRules 註冊');
    }
    final prev = existing.params;
    final next = existing.kind == CompassRuleKind.behavioral
        ? existing.copyWith(
            params: newParams, status: CompassRuleStatus.pendingApply,
            updatedBy: author, updatedAt: DateTime.now())
        : existing.copyWith(
            params: newParams, updatedBy: author, updatedAt: DateTime.now());

    _db!.execute(
        'UPDATE compass_rules SET params_json = ?, status = ?, updated_by = ?, updated_at = ? WHERE id = ?',
        [
          jsonEncode(next.params),
          next.status.name,
          next.updatedBy,
          next.updatedAt.toIso8601String(),
          ruleId,
        ]);
    _db!.execute(
        'INSERT INTO compass_rule_changes (rule_id, author, at, prev_params_json, new_params_json, reason) VALUES (?, ?, ?, ?, ?, ?)',
        [
          ruleId,
          author,
          DateTime.now().toIso8601String(),
          jsonEncode(prev),
          jsonEncode(newParams),
          reason,
        ]);
    _bump(author, 'ruleChange', '$ruleId → ${jsonEncode(newParams)}',
        ruleId: ruleId, organId: existing.organId);
    _events.add(CompassEvent('rulesChanged', {'ruleId': ruleId}));
  }

  /// [小葵 2026-10-05 Blue 開案] agent 立案新規則——
  /// 給「方案需要新規則」一條正路：建 pendingApply 的 behavioral 規則，
  /// 等使用者在羅盤 UI 裁決套用。立新規則比改舊規則敏感，永不即時生效。
  /// 已存在同 id → 拋錯（改參數請走 updateRuleParams）。
  void createRule(
    String ruleId, {
    required String organId,
    required String description,
    required String why,
    required Map<String, dynamic> params,
    required CompassRuleKind kind,
    required String author,
  }) {
    if (_db == null) throw StateError('CompassStore 未開啟');
    if (rule(ruleId) != null) {
      throw StateError('規則 $ruleId 已存在——改參數請走 updateRuleParams');
    }
    final now = DateTime.now();
    _db!.execute(
        'INSERT INTO compass_rules (id, organ_id, description, why, params_json, kind, status, updated_by, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          ruleId,
          organId,
          description,
          why,
          jsonEncode(params),
          kind.name,
          // 立新規則一律待套用（behavioral 門檻）——人按「套用」才 active
          CompassRuleStatus.pendingApply.name,
          author,
          now.toIso8601String(),
        ]);
    _db!.execute(
        'INSERT INTO compass_rule_changes (rule_id, author, at, prev_params_json, new_params_json, reason) VALUES (?, ?, ?, ?, ?, ?)',
        [ruleId, author, now.toIso8601String(), '{}', jsonEncode(params), '立案提案：$why']);
    _bump(author, 'ruleCreate', '立案 $ruleId', ruleId: ruleId, organId: organId);
    _events.add(CompassEvent('rulesChanged', {'ruleId': ruleId}));
  }

  /// 人按「套用」：pendingApply → active（behavioral 規則的生效門）
  void applyRule(String ruleId, {required String byHuman}) {
    assertHumanWrite(byHuman);
    final r = rule(ruleId);
    if (r == null) throw StateError('規則 $ruleId 不存在');
    _db!.execute(
        "UPDATE compass_rules SET status = 'active', updated_by = ?, updated_at = ? WHERE id = ?",
        [byHuman, DateTime.now().toIso8601String(), ruleId]);
    _bump(byHuman, 'ruleApply', '$ruleId 套用生效', ruleId: ruleId, organId: r.organId);
    _events.add(CompassEvent('rulesChanged', {'ruleId': ruleId}));
  }

  /// 一鍵回滾：回到上一筆變更前的參數（visual 即時生效；behavioral 進 pendingApply）
  void rollbackRule(String ruleId, {required String byHuman}) {
    assertHumanWrite(byHuman);
    final last = _db!.select(
        'SELECT * FROM compass_rule_changes WHERE rule_id = ? ORDER BY id DESC LIMIT 1',
        [ruleId]);
    if (last.isEmpty) throw StateError('$ruleId 沒有可回滾的歷史');
    final prev = jsonDecode(last.first['prev_params_json'] as String)
        as Map<String, dynamic>;
    updateRuleParams(ruleId,
        newParams: prev,
        author: byHuman,
        reason: '一鍵回滾到 ${last.first['at']}');
  }

  /// 退役規則（append-only 治理：標 retired 保留歷史，不刪除）
  /// [小葵 2026-09-07] 2D 圖譜退役——simGate/veinEdge/xrefEdge 走此路
  void retireRule(String ruleId, {required String byHuman, String? reason}) {
    assertHumanWrite(byHuman);
    final r = rule(ruleId);
    if (r == null) throw StateError('規則 $ruleId 不存在');
    _db!.execute(
        "UPDATE compass_rules SET status = 'retired', updated_by = ?, updated_at = ? WHERE id = ?",
        [byHuman, DateTime.now().toIso8601String(), ruleId]);
    _bump(byHuman, 'ruleRetire',
        '$ruleId 退役${reason != null ? '：$reason' : ''}',
        ruleId: ruleId, organId: r.organId);
    _events.add(CompassEvent('rulesChanged', {'ruleId': ruleId}));
  }

  /// 退役器官（同 append-only：標記而非刪除）
  void retireOrgan(String organId, {required String byHuman, String? reason}) {
    assertHumanWrite(byHuman);
    final exists = _db!.select(
        'SELECT id FROM compass_organs WHERE id = ?', [organId]);
    if (exists.isEmpty) return; // 冪等
    // [小葵 2026-09-11 修] 真冪等——舊版只檢查器官存在就再附加「（退役）」，
    // App 每次重啟都串一次 → brain.graph2d 名稱被「（退役）」污染 200+ 次。
    // 改：已退役（system_group='已退役'）就不再動名稱。
    _db!.execute(
        "UPDATE compass_organs SET system_group = '已退役', name = CASE WHEN system_group = '已退役' THEN name ELSE name || '（退役）' END WHERE id = ?",
        [organId]);
    _bump(byHuman, 'organRetire',
        '$organId 退役${reason != null ? '：$reason' : ''}',
        organId: organId);
    _events.add(CompassEvent('organsChanged', {'organId': organId}));
  }

  CompassRule? rule(String ruleId) {
    if (_db == null) return null;
    final rows =
        _db!.select('SELECT * FROM compass_rules WHERE id = ?', [ruleId]);
    if (rows.isEmpty) return null;
    return _rowToRule(rows.first);
  }

  List<CompassRule> rules({String? organId, bool includeRetired = false}) {
    if (_db == null) return [];
    final where = <String>[];
    if (organId != null) where.add('organ_id = ?');
    if (!includeRetired) where.add("status != 'retired'");
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = _db!.select(
        'SELECT * FROM compass_rules $clause ORDER BY organ_id, id',
        organId != null ? [organId] : []);
    return rows.map(_rowToRule).toList();
  }

  CompassRule _rowToRule(Row r) => CompassRule(
        id: r['id'] as String,
        organId: r['organ_id'] as String,
        description: r['description'] as String,
        why: r['why'] as String,
        params: jsonDecode(r['params_json'] as String) as Map<String, dynamic>,
        kind: (r['kind'] as String) == 'behavioral'
            ? CompassRuleKind.behavioral
            : CompassRuleKind.visual,
        status: CompassRuleStatus.values.firstWhere(
          (s) => s.name == (r['status'] as String),
          orElse: () => CompassRuleStatus.active,
        ),
        updatedBy: r['updated_by'] as String,
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );

  List<CompassRuleChange> ruleHistory(String ruleId, {int limit = 20}) {
    if (_db == null) return [];
    final rows = _db!.select(
        'SELECT * FROM compass_rule_changes WHERE rule_id = ? ORDER BY id DESC LIMIT ?',
        [ruleId, limit]);
    return rows.map((r) => CompassRuleChange(
          id: r['id'] as int,
          ruleId: r['rule_id'] as String,
          author: r['author'] as String,
          at: DateTime.parse(r['at'] as String),
          prevParams: r['prev_params_json'] == null
              ? null
              : jsonDecode(r['prev_params_json'] as String)
                  as Map<String, dynamic>,
          newParams:
              jsonDecode(r['new_params_json'] as String) as Map<String, dynamic>,
          reason: r['reason'] as String,
        )).toList();
  }

  // ─────────────────────────────────────────────
  // 陷阱 / 手術日誌
  // ───────────────────────── harvest 寫入 ──

  void addPitfall(String organId, String text,
      {required String author}) {
    _db!.execute(
        'INSERT INTO compass_pitfalls (organ_id, text, author, at) VALUES (?, ?, ?, ?)',
        [organId, text, author, DateTime.now().toIso8601String()]);
    _bump(author, 'pitfallAdd', text, organId: organId);
    _events.add(CompassEvent('pitfallsChanged', {'organId': organId}));
  }

  List<CompassPitfall> pitfalls(String organId) {
    if (_db == null) return [];
    return _db!
        .select('SELECT * FROM compass_pitfalls WHERE organ_id = ? ORDER BY id DESC',
            [organId])
        .map((r) => CompassPitfall(
              id: r['id'] as int?,
              organId: r['organ_id'] as String,
              text: r['text'] as String,
              author: r['author'] as String,
              at: DateTime.tryParse(r['at'] as String? ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            ))
        .toList();
  }

  /// [小葵 2026-10-05 Blue 令] 全部未結案傷口（跨器官）——
  /// 夢卡「需要處理：未結案傷口 N 筆堆積」的內容展開用。
  /// pending 判定：text 含【pending（還沒被夢境銷案改寫）。
  List<CompassPitfall> pendingPitfalls({int limit = 30}) {
    if (_db == null) return [];
    return _db!
        .select(
            "SELECT * FROM compass_pitfalls WHERE text LIKE '%【pending%' ORDER BY id DESC LIMIT ?",
            [limit])
        .map((r) => CompassPitfall(
              id: r['id'] as int?,
              organId: r['organ_id'] as String,
              text: r['text'] as String,
              author: r['author'] as String,
              at: DateTime.tryParse(r['at'] as String? ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            ))
        .toList();
  }

  /// [軍醫 2026-09-17 W4] 全庫坑卡數（boot briefing 用）
  int pitfallCount() {
    if (_db == null) return 0;
    final r = _db!.select('SELECT COUNT(*) AS n FROM compass_pitfalls');
    return r.isEmpty ? 0 : (r.first['n'] as int? ?? 0);
  }

  /// [軍醫 2026-09-17 W4] 傷口自癒——以新文字（含藥方）替換 pending 案件
  void replacePitfall(int id, String newText, {required String author}) {
    if (_db == null) return;
    _db!.execute(
        'UPDATE compass_pitfalls SET text = ?, author = ?, at = ? WHERE id = ?',
        [newText, author, DateTime.now().toIso8601String(), id]);
    _events.add(CompassEvent('pitfallsChanged', {'id': id}));
  }

  List<CompassSurgeryLog> surgeries({int limit = 50}) {
    if (_db == null) return [];
    return _db!
        .select('SELECT * FROM compass_surgeries ORDER BY id DESC LIMIT ?',
            [limit])
        .map((r) => CompassSurgeryLog(
              id: r['id'] as int,
              organId: r['organ_id'] as String?,
              ruleId: r['rule_id'] as String?,
              author: r['author'] as String,
              at: DateTime.parse(r['at'] as String),
              action: r['action'] as String,
              detail: r['detail'] as String,
            ))
        .toList();
  }

  // ─────────────────────────────────────────────
  // 種子（首播）與匯出
  // ─────────────────────────────────────────────

  /// 種子規則註冊（不存在才插入——冪等）
  void seedRule(CompassRule rule) {
    _db!.execute(
        'INSERT OR IGNORE INTO compass_rules (id, organ_id, description, why, params_json, kind, status, updated_by, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          rule.id,
          rule.organId,
          rule.description,
          rule.why,
          jsonEncode(rule.params),
          rule.kind.name,
          rule.status.name,
          rule.updatedBy,
          rule.updatedAt.toIso8601String(),
        ]);
  }

  /// 供 galaxy.html（WebView 讀取用）匯出 active 規則參數
  Map<String, dynamic> exportActiveRuleParams({required String organId}) {
    final out = <String, dynamic>{};
    for (final r in rules(organId: organId)) {
      if (r.status == CompassRuleStatus.active) out[r.id] = r.params;
    }
    return out;
  }

  DateTime? get lastHarvestAt => _lastHarvestAt;

  void setLastHarvestAt(DateTime t) {
    _lastHarvestAt = t;
    _db!.execute(
        'INSERT OR REPLACE INTO compass_meta (key, value) VALUES (?, ?)',
        ['lastHarvestAt', t.toIso8601String()]);
  }

  /// 測試輔助
  void resetForTest() {
    _db?.execute('DELETE FROM compass_organs');
    _db?.execute('DELETE FROM compass_meanings');
    _db?.execute('DELETE FROM compass_pitfalls');
    _db?.execute('DELETE FROM compass_rules');
    _db?.execute('DELETE FROM compass_rule_changes');
    _db?.execute('DELETE FROM compass_surgeries');
    _db?.execute('DELETE FROM compass_meta');
    _version = 0;
    _lastHarvestAt = null;
  }

  void dispose() {
    _events.close();
    _db?.close();
    _db = null;
  }
}
