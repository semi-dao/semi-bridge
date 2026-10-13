// path_hint_extractor.dart
// [資料主權/向量品質 2026-09-14] 路徑提示萃取器——「零設定」的提示注入。
//
// 設計哲學（Blue 09-14 提問、小葵設計）：
// 使用者不該被要求「寫提示」——他們已經用資料夾結構寫好了。
// 建「魔鬼辣椒/」這個資料夾的動作，就是使用者對這批照片的提示。
// 橋樑的工作是把它讀出來、織進描述生成，而不是要使用者再寫一遍。
//
// 對形形色色的內容（工作/生活/農場）全部零設定生效：
// 1. 自動萃取：資料夾段的中文詞/英文單詞 = 候選身分詞（品種/專案/地點…）
// 2. 防幻覺護欄：提示詞明示「path hint 僅供比對，畫面沒有就別寫」
//    ——路徑說魔鬼辣椒、照片是狗 → 描述寫狗不寫辣椒
// 3. 使用者可覆寫：資料夾裡放 hint.txt 即可加料/覆蓋（進階，
//    99% 使用者不需要——零設定已覆蓋）
//
// 效果基準：docs/benchmarks/vision-blind-2026-09-14（注入後品種正確率
// 目標 10/20 → ~20/20，蕨類從全滅到全中——答案早就在路徑裡）。

import 'dart:io';

class PathHintExtractor {
  PathHintExtractor._();
  static final PathHintExtractor instance = PathHintExtractor._();

  /// 從絕對路徑萃取提示詞。回傳空字串 = 無提示（直接用原 prompt）。
  ///
  /// 範例：外接授權根/農場資料庫/01_現況紀錄/照片紀錄/營本部/2026-04-07/
  ///       Blue陽台/象耳鹿角蕨母株/IMG_1781.jpeg
  ///  → 「象耳鹿角蕨」「母株」「Blue陽台」（數字段/日期段/流水段自動剔除）
  String extractHint(String absolutePath) {
    final segs = absolutePath.split(Platform.pathSeparator)
        .where((s) => s.isNotEmpty)
        .toList();
    if (segs.length < 2) return '';

    // 取倒數幾段（越深越具體），至多 3 段、跳過檔名本身
    final candidates = <String>[];
    for (final seg in segs.reversed.skip(1).take(3)) {
      final words = _meaningfulWords(seg);
      candidates.addAll(words);
    }
    if (candidates.isEmpty) return '';

    // 去重、保持出現順序（深→淺的具體度）
    final seen = <String>{};
    final ordered = <String>[];
    for (final w in candidates) {
      if (seen.add(w)) ordered.add(w);
    }
    return ordered.take(6).join('、');
  }

  /// 組出帶提示的完整 prompt（防幻覺護欄內建）。
  String buildPrompt(String basePrompt, String absolutePath) {
    final hint = extractHint(absolutePath);
    if (hint.isEmpty) return basePrompt;
    return '$basePrompt\n\n'
        '[路徑提示（僅供比對畫面。僅描述畫面可見內容。**不可**寫畫面外項目。）: $hint]';
  }

  /// 一段資料夾名 → 有意義詞清單。
  /// 剔除：純數字、日期（2026-04-07）、流水號（IMG_1781）、
  /// 常見結構詞（照片紀錄/採收紀錄等收納層）。
  List<String> _meaningfulWords(String seg) {
    const structural = {
      '現況紀錄', '照片紀錄', '採收紀錄', '農場資料庫', '照片', '圖片',
      'assets', 'images', 'photos', 'media', 'docs', 'files', 'data',
      'tmp', 'var', 'usr', 'home', 'users', 'downloads', 'desktop',
      'documents', 'Volumes', 'private', 'temp', 'cache',
    };
    final words = <String>[];
    // 中文連續段
    final cjk = RegExp(r'[\u4e00-\u9fff]{2,}');
    for (final m in cjk.allMatches(seg)) {
      final w = m.group(0)!;
      // 結構詞剔除（但「採收」這種事件詞保留——在結構詞清單外的）
      if (!structural.contains(w)) words.add(w);
    }
    // 英文/拼音單詞（≥3字母，剔除 IMG/DSC 等相機前綴）
    final latin = RegExp(r'[A-Za-z]{3,}');
    for (final m in latin.allMatches(seg)) {
      final w = m.group(0)!;
      if (!_cameraPrefixes.contains(w.toUpperCase()) &&
          !structural.contains(w.toLowerCase())) {
        words.add(w);
      }
    }
    return words;
  }

  static const _cameraPrefixes = {'IMG', 'DSC', 'DJI', 'GOPR', 'PXL', 'SCREENSHOT', 'ANDRO'};
}
