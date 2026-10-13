// brain_database.dart
// 大腦容器 SQLite 資料庫管理（單例）
// 建立日期: 2026-07-02
//
// 使用 sqlite3 package（不是 sqflite）。
// sqlite_vector 擴充透過 Dart 端 loadSqliteVectorExtension() 載入。

import 'dart:io';

import 'package:bridge_app/services/brain_container/brain_schema_sql.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite_vector/sqlite_vector.dart';

/// 大腦容器資料庫單例。
///
/// 使用方式：
/// ```dart
/// final db = BrainDatabase.instance;
/// await db.initialize();
/// final raw = db.db;
/// raw.execute('SELECT * FROM memories');
/// ```
class BrainDatabase {
  BrainDatabase._();
  static final BrainDatabase instance = BrainDatabase._();
  static String? _lastDbPath; // [v194] DB 檔案路徑（背景 isolate ro 連線用）

  /// [v194] DB 檔案絕對路徑——供 GalaxyDataService 背景查詢（WAL 並行讀安全）
  static String get dbPath => _lastDbPath!;

  Database? _db;
  bool _initialized = false;
  Future<void>? _initializing;

  /// DB 檔名
  static const String _dbFileName = 'brain_container.db';

  /// SharedPreferences key for custom DB directory
  static const String _dbPathPrefKey = 'vault_db_directory';

  /// 設定自訂資料庫目錄（由安裝精靈呼叫）。
  /// 設定後下次 initialize() 會使用此路徑。
  static Future<void> setCustomDbDirectory(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dbPathPrefKey, path);
  }

  /// 取得目前設定的資料庫目錄（null = 使用預設路徑）。
  static Future<String?> getCustomDbDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dbPathPrefKey);
  }

  /// 清除自訂路徑設定（回到預設）。
  static Future<void> clearCustomDbDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dbPathPrefKey);
  }

  /// 取得 SQLite3 資料庫實例。
  /// 必須在 [initialize] 完成後呼叫。
  Database get db {
    final d = _db;
    if (d == null) {
      throw StateError('BrainDatabase 尚未初始化，請先呼叫 initialize()');
    }
    return d;
  }

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// [H2 2026-10-07] 未初始化時回 null 而非 throw——
  /// MemoryLayerService 等輕量讀者用（fail-quiet：沒開就當沒資料）。
  Database? get tryDb => _initialized ? _db : null;

  /// 初始化資料庫。
  ///
  /// 步驟：
  /// 1. 載入 sqlite_vector 擴充
  /// 2. 取得 DB 路徑（iOS: ApplicationDocumentsDirectory,
  ///    macOS: ApplicationSupportDirectory）
  /// 3. 開啟/建立資料庫
  /// 4. 依序執行所有 schema SQL
  /// 5. 版本檢查與 migration（修正 3）
  /// 6. 執行 seed data（改善 2）
  /// 7. vector_init 重複執行防護（改善 5）
  /// 8. [教練 Agent 2026-08-02] 啟動驗證：檢查 DB 完整性
  Future<void> initialize() async {
    if (_initialized) return;

    // sqlite3 的 Database / extension 初始化不可重入。App 啟動、onboarding
    // 與背景服務可能同時要求 DB；它們必須等待同一個初始化 Future。
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

    // 1. 載入 sqlite_vector 擴充
    _loadSqliteVector();

    // 2. 取得 DB 路徑
    final dbPath = await _getDbPath();
    _lastDbPath = dbPath; // [v194] 供背景 isolate 查詢用（galaxy 根治）

    // 3. 開啟資料庫
    _db = sqlite3.open(dbPath);

    // 開啟外鍵支援
    _db!.execute('PRAGMA foreign_keys = ON');
    // [v189 小葵 凍結根治令] WAL 模式+synchronous=NORMAL——SQLite 官方建議：
    // WAL=寫入不阻塞讀取（讀寫分離檔）、NORMAL=不每筆交易同步 fsync——
    // 之前 rollback journal 模式的同步刷盤在 main thread 可堵數十 ms=脈衝凍結。
    _db!.execute('PRAGMA journal_mode = WAL');
    _db!.execute('PRAGMA synchronous = NORMAL');
    _db!.execute('PRAGMA wal_autocheckpoint = 512'); // 半自動 checkpoint（頁數小步做，避免突發大停頓）

    // 4. 執行 CREATE TABLE（不含索引）
    // [S23b 修復] 建表和建索引分開，中間插入 migration，
    // 確保 migration 新增的欄位在建索引時已存在。
    for (final sql in brainCreateTableStatements) {
      _db!.execute(sql);
    }

    // 5. 版本檢查與 migration（修正 3）
    //    在建索引之前執行，確保 ALTER TABLE ADD COLUMN 已完成
    _runMigrations();

    // 6. 執行 CREATE INDEX（migration 之後，欄位已齊全）
    for (final sql in brainCreateIndexStatements) {
      _db!.execute(sql);
    }

    // 7. 執行 seed data（改善 2）
    for (final sql in brainSeedStatements) {
      _db!.execute(sql);
    }

    // 7. vector_init 重複執行防護（改善 5）
    _runVectorInitIfNeeded();
    _runAssetVectorInitIfNeeded();
    _runChunkVectorInitIfNeeded(); // [教練 Agent 2026-08-20] 鐵三角 #3
    _runAgentVectorInitIfNeeded(); // [小葵 2026-09-21] agent_memories 語意可達

    // 8. [教練 Agent 2026-08-02] 啟動驗證：檢查 DB 完整性
    _validateDbIntegrity(dbPath);

    _initialized = true;
  }

  /// 版本檢查與 migration（修正 3）。
  ///
  /// - 若 brain_meta.schema_version 不存在（首次建立）：寫入當前版本。
  /// - 若版本 < 當前：執行對應 migration steps。
  /// - 若版本 == 當前：跳過。
  void _runMigrations() {
    final currentVersion = kBrainSchemaVersion;

    // 讀取現有版本
    final result = _db!.select('SELECT value FROM brain_meta WHERE key = ?', [
      'schema_version',
    ]);

    if (result.isEmpty) {
      // 首次建立 — 寫入當前版本
      _setMeta('schema_version', currentVersion);
      return;
    }

    final dbVersion = result.first['value'] as String;

    // 版本相同 — 無需 migration
    if (dbVersion == currentVersion) return;

    // 執行由舊版本到當前版本的所有 migration steps
    final dbVersionInt = int.tryParse(dbVersion) ?? 1;
    final currentVersionInt = int.tryParse(currentVersion) ?? 1;

    if (dbVersionInt < currentVersionInt) {
      for (var v = dbVersionInt; v < currentVersionInt; v++) {
        final migrationKey = 'from_v${v}_to_v${v + 1}';
        final steps = brainMigrations[migrationKey];
        if (steps != null) {
          for (final sql in steps) {
            _db!.execute(sql);
          }
        }
      }
      // 更新版本號
      _setMeta('schema_version', currentVersion);
    }
  }

  /// vector_init（改善 5 → 2026-08-20 重寫）。
  ///
  /// [教練 Agent 2026-08-20] 鐵三角 #3 實測發現：vector_init 是 per-connection
  /// 記憶體態組態——寫不進 DB、重啟即失憶。原本的「brain_meta 標記防護」
  /// 是錯的：第二次開連線看到標記就跳過 → vector_full_scan 每次報
  /// 「unable to retrieve context」→ 全部查詢靜默失敗。
  ///
  /// 正解：每次開連線都重跑（輕量、無副作用、0.3ms），meta 標記只留
  /// 診斷用途不再當防護。
  void _runVectorInitIfNeeded() {
    _db!.execute(kVectorInitSql);
    _setMeta('vector_init_done', 'true');
  }

  /// [教練 Agent 2026-08-20] 鐵三角 #3——asset_index 向量索引初始化。
  /// 同上：per-connection，每次開連線必跑。
  void _runAssetVectorInitIfNeeded() {
    _db!.execute(kAssetVectorInitSql);
    _setMeta('asset_init_last_run', DateTime.now().toIso8601String());
  }

  /// [教練 Agent 2026-08-20] 鐵三角 #1——asset_chunks 向量索引初始化。
  /// 同上：per-connection，每次開連線必跑。
  void _runChunkVectorInitIfNeeded() {
    _db!.execute(kChunkVectorInitSql);
  }

  /// [小葵 2026-09-21] agent_memories 向量索引初始化（搬家行囊語意可達的最後一里）。
  /// 同鐵三角：per-connection，每次開連線必跑。
  void _runAgentVectorInitIfNeeded() {
    _db!.execute(kAgentVectorInitSql);
  }

  /// 寫入 brain_meta（改善 3：參數化）。
  ///
  /// 使用 INSERT OR REPLACE + 參數化綁定，避免 SQL 注入。
  /// [Step 6 2026-08-18 復活] 把最後寫入的記憶改到指定房間（BridgeService 用）
  Future<void> overrideLatestMemoryRoom(String room) async {
    final db = _db;
    if (db == null || !_initialized) return;
    db.execute('''
      UPDATE memories
      SET room = ?, updated_at = ?
      WHERE id = (
        SELECT id FROM memories ORDER BY created_at DESC, rowid DESC LIMIT 1
      )
    ''', [room, DateTime.now().millisecondsSinceEpoch]);
  }

  void _setMeta(String key, String value) {
    final now = DateTime.now().toIso8601String();
    _db!.execute(
      'INSERT OR REPLACE INTO brain_meta (key, value, updated_at) VALUES (?, ?, ?)',
      [key, value, now],
    );
  }

  /// 載入 sqlite_vector 擴充。
  ///
  /// sqlite3 package 的 loadSqliteVectorExtension() 會自動找到
  /// 隨 package 帶入的原生擴充庫，不需要手動指定路徑。
  void _loadSqliteVector() {
    try {
      sqlite3.loadSqliteVectorExtension();
    } catch (e) {
      throw StateError('載入 sqlite_vector 擴充失敗: $e');
    }
  }

  /// 取得 DB 檔案路徑。
  ///
  /// 優先順序：
  /// 1. 使用者自訂路徑（SharedPreferences 'vault_db_directory'）— 安裝精靈設定
  /// 2. macOS: ApplicationSupportDirectory / iOS: ApplicationDocumentsDirectory
  ///
  /// [教練 Agent 2026-07-22] Phase 1 ③ 支援 DB 路徑指定（如外接碟）
  /// [教練 Agent 2026-08-02] 收斂：DB 路徑單一化 + 啟動驗證
  ///   - 檢查 DB 檔案是否存在且 size > 0
  ///   - 如果無效，fallback 到 ApplicationSupport 路徑
  ///   - 加 debugPrint 報告最終路徑和大小
  Future<String> _getDbPath() async {
    // 先取得預設路徑（確保 dbFile 總是有值）
    final Directory defaultDir;
    if (Platform.isIOS) {
      defaultDir = await getApplicationDocumentsDirectory();
    } else if (Platform.isMacOS) {
      defaultDir = await getApplicationSupportDirectory();
    } else {
      defaultDir = await getApplicationDocumentsDirectory();
    }
    File dbFile = File('${defaultDir.path}/$_dbFileName');
    if (!dbFile.parent.existsSync()) {
      dbFile.parent.createSync(recursive: true);
    }

    // 1. 檢查使用者自訂路徑
    final customDir = await getCustomDbDirectory();
    bool isValidDb = false;

    if (customDir != null && customDir.isNotEmpty) {
      final customDbFile = File('$customDir/$_dbFileName');
      if (!customDbFile.parent.existsSync()) {
        // [小葵 2026-09-12] 外接碟未掛載根治——自訂路徑的父目錄不存在時，
        // 絕不 createSync（在外接碟上會 Permission denied 直接炸掉
        // 整個 BrainContainer 初始化，連本地 DB fallback 都沒機會跑）。
        // 改為：跳過自訂路徑 → fallback 預設路徑（本地 956MB DB 完好），
        // 碟掛回後自動回到自訂路徑。設定的意圖保留，不等於硬崩潰。
        debugPrint(
          '[BrainDatabase] 自訂路徑父目錄不存在（磁碟未掛載？），'
          'fallback 預設路徑: ${customDbFile.parent.path}',
        );
      } else if (customDbFile.existsSync()) {
        final size = customDbFile.lengthSync();
        if (size > 0) {
          isValidDb = true;
          dbFile = customDbFile;
          debugPrint(
            '[BrainDatabase] 使用自訂路徑 DB: ${dbFile.path}, size: $size bytes',
          );
        } else {
          debugPrint(
            '[BrainDatabase] 自訂路徑 DB 大小為 0，fallback: ${customDbFile.path}',
          );
        }
      } else {
        debugPrint(
          '[BrainDatabase] 自訂路徑 DB 不存在，fallback: ${customDbFile.path}',
        );
      }
    }

    // 2. Fallback — 預設路徑（如果自訂路徑無效）
    if (!isValidDb) {
      // 驗證預設路徑的 DB
      if (dbFile.existsSync()) {
        final size = dbFile.lengthSync();
        if (size > 0) {
          debugPrint(
            '[BrainDatabase] 使用預設路徑 DB: ${dbFile.path}, size: $size bytes',
          );
        } else {
          debugPrint('[BrainDatabase] 預設路徑 DB 大小為 0，將建立新 DB: ${dbFile.path}');
        }
      } else {
        debugPrint('[BrainDatabase] 預設路徑 DB 不存在，將建立新 DB: ${dbFile.path}');
      }
    }

    return dbFile.path;
  }

  /// [教練 Agent 2026-08-02] 啟動驗證：檢查 DB 完整性
  ///
  /// 檢查項目：
  /// - 檢查 DB 檔案大小是否合理
  /// - 檢查 asset_index 是否有資料
  /// - 如果 DB size > 100KB 但 asset_index COUNT(*) == 0，可能 DB 有問題
  void _validateDbIntegrity(String dbPath) {
    final dbFile = File(dbPath);
    final dbSize = dbFile.existsSync() ? dbFile.lengthSync() : 0;

    debugPrint('[BrainDatabase] 驗證 DB 完整性: $dbPath, size: $dbSize bytes');

    // 檢查 asset_index
    try {
      final result = _db!.select('SELECT COUNT(*) as total FROM asset_index');
      final total = result.first['total'] as int;

      debugPrint('[BrainDatabase] asset_index 總數: $total');

      // 警告：DB 大小正常但沒有 asset_index 資料
      if (dbSize > 100 * 1024 && total == 0) {
        debugPrint(
          '[BrainDatabase] ⚠️ 警告：DB 大小 > 100KB 但 asset_index 沒有資料，可能 DB 有問題',
        );
      }
    } catch (e) {
      debugPrint('[BrainDatabase] 檢查 asset_index 時發生錯誤: $e');
    }
  }

  /// 關閉資料庫。
  void close() {
    _db?.close();
    _db = null;
    _initialized = false;
  }
}
