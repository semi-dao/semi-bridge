/// scrub_history_store.dart
/// [Blue 令 2026-10-17] 除痕歷史——什麼時候清了什麼、清了多大。
///
/// append-only JSONL（記憶鐵律同款：只加不刪），落地在 bridge_state/。
/// 手動一鍵除痕與背景自動除痕都記錄。
/// 每筆：{ts, trigger: manual|auto, files: n, bytes: n, items: [{label, bytes}]}
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ScrubHistoryEntry {
  final DateTime ts;
  final String trigger; // manual / auto
  final int files;
  final int bytes;
  final List<Map<String, dynamic>> items; // {label, bytes}

  ScrubHistoryEntry({
    required this.ts,
    required this.trigger,
    required this.files,
    required this.bytes,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'ts': ts.toIso8601String(),
        'trigger': trigger,
        'files': files,
        'bytes': bytes,
        'items': items,
      };
}

class ScrubHistoryStore {
  ScrubHistoryStore._();
  static final ScrubHistoryStore instance = ScrubHistoryStore._();

  File? _file;
  List<ScrubHistoryEntry>? _cache;

  Future<File> _resolve() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    final state = Directory('${dir.path}/bridge_state');
    if (!await state.exists()) await state.create(recursive: true);
    _file = File('${state.path}/scrub_history.jsonl');
    return _file!;
  }

  /// 記錄一次除痕（purge 成功後呼叫）
  Future<void> record({
    required String trigger,
    required int files,
    required int bytes,
    List<Map<String, dynamic>> items = const [],
  }) async {
    try {
      final f = await _resolve();
      final entry = ScrubHistoryEntry(
        ts: DateTime.now(),
        trigger: trigger,
        files: files,
        bytes: bytes,
        items: items,
      );
      await f.writeAsString('${jsonEncode(entry.toJson())}\n',
          mode: FileMode.append);
      _cache = null; // 快取失效
    } catch (e) {
      debugPrint('[ScrubHistory] 記錄失敗（fail-open，不擋除痕）: $e');
    }
  }

  /// 讀取歷史（新→舊）。limit 筆。
  Future<List<ScrubHistoryEntry>> load({int limit = 20}) async {
    if (_cache != null) return _cache!.take(limit).toList();
    try {
      final f = await _resolve();
      if (!await f.exists()) return _cache = [];
      final lines = (await f.readAsString())
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      final out = <ScrubHistoryEntry>[];
      for (final line in lines) {
        try {
          final m = jsonDecode(line) as Map<String, dynamic>;
          out.add(ScrubHistoryEntry(
            ts: DateTime.parse(m['ts'] as String),
            trigger: m['trigger'] as String? ?? '?',
            files: m['files'] as int? ?? 0,
            bytes: m['bytes'] as int? ?? 0,
            items: (m['items'] as List? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
          ));
        } catch (_) {}
      }
      // 新→舊
      out.sort((a, b) => b.ts.compareTo(a.ts));
      _cache = out;
      return out.take(limit).toList();
    } catch (e) {
      debugPrint('[ScrubHistory] 讀取失敗: $e');
      return [];
    }
  }
}
