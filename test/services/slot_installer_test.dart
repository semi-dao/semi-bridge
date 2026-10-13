// SlotInstaller + SlotRedTeamScanner 回歸測試——離線（自造 tarball）
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/slots/slot_installer.dart';
import 'package:bridge_app/services/slots/slot_redteam_scanner.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('slot_installer_test_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Uint8List buildTarball(Map<String, String> files) {
    final archive = Archive();
    files.forEach((path, content) {
      archive.addFile(ArchiveFile('owner-repo-abc1234/$path', content.length,
          content.codeUnits));
    });
    return Uint8List.fromList(GZipEncoder().encode(TarEncoder().encode(archive))!);
  }

  test('純客戶端工具：index.html 安裝成功，紅隊乾淨', () async {
    final slotDir = Directory('${tmp.path}/slot1');
    final tar = buildTarball({
      'index.html': '<html><body><h1>EXIF Viewer</h1>'
          '<script>console.log("local")</script></body></html>',
      'style.css': 'body{color:#333}',
    });
    final r = await SlotInstaller.instance.installFromBytes(tar, slotDir);
    expect(r.ok, isTrue, reason: r.error ?? '');
    expect(r.entryHtmlPath, 'index.html');
    expect(r.fileCount, 2);
    expect(r.redTeam!.isClean, isTrue);
    expect(r.redTeam!.warnings, isEmpty);
  });

  test('引用外部腳本 → blocker（違反純客戶端預期）', () async {
    final slotDir = Directory('${tmp.path}/slot2');
    final tar = buildTarball({
      'index.html': '<html><script src="https://cdn.example.com/lib.js">'
          '</script></html>',
    });
    final r = await SlotInstaller.instance.installFromBytes(tar, slotDir);
    expect(r.ok, isTrue);
    expect(r.redTeam!.blockers, isNotEmpty);
    expect(r.redTeam!.blockers.first, contains('cdn.example.com'));
  });

  test('路徑逃脫攻擊（../）被擋——不寫出插槽資料夾', () async {
    final slotDir = Directory('${tmp.path}/slot3');
    final tar = buildTarball({
      'index.html': '<html>ok</html>',
      '../evil.txt': 'pwned',
    });
    final r = await SlotInstaller.instance.installFromBytes(tar, slotDir);
    expect(r.ok, isTrue);
    expect(File('${tmp.path}/evil.txt').existsSync(), isFalse,
        reason: '路徑逃脫檔案不得寫出插槽資料夾');
    expect(r.fileCount, 1, reason: '只裝了 index.html，evil.txt 被濾掉');
  });

  test('沒有 HTML 入口 → 誠實紅字', () async {
    final slotDir = Directory('${tmp.path}/slot4');
    final tar = buildTarball({'main.py': 'print(1)'});
    final r = await SlotInstaller.instance.installFromBytes(tar, slotDir);
    expect(r.ok, isFalse);
    expect(r.error, contains('HTML 入口'));
  });

  test('fetch 對外 → warning', () async {
    final slotDir = Directory('${tmp.path}/slot5');
    final tar = buildTarball({
      'index.html': '<html><script>fetch("https://api.example.com/x")'
          '</script></html>',
    });
    final r = await SlotInstaller.instance.installFromBytes(tar, slotDir);
    expect(r.redTeam!.warnings, isNotEmpty);
    expect(r.redTeam!.warnings.first, contains('網路'));
  });

  test('blueprint repo: root index.html references missing /src/main.ts, falls back to dist/index.html', () async {
    // 真正藍圖屋：src/ 沒進 tarball，根入口引用缺失檔 → fallback dist 打包版
    final slotDir2 = Directory('${tmp.path}/slot7');
    final tar2 = buildTarball({
      'index.html': '<script type="module" src="/src/main.ts"></script>',
      'dist/index.html': '<html><body>packed</body></html>',
    });
    final r2 = await SlotInstaller.instance.installFromBytes(tar2, slotDir2);
    expect(r2.ok, isTrue);
    expect(r2.entryHtmlPath, 'dist/index.html',
        reason: '根入口引用缺失檔案時應改用 dist 打包版');
  });
}
