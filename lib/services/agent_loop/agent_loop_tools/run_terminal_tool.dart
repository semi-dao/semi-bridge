// run_terminal_tool.dart
// [Phase 1 2026-07-17] 原生 Agent 自維修工具 #3：執行終端指令
//
// 讓 Agent 能在專案目錄下執行終端指令（dart analyze, flutter build, grep 等）。
// 安全限制：
// - 工作目錄固定為專案根目錄
// - 白名單指令：dart, flutter, grep, find, cat, ls, wc, git status, git diff
// - 超時 120 秒
// - 回傳 stdout + stderr + exit code

import 'dart:async';
import 'dart:io';
import '../agent_tool.dart';
import '../../../core/dev_paths.dart';

const _projectRoot = '<HOME>/Developer/bridge_app';

/// 允許的指令前綴白名單
const _allowedCommands = [
  'dart',
  'flutter',
  'grep',
  'rg',
  'find',
  'cat',
  'ls',
  'wc',
  'git status',
  'git diff',
  'git log',
  'git stash',
  // [小葵 2026-09-16 Blue 令] 自修審計發現：白名單沒有 commit——
  // agent 被要求「修完 git commit」但工具不允許，機制性不可能完成。
  // 補齊版本控制鏈（add/commit/show/branch）。不給 push——遠端發佈留給人類。
  'git add',
  'git commit',
  'git show',
  'git branch',
  'head',
  'tail',
];

class RunTerminalTool extends AgentTool {
  @override
  String get name => 'run_terminal';

  @override
  String get description =>
      '在專案目錄下執行終端指令。用於 dart analyze（語法檢查）、flutter build（編譯）、'
      'grep/find（搜尋程式碼）、git status/diff（版本控制）。'
      '安全限制：只允許白名單指令（dart, flutter, grep, find, git status/diff/log, cat, ls, wc）。'
      '超時 120 秒。回傳 stdout + stderr + exit code。';

  @override
  List<AgentToolParamSpec> get paramSpecs => const [
        AgentToolParamSpec(
          name: 'command',
          description: '要執行的完整指令，例如 "dart analyze lib/screens/desktop_welcome_screen.dart"',
          required: true,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final command = args['command']?.toString() ?? '';
      if (command.isEmpty) {
        return AgentToolResult.failure('command 參數為空');
      }

      // 驗證指令在白名單內
      final isAllowed = _allowedCommands.any((c) => command.trim().startsWith(c));
      if (!isAllowed) {
        return AgentToolResult.failure(
          '指令不在白名單內。允許的指令：${_allowedCommands.join(", ")}',
        );
      }

      // 執行指令
      final result = await Process.start(
        '/bin/sh',
        ['-c', command],
        workingDirectory: _projectRoot,
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      final stdoutSub = result.stdout.transform(const SystemEncoding().decoder).listen(stdoutBuffer.write);
      final stderrSub = result.stderr.transform(const SystemEncoding().decoder).listen(stderrBuffer.write);

      // [v219 Blue 抓包] 超時 120→600 秒——flutter build 要 3-5 分鐘，
      // 120 秒砍進程=Agent 跑長任務（build/測試）必被中斷，
      // 對外表現就是「跑到一半停了」。
      final exitCode = await result.exitCode.timeout(
        const Duration(seconds: 600),
        onTimeout: () {
          result.kill(ProcessSignal.sigkill);
          return -1;
        },
      );

      await stdoutSub.cancel();
      await stderrSub.cancel();

      final stdout = stdoutBuffer.toString();
      final stderr = stderrBuffer.toString();

      // 組裝結果
      final buffer = StringBuffer();
      buffer.writeln('指令：$command');
      buffer.writeln('工作目錄：$_projectRoot');
      buffer.writeln('Exit code: $exitCode');
      if (stdout.isNotEmpty) {
        buffer.writeln('--- stdout ---');
        // 截斷過長輸出（50KB 上限）
        if (stdout.length > 50000) {
          buffer.writeln(stdout.substring(0, 50000));
          buffer.writeln('...（輸出被截斷，共 ${stdout.length} 字元）');
        } else {
          buffer.writeln(stdout);
        }
      }
      if (stderr.isNotEmpty) {
        buffer.writeln('--- stderr ---');
        if (stderr.length > 20000) {
          buffer.writeln(stderr.substring(0, 20000));
          buffer.writeln('...（輸出被截斷）');
        } else {
          buffer.writeln(stderr);
        }
      }

      if (exitCode == 0) {
        return AgentToolResult.success(buffer.toString());
      } else if (exitCode == -1) {
        return AgentToolResult.failure('指令超時（120 秒）。$buffer');
      } else {
        return AgentToolResult.success(
          '$buffer\n注意：exit code 非 0，可能有錯誤。請檢查上方輸出。',
        );
      }
    } catch (e) {
      return AgentToolResult.failure('執行指令失敗：$e');
    }
  }
}
