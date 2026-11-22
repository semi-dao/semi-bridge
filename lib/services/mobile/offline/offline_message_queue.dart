// 離線訊息佇列（Offline Message Queue）——手機版離線排隊契約
// [T4 2026-11-09] 依據 BRIDGE_MOBILE_SPEC.md v0.5 §7 離線行為拍板（Blue 2026-10-30）
//
// SPEC 條款 3 原文：「聊天輸入框保留但標『離線中，訊息重連後送出』（排隊不吞）」
// SPEC 條款 4 原文：「離線排隊的訊息，重連後依序自動送出、不吞訊息」
//
// ★ 設計紀律（排隊不吞）：
//   1. FIFO——先入隊先送出，順序即對話順序，不得重排。
//   2. flush 失敗者**留在佇列**，且後續訊息**不越過它**（順序必須維持）。
//   3. flush 過程中送出回呼丟例外 → 該則保留，不得當成已送出。
//   4. 只有「實際送出成功」才從佇列移除。
//
// 純函數核心：無 UI、無網路、無 DB——可獨立測試。

/// 一則待送訊息。
class QueuedMessage {
  /// 訊息本文。
  final String text;

  /// 入隊時刻（本地時區）。
  final DateTime queuedAt;

  /// 單調遞增序號——保證 FIFO 順序（即使同毫秒入隊也不會亂序）。
  final int sequence;

  const QueuedMessage({
    required this.text,
    required this.queuedAt,
    required this.sequence,
  });

  @override
  String toString() =>
      'QueuedMessage(#$sequence, ${queuedAt.toIso8601String()}, "$text")';
}

/// 送出結果——[sendCallback] 回傳 true 代表成功。
typedef MessageSender = Future<bool> Function(QueuedMessage message);

/// flush 結果摘要。
class FlushResult {
  /// 成功送出的訊息（依送出順序）。
  final List<QueuedMessage> sent;

  /// 失敗的那一則（成功送出到失敗點為止；null 代表全部成功）。
  final QueuedMessage? failed;

  /// 失敗後仍留在佇列的訊息（含失敗者，依佇列順序）。
  final List<QueuedMessage> remaining;

  const FlushResult({
    required this.sent,
    required this.failed,
    required this.remaining,
  });

  /// 是否全部送完（無失敗者且佇列已清空）。
  bool get isComplete => failed == null && remaining.isEmpty;

  /// 「本次沒有送出任何東西」的結果（未觸發 flush 時使用）。
  factory FlushResult.none({List<QueuedMessage> remaining = const []}) =>
      FlushResult(
        sent: const [],
        failed: null,
        remaining: List.unmodifiable(remaining),
      );
}

/// 離線訊息佇列——FIFO、flush 依序、失敗保留不吞。
class OfflineMessageQueue {
  final List<QueuedMessage> _items = [];
  int _sequence = 0;

  /// 目前佇列中的訊息數。
  int get length => _items.length;

  /// 佇列是否為空。
  bool get isEmpty => _items.isEmpty;

  /// 佇列是否非空。
  bool get isNotEmpty => _items.isNotEmpty;

  /// 目前佇列內容（依 FIFO 順序；唯讀快照）。
  List<QueuedMessage> get pending => List.unmodifiable(_items);

  /// 入隊一則訊息（追加到佇列尾端 → FIFO）。
  ///
  /// [queuedAt] 可注入（測試用固定時刻）；預設取當下。
  void enqueue(String text, {DateTime? queuedAt}) {
    _items.add(QueuedMessage(
      text: text,
      queuedAt: queuedAt ?? DateTime.now(),
      sequence: _sequence++,
    ));
  }

  /// 取出全部訊息並清空佇列（依 FIFO 順序）。
  List<QueuedMessage> dequeueAll() {
    final taken = List<QueuedMessage>.from(_items);
    _items.clear();
    return taken;
  }

  /// 清空佇列。
  void clear() => _items.clear();

  /// 依序送出所有訊息。
  ///
  /// 規則：
  /// 1. 依 FIFO 順序逐則呼叫 [sendCallback]。
  /// 2. 成功 → 移出佇列、記入 [FlushResult.sent]。
  /// 3. 失敗（回傳 false）或拋例外 → 該則與其後所有訊息**留在佇列**，
  ///    並停止本次 flush（順序不亂）。
  Future<FlushResult> flush(MessageSender sendCallback) async {
    final sent = <QueuedMessage>[];
    QueuedMessage? failed;

    while (_items.isNotEmpty) {
      final head = _items.first;
      bool ok;
      try {
        ok = await sendCallback(head);
      } catch (_) {
        // 通道炸掉 → 該則保留，不得當成已送出。
        ok = false;
      }

      if (!ok) {
        failed = head;
        break;
      }

      _items.removeAt(0);
      sent.add(head);
    }

    return FlushResult(
      sent: List.unmodifiable(sent),
      failed: failed,
      remaining: List.unmodifiable(_items),
    );
  }
}
