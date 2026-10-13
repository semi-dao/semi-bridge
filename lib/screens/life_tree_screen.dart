// life_tree_screen.dart
// [小葵 2026-10-05 Blue 令] 生命樹觀景窗——長在羅盤裡。
//
// 「生命樹是長在羅盤裡的，也跟羅盤有最大的關係，所以這個 UI
// 要長在羅盤頁面裡。」——Blue 2026-10-05
//
// 三個 tab：
//   🌙 夢（反思樹 life_tree_dreams）——夢卡按晚分組、時間之河往下捲
//   📜 戰役（歷史樹 agent_causal_ledger）——工具呼叫流水
//   💭 遺憾（life_tree_thought_branches）——沒走的路＋重評狀態
//
// 資料全部唯讀（真相源在 DB，寫入口是夢境系統），UI 只做觀景窗。
// 設計遵循 Tier 系統（文字層級）+ BridgeDSColors（顏色）鐵則。

import 'package:flutter/material.dart';

import 'package:bridge_app/services/life_tree/life_tree_store.dart';
import 'package:bridge_app/services/life_tree/global_notice_channel.dart';
import 'package:bridge_app/services/compass/compass_store.dart';
import 'package:bridge_app/services/compass/compass_models.dart';
import 'package:bridge_app/services/causal/causal_ledger_service.dart';
import 'package:bridge_app/screens/bridge_desktop_screen.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/theme/tier.dart';
import 'package:bridge_app/theme/tier_style.dart';

class LifeTreeScreen extends StatefulWidget {
  const LifeTreeScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<LifeTreeScreen> createState() => _LifeTreeScreenState();
}

class _LifeTreeScreenState extends State<LifeTreeScreen> {
  int _tab = 0; // 0 夢 · 1 戰役 · 2 遺憾 · 3 裁決
  // [小葵 2026-10-05 Blue 令] 展開中的傷口清單（「N 筆堆積」卡的內容）
  final Set<int> _expandedWoundCards = {};

  // ── 資料快取（開頁時抓一次；樹的節律是每天一場夢，不需要即時流）──
  List<LifeTreeDream> _dreams = const [];
  List<CausalEntry> _ledger = const [];
  List<LifeTreeThoughtBranch> _regrets = const [];
  Map<String, int> _snapshot = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      final store = LifeTreeStore.instance;
      _dreams = store.recentDreams(limit: 200);
      _regrets = store.unrevisitedBranches(limit: 50);
      _snapshot = store.snapshot();
      final ledger = CausalLedger.instance;
      ledger.unawaitedInit();
      _ledger = ledger.recentEntries(limit: 150);
    } catch (_) {
      // fail-open：讀不到就顯示空狀態
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = BridgeDSColors.of(context);
    return Container(
      color: cs.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          _tabBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView(
                padding: const EdgeInsets.all(BridgeDS.spaceLG),
                children: [
                  if (_tab == 0) ..._dreamTab(),
                  if (_tab == 1) ..._battleTab(),
                  if (_tab == 2) ..._regretTab(),
                  if (_tab == 3) ..._adjudicationTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════ Header ══════════

  Widget _header() {
    final cs = BridgeDSColors.of(context);
    final dreams = _snapshot['dreams'] ?? 0;
    final unrevisited = _snapshot['unrevisited'] ?? 0;
    return Padding(
      padding: const EdgeInsets.all(BridgeDS.spaceLG),
      child: Row(
        children: [
          if (widget.onBack != null)
            IconButton(
              icon: Icon(Icons.arrow_back, color: cs.textPrimary, size: 20),
              onPressed: widget.onBack,
              tooltip: '返回羅盤',
            ),
          Icon(Icons.park_outlined, color: cs.accentGreen,
              size: 24),
          const SizedBox(width: 8),
          Text('生命樹',
              style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$dreams 張夢卡 · $unrevisited 條遺憾待看',
              style: TextStyle(color: cs.textMuted, fontSize: 13),
            ),
          ),
          Tooltip(
            message: '她睡著時（02:00–05:00）會自動反思白天的一切，'
                '結論化為夢卡。帶〔已用於白天〕徽章的＝她真的把教訓帶在身上。',
            child:
                Icon(Icons.info_outline, size: 14, color: cs.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    final cs = BridgeDSColors.of(context);
    const tabs = [('🌙', '夢'), ('📜', '戰役'), ('💭', '遺憾'), ('⚖️', '裁決')];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceLG),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _tab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _tab == i
                      ? cs.accentPurple.withValues(alpha: 0.18)
                      : cs.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color:
                          _tab == i ? cs.accentPurple : cs.borderSubtle),
                ),
                child: Text('${tabs[i].$1} ${tabs[i].$2}',
                    style: TextStyle(
                        fontSize: 12,
                        color: _tab == i
                            ? cs.accentPurple
                            : cs.textMuted)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════ Tab 0：夢（反思樹）══════════

  List<Widget> _dreamTab() {
    final cs = BridgeDSColors.of(context);
    if (_dreams.isEmpty) {
      return [_empty('還沒有做過夢。每天 02:00–05:00 之間她會自動反思，'
          '第一場夢之後這裡就會開始長東西。')];
    }
    // 按晚分組（同 session = 同一晚）
    final byNight = <String, List<LifeTreeDream>>{};
    for (final d in _dreams) {
      final key = _nightKey(d.createdAt);
      byNight.putIfAbsent(key, () => []).add(d);
    }
    final nights = byNight.keys.toList();
    final widgets = <Widget>[];
    for (final night in nights) {
      final cards = byNight[night]!;
      widgets.add(_sectionLabel('🌙 $night 的夢（${cards.length} 張）'));
      for (final d in cards) {
        widgets.add(_dreamCard(d));
      }
      widgets.add(const SizedBox(height: BridgeDS.spaceLG));
    }
    return widgets;
  }

  Widget _dreamCard(LifeTreeDream d) {
    final cs = BridgeDSColors.of(context);
    final isEscalate = d.decision == 'escalate_to_user';
    final isPropose = d.decision == 'propose';
    final reused = d.conclusion.contains('[已用於白天·升級]');
    final healed = d.branchType == 'agent_consensus';
    final adjudicated = d.adjudicatedAt != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(
            color: isEscalate
                ? cs.accentPurple.withValues(alpha: 0.5)
                : cs.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_fmtTime(d.createdAt),
                  style: TextStyle(color: cs.textMuted, fontSize: 11)),
              const SizedBox(width: 8),
              _decisionBadge(d.decision),
              if (healed) ...[
                const SizedBox(width: 6),
                _badge('痊癒銷案', Colors.green),
              ],
              if (reused) ...[
                const SizedBox(width: 6),
                _badge('已用於白天 ✓', Colors.teal),
              ],
              if (isPropose && !adjudicated) ...[
                const SizedBox(width: 6),
                _badge('等你看', Colors.orange),
              ],
              if (adjudicated) ...[
                const SizedBox(width: 6),
                _badge('已裁決 ✓', Colors.green),
              ],
              const Spacer(),
              // [小葵 2026-10-05 Blue 令] propose 卡裁決——直接在卡上回覆給夥伴
              if ((isPropose || isEscalate) && !adjudicated)
                _adjudicateButton(d),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            d.conclusion.replaceAll('[已用於白天·升級] ', ''),
            style: TextStyle(color: cs.textPrimary, fontSize: 13, height: 1.5),
          ),
          // [小葵 2026-10-05 Blue 令] 「6 筆的內容」——傷口堆積卡可展開
          // 看每一筆的實際內容，才能判斷如何裁決
          if (d.conclusion.contains('未結案傷口')) ...[
            const SizedBox(height: 6),
            _woundExpansion(d),
          ],
          if (adjudicated && d.adjudication != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceElevated,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('你的裁決',
                      style: TextStyle(
                          color: cs.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  SelectableText(
                    d.adjudication!,
                    style: TextStyle(
                        color: cs.textPrimary,
                        fontSize: 12,
                        height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 傷口展開——「未結案傷口 N 筆堆積」卡的可展開清單
  /// （[小葵 2026-10-05 Blue 令]「沒有看到６筆的內容，我無法判斷如何裁決」）
  Widget _woundExpansion(LifeTreeDream d) {
    final cs = BridgeDSColors.of(context);
    final expanded = _expandedWoundCards.contains(d.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() {
            expanded
                ? _expandedWoundCards.remove(d.id)
                : _expandedWoundCards.add(d.id!);
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 14,
                  color: cs.accentPurple,
                ),
                const SizedBox(width: 2),
                Text(
                  expanded ? '收起傷口明細' : '查看傷口明細（每一筆的內容）',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.accentPurple,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          FutureBuilder<List<CompassPitfall>>(
            future: Future.value(
                CompassStore.instance.pendingPitfalls(limit: 30)),
            builder: (context, snap) {
              if (!snap.hasData) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('載入中…',
                      style:
                          TextStyle(color: cs.textMuted, fontSize: 11)),
                );
              }
              final pits = snap.data!;
              if (pits.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('目前沒有未結案傷口（可能已被夢境銷案）',
                      style:
                          TextStyle(color: cs.textMuted, fontSize: 11)),
                );
              }
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceElevated,
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: cs.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('未結案傷口 ${pits.length} 筆（全部器官）',
                        style: TextStyle(
                            color: cs.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    ...pits.map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.healing,
                                    size: 11, color: Colors.orange),
                                const SizedBox(width: 4),
                                Text(
                                    '${p.at.month}/${p.at.day} [${p.organId}]',
                                    style: TextStyle(
                                        color: cs.textMuted,
                                        fontSize: 10)),
                              ]),
                              const SizedBox(height: 2),
                              SelectableText(
                                _clipPitfallText(p.text),
                                style: TextStyle(
                                    color: cs.textSecondary,
                                    fontSize: 11,
                                    height: 1.4),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  /// 傷口文字裁剪：去掉標記前綴、截 240 字
  String _clipPitfallText(String raw) {
    var t = raw
        .replaceAll('【pending·傷口立案】', '')
        .replaceAll('【pending·認知傷口】', '')
        .replaceAll('【pending】', '');
    if (t.length > 240) t = '${t.substring(0, 240)}…';
    return t.trim();
  }

  /// 裁決按鈕＋對話框——送出後：①寫進樹的帳（adjudicate）
  /// ②送給 Agent 夥伴（activeChatController.sendDirectMessage）
  Widget _adjudicateButton(LifeTreeDream d) {
    final cs = BridgeDSColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _showAdjudicateDialog(d),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: cs.accentPurple.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: cs.accentPurple.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gavel_outlined, size: 12, color: cs.accentPurple),
            const SizedBox(width: 4),
            Text('裁決',
                style: TextStyle(
                    fontSize: 11,
                    color: cs.accentPurple,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _showAdjudicateDialog(LifeTreeDream d) {
    final cs = BridgeDSColors.of(context);
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: cs.surfaceElevated,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.borderSubtle)),
        title: Text('裁決這張夢卡',
            style: TextStyle(
                color: cs.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Text(
                d.conclusion,
                style:
                    TextStyle(color: cs.textSecondary, fontSize: 12),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              autofocus: true,
              style: TextStyle(color: cs.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: '你的決定與理由——會直接送給夥伴',
                hintStyle: TextStyle(color: cs.textMuted, fontSize: 12),
                filled: true,
                fillColor: cs.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.accentPurple),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('取消',
                style: TextStyle(color: cs.textMuted, fontSize: 13)),
          ),
          TextButton(
            onPressed: () {
              final verdict = controller.text.trim();
              if (verdict.isEmpty) return;
              Navigator.of(dialogContext).pop();
              _submitAdjudication(d, verdict);
            },
            child: Text('送出裁決',
                style: TextStyle(
                    color: cs.accentPurple,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _submitAdjudication(LifeTreeDream d, String verdict) {
    // ① 樹的帳
    LifeTreeStore.instance.adjudicate(d.id!, verdict);
    // ② 送給 Agent 夥伴——像使用者親口說的
    final chat = BridgeDesktopScreen.activeChatController.value;
    final plain = d.conclusion.length > 80
        ? '${d.conclusion.substring(0, 80)}…'
        : d.conclusion;
    final message = '（關於你夢裡提的議題）「$plain」\n'
        '我的裁決：$verdict';
    if (chat != null) {
      chat.sendDirectMessage(message);
    } else {
      // fallback：全域對話頻道（夥伴下次開對話看得到）
      GlobalNoticeChannel.instance.push(
        title: '主人裁決了你夢裡的議題',
        body: message,
        kind: 'dream_adjudication',
      );
    }
    _load(); // 刷新卡片顯示「已裁決 ✓」
  }

  // ══════════ Tab 1：戰役（歷史樹）══════════

  List<Widget> _battleTab() {
    if (_ledger.isEmpty) {
      return [_empty('還沒有戰役紀錄。她每次呼叫工具都會在這裡留下足跡。')];
    }
    final cs = BridgeDSColors.of(context);
    // 按天分組
    final byDay = <String, List<CausalEntry>>{};
    for (final e in _ledger) {
      final key = _dayKey(e.at);
      byDay.putIfAbsent(key, () => []).add(e);
    }
    final widgets = <Widget>[];
    for (final day in byDay.keys) {
      final entries = byDay[day]!;
      final fails =
          entries.where((e) => !e.success).length;
      widgets.add(_sectionLabel(
          '📜 $day（${entries.length} 次行動${fails > 0 ? ' · $fails 次失敗' : ''}）'));
      for (final e in entries.take(40)) {
        widgets.add(_battleRow(e));
      }
      if (entries.length > 40) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 24, bottom: 4),
          child: Text('…還有 ${entries.length - 40} 筆',
              style: TextStyle(color: cs.textMuted, fontSize: 11)),
        ));
      }
      widgets.add(const SizedBox(height: BridgeDS.spaceLG));
    }
    return widgets;
  }

  Widget _battleRow(CausalEntry e) {
    final cs = BridgeDSColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              e.success
                  ? Icons.check_circle_outline
                  : Icons.cancel_outlined,
              size: 14,
              color: e.success ? Colors.green : Colors.red.shade300),
          const SizedBox(width: 6),
          SizedBox(
            width: 56,
            child: Text(_fmtTime(e.at),
                style: TextStyle(color: cs.textMuted, fontSize: 11)),
          ),
          SizedBox(
            width: 160,
            child: Text(e.toolName,
                style: cs.labelMono.copyWith(
                    fontSize: 11, color: cs.textSecondary)),
          ),
          Expanded(
            child: Text(
              e.intervention.replaceAll('\n', ' '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════ Tab 3：裁決（待裁決/已裁決）══════════
  // [小葵 2026-10-05 Blue 令] 「我需要一個待裁決／已裁決的列表，
  // 方便我一一裁決」＋「已裁決列表顯示裁決內容＋日期，幫助我回憶」

  List<Widget> _adjudicationTab() {
    final cs = BridgeDSColors.of(context);
    // 待裁決：propose / escalate 且還沒裁決（最新在前）
    final pending = _dreams
        .where((d) =>
            (d.decision == 'propose' || d.decision == 'escalate_to_user') &&
            d.adjudicatedAt == null)
        .toList();
    // 已裁決：有 adjudicatedAt（最新裁決在前）
    final done = _dreams
        .where((d) => d.adjudicatedAt != null)
        .toList()
      ..sort((a, b) => b.adjudicatedAt!.compareTo(a.adjudicatedAt!));

    final widgets = <Widget>[];

    // ── 待裁決區 ──
    widgets.add(_sectionLabel('⚖️ 待裁決（${pending.length} 張）'));
    if (pending.isEmpty) {
      widgets.add(_empty('沒有待裁決的夢卡。她夢裡提的議題都處理完了。'));
    } else {
      for (final d in pending) {
        widgets.add(_dreamCard(d));
      }
    }

    widgets.add(const SizedBox(height: BridgeDS.spaceLG));

    // ── 已裁決區 ──
    widgets.add(_sectionLabel('✅ 已裁決（${done.length} 張）——幫助回憶'));
    if (done.isEmpty) {
      widgets.add(_empty('還沒有裁決紀錄。你裁決過的夢卡會在這裡留下'
          '你的決定與日期。'));
    } else {
      for (final d in done) {
        widgets.add(_adjudicatedCard(d));
      }
    }
    return widgets;
  }

  /// 已裁決卡——大卡顯示：原議題＋你的裁決＋日期
  Widget _adjudicatedCard(LifeTreeDream d) {
    final cs = BridgeDSColors.of(context);
    final dt = d.adjudicatedAt!;
    final dateStr =
        '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}'
        ' ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gavel, size: 12, color: Colors.green),
              const SizedBox(width: 4),
              Text('已裁決 · $dateStr',
                  style: TextStyle(
                      color: Colors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              _decisionBadge(d.decision),
            ],
          ),
          const SizedBox(height: 6),
          // 原議題（摘要）
          Text('她夢裡提的：',
              style: TextStyle(color: cs.textMuted, fontSize: 11)),
          const SizedBox(height: 2),
          SelectableText(
            d.conclusion.length > 120
                ? '${d.conclusion.substring(0, 120)}…'
                : d.conclusion,
            style: TextStyle(color: cs.textSecondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 8),
          // 你的裁決
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceElevated,
              borderRadius: BorderRadius.circular(8.0),
              border:
                  Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('你的裁決',
                    style: TextStyle(
                        color: cs.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                SelectableText(
                  d.adjudication ?? '',
                  style: TextStyle(
                      color: cs.textPrimary, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════ Tab 2：遺憾 ══════════

  List<Widget> _regretTab() {
    final cs = BridgeDSColors.of(context);
    // 全部分支（含已重評）——遗憾看得到代謝
    final store = LifeTreeStore.instance;
    final all = <LifeTreeThoughtBranch>[..._regrets];
    // unrevisitedBranches 只給未重評；已重評的另外查（snapshot 統計差）
    if (all.isEmpty && (_snapshot['thoughtBranches'] ?? 0) == 0) {
      return [_empty('沒有遺憾。她走的每條路都有想過的其他選擇，'
          '這裡記下那些沒走的路，夢裡會重看。')];
    }
    final widgets = <Widget>[];
    widgets.add(_sectionLabel(
        '💭 沒走的路（${_snapshot['unrevisited'] ?? 0} 條還沒在夢裡重看）'));
    for (final r in all) {
      widgets.add(Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: cs.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('遺憾 #${r.id}',
                    style:
                        TextStyle(color: cs.textMuted, fontSize: 11)),
                const SizedBox(width: 8),
                Text(_fmtTime(r.createdAt),
                    style: TextStyle(color: cs.textMuted, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(r.thought,
                style: TextStyle(
                    color: cs.textPrimary, fontSize: 13, height: 1.5)),
            if (r.whyNotTaken != null && r.whyNotTaken!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('當時沒走的原因：${r.whyNotTaken}',
                  style:
                      TextStyle(color: cs.textMuted, fontSize: 11)),
            ],
          ],
        ),
      ));
    }
    return widgets;
  }

  // ══════════ 共用零件 ══════════

  Widget _sectionLabel(String t) {
    final cs = BridgeDSColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t,
          style: TextStyle(
              color: cs.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _decisionBadge(String decision) {
    final map = {
      'maintain': ('維持', Colors.blueGrey),
      'propose': ('提案', Colors.orange),
      'escalate_to_user': ('請你看', Colors.purple),
      'agent_consensus': ('共識', Colors.green),
    };
    final (label, color) = map[decision] ?? (decision, Colors.blueGrey);
    return _badge(label, color);
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: color)),
    );
  }

  Widget _empty(String msg) {
    final cs = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: cs.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(Icons.nightlight_outlined,
              size: 16, color: cs.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style:
                    TextStyle(color: cs.textSecondary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  String _nightKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _dayKey(DateTime d) => _nightKey(d);

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
