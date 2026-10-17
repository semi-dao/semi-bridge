import 'package:bridge_app/models/second_brain_file_index.dart';
import 'package:bridge_app/models/second_brain_trace.dart';
import 'package:bridge_app/services/second_brain_file_index_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stores and searches indexed files by real room and path', () async {
    const store = SecondBrainFileIndexStore();

    await store.upsert(
      SecondBrainFileEntry(
        id: 'brain-architecture',
        title: '第二大腦架構.md',
        path: '/Volumes/DATA/橋樑計劃/docs/第二大腦架構.md',
        room: SecondBrainRoom.projects,
        summary: '定義六大房間、AI Agent 共用記憶與檔案立體檢索。',
        tags: const ['第二大腦', 'AI Agent', '檔案索引'],
        indexedAt: DateTime(2026),
        trustScore: 82,
      ),
    );

    final results = await store.search('第二大腦 檔案索引');

    expect(results, hasLength(1));
    expect(results.single.room, SecondBrainRoom.projects);
    expect(results.single.path, contains('/Volumes/DATA/橋樑計劃/docs'));
    expect(results.single.tags, contains('檔案索引'));
  });

  test('mark used increases use count without losing path', () async {
    const store = SecondBrainFileIndexStore();
    final entry = SecondBrainFileEntry(
      id: 'doors',
      title: '門與支線.md',
      path: '/Volumes/DATA/橋樑計劃/docs/門與支線.md',
      room: SecondBrainRoom.doors,
      summary: '記錄主線、支線、待回流門。',
      tags: const ['門', '主線'],
      indexedAt: DateTime(2026),
    );
    await store.upsert(entry);

    await store.markUsed([entry]);

    final saved = await store.getAll();
    expect(saved.single.useCount, 1);
    expect(saved.single.path, entry.path);
    expect(saved.single.lastUsedAt, isNotNull);
  });

  test('memory feedback persists and boosts pinned search results', () async {
    const store = SecondBrainFileIndexStore();
    final target = SecondBrainFileEntry(
      id: 'brain',
      title: '第二大腦架構.md',
      path: '/Volumes/DATA/橋樑計劃/docs/第二大腦架構.md',
      room: SecondBrainRoom.projects,
      summary: '第二大腦 檔案索引 AI Agent 共用記憶。',
      tags: const ['第二大腦'],
      indexedAt: DateTime(2026),
      trustScore: 50,
    );
    final competitor = SecondBrainFileEntry(
      id: 'other',
      title: '其他索引.md',
      path: '/Volumes/DATA/橋樑計劃/docs/其他索引.md',
      room: SecondBrainRoom.files,
      summary: '第二大腦 檔案索引 AI Agent 共用記憶。',
      tags: const ['第二大腦'],
      indexedAt: DateTime(2026, 2),
      trustScore: 80,
    );
    await store.upsert(target);
    await store.upsert(competitor);

    await store.applyMemoryFeedback(
      const SecondBrainMemoryTrace(
        content: '第二大腦 檔案索引 AI Agent 共用記憶。',
        room: 'Projects',
        sourceLabel: '第二大腦架構.md',
        sourcePath: '/Volumes/DATA/橋樑計劃/docs/第二大腦架構.md',
        reason: '測試常引用。',
      ),
      SecondBrainMemoryFeedback.pin,
    );

    final saved = await store.getAll();
    final boosted = saved.firstWhere((entry) => entry.id == 'brain');
    expect(boosted.pinned, isTrue);
    expect(boosted.usefulFeedbackCount, 1);
    expect(boosted.lastFeedbackLabel, '常引用');

    final results = await store.search('第二大腦 檔案索引', limit: 2);
    expect(results.first.id, 'brain');
  });

  test('muted memory feedback removes entry from search', () async {
    const store = SecondBrainFileIndexStore();
    final entry = SecondBrainFileEntry(
      id: 'muted',
      title: '不要引用.md',
      path: '/Volumes/DATA/橋樑計劃/docs/不要引用.md',
      room: SecondBrainRoom.files,
      summary: '第二大腦 檔案索引。',
      indexedAt: DateTime(2026),
    );
    await store.upsert(entry);

    await store.applyMemoryFeedback(
      const SecondBrainMemoryTrace(
        content: '第二大腦 檔案索引。',
        room: 'Files',
        sourceLabel: '不要引用.md',
        sourcePath: '/Volumes/DATA/橋樑計劃/docs/不要引用.md',
        reason: '測試不要引用。',
      ),
      SecondBrainMemoryFeedback.mute,
    );

    final saved = await store.getAll();
    expect(saved.single.muted, isTrue);
    expect(saved.single.irrelevantFeedbackCount, 1);

    final results = await store.search('第二大腦 檔案索引');
    expect(results, isEmpty);
  });

  test('clears visible memory correction state', () async {
    const store = SecondBrainFileIndexStore();
    final entry = SecondBrainFileEntry(
      id: 'undo',
      title: '撤回校正.md',
      path: '/Volumes/DATA/橋樑計劃/docs/撤回校正.md',
      room: SecondBrainRoom.bridges,
      summary: '校正回路與撤回。',
      indexedAt: DateTime(2026),
    );
    const memory = SecondBrainMemoryTrace(
      content: '校正回路與撤回。',
      room: 'Bridges',
      sourceLabel: '撤回校正.md',
      sourcePath: '/Volumes/DATA/橋樑計劃/docs/撤回校正.md',
      reason: '測試撤回。',
    );
    await store.upsert(entry);
    await store.applyMemoryFeedback(memory, SecondBrainMemoryFeedback.pin);

    var saved = await store.getAll();
    expect(saved.single.pinned, isTrue);
    expect(saved.single.lastFeedbackLabel, '常引用');

    await store.clearMemoryCorrection(memory);

    saved = await store.getAll();
    expect(saved.single.pinned, isFalse);
    expect(saved.single.muted, isFalse);
    expect(saved.single.lastFeedbackLabel, isEmpty);
    expect(saved.single.lastFeedbackAt, isNull);
  });

  test('moves memory to another second brain room', () async {
    const store = SecondBrainFileIndexStore();
    final entry = SecondBrainFileEntry(
      id: 'room-move',
      title: '能力橋規格.md',
      path: '/Volumes/DATA/橋樑計劃/docs/能力橋規格.md',
      room: SecondBrainRoom.files,
      summary: '正式橋能力與 adapter 規格。',
      indexedAt: DateTime(2026),
      trustScore: 60,
    );
    await store.upsert(entry);

    await store.moveMemoryToRoom(
      const SecondBrainMemoryTrace(
        content: '正式橋能力與 adapter 規格。',
        room: 'Files',
        sourceLabel: '能力橋規格.md',
        sourcePath: '/Volumes/DATA/橋樑計劃/docs/能力橋規格.md',
        reason: '測試移動房間。',
      ),
      SecondBrainRoom.bridges,
    );

    final saved = await store.getAll();
    expect(saved.single.room, SecondBrainRoom.bridges);
    expect(saved.single.lastFeedbackLabel, '移到橋樑房間');
    expect(saved.single.trustScore, 64);
  });

  test(
    'useful association feedback boosts matching memory retrieval',
    () async {
      const store = SecondBrainFileIndexStore();
      await store.upsert(
        SecondBrainFileEntry(
          id: 'generic-bridge',
          title: '正式橋總覽.md',
          path: '/Volumes/DATA/橋樑計劃/docs/正式橋總覽.md',
          room: SecondBrainRoom.bridges,
          summary: '正式橋能力 adapter 訊號中心。',
          indexedAt: DateTime(2026, 2),
          trustScore: 90,
        ),
      );
      await store.upsert(
        SecondBrainFileEntry(
          id: 'news-return-door',
          title: '新聞橋回流門.md',
          path: '/Volumes/DATA/橋樑計劃/docs/新聞橋回流門.md',
          room: SecondBrainRoom.bridges,
          summary: '新聞橋 adapter 完成訊號會回到原本卡點。',
          tags: const ['新聞橋', 'adapter', '回流門'],
          indexedAt: DateTime(2026),
          trustScore: 40,
        ),
      );

      final results = await store.search(
        '正式橋 adapter',
        limit: 2,
        associationFeedbacks: const {
          '新聞橋 ↔ adapter 完成訊號 ↔ 回到原本卡點': SecondBrainAssociationFeedback.useful,
        },
      );

      expect(results.first.id, 'news-return-door');
    },
  );

  test(
    'wrong association feedback suppresses matching memory retrieval',
    () async {
      const store = SecondBrainFileIndexStore();
      await store.upsert(
        SecondBrainFileEntry(
          id: 'news-return-door',
          title: '新聞橋回流門.md',
          path: '/Volumes/DATA/橋樑計劃/docs/新聞橋回流門.md',
          room: SecondBrainRoom.bridges,
          summary: '新聞橋 adapter 完成訊號會回到原本卡點。',
          tags: const ['新聞橋', 'adapter', '回流門'],
          indexedAt: DateTime(2026, 2),
          trustScore: 90,
        ),
      );
      await store.upsert(
        SecondBrainFileEntry(
          id: 'image-bridge',
          title: '圖片辨識橋.md',
          path: '/Volumes/DATA/橋樑計劃/docs/圖片辨識橋.md',
          room: SecondBrainRoom.bridges,
          summary: '圖片辨識橋 adapter 完成訊號。',
          tags: const ['圖片辨識橋', 'adapter'],
          indexedAt: DateTime(2026),
          trustScore: 70,
        ),
      );

      final results = await store.search(
        'adapter 完成訊號',
        limit: 2,
        associationFeedbacks: const {
          '新聞橋 ↔ adapter 完成訊號 ↔ 回到原本卡點': SecondBrainAssociationFeedback.wrong,
        },
      );

      expect(
        results.map((entry) => entry.id),
        isNot(contains('news-return-door')),
      );
      expect(results.single.id, 'image-bridge');
    },
  );
}
