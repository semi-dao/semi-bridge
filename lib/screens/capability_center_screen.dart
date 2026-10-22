/// CapabilityCenterScreen — 金鑰匙系統
///
/// 設計文件: 02-架構設計/keychain-settings-design.md §5
/// [教練 Agent 2026-08-01] Phase 1 — 取代 GoldenKeysScreen
/// [教練 Agent 2026-08-11] 正名為「金鑰匙系統」——API key 唯一入口
///
/// 能力導向的 API Key 管理介面：
/// - 10 大能力分類，每個能力一張卡片
/// - 每張卡片顯示服務列表、開通狀態
/// - 點擊展開 → 管理服務、輸入 Key、測試連線
/// - Key 共用智慧提示
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/capability/capability_models.dart';
import '../services/capability/service_registry.dart';
import '../services/capability/capability_executor.dart';
import '../services/storage_service.dart';
import '../theme/bridge_design_system.dart';
import '../widgets/bridge_desktop_widgets.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../widgets/trust/capability_maturity_badge.dart'; // [刀 6 K6.5]
import '../../widgets/adaptive_scaffold.dart';
import '../../widgets/settings/brain_api_config_card.dart';

class CapabilityCenterScreen extends StatefulWidget {
  final String? returnTo;

  const CapabilityCenterScreen({super.key, this.returnTo});

  @override
  State<CapabilityCenterScreen> createState() => _CapabilityCenterScreenState();
}

class _CapabilityCenterScreenState extends State<CapabilityCenterScreen> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initRegistry();
  }

  Future<void> _initRegistry() async {
    await ServiceRegistry.instance.initialize();
    if (mounted) setState(() => _initialized = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final groups = ServiceRegistry.instance.capabilityGroups;

    return Scaffold(
      appBar: AppBar(
        title: const Text('金鑰匙系統'),
        leading: widget.returnTo != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go(widget.returnTo!),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // [教練 Agent 2026-08-11] 主腦 API 設定——金鑰匙系統最重要的區塊
          const BrainApiConfigCard(),
          const SizedBox(height: 16),
          // 能力分類卡片
          ...groups.map((group) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CapabilityCard(group: group),
          )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 能力卡片
// ═══════════════════════════════════════════════════

class _CapabilityCard extends StatefulWidget {
  final CapabilityGroup group;

  const _CapabilityCard({required this.group});

  @override
  State<_CapabilityCard> createState() => _CapabilityCardState();
}

class _CapabilityCardState extends State<_CapabilityCard> {
  bool _expanded = false;
  bool _checkingStatus = true;
  bool _activated = false;
  int _activatedCount = 0;

  /// [刀 6 K6.5] 三態成熟度自評表——誠實聲明，只有該能力的維護者知道真相。
  /// 預設 🚧（寧可保守）；已驗證完整的標 ✅；還在紙上的標 💭。
  CapabilityMaturity _maturityFor(String displayName) {
    switch (displayName) {
      case '圖像生成':
      case '文字對話':
        return CapabilityMaturity.ready; // 主鏈路健走多時
      case '視頻生成':
      case '語音合成':
        return CapabilityMaturity.ready;
      default:
        return CapabilityMaturity.wiring; // 其餘保守標接線中
    }
  }

  @override
  void initState() {
    super.initState();
    _checkActivation();
  }

  Future<void> _checkActivation() async {
    final activated = await ServiceRegistry.instance.activatedServicesFor(
      widget.group.capability,
    );
    if (mounted) {
      setState(() {
        _activatedCount = activated.length;
        _activated = activated.isNotEmpty;
        _checkingStatus = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cap = widget.group.capability;
    final ds = BridgeDSColors.of(context);

    return BridgeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(cap.icon, size: 28, color: cap.color(context)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(cap.displayName, style: BridgeDS.headingS),
                            const SizedBox(width: 8),
                            // [刀 6 K6.5] 三態成熟度標記（Buzz 式誠實分級）
                            CapabilityMaturityBadge(
                                maturity: _maturityFor(cap.displayName)),
                            const SizedBox(width: 8),
                            if (_checkingStatus)
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              _StatusBadge(
                                activated: _activated,
                                count: _activatedCount,
                              ),
                          ],
                        ),
                        Text(
                          cap.description,
                          style: BridgeDS.small.copyWith(
                            color: ds.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: ds.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // Expanded services list
          if (_expanded) ...[
            const Divider(height: 24),
            // [Blue 令 2026-10-20] 能力級預設——該能力有 ≥2 個已開通服務時，
            // 可勾選預設服務（全線 APP 照此執行）。存 role_provider_map
            // （key=能力 id 如 image_generation，value=服務 id 如 minimax_image）。
            _CapabilityDefaultPicker(capability: widget.group.capability),
            ...widget.group.services.map(
              (service) =>
                  _ServiceTile(service: service, onChanged: _checkActivation),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// [Blue 令 2026-10-20] 能力級預設選擇器——
// 該能力有 ≥2 個已開通服務時顯示「預設服務」下拉。
// 儲存 key = 能力 id（image_generation 等），與活預設共用 role_provider_map。
// ═══════════════════════════════════════════════════

class _CapabilityDefaultPicker extends StatefulWidget {
  final CapabilityId capability;

  const _CapabilityDefaultPicker({required this.capability});

  @override
  State<_CapabilityDefaultPicker> createState() =>
      _CapabilityDefaultPickerState();
}

class _CapabilityDefaultPickerState extends State<_CapabilityDefaultPicker> {
  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return FutureBuilder<List<ServiceDefinition>>(
      future: ServiceRegistry.instance.activatedServicesFor(widget.capability),
      builder: (context, snap) {
        final activated = snap.data ?? [];
        // 未開通或只有一個選項 → 沒有「選預設」的意義
        if (activated.length < 2) return const SizedBox.shrink();
        final capKey = widget.capability.id;
        return FutureBuilder<Map<String, String>>(
          future: StorageService.getRoleProviderMap(),
          builder: (context, roleSnap) {
            final current = roleSnap.data?[capKey] ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.star_outline,
                      size: 14, color: ds.accentYellow),
                  const SizedBox(width: 6),
                  Text('預設服務',
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(color: ds.textSecondary)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: activated.any((s) => s.id == current)
                          ? current
                          : '',
                      items: [
                        const DropdownMenuItem(
                            value: '',
                            child: Text('自動（第一個可用）',
                                style: TextStyle(fontSize: 13))),
                        for (final s in activated)
                          DropdownMenuItem(
                              value: s.id,
                              child: Text('${s.providerName}・${s.serviceName}',
                                  style: const TextStyle(fontSize: 13))),
                      ],
                      onChanged: (v) async {
                        await StorageService.saveRoleProvider(
                            capKey, v ?? '');
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════
// 服務卡片（展開後的每個服務）
// ═══════════════════════════════════════════════════

class _ServiceTile extends StatefulWidget {
  final ServiceDefinition service;
  final VoidCallback onChanged;

  const _ServiceTile({required this.service, required this.onChanged});

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  bool _hasKey = false;
  bool _testing = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _checkKey();
  }

  Future<void> _checkKey() async {
    if (widget.service.keyRequirement.type == KeyType.none) {
      setState(() => _hasKey = true);
      return;
    }

    final storageKey = widget.service.keyRequirement.storageKey;
    if (storageKey == null) return;

    final token = await StorageService.getToken(provider: storageKey);
    if (mounted) {
      setState(() => _hasKey = token != null && token.isNotEmpty);
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    final result = await CapabilityExecutor.instance.testConnection(
      widget.service,
    );

    if (mounted) {
      setState(() {
        _testing = false;
        _testResult = result.message;
        _testSuccess = result.success;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final service = widget.service;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${service.providerName} · ${service.serviceName}',
                      style: BridgeDS.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (service.note != null)
                      Text(
                        service.note!,
                        style: BridgeDS.small.copyWith(color: ds.textSecondary),
                      ),
                  ],
                ),
              ),
              // Status dot
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hasKey
                      ? (service.status.isUsable
                            ? ds.accentGreen
                            : ds.accentYellow)
                      : ds.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
              // Test button
              if (_hasKey && service.keyRequirement.type != KeyType.none)
                TextButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check, size: 16),
                  label: Text(_testing ? '測試中' : '測試'),
                ),
            ],
          ),

          // Test result
          if (_testResult != null) ...[
            const SizedBox(height: 4),
            Text(
              _testResult!,
              style: BridgeDS.small.copyWith(
                color: _testSuccess ? ds.accentGreen : ds.accentRed,
              ),
            ),
          ],

          // Action button
          const SizedBox(height: 4),
          if (service.keyRequirement.type == KeyType.none)
            Text(
              '不需金鑰，已就緒',
              style: BridgeDS.small.copyWith(color: ds.accentGreen),
            )
          else if (!_hasKey)
            FilledButton.icon(
              onPressed: () => _showKeyDialog(context),
              icon: const Icon(Icons.key_outlined, size: 16),
              label: Text('設定 ${service.keyRequirement.label}'),
            )
          else
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showKeyDialog(context),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('管理'),
                ),
                if (service.pricing != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    service.pricing!.example,
                    style: BridgeDS.small.copyWith(color: ds.textSecondary),
                  ),
                ],
              ],
            ),

          // Deprecation warning
          if (service.status.needsWarning &&
              service.deprecationNotice != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ds.accentYellow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: ds.accentYellow.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: ds.accentYellow),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      service.deprecationNotice!,
                      style: BridgeDS.small.copyWith(color: ds.accentYellow),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // Key 輸入對話框
  // ═══════════════════════════════════════════════════

  void _showKeyDialog(BuildContext context) {
    final controller = TextEditingController();
    final keyReq = widget.service.keyRequirement;
    final isUrl = keyReq.type == KeyType.url;
    final ds = BridgeDSColors.of(context);

    // 預填已有的值
    if (keyReq.storageKey != null) {
      StorageService.getToken(provider: keyReq.storageKey).then((token) {
        if (token != null && mounted) {
          controller.text = token;
        }
      });
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          backgroundColor: ds.surface,
          title: Text(
            keyReq.label,
            style: theme.textTheme.titleMedium,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.service.description != null)
                Text(
                  widget.service.description!,
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: !isUrl,
                style: theme.textTheme.bodyLarge,
                cursorColor: theme.colorScheme.primary,
                decoration: InputDecoration(
                  labelText: keyReq.label,
                  hintText: keyReq.hint,
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(isUrl ? Icons.link : Icons.key),
                ),
              ),
              if (keyReq.getUrl != null) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => launchUrl(Uri.parse(keyReq.getUrl!)),
                  child: Text(
                    '取得 Key: ${keyReq.getUrl}',
                    style: TextStyle(
                      color: ds.accentBlue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _buildKeySharingHint(context),
            ],
          ),
          actions: [
            if (_hasKey)
              TextButton(
                onPressed: () async {
                  if (keyReq.storageKey != null) {
                    await StorageService.deleteToken(provider: keyReq.storageKey);
                  }
                  if (dialogContext.canPop()) dialogContext.pop();
                  _checkKey();
                  widget.onChanged();
                },
                child: const Text('刪除'),
              ),
            TextButton(
              onPressed: () => dialogContext.pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                if (keyReq.storageKey != null) {
                  await StorageService.saveToken(
                    value,
                    provider: keyReq.storageKey,
                  );
                }
                if (dialogContext.canPop()) dialogContext.pop();
                _checkKey();
                widget.onChanged();
              },
              child: const Text('儲存'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKeySharingHint(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final storageKey = widget.service.keyRequirement.storageKey;
    if (storageKey == null) return const SizedBox.shrink();

    final sharingServices = ServiceRegistry.instance.servicesSharingKey(
      storageKey,
    );
    if (sharingServices.length <= 1) return const SizedBox.shrink();

    final capNames = sharingServices
        .map((s) => s.capability.displayName)
        .toSet()
        .join('、');

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: ds.accentBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, size: 16, color: ds.accentBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '設定一把 ${widget.service.providerName} Key\n可同時開通：$capNames',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: ds.accentBlue),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// 狀態徽章
// ═══════════════════════════════════════════════════

class _StatusBadge extends StatelessWidget {
  final bool activated;
  final int count;

  const _StatusBadge({required this.activated, required this.count});

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: activated
            ? ds.accentGreen.withValues(alpha: 0.1)
            : ds.textTertiary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        activated ? '$count 個服務已開通' : '未開通',
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: activated ? ds.accentGreen : ds.textTertiary,
          fontWeight: FontWeight.w500,),
      ),
    );
  }
}
