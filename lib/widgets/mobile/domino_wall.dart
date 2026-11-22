import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';

import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

// ═══════════════════════════════════════════════════
// 🀫 骨牌牆——SPEC §8.8/8.8a/8.8b（2026-11-12 Blue 拍板）
//
// 四種磚：
//   ① hero 大格（滿寬）＝最新內容（§8.8b 新鮮度恆贏）
//   ② 矮長條（~62% 文＋38% 圖，或反向）
//   ③ 小方格 2～3 格（次要圖/時刻卡混排）
//   ④ 資料矮條（滿寬，巡查數據）
// 滿版：填滿至 tab bar 呼吸空隙，禁止大區域純底色。
// 無中線：列分割點刻意不對齊（sha256 決定列內比例）。
// ═══════════════════════════════════════════════════

/// 牆的內容模型（一格＝一面牆）。
class DominoWallContent {
  /// hero 圖（最新）——base64 或 bytes
  final Uint8List? heroImage;
  final String heroCaption;

  /// 矮長條句子
  final String quote;
  final String quoteSource;

  /// 矮長條小圖（可空＝純文字條）
  final Uint8List? stripImage;

  /// 小方格圖組（次要）
  final List<Uint8List> minis;
  final List<String> miniTags;

  /// 時刻卡（小方格之一）
  final String momentTitle;
  final String momentDetail;

  /// 資料矮條
  final String dataValue;
  final String dataLabel;

  /// [2026-11-21 此刻頁收尾·C] 資料磚縮圖（可空）——非空時 _DataBrick 顯示
  /// 縮圖（cover＋左下角「N 頁」小標籤），空＝fallback 原 value/label 文字模式。
  final Uint8List? dataThumb;

  /// [此刻頁 v2] 磚對應的 vault 路徑（點開檢視用）＋點開回呼。
  final String heroPath;
  final String stripPath;
  final List<String> miniPaths;
  final String quotePath;
  final ValueChanged<String>? onImageTap; // 圖磚點開（傳 path → 全圖檢視）
  final ValueChanged<String>? onTextTap; // 文字磚點開（傳 path → 全文檢視）

  const DominoWallContent({
    this.heroImage,
    this.heroCaption = '',
    this.quote = '',
    this.quoteSource = '',
    this.stripImage,
    this.minis = const [],
    this.miniTags = const [],
    this.momentTitle = '',
    this.momentDetail = '',
    this.dataValue = '',
    this.dataLabel = '',
    this.dataThumb,
    this.heroPath = '',
    this.stripPath = '',
    this.miniPaths = const [],
    this.quotePath = '',
    this.onImageTap,
    this.onTextTap,
  });
}

class DominoWall extends StatelessWidget {
  final DominoSlotInfo slot;
  final DominoWallContent content;

  const DominoWall({super.key, required this.slot, required this.content});

  /// sha256(YYYYMMDD|k) → 穩定隨機源（列分割點不對齊用）
  static int _hashSeed(String dateKey, int k, String salt) {
    final d = crypto.sha256
        .convert(utf8.encode('$dateKey|$k|$salt'))
        .toString()
        .substring(0, 8);
    return int.parse(d, radix: 16);
  }

  @override
  Widget build(BuildContext context) {
    final seed = _hashSeed(slot.dateKey, slot.k, 'wall');
    // 列內分割比例：0.60~0.65 浮動（黃金 ±抖動）——刻意列間不對齊
    final splitA = 0.60 + (seed % 60) / 1000; // 第一長條分割
    final splitB = 0.38 + ((seed >> 8) % 50) / 1000; // 第二長條（反向）
    final miniCount = content.minis.length;

    // [2026-11-17 v2 修] 拆掉 SingleChildScrollView(AlwaysScrollable)——
    // 牆高=視口高永不真的滾動，但 AlwaysScrollable 會在手勢競技場搶縱向拖，
    // 外層 PageView（縱向翻頁）翻不了頁。下拉重抓已由外層 RefreshIndicator 掛。
    return LayoutBuilder(builder: (context, constraints) {
      final wallH = constraints.maxHeight;

      // [此刻頁 v2] 磚點開回呼包殼（有路徑有才掛手勢）
      Widget tapWrap(String path, bool isImage, Widget child) {
        final cb = isImage ? content.onImageTap : content.onTextTap;
        if (cb == null || path.isEmpty) return child;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => cb(path),
          child: child,
        );
      }

      return SizedBox(
        height: wallH,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ① hero：最新內容（§8.8b）
          Expanded(
            flex: 42,
            child: tapWrap(
              content.heroPath,
              true,
              _HeroBrick(
                image: content.heroImage,
                caption: content.heroCaption,
                fresh: true,
              ),
            ),
          ),
          const SizedBox(height: 7),
          // ② 矮長條：文（62%）＋圖（38%）
          SizedBox(
            height: 88,
            child: Row(
              children: [
                Expanded(
                  flex: (splitA * 1000).round(),
                  child: tapWrap(
                    content.quotePath,
                    false,
                    _QuoteBrick(
                      text: content.quote,
                      source: content.quoteSource,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  flex: ((1 - splitA) * 1000).round(),
                  child: tapWrap(
                    content.stripPath,
                    true,
                    _ImageBrick(image: content.stripImage),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          // ③ 小方格：次要圖×n＋時刻卡
          SizedBox(
            height: 132,
            child: Row(
              children: [
                for (var i = 0; i < miniCount && i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 7),
                  Expanded(
                    child: tapWrap(
                      i < content.miniPaths.length
                          ? content.miniPaths[i]
                          : '',
                      true,
                      _MiniBrick(
                        image: content.minis[i],
                        tag: i < content.miniTags.length
                            ? content.miniTags[i]
                            : '',
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 7),
                // [2026-11-20 此刻頁三刀·刀②] 時刻卡改吃真內容（momentTitle/momentDetail），
                // 原 hardcode 死文案降級為 fallback（空字串時才顯示）。
                Expanded(
                  child: _MomentBrick(
                    title: content.momentTitle,
                    detail: content.momentDetail,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          // ⑤ 第二矮長條（反向：圖 38%＋文 62%）——用 slot 資訊（時間數學可視化）
          SizedBox(
            height: 80,
            child: Row(
              children: [
                Expanded(
                  flex: ((1 - splitB) * 1000).round(),
                  child: _SlotInfoBrick(slot: slot),
                ),
                const SizedBox(width: 7),
                // [2026-11-20 此刻頁三刀·刀③] 資料矮條改吃 content.dataValue/dataLabel，
                // 原「同步中…」降級 fallback。
                Expanded(
                  flex: (splitB * 1000).round(),
                  child: _DataBrick(
                    value: content.dataValue,
                    label: content.dataLabel,
                    thumb: content.dataThumb,
                    // 縮圖模式左下角小標籤：「· N 頁」尾段（無則整個 label）
                    badge: content.dataLabel.contains('·')
                        ? content.dataLabel.split('·').last.trim()
                        : content.dataLabel,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
        ),
      );
    });
  }
}

/// 格資訊（牆外層組好傳入——避免 widget 依賴 engine）。
class DominoSlotInfo {
  final int k;
  final int total;
  final String sourceLabel;
  final String windowLabel;
  final String dateKey;

  /// [2026-11-20 此刻頁三刀·刀③] 此格時間窗內的資產數（池 modified 計數）。
  /// null＝尚未計算／不適用（不顯示這行，誠實不編數字）。
  final int? slotAssetCount;

  const DominoSlotInfo({
    required this.k,
    required this.total,
    required this.sourceLabel,
    required this.windowLabel,
    required this.dateKey,
    this.slotAssetCount,
  });
}

// ── 磚元件 ──────────────────────────────────────

class _HeroBrick extends StatelessWidget {
  final Uint8List? image;
  final String caption;
  final bool fresh;

  const _HeroBrick({this.image, required this.caption, this.fresh = false});

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSubtle),
        color: colors.surfaceElevated,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            Image.memory(
              image!,
              fit: BoxFit.cover,
              opacity: const AlwaysStoppedAnimation(.94),
            )
          else
            Center(
              child: Icon(
                Icons.image_outlined,
                size: 42,
                color: colors.textTertiary,
              ),
            ),
          if (caption.isNotEmpty)
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                padding: const EdgeInsets.only(
                  left: 14,
                  right: 14,
                  top: 26,
                  bottom: 11,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Row(
                  children: [
                    if (fresh)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.fiber_new_outlined,
                          size: 14,
                          color: colors.accentYellow,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TierStyle.of(
                          context,
                          Tier.cardCaption,
                        ).toTextStyle().copyWith(color: colors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuoteBrick extends StatelessWidget {
  final String text;
  final String source;

  const _QuoteBrick({required this.text, required this.source});

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: colors.surfaceElevated,
        border: Border.all(color: colors.borderSubtle),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(
              context,
              Tier.cardBody,
            ).toTextStyle().copyWith(fontWeight: FontWeight.w300),
          ),
          if (source.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              source,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(
                context,
                Tier.cardCaption,
              ).toTextStyle().copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImageBrick extends StatelessWidget {
  final Uint8List? image;

  const _ImageBrick({this.image});

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: colors.borderSubtle),
        color: colors.surfaceElevated,
      ),
      clipBehavior: Clip.antiAlias,
      child: image != null
          ? Image.memory(
              image!,
              fit: BoxFit.cover,
              opacity: const AlwaysStoppedAnimation(.88),
            )
          : Icon(Icons.image_outlined, color: colors.textTertiary),
    );
  }
}

class _MiniBrick extends StatelessWidget {
  final Uint8List? image;
  final String tag;

  const _MiniBrick({this.image, this.tag = ''});

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: colors.borderSubtle),
        color: colors.surfaceElevated,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            Image.memory(
              image!,
              fit: BoxFit.cover,
              opacity: const AlwaysStoppedAnimation(.86),
            )
          else
            Center(
              child: Icon(
                Icons.image_outlined,
                size: 26,
                color: colors.textTertiary,
              ),
            ),
          if (tag.isNotEmpty)
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    tag,
                    style: TierStyle.of(
                      context,
                      Tier.cardCaption,
                    ).toTextStyle().copyWith(fontSize: 9),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 時刻卡小方格——暖金調（視覺稿定案）
/// [2026-11-20 此刻頁三刀·刀②] 改吃 content.momentTitle/momentDetail 真內容；
/// 空字串降級顯示原 hardcode 文案（fallback，骨架 §8.8a 不動）。
class _MomentBrick extends StatelessWidget {
  final String title;
  final String detail;

  const _MomentBrick({this.title = '', this.detail = ''});

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: colors.accentYellow.withValues(alpha: 0.08),
        border: Border.all(color: colors.accentYellow.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // 真內容優先；空→fallback 原死文案（誠實：非罐頭句而是骨架預設）
            title.isNotEmpty ? title : '時 刻',
            style: TierStyle.of(context, Tier.cardTitle).toTextStyle(),
          ),
          const SizedBox(height: 4),
          Text(
            detail.isNotEmpty ? detail : '時針與分針又相遇了一次',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(
              context,
              Tier.cardCaption,
            ).toTextStyle().copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// 格資訊條（時間數學可視化——第 k/22 格＋時間窗）
class _SlotInfoBrick extends StatelessWidget {
  final DominoSlotInfo slot;

  const _SlotInfoBrick({required this.slot});

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: colors.surfaceElevated,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第 ${slot.k} / ${slot.total} 格 · ${slot.sourceLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(
              context,
              Tier.cardCaption,
            ).toTextStyle().copyWith(letterSpacing: 1.5),
          ),
          const SizedBox(height: 3),
          Text(
            slot.windowLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(
              context,
              Tier.cardCaption,
            ).toTextStyle().copyWith(color: colors.textTertiary),
          ),
          // [2026-11-20 此刻頁三刀·刀③] 此格時間窗內資產數（有才算，null 不顯示）
          if (slot.slotAssetCount != null) ...[
            const SizedBox(height: 3),
            Text(
              '此格資產 ${slot.slotAssetCount} 件',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(
                context,
                Tier.cardCaption,
              ).toTextStyle().copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// 資料矮條——藍調（巡查數據）
/// [2026-11-20 此刻頁三刀·刀③] 改吃 content.dataValue/dataLabel 真數據；
/// 空值降級顯示原「同步中…」（fallback，骨架 §8.8a 不動）。
/// [2026-11-21 此刻頁收尾·C] thumb 非空→縮圖磚模式：圖 fit cover 圓角同其他磚、
/// 左下角「N 頁」小標籤（Tier.cardCaption＋半透明底）；空→原 value/label 文字模式。
class _DataBrick extends StatelessWidget {
  final String value;
  final String label;
  final Uint8List? thumb;
  final String badge;

  const _DataBrick({this.value = '', this.label = '', this.thumb, this.badge = ''});

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    // 縮圖模式：圖＋左下角小標籤（§8.8a 80px 矮條骨架由父層 SizedBox 控制，不動）
    if (thumb != null && thumb!.isNotEmpty) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: colors.accentBlue.withValues(alpha: 0.3)),
          color: colors.surfaceElevated,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              thumb!,
              fit: BoxFit.cover,
              opacity: const AlwaysStoppedAnimation(.88),
            ),
            if (badge.isNotEmpty)
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      // 半透明底：token 化（BridgeDS.darkPanel ＋ alpha），禁裸黑
                      color: BridgeDS.darkPanel.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(
                        context,
                        Tier.cardCaption,
                      ).toTextStyle().copyWith(
                            color: colors.textPrimary,
                          ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: colors.accentBlue.withValues(alpha: 0.07),
        border: Border.all(color: colors.accentBlue.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // 真 label（如「VAULT 素材池 · N 頁」）優先；空→fallback「VAULT」
            label.isNotEmpty ? label : 'VAULT',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(context, Tier.cardCaption)
                .toTextStyle()
                .copyWith(color: colors.textTertiary, letterSpacing: 2),
          ),
          const SizedBox(height: 2),
          Text(
            // 真 value（池筆數）優先；空→fallback「同步中…」
            value.isNotEmpty ? value : '同步中…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(
              context,
              Tier.cardTitle,
            ).toTextStyle().copyWith(color: colors.accentBlue),
          ),
        ],
      ),
    );
  }
}
