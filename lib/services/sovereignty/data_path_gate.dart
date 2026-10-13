// data_path_gate.dart
// [資料主權 P0-a 2026-09-14] 單一咽喉點——所有對外 HTTP 請求的中央閘門
// 提案：docs/specs/2026-09-14-data-sovereignty-design.md §4.1（commit ecfc3537）
//
// 病根：B1 暗管（vision_embedding_pipeline 硬編碼 api.openai.com、key 從
// ~/.openai_key 明文檔讀）證明「靠紀律」不可靠——必須有結構。
// 與 PaidActionGate 裝在 BridgeActionExecutor 咽喉點同構
// （$33 事件教訓：數所有到錢的路，不是數所有已知的門）。
//
// 分級（確定性判定，非 LLM 自評）：
//   green  127.0.0.1 / localhost / ::1 → 本地封閉迴路，資料不出這台機器
//   yellow 金鑰匙已註冊金鑰的 provider 網域 → 直連 {provider}，
//          僅你與該商的合約，橋樑不經手
//   red    白名單以外任何網域 → 攔截（throw DataPathViolationException，
//          請求不得發出）。B1 那種硬編碼暗管會被當場擋下。
//
// 設計鐵則（沿用 CausalLedger / BudgetLedger 慣例）：
// - singleton + sqlite3 同步 API + WAL
// - ledger fail-open：記帳失敗絕不影響判定本身，但必留錯誤痕跡
//   （gate 判定是安全邊界，記帳是透明度——兩件事，後者壞了不連坐前者）
// - 環形 90 天：sovereignty_ledger.db 只保留 90 天，不無限長大
// - 紅燈先記帳再攔截：被擋的請求也是主權紀錄（誰想外傳、什麼資料）

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'dart:io';

import '../provider_registry.dart';
import '../billing_modes.dart';
import '../storage_service.dart';

/// 資料路徑分級
enum DataPathGrade {
  green('green', '本地封閉迴路，資料不出這台機器'),
  yellow('yellow', '直連已註冊 provider，僅你與該商的合約，橋樑不經手'),
  red('red', '白名單以外網域——攔截，需使用者明示同意才能放行');

  const DataPathGrade(this.wire, this.label);
  final String wire; // ledger 儲存值
  final String label;
}

/// 資料分類（ledger 欄位 data_class）
enum DataPathClass {
  text('text'),
  image('image'),
  audio('audio'),
  doc('doc'),
  webTraffic('web_traffic'); // [C4] 插槽對外流量

  const DataPathClass(this.wire);
  final String wire;

  static DataPathClass fromWire(String? s) => DataPathClass.values
      .firstWhere((e) => e.wire == s, orElse: () => DataPathClass.text);
}

/// 請求目的（ledger 欄位 purpose）
enum DataPathPurpose {
  mainChat('main_chat'),
  memoryExtract('memory_extract'),
  vision('vision'),
  delegate('delegate'),
  review('review'),
  slotWeb('slot_web'); // [C4] 插槽網路請求

  const DataPathPurpose(this.wire);
  final String wire;

  static DataPathPurpose fromWire(String? s) => DataPathPurpose.values
      .firstWhere((e) => e.wire == s, orElse: () => DataPathPurpose.mainChat);
}

/// 紅燈攔截例外——請求不得發出。
/// 含目的網域與資料分類，讓呼叫端/使用者誠實看見「擋了什麼、為什麼」。
class DataPathViolationException implements Exception {
  final String endpointHost;
  final DataPathGrade grade;
  final DataPathClass dataClass;
  final String message;
  const DataPathViolationException({
    required this.endpointHost,
    required this.grade,
    required this.dataClass,
    required this.message,
  });
  @override
  String toString() =>
      'DataPathViolationException($endpointHost, ${grade.wire}, '
      '${dataClass.wire}): $message';
}

/// 一筆主權帳本條目
class SovereigntyEntry {
  final int? id;
  final String endpointHost;
  final DataPathClass dataClass;
  final int payloadBytes;
  final DataPathPurpose purpose;
  final String? keySource; // golden_key / local / none
  final DataPathGrade grade;
  final DateTime ts;

  const SovereigntyEntry({
    this.id,
    required this.endpointHost,
    required this.dataClass,
    this.payloadBytes = 0,
    required this.purpose,
    this.keySource,
    required this.grade,
    required this.ts,
  });
}

/// [資料主權 P0-a] DataPathGate——所有對外 HTTP 請求的單一咽喉點
///
/// 掛載點（P0-b 起逐路收編）：LLM chat/completions、vision、embedding API。
/// 本任務（P0-a）只交付閘門本體＋測試，不改任何既有呼叫點。
class DataPathGate {
  DataPathGate._();
  static final DataPathGate instance = DataPathGate._();

  static const retentionDays = 90;
  static const _localHosts = <String>{
    '127.0.0.1',
    'localhost',
    '::1',
    '0.0.0.0',
  };

  Database? _db;
  String? lastError;

  /// [測試用] 重置 singleton（同 CausalLedger.resetForTest 慣例）
  @visibleForTesting
  void resetForTest() {
    _db?.close();
    _db = null;
    lastError = null;
    _whitelistCache = null;
    keyProbeOverride = null;
  }

  /// [測試用] 金鑰探測接縫——覆寫後不碰真實 keychain/golden_keys.json。
  /// null = 走預設（StorageService.getToken）。
  @visibleForTesting
  Future<bool> Function(String providerId)? keyProbeOverride;

  // ─────────────────────────────────────────────
  // 白名單：provider 註冊網域 → providerId（唯一一份，來自 ProviderRegistry）
  // ─────────────────────────────────────────────

  Map<String, String>? _whitelistCache;

  Map<String, String> get _hostToProvider {
    final cached = _whitelistCache;
    if (cached != null) return cached;
    final map = <String, String>{};
    void register(String? baseUrl, String id) {
      final host = Uri.tryParse(baseUrl ?? '')?.host;
      if (host != null && host.isNotEmpty) map[host] = id;
    }

    // ① provider registry 官方網域（唯一一份 baseUrl 表）
    final ids = [...ProviderRegistry.cloudProviderIds, 'local', 'ollama'];
    for (final id in ids) {
      final meta = ProviderRegistry.metaOf(id);
      register(meta?.baseUrl, id);
    }
    // ② billing modes 的全部 URL（如 GLM Coding Plan = api.z.ai——
    //    09-14 實測：使用者實際 gateway 不在 registry 官方網域內，曾致誤攔）
    for (final pid in ProviderRegistry.cloudProviderIds) {
      for (final mode in BillingModes.getModes(pid)) {
        register(mode.baseUrl, pid);
      }
    }
    // ③ 使用者自訂 gateway_url（SharedPreferences 的 _keyGatewayUrl 鏈）
    //    非同步不進 this getter——由 ensureGatewayWhitelisted() 補註冊。
    _whitelistCache = map;
    return map;
  }

  /// [P0-b 實測修正 2026-09-14] 把使用者當前 gateway_url 補進白名單
  /// （非同步讀 SharedPreferences，App 啟動時與 gate 判定 miss 時各呼一次）。
  Future<void> ensureGatewayWhitelisted() async {
    try {
      final url = await StorageService.getGatewayUrl();
      final host = Uri.tryParse(url ?? '')?.host;
      if (host == null || host.isEmpty) return;
      if (_localHosts.contains(host)) return;
      // 歸屬到當前 provider 名下
      final provider = await StorageService.getProvider() ?? 'default';
      final providerId =
          ProviderRegistry.cloudProviderIds.contains(provider) ? provider : 'default';
      final known = _hostToProvider[host];
      if (known == null) {
        _whitelistCache = {..._hostToProvider, host: providerId};
      }
    } catch (_) {
      // 讀不到就跳過——registry+billing modes 已覆蓋絕大多數情況
    }
  }

  /// 金鑰探測——金鑰匙（StorageService/Keychain 鏈）已註冊才算白名單成立。
  ///
  /// [P0-b 實測修正 2026-09-14] StorageService 的 token key 是
  /// `api_token_v2_<provider>`，而 provider=null 時用「當前使用中 provider」
  /// 名義存（default 或 glm 等）——所以探測必須試三個位置：
  /// ①該 provider 名下 ②default 名下 ③當前 provider 名下。
  /// （實測抓到 api.z.ai 被誤判 red 攔截主對話——key 探測撲空所致。）
  Future<bool> _keyConfigured(String providerId) async {
    final probe = keyProbeOverride;
    if (probe != null) return probe(providerId);
    for (final pid in <String>[providerId, 'default']) {
      final token = await StorageService.getToken(provider: pid);
      if (token != null && token.trim().isNotEmpty) return true;
    }
    // 當前使用中 provider（getToken 無參數＝現行主腦鑰匙）
    final current = await StorageService.getToken();
    return current != null && current.trim().isNotEmpty;
  }

  // ─────────────────────────────────────────────
  // 咽喉點：檢查＋記帳
  // ─────────────────────────────────────────────

  /// 檢查資料去路並記帳。回傳分級；red 直接 throw（請求不得發出）。
  ///
  /// [url] 完整請求 URL；[dataClass] 送出的資料分類；
  /// [purpose] 為什麼送；[keySource] 金鑰來源（null 時自動推導：
  /// green→local、yellow→golden_key、red→none）；
  /// [payloadBytes] 送出的位元組數（可後補，先記 0）。
  Future<DataPathGrade> checkAndLog({
    required String url,
    required DataPathClass dataClass,
    required DataPathPurpose purpose,
    String? keySource,
    int payloadBytes = 0,
  }) async {
    final host = Uri.tryParse(url)?.host ?? '';
    final grade = await _classify(host);

    // key 來源：呼叫端明示優先，否則依分級自動推導（誠實標籤）
    final effectiveKeySource = keySource ??
        switch (grade) {
          DataPathGrade.green => 'local',
          DataPathGrade.yellow => 'golden_key',
          DataPathGrade.red => 'none',
        };

    // 紅燈也要記帳——被攔截的請求同樣是主權紀錄
    await record(SovereigntyEntry(
      endpointHost: host.isEmpty ? url : host,
      dataClass: dataClass,
      payloadBytes: payloadBytes,
      purpose: purpose,
      keySource: effectiveKeySource,
      grade: grade,
      ts: DateTime.now(),
    ));

    if (grade == DataPathGrade.red) {
      final known = _hostToProvider[host];
      throw DataPathViolationException(
        endpointHost: host,
        grade: grade,
        dataClass: dataClass,
        message: known == null
            ? '目的地「$host」不在金鑰匙註冊的 provider 白名單內——'
                '資料主權閘門已攔截（${dataClass.wire}／${purpose.wire}）。'
                '這是防止硬編碼暗管外傳資料的機制；'
                '若確有需要，請由使用者明示同意後在能力中心註冊該服務。'
            : '「$host」是已知 provider（$known）但金鑰匙尚未註冊金鑰——'
                '無金鑰的請求不應發出，已攔截。',
      );
    }
    return grade;
  }

  /// 分級判定——確定性計算，獨立出來便於直接測試
  Future<DataPathGrade> _classify(String host) async {
    if (host.isEmpty) return DataPathGrade.red; // 解析失敗＝不明去路＝攔截
    if (_localHosts.contains(host)) return DataPathGrade.green;
    final providerId = _hostToProvider[host];
    if (providerId != null) {
      // 金鑰匙已註冊 → 黃燈；已知 provider 但無金鑰 → 紅燈
      // （無金鑰的請求本來就發不出去，寧攔勿漏）
      if (await _keyConfigured(providerId)) return DataPathGrade.yellow;
      return DataPathGrade.red;
    }
    return DataPathGrade.red;
  }

  // ─────────────────────────────────────────────
  // Ledger——sovereignty_ledger.db（Application Support/bridge_app/）
  // ─────────────────────────────────────────────

  Future<void> initialize({String? dbPath}) async {
    if (_db != null) return;
    try {
      final path = dbPath ?? await defaultDbPath();
      _db = sqlite3.open(path);
      _db!.execute('PRAGMA journal_mode = WAL');
      _db!.execute('''
        CREATE TABLE IF NOT EXISTS sovereignty_ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          endpoint_host TEXT NOT NULL,
          data_class TEXT NOT NULL,
          payload_bytes INTEGER NOT NULL DEFAULT 0,
          purpose TEXT NOT NULL,
          key_source TEXT,
          grade TEXT NOT NULL,
          ts TEXT NOT NULL
        )
      ''');
      _db!.execute('CREATE INDEX IF NOT EXISTS idx_sovereignty_ts '
          'ON sovereignty_ledger(ts)');
      _db!.execute('CREATE INDEX IF NOT EXISTS idx_sovereignty_host '
          'ON sovereignty_ledger(endpoint_host)');
      await purgeOlderThanRetention();
    } catch (e) {
      lastError = 'initialize: $e';
      debugPrint('[DataPathGate] ledger init 失敗（fail-open，判定照常）: $e');
    }
  }

  static Future<String> defaultDbPath() async {
    final home = Platform.environment['HOME'] ?? '/';
    final dir = '$home/Library/Application Support/bridge_app';
    await Directory(dir).create(recursive: true);
    return '$dir/sovereignty_ledger.db';
  }

  /// 環形 90 天——主權帳本是透明度工具不是永久監控檔，
  /// 跟對話資料一樣屬於使用者，但只留 90 天足跡。
  Future<void> purgeOlderThanRetention({DateTime? now}) async {
    final db = _db;
    if (db == null) return;
    try {
      final cutoff =
          (now ?? DateTime.now()).subtract(const Duration(days: retentionDays));
      db.execute('DELETE FROM sovereignty_ledger WHERE ts < ?',
          [cutoff.toIso8601String()]);
    } catch (e) {
      lastError = 'purgeOlderThanRetention: $e';
      debugPrint('[DataPathGate] 環形清理失敗（fail-open留痕）: $e');
    }
  }

  /// 記一筆。fail-open：ledger 壞了不影響判定鏈，但留 lastError。
  Future<void> record(SovereigntyEntry entry) async {
    await initialize();
    final db = _db;
    if (db == null) return; // init 已失敗並留 lastError
    try {
      db.execute(
        'INSERT INTO sovereignty_ledger '
        '(endpoint_host, data_class, payload_bytes, purpose, key_source, grade, ts) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          entry.endpointHost,
          entry.dataClass.wire,
          entry.payloadBytes,
          entry.purpose.wire,
          entry.keySource,
          entry.grade.wire,
          entry.ts.toIso8601String(),
        ],
      );
      await purgeOlderThanRetention(now: entry.ts);
    } catch (e) {
      lastError = 'record: $e';
      debugPrint('[DataPathGate] 記帳失敗（fail-open留痕）: $e');
    }
  }

  /// [透明面板 P0 用] 最近 N 筆路徑紀錄（新→舊）
  Future<List<SovereigntyEntry>> recent({int limit = 50}) async {
    await initialize();
    final db = _db;
    if (db == null) return const [];
    try {
      final rows = db.select(
        'SELECT * FROM sovereignty_ledger ORDER BY id DESC LIMIT ?',
        [limit],
      );
      return [for (final r in rows) _rowToEntry(r)];
    } catch (e) {
      lastError = 'recent: $e';
      return const [];
    }
  }

  int get entryCount {
    final db = _db;
    if (db == null) return 0;
    try {
      final r = db.select('SELECT COUNT(*) AS n FROM sovereignty_ledger');
      return r.first['n'] as int;
    } catch (_) {
      return 0;
    }
  }

  SovereigntyEntry _rowToEntry(Row r) => SovereigntyEntry(
        id: r['id'] as int,
        endpointHost: r['endpoint_host'] as String,
        dataClass: DataPathClass.fromWire(r['data_class'] as String?),
        payloadBytes: (r['payload_bytes'] as int?) ?? 0,
        purpose: DataPathPurpose.fromWire(r['purpose'] as String?),
        keySource: r['key_source'] as String?,
        grade: DataPathGrade.values.firstWhere(
          (g) => g.wire == (r['grade'] as String?),
          orElse: () => DataPathGrade.red,
        ),
        ts: DateTime.tryParse(r['ts'] as String? ?? '') ?? DateTime.now(),
      );
}
