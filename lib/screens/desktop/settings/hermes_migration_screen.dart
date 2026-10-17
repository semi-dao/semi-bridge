// hermes_migration_screen.dart
// [WS-3 2026-09-13 Blue 拍板] 大搬家——Blue 要從頭體驗完整流程
// 系統設定 → 大搬家 → 掃描 → 勾選行李 → 執行 → 報告
//
// 流程三階段：
// 1. scan：掃描 Hermes 目錄，產出可遷移清單（每項可勾選、標註處置）
// 2. execute：逐項搬遷（進度條＋每項結果）
// 3. report：報告（成功/跳過/失敗＋原因）——寧紅字不靜默丟包

import 'package:flutter/material.dart';

import '../../../services/hermes_migration_service.dart';
import '../../../widgets/file_export_panel.dart'; // [Blue 令 2026-10-17] 匯出中心——一個搬進一個搬出
import '../../../theme/bridge_design_system.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

class HermesMigrationScreen extends StatefulWidget {
  const HermesMigrationScreen({super.key});

  @override
  State<HermesMigrationScreen> createState() => _HermesMigrationScreenState();
}

enum _MigrationPhase { idle, scanning, checklist, executing, report }

class _HermesMigrationScreenState extends State<HermesMigrationScreen> {
  final _service = HermesMigrationService();
  _MigrationPhase _phase = _MigrationPhase.idle;
  List<MigrationItem> _items = [];
  MigrationReport? _report;
  int _progressDone = 0;
  int _progressTotal = 0;
  String _progressTitle = '';

  Future<void> _scan() async {
    setState(() => _phase = _MigrationPhase.scanning);
    await Future.delayed(const Duration(milliseconds: 400)); // 掃描動畫感
    final items = await _service.scan();
    if (!mounted) return;
    setState(() {
      _items = items;
      _phase = _MigrationPhase.checklist;
    });
  }

  Future<void> _execute() async {
    setState(() => _phase = _MigrationPhase.executing);
    final report = await _service.execute(
      _items,
      onProgress: (done, total, title) {
        if (!mounted) return;
        setState(() {
          _progressDone = done;
          _progressTotal = total;
          _progressTitle = title;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _report = report;
      _phase = _MigrationPhase.report;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return Container(
      color: ds.canvas,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(BridgeDS.spaceLG),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('大搬家',
                style: TierStyle.of(context, Tier.appDisplayLarge).toTextStyle()),
            const SizedBox(height: 8),
            SelectableText(
              '把 Hermes 上的行李搬到橋樑 App——人格、記憶、排程、對話史。',
              style: ds.caption.copyWith(
                  fontSize: 14, color: ds.textMuted),
            ),
            const SizedBox(height: BridgeDS.spaceXL),
            switch (_phase) {
              _MigrationPhase.idle => _buildIdle(ds),
              _MigrationPhase.scanning => _buildScanning(ds),
              _MigrationPhase.checklist => _buildChecklist(ds),
              _MigrationPhase.executing => _buildExecuting(ds),
              _MigrationPhase.report => _buildReport(ds),
            },
          ],
        ),
      ),
    );
  }

  Widget _buildIdle(BridgeDSColors ds) => Card(
        color: ds.surfaceElevated,
        child: Padding(
          padding: const EdgeInsets.all(BridgeDS.spaceXL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.home_work_outlined, color: ds.accentMiro, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    '搬進新家前，先看看要帶什麼行李',
                    style: ds.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              SelectableText(
                '大搬家會掃描 ~/.hermes 目錄（排程任務、對話史、分身記憶），'
                '列出可遷移清單讓你逐項勾選。搬的是副本——Hermes 原檔一律不動，'
                '隨時回得去。',
                style: ds.body.copyWith(color: ds.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.travel_explore_outlined),
                label: const Text('開始掃描行李'),
              ),
            ],
          ),
        ),
      );

  Widget _buildScanning(BridgeDSColors ds) => Card(
        color: ds.surfaceElevated,
        child: Padding(
          padding: const EdgeInsets.all(BridgeDS.spaceXL),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              SelectableText('正在掃描 ~/.hermes…',
                  style: ds.body.copyWith(color: ds.textSecondary)),
            ],
          ),
        ),
      );

  Widget _buildChecklist(BridgeDSColors ds) => Card(
        color: ds.surfaceElevated,
        child: Padding(
          padding: const EdgeInsets.all(BridgeDS.spaceLG),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: SelectableText(
                    '行李清單（${_items.where((i) => i.selected).length}/${_items.length} 勾選）',
                    style: ds.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() =>
                      _phase = _MigrationPhase.idle),
                  child: const Text('重新掃描'),
                ),
              ]),
              const SizedBox(height: 8),
              for (final item in _items)
                CheckboxListTile(
                  value: item.selected,
                  onChanged: (v) => setState(() => item.selected = v ?? false),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Row(children: [
                    _dispositionChip(ds, item.disposition),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(item.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                  subtitle: Text(item.detail,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              const SizedBox(height: 12),
              Row(children: [
                FilledButton.icon(
                  onPressed: _items.any((i) => i.selected) ? _execute : null,
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: Text(
                      '開始搬家（${_items.where((i) => i.selected).length} 項）'),
                ),
              ]),
            ],
          ),
        ),
      );

  Widget _dispositionChip(BridgeDSColors ds, String d) {
    final (label, color) = switch (d) {
      'reincarnate' => ('轉世', Colors.purple),
      'skip' => ('不遷', Colors.grey),
      _ => ('直遷', Colors.teal),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(label,
          style: ds.small.copyWith(color: color, fontSize: 10)),
    );
  }

  Widget _buildExecuting(BridgeDSColors ds) => Card(
        color: ds.surfaceElevated,
        child: Padding(
          padding: const EdgeInsets.all(BridgeDS.spaceXL),
          child: Column(
            children: [
              CircularProgressIndicator(
                value: _progressTotal == 0
                    ? null
                    : _progressDone / _progressTotal,
              ),
              const SizedBox(height: 16),
              SelectableText(
                  '搬家中：$_progressTitle（$_progressDone/$_progressTotal）',
                  style: ds.body),
              const SizedBox(height: 8),
              SelectableText('Hermes 原檔保持不動——這是複製，不是剪貼',
                  style: ds.caption.copyWith(color: ds.textMuted)),
            ],
          ),
        ),
      );

  Widget _buildReport(BridgeDSColors ds) => Card(
        color: ds.surfaceElevated,
        child: Padding(
          padding: const EdgeInsets.all(BridgeDS.spaceLG),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(
                  _report!.skippedCount == 0
                      ? Icons.celebration_outlined
                      : Icons.info_outline,
                  color: _report!.skippedCount == 0
                      ? Colors.green
                      : Colors.orange,
                ),
                const SizedBox(width: 8),
                SelectableText(
                  '搬家完成：${_report!.successCount} 項成功、${_report!.skippedCount} 項未成',
                  style: ds.body.copyWith(fontWeight: FontWeight.w600),
                ),
              ]),
              const SizedBox(height: 12),
              for (final r in _report!.results)
                ListTile(
                  dense: true,
                  leading: Icon(
                    r.status == 'done' ? Icons.check_circle : Icons.error_outline,
                    color: r.status == 'done' ? Colors.green : Colors.red,
                    size: 18,
                  ),
                  title: Text(r.item.title),
                  subtitle: Text(r.note, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              const SizedBox(height: 12),
              SelectableText(
                '完整報告：~/Library/Application Support/farm.semiwasabi.bridgeApp/migration_report.json',
                style: ds.caption.copyWith(color: ds.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 12),
              Row(children: [
                OutlinedButton(
                  onPressed: () => setState(() {
                    _phase = _MigrationPhase.idle;
                    _report = null;
                  }),
                  child: const Text('完成'),
                ),
              ]),
            ],
          ),
        ),
      );
}
