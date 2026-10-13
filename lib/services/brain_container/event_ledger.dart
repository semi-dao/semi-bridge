import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import 'brain_database.dart';

/// M0 交付物 1：append-only 事件日誌（event ledger）v2
///
/// 每一輪對話/決策落一筆，hash chain 保不可竄改。
/// 使者反應（accepted/corrected/redone）以「反應事件」append 進鏈，
/// 不 UPDATE 任何列——徹底 append-only（Fable 驗收 v1 阻斷項修正）。
///
/// 單寫者假設：同一 isolate 內同步寫入（文件化；M0 不做跨程序鎖）。
/// 排序以 rowid 為唯一真相（不依賴時鐘）。
class EventLedger {
  EventLedger._(this._db);
  static final EventLedger instance = EventLedger._(
    BrainDatabase.instance.db,
  );

  /// 測試注入專用建構式（測試絕不碰真庫——R4 教訓）。
  @visibleForTesting
  EventLedger.forTest(Database db) : _db = db;

  Database _db;

  /// 覆寫 DB 連線（遷移後腦升級等場景；測試亦可用）。
  void rebind(Database db) {
    _db = db;
    _ensured = false;
    _ensuredV3 = false;
    _ensuredV4 = false;
  }

  bool _ensured = false;
  bool _ensuredV3 = false;
  bool _ensuredV4 = false;

  void _ensureTable() {
    if (!_ensured) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS event_ledger (
          rowid         INTEGER PRIMARY KEY AUTOINCREMENT,
          kind          TEXT NOT NULL DEFAULT 'turn',   -- turn / reaction
          turn_id       TEXT NOT NULL,
          ref_turn_id   TEXT,                            -- reaction 指向的 turn
          ts            INTEGER NOT NULL,
          input         TEXT,
          input_hash    TEXT,          -- v3: 完整 userMessage SHA-256（M3 歸因鍵）
          injected_ids  TEXT,          -- JSON array
          decision      TEXT,
          confidence    REAL,
          executor      TEXT,
          output        TEXT,
          user_reaction TEXT,
          meta          TEXT,          -- v4: JSON（latency_ms/dropped_count/k1_hits_n/k1_kept_n/embedding_ok/failure_reason）
          hash_prev     TEXT NOT NULL,
          hash_self     TEXT NOT NULL
        )
      ''');
      _db.execute(
        'CREATE INDEX IF NOT EXISTS idx_event_ledger_turn ON event_ledger(turn_id)',
      );
      _ensured = true;
    }
    if (!_ensuredV3) {
      // v3（Fable M0 複審建議②）：input_hash = 完整 userMessage 的 SHA-256。
      // M0 只填不存原文；M3 回饋閉環用它把 turn 對回原始輸入（穩定歸因鍵）。
      // 舊列為 NULL——verifyChain 對 NULL 一律重算 NULL，鏈不斷。
      final cols = _db.select('PRAGMA table_info(event_ledger)');
      final hasInputHash = cols.any((c) => c['name'] == 'input_hash');
      if (!hasInputHash) {
        _db.execute('ALTER TABLE event_ledger ADD COLUMN input_hash TEXT');
      }
      _ensuredV3 = true;
    }
    if (!_ensuredV4) {
      // v4 [小葵 2026-10-10 M1]（Fable delta）：注入觀測 meta 進鏈——
      // latency_ms / dropped_count / k1_hits_n / k1_kept_n / embedding_ok / failure_reason。
      // M0 時代 elapsed 只 print、droppedCount 只存在記憶體，「≤150ms」無證據。
      // 舊列為 NULL 維持 v3 形狀（與 input_hash 同款相容手法）。
      final cols = _db.select('PRAGMA table_info(event_ledger)');
      final hasMeta = cols.any((c) => c['name'] == 'meta');
      if (!hasMeta) {
        _db.execute('ALTER TABLE event_ledger ADD COLUMN meta TEXT');
      }
      _ensuredV4 = true;
    }
  }

  String? _lastHash() {
    final row = _db.select(
      'SELECT hash_self FROM event_ledger ORDER BY rowid DESC LIMIT 1',
    );
    return row.isEmpty ? null : row.first['hash_self'] as String;
  }

  String _hash({
    required String kind,
    required String turnId,
    String? refTurnId,
    required int ts,
    String? input,
    String? inputHash,
    List<String>? injectedIds,
    String? decision,
    double? confidence,
    String? executor,
    String? output,
    String? userReaction,
    String? meta,
    required String hashPrev,
  }) {
    // v2→v3→v4 相容：input_hash/meta 非空才入 payload——舊列（NULL）維持
    // 舊形狀，舊 hash 依然可驗；新列（非空）用新形狀。竄改（改值或拔成
    // NULL）都會導致驗證失敗。
    final payloadMap = <String, dynamic>{
      'kind': kind,
      'turn_id': turnId,
      'ref_turn_id': refTurnId,
      'ts': ts,
      'input': input,
      'injected_ids': injectedIds ?? const [],
      'decision': decision,
      'confidence': confidence,
      'executor': executor,
      'output': output,
      'user_reaction': userReaction,
      'hash_prev': hashPrev,
    };
    if (inputHash != null) payloadMap['input_hash'] = inputHash;
    if (meta != null) payloadMap['meta'] = meta;
    final payload = jsonEncode(payloadMap);
    return sha256.convert(utf8.encode(payload)).toString();
  }

  /// 落一筆對話輪次事件。回傳 hash_self。
  String appendTurn({
    required String turnId,
    required String input,
    String? inputHash,
    List<String> injectedIds = const [],
    String? decision,
    double? confidence,
    String? executor,
    String? output,
    Map<String, dynamic>? meta,
  }) {
    _ensureTable();
    final prev = _lastHash() ?? 'GENESIS';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final metaJson = meta == null ? null : jsonEncode(meta);
    final self = _hash(
      kind: 'turn', turnId: turnId, ts: ts, input: input,
      inputHash: inputHash,
      injectedIds: injectedIds, decision: decision,
      confidence: confidence, executor: executor, output: output,
      meta: metaJson,
      hashPrev: prev,
    );
    _db.execute(
      'INSERT INTO event_ledger (kind, turn_id, ts, input, input_hash, injected_ids, decision, confidence, executor, output, meta, hash_prev, hash_self) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [ 'turn', turnId, ts, input, inputHash, jsonEncode(injectedIds), decision,
        confidence, executor, output, metaJson, prev, self ],
    );
    return self;
  }

  /// 使者反應以新事件 append（不 UPDATE，鏈不斷）。
  /// 同一 turn 的首次反應有效；重複反應回 false。
  bool appendReaction(String turnId, String reaction) {
    _ensureTable();
    final dup = _db.select(
      "SELECT 1 FROM event_ledger WHERE kind='reaction' AND ref_turn_id = ? LIMIT 1",
      [turnId],
    );
    if (dup.isNotEmpty) return false;
    final prev = _lastHash() ?? 'GENESIS';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final self = _hash(
      kind: 'reaction', turnId: '${turnId}_r', refTurnId: turnId,
      ts: ts, userReaction: reaction, hashPrev: prev,
    );
    _db.execute(
      "INSERT INTO event_ledger (kind, turn_id, ref_turn_id, ts, user_reaction, hash_prev, hash_self) "
      "VALUES ('reaction', ?, ?, ?, ?, ?, ?)",
      ['${turnId}_r', turnId, ts, reaction, prev, self],
    );
    return true;
  }

  /// 驗證整條鏈（rowid 單一排序）。回傳 (是否有效, 筆數)。
  /// 已知限制：無外部錨點的 hash chain 無法偵測尾端截斷（文件化）。
  (bool, int) verifyChain() {
    _ensureTable();
    final rows = _db.select('SELECT * FROM event_ledger ORDER BY rowid ASC');
    String expectPrev = 'GENESIS';
    for (final r in rows) {
      if (r['hash_prev'] != expectPrev) return (false, rows.length);
      final calc = _hash(
        kind: r['kind'],
        turnId: r['turn_id'],
        refTurnId: r['ref_turn_id'],
        ts: r['ts'],
        input: r['input'],
        inputHash: r['input_hash'],
        injectedIds:
            (jsonDecode(r['injected_ids'] as String? ?? '[]') as List)
                .cast<String>(),
        decision: r['decision'],
        confidence: r['confidence'],
        executor: r['executor'],
        output: r['output'],
        userReaction: r['user_reaction'],
        meta: r['meta'],
        hashPrev: r['hash_prev'],
      );
      if (calc != r['hash_self']) return (false, rows.length);
      expectPrev = r['hash_self'] as String;
    }
    return (true, rows.length);
  }

  /// M3 用：依信心區間統計線上正確率（reaction join turn）
  List<({double bucket, int n, double acc})> onlineCalibration() {
    _ensureTable();
    final rows = _db.select('''
      SELECT t.confidence AS conf, r.user_reaction AS reaction
      FROM event_ledger t
      JOIN event_ledger r
        ON r.kind = 'reaction' AND r.ref_turn_id = t.turn_id
      WHERE t.kind = 'turn' AND t.confidence IS NOT NULL
    ''');
    final buckets = <double, List<int>>{};
    for (final r in rows) {
      final b = ((r['conf'] as double) * 10).floor() / 10.0;
      final ok = (r['reaction'] == 'accepted') ? 1 : 0;
      buckets.putIfAbsent(b, () => [0, 0]);
      buckets[b]![0] += ok;
      buckets[b]![1] += 1;
    }
    return buckets.entries
        .map((e) => (
              bucket: e.key,
              n: e.value[1],
              acc: e.value[1] == 0 ? 0.0 : e.value[0] / e.value[1],
            ))
        .toList()
      ..sort((a, b) => a.bucket.compareTo(b.bucket));
  }
}
