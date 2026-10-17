// causal_ledger_test.dart
// [因果引擎 Phase 0 2026-09-11] L1 帳本 + L2 等級的確定性驗證
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/causal/causal_ledger_service.dart';
import 'dart:io';

void main() {
  group('L2 證據等級——確定性計算（非 LLM 自評）', () {
    test('純文字回覆（無工具）= 0 推測', () {
      final g = CausalLedger.gradeForTurns([]);
      expect(g, EvidenceGrade.speculated);
      expect(g.level, 0);
      expect(g.label, '推測');
    });

    test('只有觀察型工具成功 = 1 觀測', () {
      final g = CausalLedger.gradeForTurns([
        ('screen_capture', true),
        ('read_source_file', true),
      ]);
      expect(g, EvidenceGrade.observed);
    });

    test('觀察型失敗不算證據 = 0 推測', () {
      final g = CausalLedger.gradeForTurns([
        ('screen_capture', false),
      ]);
      expect(g, EvidenceGrade.speculated);
    });

    test('改變型工具成功 = 2 干預驗證（即使混著觀察型）', () {
      final g = CausalLedger.gradeForTurns([
        ('read_source_file', true),
        ('patch_source_file', true),
        ('screen_capture', true),
      ]);
      expect(g, EvidenceGrade.intervened);
    });

    test('改變型工具失敗 = 不構成干預證據', () {
      final g = CausalLedger.gradeForTurns([
        ('read_source_file', true),
        ('patch_source_file', false),
      ]);
      expect(g, EvidenceGrade.observed);
    });

    test('未知工具 = 0（寧低估不虛報）', () {
      final g = CausalLedger.gradeForTurns([
        ('some_future_tool', true),
      ]);
      expect(g, EvidenceGrade.speculated);
    });
  });

  group('L1 介入帳本——寫入與檢索', () {
    late String dbPath;

    setUp(() {
      dbPath =
          '/tmp/causal_ledger_test_${DateTime.now().millisecondsSinceEpoch}.db';
      CausalLedger.instance.resetForTest();
    });

    tearDown(() {
      CausalLedger.instance.resetForTest();
      final f = File(dbPath);
      if (f.existsSync()) f.deleteSync();
    });

    test('record → 帳本有條目，歸人正確', () async {
      final ledger = CausalLedger.instance;
      await ledger.initialize(dbPath: dbPath);
      ledger.ambientCompanionId = 'comp-xiaoqiao';
      ledger.record(CausalEntry(
        toolName: 'patch_source_file',
        intervention: 'path=lib/foo.dart;',
        contextDigest: '修畫布節點重複生成的 bug',
        observedOutcome: '[成功] 已套用 patch',
        success: true,
        companionId: ledger.ambientCompanionId,
        at: DateTime.now(),
      ));
      expect(ledger.entryCount, 1);

      final recalled = await ledger.recallSimilar('畫布節點重複');
      expect(recalled, isNotEmpty);
      expect(recalled.first.toolName, 'patch_source_file');
      expect(recalled.first.companionId, 'comp-xiaoqiao');
    });

    test('recallSimilar 無關鍵詞命中 = 回空（誠實，不硬湊）', () async {
      final ledger = CausalLedger.instance;
      await ledger.initialize(dbPath: dbPath);
      final recalled = await ledger.recallSimilar('zzz qqq xxx');
      expect(recalled, isEmpty);
    });

    test('fail-open：壞路徑不 throw，留 lastError', () async {
      final ledger = CausalLedger.instance;
      await ledger.initialize(dbPath: '/nonexistent_dir/x/y.db');
      expect(ledger.lastError, isNotNull);
      // record 不 throw
      ledger.record(CausalEntry(
        toolName: 'run_terminal',
        intervention: 'cmd=ls',
        contextDigest: 'ctx',
        observedOutcome: '[失敗] err',
        success: false,
        at: DateTime.now(),
      ));
    });

    test('successRateFor 統計', () async {
      final ledger = CausalLedger.instance;
      await ledger.initialize(dbPath: dbPath);
      for (var i = 0; i < 3; i++) {
        ledger.record(CausalEntry(
          toolName: 'canvas_place',
          intervention: 'x=100',
          contextDigest: 'ctx',
          observedOutcome: '[成功] ok',
          success: true,
          at: DateTime.now(),
        ));
      }
      ledger.record(CausalEntry(
        toolName: 'canvas_place',
        intervention: 'x=200',
        contextDigest: 'ctx',
        observedOutcome: '[失敗] fail',
        success: false,
        at: DateTime.now(),
      ));
      expect(await ledger.successRateFor('canvas_place'), 75.0);
    });
  });

  group('L3 反饋注入格式', () {
    test('空條目 = null（誠實：不假裝查過）', () {
      expect(CausalLedger.buildFeedbackSection([]), isNull);
    });

    test('有條目 = 格式化區塊，最多 3 筆', () {
      final entries = List.generate(5, (i) => CausalEntry(
        toolName: 'canvas_add_node',
        intervention: 'type=input; x=$i',
        contextDigest: 'ctx',
        observedOutcome: '[成功] 節點已建立 wf-$i',
        success: true,
        at: DateTime(2026, 9, 12),
      ));
      final s = CausalLedger.buildFeedbackSection(entries)!;
      expect(s, contains('歷史干預記錄'));
      expect(s, contains('直接引用作答'));
      expect('wf-0'.allMatches(s).length, 1);
      expect(s.contains('wf-3'), isFalse); // 第 4 筆起截掉
    });

    test('失敗記錄標示 [失敗]', () {
      final s = CausalLedger.buildFeedbackSection([
        CausalEntry(
          toolName: 'canvas_place', intervention: 'i', contextDigest: 'c',
          observedOutcome: '[失敗] 工具不存在', success: false,
          at: DateTime(2026, 9, 12)),
      ])!;
      expect(s, contains('｜失敗] canvas_place'));
    });

    test('時間感合體：條目帶算好的時間差（今天/昨天/N 天前/個月前）', () {
      final now = DateTime(2026, 9, 12, 12);
      final mk = (DateTime at) => CausalEntry(
        toolName: 'canvas_add_node', intervention: 'i', contextDigest: 'c',
        observedOutcome: '[成功] ok', success: true, at: at);
      // 今天
      expect(CausalLedger.buildFeedbackSection([mk(DateTime(2026, 9, 12, 8))], now: now),
          contains('[今天｜成功]'));
      // 昨天
      expect(CausalLedger.buildFeedbackSection([mk(DateTime(2026, 9, 11, 8))], now: now),
          contains('[昨天｜成功]'));
      // 16 天前（家人案例——不得感知成 3 個月）
      expect(CausalLedger.buildFeedbackSection([mk(DateTime(2026, 8, 27))], now: now),
          contains('[16 天前｜成功]'));
      // 90 天前
      expect(CausalLedger.buildFeedbackSection([mk(DateTime(2026, 6, 14))], now: now),
          contains('[3 個月前｜成功]'));
    });
  });

  group('摘要安全版——不洩漏完整參數', () {
    test('digestArgs 截斷長參數', () {
      final d = CausalLedger.digestArgs({
        'prompt': 'a' * 500,
      });
      expect(d.length, lessThan(200));
      expect(d.contains('…'), isTrue);
    });

    test('digestResult 壓縮空白並截斷', () {
      final d = CausalLedger.digestResult('line1\n\n   line2\n', true);
      expect(d, startsWith('[成功]'));
      expect(d.contains('\n'), isFalse);
    });
  });
}
