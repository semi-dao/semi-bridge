// 插槽管理頁 — 無限插槽系統 C2 骨架（2026-10-06）
//
// UI 定案：design-mockup/slot-management-mockup-v1.html（v2 已過 Blue 目）
// spec：docs/specs/2026-10-04-infinite-slot-system.md「插槽管理頁」段
//
// 佈局：卡片式分類（大卡 = 類名 + 數量 + 一句話說明）→ 點開展開該類插槽小卡
// 小卡：名字（大字）+ repo（小字）+ 認證徽章 + 狀態燈 + 權限 + 記憶體
//       + 操作按鈕（啟用/停用/⇄搬家/卸載）橫向單行 nowrap 不折行
// 「更新」按鈕：v1 只在「未認證 + 有新版」顯示——無版本來源前一律不顯示（Q5 拍板）
// 卸載：AlertDialog 問「資料要留要刪」，預設保留（Q6 拍板）
// 新增：先小表單（GitHub 連結）→ 送出才動作 → 嘗試開懸浮對話窗（C1）

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/quick_assistant/floating_window_service.dart';
import '../services/slots/slot_registry.dart';
import '../services/slots/slot_resource_watchdog.dart';
import 'slot_wizard.dart'; // [Blue 決策 2026-10-06] 練夥伴式精靈
import 'slot_runner_screen.dart'; // [C3] Tier 1 WebView 沙箱執行畫面
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

class SlotManagementScreen extends StatefulWidget {
  /// 非空時：進頁面自動打開新增表單並預填此連結（首頁「試一個範例 →」用）
  final String? prefillRepoUrl;

  const SlotManagementScreen({super.key, this.prefillRepoUrl});

  @override
  State<SlotManagementScreen> createState() => _SlotManagementScreenState();
}

class _SlotManagementScreenState extends State<SlotManagementScreen> {
  final SlotRegistry _registry = SlotRegistry.instance;

  /// 展開的分類（空集合 = 全部收合）
  final Set<String> _expandedCategories = {};

  bool _prefillConsumed = false;

  @override
  void initState() {
    super.initState();
    _registry.addListener(_onRegistryChanged);
    _registry.ensureLoaded();
    // 首頁範例按鈕進來 → 自動開新增表單並預填連結
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _prefillConsumed) return;
      final url = widget.prefillRepoUrl;
      if (url != null && url.isNotEmpty) {
        _prefillConsumed = true;
        _launchWizard(url);
      }
    });
  }

  @override
  void dispose() {
    _registry.removeListener(_onRegistryChanged);
    super.dispose();
  }

  void _onRegistryChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final categories = _registry.categories;

    return Scaffold(
      backgroundColor: ds.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 頁首：標題 + 新增按鈕 ──────────────
                _buildPageHead(),
                const SizedBox(height: BridgeDS.spaceLG),
                // ── 內容：分類大卡 或 空狀態 ────────────
                Expanded(
                  child: _registry.isEmpty && _registry.isLoaded
                      ? _buildEmptyState()
                      : SingleChildScrollView(
                          padding:
                              const EdgeInsets.only(bottom: BridgeDS.spaceXL),
                          child: Column(
                            children: [
                              for (final category in categories)
                                _buildCategoryCard(category),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 頁首
  // ═══════════════════════════════════════════════════

  Widget _buildPageHead() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          BridgeDS.spaceLG, BridgeDS.spaceLG, BridgeDS.spaceLG, 0),
      child: Row(
        children: [
          IconButton(
            // [Blue 抓包 2026-10-06] 返回鈕失效——入口是 context.go()（清堆疊），
            // 沒有上一頁可 pop。pop 不了就回真首頁（bridge-desktop）。
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/bridge-desktop');
              }
            },
            icon: Icon(Icons.arrow_back,
                size: 20, color: BridgeDSColors.of(context).textSecondary),
            tooltip: '返回',
          ),
          const SizedBox(width: BridgeDS.spaceSM),
          Expanded(
            child: Text(
              '插槽管理',
              style:
                  TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(
                        color: BridgeDSColors.of(context).textPrimary,
                      ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _launchWizard(''),
            icon: const Icon(Icons.add, size: 18),
            label: Text(
              '新增插槽',
              style: TierStyle.of(context, Tier.buttonPrimary)
                  .toTextStyle()
                  .copyWith(
                    color: BridgeDSColors.of(context).textPrimary,
                  ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: BridgeDSColors.of(context).accentMiro),
              padding: const EdgeInsets.symmetric(
                  horizontal: BridgeDS.spaceLG, vertical: BridgeDS.spaceMD - 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 空狀態（教學式）
  // ═══════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.extension_outlined,
              size: 48, color: BridgeDSColors.of(context).textQuaternary),
          const SizedBox(height: BridgeDS.spaceMD),
          Text(
            '貼上一個 GitHub 連結\n讓開源程式住進你的橋樑',
            textAlign: TextAlign.center,
            style:
                TierStyle.of(context, Tier.bodyPrimary).toTextStyle().copyWith(
                      color: BridgeDSColors.of(context).textSecondary,
                      height: 1.8,
                    ),
          ),
          const SizedBox(height: BridgeDS.spaceLG),
          FilledButton.icon(
            onPressed: () =>
                _launchWizard(SlotRegistry.sampleRepoUrl),
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: Text(
              '試一個範例 →',
              style: TierStyle.of(context, Tier.buttonPrimary)
                  .toTextStyle()
                  .copyWith(
                    color: BridgeDSColors.of(context).textPrimary,
                  ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: BridgeDSColors.of(context).accentMiro,
              padding: const EdgeInsets.symmetric(
                  horizontal: BridgeDS.spaceXL, vertical: BridgeDS.spaceMD),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 分類大卡
  // ═══════════════════════════════════════════════════

  Widget _buildCategoryCard(String category) {
    final slots = _registry.listByCategory(category);
    final expanded = _expandedCategories.contains(category);

    return Container(
      margin: const EdgeInsets.only(
          left: BridgeDS.spaceLG,
          right: BridgeDS.spaceLG,
          bottom: BridgeDS.spaceLG),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Column(
        children: [
          // 大卡頭：類名 + 數量 + 說明 + 展開箭頭
          InkWell(
            onTap: () => setState(() {
              expanded
                  ? _expandedCategories.remove(category)
                  : _expandedCategories.add(category);
            }),
            borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  BridgeDS.spaceLG, BridgeDS.spaceMD, BridgeDS.spaceMD,
                  BridgeDS.spaceMD),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              category,
                              style: TierStyle.of(context, Tier.cardTitle)
                                  .toTextStyle()
                                  .copyWith(
                                    color:
                                        BridgeDSColors.of(context).textPrimary,
                                  ),
                            ),
                            const SizedBox(width: BridgeDS.spaceSM),
                            Text(
                              '${slots.length}',
                              style: TierStyle.of(context, Tier.cardCaption)
                                  .toTextStyle()
                                  .copyWith(
                                    color:
                                        BridgeDSColors.of(context).accentMiro,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _registry.categoryDescription(category),
                          style: TierStyle.of(context, Tier.cardCaption)
                              .toTextStyle()
                              .copyWith(
                                color: BridgeDSColors.of(context).textMuted,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: BridgeDSColors.of(context).textTertiary,
                  ),
                ],
              ),
            ),
          ),
          // 展開後：該類插槽小卡（橫排 wrap）
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  BridgeDS.spaceLG, 0, BridgeDS.spaceLG, BridgeDS.spaceLG),
              child: Wrap(
                spacing: BridgeDS.spaceMD,
                runSpacing: BridgeDS.spaceMD,
                children: [
                  for (final slot in slots) _SlotCard(slot: slot),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // [Blue 決策 2026-10-06] onboarding 改練夥伴式精靈——四步固定流程
  // （貼連結→認識它→用途→燈號），放棄＝不建立任何東西（免卸載）。
  // 舊 _showAddDialog 對話式流程停用（LLM 主持不穩定）。
  Future<void> _launchWizard(String initialUrl) async {
    final result = await showSlotWizard(context, initialUrl);
    if (!mounted) return;
    if (result.completed && result.record != null) {
      _toast('「${result.record!.userLabel}」住進來了 🎉');
    }
  }

  // 「+ 新增插槽」小表單（Q-C:b——先表單、送出才動作）
  // ═══════════════════════════════════════════════════

  Future<void> _showAddDialog({String? prefill}) async {
    final controller = TextEditingController(text: prefill ?? '');
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BridgeDSColors.of(dialogContext).surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundWide),
        ),
        title: Text(
          '🧩 新增插槽',
          style: TierStyle.of(dialogContext, Tier.dialogTitle)
              .toTextStyle()
              .copyWith(color: BridgeDSColors.of(dialogContext).textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '貼上你想用的開源程式 GitHub 連結，送出後小葵會跟你聊聊怎麼用它。',
              style: TierStyle.of(dialogContext, Tier.dialogBody)
                  .toTextStyle()
                  .copyWith(
                    color: BridgeDSColors.of(dialogContext).textSecondary,
                    height: 1.6,
                  ),
            ),
            const SizedBox(height: BridgeDS.spaceMD),
            TextField(
              controller: controller,
              autofocus: true,
              style: TierStyle.of(dialogContext, Tier.formInput)
                  .toTextStyle()
                  .copyWith(
                    color: BridgeDSColors.of(dialogContext).textPrimary,
                  ),
              decoration: InputDecoration(
                hintText: 'https://github.com/owner/repo',
                hintStyle: TierStyle.of(dialogContext, Tier.formHelper)
                    .toTextStyle()
                    .copyWith(
                      color: BridgeDSColors.of(dialogContext).textMuted,
                    ),
                filled: true,
                fillColor: BridgeDSColors.of(dialogContext).canvas,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(BridgeDS.roundStandard),
                  borderSide: BorderSide(
                      color: BridgeDSColors.of(dialogContext).borderDefault),
                ),
              ),
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
            ),
            const SizedBox(height: BridgeDS.spaceMD),
            Text(
              '送出後：懸浮對話窗彈出 → grill-me 聊需求 → 權限綠燈放行・黃紅點頭 → 安裝＋紅隊測試 → 測試報告',
              style: TierStyle.of(dialogContext, Tier.formHelper)
                  .toTextStyle()
                  .copyWith(
                    color: BridgeDSColors.of(dialogContext).textMuted,
                    height: 1.7,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              '取消',
              style: TierStyle.of(dialogContext, Tier.buttonSecondary)
                  .toTextStyle()
                  .copyWith(
                    color: BridgeDSColors.of(dialogContext).textSecondary,
                  ),
            ),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: BridgeDSColors.of(dialogContext).accentMiro,
            ),
            child: Text(
              '送出 → 開始對話',
              style: TierStyle.of(dialogContext, Tier.buttonPrimary)
                  .toTextStyle()
                  .copyWith(
                    color: BridgeDSColors.of(dialogContext).textPrimary,
                  ),
            ),
          ),
        ],
      ),
    );

    if (url == null || url.isEmpty || !mounted) return;
    if (!url.contains('github.com')) {
      _toast('請貼 GitHub 連結（https://github.com/owner/repo）');
      return;
    }
    // v1：建立 pending 狀態的 SlotRecord（名稱暫用 repo 名）
    final record = await _registry.addFromRepo(url);
    // 開懸浮對話窗（C1）——帶著插槽脈絡自動 grill-me 開場（Blue 抓包問題1：
    // 原本只開空窗，使用者不知從何聊起、agent 不知對象是哪個插槽）
    try {
      await FloatingWindowService.instance.showOrCreateForSlot(
        slotId: record.id,
        userLabel: record.userLabel,
        sourceRepo: record.sourceRepo,
      );
    } catch (e) {
      // 懸浮窗開不起來不擋安裝登記——記錄即可
      debugPrint('[SlotManagement] FloatingWindow showOrCreateForSlot failed: $e');
    }
    if (!mounted) return;
    _toast('已登記「${record.userLabel}」，小葵馬上來聊怎麼用它');
  }

  // ═══════════════════════════════════════════════════
  // 共用
  // ═══════════════════════════════════════════════════

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TierStyle.of(context, Tier.buttonSecondary)
              .toTextStyle()
              .copyWith(color: BridgeDSColors.of(context).textPrimary),
        ),
        backgroundColor: BridgeDSColors.of(context).surfaceElevated,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════
// 插槽小卡
// ═════════════════════════════════════════════════════

class _SlotCard extends StatelessWidget {
  final SlotRecord slot;

  const _SlotCard({required this.slot});

  @override
  Widget build(BuildContext context) {
    final running = slot.isRunning;

    return Container(
      width: 250,
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceElevated,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 名字（大字）
          Text(
            slot.userLabel,
            style: TierStyle.of(context, Tier.listItemTitle)
                .toTextStyle()
                .copyWith(
                  color: BridgeDSColors.of(context).textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          // 來源 repo（小字）
          Text(
            _shortRepo(slot.sourceRepo),
            style: TierStyle.of(context, Tier.listItemMeta)
                .toTextStyle()
                .copyWith(color: BridgeDSColors.of(context).textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // [H1] 出身徽章——履歷不是戶籍（Hermes 出身/內建）
          if (slot.origin != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${slot.origin} 出身',
                style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(
                  color: BridgeDSColors.of(context).accentBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: BridgeDS.spaceSM),
          // 認證徽章
          _certBadge(context),
          const SizedBox(height: BridgeDS.spaceSM),
          // 狀態燈 + 權限 + 記憶體
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: running
                      ? BridgeDSColors.of(context).accentGreen
                      : BridgeDSColors.of(context).textQuaternary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                running
                  ? '運行中'
                  : (slot.isPending
                      ? '等待安裝'
                      : (slot.watchdogReason != null ? '⚠️ 已被看門狗暫停' : '已停用')),
                style: TierStyle.of(context, Tier.listItemMeta)
                    .toTextStyle()
                    .copyWith(
                      color: running
                          ? BridgeDSColors.of(context).accentGreen
                          : BridgeDSColors.of(context).textTertiary,
                    ),
              ),
              const SizedBox(width: BridgeDS.spaceMD),
              // 權限圖示：🌐網路 🔓檔案
              Text(
                _permLabel(slot.permissions),
                style: TierStyle.of(context, Tier.listItemMeta)
                    .toTextStyle()
                    .copyWith(
                      color: slot.permissions.isEmpty
                          ? BridgeDSColors.of(context).textQuaternary
                          : BridgeDSColors.of(context).accentPurple,
                    ),
              ),
              const Spacer(),
              // 記憶體用量（無引擎前 —）
              Text(
                slot.memoryMb == null ? '—' : '${slot.memoryMb}MB',
                style: TierStyle.of(context, Tier.listItemMeta)
                    .toTextStyle()
                    .copyWith(color: BridgeDSColors.of(context).textMuted),
              ),
            ],
          ),
          const SizedBox(height: BridgeDS.spaceMD),
          // 操作按鈕：橫向單行、nowrap、不折行（Blue 2026-10-06 修法定案）
          // 「更新」按鈕：只在未認證＋有新版顯示——無版本來源前一律不顯示（Q5）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // [Blue 抓包 2026-10-07] 不可 reverse——reverse 讓捲動起始在尾端，
            // 「開啟」（最高頻操作）被推出視野外。正序：開啟恆在第一眼，
            // 卸載要滑到最後才看得到（順序即防誤觸）。
            child: Row(
              children: [
                _opButton(
                  context,
                  '開啟',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          SlotRunnerScreen(slotId: slot.id))),
                ),
                _opButton(
                  context,
                  running ? '停用' : '啟用',
                  onTap: () async {
                    if (running) {
                      await SlotRegistry.instance.disable(slot.id);
                      return;
                    }
                    // [Blue 抓包 2026-10-06] pending/disabled → 啟用必經
                    // 權限燈號裁決（spec：綠自動、黃紅人點頭）——不能一鍵跳 running。
                    final granted = await _showPermissionGate(context, slot);
                    if (granted == null) return; // 取消＝不啟用
                    await SlotRegistry.instance
                        .enableWithPermissions(slot.id, granted);
                    // [C4] 手動重啟＝清看門狗旗標（清白重生）
                    SlotResourceWatchdog.instance.clearTrip(slot.id);
                  },
                ),
                _opButton(context, '✏️ 改名', dashed: true,
                    onTap: () => _showRenameDialog(context)),
                _opButton(context, '⇄ 搬家', dashed: true,
                    onTap: () => _showMoveDialog(context)),
                _opButton(
                  context,
                  '卸載',
                  danger: true,
                  onTap: () => _showUninstallDialog(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _certBadge(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    // 認證徽章：Reggie 認證✓ / 未認證。v1 全部未認證。
    final color = slot.certified ? ds.accentGreen : ds.accentYellow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(BridgeDS.roundPill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        slot.certified ? '✓ 認證' : '未認證',
        style: TierStyle.of(context, Tier.listItemMeta)
            .toTextStyle()
            .copyWith(color: color),
      ),
    );
  }

  Widget _opButton(
    BuildContext context,
    String label, {
    bool danger = false,
    bool dashed = false,
    required VoidCallback onTap,
  }) {
    final color = danger
        ? BridgeDSColors.of(context).accentRed
        : BridgeDSColors.of(context).textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).canvas,
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          border: Border.all(
            color: danger
                ? BridgeDSColors.of(context).accentRed.withValues(alpha: 0.4)
                : BridgeDSColors.of(context).borderDefault,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: TierStyle.of(context, Tier.listItemMeta)
              .toTextStyle()
              .copyWith(color: color),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 搬家對話框（按鈕式選目標分類，非拖放；可新增分類）
  // ═══════════════════════════════════════════════════

  // [Blue 驗收回饋 2026-10-06] 改名——spec 使用者故事「我幫插槽取了名字」
  // 的事後編輯入口。TextField 預填現名，空值不送（誤觸清空保護）。
  Future<void> _showRenameDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: slot.userLabel);
    final ds0 = BridgeDSColors.of(context);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final ds = BridgeDSColors.of(dialogContext);
        return AlertDialog(
          backgroundColor: ds.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BridgeDS.roundWide),
          ),
          title: Text(
            '✏️ 幫它改個名字',
            style: TierStyle.of(dialogContext, Tier.dialogTitle)
                .toTextStyle()
                .copyWith(color: ds.textPrimary),
          ),
          content: SizedBox(
            width: 320,
            child: TextField(
              controller: ctrl,
              autofocus: true,
              style: TierStyle.of(dialogContext, Tier.bodyPrimary)
                  .toTextStyle()
                  .copyWith(color: ds.textPrimary),
              decoration: InputDecoration(
                hintText: '你想起的名字',
                hintStyle: TierStyle.of(dialogContext, Tier.listItemMeta)
                    .toTextStyle()
                    .copyWith(color: ds.textMuted),
                filled: true,
                fillColor: ds.canvas,
                border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(BridgeDS.roundSubtle),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(BridgeDS.roundSubtle),
                    borderSide: BorderSide(color: ds.accentMiro)),
              ),
              onSubmitted: (v) => Navigator.of(dialogContext)
                  .pop(v.trim().isEmpty ? null : v.trim()),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('取消',
                  style: TierStyle.of(dialogContext, Tier.buttonSecondary)
                      .toTextStyle()
                      .copyWith(color: ds.textSecondary)),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: ds0.accentMiro),
              onPressed: () => Navigator.of(dialogContext)
                  .pop(ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
              child: Text('好了',
                  style: TierStyle.of(dialogContext, Tier.buttonPrimary)
                      .toTextStyle()
                      .copyWith(color: ds.textPrimary)),
            ),
          ],
        );
      },
    );
    if (newName != null && newName != slot.userLabel) {
      await SlotRegistry.instance.rename(slot.id, newName);
    }
  }

  Future<void> _showMoveDialog(BuildContext context) async {
    final registry = SlotRegistry.instance;
    final categories = registry.categories;
    final target = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BridgeDSColors.of(dialogContext).surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundWide),
        ),
        title: Text(
          '⇄ 搬到哪個分類？',
          style: TierStyle.of(dialogContext, Tier.dialogTitle)
              .toTextStyle()
              .copyWith(color: BridgeDSColors.of(dialogContext).textPrimary),
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in categories)
                if (c != slot.category)
                  ListTile(
                    dense: true,
                    title: Text(
                      c,
                      style: TierStyle.of(dialogContext, Tier.listItemTitle)
                          .toTextStyle()
                          .copyWith(
                            color:
                                BridgeDSColors.of(dialogContext).textPrimary,
                          ),
                    ),
                    trailing: Text(
                      '${registry.listByCategory(c).length}',
                      style: TierStyle.of(dialogContext, Tier.listItemMeta)
                          .toTextStyle()
                          .copyWith(
                            color:
                                BridgeDSColors.of(dialogContext).textMuted,
                          ),
                    ),
                    onTap: () => Navigator.of(dialogContext).pop(c),
                  ),
              const SizedBox(height: BridgeDS.spaceSM),
              // 新增分類
              OutlinedButton.icon(
                onPressed: () async {
                  final newCategory = await _promptNewCategory(dialogContext);
                  if (newCategory != null && newCategory.isNotEmpty) {
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop(newCategory);
                    }
                  }
                },
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  '新增分類',
                  style: TierStyle.of(dialogContext, Tier.buttonSecondary)
                      .toTextStyle()
                      .copyWith(
                        color:
                            BridgeDSColors.of(dialogContext).textSecondary,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (target == null || target.isEmpty) return;
    await registry.setCategory(slot.id, target);
  }

  Future<String?> _promptNewCategory(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BridgeDSColors.of(dialogContext).surfaceElevated,
        title: Text(
          '新分類名稱',
          style: TierStyle.of(dialogContext, Tier.dialogTitle)
              .toTextStyle()
              .copyWith(color: BridgeDSColors.of(dialogContext).textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TierStyle.of(dialogContext, Tier.formInput)
              .toTextStyle()
              .copyWith(color: BridgeDSColors.of(dialogContext).textPrimary),
          decoration: InputDecoration(
            hintText: '例如：影片工具',
            hintStyle: TierStyle.of(dialogContext, Tier.formHelper)
                .toTextStyle()
                .copyWith(color: BridgeDSColors.of(dialogContext).textMuted),
          ),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              '取消',
              style: TierStyle.of(dialogContext, Tier.buttonSecondary)
                  .toTextStyle()
                  .copyWith(
                      color:
                          BridgeDSColors.of(dialogContext).textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor:
                  BridgeDSColors.of(dialogContext).accentMiro,
            ),
            child: Text(
              '建立',
              style: TierStyle.of(dialogContext, Tier.buttonPrimary)
                  .toTextStyle()
                  .copyWith(
                      color: BridgeDSColors.of(dialogContext).textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 權限燈號裁決（Blue 抓包 2026-10-06：啟用前必須讓使用者看燈號點頭）
  // spec：🟢 純本地無網路→自動放行等級；🟡 網路唯讀；🔴 網路+檔案寫入。
  // deny-by-default：未選燈號＝無權限；取消＝不啟用。
  // ═══════════════════════════════════════════════════

  Future<List<String>?> _showPermissionGate(
      BuildContext context, SlotRecord slot) async {
    // 預設建議：登記時尚無風險掃描（C3）——一律從最保守 🟡 起跳，
    // 讓使用者自己降級或升級。綠燈自動放行要等 C3 掃描背書。
    int choice = 1;
    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          backgroundColor:
              BridgeDSColors.of(dialogContext).surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BridgeDS.roundWide),
          ),
          title: Text(
            '啟用「${slot.userLabel}」——要給它什麼權限？',
            style: TierStyle.of(dialogContext, Tier.dialogTitle)
                .toTextStyle()
                .copyWith(
                    color: BridgeDSColors.of(dialogContext).textPrimary),
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '來源：${_shortRepo(slot.sourceRepo)}',
                  style: TierStyle.of(dialogContext, Tier.listItemMeta)
                      .toTextStyle()
                      .copyWith(
                          color: BridgeDSColors.of(dialogContext).textMuted),
                ),
                const SizedBox(height: 12),
                _lightOption(
                  dialogContext,
                  index: 0,
                  groupValue: choice,
                  emoji: '🟢',
                  title: '純本地——不碰網路、不寫檔案',
                  desc: '最安全。只在自己的插槽資料夾內運算。',
                  onChanged: (v) => setState(() => choice = v),
                ),
                _lightOption(
                  dialogContext,
                  index: 1,
                  groupValue: choice,
                  emoji: '🟡',
                  title: '網路唯讀——可抓資料、不下載執行檔',
                  desc: '適合讀資料/查 API 的工具（目前建議）。',
                  onChanged: (v) => setState(() => choice = v),
                ),
                _lightOption(
                  dialogContext,
                  index: 2,
                  groupValue: choice,
                  emoji: '🔴',
                  title: '網路＋檔案寫入——完整能力',
                  desc: '高風險：可下載與改寫檔案。僅在信任來源時選。',
                  onChanged: (v) => setState(() => choice = v),
                ),
                const SizedBox(height: 8),
                Text(
                  '🔒 預設全部拒絕（deny-by-default）。執行引擎（C3）上線後，'
                  '紅隊測試報告會自動標出建議燈號。',
                  style: TierStyle.of(dialogContext, Tier.listItemMeta)
                      .toTextStyle()
                      .copyWith(
                          color:
                              BridgeDSColors.of(dialogContext).textTertiary),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                '取消',
                style: TierStyle.of(dialogContext, Tier.buttonSecondary)
                    .toTextStyle()
                    .copyWith(
                        color:
                            BridgeDSColors.of(dialogContext).textSecondary),
              ),
            ),
            FilledButton(
              onPressed: () {
                const permsByChoice = <List<String>>[
                  [],            // 🟢 純本地：零權限
                  ['network'],   // 🟡 網路唯讀
                  ['network', 'file'], // 🔴 完整
                ];
                Navigator.of(dialogContext).pop(permsByChoice[choice]);
              },
              style: FilledButton.styleFrom(
                backgroundColor:
                    BridgeDSColors.of(dialogContext).accentMiro,
              ),
              child: Text(
                '點頭啟用',
                style: TierStyle.of(dialogContext, Tier.buttonPrimary)
                    .toTextStyle()
                    .copyWith(
                        color:
                            BridgeDSColors.of(dialogContext).textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lightOption(
    BuildContext dialogContext, {
    required int index,
    required int groupValue,
    required String emoji,
    required String title,
    required String desc,
    required ValueChanged<int> onChanged,
  }) {
    final selected = index == groupValue;
    final ds = BridgeDSColors.of(dialogContext);
    return InkWell(
      onTap: () => onChanged(index),
      borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? ds.accentMiro.withValues(alpha: 0.10) : ds.canvas,
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          border: Border.all(
            color: selected
                ? ds.accentMiro.withValues(alpha: 0.6)
                : ds.borderSubtle,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TierStyle.of(dialogContext, Tier.listItemTitle)
                        .toTextStyle()
                        .copyWith(
                            color: ds.textPrimary,
                            fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TierStyle.of(dialogContext, Tier.listItemMeta)
                        .toTextStyle()
                        .copyWith(color: ds.textTertiary),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 18,
              color: selected ? ds.accentMiro : ds.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 卸載對話框（Q6:b——先問資料去留，預設保留）
  // ═══════════════════════════════════════════════════

  Future<void> _showUninstallDialog(BuildContext context) async {
    final keepData = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BridgeDSColors.of(dialogContext).surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundWide),
        ),
        title: Text(
          '卸載「${slot.userLabel}」？',
          style: TierStyle.of(dialogContext, Tier.dialogTitle)
              .toTextStyle()
              .copyWith(color: BridgeDSColors.of(dialogContext).textPrimary),
        ),
        content: Text(
          '插槽產生的資料要留要刪？',
          style: TierStyle.of(dialogContext, Tier.dialogBody)
              .toTextStyle()
              .copyWith(
                  color:
                      BridgeDSColors.of(dialogContext).textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              '保留（預設）',
              style: TierStyle.of(dialogContext, Tier.buttonSecondary)
                  .toTextStyle()
                  .copyWith(
                      color:
                          BridgeDSColors.of(dialogContext).textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              '刪除資料',
              style: TierStyle.of(dialogContext, Tier.buttonSecondary)
                  .toTextStyle()
                  .copyWith(
                      color: BridgeDSColors.of(dialogContext).accentRed),
            ),
          ),
        ],
      ),
    );
    if (keepData == null) return; // 取消
    await SlotRegistry.instance.uninstall(slot.id, deleteData: !keepData);
  }

  // ═══════════════════════════════════════════════════
  // helpers
  // ═══════════════════════════════════════════════════

  String _shortRepo(String url) {
    final slug = extractRepoSlug(url);
    return slug.isEmpty ? url : 'github.com/$slug';
  }

  String _permLabel(List<String> permissions) {
    if (permissions.isEmpty) return '🔒 無權限';
    final labels = <String>[];
    if (permissions.contains('network')) labels.add('🌐網');
    if (permissions.contains('file')) labels.add('🔓檔');
    // 未知權限照列
    for (final p in permissions) {
      if (p != 'network' && p != 'file') labels.add(p);
    }
    return labels.join(' ');
  }
}
