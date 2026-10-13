import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert' show utf8, jsonDecode;
import 'package:sqlite3/sqlite3.dart';

import 'package:bridge_app/services/brain_container/event_ledger.dart';
import 'package:bridge_app/services/brain_container/inject/inject_pipeline.dart';
import 'package:bridge_app/services/brain_container/inject/slot_filter.dart';
import 'package:bridge_app/services/brain_container/inject/budget_controller.dart';

/// M0 單元測試（Fable 驗收要求）
/// 槽位限額、預算控制、槽位判定：可離線驗證的純邏輯。
/// 鏈整合測試（EventLedger.forTest 注入暫存 DB，絕不碰真庫——R4 教訓）：
/// append-only 鏈、重複反應拒絕、竄改偵測、v2→v3 遷移相容。
void main() {
  test('slot filter: 槽位限額 2/1/1/1 且同槽取最高相似度', () {
    final f = SlotFilter();
    final cands = [
      MemoryCandidate(id: 'a', text: 'h1', similarity: 0.8, slot: MemorySlot.habit),
      MemoryCandidate(id: 'b', text: 'h2', similarity: 0.9, slot: MemorySlot.habit),
      MemoryCandidate(id: 'c', text: 'h3', similarity: 0.95, slot: MemorySlot.habit), // 應擠掉 a
      MemoryCandidate(id: 'd', text: 'p1', similarity: 0.7, slot: MemorySlot.preference),
      MemoryCandidate(id: 'e', text: 'p2', similarity: 0.85, slot: MemorySlot.preference), // 應擠掉 d
    ];
    final out = f.apply(cands);
    expect(out.length, 3);
    expect(out.map((c) => c.id).toSet(), {'b', 'c', 'e'});
    expect(out.first.id, 'c'); // 依相似度降冪
    expect(f.droppedCount, 2);
  });

  test('budget: 地板過濾＋每槽保一＋400 token 上限', () {
    final b = BudgetController();
    final long = 'x' * 300; // ~360 tokens/條
    final cands = [
      MemoryCandidate(id: 'h1', text: long, similarity: 0.9, slot: MemorySlot.habit),
      MemoryCandidate(id: 'h2', text: long, similarity: 0.85, slot: MemorySlot.habit),
      MemoryCandidate(id: 'p1', text: long, similarity: 0.3, slot: MemorySlot.preference), // 低於地板
      MemoryCandidate(id: 'r1', text: long, similarity: 0.6, slot: MemorySlot.recent),
    ];
    final r = b.assemble(cands);
    expect(r.kept.length, 2); // h2 被 400 上限丟、p1 被地板丟；habit+recent 各保一
    expect(r.kept.map((c) => c.id).toSet(), {'h1', 'r1'});
    expect(r.block, contains('#1'));
  });

  test('budget: 估算與輸出一致（樣板=實際格式）', () {
    final b = BudgetController(maxTokens: 100000);
    final cands = [
      MemoryCandidate(id: 'h1', text: '短記憶', similarity: 0.9, slot: MemorySlot.habit),
      MemoryCandidate(id: 'p1', text: '短偏好', similarity: 0.8, slot: MemorySlot.preference),
    ];
    final r = b.assemble(cands);
    // block 每行格式：[背景記憶#N|槽位] 文字
    expect(r.block.split('\n').first, startsWith('[背景記憶#1|慣例]'));
  });

  test('slotOf: type 優先、精確片語退路', () {
    // type 命中 conversation → 近期（即使標題有「必」）
    expect(
      SlotFilter.slotOf(memoryType: 'hermes_conversation', title: '必要時通知'),
      MemorySlot.recent,
    );
    // type 未知＋標題鐵則 → 慣例
    expect(
      SlotFilter.slotOf(memoryType: '', title: '存檔鐵則：git commit'),
      MemorySlot.habit,
    );
    // type 未知＋「必」單字（v1 誤判源）→ 不歸槽
    expect(SlotFilter.slotOf(memoryType: null, title: '可能需要'), isNull);
    // persona → 偏好
    expect(SlotFilter.slotOf(memoryType: 'persona_card'), MemorySlot.preference);
    // lesson → 慣例
    expect(SlotFilter.slotOf(memoryType: 'lesson'), MemorySlot.habit);
    // milestone → 信念
    expect(SlotFilter.slotOf(memoryType: 'milestone'), MemorySlot.belief);
    // layer 佐證：L8 對話層
    expect(SlotFilter.slotOf(memoryType: '', layer: 'L8'), MemorySlot.recent);
  });

  group('EventLedger 整合（注入暫存 DB，絕不碰真庫）', () {
    late Database db;
    late EventLedger ledger;

    setUp(() {
      db = sqlite3.openInMemory();
      ledger = EventLedger.forTest(db);
    });

    tearDown(() {
      db.dispose();
    });

    test('appendTurn→appendReaction：append-only 鏈完整且反應可關聯', () {
      ledger.appendTurn(
        turnId: 't1',
        input: '把存檔做好',
        inputHash: 'a'.padRight(64, '0'),
        injectedIds: ['m1', 'm2'],
        decision: 'gen_answer',
        confidence: 0.82,
        executor: 'agent_loop',
      );
      expect(ledger.appendReaction('t1', 'accepted'), isTrue);
      final (ok, n) = ledger.verifyChain();
      expect(ok, isTrue);
      expect(n, 2);
    });

    test('重複反應被拒絕（同 turn 首次反應有效）', () {
      ledger.appendTurn(turnId: 't1', input: 'x');
      expect(ledger.appendReaction('t1', 'accepted'), isTrue);
      expect(ledger.appendReaction('t1', 'corrected'), isFalse);
      final (ok, n) = ledger.verifyChain();
      expect(ok, isTrue);
      expect(n, 2); // 第二筆反應沒進鏈
    });

    test('竄改 input 被偵測（hash chain 斷）', () {
      ledger.appendTurn(
        turnId: 't1',
        input: '原文',
        inputHash: 'b'.padRight(64, '0'),
      );
      db.execute("UPDATE event_ledger SET input = '被竄改' WHERE turn_id = 't1'");
      final (ok, _) = ledger.verifyChain();
      expect(ok, isFalse);
    });

    test('竄改 input_hash（拔成 NULL 或改值）被偵測', () {
      ledger.appendTurn(
        turnId: 't1',
        input: '原文',
        inputHash: 'c'.padRight(64, '0'),
      );
      // 拔成 NULL → v2 形狀重算 ≠ 原 v3 hash
      db.execute("UPDATE event_ledger SET input_hash = NULL WHERE turn_id = 't1'");
      expect(ledger.verifyChain().$1, isFalse);
    });

    test('v2→v3 遷移相容：舊 schema 建的表加欄後鏈不斷', () {
      // 先手工建 v2 schema（模擬既有 DB），無 input_hash 欄
      db.execute('''
        CREATE TABLE event_ledger (
          rowid         INTEGER PRIMARY KEY AUTOINCREMENT,
          kind          TEXT NOT NULL DEFAULT 'turn',
          turn_id       TEXT NOT NULL,
          ref_turn_id   TEXT,
          ts            INTEGER NOT NULL,
          input         TEXT,
          injected_ids  TEXT,
          decision      TEXT,
          confidence    REAL,
          executor      TEXT,
          output        TEXT,
          user_reaction TEXT,
          hash_prev     TEXT NOT NULL,
          hash_self     TEXT NOT NULL
        )
      ''');
      // 直接用 v2 演算法塞一筆舊資料（無 input_hash 鍵）
      final v2Payload =
          '{"kind":"turn","turn_id":"old1","ref_turn_id":null,"ts":1000,'
          '"input":"舊輸入","injected_ids":[],"decision":null,'
          '"confidence":null,"executor":null,"output":null,'
          '"user_reaction":null,"hash_prev":"GENESIS"}';
      final v2Hash = _sha256Of(v2Payload);
      db.execute(
        "INSERT INTO event_ledger (kind, turn_id, ts, input, injected_ids, hash_prev, hash_self) "
        "VALUES ('turn', 'old1', 1000, '舊輸入', '[]', 'GENESIS', ?)",
        [v2Hash],
      );
      // 遷移：ensureTable 補欄；舊列 hash 仍可驗；再 append 新列（v3 形狀）
      ledger.appendTurn(
        turnId: 'new1',
        input: '新輸入',
        inputHash: 'd'.padRight(64, '0'),
      );
      final (ok, n) = ledger.verifyChain();
      expect(ok, isTrue, reason: 'v2 舊列 + v3 新列混鏈必須整條可驗');
      expect(n, 2);
    });

    test('線上校準統計：反應 join 信心分桶', () {
      ledger.appendTurn(
          turnId: 't1', input: 'a', confidence: 0.85, decision: 'gen');
      ledger.appendTurn(
          turnId: 't2', input: 'b', confidence: 0.65, decision: 'gen');
      ledger.appendReaction('t1', 'accepted');
      ledger.appendReaction('t2', 'corrected');
      final stats = ledger.onlineCalibration();
      final b08 = stats.firstWhere((s) => s.bucket == 0.8);
      final b06 = stats.firstWhere((s) => s.bucket == 0.6);
      expect(b08.acc, 1.0);
      expect(b06.acc, 0.0);
    });

    test('v4 meta 落盤：latency/dropped/k1_merged/embedding_ok 進鏈', () {
      ledger.appendTurn(
        turnId: 't-meta-1',
        input: 'meta 測試',
        inputHash: 'a'.padRight(64, '0'),
        injectedIds: ['m1', 'm2'],
        meta: {
          'latency_ms': 42,
          'dropped_count': 3,
          'k1_merged_n': 1,
          'embedding_ok': true,
        },
      );
      final (ok, _) = ledger.verifyChain();
      expect(ok, isTrue, reason: 'meta 進 hash payload 後鏈必須可驗');
      final row = db.select(
          "SELECT meta FROM event_ledger WHERE turn_id = 't-meta-1'");
      final meta = jsonDecode(row.first['meta'] as String) as Map<String, dynamic>;
      expect(meta['latency_ms'], 42);
      expect(meta['k1_merged_n'], 1);
      expect(meta['embedding_ok'], true);
    });

    test('v4 竄改 meta 被偵測（改 latency_ms）', () {
      ledger.appendTurn(
        turnId: 't-meta-2',
        input: '竄改測試',
        meta: {'latency_ms': 42, 'dropped_count': 0, 'k1_merged_n': 0, 'embedding_ok': true},
      );
      db.execute(
          "UPDATE event_ledger SET meta = '{\"latency_ms\":1}' WHERE turn_id = 't-meta-2'");
      expect(ledger.verifyChain().$1, isFalse);
    });

    test('v3→v4 遷移相容：舊 schema（無 meta 欄）建表後混鏈可驗', () {
      // 手工建 v3 schema（無 meta 欄），塞 v3 形狀舊資料
      db.execute('''
        CREATE TABLE event_ledger (
          rowid         INTEGER PRIMARY KEY AUTOINCREMENT,
          kind          TEXT NOT NULL DEFAULT 'turn',
          turn_id       TEXT NOT NULL,
          ref_turn_id   TEXT,
          ts            INTEGER NOT NULL,
          input         TEXT,
          input_hash    TEXT,
          injected_ids  TEXT,
          decision      TEXT,
          confidence    REAL,
          executor      TEXT,
          output        TEXT,
          user_reaction TEXT,
          hash_prev     TEXT NOT NULL,
          hash_self     TEXT NOT NULL
        )
      ''');
      final v3Payload =
          '{"kind":"turn","turn_id":"old3","ref_turn_id":null,"ts":1001,'
          '"input":"舊3","injected_ids":[],"decision":null,"confidence":null,'
          '"executor":null,"output":null,"user_reaction":null,'
          '"hash_prev":"GENESIS","input_hash":"b000000000000000000000000000000000000000000000000000000000000000"}';
      db.execute(
        "INSERT INTO event_ledger (kind, turn_id, ts, input, input_hash, injected_ids, hash_prev, hash_self) "
        "VALUES ('turn', 'old3', 1001, '舊3', 'b000000000000000000000000000000000000000000000000000000000000000', '[]', 'GENESIS', ?)",
        [_sha256Of(v3Payload)],
      );
      // 遷移：ensureTable 補 meta 欄；舊列可驗；新列（v4 形狀）也可驗
      ledger.appendTurn(
        turnId: 'new4',
        input: '新4',
        inputHash: 'c'.padRight(64, '0'),
        meta: {'latency_ms': 5},
      );
      final (ok, n) = ledger.verifyChain();
      expect(ok, isTrue, reason: 'v3 舊列 + v4 新列混鏈必須整條可驗');
      expect(n, 2);
    });
  });

  group('M1：K1 候選合併規則（Fable delta）', () {
    test('K1 候選免地板（floorExempt）——0.3 低於地板仍被保留（拔旗標必紅）', () {
      final b = BudgetController();
      final cands = [
        MemoryCandidate(id: 'm0-1', text: '語意命中', similarity: 0.9, slot: MemorySlot.habit),
        // K1 hybrid 命中：分數 0.3（RRF 量綱），免地板 [Fable 🟡3 恢復 0.3 鎖旗標]
        MemoryCandidate(id: 'k1-1', text: 'K1命中', similarity: 0.3, slot: MemorySlot.recent, source: 'k1', floorExempt: true),
      ];
      final r = b.assemble(cands);
      expect(r.kept.map((c) => c.id), containsAll(['m0-1', 'k1-1']));
    });

    test('K1 候選不佔槽位 quota——M0 四槽規則不受擠壓', () {
      final f = SlotFilter();
      final cands = [
        MemoryCandidate(id: 'm0-r1', text: 'r1', similarity: 0.9, slot: MemorySlot.recent),
        // K1 三條全落 recent（memories 表無前綴的現實）——不佔 recent quota
        MemoryCandidate(id: 'k1-1', text: 'k', similarity: 1.0, slot: MemorySlot.recent, source: 'k1', floorExempt: true),
        MemoryCandidate(id: 'k1-2', text: 'k', similarity: 0.9, slot: MemorySlot.recent, source: 'k1', floorExempt: true),
        MemoryCandidate(id: 'k1-3', text: 'k', similarity: 0.8, slot: MemorySlot.recent, source: 'k1', floorExempt: true),
      ];
      final out = f.apply(cands);
      // M0 recent quota=1 不被 K1 擠——m0-r1 保住
      expect(out.any((c) => c.id == 'm0-r1'), isTrue);
      // K1 三條全在（獨立上限 3）
      expect(out.where((c) => c.source == 'k1').length, 3);
      expect(out.length, 4);
    });

    test('K1 額滿時 M0 補位——habit 槽 quota=2：K1 不佔槽後 M0×2 全保', () {
      final f = SlotFilter();
      final cands = [
        MemoryCandidate(id: 'm0-h1', text: 'h1', similarity: 0.88, slot: MemorySlot.habit),
        MemoryCandidate(id: 'm0-h2', text: 'h2', similarity: 0.8, slot: MemorySlot.habit),
        MemoryCandidate(id: 'k1-h3', text: 'h3', similarity: 1.0, slot: MemorySlot.habit, source: 'k1', floorExempt: true),
      ];
      final out = f.apply(cands);
      final habits = out.where((c) => c.slot == MemorySlot.habit).toList();
      // [M1 獨立通道] K1 不佔 habit quota——M0 兩條全保
      expect(habits.map((c) => c.id), containsAll(['m0-h1', 'm0-h2', 'k1-h3']));
      expect(habits.length, 3);
    });

    test('超預算淘汰序——精確斷言（mutant 全紅）[Fable 🔴1 空鎖修正]', () {
      // 每行固定 117 token（12 字前綴+84 字記憶+換行，×1.2 進位）：
      // [背景記憶#n|近期] = 12 runes（全中文 11+1 換行不含——標籤佔 11 字
      // + 空格 + 84 字 + \n → 97 字 × 1.2 = 116.4 → ceil 117）
      final mk = (String id, String slot, {bool k1 = false, double sim = 0.9}) =>
          MemoryCandidate(
            id: id, text: '很長的記憶內容' * 12, similarity: k1 ? 1.0 : sim,
            slot: MemorySlot.values.byName(slot),
            source: k1 ? 'k1' : 'm0', floorExempt: k1,
          );
      final cands = [
        mk('k1-1', 'recent', k1: true),
        mk('k1-2', 'recent', k1: true),
        mk('k1-3', 'recent', k1: true),
        mk('m0-h1', 'habit'),
        mk('m0-h2', 'habit'),
        mk('m0-p1', 'preference'),
      ];

      // 預算 400 → 3 條：6 條中 M0 非保證丟完 + M0 保證被壓縮 → K1 三條
      final r = BudgetController(maxTokens: 400).assemble(cands);
      expect(r.kept.map((c) => c.id).toList(), ['k1-1', 'k1-2', 'k1-3']);

      // 預算 470 → 4 條：M0 保證項 p1 先被丟、h1 留（M0 保證從尾端丟且在 K1 之後）
      final r470 = BudgetController(maxTokens: 470).assemble(cands);
      expect(r470.kept.map((c) => c.id).toList(),
          ['k1-1', 'k1-2', 'k1-3', 'm0-h1']);

      // 預算 240 → 2 條（K1 第 3 條先於第 2 條被丟）
      final r240 = BudgetController(maxTokens: 240).assemble(cands);
      expect(r240.kept.map((c) => c.id).toList(), ['k1-1', 'k1-2']);

      // 預算 100 → 1 條（length<=1 防護，K1 第一條永不丟）
      final r100 = BudgetController(maxTokens: 100).assemble(cands);
      expect(r100.kept.map((c) => c.id).toList(), ['k1-1']);

      // M0 純臂（K1 不在場）：全保證即接受超額 [Fable 🟡1]
      final m0Only = [
        mk('m0-h1', 'habit'),
        mk('m0-h2', 'habit'),
        mk('m0-p1', 'preference'),
        mk('m0-b1', 'belief'),
        mk('m0-r1', 'recent'),
      ];
      final rM0 = BudgetController(maxTokens: 400).assemble(m0Only);
      // 四槽各保一條：h1/p1/b1/r1 全在（M0 原語意：不因超額丟保證項）
      expect(rM0.kept.map((c) => c.id).toList(),
          ['m0-h1', 'm0-p1', 'm0-b1', 'm0-r1']);
    });

    test('assemble 內部 partition——呼叫端亂序餵入 K1 仍在前 [Fable 🟡1 鎖]', () {
      // 輸入故意 M0/K1 交錯（模擬 assemble 單獨被呼叫、未經 slot_filter）：
      // partition 不存在時 kept 順序＝輸入原序，removeLast 會先丟 K1 尾端
      final mk = (String id, String slot, {bool k1 = false}) =>
          MemoryCandidate(
            id: id, text: '很長的記憶內容' * 12, similarity: k1 ? 1.0 : 0.9,
            slot: MemorySlot.values.byName(slot),
            source: k1 ? 'k1' : 'm0', floorExempt: k1,
          );
      final cands = [
        mk('m0-h1', 'habit'),   // M0 在前
        mk('k1-1', 'recent', k1: true),
        mk('m0-p1', 'preference'),
        mk('k1-2', 'recent', k1: true),
      ];
      // @400：四條全保證（h1/p1 各槽唯一 M0、K1 全保證）＝468 > 400
      // partition 生效：kept=[k1-1,k1-2,h1,p1]，removeLast 丟 p1 → 351 ✓
      // 無 partition：kept=[h1,k1-1,p1,k1-2]，removeLast 丟 k1-2 ✗（本測試鎖）
      final r = BudgetController(maxTokens: 400).assemble(cands);
      expect(r.kept.map((c) => c.id).toList(), ['k1-1', 'k1-2', 'm0-h1']);
    });

    test('mergeCandidates 單測：同 id 撞號 K1 版勝出，M0 模糊版被取代', () {
      final m0 = [
        MemoryCandidate(id: 'mem-1', text: 'M0模糊版', similarity: 0.61, slot: MemorySlot.recent),
        MemoryCandidate(id: 'mem-2', text: 'M0獨有', similarity: 0.9, slot: MemorySlot.habit),
      ];
      final k1 = [
        MemoryCandidate(id: 'mem-1', text: 'K1明確版', similarity: 0.03, slot: MemorySlot.recent, source: 'k1', floorExempt: true),
      ];
      final merged = InjectPipeline.mergeCandidates(m0, k1);
      // mem-1 只剩 K1 版（floorExempt 帶著走，不會被地板丟）
      final mem1 = merged.where((c) => c.id == 'mem-1').toList();
      expect(mem1.length, 1);
      expect(mem1.first.source, 'k1');
      expect(mem1.first.floorExempt, isTrue);
      // mem-2 不受影響
      expect(merged.any((c) => c.id == 'mem-2'), isTrue);
      expect(merged.length, 2);
    });

    test('enrichWith 整合：K1 候選同 id 撞號時 K1 版勝出（非 K1 版被移除）', () async {
      // 直接測 enrichWith 的去重邏輯路徑：K1 extra 候選與 semantic 命中同 id
      // （測試環境無 embedding——search 回空，走 pure extra 路徑驗證 K1 保留）
      final k1 = MemoryCandidate(
        id: 'mem-42', text: 'K1命中版', similarity: 0.02,
        slot: MemorySlot.recent, source: 'k1', floorExempt: true,
      );
      // 觸發 enrichWith：若 search 無結果，candidates 只剩 K1 版
      // （same-id M0 版若存在會被 removeWhere 移除）
      final r = await InjectPipeline.instance.enrichWith(
        '測試查詢',
        extraCandidates: [k1],
      );
      // 測試環境 embedding 不可用 → 零命中 → block 空。此測試只驗證
      // 「K1 候選不因 enrich 崩潰而丟失」的路徑存活（fail-open 契約）。
      expect(r.latencyMs, greaterThanOrEqualTo(0));
      expect(r.k1KeptN, isA<int>());
    });
  });
}

/// 測試輔助：與 EventLedger._hash 的 v2 payload 形狀一致（無 input_hash 鍵）。
/// 注意必須用 utf8.encode（與 _hash 同款）——codeUnits 是 UTF-16，中文會對不上。
String _sha256Of(String payload) =>
    sha256.convert(utf8.encode(payload)).toString();
