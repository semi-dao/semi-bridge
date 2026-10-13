// agent_status_dot.dart
// [TRIO M1 2026-09-22] 夥伴狀態點——AgentStatusStore（D1 真相源）的
// 讀取端最小視覺化。
//
// 三態詞彙表（與 AgentStatusStore 同步，禁同義詞）：
//   live          綠點＋呼吸動畫——正在執行任務
//   unverifiable  黃點——斷線≠死亡（App 重啟後 Loop 已斷）
//   exited        無點——不在場（正常閒置/已交付/已失敗，詳情看任務卡）
//
// 顏色全走 BridgeDSColors token（禁 Material 預設）；
// 文字層級若需展示必走 Tier（本 widget 只出點，不出字）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bridge_app/services/collab/agent_status_store.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';

/// 訂閱 AgentStatusStore 的狀態點——放在頭像右下角
class AgentStatusDot extends StatefulWidget {
  final String agentId;
  final double size;

  const AgentStatusDot({super.key, required this.agentId, this.size = 10});

  @override
  State<AgentStatusDot> createState() => _AgentStatusDotState();
}

class _AgentStatusDotState extends State<AgentStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathe;

  @override
  void initState() {
    super.initState();
    // 呼吸感（ 夥伴定調 2026-09-13：靜態圖＋一點呼吸感）
    // [小葵 2026-10-05 節能根修] repeat(reverse:) 每幀排 vsync——10px 小點
    // 60fps 是浪費。12fps 離散取樣，人眼無感。
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _lowFreqTicker = Timer.periodic(const Duration(milliseconds: 83), (_) {
      if (!mounted) return;
      _tick = (_tick + 1) % 24;
      final t = _tick < 12 ? _tick / 12.0 : (24 - _tick) / 12.0;
      _breathe.value = t;
    });
  }

  Timer? _lowFreqTicker;
  int _tick = 0;

  @override
  void dispose() {
    _lowFreqTicker?.cancel();
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      // [小葵 2026-10-05 節能] 隔離呼吸點重繪範圍
      child: AnimatedBuilder(
        animation: Listenable.merge(
            [AgentStatusStore.instance, _breathe]),
        builder: (context, _) {
          final status = AgentStatusStore.instance.statusOf(widget.agentId);
          // 不在場（exited 或從未上工）→ 不渲染——閒置是預設態不搶戲
          if (status == null || status.state == AgentRunState.exited) {
            return const SizedBox.shrink();
          }

          final ds = BridgeDSColors.of(context);
          final isLive = status.state == AgentRunState.live;
          final color = isLive ? ds.accentGreen : ds.accentYellow;

          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              // live 呼吸（透明度韻律）；unverifiable 穩定不動
              // （「不知道」不該假裝有生命）
              border: Border.all(
                color: isLive
                    ? color.withValues(
                        alpha: 0.4 + 0.6 * (1 - _breathe.value))
                    : color,
                width: 2,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 頭像＋右下角狀態點的組合（夥伴列/選單 item 共用）
class AvatarWithStatus extends StatelessWidget {
  final Widget avatar;
  final String agentId;
  final double dotSize;

  const AvatarWithStatus({
    super.key,
    required this.avatar,
    required this.agentId,
    this.dotSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            // 描邊底座讓點跟頭像分離（深淺主題都成立）
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BridgeDSColors.of(context).surfaceElevated,
            ),
            padding: const EdgeInsets.all(1.5),
            child: AgentStatusDot(agentId: agentId, size: dotSize),
          ),
        ),
      ],
    );
  }
}
