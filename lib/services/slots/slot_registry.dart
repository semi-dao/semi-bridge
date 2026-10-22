// 插槽註冊表 — 無限插槽系統 C2 資料模型（2026-10-06）
//
// spec：docs/specs/2026-10-04-infinite-slot-system.md「資料與信任」段
// 資料位置：{BRIDGE_APP_HOME 覆寫的 app support}/slots/index.json
//   + 每插槽資料夾 slots/<slot_id>/
//
// C2 範圍：只有資料模型＋CRUD＋持久化＋變更通知。執行引擎是 C3。
//
// 通知模式：仿 CompanionStore（ChangeNotifier singleton），
// UI（首頁插槽卡／插槽管理頁）AnimatedBuilder/ListenableBuilder 監聽即時刷新。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'builtin_skills_intake.dart' show BuiltinSkillsIntake;
import '../plugins/plugin_slot_service.dart';
import '../skills/skill_catalog.dart';
import '../skills/skill_store.dart';
import 'package:uuid/uuid.dart';

/// 插槽記錄 — 一個住進橋樑的開源程式
@immutable
class SlotRecord {
  /// uuid
  final String id;

  /// 使用者取的名字（v1 新增時暫用 repo 名，之後可 rename）
  final String userLabel;

  /// 來源 repo（GitHub URL）
  final String sourceRepo;

  /// 分類（字串、動態——由 grill-me 結果長出來，或使用者手動指定）
  final String category;

  /// 執行狀態：running / disabled（pending = 已登記未安裝完成，C3 前唯一狀態）
  final String status;

  /// Reggie 認證（registry.semidao.net）；v1 一律 false
  final bool certified;

  /// 權限清單，如 ['network', 'file']；deny-by-default，逐項由使用者授予
  final List<String> permissions;

  /// 記憶體用量（MB）。無執行引擎前為 null（UI 顯示 —）
  final int? memoryMb;

  /// 已安裝版本（C3 前為 null）
  final String? version;

  /// [C3] HTML 入口（相對插槽資料夾，如 index.html）——Tier 1 引擎用
  final String? entryHtmlPath;

  /// [C4] 看門狗斷電原因（null=從未被斷電）
  final String? watchdogReason;

  /// [H1 2026-10-08] 出身標注（履歷不是戶籍）——如 'Hermes'、'GitHub'。
  /// 分類按功能，出身只在小卡上標注。
  final String? origin;

  final DateTime createdAt;

  final DateTime? lastUsedAt;

  const SlotRecord({
    required this.id,
    required this.userLabel,
    required this.sourceRepo,
    required this.category,
    required this.status,
    this.certified = false,
    this.permissions = const [],
    this.memoryMb,
    this.version,
    this.entryHtmlPath,
    this.watchdogReason,
    this.origin,
    required this.createdAt,
    this.lastUsedAt,
  });

  /// 運行中
  bool get isRunning => status == SlotStatus.running;

  /// 已登記、尚未安裝完成（grill-me 流水線還沒走完）
  bool get isPending => status == SlotStatus.pending;

  SlotRecord copyWith({
    String? userLabel,
    String? sourceRepo,
    String? category,
    String? status,
    bool? certified,
    List<String>? permissions,
    Object? memoryMb = _sentinel,
    Object? version = _sentinel,
    Object? entryHtmlPath = _sentinel,
    Object? watchdogReason = _sentinel,
    Object? origin = _sentinel,
    DateTime? lastUsedAt,
  }) {
    return SlotRecord(
      id: id,
      userLabel: userLabel ?? this.userLabel,
      sourceRepo: sourceRepo ?? this.sourceRepo,
      category: category ?? this.category,
      status: status ?? this.status,
      certified: certified ?? this.certified,
      permissions: permissions ?? this.permissions,
      memoryMb: identical(memoryMb, _sentinel) ? this.memoryMb : memoryMb as int?,
      version: identical(version, _sentinel) ? this.version : version as String?,
      entryHtmlPath: identical(entryHtmlPath, _sentinel)
          ? this.entryHtmlPath
          : entryHtmlPath as String?,
      watchdogReason: identical(watchdogReason, _sentinel)
          ? this.watchdogReason
          : watchdogReason as String?,
      origin: identical(origin, _sentinel) ? this.origin : origin as String?,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  static const _sentinel = Object();

  Map<String, dynamic> toJson() => {
        'id': id,
        'userLabel': userLabel,
        'sourceRepo': sourceRepo,
        'category': category,
        'status': status,
        'certified': certified,
        'entryHtmlPath': entryHtmlPath,
        'watchdogReason': watchdogReason,
        if (origin != null) 'origin': origin,
        'permissions': permissions,
        if (memoryMb != null) 'memoryMb': memoryMb,
        if (version != null) 'version': version,
        'createdAt': createdAt.toIso8601String(),
        if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
      };

  factory SlotRecord.fromJson(Map<String, dynamic> json) {
    return SlotRecord(
      id: json['id'] as String,
      userLabel: json['userLabel'] as String? ?? '',
      sourceRepo: json['sourceRepo'] as String? ?? '',
      category: json['category'] as String? ?? SlotRegistry.defaultCategory,
      status: json['status'] as String? ?? SlotStatus.pending,
      certified: json['certified'] as bool? ?? false,
      entryHtmlPath: json['entryHtmlPath'] as String?,
      watchdogReason: json['watchdogReason'] as String?,
      origin: json['origin'] as String?,
      permissions:
          (json['permissions'] as List<dynamic>?)?.cast<String>() ?? const [],
      memoryMb: json['memoryMb'] as int?,
      version: json['version'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.now(),
      lastUsedAt: json['lastUsedAt'] == null
          ? null
          : DateTime.tryParse(json['lastUsedAt'] as String),
    );
  }
}

/// 插槽狀態常數（字串——JSON 持久化友善，避免 enum 舊資料炸裂）
abstract final class SlotStatus {
  static const running = 'running';
  static const disabled = 'disabled';

  /// 已登記未安裝完成（C2 建立的插槽都是這個狀態；C3 引擎接手後轉 running/disabled）
  static const pending = 'pending';
}

/// 從 GitHub URL 萃取 repo 識別（owner/repo）
///
/// 接受 https://github.com/owner/repo(.git)、git@github.com:owner/repo.git 等常見格式。
String extractRepoSlug(String url) {
  var s = url.trim();
  if (s.isEmpty) return '';
  s = s.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'^git@'), '');
  s = s.replaceFirst(':', '/').replaceFirst(RegExp(r'\.git$'), '');
  s = s.replaceFirst(RegExp(r'^github\.com/?'), '');
  final parts = s.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.length >= 2) return '${parts[0]}/${parts[1]}';
  if (parts.isNotEmpty) return parts[0];
  return '';
}

/// 插槽註冊表 — 單例 ChangeNotifier
///
/// 持久化：slots/index.json（全量覆寫，v1 規模夠用）；
/// 每插槽資料夾 `slots/<id>/` 的建立/刪除由 add/uninstall 管理。
class SlotRegistry extends ChangeNotifier {
  SlotRegistry._() : _rootOverride = null;
  static final SlotRegistry instance = SlotRegistry._();

  /// 測試工廠——傳入自訂根目錄，不碰真實 app support
  @visibleForTesting
  SlotRegistry.test(Directory rootDir) : _rootOverride = rootDir;

  final Directory? _rootOverride;

  /// 預設分類——grill-me 還沒長出更好的分類前都歸這
  static const String defaultCategory = '未分類';

  /// 範例插槽（2026-10-06 Blue 授權小葵挑選的第一支示範）
  static const String sampleRepoUrl =
      'https://github.com/mraza007/mermview';

  static const Uuid _uuid = Uuid();

  List<SlotRecord> _slots = [];
  bool _loaded = false;
  String? _slotsDirPath;

  /// 已載入
  bool get isLoaded => _loaded;

  /// 全部插槽
  List<SlotRecord> get all => List.unmodifiable(_slots);

  /// 有沒有任何插槽
  bool get isEmpty => _slots.isEmpty;

  /// 運行中數量
  int get runningCount =>
      _slots.where((s) => s.status == SlotStatus.running).length;

  /// 已停用數量（含 pending——都算「未在跑」）
  int get disabledCount =>
      _slots.where((s) => s.status != SlotStatus.running).length;

  SlotRecord? getById(String id) {
    for (final s in _slots) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<SlotRecord> listByCategory(String category) =>
      _slots.where((s) => s.category == category).toList();

  /// 所有分類名（依插入序）
  List<String> get categories {
    final seen = <String>[];
    for (final s in _slots) {
      if (!seen.contains(s.category)) seen.add(s.category);
    }
    return seen;
  }

  /// 分類 → 一句話說明（v1 用固定規則；未來由 grill-me 結果萃取）
  String categoryDescription(String category) {
    switch (category) {
      case 'Skill':
        return '跑在沙箱裡的輕量技能';
      case 'CLI 工具':
        return '獨立執行序，吃資源，有看門狗守著';
      case '網頁工具':
        return '純網頁技術，最安全的 Tier 1 形態';
      // [H1 2026-10-08] 功能分類——按用途不按出身
      case '開發技能':
        return '寫 code、debug、跑工程流水線';
      case '內容創作':
        return '畫圖、影音、寫作、設計';
      case '研究調查':
        return '查資料、讀論文、驗證事實';
      case '生活助理':
        return '訊息、行程、日常大小事';
      case defaultCategory:
        return '安裝時自動歸檔，可隨時搬家';
      default:
        return '使用者建立的分類';
    }
  }

  // ═══════════════════════════════════════════════════
  // 路徑
  // ═══════════════════════════════════════════════════

  /// slots/ 根目錄。
  ///
  /// 根路徑：BRIDGE_APP_HOME 環境變數覆寫（測試不污染），
  /// 未覆寫時用 path_provider 的 Application Support（sandbox 對）——
  /// 這裡不 import path_provider（避免測試環境 platform channel 卡死），
  /// 改由呼叫方在 App 啟動時注入（[init] 或 [setRootOverride]）。
  Directory get slotsDir {
    final p = _slotsDirPath;
    if (p != null) return Directory(p);
    final o = _rootOverride;
    if (o != null) return Directory('${o.path}/slots');
    final override = Platform.environment['BRIDGE_APP_HOME'];
    final root = override ?? '';
    final dir = root.isEmpty
        ? Directory('slots') // 未注入也未設環境變數——相對路徑保底（App 啟動一定會 init）
        : Directory('$root/slots');
    return dir;
  }

  File get _indexFile => File('${slotsDir.path}/index.json');

  /// App 啟動時注入真實根路徑（main.dart 呼叫一次）。
  /// 已有注入（或測試 override）時冪等不覆蓋。
  static Future<void> init(Directory appSupportDir) async {
    final r = instance;
    if (r._rootOverride != null || r._slotsDirPath != null) return;
    r._slotsDirPath = '${appSupportDir.path}/slots';
  }

  /// 測試用：直接改根路徑
  @visibleForTesting
  void setRootOverride(Directory dir) {
    // test 建構子走 _rootOverride；此處供單例注入臨時目錄
    _slotsDirPath = '${dir.path}/slots';
  }

  // ═══════════════════════════════════════════════════
  // 載入 / 持久化
  // ═══════════════════════════════════════════════════

  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = _indexFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is List) {
          _slots = decoded
              .whereType<Map<String, dynamic>>()
              .map(SlotRecord.fromJson)
              .toList();
        } else if (decoded is Map<String, dynamic> &&
            decoded['slots'] is List) {
          _slots = (decoded['slots'] as List)
              .whereType<Map<String, dynamic>>()
              .map(SlotRecord.fromJson)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[SlotRegistry] 讀取 index.json 失敗（以空白開機）: $e');
      _slots = [];
    }
    _loaded = true;
    notifyListeners();
  }

  /// 確保已載入（UI 進頁面時呼叫）
  Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  Future<void> _persist() async {
    final dir = slotsDir;
    await dir.create(recursive: true);
    final content = jsonEncode(_slots.map((s) => s.toJson()).toList());
    await _indexFile.writeAsString(content, flush: true);
  }

  // ═══════════════════════════════════════════════════
  // CRUD
  // ═══════════════════════════════════════════════════

  /// 從 GitHub 連結建立插槽（pending 狀態）。
  ///
  /// 名稱暫用 repo 名（grill-me 聊完後可 rename）；
  /// 分類 v1 簡單規則：使用者指定優先，否則預設「未分類」。
  Future<SlotRecord> addFromRepo(
    String repoUrl, {
    String? category,
    String? label,
  }) async {
    await ensureLoaded();
    final slug = extractRepoSlug(repoUrl);
    final name = (label != null && label.isNotEmpty)
        ? label
        : (slug.contains('/') ? slug.split('/').last : (slug.isEmpty ? '新插槽' : slug));
    final record = SlotRecord(
      id: _uuid.v4(),
      userLabel: name,
      sourceRepo: repoUrl.trim(),
      category: (category == null || category.isEmpty)
          ? defaultCategory
          : category,
      status: SlotStatus.pending,
      createdAt: DateTime.now(),
    );
    _slots.add(record);
    // 建插槽專屬資料夾（C3 引擎會把下載的程式放這裡）
    await Directory('${slotsDir.path}/${record.id}').create(recursive: true);
    await _persist();
    notifyListeners();
    return record;
  }

  /// 更新（整筆替換，以 id 對位）
  Future<void> update(SlotRecord record) async {
    await ensureLoaded();
    final i = _slots.indexWhere((s) => s.id == record.id);
    if (i == -1) {
      throw StateError('Slot ${record.id} 不存在');
    }
    _slots[i] = record;
    await _persist();
    notifyListeners();
  }

  /// 改名
  Future<void> rename(String id, String newLabel) async {
    final s = getById(id);
    if (s == null) return;
    await update(s.copyWith(userLabel: newLabel));
  }

  /// 啟用
  Future<void> enable(String id) async {
    final s = getById(id);
    if (s == null) return;
    await update(s.copyWith(
      status: SlotStatus.running,
      lastUsedAt: DateTime.now(),
    ));
  }

  /// [Blue 抓包 2026-10-06] 帶權限賦與的啟用——燈號裁決（綠自動/黃紅人點頭）
  /// 後由此落地。permissions 為 null 時沿用原權限（相容舊呼叫處）。
  Future<void> enableWithPermissions(String id, List<String> permissions) async {
    final s = getById(id);
    if (s == null) return;
    await update(s.copyWith(
      status: SlotStatus.running,
      permissions: permissions,
      lastUsedAt: DateTime.now(),
    ));
  }

  /// 停用
  Future<void> disable(String id) async {
    final s = getById(id);
    if (s == null) return;
    await update(s.copyWith(status: SlotStatus.disabled));
  }

  /// [C4] 看門狗斷電——與 disable 分開記（UI 可顯示「被看門狗暫停」原因）。
  /// status 用 disabled（不新增 enum——序列化相容），原因存 record。
  Future<void> pauseByWatchdog(String id, String reason) async {
    final s = getById(id);
    if (s == null) return;
    await update(s.copyWith(status: SlotStatus.disabled, watchdogReason: reason));
  }

  /// 手動搬家——設定分類
  Future<void> setCategory(String id, String category) async {
    final s = getById(id);
    if (s == null) return;
    await update(s.copyWith(category: category));
  }

  /// 卸載。
  ///
  /// [deleteData] = 使用者在「資料去留」對話框的選擇：
  /// - true  → 刪 `slots/<id>/` 資料夾
  /// - false → 保留資料夾（資料主權：預設不刪）
  /// 兩者都會把 index.json 該筆移除。
  /// 絕不碰 slots/ 目錄以外的任何檔案。
  Future<void> uninstall(String id, {required bool deleteData}) async {
    await ensureLoaded();
    final s = getById(id);
    if (s == null) return;
    final slotDir = Directory('${slotsDir.path}/$id');
    if (deleteData && await slotDir.exists()) {
      try {
        await slotDir.delete(recursive: true);
      } catch (e) {
        debugPrint('[SlotRegistry] 刪除插槽資料夾失敗（繼續移除索引）: $e');
      }
    }
    _slots.removeWhere((x) => x.id == id);
    await _persist();
    notifyListeners();
    // [A線 2026-10-22] plugin 插槽卸載掃除——按 `<pluginName>__` 前綴刪
    // skillsDir 下的 skills＋catalog reload（uninstall 只刪 slots/<id>/，
    // 不掃這裡會留幽靈 skills）。SkillStore 未初始化（測試環境）就靜默跳過。
    if (s.sourceRepo.startsWith('skill://') && s.origin == PluginSlotService.origin) {
      final skillsPath = SkillStore.instance.skillsDirPath;
      if (skillsPath != null) {
        final pluginName = s.sourceRepo.substring('skill://'.length);
        final svc = PluginSlotService(
          catalog: SkillCatalog.instance,
          skillsDir: Directory(skillsPath),
        );
        await svc.removePluginSkills(pluginName);
      }
    }
    // [Blue 提議 2026-10-06] builtin skill 全數卸載 → 立墓碑（不還魂）
    await BuiltinSkillsIntake.instance.onSlotUninstalled(s.sourceRepo);
  }

  /// 測試用：清空狀態
  @visibleForTesting
  void resetForTest() {
    _slots = [];
    _loaded = false;
    _slotsDirPath = null;
    notifyListeners();
  }
}
