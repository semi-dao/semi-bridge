import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:flutter/material.dart';

import 'home_snapshot.dart';

/// [S4 2026-11-10] runtimeSnapshot key → 中文語意標籤。
/// 未登錄的 key 照原樣顯示（寧原文不吞資料——誠實鐵則）。
const _kLabels = <String, String>{
  'platform': '桌面平台',
  'desktopName': '桌面名稱',
  'gatewayRunning': 'Gateway',
  'gatewayPort': '連線埠',
  'mobileConnected': '手機連線',
  'activeCompanion': '目前夥伴',
  'appVersion': '版本',
  'timestamp': '快照時間',
};

/// [S4 2026-11-10] 快照中要隱藏的 key（recentChat 獨立渲染；timestamp 頂部已有）。
const _kHidden = {'recentChat', 'timestamp'};

String _labelFor(String key) => _kLabels[key] ?? key;

/// [S4 2026-11-10] 布林值 → 人話（不顯示 true/false 給使用者看）。
String _valueFor(String key, Object? value) {
  if (value is bool) return value ? '運行中' : '停止';
  if (key == 'platform') {
    switch (value) {
      case 'macos':
        return 'macOS';
      case 'windows':
        return 'Windows';
      case 'linux':
        return 'Linux';
    }
  }
  if (key == 'timestamp' && value is String && value.length >= 16) {
    // ISO 8601 → HH:mm
    return '${value.substring(11, 13)}:${value.substring(14, 16)}';
  }
  return value?.toString() ?? '—';
}

/// [S4 2026-11-10] 快照語意化渲染——raw key-value 升級為產品級顯示。
/// 兩欄式（標籤左、值右）；Tier 字級＋BridgeDSColors，零 Material 預設。
class SnapshotEntriesView extends StatelessWidget {
  final HomeSnapshot snapshot;

  const SnapshotEntriesView({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    final entries = snapshot.content.entries
        .where((e) => !_kHidden.contains(e.key))
        .toList();
    final recentChat = snapshot.content['recentChat'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    _labelFor(entry.key),
                    style: colors.caption.copyWith(color: colors.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _valueFor(entry.key, entry.value),
                    style: colors.body.copyWith(color: colors.textPrimary),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        // [S4 2026-11-10] 最近對話——手機看得到 AI 回覆（對話層第一步）
        if (recentChat is List && recentChat.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('最近對話', style: colors.caption.copyWith(color: colors.textSecondary)),
          const SizedBox(height: 6),
          for (final item in recentChat)
            if (item is Map)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (item['role'] == 'assistant') ? '🤖' : '🧑',
                      style: colors.body,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item['text'] ?? ''}',
                        style: colors.body.copyWith(color: colors.textPrimary),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ],
    );
  }
}
