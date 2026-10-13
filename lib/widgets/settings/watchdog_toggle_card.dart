import 'dart:io';

import 'package:flutter/material.dart';

import '../bridge_desktop_widgets.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// 自我喚醒（防崩潰看門狗）開關卡片——Watchdog v3 搭檔
///
/// 單一真相源：sentinel 檔
/// `~/Library/Application Support/farm.semiwasabi.bridgeApp/watchdog_disabled.flag`
/// - 檔案存在 = 自我喚醒關閉（看門狗不拉起，關掉的 App 就真的關掉）
/// - 檔案不存在 = 自我喚醒開啟（App 崩潰/被殺後 30 秒內自動復活，預設）
///
/// 系統層 watchdog（launchd farm.semiwasabi.bridgeApp.watchdog）每 30 秒輪詢此檔。
/// App 端只寫這個檔，不直接控制 launchd——單向契約、無反向依賴。
class WatchdogToggleCard extends StatefulWidget {
  const WatchdogToggleCard({super.key});

  @override
  State<WatchdogToggleCard> createState() => _WatchdogToggleCardState();
}

class _WatchdogToggleCardState extends State<WatchdogToggleCard> {
  bool _selfReviveEnabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  String get _sentinel =>
      '${Platform.environment['HOME']}/Library/Application Support/farm.semiwasabi.bridgeApp/watchdog_disabled.flag';

  Future<void> _loadState() async {
    bool disabled = false;
    try {
      disabled = await File(_sentinel).exists();
    } catch (_) {
      disabled = false;
    }
    if (!mounted) return;
    setState(() {
      _selfReviveEnabled = !disabled;
      _loading = false;
    });
  }

  Future<void> _setSelfRevive(bool enabled) async {
    setState(() => _loading = true);
    try {
      if (enabled) {
        final f = File(_sentinel);
        if (await f.exists()) await f.delete();
      } else {
        final f = File(_sentinel);
        await f.create(recursive: true);
        await f.writeAsString('disabled by user from app settings\n');
      }
    } catch (_) {
      // 寫檔失敗不靜默：狀態保持原樣，UI 由 _loadState 回讀真相
    }
    await _loadState();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return BridgeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety,
                  color: colors.accentGreen, size: 16),
              const SizedBox(width: 8),
              SelectableText('自我喚醒（防崩潰保護）',
                  style:
                      TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
              const Spacer(),
              BridgeStatusTag(
                label: _loading
                    ? '…'
                    : _selfReviveEnabled
                        ? '已啟用'
                        : '已關閉',
                type: _selfReviveEnabled
                    ? BridgeTagType.success
                    : BridgeTagType.info,
              ),
            ],
          ),
          const SizedBox(height: BridgeDS.spaceMD),
          _infoRow(
              '作用',
              _selfReviveEnabled
                  ? 'App 崩潰或意外關閉後，30 秒內自動重新啟動'
                  : 'App 關閉後不會自動重開（完全手動啟動）'),
          _infoRow('狀態檔', 'watchdog_disabled.flag（系統層輪詢）'),
          const SizedBox(height: BridgeDS.spaceMD),
          Row(
            children: [
              SelectableText('啟用自我喚醒',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
              const Spacer(),
              Switch(
                value: _selfReviveEnabled,
                onChanged: _loading ? null : _setSelfRevive,
              ),
            ],
          ),
          if (!_selfReviveEnabled)
            Padding(
              padding: const EdgeInsets.only(top: BridgeDS.spaceSM),
              child: SelectableText(
                '已關閉：之後把 App 關掉就會真的關掉。App 若崩潰也不會自動重開，需自行重新啟動。',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: colors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BridgeDS.spaceSM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: SelectableText(label,
                style:
                    TierStyle.of(context, Tier.cardCaption).toTextStyle()),
          ),
          Expanded(
            child: SelectableText(value,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
          ),
        ],
      ),
    );
  }
}
