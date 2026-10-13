// 橋樑 App — 夥伴控制中心
// 2026-08-04 Phase E: 統一入口，接回 Identity / Expression / Capability / Growth Loop

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/companion.dart';
import '../services/companion_store.dart';
import '../widgets/trust/agent_glyph.dart'; // [刀 2] 指紋縮圖
import '../services/budget_ledger.dart'; // [刀 2] 工作實績
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../widgets/adaptive_scaffold.dart';
import '../widgets/companion_rig.dart';
import '../widgets/companion_rig_animator.dart';

class CompanionControlCenterScreen extends StatefulWidget {
  final String companionId;
  final String? returnTo;
  final bool hideAppBar; // [教練 Agent 2026-08-04 Phase E+] BridgeDesktop 內嵌時隱藏
  final VoidCallback? onBack; // [教練 Agent 2026-08-04 Phase E+] 內嵌模式返回 callback
  final void Function(String page)? onNavigateTo; // [教練 Agent 2026-08-04 Phase E+] 內嵌模式導航 callback

  const CompanionControlCenterScreen({
    super.key,
    required this.companionId,
    this.returnTo,
    this.hideAppBar = false,
    this.onBack,
    this.onNavigateTo,
  });

  @override
  State<CompanionControlCenterScreen> createState() =>
      _CompanionControlCenterScreenState();
}

class _CompanionControlCenterScreenState
    extends State<CompanionControlCenterScreen> {
  Companion? _companion;

  @override
  void initState() {
    super.initState();
    _loadCompanion();
  }

  void _loadCompanion() {
    final companion = CompanionStore().getById(widget.companionId);
    if (companion != null) {
      setState(() => _companion = companion);
    }
  }

  // [教練 Agent 2026-08-04 Phase E+] 全域頂部返回按鈕邏輯
  void _handleBack() {
    if (widget.returnTo != null) {
      context.go(widget.returnTo!);
    } else {
      // [小葵 2026-09-08] 預設回桌面首頁（舊 /companions 是退役手機版頁面，
      // 使用者按返回掉進去後回不了家）
      context.go('/bridge-desktop');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final companion = _companion;

    if (companion == null) {
      return Scaffold(
        backgroundColor: ds.canvas,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: widget.hideAppBar
                ? null
                : AppBar(
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back, size: 28),
                      onPressed: () {
                        // [教練 Agent 2026-08-04 Phase E+] 優先用 onBack callback（內嵌模式），再用 returnTo，最後預設
                        if (widget.onBack != null) {
                          widget.onBack!();
                        } else if (widget.returnTo != null) {
                          context.go(widget.returnTo!);
                        } else {
                          // [小葵 2026-09-08] 舊 /companions 是退役手機版頁面，回桌面首頁
                          context.go('/bridge-desktop');
                        }
                      },
                    ),
        title: Text('${companion.name} · ${companion.roleName}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: () {
                // 設為 active 並進入對話
                CompanionStore().setActive(companion.id);
                context.go('/chat');
              },
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('進入對話'),
              style: FilledButton.styleFrom(
                backgroundColor: ds.canvas,
          side: BorderSide(color: ds.accentPurple, width: 1.5),
                foregroundColor: ds.textPrimary,
              ),
            ),
          ),
        ],
        backgroundColor: ds.canvas,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Identity Card
                _buildIdentityCard(companion, ds),
                const SizedBox(height: 24),

                // [刀 2 D2.3] 工作實績（審計軌跡）——Buzz 式成員模型
                _buildWorkRecordSection(companion, ds),
                const SizedBox(height: 16),

                // [刀 2 D2.5] 權限範圍（成員式管理——現況誠實聲明，唯讀）
                _buildPermissionSection(companion, ds),
                const SizedBox(height: 16),

                // 個性與靈魂
                _buildPersonalitySection(companion, ds),
                const SizedBox(height: 16),

                // 聲音與表達
                _buildVoiceSection(companion, ds),
                const SizedBox(height: 16),

                // 專長與能力
                _buildCapabilitySection(companion, ds),
                const SizedBox(height: 16),

                // 記憶與成長
                _buildGrowthSection(companion, ds),
                const SizedBox(height: 16),

                  // DAO / NFT
                  _buildDaoNftSection(companion, ds),
                  const SizedBox(height: 16),

                  // 形象與狀態圖
                  _buildAppearanceSection(companion, ds),
                  const SizedBox(height: 32),

                  // 底部行動按鈕
                  _buildActionButtons(companion, ds),
                ],
              ),
            ),
          ),
        ),
    );
  }

  Widget _buildIdentityCard(Companion companion, BridgeDSColors ds) {
    final mbti = companion.mbtiType;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ds.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 頭像——[刀 2] 有照片用照片；沒照片用 AgentGlyph 指紋（即刻有臉）
              // [Blue 令 2026-09-12] 照片右下角疊常駐指紋章——身份的簽名永遠在場
              Stack(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: ds.canvas,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ds.borderDefault, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      // [小葵 2026-09-13] rig 分支封存（Blue 拍板回歸靜態圖）——重啟=恢復上面分支
                      child: companion.avatarImagePath != null
                              ? Image.network(
                                  companion.avatarImagePath!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => AgentGlyph(
                                    companionId: companion.id,
                                    name: companion.name,
                                    size: 76,
                                  ),
                                )
                              : AgentGlyph(
                                  companionId: companion.id,
                                  name: companion.name,
                                  size: 76,
                                ),
                    ),
                  ),
                  // 右下角指紋章（帶白邊——蓋在照片上也清晰）
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: ds.surface,
                        shape: BoxShape.circle,
                      ),
                      child: AgentGlyph(
                        companionId: companion.id,
                        name: companion.name,
                        size: 24,
                        showInitial: false,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              // 資訊
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      companion.name,
                      style: ds.headingL.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${mbti?.name ?? companion.mbtiCode} · ${companion.roleName}',
                      style: ds.body.copyWith(color: ds.textSecondary),
                    ),
                    if (mbti != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: mbti.traits.take(3).map((trait) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: ds.accentBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              trait,
                              style: ds.small.copyWith(color: ds.accentBlue),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// [刀 2 D2.3] 工作實績——這個夥伴的審計軌跡（信任條+統計+Ledger 明細）
  Widget _buildWorkRecordSection(Companion companion, BridgeDSColors ds) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ds.borderDefault),
      ),
      child: FutureBuilder<
          ({int total, int ok, int failed, List<LedgerEntry> recent})>(
        future: () async {
          final stats = await BudgetLedger.instance.statsFor(companion.id);
          final recent =
              await BudgetLedger.instance.recentFor(companion.id, limit: 30);
          return (
            total: stats.total,
            ok: stats.ok,
            failed: stats.failed,
            recent: recent,
          );
        }(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)));
          }
          final d = snap.data!;
          final successRate =
              d.total == 0 ? 0.0 : d.ok / d.total;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📋 工作實績（審計軌跡）',
                  style: ds.headingS.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '總 ${d.total} 筆 · 成功 ${d.ok} · 失敗 ${d.failed}',
                            style: ds.body.copyWith(color: ds.textSecondary)),
                        const SizedBox(height: 6),
                        // 成功率條（同 TrustMeter 視覺語言）
                        Stack(
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: ds.borderDefault,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: successRate.clamp(0.0, 1.0),
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: successRate >= 0.8
                                      ? ds.accentGreen
                                      : (successRate >= 0.5
                                          ? ds.accentYellow
                                          : ds.accentRed),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('成功率 ${(successRate * 100).round()}%',
                            style: ds.small.copyWith(color: ds.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // [D2.4] 查看 Ledger 按鈕
                  OutlinedButton.icon(
                    onPressed: () => _showLedgerSheet(context, companion, ds),
                    icon: const Icon(Icons.receipt_long, size: 16),
                    label: const Text('完整 Ledger'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ds.textPrimary,
                      side: BorderSide(color: ds.borderDefault),
                    ),
                  ),
                ],
              ),
              if (d.recent.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  d.total == 0 ? '還沒有記帳紀錄——這個夥伴尚未執行付費動作' : '',
                  style: ds.small.copyWith(color: ds.textMuted),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// [刀 2 D2.4] 完整 Ledger BottomSheet——該夥伴最近 30 筆明細
  void _showLedgerSheet(BuildContext context, Companion companion, BridgeDSColors ds) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ds.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => FutureBuilder<List<LedgerEntry>>(
        future: BudgetLedger.instance.recentFor(companion.id, limit: 30),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          final entries = snap.data!;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('${companion.name} · Ledger（最近 ${entries.length} 筆）',
                    style: ds.headingS.copyWith(fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text('沒有紀錄',
                            style: ds.small.copyWith(color: ds.textMuted)))
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, i) {
                          final e = entries[i];
                          final statusColor = switch (e.status) {
                            'ok' => ds.accentGreen,
                            'failed' => ds.accentRed,
                            _ => ds.textMuted,
                          };
                          // [Blue 令 2026-09-12] 蓋章——每筆工作真相都有他的指紋
                          return ListTile(
                            leading: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                AgentGlyph(
                                  companionId: companion.id,
                                  name: companion.name,
                                  size: 30,
                                  showInitial: false,
                                ),
                                Positioned(
                                  right: -3,
                                  bottom: -3,
                                  child: Container(
                                    padding: const EdgeInsets.all(1.5),
                                    decoration: BoxDecoration(
                                      color: ds.surface,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      e.status == 'ok'
                                          ? Icons.check_circle
                                          : (e.status == 'failed'
                                              ? Icons.cancel
                                              : Icons.hourglass_top),
                                      size: 12,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(e.intent.isEmpty ? e.kind.name : e.intent,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${e.kind.name} · ${e.at.toIso8601String().substring(0, 16).replaceAll('T', ' ')}'),
                            dense: true,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// [刀 2 D2.5] 權限範圍——「這個隊友可以進哪些房間、動哪些資產」現況聲明。
  /// 唯讀（本刀不縮權不擴權——編輯介面列刀 7 開放層，涉及羅盤雙層所有權）。
  Widget _buildPermissionSection(Companion companion, BridgeDSColors ds) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ds.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🔑 權限範圍（現況聲明）',
              style: ds.headingS.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _permRow(ds, Icons.home_work_outlined, '房間存取', '全部房間（未分權）'),
          _permRow(ds, Icons.build_circle_outlined, '可用工具',
              'Agent 工具註冊表全部工具'),
          _permRow(ds, Icons.paid_outlined, '付費額度',
              '圖像 30/日 · 影片 5/日 · 音樂 10/日（全域保險絲，非個人化）'),
          const SizedBox(height: 8),
          Text(
            'ℹ️ 個人化權限編輯（哪些房間/資產/額度）列刀 7 開放層——權限變更需經羅盤雙層所有權流程。',
            style: ds.small.copyWith(color: ds.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _permRow(BridgeDSColors ds, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: ds.textMuted),
          const SizedBox(width: 8),
          Text(label, style: ds.body.copyWith(color: ds.textSecondary)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: ds.body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalitySection(Companion companion, BridgeDSColors ds) {
    return _buildSection(
      title: '個性與靈魂',
      icon: Icons.psychology_outlined,
      ds: ds,
      children: [
        _buildInfoRow('MBTI', companion.mbtiType?.name ?? companion.mbtiCode, ds),
        if (companion.personalityTags.isNotEmpty)
          _buildInfoRow(
            '個性標籤',
            companion.personalityTags.map((t) => t.name).join(' · '),
            ds,
          ),
        const SizedBox(height: 12),
        // [H3 2026-10-08] 靈魂文檔（SOUL）——人格的最深處，可共視編輯
        if (companion.soulMd.trim().isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ds.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: ds.accentPurple.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 14, color: ds.accentPurple),
                    const SizedBox(width: 6),
                    Text('靈魂文檔 SOUL',
                        style: TierStyle.of(context, Tier.cardCaption)
                            .toTextStyle()
                            .copyWith(
                              color: ds.accentPurple,
                              fontWeight: FontWeight.w700,
                            )),
                    const Spacer(),
                    // 共視編輯——Blue 能看能改（人格透明化）
                    GestureDetector(
                      onTap: () => _editSoulMd(companion),
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 13, color: ds.textMuted),
                          const SizedBox(width: 4),
                          Text('共視編輯',
                              style: TierStyle.of(context, Tier.cardCaption)
                                  .toTextStyle()
                                  .copyWith(color: ds.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  // 預覽：前 6 行
                  companion.soulMd.trim().split('\n').take(6).join('\n'),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle()
                      .copyWith(
                    color: ds.textSecondary,
                    height: 1.5,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            // [教練 Agent 2026-08-04 Phase E+] 內嵌模式用 callback，外部模式用 context.go
            onPressed: () {
              if (widget.onNavigateTo != null) {
                widget.onNavigateTo!('soul');
              } else {
                context.go(
                  '/companion/soul?id=${companion.id}&returnTo=${Uri.encodeComponent('/companion/control?id=${companion.id}')}',
                );
              }
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('編輯個性'),
          ),
        ),
      ],
    );
  }

  /// [H3] 共視編輯靈魂文檔——人格透明化（Blue 能看、能改）
  void _editSoulMd(Companion companion) {
    final ctl = TextEditingController(text: companion.soulMd);
    final ds = BridgeDSColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ds.surfaceElevated,
        title: Text('靈魂文檔 SOUL——${companion.name}',
            style: TierStyle.of(ctx, Tier.cardHeroTitle).toTextStyle()),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '這是夥伴的核心身份層，注入於 system prompt 最頂層——先於角色與風格設定。',
                style: TierStyle.of(ctx, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: ds.textMuted),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctl,
                maxLines: 16,
                style: TierStyle.of(ctx, Tier.cardBody)
                    .toTextStyle()
                    .copyWith(fontFamily: 'monospace', fontSize: 12.5, height: 1.6),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderSide: BorderSide(color: ds.borderSubtle)),
                  hintText: '（空 = 沒有靈魂文檔）',
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
            onPressed: () async {
              final updated =
                  companion.copyWith(soulMd: ctl.text.trim());
              await CompanionStore().update(updated);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                setState(() {
                  _companion = updated;
                });
              }
            },
            child: Text('儲存靈魂',
                style: TierStyle.of(ctx, Tier.cardBody)
                    .toTextStyle()
                    .copyWith(
                        color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceSection(Companion companion, BridgeDSColors ds) {
    return _buildSection(
      title: '聲音與表達',
      icon: Icons.record_voice_over_outlined,
      ds: ds,
      children: [
        _buildInfoRow('主聲音', companion.voiceName, ds),
        _buildInfoRow('語速', '${companion.voiceSpeed}x', ds),
        _buildInfoRow(
          '情緒語音',
          companion.emotionEnabled ? '開啟' : '關閉',
          ds,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () {
                // TODO: 測試播放
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('測試播放功能開發中...')),
                );
              },
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('測試播放'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              // [教練 Agent 2026-08-04 Phase E+] 內嵌模式用 callback
              onPressed: () {
                if (widget.onNavigateTo != null) {
                  widget.onNavigateTo!('voice');
                } else {
                  context.go(
                    '/companion/voice?id=${companion.id}&returnTo=${Uri.encodeComponent('/companion/control?id=${companion.id}')}',
                  );
                }
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('語音設定'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCapabilitySection(Companion companion, BridgeDSColors ds) {
    return _buildSection(
      title: '專長與能力',
      icon: Icons.auto_awesome_outlined,
      ds: ds,
      children: [
        _buildInfoRow('專長', companion.roleName, ds),
        _buildInfoRow(
          '工具權限',
          companion.trustBoundary.allowFileAccess ? '檔案讀寫 ✓' : '受限',
          ds,
        ),
        _buildInfoRow('Canvas 能力', '已啟用', ds),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('能力設定頁面開發中...')),
              );
            },
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('能力設定'),
          ),
        ),
      ],
    );
  }

  Widget _buildGrowthSection(Companion companion, BridgeDSColors ds) {
    return _buildSection(
      title: '記憶與成長',
      icon: Icons.show_chart_outlined,
      ds: ds,
      children: [
        _buildInfoRow('對話記憶', '${companion.totalConversations} 則保留', ds),
        _buildInfoRow('情緒記憶', companion.emotionEnabled ? '開啟' : '關閉', ds),
        _buildInfoRow('最近學到', '偏好簡潔回答、喜歡結構化思考', ds),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('記憶查看功能開發中...')),
                );
              },
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('查看記憶'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('重置記憶功能開發中...')),
                );
              },
              icon: const Icon(Icons.refresh_outlined, size: 18),
              label: const Text('重置記憶'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDaoNftSection(Companion companion, BridgeDSColors ds) {
    final passport = companion.rightsPassport;
    return _buildSection(
      title: 'DAO / NFT',
      icon: Icons.verified_outlined,
      ds: ds,
      children: [
        _buildInfoRow(
          '審核狀態',
          passport != null ? _signalToText(passport.signal) : '未提交',
          ds,
        ),
        _buildInfoRow('NFT', '未鑄造（Phase E+ 開發中）', ds),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('DAO/NFT 功能 Phase E+ 開發...')),
              );
            },
            icon: const Icon(Icons.rocket_launch_outlined, size: 18),
            label: const Text('發行成 NFT'),
          ),
        ),
      ],
    );
  }

  Widget _buildAppearanceSection(Companion companion, BridgeDSColors ds) {
    final stateCount = companion.stateImagePaths.length;
    final stateLabels = <String, String>{
      'pointing': '指路',
      'stuck': '卡住了',
      'reading': '閱讀',
      'wandering': '漫遊',
      'idea': '好點子',
      'bridging': '橋接',
      'celebrating': '慶祝',
      'writing': '編寫中',
    };
    return _buildSection(
      title: '形象與狀態圖',
      icon: Icons.image_outlined,
      ds: ds,
      children: [
        _buildInfoRow(
          '主形象',
          companion.avatarImagePath != null ? '已生成' : '未生成',
          ds,
        ),
        _buildInfoRow('狀態圖', '$stateCount/8 張完成', ds),
        // [教練 Agent 2026-08-12] 狀態圖預覽網格
        if (stateCount > 0) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: stateLabels.entries.map((e) {
              final path = companion.stateImagePaths[e.key];
              return _buildStateImageChip(e.key, e.value, path, ds);
            }).toList(),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              // [教練 Agent 2026-08-04 Phase E+] 內嵌模式用 callback
              onPressed: () {
                if (widget.onNavigateTo != null) {
                  widget.onNavigateTo!('appearance');
                } else {
                  context.go(
                    '/companion/appearance?id=${companion.id}&returnTo=${Uri.encodeComponent('/companion/control?id=${companion.id}')}',
                  );
                }
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('編輯形象'),
            ),
          ],
        ),
      ],
    );
  }

  /// [教練 Agent 2026-08-12] 狀態圖縮圖 chip
  Widget _buildStateImageChip(String key, String label, String? path, BridgeDSColors ds) {
    final hasRig = kRigByCompanion.containsKey(_companion?.name ?? '');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: hasRig ? () => _showRigStateDialog(key, label) : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: ds.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ds.borderSubtle, width: 1),
              ),
              // [小葵 2026-09-13] rig 分支封存（Blue 拍板回歸靜態圖）——重啟=恢復 hasRig 分支
              child: (path != null && path.isNotEmpty && File(path).existsSync())
                      ? Image.file(
                          File(path),
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.broken_image_outlined,
                            size: 24,
                            color: ds.textMuted,
                          ),
                        )
                      : Icon(
                          Icons.image_outlined,
                          size: 24,
                          color: ds.textMuted.withValues(alpha: 0.3),
                        ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: ds.caption.copyWith(fontSize: 11),
        ),
      ],
    );
  }

  /// [小葵 2026-09-12] 活體狀態放大預覽——點 chip 開 dialog，rig 即時動畫
  void _showRigStateDialog(String stateId, String label) {
    final ds = BridgeDSColors.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: ds.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: ds.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 260,
                height: 400,
                child: Center(
                  child: CompanionRigAnimator(
                    companionName: _companion!.name,
                    stateId: stateId,
                    size: 260,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildActionButtons(Companion companion, BridgeDSColors ds) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              CompanionStore().setActive(companion.id);
              context.go('/chat');
            },
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('進入對話'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: ds.borderDefault),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('開啟畫布功能開發中...')),
              );
            },
            icon: const Icon(Icons.grid_on_outlined),
            label: const Text('開啟畫布'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: ds.borderDefault),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('匯出角色包功能開發中...')),
              );
            },
            icon: const Icon(Icons.download_outlined),
            label: const Text('匯出角色包'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: ds.borderDefault),
            ),
          ),
        ),
      ],
    );
  }

  // Helper methods
  Widget _buildSection({
    required String title,
    required IconData icon,
    required BridgeDSColors ds,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ds.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: ds.accentBlue),
              const SizedBox(width: 8),
              Text(
                title,
                style: ds.headingM.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, BridgeDSColors ds) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: ds.body.copyWith(color: ds.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: ds.body.copyWith(color: ds.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  String _signalToText(CompanionRightsSignal signal) {
    switch (signal) {
      case CompanionRightsSignal.unreviewed:
        return '待審核';
      case CompanionRightsSignal.approved:
        return '✅ 已通過';
      case CompanionRightsSignal.watching:
        return '⚠️ 觀察中';
      case CompanionRightsSignal.blocked:
        return '❌ 已封鎖';
    }
  }
}
