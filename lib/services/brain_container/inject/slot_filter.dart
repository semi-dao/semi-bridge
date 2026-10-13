/// M0 交付物 2a：typed slot 過濾器 v2
///
/// 四槽位限額（Fable M0 規格）：
///   慣例(habit) 2 / 偏好(preference) 1 / 信念(belief) 1 / 近期(recent) 1
/// v2（Fable 驗收修正）：
///   - memory_type 判定全部跑完，標題關鍵字只在 type 未知時當退路
///   - 「必」「禁」單字太寬鬆 → 改精確片語（鐵則/禁令/必須/永不/不可）
class MemoryCandidate {
  MemoryCandidate({
    required this.id,
    required this.text,
    required this.similarity,
    required this.slot,
    this.source = 'm0',
    this.floorExempt = false,
  });

  final String id;
  final String text;
  final double similarity;
  final MemorySlot slot;

  /// 候選來源：'m0'（semantic top20）或 'k1'（K1 命中 hybrid top3）。
  /// [小葵 2026-10-10 M1] Fable delta：量綱不同（RRF vs semantic），
  /// K1 候選免相似度地板、標記來源供歸因。
  final String source;

  /// K1 候選免相似度地板（hybrid RRF 分數與 semantic 分數不可比）。
  final bool floorExempt;
}

enum MemorySlot {
  habit('慣例', 2),
  preference('偏好', 1),
  belief('信念', 1),
  recent('近期', 1);

  const MemorySlot(this.label, this.quota);
  final String label;
  final int quota;
}

class SlotFilter {
  /// 丟棄計數（歸不進槽位的候選）——觀測用，避免某類記憶永遠不注入沒人知
  int droppedCount = 0;

  /// 槽位判定：memory_type 為主，標題關鍵字僅在 type 未知時退路
  static MemorySlot? slotOf({String? memoryType, String? layer, String? title}) {
    // ---- 第一優先：memory_type（精確映射 brain_schema 遷移）----
    final mt = (memoryType ?? '').toLowerCase();
    if (mt.isNotEmpty) {
      if (mt.contains('persona') || mt.contains('identity')) {
        return MemorySlot.preference;
      }
      if (mt.contains('lesson') || mt.contains('pattern') || mt.contains('skill')) {
        return MemorySlot.habit;
      }
      if (mt.contains('milestone') || mt.contains('reflection')) {
        return MemorySlot.belief;
      }
      if (mt.contains('conversation') || mt.contains('migration')) {
        return MemorySlot.recent;
      }
    }
    // ---- 第二優先：layer 佐證 ----
    switch (layer) {
      case 'L1':
        return MemorySlot.habit; // 鐵則層
      case 'L4':
        return MemorySlot.belief;
      case 'L8':
        return MemorySlot.recent;
      case null:
      case '':
        break;
      default:
        break;
    }
    // ---- 退路：type 完全未知才看標題關鍵字（精確片語）----
    final t = title ?? '';
    if (t.contains('鐵則') || t.contains('禁令') || t.contains('必須') ||
        t.contains('永不') || t.contains('不可')) {
      return MemorySlot.habit;
    }
    return null;
  }

  /// 過濾＋限額：M0 走四槽 quota；K1 走獨立上限（不佔槽）。
  /// [M1 K1 獨立通道 2026-10-10 Fable 拍板] K1 是 need 判定的明確檢索，
  /// 不該擠壓背景記憶的槽位——M0 四槽規則一字不動，K1 依 hybrid 名次
  /// 取前 k1Quota 條（預設 3）。行標籤保留 parsed slot（語意不丟）。
  List<MemoryCandidate> apply(List<MemoryCandidate> candidates,
      {int k1Quota = 3}) {
    droppedCount = 0;
    final out = <MemoryCandidate>[];
    final m0BySlot = <MemorySlot, List<MemoryCandidate>>{};
    final k1List = <MemoryCandidate>[];
    for (final c in candidates) {
      if (c.source == 'k1') {
        k1List.add(c);
      } else {
        m0BySlot.putIfAbsent(c.slot, () => []).add(c);
      }
    }

    // M0：四槽各依相似度取 quota
    for (final slot in MemorySlot.values) {
      final list = m0BySlot[slot];
      if (list == null || list.isEmpty) continue;
      list.sort((a, b) => b.similarity.compareTo(a.similarity));
      out.addAll(list.take(slot.quota));
    }

    // K1：獨立上限（名次分數已由 preparer 依 hybrid 名次降冪給定）
    k1List.sort((a, b) => b.similarity.compareTo(a.similarity));
    out.addAll(k1List.take(k1Quota));

    droppedCount = candidates.length - out.length;
    // 最終序：K1 優先（明確 need 的檢索結果），其餘依相似度。
    out.sort((a, b) {
      final k = (a.source == 'k1' ? 0 : 1) - (b.source == 'k1' ? 0 : 1);
      if (k != 0) return k;
      return b.similarity.compareTo(a.similarity);
    });
    return out;
  }
}
