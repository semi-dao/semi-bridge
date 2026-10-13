import 'dart:async';

import 'package:flutter/foundation.dart';

import '../vector_db/identity_reembed_service.dart';

/// 系統活動中心——背景任務的唯一顯示處（單一真相源）。
///
/// [小葵 2026-09-30 金礦1] 起源：IdentityReembed 背景 2940 筆燒 200% CPU，
/// 使用者只覺得「電腦遲鈍連打字都難」，完全無從得知 App 在做什麼。
/// （2026-09-29 CPU 懸案，sample 取樣破案）
///
/// 設計：
/// - 每個長時背景任務向這裡「掛牌」（id、名稱、進度、狀態）
/// - UI 訂閱 stream 即時刷新；沒有 UI 時任務照跑（顯示層與執行層分離）
/// - 任務完成 → 保留 5 分鐘供回看 → 自動收牌
class BackgroundTaskRegistry {
  BackgroundTaskRegistry._();
  static final instance = BackgroundTaskRegistry._();

  final _tasks = <String, BackgroundTask>{};
  final _controller = StreamController<List<BackgroundTask>>.broadcast();
  Timer? _sweeper;

  /// UI 訂閱入口
  Stream<List<BackgroundTask>> get stream => _controller.stream;
  List<BackgroundTask> get tasks => List.unmodifiable(_tasks.values);

  /// 掛牌（或更新）：任務開始/進度變化時呼叫
  void update(BackgroundTask task) {
    // [幽靈修復] running 狀態的 update 自動蓋 progressAt 戳（殭屍檢測基準）
    _tasks[task.id] = (task.status == BackgroundTaskStatus.running &&
            task.progressAt == null)
        ? _withProgressAt(task)
        : task;
    _controller.add(tasks);
    _ensureSweeper();
  }

  BackgroundTask _withProgressAt(BackgroundTask t) {
    // 不可變物件沒有 copyWith(progressAt:) 的強制覆蓋——重建
    return BackgroundTask(
      id: t.id, name: t.name, detail: t.detail, progress: t.progress,
      current: t.current, status: t.status, note: t.note,
      startedAt: t.startedAt, endedAt: t.endedAt,
      progressAt: DateTime.now(),
    );
  }

  /// 收牌：任務結束（會先保留供回看，由 sweeper 真正移除）
  /// [U1 2026-09-30] 暫停請求——任務在批次邊界檢查；await resume 完成後繼續
  /// （溫和暫停：不打斷當前筆，給進行中的大任務讓路）
  final _pauseRequests = <String>{};
  bool isPauseRequested(String id) => _pauseRequests.contains(id);
  void requestPause(String id) {
    if (_pauseRequests.add(id)) _controller.add(tasks); // 觸發 UI 更新
  }

  void resumeTask(String id) {
    if (_pauseRequests.remove(id)) _controller.add(tasks);
  }

  void finish(String id, {String? note}) {
    final t = _tasks[id];
    if (t == null) return;
    _tasks[id] = t.copyWith(
      status: BackgroundTaskStatus.done,
      progress: 1.0,
      note: note ?? t.note,
      endedAt: DateTime.now(),
    );
    _controller.add(tasks);
  }

  /// 真正移除（sweeper 對完成超過 5 分鐘的任務自動呼叫）
  void remove(String id) {
    _tasks.remove(id);
    _controller.add(tasks);
  }

  void _ensureSweeper() {
    _sweeper ??= Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      final expired = _tasks.values
          .where((t) =>
              t.status == BackgroundTaskStatus.done &&
              t.endedAt != null &&
              now.difference(t.endedAt!).inMinutes >= 5)
          .map((t) => t.id)
          .toList();
      if (expired.isNotEmpty) {
        expired.forEach(remove);
      }
      // [幽靈進度條修復 2026-10-01] 殭屍任務清理——
      // running 超過 30 分鐘沒有進度推進（update 會刷新 progressAt）
      // = 任務實際上已死（異常路徑沒走到 finish）→ 標記 error 收尾，
      // 進度條不再永凍（Blue 案：檔案嵌入 86% 卡死實案）
      final zombies = _tasks.values
          .where((t) =>
              t.status == BackgroundTaskStatus.running &&
              t.progressAt != null &&
              now.difference(t.progressAt!).inMinutes >= 30)
          .toList();
      for (final z in zombies) {
        finish(z.id, note: '任務逾時無回應（系統自動收尾）');
      }
      if (_tasks.isEmpty) {
        _sweeper?.cancel();
        _sweeper = null;
      }
    });
  }
}

enum BackgroundTaskStatus { running, done, error }

class BackgroundTask {
  final String id; // 穩定識別（如 'identity_reembed'）
  final String name; // 顯示名（如「身份重嵌入」）
  final String detail; // 一行說明（如「把檔案升級為身份檢索」）
  final double progress; // 0~1；無進度概念的任務用 -1（顯示脈衝）
  final String? current; // 當前處理項
  final BackgroundTaskStatus status;
  final String? note; // 結語（完成時顯示）
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime? progressAt; // [幽靈修復] 最後進度刷新時間（殭屍檢測用）

  const BackgroundTask({
    required this.id,
    required this.name,
    required this.detail,
    this.progress = -1,
    this.current,
    this.status = BackgroundTaskStatus.running,
    this.note,
    required this.startedAt,
    this.endedAt,
    this.progressAt,
  });

  BackgroundTask copyWith({
    double? progress,
    String? current,
    BackgroundTaskStatus? status,
    String? note,
    DateTime? endedAt,
  }) =>
      BackgroundTask(
        id: id,
        name: name,
        detail: detail,
        progress: progress ?? this.progress,
        current: current ?? this.current,
        status: status ?? this.status,
        note: note ?? this.note,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        progressAt: progressAt ?? this.progressAt,
      );
}

/// [小葵 2026-09-30] 橋接：把 IdentityReembed 的進度掛到 Registry。
/// 在 BrainContainerService 啟動重嵌時安裝；UI 不需要知道任務細節。
class IdentityReembedReporter {
  static const _id = 'identity_reembed';
  static Timer? _timer;

  static void attach() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      final p = IdentityReembedService.instance.progress();
      final reg = BackgroundTaskRegistry.instance;
      if (p['running'] == true) {
        final total = (p['total'] as int?) ?? 0;
        final done = (p['done'] as int?) ?? 0;
        reg.update(BackgroundTask(
          id: _id,
          name: '身份重嵌入',
          detail: '把檔案升級為身份檢索（v2）',
          progress: total > 0 ? done / total : -1,
          current: p['current'] as String?,
          startedAt: DateTime.now(),
        ));
      } else if (total0(reg) != null) {
        // 不在跑且先前掛過牌 → 收牌
        reg.finish(_id, note: '完成 ${(total0(reg))} 筆');
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  static String? total0(BackgroundTaskRegistry reg) {
    for (final t in reg.tasks) {
      if (t.id == _id && t.status == BackgroundTaskStatus.running) return t.name;
    }
    return null;
  }
}
