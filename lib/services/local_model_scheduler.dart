// 本地模型自動離合器（Auto Clutch）——單模型時間多工的排程核心。
//
/// [小葵 2026-10-01 Blue 拍板開工] 設計稿 v0.2（/tmp/auto_clutch_design.md）。
///
/// 起源：嵌入照片辨識（12B）與聊天/任務（E4B）搶同一個 18789 模型槽，
/// Blue 得當人肉排程器去系統頁手動換模型。16GB 機不能雙開（GPU 連坐崩）。
///
/// 模型（像手排車）：
/// - 引擎（GPU）一顆，動力（模型）按路況接合
/// - 聊天是方向盤（使用者優先權恆最高）
/// - 辨識是巡航（閒置時跑，佇列消化）
///
/// 狀態機：
///   runChat（預設）→ 閒置 + 佇列有工作 → switching → runVision
///   runVision → 佇列清空 or 使用者發話 → switching → runChat
///
/// 鐵律（教訓直提煉）：
/// 1. 聊天優先權絕對高於辨識——使用者發話 = 最高優先中斷訊號
/// 2. 切換只在安全點（嵌入 item 邊界），不在 item 中間硬砍
/// 3. 失敗一次就罷手回手動（09-29 自動恢復防無限循環鐵律）
/// 4. UI 誠實：切換中顯示狀態、佇列顯示數量、失敗紅字不假裝
///
/// 進程拓撲（步驟 0 查證 2026-10-01）：
/// - EmbeddingGemma（向量嵌入）走 flutter_gemma 在 App 進程內，不搶 18789
/// - 18789 只有照片描述生成（local_vision_analyze）在搶——離合器只管這個

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_model_runtime_service.dart';
import 'storage_service.dart';

/// 離合器狀態
enum LocalClutchState {
  /// 夥伴模型在跑（預設態）
  runChat,

  /// 換模型中（載入 15-25s）
  switching,

  /// 辨識模型在跑（消化嵌入佇列）
  runVision,

  /// 自動離合失敗，罷手回手動（09-29 鐵律）
  faulted,
}

/// 離合器狀態快照（UI 用）
class LocalClutchSnapshot {
  final LocalClutchState state;
  final String? companionModelId;
  final String? visionModelId;
  final int pendingVisionItems;
  final String? faultReason;

  const LocalClutchSnapshot({
    required this.state,
    this.companionModelId,
    this.visionModelId,
    this.pendingVisionItems = 0,
    this.faultReason,
  });

  bool get hasVisionRole =>
      visionModelId != null &&
      visionModelId!.isNotEmpty &&
      visionModelId != companionModelId;
}

class LocalModelScheduler {
  LocalModelScheduler._();
  static final LocalModelScheduler instance = LocalModelScheduler._();

  final _runtimeService = LocalModelRuntimeService();

  /// 狀態變更廣播（SystemActivityCard / 模型頁訂閱）
  final _controller = StreamController<LocalClutchSnapshot>.broadcast();
  Stream<LocalClutchSnapshot> get stream => _controller.stream;

  LocalClutchSnapshot _snapshot = const LocalClutchSnapshot(
    state: LocalClutchState.runChat,
  );
  LocalClutchSnapshot get snapshot => _snapshot;

  /// 使用者活躍訊號（聊天優先權的實現）：
  /// AgentLoop 開跑 / 使用者發話時 call。重置閒置計時器。
  DateTime _lastUserActivity = DateTime.fromMillisecondsSinceEpoch(0);
  void markUserActivity() {
    _lastUserActivity = DateTime.now();
    // 使用者發話當下正在辨識 → 請求切回聊天（等安全點）
    if (_snapshot.state == LocalClutchState.runVision) {
      debugPrint('[Clutch] 使用者發話——請求切回夥伴模型（等安全點）');
      _requestChatPriority();
    }
  }

  /// 閒置門檻：使用者 N 秒沒動作 + 佇列有工作 → 才切辨識
  static const idleThreshold = Duration(seconds: 90);

  /// 佇列長度注入（嵌入管線註冊回呼）
  int Function()? _pendingVisionProvider;
  void registerPendingVisionProvider(int Function() provider) {
    _pendingVisionProvider = provider;
  }

  /// [小葵 2026-10-01 步驟7] 直接更新 pending 計數（管線 DB 查詢後推送）
  void updatePendingVisionCount(int count) {
    if (count != _snapshot.pendingVisionItems) {
      _snapshot = LocalClutchSnapshot(
        state: _snapshot.state,
        companionModelId: _snapshot.companionModelId,
        visionModelId: _snapshot.visionModelId,
        pendingVisionItems: count,
        faultReason: _snapshot.faultReason,
      );
      _controller.add(_snapshot);
    }
  }

  /// 辨識工作進行中旗標（嵌入管線 set/clear）——安全點判斷用
  bool _visionJobActive = false;
  set visionJobActive(bool active) {
    _visionJobActive = active;
    if (!active && _chatPriorityRequested) {
      // 安全點抵達（嵌入 item 結束）→ 執行切回
      _chatPriorityRequested = false;
      _switchTo(LocalClutchState.runChat);
    } else if (!active && _snapshot.state == LocalClutchState.runVision) {
      // 佇列消化完或 item 間隙 → 檢查是否還有工作
      _evaluate();
    }
  }

  bool _chatPriorityRequested = false;
  void _requestChatPriority() {
    if (!_visionJobActive) {
      _switchTo(LocalClutchState.runChat);
    } else {
      _chatPriorityRequested = true; // 等安全點
    }
  }

  /// 雙角色槽設定（模型頁寫入）
  Future<void> setRoles({
    String? companionModelId,
    String? visionModelId,
  }) async {
    _snapshot = LocalClutchSnapshot(
      state: _snapshot.state,
      companionModelId: companionModelId ?? _snapshot.companionModelId,
      visionModelId: visionModelId ?? _snapshot.visionModelId,
      pendingVisionItems: _snapshot.pendingVisionItems,
      faultReason: _snapshot.faultReason,
    );
    await StorageService.setLocalCompanionModel(companionModelId);
    await StorageService.setLocalVisionModel(visionModelId);
    _controller.add(_snapshot);
  }

  /// 啟動時載入角色設定
  Future<void> loadRoles() async {
    final companion = await StorageService.getLocalCompanionModel();
    final vision = await StorageService.getLocalVisionModel();
    _snapshot = LocalClutchSnapshot(
      state: _snapshot.state,
      companionModelId: companion,
      visionModelId: vision,
      pendingVisionItems: _snapshot.pendingVisionItems,
    );
    _controller.add(_snapshot);
  }

  /// 〔現在辨識〕手動按鈕——不等閒置直接切（Blue 拍板放系統活動中心）
  Future<void> runVisionNow() async {
    if (!_snapshot.hasVisionRole) {
      debugPrint('[Clutch] 未設辨識模型槽——手動觸發忽略');
      return;
    }
    debugPrint('[Clutch] 手動觸發辨識（現在辨識按鈕）');
    await _switchTo(LocalClutchState.runVision);
  }

  /// 主評估循環（定時 or 事件驅動 call）
  Future<void> _evaluate() async {
    if (_snapshot.state != LocalClutchState.runChat) return;
    if (!_snapshot.hasVisionRole) return;
    final pending = _pendingVisionProvider?.call() ?? 0;
    if (pending <= 0) return;
    final idle = DateTime.now().difference(_lastUserActivity) > idleThreshold;
    if (!idle) return;
    debugPrint('[Clutch] 閒置 $idleThreshold + 待辨識 $pending 張 → 切辨識模式');
    await _switchTo(LocalClutchState.runVision);
  }

  int _faultCount = 0;

  Future<void> _switchTo(LocalClutchState target) async {
    if (_snapshot.state == target) return;
    final targetModel = target == LocalClutchState.runVision
        ? _snapshot.visionModelId
        : _snapshot.companionModelId;
    if (targetModel == null || targetModel.isEmpty) return;

    _snapshot = LocalClutchSnapshot(
      state: LocalClutchState.switching,
      companionModelId: _snapshot.companionModelId,
      visionModelId: _snapshot.visionModelId,
      pendingVisionItems: _pendingVisionProvider?.call() ?? 0,
      faultReason: _snapshot.faultReason,
    );
    _controller.add(_snapshot);

    try {
      // 換模型 = server 重啟（安全：整進程換掉，無 KV 毒化問題）
      await _runtimeService.startServer(modelId: targetModel);
      _faultCount = 0;
      _snapshot = LocalClutchSnapshot(
        state: target,
        companionModelId: _snapshot.companionModelId,
        visionModelId: _snapshot.visionModelId,
        pendingVisionItems: _pendingVisionProvider?.call() ?? 0,
      );
      debugPrint('[Clutch] ✓ 已切換到 ${target.name}（$targetModel）');
    } catch (e) {
      _faultCount++;
      // 09-29 鐵律：失敗一次就罷手，絕不自動重試無限循環
      debugPrint('[Clutch] ✗ 切換失敗（第 $_faultCount 次）：$e');
      _snapshot = LocalClutchSnapshot(
        state: LocalClutchState.faulted,
        companionModelId: _snapshot.companionModelId,
        visionModelId: _snapshot.visionModelId,
        pendingVisionItems: _pendingVisionProvider?.call() ?? 0,
        faultReason: '自動切換失敗：$e',
      );
      // 罷手：嘗試恢復夥伴模型（使用者主體體驗優先）
      try {
        final companion = _snapshot.companionModelId;
        if (companion != null && companion.isNotEmpty) {
          await _runtimeService.startServer(modelId: companion);
        }
      } catch (_) {} // 手動按鈕接手
    }
    _controller.add(_snapshot);
  }

  /// 故障復位（使用者手動按鈕 or 模型頁操作後 call）
  void clearFault() {
    _faultCount = 0;
    _snapshot = LocalClutchSnapshot(
      state: LocalClutchState.runChat,
      companionModelId: _snapshot.companionModelId,
      visionModelId: _snapshot.visionModelId,
      pendingVisionItems: _snapshot.pendingVisionItems,
    );
    _controller.add(_snapshot);
  }

  /// 定時評估器（App 啟動時掛上）
  Timer? _evalTimer;
  void start() {
    loadRoles();
    _evalTimer?.cancel();
    _evalTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshPending();
      _evaluate();
    });
  }

  void stop() {
    _evalTimer?.cancel();
    _evalTimer = null;
  }

  void _refreshPending() {
    final pending = _pendingVisionProvider?.call() ?? 0;
    if (pending != _snapshot.pendingVisionItems) {
      _snapshot = LocalClutchSnapshot(
        state: _snapshot.state,
        companionModelId: _snapshot.companionModelId,
        visionModelId: _snapshot.visionModelId,
        pendingVisionItems: pending,
        faultReason: _snapshot.faultReason,
      );
      _controller.add(_snapshot);
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
