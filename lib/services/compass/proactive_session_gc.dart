// proactive_session_gc.dart
// [Blue 令 2026-11-03 晚場] 主動回應對話生命週期管理——
// 「手動刪除＋重複的留新刪舊＋已結案自動清場」的後兩刀。
//
// 病例（conversations.json 實證）：20 條 proactive 對話——
//   「主動回應 10/29」×5（race 屍體，msgs=1 空殼）
//   「主動回應 11/3」×3（4 秒開 3 session 的 race）
//   「主動回應 10/20」×2、「10/17」×2
//   且 K1 卡已 done/resolved，那條 70 則的對話還躺在側欄。
//
// 三條規則（App 啟動時跑一次，fail-quiet）：
//   GC1 同日重複：同標題（主動回應 M/D）只留最新一條，舊的全進回收桶
//      （走 ConversationStore.delete＝軟刪除，後悔可救）。
//   GC2 結案清場：對話綁的待決策卡全部 done/dismissed → 對話進回收桶。
//      卡是資產（決策軌跡留 compass_store 永久保存），對話是過程——
//      決議完，過程退場，資產留存。
//   GC3 空殼清理：msgs ≤ 1 的 proactive 超過 3 天 → 回收桶（race 屍體）。
//
// 手動刪除不歸 GC 管——側欄選單＋墓碑機制（conversation_store.dart）
// 已保證「刪了不復活」。

import 'package:flutter/foundation.dart';

import '../conversation_store.dart';
import '../../models/conversation.dart';
import 'decision_card_store.dart';

class ProactiveSessionGc {
  ProactiveSessionGc._();
  static final ProactiveSessionGc instance = ProactiveSessionGc._();

  bool _done = false;

  /// [test] 每個測試案例新鮮跑（繞過 _done 冪等）。
  @visibleForTesting
  Future<Map<String, int>> runOncePublic() async {
    final result = await runOnceCore();
    return result;
  }

  /// App 啟動時跑一次（compass_bootstrap 尾端呼叫；冪等）。
  /// 回傳 {dedup: n, closed: n, stale: n} 供 log。
  Future<Map<String, int>> runOnce() async {
    if (_done) return {'dedup': 0, 'closed': 0, 'stale': 0};
    _done = true;
    return runOnceCore();
  }

  Future<Map<String, int>> runOnceCore() async {
    var dedup = 0, closed = 0, stale = 0;
    try {
      final all = await ConversationStore.getAll();
      final proactive = all
          .where((c) => c.type == ConversationType.proactive)
          .toList();
      if (proactive.isEmpty) return {'dedup': 0, 'closed': 0, 'stale': 0};

      // ── GC1 同日重複：留新刪舊 ──────────────────────
      final byTitle = <String, List<Conversation>>{};
      for (final c in proactive) {
        byTitle.putIfAbsent(c.title, () => []).add(c);
      }
      final now = DateTime.now();
      for (final entry in byTitle.entries) {
        final group = entry.value
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        for (final old in group.skip(1)) {
          await ConversationStore.delete(old.id);
          dedup++;
        }
      }

      // ── GC2 結案清場：綁定卡全結案 → 對話退場 ──────────
      // 用 unresolvedCards 反查：對話曾綁過卡（歷史軌跡）但現在沒有
      // 未結案卡 → 全結案。搭配 sqlite 直查綁定紀錄（含已結案卡）。
      final dbCards = DecisionCardStore.instance.cardsForGc();
      final cardByConv = <String, List<DecisionCard>>{};
      for (final card in dbCards) {
        final cid = card.conversationId;
        if (cid != null) {
          cardByConv.putIfAbsent(cid, () => []).add(card);
        }
      }
      for (final conv in proactive) {
        final convCards = cardByConv[conv.id];
        if (convCards == null || convCards.isEmpty) continue;
        final allResolved = convCards
            .every((c) => c.status == 'done' || c.status == 'dismissed');
        if (allResolved) {
          await ConversationStore.delete(conv.id);
          closed++;
        }
      }

      // ── GC3 空殼清理：≤1 則且超過 3 天 ────────────────
      for (final conv in proactive) {
        if (conv.messages.length > 1) continue;
        final age = now.difference(conv.updatedAt);
        if (age.inDays >= 3) {
          await ConversationStore.delete(conv.id);
          stale++;
        }
      }

      if (dedup + closed + stale > 0) {
        debugPrint('[ProactiveGC] ✅ 整理完成：重複 $dedup、結案清場 '
            '$closed、空殼 $stale（全部進回收桶可救回）');
      }
    } catch (e) {
      debugPrint('[ProactiveGC] fail-quiet: $e');
    }
    return {'dedup': dedup, 'closed': closed, 'stale': stale};
  }
}
