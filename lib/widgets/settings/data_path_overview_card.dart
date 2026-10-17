// data_path_overview_card.dart
// [資料主權 P0-c 2026-09-14] 資料路徑總覽卡——把 sovereignty_ledger 攤給使用者看。
// 提案：docs/specs/2026-09-14-data-sovereignty-design.md §4.2
//
// 人機共視鐵則：agent 過 gate 的每筆流量，使用者都要看得到。
// 顯示最近 7 天：哪個網域、幾次、什麼資料類型、什麼用途、分級。
// 文案鐵則：內部語法永不示人——用途與分類顯示人話，host 是必要透明度（它是「去哪」的答案）。

import 'package:flutter/material.dart';

import '../../services/sovereignty/data_path_gate.dart';
import '../../services/sovereignty/trace_scrubber.dart';
import '../../services/sovereignty/scrub_history_store.dart'; // [Blue 令 2026-10-17] 除痕歷史
import '../../theme/bridge_design_system.dart';
import '../bridge_desktop_widgets.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// ledger 的讀取介面（gate 提供 stream / 查詢；UI 只負責呈現）
class DataPathOverviewCard extends StatefulWidget {
  const DataPathOverviewCard({super.key});

  @override
  State<DataPathOverviewCard> createState() => _DataPathOverviewCardState();
}

class _DataPathOverviewCardState extends State<DataPathOverviewCard> {
  List<AggregatedEntry> _rows = [];
  bool _loading = true;
  bool _autoScrub = true;
  bool _scrubBusy = false;
  List<ScrubHistoryEntry> _scrubHistory = []; // [Blue 令 2026-10-17] 除痕歷史

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAutoScrub();
  }

  Future<void> _loadAutoScrub() async {
    final on = await TraceScrubber.instance.autoEnabled;
    if (mounted) setState(() => _autoScrub = on);
  }

  Future<void> _runManualScrub() async {
    if (_scrubBusy) return;
    setState(() => _scrubBusy = true);
    try {
      // dry-run 先給使用者看要刪什麼（破壞性操作權力在使用者）。
      // [09-14 Blue 拍板] 一鍵除痕＝使用者當場親自按下＋確認＝「現在全部清掉」，
      // 不適用自動模式的 2 小時門檻（那條門檻只保護背景自動輪，防刪到使用中檔案；
      // 手動場景沒有這個風險，因為使用者就在螢幕前）。此語意鎖死，勿改。
      final items = await TraceScrubber.instance.scan(ageThreshold: Duration.zero);
      if (items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('沒有可清理的外傳暫存——乾淨。')),
          );
        }
        return;
      }
      final totalKb = items.fold<int>(0, (a, b) => a + b.bytes) / 1024;
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('一鍵除痕（預覽）'),
          content: Text(
            '將刪除 ${items.length} 個外傳暫存檔'
            '（${totalKb.toStringAsFixed(0)}KB）：\n\n'
            '${items.take(6).map((e) => '· ${e.label}').join('\n')}'
            '${items.length > 6 ? '\n…等' : ''}\n\n'
            '對話、記憶、資料、向量庫一律不動。',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('確認清除')),
          ],
        ),
      );
      if (ok == true) {
        final freed = await TraceScrubber.instance.purge(items);
        // [Blue 令 2026-10-17] 除痕歷史——手動一鍵除痕也記錄
        await ScrubHistoryStore.instance.record(
          trigger: 'manual',
          files: items.length,
          bytes: freed,
          items: [
            for (final it in items)
              {'label': it.label, 'bytes': it.bytes},
          ],
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    '已清除 ${items.length} 檔／${(freed / 1024).toStringAsFixed(0)}KB')),
          );
          await _load(); // [Blue 令] 刷新除痕歷史
        }
      }
    } finally {
      if (mounted) setState(() => _scrubBusy = false);
    }
  }

  Future<void> _load() async {
    _scrubHistory = await ScrubHistoryStore.instance.load(limit: 14);
    final raw = await DataPathGate.instance.recent(limit: 500);
    // UI 側過濾 7 天（ledger 90 天環形，recent 拉最近 500 筆足夠總覽）
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final entries = raw.where((e) => e.ts.isAfter(weekAgo)).toList();
    if (!mounted) return;
    setState(() {
      _rows = _aggregate(entries);
      _loading = false;
    });
  }

  /// host×purpose×grade 聚合（同款組合合併計數——總覽不是流水帳）
  List<AggregatedEntry> _aggregate(List<SovereigntyEntry> entries) {
    final map = <String, AggregatedEntry>{};
    for (final e in entries) {
      final key = '${e.endpointHost}|${e.purpose.wire}|${e.grade.wire}';
      final cur = map[key];
      if (cur == null) {
        map[key] = AggregatedEntry(
          host: e.endpointHost,
          purpose: e.purpose,
          grade: e.grade,
          count: 1,
          bytes: e.payloadBytes,
          lastTs: e.ts,
        );
      } else {
        cur.count++;
        cur.bytes += e.payloadBytes;
        if (e.ts.isAfter(cur.lastTs)) cur.lastTs = e.ts;
      }
    }
    final rows = map.values.toList()
      ..sort((a, b) => b.lastTs.compareTo(a.lastTs));
    return rows.take(12).toList(); // UI 上限 12 列——總覽不是無限清單
  }

  String _purposeLabel(DataPathPurpose p) => switch (p) {
        DataPathPurpose.mainChat => '主對話',
        DataPathPurpose.memoryExtract => '記憶提取',
        DataPathPurpose.vision => '照片分析',
        DataPathPurpose.delegate => '委派任務',
        DataPathPurpose.review => '內容審查',
        DataPathPurpose.slotWeb => '插槽流量', // [C4]
      };

  String _gradeLabel(DataPathGrade g) => switch (g) {
        DataPathGrade.green => '本地',
        DataPathGrade.yellow => '直連',
        DataPathGrade.red => '已攔截',
      };

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} 分鐘前';
    if (d.inHours < 24) return '${d.inHours} 小時前';
    return '${d.inDays} 天前';
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return BridgeCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined,
                    color: colors.accentBlue, size: 16),
                const SizedBox(width: 8),
                SelectableText('資料路徑總覽',
                    style:
                        TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
                const Spacer(),
                if (_rows.any((r) => r.grade == DataPathGrade.red))
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.accentRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('有攔截事件',
                        style: TierStyle.of(context, Tier.listItemMeta)
                            .toTextStyle()
                            .copyWith(color: colors.accentRed)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              '最近 7 天，你的資料去了哪——每一筆對外請求都有紀錄，只保留 90 天。',
              style: TierStyle.of(context, Tier.listItemSubtitle).toTextStyle(),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  '還沒有任何對外請求——資料都在這台機器上。',
                  style: TierStyle.of(context, Tier.listItemSubtitle)
                      .toTextStyle(),
                ),
              )
            else
              ..._rows.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: switch (r.grade) {
                              DataPathGrade.green => colors.accentGreen,
                              DataPathGrade.yellow => colors.accentYellow,
                              DataPathGrade.red => colors.accentRed,
                            },
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 150,
                          child: SelectableText(r.host,
                              style: TierStyle.of(context, Tier.listItemTitle)
                                  .toTextStyle()),
                        ),
                        SizedBox(
                          width: 80,
                          child: Text(_purposeLabel(r.purpose),
                              style:
                                  TierStyle.of(context, Tier.listItemSubtitle)
                                      .toTextStyle()),
                        ),
                        SizedBox(
                          width: 64,
                          child: Text('${r.count} 次',
                              style:
                                  TierStyle.of(context, Tier.listItemSubtitle)
                                      .toTextStyle()),
                        ),
                        Expanded(
                          child: Text('${_gradeLabel(r.grade)} · ${_ago(r.lastTs)}',
                              style:
                                  TierStyle.of(context, Tier.listItemMeta)
                                  .toTextStyle()),
                        ),
                      ],
                    ),
                  )),
            const SizedBox(height: 8),
            // [資料主權 P1] 自動除痕開關（預設開）＋一鍵除痕（dry-run→確認→真刪）
            Row(
              children: [
                Switch(
                  value: _autoScrub,
                  onChanged: (on) async {
                    await TraceScrubber.instance.setAutoEnabled(on);
                    if (mounted) setState(() => _autoScrub = on);
                  },
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('每天自動清理外傳暫存（超過 2 小時的截幀／提示暫存／縮圖快取）',
                      style: TierStyle.of(context, Tier.listItemSubtitle)
                          .toTextStyle()),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _scrubBusy ? null : _runManualScrub,
                  icon: _scrubBusy
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cleaning_services, size: 14),
                  label: const Text('一鍵除痕'),
                ),
              ],
            ),
            // [Blue 令 2026-10-17] 除痕歷史——什麼時候清了什麼、清了多大
            if (_scrubHistory.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText('除痕歷史（最近 ${_scrubHistory.length} 次）',
                  style: TierStyle.of(context, Tier.listItemTitle)
                      .toTextStyle()),
              const SizedBox(height: 4),
              ..._scrubHistory.map((h) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(
                              '${h.ts.month.toString().padLeft(2, '0')}/${h.ts.day.toString().padLeft(2, '0')} ${h.ts.hour.toString().padLeft(2, '0')}:${h.ts.minute.toString().padLeft(2, '0')}',
                              style: TierStyle.of(context, Tier.listItemMeta)
                                  .toTextStyle()
                                  .copyWith(color: colors.textMuted)),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(h.trigger == 'manual' ? '手動' : '自動',
                              style: TierStyle.of(context, Tier.listItemMeta)
                                  .toTextStyle()
                                  .copyWith(
                                      color: h.trigger == 'manual'
                                          ? colors.accentMiro
                                          : colors.textMuted)),
                        ),
                        Expanded(
                          child: Text(
                              '${h.files} 檔・${(h.bytes / 1024).toStringAsFixed(0)}KB'
                              '（${h.items.map((i) => i['label']).take(3).join('、')}${h.items.length > 3 ? ' 等' : ''}）',
                              overflow: TextOverflow.ellipsis,
                              style: TierStyle.of(context, Tier.listItemMeta)
                                  .toTextStyle()
                                  .copyWith(color: colors.textMuted)),
                        ),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 8),
            SelectableText(
              '🟢 本地封閉迴路（資料不出這台機器）　🟡 你的金鑰直連 provider（橋樑不經手）　🔴 已攔截（白名單外，請求未發出）',
              style: TierStyle.of(context, Tier.listItemMeta).toTextStyle()
                  .copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class AggregatedEntry {
  final String host;
  final DataPathPurpose purpose;
  final DataPathGrade grade;
  int count;
  int bytes;
  DateTime lastTs;
  AggregatedEntry({
    required this.host,
    required this.purpose,
    required this.grade,
    required this.count,
    required this.bytes,
    required this.lastTs,
  });
}
