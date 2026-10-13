// lib/services/theme_pack_service.dart
//
// [教練 Agent 2026-08-04] ThemePackService MVP
//
// 功能（對應 docs/BRIDGE_TYPOGRAPHY_DESIGN_PRINCIPLES.md §5.2）：
//   - importFromZip: 從 ZIP bytes 解析主題包
//   - exportToZip: 匯出主題包為 ZIP
//   - install: 存到 ~/.bridge/themes/{packId}/ + 註冊清單
//   - uninstall: 移除
//   - listInstalled: 列出所有已安裝
//   - loadManifest: 從磁碟讀回 manifest.json
//
// ZIP 結構：
//   manifest.json
//   fonts/{Inter-Regular.ttf, ...}  ← 可選
//   preview.png                       ← 可選

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/theme_pack.dart';

class ThemePackService {
  /// 內建主題包 ID（永遠不可卸載）
  static const builtinDarkId = '__builtin_dark__';
  static const builtinLightId = '__builtin_light__';

  static const _installedPrefsKey = 'bridge.installed_theme_packs.v1';
  static const _activePrefsKey = 'bridge.active_theme_pack.v1';

  /// 從 ZIP bytes 解析主題包（不解壓到磁碟）
  Future<ThemePack> importFromZip(List<int> zipBytes) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    // 找 manifest.json
    ArchiveFile? manifestFile;
    final fontFiles = <ArchiveFile>[];
    ArchiveFile? previewFile;

    for (final file in archive) {
      if (!file.isFile) continue;
      final name = file.name;
      if (name == 'manifest.json') {
        manifestFile = file;
      } else if (name.startsWith('fonts/')) {
        fontFiles.add(file);
      } else if (name == 'preview.png') {
        previewFile = file;
      }
    }

    if (manifestFile == null) {
      throw const FormatException('ZIP 內找不到 manifest.json');
    }

    // 解析 manifest.json
    final manifestJson = jsonDecode(utf8.decode(manifestFile.content as List<int>))
        as Map<String, dynamic>;
    final pack = ThemePack.fromManifestJson(manifestJson);

    // 驗證設計鐵則
    final violations = pack.validateDesignRules();
    if (violations.isNotEmpty) {
      throw FormatException(
        'ThemePack 違反設計鐵則：\n${violations.join('\n')}',
      );
    }

    // 驗證字型檔案存在（如有宣告）
    if (pack.fontFileBase != null) {
      final baseName = pack.fontFileBase!.split('/').last;
      final found = fontFiles.any((f) => f.name.endsWith(baseName));
      if (!found) {
        throw FormatException(
          'manifest 宣告字型 ${pack.fontFileBase}，但 ZIP 內找不到對應檔案',
        );
      }
    }
    if (pack.fontFileMono != null) {
      final monoName = pack.fontFileMono!.split('/').last;
      final found = fontFiles.any((f) => f.name.endsWith(monoName));
      if (!found) {
        throw FormatException(
          'manifest 宣告字型 ${pack.fontFileMono}，但 ZIP 內找不到對應檔案',
        );
      }
    }

    debugPrint('[ThemePack] importFromZip 成功: ${pack.id} (${pack.name})');
    return pack;
  }

  /// 匯出主題包為 ZIP bytes
  Future<List<int>> exportToZip(
    ThemePack pack, {
    List<int>? fontBaseBytes,
    List<int>? fontMonoBytes,
    List<int>? previewPngBytes,
  }) async {
    final archive = Archive();

    // manifest.json
    final manifestBytes = utf8.encode(pack.toManifestJsonString());
    archive.addFile(ArchiveFile.bytes('manifest.json', manifestBytes));

    // 字型
    if (fontBaseBytes != null && pack.fontFileBase != null) {
      archive.addFile(ArchiveFile.bytes(pack.fontFileBase!, fontBaseBytes));
    }
    if (fontMonoBytes != null && pack.fontFileMono != null) {
      archive.addFile(ArchiveFile.bytes(pack.fontFileMono!, fontMonoBytes));
    }

    // preview
    if (previewPngBytes != null) {
      archive.addFile(ArchiveFile.bytes('preview.png', previewPngBytes));
    }

    final zipBytes = ZipEncoder().encode(archive)!;
    debugPrint('[ThemePack] exportToZip: ${pack.id} → ${zipBytes.length} bytes');
    return zipBytes;
  }

  /// 安裝主題包：解壓到 ~/.bridge/themes/{packId}/ + 註冊清單
  Future<void> install(ThemePack pack) async {
    if (pack.id == builtinDarkId || pack.id == builtinLightId) {
      throw ArgumentError('內建主題不可重新安裝');
    }

    final themesDir = await _getThemesDirectory();
    final packDir = Directory('${themesDir.path}/${pack.id}');
    if (packDir.existsSync()) {
      // 已存在：先清空再覆蓋
      packDir.deleteSync(recursive: true);
    }
    packDir.createSync(recursive: true);

    // 寫 manifest.json
    final manifestFile = File('${packDir.path}/manifest.json');
    await manifestFile.writeAsString(pack.toManifestJsonString());

    // 註冊到 SharedPreferences 清單
    final prefs = await SharedPreferences.getInstance();
    final installed = prefs.getStringList(_installedPrefsKey) ?? [];
    if (!installed.contains(pack.id)) {
      installed.add(pack.id);
      await prefs.setStringList(_installedPrefsKey, installed);
    }

    debugPrint('[ThemePack] install: ${pack.id} → ${packDir.path}');
  }

  /// 卸載主題包
  Future<void> uninstall(String packId) async {
    if (packId == builtinDarkId || packId == builtinLightId) {
      throw ArgumentError('內建主題不可卸載');
    }

    final themesDir = await _getThemesDirectory();
    final packDir = Directory('${themesDir.path}/$packId');
    if (packDir.existsSync()) {
      packDir.deleteSync(recursive: true);
    }

    final prefs = await SharedPreferences.getInstance();
    final installed = prefs.getStringList(_installedPrefsKey) ?? [];
    installed.remove(packId);
    await prefs.setStringList(_installedPrefsKey, installed);

    // 如果當前 active 是被卸載的，切回 dark
    final activeId = prefs.getString(_activePrefsKey);
    if (activeId == packId) {
      await prefs.setString(_activePrefsKey, builtinDarkId);
    }

    debugPrint('[ThemePack] uninstall: $packId');
  }

  /// 列出所有已安裝主題（內建 + 官方 + 第三方）
  Future<List<ThemePack>> listInstalled() async {
    final packs = <ThemePack>[];

    // 內建 dark
    packs.add(_builtinDarkPack());
    // 內建 light
    packs.add(_builtinLightPack());

    // 第三方
    final prefs = await SharedPreferences.getInstance();
    final installed = prefs.getStringList(_installedPrefsKey) ?? [];
    final themesDir = await _getThemesDirectory();

    for (final packId in installed) {
      final manifestFile = File('${themesDir.path}/$packId/manifest.json');
      if (!manifestFile.existsSync()) continue;
      try {
        final json = jsonDecode(await manifestFile.readAsString())
            as Map<String, dynamic>;
        packs.add(ThemePack.fromManifestJson(json));
      } catch (e) {
        debugPrint('[ThemePack] 載入 $packId 失敗: $e');
      }
    }

    return packs;
  }

  /// 設定當前啟用主題（存 ID，啟動時由 ThemeProvider 讀回）
  Future<void> setActive(String packId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activePrefsKey, packId);
  }

  /// 取得當前啟用主題 ID（預設 dark）
  Future<String> getActiveId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activePrefsKey) ?? builtinDarkId;
  }

  /// 從 FilePicker 選 ZIP 並解析（UI 層 helper）
  Future<ThemePack?> pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      throw const FormatException('讀不到 ZIP 內容');
    }
    return importFromZip(bytes);
  }

  /// ~/.bridge/themes/ 路徑
  Future<Directory> _getThemesDirectory() async {
    final appSupport = await getApplicationSupportDirectory();
    final bridgeDir = Directory('${appSupport.path}/themes');
    if (!bridgeDir.existsSync()) {
      bridgeDir.createSync(recursive: true);
    }
    return bridgeDir;
  }

  ThemePack _builtinDarkPack() {
    return ThemePack(
      id: builtinDarkId,
      name: '橋樑暗色（內建）',
      author: 'Bridge Team',
      license: 'MIT',
      description: '預設暗色主題，xAI 科技氛圍',
      minBridgeVersion: '1.0',
      targetModes: const ['dark'],
      colors: _darkColors(),
    );
  }

  /// 測試用：取得內建 dark ThemePack
  @visibleForTesting
  ThemePack builtinDarkPackForTest() => _builtinDarkPack();

  ThemePack _builtinLightPack() {
    return ThemePack(
      id: builtinLightId,
      name: '橋樑淺色（內建）',
      author: 'Bridge Team',
      license: 'MIT',
      description: '淺色主題，純白卡片、淺灰畫布底',
      minBridgeVersion: '1.0',
      targetModes: const ['light'],
      colors: _lightColors(),
    );
  }

  Map<String, Color> _darkColors() => {
        'canvas': const Color(0xFF07080A),
        'surface': const Color(0xFF101111),
        'surfaceElevated': const Color(0xFF1B1C1E),
        'surfaceHover': const Color(0xFF252829),
        'textPrimary': const Color(0xFFF9F9F9),
        'textSecondary': const Color(0xFFCECECE),
        'textTertiary': const Color(0xFF9C9C9D),
        'textMuted': const Color(0xFF6A6B6C),
        'textQuaternary': const Color(0xFF434345),
        'accentRed': const Color(0xFFFF6363),
        'accentBlue': const Color(0xFF55B3FF),
        'accentGreen': const Color(0xFF5FC992),
        'accentYellow': const Color(0xFFFFBC33),
        'accentPurple': const Color(0xFF533AFD),
        'accentNavy': const Color(0xFF061B31),
        'accentMagenta': const Color(0xFFF96BEE),
        'accentRuby': const Color(0xFFEA2261),
        'accentMiro': const Color(0xFF5B76FE),
        'borderSubtle': const Color(0x0FFFFFFF),
        'borderDefault': const Color(0x1AFFFFFF),
        'borderStrong': const Color(0x33FFFFFF),
        'surfaceGlass': const Color(0x0DFFFFFF),
        'surfaceGlassHover': const Color(0x14FFFFFF),
        'tagSuccessBg': const Color(0xFF0E1B12),
        'tagSuccessFg': const Color(0xFFB8E8CC),
        'tagErrorBg': const Color(0xFF1B0E0E),
        'tagErrorFg': const Color(0xFFFFADAD),
        'tagInfoBg': const Color(0xFF0E151B),
        'tagInfoFg': const Color(0xFFB3DCFF),
        'tagBrainBg': const Color(0xFF0E0A1B),
        'tagBrainFg': const Color(0xFFB9B9F9),
        'tagWarnBg': const Color(0xFF1B160E),
        'tagWarnFg': const Color(0xFFFFD580),
      };

  Map<String, Color> _lightColors() => {
        'canvas': const Color(0xFFE8E9ED),
        'surface': const Color(0xFFFFFFFF),
        'surfaceElevated': const Color(0xFFF4F5F6),
        'surfaceHover': const Color(0xFFECEDEE),
        'textPrimary': const Color(0xFF1A1B1E),
        'textSecondary': const Color(0xFF3A3B3D),
        'textTertiary': const Color(0xFF525355),
        'textMuted': const Color(0xFF6A6B6D),
        'textQuaternary': const Color(0xFF8A8B8D),
        'accentRed': const Color(0xFFE53E3E),
        'accentBlue': const Color(0xFF0066CC),
        'accentGreen': const Color(0xFF2E9D5F),
        'accentYellow': const Color(0xFFD4A017),
        'accentPurple': const Color(0xFF4B2FBF),
        'accentNavy': const Color(0xFF1B3A5C),
        'accentMagenta': const Color(0xFFD43AB5),
        'accentRuby': const Color(0xFFC4154E),
        'accentMiro': const Color(0xFF4051CC),
        'borderSubtle': const Color(0x0F000000),
        'borderDefault': const Color(0x1A000000),
        'borderStrong': const Color(0x33000000),
        'surfaceGlass': const Color(0x0D000000),
        'surfaceGlassHover': const Color(0x14000000),
        'tagSuccessBg': const Color(0xFFE8F5ED),
        'tagSuccessFg': const Color(0xFF1B6B3F),
        'tagErrorBg': const Color(0xFFFDEAEA),
        'tagErrorFg': const Color(0xFFB91C1C),
        'tagInfoBg': const Color(0xFFE8F2FC),
        'tagInfoFg': const Color(0xFF1B5A9C),
        'tagBrainBg': const Color(0xFFEDE8F7),
        'tagBrainFg': const Color(0xFF4B2FBF),
        'tagWarnBg': const Color(0xFFFDF3E0),
        'tagWarnFg': const Color(0xFF9C6B0F),
      };
}