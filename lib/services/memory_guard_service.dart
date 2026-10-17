// MemoryGuardService — 記憶體監控 + 自動降級 + L1/L2 自管
// [教練 Agent 2026-07-21] 初版：四級降級
// [教練 Agent 2026-07-22] #4: L1 自管 + L2 彈窗
//
// 設計理念（使用者拍板）：
// 寧願緊急使用外部 LLM 救火，也不能讓主機系統崩潰。
// L1（黃燈）：自動暫停非必要服務，不需使用者互動
// L2（紅燈）：彈窗讓使用者選要關什麼（本地模型 / 背景程序）
//
// 機制：
// 1. Swift 端每 5 秒檢查全系統 RAM 使用率
// 2. 綠燈（<70%）→ 正常
// 3. 黃燈（70-85%）→ L1：暫停 embedding 寫入、brain reflection、smart memory extraction
// 4. 紅燈（85-95%）→ L2：彈窗列出系統程序 + 本地模型選項，使用者勾選關閉
// 5. 危險（>95%）→ 強制釋放（critical：自動殺 llama-server + 緊急雲端救火）
//
// App 啟動時自動啟動監控（bridge_desktop_screen.dart initState）

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'provider_router.dart';
import 'storage_service.dart';

enum MemoryGuardLevel { green, yellow, red, critical }

/// L2 彈窗要顯示的程序資訊
class MemoryProcessInfo {
  final int pid;
  final String name;
  final int ramMB;
  final double ramPercent;

  const MemoryProcessInfo({
    required this.pid,
    required this.name,
    required this.ramMB,
    required this.ramPercent,
  });

  factory MemoryProcessInfo.fromMap(Map<dynamic, dynamic> m) {
    return MemoryProcessInfo(
      pid: m['pid'] as int? ?? 0,
      name: m['name'] as String? ?? 'unknown',
      ramMB: m['ramMB'] as int? ?? 0,
      ramPercent: (m['ramPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// L1 暫停的服務標籤
enum PausedService { embedding, brainReflection, smartMemoryExtraction }

class MemoryGuardService {
  static const _channel = MethodChannel('bridge.desktop.shell.v1');

  static final MemoryGuardService instance = MemoryGuardService._();

  MemoryGuardService._();

  Timer? _pollTimer;
  MemoryGuardLevel _currentLevel = MemoryGuardLevel.green;
  int _usagePercent = 0;

  // L1: 被暫停的服務集合
  final Set<PausedService> _pausedServices = {};
  Set<PausedService> get pausedServices => Set.unmodifiable(_pausedServices);

  /// 當記憶體等級變化時觸發
  final _levelChangeController = StreamController<MemoryGuardLevel>.broadcast();
  Stream<MemoryGuardLevel> get levelChanges => _levelChangeController.stream;

  /// L2 彈窗事件——紅燈時觸發，UI 端 listen 後顯示對話框
  final _pressureDialogController = StreamController<void>.broadcast();
  Stream<void> get pressureDialogRequests => _pressureDialogController.stream;

  /// 當前等級
  MemoryGuardLevel get currentLevel => _currentLevel;
  int get usagePercent => _usagePercent;

  // ── L1 旗標 ──────────────────────────────────────────

  /// embedding 寫入是否被暫停
  bool get embeddingPaused => _pausedServices.contains(PausedService.embedding);

  /// brain reflection 是否被暫停
  bool get brainReflectionPaused =>
      _pausedServices.contains(PausedService.brainReflection);

  /// smart memory extraction 是否被暫停
  bool get smartMemoryExtractionPaused =>
      _pausedServices.contains(PausedService.smartMemoryExtraction);

  /// 任何非必要服務被暫停
  bool get anyServicePaused => _pausedServices.isNotEmpty;

  // ── 啟動 / 停止 ──────────────────────────────────────

  /// 啟動監控
  Future<void> start() async {
    try {
      await _channel.invokeMethod('startMemoryMonitor');
    } catch (e) {
      debugPrint('[MemoryGuard] start failed: $e');
    }

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    await _poll();
  }

  /// 停止監控
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      _channel.invokeMethod('stopMemoryMonitor');
    } catch (_) {}
  }

  /// 查詢當前狀態
  Future<void> _poll() async {
    try {
      final result = await _channel.invokeMethod<Map>('memoryGuardStatus');
      if (result == null) return;

      final levelStr = result['level'] as String? ?? 'green';
      final pct = result['usagePercent'] as int? ?? 0;
      final serverRunning = result['localServerRunning'] as bool? ?? false;

      final newLevel = _parseLevel(levelStr);
      _usagePercent = pct;

      if (newLevel != _currentLevel) {
        final old = _currentLevel;
        _currentLevel = newLevel;
        debugPrint(
            '[MemoryGuard] $old → $newLevel ($pct% RAM, server=$serverRunning)');

        _levelChangeController.add(newLevel);

        // L1: 黃燈 → 暫停非必要服務
        if (newLevel == MemoryGuardLevel.yellow) {
          _applyL1Throttle();
        }
        // 綠燈恢復 → 解除暫停
        else if (newLevel == MemoryGuardLevel.green) {
          _clearL1Throttle();
        }

        // L2: 紅燈 → 請求 UI 彈窗
        if (newLevel == MemoryGuardLevel.red) {
          _pressureDialogController.add(null);
        }

        // Critical: 保留自動殺（系統快崩了，不能等使用者）
        if (newLevel == MemoryGuardLevel.critical) {
          await _emergencyFailover();
        }
      }
    } catch (e) {
      // channel 未接通時靜默
    }
  }

  // ── L1: 黃燈暫停 / 綠燈恢復 ──────────────────────────

  void _applyL1Throttle() {
    if (_pausedServices.isNotEmpty) return; // 已在暫停中
    _pausedServices.addAll(PausedService.values);
    debugPrint('[MemoryGuard] L1 暫停: ${_pausedServices.map((e) => e.name)}');
  }

  void _clearL1Throttle() {
    if (_pausedServices.isEmpty) return;
    debugPrint('[MemoryGuard] L1 恢復: 解除所有暫停');
    _pausedServices.clear();
  }

  // ── L2: 程序列表 + 殺程序 ────────────────────────────

  /// 取得系統記憶體佔用最高的前 15 個程序
  Future<List<MemoryProcessInfo>> listTopMemoryProcesses() async {
    try {
      final result =
          await _channel.invokeMethod<Map>('listTopMemoryProcesses');
      if (result == null) return [];
      final list = result['processes'] as List? ?? [];
      return list
          .map((e) => MemoryProcessInfo.fromMap(e as Map<dynamic, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[MemoryGuard] listTopMemoryProcesses failed: $e');
      return [];
    }
  }

  /// 殺掉指定 PID 的程序
  Future<bool> killProcess(int pid) async {
    try {
      final ok = await _channel.invokeMethod<bool>('killProcess', pid);
      debugPrint('[MemoryGuard] L2: 殺掉 PID=$pid result=$ok');
      return ok ?? false;
    } catch (e) {
      debugPrint('[MemoryGuard] killProcess failed: $e');
      return false;
    }
  }

  /// 關閉本地模型 server（llama-server）
  Future<void> killLocalModelServer() async {
    try {
      await _channel.invokeMethod('killLocalModel');
      debugPrint('[MemoryGuard] L2: 本地模型已關閉');
    } catch (e) {
      debugPrint('[MemoryGuard] killLocalModel failed: $e');
    }
  }

  /// 本地模型是否正在運行（從 Swift 端查詢）
  Future<bool> isLocalServerRunning() async {
    try {
      final result = await _channel.invokeMethod<Map>('memoryGuardStatus');
      return result?['localServerRunning'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Critical: 緊急降級 ──────────────────────────────

  /// 緊急降級——切到雲端 provider + 殺本地模型
  Future<void> _emergencyFailover() async {
    debugPrint('[MemoryGuard] Critical: 緊急降級');

    // 殺本地模型（critical 不等使用者）
    try {
      await _channel.invokeMethod('killLocalModel');
    } catch (_) {}

    // [T7④ 2026-10-16 編織線] localOnly 模式——不上雲。
    // 殺本地模型後 provider 維持 local（無腦可用）=使用者要求下一輪明確重試，
    // 而不是默默把資料送出機器（D7：localOnly 是 M6 的一等設定）
    if (await StorageService.getLocalOnly()) {
      debugPrint('[MemoryGuard] localOnly：critical 只殺本地引擎，不上雲——'
          '維持 provider=local，等使用者重試或喚醒');
      return;
    }

    // 切到雲端
    final current = await StorageService.getProvider() ?? '';
    if (current == 'local') {
      final savedProviders = await _getSavedCloudProviders();
      if (savedProviders.isNotEmpty) {
        await StorageService.saveProvider(savedProviders.first);
        debugPrint('[MemoryGuard] 已切換到 ${savedProviders.first}');
      } else {
        debugPrint('[MemoryGuard] 沒有可用的雲端 provider，無法自動切換');
      }
    }
  }

  /// 取得使用者設定過的雲端 provider 列表
  Future<List<String>> _getSavedCloudProviders() async {
    final providers = <String>[];
    for (final p in ProviderRouter.cloudFallbackOrder) { // [T7⑤] 統一常數
      final token = await StorageService.getToken(provider: p);
      if (token != null && token.isNotEmpty) {
        providers.add(p);
      }
    }
    return providers;
  }

  MemoryGuardLevel _parseLevel(String s) {
    switch (s) {
      case 'critical':
        return MemoryGuardLevel.critical;
      case 'red':
        return MemoryGuardLevel.red;
      case 'yellow':
        return MemoryGuardLevel.yellow;
      default:
        return MemoryGuardLevel.green;
    }
  }

  void dispose() {
    stop();
    _levelChangeController.close();
    _pressureDialogController.close();
  }
}
