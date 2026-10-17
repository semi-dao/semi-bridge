// local_llm_runtime_card.dart
// 本地 LLM 運行時卡片 — Bridge Runtime (llama.cpp) 下載、模型選擇、server 啟停
// 建立日期: 2026-07-20 by AI Agent
// 設計：BridgeDS 深色主題 + 硬體檢測 + 模型適配度標籤

import 'dart:async';
import '../services/brain_revival_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/local_model_runtime_service.dart';
import '../services/local_model_catalog_service.dart';
import '../services/macos_desktop_shell_channel.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../services/local_model_scheduler.dart'; // [小葵 2026-10-01] 離合器角色槽
import 'bridge_desktop_widgets.dart';

class LocalLlmRuntimeCard extends StatefulWidget {
  const LocalLlmRuntimeCard({super.key});

  @override
  State<LocalLlmRuntimeCard> createState() => _LocalLlmRuntimeCardState();
}

class _LocalLlmRuntimeCardState extends State<LocalLlmRuntimeCard> {
  final _runtimeService = LocalModelRuntimeService();
  final _catalogService = const LocalModelCatalogService();
  final _desktopChannel = const MacosDesktopShellChannel();
  final _dio = Dio();

  BridgeLocalRuntimeState? _runtimeState;
  LocalHardwareProfile? _hardwareProfile;
  LocalModelPlan? _modelPlan;
  bool _isLoading = true;
  Timer? _pollTimer;
  // [小葵 2026-10-16 Blue 審計令] running 狀態即時健康監控——state 檔是快照，
  // server 事後掛掉時 UI 仍顯示假「運行中」。定期 ping 真引擎覆寫真相。
  Timer? _healthTimer;
  bool _engineUnreachable = false;
  bool _autoRestoreAttempted = false; // [小葵 2026-09-29] 自動恢復只做一次（防輪詢無限循環）
  int _selectedModelIndex = 0; // 使用者選中的模型索引
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  String _searchQuery = '';
  Set<String> _installedModels = {}; // 已下載的模型 ID（掃描硬碟得出）
  Map<String, int> _installedModelSizes = {}; // 模型 ID → 實際檔案大小（bytes）
  Map<String, bool> _modelTestResults = {}; // 模型 ID → 測試是否通過
  Map<String, String> _modelTestResponses = {}; // 模型 ID → 測試回應
  Set<String> _candidateModels = {}; // 已加入候選列表的模型 ID
  Set<String> _testingModels = {}; // 正在測試中的模型 ID
  String? _downloadingModelId; // 正在下載的模型 ID
  List<Map<String, dynamic>> _trendingModels = []; // HuggingFace 動態熱門模型
  bool _isLoadingTrending = false;
  // [小葵 2026-09-28] 模型切換狀態（Blue 指令：換模型必須走 App 按鈕）
  String? _isSwitchingModel; // 正在切換中的模型 ID
  // [小葵 2026-10-01 離合器步驟2] 角色槽狀態——夥伴/辨識雙選型
  String? _companionRoleModel; // 夥伴模型（聊天＋簡單任務）
  String? _visionRoleModel; // 辨識模型（照片嵌入＋視覺分析）

  @override
  void initState() {
    super.initState();
    _loadState();
    // [小葵 2026-10-16] running 健康輪詢（60s）——真實引擎狀態 > state 檔快照
    _healthTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _probeEngineHealth();
    });
    // [小葵 2026-10-01 離合器步驟2] 載入已存角色設定
    LocalModelScheduler.instance.loadRoles().then((_) {
      final s = LocalModelScheduler.instance.snapshot;
      if (mounted) {
        setState(() {
          _companionRoleModel = s.companionModelId;
          _visionRoleModel = s.visionModelId;
        });
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _healthTimer?.cancel();
    super.dispose();
  }

  /// [小葵 2026-10-16] ping 18789 /v1/models——2 秒逾時。
  /// 與 state 檔不符時以真相為準（顯示引擎無回應）。
  Future<void> _probeEngineHealth() async {
    if (_runtimeState?.phase != BridgeLocalRuntimePhase.running) return;
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 2), receiveTimeout: const Duration(seconds: 2)));
      final r = await dio.get('http://127.0.0.1:18789/v1/models');
      final alive = r.statusCode == 200;
      if (mounted && _engineUnreachable == alive) {
        setState(() => _engineUnreachable = !alive);
      }
    } catch (_) {
      if (mounted && !_engineUnreachable) {
        setState(() => _engineUnreachable = true);
      }
    }
  }

  Future<void> _loadState() async {
    try {
      var runtimeState = await _runtimeService.inspectBridgeRuntime();
      final hardwareProfile = await _desktopChannel.hardwareProfile();
      final modelPlan = _catalogService.buildPlan(hardware: hardwareProfile);

      // [教練 Agent 2026-07-20] 掃描硬碟上的實際模型檔案（不靠記憶體）
      await _scanInstalledModels();

      // [教練 Agent 2026-07-20] 引擎未安裝時自動下載，使用者零摩擦
      if (runtimeState.phase == BridgeLocalRuntimePhase.notInstalled) {
        runtimeState = await _runtimeService.prepareBridgeRuntime();
      }

      // [小葵 2026-09-29] 生產線自動恢復：App 啟動/頁面載入時，若有現役 modelId
      // 但 server 沒跑（phase=installed），自動啟動——重開機後無腦恢復，
      // 不再需要手動點「啟動本地 server」。（Blue 拍板：現役模型 = 開機即用）
      // ⚠️ [小葵 2026-09-29 慘案根修] 只嘗試一次！
      //   原 bug：_loadState 被 3s 輪詢反覆呼叫，startServer 失敗（GPU 忙/載入慢）
      //   → phase 回 installed → 又觸發自動恢復 → 無限重啟循環 = CPU 168%、
      //   系統遲鈍、llama 反覆生死、快測被連坐。失敗一次就罷手，回復手動按鈕。
      if (!_autoRestoreAttempted &&
          runtimeState.phase == BridgeLocalRuntimePhase.installed &&
          runtimeState.modelId != null &&
          runtimeState.modelId!.isNotEmpty) {
        _autoRestoreAttempted = true;
        debugPrint('[LocalLlm] 自動恢復生產線（僅此一次）：startServer(${runtimeState.modelId})');
        runtimeState = await _runtimeService.startServer(modelId: runtimeState.modelId);
      }

      if (mounted) {
        setState(() {
          _runtimeState = runtimeState;
          _hardwareProfile = hardwareProfile;
          _modelPlan = modelPlan;
          _isLoading = false;
          // 下載完成後標記為已安裝
          if (_downloadingModelId != null &&
              runtimeState.phase != BridgeLocalRuntimePhase.downloading) {
            _installedModels.add(_downloadingModelId!);
            _downloadingModelId = null;
          }
        });

        // Start polling if downloading or starting
        if (runtimeState.phase == BridgeLocalRuntimePhase.downloading ||
            runtimeState.phase == BridgeLocalRuntimePhase.starting) {
          _startPolling();
        } else {
          _stopPolling();
        }

        // [教練 Agent 2026-07-20] 引擎已安裝時，非同步拉取 HuggingFace 熱門 GGUF 模型
        if (runtimeState.phase == BridgeLocalRuntimePhase.installed ||
            runtimeState.phase == BridgeLocalRuntimePhase.running) {
          _fetchTrendingModels();
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadState();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _handlePrimaryAction() async {
    if (_runtimeState == null) return;

    setState(() => _isLoading = true);

    try {
      BridgeLocalRuntimeState newState;

      switch (_runtimeState!.primaryCommand) {
        case BridgeLocalRuntimeCommand.prepareRuntime:
          newState = await _runtimeService.prepareBridgeRuntime();
          break;
        case BridgeLocalRuntimeCommand.downloadModel:
          final recommendations = _modelPlan?.recommendations ?? [];
          if (recommendations.isEmpty || _selectedModelIndex >= recommendations.length) {
            setState(() => _isLoading = false);
            return;
          }
          setState(() => _downloadingModelId = recommendations[_selectedModelIndex].model.id);
          newState = await _runtimeService.downloadModel(recommendations[_selectedModelIndex]);
          break;
        case BridgeLocalRuntimeCommand.startServer:
          newState = await _runtimeService.startServer();
          break;
        case BridgeLocalRuntimeCommand.stopServer:
        case BridgeLocalRuntimeCommand.deleteModel:
        case BridgeLocalRuntimeCommand.testModel:
          newState = await _runtimeService.stopServer();
          break;
        case BridgeLocalRuntimeCommand.startLabServer:
        case BridgeLocalRuntimeCommand.stopLabServer:
          // [小葵 2026-09-29] lab server 由 ModelLabCard 自己控制，不走 primary action
          newState = await _runtimeService.inspectBridgeRuntime();
          break;
        case BridgeLocalRuntimeCommand.status:
          newState = await _runtimeService.inspectBridgeRuntime();
          break;
      }

      if (mounted) {
        setState(() {
          _runtimeState = newState;
          _isLoading = false;
          if (_downloadingModelId != null && newState.phase != BridgeLocalRuntimePhase.downloading) {
            _installedModels.add(_downloadingModelId!);
            _downloadingModelId = null;
          }
        });

        // Start polling if needed
        if (newState.phase == BridgeLocalRuntimePhase.downloading ||
            newState.phase == BridgeLocalRuntimePhase.starting) {
          _startPolling();
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _downloadingModelId = null;
        });
      }
    }
  }

  /// 下載指定模型（不影響選中的推薦模型）
  Future<void> _downloadSpecificModel(LocalModelRecommendation recommendation) async {
    setState(() {
      _downloadingModelId = recommendation.model.id;
      _isLoading = true;
    });

    try {
      final newState = await _runtimeService.downloadModel(recommendation);
      if (mounted) {
        setState(() {
          _runtimeState = newState;
          _isLoading = false;
          if (newState.phase != BridgeLocalRuntimePhase.downloading) {
            _installedModels.add(recommendation.model.id);
            _downloadingModelId = null;
          }
        });
        if (newState.phase == BridgeLocalRuntimePhase.downloading) {
          _startPolling();
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _downloadingModelId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _runtimeState == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 狀態標籤列（標題由外層 BridgeCard 提供，這裡只顯示狀態）
        if (_runtimeState != null)
          Align(
            alignment: Alignment.centerRight,
            child: BridgeStatusTag(
              label: _runtimeState!.phase.label,
              type: _getStatusTagType(_runtimeState!.phase),
            ),
          ),
        if (_runtimeState != null) const SizedBox(height: BridgeDS.spaceSM),
        _buildHardwareInfo(),
        const SizedBox(height: BridgeDS.spaceMD),
        _buildRuntimeContent(),
      ],
    );
  }


  BridgeTagType _getStatusTagType(BridgeLocalRuntimePhase phase) {
    switch (phase) {
      case BridgeLocalRuntimePhase.notInstalled:
        return BridgeTagType.info;
      case BridgeLocalRuntimePhase.downloading:
      case BridgeLocalRuntimePhase.starting:
        return BridgeTagType.warn;
      case BridgeLocalRuntimePhase.installed:
        return BridgeTagType.info;
      case BridgeLocalRuntimePhase.running:
        return BridgeTagType.success;
      case BridgeLocalRuntimePhase.failed:
        return BridgeTagType.error;
    }
  }

  Widget _buildHardwareInfo() {
    if (_hardwareProfile == null) {
      return Text(
        '等待 Bridge Desktop 回報硬體資訊...',
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault),
      ),
      child: Row(
        children: [
          Icon(
            Icons.computer,
            color: BridgeDSColors.of(context).textTertiary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_hardwareProfile!.chipLabel}${_hardwareProfile!.ramGb != null ? " · ${_hardwareProfile!.ramGb}GB RAM" : ""}',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuntimeContent() {
    if (_runtimeState == null) {
      return Text(
        '載入中...',
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and detail
        Text(
          _runtimeState!.title,
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
            color: BridgeDSColors.of(context).textPrimary,),
        ),
        const SizedBox(height: 6),
        // downloading 階段的 detail 由 _buildDownloadProgress 顯示，這裡不重複
        if (_runtimeState!.phase != BridgeLocalRuntimePhase.downloading)
          Text(
            _runtimeState!.detail,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
              height: 1.4,),
          ),
        const SizedBox(height: BridgeDS.spaceMD),

        // [小葵 2026-10-16 Blue 審計令] 多模型並行運算開關移除——
        // 純前端 setState 無引擎綁定（審計判「假」：顯示了系統沒有的承諾）。
        // 真並行調度實作後（LocalModelScheduler/ProviderRouter 接線）再回來。

        // Primary action button — 只有在引擎相關階段才顯示
        // installed/running 階段時隱藏（改由模型旁的按鈕操作）
        // 例外：stopServer→installed 後 primaryCommand=startServer 時需顯示按鈕
        if (_runtimeState!.primaryActionEnabled &&
            (_runtimeState!.primaryCommand == BridgeLocalRuntimeCommand.startServer ||
             (_runtimeState!.phase != BridgeLocalRuntimePhase.installed &&
              _runtimeState!.phase != BridgeLocalRuntimePhase.running)))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _handlePrimaryAction,
                icon: Icon(_getActionIcon(), size: 18),
                label: Text(_runtimeState!.primaryActionLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: BridgeDSColors.of(context).accentPurple,
                  foregroundColor: BridgeDSColors.of(context).textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),

        // Phase-specific content
        if (_runtimeState!.phase == BridgeLocalRuntimePhase.downloading)
          _buildDownloadProgress(),
        if (_runtimeState!.phase == BridgeLocalRuntimePhase.installed)
          _buildModelCatalog(),
        if (_runtimeState!.phase == BridgeLocalRuntimePhase.running) ...[
          _buildRunningInfo(),
          const SizedBox(height: BridgeDS.spaceMD),
          _buildModelCatalog(),
        ],
        if (_runtimeState!.phase == BridgeLocalRuntimePhase.failed)
          _buildErrorInfo(),
      ],
    );
  }

  IconData _getActionIcon() {
    switch (_runtimeState!.primaryCommand) {
      case BridgeLocalRuntimeCommand.prepareRuntime:
      case BridgeLocalRuntimeCommand.downloadModel:
        return Icons.download;
      case BridgeLocalRuntimeCommand.startServer:
        return Icons.play_arrow;
      case BridgeLocalRuntimeCommand.stopServer:
      case BridgeLocalRuntimeCommand.deleteModel:
      case BridgeLocalRuntimeCommand.testModel:
      case BridgeLocalRuntimeCommand.startLabServer:
      case BridgeLocalRuntimeCommand.stopLabServer:
        return Icons.stop;
      case BridgeLocalRuntimeCommand.status:
        return Icons.refresh;
    }
  }


  Widget _buildDownloadProgress() {
    final progress = _runtimeState!.progress;
    final detail = _runtimeState!.detail;
    // 從 detail 解析已下載位元組，或從 state 取 modelName/modelSize
    final modelName = _runtimeState!.title;
    // detail 格式："Qwen3.5-4B（約 2.52 GB）下載中，已取得 1.3 GB。"
    // 嘗試從 detail 提取已下載大小
    String downloadedStr = '';
    String totalStr = '';
    final match = RegExp(r'已取得\s*([\d.]+\s*[KMGT]?B?)').firstMatch(detail);
    if (match != null) {
      downloadedStr = match.group(1) ?? '';
    }
    final totalMatch = RegExp(r'（約\s*([\d.]+\s*[KMGT]?B?)）').firstMatch(detail);
    if (totalMatch != null) {
      totalStr = totalMatch.group(1) ?? '';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$modelName 下載中',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                  color: BridgeDSColors.of(context).textPrimary,),
              ),
            ),
            // 已下載大小 / 總大小
            if (downloadedStr.isNotEmpty || totalStr.isNotEmpty)
              Text(
                totalStr.isNotEmpty
                    ? '$downloadedStr / $totalStr'
                    : downloadedStr,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                  fontWeight: FontWeight.w500,),
              ),
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress, // [教練 Agent 2026-07-21] macOS 端 progress 是 0-1，直接使用
                    minHeight: 8,
                    backgroundColor: BridgeDSColors.of(context).surfaceHover,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      BridgeDSColors.of(context).accentPurple,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(progress * 100).toStringAsFixed(1)}%', // [教練 Agent 2026-07-21] 0-1 轉百分比顯示
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: BridgeDSColors.of(context).accentYellow,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '下載中，請保持 Bridge Desktop 運行',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModelCatalog() {
    if (_modelPlan == null) return const SizedBox.shrink();
    final recommendations = _modelPlan!.recommendations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [小葵 2026-10-01 離合器步驟2] 角色槽——夥伴/辨識雙選型
        _buildRoleSlots(),
        const SizedBox(height: BridgeDS.spaceMD),
        Text(
          '選擇模型',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
            color: BridgeDSColors.of(context).textPrimary,),
        ),
        const SizedBox(height: 8),
        // 推薦模型列表（可點選）
        ...recommendations.asMap().entries.map((entry) {
          final index = entry.key;
          final recommendation = entry.value;
          // [小葵 2026-09-29 Blue 指令] 紫色框鎖定「現役模型」（runtime state 的 modelId），
          // 不再跟隨使用者點選的候選 index——紫色=確定感=現在正在跑的那個。
          final isSelected = _runtimeState?.modelId == recommendation.model.id;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedModelIndex = index),
              child: _buildModelEntry(recommendation, isSelected),
            ),
          );
        }),
        const SizedBox(height: 8),
        Text(
          _modelPlan!.summary,
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
            height: 1.4,),
        ),
        const SizedBox(height: 4),
        Text(
          '沒看到想要的模型？用下方搜尋框搜尋 HuggingFace 上的任何 GGUF 模型，未來新模型（Qwen3.6、Gemma 5 等）也能直接搜尋下載。',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textTertiary,
            height: 1.4,),
        ),
        const SizedBox(height: BridgeDS.spaceMD),
        // 動態熱門模型
        _buildTrendingSection(),
        const SizedBox(height: BridgeDS.spaceMD),
        // 搜尋框
        _buildSearchSection(),
      ],
    );
  }

  Widget _buildRoleSlots() {
    final installed = _installedModels.toList()..sort();
    if (installed.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '角色配置',
          style: TierStyle.of(context, Tier.cardTitle).toTextStyle(),
        ),
        const SizedBox(height: 4),
        Text(
          '夥伴＝聊天＋簡單任務；辨識＝照片嵌入與視覺分析。兩個角色設好後，系統會自動在閒置時輪替（自動離合器）。',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                color: BridgeDSColors.of(context).textSecondary,
                height: 1.4,
              ),
        ),
        const SizedBox(height: 8),
        _buildRoleSlotRow(
          icon: Icons.forum_outlined,
          label: '夥伴模型',
          hint: '聊天＋簡單任務',
          value: _companionRoleModel,
          onChanged: (v) async {
            setState(() => _companionRoleModel = v);
            await LocalModelScheduler.instance
                .setRoles(companionModelId: v, visionModelId: _visionRoleModel);
          },
        ),
        const SizedBox(height: 6),
        _buildRoleSlotRow(
          icon: Icons.image_search,
          label: '辨識模型',
          hint: _companionRoleModel == null ? '未設定（用夥伴模型代替）' : '未設定（用夥伴模型代替）',
          value: _visionRoleModel,
          onChanged: (v) async {
            setState(() => _visionRoleModel = v);
            await LocalModelScheduler.instance
                .setRoles(companionModelId: _companionRoleModel, visionModelId: v);
          },
        ),
      ],
    );
  }

  Widget _buildRoleSlotRow({
    required IconData icon,
    required String label,
    required String hint,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final installed = _installedModels.toList()..sort();
    final colors = BridgeDSColors.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: colors.accentBlue),
        const SizedBox(width: 6),
        Text(label,
            style: TierStyle.of(context, Tier.cardBody)
                .toTextStyle()
                .copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.borderDefault),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: (value == null || !installed.contains(value)) ? null : value,
                isExpanded: true,
                hint: Text(hint,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                        color: colors.textMuted, fontSize: 12)),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('未設定')),
                  ...installed.map((m) =>
                      DropdownMenuItem<String?>(value: m, child: Text(m, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModelEntry(LocalModelRecommendation recommendation, bool isSelected) {
    final borderColor = isSelected
        ? BridgeDSColors.of(context).accentPurple
        : BridgeDSColors.of(context).borderDefault;
    final borderWidth = isSelected ? 2.0 : 1.0;
    final modelId = recommendation.model.id;
    final isInstalled = _installedModels.contains(modelId);
    final isDownloadingThis = _downloadingModelId == modelId;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected
            ? BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.08)
            : BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isSelected)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.check_circle,
                      color: BridgeDSColors.of(context).accentPurple, size: 18),
                ),
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        recommendation.model.name,
                        overflow: TextOverflow.ellipsis,
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: BridgeDSColors.of(context).textPrimary,),
                      ),
                    ),
                    // [小葵 2026-10-01 離合器步驟4] 角色徽章——夥伴/辨識
                    // 角色教育：使用者不需懂模型，只需懂角色
                    if (_companionRoleModel == modelId) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('💬 夥伴',
                            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                                color: BridgeDSColors.of(context).accentBlue, fontSize: 10)),
                      ),
                    ],
                    if (_visionRoleModel == modelId) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('📷 辨識',
                            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                                color: BridgeDSColors.of(context).accentPurple, fontSize: 10)),
                      ),
                    ],
                  ],
                ),
              ),
              _buildFitBadge(recommendation.fit),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${recommendation.model.downloadSize} · ${recommendation.model.quantization} · ${recommendation.model.sourceLabel}',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
          ),
          const SizedBox(height: 4),
          Text(
            recommendation.reason,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
              height: 1.3,),
          ),
          // 每個模型的獨立下載按鈕
          const SizedBox(height: 8),
          Row(
            children: [
              if (isInstalled) ...[
                Icon(Icons.check_circle, color: BridgeDSColors.of(context).accentGreen, size: 14),
                const SizedBox(width: 4),
                Text('已下載',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentGreen)),
                // 顯示實際檔案大小
                if (_installedModelSizes[modelId] != null) ...[
                  const SizedBox(width: 4),
                  Text(_formatFileSize(_installedModelSizes[modelId]!),
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted)),
                ],
                const SizedBox(width: 8),
                // [小葵 2026-09-28] 一鍵切換現役模型（Blue 指令：換模型必須走 App 按鈕）
                // _switchToModel 走 Swift startServer(modelId) 鏈：自動停舊載新
                if (_isActiveModel(modelId)) ...[
                  Icon(Icons.play_circle_fill, color: BridgeDSColors.of(context).accentPurple, size: 14),
                  const SizedBox(width: 4),
                  Text('現役模型',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple, fontWeight: FontWeight.w700)),
                ] else ...[
                  GestureDetector(
                    onTap: (_isLoading || _isSwitchingModel != null) ? null : () => _switchToModelWithConfirm(modelId, recommendation.model.name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isSwitchingModel == modelId)
                            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            // [Blue 2026-10-01] 非現役按鈕改白字——紫色專屬現役項，消除識別混淆
                            Icon(Icons.swap_horiz, size: 12, color: BridgeDSColors.of(context).textPrimary),
                          const SizedBox(width: 3),
                          Text('設為現役',
                              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // 測試按鈕 / 測試結果
                if (_testingModels.contains(modelId)) ...[
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 4),
                  Text('測試中', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted)),
                ] else if (_modelTestResults[modelId] == true) ...[
                  // 測試通過
                  Icon(Icons.verified, color: BridgeDSColors.of(context).accentGreen, size: 14),
                  const SizedBox(width: 4),
                  Text('已驗證', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentGreen, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  // 加入/移除候選列表
                  GestureDetector(
                    onTap: _isLoading ? null : () => _toggleCandidate(modelId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _candidateModels.contains(modelId)
                            ? BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.15)
                            : BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_candidateModels.contains(modelId) ? Icons.check : Icons.add, size: 12,
                              color: _candidateModels.contains(modelId) ? BridgeDSColors.of(context).accentGreen : BridgeDSColors.of(context).accentPurple),
                          const SizedBox(width: 3),
                          Text(_candidateModels.contains(modelId) ? '候選' : '加入列表',
                              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: _candidateModels.contains(modelId) ? BridgeDSColors.of(context).accentGreen : BridgeDSColors.of(context).accentPurple,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 重新測試
                  GestureDetector(
                    onTap: _isLoading ? null : () => _testModel(modelId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: BridgeDSColors.of(context).surfaceHover,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.refresh, size: 12, color: BridgeDSColors.of(context).textMuted),
                    ),
                  ),
                ] else if (_modelTestResults[modelId] == false) ...[
                  // 測試失敗
                  Icon(Icons.warning, color: BridgeDSColors.of(context).accentRed, size: 14),
                  const SizedBox(width: 4),
                  Text('測試失敗', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentRed)),
                  const SizedBox(width: 6),
                  // 重新測試
                  GestureDetector(
                    onTap: _isLoading ? null : () => _testModel(modelId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh, size: 12, color: BridgeDSColors.of(context).accentPurple),
                          const SizedBox(width: 3),
                          Text('重新測試', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  // 尚未測試
                  GestureDetector(
                    onTap: _isLoading ? null : () => _testModel(modelId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.science, size: 12, color: BridgeDSColors.of(context).accentPurple),
                          const SizedBox(width: 3),
                          Text('測試', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                // 刪除按鈕
                GestureDetector(
                  onTap: _isLoading ? null : () => _deleteModel(modelId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: BridgeDSColors.of(context).accentRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline, size: 12, color: BridgeDSColors.of(context).accentRed),
                        const SizedBox(width: 3),
                        Text('刪除', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentRed, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ] else if (isDownloadingThis) ...[
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 6),
                Text('下載中...',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted)),
              ] else ...[
                GestureDetector(
                  onTap: _isLoading ? null : () => _downloadSpecificModel(recommendation),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // [Blue 2026-10-01] 下載鈕改白字——紫色專屬現役項
                        Icon(Icons.download, size: 14, color: BridgeDSColors.of(context).textPrimary),
                        const SizedBox(width: 4),
                        Text('下載', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (isSelected && !isInstalled && !isDownloadingThis)
                Text('已選為推薦',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrendingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: BridgeDSColors.of(context).borderSubtle),
        const SizedBox(height: BridgeDS.spaceSM),
        Row(
          children: [
            Icon(Icons.trending_up, color: BridgeDSColors.of(context).textMuted, size: 14),
            const SizedBox(width: 4),
            Text(
              '熱門模型',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                color: BridgeDSColors.of(context).textPrimary,),
            ),
            const Spacer(),
            if (_isLoadingTrending)
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        const SizedBox(height: 8),
        if (_trendingModels.isEmpty && !_isLoadingTrending)
          Text(
            '暫無資料',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted),
          ),
        ..._trendingModels.map((r) => _buildTrendingEntry(r)),
      ],
    );
  }

  Widget _buildTrendingEntry(Map<String, dynamic> result) {
    final modelId = result['id'] as String? ?? '';
    final downloads = result['downloads'] as int? ?? 0;
    final likes = result['likes'] as int? ?? 0;
    final lastModified = result['lastModified'] as String? ?? '';
    final shortName = modelId.split('/').last;
    final repoOwner = modelId.split('/').first;
    String family;
    if (shortName.toLowerCase().contains('qwen')) {
      family = 'Qwen';
    } else if (shortName.toLowerCase().contains('gemma')) {
      family = 'Gemma';
    } else if (shortName.toLowerCase().contains('llama')) {
      family = 'Llama';
    } else {
      family = '其他';
    }
    final isInstalled = _installedModels.contains(modelId);
    final isDownloadingThis = _downloadingModelId == modelId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(family, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shortName,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      repoOwner,
                      if (downloads > 0) '⬇ ${_formatDownloads(downloads)}',
                      if (likes > 0) '❤ $likes',
                      if (lastModified.isNotEmpty) _formatDate(lastModified),
                    ].join(' · '),
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted),
                  ),
                ],
              ),
            ),
            // 下載按鈕 or 狀態
            if (isInstalled)
              Icon(Icons.check_circle, color: BridgeDSColors.of(context).accentGreen, size: 16)
            else if (isDownloadingThis)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            else
              GestureDetector(
                onTap: _isLoading ? null : () => _downloadTrendingModel(result),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.download, size: 14, color: BridgeDSColors.of(context).accentPurple),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays > 30) return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      if (diff.inDays > 0) return '${diff.inDays}天前';
      if (diff.inHours > 0) return '${diff.inHours}小時前';
      return '剛更新';
    } catch (_) {
      return '';
    }
  }

  Widget _buildSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: BridgeDSColors.of(context).borderSubtle),
        const SizedBox(height: BridgeDS.spaceSM),
        Text(
          '搜尋更多模型',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
            color: BridgeDSColors.of(context).textPrimary,),
        ),
        const SizedBox(height: 8),
        TextField(
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
          decoration: InputDecoration(
            hintText: '輸入模型名稱，例如 Phi-4, SmolLM3...',
            hintStyle: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
            prefixIcon: Icon(Icons.search, color: BridgeDSColors.of(context).textMuted, size: 18),
            filled: true,
            fillColor: BridgeDSColors.of(context).surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: BridgeDSColors.of(context).borderDefault),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: BridgeDSColors.of(context).borderDefault),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: BridgeDSColors.of(context).accentPurple),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          onSubmitted: (query) => _performSearch(query),
        ),
        if (_isSearching)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (_searchResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._searchResults.map((r) => _buildSearchResultEntry(r)),
        ],
      ],
    );
  }

  Widget _buildSearchResultEntry(Map<String, dynamic> result) {
    final modelId = result['id'] as String? ?? '';
    final downloads = result['downloads'] as int? ?? 0;
    final pipelineTag = result['pipeline_tag'] as String? ?? '';
    final shortName = modelId.split('/').last;
    final isInstalled = _installedModels.contains(modelId);
    final isDownloadingThis = _downloadingModelId == modelId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_download, color: BridgeDSColors.of(context).textMuted, size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shortName,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (downloads > 0 || pipelineTag.isNotEmpty)
                    Text(
                      [
                        if (downloads > 0) '⬇ ${_formatDownloads(downloads)}',
                        if (pipelineTag.isNotEmpty) pipelineTag,
                      ].join(' · '),
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted),
                    ),
                ],
              ),
            ),
            if (isInstalled)
              Icon(Icons.check_circle, color: BridgeDSColors.of(context).accentGreen, size: 16)
            else if (isDownloadingThis)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            else
              GestureDetector(
                onTap: _isLoading ? null : () => _downloadTrendingModel(result),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.download, size: 14, color: BridgeDSColors.of(context).accentPurple),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDownloads(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }

  /// [教練 Agent 2026-07-20] 下載熱門/搜尋模型（從 HuggingFace API 結果構建 recommendation）
  Future<void> _downloadTrendingModel(Map<String, dynamic> result) async {
    final modelId = result['id'] as String? ?? '';
    final shortName = modelId.split('/').last;

    // 構建一個臨時的 LocalModelCatalogEntry
    final entry = LocalModelCatalogEntry(
      id: modelId,
      name: shortName,
      sizeClass: '?',
      quantization: 'GGUF',
      minRamGb: 4,
      recommendedRamGb: 8,
      recommendedVramGb: null,
      downloadSize: '未知大小',
      runtime: 'llama.cpp',
      sourceLabel: modelId.split('/').first,
      licenseLabel: '',
      manifestUrl: 'https://huggingface.co/$modelId',
      checksumSha256: '',
      fileName: '',
      repoId: modelId,
      downloadUrl: '',
      bestFor: const [],
    );
    final recommendation = LocalModelRecommendation(
      model: entry,
      fit: LocalModelFit.good,
      reason: '來自 HuggingFace 社群',
    );

    setState(() {
      _downloadingModelId = modelId;
      _isLoading = true;
    });

    try {
      final newState = await _runtimeService.downloadModel(recommendation);
      if (mounted) {
        setState(() {
          _runtimeState = newState;
          _isLoading = false;
          if (newState.phase != BridgeLocalRuntimePhase.downloading) {
            _installedModels.add(modelId);
            _downloadingModelId = null;
          }
        });
        if (newState.phase == BridgeLocalRuntimePhase.downloading) {
          _startPolling();
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _downloadingModelId = null;
        });
      }
    }
  }

  /// [教練 Agent 2026-07-20] 透過 Swift 原生層掃描硬碟上的已下載模型
  /// 包含測試結果和候選列表狀態
  Future<void> _scanInstalledModels() async {
    try {
      // 方法 1: 透過 listInstalledModels API
      var models = await _runtimeService.listInstalledModels();
      debugPrint('[LocalLlm] listInstalledModels API returned: ${models.length} items');

      // 方法 2: 如果 API 回空，從 runtimeState 的 modelId 推導
      if (models.isEmpty && _runtimeState != null && _runtimeState!.modelId != null) {
        debugPrint('[LocalLlm] Falling back to runtimeState.modelId: ${_runtimeState!.modelId}');
        models.add({
          'modelId': _runtimeState!.modelId,
        });
      }

      for (final item in models) {
        debugPrint('[LocalLlm]   modelId=${item['modelId']}, fileSize=${item['fileSize']}');
      }

      final installed = <String>{};
      final sizes = <String, int>{};
      final testResults = <String, bool>{};
      final testResponses = <String, String>{};

      for (final item in models) {
        final modelId = item['modelId'] as String? ?? '';
        final fileSize = item['fileSize'] as int? ?? 0;
        if (modelId.isNotEmpty && fileSize > 1024 * 1024) {
          installed.add(modelId);
          sizes[modelId] = fileSize;
          if (item['testPassed'] != null) {
            testResults[modelId] = item['testPassed'] as bool;
          }
          if (item['testResponse'] != null) {
            testResponses[modelId] = item['testResponse'] as String;
          }
        } else if (modelId.isNotEmpty) {
          // 沒有 fileSize 但有 modelId（從 runtimeState fallback 來的）
          installed.add(modelId);
        }
      }

      debugPrint('[LocalLlm] 掃描完成: ${installed.length} 個已安裝模型 = $installed');

      if (mounted) {
        setState(() {
          _installedModels = installed;
          _installedModelSizes = sizes;
          _modelTestResults = testResults;
          _modelTestResponses = testResponses;
          // [教練 Agent 2026-07-25] 測試通過的模型自動加入候選列表
          for (final entry in testResults.entries) {
            if (entry.value) {
              _candidateModels.add(entry.key);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('[LocalLlm] 掃描已安裝模型失敗: $e');
    }
  }

  /// [教練 Agent 2026-07-20] 測試模型
  Future<void> _testModel(String modelId) async {
    setState(() {
      _testingModels.add(modelId);
      _isLoading = true;
    });
    try {
      // 發送測試命令（背景執行，立即回傳）
      await _runtimeService.testModel(modelId);

      // 輪詢等待測試結果（最多 30 秒）
      for (int i = 0; i < 15; i++) {
        await Future.delayed(const Duration(seconds: 2));
        await _scanInstalledModels();
        // 檢查是否有測試結果了
        if (_modelTestResults.containsKey(modelId)) {
          break;
        }
      }

      // [教練 Agent 2026-07-25] 測試通過自動加入候選列表
      // [小葵 2026-10-01 離合器步驟5 防線B] 快測成功 → 角色判定提示
      // 病例：使用者只下載 12B → 掛載成功快測成功 → 但聊天/任務極慢甚至
      // 空 → 「系統壞掉了」。藥方：快測成功當下教育角色——資訊感非推銷感。
      if (mounted && _modelTestResults[modelId] == true) {
        final isBigModel = modelId.contains('12b') || modelId.contains('14b');
        final alreadyCompanion = _companionRoleModel != null;
        if (isBigModel && !alreadyCompanion) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 12),
              backgroundColor: BridgeDSColors.of(context).surface,
              content: Text(
                '這個模型跑得很穩！它當辨識引擎很優秀，但當聊天夥伴會比較吃力'
                '（速度較慢、記憶較短）。建議在上方「角色配置」把它設為辨識模型，'
                '再挑一個小一點的模型當夥伴？',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                    color: BridgeDSColors.of(context).textPrimary),
              ),
            ),
          );
        }
      }
      if (mounted) {
        setState(() {
          _testingModels.remove(modelId);
          _isLoading = false;
          if (_modelTestResults[modelId] == true) {
            _candidateModels.add(modelId);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testingModels.remove(modelId);
          _isLoading = false;
        });
      }
    }
  }

  /// [教練 Agent 2026-07-20] 加入/移除候選列表
  void _toggleCandidate(String modelId) {
    setState(() {
      if (_candidateModels.contains(modelId)) {
        _candidateModels.remove(modelId);
      } else {
        _candidateModels.add(modelId);
      }
    });
  }

  /// [教練 Agent 2026-07-20] 格式化檔案大小
  String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }



  /// [教練 Agent 2026-07-20] 啟動指定模型（切換模型）
  Future<void> _switchToModel(String modelId) async {
    setState(() => _isLoading = true);
    try {
      final newState = await _runtimeService.startServer(modelId: modelId);
      if (mounted) {
        setState(() {
          _runtimeState = newState;
          _isLoading = false;
        });
        if (newState.phase == BridgeLocalRuntimePhase.starting ||
            newState.phase == BridgeLocalRuntimePhase.running) {
          _startPolling();
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ══════════════════════════════════════════════════════
  // [小葵 2026-09-28] 一鍵切換現役模型（Blue 指令 #2：換模型必須走 App 按鈕）
  // ══════════════════════════════════════════════════════

  /// 該模型是否為現役（server 正在跑且載入的就是它）
  bool _isActiveModel(String modelId) {
    return _runtimeState?.phase == BridgeLocalRuntimePhase.running &&
        _runtimeState?.modelId == modelId;
  }

  /// 切換前確認（模型載入需 10-60 秒，期間本地功能暫停）
  Future<void> _switchToModelWithConfirm(String modelId, String modelName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(ctx).surface,
        title: Text('切換現役模型',
            style: TierStyle.of(ctx, Tier.cardHeroTitle).toTextStyle()),
        content: Text(
          '要把本地模型切換為「$modelName」嗎？\n\n'
          '· 切換時會先停掉目前的模型再載入新的（約 10-60 秒）\n'
          '· 期間本地推理功能暫停服務\n'
          '· 下載過的模型都會保留，隨時可以切回來',
          style: TierStyle.of(ctx, Tier.cardBody).toTextStyle().copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消',
                style: TierStyle.of(ctx, Tier.cardBody).toTextStyle()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: BridgeDSColors.of(ctx).accentPurple,
            ),
            child: Text('切換',
                style: TierStyle.of(ctx, Tier.cardBody).toTextStyle()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSwitchingModel = modelId);
    await _switchToModel(modelId);
    if (mounted) {
      setState(() => _isSwitchingModel = null);
      // 切換後立即刷新狀態（modelId 由 Swift 端寫入 runtime state）
      _loadState();
    }
  }

  /// [教練 Agent 2026-07-20] 刪除已下載的模型
  Future<void> _deleteModel(String modelId) async {
    setState(() => _isLoading = true);
    try {
      final newState = await _runtimeService.deleteModel(modelId);
      if (mounted) {
        setState(() {
          _runtimeState = newState;
          _isLoading = false;
          _installedModels.remove(modelId);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// [教練 Agent 2026-07-20] 從 HuggingFace API 拉取熱門 GGUF 模型
  /// 搜尋 Qwen / Gemma / Llama 三大系列的輕量化 GGUF，按下載量排序
  /// [教練 Agent 2026-07-27] 按硬體 RAM 過濾 — 16GB 機器不顯示 27B+ 大模型
  Future<void> _fetchTrendingModels() async {
    if (_isLoadingTrending) return;
    setState(() => _isLoadingTrending = true);

    try {
      // 根據 RAM 計算可安裝的最大模型大小（bytes）
      // 經驗值：模型檔案大小 ≤ RAM × 0.6（留空間給 KV cache + 系統）
      final ramGb = _hardwareProfile?.ramGb ?? 16;
      // 限制最大參數量：16GB → 8B, 32GB → 14B, 64GB → 30B
      final maxParamB = (ramGb / 2).round().clamp(4, 30);

      final results = <Map<String, dynamic>>[];
      // 三大系列各拉 5 個最新 GGUF（多拉一些再過濾）
      // [Blue 令 2026-10-16 四修] 推薦=最新消息——sort 從 downloads 改
      // lastModified（模型日新月異，商店/推薦每次打開都要是最新）
      for (final query in ['Qwen', 'Gemma', 'Llama']) {
        final response = await _dio.get(
          'https://huggingface.co/api/models',
          queryParameters: {
            'search': query,
            'filter': 'gguf',
            'sort': 'lastModified',
            'direction': '-1',
            'limit': 5,
          },
        );
        final items = (response.data as List).cast<Map<String, dynamic>>();
        for (final item in items) {
          // 去重：如果已在推薦列表中則跳過
          final modelId = item['id'] as String? ?? '';
          final isAlreadyRecommended = _modelPlan?.recommendations.any((r) =>
              r.model.repoId == modelId) ?? false;
          if (!isAlreadyRecommended) {
            // [教練 Agent 2026-07-27] 過濾掉參數量太大的模型
            final shortName = modelId.split('/').last.toLowerCase();
            // 從名稱偵測參數量（如 27b, 30b, 70b 等）
            final paramMatch = RegExp(r'(\d+(?:\.\d+)?)\s*b').firstMatch(shortName);
            if (paramMatch != null) {
              final paramB = double.tryParse(paramMatch.group(1)!) ?? 0;
              if (paramB > maxParamB) continue; // 跳過太大的模型
            }
            results.add(item);
          }
        }
      }
      // 只取前 9 個（三大系列各 3 個）
      final filtered = results.take(9).toList();
      if (mounted) {
        setState(() {
          _trendingModels = filtered;
          _isLoadingTrending = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingTrending = false);
      }
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isSearching = true;
      _searchQuery = query.trim();
    });

    try {
      final response = await _dio.get(
        'https://huggingface.co/api/models',
        queryParameters: {
          'search': query.trim(),
          'filter': 'gguf',
          'sort': 'downloads',
          'direction': '-1',
          'limit': 5,
        },
      );
      final items = (response.data as List).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _searchResults = items;
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Widget _buildFitBadge(LocalModelFit fit) {
    Color color;
    switch (fit) {
      case LocalModelFit.excellent:
        color = BridgeDSColors.of(context).accentGreen;
        break;
      case LocalModelFit.good:
        color = BridgeDSColors.of(context).accentBlue;
        break;
      case LocalModelFit.limited:
        color = BridgeDSColors.of(context).accentYellow;
        break;
      case LocalModelFit.unsupported:
        color = BridgeDSColors.of(context).accentRed;
        break;
      case LocalModelFit.unknown:
        color = BridgeDSColors.of(context).textMuted;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        fit.label,
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: color,
          fontWeight: FontWeight.w600,),
      ),
    );
  }

  Widget _buildRunningInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [U2/F5] 生命週期真話條——訂閱 BrainRevival 單一真相源（alive 靜音）
        StreamBuilder<BrainLifecycle>(
          stream: BrainRevivalService.instance.stream,
          builder: (context, snap) {
            final lc = snap.data ?? BrainRevivalService.instance.lifecycle;
            if (lc.phase == BrainPhase.alive) return const SizedBox.shrink();
            final restarting = lc.phase == BrainPhase.restarting;
            final off = lc.phase == BrainPhase.off; // [Blue 令] 手動關/閒置卸載——資訊色
            final c = BridgeDSColors.of(context);
            final color = off
                ? c.textMuted
                : (restarting ? c.accentYellow : c.accentRed);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                Icon(off
                    ? Icons.bedtime_outlined
                    : (restarting ? Icons.restart_alt : Icons.heart_broken),
                    size: 16,
                    color: color),
                const SizedBox(width: 8),
                Text(
                  off
                      ? '本地模型休眠中'
                      : (restarting ? '重啟大腦中…' : '大腦無回應'),
                  style: TierStyle.of(context, Tier.cardBody)
                      .toTextStyle()
                      .copyWith(color: color, fontWeight: FontWeight.w600),
                ),
                if (lc.detail != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(lc.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TierStyle.of(context, Tier.cardBody)
                            .toTextStyle()
                            .copyWith(color: c.textMuted, fontSize: 12)),
                  ),
                ],
              ]),
            );
          },
        ),
        _buildRunningInfoBody(),
      ],
    );
  }

  Widget _buildRunningInfoBody() {
    // [小葵 2026-10-16 Blue 審計令] 即時健康覆寫——state 檔說 running
    // 但引擎 ping 不通時，誠實顯示無回應（不假冒運行中）。
    // [Blue 報案二修] 引擎不在≠故障：手動關（userEnabled=false）或
    // 閒置自動卸載（idleUnloaded=true）是正當休眠——顯示休眠狀態，不報紅警
    if (_engineUnreachable) {
      final revival = BrainRevivalService.instance;
      if (!revival.userEnabled || revival.idleUnloaded) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.bedtime_outlined,
                  color: BridgeDSColors.of(context).accentBlue, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  revival.idleUnloaded
                      ? '引擎休眠中（閒置 10 分鐘自動卸載，釋放記憶體）——有需求時會自動喚醒，或點頂部「本地模型」立即啟動'
                      : '引擎已手動關閉——點頂部「本地模型」開關啟動',
                  style: TierStyle.of(context, Tier.cardBody)
                      .toTextStyle()
                      .copyWith(color: BridgeDSColors.of(context).accentBlue),
                ),
              ),
            ],
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).accentRed.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: BridgeDSColors.of(context).accentRed.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline,
                color: BridgeDSColors.of(context).accentRed, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '引擎無回應（127.0.0.1:18789 ping 失敗）——狀態檔顯示運行中，但真實引擎沒有回應。請重新啟動引擎。',
                style: TierStyle.of(context, Tier.cardBody)
                    .toTextStyle()
                    .copyWith(color: BridgeDSColors.of(context).accentRed),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle,
                color: BridgeDSColors.of(context).accentGreen,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                '本地 server 運行中',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                  color: BridgeDSColors.of(context).accentGreen,),
              ),
            ],
          ),
          if (_runtimeState!.serverUrl != null) ...[
            const SizedBox(height: 8),
            Text(
              'Server URL: ${_runtimeState!.serverUrl}',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
            ),
          ],
          if (_runtimeState!.activeModelName != null) ...[
            const SizedBox(height: 4),
            Text(
              '模型: ${_runtimeState!.activeModelName}',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
            ),
          ],
          if (_runtimeState!.healthDetail != null) ...[
            const SizedBox(height: 4),
            Text(
              _runtimeState!.healthDetail!,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: BridgeDSColors.of(context).accentRed.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: BridgeDSColors.of(context).accentRed,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _runtimeState!.healthDetail ?? '運行失敗，請檢查詳情',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentRed,),
            ),
          ),
        ],
      ),
    );
  }
}
