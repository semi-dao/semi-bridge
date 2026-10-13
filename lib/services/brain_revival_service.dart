import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'activity/background_task_registry.dart';
import 'local_model_runtime_service.dart';
import 'storage_service.dart';

/// [小葵 2026-10-01 F5] 大腦自動復活 v2——引擎級（Blue 令：適用所有開源模型）。
///
/// 監測 llama-server「進程層」健康（HTTP /v1/models），與模型型號完全無關：
/// 任何 GGUF 登基都受同一套保護。
///
/// 設計（七金礦案卷——12B 四次無聲死 + UI stale「運行中」）：
/// - 每 30 秒 poll；連續 2 次失敗 = 死亡判定
/// - 死亡 → 掛牌活動中心「重啟大腦中」→ startServer()（用 Swift 側現役模型）
/// - 復活成功後 10 分鐘冷卻（防復活風暴）；每次死亡只試 1 次
/// - A3 單一真相源：本服務廣播 = 引擎生命週期唯一事實；UI 徽章只訂閱
class BrainRevivalService {
  BrainRevivalService._();
  static final instance = BrainRevivalService._();

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  Timer? _watchTimer;

  // ═══ [小葵 2026-10-05 Blue 令] 本地模型手動開關 + 閒置自動卸載 ═══
  // 三態守則：
  //  - userEnabled=false：使用者手動關閉 → 看門狗不救、閒置計時器不啟
  //  - userEnabled=true（預設）：看門狗照舊救活引擎
  //  - 閒置卸載：引擎連續 idle 10 分鐘 → 自動 stopServer（不動 userEnabled，
  //    下次需要時看門狗 60s 內自動載回）
  static const _idleUnloadThreshold = Duration(minutes: 10);
  bool _userEnabled = true; // 使用者意願（手動開關）；卸載不動它
  bool get userEnabled => _userEnabled;

  // [Blue 令 2026-10-05] 閒置自動卸載本身也要有開關（預設開，持久化）
  bool _idleUnloadEnabled = true;
  bool get idleUnloadEnabled => _idleUnloadEnabled;
  Future<void> loadIdleUnloadPref() async {
    _idleUnloadEnabled = await StorageService.getLocalModelIdleUnloadEnabled();
  }

  Future<void> setIdleUnloadEnabled(bool v) async {
    _idleUnloadEnabled = v;
    if (!v) _idleSince = null; // 關閉時清計時
    await StorageService.saveLocalModelIdleUnloadEnabled(v);
    _powerController.add(_userEnabled); // 通知 UI 刷新
  }
  DateTime? _idleSince; // 引擎開始閒置的時間
  final _powerController = StreamController<bool>.broadcast();
  /// 開關狀態變化流（頂部按鈕訂閱刷新）
  Stream<bool> get powerStream => _powerController.stream;

  /// 使用者手動開：立刻拉起引擎（不等看門狗輪詢）
  Future<void> powerOn(LocalModelRuntimeService runtime) async {
    _userEnabled = true;
    _idleSince = null;
    _idleUnloaded = false; // [小葵 2026-10-05 修] 手動喚醒=脫離閒置卸載狀態
    _powerController.add(true);
    await _revive(runtime);
  }

  /// 使用者手動關：停引擎 + 看門狗降級為「靜默觀察」（不救活）
  Future<void> powerOff(LocalModelRuntimeService runtime) async {
    _userEnabled = false;
    _idleSince = null;
    _consecutiveFailures = 0; // 重置，避免重開時誤觸冷卻
    _powerController.add(false);
    _emit(BrainPhase.off, '本地模型已手動關閉（看門狗待命，不自動重啟）');
    await runtime.stopServer();
  }
  int _consecutiveFailures = 0;
  bool _reviving = false;
  DateTime? _lastRevivalAttemptAt; // [F5d] 上次「嘗試」（成敗都算）
  int _deathCount = 0;

  /// 生命週期單一真相源（U2 徽章訂閱此 stream）
  final _lifecycleController = StreamController<BrainLifecycle>.broadcast();
  Stream<BrainLifecycle> get stream => _lifecycleController.stream;
  BrainLifecycle _lifecycle = BrainLifecycle(BrainPhase.alive);
  BrainLifecycle get lifecycle => _lifecycle;

  void _emit(BrainPhase phase, [String? detail]) {
    _lifecycle = BrainLifecycle(phase, detail);
    _lifecycleController.add(_lifecycle);
  }

  /// 啟動看門狗（App 啟動 / 引擎起來後呼叫；重複呼叫無害）
  void startWatch(LocalModelRuntimeService runtime) {
    loadIdleUnloadPref(); // [Blue 令] 載入閒置卸載開關偏好
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _poll(runtime);
    });
    debugPrint('[BrainRevival] 看門狗啟動（30s poll，引擎級，模型無關）');
  }

  void stopWatch() {
    _watchTimer?.cancel();
    _watchTimer = null;
  }

  /// [Blue 令 2026-10-05] 閒置偵測：llama-server /slots 全部 is_processing=false
  /// 連續 10 分鐘 → 自動卸載（userEnabled 不動——下次需要時看門狗自動載回）。
  Future<void> _checkIdleUnload(
      LocalModelRuntimeService runtime, String url) async {
    if (!_idleUnloadEnabled) return; // [Blue 令] 使用者關閉自動卸載
    final busy = await _anySlotProcessing(url);
    if (busy) {
      _idleSince = null; // 有人用——重置計時
      return;
    }
    final idleSince = _idleSince ??= DateTime.now();
    final idleFor = DateTime.now().difference(idleSince);
    if (idleFor >= _idleUnloadThreshold) {
      _idleSince = null;
      _emit(BrainPhase.off, '本地模型閒置 ${idleFor.inMinutes} 分鐘——已自動卸載釋放記憶體');
      BackgroundTaskRegistry.instance.finish('brain_revival',
          note: '閒置 ${idleFor.inMinutes} 分鐘自動卸載 ✓');
      debugPrint('[BrainRevival] 💤 閒置 ${idleFor.inMinutes} 分鐘 → 自動卸載本地模型');
      await runtime.stopServer();
      // [小葵 2026-10-05 修] 卸載後「保持卸載」——看門狗不再自動拉回。
      // 原設計（冷卻 10 分鐘後自動救）實測 = 延遲 20 分鐘的重啟，
      // 省記憶體意義歸零。改為：_idleUnloaded=true → _poll 靜默，
      // 手動喚醒（powerOn）或下次有需求時才會再載。
      // （UI 的「本地」按鈕點一下就能喚醒。）
      _idleUnloaded = true;
    }
  }

  DateTime? _idleCooldownUntil;

  /// [小葵 2026-10-05 Blue 令 4-AED] 需求驅動復活——她需要腦時直接喚醒。
  ///
  /// 2026-10-05 事故：她在推理中引擎死亡（記憶體壓力壓死 llama-server），
  /// loop client 收到連線失敗後只會換 provider 重試，看門狗則被
  /// _idleUnloaded / 10 分鐘冷卻擋住——「她需要腦」這個訊號沒有人聽，
  /// 卡死 40 分鐘靠教練手動 spawn。
  ///
  /// 本方法 = AED：推理層（api_service）偵測本地引擎連線失敗時直接呼叫。
  /// - 不受 _idleUnloaded 擋（有需求=不是閒置）
  /// - 不受死亡冷卻擋（有需求比節流重要）
  /// - 自帶 60s 小冷卻（防一個 turn 內連續失敗觸發復活風暴）
  /// - fail-open：救不起來不丟例外，讓原呼叫鏈走原本的錯誤處理
  DateTime? _lastDemandReviveAt;
  Future<void> demandRevive(LocalModelRuntimeService runtime) async {
    if (_lastDemandReviveAt != null &&
        DateTime.now().difference(_lastDemandReviveAt!).inSeconds < 60) {
      return; // 小冷卻中
    }
    _lastDemandReviveAt = DateTime.now();
    _idleSince = null;
    _idleUnloaded = false; // 有需求=脫離閒置卸載狀態
    _consecutiveFailures = 0; // 讓看門狗歸零重新計
    _emit(BrainPhase.restarting, '推理請求失敗——需求驅動復活中（AED）');
    BackgroundTaskRegistry.instance.update(BackgroundTask(
      id: 'brain_revival',
      name: '本地大腦',
      detail: '推理請求偵測引擎無回應——AED 啟動',
      startedAt: DateTime.now(),
    ));
    try {
      await _revive(runtime);
    } catch (e) {
      debugPrint('[BrainRevival] AED 復活例外（fail-open）: $e');
    }
  }

  /// [小葵 2026-10-05 修] 閒置自動卸載狀態——true=保持卸載，等手動喚醒
  bool _idleUnloaded = false;

  /// 查 llama-server /slots 是否有任何 slot 在處理請求
  Future<bool> _anySlotProcessing(String baseUrl) async {
    try {
      final resp = await _dio.get<List<dynamic>>('$baseUrl/slots');
      final slots = resp.data;
      if (slots == null) return true; // 讀不到就保守當忙碌（不誤殺）
      return slots.any((s) {
        final m = s;
        return m is Map && m['is_processing'] == true;
      });
    } catch (_) {
      return true; // 端點不支援（舊版 llama-server）→ 保守不卸載
    }
  }

  Future<void> _poll(LocalModelRuntimeService runtime) async {
    if (_reviving) return;
    // [Blue 令 2026-10-05] 使用者手動關閉 → 看門狗靜默觀察，不救活
    if (!_userEnabled) return;
    // [小葵 2026-10-05 修] 閒置自動卸載後保持卸載——手動喚醒前不拉回
    if (_idleUnloaded) return;
    final url = await StorageService.getLocalModelEndpoint();
    if (url == null || url.isEmpty) return; // 無現役引擎——不歸看門狗管
    if (!url.contains('127.0.0.1') && !url.contains('localhost')) return;

    final ok = await _probe(url);
    if (ok) {
      _consecutiveFailures = 0;
      if (_lifecycle.phase != BrainPhase.alive) {
        _emit(BrainPhase.alive);
      }
      // [Blue 令 2026-10-05] 閒置卸載——引擎活著但連續 10 分鐘沒人用 → 卸
      await _checkIdleUnload(runtime, url);
      return;
    }

    _consecutiveFailures++;
    debugPrint('[BrainRevival] health miss ($_consecutiveFailures/2) → $url');
    if (_consecutiveFailures < 2) return;

    // [Blue 令 2026-10-05] 閒置卸載後的冷卻期——引擎是被我們主動卸的，
    // 不是死亡。冷卻期內不救活（省 6.4GB 的意義就在這）。
    if (_idleCooldownUntil != null &&
        DateTime.now().isBefore(_idleCooldownUntil!)) {
      return;
    }

    // ── 死亡判定 ──
    // [F5e] 計數移到 _revive（每 30s miss 都 ++ 會暴衝到 904/1064）

    // [F5d] 冷卻=復活嘗試的節流（防風暴），不是死後見死不救。
    // 原 bug：復活成功後 10 分鐘內引擎再死 → 永不嘗試（miss 15/2 也不動）。
    // 修正：距上次「嘗試」<10 分鐘才跳過；否則嘗試（無論上次成功失敗）。
    if (_lastRevivalAttemptAt != null &&
        DateTime.now().difference(_lastRevivalAttemptAt!).inMinutes < 10) {
      _emit(BrainPhase.dead, '第 $_deathCount 次死亡；冷卻中（10 分鐘一試）');
      BackgroundTaskRegistry.instance.update(BackgroundTask(
        id: 'brain_revival',
        name: '本地大腦',
        detail: '引擎無回應（第 $_deathCount 次）——冷卻 10 分鐘',
        status: BackgroundTaskStatus.error,
        startedAt: DateTime.now(),
      ));
      return;
    }

    await _revive(runtime);
  }

  Future<void> _revive(LocalModelRuntimeService runtime) async {
    _reviving = true;
    _deathCount++; // [F5e] 死亡計數=復活嘗試數（真實死亡次數）
    _lastRevivalAttemptAt = DateTime.now(); // [F5d] 嘗試即計時
    _emit(BrainPhase.restarting, '重啟大腦中（現役模型，不寫死型號）');
    BackgroundTaskRegistry.instance.update(BackgroundTask(
      id: 'brain_revival',
      name: '本地大腦',
      detail: '引擎無回應——自動重啟中',
      startedAt: DateTime.now(),
    ));
    try {
      // 引擎級：不帶 modelId = Swift 側用記住的現役模型（任何 GGUF 通用）
      final state = await runtime.startServer();
      final url = state.serverUrl;
      final healthy = state.serverHealthy == true ||
          (url != null && await _probe(url));
      if (healthy) {
        _consecutiveFailures = 0;
        _emit(BrainPhase.alive, '已復活（累計第 $_deathCount 次死亡）');
        BackgroundTaskRegistry.instance.finish('brain_revival', note: '已復活 ✓');
        debugPrint('[BrainRevival] ✅ 復活成功');
      } else {
        _emit(BrainPhase.dead, '復活失敗——冷卻 10 分鐘後再試');
        BackgroundTaskRegistry.instance.update(BackgroundTask(
          id: 'brain_revival',
          name: '本地大腦',
          detail: '復活失敗——冷卻 10 分鐘',
          status: BackgroundTaskStatus.error,
          startedAt: DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('[BrainRevival] 復活例外: $e');
      _emit(BrainPhase.dead, '復活例外：$e');
    } finally {
      _reviving = false;
    }
  }

  Future<bool> _probe(String url) async {
    try {
      final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
      // [F5e] /health 是 llama 的輕量端點（不經推理佇列）；
      // /v1/models 在批次嵌入滿載時會 timeout → 誤判死亡（第 1064 次死亡之謎）
      final resp = await _dio.get<Map<String, dynamic>>('$base/health');
      return resp.statusCode == 200 && resp.data?['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }
}

/// 引擎生命週期（A3 單一真相源）
enum BrainPhase { alive, restarting, dead, off }

class BrainLifecycle {
  final BrainPhase phase;
  final String? detail;
  final DateTime at;
  BrainLifecycle(this.phase, [this.detail]) : at = DateTime.now();
}
