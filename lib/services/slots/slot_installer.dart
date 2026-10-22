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
import '../plugins/plugin_manifest.dart';
import '../plugins/plugin_slot_service.dart';
import '../skills/skill_catalog.dart';
import '../skills/skill_store.dart';
import 'slot_redteam_scanner.dart';
import 'slot_registry.dart';

class SlotInstallResult {
  final bool ok;
  final String? entryHtmlPath; // 相對插槽資料夾（如 index.html）
  final String? version; // commit/branch 標籤（plugin 分支＝manifest.version）
  final int fileCount;
  final SlotRedTeamReport? redTeam;
  final String? error; // 失敗原因（誠實紅字用）
  /// [A線 1022] plugin 分支識別——wizard 步驟2 顯示「這是 agent-plugins.org plugin」
  final String? pluginName;
  final int pluginSkillsCount; // manifest.skills 目錄掃到的 .md 數
  const SlotInstallResult({
    required this.ok,
    this.entryHtmlPath,
    this.version,
    this.fileCount = 0,
    this.redTeam,
    this.error,
    this.pluginName,
    this.pluginSkillsCount = 0,
  });
  const SlotInstallResult.fail(this.error)
      : ok = false,
        entryHtmlPath = null,
        version = null,
        fileCount = 0,
        redTeam = null,
        pluginName = null,
        pluginSkillsCount = 0;
}

class SlotInstaller {
  SlotInstaller._();
  static final instance = SlotInstaller._();

  /// [A線 2026-10-22] plugin 分支：slotDir 內探到 `.cursor-plugin/plugin.json`
  /// 就走 agent-plugins.org 流程（HTML 入口偵測短路——plugin repo 沒 index.html，
  /// 原本 L149-152 會硬失敗）。
  ///
  /// 流程：①manifest 解析（失敗誠實回錯）②紅隊掃描照跑（entryRel=null）
  /// ③skills 複製進庫＋catalog reload（一個 plugin 一張卡，不逐檔建卡）
  /// ④SlotRegistry 建一張卡＋零權限啟用。冪等：skills 檔已存在跳過、
  /// 卡已存在（同 sourceRepo）補 version/label 後直接啟用，不重複建卡。
  ///
  /// [runPluginIntake=false] 純偵測＋紅隊掃描（wizard 預掃描用）——
  /// 絕不建卡不複製：預掃臨時夾的紀錄要是真卡，放棄就留幽靈卡。
  ///
  /// [registry]/[catalog]/[skillsDir] 依賴注入點：production 用全域單例
  /// （SlotRegistry.instance / SkillCatalog.instance / SkillStore 的目錄），
  /// 測試可注入隔離實例。
  static Future<SlotInstallResult> _installPluginBranch(
    Directory slotDir, {
    String repoUrl = '',
    bool runPluginIntake = true,
    SlotRegistry? registry,
    SkillCatalog? catalog,
    Directory? skillsDir,
  }) async {
    final manifest =
        await PluginManifest.parsePluginRoot(slotDir.path);
    if (manifest == null) {
      return const SlotInstallResult.fail(
          'plugin.json 存在但解析失敗（缺 name/version 或壞 JSON）——寧拒不誤裝');
    }

    // 紅隊掃描照跑——plugin 沒有 HTML 入口，entryRel 傳 null
    final redTeam = await SlotRedTeamScanner.scan(slotDir);

    if (!runPluginIntake) {
      return SlotInstallResult(
          ok: true,
          version: manifest.version,
          redTeam: redTeam,
          pluginName: manifest.displayName ?? manifest.name,
          pluginSkillsCount: await _countSkillMd(manifest));
    }


    final reg = registry ?? SlotRegistry.instance;
    final cat = catalog ?? SkillCatalog.instance;
    final skillsRoot = skillsDir ??
        (SkillStore.instance.skillsDirPath != null
            ? Directory(SkillStore.instance.skillsDirPath!)
            : null);

    // ③ skills 進庫
    var imported = 0;
    if (skillsRoot != null) {
      final svc = PluginSlotService(catalog: cat, skillsDir: skillsRoot);
      final report = await svc.importSkills(manifest);
      imported = report?.imported ?? 0;
    } else {
      debugPrint('[SlotInstaller] SkillStore 未初始化——skills 不入庫（卡照建）');
    }

    // ④ SlotRegistry 一張卡（冪等：skill://<pluginName> 對位）
    await reg.ensureLoaded();
    final repo = 'skill://${manifest.name}';
    final existing = reg.all.where((s) => s.sourceRepo == repo).toList();
    SlotRecord record;
    if (existing.isNotEmpty) {
      record = existing.first;
      await reg.update(record.copyWith(
        userLabel: manifest.label,
        version: manifest.version,
        origin: PluginSlotService.origin,
      ));
    } else {
      final category = PluginSlotService.mapCategory(manifest.category) ??
          SlotRegistry.defaultCategory;
      record = await reg.addFromRepo(
        repo,
        label: manifest.label,
        category: category,
      );
      await reg.update(reg.getById(record.id)!.copyWith(
        version: manifest.version,
        origin: PluginSlotService.origin,
      ));
    }
    // 知識型 plugin 零權限直接啟用（不啟用會被 disabledSkillNames 排除）
    await reg.enableWithPermissions(record.id, const []);

    debugPrint('[SlotInstaller] plugin 分支：${manifest.name} '
        'v${manifest.version}（skills 入庫 $imported）');

    return SlotInstallResult(
      ok: true,
      version: manifest.version,
      fileCount: imported,
      redTeam: redTeam,
    );
  }

  /// [A線] plugin 分支結果包裝——回 SlotInstallResult，version 帶 manifest 版本
  static Future<SlotInstallResult> pluginBranchProbe(Directory slotDir) =>
      _installPluginBranch(slotDir, runPluginIntake: false);

  /// [runPluginIntake=false] 純偵測＋紅隊掃描（wizard 預掃描用）——
  /// 絕不建卡不複製：預掃臨時夾的紀錄要是真卡，放棄就留幽靈卡。
  ///
  /// 回傳：
  /// - plugin.json 存在且解析成功 → ok=true（version=manifest 版本）
  /// - plugin.json 存在但解析失敗 → fail（寧拒不誤裝）
  /// - 沒有 plugin.json → null（呼叫方續走 HTML 流程）
  static Future<SlotInstallResult?> pluginBranch({
    required Directory slotDir,
    bool runPluginIntake = true,
    String repoUrl = '',
    String? subPath,
    SlotRegistry? registry,
    SkillCatalog? catalog,
    Directory? skillsDir,
  }) async {
    // [A線 2026-10-22 通用機制] 偵測順序：
    // ① URL 指名子路徑（/tree/main/pstack → slotDir/pstack）優先
    // ② 根目錄 → 遞迴深度搜尋（限深 4），多 plugin repo 取第一個（v1 行為）。
    if (subPath != null && subPath.isNotEmpty) {
      final named = Directory('${slotDir.path}/$subPath');
      if (await File('${named.path}/.cursor-plugin/plugin.json').exists()) {
        return _installPluginBranch(named,
            repoUrl: repoUrl,
            runPluginIntake: runPluginIntake,
            registry: registry,
            catalog: catalog,
            skillsDir: skillsDir);
      }
      debugPrint('[SlotInstaller] 指名子路徑 $subPath 無 plugin.json——退回深度搜尋');
    }
    final pluginRoot = await _findPluginRoot(slotDir);
    if (pluginRoot == null) return null;
    return _installPluginBranch(
      pluginRoot,
      repoUrl: repoUrl,
      runPluginIntake: runPluginIntake,
      registry: registry,
      catalog: catalog,
      skillsDir: skillsDir,
    );
  }

  /// [A線 1022] manifest.skills 目錄 .md 計數（wizard 識別顯示用）
  static Future<int> _countSkillMd(PluginManifest manifest) async {
    final p = manifest.skillsDirPath;
    if (p == null) return 0;
    final dir = Directory(p);
    if (!await dir.exists()) return 0;
    var n = 0;
    try {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File && e.path.toLowerCase().endsWith('.md')) n++;
      }
    } catch (_) {}
    return n;
  }

  /// 深度搜尋 plugin.json：遞迴找 `.cursor-plugin/plugin.json`（限深 4 層，
  /// 且不進隱藏目錄/.git——通用機制，任何 nesting 的 monorepo 都吃）。
  /// [A線] monorepo（如 cursor/plugins）的 plugin 住在 `<plugin>/.cursor-plugin/`。
  static Future<Directory?> _findPluginRoot(Directory dir, {int depth = 0}) async {
    if (depth > 4) return null;
    try {
      // 先測當前層
      if (await File('${dir.path}/.cursor-plugin/plugin.json').exists()) {
        return dir;
      }
      for (final e in dir.listSync(followLinks: false)) {
        if (e is! Directory) continue;
        final name = e.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.') || name == 'node_modules') continue;
        final found = await _findPluginRoot(e, depth: depth + 1);
        if (found != null) return found;
      }
    } catch (_) {}
    return null;
  }

  /// 安裝 GitHub HTML 工具到插槽資料夾。
  ///
  /// [repoUrl] 形如 https://github.com/owner/repo
  /// [slotDir] 插槽專屬資料夾（已由 SlotRegistry 建立）
  /// [runPluginIntake] [A線] plugin 分支短路命中時是否真的跑 intake
  /// （建卡＋skills 入庫）。false＝純偵測（wizard 預掃描）。
  /// [registry]/[catalog]/[skillsDir] plugin 分支依賴注入點（測試用）。
  Future<SlotInstallResult> install({
    required String repoUrl,
    required Directory slotDir,
    bool runPluginIntake = true,
    SlotRegistry? pluginRegistry,
    SkillCatalog? pluginCatalog,
    Directory? pluginSkillsDir,
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

    // [A線 2026-10-22] plugin 分支短路：解壓落地後、HTML 入口偵測前探
    // `.cursor-plugin/plugin.json`——存在走 agent-plugins.org 流程
    // （plugin repo 沒 index.html，不短路會在下面 HTML 入口偵測硬失敗）。
    // [A線 1022 通用機制] 統一走 pluginBranch()——含 monorepo 子目錄深度搜尋。
    final pluginResult = await pluginBranch(
      slotDir: slotDir,
      runPluginIntake: runPluginIntake,
      repoUrl: repoUrl,
      subPath: _parseSubpath(repoUrl),
      registry: pluginRegistry,
      catalog: pluginCatalog,
      skillsDir: pluginSkillsDir,
    );
    if (pluginResult != null) return pluginResult;

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
  /// [A線 1022 通用機制] 解析 GitHub URL 子路徑——
  /// `github.com/o/r/tree/main/pstack` → 'pstack'（指名安裝 monorepo 中的特定 plugin）。
  /// 無子路徑回 null。也吃 /blob/、/subdir/ 形式。
  static String? _parseSubpath(String url) {
    final m = RegExp(
      r'github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(?:tree|blob)/[^/]+/(.+)',
    ).firstMatch(url.trim());
    if (m == null) return null;
    final sub = m.group(1)!.replaceAll(RegExp(r'/+$'), '');
    return sub.isEmpty ? null : sub;
  }

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
  ///
  /// [runPluginIntake] [A線 2026-10-22] plugin 分支短路命中時是否真的跑
  /// intake（建卡＋skills 入庫）。預設開（測試直接驗全流程）；
  /// 純偵測場景傳 false。 [registry]/[catalog]/[skillsDir] 依賴注入點。
  @visibleForTesting
  Future<SlotInstallResult> installFromBytes(
      Uint8List tarGzBytes, Directory slotDir,
      {bool runPluginIntake = true,
      String? repoUrl,
      SlotRegistry? pluginRegistry,
      SkillCatalog? pluginCatalog,
      Directory? pluginSkillsDir}) async {
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
    // [A線 2026-10-22] plugin 分支短路（與 install() 同規格）：
    // 測試路徑 runPluginIntake 預設開——合成 plugin tarball 直接到 intake。
    // [A線 1022 通用機制] 統一走 pluginBranch()——含 monorepo 子目錄深度搜尋。
    final pluginResult = await pluginBranch(
      slotDir: slotDir,
      runPluginIntake: runPluginIntake,
      subPath: repoUrl != null ? _parseSubpath(repoUrl) : null,
      registry: pluginRegistry,
      catalog: pluginCatalog,
      skillsDir: pluginSkillsDir,
    );
    if (pluginResult != null) return pluginResult;
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
