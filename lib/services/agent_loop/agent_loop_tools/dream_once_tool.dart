// [小葵 2026-09-21] R5——dream_once agent tool
// 做一場夢：組真實議程（儀表紅燈＋統計＋遺憾清單）→ DreamService
// → 結論卡入生命樹 → 白話摘要回給使用者。
// 掛載：agent_tool_registry（Blue 或任何 companion 可叫 agent 做夢）。

import '../agent_tool.dart';
import '../../compass/compass_self_gauge.dart';
import '../../compass/compass_store.dart';
import '../../life_tree/dream_service.dart';
import '../../life_tree/dream_reflection.dart'; // [小葵 2026-09-22] LLM 深夢
import '../../life_tree/global_notice_channel.dart';
import 'package:flutter/foundation.dart';
import '../../life_tree/life_tree_store.dart';
import '../../memory_layer_service.dart'; // [T3] 分層寫入+BeliefGate
import '../../belief_gate.dart'; // [T3] BeliefGateRejectedError

class DreamOnceTool extends AgentTool {
  @override
  String get name => 'dream_once';

  @override
  String get description =>
      '做一場夢：反思最近的運作（守門員判斷、傷口自癒、沒走的路），'
      '產出結論卡存入生命樹。適合在安靜時刻或使用者要求反思時呼叫。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'reason',
          description: '為什麼做這場夢（例如：使用者要求／定期反思）',
          required: false,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      // 議程三源——全部真實數據
      final gauge = CompassSelfGauge.instance;
      final metrics = gauge.compute();
      final redFlags = metrics.redFlags();
      final regrets = LifeTreeStore.instance.unrevisitedBranches(limit: 5);

      // [Blue 2026-09-21 拍板「夢境收尾」] pending 傷口進議程：
      // 夢裡驗證病灶——痊癒的自動銷案（傷口#38 教訓：
      // agent.mind 器官 9/19 建好了，傷口卻掛到今天）
      final wounds = _pendingWounds();
      final healedCount = <String>[];

      final result = DreamService.instance.runDream(
        redFlags: redFlags,
        metrics: metrics,
        regrets: regrets,
        pendingWounds: wounds,
        // 閉包包裝：銷案成功的記進 healedCount（方法本身觸及不到局部變數）
        woundHealer: (w) {
          final ok = _verifyAndCloseWound(w);
          if (ok) healedCount.add('#${w.pitfallId}（${w.toolName}）');
          return ok;
        },
        dreamers: const ['semiwasabi'],
      );

      // ── [小葵 2026-09-22 Blue 規格] LLM 深夢——向量選材＋敘事反思 ──
      // 規則版先收帳（確定論）；深夢再想「有沒有想到了什麼」。
      // 選材：EmbeddingGemma 向量檢索（本地零 token），錨=紅燈+遺憾，
      // corpus=教訓+遺憾全文。每場 ≤8K tokens。
      // 產出價值（Blue）：明天主動告訴使用者「你想到了什麼」——
      // 也許是好答案也許不是，誠實標示，不是解決報告。
      String? deepThought;
      try {
        final anchors = <String>[...redFlags];
        for (final r in regrets) {
          anchors.add(r.thought);
        }
        final corpus = <(int, String)>[
          for (final r in regrets) (r.id ?? 0, r.thought),
        ];
        // 加入未結案傷口文本（有明確難題的題材）
        for (final w in wounds) {
          corpus.add((w.pitfallId, w.text));
        }
        // [小葵 2026-09-22 Blue 夢境架構] 歷史教訓入 corpus——
        // 已修復/已自癒的傷口是最好的深夢題材（有難題、有解法、
        // 可反思「下次怎麼更早發現」）。REM 夢的糧食不是 pending
        // （那是淺眠規則夢的活兒），是「已呈現問題的策略反思」。
        for (final pid in _historyLessonIds()) {
          final t = _pitfallText(pid);
          if (t != null) corpus.add((pid, t));
        }
        if (anchors.isNotEmpty && corpus.length >= 2) {
          final topics = await DreamReflection.instance.selectTopics(
            anchors: anchors,
            corpus: corpus,
          );
          if (topics.isNotEmpty) {
            final deep = await DreamReflection.instance.reflect(
                topics: topics);
            if (deep.usedLlm) {
              deepThought = deep.reflection;
              // [小葵 2026-10-15 T3] 深夢環境事實 → BeliefGate 通道。
              // 偵測「環境/事實型」語句（規則版——寧漏勿誤），過 gate 寫 L4；
              // 被拒降級 L7（belief_pending）——夢的斷言沒有 3 次證據很正常，
              // 存證待驗，不硬寫信念。fail-open：任何失敗不影響夢報告。
              try {
                final fact = _extractEnvironmentFact(deep.reflection);
                if (fact != null) {
                  String memId;
                  String layerNote;
                  try {
                    memId = await MemoryLayerService.instance.write(
                      layer: MemoryLayer.l4Environment,
                      title: fact,
                      content: '深夢反思推論：${deep.reflection}',
                      tags: 'dream,environment',
                      memoryType: 'environment',
                    );
                    layerNote = 'L4（gate 通過）';
                  } on BeliefGateRejectedError {
                    memId = await MemoryLayerService.instance.write(
                      layer: MemoryLayer.l7ProjectCold,
                      title: '[待驗證] $fact',
                      content: '深夢反思推論：${deep.reflection}',
                      tags: 'dream,belief_pending',
                      memoryType: 'environment',
                    );
                    layerNote = 'L7（證據不足待驗）';
                  }
                  debugPrint('[DreamOnce] 環境事實入庫 $layerNote：$fact');
                }
              } catch (e) {
                debugPrint('[DreamOnce] 信念通道 fail-open: $e');
              }
              // 深夢結論入生命樹（草稿卡——「想到了什麼」需人複驗）
              LifeTreeStore.instance.addDream(LifeTreeDream(
                dreamSessionId: result.sessionId,
                branchType: 'agent_draft',
                conclusion: '深夢想到：${deep.reflection}',
                decision: 'escalate_to_user',
                sourceClues: [
                  '題材 ${topics.length} 群（向量選材）',
                  'token ~${deep.tokensIn}（預算 ${DreamReflection.kTokenBudget}）',
                ],
                companionIds: const ['semiwasabi'],
                modelUsed: deep.modelUsed,
                createdAt: DateTime.now(),
              ));
              GlobalNoticeChannel.instance.push(
                title: '夢裡想到了一件事，想提醒你',
                body: _clipForNotice(deep.reflection),
                kind: 'dream_insight',
              );
            }
          }
        }
      } catch (e) {
        // fail-open：深夢失敗不影響規則版收帳
        debugPrint('[DreamOnce] LLM 深夢跳過（fail-open）: $e');
      }

      final buf = StringBuffer();
      buf.writeln('## 夢境報告（${result.sessionId}）');
      buf.writeln();
      buf.writeln('本場結論卡 ${result.conclusions} 張，已存入生命樹夢境主幹。');
      buf.writeln();
      buf.writeln('白話摘要：');
      for (final s in result.summary) {
        buf.writeln('- $s');
      }
      if (healedCount.isNotEmpty) {
        buf.writeln();
        buf.writeln('本場銷案傷口：${healedCount.join('、')}');
      }
      buf.writeln();
      buf.writeln('（結論卡為草稿卡 agent_draft——經你確認或第二位 agent '
          '複驗後才升級為正式共識卡）');
      return AgentToolResult.success(buf.toString());
    } catch (e) {
      return AgentToolResult.failure('做夢失敗: $e');
    }
  }

  /// 撈 pending 傷口（compass_pitfalls 未自癒條目）
  List<PendingWound> _pendingWounds() {
    final wounds = <PendingWound>[];
    try {
      final store = CompassStore.instance;
      for (final oid in const ['agent.loop', 'canvas.engine', 'agent.tools',
          'agent.mcp', 'theme', 'vault', 'chat', 'chat.controller',
          'canvas.chat', 'canvas.storage']) {
        for (final p in store.pitfalls(oid)) {
          if (p.id == null) continue;
          // [小葵 2026-10-05 開案令] 認知傷口（幻讀族）也進夢：
          // 工具沒失敗但結論錯了——深夢最好的反思題材。
          final isWound = p.text.contains('【pending·傷口立案】') ||
              p.text.contains('【pending·認知傷口】');
          if (isWound &&
              !p.text.contains('【已自癒】') &&
              !p.text.contains('【夢境銷案')) {
            // 從傷口文字提取工具名：「...立案】<tool> 失敗：...」
            // （認知傷口無此格式 → 用 oid，顯示為器官名）
            final m = RegExp('】(\\S+) 失敗').firstMatch(p.text);
            wounds.add(PendingWound(
              pitfallId: p.id!,
              toolName: m?.group(1) ?? oid,
              text: p.text,
            ));
          }
        }
      }
    } catch (_) {}
    return wounds;
  }

  /// 驗證病灶並銷案：從傷口文字提取「不存在的器官」——
  /// 現在存在＝痊癒 → pitfall 改寫【夢境銷案】＋回 true
  bool _verifyAndCloseWound(PendingWound w) {
    try {
      final m = RegExp('器官 (\\S+?) 不存在').firstMatch(w.text);
      if (m == null) return false;
      final organId = m.group(1)!;
      final store = CompassStore.instance;
      final exists =
          store.organs(includeRetired: true).any((o) => o.id == organId);
      if (!exists) return false;
      // 痊癒——銷案（記錄誰治好的：器官誕生於傷口立案之後）
      store.replacePitfall(
        w.pitfallId,
        '${w.text}\n【夢境銷案 2026-09-21】病灶痊癒：器官 $organId 現已存在於羅盤'
            '（當初立案時還沒這個器官，後來建好了，傷口一直沒人結案）。',
        author: 'auto:dream',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 深夢提醒白話化截斷（全域通知用）
  /// [小葵 2026-10-15 T3] 萃取環境事實句——規則版（寧漏勿誤）。
  /// 命中特徵：「需要/應該/必須/切記」＋環境名詞對象。回 null＝不是環境事實。
  static String? _extractEnvironmentFact(String text) {
    for (final line in text.split('\n')) {
      final t = line.trim().replaceAll(RegExp(r'^[-*\d\.\s]+'), '');
      if (t.length < 6 || t.length > 80) continue;
      if (RegExp(r'(需要|應該|必須|切記|要注意|記得|依賴|喜好是|生長在)')
              .hasMatch(t) &&
          RegExp(r'(鹿角蕨|植物|澆水|光照|溫度|濕度|土壤|季節|路徑|埠|版本|'
                  r'時區|排程|模型|API|DB|備份)')
              .hasMatch(t)) {
        return t.length > 60 ? t.substring(0, 60) : t;
      }
    }
    return null;
  }

  static String _clipForNotice(String s) {
    final t = s.replaceAll(RegExp(r'[{}<>]'), '').trim();
    final lines = t.split('\n').where((l) => l.trim().isNotEmpty).take(4);
    return lines.join(' ').replaceAll(RegExp(r'\s+'), ' ');
  }

  /// 歷史教訓 pitfalls id（已修復/已自癒——深夢反思題材）
  static List<int> _historyLessonIds() {
    try {
      final store = CompassStore.instance;
      final ids = <int>[];
      for (final oid in const ['agent.loop', 'canvas.engine', 'agent.tools',
          'agent.mcp', 'theme', 'vault', 'chat', 'chat.controller',
          'canvas.chat', 'canvas.storage']) {
        for (final p in store.pitfalls(oid)) {
          if (p.id == null) continue;
          if (p.text.contains('【已修復') || p.text.contains('【已自癒】')) {
            ids.add(p.id!);
          }
        }
      }
      return ids;
    } catch (_) {
      return const [];
    }
  }

  static String? _pitfallText(int id) {
    try {
      // CompassStore 無單條查詢 API——從 pitfalls 清單撈
      for (final oid in const ['agent.loop', 'canvas.engine', 'agent.tools',
          'agent.mcp', 'theme', 'vault', 'chat', 'chat.controller',
          'canvas.chat', 'canvas.storage']) {
        for (final p in CompassStore.instance.pitfalls(oid)) {
          if (p.id == id) return p.text;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
