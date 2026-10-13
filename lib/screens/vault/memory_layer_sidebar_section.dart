// memory_layer_sidebar_section.dart — [H2/M5+ 2026-10-07 Blue 令 v2]
// 記憶十層固定在側欄底部（不佔樹狀資料夾空間）：
// - 收合時只顯示「記憶十層 N條」一列
// - 展開時十層列表「長出來」（點層 → 主區中央顯示該層內容、可編輯）
// 設計鐵則：Tier + BridgeDSColors；工作域紫、長期域藍。

import 'package:flutter/material.dart';

import '../../services/memory_layer_service.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

class MemoryLayerSidebarSection extends StatefulWidget {
  final MemoryLayer? selectedLayer;
  final ValueChanged<MemoryLayer?> onLayerTap;

  const MemoryLayerSidebarSection({
    super.key,
    required this.selectedLayer,
    required this.onLayerTap,
  });

  @override
  State<MemoryLayerSidebarSection> createState() =>
      _MemoryLayerSidebarSectionState();
}

class _MemoryLayerSidebarSectionState extends State<MemoryLayerSidebarSection> {
  List<LayerUsage> _usage = const [];
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      setState(() => _usage = MemoryLayerService.instance.usage());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    if (_usage.isEmpty) return const SizedBox.shrink();

    final total = _usage.fold<int>(0, (a, u) => a + u.count);
    final byCode = {for (final u in _usage) u.layer.code: u};

    return Container(
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: ds.borderSubtle, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 固定列：記憶十層（點擊展開/收合）──
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: BridgeDS.spaceMD, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.layers_outlined,
                      size: 15, color: ds.accentPurple),
                  const SizedBox(width: 8),
                  Text('記憶十層',
                      style: TierStyle.of(context, Tier.cardHeroTitle)
                          .toTextStyle()),
                  const SizedBox(width: 6),
                  Text('$total 條',
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(color: ds.textMuted)),
                  const Spacer(),
                  if (widget.selectedLayer != null && !_expanded) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: ds.accentPurple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.selectedLayer!.code,
                        style: TierStyle.of(context, Tier.cardCaption)
                            .toTextStyle()
                            .copyWith(
                                color: ds.accentPurple,
                                fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    size: 16,
                    color: ds.textMuted,
                  ),
                ],
              ),
            ),
          ),
          // ── 展開：十層列表從下面長出來 ──
          if (_expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: BridgeDS.spaceSM),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final layer in MemoryLayer.values)
                      _buildLayerRow(layer, byCode[layer.code]?.count ?? 0),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLayerRow(MemoryLayer layer, int count) {
    final ds = BridgeDSColors.of(context);
    final isSelected = widget.selectedLayer == layer;
    final isWorking = layer.domain == Domain.working;
    final tone = isWorking ? ds.accentPurple : ds.accentBlue;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onLayerTap(isSelected ? null : layer),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: isSelected ? tone.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                layer.code,
                textAlign: TextAlign.center,
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: tone, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                layer.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle()
                    .copyWith(
                  color: isSelected ? ds.textPrimary : ds.textSecondary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              '$count',
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(
                color: isSelected ? tone : ds.textMuted,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
