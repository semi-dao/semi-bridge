// memory_layer_entries_view.dart — [H2/M5+ 2026-10-07 Blue 令 v2]
// 主區中央視圖：側欄點層 → 這裡顯示該層全部記憶，內容可編輯（Blue 要求）。
// 佔用主區（蓋過素材牆/檔案列表）——層瀏覽是第一公民，不只是大腦記憶區的附屬。
// 設計鐵則：Tier + BridgeDSColors；AlertDialog 走 Tier 對應表。

import 'package:flutter/material.dart';

import '../../services/memory_layer_service.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

class MemoryLayerEntriesView extends StatefulWidget {
  final MemoryLayer layer;
  const MemoryLayerEntriesView({super.key, required this.layer});

  @override
  State<MemoryLayerEntriesView> createState() => _MemoryLayerEntriesViewState();
}

class _MemoryLayerEntriesViewState extends State<MemoryLayerEntriesView> {
  List<LayerEntry> _entries = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MemoryLayerEntriesView old) {
    super.didUpdateWidget(old);
    if (old.layer != widget.layer) _load();
  }

  void _load() {
    try {
      setState(() {
        _entries = MemoryLayerService.instance.entriesFor(widget.layer);
        _loaded = true;
      });
    } catch (_) {
      setState(() => _loaded = true);
    }
  }

  void _openEditor(LayerEntry e) {
    final titleCtl = TextEditingController(text: e.title);
    final contentCtl = TextEditingController(text: e.content);
    final ds = BridgeDSColors.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ds.surfaceElevated,
        title: Text('編輯記憶（${widget.layer.code}）',
            style: TierStyle.of(ctx, Tier.cardHeroTitle).toTextStyle()),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtl,
                style: TierStyle.of(ctx, Tier.cardTitle).toTextStyle(),
                decoration: InputDecoration(
                  labelText: '標題',
                  labelStyle: TierStyle.of(ctx, Tier.cardCaption).toTextStyle(),
                  border: OutlineInputBorder(
                      borderSide: BorderSide(color: ds.borderSubtle)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtl,
                maxLines: 8,
                style: TierStyle.of(ctx, Tier.cardBody)
                    .toTextStyle()
                    .copyWith(height: 1.5),
                decoration: InputDecoration(
                  labelText: '內容',
                  alignLabelWithHint: true,
                  labelStyle: TierStyle.of(ctx, Tier.cardCaption).toTextStyle(),
                  border: OutlineInputBorder(
                      borderSide: BorderSide(color: ds.borderSubtle)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消',
                style: TierStyle.of(ctx, Tier.cardBody).toTextStyle()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ds.accentPurple),
            onPressed: () {
              try {
                MemoryLayerService.instance.updateEntry(
                  e.id,
                  title: titleCtl.text.trim(),
                  content: contentCtl.text.trim(),
                );
              } catch (err) {
                debugPrint('[MemoryLayer] 編輯失敗: $err');
              }
              Navigator.pop(ctx);
              _load(); // 重新載入顯示新內容
            },
            child: Text('儲存',
                style: TierStyle.of(ctx, Tier.cardBody)
                    .toTextStyle()
                    .copyWith(
                        color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final layer = widget.layer;
    final isWorking = layer.domain == Domain.working;
    final tone = isWorking ? ds.accentPurple : ds.accentBlue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 層標題列 ──
        Padding(
          padding: const EdgeInsets.all(BridgeDS.spaceMD),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  layer.code,
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: tone, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text('${layer.label}（${_entries.length} 條）',
                  style: TierStyle.of(context, Tier.cardHeroTitle)
                      .toTextStyle()),
              if (layer.softCapBytes > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '軟上限 ${(layer.softCapBytes / 1024).toStringAsFixed(0)}KB',
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: ds.textMuted),
                ),
              ],
              const Spacer(),
              Text(
                '點條目可編輯',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: ds.textMuted),
              ),
            ],
          ),
        ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _entries.isEmpty
                  ? Center(
                      child: Text(
                        '這一層還沒有記憶',
                        style: TierStyle.of(context, Tier.cardBody)
                            .toTextStyle()
                            .copyWith(color: ds.textMuted),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: BridgeDS.spaceMD),
                      itemCount: _entries.length > 200 ? 200 : _entries.length,
                      itemBuilder: (_, i) =>
                          _buildEntryCard(_entries[i], tone, ds),
                    ),
        ),
      ],
    );
  }

  Widget _buildEntryCard(LayerEntry e, Color tone, BridgeDSColors ds) {
    return GestureDetector(
      onTap: () => _openEditor(e),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ds.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ds.borderSubtle, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TierStyle.of(context, Tier.cardTitle).toTextStyle()
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.edit_outlined, size: 13, color: ds.textMuted),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              e.content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle()
                  .copyWith(color: ds.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
