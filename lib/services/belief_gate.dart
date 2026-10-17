// M3 第二刀——信念證據門檻（2026-10-14）
//
// 藍圖（docs/WEAVE_MAP_V2.md M3）：信念寫入證據門檻——
//   L4 環境信念 ≥3 次一致證據才可寫入；L10 手動。
//
// 現況（偵察實錄）：MemoryLayerService.write() 是 L4 唯一寫入函式，
// 目前**零門檻**——任何人任何時候都能寫 L4。L4 現有 30 筆全是遷移/課程匯入。
//
// 本檔：信念守門員（BeliefGate）。掛在 write() 前面：
//   1. L4 寫入需「證據」：同一信念斷言已有 ≥N 次獨立證據（correction_events
//      的 factual 糾正、或既有 L4/L5 條目的文字一致性）
//   2. 證據來源可擴充：目前支援 correction_events（M3 第一刀）＋同層複誦
//   3. 手動通道：Blue 明示寫入（manualOverride）永遠放行——L10 精神
//   4. 拒絕可回溯：每次拒絕落盤 belief_gate_log，供事後審計

import 'package:flutter/foundation.dart';
import 'brain_container/brain_container_service.dart';
import 'brain_container/brain_database.dart';

class BeliefGate {
  static final BeliefGate _instance = BeliefGate._();
  static BeliefGate get instance => _instance;
  BeliefGate._();

  /// L4 寫入需要的獨立證據次數（藍圖：≥3 次一致證據）
  static const int l4RequiredEvidence = 3;

  bool _tableReady = false;

  /// 判定一條 L4 信念能否寫入。
  /// [assertion] 信念斷言（title 或核心句）
  /// [manualOverride] Blue 明示寫入＝直接放行（L10 精神：手動最高）
  /// [turnId] [小葵 2026-10-15 T1/D4] 信念產生輪的鑰匙——拒絕記錄可 join event_ledger
  Future<BeliefGateVerdict> checkL4({
    required String assertion,
    bool manualOverride = false,
    String? turnId,
  }) async {
    if (manualOverride) {
      return BeliefGateVerdict(
          allowed: true, reason: 'manual_override', evidenceCount: -1);
    }
    try {
      if (!BrainContainerService.instance.isInitialized) {
        // DB 還沒好——保守放行（不能因為守門員故障擋死所有寫入）
        return BeliefGateVerdict(
            allowed: true, reason: 'db_not_ready_fallback', evidenceCount: 0);
      }
      final db = BrainDatabase.instance.db;
      await _ensureTable(db);

      // 證據源1：correction_events 的 factual 糾正，內容與斷言相似
      // （同主題的糾正≥N 次＝Blue 反覆糾正同一件事＝強證據）
      final correctionRows = db.select('''
        SELECT user_text FROM correction_events
        WHERE kind = 'factual'
        ORDER BY created_at DESC LIMIT 200
      ''');
      int matches = 0;
      final key = _keywords(assertion);
      for (final r in correctionRows) {
        final t = (r['user_text'] as String?) ?? '';
        if (_keywordsOverlap(key, _keywords(t))) matches++;
      }

      if (matches >= l4RequiredEvidence) {
        return BeliefGateVerdict(
            allowed: true,
            reason: 'correction_evidence',
            evidenceCount: matches);
      }

      // 證據源2：L4/L5 既有條目複誦同一斷言（獨立來源寫過同樣的事）
      final layerRows = db.select('''
        SELECT title, content FROM agent_memories
        WHERE layer IN ('L4','L5') AND is_archived = 0 LIMIT 500
      ''');
      int echoes = 0;
      for (final r in layerRows) {
        final txt = '${r['title'] ?? ''} ${r['content'] ?? ''}';
        if (_keywordsOverlap(key, _keywords(txt))) echoes++;
      }

      final total = matches + echoes;
      if (total >= l4RequiredEvidence) {
        return BeliefGateVerdict(
            allowed: true, reason: 'layer_echo', evidenceCount: total);
      }

      // 拒絕——落盤供審計＋回溯
      // [小葵 2026-10-15 T1] 冪等補欄（舊表無 turn_id）
      final bgCols = db.select('PRAGMA table_info(belief_gate_log)');
      final bgHasTurn =
          bgCols.any((c) => c['name'] == 'turn_id');
      if (!bgHasTurn) {
        db.execute('ALTER TABLE belief_gate_log ADD COLUMN turn_id TEXT');
      }
      db.execute(
        'INSERT INTO belief_gate_log (assertion, evidence_count, created_at, turn_id) VALUES (?, ?, ?, ?)',
        [assertion, total, DateTime.now().millisecondsSinceEpoch, turnId],
      );
      return BeliefGateVerdict(
          allowed: false, reason: 'insufficient_evidence', evidenceCount: total);
    } catch (e) {
      // 守門員故障≠擋死寫入（保守放行但記錄）
      debugPrint('[BeliefGate] 檢查失敗（保守放行）：$e');
      return BeliefGateVerdict(
          allowed: true, reason: 'gate_error_fallback', evidenceCount: 0);
    }
  }

  /// 斷言關鍵詞抽取（去停用詞、取實詞）
  /// 簡版：中文取 2+ 字詞塊；英文/數字 token。
  /// @visibleForTesting 透過 debugKeywords 暴露純邏輯供測試。
  static Set<String> _keywords(String text) {
    // 注意：Dart RegExp 的 \W 不認 Unicode（中文＝非單詞字符會被清掉）——
    // 用白名單反取：保留中文區段、英數、空格，其餘當分隔符。
    final t = text
        .replaceAll(RegExp(r'[^\u4e00-\u9fff a-zA-Z0-9]+'), ' ')
        .trim()
        .toLowerCase();
    final out = <String>{};
    // 中文連續塊切 2-gram
    for (final m in RegExp(r'[\u4e00-\u9fff]{2,}').allMatches(t)) {
      final s = m.group(0)!;
      if (s.length <= 3) {
        out.add(s);
      } else {
        for (var i = 0; i + 2 <= s.length; i++) {
          out.add(s.substring(i, i + 2));
        }
      }
    }
    // 英數 token
    for (final m in RegExp(r'[a-z0-9]{2,}').allMatches(t)) {
      out.add(m.group(0)!);
    }
    return out;
  }

  /// 兩組關鍵詞重疊度（Jaccard ≥0.3 視為同主題）
  static bool _keywordsOverlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return false;
    final inter = a.intersection(b).length;
    final union = a.union(b).length;
    return inter / union >= 0.3;
  }

  // ── 測試通道（純邏輯，不碰 DB）──
  static Set<String> debugKeywords(String text) => _keywords(text);
  static bool debugOverlap(Set<String> a, Set<String> b) =>
      _keywordsOverlap(a, b);

  Future<void> _ensureTable(dynamic db) async {
    if (_tableReady) return;
    db.execute('''
      CREATE TABLE IF NOT EXISTS belief_gate_log (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        assertion       TEXT NOT NULL,
        evidence_count  INTEGER NOT NULL,
        created_at      INTEGER NOT NULL,
        turn_id         TEXT  -- [小葵 2026-10-15 T1/D4] 信念產生輪的鑰匙（M3 回溯撤銷用）
      )
    ''');
    _tableReady = true;
  }
}

class BeliefGateVerdict {
  final bool allowed;
  final String reason; // manual_override / correction_evidence / layer_echo / insufficient_evidence / *_fallback
  final int evidenceCount;
  const BeliefGateVerdict({
    required this.allowed,
    required this.reason,
    required this.evidenceCount,
  });
}

/// L4 寫入被拒——呼叫端可捕獲，降級寫 L7（專案冷存）或提示
class BeliefGateRejectedError implements Exception {
  final BeliefGateVerdict verdict;
  const BeliefGateRejectedError(this.verdict);
  @override
  String toString() =>
      'BeliefGateRejectedError(${verdict.reason}, evidence=${verdict.evidenceCount}/3)';
}
