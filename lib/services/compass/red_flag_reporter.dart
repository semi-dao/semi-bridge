// red_flag_reporter.dart
// [小葵 2026-10-19 殘件①] 紅旗報告員——CompassSelfGauge.redFlags() 的「嘴」。
//
// 病史：T9① 修好了羅盤的儀表（K1 escalate 過高/認知傷口堆積/覆蓋率偏低
// 都算得出紅旗），T12-③ 修好了開口管線（佇列持久化/證據閘/額度），
// 但把紅旗餵進嘴的生產者只有 DreamScheduler 凌晨夢一條路——
// App 半夜沒開、或紅旗白天才出現，儀表就永遠只算不說（Fable：
// 「T9① 只做了一半」的另一半）。
//
// 本類：紅旗去重記帳（同一類紅旗同日只報一次）＋委託 CompassSpeaker
// 開口（三閘仍在 speaker：信心/證據/額度）。生產者兩條：
//   - DreamScheduler 夜夢路（原有）
//   - DreamScheduler 白天心跳路（本刀新增，每小時節流）
//
// 記帳真相源：compass_meta key = speak_redflags_<yyyy-mm-dd>，
// 內容 = 已報紅旗的類別鍵 JSON 陣列（跨日自然重置）。
// 只在「真的入列了」才記帳——被閘擋下（無證據/額度滿）的紅旗
// 不記帳，下個小時重試（寧可遲到不可不說）。

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'compass_speaker.dart';
import 'compass_store.dart';

/// 紅旗類別鍵——紅旗文字含動態數字（「未結案傷口 7 筆」），
/// 逐字比對會漏去重；把數字歸一成 # 再截斷，同類紅旗隔天數字變了
/// 仍是同一類。
String redFlagCategoryKey(String flag) {
  final normalized = flag.replaceAll(RegExp(r'[0-9]+'), '#');
  return normalized.length > 24 ? normalized.substring(0, 24) : normalized;
}

class RedFlagReporter {
  RedFlagReporter._();
  static final RedFlagReporter instance = RedFlagReporter._();

  /// 當日記帳 key（speak_redflags_yyyy-mm-dd）
  String dayKey([DateTime? now]) {
    final n = now ?? DateTime.now();
    return 'speak_redflags_'
        '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Set<String> _reportedToday() {
    try {
      final j = CompassStore.instance.getMeta(dayKey());
      if (j == null || j.isEmpty) return {};
      return (jsonDecode(j) as List).cast<String>().toSet();
    } catch (_) {
      return {}; // 讀不到帳＝當作沒報過（fail-open：寧可重複不可漏報）
    }
  }

  void _markReported(Set<String> keys) {
    try {
      CompassStore.instance.setMeta(dayKey(), jsonEncode(keys.toList()));
    } catch (_) {} // fail-quiet：記帳失敗最壞情況=明天多說一次
  }

  /// 回報紅旗。同類已報的靜默跳過；新紅旗湊一則開口草稿委託 speaker。
  /// 回傳 true＝本次有新紅旗入列（供呼叫端 log）。
  bool report(List<String> flags, {String source = 'unspecified'}) {
    if (flags.isEmpty) return false;
    final reported = _reportedToday();
    final fresh = flags.where((f) => !reported.contains(redFlagCategoryKey(f))).toList();
    if (fresh.isEmpty) return false;

    // 信心沿用夢路原版推導：1 紅旗=0.80、2=0.90、3+=0.95
    final conf = switch (fresh.length) {
      1 => 0.80,
      2 => 0.90,
      _ => 0.95,
    };
    final added = CompassSpeaker.instance.tryEnqueue(CompassSpeakDraft(
      '整理內部時我注意到一些狀況（${fresh.take(2).join('；')}）。'
      '不急，你有空的時候可以看看羅盤頁。',
      '$source:${fresh.length}',
      conf,
      // 證據主體沿用夢路結論：K1/工具循環/傷口證據都在 agent.loop
      organId: 'agent.loop',
    ));
    if (added) {
      for (final f in fresh) {
        reported.add(redFlagCategoryKey(f));
      }
      _markReported(reported);
      debugPrint('[RedFlagReporter] $source 報了 ${fresh.length} 面紅旗');
    }
    return added;
  }
}
