// album_screen.dart
// [時間感 L4 2026-09-13] 相簿視圖——家的記憶按時間排列成一本真的相簿。
//
// 「翻頁就是翻日子」——一頁=一天（時間為骨架），
// 每頁收該日的代表訊息（意義為血肉，最多 3 則）。
// 來源：家庭田野提案 L4「擁抱時間而非只防錯」。
//
// 設計守則：BridgeDS tier 系統（禁寫死顏色）、排版走 TierStyle。

import 'package:flutter/material.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../../theme/bridge_design_system.dart';
import '../../services/causal/time_sense_service.dart';

/// 相簿視圖——按日子翻頁的記憶
class AlbumScreen extends StatefulWidget {
  final String? companionId;
  const AlbumScreen({super.key, this.companionId});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  List<AlbumPage> _pages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pages = await TimeSenseService.albumPages(companionId: widget.companionId);
    if (!mounted) return;
    setState(() {
      _pages = pages;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pages.isEmpty) {
      return Center(
        child: Text(
          '相簿還是空的——開始對話，日子就會在這裡累積。',
          style: TierStyle.of(context, Tier.cardBody)
              .toTextStyle()
              .copyWith(color: colors.textMuted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Text(
            '相簿 · ${_pages.length} 個日子',
            style: TierStyle.of(context, Tier.appHeadline).toTextStyle(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            '翻頁就是翻日子——最新的在最前面。',
            style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(
                  color: colors.textMuted,
                ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: PageView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _pages.length,
            itemBuilder: (context, i) {
              final page = _pages[i];
              return _AlbumPageCard(page: page, index: i, total: _pages.length);
            },
          ),
        ),
      ],
    );
  }
}

class _AlbumPageCard extends StatelessWidget {
  final AlbumPage page;
  final int index;
  final int total;
  const _AlbumPageCard({required this.page, required this.index, required this.total});

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    final date = DateTime.tryParse('${page.dateKey}T00:00:00');
    final weekday = date == null
        ? ''
        : '星期${['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1]}';

    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                page.dateKey,
                style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle(),
              ),
              Text(
                weekday,
                style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(
                      color: colors.textMuted,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: page.excerpts.isEmpty
                ? Text(
                    '（這一天安安靜靜）',
                    style: TierStyle.of(context, Tier.cardBody)
                        .toTextStyle()
                        .copyWith(color: colors.textMuted),
                  )
                : ListView.separated(
                    itemCount: page.excerpts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 6, right: 12),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: colors.accentYellow,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            page.excerpts[i],
                            style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            '${index + 1} / $total',
            style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(
                  color: colors.textMuted,
                ),
          ),
        ],
      ),
    );
  }
}
