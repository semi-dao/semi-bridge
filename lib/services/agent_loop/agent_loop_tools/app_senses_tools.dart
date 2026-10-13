import '../../bridge_mcp_server.dart';
import '../../app_retina.dart' show AppRetina;
import '../agent_tool.dart';

// ═══════════════════════════════════════════════════
// [開光 v0.4 最後一哩 · 2026-10-01 Blue 令]
// 內建 agent loop 的開光感官——同進程直呼 MCP callbacks
//（app_scroll / app_tap 語意點擊 / app_look 視網膜），
// 不走 8420 HTTP——零網路延遲、零 token 開銷。
// ═══════════════════════════════════════════════════

/// app_scroll — 捲動當前頁面（看見頁面深處）
class AppScrollSenseTool extends AgentTool {
  @override
  String get name => 'app_scroll';

  @override
  String get description =>
      '捲動當前 App 頁面。direction: up/down/top/bottom，pixels 可選（預設 600）。'
      '回傳捲動後位置與是否到底。要看清單深處、找被切掉的內容時先用這個。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        const AgentToolParamSpec(
          name: 'direction',
          description: 'up/down/top/bottom',
          required: true,
        ),
        const AgentToolParamSpec(
          name: 'pixels',
          description: '捲動像素量（up/down 用，預設 600）',
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final mcp = BridgeMcpServer.instance;
    final direction = (args['direction'] as String?) ?? 'down';
    final pixels = (args['pixels'] as num?)?.toDouble();
    if (mcp.onAppScroll == null) {
      return AgentToolResult.failure('捲動感官未接線');
    }
    final r = await mcp.onAppScroll!(direction, pixels);
    if (r['success'] == true) {
      return AgentToolResult.success(
          '已捲動 $direction → pos ${r['position']}/${r['maxScrollExtent']}'
          '${r['reachedBottom'] == true ? '（到底）' : ''}');
    }
    return AgentToolResult.failure('${r['message'] ?? '捲動失敗'}');
  }
}

/// app_tap — 語意點擊（找畫面上的按鈕文字 → 定位 → 兩段式安全點擊）
class AppTapSenseTool extends AgentTool {
  @override
  String get name => 'app_tap';

  @override
  String get description =>
      '點擊 App 畫面上的按鈕：selector=按鈕文字（如「設為現役」「下載」）。'
      '預設只定位回報座標（安全）；confirm=true 執行真點擊。也可 x/y 座標。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        const AgentToolParamSpec(
          name: 'selector',
          description: '按鈕上的文字（語意選擇器）',
        ),
        const AgentToolParamSpec(name: 'x', description: '座標後門 x'),
        const AgentToolParamSpec(name: 'y', description: '座標後門 y'),
        const AgentToolParamSpec(
          name: 'confirm',
          description: 'true=執行真點擊（預設 false 只定位）',
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final mcp = BridgeMcpServer.instance;
    final selector = args['selector'] as String?;
    final x = (args['x'] as num?)?.toDouble();
    final y = (args['y'] as num?)?.toDouble();
    final confirm = (args['confirm'] as bool?) ?? false;
    if (mcp.onAppTap == null) {
      return AgentToolResult.failure('點擊感官未接線');
    }
    final r = await mcp.onAppTap!(
        selector: selector, x: x, y: y, confirm: confirm);
    if (r['success'] == true) {
      return AgentToolResult.success(
          '${r['tapped'] == true ? '✅ 已點擊' : '📍 已定位'}「${r['found']}」'
          ' @ (${r['x']}, ${r['y']})${r['note'] != null ? ' — ${r['note']}' : ''}');
    }
    return AgentToolResult.failure('${r['message'] ?? '定位失敗'}');
  }
}

/// app_look — 視網膜：拍下當前 App 畫面（base64 PNG）
class AppLookSenseTool extends AgentTool {
  @override
  String get name => 'app_look';

  @override
  String get description =>
      '拍下當前 App 畫面（如眨眼般看見）。你看到的就是使用者看到的。'
      '⚠️ 使用者描述「畫面/畫面出現…/看起來怪怪的/有警示條」這類視覺問題時，'
      '這是你的第一手證據——先用這個看現場，再用 read_app_log 交叉驗證。'
      '只讀 log 就下結論 = 只看檢驗報告不看病人。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        const AgentToolParamSpec(
          name: 'pixelRatio',
          description: '解析度倍率（預設 1.0）',
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final b64 = await AppRetina.capture(
        pixelRatio: (args['pixelRatio'] as num?)?.toDouble() ?? 1.0,
      );
      if (b64 == null) {
        return AgentToolResult.failure('App 尚未渲染');
      }
      return AgentToolResult.success('視網膜拍照完成（${b64.length ~/ 1024}KB base64 PNG）',
          metadata: {'image': b64, 'format': 'png'});
    } catch (e) {
      return AgentToolResult.failure('拍照失敗: $e');
    }
  }
}
