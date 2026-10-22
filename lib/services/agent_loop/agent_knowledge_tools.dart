// agent_knowledge_tools.dart
// Agent 本地知識庫工具 — Phase E
// [教練 Agent 2026-07-22]
//
// 3 個工具：
// 1. agent_search_knowledge — 搜尋本地知識庫（scripts + memories）
// 2. agent_save_script — 儲存新腳本到知識庫
// 3. agent_save_memory — 儲存記憶點到知識庫

import 'package:bridge_app/services/agent_loop/agent_tool.dart';
import 'package:bridge_app/services/agent_loop/agent_knowledge_service.dart';
import 'package:bridge_app/services/memory_layer_service.dart'; // [T3] 分層寫入
import 'package:bridge_app/services/belief_gate.dart'; // [T3] BeliefGateRejectedError
import 'package:flutter/foundation.dart';

/// AgentSearchKnowledgeTool — 搜尋本地知識庫
///
/// 讓 Agent 能搜尋自己累積的腳本和記憶，
/// 實現「本地優先」策略：先查本地 → 有匹配就直接用 → 沒有才走 LLM 推理。
class AgentSearchKnowledgeTool extends AgentTool {
  @override
  String get name => 'agent_search_knowledge';

  @override
  String get description =>
      '搜尋 Agent 的本地知識庫，包含腳本（SOP/範本/快捷序列）和記憶點（教訓/偏好/模式）。'
      '用於在回答前先查本地是否有相關經驗或流程可以直接套用。'
      '回傳標題、摘要和類型。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(
      name: 'query',
      description: '搜尋關鍵字（如「畫布工作流」「記憶整理」「IG 發文」）',
      required: true,
    ),
    const AgentToolParamSpec(
      name: 'limit',
      description: '最大結果數（預設 5）',
      required: false,
      defaultValue: '5',
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final query = args['query'] as String? ?? '';
      final limit = int.tryParse(args['limit']?.toString() ?? '5') ?? 5;

      if (query.trim().isEmpty) {
        return AgentToolResult.failure('搜尋關鍵字不能為空');
      }

      final scripts = AgentKnowledgeService.instance.searchScripts(query, limit: limit);
      final memories = AgentKnowledgeService.instance.searchMemories(query, limit: 3);

      if (scripts.isEmpty && memories.isEmpty) {
        return AgentToolResult.success('本地知識庫中沒有找到與「$query」相關的內容。');
      }

      final lines = <String>[];
      if (scripts.isNotEmpty) {
        lines.add('找到 ${scripts.length} 個相關腳本：\n');
        for (var i = 0; i < scripts.length; i++) {
          final s = scripts[i];
          final cat = s.category != null ? ' [${s.category}]' : '';
          lines.add('${i + 1}. ${s.title}$cat');
          lines.add('   ${s.snippet}');
          lines.add('   ID: ${s.id}');
          lines.add('');
        }
      }

      if (memories.isNotEmpty) {
        lines.add('找到 ${memories.length} 個相關記憶：\n');
        for (var i = 0; i < memories.length; i++) {
          final m = memories[i];
          // [指紋章 2026-10-21 ②刀2] 出處章——誰的記憶、何時寫下
          final stamp = m.fingerprintLabel == null ? '' : '〔${m.fingerprintLabel}〕';
          lines.add('${i + 1}. ${m.title}$stamp');
          lines.add('   ${m.snippet}');
          lines.add('   ID: ${m.id}');
          lines.add('');
        }
      }

      return AgentToolResult.success(lines.join('\n'));
    } catch (e) {
      debugPrint('[AgentSearchKnowledgeTool] 失敗: $e');
      return AgentToolResult.failure('搜尋知識庫失敗: $e');
    }
  }
}

/// AgentSaveScriptTool — 儲存新腳本到知識庫
///
/// 讓 Agent 能把學到的新流程、SOP、範本存起來，
/// 下次遇到類似需求時可以直接套用。
class AgentSaveScriptTool extends AgentTool {
  @override
  String get name => 'agent_save_script';

  @override
  String get description =>
      '將新的腳本/SOP/範本儲存到本地知識庫。'
      '用於把成功的流程或學到的經驗固化為可重用的腳本。'
      '儲存後下次遇到類似需求可以直接搜尋套用。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(
      name: 'title',
      description: '腳本標題（簡短，如「畫布工作流建立流程」）',
      required: true,
    ),
    const AgentToolParamSpec(
      name: 'content',
      description: '腳本內容（Markdown 格式，包含步驟和原則）',
      required: true,
    ),
    const AgentToolParamSpec(
      name: 'description',
      description: '腳本描述（一行說明這個腳本做什麼）',
      required: false,
    ),
    const AgentToolParamSpec(
      name: 'tags',
      description: '標籤（逗號分隔，如「canvas, workflow, sop」）',
      required: false,
    ),
    const AgentToolParamSpec(
      name: 'category',
      description: '分類（SOP / Skill / Snippet / Tool Config）',
      required: false,
    ),
    const AgentToolParamSpec(
      name: 'trigger_keywords',
      description: '觸發關鍵字（逗號分隔，讓搜尋更容易命中）',
      required: false,
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final title = args['title'] as String? ?? '';
      final content = args['content'] as String? ?? '';
      final description = args['description'] as String?;
      final tags = args['tags'] as String?;
      final category = args['category'] as String?;
      final triggerKeywords = args['trigger_keywords'] as String?;

      if (title.trim().isEmpty || content.trim().isEmpty) {
        return AgentToolResult.failure('標題和內容不能為空');
      }

      final id = AgentKnowledgeService.instance.createScript(
        title: title,
        description: description,
        content: content,
        tags: tags,
        category: category,
        triggerKeywords: triggerKeywords,
        source: 'agent',
      );

      return AgentToolResult.success(
        '已儲存腳本「$title」到本地知識庫。\nID: $id\n下次遇到類似需求時可以用 agent_search_knowledge 搜尋套用。',
      );
    } catch (e) {
      debugPrint('[AgentSaveScriptTool] 失敗: $e');
      return AgentToolResult.failure('儲存腳本失敗: $e');
    }
  }
}

/// AgentSaveMemoryTool — 儲存記憶點到知識庫
///
/// 讓 Agent 能把學到的教訓、使用者偏好、發現的模式存起來，
/// 形成長期記憶，避免重複犯錯。
class AgentSaveMemoryTool extends AgentTool {
  @override
  String get name => 'agent_save_memory';

  @override
  String get description =>
      '將記憶點（教訓/偏好/模式/里程碑）儲存到本地知識庫。'
      '用於記錄從互動中學到的經驗，避免重複犯錯。'
      '記憶點會在未來相關對話中被自動檢索和引用。'
      '[T3] layer=environment（環境/事實斷言）會經 BeliefGate 驗證'
      '（需 3 次一致證據），證據不足時建議改用 project_cold。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
    const AgentToolParamSpec(
      name: 'title',
      description: '記憶標題（簡短，如「使用者偏好暗色介面」）',
      required: true,
    ),
    const AgentToolParamSpec(
      name: 'content',
      description: '記憶內容（詳細描述這個教訓或偏好）',
      required: true,
    ),
    const AgentToolParamSpec(
      name: 'tags',
      description: '標籤（逗號分隔，如「ui, preference, dark_mode」）',
      required: false,
    ),
    const AgentToolParamSpec(
      name: 'memory_type',
      description: '記憶類型（lesson / preference / pattern / milestone）',
      required: false,
      defaultValue: 'lesson',
    ),
    const AgentToolParamSpec(
      name: 'layer',
      description: '記憶層（lesson=教訓 / preference=偏好 / pattern=模式 / '
          'milestone=里程碑 / environment=環境事實（過 BeliefGate）/ '
          'decision=決策 / project_cold=專案冷）',
      required: false,
      defaultValue: 'lesson',
    ),
  ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final title = args['title'] as String? ?? '';
      final content = args['content'] as String? ?? '';
      final tags = args['tags'] as String?;
      final memoryType = args['memory_type'] as String? ?? 'lesson';
      // [小葵 2026-10-15 T3] layer 參數——分層寫入；
      // environment（L4）走 MemoryLayerService 過 BeliefGate（證據門檻）
      final layerArg = args['layer'] as String? ?? memoryType;

      if (title.trim().isEmpty || content.trim().isEmpty) {
        return AgentToolResult.failure('標題和內容不能為空');
      }

      // layer 對映：工具參數 → MemoryLayer
      const layerMap = {
        'lesson': 'L6',
        'preference': 'L4', // 偏好本質是環境事實——同樣過 gate
        'pattern': 'L6',
        'milestone': 'L5',
        'environment': 'L4',
        'decision': 'L5',
        'project_cold': 'L7',
        'talks': 'L8',
      };
      final layerCode = layerMap[layerArg] ?? 'L6';

      if (layerCode == 'L4') {
        // [T3] BeliefGate 通道——拒絕時降級 L7（專案冷）不擋任務
        try {
          final id = await MemoryLayerService.instance.write(
            layer: MemoryLayer.l4Environment,
            title: title,
            content: content,
            tags: tags,
            memoryType: memoryType,
          );
          return AgentToolResult.success(
            '已儲存環境信念「$title」到 L4（BeliefGate 驗證通過）。\nID: $id',
          );
        } on BeliefGateRejectedError catch (e) {
          // 降級寫 L7——信念存證不足不硬寫，但知識不丟（記憶鐵律）
          final id = await MemoryLayerService.instance.write(
            layer: MemoryLayer.l7ProjectCold,
            title: '[待驗證] $title',
            content: content,
            tags: (tags ?? '') + (tags == null || tags.isEmpty ? '' : ',') + 'belief_pending',
            memoryType: memoryType,
          );
          return AgentToolResult.success(
            '「$title」證據不足（${e.verdict.evidenceCount}/3），已存入 L7 專案冷'
            '（tag=belief_pending）。反覆被印證後可升級為 L4 信念。\nID: $id',
          );
        }
      }

      final id = AgentKnowledgeService.instance.createMemory(
        title: title,
        content: content,
        tags: tags,
        memoryType: memoryType,
      );
      // [T3] 非 L6 預設層：補 UPDATE layer（createMemory 不帶 layer）
      if (layerCode != 'L6' && layerCode != null) {
        AgentKnowledgeService.instance.setMemoryLayer(id, layerCode);
      }

      return AgentToolResult.success(
        '已儲存記憶點「$title」到本地知識庫（$layerCode 層）。\nID: $id\n這個記憶會在未來相關對話中被自動檢索。',
      );
    } catch (e) {
      debugPrint('[AgentSaveMemoryTool] 失敗: $e');
      return AgentToolResult.failure('儲存記憶失敗: $e');
    }
  }
}
