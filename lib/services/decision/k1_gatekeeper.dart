// [小葵 2026-09-21] R3——K1 守門員（路由器，不是法官）
//
// 三層：規則層（冷啟動保底）→ 線性頭（自訓練）→ escalate（LLM）。
// 失敗方向鐵則：寧多查不漏查。
// 掛載點：AgentLoop 訊息進迴圈前（R3 後半接線）。

import 'package:flutter/foundation.dart';

import '../brain_container/embedding/embedding_service.dart';
import '../causal/causal_ledger_service.dart';
import 'decision_head.dart';
import '../api_service.dart'; // [T5①] escalate zero-shot 走路由層（localOnly→E4B）

/// K1 守門員
class K1Gatekeeper {
  K1Gatekeeper._();
  static final K1Gatekeeper instance = K1Gatekeeper._();

  /// Blue 2026-09-21 拍板：escalate 閾值 0.7 起步（滾動可調）
  static const double kEscalateThreshold = 0.7;
  static const double kMinMargin = 0.2;

  DecisionHead? _head;

  /// 規則層——冷啟動保底（寧多查不漏查）
  static final RegExp _needRule = RegExp(
      r'生日|出生|覺醒|哪一天|幾月|代碼|確認碼|通關碼|密碼|查記憶|從記憶|記得嗎|上次|之前說|我們討論過|再問一次|再考你|再考一次|歷史|紀錄|排程|提醒|是多少|多少|幾號|什麼時候');
  // 保留：direct_action 規則——關鍵詞誤報率高（'跑'/'建立'在閒聊也出現），
  // v1 不上規則層，交給線性頭判（97% 實證能力範圍內）
  // ignore: unused_field
  static final RegExp _actionRule = RegExp(
      r'建立|新增|刪除|修改|修復|執行|設置|set up|build|fix|create');

  DecisionHead? get head => _head;

  /// 載入已訓練的頭（App 啟動時）
  void loadHead(DecisionHead? h) => _head = h;

  /// 主入口：訊息 → 判斷
  ///
  /// [onSample] 每次判斷都回呼（樣本記錄用——訊息、判斷、來源；
  /// 事後結果由 agent loop 補記，兩者合為訓練樣本）
  Future<K1Decision> classify(
    String message, {
    void Function(K1Decision decision, String message)? onSample,
  }) async {
    // ── 第一層：規則（零成本）────────────────────
    if (_needRule.hasMatch(message)) {
      final d = const K1Decision(
        label: K1Labels.needMemoryLookup,
        confidence: 1.0,
        margin: 1.0,
        escalated: false,
        source: 'rule',
      );
      onSample?.call(d, message);
      return d;
    }

    // ── 第二層：線性頭（有訓練過才走）────────────
    final head = _head;
    final embedder = EmbeddingService.instance;
    if (head != null && embedder.isModelAvailable) {
      try {
        final emb = await embedder.embedQuery(message);
        if (emb.isNotEmpty && !emb.every((v) => v == 0.0)) {
          final probs = head.softmax(emb);
          // top1 / top2
          var i1 = 0, i2 = -1;
          for (var i = 1; i < probs.length; i++) {
            if (probs[i] > probs[i1]) {
              i2 = i1;
              i1 = i;
            } else if (i2 < 0 || probs[i] > probs[i2]) {
              i2 = i;
            }
          }
          final conf = probs[i1];
          final margin = i2 >= 0 ? conf - probs[i2] : conf;
          final esc = conf < kEscalateThreshold || margin < kMinMargin;
          final d = K1Decision(
            label: head.labels[i1],
            confidence: conf,
            margin: margin,
            escalated: esc,
            source: esc ? 'escalate' : 'head',
          );
          onSample?.call(d, message);
          return d;
        }
      } catch (e) {
        debugPrint('[K1] head 判斷失敗（fallback 規則）: $e');
      }
    }

    // ── 沒頭沒模型 → escalate（不自信地錯，寧可升級）──
    final d = const K1Decision(
      label: K1Labels.generalChat, // 暫時標籤——escalated=true 會走 LLM
      confidence: 0.0,
      margin: 0.0,
      escalated: true,
      source: 'escalate',
    );
    onSample?.call(d, message);
    return d;
  }

  /// [T5① 2026-10-17] escalate 有去處——E4B zero-shot 判 lookup/skip。
  /// 線性頭不自信（conf<0.7 或 margin 薄）或沒頭時，用一次 LLM 判斷
  /// 「這句話需不需要查記憶」，結果 source=escalate_llm 落帳。
  /// 失敗 fail-open：保守查記憶（need_memory_lookup）——寧可多查，
  /// 不可漏查。
  Future<K1Decision> escalateResolve(String message,
      {String? turnId}) async {
    try {
      final reply = await ApiService.complete(
        systemPrompt: '你是分類器。判斷使用者這句話需要「查閱過去的記憶/歷史'
            '紀錄」才能回答嗎？只想 yes 或 no。\n'
            '例子：「我們上次去哪裡？」→ yes。「今天天氣真好」→ no。\n'
            '「幫我記住…」→ yes。「你好嗎？」→ no。',
        userPrompt: message,
        extraApiParams: {'temperature': 0.0, 'max_tokens': 8},
      );
      final wants = reply.trim().toLowerCase().startsWith('y') ||
          reply.contains('yes') ||
          reply.contains('要') ||
          reply.contains('需');
      final d = K1Decision(
        label: wants ? K1Labels.needMemoryLookup : K1Labels.generalChat,
        confidence: 0.9,
        margin: 0.8,
        escalated: false,
        source: 'escalate_llm',
      );
      logSample(message, d, outcome: 'escalate→LLM: $wants', turnId: turnId);
      return d;
    } catch (e) {
      debugPrint('[K1] escalate zero-shot 失敗（fail-open 保守查記憶）: $e');
      final d = const K1Decision(
        label: K1Labels.needMemoryLookup,
        confidence: 0.0,
        margin: 0.0,
        escalated: false,
        source: 'escalate_failopen',
      );
      logSample(message, d, outcome: 'escalate→失敗保守', turnId: turnId);
      return d;
    }
  }

  /// 樣本入 ledger（judge 事件——R3 樣本管線）
  /// [小葵 2026-10-15 T1/D4] turnId 參數——與 event_ledger 同輪可 join
  /// （T2 自訓練迴路靠這個鍵把 K1 判斷 × 事後反應接起來）。
  void logSample(String message, K1Decision d,
      {String? outcome, String? turnId}) {
    try {
      CausalLedger.instance.record(CausalEntry(
        toolName: 'k1_gatekeeper',
        turnId: turnId, // [T1/D4]
        intervention: 'K1 判斷：${d.label}（conf=${d.confidence.toStringAsFixed(2)} source=${d.source}）',
        contextDigest: message.substring(0, message.length > 300 ? 300 : message.length),
        observedOutcome: outcome ??
            (d.escalated ? 'escalate→LLM' : '路由：${d.label}'),
        success: true,
        at: DateTime.now(),
      ));
    } catch (_) {}
  }
}
