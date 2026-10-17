// [教練 Agent 2026-07-30] PolicyGenerator — App Agent 解析自然語言 → 生成 CustomRoutingPolicy 草稿
//
// 設計目標：
// 1. 使用者用自然語言描述需求（例：「Kimi 太慢了，讓它少跑幾輪」）
// 2. App Agent 透過規則式 keyword matching 解析需求（不呼叫 LLM）
// 3. 查詢 ProviderProfileStore 內建現況
// 4. 生成 CustomRoutingPolicy 草稿（isActive = false，等使用者確認）
// 5. 太模糊時回傳 null（讓呼叫方反問使用者）
//
// 設計文件：/Volumes/DATA/橋樑計劃/02-架構設計/custom-routing-policy-design.md §C
//
// 不動 CustomRoutingPolicy / ActiveStrategy / ProviderProfileStore 本身。
// 只引用、組裝資料。

import 'package:flutter/foundation.dart';
import 'agent_provider_profile.dart';
import 'agent_profile_store.dart';
import 'custom_routing_policy.dart';
import 'active_strategy.dart';

/// PolicyGenerator 內部使用的意圖列舉
/// 規則式（keyword matching），不呼叫 LLM
enum PolicyIntent {
  /// 「太慢」→ maxTurns / taskChunkSize
  tooSlow,

  /// 「太笨」→ tier 升級
  tooStupid,

  /// 「太長」→ max_tokens ↓
  tooLong,

  /// 「太短」→ max_tokens ↑
  tooShort,

  /// 「有創意」→ temperature ↑
  creative,

  /// 「嚴謹」→ temperature ↓
  deterministic,

  /// 無法辨識
  unknown,
}

/// PolicyGenerator — 規則式自然語言 → CustomRoutingPolicy 草稿
///
/// 不呼叫 LLM，純關鍵字比對。
class PolicyGenerator {
  PolicyGenerator._();

  static final PolicyGenerator instance = PolicyGenerator._();

  // ═══════════════════════════════════════════════════
  // Provider 關鍵字辨識
  // ═══════════════════════════════════════════════════

  /// provider 識別用關鍵字（key → 對應的 provider 字串）
  /// 順序敏感：先匹配較長/較具體的詞
  static const Map<List<String>, String> _providerKeywords = {
    // kimi 系列
    ['kimi', 'moonshot']: 'kimi',
    // openai 系列（含 gpt-* 型號）
    ['openai', 'gpt-', 'gpt4', 'gpt5', 'chatgpt']: 'openai',
    // glm 系列
    ['glm', 'zhipu', '智譜', 'zhipuai']: 'glm',
    // minimax 系列
    ['minimax', 'MiniMax-', 'abab']: 'minimax',
    // anthropic
    ['anthropic', 'claude']: 'anthropic',
  };

  /// 從使用者訊息中辨識 provider
  /// 回傳 (provider, matchedKeyword)；沒找到回傳 null
  (String, String)? detectProvider(String text) {
    final lower = text.toLowerCase();

    // 1. 精確匹配 provider 別名（kimi / openai / glm / minimax / anthropic）
    for (final entry in _providerKeywords.entries) {
      for (final keyword in entry.key) {
        if (lower.contains(keyword.toLowerCase())) {
          return (entry.value, keyword);
        }
      }
    }

    return null;
  }

  // ═══════════════════════════════════════════════════
  // 意圖分類（規則式）
  // ═══════════════════════════════════════════════════

  /// 從使用者訊息分類意圖
  PolicyIntent classifyIntent(String text) {
    final lower = text.toLowerCase();

    // 1. 太慢（最高優先——直接對應 maxTurns 場景）
    if (_matchAny(lower, ['太慢', '太久了', '慢一點', '慢一', '卡住', 'hang', 'slow', '久等', '等很久'])) {
      return PolicyIntent.tooSlow;
    }
    if (_matchAny(lower, ['少跑幾輪', '少跑幾', '少幾輪', '跑少一點', '別跑太多輪', '別再 20 輪', '不要跑那麼多輪'])) {
      return PolicyIntent.tooSlow;
    }
    if (_matchAny(lower, ['快一點', '快一些', '趕快', '加速', 'faster'])) {
      return PolicyIntent.tooSlow;
    }

    // 2. 太笨 / 不夠聰明（對應 tier 升級）
    if (_matchAny(lower, ['太笨', '不夠聰明', '不聰明', '笨蛋', '很蠢', 'stupid', 'dumb'])) {
      return PolicyIntent.tooStupid;
    }
    if (_matchAny(lower, ['聰明一點', '更聰明', '厲害一點', '強一點', '升級'])) {
      return PolicyIntent.tooStupid;
    }

    // 3. 太長 / 囉嗦（對應 max_tokens ↓）
    if (_matchAny(lower, ['太長', '太囉嗦', '太冗', '太多字', '講太多', 'too long', '啰嗦', '冗長'])) {
      return PolicyIntent.tooLong;
    }
    if (_matchAny(lower, ['精簡', '簡短', '短一點', '講少一點', 'short'])) {
      return PolicyIntent.tooLong;
    }

    // 4. 太短 / 想更詳細（對應 max_tokens ↑）
    if (_matchAny(lower, ['太短', '詳細一點', '講多一點', '詳細些', 'longer', 'more detail'])) {
      return PolicyIntent.tooShort;
    }

    // 5. 有創意 / 活潑（對應 temperature ↑）
    if (_matchAny(lower, ['有創意', '活潑', '有趣', '變化', 'creative', 'imaginative'])) {
      return PolicyIntent.creative;
    }

    // 6. 嚴謹 / 精確 / 穩定（對應 temperature ↓）
    if (_matchAny(lower, ['嚴謹', '精確', '穩定', '保守', '不要亂', 'deterministic', 'precise'])) {
      return PolicyIntent.deterministic;
    }

    return PolicyIntent.unknown;
  }

  bool _matchAny(String text, List<String> patterns) {
    for (final p in patterns) {
      if (text.contains(p.toLowerCase())) return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════
  // 數值建議生成
  // ═══════════════════════════════════════════════════

  /// 根據意圖 + 內建現況生成 overrides
  ///
  /// 回傳：
  /// - overrides: 寫入 CustomRoutingPolicy.overrides
  /// - description: 給使用者看的具體改動說明（從 X 到 Y）
  ///
  /// 規則（設計文件 §C.2）：
  /// - 太慢：maxTurns 從 20 降到 5（1/4），taskChunkSize 從 20 降到 5
  /// - 太笨：tier 從 tier2 升到 tier1（如果已是 tier1 → 不動，回 null）
  /// - 太長：apiParams.max_tokens 改為 4000（短回應）
  /// - 太短：apiParams.max_tokens 改為 8000（長回應）
  /// - 有創意：apiParams.temperature = 0.7
  /// - 嚴謹：apiParams.temperature = 0.1
  ({Map<String, dynamic> overrides, String changeSummary, String intentLabel})?
      buildOverridesForIntent(PolicyIntent intent, ProviderProfile currentProfile) {
    // [教練 Agent 2026-07-30] 把 named parameter 複製到 local，避免 Dart analyzer 在 switch case 內
    // 對 named parameter 的 flow promotion 怪行為（誤報 null）
    final profile = currentProfile;
    final baseMaxTurns = profile.suggestedMaxTurns ?? 20;
    final baseChunkSize = profile.suggestedTaskChunkSize ?? 7;
    final baseApiParams = profile.apiParams;
    final baseTier = profile.tier;
    switch (intent) {
      case PolicyIntent.tooSlow:
        final newMaxTurns = (baseMaxTurns / 4).ceil().clamp(3, 10);
        final newChunk = (baseChunkSize / 4).ceil().clamp(2, 5);
        final maxTokens =
            (baseApiParams['max_tokens'] as int?) ?? 4000;
        // 短一點回應空間——避免單輪太長
        final newMaxTokens = (maxTokens * 0.7).round().clamp(2000, 8000);
        final hasMaxTokens = baseApiParams.containsKey('max_tokens') ||
            baseApiParams.containsKey('max_completion_tokens');
        return (
          overrides: <String, dynamic>{
            'maxTurns': newMaxTurns,
            'taskChunkSize': newChunk,
            if (hasMaxTokens)
              'apiParams': {
                if (baseApiParams.containsKey('max_tokens'))
                  'max_tokens': newMaxTokens
                else
                  'max_completion_tokens': newMaxTokens,
              },
          },
          changeSummary:
              'maxTurns: $baseMaxTurns → $newMaxTurns（少跑幾輪）\n'
              'taskChunkSize: $baseChunkSize → $newChunk（單次任務更小）'
              '${hasMaxTokens ? '\nmax_tokens: $maxTokens → $newMaxTokens（短一點回應）' : ''}',
          intentLabel: '調降速度',
        );

      case PolicyIntent.tooStupid:
        // tier 升級：tier3 → tier2 → tier1
        final upgradedTier = _upgradeTier(baseTier);
        if (upgradedTier == baseTier) {
          // 已經是 tier1，無法再升
          return null;
        }
        final newMaxTurns = (baseMaxTurns + 5).clamp(15, 30).toInt();
        final newChunk = (baseChunkSize + 5).clamp(5, 20).toInt();
        return (
          overrides: <String, dynamic>{
            'tier': upgradedTier.name,
            'maxTurns': newMaxTurns,
            'taskChunkSize': newChunk,
          },
          changeSummary:
              'tier: ${baseTier.name} → ${upgradedTier.name}（升級能力分層）\n'
              'maxTurns: $baseMaxTurns → $newMaxTurns（給它更多空間）\n'
              'taskChunkSize: $baseChunkSize → $newChunk（單次任務更大）',
          intentLabel: '升級能力',
        );

      case PolicyIntent.tooLong:
        // max_tokens 降到 4000（如果是更長的值）；如果本來就短就不動
        final current = (baseApiParams['max_tokens'] as int?) ??
            (baseApiParams['max_completion_tokens'] as int?) ??
            8000;
        if (current <= 4000) return null;
        final newValue = 4000;
        final isCompletion = baseApiParams.containsKey('max_completion_tokens');
        return (
          overrides: <String, dynamic>{
            'apiParams': {
              if (isCompletion) 'max_completion_tokens': newValue,
              if (!isCompletion) 'max_tokens': newValue,
            },
          },
          changeSummary:
              'max_tokens: $current → $newValue（精簡回應長度）',
          intentLabel: '精簡回應',
        );

      case PolicyIntent.tooShort:
        final current = (baseApiParams['max_tokens'] as int?) ??
            (baseApiParams['max_completion_tokens'] as int?) ??
            2000;
        final newValue = (current * 2).clamp(4000, 16000);
        if (newValue == current) return null;
        final isCompletion = baseApiParams.containsKey('max_completion_tokens');
        return (
          overrides: <String, dynamic>{
            'apiParams': {
              if (isCompletion) 'max_completion_tokens': newValue,
              if (!isCompletion) 'max_tokens': newValue,
            },
          },
          changeSummary:
              'max_tokens: $current → $newValue（給長一點的回應空間）',
          intentLabel: '放長回應',
        );

      case PolicyIntent.creative:
        // temperature 0.3 → 0.7
        // 注意：kimi reasoning model 固定 temperature=1，不允許改
        if (profile.provider.toLowerCase() == 'kimi') {
          return (
            overrides: <String, dynamic>{
              'promptNudge': '請用更有創意、更活潑的方式回答。'
                  '可以加入比喻、故事、不同角度的思考。',
            },
            changeSummary:
                'Kimi 是 reasoning model，temperature 固定為 1 不能改。\n'
                '改為加 promptNudge 提示它「更有創意」。',
            intentLabel: '注入創意提示',
          );
        }
        return (
          overrides: <String, dynamic>{
            'apiParams': {'temperature': 0.7},
          },
          changeSummary:
              'temperature: 0.3 → 0.7（更有變化、更有創意）',
          intentLabel: '提高創意',
        );

      case PolicyIntent.deterministic:
        if (profile.provider.toLowerCase() == 'kimi') {
          return (
            overrides: <String, dynamic>{
              'promptNudge':
                  '請精確、嚴謹回答，避免發散。每次回答盡量一致。',
            },
            changeSummary:
                'Kimi 是 reasoning model，temperature 固定為 1 不能改。\n'
                '改為加 promptNudge 提示它「更精確」。',
            intentLabel: '注入嚴謹提示',
          );
        }
        return (
          overrides: <String, dynamic>{
            'apiParams': {'temperature': 0.1},
          },
          changeSummary:
              'temperature: 0.3 → 0.1（更穩定、更精確）',
          intentLabel: '降低隨機',
        );

      case PolicyIntent.unknown:
        return null;
    }
  }

  /// tier 升一級（tier3 → tier2 → tier1）
  ProviderTier _upgradeTier(ProviderTier current) {
    switch (current) {
      case ProviderTier.tier3:
        return ProviderTier.tier2;
      case ProviderTier.tier2:
        return ProviderTier.tier1;
      case ProviderTier.tier1:
        return current; // 已是最高
    }
  }

  // ═══════════════════════════════════════════════════
  // 草稿生成主流程
  // ═══════════════════════════════════════════════════

  /// 生成 CustomRoutingPolicy 草稿
  ///
  /// 流程（設計文件 §C.2）：
  /// 1. 鎖定 provider（從關鍵字辨識）
  /// 2. 意圖分類（太慢/太笨/太長/...）
  /// 3. 查詢內建 profile 現況
  /// 4. 生成具體數值建議
  /// 5. 太模糊 → 回傳 null（讓呼叫方反問）
  ///
  /// [userDescription] 使用者自然語言描述
  /// [currentProvider] 目前預設/活躍的 provider（如果使用者訊息沒指明 → 用這個）
  /// [currentModel] 目前預設/活躍的 model（可為 null）
  ///
  /// 回傳 CustomRoutingPolicy?：
  /// - null: 需求太模糊或無法解析
  /// - CustomRoutingPolicy: 草稿（isActive = false，等使用者確認）
  Future<CustomRoutingPolicy?> generateDraft(
    String userDescription,
    String currentProvider,
    String? currentModel,
  ) async {
    if (userDescription.trim().isEmpty) return null;

    // 1. 鎖定 provider
    String provider;
    String model;
    final detected = detectProvider(userDescription);
    if (detected != null) {
      provider = detected.$1;
      // 沒指定 model → 用該 provider 的預設 model
      // 透過 getProfile 的 fallback 機制（給 'default' 會拿到 providerDefaults）
      model = currentModel ?? 'default';
    } else {
      // 沒指明 provider → 用 current
      provider = currentProvider;
      model = currentModel ?? 'default';
    }

    // 2. 意圖分類
    final intent = classifyIntent(userDescription);

    // 3. 查詢內建現況
    final profileStore = ProviderProfileStore.instance;
    final currentProfile =
        await profileStore.getProfile(provider, model);

    // 4. 太模糊或無法處理 → 回傳 null
    if (intent == PolicyIntent.unknown) {
      debugPrint('[PolicyGenerator] 意圖無法辨識：$userDescription');
      return null;
    }

    // 5. 根據意圖生成 overrides
    final built = buildOverridesForIntent(intent, currentProfile);
    if (built == null) {
      debugPrint(
          '[PolicyGenerator] 意圖 $intent 對 $provider/$model 無法生成建議（可能已是目標狀態）');
      return null;
    }

    // 6. 生成草稿 id：crp_<provider>_<short_slug>_<timestamp>
    final shortSlug = _generateShortSlug(userDescription, built.intentLabel);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final id = 'crp_${provider}_${shortSlug}_$timestamp';

    // 7. 組裝 description（設計文件 §C.3 範本）
    final description = '${built.intentLabel}：${currentProfile.provider}/${currentProfile.model}'
        '\n原話：$userDescription'
        '\n改動：\n${built.changeSummary}';

    // 8. 組裝草稿（isActive = false，等使用者確認）
    final draft = CustomRoutingPolicy(
      id: id,
      name: _generateName(provider, model, built.intentLabel),
      description: description,
      createdAt: DateTime.now(),
      provider: provider,
      model: model == 'default' ? null : model, // null = 該 provider 下所有 model 都套用
      isActive: false, // 預設 false，等確認
      overrides: built.overrides,
    );

    debugPrint('[PolicyGenerator] 生成草稿：${draft.id} (${draft.name})');
    return draft;
  }

  /// 生成易記名稱（顯示在設定頁）
  String _generateName(String provider, String model, String intentLabel) {
    final providerCapitalized = provider.isEmpty
        ? provider
        : '${provider[0].toUpperCase()}${provider.substring(1)}';
    return '$providerCapitalized · $intentLabel';
  }

  /// 從使用者原話生成 short slug（用於 id）
  String _generateShortSlug(String description, String intentLabel) {
    final text = '$intentLabel $description'.toLowerCase();

    // 規則式提取關鍵詞
    if (text.contains('慢') || text.contains('few') || text.contains('fast')) {
      return 'fast';
    }
    if (text.contains('笨') || text.contains('聰明') || text.contains('default')) {
      return 'default';
    }
    if (text.contains('長') || text.contains('detail') || text.contains('long')) {
      return 'long';
    }
    if (text.contains('短') || text.contains('short')) {
      return 'short';
    }
    if (text.contains('創意') || text.contains('creative')) {
      return 'creative';
    }
    if (text.contains('嚴謹') || text.contains('精確') || text.contains('precise')) {
      return 'precise';
    }
    // fallback：取原話前幾個字
    final cleaned = description
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fff]+'), '_')
        .toLowerCase();
    return cleaned.length > 20 ? cleaned.substring(0, 20) : cleaned;
  }

  // ═══════════════════════════════════════════════════
  // 觸發偵測：給 chat_controller 用
  // ═══════════════════════════════════════════════════

  /// 判斷訊息是否應該觸發 PolicyGenerator
  ///
  /// 觸發條件（任一命中）：
  /// - 包含「自訂」「調用原則」「自訂原則」「調用模式」
  /// - 包含意圖關鍵字（太慢/少跑幾輪/...）+ provider 關鍵字
  static bool shouldTrigger(String userMessage) {
    final lower = userMessage.toLowerCase();

    // 0. [教練 Agent 2026-08-17] 排除條款——工具/工作指令優先。
    // 訊息帶 canvas_* / MCP 工具呼叫＝任務指令，不是原則設定。
    // 之前「模型升級驗收：...canvas_place...」被誤攔成「升級能力」
    // 原則 draft，任務根本沒進 Agent Loop（使用者 抓包）。
    if (_matchAnyStatic(lower, [
      'canvas_place', 'canvas_connect', 'canvas_get', 'canvas_add',
      'canvas_update', 'canvas_remove', 'canvas_get_state',
      'canvas_get_topology', 'canvas_get_node_params', 'canvas_clear',
      'read_app_log', 'run_terminal', 'patch_source_file',
    ])) {
      return false;
    }

    // 1. 明確提到「自訂原則」
    if (_matchAnyStatic(lower, ['自訂', '自定義', '調用原則', '調用模式', '自訂原則', 'custom policy', 'custom routing'])) {
      return true;
    }

    // 2. 意圖關鍵字 + provider 關鍵字（雙重命中）
    final intent = instance.classifyIntent(userMessage);
    if (intent != PolicyIntent.unknown) {
      final providerHit = instance.detectProvider(userMessage);
      if (providerHit != null) return true;
    }

    // 3. 純意圖關鍵字（沒指明 provider，但有「少跑幾輪」這類明確意圖）
    if (_matchAnyStatic(lower, ['少跑幾輪', '少跑幾', '跑少一點', '別再 20 輪'])) {
      return true;
    }

    return false;
  }

  static bool _matchAnyStatic(String text, List<String> patterns) {
    for (final p in patterns) {
      if (text.contains(p.toLowerCase())) return true;
    }
    return false;
  }
}
