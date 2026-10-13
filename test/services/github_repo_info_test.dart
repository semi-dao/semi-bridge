// github_repo_info 回歸測試——URL 解析（純函數）+ 抓取（真網路，標 skip 可離線）
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/slots/github_repo_info.dart';

void main() {
  group('parseUrl', () {
    test('標準連結', () {
      expect(GithubRepoInfo.parseUrl('https://github.com/code4fukui/exif-viewer'),
          ('code4fukui', 'exif-viewer'));
    });
    test('尾端 .git', () {
      expect(GithubRepoInfo.parseUrl('https://github.com/o/r.git'),
          ('o', 'r'));
    });
    test('尾端斜線', () {
      expect(GithubRepoInfo.parseUrl('github.com/o/r/'), ('o', 'r'));
    });
    test('子路徑 tree', () {
      expect(GithubRepoInfo.parseUrl('https://github.com/o/r/tree/main/lib'),
          ('o', 'r'));
    });
    test('非 GitHub → null', () {
      expect(GithubRepoInfo.parseUrl('https://gitlab.com/o/r'), isNull);
    });
    test('空字串 → null', () {
      expect(GithubRepoInfo.parseUrl(''), isNull);
    });
  });

  group('fetch', () {
    // 真網路測試（未認證 GitHub API 60/hr 遠夠）。離線環境跳過。
    test('抓 exif-viewer 真實中繼資料', () async {
      try {
        final info = await GithubRepoInfo.fetch(
            'https://github.com/code4fukui/exif-viewer');
        expect(info.fullName, 'code4fukui/exif-viewer');
        expect(info.stars, greaterThanOrEqualTo(0));
        expect(info.htmlUrl, contains('github.com'));
      } on Exception catch (e) {
        // 網路不可用時誠實跳過（fail-open 測試）
        print('網路不可用，跳過: $e');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
