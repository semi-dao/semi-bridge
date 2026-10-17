// trace_scrubber.dart
// [資料主權 P1 2026-09-14] 自動/一鍵除痕服務——刪除「外傳暫存」，
// 對話本體、記憶、資料、向量庫一律不動。
// 提案：docs/specs/2026-09-14-data-sovereignty-design.md §4.3（v1.3 定案）
//
// 09-14 Blue 拍板：
// - 自動除痕預設啟用、每天一次、閒置時執行、設定可關
// - 年齡門檻制（非時間窗）：刪除「存在超過 2 小時」的所有暫存——
//   昨天以降全部都清；最近 2 小時的（可能使用中）最晚下一輪被清
// - 最壞殘留 ≤ 2 小時的量，且 24 小時內必清
//
// 除痕 ≠ 刪除（鐵則）：
// - 只清可再生暫存：截幀、送出 prompt 暫存、縮圖快取、行為日誌
// - 不碰：對話、記憶、asset_index、向量庫、使用者檔案
// - 破壞性操作權力在使用者：一鍵除痕走 dry-run 預覽 → 確認 → 真刪
//   （自動除痕 = 預先同意的同一邏輯，範圍相同）
//
// 護欄：pipeline 忙碌時跳過本輪（截幀可能正被 vision pipeline 使用）。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'scrub_history_store.dart'; // [Blue 令 2026-10-17] 除痕歷史

import '../vector_db/vision_embedding_pipeline.dart';

/// 外傳暫存的清掃目標定義——「可再生」是收錄條件（刪掉不傷任何功能）
class _TraceTarget {
  final String dir; // 目錄（遞迴）或空
  final Pattern pattern; // 檔名 glob
  final String label; // 給使用者看的人話
  const _TraceTarget(this.dir, this.pattern, this.label);
}

const List<_TraceTarget> _kTargets = [
  // 影片截幀（frame_extract_tool 輸出，曾以 base64 整份送雲端）
  _TraceTarget('/tmp', 'frame_*.jpg', '影片截幀暫存'),
  _TraceTarget('/tmp', 'xiaoqiao_frame*.jpg', '影片截幀暫存'),
  // 送出的 vision prompt 暫存
  _TraceTarget('/tmp', 'vision_prompt*.txt', '影像分析提示暫存'),
  // 星系縮圖快取（照片縮圖）
  _TraceTarget('/tmp/galaxy_thumbs', '*', '縮圖快取'),
  // 行為殘留日誌（oplog/心跳——狀態注入取代累積的鐵則清理）
  _TraceTarget('/tmp', 'galaxy_oplog_*.json', '行為紀錄殘留'),
];

class TraceScrubber {
  TraceScrubber._();
  static final TraceScrubber instance = TraceScrubber._();

  static const _autoKey = 'sovereignty.autoScrub.enabled';
  static const _lastRunKey = 'sovereignty.autoScrub.lastRun';
  static const _threshold = Duration(hours: 2); // 09-14 Blue 令：1hr→2hr
  static const _minInterval = Duration(hours: 24);

  Timer? _timer;

  /// 掃描符合條件的檔案（不刪）——dry-run 與自動模式共用。
  /// 回傳 (label, path, size, mtime) 清單。
  Future<List<TraceItem>> scan({Duration? ageThreshold}) async {
    final threshold = ageThreshold ?? _threshold;
    final now = DateTime.now();
    final items = <TraceItem>[];
    for (final t in _kTargets) {
      final dir = Directory(t.dir);
      if (!await dir.exists()) continue;
      await for (final e in dir.list(recursive: false)) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!_globMatch(name, t.pattern)) continue;
        // bridge_ui_crash.log 等系統日誌不在此列（glob 不含）
        final stat = await e.stat();
        final age = now.difference(stat.modified);
        if (age > threshold) {
          items.add(TraceItem(
            label: t.label,
            path: e.path,
            bytes: stat.size,
            modified: stat.modified,
          ));
        }
      }
    }
    return items;
  }

  /// 真刪。回傳刪除的位元組數。（呼叫端負責先給使用者看 dry-run 結果）
  Future<int> purge(List<TraceItem> items) async {
    var freed = 0;
    for (final item in items) {
      try {
        final f = File(item.path);
        if (await f.exists()) {
          await f.delete();
          freed += item.bytes;
        }
      } catch (e) {
        debugPrint('[TraceScrubber] 刪除失敗 ${item.path}: $e');
      }
    }
    return freed;
  }

  // ─────────────────────────────────────────────
  // 自動模式：每天一次、閒置時執行（預設啟用）
  // ─────────────────────────────────────────────

  Future<bool> get autoEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoKey) ?? true; // 09-14 Blue 拍板：預設啟用
  }

  Future<void> setAutoEnabled(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoKey, on);
    if (on) {
      await runAutoIfDue();
    }
  }

  /// App 啟動時呼——排入週期檢查（每 30 分鐘看是否到期＋閒置）
  Future<void> start() async {
    _timer?.cancel();
    if (!await autoEnabled) return;
    _timer = Timer.periodic(const Duration(minutes: 30), (_) {
      runAutoIfDue();
    });
    await runAutoIfDue();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<DateTime?> get lastAutoRun async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_lastRunKey);
    return v == null ? null : DateTime.tryParse(v);
  }

  /// 到期（距上次 ≥24h）且 vision pipeline 閒置才跑；否則靜靜跳過。
  Future<void> runAutoIfDue() async {
    if (!await autoEnabled) return;
    final last = await lastAutoRun;
    final now = DateTime.now();
    if (last != null && now.difference(last) < _minInterval) return;
    if (VisionEmbeddingPipeline.instance.isRunning) {
      debugPrint('[TraceScrubber] vision pipeline 忙碌，本輪跳過');
      return;
    }
    final items = await scan();
    final freed = await purge(items);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastRunKey, now.toIso8601String());
    debugPrint('[TraceScrubber] 自動除痕：清了 ${items.length} 檔 / '
        '${(freed / 1024).toStringAsFixed(0)}KB');
    // [Blue 令 2026-10-17] 除痕歷史——什麼時候清了什麼、清了多大
    if (items.isNotEmpty) {
      await ScrubHistoryStore.instance.record(
        trigger: 'auto',
        files: items.length,
        bytes: freed,
        items: [
          for (final it in items)
            {'label': it.label, 'bytes': it.bytes},
        ],
      );
    }
  }

  bool _globMatch(String name, Pattern p) {
    if (p == '*') return true;
    final s = p.toString();
    // [09-14 測試抓包] 中間星號（frame_*.jpg）也要支援：
    // 拆成 prefix/suffix 兩段字面量比對。
    final star = s.indexOf('*');
    if (star == -1) return name == s;
    final prefix = s.substring(0, star);
    final suffix = s.substring(star + 1);
    return name.length >= prefix.length + suffix.length &&
        name.startsWith(prefix) &&
        name.endsWith(suffix);
  }
}

class TraceItem {
  final String label;
  final String path;
  final int bytes;
  final DateTime modified;
  const TraceItem({
    required this.label,
    required this.path,
    required this.bytes,
    required this.modified,
  });
}
