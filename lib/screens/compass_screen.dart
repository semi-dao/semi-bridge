// compass_screen.dart
// 羅盤系統主頁 — 人機共視的器官地圖 + 規則中心。
// 設計依據 docs/specs/2026-09-06-compass-system.md §6（Blue 拍板：卡片群 v1）。
//
// 三區：健康總覽 / 最近變更時間線 / 器官卡片群（分組）。
// 點器官卡 → 詳情頁（規則卡列表 + 意義層編輯）。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:bridge_app/services/compass/compass_models.dart';
import 'package:bridge_app/services/compass/compass_store.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/theme/tier.dart';
import 'package:bridge_app/widgets/compass/compass_graph_view.dart';
import 'package:bridge_app/theme/tier_style.dart';
import 'package:bridge_app/widgets/trust/agent_seal.dart'; // [Blue 令] 蓋章制度
import 'package:bridge_app/screens/life_tree_screen.dart'; // [小葵 2026-10-05 Blue 令] 生命樹觀景窗
import 'package:bridge_app/services/life_tree/life_tree_store.dart'; // 入口卡統計

class CompassScreen extends StatefulWidget {
  const CompassScreen({super.key});

  @override
  State<CompassScreen> createState() => _CompassScreenState();
}

class _CompassScreenState extends State<CompassScreen> {
  // [小葵 2026-09-10 Blue 令] 圖譜/列表雙檢視
  final ValueNotifier<bool> _graphMode = ValueNotifier(true); // 預設圖譜（Blue 2026-09-10 主視覺令）
  final store = CompassStore.instance;
  StreamSubscription? _sub;
  final _selectedOrgan = ValueNotifier<String?>(null);
  // [小葵 2026-10-05 Blue 令] 生命樹觀景窗——長在羅盤裡
  bool _showLifeTree = false;

  @override
  void initState() {
    super.initState();
    _sub = store.events.listen((_) {
      if (mounted) setState(() {});
    });
    // [小葵 2026-09-07 修 bug] 點器官卡沒反應——ValueNotifier 沒掛
    // listener，值變了沒人 setState。補上後點卡→切詳情頁。
    _selectedOrgan.addListener(_onOrganSelected);
  }

  void _onOrganSelected() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _selectedOrgan.removeListener(_onOrganSelected);
    _selectedOrgan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // [小葵 2026-10-05 Blue 令] 生命樹觀景窗——長在羅盤裡的子頁
    if (_showLifeTree) {
      return LifeTreeScreen(
          onBack: () => setState(() => _showLifeTree = false));
    }
    final organs = store.organs();
    final surgeries = store.surgeries(limit: 12);
    final selectedId = _selectedOrgan.value;
    // [小葵 2026-09-11 修] 圖譜模式點光球=浮動預覽卡（不跳頁）——
    // b054504f 加浮動卡時漏了這個閘：early return 無條件攔截所有選取，
    // 圖譜模式的 Stack 浮動卡永遠走不到，點光球直接整頁跳詳情。
    // 修：只有列表模式才走整頁；圖譜模式交給 Stack 疊層。
    if (selectedId != null && !_graphMode.value) {
      return _OrganDetail(
        organId: selectedId,
        onBack: () => _selectedOrgan.value = null,
      );
    }
    return Container(
      color: BridgeDSColors.of(context).canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(surgeries),
          // [小葵 2026-09-10 Blue 令] 圖譜檢視切換
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceLG),
            child: Row(
              children: [
                _viewToggle(Icons.account_tree_outlined, '圖譜', true),
                const SizedBox(width: 6),
                _viewToggle(Icons.view_list_outlined, '列表', false),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: _graphMode,
              builder: (context, graphMode, _) => graphMode
                  ? Stack(
                      children: [
                        CompassGraphView(
                          onNodeTap: (o) => _selectedOrgan.value = o.id,
                        ),
                        // [Blue 2026-09-10] 浮動預覽卡——不跳頁，疊在
                        // 圖譜上；點細節進編輯層；可退回、可關閉
                        ValueListenableBuilder<String?>(
                          valueListenable: _selectedOrgan,
                          builder: (context, sel, _) => sel == null
                              ? const SizedBox.shrink()
                              : Align(
                                  alignment: Alignment.topRight,
                                  child: Container(
                                    width: 360,
                                    margin: const EdgeInsets.all(12),
                                    child: _OrganDetail(
                                      organId: sel,
                                      compact: true,
                                      onBack: () =>
                                          _selectedOrgan.value = null,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    )
                  : ListView(
              padding: const EdgeInsets.all(BridgeDS.spaceLG),
              children: [
                // [小葵 2026-09-10 Blue 人機共視令] 人類視角重排：
                // ①全景摘要（一眼看懂羅盤在守護什麼）
                // ②有規則的器官站前排（不要滿屏零規則空卡）
                // ③Agent 直覺地圖（agent 看得到的，人也要看得到）
                // ④無規則器官收合成一行（想看再展開）
                _panoramaSummary(),
                const SizedBox(height: BridgeDS.spaceMD),
                _lifeTreeCard(),
                const SizedBox(height: BridgeDS.spaceLG),
                _timeline(surgeries),
                const SizedBox(height: BridgeDS.spaceLG),
                _agentIntuitionMap(),
                const SizedBox(height: BridgeDS.spaceLG),
                ..._organGroups(organs),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }

  /// [小葵 2026-10-05 Blue 令] 生命樹觀景窗入口卡——
  /// 「生命樹是長在羅盤裡的」：夢（反思樹）+ 戰役（歷史樹）+ 遺憾。
  /// 點卡開生命樹頁。
  Widget _lifeTreeCard() {
    final cs = BridgeDSColors.of(context);
    Map<String, int> snap;
    try {
      snap = LifeTreeStore.instance.snapshot();
    } catch (_) {
      snap = const {};
    }
    final dreams = snap['dreams'] ?? 0;
    final regrets = snap['unrevisited'] ?? 0;
    return InkWell(
      borderRadius: BorderRadius.circular(10.0),
      onTap: () => setState(() => _showLifeTree = true),
      child: Container(
        padding: const EdgeInsets.all(BridgeDS.spaceMD),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cs.surface, cs.surfaceElevated],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: cs.borderSubtle),
        ),
        child: Row(
          children: [
            Icon(Icons.park_outlined,
                color: cs.accentPurple, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('生命樹 — 她的夢與成長',
                      style: TextStyle(
                          color: cs.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                      '$dreams 張夢卡'
                      '${regrets > 0 ? ' · $regrets 條遺憾想請你看' : ' · 遺憾清單乾淨'}'
                      ' — 點開看她睡著時反思了什麼',
                      style: TextStyle(
                          color: cs.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: cs.textMuted),
          ],
        ),
      ),
    );
  }

  /// 檢視切換鈕
  Widget _viewToggle(IconData icon, String label, bool forGraph) {
    final cs = BridgeDSColors.of(context);
    final selected = _graphMode.value == forGraph;
    return ValueListenableBuilder<bool>(
      valueListenable: _graphMode,
      builder: (context, mode, _) {
        final sel = mode == forGraph;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _graphMode.value = forGraph,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: sel ? cs.accentPurple.withValues(alpha: 0.18) : cs.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: sel ? cs.accentPurple : cs.borderSubtle),
            ),
            child: Row(children: [
              Icon(icon, size: 14, color: sel ? cs.accentPurple : cs.textMuted),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: sel ? cs.accentPurple : cs.textMuted)),
            ]),
          ),
        );
      },
    );
  }

  /// 全景摘要——一句話看懂羅盤現況
  Widget _panoramaSummary() {
    final cs = BridgeDSColors.of(context);
    final allRules = store.rules();
    final activeRules = allRules
        .where((r) => r.status == CompassRuleStatus.active)
        .length;
    final organsWithRules = store
        .organs()
        .where((o) => store.rules(organId: o.id).isNotEmpty)
        .length;
    final totalOrgans = store.organs().length;
    return Container(
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.surface, cs.surfaceElevated],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: cs.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(Icons.travel_explore,
              color: cs.accentPurple, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '羅盤正以 $activeRules 條規則守護 App 的 $organsWithRules 個部位'
              '${totalOrgans > organsWithRules ? '（其餘 ${totalOrgans - organsWithRules} 個部位已定位、等規則生長）' : ''}',
              style: TextStyle(
                  color: cs.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  /// Agent 直覺地圖——agent 檢索用的意圖索引，人機共視
  /// （資料同 compass_seek 的 intent_index，從 compass_meta 讀）
  Widget _agentIntuitionMap() {
    final cs = BridgeDSColors.of(context);
    final raw = store.getMeta('intent_index');
    List<Map<String, dynamic>> idx = const [];
    if (raw != null) {
      try {
        idx = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    return Container(
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: cs.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.psychology_alt_outlined,
                color: cs.accentBlue, size: 16),
            const SizedBox(width: 6),
            Text('Agent 直覺地圖',
                style: TextStyle(
                    color: cs.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Tooltip(
              message: 'App Agent 動手前會照這張地圖自動翻到對應規則。'
                  '你看到的就是它看到的——人機共視。',
              child: Icon(Icons.info_outline,
                  size: 14, color: cs.textMuted),
            ),
          ]),
          const SizedBox(height: 8),
          if (idx.isEmpty)
            Text('直覺地圖會在 Agent 首次查詢後長出來',
                style: TextStyle(color: cs.textMuted, fontSize: 12)),
          ...idx.take(6).map((e) {
            final kws = (e['kw'] as String).split('|').take(6).join(' · ');
            final rules = (e['rules'] as List).join(', ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.surfaceElevated,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('說到 $kws',
                        style:
                            TextStyle(fontSize: 11, color: cs.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('→ 翻到 $rules',
                        style:
                            TextStyle(fontSize: 11, color: cs.textMuted)),
                  ),
                ],
              ),
            );
          }),
          if (idx.length > 6)
            Text('…共 ${idx.length} 條聯想',
                style: TextStyle(color: cs.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _header(List<CompassSurgeryLog> surgeries) {
    final pending = store
        .rules()
        .where((r) => r.status == CompassRuleStatus.pendingApply)
        .length;
    return Container(
      padding: const EdgeInsets.all(BridgeDS.spaceLG),
      child: Row(
        children: [
          Icon(Icons.explore_outlined,
              color: BridgeDSColors.of(context).accentPurple, size: 26),
          const SizedBox(width: 10),
          Text('羅盤系統',
              style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
          const SizedBox(width: 16),
          Text(
              'v${store.version} · 自動更新於 ${_fmt(store.lastHarvestAt ?? DateTime.now())}',
              style: BridgeDSColors.of(context)
                  .labelMono
                  .copyWith(fontSize: 12)),
          const Spacer(),
          if (pending > 0)
            Tooltip(
              message: '有 $pending 條行為規則等待你套用',
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(context).tagWarnBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$pending 條待套用',
                    style: TextStyle(fontSize: 12, color: BridgeDSColors.of(context).tagWarnFg)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _timeline(List<CompassSurgeryLog> surgeries) {
    final cs = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: cs.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('最近變更', style: TextStyle(color: cs.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (surgeries.isEmpty)
            Text('尚無變更記錄', style: TextStyle(color: cs.textMuted, fontSize: 12)),
          ...surgeries.take(6).map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Text(_fmt(s.at), style: cs.labelMono.copyWith(fontSize: 11, color: cs.textMuted)),
                    const SizedBox(width: 8),
                    Text(s.author, style: TextStyle(fontSize: 12, color: cs.accentPurple)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(s.detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: cs.textSecondary))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  List<Widget> _organGroups(List<CompassOrgan> organs) {
    // [小葵 2026-09-10 人機共視] 有規則的器官才攤開；零規則的收合
    final withRules = <CompassOrgan>[];
    final withoutRules = <CompassOrgan>[];
    for (final o in organs) {
      (store.rules(organId: o.id).isNotEmpty ? withRules : withoutRules)
          .add(o);
    }
    final groups = <String, List<CompassOrgan>>{};
    for (final o in withRules) {
      groups.putIfAbsent(o.systemGroup, () => []).add(o);
    }
    return [
      ...groups.entries.map((e) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${e.key} · 有規則守護',
                style: TextStyle(
                    color: BridgeDSColors.of(context).textMuted,
                    fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: e.value.map((o) => _organCard(o)).toList(),
            ),
            const SizedBox(height: BridgeDS.spaceLG),
          ],
        );
      }),
      if (withoutRules.isNotEmpty)
        Theme(
          data: Theme.of(context)
              .copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            iconColor: BridgeDSColors.of(context).textMuted,
            title: Text(
              '已定位、等規則生長（${withoutRules.length} 個部位）',
              style: TextStyle(
                  color: BridgeDSColors.of(context).textMuted, fontSize: 13),
            ),
            subtitle: Text(
              '這些部位已在羅盤上掛了名（程式碼錨點），但還沒有行為規則。'
              '有原則要立的時候，跟我說一聲就能長出來。',
              style: TextStyle(
                  color: BridgeDSColors.of(context).textQuaternary,
                  fontSize: 11),
            ),
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: withoutRules.map((o) => _organCard(o)).toList(),
              ),
              const SizedBox(height: BridgeDS.spaceLG),
            ],
          ),
        ),
    ];
  }

  Widget _organCard(CompassOrgan o) {
    final cs = BridgeDSColors.of(context);
    final rules = store.rules(organId: o.id);
    final pending = rules.where((r) => r.status == CompassRuleStatus.pendingApply).length;
    final meanings = store.meaningsOf(o.id);
    final nickname = meanings['nickname']?.value;
    return InkWell(
      onTap: () => _selectedOrgan.value = o.id,
      borderRadius: BorderRadius.circular(10.0),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(BridgeDS.spaceMD),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(
            color: o.anchorOk ? cs.borderSubtle : cs.tagWarnFg,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                o.anchorOk ? Icons.check_circle : Icons.warning_amber_rounded,
                size: 14,
                color: o.anchorOk ? cs.accentGreen : cs.tagWarnFg,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(nickname ?? o.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: cs.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              nickname != null ? o.name : '${rules.length} 條規則',
              style: TextStyle(color: cs.textMuted, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (pending > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('$pending 條待套用',
                    style: TextStyle(fontSize: 11, color: cs.tagWarnFg)),
              ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime t) =>
      '${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// 器官詳情頁 — 規則卡 + 意義層編輯
class _OrganDetail extends StatefulWidget {
  final String organId;
  final VoidCallback onBack;
  /// [Blue 2026-09-10] compact=true → 圖譜上的浮動預覽卡：
  /// 第一層摘要預覽；點「細節」進編輯層；退回一層/關閉。
  final bool compact;
  const _OrganDetail(
      {required this.organId, required this.onBack, this.compact = false});

  @override
  State<_OrganDetail> createState() => _OrganDetailState();
}

class _OrganDetailState extends State<_OrganDetail> {
  final store = CompassStore.instance;
  StreamSubscription? _sub;
  int _depth = 0; // 0=預覽 1=編輯層（compact 模式）

  @override
  void initState() {
    super.initState();
    _sub = store.events.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = BridgeDSColors.of(context);
    final organs = store.organs();
    final organ = organs.firstWhere(
      (o) => o.id == widget.organId,
      orElse: () => CompassOrgan(
          id: widget.organId, systemGroup: '未知', name: widget.organId),
    );
    final rules = store.rules(organId: organ.id);
    final meanings = store.meaningsOf(organ.id);
    if (widget.compact) return _buildCompact(organ, rules, meanings);
    return Container(
      color: cs.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: cs.textPrimary),
              onPressed: widget.onBack,
              tooltip: '返回羅盤主頁',
            ),
            Text(organ.name,
                style:
                    TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
            const SizedBox(width: 12),
            Text(organ.systemGroup,
                style: TextStyle(color: cs.textMuted, fontSize: 13)),
          ]),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(BridgeDS.spaceLG),
              children: [
                // ── 意義層（人擁有，可編輯）──
                _sectionTitle('說明'),
                _meaningEditor(organ, meanings),
                const SizedBox(height: BridgeDS.spaceLG),
                // ── 規則卡 ──
                _sectionTitle('規則卡（${rules.length}）'),
                ...rules.map((r) => _ruleCard(r)),
                if (rules.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(10.0),
                      border: Border.all(color: cs.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.hourglass_empty,
                            size: 16, color: cs.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '這個部位還在自由生長——沒有規則約束它。'
                            '如果你發現它該有原則（例如「每次都要…」「絕不…」），'
                            '跟小葵說一聲，規則會從這裡長出來。',
                            style:
                                TextStyle(color: cs.textSecondary, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: BridgeDS.spaceLG),
                // ── 事實層（唯讀）──
                _sectionTitle('事實層（自動採集，唯讀）'),
                ...organ.facts.paths.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: SelectableText(p,
                          style: cs.labelMono
                              .copyWith(fontSize: 11, color: cs.textSecondary)),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 圖譜浮動預覽卡（compact）：depth 0 摘要 → depth 1 編輯層
  Widget _buildCompact(
      CompassOrgan organ, List<CompassRule> rules, meanings) {
    final cs = BridgeDSColors.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 460),
      decoration: BoxDecoration(
        color: cs.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: cs.canvas.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列：名稱＋群＋關閉
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 0),
            child: Row(
              children: [
                if (_depth == 1)
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new,
                        size: 14, color: cs.textSecondary),
                    onPressed: () => setState(() => _depth = 0),
                    tooltip: '退回預覽',
                  ),
                Expanded(
                  child: Text(organ.name,
                      style: TextStyle(
                          color: cs.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
                Text(organ.systemGroup,
                    style: TextStyle(color: cs.textMuted, fontSize: 11)),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: cs.textMuted),
                  onPressed: widget.onBack,
                  tooltip: '關閉預覽卡',
                ),
              ],
            ),
          ),
          Divider(color: cs.borderSubtle, height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(14),
              children: [
                if (_depth == 0) ...[
                  // ── 第一層：摘要預覽 ──
                  // [Blue 2026-09-11 令] 說明常駐預覽卡——白話描述這個點
                  // 的特性與用法（meanings.nickname 承載）
                  if ((meanings['nickname']?.value ?? '').trim().isNotEmpty) ...[
                    Text(meanings['nickname']!.value,
                        style: TextStyle(
                            color: cs.textSecondary, fontSize: 12, height: 1.5)),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    rules.isEmpty
                        ? '還沒有規則——這個部位在自由生長中'
                        : '${rules.length} 條規則守護中',
                    style: TextStyle(
                        color: rules.isEmpty ? cs.textMuted : cs.accentGreen,
                        fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  ...rules.take(4).map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.rule, size: 13, color: cs.accentPurple),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(r.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: cs.textSecondary,
                                      fontSize: 12)),
                            ),
                          ],
                        ),
                      )),
                  if (rules.length > 4)
                    Text('…還有 ${rules.length - 4} 條',
                        style:
                            TextStyle(color: cs.textMuted, fontSize: 11)),
                  const SizedBox(height: 10),
                  // 檔案錨點
                  if (organ.facts.paths.isNotEmpty)
                    Text('檔案：${organ.facts.paths.first}',
                        style: TextStyle(
                            color: cs.textQuaternary, fontSize: 10)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.tune, size: 14),
                      label: Text(_depthLabel(rules)),
                      style: OutlinedButton.styleFrom(
                        textStyle: const TextStyle(fontSize: 12),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () => setState(() => _depth = 1),
                    ),
                  ),
                ] else ...[
                  // ── 第二層：編輯（沿用完整詳情內容）──
                  _sectionTitle('說明'),
                  _meaningEditor(organ, meanings),
                  const SizedBox(height: 12),
                  _sectionTitle('規則卡（${rules.length}）'),
                  ...rules.take(6).map((r) => _ruleCard(r)),
                  if (rules.isEmpty)
                    Text('此器官尚無規則卡',
                        style:
                            TextStyle(color: cs.textMuted, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _depthLabel(List<CompassRule> rules) =>
      rules.isEmpty ? '看細節' : '看 ${rules.length} 條規則細節＋編輯';

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: TextStyle(
                color: BridgeDSColors.of(context).textMuted, fontSize: 13)),
      );

  Widget _meaningEditor(CompassOrgan organ, Map<String, CompassMeaningField> meanings) {
    final cs = BridgeDSColors.of(context);
    final nicknameCtrl = TextEditingController(
        text: meanings['nickname']?.value ?? '');
    nicknameCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: nicknameCtrl.text.length));
    return Container(
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: cs.borderSubtle),
      ),
      child: Column(
        children: [
          TextField(
            controller: nicknameCtrl,
            decoration: InputDecoration(
              labelText: '說明（這個部位是什麼、怎麼用）',
              labelStyle: TextStyle(color: cs.textMuted, fontSize: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            style: TextStyle(color: cs.textPrimary, fontSize: 13),
            maxLines: 3,
            minLines: 2,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _SaveMeaningButton(
              organId: organ.id,
              nicknameController: nicknameCtrl,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleCard(CompassRule r) {
    final cs = BridgeDSColors.of(context);
    final pending = r.status == CompassRuleStatus.pendingApply;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: pending ? cs.tagWarnFg : cs.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(r.description,
                  style: TextStyle(
                      color: cs.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            if (pending)
              Tooltip(
                message: '行為規則：需人按套用才生效',
                child: Icon(Icons.shield_outlined, size: 16, color: cs.tagWarnFg),
              ),
            if (r.kind == CompassRuleKind.visual)
              Tooltip(
                message: '視覺規則：修改即時生效',
                child: Icon(Icons.visibility_outlined,
                    size: 16, color: cs.textMuted),
              ),
          ]),
          const SizedBox(height: 4),
          Text('為什麼：${r.why}',
              style: TextStyle(color: cs.textMuted, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: r.params.entries.map((e) {
              return Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${e.key}:',
                    style: cs.labelMono.copyWith(fontSize: 11, color: cs.textMuted)),
                const SizedBox(width: 4),
                _ParamEditChip(rule: r, paramKey: e.key, value: e.value),
              ]);
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(children: [
            // [Blue 令 2026-09-12] 蓋章——誰寫的規則，磚上有簽名
            AgentSeal(author: r.updatedBy, size: 16),
            const SizedBox(width: 6),
            Text('最後修改：${r.updatedBy} · ${r.updatedAt.month}/${r.updatedAt.day}',
                style: TextStyle(color: cs.textMuted, fontSize: 11)),
            const Spacer(),
            if (pending)
              TextButton(
                onPressed: () => _apply(r),
                child: Text('套用', style: TextStyle(fontSize: 13)),
              ),
            TextButton(
              onPressed: () => _rollback(r),
              child: Text('回滾', style: TextStyle(fontSize: 13)),
            ),
          ]),
        ],
      ),
    );
  }

  void _apply(CompassRule r) {
    store.applyRule(r.id, byHuman: 'human:Blue');
    _snack('${r.id} 已套用生效');
  }

  void _rollback(CompassRule r) {
    try {
      store.rollbackRule(r.id, byHuman: 'human:Blue');
      _snack('${r.id} 已回滾到上一版');
    } catch (e) {
      _snack('$e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 14)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _SaveMeaningButton extends StatefulWidget {
  final String organId;
  final TextEditingController nicknameController;
  const _SaveMeaningButton(
      {required this.organId, required this.nicknameController});

  @override
  State<_SaveMeaningButton> createState() => _SaveMeaningButtonState();
}

class _SaveMeaningButtonState extends State<_SaveMeaningButton> {
  var _saving = false;
  var _saved = false;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        side: const BorderSide(color: Colors.deepPurpleAccent, width: 1.5),
        foregroundColor: Colors.white,
      ),
      onPressed: _saving ? null : _save,
      child: Text(
        _saving ? '儲存中…' : (_saved ? '✓ 已存檔' : '儲存'),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    CompassStore.instance.setMeaning(
      widget.organId,
      'nickname',
      widget.nicknameController.text,
      author: 'human:Blue',
    );
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) {
      setState(() {
        _saving = false;
        _saved = true;
      });
    }
  }
}

class _ParamEditChip extends StatefulWidget {
  final CompassRule rule;
  final String paramKey;
  final dynamic value;
  const _ParamEditChip(
      {required this.rule, required this.paramKey, required this.value});

  @override
  State<_ParamEditChip> createState() => _ParamEditChipState();
}

class _ParamEditChipState extends State<_ParamEditChip> {
  bool _editing = false;
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.value}');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = BridgeDSColors.of(context);
    if (_editing) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 64,
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: cs.labelMono.copyWith(fontSize: 11, color: cs.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onSubmitted: (_) => _commit(),
          ),
        ),
        IconButton(
          icon: Icon(Icons.check, size: 14, color: cs.accentPurple),
          onPressed: _commit,
          tooltip: '確定',
        ),
      ]);
    }
    return InkWell(
      onTap: () => setState(() => _editing = true),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        child: Text('${widget.value}',
            style: cs.labelMono
                .copyWith(fontSize: 11, color: cs.accentPurple)),
      ),
    );
  }

  void _commit() {
    final v = double.tryParse(_ctrl.text);
    if (v == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${widget.paramKey}：請輸入數字',
            style: const TextStyle(fontSize: 14)),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final newParams = Map<String, dynamic>.from(widget.rule.params);
    newParams[widget.paramKey] = v;
    try {
      CompassStore.instance.updateRuleParams(
        widget.rule.id,
        newParams: newParams,
        author: 'human:Blue',
        reason: '羅盤 UI 調整 ${widget.paramKey}',
      );
      setState(() => _editing = false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e', style: const TextStyle(fontSize: 14)),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}
