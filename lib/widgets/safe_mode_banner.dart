// SafeModeBanner — 安全模式黃色橫幅（自救三刀・刀一 UI）
//
// [小葵 2026-10-31 Safe Mode] 設計鐵則（計劃卡 docs/SELF_RESCUE_THREE_BLADES_PLAN.md）：
// - 明顯但不擋操作——頂部橫幅，不是彈窗（「確認類走全域對話」鐵則：
//   橫幅是狀態告知不是確認框，使用者可以無視它繼續用 App）
// - 誠實 UI：白話解釋發生了什麼、保證資料完好、給明確出路
// - 按鈕樣式走 BridgePillButton（primary=黑底白粗體、ghost=描邊——既有偏好）
//
// 刀二留位：計劃卡的橫幅規格有〔匯出診斷報告〕按鈕——屬刀二範圍，
// 此處先留註解位，刀二合流時在 _retry 旁加 BridgePillButton（type: ghost）。

import 'package:flutter/material.dart';

import '../../services/system/crash_guard.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import 'bridge_desktop_widgets.dart';

/// Safe Mode 頂部黃色橫幅。
///
/// 用法：掛在 MaterialApp builder 的 child 上方（app.dart），
/// CrashGuard.safeMode == false 時整條橫幅不佔任何空間。
class SafeModeBanner extends StatelessWidget {
  const SafeModeBanner({super.key, this.onExited});

  /// 退出 Safe Mode 後的額外回呼（留給主線：例如跳出 SnackBar 告知重掃中）
  final void Function()? onExited;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CrashGuard.instance,
      builder: (context, _) {
        if (!CrashGuard.instance.shouldShowBanner) return const SizedBox.shrink();
        return _BannerBody(onExited: onExited);
      },
    );
  }
}

class _BannerBody extends StatelessWidget {
  const _BannerBody({this.onExited});

  final void Function()? onExited;

  /// 黃色系（明顯但不刺眼）——App 的 BridgeDSColors 無 warning token，
  /// 專案既有黃色前例（galaxy 面板 0xFFF0CE5E）走 const Color，此處照做。
  static const Color _bannerYellow = Color(0xFFF0CE5E);

  @override
  Widget build(BuildContext context) {
    final darkText = BridgeDSColors.of(context).canvas; // 深色主題下 canvas 近黑，黃底上當深字用
    return Material(
      color: _bannerYellow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.health_and_safety_outlined, color: darkText, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '安全模式：系統偵測到 App 最近異常重啟，已暫停背景索引與本地模型自動排程。你的資料完好無損。',
                style: TierStyle.of(context, Tier.cardBody)
                    .toTextStyle()
                    .copyWith(color: darkText, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 12),
            // 〔重試背景服務〕——退出 Safe Mode 並重新拉背景索引
            BridgePillButton(
              label: '重試背景服務',
              icon: Icons.refresh,
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await CrashGuard.instance.exitSafeMode();
                  onExited?.call();
                } catch (e) {
                  // 誠實 UI：重試失敗要讓使用者知道，不假裝成功
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('背景服務重啟失敗：$e'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
            const SizedBox(width: 8),
            // 〔知道了〕——只收橫幅，Safe Mode 狀態不變（背景服務維持暫停）
            BridgePillButton(
              label: '知道了',
              type: BridgeButtonType.ghost,
              onPressed: () => CrashGuard.instance.dismissBanner(),
            ),
            // [刀二留位] 〔匯出診斷報告〕按鈕——DiagnosticBox 合流時在此加
            // BridgePillButton(label: '匯出診斷報告', type: BridgeButtonType.ghost, ...)
          ],
        ),
      ),
    );
  }
}
