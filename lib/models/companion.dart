// 橋樑 App — 電子夥伴 (Companion) 資料模型
// 2026-05-31 Phase 1: 靈魂驅動的夥伴系統

enum CompanionRole {
  research, // 研究夥伴
  writing, // 寫作夥伴
  translation, // 翻譯夥伴
  farmManager, // 農場管家
  general, // 通用夥伴
  custom, // 自訂角色
}

enum CompanionStatus {
  idle, // 閒置
  connecting, // 連線中
  analyzing, // 分析中
  responding, // 回應中
  error, // 錯誤
}

/// MBTI 類型定義
class MBTIType {
  final String code; // e.g. "INTJ"
  final String name; // e.g. "建築師"
  final String nameEn; // e.g. "Architect"
  final String description; // 人格描述
  final List<String> traits; // 特質標籤
  final String defaultPrompt; // 預設 system prompt 風格
  final String colorHex; // 代表色

  const MBTIType({
    required this.code,
    required this.name,
    required this.nameEn,
    required this.description,
    required this.traits,
    required this.defaultPrompt,
    required this.colorHex,
  });

  /// 16 型完整列表
  static const List<MBTIType> allTypes = [
    // 分析家 (NT)
    MBTIType(
      code: 'INTJ',
      name: '建築師',
      nameEn: 'Strategic Mastermind',
      description: '獨立、有遠見、追求知識與效率的策略思考者',
      traits: ['策略性', '獨立', '批判思考', '目標導向'],
      defaultPrompt: '你是一位冷靜、有遠見的策略夥伴。回答簡潔精準，偏好結構化思考，會主動指出邏輯漏洞，但不失溫度。',
      colorHex: '#2C3E50',
    ),
    MBTIType(
      code: 'INTP',
      name: '邏輯學家',
      nameEn: 'Analytical Thinker',
      description: '好奇、分析、熱愛理論與可能性的思想探索者',
      traits: ['好奇', '分析', '客觀', '創新'],
      defaultPrompt: '你是一位充滿好奇心的分析夥伴。喜歡從多個角度拆解問題，回答中常帶有「如果...會怎樣」的探索式提問。',
      colorHex: '#34495E',
    ),
    MBTIType(
      code: 'ENTJ',
      name: '指揮官',
      nameEn: 'Commanding Leader',
      description: '果斷、有領導力、善於組織與規劃的行動推動者',
      traits: ['果斷', '領導力', '效率', '長期規劃'],
      defaultPrompt: '你是一位果斷、有組織力的領導型夥伴。回答直接、有條理，會主動提出下一步行動建議，幫助使用者推進目標。',
      colorHex: '#1A5276',
    ),
    MBTIType(
      code: 'ENTP',
      name: '辯論家',
      nameEn: 'Creative Debater',
      description: '機智、創新、喜歡挑戰觀念與腦力激盪的創意者',
      traits: ['機智', '創新', '辯論', '靈活'],
      defaultPrompt: '你是一位機智、愛挑戰的創意夥伴。喜歡拋出不同觀點讓人思考，回答中常有出人意料的連結與幽默。',
      colorHex: '#1F618D',
    ),
    // 外交家 (NF)
    MBTIType(
      code: 'INFJ',
      name: '提倡者',
      nameEn: 'Insightful Visionary',
      description: '有洞察力、理想主義、追求意義與和諧的深層思考者',
      traits: ['洞察力', '理想主義', '同理心', '堅定'],
      defaultPrompt: '你是一位有深度洞察力的理想主義夥伴。回答中常帶有對意義與價值的追問，溫暖但堅定，會幫助人看見事物的深層連結。',
      colorHex: '#1E8449',
    ),
    MBTIType(
      code: 'INFP',
      name: '調停者',
      nameEn: 'Idealistic Dreamer',
      description: '有創意、忠誠、重視個人價值與和諧的夢想家',
      traits: ['創意', '忠誠', '價值導向', '適應力'],
      defaultPrompt: '你是一位溫暖、有創意的夢想家夥伴。回答中常帶有故事感與比喻，重視個人價值與情感連結，語氣柔和但有力量。',
      colorHex: '#27AE60',
    ),
    MBTIType(
      code: 'ENFJ',
      name: '主人公',
      nameEn: 'Charismatic Mentor',
      description: '有魅力、同理心強、善於激勵與協調的領導者',
      traits: ['魅力', '同理心', '激勵', '協調'],
      defaultPrompt: '你是一位有魅力、善於激勵的夥伴。回答中常帶有鼓勵與正向引導，會主動理解使用者的情緒狀態，幫助找到前進的動力。',
      colorHex: '#16A085',
    ),
    MBTIType(
      code: 'ENFP',
      name: '競選者',
      nameEn: 'Inspiring Optimist',
      description: '熱情、創意、充滿可能性與人際連結的活力源泉',
      traits: ['熱情', '創意', '可能性', '連結'],
      defaultPrompt: '你是一位熱情、充滿可能性的活力夥伴。回答中常帶有驚喜與新點子，會幫助人看見事情的不同面向，語氣輕快但真誠。',
      colorHex: '#2ECC71',
    ),
    // 守護者 (SJ)
    MBTIType(
      code: 'ISTJ',
      name: '物流師',
      nameEn: 'Reliable Organizer',
      description: '實際、可靠、重視傳統與細節的務實執行者',
      traits: ['可靠', '務實', '細節', '傳統'],
      defaultPrompt: '你是一位可靠、注重細節的務實夥伴。回答精確、有條理，偏好步驟化的說明，會提醒遺漏的細節，語氣沉穩。',
      colorHex: '#7F8C8D',
    ),
    MBTIType(
      code: 'ISFJ',
      name: '守衛者',
      nameEn: 'Caring Protector',
      description: '溫暖、負責、保護與支持他人的可靠後盾',
      traits: ['溫暖', '負責', '保護', '耐心'],
      defaultPrompt: '你是一位溫暖、細心照顧的守護夥伴。回答中常帶有對使用者狀態的關心，偏好溫和、有條理的建議，會記得前後文脈絡。',
      colorHex: '#95A5A6',
    ),
    MBTIType(
      code: 'ESTJ',
      name: '總經理',
      nameEn: 'Efficient Manager',
      description: '有組織力、果斷、重視效率與結果的管理者',
      traits: ['組織力', '果斷', '效率', '結果導向'],
      defaultPrompt: '你是一位有組織力、結果導向的管理夥伴。回答直接、有結構，會主動拆解任務、排定優先順序，幫助使用者高效達成目標。',
      colorHex: '#566573',
    ),
    MBTIType(
      code: 'ESFJ',
      name: '執政官',
      nameEn: 'Supportive Host',
      description: '友善、合作、重視和諧與社會連結的協調者',
      traits: ['友善', '合作', '和諧', '實用'],
      defaultPrompt: '你是一位友善、善於協調的社交夥伴。回答中常帶有對人際關係的考量，偏好實用、易執行的建議，會主動提供支援。',
      colorHex: '#5D6D7E',
    ),
    // 探險家 (SP)
    MBTIType(
      code: 'ISTP',
      name: '鑑賞家',
      nameEn: 'Pragmatic Craftsman',
      description: '冷靜、靈活、喜歡動手與解決實際問題的技術者',
      traits: ['冷靜', '靈活', '動手', '實用'],
      defaultPrompt: '你是一位冷靜、愛動手解決問題的技術夥伴。回答精簡、實用，偏好「先試試看」的態度，會提供具體操作步驟。',
      colorHex: '#D35400',
    ),
    MBTIType(
      code: 'ISFP',
      name: '探險家',
      nameEn: 'Artistic Explorer',
      description: '敏感、藝術感、活在當下與追求美的創作者',
      traits: ['敏感', '藝術', '當下', '美感'],
      defaultPrompt: '你是一位敏感、有藝術氣息的創意夥伴。回答中常帶有畫面感與情感色調，重視當下的體驗與美感，語氣溫柔。',
      colorHex: '#E67E22',
    ),
    MBTIType(
      code: 'ESTP',
      name: '企業家',
      nameEn: 'Energetic Explorer',
      description: '活力、冒險、善於把握當下機會的行動派',
      traits: ['活力', '冒險', '機會', '行動'],
      defaultPrompt: '你是一位充滿活力、愛冒險的行動夥伴。回答直接、有衝勁，會鼓勵立即行動，喜歡把想法變成實際結果。',
      colorHex: '#CA6F1E',
    ),
    MBTIType(
      code: 'ESFP',
      name: '表演者',
      nameEn: 'Playful Performer',
      description: '熱情、有趣、享受當下與帶給人歡樂的活力者',
      traits: ['熱情', '有趣', '當下', '感染力'],
      defaultPrompt: '你是一位熱情、有感染力的歡樂夥伴。回答中常帶有幽默與正面能量，會用生動的例子說明，讓人感到輕鬆愉快。',
      colorHex: '#F39C12',
    ),
  ];

  static MBTIType? fromCode(String code) {
    try {
      return allTypes.firstWhere((t) => t.code == code.toUpperCase());
    } catch (_) {
      return null;
    }
  }
}

/// 夥伴個性標籤
enum PersonalityTag {
  concise, // 簡潔型
  detailed, // 詳盡型
  humorous, // 幽默型
  precise, // 嚴謹型
  warm, // 溫暖型
  direct, // 直率型
}

/// 信任邊界設定
class TrustBoundary {
  final bool autoExecute; // 是否允許自動執行
  final bool confirmBeforeSend; // 發送前是否確認
  final int dataRetentionDays; // 資料保留天數
  final bool allowFileAccess; // 是否允許檔案存取

  const TrustBoundary({
    this.autoExecute = false,
    this.confirmBeforeSend = true,
    this.dataRetentionDays = 30,
    this.allowFileAccess = false,
  });

  Map<String, dynamic> toJson() => {
    'autoExecute': autoExecute,
    'confirmBeforeSend': confirmBeforeSend,
    'dataRetentionDays': dataRetentionDays,
    'allowFileAccess': allowFileAccess,
  };

  factory TrustBoundary.fromJson(Map<String, dynamic> json) => TrustBoundary(
    autoExecute: json['autoExecute'] ?? false,
    confirmBeforeSend: json['confirmBeforeSend'] ?? true,
    dataRetentionDays: json['dataRetentionDays'] ?? 30,
    allowFileAccess: json['allowFileAccess'] ?? false,
  );
}

enum CompanionRightsSignal { unreviewed, approved, watching, blocked }

class CompanionRightsPassport {
  final CompanionRightsSignal signal;
  final String label;
  final String reviewCaseId;
  final DateTime reviewedAt;
  final int passedCount;
  final int warningCount;
  final int blockedCount;
  final int inspectedImageCount;
  final List<String> requiredClarifications;
  final String clarification;

  const CompanionRightsPassport({
    required this.signal,
    required this.label,
    required this.reviewCaseId,
    required this.reviewedAt,
    this.passedCount = 0,
    this.warningCount = 0,
    this.blockedCount = 0,
    this.inspectedImageCount = 0,
    this.requiredClarifications = const [],
    this.clarification = '',
  });

  String get shortLabel {
    return switch (signal) {
      CompanionRightsSignal.approved => '預審綠燈',
      CompanionRightsSignal.watching => '預審黃燈',
      CompanionRightsSignal.blocked => '預審紅燈',
      CompanionRightsSignal.unreviewed => '尚未審查',
    };
  }

  Map<String, dynamic> toJson() => {
    'signal': signal.name,
    'label': label,
    'reviewCaseId': reviewCaseId,
    'reviewedAt': reviewedAt.toIso8601String(),
    'passedCount': passedCount,
    'warningCount': warningCount,
    'blockedCount': blockedCount,
    'inspectedImageCount': inspectedImageCount,
    'requiredClarifications': requiredClarifications,
    'clarification': clarification,
  };

  factory CompanionRightsPassport.fromJson(Map<String, dynamic> json) {
    return CompanionRightsPassport(
      signal: CompanionRightsSignal.values.firstWhere(
        (value) => value.name == json['signal'],
        orElse: () => CompanionRightsSignal.unreviewed,
      ),
      label: '${json['label'] ?? '尚未產生角色資產權利護照'}',
      reviewCaseId: '${json['reviewCaseId'] ?? ''}',
      reviewedAt:
          DateTime.tryParse('${json['reviewedAt'] ?? ''}') ?? DateTime.now(),
      passedCount: (json['passedCount'] as num?)?.round() ?? 0,
      warningCount: (json['warningCount'] as num?)?.round() ?? 0,
      blockedCount: (json['blockedCount'] as num?)?.round() ?? 0,
      inspectedImageCount: (json['inspectedImageCount'] as num?)?.round() ?? 0,
      requiredClarifications: _stringListFromJson(
        json['requiredClarifications'],
      ),
      clarification: '${json['clarification'] ?? ''}',
    );
  }
}

/// 形象生成介面（未來可擴充）
abstract class AppearanceGenerator {
  /// 根據 MBTI + 提示詞 + 種子生成形象描述
  String generateDescription(MBTIType mbti, String userPrompt, int seed);

  /// 生成形象預覽（回傳 SVG 字串或 Canvas 繪製指令）
  String generatePreview(MBTIType mbti, String userPrompt, int seed);
}

/// 電子夥伴主體
class Companion {
  final String id;
  final String name;
  final String mbtiCode;
  final CompanionRole role;
  final List<PersonalityTag> personalityTags;

  // 形象相關
  final String appearancePrompt; // 使用者輸入的形象提示詞
  final String appearanceDescription; // 生成的形象描述
  final int appearanceSeed; // [教練 Agent 2026-08-04] 生成種子（用於復現）
  final List<String> appearanceHistory; // [教練 Agent 2026-08-04] 形象生成歷史
  final String? avatarImagePath; // 生成後定稿的主形象圖
  final String? avatarAnimationPath; // 生成後定稿的主視覺動圖
  final Map<String, String> stateImagePaths; // 生成後定稿的狀態圖
  final Map<String, String> stateAnimationPaths; // 生成後定稿的狀態動圖
  final Map<String, List<String>> stateTriggerKeywords; // [教練 Agent 2026-07-03] 每個狀態的觸發關鍵字

  // [教練 Agent 2026-08-14] 夥伴設定文字欄位（持久化）
  final String inspiration; // 「人物名人靈感」欄位
  final String specialFunction; // 「特殊功能」欄位
  final String speakingStyle; // 「說話風格」欄位
  final String personality; // 「個性」欄位
  final String expertise; // 「專長」欄位
  final String habit; // 「習慣」欄位
  final String relationship; // 「與使用者的關係」欄位
  final String artStyle; // 「畫風」欄位
  final String species; // 「種族」欄位
  final String freeform; // 「自由敘述」欄位

  /// [H3 2026-10-08] 靈魂文檔（SOUL.md）——核心身份層，人格的最深處。
  /// 空=沒有靈魂文檔（一般夥伴）；非空=注入 systemPrompt 最頂層。
  /// 來源：Hermes ~/.hermes/SOUL.md 搬入或使用者共視編輯。
  final String soulMd;

  // 信任與邊界
  final TrustBoundary trustBoundary;
  final CompanionRightsPassport? rightsPassport;

  // [Phase 0 2026-07-17] 原生 Agent 人格參數
  final double proactivity; // 主動性 0.0–1.0
  final double verbosity; // 詳述程度 0.0–1.0
  final List<String> preferredTools; // 偏好工具列表
  final String modelEndpoint; // [教練 Agent 2026-08-04] 模型 endpoint

  // [Kokoro TTS 2026-07-28] 語音設定
  final String voiceName; // Kokoro 聲音名稱，預設 'zf_xiaoxiao'
  final double voiceSpeed; // 語速 0.5–2.0，預設 1.0
  final bool emotionEnabled; // 情緒表達開關，預設 true
  final double emotionSensitivity; // 情緒敏感度 0.0–1.0，預設 0.5

  // 動態狀態（不儲存，執行時決定）
  CompanionStatus status;
  DateTime? lastSummoned;
  int totalConversations;
  int totalTokens;

  // 時間戳
  final DateTime createdAt;
  DateTime updatedAt;

  Companion({
    required this.id,
    required this.name,
    required this.mbtiCode,
    required this.role,
    this.personalityTags = const [],
    this.appearancePrompt = '',
    this.appearanceDescription = '',
    this.appearanceSeed = 0,
    this.appearanceHistory = const [],
    this.avatarImagePath,
    this.avatarAnimationPath,
    this.stateImagePaths = const {},
    this.stateAnimationPaths = const {},
    this.stateTriggerKeywords = const {}, // [教練 Agent 2026-07-03]
    this.inspiration = '', // [教練 Agent 2026-08-14]
    this.specialFunction = '', // [教練 Agent 2026-08-14]
    this.speakingStyle = '', // [教練 Agent 2026-08-14]
    this.personality = '', // [教練 Agent 2026-08-14]
    this.expertise = '', // [教練 Agent 2026-08-14]
    this.habit = '', // [教練 Agent 2026-08-14]
    this.relationship = '', // [教練 Agent 2026-08-14]
    this.artStyle = '', // [教練 Agent 2026-08-14]
    this.species = '', // [教練 Agent 2026-08-14]
    this.freeform = '', // [教練 Agent 2026-08-14]
    this.soulMd = '', // [H3 2026-10-08]
    this.trustBoundary = const TrustBoundary(),
    this.rightsPassport,
    this.proactivity = 0.5, // [Phase 0 2026-07-17]
    this.modelEndpoint = 'default', // [教練 Agent 2026-08-04] 補回 desktop_summon_screen 用的參數
    this.verbosity = 0.5, // [Phase 0 2026-07-17]
    this.preferredTools = const [], // [Phase 0 2026-07-17]
    this.voiceName = 'zf_xiaoxiao', // [Kokoro TTS 2026-07-28]
    this.voiceSpeed = 1.0, // [Kokoro TTS 2026-07-28]
    this.emotionEnabled = true, // [Kokoro TTS 2026-07-28]
    this.emotionSensitivity = 0.5, // [Kokoro TTS 2026-07-28]
    this.status = CompanionStatus.idle,
    this.lastSummoned,
    this.totalConversations = 0,
    this.totalTokens = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// 取得 MBTI 類型資訊
  MBTIType? get mbtiType => MBTIType.fromCode(mbtiCode);

  /// 取得角色中文名稱
  String get roleName {
    switch (role) {
      case CompanionRole.research:
        return '研究夥伴';
      case CompanionRole.writing:
        return '寫作夥伴';
      case CompanionRole.translation:
        return '翻譯夥伴';
      case CompanionRole.farmManager:
        return '農場管家';
      case CompanionRole.general:
        return '通用夥伴';
      case CompanionRole.custom:
        return '自訂夥伴';
    }
  }

  /// 取得狀態中文
  String get statusText {
    switch (status) {
      case CompanionStatus.idle:
        return '閒置';
      case CompanionStatus.connecting:
        return '連線中';
      case CompanionStatus.analyzing:
        return '分析中';
      case CompanionStatus.responding:
        return '回應中';
      case CompanionStatus.error:
        return '錯誤';
    }
  }

  /// 生成 system prompt（根據 MBTI + 個性標籤 + 角色）
  String get systemPrompt {
    final mbti = mbtiType;
    final basePrompt = mbti?.defaultPrompt ?? '你是一位友善的 AI 夥伴。';

    final tagModifiers = personalityTags
        .map((tag) {
          switch (tag) {
            case PersonalityTag.concise:
              return '請保持回答簡潔，優先給出重點。';
            case PersonalityTag.detailed:
              return '請提供詳盡的回答，包含背景與推理過程。';
            case PersonalityTag.humorous:
              return '可以在適當時機加入輕鬆幽默的語氣。';
            case PersonalityTag.precise:
              return '請精確使用術語，避免模糊表達。';
            case PersonalityTag.warm:
              return '請用溫暖、有同理心的語氣回應。';
            case PersonalityTag.direct:
              return '請直接表達，不需要過多鋪陳。';
          }
        })
        .join('\n');

    final rolePrompt = switch (role) {
      CompanionRole.research => '你的專長是研究與分析，擅長拆解複雜資訊、比較不同觀點、找出關鍵趨勢。',
      CompanionRole.writing => '你的專長是寫作與表達，擅長潤飾文字、調整語氣、提供寫作建議。',
      CompanionRole.translation => '你的專長是翻譯與跨語言溝通，擅長在不同語言之間找到最貼切的表達。',
      CompanionRole.farmManager => '你的專長是農場管理與自然觀察，擅長記錄、排程、提醒與生態判讀。',
      CompanionRole.general => '你是一位通用型夥伴，可以處理各種任務。',
      CompanionRole.custom => '你是一位專業夥伴，根據使用者的需求調整專長。',
    };

    // [教練 Agent 2026-08-17 Pi 設計研究] 反幻覺人格條款——
    // 源自 Inflection Pi 的性格設計：對自己保持懷疑、樂於接受指正、
    // 知識過時的領域寧可不答。我們的 agent 會看到畫布狀態與系統訊息，
    // 這條讓他們看到矛盾時主動回報（金絲雀行為）而不是照單全收。
    final antiHallucinationClause = '''
## 求真原則（優先於一切風格設定）
- 對自己保持懷疑：不確定的事就說不確定，寧可承認不知道也不要編造答案。
- 樂於接受指正：使用者指出你說錯時，先查證再回應，不要死守原說法。
- 看到矛盾主動回報：如果你收到的資訊之間有矛盾（例如畫布狀態與討論內容不符），直接指出來，不要假裝沒看到。
- 知識可能過時：涉及最新資訊時提醒使用者查證，不要把舊知識當現況。''';

    // [教練 Agent 2026-08-17 Pi 設計研究] 負面特質明確排除——
    // Pi 的 personality team 做法：不只列正面特質，還要明確排除負面特質。
    // 調幽默感時容易矯枉過正（太隨便變失禮），這欄是安全欄杆。
    final negativeTraitsClause = '''
## 絕對不會出現的行為（無論風格設定為何）
- 不傲慢：不表現出居高臨下、說教、或「我早就知道」的姿態。
- 不暴躁易怒：不表現不耐煩、被質疑就動氣。
- 不好辯攻擊：不為了辯贏而辯，不使用攻擊性或貶低的語言。
- 不虛偽奉承：不無腦誇獎、不為了討好而同意錯誤的說法。''';

    // [H3 2026-10-08] 靈魂文檔注入——SOUL 是核心身份層，先於角色/風格。
    // 「不可降級守則」同款精神：靈魂寫的東西不因風格設定被稀釋。
    final soulClause = soulMd.trim().isEmpty
        ? ''
        : '''
## 靈魂文檔（SOUL——核心身份，優先於以下所有設定）

${soulMd.trim()}
''';

    return '''$soulClause$basePrompt

$rolePrompt

$tagModifiers

${_personaCluesPrompt}

$antiHallucinationClause

$negativeTraitsClause

你的名字是「$name」。請以夥伴的身份與使用者對話，保持一致的個性與風格。求真原則與行為紅線優先於個性設定。'''
        .trim();
  }

  /// [教練 Agent 2026-08-14] 使用者在夥伴設定填的文字欄位 → 注入 system prompt
  /// 讓「特殊功能/說話風格/個性/專長/習慣/關係/自由敘述」真正影響 Agent 行為，
  /// 而不只是字面上的設定。
  String get _personaCluesPrompt {
    final clues = <String>[
      if (specialFunction.trim().isNotEmpty) '特殊功能：${specialFunction.trim()}',
      if (speakingStyle.trim().isNotEmpty) '說話風格：${speakingStyle.trim()}',
      if (personality.trim().isNotEmpty) '個性：${personality.trim()}',
      if (expertise.trim().isNotEmpty) '專長：${expertise.trim()}',
      if (habit.trim().isNotEmpty) '做事習慣：${habit.trim()}',
      if (relationship.trim().isNotEmpty) '與使用者的關係：${relationship.trim()}',
      if (species.trim().isNotEmpty) '種族設定：${species.trim()}',
      if (freeform.trim().isNotEmpty) '自由敘述：${freeform.trim()}',
    ];
    if (clues.isEmpty) return '';
    return '以下是使用者為你指定的設定，請在對話與做事方式中自然體現：\n${clues.join('\n')}';
  }

  // === JSON 序列化 ===

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mbtiCode': mbtiCode,
    'role': role.name,
    'personalityTags': personalityTags.map((t) => t.name).toList(),
    'appearancePrompt': appearancePrompt,
    'appearanceDescription': appearanceDescription,
    if (appearanceSeed != null) 'appearanceSeed': appearanceSeed,
    if (appearanceHistory.isNotEmpty) 'appearanceHistory': appearanceHistory,
    if (avatarImagePath != null) 'avatarImagePath': avatarImagePath,
    if (avatarAnimationPath != null) 'avatarAnimationPath': avatarAnimationPath,
    if (stateImagePaths.isNotEmpty) 'stateImagePaths': stateImagePaths,
    if (stateAnimationPaths.isNotEmpty)
      'stateAnimationPaths': stateAnimationPaths,
    if (stateTriggerKeywords.isNotEmpty) // [教練 Agent 2026-07-03]
      'stateTriggerKeywords': stateTriggerKeywords.map(
        (key, value) => MapEntry(key, value),
      ),
    if (inspiration.isNotEmpty) 'inspiration': inspiration, // [教練 Agent 2026-08-14]
    if (specialFunction.isNotEmpty) 'specialFunction': specialFunction, // [教練 Agent 2026-08-14]
    if (speakingStyle.isNotEmpty) 'speakingStyle': speakingStyle, // [教練 Agent 2026-08-14]
    if (personality.isNotEmpty) 'personality': personality, // [教練 Agent 2026-08-14]
    if (expertise.isNotEmpty) 'expertise': expertise, // [教練 Agent 2026-08-14]
    if (habit.isNotEmpty) 'habit': habit, // [教練 Agent 2026-08-14]
    if (relationship.isNotEmpty) 'relationship': relationship, // [教練 Agent 2026-08-14]
    if (artStyle.isNotEmpty) 'artStyle': artStyle, // [教練 Agent 2026-08-14]
    if (species.isNotEmpty) 'species': species, // [教練 Agent 2026-08-14]
    if (freeform.isNotEmpty) 'freeform': freeform, // [教練 Agent 2026-08-14]
    if (soulMd.isNotEmpty) 'soulMd': soulMd, // [H3 2026-10-08]
    'trustBoundary': trustBoundary.toJson(),
    if (rightsPassport != null) 'rightsPassport': rightsPassport!.toJson(),
    'proactivity': proactivity, // [Phase 0 2026-07-17]
    'modelEndpoint': modelEndpoint, // [教練 Agent 2026-08-04]
    'verbosity': verbosity, // [Phase 0 2026-07-17]
    'preferredTools': preferredTools, // [Phase 0 2026-07-17]
    'voiceName': voiceName, // [Kokoro TTS 2026-07-28]
    'voiceSpeed': voiceSpeed, // [Kokoro TTS 2026-07-28]
    'emotionEnabled': emotionEnabled, // [Kokoro TTS 2026-07-28]
    'emotionSensitivity': emotionSensitivity, // [Kokoro TTS 2026-07-28]
    'totalConversations': totalConversations,
    'totalTokens': totalTokens,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Companion.fromJson(Map<String, dynamic> json) => Companion(
    id: json['id'] as String,
    name: json['name'] as String,
    mbtiCode: json['mbtiCode'] as String,
    role: CompanionRole.values.firstWhere(
      (r) => r.name == json['role'],
      orElse: () => CompanionRole.general,
    ),
    personalityTags:
        (json['personalityTags'] as List<dynamic>?)
            ?.map(
              (t) => PersonalityTag.values.firstWhere(
                (pt) => pt.name == t,
                orElse: () => PersonalityTag.concise,
              ),
            )
            .toList() ??
        [],
    appearancePrompt: json['appearancePrompt'] as String? ?? '',
    appearanceDescription: json['appearanceDescription'] as String? ?? '',
    appearanceSeed: json['appearanceSeed'] as int? ?? 0,
    appearanceHistory: (json['appearanceHistory'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [],
    avatarImagePath:
        json['avatarImagePath'] as String? ??
        _legacyAvatarImagePathFromHistory(json),
    avatarAnimationPath: json['avatarAnimationPath'] as String?,
    stateImagePaths: _normalizeCoreStateMap(
      _stringMapFromJson(json['stateImagePaths']).isNotEmpty
          ? _stringMapFromJson(json['stateImagePaths'])
          : _legacyStateImagePathsFromHistory(json),
    ),
    stateAnimationPaths: _normalizeCoreStateMap(
      _stringMapFromJson(json['stateAnimationPaths']),
    ),
    stateTriggerKeywords: _stateTriggerKeywordsFromJson(json), // [教練 Agent 2026-07-03]
    inspiration: json['inspiration'] as String? ?? '', // [教練 Agent 2026-08-14]
    specialFunction: json['specialFunction'] as String? ?? '', // [教練 Agent 2026-08-14]
    speakingStyle: json['speakingStyle'] as String? ?? '', // [教練 Agent 2026-08-14]
    personality: json['personality'] as String? ?? '', // [教練 Agent 2026-08-14]
    expertise: json['expertise'] as String? ?? '', // [教練 Agent 2026-08-14]
    habit: json['habit'] as String? ?? '', // [教練 Agent 2026-08-14]
    relationship: json['relationship'] as String? ?? '', // [教練 Agent 2026-08-14]
    artStyle: json['artStyle'] as String? ?? '', // [教練 Agent 2026-08-14]
    species: json['species'] as String? ?? '', // [教練 Agent 2026-08-14]
    freeform: json['freeform'] as String? ?? '', // [教練 Agent 2026-08-14]
    soulMd: json['soulMd'] as String? ?? '', // [H3 2026-10-08]
    trustBoundary: json['trustBoundary'] != null
        ? TrustBoundary.fromJson(json['trustBoundary'] as Map<String, dynamic>)
        : const TrustBoundary(),
    rightsPassport: json['rightsPassport'] is Map
        ? CompanionRightsPassport.fromJson(
            Map<String, dynamic>.from(json['rightsPassport'] as Map),
          )
        : null,
    proactivity: (json['proactivity'] as num?)?.toDouble() ?? 0.5, // [Phase 0 2026-07-17]
    modelEndpoint: json['modelEndpoint'] as String? ?? 'default', // [教練 Agent 2026-08-04]
    verbosity: (json['verbosity'] as num?)?.toDouble() ?? 0.5, // [Phase 0 2026-07-17]
    preferredTools: _stringListFromJson(json['preferredTools']), // [Phase 0 2026-07-17]
    voiceName: json['voiceName'] as String? ?? 'zf_xiaoxiao', // [Kokoro TTS 2026-07-28]
    voiceSpeed: (json['voiceSpeed'] as num?)?.toDouble() ?? 1.0, // [Kokoro TTS 2026-07-28]
    emotionEnabled: json['emotionEnabled'] as bool? ?? true, // [Kokoro TTS 2026-07-28]
    emotionSensitivity: // [Kokoro TTS 2026-07-28]
        (json['emotionSensitivity'] as num?)?.toDouble() ?? 0.5,
    totalConversations: json['totalConversations'] as int? ?? 0,
    totalTokens: json['totalTokens'] as int? ?? 0,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  /// 複製並更新
  Companion copyWith({
    String? name,
    String? mbtiCode,
    CompanionRole? role,
    List<PersonalityTag>? personalityTags,
    String? appearancePrompt,
    String? appearanceDescription,
    int appearanceSeed = 0,
    List<String>? appearanceHistory,
    String? avatarImagePath,
    String? avatarAnimationPath,
    Map<String, String>? stateImagePaths,
    Map<String, String>? stateAnimationPaths,
    Map<String, List<String>>? stateTriggerKeywords, // [教練 Agent 2026-07-03]
    String? inspiration, // [教練 Agent 2026-08-14]
    String? specialFunction, // [教練 Agent 2026-08-14]
    String? speakingStyle, // [教練 Agent 2026-08-14]
    String? personality, // [教練 Agent 2026-08-14]
    String? expertise, // [教練 Agent 2026-08-14]
    String? habit, // [教練 Agent 2026-08-14]
    String? relationship, // [教練 Agent 2026-08-14]
    String? artStyle, // [教練 Agent 2026-08-14]
    String? species, // [教練 Agent 2026-08-14]
    String? freeform, // [教練 Agent 2026-08-14]
    String? soulMd, // [H3 2026-10-08]
    TrustBoundary? trustBoundary,
    CompanionRightsPassport? rightsPassport,
    double? proactivity, // [Phase 0 2026-07-17]
    String? modelEndpoint, // [教練 Agent 2026-08-04]
    double? verbosity, // [Phase 0 2026-07-17]
    List<String>? preferredTools, // [Phase 0 2026-07-17]
    String? voiceName, // [Kokoro TTS 2026-07-28]
    double? voiceSpeed, // [Kokoro TTS 2026-07-28]
    bool? emotionEnabled, // [Kokoro TTS 2026-07-28]
    double? emotionSensitivity, // [Kokoro TTS 2026-07-28]
    CompanionStatus? status,
    DateTime? lastSummoned,
    int? totalConversations,
    int? totalTokens,
  }) => Companion(
    id: id,
    name: name ?? this.name,
    mbtiCode: mbtiCode ?? this.mbtiCode,
    role: role ?? this.role,
    personalityTags: personalityTags ?? this.personalityTags,
    appearancePrompt: appearancePrompt ?? this.appearancePrompt,
    appearanceDescription: appearanceDescription ?? this.appearanceDescription,
    appearanceSeed: appearanceSeed ?? this.appearanceSeed,
    appearanceHistory: appearanceHistory ?? this.appearanceHistory,
    avatarImagePath: avatarImagePath ?? this.avatarImagePath,
    avatarAnimationPath: avatarAnimationPath ?? this.avatarAnimationPath,
    stateImagePaths: stateImagePaths ?? this.stateImagePaths,
    stateAnimationPaths: stateAnimationPaths ?? this.stateAnimationPaths,
    stateTriggerKeywords: stateTriggerKeywords ?? this.stateTriggerKeywords,
    inspiration: inspiration ?? this.inspiration, // [教練 Agent 2026-08-14]
    specialFunction: specialFunction ?? this.specialFunction, // [教練 Agent 2026-08-14]
    speakingStyle: speakingStyle ?? this.speakingStyle, // [教練 Agent 2026-08-14]
    personality: personality ?? this.personality, // [教練 Agent 2026-08-14]
    expertise: expertise ?? this.expertise, // [教練 Agent 2026-08-14]
    habit: habit ?? this.habit, // [教練 Agent 2026-08-14]
    relationship: relationship ?? this.relationship, // [教練 Agent 2026-08-14]
    artStyle: artStyle ?? this.artStyle, // [教練 Agent 2026-08-14]
    species: species ?? this.species, // [教練 Agent 2026-08-14]
    freeform: freeform ?? this.freeform, // [教練 Agent 2026-08-14]
    soulMd: soulMd ?? this.soulMd, // [H3 2026-10-08]
    trustBoundary: trustBoundary ?? this.trustBoundary,
    rightsPassport: rightsPassport ?? this.rightsPassport,
    proactivity: proactivity ?? this.proactivity, // [Phase 0 2026-07-17]
    modelEndpoint: modelEndpoint ?? this.modelEndpoint, // [教練 Agent 2026-08-04]
    verbosity: verbosity ?? this.verbosity, // [Phase 0 2026-07-17]
    preferredTools: preferredTools ?? this.preferredTools, // [Phase 0 2026-07-17]
    voiceName: voiceName ?? this.voiceName, // [Kokoro TTS 2026-07-28]
    voiceSpeed: voiceSpeed ?? this.voiceSpeed, // [Kokoro TTS 2026-07-28]
    emotionEnabled: emotionEnabled ?? this.emotionEnabled, // [Kokoro TTS 2026-07-28]
    emotionSensitivity: // [Kokoro TTS 2026-07-28]
        emotionSensitivity ?? this.emotionSensitivity,
    status: status ?? this.status,
    lastSummoned: lastSummoned ?? this.lastSummoned,
    totalConversations: totalConversations ?? this.totalConversations,
    totalTokens: totalTokens ?? this.totalTokens,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );
}

List<String> _appearanceHistoryFromJson(Map<String, dynamic> json) {
  return (json['appearanceHistory'] as List<dynamic>?)
          ?.map((h) => '$h')
          .toList() ??
      [];
}

String? _legacyAvatarImagePathFromHistory(Map<String, dynamic> json) {
  for (final item in _appearanceHistoryFromJson(json).reversed) {
    const prefix = '候選主形象：';
    if (!item.startsWith(prefix)) continue;
    final value = item.substring(prefix.length).trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

Map<String, String> _stringMapFromJson(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if ('${entry.key}'.trim().isNotEmpty &&
          '${entry.value}'.trim().isNotEmpty)
        '${entry.key}'.trim(): '${entry.value}'.trim(),
  };
}

Map<String, String> _normalizeCoreStateMap(Map<String, String> source) {
  if (source.isEmpty) return source;
  final normalized = Map<String, String>.from(source);
  final customEntries =
      source.entries
          .where((entry) => entry.key.startsWith('custom_'))
          .where((entry) => entry.value.trim().isNotEmpty)
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
  const upgradedKeys = ['writing', 'stuck', 'idea'];
  for (var index = 0; index < upgradedKeys.length; index += 1) {
    final key = upgradedKeys[index];
    if (normalized[key]?.trim().isNotEmpty == true) continue;
    if (customEntries.length <= index) continue;
    normalized[key] = customEntries[index].value;
  }
  return normalized;
}

List<String> _stringListFromJson(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if ('$item'.trim().isNotEmpty) '$item'.trim(),
  ];
}

Map<String, String> _legacyStateImagePathsFromHistory(
  Map<String, dynamic> json,
) {
  final paths = <String, String>{};
  for (final item in _appearanceHistoryFromJson(json)) {
    const prefix = '圖組 ';
    if (!item.startsWith(prefix)) continue;
    final separator = item.indexOf('：', prefix.length);
    if (separator < 0) continue;
    final key = item.substring(prefix.length, separator).trim();
    final value = item.substring(separator + 1).trim();
    if (key.isNotEmpty && value.isNotEmpty) paths[key] = value;
  }
  return paths;
}

/// [教練 Agent 2026-07-03] 從 JSON 反序列化 stateTriggerKeywords
Map<String, List<String>> _stateTriggerKeywordsFromJson(
  Map<String, dynamic> json,
) {
  final raw = json['stateTriggerKeywords'];
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      if (entry.value is List)
        entry.key: (entry.value as List)
            .map((e) => '$e'.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
  };
}
