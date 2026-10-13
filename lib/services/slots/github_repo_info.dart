// GitHub Repo 資訊抓取——插槽引導精靈（練夥伴模式）用
//
// [Blue 決策 2026-10-06] 插槽 onboarding 棄用 LLM 對話主持（不穩定：
// 模型不回覆/不照劇本），改固定步驟精靈。「認識專案」步驟由本服務
// 直接抓 GitHub API 真實資料（description/language/stars/license/topics）
// ——確定性、零幻覺。誠實鐵則：抓不到就說抓不到，不編。
//
// 速率邊界：未認證 api.github.com 60 req/hr——引導精靈一次一個 repo，
// 遠低於上限。C3 執行引擎上線後會做更深的 clone+掃描，這裡只求「第一步
// 讓使用者認識這是什麼」。

import 'package:dio/dio.dart';

class GithubRepoInfo {
  final String fullName; // owner/repo
  final String? description;
  final String? language;
  final int stars;
  final String? license; // SPDX id（如 MIT / Apache-2.0）
  final List<String> topics;
  final String htmlUrl;

  const GithubRepoInfo({
    required this.fullName,
    this.description,
    this.language,
    required this.stars,
    this.license,
    required this.topics,
    required this.htmlUrl,
  });

  /// 從 GitHub URL 解析 owner/repo（支援 https://github.com/o/r、
  /// 尾端 .git、尾端斜線、tree/blob 子路徑）。非 GitHub 連結回 null。
  static (String, String)? parseUrl(String raw) {
    final m = RegExp(
      r'github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)',
    ).firstMatch(raw.trim());
    if (m == null) return null;
    final owner = m.group(1)!;
    var repo = m.group(2)!.replaceAll('.git', '').replaceAll('/', '');
    if (owner.isEmpty || repo.isEmpty) return null;
    return (owner, repo);
  }

  /// 抓取 repo 中繼資料。任何失敗（網路/404/速率）→ throw，呼叫端
  /// 顯示誠實錯誤並允許重試或放棄——絕不回傳假資料。
  static Future<GithubRepoInfo> fetch(String url) async {
    final parsed = parseUrl(url);
    if (parsed == null) {
      throw ArgumentError('不是有效的 GitHub 連結');
    }
    final (owner, repo) = parsed;
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/vnd.github+json'},
    ));
    final res = await dio.get<Map<String, dynamic>>(
      'https://api.github.com/repos/$owner/$repo',
    );
    final data = res.data;
    if (data == null) throw StateError('GitHub 回應空');
    final licenseNode = data['license'];
    return GithubRepoInfo(
      fullName: (data['full_name'] as String?) ?? '$owner/$repo',
      description: data['description'] as String?,
      language: data['language'] as String?,
      stars: (data['stargazers_count'] as num?)?.toInt() ?? 0,
      license: licenseNode is Map ? licenseNode['spdx_id'] as String? : null,
      topics: (data['topics'] as List?)
              ?.map((e) => e.toString())
              .take(8)
              .toList() ??
          const [],
      htmlUrl: (data['html_url'] as String?) ?? url,
    );
  }
}
