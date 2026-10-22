// 主腦 API 設定卡 — 自包含 StatefulWidget
// 從 bridge_desktop_screen.dart 抽出，用於 Capability Center
//
// 功能：
// - Provider 選擇 (kimi, openai, glm, minimax, claude, gemini, local)
// - Gateway URL 輸入
// - API Token 輸入（密碼顯示切換）
// - 計費模式切換（支援多模式的 provider）
// - 測試連線 → 顯示可用模型
// - 儲存設定 → 鎖定 provider
// - 解除鎖定 → 重新編輯

import 'package:flutter/material.dart';

import '../../services/storage_service.dart';
import '../../services/api_service.dart';
import '../../services/billing_modes.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../bridge_desktop_widgets.dart';

class BrainApiConfigCard extends StatefulWidget {
  const BrainApiConfigCard({super.key});

  @override
  State<BrainApiConfigCard> createState() => _BrainApiConfigCardState();
}

class _BrainApiConfigCardState extends State<BrainApiConfigCard> {
  // Controller
  final _apiUrlController = TextEditingController();
  final _apiTokenController = TextEditingController();

  // State
  String _apiProvider = 'kimi';
  bool _obscureToken = true;
  bool _apiTesting = false;
  bool _apiSaving = false;
  // [教練 Agent 2026-08-17 使用者回饋] 儲存成功視覺回饋——按鈕變綠打勾 1.5 秒
  bool _saveJustSucceeded = false;
  String? _selectedApiModel;
  String _selectedBillingMode = 'payg';

  // Per-provider state
  final Map<String, bool> _providerSaved = {};
  final Map<String, bool> _providerTested = {};
  final Map<String, List<String>> _providerTestModels = {};
  final Map<String, String?> _providerTestError = {};

  // [教練 Agent 2026-08-17 使用者 微調] 模型清單折疊——
  // OpenAI 型號上百顆，常用優先、長尾折疊
  final Map<String, bool> _providerModelsExpanded = {};
  bool get _modelsExpanded => _providerModelsExpanded[_apiProvider] ?? false;

  // Computed getters
  List<String>? get _apiTestModels => _providerTestModels[_apiProvider];
  String? get _apiTestError => _providerTestError[_apiProvider];
  bool get _apiSaved => _providerSaved[_apiProvider] ?? false;

  /// [教練 Agent 2026-08-17 使用者 微調] 常用模型偵測——
  /// 對話/coding 常用 + 影像/影片生成常用優先列出，長尾折疊。
  /// 泛用規則（各家 provider 通吃）：
  /// - 排除明確的非任務型：embedding / moderation / tts / transcribe /
  ///   whisper / realtime / audio / diarize（這些是工具型，不是大腦）
  /// - 排除帶日期快照版（-2024-04-09 之類）——同型號留主條目就好
  static bool _isFeaturedModel(String m) {
    final lower = m.toLowerCase();
    // 工具型 / 語音型 / 舊時代型號 → 非常用
    if (lower.contains('embedding') ||
        lower.contains('moderation') ||
        lower.contains('tts') ||
        lower.contains('transcribe') ||
        lower.contains('whisper') ||
        lower.contains('realtime') ||
        lower.contains('audio') ||
        lower.contains('diarize') ||
        lower.contains('davinci') ||
        lower.contains('babbage') ||
        lower.contains('instruct')) {
      return false;
    }
    // 日期快照版（-YYYY-MM-DD 結尾）→ 折疊
    if (RegExp(r'-\d{4}-\d{2}-\d{2}$').hasMatch(lower)) return false;
    return true;
  }

  // Constants
  static const _providers = [
    'kimi',
    'openai',
    'glm',
    'minimax',
    'claude',
    'gemini',
    'local',
    'ollama', // [教練 Agent 2026-08-21] Ollama——全本地主權（DGX Spark 計畫）
  ];

  @override
  void initState() {
    super.initState();
    _loadApiConfig();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _apiTokenController.dispose();
    super.dispose();
  }

  /// [Blue 令 2026-10-20] 用途角色映射（活預設）——
  /// 每個用途角色（chat/coding/reasoning/image_gen）可指定一把鑰匙。
  /// 「預設」模式下路由按意圖角色找鑰匙；沒設的角色走原本邏輯。
  static const _roleLabels = {
    'chat': '主要對話',
    'coding': '主要編程',
    'reasoning': '深度推理',
    // [Blue 令 2026-10-20 #2] image_gen 移除——圖片生成等能力級預設
    // 歸能力卡管（capability_center 每能力 ≥2 開通服務時可選預設服務）。
  };

  Widget _buildRoleMapSection() {
    final ds = BridgeDSColors.of(context);
    return FutureBuilder<Map<String, String>>(
      future: StorageService.getRoleProviderMap(),
      builder: (context, roleSnap) {
        final roleMap = roleSnap.data ?? {};
        // 候選鑰匙＝有 token 的 provider（角色映射只對有鑰匙的有意義）
        return FutureBuilder<List<String>>(
          future: _lockedProviders(),
          builder: (context, lockSnap) {
            final locked = lockSnap.data ?? [];
            if (locked.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('用途預設（各角色用哪把鑰匙）',
                    style: ds.small.copyWith(
                        fontSize: 14, color: ds.textMuted)),
                const SizedBox(height: 4),
                SelectableText(
                    '選「預設」模式時，路由會按用途找對應鑰匙；沒設的角色走本地優先＋自動雲端。',
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(color: ds.textTertiary)),
                const SizedBox(height: 8),
                for (final entry in _roleLabels.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 90,
                          child: Text(entry.value,
                              style: TierStyle.of(context, Tier.cardCaption)
                                  .toTextStyle()
                                  .copyWith(color: ds.textSecondary)),
                        ),
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: locked.contains(roleMap[entry.key])
                                ? roleMap[entry.key]
                                : '',
                            items: [
                              const DropdownMenuItem(
                                  value: '',
                                  child: Text('自動（未指定）',
                                      style: TextStyle(fontSize: 13))),
                              for (final p in locked)
                                DropdownMenuItem(
                                    value: p,
                                    child: Text(p,
                                        style:
                                            const TextStyle(fontSize: 13))),
                            ],
                            onChanged: (v) async {
                              await StorageService.saveRoleProvider(
                                  entry.key, v ?? '');
                              if (mounted) setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// 掃出有 token（已鎖定）的 provider 清單
  Future<List<String>> _lockedProviders() async {
    final result = <String>[];
    for (final p in _providers) {
      if (p == 'local' || p == 'ollama') continue;
      try {
        final token = await StorageService.getToken(provider: p);
        if (token != null && token.trim().isNotEmpty) result.add(p);
      } catch (_) {}
    }
    return result;
  }

  /// 載入 API 設定
  Future<void> _loadApiConfig() async {
    debugPrint('[BrainApiConfigCard] _loadApiConfig 開始');
    String? url;
    String? provider;
    String? token;
    try {
      url = await StorageService.getGatewayUrl();
      provider = await StorageService.getProvider() ?? 'kimi';
      token = await StorageService.getToken(provider: provider);
      debugPrint('[BrainApiConfigCard] 載入成功: provider=$provider, url=$url, token=${token != null ? "${token.length} chars" : "null"}');
    } catch (e) {
      debugPrint('[BrainApiConfigCard] 載入 API 設定失敗: $e');
    }
    final nonNullProvider = provider ?? 'kimi';
    if (mounted) {
      setState(() {
        _apiUrlController.text = url ?? _defaultApiUrl(nonNullProvider);
        _apiProvider = nonNullProvider;
        _apiTokenController.text = token ?? '';
        // 已儲存的 provider 標記為已鎖定
        if (token != null && token.isNotEmpty) {
          _providerSaved[nonNullProvider] = true;
          _providerTested[nonNullProvider] = true;
        }
      });
    }
    // 掃描所有 provider，有 token 的標記為已鎖定
    await _scanAllProviderLockStatus();
    // 載入計費模式
    await _loadBillingMode(_apiProvider);
  }

  /// 掃描所有 provider，有 token 的標記為已鎖定
  Future<void> _scanAllProviderLockStatus() async {
    for (final p in _providers) {
      try {
        final t = await StorageService.getToken(provider: p);
        if (t != null && t.isNotEmpty && mounted) {
          setState(() {
            _providerSaved[p] = true;
            _providerTested[p] = true;
          });
        }
      } catch (_) {}
    }
  }

  /// 載入 billing mode 並更新 URL
  Future<void> _loadBillingMode(String provider) async {
    if (!BillingModes.hasMultipleModes(provider)) {
      _selectedBillingMode = 'payg';
      return;
    }
    _selectedBillingMode = await BillingModes.getSelectedModeId(provider);
    // 用 billing mode 的 base_url 更新輸入框
    final baseUrl = await BillingModes.getBaseUrl(provider);
    if (baseUrl.isNotEmpty && mounted) {
      setState(() {
        _apiUrlController.text = baseUrl;
      });
    }
  }

  /// 取得預設 API URL
  String _defaultApiUrl(String provider) {
    switch (provider) {
      case 'openai':
        return 'https://api.openai.com/v1';
      case 'kimi':
        return 'https://api.moonshot.cn/v1';
      case 'minimax':
        return 'https://api.minimax.io/v1';
      case 'claude':
        return 'https://api.anthropic.com/v1';
      case 'gemini':
        return 'https://generativelanguage.googleapis.com/v1beta/openai';
      case 'glm':
        return 'https://open.bigmodel.cn/api/paas/v4';
      case 'replicate':
        return 'https://api.replicate.com/v1';
      case 'local':
        return 'http://127.0.0.1:18789';
      case 'ollama': // [教練 Agent 2026-08-21] Ollama 預設 port 11434
        return 'http://127.0.0.1:11434';
      default:
        return _apiUrlController.text;
    }
  }

  /// 選擇 API Provider
  Future<void> _selectApiProvider(String provider) async {
    debugPrint('[BrainApiConfigCard] _selectApiProvider: $provider (從 $_apiProvider)');
    final previousProvider = _apiProvider;
    final previousToken = _apiTokenController.text.trim();
    // 只在欄位有值時才存，避免空字串覆蓋已存的 token
    if (previousToken.isNotEmpty) {
      try {
        await StorageService.saveToken(previousToken, provider: previousProvider);
      } catch (e) {
        debugPrint('[BrainApiConfigCard] 儲存前一個 token 失敗: $e');
      }
    }
    // 載入新 provider 的 token
    String? nextToken;
    try {
      nextToken = await StorageService.getToken(provider: provider);
      debugPrint('[BrainApiConfigCard] 載入 $provider token: ${nextToken != null ? "${nextToken.length} chars" : "null"}');
    } catch (e) {
      debugPrint('[BrainApiConfigCard] 載入新 token 失敗: $e');
    }
    // 載入已儲存的 model
    String? storedModel;
    try {
      storedModel = await StorageService.getApiModel(provider: provider);
    } catch (e) {
      debugPrint('[BrainApiConfigCard] 載入 $provider model 失敗: $e');
    }
    // 直接切換，不暫停 listener
    if (mounted) {
      setState(() {
        _apiProvider = provider;
        _apiUrlController.text = _defaultApiUrl(provider);
        _apiTokenController.text = nextToken ?? '';
        _selectedApiModel = storedModel;
        // 切到已有 token 的 provider → 保持鎖定
        // 沒有 token 的 provider → 清除狀態，讓用戶可以測試+儲存
        if (nextToken != null && nextToken.isNotEmpty) {
          _providerSaved[provider] = true;
          _providerTested[provider] = true;
        } else {
          _providerTested.remove(provider);
          _providerSaved.remove(provider);
          _providerTestModels.remove(provider);
          _providerTestError.remove(provider);
        }
      });
    }
    // 載入 billing mode
    await _loadBillingMode(provider);
  }

  /// 儲存 API 設定
  Future<void> _saveApiConfig() async {
    // [教練 Agent 2026-08-21] 本地 runtime 家族（local/ollama）token 可留空——
    // 全本地部署不需要金鑰，URL 即一切。DGX Spark 主權方案。
    final isLocalRuntime =
        _apiProvider == 'local' || _apiProvider == 'ollama';
    if (_apiTokenController.text.trim().isEmpty && !isLocalRuntime) {
      setState(() => _providerTestError[_apiProvider] = '請先填入 API Token。');
      return;
    }
    setState(() => _apiSaving = true);
    try {
      final token = _apiTokenController.text.trim();
      await StorageService.saveGatewayUrl(_apiUrlController.text.trim());
      if (token.isNotEmpty) {
        await StorageService.saveToken(token, provider: _apiProvider);
      } else {
        // 本地 runtime 空 token——寫個佔位確保 provider 被視為已設定
        await StorageService.saveToken('(local)', provider: _apiProvider);
      }
      // 驗證寫回
      final verify = await StorageService.getToken(provider: _apiProvider);
      if (verify == null || verify.trim().isEmpty) {
        throw Exception('Token 寫入後驗證失敗——讀回為空 (provider=$_apiProvider)');
      }
      debugPrint('[BrainApiConfigCard] ✅ _saveApiConfig: $_apiProvider token 已持久化 (len=${verify.length})');
      if (mounted) {
        setState(() {
          _apiSaving = false;
          _providerSaved[_apiProvider] = true;
          // [教練 Agent 2026-08-17 使用者回饋] 儲存成功視覺回饋
          _saveJustSucceeded = true;
        });
        // 1.5 秒後回到正常「儲存」樣態
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            setState(() => _saveJustSucceeded = false);
          }
        });
      }
    } catch (e) {
      debugPrint('[BrainApiConfigCard] ❌ _saveApiConfig 失敗: $e');
      if (mounted) {
        setState(() {
          _apiSaving = false;
          _providerSaved[_apiProvider] = false;
          _saveJustSucceeded = false;
          _providerTestError[_apiProvider] = '儲存失敗：$e';
        });
      }
    }
  }

  /// 測試 API 連線
  Future<void> _testApiConnection() async {
    // [教練 Agent 2026-08-17 使用者 抓包] 空 token 早擋——
    // 之前「先存再測」會把空字串 token 寫進 prefs，覆蓋已存的合法
    // token；而且空 token 進 401，把「測試成功」假象甩給使用者。
    final token = _apiTokenController.text.trim();
    // [教練 Agent 2026-08-21] 本地 runtime 家族（local/ollama）不需要 token——
    // 連線測試靠 HTTP ping，不靠金鑰。DGX Spark 全本地主權方案。
    final isLocalRuntime =
        _apiProvider == 'local' || _apiProvider == 'ollama';
    if (token.isEmpty && !isLocalRuntime) {
      setState(() {
        _apiTesting = false;
        _providerTestError[_apiProvider] = '請先填入 API Token 才能測試連線';
      });
      return;
    }
    setState(() {
      _apiTesting = true;
      _providerTestModels.remove(_apiProvider);
      _providerTestError.remove(_apiProvider);
    });
    try {
      // 套用 billing mode 的 base_url
      if (BillingModes.hasMultipleModes(_apiProvider)) {
        final billingUrl = await BillingModes.getBaseUrl(_apiProvider);
        if (billingUrl.isNotEmpty && mounted) {
          setState(() {
            _apiUrlController.text = billingUrl;
          });
        }
      }
      // [教練 Agent 2026-08-17] 不在測試流程裡寫 prefs——測試只是驗證
      // token 是否有效，沒成功就不該動到 prefs。
      // 之前「先存再測」會覆蓋已存的合法 token。
      final models = await ApiService.testConnectionWith(
        _apiUrlController.text.trim(),
        token,
      );
      // 測試成功後處理模型
      List<String> effectiveModels = models;
      if (effectiveModels.isEmpty) {
        // 某些 provider（如 Claude）不支援 /models，用 fallback
        effectiveModels = ApiService.fallbackModelList(_apiProvider);
      }
      // [教練 Agent 2026-08-17 使用者 指示] 尊重使用者已選的模型——
      // 重新測試只是刷新清單，不把使用者的選擇改掉。
      // 只有在「沒有已存的模型」或「已存模型不在新清單裡（已下架）」
      // 時才自動挑選。
      final stored = await StorageService.getApiModel(provider: _apiProvider);
      final stillAvailable =
          stored != null && effectiveModels.contains(stored);
      if (stillAvailable) {
        _selectedApiModel = stored;
      } else {
        final best = ApiService.pickBestModel(_apiProvider, effectiveModels);
        if (best != null) {
          await StorageService.saveApiModel(best, provider: _apiProvider);
          _selectedApiModel = best;
        }
      }
      if (mounted) {
        setState(() {
          // [教練 Agent 2026-08-17 使用者回饋] Claude 等 provider 不支援 /models
          // → 原始清單是空的，chips 要用 fallback 清單，
          // 否則使用者沒有模型可選
          _providerTestModels[_apiProvider] = effectiveModels;
          _providerTested[_apiProvider] = true;
          _providerTestError.remove(_apiProvider);
          _apiTesting = false;
        });
      }
      debugPrint('[BrainApiConfigCard] API 連線測試成功，${models.length} 個模型');
    } catch (e) {
      if (mounted) {
        setState(() {
          _providerTestError[_apiProvider] = e.toString();
          _apiTesting = false;
        });
      }
      debugPrint('[BrainApiConfigCard] API 連線測試失敗：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasConfig = _apiUrlController.text.trim().isNotEmpty &&
        _apiTokenController.text.trim().isNotEmpty;

    return BridgeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列
          Row(
            children: [
              Icon(Icons.cloud, color: BridgeDSColors.of(context).accentBlue, size: 16),
              SizedBox(width: 8),
              SelectableText('主腦 API 設定',
                  style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
              Spacer(),
              BridgeStatusTag(
                label: hasConfig ? '已設定' : '未設定',
                type: hasConfig
                    ? BridgeTagType.success
                    : BridgeTagType.warn,
              ),
            ],
          ),
          SizedBox(height: BridgeDS.spaceMD),

          // [Blue 令 2026-10-20] 用途角色映射（活預設）——每把鑰匙可掛用途
          _buildRoleMapSection(),
          SizedBox(height: BridgeDS.spaceMD),

          // Provider 選擇
          SelectableText('Provider',
              style: BridgeDSColors.of(context).small.copyWith(
                fontSize: 14,
                color: BridgeDSColors.of(context).textMuted,
              )),
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _providers.map((p) {
              final selected = p == _apiProvider;
              final locked = _providerSaved[p] == true;
              return GestureDetector(
                onTap: () => _selectApiProvider(p),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? BridgeDSColors.of(context).accentBlue
                        : BridgeDSColors.of(context).surfaceHover,
                    borderRadius:
                        BorderRadius.circular(BridgeDS.roundComfortable),
                    border: Border.all(
                      color: locked
                          ? BridgeDSColors.of(context).accentGreen
                          : selected
                              ? BridgeDSColors.of(context).accentBlue
                              : BridgeDSColors.of(context).borderSubtle,
                      width: locked ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (locked) ...[
                        Icon(Icons.lock, size: 12,
                            color: selected
                                ? BridgeDSColors.of(context).canvas
                                : BridgeDSColors.of(context).accentGreen),
                        SizedBox(width: 4),
                      ],
                      Text(
                        p,
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                          color: selected
                              ? BridgeDSColors.of(context).canvas
                              : BridgeDSColors.of(context).textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          SizedBox(height: BridgeDS.spaceMD),

          // Gateway URL 輸入欄
          TextField(
            controller: _apiUrlController,
            style: BridgeDSColors.of(context).code.copyWith(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Gateway URL',
              labelStyle: BridgeDSColors.of(context).small.copyWith(
                fontSize: 14,
                color: BridgeDSColors.of(context).textMuted,
              ),
              hintText: 'https://api.example.com/v1',
              hintStyle: BridgeDSColors.of(context).small.copyWith(
                fontSize: 14,
                color: BridgeDSColors.of(context).textQuaternary,
              ),
              filled: true,
              fillColor: BridgeDSColors.of(context).surface,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(BridgeDS.roundComfortable),
                borderSide: BorderSide(color: BridgeDSColors.of(context).borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(BridgeDS.roundComfortable),
                borderSide: BorderSide(color: BridgeDSColors.of(context).borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(BridgeDS.roundComfortable),
                borderSide: BorderSide(color: BridgeDSColors.of(context).accentBlue),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            ),
          ),
          SizedBox(height: BridgeDS.spaceMD),

          // API Token 輸入欄
          TextField(
            controller: _apiTokenController,
            obscureText: _obscureToken,
            style: BridgeDSColors.of(context).code.copyWith(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'API Token',
              labelStyle: BridgeDSColors.of(context).small.copyWith(
                fontSize: 14,
                color: BridgeDSColors.of(context).textMuted,
              ),
              filled: true,
              fillColor: BridgeDSColors.of(context).surface,
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(BridgeDS.roundComfortable),
                borderSide: BorderSide(color: BridgeDSColors.of(context).borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(BridgeDS.roundComfortable),
                borderSide: BorderSide(color: BridgeDSColors.of(context).borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(BridgeDS.roundComfortable),
                borderSide: BorderSide(color: BridgeDSColors.of(context).accentBlue),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              suffixIcon: Semantics(
                label: _obscureToken ? '顯示密碼' : '隱藏密碼',
                button: true,
                child: IconButton(
                  icon: Icon(
                    _obscureToken
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: BridgeDSColors.of(context).textMuted,
                  ),
                  tooltip: _obscureToken ? '顯示密碼' : '隱藏密碼',
                  onPressed: () {
                    setState(() => _obscureToken = !_obscureToken);
                  },
                ),
              ),
            ),
          ),
          SizedBox(height: BridgeDS.spaceMD),

          // 計費模式 toggle（只有支援多模式的 provider 才顯示）
          if (BillingModes.hasMultipleModes(_apiProvider)) ...[
            SizedBox(height: BridgeDS.spaceMD),
            Padding(
              padding: EdgeInsets.only(left: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    '計費模式',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                      color: BridgeDSColors.of(context).textMuted,
                    ),
                  ),
                  SizedBox(height: 8),
                  // [教練 Agent 2026-08-17 使用者 微調] 按鈕間距放寬——
                  // 計費模式 chips 之間水平 16 / 換行 10，不再擠成一團
                  Wrap(
                    spacing: 16,
                    runSpacing: 10,
                    children: BillingModes.getModes(_apiProvider).map((mode) {
                      final isSelected = mode.id == _selectedBillingMode;
                      return ChoiceChip(
                        label: SelectableText(mode.label, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: isSelected ? BridgeDSColors.of(context).textPrimary : BridgeDSColors.of(context).textPrimary,)),
                        selected: isSelected,
                        selectedColor: BridgeDSColors.of(context).accentBlue,
                        onSelected: (selected) async {
                          if (selected) {
                            await BillingModes.setSelectedModeId(_apiProvider, mode.id);
                            // [教練 Agent 2026-08-16 使用者 抓包] 治本——計費模式切換
                            // 必須立即持久化 gateway_url。之前只改 UI 輸入框，
                            // 已鎖定狀態下儲存鈕是隱藏的，URL 永遠存不進去，
                            // 導致 coding plan 的 key 打 payg 端點 → 429。
                            await StorageService.saveGatewayUrl(mode.baseUrl);
                            // 同步 golden_keys 雙寫鏈的 provider 設定
                            await StorageService.saveProviderConfig(_apiProvider, mode.baseUrl);
                            setState(() {
                              _selectedBillingMode = mode.id;
                              _apiUrlController.text = mode.baseUrl;
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            // [教練 Agent 2026-08-17 使用者 微調] 計費模式區塊與下方按鈕列
            // 的垂直間距——之前直接貼在一起太擠
            SizedBox(height: BridgeDS.spaceMD),
          ],

          // 按鈕列
          // 三階段流程：
          // 1. 未鎖定 → [測試連線] [儲存]
          // 2. 測試中/儲存中 → spinner
          // 3. 已鎖定 → ✓ 已鎖定 + [儲存] [解除鎖定]
          //    [教練 Agent 2026-08-17 使用者回饋] 已鎖定狀態也要給「儲存」鈕——
          //    之前只給「解除鎖定」，解鎖→測試→切走→切回變已鎖定場景
          //    想儲存新測試結果找不到鈕，必須再解除一次。
          //    現在不解鎖也能直接儲存最新設定。
          if (_apiSaved) ...[
            Row(
              children: [
                Icon(Icons.lock, color: BridgeDSColors.of(context).accentGreen, size: 16),
                SizedBox(width: 8),
                SelectableText(
                  '$_apiProvider 已鎖定',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                    color: BridgeDSColors.of(context).accentGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Spacer(),
                _buildSaveButton(
                  saved: true,
                  onPressed: _saveApiConfig,
                ),
                SizedBox(width: 12),
                BridgePillButton(
                  label: '解除鎖定',
                  icon: Icons.lock_open,
                  type: BridgeButtonType.ghost,
                  onPressed: () {
                    setState(() {
                      _providerSaved[_apiProvider] = false;
                      _providerTested[_apiProvider] = false;
                      _providerTestModels.remove(_apiProvider);
                      _providerTestError.remove(_apiProvider);
                    });
                  },
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                BridgePillButton(
                  label: _apiTesting ? '測試中' : '測試連線',
                  icon: _apiTesting
                      ? null
                      : Icons.wifi_tethering,
                  type: BridgeButtonType.ghost,
                  onPressed: _apiTesting ? null : _testApiConnection,
                ),
                SizedBox(width: 24),
                _buildSaveButton(
                  saved: false,
                  onPressed: _saveApiConfig,
                ),
                if (_apiTesting || _apiSaving) ...[
                  SizedBox(width: 16),
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: BridgeDSColors.of(context).accentBlue,
                    ),
                  ),
                ],
              ],
            ),
          ],

          // 測試成功結果
          if (_apiTestModels != null) ...[
            SizedBox(height: BridgeDS.spaceMD),
            Row(
              children: [
                Icon(Icons.check_circle,
                    color: BridgeDSColors.of(context).accentGreen, size: 16),
                SizedBox(width: 8),
                SelectableText(
                  '連線成功，可用模型：',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                    color: BridgeDSColors.of(context).accentGreen,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            // [教練 Agent 2026-08-17 使用者 指示] 模型自選——
            // 使用者可從測試拉回的可用模型清單點選預設型號。
            // 自動挑選仍當初始值（首次測試後），但使用者一點就覆蓋。
            // 場景：GLM 選最強 5.3 當主腦；OpenAI 選快速型當備用/特定功能。
            if (_selectedApiModel != null) ...[
              Padding(
                padding: EdgeInsets.only(left: 24, top: 4),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 14,
                        color: BridgeDSColors.of(context).accentGreen),
                    SizedBox(width: 6),
                    SelectableText(
                      '預設模型：$_selectedApiModel',
                      style: BridgeDSColors.of(context).code.copyWith(
                        fontSize: 14,
                        color: BridgeDSColors.of(context).accentGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_apiTestModels != null && _apiTestModels!.isNotEmpty) ...[
              SizedBox(height: 4),
              Padding(
                padding: EdgeInsets.only(left: 24),
                child: _buildModelChips(_apiTestModels!),
              ),
            ],
          ],

          // 測試錯誤結果
          if (_apiTestError != null) ...[
            SizedBox(height: BridgeDS.spaceMD),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline,
                    color: BridgeDSColors.of(context).accentRed, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    _apiTestError!,
                    style: BridgeDSColors.of(context).code.copyWith(
                      fontSize: 14,
                      color: BridgeDSColors.of(context).accentRed,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// [教練 Agent 2026-08-17 使用者 微調] 折疊式模型 chips——
  /// 常用型號（對話/coding/影像生成）直接列出；長尾（工具型、
  /// 日期快照、舊時代）折疊在「顯示全部 N 個型號」後面。
  Widget _buildModelChips(List<String> models) {
    final featured = models.where(_isFeaturedModel).toList();
    final rest = models.where((m) => !_isFeaturedModel(m)).toList();

    // 全部都常用（如 GLM 只有 9 顆）→ 不需要折疊
    if (rest.isEmpty || featured.isEmpty) {
      return Wrap(spacing: 6, runSpacing: 6, children: [
        for (final model in models) _buildModelChip(model),
      ]);
    }

    final expanded = _modelsExpanded;
    // 選中的模型如果在折疊區，也要撈出來顯示（不能看不到自己的選擇）
    final visibleFeatured = expanded
        ? featured
        : [
            ...featured,
            if (_selectedApiModel != null && rest.contains(_selectedApiModel))
              _selectedApiModel!,
          ];
    final shown = expanded ? models : visibleFeatured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final model in shown) _buildModelChip(model),
        ]),
        SizedBox(height: 6),
        // 折疊開關
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() {
            _providerModelsExpanded[_apiProvider] = !expanded;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: BridgeDSColors.of(context).textMuted,
                ),
                SizedBox(width: 4),
                Text(
                  expanded ? '收合長尾型號' : '顯示全部 ${models.length} 個型號',
                  style: BridgeDSColors.of(context).code.copyWith(
                    fontSize: 12,
                    color: BridgeDSColors.of(context).textMuted,
                  ),
                ),
                if (!expanded) ...[
                  SizedBox(width: 6),
                  Text(
                    '（常用 ${featured.length} 顆已列出）',
                    style: BridgeDSColors.of(context).code.copyWith(
                      fontSize: 11,
                      color: BridgeDSColors.of(context).textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModelChip(String model) {
    final selected = model == _selectedApiModel;
    return ActionChip(
      label: Text(
        model,
        style: BridgeDSColors.of(context).code.copyWith(
          fontSize: 12,
          color: selected
              ? BridgeDSColors.of(context).accentGreen
              : BridgeDSColors.of(context).textMuted,
        ),
      ),
      backgroundColor: selected
          ? BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.12)
          : BridgeDSColors.of(context).surface,
      side: BorderSide(
        color: selected
            ? BridgeDSColors.of(context).accentGreen
            : BridgeDSColors.of(context).borderDefault,
      ),
      onPressed: () async {
        // 點選＝設為此 provider 的預設模型
        await StorageService.saveApiModel(model, provider: _apiProvider);
        setState(() {
          _selectedApiModel = model;
        });
        debugPrint(
            '[BrainApiConfigCard] 使用者指定預設模型：$_apiProvider → $model');
      },
    );
  }

  /// [教練 Agent 2026-08-17 使用者回饋] 儲存鈕視覺回饋——
  /// 儲存中：藍底 spinner 「儲存中…」
  /// 儲存成功：1.5 秒綠底「✓ 已儲存」打勾
  /// 平常：藍底「💾 儲存」
  Widget _buildSaveButton({
    required bool saved,
    required VoidCallback onPressed,
  }) {
    if (_apiSaving) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).accentBlue
              .withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: BridgeDSColors.of(context).canvas,
              ),
            ),
            SizedBox(width: 8),
            Text(
              '儲存中…',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                    color: BridgeDSColors.of(context).canvas,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      );
    }

    if (_saveJustSucceeded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).accentGreen,
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle,
                size: 16, color: BridgeDSColors.of(context).canvas),
            SizedBox(width: 6),
            Text(
              '已儲存',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                    color: BridgeDSColors.of(context).canvas,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      );
    }

    return BridgePillButton(
      label: '儲存',
      icon: Icons.save_outlined,
      type: BridgeButtonType.accent,
      onPressed: onPressed,
    );
  }
}