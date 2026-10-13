// Slot Red-Team Scanner — 插槽安裝前的紅隊掃描
//
// [Spec C3/C6] 測試報告含紅隊章節：agent 親自攻它。本掃描器做靜態段——
// 掃整包檔案找危險模式；動態段（WebView 沙箱內實際跑、驗證網路隔離）
// 屬 C4 權限系統，這裡先把「看得見的風險」誠實列出。
//
// 分級：
//   BLOCK  外部腳本引用（CDN）——違反「純客戶端」預期，需網路權限才跑得動
//   WARN   需要網路 fetch/XHR、外部字型、上傳行為——裝了會跑一半
//   INFO   一般觀察（檔案大小、內嵌腳本量）

import 'dart:io';
import 'package:flutter/foundation.dart';

class SlotRedTeamReport {
  final List<String> blockers;
  final List<String> warnings;
  final List<String> infos;
  final int scannedFiles;
  final int htmlCount;
  const SlotRedTeamReport({
    required this.blockers,
    required this.warnings,
    required this.infos,
    required this.scannedFiles,
    required this.htmlCount,
  });
  bool get isClean => blockers.isEmpty;
}

class SlotRedTeamScanner {
  SlotRedTeamScanner._();

  /// 掃插槽資料夾全部檔案（HTML/JS 深掃，其他檔案計量）。
  static Future<SlotRedTeamReport> scan(Directory slotDir,
      {String? entryRel}) async {
    final blockers = <String>[];
    final warnings = <String>[];
    final infos = <String>[];

    var scanned = 0;
    var htmlCount = 0;
    var totalBytes = 0;

    final files = slotDir.listSync(recursive: true).whereType<File>().toList();
    for (final f in files) {
      scanned++;
      final rel = f.path.substring(slotDir.path.length + 1);
      final ext = rel.split('.').last.toLowerCase();
      totalBytes += await f.length();

      // 深掃 HTML 與 JS
      if (ext == 'html' || ext == 'htm' || ext == 'js') {
        if (ext != 'js') htmlCount++;
        final content = await f.readAsString();
        // BLOCK：外部腳本（非插槽內相對路徑）
        final extScripts = RegExp(
                r'''<script[^>]+src\s*=\s*["'](https?://[^"']+)["']''')
            .allMatches(content)
            .map((m) => m.group(1)!)
            .toSet();
        for (final u in extScripts) {
          blockers.add('$rel 引用外部腳本：$u（離線跑不動；需網路權限）');
        }
        // WARN：fetch/XHR 對外
        if (RegExp(r'''fetch\s*\(\s*["']https?://''').hasMatch(content) ||
            RegExp(r'XMLHttpRequest').hasMatch(content)) {
          warnings.add('$rel 有對外網路請求（fetch/XHR）——需要網路權限才能完整運作');
        }
        // WARN：外部字型/樣式
        final extLinks = RegExp(
                r'''<link[^>]+href\s*=\s*["'](https?://[^"']+)["']''')
            .allMatches(content)
            .map((m) => m.group(1)!)
            .toSet();
        for (final u in extLinks) {
          warnings.add('$rel 引用外部資源：$u（離線時樣式會缺）');
        }
        // INFO：大型內嵌腳本
        final inlineJs = RegExp(r'''<script(?![^>]*src)[^>]*>([\s\S]*?)</script>''');
        var inlineBytes = 0;
        for (final m in inlineJs.allMatches(content)) {
          inlineBytes += m.group(1)!.length;
        }
        if (inlineBytes > 200 * 1024) {
          infos.add('$rel 內嵌腳本 ${(inlineBytes / 1024).round()}KB——量大，注意效能');
        }
      }

      // 計量 INFO：巨型檔案
      final len = await f.length();
      if (len > 10 * 1024 * 1024) {
        infos.add('$rel ${(len / 1024 / 1024).toStringAsFixed(1)}MB——大檔案');
      }
    }

    if (entryRel != null) {
      infos.add('入口：$entryRel（${files.length} 檔，'
          '${(totalBytes / 1024).toStringAsFixed(0)}KB）');
    }

    debugPrint('[SlotRedTeam] 掃 $scanned 檔：'
        'block=${blockers.length} warn=${warnings.length} info=${infos.length}');
    return SlotRedTeamReport(
      blockers: blockers,
      warnings: warnings,
      infos: infos,
      scannedFiles: scanned,
      htmlCount: htmlCount,
    );
  }
}
