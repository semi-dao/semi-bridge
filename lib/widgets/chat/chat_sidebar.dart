// [以利沙 Sprint 4 2026-06-24]
// ChatSidebar — 從 chat_screen.dart 抽出的純 StatelessWidget 側邊欄
// 業務邏輯（_isProjectConversation）留在 _ChatScreenState，
// 這裡只負責 UI；外部傳入已分類好的 projectConversations / generalConversations
import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/project_door.dart';
import '../../theme/app_theme.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../../theme/bridge_design_system.dart';
import '../../services/companion_store.dart'; // [刀 2] 反查夥伴名
import 'package:bridge_app/widgets/trust/agent_glyph.dart'; // [刀 2] 指紋縮圖

/// 左側對話列表側邊欄（純 UI，StatelessWidget）
class ChatSidebar extends StatelessWidget {
  // [以利沙 Sprint 4 2026-06-24]
  const ChatSidebar({
    super.key,
    required this.conversations,
    required this.projectDoors,
    required this.currentConversation,
    required this.onNewConversation,
    required this.onSwitchConversation,
    required this.onRenameConversation,
    required this.onDeleteConversation,
    this.isProjectConversation,
  });

  final List<Conversation> conversations;
  final List<ProjectDoor> projectDoors;
  final Conversation? currentConversation;
  final VoidCallback onNewConversation;
  final ValueChanged<Conversation> onSwitchConversation;
  final ValueChanged<Conversation> onRenameConversation;
  final ValueChanged<String> onDeleteConversation;

  /// 外部注入的分類判斷函數（保留業務邏輯在 _ChatScreenState）
  final bool Function(Conversation conv, Set<String> projectTitles)?
      isProjectConversation;

  // ── Section Header ──────────────────────────────────────
  Widget _buildSectionHeader(BuildContext context, {
    required IconData icon,
    required String title,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.textSecondary,
                fontWeight: FontWeight.w900,),
            ),
          ),
          Text(
            '$count',
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textMuted,
              fontWeight: FontWeight.w700,),
          ),
        ],
      ),
    );
  }

  // ── Conversation Tile ───────────────────────────────────
  Widget _buildConversationTile(
    BuildContext context,
    Conversation conv, {
    required bool isProject,
  }) {
    // [以利沙 Sprint 4 2026-06-24]
    final isActive = conv.id == currentConversation?.id;
    // [刀 2 2026-09-08 Blue 令] 參與這個對話的 Agent 縮圖列——
    // 掃訊息 speakerId（companion.id）去重；名字從 CompanionStore 反查。
    final speakerIds = conv.messages
        .map((m) => m.speakerId)
        .whereType<String>()
        .toSet()
        .take(4)
        .toList();
    final extraCount = conv.messages
            .map((m) => m.speakerId)
            .whereType<String>()
            .toSet()
            .length -
        speakerIds.length;
    return ListTile(
      leading: Icon(
        isProject ? Icons.flag_circle_outlined : Icons.chat_bubble_outline,
        color: isActive ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        conv.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.bold : null,
          color: isActive ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        isProject
            ? '專案門 · ${conv.messages.length} 則訊息'
            : '${conv.messages.length} 則訊息',
        style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
      ),
      selected: isActive,
      onTap: () => onSwitchConversation(conv),
      // [刀 2] 參與者 glyph 列＋選單鈕（無參與者＝只有選單）
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (speakerIds.isNotEmpty) ...[
            for (final sid in speakerIds)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Tooltip(
                  message: _companionNameOf(sid),
                  waitDuration: const Duration(milliseconds: 400),
                  child: AgentGlyph(
                    companionId: sid,
                    name: _companionNameOf(sid),
                    size: 18,
                    showInitial: false,
                  ),
                ),
              ),
            if (extraCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  '+$extraCount',
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: Theme.of(context).hintColor),
                ),
              ),
            const SizedBox(width: 2),
          ],
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') {
                onRenameConversation(conv);
              }
              if (value == 'delete') {
                onDeleteConversation(conv.id);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 18),
                    SizedBox(width: 8),
                    Text('重新命名'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, size: 18, color: BridgeDS.red500),
                    SizedBox(width: 8),
                    Text('刪除', style: TextStyle(color: BridgeDS.red500)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// [刀 2] speakerId → 夥伴名（反查失敗退 '？'——顯示不炸）
  String _companionNameOf(String speakerId) {
    // [指紋定律 2026-10-16 Blue] 原生 Agent 具名＋品牌紫指紋
    if (speakerId == 'native-agent') return '原生 Agent';
    try {
      final c = CompanionStore().getById(speakerId);
      return c?.name ?? '未知夥伴';
    } catch (_) {
      return '未知夥伴';
    }
  }

  @override
  Widget build(BuildContext context) {
    // [以利沙 Sprint 4 2026-06-24]
    final projectTitles = projectDoors
        .map((door) => door.title.trim())
        .where((title) => title.isNotEmpty)
        .toSet();

    final classifier = isProjectConversation;

    final projectConversations = classifier != null
        ? conversations
            .where((conv) => classifier(conv, projectTitles))
            .toList()
        : <Conversation>[];

    final generalConversations = classifier != null
        ? conversations
            .where((conv) => !classifier(conv, projectTitles))
            .toList()
        : conversations;

    // [Blue 令 2026-10-17] 主動回應獨立分組——羅盤/夢的開話 session
    // 與一般對話分開列，確保訊息保存可見（不混入、不消失）。
    final proactiveConversations = conversations
        .where((conv) => conv.type == ConversationType.proactive)
        .toList();
    final nonProactiveGeneral = generalConversations
        .where((conv) => conv.type != ConversationType.proactive)
        .toList();
    final nonProactiveProject = projectConversations
        .where((conv) => conv.type != ConversationType.proactive)
        .toList();

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onNewConversation,
                  icon: const Icon(Icons.add),
                  label: const Text('新對話'),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  if (proactiveConversations.isNotEmpty)
                    _buildSectionHeader(
                      context,
                      icon: Icons.auto_awesome_outlined,
                      title: '主動回應',
                      count: proactiveConversations.length,
                    ),
                  for (final conv in proactiveConversations)
                    _buildConversationTile(context, conv, isProject: false),
                  if (nonProactiveProject.isNotEmpty)
                    _buildSectionHeader(
                      context,
                      icon: Icons.flag_circle_outlined,
                      title: '專案門',
                      count: nonProactiveProject.length,
                    ),
                  for (final conv in nonProactiveProject)
                    _buildConversationTile(context, conv, isProject: true),
                  if (nonProactiveGeneral.isNotEmpty)
                    _buildSectionHeader(
                      context,
                      icon: Icons.chat_bubble_outline,
                      title: '一般對話',
                      count: nonProactiveGeneral.length,
                    ),
                  for (final conv in nonProactiveGeneral)
                    _buildConversationTile(context, conv, isProject: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
