import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'companion_runtime_store.dart';
import 'local_model_catalog_service.dart';
import 'macos_desktop_shell_channel.dart';
import 'storage_service.dart';
import 'provider_router.dart'; // [教練 Agent 2026-07-22] 動態路由

typedef LocalModelRuntimeProbe =
    Future<Map<String, dynamic>> Function(String endpoint);
typedef BridgeRuntimeHealthProbe =
    Future<Map<String, dynamic>> Function(String endpoint);

class LocalModelRuntimeProfile {
  final String endpoint;
  final bool connected;
  final String runtimeLabel;
  final List<String> models;
  final String? selectedModel;
  final String detail;

  const LocalModelRuntimeProfile({
    required this.endpoint,
    required this.connected,
    required this.runtimeLabel,
    this.models = const [],
    this.selectedModel,
    required this.detail,
  });

  String get statusLabel {
    if (connected && selectedModel != null) return '本地主腦可用';
    if (connected) return '已偵測';
    return '尚未偵測';
  }
}

enum BridgeLocalRuntimePhase {
  notInstalled,
  downloading,
  installed,
  starting,
  running,
  failed,
}

enum BridgeLocalRuntimeCommand {
  status,
  prepareRuntime,
  downloadModel,
  deleteModel,
  testModel,
  startServer,
  stopServer,
  startLabServer, // [小葵 2026-09-29 A案] 模型實驗室專用（18799），不動主生產線
  stopLabServer,
}

extension BridgeLocalRuntimePhaseX on BridgeLocalRuntimePhase {
  String get label {
    switch (this) {
      case BridgeLocalRuntimePhase.notInstalled:
        return '尚未安裝';
      case BridgeLocalRuntimePhase.downloading:
        return '下載中';
      case BridgeLocalRuntimePhase.installed:
        return '已安裝';
      case BridgeLocalRuntimePhase.starting:
        return '啟動中';
      case BridgeLocalRuntimePhase.running:
        return '運行中';
      case BridgeLocalRuntimePhase.failed:
        return '需要處理';
    }
  }
}

class BridgeLocalRuntimeState {
  final BridgeLocalRuntimePhase phase;
  final String title;
  final String detail;
  final BridgeLocalRuntimeCommand primaryCommand;
  final String primaryActionLabel;
  final bool primaryActionEnabled;
  final double? progress;
  final String? runtimePath;
  final String? runtimeExecutablePath;
  final String? expectedRuntimeExecutablePath;
  final String? modelFilePath;
  final String? expectedModelFilePath;
  final String? serverUrl;
  final String? taskPath;
  final String? modelId;
  final String? activeModelName;
  final bool? serverHealthy;
  final String? healthDetail;

  const BridgeLocalRuntimeState({
    required this.phase,
    required this.title,
    required this.detail,
    required this.primaryCommand,
    required this.primaryActionLabel,
    required this.primaryActionEnabled,
    this.progress,
    this.runtimePath,
    this.runtimeExecutablePath,
    this.expectedRuntimeExecutablePath,
    this.modelFilePath,
    this.expectedModelFilePath,
    this.serverUrl,
    this.taskPath,
    this.modelId,
    this.activeModelName,
    this.serverHealthy,
    this.healthDetail,
  });

  bool get running => phase == BridgeLocalRuntimePhase.running;
  bool get installed =>
      phase == BridgeLocalRuntimePhase.installed ||
      phase == BridgeLocalRuntimePhase.starting ||
      phase == BridgeLocalRuntimePhase.running;

  factory BridgeLocalRuntimeState.fromJson(Map<dynamic, dynamic> json) {
    return BridgeLocalRuntimeState(
      phase: _phaseFrom(json['phase']),
      title: _readString(json, 'title', 'Bridge Local Runtime'),
      detail: _readString(json, 'detail', '等待 Bridge Desktop 回報本地引擎狀態。'),
      primaryCommand: _commandFrom(json['primaryCommand']),
      primaryActionLabel: _readString(json, 'primaryActionLabel', '準備下載本地引擎'),
      primaryActionEnabled: json['primaryActionEnabled'] == true,
      progress: _readDouble(json, 'progress'),
      runtimePath: _readOptionalString(json, 'runtimePath'),
      runtimeExecutablePath: _readOptionalString(json, 'runtimeExecutablePath'),
      expectedRuntimeExecutablePath: _readOptionalString(
        json,
        'expectedRuntimeExecutablePath',
      ),
      modelFilePath: _readOptionalString(json, 'modelFilePath'),
      expectedModelFilePath: _readOptionalString(json, 'expectedModelFilePath'),
      serverUrl: _readOptionalString(json, 'serverUrl'),
      taskPath: _readOptionalString(json, 'taskPath'),
      modelId: _readOptionalString(json, 'modelId'),
      activeModelName:
          _readOptionalString(json, 'activeModelName') ??
          _readOptionalString(json, 'modelName') ??
          _readOptionalString(json, 'modelId'),
      serverHealthy: _readOptionalBool(json, 'serverHealthy'),
      healthDetail: _readOptionalString(json, 'healthDetail'),
    );
  }

  BridgeLocalRuntimeState copyWith({
    BridgeLocalRuntimePhase? phase,
    String? title,
    String? detail,
    BridgeLocalRuntimeCommand? primaryCommand,
    String? primaryActionLabel,
    bool? primaryActionEnabled,
    double? progress,
    String? runtimePath,
    String? runtimeExecutablePath,
    String? expectedRuntimeExecutablePath,
    String? modelFilePath,
    String? expectedModelFilePath,
    String? serverUrl,
    String? taskPath,
    String? modelId,
    String? activeModelName,
    bool? serverHealthy,
    String? healthDetail,
  }) {
    return BridgeLocalRuntimeState(
      phase: phase ?? this.phase,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      primaryCommand: primaryCommand ?? this.primaryCommand,
      primaryActionLabel: primaryActionLabel ?? this.primaryActionLabel,
      primaryActionEnabled: primaryActionEnabled ?? this.primaryActionEnabled,
      progress: progress ?? this.progress,
      runtimePath: runtimePath ?? this.runtimePath,
      runtimeExecutablePath:
          runtimeExecutablePath ?? this.runtimeExecutablePath,
      expectedRuntimeExecutablePath:
          expectedRuntimeExecutablePath ?? this.expectedRuntimeExecutablePath,
      modelFilePath: modelFilePath ?? this.modelFilePath,
      expectedModelFilePath:
          expectedModelFilePath ?? this.expectedModelFilePath,
      serverUrl: serverUrl ?? this.serverUrl,
      taskPath: taskPath ?? this.taskPath,
      modelId: modelId ?? this.modelId,
      activeModelName: activeModelName ?? this.activeModelName,
      serverHealthy: serverHealthy ?? this.serverHealthy,
      healthDetail: healthDetail ?? this.healthDetail,
    );
  }

  static BridgeLocalRuntimePhase _phaseFrom(Object? value) {
    final name = value?.toString();
    for (final phase in BridgeLocalRuntimePhase.values) {
      if (phase.name == name) return phase;
    }
    return BridgeLocalRuntimePhase.notInstalled;
  }

  static BridgeLocalRuntimeCommand _commandFrom(Object? value) {
    final name = value?.toString();
    for (final command in BridgeLocalRuntimeCommand.values) {
      if (command.name == name) return command;
    }
    return BridgeLocalRuntimeCommand.prepareRuntime;
  }

  static String _readString(
    Map<dynamic, dynamic> json,
    String key,
    String fallback,
  ) {
    final value = json[key];
    return value is String && value.isNotEmpty ? value : fallback;
  }

  static double? _readDouble(Map<dynamic, dynamic> json, String key) {
    final value = json[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String? _readOptionalString(Map<dynamic, dynamic> json, String key) {
    final value = json[key];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  static bool? _readOptionalBool(Map<dynamic, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) return value;
    if (value is String) return bool.tryParse(value);
    return null;
  }
}

class LocalModelRuntimeService {
  static const defaultEndpoint = 'http://127.0.0.1:18789';

  LocalModelRuntimeService({
    Dio? dio,
    LocalModelRuntimeProbe? probe,
    BridgeRuntimeHealthProbe? healthProbe,
    MacosDesktopShellChannel desktopChannel = const MacosDesktopShellChannel(),
  }) : _dio = dio ?? Dio(),
       _probe = probe,
       _healthProbe = healthProbe,
       _desktopChannel = desktopChannel;

  final Dio _dio;
  final LocalModelRuntimeProbe? _probe;
  final BridgeRuntimeHealthProbe? _healthProbe;
  final MacosDesktopShellChannel _desktopChannel;

  Future<LocalModelRuntimeProfile> inspectStored() async {
    final endpoint =
        await StorageService.getLocalModelEndpoint() ?? defaultEndpoint;
    final selectedModel = await StorageService.getLocalModelName();
    if (selectedModel == null || selectedModel.trim().isEmpty) {
      return LocalModelRuntimeProfile(
        endpoint: endpoint,
        connected: false,
        runtimeLabel: 'Ollama / OpenAI-compatible',
        selectedModel: null,
        detail: '尚未偵測本機模型服務，可先嘗試預設端點。',
      );
    }
    return LocalModelRuntimeProfile(
      endpoint: endpoint,
      connected: true,
      runtimeLabel: '本地 OpenAI-compatible',
      models: [selectedModel],
      selectedModel: selectedModel,
      detail: '已保存本地主腦模型 $selectedModel。',
    );
  }

  Future<BridgeLocalRuntimeState> inspectBridgeRuntime() async {
    final nativeState = await _invokeBridgeRuntime(
      BridgeLocalRuntimeCommand.status,
    );
    if (nativeState != null) {
      var checkedState = nativeState.running
          ? await _withBridgeRuntimeHealth(nativeState)
          : nativeState;
      // [教練 Agent 2026-08-25] port 被佔就重用：App 自己沒 spawn 引擎時，
      // 探測 18789 是否有外部引擎（launchd 常駐 llama-server 等）在服務。
      // 有 → 直接報 running（engine 重用，不改使用者 provider 選擇——inspect 是 probe）。
      if (!checkedState.running) {
        try {
          final payload = await _probeOpenAIModels(defaultEndpoint);
          final models = _parseModels(payload);
          if (models.isNotEmpty) {
            checkedState = checkedState.copyWith(
              phase: BridgeLocalRuntimePhase.running,
              detail: '偵測到 $defaultEndpoint 已有推論引擎服務中（外部引擎），直接重用。',
              serverUrl: defaultEndpoint,
              activeModelName: _resolveShortModelName(models.first),
              serverHealthy: true,
              healthDetail: '外部引擎健康檢查通過，偵測到 ${models.length} 個本地模型。',
            );
          }
        } catch (_) {
          // 18789 沒人服務＝正常情況，走原本的 installed/notInstalled 流程
        }
      }
      // [教練 Agent 2026-08-07] 修復：inspect 是 probe，不應該改 provider！
      // 之前 line 293 自動 activateBridgeRuntimeAsBrain 導致使用者選 Gemini 時，
      // UI 為判斷 local 是否在跑而 probe → 自動把 provider 改成 local。
      // activateBridgeRuntimeAsBrain 仍保留，但只在明確呼叫 startServer 時觸發。
      _publishCompanionSignal(checkedState);
      return checkedState;
    }

    final selectedModel = await StorageService.getLocalModelName();
    final provider = await StorageService.getProvider();
    if (provider == 'local' &&
        selectedModel != null &&
        selectedModel.trim().isNotEmpty) {
      final runningState = BridgeLocalRuntimeState(
        phase: BridgeLocalRuntimePhase.running,
        title: 'Bridge Local Runtime',
        detail: '本地主腦已接入，Bridge 會把本地模型視為內建能力。',
        primaryCommand: BridgeLocalRuntimeCommand.status,
        primaryActionLabel: '已啟用',
        primaryActionEnabled: false,
      );
      _publishCompanionSignal(runningState);
      return runningState;
    }

    return const BridgeLocalRuntimeState(
      phase: BridgeLocalRuntimePhase.notInstalled,
      title: 'Bridge Local Runtime',
      detail: '下一步會由 Bridge Desktop 下載並管理內建推論引擎，使用者不需要另外安裝 Ollama。',
      primaryCommand: BridgeLocalRuntimeCommand.prepareRuntime,
      primaryActionLabel: '準備下載本地引擎',
      primaryActionEnabled: true,
    );
  }

  Future<BridgeLocalRuntimeState> prepareBridgeRuntime() async {
    final nativeState = await _invokeBridgeRuntime(
      BridgeLocalRuntimeCommand.prepareRuntime,
    );
    if (nativeState != null) {
      _publishCompanionSignal(nativeState);
      return nativeState;
    }

    return const BridgeLocalRuntimeState(
      phase: BridgeLocalRuntimePhase.notInstalled,
      title: 'Bridge Local Runtime',
      detail: 'Bridge Desktop 尚未接管本地引擎安裝命令；目前仍可用進階相容入口連接既有本地服務。',
      primaryCommand: BridgeLocalRuntimeCommand.status,
      primaryActionLabel: '等待桌面端支援',
      primaryActionEnabled: false,
    );
  }

  Future<BridgeLocalRuntimeState> downloadModel(
    LocalModelRecommendation recommendation,
  ) async {
    final nativeState = await _invokeBridgeRuntime(
      BridgeLocalRuntimeCommand.downloadModel,
      payload: {
        'model': recommendation.model.toJson(),
        'fit': recommendation.fit.name,
        'reason': recommendation.reason,
      },
    );
    if (nativeState != null) {
      _publishCompanionSignal(nativeState);
      return nativeState;
    }

    return const BridgeLocalRuntimeState(
      phase: BridgeLocalRuntimePhase.installed,
      title: 'Bridge Local Runtime',
      detail: 'Bridge Desktop 尚未接管模型下載命令；目前仍可用進階相容入口連接既有本地服務。',
      primaryCommand: BridgeLocalRuntimeCommand.status,
      primaryActionLabel: '等待桌面端支援',
      primaryActionEnabled: false,
    );
  }

  /// [教練 Agent 2026-07-20] 刪除已下載的模型檔案
  Future<BridgeLocalRuntimeState> deleteModel(String modelId) async {
    final nativeState = await _invokeBridgeRuntime(
      BridgeLocalRuntimeCommand.deleteModel,
      payload: {'modelId': modelId},
    );
    if (nativeState != null) {
      _publishCompanionSignal(nativeState);
      return nativeState;
    }

    return const BridgeLocalRuntimeState(
      phase: BridgeLocalRuntimePhase.installed,
      title: 'Bridge Local Runtime',
      detail: '模型刪除命令無法送達桌面端。',
      primaryCommand: BridgeLocalRuntimeCommand.status,
      primaryActionLabel: '等待桌面端支援',
      primaryActionEnabled: false,
    );
  }

  /// [教練 Agent 2026-07-20] 測試模型是否可用
  Future<BridgeLocalRuntimeState> testModel(String modelId) async {
    final nativeState = await _invokeBridgeRuntime(
      BridgeLocalRuntimeCommand.testModel,
      payload: {'modelId': modelId},
    );
    if (nativeState != null) {
      _publishCompanionSignal(nativeState);
      return nativeState;
    }
    return const BridgeLocalRuntimeState(
      phase: BridgeLocalRuntimePhase.installed,
      title: '本地 LLM 引擎',
      detail: '測試指令失敗（native 無回應）',
      primaryCommand: BridgeLocalRuntimeCommand.status,
      primaryActionLabel: '重新檢查',
      primaryActionEnabled: true,
    );
  }

  /// [小葵 2026-09-29 A案] 模型實驗室 lab server（18799）——快測專用引擎，
  /// 與 18789 主生產線完全獨立。回傳 native state（含 labServer 狀態）。
  Future<BridgeLocalRuntimeState?> startLabServer(String modelId) async {
    return _invokeBridgeRuntime(
      BridgeLocalRuntimeCommand.startLabServer,
      payload: {'modelId': modelId},
    );
  }

  Future<BridgeLocalRuntimeState?> stopLabServer() async {
    return _invokeBridgeRuntime(
      BridgeLocalRuntimeCommand.stopLabServer,
    );
  }

  /// [教練 Agent 2026-07-20] 列出已安裝模型（含測試結果）
  Future<List<Map<String, dynamic>>> listInstalledModels() async {
    final response = await _desktopChannel.localRuntime({'action': 'listInstalledModels'});
    if (response == null) return [];
    final list = response['installedModels'] as List? ?? [];
    // 安全轉換：每個 item 可能是 _Map<dynamic, dynamic>
    final result = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is Map) {
        result.add(Map<String, dynamic>.from(item));
      }
    }
    return result;
  }

  /// [教練 Agent 2026-07-20] 啟動 server，可指定 modelId 切換模型
  Future<BridgeLocalRuntimeState> startServer({String? modelId}) async {
    final Map<String, Object?>? payload = modelId != null ? {'modelId': modelId} : null;
    final nativeState = await _invokeBridgeRuntime(
      BridgeLocalRuntimeCommand.startServer,
      payload: payload,
    );
    if (nativeState != null) {
      final checkedState = await _withBridgeRuntimeHealth(nativeState);
      if (checkedState.serverHealthy == true) {
        // [T7③ 2026-10-16 編織線 D7] startServer 是 clutch/背景行為——
        // 只通知路由層「本地可用」，禁改使用者 storage provider。
        // 寫 storage（saveProvider('local')）只留給使用者明確「設為現役」
        // 的 activateBridgeRuntimeAsBrain。
        _notifyRouterLocalAvailable();
      }
      _publishCompanionSignal(checkedState);
      return checkedState;
    }

    return const BridgeLocalRuntimeState(
      phase: BridgeLocalRuntimePhase.installed,
      title: 'Bridge Local Runtime',
      detail: 'Bridge Desktop 尚未接管本地 server 啟動命令。',
      primaryCommand: BridgeLocalRuntimeCommand.status,
      primaryActionLabel: '等待桌面端支援',
      primaryActionEnabled: false,
    );
  }

  /// [T7③ 2026-10-16 編織線] 背景 clutch 用的輕量通知——只動路由層記憶體，
  /// 不碰 StorageService（使用者選的 provider 不被背景程序覆蓋，D7）
  void _notifyRouterLocalAvailable() {
    ProviderRouter.instance.localServerAvailable = true;
  }

  Future<bool> activateBridgeRuntimeAsBrain(
    BridgeLocalRuntimeState state,
  ) async {
    if (!state.running ||
        state.serverUrl == null ||
        state.serverHealthy != true) {
      return false;
    }
    final modelName =
        state.activeModelName ?? state.modelId ?? state.modelFilePath;
    if (modelName == null || modelName.trim().isEmpty) return false;
    await StorageService.saveProvider('local');
    await StorageService.saveGatewayUrl(state.serverUrl!);
    await StorageService.saveToken('bridge-local-runtime', provider: 'local');
    await StorageService.saveLocalModelEndpoint(state.serverUrl!);
    // [教練 Agent 2026-08-05] 用短名存進去（chat 泡泡顯示）
    await StorageService.saveLocalModelName(_resolveShortModelName(modelName)!);
    // [教練 Agent 2026-07-22] 通知路由層：本地 server 可用
    ProviderRouter.instance.localServerAvailable = true;
    return true;
  }

  Future<BridgeLocalRuntimeState> _withBridgeRuntimeHealth(
    BridgeLocalRuntimeState state,
  ) async {
    if (!state.running || state.serverUrl == null) return state;
    // [教練 Agent 2026-07-27] 健康檢查重試 — llama-server 啟動後需要時間載入模型
    // mmproj 多模態投影器載入需要額外時間（~15-20 秒）
    debugPrint('[LocalRuntime] 開始健康檢查重試（最多 8 次，每次間隔 3 秒）');
    for (int attempt = 0; attempt < 8; attempt++) {
      try {
        debugPrint('[LocalRuntime] 健康檢查 attempt ${attempt + 1}/8 → ${state.serverUrl}');
        final payload =
            await (_healthProbe?.call(state.serverUrl!) ??
                _probeOpenAIModels(state.serverUrl!));
        final models = _parseModels(payload);
        debugPrint('[LocalRuntime] ✅ 健康檢查通過，models=${models.length}');
        final modelName = models.isNotEmpty
            ? models.first
            : state.activeModelName ?? state.modelId ?? state.modelFilePath;
        return state.copyWith(
          // [教練 Agent 2026-08-05] 把 llama-server 回傳的檔名解析成 catalog 短 id
          activeModelName: _resolveShortModelName(modelName),
          serverHealthy: true,
          healthDetail: models.isNotEmpty
              ? '健康檢查通過，偵測到 ${models.length} 個本地模型。'
              : '健康檢查通過，本地 server 已回應。',
          detail: '本地模型 server 已通過健康檢查，可以作為本地主腦。',
        );
      } catch (error) {
        debugPrint('[LocalRuntime] ❌ 健康檢查 attempt ${attempt + 1} 失敗: $error');
        if (attempt < 7) {
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
        return state.copyWith(
          serverHealthy: false,
          healthDetail: '健康檢查失敗：$error',
          detail: '本地模型 server 已啟動，但尚未通過健康檢查。',
        );
      }
    }
    return state;
  }

  Future<BridgeLocalRuntimeState> stopServer() async {
    final nativeState = await _invokeBridgeRuntime(
      BridgeLocalRuntimeCommand.stopServer,
    );
    if (nativeState != null) {
      _publishCompanionSignal(nativeState);
      return nativeState;
    }

    return const BridgeLocalRuntimeState(
      phase: BridgeLocalRuntimePhase.installed,
      title: 'Bridge Local Runtime',
      detail: 'Bridge Desktop 尚未接管本地 server 停止命令。',
      primaryCommand: BridgeLocalRuntimeCommand.status,
      primaryActionLabel: '等待桌面端支援',
      primaryActionEnabled: false,
    );
  }

  Future<BridgeLocalRuntimeState?> _invokeBridgeRuntime(
    BridgeLocalRuntimeCommand command, {
    Map<String, Object?>? payload,
  }) async {
    final response = await _desktopChannel.localRuntime({
      'action': command.name,
      ...?payload,
    });
    if (response == null) return null;
    return BridgeLocalRuntimeState.fromJson(response);
  }

  void _publishCompanionSignal(BridgeLocalRuntimeState state) {
    if (state.phase == BridgeLocalRuntimePhase.notInstalled) return;
    CompanionRuntimeStore.instance.reportLocalRuntimeSignal(
      phase: state.phase.name,
      title: state.title,
      detail: state.detail,
      label: state.phase.label,
      progress: state.progress,
    );
  }

  Future<LocalModelRuntimeProfile> detectAndSave({
    String endpoint = defaultEndpoint,
  }) async {
    final normalizedEndpoint = _normalizeEndpoint(endpoint);
    try {
      final payload =
          await (_probe?.call(normalizedEndpoint) ??
              _probeOllamaTags(normalizedEndpoint));
      final models = _parseModels(payload);
      if (models.isEmpty) {
        return LocalModelRuntimeProfile(
          endpoint: normalizedEndpoint,
          connected: false,
          runtimeLabel: _runtimeLabel(payload),
          detail: '已連到本機服務，但沒有找到可用模型。',
        );
      }

      final selectedModel = models.first;
      await StorageService.saveLocalModelEndpoint(normalizedEndpoint);
      // [教練 Agent 2026-08-05] 用短名存進去（chat 泡泡顯示）
      await StorageService.saveLocalModelName(_resolveShortModelName(selectedModel)!);
      return LocalModelRuntimeProfile(
        endpoint: normalizedEndpoint,
        connected: true,
        runtimeLabel: _runtimeLabel(payload),
        models: models,
        selectedModel: selectedModel,
        detail: '已偵測 ${models.length} 個本地模型，預設使用 $selectedModel。',
      );
    } catch (error) {
      return LocalModelRuntimeProfile(
        endpoint: normalizedEndpoint,
        connected: false,
        runtimeLabel: 'Ollama / OpenAI-compatible',
        detail: '偵測失敗：$error',
      );
    }
  }

  Future<void> activateAsBrain(LocalModelRuntimeProfile profile) async {
    final selectedModel = profile.selectedModel;
    if (!profile.connected || selectedModel == null || selectedModel.isEmpty) {
      throw StateError('尚未偵測到可用本地模型');
    }
    await StorageService.saveProvider('local');
    await StorageService.saveGatewayUrl(profile.endpoint);
    await StorageService.saveToken('bridge-local-runtime', provider: 'local');
    await StorageService.saveLocalModelEndpoint(profile.endpoint);
    // [教練 Agent 2026-08-05] 用短名存進去（chat 泡泡顯示）
    await StorageService.saveLocalModelName(_resolveShortModelName(selectedModel)!);
  }

  Future<Map<String, dynamic>> _probeOllamaTags(String endpoint) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$endpoint/api/tags',
      options: Options(
        receiveTimeout: const Duration(seconds: 2),
        sendTimeout: const Duration(seconds: 2),
      ),
    );
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> _probeOpenAIModels(String endpoint) async {
    final normalizedEndpoint = _normalizeEndpoint(endpoint);
    final response = await _dio.get<Map<String, dynamic>>(
      '$normalizedEndpoint/v1/models',
      options: Options(
        receiveTimeout: const Duration(seconds: 3),
        sendTimeout: const Duration(seconds: 3),
      ),
    );
    return response.data ?? const {};
  }

  List<String> _parseModels(Map<String, dynamic> payload) {
    final ollamaModels = payload['models'];
    if (ollamaModels is List) {
      return ollamaModels
          .map((item) {
            if (item is Map) return item['name']?.toString() ?? '';
            return item.toString();
          })
          .where((name) => name.trim().isNotEmpty)
          .toList();
    }

    final openAiModels = payload['data'];
    if (openAiModels is List) {
      return openAiModels
          .map((item) {
            if (item is Map) return item['id']?.toString() ?? '';
            return item.toString();
          })
          .where((name) => name.trim().isNotEmpty)
          .toList();
    }

    return const [];
  }

  String _runtimeLabel(Map<String, dynamic> payload) {
    if (payload['models'] is List) return 'Ollama';
    if (payload['data'] is List) return 'OpenAI-compatible Local';
    return '本地模型服務';
  }

  String _normalizeEndpoint(String endpoint) {
    var value = endpoint.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value.isEmpty ? defaultEndpoint : value;
  }

  // [教練 Agent 2026-08-05] 把 llama-server 回傳的檔名（或長檔名）解析成 catalog 的短 id
  // 例如 "Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M" → "gemma-4-e4b-q4"
  // 對話泡泡底下要顯示短名不要顯示整個檔名
  String? _resolveShortModelName(String? fileNameOrId) {
    return resolveShortModelName(fileNameOrId);
  }
}

/// [教練 Agent 2026-08-05] Top-level helper：把 llama-server 回傳的檔名解析成精簡顯示名
/// [教練 Agent 2026-08-14] 使用者要求：對話泡泡只顯示「Gemma-4-E4B」型號，不要後綴
/// 處理：
/// - "/Users/.../Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf" → "Gemma-4-E4B"
/// - "Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M" → "Gemma-4-E4B"
/// - "gemma-4-e4b-q4" → "Gemma-4-E4B"
/// - "Qwen3.5-4B-Uncensored-HauhauCS-Aggressive-Q4_K_M" → "Qwen3.5-4B"
String? resolveShortModelName(String? fileNameOrId) {
  if (fileNameOrId == null || fileNameOrId.isEmpty) return fileNameOrId;

  // 擷取 basename
  String basename = fileNameOrId;
  if (fileNameOrId.contains('/')) {
    basename = fileNameOrId.split('/').last;
  }

  // 移除 .gguf
  basename = basename.replaceAll(RegExp(r'\.gguf$'), '');

  // [教練 Agent 2026-08-14] 精簡格式：取主型號名，去掉所有後綴
  // Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M → Gemma-4-E4B
  // Qwen3.5-4B-Uncensored-HauhauCS-Aggressive-Q4_K_M → Qwen3.5-4B
  // gemma-4-e4b-q4 → Gemma-4-E4B
  // 先標準化大小寫
  final lower = basename.toLowerCase();

  // 嘗試匹配已知型號 pattern
  final gemmaMatch = RegExp(r'gemma[-_]?(\d+)[-_(]?e(\d+)b', caseSensitive: false).firstMatch(basename);
  if (gemmaMatch != null) {
    return 'Gemma-${gemmaMatch.group(1)}-E${gemmaMatch.group(2)}B';
  }

  final qwenMatch = RegExp(r'(qwen[\d.]*)[-_]?(\d+)b', caseSensitive: false).firstMatch(basename);
  if (qwenMatch != null) {
    final version = qwenMatch.group(1) ?? 'Qwen';
    final params = qwenMatch.group(2) ?? '';
    // Qwen3.5 → Qwen3.5-4B
    return '${_capitalizeQwen(version)}-$params"B'.replaceAll('"B', 'B');
  }

  // 3. fallback: 去掉量化 + 授權後綴，只留主型號
  final cleaned = basename
      .replaceAll(RegExp(r'-Q\d+_K_[A-Z]+$'), '')
      .replaceAll(RegExp(r'-Uncensored.*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'-Instruct$'), '')
      .replaceAll(RegExp(r'-q\d+$'), '');

  return cleaned.isEmpty ? basename : cleaned;
}

String _capitalizeQwen(String s) {
  if (s.isEmpty) return s;
  return 'Qwen${s.substring(4)}';
}
