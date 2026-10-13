// project_door_grid.dart
// [W3.5 2026-10-09 小葵·第二刀 UX 補完] 專案頁下區——畫布專案卡
//
// Blue 拍板（2026-10-09 W3.5 令）：
// - 下區＝「我做的東西——被動容器」：畫布專案卡按產生順序橫排
// - 含排程的專案 → 卡底橙徽章「📅 含排程 ×N」；無排程 → 灰虛線「無排程」
// - 最後一張「＋ 新增專案門」虛線入口
// - 「顯示全部」按鈕：往上拉出全部專案卡（wrap 換行）——無時間軸
// - 取代舊 kanban 三欄（等待中/進行中/已完成）——舊版退役
//
// 資料源：CanvasStore.getAll()（畫布 metadata：節點數從 canvas_nodes 統計）
// ＋schedule 節點掃描（W3 同款）算每個專案的排程數。

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/project_door_store.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/services/canvas_store.dart';

import '../../../theme/bridge_design_system.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 專案卡視圖模型
class ProjectCardVM {
  final String canvasId;
  final String title;
  final DateTime updatedAt;
  final int nodeCount;
  final int scheduleCount;

  const ProjectCardVM({
    required this.canvasId,
    required this.title,
    required this.updatedAt,
    required this.nodeCount,
    required this.scheduleCount,
  });
}

/// 下區「🎨 畫布專案卡」——被動容器，按產生順序排列。
class ProjectDoorGrid extends StatefulWidget {
  /// 點專案卡 → 開畫布
  final void Function(String canvasId)? onOpenCanvas;

  /// 點「＋ 新增專案門」
  final VoidCallback? onCreateProject;

  const ProjectDoorGrid({super.key, this.onOpenCanvas, this.onCreateProject});

  @override
  State<ProjectDoorGrid> createState() => _ProjectDoorGridState();
}

class _ProjectDoorGridState extends State<ProjectDoorGrid> {
  List<ProjectCardVM> _cards = [];
  bool _showAll = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cards = <ProjectCardVM>[];
    try {
      final graph = EntityGraphService.withSqliteCanvasStore(
        memoryStore: MemoryStore(),
        doorStore: ProjectDoorStore(),
        assetStore: DigitalAssetRegistryStore(),
      );
      final nodes = await graph.getCanvasNodes(canvasId: null);
      // 依 canvas 分組統計節點數＋schedule 數
      final byCanvas = <String, List<dynamic>>{};
      for (final e in nodes) {
        final cid = e.props.canvasId;
        if (cid == null || cid.isEmpty) continue;
        byCanvas.putIfAbsent(cid, () => []).add(e);
      }
      // 畫布清單（CanvasStore.getAll 走 graph 的 store 層——直接用 sqlite）
      final canvases = await _allCanvases();
      for (final c in canvases) {
        final cn = byCanvas[c.$1] ?? const [];
        cards.add(ProjectCardVM(
          canvasId: c.$1,
          title: c.$2.isEmpty ? '（未命名）' : c.$2,
          updatedAt: c.$3,
          nodeCount: cn.length,
          scheduleCount: cn
              .where((e) => e.props.nodeType == WorkflowNodeType.schedule)
              .length,
        ));
      }
      // 按產生順序（createdAt）——payload 帶的是 updatedAt；sort 用 updatedAt 近似
      cards.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      // fail-quiet
    }
    if (mounted) setState(() { _cards = cards; _loaded = true; });
  }

  /// 直接讀 canvases.json 拿畫布清單（id, title, updatedAt）——輕量
  Future<List<(String, String, DateTime)>> _allCanvases() async {
    try {
      final canvases = await CanvasStore.getAll();
      return [
        for (final c in canvases)
          (c.id, c.title, c.updatedAt)
      ];
    } catch (_) {
      return const [];
    }
  }

  Widget _showAllToggle(BridgeDSColors ds) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('顯示全部',
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: ds.accentBlue)),
          Icon(_showAll ? Icons.expand_less : Icons.expand_more,
              size: 16, color: ds.accentBlue),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    if (!_loaded) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.dashboard_outlined, size: 18, color: ds.accentYellow),
          const SizedBox(width: 8),
          Text('🎨 畫布專案',
              style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
          const SizedBox(width: 10),
          Text('我做的東西 — 被動容器 · 點擊開啟專案門',
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: ds.textMuted)),
          const Spacer(),
          if (_cards.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _showAll = !_showAll),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: ds.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ds.borderSubtle),
                ),
                child: _showAllToggle(ds),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        if (_showAll)
          _buildWrap(ds)
        else
          SizedBox(
            height: 118,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in _cards) _buildCard(ds, c),
              ],
            ),
          ),
      ],
    );
  }


  Widget _buildWrap(BridgeDSColors ds) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final c in _cards) _buildCard(ds, c, fixedWidth: true),
      ],
    );
  }

  Widget _buildCard(BridgeDSColors ds, ProjectCardVM c, {bool fixedWidth = false}) {
    final hasSched = c.scheduleCount > 0;
    return GestureDetector(
      onTap: () => widget.onOpenCanvas?.call(c.canvasId),
      child: Container(
        width: fixedWidth ? 218 : 218,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ds.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: hasSched
                ? ds.accentYellow.withValues(alpha: .45)
                : ds.borderDefault,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.palette_outlined, size: 15, color: ds.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(c.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TierStyle.of(context, Tier.listItemTitle)
                        .toTextStyle()),
              ),
            ]),
            const SizedBox(height: 6),
            Text('${c.nodeCount} 節點 · ${_relTime(c.updatedAt)}',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: ds.textTertiary)),
            const Spacer(),
            // 排程徽章：橙「📅 含排程 ×N」/ 灰虛線「無排程」
            if (hasSched)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: ds.accentYellow.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: ds.accentYellow.withValues(alpha: .4)),
                ),
                child: Text('📅 含排程 ×${c.scheduleCount}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ds.accentYellow)),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: ds.textMuted.withValues(alpha: .4),
                      style: BorderStyle.solid),
                ),
                child: Text('無排程',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ds.textMuted)),
              ),
          ],
        ),
      ),
    );
  }


  static String _relTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inDays == 0) return '今天';
    if (d.inDays == 1) return '昨天';
    if (d.inDays < 7) return '${d.inDays} 天前';
    if (d.inDays < 30) return '${(d.inDays / 7).floor()} 週前';
    return '${(d.inDays / 30).floor()} 個月前';
  }
}
