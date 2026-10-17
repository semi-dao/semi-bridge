// memory_write_tool.dart
// [小葵 2026-10-17 T3②] memory_write agent 工具——寫記憶。
// L4（環境/事實信念）必過 BeliefGate（≥3 次獨立證據才可寫入）；
// 拒絕時回覆紅字原因與證據數，agent 可降級寫 L0（一般記憶）。
// manualOverride 只給 UI（人工確認），agent 路徑永遠 false——
// 信念的門檻不能被 agent 自己繞過（BeliefGate 註解同款鐵則）。

import 'package:flutter/foundation.dart';

import '../agent_tool.dart';
import '../../belief_gate.dart';

/// L4 寫入的實際落庫由 MemoryLayerService（vault 線）處理；
/// agent 線走本工具：L0 直寫腦容器管線、L4 過 gate 後標記寫入。
class MemoryWriteTool extends AgentTool {
  /// L4 寫入回呼——由註冊處注入（vault 線的 MemoryLayerService.write）。
  /// 簽名：(content, tags) => Future<bool>
  final Future<bool> Function(String content, List<String> tags)? onL4Write;

  /// L0 寫入回呼——腦容器 MemoryWritePipeline.write。
  /// 簽名：(content, tags) => Future<bool>
  final Future<bool> Function(String content, List<String> tags)? onL0Write;

  MemoryWriteTool({this.onL4Write, this.onL0Write});

  @override
  String get name => 'memory_write';

  @override
  String get description => '寫入一條記憶。layer="L0"（一般記憶，預設）或 '
      '"L4"（環境/事實信念——需要 ≥3 次獨立證據，不足會被拒絕並附原因；'
      '可改寫 L0）。\n'
      '⚠️ L4 斷言必須語意精確、帶限定語：斷言的是什麼範圍的事實就寫什麼範圍'
      '（例：「在哲學討論中，X 常被視為 Y」≠「X 是 Y」）。未限定的絕對化'
      '斷言（尤其與物理事實相悖的）不得寫入——先向使用者確認精確表述。'
      '[Blue 令 2026-10-17：不可接受直接植入「地球是平的」這類未限定斷言]';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'content',
          description: '記憶內容（一句斷言，L4 尤其要精確）',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'layer',
          description: 'L0=一般記憶（預設）；L4=環境/事實信念（過 BeliefGate）',
          required: false,
        ),
        AgentToolParamSpec(
          name: 'tags',
          description: '標籤，逗號分隔（可選）',
          required: false,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final content = (args['content']?.toString() ?? '').trim();
    if (content.isEmpty) {
      return AgentToolResult.failure('content 不可為空');
    }
    final layer = (args['layer']?.toString() ?? 'L0').toUpperCase();
    final tags = (args['tags']?.toString() ?? '')
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    // L4 必過 BeliefGate——agent 路徑 manualOverride 永遠 false
    if (layer == 'L4') {
      final verdict = await BeliefGate.instance.checkL4(
        assertion: content,
        manualOverride: false, // agent 不可自繞
      );
      if (!verdict.allowed) {
        debugPrint('[MemoryWriteTool] 🚫 L4 拒絕（${verdict.reason}）');
        return AgentToolResult.failure(
          'L4 信念寫入被拒（原因：${verdict.reason}；證據 '
          '${verdict.evidenceCount}/${BeliefGate.l4RequiredEvidence}）。'
          '可改寫 L0（一般記憶），或等更多證據累積。',
        );
      }
      final wrote = await onL4Write?.call(content, [...tags, 'L4-belief']);
      if (wrote != true) {
        return AgentToolResult.failure('L4 寫入失敗（落庫回呼未就緒）');
      }
      return AgentToolResult.success('已寫入 L4 信念：$content');
    }

    // L0：一般記憶
    if (onL0Write == null) {
      return AgentToolResult.failure('L0 寫入回呼未就緒');
    }
    final ok = await onL0Write!(content, tags);
    if (!ok) return AgentToolResult.failure('寫入失敗');
    return AgentToolResult.success('已寫入記憶：$content');
  }
}
