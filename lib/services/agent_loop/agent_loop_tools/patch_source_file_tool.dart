// patch_source_file_tool.dart
// [Phase 1 2026-07-17] 原生 Agent 自維修工具 #2：修改原始碼檔案
//
// 讓 Agent 能用搜尋替換的方式修改專案內的原始碼檔案。
// 安全限制：
// - 只允許修改專案目錄下的檔案
// - old_string 必須在檔案中唯一存在，否則拒絕（避免誤改）
// - 改完後自動回傳 diff 讓 LLM 確認

import 'dart:io';
import '../agent_tool.dart';
import '../../../core/dev_paths.dart';

const _projectRoot = '<HOME>/Developer/bridge_app';

class PatchSourceFileTool extends AgentTool {
  @override
  String get name => 'patch_source_file';

  @override
  String get description =>
      '用搜尋替換的方式修改專案原始碼檔案。'
      '找到 old_string 並替換為 new_string。'
      'old_string 必須在檔案中唯一存在，否則拒絕修改。'
      '改完後回傳 diff 讓你確認。'
      '安全限制：只能修改專案目錄內的檔案。'
      '注意：修改後需要用 run_terminal 執行 dart analyze 驗證，再用 restart_app 重啟。';

  @override
  List<AgentToolParamSpec> get paramSpecs => const [
        AgentToolParamSpec(
          name: 'path',
          description: '檔案相對路徑（相對於專案根目錄），例如 lib/screens/desktop_welcome_screen.dart',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'old_string',
          description: '要搜尋的原始文字（必須唯一存在於檔案中）',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'new_string',
          description: '替換後的文字（傳空字串可刪除 old_string）',
          required: true,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final relativePath = args['path']?.toString() ?? '';
      final oldString = args['old_string']?.toString() ?? '';
      final newString = args['new_string']?.toString() ?? '';

      if (relativePath.isEmpty) {
        return AgentToolResult.failure('path 參數為空');
      }
      if (oldString.isEmpty) {
        return AgentToolResult.failure('old_string 參數為空');
      }

      // 解析路徑
      final fullPath = _resolvePath(relativePath);
      if (fullPath == null) {
        return AgentToolResult.failure('路徑不在專案目錄內。專案根目錄：$_projectRoot');
      }

      final file = File(fullPath);
      if (!await file.exists()) {
        return AgentToolResult.failure('檔案不存在：$relativePath');
      }

      // 讀取原檔
      final content = await file.readAsString();

      // 檢查 old_string 存在性
      final matchCount = _countOccurrences(content, oldString);
      if (matchCount == 0) {
        return AgentToolResult.failure(
          'old_string 在檔案中找不到。請用 read_source_file 確認檔案內容。',
        );
      }
      if (matchCount > 1) {
        return AgentToolResult.failure(
          'old_string 在檔案中出現 $matchCount 次，不是唯一的。'
          '請加入更多上下文讓 old_string 唯一。',
        );
      }

      // 執行替換
      final newContent = content.replaceFirst(oldString, newString);
      await file.writeAsString(newContent);

      // 產生 diff
      final oldLines = oldString.split('\n');
      final newLines = newString.split('\n');
      final diff = StringBuffer();
      diff.writeln('✅ 修改成功：$relativePath');
      diff.writeln('---');
      diff.writeln('移除（${oldLines.length} 行）：');
      for (final line in oldLines) {
        diff.writeln('- $line');
      }
      diff.writeln('新增（${newLines.length} 行）：');
      for (final line in newLines) {
        diff.writeln('+ $line');
      }
      diff.writeln('---');

      // [2026-07-18] 自動跑 dart analyze — 守門員機制
      // patch 完立刻驗證，如果有新 error 直接回傳讓 Agent 修
      try {
        final analyzeResult = await Process.run(
          'dart',
          ['analyze', fullPath],
          workingDirectory: _projectRoot,
        );
        final analyzeOutput = analyzeResult.stdout.toString();
        final analyzeError = analyzeResult.stderr.toString();
        final combined = '$analyzeOutput\n$analyzeError'.trim();

        // 解析 error 行
        final errorLines = combined
            .split('\n')
            .where((l) => l.contains('error -') || l.contains('Error:'))
            .toList();

        if (errorLines.isNotEmpty) {
          diff.writeln('❌ dart analyze 發現 ${errorLines.length} 個 error：');
          diff.writeln('```');
          for (final line in errorLines.take(10)) {
            diff.writeln(line.trim());
          }
          diff.writeln('```');
          diff.writeln('');
          diff.writeln('⚠️ 你的修改引入了編譯錯誤！請立即修復：');
          diff.writeln('1. 檢查你用的參數是否存在於該 class/widget 的定義中');
          diff.writeln('2. 用 read_source_file 查看該 class 的定義（找到 class 名稱，讀它的參數列表）');
          diff.writeln('3. 重新 patch_source_file 修復錯誤');
          diff.writeln('4. 不要假設參數存在——必須查證');
          return AgentToolResult.success(diff.toString());
        } else {
          diff.writeln('✅ dart analyze 通過，無新 error。');
        }
      } catch (e) {
        diff.writeln('⚠️ dart analyze 執行失敗（$e），請手動用 run_terminal 驗證。');
      }

      return AgentToolResult.success(diff.toString());
    } catch (e) {
      return AgentToolResult.failure('修改檔案失敗：$e');
    }
  }

  String? _resolvePath(String relativePath) {
    final cleaned = relativePath.replaceAll('..', '').replaceAll('//', '/');
    final fullPath = '$_projectRoot/$cleaned';
    final normalized = File(fullPath).absolute.path;
    if (!normalized.startsWith(_projectRoot)) return null;
    return normalized;
  }

  int _countOccurrences(String source, String pattern) {
    var count = 0;
    var idx = source.indexOf(pattern);
    while (idx != -1) {
      count++;
      idx = source.indexOf(pattern, idx + pattern.length);
    }
    return count;
  }
}
