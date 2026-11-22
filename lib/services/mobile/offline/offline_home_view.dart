// 離線誠實視圖（Offline Home View）——快照＋聊天輸入的區塊化元件
// [S3 UI 接線 2026-11-09] 依據 BRIDGE_MOBILE_SPEC.md v0.5 §7 離線行為
// [S4 2026-11-10 Blue 令] 區塊化重組——快照/對話不再綁死首頁：
//   - 快照區（含離線誠實標灰）→ 「配對」tab
//   - 對話區（輸入框＋最近對話）→ 「對話」tab
//   - OfflineHomeView 保留 = 兩區塊直疊（過渡期相容＋測試沿用）
//
// 設計鐵則：Tier 系統（字級/顏色禁 Material 預設）、離線不空白不轉圈。

import 'package:bridge_app/services/mobile/offline/home_view_state.dart';
import 'package:bridge_app/services/mobile/offline/snapshot_entries_view.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/theme/tier.dart';
import 'package:bridge_app/theme/tier_style.dart';
import 'package:flutter/material.dart';

/// 過渡期組裝：快照區＋對話區直疊（原首頁下半部）。
class OfflineHomeView extends StatelessWidget {
  final HomeViewState state;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmit;

  const OfflineHomeView({
    super.key,
    required this.state,
    this.controller,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    final offline = state.isOffline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ★ 條款 1：狀態燈——離線黃燈/線上綠燈（誠實燈號）
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: offline ? colors.tagWarnFg : colors.accentGreen,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              offline ? '離線' : '已連線',
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(
                    color: offline ? colors.tagWarnFg : colors.accentGreen,
                  ),
            ),
            if (offline) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '離線中，顯示的是上次快照',
                  style: TierStyle.of(
                    context,
                    Tier.cardCaption,
                  ).toTextStyle().copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: SnapshotSection(state: state)),
        const SizedBox(height: 12),
        ChatInputSection(
          state: state,
          controller: controller,
          onSubmit: onSubmit,
        ),
      ],
    );
  }
}

/// 快照區（可獨立使用）——[S4 2026-11-10] 搬入「配對」tab 的主體。
///
/// ★ 條款 1：離線時整體標灰（明示「這是舊資料」）。
/// ★ 條款 2：時間戳屬於快照本身（不是當下時間）。
class SnapshotSection extends StatelessWidget {
  final HomeViewState state;

  const SnapshotSection({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    final snapshot = state.snapshot;

    if (snapshot == null || snapshot.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.borderDefault),
        ),
        child: Text(
          state.emptySnapshotNotice,
          style: TierStyle.of(
            context,
            Tier.cardBody,
          ).toTextStyle().copyWith(color: colors.textSecondary),
        ),
      );
    }

    return Opacity(
      opacity: state.dimmedOpacity,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.borderDefault),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ★ 條款 2：時間戳屬於快照本身（不是當下時間）。
              Text(
                '上次快照：${state.snapshotTimestampLabel}',
                style: TierStyle.of(
                  context,
                  Tier.cardCaption,
                ).toTextStyle().copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 8),
              // [S4 2026-11-10] 語意化渲染——raw key-value → 中文標籤兩欄式
              SnapshotEntriesView(snapshot: snapshot),
            ],
          ),
        ),
      ),
    );
  }
}

/// 對話輸入區（可獨立使用）——[S4 2026-11-10] 搬入「對話」tab 的主體。
///
/// ★ 條款 3：離線時仍可打字，並標「離線中，訊息重連後送出」。
class ChatInputSection extends StatelessWidget {
  final HomeViewState state;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmit;

  const ChatInputSection({
    super.key,
    required this.state,
    this.controller,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);

    // [S4 2026-11-10] TextField 需要 Material 祖先（脫離首頁 Scaffold 獨立使用）
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  // ★ 條款 3：inputEnabled 恆 true（離線也不禁用輸入框）。
                  enabled: state.inputEnabled,
                  style: TierStyle.of(
                    context,
                    Tier.cardBody,
                  ).toTextStyle().copyWith(color: colors.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: state.inputHint,
                    hintStyle: TierStyle.of(
                      context,
                      Tier.cardBody,
                    ).toTextStyle().copyWith(color: colors.textMuted),
                    filled: true,
                    fillColor: colors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.borderDefault),
                    ),
                  ),
                  onSubmitted: onSubmit,
                ),
              ),
              const SizedBox(width: 8),
              // [S4 2026-11-10] 單色極簡 icon——符合 Blue 符號簡約令
              IconButton(
                onPressed: () {
                  final text = controller?.text ?? '';
                  if (text.trim().isNotEmpty) onSubmit?.call(text);
                },
                icon: Icon(Icons.north, size: 20, color: colors.textPrimary),
                style: IconButton.styleFrom(
                  backgroundColor: colors.surface,
                  shape: const CircleBorder(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
