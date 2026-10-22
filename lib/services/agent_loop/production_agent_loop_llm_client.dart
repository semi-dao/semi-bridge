/// Production LLM client for AgentLoop — 包裝 ApiService
///
/// 把 ApiService.complete() 包成 AgentLoopLLMClient 介面。
/// 與 brain pipeline ProductionPipelineLLMClient 同路線：
/// 用 ApiService.complete() 送 system+user 拿純文字，不走 function calling。
///
/// [2026-07-18] multimodal vision 支援：
/// 當 messages 中有 content 是 List（含 image_url block）時，
/// 改用 ApiService.completeWithMessages() 送完整 messages array，
/// 讓 LLM 真正看到截圖像素。
///
/// [教練 Agent P0.5b-fix 2026-08-07] 修：AgentLoop 切換模型的 bug。
/// 之前 model 是建構子時決定一次（甚至 null），整個 AgentLoop 期間都鎖死。
/// 現在：每次 complete() 都動態讀取使用者選擇的 provider 和對應 model。
/// - 使用者選了具體雲端 provider（例如 gemini）→ 永遠用 gemini
/// - 使用者選了「預設」→ 用 ProviderRouter 路由結果（原本行為）
/// - 使用者選了 local → 用本地 model

import 'agent_loop.dart';
import '../api_service.dart';
import '../brand_ladder_router.dart'; // [小葵 2026-09-20] 品牌階梯路由
import '../budget_ledger.dart'; // [小葵 2026-09-21] cost 防火牆——chat loop 過帳
import '../paid_action_gate.dart'; // [小葵 2026-09-21] PaidActionKind.llm
import '../storage_service.dart';
import '../provider_router.dart';
import '../provider_registry.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProductionAgentLoopLLMClient implements AgentLoopLLMClient {
  final String? model;

  /// [T11② 2026-10-17] 最近一次路由結果——雲端率儀表資料源。
  /// AgentLoop 在輪次結束後讀取並 updateTurnMeta 進 event_ledger。
  /// [T12-⑥ 2026-10-17] 去 static——聊天與畫布兩迴圈並行時 static 互
  /// 踩（雲端率記錯回合，Fable 指認）。改實例欄位，由 interface 預設
  /// getter（空 Map）統一合約。
  @override
  Map<String, dynamic> lastRoute = {};
  ApiCompletionReceipt? _lastReceipt;

  /// [教練 Agent 2026-08-08] 輪數計數器——追蹤 complete() 被呼叫幾次
  /// 預設模式下，第 2 輪起如果還在本地，就升級到雲端
  int _callCount = 0;

  /// [教練 Agent 2026-08-08] 教練模式——取得原生 Agent最後回覆
  String? get lastAgentReplyText => null;

  /// [教練 Agent 2026-08-08] 強制升級到雲端——本地 timeout 後呼叫
  void forceUpgradeToCloud() {
    _callCount = 2; // 觸發 _resolveModel 裡的 >= 2 升級邏輯
  }

  /// 只代表剛完成的那次 LLM request；不從 Settings 推測。
  ApiCompletionReceipt? get lastReceipt => _lastReceipt;

  ProductionAgentLoopLLMClient({this.model});

  /// [教練 Agent P0.5b-fix 2026-08-07] 動態解析要使用的 model。
  /// 優先順序：
  /// 1. 構造時傳入的 model（測試 mock 用）
  /// 2. 使用者選的雲端 provider 對應的 model（鎖定使用者選擇——階梯不動）
  /// 3. 品牌階梯路由（[小葵 2026-09-20]：預設模式從最便宜起步，信號觸發升級）
  /// 4. ProviderRouter 路由結果（舊行為，作為 fallback）
  Future<String?> _resolveModel() async {
    if (model != null) return model;

    _callCount++;
    final userProvider = await StorageService.getProvider();

    // [T7④ 補刀 2026-10-16] localOnly 否決明選雲端——與 chat_controller 同步
    // （盲測實證：明選 openai+失效 token 繞過路由層，localOnly 必須全域一票否決）
    if (await StorageService.getLocalOnly()) {
      final localModel = await StorageService.getApiModel(provider: 'local');
      _logTrace('local_only_veto', 'local', localModel ?? '');
      return localModel;
    }

    // 使用者明確選了雲端 provider → 鎖定（不套階梯）
    if (userProvider != null &&
        userProvider != 'local' &&
        userProvider != 'default') {
      final userModel = await StorageService.getApiModel(provider: userProvider);
      if (userModel != null && userModel.trim().isNotEmpty) {
        final resolved = userModel.trim();
        _logTrace('user_locked', userProvider, resolved);
        return resolved;
      }
    }

    // [Blue 令 2026-10-20] 「預設」= 本地優先＋自動觸發雲端——
    // 但只在「使用者有安裝本地模型」時啟動。上游 chat_controller 已依
    // 意圖 route()（閒聊→本地、執行/專案→雲端）並 setCurrent；這裡
    // 尊重路由結果：本地路且本地 server 活著 → 用本地模型；否則落到
    // 下方品牌階梯（雲端）。route() 的安全閥（本地沒跑→雲端）天然
    // 處理「沒裝本地模型」的情況。
    if (userProvider == 'default' || userProvider == null) {
      // [Blue 令 2026-10-20 活預設] 此 client 是對話迴圈——chat 角色映射優先。
      // 上游 chat_controller 已按意圖 setCurrent；這裡對 chat/casual 輪
      // 檢查 chat 角色有沒有指定鑰匙（例：chat=glm），有 → 鎖定該鑰匙。
      final chatRoleProvider = await StorageService.getRoleProvider('chat');
      if (chatRoleProvider != null && chatRoleProvider.isNotEmpty) {
        final token =
            await StorageService.getToken(provider: chatRoleProvider);
        if (token != null && token.trim().isNotEmpty) {
          final m = await StorageService.getApiModel(provider: chatRoleProvider);
          ProviderRouter.instance.setCurrent(RoutedProvider(
            target: RoutedTarget.cloud,
            providerId: chatRoleProvider,
            reason: '活預設 chat → $chatRoleProvider',
          ));
          _logTrace('role_map_chat', chatRoleProvider, m ?? '');
          if (m != null && m.trim().isNotEmpty) return m.trim();
        }
      }

      final routed = ProviderRouter.instance.current;
      if (routed != null && routed.isLocal) {
        // 再探一次本地 server——route() 的探測可能已是幾秒前
        await ProviderRouter.instance.probeLocalServerNow();
        if (ProviderRouter.instance.localServerAvailable) {
          final localModel =
              await StorageService.getApiModel(provider: 'local');
          if (localModel != null && localModel.trim().isNotEmpty) {
            _logTrace('default_local_first', 'local', localModel);
            return localModel;
          }
        }
      }
    }

    // [教練 Agent 2026-08-09] Agent Loop 一律走雲端——本地 gemma-4-e4b 太弱
    // reasoning token 吃光 content，Agent Loop prompt-based JSON 解析失敗。
    // 只在使用者明確選 local 時才走本地。
    final isLocalMode = userProvider == 'local';

    if (!isLocalMode) {
      // [小葵 2026-09-20 品牌階梯] default 模式：先看階梯有沒有選定的 model
      // （上輪信號觸發的升級會留在這裡），沒有的話取最便宜的起點。
      String? ladderModel = BrandLadderRouter.instance.activeModel;

      // [教練 Agent 2026-08-09] macOS 上 token 存在 SharedPreferences，不是 secure storage
      // key 格式：api_token_v2_<provider>，model 格式：api_model_<provider>
      final prefs = await SharedPreferences.getInstance();
      final knownCloudProviders = ProviderRouter.cloudFallbackOrder; // [T7⑤] 統一常數
      // 階梯模式首選：根據有 token 的 provider 順序，找第一個階梯裡有 key 的
      for (final pid in knownCloudProviders) {
        final token = prefs.getString('api_token_v2_$pid');
        if (token == null || token.trim().isEmpty) continue;
        // 這個 provider 有 key
        // 如果階梯已有 active model 且 brand 對得上 → 用它
        if (ladderModel != null && ladderModel.isNotEmpty) {
          // 模糊判斷 model 屬於這個 provider
          if (pid == 'openai' && ladderModel.toLowerCase().startsWith('gpt')) {
            ProviderRouter.instance.setCurrent(RoutedProvider(
              target: RoutedTarget.cloud,
              providerId: pid,
              reason: 'BrandLadder: $ladderModel',
            ));
            _logTrace('brand_ladder', pid, ladderModel);
            return ladderModel;
          }
          if (pid == 'glm' && ladderModel.toLowerCase().startsWith('glm')) {
            ProviderRouter.instance.setCurrent(RoutedProvider(
              target: RoutedTarget.cloud,
              providerId: pid,
              reason: 'BrandLadder: $ladderModel',
            ));
            _logTrace('brand_ladder', pid, ladderModel);
            return ladderModel;
          }
          if (pid == 'claude' && ladderModel.toLowerCase().startsWith('claude')) {
            ProviderRouter.instance.setCurrent(RoutedProvider(
              target: RoutedTarget.cloud,
              providerId: pid,
              reason: 'BrandLadder: $ladderModel',
            ));
            _logTrace('brand_ladder', pid, ladderModel);
            return ladderModel;
          }
          if (pid == 'gemini' && ladderModel.toLowerCase().startsWith('gemini')) {
            ProviderRouter.instance.setCurrent(RoutedProvider(
              target: RoutedTarget.cloud,
              providerId: pid,
              reason: 'BrandLadder: $ladderModel',
            ));
            _logTrace('brand_ladder', pid, ladderModel);
            return ladderModel;
          }
        }
        // 沒階梯或 brand 對不上 → 用這個 provider 的階梯起點（最便宜）
        final ladder = _getLadderForBrand(pid);
        if (ladder != null) {
          ProviderRouter.instance.setCurrent(RoutedProvider(
            target: RoutedTarget.cloud,
            providerId: pid,
            reason: 'BrandLadder init: ${ladder.cheapest}',
          ));
          BrandLadderRouter.instance.reset(pid);
          _logTrace('brand_ladder_init', pid, ladder.cheapest);
          return ladder.cheapest;
        }
        // 沒階梯定義的 provider → fallback 用儲存的 model
        final m = prefs.getString('api_model_$pid');
        if (m != null && m.trim().isNotEmpty) {
          ProviderRouter.instance.setCurrent(RoutedProvider(
            target: RoutedTarget.cloud,
            providerId: pid,
            reason: 'Agent Loop prefs → $pid',
          ));
          _logTrace('agent_loop_prefs', pid, m);
          return m.trim();
        }
      }

      // fallback：透過 StorageService API（內部也會讀 prefs）
      for (final pid in knownCloudProviders) {
        final token = await StorageService.getToken(provider: pid);
        if (token != null && token.trim().isNotEmpty) {
          final m = await StorageService.getApiModel(provider: pid);
          if (m != null && m.trim().isNotEmpty) {
            ProviderRouter.instance.setCurrent(RoutedProvider(
              target: RoutedTarget.cloud,
              providerId: pid,
              reason: 'Agent Loop StorageService → $pid',
            ));
            _logTrace('agent_loop_ss', pid, m);
            return m.trim();
          }
        }
      }

      // 最後 fallback：動態探測
      final best = await ProviderRegistry.instance.selectBestCloud();
      if (best != null && best.availableModels.isNotEmpty) {
        final cloudModel = best.availableModels.first;
        ProviderRouter.instance.setCurrent(RoutedProvider(
          target: RoutedTarget.cloud,
          providerId: best.providerId,
          reason: 'Agent Loop discover → ${best.providerId}',
        ));
        _logTrace('agent_loop_cloud', best.providerId, cloudModel);
        return cloudModel;
      }
    }

    _logTrace('router_default', userProvider ?? 'null', null);
    return null;
  }

  /// [小葵 2026-09-20 品牌階梯] 從 brand id 拿階梯定義
  BrandLadder? _getLadderForBrand(String pid) {
    switch (pid) {
      case 'openai':
        return const BrandLadder(
          brand: 'openai',
          rungs: [
            'gpt-4o-mini',
            'gpt-4o',
            'gpt-5-mini',
            'gpt-5',
            'gpt-6-astra',
          ],
        );
      case 'glm':
        return const BrandLadder(
          brand: 'glm',
          rungs: ['glm-4.5', 'glm-5', 'glm-5.2', 'glm-5.3'],
        );
      case 'claude':
        return const BrandLadder(
          brand: 'claude',
          rungs: ['claude-haiku-4-5', 'claude-sonnet-4-6', 'claude-opus-4-7'],
        );
      case 'gemini':
        return const BrandLadder(
          brand: 'gemini',
          rungs: ['gemini-2.5-flash', 'gemini-3.5-flash', 'gemini-3.5-pro'],
        );
      default:
        return null;
    }
  }

  /// [教練 Agent P0.5b-debug 2026-08-07] 追蹤每次 LLM 呼叫的 provider/model
  /// [教練 Agent 2026-08-08] 移除 file I/O，保留 debugPrint（kDebugMode 時才輸出）
  void _logTrace(String reason, String? provider, String? modelResolved) {
    final timestamp = DateTime.now().toIso8601String();
    final line =
        '$timestamp\t$reason\tprovider=$provider\tresolved_model=$modelResolved\tconstructed_model=$model';
    if (kDebugMode) {
      debugPrint('[AgentLoopLLMClient] $line');
    }
  }

  @override
  Future<String> complete(List<Map<String, dynamic>> messages) async {
    final resolvedModel = await _resolveModel();

    // [小葵 2026-09-21 cost 防火牆] chat agent loop 過帳——
    // 9/21 astra 生日問答 5 題燒 $9：主對話的 LLM 呼叫完全沒進 BudgetLedger，
    // cost 防火牆只攔 workflow 節點、chat loop 是繞過它的。現在每一輪都記帳。
    final ledgerId = await BudgetLedger.instance.record(
      kind: PaidActionKind.llm,
      intent: 'chat:${resolvedModel ?? 'auto'}',
      prompt: messages.isNotEmpty
          ? messages.last['content']?.toString() ?? ''
          : '',
    );

    try {
      final result = await _completeInner(messages, resolvedModel);
      // [T11②] 記錄實際路由（儀表資料源）
      final provider = providerOfModel(resolvedModel);
      lastRoute = {
        'provider': provider,
        'model': resolvedModel ?? 'auto',
        'is_local': provider == 'local',
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
      await PaidActionGate.settle(ledgerId, ok: true);
      // [T7② 2026-10-16 編織線] 成功回饋階梯——連續失敗歸零（advance 原本接了線沒人通電）
      _ladderFeedback(success: true, model: resolvedModel);
      return result;
    } catch (e) {
      await PaidActionGate.settle(ledgerId, ok: false, error: e.toString());
      // [T7② 2026-10-16 編織線] 失敗回饋階梯——advance() 決定升一階或跳旗艦，
      // 下一輪 _resolveModel() 讀 activeModel 自然吃到
      _ladderFeedback(success: false, model: resolvedModel);
      rethrow;
    }
  }

  String? _lastRouteProvider;

  /// [T11②] model 名 → provider 歸屬（儀表用，模糊前綴對映）
  static String providerOfModel(String? m) {
    if (m == null || m.isEmpty) return 'auto';
    final s = m.toLowerCase();
    if (s.startsWith('gpt') || s.startsWith('o1') || s.startsWith('o3')) return 'openai';
    if (s.startsWith('gemini')) return 'gemini';
    if (s.startsWith('claude')) return 'anthropic';
    if (s.startsWith('glm')) return 'zai';
    if (s.contains('e4b') || s.contains('gemma') || s.contains('k1') ||
        s.contains('eg2') || s.contains('local')) return 'local';
    return 'cloud';
  }

  // [T7② 2026-10-16 編織線] 階梯回饋通道——BrandLadderRouter.advance() 的唯一通電點
  int _consecutiveLLMFailures = 0;
  void _ladderFeedback({required bool success, String? model}) {
    final routed = ProviderRouter.instance.current;
    if (routed == null || routed.target != RoutedTarget.cloud) return; // local 無階梯
    if (success) {
      _consecutiveLLMFailures = 0;
      return;
    }
    _consecutiveLLMFailures++;
    final m = model ?? BrandLadderRouter.instance.activeModel;
    if (m == null) return;
    BrandLadderRouter.instance.advance(
      resolvedProvider: routed.providerId,
      currentModel: m,
      signal: TaskSignal(
        lastCallFailed: true,
        consecutiveFailures: _consecutiveLLMFailures,
      ),
    );
  }

  Future<String> _completeInner(
      List<Map<String, dynamic>> messages, String? resolvedModel) async {
    // 檢查是否有 multimodal content（content 是 List 而非 String）
    final hasMultimodal = messages.any((m) {
      final content = m['content'];
      return content is List;
    });

    if (hasMultimodal) {
      // multimodal 路徑：仍走 completeWithMessages（純文字路徑已不適用）
      _lastReceipt = null;
      return ApiService.completeWithMessages(
        messages: messages,
        model: resolvedModel,
      );
    }

    // [小葵 2026-09-20 cache 工程] 真多輪 messages array 直送——
    // 過去壓扁成「system + 單條 user」的策略會破壞 prefix 穩定性，
    // provider 端 prompt cache 命中率趨近 0（9/19 astra cache writes $35 元兇）。
    // 現在：保持 messages 陣列結構，prefix 凍結 + 歷史 append，
    // 讓 cache 真正能命中——同樣 179 輪對話預期砍掉 ~90% cache writes。
    final provider = await StorageService.getProvider() ?? '';
    if (provider == 'local' && _joinedLength(messages) > 28000) {
      // [教練 Agent 2026-08-02] 本地模型保護：context 超過限制時截斷舊輪
      debugPrint('[AgentLoopLLMClient] local prompt 截斷');
      _truncateOldTurns(messages);
    } else if (provider != 'local' && _joinedLength(messages) > 24000) {
      // [小葵 2026-09-21→09-22] 雲端 context 壓縮——9/21 astra $9 事件第三刀：
      // 歷史 194 則每輪重送 31K+ tokens，cache 又因檢索注入破壞 prefix 而 miss。
      // [09-22 打鐵趁熱] 門檻 60K→24K 字元：實測 15.5K tokens 已是大戶，
      // 60K 等於放任 30K+ tokens 空轉。24K（~12K tokens）以上就壓。
      compressCloudContext(messages);
    }

    // [小葵 2026-09-24 Blue 三修之二] receipt 接回——9-21 cache 工程把主路徑改走
    // completeWithMessagesRaw（純字串）後 _lastReceipt 永遠是 null，對話泡泡的
    // 模型形別從此消失。這裡還原 receipt：provider/model 用本次實際解析值
    // （與 raw 內部 _effectiveProvider + _defaultModelFor 同源，不回讀 Settings）。
    final receiptProvider = await StorageService.getProvider() ?? '';
    final receiptModel =
        resolvedModel ?? await ApiService.defaultModelFor(receiptProvider);
    final rawText = await ApiService.completeWithMessagesRaw(
      messages: messages,
      model: resolvedModel,
    );
    final usedLocalFallback =
        rawText.contains('已自動改用本地模型完成');
    _lastReceipt = ApiCompletionReceipt(
      text: rawText,
      provider: receiptProvider,
      model: receiptModel,
      usedLocalFallback: usedLocalFallback,
    );
    return rawText;
  }

  /// [小葵 2026-09-21] 雲端 context 壓縮（就地修改 messages）——
  /// 不動儲存的對話歷史（conversations.json 永不刪），只瘦身「這次要送的」。
  /// L1 分段 + L3 確定性事實層（user 全文逐字 + assistant 訊號行逐字）。
  /// L2 LLM 摘要暫不接（成本與延遲考量）——事實層已實測保住 11/14 細節。
  @visibleForTesting
  void compressCloudContext(List<Map<String, dynamic>> messages) {
    const keepRecent = 8;
    const minMiddle = 12; // 中間段至少 12 則才值得壓（避免短對話頻繁重壓）
    if (messages.length <= keepRecent + minMiddle) return;

    final locked = <Map<String, dynamic>>[];
    var i = 0;
    if (messages.first['role'] == 'system') {
      locked.add(messages[0]);
      i = 1;
    }
    if (i < messages.length) {
      locked.add(messages[i]); // 首則 user 任務（任務原意永遠保留）
      i++;
    }
    final recentStart = (messages.length - keepRecent).clamp(i, messages.length);
    if (recentStart - i < minMiddle) return; // 中間段太薄，不壓

    final middle = messages.sublist(i, recentStart);

    // 事實層 A：user 訊息全文（教練指示攜帶全部決策——實測 23K 字保住全部決策題）
    final userBuf = StringBuffer();
    // 事實層 B：assistant 訊號行（hash/全大寫檔名/決策關鍵字）
    final ledgerBuf = StringBuffer();
    final hashRe = RegExp(r'\b[0-9a-f]{7,40}\b');
    final capsRe = RegExp(r'\b[A-Z][A-Z0-9_]{8,}\b');
    final signalRe =
        RegExp('撤回|不實|拍板|閥|重試|重複|兩小時|抓包|上線|已修|移除|催');
    for (final m in middle) {
      final role = m['role']?.toString() ?? '';
      final content = m['content']?.toString() ?? '';
      if (role == 'user') {
        userBuf.writeln('== [user 原文] ==');
        userBuf.writeln(content);
      } else {
        for (final line in content.split('\n')) {
          final t = line.trim();
          if (t.isEmpty || t.length > 600) continue;
          if (hashRe.hasMatch(t) || capsRe.hasMatch(t) || signalRe.hasMatch(t)) {
            ledgerBuf.writeln(t);
          }
        }
      }
    }
    var ledgerStr = ledgerBuf.toString();
    if (ledgerStr.length > 20000) ledgerStr = ledgerStr.substring(0, 20000);

    final compressed =
        '[歷史摘要] 以下為較早對話的壓縮保存（原文永不刪除，僅縮小本次送出的 context）。\n\n'
        '== 事實層A：user 訊息全文（逐字）==\n$userBuf\n'
        '== 事實層B：assistant 關鍵行（hash/檔名/決策訊號，逐字）==\n$ledgerStr';

    final rebuilt = <Map<String, dynamic>>[
      ...locked,
      {'role': 'user', 'content': compressed},
      ...messages.sublist(recentStart),
    ];
    messages
      ..clear()
      ..addAll(rebuilt);
    debugPrint('[AgentLoopLLMClient] 雲端 context 壓縮：'
        '${middle.length} 則中間歷史 → 摘要+事實層（${compressed.length} 字元）');
  }

  int _joinedLength(List<Map<String, dynamic>> msgs) {
    var n = 0;
    for (final m in msgs) {
      n += (m['content']?.toString() ?? '').length;
    }
    return n;
  }

  /// [小葵 2026-09-20 cache 工程] 本地模型超過限制時截斷中間舊輪——
  /// 保留 system + 首兩條 user/assistant，最後保留 N 條。
  /// 注意：從尾部往前刪，不打散前綴。
  void _truncateOldTurns(List<Map<String, dynamic>> msgs) {
    if (msgs.length <= 10) return;
    final tailKeep = 6;
    final first = msgs.sublist(0, 2); // system + initial user task
    final tail = msgs.sublist(msgs.length - tailKeep);
    final truncated = <Map<String, dynamic>>[]
      ..addAll(first)
      ..add({
        'role': 'user',
        'content':
            '〔歷史摘要〕之前 ${msgs.length - tailKeep - 2} 則訊息已省略以節省本地模型 context 空間。',
      })
      ..addAll(tail);
    msgs
      ..clear()
      ..addAll(truncated);
    debugPrint('[AgentLoopLLMClient] 本地模型截斷為 ${truncated.length} 則');
  }
}
