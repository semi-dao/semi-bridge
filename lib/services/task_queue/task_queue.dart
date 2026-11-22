// task_queue.dart
// 長任務佇列 — 管理桌面端所有非同步任務的生命週期。
// 在 Dart 主 isolate 跑（瀏覽器操作是 async I/O，不佔 CPU，不需要額外 isolate）。
// 實作 GatewayTaskHandler 介面，讓 Gateway 可以路由 taskRun 請求到此佇列。
// Sprint 19c by 教練 Agent (CEO)

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/task_queue/task.dart';
import '../browser_automation/browser_automation_service.dart';
import '../desktop_bridge_gateway_protocol.dart';
import '../mobile/chat_relay_handler.dart';

/// 任務狀態變化回呼
typedef TaskStatusListener = void Function(Task task);

/// 長任務佇列。
///
/// 職責：
/// - 接收 taskRun 請求 → 建立 Task → 加入佇列 → 委派給實際 handler 執行
/// - 管理任務狀態機：pending → running → awaiting_confirmation → completed/failed/cancelled
/// - 每次狀態變化通知 listener（UI 層 listen 即可更新畫面）
/// - v1 不持久化（while-app-is-running），未來需要再加 SQLite
///
/// 與 BrowserAutomationService 的關係：
/// - TaskQueue 是外層管理器，BrowserAutomationService 是實際執行器
/// - Gateway → TaskQueue.startTask() → BrowserAutomationService.startTask()
/// - TaskQueue 負責狀態追蹤、佇列排序、取消機制
/// - BrowserAutomationService 負責實際的 Chrome 操作
class TaskQueue implements GatewayTaskHandler {
  final BrowserAutomationService _browserService;

  /// 所有任務（進行中 + 已完成，保留最近 N 個）
  final List<Task> _tasks = [];
  static const int _maxRetainedTasks = 50;

  /// 狀態變化 listener 列表
  final List<TaskStatusListener> _listeners = [];

  /// taskType → handler 映射
/// 目前只有 browser.* 類型，未來可以加 file.* / long_task.* 等
  final Map<String, GatewayTaskHandler> _handlers = {};

  TaskQueue({required BrowserAutomationService browserService})
      : _browserService = browserService {
    // 註冊 browser.* 類型
    _handlers['browser'] = _browserService;
    // [S4 2026-11-10] 聊天直送——chat.send（手機訊息注入桌面對話）
    _handlers['chat'] = ChatRelayHandler();
  }

  // ─────────────────────────────────────────────────────────
  // GatewayTaskHandler 實作
  // ─────────────────────────────────────────────────────────

  @override
  String startTask({
    required String taskType,
    required Map<String, dynamic> payload,
    required void Function(double progress, String message) onProgress,
    required void Function(bool success, Map<String, dynamic> result, String? error) onComplete,
    required void Function(String reason, Map<String, dynamic> context) onAwaitingConfirmation,
  }) {
    // 建立內部 Task 追蹤
    final task = Task(
      id: 'task-${DateTime.now().millisecondsSinceEpoch}',
      type: taskType,
      payload: payload,
    );
    _addTask(task);
    task.status = TaskStatus.running;
    task.startedAt = DateTime.now();
    _notifyListeners(task);

    // 找到對應的 handler
    final handler = _findHandler(taskType);
    if (handler == null) {
      task.status = TaskStatus.failed;
      task.error = 'No handler for task type: $taskType';
      task.completedAt = DateTime.now();
      _notifyListeners(task);
      onComplete(false, {}, task.error);
      return task.id;
    }

    // 委派給 handler，用 wrapper 追蹤進度
    final actualTaskId = handler.startTask(
      taskType: taskType,
      payload: payload,
      onProgress: (progress, message) {
        task.progress = progress;
        task.message = message;
        _notifyListeners(task);
        onProgress(progress, message);
      },
      onComplete: (success, result, error) {
        task.status = success ? TaskStatus.completed : TaskStatus.failed;
        task.result = result;
        task.error = error;
        task.progress = 1.0;
        task.completedAt = DateTime.now();
        _notifyListeners(task);
        onComplete(success, result, error);
      },
      onAwaitingConfirmation: (reason, context) {
        task.status = TaskStatus.awaitingConfirmation;
        task.message = reason;
        task.result = context;
        _notifyListeners(task);
        onAwaitingConfirmation(reason, context);
      },
    );

    // 更新 task id 為 handler 回傳的真實 id
    // 注意：我們用內部 task.id 追蹤，handler 回傳的 actualTaskId 用於取消
    task.message = 'Handler task ID: $actualTaskId';

    return task.id;
  }

  @override
  bool cancelTask(String taskId) {
    final task = _findTask(taskId);
    if (task == null || task.isTerminal) return false;

    task.status = TaskStatus.cancelled;
    task.completedAt = DateTime.now();
    _notifyListeners(task);

    // 委派取消給 handler
    final handler = _findHandler(task.type);
    handler?.cancelTask(taskId);

    return true;
  }

  // ─────────────────────────────────────────────────────────
  // 佇列管理
  // ─────────────────────────────────────────────────────────

  /// 所有任務（按建立時間倒序，最新的在前）
  List<Task> get tasks => List.unmodifiable(_tasks.reversed);

  /// 進行中的任務
  List<Task> get activeTasks =>
      _tasks.where((t) => t.isActive).toList();

  /// 已完成的任務
  List<Task> get completedTasks =>
      _tasks.where((t) => t.isTerminal).toList();

  /// 取得單一任務
  Task? getTask(String id) => _findTask(id);

  /// 加入狀態變化 listener
  void addListener(TaskStatusListener listener) {
    _listeners.add(listener);
  }

  /// 移除 listener
  void removeListener(TaskStatusListener listener) {
    _listeners.remove(listener);
  }

  /// 清除已完成的任務
  void clearCompleted() {
    _tasks.removeWhere((t) => t.isTerminal);
  }

  /// 關閉佇列，釋放資源
  Future<void> dispose() async {
    await _browserService.dispose();
    _listeners.clear();
    _tasks.clear();
  }

  // ─────────────────────────────────────────────────────────
  // 內部方法
  // ─────────────────────────────────────────────────────────

  void _addTask(Task task) {
    _tasks.add(task);
    // 超過上限就移除最舊的已完成任務
    while (_tasks.length > _maxRetainedTasks) {
      final oldestCompleted = _tasks
          .where((t) => t.isTerminal)
          .toList();
      if (oldestCompleted.isEmpty) break;
      _tasks.remove(oldestCompleted.first);
    }
  }

  Task? _findTask(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  GatewayTaskHandler? _findHandler(String taskType) {
    // browser.navigate → handler key "browser"
    // file.read → handler key "file"
    // long_task.run → handler key "long_task"
    final prefix = taskType.split('.').first;
    return _handlers[prefix];
  }

  void _notifyListeners(Task task) {
    for (final listener in _listeners) {
      try {
        listener(task);
      } catch (e) {
        debugPrint('[TaskQueue] listener error: $e');
      }
    }
  }
}
