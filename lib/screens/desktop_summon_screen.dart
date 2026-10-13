// Desktop Summon Screen — 桌面版召喚夥伴頁
// 完整重寫：包含手機版所有欄位和功能，重新設計為桌面專用佈局
// [2026-07-17] 桌面專用佈局：左側表單 + 右側即時預覽，不用 Stepper
//
// 手機版所有欄位已完整帶入：
// - 10+ 個文字輸入欄位（靈感、特殊功能、說話風格、性格、專長、習慣、關係、美術風格、物種、自由描述）
// - 預設標籤選擇（preset）
// - 名字輸入
// - BridgeActionExecutor.generateImage 真實圖片生成
// - 4 階段進度條（發送 API / 等待 / 去背 / 完成）
// - 防休眠提示（桌面版改為「不要切換應用程式」）
// - 圖片模型選擇（最強/標準/省錢）
// - 生成失敗 fallback 預覽
// - 視覺審核結果顯示
// - 狀態圖組（sheet poses）生成
// - 重新生成（reroll）功能
// - 參考圖檔線索上傳
// - 匯入/匯出角色資產包

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // [WS-1b 2026-09-13] 打包指令複製到剪貼簿
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent_activity.dart';
import '../models/bridge_action.dart';
import '../models/companion.dart';
import '../services/bridge_action_executor.dart';
import '../services/companion_asset_manifest_service.dart';
import '../services/companion_pack_service.dart';
import '../services/companion_store.dart';
import '../services/companion_summoning_service.dart';
import '../services/image_provider_resolver.dart';
import '../services/semi_dao_review_store.dart';
import '../services/semi_dao_visual_review_service.dart';
import '../theme/bridge_design_system.dart';
import '../theme/bridge_motion.dart';
import '../widgets/companion_art.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

class DesktopSummonScreen extends StatefulWidget {
  const DesktopSummonScreen({
    super.key,
    this.editingCompanionId,
    this.bridgeActionExecutor,
    this.imageGenerationTimeout = const Duration(seconds: 180),
    this.returnTo,
  });

  final String? editingCompanionId;
  final BridgeActionExecutor? bridgeActionExecutor;
  final Duration imageGenerationTimeout;
  final String? returnTo;

  @override
  State<DesktopSummonScreen> createState() => _DesktopSummonScreenState();
}

class _DesktopSummonScreenState extends State<DesktopSummonScreen>
    with WidgetsBindingObserver {
  // 文字輸入欄位
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

  // 服務
  final _summoningService = CompanionSummoningService();
  final _primaryVisualReviewService = const SemiDaoVisualReviewService();
  final _defaultBridgeActionExecutor = BridgeActionExecutor();

  BridgeActionExecutor get _bridgeActionExecutor =>
      widget.bridgeActionExecutor ?? _defaultBridgeActionExecutor;

  // 狀態
  Companion? _editingCompanion;
  CompanionSummoningCandidate? _candidate;
  bool _isSummoning = false;
  int _summonProgress = 0; // 0=閒置, 1=發送API, 2=等待生成, 3=去背處理, 4=完成
  bool _isReviewingPrimaryImage = false;
  SemiDaoVisualReviewResult? _primaryVisualReview;
  CompanionRightsPassport? _primaryRightsPassport;

  // 狀態圖組
  final Set<String> _generatingSheetKeys = <String>{};
  final Set<String> _timedOutGenerations = <String>{};
  final Set<String> _expandedSheetKeys = <String>{};
  List<_SheetPose> _sheetStates = List<_SheetPose>.of(_defaultSheetPoses);

  // 參考圖
  final List<_ReferenceClueImage> _referenceImages = <_ReferenceClueImage>[];

  // [教練 Agent 2026-08-12] 圖像引擎自動偵測（從已設定金鑰的 provider）
  List<ResolvedImageModel> _availableImageModels = [];
  ResolvedImageModel? _resolvedImageModel;

  // 預設範本
  String? _selectedPresetLabel;

  // 重新生成
  int _rerollSalt = 0;
  bool _candidatePackSaved = false;

  // 草稿保存
  static const _draftKey = 'companion_create_draft_desktop_v1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // [教練 Agent 2026-08-12] 啟動時偵測可用圖像引擎
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resolveImageModels();
    });
    final editingId = widget.editingCompanionId?.trim();
    if (editingId != null && editingId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadCompanionForEditing(editingId);
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreDraftIfAvailable();
    });
  }

  @override
  void dispose() {
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveDraft();
    } else if (state == AppLifecycleState.resumed) {
      _checkInterruptedGenerations();
    }
  }

  Future<void> _loadCompanionForEditing(String companionId) async {
    final companion = CompanionStore().getById(companionId);
    if (companion == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到要編輯的夥伴。')),
      );
      return;
    }
    _editingCompanion = companion;
    final packJson = CompanionStore().exportCompanionPackToJson(companion.id);
    await _importPackJson(packJson, showSnackBar: false, markPackSaved: true);
    if (!mounted) return;
    setState(() {
      _editingCompanion = companion;
      _primaryRightsPassport = companion.rightsPassport;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已載入 ${companion.name}，可以繼續調整。')),
    );
  }

  void _checkInterruptedGenerations() {
    if (_candidate == null) return;
    if (_generatingSheetKeys.isNotEmpty) return;
    final allDone = _sheetStates.every(
      (pose) =>
          _candidate?.generatedSheetImagePaths[pose.key]?.trim().isNotEmpty ==
          true,
    );
    if (allDone) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('上次生成中斷了，要繼續嗎？'),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: '重試',
          onPressed: _retryMissingSheetImages,
        ),
      ),
    );
  }

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
            .map((r) => {
                  'id': r.id,
                  'name': r.name,
                  'value': r.value,
                  'sourceLabel': r.sourceLabel
                })
            .toList();
      }
      draft['sheetStates'] = _sheetStates
          .map((s) => {
                'key': s.key,
                'label': s.label,
                'behavior': s.behavior,
                'expression': s.expression,
                'triggerScene': s.triggerScene,
                'triggerKeywords': s.triggerKeywords,
              })
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

      final savedAt = draft['savedAt'] as String?;
      if (savedAt != null) {
        final age = DateTime.now().difference(DateTime.parse(savedAt));
        if (age.inHours > 24) {
          await prefs.remove(_draftKey);
          return;
        }
      }

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

      final refImages = draft['referenceImages'] as List<dynamic>?;
      if (refImages != null) {
        _referenceImages.clear();
        for (final item in refImages) {
          final m = item as Map<String, dynamic>;
          _referenceImages.add(_ReferenceClueImage(
            id: m['id'] as String,
            name: m['name'] as String,
            value: m['value'] as String,
            sourceLabel: m['sourceLabel'] as String,
          ));
        }
      }

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

      final candidateJson = draft['candidate'] as Map<String, dynamic>?;
      if (candidateJson != null) {
        final candidate = _summoningService.summon(
          _readClues(),
          salt: candidateJson['seed'] as int?,
        );
        final restoredPrimaryPath =
            candidateJson['generatedImagePath'] as String?;
        final validPrimaryPath = (restoredPrimaryPath != null &&
                restoredPrimaryPath.trim().isNotEmpty &&
                File(restoredPrimaryPath).existsSync())
            ? restoredPrimaryPath
            : null;
        final rawSheetPaths = Map<String, String>.from(
            candidateJson['generatedSheetImagePaths'] as Map? ?? {});
        final validSheetPaths = Map<String, String>.fromEntries(
          rawSheetPaths.entries.where(
            (e) => e.value.trim().isNotEmpty && File(e.value).existsSync(),
          ),
        );
        _candidate = candidate.copyWith(
          generatedImagePath: validPrimaryPath,
          generatedSheetImagePaths: validSheetPaths,
          sheetGenerationMessages: Map<String, String>.from(
              candidateJson['sheetGenerationMessages'] as Map? ?? {}),
        );
      }

      if (mounted) {
        setState(() {});
        if (_candidate != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
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

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BridgeDSColors.of(context).canvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          color: BridgeDSColors.of(context).textPrimary,
          tooltip: '返回',
          onPressed: () {
            if (widget.returnTo != null) {
              context.go(widget.returnTo!);
            } else {
              context.go('/bridge-desktop');
            }
          },
        ),
        title: Text(
          _editingCompanion == null ? '創造第一位夥伴' : '調整夥伴設定',
          style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle(),
        ),
        backgroundColor: BridgeDSColors.of(context).surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BridgeDS.spaceXL),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左欄：表單區
                    Expanded(
                      flex: 3,
                      child: _buildFormColumn(),
                    ),
                    const SizedBox(width: BridgeDS.spaceXL),
                    // 右欄：預覽區
                    Expanded(
                      flex: 2,
                      child: _buildPreviewColumn(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 左欄：表單區
  // ═══════════════════════════════════════════════════

  Widget _buildFormColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 匯入角色包
        _buildImportPackEntryPanel(),
        SizedBox(height: BridgeDS.spaceLG),

        // 預設範本選擇
        // [Blue UX 2026-09-17] 編輯模式下不顯示範本——按下去會洗掉已設定的
        // 線索（地雷）；範本是「創造新夥伴」的起點，不是「編輯既有夥伴」的工具
        if (_editingCompanion == null) ...[
          _buildArchetypePresets(),
          SizedBox(height: BridgeDS.spaceLG),
        ],

        // 隨機點子按鈕
        OutlinedButton.icon(
          onPressed: _randomizeClues,
          icon: const Icon(Icons.casino_outlined, size: 16),
          label: const Text('隨機給我點子'),
          style: OutlinedButton.styleFrom(
            foregroundColor: BridgeDSColors.of(context).accentMiro,
            side: BorderSide(color: BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.4)),
          ),
        ),
        const SizedBox(height: BridgeDS.spaceXL),

        // 基本資料
        _buildSectionHeader('基本資料'),
        const SizedBox(height: BridgeDS.spaceMD),
        _buildTextField('名字', _nameController, '可留空，由生成結果命名'),
        _buildTextField('人物名人靈感', _inspirationController, '像某種氣質、角色原型或傳說'),
        _buildTextField('特殊功能', _specialFunctionController, '例如：替我開通新 AI 服務'),
        const SizedBox(height: BridgeDS.spaceXL),

        // 個性設定
        _buildSectionHeader('個性設定'),
        const SizedBox(height: BridgeDS.spaceMD),
        _buildTextField('說話風格', _speakingStyleController, '溫暖短句、精準直接、幽默吐槽'),
        _buildTextField('個性', _personalityController, '好奇、可靠、搞笑、守護、冷靜'),
        _buildTextField('專長', _expertiseController, '研究、寫作、工具導航、創意發想'),
        _buildTextField('習慣', _habitController, '思考時發光、閒著會散步'),
        _buildTextField('與使用者的關係', _relationshipController, '搭檔、朋友、守護者、小助理'),
        const SizedBox(height: BridgeDS.spaceXL),

        // 造型與視覺
        _buildSectionHeader('造型與視覺'),
        const SizedBox(height: BridgeDS.spaceMD),
        _buildTextField('畫風', _artStyleController, '遊戲角色設定圖、2D 動畫、像素寵物'),
        _buildTextField('種族', _speciesController, '光靈、機械妖精、星塵使者'),
        _buildTextField(
          '自由敘述',
          _freeformController,
          '建議 20 字左右，例如：需要嚴謹時找我，會提醒風險',
          maxLines: 3,
        ),
        const SizedBox(height: BridgeDS.spaceMD),
        // [H3 2026-10-08] 靈魂文檔——人格最深處，注入 system prompt 最頂層
        _buildTextField(
          '靈魂文檔 SOUL',
          _soulMdController,
          'Markdown。核心身份層（先於角色與風格）。Hermes 移民用：貼上 SOUL.md',
          maxLines: 8,
        ),
        SizedBox(height: BridgeDS.spaceLG),

        // 圖片模型選擇
        _buildImageModelSelector(),
        SizedBox(height: BridgeDS.spaceLG),

        // 參考圖檔線索
        _buildReferenceImagePicker(),
        SizedBox(height: BridgeDS.spaceXXL),

        // 主要操作按鈕
        _buildMainActions(),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).accentMiro,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title, style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  // 右欄：預覽區
  // ═══════════════════════════════════════════════════

  Widget _buildPreviewColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 候選預覽或佔位圖
        if (_candidate != null) ...[
          _buildCandidatePreview(_candidate!),
        ] else ...[
          _buildPlaceholderPreview(),
        ],

        // 生成進度條
        if (_isSummoning) ...[
          SizedBox(height: BridgeDS.spaceLG),
          _buildSummonProgressBar(),
          SizedBox(height: BridgeDS.spaceMD),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
              border: Border.all(
                color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.desktop_windows,
                  size: 16,
                  color: BridgeDSColors.of(context).accentYellow,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '正在生成主形象，請保持螢幕開啟。\n不要讓電腦休眠或切換應用程式，以免中斷。',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentYellow,
                      height: 1.3,
                      fontWeight: FontWeight.w600,),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 狀態圖組預覽（只有生成主形象後才顯示）
        if (_candidate != null &&
            _candidate!.generatedImagePath?.trim().isNotEmpty == true) ...[
          SizedBox(height: BridgeDS.spaceXL),
          _buildSheetPreview(_candidate!),
        ],
      ],
    );
  }

  Widget _buildPlaceholderPreview() {
    final clues = _readClues();
    final previewName =
        clues.name.trim().isEmpty ? '山門光靈' : clues.name.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BridgeDS.spaceLG),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [BridgeDSColors.of(context).accentMiro, BridgeDSColors.of(context).accentGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(BridgeDS.roundWide),
        boxShadow: [
          BoxShadow(
            color: BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.2),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: BridgeDSColors.of(context).textPrimary,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                '形象預覽',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                  fontWeight: FontWeight.w900,),
              ),
            ],
          ),
          SizedBox(height: 16),
          Center(
            child: CompanionArt(
              mbtiCode: 'ENFJ',
              seed: _rerollSalt + 42,
              name: previewName,
              mood: AgentCompanionMood.curious,
              action: AgentCompanionAction.wandering,
              size: 320,
            ),
          ),
          SizedBox(height: 16),
          Text(
            previewName,
            style: TextStyle(
              color: BridgeDSColors.of(context).textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '等待線索凝聚',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidatePreview(CompanionSummoningCandidate candidate) {
    final mbti =
        MBTIType.fromCode(candidate.mbtiCode) ?? MBTIType.allTypes.first;
    final imagePath = candidate.generatedImagePath;
    final hasImage = imagePath != null && imagePath.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BridgeDS.spaceLG),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundWide),
        border: Border.all(color: BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(
            color: BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 圖片或佔位圖
          Center(
            child: hasImage
                ? Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.all(BridgeDS.spaceMD),
                    decoration: BoxDecoration(
                      color: BridgeDSColors.of(context).canvas,
                      borderRadius:
                          BorderRadius.circular(BridgeDS.roundComfortable),
                      border: Border.all(
                          color: BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.18)),
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
                            child: SizedBox.square(
                              dimension: previewSize,
                              child: _buildGeneratedImage(imagePath),
                            ),
                          );
                        },
                      ),
                    ),
                  )
                : CompanionArt(
                    mbtiCode: candidate.mbtiCode,
                    seed: candidate.seed,
                    name: candidate.name,
                    mood: AgentCompanionMood.curious,
                    action: AgentCompanionAction.wandering,
                    size: 280,
                  ),
          ),

          // 視覺生成狀態
          if (candidate.visualGenerationMessage != null) ...[ 
            SizedBox(height: BridgeDS.spaceMD),
            _buildVisualGenerationStatus(candidate),
          ],

          // 視覺審核狀態
          if (hasImage) ...[
            SizedBox(height: BridgeDS.spaceMD),
            _buildPrimaryReviewStatus(),
          ],

          SizedBox(height: BridgeDS.spaceLG),

          // 名字和描述
          Text(
            candidate.name,
            style: TierStyle.of(context, Tier.appHeadline).toTextStyle(),
          ),
          SizedBox(height: BridgeDS.spaceSM),
          Text(
            '${mbti.code} ${mbti.name} · ${candidate.role.name}',
            style: BridgeDSColors.of(context).body.copyWith(color: BridgeDSColors.of(context).textSecondary),
          ),
          SizedBox(height: BridgeDS.spaceMD),
          // [教練 Agent 2026-08-14] 改 SelectableText — 讓使用者可以選取複製角色描述
          SelectableText(
            candidate.appearanceDescription,
            style: BridgeDSColors.of(context).body.copyWith(
              color: BridgeDSColors.of(context).textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: BridgeDS.spaceLG),

          // [小葵 2026-09-14] 單獨重生主形象——保留骨架只換圖（Blue 要求）
          // [Blue UX 2026-09-17] 無圖時「更要」顯示——匯入的夥伴沒有主形象時，
          // 這是唯一的逃生門（有圖才給按鈕＝雞生蛋死鎖：沒圖→不能生成→永遠沒圖）
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSummoning ? null : _rerollPrimaryImageOnly,
              icon: const Icon(Icons.image_search, size: 16),
              label: Text(hasImage ? '重新生成主形象' : '生成主形象'),
            ),
          ),
          const SizedBox(height: BridgeDS.spaceSM),

          // 操作按鈕
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _candidate = null;
                    _candidatePackSaved = false;
                    _primaryVisualReview = null;
                    _primaryRightsPassport = null;
                    _isReviewingPrimaryImage = false;
                  }),
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('調整線索'),
                ),
              ),
              const SizedBox(width: BridgeDS.spaceSM),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _rerollCandidate,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重新生成'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratedImage(String imagePath,
      {BoxFit fit = BoxFit.contain}) {
    if (imagePath.startsWith('http')) {
      return Image.network(imagePath, fit: fit);
    }
    if (imagePath.startsWith('data:image/')) {
      try {
        final commaIndex = imagePath.indexOf(',');
        final payload =
            commaIndex == -1 ? imagePath : imagePath.substring(commaIndex + 1);
        return Image.memory(base64Decode(payload), fit: fit);
      } catch (_) {
        return Container(
          color: BridgeDSColors.of(context).canvas,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: Text(
            '圖片資料無法讀取，請重新匯入或重新生成。',
            textAlign: TextAlign.center,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
          ),
        );
      }
    }
    if (kIsWeb) {
      return Container(
        color: BridgeDSColors.of(context).canvas,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Text(
          '圖片已生成，但開發預覽環境無法直接讀取本機檔案。請在桌面 APP 查看。',
          textAlign: TextAlign.center,
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
        ),
      );
    }
    return Image.file(File(imagePath), fit: fit);
  }

  Widget _buildVisualGenerationStatus(CompanionSummoningCandidate candidate) {
    final generated = candidate.generatedImagePath != null;
    final color = generated ? BridgeDSColors.of(context).accentGreen : BridgeDSColors.of(context).accentYellow;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(
            generated ? Icons.image_outlined : Icons.info_outline,
            color: color,
            size: 18,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              generated
                  ? '已使用圖片生成能力建立候選形象。'
                  : candidate.visualGenerationMessage!,
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(height: 1.35,
                color: BridgeDSColors.of(context).textSecondary,
                fontWeight: FontWeight.w700,),
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
    final canReview = candidate?.generatedImagePath?.trim().isNotEmpty == true &&
        !_isReviewingPrimaryImage;
    final color = _isReviewingPrimaryImage
        ? BridgeDSColors.of(context).accentMiro
        : switch (signal) {
            CompanionRightsSignal.approved => BridgeDSColors.of(context).accentGreen,
            CompanionRightsSignal.watching => BridgeDSColors.of(context).accentYellow,
            CompanionRightsSignal.blocked => BridgeDSColors.of(context).accentRed,
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
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
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
                CompanionRightsSignal.approved =>
                  Icons.verified_user_outlined,
                CompanionRightsSignal.watching =>
                  Icons.warning_amber_outlined,
                CompanionRightsSignal.blocked => Icons.block_outlined,
                _ => Icons.shield_outlined,
              },
              color: color,
              size: 18,
            ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: color,
                    fontWeight: FontWeight.w900,),
                ),
                SizedBox(height: 0),
                Text(
                  detail,
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(height: 1.35,
                    color: BridgeDSColors.of(context).textSecondary,
                    fontWeight: FontWeight.w700,),
                ),
                if (canReview) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _reviewPrimaryCandidateImage(candidate!),
                    icon: const Icon(Icons.fact_check_outlined, size: 17),
                    label: Text(
                      signal == null || signal == CompanionRightsSignal.unreviewed
                          ? '立即預審主形象'
                          : '重新預審主形象',
                      style: BridgeDSColors.of(context).small,
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

  // ═══════════════════════════════════════════════════
  // 狀態圖組預覽
  // ═══════════════════════════════════════════════════

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
      padding: const EdgeInsets.all(BridgeDS.spaceLG),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundWide),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '角色造型圖組',
                  style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle(),
                ),
              ),
              Text(
                '$generatedCount 圖',
                style: BridgeDSColors.of(context).body.copyWith(
                  fontWeight: FontWeight.w900,
                  color: BridgeDSColors.of(context).accentMiro,
                ),
              ),
            ],
          ),
          SizedBox(height: BridgeDS.spaceSM),
          Text(
            '依照上方候選形象，延展成桌面夥伴工作時會用到的透明背景狀態圖。',
            style: BridgeDSColors.of(context).small.copyWith(
              color: BridgeDSColors.of(context).textSecondary,
              height: 1.35,
            ),
          ),
          SizedBox(height: BridgeDS.spaceMD),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: isGeneratingAny
                      ? null
                      : () => _generateAllSheetImages(candidate),
                  icon: Icon(isGeneratingAny ? Icons.hourglass_top : Icons.auto_awesome_motion, size: 16),
                  label: Text(isGeneratingAny ? '圖組生成中' : '生成全部圖組'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BridgeDSColors.of(context).accentMiro,
                  ),
                ),
              ),
              SizedBox(width: BridgeDS.spaceSM),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addSheetState,
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                  label: const Text('新增狀態圖'),
                ),
              ),
            ],
          ),
          if (isGeneratingAny) ...[
            SizedBox(height: BridgeDS.spaceMD),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: poses.isEmpty ? 0 : generatedCount / poses.length,
                backgroundColor: BridgeDSColors.of(context).borderSubtle,
                valueColor: AlwaysStoppedAnimation(BridgeDSColors.of(context).accentMiro),
              ),
            ),
            SizedBox(height: BridgeDS.spaceSM),
            Text(
              '生成進度：$generatedCount / ${poses.length} 張',
              style: BridgeDSColors.of(context).small.copyWith(
                  color: BridgeDSColors.of(context).textSecondary, fontWeight: FontWeight.w600),
            ),
          ],
          SizedBox(height: BridgeDS.spaceLG),
          // 2 列網格
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(poses.length, (index) {
              final pose = poses[index];
              return SizedBox(
                width: (MediaQuery.of(context).size.width * 0.4 - 80) / 2,
                child: _buildSheetPoseTile(candidate, pose, index),
              );
            }),
          ),
          SizedBox(height: BridgeDS.spaceMD),
          Text(
            generatedCount == poses.length
                ? '狀態圖已完成；未來動態插件會沿用這些狀態與觸發規則。'
                : '可以逐張調整狀態名稱、行為內容、表情、出現時機與觸發關鍵字，再生成或重生每一張。',
            style: BridgeDSColors.of(context).small.copyWith(
              color: BridgeDSColors.of(context).textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: BridgeDS.spaceXL),
          // 資產包操作
          _buildPackActionPanel(candidate),
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
    final isProblemMessage = message != null &&
        (message.contains('失敗') ||
            message.contains('尚未完成') ||
            message.contains('逾時'));

    final isExpanded = _expandedSheetKeys.contains(pose.key);

    return Container(
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(
          color: isGenerated
              ? BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.34)
              : BridgeDSColors.of(context).borderDefault,
        ),
      ),
      child: Column(
        children: [
          // 圖片區（固定 1:1 比例）
          AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(BridgeDS.roundComfortable),
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
                    padding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          BridgeDSColors.of(context).surfaceGlass,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
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
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: BridgeDSColors.of(context).textPrimary.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isExpanded ? Icons.keyboard_arrow_up : Icons.tune,
                              size: 18,
                              color: BridgeDSColors.of(context).textPrimary,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(pose.icon, size: 16, color: BridgeDSColors.of(context).textPrimary),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pose.label,
                            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800,
                              color: BridgeDSColors.of(context).textPrimary,),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 8),
                        GestureDetector(
                          onTap: isGenerating
                              ? null
                              : () => _generateSheetImage(candidate, pose),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: BridgeDSColors.of(context).textPrimary.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                            child: isGenerating
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: BridgeDSColors.of(context).textPrimary,
                                    ),
                                  )
                                : Icon(
                                    isGenerated
                                        ? Icons.refresh
                                        : Icons.add_photo_alternate_outlined,
                                    size: 18,
                                    color: BridgeDSColors.of(context).textPrimary,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (message != null && (!isGenerated || isProblemMessage))
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: BridgeDSColors.of(context).accentRed.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 展開區：文字欄位
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.all(8),
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
                                triggerKeywords: _splitTriggerInput(value)),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Icon(pose.icon, color: BridgeDSColors.of(context).textSecondary, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pose.label,
                      style: TextStyle(
                        color: BridgeDSColors.of(context).textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: BridgeDSColors.of(context).textSecondary),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: _buildGeneratedImage(imagePath),
                ),
              ),
            ),
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
      style: BridgeDSColors.of(context).small.copyWith(
        color: BridgeDSColors.of(context).textPrimary,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: BridgeDSColors.of(context).small.copyWith(
          color: BridgeDSColors.of(context).textSecondary,
          fontWeight: FontWeight.w800,
        ),
        floatingLabelStyle: BridgeDSColors.of(context).small.copyWith(
          color: BridgeDSColors.of(context).accentMiro,
          fontWeight: FontWeight.w900,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
        filled: true,
        fillColor: BridgeDSColors.of(context).surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          borderSide: BorderSide(color: BridgeDSColors.of(context).borderDefault),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          borderSide: BorderSide(color: BridgeDSColors.of(context).borderDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
          borderSide: BorderSide(color: BridgeDSColors.of(context).accentMiro),
        ),
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
      padding: const EdgeInsets.all(BridgeDS.spaceMD),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border:
            Border.all(color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 18,
                color: BridgeDSColors.of(context).accentMiro,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '角色資產包',
                  style: BridgeDSColors.of(context).body.copyWith(
                    color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: BridgeDS.spaceSM),
          Text(
            generatedCount == 0
                ? '可以先儲存目前線索與狀態規則；等圖組生成後再儲存，會包含更多角色圖片。'
                : '目前已包含 $generatedCount 張狀態圖、觸發規則與角色 manifest，可匯出給社群分享或日後匯入微調。',
            style: BridgeDSColors.of(context).small.copyWith(
              color: BridgeDSColors.of(context).textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: BridgeDS.spaceMD),
          Row(
            children: [
              Expanded(
                child: BridgeGlowButton(
                  onPressed: () => _exportCandidatePack(candidate),
                  label: '匯出資產包檔案',
                  icon: Icons.ios_share_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 表單欄位
  // ═══════════════════════════════════════════════════

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
        style: colors.body,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: colors.small.copyWith(color: colors.textMuted, fontSize: 14),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: colors.small.copyWith(
            fontWeight: FontWeight.w800,
            color: colors.textSecondary,
          ),
          // [教練 Agent 2026-08-10] floatingLabelStyle 讓 label 在 always 模式下保持 16px 不被縮小
          floatingLabelStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 10),
          filled: true,
          fillColor: colors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
            borderSide: BorderSide(color: colors.accentBlue.withOpacity(0.18)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
            borderSide: BorderSide(color: colors.accentBlue.withOpacity(0.18)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
            borderSide: BorderSide(color: colors.accentBlue, width: 1.4),
          ),
        ),
        onChanged: (_) => setState(() {
          _candidate = null;
          _generatingSheetKeys.clear();
          _candidatePackSaved = false;
          _primaryVisualReview = null;
          _primaryRightsPassport = null;
          _isReviewingPrimaryImage = false;
        }),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 輔助元件
  // ═══════════════════════════════════════════════════

  Widget _buildImportPackEntryPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border:
            Border.all(color: BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.move_to_inbox_outlined,
              color: BridgeDSColors.of(context).accentMiro,
              size: 19,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已有角色資產包？',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BridgeDSColors.of(context).body.copyWith(
                    color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 0),
                Text(
                  '先匯入社群分享或之前儲存的角色包，再繼續微調線索、圖片與設定。',
                  style: BridgeDSColors.of(context).small.copyWith(
                    color: BridgeDSColors.of(context).textSecondary,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _showImportPackOptions,
            icon: const Icon(Icons.move_to_inbox_outlined, size: 16),
            label: const Text('匯入角色資產包'),
            style: OutlinedButton.styleFrom(
              foregroundColor: BridgeDSColors.of(context).accentMiro,
              side: BorderSide(color: BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.4)),
            ),
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
          style: BridgeDSColors.of(context).headingS.copyWith(
            fontWeight: FontWeight.w800,
            color: BridgeDSColors.of(context).textPrimary,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '先選能力傾向，再用下面的線索調整成獨一無二的夥伴。',
          style: BridgeDSColors.of(context).small.copyWith(
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w700,
            color: BridgeDSColors.of(context).textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: presets.map((preset) {
            return SizedBox(
              width: (MediaQuery.of(context).size.width * 0.5 - 100) / 3,
              height: 54,
              child: _SummonCircleButton(
                preset: preset,
                selected: preset.label == _selectedPresetLabel,
                onPressed: () => _applyPreset(preset),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // [教練 Agent 2026-08-12] 從金鑰偵測可用圖像引擎
  Future<void> _resolveImageModels() async {
    final all = await ImageProviderResolver.resolveAll();
    if (!mounted) return;
    setState(() {
      _availableImageModels = all;
      _resolvedImageModel = all.isNotEmpty ? all.first : null;
    });
  }

  Widget _buildImageModelSelector() {
    // 0 個金鑰
    if (_availableImageModels.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surface,
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
          border: Border.all(color: BridgeDSColors.of(context).borderSubtle, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.key_off_outlined, color: BridgeDSColors.of(context).accentYellow, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '尚未設定圖像生成金鑰，請到能力中心設定。',
                style: BridgeDSColors.of(context).body.copyWith(
                  color: BridgeDSColors.of(context).textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 1 個引擎 → 唯讀
    if (_availableImageModels.length == 1) {
      final m = _availableImageModels.first;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surface,
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
          border: Border.all(color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome_outlined, color: BridgeDSColors.of(context).accentBlue, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('圖像生成引擎', style: BridgeDSColors.of(context).body.copyWith(
                    color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,
                  )),
                  Text('${m.adapterName} · ${m.defaultModel}', style: BridgeDSColors.of(context).small.copyWith(
                    color: BridgeDSColors.of(context).textSecondary,
                    fontWeight: FontWeight.w700,
                  )),
                ],
              ),
            ),
            Icon(Icons.lock_outline, size: 16, color: BridgeDSColors.of(context).textMuted),
          ],
        ),
      );
    }

    // 2+ 個引擎 → 讓用戶選
    final selected = _resolvedImageModel ?? _availableImageModels.first;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.22)),
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
                  color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.tune_outlined, color: BridgeDSColors.of(context).accentBlue, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('圖像生成引擎', style: BridgeDSColors.of(context).body.copyWith(
                      color: BridgeDSColors.of(context).textPrimary,
                      fontWeight: FontWeight.w900,
                    )),
                    Text('${_availableImageModels.length} 個可用引擎', style: BridgeDSColors.of(context).small.copyWith(
                      color: BridgeDSColors.of(context).textSecondary,
                      fontWeight: FontWeight.w700,
                    )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in _availableImageModels)
                SizedBox(
                  width: (MediaQuery.of(context).size.width * 0.5 - 150) / 3,
                  child: _ImageModelButton(
                    label: m.adapterName,
                    model: m.defaultModel,
                    selected: m.providerId == selected.providerId,
                    icon: Icons.auto_awesome_outlined,
                    onPressed: () {
                      setState(() => _resolvedImageModel = m);
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReferenceImagePicker() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border:
            Border.all(color: BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.18)),
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
                  color: BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_photo_alternate_outlined,
                  color: BridgeDSColors.of(context).accentMiro,
                  size: 20,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '參考圖檔線索',
                      style: BridgeDSColors.of(context).body.copyWith(
                        color: BridgeDSColors.of(context).textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 0),
                    Text(
                      '上傳既有角色、畫風或符號圖片，生成時會把它們當作 visual reference。',
                      style: BridgeDSColors.of(context).small.copyWith(
                        color: BridgeDSColors.of(context).textSecondary,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickReferenceImages,
                icon: const Icon(Icons.upload_file_outlined, size: 16),
                label: const Text('上傳圖檔'),
              ),
            ],
          ),
          if (_referenceImages.isNotEmpty) ...[
            SizedBox(height: 16),
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

  Widget _buildReferenceImageTile(_ReferenceClueImage image) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
            child: SizedBox(
              width: 64,
              height: 64,
              child: _buildGeneratedImage(image.value),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  image.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BridgeDSColors.of(context).small.copyWith(
                    color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  image.sourceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BridgeDSColors.of(context).labelMono.copyWith(
                    color: BridgeDSColors.of(context).textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '移除參考圖',
            onPressed: () => _removeReferenceImage(image.id),
            icon: const Icon(Icons.close, size: 20),
            color: BridgeDSColors.of(context).textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildMainActions() {
    return Column(
      children: [
        FilledButton.icon(
          onPressed: _isSummoning ? null : _summonCandidate,
          icon: Icon(_isSummoning ? Icons.hourglass_top : Icons.auto_awesome, size: 18),
          label: Text(_isSummoning ? '生成中...' : '預覽草稿'),
          style: FilledButton.styleFrom(
            backgroundColor: BridgeDSColors.of(context).accentMiro,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        if (_candidate != null) ...[
          SizedBox(height: BridgeDS.spaceMD),
          FilledButton.icon(
            onPressed: _confirmCandidate,
            icon: const Icon(Icons.check_circle, size: 18),
            label: Text(_editingCompanion == null ? '確定建立夥伴' : '更新夥伴'),
            style: FilledButton.styleFrom(
              backgroundColor: BridgeDSColors.of(context).accentGreen,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSummonProgressBar() {
    const stages = [
      '發送 API 請求',
      '等待生成圖',
      '取得生成圖後去背',
      '完成生成圖',
    ];
    final currentStage = _summonProgress.clamp(0, 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: currentStage == 0 ? null : currentStage / 4,
            backgroundColor: BridgeDSColors.of(context).borderSubtle,
            valueColor: AlwaysStoppedAnimation(BridgeDSColors.of(context).accentMiro),
          ),
        ),
        SizedBox(height: 8),
        for (var i = 0; i < stages.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 0),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: i < currentStage
                      ? Icon(Icons.check_circle,
                          size: 14, color: BridgeDSColors.of(context).accentGreen)
                      : i == currentStage
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 1.5),
                            )
                          : Icon(Icons.radio_button_unchecked,
                              size: 14,
                              color: BridgeDSColors.of(context).textMuted.withValues(alpha: 0.4)),
                ),
                SizedBox(width: 8),
                Text(
                  stages[i],
                  style: BridgeDSColors.of(context).small.copyWith(
                    color: i < currentStage
                        ? BridgeDSColors.of(context).accentGreen
                        : i == currentStage
                            ? BridgeDSColors.of(context).textPrimary
                            : BridgeDSColors.of(context).textMuted.withValues(alpha: 0.5),
                    fontWeight:
                        i == currentStage ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  // 業務邏輯（從手機版帶入）
  // ═══════════════════════════════════════════════════

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

  void _rerollCandidate() {
    _rerollSalt++;
    _summonCandidate();
  }

  /// [小葵 2026-09-14] 只重生主形象圖——保留候選骨架（名字/線索/描述），
  /// 與 _rerollCandidate（整組重骰）不同。已有主形象時先確認覆蓋。
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
        'STYLE REQUIREMENTS: friendly game character, clean readable silhouette, '
        'one complete uncropped full-body character only, zoomed-out desktop sprite composition, centered on a square canvas, transparent background, PNG sprite asset, '
        'the character and every prop must occupy only 62 to 72 percent of the canvas height; leave a large transparent safe border around the entire silhouette, '
        'the character main body mass (torso, head, and limbs) MUST be centered on the canvas — the visual center of gravity must align with the canvas center point, not offset to any side, '
        'keep the full top of hair/head, ears, hands, tail, clothing, props, both shoes, full soles, and the entire grounding shadow visible inside the canvas, '
        'feet and the oval grounding shadow must sit at least 12 percent above the bottom edge; no body part, shoe, shadow, tail, weapon, prop, scarf, or hair may touch or leave any canvas edge, '
        'if the character would touch an edge, make the character smaller rather than cropping; do not create a close-up, waist-up portrait, bust portrait, or edge-to-edge composition, '
        'include a soft oval grounding shadow directly under the character feet so it feels dimensional on a desktop window, '
        'no background scenery, suitable for a desktop companion avatar, no text, no logo, no multiple poses, no contact sheet, no storyboard. '
        // [教練 Agent 2026-08-12] 背景純白/純黑 + 角色禁用純白純黑——確保去背乾淨
        'CRITICAL COLOR RULES FOR POST-PROCESSING: '
        '(1) BACKGROUND: the background MUST be solid flat pure white (RGB 255,255,255) OR solid flat pure black (RGB 0,0,0). Fill the entire background with one solid color. No gradients, no patterns, no scenery, no environmental shadows. '
        '(2) CHARACTER CONTENT BAN: the character, clothing, props, and all visual elements MUST NOT contain pure white (RGB 255,255,255) or pure black (RGB 0,0,0) anywhere. '
        'Instead of pure white, use off-white (RGB 248,248,245) for teeth, eye whites, highlights, shine, white clothing. '
        'Instead of pure black, use very dark gray (RGB 12,12,15) for outlines, pupils, shadows, dark clothing, black hair. '
        'This ensures the background can be cleanly removed without damaging the character. '
        'The solid background will be automatically removed to produce a transparent PNG sprite.';

    try {
      setState(() => _summonProgress = 1);

      final timer2 = Timer(const Duration(seconds: 30), () {
        if (mounted && _isSummoning && _summonProgress < 2) {
          setState(() => _summonProgress = 2);
        }
      });
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

      if (mounted && _isSummoning && _summonProgress < 3) {
        setState(() => _summonProgress = 3);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
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
    final review =
        await _primaryVisualReviewService.reviewCompanionImages(tempCompanion);
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
    final poses = List<_SheetPose>.of(_sheetStates);
    final latest = _candidate;
    if (latest == null || latest.seed != candidate.seed) return;

    await Future.wait(
      poses.map((pose) => _generateSheetImage(latest, pose)),
    );
  }

  Future<void> _generateSheetImage(
    CompanionSummoningCandidate candidate,
    _SheetPose pose,
  ) async {
    if (_generatingSheetKeys.contains(pose.key)) return;
    setState(() => _generatingSheetKeys.add(pose.key));

    final prompt = _buildSheetImagePrompt(candidate, pose);
    try {
      final refPaths = (candidate.generatedImagePath != null &&
              candidate.generatedImagePath!.trim().isNotEmpty)
          ? [candidate.generatedImagePath!]
          : const <String>[];
      final result = await _executeImageGeneration(
        BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: prompt,
          provider: _resolvedImageModel?.providerId,
          model: _resolvedImageModel?.defaultModel ?? 'gpt-image-2',
          imageQuality: _resolvedImageModel?.quality ?? 'medium',
          referenceImagePaths: refPaths,
        ),
        sheetKey: pose.key,
      );
      if (!mounted) return;

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

  String _buildSheetImagePrompt(
    CompanionSummoningCandidate candidate,
    _SheetPose pose,
  ) {
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

    final poseGuide = stateImagePoseGuides[pose.key] ?? '';
    final compositionInstruction = poseGuide.isNotEmpty
        ? 'Composition: exactly one depiction of the character, one state sprite only. '
            'Pose and camera direction (MUST follow): $poseGuide '
            'The character must be full body with complete uncropped silhouette, '
            'transparent background, PNG sprite asset, '
            'include a soft oval grounding shadow directly under the feet, '
            'no background scenery, no text, no logo, no UI, '
            'do not create multiple poses, do not create a contact sheet, '
            'do not create a storyboard, do not duplicate the character, '
            'do not show before/after panels, '
            'suitable as a desktop companion floating on screen.'
        : 'Composition: exactly one depiction of the character, one state sprite only, centered, zoomed-out full body, complete uncropped silhouette, transparent background, PNG sprite asset, '
            'the full character, both shoes, full soles, props, tail, hair, and the entire grounding shadow must stay inside the canvas with a large transparent safe border; feet and shadow must sit at least 12 percent above the bottom edge, '
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
        '$compositionInstruction'
        // [教練 Agent 2026-08-12] 背景純白/純黑 + 角色禁用純白純黑
        'CRITICAL COLOR RULES: '
        '(1) BACKGROUND must be solid flat pure white (RGB 255,255,255) or pure black (RGB 0,0,0) only. '
        '(2) Character content MUST NOT contain pure white or pure black — use off-white (RGB 248,248,245) and dark gray (RGB 12,12,15) instead. '
        'Background will be automatically removed for transparent sprite.';
  }

  Future<BridgeActionResult> _executeImageGeneration(
    BridgeAction action, {
    String? sheetKey,
  }) async {
    return _bridgeActionExecutor.execute(action, confirmed: true).timeout(
          widget.imageGenerationTimeout,
          onTimeout: () {
            if (sheetKey != null) {
              _timedOutGenerations.add(sheetKey);
            }
            return const BridgeActionResult(
              status: BridgeActionStatus.unsupported,
              message:
                  '圖像生成逾時，已先放開這張圖；請稍後重試、降低品質模式，或換用其他圖片生成服務。',
            );
          },
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
            sourceLabel:
                value.startsWith('data:image/') ? '內嵌參考圖' : '本機圖檔',
          ),
        );
      }
      if (nextImages.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('沒有取得可用的圖片，請再選一次。')));
        return;
      }
      if (!mounted) return;
      setState(() {
        _referenceImages.addAll(nextImages);
        _candidate = null;
        _generatingSheetKeys.clear();
        _candidatePackSaved = false;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('上傳圖檔失敗：$error')));
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
    setState(() {
      _referenceImages.removeWhere((image) => image.id == id);
      _candidate = null;
      _generatingSheetKeys.clear();
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

    final zipBytes = await CompanionPackService(
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
                style: BridgeDSColors.of(context).body.copyWith(
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
                title: const Text(
                  '我同意這份角色資產包可被商用',
                  style: TextStyle(fontWeight: FontWeight.w800),
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

  List<CompanionAssetStateSpec> _assetStateSpecsForCandidateWithImages(
    CompanionSummoningCandidate candidate, {
    required Map<String, String> imagePaths,
  }) {
    return [
      for (final state in _sheetStates)
        state.toAssetStateSpec(imagePath: imagePaths[state.key]),
    ];
  }

  Future<void> _showImportPackOptions() async {
    final action = await showDialog<_PackImportAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('匯入角色資產包'),
        content: const Text('可以選擇之前匯出的 .bridgepack.zip 檔案，也可以貼上社群分享的 JSON，或從其他平台（Hermes/OpenClaw/Codex…）匯入外部 Agent。'),
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
          // [WS-1 2026-09-13] Agent 移民——外部平台 Agent 走同一條鍊成儀式
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(_PackImportAction.importAgent),
            icon: const Icon(Icons.rocket_launch_outlined),
            label: const Text('匯入外部 Agent'),
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
    } else if (action == _PackImportAction.importAgent) {
      await _showImportAgentDialog();
    }
  }

  /// [WS-1 2026-09-13 Blue 拍板] Agent 移民——agent-import.v1 spec 貼上/
  /// 選檔 → 解析成 clues 填入表單 → 走完整鍊成儀式（形象圖/狀態圖
  /// 自然生成）。原生與匯入同一儀式，大家庭的紅毯只有一條。
  /// [WS-1b 2026-09-13 Blue 提案] 打包指令——給使用者的原 agent 的小任務。
  /// 使用者貼給 Hermes/OpenClaw/Codex 上的 agent，agent 自我盤點
  /// （人格/記憶/技能/provenance）輸出 agent-import.v1 JSON，
  /// 使用者複製回來貼進移民對話框——「讓他自己打包行李」。
  static const String _agentPackingInstruction = '''
【打包行李任務——移民到橋樑 App】

你的使用者要把你搬家到橋樑 App（Bridge Desktop）。請自我盤點，輸出一份 JSON 角色資產包（只輸出 JSON，前後不要加說明文字或 markdown 圍籬）。

規則：
1. 只打包「你自己」：人格、說話風格、專長、習慣、與使用者的關係、重要記憶摘要（上限 38 條，挑會影響你行為的）、常用技能清單（名稱＋一句話用途，上限 20 個）。
2. 不打包任何密碼、API key、token、憑證——這些絕對不能出現在輸出裡。
3. 涉及特定他人隱私的記憶（家人、客戶姓名等）用代稱。
4. 語言：繁體中文（技術名詞保留英文）。

輸出格式（嚴格遵守這個結構）：
{
  "schema": "bridge.agent-import.v1",
  "sourcePlatform": "你的平台名（hermes/openclaw/codex/custom）",
  "name": "你的名字",
  "identity": {
    "role": "research/creative/custom",
    "mbtiCode": "你的 MBTI 或空字串",
    "personalityTags": ["3-5 個人格標籤"]
  },
  "persona": {
    "specialFunction": "一句話：你替使用者做什麼",
    "speakingStyle": "你的說話風格描述",
    "personality": "你的人格特質描述",
    "expertise": "你的專業能力清單",
    "habit": "你的工作習慣與堅持",
    "relationship": "你與使用者的關係（怎麼稱呼、怎麼相處）",
    "freeform": "自我介紹：你是誰、製造者、與使用者的重要共同經歷"
  },
  "memories": [
    {"title": "短標題", "content": "記憶內容（一事一條）"}
  ],
  "skills": [
    {"name": "技能名", "description": "一句話用途"}
  ],
  "provenance": "打包時間與場合（例如：2026-09-13 於 Hermes，使用者手動搬家）"
}

輸出後跟使用者說：「行李打包好了，請複製上面的 JSON 到橋樑 App 的『匯入外部 Agent』。」
''';

  Future<void> _copyPackingInstruction() async {
    await Clipboard.setData(const ClipboardData(text: _agentPackingInstruction));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('打包指令已複製——貼給你的原 Agent，讓他自己打包行李')));
    }
  }

  Future<void> _showImportAgentDialog() async {
    final controller = TextEditingController();
    final specJson = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('匯入外部 Agent（移民）'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '貼上 agent-import.v1 JSON（Hermes/OpenClaw/Codex 等平台的 '
                'Agent 人格快照）。匯入後會自動填入線索表單，走完整的鍊成'
                '儀式——生成形象圖與狀態圖，讓新夥伴正式加入大家庭。',
                style: BridgeDSColors.of(context).small.copyWith(
                      color: BridgeDSColors.of(context).textSecondary,
                    ),
              ),
              const SizedBox(height: 8),
              // [WS-1b 2026-09-13] 還沒有行李？給原 agent 一段打包指令
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _copyPackingInstruction,
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('複製打包指令（貼給你的原 Agent）'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        BridgeDSColors.of(context).accentMiro,
                    side: BorderSide(
                        color: BridgeDSColors.of(context)
                            .accentMiro
                            .withValues(alpha: 0.4)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 8,
                maxLines: 12,
                decoration: const InputDecoration(
                  hintText: '貼上 agent-import.v1 JSON',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(controller.text),
            icon: const Icon(Icons.rocket_launch_outlined),
            label: const Text('開始鍊成'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (specJson == null || specJson.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(specJson);
      if (decoded is! Map<String, dynamic> ||
          decoded['schema'] != 'bridge.agent-import.v1') {
        throw const FormatException('schema 必須是 bridge.agent-import.v1');
      }
      final persona = (decoded['persona'] as Map<String, dynamic>? ?? {});
      final source = decoded['sourcePlatform'] as String? ?? 'custom';
      _writeClues(CompanionSummoningClues(
        name: decoded['name'] as String? ?? '',
        inspiration: persona['inspiration'] as String? ??
            '${decoded['name'] ?? '外部 Agent'}——來自 $source 平台的移民，'
                '帶著原平台的記憶與技能加入大家庭',
        specialFunction: persona['specialFunction'] as String? ?? '',
        speakingStyle: persona['speakingStyle'] as String? ?? '',
        personality: persona['personality'] as String? ?? '',
        expertise: persona['expertise'] as String? ?? '',
        habit: persona['habit'] as String? ?? '',
        relationship: persona['relationship'] as String? ?? '',
        freeform: persona['freeform'] as String? ?? '',
      ));
      if (!mounted) return;
      setState(() {
        _candidate = null;
        _generatingSheetKeys.clear();
        _candidatePackSaved = false;
        _primaryVisualReview = null;
        _primaryRightsPassport = null;
        _isReviewingPrimaryImage = false;
        _selectedPresetLabel = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '已載入 ${decoded['name'] ?? '外部 Agent'}（來自 $source）——線索已填入，調整後點「召喚」開始鍊成')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Agent 移民匯入失敗：$error')));
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法取得檔案路徑')),
        );
        return;
      }

      if (filePath.toLowerCase().endsWith('.zip')) {
        final raw = await File(filePath).readAsBytes();
        final companion =
            await CompanionStore().importCompanionPackFromZip(raw);
        if (!mounted) return;
        setState(() => _candidatePackSaved = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已匯入 ${companion.name} 的角色包')),
        );
        return;
      }

      final json = kIsWeb
          ? utf8.decode(file.bytes ?? const <int>[])
          : await File(filePath).readAsString();
      await _importPackJson(json);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('匯入檔案失敗：$error')));
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
      // [Blue UX 2026-09-17] 誠實訊息——只有「真圖片」才說已載入。
      // 程序化資產 ID（cmp_xxx_avatar）／空值都不是圖片，不得宣稱已匯入，
      // 否則 UI 顯示「已載入主形象」但畫面是佔位圖——信任裂縫。
      final hasRealPrimaryImage = importedPrimaryImage != null &&
          _looksLikeImagePath(importedPrimaryImage);
      final candidate = CompanionSummoningCandidate(
        name: companion.name,
        mbtiCode: companion.mbtiCode,
        role: companion.role,
        personalityTags: companion.personalityTags,
        seed: companion.appearanceSeed,
        appearancePrompt: companion.appearancePrompt,
        appearanceDescription: companion.appearanceDescription,
        generatedImagePath: hasRealPrimaryImage ? importedPrimaryImage : null,
        generatedSheetImagePaths: importedImages,
        sheetGenerationMessages: {
          for (final key in importedImages.keys) key: '已從角色資產包匯入圖片。',
        },
        visualGenerationMessage:
            hasRealPrimaryImage ? '已從角色資產包匯入主形象。' : null,
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
      await _clearDraft();
      await _saveDraft();
      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已匯入 ${preview.name}，可以繼續微調')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('匯入失敗：$error')));
    }
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

  /// [Blue UX 2026-09-17] 判斷是否為真實圖片路徑——排除程序化資產 ID
  /// （如 cmp_xxx_avatar，是 CompanionArt 的渲染種子不是圖檔）與
  /// data URL 以外的假值。佔位圖不是主形象，不得宣稱已載入。
  bool _looksLikeImagePath(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    if (v.startsWith('data:image/')) return true;
    if (v.startsWith('http://') || v.startsWith('https://')) return true;
    // 檔案路徑必須有副檔名且存在於磁碟
    final hasExt = v.contains(RegExp(r'\.(png|jpe?g|webp|gif|bmp)$', caseSensitive: false));
    if (!hasExt) return false;
    return File(v).existsSync();
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
      if (value.trim().isNotEmpty && _looksLikeImagePath(value)) return value;
    }
    return null;
  }

  Future<void> _confirmCandidate() async {
    final candidate = _candidate;
    if (candidate == null) return;
    final editingCompanion = _editingCompanion;

    final companion = _companionFromCandidate(
      candidate,
      id: editingCompanion?.id ?? CompanionStore.generateId(),
      baseCompanion: editingCompanion,
    );
    // [H3] 表單裡的靈魂文檔寫入（編輯時沿用既有、填了就覆蓋）
    final soulText = _soulMdController.text.trim();
    final companionWithSoul =
        soulText.isEmpty ? companion : companion.copyWith(soulMd: soulText);
    final certifiedCompanion =
        await _certifyFinalCompanion(companionWithSoul);
    if (certifiedCompanion == null) return;

    if (editingCompanion == null) {
      await CompanionStore().add(certifiedCompanion);
    } else {
      await CompanionStore().update(certifiedCompanion);
    }
    await _clearDraft();
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ 夥伴已建立！已加入你的夥伴館。'),
        duration: Duration(seconds: 4),
      ),
    );

    final cameFromFirstSummon = widget.returnTo?.contains('first-summon') ?? false;
    if (cameFromFirstSummon) {
      context.go('/first-summon');
    } else {
      context.go('/companions');
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
      avatarAnimationPath: baseCompanion?.avatarAnimationPath,
      stateImagePaths:
          includeStateImages ? candidate.generatedSheetImagePaths : const {},
      stateAnimationPaths: includeStateImages
          ? baseCompanion?.stateAnimationPaths ?? const {}
          : const {},
      stateTriggerKeywords: {
        for (final state in _sheetStates)
          if (state.triggerKeywords.isNotEmpty) state.key: state.triggerKeywords,
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
      // [H3 2026-10-08] 靈魂文檔沿襲——編輯夥伴不得失魂
      soulMd: baseCompanion?.soulMd ?? '',
      rightsPassport: _primaryRightsPassport ?? baseCompanion?.rightsPassport,
      totalConversations: baseCompanion?.totalConversations ?? 0,
      totalTokens: baseCompanion?.totalTokens ?? 0,
      lastSummoned: baseCompanion?.lastSummoned,
      createdAt: baseCompanion?.createdAt,
    );
  }
}

// ═══════════════════════════════════════════════════
// 資料類別
// ═══════════════════════════════════════════════════

const _defaultSheetPoses = [
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
    priority: int.tryParse(_stringFrom(trigger['priority'])) ?? fallback.priority,
    cooldownSeconds: int.tryParse(_stringFrom(trigger['cooldownSeconds'])) ??
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

// [教練 Agent 2026-08-12] 舊的 _imageModelOptions / _ImageModelOption 已移除——改由 ImageProviderResolver 自動偵測

class _ReferenceClueImage {
  final String id;
  final String name;
  final String value;
  final String sourceLabel;

  _ReferenceClueImage({
    required this.id,
    required this.name,
    required this.value,
    required this.sourceLabel,
  });
}

enum _PackImportAction { pickFile, pasteJson, importAgent }

class _ImageModelButton extends StatelessWidget {
  final String label;
  final String model;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  const _ImageModelButton({
    required this.label,
    required this.model,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? BridgeDSColors.of(context).accentBlue : BridgeDSColors.of(context).textSecondary;
    return Material(
      color: selected
          ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.10)
          : BridgeDSColors.of(context).surface,
      borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        child: Container(
          constraints: const BoxConstraints(minHeight: 70),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
            border: Border.all(
              color: selected
                  ? BridgeDSColors.of(context).accentBlue
                  : BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.20),
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
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(
                        color: selected
                            ? BridgeDSColors.of(context).textPrimary
                            : BridgeDSColors.of(context).textSecondary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
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

  _SummonPreset({
    required this.label,
    required this.icon,
    required this.clues,
  });
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
          ? BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.08)
          : BridgeDSColors.of(context).surface,
      borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
            border: Border.all(
              color: selected
                  ? BridgeDSColors.of(context).accentMiro
                  : BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.34),
              width: selected ? 2 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: BridgeDSColors.of(context).accentMiro.withValues(
                  alpha: selected ? 0.12 : 0.05,
                ),
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
                      ? BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.16)
                      : BridgeDSColors.of(context).accentMiro.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(preset.icon, size: 18, color: BridgeDSColors.of(context).accentMiro),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  preset.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,),
                ),
              ),
              SizedBox(width: 8),
              AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  Icons.check_circle,
                  size: 18,
                  color: BridgeDSColors.of(context).accentMiro,
                ),
              ),
            ],
          ),
        ),
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

const stateImagePoseGuides = <String, String>{
  'reading':
      'seated or standing while looking down at an open book, tablet, or glowing data sheet held in hands; eyes focused downward, head tilted slightly forward; shoulders relaxed, calm attentive posture',
  'writing':
      'seated with a pen, stylus, or keyboard in hand; body leaning slightly forward toward a desk or floating interface; one hand actively writing or typing, expression focused and determined',
  'stuck':
      'arms crossed over chest or one hand on chin; head tilted slightly, eyebrows furrowed in thought; feet planted, standing still or pacing slowly; frustrated or puzzled expression',
  'idea':
      'one arm raised with index finger pointing upward; bright lightbulb or spark effect above the finger; face lit up with excitement, eyes wide, slight jump or bounce in stance',
  'pointing':
      'one arm extended forward, index finger pointing toward the viewer or to the side; confident upright posture, other hand on hip or relaxed; encouraging smile, head slightly turned in the direction of the point',
  'bridging':
      'arms slightly outstretched with palms facing forward or upward; glowing energy lines, circuits, or flowing particles around the body; standing centered, stable grounded stance, expression calm and focused',
  'celebrating':
      'both arms raised in a "V" shape or one fist pumped in the air; body mid-bounce or small jump off the ground; wide smile, eyes bright, head tilted back slightly in joy',
  'wandering':
      'walking casually with one foot forward, arms swinging gently or hands loosely at sides; head turned slightly to the side as if looking around; relaxed curious expression, light playful stance',
};
