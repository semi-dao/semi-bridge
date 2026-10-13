import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../core/responsive.dart';
import 'package:flutter/material.dart';

import '../widgets/breathing_image.dart'; // [小葵 2026-09-13] 呼吸感預覽
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent_activity.dart';
import '../models/bridge_action.dart';
import '../models/companion.dart';
import '../services/background_remover.dart';
import '../services/bridge_action_executor.dart';
import '../services/companion_asset_manifest_service.dart';
import '../services/companion_pack_service.dart';
import '../services/companion_store.dart';
import '../services/companion_summoning_service.dart';
import '../services/companion_image_vault.dart';
import '../services/image_provider_resolver.dart';
import '../services/semi_dao_review_store.dart';
import '../services/semi_dao_visual_review_service.dart';
import '../services/tts/kokoro_tts_service.dart';
// [小葵 2026-08-30] 測試播放真實發聲——與三個聊天 UI 同一播放器
import '../services/voice/native_audio_bytes_player.dart';
import '../theme/app_theme.dart';
import '../widgets/companion_art.dart';
import '../widgets/companion_avatar_image.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart'; // [教練 Agent 2026-08-05] Step 4 — Tier enum 用來查 TierStyle
import '../theme/tier_style.dart'; // [教練 Agent 2026-08-05] Step 4 — TierStyle.of() 替換寫死的 fontSize/fontWeight

class CompanionCreateScreen extends StatefulWidget {
  const CompanionCreateScreen({
    super.key,
    this.editingCompanionId,
    this.bridgeActionExecutor,
    this.imageGenerationTimeout = const Duration(seconds: 180),
    this.returnTo, // [以利沙 P1 修復十五輪 2026-06-27] 返回來源路由
    this.hideAppBar =
        false, // [教練 Agent 2026-08-04 Phase E+] BridgeDesktop 內嵌時隱藏
    this.onBack, // [教練 Agent 2026-08-04 Phase E+] 內嵌模式返回 callback
    this.onNavigateTo, // [教練 Agent 2026-08-04 Phase E+] 內嵌模式導航 callback
  });

  final String? editingCompanionId;
  final BridgeActionExecutor? bridgeActionExecutor;
  final Duration imageGenerationTimeout;
  final String? returnTo; // 返回目標，null 時預設 '/companions'
  final bool hideAppBar; // [教練 Agent 2026-08-04 Phase E+] BridgeDesktop 內嵌時隱藏
  final VoidCallback? onBack; // [教練 Agent 2026-08-04 Phase E+] 內嵌模式返回 callback
  final void Function(String page)?
  onNavigateTo; // [教練 Agent 2026-08-04 Phase E+] 內嵌模式導航 callback

  @override
  State<CompanionCreateScreen> createState() => _CompanionCreateScreenState();
}

class _CompanionCreateScreenState extends State<CompanionCreateScreen>
    with WidgetsBindingObserver {
  final _nameController = TextEditingController();
  final _inspirationController = TextEditingController();
  final _specialFunctionController = TextEditingController();
  final _speakingStyleController = TextEditingController();
  final _personalityController = TextEditingController();
  final _expertiseController = TextEditingController();
  final _habitController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _artStyleController = TextEditingController();
  final _speciesController = TextEditingController();
  final _freeformController = TextEditingController();
  final _soulMdController = TextEditingController(); // [H3] 靈魂文檔
  final _summoningService = CompanionSummoningService();
  final _primaryVisualReviewService = const SemiDaoVisualReviewService();
  final _defaultBridgeActionExecutor = BridgeActionExecutor();

  Companion? _editingCompanion;
  CompanionSummoningCandidate? _candidate;
  bool _isSummoning = false;
  int _summonProgress =
      0; // [教練 Agent 2026-07-01] 0=閒置, 1=發送API, 2=等待生成, 3=去背處理, 4=完成
  bool _isReviewingPrimaryImage = false;
  SemiDaoVisualReviewResult? _primaryVisualReview;
  CompanionRightsPassport? _primaryRightsPassport;
  final Set<String> _generatingSheetKeys = <String>{};
  final Set<String> _timedOutGenerations = <String>{};
  final Set<String> _expandedSheetKeys = <String>{};
  final List<_ReferenceClueImage> _referenceImages = <_ReferenceClueImage>[];
  List<_SheetPose> _sheetStates = List<_SheetPose>.of(_defaultSheetPoses);
  // [教練 Agent 2026-08-12] 圖像模型由 ImageProviderResolver 自動選擇（從已設定金鑰的 provider）
  List<ResolvedImageModel> _availableImageModels = [];
  ResolvedImageModel? _resolvedImageModel;
  String? _selectedPresetLabel;
  int _rerollSalt = 0;
  bool _candidatePackSaved = false;
  // [以利沙 P2-16 2026-06-30] Stepper 重構 — 分步驟索引
  int _currentStep = 0;
  final GlobalKey _stepContentKey =
      GlobalKey(); // [教練 Agent 2026-07-01] 步驟切換時捲動定位
  // [教練 Agent 2026-07-03] Stepper 捲動控制器 — 強制切換步驟時回到頂部
  final ScrollController _stepperScrollController = ScrollController();
  // [教練 Agent 2026-06-29] 呼吸系統 state 變數已封存

  // [Kokoro TTS 2026-07-28] 語音設定 state
  String _voiceName = 'zf_xiaoxiao'; // 聲音名稱，預設小曉
  String? _importedAnimationPath; // [小葵 2026-09-24 出道令] 匯入的外部動畫影片
  double _voiceSpeed = 1.0; // 語速 0.5–2.0
  bool _emotionEnabled = true; // 情緒表達開關
  double _emotionSensitivity = 0.5; // 情緒敏感度 0.0–1.0
  bool _isTestingVoice = false; // 測試播放中
  final KokoroTtsService _kokoroTtsService = KokoroTtsService();
  // [小葵 2026-08-30] 測試播放用——與三個聊天 UI 的 onPlayAudioBytes 同一播放器
  final NativeAudioBytesPlayer _testVoicePlayer = NativeAudioBytesPlayer();

  BridgeActionExecutor get _bridgeActionExecutor =>
      widget.bridgeActionExecutor ?? _defaultBridgeActionExecutor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // [教練 Agent 2026-08-13] 效能追蹤
    final _t0 = DateTime.now();
    debugPrint('[PerfTrace] CompanionCreateScreen.initState start');
    // [教練 Agent 2026-08-12] 啟動時偵測可用圖像引擎
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[PerfTrace] postFrame #1: _resolveImageModels start');
      if (mounted) _resolveImageModels();
      debugPrint('[PerfTrace] postFrame #1: _resolveImageModels done');
    });
    // [小葵 2026-08-30] 背景預熱 Kokoro server（金鑰匙原則：使用者按測試
    // 播放時 server 已就緒，第一次鍊成就有完整語音體驗）。不 await、不擋 UI；
    // 啟動失敗靜默——測試播放時 _testVoicePlayback 會再ensure並誠實報錯。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          _kokoroTtsService.startServer().then((ok) {
            debugPrint(
              '[CompanionCreate] Kokoro 預熱: ${ok ? '✅ 就緒' : '❌ 失敗（測試播放時會再試）'}',
            );
          }),
        );
      }
    });
    final editingId = widget.editingCompanionId?.trim();
    final isEditing = editingId != null && editingId.isNotEmpty;
    if (editingId != null && editingId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('[PerfTrace] postFrame #2: _loadCompanionForEditing start');
        if (mounted) _loadCompanionForEditing(editingId);
        debugPrint('[PerfTrace] postFrame #2: _loadCompanionForEditing fired');
      });
      debugPrint(
        '[PerfTrace] initState end (editing mode), elapsed: ${DateTime.now().difference(_t0).inMilliseconds}ms',
      );
      return;
    }
    // [教練 Agent 2026-06-29] 問題2：啟動時檢查是否有未完成草稿
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreDraftIfAvailable();
    });
  }

  @override
  void dispose() {
    // [教練 Agent 2026-07-01] 修復：離開畫面時也存草稿，
    // 避免用戶按返回鍵後下次回來恢復的是更早的版本
    _saveDraft();
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _inspirationController.dispose();
    _specialFunctionController.dispose();
    _speakingStyleController.dispose();
    _personalityController.dispose();
    _expertiseController.dispose();
    _habitController.dispose();
    _relationshipController.dispose();
    _artStyleController.dispose();
    _speciesController.dispose();
    _freeformController.dispose();
    _soulMdController.dispose();
    _stepperScrollController.dispose();
    // [Kokoro TTS 2026-07-28] 釋放 TTS 服務資源
    // [小葵 2026-08-30] 注意：不 stopServer——server 採「port 被佔即重用」，
    // 留著給下一個畫面（聊天 VoiceEngine）直接重用，跟 18789 同原則。
    unawaited(_kokoroTtsService.dispose());
    unawaited(_testVoicePlayer.dispose());
    super.dispose();
  }

  Future<void> _loadCompanionForEditing(String companionId) async {
    final _t = DateTime.now();
    debugPrint('[PerfTrace] _loadCompanionForEditing: start');
    final companion = CompanionStore().getById(companionId);
    debugPrint(
      '[PerfTrace] getById: ${DateTime.now().difference(_t).inMilliseconds}ms',
    );
    if (companion == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('找不到要編輯的夥伴。')));
      return;
    }
    _editingCompanion = companion;

    // [教練 Agent 2026-08-13] 效能優化：繞過 pack JSON 來回轉換，直接從 companion 組 candidate
    // 舊做法 exportCompanionPackToJson → _importPackJson 會多 ~2s 延遲
    final importedImages = Map<String, String>.from(companion.stateImagePaths);
    final candidate = CompanionSummoningCandidate(
      name: companion.name,
      mbtiCode: companion.mbtiCode,
      role: companion.role,
      personalityTags: companion.personalityTags,
      seed: companion.appearanceSeed,
      appearancePrompt: companion.appearancePrompt,
      appearanceDescription: companion.appearanceDescription,
      generatedImagePath:
          (companion.avatarImagePath?.trim().isNotEmpty == true &&
                  _looksLikeImagePath(companion.avatarImagePath!))
              ? companion.avatarImagePath
              : null,
      generatedSheetImagePaths: importedImages,
      sheetGenerationMessages: {
        for (final key in importedImages.keys) key: '已從夥伴資料載入。',
      },
      // [Blue UX 2026-09-17] 誠實訊息——avatarImagePath 可能是程序化資產 ID
      // （cmp_xxx_avatar 渲染種子）不是圖檔；佔位圖不得宣稱「已載入主形象」
      visualGenerationMessage:
          (companion.avatarImagePath?.trim().isNotEmpty == true &&
                  _looksLikeImagePath(companion.avatarImagePath!))
              ? '已從夥伴資料載入主形象。'
              : null,
      characterSheetPrompts: const <String>[],
    );

    // 填入 clues（文字欄位）— [教練 Agent 2026-08-14] 全部 10 個欄位都從 companion 載入
    _nameController.text = companion.name;
    _inspirationController.text = companion.inspiration.isNotEmpty
        ? companion.inspiration
        : companion.roleName;
    _specialFunctionController.text = companion.specialFunction.isNotEmpty
        ? companion.specialFunction
        : companion.roleName;
    _speakingStyleController.text = companion.speakingStyle;
    _personalityController.text = companion.personality;
    _expertiseController.text = companion.expertise;
    _habitController.text = companion.habit;
    _relationshipController.text = companion.relationship;
    _artStyleController.text = companion.artStyle;
    _speciesController.text = companion.species;
    _freeformController.text = companion.freeform;
    _soulMdController.text = companion.soulMd; // [H3]

    if (!mounted) return;
    setState(() {
      _sheetStates = List<_SheetPose>.of(_defaultSheetPoses);
      _candidate = candidate;
      _candidatePackSaved = true;
      _editingCompanion = companion;
      _primaryRightsPassport = companion.rightsPassport;
      _voiceName = companion.voiceName;
      _voiceSpeed = companion.voiceSpeed;
      _emotionEnabled = companion.emotionEnabled;
      _emotionSensitivity = companion.emotionSensitivity;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已載入 ${companion.name}，可以繼續調整。')));
  }

  // [教練 Agent 2026-06-29] 問題2：App 背景被殺後狀態歸零
  // 在 paused 時把草稿存到 SharedPreferences，resumed/initState 時恢復
  static const _draftKey = 'companion_create_draft_v1';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveDraft();
    } else if (state == AppLifecycleState.resumed) {
      _checkInterruptedGenerations();
    }
  }

  /// [Blue UX 2026-09-17] 回前景檢查中斷——三重修正：
  /// 1. 「中斷」定義收緊：必須「曾經開始生狀態圖」（至少 1 張存在）且未全部
  ///    完成才算中斷。0 張＝使用者根本還沒開始（主形象可能剛生成好），
  ///    彈「生成中斷」是說謊——Blue 實測被幽靈彈窗嚇到。
  /// 2. 按鈕文字「重試」→「繼續」：續跑未完成的，不是重新生成。
  /// 3. 防連發：macOS 切視窗會連發多次 resumed，SnackBar 會排隊彈兩次——
  ///    用 _interruptSnackBarShown 旗標一輪只彈一次（新生成開始時重置）。
  bool _interruptSnackBarShown = false;

  void _checkInterruptedGenerations() {
    if (_candidate == null) return;
    if (_generatingSheetKeys.isNotEmpty) return;
    if (_interruptSnackBarShown) return;
    final hasAnySheet = _sheetStates.any(
      (pose) =>
          _candidate?.generatedSheetImagePaths[pose.key]?.trim().isNotEmpty ==
          true,
    );
    if (!hasAnySheet) return; // 0 張＝尚未開始，不是中斷
    final allDone = _sheetStates.every(
      (pose) =>
          _candidate?.generatedSheetImagePaths[pose.key]?.trim().isNotEmpty ==
          true,
    );
    if (allDone) return;
    if (!mounted) return;
    _interruptSnackBarShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('狀態圖有幾張還沒完成，要繼續生成嗎？'),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: '繼續',
          onPressed: _retryMissingSheetImages,
        ),
      ),
    );
  }

  /// 重試生成未完成的狀態圖
  Future<void> _retryMissingSheetImages() async {
    final candidate = _candidate;
    if (candidate == null) return;
    for (final pose in List<_SheetPose>.of(_sheetStates)) {
      if (!mounted) return;
      final latest = _candidate;
      if (latest == null || latest.seed != candidate.seed) return;
      if (latest.generatedSheetImagePaths[pose.key]?.trim().isNotEmpty ==
          true) {
        continue;
      }
      await _generateSheetImage(latest, pose);
    }
  }

  Future<void> _saveDraft() async {
    if (_candidate == null && _nameController.text.trim().isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = <String, dynamic>{
        'name': _nameController.text,
        'inspiration': _inspirationController.text,
        'specialFunction': _specialFunctionController.text,
        'speakingStyle': _speakingStyleController.text,
        'personality': _personalityController.text,
        'expertise': _expertiseController.text,
        'habit': _habitController.text,
        'relationship': _relationshipController.text,
        'artStyle': _artStyleController.text,
        'species': _speciesController.text,
        'freeform': _freeformController.text,
        if (_soulMdController.text.trim().isNotEmpty)
          'soulMd': _soulMdController.text, // [H3]
        'savedAt': DateTime.now().toIso8601String(),
      };
      if (_candidate != null) {
        final c = _candidate!;
        draft['candidate'] = {
          'name': c.name,
          'mbtiCode': c.mbtiCode,
          'seed': c.seed,
          'appearancePrompt': c.appearancePrompt,
          'appearanceDescription': c.appearanceDescription,
          'generatedImagePath': c.generatedImagePath,
          'generatedSheetImagePaths': c.generatedSheetImagePaths,
          'sheetGenerationMessages': c.sheetGenerationMessages,
          'characterSheetPrompts': c.characterSheetPrompts,
        };
      }
      if (_referenceImages.isNotEmpty) {
        draft['referenceImages'] = _referenceImages
            .map(
              (r) => {
                'id': r.id,
                'name': r.name,
                'value': r.value,
                'sourceLabel': r.sourceLabel,
              },
            )
            .toList();
      }
      draft['sheetStates'] = _sheetStates
          .map(
            (s) => {
              'key': s.key,
              'label': s.label,
              'behavior': s.behavior,
              'expression': s.expression,
              'triggerScene': s.triggerScene,
              'triggerKeywords': s.triggerKeywords,
            },
          )
          .toList();
      await prefs.setString(_draftKey, jsonEncode(draft));
    } catch (_) {
      // 靜默失敗 — 草稿保存不能 crash app
    }
  }

  Future<void> _restoreDraftIfAvailable() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_draftKey);
      if (json == null || json.isEmpty) return;
      final draft = jsonDecode(json) as Map<String, dynamic>;

      // 檢查草稿是否太舊（超過 24 小時就不恢復）
      final savedAt = draft['savedAt'] as String?;
      if (savedAt != null) {
        final age = DateTime.now().difference(DateTime.parse(savedAt));
        if (age.inHours > 24) {
          await prefs.remove(_draftKey);
          return;
        }
      }

      // 恢復文字欄位
      _nameController.text = draft['name'] as String? ?? '';
      _inspirationController.text = draft['inspiration'] as String? ?? '';
      _specialFunctionController.text =
          draft['specialFunction'] as String? ?? '';
      _speakingStyleController.text = draft['speakingStyle'] as String? ?? '';
      _personalityController.text = draft['personality'] as String? ?? '';
      _expertiseController.text = draft['expertise'] as String? ?? '';
      _habitController.text = draft['habit'] as String? ?? '';
      _relationshipController.text = draft['relationship'] as String? ?? '';
      _artStyleController.text = draft['artStyle'] as String? ?? '';
      _speciesController.text = draft['species'] as String? ?? '';
      _freeformController.text = draft['freeform'] as String? ?? '';
      _soulMdController.text = draft['soulMd'] as String? ?? ''; // [H3]

      // 恢復參考圖
      final refImages = draft['referenceImages'] as List<dynamic>?;
      if (refImages != null) {
        _referenceImages.clear();
        for (final item in refImages) {
          final m = item as Map<String, dynamic>;
          _referenceImages.add(
            _ReferenceClueImage(
              id: m['id'] as String,
              name: m['name'] as String,
              value: m['value'] as String,
              sourceLabel: m['sourceLabel'] as String,
            ),
          );
        }
      }

      // 恢復狀態圖設定
      final sheetStates = draft['sheetStates'] as List<dynamic>?;
      if (sheetStates != null) {
        for (final item in sheetStates) {
          final m = item as Map<String, dynamic>;
          final key = m['key'] as String;
          final index = _sheetStates.indexWhere((s) => s.key == key);
          if (index >= 0) {
            _sheetStates[index] = _sheetStates[index].copyWith(
              label: m['label'] as String?,
              behavior: m['behavior'] as String?,
              expression: m['expression'] as String?,
              triggerScene: m['triggerScene'] as String?,
              triggerKeywords: (m['triggerKeywords'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList(),
            );
          }
        }
      }

      // 恢復候選角色（含已生成圖片路徑）
      // [教練 Agent 2026-06-30] 修復：草稿恢復時驗證圖片檔案是否真的存在，
      // iOS 重裝 app 後 container 路徑改變，舊路徑指向不存在的檔案。
      // 不驗證的話進度板會誤顯「已生成」但實際圖片是空的。
      final candidateJson = draft['candidate'] as Map<String, dynamic>?;
      if (candidateJson != null) {
        // 透過 summon 重新生成候選骨架，然後覆寫已生成的圖片路徑
        final candidate = _summoningService.summon(
          _readClues(),
          salt: candidateJson['seed'] as int?,
        );
        // 驗證主形象路徑：檔案不存在就清空
        final restoredPrimaryPath =
            candidateJson['generatedImagePath'] as String?;
        final validPrimaryPath =
            (restoredPrimaryPath != null &&
                restoredPrimaryPath.trim().isNotEmpty &&
                File(restoredPrimaryPath).existsSync())
            ? restoredPrimaryPath
            : null;
        // 驗證狀態圖路徑：逐一檢查，不存在的清掉
        final rawSheetPaths = Map<String, String>.from(
          candidateJson['generatedSheetImagePaths'] as Map? ?? {},
        );
        final validSheetPaths = Map<String, String>.fromEntries(
          rawSheetPaths.entries.where(
            (e) => e.value.trim().isNotEmpty && File(e.value).existsSync(),
          ),
        );
        _candidate = candidate.copyWith(
          generatedImagePath: validPrimaryPath,
          generatedSheetImagePaths: validSheetPaths,
          sheetGenerationMessages: Map<String, String>.from(
            candidateJson['sheetGenerationMessages'] as Map? ?? {},
          ),
        );
      }

      if (mounted) {
        setState(() {
          // [以利沙 P2-16 2026-06-30] Stepper 重構 — 恢復草稿有 candidate 時自動跳到預覽步驟
          // [教練 Agent 2026-06-30] 5 步重構：有主形象跳 Step 3，有狀態圖跳 Step 4
          if (_candidate != null) {
            final hasPrimary =
                _candidate!.generatedImagePath?.trim().isNotEmpty == true;
            final hasSheets = _sheetStates.any(
              (s) =>
                  _candidate!.generatedSheetImagePaths[s.key]
                      ?.trim()
                      .isNotEmpty ==
                  true,
            );
            _currentStep = hasSheets ? 4 : (hasPrimary ? 4 : 3);
          }
        });
        if (_candidate != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已恢復上次的草稿，可以繼續編輯。'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (_) {
      // 草稿恢復失敗不 crash app
    }
  }

  /// 清除草稿（角色確認建立後呼叫）
  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // [教練 Agent 2026-08-05 Step 3a] 寫死的 AppTheme.surfaceHighlight 改成 context 動態查
      backgroundColor: BridgeDSColors.of(context).surface,
      // [教練 Agent 2026-08-05] 內嵌模式（_wrapCompanionSubPage）時隱藏內部 AppBar，
      // 由外殼提供標題列。否則會跟外殼標題列重複。
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: BridgeDSColors.of(context).textPrimary,
                  size: 28,
                ),
                tooltip: '返回',
                onPressed: () {
                  // [教練 Agent 修復真機輪 2026-06-27] 改用實心 arrow_back + 加大 size + tooltip，
                  // 原本 arrow_back_ios 細箭頭在深色背景太不明顯，真機上使用者找不到返回鍵
                  if (widget.returnTo != null) {
                    context.go(widget.returnTo!);
                  } else {
                    context.go('/companions');
                  }
                },
              ),
              title: Text(_editingCompanion == null ? '創造第一位夥伴' : '調整夥伴設定'),
              backgroundColor: BridgeDSColors.of(context).canvas,
            ),
      body: SafeArea(
        // [教練 Agent 2026-08-05 Step 3a] 寫死的 AppTheme.surfaceHighlight 改成
        // context 動態查 BridgeDSColors.surface，這樣切換 light/dark 主題時
        // 背景會跟著變（Tier 系統正式接上前的基礎工作）
        child: DecoratedBox(
          decoration: BoxDecoration(color: BridgeDSColors.of(context).surface),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide =
                  Responsive.isDesktop(context) || constraints.maxWidth >= 920;
              // [以利沙 P2-16 2026-06-30] Stepper 重構 — wide 維持原 SingleChildScrollView，narrow 改用 Stepper
              if (isWide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacingM,
                    AppTheme.spacingM,
                    AppTheme.spacingM,
                    AppTheme.spacingL,
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 1,
                            child: _buildSummonForm(
                              includeCandidate: false,
                              includeActions: false,
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacingM),
                          Expanded(flex: 1, child: _buildSummonPreviewPanel()),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingM),
                      _buildWideRitualActions(),
                    ],
                  ),
                );
              }
              // narrow: 使用 Stepper 分步驟
              return _buildStepperBody();
            },
          ),
        ),
      ),
    );
  }

  // [以利沙 P2-16 2026-06-30] Stepper 重構 — narrow layout 分步驟表單
  // [教練 Agent 2026-06-30] 步驟重排：preset 移到 Step 0，加中文化 controlsBuilder
  // [教練 Agent 2026-06-30] 拆成 5 步：基本→個性→造型→主形象預覽→狀態圖組
  String _stepSummary(int step) {
    switch (step) {
      case 0:
        final parts = <String>[];
        if (_selectedPresetLabel != null) parts.add(_selectedPresetLabel!);
        if (_nameController.text.trim().isNotEmpty)
          parts.add(_nameController.text.trim());
        if (_inspirationController.text.trim().isNotEmpty) {
          parts.add(_truncate(_inspirationController.text.trim(), 12));
        }
        if (_specialFunctionController.text.trim().isNotEmpty) {
          parts.add(_truncate(_specialFunctionController.text.trim(), 12));
        }
        return parts.isEmpty ? '' : parts.join(' · ');
      case 1:
        final parts = <String>[];
        if (_speakingStyleController.text.trim().isNotEmpty) {
          parts.add(
            '風格:${_truncate(_speakingStyleController.text.trim(), 10)}',
          );
        }
        if (_personalityController.text.trim().isNotEmpty) {
          parts.add('個性:${_truncate(_personalityController.text.trim(), 10)}');
        }
        if (_expertiseController.text.trim().isNotEmpty) {
          parts.add('專長:${_truncate(_expertiseController.text.trim(), 10)}');
        }
        if (_habitController.text.trim().isNotEmpty) {
          parts.add('習慣:${_truncate(_habitController.text.trim(), 10)}');
        }
        if (_relationshipController.text.trim().isNotEmpty) {
          parts.add('關係:${_truncate(_relationshipController.text.trim(), 10)}');
        }
        return parts.isEmpty ? '' : parts.join(' ');
      case 2:
        final parts = <String>[];
        if (_artStyleController.text.trim().isNotEmpty) {
          parts.add('畫風:${_truncate(_artStyleController.text.trim(), 12)}');
        }
        if (_speciesController.text.trim().isNotEmpty) {
          parts.add('種族:${_truncate(_speciesController.text.trim(), 10)}');
        }
        if (_freeformController.text.trim().isNotEmpty) {
          parts.add('描述:${_truncate(_freeformController.text.trim(), 12)}');
        }
        return parts.isEmpty ? '' : parts.join(' ');
      case 3:
        final hasImage =
            _candidate?.generatedImagePath?.trim().isNotEmpty == true;
        if (hasImage) return '主形象已生成';
        return '';
      case 4:
        final count = _candidate == null
            ? 0
            : _sheetStates
                  .where(
                    (s) =>
                        _candidate!.generatedSheetImagePaths[s.key]
                            ?.trim()
                            .isNotEmpty ==
                        true,
                  )
                  .length;
        if (count > 0) return '$count/${_sheetStates.length} 張已完成';
        return '';
      case 5:
        // [Kokoro TTS 2026-07-28] 語音設定摘要
        final voiceMatch = kokoroChineseVoices
            .where((v) => v.id == _voiceName)
            .toList();
        final voiceName = voiceMatch.isNotEmpty
            ? voiceMatch.first.name
            : _voiceName;
        return '$voiceName · 語速 ${_voiceSpeed.toStringAsFixed(1)}×'
            '${_emotionEnabled ? ' · 情緒開' : ''}';
      default:
        return '';
    }
  }

  String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}…';
  }

  Widget _buildStepperBody() {
    return Stepper(
      currentStep: _currentStep,
      onStepContinue: () {
        if (_currentStep < 5) {
          final nextStep = _currentStep + 1;
          setState(() => _currentStep = nextStep);
          // [教練 Agent 2026-07-03] 強制捲到頂部 — 找最近 Scrollable 直接 jumpTo(0)
          // ensureVisible 被 Stepper 內部捲動覆蓋，改用直接控制捲軸位置
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future.delayed(const Duration(milliseconds: 150), () {
              final ctx = _stepContentKey.currentContext;
              if (ctx != null) {
                final scrollable = Scrollable.maybeOf(ctx);
                if (scrollable != null) {
                  scrollable.position.jumpTo(0);
                }
              }
            });
          });
          // [Blue UX 2026-09-17] 移除「進 Step 4 自動生成 8 張狀態圖」——
          // 主形象還沒被使用者確認前不該衍生。狀態圖生成一律由使用者
          // 在 Step 4 手動按「生成全部狀態圖」按鈕觸發（按鈕已存在）。
          // 理由：主形象可能要換好幾張才定案，自動連生 8 張＝浪費＋
          // 全部跟錯母版。
        }
      },
      onStepCancel: () {
        if (_currentStep > 0) {
          setState(() => _currentStep--);
        }
      },
      onStepTapped: (step) {
        setState(() => _currentStep = step);
        // [教練 Agent 2026-07-03] 強制捲到頂部 — 找最近 Scrollable 直接 jumpTo(0)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 150), () {
            final ctx = _stepContentKey.currentContext;
            if (ctx != null) {
              final scrollable = Scrollable.maybeOf(ctx);
              if (scrollable != null) {
                scrollable.position.jumpTo(0);
              }
            }
          });
        });
      },
      type: StepperType.vertical,
      controlsBuilder: (context, details) {
        final isLastStep = _currentStep >= 5;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              // 下一步 / 完成
              // [教練 Agent 2026-07-01] 「下一步」改白色 OutlinedButton，只有最後一步「確定建立夥伴」和各步驟主動作按鈕保持藍色
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: isLastStep
                      ? FilledButton.icon(
                          onPressed: _confirmCandidate,
                          icon: const Icon(Icons.check_circle),
                          label: Text(
                            _editingCompanion == null ? '確定建立夥伴' : '更新夥伴',
                            style: TierStyle.of(
                              context,
                              Tier.cardTitle,
                            ).toTextStyle(),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: BridgeDSColors.of(context).canvas,
                            side: BorderSide(
                              color: BridgeDSColors.of(context).accentPurple,
                              width: 1.5,
                            ),
                            foregroundColor: BridgeDSColors.of(
                              context,
                            ).textPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: details.onStepContinue,
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(
                            '下一步',
                            style: TierStyle.of(
                              context,
                              Tier.cardTitle,
                            ).toTextStyle(),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: BridgeDSColors.of(
                              context,
                            ).textSecondary,
                            side: BorderSide(
                              color: BridgeDSColors.of(
                                context,
                              ).textSecondary.withValues(alpha: 0.3),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                ),
              ),
              if (_currentStep > 0) ...[
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: details.onStepCancel,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(
                        '上一步',
                        style: TierStyle.of(
                          context,
                          Tier.cardTitle,
                        ).toTextStyle(),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BridgeDSColors.of(
                          context,
                        ).textSecondary,
                        side: BorderSide(
                          color: BridgeDSColors.of(
                            context,
                          ).textSecondary.withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
      steps: [
        // Step 0: 基本資料（匯入角色包 → 預設範本 → 隨機點子 → 名字 → 靈感 → 特殊功能）
        Step(
          title: const Text('基本資料'),
          subtitle: _currentStep != 0 && _stepSummary(0).isNotEmpty
              ? Text(
                  _stepSummary(0),
                  style: TierStyle.of(context, Tier.stepSummary).toTextStyle(),
                )
              : const Text('先選夥伴類型，再填基本資訊'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // [教練 Agent 2026-06-30] 匯入角色包移到 Step 0 最上面
              _buildImportPackEntryPanel(),
              const SizedBox(height: AppTheme.spacingL),
              // [Blue UX 2026-09-17] 編輯模式下不顯示範本——按下會洗掉已設定的
              // 線索（地雷）；範本是「創造新夥伴」的起點，不是編輯工具
              if (_editingCompanion == null) ...[
                _buildArchetypePresets(),
                const SizedBox(height: AppTheme.spacingM),
              ],
              // [教練 Agent 2026-06-30] 隨機點子按鈕移到 Step 0，順序：分類 → 隨機 → 手動輸入
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _randomizeClues,
                  icon: const Icon(Icons.casino_outlined),
                  label: const Text('隨機給我點子'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BridgeDSColors.of(context).accentBlue,
                    side: BorderSide(
                      color: BridgeDSColors.of(
                        context,
                      ).accentBlue.withValues(alpha: 0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingL),
              _buildBasicInfoFields(),
            ],
          ),
          isActive: _currentStep >= 0,
        ),
        // Step 1: 個性設定
        Step(
          title: const Text('個性設定'),
          subtitle: _currentStep != 1 && _stepSummary(1).isNotEmpty
              ? Text(
                  _stepSummary(1),
                  style: TierStyle.of(context, Tier.stepSummary).toTextStyle(),
                )
              : null,
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildPersonalityFields(),
          ),
          isActive: _currentStep >= 1,
        ),
        // Step 2: 造型與視覺
        Step(
          title: const Text('造型與視覺'),
          subtitle: _currentStep != 2 && _stepSummary(2).isNotEmpty
              ? Text(
                  _stepSummary(2),
                  style: TierStyle.of(context, Tier.stepSummary).toTextStyle(),
                )
              : null,
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                _buildVisualFields(),
                const SizedBox(height: AppTheme.spacingL),
                _buildImageModelSelector(),
                const SizedBox(height: AppTheme.spacingL),
                // [教練 Agent 2026-06-30] 匯入角色包移到 Step 0，這裡不再顯示
                _buildReferenceImagePicker(),
              ],
            ),
          ),
          isActive: _currentStep >= 2,
        ),
        // Step 3: 預覽草稿（生成主形象）
        Step(
          title: const Text('預覽草稿'),
          subtitle: _currentStep != 3 && _stepSummary(3).isNotEmpty
              ? Text(
                  _stepSummary(3),
                  style: TierStyle.of(context, Tier.stepSummary).toTextStyle(),
                )
              : const Text('生成主形象'),
          content: Column(
            children: [
              // [教練 Agent 2026-06-30] 隨機按鈕已移到 Step 0，這裡只留預覽草稿
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _isSummoning ? null : _summonCandidate,
                  icon: _isSummoning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _isSummoning ? '生成中...' : '預覽草稿',
                    style: TierStyle.of(context, Tier.cardTitle).toTextStyle(),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: BridgeDSColors.of(context).canvas,
                    side: BorderSide(
                      color: BridgeDSColors.of(context).accentPurple,
                      width: 1.5,
                    ),
                    foregroundColor: BridgeDSColors.of(context).textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              // [教練 Agent 2026-07-01] 分階段進度條 + 防休眠提示
              if (_isSummoning) ...[
                SizedBox(height: 16),
                _buildSummonProgressBar(),
                SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(
                      context,
                    ).accentYellow.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: BridgeDSColors.of(
                        context,
                      ).accentYellow.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.phone_android,
                        size: 16,
                        color: BridgeDSColors.of(context).accentYellow,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '正在生成主形象，請保持螢幕開啟。\n不要讓手機休眠或切換應用程式，以免中斷。',
                          style: TierStyle.of(
                            context,
                            Tier.statusWarning,
                          ).toTextStyle().copyWith(height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_candidate != null) ...[
                const SizedBox(height: AppTheme.spacingL),
                _buildCandidateCard(_candidate!),
              ],
            ],
          ),
          isActive: _currentStep >= 3,
        ),
        // Step 4: 狀態圖組（獨立步驟，主形象生成後才能進入）
        Step(
          title: const Text('狀態圖組'),
          subtitle: _currentStep != 4 && _stepSummary(4).isNotEmpty
              ? Text(
                  _stepSummary(4),
                  style: TierStyle.of(context, Tier.stepSummary).toTextStyle(),
                )
              : const Text('生成待機、閱讀等狀態圖'),
          content:
              _candidate != null &&
                  _candidate!.generatedImagePath?.trim().isNotEmpty == true
              ? Column(
                  key: _stepContentKey,
                  children: [
                    _buildSheetPreview(_candidate!),
                    SizedBox(height: AppTheme.spacingL),
                    // [教練 Agent 2026-07-01] 資產包匯出移到 Step 4（全部圖生成完再匯出）
                    _buildPackActionPanel(_candidate!),
                    // [教練 Agent 2026-07-01] 「確定建立夥伴」按鈕已移至 controlsBuilder 的「完成」按鈕，
                    // 不再重複顯示在步驟內容裡
                  ],
                )
              : Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 32,
                        color: BridgeDSColors.of(context).textMuted,
                      ),
                      SizedBox(height: 8),
                      Text(
                        '請先在上一步生成主形象，才能開始製作狀態圖。',
                        style: TierStyle.of(context, Tier.listItemSubtitle)
                            .toTextStyle()
                            .copyWith(
                              color: BridgeDSColors.of(context).textMuted,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
          isActive: _currentStep >= 4,
        ),
        // Step 5: 語音設定（Kokoro TTS）
        Step(
          title: const Text('語音設定'),
          subtitle: _currentStep != 5 && _stepSummary(5).isNotEmpty
              ? Text(
                  _stepSummary(5),
                  style: TierStyle.of(context, Tier.stepSummary).toTextStyle(),
                )
              : const Text('設定夥伴的聲音與情緒表達'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildVoiceSettingsFields(),
          ),
          isActive: _currentStep >= 5,
        ),
      ],
    );
  }

  Widget _buildSummonForm({
    required bool includeCandidate,
    bool includeActions = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [教練 Agent 2026-08-05 Phase E+ 編輯模式隱藏] 左側「輸入描述，創造你的 AI 夥伴」標題卡 — 編輯模式已建立角色，不需要創建引導
        Visibility(
          visible: _editingCompanion == null,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: false,
          child: _buildRitualHeader(),
        ),
        const SizedBox(height: AppTheme.spacingM),
        // [教練 Agent 2026-08-05 Phase E+ 編輯模式隱藏] 左側「建立任務進度」進度板 — 編輯模式不需要建立嚮導
        Visibility(
          visible: _editingCompanion == null,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: false,
          child: _buildSummonQuestBoard(candidate: _candidate),
        ),
        const SizedBox(height: AppTheme.spacingL),
        // [教練 Agent 2026-08-05 Phase E+ 編輯模式搬移] 圖像版本/模型品質選擇器已從左側移除，改放到右側「重新生成」按鈕之上（見 _buildCandidateCard）
        // [Blue UX 2026-09-17] 編輯模式下不顯示範本（第二呼叫點——桌面寬畫面版；
        // 按下會洗掉已設定線索，且此頁第一個區塊應為匯入角色資產包）
        if (_editingCompanion == null) ...[
          _buildArchetypePresets(),
          const SizedBox(height: AppTheme.spacingL),
        ],
        _buildImportPackEntryPanel(),
        const SizedBox(height: AppTheme.spacingL),
        _buildReferenceImagePicker(),
        const SizedBox(height: AppTheme.spacingL),
        _buildClueGrid(),
        const SizedBox(height: AppTheme.spacingL),
        // [小葵 2026-08-30] 桌面版寬畫面鍊成流程補上語音設定
        // Stepper 的 Step 5（語音設定）只在窄畫面顯示；寬畫面（≥920px，桌面
        // App 必然走這條）的 _buildSummonForm 原本完全沒有語音入口，導致
        // 「鍊成過程中調不了聲音/語速/情緒」。這裡把同一組欄位接回主流程。
        _buildVoiceSettingsCard(),
        if (includeActions) ...[
          const SizedBox(height: AppTheme.spacingM),
          _buildRitualActions(),
        ],
        if (includeCandidate && _candidate != null) ...[
          const SizedBox(height: AppTheme.spacingL),
          _buildCandidateCard(_candidate!),
        ],
        if (includeCandidate) const SizedBox(height: AppTheme.spacingL),
      ],
    );
  }

  Widget _buildSummonPreviewPanel() {
    final candidate = _candidate;
    if (candidate == null) {
      final clues = _readClues();
      final previewName = clues.name.trim().isEmpty
          ? '山門光靈'
          : clues.name.trim();
      return LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth - 80;
          final availableHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight - 150
              : availableWidth;
          final artSize = math
              .min(availableWidth, availableHeight)
              .clamp(300.0, 720.0)
              .toDouble();
          return Container(
            width: double.infinity,
            height: constraints.hasBoundedHeight ? double.infinity : 620,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  BridgeDSColors.of(context).accentNavy,
                  BridgeDSColors.of(context).accentNavy,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              boxShadow: AppTheme.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: BridgeDSColors.of(context).accentYellow,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '形象預覽',
                      style: tierBasedStyle(
                        context,
                        Tier.blockHeading,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: CompanionArt(
                      mbtiCode: 'ENFJ',
                      seed: _rerollSalt + 42,
                      name: previewName,
                      mood: AgentCompanionMood.curious,
                      action: AgentCompanionAction.wandering,
                      size: artSize,
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  previewName,
                  style: tierBasedStyle(
                    context,
                    Tier.appTitle,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '等待線索凝聚',
                  style: TierStyle.of(
                    context,
                    Tier.listItemSubtitle,
                  ).toTextStyle(),
                ),
              ],
            ),
          );
        },
      );
    }

    return _buildCandidateCard(candidate);
  }

  Widget _buildRitualHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            BridgeDSColors.of(context).surface,
            BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.16),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: BridgeDSColors.of(
                context,
              ).accentBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_awesome,
              color: BridgeDSColors.of(context).accentBlue,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '輸入描述，創造你的 AI 夥伴',
                  style: tierBasedStyle(
                    context,
                    Tier.blockHeading,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '像創造遊戲角色一樣，填寫靈感、功能、個性與畫風。你可以建立多位夥伴，他們共用同一個大腦架構與長期記憶，但各自有不同專長與說話方式。',
                  style: TierStyle.of(
                    context,
                    Tier.listItemSubtitle,
                  ).toTextStyle().copyWith(height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // [教練 Agent 2026-08-12] 從金鑰偵測所有可用圖像引擎，自動選最高階
  Future<void> _resolveImageModels() async {
    final _t = DateTime.now();
    debugPrint('[PerfTrace] _resolveImageModels: start');
    final all = await ImageProviderResolver.resolveAll();
    debugPrint(
      '[PerfTrace] resolveAll: ${DateTime.now().difference(_t).inMilliseconds}ms',
    );
    if (!mounted) return;
    setState(() {
      _availableImageModels = all;
      // 預設選最高階（rank 1）
      _resolvedImageModel = all.isNotEmpty ? all.first : null;
    });
  }

  // [教練 Agent 2026-08-12] 圖像生成引擎選擇器
  // - 0 個金鑰 → 顯示「請設定金鑰」提示
  // - 1 個金鑰 → 唯讀顯示（不需要選）
  // - 2+ 個金鑰 → 讓用戶選擇（按鈕列表）
  Widget _buildImageModelSelector() {
    // 沒有金鑰
    if (_availableImageModels.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(
            color: BridgeDSColors.of(context).borderSubtle,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(
                      context,
                    ).accentYellow.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.key_off_outlined,
                    color: BridgeDSColors.of(context).accentYellow,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '尚未設定任何圖像生成金鑰',
                    style: tierBasedStyle(
                      context,
                      Tier.listItemTitle,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '請到「能力中心 → 圖像生成」設定 OpenAI / MiniMax / Replicate / Gemini 任一 provider 的 API 金鑰，才能召喚夥伴。',
              style: TierStyle.of(context, Tier.cardCaptionBold)
                  .toTextStyle()
                  .copyWith(
                    color: BridgeDSColors.of(context).textSecondary,
                    height: 1.35,
                  ),
            ),
          ],
        ),
      );
    }

    // 只有 1 個引擎 → 唯讀顯示
    if (_availableImageModels.length == 1) {
      final model = _availableImageModels.first;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(
            color: BridgeDSColors.of(
              context,
            ).accentBlue.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: BridgeDSColors.of(
                  context,
                ).accentBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_outlined,
                color: BridgeDSColors.of(context).accentBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '圖像生成引擎',
                    style: tierBasedStyle(
                      context,
                      Tier.listItemTitle,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${model.adapterName} · ${model.defaultModel}',
                    style: TierStyle.of(context, Tier.cardCaptionBold)
                        .toTextStyle()
                        .copyWith(
                          color: BridgeDSColors.of(context).textSecondary,
                          height: 1.3,
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.lock_outline,
              size: 16,
              color: BridgeDSColors.of(context).textMuted,
            ),
          ],
        ),
      );
    }

    // 2+ 個引擎 → 讓用戶選擇
    final selected = _resolvedImageModel ?? _availableImageModels.first;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(
          color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(
                    context,
                  ).accentBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.tune_outlined,
                  color: BridgeDSColors.of(context).accentBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '圖像生成引擎',
                      style: tierBasedStyle(
                        context,
                        Tier.listItemTitle,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${_availableImageModels.length} 個可用引擎',
                      style: TierStyle.of(context, Tier.cardCaptionBold)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textSecondary,
                            height: 1.3,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final count = _availableImageModels.length;
              final wide = constraints.maxWidth >= 700;
              final crossCount = wide ? math.min(count, 4) : math.min(count, 2);
              final itemWidth =
                  (constraints.maxWidth - 8 * (crossCount - 1)) / crossCount;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final model in _availableImageModels)
                    SizedBox(
                      width: itemWidth,
                      child: _ImageEngineButton(
                        model: model,
                        selected: model.providerId == selected.providerId,
                        onPressed: () {
                          setState(() => _resolvedImageModel = model);
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildArchetypePresets() {
    final presets = [
      _SummonPreset(
        label: '理性秩序',
        icon: Icons.science_outlined,
        clues: const CompanionSummoningClues(
          name: '',
          inspiration: '冷靜、可靠、擅長研究與判斷的理性夥伴',
          specialFunction: '替我研究資料、檢查邏輯、比較方案',
          speakingStyle: '嚴謹、精準、一步一步說清楚',
          personality: '冷靜、專注、策略性、批判思考',
          expertise: '研究分析與技術判斷',
          habit: '思考時會翻閱記憶與標記疑點',
          relationship: '像可靠的策略顧問',
          artStyle: '明亮的遊戲角色設定圖',
          species: '知識光靈',
          freeform: '需要嚴謹時找我，會提醒風險與缺漏。',
        ),
      ),
      _SummonPreset(
        label: '靈感創造',
        icon: Icons.palette_outlined,
        clues: const CompanionSummoningClues(
          name: '',
          inspiration: '自由、跳躍、擅長風格與創意轉換的創造夥伴',
          specialFunction: '替我發想創意、轉換視角、生成視覺方向',
          speakingStyle: '跳躍、幽默、充滿畫面感',
          personality: '創意、自由、搞笑、敢打破規則',
          expertise: '創意發想與風格設計',
          habit: '閒著時會在桌面做奇怪小動作',
          relationship: '像一起冒險的創作搭檔',
          artStyle: '鮮明 2D 動畫風與抽象幾何角色設定圖',
          species: '色塊精靈',
          freeform: '需要創意時找我，會提出意外但有用的連結。',
        ),
      ),
      _SummonPreset(
        label: '表達共鳴',
        icon: Icons.edit_note_outlined,
        clues: const CompanionSummoningClues(
          name: '',
          inspiration: '溫暖、敏銳、擅長語言與情感整理的表達夥伴',
          specialFunction: '替我寫文章、潤飾文字、找出漂亮表達',
          speakingStyle: '有文采、溫暖、句子帶節奏',
          personality: '浪漫、敏銳、溫柔、自由',
          expertise: '寫作、命名、故事與文案',
          habit: '想到好句子時會發光',
          relationship: '像坐在旁邊陪我寫作的朋友',
          artStyle: '柔和水墨融合遊戲角色設定圖',
          species: '月光詩靈',
          freeform: '需要文章、標語、故事感時找我。',
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '選擇預設夥伴範本',
          style: tierBasedStyle(
            context,
            Tier.blockHeading,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '先選能力傾向，再用下面的線索調整成獨一無二的夥伴。',
          style: TierStyle.of(context, Tier.cardCaptionBold)
              .toTextStyle()
              .copyWith(
                color: BridgeDSColors.of(context).textSecondary,
                fontSize: 14,
                height: 1.35,
              ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final itemWidth = wide
                ? (constraints.maxWidth - 20) / 3
                : constraints.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: presets.map((preset) {
                return SizedBox(
                  width: itemWidth,
                  height: 54,
                  child: _SummonCircleButton(
                    preset: preset,
                    selected: preset.label == _selectedPresetLabel,
                    onPressed: () => _applyPreset(preset),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildClueGrid() {
    return Column(
      children: [
        _buildTextField('名字', _nameController, '可留空，由生成結果命名'),
        _buildTextField('人物名人靈感', _inspirationController, '像某種氣質、角色原型或傳說'),
        _buildTextField('特殊功能', _specialFunctionController, '例如：替我開通新 AI 服務'),
        _buildTextField('說話風格', _speakingStyleController, '溫暖短句、精準直接、幽默吐槽'),
        _buildTextField('個性', _personalityController, '好奇、可靠、搞笑、守護、冷靜'),
        _buildTextField('專長', _expertiseController, '研究、寫作、工具導航、創意發想'),
        _buildTextField('習慣', _habitController, '思考時發光、閒著會散步'),
        _buildTextField('與使用者的關係', _relationshipController, '搭檔、朋友、守護者、小助理'),
        _buildTextField('畫風', _artStyleController, '遊戲角色設定圖、2D 動畫、像素寵物'),
        _buildTextField('種族', _speciesController, '光靈、機械妖精、星塵使者'),
        _buildTextField(
          '自由敘述',
          _freeformController,
          '建議 20 字左右，例如：需要嚴謹時找我，會提醒風險',
          maxLines: 3,
        ),
        // [H3 2026-10-08] 靈魂文檔——人格最深處，注入 system prompt 最頂層
        _buildTextField(
          '靈魂文檔 SOUL',
          _soulMdController,
          'Markdown。核心身份層（先於角色與風格）。Hermes 移民用：貼上 SOUL.md',
          maxLines: 8,
        ),
      ],
    );
  }

  // [以利沙 P2-16 2026-06-30] Stepper 重構 — Step 0 基本資料欄位
  Widget _buildBasicInfoFields() {
    return Column(
      children: [
        _buildTextField('名字', _nameController, '可留空，由生成結果命名'),
        _buildTextField('人物名人靈感', _inspirationController, '像某種氣質、角色原型或傳說'),
        _buildTextField('特殊功能', _specialFunctionController, '例如：替我開通新 AI 服務'),
      ],
    );
  }

  // [以利沙 P2-16 2026-06-30] Stepper 重構 — Step 1 個性設定欄位
  Widget _buildPersonalityFields() {
    return Column(
      children: [
        _buildTextField('說話風格', _speakingStyleController, '溫暖短句、精準直接、幽默吐槽'),
        _buildTextField('個性', _personalityController, '好奇、可靠、搞笑、守護、冷靜'),
        _buildTextField('專長', _expertiseController, '研究、寫作、工具導航、創意發想'),
        _buildTextField('習慣', _habitController, '思考時發光、閒著會散步'),
        _buildTextField('與使用者的關係', _relationshipController, '搭檔、朋友、守護者、小助理'),
      ],
    );
  }

  // [以利沙 P2-16 2026-06-30] Stepper 重構 — Step 2 造型與視覺欄位
  Widget _buildVisualFields() {
    return Column(
      children: [
        _buildTextField('畫風', _artStyleController, '遊戲角色設定圖、2D 動畫、像素寵物'),
        _buildTextField('種族', _speciesController, '光靈、機械妖精、星塵使者'),
        _buildTextField(
          '自由敘述',
          _freeformController,
          '建議 20 字左右，例如：需要嚴謹時找我，會提醒風險',
          maxLines: 3,
        ),
      ],
    );
  }

  // [小葵 2026-08-30] 寬畫面鍊成流程的語音設定卡片
  // 樣式對齊「圖像生成引擎」卡片（圓形 icon + 標題 + 說明），
  // 內容重用 Stepper Step 5 的 _buildVoiceSettingsFields（聲音/語速/情緒/測試播放）。
  Widget _buildVoiceSettingsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(
          color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(
                    context,
                  ).accentBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.graphic_eq,
                  color: BridgeDSColors.of(context).accentBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '語音與情緒',
                      style: tierBasedStyle(
                        context,
                        Tier.listItemTitle,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '設定夥伴的聲音、語速與情緒表達（Kokoro TTS）',
                      style: TierStyle.of(context, Tier.cardCaptionBold)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textSecondary,
                            height: 1.3,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildVoiceSettingsFields(
            showAdvancedEntry: _editingCompanion != null,
          ),
        ],
      ),
    );
  }

  // [Kokoro TTS 2026-07-28] Step 5 語音設定欄位
  // [小葵 2026-08-30] showAdvancedEntry — 進階語音設定入口需要已存檔的
  // companion ID；新建鍊成流程（寬畫面卡片）傳 false 隱藏，Stepper Step 5
  // （編輯模式）維持顯示。
  Widget _buildVoiceSettingsFields({bool showAdvancedEntry = true}) {
    final ds = BridgeDSColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── [小葵 2026-09-24 出道令] 匯入門：外部音色 / 音檔直接放入 ──
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: OutlinedButton.icon(
            onPressed: _importExternalVoice,
            icon: const Icon(Icons.library_music_outlined, size: 20),
            label: const Text('匯入外部音色 / 音檔'),
          ),
        ),
        // ── 聲音選擇下拉 ──
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DropdownButtonFormField<String>(
            // [小葵 2026-09-24 出道令修] companion.voiceName 可能是外部音色
            // （例：xiaokui_video_voice＝MiniMax 克隆音色），不在 Kokoro 清單內——
            // 直接當 initialValue 會 assert 炸紅屏。顯示 fallback 到 null，
            // _voiceName 仍保留原值（儲存時照存，不會丟失音色偏好）。
            initialValue: kokoroChineseVoices.any((v) => v.id == _voiceName)
                ? _voiceName
                : null,
            hint: kokoroChineseVoices.any((v) => v.id == _voiceName)
                ? null
                : Text(
                    '$_voiceName（外部音色）',
                    style: tierBasedStyle(
                      context,
                      Tier.blockSubheading,
                      color: BridgeDSColors.of(context).textSecondary,
                    ),
                  ),
            decoration: InputDecoration(
              labelText: '聲音選擇',
              labelStyle: tierBasedStyle(
                context,
                Tier.blockSubheading,
                color: BridgeDSColors.of(context).textSecondary,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 10),
              filled: true,
              fillColor:
                  ds.surface, // [教練 Agent 2026-08-03] R1: 修 textPrimary 誤用為背景
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                borderSide: BorderSide(
                  color: BridgeDSColors.of(context).borderSubtle,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                borderSide: BorderSide(
                  color: BridgeDSColors.of(context).borderSubtle,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                borderSide: BorderSide(
                  color: BridgeDSColors.of(context).accentBlue,
                  width: 1.4,
                ),
              ),
            ),
            items: kokoroChineseVoices.map((voice) {
              final genderLabel = voice.gender == 'female' ? '女聲' : '男聲';
              return DropdownMenuItem(
                value: voice.id,
                child: Text('${voice.name} — $genderLabel'),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _voiceName = value);
              }
            },
          ),
        ),

        // ── 語速滑桿 ──
        _buildVoiceSliderTile(
          icon: Icons.speed,
          title: '語速',
          valueLabel: '${_voiceSpeed.toStringAsFixed(1)}×',
          value: _voiceSpeed,
          min: 0.5,
          max: 2.0,
          divisions: 15,
          onChanged: (value) => setState(() => _voiceSpeed = value),
        ),
        const SizedBox(height: 16),

        // ── 情緒表達開關 ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: ds.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: ds.borderSubtle),
          ),
          child: Row(
            children: [
              Icon(
                Icons.mood_outlined,
                size: 20,
                color: BridgeDSColors.of(context).accentBlue,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '情緒表達',
                      style: tierBasedStyle(
                        context,
                        Tier.cardTitle,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '讓夥伴的語音帶有情緒起伏',
                      style: TierStyle.of(
                        context,
                        Tier.cardCaption,
                      ).toTextStyle().copyWith(color: ds.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _emotionEnabled,
                onChanged: (value) => setState(() => _emotionEnabled = value),
                activeThumbColor: BridgeDSColors.of(context).accentBlue,
              ),
            ],
          ),
        ),

        // ── 情緒敏感度滑桿（只在情緒開啟時顯示）──
        if (_emotionEnabled) ...[
          const SizedBox(height: 12),
          _buildVoiceSliderTile(
            icon: Icons.tune,
            title: '情緒敏感度',
            valueLabel: '${(_emotionSensitivity * 100).round()}%',
            value: _emotionSensitivity,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            onChanged: (value) => setState(() => _emotionSensitivity = value),
          ),
        ],

        const SizedBox(height: 20),

        // ── 測試播放按鈕 ──
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isTestingVoice ? null : _testVoicePlayback,
            icon: _isTestingVoice
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_circle_fill),
            label: Text(
              _isTestingVoice ? '播放中...' : '測試播放',
              style: tierBasedStyle(
                context,
                Tier.cardTitle,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: BridgeDSColors.of(context).canvas,
              side: BorderSide(
                color: BridgeDSColors.of(context).accentPurple,
                width: 1.5,
              ),
              foregroundColor: ds.textPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        // [教練 Agent 2026-08-03] C5: 進階語音設定入口（混合聲音、情緒清單、進階選項）
        // [小葵 2026-08-30] showAdvancedEntry=false（新建鍊成中）時隱藏 —
        // 該入口需要已存檔的 companion ID，新建流程中是死路按鈕。
        if (showAdvancedEntry) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                // [教練 Agent 2026-08-03] C5: 跳到完整語音設定頁
                // 注意：要在 companion 已存檔後才能跳（需要 ID）
                final id = _editingCompanion?.id;
                if (id == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('請先儲存夥伴後再開啟語音設定')),
                  );
                  return;
                }
                // [小葵 2026-09-08] 不帶 returnTo——push 進來的頁面，返回就該 pop 回這裡。
                // 帶 returnTo 會讓返回 go() 跳去控制中心（獨立全屏頁，使用者回不了原頁）。
                context.push('/companion/voice?id=$id');
              },
              icon: const Icon(Icons.tune),
              label: const Text('進階語音設定（混合聲音 / 情緒清單）'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 語音設定專用的滑桿欄位元件
  Widget _buildVoiceSliderTile({
    required IconData icon,
    required String title,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final ds = BridgeDSColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: ds.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: BridgeDSColors.of(context).accentBlue,
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: tierBasedStyle(
                  context,
                  Tier.cardTitle,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                valueLabel,
                style: tierBasedStyle(
                  context,
                  Tier.cardCaptionBold,
                  color: ds.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: BridgeDSColors.of(context).accentBlue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  /// 測試播放語音 — 呼叫 KokoroTtsService 合成並播放
  /// [小葵 2026-08-30] 真正接上 NativeAudioBytesPlayer 播放（原本只顯示
  /// SnackBar 不出聲=UI殼）+ server 冷啟動時顯示「啟動中」進度提示。
  Future<void> _testVoicePlayback() async {
    setState(() => _isTestingVoice = true);
    try {
      // 確保 server 已啟動
      if (!_kokoroTtsService.isRunning) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎙 語音引擎啟動中（首次約需數秒）…'),
              duration: Duration(seconds: 10),
            ),
          );
        }
        final started = await _kokoroTtsService.startServer();
        if (!started) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '❌ Kokoro server 啟動失敗：${_kokoroTtsService.lastError}',
                ),
              ),
            );
          }
          return;
        }
      }

      // 合成語音
      final result = await _kokoroTtsService.synthesize(
        KokoroTtsRequest(
          text: '你好，我是你的夥伴，很高興見到你！',
          voice: _voiceName,
          speed: _voiceSpeed,
          emotion: _emotionEnabled ? 'amused' : null,
          emotionSensitivity: _emotionSensitivity,
        ),
      );

      // [小葵 2026-08-30] 真正播放——接 NativeAudioBytesPlayer
      // （與三個聊天 UI 的 onPlayAudioBytes 同一播放器）
      await _testVoicePlayer.play(result.audioBytes);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('✅ 播放完成，聲音：$_voiceName')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('語音測試失敗：$error')));
      }
    } finally {
      if (mounted) setState(() => _isTestingVoice = false);
    }
  }

  Widget _buildReferenceImagePicker() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(
          color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(
                    context,
                  ).accentBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_photo_alternate_outlined,
                  color: BridgeDSColors.of(context).accentBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '參考圖檔線索',
                      style: tierBasedStyle(
                        context,
                        Tier.blockSubheading,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 0),
                    // [教練 Agent 2026-08-05 Step 3b] 用 textPrimary（深色）取代 textSecondary
                    // light theme 下即使是 dark textSecondary 在小字 (12) 看起來還是糊
                    Text(
                      '上傳既有角色、畫風或符號圖片，生成時會把它們當作 visual reference。',
                      style: TierStyle.of(
                        context,
                        Tier.cardCaptionBold,
                      ).toTextStyle().copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickReferenceImages,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('上傳圖檔'),
              ),
            ],
          ),
          if (_referenceImages.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _referenceImages.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final image = _referenceImages[index];
                  return _buildReferenceImageTile(image);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImportPackEntryPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: BridgeDSColors.of(
                context,
              ).accentBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.move_to_inbox_outlined,
              color: BridgeDSColors.of(context).accentBlue,
              size: 19,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已有角色資產包？',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tierBasedStyle(
                    context,
                    Tier.blockSubheading,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 0),
                // [教練 Agent 2026-08-05 Step 3b] 用 textPrimary（深色）取代 textSecondary
                Text(
                  '先匯入社群分享或之前儲存的角色包，再繼續微調線索、圖片與設定。',
                  style: TierStyle.of(
                    context,
                    Tier.cardCaptionBold,
                  ).toTextStyle().copyWith(height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildImportPackButton(),
        ],
      ),
    );
  }

  Widget _buildReferenceImageTile(_ReferenceClueImage image) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            child: SizedBox(
              width: 64,
              height: 64,
              child: _buildGeneratedImage(image.value),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  image.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.numericEmphasis)
                      .toTextStyle()
                      .copyWith(
                        color: BridgeDSColors.of(context).textPrimary,
                        height: 1.2,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  image.sourceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.cardCaptionBold)
                      .toTextStyle()
                      .copyWith(
                        color: BridgeDSColors.of(context).textMuted,
                        fontSize: 14,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '移除參考圖',
            onPressed: () => _removeReferenceImage(image.id),
            icon: const Icon(
              Icons.close,
              size: 20,
            ), // [P3-4 修復 2026-06-30] 18→20
            color: BridgeDSColors.of(context).textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
  }) {
    final colors = BridgeDSColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: TierStyle.of(
          context,
          Tier.formInput,
        ).toTextStyle().copyWith(fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: colors.textMuted, fontSize: 14),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: TierStyle.of(
            context,
            Tier.formLabel,
          ).toTextStyle().copyWith(fontWeight: FontWeight.w800),
          // [教練 Agent 2026-08-10] 關鍵：floatingLabelStyle 讓 label 在 always 模式下保持 16px 不被縮小
          floatingLabelStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 10),
          filled: true,
          fillColor: colors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            borderSide: BorderSide(color: colors.accentBlue.withOpacity(0.18)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            borderSide: BorderSide(color: colors.accentBlue.withOpacity(0.18)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            borderSide: BorderSide(color: colors.accentBlue, width: 1.4),
          ),
        ),
        // [教練 Agent 2026-08-14] 修復：編輯模式下改文字不清掉 candidate
        // 舊邏輯：任何文字欄位一改就 _candidate = null → 右側形象圖+資料+存檔全部消失
        // 新邏輯：只在「新建模式」清 candidate；編輯模式保留舊 candidate 讓用戶繼續看到形象圖
        onChanged: (_) {
          if (_editingCompanion != null) return; // 編輯模式：不清 candidate
          setState(() {
            _candidate = null;
            _generatingSheetKeys.clear();
            _candidatePackSaved = false;
            _primaryVisualReview = null;
            _primaryRightsPassport = null;
            _isReviewingPrimaryImage = false;
          });
        },
      ),
    );
  }

  Widget _buildRitualActions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildRandomizeButton()),
            const SizedBox(width: 8),
            Expanded(child: _buildSummonCandidateButton()),
          ],
        ),
      ],
    );
  }

  Widget _buildWideRitualActions() {
    return Row(
      children: [
        Expanded(child: _buildRandomizeButton()),
        const SizedBox(width: AppTheme.spacingM),
        Expanded(child: _buildSummonCandidateButton()),
      ],
    );
  }

  Widget _buildRandomizeButton() {
    return OutlinedButton.icon(
      onPressed: _randomizeClues,
      icon: const Icon(Icons.casino_outlined),
      label: const Text('隨機給我點子'),
    );
  }

  Widget _buildSummonCandidateButton() {
    return FilledButton.icon(
      onPressed: _isSummoning ? null : _summonCandidate,
      icon: _isSummoning
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_awesome),
      label: Text(_isSummoning ? '生成中...' : '預覽草稿'),
    );
  }

  Widget _buildImportPackButton() {
    return OutlinedButton.icon(
      onPressed: _showImportPackOptions,
      icon: const Icon(Icons.move_to_inbox_outlined),
      label: const Text('匯入角色資產包'),
    );
  }

  Widget _buildCandidateCard(CompanionSummoningCandidate candidate) {
    final mbti =
        MBTIType.fromCode(candidate.mbtiCode) ?? MBTIType.allTypes.first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(
          color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: BridgeDSColors.of(
              context,
            ).accentBlue.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _buildCandidateVisual(candidate)),
          if (candidate.visualGenerationMessage != null) ...[
            const SizedBox(height: 8),
            _buildVisualGenerationStatus(candidate),
          ],
          if (candidate.generatedImagePath?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            _buildPrimaryReviewStatus(),
          ],
          const SizedBox(height: 16),
          Text(
            candidate.name,
            style: tierBasedStyle(
              context,
              Tier.appTitle,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${mbti.code} ${mbti.name} · ${candidate.role.name}',
            style: TierStyle.of(context, Tier.listItemSubtitle).toTextStyle(),
          ),
          const SizedBox(height: 16),
          // [教練 Agent 2026-08-14] 改 SelectableText — 讓使用者可以選取複製角色描述
          SelectableText(
            candidate.appearanceDescription,
            style: TierStyle.of(
              context,
              Tier.listItemSubtitle,
            ).toTextStyle().copyWith(height: 1.4),
          ),
          const SizedBox(height: 16),
          // [教練 Agent 2026-08-05 Phase E+ 編輯模式搬移] 圖像版本/模型品質選擇器移到右側「重新生成」按鈕之上（自 _buildSummonForm 移入）
          _buildImageModelSelector(),
          const SizedBox(height: 16),
          // [教練 Agent 2026-08-05 Phase E+ 編輯模式隱藏] 右側「建立任務進度」進度板 — 編輯模式不需要建立嚮導
          Visibility(
            visible: _editingCompanion == null,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: false,
            child: _buildCandidateFlowGuide(candidate),
          ),
          const SizedBox(height: 16),
          // [小葵 2026-09-14] 單獨重生主形象——保留骨架只換圖（Blue 要求）
          // [Blue UX 2026-09-17] 無圖時更要顯示——匯入夥伴沒主形象時這是唯一
          // 逃生門（有圖才給按鈕＝雞生蛋死鎖：沒圖→不能生成→永遠沒圖）
          // [Blue UX 2026-09-17] 生成中：按鈕顯示旋轉＋文字，下方加進度條
          // （寬畫面版原本完全沒有進度回饋，Blue 按下去後不知發生什麼事）
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSummoning ? null : _rerollPrimaryImageOnly,
              icon: _isSummoning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image_search, size: 16),
              label: Text(_isSummoning
                  ? '主形象生成中…'
                  : candidate.generatedImagePath?.trim().isNotEmpty == true
                  ? '重新生成主形象'
                  : '生成主形象'),
            ),
          ),
          const SizedBox(height: 8),
          // [小葵 2026-09-24 出道令] 匯入門——不經生成器直接放圖/影片
          _buildImportVisualButton(),
          // [Blue UX 2026-09-17] 生成中的即時階段進度（發送請求→等待→去背→完成）
          if (_isSummoning) ...[
            const SizedBox(height: 8),
            _buildSummonProgressBar(),
          ],
          const SizedBox(height: 8),
          // [Blue UX 2026-09-17] 桌面寬畫面版補「一次生成全部狀態圖」——此按鈕
          // 原本只存在於窄畫面 Stepper Step 4，桌面 App 永遠走寬畫面版（≥920px）
          // 導致 Blue 找不到按鈕。此鈕只生成狀態圖、不動主形象（主形象用上方
          // 「重新生成主形象」單獨換）。需先有主形象（母版）。
          if (candidate.generatedImagePath?.trim().isNotEmpty == true) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _generatingSheetKeys.isNotEmpty
                    ? null
                    : () => _generateAllSheetImages(candidate),
                icon: _generatingSheetKeys.isNotEmpty
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_motion),
                label: Text(_generatingSheetKeys.isNotEmpty
                    ? '狀態圖生成中'
                    : '一次生成全部狀態圖'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          // [教練 Agent 2026-06-30] 狀態圖組和資產包移到獨立步驟，不再顯示在候選卡片裡
          _buildAssetManifestPreview(candidate),
          const SizedBox(height: 8),
          // [Blue UX 2026-09-17] 移除「調整線索」——它會把候選形象整個丟棄
          // （_candidate=null），使用者以為只是微調文字，結果右側全收空卡。
          // 文字線索直接改左側欄位即可（即時生效，無須丟棄候選）；
          // 換圖用「重新生成主形象」。無不可取代功能 → 刪。
        ],
      ),
    );
  }

  Widget _buildPackActionPanel(CompanionSummoningCandidate candidate) {
    final generatedCount = _sheetStates
        .where(
          (state) =>
              candidate.generatedSheetImagePaths[state.key]
                  ?.trim()
                  .isNotEmpty ==
              true,
        )
        .length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: BridgeDSColors.of(
            context,
          ).accentYellow.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 18,
                color: BridgeDSColors.of(context).accentBlue,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '角色資產包',
                  style: tierBasedStyle(
                    context,
                    Tier.listItemTitle,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 0),
          Text(
            '角色資產包會保存主形象、狀態圖、觸發規則與角色 manifest，方便日後匯入微調或分享給社群。動態插件接口會保留在資料格式中，前端暫不開放設定。',
            style: TierStyle.of(context, Tier.cardCaptionBold)
                .toTextStyle()
                .copyWith(
                  color: BridgeDSColors.of(context).textSecondary,
                  fontSize: 10,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            generatedCount == 0
                ? '可以先儲存目前線索與狀態規則；等圖組生成後再儲存，會包含更多角色圖片。'
                : '目前已包含 $generatedCount 張狀態圖、觸發規則與角色 manifest，可匯出給社群分享或日後匯入微調。',
            style: TierStyle.of(context, Tier.cardCaptionBold)
                .toTextStyle()
                .copyWith(
                  color: BridgeDSColors.of(context).textSecondary,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _exportCandidatePack(candidate),
                  icon: const Icon(Icons.ios_share_outlined),
                  label: const Text('匯出資產包檔案'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateFlowGuide(CompanionSummoningCandidate candidate) {
    return _buildSummonQuestBoard(candidate: candidate, elevated: true);
  }

  Widget _buildSummonQuestBoard({
    required CompanionSummoningCandidate? candidate,
    bool elevated = false,
  }) {
    final hasPrimaryImage =
        candidate?.generatedImagePath?.trim().isNotEmpty == true;
    final generatedCount = candidate == null
        ? 0
        : _sheetStates
              .where(
                (state) =>
                    candidate.generatedSheetImagePaths[state.key]
                        ?.trim()
                        .isNotEmpty ==
                    true,
              )
              .length;
    final totalStates = _sheetStates.length;
    final allStatesGenerated = totalStates > 0 && generatedCount >= totalStates;
    final packReady =
        _candidatePackSaved && hasPrimaryImage && allStatesGenerated;
    final summonReady = hasPrimaryImage && allStatesGenerated && packReady;
    final activeIndex = !hasPrimaryImage
        ? 0
        : !allStatesGenerated
        ? 1
        : !packReady
        ? 2
        : 3;
    final steps = [
      _SummonQuestStep(
        icon: Icons.auto_awesome_outlined,
        title: '主形象',
        detail: hasPrimaryImage ? '主形象已生成。' : '填好描述後按「預覽草稿」。',
        done: hasPrimaryImage,
        active: activeIndex == 0,
      ),
      _SummonQuestStep(
        icon: Icons.auto_awesome_motion,
        title: '狀態圖組',
        detail: allStatesGenerated
            ? '$generatedCount/$totalStates 張已完成。'
            : '生成待機、閱讀、指路等狀態圖：$generatedCount/$totalStates。',
        done: allStatesGenerated,
        active: activeIndex == 1,
      ),
      _SummonQuestStep(
        icon: Icons.inventory_2_outlined,
        title: '資產包',
        detail: packReady ? '資產包已儲存或匯出。' : '封存文字、主圖與狀態圖。',
        done: packReady,
        active: activeIndex == 2,
      ),
      _SummonQuestStep(
        icon: Icons.check_circle_outline,
        title: '確定建立夥伴',
        detail: summonReady ? '可以正式加入夥伴館。' : '完成前面任務後再定稿。',
        done: false,
        active: activeIndex == 3,
      ),
    ];
    final next = steps[activeIndex];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: elevated
            ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.07)
            : BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(
          color: BridgeDSColors.of(
            context,
          ).accentBlue.withValues(alpha: elevated ? 0.24 : 0.18),
        ),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: BridgeDSColors.of(
                    context,
                  ).accentBlue.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(
                    context,
                  ).accentYellow.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.flag_outlined,
                  color: BridgeDSColors.of(context).accentBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '建立任務進度',
                      style: tierBasedStyle(
                        context,
                        Tier.blockSubheading,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 0),
                    Text(
                      '目前第 ${activeIndex + 1} / ${steps.length} 步。下一步：${next.title}',
                      style: TierStyle.of(context, Tier.cardCaptionBold)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              _QuestProgressBadge(label: '${activeIndex + 1}/${steps.length}'),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 620;
              if (!wide) {
                return Column(
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      _SummonQuestStepTile(index: i + 1, step: steps[i]),
                      if (i < steps.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < steps.length; i++) ...[
                    Expanded(
                      child: _SummonQuestStepTile(
                        index: i + 1,
                        step: steps[i],
                        compact: true,
                      ),
                    ),
                    if (i < steps.length - 1)
                      Container(
                        width: 18,
                        height: 42,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.chevron_right,
                          size: 17,
                          color: steps[i].done
                              ? BridgeDSColors.of(context).accentBlue
                              : BridgeDSColors.of(context).borderSubtle,
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: BridgeDSColors.of(
                context,
              ).accentYellow.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(
                color: BridgeDSColors.of(
                  context,
                ).accentYellow.withValues(alpha: 0.24),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  next.icon,
                  color: BridgeDSColors.of(context).accentBlue,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    next.detail,
                    style: TierStyle.of(
                      context,
                      Tier.cardCaptionBold,
                    ).toTextStyle().copyWith(height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateVisual(CompanionSummoningCandidate candidate) {
    final imagePath = candidate.generatedImagePath;
    if (imagePath == null || imagePath.trim().isEmpty) {
      return CompanionArt(
        mbtiCode: candidate.mbtiCode,
        seed: candidate.seed,
        name: candidate.name,
        mood: AgentCompanionMood.curious,
        action: AgentCompanionAction.wandering,
        size: 240,
      );
    }

    // [教練 Agent 2026-08-12] 主圖包進 GestureDetector，點擊放大預覽
    return GestureDetector(
      onTap: () => _showStateImageDialog(imagePath, '主形象 · ${candidate.name}'),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).canvas,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(
            color: BridgeDSColors.of(
              context,
            ).accentBlue.withValues(alpha: 0.18),
          ),
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final previewSize = math.min(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              return Center(
                // [小葵 2026-09-13] 主形象呼吸感——預覽即活的
                child: BreathingImage(
  anchor: const Alignment(0, 0.15),  // 胸口呼吸
                  child: SizedBox.square(
                    dimension: previewSize,
                    child: _buildGeneratedImage(imagePath),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGeneratedImage(String imagePath, {BoxFit fit = BoxFit.contain}) {
    if (imagePath.startsWith('http')) {
      return Image.network(imagePath, fit: fit);
    }
    if (imagePath.startsWith('data:image/')) {
      try {
        final commaIndex = imagePath.indexOf(',');
        final payload = commaIndex == -1
            ? imagePath
            : imagePath.substring(commaIndex + 1);
        return Image.memory(base64Decode(payload), fit: fit);
      } catch (_) {
        return Container(
          // [教練 Agent 2026-08-05 Step 3a] 寫死改成 context 動態查
          color: BridgeDSColors.of(context).surface,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: Text(
            '圖片資料無法讀取，請重新匯入或重新生成。',
            textAlign: TextAlign.center,
            style: TierStyle.of(context, Tier.cardCaption).toTextStyle(),
          ),
        );
      }
    }
    if (kIsWeb) {
      return Container(
        color: AppTheme.surfaceHighlight,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Text(
          '圖片已生成，但開發預覽環境無法直接讀取本機檔案。請在桌面 APP 查看。',
          textAlign: TextAlign.center,
          style: TierStyle.of(context, Tier.cardCaption).toTextStyle(),
        ),
      );
    }
    return Image.file(File(imagePath), fit: fit);
  }

  Widget _buildVisualGenerationStatus(CompanionSummoningCandidate candidate) {
    final generated = candidate.generatedImagePath != null;
    final color = generated
        ? BridgeDSColors.of(context).accentBlue
        : BridgeDSColors.of(context).accentYellow;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(
            generated ? Icons.image_outlined : Icons.info_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              generated
                  ? '已使用圖片生成能力建立候選形象。'
                  : candidate.visualGenerationMessage!,
              style: TierStyle.of(context, Tier.cardCaptionBold)
                  .toTextStyle()
                  .copyWith(
                    color: BridgeDSColors.of(context).textSecondary,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryReviewStatus() {
    final review = _primaryVisualReview;
    final signal = _primaryRightsPassport?.signal;
    final candidate = _candidate;
    final canReview =
        candidate?.generatedImagePath?.trim().isNotEmpty == true &&
        !_isReviewingPrimaryImage;
    final color = _isReviewingPrimaryImage
        ? BridgeDSColors.of(context).accentBlue
        : switch (signal) {
            CompanionRightsSignal.approved => BridgeDSColors.of(
              context,
            ).accentGreen,
            CompanionRightsSignal.watching => BridgeDSColors.of(
              context,
            ).accentYellow,
            CompanionRightsSignal.blocked => BridgeDSColors.of(
              context,
            ).accentRed,
            _ => BridgeDSColors.of(context).textSecondary,
          };
    final title = _isReviewingPrimaryImage
        ? '主形象第一輪預審中'
        : _primaryRightsPassport?.shortLabel ?? '主形象尚未完成預審';
    final detail = _isReviewingPrimaryImage
        ? '正在檢查主形象是否有成人、暴力、Logo、官方混淆或明顯 IP 風險。'
        : review == null
        ? signal == CompanionRightsSignal.unreviewed
              ? '這個角色資產包尚未產生第一輪圖片預審。請先預審主形象，再繼續狀態圖組。'
              : '主形象生成後會先做第一輪圖片預檢，再繼續狀態圖組。'
        : [
            '已檢查 ${review.inspectedImageCount} 張主形象圖片。',
            if (review.blockedChecks.isNotEmpty)
              '封鎖：${review.blockedChecks.first}'
            else if (review.warningChecks.isNotEmpty)
              '提醒：${review.warningChecks.first}'
            else
              '後續狀態圖組請以這張通過預檢的主形象作為安全母版。',
          ].join(' ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isReviewingPrimaryImage)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              switch (signal) {
                CompanionRightsSignal.approved => Icons.verified_user_outlined,
                CompanionRightsSignal.watching => Icons.warning_amber_outlined,
                CompanionRightsSignal.blocked => Icons.block_outlined,
                _ => Icons.shield_outlined,
              },
              color: color,
              size: 18,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TierStyle.of(
                    context,
                    Tier.numericEmphasis,
                  ).toTextStyle().copyWith(color: color),
                ),
                const SizedBox(height: 0),
                Text(
                  detail,
                  style: TierStyle.of(context, Tier.cardCaptionBold)
                      .toTextStyle()
                      .copyWith(
                        color: BridgeDSColors.of(context).textSecondary,
                        height: 1.35,
                      ),
                ),
                if (review != null && review.warningChecks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...review.warningChecks.map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(top: 0),
                      child: Text(
                        '• $w',
                        style: TierStyle.of(context, Tier.cardCaptionBold)
                            .toTextStyle()
                            .copyWith(
                              color: BridgeDSColors.of(context).accentYellow,
                              height: 1.3,
                            ),
                      ),
                    ),
                  ),
                ],
                if (review != null && review.blockedChecks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...review.blockedChecks.map(
                    (b) => Padding(
                      padding: const EdgeInsets.only(top: 0),
                      child: Text(
                        '⛔ $b',
                        style: TierStyle.of(context, Tier.cardCaptionBold)
                            .toTextStyle()
                            .copyWith(
                              color: BridgeDSColors.of(context).accentRed,
                              height: 1.3,
                            ),
                      ),
                    ),
                  ),
                ],
                if (review != null &&
                    !review.deepContentReviewRan &&
                    review.infoNotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'ℹ️ ${review.infoNotes.first}',
                    style: TierStyle.of(context, Tier.cardCaptionBold)
                        .toTextStyle()
                        .copyWith(
                          fontSize: 10.5,
                          color: BridgeDSColors.of(context).textSecondary,
                          height: 1.35,
                        ),
                  ),
                ],
                if (canReview) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => _reviewPrimaryCandidateImage(candidate!),
                      icon: const Icon(Icons.fact_check_outlined, size: 17),
                      label: Text(
                        signal == null ||
                                signal == CompanionRightsSignal.unreviewed
                            ? '立即預審主形象'
                            : '重新預審主形象',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetPreview(CompanionSummoningCandidate candidate) {
    final poses = _sheetStates;
    final generatedCount = poses
        .where(
          (pose) =>
              candidate.generatedSheetImagePaths[pose.key]?.trim().isNotEmpty ==
              true,
        )
        .length;
    final isGeneratingAny = _generatingSheetKeys.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '角色造型圖組',
                  style: tierBasedStyle(
                    context,
                    Tier.blockSubheading,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$generatedCount 圖',
                style: TierStyle.of(context, Tier.numericEmphasis)
                    .toTextStyle()
                    .copyWith(color: BridgeDSColors.of(context).accentBlue),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '依照上方候選形象，延展成桌面夥伴工作時會用到的透明背景狀態圖。',
            style: TierStyle.of(
              context,
              Tier.cardCaption,
            ).toTextStyle().copyWith(height: 1.35),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: isGeneratingAny
                      ? null
                      : () => _generateAllSheetImages(candidate),
                  icon: isGeneratingAny
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_motion),
                  label: Text(isGeneratingAny ? '狀態圖生成中' : '一次生成全部狀態圖'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addSheetState,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('新增狀態圖'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: BridgeDSColors.of(
                context,
              ).accentBlue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(
                color: BridgeDSColors.of(
                  context,
                ).accentBlue.withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.layers_clear_outlined,
                  size: 17,
                  color: BridgeDSColors.of(context).accentBlue,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '所有狀態圖都會以 PNG 透明背景生成，方便未來桌面夥伴直接浮在螢幕上。',
                    style: TierStyle.of(context, Tier.cardCaptionBold)
                        .toTextStyle()
                        .copyWith(
                          color: BridgeDSColors.of(context).textSecondary,
                          height: 1.35,
                        ),
                  ),
                ),
              ],
            ),
          ),
          // [教練 Agent 2026-07-01] 生成中進度條 + 防休眠提示
          if (isGeneratingAny) ...[
            SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: poses.isEmpty ? 0 : generatedCount / poses.length,
                backgroundColor: BridgeDSColors.of(context).borderSubtle,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '生成進度：$generatedCount / ${poses.length} 張',
              style: TierStyle.of(context, Tier.cardCaptionBold)
                  .toTextStyle()
                  .copyWith(color: BridgeDSColors.of(context).textSecondary),
            ),
            SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(
                  context,
                ).accentYellow.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: BridgeDSColors.of(
                    context,
                  ).accentYellow.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.phone_android,
                    size: 16,
                    color: BridgeDSColors.of(context).accentYellow,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '正在並行生成狀態圖，請保持螢幕開啟。\n不要讓手機休眠或切換應用程式，以免中斷。',
                      style: TierStyle.of(
                        context,
                        Tier.statusWarning,
                      ).toTextStyle().copyWith(height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              // [教練 Agent 2026-06-30] 2 列，卡片更大更好預覽
              const crossAxisCount = 2;
              const spacing = 4.0; // [教練 Agent 2026-06-30] 8→4 減少間距讓圖更大
              final itemWidth =
                  (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                  crossAxisCount;
              // [教練 Agent 2026-06-29] 用 Wrap 取代 GridView，展開欄位時卡片可自由長高不溢出
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: List.generate(poses.length, (index) {
                  final pose = poses[index];
                  return SizedBox(
                    width: itemWidth,
                    child: _buildSheetPoseTile(candidate, pose, index),
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            generatedCount == poses.length
                ? '狀態圖已完成；未來動態插件會沿用這些狀態與觸發規則。'
                : '可以逐張調整狀態名稱、行為內容、表情、出現時機與觸發關鍵字，再生成或重生每一張。',
            style: TierStyle.of(
              context,
              Tier.cardCaption,
            ).toTextStyle().copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetPoseTile(
    CompanionSummoningCandidate candidate,
    _SheetPose pose,
    int index,
  ) {
    final imagePath = candidate.generatedSheetImagePaths[pose.key];
    final message = candidate.sheetGenerationMessages[pose.key];
    final isGenerated = imagePath != null && imagePath.trim().isNotEmpty;
    final isGenerating = _generatingSheetKeys.contains(pose.key);
    final isProblemMessage =
        message != null &&
        (message.contains('失敗') ||
            message.contains('尚未完成') ||
            message.contains('逾時'));

    final isExpanded = _expandedSheetKeys.contains(pose.key);

    return Container(
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: isGenerated
              ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.34)
              : BridgeDSColors.of(context).borderSubtle,
        ),
      ),
      child: Column(
        children: [
          // ── 圖片區（固定 1:1 比例，不展開時卡片精簡）──
          // [教練 Agent 2026-06-30] 減少 padding 讓圖片更大
          AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 圖片或佔位圖
                ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppTheme.radiusMedium),
                  ),
                  child: isGenerated
                      ? GestureDetector(
                          onTap: () => _showFullScreenImage(
                            context,
                            imagePath,
                            candidate,
                            pose,
                          ),
                          child: _buildGeneratedImage(imagePath),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final size = math.min(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );
                            return Center(
                              child: CompanionArt(
                                mbtiCode: candidate.mbtiCode,
                                seed: candidate.seed + (index * 97),
                                name: candidate.name,
                                mood: pose.mood,
                                action: pose.action,
                                size: size,
                                framed: false,
                              ),
                            );
                          },
                        ),
                ),
                // 底部漸層浮層：狀態名 + 生成按鈕
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          BridgeDSColors.of(
                            context,
                          ).surface.withValues(alpha: 0.6),
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        // [教練 Agent 2026-06-30] 按鈕順序：調整(左) → 狀態名(中) → 生成(右)
                        // 編輯展開按鈕 [P1-8 修復 2026-06-30] 觸控區加大 30→44
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedSheetKeys.remove(pose.key);
                              } else {
                                _expandedSheetKeys.add(pose.key);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: BridgeDSColors.of(
                                context,
                              ).textPrimary.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isExpanded ? Icons.keyboard_arrow_up : Icons.tune,
                              size: 22,
                              color: BridgeDSColors.of(context).textPrimary,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        // [教練 Agent 2026-07-01] 狀態符號旁加文字簡稱，確保被看見
                        Icon(
                          pose.icon,
                          size: 18,
                          color: BridgeDSColors.of(context).textPrimary,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pose.label,
                            style: tierBasedStyle(
                              context,
                              Tier.cardTitle,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 8),
                        // 生成/重生按鈕 [P1-8 修復 2026-06-30] 觸控區加大
                        GestureDetector(
                          onTap: isGenerating
                              ? null
                              : () => _generateSheetImage(candidate, pose),
                          child: Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: BridgeDSColors.of(
                                context,
                              ).textPrimary.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                            child: isGenerating
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: BridgeDSColors.of(
                                        context,
                                      ).textPrimary,
                                    ),
                                  )
                                : Icon(
                                    isGenerated
                                        ? Icons.refresh
                                        : Icons.add_photo_alternate_outlined,
                                    size: 22,
                                    color: BridgeDSColors.of(
                                      context,
                                    ).textPrimary,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 錯誤訊息浮層
                if (message != null && (!isGenerated || isProblemMessage))
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 0,
                      ),
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: BridgeDSColors.of(
                          context,
                        ).accentRed.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TierStyle.of(
                          context,
                          Tier.numericEmphasis,
                        ).toTextStyle().copyWith(fontSize: 8),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ── 展開區：文字欄位（預設收合）──
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                    child: Column(
                      children: [
                        _buildSheetTextField(
                          fieldKey: '${pose.key}-label',
                          label: '狀態名稱',
                          value: pose.label,
                          onChanged: (value) => _updateSheetState(
                            pose.key,
                            (state) => state.copyWith(label: value),
                            rebuild: false,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildSheetTextField(
                          fieldKey: '${pose.key}-behavior',
                          label: '行為內容',
                          value: pose.behavior,
                          minLines: 2,
                          maxLines: 3,
                          onChanged: (value) => _updateSheetState(
                            pose.key,
                            (state) => state.copyWith(behavior: value),
                            rebuild: false,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildSheetTextField(
                          fieldKey: '${pose.key}-expression',
                          label: '表情敘述',
                          value: pose.expression,
                          minLines: 2,
                          maxLines: 3,
                          onChanged: (value) => _updateSheetState(
                            pose.key,
                            (state) => state.copyWith(expression: value),
                            rebuild: false,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildSheetTextField(
                          fieldKey: '${pose.key}-trigger-scene',
                          label: '出現時機',
                          value: pose.triggerScene,
                          minLines: 2,
                          maxLines: 3,
                          onChanged: (value) => _updateSheetState(
                            pose.key,
                            (state) => state.copyWith(triggerScene: value),
                            rebuild: false,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildSheetTextField(
                          fieldKey: '${pose.key}-trigger-keywords',
                          label: '觸發關鍵字',
                          value: pose.triggerKeywords.join('、'),
                          onChanged: (value) => _updateSheetState(
                            pose.key,
                            (state) => state.copyWith(
                              triggerKeywords: _splitTriggerInput(value),
                            ),
                            rebuild: false,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // [教練 Agent 2026-06-29] 問題4：全螢幕大圖查看 + 重新生成選項
  void _showFullScreenImage(
    BuildContext context,
    String imagePath,
    CompanionSummoningCandidate candidate,
    _SheetPose pose,
  ) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: BridgeDSColors.of(context).surface,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 頂部標題列
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Icon(
                    pose.icon,
                    color: BridgeDSColors.of(context).textSecondary,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pose.label,
                      style: tierBasedStyle(
                        context,
                        Tier.cardTitle,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: BridgeDSColors.of(context).textSecondary,
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            ),
            // 大圖
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: _buildGeneratedImage(imagePath),
                ),
              ),
            ),
            // 底部操作列
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _generateSheetImage(candidate, pose);
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重新生成'),
                    style: TextButton.styleFrom(
                      foregroundColor: BridgeDSColors.of(context).accentYellow,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('確認，繼續設定'),
                    style: TextButton.styleFrom(
                      foregroundColor: BridgeDSColors.of(context).accentGreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetTextField({
    required String fieldKey,
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return TextFormField(
      key: ValueKey(fieldKey),
      initialValue: value,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: onChanged,
      style: TierStyle.of(
        context,
        Tier.cardCaptionBold,
      ).toTextStyle().copyWith(height: 1.3),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: tierBasedStyle(
          context,
          Tier.cardCaptionBold,
          color: BridgeDSColors.of(context).textSecondary,
        ),
        floatingLabelStyle: TierStyle.of(
          context,
          Tier.numericEmphasis,
        ).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentBlue),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
        filled: true,
        fillColor: BridgeDSColors.of(context).canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide(
            color: BridgeDSColors.of(context).borderSubtle,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide(
            color: BridgeDSColors.of(context).borderSubtle,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide(color: BridgeDSColors.of(context).accentBlue),
        ),
      ),
    );
  }

  Widget _buildAssetManifestPreview(CompanionSummoningCandidate candidate) {
    final manifest = const CompanionAssetManifestService().buildManifest(
      companionId: 'preview_${candidate.seed}',
      name: candidate.name,
      mbtiCode: candidate.mbtiCode,
      seed: candidate.seed,
      appearancePrompt: candidate.appearancePrompt,
      appearanceDescription: candidate.appearanceDescription,
      characterSheetPrompts: candidate.characterSheetPrompts,
      assetStates: _assetStateSpecsForCandidate(candidate),
      primaryImagePath: candidate.generatedImagePath,
    );
    final states = (manifest['states'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();
    final includedAssets = (manifest['includedAssets'] as List<dynamic>)
        .whereType<String>()
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: BridgeDSColors.of(
                    context,
                  ).accentBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 16,
                  color: BridgeDSColors.of(context).accentBlue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '角色資產包 Manifest',
                  style: tierBasedStyle(
                    context,
                    Tier.blockSubheading,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${includedAssets.length} assets',
                style: TierStyle.of(context, Tier.numericEmphasis)
                    .toTextStyle()
                    .copyWith(
                      fontSize: 12,
                      color: BridgeDSColors.of(context).accentBlue,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildManifestChip('Engine', manifest['renderEngine'] as String),
              _buildManifestChip('Seed', '${candidate.seed}'),
              _buildManifestChip('Target', 'Desktop Companion'),
            ],
          ),
          const SizedBox(height: 8),
          // [教練 Agent 2026-08-12] 狀態圖預覽網格 — 4 欄 × 2 行 = 8 張 64×64 縮圖
          _buildManifestStateGrid(states),
          const SizedBox(height: 8),
          Text(
            '確定建立夥伴後，這份 manifest 會跟著 Companion Pack 匯出；核心狀態由桌面 runtime 保證呼叫，自訂狀態會依照觸發規則出現。',
            style: TierStyle.of(
              context,
              Tier.cardCaption,
            ).toTextStyle().copyWith(height: 1.35),
          ),
          const SizedBox(height: 12),
          // [教練 Agent 2026-08-12] 存檔 + 匯出按鈕排
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _confirmCandidate,
                  icon: const Icon(Icons.save, size: 18),
                  label: Text(
                    _editingCompanion == null ? '建立夥伴' : '存檔更新',
                    style: TierStyle.of(context, Tier.cardTitle).toTextStyle(),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: BridgeDSColors.of(context).canvas,
                    side: BorderSide(
                      color: BridgeDSColors.of(context).accentPurple,
                      width: 1.5,
                    ),
                    foregroundColor: BridgeDSColors.of(context).textPrimary,
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _exportCandidatePack(candidate),
                  icon: const Icon(Icons.archive_outlined, size: 18),
                  label: Text(
                    '匯出資產包',
                    style: TierStyle.of(context, Tier.cardTitle).toTextStyle(),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BridgeDSColors.of(context).textSecondary,
                    side: BorderSide(
                      color: BridgeDSColors.of(
                        context,
                      ).textSecondary.withValues(alpha: 0.3),
                    ),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManifestChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Text(
        '$label: $value',
        style: TierStyle.of(context, Tier.cardCaptionBold)
            .toTextStyle()
            .copyWith(
              fontSize: 10,
              color: BridgeDSColors.of(context).textSecondary,
            ),
      ),
    );
  }

  /// [教練 Agent 2026-08-12] 狀態圖預覽網格（manifest 內嵌）— 4 欄 × 2 行，縮圖填滿 cell 含中文標籤
  /// [教練 Agent 2026-08-12] 每張狀態圖右上角加「重新生成」按鈕
  Widget _buildManifestStateGrid(List<Map<String, dynamic>> states) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.85, // 寬:高 — 圖片接近正方形 + label
      children: [
        for (final state in states.take(8))
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // [教練 Agent 2026-08-12] 點擊放大預覽 + 重新生成按鈕
              Expanded(
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: () => _showStateImageDialog(
                        state['imagePath'] as String?,
                        '${state['label']}',
                      ),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: BridgeDSColors.of(context).surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: BridgeDSColors.of(context).borderSubtle,
                            width: 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: () {
                          final imagePath = state['imagePath'] as String?;
                          final hasImage =
                              imagePath != null &&
                              imagePath.trim().isNotEmpty &&
                              File(imagePath).existsSync();
                          if (hasImage) {
                            // [教練 Agent 2026-08-13] 改回 Image.file — 去背已在生成時完成
                            // 在 build 裡跑 BackgroundRemover 會卡 UI thread ~2s
                            return BreathingImage(
                              // [小葵 2026-09-13] 狀態圖呼吸感（胸口擴散）
                              anchor: const Alignment(0, 0.15),
                              child: Image.file(
                                File(imagePath),
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.broken_image_outlined,
                                  color: BridgeDSColors.of(context).textMuted,
                                ),
                              ),
                            );
                          }
                          return Icon(
                            Icons.image_outlined,
                            color: BridgeDSColors.of(
                              context,
                            ).textMuted.withValues(alpha: 0.4),
                          );
                        }(),
                      ),
                    ),
                    // [教練 Agent 2026-08-12] 右上角重新生成按鈕
                    Positioned(
                      top: 2,
                      right: 2,
                      child: _buildRegenerateButton(state),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${state['label']}',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(
                      fontSize: 11,
                      color: BridgeDSColors.of(context).textSecondary,
                    ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
      ],
    );
  }

  /// [教練 Agent 2026-08-12] 單張狀態圖重新生成按鈕
  Widget _buildRegenerateButton(Map<String, dynamic> state) {
    final stateId = state['stateId'] as String? ?? '';
    final isGenerating = _generatingSheetKeys.contains(stateId);
    final candidate = _candidate;

    if (isGenerating) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surface.withValues(alpha: 0.9),
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: BridgeDSColors.of(context).accentBlue,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: (candidate == null)
          ? null
          : () {
              final pose = _sheetStates
                  .where((s) => s.key == stateId)
                  .firstOrNull;
              if (pose != null) {
                _generateSheetImage(candidate, pose);
              }
            },
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surface.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          border: Border.all(
            color: BridgeDSColors.of(context).borderSubtle,
            width: 0.5,
          ),
        ),
        child: Icon(
          Icons.refresh,
          size: 14,
          color: BridgeDSColors.of(context).textSecondary,
        ),
      ),
    );
  }

  /// [教練 Agent 2026-08-12] 狀態圖點擊放大預覽 dialog
  void _showStateImageDialog(String? imagePath, String label) {
    if (imagePath == null ||
        imagePath.trim().isEmpty ||
        !File(imagePath).existsSync())
      return;
    showDialog(
      context: context,
      barrierColor: BridgeDSColors.of(context).surface.withValues(alpha: 0.85),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: GestureDetector(
          onTap: () => Navigator.pop(dialogContext),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(dialogContext).size.width * 0.8,
                  maxHeight: MediaQuery.of(dialogContext).size.height * 0.75,
                ),
                child: BreathingImage(
                  // [小葵 2026-09-13] 放大預覽也有呼吸（胸口擴散）
                  anchor: const Alignment(0, 0.15),
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TierStyle.of(context, Tier.blockHeading)
                    .toTextStyle()
                    .copyWith(color: BridgeDSColors.of(context).textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                '點任意處關閉',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: BridgeDSColors.of(context).textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [教練 Agent 2026-08-12] 狀態圖縮圖（manifest 內嵌預覽）
  Widget _buildManifestStateThumb(String? imagePath, {double size = 40}) {
    final hasImage =
        imagePath != null &&
        imagePath.trim().isNotEmpty &&
        File(imagePath).existsSync();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: BridgeDSColors.of(context).borderSubtle,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasImage
          ? Image.file(
              File(imagePath),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Icon(
                Icons.broken_image_outlined,
                size: size * 0.4,
                color: BridgeDSColors.of(context).textMuted,
              ),
            )
          : Icon(
              Icons.image_outlined,
              size: size * 0.4,
              color: BridgeDSColors.of(
                context,
              ).textMuted.withValues(alpha: 0.4),
            ),
    );
  }

  CompanionSummoningClues _readClues() {
    return CompanionSummoningClues(
      name: _nameController.text,
      inspiration: _inspirationController.text,
      specialFunction: _specialFunctionController.text,
      speakingStyle: _speakingStyleController.text,
      personality: _personalityController.text,
      expertise: _expertiseController.text,
      habit: _habitController.text,
      relationship: _relationshipController.text,
      artStyle: _artStyleController.text,
      species: _speciesController.text,
      freeform: _freeformController.text,
      referenceImagePaths: _referenceImageValues(),
    );
  }

  void _writeClues(CompanionSummoningClues clues) {
    _nameController.text = clues.name;
    _inspirationController.text = clues.inspiration;
    _specialFunctionController.text = clues.specialFunction;
    _speakingStyleController.text = clues.speakingStyle;
    _personalityController.text = clues.personality;
    _expertiseController.text = clues.expertise;
    _habitController.text = clues.habit;
    _relationshipController.text = clues.relationship;
    _artStyleController.text = clues.artStyle;
    _speciesController.text = clues.species;
    _freeformController.text = clues.freeform;
  }

  void _randomizeClues() {
    _writeClues(_summoningService.randomClues());
    setState(() {
      _candidate = null;
      _generatingSheetKeys.clear();
      _candidatePackSaved = false;
      _primaryVisualReview = null;
      _primaryRightsPassport = null;
      _isReviewingPrimaryImage = false;
      _selectedPresetLabel = null;
    });
  }

  void _applyPreset(_SummonPreset preset) {
    _writeClues(preset.clues);
    setState(() {
      _candidate = null;
      _generatingSheetKeys.clear();
      _candidatePackSaved = false;
      _primaryVisualReview = null;
      _primaryRightsPassport = null;
      _isReviewingPrimaryImage = false;
      _selectedPresetLabel = preset.label;
    });
  }

  Future<void> _summonCandidate() async {
    final clues = _readClues();
    if (!clues.hasAnySignal) {
      _randomizeClues();
    }
    setState(() {
      _isSummoning = true;
      _summonProgress = 0;
      _isReviewingPrimaryImage = false;
      _primaryVisualReview = null;
      _primaryRightsPassport = null;
      _generatingSheetKeys.clear();
      _candidatePackSaved = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    var candidate = _summoningService.summon(_readClues(), salt: _rerollSalt);
    if (!mounted) {
      return;
    }
    setState(() => _candidate = candidate);

    candidate = await _generateCandidateVisual(candidate);
    if (!mounted) {
      return;
    }
    setState(() {
      _candidate = candidate;
      _isSummoning = false;
      _summonProgress = 0;
    });
    await _reviewPrimaryCandidateImage(candidate);
  }

  // [教練 Agent 2026-07-01] 主形象生成分階段進度條
  Widget _buildSummonProgressBar() {
    const stages = ['發送 API 請求', '等待生成圖', '取得生成圖後去背', '完成生成圖'];
    final currentStage = _summonProgress.clamp(0, 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 進度條
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: currentStage == 0 ? null : currentStage / 4,
            backgroundColor: BridgeDSColors.of(context).borderSubtle,
          ),
        ),
        const SizedBox(height: 8),
        // 階段列表
        for (var i = 0; i < stages.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 0),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: i < currentStage
                      ? Icon(
                          Icons.check_circle,
                          size: 14,
                          color: BridgeDSColors.of(context).accentBlue,
                        )
                      : i == currentStage
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : Icon(
                          Icons.radio_button_unchecked,
                          size: 14,
                          color: BridgeDSColors.of(
                            context,
                          ).textSecondary.withValues(alpha: 0.4),
                        ),
                ),
                const SizedBox(width: 8),
                Text(
                  stages[i],
                  style: TierStyle.of(context, Tier.cardCaptionBold)
                      .toTextStyle()
                      .copyWith(
                        color: i < currentStage
                            ? BridgeDSColors.of(context).accentBlue
                            : i == currentStage
                            ? BridgeDSColors.of(context).textPrimary
                            : BridgeDSColors.of(
                                context,
                              ).textSecondary.withValues(alpha: 0.5),
                        fontWeight: i == currentStage
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // [Blue UX 2026-09-17] _rerollCandidate（整組重骰）已無呼叫者——按鈕移除
  // 後成為死代碼，刪除。換主形象用 _rerollPrimaryImageOnly（保留骨架）。

  /// [小葵 2026-09-14] 只重生主形象圖——保留候選骨架（名字/線索/描述），
  /// 與 _rerollCandidate（整組重骰）不同。已有主形象時先確認覆蓋。
  /// [Blue UX 2026-09-17] 判斷是否為真實圖片路徑——排除程序化資產 ID
  /// （cmp_xxx_avatar 是 CompanionArt 渲染種子不是圖檔）。佔位圖不是主形象。
  bool _looksLikeImagePath(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    if (v.startsWith('data:image/')) return true;
    if (v.startsWith('http://') || v.startsWith('https://')) return true;
    final hasExt = v.contains(
        RegExp(r'\.(png|jpe?g|webp|gif|bmp)$', caseSensitive: false));
    if (!hasExt) return false;
    return File(v).existsSync();
  }

  Future<void> _rerollPrimaryImageOnly() async {
    final candidate = _candidate;
    if (candidate == null || _isSummoning) return;

    final hasPrimary =
        candidate.generatedImagePath?.trim().isNotEmpty == true;
    final hasSheets = candidate.generatedSheetImagePaths.values
        .any((p) => p.trim().isNotEmpty);
    if (hasPrimary || hasSheets) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('重新生成主形象'),
          content: const Text(
            '將會把原有主形象與狀態圖覆蓋，確定要這麼做嗎？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('確定覆蓋'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _isSummoning = true;
      _summonProgress = 0;
      _isReviewingPrimaryImage = false;
      _primaryVisualReview = null;
      _primaryRightsPassport = null;
      _generatingSheetKeys.clear();
      // 覆蓋：清掉舊圖（主形象 + 狀態圖），保留文字骨架
      _candidate = candidate.copyWith(
        generatedImagePath: null,
        generatedSheetImagePaths: const {},
        sheetGenerationMessages: const {},
      );
    });

    final updated = await _generateCandidateVisual(_candidate!);
    if (!mounted) return;
    setState(() {
      _candidate = updated;
      _isSummoning = false;
      _summonProgress = 0;
    });
    await _reviewPrimaryCandidateImage(updated);
  }

  Future<CompanionSummoningCandidate> _generateCandidateVisual(
    CompanionSummoningCandidate candidate,
  ) async {
    final prompt =
        'Create a polished character portrait for an AI desktop companion. '
        'Name: ${candidate.name}. MBTI: ${candidate.mbtiCode}. '
        'Role: ${candidate.role.name}. Visual clues: ${candidate.appearancePrompt}. '
        'TEXT-DOMINANT REDESIGN MODE: written clues must control at least 90 percent of the final art direction. If reference images are provided, use them only as a weak ingredient library, at most 10 percent influence. Extract only tiny reusable hints such as a broad silhouette cue, one or two color accents, a species clue, a clothing motif, or a prop idea. '
        'Do not preserve the reference image composition, pose, camera angle, rendering style, facial design, outfit design, or exact character identity unless the written clues explicitly request it. The written art style, personality, role, speaking style, habits, relationship, special function, species, and freeform description are the source of truth and must override the reference image whenever they conflict. '
        'The result must look like a newly redesigned AI companion born from the written description, not an edited copy, traced variant, cosplay version, or style-preserved remake of the uploaded reference. '
        'Style requirements: friendly game character, clean readable silhouette, '
        'one complete uncropped full-body character only, zoomed-out desktop sprite composition, centered on a square canvas, flat solid pure-white background (#FFFFFF, no checkerboard, no transparency illusion — background removal happens in post-processing, so just paint flat white), PNG sprite asset, '
        'the character and every prop must occupy only 62 to 72 percent of the canvas height; leave a large empty white margin around the entire silhouette, '
        'the character main body mass (torso, head, and limbs) MUST be centered on the canvas — the visual center of gravity must align with the canvas center point, not offset to any side, '
        'keep the full top of hair/head, ears, hands, tail, clothing, props, both shoes, full soles, and the entire grounding shadow visible inside the canvas, '
        'feet and the oval grounding shadow must sit at least 12 percent above the bottom edge; no body part, shoe, shadow, tail, weapon, prop, scarf, or hair may touch or leave any canvas edge, '
        'if the character would touch an edge, make the character smaller rather than cropping; do not create a close-up, waist-up portrait, bust portrait, or edge-to-edge composition, '
        'include a soft oval grounding shadow directly under the character feet so it feels dimensional on a desktop window, '
        'no background scenery, suitable for a desktop companion avatar, no text, no logo, no multiple poses, no contact sheet, no storyboard. '
        'COLOR SAFETY RULE (ABSOLUTE, critical for background removal): NOT A SINGLE PIXEL of the character may be near-white. This includes specular highlights, nose tip glints, eye glints, metal shine, glass shine, rim light, teeth, eyes sclera, white hair, white clothing, white fur — every highlight must be rendered in warm cream / soft gold tones strictly between RGB(210,200,185) and RGB(235,228,215). Zero pixels above RGB(238,238,238) anywhere on the character, no exceptions, no matter how small the highlight dot is. Treat pure white as a forbidden color for the character; only the background may be pure white. ';

    try {
      // [教練 Agent 2026-07-01] 分階段進度條——用定時器自動推進
      // 階段 1：發送 API 請求（立即顯示）
      setState(() => _summonProgress = 1);
      // 30 秒後自動進到階段 2：等待生成圖
      final timer2 = Timer(const Duration(seconds: 30), () {
        if (mounted && _isSummoning && _summonProgress < 2) {
          setState(() => _summonProgress = 2);
        }
      });
      // 60 秒後自動進到階段 3：去背處理
      final timer3 = Timer(const Duration(seconds: 60), () {
        if (mounted && _isSummoning && _summonProgress < 3) {
          setState(() => _summonProgress = 3);
        }
      });

      final result = await _executeImageGeneration(
        BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: prompt,
          provider: _resolvedImageModel?.providerId,
          model: _resolvedImageModel?.defaultModel ?? 'gpt-image-2',
          imageQuality: _resolvedImageModel?.quality ?? 'high',
          referenceImagePaths: _referenceImageValues(),
        ),
      );

      timer2.cancel();
      timer3.cancel();

      // [教練 Agent 2026-07-01] 階段 3：取得生成圖後去背
      // （adapter 內部已完成去背，這裡顯示進度回饋）
      if (mounted && _isSummoning && _summonProgress < 3) {
        setState(() => _summonProgress = 3);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      // 階段 4：完成（只有 API 真正回傳才打勾）
      if (mounted && _isSummoning) {
        setState(() => _summonProgress = 4);
      }
      if (result.status == BridgeActionStatus.completed &&
          result.mediaUrl != null &&
          result.mediaUrl!.trim().isNotEmpty) {
        return candidate.copyWith(
          generatedImagePath: result.mediaUrl,
          visualGenerationMessage: result.message,
        );
      }
      return candidate.copyWith(
        visualGenerationMessage: '雲端圖像生成尚未完成：${result.message}',
      );
    } catch (error) {
      return candidate.copyWith(
        visualGenerationMessage: '雲端圖像生成失敗，已先使用預設形象預覽：$error',
      );
    }
  }

  Future<void> _reviewPrimaryCandidateImage(
    CompanionSummoningCandidate candidate,
  ) async {
    final imagePath = candidate.generatedImagePath?.trim();
    if (imagePath == null || imagePath.isEmpty) return;
    setState(() => _isReviewingPrimaryImage = true);
    final tempCompanion = _companionFromCandidate(
      candidate,
      id: 'primary_review_${candidate.seed}',
      baseCompanion: _editingCompanion,
      includeStateImages: false,
    );
    final review = await _primaryVisualReviewService.reviewCompanionImages(
      tempCompanion,
    );
    if (!mounted) return;
    final hasBlocked = review.blockedChecks.isNotEmpty;
    final hasWarning = review.warningChecks.isNotEmpty;
    final signal = hasBlocked
        ? CompanionRightsSignal.blocked
        : hasWarning
        ? CompanionRightsSignal.watching
        : CompanionRightsSignal.approved;
    setState(() {
      _isReviewingPrimaryImage = false;
      _primaryVisualReview = review;
      _primaryRightsPassport = CompanionRightsPassport(
        signal: signal,
        label: switch (signal) {
          CompanionRightsSignal.approved => '主形象預審綠燈：可繼續衍生',
          CompanionRightsSignal.watching => '主形象預審黃燈：建議補充確認',
          CompanionRightsSignal.blocked => '主形象預審紅燈：建議先重新生成',
          CompanionRightsSignal.unreviewed => '主形象尚未預審',
        },
        reviewCaseId: 'primary_${DateTime.now().millisecondsSinceEpoch}',
        reviewedAt: review.reviewedAt,
        passedCount: review.passedChecks.length,
        warningCount: review.warningChecks.length,
        blockedCount: review.blockedChecks.length,
        inspectedImageCount: review.inspectedImageCount,
        requiredClarifications: [
          if (hasWarning) '請確認主形象為原創、安全，且後續圖組會依此安全母版衍生。',
        ],
      );
    });
  }

  Future<void> _generateAllSheetImages(
    CompanionSummoningCandidate candidate,
  ) async {
    // [教練 Agent 2026-07-01] 並行生成全部狀態圖——測試確認可同時跑
    final poses = List<_SheetPose>.of(_sheetStates);
    final latest = _candidate;
    if (latest == null || latest.seed != candidate.seed) return;

    await Future.wait(poses.map((pose) => _generateSheetImage(latest, pose)));
  }

  Future<void> _generateSheetImage(
    CompanionSummoningCandidate candidate,
    _SheetPose pose,
  ) async {
    if (_generatingSheetKeys.contains(pose.key)) return;
    _interruptSnackBarShown = false; // 新一輪生成開始——重置中斷提示旗標
    setState(() => _generatingSheetKeys.add(pose.key));

    final prompt = _buildSheetImagePrompt(candidate, pose);
    try {
      // [教練 Agent 2026-06-29] 狀態圖用 medium 加速（high ~30s, medium ~15s）
      // 在 230px 顯示尺寸下品質差異幾乎看不出來
      // [教練 Agent 2026-06-29] 狀態圖帶主形象當參考圖（edits API），保持角色一致性
      final refPaths =
          (candidate.generatedImagePath != null &&
              candidate.generatedImagePath!.trim().isNotEmpty)
          ? [candidate.generatedImagePath!]
          : const <String>[];
      // [教練 Agent 2026-08-12] 狀態圖用同一引擎（跟隨用戶選擇），不再寫死 gpt-image-2
      final result = await _executeImageGeneration(
        BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: prompt,
          provider: _resolvedImageModel?.providerId,
          model: _resolvedImageModel?.defaultModel ?? 'gpt-image-2',
          imageQuality: _resolvedImageModel?.quality ?? 'high',
          referenceImagePaths: refPaths,
        ),
        sheetKey: pose.key,
      );
      if (!mounted) return;

      // [教練 Agent 2026-07-01] 並行安全：讀「當下最新」的 _candidate 來 merge，
      // 不用 await 前抓的快照，避免並行完成時互相覆蓋
      final current = _candidate;
      if (current == null || current.seed != candidate.seed) return;

      final nextImages = Map<String, String>.from(
        current.generatedSheetImagePaths,
      );
      final nextMessages = Map<String, String>.from(
        current.sheetGenerationMessages,
      );

      if (result.status == BridgeActionStatus.completed &&
          result.mediaUrl != null &&
          result.mediaUrl!.trim().isNotEmpty) {
        nextImages[pose.key] = result.mediaUrl!;
        nextMessages[pose.key] = result.message;
      } else {
        nextMessages[pose.key] = '這張尚未完成：${result.message}';
      }

      setState(() {
        _candidate = current.copyWith(
          generatedSheetImagePaths: nextImages,
          sheetGenerationMessages: nextMessages,
        );
      });
    } catch (error) {
      if (!mounted) return;
      final current = _candidate;
      if (current == null || current.seed != candidate.seed) return;
      final nextMessages = Map<String, String>.from(
        current.sheetGenerationMessages,
      )..[pose.key] = '生成失敗：$error';
      setState(() {
        _candidate = current.copyWith(sheetGenerationMessages: nextMessages);
      });
    } finally {
      if (mounted) {
        setState(() => _generatingSheetKeys.remove(pose.key));
      }
    }
  }

  Future<BridgeActionResult> _executeImageGeneration(
    BridgeAction action, {
    String? sheetKey,
  }) async {
    return _bridgeActionExecutor
        .execute(action, confirmed: true)
        .timeout(
          widget.imageGenerationTimeout,
          onTimeout: () {
            // 記錄逾時，回前景時可重試
            if (sheetKey != null) {
              _timedOutGenerations.add(sheetKey);
            }
            return const BridgeActionResult(
              status: BridgeActionStatus.unsupported,
              message: '圖像生成逾時，已先放開這張圖；請稍後重試、降低品質模式，或換用其他圖片生成服務。',
            );
          },
        );
  }


  // ═══ [小葵 2026-09-24 出道令] 資產匯入門 ═══
  // 使用者直接放入自己的圖檔 / 影片檔 / 音檔——不經生成器。
  // 為自己也為開源使用者開的門：資產放在 companion store，
  // 離開編輯頁後照常被 CompanionAvatarImage / CompanionLoopVideo / TTS 消費。

  /// 匯入外部音檔（wav/mp3）→ bridge_media/audio；voiceName 記成
  /// ext_audio:<檔名>（播放端認得這個前綴就直接播音檔，不過 TTS）。
  Future<void> _importExternalVoice() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['wav', 'mp3', 'm4a', 'ogg'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final docs = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${docs.path}/bridge_media/audio');
      if (!await audioDir.exists()) await audioDir.create(recursive: true);
      final dest =
          '${audioDir.path}/ext_voice_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      await File(file.path!).copy(dest);
      if (!mounted) return;
      setState(() {
        // [外部音色] 前綴＝播放端直通音檔；_voiceName 會存回 companion.voiceName
        _voiceName = 'ext_audio:${file.name}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已匯入音檔：${file.name}（夥伴將直接使用此音檔）')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('匯入音檔失敗：$e')));
      }
    }
  }

  /// 匯入外部形象（png/jpg 或 mp4 影片）→ bridge_media；
  /// 圖片設為主形象候選，影片設為 avatarAnimationPath。
  Future<void> _importExternalVisual() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'mp4'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final docs = await getApplicationDocumentsDirectory();
      final isVideo = file.name.toLowerCase().endsWith('.mp4');
      final subDir = isVideo ? 'animations' : 'images';
      final dir = Directory('${docs.path}/bridge_media/$subDir');
      if (!await dir.exists()) await dir.create(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final ext = file.name.contains('.')
          ? file.name.substring(file.name.lastIndexOf('.'))
          : (isVideo ? '.mp4' : '.png');
      final dest = '${dir.path}/ext_asset_$stamp$ext';
      await File(file.path!).copy(dest);
      if (!mounted) return;
      if (isVideo) {
        setState(() {
          _importedAnimationPath = dest;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已匯入動畫影片：${file.name}（待機循環播放）')),
        );
      } else {
        setState(() {
          final prev = _candidate;
          _candidate = CompanionSummoningCandidate(
            name: _nameController.text,
            mbtiCode: prev?.mbtiCode ?? 'ENFP',
            role: prev?.role ?? CompanionRole.research,
            personalityTags: prev?.personalityTags ?? const [],
            appearancePrompt: prev?.appearancePrompt ?? '',
            appearanceDescription: prev?.appearanceDescription ?? '',
            seed: prev?.seed ?? 0,
            generatedImagePath: dest,
            generatedSheetImagePaths: prev?.generatedSheetImagePaths ?? const {},
            sheetGenerationMessages: const {},
            characterSheetPrompts: const [],
          );
          _importedAnimationPath = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已匯入主形象：${file.name}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('匯入形象失敗：$e')));
      }
    }
  }

    // [小葵 2026-09-24 出道令] 形象匯入按鈕（放主形象區塊用）
  Widget _buildImportVisualButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        onPressed: _importExternalVisual,
        icon: const Icon(Icons.file_upload_outlined, size: 20),
        label: const Text('匯入圖檔 / 影片檔'),
      ),
    );
  }

Future<void> _pickReferenceImages() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
        allowMultiple: true,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;

      final nextImages = <_ReferenceClueImage>[];
      for (final file in result.files) {
        final value = _referenceValueForPickedFile(file);
        if (value == null || value.trim().isEmpty) continue;
        nextImages.add(
          _ReferenceClueImage(
            id: '${DateTime.now().microsecondsSinceEpoch}_${file.name}',
            name: file.name,
            value: value,
            sourceLabel: value.startsWith('data:image/') ? '內嵌參考圖' : '本機圖檔',
          ),
        );
      }
      if (nextImages.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('沒有取得可用的圖片，請再選一次。')));
        return;
      }
      if (!mounted) return;
      // [小葵 2026-09-21] 上傳參考圖不該清掉候選卡——與文字欄位 08-14 修法同族：
      // 舊邏輯無條件 _candidate = null → 生成按鈕（住在候選卡裡）整塊消失，
      // Blue 實測「上傳參考圖後右側生成按鈕全不見」。編輯模式必須保留
      // candidate（既有主形象/狀態圖繼續顯示）；新建模式維持原行為（換參考
      // 圖 = 重鍊方向）。
      setState(() {
        _referenceImages.addAll(nextImages);
        if (_editingCompanion == null) {
          _candidate = null;
          _generatingSheetKeys.clear();
          _candidatePackSaved = false;
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('上傳圖檔失敗：$error')));
    }
  }

  String? _referenceValueForPickedFile(PlatformFile file) {
    final path = file.path;
    if (!kIsWeb && path != null && path.trim().isNotEmpty) return path;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    final mimeType = _mimeTypeForFileName(file.name);
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  String _mimeTypeForFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }

  void _removeReferenceImage(String id) {
    // [小葵 2026-09-21] 移除參考圖同族修復——編輯模式保留 candidate
    // （與 _pickReferenceImages 同日同根因：無條件清 _candidate → 生成按鈕消失）
    setState(() {
      _referenceImages.removeWhere((image) => image.id == id);
      if (_editingCompanion == null) {
        _candidate = null;
        _generatingSheetKeys.clear();
      }
    });
  }

  List<String> _referenceImageValues({String? leadingImagePath}) {
    final values = <String>[
      if (leadingImagePath != null && leadingImagePath.trim().isNotEmpty)
        leadingImagePath.trim(),
      for (final image in _referenceImages) image.value,
    ];
    return values;
  }

  List<CompanionAssetStateSpec> _assetStateSpecsForCandidate(
    CompanionSummoningCandidate candidate,
  ) => _assetStateSpecsForCandidateWithImages(
    candidate,
    imagePaths: candidate.generatedSheetImagePaths,
  );

  List<CompanionAssetStateSpec> _assetStateSpecsForCandidateWithImages(
    CompanionSummoningCandidate candidate, {
    required Map<String, String> imagePaths,
  }) {
    return [
      for (final state in _sheetStates)
        state.toAssetStateSpec(imagePath: imagePaths[state.key]),
    ];
  }

  Future<void> _exportCandidatePack(
    CompanionSummoningCandidate candidate,
  ) async {
    final localOnly = _isLocalOnlyPassport(_primaryRightsPassport);
    final commercialUseAllowed = await _askCommercialUseAllowed(
      title: '儲存角色資產包',
      body:
          '這份存檔未來可能被你自己匯入、備份或私下傳給朋友。請確認是否允許收到這份資產包的人拿它做商業用途。'
          '${localOnly ? '\n\n注意：目前主形象預審是黃燈或紅燈，匯出的資產包會標記為本機限定，只能在這台電腦/這個 Bridge 安裝匯入，其他電腦會拒絕載入。' : ''}',
      confirmLabel: '繼續儲存',
    );
    if (commercialUseAllowed == null) return;
    final companion = _companionFromCandidate(
      candidate,
      id: 'draft_${candidate.seed}',
    );
    final primaryImagePath = await _portablePackImageValue(
      candidate.generatedImagePath,
    );
    final portableSheetImages = <String, String>{};
    for (final entry in candidate.generatedSheetImagePaths.entries) {
      final portable = await _portablePackImageValue(entry.value);
      if (portable != null && portable.trim().isNotEmpty) {
        portableSheetImages[entry.key] = portable;
      }
    }

    // [教練 Agent 2026-07-01] 改用 ZIP 格式匯出（含 manifest.json + 圖片），
    // 與匯入端一致，解決匯入時「ZIP 缺 manifest.json」的問題
    final zipBytes =
        await CompanionPackService(
          localInstallId: CompanionStore().localInstallId,
        ).exportToZip(
          companion,
          summary: '${candidate.name} 的 Bridge 角色資產包草稿',
          assetStates: _assetStateSpecsForCandidateWithImages(
            candidate,
            imagePaths: portableSheetImages,
          ),
          primaryImagePath: primaryImagePath,
          commercialUseAllowed: commercialUseAllowed,
        );

    final fileName = _safePackFileName(candidate.name, candidate.seed);
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: '儲存角色資產包',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      bytes: Uint8List.fromList(zipBytes),
    );
    if (!mounted) return;
    final message = kIsWeb
        ? '已下載 $fileName'
        : savedPath == null
        ? '已取消儲存。'
        : '已儲存 ${candidate.name} 的角色資產包：$savedPath';
    setState(() => _candidatePackSaved = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool?> _askCommercialUseAllowed({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    var allowCommercialUse = false;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                body,
                style: TextStyle(
                  color: BridgeDSColors.of(context).textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: allowCommercialUse,
                onChanged: (value) =>
                    setDialogState(() => allowCommercialUse = value == true),
                title: Text(
                  '我同意這份角色資產包可被商用',
                  style: tierBasedStyle(
                    context,
                    Tier.listItemTitle,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: const Text('不勾選時，資產包會標記為不允許商用。'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(allowCommercialUse),
              icon: const Icon(Icons.save_alt_outlined),
              label: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
  }

  bool _isLocalOnlyPassport(CompanionRightsPassport? passport) {
    return passport?.signal == CompanionRightsSignal.watching ||
        passport?.signal == CompanionRightsSignal.blocked;
  }

  String _safePackFileName(String name, int seed) {
    final normalized = name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    final base = normalized.isEmpty ? 'bridge_companion_$seed' : normalized;
    return '$base.bridgepack.zip';
  }

  Future<void> _showImportPackOptions() async {
    final action = await showDialog<_PackImportAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('匯入角色資產包'),
        content: const Text('可以選擇之前匯出的 .bridgepack.zip 檔案，也可以貼上社群分享的 JSON。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(_PackImportAction.pasteJson),
            icon: const Icon(Icons.content_paste_outlined),
            label: const Text('貼上 JSON'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(_PackImportAction.pickFile),
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('選擇檔案'),
          ),
        ],
      ),
    );
    if (action == _PackImportAction.pickFile) {
      await _importPackFromFile();
    } else if (action == _PackImportAction.pasteJson) {
      await _showImportPackDialog();
    }
  }

  Future<void> _importPackFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final filePath = file.path;
      if (filePath == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無法取得檔案路徑')));
        return;
      }

      // [教練 Agent 2026-06-29] 支援 ZIP 格式（.bridgepack.zip）
      if (filePath.toLowerCase().endsWith('.zip')) {
        final raw = await File(filePath).readAsBytes();
        final companion = await CompanionStore().importCompanionPackFromZip(
          raw,
        );
        if (!mounted) return;
        setState(() => _candidatePackSaved = true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已匯入 ${companion.name} 的角色包')));
        return;
      }

      // JSON 格式
      final json = kIsWeb
          ? utf8.decode(file.bytes ?? const <int>[])
          : await File(filePath).readAsString();
      await _importPackJson(json);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('匯入檔案失敗：$error')));
    }
  }

  Future<void> _showImportPackDialog() async {
    final controller = TextEditingController();
    final json = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('匯入角色資產包'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '貼上社群分享的 Companion Pack JSON',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(controller.text),
            icon: const Icon(Icons.move_to_inbox_outlined),
            label: const Text('匯入到創造頁'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (json == null || json.trim().isEmpty) return;

    await _importPackJson(json);
  }

  Future<void> _importPackJson(
    String json, {
    bool showSnackBar = true,
    bool markPackSaved = true,
  }) async {
    try {
      final service = CompanionPackService(
        localInstallId: CompanionStore().localInstallId,
      );
      final preview = service.previewFromJson(json);
      if (!preview.isSafe) {
        throw CompanionPackException(
          '這個角色包不安全：${preview.unsafeReasons.join('、')}',
        );
      }
      final companion = service.importFromPackJson(preview.pack);
      final clues = _cluesFromImportedPack(preview.pack, companion, preview);
      _writeClues(clues);
      final importedStates = _sheetStatesFromPack(preview.pack);
      final importedImages = _sheetImagePathsFromPack(preview.pack).isEmpty
          ? companion.stateImagePaths
          : _sheetImagePathsFromPack(preview.pack);
      final importedPrimaryImage =
          _primaryImagePathFromPack(preview.pack) ?? companion.avatarImagePath;
      final candidate = CompanionSummoningCandidate(
        name: companion.name,
        mbtiCode: companion.mbtiCode,
        role: companion.role,
        personalityTags: companion.personalityTags,
        seed: companion.appearanceSeed,
        appearancePrompt: companion.appearancePrompt,
        appearanceDescription: companion.appearanceDescription,
        generatedImagePath: importedPrimaryImage,
        generatedSheetImagePaths: importedImages,
        sheetGenerationMessages: {
          for (final key in importedImages.keys) key: '已從角色資產包匯入圖片。',
        },
        visualGenerationMessage: importedPrimaryImage == null
            ? null
            : '已從角色資產包匯入主形象。',
        characterSheetPrompts: _characterSheetPromptsFromPack(preview.pack),
      );
      if (!mounted) return;
      setState(() {
        _sheetStates = importedStates.isEmpty
            ? List<_SheetPose>.of(_defaultSheetPoses)
            : importedStates;
        _candidate = candidate;
        _candidatePackSaved = markPackSaved;
        _primaryVisualReview = null;
        _primaryRightsPassport = companion.rightsPassport;
        _isReviewingPrimaryImage = false;
        _generatingSheetKeys.clear();
        _selectedPresetLabel = null;
      });
      // [教練 Agent 2026-06-30] 修復：匯入角色包後清舊草稿再存新草稿，
      // 避免下次「鍊成新夥伴」時恢復到上一個匯入的角色資料
      await _clearDraft();
      await _saveDraft();
      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已匯入 ${preview.name}，可以繼續微調')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('匯入失敗：$error')));
    }
  }

  // ignore: unused_element
  Map<String, dynamic> _cluesToPackJson(CompanionSummoningClues clues) {
    return {
      'name': clues.name,
      'inspiration': clues.inspiration,
      'specialFunction': clues.specialFunction,
      'speakingStyle': clues.speakingStyle,
      'personality': clues.personality,
      'expertise': clues.expertise,
      'habit': clues.habit,
      'relationship': clues.relationship,
      'artStyle': clues.artStyle,
      'species': clues.species,
      'freeform': clues.freeform,
    };
  }

  CompanionSummoningClues _cluesFromImportedPack(
    Map<String, dynamic> pack,
    Companion companion,
    CompanionPackPreview preview,
  ) {
    final packedClues = pack['summoningClues'];
    if (packedClues is Map) {
      final map = Map<dynamic, dynamic>.from(packedClues);
      return CompanionSummoningClues(
        name: _stringFrom(map['name'], fallback: companion.name),
        inspiration: _stringFrom(map['inspiration']),
        specialFunction: _stringFrom(map['specialFunction']),
        speakingStyle: _stringFrom(map['speakingStyle']),
        personality: _stringFrom(map['personality']),
        expertise: _stringFrom(map['expertise']),
        habit: _stringFrom(map['habit']),
        relationship: _stringFrom(map['relationship']),
        artStyle: _stringFrom(map['artStyle']),
        species: _stringFrom(map['species']),
        freeform: _stringFrom(map['freeform']),
      );
    }

    final promptFields = _clueFieldsFromAppearancePrompt(
      companion.appearancePrompt,
    );
    return CompanionSummoningClues(
      name: companion.name,
      inspiration: promptFields['人物名人靈感'] ?? '',
      specialFunction: preview.specialFunction.isEmpty
          ? promptFields['特殊功能'] ?? companion.roleName
          : preview.specialFunction,
      speakingStyle: promptFields['說話風格'] ?? preview.speakingStyle,
      personality: [
        if ((promptFields['個性'] ?? '').trim().isNotEmpty) promptFields['個性'],
        if ((promptFields['個性'] ?? '').trim().isEmpty)
          ...preview.personalityTags,
        if ((promptFields['個性'] ?? '').trim().isEmpty)
          ...companion.personalityTags.map((tag) => tag.name),
      ].whereType<String>().where((value) => value.trim().isNotEmpty).join('、'),
      expertise: preview.expertise.isEmpty
          ? promptFields['專長'] ?? companion.roleName
          : preview.expertise.join('、'),
      habit: promptFields['習慣'] ?? '',
      relationship: promptFields['與使用者的關係'] ?? '使用者的 Bridge Brain 角色外殼',
      artStyle: promptFields['畫風'] ?? '',
      species: promptFields['種族'] ?? '',
      freeform: promptFields['自由敘述'] ?? preview.summary,
    );
  }

  Map<String, String> _clueFieldsFromAppearancePrompt(String prompt) {
    final fields = <String, String>{};
    for (final part in prompt.split(RegExp(r'[；;]\s*'))) {
      final separator = part.indexOf('：');
      if (separator <= 0) continue;
      final key = part.substring(0, separator).trim();
      final value = part.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) fields[key] = value;
    }
    return fields;
  }

  List<String> _characterSheetPromptsFromPack(Map<String, dynamic> pack) {
    final assets = pack['assets'];
    final manifest = assets is Map ? assets['manifest'] : null;
    final manifestMap = manifest is Map ? manifest : const {};
    final states = manifestMap['states'];
    final prompts = <String>[
      _stringFrom(
        manifestMap['appearance'] is Map
            ? (manifestMap['appearance'] as Map)['prompt']
            : null,
      ),
    ];
    if (states is List) {
      for (final state in states) {
        if (state is! Map) continue;
        final prompt = _stringFrom(state['prompt']);
        if (prompt.isNotEmpty) prompts.add(prompt);
      }
    }
    return prompts.where((prompt) => prompt.trim().isNotEmpty).toList();
  }

  List<_SheetPose> _sheetStatesFromPack(Map<String, dynamic> pack) {
    final assets = pack['assets'];
    if (assets is! Map) return const [];
    final manifest = assets['manifest'];
    if (manifest is! Map) return const [];
    final states = manifest['states'];
    if (states is! List) return const [];
    return [
      for (final state in states)
        if (state is Map) _sheetPoseFromManifestState(state),
    ];
  }

  Map<String, String> _sheetImagePathsFromPack(Map<String, dynamic> pack) {
    final assets = pack['assets'];
    if (assets is! Map) return const {};
    final manifest = assets['manifest'];
    if (manifest is! Map) return const {};
    final states = manifest['states'];
    if (states is! List) return const {};
    final images = <String, String>{};
    for (final state in states) {
      if (state is! Map) continue;
      final stateId = _stringFrom(state['stateId'], fallback: '${state['id']}');
      final still = state['still'] is Map
          ? Map<dynamic, dynamic>.from(state['still'] as Map)
          : const <dynamic, dynamic>{};
      final imagePath = _stringFrom(
        state['imagePath'],
        fallback: _stringFrom(still['path']),
      );
      if (stateId.trim().isNotEmpty && imagePath.trim().isNotEmpty) {
        images[stateId] = imagePath;
      }
    }
    return images;
  }

  String? _primaryImagePathFromPack(Map<String, dynamic> pack) {
    final appearance = pack['appearance'];
    final assets = pack['assets'];
    final manifest = assets is Map ? assets['manifest'] : null;
    final appearanceMap = appearance is Map ? appearance : const {};
    final manifestMap = manifest is Map ? manifest : const {};
    final candidates = [
      appearanceMap['avatarImagePath'],
      appearanceMap['portraitImagePath'],
      appearanceMap['avatarImage'],
      manifestMap['primaryAvatarImagePath'],
    ];
    for (final candidate in candidates) {
      final value = _stringFrom(candidate);
      if (value.trim().isNotEmpty) return value;
    }
    return null;
  }

  String _buildSheetImagePrompt(
    CompanionSummoningCandidate candidate,
    _SheetPose pose,
  ) {
    // [教練 Agent 2026-06-29] 狀態圖不走 edits API（不帶參考圖），
    // 改用文字描述強化角色一致性
    final characterIdentity =
        'Character identity anchor (text-only, no reference image provided): '
        'Name: ${candidate.name}. '
        'MBTI: ${candidate.mbtiCode}. Role: ${candidate.role.name}. '
        'Full appearance description: ${candidate.appearancePrompt}. '
        'Appearance summary: ${candidate.appearanceDescription}. '
        'You MUST reproduce this exact character — same face, hair or head shape, '
        'outfit, color palette, species, proportions, and art style — purely from '
        'the written description above. ';
    final safetyAnchor =
        _primaryRightsPassport?.signal == CompanionRightsSignal.approved
        ? 'The first-round visual safety review approved the primary portrait. Treat that primary portrait as the safety canon: all derived state images must remain consistent with it and must not introduce adult content, nudity, gore, hateful symbols, logos, trademarks, official-collaboration wording, recognizable existing IP, or new brand marks. '
        : 'Keep the derived state image safe for community preview: no adult content, nudity, gore, hateful symbols, logos, trademarks, official-collaboration wording, recognizable existing IP, or brand marks. ';

    // [教練 Agent 2026-07-03] 狀態圖多樣性：每個狀態配獨特的姿勢/構圖/視角
    // 角色特徵（臉、服裝、配色）由 characterIdentity 鎖定，
    // 但姿勢、構圖、視角、動態由 poseGuide 主導，確保 8 張圖遠看也有明顯差異
    final poseGuide = stateImagePoseGuides[pose.key] ?? '';
    final compositionInstruction = poseGuide.isNotEmpty
        ? 'Composition: exactly one depiction of the character, one state sprite only. '
              'Pose and camera direction (MUST follow): $poseGuide '
              'The character must be full body with complete uncropped silhouette, '
              'flat solid pure-white background (#FFFFFF, no checkerboard, no transparency illusion — background removal happens in post), PNG sprite asset, '
              'include a soft oval grounding shadow directly under the feet, '
              'no background scenery, no text, no logo, no UI, '
              'do not create multiple poses, do not create a contact sheet, '
              'do not create a storyboard, do not duplicate the character, '
              'do not show before/after panels, '
              'suitable as a desktop companion floating on screen.'
        : 'Composition: exactly one depiction of the character, one state sprite only, centered, zoomed-out full body, complete uncropped silhouette, flat solid pure-white background (#FFFFFF, no checkerboard), PNG sprite asset, '
              'the full character, both shoes, full soles, props, tail, hair, and the entire grounding shadow must stay inside the canvas with a large empty white margin; feet and shadow must sit at least 12 percent above the bottom edge, '
              'include a soft oval grounding shadow directly under the feet, no background scenery, no text, no logo, no UI, '
              'do not create multiple poses, do not create a contact sheet, do not create a storyboard, do not duplicate the character, do not show before/after panels, '
              'suitable as a desktop companion floating on screen.';

    return '$characterIdentity'
        '$safetyAnchor'
        'Create one consistent character sheet image for the same AI desktop companion. '
        'Keep the same character identity, face, hair or head shape, outfit, color palette, species, proportions, and art style across the whole set. '
        'Preserve the redesigned companion identity created from the written clues; written art style, personality, behavior, expression, and state description have dominant priority. '
        'The state image must feel like the same newly designed companion acting in the requested state. '
        'Required state name: ${pose.label}. '
        'Behavior: ${pose.behavior}. '
        'Facial expression and emotion: ${pose.expression}. '
        '$compositionInstruction';
  }

  void _addSheetState() {
    final index = _sheetStates.length + 1;
    setState(() {
      _sheetStates = [
        ..._sheetStates,
        _SheetPose(
          key: 'custom_${DateTime.now().microsecondsSinceEpoch}',
          label: '自訂狀態 $index',
          behavior: '描述這張圖要做的動作，例如招手、思考、睡覺、提醒。',
          expression: '描述臉部表情與情緒，例如微笑、驚喜、專注、調皮。',
          triggerScene: '描述這張圖什麼時候出現，例如使用者稱讚、任務卡住、等待外部服務。',
          triggerKeywords: const ['太棒了', '卡住了'],
          intentTags: const ['custom'],
          priority: 55,
          cooldownSeconds: 20,
          fallbackStateId: 'idle',
          kind: 'custom',
          icon: Icons.add_reaction_outlined,
          mood: AgentCompanionMood.curious,
          action: AgentCompanionAction.wandering,
        ),
      ];
    });
  }

  List<String> _splitTriggerInput(String value) {
    return value
        .split(RegExp(r'[,，、\s]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  void _updateSheetState(
    String key,
    _SheetPose Function(_SheetPose state) update, {
    bool rebuild = true,
  }) {
    final nextStates = [
      for (final state in _sheetStates)
        if (state.key == key) update(state) else state,
    ];
    if (rebuild) {
      setState(() => _sheetStates = nextStates);
      return;
    }
    _sheetStates = nextStates;
  }

  Future<void> _confirmCandidate() async {
    final candidate = _candidate;
    final editingCompanion = _editingCompanion;

    // [教練 Agent 2026-08-14] 使用者要求：編輯模式下只改文字不需要重新生成形象圖。
    // 不管 _candidate 是否存在，編輯模式一律走「快速文字存檔」路徑：
    // 用舊 Companion 的圖片 + controller 裡的新文字直接存檔。
    // 只有「新建夥伴」才走完整的 candidate → 生成 → 認證流程。
    // [教練 Agent 2026-08-14] 使用者要求：編輯模式下只改文字不需要重新生成形象圖。
    // 不管 _candidate 是否存在，編輯模式一律走「快速文字存檔」路徑：
    // 用舊 Companion 的圖片 + controller 裡的新文字直接存檔。
    // 只有「新建夥伴」才走完整的 candidate → 生成 → 認證流程。
    if (editingCompanion != null) {
      final newName = _nameController.text.trim();
      // [Blue UX 2026-09-17] 存檔鎖定圖片——舊版編輯模式只存文字，新生的
      // 主形象/狀態圖按存檔後直接消失（null 蓋回去）。現在：有新圖帶新圖，
      // 沒生成過就保留舊圖。存檔＝鎖定，圖不許不見。
      final newAvatar = candidate?.generatedImagePath?.trim();
      final newSheets = <String, String>{};
      final candidateSheets = candidate?.generatedSheetImagePaths;
      if (candidateSheets != null) {
        for (final entry in candidateSheets.entries) {
          final v = entry.value.trim();
          if (v.isNotEmpty) newSheets[entry.key] = v;
        }
      }
      final updated = editingCompanion.copyWith(
        name: newName.isNotEmpty ? newName : editingCompanion.name,
        avatarImagePath: (newAvatar != null && newAvatar.isNotEmpty)
            ? newAvatar
            : editingCompanion.avatarImagePath,
        stateImagePaths: newSheets.isNotEmpty ? newSheets : editingCompanion.stateImagePaths,
        inspiration: _inspirationController.text.trim(),
        specialFunction: _specialFunctionController.text.trim(),
        speakingStyle: _speakingStyleController.text.trim(),
        personality: _personalityController.text.trim(),
        expertise: _expertiseController.text.trim(),
        habit: _habitController.text.trim(),
        relationship: _relationshipController.text.trim(),
        artStyle: _artStyleController.text.trim(),
        species: _speciesController.text.trim(),
        freeform: _freeformController.text.trim(),
        soulMd: _soulMdController.text.trim(), // [H3]
        rightsPassport:
            _primaryRightsPassport ?? editingCompanion.rightsPassport,
      );
      // [Blue UX 2026-09-17] 編輯模式存檔同樣收保管庫（與新建一致）
      var lockedCompanion = updated;
      try {
        final vaultResult = await CompanionImageVault.lockIn(
          companionId: updated.id,
          avatarImagePath: updated.avatarImagePath,
          stateImagePaths: updated.stateImagePaths,
        );
        lockedCompanion = updated.copyWith(
          avatarImagePath: vaultResult.avatarImagePath,
          stateImagePaths: vaultResult.stateImagePaths,
        );
      } catch (e) {
        debugPrint('[ConfirmCandidate] 編輯存檔保管庫收存失敗（保留原路徑）: $e');
      }
      await CompanionStore().update(lockedCompanion);
      if (!mounted) return;
      if (widget.onBack != null) {
        widget.onBack!();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ 夥伴設定已更新！'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        context.go('/');
      }
      return;
    }

    // 以下只有「新建夥伴」會走到
    if (candidate == null) return; // 新建夥伴必須先生成

    var companion = _companionFromCandidate(
      candidate,
      id: editingCompanion?.id ?? CompanionStore.generateId(),
      baseCompanion: editingCompanion,
    );
    // [H3] 表單靈魂文檔寫入（空=沿用 baseCompanion 預設）
    final soulText = _soulMdController.text.trim();
    if (soulText.isNotEmpty) {
      companion = companion.copyWith(soulMd: soulText);
    }
    // [Blue UX 2026-09-17] 存檔鎖定——圖像收進 App 容器保管庫，使用者
    // 誤刪 bridge_media 也不影響 App 顯示（Blue：存檔後圖的資料要鎖定）
    try {
      final vaultResult = await CompanionImageVault.lockIn(
        companionId: companion.id,
        avatarImagePath: companion.avatarImagePath,
        stateImagePaths: companion.stateImagePaths,
      );
      companion = companion.copyWith(
        avatarImagePath: vaultResult.avatarImagePath,
        stateImagePaths: vaultResult.stateImagePaths,
      );
    } catch (e) {
      debugPrint('[ConfirmCandidate] 保管庫收存失敗（保留原路徑）: $e');
    }
    final certifiedCompanion = await _certifyFinalCompanion(companion);
    if (certifiedCompanion == null) return;

    if (editingCompanion == null) {
      await CompanionStore().add(certifiedCompanion);
    } else {
      await CompanionStore().update(certifiedCompanion);
    }
    // [教練 Agent 2026-06-29] 角色確認建立後清除草稿
    await _clearDraft();
    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: BridgeDSColors.of(context).surface.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _SummonRewardOverlay(companion: certifiedCompanion);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curve),
            child: child,
          ),
        );
      },
    );
    if (!mounted) return;
    // [教練 Agent 修復真機輪 2026-06-27] 建立成功後，若來自首次設定流程，直接回 first-summon
    // 讓黃燈→綠燈的進度能被使用者看到；否則回夥伴館。
    // 舊版用 SnackBar 的「查看進度」按鈕，但緊接著 context.go('/companions') 立即蓋掉頁面，
    // 導致 SnackBar context 失效、按鈕點了沒反應。改為直接依來源導航。
    final cameFromFirstSummon =
        widget.returnTo?.contains('first-summon') ?? false;
    if (cameFromFirstSummon) {
      context.go('/first-summon');
    } else if (widget.onBack != null) {
      // [教練 Agent 2026-08-12] 桌面版內嵌模式：用 callback 回夥伴館列表，不走舊路由
      widget.onBack!();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 夥伴已存檔更新！'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } else {
      context.go('/');
      if (mounted) {
        ScaffoldMessenger.of(
          Navigator.of(context, rootNavigator: true).context,
        ).showSnackBar(
          const SnackBar(
            content: Text('✅ 夥伴已建立！已加入你的夥伴館。'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<Companion?> _certifyFinalCompanion(Companion companion) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('正在進行收尾預審，產生角色資產權利護照...')),
          ],
        ),
      ),
    );
    var progressClosed = false;
    try {
      final packJson = CompanionPackService(
        localInstallId: CompanionStore().localInstallId,
      ).exportToJson(companion);
      final reviewCase = await const SemiDaoReviewStore().submitCompanion(
        companion: companion,
        packJson: packJson,
      );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      progressClosed = true;
      return companion.copyWith(
        rightsPassport: _passportFromFinalReview(reviewCase),
      );
    } catch (error) {
      if (mounted && !progressClosed) {
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) navigator.pop();
      }
      progressClosed = true;
      if (!mounted) return null;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('收尾預審未完成'),
          content: Text('角色尚未寫入，請稍後再試。錯誤：$error'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return null;
    } finally {
      if (mounted && !progressClosed) {
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) navigator.pop();
      }
    }
  }

  CompanionRightsPassport _passportFromFinalReview(
    SemiDaoReviewCase reviewCase,
  ) {
    return CompanionRightsPassport(
      signal: switch (reviewCase.signal) {
        SemiDaoReviewSignal.approved => CompanionRightsSignal.approved,
        SemiDaoReviewSignal.watching => CompanionRightsSignal.watching,
        SemiDaoReviewSignal.blocked => CompanionRightsSignal.blocked,
      },
      label: reviewCase.signalLabel,
      reviewCaseId: reviewCase.id,
      reviewedAt: reviewCase.certification.certifiedAt,
      passedCount: reviewCase.certification.passedChecks.length,
      warningCount: reviewCase.certification.warningChecks.length,
      blockedCount: reviewCase.certification.blockedChecks.length,
      inspectedImageCount:
          reviewCase.certification.visualReview?.inspectedImageCount ?? 0,
      requiredClarifications: reviewCase.certification.requiredClarifications,
      clarification: reviewCase.clarification,
    );
  }

  Companion _companionFromCandidate(
    CompanionSummoningCandidate candidate, {
    required String id,
    Companion? baseCompanion,
    bool includeStateImages = true,
  }) {
    return Companion(
      id: id,
      name: candidate.name,
      mbtiCode: candidate.mbtiCode,
      role: candidate.role,
      personalityTags: candidate.personalityTags,
      appearancePrompt: candidate.appearancePrompt,
      appearanceDescription: candidate.appearanceDescription,
      appearanceSeed: candidate.seed,
      avatarImagePath: candidate.generatedImagePath,
      // [小葵 2026-09-24 出道令] 匯入的動畫影片優先；沒匯入沿用原值
      avatarAnimationPath: _importedAnimationPath ?? baseCompanion?.avatarAnimationPath,
      stateImagePaths: includeStateImages
          ? candidate.generatedSheetImagePaths
          : const {},
      stateAnimationPaths: includeStateImages
          ? baseCompanion?.stateAnimationPaths ?? const {}
          : const {},
      // [教練 Agent 2026-07-03] 把使用者設定的觸發關鍵字存進 Companion
      stateTriggerKeywords: {
        for (final state in _sheetStates)
          if (state.triggerKeywords.isNotEmpty)
            state.key: state.triggerKeywords,
      },
      appearanceHistory: [
        ...candidate.characterSheetPrompts,
        for (final state in _sheetStates)
          '狀態 ${state.key}：${state.label}｜行為：${state.behavior}｜表情：${state.expression}｜出現時機：${state.triggerScene}｜關鍵字：${state.triggerKeywords.join('、')}',
        if (candidate.generatedImagePath != null)
          '候選主形象：${candidate.generatedImagePath}',
        for (final entry in candidate.generatedSheetImagePaths.entries)
          '圖組 ${entry.key}：${entry.value}',
      ],
      modelEndpoint: 'default',
      // [H3] 靈魂文檔沿襲——編輯夥伴不得失魂
      soulMd: baseCompanion?.soulMd ?? '',
      rightsPassport: _primaryRightsPassport ?? baseCompanion?.rightsPassport,
      // [Kokoro TTS 2026-07-28] 語音設定
      voiceName: _voiceName,
      voiceSpeed: _voiceSpeed,
      emotionEnabled: _emotionEnabled,
      emotionSensitivity: _emotionSensitivity,
      totalConversations: baseCompanion?.totalConversations ?? 0,
      totalTokens: baseCompanion?.totalTokens ?? 0,
      lastSummoned: baseCompanion?.lastSummoned,
      createdAt: baseCompanion?.createdAt,
    );
  }
}

class _SummonQuestStep {
  final IconData icon;
  final String title;
  final String detail;
  final bool done;
  final bool active;

  const _SummonQuestStep({
    required this.icon,
    required this.title,
    required this.detail,
    required this.done,
    required this.active,
  });
}

class _QuestProgressBadge extends StatelessWidget {
  final String label;

  const _QuestProgressBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: BridgeDSColors.of(
            context,
          ).accentYellow.withValues(alpha: 0.34),
        ),
      ),
      child: Text(
        label,
        style: TierStyle.of(
          context,
          Tier.numericEmphasis,
        ).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentBlue),
      ),
    );
  }
}

class _SummonQuestStepTile extends StatelessWidget {
  final int index;
  final _SummonQuestStep step;
  final bool compact;

  const _SummonQuestStepTile({
    required this.index,
    required this.step,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = step.done
        ? BridgeDSColors.of(context).accentGreen
        : step.active
        ? BridgeDSColors.of(context).accentBlue
        : BridgeDSColors.of(context).textMuted;
    return Container(
      width: double.infinity,
      constraints: compact
          ? const BoxConstraints(minHeight: 86)
          : const BoxConstraints(),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: step.active
            ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.10)
            : BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: step.active
              ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.34)
              : BridgeDSColors.of(context).borderSubtle,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: step.done
                ? Icon(
                    Icons.check,
                    size: 15,
                    color: BridgeDSColors.of(context).accentGreen,
                  )
                : Text(
                    '$index',
                    style: TierStyle.of(
                      context,
                      Tier.numericEmphasis,
                    ).toTextStyle().copyWith(color: color),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(step.icon, size: 15, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        step.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TierStyle.of(context, Tier.numericEmphasis)
                            .toTextStyle()
                            .copyWith(
                              color: step.active
                                  ? BridgeDSColors.of(context).textPrimary
                                  : color,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  step.detail,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.cardCaptionBold)
                      .toTextStyle()
                      .copyWith(
                        color: BridgeDSColors.of(context).textSecondary,
                        fontSize: 10,
                        height: 1.3,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _stringFrom(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }
  final text = '$value'.trim();
  return text.isEmpty ? fallback : text;
}

Future<String?> _portablePackImageValue(String? imagePath) async {
  final value = imagePath?.trim();
  if (value == null || value.isEmpty) return null;
  if (value.startsWith('data:image/') ||
      value.startsWith('http://') ||
      value.startsWith('https://')) {
    return value;
  }
  if (kIsWeb) return value;
  final file = File(value);
  if (!await file.exists()) return value;
  final bytes = await file.readAsBytes();
  final lower = value.toLowerCase();
  final mimeType = lower.endsWith('.jpg') || lower.endsWith('.jpeg')
      ? 'image/jpeg'
      : lower.endsWith('.webp')
      ? 'image/webp'
      : 'image/png';
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}

class _SummonRewardOverlay extends StatefulWidget {
  final Companion companion;

  const _SummonRewardOverlay({required this.companion});

  @override
  State<_SummonRewardOverlay> createState() => _SummonRewardOverlayState();
}

class _SummonRewardOverlayState extends State<_SummonRewardOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _closeTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _closeTimer = Timer(const Duration(milliseconds: 3300), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mbti = widget.companion.mbtiType;
    final color = mbti == null
        ? BridgeDSColors.of(context).accentBlue
        : Color(int.parse(mbti.colorHex.replaceFirst('#', '0xFF')));
    return Material(
      color: Colors.transparent,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = _controller.value;
            return Container(
              width: math.min(MediaQuery.of(context).size.width - 32, 520),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    BridgeDSColors.of(context).accentNavy,
                    color,
                    BridgeDSColors.of(context).accentNavy,
                  ],
                ),
                border: Border.all(
                  color: BridgeDSColors.of(
                    context,
                  ).textPrimary.withValues(alpha: 0.42),
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 42,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _SummonRewardPainter(
                        progress: t,
                        color: color,
                        seed: widget.companion.appearanceSeed,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '夥伴建立成功',
                        style: tierBasedStyle(
                          context,
                          Tier.appTitle,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '新夥伴已加入 Bridge Brain',
                        style: TierStyle.of(context, Tier.blockSubheading)
                            .toTextStyle()
                            .copyWith(
                              color: BridgeDSColors.of(
                                context,
                              ).textPrimary.withValues(alpha: 0.78),
                            ),
                      ),
                      SizedBox(height: 24),
                      Transform.scale(
                        scale: 1 + math.sin(t * math.pi * 2) * 0.018,
                        child: Container(
                          width: 220,
                          height: 220,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: BridgeDSColors.of(
                              context,
                            ).textPrimary.withValues(alpha: 0.14),
                            border: Border.all(
                              color: BridgeDSColors.of(
                                context,
                              ).textPrimary.withValues(alpha: 0.52),
                            ),
                          ),
                          child: ClipOval(
                            child: Container(
                              color: BridgeDSColors.of(
                                context,
                              ).textPrimary.withValues(alpha: 0.92),
                              child: CompanionAvatarImage(
                                companion: widget.companion,
                                mbtiCode: widget.companion.mbtiCode,
                                seed: widget.companion.appearanceSeed,
                                name: widget.companion.name,
                                mood: AgentCompanionMood.proud,
                                action: AgentCompanionAction.bouncing,
                                size: 196,
                                framed: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        widget.companion.name,
                        textAlign: TextAlign.center,
                        style: tierBasedStyle(
                          context,
                          Tier.appTitle,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '${widget.companion.mbtiCode} · ${widget.companion.roleName}',
                        textAlign: TextAlign.center,
                        style: TierStyle.of(context, Tier.blockSubheading)
                            .toTextStyle()
                            .copyWith(
                              color: BridgeDSColors.of(
                                context,
                              ).textPrimary.withValues(alpha: 0.82),
                            ),
                      ),
                      SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: BridgeDSColors.of(
                            context,
                          ).textPrimary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusXL,
                          ),
                          border: Border.all(
                            color: BridgeDSColors.of(
                              context,
                            ).textPrimary.withValues(alpha: 0.24),
                          ),
                        ),
                        child: Text(
                          '角色資產包已封存，準備進入夥伴房間',
                          style: TierStyle.of(
                            context,
                            Tier.cardCaptionBold,
                          ).toTextStyle(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SummonRewardPainter extends CustomPainter {
  final double progress;
  final Color color;
  final int seed;

  _SummonRewardPainter({
    required this.progress,
    required this.color,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rng = math.Random(seed);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = BridgeDS.textPrimary.withValues(alpha: 0.24);

    for (var i = 0; i < 4; i++) {
      final radius = 92 + i * 42 + math.sin(progress * math.pi * 2 + i) * 8;
      canvas.drawCircle(center, radius, ringPaint);
    }

    for (var i = 0; i < 34; i++) {
      final baseAngle = rng.nextDouble() * math.pi * 2;
      final orbit = 70 + rng.nextDouble() * 190;
      final angle = baseAngle + progress * math.pi * (0.45 + rng.nextDouble());
      final point = center.translate(
        math.cos(angle) * orbit,
        math.sin(angle) * orbit,
      );
      final sizeValue = 2.2 + rng.nextDouble() * 4.8;
      final alpha = 0.25 + (math.sin(progress * math.pi * 2 + i) + 1) * 0.22;
      canvas.drawCircle(
        point,
        sizeValue,
        Paint()
          ..color = (i.isEven ? BridgeDS.textPrimary : color).withValues(
            alpha: alpha,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SummonRewardPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.seed != seed;
  }
}

const _defaultSheetPoses = [
  // [教練 Agent 2026-06-29] 刪除「待機」— 主形象圖即為待機圖，只需 8 張狀態圖
  _SheetPose(
    key: 'reading',
    label: '閱讀',
    behavior: '整理上下文與記憶，像在翻閱筆記或光頁。',
    expression: '專注、沉穩、思考中。',
    triggerScene: '正在讀取、整理、摘要、壓縮上下文或檢查資料時。',
    triggerKeywords: ['整理', '摘要', '讀一下', '幫我看'],
    intentTags: ['reading', 'research', 'summarize', 'context'],
    priority: 50,
    cooldownSeconds: 10,
    fallbackStateId: 'idle',
    kind: 'core',
    icon: Icons.menu_book_outlined,
    mood: AgentCompanionMood.focused,
    action: AgentCompanionAction.reading,
  ),
  _SheetPose(
    key: 'writing',
    label: '編寫中',
    behavior: '用電腦或筆記本把想法整理成文字、程式或草稿。',
    expression: '努力的編寫樣子。',
    triggerScene: '當 Agent 正在代碼、寫程式、寫文案、寫草稿或執行內容產出時。',
    triggerKeywords: ['編輯', '寫', '執行', '程式', '文案'],
    intentTags: ['writing', 'coding', 'drafting', 'execution'],
    priority: 70,
    cooldownSeconds: 8,
    fallbackStateId: 'reading',
    kind: 'core',
    icon: Icons.edit_note_outlined,
    mood: AgentCompanionMood.focused,
    action: AgentCompanionAction.reading,
  ),
  _SheetPose(
    key: 'stuck',
    label: '卡住了',
    behavior: '苦惱中雙手交在胸前，正在重新思考問題。',
    expression: '苦惱中的樣子。',
    triggerScene: '遇到卡點、等待外部條件、需要使用者補充，或重複錯誤循環時。',
    triggerKeywords: ['卡住了', '卡點', '失敗', '錯誤', '等等'],
    intentTags: ['blocked', 'waiting', 'error', 'needs_input'],
    priority: 85,
    cooldownSeconds: 14,
    fallbackStateId: 'reading',
    kind: 'core',
    icon: Icons.sentiment_dissatisfied_outlined,
    mood: AgentCompanionMood.waiting,
    action: AgentCompanionAction.standing,
  ),
  _SheetPose(
    key: 'idea',
    label: '有好點子了',
    behavior: '一隻手指向上方，上方有一個發亮的燈泡。',
    expression: '微笑、驚喜、調皮。',
    triggerScene: '有好主意、好點子、好方法出現，或找到正確方向時。',
    triggerKeywords: ['好點子', '好方法', '靈感', '想到', '正確方向'],
    intentTags: ['idea', 'insight', 'solution', 'breakthrough'],
    priority: 88,
    cooldownSeconds: 16,
    fallbackStateId: 'pointing',
    kind: 'core',
    icon: Icons.emoji_objects_outlined,
    mood: AgentCompanionMood.proud,
    action: AgentCompanionAction.pointing,
  ),
  _SheetPose(
    key: 'pointing',
    label: '指路',
    behavior: '伸手指向下一座橋或下一個任務方向。',
    expression: '清楚、有方向感、帶著鼓勵。',
    triggerScene: '正在判斷下一步、選工具、帶路或給使用者建議時。',
    triggerKeywords: ['下一步', '怎麼做', '帶我', '建議'],
    intentTags: ['route', 'next_step', 'guide'],
    priority: 60,
    cooldownSeconds: 12,
    fallbackStateId: 'reading',
    kind: 'core',
    icon: Icons.assistant_direction_outlined,
    mood: AgentCompanionMood.routing,
    action: AgentCompanionAction.pointing,
  ),
  _SheetPose(
    key: 'bridging',
    label: '橋接',
    behavior: '正在連接外部能力，身邊有穩定發光或能量流。',
    expression: '認真、可靠、正在施展能力。',
    triggerScene: '正在呼叫 API、連接外部服務、生成圖片或執行橋接任務時。',
    triggerKeywords: ['連接', '生成', '呼叫', '橋接'],
    intentTags: ['tool_call', 'api', 'external_service', 'generate'],
    priority: 80,
    cooldownSeconds: 8,
    fallbackStateId: 'reading',
    kind: 'core',
    icon: Icons.account_tree_outlined,
    mood: AgentCompanionMood.bridging,
    action: AgentCompanionAction.spinning,
  ),
  _SheetPose(
    key: 'celebrating',
    label: '慶祝',
    behavior: '任務完成後小幅跳起、揮手或發光。',
    expression: '開心、得意、像完成一件好事。',
    triggerScene: '任務完成、使用者稱讚、成果已生成或需要正向回饋時。',
    triggerKeywords: ['完成', '成功', '太棒了', '漂亮'],
    intentTags: ['celebration', 'success', 'completed'],
    priority: 90,
    cooldownSeconds: 20,
    fallbackStateId: 'idle',
    kind: 'core',
    icon: Icons.celebration_outlined,
    mood: AgentCompanionMood.proud,
    action: AgentCompanionAction.bouncing,
  ),
  _SheetPose(
    key: 'wandering',
    label: '漫遊',
    behavior: '平時在桌面自由走動，帶一點俏皮的小動作。',
    expression: '好奇、輕鬆、正在探索。',
    triggerScene: '平時陪伴、輕鬆探索、等待使用者或剛開始理解意圖時。',
    triggerKeywords: ['隨便逛逛', '陪我', '放輕鬆'],
    intentTags: ['explore', 'casual', 'companion'],
    priority: 20,
    cooldownSeconds: 8,
    fallbackStateId: 'idle',
    kind: 'core',
    icon: Icons.explore_outlined,
    mood: AgentCompanionMood.curious,
    action: AgentCompanionAction.wandering,
  ),
];

class _SheetPose {
  final String key;
  final String label;
  final String behavior;
  final String expression;
  final String triggerScene;
  final List<String> triggerKeywords;
  final List<String> intentTags;
  final int priority;
  final int cooldownSeconds;
  final String fallbackStateId;
  final String kind;
  final IconData icon;
  final AgentCompanionMood mood;
  final AgentCompanionAction action;

  const _SheetPose({
    required this.key,
    required this.label,
    required this.behavior,
    required this.expression,
    required this.triggerScene,
    required this.triggerKeywords,
    required this.intentTags,
    required this.priority,
    required this.cooldownSeconds,
    required this.fallbackStateId,
    required this.kind,
    required this.icon,
    required this.mood,
    required this.action,
  });

  String get detail => '$behavior；$expression';

  _SheetPose copyWith({
    String? label,
    String? behavior,
    String? expression,
    String? triggerScene,
    List<String>? triggerKeywords,
  }) {
    return _SheetPose(
      key: key,
      label: label ?? this.label,
      behavior: behavior ?? this.behavior,
      expression: expression ?? this.expression,
      triggerScene: triggerScene ?? this.triggerScene,
      triggerKeywords: triggerKeywords ?? this.triggerKeywords,
      intentTags: intentTags,
      priority: priority,
      cooldownSeconds: cooldownSeconds,
      fallbackStateId: fallbackStateId,
      kind: kind,
      icon: icon,
      mood: mood,
      action: action,
    );
  }

  CompanionAssetStateSpec toAssetStateSpec({
    String? imagePath,
    String? prompt,
  }) {
    return CompanionAssetStateSpec(
      stateId: key,
      label: label,
      kind: kind,
      behavior: behavior,
      expression: expression,
      mood: mood,
      action: action,
      imagePath: imagePath,
      prompt: prompt,
      trigger: CompanionAssetTriggerRule(
        keywords: triggerKeywords,
        stages: [mood.name, action.name],
        intentTags: intentTags,
        scene: triggerScene,
        priority: priority,
        cooldownSeconds: cooldownSeconds,
        fallbackStateId: fallbackStateId,
      ),
    );
  }
}

_SheetPose _sheetPoseFromManifestState(Map<dynamic, dynamic> state) {
  final stateId = _stringFrom(state['stateId'], fallback: '${state['id']}');
  final fallback = _defaultSheetPoses.firstWhere(
    (pose) => pose.key == stateId,
    orElse: () => _defaultSheetPoses.first,
  );
  final trigger = state['trigger'] is Map
      ? Map<dynamic, dynamic>.from(state['trigger'] as Map)
      : const <dynamic, dynamic>{};
  final keywords = trigger['keywords'] is List
      ? [
          for (final keyword in trigger['keywords'] as List)
            if (_stringFrom(keyword).isNotEmpty) _stringFrom(keyword),
        ]
      : fallback.triggerKeywords;
  final intentTags = trigger['intentTags'] is List
      ? [
          for (final tag in trigger['intentTags'] as List)
            if (_stringFrom(tag).isNotEmpty) _stringFrom(tag),
        ]
      : fallback.intentTags;

  return _SheetPose(
    key: stateId.isEmpty ? fallback.key : stateId,
    label: _stringFrom(state['label'], fallback: fallback.label),
    behavior: _stringFrom(state['behavior'], fallback: fallback.behavior),
    expression: _stringFrom(state['expression'], fallback: fallback.expression),
    triggerScene: _stringFrom(
      trigger['scene'],
      fallback: fallback.triggerScene,
    ),
    triggerKeywords: keywords,
    intentTags: intentTags,
    priority:
        int.tryParse(_stringFrom(trigger['priority'])) ?? fallback.priority,
    cooldownSeconds:
        int.tryParse(_stringFrom(trigger['cooldownSeconds'])) ??
        fallback.cooldownSeconds,
    fallbackStateId: _stringFrom(
      trigger['fallbackStateId'],
      fallback: fallback.fallbackStateId,
    ),
    kind: _stringFrom(state['kind'], fallback: fallback.kind),
    icon: fallback.icon,
    mood: AgentCompanionMood.values.firstWhere(
      (mood) => mood.name == _stringFrom(state['mood']),
      orElse: () => fallback.mood,
    ),
    action: AgentCompanionAction.values.firstWhere(
      (action) => action.name == _stringFrom(state['action']),
      orElse: () => fallback.action,
    ),
  );
}

// [教練 Agent 2026-08-12] 移除舊的 _imageModelOptions / _ImageModelOption —— 改由 ImageProviderResolver 從金鑰自動選出最高階圖像引擎。

class _ReferenceClueImage {
  final String id;
  final String name;
  final String value;
  final String sourceLabel;

  const _ReferenceClueImage({
    required this.id,
    required this.name,
    required this.value,
    required this.sourceLabel,
  });
}

enum _PackImportAction { pickFile, pasteJson }

// [教練 Agent 2026-08-12] 圖像引擎選擇按鈕 —— 使用 ResolvedImageModel（從金鑰自動偵測）
class _ImageEngineButton extends StatelessWidget {
  final ResolvedImageModel model;
  final bool selected;
  final VoidCallback onPressed;

  const _ImageEngineButton({
    required this.model,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? BridgeDSColors.of(context).accentBlue
        : BridgeDSColors.of(context).textSecondary;
    return Material(
      color: selected
          ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.10)
          : BridgeDSColors.of(context).surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Container(
          constraints: const BoxConstraints(minHeight: 70),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(
              color: selected
                  ? BridgeDSColors.of(context).accentBlue
                  : BridgeDSColors.of(
                      context,
                    ).accentBlue.withValues(alpha: 0.20),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      model.adapterName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tierBasedStyle(
                        context,
                        Tier.numericEmphasis,
                        color: selected
                            ? BridgeDSColors.of(context).textPrimary
                            : BridgeDSColors.of(context).textSecondary,
                      ),
                    ),
                    Text(
                      model.defaultModel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(
                        context,
                        Tier.cardCaptionBold,
                      ).toTextStyle().copyWith(color: color, fontSize: 10),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle,
                  color: BridgeDSColors.of(context).accentBlue,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummonPreset {
  final String label;
  final IconData icon;
  final CompanionSummoningClues clues;

  _SummonPreset({required this.label, required this.icon, required this.clues});
}

class _SummonCircleButton extends StatelessWidget {
  final _SummonPreset preset;
  final bool selected;
  final VoidCallback onPressed;

  _SummonCircleButton({
    required this.preset,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.08)
          : BridgeDSColors.of(
              context,
            ).surface, // [教練 Agent 2026-08-03] R1: 修 textPrimary 誤用為背景
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(
              color: selected
                  ? BridgeDSColors.of(context).accentBlue
                  : BridgeDSColors.of(
                      context,
                    ).accentBlue.withValues(alpha: 0.34),
              width: selected ? 2 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: BridgeDSColors.of(
                  context,
                ).accentBlue.withValues(alpha: selected ? 0.12 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: selected
                      ? BridgeDSColors.of(
                          context,
                        ).accentBlue.withValues(alpha: 0.16)
                      : BridgeDSColors.of(
                          context,
                        ).accentBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  preset.icon,
                  size: 18,
                  color: BridgeDSColors.of(context).accentBlue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preset.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tierBasedStyle(
                    context,
                    Tier.blockSubheading,
                    fontWeight: FontWeight.w900,
                  ).copyWith(fontSize: 16),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  Icons.check_circle,
                  size: 18,
                  color: BridgeDSColors.of(context).accentBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
