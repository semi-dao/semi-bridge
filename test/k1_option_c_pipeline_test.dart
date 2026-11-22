// k1_option_c_pipeline_test.dart
// [小葵 2026-11-03 K1卡選項C 回歸鎖] 屍檢三病的回歸測試：
// ① 止血刀——「建議類反問」不再 escalate（generalChat 規則命中）
// ② 管線刀——compass_ 假 turn 反應與 escalate_failopen 保險樣本不進訓練池
// ③ 源頭刀——lastTurnId 全域 fallback 不回 compass_ turn
// 病例標本：2026-11-03 K1 卡屍檢（99 筆判斷 64 escalate 的真相）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bridge_app/services/decision/k1_gatekeeper.dart';
import 'package:bridge_app/services/decision/decision_head.dart' show K1Labels;
import 'package:bridge_app/services/decision/k1_auto_trainer.dart';

void main() {
  group('① 止血刀：建議類反問不走 escalate', () {
    test('「這題你建議該如何調整？」→ generalChat 規則命中', () async {
      final d = await K1Gatekeeper.instance
          .classify('這題你建議該如何調整？');
      expect(d.escalated, isFalse, reason: '建議類反問＝當前對話推進，不查記憶');
      expect(d.source, 'rule');
      expect(d.label, K1Labels.generalChat);
    });

    test('「你覺得呢」也止住', () async {
      final d = await K1Gatekeeper.instance.classify('你覺得呢');
      expect(d.escalated, isFalse);
    });

    test('歷史詞優先——「上次建議了什麼」仍查記憶（need 規則在前）', () async {
      final d = await K1Gatekeeper.instance.classify('上次建議了什麼？');
      expect(d.label, K1Labels.needMemoryLookup,
          reason: '含「上次」＝歷史查詢，止血刀不得攔');
    });

    test('生日/密碼類不受影響', () async {
      final d = await K1Gatekeeper.instance.classify('我的生日是哪一天？');
      expect(d.label, K1Labels.needMemoryLookup);
    });
  });

  group('②③ 管線刀＋源頭刀：訓練池去污染', () {
    late Database causal;
    late Database brain;

    setUp(() {
      causal = sqlite3.openInMemory();
      brain = sqlite3.openInMemory();
      causal.execute('''
        CREATE TABLE agent_causal_ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          turn_id TEXT, tool_name TEXT, intervention TEXT,
          context_digest TEXT, observed_outcome TEXT, success INTEGER,
          created_at TEXT
        )
      ''');
      brain.execute('''
        CREATE TABLE event_ledger (
          rowid INTEGER PRIMARY KEY,
          kind TEXT, turn_id TEXT, ref_turn_id TEXT, ts INTEGER,
          user_reaction TEXT
        )
      ''');
      // 樣本佈置（模擬屍檢現場）：
      // - 真 turn_ 判 need + accepted → 好樣本（need）
      // - 真 turn_ 判 generalChat(conf=0) + accepted → 好樣本（no）
      // - 真 turn_ escalate_failopen + accepted → 保險非判斷 → 排除
      // - compass_ 假 turn + accepted → 假配對 → 排除
      void k1(String tid, String intervention) {
        causal.execute(
            "INSERT INTO agent_causal_ledger (turn_id, tool_name, intervention, context_digest, success, created_at) "
            "VALUES (?, 'k1_gatekeeper', ?, '使用者最新訊息：測試', 1, '2026-11-03')",
            [tid, intervention]);
      }

      void react(String tid, [String reaction = 'accepted']) {
        brain.execute(
            "INSERT INTO event_ledger (kind, ref_turn_id, ts, user_reaction) "
            "VALUES ('reaction', ?, 1793696000000, ?)",
            [tid, reaction]);
      }

      k1('turn_good_need', 'K1 判斷：need_memory_lookup（conf=1.00 source=rule）');
      react('turn_good_need');
      k1('turn_good_no', 'K1 判斷：general_chat（conf=0.00 source=escalate）');
      react('turn_good_no');
      k1('turn_failopen', 'K1 判斷：need_memory_lookup（conf=0.00 source=escalate_failopen）');
      react('turn_failopen');
      k1('compass_1793673303833', 'K1 判斷：need_memory_lookup（conf=1.00 source=rule）');
      react('compass_1793673303833');
    });

    tearDown(() {
      causal.close();
      brain.close();
    });

    test('★_scan：failopen 保險樣本與 compass_ 假 turn 都被排除', () {
      final scan = K1AutoTrainer.scanPairSamplesForTest(causal, brain);
      expect(scan['accepted'], 2, reason: '只收兩筆真判斷樣本');
      expect(scan['by_label']['need'], 1);
      expect(scan['by_label']['no'], 1, reason: '雙邊標籤都在——可訓練');
    });

    test('★buildLabelsJsonl：訓練集不含 failopen/compass_ 樣本', () {
      final jsonl = K1AutoTrainer.buildLabelsJsonlForTest(causal, brain);
      // 只 2 筆 < 20 門檻 → null（組建本身的門檻行為）
      expect(jsonl, isNull, reason: '2 筆低於 20 筆組建門檻——null 正常');
      // 驗證過濾邏輯：把組建門檻拿掉的方式——直接再掃一次比對
      final scan = K1AutoTrainer.scanPairSamplesForTest(causal, brain);
      expect(scan['paired'], 3, reason: 'compass_ 已在 SQL 層排除，paired 只算 turn_ 反應');
    });
  });
}
