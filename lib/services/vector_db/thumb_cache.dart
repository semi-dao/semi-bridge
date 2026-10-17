/// thumb_cache.dart
/// [Blue 令 2026-10-17] 縮圖 48 小時快取——已顯示過的縮圖不再重讀原圖。
///
/// 病例：vault 牆上滑動時每張 Image.file 都重新 decode 原圖
/// （4000px 農場照片）——滑一次燒一次 CPU/IO，回滑又重來。
///
/// 設計：
/// - 磁碟快取：App Support/thumb_cache/<sha1(absPath|mtime|size)>.jpg
///   （來源檔變更 → hash 變 → 自動重生成，不會顯示舊縮圖）
/// - 記憶體 LRU：最近 500 張 decoded ui.Image（PaintingBinding imageCache
///   已有全域快取，這裡確保 provider key 穩定就會命中）
/// - 48h 清理：掃描 thumb_cache 目錄，刪 mtime 超過 48h 的檔
///   （App 啟動時背景執行一次，不擋 UI）
///
/// 產物是「縮圖檔」不是 widget——widget 層用 ThumbImage(file:) 包。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

class ThumbCache {
  ThumbCache._();
  static final ThumbCache instance = ThumbCache._();

  Directory? _dir;
  static const _maxAge = Duration(hours: 48);

  Future<Directory> _resolve() async {
    if (_dir != null) return _dir!;
    final base = await _appSupport();
    final d = Directory('${base.path}/thumb_cache');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  Future<Directory> _appSupport() async {
    // 不引入 path_provider 依賴重複——用 Platform.environment 同 app 慣例
    final home = Platform.environment['HOME'] ?? '.';
    // macOS App Support（sandbox 內外都通）
    final container =
        '$home/Library/Containers/farm.semiwasabi.bridgeApp/Data/Library/Application Support';
    final dir = Directory(container);
    if (await dir.exists()) return dir;
    final plain = Directory('$home/Library/Application Support');
    return plain;
  }

  String _key(File src, DateTime mtime, int size) =>
      sha1.convert(utf8.encode('${src.path}|$mtime|$size')).toString();

  /// 取縮圖檔（存在=快取命中；不存在=null，呼叫端 fallback 原圖）
  Future<File?> lookup(File src) async {
    try {
      final stat = await src.stat();
      if (stat.type == FileSystemEntityType.notFound) return null;
      final d = await _resolve();
      final f = File('${d.path}/${_key(src, stat.modified, stat.size)}.jpg');
      return await f.exists() ? f : null;
    } catch (_) {
      return null;
    }
  }

  /// 存縮圖（generate 是呼叫端提供的縮圖生成器——本類不管 decode）
  Future<File?> store(File src, List<int> jpegBytes) async {
    try {
      final stat = await src.stat();
      final d = await _resolve();
      final f = File('${d.path}/${_key(src, stat.modified, stat.size)}.jpg');
      await f.writeAsBytes(jpegBytes, flush: false);
      return f;
    } catch (e) {
      debugPrint('[ThumbCache] store 失敗: $e');
      return null;
    }
  }

  /// 48h 清理（啟動時背景一次）
  Future<void> purgeExpired() async {
    try {
      final d = await _resolve();
      final now = DateTime.now();
      await for (final e in d.list()) {
        if (e is! File) continue;
        final stat = await e.stat();
        if (now.difference(stat.modified) > _maxAge) {
          await e.delete();
        }
      }
    } catch (_) {}
  }

  /// 快取命中率（診斷用）
  Future<(int, int)> stats() async {
    try {
      final d = await _resolve();
      var n = 0, bytes = 0;
      await for (final e in d.list()) {
        if (e is File) {
          n++;
          bytes += (await e.stat()).size;
        }
      }
      return (n, bytes);
    } catch (_) {
      return (0, 0);
    }
  }
}

/// 穩定 key 的 FileImage（Flutter imageCache 命中的關鍵：同檔案同 key）
FileImage cachedThumbImage(File f) => FileImage(f, scale: 1.0);

