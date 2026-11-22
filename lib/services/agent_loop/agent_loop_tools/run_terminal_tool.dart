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

const _projectRoot = '<BRIDGE_APP_ROOT>';

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
  // [小葵 2026-11-03 待決策卡閉環] 補 timeout——病例：agent 查 DB 用
  // `timeout 10 sqlite3 …` 被開頭白名單連坐擋下 5 次（它其實只是想
  // 限時防呆）。timeout 本身無害，包的指令仍要過白名單的「下一關」。
  'timeout',
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
      // [小葵 2026-11-03 晚場補洞] timeout 前綴剝殼檢查——病例：小橋現場
      // 發現 `timeout 10 sqlite3 …` 開頭是 timeout → 過白名單 → 任何指令
      // 包一層 timeout 就能繞。修法：timeout 只是計時器外殼，剝掉外殼
      // 與時長參數後，內層指令必須自己過白名單。
      var checkCmd = command.trim();
      final timeoutShell = RegExp(r'^timeout\s+([0-9]+(\.[0-9]+)?[smh]?)?\s+');
      while (timeoutShell.hasMatch(checkCmd)) {
        checkCmd = checkCmd.replaceFirst(timeoutShell, '');
      }
      final isAllowed = _allowedCommands.any((c) => checkCmd.startsWith(c));
      if (!isAllowed) {
        // [小葵 2026-11-03 待決策卡閉環] 教材式錯誤——工具報錯要當教材
        // 不只擋（compass_propose 案驗證有效）：告訴 agent 能用什麼代替。
        final first = command.trim().split(RegExp(r'\s+')).first;
        String hint = '';
        if (first == 'sqlite3') {
          hint = '\n提示：sqlite3 不開放（直開 DB 有寫入風險）。'
              '替代路線：grep -o 檔案抓欄位值、find 找檔案、head/tail 看內容'
              '（2026-11-03 病例實證這條路查得到資料）。';
        } else if (first == 'python3' || first == 'python') {
          hint = '\n提示：python 不在白名單。資料查證走 grep/find/head/tail，'
              '程式修改走 patch_source_file。';
        } else if (first == 'rm' || first == 'mv' || first == 'cp') {
          hint = '\n提示：檔案系統寫操作不開放。程式修改走 patch_source_file。';
        }
        return AgentToolResult.failure(
          '指令不在白名單內（$first）。允許的指令：'
          '${_allowedCommands.join(", ")}.$hint',
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
