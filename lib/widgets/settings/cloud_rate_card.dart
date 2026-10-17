/// cloud_rate_card.dart
/// [T11② 2026-10-17] 雲端率儀表——event_ledger meta 的 provider 統計。
/// [Blue 令 2026-10-17 #4] 升級：7 天逐輪記錄可滾動；
///   舊輪無路由記錄顯示「未記錄」（誠實，不算本地也不算雲端）。
///
/// M6 驗收：雲端率 ≤30%。分母=有路由記錄的輪次（補記機制上線後才開始累積）。
///
/// UI 鐵則：Tier 字級（TierStyle.of）、BridgeDSColors、誠實顯示。
library;

import 'package:flutter/material.dart';
import '../../services/brain_container/event_ledger.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// [T11③] 修正率週報行——三週數字一列（驗收：遞減）
class _CorrectionWeeksRow extends StatelessWidget {
  final Map<String, dynamic> report;
  const _CorrectionWeeksRow({required this.report});

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final weeks = (report['weeks'] as List).cast<Map<String, dynamic>>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('修正率週報（糾正 / 輪次）',
            style: TierStyle.of(context, Tier.cardCaption)
                .toTextStyle()
                .copyWith(color: ds.textSecondary)),
        const SizedBox(height: 4),
        for (final w in weeks)
          Text(
            '${w['week_start']}：${w['corrected']} / ${w['turns']}'
            '${w['rate'] == null ? '' : '（${((w['rate'] as double) * 100).toStringAsFixed(1)}%）'}',
            style: TierStyle.of(context, Tier.cardCaption)
                .toTextStyle()
                .copyWith(color: ds.textTertiary),
          ),
      ],
    );
  }
}

/// [Blue 令 #4] 逐輪記錄列——時間 / 提供者 / 模型
class _TurnTile extends StatelessWidget {
  final Map<String, dynamic> turn;
  const _TurnTile({required this.turn});

  String _fmtTs(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final unknown = turn['unknown'] == true;
    final isLocal = turn['is_local'] == true;
    final provider = unknown ? '未記錄' : turn['provider']?.toString() ?? '?';
    final model = turn['model']?.toString() ?? '';
    final color = unknown
        ? ds.textTertiary
        : (isLocal ? ds.accentGreen : ds.accentBlue);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(_fmtTs(turn['ts'] as int),
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: ds.textTertiary)),
          ),
          SizedBox(
            width: 64,
            child: Text(provider,
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: color)),
          ),
          Expanded(
            child: Text(model,
                overflow: TextOverflow.ellipsis,
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: ds.textTertiary)),
          ),
        ],
      ),
    );
  }
}

class CloudRateCard extends StatefulWidget {
  const CloudRateCard({super.key});

  @override
  State<CloudRateCard> createState() => _CloudRateCardState();
}

class _CloudRateCardState extends State<CloudRateCard> {
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _correctionReport;
  List<Map<String, dynamic>> _turns = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = EventLedger.instance.cloudRateStats(days: 7);
      final corr = EventLedger.instance.correctionWeeklyReport(weeks: 3);
      final turns = EventLedger.instance.recentTurns(days: 7);
      if (mounted) {
        setState(() {
          _stats = stats;
          _correctionReport = corr;
          _turns = turns;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _stats = {'error': true});
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final stats = _stats;

    final Widget body;
    if (stats == null) {
      body = Text('統計中…', style: TierStyle.of(context, Tier.cardBody).toTextStyle());
    } else if (stats['error'] == true) {
      body = Text('統計失敗（見 log）',
          style: TierStyle.of(context, Tier.cardBody)
              .toTextStyle()
              .copyWith(color: ds.accentRed));
    } else {
      final known = stats['total'] as int;
      final unknown = (stats['unknown'] as int?) ?? 0;
      final localN = stats['local'] as int;
      final cloudN = stats['cloud'] as int;
      final cloudPct = known == 0 ? 0 : (cloudN * 100 / known).round();
      final byProvider =
          (stats['by_provider'] as Map<String, dynamic>?)?.entries.toList()
            ?..sort((a, b) => (b.value as int).compareTo(a.value as int));
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('雲端率 $cloudPct%',
                  style: TierStyle.of(context, Tier.cardTitle)
                      .toTextStyle()
                      .copyWith(
                          color:
                              known == 0 ? ds.textSecondary : (cloudPct > 30 ? ds.accentRed : ds.accentGreen))),
              const Spacer(),
              Text('（目標 ≤30%）',
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: ds.textTertiary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            known == 0
                ? '路由記錄今天開始累積——對話幾輪後這裡會顯示本地/雲端分佈。'
                : '近 7 天 $known 輪（有記錄）：本地 $localN・雲端 $cloudN'
                    '${unknown > 0 ? '・未記錄 $unknown（早期輪次）' : ''}',
            style: TierStyle.of(context, Tier.cardCaption)
                .toTextStyle()
                .copyWith(color: ds.textSecondary),
          ),
          if (byProvider != null && byProvider.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final e in byProvider.take(5))
                  Text('${e.key} ×${e.value}',
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(color: ds.textTertiary)),
              ],
            ),
          ],
          if (_correctionReport != null)
            _CorrectionWeeksRow(report: _correctionReport!),
          // [Blue 令 #4] 逐輪記錄——可滾動，看 7 天前也行
          if (_turns.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('逐輪記錄（近 7 天 ${_turns.length} 輪）',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: ds.textSecondary)),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _turns.length,
                itemBuilder: (_, i) => _TurnTile(turn: _turns[i]),
              ),
            ),
          ],
        ],
      );
    }

    return Card(
      color: ds.surfaceElevated,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.cloud_outlined, size: 18, color: ds.textSecondary),
              const SizedBox(width: 8),
              Text('雲端率儀表',
                  style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.refresh, size: 16, color: ds.textTertiary),
                onPressed: () {
                  setState(() {
                    _stats = null;
                    _turns = const [];
                  });
                  _load();
                },
              ),
            ]),
            body,
          ],
        ),
      ),
    );
  }
}
