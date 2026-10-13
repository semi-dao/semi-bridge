// task_list_sidebar.dart
// [W3.5 2026-10-09] 專案頁左欄——任務清單
//
// Blue 拍板圖（2026-10-08 定案）：
// - 上半 ⏰ 排程任務（排隊中）：每項 icon + 名稱 + 即時倒數（每分鐘重算）；暫停標 ⏸
// - 下半 🎨 專案任務門：icon + 名稱 + ⏰×N 標（含排程數）/節點數
// - 點項目 → 開該任詳細設定/專案畫布（W4 擴充點）

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/project_door_store.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/services/semicanvas/schedule_engine.dart';
import 'package:bridge_app/services/semicanvas/schedule_run_store.dart';
import 'package:bridge_app/services/canvas_store.dart';

import '../../../theme/bridge_design_system.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 左欄「任務清單」——排程任務（上）＋專案任務門（下）
class TaskListSidebar extends StatefulWidget {
  final void Function(String canvasId)? onOpenCanvas;
  const TaskListSidebar({super.key, this.onOpenCanvas});

  @override
  State<TaskListSidebar> createState() => _TaskListSidebarState();
}

class _TaskListSidebarState extends State<TaskListSidebar> {
  List<_SchedItem> _sched = [];
  List<_DoorItem> _doors = [];
  String? _selectedCanvasId;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {}); // 倒數重算
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final sched = <_SchedItem>[];
    final doors = <_DoorItem>[];
    try {
      final graph = EntityGraphService.withSqliteCanvasStore(
        memoryStore: MemoryStore(),
        doorStore: ProjectDoorStore(),
        assetStore: DigitalAssetRegistryStore(),
      );
      final nodes = await graph.getCanvasNodes(canvasId: null);
      final runs = await ScheduleRunStore.instance.allRuns();
      for (final e in nodes) {
        if (e.props.nodeType != WorkflowNodeType.schedule) continue;
        final params = e.props.params;
        final next = ScheduleEngine.calcNextFirePublic(params, DateTime.now());
        final paused = params['paused'] == true;
        final title = (params['title'] as String?) ??
            (params['label'] as String?) ??
            e.entity.title;
        final lastRun = runs
            .where((r) => r.jobId == e.entity.id)
            .fold<ScheduleRunRecord?>(null, (acc, r) => r);
        sched.add(_SchedItem(
          nodeId: e.entity.id,
          title: title,
          canvasId: e.props.canvasId ?? '',
          next: next,
          paused: paused,
          failed: lastRun != null && !lastRun.success,
        ));
      }
      sched.sort((a, b) {
        if (a.paused != b.paused) return a.paused ? 1 : -1;
        final an = a.next, bn = b.next;
        if (an == null) return 1;
        if (bn == null) return -1;
        return an.compareTo(bn);
      });

      // 專案門（畫布）＋排程數
      final schedByCanvas = <String, int>{};
      for (final s in sched) {
        schedByCanvas[s.canvasId] = (schedByCanvas[s.canvasId] ?? 0) + 1;
      }
      final nodeByCanvas = <String, int>{};
      for (final e in nodes) {
        final cid = e.props.canvasId;
        if (cid != null && cid.isNotEmpty) {
          nodeByCanvas[cid] = (nodeByCanvas[cid] ?? 0) + 1;
        }
      }
      final canvases = await CanvasStore.getAll();
      for (final c in canvases) {
        doors.add(_DoorItem(
          canvasId: c.id,
          title: c.title.isEmpty ? '（未命名）' : c.title,
          nodeCount: nodeByCanvas[c.id] ?? 0,
          scheduleCount: schedByCanvas[c.id] ?? 0,
        ));
      }
      doors.sort((a, b) => b.nodeCount.compareTo(a.nodeCount));
    } catch (_) {}
    if (mounted) setState(() { _sched = sched; _doors = doors; });
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return Container(
      width: 250,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('任務清單',
              style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
          const SizedBox(height: 2),
          Text('Tasks 明細 + 專案 · 點擊開啟詳細設定',
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: ds.textMuted)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                _section(ds, '排程任務 · 排隊中', Icons.schedule_outlined, ds.accentPurple),
                const SizedBox(height: 4),
                if (_sched.isEmpty)
                  _empty(ds, '還沒有排程任務')
                else
                  for (final s in _sched) _schedRow(ds, s),
                const SizedBox(height: 14),
                _section(ds, '專案任務 · 門', Icons.door_front_door_outlined, ds.accentYellow),
                const SizedBox(height: 4),
                if (_doors.isEmpty)
                  _empty(ds, '還沒有專案')
                else
                  for (final d in _doors) _doorRow(ds, d),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BridgeDSColors ds, String label, IconData icon, Color c) =>
      Row(children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: ds.textTertiary)),
      ]);

  Widget _empty(BridgeDSColors ds, String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Text(msg,
            style: TextStyle(fontSize: 12, color: ds.textMuted)),
      );

  Widget _schedRow(BridgeDSColors ds, _SchedItem s) {
    final selected = s.canvasId == _selectedCanvasId;
    final countdown = (s.paused || s.next == null)
        ? (s.paused ? '⏸ 已暫停' : '—')
        : _fmt(s.next!.difference(DateTime.now()));
    return GestureDetector(
      onTap: () {
        setState(() => _selectedCanvasId = s.canvasId);
        if (s.canvasId.isNotEmpty) widget.onOpenCanvas?.call(s.canvasId);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? ds.accentBlue.withValues(alpha: .12) : null,
          borderRadius: BorderRadius.circular(7),
          border: selected ? Border.all(color: ds.accentBlue.withValues(alpha: .4)) : null,
        ),
        child: Row(children: [
          Icon(_schedIcon(s.title), size: 13, color: ds.textSecondary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(s.title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: s.paused ? ds.textMuted : ds.textPrimary)),
          ),
          Text(countdown,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: s.paused
                      ? ds.textMuted
                      : (s.failed
                          ? ds.accentRed
                          : ds.accentGreen))),
        ]),
      ),
    );
  }

  Widget _doorRow(BridgeDSColors ds, _DoorItem d) {
    final selected = d.canvasId == _selectedCanvasId;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedCanvasId = d.canvasId);
        widget.onOpenCanvas?.call(d.canvasId);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? ds.accentBlue.withValues(alpha: .12) : null,
          borderRadius: BorderRadius.circular(7),
          border: selected ? Border.all(color: ds.accentBlue.withValues(alpha: .4)) : null,
        ),
        child: Row(children: [
          Icon(Icons.palette_outlined, size: 13, color: ds.textSecondary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(d.title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: ds.textPrimary)),
          ),
          if (d.scheduleCount > 0)
            Text('⏰×${d.scheduleCount}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ds.accentYellow))
          else
            Text('${d.nodeCount} 節點',
                style: TextStyle(fontSize: 12, color: ds.textMuted)),
        ]),
      ),
    );
  }

  static IconData _schedIcon(String title) {
    if (title.contains('咖啡')) return Icons.local_cafe_outlined;
    if (title.contains('體力')) return Icons.bolt_outlined;
    if (title.contains('記憶')) return Icons.psychology_outlined;
    if (title.contains('IG') || title.contains('靈感')) return Icons.image_outlined;
    if (title.contains('農場')) return Icons.grass_outlined;
    return Icons.schedule_outlined;
  }

  static String _fmt(Duration d) {
    if (d.isNegative) return '觸發中';
    if (d.inDays >= 1) return '${d.inDays}天';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }
}

class _SchedItem {
  final String nodeId;
  final String title;
  final String canvasId;
  final DateTime? next;
  final bool paused;
  final bool failed;
  const _SchedItem({
    required this.nodeId,
    required this.title,
    required this.canvasId,
    this.next,
    this.paused = false,
    this.failed = false,
  });
}

class _DoorItem {
  final String canvasId;
  final String title;
  final int nodeCount;
  final int scheduleCount;
  const _DoorItem({
    required this.canvasId,
    required this.title,
    required this.nodeCount,
    required this.scheduleCount,
  });
}
