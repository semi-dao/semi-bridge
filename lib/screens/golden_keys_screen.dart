import 'dart:async';

import 'package:flutter/material.dart';
import '../core/responsive.dart';
import 'package:go_router/go_router.dart';

import '../models/bridge_action.dart';
import '../models/capability_catalog.dart';
import '../services/capability_activation_signal.dart';
import '../services/capability_catalog_service.dart';
import '../services/capability_health_service.dart';
import '../services/local_hardware_profile_store.dart';
import '../services/local_model_catalog_service.dart';
import '../services/local_model_runtime_service.dart';
import '../services/local_task_routing_service.dart';
import '../services/macos_desktop_shell_channel.dart';
import '../services/summon_readiness_service.dart';
import '../services/task_routing_rule_store.dart';
import '../theme/app_theme.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import 'bridge_desktop_screen.dart';

class GoldenKeysScreen extends StatefulWidget {
  final String? returnTo;

  const GoldenKeysScreen({super.key, this.returnTo});

  @override
  State<GoldenKeysScreen> createState() => _GoldenKeysScreenState();
}

class _GoldenKeysScreenState extends State<GoldenKeysScreen> {
  late Future<_GoldenKeysSnapshot> _snapshotFuture;
  Timer? _runtimePollTimer;
  final _capabilityCatalog = CapabilityCatalogService();

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _loadSnapshot();
  }

  Future<_GoldenKeysSnapshot> _loadSnapshot() async {
    final readiness = await SummonReadinessService().inspect();
    final health = await CapabilityHealthService().inspect();
    final capabilityCatalog = await _capabilityCatalog.inspect();
    final hardware = await _loadHardwareProfile();
    final taskRoutingRules = await const TaskRoutingRuleStore().load();
    final localModelPlan = const LocalModelCatalogService().buildPlan(
      hardware: hardware,
    );
    final localRuntime = await LocalModelRuntimeService().inspectStored();
    final bridgeRuntime = await LocalModelRuntimeService()
        .inspectBridgeRuntime();
    final taskRoutingPlan = const LocalTaskRoutingService().build(
      localModelPlan: localModelPlan,
      health: health,
      rules: taskRoutingRules,
    );
    return _GoldenKeysSnapshot(
      readiness: readiness,
      health: health,
      capabilityCatalog: capabilityCatalog,
      localModelPlan: localModelPlan,
      localRuntime: localRuntime,
      bridgeRuntime: bridgeRuntime,
      taskRoutingPlan: taskRoutingPlan,
    );
  }

  Future<LocalHardwareProfile?> _loadHardwareProfile() async {
    const store = LocalHardwareProfileStore();
    final liveProfile = await const MacosDesktopShellChannel()
        .hardwareProfile();
    if (liveProfile != null && liveProfile.desktopConnected) {
      await store.save(liveProfile);
      return liveProfile;
    }
    return store.load();
  }

  void _refresh() {
    setState(() {
      _snapshotFuture = _loadSnapshot();
    });
  }

  Future<void> _openCustomBridgeDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final triggersController = TextEditingController();
    final providersController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('建立自訂能力橋'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: '輸入能力名稱',
                textField: true,
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '能力名稱'),
                ),
              ),
              Semantics(
                label: '輸入能力描述',
                textField: true,
                child: TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: '這座橋能做什麼'),
                ),
              ),
              Semantics(
                label: '輸入觸發情境或關鍵詞',
                textField: true,
                child: TextField(
                  controller: triggersController,
                  decoration: const InputDecoration(
                    labelText: '觸發情境 / 關鍵詞，用逗號分隔',
                  ),
                ),
              ),
              Semantics(
                label: '輸入候選服務名稱',
                textField: true,
                child: TextField(
                  controller: providersController,
                  decoration: const InputDecoration(
                    labelText: '候選 provider / 服務名稱，用逗號分隔',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.add),
            label: const Text('寫入大腦'),
          ),
        ],
      ),
    );
    if (created != true) return;
    await _capabilityCatalog.registerCustomCapability(
      name: nameController.text,
      description: descriptionController.text,
      triggerPhrases: _splitList(triggersController.text),
      providers: _splitList(providersController.text),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('自訂能力橋已寫入能力目錄與第二大腦。')));
    _refresh();
  }

  List<String> _splitList(String value) {
    return value
        .split(RegExp(r'[,，、\n]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  void _syncRuntimePolling(BridgeLocalRuntimeState state) {
    final shouldPoll =
        state.phase == BridgeLocalRuntimePhase.downloading ||
        state.phase == BridgeLocalRuntimePhase.starting;
    if (!shouldPoll) {
      _runtimePollTimer?.cancel();
      _runtimePollTimer = null;
      return;
    }
    if (_runtimePollTimer?.isActive == true) return;
    _runtimePollTimer = Timer.periodic(const Duration(seconds: 30), (_) { // [v184] 3s→30s：main-thread DB 脈衝止血
      if (!mounted) return;
      _refresh();
    });
  }

  @override
  void dispose() {
    _runtimePollTimer?.cancel();
    super.dispose();
  }

  Future<void> _updateTaskRule(String taskId, TaskRoutingRuleMode mode) async {
    await const TaskRoutingRuleStore().saveRule(taskId, mode);
    _refresh();
  }

  Future<void> _detectLocalRuntime() async {
    final runtime = await LocalModelRuntimeService().detectAndSave();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(runtime.detail)));
    _refresh();
  }

  Future<void> _activateLocalRuntime(LocalModelRuntimeProfile runtime) async {
    try {
      await LocalModelRuntimeService().activateAsBrain(runtime);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切換成本地主腦：${runtime.selectedModel}')),
      );
      // [以利沙 P0 修復 2026-06-27] 補發 CapabilityActivationBus 信號
      CapabilityActivationBus.instance.emitReady(
        title: '本地 AI 模型能力已開通',
        source: 'golden-keys.local-model',
      );
      if (mounted && widget.returnTo != null && widget.returnTo!.contains('/chat')) {
        context.go(widget.returnTo!);
        return;
      }
      _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('切換失敗：$error')));
    }
  }

  Future<void> _runBridgeRuntimePrimaryAction(
    LocalModelPlan plan,
    BridgeLocalRuntimeState currentState,
  ) async {
    final service = LocalModelRuntimeService();
    final state = switch (currentState.primaryCommand) {
      BridgeLocalRuntimeCommand.prepareRuntime =>
        await service.prepareBridgeRuntime(),
      BridgeLocalRuntimeCommand.downloadModel => await service.downloadModel(
        plan.preferredDownload!,
      ),
      BridgeLocalRuntimeCommand.startServer => await service.startServer(),
      BridgeLocalRuntimeCommand.stopServer => await service.stopServer(),
      BridgeLocalRuntimeCommand.deleteModel => await service.inspectBridgeRuntime(),
      BridgeLocalRuntimeCommand.testModel => await service.inspectBridgeRuntime(),
      BridgeLocalRuntimeCommand.startLabServer => await service.inspectBridgeRuntime(),
      BridgeLocalRuntimeCommand.stopLabServer => await service.inspectBridgeRuntime(),
      BridgeLocalRuntimeCommand.status => await service.inspectBridgeRuntime(),
    };
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(state.detail)));
    _refresh();
  }

  void _emitFormalBridgeCapabilityReady(_FormalBridgeAbility ability) {
    CapabilityActivationBus.instance.emitReady(
      title: '${ability.label}能力已開通',
      source: 'golden-keys.formal-bridge',
      actionType: ability.actionType,
      provider: ability.provider,
    );
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('${ability.label}能力已發出完成訊號；如果聊天中有相符卡點，會自動回去接續。'),
          backgroundColor: BridgeDSColors.of(context).accentPurple,
          duration: const Duration(seconds: 4),
        ),
      );
    if (widget.returnTo != null && widget.returnTo!.contains('/chat')) {
      context.go(widget.returnTo!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceHighlight,
      appBar: AppBar(
        title: const Text('金鑰匙中心'),
        backgroundColor: AppTheme.background,
        leading: Semantics(
          label: '返回',
          button: true,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, size: 28), // [P1-12 修復 2026-06-30] 統一返回箭頭
            tooltip: '返回',
            onPressed: () => context.go(widget.returnTo ?? '/chat'),
          ),
        ),
        actions: [
          Semantics(
            label: '重新檢查金鑰',
            button: true,
            child: IconButton(
              tooltip: '重新檢查',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_GoldenKeysSnapshot>(
          future: _snapshotFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data;
            if (data == null) {
              return const Center(child: Text('金鑰匙狀態讀取失敗'));
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _syncRuntimePolling(data.bridgeRuntime);
            });

            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = Responsive.isDesktop(context) ||
                  constraints.maxWidth >= 980;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTheme.spacingM),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeroCard(readiness: data.readiness),
                      const SizedBox(height: AppTheme.spacingM),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _BrainKeyCard(data: data)),
                            const SizedBox(width: AppTheme.spacingM),
                            Expanded(child: _CreativeKeyCard(data: data)),
                          ],
                        )
                      else ...[
                        _BrainKeyCard(data: data),
                        const SizedBox(height: AppTheme.spacingM),
                        _CreativeKeyCard(data: data),
                      ],
                      const SizedBox(height: AppTheme.spacingM),
                      _SearchKeyCard(data: data),
                      const SizedBox(height: AppTheme.spacingM),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _LocalModelKeyCard(
                                plan: data.localModelPlan,
                                runtime: data.localRuntime,
                                bridgeRuntime: data.bridgeRuntime,
                                onBridgeRuntimePrimaryAction:
                                    _runBridgeRuntimePrimaryAction,
                                onDetect: _detectLocalRuntime,
                                onActivate: _activateLocalRuntime,
                              ),
                            ),
                            const SizedBox(width: AppTheme.spacingM),
                            Expanded(
                              child: _TaskRoutingCard(
                                plan: data.taskRoutingPlan,
                                onRuleChanged: _updateTaskRule,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _LocalModelKeyCard(
                          plan: data.localModelPlan,
                          runtime: data.localRuntime,
                          bridgeRuntime: data.bridgeRuntime,
                          onBridgeRuntimePrimaryAction:
                              _runBridgeRuntimePrimaryAction,
                          onDetect: _detectLocalRuntime,
                          onActivate: _activateLocalRuntime,
                        ),
                        const SizedBox(height: AppTheme.spacingM),
                        _TaskRoutingCard(
                          plan: data.taskRoutingPlan,
                          onRuleChanged: _updateTaskRule,
                        ),
                      ],
                      const SizedBox(height: AppTheme.spacingM),
                      _CapabilityCatalogCard(
                        capabilities: data.capabilityCatalog,
                        onCreateCustomBridge: _openCustomBridgeDialog,
                      ),
                      const SizedBox(height: AppTheme.spacingM),
                      _FormalBridgeCapabilityCard(
                        data: data,
                        onCapabilityReady: _emitFormalBridgeCapabilityReady,
                      ),
                      const SizedBox(height: AppTheme.spacingM),
                      _KeyActionBar(returnTo: widget.returnTo),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _GoldenKeysSnapshot {
  final SummonReadiness readiness;
  final List<CapabilityHealthItem> health;
  final List<CapabilityRuntimeStatus> capabilityCatalog;
  final LocalModelPlan localModelPlan;
  final LocalModelRuntimeProfile localRuntime;
  final BridgeLocalRuntimeState bridgeRuntime;
  final TaskRoutingPlan taskRoutingPlan;

  const _GoldenKeysSnapshot({
    required this.readiness,
    required this.health,
    required this.capabilityCatalog,
    required this.localModelPlan,
    required this.localRuntime,
    required this.bridgeRuntime,
    required this.taskRoutingPlan,
  });

  CapabilityHealthItem? itemFor(BridgeActionType type) {
    for (final item in health) {
      if (item.type == type) return item;
    }
    return null;
  }

  CapabilityHealthItem? itemByLabel(String label) {
    for (final item in health) {
      if (item.label == label) return item;
    }
    return null;
  }
}

class _HeroCard extends StatelessWidget {
  final SummonReadiness readiness;

  _HeroCard({required this.readiness});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.accent, AppTheme.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: BridgeDSColors.of(context).textPrimary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
            ),
            child: const Icon(
              Icons.vpn_key_outlined,
              color: AppTheme.secondary,
              size: 30,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '握住你的 AI 主權金鑰',
                  style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
                SizedBox(height: 8),
                Text(
                  readiness.summary,
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                    fontWeight: FontWeight.w700,
                    height: 1.45,),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrainKeyCard extends StatelessWidget {
  final _GoldenKeysSnapshot data;

  const _BrainKeyCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final chat = data.itemByLabel('聊天');
    return _KeyCard(
      icon: Icons.psychology_alt_outlined,
      title: '主腦鑰匙',
      subtitle: '聊天、判斷、語意壓縮與思維儀表',
      status: data.readiness.brainReady ? '可用' : '缺少金鑰',
      ready: data.readiness.brainReady,
      detail:
          '${_providerName(data.readiness.brainProvider)} · ${chat?.detail ?? '等待設定主腦 provider token'}',
      children: [
        const _KeyPermissionLine(label: '可用任務', value: '對話、意圖判斷、上下文壓縮'),
        const _KeyPermissionLine(label: '資料邊界', value: '任務內容送往所選主腦 provider'),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => BridgeDesktopScreen.navigateTo('system'),
            icon: const Icon(Icons.key_outlined, size: 16),
            label: Text(data.readiness.brainReady ? '管理雲端主腦' : '設定雲端主腦'),
          ),
        ),
      ],
    );
  }
}

class _CreativeKeyCard extends StatelessWidget {
  final _GoldenKeysSnapshot data;

  const _CreativeKeyCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final image = data.itemFor(BridgeActionType.generateImage);
    return _KeyCard(
      icon: Icons.auto_awesome_outlined,
      title: '創造鑰匙',
      subtitle: '夥伴形象、角色設定圖組與未來素材生成',
      status: data.readiness.imageReady ? '可用' : '缺少金鑰',
      ready: data.readiness.imageReady,
      detail: '圖片生成服務 · ${image?.detail ?? '等待圖片生成 provider token'}',
      children: [
        const _KeyPermissionLine(label: '可用任務', value: '生成夥伴形象、角色圖組'),
        const _KeyPermissionLine(
          label: '成本提醒',
          value: '生成圖片前應顯示 provider 與預估花費',
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => BridgeDesktopScreen.navigateTo('system'),
            icon: const Icon(Icons.auto_awesome_outlined, size: 16),
            label: Text(data.readiness.imageReady ? '管理圖片生成金鑰' : '設定圖片生成金鑰'),
          ),
        ),
      ],
    );
  }
}

class _SearchKeyCard extends StatelessWidget {
  final _GoldenKeysSnapshot data;

  const _SearchKeyCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final browse = data.itemFor(BridgeActionType.browse);
    final ready = browse?.status == CapabilityHealthStatus.ready;
    return _KeyCard(
      icon: Icons.travel_explore_outlined,
      title: '搜尋鑰匙',
      subtitle: '新聞、網頁、時刻表與時間敏感資訊查詢',
      status: ready ? '可用' : '缺少金鑰',
      ready: ready,
      detail: '新聞與網頁搜尋橋 · ${browse?.detail ?? '等待 OpenAI Web Search token'}',
      children: [
        const _KeyPermissionLine(
          label: '可用任務',
          value: '查新聞、找資料、查時刻表、整理來源與時間敏感資訊',
        ),
        const _KeyPermissionLine(
          label: '資料邊界',
          value: '搜尋問題會送往搜尋 provider；回覆必須附摘要、時間與可追查來源',
        ),
        const _KeyPermissionLine(
          label: '建議服務',
          value: '目前 v0 使用 OpenAI Web Search；未來可接 Bridge Desktop 或社群搜尋插件',
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => BridgeDesktopScreen.navigateTo('system'),
            icon: const Icon(Icons.manage_search_outlined, size: 16),
            label: Text(ready ? '管理搜尋金鑰' : '設定搜尋金鑰'),
          ),
        ),
      ],
    );
  }
}

class _LocalModelKeyCard extends StatelessWidget {
  final LocalModelPlan plan;
  final LocalModelRuntimeProfile runtime;
  final BridgeLocalRuntimeState bridgeRuntime;
  final Future<void> Function(
    LocalModelPlan plan,
    BridgeLocalRuntimeState currentState,
  )
  onBridgeRuntimePrimaryAction;
  final Future<void> Function() onDetect;
  final Future<void> Function(LocalModelRuntimeProfile runtime) onActivate;

  const _LocalModelKeyCard({
    required this.plan,
    required this.runtime,
    required this.bridgeRuntime,
    required this.onBridgeRuntimePrimaryAction,
    required this.onDetect,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    final ready =
        bridgeRuntime.installed ||
        runtime.connected ||
        plan.hardware.desktopConnected;
    return _KeyCard(
      icon: Icons.memory_outlined,
      title: '本地模型鑰匙',
      subtitle: 'Bridge 內建本地模型引擎、硬體檢測與模型管理',
      status: bridgeRuntime.running
          ? bridgeRuntime.phase.label
          : runtime.connected
          ? runtime.statusLabel
          : plan.hardware.desktopConnected
          ? '可評估'
          : '待桌面檢測',
      ready: ready,
      detail: bridgeRuntime.running
          ? bridgeRuntime.detail
          : runtime.connected
          ? runtime.detail
          : bridgeRuntime.detail,
      children: [
        _BridgeLocalRuntimePanel(
          state: bridgeRuntime,
          plan: plan,
          desktopConnected: plan.hardware.desktopConnected,
          onPrimaryAction: onBridgeRuntimePrimaryAction,
        ),
        const SizedBox(height: 16),
        _KeyPermissionLine(
          label: '相容入口',
          value:
              '${runtime.runtimeLabel} · ${runtime.endpoint} · ${runtime.statusLabel}',
        ),
        if (runtime.selectedModel != null)
          _KeyPermissionLine(label: '目前模型', value: runtime.selectedModel!),
        const SizedBox(height: 8),
        _LocalRuntimeActions(
          runtime: runtime,
          onDetect: onDetect,
          onActivate: onActivate,
        ),
        const SizedBox(height: 8),
        _KeyPermissionLine(
          label: '硬體檢測',
          value:
              '${plan.hardware.chipLabel} · RAM ${plan.hardware.ramGb?.toString() ?? '--'}GB · VRAM ${plan.hardware.vramGb?.toString() ?? '--'}GB',
        ),
        _KeyPermissionLine(label: '模型建議', value: plan.summary),
        const _KeyPermissionLine(
          label: '下載方式',
          value: '正式版由 Bridge Desktop 一鍵下載與啟動，不要求使用者碰複雜命令',
        ),
        const _KeyPermissionLine(label: '主權價值', value: '私人任務可優先交給本地模型處理'),
        const SizedBox(height: 16),
        ...plan.recommendations.map(_LocalModelRow.new),
      ],
    );
  }
}

class _LocalModelRow extends StatelessWidget {
  final LocalModelRecommendation recommendation;

  const _LocalModelRow(this.recommendation);

  @override
  Widget build(BuildContext context) {
    final fitColor = _fitColor(recommendation.fit);
    final model = recommendation.model;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: fitColor.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fitColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Text(
              model.sizeClass,
              style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: fitColor,
                fontWeight: FontWeight.w900,),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${model.name} · ${model.quantization}',
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
                const SizedBox(height: 0),
                Text(
                  '${model.downloadSize} · ${model.bestFor.map((task) => task.label).join('、')}',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                    height: 1.35,),
                ),
                const SizedBox(height: 0),
                Text(
                  '${model.sourceLabel} · ${model.licenseLabel}',
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                    height: 1.25,
                    fontWeight: FontWeight.w700,),
                ),
                const SizedBox(height: 0),
                Text(
                  recommendation.reason,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                    height: 1.25,),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusPill(label: recommendation.fit.label, color: fitColor),
        ],
      ),
    );
  }

  Color _fitColor(LocalModelFit fit) {
    switch (fit) {
      case LocalModelFit.excellent:
      case LocalModelFit.good:
        return BridgeDS.accentGreen;
      case LocalModelFit.limited:
      case LocalModelFit.unknown:
        return BridgeDS.accentYellow;
      case LocalModelFit.unsupported:
        return AppTheme.error;
    }
  }
}

class _BridgeLocalRuntimePanel extends StatelessWidget {
  final BridgeLocalRuntimeState state;
  final LocalModelPlan plan;
  final bool desktopConnected;
  final Future<void> Function(
    LocalModelPlan plan,
    BridgeLocalRuntimeState currentState,
  )
  onPrimaryAction;

  const _BridgeLocalRuntimePanel({
    required this.state,
    required this.plan,
    required this.desktopConnected,
    required this.onPrimaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (state.phase) {
      BridgeLocalRuntimePhase.running ||
      BridgeLocalRuntimePhase.installed => BridgeDSColors.of(context).accentGreen,
      BridgeLocalRuntimePhase.downloading ||
      BridgeLocalRuntimePhase.starting => BridgeDSColors.of(context).accentPurple,
      BridgeLocalRuntimePhase.failed => AppTheme.error,
      BridgeLocalRuntimePhase.notInstalled => BridgeDSColors.of(context).accentYellow,
    };
    final canRunPrimary =
        desktopConnected &&
        state.primaryActionEnabled &&
        (state.primaryCommand != BridgeLocalRuntimeCommand.downloadModel ||
            plan.preferredDownload != null);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.title,
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
              ),
              _StatusPill(label: state.phase.label, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            desktopConnected
                ? state.detail
                : '本地模型下載與啟動需要 Bridge Desktop 桌面 App。你目前在網頁預覽中，可以查看狀態，但不能直接下載本地引擎或模型。',
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
              height: 1.35,
              fontWeight: FontWeight.w700,),
          ),
          if (state.progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: state.progress),
          ],
          if (state.installed ||
              state.phase == BridgeLocalRuntimePhase.downloading ||
              state.phase == BridgeLocalRuntimePhase.failed) ...[
            const SizedBox(height: 8),
            _BridgeRuntimeChecklist(state: state),
          ],
          if (!desktopConnected) ...[
            const SizedBox(height: 8),
            const _DesktopRuntimeRequiredNotice(),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canRunPrimary
                  ? () => onPrimaryAction(plan, state)
                  : null,
              icon: const Icon(Icons.download_for_offline_outlined, size: 16),
              label: Text(
                desktopConnected
                    ? state.primaryActionLabel
                    : '請在 Bridge Desktop 內下載',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormalBridgeCapabilityCard extends StatelessWidget {
  final _GoldenKeysSnapshot data;
  final ValueChanged<_FormalBridgeAbility> onCapabilityReady;

  const _FormalBridgeCapabilityCard({
    required this.data,
    required this.onCapabilityReady,
  });

  @override
  Widget build(BuildContext context) {
    return _KeyCard(
      icon: Icons.hub_outlined,
      title: '正式橋能力',
      subtitle: '新聞搜尋、音樂生成、桌面整理、圖片辨識的開通完成出口',
      status: '訊號中心',
      ready: true,
      detail: '完成任一能力設定後，在這裡送出完成訊號；聊天頁會自動回到相符的待恢復任務。',
      children: [
        const _KeyPermissionLine(
          label: '使用方式',
          value: '先完成官方服務、插件或桌面橋設定，再按該能力的完成按鈕。',
        ),
        const _KeyPermissionLine(
          label: '誠實邊界',
          value: '這裡只負責回到卡點；真正能不能產出，仍由 adapter / provider 決定。',
        ),
        const SizedBox(height: 8),
        ..._formalBridgeAbilities.map(
          (ability) => _FormalBridgeAbilityRow(
            ability: ability,
            health: data.itemFor(ability.actionType),
            onReady: () => onCapabilityReady(ability),
          ),
        ),
      ],
    );
  }
}

class _CapabilityCatalogCard extends StatelessWidget {
  final List<CapabilityRuntimeStatus> capabilities;
  final VoidCallback onCreateCustomBridge;

  const _CapabilityCatalogCard({
    required this.capabilities,
    required this.onCreateCustomBridge,
  });

  @override
  Widget build(BuildContext context) {
    final readyCount = capabilities.where((item) => item.ready).length;
    return _KeyCard(
      icon: Icons.account_tree_outlined,
      title: '能力目錄 / 大腦技能表',
      subtitle: '大腦會依這份清單判斷自己會什麼、缺什麼、下一步該接哪座橋。',
      status: '$readyCount/${capabilities.length} 可用',
      ready: readyCount > 0,
      detail: '新增自訂能力橋後，會同步寫入第二大腦 Bridges 房間，未來可被思維儀表與任務路由讀取。',
      children: [
        const _KeyPermissionLine(
          label: '資料邊界',
          value: '這裡是能力卡與路由語意，不等於 adapter 已完成；真正執行仍由 provider / 插件測試決定。',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: capabilities
              .map((capability) => _CapabilityCatalogChip(capability))
              .toList(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onCreateCustomBridge,
            icon: const Icon(Icons.add_link_outlined),
            label: const Text('建立自訂能力橋'),
          ),
        ),
      ],
    );
  }
}

class _CapabilityCatalogChip extends StatelessWidget {
  final CapabilityRuntimeStatus capability;

  const _CapabilityCatalogChip(this.capability);

  @override
  Widget build(BuildContext context) {
    final color = switch (capability.availability) {
      CapabilityAvailability.ready => BridgeDSColors.of(context).accentGreen,
      CapabilityAvailability.needsSetup => BridgeDSColors.of(context).accentYellow,
      CapabilityAvailability.unsupported => AppTheme.error,
      CapabilityAvailability.planned => BridgeDSColors.of(context).accentPurple,
    };
    return Tooltip(
      message: '查看${capability.definition.name}能力卡',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        onTap: () => _showCapabilityDetail(context, color),
        child: Container(
          constraints: const BoxConstraints(minWidth: 150, maxWidth: 230),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: color.withValues(alpha: 0.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconFor(capability.definition.kind),
                color: color,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      capability.definition.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                        fontWeight: FontWeight.w900,),
                    ),
                    Text(
                      capability.availability.label,
                      style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: color,
                        fontWeight: FontWeight.w900,),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCapabilityDetail(BuildContext context, Color color) {
    final definition = capability.definition;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(_iconFor(definition.kind), color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(definition.name)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CapabilityDetailLine(
                  label: '狀態',
                  value: capability.availability.label,
                ),
                _CapabilityDetailLine(
                  label: 'Provider',
                  value: capability.providerLabel,
                ),
                _CapabilityDetailLine(
                  label: '用途',
                  value: definition.description,
                ),
                _CapabilityDetailLine(
                  label: 'v0 範圍',
                  value: definition.v0Scope,
                ),
                _CapabilityDetailLine(
                  label: '輸入',
                  value: definition.inputFormat,
                ),
                _CapabilityDetailLine(
                  label: '輸出',
                  value: definition.outputFormat,
                ),
                _CapabilityDetailLine(
                  label: '證據類型',
                  value: definition.evidenceKind,
                ),
                _CapabilityDetailLine(
                  label: 'Adapter',
                  value: definition.adapterContract,
                ),
                _CapabilityDetailLine(
                  label: '社群插件',
                  value: definition.communityPluginNote,
                ),
                _CapabilityDetailLine(label: '下一步', value: capability.nextStep),
                if (definition.setupSteps.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '開通步驟',
                    style: TextStyle(
                      color: BridgeDSColors.of(context).textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final entry in definition.setupSteps.asMap().entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${entry.key + 1}. ${entry.value}',
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                          height: 1.35,),
                      ),
                    ),
                ],
                if (definition.officialEntryHints.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: definition.officialEntryHints
                        .map((hint) => Chip(label: Text(hint)))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('關閉'),
            ),
          ],
        );
      },
    );
  }

  IconData _iconFor(CapabilityKind kind) {
    switch (kind) {
      case CapabilityKind.search:
        return Icons.travel_explore_outlined;
      case CapabilityKind.vision:
        return Icons.image_search_outlined;
      case CapabilityKind.image:
        return Icons.auto_awesome_outlined;
      case CapabilityKind.music:
        return Icons.music_note_outlined;
      case CapabilityKind.video:
        return Icons.movie_creation_outlined;
      case CapabilityKind.document:
        return Icons.description_outlined;
      case CapabilityKind.desktop:
        return Icons.desktop_windows_outlined;
      case CapabilityKind.animation:
        return Icons.animation_outlined;
      case CapabilityKind.custom:
        return Icons.add_link_outlined;
    }
  }
}

class _CapabilityDetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _CapabilityDetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                fontWeight: FontWeight.w800,),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                height: 1.35,
                fontWeight: FontWeight.w700,),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormalBridgeAbilityRow extends StatelessWidget {
  final _FormalBridgeAbility ability;
  final CapabilityHealthItem? health;
  final VoidCallback onReady;

  const _FormalBridgeAbilityRow({
    required this.ability,
    required this.health,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    final status = health?.status;
    final color = status == CapabilityHealthStatus.ready
        ? BridgeDSColors.of(context).accentGreen
        : ability.requiresDesktopBridge
        ? BridgeDSColors.of(context).accentPurple
        : BridgeDSColors.of(context).accentYellow;
    final statusLabel = status == CapabilityHealthStatus.ready
        ? '已接 adapter'
        : ability.requiresDesktopBridge
        ? '靠桌面橋'
        : '等待插件';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Icon(ability.icon, color: color, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ability.label,
                        style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                          fontWeight: FontWeight.w900,),
                      ),
                    ),
                    _StatusPill(label: statusLabel, color: color),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  ability.detail,
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                    height: 1.35,
                    fontWeight: FontWeight.w700,),
                ),
                if (health != null) ...[
                  const SizedBox(height: 0),
                  Text(
                    health!.detail,
                    style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                      height: 1.25,
                      fontWeight: FontWeight.w700,),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: ValueKey('formal-bridge-ready-${ability.id}'),
            onPressed: onReady,
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('我已設定完成'), // [P2-26 修復 2026-06-30] 語意更清楚
          ),
        ],
      ),
    );
  }
}

class _FormalBridgeAbility {
  final String id;
  final BridgeActionType actionType;
  final String label;
  final String detail;
  final IconData icon;
  final String provider;
  final bool requiresDesktopBridge;

  const _FormalBridgeAbility({
    required this.id,
    required this.actionType,
    required this.label,
    required this.detail,
    required this.icon,
    required this.provider,
    this.requiresDesktopBridge = false,
  });
}

const _formalBridgeAbilities = [
  _FormalBridgeAbility(
    id: 'browse-news',
    actionType: BridgeActionType.browse,
    label: '新聞與網頁搜尋',
    detail: '用於查新聞、找資料、整理網頁來源；正式版會接瀏覽/搜尋 adapter。',
    icon: Icons.travel_explore_outlined,
    provider: 'bridge-desktop',
    requiresDesktopBridge: true,
  ),
  _FormalBridgeAbility(
    id: 'music',
    actionType: BridgeActionType.generateMusic,
    label: '音樂生成',
    detail: '用於產生配樂、讀書音樂、音效；等待音樂 provider 或 SemiDAO 插件。',
    icon: Icons.music_note_outlined,
    provider: 'semi-dao-music-plugin',
  ),
  _FormalBridgeAbility(
    id: 'desktop-files',
    actionType: BridgeActionType.browse,
    label: '桌面檔案整理',
    detail: '用於讀取、分類、命名與整理本機檔案；目前走 Bridge Desktop 能力線。',
    icon: Icons.folder_copy_outlined,
    provider: 'bridge-desktop',
    requiresDesktopBridge: true,
  ),
  _FormalBridgeAbility(
    id: 'vision',
    actionType: BridgeActionType.vision,
    label: '圖片辨識',
    detail: '用於辨識圖片內容、分析截圖與視覺線索；等待 Vision provider 或插件。',
    icon: Icons.image_search_outlined,
    provider: 'vision-provider',
  ),
];

class _DesktopRuntimeRequiredNotice extends StatelessWidget {
  const _DesktopRuntimeRequiredNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: const Color(0xFFF6C453).withValues(alpha: 0.44),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.desktop_mac_outlined, color: Color(0xFFB7791F), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '請開啟 Bridge Desktop App 後，在桌面版金鑰匙中心按「準備下載本地引擎」。網頁預覽沒有權限下載 llama-server 或 GGUF 模型檔。',
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                height: 1.35,
                fontWeight: FontWeight.w700,),
            ),
          ),
        ],
      ),
    );
  }
}

class _BridgeRuntimeChecklist extends StatelessWidget {
  final BridgeLocalRuntimeState state;

  const _BridgeRuntimeChecklist({required this.state});

  @override
  Widget build(BuildContext context) {
    final enginePath =
        state.runtimeExecutablePath ?? state.expectedRuntimeExecutablePath;
    final modelPath = state.modelFilePath ?? state.expectedModelFilePath;
    final serverUrl = state.serverUrl ?? 'http://127.0.0.1:18789';

    return Column(
      children: [
        _RuntimeCheckLine(
          icon: Icons.terminal_rounded,
          label: '推論引擎',
          ready: state.runtimeExecutablePath != null,
          value: state.runtimeExecutablePath != null
              ? '已找到 llama-server'
              : '等待 Bridge Desktop 放入 llama-server',
          hint: enginePath,
        ),
        _RuntimeCheckLine(
          icon: Icons.memory_rounded,
          label: '模型檔',
          ready: state.modelFilePath != null,
          value: state.modelFilePath != null ? '已找到 GGUF 模型' : '等待模型下載完成',
          hint: modelPath,
        ),
        _RuntimeCheckLine(
          icon: Icons.sensors_rounded,
          label: '本地服務',
          ready: state.phase == BridgeLocalRuntimePhase.running,
          value: state.phase == BridgeLocalRuntimePhase.running
              ? '已啟動，可以分配任務'
              : '尚未啟動',
          hint: serverUrl,
        ),
        _RuntimeCheckLine(
          icon: Icons.health_and_safety_outlined,
          label: '健康檢查',
          ready: state.serverHealthy == true,
          value: state.serverHealthy == true
              ? '模型 API 已回應'
              : state.serverHealthy == false
              ? '等待模型 API 回應'
              : '啟動後自動檢查',
          hint: state.healthDetail,
        ),
      ],
    );
  }
}

class _RuntimeCheckLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool ready;
  final String value;
  final String? hint;

  _RuntimeCheckLine({
    required this.icon,
    required this.label,
    required this.ready,
    required this.value,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final color = ready ? BridgeDSColors.of(context).accentGreen : BridgeDSColors.of(context).accentYellow;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).textPrimary.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label：$value',
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 0),
                  Text(
                    hint!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                      fontWeight: FontWeight.w700,),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusPill(label: ready ? '可用' : '待處理', color: color),
        ],
      ),
    );
  }
}

class _LocalRuntimeActions extends StatelessWidget {
  final LocalModelRuntimeProfile runtime;
  final Future<void> Function() onDetect;
  final Future<void> Function(LocalModelRuntimeProfile runtime) onActivate;

  const _LocalRuntimeActions({
    required this.runtime,
    required this.onDetect,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onDetect,
            icon: const Icon(Icons.radar_outlined, size: 16),
            label: const Text('進階：連接既有服務'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: runtime.connected ? () => onActivate(runtime) : null,
            icon: const Icon(Icons.memory_rounded, size: 16),
            label: const Text('設成本地主腦'),
          ),
        ),
      ],
    );
  }
}

class _TaskRoutingCard extends StatelessWidget {
  final TaskRoutingPlan plan;
  final Future<void> Function(String taskId, TaskRoutingRuleMode mode)
  onRuleChanged;

  const _TaskRoutingCard({required this.plan, required this.onRuleChanged});

  @override
  Widget build(BuildContext context) {
    return _KeyCard(
      icon: Icons.account_tree_outlined,
      title: '任務分配',
      subtitle: '讓每把鑰匙負責最適合的任務',
      status: plan.readyCount > 0 ? '${plan.readyCount} 條路線' : '待設定',
      ready: plan.readyCount > 0,
      detail: plan.summary,
      children: [
        const _KeyPermissionLine(label: '分配原則', value: '隱私、本地算力、成本、速度與任務品質'),
        const _KeyPermissionLine(label: '使用者控制', value: '每種任務都可手動指定模型與確認規則'),
        const SizedBox(height: 16),
        ...plan.items.map(
          (item) => _TaskRouteRow(item, onRuleChanged: onRuleChanged),
        ),
      ],
    );
  }
}

class _TaskRouteRow extends StatelessWidget {
  final TaskRoutingItem item;
  final Future<void> Function(String taskId, TaskRoutingRuleMode mode)
  onRuleChanged;

  const _TaskRouteRow(this.item, {required this.onRuleChanged});

  @override
  Widget build(BuildContext context) {
    final color = _laneColor(item.lane);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
              ),
              _StatusPill(label: item.lane.label, color: color),
            ],
          ),
          const SizedBox(height: 8),
          _TaskRuleDropdown(
            value: item.ruleMode,
            onChanged: (mode) => onRuleChanged(item.id, mode),
          ),
          const SizedBox(height: 8),
          Text(
            item.scenario,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
              height: 1.3,),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _MiniRouteChip(label: '主', value: item.primaryKey, color: color),
              _MiniRouteChip(
                label: '備',
                value: item.backupKey,
                color: BridgeDSColors.of(context).textMuted,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.reason,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
              height: 1.3,),
          ),
        ],
      ),
    );
  }

  Color _laneColor(TaskExecutionLane lane) {
    switch (lane) {
      case TaskExecutionLane.localFirst:
        return BridgeDS.accentGreen;
      case TaskExecutionLane.cloudFirst:
        return AppTheme.accent;
      case TaskExecutionLane.hybrid:
        return BridgeDS.accentPurple;
      case TaskExecutionLane.askEveryTime:
        return AppTheme.secondary;
      case TaskExecutionLane.setupRequired:
        return BridgeDS.accentYellow;
    }
  }
}

class _TaskRuleDropdown extends StatelessWidget {
  final TaskRoutingRuleMode value;
  final ValueChanged<TaskRoutingRuleMode> onChanged;

  const _TaskRuleDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40, // [P2-41 修復 2026-06-30] 32→40 更好按
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TaskRoutingRuleMode>(
          value: value,
          isExpanded: true,
          iconSize: 18,
          style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
            fontWeight: FontWeight.w800,),
          items: [
            for (final mode in TaskRoutingRuleMode.values)
              DropdownMenuItem(value: mode, child: Text(mode.label)),
          ],
          onChanged: (mode) {
            if (mode != null) onChanged(mode);
          },
        ),
      ),
    );
  }
}

class _MiniRouteChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniRouteChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: RichText(
        text: TextSpan(
          style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800),
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(color: color),
            ),
            TextSpan(
              text: value,
              style: TextStyle(color: BridgeDSColors.of(context).textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final bool ready;
  final String detail;
  final List<Widget> children;

  const _KeyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.ready,
    required this.detail,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final color = ready ? BridgeDSColors.of(context).accentGreen : BridgeDSColors.of(context).accentYellow;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                        fontWeight: FontWeight.w900,),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                        fontWeight: FontWeight.w700,
                        height: 1.35,),
                    ),
                  ],
                ),
              ),
              _StatusPill(label: status, color: color),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            detail,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
              height: 1.4,),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _KeyPermissionLine extends StatelessWidget {
  final String label;
  final String value;

  const _KeyPermissionLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                fontWeight: FontWeight.w800,),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.35,),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: color,
          fontWeight: FontWeight.w900,),
      ),
    );
  }
}

class _KeyActionBar extends StatelessWidget {
  final String? returnTo;

  const _KeyActionBar({required this.returnTo});

  @override
  Widget build(BuildContext context) {
    final settingsUri = Uri(
      path: '/system',
      queryParameters: {
        'returnTo': '/chat',
      },
    );
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.go(settingsUri.toString()),
            icon: const Icon(Icons.key_outlined),
            label: const Text('編輯雲端鑰匙'),
          ),
        ),
        const SizedBox(width: AppTheme.spacingM),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => context.go(returnTo ?? '/chat'),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('完成'),
          ),
        ),
      ],
    );
  }
}

String _providerName(String provider) {
  switch (provider) {
    case 'openai':
      return 'OpenAI';
    case 'replicate':
      return 'Replicate';
    case 'kimi':
      return 'Kimi';
    case 'minimax':
      return 'MiniMax';
    case 'claude':
      return 'Claude';
    case 'gemini':
      return 'Gemini';
    default:
      return provider;
  }
}
