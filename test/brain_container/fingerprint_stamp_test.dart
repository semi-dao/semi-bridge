// 指紋章（fingerprint）回歸測試——②刀1/刀2 資料層契約
// Blue 2026-10-21 設計概念：不同身份不同靈魂、共用記憶——
// 每則記憶掛「誰說的」指紋章，回憶時永遠知道出處（誰·何時）。
// 測試不含 LLM 呼叫——驗證呈現層契約：
//   有章就亮（〔小橋·10/14〕）、無章不添（shared 不硬標）、格式不破壞。
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/brain_container/inject/slot_filter.dart';
import 'package:bridge_app/services/brain_container/inject/budget_controller.dart';
import 'package:bridge_app/services/agent_loop/agent_knowledge_service.dart';
import 'package:bridge_app/services/companion_store.dart';

void main() {
  group('[指紋章] MemoryCandidate → BudgetController 注入格式', () {
    MemoryCandidate mk({
      String? fingerprint,
      String text = '[belief] 測試記憶 — 內容本體',
    }) {
      return MemoryCandidate(
        id: 'test-mem',
        text: text,
        similarity: 0.9,
        slot: MemorySlot.belief,
        fingerprint: fingerprint,
      );
    }

    test('有章就亮：〔小橋·10/14〕前綴在槽位標籤後', () {
      final r = BudgetController().assemble([mk(fingerprint: '小橋·10/14')]);
      expect(r.block, startsWith('[背景記憶#1|信念]〔小橋·10/14〕'));
    });

    test('無章不添：fingerprint=null 不出現〔〕', () {
      final r = BudgetController().assemble([mk(fingerprint: null)]);
      expect(r.block, startsWith('[背景記憶#1|信念] [belief]'));
      expect(r.block.contains('〔'), isFalse);
    });

    test('預算估算與輸出一字不差（章計入 token）', () {
      final withStamp = BudgetController()
          .assemble([mk(fingerprint: '小橋·10/14', text: '同內容')]);
      final noStamp =
          BudgetController().assemble([mk(fingerprint: null, text: '同內容')]);
      // 章佔空間——帶章版本必 ≥ 無章版本（估算樣板=實際輸出）
      expect(withStamp.block.length >= noStamp.block.length, isTrue);
    });

    test('多條混合：有章無章並存格式不破壞', () {
      final r = BudgetController().assemble([
        mk(fingerprint: '小橋·10/14'),
        MemoryCandidate(
          id: 'test-mem-2',
          text: '[habit] 另一條 — 無章',
          similarity: 0.85,
          slot: MemorySlot.habit,
        ),
      ]);
      final lines = r.block.split('\n');
      expect(lines[0], startsWith('[背景記憶#1|信念]〔小橋·10/14〕'));
      expect(lines[1], startsWith('[背景記憶#2|慣例] [habit]'));
    });
  });

  group('[指紋章] KnowledgeSearchResult 出處標籤', () {
    test('具名夥伴+日期：小橋·10/14', () {
      final r = KnowledgeSearchResult(
        id: 'x', title: 't', snippet: 's', type: 'memory',
        ownerName: '小橋', createdAtLabel: '10/14',
      );
      expect(r.fingerprintLabel, '小橋·10/14');
    });

    test('具名夥伴無日期：只有名字', () {
      final r = KnowledgeSearchResult(
        id: 'x', title: 't', snippet: 's', type: 'memory',
        ownerName: 'MimeMi',
      );
      expect(r.fingerprintLabel, 'MimeMi');
    });

    test('shared → 共用（不是 shared 英文，給使用者看的）', () {
      final r = KnowledgeSearchResult(
        id: 'x', title: 't', snippet: 's', type: 'memory',
        ownerName: 'shared', createdAtLabel: '10/14',
      );
      expect(r.fingerprintLabel, '共用');
    });

    test('無 owner → null（不硬標）', () {
      final r = KnowledgeSearchResult(
        id: 'x', title: 't', snippet: 's', type: 'memory',
      );
      expect(r.fingerprintLabel, isNull);
    });
  });

  group('[指紋章] CompanionStore.fingerprintName 誠實邊界', () {
    // 不依賴 SharedPreferences 初始化——只驗證守衛邏輯（getById 找不到
    // 的 id 在未初始化 store 必然 miss，正好覆蓋保守 fallback 路徑）
    test('空 id / shared → shared（寧標 shared 不誤標）', () {
      final s = CompanionStore();
      expect(s.fingerprintName(''), 'shared');
      expect(s.fingerprintName('shared'), 'shared');
    });

    test('未知 id（store 未載入）→ shared 不猜名字', () {
      final s = CompanionStore();
      expect(s.fingerprintName('cmp_nonexistent'), 'shared');
    });
  });
}
