// AgentModelSelector — 聊天輸入區的模型快速切換器
//
// 顯示有 API Key 的 provider + 本地模型（如果在跑），
// 讓使用者一鍵切換 Agent 主模型，不用進設定頁。
//
// [教練 Agent 2026-07-30] 重構——改用 ProviderRegistry 取代硬編碼的
// _allProviderInfos / _defaultGatewayUrl / _findProviderInfo。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../services/local_model_runtime_service.dart';
import '../../services/storage_service.dart';
import '../../services/provider_registry.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import 'data_path_badge.dart';
import '../../services/sovereignty/data_path_gate.dart' show DataPathGrade;

/// 探測本地模型是否在跑
/// [教練 Agent 2026-08-05] 改用 LocalModelRuntimeService 讀 runtime state，
/// 不再寫死 127.0.0.1:18789 — 改成讀 state.serverUrl（runtime 實際回報的 port）
/// 之前寫死 18789 會在 runtime 換 port（如 testLocalModel 用 18799）時誤判 local 沒跑
/// [教練 Agent 2026-08-13] 縮短 timeout 從 2s → 800ms，避免初始載入卡住 UI
Future<bool> _isLocalModelRunning() async {
  try {
    final state = await LocalModelRuntimeService().inspectBridgeRuntime();
    if (!state.running || state.serverUrl == null) {
      return false;
    }
    final endpoint = state.serverUrl!;
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(milliseconds: 800),
      receiveTimeout: const Duration(milliseconds: 800),
    ));
    final response = await dio.get('$endpoint/v1/models');
    dio.close();
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}

// ═══════════════════════════════════════════════════
// AgentModelSelector
// ═══════════════════════════════════════════════════

class AgentModelSelector extends StatefulWidget {
  /// 切換 provider 後的回呼（通常用來通知 ChatController 重新載入）
  final VoidCallback? onProviderChanged;

  /// [教練 Agent 2026-08-18 使用者 抓包] 浮動面板模式——
  /// 隨身小幫手是可拖曳 overlay，PopupMenuButton 是 route-based，
  /// 拖走後選單孤兒化停在原地、barrier 也攔不到按鈕（使用者 實測疊了四個收不回來）。
  /// floating 模式改用 OverlayPortal + LayerLink：選單錨定按鈕跟著面板走、
  /// 點外面就關，不留孤兒。
  final bool floating;

  const AgentModelSelector(
      {super.key, this.onProviderChanged, this.floating = false});

  @override
  State<AgentModelSelector> createState() => _AgentModelSelectorState();
}

class _AgentModelSelectorState extends State<AgentModelSelector> {
  /// 可用的 provider 列表（有 token 或 local 在跑）
  /// [教練 Agent 2026-07-30] 改用 ProviderMeta 取代 _ProviderDisplayInfo
  List<ProviderMeta> _availableProviders = const [];

  /// 當前選中的 provider
  String? _currentProvider;

  /// 本地模型是否在跑
  bool _localRunning = false;

  /// 是否正在載入
  bool _isLoading = true;

  // [教練 Agent 2026-08-18] floating 模式用
  final _layerLink = LayerLink();
  final _overlayPortalController = OverlayPortalController();
  bool _menuOpen = false;

  // [教練 Agent 2026-08-13] Static 快取——避免 widget 重建時重新偵測
  // AgentModelSelector 在 chat_screen 裡會因為 Column 條件 widget 導致重建
  // 重建會觸發 initState → _detectProviders → _isLocalModelRunning (60s timeout)
  // 用 static 快取讓重建直接跳過偵測
  static List<ProviderMeta>? _cachedProviders;
  static String? _cachedCurrentProvider;
  static bool _localProbeDone = false;
  static bool _localProbeResult = false;

  @override
  void initState() {
    super.initState();
    _detectProviders();
  }

  /// 偵測可用 provider 列表
  /// [教練 Agent 2026-08-13] 徹底重寫——分兩階段：
  /// 階段 1（同步閃電）：用 static 快取或雲端 token 偵測，秒顯示按鈕
  /// 階段 2（背景慢）：local model 探測跑完後如果有就加進去
  Future<void> _detectProviders() async {
    // 檢查 static 快取——widget 重建時直接用
    if (_cachedProviders != null) {
      if (mounted) {
        setState(() {
          _availableProviders = _cachedProviders!;
          _currentProvider = _cachedCurrentProvider ?? 'default';
          // [教練 Agent 2026-08-18 使用者 抓包] 還原 _localRunning——
          // 之前只還原清單不還原這個，新實例（隨身小幫手）永遠掛誤導性 ⚠️
          _localRunning = _localProbeDone && _localProbeResult;
          _isLoading = false;
        });
      }
      // 如果 local 探測還沒跑完，背景繼續跑
      if (!_localProbeDone) {
        _probeLocalInBackground();
      }
      return;
    }

    // 階段 1：雲端 token 偵測（快速，<100ms）
    try {
      final List<ProviderMeta> available = [];
      final allMetas = ProviderRegistry.instance.allMetas();

      for (final meta in allMetas) {
        if (meta.id == 'local') continue;
        try {
          final token = await StorageService.getToken(provider: meta.id);
          if (token != null && token.trim().isNotEmpty) {
            available.add(meta);
          }
        } catch (_) {}
      }

      String? currentProvider;
      try {
        currentProvider = await StorageService.getProvider();
      } catch (_) {
        currentProvider = 'default';
      }

      final defaultMeta = ProviderMeta(
        id: 'default',
        baseUrl: '',
        displayName: '預設',
        emoji: '✨',
      );

      final providers = [defaultMeta, ...available];

      // 快取
      _cachedProviders = providers;
      _cachedCurrentProvider = currentProvider ?? 'default';

      if (mounted) {
        setState(() {
          _availableProviders = providers;
          _currentProvider = currentProvider ?? 'default';
          _isLoading = false;
        });
      }

      // 階段 2：背景偵測 local model（不卡 UI）
      _probeLocalInBackground();
    } catch (e) {
      debugPrint('[AgentModelSelector] _detectProviders failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _availableProviders = const [];
        });
      }
    }
  }

  /// [教練 Agent 2026-08-13] 背景 local model 偵測——跑完後如果有就加進去
  /// 用 static flag 確保全域只跑一次
  Future<void> _probeLocalInBackground() async {
    if (_localProbeDone) return;

    bool localRunning = false;
    try {
      localRunning = await _isLocalModelRunning();
    } catch (_) {
      localRunning = false;
    }

    _localProbeDone = true;
    _localProbeResult = localRunning;

    if (localRunning && _cachedProviders != null) {
      final localMeta = ProviderRegistry.metaOf('local');
      if (localMeta != null && !_cachedProviders!.any((p) => p.id == 'local')) {
        _cachedProviders = [..._cachedProviders!, localMeta];
        if (mounted) {
          setState(() {
            _availableProviders = _cachedProviders!;
            _localRunning = true;
          });
        }
      }
    }
  }

  /// [教練 Agent 2026-07-30] 選擇「預設」——Agent 依預設選型原則動態選模型
  Future<void> _selectDefault() async {
    await StorageService.saveProvider('default');
    _cachedCurrentProvider = 'default';
    if (mounted) {
      setState(() {
        _currentProvider = 'default';
      });
      widget.onProviderChanged?.call();
    }
  }

  /// 切換 provider
  /// [教練 Agent 2026-07-30] 用 ProviderRegistry.baseUrlOf() 取代 _defaultGatewayUrl()
  /// [收斂任務 3] 改用 saveProviderConfig 自動同步 gateway_url
  Future<void> _selectProvider(String provider) async {
    if (provider == _currentProvider) return;

    // 如果選 local 但沒在跑，顯示警告但仍允許切換
    if (provider == 'local' && !_localRunning) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('⚠️ 本地模型似乎沒在跑（本地推理服務無回應）'),
            backgroundColor: BridgeDSColors.of(context).accentRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }

    // [收斂任務 3] 使用便捷方法同時更新 provider 和 gateway_url
    String? gatewayUrl;
    if (provider != 'default') {
      gatewayUrl = ProviderRegistry.baseUrlOf(provider);
    }
    await StorageService.saveProviderConfig(provider, gatewayUrl);
    _cachedCurrentProvider = provider;

    if (mounted) {
      setState(() {
        _currentProvider = provider;
      });
      // 通知外部重新載入
      widget.onProviderChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      // 載入中不顯示
      return const SizedBox.shrink();
    }

    // 只有 0 或 1 個可用 provider → 不顯示選擇器
    if (_availableProviders.length <= 1) {
      return const SizedBox.shrink();
    }

    // [教練 Agent 2026-07-30] 用 ProviderMeta 取代 _findProviderInfo
    // 「預設」模式：Agent 依預設選型原則動態選模型
    final isDefault = _currentProvider == 'default' || _currentProvider == null;
    final meta = ProviderRegistry.metaOf(_currentProvider ?? '');
    final displayEmoji = isDefault ? '✨' : (meta?.emoji ?? '❓');
    final displayLabel = isDefault ? '預設' : (meta?.displayName ?? _currentProvider ?? '未知');

    // [教練 Agent 2026-08-18] floating 面板（隨身小幫手）用錨定選單
    if (widget.floating) {
      return _buildFloatingButton(context, displayEmoji, displayLabel);
    }
    return _buildCompactButton(context, displayEmoji, displayLabel);
  }

  /// [教練 Agent 2026-08-18] 浮動面板版按鈕——OverlayPortal + LayerLink 錨定
  Widget _buildFloatingButton(BuildContext context, String emoji, String label) {
    final colors = BridgeDSColors.of(context);
    return OverlayPortal(
      controller: _overlayPortalController,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: TapRegion(
          groupId: 'qa-model-menu',
          onTapOutside: (_) => _closeFloatingMenu(),
          child: GestureDetector(
            onTap: () {
              if (_menuOpen) {
                _closeFloatingMenu();
              } else {
                _openFloatingMenu();
              }
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji,
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _menuOpen ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      overlayChildBuilder: (BuildContext ctx) {
        return Positioned(
          width: 240,
          child: CompositedTransformFollower(
            link: _layerLink,
            // [Blue 抓包 2026-10-06 問題2] 懸浮窗版選單改「向上開」——
            // 選擇器貼在視窗底部輸入列，向下開會掉出視窗外被裁掉。
            // 對話面板的 chat 版維持向下（周圍有空間），這裡只改懸浮窗
            // 共用的 floating 版行為。
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.bottomLeft,
            showWhenUnlinked: false,
            child: TapRegion(
              groupId: 'qa-model-menu',
              onTapOutside: (_) => _closeFloatingMenu(),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(10),
                color: colors.surfaceElevated,
                child: _buildMenuItems(ctx, colors),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openFloatingMenu() {
    _overlayPortalController.show();
    if (mounted) setState(() => _menuOpen = true);
  }

  void _closeFloatingMenu() {
    if (!mounted) return;
    _overlayPortalController.hide();
    setState(() => _menuOpen = false);
  }

  /// 選單項目（floating 版共用）
  Widget _buildMenuItems(BuildContext context, BridgeDSColors colors) {
    final isDefault =
        _currentProvider == 'default' || _currentProvider == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _menuItem(context, colors, '⚡', '預設', 'default', isDefault),
        const PopupMenuDivider(),
        ..._availableProviders.map((meta) {
          final isSelected = meta.id == _currentProvider;
          return _menuItem(
            context, colors, meta.emoji, meta.displayName, meta.id, isSelected,
            warn: meta.id == 'local' && !_localRunning,
          );
        }),
      ],
    );
  }

  Widget _menuItem(
    BuildContext context,
    BridgeDSColors colors,
    String emoji,
    String label,
    String value,
    bool isSelected, {
    bool warn = false,
  }) {
    return InkWell(
      onTap: () {
        _closeFloatingMenu();
        if (value == 'default') {
          _selectDefault();
        } else {
          _selectProvider(value);
        }
      },
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Text(emoji,
                style: TierStyle.of(context, Tier.cardTitle)
                    .toTextStyle()),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected
                      ? colors.accentBlue
                      : colors.textPrimary,
                ),
              ),
            ),
            if (warn)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.warning_amber_rounded,
                    size: 14, color: colors.accentRed),
              ),
            if (isSelected)
              Icon(Icons.check, size: 14, color: colors.accentBlue),
          ],
        ),
      ),
    );
  }

  /// 緊湊的下拉按鈕
  Widget _buildCompactButton(
    BuildContext context,
    String emoji,
    String label,
  ) {
    final colors = BridgeDSColors.of(context);
    final isDefault = _currentProvider == 'default' || _currentProvider == null;

    return PopupMenuButton<String>(
      tooltip: '切換 Agent 模型',
      onSelected: (value) {
        if (value == 'default') {
          _selectDefault();
        } else {
          _selectProvider(value);
        }
      },
      offset: const Offset(0, -8),
      constraints: BoxConstraints(
        minWidth: 180,
        maxWidth: 260,
      ),
      itemBuilder: (context) => [
        // [教練 Agent 2026-07-30] 「預設」選項——動態路由
        PopupMenuItem<String>(
          value: 'default',
          child: Row(
            children: [
              Text('⚡', style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '預設',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(// [教練 Agent 2026-08-03] 升級 13→14
                    fontWeight: isDefault ? FontWeight.w700 : FontWeight.w400,
                    color: isDefault ? colors.accentBlue : colors.textPrimary,),
                ),
              ),
              if (isDefault)
                Icon(Icons.check, size: 14, color: colors.accentBlue),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // 以下為具體 provider
        ..._availableProviders.map((meta) {
        final isSelected = meta.id == _currentProvider;
        return PopupMenuItem<String>(
          value: meta.id,
          child: Row(
            children: [
              Text(meta.emoji, style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  meta.displayName,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(// [教練 Agent 2026-08-03] 升級 13→14
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w400,
                    color: isSelected
                        ? colors.accentBlue
                        : colors.textPrimary,),
                ),
              ),
              if (isSelected)
                Icon(Icons.check, size: 14, color: colors.accentBlue),
              // [資料主權 P0-c] 資料路徑徽章——選模型時看見資料去哪
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: DataPathBadge(
                    grade: dataPathGradeForProvider(meta.id)),
              ),
              if (meta.id == 'local' && !_localRunning)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: colors.accentRed,
                  ),
                ),
            ],
          ),
        );
      }),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
            const SizedBox(width: 4),
            Text(
              label,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(// [教練 Agent 2026-08-03] 升級 11→14
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,),
            ),
            const SizedBox(width: 2),
            // [資料主權 P0-c] 按鈕本體也帶徽章（非 compact，顯示「本地/直連」短語）
            DataPathBadge(
                grade: _currentProvider == null
                    ? DataPathGrade.yellow
                    : dataPathGradeForProvider(
                        _currentProvider == 'default' ? 'default' : _currentProvider!),
                compact: false),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
