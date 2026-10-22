// task_delivery_card.dart
// [隊友訊息流 第 1 刀 C4 2026-09-08]
// 交付卡——TaskSession 完成時的交付訊息渲染。設計稿 §5：
// ✅ 完成 + 產出縮圖列（Deliverable 點開即看）+ 查看畫布
// awaitingReview 態：頂部黃條「需要你的判斷」確認（○ 確認 / △ 修改 / ✕ 取消）
//
// C4 範圍：交付卡本體。Deliverable 縮圖列讀 TaskSession.deliverables
// （C2 的 runner 已收集；本卡從 dispatcher/store 讀即時狀態）。

import 'package:flutter/material.dart';
import 'package:bridge_app/models/conversation.dart';
import 'package:bridge_app/services/tasks/task_dispatcher.dart';
import 'package:bridge_app/services/tasks/task_session.dart';
import 'package:bridge_app/services/tasks/task_session_store.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/theme/tier.dart';
import 'package:bridge_app/theme/tier_style.dart';
import 'dart:io';

class TaskDeliveryCard extends StatefulWidget {
  const TaskDeliveryCard({
    super.key,
    required this.message,
    required this.onViewCanvas,
  });

  final Message message;

  /// 查看工作畫布（直播視圖第 2 層）
  final void Function(String workCanvasId) onViewCanvas;

  @override
  State<TaskDeliveryCard> createState() => _TaskDeliveryCardState();
}

class _TaskDeliveryCardState extends State<TaskDeliveryCard> {
  TaskSession? _session;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final taskId = widget.message.metadata?['taskId'] as String?;
    if (taskId == null) return;
    // 先試記憶體態，再落 store
    final mem = TaskDispatcher.instance.activeSessions
        .where((s) => s.id == taskId)
        .firstOrNull;
    final s = mem ?? await TaskSessionStore.getById(taskId);
    if (mounted) setState(() => _session = s);
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final session = _session;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ds.borderDefault),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 標題列 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 18, color: ds.accentGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    session?.title ?? '任務完成',
                    style:
                        TierStyle.of(context, Tier.cardTitle).toTextStyle(),
                  ),
                ),
                if (session != null)
                  Text(
                    _durationLabel(session),
                    style: TierStyle.of(context, Tier.cardBody)
                        .toTextStyle()
                        .copyWith(color: ds.textMuted, fontSize: 11),
                  ),
              ],
            ),
          ),
          // ── awaitingReview 確認條（黃） ──
          if (session?.status == TaskStatus.awaitingReview)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: ds.accentYellow.withValues(alpha: 0.12),
              child: Row(
                children: [
                  Icon(Icons.help_outline, size: 16, color: ds.accentYellow),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('需要你的判斷',
                        style: TextStyle(color: ds.accentYellow, fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: () => _review(TaskStatus.delivered),
                    child: const Text('確認'),
                  ),
                  TextButton(
                    onPressed: () => _review(TaskStatus.working),
                    child: const Text('修改'),
                  ),
                  TextButton(
                    onPressed: () => _review(TaskStatus.cancelled),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
          // ── 摘要 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: Text(
              session?.finalSummary ?? widget.message.content,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
            ),
          ),
          // ── 產出縮圖列（Deliverables） ──
          if (session != null && session.deliverables.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: session.deliverables.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final d = session.deliverables[i];
                    return _DeliverableThumb(deliverable: d);
                  },
                ),
              ),
            ),
          ],
          // ── 底部動作 ──
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: Row(
              children: [
                if (session != null)
                  TextButton.icon(
                    onPressed: () => widget.onViewCanvas(session.workCanvasId),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('查看畫布', style: TextStyle(fontSize: 13)),
                  ),
                const Spacer(),
                Text(
                  '${session?.steps.length ?? 0} 步',
                  style: TierStyle.of(context, Tier.cardBody)
                      .toTextStyle()
                      .copyWith(color: ds.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _durationLabel(TaskSession s) {
    final end = s.finishedAt ?? DateTime.now();
    final d = end.difference(s.createdAt);
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m';
    return '${d.inHours}h${d.inMinutes % 60}m';
  }

  Future<void> _review(TaskStatus next) async {
    final s = _session;
    if (s == null) return;
    try {
      final updated = s.transitionTo(next,
          reason: next == TaskStatus.working ? '使用者要求修改' : null);
      await TaskDispatcher.instance.updateSession(updated);
      if (mounted) setState(() => _session = updated);
    } catch (e) {
      // 狀態機拒絕（如已 delivered）——誠實顯示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('狀態更新失敗：$e'), backgroundColor: ds_red(context)),
        );
      }
    }
  }

  Color ds_red(BuildContext context) => BridgeDSColors.of(context).accentRed;
}

/// 產出縮圖——圖片直讀檔案、canvas 顯示圖標、text/file 顯示圖標+名
class _DeliverableThumb extends StatelessWidget {
  const _DeliverableThumb({required this.deliverable});
  final TaskDeliverable deliverable;

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final w = SizedBox(
      width: 72,
      height: 72,
      child: deliverable.kind == 'image' && File(deliverable.ref).existsSync()
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              // [小葵 2026-10-20] 同對話滾動卡頓修復——縮圖按需解碼（72px 顯示）
              child: Image.file(File(deliverable.ref),
                  fit: BoxFit.cover, cacheWidth: 144,
                  errorBuilder: (_, __, ___) => _fallback(ds)),
            )
          : _fallback(ds),
    );
    return Tooltip(message: deliverable.caption, child: w);
  }

  Widget _fallback(ds) => Container(
        decoration: BoxDecoration(
          color: ds.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          deliverable.kind == 'canvas'
              ? Icons.grid_view_outlined
              : Icons.description_outlined,
          color: ds.textTertiary,
          size: 24,
        ),
      );
}
