// ProviderRouter — 動態 Agent 路由
// [教練 Agent 2026-07-22]
//
// 使用者的三層模型分工設計：
//   場景 A（模糊需求）：Agent 判斷模糊 → 本地 4B 釐清 → 共識 → 外部 LLM 開工
//   場景 B（明確指令）：Agent 判斷明確 → 直接外部 LLM → 本地 4B 整理 → embedding 歸檔
//   閒聊 → 本地 4B 輕量
//
// 路由邏輯（純 Dart 規則層，0 token）：
//   IntentSpineMode.execute       → 雲端（重算力）
//   IntentSpineMode.project       → 雲端（需要完整知識庫）
//   IntentSpineMode.assetReuse    → 雲端（需要完整知識庫）
//   IntentSpineMode.capabilitySetup → 雲端
//   IntentSpineMode.analyze       → 本地（輕量釐清）
//   IntentSpineMode.clarify       → 本地（輕量釐清）
//   IntentSpineMode.casual        → 本地（輕量閒聊）
//
// 安全閥：
//   - MemoryGuard 紅燈/危險 → 强制雲端（如果可用）
//   - llama-server 未運行 → 雲端（如果可用）
//   - 沒有雲端 token → 本地（即使意圖是雲端）
//   - 沒有本地 server → 雲端（即使意圖是本地）

import 'package:flutter/foundation.dart';
import 'dart:io'; // [教練 Agent 2026-07-22] HttpClient for server probe
import 'dart:convert'; // [教練 Agent 2026-07-22] utf8 decoder
import '../models/intent_spine.dart';
import 'storage_service.dart';
import 'provider_registry.dart'; // [教練 Agent 2026-07-30] 動態 Provider 探測 + URL 查詢
import 'agent_loop/agent_profile_store.dart'; // [教練 Agent 2026-07-30] 預設選型需要
import 'agent_loop/agent_provider_profile.dart'; // [教練 Agent 2026-07-30] ProviderTier
import 'memory_guard_service.dart';

enum RoutedTarget { local, cloud }

class RoutedProvider {
  final RoutedTarget target;
  final String providerId;
  final String reason;

  /// 是否走輕量路徑（短 prompt + 跳過子分析 + 截斷歷史）
  bool get isLocal => target == RoutedTarget.local;

  const RoutedProvider({
    required this.target,
    required this.providerId,
    required this.reason,
  });
}

class ProviderRouter {
  static final ProviderRouter instance = ProviderRouter._();
  ProviderRouter._();

  /// [T7⑤ 2026-10-16 編織線] 雲端 fallback 順序——全 App 唯一一份常數。
  /// MemoryGuard 緊急降級、LLM client 階梯起點都用這裡，改一處全生效。
  static const List<String> cloudFallbackOrder = [
    'glm', 'openai', 'kimi', 'gemini', 'claude', 'minimax', 'anthropic',
  ];

  /// 當前路由結果（per-message 設定，供 native_agent_loop 讀取）
  RoutedProvider? _current;
  RoutedProvider? get current => _current;

  /// [教練 Agent 2026-07-30] 由外部（chat_controller）設定路由結果
  /// 使用時機：使用者已明確選了雲端 provider，chat_controller 直接建構
  /// RoutedProvider 並傳入，跳過 route() 的快取檢測邏輯。
  void setCurrent(RoutedProvider r) {
    _current = r;
    if (r.target == RoutedTarget.cloud) {
      // [教練 Agent 2026-07-30] 改用 ProviderRegistry.baseUrlOf() 取代 _cloudBaseUrl()
      _routedBaseUrl = ProviderRegistry.baseUrlOf(r.providerId);
    } else if (r.target == RoutedTarget.local) {
      _routedBaseUrl = 'http://127.0.0.1:18789';
    }
    debugPrint('[ProviderRouter] setCurrent: ${r.target.name} (${r.providerId}) — ${r.reason}');
  }

  /// [教練 Agent 2026-07-29] 路由後的 base URL（記憶體中，不寫入 StorageService）
  /// ApiService 讀取此值決定請求目標，使用者選的 provider 不會被覆蓋
  String? _routedBaseUrl;
  String? get routedBaseUrl => _routedBaseUrl;

  /// 備用雲端 provider（啟動時檢測一次）
  String? _cachedCloudProvider;
  bool _localServerAvailable = false;

  /// 設定本地 server 是否可用（由 local_model_runtime_service 更新）
  set localServerAvailable(bool v) {
    _localServerAvailable = v;
    debugPrint('[ProviderRouter] localServerAvailable = $v');
  }

  /// 啟動時檢測可用的雲端 provider
  Future<void> init() async {
    _cachedCloudProvider = await _detectCloudProvider();
    debugPrint('[ProviderRouter] 雲端 fallback = $_cachedCloudProvider');
    // [教練 Agent 2026-07-22] 也檢測本地 server 是否已在運行
    await _probeLocalServer();
  }

  /// 偵測本地 server 是否在跑（HTTP health check）
  Future<void> _probeLocalServer() async {
    try {
      final endpoint = await StorageService.getLocalModelEndpoint() ??
          'http://127.0.0.1:18789';
      // 用一個超短的 timeout 避免阻塞
      final result = await _httpGet('$endpoint/health').timeout(
        const Duration(seconds: 2),
      );
      _localServerAvailable = (result == '{"status":"ok"}');
    } catch (_) {
      _localServerAvailable = false;
    }
    debugPrint('[ProviderRouter] localServerAvailable = $_localServerAvailable (probed)');
  }

  /// 輕量 HTTP GET（不依賴 dio）
  Future<String> _httpGet(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return body;
    } finally {
      client.close();
    }
  }

  /// 路由判斷——根據意圖模式決定走本地或雲端
  Future<RoutedProvider> route(IntentSpine intentSpine) async {
    // [教練 Agent 2026-07-22] 每次路由前 probe 本地 server
    await _probeLocalServer();

    final cloudProvider = _cachedCloudProvider ?? await _detectCloudProvider();
    final hasCloud = cloudProvider != null;
    final hasLocal = _localServerAvailable;

    // 安全閥 1：MemoryGuard 紅燈 → 强制雲端（本地 server 可能已被殺）
    if (MemoryGuardService.instance.currentLevel == MemoryGuardLevel.red ||
        MemoryGuardService.instance.currentLevel == MemoryGuardLevel.critical) {
      if (hasCloud) {
        return _setAsync(RoutedTarget.cloud, cloudProvider!,
            'MemoryGuard 紅燈/危險——緊急切雲端');
      }
      if (hasLocal) {
        return _setAsync(RoutedTarget.local, 'local', 'MemoryGuard 警告但無雲端可用');
      }
      // [教練 Agent 2026-07-30] 不再硬編碼 'glm'——selectBestCloud 已選過，null 就真的沒有
      return _setAsync(RoutedTarget.cloud, cloudProvider ?? 'unknown',
          'MemoryGuard 警告，無可用 provider，嘗試雲端');
    }

    // 安全閥 2：本地 server 沒跑 → 雲端
    if (!hasLocal && hasCloud) {
      return _setAsync(RoutedTarget.cloud, cloudProvider!,
          '本地 server 未運行——走雲端');
    }

    // 安全閥 3：沒有雲端 token → 本地（即使意圖是雲端）
    if (!hasCloud && hasLocal) {
      return _setAsync(RoutedTarget.local, 'local',
          '無雲端 token——走本地（意圖：${intentSpine.mode.name}）');
    }

    // 安全閥 4：都沒有 → 嘗試雲端（讓 ApiService 報錯，使用者會看到）
    if (!hasCloud && !hasLocal) {
      // [教練 Agent 2026-07-30] 不再硬編碼 'glm'——沒有可用 provider 時用 'unknown'
      return _setAsync(RoutedTarget.cloud, 'unknown',
          '無可用 provider——嘗試雲端（會報錯）');
    }

    // [教練 Agent 2026-07-29] 使用者明確選了外部 provider——尊重選擇
    // 之前：即使使用者選了 glm/openai/kimi，Router 也會因為意圖是 casual/簡單 clarify
    //   就偷偷降級到本地模型，外部 API 根本沒被呼叫。
    // 現在：只有「自動模式」(provider == 'local' 或沒設) 才允許 Router 自己判斷；
    //   使用者明確選了非 local 的 provider 時，一律走使用者選的雲端。
    final storedProvider = await StorageService.getProvider();
    final userExplicitlyPickedCloud = storedProvider != null &&
        storedProvider.isNotEmpty &&
        storedProvider != 'local' &&
        hasCloud &&
        cloudProvider == storedProvider;
    if (userExplicitlyPickedCloud) {
      return _setAsync(RoutedTarget.cloud, cloudProvider!,
          '使用者已選 $cloudProvider——尊重選擇（意圖：${intentSpine.mode.name}）');
    }

    // 自動模式——根據 IntentSpineMode 決定本地或雲端
    final mode = intentSpine.mode;
    final shouldUseCloud = switch (mode) {
      IntentSpineMode.execute => true,
      IntentSpineMode.project => true,
      IntentSpineMode.assetReuse => true,
      IntentSpineMode.capabilitySetup => true,
      IntentSpineMode.analyze => _isComplexClarify(intentSpine),
      IntentSpineMode.clarify => _isComplexClarify(intentSpine),
      IntentSpineMode.casual => false,
    };

    if (shouldUseCloud && hasCloud) {
      return _setAsync(RoutedTarget.cloud, cloudProvider!,
          '意圖 ${mode.name} → 雲端（重算力）');
    }

    // 本地路徑或雲端意圖但沒雲端
    return _setAsync(RoutedTarget.local, 'local',
        '意圖 ${mode.name} → 本地（輕量）');
  }

  /// 判斷 clarify/analyze 是否太複雜，需要走雲端
  ///
  /// 簡單追問走本地（快、省錢）：
  ///   - 訊息短（< 30 字）
  ///   - 信號少（≤ 2 個）
  ///   - 沒有 clarificationOptions（不需要多選項深度分析）
  ///
  /// 複雜釐清走雲端（需要深度推理）：
  ///   - 訊息長（≥ 30 字）— 可能涉及多個面向
  ///   - 信號多（> 2 個）— 多重模糊度需要強模型拆解
  ///   - 有 clarificationOptions — 需要生成結構化選項
  bool _isComplexClarify(IntentSpine intentSpine) {
    // 有 clarificationOptions → 複雜，走雲端
    if (intentSpine.clarificationOptions.isNotEmpty) return true;

    // 信號多 → 複雜
    if (intentSpine.signals.length > 2) return true;

    // 訊息長 → 複雜
    if (intentSpine.rawText.length >= 30) return true;

    // 簡單追問 → 本地
    return false;
  }

  Future<RoutedProvider> _setAsync(
    RoutedTarget target,
    String providerId,
    String reason,
  ) async {
    final r = RoutedProvider(
      target: target,
      providerId: providerId,
      reason: reason,
    );
    _current = r;
    debugPrint('[ProviderRouter] ${r.target.name} ($providerId) — $reason');
    // [教練 Agent 2026-07-29] 修復：不再呼叫 saveProvider / saveGatewayUrl 覆蓋使用者選的 provider
    // 只在記憶體中記住路由結果，由 ApiService 讀取 routedBaseUrl 使用
    if (target == RoutedTarget.cloud) {
      // [教練 Agent 2026-07-30] 改用 ProviderRegistry.baseUrlOf() 取代 _cloudBaseUrl()
      _routedBaseUrl = ProviderRegistry.baseUrlOf(providerId);
    } else if (target == RoutedTarget.local) {
      // 本地路由——讀取本地 server endpoint
      final localUrl = await StorageService.getLocalModelEndpoint();
      _routedBaseUrl = (localUrl != null && localUrl.isNotEmpty)
          ? localUrl
          : 'http://127.0.0.1:18789';
    }
    return r;
  }

  /// 取得當前路由的 provider ID（給 native_agent_loop 用）
  Future<String> get effectiveProviderId async {
    if (_current != null) return _current!.providerId;
    // fallback：讀 StorageService
    // [教練 Agent 2026-07-30] 不再硬編碼 'glm'——沒有設定就回 'unknown'
    return await StorageService.getProvider() ?? 'unknown';
  }

  /// 偵測可用的雲端 provider
  ///
  /// [教練 Agent 2026-07-30] 重構——改用 ProviderRegistry.instance.selectBestCloud()
  /// 舊邏輯：寫死品牌列表 ['glm', 'minimax', 'openai', 'kimi', 'anthropic'] 按順序檢查 token
  /// 新邏輯：動態探測 + 按 Tier 排序，選最強大腦
  Future<String?> _detectCloudProvider() async {
    // 使用者明確設定了 provider → 尊重選擇
    final stored = await StorageService.getProvider() ?? '';
    // [教練 Agent 2026-07-30] 'default' = 預設選型——不直接用，走 route(null)
    if (stored == 'default') {
      final best = await ProviderRegistry.instance.selectBestCloud();
      return best?.providerId;
    }
    if (stored != 'local' && stored != 'default' && stored.isNotEmpty) {
      final token = await StorageService.getToken(provider: stored);
      if (token != null && token.isNotEmpty) return stored;
    }
    // 沒有明確選擇 → 動態選最強大腦
    final best = await ProviderRegistry.instance.selectBestCloud();
    return best?.providerId;
  }

  /// [教練 Agent 2026-07-30] 預設選型——解析 'default' 為實際 provider+model
  ///
  /// 解析優先序：
  /// 1. 有 active CustomRoutingPolicy → 用 policy 指定的 provider（policy 的 overrides 可能含 tier 升降）
  /// 2. 沒有 policy → ProviderRegistry.selectBestCloud()（Tier 最高的可用 provider）
  /// 3. 沒有雲端 → 本地模型
  ///
  /// 回傳 RoutedProvider，呼叫端用它來 setCurrent()
  Future<RoutedProvider> resolveDefault() async {
    // [T7④ 2026-10-16 編織線] localOnly 模式——永不回雲端（M6 斷網血管）
    if (await StorageService.getLocalOnly()) {
      return _setAsync(RoutedTarget.local, 'local', 'localOnly 模式——斷網可用優先，禁上雲');
    }
    // 1. 查 active custom policies
    final store = ProviderProfileStore.instance;
    await store.initialize();
    final allPolicies = await store.getAllPolicies();
    final activePolicies = allPolicies.where((p) => p.isActive).toList();

    if (activePolicies.isNotEmpty) {
      // 選 tier 最高的 policy 對應的 provider
      // 先取每個 policy 的 provider，查 profile tier，選 tier 最低（=最高能力）的
      String? bestProvider;
      String? bestModel;
      ProviderTier bestTier = ProviderTier.tier3;
      for (final policy in activePolicies) {
        final profile = await store.getProfile(policy.provider, policy.model ?? '');
        final tierOverride = policy.overrides['tier'] as String?;
        final effectiveTier = tierOverride != null
            ? _tierFromString(tierOverride)
            : profile.tier;
        if (effectiveTier.index < bestTier.index ||
            (effectiveTier == bestTier && bestProvider == null)) {
          bestTier = effectiveTier;
          bestProvider = policy.provider;
          bestModel = policy.model;
        }
      }
      if (bestProvider != null) {
        final hasToken = await StorageService.getToken(provider: bestProvider) != null;
        if (hasToken) {
          return _setAsync(RoutedTarget.cloud, bestProvider,
              '預設選型：自訂原則 $bestProvider (tier ${bestTier.name})');
        }
      }
    }

    // 2. 沒有 active policy → 動態選最強大腦
    final best = await ProviderRegistry.instance.selectBestCloud();
    if (best != null) {
      return _setAsync(RoutedTarget.cloud, best.providerId,
          '預設選型：自動選擇 ${best.providerId} (tier ${best.tier.name})');
    }

    // 3. 沒有雲端 → 本地
    return _setAsync(RoutedTarget.local, 'local',
        '預設選型：無雲端可用，走本地');
  }

  ProviderTier _tierFromString(String s) {
    switch (s) {
      case 'tier1': return ProviderTier.tier1;
      case 'tier2': return ProviderTier.tier2;
      default: return ProviderTier.tier3;
    }
  }
}
