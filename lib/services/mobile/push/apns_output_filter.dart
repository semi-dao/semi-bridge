// APNs 輸出濾網（APNs output filter）
// [S3 提前·蜂群演習二 Wave 2] 依據 BRIDGE_MOBILE_SPEC.md v0.5 §7「推播基礎設施」
// 拍板 A＋紅隊 #17 修訂條款（原文錨定）：
//
// 「通知文字只放開放層內容，APNs 送出前過輸出濾網（比對機密層實體清單，
//  命中即降級為『有新報告，請開 App 查看』）——LLM 轉譯若幻覺塞入帳本數字，
//  濾網攔截，不只靠紀律。」
//
// 三層設計（純函數模組：無 UI、無網路、無 DB）：
// 1. 開放層文字只放自然語言；機密層（專家模型/演算法/產量帳本）永遠不出家門。
// 2. 送出前比對「機密層實體清單」——命中即降級為固定文案，不外洩任何機密內容。
// 3. 比對用正規化（正規化後的字串包含關係），擋掉 LLM 幻覺塞入的帳本數字變體：
//    全形/半形、千分位逗號、頓號、連字號、空白、大小寫、繁簡、中文數字。
//
// 比對策略說明（為何用「正規化後包含」而非等值）：
// - LLM 幻覺的數字寫法與帳本原值格式不同（1,240 vs 1240 vs 1、240 vs 1.240）。
// - 機密詞可能以詞中/前綴/後綴形式出現（產量、總產量報表、餘額帳本）。
// - 命中即降級是 fail-closed（誤擋只多開一次 App，漏擋則機密外洩）——不對稱取捨。
//
// 純函數模組：無 UI、無網路、無 DB——蜂群演習二的品質範本（對照組）。

/// SPEC §7 拍板的降級文案（原文照抄，不可改寫）。
///
/// 命中機密層實體時的通知文字——不帶任何機密資訊、不帶任何數字。
const String kApnsFallbackText = '有新報告，請開 App 查看';

/// 過濾 APNs 推播通知文字。
///
/// 對外正式 API（紅隊 #5：測試必須綁這支正式實作，不可綁佔位草稿）。
///
/// [text] 待送出的通知文字（標題或內文）。
/// [confidentialTerms] 機密層實體清單（帳本數字、產量欄位名、金額、餘額…）。
///
/// 回傳：
/// - 命中任一機密詞 → [kApnsFallbackText]（固定降級，不洩漏原文與機密詞）。
/// - 未命中 → 原文字逐字回傳（標點、大小寫、全形、emoji 皆不動）。
///
/// 空文案／空清單 → 放行（fail-open 只限「沒有可比對的目標」）。
String pushNotificationText(String text, List<String> confidentialTerms) {
  if (text.isEmpty) return text;
  final normText = _normalizeForMatching(text);
  if (normText.isEmpty) return text;
  for (final term in confidentialTerms) {
    if (_hitsConfidentialTerm(normText, term)) return kApnsFallbackText;
  }
  return text;
}

/// 文字是否命中某個機密詞（含正規化變體比對）。
bool _hitsConfidentialTerm(String normText, String term) {
  final normTerm = _normalizeForMatching(term);
  if (normTerm.isEmpty) return false; // 空字串／純標點的清單項一律忽略

  // 1. 直接包含（已吃下正規化後的格式差異）
  if (normText.contains(normTerm)) return true;

  // 2. 數字變體互比（中文數字 ↔ 阿拉伯數字；帳本數字幻覺的主要洩漏路徑）
  return _numericAliasHit(normText, normTerm);
}

/// 中文數字別名的最低門檻值。
///
/// 低於三位數（< 100）不產生中文別名——「一」「十」「百」單字在中文語境
/// 極易成為假陽性（「十分」「一百個」）；誤擋只多開一次 App，但規則必須夠嚴謹。
const int _minChineseAliasValue = 100;

/// 數字別名互比（純函數）。
///
/// 兩個方向：
/// - term 是阿拉伯數字 → 產生其中文寫法別名（含「两」變體），到文字裡找。
/// - term 是中文數字 → 解析出數值，到文字的阿拉伯數字裡找相同數值。
bool _numericAliasHit(String normText, String normTerm) {
  final termValue = int.tryParse(normTerm);
  if (termValue != null) {
    if (termValue < _minChineseAliasValue) return false;
    // 方向一：阿拉伯 term → 中文別名
    for (final alias in _chineseNumeralAliases(termValue)) {
      if (_containsBoundedRun(normText, alias)) return true;
    }
    // 方向一之補：文字中的中文數字 run 解析後數值相同
    for (final run in _chineseNumeralRuns(normText)) {
      if (_parseChineseNumeral(run) == termValue) return true;
    }
    return false;
  }

  // 方向二：中文 term → 阿拉伯數值，到文字裡找同值數字
  if (!_isAllChineseNumeralChars(normTerm)) return false;
  final value = _parseChineseNumeral(normTerm);
  if (value == null || value < _minChineseAliasValue) return false;
  return _containsArabicValue(normText, value);
}

/// 阿拉伯數字 → 中文數字別名（含「两」變體）。
List<String> _chineseNumeralAliases(int value) {
  final canonical = _arabicToChinese(value);
  final variants = <String>{canonical};
  if (canonical.contains('二')) variants.add(canonical.replaceAll('二', '两'));
  return variants.toList();
}

/// 文字中是否出現「值相同」的阿拉伯數字（正規化後）。
bool _containsArabicValue(String normText, int value) {
  for (final match in RegExp(r'\d+').allMatches(normText)) {
    final parsed = int.tryParse(match.group(0)!);
    if (parsed == value) return true;
  }
  return false;
}

/// 完整 run 比對——避免「一千二百四十」被「一千二百四十五」誤判為命中。
bool _containsBoundedRun(String haystack, String needle) {
  var index = haystack.indexOf(needle);
  while (index != -1) {
    final before = index == 0 ? '' : haystack[index - 1];
    final endIndex = index + needle.length;
    final after = endIndex >= haystack.length ? '' : haystack[endIndex];
    if (!_isChineseNumeralChar(before) && !_isChineseNumeralChar(after)) {
      return true;
    }
    index = haystack.indexOf(needle, index + 1);
  }
  return false;
}

// ─────────────────────────────────────────────────────────
// 正規化（全形→半形、繁→簡、剝分隔符、轉小寫）
// ─────────────────────────────────────────────────────────

/// 正規化字串——僅用於「比對」，不影響回傳給使用者的原文。
String _normalizeForMatching(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    var ch = String.fromCharCode(rune);
    ch = _toHalfWidth(ch);
    ch = _simplifyChar(ch);
    ch = ch.toLowerCase();
    if (_isSeparator(ch)) continue;
    buffer.write(ch);
  }
  return buffer.toString();
}

/// 全形 ASCII（U+FF01–U+FF5E）與全形空格（U+3000）→ 半形。
String _toHalfWidth(String ch) {
  final code = ch.codeUnitAt(0);
  if (code >= 0xFF01 && code <= 0xFF5E) {
    return String.fromCharCode(code - 0xFEE0);
  }
  if (code == 0x3000) return ' ';
  return ch;
}

/// 分隔符／標點（比對時直接剝掉——「1,240」「1、240」「2026-11-09」同形）。
const Set<String> _separatorChars = {
  ',', '.', ';', ':', '!', '?', '"', "'", '`', '(', ')', '[', ']', '{', '}',
  '<', '>', '/', '\\', '|', '-', '_', '+', '=', '*', '&', '^', '%', '\$', '#',
  '@', '~', '、', '。', '，', '；', '：', '！', '？', '「', '」', '『', '』',
  '（', '）', '《', '》', '〈', '〉', '【', '】', '…', '—', '–', '～', '·',
  '‧', '〜', '﹒', '﹕',
};

bool _isSeparator(String ch) {
  if (ch.trim().isEmpty) return true; // 空白（含全形空格、tab、換行）
  return _separatorChars.contains(ch);
}

/// 繁體→簡體常用對照（裁切版）——成對字串，每兩字一組「繁→簡」。
///
/// 涵蓋帳本/產量/金額/農場/技術等高頻詞；只收「確定的繁簡對應」，
/// 身份映射（繁簡同形）不入表。text 與 term 兩邊都套用同一張表，
/// 因此 term 用繁體或簡體寫都對得上。
///
/// 用成對字串而非 Map 字面值：省掉 90 行樣板噪音，且天然不可能有重複 key
/// （重複字元對＝自我映射，由 test/mobile/apns_filter_test.dart 的完整性測試擋掉）。
const String kApnsSimplifiedPairs =
    '產产帳账賬账餘余額额報报總总數数據据預预測测試试紀记錄录億亿萬万圓圆兩两幣币場场農农業业開开當当種种價价買买賣卖費费機机專专體体權权鑰钥'
    '電电腦脑軟软網网絡络監监線线壓压溫温濕湿陽阳葉叶實实莖茎運运輸输車车輛辆庫库貨货訂订單单轉转對对應应統统計计營营資资訊讯編编輯辑儲储讀读'
    '寫写設设驗验證证檢检檔档連连頁页視视圖图層层階阶級级別别類类態态狀状換换關关啟启動动靜静語语號号碼码參参備备冊册標标題题註注說说謝谢請请'
    '問问詞词譯译簡简虛虚構构畫画製制損损風风險险醫医療疗藥药劑剂準准確确誤误異异規规則则順顺優优勢势責责義义務务職职員员團团隊队組组織织領领'
    '導导幹干處处裡里裏里後后內内間间邊边東东週周時时歲岁節节慶庆賀贺歡欢誕诞續续聯联繫系話话閱阅尋寻篩筛選选擇择過过濾滤徑径軌轨跡迹歷历載载'
    '刪删復复複复繼继暫暂執执顯显隱隐議议論论歸归納纳範范聽听講讲調调溝沟協协進进敗败質质達达見见認认為为覺觉踐践壞坏錯错護护補补雜杂倉仓盤盘'
    '點点揀拣濃浓鹽盐養养診诊術术傳传穩稳變变減减趨趋環环佔占樣样個个積积淨净稅税貸贷還还現现結结戶户審审決决經经財财辦办書书會会舉举憑凭簽签'
    '憶忆攝摄頭头麥麦熱热卻却島岛貴贵禮礼贈赠寶宝將将髮发發发乾干麵面鐘钟儘尽盡尽嘗尝佈布眾众錶表菸烟煙烟撐撑遊游讚赞贊赞鑽钻齣出齡龄龍龙龜龟'
    '鹼碱黨党廠厂廣广廢废廚厨徵征徹彻恆恒愛爱慘惨慣惯慮虑憐怜憤愤懶懒懼惧戀恋戲戏戰战紮扎絲丝綁绑綢绸綜综綻绽綱纲綴缀綠绿緒绪締缔練练緘缄緞缎'
    '緣缘縣县縫缝縮缩縱纵績绩縷缕繃绷繕缮繞绕繡绣繩绳繳缴纏缠纖纤罷罢罰罚羅罗羨羡習习翹翘聖圣聰聪聲声肅肃脅胁脈脉腸肠膚肤臟脏與与興兴艙舱艦舰'
    '艱艰蘇苏藝艺蘭兰蝦虾蠻蛮衛卫衝冲裝装親亲覽览觀观觸触討讨訓训訪访許许訴诉詐诈評评詩诗誠诚該该詳详誌志課课誰谁談谈諒谅諾诺謀谋識识譜谱讓让'
    '豐丰賓宾賦赋賭赌購购賽赛贏赢贓赃趕赶躍跃軀躯軍军較较輔辅輕轻輝辉輩辈輪轮迴回這这遠远違违適适遺遗邁迈郵邮鄉乡鄰邻醞酝釀酿釋释鑑鉴針针釣钓'
    '鉛铅銀银銅铜鋪铺鋼钢錢钱鍵键鎮镇鏡镜鐵铁門门閉闭闆板闊阔闖闯陣阵際际隨随雖虽雞鸡離离難难雲云霧雾靈灵韓韩項项須须頻频顆颗顏颜願愿顧顾飄飘'
    '飯饭飲饮飾饰餅饼館馆馬马駕驾騎骑驚惊驢驴魚鱼鳥鸟鳴鸣鵝鹅鹹咸黃黄齊齐齒齿牀床潛潜瀉泻瀏浏燈灯燒烧爐炉犧牺瑪玛畢毕癢痒皚皑盜盗瞞瞒矯矫磚砖'
    '礙碍禍祸穌稣窩窝筆笔籃篮紐纽紛纷紙纸細细終终絕绝絹绢緊紧臺台臨临蟲虫記记詢询詔诏諸诸';

/// 繁→簡對照表（由 [kApnsSimplifiedPairs] 成對字串建構）。
final Map<String, String> _simplifiedTable = _buildSimplifiedTable();

Map<String, String> _buildSimplifiedTable() {
  final table = <String, String>{};
  final pairs = kApnsSimplifiedPairs;
  for (var i = 0; i + 1 < pairs.length; i += 2) {
    table[pairs[i]] = pairs[i + 1];
  }
  return table;
}

/// 單字繁→簡（無對應則原樣返回）。
String _simplifyChar(String ch) => _simplifiedTable[ch] ?? ch;

// ─────────────────────────────────────────────────────────
// 中文數字 ↔ 阿拉伯數字
// ─────────────────────────────────────────────────────────

const Map<String, int> _chineseDigits = {
  '零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '兩': 2, '三': 3, '四': 4,
  '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
};

const Map<String, int> _chineseSmallUnits = {
  '十': 10, '百': 100, '千': 1000,
};

const Map<String, int> _chineseBigUnits = {
  '万': 10000, '萬': 10000, '亿': 100000000, '億': 100000000,
};

bool _isChineseNumeralChar(String ch) =>
    _chineseDigits.containsKey(ch) ||
    _chineseSmallUnits.containsKey(ch) ||
    _chineseBigUnits.containsKey(ch);

bool _isAllChineseNumeralChars(String text) {
  if (text.isEmpty) return false;
  for (final ch in text.split('')) {
    if (!_isChineseNumeralChar(ch)) return false;
  }
  return true;
}

/// 中文數字字串 → 阿拉伯數值（不合法回 null）。
int? _parseChineseNumeral(String text) {
  if (text.isEmpty) return null;
  var total = 0;
  var section = 0;
  var number = 0;
  var hasDigit = false;
  for (final ch in text.split('')) {
    final digit = _chineseDigits[ch];
    if (digit != null) {
      number = digit;
      hasDigit = true;
      continue;
    }
    final small = _chineseSmallUnits[ch];
    if (small != null) {
      section += (number == 0 ? 1 : number) * small;
      number = 0;
      hasDigit = true;
      continue;
    }
    final big = _chineseBigUnits[ch];
    if (big != null) {
      total += (section + number) * big;
      section = 0;
      number = 0;
      hasDigit = true;
      continue;
    }
    return null;
  }
  if (!hasDigit) return null;
  return total + section + number;
}

/// 阿拉伯數值 → 中文數字字串（正整數；上限億位）。
String _arabicToChinese(int value) {
  if (value <= 0) return '零';
  final groups = <int>[];
  var rest = value;
  while (rest > 0) {
    groups.add(rest % 10000);
    rest ~/= 10000;
  }
  const unitBig = ['', '万', '亿'];
  final buffer = StringBuffer();
  var pendingZero = false;
  for (var i = groups.length - 1; i >= 0; i--) {
    final group = groups[i];
    if (group == 0) {
      if (buffer.isNotEmpty) pendingZero = true;
      continue;
    }
    if (pendingZero) {
      buffer.write('零');
      pendingZero = false;
    }
    buffer.write(_fourDigitSectionToChinese(group));
    if (i > 0) buffer.write(unitBig[i]);
  }
  var result = buffer.toString();
  if (result.startsWith('一十')) result = result.substring(1);
  return result;
}

/// 四位一節 → 中文（「1005」→「一千零五」）。
String _fourDigitSectionToChinese(int section) {
  const digits = '零一二三四五六七八九';
  const unitSmall = ['', '十', '百', '千'];
  final digitList = <int>[];
  var rest = section;
  for (var i = 0; i < 4; i++) {
    digitList.add(rest % 10);
    rest ~/= 10;
  }
  final buffer = StringBuffer();
  var zeroPending = false;
  for (var position = 3; position >= 0; position--) {
    final digit = digitList[position];
    if (digit == 0) {
      if (buffer.isNotEmpty) zeroPending = true;
    } else {
      if (zeroPending) {
        buffer.write('零');
        zeroPending = false;
      }
      buffer.write(digits[digit]);
      buffer.write(unitSmall[position]);
    }
  }
  return buffer.toString();
}

/// 文字中所有「中文數字 run」（最大連續段）。
List<String> _chineseNumeralRuns(String text) {
  final runs = <String>[];
  final current = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    if (_isChineseNumeralChar(ch)) {
      current.write(ch);
    } else if (current.isNotEmpty) {
      runs.add(current.toString());
      current.clear();
    }
  }
  if (current.isNotEmpty) runs.add(current.toString());
  return runs;
}
