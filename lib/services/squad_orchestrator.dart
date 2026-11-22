import '../models/conversation.dart';

/// [SPEC §9.2 對話頁v2 步驟3] 「開小隊」編排器
///
/// Claude 2.0 總管-小隊模式的我們版本：
/// 使用者在母對話說「開小隊：A、B、C」→ 自動建 N 個子對話
/// （parentConversationId 掛母、context 注入 brief）→ 母對話插系統卡。
///
/// v1 為**明示指令制**（deterministic，不靠 LLM 判斷意圖、零誤觸）：
///   開小隊：菜單、採買、預算
///   開三個小隊：A、B、C（數字需與項目數一致，否則以項目為準）
/// 未來 v2 再加自然語言分派（走 LLM 判斷，另一條路）。
class SquadOrchestrator {
  /// 解析「開小隊」指令。非指令 → null；指令但沒有任何隊名 → 空列表（呼叫端報錯）。
  static SquadDirective? parseDirective(String text) {
    final t = text.trim();
    // 明示開頭：開小隊 / 開N個小隊 / 開小隊：
    // dotAll：隊名可換行分隔（開小隊：\n菜單\n採買）
    final m = RegExp(
      r'^開(小隊|(\d+)個小隊|幾個小隊)\s*[:：]?\s*(.*)$',
      dotAll: true,
    ).firstMatch(t);
    if (m == null) return null;
    final claimed = m.group(2) != null ? int.tryParse(m.group(2)!) : null;
    final namesRaw = m.group(3) ?? '';
    // 隊名分隔：頓號/逗號/冒號後分行也常見——支援 、,， 與換行
    final names = namesRaw
        .split(RegExp(r'[、,，\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return SquadDirective(claimedCount: claimed, squadNames: names);
  }

  /// 指令是否完整可執行（有隊名；宣稱數與實名數衝突時以實名為準並標記）。
  static bool isExecutable(SquadDirective d) => d.squadNames.isNotEmpty;

  /// 建 N 個子對話（不存檔——呼叫端負責 ConversationStore.save 與 UI 狀態）。
  /// 每個子對話：parentConversationId 掛母、context 首則訊息注入母對話摘要＋隊任務。
  static List<Conversation> buildSquadConversations({
    required Conversation parent,
    required List<String> squadNames,
  }) {
    final now = DateTime.now();
    final parentDigest = _digest(parent);
    return [
      for (final (i, name) in squadNames.indexed)
        Conversation(
          id:
              'squad-${parent.id}-$i-${now.millisecondsSinceEpoch}',
          title: name,
          createdAt: now,
          updatedAt: now,
          messages: [
            Message(
              id: 'squad-brief-$i-${now.millisecondsSinceEpoch}',
              role: 'user',
              content: '【小隊任務：$name】\n'
                  '你隸屬對話「${parent.title}」的小隊，只負責「$name」這一路。\n'
                  '母對話摘要：$parentDigest\n'
                  '完成後把結論回報母對話。',
              timestamp: now,
            ),
          ],
          companionId: parent.companionId,
          parentConversationId: parent.id,
        ),
    ];
  }

  /// 母對話的「小隊已出動」系統卡。
  static Message buildSpawnCard({
    required List<Conversation> squads,
    required DateTime at,
  }) {
    final names = squads.map((s) => '• ${s.title}').join('\n');
    return Message(
      id: 'squad-card-${at.millisecondsSinceEpoch}',
      role: 'assistant',
      content: '🚩 已開 ${squads.length} 個小隊，各自獨立處理：\n$names\n'
          '（左欄對話列表中已縮排在母對話下；點入即可對該小隊下指令）',
      timestamp: at,
      metadata: const {
        'kind': 'squad_spawn_card',
        'squadIds': [],
      },
    );
  }

  /// [觸發線 2026-11-17] 該不該插回報卡：小隊判定（id 以 'squad-' 開頭＋掛母）
  /// ＋最後一則訊息是 assistant 回覆（小隊剛說完話＝完成回報時機）。
  static bool shouldReport(Conversation squad) =>
      squad.id.startsWith('squad-') &&
      squad.parentConversationId != null &&
      squad.messages.isNotEmpty &&
      squad.messages.last.role == 'assistant';

  /// 回報卡的去重鍵：同一則 assistant 回覆→同一 id（防重複插卡）。
  /// 取小隊最後一則 assistant 訊息 id；全無 assistant 訊息→後綴 no-assistant。
  static String reportCardId(Conversation squad) {
    for (int i = squad.messages.length - 1; i >= 0; i--) {
      if (squad.messages[i].role == 'assistant') {
        return 'squad-report-${squad.id}-${squad.messages[i].id}';
      }
    }
    return 'squad-report-${squad.id}-no-assistant';
  }

  /// 小隊的「回報」系統卡（插回母對話）——v1 由小隊對話完成回覆時觸發。
  /// [觸發線 2026-11-17] 可选 id：呼叫端傳 reportCardId() 鎖去重鍵；
  /// 不傳→維持舊行為（時間戳 id，向後相容）。
  static Message buildReportCard({
    required Conversation squad,
    required String summary,
    required DateTime at,
    String? id,
  }) {
    return Message(
      id: id ?? 'squad-report-${squad.id}-${at.millisecondsSinceEpoch}',
      role: 'assistant',
      content: '✓ 小隊「${squad.title}」回報：$summary',
      timestamp: at,
      metadata: {'kind': 'squad_report_card', 'squadId': squad.id},
    );
  }

  /// 母對話摘要（前 5 則、每則 60 字）——子對話的共享 context。
  static String _digest(Conversation parent) {
    if (parent.messages.isEmpty) return '（母對話尚無內容）';
    final recent = parent.messages.length > 5
        ? parent.messages.sublist(parent.messages.length - 5)
        : parent.messages;
    return recent
        .map((m) => '${m.role == "user" ? "使用者" : "AI"}：'
            '${m.content.length > 60 ? m.content.substring(0, 60) : m.content}')
        .join('／');
  }
}

/// 解析結果：宣稱數（可空）＋實際隊名列表。
class SquadDirective {
  final int? claimedCount;
  final List<String> squadNames;
  const SquadDirective({this.claimedCount, required this.squadNames});

  /// 宣稱數與實名數不一致（供 UI 提醒；以實名為準）。
  bool get countMismatch =>
      claimedCount != null && claimedCount != squadNames.length;
}
