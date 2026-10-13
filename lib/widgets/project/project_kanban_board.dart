// project_kanban_board.dart
// D11-8: 專案看板視圖 — 將專案以卡片式看板呈現
//
// 三欄：進行中 (active) | 等待中 (waiting) | 已完成 (completed)
// 卡片顯示：標題、進度條、狀態徽章、最後更新時間、畫布連結圖示
// 點擊有畫布的卡片 → onOpenCanvas(canvasId)

import 'package:flutter/material.dart';

import '../../models/canvas/canvas_metadata.dart';
import '../../models/project_door.dart';
import '../../services/canvas_store.dart';
import '../../services/project_door_store.dart';
import '../../services/schedule_registry.dart';
import '../../models/schedule_card.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

class ProjectKanbanBoard extends StatefulWidget {
  final void Function(String canvasId)? onOpenCanvas;
  const ProjectKanbanBoard({super.key, this.onOpenCanvas});

  @override
  State<ProjectKanbanBoard> createState() => _ProjectKanbanBoardState();
}

class _ProjectKanbanBoardState extends State<ProjectKanbanBoard> {
  List<ProjectDoor> _doors = [];
  List<CanvasMetadata> _canvases = [];
  bool _isLoading = true;
  String? _error;

  // [H4 2026-10-08] 排程任務卡（Hermes 28 cron 重現）
  List<ScheduleCard> _schedules = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // [H4] 排程卡載入（fail-quiet——Hermes 資料不在也不阻擋看板）
    ScheduleRegistry.instance.loadAll().then((cards) {
      if (mounted) setState(() => _schedules = cards);
    });
    try {
      final doors = await ProjectDoorStore().loadAll();
      final canvases = await CanvasStore.getAll();
      // 只顯示有對應畫布的門（過濾孤兒門）
      final canvasDoorIds = canvases.map((c) => c.projectDoorId).toSet();
      final validDoors = doors.where((d) => canvasDoorIds.contains(d.id)).toList();
      if (!mounted) return;
      setState(() {
        _doors = validDoors;
        _canvases = canvases;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 查找此門對應的畫布
  CanvasMetadata? _canvasForDoor(ProjectDoor door) {
    for (final c in _canvases) {
      if (c.projectDoorId == door.id) return c;
    }
    return null;
  }

  /// 根據 kanbanStatus 分組
  Map<String, List<ProjectDoor>> _groupDoors() {
    final active = <ProjectDoor>[];
    final waiting = <ProjectDoor>[];
    final completed = <ProjectDoor>[];

    for (final door in _doors) {
      switch (door.kanbanStatus) {
        case ProjectDoor.statusCompleted:
          completed.add(door);
          break;
        case ProjectDoor.statusWaiting:
          waiting.add(door);
          break;
        default:
          active.add(door);
      }
    }

    return {
      ProjectDoor.statusActive: active,
      ProjectDoor.statusWaiting: waiting,
      ProjectDoor.statusCompleted: completed,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: BridgeDSColors.of(context).canvas,
        child: Center(
          child: CircularProgressIndicator(color: BridgeDSColors.of(context).accentBlue),
        ),
      );
    }

    if (_error != null) {
      return Container(
        color: BridgeDSColors.of(context).canvas,
        child: Center(
          child: Text(
            '載入失敗：$_error',
            style: BridgeDSColors.of(context).caption.copyWith(color: BridgeDSColors.of(context).accentRed),
          ),
        ),
      );
    }

    if (_doors.isEmpty && _schedules.isEmpty) {
      return _buildEmptyState();
    }

    final groups = _groupDoors();

    return Container(
      color: BridgeDSColors.of(context).canvas,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(BridgeDS.spaceLG),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildColumn(
              title: '進行中',
              status: ProjectDoor.statusActive,
              doors: groups[ProjectDoor.statusActive]!,
              accentColor: BridgeDSColors.of(context).accentGreen,
            ),
            SizedBox(width: BridgeDS.spaceMD),
            _buildColumn(
              title: '等待中',
              status: ProjectDoor.statusWaiting,
              doors: groups[ProjectDoor.statusWaiting]!,
              accentColor: BridgeDSColors.of(context).accentYellow,
            ),
            SizedBox(width: BridgeDS.spaceMD),
            _buildColumn(
              title: '已完成',
              status: ProjectDoor.statusCompleted,
              doors: groups[ProjectDoor.statusCompleted]!,
              accentColor: BridgeDSColors.of(context).accentBlue,
            ),
            SizedBox(width: BridgeDS.spaceMD),
            // [H4 2026-10-08] 排程欄——生活卡在上（有溫度），工作卡在
            // 下（可折疊）。28 個 Hermes cron 重現為任務卡。
            _buildScheduleColumn(),
          ],
        ),
      ),
    );
  }

  // ── [H4] 排程欄 ─────────────────────────────────────────

  Widget _buildScheduleColumn() {
    final ds = BridgeDSColors.of(context);
    final life = _schedules
        .where((c) => c.warmth == ScheduleWarmth.life)
        .toList(growable: false);
    final work = _schedules
        .where((c) => c.warmth != ScheduleWarmth.life)
        .toList(growable: false);
    return Container(
      width: 300,
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: ds.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ds.borderSubtle),
      ),
      child: SingleChildScrollView(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_outlined, size: 16, color: ds.accentPurple),
              const SizedBox(width: 6),
              Text('排程',
                  style: TierStyle.of(context, Tier.cardHeroTitle)
                      .toTextStyle()),
              const SizedBox(width: 8),
              Text('${_schedules.length} 個約定',
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: ds.textMuted)),
            ],
          ),
          const SizedBox(height: BridgeDS.spaceMD),
          // 生活卡——有溫度：暖色卡片、心意一行、下次相見
          if (life.isNotEmpty) ...[
            Text('生活 · 心意',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: ds.accentPurple, fontWeight: FontWeight.w700)),
            const SizedBox(height: BridgeDS.spaceSM),
            for (final c in life) _buildLifeCard(c),
            const SizedBox(height: BridgeDS.spaceMD),
          ],
          // 工作卡——看排程：緊湊列表
          if (work.isNotEmpty) ...[
            Text('工作 · 維運',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: ds.textMuted, fontWeight: FontWeight.w700)),
            const SizedBox(height: BridgeDS.spaceSM),
            for (final c in work.take(8)) _buildWorkRow(c),
            if (work.length > 8)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('…還有 ${work.length - 8} 個',
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(color: ds.textMuted)),
              ),
          ],
        ],
      ),
      ),
    );
  }

  /// 生活卡——Blue：「不是冷冰冰數據與完成燈號」
  Widget _buildLifeCard(ScheduleCard c) {
    final ds = BridgeDSColors.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: BridgeDS.spaceSM),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ds.accentPurple.withValues(alpha: 0.10),
            ds.accentMiro.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ds.accentPurple.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.listItemTitle)
                  .toTextStyle()
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          // 心意一行——這是溫度所在
          Text(c.warmLine ?? '',
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: ds.textSecondary, height: 1.4)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.favorite_outline,
                  size: 12, color: ds.accentPurple),
              const SizedBox(width: 4),
              Text(_nextRunText(c),
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: ds.accentPurple)),
            ],
          ),
        ],
      ),
    );
  }

  /// 工作卡——一行一個：名稱＋時間，冷靜有效率
  Widget _buildWorkRow(ScheduleCard c) {
    final ds = BridgeDSColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: ds.textQuaternary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(c.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TierStyle.of(context, Tier.listItemMeta).toTextStyle()),
          ),
          Text(c.humanSchedule,
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: ds.textMuted)),
        ],
      ),
    );
  }

  String _nextRunText(ScheduleCard c) {
    final n = c.nextRun;
    if (n == null) {
      final h = c.humanSchedule;
      return h.contains('null') ? '已排定' : h;
    }
    final d = n.difference(DateTime.now());
    if (d.inMinutes < 60) return '${d.inMinutes} 分鐘後';
    if (d.inHours < 24) return '${d.inHours} 小時後';
    return '${d.inDays} 天後';
  }

  // ── 空狀態 ──────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Container(
      color: BridgeDSColors.of(context).canvas,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.view_kanban_outlined,
              size: 64,
              color: BridgeDSColors.of(context).textMuted,
            ),
            SizedBox(height: BridgeDS.spaceMD),
            Text(
              '尚無專案',
              style: BridgeDSColors.of(context).headingM.copyWith(color: BridgeDSColors.of(context).textSecondary),
            ),
            SizedBox(height: BridgeDS.spaceSM),
            Text(
              '在畫布中存檔後，專案會自動出現在這裡',
              style: BridgeDSColors.of(context).caption.copyWith(color: BridgeDSColors.of(context).textMuted),
            ),
          ],
        ),
      ),
    );
  }

  // ── 看板欄 ──────────────────────────────────────────────

  Widget _buildColumn({
    required String title,
    required String status,
    required List<ProjectDoor> doors,
    required Color accentColor,
  }) {
    return SizedBox(
      width: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 欄標題
          Padding(
            padding: const EdgeInsets.only(
              left: BridgeDS.spaceSM,
              bottom: BridgeDS.spaceMD,
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: BridgeDS.spaceSM),
                Text(
                  title,
                  style: BridgeDSColors.of(context).headingS.copyWith(color: BridgeDSColors.of(context).textPrimary),
                ),
                SizedBox(width: BridgeDS.spaceSM),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(context).surfaceElevated,
                    borderRadius: BorderRadius.circular(BridgeDS.roundPill),
                  ),
                  child: Text(
                    '${doors.length}',
                    style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textTertiary),
                  ),
                ),
              ],
            ),
          ),
          // 卡片列表
          Expanded(
            child: doors.isEmpty
                ? _buildEmptyColumn()
                : ListView.separated(
                    itemCount: doors.length,
                    separatorBuilder: (_, _) =>
                        SizedBox(height: BridgeDS.spaceSM),
                    itemBuilder: (context, index) =>
                        _buildCard(doors[index], accentColor),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyColumn() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(
          color: BridgeDSColors.of(context).borderSubtle,
          style: BorderStyle.solid,
        ),
      ),
      child: Center(
        child: Text(
          '—',
          style: BridgeDSColors.of(context).caption.copyWith(color: BridgeDSColors.of(context).textMuted),
        ),
      ),
    );
  }

  // ── 專案卡片 ────────────────────────────────────────────

  Future<void> _renameDoor(ProjectDoor door) async {
    final controller = TextEditingController(text: door.title);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(context).surfaceElevated,
        title: Text('改名', style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
          decoration: InputDecoration(
            filled: true,
            fillColor: BridgeDSColors.of(context).canvas,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: BridgeDSColors.of(context).borderSubtle),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: BridgeDSColors.of(context).textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text('確定', style: TextStyle(color: BridgeDSColors.of(context).accentGreen)),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == door.title) return;

    final doorStore = ProjectDoorStore();
    final updated = door.copyWith(title: newName, updatedAt: DateTime.now());
    await doorStore.save(updated);

    // 同步更新對應的 CanvasMetadata 標題
    final canvases = await CanvasStore.getAll();
    final canvas = canvases.where((c) => c.projectDoorId == door.id).firstOrNull;
    if (canvas != null) {
      await CanvasStore.save(canvas.copyWith(title: newName));
    }

    setState(() {});
  }

  Widget _buildCard(ProjectDoor door, Color accentColor) {
    final canvas = _canvasForDoor(door);
    final hasCanvas = canvas != null;
    final progress = door.flowProgress;

    return MouseRegion(
      cursor: hasCanvas
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: _HoverCard(
        accentColor: accentColor,
        onTap: hasCanvas
            ? () => widget.onOpenCanvas?.call(canvas.id)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(BridgeDS.spaceMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 標題列
              Row(
                children: [
                  Expanded(
                    child: Text(
                      door.title,
                      style: BridgeDSColors.of(context).bodyTight.copyWith(
                        color: BridgeDSColors.of(context).textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasCanvas) ...[
                    SizedBox(width: BridgeDS.spaceSM),
                    Tooltip(
                      message: '畫布：${canvas.title}',
                      child: Text('🎨', style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
                    ),
                  ],
                  // 改名按鈕
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      icon: Icon(Icons.edit_outlined, color: BridgeDSColors.of(context).textTertiary),
                      tooltip: '改名',
                      onPressed: () => _renameDoor(door),
                    ),
                  ),
                ],
              ),
              SizedBox(height: BridgeDS.spaceSM),
              // 進度條
              if (door.totalFlowCount > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(BridgeDS.roundPill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: BridgeDSColors.of(context).surfaceElevated,
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '${door.completedFlowCount} / ${door.totalFlowCount} 步驟',
                  style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textTertiary),
                ),
              ] else
                Text(
                  '無流程步驟',
                  style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textMuted),
                ),
              SizedBox(height: BridgeDS.spaceSM),
              // 底部：狀態徽章 + 更新時間
              Row(
                children: [
                  _buildStatusBadge(door.status, accentColor),
                  Spacer(),
                  Text(
                    _formatTime(door.updatedAt),
                    style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, Color accentColor) {
    final label = switch (status) {
      ProjectDoor.statusActive => '進行中',
      ProjectDoor.statusWaiting => '等待中',
      ProjectDoor.statusCompleted => '已完成',
      ProjectDoor.statusIntake => '草稿',
      _ => status,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: BridgeDSColors.of(context).small.copyWith(
          color: accentColor,
          fontSize: 14,
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return '剛剛';
    if (diff.inHours < 1) return '${diff.inMinutes} 分鐘前';
    if (diff.inDays < 1) return '${diff.inHours} 小時前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day}';
  }
}

// ── 帶 hover 效果的卡片 ──────────────────────────────────

class _HoverCard extends StatefulWidget {
  final Color accentColor;
  final VoidCallback? onTap;
  final Widget child;

  _HoverCard({
    required this.accentColor,
    required this.onTap,
    required this.child,
  });

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: BridgeDS.durationFast,
        decoration: BoxDecoration(
          color: _isHovered ? BridgeDSColors.of(context).surfaceHover : BridgeDSColors.of(context).surface,
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
          border: Border.all(
            color: _isHovered
                ? widget.accentColor.withValues(alpha: 0.4)
                : BridgeDSColors.of(context).borderSubtle,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
