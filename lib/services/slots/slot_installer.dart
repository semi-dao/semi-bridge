// Slot Installer — C3 Tier 1 執行引擎的「安裝」段
//
// 流程：GitHub tarball 下載 → 解壓（剝頂層目錄）→ 落插槽資料夾
// → 偵測 HTML 入口 → 紅隊掃描 → 回報。誠實鐵則：任何一步失敗都紅字
// 回報原因，絕不假成功。
//
// 硬體不寫死（Blue 2026-10-06 令）：埠/路徑/模型都不綁；這裡只碰
// GitHub 公開端點與插槽自身資料夾。

import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'slot_redteam_scanner.dart';

class SlotInstallResult {
  final bool ok;
  final String? entryHtmlPath; // 相對插槽資料夾（如 index.html）
  final String? version; // commit/branch 標籤
  final int fileCount;
  final SlotRedTeamReport? redTeam;
  final String? error; // 失敗原因（誠實紅字用）
  const SlotInstallResult({
    required this.ok,
    this.entryHtmlPath,
    this.version,
    this.fileCount = 0,
    this.redTeam,
    this.error,
  });
  const SlotInstallResult.fail(this.error)
      : ok = false,
        entryHtmlPath = null,
        version = null,
        fileCount = 0,
        redTeam = null;
}

class SlotInstaller {
  SlotInstaller._();
  static final instance = SlotInstaller._();

  /// 安裝 GitHub HTML 工具到插槽資料夾。
  ///
  /// [repoUrl] 形如 https://github.com/owner/repo
  /// [slotDir] 插槽專屬資料夾（已由 SlotRegistry 建立）
  Future<SlotInstallResult> install({
    required String repoUrl,
    required Directory slotDir,
  }) async {
    final slug = _parseSlug(repoUrl);
    if (slug == null) {
      return const SlotInstallResult.fail('不是有效的 GitHub 連結');
    }
    final (owner, repo) = slug;

    // ── 1. 下載 tarball（main → master fallback）──
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 3),
      responseType: ResponseType.bytes,
      followRedirects: true,
      headers: {'User-Agent': 'bridge-app-slot-installer'},
    ));

    Uint8List? tarBytes;
    String? branchUsed;
    Object? lastErr;
    for (final branch in const ['main', 'master']) {
      try {
        final res = await dio.get<List<int>>(
            'https://codeload.github.com/$owner/$repo/tar.gz/refs/heads/$branch');
        tarBytes = Uint8List.fromList(res.data ?? []);
        if (tarBytes.isNotEmpty) {
          branchUsed = branch;
          break;
        }
      } catch (e) {
        lastErr = e;
      }
    }
    if (tarBytes == null || tarBytes.isEmpty) {
      return SlotInstallResult.fail(
          '下載失敗（main/master 都試過）：$lastErr。可能是私有 repo、網路不通、或分支名不標準');
    }

    // ── 2. 解壓（剝頂層 owner-repo-xxxx/ 目錄）──
    final Archive archive;
    try {
      archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(tarBytes));
    } catch (e) {
      return SlotInstallResult.fail('解壓失敗（不是合法 tar.gz）：$e');
    }

    // 先清掉舊安裝（重裝場景）
    if (await slotDir.exists()) {
      await slotDir.delete(recursive: true);
    }
    await slotDir.create(recursive: true);

    var fileCount = 0;
    var entryHtmlPath = <String?>[
      'index.html', // 最常見：根目錄 index.html
    ];
    String? foundEntry;
    final htmlAtRoot = <String>[];
    for (final f in archive.files) {
      if (!f.isFile) continue;
      var rel = f.name;
      final firstSlash = rel.indexOf('/');
      if (firstSlash == -1) continue; // tarball 頂層目錄外的怪檔
      rel = rel.substring(firstSlash + 1);
      if (rel.isEmpty) continue;
      // 安全：擋掉路徑逃脫（../）與絕對路徑——紅隊基本功
      if (rel.contains('..') || rel.startsWith('/')) {
        continue;
      }
      final out = File('${slotDir.path}/$rel');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>);
      fileCount++;
      if (rel.endsWith('.html')) {
        htmlAtRoot.add(rel);
        if (entryHtmlPath.contains(rel)) foundEntry ??= rel;
      }
    }

    if (fileCount == 0) {
      return const SlotInstallResult.fail('tarball 內容是空的——repo 可能沒有檔案');
    }

    // 入口偵測：根目錄 index.html 優先，其次根目錄任一 .html
    if (foundEntry == null) {
      final rootHtml =
          htmlAtRoot.where((p) => !p.contains('/')).toList()..sort();
      if (rootHtml.isNotEmpty) {
        foundEntry = rootHtml.first;
        debugPrint('[SlotInstaller] 無 index.html，改用 ${rootHtml.first}');
      }
    }

    // 藍圖屋偵測（Blue 拍板 2026-10-06）：見 _detectBlueprintFallback
    if (foundEntry != null) {
      final distFallback =
          await _detectBlueprintFallback(slotDir, foundEntry);
      if (distFallback != null) foundEntry = distFallback;
    }

    if (foundEntry == null) {
      return const SlotInstallResult.fail(
          '找不到 HTML 入口（根目錄沒有任何 .html）——這可能不是 Tier 1 純網頁工具');
    }

    // ── 3. 紅隊掃描 ──
    final redTeam = await SlotRedTeamScanner.scan(slotDir, entryRel: foundEntry);

    return SlotInstallResult(
      ok: true,
      entryHtmlPath: foundEntry,
      version: branchUsed,
      fileCount: fileCount,
      redTeam: redTeam,
    );
  }

  /// owner/repo 解析（複用 GithubRepoInfo 的規則，簡版）
  (String, String)? _parseSlug(String url) {
    final m = RegExp(
      r'github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)',
    ).firstMatch(url.trim());
    if (m == null) return null;
    final repo = m.group(2)!.replaceAll('.git', '');
    if (repo.isEmpty) return null;
    return (m.group(1)!, repo);
  }

  /// 藍圖屋偵測：根 index.html 引用不存在的本地檔（如 /src/main.ts）
  /// ＝開發版施工圖，真房子在 dist/。Vite/webpack 類 repo 通用。
  /// 回傳 dist 入口路徑（自足驗證通過時），否則 null（沿用原入口）。
  Future<String?> _detectBlueprintFallback(
      Directory slotDir, String foundEntry) async {
    if (foundEntry.contains('/')) return null;
    final entryContent =
        await File('${slotDir.path}/$foundEntry').readAsString();
    final localRefs = RegExp(r'''(?:src|href)\s*=\s*["'](/[^"']+)["']''')
        .allMatches(entryContent)
        .map((m) => m.group(1)!.replaceFirst('/', ''))
        .where((ref) => !ref.startsWith('http'));
    final missing = <String>[];
    for (final ref in localRefs) {
      if (!await File('${slotDir.path}/$ref').exists()) missing.add(ref);
    }
    // 引用 TypeScript/JSX 原始碼＝開發版鐵證（瀏覽器只能跑 .js）——
    // 即使檔案存在也是藍圖（mermview 案：src/main.ts 在但沒 build 不能跑）
    final tsRefs = localRefs.where((r) =>
        r.endsWith('.ts') || r.endsWith('.tsx') || r.endsWith('.jsx'));
    if (tsRefs.isNotEmpty) {
      debugPrint('[SlotInstaller] 入口引用 TS/JSX 原始碼（開發版鐵證）：$tsRefs');
    } else if (missing.isEmpty) {
      return null;
    }
    debugPrint('[SlotInstaller] 根入口引用不存在的檔案（藍圖屋特徵）：$missing');
    final distCandidates = <String>[];
    final distDir = Directory('${slotDir.path}/dist');
    if (await distDir.exists()) {
      await for (final e in distDir.list()) {
        if (e is File && e.path.endsWith('.html')) {
          distCandidates.add('dist/${e.path.split('/').last}');
        }
      }
    }
    // dist/index.html 最優先，其餘按名稱排序
    distCandidates.sort((a, b) {
      if (a == 'dist/index.html') return -1;
      if (b == 'dist/index.html') return 1;
      return a.compareTo(b);
    });
    for (final cand in distCandidates) {
      final content = await File('${slotDir.path}/$cand').readAsString();
      final refs = RegExp(r'''(?:src|href)\s*=\s*["']([^"']+)["']''')
          .allMatches(content)
          .map((m) => m.group(1)!)
          .where((r) =>
              !r.startsWith('http') &&
              !r.startsWith('data:') &&
              !r.startsWith('#') &&
              r.contains('.'));
      var allExist = true;
      for (final ref in refs) {
        final rel = ref.startsWith('/') ? ref.substring(1) : ref;
        if (!await File('${slotDir.path}/$rel').exists()) {
          allExist = false;
          break;
        }
      }
      if (allExist) {
        debugPrint('[SlotInstaller] 改用打包完成入口：$cand');
        return cand;
      }
    }
    return null;
  }

  /// 測試用：從本機 tar.gz 位元流安裝（不碰網路）。
  @visibleForTesting
  Future<SlotInstallResult> installFromBytes(
      Uint8List tarGzBytes, Directory slotDir) async {
    final Archive archive;
    try {
      archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(tarGzBytes));
    } catch (e) {
      return SlotInstallResult.fail('解壓失敗：$e');
    }
    if (await slotDir.exists()) await slotDir.delete(recursive: true);
    await slotDir.create(recursive: true);
    var fileCount = 0;
    String? foundEntry;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      var rel = f.name;
      final firstSlash = rel.indexOf('/');
      if (firstSlash == -1) continue;
      rel = rel.substring(firstSlash + 1);
      if (rel.isEmpty || rel.contains('..') || rel.startsWith('/')) continue;
      final out = File('${slotDir.path}/$rel');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>);
      fileCount++;
      if (rel == 'index.html') foundEntry ??= rel;
    }
    if (fileCount == 0) return const SlotInstallResult.fail('空 tarball');
    // 與 install() 同規格：無入口先失敗；有入口則跑藍圖屋偵測（dist fallback）
    if (foundEntry == null) {
      return const SlotInstallResult.fail('找不到 HTML 入口');
    }
    final distFallback =
        await _detectBlueprintFallback(slotDir, foundEntry);
    if (distFallback != null) foundEntry = distFallback;
    final redTeam = await SlotRedTeamScanner.scan(slotDir, entryRel: foundEntry);
    return SlotInstallResult(
        ok: true, entryHtmlPath: foundEntry, fileCount: fileCount, redTeam: redTeam);
  }
}
