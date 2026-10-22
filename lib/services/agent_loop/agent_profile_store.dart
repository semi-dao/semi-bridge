/// ProviderProfileStore — 可自進化的 Provider 能力設定檔管理器
///
/// 取代硬編碼的 _profiles Map。設定檔存在 JSON 裡，原生 Agent可讀可寫。
/// 遇到新模型時：
/// 1. 先用保守預設（conservativeProfile）
/// 2. 原生 Agent可用 test_provider_capability 工具跑基準測試
/// 3. 測試結果自動寫入 JSON
/// 4. 之後就用適配過的設定
///
/// [教練 Agent 2026-07-18 Phase 3] 自進化分層系統
///
/// [教練 Agent 2026-07-30 v2 Phase 2] ProviderProfile v2 策略模式：
/// - maxTurns / forceToolUse / taskChunkSize 已從建構子移除
/// - 新欄位：suggestedMaxTurns / suggestedTaskChunkSize / unlimited（預設 true）
/// - JSON 載入時做欄位遷移（v1 → v2）：maxTurns → suggestedMaxTurns 等
///
/// [教練 Agent 2026-07-30 Phase 4] 加入 CustomRoutingPolicy 支援：
/// - 使用者可建立自訂調用原則，覆寫內建 profile 的指定欄位
/// - 同一 provider+model 同一時間只有一個 active 原則
/// - 啟用新原則時舊的自動 isActive=false（原子寫入）
/// - custom policies 存在 JSON 的 `_customPolicies` 區塊，與 provider profiles 分開管理
/// - `_customPolicySeedVersion` 獨立追蹤，不會被 ProviderProfile seed 更新清空
///
/// ## CustomRoutingPolicy overrides 與 ProviderProfile v2 欄位對應
/// - `maxTurns` → 套用到 `suggestedMaxTurns`
/// - `taskChunkSize` → 套用到 `suggestedTaskChunkSize`
/// - `forceToolUse` → 映射到 `unlimited`（forceToolUse=false → unlimited=true；反之亦然）
/// - `apiParams` → 深度合併
/// - `promptNudge` / `supportsReasoningContent` / `visionModel` / `tier` → 直接覆蓋
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'active_strategy.dart';
import 'agent_provider_profile.dart';
import 'custom_routing_policy.dart';

class ProviderProfileStore {
  static const _fileName = 'provider_profiles.json';
  /// [教練 Agent 2026-07-30] ProviderProfile 種子版本號——每次修正種子數據時 +1，啟動時自動覆蓋舊的持久化 profile
  static const _currentSeedVersion = 5;
  /// [教練 Agent 2026-07-30 Phase 4] Custom policy 種子版本號——獨立追蹤，避免 ProviderProfile seed 更新時清空使用者自訂原則
  static const _currentCustomPolicySeedVersion = 3;
  /// JSON 中 custom policies 區塊的 key
  static const _customPoliciesKey = '_customPolicies';
  /// JSON 中 custom policy seed version 的 key
  static const _customPolicySeedVersionKey = '_customPolicySeedVersion';
  static ProviderProfileStore? _instance;

  final Map<String, ProviderProfile> _cache = {};
  /// [教練 Agent 2026-07-30 Phase 4] 自訂調用原則 cache（id → policy）
  final Map<String, CustomRoutingPolicy> _customPolicies = {};
  bool _initialized = false;

  ProviderProfileStore._();

  static ProviderProfileStore get instance {
    _instance ??= ProviderProfileStore._();
    return _instance!;
  }

  /// 初始化：如果 JSON 不存在，寫入種子數據；如果存在，載入到 cache
  ///
  /// [教練 Agent 2026-07-30 Phase 4] custom policies 與 provider profiles 分開載入/儲存
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final file = await _getFilePath();
      final fileObj = File(file);

      if (await fileObj.exists()) {
        final content = await fileObj.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;

        // 1. 載入 provider profiles（排除底線開頭的中繼資料）
        _cache.clear();
        for (final entry in json.entries) {
          if (entry.key.startsWith('_')) continue;
          _cache[entry.key] = _profileFromJson(entry.value as Map<String, dynamic>);
        }

        // 2. 載入 custom policies
        _customPolicies.clear();
        final customPoliciesJson = json[_customPoliciesKey] as Map<String, dynamic>?;
        if (customPoliciesJson != null) {
          for (final entry in customPoliciesJson.entries) {
            try {
              _customPolicies[entry.key] =
                  CustomRoutingPolicy.fromJson(entry.value as Map<String, dynamic>);
            } catch (e) {
              debugPrint('[ProviderProfile] 略過損壞的 custom policy ${entry.key}: $e');
            }
          }
        }

        // 3. ProviderProfile 種子版本檢查
        final storedVersion = json['_seedVersion'] as int? ?? 0;
        if (storedVersion < _currentSeedVersion) {
          debugPrint('[ProviderProfile] 種子版本 $storedVersion → $_currentSeedVersion，更新已知 profile');
          _seedDefaults();  // 覆蓋種子裡有定義的 profile
          await _saveToFile();
        }

        // 4. CustomPolicy seed 版本檢查
        final storedCustomPolicyVersion =
            json[_customPolicySeedVersionKey] as int? ?? 0;
        if (storedCustomPolicyVersion < _currentCustomPolicySeedVersion) {
          debugPrint('[CustomPolicy] 種子版本 $storedCustomPolicyVersion → $_currentCustomPolicySeedVersion');
          _seedDefaultPolicies();  // [教練 Agent 2026-07-30] 建立預設選型原則
          await _saveToFile();
        }

        debugPrint('[ProviderProfile] 已載入 ${_cache.length} 個 profile，'
            '${_customPolicies.length} 個 custom policy');
      } else {
        // 首次啟動——寫入種子數據
        _seedDefaults();
        await _saveToFile();
        debugPrint('[ProviderProfile] 首次啟動，已寫入 ${_cache.length} 個種子 profile');
      }
      _initialized = true;
    } catch (e) {
      debugPrint('[ProviderProfile] 載入失敗，使用記憶體種子: $e');
      _seedDefaults();
      _initialized = true;
    }
  }

  /// 取得 profile（async，因為可能需要從檔案載入）
  ///
  /// [教練 Agent 2026-07-30 Phase 4] 套用 active CustomRoutingPolicy：
  /// - 先查內建 profile（含 fallback 邏輯）
  /// - 若有 active policy，再套用 overrides
  /// - custom policy 不覆寫路由決策，只覆寫選定 provider 後的調用參數
  Future<ProviderProfile> getProfile(String provider, String model) async {
    if (!_initialized) await initialize();

    final baseProfile = await _getBuiltinProfile(provider, model);

    // [教練 Agent 2026-07-30 Phase 4] 套用 active custom policy
    final activePolicy = _findActiveCustomPolicy(provider, model);
    if (activePolicy != null) {
      debugPrint('[ProviderProfile] 套用自訂原則 ${activePolicy.id} '
          '(${activePolicy.name}) 到 $provider/$model');
      return applyOverrides(baseProfile, activePolicy.overrides);
    }

    return baseProfile;
  }

  /// [教練 Agent 2026-07-30 Phase 4] 解析「最終生效」的策略（給 NativeAgentLoop 用）
  ///
  /// 優先序：自訂原則 > 內建 profile > conservative fallback
  /// 回傳 ActiveStrategy 物件，NativeAgentLoop 直接讀取即可。
  ///
  /// 完整流程：
  /// 1. getProfile() 已自動套用 custom policy
  /// 2. 從合併後的 ProviderProfile 讀取 unlimited / suggestedMaxTurns / suggestedTaskChunkSize
  /// 3. 包成 ActiveStrategy 回傳
  Future<ActiveStrategy> resolveActiveStrategy(
    String provider,
    String model,
  ) async {
    final profile = await getProfile(provider, model);

    return ActiveStrategy(
      unlimited: profile.unlimited,
      suggestedMaxTurns: profile.suggestedMaxTurns,
      suggestedTaskChunkSize: profile.suggestedTaskChunkSize,
      promptNudge: profile.promptNudge,
      apiParams: Map<String, dynamic>.from(profile.apiParams),
      provider: profile.provider,
      model: profile.model,
      tier: profile.tier,
    );
  }

  /// 原生 Agent更新 profile（測試完成後呼叫）
  Future<void> updateProfile(String provider, String model, ProviderProfile profile) async {
    if (!_initialized) await initialize();

    final key = '${provider}_$model'.toLowerCase();
    _cache[key] = profile;
    await _saveToFile();
    debugPrint('[ProviderProfile] 已更新 profile: $key '
        '(Tier ${profile.tier.name}, unlimited=${profile.unlimited})');
  }

  /// 列出所有 profile（給原生 Agent查看用）
  Future<List<Map<String, dynamic>>> listProfiles() async {
    if (!_initialized) await initialize();

    return _cache.entries.map((e) {
      final p = e.value;
      return {
        'key': e.key,
        'provider': p.provider,
        'model': p.model,
        'tier': p.tierName,
        'suggestedMaxTurns': p.suggestedMaxTurns,
        'suggestedTaskChunkSize': p.suggestedTaskChunkSize,
        'unlimited': p.unlimited,
        'tested': p.tested};
    }).toList();
  }

  /// 取得所有未測試的 profile
  Future<List<Map<String, dynamic>>> untestedProfiles() async {
    final all = await listProfiles();
    return all.where((p) => p['tested'] == false).toList();
  }

  // ════════════════════════════════════════════════════════════════════
  // [教練 Agent 2026-07-30 Phase 4] CustomRoutingPolicy 管理 API
  // ════════════════════════════════════════════════════════════════════

  /// 建立並儲存一筆新的 CustomRoutingPolicy
  ///
  /// 規則：
  /// - 寫入 _customPolicies map 並立即持久化
  /// - 預設 isActive=false（建立後不會自動啟用）
  /// - 若呼叫者希望立即啟用，再呼叫 activatePolicy(policyId)
  Future<void> createPolicy(CustomRoutingPolicy policy) async {
    if (!_initialized) await initialize();

    if (policy.id.isEmpty) {
      throw ArgumentError('CustomRoutingPolicy.id 不能為空');
    }
    if (_customPolicies.containsKey(policy.id)) {
      throw StateError('CustomRoutingPolicy.id 已存在: ${policy.id}');
    }

    _customPolicies[policy.id] = policy;
    await _saveToFile();
    debugPrint('[CustomPolicy] 已建立: ${policy.id} (${policy.name}), '
        'isActive=${policy.isActive}');
  }

  /// 啟用指定的 custom policy
  ///
  /// 自動機制（設計文件 §B.3、§D.3）：
  /// 1. 同一 provider+model 下所有舊 active policy 改為 isActive=false
  /// 2. 目標 policy 設為 isActive=true
  /// 3. 原子寫入（一次 save，避免 partial state）
  ///
  /// 注意：policy.model 為 null = 該 provider 下所有 model 都適用；
  /// 因此 model 為 null 的舊 policy 也會被視為「同 provider」而被自動停用。
  Future<void> activatePolicy(String policyId) async {
    if (!_initialized) await initialize();

    final policy = _customPolicies[policyId];
    if (policy == null) {
      throw StateError('CustomPolicy not found: $policyId');
    }

    // 在記憶體內完成所有變更，最後一次性寫入
    final updated = <String, CustomRoutingPolicy>{..._customPolicies};
    var deactivatedCount = 0;
    for (final entry in _customPolicies.entries) {
      final p = entry.value;
      if (!p.isActive) continue;
      if (p.id == policyId) continue;
      if (!_policyTargetsSameScope(p, policy)) continue;
      updated[p.id] = p.copyWith(isActive: false);
      deactivatedCount++;
      debugPrint('[CustomPolicy] 自動停用舊原則: ${p.id}');
    }

    // 啟用新原則
    updated[policyId] = policy.copyWith(isActive: true);

    _customPolicies
      ..clear()
      ..addAll(updated);
    await _saveToFile();

    debugPrint('[CustomPolicy] 已啟用: $policyId '
        '(${policy.name}, 自動停用 $deactivatedCount 個舊原則)');
  }

  /// 停用指定的 custom policy
  ///
  /// 停用後該 provider+model 會回到內建 profile（設計文件 §E.2 流程 B）。
  /// 不會刪除 policy——日後可重新啟用。
  Future<void> deactivatePolicy(String policyId) async {
    if (!_initialized) await initialize();

    final policy = _customPolicies[policyId];
    if (policy == null) {
      throw StateError('CustomPolicy not found: $policyId');
    }
    if (!policy.isActive) {
      debugPrint('[CustomPolicy] $policyId 已經是停用狀態，無需操作');
      return;
    }

    _customPolicies[policyId] = policy.copyWith(isActive: false);
    await _saveToFile();
    debugPrint('[CustomPolicy] 已停用: $policyId');
  }

  /// 取得指定 provider/model 當前 active 的 custom policy（沒有則回傳 null）
  Future<CustomRoutingPolicy?> getActivePolicy(
    String provider,
    String model,
  ) async {
    if (!_initialized) await initialize();
    return _findActiveCustomPolicy(provider, model);
  }

  /// 列出所有 custom policy（含停用的），給設定頁用
  Future<List<CustomRoutingPolicy>> getAllPolicies() async {
    if (!_initialized) await initialize();
    return _customPolicies.values.toList();
  }

  /// 套用 custom policy 的 overrides 到內建 profile
  ///
  /// 規則（設計文件 §B.2）：
  /// - 每個覆寫鍵獨立處理（tier / maxTurns / forceToolUse / ...）
  /// - apiParams 特殊處理：**深度合併**（key-by-key 覆寫），而非整個替換
  /// - 其他欄位沒給就沿用內建
  /// - tested 永遠沿用內建（自訂原則不代表通過基準測試）
  ///
  /// [教練 Agent 2026-07-30 v2] ProviderProfile v2 欄位映射：
  /// - `maxTurns` override → 套用到 `suggestedMaxTurns`
  /// - `taskChunkSize` override → 套用到 `suggestedTaskChunkSize`
  /// - `forceToolUse` override → 映射到 `unlimited`
  ///   （forceToolUse=false → unlimited=true；反之 unlimited=false）
  /// - 其他欄位（tier / apiParams / promptNudge / supportsReasoningContent / visionModel）直接覆蓋
  ///
  /// 不修改 ProviderProfile 結構，只建立新 instance。
  ProviderProfile applyOverrides(
    ProviderProfile base,
    Map<String, dynamic> overrides,
  ) {
    // [小葵 2026-09-19 架構審視第一刀 · agent.mind.modelFollowUser]
    // 模型跟隨鐵則：tier 客製政策不得覆寫 API 參數。
    // 病例：2026-09-19 Blue 切 GPT-6（只支援 temperature=1），
    // tier1 政策塞 temperature 0.3 → 每次請求 400 → 小橋沉默 3 小時。
    // 政策只管行為參數（輪數/拆分/是否信任），apiParams 一律沿用 base profile。
    final overrideApiParams = overrides['apiParams'];
    if (overrideApiParams is Map && overrideApiParams.isNotEmpty) {
      debugPrint(
        '[ProviderProfile] ⚠️ 政策 apiParams 覆寫已停用（modelFollowUser 鐵則）——'
        '忽略 ${overrideApiParams.keys.toList()}',
      );
    }
    final Map<String, dynamic> mergedApiParams = base.apiParams;

    // 2. 處理 suggestedMaxTurns（從舊 maxTurns key 讀取）
    final overrideMaxTurns = overrides['maxTurns'] as int?;
    final newSuggestedMaxTurns = overrideMaxTurns ?? base.suggestedMaxTurns;

    // 3. 處理 suggestedTaskChunkSize（從舊 taskChunkSize key 讀取）
    final overrideTaskChunkSize = overrides['taskChunkSize'] as int?;
    final newSuggestedTaskChunkSize =
        overrideTaskChunkSize ?? base.suggestedTaskChunkSize;

    // 4. 處理 unlimited（從舊 forceToolUse key 反推）
    // forceToolUse=true → 保守 → unlimited=false
    // forceToolUse=false → 信任 → unlimited=true
    final overrideForceToolUse = overrides['forceToolUse'] as bool?;
    final newUnlimited = overrideForceToolUse != null
        ? !overrideForceToolUse
        : base.unlimited;

    return ProviderProfile(
      provider: base.provider,
      model: base.model,
      tier: _parseTierOverride(overrides['tier']) ?? base.tier,
      apiParams: mergedApiParams,
      suggestedMaxTurns: newSuggestedMaxTurns,
      suggestedTaskChunkSize: newSuggestedTaskChunkSize,
      promptNudge: overrides['promptNudge'] as String? ?? base.promptNudge,
      unlimited: newUnlimited,
      supportsReasoningContent: overrides['supportsReasoningContent'] as bool?
          ?? base.supportsReasoningContent,
      visionModel: overrides['visionModel'] as String? ?? base.visionModel,
      tested: base.tested,  // 永遠沿用內建
    );
  }

  // ═══════════════════════════════════════════════════
  // 內部方法
  // ═══════════════════════════════════════════════════

  /// [教練 Agent 2026-07-30] 建立預設選型原則——每個雲端 provider 一個，全部啟用。
  /// 選擇「預設」時，resolveDefault() 會依 tier 排序選最佳 provider。
  /// 使用者之後可從設定頁停用或微調。
  Future<String> _getFilePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$_fileName';
  }

  /// 寫入 JSON：provider profiles + custom policies
  ///
  /// 結構：
  /// ```
  /// {
  ///   "_seedVersion": 5,
  ///   "_customPolicySeedVersion": 1,
  ///   "openai_gpt-5.4": { ... },
  ///   "_customPolicies": {
  ///     "crp_xxx": { ... }
  ///   }
  /// }
  /// ```
  Future<void> _saveToFile() async {
    try {
      final path = await _getFilePath();
      final json = <String, dynamic>{
        '_seedVersion': _currentSeedVersion,
        _customPolicySeedVersionKey: _currentCustomPolicySeedVersion,
      };
      // 先寫 provider profiles（底線開頭的中繼資料已用 _seedVersion 處理）
      for (final entry in _cache.entries) {
        json[entry.key] = _profileToJson(entry.value);
      }
      // 再寫 custom policies（獨立區塊）
      if (_customPolicies.isNotEmpty) {
        final policiesJson = <String, dynamic>{};
        for (final entry in _customPolicies.entries) {
          policiesJson[entry.key] = entry.value.toJson();
        }
        json[_customPoliciesKey] = policiesJson;
      }
      await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    } catch (e) {
      debugPrint('[ProviderProfile] 儲存失敗: $e');
    }
  }

  /// 取得內建 profile（含完全匹配 / 模糊匹配 / provider 預設 / 新模型保守預設）
  Future<ProviderProfile> _getBuiltinProfile(String provider, String model) async {
    final key = '${provider}_$model'.toLowerCase();

    // 1. 完全匹配
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    // 2. 模糊匹配
    for (final entry in _cache.entries) {
      if (entry.key.contains(provider.toLowerCase()) &&
          _modelMatches(entry.key, model.toLowerCase())) {
        return entry.value;
      }
    }

    // 3. provider 預設
    final providerKey = provider.toLowerCase();
    for (final entry in _cache.entries) {
      if (entry.key.startsWith('${providerKey}_') &&
          entry.value.model.toLowerCase() == providerKey) {
        // 這是 provider 預設（model 名 == provider 名的簡化判斷）
        return entry.value;
      }
    }

    // 4. 新模型——用保守預設，標記為「未測試」
    // [教練 Agent 2026-07-30 v2] 用 ProviderProfile.conservativeProfile 當 fallback
    final newProfile = ProviderProfile(
      provider: provider,
      model: model,
      tier: ProviderTier.tier3,
      apiParams: const {'temperature': 0.3},
      suggestedMaxTurns: 15,
      suggestedTaskChunkSize: 3,
      unlimited: false,
      tested: false,
      promptNudge: '這個模型尚未經過能力測試，使用保守設定。'
          '請一次只做一個明確的任務。使用 <<<tool_call>>> 格式呼叫工具。',
    );

    // 自動寫入，下次就不用再 fallback
    _cache[key] = newProfile;
    await _saveToFile();
    debugPrint('[ProviderProfile] 新模型自動建立保守 profile: $key (未測試)');

    return newProfile;
  }

  /// 找出指定 provider/model 的 active CustomRoutingPolicy
  ///
  /// 規則（設計文件 §D.2）：
  /// - policy.provider 必須匹配（小寫比較）
  /// - policy.model 為 null → 該 provider 下所有 model 都適用
  /// - policy.model 不為 null → 必須完全匹配（小寫比較）
  CustomRoutingPolicy? _findActiveCustomPolicy(String provider, String model) {
    final providerLower = provider.toLowerCase();
    final modelLower = model.toLowerCase();
    for (final policy in _customPolicies.values) {
      if (!policy.isActive) continue;
      if (policy.provider.toLowerCase() != providerLower) continue;
      if (policy.model == null) return policy;
      if (policy.model!.toLowerCase() == modelLower) return policy;
    }
    return null;
  }

  /// 判斷兩個 custom policy 是否「針對同一個 target 範圍」
  ///
  /// 用於 activatePolicy() 時自動停用舊原則：
  /// - 同 provider
  /// - 且 model 範圍重疊（任一為 null，或 model 相同）
  bool _policyTargetsSameScope(
    CustomRoutingPolicy a,
    CustomRoutingPolicy b,
  ) {
    if (a.provider.toLowerCase() != b.provider.toLowerCase()) return false;
    // [教練 Agent 2026-07-30] 不同 tier 的原則可以共存——它們是不同層級的路由規則
    final tierA = a.overrides['tier'] as String?;
    final tierB = b.overrides['tier'] as String?;
    if (tierA != null && tierB != null && tierA != tierB) return false;
    // 任一 model 為 null = 該 provider 下所有 model 都適用 → 視為重疊
    if (a.model == null || b.model == null) return true;
    return a.model!.toLowerCase() == b.model!.toLowerCase();
  }

  /// 解析 overrides['tier'] 字串為 ProviderTier enum
  ProviderTier? _parseTierOverride(dynamic value) {
    if (value is String) return _tierFromString(value);
    return null;
  }

  bool _modelMatches(String profileKey, String model) {
    final parts = profileKey.split('_');
    if (parts.length < 2) return false;
    final modelPart = parts.sublist(1).join('_');
    // 精確匹配優先
    if (model == modelPart) return true;
    // 前綴匹配（避免 gpt-5.4 匹配到 gpt-5）
    if (model.startsWith(modelPart) && modelPart.length >= 3) return true;
    return false;
  }

  /// [教練 Agent 2026-07-30 v2] 種子改用 ProviderProfile v2 API
  /// （全面開通策略：unlimited=true，移除 max_tokens / max_completion_tokens）
  void _seedDefaults() {
    final seeds = {
      // === OpenAI ===
      'openai_gpt-4o': ProviderProfile(
        provider: 'openai', model: 'gpt-4o', tier: ProviderTier.tier1,
        apiParams: {'temperature': 0.3},
        suggestedMaxTurns: 25, suggestedTaskChunkSize: 20, tested: true,
      ),
      'openai_gpt-4o-mini': ProviderProfile(
        provider: 'openai', model: 'gpt-4o-mini', tier: ProviderTier.tier2,
        apiParams: {'temperature': 0.3},
        suggestedMaxTurns: 20, suggestedTaskChunkSize: 7, tested: true,
      ),
      'openai_gpt-5.4': ProviderProfile(
        provider: 'openai', model: 'gpt-5.4', tier: ProviderTier.tier1,
        apiParams: {},
        suggestedMaxTurns: 25, suggestedTaskChunkSize: 20, tested: true,
        promptNudge: '你是 Tier 1 高能力模型。直接執行任務，多步驟工具使用。收到工具結果後立即分析並行動。',
      ),
      'openai_gpt-5': ProviderProfile(
        provider: 'openai', model: 'gpt-5', tier: ProviderTier.tier2,
        apiParams: {},
        suggestedMaxTurns: 20, suggestedTaskChunkSize: 10, tested: true,
        promptNudge: '收到工具結果後，請直接分析並用 patch_source_file 修復，不要先做額外確認。',
      ),
      'openai_gpt-5-mini': ProviderProfile(
        provider: 'openai', model: 'gpt-5-mini', tier: ProviderTier.tier2,
        apiParams: {},
        suggestedMaxTurns: 20, suggestedTaskChunkSize: 7, tested: true,
        promptNudge: '收到工具結果後，請直接分析並用 patch_source_file 修復，不要先做額外確認。',
      ),
      // === GLM ===
      'glm_glm-5': ProviderProfile(
        provider: 'glm', model: 'glm-5', tier: ProviderTier.tier1,
        // [教練 Agent 2026-08-16] glm-5.x 預設強制思考（每輪 16-23 秒），
        // thinking.disabled 對 4.6/5-turbo 有效；5/5.2 無效但帶著無害
        apiParams: {'temperature': 0.3, 'thinking': {'type': 'disabled'}},
        suggestedMaxTurns: 25, suggestedTaskChunkSize: 15, tested: true,
      ),
      'glm_glm-5-turbo': ProviderProfile(
        provider: 'glm', model: 'glm-5-turbo', tier: ProviderTier.tier1,
        // [教練 Agent 2026-08-16] 快攻模型——thinking.disabled 實測有效
        // （0 思考 tokens、秒級回應），AgentLoop 首選
        apiParams: {'temperature': 0.3, 'thinking': {'type': 'disabled'}},
        suggestedMaxTurns: 25, suggestedTaskChunkSize: 15, tested: true,
        supportsReasoningContent: true,
        visionModel: 'glm-4.6v',
        promptNudge: '你是 GLM-5-turbo，快速執行模型。直接執行任務，減少解釋，多步驟工具使用。收到工具結果後立即分析並行動。',
      ),
      'glm_glm-5.3': ProviderProfile(
        provider: 'glm', model: 'glm-5.3', tier: ProviderTier.tier1,
        // [小葵 2026-10-20 修復] 5.3 曾「disabled 帶著無害」——API 改版後
        // 不成立了：錯誤 1210「该模型始终思考，不支持关闭思考；请使用
        // low、high 或 max」。thinking.disabled 現在整包 400。改不帶參數
        //（預設思考），需要快的場合 suggestsFallbackModel 有 5-turbo。
        apiParams: {'temperature': 0.3},
        suggestsFallbackModel: 'glm-5-turbo', // [教練 Agent 2026-08-16] 5.3 額度滿/429 fallback
        suggestedMaxTurns: 25, suggestedTaskChunkSize: 15, tested: true,
        supportsReasoningContent: true,
        visionModel: 'glm-4.6v',
        promptNudge: '你是 GLM-5.3（智譜 2026-08-14 旗艦），Tier 1 高能力推理模型。'
            '比 5.2 思考更短、回應更快、推理更強。直接執行任務，多步驟工具使用。'
            '收到工具結果後立即分析並行動。',
      ),
      'glm_glm-5.2': ProviderProfile(
        provider: 'glm', model: 'glm-5.2', tier: ProviderTier.tier1,
        apiParams: {'temperature': 0.3, 'thinking': {'type': 'disabled'}},
        suggestedMaxTurns: 25, suggestedTaskChunkSize: 15, tested: true,
        supportsReasoningContent: true,
        visionModel: 'glm-4.6v',
        promptNudge: '你是 GLM-5.2，Tier 1 高能力推理模型。直接執行任務，多步驟工具使用。收到工具結果後立即分析並行動。',
      ),
      'glm_glm-4.7': ProviderProfile(
        provider: 'glm', model: 'glm-4.7', tier: ProviderTier.tier2,
        apiParams: {'temperature': 0.3},
        suggestedMaxTurns: 20, suggestedTaskChunkSize: 7, tested: true,
        promptNudge: '收到工具結果後，請直接分析並用 patch_source_file 修復，不要先做額外確認。',
      ),
      'glm_glm-4.5': ProviderProfile(
        provider: 'glm', model: 'glm-4.5', tier: ProviderTier.tier3,
        apiParams: {'temperature': 0.3},
        suggestedMaxTurns: 15, suggestedTaskChunkSize: 3, tested: true,
      ),
      // === Kimi ===
      'kimi_kimi-k3': ProviderProfile(
        provider: 'kimi', model: 'kimi-k3', tier: ProviderTier.tier2,
        // [教練 Agent 2026-07-30] kimi-k3 是 reasoning model，temperature 固定 1
        // 注意：必須用 int 1 而非 double 1.0，Kimi API 嚴格區分整數與浮點數
        apiParams: {'temperature': 1},
        suggestedMaxTurns: 20, suggestedTaskChunkSize: 15, tested: true,
        promptNudge: '收到工具結果後，請直接分析並用 patch_source_file 修復，不要先做額外確認。',
      ),
      'kimi_kimi-k2.5': ProviderProfile(
        provider: 'kimi', model: 'kimi-k2.5', tier: ProviderTier.tier3,
        apiParams: {'temperature': 0.3},
        suggestedMaxTurns: 15, suggestedTaskChunkSize: 3, tested: true,
        supportsReasoningContent: true,
        promptNudge: '一次只做一個明確的任務。使用 <<<tool_call>>> 格式呼叫工具。',
      ),
      // === MiniMax ===
      'minimax_minimax-m2.5': ProviderProfile(
        provider: 'minimax', model: 'MiniMax-M3', tier: ProviderTier.tier2,
        apiParams: {'temperature': 0.3},
        suggestedMaxTurns: 20, suggestedTaskChunkSize: 7, tested: false,
        promptNudge: '收到工具結果後，請直接分析並用 patch_source_file 修復，不要先做額外確認。',
      ),
      // === Local ===
      'local_llama3.1:8b': ProviderProfile(
        provider: 'local', model: 'llama3.1:8b', tier: ProviderTier.tier3,
        apiParams: {'temperature': 0.3},
        suggestedMaxTurns: 10, suggestedTaskChunkSize: 1, tested: true,
        promptNudge: '一次只做一個明確的任務。使用 <<<tool_call>>> 格式呼叫工具。',
      ),
      // [教練 Agent 2026-07-21] Qwen3.5-4B 本地模型：關閉 thinking 模式避免無限推理
      'local_qwen3.5-4b': ProviderProfile(
        provider: 'local', model: 'qwen3.5-4b', tier: ProviderTier.tier3,
        apiParams: {
          'temperature': 0.3,
          'chat_template_kwargs': {'enable_thinking': false}},
        suggestedMaxTurns: 10, suggestedTaskChunkSize: 1, tested: true,
        promptNudge: '一次只做一個明確的任務。使用 <<<tool_call>>> 格式呼叫工具。',
      )};
    _cache.clear();
    _cache.addAll(seeds);
  }

  /// [教練 Agent 2026-07-30 v2] 序列化用 ProviderProfile v2 欄位
  Map<String, dynamic> _profileToJson(ProviderProfile p) {
    return {
      'provider': p.provider,
      'model': p.model,
      'tier': p.tier.name,
      'apiParams': p.apiParams,
      'suggestedMaxTurns': p.suggestedMaxTurns,
      'suggestedTaskChunkSize': p.suggestedTaskChunkSize,
      'unlimited': p.unlimited,
      'supportsReasoningContent': p.supportsReasoningContent,
      'visionModel': p.visionModel,
      'tested': p.tested,
      'promptNudge': p.promptNudge};
  }

  /// [教練 Agent 2026-07-30 v2] 反序列化：容錯處理 v1 欄位（maxTurns / forceToolUse / taskChunkSize）
  /// 自動遷移：maxTurns → suggestedMaxTurns；forceToolUse 反推 unlimited
  ProviderProfile _profileFromJson(Map<String, dynamic> json) {
    // 解析 tier
    final tier = _tierFromString(json['tier'] as String? ?? 'tier3');

    // suggestedMaxTurns：新欄位優先，否則從舊 maxTurns 遷移
    int? suggestedMaxTurns;
    if (json.containsKey('suggestedMaxTurns')) {
      suggestedMaxTurns = json['suggestedMaxTurns'] as int?;
    } else if (json.containsKey('maxTurns')) {
      suggestedMaxTurns = json['maxTurns'] as int?;
    }

    // suggestedTaskChunkSize：新欄位優先，否則從舊 taskChunkSize 遷移
    int? suggestedTaskChunkSize;
    if (json.containsKey('suggestedTaskChunkSize')) {
      suggestedTaskChunkSize = json['suggestedTaskChunkSize'] as int?;
    } else if (json.containsKey('taskChunkSize')) {
      suggestedTaskChunkSize = json['taskChunkSize'] as int?;
    }

    // unlimited：新欄位優先；舊 forceToolUse 反推（forceToolUse=true → unlimited=false）
    bool unlimited;
    if (json.containsKey('unlimited')) {
      unlimited = json['unlimited'] as bool? ?? true;
    } else if (json.containsKey('forceToolUse')) {
      unlimited = !(json['forceToolUse'] as bool? ?? true);
    } else {
      unlimited = true;  // v2 預設 unlimited=true
    }

    return ProviderProfile(
      provider: json['provider'] as String? ?? 'unknown',
      model: json['model'] as String? ?? 'unknown',
      tier: tier,
      apiParams: Map<String, dynamic>.from(json['apiParams'] as Map? ?? {}),
      suggestedMaxTurns: suggestedMaxTurns,
      suggestedTaskChunkSize: suggestedTaskChunkSize,
      promptNudge: json['promptNudge'] as String?,
      unlimited: unlimited,
      supportsReasoningContent: json['supportsReasoningContent'] as bool? ?? false,
      visionModel: json['visionModel'] as String?,
      tested: json['tested'] as bool? ?? false,
    );
  }

  ProviderTier _tierFromString(String s) {
    switch (s) {
      case 'tier1': return ProviderTier.tier1;
      case 'tier2': return ProviderTier.tier2;
      default: return ProviderTier.tier3;
    }
  }

  /// [教練 Agent 2026-07-30] 預設選型原則——三層模型調用架構
  ///
  /// 初始狀態注入三條原則，使用者之後可透過對話自訂調整。
  /// 選擇「預設」時，ProviderRouter 依意圖自動選模型，
  /// 選中的 provider 會套用對應的 active policy overrides。
  void _seedDefaultPolicies() {
    final now = DateTime.now();
    _customPolicies.clear();
    _customPolicies['crp_default_tier1'] = CustomRoutingPolicy(
      id: 'crp_default_tier1',
      name: '雲端高級（Tier 1）',
      description: '完整多步驟工具使用，適合複雜任務。GPT-5.4 / GLM-5.2 等。',
      createdAt: now,
      provider: 'tier1',
      isActive: true,
      overrides: {
        'tier': 'tier1',
        'maxTurns': 20,
        'forceToolUse': false,
        'apiParams': {'temperature': 0.3},
      },
    );
    _customPolicies['crp_default_tier2'] = CustomRoutingPolicy(
      id: 'crp_default_tier2',
      name: '雲端快速（Tier 2）',
      description: '能用工具但需拆分小任務。Kimi-K3 / MiniMax-M2.5 等。',
      createdAt: now,
      provider: 'tier2',
      isActive: true,
      overrides: {
        'tier': 'tier2',
        'maxTurns': 10,
        'forceToolUse': false,
        'apiParams': {'temperature': 0.7},
      },
    );
    _customPolicies['crp_default_local'] = CustomRoutingPolicy(
      id: 'crp_default_local',
      name: '本地模型（Layer 1）',
      description: 'llama.cpp 4B @18789，快速回應、不消耗 API 額度。適合簡單任務。',
      createdAt: now,
      provider: 'local',
      isActive: true,
      overrides: {
        'tier': 'tier3',
        'maxTurns': 5,
        'forceToolUse': false,
        'apiParams': {'temperature': 0.3},
      },
    );
    debugPrint('[CustomPolicy] 已注入 ${_customPolicies.length} 條預設選型原則');
  }
}