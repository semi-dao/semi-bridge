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
    _ensuredV5 = false;
  }

  bool _ensured = false;
  bool _ensuredV3 = false;
  bool _ensuredV4 = false;
  bool _ensuredV5 = false;
  bool _ensuredV6 = false; // [T12-④] conversation_id 欄遷移旗

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
    if (!_ensuredV5) {
      // v5 [小葵 2026-10-15 T2/D2] 信心雙軌制：
      // confidence＝K1「要不要查記憶」的信心（原有，誤用中）；
      // answer_confidence＝「回答正確性」信心（校準/熔斷/M6 修正率唯一吃的）。
      // 舊列 NULL＝尚未有來源；onlineCalibration 對 NULL 桶跳過（見下）。
      final cols = _db.select('PRAGMA table_info(event_ledger)');
      final hasAnsConf = cols.any((c) => c['name'] == 'answer_confidence');
      if (!hasAnsConf) {
        _db.execute('ALTER TABLE event_ledger ADD COLUMN answer_confidence REAL');
      }
      _ensuredV5 = true;
    }
    if (!_ensuredV6) {
      // v6 [T12-④ 2026-10-17] lastTurnId 帶對話歸屬——全域「最新一輪」
      // 在多對話並行時會指錯輪（A 對話的糾正掛到 B 對話的 turn 上）。
      // conversation_id 落欄；lastTurnId(conversationId) 過濾後回
      // 「該對話」最新一輪。舊列 NULL＝未標記（全域 fallback 行為保留）。
      final cols = _db.select('PRAGMA table_info(event_ledger)');
      final hasConv = cols.any((c) => c['name'] == 'conversation_id');
      if (!hasConv) {
        _db.execute(
            'ALTER TABLE event_ledger ADD COLUMN conversation_id TEXT');
        _db.execute(
            'CREATE INDEX IF NOT EXISTS idx_event_ledger_conv '
            'ON event_ledger(conversation_id)');
      }
      _ensuredV6 = true;
    }
  }

  String? _lastHash() {
    final row = _db.select(
      'SELECT hash_self FROM event_ledger ORDER BY rowid DESC LIMIT 1',
    );
    return row.isEmpty ? null : row.first['hash_self'] as String;
  }

  /// [小葵 2026-10-14 M3-第三刀] 最近一筆 turn 的 turn_id——
  /// 糾正→reaction 接線用（chat_controller 不必知道 turnId 生成細節）。
  /// [T12-④ 2026-10-17] 帶對話歸屬過濾——多對話並行時全域「最新一輪」
  /// 會指錯（A 對話的糾正掛到 B 的 turn）。帶 [conversationId] 時只回
  /// 該對話的最新一輪；不帶＝舊行為（全域最新，未標記歸屬的舊列相容）。
  String? lastTurnId({String? conversationId}) {
    if (conversationId != null) {
      final row = _db.select(
        "SELECT turn_id FROM event_ledger "
        "WHERE kind='turn' AND conversation_id = ? "
        "ORDER BY rowid DESC LIMIT 1",
        [conversationId],
      );
      if (row.isNotEmpty) return row.first['turn_id'] as String;
      // 該對話沒有標記過的輪——fallback 全域（未遷移的舊輪相容）
    }
    final row = _db.select(
      "SELECT turn_id FROM event_ledger WHERE kind='turn' ORDER BY rowid DESC LIMIT 1",
    );
    return row.isEmpty ? null : row.first['turn_id'] as String;
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
  /// [T11②+ 2026-10-17 Blue #4] 近 N 天逐輪記錄——儀表滾動列表資料源。
  /// 每筆：{ts, provider, model, is_local, unknown}。舊輪無 provider
  /// 標 unknown（誠實顯示，不猜）。
  List<Map<String, dynamic>> recentTurns({int days = 7}) {
    try {
      final db = _db;
      if (db == null) return [];
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .millisecondsSinceEpoch;
      final rows = db.select(
          "SELECT ts, meta FROM event_ledger WHERE kind = 'turn' AND ts >= ? ORDER BY ts DESC",
          [since]);
      final out = <Map<String, dynamic>>[];
      for (final r in rows) {
        Map<String, dynamic> meta = {};
        try {
          meta = (jsonDecode(r['meta'] as String) as Map).cast<String, dynamic>();
        } catch (_) {}
        out.add({
          'ts': r['ts'] as int,
          'provider': meta['provider'],
          'model': meta['model'],
          'is_local': meta['is_local'] == true,
          'unknown': !meta.containsKey('provider'),
        });
      }
      return out;
    } catch (e) {
      debugPrint('[EventLedger] recentTurns 失敗: $e');
      return [];
    }
  }

  /// [T11③ 2026-10-17] 修正率週報——correction_events / turns。
  /// 驗收：修正率三週遞減。無反應記錄時回 null（誠實：分母不足不硬算）。
  Map<String, dynamic>? correctionWeeklyReport({int weeks = 3}) {
    try {
      final db = _db;
      if (db == null) return null;
      final report = <String, dynamic>{'weeks': <Map<String, dynamic>>[]};
      final now = DateTime.now();
      for (var w = 0; w < weeks; w++) {
        // 本週窗口含 now（w=0 時 end=now+1s 防邊界漏掉剛發生的輪）
        final end = now.subtract(Duration(days: 7 * w)).add(const Duration(seconds: 1));
        final start = end.subtract(const Duration(days: 7));
        final turnsN = db.select(
            "SELECT COUNT(*) as n FROM event_ledger WHERE kind = 'turn' AND ts >= ? AND ts < ?",
            [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch]).first['n'] as int;
        var correctedN = 0;
        try {
          correctedN = db.select(
              "SELECT COUNT(*) as n FROM correction_events WHERE created_at >= ? AND created_at < ?",
              [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch]).first['n'] as int;
        } catch (_) {
          // 表不存在（早期 DB）——0
        }
        (report['weeks'] as List).add({
          'week_start': start.toIso8601String().substring(0, 10),
          'turns': turnsN,
          'corrected': correctedN,
          'rate': turnsN == 0 ? null : (correctedN / turnsN),
        });
      }
      return report;
    } catch (e) {
      debugPrint('[EventLedger] correctionWeeklyReport 失敗: $e');
      return null;
    }
  }

  /// [T11② 2026-10-17] 雲端率統計——近 N 天 turn 的 provider 分佈。
  /// 回傳 {total, local, cloud, by_provider}。無 meta 的舊輪次不計入
  /// （誠實：分母=有路由記錄的輪次，不是全部輪次）。
  Map<String, dynamic> cloudRateStats({int days = 7}) {
    try {
      final db = _db;
      if (db == null) return {'total': 0};
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .millisecondsSinceEpoch;
      final rows = db.select(
          "SELECT meta FROM event_ledger WHERE kind = 'turn' AND ts >= ? AND meta IS NOT NULL",
          [since]);
      var local = 0, cloud = 0;
      final byProvider = <String, int>{};
      var unknown = 0; // [Blue 抓包 2026-10-17 #4] 舊輪無 provider——誠實分類
      for (final r in rows) {
        try {
          final meta = (jsonDecode(r['meta'] as String) as Map);
          final hasRoute = meta.containsKey('provider');
          if (!hasRoute) {
            unknown++; // 補記機制上線前的歷史輪——不算本地也不算雲端
            continue;
          }
          final isLocal = meta['is_local'] == true;
          final provider = meta['provider']?.toString() ?? 'unknown';
          if (isLocal) {
            local++;
          } else {
            cloud++;
          }
          byProvider[provider] = (byProvider[provider] ?? 0) + 1;
        } catch (_) {
          unknown++;
        }
      }
      return {
        'total': local + cloud, // 分母=有路由記錄的輪（誠實：不含 unknown）
        'local': local,
        'cloud': cloud,
        'unknown': unknown,
        'by_provider': byProvider,
      };
    } catch (e) {
      debugPrint('[EventLedger] cloudRateStats 失敗: $e');
      return {'total': 0};
    }
  }

  /// [T11② 2026-10-17] 補記 turn meta——LLM 呼叫完成後才知道的欄位
  /// （provider/model/is_local）。雲端率儀表的資料源：不改 appendTurn
  /// 簽名（它在注入前呼叫，provider 還沒定）。
  void updateTurnMeta(String turnId, Map<String, dynamic> extra) {
    try {
      final db = _db;
      if (db == null) return;
      final row = db.select(
          "SELECT meta FROM event_ledger WHERE turn_id = ? AND kind = 'turn'",
          [turnId]);
      if (row.isEmpty) return;
      final raw = row.first['meta'] as String?;
      Map<String, dynamic> meta = {};
      if (raw != null && raw.isNotEmpty) {
        try {
          meta = (jsonDecode(raw) as Map).cast<String, dynamic>();
        } catch (_) {}
      }
      meta.addAll(extra);
      db.execute(
          "UPDATE event_ledger SET meta = ? WHERE turn_id = ? AND kind = 'turn'",
          [jsonEncode(meta), turnId]);
    } catch (e) {
      debugPrint('[EventLedger] updateTurnMeta 失敗（fail-open）: $e');
    }
  }

  String appendTurn({
    required String turnId,
    required String input,
    String? inputHash,
    List<String> injectedIds = const [],
    String? decision,
    double? confidence,
    double? answerConfidence, // [T2/D2] 回答正確性信心（校準/熔斷用）
    String? executor,
    String? output,
    Map<String, dynamic>? meta,
    String? conversationId, // [T12-④] 對話歸屬——lastTurnId 過濾用
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
      'INSERT INTO event_ledger (kind, turn_id, ts, input, input_hash, injected_ids, decision, confidence, answer_confidence, executor, output, meta, conversation_id, hash_prev, hash_self) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [ 'turn', turnId, ts, input, inputHash, jsonEncode(injectedIds), decision,
        confidence, answerConfidence, executor, output, metaJson, conversationId, prev, self ],
    );
    return self;
  }

  /// [T12-① D2 2026-10-17] answer_confidence 收尾補寫——唯一寫入通道。
  /// appendTurn 在輪開頭落盤（答案未生成，欄位 NULL）；agent_loop.run()
  /// 收尾時以本方法補上 AnswerConfidenceScorer 的評分。UPDATE 只動本輪
  /// 列（WHERE turn_id+kind），不觸 hash 欄（hash_self/hash_prev 不含
  /// answer_confidence——見 _hash 參數清單），hash 鏈不斷。
  /// 冪等：同輪重複補寫覆蓋為最新評分（輕裝→全裝重跑場景，最終結果勝出）。
  void setAnswerConfidence(String turnId, double value) {
    _ensureTable();
    _db.execute(
      "UPDATE event_ledger SET answer_confidence = ? "
      "WHERE turn_id = ? AND kind = 'turn'",
      [value, turnId],
    );
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
  /// [小葵 2026-10-15 T2/D2] 改吃 answer_confidence（回答正確性信心）——
  /// 舊欄 confidence 是 K1 的「要不要查」信心，語意錯配（Fable 斷鏈①）。
  /// answer_confidence IS NULL 的舊輪不進統計（無訊號≠零分）。
  List<({double bucket, int n, double acc})> onlineCalibration() {
    _ensureTable();
    final rows = _db.select('''
      SELECT t.answer_confidence AS conf, r.user_reaction AS reaction
      FROM event_ledger t
      JOIN event_ledger r
        ON r.kind = 'reaction' AND r.ref_turn_id = t.turn_id
      WHERE t.kind = 'turn' AND t.answer_confidence IS NOT NULL
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
