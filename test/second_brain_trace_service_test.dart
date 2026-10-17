import 'package:bridge_app/models/agent_activity.dart';
import 'package:bridge_app/models/second_brain_file_index.dart';
import 'package:bridge_app/models/second_brain_trace.dart';
import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/second_brain_file_index_store.dart';
import 'package:bridge_app/services/second_brain_trace_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const reflection = BrainReflection(
    userIntent: '正在討論第二大腦與 AI Agent 共用記憶。',
    attentionState: AttentionState.clear,
    pendulumSignals: [],
    importanceLevel: ImportanceLevel.balanced,
    heartMindAlignment: HeartMindAlignment.aligned,
    fraileResonance: FraileResonance.present,
    doorCandidates: [
      DoorCandidate(
        kind: DoorKind.ownDoor,
        label: '自己的門',
        reason: '使用者在整理長期產品方向。',
      ),
    ],
    flowState: FlowState.withFlow,
    recommendedMove: RecommendedMove.takeNextAction,
    companionExpression: CompanionExpression(
      mood: AgentCompanionMood.focused,
      action: AgentCompanionAction.reading,
      statusText: '正在調閱第二大腦',
    ),
    guidance: '把第二大腦運作回饋顯示出來。',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'builds rich memory traces from recalled Transurfing insights',
    () async {
      const service = SecondBrainTraceService();
      const recalled = 'Transurfing洞察：遇到新工具或新平台時，最佳策略是把資訊消費轉成具體作品或任務輸出。';
      const added = 'Transurfing洞察：此類議題出現自己的門訊號，與使用者需求、喜好或創作方向有共振。';

      await MemoryStore.add(recalled);

      final trace = await service.build(
        reflection: reflection,
        recalledInsights: const [recalled],
        newInsights: const [added],
        activeCompanionName: '約瑟',
        activeBridgeActionLabel: '新聞與網頁搜尋橋',
      );

      expect(trace.agentName, '約瑟');
      expect(trace.recalledMemories, hasLength(1));
      expect(trace.recalledMemories.first.room, 'Bridges');
      expect(trace.recalledMemories.first.sourceLabel, 'Transurfing 洞察庫');
      expect(trace.recalledMemories.first.reason, contains('新聞與網頁搜尋橋'));
      expect(trace.recalledMemories.first.tags, contains('新 AI 服務'));
      expect(trace.newInsights.single.room, 'Doors');
      expect(trace.newInsights.single.tags, contains('門'));
    },
  );

  test('recalls indexed files with real room and source path', () async {
    const fileIndexStore = SecondBrainFileIndexStore();
    await fileIndexStore.upsert(
      SecondBrainFileEntry(
        id: 'second-brain-architecture',
        title: '第二大腦架構.md',
        path: '/Volumes/DATA/橋樑計劃/docs/第二大腦架構.md',
        room: SecondBrainRoom.projects,
        summary: '定義六大房間、AI Agent 共用記憶與檔案立體檢索。',
        tags: const ['第二大腦', '檔案索引'],
        indexedAt: DateTime(2026),
        trustScore: 88,
      ),
    );

    const service = SecondBrainTraceService(fileIndexStore: fileIndexStore);
    final trace = await service.build(
      reflection: reflection,
      recalledInsights: const [],
      newInsights: const [],
      activeCompanionName: '約瑟',
    );

    expect(trace.recalledMemories, hasLength(1));
    expect(trace.recalledMemories.single.room, 'Projects');
    expect(trace.recalledMemories.single.sourceLabel, '第二大腦架構.md');
    expect(
      trace.recalledMemories.single.sourcePath,
      '/Volumes/DATA/橋樑計劃/docs/第二大腦架構.md',
    );
    expect(trace.recalledMemories.single.tags, contains('計畫房間'));
    expect(
      trace.recalledMemories.single.retrievalSignals,
      contains('房間命中：計畫房間'),
    );
    expect(
      trace.recalledMemories.single.retrievalSignals.join(' '),
      contains('關鍵字命中'),
    );
    expect(trace.associations.single, contains('真實來源'));
  });

  test(
    'uses persisted association feedback to bias recalled indexed files',
    () async {
      const fileIndexStore = SecondBrainFileIndexStore();
      await fileIndexStore.upsert(
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
      await fileIndexStore.upsert(
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
      await MemoryStore.markSecondBrainAssociationFeedback(
        '新聞橋 ↔ adapter 完成訊號 ↔ 回到原本卡點',
        SecondBrainAssociationFeedback.useful,
      );

      const service = SecondBrainTraceService(fileIndexStore: fileIndexStore);
      final trace = await service.build(
        reflection: reflection,
        recalledInsights: const [],
        newInsights: const [],
        activeCompanionName: '約瑟',
        activeBridgeActionLabel: '正式橋 adapter',
      );

      expect(trace.recalledMemories.first.sourceLabel, '新聞橋回流門.md');
      expect(
        trace.recalledMemories.first.retrievalSignals.join(' '),
        contains('好關聯加權'),
      );
    },
  );
}
