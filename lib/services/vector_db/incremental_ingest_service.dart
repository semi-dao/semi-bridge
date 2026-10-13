// incremental_ingest_service.dart
// [教練 Agent 2026-08-21] 鐵三角 #7 + #9 — 事件驅動髒標記 + 週期自動 ingest
//
// #7 髒標記事件驅動：Directory.watch 監看已授權根目錄，檔案
//    變更 → 300ms 防抖 → 只重掃該根目錄（fullScan 冪等，已嵌入
//    記錄自動保留）→ generateEmbeddings 補嵌新增 pending 檔。
// #9 週期自動 ingest：watch 之外每 30 分鐘兜底重掃一輪（watch
//    會漏：App 沒開時的變更、外接碟卸載重掛）。
//
// 設計原則：
// - 讓出 UI：重掃/補嵌本來就是背景 worker 設計（分批 + await Future.delayed）
// - 單輪互斥：掃描中收到新事件只設 _dirty，不重入
// - 誠實：進度寫 brain_meta（'auto_ingest_status'），MCP /import_progress 可查

import 'dart:async';

import '../activity/background_task_registry.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'vector_sketch_service.dart';

import '../brain_container/brain_database.dart';
import 'asset_index_service.dart';

class IncrementalIngestService {
  IncrementalIngestService._();
  static final IncrementalIngestService instance = IncrementalIngestService._();

  final AssetIndexService _indexService = AssetIndexService();
  Timer? _cycleTimer;
  final List<StreamSubscription<FileSystemEvent>> _watchers = [];
  final Set<String> _dirtyRoots = {};
  bool _scanning = false;
  bool _started = false;

  /// 啟動：watch 所有已授權根目錄 + 30 分鐘週期兜底
  Future<void> start() async {
    if (_started) return;
    _started = true;

    final roots = _sandboxRoots();
    debugPrint('[AutoIngest] 啟動：${roots.length} 個根目錄');

    for (final root in roots) {
      _watch(root);
    }

    _cycleTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _markAllDirty('週期兜底');
    });

    // 啟動時先跑一輪（補 App 沒開時的變更）
    _markAllDirty('啟動補掃');
  }

  List<String> _sandboxRoots() {
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        "SELECT DISTINCT folder_root FROM asset_index WHERE folder_root IS NOT NULL",
      );
      final roots = rows
          .map((r) => r['folder_root'] as String)
          .where((p) => Directory(p).existsSync())
          .toSet()
          .toList();
      return roots;
    } catch (e) {
      debugPrint('[AutoIngest] 讀根目錄失敗: $e');
      return const [];
    }
  }

  void _watch(String root) {
    final dir = Directory(root);
    if (!dir.existsSync()) return;
    try {
      final sub = dir.watch(recursive: true, events: FileSystemEvent.all).listen(
        (event) {
          // 忽略系統暫存（.DS_Store、隱藏檔、.tmp 前綴——偵探框架排除慣例）
          final path = event.path;
          final base = path.split('/').last;
          if (base.startsWith('.') || base.startsWith('.tmp.')) return;
          // [教練 Agent 2026-08-21] P0 自觸發死循環修復——fullScan 會把
          // manifest.json 寫進 watch 目錄的 .bridge/，事件回頭觸發
          // watcher → 300ms 後又 fullScan → 又寫 manifest → 無限循環。
          // 實測：App 啟動 120 秒（autoIngest 啟動）後 CPU 爬到 125%、
          // 記憶體 +64MB/min 漲到系統 OOM、每數秒重寫 manifest 一次。
          // 修：.bridge/ 是我們自己的工作目錄，事件一律忽略。
          if (path.contains('/.bridge/')) return;
          _dirtyRoots.add(root);
          _scheduleScan();
        },
        onError: (e) {
          // 外接碟卸載等——watcher 掛掉不炸服務，週期兜底會補
          debugPrint('[AutoIngest] watcher 錯誤 ($root): $e');
        },
      );
      _watchers.add(sub);
    } catch (e) {
      debugPrint('[AutoIngest] watch 失敗 ($root): $e');
    }
  }

  Timer? _debounce;

  /// [教練 Agent 2026-08-21] P0 保險絲——單一 root 兩輪掃描最小間隔 30 秒。
  /// 動機：除 .bridge 自觸發外，任何「掃描本身會寫回 watch 目錄」的
  /// 路徑（DB、快取、日誌）都會形成回授循環。防抖只解決突發，解決
  /// 不了持續回授；冷卻讓「掃描→事件→掃描」每輪至少間隔 30 秒，
  /// CPU 佔用從無限循環降到可忽略。真正的變更最多晚 30 秒入庫。
  final Map<String, DateTime> _lastScanAt = {};

  void _scheduleScan() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _scanDirtyRoots);
  }

  bool _onCooldown(String root) {
    final last = _lastScanAt[root];
    if (last == null) return false;
    return DateTime.now().difference(last).inSeconds < 30;
  }

  void _markAllDirty(String reason) {
    debugPrint('[AutoIngest] $reason：標記全部根目錄');
    for (final r in _sandboxRoots()) {
      _dirtyRoots.add(r);
    }
    _scheduleScan();
  }

  /// [小葵 2026-09-09 Blue 令] 手動重掃（模擬重新匯入）——
  /// 完成後自動觸發素描（分類自動修正）
  void requestFullRescan() => _markAllDirty('手動重掃');

  Future<void> _scanDirtyRoots() async {
    if (_scanning || _dirtyRoots.isEmpty) return;
    _scanning = true;
    // [教練 Agent 2026-08-21] 冷卻中的 root 延後處理（不丟失真實變更）
    final roots = List<String>.from(_dirtyRoots).where((r) {
      if (_onCooldown(r)) {
        Future.delayed(const Duration(seconds: 30), () {
          _dirtyRoots.add(r);
          _scheduleScan();
        });
        return false;
      }
      return true;
    }).toList();
    _dirtyRoots.clear();
    if (roots.isEmpty) {
      _scanning = false;
      return;
    }
    for (final r in roots) {
      _lastScanAt[r] = DateTime.now();
    }

    try {
      _writeStatus('running: 掃描 ${roots.length} 個根目錄');
      for (final root in roots) {
        try {
          // [教練 Agent 2026-08-21] 24/7 記憶體治理——樹指紋一致就整輪跳過
          //（不重建 records/不寫 manifest/不寫 DB），heap 不再緩漲
          await _indexService.fullScan(root, skipIfUnchanged: true);
        } catch (e) {
          debugPrint('[AutoIngest] 重掃失敗 ($root): $e');
        }
      }

      // 補嵌新增的 pending 檔（generateEmbeddings 本身冪等：
      // 只處理 DB pending / manifest embedding=false 的）
      _writeStatus('running: 補嵌新增檔案');
      await _indexService.generateEmbeddings();

      _writeStatus('idle: ${DateTime.now().toIso8601String()}');
      debugPrint('[AutoIngest] 一輪完成');

      // [小葵 2026-09-09 Blue 令] 差異嵌入完成 → 自動向量資料素描。
      // 使用者新增/編輯檔案 → 增量嵌入 → 素描自動重跑 → 分類/關聯詞
      // 自動修正（含重複資料夾合併規則：葉段 key 寫回 folder_origin）。
      // 素描失敗不影響嵌入（fail-open）。
      unawaited(() async {
        try {
          await VectorSketchService.instance.run();
          debugPrint('[AutoIngest] ✅ 自動素描完成（分類自動修正）');
        } catch (e) {
          debugPrint('[AutoIngest] 素描失敗（不影響嵌入）: $e');
        }
      }());
    } catch (e) {
      _writeStatus('error: $e');
      debugPrint('[AutoIngest] 輪失敗: $e');
    } finally {
      _scanning = false;
      // 掃描期間又髒了 → 立刻再來一輪
      if (_dirtyRoots.isNotEmpty) _scheduleScan();
    }
  }

  void _writeStatus(String s) {
    // [小葵 2026-09-30 F2] 活動中心掛牌——AutoIngest 全生命週期可視
    final r = BackgroundTaskRegistry.instance;
    final now = DateTime.now();
    if (s.startsWith('running:')) {
      r.update(BackgroundTask(
        id: 'auto_ingest', name: '自動檔案巡邏',
        detail: s.substring(8), startedAt: now,
        progress: -1, current: s.substring(8),
      ));
    } else if (s.startsWith('idle')) {
      r.finish('auto_ingest', note: '一輪完成');
    } else if (s.startsWith('error')) {
      r.finish('auto_ingest', note: '失敗：$s');
    }
    try {
      final db = BrainDatabase.instance.db;
      db.execute(
        "INSERT OR REPLACE INTO brain_meta (key, value) VALUES ('auto_ingest_status', ?)",
        [s],
      );
    } catch (_) {}
  }

  void dispose() {
    _cycleTimer?.cancel();
    _debounce?.cancel();
    for (final w in _watchers) {
      w.cancel();
    }
    _watchers.clear();
    _started = false;
  }
}
