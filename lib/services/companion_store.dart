// 橋樑 App — 電子夥伴本地儲存服務
// 2026-05-31 Phase 1: 資料持久層

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/companion.dart';
import 'companion_pack_service.dart';
import 'companion_runtime_store.dart';
import 'agent_loop/persona_inference_service.dart'; // [教練 Agent 2026-07-22] Phase H

class CompanionStore extends ChangeNotifier {
  static const String _storageKey = 'bridge_companions_v1';
  static const String _activeCompanionKey = 'bridge_active_companion_id';
  static const String _localInstallIdKey = 'bridge_local_install_id';

  static final CompanionStore _instance = CompanionStore._internal();
  factory CompanionStore() => _instance;
  CompanionStore._internal();

  SharedPreferences? _prefs;
  List<Companion> _companions = [];
  String? _activeCompanionId;
  String _localInstallId = '';
  bool _initialized = false;

  /// 初始化（App 啟動時呼叫一次）
  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _localInstallId = _ensureLocalInstallId();
    await _loadFromStorage();
    CompanionRuntimeStore.instance.setActiveCompanion(activeCompanion);
    _initialized = true;
  }

  /// 是否已初始化
  bool get isInitialized => _initialized;

  // === 讀取 ===

  /// 取得所有夥伴（副本）
  List<Companion> get all => List.unmodifiable(_companions);

  /// 取得夥伴數量
  int get count => _companions.length;

  /// 是否有任何夥伴
  bool get hasCompanions => _companions.isNotEmpty;

  /// 根據 ID 取得夥伴
  Companion? getById(String id) {
    try {
      return _companions.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// [指紋章 2026-10-21 ②刀1] companion_id → 指紋章名字。
  /// 'shared'/空/未知 id → 'shared'（寧標 shared 不誤標——誠實鐵則，
  /// 呼應 WS-2「找不到 active 保守回 shared」）。
  String fingerprintName(String companionId) {
    if (companionId.isEmpty || companionId == 'shared') return 'shared';
    final c = getById(companionId);
    return c?.name ?? 'shared';
  }

  /// 取得當前活躍夥伴
  Companion? get activeCompanion {
    if (_activeCompanionId == null) return null;
    return getById(_activeCompanionId!);
  }

  /// 取得活躍夥伴 ID
  String? get activeCompanionId => _activeCompanionId;

  String get localInstallId {
    if (_localInstallId.isEmpty) {
      _localInstallId = _ensureLocalInstallId();
    }
    return _localInstallId;
  }

  /// 根據角色篩選
  List<Companion> byRole(CompanionRole role) =>
      _companions.where((c) => c.role == role).toList();

  /// 根據 MBTI 篩選
  List<Companion> byMBTI(String mbtiCode) =>
      _companions.where((c) => c.mbtiCode == mbtiCode.toUpperCase()).toList();

  // === 寫入 ===

  /// 新增夥伴
  Future<void> add(Companion companion) async {
    // 檢查 ID 是否重複
    if (_companions.any((c) => c.id == companion.id)) {
      throw Exception('Companion with id ${companion.id} already exists');
    }
    _companions.add(companion);
    // 第一個夥伴自動設為活躍
    if (_companions.length == 1) {
      _activeCompanionId = companion.id;
      CompanionRuntimeStore.instance.setActiveCompanion(companion);
    }
    await _saveToStorage();
  }

  /// 更新夥伴
  ///
  /// [教練 Agent 2026-07-22] Phase H — 更新後非阻塞觸發人格卡重新推理。
  Future<void> update(Companion companion) async {
    final index = _companions.indexWhere((c) => c.id == companion.id);
    if (index == -1) {
      throw Exception('Companion with id ${companion.id} not found');
    }
    _companions[index] = companion;
    await _saveToStorage();

    // [教練 Agent 2026-07-22] Phase H — 非阻塞觸發人格卡重新推理
    _triggerPersonaReinference(companion);
  }

  /// 刪除夥伴
  Future<void> delete(String id) async {
    _companions.removeWhere((c) => c.id == id);
    // 如果刪除的是活躍夥伴，重置
    if (_activeCompanionId == id) {
      _activeCompanionId = _companions.isNotEmpty ? _companions.first.id : null;
      CompanionRuntimeStore.instance.setActiveCompanion(activeCompanion);
    }
    await _saveToStorage();
  }

  /// 設置活躍夥伴
  /// [2026-08-26 共視修復] 換夥伴廣播——任何 setActive 都通知所有監聽者。
  /// 病根：切換 sheet 只改 store，ChatController._activeCompanion 沒跟
  /// → system prompt 仍注入前一位人格（換了等於沒換）。
  final _companionChangedListeners = <void Function(Companion)>[];

  void addCompanionChangedListener(void Function(Companion) fn) =>
      _companionChangedListeners.add(fn);
  void removeCompanionChangedListener(void Function(Companion) fn) =>
      _companionChangedListeners.remove(fn);

  Future<void> setActive(String id) async {
    if (!_companions.any((c) => c.id == id)) {
      throw Exception('Companion with id $id not found');
    }
    _activeCompanionId = id;
    await _prefs?.setString(_activeCompanionKey, id);
    CompanionRuntimeStore.instance.setActiveCompanion(activeCompanion);
    notifyListeners();
    // [2026-08-26 共視修復] 廣播換人——讓所有 ChatController 即時跟上，
    // system prompt 的人格注入才會同步換人。
    final c = activeCompanion;
    if (c != null) {
      for (final fn in List.of(_companionChangedListeners)) {
        try {
          fn(c);
        } catch (_) {}
      }
    }
  }

  /// 更新夥伴狀態（不觸發儲存，用於執行時狀態）
  void updateStatus(String id, CompanionStatus status) {
    final index = _companions.indexWhere((c) => c.id == id);
    if (index != -1) {
      _companions[index].status = status;
      if (status != CompanionStatus.idle) {
        _companions[index].lastSummoned = DateTime.now();
      }
    }
  }

  /// 記錄對話統計
  Future<void> recordConversation(String id, int tokens) async {
    final companion = getById(id);
    if (companion == null) return;

    final updated = companion.copyWith(
      totalConversations: companion.totalConversations + 1,
      totalTokens: companion.totalTokens + tokens,
      lastSummoned: DateTime.now(),
    );
    await update(updated);
  }

  // [教練 Agent 2026-08-04] appearanceHistory 已刪除，函數已棄用
  // /// 新增形象變化到歷史
  // Future<void> addAppearanceHistory(String id, String description) async {
  //   final companion = getById(id);
  //   if (companion == null) return;
  //
  //   final history = [...companion.appearanceHistory, description];
  //   // 只保留最近 10 筆
  //   if (history.length > 10) {
  //     history.removeAt(0);
  //   }
  //
  //   final updated = companion.copyWith(
  //     appearanceHistory: history,
  //     appearanceDescription: description,
  //   );
  //   await update(updated);
  // }

  // === 儲存 / 載入 ===

  Future<void> _loadFromStorage() async {
    if (_prefs == null) return;

    final jsonString = _prefs!.getString(_storageKey);
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _companions = jsonList
            .map((j) => Companion.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (e) {
        // 如果解析失敗，重置為空列表
        _companions = [];
      }
    }

    _activeCompanionId = _prefs!.getString(_activeCompanionKey);
  }

  Future<void> _saveToStorage() async {
    if (_prefs == null) return;

    final jsonList = _companions.map((c) => c.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await _prefs!.setString(_storageKey, jsonString);

    if (_activeCompanionId != null) {
      await _prefs!.setString(_activeCompanionKey, _activeCompanionId!);
    }
  }

  // === 匯出 / 匯入（未來擴充）===

  /// 匯出所有夥伴為 JSON 字串
  String exportToJson() {
    final jsonList = _companions.map((c) => c.toJson()).toList();
    return jsonEncode({
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'companions': jsonList,
      'activeCompanionId': _activeCompanionId,
    });
  }

  /// 從 JSON 匯入夥伴
  Future<int> importFromJson(String jsonString) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final List<dynamic> companionList = data['companions'];

    int imported = 0;
    for (final item in companionList) {
      try {
        final companion = Companion.fromJson(item as Map<String, dynamic>);
        // 如果 ID 重複，生成新 ID
        if (_companions.any((c) => c.id == companion.id)) {
          continue; // 跳過重複
        }
        _companions.add(companion);
        imported++;
      } catch (_) {
        // 跳過無效的夥伴資料
      }
    }

    await _saveToStorage();
    return imported;
  }

  /// 匯出單一夥伴為 Companion Pack JSON
  String exportCompanionPackToJson(String id, {bool? commercialUseAllowed}) {
    final companion = getById(id);
    if (companion == null) {
      throw Exception('Companion with id $id not found');
    }
    return CompanionPackService(
      localInstallId: localInstallId,
    ).exportToJson(companion, commercialUseAllowed: commercialUseAllowed);
  }

  /// 從 Companion Pack JSON 匯入夥伴（同步版，不處理圖片存檔）
  Future<Companion> importCompanionPackFromJson(String jsonString) async {
    final companion = CompanionPackService(
      localInstallId: localInstallId,
    ).importFromJson(jsonString);
    await add(companion);
    return companion;
  }

  /// [教練 Agent 2026-06-28] OOM 安全匯入：base64 圖片存檔，不在記憶體保留
  Future<Companion> importCompanionPackFromJsonAsync(String jsonString) async {
    final companion = await CompanionPackService(
      localInstallId: localInstallId,
    ).importFromJsonAsync(jsonString);
    await add(companion);
    return companion;
  }

  /// [教練 Agent 2026-06-28] ZIP 格式匯出
  Future<List<int>> exportCompanionPackToZip(String id, {bool? commercialUseAllowed}) async {
    final companion = getById(id);
    if (companion == null) {
      throw Exception('Companion with id $id not found');
    }
    return CompanionPackService(
      localInstallId: localInstallId,
    ).exportToZip(companion, commercialUseAllowed: commercialUseAllowed);
  }

  /// [教練 Agent 2026-06-28] ZIP 格式匯入
  Future<Companion> importCompanionPackFromZip(List<int> zipBytes) async {
    final companion = await CompanionPackService(
      localInstallId: localInstallId,
    ).importFromZip(zipBytes);
    await add(companion);
    return companion;
  }

  /// [教練 Agent 2026-07-22] Phase H — 非阻塞觸發人格卡重新推理
  ///
  /// 夥伴基本資料修改後，用更新後的資料重新推理人格卡。
  /// 舊的人格卡會被封存，新的覆蓋上去。
  void _triggerPersonaReinference(Companion companion) {
    // 非阻塞——fire and forget
    PersonaInferenceService.instance.reinfer(
      companion: companion,
      summonPrompt: companion.appearancePrompt,
    ).then((card) {
      debugPrint('[CompanionStore] 人格卡重新推理完成: ${card.archetype}');
    }).catchError((e) {
      debugPrint('[CompanionStore] 人格卡重新推理失敗: $e');
    });
  }

  String _ensureLocalInstallId() {
    final current = _prefs?.getString(_localInstallIdKey);
    if (current != null && current.trim().isNotEmpty) return current;
    final generated = 'local_${DateTime.now().microsecondsSinceEpoch}';
    _prefs?.setString(_localInstallIdKey, generated);
    return generated;
  }

  // === 預設夥伴工廠 ===

  /// 建立一個通用型預設夥伴（用於首次使用引導）
  static Companion createDefaultCompanion() {
    return Companion(
      id: 'default_${DateTime.now().millisecondsSinceEpoch}',
      name: '夥伴', // [2026-08-26] 原生 Agent 不再有固定名字——名字主權歸使用者
      mbtiCode: 'ENFJ',
      role: CompanionRole.general,
      personalityTags: [PersonalityTag.warm, PersonalityTag.concise],
      appearancePrompt: '溫暖友善的幾何光點，像一盞引路的燈',
      appearanceDescription: '一團溫暖的琥珀色幾何光點，邊緣柔和，會隨著對話節奏輕微脈動',
      trustBoundary: const TrustBoundary(
        autoExecute: false,
        confirmBeforeSend: true,
        dataRetentionDays: 30,
        allowFileAccess: false,
      ),
    );
  }

  /// 產生唯一 ID
  static String generateId() {
    return 'cmp_${DateTime.now().millisecondsSinceEpoch}_${(1000 + DateTime.now().microsecond)}';
  }

  @visibleForTesting
  void resetForTest() {
    _prefs = null;
    _companions = [];
    _activeCompanionId = null;
    _initialized = false;
  }
}
