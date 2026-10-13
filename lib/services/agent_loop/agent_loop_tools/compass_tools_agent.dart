/// 羅盤系統工具 — App Agent 動系統前的第一站
///
/// [三步長肉 Step 3 · 小葵 2026-09-07]
/// 治理原則（docs/specs/2026-09-06-compass-system.md §7）：
/// - Agent 不可寫意義層（人的擁有物）
/// - Agent 不可 apply 行為規則（人的最後一道閘）
/// - visual 規則 propose 即時生效；behavioral 規則 propose → pendingApply 等人套用
/// - 動任何器官前必須先 compass_read 看規則（手術前看羅盤）

import 'dart:convert';

import '../agent_tool.dart';
import '../../compass/compass_models.dart';
import '../../compass/compass_self_gauge.dart'; // [小葵 2026-09-21 R4] 儀表
import '../../compass/compass_store.dart';

class CompassReadTool extends AgentTool {
  @override
  String get name => 'compass_read';

  @override
  String get description =>
      '讀取羅盤系統——App 的自我認知地圖與規則中心。'
      '任何要修改 App 系統/器官/規則的任務，執行前必須先呼叫本工具。'
      '\n'
      '回傳：器官清單（含健康與檔案錨點）+ 每個器官的規則卡。'
      '\n'
      '適用場景：\n'
      '- 修改系統行為前查詢現有規則（誰改的、為什麼、可回滾）\n'
      '- 修理自己前確認器官位置與依賴\n'
      '- 長新器官前看現有結構與治理慣例';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'organ_id',
          description: '只看單一器官（如 brain.galaxy3d）；省略=全部摘要',
          required: false,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final store = CompassStore.instance;
    final organId = args['organ_id']?.toString();

    try {
      final buf = StringBuffer();
      buf.writeln('## 羅盤 v${store.version}');
      buf.writeln();

      if (organId != null && organId.isNotEmpty) {
        // [小葵 2026-09-21 R4] compass.self = 儀表器官——即時算指標
        if (organId == 'compass.self') {
          final gauge = CompassSelfGauge.instance;
          final m = gauge.compute();
          // 快照入 meta（前端/夢境議程可讀最後一份）
          try {
            store.setMeta('self_gauge_last', gauge.metricsJson(m));
          } catch (_) {}
          return AgentToolResult.success(gauge.briefing(m));
        }
        final organs = store.organs(includeRetired: true)
            .where((o) => o.id == organId);
        if (organs.isEmpty) {
          // [小葵 2026-09-21 R2 傷口#38] 查不存在的器官：裸 failure 會讓
          // agent 反覆撞牆（2026-09-18 實證：agent.mind 連敗立案）。
          // fail-open＋建議：給相近器官清單，引導下一步就走對。
          final all = store.organs(includeRetired: true).map((o) => o.id).toList();
          final near = all.where((id) => id.contains(
              organId.split('.').last)).take(5).toList();
          final hint = near.isEmpty
              ? '現有器官：${all.take(12).join('、')}${all.length > 12 ? '…共 ${all.length} 個' : ''}'
              : '相近器官：${near.join('、')}';
          return AgentToolResult.failure(
              '器官 $organId 不存在於羅盤。$hint。用 compass_read 不帶 organ_id 可看全圖索引。');
        }
        final o = organs.first;
        buf.writeln('### ${o.name}（${o.id}）· ${o.systemGroup}'
            '${o.systemGroup == '已退役' ? ' ⚠️ 已退役' : ''}');
        buf.writeln('檔案錨點：');
        for (final p in o.facts.paths) {
          buf.writeln('  - $p (${o.facts.loc} 行)');
        }
        if (o.facts.endpoints.isNotEmpty) {
          buf.writeln('端點：${o.facts.endpoints.join(', ')}');
        }
        buf.writeln();
        final rules = store.rules(organId: o.id, includeRetired: true);
        buf.writeln('規則卡（${rules.where((r) => r.status != CompassRuleStatus.retired).length} 條活躍）：');
        for (final r in rules) {
          final st = r.status == CompassRuleStatus.retired ? ' [已退役]' : '';
          buf.writeln('- ${r.id}$st');
          buf.writeln('  ${r.description}');
          buf.writeln('  為什麼：${r.why}');
          buf.writeln('  參數：${jsonEncode(r.params)}');
          buf.writeln('  最後修改：${r.updatedBy} · ${r.updatedAt.month}/${r.updatedAt.day}');
        }
        final pitfalls = store.pitfalls(o.id);
        if (pitfalls.isNotEmpty) {
          buf.writeln('陷阱：');
          for (final p in pitfalls) {
            buf.writeln('  ⚠️ ${p.text}');
          }
        }
      } else {
        final organs = store.organs();
        final groups = <String, List<String>>{};
        for (final o in organs) {
          groups.putIfAbsent(o.systemGroup, () => []).add(o.id);
        }
        buf.writeln('器官總數：${organs.length}（分 ${groups.length} 群）');
        buf.writeln();
        for (final e in groups.entries) {
          final withRules = e.value
              .where((id) => store.rules(organId: id).isNotEmpty)
              .map((id) => '$id*')
              .toList();
          buf.writeln('${e.key}（${e.value.length}）：'
              '${withRules.isNotEmpty ? withRules.join(' ') : e.value.join(' ')}');
        }
        buf.writeln();
        buf.writeln('（* = 有規則卡；compass_read?organ_id=XXX 看詳情）');
      }
      return AgentToolResult.success(buf.toString().trim());
    } catch (e) {
      return AgentToolResult.failure('羅盤讀取失敗：$e');
    }
  }
}

class CompassProposeTool extends AgentTool {
  @override
  String get name => 'compass_propose';

  @override
  String get description =>
      '提議修改羅盤規則參數（不直接改 code）。'
      '\n'
      '治理：visual 規則提議後即時生效；behavioral 規則提議後進入'
      '「待套用」狀態，等使用者在羅盤 UI 按「套用」才生效。'
      '每次提議都會記錄署名與原因，可回滾。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'rule_id',
          description: '規則 id（如 galaxy.lightAuthority）',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'params',
          description: '新參數 JSON（完整覆蓋，如 {"threshold": 0.55}）',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'reason',
          description: '提議原因（會記錄在規則歷史，人會看到）',
          required: true,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final store = CompassStore.instance;
    final ruleId = args['rule_id']?.toString() ?? '';
    final reason = args['reason']?.toString() ?? '';
    if (ruleId.isEmpty || reason.isEmpty) {
      return AgentToolResult.failure('rule_id 與 reason 為必填');
    }
    Map<String, dynamic> newParams;
    try {
      newParams = jsonDecode(args['params'].toString())
          as Map<String, dynamic>;
    } catch (e) {
      // [小葵 2026-10-05 Blue 開案] 她 8 次撞牆都是無引號假 JSON——
      // 給她「正確的路」：錯誤訊息直接附正確格式範例，照抄就會過。
      return AgentToolResult.failure(
          'params 不是合法 JSON：$e\n'
          '常見錯誤：鍵與字串值沒有用雙引號包起來。\n'
          '正確範例（照抄這個格式）：{"threshold": 0.55, "mode": "rolling"}\n'
          '錯誤範例（不要這樣寫）：{threshold: 0.55, mode: rolling}');
    }

    try {
      final existing = store.rule(ruleId);
      if (existing == null) {
        // [小葵 2026-10-05 Blue 開案] 立新規則的門——
        // 舊行為：規則不存在直接擋（她的方案需要新規則，無路可走）。
        // 新行為：不存在的 rule_id 走「立案提案」——建一條 pendingApply
        // 的 behavioral 規則（一律待套用，等使用者在羅盤 UI 裁決），
        // 署名 agent 提案、附原因、可回滾。立新規則比改舊規則更敏感，
        // 所以永遠不即時生效。
        final organId = ruleId.contains('.')
            ? ruleId.substring(0, ruleId.indexOf('.'))
            : 'agent.loop';
        store.createRule(
          ruleId,
          organId: organId,
          description: '（agent 提案立項，待使用者審核）$reason',
          why: reason,
          params: newParams,
          kind: CompassRuleKind.behavioral,
          author: 'agent:小橋',
        );
        return AgentToolResult.success(
            '已立案新規則 $ruleId（進入待套用——等使用者在羅盤 UI 按「套用」才生效）\n'
            '原因：$reason\n'
            '下一步建議：compass_read $ruleId 回讀驗證立案內容。');
      }
      store.updateRuleParams(
        ruleId,
        newParams: newParams,
        author: 'agent:小橋',
        reason: reason,
      );
      final statusNote = existing.kind == CompassRuleKind.visual
          ? '（visual 規則：已即時生效）'
          : '（behavioral 規則：進入待套用，等使用者按「套用」）';
      return AgentToolResult.success(
          '已提議 $ruleId → ${jsonEncode(newParams)}$statusNote\n'
          '原因：$reason\n'
          '下一步建議：compass_read $ruleId 回讀驗證參數已更新。');
    } catch (e) {
      return AgentToolResult.failure('提議失敗：$e');
    }
  }
}
