// M3 回饋閉環——修正捕手（2026-10-14 開工，Blue 令「開M3」）
//
// 藍圖（docs/WEAVE_MAP_V2.md M3）：Blue 修正自動成標籤回流訓練資料。
// 本檔：對話中自然語言糾正信號的偵測＋落盤。UI 點擊回饋（useful/irrelevant）
// 已有管線（memory_store.dart）；「不對，應該是…」這類對話內糾正是本檔的職責。
//
// 設計原則：
// 1. 寧漏勿誤——偵測器只抓高信心模式，寧可漏掉模糊糾正也不誤標正常對話
//    （誤標會污染訓練資料，比漏掉更糟）
// 2. 落盤 raw＋標籤分離——原始對話片段永遠保留，標籤可重跑重判
// 3. 只記不動——捕手不修改任何記憶/信念，只記錄事件（寫入/熔斷是後續刀）

import 'package:flutter/foundation.dart';
import 'brain_container/brain_container_service.dart';
import 'brain_container/brain_database.dart';

/// 糾正信號類型（標籤）
enum CorrectionKind {
  factual, // 事實糾正：「不對，那是 X」「應該是」
  preference, // 偏好糾正：「不要這樣說」「我不喜歡」
  instruction, // 指令重申：「我說過要」「跟你講過幾次」
  boundary, // 邊界糾正：「不要動」「別碰」
}

class CorrectionCatcher {
  static final CorrectionCatcher _instance = CorrectionCatcher._();
  static CorrectionCatcher get instance => _instance;
  CorrectionCatcher._();

  bool _tableReady = false;

  // ── 高信心糾正模式（寧漏勿誤：每條都要「幾乎不可能是正常對話」）──
  // 命中即落盤；kind 由模式分類。
  static const Map<CorrectionKind, List<String>> _patterns = {
    CorrectionKind.factual: [
      '不對，應該是', '不對，是', '不是，是', '搞錯了', '你記錯了', '記錯了，',
      '打錯了', '那不是', '不對啦', '錯了，',
    ],
    CorrectionKind.preference: [
      '不要這樣說', '我不喜歡你', '別用這種語氣', '不要叫我',
      '講白話', '說人話', '不要那麼',
    ],
    CorrectionKind.instruction: [
      '我說過', '跟你講過', '講了幾次', '我不是說', '就跟你說',
      '之前就告訴你',
    ],
    CorrectionKind.boundary: [
      '不要動我的', '別碰', '不准刪', '不要刪', '不准花', '不要自己',
    ],
  };

  /// 偵測一則使用者訊息。回傳 null＝非糾正；命中回（類型, 命中片段）。
  /// context：前一則 assistant 訊息（裁上下文用，可空）。
  static ({CorrectionKind kind, String hit})? detect(
      String userMessage, String? prevAssistantMessage) {
    final msg = userMessage.trim();
    if (msg.isEmpty || msg.length > 2000) return null; // 超長貼文不是糾正場景
    for (final e in _patterns.entries) {
      for (final p in e.value) {
        if (msg.contains(p)) {
          return (kind: e.key, hit: p);
        }
      }
    }
    return null;
  }

  /// 落盤一筆修正事件（冪等：同一訊息不重複記）。
  /// [conversationId]/[messageId] 用於回溯原文；[fullText] 保留原始訊息全文。
  Future<void> record({
    required String conversationId,
    required String messageId,
    required String userText,
    required String assistantContext,
    required CorrectionKind kind,
    required String hitPattern,
    String? refTurnId, // [小葵 2026-10-15 T1/D4] 被糾正輪的 turn_id（可空——舊路徑）
  }) async {
    try {
      if (!BrainContainerService.instance.isInitialized) return;
      final db = BrainDatabase.instance.db;

      if (!_tableReady) {
        await _ensureTable(db);
        _tableReady = true;
      }

      db.execute(
        'INSERT OR IGNORE INTO correction_events '
        '(id, conversation_id, message_id, kind, hit_pattern, user_text, assistant_context, created_at, ref_turn_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          messageId, // 冪等鍵：同一則訊息只記一次
          conversationId,
          messageId,
          kind.name,
          hitPattern,
          userText,
          assistantContext.length > 2000
              ? assistantContext.substring(0, 2000)
              : assistantContext,
          DateTime.now().millisecondsSinceEpoch,
          refTurnId, // [T1/D4]
        ],
      );
      debugPrint('[CorrectionCatcher] 捕獲 ${kind.name} 糾正：${userText.length} 字（$hitPattern）');
    } catch (e) {
      // 只記不動原則：捕手失敗絕不影響對話主流程
      debugPrint('[CorrectionCatcher] 落盤失敗（不影響對話）：$e');
    }
  }

  static Future<void> _ensureTable(dynamic db) async {
    db.execute('''
      CREATE TABLE IF NOT EXISTS correction_events (
        id                 TEXT PRIMARY KEY,
        conversation_id    TEXT NOT NULL,
        message_id         TEXT NOT NULL,
        kind               TEXT NOT NULL,
        hit_pattern        TEXT NOT NULL,
        user_text          TEXT NOT NULL,
        assistant_context  TEXT NOT NULL DEFAULT '',
        created_at         INTEGER NOT NULL,
        ref_turn_id        TEXT  -- [小葵 2026-10-15 T1/D4] 指向被糾正那輪的 event_ledger turn_id
      )
    ''');
    // [小葵 2026-10-15 T1] 舊表冪等補欄
    final cols = db.select('PRAGMA table_info(correction_events)');
    if (!cols.any((c) => c['name'] == 'ref_turn_id')) {
      db.execute(
          'ALTER TABLE correction_events ADD COLUMN ref_turn_id TEXT');
    }
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_correction_conv ON correction_events(conversation_id)');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_correction_kind ON correction_events(kind)');
  }
}
