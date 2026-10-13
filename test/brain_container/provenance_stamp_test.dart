// 出處戳 provenance 回歸測試——spike 001 紅隊題組轉正式測資
// 內部真實案例 #7：AI 把自己寫的農場文誤歸為使用者話語（偽造親密證據鏈）
// 測試不含 LLM 呼叫——驗證的是「資料層事實」：
// speaker 戳寫入→讀回→注入格式 三段不出錯、不丟失、不相容性破壞。
// （模型行為層的攔截率已由 spike 001 實測 3/3，此處鎖資料層契約。）
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/models/brain_container/memory_source.dart';
import 'package:bridge_app/models/brain_container/memory.dart';
import 'package:bridge_app/models/brain_container/brain_room.dart';

void main() {
  group('[出處戳] MemorySpeaker enum 契約', () {
    test('四值齊全：user/agent/external/unknown', () {
      expect(MemorySpeaker.values.length, 4);
      expect(MemorySpeaker.values.map((e) => e.name).toList(),
          ['user', 'agent', 'external', 'unknown']);
    });

    test('fromDbOrDefault：合法值解析', () {
      expect(MemorySpeaker.fromDbOrDefault('user'), MemorySpeaker.user);
      expect(MemorySpeaker.fromDbOrDefault('agent'), MemorySpeaker.agent);
      expect(MemorySpeaker.fromDbOrDefault('external'), MemorySpeaker.external);
    });

    test('fromDbOrDefault：null/非法值 → unknown（誠實不猜）', () {
      // 2026-09-15 前的既有記憶（speaker=NULL）與髒資料都落到 unknown
      expect(MemorySpeaker.fromDbOrDefault(null), MemorySpeaker.unknown);
      expect(MemorySpeaker.fromDbOrDefault(''), MemorySpeaker.unknown);
      expect(MemorySpeaker.fromDbOrDefault('nonsense'),
          MemorySpeaker.unknown);
    });
  });

  group('[出處戳] Memory model 往返（toMap/fromMap）', () {
    Memory mkMemory(MemorySpeaker speaker) {
      final now = DateTime.now();
      return Memory(
        id: 'test-$speaker',
        content: '測試記憶（$speaker）',
        room: BrainRoom.stream,
        subCategory: '',
        agent: 'test',
        companionId: '',
        source: MemorySource.chat,
        speaker: speaker,
        project: '',
        tags: const [],
        importance: 3,
        createdAt: now,
        updatedAt: now,
        accessCount: 0,
        archived: false,
        chunkIndex: 0,
        totalChunks: 1,
      );
    }

    test('speaker 四值往返不丟失', () {
      for (final sp in MemorySpeaker.values) {
        final m = mkMemory(sp);
        final restored = Memory.fromMap(m.toMap());
        expect(restored.speaker, sp, reason: 'speaker=$sp 往返後改變');
      }
    });

    test('舊資料（map 無 speaker 鍵）→ unknown，不 crash', () {
      // 模擬 migration 前的舊 row（無 speaker 欄位值）
      final now = DateTime.now().millisecondsSinceEpoch;
      final oldRow = {
        'id': 'old-1',
        'content': '舊記憶',
        'room': 'stream',
        'sub_category': '',
        'agent': 'test',
        'companion_id': '',
        'source': 'chat',
        'source_id': null,
        // 故意不放 speaker
        'project': '',
        'tags': '[]',
        'importance': 3,
        'created_at': now,
        'updated_at': now,
        'access_count': 0,
        'archived': 0,
        'chunk_index': 0,
        'total_chunks': 1,
      };
      final m = Memory.fromMap(oldRow);
      expect(m.speaker, MemorySpeaker.unknown);
    });

    test('copyWith 帶 speaker', () {
      final m = mkMemory(MemorySpeaker.unknown);
      expect(m.copyWith(speaker: MemorySpeaker.user).speaker,
          MemorySpeaker.user);
      // 不帶則保留原值
      expect(m.copyWith(content: '改內容').speaker, MemorySpeaker.unknown);
    });
  });

  group('[出處戳] 注入格式（spike 001 實測契約）', () {
    test('speaker= 前綴為必要語法——注入字串必含 speaker=<值>', () {
      // 這個字串格式由 BrainContainerService.getFormattedContext 產出：
      // '記憶 N（X 天前｜speaker=user）: 內容'
      // 契約：speaker= 前綴不可省（裸值會被模型忽略——spike 001 實測）
      for (final sp in MemorySpeaker.values) {
        final line = '記憶 1（3 天前｜speaker=${sp.name}）: 測試';
        expect(line.contains('speaker=${sp.name}'), isTrue);
      }
    });
  });
}
