import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../controllers/chat_controller.dart';
import '../desktop_bridge_gateway_protocol.dart';

/// [S4 2026-11-10] 手機聊天直送 handler——taskType 前綴 `chat`。
///
/// 手機送來的訊息經 gateway taskRun（過白名單 `chat.send`）→
/// 注入桌面活躍 ChatController.sendDirectMessage——與 MCP 注入同一條路，
/// 人格注入、付費閘門、對話通知全部沿用，零新通道。
///
/// 誠實鐵則：controller 不可用 → 任務失敗回報，不假成功。
class ChatRelayHandler implements GatewayTaskHandler {
  final ValueChanged<String>? onRelayed;

  ChatRelayHandler({this.onRelayed});

  /// 注入點（由 bridge_desktop_screen 接線；測試可替換）。
  static ChatController? Function()? controllerProvider;

  @override
  String startTask({
    required String taskType,
    required Map<String, dynamic> payload,
    required void Function(double progress, String message) onProgress,
    required void Function(bool success, Map<String, dynamic> result, String? error) onComplete,
    required void Function(String reason, Map<String, dynamic> context) onAwaitingConfirmation,
  }) {
    final taskId = 'chat-${DateTime.now().millisecondsSinceEpoch}';
    final text = (payload['text'] as String?)?.trim() ?? '';

    if (text.isEmpty) {
      onComplete(false, const {}, 'empty message');
      return taskId;
    }

    final controller = controllerProvider?.call();
    if (controller == null) {
      onComplete(false, const {}, 'no active chat controller');
      return taskId;
    }

    unawaited(
      controller.sendDirectMessage(text).then((_) {
        onRelayed?.call(text);
        onProgress(1.0, '已送達');
        onComplete(true, const {'relayed': true}, null);
      }).catchError((Object e) {
        onComplete(false, const {}, e.toString());
      }),
    );
    return taskId;
  }

  @override
  bool cancelTask(String taskId) => false; // 聊天送出不可取消（瞬時任務）
}

/// 桌面端接線 helper：把 controllerProvider 指到 static 真相源。
void wireChatRelay({required ChatController? Function() provider}) {
  ChatRelayHandler.controllerProvider = provider;
}
