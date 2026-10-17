// vault_screen.dart
// 向量資料庫大頁面 — 第二大腦首頁
// [教練 Agent 2026-07-22] Phase 2 ④
//
// 三檢視切換：列表 / Graph View / 卡片牆
// 左側標籤面板 + 右側詳情面板
// 三模式搜尋：全文 / 語意 / 標籤
//
// 設計文件：/Volumes/DATA/橋樑計劃/02-架構設計/向量資料庫與畫布交互設計.md

import 'dart:io';
import 'package:bridge_app/services/material_pool_service.dart';
import 'dart:async';

import 'package:bridge_app/services/vault/vault_service.dart';
import 'package:bridge_app/services/vault/vault_search_facade.dart'; // [S4 統一令]
import 'package:bridge_app/services/vector_db/asset_index_service.dart';
import 'package:bridge_app/widgets/settings/master_folder_card.dart';
import 'package:bridge_app/widgets/vault/thumb_image.dart';
import 'package:bridge_app/services/file_tag_store.dart';
import 'package:bridge_app/models/master_folder.dart' show FileTag;
import 'package:bridge_app/services/vector_db/thumb_cache.dart'; // [Blue 令] 縮圖快取 // [Blue 令 2026-10-17] 縮圖快取 // [Blue 令 2026-10-17] 資安邊界 // [教練 Agent 2026-07-25] 向量資料庫
import 'package:bridge_app/services/vector_db/asset_sandbox.dart'; // [教練 Agent 2026-07-25] 向量資料庫安全邊界
import 'package:bridge_app/services/vector_db/file_classifier.dart'; // [教練 Agent 2026-07-28] 決策 2：FileRoom
import 'package:bridge_app/services/vector_db/embedding_progress_tracker.dart'; // [教練 Agent 2026-07-31] 快速嵌入進度
import 'package:bridge_app/services/brain_container/brain_database.dart'; // [教練 Agent 2026-08-02] 嵌入統計
import 'package:bridge_app/services/vector_db/hybrid_search_service.dart'; // [教練 Agent 2026-07-25] 混合搜尋
import 'package:bridge_app/widgets/vault/vault_graph_view.dart';
import 'package:file_picker/file_picker.dart';
import 'package:collection/collection.dart';
import 'package:bridge_app/services/vector_db/dedup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

import '../services/vector_db/vision_embedding_pipeline.dart';
import '../widgets/vault/sovereignty_import_bubble.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../widgets/bridge_desktop_widgets.dart';
import 'vault/vault_entry_card.dart';
import 'vault/memory_layer_gauge.dart'; // [H2/M5] 記憶十層儀表
import 'vault/memory_layer_sidebar_section.dart'; // [H2/M5+] Blue 令：十層入側欄
import 'vault/memory_layer_entries_view.dart'; // [H2/M5+] 層條目主區視圖
import '../services/memory_layer_service.dart'; // [H2/M5+] MemoryLayer 定義
import 'vault/vault_file_tree.dart';
import '../services/vector_db/vector_sketch_service.dart'; // [小葵 2026-10-14] junk 過濾共用

/// 向量資料庫頁面檢視模式
enum VaultViewMode { materialWall, list } // [小葵 2026-08-29] 圖譜/卡片牆退場——那是大腦頁的職責，向量庫專注挑選素材

/// 向量資料庫大頁面
///
/// App 主導航的獨立 tab，與畫布、對話平級。
/// 這不是一個列表頁——它是使用者的大腦中樞。
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  /// [收據搜尋 S3 2026-09-08] 外部帶入搜尋字——全局搜尋「在向量資料庫開啟」
  /// 寫入此 ValueNotifier；VaultScreen initState 消費後清空。
  static final ValueNotifier<String?> externalSearchQuery = ValueNotifier(null);

  @override
  State<VaultScreen> createState() => VaultScreenState();
}

class VaultScreenState extends State<VaultScreen> {
  // --- 搜尋 ---
  final _searchController = TextEditingController();
  // [小葵 2026-09-09 Blue v2 檢索令] 預設「全部」——FTS+語意+五因素排序
  VaultSearchMode _searchMode = VaultSearchMode.hybrid;
  List<VaultEntry> _results = [];
  // [小葵 2026-09-09 Blue v2 檢索令] 分組檢視——搜尋結果按資料夾分組
  final Set<String> _expandedResultFolders = {};
  bool _isSearching = false;

  // --- 標籤 ---
  Map<String, int> _tagCounts = {};
  final List<String> _selectedTags = [];

  // [教練 Agent 2026-07-29] 六大房間篩選
  FileRoom? _selectedRoom;

  // [教練 Agent 2026-07-29] Vision 嵌入
  StreamSubscription<VisionPipelineProgress>? _visionPipelineSub;
  bool _visionEmbeddingRunning = false;
  VisionPipelineProgress? _visionProgress;

  // [教練 Agent 2026-07-31] 快速嵌入（文字類）進度
  StreamSubscription<EmbeddingProgress>? _quickEmbedSub;
  bool _quickEmbeddingRunning = false;
  EmbeddingProgress? _quickProgress;

  // [教練 Agent 2026-07-29] 掃描進度
  bool _isScanning = false;
  int _scanFolderIndex = 0;
  int _scanFolderTotal = 0;
  String _scanCurrentFolder = '';

  // [教練 Agent 2026-08-02] 嵌入統計狀態
  int _indexedCount = 0;
  int _pendingCount = 0;
  int _errorCount = 0;
  int _skippedCount = 0;  // [教練 Agent 2026-08-02] 無法嵌入的檔案（SVG/binary等），不算 error
  int _totalCount = 0;
  bool _isOneClickEmbedding = false;  // 一鍵嵌入執行中

  // --- 檢視模式 ---
  VaultViewMode _viewMode = VaultViewMode.materialWall; // [小葵 2026-08-29] 素材牆為預設——挑選體驗優先

  // --- 選中條目 ---
  VaultEntry? _selectedEntry;
  List<WikiLinkInfo> _outgoingLinks = [];
  List<WikiLinkInfo> _backlinks = [];
  bool _isLoadingDetail = false;

  // --- 統計 ---
  int _totalEntries = 0;

  // [教練 Agent 2026-07-25] 向量資料庫 — 圖書館區
  List<ManifestFile> _libraryFiles = [];
  int _libraryFileCount = 0;
  int _libraryFolderCount = 0;
  bool _libraryExpanded = true; // [教練 Agent 2026-07-28] 預設展開，讓使用者立刻看到檔案
  final Set<String> _expandedFolders = {}; // [教練 Agent 2026-07-28] 檔案樹展開狀態

  // [教練 Agent 2026-07-28] 檔案樹快取 — 避免每次 build 都重建 18550 個節點
  FileTreeNode? _fileTreeCache;
  int _fileTreeCacheHash = 0;

  // [小葵 2026-09-12] 離線根目錄——DB 有紀錄但磁碟上不存在（外接碟未掛載）
  final Set<String> _offlineRoots = {};
  int _offlineFileCount = 0;

  // [教練 Agent 2026-07-28] 決策 2：批量分類模式
  bool _batchMode = false;
  final Set<String> _selectedFileIds = {}; // 以 file_path 為 key
  // [Blue 令 2026-10-17] 標籤系統——自由文字標籤（FileTagStore）
  List<FileTag> _allTags = [];
  final _tagInputController = TextEditingController();
  // [Blue 令 2026-10-17] 標籤列表——使用者貼的＋DB 已有的
  String? _selectedTag;
  List<String> _dbTags = [];
  // [Blue 令 2026-10-17] 素材包選取——點側欄包=主區顯示該包素材牆
  String? _selectedPackId;
  Set<String> _expandedPacks = {};
  // [Blue 令 2026-10-17] 素材池泡泡——有東西加入時徽章上方冒提醒
  int _lastPoolCount = 0;
  bool _showPoolBubble = false;
  Timer? _poolBubbleTimer;
  Map<String, AssetRecord> _assetRecordsMap = {}; // file_path → AssetRecord
  Set<String> _dbFilePaths = {}; // [小葵 2026-09-24] DB 路徑快取（輕量 timer 用）

  // [小葵 2026-08-29] 素材池
  bool _poolDrawerOpen = false;
  // [小葵 2026-10-16 Blue 令] 向量庫資料夾「加入/移出」——左側列表管理
  bool _removeRootMode = false; // 移出模式：根層資料夾顯示叉叉

  // [H2/M5+ 2026-10-07 Blue 令] 記憶十層——選中層（null = 全部）
  MemoryLayer? _selectedLayer;

// [小葵 2026-08-29] Finder 樹——選中資料夾路徑（null = 全部）
  String? _selectedFolderPath;

  /// [小葵 2026-10-15] 首次載入完成旗標——空狀態 vs 載入中判別用
  bool _libraryLoadedOnce = false;
  final Set<String> _expandedTreeFolders = {};

  /// [小葵 2026-08-29] 檔案預覽——圖片看圖、文字讀前段、其他給資訊
  Future<void> _previewFile(ManifestFile mf) async {
    final absPath = '${mf.folder}/${mf.path}';
    final fileName = mf.path.split('/').last;
    final ext = mf.path.contains('.')
        ? mf.path.split('.').last.toLowerCase()
        : '';
    final file = File(absPath);
    final colors = BridgeDSColors.of(context);

    Widget content;
    if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext) &&
        await file.exists()) {
      content = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
        child: Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined,
                  size: 48, color: colors.textMuted),
              const SizedBox(height: 8),
              Text('圖片無法載入',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
            ],
          ),
        ),
      );
    } else if (['md', 'txt', 'json', 'csv'].contains(ext) &&
        await file.exists()) {
      final raw = await file.readAsString();
      final preview = raw.length > 2000
          ? '${raw.substring(0, 2000)}\n\n...（僅顯示前 2000 字）'
          : raw;
      content = Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 420),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.canvas,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: SingleChildScrollView(
          child: SelectableText(
            preview.isEmpty ? '（空檔案）' : preview,
            style: TierStyle.of(context, Tier.cardBody)
                .toTextStyle()
                .copyWith(color: colors.textPrimary, height: 1.6),
          ),
        ),
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined,
              size: 48, color: colors.textMuted),
          const SizedBox(height: 8),
          Text(
            '此檔案類型（.$ext）不支援內建預覽\n可從 Finder 開啟：\n$absPath',
            textAlign: TextAlign.center,
            style: TierStyle.of(context, Tier.cardBody)
                .toTextStyle()
                .copyWith(color: colors.textSecondary, height: 1.6),
          ),
        ],
      );
    }

    // [Blue 令 2026-10-17] 預覽時的池狀態
    final record0 = _assetRecordsMap[mf.path];
    final assetId0 = record0?.id ?? mf.path;
    final inPoolPreview = MaterialPoolService.instance.draft?.items
            .any((item) => item.assetId == assetId0) ==
        true;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        title: Text(fileName,
            style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
        content: content,
        actions: [
          // [小葵 2026-09-10 Blue 令] 資料夾按鈕——Finder 開該檔所屬資料夾
          OutlinedButton.icon(
            onPressed: () {
              // -R = 在 Finder 中揭示該檔（開資料夾+選中它）
              Process.runSync('open', ['-R', absPath]);
            },
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('資料夾'),
          ),
          // [Blue 令 2026-10-17] 預覽 dialog——已加入者按鈕變「取消加入素材池」
          OutlinedButton(
            onPressed: () {
              _togglePool(mf);
              Navigator.pop(ctx);
            },
            style: OutlinedButton.styleFrom(
              backgroundColor: colors.canvas,
              foregroundColor: BridgeDSColors.of(context).textPrimary,
              side: BorderSide(color: colors.accentPurple, width: 1.5),
            ),
            child: Text(inPoolPreview
                ? '取消加入素材池'
                : '加入素材池'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  /// [Blue 令 2026-10-17] 加入/移出素材池 toggle
  void _togglePool(ManifestFile mf) {
    final record = _assetRecordsMap[mf.path];
    final assetId = record?.id ?? mf.path;
    final inPool = MaterialPoolService.instance.draft?.items
            .any((item) => item.assetId == assetId) ==
        true;
    if (inPool) {
      MaterialPoolService.instance.removeFromDraft(assetId);
      setState(() {});
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text('已移出素材池：${mf.path.split('/').last}'),
        duration: const Duration(seconds: 2),
      ));
    } else {
      _addToPool(mf);
    }
  }

  /// 加入素材池
  void _addToPool(ManifestFile mf) {
    final record = _assetRecordsMap[mf.path];
    final ok = MaterialPoolService.instance.addToDraft(
      assetId: record?.id ?? mf.path,
      filePath: mf.path,
      fileName: mf.path.split('/').last,
      title: record?.title,
    );
    setState(() {});
    if (ok) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('已加入素材池：${mf.path.split('/').last}'),
          duration: const Duration(seconds: 2),
        ),
      );
      _bubblePool();
    }
  }

  /// [Blue 令 2026-10-17] 素材池徽章上方冒對話泡泡（3 秒）
  void _bubblePool() {
    _poolBubbleTimer?.cancel();
    setState(() => _showPoolBubble = true);
    _poolBubbleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showPoolBubble = false);
    });
  }

  /// 池徽章（右上角購物車計數）
  Widget _buildPoolBadge() {
    final count = MaterialPoolService.instance.draftCount;
    final colors = BridgeDSColors.of(context);
    final badge = GestureDetector(
      onTap: () => setState(() => _poolDrawerOpen = !_poolDrawerOpen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.canvas,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: count > 0 ? colors.accentPurple : colors.borderSubtle,
            width: count > 0 ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_basket_outlined,
              size: 16,
              color: count > 0 ? colors.accentPurple : colors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TierStyle.of(context, Tier.cardBody)
                  .toTextStyle()
                  .copyWith(
                    color: count > 0 ? colors.textPrimary : colors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );

    // [Blue 抓包 2026-10-17] Column 會佔高度→top bar 溢出 11px（黑黃警示條）。
    // 改 Stack overlay：泡泡浮在徽章正上方，不佔 layout 高度。
    if (!_showPoolBubble) return badge;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        badge,
        Positioned(
          bottom: badgeHeight + 8,
          child: _buildPoolBubble(count),
        ),
      ],
    );
  }

  static const badgeHeight = 34.0; // 徽章高度估算（padding6*2+icon16）

  /// 對話泡泡本體
  Widget _buildPoolBubble(int count) {
    final colors = BridgeDSColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.accentPurple,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            '素材池有 $count 件——在這裡打包素材',
            style: TierStyle.of(context, Tier.cardCaption)
                .toTextStyle()
                .copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  /// 素材池抽屜（右側）
  Widget _buildPoolDrawer() {
    final pool = MaterialPoolService.instance;
    final draft = pool.draft;
    final colors = BridgeDSColors.of(context);
    return Positioned(
      top: 64,
      right: 0,
      bottom: 0,
      width: 300,
      child: Material(
        color: colors.surface,
        child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            left: BorderSide(color: colors.borderSubtle, width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(-2, 0),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題列
            Container(
              padding: const EdgeInsets.all(BridgeDS.spaceMD),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.borderSubtle, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.shopping_basket,
                      size: 16, color: colors.accentPurple),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '素材池（${draft?.itemCount ?? 0}）',
                      style: TierStyle.of(context, Tier.cardTitle)
                          .toTextStyle()
                          .copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _poolDrawerOpen = false),
                    child: Icon(Icons.close,
                        size: 16, color: colors.textMuted),
                  ),
                ],
              ),
            ),
            // 素材列表
            Expanded(
              child: (draft == null || draft.isEmpty)
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 32, color: colors.textMuted),
                          const SizedBox(height: 8),
                          Text(
                            '池是空的\n搜尋後點「加入」挑選素材',
                            textAlign: TextAlign.center,
                            style: TierStyle.of(context, Tier.cardBody)
                                .toTextStyle()
                                .copyWith(color: colors.textMuted),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: draft.items.length,
                      itemBuilder: (ctx, i) {
                        final item = draft.items[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: colors.canvas,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: colors.borderSubtle),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 14,
                                color: colors.accentBlue,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item.fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TierStyle.of(context, Tier.cardBody)
                                      .toTextStyle()
                                      .copyWith(color: colors.textPrimary),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  pool.removeFromDraft(item.assetId);
                                  setState(() {});
                                },
                                child: Icon(Icons.remove_circle_outline,
                                    size: 14, color: colors.textMuted),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            // 底部動作列：打包存檔 / 清空
            if (draft != null && draft.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(BridgeDS.spaceMD),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: colors.borderSubtle, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          pool.discardDraft();
                          setState(() {});
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.textSecondary,
                          side: BorderSide(color: colors.borderDefault),
                        ),
                        child: const Text('清空'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: () => _sealPoolDialog(pool),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: colors.canvas,
                          foregroundColor: BridgeDSColors.of(context).textPrimary,
                          side: BorderSide(
                              color: colors.accentPurple, width: 1.5),
                        ),
                        child: Text(
                          '打包存檔',
                          style: TierStyle.of(context, Tier.cardBody)
                              .toTextStyle()
                              .copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // 既有素材包（載入續挑／刪除）
            Container(
              padding: const EdgeInsets.all(BridgeDS.spaceMD),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colors.borderSubtle, width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '我的素材包（${pool.packs.length}）',
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(
                          color: colors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  ...pool.packs.take(5).map(
                        (pack) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () async {
                                    await pool.loadPackAsDraft(pack.id);
                                    setState(() {});
                                  },
                                  child: Text(
                                    '${pack.title}（${pack.itemCount}）',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TierStyle.of(context, Tier.cardBody)
                                        .toTextStyle()
                                        .copyWith(color: colors.textPrimary),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () async {
                                  await pool.deletePack(pack.id);
                                  setState(() {});
                                },
                                child: Icon(Icons.delete_outline,
                                    size: 14, color: colors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  /// 打包存檔對話框——命名
  Future<void> _sealPoolDialog(MaterialPoolService pool) async {
    final nameController = TextEditingController(
      text: pool.draft?.title ?? '未命名素材包',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(context).surfaceElevated,
        title: Text('打包素材包',
            style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('給這包素材取個名字——之後可以隨時載入續用。',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                    color: BridgeDSColors.of(context).textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '例如：鹿角蕨專題',
                filled: true,
                fillColor: BridgeDSColors.of(context).surface,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameController.text),
            child: const Text('存檔'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final pack = pool.sealDraft(title: name);
    if (mounted) setState(() {}); // [Blue 令] 打包後側欄素材池列表刷新
      if (pack != null) {
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text('素材包已存檔：${pack.title}（${pack.itemCount} 個素材）'),
              backgroundColor: BridgeDSColors.of(context).accentGreen,
            ),
          );
        }
      }
    }
  }

  // --- Timer for search debounce ---
  Timer? _debounceTimer;
  // [教練 Agent 2026-08-02] 定時刷新嵌入統計（嵌入在背景跑時讓進度條動）
  Timer? _embedStatsTimer;

  @override
  void initState() {
    // [小葵 2026-08-29] 載入素材包庫
    MaterialPoolService.instance.load();
    super.initState();
    // [Blue 令 2026-10-17] 縮圖快取 48h 清理——背景執行不擋 UI
    ThumbCache.instance.purgeExpired();
    // [Blue 抓包] 開頁即載既有標籤（FileTagStore）——原本只在其後
    // 進「標籤系統」才載，側欄標籤區開頁永遠空白
    FileTagStore().loadAll().then((tags) {
      if (mounted && tags.isNotEmpty) setState(() => _allTags = tags);
    });
    // [Blue 抓包 v2] imageCache 容量——預設 100MB/1000 張不夠 6088 張牆，
    // 滑遠就逐出→回滑重 decode。提高容納全牆縮圖（240px 縮圖約 30-60KB/張，
    // 6088 張 decoded 約 300-400MB ui.Image——快取的 decoded 圖用 240x180
    // RGBA ≈ 170KB/張 → 6088 張 ≈ 1GB 上限太狂；設 400MB/2000 張折衷，
    // 搭配磁碟快取，逐出後重 decode 也只 decode 小縮圖（不是原圖））
    PaintingBinding.instance.imageCache.maximumSizeBytes = 400 << 20;
    PaintingBinding.instance.imageCache.maximumSize = 2000;
    // [收據搜尋 S3 2026-09-08] 消費外部搜尋字（全局搜尋 → vault 開啟）
    final extQuery = VaultScreen.externalSearchQuery.value;
    if (extQuery != null && extQuery.isNotEmpty) {
      VaultScreen.externalSearchQuery.value = null; // 消費即清
      _searchController.text = extQuery;
      _onSearchChanged(extQuery);
    }
    _visionPipelineSub = VisionEmbeddingPipeline.instance.progressStream.listen((p) {
      if (!mounted) return;
      setState(() {
        _visionProgress = p;
        _visionEmbeddingRunning = p.stage == VisionPipelineStage.analyzing ||
            p.stage == VisionPipelineStage.embedding;
      });
    });
    // [教練 Agent 2026-07-31] 監聽快速嵌入（文字類）進度
    // 先讀取快取的當前進度（如果嵌入已在跑，切到 vault 頁面時能立刻看到）
    final currentProgress = EmbeddingProgressTracker.instance.currentProgress;
    if (currentProgress.isActive) {
      _quickProgress = currentProgress;
      _quickEmbeddingRunning = true;
    }
    _quickEmbedSub = EmbeddingProgressTracker.instance.progressStream.listen((p) {
      if (!mounted) return;
      setState(() {
        _quickProgress = p;
        _quickEmbeddingRunning = p.isActive;
      });
    });
    _loadData();
    _loadEmbeddingStats();
    // [教練 Agent 2026-08-02] 每 5 秒刷新嵌入統計（背景嵌入時讓進度條動）
    _embedStatsTimer = Timer.periodic(const Duration(seconds: 30), (_) { // [v184] 5s→30s：main-thread DB 脈衝止血
      if (mounted) {
        _loadEmbeddingStats();
        // [小葵 2026-10-16] 總條目隨統計刷新——初次載入時 BrainDatabase
        // 可能未就緒（getTotalEntryCount catch 回 0），30 秒後補真值
        _loadTotalCount();
        // [小葵 2026-09-12] 離線偵測隨統計刷新——BrainContainer 初始化可能晚於
        // 首次載入（embedding 模型載入需數十秒），定時補偵測直到拿到 DB 真相
        // [小葵 2026-09-24] timer 用輕量版（只撈路徑）——_loadAssetRecords
        // 是 6908 行全欄位 SELECT，每 30s 打一次是讀取慢的幫兇
        _loadAssetPathsOnly();
        _detectOfflineRoots();
      }
    });
  }

  @override
  void dispose() {
    _poolBubbleTimer?.cancel();
    _tagInputController.dispose();
    _visionPipelineSub?.cancel();
    _quickEmbedSub?.cancel();
    _embedStatsTimer?.cancel();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _loadTags();
    await _loadTotalCount();
    await _loadLibraryFiles(); // [教練 Agent 2026-07-25] 向量資料庫
    await _performSearch();
  }

  // [教練 Agent 2026-07-25] 向量資料庫 — 載入圖書館檔案
  // [教練 Agent 2026-07-28] 決策 2：同時載入 DB 記錄（含 room / confidence）
  // [教練 Agent 2026-07-28] 修復：先 loadManifests 確保記憶體資料同步
  Future<void> _loadLibraryFiles() async {
    try {
      // [小葵 2026-10-16] prefs 競態修——等 sandbox 根清單就緒再讀 manifest
      await AssetSandbox().ensurePrefsLoaded();
      final indexService = AssetIndexService();
      await indexService.loadManifests(); // 確保 manifest 從磁碟載入
      // [小葵 2026-10-14 Blue 報案] 清篩選暴增 6 萬筆卡頓——44%（30,126 筆）是
      // venv/node_modules 等依賴樹 junk。素描層早有 isJunkFolder 過濾（省 LLM），
      // 檔案列表這層沒接——同一條規則兩層共用：對人類無參考價值的檔案不入牆。
      _libraryFiles = indexService.allFiles
          .where((mf) => !VectorSketchService.isJunkFolder(mf.path))
          .toList();
      _libraryFileCount = _libraryFiles.length; // 顯示數＝過濾後（牆上看到多少就是多少）
      _libraryFolderCount = indexService.folderCount;
      debugPrint('[VaultScreen] 載入完成: ${_libraryFiles.length} 檔案, '
          '$_libraryFileCount count, $_libraryFolderCount 資料夾');
      _libraryLoadedOnce = true;
      if (mounted) setState(() {}); // [小葵 2026-10-14] 檔案清單先上屏——不等 records/離線偵測
      // 從 DB 載入含 room/confidence 的記錄
      _loadAssetRecords();
      // [小葵 2026-09-12] 離線根目錄偵測——外接碟未掛載時 DB 有紀錄但檔案樹看不到
      await _detectOfflineRoots();
      // [小葵 2026-09-12] App 剛啟動時 BrainContainerService 可能尚未初始化完成
      // （getAllRecords 回空）——延遲重試，確保離線偵測一定拿到 DB 真相
      // [小葵 2026-10-14 Blue 報案] 這個重試迴圈原本擋在 setState 前面——
      // records 慢 5×2s＝開頁旋轉 10 秒+。改背景補：牆先顯示，records 到貨再補一幀。
      if (_assetRecordsMap.isEmpty) {
        for (var i = 0; i < 5 && _assetRecordsMap.isEmpty; i++) {
          await Future.delayed(const Duration(seconds: 2));
          if (!mounted) return;
          _loadAssetRecords();
          if (mounted && _assetRecordsMap.isNotEmpty) setState(() {});
        }
        await _detectOfflineRoots();
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('[VaultScreen] 載入圖書館檔案失敗: $e');
    }
  }

  /// [小葵 2026-09-12] 偵測離線根目錄（外接碟未掛載）
  ///
  /// DB 真相 vs 磁碟現況對帳：DB 裡有 folder_root 的紀錄、但該根目錄
  /// 現在不存在於磁碟上＝離線。UI 必須誠實顯示「離線 N 個資料夾，
  /// X 個檔案暫時看不到」，絕不默默縮水讓使用者誤以為東西不見了。
  Future<void> _detectOfflineRoots() async {
    _offlineRoots.clear();
    _offlineFileCount = 0;
    try {
      final records = _assetRecordsMap.values;
      final rootsInDb = <String, int>{};
      for (final r in records) {
        rootsInDb[r.folderRoot] = (rootsInDb[r.folderRoot] ?? 0) + 1;
      }
      for (final root in rootsInDb.keys) {
        final exists = await Directory(root).exists();
        if (!exists) {
          _offlineRoots.add(root);
          _offlineFileCount += rootsInDb[root] ?? 0;
        }
      }
      if (_offlineRoots.isNotEmpty) {
        debugPrint('[VaultScreen] ⚠️ 離線根目錄: ${_offlineRoots.length} 個, '
            '共 $_offlineFileCount 個檔案暫時看不到: $_offlineRoots');
      }
    } catch (e) {
      debugPrint('[VaultScreen] 離線偵測失敗: $e');
    }
  }

  /// [教練 Agent 2026-07-28] 決策 2：從 DB 載入 asset records（含 room / confidence）
  void _loadAssetRecords() {
    final records = AssetIndexService().getAllRecords();
    _assetRecordsMap = {
      for (final r in records) r.filePath: r,
    };
    _dbFilePaths = _assetRecordsMap.keys.toSet();
    // [Blue 令 2026-10-17] DB 既有標籤清單（側欄標籤區聯集用）
    _dbTags = _assetRecordsMap.values
        .expand((r) => r.tags)
        .toSet()
        .toList()
      ..sort();
    // [Blue 抓包] 標籤清單更新後通知 UI——否則側欄停在「尚無標籤」
    if (mounted) setState(() {});
  }

  /// [小葵 2026-09-24 Blue 抓包] 輕量版——只撈 file_path 集合。
  /// 30 秒 timer 的離線偵測只需要「DB 有哪些路徑」，
  /// 不需要 6908 行全欄位 SELECT（每 30s 一次的 main-thread 脈衝）。
  void _loadAssetPathsOnly() {
    if (!mounted) return;
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select('SELECT file_path FROM asset_index');
      _dbFilePaths = rows.map((r) => r['file_path'] as String).toSet();
      _assetRecordsMap = {
        for (final p in _dbFilePaths)
          if (_assetRecordsMap.containsKey(p)) p : _assetRecordsMap[p]!,
      };
    } catch (_) {
      // DB 尚未初始化——保持原狀，下次 timer 再試
    }
  }

  /// [教練 Agent 2026-08-02] 載入嵌入統計狀態
  Future<void> _loadEmbeddingStats() async {
    try {
      final db = BrainDatabase.instance.db;
      // [小葵 2026-10-16 Blue 報案] missing（已移出/死鏈）不算總數——
      // 否則 indexed 永遠 < total，落入「載入嵌入狀態...」僵屍分支
      final totalRows = db.select(
        "SELECT COUNT(*) as cnt FROM asset_index "
        "WHERE index_status != 'missing'",
      );
      _totalCount = totalRows.first['cnt'] as int? ?? 0;

      final indexedRows = db.select(
        "SELECT COUNT(*) as cnt FROM asset_index WHERE index_status = 'indexed'",
      );
      _indexedCount = indexedRows.first['cnt'] as int? ?? 0;

      final pendingRows = db.select(
        "SELECT COUNT(*) as cnt FROM asset_index WHERE index_status = 'pending'",
      );
      _pendingCount = pendingRows.first['cnt'] as int? ?? 0;

      final errorRows = db.select(
        "SELECT COUNT(*) as cnt FROM asset_index WHERE index_status IN ('error', 'skipped')",
      );
      _errorCount = errorRows.first['cnt'] as int? ?? 0;

      // [教練 Agent 2026-08-02] skipped 不算 error，獨立計算
      final skippedRows = db.select(
        "SELECT COUNT(*) as cnt FROM asset_index WHERE index_status = 'skipped'",
      );
      _skippedCount = skippedRows.first['cnt'] as int? ?? 0;

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[VaultScreen] 載入嵌入統計失敗: $e');
    }
  }

  /// [教練 Agent 2026-08-02] 一鍵嵌入（先快速嵌入再深度嵌入）
  Future<void> _startOneClickEmbedding() async {
    if (_quickEmbeddingRunning || _visionEmbeddingRunning || _isOneClickEmbedding) {
      return;
    }

    // [資料主權 09-15 Blue 令] 匯入前的提示語泡泡——主權與兩模式差別，
    // 在資料進入向量庫之前讓使用者看見並選擇。取消＝不嵌入。
    final mode = await SovereigntyImportBubble.show(
      context,
      pendingCount: _pendingCount,
      hasLocalModel: true, // vault 頁無法同步探測——pipeline 自己會 fallback
    );
    if (mode == null) return;
    VisionEmbeddingPipeline.instance.localOnlyOverride =
        (mode == SovereigntyMode.local);

    setState(() {
      _isOneClickEmbedding = true;
    });

    try {
      // 階段 1：快速嵌入（文字類）
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: BridgeDSColors.of(context).textPrimary),
                ),
                SizedBox(width: 12),
                Text('階段 1/2：快速嵌入中...'),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: BridgeDSColors.of(context).accentGreen,
          ),
        );
      }

      final quickCount = await AssetIndexService().generateEmbeddings();
      debugPrint('[VaultScreen] 快速嵌入完成: $quickCount 個檔案');

      // 等待快速嵌入完成
      await Future.delayed(const Duration(seconds: 1));

      // 階段 2：深度嵌入（圖片/影片）
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: BridgeDSColors.of(context).textPrimary),
                ),
                SizedBox(width: 12),
                Text('階段 2/2：深度嵌入中...'),
              ],
            ),
            duration: const Duration(seconds: 4),
            backgroundColor: BridgeDSColors.of(context).accentBlue,
          ),
        );
      }

      final visionCount = await VisionEmbeddingPipeline.instance.processPendingVisionAssets();
      debugPrint('[VaultScreen] 深度嵌入完成: $visionCount 個檔案');

      // 重新載入統計
      await _loadEmbeddingStats();
      await _loadLibraryFiles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('一鍵嵌入完成！快速嵌入 $quickCount 個，深度嵌入 $visionCount 個'),
            backgroundColor: BridgeDSColors.of(context).accentGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('[VaultScreen] 一鍵嵌入失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('一鍵嵌入失敗：$e'),
            backgroundColor: BridgeDSColors.of(context).accentYellow,
          ),
        );
      }
    } finally {
      setState(() {
        _isOneClickEmbedding = false;
      });
    }
  }

  /// [教練 Agent 2026-07-29] 掃描進度文字
  String _scanStatusText() {
    if (_scanFolderTotal <= 0) return '正在掃描，請稍候...';
    final folderName = _scanCurrentFolder.isEmpty ? '' : '：$_scanCurrentFolder';
    return '正在掃描第 $_scanFolderIndex/$_scanFolderTotal 個資料夾$folderName';
  }

  /// [教練 Agent 2026-07-28] 決策 2：切換批量選擇模式
  void _toggleBatchMode() {
    setState(() {
      _batchMode = !_batchMode;
      if (!_batchMode) {
        _selectedFileIds.clear();
      }
    });
    // [Blue 令 2026-10-17] 進標籤系統時載入既有標籤
    if (_batchMode) {
      FileTagStore().loadAll().then((tags) {
        if (mounted) setState(() => _allTags = tags);
      });
    }
  }

  /// [Blue 令 2026-10-17] 為選取檔案貼標籤（FileTagStore 持久化
  /// ＋同步 asset_index.tags——智慧搜尋與 Agent 向量檢索的定位方向）
  Future<void> _applyTag(String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty || _selectedFileIds.isEmpty) return;
    for (final path in _selectedFileIds) {
      await FileTagStore().tagFile(path, trimmed);
    }
    // 同步 DB：record tags 聯集（搜尋引擎吃這個）
    final recordIds = _selectedFileIds
        .map((p0) => _assetRecordsMap[p0]?.id)
        .whereType<String>()
        .toList();
    if (recordIds.isNotEmpty) {
      AssetIndexService().batchAddTags(recordIds, trimmed);
      _loadAssetRecords(); // 刷新快取＋_dbTags
      setState(() {}); // 側欄標籤區即時更新
    }
    _tagInputController.clear();
    final tags = await FileTagStore().loadAll();
    if (mounted) {
      setState(() => _allTags = tags);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已為 ${_selectedFileIds.length} 個檔案貼上「$trimmed」'),
      ));
    }
  }

  /// [教練 Agent 2026-07-28] 決策 2：切換選取檔案
  void _toggleSelectFile(String filePath) {
    setState(() {
      if (_selectedFileIds.contains(filePath)) {
        _selectedFileIds.remove(filePath);
      } else {
        _selectedFileIds.add(filePath);
      }
    });
  }

  /// [教練 Agent 2026-07-28] 決策 2：全選 / 全不選
  void _toggleSelectAll() {
    setState(() {
      if (_selectedFileIds.length == _libraryFiles.length) {
        _selectedFileIds.clear();
      } else {
        _selectedFileIds
          ..clear()
          ..addAll(_libraryFiles.map((f) => f.path));
      }
    });
  }

  /// [教練 Agent 2026-07-28] 決策 2：批量改房間
  Future<void> _batchUpdateRoom(FileRoom room) async {
    if (_selectedFileIds.isEmpty) return;

    // 從 file_path 查找對應的 AssetRecord id
    final recordIds = <String>[];
    for (final filePath in _selectedFileIds) {
      final record = _assetRecordsMap[filePath];
      if (record != null) {
        recordIds.add(record.id);
      }
    }

    if (recordIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('選取的檔案尚未建立索引，無法修改分類'),
            backgroundColor: BridgeDSColors.of(context).accentYellow,
          ),
        );
      }
      return;
    }

    final updated = AssetIndexService().batchUpdateRoom(recordIds, room);

    // 重新載入記錄
    _loadAssetRecords();

    if (mounted) {
      setState(() {
        _selectedFileIds.clear();
        _batchMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已將 $updated 個檔案歸類到「${room.label}」'),
          backgroundColor: BridgeDSColors.of(context).accentGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _loadTags() async {
    final tags = await VaultService.instance.getAllTags();
    if (mounted) {
      setState(() => _tagCounts = tags);
    }
  }

  Future<void> _loadTotalCount() async {
    final count = await VaultService.instance.getTotalEntryCount();
    if (mounted) {
      setState(() => _totalEntries = count);
    }
  }

  Future<void> _performSearch() async {
    setState(() => _isSearching = true);

    // [教練 Agent 2026-07-25] hybrid 模式用 HybridSearchService（同時搜大腦 + 檔案）
    if (_searchMode == VaultSearchMode.hybrid) {
      // [S4 統一令] hybrid 走 VaultSearchFacade——與全域搜尋同一套程式碼
      try {
        _results = await VaultSearchFacade.instance.search(
          query: _searchController.text,
          mode: VaultFacadeMode.hybrid,
          limit: 100000, // [小葵 2026-09-09 Blue 令] 搜尋無上限
        );
        if (mounted) {
          setState(() => _isSearching = false);
        }
        return;
      } catch (e) {
        debugPrint('[VaultScreen] hybrid 搜尋失敗，降級為全文: $e');
        // 降級為全文搜尋（facade 內也會降級——此處攔 UI 例外）
      }
    }

    // [S4 統一令] 非 hybrid 模式也走 facade——所有搜尋單一真相
    final results = await VaultSearchFacade.instance.search(
      mode: _searchMode == VaultSearchMode.hybrid
          ? VaultFacadeMode.fullText
          : switch (_searchMode) {
              VaultSearchMode.semantic => VaultFacadeMode.semantic,
              VaultSearchMode.tag => VaultFacadeMode.tag,
              _ => VaultFacadeMode.fullText,
            },
      query: _searchController.text,
      roomFilter: null,
      tagFilter: _selectedTags.isEmpty ? null : _selectedTags,
      limit: 100,
    );

    if (mounted) {
      setState(() {
        _results = results;
        _isSearching = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    // [小葵 2026-09-09 Blue 回報] 輸入即亮「搜尋中」——debounce 400ms
    // 期間就讓使用者知道系統有反應，不會以為當機
    if (value.isNotEmpty) setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _performSearch();
    });
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
    _performSearch();
  }

  Future<void> _selectEntry(VaultEntry entry) async {
    setState(() {
      _selectedEntry = entry;
      _isLoadingDetail = true;
    });

    final outgoing = await VaultService.instance.getOutgoingLinks(entry.id);
    final backlinks = await VaultService.instance.getBacklinks(entry.id);

    if (mounted) {
      setState(() {
        _outgoingLinks = outgoing;
        _backlinks = backlinks;
        _isLoadingDetail = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: BridgeDSColors.of(context).canvas,
      child: Stack(
        children: [
          Row(
            children: [
              // 左側標籤面板
              _buildTagPanel(),

              // 主內容區
              Expanded(
                child: Column(
                  children: [
                    // [教練 Agent 2026-07-25] 資料夾管理頭部
                    _buildFolderHeader(),
                    // 頂部：搜尋列 + 檢視切換
                    _buildTopBar(),

                    // 主內容
                    Expanded(
                      child: _buildMainContent(),
                    ),

                    // [教練 Agent 2026-07-28] 決策 2：批量操作列
                    if (_batchMode) _buildBatchActionBar(),

                    // 底部嵌入進度條（固定在向量資料庫頁面底部）
                    _buildEmbeddingProgressBar(),

                    // 底部狀態列
                    _buildStatusBar(),
                  ],
                ),
              ),

              // 右側詳情面板
              if (_selectedEntry != null) _buildDetailPanel(),
            ],
          ),

          // [小葵 2026-08-29] 素材池抽屜（右側覆蓋）
          if (_poolDrawerOpen) _buildPoolDrawer(),
        ],
      ),
    );
  }

  // ── 左側標籤面板 ──────────────────────────────────────────────

  Widget _buildTagPanel() {
    // [小葵 2026-08-29] Blue 指示：六大房間下架——改 Finder 式樹狀資料夾。
    // 傳統樹狀選單是大眾習慣；點資料夾 → 中間區出現該資料夾檔案（素材牆）。
    final colors = BridgeDSColors.of(context);
    final tree = _buildFolderTreeData();
    final hasFilter = _selectedFolderPath != null;

    // [Blue 令 2026-10-17] 點側欄空白處=一鍵清除全部篩選（回原始狀態）
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_selectedFolderPath != null ||
            _selectedPackId != null ||
            _selectedRoom != null ||
            _selectedTag != null ||
            _selectedLayer != null ||
            _searchController.text.isNotEmpty) {
          setState(() {
            _selectedFolderPath = null;
            _selectedPackId = null;
            _selectedRoom = null;
            _selectedTag = null;
            _selectedLayer = null;
            _searchController.clear();
          });
        }
      },
      child: Container(
      width: 220,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          right: BorderSide(color: colors.borderSubtle, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 標題：資料夾 ──
          Padding(
            padding: const EdgeInsets.all(BridgeDS.spaceMD),
            child: Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 16, color: colors.accentBlue),
                const SizedBox(width: 8),
                Text('資料夾',
                    style: TierStyle.of(context, Tier.cardHeroTitle)
                        .toTextStyle()),
                const Spacer(),
                if (hasFilter)
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedFolderPath = null;
                      _selectedRoom = null;
                    }),
                    child: Tooltip(
                      message: '清除資料夾篩選',
                      child: Icon(Icons.filter_alt_off_outlined,
                          size: 14, color: colors.textMuted),
                    ),
                  ),
                // [Blue 令 2026-10-17] 資安邊界入口（盾牌）
                Tooltip(
                  message: '資安邊界——App 只碰這裡登錄的資料夾',
                  child: GestureDetector(
                    onTap: _showBoundaryDialog,
                    child: Icon(Icons.shield_outlined,
                        size: 15, color: colors.accentGreen),
                  ),
                ),
                // [小葵 2026-10-16] 加入資料夾（Finder 選單）／移出模式
                const SizedBox(width: 8),
                _buildFolderManageButtons(),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── 樹狀資料夾 ──
          Expanded(
            child: tree == null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '尚無資料\n點右上「加入資料夾」開始',
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(color: colors.textMuted, height: 1.6),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._buildFolderTreeNodes(tree, 0),
                        // [Blue 令 2026-10-17] 標籤區——使用者＋向量庫標籤
                        _buildTagSidebarSection(),
                        // [Blue 令 2026-10-17] 素材池區隨樹捲動——
                        // 放 Expanded 之外會被樹擠出可視區（點不到）
                        _buildPoolSidebarSection(),
                      ],
                    ),
                  ),
          ),
          // ── [H2/M5+ Blue 令 v2] 記憶十層固定側欄底部（點擊展開列表）──
          MemoryLayerSidebarSection(
            selectedLayer: _selectedLayer,
            onLayerTap: (layer) => setState(() {
              _selectedLayer = layer;
              _selectedFolderPath = null; // 層過濾與資料夾過濾互斥
              _selectedRoom = null;
            }),
          ),
        ],
      ),
      ),
    );
  }

  // ── [小葵 2026-10-16 Blue 令] 向量庫資料夾加入/移出 ──────────────

  /// 標題列的 ＋ / − 小按鈕
  /// [Blue 令 2026-10-17] 資安邊界（主資料夾）——App 只碰登錄的資料夾。
  /// 檔案總管頁退役，邊界管理搬到向量資料庫頁（邊界＝向量庫範圍）。
  void _showBoundaryDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('資安邊界（主資料夾）'),
        content: const SizedBox(
          width: 480,
          child: MasterFolderCard(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
        ],
      ),
    );
  }

  /// [Blue 令 2026-10-17] 側欄「標籤」區——使用者貼的標籤＋DB 既有標籤。
  /// 點標籤=主區過濾出帶該標籤的檔案（方向定位——向量搜尋的錨點）
  Widget _buildTagSidebarSection() {
    final colors = BridgeDSColors.of(context);
    // 聯集：FileTagStore（用戶貼的）＋ asset_index tags（向量庫已有）
    final userTags = _allTags.map((t) => t.label).toSet();
    final allTags = {...userTags, ..._dbTags}.toList()..sort();
    final isSelected = _selectedTag != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              // [Blue 令 2026-10-17] 標籤 icon 橘黃色（Tier token：accentYellow）
              Icon(Icons.label_outline, size: 18, color: colors.accentYellow),
              const SizedBox(width: 8),
              Text('標籤',
                  style: TierStyle.of(context, Tier.cardHeroTitle)
                      .toTextStyle()),
              const Spacer(),
              if (isSelected)
                GestureDetector(
                  onTap: () => setState(() => _selectedTag = null),
                  child: Tooltip(
                    message: '清除標籤篩選',
                    child: Icon(Icons.filter_alt_off_outlined,
                        size: 14, color: colors.textMuted),
                  ),
                ),
            ],
          ),
        ),
        if (allTags.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              '尚無標籤\n選取檔案後用「標籤系統」貼標籤',
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: colors.textMuted, height: 1.5),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: allTags.take(30).map((label) {
                final selected = _selectedTag == label;
                final count = _libraryFiles
                    .where((mf) =>
                        (_assetRecordsMap[mf.path]?.tags ?? const [])
                            .map((t) => t)
                            .contains(label) ||
                        _allTags
                            .where((t) => t.label == label)
                            .expand((t) => t.filePaths)
                            .contains(mf.path))
                    .length;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedTag = selected ? null : label;
                    _selectedFolderPath = null;
                    _selectedPackId = null;
                    _selectedRoom = null;
                  }),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.accentYellow.withValues(alpha: 0.18)
                          : colors.surfaceHover.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: selected
                            ? colors.accentYellow
                            : colors.borderSubtle,
                      ),
                    ),
                    child: Text(
                      '#$label $count',
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(
                            color: selected
                                ? colors.accentYellow
                                : colors.textSecondary,
                          ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  /// [Blue 令 2026-10-17] 側欄「素材池」區——與「資料夾」同層級同規格：
  /// 同標題樣式（cardHeroTitle）、樹狀節點（▸/▾＋名稱＋件數）、
  /// 點包＝主區素材牆顯示該包內容（與點資料夾同款預覽卡）
  Widget _buildPoolSidebarSection() {
    final colors = BridgeDSColors.of(context);
    final pool = MaterialPoolService.instance;
    final packs = pool.packs;
    final hasPackFilter = _selectedPackId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        // 標題列——與「資料夾」同款樣式
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 18, color: colors.accentPurple),
              const SizedBox(width: 8),
              Text('素材池',
                  style: TierStyle.of(context, Tier.cardHeroTitle)
                      .toTextStyle()),
              const Spacer(),
              if (hasPackFilter)
                GestureDetector(
                  onTap: () => setState(() => _selectedPackId = null),
                  child: Tooltip(
                    message: '清除素材包篩選',
                    child: Icon(Icons.filter_alt_off_outlined,
                        size: 14, color: colors.textMuted),
                  ),
                ),
              if (pool.draftCount > 0) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() => _poolDrawerOpen = true),
                  child: Text(
                    '草稿 ${pool.draftCount} 件',
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(color: colors.accentPurple),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (packs.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              '尚無素材包\n加入素材後「打包存檔」會存在這裡',
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: colors.textMuted, height: 1.5),
            ),
          )
        else
          // 樹狀節點——與資料夾樹同款視覺（▸/▾＋icon＋名稱＋件數）
          ...packs.map((pack) {
            final isExpanded = _expandedPacks.contains(pack.id);
            final isSelected = _selectedPackId == pack.id;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                _selectedPackId = isSelected ? null : pack.id;
                _selectedFolderPath = null; // 包過濾與資料夾過濾互斥
                _selectedRoom = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                color: isSelected
                    ? colors.accentPurple.withValues(alpha: 0.12)
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => setState(() {
                            isExpanded
                                ? _expandedPacks.remove(pack.id)
                                : _expandedPacks.add(pack.id);
                          }),
                          child: Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_right,
                            size: 14,
                            color: colors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          isExpanded
                              ? Icons.folder_zip
                              : Icons.folder_zip_outlined,
                          size: 14,
                          // [Blue 令 2026-10-17] 與樹節點同邏輯——平時
                          // accentBlue 常亮（原 textMuted 灰顯得小一號）
                          color: isSelected ? colors.accentPurple : colors.accentBlue,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            pack.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // [Blue 令 2026-10-17] 與樹節點同級——同字級同邏輯
                            style: TierStyle.of(context, Tier.cardBody)
                                .toTextStyle()
                                .copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        Text('${pack.itemCount}',
                            style: TierStyle.of(context, Tier.cardBody)
                                .toTextStyle()
                                .copyWith(color: colors.textMuted)),
                      ],
                    ),
                    // 展開：包內檔名逐列（點列=主牆直接看該包）
                    if (isExpanded)
                      Padding(
                        padding: const EdgeInsets.only(left: 24, top: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: pack.items
                              .take(8)
                              .map((item) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 1),
                                    child: Text(
                                      item.fileName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TierStyle.of(context, Tier.cardCaption)
                                          .toTextStyle()
                                          .copyWith(
                                              color: colors.textMuted,
                                              fontSize: 10),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 6),
      ],
    );
  }
  Widget _buildFolderManageButtons() {
    final colors = BridgeDSColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: '加入資料夾到向量資料庫',
          child: GestureDetector(
            onTap: _addFolderToVault,
            child: Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: colors.accentBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(Icons.add, size: 14, color: colors.accentBlue),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: _removeRootMode ? '取消移出模式' : '移出資料夾（選取模式）',
          child: GestureDetector(
            onTap: () => setState(() => _removeRootMode = !_removeRootMode),
            child: Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: _removeRootMode
                    ? colors.accentRed.withValues(alpha: 0.15)
                    : colors.surfaceHover.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: _removeRootMode
                      ? colors.accentRed.withValues(alpha: 0.5)
                      : colors.borderSubtle,
                  width: 1,
                ),
              ),
              child: Icon(Icons.remove,
                  size: 14,
                  color: _removeRootMode
                      ? colors.accentRed
                      : colors.textMuted),
            ),
          ),
        ),
      ],
    );
  }

  /// 加入：Finder 選資料夾 → sandbox 註冊 → 全掃（asset_library_panel 同款鏈）
  Future<void> _addFolderToVault() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '選擇要加入向量資料庫的資料夾',
    );
    if (path == null || path.trim().isEmpty) return;
    final sandbox = AssetSandbox();
    final existed = sandbox.rootPaths.contains(path);
    sandbox.addFolder(path);
    try {
      await AssetIndexService().fullScan(path);
      if (mounted) _loadAssetRecords(); // sync void——觸發重載即可
    } catch (e) {
      debugPrint('[Vault] 加入資料夾掃描失敗: $e');
    } finally {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(existed
              ? '「${path.split('/').last}」已在清單中，已重新掃描'
              : '已加入「${path.split('/').last}」到向量資料庫')),
        );
      }
    }
  }

  /// 移出：確認對話框（防誤觸）→ sandbox 移除 → 向量標 missing（除痕≠刪除）
  Future<void> _removeRootFromVault(String rootPath) async {
    final name = rootPath.split('/').last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('移出向量資料庫',
            style: TierStyle.of(ctx, Tier.cardHeroTitle).toTextStyle()),
        content: Text(
          '確定要將「$name」移出向量資料庫嗎？\n\n'
          '· 檔案不會被刪除\n'
          '· 向量索引會標記為「missing」，搜尋不再命中\n'
          '· 之後可隨時再加回來（重新掃描即可）',
          style: TierStyle.of(ctx, Tier.cardBody)
              .toTextStyle()
              .copyWith(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: BridgeDSColors.of(ctx).accentRed),
            child: const Text('確認移出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    AssetSandbox().removeFolder(rootPath);
    try {
      final db = BrainDatabase.instance.db;
      db.execute(
        "UPDATE asset_index SET index_status = 'missing' WHERE folder_root = ?",
        [rootPath],
      );
      // [Blue 報案] chunks 向量除污（35 萬筆 UPDATE）移到背景——
      // asset_index 標 missing 已擋搜尋，除污不需要卡在確認流程裡
      Future<void>.delayed(const Duration(milliseconds: 100)).then((_) {
        try {
          final db2 = BrainDatabase.instance.db;
          db2.execute(
            "UPDATE asset_chunks SET embedding = NULL, model_version = NULL "
            "WHERE asset_id IN "
            "  (SELECT id FROM asset_index WHERE folder_root = ?)",
            [rootPath],
          );
          debugPrint('[Vault] chunks 背景除污完成: $name');
        } catch (e) {
          debugPrint('[Vault] chunks 背景除污失敗: $e');
        }
      });
    } catch (e) {
      debugPrint('[Vault] 移出標記失敗: $e');
    }
    if (mounted) {
      // [小葵 2026-10-16 Blue 報案] 移除後樹不刷新——快取打穿＋manifest 重載
      _folderTreeCache = null;
      _folderTreeCacheHash = 0;
      setState(() {
        _removeRootMode = false;
        _selectedFolderPath = null;
      });
      _loadAssetRecords();
      _loadLibraryFiles(); // sandbox 已移除該根 → manifest 重載即剔除
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已將「$name」移出向量資料庫（檔案未刪除）')),
      );
    }
  }

  /// 建樹狀資料夾資料（從 _libraryFiles，快取）
  FileTreeNode? _folderTreeCache;
  int _folderTreeCacheHash = 0;

  /// [小葵 2026-10-16] DB fallback 根層樹——manifest 不可讀時的最後一哩。
  FileTreeNode? _buildRootTreeFromDb() {
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        "SELECT folder_root, COUNT(*) AS n FROM asset_index "
        "WHERE folder_root IS NOT NULL AND index_status = 'indexed' "
        "GROUP BY folder_root ORDER BY folder_root",
      );
      if (rows.isEmpty) return null;
      final root = FileTreeNode(name: '/', path: '/', isFolder: true);
      for (final r in rows) {
        final p = r['folder_root'] as String;
        root.children.add(FileTreeNode(
          name: p.split('/').last,
          path: p,
          isFolder: true,
        ));
      }
      return root;
    } catch (_) {
      return null;
    }
  }

  FileTreeNode? _buildFolderTreeData() {
    // [小葵 2026-10-16 Blue 令 UI 驗收抓包] manifest 讀取死鎖 fallback——
    // .bridge/manifest.json 的磁碟 I/O 卡死（EINTR 循環，ls 都卡）時，
    // _libraryFiles 空 → 樹消失「尚無資料」。改：manifest 空時從
    // asset_index（系統碟 DB，健康）直建根層樹——至少看得到根＋檔案數。
    if (_libraryFiles.isEmpty) return _buildRootTreeFromDb();
    
    final hash = _libraryFiles.length.hashCode ^
        _libraryFiles.first.folder.hashCode;
    if (_folderTreeCache == null || _folderTreeCacheHash != hash) {
      // [小葵 2026-09-09] groupByRoot——第一層為授權根（資料庫/DATA…），
      // 各根保留自己的原生結構，不再扁平混層
      _folderTreeCache = buildFileTree(_libraryFiles, groupByRoot: true);
      _folderTreeCacheHash = hash;
    }
    return _folderTreeCache;
  }

  /// 遞迴渲染樹節點（Finder 風格：▸/▾ 資料夾名（N））
  List<Widget> _buildFolderTreeNodes(FileTreeNode node, int depth) {
    final colors = BridgeDSColors.of(context);
    node.ensureSorted();
    final widgets = <Widget>[];

    for (final child in node.children.where((c) => c.isFolder)) {
      final isExpanded = _expandedTreeFolders.contains(child.path);
      final isSelected = _selectedFolderPath == child.path;
      // [小葵 2026-10-16 Blue 令] 移出模式：根層（depth==0）顯示叉叉
      final showRemoveX = _removeRootMode && depth == 0;

      widgets.add(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: showRemoveX
              ? () => _removeRootFromVault(child.path)
              : () => setState(() {
            _selectedFolderPath = child.path;
            if (isExpanded) {
              _expandedTreeFolders.remove(child.path);
            } else {
              _expandedTreeFolders.add(child.path);
            }
          }),
          onSecondaryTap: () {}, // 保留擴充空間
          child: Container(
            margin: EdgeInsets.only(left: depth * 14.0),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            color: showRemoveX
                ? colors.accentRed.withValues(alpha: 0.08)
                : isSelected
                    ? colors.accentPurple.withValues(alpha: 0.12)
                    : null,
            child: Row(
              children: [
                if (showRemoveX) ...[
                  Icon(Icons.close, size: 13, color: colors.accentRed),
                  const SizedBox(width: 6),
                ] else ...[
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 14,
                  color: colors.textMuted,
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded
                      ? Icons.folder_open_outlined
                      : Icons.folder_outlined,
                  size: 14,
                  color: isSelected ? colors.accentPurple : colors.accentBlue,
                ),
                const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    child.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TierStyle.of(context, Tier.cardBody)
                        .toTextStyle()
                        .copyWith(
                          color: showRemoveX
                              ? colors.textPrimary
                              : isSelected
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                          fontWeight:
                              isSelected || showRemoveX
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                        ),
                  ),
                ),
                Text(
                  '${child.totalFileCount}',
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
        ),
      );

      // 選到資料夾也觸發篩選（單擊箭頭展開；點名字＝篩選+展開）
      // ↑ 我們把「點整列」定義為：篩選該資料夾＋切換展開
      if (isSelected != null) {}

      if (isExpanded) {
        widgets.addAll(_buildFolderTreeNodes(child, depth + 1));
      }
    }
    return widgets;
  }


  // ── 頂部搜尋列 + 檢視切換 ──────────────────────────────────────

  /// [小葵 2026-08-29] 重建（簡化版）——當前資料夾麵包屑
  Widget _buildFolderHeader() {
    final colors = BridgeDSColors.of(context);
    final count = _filteredLibraryFiles.length;
    // [Blue 令 2026-10-17] 素材包過濾時顯示包名
    if (_selectedPackId != null) {
      final pack = MaterialPoolService.instance.packs
          .where((p) => p.id == _selectedPackId)
          .firstOrNull;
      if (pack != null) {
        // 包模式直接回專屬 header（icon＋包名＋件數＋清除）
        return Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceMD),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              bottom: BorderSide(color: colors.borderSubtle, width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_zip_outlined,
                  size: 14, color: colors.accentPurple),
              const SizedBox(width: 6),
              Text(
                pack.title,
                style: TierStyle.of(context, Tier.cardBody)
                    .toTextStyle()
                    .copyWith(
                        color: colors.textPrimary, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text(
                '$count 個檔案',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: colors.textMuted),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _selectedPackId = null),
                child: Tooltip(
                  message: '離開素材包',
                  child: Icon(Icons.close,
                      size: 14, color: colors.textMuted),
                ),
              ),
            ],
          ),
        );
      }
    }
    final current = _selectedFolderPath ?? '所有資料夾';
    final shortName = current.split('/').last;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open_outlined,
              size: 14, color: colors.accentBlue),
          const SizedBox(width: 6),
          Text(
            shortName,
            style: TierStyle.of(context, Tier.cardBody)
                .toTextStyle()
                .copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count 個檔案',
            style: TierStyle.of(context, Tier.cardCaption)
                .toTextStyle()
                .copyWith(color: colors.textMuted),
          ),
          // [小葵 2026-09-12] 離線根目錄誠實顯示——外接碟未掛載時 DB 紀錄仍在
          // 但檔案樹看不到。顯示真實離線數＋提示，絕不默默縮水。
          if (_offlineRoots.isNotEmpty) ...[
            const SizedBox(width: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.accentRed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: colors.accentRed.withValues(alpha: 0.5),
                    width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.usb_off_outlined,
                      size: 13, color: colors.accentRed),
                  const SizedBox(width: 5),
                  Text(
                    '離線 ${_offlineRoots.length} 個資料夾 · $_offlineFileCount 個檔案暫時看不到',
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(
                          color: colors.accentRed,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(width: 5),
                  Tooltip(
                    message: '這些資料夾的磁碟目前未連接：\n'
                        '${_offlineRoots.join('\n')}\n\n'
                        '檔案索引都還在（沒有消失），磁碟接回後按「重新掃描」即可恢復。',
                    child: Icon(Icons.help_outline,
                        size: 13, color: colors.accentRed),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        border: Border(
          bottom: BorderSide(
            color: BridgeDSColors.of(context).borderSubtle,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 搜尋列
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).surfaceHover,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.search,
                      size: 18, color: BridgeDSColors.of(context).textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
                      decoration: InputDecoration(
                        hintText: _searchMode == VaultSearchMode.hybrid
                            ? '搜尋全部（智慧排序）...'
                            : _searchMode == VaultSearchMode.semantic
                                ? '語意搜尋...'
                                : _searchMode == VaultSearchMode.tag
                                    ? '標籤篩選...'
                                    : '搜尋條目...',
                        hintStyle: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  // 搜尋模式切換
                  PopupMenuButton<VaultSearchMode>(
                    icon: Icon(Icons.tune,
                        size: 18, color: BridgeDSColors.of(context).textMuted),
                    tooltip: '搜尋模式',
                    onSelected: (mode) {
                      setState(() => _searchMode = mode);
                      _performSearch();
                    },
                    // [小葵 2026-09-10 Blue 抓包] 選項字直接指定 14——
                    // M3 PopupMenuItem 內 Text 不吃 popupMenuTheme.textStyle，
                    // 全域改了兩輪都沒效，這裡顯式指定一次到位。
                    itemBuilder: (context) => [
                      // [小葵 2026-09-09 Blue v2 檢索令] 四模式真差異化：
                      // 全部=FTS+語意+查詢擴展+五因素排序（日常入口）
                      const PopupMenuItem(
                        value: VaultSearchMode.hybrid,
                        child: Row(children: [
                          Icon(Icons.auto_awesome, size: 16),
                          SizedBox(width: 8),
                          Text('全部（智慧排序）',
                              style: TextStyle(fontSize: 14)),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: VaultSearchMode.fullText,
                        child: Row(children: [
                          Icon(Icons.text_fields, size: 16),
                          SizedBox(width: 8),
                          Text('全文（精確字面）',
                              style: TextStyle(fontSize: 14)),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: VaultSearchMode.semantic,
                        child: Row(children: [
                          Icon(Icons.psychology_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('語意（概念搜尋）',
                              style: TextStyle(fontSize: 14)),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: VaultSearchMode.tag,
                        child: Row(children: [
                          Icon(Icons.local_offer_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('標籤（分類瀏覽）',
                              style: TextStyle(fontSize: 14)),
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // [小葵 2026-08-29] 素材池徽章（購物車）——點開抽屜
          _buildPoolBadge(),
          const SizedBox(width: 8),

          // [教練 Agent 2026-08-02] 一鍵嵌入按鈕（快速嵌入 + 深度嵌入）
          Semantics(
            label: _isOneClickEmbedding ? '一鍵嵌入進行中' : '一鍵嵌入',
            button: true,
            child: IconButton(
              tooltip: _isOneClickEmbedding
                  ? '一鍵嵌入進行中...'
                  : '一鍵嵌入（文字 + 圖片/影片）',
              icon: _isOneClickEmbedding
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          BridgeDSColors.of(context).accentGreen,
                        ),
                      ),
                    )
                  : Icon(Icons.play_circle_outline, size: 20),
              color: _isOneClickEmbedding
                  ? BridgeDSColors.of(context).accentGreen
                  : BridgeDSColors.of(context).textMuted,
              onPressed: (_isOneClickEmbedding || _quickEmbeddingRunning || _visionEmbeddingRunning)
                  ? null
                  : _startOneClickEmbedding,
            ),
          ),

          // [小葵 2026-09-09 Blue 令] 實體去重入口——使用者主動觸發，
          // dry-run 預覽 → 確認才刪（丟垃圾桶可反悔）
          Semantics(
            label: '去重分析',
            button: true,
            child: IconButton(
              tooltip: '去重分析（預覽重複檔案）',
              icon: const Icon(Icons.content_copy, size: 20),
              color: BridgeDSColors.of(context).textMuted,
              onPressed: _showDedupDialog,
            ),
          ),

          // [教練 Agent 2026-07-28] 決策 2：批量選擇模式切換按鈕
          if (_libraryFileCount > 0)
            Semantics(
              label: _batchMode ? '退出標籤系統' : '標籤系統', // [Blue 令 2026-10-17] 批量調整分類→標籤系統
              button: true,
              child: IconButton(
                tooltip: _batchMode ? '退出標籤系統' : '標籤系統',
                icon: Icon(
                  _batchMode ? Icons.checklist : Icons.checklist_outlined,
                  size: 20,
                ),
                color: _batchMode
                    ? BridgeDSColors.of(context).accentPurple
                    : BridgeDSColors.of(context).textMuted,
                onPressed: _toggleBatchMode,
              ),
            ),

          // 檢視切換
          _buildViewModeSwitcher(),
        ],
      ),
    );
  }

  Widget _buildViewModeSwitcher() {
    return Container(
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceHover,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: VaultViewMode.values.map((mode) {
          final isSelected = _viewMode == mode;
          final icon = switch (mode) {
            VaultViewMode.materialWall => Icons.dashboard_customize,
            VaultViewMode.list => Icons.list,
          };
          final label = switch (mode) {
            VaultViewMode.materialWall => '素材牆',
            VaultViewMode.list => '列表',
          };

          return Semantics(
            label: '切換到$label檢視',
            button: true,
            child: IconButton(
              tooltip: label,
              icon: Icon(icon, size: 18),
              color: isSelected
                  ? BridgeDSColors.of(context).accentPurple
                  : BridgeDSColors.of(context).textMuted,
              // [小葵 2026-10-14 Blue 報案] 層視圖優先權蓋過 _viewMode——
              // 只設 viewMode 不清 _selectedLayer 時畫面紋絲不動（點了沒反應）。
              // 切到素材牆＝同時退出層視圖，兩顆素材牆按鈕行為一致。
              onPressed: () => setState(() {
                _viewMode = mode;
                if (mode == VaultViewMode.materialWall) {
                  debugPrint('[MemoryLayer] 工具列素材牆鈕：清 _selectedLayer');
                  _selectedLayer = null;
                }
              }),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── 主內容區 ──────────────────────────────────────────────────

  Widget _buildMainContent() {
    if (_isSearching && _results.isEmpty && _libraryFiles.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: BridgeDSColors.of(context).accentPurple,
        ),
      );
    }

    // [教練 Agent 2026-07-28] 修復：fileCount > 0 但 files 為空 → manifest 未同步，重新載入
    if (_libraryFileCount > 0 && _libraryFiles.isEmpty) {
      _loadLibraryFiles(); // 觸發重新載入
      return Center(
        child: CircularProgressIndicator(
          color: BridgeDSColors.of(context).accentBlue,
        ),
      );
    }

    if (_results.isEmpty && _libraryFiles.isEmpty) {
      return _buildEmptyState();
    }

    // [H2/M5+ Blue 令 v2] 記憶層瀏覽最優先——點層即主區顯示（可編輯），
    // 蓋過素材牆/檔案列表：層是第一公民不是附屬。
    if (_selectedLayer != null) {
      return MemoryLayerEntriesView(
        layer: _selectedLayer!,
        onClose: () {
          debugPrint('[MemoryLayer] 素材牆返回鈕點擊：清 _selectedLayer');
          setState(() => _selectedLayer = null);
        },
      );
    }

    // [小葵 2026-08-29] 素材牆——挑選/預覽/打包的核心體驗（預設）
    if (_viewMode == VaultViewMode.materialWall) {
      return _buildMaterialWall();
    }

    // [教練 Agent 2026-07-25] 列表模式時加入圖書館區
    // [教練 Agent 2026-07-29] 檔案區與記憶區視覺分離
    if (_viewMode == VaultViewMode.list) {
      return ListView(
        padding: const EdgeInsets.all(BridgeDS.spaceMD),
        children: [
          // 📚 向量資料庫（檔案區）
          if (_libraryFileCount > 0)
            Container(
              margin: const EdgeInsets.only(bottom: BridgeDS.spaceMD),
              padding: const EdgeInsets.all(BridgeDS.spaceMD),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: BridgeDSColors.of(context)
                      .accentBlue
                      .withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: _buildLibrarySection(),
            ),

          // 🧠 大腦記憶區
          Container(
            padding: const EdgeInsets.all(BridgeDS.spaceMD),
            decoration: BoxDecoration(
              color: BridgeDSColors.of(context).surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: BridgeDSColors.of(context)
                    .accentPurple
                    .withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 大腦記憶標題
                Row(
                  children: [
                    Icon(Icons.psychology_outlined,
                        size: 16,
                        color: BridgeDSColors.of(context).accentPurple),
                    const SizedBox(width: 8),
                    Text('大腦記憶', style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
                    const SizedBox(width: 6),
                    Text('$_totalEntries',
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,)),
                  ],
                ),
                // [H2/M5 2026-10-07] 記憶十層容量儀表（Blue 贈禮可視化）
                const MemoryLayerGauge(),
                const SizedBox(height: BridgeDS.spaceSM),
                if (_results.isNotEmpty) ...[
                  ..._results.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: VaultEntryCard(
                          entry: entry,
                          isSelected: _selectedEntry?.id == entry.id,
                          onTap: () => _selectEntry(entry),
                        ),
                      )),
                ] else if (!_isSearching) ...[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '大腦記憶區尚無條目',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    switch (_viewMode) {
      case VaultViewMode.materialWall:
        return _buildMaterialWall(); // 不會到這裡，上方已處理
      case VaultViewMode.list:
        return _buildListView(); // 不會到這裡，上方已處理
    }
  }

  /// 日期段折疊——把路徑中的純日期段（2026-05-13 / 20260513 / 05-13 等）
  /// 拿掉再比對，讓「不同日期的同品種資料夾」歸為一組。
  static final RegExp _dateSegRe = RegExp(r'^\d{4}[-_/]?\d{1,2}([-_/]?\d{1,2})?$');
  String _foldDateSegments(String folder) {
    final segs = folder.split('/').where((s) {
      final t = s.trim();
      if (t.isEmpty) return false;
      if (_dateSegRe.hasMatch(t)) return false; // 日期段折掉
      return true;
    }).toList();
    return segs.isEmpty ? folder : segs.join('/');
  }

  /// [小葵 2026-09-09 Blue 令] 葉段分組 key——同葉名（品種名）跨根合併。
  /// 例：阿川資料區/.../Blue陽台/象耳鹿角蕨子株 與
  /// 01_現況紀錄/.../Blue陽台/象耳鹿角蕨子株 → 同組「象耳鹿角蕨子株」。
  /// （日期折疊後）葉段就是人類分類的最小單位——品種名。
  String _leafGroupKey(String folder) {
    final folded = _foldDateSegments(folder);
    final segs = folded.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return folder;
    return segs.last;
  }

  // ═══ [小葵 2026-09-09 Blue v2 檢索令] 分組搜尋結果 ═══
  //
  // 搜「鹿角蕨」→ 先看到品種資料夾卡（7/20 檔案相關）→ 點開看命中檔案。
  // 資料夾排序＝組內最高相關度；組內按五因素排序（facade 已排好）。

  Widget _buildGroupedSearchResults() {
    final colors = BridgeDSColors.of(context);

    // 記憶命中（agent=非 asset_index）獨立一組
    final memoryEntries =
        _results.where((e) => e.agent != 'asset_index').toList();
    // 資產命中按資料夾分組（subCategory 承載相對路徑）
    final assetEntries =
        _results.where((e) => e.agent == 'asset_index').toList();
    final groups = <String, List<VaultEntry>>{};
    for (final e in assetEntries) {
      final path = e.subCategory;
      final folder = path.contains('/')
          ? path.substring(0, path.lastIndexOf('/'))
          : '';
      // [小葵 2026-09-09 Blue 令] 品種級分組加強——葉段 key：
      // 同一資料夾名（象耳鹿角蕨子株）在多個授權根有副本
      // （阿川資料區/03_照片紀錄/... vs 01_現況紀錄/照片紀錄/...）
      // 一律併成同一組。葉名衝突跨主題時才退回折疊全路徑。
      final key = folder.isEmpty
          ? '（根目錄散檔）'
          : _leafGroupKey(folder);
      groups.putIfAbsent(key, () => []).add(e);
    }
    // 資料夾排序：組內第一筆（最高分）的原始順序
    final groupKeys = groups.keys.toList();

    // [小葵 2026-09-09 Blue 令] 圖片組排最前——組內首筆是圖片者優先，
    // 再按組大小；記憶條目（純文字）殿後
    bool groupHasImage(String k) => groups[k]!.any((e) {
          final mf = _libraryFiles
              .where((f) => f.path == e.subCategory)
              .firstOrNull;
          if (mf == null) return false;
          final ext = mf.path.contains('.')
              ? mf.path.split('.').last.toLowerCase()
              : '';
          return ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'].contains(ext);
        });
    groupKeys.sort((a, b) {
      final ia = groupHasImage(a) ? 1 : 0;
      final ib = groupHasImage(b) ? 1 : 0;
      if (ia != ib) return ib.compareTo(ia);
      return groups[b]!.length.compareTo(groups[a]!.length);
    });

    return CustomScrollView(
      slivers: [
        // [小葵 2026-09-09 Blue 令] 資料夾卡方格排版（非條列）
        SliverPadding(
          padding: const EdgeInsets.all(BridgeDS.spaceMD),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: BridgeDS.spaceSM,
              crossAxisSpacing: BridgeDS.spaceSM,
              childAspectRatio: 0.95,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final key = groupKeys[i];
                final group = groups[key]!;
        final isExpanded = _expandedResultFolders.contains(key);
        final folderName = key.split('/').last;
        // [小葵 2026-09-09 Blue 驗收回報] 資料夾組補滿——該資料夾全部
        // 檔案都展開（不只命中的），命中檔標記。Blue 要「點開品種資料夾
        // 看到所有照片」，搜尋只是帶路。
        final siblingFiles = _siblingFilesOf(key);

                // [小葵 2026-09-09 Blue 令] 方格卡片——上縮圖下名稱
                return _buildFolderGridCard(
                    key, group, siblingFiles, isExpanded);
              },

              childCount: groupKeys.length,
            ),
          ),
        ),
        // 記憶條目殿後
        if (memoryEntries.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceMD),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final e = memoryEntries[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: VaultEntryCard(
                      entry: e,
                      isSelected: _selectedEntry?.id == e.id,
                      onTap: () => _selectEntry(e),
                    ),
                  );
                },
                childCount: memoryEntries.length,
              ),
            ),
          ),
      ],
    );
  }

  /// [小葵 2026-09-09 Blue 令] 去重分析對話框——掃描（dry-run）→
  /// 列出重複候選 → 使用者確認 → 刪除（丟垃圾桶）。
  /// 鐵則：不主動執行；刪除權力在使用者手上。
  Future<void> _showDedupDialog() async {
    final colors = BridgeDSColors.of(context);
    var scanning = true;
    var candidates = <DedupCandidate>[];
    unawaited(DedupService.instance.scan().then((r) {
      candidates = r;
      scanning = false;
      // 觸發重建——用 setState 包不住 dialog，改用 ValueNotifier 或
      // 簡單法：掃完再開第二個對話框
    }));
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return Dialog(
            backgroundColor: colors.surfaceElevated,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BridgeDS.roundComfortable)),
            child: Container(
              width: 640,
              height: 480,
              padding: const EdgeInsets.all(BridgeDS.spaceMD),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Icon(Icons.content_copy,
                        size: 18, color: colors.accentBlue),
                    const SizedBox(width: 8),
                    Text('去重分析',
                        style: TierStyle.of(context, Tier.cardTitle)
                            .toTextStyle()
                            .copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close,
                          size: 18, color: colors.textMuted),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    '掃描內容相同（hash 一致）的圖片／影片副本。\n'
                    '只預覽不刪除——確認後才會丟進垃圾桶（可反悔）。',
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(color: colors.textTertiary),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: scanning
                        ? const Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          )
                        : candidates.isEmpty
                            ? Center(
                                child: Text('沒有發現重複檔案 🎉',
                                    style: TierStyle.of(context, Tier.cardBody)
                                        .toTextStyle()),
                              )
                            : ListView.builder(
                                itemCount: candidates.length,
                                itemBuilder: (c, i) {
                                  final cd = candidates[i];
                                  final mb =
                                      (cd.sizeBytes / 1024 / 1024).toStringAsFixed(1);
                                  return ListTile(
                                    dense: true,
                                    leading: Icon(Icons.copy_outlined,
                                        size: 16, color: colors.accentYellow),
                                    title: Text(
                                      cd.dupPath.split('/').last,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TierStyle.of(context, Tier.cardCaption)
                                          .toTextStyle()
                                          .copyWith(color: colors.textPrimary),
                                    ),
                                    subtitle: Text(
                                      '${cd.dupPath}\n保留：${cd.keepPath}（$mb MB）',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TierStyle.of(context, Tier.cardCaption)
                                          .toTextStyle()
                                          .copyWith(
                                              color: colors.textTertiary,
                                              fontSize: 10),
                                    ),
                                    isThreeLine: true,
                                  );
                                },
                              ),
                  ),
                  if (!scanning && candidates.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Text(
                          '${candidates.length} 個重複 · 共 ${(_totalDupMb(candidates)).toStringAsFixed(0)} MB 可省',
                          style: TierStyle.of(context, Tier.cardCaption)
                              .toTextStyle()
                              .copyWith(color: colors.accentYellow),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () async {
                            final ok = await DedupService.instance
                                .delete(candidates);
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      '已移除 $ok 個重複檔到垃圾桶（可反悔）')),
                            );
                          },
                          child: Text('移除 ${candidates.length} 個到垃圾桶'),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  double _totalDupMb(List<DedupCandidate> cs) =>
      cs.fold(0.0, (a, c) => a + c.sizeBytes) / 1024 / 1024;

  /// [小葵 2026-09-09 Blue 回報] 資料夾詳情視窗——點方格卡開啟，
  /// 整面縮圖牆立即呈現（命中藍框高亮），點縮圖再開大圖預覽。
  Future<void> _openFolderDetail(
      String key, List<VaultEntry> group, List<ManifestFile> siblings) async {
    final colors = BridgeDSColors.of(context);
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: colors.surfaceElevated,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BridgeDS.roundComfortable)),
        child: Container(
          width: 900,
          height: 620,
          padding: const EdgeInsets.all(BridgeDS.spaceMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 標題列
              Row(
                children: [
                  // [小葵 2026-09-09 Blue 驗收回報] 標題縮圖必須包尺寸
                  // ——無約束 Image.file 用原圖 4000px 撐爆視窗
                  // （看起來像「縮圖局部放大圖」的元兇）
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: _folderCardCover(siblings, colors),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      key.split('/').last,
                      style: TierStyle.of(context, Tier.cardTitle)
                          .toTextStyle()
                          .copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Text(
                    '命中 ${group.length} / 共 ${siblings.length} 筆',
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(color: colors.accentBlue),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: colors.textMuted),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              // 縮圖牆（可捲動——命中在前藍框，其餘同資料夾在後）
              Expanded(
                child: _buildFolderThumbGrid(key, group, siblings,
                    scrollable: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 展開組的 sibling 檔案（供 Sliver 縮圖牆用）
  List<ManifestFile> _siblingFilesOf(String key) {
    return _libraryFiles.where((f) {
      final fFolder = f.path.contains('/')
          ? f.path.substring(0, f.path.lastIndexOf('/'))
          : '';
      if (fFolder.isEmpty) return key == '（根目錄散檔）';
      return _leafGroupKey(fFolder) == key;
    }).toList();
  }

  /// [小葵 2026-09-09 Blue 令] 方格資料夾卡——上大縮圖、下名稱與筆數。
  /// 點卡＝展開/收合該組縮圖牆（在方格牆下方）。
  Widget _buildFolderGridCard(String key, List<VaultEntry> group,
      List<ManifestFile> siblings, bool isExpanded) {
    final colors = BridgeDSColors.of(context);
    final folderName = key.split('/').last;

    return GestureDetector(
      // [小葵 2026-09-09 Blue 回報] 點卡＝開資料夾詳情視窗——原本
      // inline 展開掛在方格牆尾端，點了看不到像沒反應
      onTap: () => _openFolderDetail(key, group, siblings),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          border: Border.all(color: colors.borderSubtle.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 卡面縮圖
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(7)),
                child: _folderCardCover(siblings, colors),
              ),
            ),
            // 名稱+筆數
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${group.length}/${siblings.length} 筆',
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(
                          color: colors.accentBlue,
                          fontSize: 10,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 卡面大縮圖（第一張圖片；無圖退回資料夾 icon）
  Widget _folderCardCover(List<ManifestFile> siblings, colors) {
    final img = siblings.firstWhereOrNull((f) {
      final ext = f.path.contains('.')
          ? f.path.split('.').last.toLowerCase()
          : '';
      return ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'].contains(ext);
    });
    if (img == null) {
      return Container(
        color: colors.surfaceHover.withValues(alpha: 0.4),
        alignment: Alignment.center,
        child: Icon(Icons.folder_outlined,
            size: 32, color: colors.accentBlue),
      );
    }
    return ThumbImage(
      file: File('${img.folder}/${img.path}'),
      errorBuilder: (_) => Container(
        color: colors.surfaceHover.withValues(alpha: 0.4),
        alignment: Alignment.center,
        child: Icon(Icons.folder_outlined,
            size: 32, color: colors.accentBlue),
      ),
    );
  }

  /// [小葵 2026-09-09 Blue 令] 資料夾卡縮圖——第一張圖片當卡面
  Widget _folderCardThumb(List<ManifestFile> siblings) {
    final colors = BridgeDSColors.of(context);
    final img = siblings.firstWhereOrNull((f) {
      final ext = f.path.contains('.')
          ? f.path.split('.').last.toLowerCase()
          : '';
      return ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'].contains(ext);
    });
    if (img == null) {
      return Icon(Icons.folder_outlined, size: 20, color: colors.accentBlue);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        width: 32,
        height: 32,
        child: ThumbImage(
          file: File('${img.folder}/${img.path}'),
          errorBuilder: (_) =>
              Icon(Icons.folder_outlined, size: 20, color: colors.accentBlue),
        ),
      ),
    );
  }

  /// [小葵 2026-09-09 Blue 驗收回報] 資料夾縮圖牆——點開品種資料夾
  /// 看到所有照片（縮圖預覽），命中檔加藍框高亮。
  Widget _buildFolderThumbGrid(
      String folderKey, List<VaultEntry> hits, List<ManifestFile> siblings,
      {bool scrollable = false}) {
    final hitPaths = hits.map((e) => e.subCategory).toSet();
    // 命中檔在前（按分數序），同資料夾其餘照片在後
    final hitFiles = <ManifestFile>[];
    for (final e in hits) {
      final mf = _libraryFiles.where((f) => f.path == e.subCategory).firstOrNull;
      if (mf != null) hitFiles.add(mf);
    }
    final rest =
        siblings.where((f) => !hitPaths.contains(f.path)).toList();
    final all = [...hitFiles, ...rest];

    if (all.isEmpty) {
      // 命中但 manifest 沒有（例如 memories）——退回列表列
      return Column(
        children: hits
            .map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _buildGroupedAssetRow(e),
                ))
            .toList(),
      );
    }

    return GridView.builder(
      // [小葵 2026-09-09 Blue 回報] 詳情視窗（Dialog Expanded 內）要可
      // 捲動——shrinkWrap 會把 171 張全展開爆版；inline 場景維持原樣
      shrinkWrap: !scrollable,
      physics: scrollable
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 4),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.82,
      ),
      itemCount: all.length,
      itemBuilder: (ctx, i) {
        final mf = all[i];
        final isHit = hitPaths.contains(mf.path);
        final fileName = mf.path.split('/').last;
        final ext = mf.path.contains('.')
            ? mf.path.split('.').last.toLowerCase()
            : '';
        final absPath = '${mf.folder}/${mf.path}';
        final isImage =
            ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext);

        return GestureDetector(
          onTap: () => _previewFile(mf),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isHit
                  ? Border.all(
                      color: BridgeDSColors.of(context).accentBlue, width: 2)
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (isImage)
                    // [Blue 令 2026-10-17] 縮圖 48h 快取——回滑不重讀原圖
                    ThumbImage(
                      file: File(absPath),
                      errorBuilder: (_) => _wallFallbackIcon(ext),
                    )
                  else
                    _wallFallbackIcon(ext),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.55),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      child: Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 組內資產列（精簡：圖示/縮圖 + 檔名 + 開啟）
  Widget _buildGroupedAssetRow(VaultEntry e) {
    final colors = BridgeDSColors.of(context);
    final relPath = e.subCategory;
    final fileName = relPath.split('/').last;
    // 從 manifest 找對應檔案（預覽/加入素材池用）
    final mf = _libraryFiles
        .where((f) => f.path == relPath)
        .firstOrNull;

    return InkWell(
      onTap: mf != null ? () => _previewFile(mf) : null,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Icon(Icons.insert_drive_file_outlined,
                size: 14, color: colors.accentBlue),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TierStyle.of(context, Tier.cardBody)
                    .toTextStyle()
                    .copyWith(color: colors.textPrimary),
              ),
            ),
            if (mf != null)
              GestureDetector(
                onTap: () => _addToPool(mf),
                child: Icon(Icons.add_shopping_cart_outlined,
                    size: 14, color: colors.accentPurple),
              ),
          ],
        ),
      ),
    );
  }

  // ═══ [小葵 2026-08-29] 素材牆——挑選/預覽/打包核心體驗 ═══
  Widget _buildMaterialWall() {
    final files = _filteredLibraryFiles;
    final colors = BridgeDSColors.of(context);

    // [小葵 2026-09-09 Blue v2 檢索令] 搜尋分組呈現——結果按資料夾分組，
    // 先見資料夾（既有分類），點開才看命中檔案（Blue 的檢索心法）
    if (_isSearching || _searchController.text.isNotEmpty) {
      // [小葵 2026-09-09 Blue 回報] 搜尋中提示——讓使用者知道系統在跑
      if (_isSearching && _results.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 12),
              Text(
                '搜尋中…',
                style: TierStyle.of(context, Tier.cardBody)
                    .toTextStyle()
                    .copyWith(color: colors.textMuted),
              ),
            ],
          ),
        );
      }
      if (_results.isEmpty && files.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 48, color: colors.textMuted),
              const SizedBox(height: 12),
              Text(
                '沒有符合的素材',
                style: TierStyle.of(context, Tier.cardTitle)
                    .toTextStyle()
                    .copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        );
      }
      return _buildGroupedSearchResults();
    }

    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: colors.textMuted),
            const SizedBox(height: 12),
            Text(
              '沒有符合的素材',
              style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              '試試別的關鍵詞，或清除房間篩選',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: BridgeDS.spaceSM,
        crossAxisSpacing: BridgeDS.spaceSM,
        childAspectRatio: 0.82, // 卡片 180x220
      ),
      itemCount: files.length,
      itemBuilder: (ctx, i) => _buildMaterialCard(files[i]),
    );
  }

  /// 單張素材卡——縮圖本體（圖片看圖/文字看開頭/媒體看類型）＋檔名＋加入鈕
  Widget _buildMaterialCard(ManifestFile mf) {
    final colors = BridgeDSColors.of(context);
    final fileName = mf.path.split('/').last;
    final ext = mf.path.contains('.')
        ? mf.path.split('.').last.toLowerCase()
        : '';
    final absPath = '${mf.folder}/${mf.path}';
    final record = _assetRecordsMap[mf.path];
    final inPool = MaterialPoolService.instance.draft?.items
            .any((item) => item.assetId == (record?.id ?? mf.path)) ==
        true;

    final isImage =
        ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext);
    final isText = ['md', 'txt', 'json', 'csv'].contains(ext);
    final isVideo = ['mp4', 'mov'].contains(ext);
    final isAudio = ['mp3', 'wav', 'm4a'].contains(ext);

    return GestureDetector(
      // [Blue 令 2026-10-17] 標籤模式點卡=選取；一般模式=大預覽
      onTap: () => _batchMode
          ? _toggleSelectFile(mf.path)
          : _previewFile(mf),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: inPool
                ? colors.accentPurple.withValues(alpha: 0.6)
                : colors.borderSubtle,
            width: inPool ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 預覽區
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(9)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (isImage)
                      // [Blue 抓包 v2] 主牆卡——真正的病灶在這（之前只改到搜尋卡）
                      ThumbImage(
                        file: File(absPath),
                        errorBuilder: (_) => _wallFallbackIcon(ext),
                      )
                    else if (isText)
                      FutureBuilder<String>(
                        future: _readTextHead(absPath),
                        builder: (ctx, snap) {
                          final head = snap.data ?? '';
                          if (head.isEmpty) return _wallFallbackIcon(ext);
                          return Container(
                            color: colors.canvas,
                            padding: const EdgeInsets.all(8),
                            alignment: Alignment.topLeft,
                            child: Text(
                              head,
                              maxLines: 7,
                              overflow: TextOverflow.fade,
                              style: TierStyle.of(context, Tier.cardCaption)
                                  .toTextStyle()
                                  .copyWith(
                                    color: colors.textSecondary,
                                    height: 1.4,
                                  ),
                            ),
                          );
                        },
                      )
                    else
                      _wallFallbackIcon(ext),
                    // 類型角標（影片/音訊）
                    if (isVideo || isAudio)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isVideo
                                    ? Icons.movie_outlined
                                    : Icons.audio_file_outlined,
                                size: 10,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                isVideo ? '影片' : '音訊',
                                style: TierStyle.of(context, Tier.cardCaption)
                                    .toTextStyle()
                                    .copyWith(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // 底部：檔名＋加入鈕
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // [Blue 令 2026-10-17] 加入素材池 toggle——再點一次取消；
                  // 未加入時圓圈預設白色（原紫太隱形）
                  GestureDetector(
                    onTap: () => _togglePool(mf),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: inPool ? colors.accentPurple : colors.canvas,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: inPool
                              ? colors.accentPurple
                              : Colors.white.withValues(alpha: 0.9),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        inPool ? Icons.check : Icons.add,
                        size: 12,
                        color: inPool ? Colors.white : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 媒體類 fallback 圖示（置中大圖示）
  Widget _wallFallbackIcon(String ext) {
    final colors = BridgeDSColors.of(context);
    IconData icon = Icons.insert_drive_file_outlined;
    if (['mp4', 'mov'].contains(ext)) {
      icon = Icons.movie_outlined;
    } else if (['mp3', 'wav', 'm4a'].contains(ext)) {
      icon = Icons.audio_file_outlined;
    } else if (['pdf', 'docx'].contains(ext)) {
      icon = Icons.description_outlined;
    }
    return Container(
      color: colors.canvas,
      alignment: Alignment.center,
      child: Icon(icon, size: 32, color: colors.textMuted),
    );
  }

  /// 讀文字檔開頭（素材卡內嵌預覽）
  Future<String> _readTextHead(String absPath) async {
    try {
      final f = File(absPath);
      if (!await f.exists()) return '';
      final raw = await f.readAsString();
      if (raw.isEmpty) return '';
      return raw.length > 300 ? raw.substring(0, 300) : raw;
    } catch (_) {
      return '';
    }
  }

  // [教練 Agent 2026-07-25] 向量資料庫 — 圖書館區
  // [教練 Agent 2026-07-28] 改為分層檔案樹結構
  Widget _buildLibrarySection() {
    final hasSearch = _searchController.text.isNotEmpty;
    // [教練 Agent 2026-07-29] 房間篩選時也用 flat list（檔案樹無法按 room 過濾）
    final hasRoomFilter = _selectedRoom != null;
    final showFlatList = hasSearch || hasRoomFilter;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _libraryExpanded = !_libraryExpanded),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 16, color: BridgeDSColors.of(context).accentBlue),
                const SizedBox(width: 8),
                Text('向量資料庫', style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_libraryFileCount',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentBlue,
                      fontWeight: FontWeight.w600,),
                  ),
                ),
                if (_libraryFolderCount > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '($_libraryFolderCount 個資料夾)',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                  ),
                ],
                // [小葵 2026-09-12] 離線根目錄誠實顯示——DB 有紀錄但磁碟上不存在
                if (_offlineRoots.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: BridgeDSColors.of(context).accentRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.usb_off_outlined, size: 12,
                            color: BridgeDSColors.of(context).accentRed),
                        const SizedBox(width: 4),
                        Text(
                          '離線 $_offlineFileCount 檔',
                          style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(
                            color: BridgeDSColors.of(context).accentRed,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: '外接碟未掛載：${_offlineRoots.join('\n')}\n檔案沒有不見，掛回磁碟後重新檢查即可。',
                    child: Icon(Icons.help_outline, size: 14,
                        color: BridgeDSColors.of(context).textMuted),
                  ),
                ],
                // [教練 Agent 2026-07-29] 房間篩選指示器
                if (_selectedRoom != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Color(_selectedRoom!.colorValue).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Color(_selectedRoom!.colorValue).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_selectedRoom!.icon, style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
                        const SizedBox(width: 4),
                        Text(
                          _selectedRoom!.label,
                          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: Color(_selectedRoom!.colorValue),
                            fontWeight: FontWeight.w600,),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => setState(() => _selectedRoom = null),
                          child: Icon(
                            Icons.close,
                            size: 12,
                            color: Color(_selectedRoom!.colorValue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                Icon(
                  _libraryExpanded ? Icons.expand_less : Icons.chevron_right,
                  size: 16,
                  color: BridgeDSColors.of(context).textMuted,
                ),
              ],
            ),
          ),
        ),
        if (_libraryExpanded) ...[
          // [教練 Agent 2026-07-28] RepaintBoundary 隔離檔案樹 — 避免整個頁面重繪
          RepaintBoundary(
            child: showFlatList
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _filteredLibraryFiles.take(50).map((mf) => buildLibraryTile(
                          context,
                          mf,
                          batchMode: _batchMode,
                          isSelected: _selectedFileIds.contains(mf.path),
                          onToggleSelect: _batchMode ? () => _toggleSelectFile(mf.path) : null,
                          assetRecord: _assetRecordsMap[mf.path],
                        )).toList(),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildLimitedFileTree(),
                  ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  /// [教練 Agent 2026-07-28] 用快取的檔案樹 — 避免每次 build 重建 18550 個節點
  List<Widget> _buildLimitedFileTree() {
    // 用 files 的 length + first/last path 做 hash，只有檔案列表改變才重建
    final hash = _libraryFiles.length.hashCode ^
        (_libraryFiles.isEmpty ? 0 : _libraryFiles.first.path.hashCode) ^
        (_libraryFiles.isEmpty ? 0 : _libraryFiles.last.path.hashCode);

    if (_fileTreeCache == null || _fileTreeCacheHash != hash) {
      // [小葵 2026-09-09] 同側欄樹——groupByRoot 保持鍵空間一致（絕對路徑）
      _fileTreeCache = buildFileTree(_libraryFiles, groupByRoot: true);
      _fileTreeCacheHash = hash;
      debugPrint('[VaultScreen] 檔案樹重建: ${_libraryFiles.length} 檔案');
    }

    return [
      buildFileTreeNodes(
        context,
        _fileTreeCache!,
        0,
        _expandedFolders,
        (p) => setState(() {
          if (_expandedFolders.contains(p)) {
            _expandedFolders.remove(p);
          } else {
            _expandedFolders.add(p);
          }
        }),
        batchMode: _batchMode,
        selectedIds: _selectedFileIds,
        onToggleSelect: _batchMode ? _toggleSelectFile : null,
        assetRecords: _assetRecordsMap,
      ),
    ];
  }

  /// [教練 Agent 2026-07-29] 六大房間計數（從 asset_index DB 記錄統計）
  Map<FileRoom, int> get _roomCounts {
    final counts = <FileRoom, int>{};
    for (final record in _assetRecordsMap.values) {
      final room = FileRoom.values.cast<FileRoom?>().firstWhere(
            (r) => r?.name == record.room,
            orElse: () => null,
          );
      if (room != null) {
        counts[room] = (counts[room] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// 搜尋過濾後的圖書館檔案
  List<ManifestFile> get _filteredLibraryFiles {
    var files = _libraryFiles;

    // [Blue 令 2026-10-17] 素材包篩選——點包=只看這包的素材（最高優先）
    if (_selectedPackId != null) {
      final pack = MaterialPoolService.instance.packs
          .where((p) => p.id == _selectedPackId)
          .firstOrNull;
      if (pack != null) {
        final ids = pack.items.map((i) => i.filePath).toSet();
        final assetIds = pack.items.map((i) => i.assetId).toSet();
        return files.where((mf) {
          if (ids.contains(mf.path)) return true;
          final record = _assetRecordsMap[mf.path];
          return record != null && assetIds.contains(record.id);
        }).toList();
      }
    }

    // [Blue 令 2026-10-17] 標籤篩選——DB tags 或 FileTagStore 命中
    if (_selectedTag != null) {
      final tag = _selectedTag!;
      final taggedPaths = _allTags
          .where((t) => t.label == tag)
          .expand((t) => t.filePaths)
          .toSet();
      files = files.where((mf) {
        if (taggedPaths.contains(mf.path)) return true;
        return (_assetRecordsMap[mf.path]?.tags ?? const []).contains(tag);
      }).toList();
    }

    // [小葵 2026-08-29] Finder 樹——資料夾篩選（優先於房間）
    if (_selectedFolderPath != null) {
      files = files.where((mf) {
        final abs = '${mf.folder}/${mf.path}';
        return abs.startsWith('$_selectedFolderPath/') ||
            mf.folder == _selectedFolderPath;
      }).toList();
    }

    // [教練 Agent 2026-07-29] 六大房間篩選
    if (_selectedRoom != null) {
      files = files.where((mf) {
        final record = _assetRecordsMap[mf.path];
        return record?.room == _selectedRoom!.name;
      }).toList();
    }

    if (_searchController.text.isEmpty) return files;

    // [小葵 2026-08-29] 聰明檢索——多關鍵詞 AND＋內容感知＋相關度排序
    // 舊：整串 query 只比檔名 contains（打「鹿角蕨 照顧」＝找不到任何檔名同含兩詞者）
    // 新：拆詞 AND 比對；命中範圍擴及 title/summary（向量索引時萃取的）；分數排序
    final terms = _searchController.text
        .toLowerCase()
        .split(RegExp(r'[\s,，、/]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return files;

    final scored = <MapEntry<ManifestFile, int>>[];
    for (final mf in files) {
      final record = _assetRecordsMap[mf.path];
      final fileName = mf.path.split('/').last.toLowerCase();
      final folder = mf.folder.toLowerCase();
      final title = record?.title?.toLowerCase() ?? '';
      final summary = record?.summary?.toLowerCase() ?? '';
      final tags = record?.tags.map((t) => t.toLowerCase()).join(' ') ?? '';

      var score = 0;
      var allHit = true;
      for (final t in terms) {
        if (fileName.contains(t)) {
          score += 10;
        } else if (title.contains(t)) {
          score += 8;
        } else if (tags.contains(t)) {
          score += 6;
        } else if (summary.contains(t)) {
          score += 4;
        } else if (folder.contains(t)) {
          score += 2;
        } else {
          allHit = false;
          break;
        }
      }
      if (allHit) scored.add(MapEntry(mf, score));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }

  Widget _buildEmptyState() {
    // [小葵 2026-10-15 Blue 報案] initState 期間 _libraryFiles 尚空會閃
    // 「資料庫是空的」——誤導（資料明明在，只是還沒載完）。
    // 修：sandbox 有根資料夾（曾匯入過）＋檔案清單仍空 → 顯示載入中，
    // 只有「真的從未匯入」才顯示空狀態。
    final hasRoots = AssetSandbox().rootPaths.isNotEmpty;
    if (hasRoots && !_libraryLoadedOnce) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 12),
            Text(
              '載入資料庫…',
              style: TierStyle.of(context, Tier.cardBody)
                  .toTextStyle()
                  .copyWith(color: BridgeDSColors.of(context).textMuted),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_motion_outlined,
              size: 64, color: BridgeDSColors.of(context).textMuted),
          const SizedBox(height: 16),
          Text(
            '資料庫是空的',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
              color: BridgeDSColors.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '記憶和知識會自動存入這裡',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
          ),
        ],
      ),
    );
  }

  // ── 列表檢視 ──────────────────────────────────────────────────

  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final entry = _results[index];
        final isSelected = _selectedEntry?.id == entry.id;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: VaultEntryCard(
            entry: entry,
            isSelected: isSelected,
            onTap: () => _selectEntry(entry),
          ),
        );
      },
    );
  }

  // ── Graph View（力導向圖譜）──────────────────────────────────

  Widget _buildGraphViewPlaceholder() {
    // 空狀態：沒有記憶條目時顯示提示
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined,
                size: 48, color: BridgeDSColors.of(context).textMuted),
            const SizedBox(height: 12),
            Text(
              '圖譜需要大腦記憶條目',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
            ),
            const SizedBox(height: 4),
            Text(
              '與夥伴對話後，記憶會自動建立關聯圖譜',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
            ),
          ],
        ),
      );
    }
    return VaultGraphView(
      onNodeTap: (node) {
        // 點擊節點 → 載入該條目到右側詳情面板
        final entry = _results.where((e) => e.id == node.id).firstOrNull;
        if (entry != null) {
          _selectEntry(entry);
        }
      },
    );
  }

  // ── 卡片牆檢視 ────────────────────────────────────────────────

  Widget _buildCardWallView() {
    // 空狀態：沒有記憶條目時顯示提示
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_view,
                size: 48, color: BridgeDSColors.of(context).textMuted),
            const SizedBox(height: 12),
            Text(
              '卡片牆需要大腦記憶條目',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
            ),
            const SizedBox(height: 4),
            Text(
              '與夥伴對話後，記憶會以卡片形式顯示在這裡',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final entry = _results[index];
        return VaultEntryCard(
          entry: entry,
          isSelected: _selectedEntry?.id == entry.id,
          onTap: () => _selectEntry(entry),
          isCardWall: true,
        );
      },
    );
  }

  // ── 右側詳情面板 ──────────────────────────────────────────────

  Widget _buildDetailPanel() {
    final entry = _selectedEntry!;
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        border: Border(
          left: BorderSide(
            color: BridgeDSColors.of(context).borderSubtle,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列
          Container(
            padding: const EdgeInsets.all(BridgeDS.spaceMD),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: BridgeDSColors.of(context).borderSubtle,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '條目詳情',
                    style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle(),
                  ),
                ),
                Semantics(
                  label: '關閉詳情',
                  button: true,
                  child: IconButton(
                    tooltip: '關閉',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _selectedEntry = null),
                  ),
                ),
              ],
            ),
          ),

          // 內容
          Expanded(
            child: _isLoadingDetail
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(BridgeDS.spaceMD),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 類型 + 日期
                        Row(
                          children: [
                            BridgeStatusTag(
                              label: entry.typeLabel,
                              type: BridgeTagType.info,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${entry.createdAt.month}/${entry.createdAt.day}',
                              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                            ),
                            const Spacer(),
                            if (entry.importance >= 4)
                              Icon(Icons.star,
                                  size: 16,
                                  color: BridgeDSColors.of(context).accentYellow),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 內容全文
                        SelectableText(
                          entry.content,
                          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(height: 1.6,
                            color: BridgeDSColors.of(context).textPrimary,),
                        ),
                        const SizedBox(height: 16),

                        // 標籤
                        if (entry.tags.isNotEmpty) ...[
                          Text('標籤',
                              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                                color: BridgeDSColors.of(context).textSecondary,)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: entry.tags.map((tag) {
                              return Chip(
                                label: Text(tag, style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // 連結
                        if (_outgoingLinks.isNotEmpty) ...[
                          Row(
                            children: [
                              Icon(Icons.link,
                                  size: 14,
                                  color: BridgeDSColors.of(context).textMuted),
                              const SizedBox(width: 6),
                              Text('連結 (${_outgoingLinks.length})',
                                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                                    color: BridgeDSColors.of(context).textSecondary,)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ..._outgoingLinks.map((link) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '→ ${link.linkText}',
                                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple,),
                                ),
                              )),
                          const SizedBox(height: 16),
                        ],

                        // Backlinks
                        if (_backlinks.isNotEmpty) ...[
                          Row(
                            children: [
                              Icon(Icons.reply,
                                  size: 14,
                                  color: BridgeDSColors.of(context).textMuted),
                              const SizedBox(width: 6),
                              Text('被引用 (${_backlinks.length})',
                                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                                    color: BridgeDSColors.of(context).textSecondary,)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ..._backlinks.map((link) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '← ${link.linkText}',
                                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentBlue,),
                                ),
                              )),
                        ],

                        // Metadata
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        _buildMetadataRow('房間', entry.room),
                        _buildMetadataRow('來源', entry.source),
                        _buildMetadataRow('存取次數', '${entry.accessCount}'),
                        _buildMetadataRow('建立時間',
                            '${entry.createdAt.month}/${entry.createdAt.day} ${entry.createdAt.hour}:${entry.createdAt.minute.toString().padLeft(2, '0')}'),
                      ],
                    ),
                  ),
          ),

          // 操作列
          Container(
            padding: const EdgeInsets.all(BridgeDS.spaceMD),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: BridgeDSColors.of(context).borderSubtle,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    // Phase 3: 送至畫布
                  },
                  icon: const Icon(Icons.send, size: 16),
                  label: Text('送至畫布', style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    // 編輯標籤
                  },
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text('編輯', style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label：',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
          ),
          Text(
            value,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
          ),
        ],
      ),
    );
  }

  // ── 批量操作列 ────────────────────────────────────────────────

  /// [教練 Agent 2026-07-28] 決策 2：批量分類操作列
  ///
  /// 選取檔案後底部出現：六房間按鈕（每個帶 Tooltip 顯示 definition）+ 全選 + 取消
  Widget _buildBatchActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BridgeDS.spaceMD,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceElevated,
        border: Border(
          top: BorderSide(
            color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 選取計數
          Text(
            '已選 ${_selectedFileIds.length} 個檔案',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
              color: BridgeDSColors.of(context).accentPurple,),
          ),
          const SizedBox(width: 12),

          // 全選按鈕
          if (_libraryFiles.isNotEmpty)
            TextButton.icon(
              onPressed: _toggleSelectAll,
              icon: Icon(
                _selectedFileIds.length == _libraryFiles.length
                    ? Icons.deselect
                    : Icons.select_all,
                size: 16,
              ),
              label: Text(
                _selectedFileIds.length == _libraryFiles.length ? '取消全選' : '全選',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
              ),
            ),

          const SizedBox(width: 8),

          // 分隔線
          Container(
            width: 1,
            height: 24,
            color: BridgeDSColors.of(context).borderSubtle,
          ),
          const SizedBox(width: 8),

          // [Blue 令 2026-10-17] 標籤系統——自由文字標籤（取代六大房間）
          Expanded(
            child: Row(
              children: [
                // 新標籤輸入框
                SizedBox(
                  width: 200,
                  height: 34,
                  child: TextField(
                    controller: _tagInputController,
                    enabled: _selectedFileIds.isNotEmpty,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
                    decoration: InputDecoration(
                      hintText: _selectedFileIds.isEmpty
                          ? '先點選檔案…'
                          : '輸入新標籤，Enter 套用',
                      hintStyle: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(
                              color: BridgeDSColors.of(context).textMuted),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: BridgeDSColors.of(context).borderSubtle),
                      ),
                    ),
                    onSubmitted: _applyTag,
                  ),
                ),
                const SizedBox(width: 8),
                // 既有標籤 chips（一鍵套用）
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final tag in _allTags.take(12))
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text(
                                '#${tag.label}（${tag.filePaths.length}）',
                                style: TierStyle.of(context, Tier.cardCaption)
                                    .toTextStyle()
                                    .copyWith(
                                        color: _selectedFileIds.isEmpty
                                            ? BridgeDSColors.of(context)
                                                .textMuted
                                            : BridgeDSColors.of(context)
                                                .accentPurple),
                              ),
                              backgroundColor:
                                  BridgeDSColors.of(context).surfaceHover,
                              side: BorderSide(
                                color: _selectedFileIds.isEmpty
                                    ? BridgeDSColors.of(context).borderSubtle
                                    : BridgeDSColors.of(context)
                                        .accentPurple
                                        .withValues(alpha: 0.4),
                              ),
                              onPressed: _selectedFileIds.isEmpty
                                  ? null
                                  : () => _applyTag(tag.label),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 取消按鈕
          TextButton(
            onPressed: _toggleBatchMode,
            child: Text('取消', style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
          ),
        ],
      ),
    );
  }

  // ── 嵌入進度條（固定在向量資料庫頁面底部）──────────────────

  /// [教練 Agent 2026-07-31] 嵌入進度條 — 固定位置，不在浮動欄位
  /// 快速嵌入用綠色，深度嵌入用藍色
  Widget _buildEmbeddingProgressBar() {
    // [教練 Agent 2026-08-02] 進度條始終顯示——不管有沒有在嵌入
    final isEmbedding = _quickEmbeddingRunning || _visionEmbeddingRunning || _isOneClickEmbedding;
    final isQuick = _quickEmbeddingRunning;
    final progress = _quickProgress;
    final visionProgress = _visionProgress;

    // 從 DB 統計算進度
    final fraction = _totalCount > 0 ? _indexedCount / _totalCount : 0.0;
    final percent = (fraction * 100).toStringAsFixed(1);

    // 決定顯示模式
    String label;
    String countText;
    Color color;

    if (isEmbedding && isQuick && progress != null) {
      // 快速嵌入中
      color = BridgeDSColors.of(context).accentGreen;
      label = '嵌入中：${progress.currentFile ?? ""}';
      countText = '${progress.done}/${progress.total}';
    } else if (isEmbedding && _visionEmbeddingRunning && visionProgress != null) {
      // 深度嵌入中
      color = BridgeDSColors.of(context).accentBlue;
      label = visionProgress.message;
      countText = '${visionProgress.current}/${visionProgress.total}';
    } else if (isEmbedding && _isOneClickEmbedding) {
      // 一鍵嵌入中但沒有細部進度
      color = BridgeDSColors.of(context).accentGreen;
      label = '一鍵嵌入進行中...';
      countText = '$_indexedCount/$_totalCount';
    } else if (_pendingCount > 0) {
      // 沒在嵌入，但有待處理
      color = BridgeDSColors.of(context).accentYellow;
      label = '$_pendingCount 個檔案待嵌入';
      countText = '$_indexedCount/$_totalCount ($percent%)';
    } else if (_totalCount == 0) {
      // 還沒載入或 DB 是空的——載入中用轉圈，載入完（DB 空或全 missing）給綠燈
      color = BridgeDSColors.of(context).textMuted;
      label = _pendingCount > 0 ? '$_pendingCount 個檔案待嵌入' : '載入嵌入狀態...';
      countText = '';
    } else if (_totalCount > 0 && _pendingCount == 0 && _indexedCount + _skippedCount + _errorCount >= _totalCount) {
      // [Blue 報案 2026-10-16] 無待嵌入＝完成——跳過/錯誤的也算「處理完」，
      // 不再落入僵屍「載入中」。改顯示綠燈（取代原本 return shrink 的完全靜默——
      // 使用者需要一眼判斷「結束了、一切正常」）
      color = BridgeDSColors.of(context).accentGreen;
      label = '嵌入完成 ✓ 全部就緒';
      countText = '$_indexedCount 筆';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceMD, vertical: 6),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surface,
          border: Border(
            top: BorderSide(
              color: color.withValues(alpha: 0.3), width: 1),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 13, color: color),
            const SizedBox(width: 8),
            Text(label,
              style: TierStyle.of(context, Tier.cardBody)
                  .toTextStyle()
                  .copyWith(color: color)),
            const SizedBox(width: 8),
            Text(countText,
              style: TierStyle.of(context, Tier.cardBody)
                  .toTextStyle()
                  .copyWith(color: color, fontWeight: FontWeight.w600)),
            if (_skippedCount > 0) ...[
              const SizedBox(width: 8),
              Text('（$_skippedCount 跳過）',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: BridgeDSColors.of(context).textMuted)),
            ],
          ],
        ),
      );
    } else if (_totalCount > 0 && _indexedCount == _totalCount) {
      // 全部完成
      // [小葵 2026-09-09 Blue 令] 嵌入完成後綠字+進度條收起
      // ——只剩乾淨的狀態列（無嵌入資訊）
      return const SizedBox.shrink();
      // color = BridgeDSColors.of(context).accentGreen;
      // label = '嵌入完成';
      // countText = '$_indexedCount 筆';
    } else {
      // 初始狀態（還沒載入統計）
      color = BridgeDSColors.of(context).textMuted;
      label = '載入嵌入狀態...';
      countText = '';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceMD, vertical: 6),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        border: Border(
          top: BorderSide(color: color.withValues(alpha: 0.3), width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 文字行：狀態 + 檔名 + 計數
          Row(
            children: [
              if (isEmbedding)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              else
                Icon(
                  _pendingCount > 0 ? Icons.hourglass_top : Icons.check_circle_outline,
                  size: 12,
                  color: color,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: color),
                ),
              ),
              if (_skippedCount > 0) ...[
                Text(
                  '$_skippedCount 已跳過',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted),
                ),
                const SizedBox(width: 8),
              ],
              if (_errorCount > 0) ...[
                Text(
                  '$_errorCount 錯誤',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentRed),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                countText,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                  color: color,),
              ),
              // [教練 Agent 2026-08-02] 當有待處理檔案時，顯示「開始嵌入」按鈕
              if (_pendingCount > 0 && !isEmbedding) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: (_quickEmbeddingRunning || _visionEmbeddingRunning)
                      ? null
                      : _startOneClickEmbedding,
                  icon: const Icon(Icons.play_arrow, size: 14),
                  label: Text('開始嵌入', style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    backgroundColor: color.withValues(alpha: 0.1),
                    foregroundColor: color,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // 進度條
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: isEmbedding && progress != null
                  ? progress.fraction
                  : (isEmbedding && _visionEmbeddingRunning && visionProgress != null
                      ? visionProgress.fraction
                      : fraction),
              minHeight: 4,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  // ── 底部狀態列 ────────────────────────────────────────────────

  Widget _buildStatusBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        border: Border(
          top: BorderSide(
            color: BridgeDSColors.of(context).borderSubtle,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '總共 $_totalEntries 條目',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
          ),
          const SizedBox(width: 16),
          Text(
            '顯示 ${_results.length} 筆',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
          ),
          if (_selectedTags.isNotEmpty) ...[
            const SizedBox(width: 16),
            Text(
              '篩選：${_selectedTags.join(", ")}',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple,),
            ),
          ],
          if (_selectedRoom != null) ...[
            const SizedBox(width: 16),
            Text(
              '${_selectedRoom!.icon} ${_selectedRoom!.label}（${_filteredLibraryFiles.length} 個檔案）',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: Color(_selectedRoom!.colorValue),),
            ),
          ],
        ],
      ),
    );
  }
}

