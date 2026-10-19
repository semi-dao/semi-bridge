// [殘件② 2026-10-19] K1AutoTrainer 驗收——配對掃描 + 水位防重複觸發。
// 不真跑訓練（樣本遠未達 200）——鎖的是「掃描正確」與「不到門檻零動作」。
// 訓練本體的守門（LOO-CV/單調落盤）由 k1_gatekeeper_test 既有測試覆蓋。
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:bridge_app/services/decision/k1_auto_trainer.dart';

void main() {
  late Database causal;
  late Database brain;

  setUp(() {
    causal = sqlite3.openInMemory();
    causal.execute('CREATE TABLE agent_causal_ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, tool_name TEXT NOT NULL, intervention TEXT NOT NULL, context_digest TEXT NOT NULL, observed_outcome TEXT NOT NULL, success INTEGER NOT NULL, companion_id TEXT, created_at TEXT NOT NULL, turn_id TEXT)');
    causal.execute('CREATE INDEX idx_causal_tool ON agent_causal_ledger(tool_name)');
    brain = sqlite3.openInMemory();
    brain.execute('''CREATE TABLE event_ledger (
          rowid INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL DEFAULT 'turn',
          turn_id TEXT NOT NULL,
          ref_turn_id TEXT,
          ts INTEGER NOT NULL,
          input TEXT,
          input_hash TEXT,
          injected_ids TEXT,
          decision TEXT,
          confidence REAL,
          executor TEXT,
          output TEXT,
          user_reaction TEXT,
          meta TEXT)''');
  });

  tearDown(() {
    causal.dispose();
    brain.dispose();
  });

  void seedK1(String turnId, String intervention, String userMsg) {
    causal.execute(
        "INSERT INTO agent_causal_ledger (tool_name, intervention, context_digest, observed_outcome, success, created_at, turn_id) "
        "VALUES ('k1_gatekeeper', ?, ?, '路由', 1, '2026-10-19T20:00:00', ?)",
        [intervention, '以下是之前的對話歷史：\n\n[使用者]\n$userMsg\n\n---\n\n使用者最新訊息：$userMsg', turnId]);
  }

  void seedReaction(String refTurnId, String reaction) {
    brain.execute(
        "INSERT INTO event_ledger (kind, turn_id, ref_turn_id, ts, user_reaction) VALUES ('reaction', 'x', ?, 1792400000000, ?)",
        [refTurnId, reaction]);
  }

  test('配對掃描：accepted×K1 判斷 → by_label 正確分類', () {
    seedK1('t1', 'K1 判斷：need_memory_lookup（conf=1.00 source=rule）', '幫我查記憶');
    seedK1('t2', 'K1 判斷：general_chat（conf=0.00 source=rule）', '哈囉');
    seedK1('t3', 'K1 判斷：need_memory_lookup（conf=1.00 source=rule）', '還記得嗎');
    seedReaction('t1', 'accepted');
    seedReaction('t2', 'accepted');
    seedReaction('t3', 'corrected'); // 糾正不進樣本

    final r = K1AutoTrainer.scanPairSamplesForTest(causal, brain);
    expect(r['accepted'], 2, reason: 'corrected 不算可用樣本');
    expect(r['by_label']['need'], 1);
    expect(r['by_label']['no'], 1);
  });

  test('無反應的輪不進樣本（無校準訊號＝不知道對錯）', () {
    seedK1('t1', 'K1 判斷：need_memory_lookup（conf=1.00 source=rule）', '幫我查');
    final r = K1AutoTrainer.scanPairSamplesForTest(causal, brain);
    expect(r['accepted'], 0);
    expect(r['paired'], 0);
  });

  test('標註組建：text 抽「使用者最新訊息：」之後、過濾超長', () {
    // 組建門檻 n≥20（bootstrapFromLabels 的 too_few_samples 防線）
    for (var i = 0; i < 12; i++) {
      seedK1('need$i', 'K1 判斷：need_memory_lookup（conf=1.00 source=rule）', '幫我查記憶$i');
      seedReaction('need$i', 'accepted');
    }
    for (var i = 0; i < 10; i++) {
      seedK1('no$i', 'K1 判斷：general_chat（conf=0.00 source=rule）', '哈囉$i');
      seedReaction('no$i', 'accepted');
    }
    // 無反應與糾正的輪不進樣本
    seedK1('unreacted', 'K1 判斷：need_memory_lookup（conf=1.00 source=rule）', '沒反應的輪');
    seedK1('corrected1', 'K1 判斷：need_memory_lookup（conf=1.00 source=rule）', '被糾正的輪');
    seedReaction('corrected1', 'corrected');
    final jsonl = K1AutoTrainer.buildLabelsJsonlForTest(causal, brain);
    expect(jsonl, isNotNull);
    final lines = jsonl!.trim().split('\n');
    expect(lines.length, 22, reason: '22 accepted 配對（無反應與 corrected 排除）');
    expect(lines.where((l) => l.contains('"label":"need"')).length, 12);
    expect(lines.where((l) => l.contains('"label":"no"')).length, 10);
  });
}
