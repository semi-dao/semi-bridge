// Voice Live Controller — 雙向溝通直接聊天互動的中央控制器
//
// [教練 Agent 2026-08-03] Phase 1 MVP
//
// 設計理念：
// 按一次麥克風 → 進入「持續對話」模式
// 1. STT 持續監聽（取得文字）
// 2. 音量 VAD 偵測使用者開/停口
// 3. 說完話 → 自動送 LLM
// 4. LLM 回應 → TTS streaming 播放
// 5. Agent 講話時使用者可以插嘴（自動停止 TTS + 處理新訊息）
// 6. 再按一次麥克風 → 完全停止
//
// 連接的元件：
// - VoiceSpeechHandler（STT + 音量）
// - VoiceEngine（狀態機 + TTS + AgentLoop trigger）
// - VoiceInterruptionDetector（插嘴偵測）
// - ChatController（送出 LLM 訊息 + 接收 LLM streaming）
// - ChatTtsHandler（TTS 播放）

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'voice_engine.dart';
import 'voice_interruption_detector.dart';
import 'voice_state_machine.dart';
import '../../controllers/chat_controller.dart';
import '../../screens/chat/handlers/voice_speech_handler.dart';

/// 雙向溝通模式 — 中央控制器
class VoiceLiveController {
  final VoiceSpeechHandler _speechHandler;
  final VoiceEngine _voiceEngine;
  final ChatController _chatController;

  // 訂閱
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<String>? _finalTextSub;

  // 簡單 VAD（基於音量 threshold + 持續時間）
  bool _isUserSpeaking = false;
  double _vadSilenceThreshold = 0.05;  // 音量高於此視為說話

  /// [小葵 2026-08-30] VAD 沉默判定 1.5s → 800ms（延遲優化）。
  /// 說完話到送 LLM 的等待砍半；講話中間停頓被誤判斷句的風險略增，
  /// 實測 zh_TW dictation 模式下 800ms 是安全值。建構子可覆寫。
  Duration _silenceDuration = const Duration(milliseconds: 800);
  DateTime? _lastVoiceTime;  // 最後一次偵測到聲音的時間
  Timer? _silenceTimer;

  /// [小葵 2026-30] 等 STT final result 的 timeout 計時器。
  /// VAD 判定停口後：優先等 final result（最準）；
  /// 超時（1200ms）就用 lastPartialText fallback 送出，不丟句。
  Timer? _finalWaitTimer;
  bool _waitingForFinalResult = false;

  /// [小葵 2026-08-30] 送出後抑制窗——防止遲到的 final result
  /// 跟 fallback 送出重複（同一句送兩次 LLM）。
  DateTime _lastDispatchAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _dispatchSuppression = const Duration(milliseconds: 3000);

  // 插嘴偵測器
  VoiceInterruptionDetector? _interruptionDetector;

  // 當前是否在持續對話中
  bool _isLiveMode = false;

  // 當前 agent 是否在講話（用來啟動插嘴偵測）
  bool _isAgentSpeaking = false;

  // 當前 LLM 串流回應（用於插嘴時中斷）
  String _currentAgentReply = '';

  // 狀態變化通知（給 UI 訂閱）
  final ValueNotifier<VoiceLiveState> state =
      ValueNotifier<VoiceLiveState>(VoiceLiveState.idle);

  VoiceLiveController({
    required VoiceSpeechHandler speechHandler,
    required VoiceEngine voiceEngine,
    required ChatController chatController,
    this.onExternalTurn,
    this.onExternalBargeIn,
    this.isExternalAgentSpeaking,
  })  : _speechHandler = speechHandler,
        _voiceEngine = voiceEngine,
        _chatController = chatController {
    // 訂閱語音引擎狀態
    _voiceEngine.state.addListener(_onEngineStateChanged);
  }

  /// [小葵 2026-08-30] 外部回合 hook——RealtimeVoiceOrchestrator 注入。
  /// 非 null 時，VAD 判定的整輪文字改交給 orchestrator（快答慢想雙軌），
  /// 不再走 VoiceEngine.onSpeechRecognized（單軌整段朗讀）。
  final void Function(String turnText)? onExternalTurn;

  /// [小葵 2026-08-30] 外部插嘴 hook——orchestrator 需要 flush 自己的 TTS 佇列
  final void Function()? onExternalBargeIn;

  /// [小葵 2026-09-24 Blue 插嘴令] 外部「agent 正在講話」判定——
  /// orchestrator 的 TTS 走自己的 player 不經過 VoiceEngine，
  /// _isAgentSpeaking（VoiceEngine 狀態驅動）在 orchestrator 模式永遠 false
  /// → 插嘴偵測從未生效（Blue 實測：她像問答機把話全部吐完才理人）。
  /// 此 hook 非 null 時，插嘴判定以它為真相源。
  final bool Function()? isExternalAgentSpeaking;

  /// 開始雙向溝通模式
  Future<void> start() async {
    if (_isLiveMode) return;
    _isLiveMode = true;
    state.value = VoiceLiveState.connecting;

    try {
      // 1. 啟動 voice engine 對話
      await _voiceEngine.startConversation();

      // 2. 啟動 STT
      await _speechHandler.start();

      // 3. 訂閱音量（給 UI 顯示波形 + 給 VAD 判斷）
      _volumeSub = _speechHandler.amplitudeStream.listen(_onVolumeChanged);

      // 4. [小葵 2026-08-30] 訂閱 STT final result——改訂 finalTextStream。
      // 舊版訂 partialTextStream 等「非空 final」永遠等不到：
      // partialTextStream 在 final 時推空字串（清 overlay 用），
      // 實際行為變成「下一句的第一個 partial 被當成上一句的 final 送出」。
      _finalTextSub = _speechHandler.finalTextStream.listen((text) {
        if (_waitingForFinalResult && text.isNotEmpty) {
          debugPrint('[VoiceLive] 收到 STT final: $text');
          _finalWaitTimer?.cancel();
          _finalWaitTimer = null;
          _waitingForFinalResult = false;
          _onSpeechFinalResult(text);
        }
      });

      // 5. 設定插嘴偵測器
      _interruptionDetector = VoiceInterruptionDetector(
        onInterrupt: () => _onUserInterruption(),
      );

      state.value = VoiceLiveState.listening;
      debugPrint('[VoiceLive] 雙向溝通模式啟動');
    } catch (e) {
      debugPrint('[VoiceLive] 啟動失敗: $e');
      await stop();
      rethrow;
    }
  }

  /// 停止雙向溝通模式
  Future<void> stop() async {
    if (!_isLiveMode) return;
    _isLiveMode = false;

    // 取消所有訂閱
    await _volumeSub?.cancel();
    _volumeSub = null;
    await _finalTextSub?.cancel();
    _finalTextSub = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    // [小葵 2026-08-30] fallback 計時器也要清
    _finalWaitTimer?.cancel();
    _finalWaitTimer = null;
    _waitingForFinalResult = false;

    // 停止 STT
    await _speechHandler.stop();

    // 停止 voice engine
    await _voiceEngine.stopConversation();

    // 清掉插嘴偵測器
    _interruptionDetector?.dispose();
    _interruptionDetector = null;

    _isUserSpeaking = false;
    _isAgentSpeaking = false;
    _waitingForFinalResult = false;
    // [小葵 2026-09-24] dispose race 修——stop() 是 async，panel dispose 的
    // fire-and-forget 呼叫可能在 state.dispose() 之後才走到這行
    // （舊 log：ValueNotifier used after disposed）。用 try-catch 防禦
    // （ValueNotifier 沒有 disposed getter，Flutter 3.x 用 ChangeNotifier
    // 的 debug 斷言在 release 不炸但 debug 炸）。
    try {
      state.value = VoiceLiveState.idle;
    } catch (_) {
      // 已 disposed——跳過
    }
    debugPrint('[VoiceLive] 雙向溝通模式已停止');
  }

  /// 有效「agent 正在講話」判定——orchestrator 模式用外部真相源。
  /// [小葵 2026-09-24 Blue 插嘴令] 見 isExternalAgentSpeaking 文檔。
  bool get _effectiveAgentSpeaking =>
      (isExternalAgentSpeaking?.call() ?? false) || _isAgentSpeaking;

  /// 處理使用者插嘴
  void _onUserInterruption() {
    if (!_isLiveMode) return;
    if (!_effectiveAgentSpeaking) return;

    debugPrint('[VoiceLive] 偵測到使用者插嘴');

    // [小葵 2026-08-30] orchestrator 模式——flush 外部 TTS 佇列優先
    if (onExternalBargeIn != null) {
      onExternalBargeIn!();
    }

    // 1. 通知 voice engine 進入 listening（停止 TTS）
    _voiceEngine.onUserStartedSpeaking();

    // 2. UI 狀態切換
    state.value = VoiceLiveState.listening;
  }

  /// 處理音量變化（基於音量 VAD）
  void _onVolumeChanged(double volume) {
    if (!_isLiveMode) return;

    // 簡單 VAD：音量 > 閾值 → 視為說話
    if (volume > _vadSilenceThreshold) {
      _lastVoiceTime = DateTime.now();

      if (!_isUserSpeaking) {
        // 開始說話
        _isUserSpeaking = true;
        debugPrint('[VoiceLive] VAD 偵測到使用者開口');

        // 如果 agent 在講話 → 觸發插嘴
        // [小葵 2026-09-24 Blue 插嘴令] 用 _effectiveAgentSpeaking——
        // orchestrator 模式下 VoiceEngine 狀態不是真相源（orchestrator
        // 的 TTS 走自己 player）。不插嘴＝她把話全部吐完才理人（Blue 抓包）。
        if (_effectiveAgentSpeaking) {
          _interruptionDetector?.onInterrupt?.call();
        } else {
          _voiceEngine.onUserStartedSpeaking();
          state.value = VoiceLiveState.listening;
        }
      }

      // 取消沉默計時器
      _silenceTimer?.cancel();
      _silenceTimer = null;
    } else {
      // 沉默 — 啟動計時器
      if (_isUserSpeaking && _silenceTimer == null) {
        // [小葵 2026-08-31] 語意自適應 VAD——沉默時長由句尾完整度決定：
        // Campione & Veronis 多語言停頓研究：人類子句邊界停頓峰在 ~426ms。
        // 若句子看起來已完整（問號/句號/語氣詞尾）→ 300ms 快切（逼近
        // Stivers 2009 跨文化 200ms 通用值）；未完整 → 800ms 保護，
        // 不在使用者子句間呼吸時搶答。
        final silence = _adaptiveSilenceFor(_speechHandler.lastPartialText);
        _silenceTimer = Timer(silence, () {
          _onUserStoppedSpeaking();
        });
      }
    }

    // 如果 agent 在講話，把音量傳給插嘴偵測
    // VoiceInterruptionDetector 預期用 startMonitoring(stream)
    // 我們簡化：直接呼叫 onInterrupt 觸發停 TTS
    if (_effectiveAgentSpeaking && _isUserSpeaking) {
      // [教練 Agent 2026-08-03] 簡化：音量 VAD 觸發 + agent 在講話 = 插嘴
      _interruptionDetector?.onInterrupt?.call();
    }
  }

  // ── [小葵 2026-08-31] 語意自適應沉默時長 ──

  /// 句尾「完整語意」訊號——這些字詞結尾時，句子大概率講完了
  static const List<String> _turnFinalCues = [
    '嗎', '呢', '吧', '啊', '啦', '喔', '哦', '嘛', '呀', '？', '?',
    '。', '！', '!', '。',
  ];

  /// 根據目前 partial 的句尾判斷沉默時長
  ///
  /// 純函式（static）——可單測。預設 800ms（保護子句間呼吸），
  /// 句尾有完整語意訊號 → 300ms（快切，像真人接話）。
  static Duration adaptiveSilenceFor(String partialText) {
    final t = partialText.trim();
    if (t.length < 2) return const Duration(milliseconds: 800);
    // 找最後一個非標點字元，檢查句尾 2 字內有無完整訊號
    for (final cue in _turnFinalCues) {
      if (t.endsWith(cue)) return const Duration(milliseconds: 300);
    }
    // 無訊號——句子可能還沒完（子句中呼吸），保守等待
    return const Duration(milliseconds: 800);
  }

  Duration _adaptiveSilenceFor(String partialText) =>
      adaptiveSilenceFor(partialText);

  /// 處理使用者停口
  void _onUserStoppedSpeaking() {
    if (!_isUserSpeaking) return;
    _isUserSpeaking = false;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    debugPrint('[VoiceLive] VAD 偵測到使用者停口');

    _voiceEngine.onUserStoppedSpeaking();

    // 等待 STT 給出 final result
    _waitingForFinalResult = true;

    // [小葵 2026-08-30] fallback 計時器：等不到 final result
    // 就用 lastPartialText 送出，不丟句。
    // [小葵 2026-09-24 業界對齊] 1200→500ms：speculative prefill 上線後
    // partial 本來就在跑，final 只是 commit——等太久純浪費延遲。
    // （舊版註解自承「實際上我們還沒有文字」→ 就是不送。）
    _finalWaitTimer?.cancel();
    _finalWaitTimer = Timer(const Duration(milliseconds: 500), () {
      if (!_waitingForFinalResult) return;
      final fallback = _speechHandler.lastPartialText.trim();
      // [小葵 2026-09-24 Blue 抓包④] 裱除已送出前綴——fallback 文字
      // 只取本輪新增（dictation 累積的殘留不帶上）。
      final visible = _speechHandler.stripDispatchedPrefix(fallback);
      debugPrint('[VoiceLive] final 超時，fallback 用 partial："$visible"');
      _waitingForFinalResult = false;
      if (visible.isNotEmpty) {
        _onSpeechFinalResult(visible);
      }
    });
  }

  /// 處理 STT 最終辨識結果（使用者停口後）
  void _onSpeechFinalResult(String text) {
    if (!_isLiveMode) return;
    if (text.trim().isEmpty) return;

    // [小葵 2026-08-30] 抑制窗——fallback 送出後 3 秒內抵達的遲到 final
    // 直接丟棄，避免同一句送兩次 LLM。
    final now = DateTime.now();
    if (now.difference(_lastDispatchAt) < _dispatchSuppression) {
      debugPrint('[VoiceLive] 抑制遲到結果（剛送出過）："$text"');
      return;
    }
    _lastDispatchAt = now;

    debugPrint('[VoiceLive] 送出語音輸入：$text');

    // [小葵 2026-09-24 Blue 抓包④] 切句——把已送出的長度記為累積前綴，
    // 之後 dictation 累積 partial 只取新增句（殘留根修）。
    _speechHandler.markDispatched(text);

    // [小葵 2026-08-30] orchestrator 模式——整輪交給快答慢想雙軌，
    // 不再走 VoiceEngine.onSpeechRecognized（單軌整段朗讀）
    if (onExternalTurn != null) {
      onExternalTurn!(text);
      return;
    }

    // 透過 VoiceEngine 進入 thinking → 觸發 LLM
    _voiceEngine.onSpeechRecognized(
      VoiceInput(
        text: text,
        audioSamples: const [],
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// 處理 voice engine 狀態變化
  void _onEngineStateChanged() {
    final newState = _voiceEngine.state.value;
    debugPrint('[VoiceLive] VoiceEngine 狀態: $newState');

    switch (newState) {
      case VoiceState.idle:
        if (_isLiveMode) {
          state.value = VoiceLiveState.listening;
        } else {
          state.value = VoiceLiveState.idle;
        }
        _isAgentSpeaking = false;
        _interruptionDetector?.stopMonitoring();
        break;

      case VoiceState.listening:
        state.value = VoiceLiveState.listening;
        _isAgentSpeaking = false;
        _interruptionDetector?.stopMonitoring();
        break;

      case VoiceState.thinking:
        state.value = VoiceLiveState.thinking;
        _isAgentSpeaking = false;
        _interruptionDetector?.stopMonitoring();
        break;

      case VoiceState.speaking:
        state.value = VoiceLiveState.speaking;
        _isAgentSpeaking = true;
        // 啟動插嘴偵測（agent 講話時監聽使用者開不開口）
        // 由於 VoiceInterruptionDetector 預期 Stream<List<double>>，
        // 我們在 _onVolumeChanged 手動呼叫 processAmplitude
        debugPrint('[VoiceLive] Agent 開始講話，啟動插嘴偵測');
        break;
    }
  }

  bool get isLiveMode => _isLiveMode;

  void dispose() {
    stop();
    _voiceEngine.state.removeListener(_onEngineStateChanged);
    state.dispose();
  }
}

/// 雙向溝通狀態
enum VoiceLiveState {
  idle,        // 待機
  connecting,  // 啟動中
  listening,   // 監聽使用者（VAD 偵測到開口）
  thinking,    // LLM 思考中
  speaking,    // Agent 講話中
}
