// CrashGuard — 崩潰迴圈守門員（自救三刀・刀一）
//
// [小葵 2026-10-31 Safe Mode] 起源：10-30 暴衝案——素材索引器吃 62,726 筆 →
// Dart heap 83GB → jetsam 連環殺 App 13 次。launchd watchdog 一直拉活，
// 但拉起來又馬上死，使用者看到的是「打不開」。本服務讓 App 在連續快速
// 重啟後自動降級啟動（Safe Mode）——先活著，再談修。
//
// 機制（計劃卡 docs/SELF_RESCUE_THREE_BLADES_PLAN.md「刀一」節）：
// - 每次啟動 markLaunched() 寫時間戳進 heartbeat 檔（crash_guard.json）
// - 10 分鐘內第 3 次啟動 → 判定崩潰迴圈 → safeMode=true
// - 優雅退出（lifecycle detached）清 heartbeat——正常關閉不算崩潰
// - safeMode 持久：jetsam 殺掉的進程沒機會清檔，重啟後照樣讀到
//
// 誠實 UI 鐵則：Safe Mode 進入必須明顯可見（黃色橫幅）、可解釋、可退出。
// 絕不假裝一切正常。

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Directory;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBindingObserver, AppLifecycleState;

import '../vector_db/incremental_ingest_service.dart';

/// Safe Mode 事件（給未來 DiagnosticBox／刀二黑盒子訂閱的合約）。
///
/// [type] 事件種類（白話繁中）；[detail] 白話補充說明。
/// 這是與刀二的接縫：DiagnosticBox 未來只要 listen 這條 stream，
/// 就能把 Safe Mode 事件收進黑盒子。
class CrashGuardEvent {
  const CrashGuardEvent({required this.type, required this.detail, required this.at});

  /// 事件種類：'safe_mode_entered'／'safe_mode_exited'／'heartbeat_cleared'
  final String type;

  /// 白話繁中補充說明（給人看，也給刀二黑盒子存檔）
  final String detail;

  /// 事件時間
  final DateTime at;

  @override
  String toString() => '[CrashGuard] $type：$detail（$at）';
}

/// [刀二合約] DiagnosticBox 反向接線座——刀一不 import 刀二（依賴方向：
/// app.dart 接線，CrashGuard 只認這個 callback 座）。未接線時全 null。
class DiagnosticBoxBridge {
  /// Safe Mode 事件 → 黑盒子。app.dart 內接：
  /// `DiagnosticBoxBridge.onCrashGuardEvent = DiagnosticBox.instance.log;`
  static void Function(String kind, String detail)? onCrashGuardEvent;
}

/// 崩潰迴圈守門員單例。
///
/// 繼承 ChangeNotifier：safeMode 變化時 notifyListeners()，
/// 讓 Safe Mode 橫幅（SafeModeBanner）用 ListenableBuilder 即時反應。
///
/// 可注入 [storageDir]（heartbeat 檔所在目錄）與 [clock]（時間源），
/// 測試不碰真實 App Support、不靠真實時間。
class CrashGuard extends ChangeNotifier {
  CrashGuard._();
  static final CrashGuard instance = CrashGuard._();

  /// [測試注入] 測試專用實例——單例保留給正式程式，測試用乾淨實例
  /// 避免跨測線污染。
  factory CrashGuard.forTest() => CrashGuard._();

  // ── 可注入依賴（測試用）──────────────────────────────────────
  /// heartbeat 檔所在目錄。預設 null＝尚未接線，init() 時由 main 注入。
  Directory? storageDir;

  /// 時鐘函數。預設系統時間；測試注入 fake time 控制「10 分鐘」判定。
  DateTime Function() clock = DateTime.now;

  // ── 閾值常數（可持續觀察調整）────────────────────────────────
  /// 崩潰迴圈判定窗：10 分鐘
  static const Duration windowDuration = Duration(minutes: 10);

  /// 窗內第 N 次啟動觸發 Safe Mode：3 次
  static const int launchThreshold = 3;

  /// heartbeat 檔名
  static const String fileName = 'crash_guard.json';

  // ── 狀態 ────────────────────────────────────────────────────
  /// 是否處於安全模式。持久判定結果（跨本次啟動有效，直到 exitSafeMode）。
  bool safeMode = false;

  /// 橫幅是否被使用者〔知道了〕收起（本次啟動內有效）
  bool _bannerDismissed = false;

  /// 橫幅現在該不該顯示：Safe Mode 中且未被收起
  bool get shouldShowBanner => safeMode && !_bannerDismissed;

  /// 本次啟動前的 heartbeat 陣列（判斷依據，留給診斷用）
  List<DateTime> _heartbeats = [];

  final StreamController<CrashGuardEvent> _eventController =
      StreamController<CrashGuardEvent>.broadcast();

  /// Safe Mode 事件流——與刀二 DiagnosticBox 的合約：
  /// broadcast stream，任何人可訂閱，事件文字全白話繁中。
  Stream<CrashGuardEvent> get eventStream => _eventController.stream;

  File get _heartbeatFile {
    final dir = storageDir;
    if (dir == null) {
      throw StateError('CrashGuard 尚未接線：先呼叫 init() 注入 storageDir');
    }
    return File('${dir.path}/$fileName');
  }

  /// 啟動早期接線（main() 內呼叫）：注入目錄即可，讀檔延到 markLaunched。
  void init(Directory dir) {
    storageDir = dir;
  }

  /// 讀 heartbeat 檔（crash_guard.json），壞檔視為空——不擋啟動。
  Future<List<DateTime>> _loadHeartbeats() async {
    try {
      final file = _heartbeatFile;
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map((e) => DateTime.tryParse(e.toString()))
          .whereType<DateTime>()
          .toList();
    } catch (e) {
      // 檔案毀損不算崩潰證據——fail-open，寧可漏判不可誤判擋啟動
      debugPrint('[CrashGuard] heartbeat 讀取失敗（視為空）: $e');
      return [];
    }
  }

  /// 寫 heartbeat 檔。失敗只 log——守門員掛了不能反過來擋 App 活著。
  Future<void> _saveHeartbeats(List<DateTime> stamps) async {
    try {
      final file = _heartbeatFile;
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(stamps.map((d) => d.toIso8601String()).toList()),
      );
    } catch (e) {
      debugPrint('[CrashGuard] heartbeat 寫入失敗（不擋啟動）: $e');
    }
  }

  /// 記錄本次啟動＋判定是否進 Safe Mode。main() 早期呼叫。
  ///
  /// 判定：windowDuration 內已有 >= launchThreshold-1 筆紀錄 → 這是第
  /// launchThreshold 次啟動 → 進 Safe Mode。
  Future<void> markLaunched() async {
    final now = clock();
    _heartbeats = await _loadHeartbeats();

    // 只留窗口內的紀錄
    _heartbeats =
        _heartbeats.where((d) => now.difference(d) <= windowDuration).toList();

    if (_heartbeats.length >= launchThreshold - 1) {
      safeMode = true;
      notifyListeners(); // [小葵 2026-10-31] 橫幅即時反應
      debugPrint(
        '[CrashGuard] 🟡 崩潰迴圈判定成立：窗口內第 ${_heartbeats.length + 1} 次啟動 → 進 Safe Mode',
      );
      _emit(
        'safe_mode_entered',
        '系統偵測到 App 在短時間內連續重啟（${_heartbeats.length + 1} 次），已進入安全模式：背景索引與本地模型自動排程暫停，你的資料完好無損。',
      );
    } else {
      debugPrint(
        '[CrashGuard] 啟動 heartbeat 記錄（窗口內 ${_heartbeats.length + 1} 次，未達門檻 $launchThreshold）',
      );
    }

    // 記下這次啟動（含 Safe Mode 下——重啟計數要持續累積）
    _heartbeats = [..._heartbeats, now];
    await _saveHeartbeats(_heartbeats);
  }

  /// 優雅退出——lifecycle detached（正常關閉）時呼叫，清空 heartbeat。
  ///
  /// 正常關閉不算崩潰：下次啟動從零起算，不會因為「用戶開開關關三次」
  /// 誤進 Safe Mode。
  Future<void> clearHeartbeat() async {
    _heartbeats = [];
    safeMode = false;
    await _saveHeartbeats([]);
    debugPrint('[CrashGuard] 優雅退出——heartbeat 已清空');
    _emit('heartbeat_cleared', 'App 正常關閉，重啟計數已重置。');
  }

  /// 使用者按〔重試背景服務〕時呼叫：退出 Safe Mode。
  ///
  /// 做三件事：清 heartbeat（重啟計數歸零）、safeMode=false、
  /// 重新拉 IncrementalIngestService.start()（被停掉的背景索引）。
  Future<void> exitSafeMode() async {
    safeMode = false;
    notifyListeners(); // [小葵 2026-10-31] 橫幅即時消失
    _bannerDismissed = false;
    _heartbeats = [];
    await _saveHeartbeats([]);
    debugPrint('[CrashGuard] 使用者退出 Safe Mode——背景服務將重新啟動');
    _emit('safe_mode_exited', '你按了「重試背景服務」，安全模式已退出，背景索引重新啟動。');
    // 重新拉背景索引（10-30 案暴衝源，Safe Mode 下被擋在 start 前）。
    // [測試注入] exitRestartHook 非 null 時走注入路徑（測試不碰真實索引器）。
    if (exitRestartHook != null) {
      await exitRestartHook!();
      return;
    }
    try {
      final ingest = IncrementalIngestService.instance;
      await ingest.start();
    } catch (e) {
      debugPrint('[CrashGuard] 背景索引重啟失敗（誠實不假成功，留給橫幅重試）: $e');
      rethrow;
    }
  }

  /// [測試注入] 退出 Safe Mode 時的背景索引重啟動作。
  /// 預設 null＝走真實 IncrementalIngestService.start()。
  @visibleForTesting
  Future<void> Function()? exitRestartHook;

  /// 使用者按〔知道了〕時呼叫：只收橫幅，Safe Mode 狀態不變。
  ///
  /// 誠實 UI：背景服務仍是暫停的——只是使用者選擇不再看這條提醒。
  /// （與 exitSafeMode 不同：不清 heartbeat、不重啟索引）
  void dismissBanner() {
    _bannerDismissed = true;
    notifyListeners();
    debugPrint('[CrashGuard] 橫幅已收起（Safe Mode 維持，背景服務仍暫停）');
    _emit('banner_dismissed', '你按了「知道了」，橫幅收起。安全模式仍在，背景索引與模型排程維持暫停。');
    DiagnosticBoxBridge.onCrashGuardEvent?.call(
        'banner_dismissed', '使用者收起安全模式橫幅（狀態維持）');
  }

  void _emit(String type, String detail) {
    _eventController.add(CrashGuardEvent(
      type: type,
      detail: detail,
      at: clock(),
    ));
    // [刀二合約] DiagnosticBox 反向入口——app.dart 接線後，每條事件同步
    // 進黑盒子（kind: safe_mode）。未接線時為 null，零依賴。
    DiagnosticBoxBridge.onCrashGuardEvent?.call(type, detail);
  }

  /// 測試用：完整重置（狀態＋依賴）
  @visibleForTesting
  void resetForTest() {
    safeMode = false;
    _heartbeats = [];
    storageDir = null;
    clock = DateTime.now;
    // ChangeNotifier 沒有 reset API——測試各 case 建新實例即可，
    // 單例僅在正式程式使用。此處僅重置純欄位。
  }
}

/// [小葵 2026-10-31 Safe Mode] main() 用的 CrashGuard lifecycle 觀察器：
/// App 正常關閉（detached）時清 heartbeat——正常關閉不算崩潰。
///
/// 注意：jetsam 殺進程時 detached 不會觸發——這正是設計重點，
/// 被殺掉的紀錄會留在 heartbeat 檔裡成為崩潰證據。
class CrashGuardLifecycleObserver with WidgetsBindingObserver {
  const CrashGuardLifecycleObserver();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // 優雅退出：清 heartbeat。fire-and-forget——detached 時不保證等得到 await
      unawaited(CrashGuard.instance.clearHeartbeat());
    }
  }
}
