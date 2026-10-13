// tray_service.dart
// P4: macOS 系統列圖示服務
//
// 功能:
// - 右上角 menu bar 小圖示（⏰）
// - 左鍵點擊 → 顯示/隱藏 App 視窗
// - 右鍵選單 → 顯示視窗 / 隱藏視窗 / 設定開機啟動 / 退出
// - 關視窗 = 隱藏（不是退出 App）

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/dev_paths.dart';
import 'package:bridge_app/services/tasks/task_dispatcher.dart'; // [隊友訊息流 C7]
import 'package:bridge_app/widgets/trust/trust_meter_card.dart'; // [刀 6 K6.3]
import 'package:bridge_app/widgets/routines/system_routine_overlay.dart'; // [刀 5 延伸 SR.3]

class TrayService with TrayListener {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  /// [Blue 拍板 2026-09-12] 訓練頁導航 callback——由 BridgeDesktopScreen 掛上
  /// （避免 service→screen 反向依賴；同 navigateToCompass 模式）
  static VoidCallback? onOpenTrainingPage;

  bool _initialized = false;
  bool _autoStartEnabled = false;

  /// 啟動系統列服務
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 確保 window_manager 已初始化
    await windowManager.ensureInitialized();

    // 設定關閉按鈕 = 隱藏視窗（攔截關閉事件）
    await windowManager.setPreventClose(true);

    // 建立 tray icon
    // tray_manager 需要圖示檔案路徑
    // 使用 macOS App icon 的 16x16 版本
    String iconPath;
    if (Platform.isMacOS) {
      // 嘗試使用打包在 App 內的圖示
      // tray_manager 在 macOS 上接受 NSImage 名稱或檔案路徑
      iconPath = 'assets/icons/tray_icon.png';
    } else {
      iconPath = 'assets/icons/tray_icon.png';
    }

    try {
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('橋樑 App — 排程運行中');

      // 設定選單
      final menu = Menu(
        items: [
          MenuItem(
            key: 'show_window',
            label: '顯示橋樑',
          ),
          MenuItem(
            key: 'hide_window',
            label: '隱藏橋樑',
          ),
          // [刀 6 K6.3] 今日信任指數——點開 TrustMeterCard（Overlay 常駐）
          MenuItem(
            key: 'trust_meter',
            label: '今日信任指數',
          ),
          // [刀 5 延伸 SR.3] 全電腦示範錄製入口
          MenuItem(
            key: 'system_routine_record',
            label: '⏺ 示範錄製（全電腦）',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'toggle_autostart',
            label: '開機自動啟動',
            disabled: false,
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'quit',
            label: '退出橋樑',
          ),
        ],
      );
      await trayManager.setContextMenu(menu);

      // 註冊 listener
      trayManager.addListener(this);

      debugPrint('[TrayService] 系統列圖示已初始化');
    } catch (e) {
      debugPrint('[TrayService] 初始化失敗: $e');
    }
  }

  /// 顯示 App 視窗
  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// 隱藏 App 視窗
  Future<void> hideWindow() async {
    await windowManager.hide();
  }

  /// 切換視窗顯示/隱藏
  Future<void> toggleWindow() async {
    final isVisible = await windowManager.isVisible();
    if (isVisible) {
      await hideWindow();
    } else {
      await showWindow();
    }
  }

  /// 退出 App
  ///
  /// [隊友訊息流 C7 2026-09-08] 有活躍任務時先確認（D002 哲學：
  /// 任務值得被問一句——「不中斷鐵則」的最後防線）。
  /// 確認框走全域 Overlay（不依賴特定頁面 context）。
  Future<void> quit() async {
    final active = TaskDispatcher.instance.activeSessions;
    if (active.isNotEmpty) {
      final taskNames = active.map((s) => '• ${s.title}').join('\n');
      final confirmed = await _confirmQuitWithActiveTasks(taskNames);
      if (!confirmed) return; // 取消退出——任務繼續跑（不中斷鐵則）
    }
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  /// 全域確認框——用 root navigator 的 overlay context
  Future<bool> _confirmQuitWithActiveTasks(String taskNames) async {
    final ctx = _rootContext;
    if (ctx == null) return true; // 拿不到 context（異常狀態）→ 不擋退出
    final result = await showDialog<bool>(
      context: ctx,
      builder: (context) => AlertDialog(
        title: const Text('還有任務在進行'),
        content: Text(
          '以下任務正在背景執行，退出會中斷它們：\n\n$taskNames\n\n確定要退出嗎？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('讓任務繼續'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('仍要退出'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// root navigator context——由 App 啟動時注入
  BuildContext? _rootContext;
  void setRootContext(BuildContext context) => _rootContext = context;

  /// 設定開機自動啟動
  ///
  /// macOS: 建立 ~/Library/LaunchAgents/farm.semiwasabi.bridgeApp.autostart.plist
  /// 使用 launchd 的 RunAtLoad 實現開機啟動
  Future<bool> setAutoStart(bool enabled) async {
    _autoStartEnabled = enabled;
    try {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final plistPath =
          '$home/Library/LaunchAgents/farm.semiwasabi.bridgeApp.autostart.plist';

      if (enabled) {
        // 取得 App 路徑
        final appPath = await _getAppPath();
        if (appPath == null) {
          debugPrint('[TrayService] 無法取得 App 路徑');
          return false;
        }

        final plistContent = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>farm.semiwasabi.bridgeApp.autostart</string>
    <key>ProgramArguments</key>
    <array>
        <string>open</string>
        <string>-a</string>
        <string>$appPath</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>''';

        final file = File(plistPath);
        await file.parent.create(recursive: true);
        await file.writeAsString(plistContent);

        // Bootstrap 到 launchd
        final result = await Process.run('launchctl', [
          'bootstrap',
          'gui/${_getUid()}',
          plistPath,
        ]);
        debugPrint('[TrayService] 開機啟動已啟用: ${result.exitCode == 0}');
        return result.exitCode == 0;
      } else {
        // 移除
        await Process.run('launchctl', [
          'bootout',
          'gui/${_getUid()}/farm.semiwasabi.bridgeApp.autostart',
        ]);
        final file = File(plistPath);
        if (await file.exists()) {
          await file.delete();
        }
        debugPrint('[TrayService] 開機啟動已停用');
        return true;
      }
    } catch (e) {
      debugPrint('[TrayService] 設定開機啟動失敗: $e');
      return false;
    }
  }

  bool get isAutoStartEnabled => _autoStartEnabled;

  /// 取得目前 App 的路徑
  Future<String?> _getAppPath() async {
    try {
      // .app bundle 路徑
      final result = await Process.run('ls', [
        '-d',
        '/Applications/bridge_app.app',
      ]);
      if (result.exitCode == 0) {
        return '/Applications/bridge_app.app';
      }
      // 開發中的路徑
      final devPath =
          resolveDevPath('~/Developer/bridge_app/build/macos/Build/Products/Debug/bridge_app.app');
      if (await File(devPath).exists()) {
        return devPath;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  int _getUid() {
    return Platform.environment['SUDO_UID'] != null
        ? int.parse(Platform.environment['SUDO_UID']!)
        : Platform.environment['UID'] != null
            ? int.parse(Platform.environment['UID']!)
            : 501; // 預設
  }

  // ── TrayListener ──

  @override
  void onTrayIconMouseDown() {
    // 左鍵點擊 → 切換視窗
    toggleWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右鍵點擊 → 顯示選單（tray_manager 自動處理）
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        showWindow();
        break;
      case 'hide_window':
        hideWindow();
        break;
      case 'trust_meter':
        // [刀 6 K6.3] 開信任儀表板（root overlay——不開新視窗）
        showWindow();
        if (_rootContext != null) TrustMeterOverlay.open(_rootContext!);
        break;
      case 'system_routine_record':
        // [Blue 拍板 2026-09-12] 唯一入口在首頁訓練頁——托盤收斂為導航
        showWindow();
        TrayService.onOpenTrainingPage?.call();
        break;
      case 'toggle_autostart':
        setAutoStart(!_autoStartEnabled);
        break;
      case 'quit':
        quit();
        break;
    }
  }

  /// 釋放資源
  Future<void> dispose() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
  }
}
