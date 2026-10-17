// Desktop Homepage — 桌面版首頁
// [Phase 0 2026-07-17]
//
// 使用者的想像：未來這裡是社群創作者分享外掛/skill/資產包/活動的地方。
// 現在先佔位，只呈現初次體驗教學引導。
//
// 設計：BridgeDS 暗色風格 + Miro 無限轉場動態

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/bridge_design_system.dart';
import '../../theme/bridge_motion.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

class DesktopHomepageScreen extends StatefulWidget {
  DesktopHomepageScreen({super.key});

  @override
  State<DesktopHomepageScreen> createState() => _DesktopHomepageScreenState();
}

class _DesktopHomepageScreenState extends State<DesktopHomepageScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BridgeDSColors.of(context).canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BridgeDS.spaceXXL),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Hero ──────────────────────────────
                  _buildHero(),
                  const SizedBox(height: BridgeDS.spaceXXL),

                  // ── 教學引導卡片 ────────────────────
                  _buildTutorialSection(),
                  const SizedBox(height: BridgeDS.spaceXL),

                  // ── 社群佔位 ────────────────────────
                  _buildCommunityPlaceholder(),
                  SizedBox(height: BridgeDS.spaceXL),

                  // ── 進入桌面 ────────────────────────
                  _buildEnterButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // Hero
  // ═══════════════════════════════════════════════════

  Widget _buildHero() {
    return BridgeScaleIn(
      beginScale: 0.88,
      child: Column(
        children: [
          BridgePulseDot(
            color: BridgeDSColors.of(context).accentMiro,
            size: 12,
            active: true,
          ),
          SizedBox(height: BridgeDS.spaceLG),
          Text(
            '歡迎來到橋樑',
            style: BridgeDSColors.of(context).display.copyWith(
              fontSize: 48,
              color: BridgeDSColors.of(context).textPrimary,
            ),
          ),
          SizedBox(height: BridgeDS.spaceSM),
          BridgeSlideIn(
            delay: const Duration(milliseconds: 200),
            child: Text(
              '你的 AI 夥伴已經在等你了',
              style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(
                color: BridgeDSColors.of(context).textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 教學引導
  // ═══════════════════════════════════════════════════

  Widget _buildTutorialSection() {
    final tutorials = [
      _TutorialCard(
        icon: Icons.chat_bubble_outline,
        title: '跟夥伴對話',
        description: '在左側聊天面板跟你的 AI 夥伴聊天。它會記住你、理解你。',
        color: BridgeDSColors.of(context).accentBlue,
      ),
      _TutorialCard(
        icon: Icons.account_tree_outlined,
        title: '畫布工作區',
        description: '切換到畫布 tab，把想法變成工作流。你的夥伴能幫你操作畫布。',
        color: BridgeDSColors.of(context).accentMiro,
      ),
      _TutorialCard(
        icon: Icons.memory,
        title: '大腦記憶',
        description: '夥伴會把重要的事寫進大腦容器，跨對話記住你的偏好和專案。',
        color: BridgeDSColors.of(context).accentGreen,
      ),
      _TutorialCard(
        icon: Icons.settings_outlined,
        title: '系統設定',
        description: '在系統 tab 管理 API Key、配對手機、下載本地模型。',
        color: BridgeDSColors.of(context).accentYellow,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BridgeSlideIn(
          child: Text(
            '快速上手',
            style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary),
          ),
        ),
        const SizedBox(height: BridgeDS.spaceMD),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.5,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: tutorials.length,
          itemBuilder: (context, i) {
            return BridgeScaleIn(
              delay: Duration(milliseconds: 150 * (i + 1)),
              beginScale: 0.9,
              child: tutorials[i],
            );
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  // 社群佔位
  // ═══════════════════════════════════════════════════

  Widget _buildCommunityPlaceholder() {
    return BridgeSlideIn(
      delay: const Duration(milliseconds: 500),
      child: Container(
        padding: const EdgeInsets.all(BridgeDS.spaceXL),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(BridgeDS.roundWide),
          border: Border.all(
            color: BridgeDSColors.of(context).borderSubtle,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.rocket_launch_outlined,
              size: 32,
              color: BridgeDSColors.of(context).textQuaternary,
            ),
            SizedBox(height: 12),
            Text(
              '社群市集即將上線',
              style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(
                color: BridgeDSColors.of(context).textTertiary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '未來這裡會有創作者分享的外掛、Skill、資產包和社群活動。\n敬請期待。',
              textAlign: TextAlign.center,
              style: BridgeDSColors.of(context).body.copyWith(
                color: BridgeDSColors.of(context).textMuted,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 進入桌面按鈕
  // ═══════════════════════════════════════════════════

  Widget _buildEnterButton() {
    return BridgeSlideIn(
      delay: const Duration(milliseconds: 600),
      child: FilledButton.icon(
        onPressed: () => context.go('/bridge-desktop'),
        icon: const Icon(Icons.desktop_windows, size: 16),
        label: const Text('進入桌面'),
        style: FilledButton.styleFrom(
          backgroundColor: BridgeDSColors.of(context).accentMiro,
          minimumSize: const Size.fromHeight(48),
        ),
      ),
    );
  }
}

/// 教學卡片
class _TutorialCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  _TutorialCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: BridgeDSColors.of(context).body.copyWith(
                    color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  description,
                  style: BridgeDSColors.of(context).caption.copyWith(
                    color: BridgeDSColors.of(context).textTertiary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
