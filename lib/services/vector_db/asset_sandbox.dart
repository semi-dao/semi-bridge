// asset_sandbox.dart
// [教練 Agent 2026-07-25] 向量資料庫安全邊界
//
// 智慧型多維度圖書館管理員的安全規則：
// - 使用者的檔案位置不動、結構不動
// - 系統只在 .bridge/ 裡整理索引
// - Agent 只能讀寫已登記資料夾邊界內的檔案
// - Agent 產出強制存入 .bridge/assets/（跟使用者原始檔案隔離）
//
// 設計文件：B+-Hybrid-GraphRAG-大腦與圖書館協同架構.md §2 + §14

import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// 向量資料庫安全邊界 — 多資料夾版
///
/// 管理已登記的資料夾清單（向量資料庫範圍），
/// 確保所有檔案操作都在安全邊界內。
class AssetSandbox {
  static final AssetSandbox _instance = AssetSandbox._();
  factory AssetSandbox() => _instance;
  AssetSandbox._();

  static const _prefsKey = 'vector_db_root_paths';

  /// 已登記的資料夾清單（向量資料庫範圍）
  final List<String> _rootPaths = [];

  /// 唯讀：目前登記的資料夾清單
  List<String> get rootPaths => List.unmodifiable(_rootPaths);

  /// 預設排除的目錄名稱（系統目錄、開發快取等）
  ///
  /// [小葵 2026-10-30 暴衝案] 加入 '04-備份'——10-29 主碟清查把 12G 模型＋
  /// App 備份搬進 <DATA_VOLUME>/backup/，素材索引器遞迴全掃把
  /// Chrome 快取/模型檔等 62,726 筆垃圾吃進 asset_index（brain_container.db
  /// 膨脹到 2.4GB），embedding 循環累積 → Dart heap 暴衝 83GB → jetsam 連環
  /// 殺 App。備份區對素材索引零價值，一體排除（指紋計算與掃描同源此清單）。
  static const defaultExcludedDirs = [
    '.bridge',
    '.git',
    '.trash',
    'node_modules',
    '__pycache__',
    '.DS_Store',
    'tmp',
    'cache',
    '.cache',
    'Thumbs.db',
    '04-備份',
  ];

  /// [教練 Agent 2026-08-21] Google Drive/雲端同步暫存目錄模式——
  /// `.tmp.driveupload` 這類「.` 開頭 + tmp」的同步殘骸（實測曾吞
  /// 18,464 筆幽靈記錄）。用前綴模式而非 hardcode 單一名稱，
  /// 未來任何雲端工具的暫存目錄（.tmp.*）一體適用。
  static bool isSyncJunkDir(String dirName) {
    return dirName.startsWith('.tmp.');
  }

  /// [小葵 2026-09-09 Blue 分層令] 純垃圾檔——不索引、不入 manifest、
  /// 既有記錄清除。對使用者與 agent 都零價值。
  /// - `._*`：AppleDouble 檔（macOS 在非 HFS+ 碟上的資源 fork 殘骸）
  /// - `Icon\r`：macOS 資料夾自訂圖示的資源檔（**2026-10-30 修正**——舊註解
  ///   寫「0B 幽靈」是錯的：本體 0 byte 但掛 163,057B `com.apple.ResourceFork`，
  ///   是真圖示不是垃圾。兇手＝Google Drive for desktop 把 <DATA_VOLUME> 當
  ///   可串流碟並掛兩個 mirror root，開機後約 1 分鐘重物化 1,171 個。
  ///   行為維持不變（不索引是安全的），但絕不可寫「刪 DATA 上所有 junk 檔」
  ///   的清理腳本——那會刪掉 Blue 農場資料庫 1,171 個資料夾的圖示。
  ///   判 junk 前必查 xattr 與資源內容，不能只看檔案本體大小。
  static bool isJunkFile(String fileName) {
    return fileName == 'Icon\r' || fileName.startsWith('._');
  }

  /// [小葵 2026-09-09 Blue 智慧寫入令] 路徑身分前綴——寫入/嵌入時注入。
  /// 例：`01_現況紀錄/照片紀錄/營本部/2026-08-13/Blue陽台/千手皇冠/x.jpg`
  /// → `[資料夾: 01_現況紀錄/照片紀錄/營本部/2026-08-13/Blue陽台/千手皇冠]`
  /// 照片本身只有流水編號，但資料夾路徑就是它的身份（品種/地點/日期）。
  static String folderContextPrefix(String relPath) {
    final segs = relPath.split('/');
    if (segs.length < 2) return '';
    return '[資料夾: ${segs.take(segs.length - 1).join('/')}] ';
  }

  /// [小葵 2026-09-09 Blue 智慧寫入令] 路徑標籤——從資料夾結構萃取。
  /// 日期段（2026-08-13 等）不當標籤；保留語意段（品種/地點/主題）。
  /// 根目錄名與 origin_kind 一併入標籤。
  static List<String> pathTags(String relPath, String folderRoot,
      {String? originKind}) {
    final dateRe = RegExp(r'^\d{4}[-_/]?\d{0,2}$');
    final segs = relPath.split('/')..removeLast();
    final tags = <String>[];
    for (final s in segs) {
      if (s.isEmpty) continue;
      if (dateRe.hasMatch(s)) continue; // 純日期段跳過
      tags.add(s);
    }
    final rootName =
        folderRoot.endsWith('/') ? folderRoot.substring(0, folderRoot.length - 1) : folderRoot;
    final lastSeg = rootName.split('/').last;
    if (lastSeg.isNotEmpty && !tags.contains(lastSeg)) tags.add(lastSeg);
    if (originKind != null && originKind.isNotEmpty) {
      tags.add('來源:$originKind');
    }
    return tags;
  }

  /// [小葵 2026-09-09 Blue 分層令] 技術層檔案——保留但預設搜尋不可見。
  /// 工程師類使用者（工程模式/絕對搜尋）才看得到。
  /// 業界慣例（.gitignore / ripgrep / VS Code Search Exclusions 同款精神）：
  /// vendored 依賴庫、開發工具隱藏設定、建置產物不混入一般搜尋空間。
  static bool isTechnicalPath(String relativePath, {String? folderRoot}) {
    final full = folderRoot == null ? relativePath : '$folderRoot/$relativePath';
    final segs = full.split('/');
    for (final seg in segs) {
      // vendored 依賴庫目錄（node_modules 已在 excludedDirs；此處補 lib/ 型）
      if (seg == 'openzeppelin-contracts' || seg == 'forge-std') return true;
      // 開發工具隱藏設定目錄（.github/.claude/.dart_tool/.husky/.changeset/
      // .obsidian…一體適用：'.' 開頭的專案設定目錄，例外：.bridge 自家）
      if (seg.startsWith('.') && seg != '.bridge' && seg.length > 1) return true;
      // 建置產物
      if (seg == 'build' || seg.endsWith('.app') || seg.endsWith('.saver')) {
        return true;
      }
    }
    return false;
  }

  /// 預設排除的副檔名
  static const defaultExcludedExts = [
    '.DS_Store',
    '.pyc',
    '.class',
    '.o',
    '.so',
    '.dll',
  ];

  /// 加入新資料夾到向量資料庫清單
  ///
  /// 路徑會被正規化（移除尾部斜線、轉為絕對路徑）。
  /// 重複加入同一資料夾不會有問題。
  void addFolder(String path) {
    final normalized = _normalizePath(path);
    if (normalized.isNotEmpty && !_rootPaths.contains(normalized)) {
      _rootPaths.add(normalized);
      _persist();
    }
  }

  /// 移除資料夾（不刪檔案，只移除索引範圍）
  void removeFolder(String path) {
    final normalized = _normalizePath(path);
    _rootPaths.remove(normalized);
    _persist();
  }

  /// 清除所有資料夾
  void clear() {
    _rootPaths.clear();
    _persist();
  }

  /// 從持久化清單載入
  void loadFromPaths(List<String> paths) {
    _rootPaths.clear();
    for (final p in paths) {
      addFolder(p);
    }
  }

  // [教練 Agent 2026-07-25] 持久化 — App 重啟後保留資料夾清單

  /// 從 SharedPreferences 載入資料夾清單（App 啟動時呼叫）
  ///
  /// [2026-11-13 手機「無法開啟」根因] sandboxed App 的 SharedPreferences 寫
  /// 進容器域，但歷史上 roots 曾寫進 host 域（~/Library/Preferences）——兩域
  /// 都撈，先容器後 host，聯集去重。漏讀＝vault manifest 全空＝手機全滅。
  Future<void> loadFromPrefs() async {
    _rootPaths.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_prefsKey) ?? [];
      _rootPaths.addAll(paths);
    } catch (e) {
      // SharedPreferences 不可用時靜默降級
    }
    // fallback：host 域（NSUserDefaults 直接讀，無需特權）
    try {
      final proc = await Process.run('defaults', [
        'read', 'farm.semiwasabi.bridgeApp', 'flutter.$_prefsKey',
      ]);
      final out = proc.stdout.toString().trim();
      if (out.isNotEmpty) {
        // defaults read 印出 ("a", "b",) 格式
        final items = RegExp(r'"([^"]+)"').allMatches(out).map((m) => m.group(1)!);
        for (final p in items) {
          if (!_rootPaths.contains(p)) _rootPaths.add(p);
        }
      }
    } catch (_) {
      // host 域沒有也算了
    }
  }

  /// [小葵 2026-10-16 Blue 令 UI 驗收抓包] prefs 載入競態——
  /// App 重啟後 vault 立即開：_loadLibraryFiles 在 loadFromPrefs
  /// 完成前跑 → sandbox 空根 → manifest 空 →「尚無資料」定格。
  /// 並發呼叫共享同一個載入 Future；完成後保證有根。
  Future<void>? _prefsLoadFuture;
  Future<void> ensurePrefsLoaded() async {
    _prefsLoadFuture ??= loadFromPrefs();
    await _prefsLoadFuture;
    // 空根重試一次（prefs 偶發延遲載入）——仍空就認命（真的沒匯入過）
    if (_rootPaths.isEmpty) {
      _prefsLoadFuture = loadFromPrefs();
      await _prefsLoadFuture;
    }
  }

  /// 持久化到 SharedPreferences
  void _persist() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setStringList(_prefsKey, _rootPaths);
    });
  }

  /// 檢查路徑是否在任何一個沙盒內
  bool isWithinSandbox(String filePath) {
    if (_rootPaths.isEmpty) return false;
    final normalized = _normalizePath(filePath);
    return _rootPaths.any((root) => normalized.startsWith(root));
  }

  /// 取得路徑所屬的根資料夾（如果有的話）
  String? rootFolderFor(String filePath) {
    final normalized = _normalizePath(filePath);
    for (final root in _rootPaths) {
      if (normalized.startsWith(root)) {
        return root;
      }
    }
    return null;
  }

  /// 取得相對於根資料夾的路徑
  ///
  /// 如果路徑不在任何沙盒內，回傳 null。
  String? relativePath(String filePath) {
    final root = rootFolderFor(filePath);
    if (root == null) return null;
    final normalized = _normalizePath(filePath);
    var rel = normalized.substring(root.length);
    if (rel.startsWith('/')) rel = rel.substring(1);
    return rel;
  }

  /// Agent 寫入路徑（強制進 .bridge/assets/ 子目錄）
  ///
  /// [folderRoot] — 資料夾根路徑
  /// [filename] — 檔名
  String agentOutputPath(String folderRoot, String filename) {
    final root = _normalizePath(folderRoot);
    return '$root/.bridge/assets/$filename';
  }

  /// 確保 .bridge/ 目錄結構存在
  Future<void> ensureBridgeDir(String folderRoot) async {
    final root = _normalizePath(folderRoot);
    await Directory('$root/.bridge/assets').create(recursive: true);
  }

  /// 檢查目錄是否應被排除
  static bool isExcludedDir(String dirName) {
    return defaultExcludedDirs.contains(dirName);
  }

  /// 檢查副檔名是否應被排除
  static bool isExcludedExt(String ext) {
    return defaultExcludedExts.contains(ext.toLowerCase());
  }

  /// 正規化路徑
  String _normalizePath(String path) {
    var p = path.trim();
    // 移除尾部斜線
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    // 確保是絕對路徑
    if (!p.startsWith('/')) {
      p = File(p).absolute.path;
    }
    // 再移除一次尾部斜線（absolute 可能加上）
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }
}
