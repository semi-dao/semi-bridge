// [教練 Agent Sprint 17 Step 5 — 2026-07-07]
// 訊息渲染輔助 widget 與工具函式。
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/conversation.dart';
import '../../../models/capability_advisor.dart';
import '../../../services/memory_store.dart';
import '../../../services/companion_store.dart';
import '../../../widgets/bridge_cards/capability_advisor_card.dart';
import '../cards/misc_card_widgets.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';

/// 訊息圖片渲染：支援 base64 data URI、HTTP URL、本機檔案。
class MessageImage extends StatelessWidget {
  final String imagePath;

  const MessageImage({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    if (imagePath.startsWith('data:image/')) {
      final commaIndex = imagePath.indexOf(',');
      final encoded = commaIndex >= 0
          ? imagePath.substring(commaIndex + 1)
          : imagePath;
      return Image.memory(base64Decode(encoded), width: 240, fit: BoxFit.cover);
    }

    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(imagePath, width: 240, fit: BoxFit.cover);
    }

    if (kIsWeb) {
      return const Icon(Icons.image, size: 100);
    }

    return Image.file(File(imagePath), width: 200, fit: BoxFit.cover);
  }
}

/// 訊息複製按鈕樣式。
ButtonStyle messageCopyButtonStyle(BuildContext context) {
  return TextButton.styleFrom(
    foregroundColor: BridgeDS.grey700,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    minimumSize: const Size(0, 28),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    textStyle: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800),
  );
}

/// 文字選取右鍵選單（只保留 copy）。
Widget buildTextSelectionContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  final buttonItems = editableTextState.contextMenuButtonItems;
  final focusedItems = buttonItems
      .where((item) => item.type == ContextMenuButtonType.copy)
      .toList();
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: focusedItems.isEmpty ? buttonItems : focusedItems,
  );
}

/// 解析 agent 名稱。
String resolveAgentName(String speakerId) {
  // [指紋定律 2026-10-16 Blue] 原生 Agent 具名——不是匿名「夥伴」。
  // 沒有 companion 的對話＝App 原生 Agent（小葵家族的預設身份）。
  if (speakerId == 'native-agent') return '原生 Agent';
  final companion = CompanionStore().getById(speakerId);
  return companion?.name ?? '原生 Agent';
}

/// 回答回饋列：準確 / 不準確 / 先別採用。
class AnswerFeedbackBar extends StatelessWidget {
  final Message msg;
  final void Function(Message msg, TransurfingInsightFeedback feedback) onFeedback;

  const AnswerFeedbackBar({
    super.key,
    required this.msg,
    required this.onFeedback,
  });

  @override
  Widget build(BuildContext context) {
    final feedback = msg.metadata?['answerFeedback']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '這輪回答',
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDS.grey600,
              fontWeight: FontWeight.w800,),
          ),
          AnswerFeedbackChip(
            label: '準確',
            icon: Icons.check_circle_outline_rounded,
            selected: feedback == 'accurate',
            onTap: () => onFeedback(msg, TransurfingInsightFeedback.accurate),
          ),
          AnswerFeedbackChip(
            label: '不準確',
            icon: Icons.report_problem_outlined,
            selected: feedback == 'inaccurate',
            onTap: () => onFeedback(msg, TransurfingInsightFeedback.inaccurate),
          ),
          AnswerFeedbackChip(
            label: '先別採用',
            icon: Icons.visibility_off_outlined,
            selected: feedback == 'muted',
            onTap: () => onFeedback(msg, TransurfingInsightFeedback.muted),
          ),
        ],
      ),
    );
  }
}

/// Capability Advisor 卡片建構器。
/// 將原本 _buildCapabilityAdvisorCard 的 callback 包裝邏輯搬出。
/// SnackBar 邏輯由呼叫端處理（需 context + mounted）。
class CapabilityAdvisorCardBuilder extends StatelessWidget {
  final CapabilityAdvisorCardData data;
  final VoidCallback onConfirmIntent;
  final VoidCallback onStartBrowseSubFlow;
  final void Function(String intent) onCorrectIntent;
  final void Function(String id) onSelectSolution;
  final VoidCallback onVerify;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onReturnToTask;

  const CapabilityAdvisorCardBuilder({
    super.key,
    required this.data,
    required this.onConfirmIntent,
    required this.onStartBrowseSubFlow,
    required this.onCorrectIntent,
    required this.onSelectSolution,
    required this.onVerify,
    required this.onRetry,
    required this.onCancel,
    required this.onReturnToTask,
  });

  @override
  Widget build(BuildContext context) {
    return CapabilityAdvisorCard(
      data: data,
      onConfirmIntent: onConfirmIntent,
      onStartBrowseSubFlow: onStartBrowseSubFlow,
      onCorrectIntent: onCorrectIntent,
      onSelectSolution: onSelectSolution,
      onOpenUrl: (url) {
        // URL 開啟由 widget 內部 url_launcher 處理
      },
      onVerify: onVerify,
      onRetry: onRetry,
      onCancel: onCancel,
      onReturnToTask: onReturnToTask,
    );
  }
}
