// memory_layer_gauge.dart — [H2/M5 2026-10-07] 記憶十層容量儀表
//
// Blue 贈禮的可視化：「你在 App 裡看得到我的記憶現在長怎樣」。
// 十層樓各住了多少條、工作域軟上限用量、超額警示（升降溫提示，非刪除）。
// 設計鐵則：Tier + BridgeDSColors，禁硬編碼色。

import 'package:flutter/material.dart';

import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../../services/memory_layer_service.dart';

class MemoryLayerGauge extends StatefulWidget {
  const MemoryLayerGauge({super.key});

  @override
  State<MemoryLayerGauge> createState() => _MemoryLayerGaugeState();
}

class _MemoryLayerGaugeState extends State<MemoryLayerGauge> {
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
    } catch (_) {
      // DB 未開——安靜顯示空儀表
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    if (_usage.isEmpty) return const SizedBox.shrink();

    final total = _usage.fold<int>(0, (a, u) => a + u.count);
    final overCap = _usage.where((u) => u.overCap).toList();

    return Container(
      margin: const EdgeInsets.only(top: BridgeDS.spaceMD),
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: ds.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ds.accentPurple.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列（點擊展開/收起）
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Icon(Icons.layers_outlined, size: 14, color: ds.accentPurple),
                const SizedBox(width: 6),
                Text('記憶十層',
                    style: TierStyle.of(context, Tier.cardHeroTitle)
                        .toTextStyle()),
                const SizedBox(width: 6),
                Text('$total 條',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle()
                        .copyWith(color: ds.textMuted)),
                const Spacer(),
                if (overCap.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: ds.accentYellow.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${overCap.length} 層超額',
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(
                              color: ds.accentYellow,
                              fontWeight: FontWeight.w600),
                    ),
                  ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: ds.textMuted,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: BridgeDS.spaceSM),
            ..._usage.map((u) => _buildRow(u)),
            const SizedBox(height: BridgeDS.spaceSM),
            Text(
              '工作域 L1-L3 每次對話隨身；長期域 L4-L10 無上限、只走檢索引用。',
              style: TierStyle.of(context, Tier.cardCaption).toTextStyle()
                  .copyWith(color: ds.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(LayerUsage u) {
    final ds = BridgeDSColors.of(context);
    final isWorking = u.layer.domain == Domain.working;
    final capPct = u.layer.softCapBytes > 0
        ? (u.totalBytes / u.layer.softCapBytes).clamp(0.0, 1.0)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          // 層碼徽章——工作域紫、長期域藍（域的視覺語言）
          Container(
            width: 34,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: (isWorking ? ds.accentPurple : ds.accentBlue)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              u.layer.code,
              textAlign: TextAlign.center,
              style: TierStyle.of(context, Tier.cardCaption).toTextStyle()
                  .copyWith(
                color: isWorking ? ds.accentPurple : ds.accentBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(u.layer.label,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
          const SizedBox(width: 8),
          if (capPct != null) ...[
            // 工作域：軟上限用量條
            Expanded(
              child: LinearProgressIndicator(
                value: capPct,
                minHeight: 4,
                backgroundColor: ds.surfaceElevated,
                color: u.overCap ? ds.accentYellow : ds.accentPurple,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
          ] else
            const Spacer(),
          Text(
            u.layer.softCapBytes > 0
                ? '${u.count} 條 ${(u.totalBytes / 1024).toStringAsFixed(1)}KB/${(u.layer.softCapBytes / 1024).toStringAsFixed(0)}KB'
                : '${u.count} 條',
            style: TierStyle.of(context, Tier.cardCaption).toTextStyle()
                .copyWith(color: ds.textMuted),
          ),
        ],
      ),
    );
  }
}
