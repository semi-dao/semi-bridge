// export_import_service.dart
// [教練 Agent 2026-07-28] 向量資料庫匯出/匯入服務
//
// 設計文件 §八 可攜性：
// - 匯出 manifest.json + 向量索引檔 + 大腦記憶資料庫 + 圖譜連線資料
// - 匯入到新機器：偵測路徑變了→自動更新路徑，向量索引不需要重算
//
// 匯出格式：.bridge-backup/ 目錄
//   .bridge-backup/
//     ├── manifest.json       ← 合併所有根資料夾的向量索引 manifest
//     ├── brain_container.db  ← 大腦記憶資料庫副本（含向量 + 圖譜連線）
//     └── backup_meta.json    ← 備份元資料（匯出時間、原始路徑、schema 版本）

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../brain_container/brain_database.dart';
import '../brain_container/brain_schema_sql.dart';
import 'asset_index_service.dart';
import 'asset_sandbox.dart';

/// 備份元資料
class BackupMetadata {
  final int formatVersion;
  final String createdAt;
  final String appVersion;
  final List<String> originalRootPaths;
  final String schemaVersion;
  final int fileCount;
  final int folderCount;

  const BackupMetadata({
    this.formatVersion = 1,
    required this.createdAt,
    this.appVersion = '',
    required this.originalRootPaths,
    this.schemaVersion = '',
    this.fileCount = 0,
    this.folderCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'format_version': formatVersion,
        'created_at': createdAt,
        'app_version': appVersion,
        'original_root_paths': originalRootPaths,
        'schema_version': schemaVersion,
        'file_count': fileCount,
        'folder_count': folderCount,
      };

  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    return BackupMetadata(
      formatVersion: json['format_version'] as int? ?? 1,
      createdAt: json['created_at'] as String? ?? '',
      appVersion: json['app_version'] as String? ?? '',
      originalRootPaths: (json['original_root_paths'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      schemaVersion: json['schema_version'] as String? ?? '',
      fileCount: json['file_count'] as int? ?? 0,
      folderCount: json['folder_count'] as int? ?? 0,
    );
  }
}

/// 路徑遷移記錄（匯入時偵測路徑變化用）
class PathMigration {
  /// 備份時的原始路徑
  final String oldPath;

  /// 匯入後對應的新路徑（若路徑未變則等同 oldPath）
  final String newPath;

  /// 路徑是否發生變化
  final bool pathChanged;

  /// 未自動匹配時的警告訊息（null = 成功匹配或無需遷移）
  final String? warning;

  const PathMigration({
    required this.oldPath,
    required this.newPath,
    required this.pathChanged,
    this.warning,
  });
}

/// 匯出結果
class ExportResult {
  /// 備份目錄完整路徑
  final String backupPath;

  /// 匯出的 manifest 檔案數
  final int manifestFiles;

  /// 匯出的 manifest 資料夾數
  final int manifestFolders;

  /// brain_container.db 檔案大小（bytes）
  final int dbSizeBytes;

  /// 耗時
  final Duration elapsed;

  const ExportResult({
    required this.backupPath,
    required this.manifestFiles,
    required this.manifestFolders,
    required this.dbSizeBytes,
    required this.elapsed,
  });
}

/// 匯入結果
class ImportResult {
  /// 還原的檔案記錄數
  final int restoredFiles;

  /// 還原的資料夾數
  final int restoredFolders;

  /// 路徑遷移的數量
  final int migratedPaths;

  /// 詳細路徑遷移資訊
  final List<PathMigration> pathMigrations;

  /// DB 是否成功還原
  final bool dbRestored;

  /// 耗時
  final Duration elapsed;

  const ImportResult({
    required this.restoredFiles,
    required this.restoredFolders,
    required this.migratedPaths,
    required this.pathMigrations,
    required this.dbRestored,
    required this.elapsed,
  });
}

/// 向量資料庫匯出/匯入服務（單例）
///
/// 使用方式：
/// ```dart
/// // 匯出
/// final result = await ExportImportService().exportAll('/Volumes/DATA/backup');
///
/// // 匯入（在新機器上）
/// final result = await ExportImportService().importAll('/Volumes/DATA/backup');
/// ```
class ExportImportService {
  static final ExportImportService _instance = ExportImportService._();
  factory ExportImportService() => _instance;
  ExportImportService._();

  final AssetSandbox _sandbox = AssetSandbox();
  final AssetIndexService _indexService = AssetIndexService();

  // ── 常數 ──────────────────────────────────────────────
  static const String _backupDirName = '.bridge-backup';
  static const String _manifestFileName = 'manifest.json';
  static const String _metadataFileName = 'backup_meta.json';
  static const String _dbFileName = 'brain_container.db';

  // ═══════════════════════════════════════════════════
  // 匯出
  // ═══════════════════════════════════════════════════

  /// 匯出 manifest + brain_container.db 到指定路徑
  ///
  /// [outputPath] — 匯出目標目錄（會在底下建立 .bridge-backup/ 子目錄）
  ///
  /// 流程：
  /// 1. 建立 .bridge-backup/ 目錄（若已存在則先清除）
  /// 2. 合併所有根資料夾的 manifest 寫入 manifest.json
  /// 3. 複製 brain_container.db（含向量索引 + 圖譜連線）
  /// 4. 寫入 backup_meta.json（備份元資料）
  Future<ExportResult> exportAll(String outputPath) async {
    final stopwatch = Stopwatch()..start();

    // 1. 建立 .bridge-backup/ 目錄
    final backupDir = Directory(p.join(outputPath, _backupDirName));
    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
    }
    await backupDir.create(recursive: true);

    // 2. 匯出 manifest.json（合併所有根資料夾的 manifest）
    final manifest = _indexService.manifest;
    final manifestJson =
        const JsonEncoder.withIndent('  ').convert(manifest.toJson());
    final manifestFile = File(p.join(backupDir.path, _manifestFileName));
    await manifestFile.writeAsString(manifestJson, flush: true);

    // 3. 複製 brain_container.db
    final dbPath = await _getCurrentDbPath();
    final dbFile = File(dbPath);
    var dbSize = 0;
    if (await dbFile.exists()) {
      final destDbPath = p.join(backupDir.path, _dbFileName);
      await dbFile.copy(destDbPath);
      dbSize = await dbFile.length();
    } else {
      debugPrint('[ExportImport] 警告: brain_container.db 不存在 ($dbPath)');
    }

    // 4. 寫入備份元資料
    final metadata = BackupMetadata(
      createdAt: DateTime.now().toIso8601String(),
      originalRootPaths: _sandbox.rootPaths.toList(),
      schemaVersion: kBrainSchemaVersion,
      fileCount: manifest.files.length,
      folderCount: manifest.folders.length,
    );
    final metadataFile = File(p.join(backupDir.path, _metadataFileName));
    await metadataFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(metadata.toJson()),
      flush: true,
    );

    stopwatch.stop();
    debugPrint(
      '[ExportImport] 匯出完成: ${backupDir.path} '
      '(${manifest.files.length} 檔案, ${manifest.folders.length} 資料夾, '
      '${stopwatch.elapsedMilliseconds}ms)',
    );

    return ExportResult(
      backupPath: backupDir.path,
      manifestFiles: manifest.files.length,
      manifestFolders: manifest.folders.length,
      dbSizeBytes: dbSize,
      elapsed: stopwatch.elapsed,
    );
  }

  // ═══════════════════════════════════════════════════
  // 匯入
  // ═══════════════════════════════════════════════════

  /// 從指定路徑匯入，偵測路徑變化並更新 file_path
  ///
  /// [inputPath] — 包含 .bridge-backup/ 的目錄路徑
  ///
  /// 流程：
  /// 1. 讀取 backup_meta.json + manifest.json
  /// 2. 偵測路徑變化（比對備份時的原始路徑與當前已登記的根資料夾）
  /// 3. 關閉 DB → 複製 brain_container.db → 重新開啟 DB
  /// 4. 更新 asset_index 表的 folder_root（路徑遷移）
  /// 5. 還原 manifest 到各根資料夾的 .bridge/
  ///
  /// 向量索引不需要重算 — embedding BLOB 隨 DB 一起搬移。
  Future<ImportResult> importAll(String inputPath) async {
    final stopwatch = Stopwatch()..start();

    // 1. 驗證備份目錄
    final backupDir = Directory(p.join(inputPath, _backupDirName));
    if (!await backupDir.exists()) {
      throw FileSystemException(
        '找不到備份目錄 .bridge-backup/',
        backupDir.path,
      );
    }

    // 2. 讀取備份元資料
    final metadataFile = File(p.join(backupDir.path, _metadataFileName));
    BackupMetadata? metadata;
    if (await metadataFile.exists()) {
      final json = jsonDecode(await metadataFile.readAsString());
      metadata = BackupMetadata.fromJson(json as Map<String, dynamic>);
    }

    // 3. 讀取 manifest.json
    final manifestFile = File(p.join(backupDir.path, _manifestFileName));
    VectorDbManifest? manifest;
    if (await manifestFile.exists()) {
      final json = jsonDecode(await manifestFile.readAsString());
      manifest = VectorDbManifest.fromJson(json as Map<String, dynamic>);
    }

    // 4. 偵測路徑變化
    final oldRootPaths = metadata?.originalRootPaths ?? [];
    final currentRootPaths = _sandbox.rootPaths;
    final migrations = <PathMigration>[];

    for (final oldPath in oldRootPaths) {
      final migration = await _detectPathMigration(oldPath, currentRootPaths);
      migrations.add(migration);
    }

    // 5. 複製 brain_container.db 回原位
    var dbRestored = false;
    final backupDbPath = p.join(backupDir.path, _dbFileName);
    final backupDbFile = File(backupDbPath);
    if (await backupDbFile.exists()) {
      final currentDbPath = await _getCurrentDbPath();
      final currentDbFile = File(currentDbPath);

      // 關閉已開啟的 DB 連線
      if (BrainDatabase.instance.isInitialized) {
        BrainDatabase.instance.close();
      }

      // 確保目標目錄存在
      if (!currentDbFile.parent.existsSync()) {
        currentDbFile.parent.createSync(recursive: true);
      }

      // 覆蓋 DB 檔案
      await backupDbFile.copy(currentDbPath);
      dbRestored = true;
      debugPrint('[ExportImport] DB 已還原: $currentDbPath');

      // 重新開啟 DB（後續路徑更新需要）
      await BrainDatabase.instance.initialize();
    }

    // 6. 更新 DB 中的 folder_root（路徑遷移）
    var migratedCount = 0;
    if (dbRestored) {
      for (final m in migrations.where((m) => m.pathChanged)) {
        await _updatePathsInDb(m.oldPath, m.newPath);
        migratedCount++;
      }
    }

    // 7. 還原 manifest 到各根資料夾的 .bridge/
    if (manifest != null) {
      for (final m in migrations) {
        final targetRoot = m.pathChanged ? m.newPath : m.oldPath;
        if (!await Directory(targetRoot).exists()) {
          debugPrint('[ExportImport] 跳過 manifest 還原（目錄不存在）: $targetRoot');
          continue;
        }

        await _sandbox.ensureBridgeDir(targetRoot);

        // 篩選屬於此根資料夾的 manifest 資料，並更新路徑
        final oldRoot = m.oldPath;
        final folderManifest = VectorDbManifest(
          folders: manifest.folders
              .where((f) => f.path == oldRoot)
              .map((f) => ManifestFolder(
                    path: m.pathChanged ? m.newPath : f.path,
                    addedAt: f.addedAt,
                    scanMode: f.scanMode,
                    subfolderCount: f.subfolderCount,
                    fileCount: f.fileCount,
                    excluded: f.excluded,
                  ))
              .toList(),
          files: manifest.files
              .where((f) => f.folder == oldRoot)
              .map((f) => ManifestFile(
                    path: f.path,
                    folder: m.pathChanged ? m.newPath : f.folder,
                    hash: f.hash,
                    size: f.size,
                    modified: f.modified,
                    indexed: f.indexed,
                    embedding: f.embedding,
                  ))
              .toList(),
          fastScanHints: manifest.fastScanHints,
        );

        final targetManifestFile =
            File('$targetRoot/.bridge/$_manifestFileName');
        await targetManifestFile.writeAsString(
          const JsonEncoder.withIndent('  ')
              .convert(folderManifest.toJson()),
          flush: true,
        );
      }
    }

    stopwatch.stop();
    debugPrint(
      '[ExportImport] 匯入完成: '
      '${manifest?.files.length ?? 0} 檔案, '
      '$migratedCount 路徑遷移, '
      'DB=${dbRestored ? "已還原" : "未還原"}, '
      '${stopwatch.elapsedMilliseconds}ms',
    );

    return ImportResult(
      restoredFiles: manifest?.files.length ?? 0,
      restoredFolders: manifest?.folders.length ?? 0,
      migratedPaths: migratedCount,
      pathMigrations: migrations,
      dbRestored: dbRestored,
      elapsed: stopwatch.elapsed,
    );
  }

  // ═══════════════════════════════════════════════════
  // 內部方法 — 路徑偵測
  // ═══════════════════════════════════════════════════

  /// 偵測單一根路徑的遷移
  ///
  /// 策略（依優先順序）：
  /// 1. 舊路徑仍存在 → 無需遷移
  /// 2. 已登記的根資料夾中有目錄名稱完全匹配者 → 使用該路徑
  /// 3. 只有一個已登記的根資料夾 → 使用該路徑（推定為對應）
  /// 4. 路徑尾段匹配（新路徑以舊路徑的目錄名結尾）
  /// 5. 以上都失敗 → 標記警告，路徑不變
  Future<PathMigration> _detectPathMigration(
    String oldPath,
    List<String> currentRoots,
  ) async {
    // 策略 1：舊路徑仍存在
    if (await Directory(oldPath).exists()) {
      return PathMigration(
        oldPath: oldPath,
        newPath: oldPath,
        pathChanged: false,
      );
    }

    // 策略 2：目錄名稱完全匹配
    final oldDirName = p.basename(oldPath);
    final exactMatches = currentRoots
        .where((r) => p.basename(r) == oldDirName)
        .toList();
    if (exactMatches.length == 1) {
      debugPrint('[ExportImport] 路徑匹配（名稱）: $oldPath → ${exactMatches.first}');
      return PathMigration(
        oldPath: oldPath,
        newPath: exactMatches.first,
        pathChanged: true,
      );
    }

    // 策略 3：只有一個已登記的根資料夾
    if (currentRoots.length == 1) {
      debugPrint('[ExportImport] 路徑匹配（唯一根）: $oldPath → ${currentRoots.first}');
      return PathMigration(
        oldPath: oldPath,
        newPath: currentRoots.first,
        pathChanged: true,
      );
    }

    // 策略 4：路徑尾段匹配
    for (final root in currentRoots) {
      if (root.endsWith(oldDirName)) {
        debugPrint('[ExportImport] 路徑匹配（尾段）: $oldPath → $root');
        return PathMigration(
          oldPath: oldPath,
          newPath: root,
          pathChanged: true,
        );
      }
    }

    // 策略 5：無法自動匹配
    debugPrint('[ExportImport] 警告: 找不到舊路徑的對應 ($oldPath)');
    return PathMigration(
      oldPath: oldPath,
      newPath: oldPath,
      pathChanged: false,
      warning: '無法自動匹配新路徑，請手動確認',
    );
  }

  // ═══════════════════════════════════════════════════
  // 內部方法 — DB 操作
  // ═══════════════════════════════════════════════════

  /// 取得目前 brain_container.db 的路徑
  ///
  /// 複製 BrainDatabase._getDbPath() 的邏輯，因為該方法為 private。
  /// 優先順序與 BrainDatabase 一致：
  /// 1. 使用者自訂路徑（SharedPreferences 'vault_db_directory'）
  /// 2. macOS: ApplicationSupportDirectory / iOS: ApplicationDocumentsDirectory
  Future<String> _getCurrentDbPath() async {
    // 1. 檢查使用者自訂路徑
    final customDir = await BrainDatabase.getCustomDbDirectory();
    if (customDir != null && customDir.isNotEmpty) {
      return p.join(customDir, _dbFileName);
    }

    // 2. 預設路徑
    final Directory dir;
    if (Platform.isIOS) {
      dir = await getApplicationDocumentsDirectory();
    } else if (Platform.isMacOS) {
      dir = await getApplicationSupportDirectory();
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    return p.join(dir.path, _dbFileName);
  }

  /// 更新 DB 中的舊路徑為新路徑
  ///
  /// 更新 asset_index 表的 folder_root 欄位，
  /// 以及 file_path 中以舊根路徑為前綴的絕對路徑。
  ///
  /// 注意：asset_index.file_path 通常存的是相對路徑（相對於 folder_root），
  /// 所以一般只需要更新 folder_root。但為了保險，也檢查並更新
  /// 以舊根路徑開頭的 file_path。
  Future<void> _updatePathsInDb(String oldRoot, String newRoot) async {
    if (oldRoot == newRoot) return;

    // 確保 DB 已初始化
    if (!BrainDatabase.instance.isInitialized) {
      await BrainDatabase.instance.initialize();
    }

    final db = BrainDatabase.instance.db;

    // 1. 更新 folder_root 欄位
    final folderRootUpdated = db.execute(
      'UPDATE asset_index SET folder_root = ? WHERE folder_root = ?',
      [newRoot, oldRoot],
    );
    debugPrint('[ExportImport] folder_root 更新: $oldRoot → $newRoot');

    // 2. 更新 file_path 中以舊根路徑開頭的記錄
    //    （通常 file_path 是相對路徑，但有些記錄可能存了絕對路徑）
    final rows = db.select(
      'SELECT id, file_path FROM asset_index WHERE file_path LIKE ?',
      ['$oldRoot%'],
    );

    for (final row in rows) {
      final id = row['id'] as String;
      final filePath = row['file_path'] as String;
      final newFilePath = filePath.replaceFirst(oldRoot, newRoot);
      db.execute(
        'UPDATE asset_index SET file_path = ? WHERE id = ?',
        [newFilePath, id],
      );
    }

    debugPrint('[ExportImport] 路徑遷移完成: $oldRoot → $newRoot '
        '(file_path 更新 ${rows.length} 筆)');

    // 3. 更新 manifest 中的 folder 欄位（在 manifest 還原時已處理）
    // 忽略 folderRootUpdated — SQLite execute 不回傳受影響行數
    folderRootUpdated;
  }
}
