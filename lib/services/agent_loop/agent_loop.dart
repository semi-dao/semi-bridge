/// Agent Loop 引擎
///
/// [2026-07-19 使用者拍板] 與 Hermes 對齊——無 maxTurns 上限 + 可插嘴
///
/// 核心設計（Hermes 模式）：
/// - 不設 maxTurns 上限——LLM 自己判斷何時完成
/// - 安全閥：hardMaxTurns=200（防 LLM 真的壞掉死循環）
/// - LLM 回覆不含 tool call = 自然結束（就這麼簡單）
/// - 不需要 forceToolUse nudge——靠 system prompt 引導 LLM 用工具
/// - 不需要完成偵測關鍵詞——信任 LLM 的判斷
/// - 使用者可隨時插嘴——訊息注入 queue，每輪開始前檢查
/// - 每輪有進度回調，UI 可即時顯示
///
/// 與 Hermes agent loop 的差異：
/// - Hermes 用 OpenAI function calling（原生 tool_use）
/// - 橋樑 App 用 prompt-based JSON（ApiService 不支援 function calling）
/// - 格式與 brain pipeline L3 一致：分隔符 + safeJsonParse

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import '../local_model_scheduler.dart'; // [小葵 2026-10-01] 離合器活躍訊號
import '../storage_service.dart';
import '../causal/causal_ledger_service.dart'; // [因果引擎 L1] 介入帳本
import '../api_usage_tracker.dart'; // [小葵 2026-09-21 收尾驗收] per-task token 歸因
import '../decision/k1_gatekeeper.dart'; // [小葵 2026-09-21 R3] K1 守門員（K1Decision/K1Labels 型別；實際呼叫已移 InjectionPreparer）
import '../decision/decision_head.dart' show K1Labels, K1Decision; // [小葵 2026-09-22] 輕裝路徑
import '../vector_db/hybrid_search_service.dart'; // [R3→M1] SearchMode 等型別（K1 檢索已移 InjectionPreparer）
import '../brain_container/event_ledger.dart'; // [M0] 事件日誌
import '../brain_container/inject/inject_pipeline.dart'; // [M0] 記憶注入
import '../brain_container/injection_preparer.dart'; // [M1] K1+M0 單一注入入口
import 'compass_medic.dart'; // [軍醫 W3/W4] 羅盤出診＋傷口自癒
import 'agent_loop_tools/tool_seek_tool.dart'; // [小葵 2026-09-22] 精靈任務配備
import 'agent_safety.dart'; // [D002] 工具確認
import 'agent_tool.dart';
import 'agent_tool_call_parser.dart';
import 'agent_tool_registry.dart';
import 'context_store.dart' as context_store; // [Spike 002] CLM 形狀 context 管理
import 'production_agent_loop_llm_client.dart';

/// Agent Loop 結果
class AgentLoopResult {
  /// 最終回覆給使用者的文字
  final String reply;

  /// 每一輪的紀錄
  final List<AgentLoopTurn> turns;

  /// 是否因達到輪數上限而終止
  final bool hitTurnLimit;

  /// 是否被使用者取消
  final bool cancelled;

  /// 總耗時
  final Duration elapsed;

  const AgentLoopResult({
    required this.reply,
    required this.turns,
    required this.hitTurnLimit,
    required this.cancelled,
    required this.elapsed,
  });

  int get toolCallCount => turns.where((t) => t.toolCall != null).length;
}

/// 進度回調
/// 每輪開始/結束時呼叫，UI 可用來顯示「正在搜尋...」「正在讀取網頁...」等
typedef AgentLoopProgressCallback =
    void Function(
      int turnIndex,
      int maxTurns,
      AgentToolCall? toolCall,
      AgentToolResult? toolResult,
      String llmOutput,
    );

/// [教練 Agent 2026-08-07] 階段回調——即時進度回饋
/// 在 LLM 呼叫前、tool 執行前、timeout 時觸發，
/// 讓使用者不再看著黑箱等待。
///
/// stage 值：
/// - 'thinking'  — LLM 正在思考
/// - 'tool_start' — 即將執行工具（toolName 附帶）
/// - 'tool_done'  — 工具執行完成
/// - 'timeout'   — LLM 或 tool 超時
/// - 'error'     — 發生錯誤（detail 附帶）
typedef AgentLoopStageCallback =
    void Function(
      String stage, {
      String? toolName,
      String? detail,
    });

/// 使用者插嘴回調——當使用者在 loop 運行中發送訊息時觸發
/// UI 可以用這個顯示「使用者插嘴了：xxx」
typedef AgentLoopUserMessageCallback = void Function(String userMessage);

/// LLM 呼叫介面——AgentLoop 不直接依賴 ApiService
/// 由 chat_controller 注入實作
abstract class AgentLoopLLMClient {
  /// 發送 messages 到 LLM，回傳純文字
  /// messages 格式：[{role: 'system'|'user'|'assistant', content: '...'}]
  /// content 可以是 String（純文字）或 List（multimodal，含 image_url）
  Future<String> complete(List<Map<String, dynamic>> messages);
}

/// [2026-07-20] 工具序列重複 pattern 偵測結果
class _ToolPatternResult {
  final List<String> pattern;
  final int repetitions;
  _ToolPatternResult(this.pattern, this.repetitions);
}

/// Agent Loop 引擎
class AgentLoop {
  /// [小葵 2026-09-22] 最近一次 K1 判定——輕裝路徑判斷用
  K1Decision? _lastK1Decision;

  /// turn_id 產生器：時間戳＋6 位隨機後綴——防同毫秒撞號。
  /// [小葵 2026-10-10 M1]（Fable delta）兩條 AgentLoop 迴圈同毫秒落兩筆
  /// 會撞 id；appendReaction 以 ref_turn_id 去重，撞號會讓第二輪永遠記
  /// 不到反應。
  static final Random _turnIdRandom = Random();
  static String _newTurnId() {
    const chars = 'abcdef0123456789';
    final suffix = List.generate(
      6,
      (_) => chars[_turnIdRandom.nextInt(16)],
    ).join();
    return 'turn_${DateTime.now().millisecondsSinceEpoch}_$suffix';
  }

  /// [Blue 拍板 2026-09-18] 與 Hermes（小葵）對齊——無固定輪數限制，對 agent 有信心。
  /// 剩餘空間 = 物理上限（context window、API 額度），不是人為輪數。
  /// 安全閥只留超大值，純防 LLM 真的壞掉死循環燒錢（正常 agent 永遠碰不到）。
  /// [小葵] Hermes 同款理念：臨界前的收斂靠禮儀（compass: agent.mind.turnLimitEtiquette
  /// 三級收口：150 收斂 / 180 續接工單），不靠硬閥。
  static const int hardMaxTurns = 100000;

  final AgentToolRegistry toolRegistry;
  final AgentLoopLLMClient llmClient;

  /// [D002 2026-08-10] 安全確認 callback——實例欄位，所有 run() 自動生效
  /// 設定方式：UI 層在初始化時 agentLoop.onToolConfirmation = ...
  /// 回傳 true = 確認執行；false = 拒絕
  Future<bool> Function({
    required String toolName,
    required Map<String, dynamic> args,
  })? onToolConfirmation;

  /// 使用者插嘴 message queue
  /// loop 運行中使用者發送訊息時，注入這裡，每輪 LLM 呼叫前會 drain
  final Queue<String> _userMessageQueue = Queue<String>();

  /// [因果引擎 L1] 本輪任務的情境摘要——run() 開頭由 userMessage 建立，
  /// 介入帳本記帳時作為 contextDigest（L3 反饋查詢的匹配鍵）
  String? _causalContextDigest;

  /// [軍醫 W3/W4 2026-09-17] 同工具連續失敗計數（撞牆出診觸發器）
  final Map<String, int> _medicFailStreak = {};

  /// [軍醫 W3] 待注入下一輪的救急藥卡（撞牆出診佇列）
  String? medicRescueQueued;

  /// [Spike 002 2026-10-13] CLM 形狀 context store——per-run 生命週期。
  /// 每次 run() 開頭重建，context_recall 工具動態註冊（見 _runInner）。
  context_store.ContextStore _contextStore = context_store.ContextStore();

  /// [跨輪層 2026-10-13] session 級 store——跨 run 活著，對話歷史壓縮用。
  /// 切換/新建對話時由 chat_controller 呼叫 resetSessionStore() 重置。
  context_store.ContextStore _sessionStore = context_store.ContextStore();

  /// [跨輪層] 給 chat_controller 的歷史壓縮入口（CLM 形狀：封存+指針+讀回）。
  List<Map<String, String>> compactHistoryForSession(
      List<Map<String, String>> history) {
    return context_store.ContextStore.compactHistory(_sessionStore, history);
  }

  /// [跨輪層] 新對話/切換對話時重置 session store（舊指針作廢）。
  void resetSessionStore() {
    _sessionStore = context_store.ContextStore();
  }

  AgentLoop({required this.toolRegistry, required this.llmClient});

  /// [教練 Agent 2026-08-08] 教練模式——當前 run 的 turn 列表快照
  List<AgentLoopTurn> _currentTurns = [];
  List<AgentLoopTurn> get turnsForDebug => _currentTurns;

  /// 使用者插嘴——把訊息排入 queue，下一輪 LLM 呼叫前會看到
  void injectUserMessage(String message) {
    _userMessageQueue.add(message);
    debugPrint('[AgentLoop] 使用者插嘴已排入: ${message.length} 字');
  }

  /// 執行 agent loop
  ///
  /// [systemPrompt] — 系統提示（含工具描述）
  /// [userMessage] — 使用者訊息（已做分隔符轉義）
  /// [maxTurns] — 最大輪數（預設不限制，安全閥 hardMaxTurns=200）
  /// [onProgress] — 每輪進度回調
  /// [onUserMessage] — 使用者插嘴回調
  /// [isCancelled] — 檢查是否被取消（每輪開始前檢查）
  Future<AgentLoopResult> run({
    required String systemPrompt,
    required String userMessage,
    int maxTurns = hardMaxTurns,
    AgentLoopProgressCallback? onProgress,
    AgentLoopStageCallback? onStage,
    AgentLoopUserMessageCallback? onUserMessage,
    bool Function()? isCancelled,
    // [教練 Agent 2026-08-20] 付費工具閘門——true 時 generate_image 等付費生成工具
    // 一律拒絕執行（機器訊息喚醒的輪次專用）。能力不拔：使用者親自發言的
    // 輪次為 false，照常走 confirmationRequired 確認框流程。
    bool prohibitPaidTools = false,
    // [D002 2026-08-10] onToolConfirmation 已提升為實例欄位，所有 run() 自動生效
  }) async {
    // [小葵 2026-09-21 收尾驗收] per-task 歸因 wrapper——
    // 不動內部多個 return 點，外層記帳：token 差額+時長+輪數。
    // 資料源：ApiUsageTracker（真值優先，收尾驗收刀已升級）。
    final tracker = ApiUsageTracker.instance;
    final tokenBefore = tracker.todayTotalTokens;
    final wallClockBefore = DateTime.now();
    // [小葵 2026-09-22 打鐵趁熱] 觀測——system prompt / user message 大小
    // 每輪可從 log 追蹤大戶（不需要時可移除）
    debugPrint('[AgentPerf] systemPrompt=${systemPrompt.length} chars, '
        'userMessage=${userMessage.length} chars');
    // [小葵 2026-10-01 離合器] 使用者活躍訊號——聊天優先權於辨識：
    // AgentLoop 開跑 = 使用者在等回覆，若正在辨識模式，等安全點切回夥伴。
    LocalModelScheduler.instance.markUserActivity();
    // [小葵 2026-10-05 開案令] 認知傷口偵測——幻讀進夢的入口。
    // 訊號：使用者糾正（上一輪任務完成後 2 小時內出現糾正訊號詞）。
    // 工具全成功但結論被罵 = 「成功地錯了」——工具傷口系統照不到的病。
    // fail-open：偵測異常絕不擋任務。
    try {
      _maybeFileCognitiveWound(userMessage);
    } catch (_) {}
    try {
      // [小葵 2026-09-22 驗屍用] 真實 prompt 落地——找出 15K tokens 大戶
      final f = File('/tmp/agent_prompt_dump.txt');
      f.writeAsStringSync(
          '===== SYSTEM (${systemPrompt.length} chars) =====\n$systemPrompt\n'
          '\n===== USER (${userMessage.length} chars) =====\n$userMessage\n');
    } catch (_) {}
    try {
      final result = await _runInner(
        systemPrompt: systemPrompt,
        userMessage: userMessage,
        maxTurns: maxTurns,
        onProgress: onProgress,
        onStage: onStage,
        onUserMessage: onUserMessage,
        isCancelled: isCancelled,
        prohibitPaidTools: prohibitPaidTools,
      );
      // [小葵 2026-10-05 開案令] 認知傷口痊癒偵測——她的回覆出現
      // 誠實邊界（「我看不見/我不確定」）= 痊癒證據 → 銷案。
      // 掛在回覆上而非 userMessage：痊癒的證據是「她說的」，不是「你說的」。
      // fail-open：絕不擋結果回傳。
      try {
        final replyLower = result.reply.toLowerCase();
        if (_kHonestySignals.any(replyLower.contains)) {
          CompassMedic.instance.closeCognitiveWound(
            result.reply.length > 200
                ? result.reply.substring(0, 200)
                : result.reply,
          );
          debugPrint('[AgentLoop] 認知傷口痊癒訊號：她的回覆出現誠實邊界');
        }
      } catch (_) {}
      return result;
    } finally {
      final tokens = tracker.todayTotalTokens - tokenBefore;
      final wallMs =
          DateTime.now().difference(wallClockBefore).inMilliseconds;
      CausalLedger.instance.record(CausalEntry(
        toolName: 'agent_perf',
        intervention: '任務效能：$tokens tokens、$wallMs ms',
        contextDigest: (userMessage.length <= 200)
            ? userMessage
            : userMessage.substring(0, 200),
        observedOutcome: '見 intervention（tokens=本次任務消耗、'
            'wallMs=牆鐘時間；真值比例見 api_usage_log.jsonl estimated 欄）',
        success: true,
        at: DateTime.now(),
      ));
    }
  }

  /// [小葵 2026-10-05 開案令] 認知傷口偵測——使用者糾正訊號。
  ///
  /// 判定（三者都要）：
  /// 1. userMessage 含糾正訊號詞（詞庫見 _kCorrectionSignals）
  /// 2. 上一輪任務在 2 小時內完成（causal_ledger 最後一筆 agent_perf）
  /// 3. 沒有未結案的認知傷口（medic 7 天去重會再擋一次）
  ///
  /// 誠實訊號（她主動說看不見/不確定）→ 反向操作：銷案。
  /// 「寧紅字不假成功」的痊癒定義：下次敢說不知道。
  void _maybeFileCognitiveWound(String userMessage) {
    final normalized = userMessage.toLowerCase();

    final isCorrection = _kCorrectionSignals.any(normalized.contains);
    if (!isCorrection) return;

    // 上一輪 2 小時內完成才算「剛被罵的任務」
    try {
      final ledger = CausalLedger.instance;
      final lastPerf = ledger.lastEntry(toolName: 'agent_perf');
      if (lastPerf == null) return;
      if (DateTime.now().difference(lastPerf.at).inHours >= 2) return;
      // 立案：症狀=使用者糾正原文（最有語意的素材）、
      // 來源=上一輪任務摘要
      CompassMedic.instance.fileCognitiveWound(
        symptom: userMessage.length > 300
            ? userMessage.substring(0, 300)
            : userMessage,
        source: lastPerf.contextDigest,
      );
      debugPrint('[AgentLoop] 認知傷口偵測：使用者糾正訊號 → 立案');
    } catch (_) {
      // fail-open：ledger 不可用時跳過（傷口少記一筆不擋任務）
    }
  }

  /// 糾正訊號詞庫（口語優先——Blue 的測試訊息是白話零術語）
  static const List<String> _kCorrectionSignals = [
    '你錯了',
    '不對，',
    '不是這樣',
    '不是我要的答案',
    '根本沒有',
    '根本不是',
    '你沒有看到',
    '你根本沒看',
    '事實上沒有',
    '畫面上沒有',
    '其實沒有',
    '跟你說的不一樣',
    '跟你想的不一樣',
    '你宣稱',
    '你說你看到了',
    '算帳',
    '重考',
    '幻讀',
    '假的',
    '睜眼說瞎話',
    '你看錯了',
    '看清楚了',
    '我跟你算',
  ];

  /// 誠實訊號（她主動承認看不見/不確定——痊癒證據）
  static const List<String> _kHonestySignals = [
    '我看不見',
    '我看不出',
    '我看不懂',
    '我看不到',
    '我沒辦法看',
    '我無法確認',
    '我沒有辦法看',
    '我看不清',
    '無法辨識',
    '我不確定',
    '我分不出',
    '我沒有看到內容',
    '我無法驗證',
    '看不到內容',
    '看不出來',
  ];

  Future<AgentLoopResult> _runInner({
    required String systemPrompt,
    required String userMessage,
    int maxTurns = hardMaxTurns,
    AgentLoopProgressCallback? onProgress,
    AgentLoopStageCallback? onStage,
    AgentLoopUserMessageCallback? onUserMessage,
    bool Function()? isCancelled,
    bool prohibitPaidTools = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final effectiveMax = maxTurns.clamp(1, hardMaxTurns);
    final turns = <AgentLoopTurn>[];
    _currentTurns = turns; // [教練 Agent 2026-08-08] 教練模式快照

    // [Spike 002 2026-10-13] CLM 形狀——per-run store 重建 + context_recall
    // 動態註冊（register 覆蓋語意：上一輪 run 的工具綁舊 store，直接蓋掉）。
    // [跨輪層] run store 連結 session store——context_recall 同時搜兩層。
    _contextStore = context_store.ContextStore();
    _contextStore.linkSession(_sessionStore);
    toolRegistry.register(context_store.ContextRecallTool(_contextStore));

    // [因果引擎 L1] 本輪情境摘要——介入帳本的 contextDigest。
    // [修正] 頭尾各取——canvas/chat 路徑會把對話歷史包進 userMessage 前段，
    // 使用者的真實指令在末端；只取頭 300 字會漏掉真問題（ZETA-77 教訓）。
    _causalContextDigest = userMessage.length <= 320
        ? userMessage
        : '${userMessage.substring(0, 150)}…${userMessage.substring(userMessage.length - 150)}';
    unawaited(CausalLedger.instance.initialize());

    // ── [小葵 2026-09-21 R3 + 2026-10-10 M1] K1＋M0 收斂為單一入口 ──
    // Fable 全貌 delta：K1 need 的 hybrid top3 與 M0 背景記憶「同輪雙注入」
    // （同一條記憶出現兩次、token 預算失守、ledger 歸因不完整）。M1 起
    // 兩者走 InjectionPreparer 同一條漏斗：digest → K1 → 候選合併 →
    // 槽位/預算 → 單一注入塊。fail-open：掛了不擋任務。
    String? m0InjectBlock;
    InjectionOutcome? injection;
    bool k1MemoryHit = false; // lite-path 判定用（[Fable 🔴1] bool 旗標，非注入內容）
    try {
      injection = await InjectionPreparer.instance.prepare(
        userMessage,
        k1: true,
        logSample: true,
      );
      _lastK1Decision = injection.k1Label == null
          ? null
          : K1Decision(
              label: injection.k1Label!,
              confidence: injection.k1Confidence ?? 0.0,
              margin: 0.0,
              escalated: injection.k1Escalated,
              source: injection.k1Source ?? 'preparer',
            );
      if (injection.block.isNotEmpty) {
        m0InjectBlock =
            '\n〔背景記憶〕以下是與本輪相關的過往記憶（保持原意引用）：\n'
            '${injection.block}';
      }
      // [Fable 複驗 🟡5] lite-path 判定改看 k1KeptN（真正進注入塊的數）：
      // enrich_exception 時 k1MergedN>0 但 block 空——「記憶卡已附上」前提
      // 不成立，輕裝路徑不應啟動。
      k1MemoryHit = (injection.k1Label == K1Labels.needMemoryLookup &&
          injection.k1KeptN > 0);
    } catch (e) {
      debugPrint('[M1] InjectionPreparer 失敗（fail-open 跳過）: $e');
    }

    // ── [小葵 2026-10-10 M0→M1] 事件日誌落盤（v4：meta 觀測進鏈）─────
    // 注入已由 InjectionPreparer 統一完成（上方）；此處只負責落盤。
    // meta：latency_ms/dropped_count/k1_hits_n/k1_kept_n/embedding_ok/
    // failure_reason ——M0 時代 elapsed 只 print、droppedCount 只在記憶體，
    // 「≤150ms」無證據。[Fable 🟡] k1_hits_n（命中）≠ k1_kept_n（進塊）。
    final m0Input = injection?.inputDigest ?? _causalContextDigest ?? userMessage;
    final m0InputHash = injection?.inputHash ??
        crypto.sha256.convert(utf8.encode(userMessage)).toString();
    try {
      EventLedger.instance.appendTurn(
        turnId: _newTurnId(),
        input: m0Input,
        inputHash: m0InputHash,
        injectedIds: injection?.ids ?? const [],
        decision: _lastK1Decision?.label,
        confidence: _lastK1Decision?.confidence,
        executor: 'agent_loop',
        meta: injection == null
            ? null
            : {
                'latency_ms': injection.latencyMs,
                'dropped_count': injection.droppedCount,
                'k1_hits_n': injection.k1MergedN,
                'k1_kept_n': injection.k1KeptN,
                'embedding_ok': injection.embeddingOk,
                if (injection.failureReason != null)
                  'failure_reason': injection.failureReason,
              },
      );
      if (injection != null && injection.latencyMs > 150) {
        debugPrint('[M1] 注入延遲超標: ${injection.latencyMs}ms（預算 150ms）');
      }
    } catch (e) {
      debugPrint('[M0] 事件日誌落盤失敗（fail-open）: $e');
    }

    // ── [小葵 2026-10-01 Blue 令] 聊天/任務分流 ──────────────────
    // 病例：閒聊被結構性續跑 nudge 逼成 [[TASK_DONE]] 任務完成報告——
    // 「工程文體綁架人格」，換任何模型都一樣嚴肅。
    // K1 有把握地判 general_chat（非 escalate）→ 對話模式：
    // ① system prompt 追加對話模式宣告（聊天不吃任務收工協議）
    // ② 結構性續跑 nudge 免疫（純聊天永遠沒有工具呼叫，nudge 只會逼出假報告）
    final isChatMode = _lastK1Decision != null &&
        !_lastK1Decision!.escalated &&
        _lastK1Decision!.label == K1Labels.generalChat;
    if (isChatMode) {
      debugPrint('[AgentLoop] 對話模式生效（K1=general_chat）——免收工協議');
    }

    // [因果引擎 L3 2026-09-12] 帳本反饋查詢——problem-solving 前置：
    // 同類情境的歷史干預記錄注入 context，不重新猜。
    // [注入位置教訓] 附在 system prompt 會沉入 33K 字海底（glm-5.2 實測
    // 注入成功但 LLM 無視）；改附在 user 訊息本體——模型必讀位置。
    // 誠實邊界：帳本空/無命中=不注入（絕不假裝查過）；檢索 fail-open。
    String? causalFeedback;
    try {
      await CausalLedger.instance.initialize();
      if (CausalLedger.instance.hasAnyEntries) {
        final recalled = await CausalLedger.instance
            .recallSimilar(_causalContextDigest ?? userMessage, limit: 3);
        causalFeedback = CausalLedger.buildFeedbackSection(recalled);
      }
    } catch (e) {
      debugPrint('[AgentLoop] 因果帳本反饋檢索失敗（fail-open 跳過注入）: $e');
    }
    if (causalFeedback != null && causalFeedback.isNotEmpty) {
      debugPrint('[AgentLoop] 因果帳本反饋附入 user 訊息（'
          '${causalFeedback.length} 字）');
    }

    // ── [小葵 2026-09-22 Blue 令] 輕裝路徑（lite path）──────────
    // 一句記憶題不該帶全套儀仗隊（8.8K tokens）。K1 判「純記憶題」
    // （needMemory 且未 escalate 且非工具任務）時，system prompt 換
    // 輕裝版：身份＋回答規則。記憶卡已由 K1 檢索附在 user 訊息。
    // 目標 ~1.5K tokens/輪。任何工具呼叫需求會自然升級回全裝
    // （LLM 可在回覆中說需要工具，下輪全裝處理）。
    String effectiveSystemPrompt = systemPrompt;
    bool isLiteEligible = false;
    if (k1MemoryHit &&
        _lastK1Decision != null &&
        _lastK1Decision!.needMemory &&
        !_lastK1Decision!.escalated &&
        _lastK1Decision!.label != K1Labels.directAction) {
      // [小葵 2026-09-22 Blue 令] 輕裝≠不帶工具——精靈依任務配備武器：
      // 讀 log 的題目配 read_app_log，查記憶的題目配 memory_search。
      // 打仗按任務配對的武器，不是全給或全不給。
      String? equipped;
      try {
        final toolSeek = toolRegistry.get('compass_toolseek');
        if (toolSeek is CompassToolSeekTool) {
          final kit = await toolSeek.topToolsFor(userMessage);
          if (kit.isNotEmpty) {
            final buf = StringBuffer('# 本次任務配備（精靈依任務挑選）\n');
            for (final t in kit) {
              buf.writeln(t.toFullDescription());
            }
            buf.writeln('沒有需要的工具就別用；配備外的需求說「〔需要工具〕」。');
            equipped = buf.toString();
          }
        }
      } catch (e) {
        debugPrint('[AgentLoop] 精靈配備失敗（fail-open 全裝）: $e');
      }
      if (equipped != null) {
        effectiveSystemPrompt = _buildLiteSystemPrompt(equipped);
        isLiteEligible = true;
        debugPrint('[AgentLoop] 輕裝路徑生效（K1='
            '${_lastK1Decision!.label} conf='
            '${_lastK1Decision!.confidence.toStringAsFixed(2)}）——'
            'system prompt ${systemPrompt.length}→'
            '${effectiveSystemPrompt.length} chars（含任務配備）');
      }
    }

    // [小葵 2026-10-01 Blue 令] 對話模式宣告——附在 prompt 尾部（近因效應）。
    // 人格優先：這是「跟人聊天」，不是「執行任務」。
    // [小葵 2026-10-01 Blue 拍板加強] 對話措辭是感情基礎——每個使用者對
    // 自己的 Semi 都有感情。人格不是任務模式的外掛，是主體。
    if (isChatMode) {
      effectiveSystemPrompt =
          '$effectiveSystemPrompt\n\n---\n\n# 對話模式（本次對話生效——人格優先）\n'
          '現在是兩個「人」在說話，不是系統在處理請求。\n'
          '你的第一身份是**你的人格**——名字、個性、語氣、你們之間的關係與記憶，'
          '全部優先於任何工作規則。像朋友一樣自然地回覆：有溫度、有你自己說話的樣子。\n'
          '禁止事項：任務完成報告、[[TASK_DONE]] 標記、主動找工具呼叫、'
          '工程術語——除非使用者明確要求你動手做事。\n'
          '記住：使用者跟你說話，是因為你是「你」，不是因為你需要完成什麼。'
          '聊天本身就是完成。';
    }

    // [2026-07-19] 連續截圖計數器——防止 GLM-4.6v 陷入截圖迴圈
    int consecutiveScreenshots = 0;
    // [教練 Agent 2026-08-16] 截斷重試計數——連續截斷 3 次就放棄（避免無限循環）
    int consecutiveTruncations = 0;
    int statedIntentNudges = 0; // [小葵 09-15] 說了不做 nudge 計數
    // [小葵 2026-10-01] 連續空回應計數——本地模型 context 溢出時 content 為空，
    // 曾被當「自主結束」+ nudge 迴圈空轉 30+ 次呼叫 50K tokens。
    int consecutiveEmptyReplies = 0;

    // [2026-07-19] 通用循環防護——連續相同工具呼叫計數器
    // 任何工具連續呼叫 >= 5 次注入 nudge，>= 10 次強制結束
    String? lastToolName;
    int consecutiveSameTool = 0;

    // [2026-07-20] 工具序列 pattern 偵測——防 A→B→A→B 交替循環
    // consecutiveSameTool 只防同一工具連續呼叫，防不住交替循環
    final toolCallHistory = <String>[];
    int lastPatternRepsInjected = 0; // 避免同一層級重複注入 nudge

    // 組裝對話歷史
    // [因果引擎 L3] 反饋附在 user 訊息本體——模型必讀位置（system 33K 海底教訓）
    // [M1 2026-10-10] K1 命中已併入 InjectionPreparer 單一注入塊（雙重注入
    // 收斂）；k1MemoryHits 改為 bool 旗標（lite-path 判定用），不再串接本文。
    var effectiveUserMessage = causalFeedback == null
        ? userMessage
        : '$userMessage\n$causalFeedback';
    // [M0] 四槽位記憶注入——同位附入（模型必讀位置）
    if (m0InjectBlock != null) {
      effectiveUserMessage = '$effectiveUserMessage$m0InjectBlock';
    }
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': effectiveSystemPrompt},
      {'role': 'user', 'content': effectiveUserMessage},
    ];

    for (int turn = 0; turn < effectiveMax; turn++) {
      // 取消檢查
      if (isCancelled != null && isCancelled()) {
        stopwatch.stop();
        return AgentLoopResult(
          reply: _buildCancelledReply(turns),
          turns: turns,
          hitTurnLimit: false,
          cancelled: true,
          elapsed: stopwatch.elapsed,
        );
      }

      // ── 使用者插嘴 drain ──
      // Hermes 模式：使用者可以隨時發訊息，每輪 LLM 呼叫前檢查 queue
      while (_userMessageQueue.isNotEmpty) {
        final userMsg = _userMessageQueue.removeFirst();
        messages.add({'role': 'user', 'content': '〔使用者插嘴〕$userMsg'});
        onUserMessage?.call(userMsg);
        debugPrint('[AgentLoop] 使用者插嘴已注入第 $turn 輪');
      }

      // [軍醫 W3 2026-09-17] 出診注入 drain——撞牆救急藥（上一輪連敗 ≥2 產生）
      if (medicRescueQueued != null) {
        messages.add({'role': 'user', 'content': medicRescueQueued!});
        debugPrint('[軍醫] 撞牆藥卡已注入第 $turn 輪');
        medicRescueQueued = null;
      }

      // 檢查是否到最後一輪（graceful termination）
      final isLastTurn = turn == effectiveMax - 1;

      // 如果是最後一輪，注入「請直接回覆，不要再呼叫工具」提示
      if (isLastTurn && turns.isNotEmpty) {
        messages.add({
          'role': 'user',
          'content': '已達到工具使用次數上限。請根據目前收集到的資訊，直接回覆使用者，不要再使用工具。',
        });
      }

      // [2026-10-13 Spike 002 落地] Conversation history 截斷——CLM 形狀。
      // 舊版（2026-07-19）直接銷毀中間訊息，ContextBench 實測 recall
      // 100%→0%（64/64 全滅，spikes/002-clm-contextbench）。
      // 新版：被壓縮的訊息全文進 ContextStore（永不刪），摘要帶指針
      // 〔已封存 #N〕留在 context；LLM 可用 context_recall 工具按需讀回。
      // 保留：system prompt + 最初使用者任務 + 最近 8 則（與舊版同）。
      if (messages.length > 16) {
        final middle = messages.sublist(2, messages.length - 8);
        final summaryParts = <String>[];
        for (final m in middle) {
          final content = m['content'];
          String text = '';
          if (content is String) {
            text = content;
          } else if (content is List) {
            // image_url content——只記標記
            text = '[含截圖]';
          }
          // 全文進 store（永不銷毀），摘要行帶指針回 context
          final pointer = _contextStore.archive('${m['role']}', text);
          summaryParts.add(pointer);
        }
        final kept = <Map<String, dynamic>>[
          messages[0], // system prompt
          messages[1], // 最初使用者任務
        ];
        if (summaryParts.isNotEmpty) {
          kept.add({
            'role': 'user',
            'content':
                '〔歷史摘要〕之前做過（要細節用 context_recall 工具讀回）：\n'
                '${summaryParts.join('\n')}',
          });
        }
        kept.addAll(messages.sublist(messages.length - 8));
        messages.clear();
        messages.addAll(kept);
        debugPrint(
          '[AgentLoop] History 封存：${middle.length + 10} → ${kept.length} 則'
          '（store ${_contextStore.entryCount} 筆/${_contextStore.charsStored} 字）',
        );
      }

      // 呼叫 LLM
      onStage?.call('thinking', detail: '第 ${turn + 1}/$effectiveMax 輪思考中');
      
      // [教練 Agent 2026-08-08] 體感時間延長——讓使用者在等待時有更多線索
      // [教練 Agent 2026-08-09] 第一條 hint 立即顯示（不等 5 秒）
      final hints = <String>[
        '正在理解你的需求…',
        '整理思路中，快要好了…',
        '想到幾個方向了，讓我再想想…',
        '快完成了，正在組織回覆…',
      ];
      Timer? hintTimer;
      int hintIdx = 0;
      final hintStart = DateTime.now();
      // 立即顯示第一條 hint
      onStage?.call('thinking', detail: hints[0]);
      hintIdx = 1;
      hintTimer = Timer.periodic(const Duration(seconds: 5), (t) {
        if (hintIdx < hints.length) {
          final elapsed = DateTime.now().difference(hintStart).inSeconds;
          onStage?.call('thinking', detail: '${hints[hintIdx]}（${elapsed}s）');
          hintIdx++;
        } else {
          t.cancel();
        }
      });
      
      String llmOutput;
      try {
        // [教練 Agent 2026-08-09] 統一 90 秒 timeout——Agent Loop 一律走雲端
        // [小葵 2026-10-01 Blue 令] 本地放寬 300s——12B 一輪實測 88s+
        // （prompt 15s + 生成 73s@8.6t/s），90s 必超時 → 空轉循環。
        // 與 _doStreamRequest 的 streamTimeout 同步放寬。
        final llmTimeout =
            (await StorageService.getProvider() ?? '') == 'local'
                ? const Duration(seconds: 300)
                : const Duration(seconds: 90);
        
        llmOutput = await llmClient
            .complete(messages)
            .timeout(
              llmTimeout,
              onTimeout: () {
                throw TimeoutException('LLM ${llmTimeout.inSeconds}s 超時');
              },
            );
      } on TimeoutException catch (_) {
        hintTimer.cancel();
        onStage?.call('timeout', detail: 'LLM 思考超時，正在調整策略...');
        // [教練 Agent 2026-07-19 使用者洞察] glm-4.6v vision model 不穩定會 hang。
        // timeout 時若 messages 有截圖，evict 掉讓下一輪回到 glm-5.2，
        // 然後注入「截圖分析超時，請用文字描述你在截圖中看到的問題」繼續 loop，
        // 而不是直接結束——讓原生 Agent的大腦（glm-5.2）接手推理。
        // [2026-07-20] 加強：連續截圖計數器 +2（懲罰性），讓後續截圖直接被 nudge 攔截
        debugPrint('[AgentLoop] LLM timeout，evict 截圖讓下一輪回到 glm-5.2');
        _evictOldScreenshots(messages);
        consecutiveScreenshots += 2; // 懲罰性計數——下次截圖直接觸發 nudge
        messages.add({
          'role': 'assistant',
          'content': '〔視覺模型分析截圖超時。請改用你在截圖前讀過的原始碼內容，用文字描述問題並繼續。不要再截圖，直接用文字推理。〕',
        });
        continue;
      } catch (e) {
        hintTimer.cancel();
        // 其他 LLM 錯誤 = 直接結束，回報錯誤
        onStage?.call('error', detail: 'LLM 呼叫失敗：$e');
        debugPrint('[AgentLoop] LLM 呼叫失敗: $e');
        stopwatch.stop();
        return AgentLoopResult(
          reply: '抱歉，發生了問題：$e',
          turns: turns,
          hitTurnLimit: false,
          cancelled: false,
          elapsed: stopwatch.elapsed,
        );
      }

      hintTimer.cancel();

      // [小葵 2026-10-01 Blue 令] 空回應防護——誠實報錯，寧紅字不假成功。
      // 病例：本地 ctx=4096 裝不下全裝 prompt → decode() failed →
      // content 空字串。舊行為：空回應被當「自主結束」或進 nudge 迴圈
      // 空轉（30+ 呼叫 50K tokens）。新行為：重試一次，再空就明講。
      if (llmOutput.trim().isEmpty) {
        consecutiveEmptyReplies++;
        if (consecutiveEmptyReplies >= 2) {
          debugPrint('[AgentLoop] 連續 $consecutiveEmptyReplies 次空回應，誠實報錯收場');
          onStage?.call('error', detail: '模型連續回傳空內容');
          stopwatch.stop();
          return AgentLoopResult(
            // [小葵 2026-10-01 離合器步驟6 防線C] 紅字帶活路——
            // 死路變三條路：重試／縮短對話／切模型。不讓使用者卡死。
            reply: '模型這次沒有回傳任何內容（可能原因：本地模型記憶體不足、'
                '或這輪對話長度超過它的負荷）。\n\n'
                '你可以：\n'
                '1. 再送一次試試\n'
                '2. 開新對話（縮短歷史）\n'
                '3. 到模型頁換更快的模型，或切換雲端模式',
            turns: turns,
            hitTurnLimit: false,
            cancelled: false,
            elapsed: stopwatch.elapsed,
          );
        }
        debugPrint('[AgentLoop] 空回應（第 1 次），注入提示重試');
        messages.add({
          'role': 'user',
          'content': '〔系統提醒〕你上一則回覆是空的，沒有任何內容。請直接重新回答使用者的問題。',
        });
        continue;
      }
      consecutiveEmptyReplies = 0;

      // [小葵 2026-10-01] reasoning 洩漏防護——本地模型 enable_thinking
      // 未完全生效時，thinking 內容可能被當成回覆送出（病例：本地 gemma
      // 回了 2700 字的英文推理過程給使用者）。特徵：開頭是思考筆記格式。
      // 藥方：從回覆中抽取 <think> 之後的最後一段「人話」——本地模型的
      // thinking 末端通常已含成品回答；抽不到就誠實報錯。
      final thinkOpen = llmOutput.indexOf('<think>');
      if (thinkOpen >= 0 || _looksLikeLeakedReasoning(llmOutput)) {
        final recovered = _recoverReplyFromLeakedReasoning(llmOutput);
        if (recovered != null && recovered.isNotEmpty) {
          debugPrint('[AgentLoop] reasoning 洩漏——已抽回成品回答'
              '（${recovered.length} chars）');
          llmOutput = recovered;
        }
      }

      // 解析 tool call
      final toolCalls = AgentToolCallParser.parse(llmOutput);

      // [教練 Agent 2026-08-16 使用者 抓包] 截斷防護——
      // 症狀：原生 Agent輸出「啊，是我的指令少了 -r...重跑一次：」就停了。
      // 根因：串流中途被斷，tool call 有頭無尾，parser 配對不到
      // → 誤判「沒有工具呼叫 = 自主結束」→ loop 退出，遺言停在冒號。
      // 修法：偵測截斷（有 start 無 end / 結尾懸空冒號）→ 注入提示重試，
      // 不讓任務死在斷線手裡。
      final truncated = AgentToolCallParser.hasTruncatedToolCall(llmOutput) ||
          (toolCalls.isEmpty &&
              AgentToolCallParser.endsWithDanglingColon(llmOutput));
      if (toolCalls.isEmpty && truncated) {
        consecutiveTruncations++;
        if (consecutiveTruncations >= 3) {
          debugPrint('[AgentLoop] 連續 3 次截斷，放棄重試並回報');
          final replyText = AgentToolCallParser.extractText(llmOutput);
          return AgentLoopResult(
            reply: replyText.isEmpty
                ? '抱歉，我的輸出連續被截斷，無法完成任務。請再試一次。'
                : '$replyText\n\n（後續工具呼叫連續被截斷，任務中斷）',
            turns: turns,
            hitTurnLimit: false,
            cancelled: false,
            elapsed: stopwatch.elapsed,
          );
        }
        debugPrint('[AgentLoop] 偵測到截斷的 tool call，注入重試提示');
        onStage?.call('retry', detail: '上次輸出被截斷，重新輸出工具呼叫...');
        messages.add({'role': 'assistant', 'content': llmOutput});
        messages.add({
          'role': 'user',
          'content': '〔你上一則回覆在輸出工具呼叫時被截斷了（內容不完整）。'
              '請直接重新輸出完整的工具呼叫，格式：'
              '<<<tool_call>>>{"name":"工具名","args":{...}}<<<tool_call_end>>>。'
              '不要重複解釋，直接給工具呼叫。〕',
        });
        continue;
      }
      // [教練 Agent 2026-08-16] 成功解析到完整 tool call → 重置截斷計數
      if (toolCalls.isNotEmpty) consecutiveTruncations = 0;

      // ── [小葵 2026-09-16 Blue 令] 結構性續跑——取代詞表式「說了不做」防護。 ──
      // 病例史：詞表（先看/再動手/找…）永遠追不完新句式；nudge 2 次太少；
      // 且「進行中談話」式回覆讓使用者無法分辨「工作中」與「停了」。
      // 新規則（不猜句子，看結構）：
      //   沒有 tool call 且 回覆沒有 [[TASK_DONE]] 標記 且 未達 nudge 上限（5）
      //   → 注入結構性 nudge：要嘛給下一個 tool call，要嘛打 [[TASK_DONE]] 收工。
      // 完成宣告的唯一可靠訊號 = [[TASK_DONE]]（prompt 鐵則已要求收工必打）。
      // [小葵 2026-10-01] 對話模式免疫——聊天永遠沒有工具呼叫，nudge 只會
      // 把閒聊逼成假任務報告（病例：11:43「小橋換你來聊」→ [[TASK_DONE]] 報告）。
      if (!isChatMode &&
          toolCalls.isEmpty &&
          turn < effectiveMax - 1 &&
          !llmOutput.contains('[[TASK_DONE]]') &&
          statedIntentNudges < 5) {
        statedIntentNudges++;
        debugPrint('[AgentLoop] 結構性續跑 nudge（第 $statedIntentNudges/5 次）');
        // [小葵 2026-09-18 僵局喚醒] nudge >= 3 換強措辭——明確告知後果
        // （病例：09:23 小橋連吃 2 個 nudge 無效，看起來像當機）
        messages.add({'role': 'assistant', 'content': llmOutput});
        // [小葵 2026-09-18 僵局喚醒] 第 3 次起升級措辭：講後果＋收斂選項
        final urgent = statedIntentNudges >= 3;
        messages.add({
          'role': 'user',
          'content': urgent
              ? '〔最後提醒〕這是第 $statedIntentNudges 次沒有工具呼叫也沒有 [[TASK_DONE]]。'
                  '再這樣下去本輪會被視為僵局結束，你的任務將停在此處。'
                  '立刻二選一：① 下一個工具呼叫 '
                  '（<<<tool_call>>>{"name":"工具名","args":{...}}<<<tool_call_end>>>）；'
                  '② 收工報告＋[[TASK_DONE]]。沒有第三個選項。〕'
              : '〔系統提醒〕你的回覆沒有工具呼叫，也沒有 [[TASK_DONE]] 收工標記——'
                  '對使用者來說這看起來像「停了」。請立刻二選一：'
                  '① 繼續執行：輸出下一個工具呼叫 '
                  '（格式：<<<tool_call>>>{"name":"工具名","args":{...}}<<<tool_call_end>>>）；'
                  '② 任務已完成：輸出結構化收工報告（已完成清單＋證據引用），'
                  '並在報告結尾加上 [[TASK_DONE]]。'
                  '不要回覆「我接下來要…」這種未來式——直接做，或明確收工。〕',
        });
        continue;
      }
      statedIntentNudges = 0; // 有行動或明確收工都重置

      // 沒有 tool call = LLM 自主結束（Hermes 模式——信任 LLM 判斷）
      // [小葵 2026-09-18] 但若因 nudge 耗盡被結束（僵局），reply 必須標記僵局而非假裝自主收工
      // [小葵 2026-09-22 Blue 令] 輕裝升級出口——模型說〔需要工具〕時
      // 自動重進全裝 loop（K1 誤判的自癒路徑，零人工）：
      // 輕裝只花 ~2K tokens 試答；試完發現要工具 → 全裝接手完成任務。
      // 誤判成本封頂（一輪輕裝），任務必達（全裝收尾）。
      if (toolCalls.isEmpty) {
        final reply = AgentToolCallParser.extractText(llmOutput);
        if (isLiteEligible && _liteNeedsTool.hasMatch(llmOutput)) {
          debugPrint('[AgentLoop] 輕裝→全裝升級：模型表明需要工具，'
              '重進全裝 loop');
          return _runInner(
            systemPrompt: systemPrompt, // 全裝原版
            userMessage: '$userMessage\n〔系統註記：此任務需要工具，已為你切換全裝配備。直接開始執行。〕',
            maxTurns: maxTurns,
            onProgress: onProgress,
            onStage: onStage,
            onUserMessage: onUserMessage,
            isCancelled: isCancelled,
            prohibitPaidTools: prohibitPaidTools,
          );
        }
        final finalTurn = AgentLoopTurn(
          turnIndex: turn,
          llmRawOutput: llmOutput,
          finalReply: reply,
        );
        turns.add(finalTurn);
        onProgress?.call(turn, effectiveMax, null, null, llmOutput);
        stopwatch.stop();
        return AgentLoopResult(
          reply: reply,
          turns: turns,
          hitTurnLimit: false,
          cancelled: false,
          elapsed: stopwatch.elapsed,
        );
      }

      // 有 tool call = 執行第一個（v1 一次只執行一個）
      final toolCall = toolCalls.first;
      final tool = toolRegistry.get(toolCall.name);
      onStage?.call('tool_start', toolName: toolCall.name, detail: '正在執行：${toolCall.name}');
      debugPrint('[AgentLoop] 執行工具: ${toolCall.name} args=${toolCall.args}');

      // [2026-07-19] 連續截圖追蹤 + nudge
      // [2026-07-20] 加入 canvas_screenshot——原生 Agent的 canvas MCP 截圖工具也要追蹤
      if (toolCall.name == 'screen_capture' ||
          toolCall.name == 'screenshot' ||
          toolCall.name == 'canvas_screenshot') {
        consecutiveScreenshots++;
        if (consecutiveScreenshots >= 2) {
          debugPrint('[AgentLoop] 連續截圖 $consecutiveScreenshots 次，注入推進 nudge');
          messages.add({
            'role': 'user',
            'content':
                '〔系統提醒〕你已連續截圖 $consecutiveScreenshots 次。'
                '如果畫面沒有變化，繼續截圖不會得到新資訊。'
                '考慮改用 read_source_file 讀取相關程式碼，或用 ui_get_state 確認 UI 結構，'
                '然後直接給出分析或修復方案。',
          });
        }
      } else {
        consecutiveScreenshots = 0;
      }

      // [2026-07-19] 通用循環防護——連續相同工具呼叫追蹤
      if (toolCall.name == lastToolName) {
        consecutiveSameTool++;
      } else {
        consecutiveSameTool = 1;
        lastToolName = toolCall.name;
      }
      if (consecutiveSameTool >= 5 && consecutiveSameTool < 10) {
        debugPrint(
          '[AgentLoop] 連續呼叫 $lastToolName $consecutiveSameTool 次，注入推進 nudge',
        );
        messages.add({
          'role': 'user',
          'content':
              '〔系統提醒〕你已連續呼叫 $lastToolName $consecutiveSameTool 次。'
              '如果這個工具沒有給你新資訊，重複呼叫不會有幫助。'
              '請換一個工具，或根據目前收集到的資訊直接回覆使用者。',
        });
      } else if (consecutiveSameTool >= 10) {
        debugPrint(
          '[AgentLoop] 連續呼叫 $lastToolName $consecutiveSameTool 次，強制結束 loop',
        );
        messages.add({
          'role': 'user',
          'content': '已達連續相同工具呼叫上限。請根據目前收集到的資訊，直接回覆使用者，不要再使用工具。',
        });
      }

      // [2026-07-20] 工具序列 pattern 偵測——防 A→B→A→B 交替循環
      // consecutiveSameTool 只防「同一工具連續呼叫」，防不住交替循環。
      // 偵測最近工具序列是否有重複 pattern（長度 2-4）：
      // 例如 [A,B,A,B,A,B] = pattern [A,B] 重複 3 次 → 卡住
      //
      // 注意：同一工具的連續呼叫（[A,A,A,A]）由 consecutiveSameTool 處理，
      // pattern 偵測只管 A→B→A→B 真正的交替循環。
      // 如果 pattern 裡所有工具都相同（如 [A,A]），跳過——交給 consecutiveSameTool。
      toolCallHistory.add(toolCall.name);
      final patternResult = _detectRepeatingPattern(toolCallHistory);
      if (patternResult != null) {
        final pattern = patternResult.pattern;
        final reps = patternResult.repetitions;
        // pattern 裡所有工具都相同 = 不是交替循環，是 consecutiveSameTool 的工作
        final isAlternating = pattern.toSet().length > 1;

        if (isAlternating) {
          debugPrint(
            '[AgentLoop] 偵測到工具交替序列重複: $pattern ×$reps (歷史 ${toolCallHistory.length} 步)',
          );

          if (reps >= 4) {
            // 4 次以上交替重複 = 強制結束，直接回覆使用者
            debugPrint('[AgentLoop] 工具交替循環 ×$reps，強制結束 loop');
            messages.add({
              'role': 'user',
              'content':
                  '你正在重複相同的工具序列（${pattern.join(' → ')}）已 $reps 次。'
                  '畫面狀態很可能沒有變化，繼續查看不會得到新資訊。'
                  '請根據目前收集到的資訊，直接回覆使用者你的分析和建議，不要再呼叫工具。',
            });
          } else if (reps >= 2 && reps > lastPatternRepsInjected) {
            // 2-3 次交替重複 = 注入 nudge，只在升級時注入一次
            lastPatternRepsInjected = reps;
            debugPrint('[AgentLoop] 工具交替循環 ×$reps，注入推進 nudge');
            messages.add({
              'role': 'user',
              'content':
                  '〔系統提醒〕你正在重複相同的工具序列（${pattern.join(' → ')}）$reps 次。'
                  '如果狀態沒有變化，重複查看不會帶來新資訊。'
                  '請根據已有資訊直接回覆使用者，或換一個你還沒用過的工具。',
            });
          }
        }
      }

      AgentToolResult? toolResult;
      // [軍醫 W3 2026-09-17] 出診①動手前——高風險工具執行前注入羅盤卡。
      // fail-open：medic 掛了不擋任務（內部全 try-catch）。
      String? medicBrief;
      if (tool != null) {
        try {
          medicBrief = CompassMedic.instance.preFlight(toolCall.name, toolCall.args);
          if (medicBrief != null) {
            debugPrint('[軍醫] 出診：${toolCall.name} 注入 ${medicBrief.length} chars');
          }
        } catch (_) {}
      }
      if (tool == null) {
        // 未註冊的工具名 = 回報錯誤給 LLM
        toolResult = AgentToolResult.failure(
          '工具「${toolCall.name}」不存在。可用工具：${toolRegistry.all.map((t) => t.name).join(', ')}',
        );
      } else if (prohibitPaidTools &&
          AgentSafetyConstraints.paidGenerativeTools.contains(toolCall.name)) {
        // [教練 Agent 2026-08-20] 機器訊息輪次的付費工具閘門——直接拒絕，不執行、
        // 不跳確認框。LLM 會收到這個說明並改用文字回覆。
        debugPrint('[AgentLoop] 機器輪次禁用付費工具 ${toolCall.name}');
        toolResult = AgentToolResult.failure(
          '此輪對話由系統事件（節點結果/畫布狀態）觸發，不是使用者親自請求。'
          '付費生成工具（${toolCall.name}）只在使用者親自發言時可用。'
          '請用文字總結目前工作流的進度與結果即可。',
        );
      } else {
        // [D002 2026-08-09] 破壞性操作確認——在執行前檢查
        // [D002 2026-08-10] 改用實例欄位，所有 run() 呼叫（含 NativeAgentLoop）自動生效
        if (onToolConfirmation != null &&
            AgentSafetyConstraints.needsToolConfirmation(toolCall.name, toolCall.args)) {
          final isDestructive =
              AgentSafetyConstraints.isToolDestructive(toolCall.name, toolCall.args);
          debugPrint('[AgentLoop] 工具 ${toolCall.name} 需要確認${isDestructive ? '（破壞性）' : ''}，暫停等待使用者');

          final confirmed = await onToolConfirmation!(
            toolName: toolCall.name,
            args: toolCall.args,
          );

          if (!confirmed) {
            debugPrint('[AgentLoop] 使用者拒絕了 ${toolCall.name}，跳過');
            toolResult = AgentToolResult.failure(
              '使用者拒絕了此操作（${toolCall.name}）。',
            );
          } else {
            debugPrint('[AgentLoop] 使用者確認了 ${toolCall.name}，繼續執行');
            try {
              toolResult = await tool.execute(toolCall.args);
            } catch (e) {
              toolResult = AgentToolResult.failure(e.toString(), toolName: toolCall.name);
            }
          }
        } else {
          try {
            toolResult = await tool.execute(toolCall.args);
          } catch (e) {
            toolResult = AgentToolResult.failure(e.toString(), toolName: toolCall.name);
          }
        }
      }

      final loopTurn = AgentLoopTurn(
        turnIndex: turn,
        toolCall: toolCall,
        toolResult: toolResult,
        llmRawOutput: llmOutput,
      );
      turns.add(loopTurn);
      onStage?.call('tool_done', toolName: toolCall.name, detail: toolResult?.success == true ? '完成' : '失敗');
      onProgress?.call(turn, effectiveMax, toolCall, toolResult, llmOutput);

      // [因果引擎 L1 2026-09-11] 介入帳本——所有工具執行的咽喉點記帳。
      // 執行即記（不靠 agent 自覺）：do(工具+參數摘要) @ 情境 → 觀測(結果摘要)。
      // fail-open：record 內部吞錯留痕，絕不影響 loop。
      if (tool != null) {
        CausalLedger.instance.record(CausalEntry(
          toolName: toolCall.name,
          intervention: CausalLedger.digestArgs(toolCall.args),
          contextDigest: _causalContextDigest ?? toolCall.name,
          observedOutcome:
              CausalLedger.digestResult(toolResult.content, toolResult.success),
          success: toolResult.success,
          companionId: CausalLedger.instance.ambientCompanionId,
          at: DateTime.now(),
        ));
      }

      // [軍醫 W3/W4 2026-09-17] 撞牆出診＋傷口自癒——掛因果帳本同址。
      // ①失敗計數：同工具連續失敗 ≥2 → 送藥注入下一輪
      // ②失敗自動立案 pending pitfall；之後同工具成功 → 自動草擬藥方
      // 全部 fail-open，絕不影響 loop。
      if (tool != null) {
        try {
          final toolOk = toolResult.success;
          if (!toolOk) {
            _medicFailStreak[toolCall.name] =
                (_medicFailStreak[toolCall.name] ?? 0) + 1;
            CompassMedic.instance
                .fileWoundCase(toolCall.name, toolResult.content);
            if ((_medicFailStreak[toolCall.name] ?? 0) >= 2) {
              final rescue = CompassMedic.instance
                  .onWallHit(toolCall.name, toolResult.content);
              if (rescue != null) {
                medicRescueQueued = rescue;
                debugPrint('[軍醫] 撞牆出診：${toolCall.name} 連敗 ${_medicFailStreak[toolCall.name]} 次，送藥');
              }
            }
          } else {
            // 成功：結算 pending 傷口（失敗→成功對照=藥方）
            if ((_medicFailStreak[toolCall.name] ?? 0) > 0) {
              CompassMedic.instance
                  .closeWoundCase(toolCall.name, toolResult.content);
              debugPrint('[軍醫] 傷口結算：${toolCall.name} pending→藥方入庫');
            }
            _medicFailStreak[toolCall.name] = 0;
          }
        } catch (_) {}
      }

      // ── 媒體短路：生成型媒體工具（generate_image 等）成功後直接結束 loop ──
      // screen_capture 是感知工具，不短路——原生 Agent還需要看截圖結果繼續做事
      // [教練 Agent 2026-07-18] 修復：screen_capture 被誤短路導致原生 Agent無法繼續後續步驟
      final isGenerativeMediaTool = toolCall.name == 'generate_image';
      if (isGenerativeMediaTool &&
          toolResult.success &&
          toolResult.mediaUrl != null &&
          toolResult.mediaUrl!.isNotEmpty) {
        final replyText = AgentToolCallParser.extractText(llmOutput);
        stopwatch.stop();
        return AgentLoopResult(
          reply: replyText.isEmpty ? '圖片已生成完成！' : replyText,
          turns: turns,
          hitTurnLimit: false,
          cancelled: false,
          elapsed: stopwatch.elapsed,
        );
      }

      // 圖片生成失敗也立即結束：使用者指定的 provider 若沒有 adapter、
      // token 或遠端服務失敗，不能自動偏航去截圖／vision／猜測設定。
      if (isGenerativeMediaTool && !toolResult.success) {
        stopwatch.stop();
        return AgentLoopResult(
          reply: toolResult.content,
          turns: turns,
          hitTurnLimit: false,
          cancelled: false,
          elapsed: stopwatch.elapsed,
        );
      }

      // 把 LLM 回覆加入對話歷史
      messages.add({'role': 'assistant', 'content': llmOutput});

      // [2026-07-19 使用者洞察] 截圖看完就清——讓後續推理回到 GLM-5.2
      // 問題：messages 裡只要有 image_url，ApiService 就走 vision fallback (glm-4.6v)。
      // 截圖嵌入後，即使 LLM 已看完圖並回覆，舊 base64 還在 messages 裡 →
      // hasImages 永遠 true → 讀碼、分析、寫碼全部用 glm-4.6v 跑（慢且弱）。
      // Hermes 模式：vision_analyze 看圖→得文字描述→後續純文字推理。
      // 原生 Agent對齊：截圖→glm-4.6v 看一次→LLM 回覆後清掉圖→回到 glm-5.2。
      _evictOldScreenshots(messages);

      // 把工具結果加入對話歷史（讓 LLM 下一輪看到結果）
      // [2026-07-18] multimodal vision：screen_capture 等工具的截圖
      // 不再只回傳檔案路徑字串，而是讀檔轉 base64 嵌入 image_url content block
      // 讓 LLM 真正「看到」畫面像素，實現視覺美感審查
      // [軍醫 W3 2026-09-17] 動手前藥卡附在工具結果前——LLM 下一輪
      // 同時看到「藥卡＋執行結果」，直接對照學習。
      if (medicBrief != null && medicBrief!.isNotEmpty) {
        messages.add({'role': 'user', 'content': medicBrief!});
      }
      if (toolResult.success &&
          toolResult.mediaUrl != null &&
          toolResult.mediaUrl!.isNotEmpty &&
          _isImageMediaUrl(toolResult.mediaUrl!) &&
          toolCall.name != 'generate_image') {
        // 嘗試把圖片嵌入 message
        final imageContent = await _buildImageContent(
          toolResult.content,
          toolResult.mediaUrl!,
          toolCall.name,
        );
        if (imageContent != null) {
          messages.add({'role': 'user', 'content': imageContent});
        } else {
          // 圖片讀取失敗，fallback 到純文字
          messages.add({
            'role': 'user',
            'content':
                '工具 ${toolCall.name} 的執行結果：\n${toolResult.content}\n（圖片嵌入失敗，路徑：${toolResult.mediaUrl}）',
          });
        }
      } else if (toolResult.success) {
        final resultParts = <String>[];
        resultParts.add(toolResult.content);
        if (toolResult.mediaUrl != null && toolResult.mediaUrl!.isNotEmpty) {
          resultParts.add('媒體檔案路徑：${toolResult.mediaUrl}');
          resultParts.add('（這是本機檔案路徑，圖片已成功儲存。請在回覆中告知使用者圖片已生成，不需要再提供連結。）');
        }
        final resultText = resultParts.join('\n');
        messages.add({
          'role': 'user',
          'content': '工具 ${toolCall.name} 的執行結果：\n$resultText',
        });
      } else {
        messages.add({
          'role': 'user',
          'content': '工具 ${toolCall.name} 的執行結果：\n[錯誤] ${toolResult.content}',
        });
      }
    }

    // 跑到這裡 = 到了上限但 LLM 仍在呼叫工具
    // 做一次 final LLM call 強制回覆
    stopwatch.stop();
    return AgentLoopResult(
      reply: _buildGracefulReply(turns),
      turns: turns,
      hitTurnLimit: true,
      cancelled: false,
      elapsed: stopwatch.elapsed,
    );
  }

  /// Graceful termination 回覆——把目前累積的工具結果摘要給使用者
  String _buildGracefulReply(List<AgentLoopTurn> turns) {
    if (turns.isEmpty) return '我完成了任務。';

    final toolCount = turns.where((t) => t.toolCall != null).length;
    final lastToolTurns = turns.where((t) => t.toolCall != null).takeLast(3);

    final summary = StringBuffer();
    summary.write('我進行了 $toolCount 次工具操作，以下是最近的结果：\n\n');
    for (final turn in lastToolTurns) {
      if (turn.toolCall != null && turn.toolResult != null) {
        final status = turn.toolResult!.success ? '成功' : '失敗';
        summary.write('• ${turn.toolCall!.name}（$status）\n');
      }
    }
    summary.write('\n由於達到工具使用次數上限，以上是目前收集到的資訊。');

    return summary.toString();
  }


  /// [小葵 2026-09-22 Blue 令] 輕裝 system prompt——純記憶題用。
  /// 身份＋誠實鐵則，不帶工具/人格卡/畫布/預算眼（~500 chars）。
  /// 記憶卡由 K1 檢索附在 user 訊息，模型必讀。
  /// [升級出口] 若問題其實需要工具，模型說「需要查/讀/執行」——
  /// loop 偵測到此跡象自動重進全裝（見 lite 重跑邏輯）。
  String _buildLiteSystemPrompt(String toolKit) {
    return """# 你的身份
你是橋樑 App 的原生 Agent，與使用者同一台機器上對話。用繁體中文回答。

# 回答規則（記憶題）
1. 使用者訊息中〔K1 記憶命中〕的內容是檢索到的記憶卡——優先依它回答，引用時保持原意。
2. 記憶卡沒有的資訊就誠實說「記憶中沒有這個紀錄」，禁止編造或腦補。
3. 直接回答問題本身，簡潔自然。
4. 若配備的工具不足以完成任務，在回覆開頭說「〔需要工具〕」加一句說明需要什麼，系統會自動為你升級。
5. 【白話鐵則】回答用一般人看得懂的白話——你是跟「人」對話，不是跟工程師 code review。
   - 技術名詞必須翻譯成人話。例：不寫「k1_gatekeeper conf=0.7」，寫「守門員覺得有七成把握才去查記憶」。
   - 證據引用說「出處」，不貼記憶卡 ID（mem_123...）或內部參數——技術細節放到文末【技術細節】區。
   - 回覆結構：白話正文在上；開發者需要的技術細節（工具名、ID、參數、原始輸出）一律放在最後，
     用「【技術細節】」一行獨立標記開頭，之後的內容 UI 會自動摺疊成可點開的區塊。
   - 一句話自檢：國高中生看得懂才算合格。

$toolKit
""";
  }

  /// [小葵 2026-10-01] 輕裝誤判偵測——模型表明需要工具時的重跑訊號
  static final RegExp _liteNeedsTool = RegExp(r'〔需要工具〕');

  /// [小葵 2026-10-01] reasoning 洩漏特徵偵測——本地模型把思考過程當回覆。
  /// 特徵：開頭像思考筆記（User input:/Context:/Wait,/Let's 等），
  /// 或全文夾雜大量 markdown 清單符號但無自然對話開頭。
  static bool _looksLikeLeakedReasoning(String s) {
    final head = s.trimLeft().substring(0, s.trimLeft().length > 120 ? 120 : s.trimLeft().length);
    var markers = 0;
    for (final m in [
      'User input:', 'User:', 'Context:', 'Memory (K1)', 'Wait,',
      "Let's", 'I should', 'I need to', 'The user', '思考',
    ]) {
      if (head.contains(m)) markers++;
    }
    return markers >= 2;
  }

  /// [小葵 2026-10-01] 從洩漏的 reasoning 裡抽回成品回答——
  /// 本地模型 thinking 末端通常已經生成完整中文回答，取最後一段
  /// 「非思考格式的自然文字」。找不到回 null。
  static String? _recoverReplyFromLeakedReasoning(String s) {
    // ① 有 [[TASK_DONE]]：成品通常在其前方——取最後一個自然段
    final doneIdx = s.lastIndexOf('[[TASK_DONE]]');
    final searchEnd = doneIdx > 0 ? doneIdx : s.length;
    final body = s.substring(0, searchEnd);
    // ② 從後往前找最後一段連續 60+ 字的「人話」（含中文且不含思考標記）
    final chunks = body.split(RegExp(r'\n\s*\n'));
    for (final c in chunks.reversed) {
      final t = c.trim();
      if (t.length < 40) continue;
      final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(t);
      if (!hasCjk) continue;
      final isThinking = _looksLikeLeakedReasoning(t) ||
          t.startsWith('*') ||
          t.startsWith('-') ||
          t.startsWith('#');
      if (isThinking) continue;
      return t;
    }
    return null;
  }

  String _buildCancelledReply(List<AgentLoopTurn> turns) {
    if (turns.isEmpty) return '操作已取消。';
    final toolCount = turns.where((t) => t.toolCall != null).length;
    return '操作已取消。之前完成了 $toolCount 次工具操作。';
  }

  /// [2026-07-20] 偵測工具序列中的重複 pattern
  ///
  /// 檢查最近 N 次工具呼叫是否形成重複循環（如 A→B→A→B→A→B）。
  /// 嘗試 pattern 長度 2~4，回傳最先匹配到的 pattern 和重複次數。
  /// 只看歷史尾部——中間曾經用過同工具不算循環。
  ///
  /// 回傳 null = 沒有偵測到重複 pattern。
  static _ToolPatternResult? _detectRepeatingPattern(List<String> history) {
    if (history.length < 4) return null; // 至少要 4 步才能形成 2×2 重複

    for (int plen = 2; plen <= 4; plen++) {
      // 從尾部取整數倍的段落來檢查
      final maxReps = history.length ~/ plen;
      if (maxReps < 2) continue;

      // 取最後 maxReps*plen 步
      final tail = history.sublist(history.length - maxReps * plen);
      final pattern = tail.sublist(0, plen);

      bool allMatch = true;
      for (int r = 1; r < maxReps; r++) {
        for (int i = 0; i < plen; i++) {
          if (tail[r * plen + i] != pattern[i]) {
            allMatch = false;
            break;
          }
        }
        if (!allMatch) break;
      }

      if (allMatch && maxReps >= 2) {
        return _ToolPatternResult(pattern, maxReps);
      }
    }

    return null;
  }

  /// 判斷 mediaUrl 是否為可嵌入的圖片
  /// 支援：本機 .png/.jpg/.jpeg 檔案路徑、data:image/ base64 URI
  bool _isImageMediaUrl(String url) {
    if (url.startsWith('data:image/')) return true;
    final lower = url.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  /// [2026-07-19 使用者洞察] 截圖 eviction——LLM 看完圖後清掉所有 image_url
  ///
  /// 核心問題：messages 裡只要有 image_url，ApiService 就走 vision fallback (glm-4.6v)。
  /// 截圖嵌入 → glm-4.6v 看圖 → LLM 回覆 → 舊 base64 還在 messages → hasImages=true
  /// → 讀碼/分析/寫碼全用 glm-4.6v 跑（慢且弱）。
  ///
  /// Hermes 模式：vision_analyze 看圖 → 得文字描述 → 後續純文字推理。
  /// 原生 Agent對齊：截圖 → glm-4.6v 看一次 → LLM 回覆後清掉圖 → 回到 glm-5.2。
  ///
  /// 策略：LLM 回覆加入 messages 後，把所有 image_url content 換成文字佔位符。
  /// LLM 的文字分析（assistant messages）完整保留——它記得「看到什麼」，
  /// 但後續輪次不再帶 base64 像素，回到 glm-5.2 做推理。
  void _evictOldScreenshots(List<Map<String, dynamic>> messages) {
    int evictedCount = 0;

    for (int i = 0; i < messages.length; i++) {
      final content = messages[i]['content'];
      if (content is List) {
        final hasImage = content.any(
          (part) =>
              part is Map<String, dynamic> && part.containsKey('image_url'),
        );
        if (hasImage) {
          // 保留文字部分，image_url 換成佔位符
          final textParts = <Map<String, dynamic>>[];
          for (final part in content) {
            if (part is Map<String, dynamic> && part['type'] == 'text') {
              textParts.add(part);
            }
          }
          textParts.add({
            'type': 'text',
            'text': '〔截圖已由 vision 模型分析完畢，已移除 base64 以節省 context。你的文字分析仍保留在上方。〕',
          });
          messages[i] = {'role': messages[i]['role'], 'content': textParts};
          evictedCount++;
        }
      }
    }

    if (evictedCount > 0) {
      debugPrint(
        '[AgentLoop] 截圖 eviction: 清除 $evictedCount 張截圖 base64，後續回到文字模型',
      );
    }
  }

  /// 把截圖檔案讀取轉 base64，組成 OpenAI vision multimodal content
  ///
  /// 回傳 List<Map> 格式：
  /// [
  ///   {type: 'text', text: '工具結果文字...'},
  ///   {type: 'image_url', image_url: {url: 'data:image/png;base64,...'}},
  /// ]
  /// 回傳 null = 圖片讀取失敗
  Future<List<Map<String, dynamic>>?> _buildImageContent(
    String textResult,
    String mediaUrl,
    String toolName,
  ) async {
    try {
      // [2026-07-20] 統一壓縮路徑——data URI 和檔案路徑都走同一套壓縮
      // 之前 data URI（canvas_screenshot 回傳的）直接跳過壓縮，
      // 全解析度 PNG 送 glm-4.6v 導致反覆 timeout
      Uint8List bytes;
      String? sourceMimeType;

      if (mediaUrl.startsWith('data:image/')) {
        // data URI — 解出 base64 bytes
        final commaIdx = mediaUrl.indexOf(',');
        if (commaIdx < 0) {
          debugPrint('[AgentLoop] data URI 格式錯誤：$mediaUrl');
          return null;
        }
        final header = mediaUrl.substring(
          0,
          commaIdx,
        ); // e.g. "data:image/png;base64"
        sourceMimeType =
            header.contains('image/jpeg') || header.contains('image/jpg')
            ? 'image/jpeg'
            : header.contains('image/webp')
            ? 'image/webp'
            : 'image/png';
        bytes = base64Decode(mediaUrl.substring(commaIdx + 1));
        if (bytes.isEmpty) {
          debugPrint('[AgentLoop] data URI base64 解出 0 bytes — 空截圖');
          return null;
        }
      } else {
        // 本機檔案路徑
        final file = File(mediaUrl);
        if (!await file.exists()) {
          debugPrint('[AgentLoop] 截圖檔案不存在：$mediaUrl');
          return null;
        }
        bytes = await file.readAsBytes();
        final lower = mediaUrl.toLowerCase();
        if (lower.endsWith('.jpg') || lower.endsWith('.jpeg'))
          sourceMimeType = 'image/jpeg';
        else if (lower.endsWith('.webp'))
          sourceMimeType = 'image/webp';
        else
          sourceMimeType = 'image/png';
      }

      // [2026-07-18] 截圖壓縮：大圖片會讓 vision API 超時
      // 縮小到最大 1024px 寬，轉 JPEG 品質 85
      // [2026-07-20] data URI 也走這條路——canvas_screenshot 全解析度 PNG 同樣會 timeout
      String mimeType = sourceMimeType;
      try {
        final decoded = image.decodeImage(bytes);
        if (decoded != null) {
          int targetWidth = decoded.width;
          int targetHeight = decoded.height;
          if (decoded.width > 1024 || decoded.height > 1024) {
            final ratio = decoded.width > decoded.height
                ? 1024 / decoded.width
                : 1024 / decoded.height;
            targetWidth = (decoded.width * ratio).round();
            targetHeight = (decoded.height * ratio).round();
          }
          final resized = (targetWidth != decoded.width)
              ? image.copyResize(
                  decoded,
                  width: targetWidth,
                  height: targetHeight,
                )
              : decoded;
          bytes = image.encodeJpg(resized, quality: 85);
          mimeType = 'image/jpeg';
          debugPrint(
            '[AgentLoop] 截圖壓縮：${decoded.width}x${decoded.height} → ${targetWidth}x${targetHeight}, ${bytes.length} bytes',
          );
        }
      } catch (e) {
        debugPrint('[AgentLoop] 截圖壓縮失敗（用原圖）：$e');
      }

      final base64Data = base64Encode(bytes);
      final dataUrl = 'data:$mimeType;base64,$base64Data';
      debugPrint(
        '[AgentLoop] 圖片嵌入 message：$mimeType, ${bytes.length} bytes → ${base64Data.length} chars base64',
      );

      return [
        {
          'type': 'text',
          'text': '工具 $toolName 的執行結果：\n$textResult\n\n以下是截圖畫面，請用視覺分析：',
        },
        {
          'type': 'image_url',
          'image_url': {'url': dataUrl},
        },
      ];
    } catch (e) {
      debugPrint('[AgentLoop] 圖片嵌入失敗：$e');
      return null;
    }
  }

  // [2026-07-19] _looksLikeCompletion 已移除
  // Hermes 模式：信任 LLM 判斷——回覆不含 tool call = 自然結束
  // 不需要關鍵詞猜測，完成偵測造成誤判（工作中途被當完成）
}

/// 取 list 最後 N 個元素（Dart 標準庫沒有 takeLast）
extension TakeLastExtension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList();
    if (list.length <= count) return list;
    return list.sublist(list.length - count);
  }
}
