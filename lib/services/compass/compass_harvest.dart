// compass_harvest.dart
// 羅盤事實層採集器 — 自動掃描程式碼回填器官錨點（檔案路徑、行號、端點）。
//
// 三步長肉 Step 1（Blue 2026-09-07 令）：
// - 靜態掃 lib/ 下的 .dart 檔，找出每個器官 id 的出現位置
// - paths：器官主要檔案（檔名符合對映表）
// - anchors：出現行號（[小葵/教練 Agent 日期] 標記的治理點）
// - endpoints：HTTP/服務埠掃描（18789 引擎、18900 Kokoro、8420 MCP）
// - lastVerifiedAt：每次掃描更新（mtime 地面真相）
//
// 治理：只寫事實層（facts），不碰意義層/規則層。冪等：重掃覆蓋 facts。

import 'dart:io';

import '../../core/dev_paths.dart';
import 'compass_models.dart';
import 'compass_store.dart';

/// 器官 id → 主要檔案對映（掃描目標）
/// 維護原則：新增器官時在 compass_seed 註冊，在這裡補檔案對映。
const Map<String, List<String>> kOrganFileMap = {
  'chat': [
    'lib/screens/chat_screen.dart',
    'lib/screens/desktop/desktop_chat_panel.dart',
  ],
  'chat.controller': ['lib/controllers/chat_controller.dart'],
  'voice.input': ['lib/services/voice/voice_engine.dart'],
  'voice.tts': ['lib/services/tts/kokoro_tts_service.dart'],
  'canvas.engine': [
    'lib/widgets/canvas/v2/canvas_v2_workspace.dart',
    'lib/widgets/canvas/v2/canvas_controller.dart',
  ],
  'canvas.chat': ['lib/widgets/canvas/v2/graph_canvas.dart'],
  'canvas.inspector': ['lib/widgets/canvas/v2/workflow_static_analyzer.dart'],
  'canvas.templates': ['lib/widgets/canvas/v2/template_picker_dialog.dart'],
  'brain.galaxy3d': [
    'assets/galaxy/galaxy.html',
    'lib/services/brain_container/galaxy_data_service.dart',
  ],
  'brain.container': ['lib/services/brain_container/brain_container_service.dart'],
  'brain.ingest': ['lib/services/vector_db/incremental_ingest_service.dart'],
  'brain.embed': ['lib/services/brain_container/embedding/'],
  // [小葵 2026-09-10 深度審查] vault 涉及檔案群補齊——只有
  // vault_screen.dart 時 agent 會漏改搜尋管線/MCP 端點
  'vault': [
    'lib/screens/vault_screen.dart',
    'lib/services/vault/vault_search_facade.dart',
    'lib/services/vector_db/hybrid_search_service.dart',
    'lib/services/vector_db/vector_sketch_service.dart',
    'lib/services/vector_db/identity_reembed_service.dart',
    'lib/services/vector_db/incremental_ingest_service.dart',
    'lib/services/vector_db/five_factor_rerank.dart',
    'lib/services/vector_db/dedup_service.dart',
    'lib/services/bridge_mcp_server.dart',
  ],
  'vault.graphrag': ['lib/services/vector_db/hover_insight_service.dart'],
  'project.door': ['lib/screens/companion_control_center_screen.dart'],
  'project.kanban': ['lib/widgets/project/project_kanban_board.dart'],
  'project.relation': ['lib/widgets/vault/vault_graph_view.dart'],
  'companion.hall': ['lib/screens/companion_list_screen.dart'],
  'companion.summon': ['lib/screens/summon_screen.dart'],
  'companion.control': ['lib/services/companion_runtime_outlet.dart'],
  'companion.floating': ['lib/widgets/floating_companion.dart'],
  // [小葵 2026-09-10 深度審查] agent.loop 檔案群補齊
  'agent.loop': [
    'lib/services/agent_loop/agent_loop.dart',
    'lib/services/agent_loop/agent_loop_prompt_builder.dart',
    'lib/services/agent_loop/agent_design_knowledge.dart',
    'lib/services/agent_loop/agent_tool_registry.dart',
    'lib/services/agent_loop/agent_loop_tools/compass_seek_agent_tool.dart',
  ],
  'agent.tools': ['lib/services/agent_loop/agent_loop.dart'],
  'agent.mcp': ['lib/services/bridge_mcp_server.dart'],
  'agent.budget': ['lib/services/budget_ledger.dart'],
  'local.engine': ['lib/services/local_model_runtime_service.dart'],
  'local.kokoro': ['lib/services/tts/kokoro_tts_service.dart'],
  'memory': ['lib/services/memory_store.dart'],
  'schedule': ['lib/services/agent_loop/agent_checkpoint.dart'],
  'theme': ['lib/theme/bridge_design_system.dart'],
  'goldenkeys': ['lib/services/api_service.dart'],
  'semidao': ['lib/services/semidao/semidao_service.dart'],
  'computeruse': ['lib/services/computer_use/'],
};

/// 掃描結果
class HarvestResult {
  final int organsTouched;
  final int pathsFound;
  final int anchorsFound;
  HarvestResult(this.organsTouched, this.pathsFound, this.anchorsFound);
}

/// 執行一次掃描（冪等；失敗靜默——fail-open）
HarvestResult harvestFacts(CompassStore store, {String? projectRoot}) {
  final root = projectRoot ??
      Platform.environment['BRIDGE_APP_ROOT'] ??
      _findRoot();
  if (root == null) return HarvestResult(0, 0, 0);

  var organsTouched = 0;
  var pathsFound = 0;
  var anchorsFound = 0;

  for (final entry in kOrganFileMap.entries) {
    final organId = entry.key;
    final organ = store.organs(includeRetired: true)
        .where((o) => o.id == organId).firstOrNull;
    if (organ == null) continue; // 未註冊器官不建檔

    final paths = <String>[];
    final anchors = <String>[];
    final endpoints = <String>[];

    for (final rel in entry.value) {
      final f = File('$root/$rel');
      if (f.existsSync()) {
        paths.add(rel);
        // 端點掃描：埠號出現
        final content = f.readAsStringSync();
        for (final m in RegExp(r'(?:127\.0\.0\.1|localhost):(\d{4,5})')
            .allMatches(content)) {
          final ep = 'localhost:${m.group(1)}';
          if (!endpoints.contains(ep)) endpoints.add(ep);
        }
        if (rel.endsWith('.dart')) {
          // 錨點掃描：治理標記（日期標記 = 治理點）
          for (final m in RegExp(
                  r'(\d{4}-\d{2}-\d{2})') // 任何 ISO 日期標記
              .allMatches(content)) {
            anchors.add('$rel#L${_lineOf(content, m.start)}');
            if (anchors.length > 20) break; // 每檔上限 20 錨點
          }
        }
      } else {
        final d = Directory('$root/$rel');
        if (d.existsSync()) {
          for (final sub in d.listSync().whereType<File>().take(10)) {
            paths.add('$rel${sub.path.split('/').last}');
          }
        }
      }
    }

    if (paths.isNotEmpty) {
      final facts = OrganFacts(
        paths: paths,
        anchors: anchors.take(20).toList(),
        deps: organ.facts.deps,
        endpoints: endpoints.take(10).toList(),
        loc: _countLoc(root, entry.value),
        lastVerifiedAt: DateTime.now(),
      );
      store.upsertOrgan(CompassOrgan(
        id: organ.id,
        systemGroup: organ.systemGroup,
        name: organ.name,
        facts: facts,
        anchorOk: true,
      ), byHarvest: 'auto:harvest');
      organsTouched++;
      pathsFound += paths.length;
      anchorsFound += anchors.length;
    }
  }
  return HarvestResult(organsTouched, pathsFound, anchorsFound);
}

int _lineOf(String content, int charOffset) =>
    '\n'.allMatches(content.substring(0, charOffset)).length + 1;

int _countLoc(String root, List<String> rels) {
  var loc = 0;
  for (final rel in rels) {
    final f = File('$root/$rel');
    if (f.existsSync() && rel.endsWith('.dart')) {
      loc += f.readAsLinesSync().length;
    }
  }
  return loc;
}

String? _findRoot() {
  // 從 cwd 往上找 pubspec.yaml
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  // fallback：已知本尊路徑
  const fallback = '<HOME>/Developer/bridge_app';
  if (File('$fallback/pubspec.yaml').existsSync()) return fallback;
  return null;
}
