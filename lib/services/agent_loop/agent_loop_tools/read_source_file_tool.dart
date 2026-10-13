// read_source_file_tool.dart
// [Phase 1 2026-07-17] 原生 Agent 自維修工具 #1：讀原始碼檔案
//
// 讓 Agent 能讀取專案內的 .dart / .yaml / .entitlements 等文字檔案。
// 安全限制：只允許讀取專案目錄下的檔案，禁止讀取沙盒外路徑。

import 'dart:io';
import '../agent_tool.dart';
import '../../../core/dev_paths.dart';

/// 專案根目錄——Agent 只能讀這個目錄底下的檔案
final _projectRoot = resolveDevPath('~/Developer/bridge_app');

class ReadSourceFileTool extends AgentTool {
  @override
  String get name => 'read_source_file';

  @override
  String get description =>
      '讀取專案原始碼檔案內容。可用於查看 .dart / .yaml / .entitlements 等文字檔案，'
      '定位 bug 或理解程式邏輯。'
      '安全限制：只能讀取專案目錄內的檔案。'
      '支援 offset（從第幾行開始，1-indexed）和 limit（讀幾行）參數分頁讀取大檔案。';

  @override
  List<AgentToolParamSpec> get paramSpecs => const [
        AgentToolParamSpec(
          name: 'path',
          description: '檔案相對路徑（相對於專案根目錄），例如 lib/screens/desktop_welcome_screen.dart',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'offset',
          description: '從第幾行開始讀（1-indexed），預設 1',
          required: false,
          defaultValue: '1',
        ),
        AgentToolParamSpec(
          name: 'limit',
          description: '最多讀幾行，預設 200',
          required: false,
          defaultValue: '200',
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final relativePath = args['path']?.toString() ?? '';
      if (relativePath.isEmpty) {
        return AgentToolResult.failure('path 參數為空');
      }

      // 組合絕對路徑並驗證在專案目錄內
      final fullPath = _resolvePath(relativePath);
      if (fullPath == null) {
        return AgentToolResult.failure(
          '路徑不在專案目錄內。專案根目錄：$_projectRoot',
        );
      }

      final file = File(fullPath);
      if (!await file.exists()) {
        return AgentToolResult.failure('檔案不存在：$relativePath');
      }

      // 讀取檔案
      final lines = await file.readAsLines();
      final totalLines = lines.length;

      final offset = int.tryParse(args['offset']?.toString() ?? '1') ?? 1;
      final limit = int.tryParse(args['limit']?.toString() ?? '200') ?? 200;

      final startIdx = (offset - 1).clamp(0, totalLines);
      final endIdx = (startIdx + limit).clamp(0, totalLines);
      final sliced = lines.sublist(startIdx, endIdx);

      // 格式化輸出：LINE_NUM|content
      final buffer = StringBuffer();
      buffer.writeln('檔案：$relativePath（共 $totalLines 行）');
      buffer.writeln('顯示：第 ${startIdx + 1} ~ $endIdx 行');
      buffer.writeln('---');
      for (var i = 0; i < sliced.length; i++) {
        buffer.writeln('${startIdx + i + 1}|${sliced[i]}');
      }

      if (endIdx < totalLines) {
        buffer.writeln('---');
        buffer.writeln('還有 ${totalLines - endIdx} 行未顯示。用 offset=${endIdx + 1} 繼續讀。');
      }

      return AgentToolResult.success(buffer.toString());
    } catch (e) {
      return AgentToolResult.failure('讀取檔案失敗：$e');
    }
  }

  /// 解析相對路徑為絕對路徑，驗證在專案目錄內
  String? _resolvePath(String relativePath) {
    // 淨化路徑：移除 ../ 等目錄穿越攻擊
    final cleaned = relativePath.replaceAll('..', '').replaceAll('//', '/');
    final fullPath = '$_projectRoot/$cleaned';

    // 確認解析後的路徑仍在專案目錄內
    final normalized = File(fullPath).absolute.path;
    if (!normalized.startsWith(_projectRoot)) {
      return null;
    }
    return normalized;
  }
}
