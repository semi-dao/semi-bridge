import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// [Blue 令 2026-10-05 · 以終為始] 視窗自動適裝（Window Auto-Fit）
///
/// 「更聰明的方法不是寫死預設 APP 大小，而是讓視窗預設＋最小尺寸
/// 在未來按鈕加更多的時候，預設的視窗就會自動變大。」
///
/// ── 這是什麼 ──
/// 頂部導航列（或任何註冊進來的「需求寬度」源）告訴本服務：
///「我的內容需要 N 像素寬才不擠」。本服務據此：
///   1. 動態調整 minimumSize——視窗永遠縮不小於內容需求（縮了就爆警示條）
///   2. 若當前視窗寬 < 需求 → 自動把視窗撐大到需求寬（僅一次、可設定）
///
/// 未來加按鈕 → 頂列量出的需求寬變大 → 視窗自動長大 → 永遠不爆。
/// 不寫死任何尺寸——「內容決定容器」取代「容器約束內容」。
///
/// ── 設計原則 ──
/// * 只在桌面平台作用（macOS/Windows/Linux；iOS/Web 跳過）
/// * 需求寬度由 UI 層「實測」（RenderBox 自然寬）上報，不是猜的
/// * 自動撐大僅在「使用者沒有手動縮小過」時生效一次（尊重使用者佈局）
/// * 所有動作有 log（[WindowAutoFit] 前綴）——教練可驗證
class WindowAutoFitService {
  WindowAutoFitService._();
  static final WindowAutoFitService instance = WindowAutoFitService._();

  /// 各需求源上報的寬度（key = 源名，如 'top_bar'）
  final Map<String, double> _requiredWidths = {};

  /// 使用者是否手動改過視窗大小（改過就不自動撐大，只調 minimumSize）
  bool _userResized = false;

  /// 防抖：視窗操作節流（避免每幀都 setMinimumSize）
  Timer? _pending;
  DateTime _lastApply = DateTime.fromMillisecondsSinceEpoch(0);
  static const _minApplyInterval = Duration(milliseconds: 800);

  /// 視窗寬度緩衝（左右 padding + 一點呼吸空間）
  static const double _widthBuffer = 24.0;

  /// 上報某個區域需要的最小寬度（像素）。
  /// UI 層在 layout 後實測自己的自然寬，呼叫此方法。
  void reportRequiredWidth(String source, double width) {
    if (width <= 0) return;
    final old = _requiredWidths[source];
    if (old != null && (old - width).abs() < 0.5) return; // 沒變就不折騰
    _requiredWidths[source] = width;
    _scheduleApply();
  }

  /// 清除某個需求源（頁面關閉時）
  void clearRequiredWidth(String source) {
    if (_requiredWidths.remove(source) != null) {
      _scheduleApply();
    }
  }

  /// 目前總需求寬（所有源最大值 + buffer）
  double get requiredWidth {
    if (_requiredWidths.isEmpty) return 0;
    final maxW = _requiredWidths.values.reduce((a, b) => a > b ? a : b);
    return maxW + _widthBuffer;
  }

  /// 查詢用：目前各源需求（教練/debug 用）
  Map<String, double> get debugWidths => Map.unmodifiable(_requiredWidths);

  /// 使用者手動改視窗大小時叫這個（window_listener onWindowResize）
  void markUserResized() => _userResized = true;

  bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  void _scheduleApply() {
    if (!isDesktop) return;
    _pending?.cancel();
    _pending = Timer(_minApplyInterval, _apply);
  }

  Future<void> _apply() async {
    if (!isDesktop) return;
    final now = DateTime.now();
    if (now.difference(_lastApply) < _minApplyInterval) return;
    _lastApply = now;

    final need = requiredWidth;
    if (need <= 0) return;

    try {
      final current = await windowManager.getSize();

      // 1) minimumSize 永遠跟上需求（高不變——需求寬度跟高度無關）
      const minH = 720.0;
      final newMin = Size(need, minH);
      await windowManager.setMinimumSize(newMin);
      debugPrint(
          '[WindowAutoFit] minimumSize → ${need.toInt()}x$minH（需求源: ${_requiredWidths.keys.toList()}）');

      // 2) 視窗比需求還小 → 自動撐大（僅在使用者沒手動縮過時）
      if (current.width < need && !_userResized) {
        await windowManager.setSize(Size(need, current.height));
        debugPrint(
            '[WindowAutoFit] 視窗自動撐大 → ${need.toInt()}x${current.height.toInt()}（內容需要）');
      }
    } catch (e) {
      debugPrint('[WindowAutoFit] 應用失敗: $e');
    }
  }

  void dispose() {
    _pending?.cancel();
    _requiredWidths.clear();
  }
}
