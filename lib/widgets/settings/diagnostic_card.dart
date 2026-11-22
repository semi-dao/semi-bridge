import 'package:flutter/material.dart';

import '../../services/system/diagnostic_box.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../bridge_desktop_widgets.dart';

/// [小葵 2026-10-31 黑盒子] 診斷黑盒子卡（刀二）——系統頁的 flight recorder 面孔
///
/// 顯示最近 3 條事件摘要＋〔匯出診斷報告〕按鈕。
/// 匯出 = DiagnosticBox.exportMarkdown() 寫到使用者指定處
/// （file_picker 選位置；取消/不可用則 fallback 桌面，SnackBar 告知路徑）。
/// 報告零敏感資訊（路徑只到根目錄層、無 token、無對話內容——資料主權紅線）。
class DiagnosticCard extends StatefulWidget {
  const DiagnosticCard({super.key});

  @override
  State<DiagnosticCard> createState() => _DiagnosticCardState();
}

class _DiagnosticCardState extends State<DiagnosticCard> {
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    // 進場保證黑盒子已初始化（冪等，重複呼叫無副作用）
    DiagnosticBox.instance.ensureInit();
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      // fallbackDir 傳 null：走 HOME/Desktop 預設（測試可注入 tmp 目錄）
      final path = await DiagnosticBox.instance.exportToFile();
      if (!mounted) return;
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('匯出失敗——報告未能寫入。')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('診斷報告已匯出：$path')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    final recent = DiagnosticBox.instance.recent(3).reversed.toList();
    return BridgeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flight_takeoff, color: colors.accentBlue, size: 16),
              const SizedBox(width: 8),
              SelectableText('診斷黑盒子',
                  style:
                      TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
              const Spacer(),
              BridgeStatusTag(
                label: recent.isEmpty ? '無事件' : '${recent.length} 條近事',
                type: recent.isEmpty ? BridgeTagType.success : BridgeTagType.info,
              ),
            ],
          ),
          const SizedBox(height: BridgeDS.spaceSM),
          SelectableText(
            'App 自動記錄系統狀態（啟動、安全模式、崩潰線索、巡邏熔斷），'
            '異常時可一鍵匯出報告——給人看或給 Agent 讀。不含對話內容。',
            style: TierStyle.of(context, Tier.cardCaption)
                .toTextStyle()
                .copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: BridgeDS.spaceMD),
          if (recent.isEmpty)
            SelectableText(
              '最近沒有記錄到任何事件——一切平靜。',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
            )
          else
            ...recent.map((e) => _eventRow(
                  _shortTs(e['ts'] ?? ''),
                  DiagnosticBox.kindLabel(e['kind'] ?? 'unknown'),
                  e['detail'] ?? '',
                )),
          const SizedBox(height: BridgeDS.spaceMD),
          BridgePillButton(
            label: _exporting ? '匯出中…' : '匯出診斷報告',
            icon: Icons.file_download_outlined,
            type: BridgeButtonType.ghost,
            onPressed: _exporting ? null : _export,
            expanded: true,
          ),
        ],
      ),
    );
  }

  /// 單條事件列：時間＋類別標籤＋摘要（敏感已由黑盒子寫入前消毒）
  Widget _eventRow(String ts, String kind, String detail) {
    final colors = BridgeDSColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: BridgeDS.spaceSM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: SelectableText(ts,
                style:
                    TierStyle.of(context, Tier.cardCaption).toTextStyle()),
          ),
          SizedBox(
            width: 72,
            child: SelectableText(kind,
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: colors.accentBlue)),
          ),
          Expanded(
            child: SelectableText(detail,
                maxLines: 2,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
          ),
        ],
      ),
    );
  }

  /// 時間戳縮短（黑盒子同款格式）
  static String _shortTs(String iso) {
    try {
      final t = DateTime.parse(iso);
      final mm = t.month.toString().padLeft(2, '0');
      final dd = t.day.toString().padLeft(2, '0');
      final hh = t.hour.toString().padLeft(2, '0');
      final mi = t.minute.toString().padLeft(2, '0');
      return '$mm-$dd $hh:$mi';
    } catch (_) {
      return iso;
    }
  }
}
