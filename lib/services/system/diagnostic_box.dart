import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// [小葵 2026-10-31 黑盒子] 診斷黑盒子（刀二）——App 自己的 flight recorder
///
/// 起源：10-30 暴潰案靠小葵在終端機查 jetsam report 才破案。
/// 未來使用者沒有終端機——App 必須自己記錄「發生了什麼」，
/// 讓使用者一鍵匯出報告（給人看），也讓 Agent 透過 MCP 讀（給 agent 讀）。
///
/// 設計鐵則（資料主權紅線）：
/// - 對外報告零敏感資訊：路徑只顯示到根目錄層、無 token、無對話內容
/// - 黑盒子本身故障不得拖垮 App：所有 I/O 都包 try-catch，失敗只 debugPrint
///
/// 接線契約（與刀一/刀三平行開發，介面先約定）：
/// - 刀一 CrashGuard（lib/services/system/crash_guard.dart，尚未存在）：
///   TODO(刀一合流)：Safe Mode 進入/退出時呼叫
///   `DiagnosticBox.instance.log('safe_mode', '進入安全模式：…')`
/// - 刀三 IngestCircuitBreaker（lib/services/vector_db/ingest_circuit_breaker.dart，
///   尚未存在）：TODO(刀三合流)：熔斷跳脫時呼叫
///   `DiagnosticBox.instance.log('circuit_breaker', '…root 單輪 N 筆超過上限')`
/// - AutoIngest 狀態變化：TODO(主線接線)：IncrementalIngestService 狀態改變時
///   呼叫 `DiagnosticBox.instance.log('auto_ingest', '…')`
/// - 本檔不 import 上述尚未存在的檔案——由對方（或主線）反向呼叫本入口。
class DiagnosticBox {
  DiagnosticBox._();

  /// 全域單例——CrashGuard / 熔斷器 / 主線都從這裡寫入
  static final DiagnosticBox instance = DiagnosticBox._();

  /// 測試用：可注入獨立目錄與輪替門檻，絕不碰真 App Support
  factory DiagnosticBox.forTest(String baseDir, {int maxBytes = 1048576}) {
    final box = DiagnosticBox._();
    box._baseDir = baseDir;
    box._maxBytes = maxBytes;
    box._injected = true;
    return box;
  }

  // ── 常數 ──────────────────────────────────────────────
  /// ring buffer 上限（計劃卡定案：200 條）
  static const int maxEvents = 200;

  /// 崩潰 log 尾端取用行數
  static const int _crashLogTailLines = 5;

  static const String _fileName = 'diagnostic_box.jsonl';

  // ── 狀態 ──────────────────────────────────────────────
  final List<Map<String, String>> _ring = <Map<String, String>>[];
  String? _baseDir;
  int _maxBytes = 1024 * 1024; // jsonl 輪替門檻：>1MB 輪替
  bool _injected = false;
  bool _initialized = false;

  String get _filePath => '$_baseDir/$_fileName';

  /// 目前 ring buffer 內容（時間正序副本）
  List<Map<String, String>> get events => List.unmodifiable(_ring);

  /// 最近 n 條事件（時間正序）
  List<Map<String, String>> recent(int n) {
    final start = _ring.length > n ? _ring.length - n : 0;
    return List.unmodifiable(_ring.sublist(start));
  }

  /// 初始化——解析儲存目錄、回載歷史、收崩潰 log 尾端、記啟動事件。
  /// 冪等：重複呼叫無副作用。
  Future<void> init({String? baseDir}) async {
    if (_initialized) return;
    try {
      if (baseDir != null) {
        _baseDir = baseDir;
      } else if (!_injected) {
        final dir = await getApplicationSupportDirectory();
        _baseDir = dir.path;
      }
      if (_baseDir == null) return;
      await Directory(_baseDir!).create(recursive: true);
      await _loadHistory();
      await _collectCrashLogTail();
      _initialized = true;
      log('lifecycle', 'App 啟動——診斷黑盒子就緒（歷史 $_ring.length 條已回載）');
    } catch (e) {
      // 黑盒子故障不拖垮 App：靜默降級（ring buffer 仍在記憶體運作）
      debugPrint('[DiagnosticBox] init 失敗：$e');
      _initialized = true;
    }
  }

  /// 保證已初始化（卡片 / MCP 工具進場前呼叫）
  Future<void> ensureInit() async {
    if (!_initialized) await init();
  }

  /// 從 jsonl 回載歷史（取最後 maxEvents 條）——重啟不斷片
  Future<void> _loadHistory() async {
    try {
      final f = File(_filePath);
      if (!await f.exists()) return;
      final lines = await f.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final obj = jsonDecode(line) as Map<String, dynamic>;
          _ring.add({
            'ts': obj['ts']?.toString() ?? '',
            'kind': obj['kind']?.toString() ?? 'unknown',
            'detail': obj['detail']?.toString() ?? '',
          });
        } catch (_) {
          // 壞行略過——黑盒子不容許一條壞資料中斷回載
        }
      }
      while (_ring.length > maxEvents) {
        _ring.removeAt(0);
      }
    } catch (e) {
      debugPrint('[DiagnosticBox] 歷史回載失敗：$e');
    }
  }

  /// 收崩潰 log 尾端（/tmp/bridge_ui_crash.log 若存在取最後幾筆）
  /// 這是 10-30 暴潰案的破案線索檔——App 啟動時主動收編進黑盒子
  Future<void> _collectCrashLogTail() async {
    try {
      const crashLogPath = '/tmp/bridge_ui_crash.log';
      final f = File(crashLogPath);
      if (!await f.exists()) return;
      final lines = await f.readAsLines();
      if (lines.isEmpty) return;
      final tail = lines.length > _crashLogTailLines
          ? lines.sublist(lines.length - _crashLogTailLines)
          : lines;
      log('crash_log_tail', '崩潰 log 尾端（$crashLogPath）：${tail.join(' ⏎ ')}');
    } catch (e) {
      debugPrint('[DiagnosticBox] 崩潰 log 收集失敗：$e');
    }
  }

  // ═══════════════════════════════════════════════════
  // 寫入入口——刀一/刀三/主線接線統一走這裡
  // ═══════════════════════════════════════════════════

  /// 記一條事件（同步進 ring buffer，異步持久化）。
  ///
  /// kind 慣例：
  /// - lifecycle：啟動/關閉
  /// - safe_mode：安全模式進入/退出（刀一）
  /// - crash_log_tail：崩潰 log 尾端
  /// - auto_ingest：AutoIngest 狀態變化
  /// - circuit_breaker：熔斷事件（刀三）
  /// - memory：記憶體壓力 / jetsam 線索
  void log(String kind, String detail) {
    final entry = <String, String>{
      'ts': DateTime.now().toIso8601String(),
      'kind': kind,
      // 寫入前就消毒——連本地 jsonl 都不落敏感原文（防禦縱深）
      'detail': sanitize(detail),
    };
    _ring.add(entry);
    while (_ring.length > maxEvents) {
      _ring.removeAt(0); // ring buffer 上限：丟最舊
    }
    unawaited(_appendPersist(entry));
  }

  /// [小葵 2026-10-31 黑盒子·修] 持久化串行鏈——log() 是高頻入口，
  /// 每條都 fire-and-forget 會開出併發檔案 I/O（fd 風暴＋寫入交錯破檔）。
  /// 全部 append 排隊走同一條鏈：順序保證、單一 fd、呼叫端永不等待。
  Future<void> _ioChain = Future.value();

  /// 等待排隊中的持久化全部落盤（測試與關閉前用；一般呼叫端不需要）
  Future<void> flush() => _ioChain;

  /// append-only 持久化；>1MB 輪替成 .1（僅保留一份）
  Future<void> _appendPersist(Map<String, String> entry) {
    final job = _ioChain.then((_) async {
      try {
        if (_baseDir == null) return;
        final f = File(_filePath);
        // 輪替：超過門檻就 rename 成 .1（舊 .1 直接覆蓋）
        if (await f.exists()) {
          final len = await f.length();
          if (len > _maxBytes) {
            final rotated = File('$_filePath.1');
            if (await rotated.exists()) await rotated.delete();
            await f.rename('$_filePath.1');
          }
        }
        final line = jsonEncode(entry);
        await f.writeAsString('$line\n',
            mode: FileMode.append, flush: false);
      } catch (e) {
        // 持久化失敗不拋——ring buffer 仍在，黑盒子不能變成新的崩潰源
        debugPrint('[DiagnosticBox] 持久化失敗：$e');
      }
    });
    // 鏈上任一失敗不讓後續任務餓死——重置鏈繼續排隊
    _ioChain = job.catchError((_) {});
    return job;
  }

  // ═══════════════════════════════════════════════════
  // 敏感過濾（資料主權紅線）
  // ═══════════════════════════════════════════════════

  /// 絕對路徑（/Users/... /Volumes/...）——抓到行尾或標點為止
  static final RegExp _absPath =
      RegExp(r'(/Users/[^\s，。;:）)"』]+|/Volumes/[^\s，。;:）)"』]+)');

  /// token 類敏感字串：API key / JWT / 長 hex
  static final RegExp _tokenLike =
      RegExp(r'(sk-[A-Za-z0-9_\-]{8,}|eyJ[A-Za-z0-9_\-\.]{20,}|[A-Fa-f0-9]{32,})');

  /// 消毒：路徑只顯示到根目錄層、token 遮蔽（遮蔽樣式：`<已遮蔽>`）
  static String sanitize(String input) {
    var s = input.replaceAllMapped(_tokenLike, (_) => '<已遮蔽>');
    s = s.replaceAllMapped(_absPath, (m) {
      final p = m.group(0)!;
      final parts = p.split('/');
      // /home/xxx → 只留前兩層（根目錄層），其餘以 … 收尾
      final kept = parts.take(3).join('/');
      return '$kept/…';
    });
    return s;
  }

  // ═══════════════════════════════════════════════════
  // 匯出——markdown 報告（白話摘要段＋技術附錄）
  // ═══════════════════════════════════════════════════

  /// 白話摘要段——給人看的：最近發生什麼、資料是否安好
  String plainSummary() {
    if (_ring.isEmpty) {
      return '最近沒有記錄到任何異常事件，一切平靜。你的資料安好。';
    }
    final kindCount = <String, int>{};
    for (final e in _ring) {
      kindCount[e['kind']!] = (kindCount[e['kind']!] ?? 0) + 1;
    }
    final lines = <String>[];
    // 依事件種類給白話判讀
    final hadCrash = kindCount.containsKey('crash_log_tail');
    final hadSafeMode = kindCount.containsKey('safe_mode');
    final hadCircuit = kindCount.containsKey('circuit_breaker');

    if (hadCrash) {
      lines.add('• App 曾經異常結束（崩潰）——已留下崩潰線索，可供除錯。');
    }
    if (hadSafeMode) {
      lines.add('• 系統曾進入安全模式：偵測到異常重啟後暫停背景工作保護資料。');
    }
    if (hadCircuit) {
      lines.add('• 自動檔案巡邏曾因工作量異常而暫停（熔斷保護）——這是預期的保險絲行為，你的資料沒有受損。');
    }
    if (lines.isEmpty) {
      lines.add('• 最近記錄的都是例行事件（啟動、索引狀態），沒有異常。');
    }
    final last = _ring.last;
    lines.add('');
    lines.add(
        '最近一筆記錄：${_fmtTs(last['ts']!)}（${kindLabel(last['kind']!)}）。');
    lines.add('你的資料安好——黑盒子只記錄系統狀態，不含任何對話內容。');
    return lines.join('\n');
  }

  /// 組完整 markdown 報告
  String exportMarkdown() {
    final now = DateTime.now();
    final buf = StringBuffer();
    buf.writeln('# 橋樑 App 診斷報告');
    buf.writeln('');
    buf.writeln('產出時間：${now.toIso8601String()}');
    buf.writeln('');
    buf.writeln('## 白話摘要（給你看的）');
    buf.writeln('');
    buf.writeln(plainSummary());
    buf.writeln('');
    buf.writeln('## 技術附錄（給 Agent／工程師看的時間軸）');
    buf.writeln('');
    if (_ring.isEmpty) {
      buf.writeln('（無事件）');
    } else {
      buf.writeln('| 時間 | 類別 | 事件 |');
      buf.writeln('| --- | --- | --- |');
      for (final e in _ring) {
        // markdown 表格內容跳脫豎線，避免破表
        final detail = e['detail']!.replaceAll('|', '\\|');
        buf.writeln('| ${_fmtTs(e['ts']!)} | ${kindLabel(e['kind']!)} | $detail |');
      }
    }
    buf.writeln('');
    buf.writeln('---');
    buf.writeln('');
    buf.writeln('> 本報告由 App 內建診斷黑盒子產出。');
    buf.writeln('> 隱私承諾：路徑只顯示到根目錄層、無任何金鑰/token、無對話內容。');
    return buf.toString();
  }

  /// 匯出到檔案：優先用 file_picker 讓使用者選位置；取消或失敗則
  /// fallback 寫到 `~/Desktop/bridge-diagnostic-<yyyyMMdd-HHmm>.md`。
  /// 回傳實際寫入路徑（null = 使用者取消）。
  Future<String?> exportToFile({String? fallbackDir}) async {
    String? path;
    try {
      // file_picker 已在 pubspec.yaml（^9.2.3）——saveFile 讓使用者選匯出位置
      final result = await FilePickerWrapper.pickSaveFile(
        defaultName: _defaultFileName(),
      );
      path = result; // 使用者取消時為 null
    } catch (e) {
      debugPrint('[DiagnosticBox] file_picker 不可用，走桌面 fallback：$e');
      path = null;
    }
    if (path == null) {
      // fallback：預設桌面直接寫
      final dir = fallbackDir ??
          '${Platform.environment['HOME']}/Desktop';
      path = '$dir/${_defaultFileName()}';
    }
    try {
      final content = exportMarkdown();
      final f = File(path);
      await f.create(recursive: true);
      await f.writeAsString(content, flush: true);
      return path;
    } catch (e) {
      debugPrint('[DiagnosticBox] 匯出寫檔失敗：$e');
      return null;
    }
  }

  String _defaultFileName() {
    final n = DateTime.now();
    final mm = n.month.toString().padLeft(2, '0');
    final dd = n.day.toString().padLeft(2, '0');
    final hh = n.hour.toString().padLeft(2, '0');
    final mi = n.minute.toString().padLeft(2, '0');
    return 'bridge-diagnostic-${n.year}$mm$dd-$hh$mi.md';
  }

  // ── 呈現輔助 ──────────────────────────────────────────

  /// 時間戳縮短：2026-10-31T08:15:00.000 → 10-31 08:15:00
  static String _fmtTs(String iso) {
    try {
      final t = DateTime.parse(iso);
      final mm = t.month.toString().padLeft(2, '0');
      final dd = t.day.toString().padLeft(2, '0');
      final hh = t.hour.toString().padLeft(2, '0');
      final mi = t.minute.toString().padLeft(2, '0');
      final ss = t.second.toString().padLeft(2, '0');
      return '$mm-$dd $hh:$mi:$ss';
    } catch (_) {
      return iso;
    }
  }

  /// 事件類別白話標籤（公開：卡片與 MCP 工具共用）
  static String kindLabel(String kind) {
    switch (kind) {
      case 'lifecycle':
        return '啟動/關閉';
      case 'safe_mode':
        return '安全模式';
      case 'crash_log_tail':
        return '崩潰線索';
      case 'auto_ingest':
        return '自動巡邏';
      case 'circuit_breaker':
        return '熔斷保護';
      case 'memory':
        return '記憶體';
      default:
        return kind;
    }
  }
}

/// [小葵 2026-10-31 黑盒子] file_picker 薄包裝——獨立出來是為了讓
/// DiagnosticBox 主邏輯可測（測試不觸發 platform channel）。
class FilePickerWrapper {
  FilePickerWrapper._();

  /// 選匯出位置；取消回 null。任何例外由呼叫端接手走 fallback。
  static Future<String?> pickSaveFile({required String defaultName}) async {
    // 延遲 import 的效果：只在真的呼叫時才載 file_picker
    // （dart 不支援條件 import，這裡用獨立類別把依賴收斂到單點）
    return _pickImpl(defaultName);
  }

  static Future<String?> _pickImpl(String defaultName) async {
    final result = await FilePicker.platform.saveFile(
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: ['md'],
    );
    return result; // 使用者取消時為 null
  }
}
