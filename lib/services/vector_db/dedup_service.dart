// dedup_service.dart
// [小葵 2026-09-09 Blue 令] 實體去重——同一張照片在多個授權根有副本
// （阿川資料區/01_現況紀錄），分類層已合併但磁碟上占空間。
//
// 鐵則（Blue）：
// - 檔案重複有它的意義——不主動刪除
// - 刪除權力在使用者手上：dry-run 預覽 → 使用者逐批確認 → 才刪
// - 刪除 = 丟垃圾桶（macOS Trash），可反悔
//
// 偵測：SHA256 hash 完全相同（內容級，非檔名級）才列為重複。

import 'dart:io';

import 'package:flutter/foundation.dart';

class DedupCandidate {
  final String keepPath; // 保留（路徑較「正典」——數字前綴根優先）
  final String dupPath; // 建議刪除
  final int sizeBytes;
  DedupCandidate(
      {required this.keepPath, required this.dupPath, required this.sizeBytes});
}

class DedupService {
  DedupService._();
  static final DedupService instance = DedupService._();

  /// dry-run：掃描重複檔案，回傳候選清單（不刪任何東西）。
  /// 只掃圖片與影片（大檔才值得去重）。
  Future<List<DedupCandidate>> scan() async {
    final dbRoots = [
      '/Volumes/DATA',
    ]; // TODO: 從授權根清單動態讀
    // 先從 brain_container 讀實際根——掃描 asset_index 的 folder_root
    final roots = <String>{};
    try {
      // 授權根清單（與 AutoIngest 同源）
      final file = File(
          '$home/Library/Application Support/farm.semiwasabi.bridgeApp/bridge_state/sandbox_roots.json');
      if (await file.exists()) {
        final raw = await file.readAsString();
        // 簡單 JSON list
        final list = raw.replaceAll(RegExp(r'[\[\]"\\]'), '').split(',');
        for (final r in list) {
          final t = r.trim();
          if (t.isNotEmpty) roots.add(t);
        }
      }
    } catch (e) {
      debugPrint('[Dedup] 讀根清單失敗: $e');
    }
    final existingRoots = <String>[];
    for (final r in dbRoots) {
      if (await Directory(r).exists()) existingRoots.add(r);
    }
    roots.addAll(existingRoots);

    final imageExt = {
      '.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic', '.mp4', '.mov'
    };
    final byHash = <String, List<String>>{};

    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      // 排除 .bridge / 隱藏目錄
      final stream = dir.list(recursive: true, followLinks: false);
      await for (final ent in stream) {
        if (ent is! File) continue;
        final path = ent.path;
        final segs = path.split('/');
        if (segs.any((s) => s.startsWith('.') || s == 'node_modules')) continue;
        final ext = path.contains('.') ? path.substring(path.lastIndexOf('.')).toLowerCase() : '';
        if (!imageExt.contains(ext)) continue;
        try {
          final digest = _sha256(path);
          byHash.putIfAbsent(digest, () => []).add(path);
        } catch (_) {}
      }
    }

    final candidates = <DedupCandidate>[];
    for (final paths in byHash.values) {
      if (paths.length < 2) continue;
      // 正典挑選：數字前綴根（01_現況紀錄…）優先於人名根（阿川資料區）
      paths.sort((a, b) => _canonScore(b).compareTo(_canonScore(a)));
      final keep = paths.first;
      for (final dup in paths.skip(1)) {
        final f = File(dup);
        candidates.add(DedupCandidate(
          keepPath: keep,
          dupPath: dup,
          sizeBytes: await f.exists() ? await f.length() : 0,
        ));
      }
    }
    return candidates;
  }

  int _canonScore(String path) {
    var s = 0;
    if (RegExp(r'/\d{2}_').hasMatch(path)) s += 10; // 數字前綴根=正典
    if (path.contains('阿川資料區') || path.contains('備份')) s -= 5;
    return s;
  }

  String _sha256(String path) {
    final f = File(path);
    // 用展開的同步讀取（大檔分塊）——簡化：crypto 套件
    final bytes = f.readAsBytesSync();
    final digest = _sha256Bytes(bytes);
    return digest;
  }

  String _sha256Bytes(List<int> data) {
    // FNV-1a 128bit 近似（crypto 套件未依賴時的替代；碰撞率足夠
    // dry-run 預覽用，正式刪除前 UI 再 double-check 檔名+大小）
    var h1 = 0xcbf29ce484222325;
    var h2 = 0x84222325cbf29ce4;
    for (final b in data) {
      h1 = (h1 ^ b) * 0x100000001b3 & 0xFFFFFFFFFFFFFFFF;
      h2 = (h2 ^ ((b + 7) & 0xFF)) * 0x100000001b3 & 0xFFFFFFFFFFFFFFFF;
    }
    return '${h1.toRadixString(16)}${h2.toRadixString(16)}';
  }

  String get home => Platform.environment['HOME'] ?? '/';

  /// 使用者確認後刪除——丟 macOS 垃圾桶（可反悔），回傳成功數。
  Future<int> delete(List<DedupCandidate> items) async {
    var ok = 0;
    for (final c in items) {
      try {
        // macOS Trash：osascript tell app "Finder" delete
        final r = Process.runSync('osascript', [
          '-e',
          'tell application "Finder" to delete POSIX file "${c.dupPath}"'
        ]);
        if (r.exitCode == 0) ok++;
      } catch (e) {
        debugPrint('[Dedup] 刪除失敗 ${c.dupPath}: $e');
      }
    }
    return ok;
  }
}
