// schedule_run_store.dart
// [W2 2026-10-08 小葵·第二刀 UX] 排程執行落盤 + 產出記錄歸位
//
// 規格：docs/SCHEDULE_UX_DESIGN_SECOND_CUT.md §四-3/四-4
// - schedule_runs.jsonl：每次排程執行一筆 {jobId, firedAt, success,
//   outputType, outputPaths[], summary}——排隊卡「上次 ✓ 摘要 3.2KB」
//   與 W4 歷史時間線的資料源
// - daemon 的 schedule_triggers.jsonl 保留（它記「觸發」；本 store 記「執行結果」）
//
// ⚠️ 位置主權鐵則（Blue 令 2026-10-08：「檔案位置是原本的檔案位置，不要變」）：
// - 本 store 只「記錄」產出檔案的路徑，不搬移、不重定向、不複製任何既有檔案
// - 排程執行時產出寫到工作流 output 節點定義的原位置（bridge_media 等）
// - schedule_outputs/<jobId>/ 只給「從零新建、output 節點沒有指定位置」的排程
// - 既有任務的既有位置 = 主權，H6 移轉時才由使用者逐案決定

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 單次排程執行紀錄
class ScheduleRunRecord {
  final String jobId;
  final String jobTitle;
  final String canvasId;
  final DateTime firedAt;
  final bool success;

  /// 執行耗時
  final Duration duration;

  /// 產出類型摘要（voice / image / document / text …）
  final String? outputType;

  /// 產出檔案路徑（原位置如實記錄——見檔頭「位置主權鐵則」）
  final List<String> outputPaths;

  /// 人類可讀摘要（排隊卡「上次 ✓ 摘要 3.2KB」那行）
  final String? summary;

  /// 失敗原因（success=false 時）
  final String? error;

  const ScheduleRunRecord({
    required this.jobId,
    required this.jobTitle,
    required this.canvasId,
    required this.firedAt,
    required this.success,
    this.duration = Duration.zero,
    this.outputType,
    this.outputPaths = const [],
    this.summary,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'jobTitle': jobTitle,
        'canvasId': canvasId,
        'firedAt': firedAt.toIso8601String(),
        'success': success,
        'durationMs': duration.inMilliseconds,
        'outputType': outputType,
        'outputPaths': outputPaths,
        'summary': summary,
        'error': error,
      };

  factory ScheduleRunRecord.fromJson(Map<String, dynamic> m) =>
      ScheduleRunRecord(
        jobId: m['jobId'] as String? ?? '',
        jobTitle: m['jobTitle'] as String? ?? '',
        canvasId: m['canvasId'] as String? ?? '',
        firedAt: DateTime.tryParse(m['firedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        success: m['success'] as bool? ?? false,
        duration: Duration(
            milliseconds: (m['durationMs'] as num?)?.toInt() ?? 0),
        outputType: m['outputType'] as String?,
        outputPaths: (m['outputPaths'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        summary: m['summary'] as String?,
        error: m['error'] as String?,
      );
}

/// 排程執行紀錄 store — jsonl append-only。
///
/// 檔案位置：Application Support/farm.semiwasabi.bridgeApp/schedule_runs.jsonl
/// （與 schedule_triggers.jsonl 同目錄——App 沙箱根）
class ScheduleRunStore {
  ScheduleRunStore._();
  static final ScheduleRunStore instance = ScheduleRunStore._();

  File? _file;

  Future<File> _ensureFile() async {
    final existing = _file;
    if (existing != null) return existing;
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/schedule_runs.jsonl');
    if (!await f.exists()) {
      await f.create(recursive: true);
    }
    return _file = f;
  }

  /// 寫入一筆執行紀錄（append；失敗只記 log 不拋——落盤不能炸引擎）
  Future<void> append(ScheduleRunRecord record) async {
    try {
      final f = await _ensureFile();
      await f.writeAsString('${jsonEncode(record.toJson())}\n',
          mode: FileMode.append);
    } catch (e) {
      debugPrint('[ScheduleRunStore] 落盤失敗（不影響引擎）: $e');
    }
  }

  /// 指定 job 的最近一筆紀錄（排隊卡「上次」行）
  Future<ScheduleRunRecord?> lastRunOf(String jobId) async {
    final all = await runsOf(jobId);
    return all.isEmpty ? null : all.last;
  }

  /// 指定 job 的所有紀錄（新→舊；W4 歷史時間線）
  Future<List<ScheduleRunRecord>> runsOf(String jobId) async {
    final all = await allRuns();
    return all.where((r) => r.jobId == jobId).toList();
  }

  /// 全部紀錄（舊→新）
  Future<List<ScheduleRunRecord>> allRuns() async {
    try {
      final f = await _ensureFile();
      if (!await f.exists()) return const [];
      final lines = await f.readAsLines();
      return lines
          .where((l) => l.trim().isNotEmpty)
          .map((l) {
            try {
              return ScheduleRunRecord.fromJson(
                  jsonDecode(l) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<ScheduleRunRecord>()
          .toList();
    } catch (e) {
      debugPrint('[ScheduleRunStore] 讀取失敗: $e');
      return const [];
    }
  }
}

/// [W2] 產出記錄歸位 — 從執行結果萃取產出檔案路徑與摘要。
///
/// 位置主權鐵則：這裡只「解析＆記錄」，產出檔案在哪就在哪（bridge_media、
/// 工作流定義的輸出位置）。不搬不移。新任務未指定位置時才建
/// `schedule_outputs/<jobId>/`。
class ScheduleOutputResolver {
  static final RegExp _audioRe =
      RegExp(r'(?:/[\w./-]+|https?://[^\s"]+)\.(?:aiff|mp3|wav|m4a|mp4)');
  static final RegExp _imageRe =
      RegExp(r'(?:/[\w./-]+|https?://[^\s"]+)\.(?:png|jpg|jpeg|webp|gif)');
  static final RegExp _docRe =
      RegExp(r'(?:/[\w./-]+|https?://[^\s"]+)\.(?:md|txt|pdf|docx)');

  /// 從節點執行結果萃取：產出類型、檔案路徑清單、人類可讀摘要
  static ({String? type, List<String> paths, String? summary}) resolve(
      List<NodeExecutionResultLite> results) {
    final paths = <String>[];
    String? type;

    for (final r in results) {
      final out = r.output ?? '';
      for (final re in [_audioRe, _imageRe, _docRe]) {
        for (final m in re.allMatches(out)) {
          final p = m.group(0)!;
          if (p.startsWith('/') || p.startsWith('http')) paths.add(p);
        }
      }
      if (type == null) {
        if (_audioRe.hasMatch(out)) {
          type = 'voice';
        } else if (_imageRe.hasMatch(out)) {
          type = 'image';
        } else if (_docRe.hasMatch(out)) {
          type = 'document';
        }
      }
    }

    String? summary;
    if (type == 'voice') {
      summary = '語音';
    } else if (type == 'image') {
      summary = '圖片';
    } else if (type == 'document') {
      summary = '文件';
    }
    return (type: type, paths: paths.toSet().toList(), summary: summary);
  }
}

/// NodeExecutionResult 的輕量投影（解耦：store 不 import workflow_executor）
class NodeExecutionResultLite {
  final String nodeId;
  final bool success;
  final String? output;
  const NodeExecutionResultLite(
      {required this.nodeId, required this.success, this.output});
}
