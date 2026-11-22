// ingest_circuit_breaker.dart
// [小葵 2026-10-31 熔斷器] 刀三：索引熔斷器——素材索引循環的防暴衝保險絲。
//
// 起源：10-30 暴衝案——使用者把 12G 備份搬進監看根目錄，素材索引器
// 遞迴全掃吃進 62,726 筆 → embedding 循環 → Dart heap 83GB →
// 被 macOS jetsam 連環殺。治本排除（04-備份）已由 commit ff38072e 落地；
// 本檔是「保險絲」：任何單輪量異常就熔斷暫停，待明確重試。
//
// 設計（SELF_RESCUE_THREE_BLADES_PLAN.md 刀三）：
// - 閘 A：單輪 fullScan 累積 records > scanMaxRecords → 拋 ScanAbortedException
//   （asset_index_service._scanDirectory 觸發），該 root 進 circuit-open。
// - 閘 B：generateEmbeddings pending > embedMaxPending → 拒跑本輪，
//   開嵌入熔斷旗標（全循環層級，不綁 root）。
// - 兩道閘都「寧可暫停，不可暴衝」：只有 resetCircuits()（明確重試，
//   UI/MCP 呼叫）能復位；週期兜底/watcher 自動重掃不會誤觸重試。
// - 事件廣播：白話繁中事件字串，供刀二 DiagnosticBox 訂閱（合約：
//   Stream<String>，收尾小葵接線）。
// - 限額可調：brain_meta 鍵 'ingest_circuit_limits'（JSON
//   {"scanMaxRecords":10000,"embedMaxPending":5000}），讀不到用預設。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../brain_container/brain_database.dart';

/// 閘 A 觸發時拋出的熔斷例外。
///
/// [小葵 2026-10-31 熔斷器] 注意：_scanDirectory 內部有 catch-all 的
/// try/catch（吞一般 IO 例外），呼叫端必須 `on ScanAbortedException`
/// rethrow 穿透，否則熔斷訊號會被吞掉、暴衝照樣發生。
class ScanAbortedException implements Exception {
  /// 觸發熔斷的根目錄（正規化後）
  final String root;

  /// 觸發當下已累積的檔案數
  final int count;

  /// 本輪上限（scanMaxRecords）
  final int limit;

  const ScanAbortedException(this.root, this.count, this.limit);

  @override
  String toString() =>
      'ScanAbortedException: $root 單輪 $count 筆超過上限 $limit（熔斷）';
}

/// 限額設定（brain_meta 'ingest_circuit_limits' 的形狀）
class IngestCircuitLimits {
  /// 單輪掃描累積檔案數上限（閘 A）
  final int scanMaxRecords;

  /// 嵌入佇列 pending 數上限（閘 B）
  final int embedMaxPending;

  const IngestCircuitLimits({
    this.scanMaxRecords = 10000,
    this.embedMaxPending = 5000,
  });

  factory IngestCircuitLimits.fromJson(Map<String, dynamic> json) {
    return IngestCircuitLimits(
      scanMaxRecords:
          (json['scanMaxRecords'] as num?)?.toInt() ?? 10000,
      embedMaxPending:
          (json['embedMaxPending'] as num?)?.toInt() ?? 5000,
    );
  }

  Map<String, dynamic> toJson() => {
        'scanMaxRecords': scanMaxRecords,
        'embedMaxPending': embedMaxPending,
      };
}

/// 素材索引熔斷器（單例）。
///
/// [小葵 2026-10-31 熔斷器] 狀態單一真相源：
/// - `_openRoots`：閘 A 熔斷中的 root 集合（IncrementalIngestService
///   據此跳過 _scanDirtyRoots + 忽略 watcher 事件）
/// - `embedCircuitOpen`：閘 B 嵌入熔斷旗標（generateEmbeddings 進場檢查）
/// - `events`：白話繁中事件廣播（DiagnosticBox 訂閱合約）
class IngestCircuitBreaker {
  IngestCircuitBreaker._();
  static final IngestCircuitBreaker instance = IngestCircuitBreaker._();

  static const _limitsKey = 'ingest_circuit_limits';

  /// 預設限額（brain_meta 讀不到時用）
  static const IngestCircuitLimits defaultLimits = IngestCircuitLimits();

  IngestCircuitLimits _limits = defaultLimits;
  bool _limitsLoaded = false;

  /// 閘 A：熔斷中的 root 集合（後續自動重掃跳過）
  final Set<String> _openRoots = {};

  /// 閘 B：嵌入熔斷旗標
  bool _embedCircuitOpen = false;

  /// 事件廣播（白話繁中，給刀二 DiagnosticBox 訂閱）
  final StreamController<String> _events =
      StreamController<String>.broadcast();
  Stream<String> get events => _events.stream;

  // ── 限額 ──

  /// 目前生效的限額
  IngestCircuitLimits get limits => _limits;

  /// 從 brain_meta 載入限額（讀不到/解析失敗用預設）。
  ///冪等：已載入過不再重讀（重設限額後 App 重啟自然生效）。
  void loadLimits() {
    if (_limitsLoaded) return;
    _limitsLoaded = true;
    try {
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        'SELECT value FROM brain_meta WHERE key = ?',
        [_limitsKey],
      );
      if (rows.isNotEmpty) {
        final raw = rows.first['value'] as String?;
        if (raw != null && raw.isNotEmpty) {
          _limits = IngestCircuitLimits.fromJson(
              jsonDecode(raw) as Map<String, dynamic>);
          debugPrint('[CircuitBreaker] 限額載入（DB 覆寫）: '
              'scan=$_limits.scanMaxRecords embed=${_limits.embedMaxPending}');
          return;
        }
      }
    } catch (e) {
      debugPrint('[CircuitBreaker] 限額載入失敗（用預設）: $e');
    }
    _limits = defaultLimits;
  }

  /// 同步載入限額（DB 未初始化時不炸——用預設，下次有 DB 再載）
  void _ensureLimits() {
    if (_limitsLoaded) return;
    loadLimits();
  }

  // ── 閘 A：掃描熔斷 ──

  /// 該 root 是否熔斷中（_scanDirtyRoots / watcher 檢查）
  bool isRootOpen(String root) => _openRoots.contains(root);

  /// 全部熔斷中的 root（唯讀快照）
  List<String> get openRoots => List.unmodifiable(_openRoots);

  /// 閘 A 觸發：root 進冷卻、發事件。
  /// [小葵 2026-10-31 熔斷器] 由 IncrementalIngestService 攔截
  /// ScanAbortedException 時呼叫。
  void tripScan(String root, int count) {
    _ensureLimits();
    _openRoots.add(root);
    final msg = '熔斷：$root 單輪 $count 筆超過上限 ${_limits.scanMaxRecords}';
    debugPrint('[CircuitBreaker] $msg');
    _emit(msg);
  }

  // ── 閘 B：嵌入熔斷 ──

  /// 嵌入熔斷旗標（generateEmbeddings 進場檢查）
  bool get embedCircuitOpen => _embedCircuitOpen;

  /// 閘 B 觸發：開嵌入熔斷旗標、發事件。
  void tripEmbed(int pending) {
    _ensureLimits();
    _embedCircuitOpen = true;
    final msg = '熔斷：待嵌入檔案 $pending 筆超過上限 ${_limits.embedMaxPending}，'
        '嵌入循環已暫停，待明確重試';
    debugPrint('[CircuitBreaker] $msg');
    _emit(msg);
  }

  // ── 明確重試 ──

  /// 明確重試入口（UI 重試按鈕 / MCP rescan 呼叫）。
  /// 清除所有熔斷狀態（root 冷卻 + 嵌入旗標）；是否真的重掃由呼叫端
  /// 再標 dirty 觸發（重試 = 允許下一輪跑，不是立刻自動跑）。
  void resetCircuits() {
    if (_openRoots.isEmpty && !_embedCircuitOpen) return;
    final roots = List<String>.from(_openRoots);
    _openRoots.clear();
    _embedCircuitOpen = false;
    final msg = '熔斷已重置：${roots.length} 個根目錄恢復巡邏，嵌入循環恢復';
    debugPrint('[CircuitBreaker] $msg');
    _emit(msg);
  }

  // ── 內部 ──

  void _emit(String msg) {
    if (!_events.isClosed) {
      _events.add(msg);
    }
  }

  /// [小葵 2026-10-31 熔斷器] 測試輔助：完全重置（含限額快取）。
  /// 只為測試隔離存在；正式流程一律走 resetCircuits()。
  @visibleForTesting
  void resetForTest() {
    _openRoots.clear();
    _embedCircuitOpen = false;
    _limits = defaultLimits;
    _limitsLoaded = false;
  }
}
