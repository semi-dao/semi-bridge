/// master_folder_card.dart
/// [Blue 令 2026-10-17] 資安邊界卡——App 只碰登錄進向量資料庫的資料夾。
/// [Blue 令 2026-10-17 追加] 空白處列出已載入資料夾清單＋更新時間。
///
/// 真相源：AssetSandbox.rootPaths（vector_db_root_paths）——vault 樹的
/// 同一個源（不是舊 master_folders 機制，那是空的）。每根顯示：
/// 路徑＋檔案數（manifest）＋更新時間（.bridge/manifest.json mtime）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import '../../services/vector_db/asset_sandbox.dart';
import '../../services/vector_db/asset_index_service.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

class MasterFolderCard extends StatefulWidget {
  const MasterFolderCard({super.key});

  @override
  State<MasterFolderCard> createState() => _MasterFolderCardState();
}

class _MasterFolderEntry {
  final String path;
  final int fileCount;
  final DateTime? updatedAt;
  final bool offline; // 根不存在（外接碟未掛載）
  _MasterFolderEntry(this.path, this.fileCount, this.updatedAt, this.offline);
}

class _MasterFolderCardState extends State<MasterFolderCard> {
  List<_MasterFolderEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await AssetSandbox().ensurePrefsLoaded();
    final index = AssetIndexService();
    await index.loadManifests();
    final roots = AssetSandbox().rootPaths;
    final entries = <_MasterFolderEntry>[];
    for (final root in roots) {
      final dir = Directory(root);
      final exists = await dir.exists();
      // 檔案數：manifest 中屬於此根的檔案。
      // [Blue 抓包 2026-10-17] ManifestFile.path 是相對路徑，
      // 根在 folder 欄——startsWith(root) 全 miss 顯示 0 檔。
      var count = 0;
      try {
        count = index.allFiles.where((f) => f.folder == root).length;
      } catch (_) {}
      // 更新時間：.bridge/manifest.json 的 mtime
      DateTime? updated;
      try {
        final m = File('$root/.bridge/manifest.json');
        if (await m.exists()) {
          updated = (await m.stat()).modified;
        }
      } catch (_) {}
      entries.add(_MasterFolderEntry(root, count, updated, !exists));
    }
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);

    return Card(
      color: ds.surfaceElevated,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(Icons.shield_outlined, size: 18, color: ds.accentGreen),
              const SizedBox(width: 8),
              Text('資安邊界（主資料夾）',
                  style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
            ]),
            const SizedBox(height: 4),
            Text(
              'App 只讀取這裡登錄的資料夾（進向量資料庫）——其餘一律不碰。這是我們與使用者的資安契約。',
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: ds.textSecondary),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_entries.isEmpty)
              Text(
                '尚未設定——加入資料夾後這裡會列出清單。',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: ds.textTertiary),
              )
            else ...[
              // [Blue 令] 清單＋更新時間
              Text('已載入資料夾（${_entries.length}）',
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: ds.textSecondary)),
              const SizedBox(height: 6),
              ..._entries.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                            e.offline
                                ? Icons.usb_off_outlined
                                : Icons.folder_open,
                            size: 16,
                            color: e.offline
                                ? ds.accentRed
                                : ds.accentBlue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.path,
                                  overflow: TextOverflow.ellipsis,
                                  style: TierStyle.of(context, Tier.cardCaption)
                                      .toTextStyle()),
                              Text(
                                '${e.offline ? '離線（未掛載）· ' : ''}'
                                '${e.fileCount} 檔 · 更新 ${_fmtDate(e.updatedAt)}',
                                style: TierStyle.of(context, Tier.cardCaption)
                                    .toTextStyle()
                                    .copyWith(
                                        color: e.offline
                                            ? ds.accentRed
                                            : ds.textTertiary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}
