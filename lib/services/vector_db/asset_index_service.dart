// asset_index_service.dart
// [教練 Agent 2026-07-25] 向量資料庫索引服務
//
// 智慧型多維度圖書館管理員：
// - 第一次完整掃描（含子資料夾）→ 建立 manifest
// - 日常只掃表層（比對 manifest，不遞迴子資料夾）
// - 新資料夾加入時做完整掃描 + manifest 更新
//
// 整理對象是系統索引，不碰使用者檔案。
//
// 設計文件：B+-Hybrid-GraphRAG-大腦與圖書館協同架構.md §4 + §14

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'asset_sandbox.dart';
import '../activity/background_task_registry.dart';
import 'identity_embed_text.dart';
import 'embedding_progress_tracker.dart';
import 'file_classifier.dart';
import '../brain_container/brain_database.dart';
import '../brain_container/brain_container_service.dart';
import '../brain_container/embedding/embedding_service.dart';
import '../brain_container/asset_content_reembed_service.dart'; // [小葵 2026-08-28] 新檔導入後內容補嵌
import 'vision_embedding_pipeline.dart';
import 'vector_sketch_service.dart'; // [小葵 2026-10-14] fastScan junk 跳過（isJunkFolder 共用）

/// 檔案類型
enum AssetKind {
  image,      // .jpg .png .webp .heic
  video,      // .mp4 .mov
  document,   // .md .txt .pdf .docx
  audio,      // .mp3 .wav
  workflow,   // .json（工作流）
  other,
}

/// 檔案索引記錄
class AssetRecord {
  final String id;
  final String filePath;     // 相對於根資料夾的路徑
  final String folderRoot;   // 所屬根資料夾
  final String fileName;
  final String? fileExt;
  final int fileSize;
  final int fileModified;    // epoch ms
  final String indexStatus;  // pending / indexed / error
  final int? indexedAt;
  final String? title;
  final String? summary;
  final String? contentText;
  final AssetKind assetKind;
  final List<String> tags;
  final String source;       // user / agent_generated / imported
  // v8 新增
  final String room;              // 六大房間 (stream/doors/pendulums/heartMind/fraile/bridges)
  final String? projectId;        // 專案 ID（可為 null）
  final double classificationConfidence;  // 分類信心度 0-1
  final String sourceType;        // imported / system / agent
  // [小葵 2026-09-09 Blue 分層令] v14：受眾分層
  // general=一般使用者（預設搜尋可見）；technical=工程師層
  // （vendored 依賴/開發工具設定/建置產物——預設搜尋不可見）
  final String audience;
  // [教練 Agent 2026-07-31] v9: 增量更新用 file_hash
  final String? fileHash;

  const AssetRecord({
    required this.id,
    required this.filePath,
    required this.folderRoot,
    required this.fileName,
    this.fileExt,
    required this.fileSize,
    required this.fileModified,
    this.indexStatus = 'pending',
    this.indexedAt,
    this.title,
    this.summary,
    this.contentText,
    this.assetKind = AssetKind.other,
    this.tags = const [],
    this.source = 'user',
    this.room = 'bridges',
    this.projectId,
    this.classificationConfidence = 0.0,
    this.sourceType = 'imported',
    this.audience = 'general',
    this.fileHash,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'file_path': filePath,
    'folder_root': folderRoot,
    'file_name': fileName,
    'file_ext': fileExt,
    'file_size': fileSize,
    'file_modified': fileModified,
    'index_status': indexStatus,
    'indexed_at': indexedAt,
    'title': title,
    'summary': summary,
    'content_text': contentText,
    'asset_kind': assetKind.name,
    'tags': jsonEncode(tags),
    'source': source,
    'room': room,
    'project_id': projectId,
    'classification_confidence': classificationConfidence,
    'source_type': sourceType,
    'audience': audience,
    'file_hash': fileHash,
  };
}

/// 結構化蒸餾結果
/// Cerebras Knowledge 證明：結構化蒸餾比純文字摘要更有用
class DistilledContent {
  final String summary;        // 一行摘要
  final List<String> keywords; // 關鍵詞
  final String? resolution;    // 解決方案（如有）
  final List<String> systems;  // 相關系統/工具

  const DistilledContent({
    required this.summary,
    this.keywords = const [],
    this.resolution,
    this.systems = const [],
  });

  /// 合併成一個文字（用於 embedding）
  String toEmbeddingText() {
    final parts = <String>[summary];
    if (keywords.isNotEmpty) parts.addAll(keywords);
    if (resolution != null) parts.add(resolution!);
    if (systems.isNotEmpty) parts.addAll(systems);
    return parts.join(' ');
  }

  /// 用於存入 summary 欄位的文字
  String toSummaryText() {
    final parts = <String>[summary];
    if (keywords.isNotEmpty) {
      parts.add('關鍵詞: ${keywords.join(', ')}');
    }
    if (systems.isNotEmpty) {
      parts.add('系統: ${systems.join(', ')}');
    }
    if (resolution != null) {
      parts.add('解決: $resolution');
    }
    return parts.join(' | ');
  }
}

/// 掃描結果
class ScanResult {
  final int totalFiles;
  final int newFiles;
  final int updatedFiles;
  final int skippedFiles;
  final int excludedFiles;
  final List<AssetRecord> records;
  final Duration elapsed;

  const ScanResult({
    required this.totalFiles,
    required this.newFiles,
    required this.updatedFiles,
    required this.skippedFiles,
    required this.excludedFiles,
    required this.records,
    required this.elapsed,
  });
}

/// manifest 檔案結構
class VectorDbManifest {
  final int version;
  final List<ManifestFolder> folders;
  final List<ManifestFile> files;
  final FastScanHints fastScanHints;

  const VectorDbManifest({
    this.version = 1,
    this.folders = const [],
    this.files = const [],
    this.fastScanHints = const FastScanHints(),
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'folders': folders.map((f) => f.toJson()).toList(),
    'files': files.map((f) => f.toJson()).toList(),
    'fast_scan_hints': fastScanHints.toJson(),
  };

  factory VectorDbManifest.fromJson(Map<String, dynamic> json) {
    return VectorDbManifest(
      version: json['version'] as int? ?? 1,
      folders: (json['folders'] as List? ?? [])
          .map((f) => ManifestFolder.fromJson(f as Map<String, dynamic>))
          .toList(),
      files: (json['files'] as List? ?? [])
          .map((f) => ManifestFile.fromJson(f as Map<String, dynamic>))
          .toList(),
      fastScanHints: FastScanHints.fromJson(
        json['fast_scan_hints'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  VectorDbManifest copyWith({
    List<ManifestFolder>? folders,
    List<ManifestFile>? files,
    FastScanHints? fastScanHints,
  }) {
    return VectorDbManifest(
      version: version,
      folders: folders ?? this.folders,
      files: files ?? this.files,
      fastScanHints: fastScanHints ?? this.fastScanHints,
    );
  }
}

class ManifestFolder {
  final String path;
  final String addedAt;
  final String scanMode;  // full / fast
  final int subfolderCount;
  final int fileCount;
  final List<String> excluded;

  const ManifestFolder({
    required this.path,
    required this.addedAt,
    this.scanMode = 'full',
    this.subfolderCount = 0,
    this.fileCount = 0,
    this.excluded = const [],
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'added_at': addedAt,
    'scan_mode': scanMode,
    'subfolder_count': subfolderCount,
    'file_count': fileCount,
    'excluded': excluded,
  };

  factory ManifestFolder.fromJson(Map<String, dynamic> json) {
    return ManifestFolder(
      path: json['path'] as String,
      addedAt: json['added_at'] as String? ?? '',
      scanMode: json['scan_mode'] as String? ?? 'full',
      subfolderCount: json['subfolder_count'] as int? ?? 0,
      fileCount: json['file_count'] as int? ?? 0,
      excluded: (json['excluded'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class ManifestFile {
  final String path;
  final String folder;
  final String hash;
  final int size;
  final int modified;
  final bool indexed;
  final bool embedding;

  const ManifestFile({
    required this.path,
    required this.folder,
    required this.hash,
    required this.size,
    required this.modified,
    this.indexed = false,
    this.embedding = false,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'folder': folder,
    'hash': hash,
    'size': size,
    'modified': modified,
    'indexed': indexed,
    'embedding': embedding,
  };

  factory ManifestFile.fromJson(Map<String, dynamic> json) {
    return ManifestFile(
      path: json['path'] as String,
      folder: json['folder'] as String? ?? '',
      hash: json['hash'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      modified: json['modified'] as int? ?? 0,
      indexed: json['indexed'] as bool? ?? false,
      embedding: json['embedding'] as bool? ?? false,
    );
  }
}

class FastScanHints {
  final List<String> hotDirs;
  final List<String> coldDirs;
  final List<String> watchPatterns;

  const FastScanHints({
    this.hotDirs = const ['照片/', '文章/', 'images/', 'docs/'],
    this.coldDirs = const ['archive/', 'backup/', 'old/'],
    this.watchPatterns = const ['.jpg', '.md', '.pdf', '.png', '.txt'],
  });

  Map<String, dynamic> toJson() => {
    'hot_dirs': hotDirs,
    'cold_dirs': coldDirs,
    'watch_patterns': watchPatterns,
  };

  factory FastScanHints.fromJson(Map<String, dynamic> json) {
    return FastScanHints(
      hotDirs: (json['hot_dirs'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      coldDirs: (json['cold_dirs'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      watchPatterns: (json['watch_patterns'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// 向量資料庫索引服務
///
/// 負責：
/// - 掃描已登記資料夾（第一次完整掃、日常快速掃）
/// - 維護 manifest.json（檔案清單 + 快速掃描線索）
/// - 基本索引（檔名、類型、大小，不含 embedding）
class AssetIndexService {
  static final AssetIndexService _instance = AssetIndexService._();
  factory AssetIndexService() => _instance;
  AssetIndexService._();

  // [教練 Agent 2026-07-31] 雙模式嵌入用的檔案副檔名常量
  static const _imageExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.gif', '.svg', '.bmp'];
  static const _videoExtensions = ['.mp4', '.mov', '.avi', '.mkv'];

  final AssetSandbox _sandbox = AssetSandbox();

  /// manifest 快取（記憶體中）
  VectorDbManifest _manifest = const VectorDbManifest();

  /// [教練 Agent 2026-08-21] 樹指紋快取——root → 指紋（fullScan 短路用）
  final Map<String, String> _lastTreeFingerprints = {};

  // [小葵 2026-09-30 D1-F1 指紋落盤] tree fingerprint 存 brain_meta——
  // 重啟不再全量重掃（原：記憶體快取重啟歸零 → 每次啟動 30GB hash 讀取 1 小時）。
  // key: tree_fp:<root路徑hash>；value: fingerprint 字串。
  bool _fpLoadedFromDb = false;
  static const _fpKeyPrefix = 'tree_fp:';

  void _loadFingerprintsFromDb() {
    if (_fpLoadedFromDb) return;
    _fpLoadedFromDb = true;
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        "SELECT key, value FROM brain_meta WHERE key LIKE '$_fpKeyPrefix%'",
      );
      for (final r in rows) {
        final rootHash = (r['key'] as String).substring(_fpKeyPrefix.length);
        // 反查 root：value 格式 "rootPath\nfingerprint"（FNV-1a 穩定驗證）
        final raw = r['value'] as String;
        final idx = raw.indexOf('\n');
        if (idx <= 0) continue;
        final rootPath = raw.substring(0, idx);
        if (_stablePathHash(rootPath) != rootHash) continue; // 防竄改/搬移
        _lastTreeFingerprints[rootPath] = raw.substring(idx + 1);
      }
      debugPrint('[AssetIndex] 指紋快取落盤載入: ${_lastTreeFingerprints.length} roots');
    } catch (e) {
      debugPrint('[AssetIndex] 指紋落盤載入失敗（無害，走全掃）: $e');
    }
  }

  void _persistFingerprint(String root, String fp) {
    try {
      final db = BrainDatabase.instance.db;
      // [F1c] String.hashCode 每個 isolate 隨機化（重啟即變）→ key 必 miss。
      // 改穩定 digest：路徑 UTF-8 bytes 的 FNV-1a 64bit（純 Dart、無依賴）。
      final key = '$_fpKeyPrefix${_stablePathHash(root)}';
      db.execute(
        "INSERT OR REPLACE INTO brain_meta (key, value) VALUES (?, ?)",
        [key, '$root\n$fp'],
      );
    } catch (_) {/* 無害——下次掃描重存 */}
  }

  /// FNV-1a 64bit——跨啟動穩定的路徑指紋
  static String _stablePathHash(String s) {
    var h = 0xcbf29ce484222325;
    for (final b in s.codeUnits) {
      h ^= b;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  /// 唯讀：目前 manifest
  VectorDbManifest get manifest => _manifest;

  /// manifest 檔案路徑（每個根資料夾的 .bridge/ 裡各一份）
  File _manifestFile(String rootPath) {
    return File('$rootPath/.bridge/manifest.json');
  }

  // ═══════════════════════════════════════════════════
  // 載入 / 持久化
  // ═══════════════════════════════════════════════════

  /// 從磁碟載入所有已登記資料夾的 manifest
  Future<void> loadManifests() async {
    final allFolders = <ManifestFolder>[];
    final allFiles = <ManifestFile>[];
    final allHotDirs = <String>{};
    final allColdDirs = <String>{};

    for (final root in _sandbox.rootPaths) {
      final file = _manifestFile(root);
      if (await file.exists()) {
        try {
          final json = jsonDecode(await file.readAsString());
          final m = VectorDbManifest.fromJson(json);
          allFolders.addAll(m.folders);
          allFiles.addAll(m.files);
          allHotDirs.addAll(m.fastScanHints.hotDirs);
          allColdDirs.addAll(m.fastScanHints.coldDirs);
        } catch (e) {
          debugPrint('[AssetIndex] 載入 manifest 失敗 ($root): $e');
        }
      }
    }

    _manifest = VectorDbManifest(
      folders: allFolders,
      files: allFiles,
      fastScanHints: FastScanHints(
        hotDirs: allHotDirs.toList(),
        coldDirs: allColdDirs.toList(),
      ),
    );

    debugPrint('[AssetIndex] Manifest 載入完成: '
        '${allFolders.length} 資料夾, ${allFiles.length} 檔案');
  }

  /// 儲存 manifest 到指定根資料夾的 .bridge/
  Future<void> _saveManifest(String rootPath) async {
    await _sandbox.ensureBridgeDir(rootPath);

    // 篩選出屬於這個根資料夾的檔案
    final folderManifest = VectorDbManifest(
      folders: _manifest.folders
          .where((f) => f.path == rootPath)
          .toList(),
      files: _manifest.files
          .where((f) => f.folder == rootPath)
          .toList(),
      fastScanHints: _manifest.fastScanHints,
    );

    final file = _manifestFile(rootPath);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(folderManifest.toJson()),
      flush: true,
    );
  }

  // ═══════════════════════════════════════════════════
  // 掃描
  // ═══════════════════════════════════════════════════

  /// 完整掃描（第一次加入 + 新資料夾加入時）
  ///
  /// 遞迴掃描所有子資料夾，建立完整 manifest。
  ///
  /// [教練 Agent 2026-08-21] 24/7 記憶體治理——[skipIfUnchanged] 為 true 時，
  /// 先做輕量指紋走訪（檔案數＋size＋mtime 累計 hash，只 stat 不讀內容），
  /// 與上次一致就整輪跳過：不重建 records、不序列化 manifest、不寫 DB。
  /// 動機：autoIngest 每 30 分鐘兜底＋watcher 觸發的重掃，每輪都會
  /// 重建數千筆 AssetRecord＋序列化 1.2MB JSON——Dart heap 高水位
  /// 緩慢上升（9 小時 3.3GB），24/7 開機下不可持續。
  /// 指紋走訪與 _scanDirectory 同一套排除規則（.bridge/.git/tmp/…），
  /// 結果不一致（任何新增/刪除/修改）才走完整 fullScan。
  /// 真實變更不會漏：指紋不同 = 必走全掃；指紋相同 = 掃了也不會有
  /// 任何 DB/manifest 變化，跳過零損失。
  Future<ScanResult> fullScan(String rootPath,
      {bool skipIfUnchanged = false}) async {
    final stopwatch = Stopwatch()..start();
    final root = _normalizeRoot(rootPath);

    if (skipIfUnchanged) {
      _loadFingerprintsFromDb(); // [D1-F1] 重啟後也吃得到上次指紋
      final fp = await _computeTreeFingerprint(root);
      if (fp != null && fp == _lastTreeFingerprints[root]) {
        debugPrint('[AssetIndex] 指紋一致，跳過整輪 fullScan ($root) '
            '— ${_lastTreeFingerprints.length} roots cached');
        return ScanResult(
          totalFiles: 0,
          newFiles: 0,
          updatedFiles: 0,
          skippedFiles: 0,
          excludedFiles: 0,
          records: const [],
          elapsed: stopwatch.elapsed,
        );
      }
      // 指紋不同或首次：記住新指紋（全掃完成後的樹狀態）
      if (fp != null) {
        _lastTreeFingerprints[root] = fp;
        _persistFingerprint(root, fp); // [D1-F1] 落盤
      }
    }

    final records = <AssetRecord>[];
    final manifestFiles = <ManifestFile>[];
    var excluded = 0;

    await _sandbox.ensureBridgeDir(root);

    // 掃描目錄
    await _scanDirectory(
      Directory(root),
      root,
      records,
      manifestFiles,
      depth: 0,
    );

    // 更新 manifest
    final now = DateTime.now().toIso8601String();
    final existingFolders = _manifest.folders
        .where((f) => f.path != root)
        .toList();
    final existingFiles = _manifest.files
        .where((f) => f.folder != root)
        .toList();

    // [教練 Agent 2026-07-28] 保留已嵌入檔案的 embedding 標記
    // 建立舊檔案的 path → embedding 查找表
    final oldEmbeddingMap = <String, bool>{};
    for (final f in _manifest.files.where((f) => f.folder == root)) {
      oldEmbeddingMap[f.path] = f.embedding;
    }
    // 如果新掃描的檔案在舊 manifest 裡已有 embedding=true，保留它
    for (final mf in manifestFiles) {
      if (oldEmbeddingMap[mf.path] == true) {
        manifestFiles[manifestFiles.indexOf(mf)] = ManifestFile(
          path: mf.path,
          folder: mf.folder,
          hash: mf.hash,
          size: mf.size,
          modified: mf.modified,
          indexed: mf.indexed,
          embedding: true,
        );
      }
    }

    _manifest = VectorDbManifest(
      folders: [
        ...existingFolders,
        ManifestFolder(
          path: root,
          addedAt: now,
          scanMode: 'full',
          subfolderCount: _countSubdirs(records),
          fileCount: records.length,
          excluded: AssetSandbox.defaultExcludedDirs,
        ),
      ],
      files: [...existingFiles, ...manifestFiles],
      fastScanHints: _manifest.fastScanHints,
    );

    await _saveManifest(root);

    // [教練 Agent 2026-07-28] v8: 將分類結果寫入 DB
    await _writeRecordsToDb(records, root);

    // [教練 Agent 2026-08-21] 死鏈處理——檔案系統是唯一真相：這輪掃描沒看到
    /// 的（屬於此 root、已不存在於磁碟的）行，從 asset_index 移除。
    /// 動機：fullScan 只增不刪，24/7 autoIngest 下刪掉的檔案會變死鏈
    /// 永遠留在 DB／圖譜（08-21 曾手動清 6 筆）。指紋短路保證這段
    /// 只在樹真的變了才執行，成本可接受。
    /// [小葵 2026-10-06 移植自 semi-bridge 025642f 改標記制] 跨 root 搬家的
    /// 檔案舊路徑會先在這裡被掃到——直接 DELETE 會把向量一起埋掉，新 root
    /// 的 hash 對帳就沒得救了。改標 index_status='missing'：搜尋/嵌入查詢
    /// 全部過濾 ='indexed' 自然排除（行為等價於刪除），但身份（向量/描述）
    /// 保留，給 _writeRecordsToDb 的搬家對帳一個救回的機會。真的被刪除的
    /// 檔案就永遠停在 missing（無害殘跡，未來可批量清）。
    try {
      final db = BrainDatabase.instance.db;
      final currentPaths = records.map((r) => r.filePath).toSet();
      final rows = db.select(
        'SELECT file_path FROM asset_index WHERE folder_root = ?',
        [root],
      );
      var removed = 0;
      for (final row in rows) {
        final fp = row['file_path'] as String;
        if (!currentPaths.contains(fp) && !File('$root/$fp').existsSync()) {
          db.execute(
            "UPDATE asset_index SET index_status = 'missing' "
            "WHERE file_path = ? AND folder_root = ?",
            [fp, root],
          );
          removed++;
        }
      }
      if (removed > 0) {
        debugPrint('[AssetIndex] 死鏈標記 ($root): $removed 筆 → missing'
            '（搬家對帳可救回，向量不埋葬）');
      }
    } catch (e) {
      debugPrint('[AssetIndex] 死鏈標記失敗 ($root): $e');
    }

    stopwatch.stop();
    debugPrint('[AssetIndex] 完整掃描完成 ($root): '
        '${records.length} 檔案, ${stopwatch.elapsedMilliseconds}ms');

    return ScanResult(
      totalFiles: records.length,
      newFiles: records.length,
      updatedFiles: 0,
      skippedFiles: 0,
      excludedFiles: excluded,
      records: records,
      elapsed: stopwatch.elapsed,
    );
  }

  /// 日常快速掃描（App 啟動時）
  ///
  /// 只檢查 manifest 裡有記錄的檔案是否有變動，
  /// 加上 hot_dirs 裡的新檔案。不遞迴子資料夾。
  Future<ScanResult> fastScan() async {
    final stopwatch = Stopwatch()..start();
    var newCount = 0;
    var updatedCount = 0;
    var skippedCount = 0;
    final records = <AssetRecord>[];

    for (final root in _sandbox.rootPaths) {
      // 檢查 manifest 裡的檔案
      final manifestFiles = _manifest.files
          .where((f) => f.folder == root)
          .toList();

      for (final mf in manifestFiles) {
        // [小葵 2026-10-14 Blue 報案 fastScan 22s] 依賴樹 junk（venv/node_modules
        // 等 30,126 筆＝44%）不做 stat——I/O 砍近半，外接碟上尤其有感。
        // 規則與素描層/顯示層共用 isJunkFolder。
        if (VectorSketchService.isJunkFolder(mf.path)) {
          skippedCount++;
          continue;
        }
        final fullPath = '$root/${mf.path}';
        final file = File(fullPath);

        if (!await file.exists()) {
          // 檔案被刪除了，標記為離線（不刪記錄）
          continue;
        }

        final stat = await file.stat();
        final modified = stat.modified.millisecondsSinceEpoch;

        if (modified > mf.modified) {
          // 檔案有更新
          updatedCount++;
          final record = _buildRecord(file, root, stat);
          records.add(record);
        } else {
          skippedCount++;
        }
      }

      // 檢查 hot_dirs 裡的新檔案
      for (final hotDir in _manifest.fastScanHints.hotDirs) {
        final dirPath = '$root/$hotDir';
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          await for (final entity in dir.list(followLinks: false)) {
            if (entity is! File) continue;
            final relPath = p.relative(entity.path, from: root);
            final exists = manifestFiles.any((mf) => mf.path == relPath);
            if (!exists) {
              newCount++;
              final stat = await entity.stat();
              final record = _buildRecord(entity, root, stat);
              records.add(record);
            }
          }
        }
      }
    }

    stopwatch.stop();
    debugPrint('[AssetIndex] 快速掃描完成: '
        '$newCount 新, $updatedCount 更新, $skippedCount 跳過, '
        '${stopwatch.elapsedMilliseconds}ms');

    return ScanResult(
      totalFiles: newCount + updatedCount + skippedCount,
      newFiles: newCount,
      updatedFiles: updatedCount,
      skippedFiles: skippedCount,
      excludedFiles: 0,
      records: records,
      elapsed: stopwatch.elapsed,
    );
  }

  /// 對特定子資料夾做 targeted scan（補償機制）
  Future<List<AssetRecord>> targetedScan(String rootPath, String subDir) async {
    final root = _normalizeRoot(rootPath);
    final dirPath = '$root/$subDir';
    final dir = Directory(dirPath);
    final records = <AssetRecord>[];

    if (!await dir.exists()) return records;

    await _scanDirectory(dir, root, records, [], depth: 0);

    // 把這個子資料夾加入 hot_dirs（之後日常掃描會覆蓋）
    // TODO: 更新 manifest 的 hot_dirs

    debugPrint('[AssetIndex] Targeted scan ($subDir): ${records.length} 檔案');
    return records;
  }

  // ═══════════════════════════════════════════════════
  // 查詢
  // ═══════════════════════════════════════════════════

  /// 取得所有已索引的檔案記錄
  List<ManifestFile> get allFiles => List.unmodifiable(_manifest.files);

  /// 取得所有已登記的資料夾
  List<ManifestFolder> get allFolders => List.unmodifiable(_manifest.folders);

  /// 取得檔案總數
  int get fileCount => _manifest.files.length;

  /// 取得資料夾總數
  int get folderCount => _manifest.folders.length;

  // ═══════════════════════════════════════════════════
  // 內部方法
  // ═══════════════════════════════════════════════════

  /// 遞迴掃描目錄
  /// [教練 Agent 2026-08-21] 樹指紋——與 _scanDirectory 同套排除規則的輕量走訪。
  /// 回傳 "count:combineHash"；root 不存在回 null（走全掃）。
  /// 只 stat 不讀檔案內容，數千檔約數百 ms。
  Future<String?> _computeTreeFingerprint(String root) async {
    final dir = Directory(root);
    if (!dir.existsSync()) return null;
    var count = 0;
    var hash = 0;
    await _fingerprintWalk(dir, (stat) {
      count++;
      // size + mtime 混合；31 是慣用質數乘子
      hash = (hash * 31 + stat.size) ^ stat.modified.millisecondsSinceEpoch;
    });
    return '$count:${(hash & 0x7FFFFFFFFFFFFFFF).toRadixString(16)}';
  }

  Future<void> _fingerprintWalk(
      Directory dir, void Function(FileStat) onFile) async {
    try {
      await for (final entity in dir.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (entity is Directory) {
          if (AssetSandbox.isExcludedDir(name)) continue;
          if (AssetSandbox.isSyncJunkDir(name)) continue;
          // 注意：不排除一般隱藏目錄——與 _scanDirectory 行為對齊
          // （那邊只靠 isExcludedDir，隱藏目錄內的非隱藏檔仍會被掃）
          await _fingerprintWalk(entity, onFile);
        } else if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (AssetSandbox.isExcludedExt(ext)) continue;
          if (name.startsWith('.')) continue;
          // [小葵 2026-09-09 Blue 分層令] 純垃圾檔不進 manifest/索引
          if (AssetSandbox.isJunkFile(name)) continue;
          final stat = await entity.stat();
          onFile(stat);
        }
      }
    } catch (_) {
      // 讀不到的目錄：貢獻為空，與全掃的容錯行為一致
    }
  }

  Future<void> _scanDirectory(
    Directory dir,
    String root,
    List<AssetRecord> records,
    List<ManifestFile> manifestFiles, {
    required int depth,
  }) async {
    if (depth > 20) return; // 安全限制

    try {
      await for (final entity in dir.list(followLinks: false)) {
        final name = p.basename(entity.path);

        if (entity is Directory) {
          // 排除系統目錄
          if (AssetSandbox.isExcludedDir(name)) continue;
          // [教練 Agent 2026-08-21] 雲端同步暫存殘骸（.tmp.* 模式，如
          // Google Drive .tmp.driveupload）——實測曾吞 18,464 筆幽靈
          if (AssetSandbox.isSyncJunkDir(name)) continue;
          await _scanDirectory(
            entity, root, records, manifestFiles,
            depth: depth + 1,
          );
        } else if (entity is File) {
          // 排除系統檔案
          final ext = p.extension(entity.path).toLowerCase();
          if (AssetSandbox.isExcludedExt(ext)) continue;
          if (name.startsWith('.')) continue;
          // [小葵 2026-09-09 Blue 分層令] 純垃圾檔不進 manifest/索引
          if (AssetSandbox.isJunkFile(name)) continue;

          final stat = await entity.stat();
          final record = _buildRecord(entity, root, stat);
          records.add(record);

          final manifestFile = ManifestFile(
            path: p.relative(entity.path, from: root),
            folder: root,
            hash: '${stat.size}_${stat.modified.millisecondsSinceEpoch}',
            size: stat.size,
            modified: stat.modified.millisecondsSinceEpoch,
            indexed: true,
            embedding: false,
          );
          manifestFiles.add(manifestFile);
        }
      }
    } catch (e) {
      debugPrint('[AssetIndex] 掃描目錄失敗 (${dir.path}): $e');
    }
  }

  /// 從檔案建立索引記錄（含六大房間分類）
  AssetRecord _buildRecord(File file, String root, FileStat stat) {
    final path = file.path;
    final fileName = p.basename(path);
    final ext = p.extension(path).toLowerCase();
    final relPath = p.relative(path, from: root);
    final kind = _inferAssetKind(ext);

    // [教練 Agent 2026-07-28] v8: 六大房間分類
    final classification = FileClassifier.instance.classify(
      fileName: fileName,
      fileExt: ext,
    );

    return AssetRecord(
      id: '${root.hashCode}_${relPath.hashCode}',
      filePath: relPath,
      folderRoot: root,
      fileName: fileName,
      fileExt: ext,
      fileSize: stat.size,
      fileModified: stat.modified.millisecondsSinceEpoch,
      indexStatus: 'pending',
      assetKind: kind,
      title: fileName,
      source: 'user',
      room: classification.room.name,
      classificationConfidence: classification.confidence,
      sourceType: 'imported',
      // [小葵 2026-09-09 Blue 分層令] 掃描時即分層——junk 已在掃描排除，
      // technical 路徑（vendored/工具設定/build）標記分層
      audience: AssetSandbox.isTechnicalPath(relPath, folderRoot: root)
          ? 'technical'
          : 'general',
    );
  }

  /// [教練 Agent 2026-07-28] v8: 將掃描結果寫入 asset_index 表（含房間分類）
  Future<void> _writeRecordsToDb(List<AssetRecord> records, String root) async {
    if (!BrainContainerService.instance.isInitialized) {
      debugPrint('[AssetIndex] BrainContainer 未初始化，跳過 DB 寫入');
      return;
    }

    final db = BrainDatabase.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    // [小葵 2026-09-30 F1b] 批次化：原逐筆 SELECT+debugPrint，7000 檔 =
    // 7000 次查詢 + 7000 行 log——fullScan「掃描 5 根目錄」卡 80 分鐘的元兇。
    // 改一次撈全表 file_path→index_status，記憶體比對。
    final existingStatuses = <String, String>{};
    try {
      for (final row in db.select(
        "SELECT file_path, index_status FROM asset_index",
      )) {
        final fp0 = row['file_path'] as String?;
        final st0 = row['index_status'] as String?;
        if (fp0 != null && st0 != null) existingStatuses[fp0] = st0;
      }
    } catch (_) {/* 無害——fallback 逐筆 */}
    var skippedCount = 0;

    // [小葵 2026-10-06 移植自 semi-bridge 025642f] hash 優先對帳——檔案
    // 搬家/改名偵測。內容是身份，路徑只是指標（vault 只整理不動檔案的鏡像）。
    // 掃描發現的「新路徑」若內容 hash 與 DB 某筆已嵌入紀錄相同，且舊路徑
    // 已不存在於磁碟（=搬家/改名，非複製）→ 那筆搬家，向量/描述/標籤/分類
    // 全保留（零重嵌入）。跨 root 搬家也吃這條路；missing（死鏈標記）在
    // 救回名單內——復原 indexed。舊路徑還在＝複製→當新檔案走 INSERT。
    // 只對帳已嵌入（indexed/embedded/missing）的——pending 重嵌成本低。
    // 融合 F1b 批次化：hash 索引也一次撈全表。
    final hashIndex = <String, ({String root, String path})>{};
    try {
      for (final row in db.select(
        "SELECT folder_root, file_path, file_hash FROM asset_index "
        "WHERE file_hash IS NOT NULL "
        "  AND index_status IN ('indexed','embedded','missing')",
      )) {
        hashIndex[row['file_hash'] as String] = (
          root: row['folder_root'] as String,
          path: row['file_path'] as String,
        );
      }
    } catch (e) {
      debugPrint('[AssetIndex] hash 對帳索引建置失敗（無妨，跳過搬家偵測）: $e');
    }

    var relocated = 0;
    for (final r in records) {
      try {
        // ── 搬家偵測：新路徑 + 內容 hash 命中舊紀錄 ──
        String? newHash = r.fileHash;
        if (newHash == null || newHash.isEmpty) {
          // 掃描時不算 content hash——這裡補算（只在 hash 索引非空時，
          // 空 DB/首掃完全零成本）
          if (hashIndex.isNotEmpty) {
            newHash = await _computeFileHash(File('$root/${r.filePath}'));
          }
        }
        final hit = newHash == null ? null : hashIndex[newHash];
        if (newHash != null && hit != null && hit.path != r.filePath) {
          final oldFull = '${hit.root}/${hit.path}';
          final oldStillExists = File(oldFull).existsSync();
          if (!oldStillExists) {
            db.execute(
              'UPDATE asset_index SET '
              'file_path = ?, folder_root = ?, file_name = ?, file_ext = ?, '
              'file_size = ?, file_modified = ?, indexed_at = ?, '
              "index_status = 'indexed' "
              'WHERE file_path = ?',
              [r.filePath, root, r.fileName, r.fileExt, r.fileSize,
               r.fileModified, now, hit.path],
            );
            hashIndex[newHash] = (root: root, path: r.filePath);
            relocated++;
            debugPrint('[AssetIndex] 🔄 搬家偵測: ${hit.root}/${hit.path} → '
                '$root/${r.filePath}（內容相同，向量與描述保留）');
            continue;
          }
          // 舊路徑還在＝複製，兩筆並存——落到正常 INSERT 當新檔案
        }

        // [教練 Agent 2026-07-31] 修復：不要覆蓋已嵌入的記錄
        // 如果 DB 裡已有此 file_path 且 index_status != 'pending'，跳過不覆蓋
        final existing = existingStatuses.containsKey(r.filePath)
            ? <String, Object?>{'index_status': existingStatuses[r.filePath]}
            : null;

        if (existing != null) {
          final status = existing['index_status'] as String?;
          if (status == 'indexed' || status == 'embedded') {
            skippedCount++;
            continue;
          }
        }

        db.execute(
          '''INSERT INTO asset_index
             (id, file_path, folder_root, file_name, file_ext, file_size,
              file_modified, index_status, indexed_at, title, asset_kind,
              tags, source, created_at, room, project_id,
              classification_confidence, source_type, file_hash, audience)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(file_path) DO UPDATE SET
              file_name = excluded.file_name,
              file_ext = excluded.file_ext,
              file_size = excluded.file_size,
              file_modified = excluded.file_modified,
              title = excluded.title,
              asset_kind = excluded.asset_kind,
              tags = excluded.tags,
              file_hash = excluded.file_hash,
              indexed_at = excluded.indexed_at
             -- [小葵 2026-09-30 狀態機] 不碰 embed_source/embedding/content_text：
             -- INSERT OR REPLACE 會整 row 重建、丟失嵌入成果（第七金礦根因）
             --''',
          [
            r.id,
            r.filePath,
            r.folderRoot,
            r.fileName,
            r.fileExt,
            r.fileSize,
            r.fileModified,
            r.indexStatus,
            now,
            r.title,
            r.assetKind.name,
            jsonEncode(r.tags),
            r.source,
            now,
            r.room,
            r.projectId,
            r.classificationConfidence,
            r.sourceType,
            r.fileHash,
            r.audience,
          ],
        );
      } catch (e) {
        debugPrint('[AssetIndex] DB 寫入失敗 (${r.fileName}): $e');
      }
    }
    if (skippedCount > 0) {
      debugPrint('[AssetIndex] 批次完成：跳過 $skippedCount 筆已嵌入記錄（F1b 批次化）');
    }
    if (relocated > 0) {
      debugPrint('[AssetIndex] hash 對帳完成: $relocated 筆搬家（零重嵌入）');
    }

    debugPrint('[AssetIndex] DB 寫入完成: ${records.length} 筆 ($root)');
  }

  /// 從副檔名推斷檔案類型
  AssetKind _inferAssetKind(String ext) {
    switch (ext) {
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.webp':
      case '.heic':
      case '.gif':
        return AssetKind.image;
      case '.mp4':
      case '.mov':
      case '.avi':
      case '.mkv':
        return AssetKind.video;
      case '.md':
      case '.txt':
      case '.pdf':
      case '.docx':
      case '.doc':
      case '.rtf':
        return AssetKind.document;
      case '.mp3':
      case '.wav':
      case '.m4a':
      case '.flac':
        return AssetKind.audio;
      case '.json':
        return AssetKind.workflow;
      default:
        return AssetKind.other;
    }
  }

  /// 計算子目錄數
  int _countSubdirs(List<AssetRecord> records) {
    final dirs = <String>{};
    for (final r in records) {
      final parts = r.filePath.split('/');
      if (parts.length > 1) {
        dirs.add(parts.first);
      }
    }
    return dirs.length;
  }

  /// 正規化根路徑
  String _normalizeRoot(String path) {
    var p = path.trim();
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  // ═══════════════════════════════════════════════════
  // Phase 3：Embedding 生成
  // ═══════════════════════════════════════════════════

  /// 用本地 Gemma 模型蒸餾文字內容
  /// Cerebras Knowledge 證明：embed 蒸餾後的摘要比 embed 原文準確度高
  /// 蒸餾結果：一行摘要 + 關鍵詞（用於 embedding）
  Future<String> _distillText(String rawText, String fileName) async {
    const endpoint = 'http://127.0.0.1:18789/v1/chat/completions';

    // 截斷原始文字（避免超出模型 context）
    final truncated = rawText.length > 4000
        ? rawText.substring(0, 4000)
        : rawText;

    final prompt = '請閱讀以下檔案內容，生成一行摘要（50字以內）和3-5個關鍵詞，用空格分隔。'
        '只輸出摘要和關鍵詞，不要其他文字。\n\n'
        '檔名: $fileName\n'
        '內容:\n$truncated';

    try {
      final response = await Dio().post(
        endpoint,
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
        data: {
          'model': 'gemma-4-e4b',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'stream': false,
          'max_tokens': 200,
          'temperature': 0.2,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final distilled = data['choices']?[0]?['message']?['content'] as String? ?? '';
        if (distilled.trim().isNotEmpty) {
          return distilled.trim();
        }
      }
    } catch (e) {
      debugPrint('[AssetIndex] 蒸餾失敗，fallback 到原文: $e');
    }

    // fallback: 用截斷的原文
    return rawText.length > 8000 ? rawText.substring(0, 8000) : rawText;
  }

  /// 結構化蒸餾 — 用本地 Gemma 提取結構化資訊
  /// Cerebras Knowledge 證明：結構化蒸餾比純文字摘要更有用
  /// 返回：摘要 + 關鍵詞 + 解決方案 + 相關系統
  Future<DistilledContent> _distillStructured(String rawText, String fileName) async {
    const endpoint = 'http://127.0.0.1:18789/v1/chat/completions';

    final truncated = rawText.length > 4000
        ? rawText.substring(0, 4000)
        : rawText;

    final prompt = '請分析以下檔案內容，提取結構化資訊。'
        '用 JSON 格式回答，格式如下：\n'
        '{"summary": "一行摘要(50字內)", "keywords": ["關鍵詞1", "關鍵詞2"], '
        '"resolution": "解決方案(如有)", "systems": ["相關系統1"]}\n'
        '只輸出 JSON，不要其他文字。\n\n'
        '檔名: $fileName\n'
        '內容:\n$truncated';

    try {
      final response = await Dio().post(
        endpoint,
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
        data: {
          'model': 'gemma-4-e4b',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'stream': false,
          'max_tokens': 300,
          'temperature': 0.2,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final text = data['choices']?[0]?['message']?['content'] as String? ?? '';

        // 嘗試解析 JSON
        final json = _parseJsonFromLLM(text);
        if (json != null) {
          return DistilledContent(
            summary: json['summary'] as String? ?? rawText.substring(0, rawText.length > 50 ? 50 : rawText.length),
            keywords: (json['keywords'] as List?)?.map((e) => e.toString()).toList() ?? [],
            resolution: json['resolution'] as String?,
            systems: (json['systems'] as List?)?.map((e) => e.toString()).toList() ?? [],
          );
        }
      }
    } catch (e) {
      debugPrint('[AssetIndex] 結構化蒸餾失敗，fallback 到純文字: $e');
    }

    // fallback: 用純文字蒸餾
    final fallbackText = await _distillText(rawText, fileName);
    return DistilledContent(summary: fallbackText);
  }

  /// 從 LLM 回應中解析 JSON（容忍 markdown code block 包裹）
  Map<String, dynamic>? _parseJsonFromLLM(String text) {
    var cleaned = text.trim();

    // 移除 markdown code block
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceAll(RegExp(r'^```\w*\n?'), '').replaceAll(RegExp(r'\n?```$'), '');
    }

    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      // 嘗試找到第一個 { 和最後一個 }
      final start = cleaned.indexOf('{');
      final end = cleaned.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          return jsonDecode(cleaned.substring(start, end + 1)) as Map<String, dynamic>;
        } catch (_) {}
      }
      return null;
    }
  }

  /// 按標題切分 Markdown 文字
  /// Cerebras Knowledge 警告：固定字數截斷會破壞語意完整性
  /// 按 ## / ### 標題切分，每個 section 獨立處理
  List<String> _chunkByHeadings(String text) {
    // 如果文字不長（<3000字），不需要切分
    if (text.length < 3000) return [text];

    final lines = text.split('\n');
    final chunks = <String>[];
    final currentChunk = <String>[];

    for (final line in lines) {
      // 偵測標題行：# / ## / ### / ####
      final isHeading = RegExp(r'^#{1,4}\s').hasMatch(line);

      if (isHeading && currentChunk.isNotEmpty) {
        // 遇到新標題 → 把之前的 chunk 存起來
        final chunk = currentChunk.join('\n').trim();
        if (chunk.isNotEmpty) {
          chunks.add(chunk);
        }
        currentChunk.clear();
      }

      currentChunk.add(line);
    }

    // 最後一個 chunk
    final lastChunk = currentChunk.join('\n').trim();
    if (lastChunk.isNotEmpty) {
      chunks.add(lastChunk);
    }

    // 如果切分後只有 1 個 chunk（沒有標題），且文字太長 → 回退到固定截斷
    if (chunks.length <= 1) {
      return [text.length > 8000 ? text.substring(0, 8000) : text];
    }

    // 每個 chunk 如果超過 8000 字還是要截斷
    return chunks.map((c) => c.length > 8000 ? c.substring(0, 8000) : c).toList();
  }

  /// 計算檔案 SHA256 hash（用於增量更新比對）
  Future<String?> _computeFileHash(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      return null;
    }
  }

  /// 為已掃描的檔案生成 embedding 向量
  ///
  /// [教練 Agent 2026-07-31] 雙模式嵌入：
  /// 1. 快速模式（文字類）：md/txt/json/code → 立即 embed
  /// 2. 深度模式（圖片/影片）：背景慢慢跑 VisionPipeline
  /// App 啟動時只跑快速模式，深度模式留給使用者手動觸發或自動背景
  ///
  /// 在 fullScan 完成後呼叫。需要 EmbeddingService 已初始化。
  ///
  /// [rootPath] — 要生成 embedding 的根資料夾
  /// [onProgress] — 進度回調 (已處理數, 總數)
  /// [教練 Agent 2026-07-31] 簡化版嵌入：
  /// 所有檔案統一處理 — 讀取 → embed → 存 DB
  /// 蒸餾分析（summary/keywords）改為按需觸發，不在這裡做
  /// 進度透過 [EmbeddingProgressTracker] 廣播
  Future<int> generateEmbeddings({
    String? rootPath,
    void Function(int done, int total)? onProgress,
  }) async {
    final tracker = EmbeddingProgressTracker.instance;
    final embedder = EmbeddingService.instance;
    // [小葵 2026-09-24 Blue 抓包] 防重入——watcher 觸發鏈會連續叫
    // autoResumeEmbedding，沒有 active 檢查時同一輪全表檢查會疊加跑
    //（log 實錘 20+ 次連發）。這裡跟 generateEmbeddingsInBackground 同款閘門。
    if (tracker.isEmbeddingActive) {
      debugPrint('[AssetIndex] generateEmbeddings：嵌入任務已在執行中，跳過');
      return 0;
    }
    debugPrint('[AssetIndex] generateEmbeddings: isModelAvailable=${embedder.isModelAvailable}, files=${_manifest.files.length}');
    if (!embedder.isModelAvailable) {
      debugPrint('[AssetIndex] Embedding 模型未安裝，跳過');
      return 0;
    }

    // 所有未嵌入的檔案
    // [教練 Agent 2026-08-02] 修正：直接從 DB pending 列表驅動嵌入
    // 之前用 manifest.files + mf.embedding 判斷，但 manifest 不完整
    // （DB 有 50,836 筆但 manifest 只有 ~21,855），且 manifest.embedding 標記不可靠
    // 改為：DB index_status='pending' 的直接納入嵌入佇列
    final db = BrainDatabase.instance.db;
    
    // 從 DB 取 pending 檔案的路徑集合
    final pendingDbPaths = <String>{};
    try {
      final rows = db.select(
        "SELECT file_path FROM asset_index WHERE index_status = 'pending'",
      );
      for (final row in rows) {
        pendingDbPaths.add(row['file_path'] as String);
      }
      debugPrint('[AssetIndex] DB pending: ${pendingDbPaths.length} 筆');
    } catch (e) {
      debugPrint('[AssetIndex] 查詢 pending 失敗: $e');
    }

    // 同時保留 manifest 裡 embedding=false 的（相容舊邏輯）
    final embeddedPaths = <String>{};
    try {
      final rows = db.select(
        "SELECT file_path FROM asset_index WHERE index_status IN ('indexed', 'embedded')",
      );
      for (final row in rows) {
        embeddedPaths.add(row['file_path'] as String);
      }
    } catch (_) {}

    // [小葵 2026-09-30 根修] identity = 終態：已是身份嵌入的檔案一律跳過。
    // 慘案：generateEmbeddings 把 manifest.embedding=false 的舊檔重嵌成
    // embed_source='content'，把 IdentityReembed 做好的身份嵌入整批覆蓋
    //（2026-09-30 實證：identity 6802→4148、content 281→2946，兩個任務互相踩）。
    final identityPaths = <String>{};
    try {
      final rows = db.select(
        "SELECT file_path FROM asset_index WHERE embed_source = 'identity'",
      );
      for (final row in rows) {
        identityPaths.add(row['file_path'] as String);
      }
    } catch (_) {}

    var pendingFiles = _manifest.files.where((mf) {
      if (rootPath != null && mf.folder != rootPath) return false;
      // [小葵 2026-09-30] identity 終態保護——絕不重嵌（身份嵌入是檢索升級 v2 的成果）
      if (identityPaths.contains(mf.path)) return false;
      // [教練 Agent 2026-08-02] DB pending 的檔案直接納入，不管 manifest.embedding
      if (pendingDbPaths.contains(mf.path)) return true;
      // manifest 裡 embedding=false 且 DB 也不是 indexed 的也納入
      if (mf.embedding) return false;
      if (embeddedPaths.contains(mf.path)) return false;
      return true;
    }).toList();

    // [教練 Agent 2026-08-02] 補充：DB 裡 pending 但 manifest 不認識的檔案
    // 這些檔案可能是之前匯入但 manifest 已重建
    final manifestPaths = _manifest.files.map((mf) => mf.path).toSet();
    for (final dbPath in pendingDbPaths) {
      if (!manifestPaths.contains(dbPath)) {
        // 從 DB 補一個 ManifestFile（需要 folder + path 拆分）
        final lastSlash = dbPath.lastIndexOf('/');
        final folder = lastSlash > 0 ? dbPath.substring(0, lastSlash) : '/';
        pendingFiles.add(ManifestFile(
          folder: folder,
          path: dbPath,
          size: 0,
          modified: 0,
          hash: '',
          embedding: false,
        ));
      }
    }

    debugPrint('[AssetIndex] pendingFiles total: ${pendingFiles.length} '
        '(manifest: ${_manifest.files.length}, DB pending: ${pendingDbPaths.length})');

    // [教練 Agent 2026-07-31] 排序：文字類優先（秒完），圖片/影片排後面
    pendingFiles.sort((a, b) {
      final aIsMedia = _imageExtensions.any((e) => a.path.toLowerCase().endsWith(e)) ||
          _videoExtensions.any((e) => a.path.toLowerCase().endsWith(e));
      final bIsMedia = _imageExtensions.any((e) => b.path.toLowerCase().endsWith(e)) ||
          _videoExtensions.any((e) => b.path.toLowerCase().endsWith(e));
      if (aIsMedia && !bIsMedia) return 1;  // a 排後面
      if (!aIsMedia && bIsMedia) return -1; // a 排前面
      return 0;
    });

    if (pendingFiles.isEmpty) return 0;

    // [教練 Agent 2026-07-31] 增量更新：用 file_hash 跳過未改變的檔案
    final existingHashes = <String, String>{}; // file_path -> file_hash
    try {
      final rows = db.select(
        'SELECT file_path, file_hash FROM asset_index WHERE file_hash IS NOT NULL',
      );
      for (final row in rows) {
        existingHashes[row['file_path'] as String] = row['file_hash'] as String;
      }
    } catch (_) {
      // file_hash 欄位可能還不存在（舊 schema）
    }

    // [小葵 2026-10-01 F3] hash 統一層——快指紋優先：
    // 舊流程對每個 pending 檔全量讀檔算 SHA256（7000 筆=30GB 讀取），
    // 但絕大多數是「內容未變、只是 file_hash 空」的舊資產。
    // 新流程：stat 的 mtime+size 與 DB 一致 → 視同未變（零讀檔）；
    // 不一致才讀檔算 hash（真變更）。
    final existingStatFingerprints = <String, String>{};
    try {
      for (final row in db.select(
          'SELECT file_path, file_size, file_modified FROM asset_index')) {
        final fp0 = row['file_path'] as String?;
        if (fp0 == null) continue;
        existingStatFingerprints[fp0] =
            '${row['file_size']}:${row['file_modified']}';
      }
    } catch (_) {/* 舊 schema 無欄位——fallback 全量 hash */}

    final hashCache = <String, String?>{}; // path -> hash
    final filesToEmbed = <ManifestFile>[];
    var statSkipped = 0;
    for (final mf in pendingFiles) {
      final fullPath = '${mf.folder}/${mf.path}';
      final f = File(fullPath);
      // 快指紋層：stat 比對（零讀檔）
      try {
        final st = await f.stat();
        final fastFp = '${st.size}:${st.modified.millisecondsSinceEpoch}';
        if (existingStatFingerprints[fullPath] != null &&
            existingStatFingerprints[fullPath] == fastFp) {
          statSkipped++;
          continue; // mtime+size 未變——內容 hash 必然一致（碰撞率可忽略）
        }
      } catch (_) {/* stat 失敗——走完整 hash */}
      final hash = await _computeFileHash(f);
      if (hash != null && existingHashes[mf.path] == hash) {
        continue;
      }
      hashCache[mf.path] = hash;
      filesToEmbed.add(mf);
    }
    if (statSkipped > 0) {
      debugPrint('[AssetIndex] [F3] 快指紋跳過 $statSkipped 筆（零讀檔）');
    }

    if (filesToEmbed.isEmpty) return 0;

    // 通知 tracker 開始
    tracker.startEmbedding(total: filesToEmbed.length, rootPath: rootPath);

    var done = 0;
    var success = 0;

    for (final mf in filesToEmbed) {
      // ── 進度可見：每個檔案開始時更新 tracker ──
      debugPrint('[AssetIndex] 📄 處理中 $done/${filesToEmbed.length}: ${mf.path}');
      tracker.updateFile(
        done: done,
        total: filesToEmbed.length,
        currentFile: mf.path,
      );

      try {
        // ── 根據檔案類型走不同嵌入路徑 ──
        final ext = mf.path.contains('.')
            ? mf.path.split('.').last.toLowerCase()
            : '';
        final isTextFile = ['md', 'txt', 'docx', 'svg', 'xml', 'json',
            'dart', 'py', 'js', 'ts', 'sol', 'toml', 'yaml', 'yml',
            'html', 'css', 'scss', 'csv', 'sh', 'swift', 'go', 'rs',
            ].contains(ext);
        // [教練 Agent 2026-08-02] SVG 不再走圖片路徑——它是 XML 文字
        // 原本 SVG 被歸為 image → 走 VisionPipeline → 失敗標 error
        // 改為文字路徑：提取 XML 內容做 embedding
        final isImage = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'gif', 'bmp',
            'avif'].contains(ext); // [小葵 2026-08-28] +avif（QL 可渲染）
        final isVideo = ['mp4', 'mov', 'avi', 'mkv'].contains(ext);
        final isPdf = ext == 'pdf';

        if (isPdf) {
          // ── PDF：helper 抽文字層 → embed；掃描版等補嵌服務 ──
          final fullPath = '${mf.folder}/${mf.path}';
          final pr = await Process.run('python3', [
            'tools/pdf_extract_text.py', fullPath, '50',
          ]);
          String text = '';
          bool scanned = false;
          if (pr.exitCode == 0) {
            try {
              final j = jsonDecode(pr.stdout as String) as Map<String, dynamic>;
              text = (j['text'] as String? ?? '').trim();
              scanned = j['scanned'] == true;
            } catch (_) {}
          }
          if (text.length >= 30 && !scanned) {
            final body = text.length > 2000 ? text.substring(0, 2000) : text;
            final result = await embedder.embedOne(body);
            db.execute(
              "UPDATE asset_index SET embedding = vector_as_f32(?), "
              "  content_text = ?, file_hash = ?, "
              "  embed_source = 'content', "
              "  index_status = 'indexed', indexed_at = ? "
              "WHERE file_path = ? "
              "  AND COALESCE(embed_source, '') != 'identity'",
              [
                jsonEncode(result.vector),
                body,
                hashCache[mf.path],
                DateTime.now().millisecondsSinceEpoch,
                mf.path,
              ],
            );
            success++;
          } else {
            // 掃描/無文字層：標 metadata（PDF 補嵌服務會再掃）
            db.execute(
              "UPDATE asset_index SET embed_source = 'metadata', "
              "  file_hash = ?, index_status = 'indexed', indexed_at = ? "
              "WHERE file_path = ?",
              [hashCache[mf.path],
               DateTime.now().millisecondsSinceEpoch, mf.path],
            );
          }
          debugPrint('[AssetIndex] ✅ $done/${filesToEmbed.length}: ${mf.path} (PDF)');

        } else if (isTextFile) {
          // ── 文字類：讀取 → 直接 embed → 存 DB ──
          // [教練 Agent 2026-07-31] 簡化：嵌入就是嵌入，不跑 LLM 蒸餾
          // 蒸餾分析改為按需觸發（使用者點開檔案時才做）
          final fullPath = '${mf.folder}/${mf.path}';
          final file = File(fullPath);
          if (!await file.exists()) continue;

          String text;
          if (ext == 'md' || ext == 'txt') {
            try {
              text = await file.readAsString();
            } catch (_) {
              text = String.fromCharCodes(await file.readAsBytes());
            }
          } else if (ext == 'svg' || ext == 'xml') {
            // [教練 Agent 2026-08-02] SVG/XML：讀原始 XML，提取有意義的文字
            try {
              final raw = await file.readAsString();
              // 提取 <text> 內容、class 名稱、id、title 等有意義的字串
              final textMatches = RegExp(r'>([^<>]+)<').allMatches(raw)
                  .map((m) => m.group(1)?.trim() ?? '')
                  .where((s) => s.isNotEmpty && s.length > 1)
                  .join(' ');
              // 也提取 class/id/title 屬性值
              final attrMatches = RegExp(r'(?:class|id|title|aria-label)="([^"]+)"')
                  .allMatches(raw)
                  .map((m) => m.group(1)?.trim() ?? '')
                  .where((s) => s.isNotEmpty)
                  .join(' ');
              text = [mf.path.split('/').last, textMatches, attrMatches]
                  .where((s) => s.isNotEmpty).join(' ');
              if (text.isEmpty) text = mf.path.split('/').last;
            } catch (_) {
              text = mf.path.split('/').last;
            }
          } else if (['dart', 'py', 'js', 'ts', 'sol', 'toml', 'yaml', 'yml',
                      'html', 'css', 'scss', 'csv', 'sh', 'swift', 'go', 'rs',
                      'json'].contains(ext)) {
            // [教練 Agent 2026-08-02] 程式碼/設定檔：讀原始碼文字
            try {
              text = await file.readAsString();
            } catch (_) {
              text = mf.path.split('/').last;
            }
          } else {
            text = mf.path.split('/').last;
          }

          // [小葵 2026-09-09 Blue v2 檢索令] 身份嵌入——五因素織進向量
          final fullText = await IdentityEmbedText.instance.build(
            relPath: mf.path,
            folderRoot: mf.folder,
            content: text,
          );
          final embedText =
              fullText.length > 2000 ? fullText.substring(0, 2000) : fullText;
          final result = await embedder.embedOne(embedText);

          db.execute(
            "UPDATE asset_index SET embedding = vector_as_f32(?), "
            "  content_text = ?, file_hash = ?, "
            "  embed_source = 'content', "
            "  index_status = 'indexed', indexed_at = ? "
            "WHERE file_path = ? "
            "  AND COALESCE(embed_source, '') != 'identity'",
            [
              jsonEncode(result.vector),
              fullText,
              hashCache[mf.path],
              DateTime.now().millisecondsSinceEpoch,
              mf.path,
            ],
          );

          success++;
          debugPrint('[AssetIndex] ✅ $done/${filesToEmbed.length}: ${mf.path} (文字)');

        } else if (isImage || isVideo) {
          // ── 圖片/影片：VisionPipeline 解析 → embed 描述 ──
          final result = await VisionEmbeddingPipeline.instance.processSingleAsset(
            filePath: mf.path,
            folderRoot: mf.folder,
            fileName: mf.path.split('/').last,
            fileExt: '.$ext',
          );
          if (result) success++;
          debugPrint('[AssetIndex] ✅ $done/${filesToEmbed.length}: ${mf.path} (${isImage ? "圖片" : "影片"})');
          // [F2] 視覺資產進度（VisionPipeline 逐張）
          BackgroundTaskRegistry.instance.update(BackgroundTask(
            id: 'gen_embeddings', name: '檔案嵌入',
            detail: '補嵌 ${filesToEmbed.length} 個（視覺管线）',
            progress: filesToEmbed.isEmpty ? 1 : done / filesToEmbed.length,
            current: '${isImage ? "🖼" : "🎬"} ${mf.path.split('/').last}',
            startedAt: DateTime.now(),
          ));

        } else {
          // ── 其他：用檔名 embed（標記 'filename'——內容補嵌掃描的待辦印記）──
          // [小葵 2026-09-09 Blue v2 檢索令] 身份嵌入（fallback 檔案也帶身份）
          final fallbackText = await IdentityEmbedText.instance.build(
            relPath: mf.path,
            folderRoot: mf.folder,
            content: mf.path.split('/').last,
          );
          final result = await embedder.embedOne(fallbackText);

          db.execute(
            "UPDATE asset_index SET embedding = vector_as_f32(?), "
            "  content_text = ?, file_hash = ?, "
            "  embed_source = 'filename', "
            "  index_status = 'indexed', indexed_at = ? "
            "WHERE file_path = ? "
            "  AND COALESCE(embed_source, '') != 'identity'",
            [
              jsonEncode(result.vector),
              fallbackText,
              hashCache[mf.path],
              DateTime.now().millisecondsSinceEpoch,
              mf.path,
            ],
          );

          success++;
          debugPrint('[AssetIndex] ✅ $done/${filesToEmbed.length}: ${mf.path} (其他)');
        }
      } catch (e) {
        // [教練 Agent 2026-08-02] 嵌入失敗 → 標記 'skipped'（不是 error）
        // 這類檔案格式不支援或檔案損壞，不是系統錯誤，是正常的例外處理
        debugPrint('[AssetIndex] 檔案跳過 (${mf.path}): $e');
        try {
          db.execute(
            "UPDATE asset_index SET index_status = 'skipped', indexed_at = ? "
            "WHERE file_path = ?",
            [DateTime.now().millisecondsSinceEpoch, mf.path],
          );
        } catch (_) {}
      }

      done++;
      onProgress?.call(done, filesToEmbed.length);
      // 更新 tracker 進度（含已完成的 done 數）
      tracker.updateFile(
        done: done,
        total: filesToEmbed.length,
        currentFile: mf.path,
      );
    }

    // 通知 tracker 進入收尾
    tracker.setCompleting();

    // 更新 manifest 標記
    _manifest = _manifest.copyWith(
      files: _manifest.files.map((f) {
        if (filesToEmbed.any((e) => e.path == f.path && e.folder == f.folder)) {
          return ManifestFile(
            path: f.path,
            folder: f.folder,
            hash: f.hash,
            size: f.size,
            modified: f.modified,
            indexed: true,
            embedding: true,
          );
        }
        return f;
      }).toList(),
    );

    // 儲存更新後的 manifest
    if (rootPath != null) {
      await _saveManifest(rootPath);
    } else {
      for (final root in _sandbox.rootPaths) {
        await _saveManifest(root);
      }
    }

    // 通知 tracker 完成
    tracker.completeEmbedding();

    debugPrint('[AssetIndex] Embedding 生成完成: $success/$done 成功');
    // [幽靈進度條終結 2026-10-01 案二] finish 收進函數自身——
    // 所有呼叫者（autoIngest/watcher/vault 手動）都受保護，不再依賴
    // 呼叫端記得收尾（本案：auto_ingest 裸呼 generateEmbeddings 沒 finish，
    // 任務屍體 67% 永凍；前案 86% 同根因不同入口）
    BackgroundTaskRegistry.instance.finish('gen_embeddings',
        note: '$success/$done 成功');

    // [小葵 2026-08-28] Blue 指定：新檔導入後接內容重嵌掃描——
    // generateEmbeddings 的「其他類只嵌檔名」遺珠，content_text 有料的
    // 由 AssetContentReembedService 冪等補上（embed_source 守門）。
    if (success > 0) {
      Future.delayed(const Duration(seconds: 5), () {
        AssetContentReembedService.instance.start();
      });
    }
    return success;
  }

  /// 在背景啟動嵌入生成（fire-and-forget）。
  ///
  /// 呼叫者不需要 await — 嵌入會在背景繼續跑，
  /// 進度透過 [EmbeddingProgressTracker.progressStream] 廣播。
  /// 使用者可以切換頁面，嵌入不會中斷。
  ///
  /// 如果已經有嵌入任務在跑，會跳過（不重複啟動）。
  void generateEmbeddingsInBackground({String? rootPath}) {
    final tracker = EmbeddingProgressTracker.instance;
    if (tracker.isEmbeddingActive) {
      debugPrint('[AssetIndex] 嵌入任務已在執行中，跳過');
      return;
    }

    // fire-and-forget — 不 await，讓呼叫端立刻返回
    Future(() async {
      try {
        await generateEmbeddings(rootPath: rootPath);
      } catch (e) {
        debugPrint('[AssetIndex] 背景嵌入失敗: $e');
        tracker.failEmbedding(e.toString());
      }
    });
  }

  // ═══════════════════════════════════════════════════
  // 斷點續傳
  // ═══════════════════════════════════════════════════

  /// 確保只在 App 啟動時自動恢復一次
  bool _autoResumed = false;

  /// [教練 Agent 2026-07-31] macOS 原生檔案系統監測 — 事件驅動，0 負擔
  /// 檔案有變動才觸發，沒變動完全不耗 CPU/磁碟
  final Map<String, StreamSubscription<FileSystemEvent>> _watchers = {};

  /// App 啟動時呼叫一次：載入 manifest → 檢查 pending → 自動恢復嵌入
  ///
  /// 在 BrainContainerService.initialize() 完成後由外部呼叫。
  /// 不阻塞 App 啟動 — 嵌入在背景跑。
  Future<void> initOnAppStart() async {
    await loadManifests();
    if (!_autoResumed) {
      _autoResumed = true;
      await autoResumeEmbedding();
      // [教練 Agent 2026-07-31] 啟動事件驅動的檔案監測
      _startFileSystemWatchers();
    }
  }

  /// [教練 Agent 2026-07-31] 使用 macOS 原生 FileSystemEntity.watch()
  /// 監測已登記的資料夾，有新檔案或修改時才觸發嵌入
  /// 事件驅動 → 沒檔案變動時完全 0 CPU/0 I/O
  void _startFileSystemWatchers() {
    for (final root in _sandbox.rootPaths) {
      if (_watchers.containsKey(root)) continue;

      try {
        final dir = Directory(root);
        if (!dir.existsSync()) continue;

        // recursive: true → 監測所有子資料夾
        // events: create + modify + move（新檔案、修改、重命名）
        final stream = dir.watch(
          recursive: true,
          events: FileSystemEvent.create | FileSystemEvent.modify | FileSystemEvent.move,
        );

        // debounce — 避免短時間大量事件（例如複製 100 個檔案）狂觸發
        Timer? debounce;
        _watchers[root] = stream.listen((event) {
          // [小葵 2026-09-24 Blue 抓包] 向量庫讀取慢根因之一——
          // .DS_Store/.bridge 自家檔的系統級雜訊事件（Finder 碰一下就 modify）
          // 也會觸發 debounce → fastScan(6606 檔逐個 stat) →
          // autoResumeEmbedding → generateEmbeddings 全表檢查。
          // log 實錘：39 次觸發全來自 .DS_Store modify。
          // 修：雜訊路徑直接吞掉，不進 debounce。
          final baseName = p.basename(event.path);
          final isNoise = baseName == '.DS_Store' ||
              baseName.startsWith('._') ||
              event.path.contains('/.bridge/');
          if (isNoise) return;

          debugPrint('[AssetIndex] 檔案變動偵測: ${event.path} (${event.type})');

          // debounce 3 秒 — 等檔案操作穩定後再觸發嵌入
          debounce?.cancel();
          debounce = Timer(const Duration(seconds: 3), () {
            _onFileSystemChanged(root);
          });
        });

        debugPrint('[AssetIndex] 檔案監測已啟動: $root');
      } catch (e) {
        debugPrint('[AssetIndex] 檔案監測啟動失敗 ($root): $e');
      }
    }
  }

  /// [教練 Agent 2026-07-31] 檔案系統有變動時觸發
  /// 先 fastScan 偵測新檔案 → 再觸發嵌入鏈
  void _onFileSystemChanged(String root) async {
    if (!BrainContainerService.instance.isInitialized) return;
    if (EmbeddingProgressTracker.instance.isEmbeddingActive) {
      debugPrint('[AssetIndex] 嵌入進行中，跳過新檔案處理');
      return;
    }

    try {
      final result = await fastScan();
      if (result.newFiles > 0 || result.updatedFiles > 0) {
        debugPrint('[AssetIndex] 偵測到變動: ${result.newFiles} 新, ${result.updatedFiles} 更新');
        // 有新檔案 → 自動觸發嵌入鏈（快速 → 深度）
        await autoResumeEmbedding();
      }
    } catch (e) {
      debugPrint('[AssetIndex] 檔案變動處理失敗: $e');
    }
  }

  /// App 啟動時自動恢復嵌入
  ///
  /// 檢查 DB 裡是否有 pending 檔案，有就背景開始嵌入。
  /// 所有失敗都靜默 fallback，不影響 App 啟動。
  /// [教練 Agent 2026-07-31] 啟動時只跑快速嵌入（文字類），深度嵌入留給背景
  Future<void> autoResumeEmbedding() async {
    if (!BrainContainerService.instance.isInitialized) return;

    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        "SELECT COUNT(*) as cnt FROM asset_index WHERE index_status = 'pending'",
      );
      final pendingCount = rows.first['cnt'] as int? ?? 0;

      if (pendingCount > 0) {
        debugPrint('[AssetIndex] 自動恢復嵌入: $pendingCount 個 pending 檔案');
        // [教練 Agent 2026-07-31] 簡化：一次跑完所有檔案（文字+圖片+影片）
        // 蒸餾分析不在這裡，改為按需觸發
        Future(() async {
          try {
            final count = await generateEmbeddings();
            debugPrint('[AssetIndex] 嵌入完成: $count 個檔案');
            BackgroundTaskRegistry.instance.finish('gen_embeddings',
                note: '$count 個完成');
          } catch (e) {
            debugPrint('[AssetIndex] 自動嵌入失敗: $e');
            // [幽靈進度條修復 2026-10-01] 失敗也要收尾——registry 不留 running 屍體
            BackgroundTaskRegistry.instance.finish('gen_embeddings',
                note: '嵌入中斷: $e');
          }
        });
      } else {
        debugPrint('[AssetIndex] 無 pending 檔案，嵌入已完成');
      }
    } catch (e) {
      debugPrint('[AssetIndex] 檢查 pending 失敗: $e');
    }
  }

  // ═══════════════════════════════════════════════════
  // 查詢 DB（含房間/信心度）
  // ═══════════════════════════════════════════════════

  /// [教練 Agent 2026-07-28] 決策 2：從 DB 查詢 AssetRecord（含 room / confidence）
  ///
  /// VaultScreen 批量分類 UI 需要每個檔案的 room 和 classification_confidence。
  /// ManifestFile 只存檔案系統資訊，房間/信心度存在 asset_index 表。
  AssetRecord? getRecordByPath(String filePath) {
    if (!BrainContainerService.instance.isInitialized) return null;
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        'SELECT id, file_path, folder_root, file_name, file_ext, file_size, '
        'file_modified, index_status, indexed_at, title, asset_kind, source, '
        'room, project_id, classification_confidence, source_type, audience '
        'FROM asset_index WHERE file_path = ?',
        [filePath],
      );
      if (rows.isEmpty) return null;
      return _rowToAssetRecord(rows.first);
    } catch (e) {
      debugPrint('[AssetIndex] 查詢記錄失敗 ($filePath): $e');
      return null;
    }
  }

  /// 查詢所有已索引檔案的 AssetRecord（含 room / confidence）
  List<AssetRecord> getAllRecords() {
    if (!BrainContainerService.instance.isInitialized) return [];
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        'SELECT id, file_path, folder_root, file_name, file_ext, file_size, '
        'file_modified, index_status, indexed_at, title, asset_kind, source, '
        'room, project_id, classification_confidence, source_type, audience '
        'FROM asset_index',
      );
      return rows.map(_rowToAssetRecord).toList();
    } catch (e) {
      debugPrint('[AssetIndex] 查詢所有記錄失敗: $e');
      return [];
    }
  }

  /// [教練 Agent 2026-07-28] 決策 2：批量改房間
  ///
  /// 使用者手動調整分類時，批量 UPDATE asset_index SET room = ? WHERE id IN (...)
  /// 手動設定時 confidence 提升為 1.0（使用者確認的分類）。
  ///
  /// [recordIds] — 要修改的 AssetRecord id 列表
  /// [room] — 目標房間（FileRoom enum）
  /// 回傳成功更新的筆數
  /// [Blue 令 2026-10-17] 批量加標籤——用戶手動貼標同步進 asset_index.tags，
  /// 讓智慧搜尋（_filteredLibraryFiles 比對 record.tags）與 Agent 向量檢索
  /// 都吃得到。既有標籤保留（聯集去重）。
  int batchAddTags(List<String> recordIds, String label) {
    if (!BrainContainerService.instance.isInitialized) return 0;
    if (recordIds.isEmpty || label.trim().isEmpty) return 0;
    final db = BrainDatabase.instance.db;
    var updated = 0;
    try {
      db.execute('BEGIN');
      for (final id in recordIds) {
        final rows = db.select(
          'SELECT tags FROM asset_index WHERE id = ?',
          [id],
        );
        if (rows.isEmpty) continue;
        List<dynamic> existing;
        try {
          existing = jsonDecode(rows.first['tags'] as String? ?? '[]') as List;
        } catch (_) {
          existing = [];
        }
        final merged = {...existing.map((e) => e.toString()), label.trim()};
        db.execute(
          'UPDATE asset_index SET tags = ? WHERE id = ?',
          [jsonEncode(merged.toList()), id],
        );
        updated++;
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      debugPrint('[AssetIndex] batchAddTags 失敗: $e');
      return 0;
    }
    return updated;
  }

  int batchUpdateRoom(List<String> recordIds, FileRoom room) {
    if (!BrainContainerService.instance.isInitialized) return 0;
    if (recordIds.isEmpty) return 0;

    final db = BrainDatabase.instance.db;
    var updated = 0;
    try {
      db.execute('BEGIN');
      for (final id in recordIds) {
        final before = db.select(
          'SELECT COUNT(*) as c FROM asset_index WHERE id = ?',
          [id],
        );
        db.execute(
          'UPDATE asset_index SET room = ?, classification_confidence = 1.0 '
          'WHERE id = ?',
          [room.name, id],
        );
        if ((before.first['c'] as int) > 0) updated++;
      }
      db.execute('COMMIT');
      debugPrint('[AssetIndex] 批量改房間完成: $updated/${recordIds.length} 筆 → ${room.label}');
    } catch (e) {
      db.execute('ROLLBACK');
      debugPrint('[AssetIndex] 批量改房間失敗: $e');
    }
    return updated;
  }

  /// 將 DB row 轉成 AssetRecord
  AssetRecord _rowToAssetRecord(Map<String, dynamic> row) {
    return AssetRecord(
      id: row['id'] as String,
      filePath: row['file_path'] as String,
      folderRoot: row['folder_root'] as String,
      fileName: row['file_name'] as String,
      fileExt: row['file_ext'] as String?,
      fileSize: row['file_size'] as int,
      fileModified: row['file_modified'] as int,
      indexStatus: row['index_status'] as String? ?? 'pending',
      indexedAt: row['indexed_at'] as int?,
      title: row['title'] as String?,
      assetKind: _parseAssetKind(row['asset_kind'] as String?),
      source: row['source'] as String? ?? 'user',
      room: row['room'] as String? ?? 'bridges',
      projectId: row['project_id'] as String?,
      classificationConfidence:
          (row['classification_confidence'] as num?)?.toDouble() ?? 0.0,
      sourceType: row['source_type'] as String? ?? 'imported',
      audience: row['audience'] as String? ?? 'general',
    );
  }

  AssetKind _parseAssetKind(String? name) {
    if (name == null) return AssetKind.other;
    return AssetKind.values.firstWhere(
      (k) => k.name == name,
      orElse: () => AssetKind.other,
    );
  }

  /// 為圖片/影片檔案生成 embedding 向量（透過本地視覺模型）
  ///
  /// [教練 Agent 2026-07-28] 決策 4 實作
  ///
  /// 使用 VisionEmbeddingPipeline：
  /// - 圖片：local_vision_analyze → 描述 → EmbeddingGemma → BLOB
  /// - 影片：frame_extract → 逐幀 vision_analyze → 彙整 → EmbeddingGemma → BLOB
  ///
  /// [rootPath] — 限定根資料夾（null = 處理全部）
  /// 回傳成功處理的檔案數
  ///
  /// 進度透過 VisionEmbeddingPipeline.instance.progressStream 監聽。
  /// 不可中斷提醒：「嵌入中，請勿關機」
  Future<int> generateVisionEmbeddings({String? rootPath}) async {
    return VisionEmbeddingPipeline.instance
        .processPendingVisionAssets(rootPath: rootPath);
  }

}
