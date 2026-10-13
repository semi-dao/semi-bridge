// 橋樑 Computer Use P1a — 最小 Agent Loop（眼睛→大腦→手 閉環）
//
// Spec: docs/specs/2026-09-05-bridge-computer-use.md §2.4
// 驗收目標（P1a）：模型操作 Finder 建資料夾＋改名，全程可觀測、可喊停。
//
// 設計：
// - 模型不可知：大腦是任何 OpenAI-compatible chat 端點（本地 18789 / 雲端鑰匙）
// - 每一步 emit ComputerUseStep 事件（UI 投影用，共同看見）
// - 每個動作前 Swift 端 TakeoverGate 單點檢查，Dart 端不重複判斷
// - 最大步數上限 + 停止旗標 = 雙保險
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'computer_use_service.dart';

/// 單步執行紀錄（畫布投影用）
class ComputerUseStep {
  final int index;
  final String think; // 模型這一步的想法
  final String action; // click / type / scroll / drag / done / fail
  final Map<String, dynamic>? target;
  final String? screenshotPath;
  final bool ok;
  final String? error;

  const ComputerUseStep({
    required this.index,
    required this.think,
    required this.action,
    this.target,
    this.screenshotPath,
    this.ok = true,
    this.error,
  });
}

/// Agent 迴圈的模型設定（模型不可知：任何 OpenAI-compatible 端點）
class ComputerUseBrain {
  final String baseUrl; // 例 http://127.0.0.1:18789/v1
  final String model; // 例 local-model
  final String? apiKey; // 本地引擎通常免鑰

  const ComputerUseBrain({
    required this.baseUrl,
    required this.model,
    this.apiKey,
  });
}

class ComputerUseAgent {
  static const MethodChannel _screen = MethodChannel('bridge.screen_capture.macos.v1');

  ComputerUseAgent({required this.brain, this.maxSteps = 15});

  final ComputerUseBrain brain;
  final int maxSteps;

  final _stepsController = StreamController<ComputerUseStep>.broadcast();
  Stream<ComputerUseStep> get stepStream => _stepsController.stream;

  bool _stopRequested = false;
  /// 使用者喊停（UI 的停止按鈕 / Esc 急停後的 Dart 端同步）
  void requestStop() => _stopRequested = true;

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30);

  // ---- 主循環 ----

  /// 執行任務。回傳最後一步（done 或 fail）。
  Future<ComputerUseStep> run(String task) async {
    final cu = ComputerUseService.instance;
    _stopRequested = false;

    // 安全前置：必須 armed → active 才開始
    final armErr = await cu.arm('agent:$task');
    if (armErr != null) {
      return _emit(ComputerUseStep(
        index: 0, think: '無法授權接管', action: 'fail', ok: false, error: armErr));
    }
    if (!await cu.activate()) {
      return _emit(ComputerUseStep(
        index: 0, think: 'activate 失敗', action: 'fail', ok: false,
        error: '需先 arm'));
    }

    final history = <Map<String, String>>[
      {'role': 'system', 'content': _systemPrompt()},
      {'role': 'user', 'content': task},
    ];

    for (var i = 1; i <= maxSteps; i++) {
      if (_stopRequested) {
        await cu.suspend('user_stop');
        return _emit(ComputerUseStep(
            index: i, think: '使用者喊停', action: 'fail', ok: false,
            error: 'stopped_by_user'));
      }

      // 1. 眼睛：截圖（錯誤=降級續跑，模型仍有 AX/歷史可用）
      final shotPath = await _captureFrontmost();
      if (shotPath != null) {
        history.add({'role': 'user', 'content': 'SCREENSHOT:$shotPath'});
      }

      // 2. 大腦：問下一步（含 AX 樹摘要）
      final axSummary = await _axSummary();
      if (axSummary != null) {
        history.add({'role': 'user', 'content': 'AX_TREE:$axSummary'});
      }

      final Map<String, dynamic> decision;
      try {
        decision = await _think(history);
      } catch (e) {
        await cu.suspend('brain_error');
        return _emit(ComputerUseStep(
            index: i, think: '模型呼叫失敗', action: 'fail', ok: false,
            error: e.toString()));
      }

      final action = decision['action'] as String? ?? 'fail';
      final think = decision['think'] as String? ?? '';

      // 3. 終止條件
      if (action == 'done' || action == 'fail') {
        await cu.disarm();
        return _emit(ComputerUseStep(
            index: i, think: think, action: action,
            ok: action == 'done',
            error: action == 'fail' ? (decision['reason'] as String?) : null));
      }

      // 4. 手：執行動作
      final ok = await _act(decision);
      history.add({
        'role': 'assistant',
        'content': jsonEncode(decision),
      });
      history.add({
        'role': 'user',
        'content': ok ? 'ACTION_OK' : 'ACTION_FAILED(gate/protected)',
      });

      _emit(ComputerUseStep(
          index: i, think: think, action: action,
          target: decision as Map<String, dynamic>?,
          screenshotPath: shotPath, ok: ok));
    }

    // 步數用盡
    await cu.suspend('max_steps');
    return _emit(ComputerUseStep(
        index: maxSteps, think: '超過最大步數', action: 'fail', ok: false,
        error: 'max_steps'));
  }

  // ---- 眼睛 ----

  Future<String?> _captureFrontmost() async {
    try {
      final wins = await _screen.invokeMethod('listWindows') as List;
      if (wins.isEmpty) return null;
      // 找前景（onScreen 且最上層）視窗；取第一個可用即可
      final w = wins.first as Map;
      final r = await _screen.invokeMethod('captureWindow', {
        'windowId': w['windowId'],
      }) as Map;
      return r['path'] as String?;
    } on PlatformException {
      return null;
    }
  }

  Future<String?> _axSummary() async {
    final tree = await ComputerUseService.instance.windowTree(maxDepth: 3);
    if (tree == null) return null;
    try {
      return jsonEncode(tree).length > 4000
          ? jsonEncode(tree).substring(0, 4000)
          : jsonEncode(tree);
    } catch (_) {
      return null;
    }
  }

  // ---- 大腦 ----

  String _systemPrompt() => '''
你是一個電腦操作代理，透過滑鼠與鍵盤完成使用者的任務。
每一步你會收到：螢幕截圖路徑（SCREENSHOT:開頭）與 UI 樹摘要（AX_TREE:開頭）。
你必須只回覆一個 JSON 物件，不要任何其他文字：
{"think":"一句話說明你看到什麼與打算做什麼",
 "action":"click|type|scroll|drag|done|fail",
 "x":數字,"y":數字,"text":"要打的字","dx":數字,"dy":數字,
 "fromX":數字,"fromY":數字,"toX":數字,"toY":數字,
 "reason":"action=fail時的失敗原因"}
規則：
- 座標使用 AX_TREE 內 bounds 的全域座標（螢幕絕對座標）
- 任務完成就回 done；無法完成就回 fail 並給 reason
- 不確定時先回觀察步驟。**不可**亂點。
''';

  Future<Map<String, dynamic>> _think(List<Map<String, String>> history) async {
    final uri = Uri.parse('${brain.baseUrl}/chat/completions');
    final req = await _http.postUrl(uri)
      ..headers.contentType = ContentType.json;
    if (brain.apiKey != null && brain.apiKey!.isNotEmpty) {
      req.headers.set('Authorization', 'Bearer ${brain.apiKey}');
    }
    // 截圖路徑以文字描述（最小閉環用；多模態直接傳 image_url 是 P1b 增強）
    final msgs = history
        .map((m) => {
              'role': m['role'],
              'content': m['content'],
            })
        .toList();
    req.write(jsonEncode({
      'model': brain.model,
      'messages': msgs,
      'temperature': 0,
    }));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != 200) {
      throw Exception('brain ${resp.statusCode}: ${body.substring(0, body.length > 300 ? 300 : body.length)}');
    }
    final content =
        (jsonDecode(body)['choices'][0]['message']['content'] as String?) ?? '';
    return _parseDecision(content);
  }

  Map<String, dynamic> _parseDecision(String raw) {
    // 容錯：模型回覆可能包 markdown code fence
    var s = raw.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(s);
    if (fence != null) s = fence.group(1)!.trim();
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start >= 0 && end > start) s = s.substring(start, end + 1);
    return jsonDecode(s) as Map<String, dynamic>;
  }

  // ---- 手 ----

  Future<bool> _act(Map<String, dynamic> d) async {
    final cu = ComputerUseService.instance;
    switch (d['action'] as String?) {
      case 'click':
        return cu.click((d['x'] as num?)?.toDouble() ?? 0,
            (d['y'] as num?)?.toDouble() ?? 0);
      case 'type':
        final typed = await cu.typeText(d['text'] as String? ?? '');
        return typed;
      case 'scroll':
        return cu.scroll((d['dx'] as num?)?.toDouble() ?? 0,
            (d['dy'] as num?)?.toDouble() ?? 0);
      case 'drag':
        return cu.drag(
          (d['fromX'] as num?)?.toDouble() ?? 0,
          (d['fromY'] as num?)?.toDouble() ?? 0,
          (d['toX'] as num?)?.toDouble() ?? 0,
          (d['toY'] as num?)?.toDouble() ?? 0,
        );
      default:
        return false;
    }
  }

  ComputerUseStep _emit(ComputerUseStep s) {
    _stepsController.add(s);
    return s;
  }

  void dispose() {
    _stepsController.close();
    _http.close();
  }
}
