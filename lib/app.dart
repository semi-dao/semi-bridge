import 'dart:async';
import 'dart:io' show File, Directory, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'controllers/chat_controller.dart';
import 'services/system/daemon_client.dart';
import 'services/system/tray_service.dart'; // [隊友訊息流 C7]
import 'services/bridge_mcp_server.dart';
import 'state/theme_provider.dart';
import 'state/typography_scale_provider.dart';
import 'theme/bridge_design_system.dart';
import 'theme/tier_style.dart'; // [教練 Agent 2026-08-05] Step 3c — TierTheme 接到 MaterialApp
import 'services/app_retina.dart'; // [教練 Agent 2026-08-22] 全域視網膜
import 'screens/bridge_desktop_screen.dart';
import 'services/agent_loop/agent_safety.dart'; // [D002] D002 safety confirmation
import 'screens/desktop_welcome_screen.dart';
import 'screens/desktop_summon_screen.dart';
// [2026-10-06 封存] desktop_homepage_screen.dart → lib/screens/_archived/
// （孤兒頁面：全 App 零導航入口，Blue 拍板封存）
import 'screens/slot_management_screen.dart'; // [無限插槽 C2 2026-10-06 移植]
import 'screens/lock_screen.dart';
import 'screens/mobile_bridge_pairing_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/first_summon_screen.dart';
import 'screens/capability_center_screen.dart'; // [教練 Agent 2026-08-01] 能力中心
import 'screens/summon_screen.dart';
import 'screens/companion_list_screen.dart';
import 'screens/companion_control_center_screen.dart'; // [教練 Agent 2026-09-08] /companion/control 路由
import 'screens/companion_create_screen.dart';
import 'screens/companion_soul_screen.dart';
import 'screens/companion_appearance_screen.dart';
import 'screens/companion_settings/voice_settings_screen.dart'; // [教練 Agent 2026-08-03] 夥伴語音設定
import 'screens/achievement_collection_screen.dart';
import 'screens/semi_dao_review_coming_soon_screen.dart';
import 'screens/brain_container_screen.dart';
import 'widgets/bridge_shortcuts.dart';
import 'services/brain_container/brain_container_service.dart';
import 'services/compass/compass_bootstrap.dart'; // [羅盤 2026-09-06]
import 'package:bridge_app/services/compass/compass_speaker.dart';
import 'services/compass/compass_galaxy_bridge.dart';
import 'services/compass/compass_heartbeat.dart';
import 'services/life_tree/dream_scheduler.dart';
import 'services/compass/compass_models.dart' show CompassHealth, OrganHealthEvidence;
import 'services/compass/compass_store.dart';
import 'services/brain_container/brain_database.dart'; // [教練 Agent 2026-07-22] Phase 1 ③ DB 路徑
import 'services/brain_container/embedding/embedding_model_manager.dart';
import 'services/onboarding/onboarding_flow.dart'; // [教練 Agent 2026-07-22] Phase 1 ③ 安裝精靈
import 'services/vault/vault_service.dart'; // [教練 Agent 2026-07-22] Phase 1 ② Vault 服務
import 'services/skills/skill_store.dart';
import 'services/slots/builtin_skills_intake.dart';
import 'services/slots/hermes_skills_migration.dart'; // [教練 Agent S20] Skills 系統
import 'services/skills/builtin_skills_loader.dart'; // [教練 Agent 2026-07-23] 內建 skills 載入
import 'services/vector_db/asset_sandbox.dart'; // [教練 Agent 2026-07-25] 向量資料庫
import 'services/vector_db/asset_index_service.dart'; // [教練 Agent 2026-07-25] 向量資料庫索引
import 'services/js_bridge.dart';
import 'services/companion_store.dart';
import 'services/companion_runtime_outlet.dart';
import 'services/storage_service.dart';
import '../theme/tier.dart';
import '../theme/bridge_design_system.dart';

/// 平台感知：桌面平台（macOS/Windows/Linux）用桌面入口
/// [教練 Agent 2026-08-10] 手機版正式宣告刪除——所有平台一律走桌面流程
bool get _isDesktopPlatform {
  return true;
}

/// [D002 2026-08-10] 全域 Overlay——D002 安全確認框用
OverlayState? d002Overlay;

/// [D002 2026-08-10] D002 安全確認框——用全域 Overlay 顯示，繞過 GoRouter navigator 結構
/// 回傳 true=確認執行, false=取消
///
/// [小葵 2026-10-03] 拒絕冷卻——使用者拒絕同一工具後 15 分鐘內不再跳框（自動拒絕）。
/// 起源：restart_app 確認框一天跳多次的困擾案——Agent 每次被喚醒都重新提出，
/// 使用者的「拒絕」沒有被記住 = 對「不要」的不尊重。冷卻期內直接自動拒絕，
/// Agent 收到失敗訊息可改走別的路；使用者想主動執行時隨時可自己操作。
final Map<String, DateTime> _d002LastRejectedAt = {};
const Duration _d002RejectionCooldown = Duration(minutes: 15);

Future<bool> showD002ConfirmationDialog({
  required String toolName,
  required Map<String, dynamic> args,
}) {
  // 拒絕冷卻檢查
  final lastRejected = _d002LastRejectedAt[toolName];
  if (lastRejected != null &&
      DateTime.now().difference(lastRejected) < _d002RejectionCooldown) {
    debugPrint('[D002] $toolName 冷卻期內（使用者已拒絕過），自動拒絕不跳框');
    return Future.value(false);
  }
  if (d002Overlay == null) {
    debugPrint('[D002] Overlay 未捕獲，無法顯示確認框');
    return Future.value(true);
  }

  final completer = Completer<bool>();

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      final colors = BridgeDSColors.of(context);
      return Material(
        color: Colors.transparent,
        child: Container(
          color: colors.canvas.withOpacity(0.7),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(BridgeDS.roundWide),
                border: Border.all(color: colors.borderDefault),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: colors.accentBlue, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        '確認執行',
                        style: TierStyle.of(context, Tier.dialogTitle).toTextStyle(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '工具：$toolName',
                    style: TierStyle.of(context, Tier.dialogBody).toTextStyle(),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
                    ),
                    child: SelectableText(
                      args.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  if (AgentSafetyConstraints.isToolDestructive(toolName, args)) ...[
                    const SizedBox(height: 12),
                    Text(
                      '此操作不可逆，請確認。',
                      style: TextStyle(color: colors.textMuted, fontSize: 14),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          _d002LastRejectedAt[toolName] = DateTime.now(); // [小葵 2026-10-03] 記住拒絕——15 分鐘冷卻
                          entry.remove();
                          completer.complete(false);
                        },
                        child: Text('取消', style: TextStyle(color: colors.textSecondary)),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () {
                          entry.remove();
                          completer.complete(true);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.accentBlue.withOpacity(0.15),
                          foregroundColor: colors.textPrimary,
                        ),
                        child: const Text('確認執行'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  d002Overlay!.insert(entry);
  debugPrint('[D002] 彈出確認框 (Overlay)：$toolName');
  return completer.future;
}

// [Phase 0 2026-07-17] 桌面版初始路徑改為偵測流程
final _router = GoRouter(
  initialLocation: '/desktop-welcome', // [2026-08-10] 手機版刪除，一律桌面入口
  redirect: (context, state) async {
    // 桌面平台：偵測流程（Key → Companion → Desktop）
    final path = state.uri.path;
    if (path == '/bridge-desktop' ||
        path == '/desktop-welcome' ||
        path == '/desktop-summon') {
      if (path == '/desktop-welcome') {
        await CompanionStore().init();
        if (CompanionStore().all.isNotEmpty) return '/bridge-desktop';
        return null;
      }
      if (path == '/desktop-summon') return null;
      await CompanionStore().init();
      if (CompanionStore().all.isEmpty && path == '/bridge-desktop') {
        final token = await StorageService.getToken();
        if (token == null || token.trim().isEmpty) return '/desktop-welcome';
        return '/desktop-summon';
      }
      return null;
    }
    // [2026-08-10] 手機版已刪除，舊路徑一律導向桌面流程
    if (path == '/first-summon' || path == '/summon' || path == '/bridge-pairing') {
      return '/desktop-welcome';
    }
    return null;
  },
  // [教練 Agent 2026-09-08] 死路由優雅降級——任何未註冊路徑回 App 內頁，
  // 不再出現原始 GoException 全畫面（夥伴語音設定當機事件的第三道防線）。
  errorPageBuilder: (context, state) {
    debugPrint('[Router] 未註冊路徑: ${state.uri} — 導回桌面首頁');
    return NoTransitionPage(
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.explore_off, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text('找不到頁面：${state.uri.path}'),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => context.go('/bridge-desktop'),
                child: const Text('回到首頁'),
              ),
            ],
          ),
        ),
      ),
    );
  },
  routes: [
    GoRoute(path: '/lock', builder: (context, state) => const LockScreen()),
    GoRoute(
      path: '/desktop-welcome',
      builder: (context, state) => const DesktopWelcomeScreen(),
    ),
    GoRoute(
      path: '/desktop-summon',
      builder: (context, state) => const DesktopSummonScreen(),
    ),
    // [2026-10-06 封存] '/desktop-homepage' 路由已移除——孤兒頁面（全 App
    // 零導航入口，Blue 拍板封存），檔案在 lib/screens/_archived/。
    // [無限插槽 C2 2026-10-06 移植] /slots 插槽管理頁（首頁插槽卡入口）
    // ?prefill=<github url>：進頁自動開新增表單並預填（首頁「試一個範例」）
    GoRoute(
      path: '/slots',
      builder: (context, state) => SlotManagementScreen(
        prefillRepoUrl: state.uri.queryParameters['prefill'],
      ),
    ),
    GoRoute(
      path: '/bridge-desktop',
      builder: (context, state) => const BridgeDesktopScreen(),
    ),
    GoRoute(
      path: '/settings',
      redirect: (context, state) => '/',
    ),
    GoRoute(
      path: '/golden-keys',
      builder: (context, state) {
        // [教練 Agent 2026-08-01] 金鑰匙中心 → 能力中心（Phase 1 遷移）
        return CapabilityCenterScreen(
          returnTo: state.uri.queryParameters['returnTo'],
        );
      },
    ),
    GoRoute(
      path: '/capabilities',
      builder: (context, state) {
        return CapabilityCenterScreen(
          returnTo: state.uri.queryParameters['returnTo'],
        );
      },
    ),
    // [教練 Agent 2026-09-08] 夥伴控制中心 — soul/voice 頁返回 fallback 的正宮路由。
    // 之前不存在：voice/soul 頁按返回 → context.go('/companion/control') → GoException 白屏當機。
    GoRoute(
      path: '/companion/control',
      builder: (context, state) {
        final companionId = state.uri.queryParameters['id'] ?? '';
        return CompanionControlCenterScreen(companionId: companionId);
      },
    ),
    GoRoute(path: '/chat', builder: (context, state) => const ChatScreen()),
    GoRoute(
      path: '/companions',
      builder: (context, state) => const CompanionListScreen(),
    ),
    GoRoute(
      path: '/achievements',
      builder: (context, state) => const AchievementCollectionScreen(),
    ),
    GoRoute(
      path: '/companion/create',
      builder: (context, state) {
        final companionId = state.uri.queryParameters['id'];
        final returnTo =
            state.uri.queryParameters['returnTo']; // [以利沙 P1 修復十五輪 2026-06-27]
        return CompanionCreateScreen(
          editingCompanionId: companionId,
          returnTo: returnTo,
        );
      },
    ),
    // [教練 Agent 2026-08-05] 社群評審系統 placeholder — 避免使用者掉進舊版無法返回的頁面
    // 這個 widget 是 placeholder，未來社群評審實作完成時直接替換即可
    GoRoute(
      path: '/semi-dao/review',
      builder: (context, state) => const SemiDaoReviewComingSoonScreen(),
    ),
    GoRoute(
      path: '/brain-container',
      builder: (context, state) => const BrainContainerScreen(),
    ),
    GoRoute(
      path: '/companion/soul',
      builder: (context, state) {
        final companionId = state.uri.queryParameters['id'] ?? '';
        return CompanionSoulScreen(companionId: companionId);
      },
    ),
    GoRoute(
      path: '/companion/appearance',
      builder: (context, state) {
        final companionId = state.uri.queryParameters['id'] ?? '';
        return CompanionAppearanceScreen(companionId: companionId);
      },
    ),
    // [教練 Agent 2026-08-03] 夥伴語音設定
    GoRoute(
      path: '/companion/voice',
      builder: (context, state) {
        final companionId = state.uri.queryParameters['id'] ?? '';
        return VoiceSettingsScreen(companionId: companionId);
      },
    ),
  ],
);

GoRouter get appRouter => _router;

class BridgeApp extends StatefulWidget {
  const BridgeApp({super.key});

  @override
  State<BridgeApp> createState() => _BridgeAppState();
}

/// [T12-③ 2026-10-17] 羅盤前景沖出——resumed 時 flushQueue。
/// 主動訊息等的就是使用者回來看：開機 45 秒唯一窗口的病根修復
/// （Fable V3：羅盤有嘴但只在開機 45 秒開一次——App 持續運行期間
/// 入列的紅旗永遠沖不到使用者）。
class _CompassFlushObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      CompassSpeaker.instance.flushQueue(); // 1h 限頻在 speaker 內
    }
  }
}

class _BridgeAppState extends State<BridgeApp> with WindowListener {
  // [隊友訊息流 C7 2026-09-08] Tray 退出確認需要 root context
  final TrayService _tray = TrayService();
  // [T12-③] 羅盤前景沖出 observer（resumed → flushQueue）
  final _compassFlushObserver = _CompassFlushObserver();
  // [教練 Agent 2026-07-24] P5: Daemon WebSocket client (singleton)
  final DaemonClient _daemonClient = DaemonClient();
  StreamSubscription? _daemonEventSub;
  StreamSubscription? _daemonStateSub;
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  // [教練 Agent 2026-08-04] Phase E+：主題包 ThemeProvider (singleton)
  ThemeProvider get _themeProvider => ThemeProvider.instance;
  // [教練 Agent 2026-08-05] Step 3c — TierTheme future（cache 避免每次 rebuild 重 load）
  Future<TierTheme>? _tierThemeFuture;
  @override
  void initState() {
    super.initState();
    // [教練 Agent 2026-07-24] P4: 攔截視窗關閉 = 隱藏（不是退出）
    windowManager.addListener(this);
    // [教練 Agent 2026-08-02] MCP server 在 App 根層啟動，確保任何畫面都能被 Agent 控制
    BridgeMcpServer.instance.start();
    // [教練 Agent 2026-07-24] P5: 啟動 daemon WebSocket client
    _daemonClient.start();
    _daemonEventSub = _daemonClient.eventStream.listen((event) {
      debugPrint('[App] 排程觸發通知: ${event.title} (canvas: ${event.canvasId})');
      // 顯示 SnackBar 通知
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.alarm, color: BridgeDS.textOnAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '排程觸發：${event.title}',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: '查看',
            onPressed: () {
              // [教練 Agent 2026-08-03] R4: 死按鈕救援 — 跳到對應畫布，找不到則導向桌面
              if (event.canvasId != null) {
                // 試試用 GoRouter 跳到對應畫布
                _router.go('/canvas/${event.canvasId}');
              } else {
                // 沒 canvasId 就至少回桌面
                _router.go('/desktop');
              }
            },
          ),
        ),
      );
    });
    // 觸發 stateStream 更新（讓設定頁 UI 即時刷新）
    _daemonStateSub = _daemonClient.stateStream.listen((_) {});
    CompanionStore().init();
    JsBridge.instance.init();
    CompanionRuntimeOutlet.instance.start();
    JsBridge.instance.appState.addListener(_handleNavigation);
    // [教練 Agent 2026-08-04] Phase E+ v1.1：ThemeProvider 啟動（取代舊 ThemeController）
    _themeProvider.init();
    // [教練 Agent 2026-08-04] Phase E+ v1.1：TypographyScaleProvider 啟動（讀回上次字體縮放）
    TypographyScaleProvider.instance.init();
    // [教練 Agent S21f 2026-07-09] 大腦容器初始化：先 bootstrap EmbeddingModelManager，
    // 再 initialize BrainContainerService。bootstrap 會檢查已安裝的模型並載入。
    _bootstrapBrainContainer();
    // [教練 Agent S20] Skills 系統初始化（非同步，不阻擋 UI）
    _initializeSkills();
    // [教練 Agent 2026-07-25] 向量資料庫 — 載入持久化的資料夾清單 + manifest
    AssetSandbox().loadFromPrefs().then((_) {
      AssetIndexService().loadManifests();
    });
  }

  /// 啟動大腦容器：先載入 embedding model（若已安裝），再初始化服務。
  ///
  /// [教練 Agent 2026-07-22] Phase 1 ③
  /// 如果尚未完成安裝精靈，先設定預設 DB 路徑（系統碟 Application Support），
  /// 再初始化。安裝精靈 UI 會在桌面畫面中顯示（首次啟動時）。
  Future<void> _bootstrapBrainContainer() async {
    try {
      // [教練 Agent 2026-07-22] 安裝精靈：檢查是否已完成
      final onboardingDone = await OnboardingManager.isCompleted();
      if (!onboardingDone) {
        // 未完成 → 使用預設路徑（系統碟 Application Support）
        // 安裝精靈 UI 之後可以讓使用者改
        final customDir = await BrainDatabase.getCustomDbDirectory();
        if (customDir == null || customDir.isEmpty) {
          await BrainDatabase.setCustomDbDirectory(
            OnboardingManager.defaultDbPath,
          );
          debugPrint('[App] 首次啟動 — DB 路徑設為 ${OnboardingManager.defaultDbPath}');
        }
      }

      final hfToken = await StorageService.getHuggingFaceToken();
      await EmbeddingModelManager.instance.bootstrap(huggingFaceToken: hfToken);
    } catch (e) {
      debugPrint('[App] EmbeddingModelManager bootstrap failed: $e');
    }
    // 無論 bootstrap 結果如何，都初始化 BrainContainerService（fallback 模式仍可運作）
    BrainContainerService.instance.initialize();

    // [羅盤 2026-09-06] 羅盤系統啟動——store + 種子 + 規則快取
    //（fail-open：羅盤掛了不擋 App，渲染端有 fallback 種子值）
    unawaited(CompassBootstrap.instance.ensureInitialized());

    // [T9③ 2026-10-17] 羅盤開口 M4——夢裡排隊的話，開 App 後沖出
    // （走既有注入通道 injectAssistantMessage + kind:compass，不另建
    // 聊天路徑；開口閘全在 CompassSpeaker——信心/額度/證據）
    // [T12-③ 2026-10-17] 前景沖出——開機 45 秒不是唯一窗口：
    // WidgetsBindingObserver resumed 時也沖（主動訊息等的就是使用者
    // 回來看；App 持續運行期間入列的訊息原本永遠沖不到）。
    WidgetsBinding.instance.addObserver(_compassFlushObserver);
    Timer(const Duration(seconds: 45), () {
      if (!mounted) return;
      CompassSpeaker.instance.onSpeak = (content, metadata) async {
        // [Blue 令 2026-10-17] 主動回應走獨立頻道——不跑進既有對話討論串。
        // 做法：當前 controller 切到 proactive 類型的 session（沒有就建），
        // 注入後不自動切回——使用者自己決定何時看。
        final controller = BridgeDesktopScreen.activeChatController.value;
        if (controller == null) return;
        await controller.openOrCreateProactiveSession();
        await controller.injectAssistantMessage(content, metadata: metadata);
      };
      unawaited(CompassSpeaker.instance.flushQueue());
    });

    // [羅盤 2026-09-06] 心跳層 + galaxy 規則匯出（背景跑）
    Timer(const Duration(seconds: 60), () {
      if (!mounted) return;
      final hb = CompassHeartbeat(CompassStore.instance);
      registerDefaultProbes(hb);
      hb.start(interval: const Duration(seconds: 60));
      CompassGalaxyBridge(CompassStore.instance).start();
      // [小葵 2026-09-22 Blue 規格] 夢境自動排程——冷門時段做夢，
      // 節律由 DreamRhythm 決定（呼吸感：深夢有事才做、平靜夜安睡、
      // 連續平靜+有美好可記 → 詩夢）
      hb.register(_DreamTickerProbe());
    });

    // [教練 Agent 2026-07-22] Phase 1 ② 初始化 VaultService
    // 等 BrainContainer 初始化完成後標記
    _initVaultService();
  }

  /// 初始化 VaultService（等 BrainContainer 就緒後標記）
  Future<void> _initVaultService() async {
    for (var i = 0; i < 60; i++) {
      if (BrainContainerService.instance.isInitialized) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (BrainContainerService.instance.isInitialized) {
      VaultService.instance.markInitialized();
      debugPrint('[VaultService] 初始化完成');

      // [小葵 2026-10-20 Blue 抓包·滾動卡頓] 啟動掃描延後——原本 BrainContainer
      // 一就緒就 fullScan＋嵌入（51s 掃描＋6182 檔嵌入直接壓在剛啟動的 UI 上，
      // 滾對話就轉圈圈）。延後 45 秒讓 UI 先暖；期間的新檔案由 watcher＋
      // 兜底 fullScan 追上（fullScan 會對帳整棵樹，不會漏）。
      Future.delayed(const Duration(seconds: 45), () async {
        // [教練 Agent P0.6c 2026-08-07] 把 bridge_media/ 加入向量 DB 受管範圍，
        // 讓生成的圖片/文件/音訊自動被偵測和嵌入。
        await _registerBridgeMediaInSandbox();

        // [教練 Agent 2026-07-28] App 啟動時自動觸發嵌入
        // 偵測到有檔案但沒 embedding 的就自動跑
        _autoGenerateEmbeddings();
      });
    } else {
      debugPrint('[VaultService] BrainContainer 未初始化，Vault 服務暫停');
    }
  }

  /// App 啟動後自動觸發嵌入（如果有檔案需要嵌入）
  ///
  /// [教練 Agent 2026-07-31] 改用 initOnAppStart — 統一嵌入 + 斷點續傳
  ///
  Future<void> _autoGenerateEmbeddings() async {
    try {
      final indexService = AssetIndexService();
      await indexService.initOnAppStart();
    } catch (e) {
      debugPrint('[App] 自動嵌入檢查失敗: $e');
    }
  }

  /// [教練 Agent P0.6c 2026-08-07] 把 bridge_media/ 加入向量 DB 受管範圍。
  ///
  /// 生成的圖片/文件/音訊存在 ~/Documents/bridge_media/，
  /// 把這個根目錄登記進 AssetSandbox，AssetIndexService 就會自動偵測和嵌入。
  /// 同時觸發一次增量掃描，把現有但尚未索引的檔案補上。
  Future<void> _registerBridgeMediaInSandbox() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final mediaRoot = '${docs.path}/bridge_media';
      final sandbox = AssetSandbox();
      if (!sandbox.rootPaths.contains(mediaRoot)) {
        sandbox.addFolder(mediaRoot);
        debugPrint('[App] bridge_media/ 已加入向量 DB 受管範圍: $mediaRoot');
      }
      // 增量掃描，把剛加入的檔案補進索引
      // [小葵 2026-10-20 Blue 抓包·滾動卡頓] 帶指紋短路——指紋一致時整輪
      // 跳過（原本每次啟動都白掃 51 秒 887 檔）。有真實變更仍走全掃。
      final indexService = AssetIndexService();
      await indexService.fullScan(mediaRoot, skipIfUnchanged: true);
      debugPrint('[App] bridge_media/ 增量掃描完成');
    } catch (e) {
      debugPrint('[App] bridge_media/ 向量 DB 註冊失敗: $e');
    }
  }

  @override
  void dispose() {
    _daemonEventSub?.cancel();
    _daemonStateSub?.cancel();
    // 不 dispose singleton DaemonClient（其他頁面也在用）
    WidgetsBinding.instance.removeObserver(_compassFlushObserver); // [T12-③]
    windowManager.removeListener(this);
    JsBridge.instance.appState.removeListener(_handleNavigation);
    CompanionRuntimeOutlet.instance.stop();
    super.dispose();
  }

  // [教練 Agent 2026-07-24] P4: 攔截視窗關閉 → 隱藏而非退出
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  /// [教練 Agent S20] Skills 系統初始化
  /// 從 app Documents Directory /skills/ 載入 skill 檔案
  /// [教練 Agent 2026-07-23] 先載入內建 skills，再讓 SkillStore 初始化
  Future<void> _initializeSkills() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final skillsDir = '${docsDir.path}/skills';

      // [教練 Agent 2026-07-23] 載入/更新內建 skills
      final loaded = await BuiltinSkillsLoader.loadTo(skillsDir);
      if (loaded > 0) {
        debugPrint('[Skills] 載入了 $loaded 個內建 skill');
      }

      await SkillStore.instance.initialize(skillsDir: skillsDir);

      // [Blue 提議 2026-10-06] 內建 skills 收編進插槽管理——初始安裝
      // 就看得到裝了什麼、不要可單獨卸載（冪等；卸載過不還魂）。
      await BuiltinSkillsIntake.instance.runIfNeeded();

      // [Blue 抓包 2026-10-06] 大搬家補線——Hermes skills（207 個）從未
      // 接上。搬進 Documents/skills/hermes/ ＋收編插槽（冪等）。
      try {
        final (found, migrated) = await HermesSkillsMigration.instance
            .migrate(appSkillsDir: skillsDir);
        if (migrated > 0) {
          debugPrint('[HermesSkillsMigration] 搬入 $migrated/$found 個 skills');
        }
      } catch (e) {
        debugPrint('[HermesSkillsMigration] 失敗（下次啟動再試）: $e');
      }
    } catch (e) {
      // Skills 載入失敗不影響 app 運行
      debugPrint('Skills init failed: $e');
    }
  }

  void _handleNavigation() {
    final state = JsBridge.instance.appState.value;
    final route = state['navigateTo'] as String?;
    if (route != null && mounted) {
      _router.go(route);
      JsBridge.instance.clearNavigateCommand();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // [教練 Agent 2026-08-04] Phase E+ v1.1：ThemeProvider + TypographyScaleProvider 監聽
      listenable: _themeProvider,
      builder: (context, _) {
        return ListenableBuilder(
          listenable: TypographyScaleProvider.instance,
          builder: (context, _) {
            final scale = TypographyScaleProvider.instance.scale;
            // [教練 Agent 2026-08-05] Step 3c — 載入 tier manifest 接到 MaterialApp.extensions
            return FutureBuilder<TierTheme>(
              future: _tierThemeFuture ??= loadDefaultTierTheme(),
              builder: (context, snapshot) {
                final tierTheme = snapshot.data;
                // Tier manifest 尚未就緒時，不能先建立功能頁面：
                // 任何 TierStyle.of() 都會因 ThemeExtension 尚未註冊而 red screen。
                // 等它完成，再建立 router，讓所有功能頁都看到同一份 TierTheme。
                if (tierTheme == null) {
                  return MaterialApp(
                    title: '橋樑計畫',
                    debugShowCheckedModeBanner: false,
                    theme: ThemeData.dark(),
                    home: const Scaffold(
                      body: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('正在載入 Bridge 設計系統…'),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                final themeData = BridgeDS.themeFrom(
                  _themeProvider.colors,
                  textScale: scale,
                  tierTheme: tierTheme,
                );

                return ValueListenableBuilder<ChatController?>(
                  valueListenable: BridgeDesktopScreen.activeChatController,
                  builder: (context, chatController, _) {
                    return BridgeShortcuts(
                      chatController: chatController,
                      // [教練 Agent 2026-08-22 全域視網膜] 整個 App 的畫面
                      // 都在這個 RepaintBoundary 裡——無論使用者停在哪頁。
                      // AppRetina.capture() 直讀（render layer → PNG）。
                      child: RepaintBoundary(
                        key: AppRetina.rootKey,
                        child: MaterialApp.router(
                        title: '橋樑計畫',
                        debugShowCheckedModeBanner: false,
                        scaffoldMessengerKey: _scaffoldMessengerKey,
                        // [隊友訊息流 C7 2026-09-08] root context 注入給
                        // TrayService 退出確認框（全域 Overlay，不依賴頁面）
                        builder: (context, child) {
                          _tray.setRootContext(context);
                          return child ?? const SizedBox.shrink();
                        },
                        locale: const Locale('zh', 'TW'),
                        supportedLocales: const [
                          Locale('zh', 'TW'),
                          Locale('zh', 'CN'),
                          Locale('en', 'US'),
                        ],
                        localizationsDelegates: const [
                          GlobalMaterialLocalizations.delegate,
                          GlobalWidgetsLocalizations.delegate,
                          GlobalCupertinoLocalizations.delegate,
                        ],
                        theme: themeData,
                        routerConfig: _router,
                      ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// [小葵 2026-09-22] 夢境心跳探針——把 DreamScheduler 掛進 CompassHeartbeat
/// （每分鐘 tick；排程器內部判斷冷門時段+節律，其餘時間靜默）
class _DreamTickerProbe implements OrganHealthProbe {
  @override
  final organId = 'life_tree.dream';

  @override
  Future<OrganHealthEvidence> probe() async {
    await DreamScheduler.instance.tick();
    return OrganHealthEvidence(
      status: CompassHealth.green,
      summary: '夢境節律運行中',
      checkedAt: DateTime.now(),
    );
  }
}
