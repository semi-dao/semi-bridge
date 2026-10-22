import 'package:flutter/foundation.dart';
import '../models/bridge_action.dart';
import 'bridge_adapters/bridge_action_adapter.dart';
import 'bridge_adapters/bridge_adapter_registry.dart';
import 'storage_service.dart';

class CapabilityRoute {
  final BridgeActionAdapter? adapter;
  final String? provider;
  final List<String> candidateProviders;
  final String reason;

  const CapabilityRoute({
    required this.adapter,
    required this.provider,
    required this.candidateProviders,
    required this.reason,
  });

  bool get hasAdapter => adapter != null;
}

class CapabilityRouter {
  CapabilityRouter({required BridgeAdapterRegistry registry})
    : _registry = registry;

  final BridgeAdapterRegistry _registry;

  Future<CapabilityRoute> route(BridgeAction action) async {
    if (action.provider != null && action.provider!.trim().isNotEmpty) {
      final requested = action.provider!.trim().toLowerCase();
      final adapter = _registry.findAdapter(action, requested);
      return CapabilityRoute(
        adapter: adapter,
        provider: requested,
        candidateProviders: [requested],
        reason: adapter == null
            ? 'requested_provider_unavailable'
            : 'requested_provider',
      );
    }

    // [Blue 令 2026-10-20] 能力級預設——金鑰匙能力卡勾選的「預設服務」
    // 優先於 current provider。map key = 能力 id（image_generation 等），
    // value = 服務 id（minimax_image / openai_image 等）。adapter id 與
    // 服務 id 不同名時嘗試前綴對映（minimax_image → minimax）。
    final capKey = switch (action.type) {
      BridgeActionType.generateImage => 'image_generation',
      BridgeActionType.generateAnimation => 'image_generation',
      BridgeActionType.generateVideo => 'video_generation',
      BridgeActionType.generateMusic => 'music_generation',
      BridgeActionType.vision => 'image_understanding',
      BridgeActionType.browse => 'web_search',
      BridgeActionType.document => 'text_reasoning',
      BridgeActionType.desktopFiles => 'text_reasoning',
      BridgeActionType.unknown => null,
    };
    if (capKey != null) {
      final preferred = await StorageService.getRoleProvider(capKey);
      if (preferred != null && preferred.trim().isNotEmpty) {
        // 服務 id（minimax_image）→ adapter id（minimax）前綴對映：
        // 底線前段 = provider 名。直接同名也試（保險）。
        var providerId = preferred.trim().toLowerCase();
        var adapter = _registry.findAdapter(action, providerId);
        adapter ??= _registry.findAdapter(
            action, providerId.split('_').first);
        if (adapter != null && await _isProviderReady(adapter.id)) {
          return CapabilityRoute(
            adapter: adapter,
            provider: adapter.id,
            candidateProviders: [adapter.id],
            reason: 'capability_default（能力卡預設 $preferred）',
          );
        }
      }
    }

    final currentProvider = (await StorageService.getProvider() ?? 'kimi')
        .trim()
        .toLowerCase();
    final currentAdapter = _registry.findAdapter(action, currentProvider);
    if (currentAdapter != null && await _isProviderReady(currentAdapter.id)) {
      return CapabilityRoute(
        adapter: currentAdapter,
        provider: currentAdapter.id,
        candidateProviders: [currentAdapter.id],
        reason: 'current_provider',
      );
    }

    final candidates = _registry.adaptersFor(action.type);
    final candidateProviders = candidates.map((adapter) => adapter.id).toList();
    for (final adapter in candidates) {
      if (await _isProviderReady(adapter.id)) {
        return CapabilityRoute(
          adapter: adapter,
          provider: adapter.id,
          candidateProviders: candidateProviders,
          reason: 'capability_provider',
        );
      }
    }

    final fallback = currentAdapter ?? candidates.firstOrNull;
    return CapabilityRoute(
      adapter: fallback,
      provider: fallback?.id ?? currentProvider,
      candidateProviders: candidateProviders,
      reason: fallback == null ? 'no_adapter' : 'provider_not_configured',
    );
  }

  Future<bool> _isProviderReady(String provider) async {
    if (provider == 'local_document') return true;
    if (provider == 'local_desktop_files') return true;
    final token = await StorageService.getToken(provider: provider);
    var ready = token != null && token.trim().isNotEmpty;
    // [小葵 2026-09-24 Blue 抓包①] 金鑰匙原則——衍生 provider 共用主帳號 key：
    // minimax-tts 的 token 實際存在 api_token_v2_minimax（adapter execute
    // 也是讀 minimax）。key 存在但 router 查錯 key 名 → 永遠 not ready →
    // TTS 全落 Kokoro（聲音不是小葵）。
    if (!ready && provider.contains('-tts')) {
      final baseProvider = provider.replaceAll('-tts', '');
      final baseToken = await StorageService.getToken(provider: baseProvider);
      ready = baseToken != null && baseToken.trim().isNotEmpty;
    }
    debugPrint('[CapabilityRouter] _isProviderReady($provider) = $ready');
    return ready;
  }
}
