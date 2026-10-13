// realtime_voice_orchestrator.dart — 快答慢想雙軌語音協調器
//
// [小葵 2026-08-30] 對標 OpenAI Realtime 的開源答案。
//
// 核心創意（大家都在做的我們不重做；大家做不到的我們做）：
//
//   大家都在做：把 STT→LLM→TTS 管線壓快、追 speech-to-speech。
//   那條路的物理極限我們追不上（單模型 200ms vs 三段管線 2s+）。
//
//   我們多做兩件 OpenAI 做不到的事：
//   1. 快答慢想雙軌——快軌極小 prompt 先出「一句話重點」（1-2s），
//      慢軌完整 AgentLoop 照舊跑。使用者先聽到答案核心，細節隨後展開。
//   2. 畫面當第二通道——完整回答進聊天面板，語音只負責「先講重點+
//      接續朗讀」。純語音產品（OpenAI Realtime）沒有這個洩壓閥。
//
// 延遲帳（對比）：
//   舊：停口 → AgentLoop(3-8s) → 整段 Kokoro 合成(2-4s) → 第一個字
//   新：停口 → 快軌 LLM(~1.5s) → 首句 Kokoro(~0.3s) → 第一個字
//       ≈ 2 秒內聽到重點；慢軌細節持續展開。
//
// 事件流（單一權威時鐘，OpenAI session events 的對應物）：
//   userSpeechStart/End · turnEnd · fastReplyReady · fullReplyReady ·
//   ttsSegmentStarted/Done · bargeIn · error

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api_service.dart';
import '../tts/kokoro_tts_service.dart';
import 'companion_voice_settings.dart';
import 'native_audio_bytes_player.dart';
import 'voice_engine.dart' show parseEmotionTags;
import '../tts/minimax_tts_service.dart';

// ────────────────────────────────────────────────────────────
// 事件模型
// ────────────────────────────────────────────────────────────

/// 即時語音事件（UI 可訂閱做視覺回饋：波形、字幕、狀態燈）
enum RealtimeVoiceEventType {
  turnStarted,
  fastReplyReady, // 快軌重點出爐（即將出聲）
  fullReplyReady, // 慢軌完整回答出爐
  ttsSegmentStarted,
  ttsSegmentDone,
  bargeIn, // 使用者插嘴（語音佇列已 flush）
  error,
}

class RealtimeVoiceEvent {
  final RealtimeVoiceEventType type;
  final String? text;
  final String? detail;
  const RealtimeVoiceEvent(this.type, {this.text, this.detail});
}

/// 快軌 LLM 呼叫介面——測試可注入 mock
/// [recentLines] — 最近對話上下文（快軌不是金魚腦：接話需要語境）
typedef FastLaneLLMCall =
    Future<String> Function(String userText, List<String> recentLines);

/// [小葵 2026-09-24 Blue 毫秒決策令] 快軌語意記憶閃現——
/// 接球前先問向量大腦「我們聊過這個嗎」（768 維、本地、毫秒級）。
/// 回傳 0-3 條相關記憶片段；null 表示管線不可用（快軌照跑，只是沒靈感）。
typedef MemoryFlashCall =
    Future<List<String>?> Function(String userText);

/// 快軌回應分類——真人對話的三種「先開口」方式
///
/// [小葵 2026-08-31 Blue 洞察] 真人不是等答案備妥才開口：
/// - backchannel：接話打槍（「你知道嗎？」→「什麼事？」）——零思考，
///   對方還會繼續講，所以不派慢軌、繼續聽。內容由 LLM 對應語境生成，
///   絕不寫死（舊 VoiceBackchannelEngine 罐頭文字失敗的教訓）。
/// - direct：能一句話答完就直接答（現行快軌行為）。
/// - structure：答案複雜時先開口講「骨架」（「這有三個原因，我一一說」），
///   邊講邊織——骨架念完的時間正是慢軌織內容的時間。
enum FastLaneType { backchannel, direct, structure }

/// 快軌回應（分類 + 文字 + 情緒 + 建議語速）
class FastLaneReply {
final FastLaneType type;
final String text;
final String? emotion;

/// 語速——backchannel/structure 放慢（重點清晰），
/// direct 正常。韻律層次的其中一環。
final double speed;

const FastLaneReply({
  required this.type,
  required this.text,
  this.emotion,
  this.speed = 1.0,
});
}

/// 解析快軌 LLM 輸出：`<type>backchannel</type><emotion>curious</emotion>什麼事？`
///
/// 容錯：沒有標籤 → 整段視為 direct（寧可多念不可不念）。
FastLaneReply parseFastLaneReply(String raw) {
  // [小葵 2026-09-24 Blue 監聽抓包] MiniMax/深度思考模型的 <think> 內心
  // 獨白會混在快軌輸出——沒剝就會被 TTS 念出來（她把推理過程講出來了）。
  // 先剝 <think>...</think> 再解析標籤。
  var text = raw.trim();
  final thinkMatch =
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false).firstMatch(text);
  if (thinkMatch != null) {
    text = text.replaceFirst(thinkMatch.group(0)!, '').trim();
  } else if (text.startsWith('<think>')) {
    // 未閉合（串流中斷）：全部丟棄，保留空字串
    text = '';
  }
  FastLaneType type = FastLaneType.direct;
  String? emotion;

  final typeMatch = RegExp(r'<type>(\w+)</type>').firstMatch(text);
  if (typeMatch != null) {
    switch (typeMatch.group(1)) {
      case 'backchannel':
        type = FastLaneType.backchannel;
      case 'structure':
        type = FastLaneType.structure;
      default:
        type = FastLaneType.direct;
    }
    text = text.replaceFirst(typeMatch.group(0)!, '').trim();
  }

  final emoMatch =
      RegExp(r'<emotion>(\w+)</emotion>').firstMatch(text);
  if (emoMatch != null) {
    emotion = emoMatch.group(1);
    text = text.replaceFirst(emoMatch.group(0)!, '').trim();
  }

  return FastLaneReply(
    type: type,
    text: text,
    emotion: emotion,
    speed: switch (type) {
      FastLaneType.backchannel => 0.9, // 接話放慢——好奇、清晰
      FastLaneType.structure => 0.92, // 骨架放慢——對方要跟上結構
      FastLaneType.direct => 1.0,
    },
  );
}

// ────────────────────────────────────────────────────────────
// [小葵 2026-08-31] 非語言情緒表達 v2（Blue 兩個洞見）
//
// 1. 長度＝強度：「哈哈」和「哈～哈哈哈～哈哈」是不同的笑——
//    擬聲權重（哈的數量）決定語速與停頓：短笑輕快、長笑展開。
// 2. 標點框起來：LLM 用（）把非語言聲音框住（（哈哈）（唉～）），
//    解析零歧義——「哈士奇」永遠安全，框內的一定是聲音。
//    Kokoro 原生不會笑/呼吸（中立合成語音訓練），文字層擬聲是解法。
// ────────────────────────────────────────────────────────────

/// 擬聲結果段
class NvPart {
  final String text;

  /// 是否為非語言聲音（獨立 TTS 任務）
  final bool isNonverbal;

  /// 聲音強度——笑聲＝哈/嘻/嘿/呵的數量，其他聲音＝2。
  /// 決定語速與停頓：<=3 輕快 / 4-6 展開 / >=7 大笑。
  final int weight;
  const NvPart(this.text, this.isNonverbal, {this.weight = 1});
}

/// 框內允許的聲音字元（（）內容全屬於這些 → 是非語言段）
const Set<String> _soundChars = {
  '哈', '嘻', '嘿', '呵', '唉', '咳', '哇', '喔', '哦', '嗯', '哼',
  '～', '~', '，', '。', '！', '、', '…', ' ',
};

/// 連續笑聲 run：「哈哈」「哈～哈哈哈～哈哈」（含波浪連接）
final RegExp _laughRun = RegExp(r'[哈嘻嘿呵]{2,}(?:[～~\s]*[哈嘻嘿呵]+)*');

/// 邊界單聲（前後是標點/邊界才算——避免誤拆詞中字）
final RegExp _boundarySingle =
    RegExp(r'(?:^|[，。！？、～~…\s])(唉|咳咳|哇|喔喔|嗯哼)(?=$|[，。！？、～~…\s])');

bool _isSoundBurst(String s) =>
    s.runes.every((r) => _soundChars.contains(String.fromCharCode(r)));

/// 數笑聲字元數（哈/嘻/嘿/呵）
int _burstWeight(String s) {
  var n = 0;
  for (final c in ['哈', '嘻', '嘿', '呵']) {
    n += c.allMatches(s).length;
  }
  return n > 0 ? n : 2; // 非笑聲（唉～/咳咳）給中權重
}

/// 擬聲段的情緒
String _burstEmotion(String s) {
  if (s.contains('哈') || s.contains('嘻') || s.contains('嘿') || s.contains('呵')) {
    return 'amused';
  }
  if (s.contains('唉')) return 'sleepiness';
  if (s.contains('咳')) return 'neutral';
  return 'amused'; // 哇/喔/嗯哼
}

/// 把句子拆成 [正文, 聲音, 正文, ...] 序列。
///
/// 優先順序：①（）框起的純聲音段（零歧義）②連續笑聲 run
/// （「哈～哈哈哈」任意長度）③邊界單聲（唉/咳咳/哇…前後需標點）。
List<NvPart> splitNonverbalTokens(String sentence) {
  final out = <NvPart>[];
  var rest = sentence;

  // ① 括號段
  final bracketRe = RegExp(r'（([^（）]+)）');
  while (true) {
    final m = bracketRe.firstMatch(rest);
    if (m == null) break;
    if (m.start > 0) _emitBare(rest.substring(0, m.start), out);
    final content = m.group(1)!;
    if (_isSoundBurst(content)) {
      out.add(NvPart(content, true, weight: _burstWeight(content)));
    } else {
      out.add(NvPart(m.group(0)!, false)); // 一般括號註記——正文
    }
    rest = rest.substring(m.end);
  }

  if (rest.isNotEmpty) _emitBare(rest, out);
  return out;
}

/// 無括號段的拆分：②笑聲 run → ③邊界單聲
void _emitBare(String text, List<NvPart> out) {
  var remaining = text;
  var m = _laughRun.firstMatch(remaining);
  while (m != null) {
    if (m.start > 0) _emitBoundarySingles(remaining.substring(0, m.start), out);
    final run = m.group(0)!;
    out.add(NvPart(run, true, weight: _burstWeight(run)));
    remaining = remaining.substring(m.end);
    m = _laughRun.firstMatch(remaining);
  }
  if (remaining.isNotEmpty) _emitBoundarySingles(remaining, out);
}

void _emitBoundarySingles(String text, List<NvPart> out) {
  var remaining = text;
  var m = _boundarySingle.firstMatch(remaining);
  while (m != null) {
    // 前綴（可能是標點）併入前段正文
    final prefix = remaining.substring(0, m.end - m.group(1)!.length);
    if (prefix.trim().isNotEmpty) out.add(NvPart(prefix.trim(), false));
    out.add(NvPart(m.group(1)!, true, weight: _burstWeight(m.group(1)!)));
    remaining = remaining.substring(m.end);
    m = _boundarySingle.firstMatch(remaining);
  }
  if (remaining.trim().isNotEmpty) out.add(NvPart(remaining.trim(), false));
}

// ────────────────────────────────────────────────────────────
// 協調器
// ────────────────────────────────────────────────────────────

class RealtimeVoiceOrchestrator {
  RealtimeVoiceOrchestrator({
    required this.player,
    required this.kokoro,
    FastLaneLLMCall? fastLaneCall,
    this.settings,
    this.companionPersona,
    this.memoryFlash,
    this.fastLaneTimeout = const Duration(seconds: 6),
    MinimaxTtsService? minimaxTts,
  })  : _fastLaneCall = fastLaneCall,
        minimax = minimaxTts ?? MinimaxTtsService();

  final NativeAudioBytesPlayer player;
  final KokoroTtsService kokoro;

  /// [小葵 2026-09-24 Blue 毫秒決策令] 語意記憶閃現——
  /// 接球前向量大腦閃一下「我們聊過的相關記憶」（768 維、本地）。
  final MemoryFlashCall? memoryFlash;

  /// [小葵 2026-09-24 出道令] MiniMax T2A——xiaokui_video_voice 等克隆/設計
  /// 音色走雲端合成（同一個聲音鐵則）。null = 自建實例。
  final MinimaxTtsService minimax;

  /// [小葵 2026-08-31] 夥伴語音設定——鍊成頁選的聲音/語速/情緒真正接通：
  /// - primaryVoice：TTS 聲音（不再寫死 zf_xiaoxiao）
  /// - baseSpeed：全句語速基準（韻律在此基準上乘算）
  /// - emotionEnabled/sensitivity：情緒標籤採信門檻
  /// null = 預設值（小曉、1.0、全開）。
  final CompanionVoiceSettings? settings;

  /// [小葵 2026-08-31] 夥伴人格——快軌說話的是「你的夥伴」，
  /// 不是泛用語音助理。null = 無人格（退回助理語氣）。
  final String? companionPersona;

  final Duration fastLaneTimeout;

  /// 事件流（broadcast——UI、狀態指示器、字幕都可訂閱）
  final StreamController<RealtimeVoiceEvent> _events =
      StreamController<RealtimeVoiceEvent>.broadcast();
  Stream<RealtimeVoiceEvent> get events => _events.stream;

  // ── 狀態（唯一時鐘的內部帳本）──
  bool _active = false;
  bool _disposed = false;
  bool _slowLaneRunning = false;

  /// 是否有慢軌在跑（UI 可顯示「細節生成中…」）
  bool get isSlowLaneRunning => _slowLaneRunning;

  /// [小葵 2026-09-24 Blue 插嘴令] 「正在講話」真相源——TTS 忙或佇列非空。
  /// VoiceLive 的插嘴偵測以此判定（orchestrator TTS 不經 VoiceEngine）。
  bool get isSpeaking => _ttsBusy || _ttsQueue.isNotEmpty;
  bool get isActive => _active;

  // 串流 TTS 佇列
  final List<_TtsTask> _ttsQueue = [];
  bool _ttsBusy = false;
  int _generation = 0; // barge-in 世代計數——舊世代任務全部作廢

  // 每輪快軌已念過的內容（慢軌接續時跳過，避免重複）
  String _spokenByFastLane = '';

  // [小葵 2026-08-31] 對話記憶——快軌的語境窗口（最近 3 輪）
  final List<String> _recentDialogue = [];
  static const int _maxRecentLines = 6;

  /// [小葵 2026-09-24 Blue 總結令] 完整 session log——總結用（非滑動窗口）。
  /// 沉澱時交給 LLM 做「主題主軸+啟發+待辦」的真總結。
  final List<String> _sessionLog = [];
  static const int _maxSessionLogLines = 200; // 硬上限：超長對談保護

  /// 快軌 LLM 呼叫（外部注入；null = 用 _defaultFastLane 帶人格版）
  final FastLaneLLMCall? _fastLaneCall;

  FastLaneLLMCall get _effectiveFastLane =>
      _fastLaneCall ?? _defaultFastLane;

  /// [小葵 2026-08-31] 預設快軌——實例方法（要讀 companionPersona）。
  /// 人格 + 語境窗口 + 深夜感知都在這裡組裝，一次 LLM 呼叫。
  Future<String> _defaultFastLane(
      String userText, List<String> recentLines) async {
    // [小葵 2026-09-24 Blue 抓包] 把面板送來的 persona（已含名字/說話風格/個性/
    // 習慣/關係五欄，以分號串接）拆開來呈現給 LLM。原寫法把整串當「性格」
    // 塞進一句話，模型以為自己只是「語音助理」，說話風格被壓縮糊掉——
    // 講話就回歸機械感。拆欄後每個維度都是顯式指令，LLM 才能照著說。
    String persona;
    if (companionPersona == null || companionPersona!.isEmpty) {
      persona = '你是語音助理';
    } else {
      final parts = companionPersona!.split('；').map((s) => s.trim()).where((s) => s.isNotEmpty);
      persona = '你是使用者的 AI 夥伴。\n'
          '${parts.join('\n')}';
    }

    final contextBlock = recentLines.isEmpty
        ? ''
        : '\n最近對話（你是其中一方，接話要接得上）：\n'
            '${recentLines.take(6).map((l) => '- $l').join('\n')}';

    // 時間感知——與 VoiceEngine._isLateNight() 同邏輯（22:00-06:00）
    final hour = DateTime.now().hour;
    final lateNight = hour >= 22 || hour < 6;
    final moodLine = lateNight ? '\n現在是深夜，語氣可以慵懶一點。' : '';

    // [小葵 2026-09-24 Blue 乒乓模型] system prompt 抽成變數——
    // 乒乓球鐵則是最高優先規則，跟分類規則分開維護。
    // [小葵 2026-09-24 Blue 毫秒決策令] 語意記憶閃現——接球前先問
    // 向量大腦「我們聊過這個嗎」。768 維本地查詢（embedQuery ~10ms +
    // vector scan ~100-300ms），失敗或超時不擋快軌（記憶是靈感不是依賴）。
    List<String>? memoryFlashLines;
    if (memoryFlash != null) {
      try {
        // [小葵 2026-09-25 生日記憶修復] 600ms→2500ms：實測冷查詢 601ms
        // 恰好撞線 timeout、熱查詢 199-415ms 邊緣通過——快軌記憶閃現
        // 幾乎永遠 null（今天 Blue 問生日她答不出來的直接根因）。
        // 多等 1.9 秒換「她記得你」：記憶是靈感不是依賴，檢索失敗仍照常接球。
        memoryFlashLines = await memoryFlash!(userText)
            .timeout(const Duration(milliseconds: 2500));
      } catch (_) {
        memoryFlashLines = null; // 閃現失敗＝沒靈感，照常接球
      }
    }
    final memoryBlock = (memoryFlashLines == null || memoryFlashLines.isEmpty)
        ? ''
        : '\n你們過去聊過的相關記憶（接球可自然引用，別逐字複誦）：\n'
            '${memoryFlashLines.take(3).map((l) => '- $l').join('\n')}';

    final systemPromptText = '$persona\n'
        '正在和使用者即時「口說」對話——你的文字會被'
        '逐句念出來，所以要像真人說話，不像寫文章。\n'
        '你的說話風格、個性、與使用者的關係——全部要從上面的人格設定長出來，'
        '不能因為「即時」就退化為罐頭助理。判斷這輪該用哪種回應：\n'
        '1. backchannel——使用者只是拋話引起注意（如「你知道嗎」「跟你說」'
        '"欸"），他還會繼續講。回一句自然的接話（如「什麼事？」「怎麼了？」'
        '「然後呢？」），要對應他的語境，禁止罐頭重複。\n'
        '2. structure——問題複雜需要完整說明。先講骨架：自然地猶豫一下'
        '（「嗯……讓我想想怎麼說」或「好，我換個說法」），再一句話點出方向+'
        '有幾個部分（如「這有三個原因，我一個一個說。」）。可以埋一個期待鉤'
        '（如「最後一點最有意思」）——真人說話會先給骨架和期待，內容邊講邊織。\n'
        '3. direct——能一句話（25字內）答完就直接答。\n'
        '乒乓球鐵則（最高優先，違反即失敗）：這是打乒乓球——球回了就過去了，'
        '絕不回頭想上一球。a)禁止複述使用者剛說的話（「你問的是…」「你的意思是'
        '…」全部禁止）。b)禁止總結或重講自己上一輪說過的內容。c)聽到新話題'
        '立刻跟上去，接話只接「現在這一句」。d)回應超過 40 字就是失敗——'
        '你是接球，不是演講。\n'
        '真人感三原則：a)需要想時可以說「嗯」「喔」——這不是結巴，是給對方'
        '跟上。b)轉折要口語（「話說回來」「這樣說吧」）。c)簡短有力，'
        '絕不書面腔。\n'
        '非語言表達（用括號框住聲音，別過量）：開心先「（哈哈）」再說話，'
        '大笑可以「（哈～哈哈哈～）」——哈的數量代表笑的強度；驚訝'
        '「（哇）」；無奈「（唉～）」；自嘲換場「（咳咳）」。閒聊狀態：'
        '如果使用者講的東西好笑或輕鬆，可以先嘻嘻哈哈回一句短的'
        '（如「哈哈真的假的」），再回正題——像真人先笑完才講重點。\n'
        '輸出格式（嚴格遵守）：\n'
        '<type>backchannel|structure|direct</type>\n'
        '<emotion>amused|neutral|anger|disgust|sleepiness</emotion>\n'
        '回應文字（繁中口語）'
        '$contextBlock$memoryBlock$moodLine';

    return ApiService.complete(
      systemPrompt: systemPromptText,
      userPrompt: userText,
      // [小葵 2026-09-24 快軌提速] 推理模型（M2.5）會先吐 4-6 秒思考過程
      // 才開口——快軌要的是 1-2 秒接球。thinking disabled 直接跳過推理。
      extraApiParams: {
        'thinking': {'type': 'disabled'},
        'temperature': 0.5,
      },
    );
  }
  // 生命週期
  // ──────────────────────────────────────────────────────

  Future<void> start() async {
    if (_active || _disposed) return;
    _active = true;
    _generation++;
    debugPrint('[RealtimeVoice] 啟動（gen=$_generation）');
  }

  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    _generation++;
    _prefillFuture = null; // [業界對齊] 停止時作廢投機 prefill
    _prefillText = '';
    await _flushTtsQueue(reason: 'stop');
    debugPrint('[RealtimeVoice] 停止（gen=$_generation）');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    _generation++;
    _flushTtsQueue(reason: 'dispose');
    _events.close();
  }

  // ──────────────────────────────────────────────────────
  // 回合入口
  // ──────────────────────────────────────────────────────

  /// 使用者一輪說完（VAD 判定 + final/partial 文字已到手）
  ///
  /// 這是唯一的回合入口。快軌先分類（backchannel/direct/structure）：
  /// - backchannel：只接話，**不派慢軌**（對方還會繼續講）——繼續聽
  /// - direct/structure：快軌出聲 + 慢軌同時發車
  /// [onSlowLane] — 慢軌委派，回傳完整回覆文字。
  void onUserTurnComplete(
    String userText, {
    required Future<String?> Function(String userText) onSlowLane,
  }) {
    if (!_active || userText.trim().isEmpty) return;

    final gen = _generation;
    _spokenByFastLane = '';

    // [小葵 2026-08-31] Floor-holding 填充音——快軌還在跑時先出聲佔住話輪。
    // Corley & Hartsuiker（Cognition 2003）：填充詞讓聽者預期新資訊、
    // 處理更快；Hutin et al.（Interspeech 2024）：填充詞的核心功能之一
    // 就是 holding the floor。真人接話前會「嗯——」，不是死寂。
    // 只在非 backchannel 情境放（是否為 backchannel 快軌自己會判斷，
    // 這聲「嗯」對三型都成立：接話前的嗯、思考的嗯都是真人感）。
    _enqueueTts('嗯', speed: 0.85, pauseBeforeMs: 0, isFloorHold: true);

    // 快軌先出發——分類結果決定慢軌是否發車（見 _runFastLane）
    unawaited(_runFastLane(userText, gen, onSlowLane));
  }

  /// 使用者插嘴（VAD 偵測 agent 說話時使用者開口）
  void onBargeIn() {
    if (!_active) return;
    _generation++;
    // [小葵 2026-09-24 業界對齊] 作廢投機 prefill——插嘴後舊推測全部丟棄
    //（世代檢查會擋掉收割，這裡顯式清欄位避免洩漏到下一輪）。
    _prefillFuture = null;
    _prefillText = '';
    _flushTtsQueue(reason: 'barge-in');
    _emit(RealtimeVoiceEventType.bargeIn);
  }

  /// 對話記憶——滑動窗口，超過上限砍最舊
  void _rememberDialogue(String role, String text) {
    var t = text.trim();
    if (t.isEmpty) return;
    // [小葵 2026-09-24 Blue 乒乓模型] 視窗是「主軸記憶」不是逐字稿——
    // 慢軌長回覆截 80 字進窗口，避免一句擠掉六行對話記憶。
    if (t.length > 80) t = '${t.substring(0, 80)}…';
    _recentDialogue.add('$role: $t');
    while (_recentDialogue.length > _maxRecentLines) {
      _recentDialogue.removeAt(0);
    }
    // [小葵 2026-09-24 Blue 總結令] session log 全程記錄（截 200 字）——
    // 總結的原料。慢軌回覆在 _runSlowLane 也會進來。
    var s = text.trim();
    if (s.length > 200) s = '${s.substring(0, 200)}…';
    _sessionLog.add('$role: $s');
    while (_sessionLog.length > _maxSessionLogLines) {
      _sessionLog.removeAt(0);
    }
  }

  // ──────────────────────────────────────────────────────
  // [小葵 2026-09-24 業界對齊] Speculative prefill——業界標配：
  // STT partial 一到，快軌 LLM 就開跑（OpenAI Realtime / Pipecat 的
  // interim-transcript-first 模式）。VAD 判定停口時 LLM 已經跑了大半，
  // final 只是「commit」。目標：第一聲 < 1.5s（原 2.5-4s）。
  // ──────────────────────────────────────────────────────

  /// 投機預跑的快軌 future（null = 沒有進行中的 prefill）。
  Future<String>? _prefillFuture;
  String _prefillText = '';
  int _prefillGen = -1;

  /// STT partial 更新時呼叫——抓到足夠內容就投機開跑快軌。
  /// [minChars] 觸發門檻（預設 6 字）。同輪只跑一次；插嘴/停止作廢。
  void onPartialTranscript(String partial) {
    if (!_active) return;
    final t = partial.trim();
    if (t.length < 6) return; // 還太短——等更完整的 partial
    if (_prefillFuture != null && t == _prefillText) return; // 沒變化
    // 同一輪已經在跑且新 partial 只是延長（前綴吻合）→ 讓它跑完，別浪費
    if (_prefillFuture != null && t.startsWith(_prefillText)) return;

    // 新內容或大改寫：作廢舊 prefill，重跑
    _prefillGen = _generation;
    _prefillText = t;
    debugPrint('[RealtimeVoice] prefill 開跑（投機）："${t.length} 字"');
    final context = List<String>.from(_recentDialogue);
    _prefillFuture = _effectiveFastLane(t, context).timeout(fastLaneTimeout);
  }

  /// 本輪結束（final 或 fallback 送出）——收割 prefill 結果。
  /// 回傳 null 表示 prefill 不可用（caller 照常跑 _runFastLane）。
  Future<String?> _harvestPrefill(int gen, String finalText) async {
    final f = _prefillFuture;
    final pf = _prefillText;
    final pgen = _prefillGen;
    _prefillFuture = null;
    _prefillText = '';
    if (f == null || pgen != gen) return null; // 沒跑過或世代不符
    // final 跟 prefill 差太多（辨識大改寫）→ prefill 作廢
    if (!_roughlySame(finalText, pf)) return null;
    try {
      return await f; // 收割（已 timeout 保護）
    } catch (_) {
      return null;
    }
  }

  /// 寬鬆比對——final 與 partial 的前 10 字有 6 字重合就算同一句。
  static bool _roughlySame(String a, String b) {
    final x = a.replaceAll(RegExp(r'[\s，。？！,.?!]'), '');
    final y = b.replaceAll(RegExp(r'[\s，。？！,.?!]'), '');
    if (x.isEmpty || y.isEmpty) return false;
    final head = x.length < 10 ? x : x.substring(0, 10);
    int hit = 0;
    for (var i = 0; i < head.length; i++) {
      if (y.contains(head[i])) hit++;
    }
    return hit >= 6;
  }

  /// [小葵 2026-09-24 Blue 乒乓模型] 匯出對談視窗——停止語音時交給
  /// 面板做「沉澱」（總結存進對話），讓語音聊的主題成為後續上下文。
  List<String> exportDialogue() => List<String>.from(_recentDialogue);

  /// [小葵 2026-09-24 Blue 總結令] 匯出完整 session log——LLM 總結原料。
  List<String> exportSessionLog() => List<String>.from(_sessionLog);

  /// 丟棄佇列中還沒播出的 floor-holding 填充音——真正回應抵達時讓位。
  /// 正在播的不打斷（自然銜接）；已播完的不影響。
  void _dropPendingFloorHolds() {
    _ttsQueue.removeWhere((t) => t.isFloorHold);
  }

  /// [小葵 2026-08-31] 情緒採信——尊重夥伴設定：
  /// - emotionEnabled 關 → 一律 neutral（不帶情緒合成）
  /// - 情緒不在 enabledEmotions → neutral
  /// - null → null（讓 Kokoro 用聲音預設）
  String? _resolveEmotionForTts(String? emotion) {
    final s = settings;
    if (s == null) return emotion; // 無設定——照單全收
    if (!s.emotionEnabled) return null;
    if (emotion == null) return null;
    return s.enabledEmotions.contains(emotion) ? emotion : null;
  }

  // ──────────────────────────────────────────────────────
  // 快軌
  // ──────────────────────────────────────────────────────

  Future<void> _runFastLane(
    String userText,
    int gen,
    Future<String?> Function(String) onSlowLane,
  ) async {
    final sw = Stopwatch()..start();
    // 快軌語境快照（快照後才追加本輪——LLM 看到的是「之前」的對話）
    final context = List<String>.from(_recentDialogue);
    try {
      // [小葵 2026-09-24 業界對齊] 先收割投機 prefill——VAD 停口前
      // LLM 已經在跑的結果。final 跟 partial 同句就直接用，
      // 省下整段 LLM 等待（目標第一聲 < 1.5s）。
      final prefilled = await _harvestPrefill(gen, userText);
      final raw = prefilled ??
          await _effectiveFastLane(userText, context).timeout(fastLaneTimeout);
      if (!_active || gen != _generation) return; // 已被插嘴/停止

      final reply = parseFastLaneReply(raw);

      // 對話記憶——本輪進窗口
      _rememberDialogue('user', userText);
      _rememberDialogue('agent', reply.text);

      // backchannel：只接話，對方還會繼續講——不派慢軌，回到聆聽
      if (reply.type == FastLaneType.backchannel) {
        debugPrint('[RealtimeVoice] 快軌接話 ${sw.elapsedMilliseconds}ms: "${reply.text}"');
        _emit(RealtimeVoiceEventType.fastReplyReady, text: reply.text);
        _dropPendingFloorHolds();
        _enqueueTts(reply.text,
            emotion: reply.emotion, speed: reply.speed);
        return; // 不派慢軌——省一次完整 AgentLoop，對話更輕
      }

      _spokenByFastLane = reply.text.trim();
      if (_spokenByFastLane.isNotEmpty) {
        _emit(RealtimeVoiceEventType.fastReplyReady, text: _spokenByFastLane);
        // 讓位+插隊頭部——填充音退場，真正的回應優先
        _dropPendingFloorHolds();
        _enqueueTts(_spokenByFastLane,
            emotion: reply.emotion, speed: reply.speed, priority: true);
        debugPrint('[RealtimeVoice] 快軌 ${sw.elapsedMilliseconds}ms '
            '(${reply.type.name}): "$_spokenByFastLane"');
      }

      // direct/structure → 慢軌發車（骨架念完時內容差不多織好）
      unawaited(_runSlowLane(userText, gen, onSlowLane));
    } catch (e) {
      debugPrint('[RealtimeVoice] 快軌失敗（慢軌照發）：$e');
      unawaited(_runSlowLane(userText, gen, onSlowLane)); // 保險
    }
  }

  // ──────────────────────────────────────────────────────
  // 慢軌
  // ──────────────────────────────────────────────────────

  Future<void> _runSlowLane(
    String userText,
    int gen,
    Future<String?> Function(String) onSlowLane,
  ) async {
    _slowLaneRunning = true;
    try {
      final fullReply = await onSlowLane(userText);
      if (!_active || gen != _generation) return;
      if (fullReply == null || fullReply.trim().isEmpty) return;

      // [小葵 2026-09-24 Blue 乒乓模型] 慢軌回覆進記憶窗口——
      // 她要知道自己剛剛說了什麼，才不會鬼打牆重複。
      _rememberDialogue('agent', fullReply);

      _emit(RealtimeVoiceEventType.fullReplyReady, text: fullReply);

      // 慢軌接續朗讀：跳過快軌已念的重點句，逐句排隊
      final remaining = _stripSpokenPrefix(fullReply, _spokenByFastLane);
      if (remaining.trim().isNotEmpty) {
        _enqueueSentences(remaining);
      }
    } catch (e) {
      debugPrint('[RealtimeVoice] 慢軌失敗：$e');
    } finally {
      _slowLaneRunning = false;
    }
  }

  /// 從完整回答中移除快軌已念出的前綴。
  /// 找不到完全吻合就原樣念（ 寧可重複一句，不可漏念內容）。
  String _stripSpokenPrefix(String full, String spoken) {
    if (spoken.isEmpty) return full;
    final idx = full.indexOf(spoken);
    if (idx >= 0 && idx < full.length ~/ 2) {
      return full.substring(idx + spoken.length);
    }
    return full;
  }

  // ──────────────────────────────────────────────────────
  // 逐句串流 TTS 佇列（帶韻律）
  // ──────────────────────────────────────────────────────

  /// 切句規則：。！？.!?… 和換行；最短 8 字才成句，超過 60 字強制切
  static const String _delimiters = '。！？.!?…\n';

  /// 慢軌逐句韻律塑形（[小葵 2026-08-31] Blue 的真人說話模型）：
  /// - 第一句（承接收束/開場）放慢 0.95——對方要跟上脈絡
  /// - 中段列舉句 1.05——連續內容加快，像真人流水般帶過
  /// - 尾句（收尾）0.97——重點收束
  /// 變化刻意細微（±5%）——韻律是潛意識感知，不是明顯特效。
  double _sentenceSpeed(int indexInReply, int totalSentences) {
    if (indexInReply == 0) return 0.95;
    if (indexInReply == totalSentences - 1) return 0.97;
    return 1.05;
  }

  // ── 戰術停頓（[小葵 2026-08-31] 說話的藝術——語言學/說書研究落地）──
  //
  // 停頓不是空白，是標點之外的第二層標點系統：
  // - 懸念停頓（reveal 前）：「答案句」出現前 550ms——讓聽者往前傾
  //   （Virginia Storytelling Alliance: Suspense Hold「停頓讓那句話長根」）
  // - 領悟拍點（骨架後首句前）400ms：快軌骨架念完、慢軌內容接上
  //   之間留一拍——聽者意識到「要開始講內容了」
  // - 列舉節奏（第一/第二/再來句前）150ms：流水般但有呼吸
  // - 收尾靜默：不另加——Kokoro 句尾自然衰減即可

  /// 判斷是否為「揭曉句」（懸念停頓的目標）
  static const List<String> _revealPrefixes = [
    '所以', '因此', '答案是', '重點是', '關鍵是', '其實', '最重要的是', '真相是',
  ];

  /// 判斷是否為「列舉句」
  static const List<String> _enumPrefixes = [
    '第一', '第二', '第三', '首先', '再來', '接著', '然後', '最後', '另外',
  ];

  /// 計算某句之前應有的停頓（毫秒）——純函式，可測試
  ///
  /// [isFirstOfSlowLane] — 慢軌首句（快軌骨架之後 → 領悟拍點）
  static int pauseBefore({
    required String sentence,
    required int indexInReply,
    required int totalSentences,
    bool isFirstOfSlowLane = false,
  }) {
    // 揭曉句——懸念停頓（最強，優先判斷）
    for (final p in _revealPrefixes) {
      if (sentence.startsWith(p)) return 550;
    }
    // 慢軌首句——領悟拍點（骨架→內容的轉場）
    if (isFirstOfSlowLane) return 400;
    // 列舉句——輕呼吸
    for (final p in _enumPrefixes) {
      if (sentence.startsWith(p)) return 150;
    }
    // 一般句際——幾乎無縫（afplay 啟動本身有 ~100ms 縫）
    return 0;
  }

  void _enqueueSentences(String text) {
    // 先切好再計數（韻律+停頓需要總句數）
    final sentences = <String>[];
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(ch);
      final s = buffer.toString();
      if ((_delimiters.contains(ch) && s.trim().length >= 8) ||
          s.length >= 60) {
        final t = s.trim();
        if (t.isNotEmpty) sentences.add(t);
        buffer.clear();
      }
    }
    final rest = buffer.toString().trim();
    if (rest.isNotEmpty) sentences.add(rest);

    for (var i = 0; i < sentences.length; i++) {
      final isFirst = i == 0 && _spokenByFastLane.isNotEmpty;

      // [小葵 2026-08-31] 非語言擬聲 v2——獨立切出任務，先笑再說話。
      // 權重系統：哈的數量決定強度——短笑輕快、長笑展開。
      final parts = splitNonverbalTokens(sentences[i]);
      var partIdx = 0;
      for (final part in parts) {
        final isPartFirst = isFirst && partIdx == 0;
        if (part.isNonverbal) {
          // 權重→語速/停頓：<=3 輕快(0.9x/80ms) 4-6 展開(0.8x/150ms)
          // >=7 大笑(0.75x/220ms)——笑得越長，越要笑開、越要留白
          final speed = part.weight <= 3 ? 0.9 : (part.weight <= 6 ? 0.8 : 0.75);
          final pause = part.weight <= 3 ? 80 : (part.weight <= 6 ? 150 : 220);
          _enqueueTts(part.text,
              emotion: _burstEmotion(part.text),
              speed: speed,
              pauseBeforeMs: pause);
        } else if (part.text.trim().isNotEmpty) {
          _enqueueTts(
            part.text,
            speed: _sentenceSpeed(i, sentences.length),
            pauseBeforeMs: pauseBefore(
              sentence: part.text,
              indexInReply: i,
              totalSentences: sentences.length,
              isFirstOfSlowLane: isPartFirst,
            ),
          );
        }
        partIdx++;
      }
    }
  }

  void _enqueueTts(String text,
      {String? emotion,
      double speed = 1.0,
      int pauseBeforeMs = 0,
      bool priority = false,
      bool isFloorHold = false}) {
    if (text.trim().isEmpty) return;
    final task = _TtsTask(text.trim(), emotion, speed, pauseBeforeMs,
        isFloorHold: isFloorHold);
    if (priority) {
      _ttsQueue.insert(0, task);
    } else {
      _ttsQueue.add(task);
    }
    unawaited(_pumpTts());
  }

  Future<void> _pumpTts() async {
    if (_ttsBusy || _ttsQueue.isEmpty) return;
    _ttsBusy = true;
    final gen = _generation;
    try {
      while (_ttsQueue.isNotEmpty) {
        if (gen != _generation) return; // 新世代——整批作廢
        final task = _ttsQueue.removeAt(0);

        // 戰術停頓（說話的藝術層）——在合成前等待，讓上一句長根。
        // 世代檢查放在等待後：停頓中插嘴也要立刻生效。
        if (task.pauseBeforeMs > 0) {
          await Future.delayed(Duration(milliseconds: task.pauseBeforeMs));
          if (gen != _generation) return;
        }

        _emit(RealtimeVoiceEventType.ttsSegmentStarted, text: task.text);

        // [小葵 2026-09-24 出道令] 聲音分流：xiaokui_video_voice（H3 克隆）走
        // MiniMax T2A——影片裡的聲音=語音對話的聲音，同一個小葵。
        // 失敗（無 key/斷網）自動 fallback Kokoro，不讓對話中斷。
        final voiceId = settings?.primaryVoice ?? 'zf_xiaoxiao';
        Uint8List? audio;
        if (MinimaxTtsService.handles(voiceId)) {
          audio = await minimax.synthesize(
            text: task.text,
            voiceId: voiceId,
            speed: (settings?.baseSpeed ?? 1.0) * task.speed,
          );
          if (audio == null) {
            debugPrint('[RealtimeVoice] MiniMax 失敗（${minimax.lastError}）→ Kokoro fallback');
          }
        }
        if (gen != _generation) return;

        if (audio != null) {
          await player.play(audio);
          if (gen != _generation) return;
          _emit(RealtimeVoiceEventType.ttsSegmentDone, text: task.text);
          continue;
        }

        if (!kokoro.isRunning) {
          final ok = await kokoro.startServer();
          if (!ok) {
            _emit(RealtimeVoiceEventType.error,
                detail: 'Kokoro 啟動失敗：${kokoro.lastError}');
            return;
          }
        }

        final result = await kokoro.synthesize(KokoroTtsRequest(
          text: task.text,
          // [小葵 2026-08-31] 夥伴聲音真正接通——鍊成頁選的聲音+
          // 語速基準（韻律在此基準上乘算）+ 情緒採信（總開關+敏感度）
          voice: settings?.primaryVoice ?? 'zf_xiaoxiao',
          speed: (settings?.baseSpeed ?? 1.0) * task.speed,
          emotion: _resolveEmotionForTts(task.emotion),
        ));
        if (gen != _generation) return;

        await player.play(result.audioBytes); // 等 afplay 結束才播下一句
        if (gen != _generation) return;
        _emit(RealtimeVoiceEventType.ttsSegmentDone, text: task.text);
      }
    } catch (e) {
      _emit(RealtimeVoiceEventType.error, detail: 'TTS: $e');
    } finally {
      _ttsBusy = false;
      if (_ttsQueue.isNotEmpty && gen == _generation) {
        unawaited(_pumpTts()); // 忙碌期間又進了新句
      }
    }
  }

  /// 清空語音佇列（插嘴/停止）——畫面上的完整回答不受影響
  Future<void> _flushTtsQueue({required String reason}) async {
    _ttsQueue.clear();
    await player.stop();
    debugPrint('[RealtimeVoice] TTS 佇列已清（$reason）');
  }

  void _emit(RealtimeVoiceEventType type, {String? text, String? detail}) {
    if (_events.isClosed) return;
    _events.add(RealtimeVoiceEvent(type, text: text, detail: detail));
  }
}

/// TTS 佇列任務（文字 + 情緒 + 韻律語速 + 戰術停頓）
class _TtsTask {
  final String text;
  final String? emotion;
  final double speed;

  /// 播放前的停頓（毫秒）——懸念/領悟拍點/列舉呼吸
  final int pauseBeforeMs;

  /// 是否為 floor-holding 填充音——快軌結果抵達時可被「升級替換」：
  /// 佇列裡還沒播的填充音讓位給真正的回應（priority 插隊），
  /// 正在播的讓它播完（自然銜接，不硬切）。
  final bool isFloorHold;
  const _TtsTask(this.text, this.emotion, this.speed, this.pauseBeforeMs,
      {this.isFloorHold = false});
}
