import 'dart:async' show unawaited;
import 'dart:io' show Platform, File, FileMode;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'quick_assistant_window.dart' as qa_window; // [無限插槽 C1 2026-10-06 移植]
import 'services/local_model_scheduler.dart'; // [小葵 2026-10-01] 離合器
import 'services/agent_loop/app_log_buffer.dart';
import 'services/sovereignty/trace_scrubber.dart';
import 'services/computer_use/cu_e2e_test.dart';
import 'services/system/tray_service.dart';
import 'services/api_usage_tracker.dart'; // [小葵 2026-09-21 收尾驗收] token 歷史載入
import 'services/brain_revival_service.dart'; // [小葵 2026-10-05 自檢後門] 本地模型開關
import 'services/local_model_runtime_service.dart'; // [小葵 2026-10-05 自檢後門]
import 'services/storage_service.dart'; // [小葵 2026-10-05 自檢後門] 閒置卸載偏好持久化
import 'services/trust/trust_loop.dart'; // [刀 6 K6.4]
import 'services/quick_assistant/floating_window_service.dart'; // [無限插槽 C1]

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // [無限插槽 C1 2026-10-06 移植] 子視窗 engine 進入點——desktop_multi_window
  // 以 dartEntrypointArguments ["multi_window", windowId, arguments] 啟動子引擎，
  // args[2]=='quick_assistant' 時執行流轉交懸浮窗 UI（絕不初始化主 App）。
  if (qa_window.isQuickAssistantWindowLaunch(args)) {
    await qa_window.main(args);
    return;
  }

  // [小葵 2026-10-05 自檢後門] BRIDGE_SELFTEST=poweroff|poweron：
  // 整合測試本地模型開關鏈（UI 按鈕與此同一條鏈）。10 秒後自動執行，
  // 觀察 stdout log 與 llama-server 進程生死即可驗證。
  final selftest = Platform.environment['BRIDGE_SELFTEST'];
  if (selftest == 'idleoff' || selftest == 'idleon') {
    // [Blue 令 2026-10-05] 閒置卸載開關自檢：切換 → 驗證持久化（新 Service 實例讀回）
    debugPrint('[SelfTest] 🧪 BRIDGE_SELFTEST=$selftest 將於 8 秒後執行');
    Future.delayed(const Duration(seconds: 8), () async {
      final svc = BrainRevivalService.instance;
      await svc.setIdleUnloadEnabled(selftest == 'idleon');
      debugPrint('[SelfTest] 🧪 idleUnloadEnabled=${svc.idleUnloadEnabled}');
      // 用 StorageService 直接讀回驗證持久化
      final persisted = await StorageService.getLocalModelIdleUnloadEnabled();
      debugPrint('[SelfTest] 🧪 持久化讀回=$persisted（應=${selftest == 'idleon'}）');
      debugPrint('[SelfTest] 🧪 完成');
    });
  }
  if (selftest == 'poweroff' || selftest == 'poweron') {
    debugPrint('[SelfTest] 🧪 BRIDGE_SELFTEST=$selftest 將於 10 秒後執行');
    Future.delayed(const Duration(seconds: 10), () async {
      final svc = BrainRevivalService.instance;
      debugPrint('[SelfTest] 🧪 userEnabled=${svc.userEnabled} → 執行 $selftest');
      if (selftest == 'poweroff') {
        await svc.powerOff(LocalModelRuntimeService());
      } else {
        await svc.powerOn(LocalModelRuntimeService());
      }
      debugPrint('[SelfTest] 🧪 完成：userEnabled=${svc.userEnabled}');
    });
  }

  // [小葵 2026-09-06 Computer Use P1a] --cu-e2e：App 內真實環境 E2E 測試
  // （鐵則「終端測通≠App內通」——flutter test 是 fake channel 環境測不到）
  if (Platform.environment.containsKey('BRIDGE_CU_E2E') ||
      (Platform.environment['ARGS'] ?? '').contains('--cu-e2e')) {
    await runComputerUseE2E();
    return;
  }

  // [教練 Agent 2026-08-22] profile 模式灰屏驗屍器——build 例外在 profile 下
  // 不顯示紅屏（ErrorWidget 變灰），把完整堆疊寫 /tmp/bridge_ui_crash.log
  // 才能對症下藥（使用者 抓包：點農場日記IG合集節點→整頁灰）。
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    try {
            final f = File('/tmp/bridge_ui_crash.log');
            f.writeAsStringSync(
              '[${DateTime.now()}] ${details.exception}\n${details.stack}\n${'=' * 60}\n',
              mode: FileMode.append,
            );
    } catch (_) {}
  };

  // [Phase 1 2026-07-17] 安裝 App Log Ring Buffer
  appLogBuffer.install();

  // [小葵 2026-09-21 收尾驗收] API token 歷史載入（jsonl 持久化，
  // 7 天內）——儀表板重啟不洗牌
  try {
    await ApiUsageTracker.instance.loadPersisted();
  } catch (_) {}

  // [教練 Agent 2026-07-24] P4: 初始化視窗管理 + 系統列圖示
  // [教練 Agent 2026-07-30] iOS/Web 跳過 window_manager（無實作）
  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1440, 900),
      // [教練 Agent 2026-08-14] 最小寬度 1280，防止頂部按鈕被擠壓產生黃黑警示條
      minimumSize: Size(1280, 720),
      titleBarStyle: TitleBarStyle.normal,
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    // 啟動系統列圖示（桌面限定）
    await TrayService().init();
    // [刀 6 K6.4] 信任 loop 引擎上線——做事→回報→檢討→升級（事件流供
    // 跑馬燈/TrustMeterCard/托盤摘要三個介面消費）
    TrustLoop.instance.wire();

    // [資料主權 P1 2026-09-14] 自動除痕上線——預設啟用（Blue 拍板）、
    // 每天一次、閒置時執行、2hr 年齡門檻；只清外傳暫存不碰任何資產。
    unawaited(TraceScrubber.instance.start());

    // [無限插槽 C1 2026-10-06 移植] 系統級懸浮窗服務 + 全域熱鍵 Cmd+Shift+K。
    // 失敗（無輔助功能權限等）只記 log——App 內 Cmd+K 與 overlay fallback 不受影響。
    try {
      await FloatingWindowService.instance.init();
      // HotKey 建構子非 const（identifier 預設取 uuid），故用 final。
      final hotKey = HotKey(
        identifier: 'bridge_quick_assistant_toggle',
        key: LogicalKeyboardKey.keyK,
        modifiers: [HotKeyModifier.meta, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      );
      await HotKeyManager.instance.register(
        hotKey,
        keyDownHandler: (_) => unawaited(FloatingWindowService.instance.toggle()),
      );
      // App 結束時解除全域熱鍵——掛在 WidgetsBinding 的 lifecycle 觀察
      WidgetsBinding.instance.addObserver(_HotKeyCleanupObserver(hotKey));
    } catch (e) {
      debugPrint('[QuickAssistant] 全域熱鍵/懸浮窗初始化失敗（fallback overlay）: $e');
    }
  }

  // [T7④ 根修 2026-10-16] localOnly 預熱——冷啟動第一輪 race 窗口關閉。
  // 盲測實證：首輪 SharedPreferences 未載入完成 → getLocalOnly=false →
  // 打雲 401。runApp 前同步讀一次，static 快取從第一輪就正確。
  try {
    await StorageService.getLocalOnly();
  } catch (_) {}
  runApp(const BridgeApp());
  // [小葵 2026-10-01 離合器] App 啟動掛 Scheduler——
  // 載入角色設定＋定時評估（閒置+有待辨識 → 自動切辨識模式）
  LocalModelScheduler.instance.start();
}

/// [無限插槽 C1 2026-10-06 移植] App 退出時解除全域熱鍵。
///
/// lifecycle == detached 在 macOS 視窗關閉／Cmd+Q 前不一定每次都觸發，
/// 但這是純 Flutter 層能做到的最後時機；hotkey 系統攔截在進程死亡時
/// 也會被 OS 回收，此處是「優雅解除」的保險。
class _HotKeyCleanupObserver extends WidgetsBindingObserver {
  _HotKeyCleanupObserver(this._hotKey);
  final HotKey _hotKey;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      HotKeyManager.instance.unregister(_hotKey);
    }
  }
}
