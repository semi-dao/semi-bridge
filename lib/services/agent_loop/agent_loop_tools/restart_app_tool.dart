// restart_app_tool.dart
// [Phase 1 2026-07-17] 原生 Agent 自維修工具 #5：重啟 App
// [2026-07-18] Checkpoint 協議：重啟前寫 checkpoint，重啟後 NativeAgentLoop 讀取並驗證
//
// 讓 Agent 能在修改程式碼 + build 後重啟 App。
// 原理：啟動新的 App 進程，然後 exit 當前進程。
// 安全限制：需要先 build 才能重啟（否則跑的還是舊 binary）。
//
// 注意：此工具執行後 App 會立即關閉並重開。Agent 的對話狀態會丟失。
// 但 checkpoint 會保留——重啟後 NativeAgentLoop 會讀取並接續工作。
// 建議流程：patch_source_file → run_terminal("dart analyze ...") → run_terminal("flutter build") → restart_app

import 'dart:io';
import 'package:flutter/foundation.dart';
import '../agent_tool.dart';
import '../../../core/dev_paths.dart';
import '../app_log_buffer.dart';
import '../agent_checkpoint.dart';

class RestartAppTool extends AgentTool {
  @override
  String get name => 'restart_app';

  @override
  String get description =>
      '重啟 App（關閉當前進程並開啟新進程）。用於修改程式碼並 build 後讓變更生效。'
      '注意：執行後 App 會立即關閉重開，對話狀態會丟失。'
      '重啟前會自動寫入 checkpoint，重啟後系統會自動讀取並驗證修改效果。'
      '建議流程：patch_source_file → run_terminal("dart analyze ...") → '
      'run_terminal("flutter build macos --debug") → restart_app';

  @override
  List<AgentToolParamSpec> get paramSpecs => const [
        AgentToolParamSpec(
          name: 'reason',
          description: '重啟原因（將存入 checkpoint，重啟後用於驗證）。例如：「驗證首頁改善效果」',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'changed_files',
          description: '修改了哪些檔案（JSON 陣列字串）。例如：["lib/screens/bridge_desktop_screen.dart"]',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'expected_effect',
          description: '預期重啟後看到什麼效果（給驗證用）。例如：「首頁卡片有 hover 效果和手型指標」',
          required: false,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      // [小葵 2026-09-16 Blue 令] 開放重啟給 App Agent——路徑改為優先 Profile
      // （實際運行的 build），不存在再退 Debug。原本寫死 Debug 會重啟到舊 binary。
      final profilePath = resolveDevPath('~/Developer/bridge_app/'
          'build/macos/Build/Products/Profile/bridge_app.app');
      final debugPath = resolveDevPath('~/Developer/bridge_app/'
          'build/macos/Build/Products/Debug/bridge_app.app');
      final profileExists = await Directory(profilePath).exists();
      final appPath = profileExists ? profilePath : debugPath;

      // 確認 App binary 存在
      final appFile = Directory(appPath);
      if (!await appFile.exists()) {
        return AgentToolResult.failure(
          'App binary 不存在：$appPath。請先執行 run_terminal("flutter build macos --debug")。',
        );
      }

      // [2026-07-18] 寫入 checkpoint — 重啟後 NativeAgentLoop 會讀取
      final reason = args['reason']?.toString() ?? 'Agent 主動重啟';
      final changedFilesRaw = args['changed_files']?.toString() ?? '[]';
      final expectedEffect = args['expected_effect']?.toString();

      List<String> changedFiles;
      try {
        changedFiles = (changedFilesRaw.startsWith('['))
            ? (jsonDecodeAsList(changedFilesRaw) as List).cast<String>()
            : [changedFilesRaw];
      } catch (_) {
        changedFiles = [changedFilesRaw];
      }

      final checkpoint = AgentCheckpoint(
        checkpointId: 'restart_${DateTime.now().millisecondsSinceEpoch}',
        reason: reason,
        changedFiles: changedFiles,
        expectedEffect: expectedEffect,
        createdAt: DateTime.now(),
      );
      await AgentCheckpointManager().write(checkpoint);

      appLogBuffer.add('[RestartApp] 準備重啟 App... (checkpoint: ${checkpoint.checkpointId})');
      debugPrint('[RestartApp] 準備重啟 App... (checkpoint: ${checkpoint.checkpointId})');

      // 用 detached 模式啟動新進程（不繼承當前進程的 stdout/stderr）
      // 延遲 2 秒啟動，確保當前進程有時間完成 cleanup
      final detachResult = await Process.start(
        '/bin/sh',
        ['-c', 'sleep 2 && open "$appPath"'],
        mode: ProcessStartMode.detached,
      );

      appLogBuffer.add('[RestartApp] 新進程將在 2 秒後啟動 (pid=${detachResult.pid})');
      debugPrint('[RestartApp] 新進程將在 2 秒後啟動 (pid=${detachResult.pid})');

      // 延遲 exit 讓 AgentLoop 把結果回傳給 LLM
      Future.delayed(const Duration(seconds: 1), () {
        debugPrint('[RestartApp] 正在關閉當前進程...');
        exit(0);
      });

      return AgentToolResult.success(
        '✅ App 即將重啟。\n'
        'Checkpoint 已寫入：${checkpoint.checkpointId}\n'
        '原因：$reason\n'
        '修改檔案：${changedFiles.join(", ")}\n'
        '預期效果：${expectedEffect ?? "（未指定）"}\n\n'
        '新進程將在 2 秒後啟動，當前進程將在 1 秒後關閉。\n'
        '重啟後系統會自動讀取 checkpoint 並驗證修改效果。',
      );
    } catch (e) {
      return AgentToolResult.failure('重啟 App 失敗：$e');
    }
  }

  // 簡易 JSON array 解析（不引入 dart:convert 到工具層的複雜度）
  List<dynamic> jsonDecodeAsList(String s) {
    final cleaned = s.trim();
    if (!cleaned.startsWith('[')) return [s];
    // 去掉前後括號，按逗號分割，去引號空白
    final inner = cleaned.substring(1, cleaned.length - 1);
    if (inner.trim().isEmpty) return [];
    return inner.split(',').map((e) => e.trim().replaceAll('"', '').replaceAll("'", '')).toList();
  }
}
