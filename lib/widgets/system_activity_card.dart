import 'dart:async';

import 'package:flutter/material.dart';

import '../services/activity/background_task_registry.dart';
import '../services/local_model_scheduler.dart'; // [小葵 2026-10-01] 離合器
import 'bridge_desktop_widgets.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

/// 系統活動中心——背景任務可視化（金礦1，2026-09-30）。
///
/// 起源：身份重嵌入背景燒 200% CPU、使用者只覺得電腦遲鈍（2026-09-29 懸案）。
/// 本卡 = 背景任務的唯一顯示處：正在做什麼、進度、做完什麼。
/// 無任務時整卡隱藏（不佔位）——「安靜就是綠燈」。
class SystemActivityCard extends StatefulWidget {
  const SystemActivityCard({super.key});

  @override
  State<SystemActivityCard> createState() => _SystemActivityCardState();
}

class _SystemActivityCardState extends State<SystemActivityCard> {
  StreamSubscription<List<BackgroundTask>>? _sub;
  List<BackgroundTask> _tasks = [];

  @override
  void initState() {
    super.initState();
    _tasks = BackgroundTaskRegistry.instance.tasks;
    _sub = BackgroundTaskRegistry.instance.stream.listen((tasks) {
      if (mounted) setState(() => _tasks = tasks);
    });
    // [小葵 2026-10-01 離合器步驟3] 訂閱離合器狀態——照片辨識常駐區塊
    _clutchSub = LocalModelScheduler.instance.stream.listen((_) {
      if (mounted) setState(() {});
    });
    LocalModelScheduler.instance.loadRoles();
  }

  StreamSubscription<LocalClutchSnapshot>? _clutchSub;

  @override
  void dispose() {
    _sub?.cancel();
    _clutchSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // [小葵 2026-10-01 離合器步驟3] 有辨識角色 or 有待辨識 → 卡片常駐顯示
    // （Blue 拍板：「現在辨識」放系統活動中心，常駐不自動收起）
    final clutch = LocalModelScheduler.instance.snapshot;
    final hasVisionWork = clutch.hasVisionRole && clutch.pendingVisionItems > 0;
    if (_tasks.isEmpty && !hasVisionWork) return const SizedBox.shrink();
    final colors = BridgeDSColors.of(context);
    final running = _tasks.where((t) => t.status == BackgroundTaskStatus.running).length;

    return BridgeCard(
      child: Padding(
        padding: const EdgeInsets.all(BridgeDS.spaceLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.monitor_heart_outlined, size: 18, color: colors.accentBlue),
              const SizedBox(width: 8),
              Text('系統活動中心', style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.accentBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$running 進行中',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                        color: colors.accentBlue, fontSize: 12)),
              ),
              const Spacer(),
              Text('背景工作會自動完成，不影響你使用',
                  style: TierStyle.of(context, Tier.cardBody)
                      .toTextStyle()
                      .copyWith(color: colors.textMuted, fontSize: 12)),
            ]),
            const SizedBox(height: BridgeDS.spaceMD),
            // [小葵 2026-10-01 離合器步驟3] 照片辨識常駐區塊（Blue 拍板）
            _buildVisionSection(colors),
            ..._tasks.map((t) => _taskRow(t, colors)),
          ],
        ),
      ),
    );
  }

  Widget _taskRow(BackgroundTask t, BridgeDSColors colors) {
    final done = t.status == BackgroundTaskStatus.done;
    final hasProgress = t.progress >= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: BridgeDS.spaceSM),
      child: Row(children: [
        Icon(
          done ? Icons.check_circle : (t.status == BackgroundTaskStatus.error ? Icons.error : Icons.autorenew),
          size: 16,
          color: done ? colors.accentGreen : colors.accentBlue,
        ),
        const SizedBox(width: 8),
        Text(t.name, style: TierStyle.of(context, Tier.cardBody)
            .toTextStyle().copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            done
                ? (t.note ?? '完成')
                : (t.current != null ? '…… ${_base(t.current!)}' : t.detail),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(context, Tier.cardBody)
                .toTextStyle().copyWith(color: colors.textMuted, fontSize: 12),
          ),
        ),
        if (!done && hasProgress)
          Text('${(t.progress * 100).round()}%',
              style: TierStyle.of(context, Tier.cardBody)
                  .toTextStyle().copyWith(color: colors.accentBlue, fontSize: 12)),
        if (!done) ...[
          const SizedBox(width: 6),
          // [U1] 溫和暫停——任務在批次邊界檢查，不打斷當前筆
          _PauseButton(taskId: t.id),
        ],
      ]),
    );
  }

  String _base(String p) => p.split('/').last;

  /// [小葵 2026-10-01 離合器步驟3] 照片辨識常駐區塊——「現在辨識」按鈕
  /// Blue 拍板：放系統活動中心、常駐不自動收起。
  Widget _buildVisionSection(BridgeDSColors colors) {
    final clutch = LocalModelScheduler.instance.snapshot;

    // 未設辨識角色 → 不顯示（零強迫，行為退回現狀）
    if (!clutch.hasVisionRole) return const SizedBox.shrink();

    final stateLabel = switch (clutch.state) {
      LocalClutchState.runChat => '夥伴模式中',
      LocalClutchState.switching => '切換模型中…',
      LocalClutchState.runVision => '辨識模式中（完成後自動接回聊天）',
      LocalClutchState.faulted => '自動切換失敗（已回手動）',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: BridgeDS.spaceMD),
      child: Container(
        padding: const EdgeInsets.all(BridgeDS.spaceMD),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.borderDefault),
        ),
        child: Row(children: [
          Icon(Icons.image_search,
              size: 16,
              color: clutch.state == LocalClutchState.faulted
                  ? colors.accentRed
                  : colors.accentBlue),
          const SizedBox(width: 8),
          Text('照片辨識',
              style: TierStyle.of(context, Tier.cardBody)
                  .toTextStyle()
                  .copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              clutch.pendingVisionItems > 0
                  ? '待辨識 ${clutch.pendingVisionItems} 張 · $stateLabel'
                  : stateLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.cardBody)
                  .toTextStyle()
                  .copyWith(color: colors.textMuted, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          // 〔現在辨識〕手動按鈕——不等閒置直接切
          if (clutch.state == LocalClutchState.faulted)
            GestureDetector(
              onTap: () => LocalModelScheduler.instance.clearFault(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.accentYellow.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('重試自動切換',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle()
                        .copyWith(
                            color: colors.accentYellow,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
              ),
            )
          else
            GestureDetector(
              onTap: (clutch.state == LocalClutchState.switching)
                  ? null
                  : () => LocalModelScheduler.instance.runVisionNow(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.accentBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('現在辨識',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle()
                        .copyWith(
                            color: colors.accentBlue,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
      ),
    );
  }
}


/// [U1 2026-09-30] 暫停/繼續鈕——訂閱 Registry 暫停狀態
class _PauseButton extends StatefulWidget {
  final String taskId;
  const _PauseButton({required this.taskId});
  @override
  State<_PauseButton> createState() => _PauseButtonState();
}

class _PauseButtonState extends State<_PauseButton> {
  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return StreamBuilder<List<BackgroundTask>>(
      stream: BackgroundTaskRegistry.instance.stream,
      builder: (context, _) {
        final paused = BackgroundTaskRegistry.instance.isPauseRequested(widget.taskId);
        return GestureDetector(
          onTap: () => paused
              ? BackgroundTaskRegistry.instance.resumeTask(widget.taskId)
              : BackgroundTaskRegistry.instance.requestPause(widget.taskId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (paused ? colors.accentYellow : colors.textMuted).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(paused ? Icons.play_arrow : Icons.pause, size: 14,
                  color: paused ? colors.accentYellow : colors.textMuted),
              const SizedBox(width: 2),
              Text(paused ? '繼續' : '暫停',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                      color: paused ? colors.accentYellow : colors.textMuted, fontSize: 11)),
            ]),
          ),
        );
      },
    );
  }
}
