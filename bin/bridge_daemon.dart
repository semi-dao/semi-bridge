// bridge_daemon.dart
// 橋樑 App 排程 Daemon — headless 排程引擎
//
// P2: 獨立於 Flutter App UI 運行的排程服務
// 由 launchd 託管，開機自動啟動
//
// 設計: 完全自包含，不 import lib/ 的 service 層
// （因為 MemoryStore → brain_database → sqlite3/sqlite_vector 有 native build hooks，
// 無法用 dart compile exe 編譯成獨立 binary）
//
// 排程邏輯從 schedule_engine.dart 抽出，daemon 自己實作觸發判斷
// App 端把 schedule 節點同步到 schedule_jobs.json，daemon 讀取並觸發
//
// 編譯: dart compile exe bin/bridge_daemon.dart -o bridge_daemon
// 安裝: cp bridge_daemon ~/Library/bridge_daemon
//        安裝 plist: ~/Library/LaunchAgents/farm.semiwasabi.bridgeDaemon.plist
//        launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/farm.semiwasabi.bridgeDaemon.plist
//
// 設計參考: Hermes gateway（launchd 託管 + cron scheduler + jobs.json）

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ═══════════════════════════════════════════════════════
//  排程觸發邏輯（從 schedule_engine.dart 抽出的純邏輯）
// ═══════════════════════════════════════════════════════

/// 判斷排程是否應該在 [now] 觸發
bool shouldFire(Map<String, dynamic> params, DateTime now) {
  final scheduleType = params['scheduleType']?.toString() ?? 'daily';
  final timeStr = params['time']?.toString() ?? '09:00';

  final timeParts = timeStr.split(':');
  if (timeParts.length != 2) return false;
  final hour = int.tryParse(timeParts[0]);
  final minute = int.tryParse(timeParts[1]);
  if (hour == null || minute == null) return false;

  switch (scheduleType) {
    case 'daily':
      return now.hour == hour && now.minute == minute;

    case 'weekly':
      final weekday = params['weekday'] as int? ?? 1;
      return now.weekday == weekday &&
          now.hour == hour &&
          now.minute == minute;

    case 'monthly':
      final dayOfMonth = params['dayOfMonth'] as int? ?? 1;
      return now.day == dayOfMonth &&
          now.hour == hour &&
          now.minute == minute;

    case 'once':
      final dateStr = params['date']?.toString() ?? '';
      if (dateStr.isEmpty) return false;
      final dp = dateStr.split('-');
      if (dp.length != 3) return false;
      final y = int.tryParse(dp[0]);
      final m = int.tryParse(dp[1]);
      final d = int.tryParse(dp[2]);
      if (y == null || m == null || d == null) return false;
      return now.year == y &&
          now.month == m &&
          now.day == d &&
          now.hour == hour &&
          now.minute == minute;

    case 'cron':
      final cronExpr = params['cronExpr']?.toString() ?? '';
      if (cronExpr.isEmpty) return false;
      return matchCron(cronExpr, now);

    default:
      return false;
  }
}

/// 簡易 cron 語法比對
bool matchCron(String expr, DateTime now) {
  final parts = expr.trim().split(RegExp(r'\s+'));
  if (parts.length != 5) return false;

  if (!_matchCronField(parts[0], now.minute, 0, 59)) return false;
  if (!_matchCronField(parts[1], now.hour, 0, 23)) return false;
  if (!_matchCronField(parts[2], now.day, 1, 31)) return false;
  if (!_matchCronField(parts[3], now.month, 1, 12)) return false;
  final cronWeekday = now.weekday == 7 ? 0 : now.weekday;
  if (!_matchCronField(parts[4], cronWeekday, 0, 7)) return false;

  return true;
}

bool _matchCronField(String field, int value, int min, int max) {
  if (field == '*') return true;
  if (field.contains(',')) {
    for (final part in field.split(',')) {
      if (_matchCronField(part, value, min, max)) return true;
    }
    return false;
  }
  if (field.startsWith('*/')) {
    final step = int.tryParse(field.substring(2));
    if (step == null || step == 0) return false;
    return (value - min) % step == 0;
  }
  if (field.contains('-')) {
    final range = field.split('-');
    if (range.length != 2) return false;
    final start = int.tryParse(range[0]);
    final end = int.tryParse(range[1]);
    if (start == null || end == null) return false;
    return value >= start && value <= end;
  }
  final num = int.tryParse(field);
  if (num == null) return false;
  return value == num;
}

bool _isSameMinute(DateTime a, DateTime b) {
  return a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;
}

// ═══════════════════════════════════════════════════════
//  排程作業定義
// ═══════════════════════════════════════════════════════

class ScheduleJob {
  final String id;
  final String title;
  final String canvasId;
  final Map<String, dynamic> params;

  const ScheduleJob({
    required this.id,
    required this.title,
    required this.canvasId,
    required this.params,
  });

  factory ScheduleJob.fromJson(Map<String, dynamic> json) {
    return ScheduleJob(
      id: json['id'] as String,
      title: json['title'] as String? ?? '未命名排程',
      canvasId: json['canvasId'] as String? ?? 'default',
      params: (json['params'] as Map<String, dynamic>?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

// ═══════════════════════════════════════════════════════
//  Daemon 配置
// ═══════════════════════════════════════════════════════

class DaemonConfig {
  final String jobsPath;
  final String logPath;
  final Duration scanInterval;

  const DaemonConfig({
    required this.jobsPath,
    required this.logPath,
    this.scanInterval = const Duration(seconds: 60),
  });

  factory DaemonConfig.defaultConfig() {
    final home = Platform.environment['HOME'] ?? '/tmp';
    final appSupport = '$home/Library/Application Support/farm.semiwasabi.bridgeApp';
    return DaemonConfig(
      jobsPath: '$appSupport/schedule_jobs.json',
      logPath: '$home/Library/Logs/bridge_daemon.log',
    );
  }
}

// ═══════════════════════════════════════════════════════
//  Daemon 主體
// ═══════════════════════════════════════════════════════

class BridgeDaemon {
  final DaemonConfig config;
  Timer? _scanTimer;
  Timer? _fileWatchTimer;
  Timer? _orphanHunterTimer; // [小葵 2026-09-16 Blue 令] 孤兒程序獵人
  List<ScheduleJob> _jobs = [];
  final Map<String, DateTime> _lastFiredMap = {};
  IOSink? _logSink;
  DateTime? _jobsFileMtime;

  BridgeDaemon({DaemonConfig? config})
      : config = config ?? DaemonConfig.defaultConfig();

  Future<void> start() async {
    await _initLogger();
    _log('=== Bridge Daemon 啟動 ===');
    _log('Jobs path: ${config.jobsPath}');
    _log('Log path: ${config.logPath}');
    _log('Scan interval: ${config.scanInterval.inSeconds}s');

    await _reloadJobs();

    // 立即掃描一次
    _scanAndFire();

    // 啟動定期 Timer
    _scanTimer = Timer.periodic(config.scanInterval, (_) => _scanAndFire());

    // [小葵 2026-09-16 Blue 令] 孤兒程序獵人——每 5 分鐘掃描，
    // 詳見 _huntOrphanProcesses()
    _orphanHunterTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _huntOrphanProcesses(),
    );

    // file watcher — 每 10 秒檢查 jobs.json 是否更新
    _fileWatchTimer = Timer.periodic(const Duration(seconds: 10), (_) => _reloadJobs());

    _log('Daemon 運行中，等待排程觸發...');

    await _waitForShutdown();
  }

  Future<void> stop() async {
    _log('Stopping daemon...');
    _scanTimer?.cancel();
    _fileWatchTimer?.cancel();
    _orphanHunterTimer?.cancel();
    await _logSink?.flush();
    await _logSink?.close();
  }

  /// [小葵 2026-09-16 Blue 令] 孤兒程序獵人
  /// 沒有活躍連線且閒置的重型常駐程序 → 自動關閉釋放記憶體。
  /// 病例：llama-server 佔 11GB 記憶體閒置 14 天無人關。
  final Map<String, int> _orphanIdleStrikes = {}; // pid → 連續閒置輪數

  Future<void> _huntOrphanProcesses() async {
    try {
      final r = await Process.run('/bin/sh', [
        '-c',
        "ps aux | grep 'llama-server' | grep -v grep | awk '{print \$2}'",
      ]);
      final pids = r.stdout
          .toString()
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      // [2026-09-28 修 v2] per-pid 動態檢查：
      // 1. 找出該 llama-server 進程「正在監聽的 port」（不再寫死 18789）
      // 2. 查有無任何進程連向這些 port（任何狀態——llama.cpp 的 HTTP 連線
      //    生命週期與請求綁定，server 側 lsof 常看不到 ESTABLISHED）
      // 教訓：12B bench 三死就是因為舊版寫死 18789，18790 永遠「無連線」被誤殺。
      Future<bool> hasActiveConnection(String pid) async {
        final listen = await Process.run('/bin/sh', [
          '-c',
          "lsof -nP -iTCP -sTCP:LISTEN -a -p $pid 2>/dev/null | awk '{print \$9}' | grep -oE '[0-9]+\$' | sort -u",
        ]);
        final ports = listen.stdout
            .toString()
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet();
        if (ports.isEmpty) return false; // 找不到監聽 port → 視為無連線
        // 用 Dart 端精確過濾取代 shell grep regex（避免 $ 插值衝突）：
        // lsof NAME 欄格式「127.0.0.1:52042->127.0.0.1:18789」或「*:18789」
        final allConn = await Process.run('/bin/sh', [
          '-c',
          'lsof -nP -iTCP 2>/dev/null',
        ]);
        final lines = allConn.stdout.toString().split('\n');
        for (final p in ports) {
          final suffix = ':$p';
          final hit = lines.any((l) {
            if (l.contains('LISTEN')) return false;
            // NAME 欄含 ->suffix 結尾（client → server）或 suffix-> 開頭（server 端）
            final idx = l.indexOf('->');
            return idx >= 0 &&
                (l.substring(idx).startsWith(suffix) ||
                    l.contains('$suffix->'));
          });
          if (hit) return true;
        }
        return false;
      }
      for (final pidStr in pids) {
        if (await hasActiveConnection(pidStr)) {
          // 有活躍連線 → 有人用 → 歸零
          _orphanIdleStrikes.remove(pidStr);
          continue;
        }
        final cpu = await Process.run('/bin/sh', [
          '-c',
          "ps -o cpu= -p $pidStr | tr -d ' '",
        ]);
        final cpuVal = double.tryParse(cpu.stdout.toString().trim()) ?? 100.0;
        if (cpuVal > 5.0) {
          _orphanIdleStrikes.remove(pidStr);
          continue;
        }
        final strikes = (_orphanIdleStrikes[pidStr] ?? 0) + 1;
        _orphanIdleStrikes[pidStr] = strikes;
        if (strikes >= 2) {
          await Process.run('kill', [pidStr]);
          _log('孤兒獵人：llama-server(pid $pidStr) 閒置 ${strikes * 5} 分鐘無連線，已關閉釋放記憶體');
          _orphanIdleStrikes.remove(pidStr);
        } else {
          _log('孤兒獵人：llama-server(pid $pidStr) 閒置中（$strikes/2 輪）');
        }
      }
      _orphanIdleStrikes.removeWhere((pid, _) => !pids.contains(pid));
    } catch (e) {
      _log('孤兒獵人錯誤（不影響排程）: $e');
    }
  }

  /// 重新載入排程定義
  Future<void> _reloadJobs() async {
    try {
      final file = File(config.jobsPath);
      if (!await file.exists()) {
        if (_jobs.isNotEmpty) {
          _log('Jobs file removed, clearing ${_jobs.length} jobs');
          _jobs = [];
          _jobsFileMtime = null;
        }
        return;
      }

      final stat = await file.stat();
      if (_jobsFileMtime != null && !stat.modified.isAfter(_jobsFileMtime!)) {
        return; // 沒更新
      }
      _jobsFileMtime = stat.modified;

      final content = await file.readAsString();
      if (content.trim().isEmpty) return;

      final data = jsonDecode(content) as Map<String, dynamic>;
      final jobsList = (data['jobs'] as List?) ?? [];
      final newJobs = jobsList
          .map((j) => ScheduleJob.fromJson(j as Map<String, dynamic>))
          .toList();

      if (newJobs.length != _jobs.length) {
        _log('Jobs updated: ${_jobs.length} → ${newJobs.length} jobs');
      }
      _jobs = newJobs;
    } catch (e) {
      _log('Error reloading jobs: $e');
    }
  }

  /// 主掃描迴圈
  void _scanAndFire() {
    final now = DateTime.now();
    for (final job in _jobs) {
      if (!shouldFire(job.params, now)) continue;

      // 防重複
      final lastFired = _lastFiredMap[job.id];
      if (lastFired != null && _isSameMinute(lastFired, now)) continue;

      _lastFiredMap[job.id] = now;
      _log('觸發排程: ${job.title} (${job.id}) at $now');

      // 觸發執行（非阻塞）
      _executeJob(job).catchError((e) {
        _log('執行失敗 (${job.id}): $e');
      });
    }
  }

  /// 執行排程作業
  ///
  /// P2 初期：記錄觸發事件，寫入 trigger log
  /// P3：透過 IPC（WebSocket / HTTP）通知 App 執行 DAG
  /// P4：daemon 自己呼叫 LLM API 執行節點
  Future<void> _executeJob(ScheduleJob job) async {
    _log('排程觸發: ${job.title} (canvas: ${job.canvasId})');
    _log('Params: ${jsonEncode(job.params)}');

    // 寫入 trigger log（給 App 讀取）
    final home = Platform.environment['HOME'] ?? '/tmp';
    final appSupport = '$home/Library/Application Support/farm.semiwasabi.bridgeApp';
    final triggerLog = File('$appSupport/schedule_triggers.jsonl');
    try {
      final entry = jsonEncode({
        'jobId': job.id,
        'title': job.title,
        'canvasId': job.canvasId,
        'firedAt': DateTime.now().toIso8601String(),
      });
      await triggerLog.parent.create(recursive: true);
      await triggerLog.writeAsString('$entry\n', mode: FileMode.append);
      _log('Trigger logged to ${triggerLog.path}');
    } catch (e) {
      _log('Failed to write trigger log: $e');
    }
  }

  void _log(String msg) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] $msg';
    print(line);
    _logSink?.writeln(line);
  }

  Future<void> _initLogger() async {
    try {
      final logFile = File(config.logPath);
      final logDir = logFile.parent;
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _logSink = logFile.openWrite(mode: FileMode.append);
    } catch (e) {
      stderr.writeln('Failed to init logger: $e');
    }
  }

  Future<void> _waitForShutdown() async {
    final completer = Completer<void>();

    ProcessSignal.sigterm.watch().listen((_) {
      _log('Received SIGTERM');
      completer.complete();
    });
    ProcessSignal.sigint.watch().listen((_) {
      _log('Received SIGINT');
      completer.complete();
    });

    await completer.future;
    await stop();
  }
}

// ═══════════════════════════════════════════════════════
//  Entry point
// ═══════════════════════════════════════════════════════

Future<void> main(List<String> args) async {
  // 解析命令列參數
  var config = DaemonConfig.defaultConfig();
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--jobs' && i + 1 < args.length) {
      config = DaemonConfig(
        jobsPath: args[i + 1],
        logPath: config.logPath,
        scanInterval: config.scanInterval,
      );
    } else if (args[i] == '--interval' && i + 1 < args.length) {
      final seconds = int.tryParse(args[i + 1]);
      if (seconds != null) {
        config = DaemonConfig(
          jobsPath: config.jobsPath,
          logPath: config.logPath,
          scanInterval: Duration(seconds: seconds),
        );
      }
    } else if (args[i] == '--help' || args[i] == '-h') {
      print('橋樑排程 Daemon');
      print('');
      print('用法: bridge_daemon [--jobs <path>] [--interval <seconds>]');
      print('');
      print('選項:');
      print('  --jobs <path>      排程定義檔路徑（預設: ~/Library/Application Support/farm.semiwasabi.bridgeApp/schedule_jobs.json）');
      print('  --interval <sec>   掃描間隔秒數（預設: 60）');
      print('  --help             顯示說明');
      exit(0);
    }
  }

  final daemon = BridgeDaemon(config: config);
  try {
    await daemon.start();
  } catch (e, stack) {
    stderr.writeln('Fatal error: $e\n$stack');
    await daemon.stop();
    exit(1);
  }
}
