// thumb_image.dart
// [Blue 令 2026-10-17] 牆面縮圖 widget——48h 磁碟快取＋記憶體快取。
// [Blue 抓包 v2 2026-10-17] 滑動仍重讀：病因=每次 initState 都 async 磁碟
// lookup，等待期間 build fallback 顯示「原圖」→ 4000px 整張 decode →
// lag＋快取形同虛設。修：
//  ① 靜態記憶體 Map（path→縮圖檔）——同 session 重访 0 IO、同步 build
//  ② 未解析完成顯示色塊 placeholder（絕不 decode 原圖救場）
//  ③ 縮圖 decode 靠 Flutter 全域 imageCache 同 key 命中（容量在 vault
//     initState 提高）
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/vector_db/thumb_cache.dart';
import '../../theme/bridge_design_system.dart';

class ThumbImage extends StatefulWidget {
  final File file;
  final BoxFit fit;
  final WidgetBuilder? errorBuilder;
  const ThumbImage(
      {super.key, required this.file, this.fit = BoxFit.cover, this.errorBuilder});

  /// 記憶體層：絕對路徑 → 縮圖檔（session 存活期間零磁碟查詢）
  static final Map<String, File> _mem = {};

  /// 正在生成中的路徑（防同圖多卡重複生成）
  static final Set<String> _pending = {};

  @override
  State<ThumbImage> createState() => _ThumbImageState();
}

class _ThumbImageState extends State<ThumbImage> {
  File? _thumb;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ThumbImage old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path) {
      _thumb = null;
      _failed = false;
      _load();
    }
  }

  void _load() {
    final key = widget.file.path;
    final cached = ThumbImage._mem[key];
    if (cached != null) {
      _thumb = cached; // 同步——build 直接命中
      return;
    }
    if (ThumbImage._pending.contains(key)) return; // 別的卡正在生成
    ThumbImage._pending.add(key);
    _resolve(key);
  }

  Future<void> _resolve(String key) async {
    try {
      // ① 磁碟快取
      final disk = await ThumbCache.instance.lookup(widget.file);
      if (disk != null) {
        ThumbImage._mem[key] = disk;
        if (mounted) setState(() => _thumb = disk);
        return;
      }
      // ② 生成縮圖（240px）
      final bytes = await widget.file.readAsBytes();
      final codec =
          await ui.instantiateImageCodec(bytes, targetWidth: 240);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      if (data == null) return;
      final stored =
          await ThumbCache.instance.store(widget.file, data.buffer.asUint8List());
      if (stored != null) {
        ThumbImage._mem[key] = stored;
        if (mounted) setState(() => _thumb = stored);
      }
    } catch (e) {
      debugPrint('[ThumbImage] 縮圖生成失敗: $e');
      if (mounted) setState(() => _failed = true);
    } finally {
      ThumbImage._pending.remove(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 失敗 → errorBuilder；未就緒 → placeholder 色塊（不 decode 原圖）
    if (_failed) {
      return widget.errorBuilder?.call(context) ?? const SizedBox.shrink();
    }
    final f = _thumb;
    if (f == null) {
      return Container(color: BridgeDSColors.of(context).surfaceHover);
    }
    return Image.file(
      f,
      fit: widget.fit,
      cacheWidth: 240,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          widget.errorBuilder?.call(context) ?? const SizedBox.shrink(),
    );
  }
}
