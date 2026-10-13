import 'slot_filter.dart';

/// M0 交付物 2b：注入預算控制器 v2
///
/// 總預算 400 tokens。中文粗估 1 字 ≈ 1.2 token。
/// v2（Fable 驗收修正）：
///   - 估算樣板與實際輸出完全一致（含槽位標籤+換行）
///   - 回傳結構化結果（block + kept 清單），不用字串反推
///   - 每槽至少保一條（裁切不吞整槽）
///   - 注入用短序號（#1 #2…），ledger 對回真實 id（省預算）
class BudgetResult {
  BudgetResult(this.block, this.kept);
  final String block;            // 組好的注入區塊
  final List<MemoryCandidate> kept; // 實際保留的記憶（依序=序號）
}

class BudgetController {
  BudgetController({this.maxTokens = 400, this.similarityFloor = 0.55});

  final int maxTokens;
  final double similarityFloor;

  static int estimateTokens(String text) => (text.length * 1.2).ceil();

  BudgetResult assemble(List<MemoryCandidate> candidates) {
    // 1. 相似度地板（candidates 已按相似度降冪；K1 候選 floorExempt 免地板）
    final floorPass = candidates
        .where((c) => c.floorExempt || c.similarity >= similarityFloor)
        .toList();

    // 1.5 [Fable 🟡2] 內部 partition：K1 在前、M0 在後（各自保序）。
    //     K1 保護不外包給呼叫端排序——assemble 單獨被呼叫也成立。
    final overFloor = [
      ...floorPass.where((c) => c.source == 'k1'),
      ...floorPass.where((c) => c.source != 'k1'),
    ];

    // 2. 保證項：K1 全部（排最前）＋每槽第一條 M0（保多樣性）。
    // [M1 K1 獨立通道 2026-10-10 Fable 拍板] K1 是 need 判定的明確檢索，
    // 全列保證項且排在 M0 保證項之前；超預算先丟 M0 非保證、再丟 M0
    // 保證、最後才丟 K1 尾端（第 3、2 條）——K1 第一條永不丟。
    final guaranteed = <MemoryCandidate>[];
    for (final c in overFloor) {
      if (c.source == 'k1') guaranteed.add(c);
    }
    final seenSlots = <MemorySlot>{};
    for (final c in overFloor) {
      if (c.source == 'k1') continue;
      if (!seenSlots.contains(c.slot)) {
        seenSlots.add(c.slot);
        guaranteed.add(c);
      }
    }

    // 3. 從尾端丟非保證項直到符合預算（估算樣板=實際輸出格式）。
    //    kept 順序＝K1 在前（1.5 內部 partition 保證）→ 尾端先碰 M0
    //    保證項，丟完才輪到 K1 第 3、2 條；K1 第一條（kept[0]）由
    //    length<=1 防護永不丟（截短交給 _clip）。
    //    [Fable 🟡1] M0 純臂（K1 不在場）維持 M0 原語意：全保證即接受
    //    超額（Blue 拍板的是 K1 通道，不是 M0 預算語意）。
    final hasK1 = overFloor.any((c) => c.source == 'k1');
    var kept = List<MemoryCandidate>.from(overFloor);
    while (kept.isNotEmpty && _total(kept) > maxTokens) {
      // 找最後一個非保證項丟
      final idx = kept.lastIndexWhere((c) => !guaranteed.contains(c));
      if (idx >= 0) {
        kept.removeAt(idx);
        continue;
      }
      // 全是保證項：K1 在場才從尾端丟（M0 保證項先被丟，最後 K1 3/2 條）；
      // M0 純臂 break 接受超額（每槽至少保一條的 M0 承諾不變）
      if (kept.length <= 1) break;
      if (!hasK1) break;
      kept.removeLast();
    }

    // 4. 序號組裝（#1..#n），kept 順序即序號順序
    final buf = StringBuffer();
    for (var i = 0; i < kept.length; i++) {
      final c = kept[i];
      buf.writeln('[背景記憶#${i + 1}|${c.slot.label}] ${_clip(c.text)}');
    }
    return BudgetResult(buf.toString().trimRight(), kept);
  }

  /// 估算與輸出格式一字不差
  String _line(MemoryCandidate c, int seq) =>
      '[背景記憶#$seq|${c.slot.label}] ${_clip(c.text)}';

  int _total(List<MemoryCandidate> cs) {
    var sum = 0;
    for (var i = 0; i < cs.length; i++) {
      sum += estimateTokens('${_line(cs[i], i + 1)}\n');
    }
    return sum;
  }

  /// 單條記憶最長 120 字（rune 安全截斷）
  String _clip(String text) {
    final runes = text.runes.toList();
    if (runes.length <= 120) return text;
    return String.fromCharCodes(runes.sublist(0, 120)) + '…';
  }
}
