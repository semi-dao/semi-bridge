import 'package:bridge_app/models/agent_activity.dart';
import 'package:bridge_app/models/bridge_action.dart';
import 'package:bridge_app/models/capability_catalog.dart';
import 'package:bridge_app/models/second_brain_file_index.dart';
import 'package:bridge_app/models/second_brain_trace.dart';
import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/services/agent_motivation_engine.dart';
import 'package:bridge_app/theme/tier_style.dart';
import 'package:bridge_app/widgets/brain_reflection_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // [Tier 整肅 2026-09-21 後] panel 內 TierStyle.of() 要求 TierTheme 已註冊，
  // 否則 throw StateError。host 須掛載（loadDefaultTierTheme 已記憶化）。
  late final ThemeData tierHostTheme;
  setUpAll(() async {
    final tierTheme = await loadDefaultTierTheme();
    tierHostTheme = ThemeData.dark().copyWith(extensions: [tierTheme]);
  });

  const reflection = BrainReflection(
    userIntent: '想把外部 AI 服務轉成自己的可用能力。',
    attentionState: AttentionState.captured,
    pendulumSignals: [
      PendulumSignal(
        type: PendulumSignalType.platformPull,
        label: '平台拉力',
        evidence: '影片生成',
      ),
    ],
    importanceLevel: ImportanceLevel.elevated,
    heartMindAlignment: HeartMindAlignment.mixed,
    fraileResonance: FraileResonance.obscured,
    doorCandidates: [
      DoorCandidate(
        kind: DoorKind.foreignDoor,
        label: '外部平台的門',
        reason: '訊息焦點被新服務吸引。',
      ),
    ],
    flowState: FlowState.againstFlow,
    recommendedMove: RecommendedMove.convertToOutput,
    companionExpression: CompanionExpression(
      mood: AgentCompanionMood.focused,
      action: AgentCompanionAction.reading,
      statusText: '正在收束注意力',
    ),
    guidance: '把外部資訊轉成自己的輸出，先選一個最貼近目標的成果。',
  );

  const branchingReflection = BrainReflection(
    userIntent: '想判斷要走主線或支線。',
    attentionState: AttentionState.clear,
    pendulumSignals: [],
    importanceLevel: ImportanceLevel.balanced,
    heartMindAlignment: HeartMindAlignment.mixed,
    fraileResonance: FraileResonance.present,
    doorCandidates: [
      DoorCandidate(
        kind: DoorKind.currentLink,
        label: '目前 transfer chain 的下一環',
        reason: '正在判斷下一步。',
      ),
    ],
    doorDecision: DoorDecision(
      id: 'door-test',
      title: '偵測到重大分支門',
      summary: '現在有兩條路都合理。',
      mainlineLabel: '先走主線',
      mainlineReason: '先完成核心流程。',
      branchLabel: '先進支線',
      branchReason: '先補足新能力。',
      recommendedChoice: DoorDecisionChoice.mainline,
      recommendationReason: '主線還沒完全走通。',
      returnPrompt: '回到 adapter 支線。',
    ),
    flowState: FlowState.withFlow,
    recommendedMove: RecommendedMove.takeNextAction,
    companionExpression: CompanionExpression(
      mood: AgentCompanionMood.focused,
      action: AgentCompanionAction.reading,
      statusText: '正在判斷門',
    ),
    guidance: '先看清楚門，再走。',
  );

  const flowReflection = BrainReflection(
    userIntent: '正在做同一水流裡的細節收尾。',
    attentionState: AttentionState.clear,
    pendulumSignals: [],
    importanceLevel: ImportanceLevel.balanced,
    heartMindAlignment: HeartMindAlignment.aligned,
    fraileResonance: FraileResonance.present,
    doorCandidates: [
      DoorCandidate(
        kind: DoorKind.currentLink,
        label: '目前 transfer chain 的下一環',
        reason: '這是同一條水流裡的細節收尾。',
      ),
    ],
    doorDecision: DoorDecision(
      id: 'flow-test',
      navigationKind: NavigationDecisionKind.flow,
      title: '偵測到同一水流的細節收尾',
      summary: '這比較像在同一條工作水流裡優化一個細節。',
      mainlineLabel: '順著水流收尾',
      mainlineReason: '修完就回主線。',
      branchLabel: '回到主線之門',
      branchReason: '如果細節已足夠，就回到主線。',
      recommendedChoice: DoorDecisionChoice.mainline,
      recommendationReason: '這是低阻力的細節水流。',
      returnPrompt: '回到主線之門。',
    ),
    flowState: FlowState.withFlow,
    recommendedMove: RecommendedMove.takeNextAction,
    companionExpression: CompanionExpression(
      mood: AgentCompanionMood.focused,
      action: AgentCompanionAction.reading,
      statusText: '正在順流收尾',
    ),
    guidance: '先完成這股水流，再回到主線。',
  );

  testWidgets('renders thinking dashboard chips and guidance', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tierHostTheme,
        home: Scaffold(body: BrainReflectionPanel(reflection: reflection)),
      ),
    );

    expect(find.text('思維儀表'), findsWidgets);
    expect(find.text('儀表摘要'), findsOneWidget);
    expect(find.text('轉成輸出'), findsWidgets);
    expect(find.textContaining('外部資訊轉成自己的輸出'), findsOneWidget);
  });

  testWidgets('renders pinned instrument status strip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tierHostTheme,
        home: Scaffold(
          body: BrainInstrumentStatusStrip(reflection: reflection),
        ),
      ),
    );

    expect(find.text('注意力：'), findsOneWidget);
    expect(find.text('被捕獲'), findsOneWidget);
    expect(find.text('重要性：'), findsOneWidget);
    expect(find.text('偏高'), findsOneWidget);
    expect(find.text('門：'), findsOneWidget);
    expect(find.textContaining('外部平台的門'), findsOneWidget);
    expect(find.text('水流：'), findsOneWidget);
    expect(find.text('逆流'), findsOneWidget);
    expect(find.text('建議：'), findsOneWidget);
    expect(find.text('轉成輸出'), findsOneWidget);
  });

  testWidgets('question button opens explanation sheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tierHostTheme,
        home: Scaffold(body: BrainReflectionPanel(reflection: reflection)),
      ),
    );

    await tester.tap(find.byIcon(Icons.help_outline).first);
    await tester.pumpAndSettle();

    expect(find.text('思維儀表'), findsWidgets);
    expect(find.textContaining('方向判斷層'), findsOneWidget);
  });

  testWidgets('hides recalled insight manual feedback actions', (tester) async {
    const insight = 'Transurfing洞察：遇到新工具或新平台時，最佳策略是把資訊消費轉成具體作品或任務輸出。';

    await tester.pumpWidget(
      MaterialApp(
        theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: reflection,
            recalledInsights: [insight],
          ),
        ),
      ),
    );

    expect(find.text('回收洞察'), findsNothing);
    expect(find.textContaining('新工具或新平台'), findsNothing);
    expect(find.text('準確'), findsNothing);
    expect(find.text('不準'), findsNothing);
    expect(find.text('先別用'), findsNothing);
  });

  testWidgets('renders live brain action stage and working materials', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: reflection,
            activeStage: AgentActivityStage.context,
            activeTelemetry: AgentActivityTelemetry(
              messages: 3,
              chars: 240,
              memories: 2,
              attachments: 1,
            ),
            isWorking: true,
          ),
        ),
      ),
    );

    expect(find.text('儀表摘要'), findsOneWidget);
    expect(find.text('運行中'), findsOneWidget);
    await tester.tap(find.text('儀表摘要'));
    await tester.pumpAndSettle();

    expect(find.text('正在整理上下文'), findsOneWidget);
    expect(find.textContaining('3對話'), findsOneWidget);
    expect(find.textContaining('2記憶'), findsOneWidget);
    expect(find.textContaining('1附件'), findsOneWidget);
  });

  testWidgets('renders brain skill registry capability decision', (
    tester,
  ) async {
    const definition = CapabilityDefinition(
      id: 'music-generation',
      name: '音樂生成橋',
      kind: CapabilityKind.music,
      actionType: BridgeActionType.generateMusic,
      description: '產生配樂。',
      triggerPhrases: ['音樂'],
      providers: ['SemiDAO Plugin'],
      setupRoute: '/golden-keys',
      brainRoom: 'Bridges',
    );
    const status = CapabilityRuntimeStatus(
      definition: definition,
      availability: CapabilityAvailability.needsSetup,
      providerLabel: 'SemiDAO Plugin',
      detail: '等待插件',
      nextStep: '前往/golden-keys開通或測試金鑰。',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: reflection,
            brainSkillRegistry: BrainSkillRegistrySnapshot(
              capabilities: [status],
              recommendations: [
                BrainSkillRecommendation(
                  capability: status,
                  reason: '使用者需求命中音樂能力線索。',
                  confidence: 92,
                ),
              ],
              summary: '大腦建議使用「音樂生成橋」，狀態：需開通。',
            ),
          ),
        ),
      ),
    );

    expect(find.text('能力判斷'), findsOneWidget);
    await tester.tap(find.text('能力判斷'));
    await tester.pumpAndSettle();

    expect(find.text('音樂生成橋'), findsOneWidget);
    expect(find.text('需開通'), findsOneWidget);
    expect(find.textContaining('使用者需求命中音樂能力線索'), findsOneWidget);
  });

  testWidgets('hides empty brain skill registry placeholder', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: reflection,
            brainSkillRegistry: BrainSkillRegistrySnapshot(),
          ),
        ),
      ),
    );

    expect(find.text('能力判斷'), findsNothing);
    expect(find.text('0/0 可用'), findsNothing);
    expect(find.textContaining('正在比對能力目錄'), findsNothing);
  });

  testWidgets('renders second brain workbench with memory trace', (
    tester,
  ) async {
    const trace = SecondBrainTrace(
      agentName: '約瑟',
      recalledMemories: [
        SecondBrainMemoryTrace(
          content: '遇到新工具或新平台時，最佳策略是把資訊消費轉成具體作品或任務輸出。',
          room: 'Bridges',
          sourceLabel: 'Transurfing 洞察庫',
          sourcePath: 'local://memory/transurfing-insights',
          reason: '因為這輪意圖被判定為「想把外部 AI 服務轉成自己的可用能力。」。',
          retrievalSignals: ['意圖命中：AI 服務', '主題標籤：橋樑能力、新 AI 服務'],
          freshnessLabel: '剛更新',
          sourcePreview: '這是來源原文摘錄，說明如何把新工具轉成可執行任務。',
          tags: ['橋樑能力', '新 AI 服務'],
          trustScore: 65,
        ),
        SecondBrainMemoryTrace(
          content: 'Door Decision Card 會保存主線、支線與待回流門。',
          room: 'Doors',
          sourceLabel: 'Door Decision Card.md',
          sourcePath: '/Volumes/DATA/橋樑計劃/docs/Door Decision Card.md',
          reason: '因為這輪正在判斷門與回流。',
          retrievalSignals: ['關鍵字命中：門、回流', '房間命中：門房間'],
          tags: ['門房間', '主線', '橋樑能力'],
          trustScore: 78,
        ),
      ],
      newInsights: [
        SecondBrainNewInsightTrace(
          content: '使用者正在把第二大腦面板轉成可見的共同工作台。',
          room: 'Bridges',
          tags: ['第二大腦', 'AI Agent 共用記憶'],
        ),
      ],
      associations: [
        '第二大腦 ↔ 檔案索引 ↔ AI Agent 共用記憶',
        '新聞橋 ↔ adapter 完成訊號 ↔ 回到原本卡點',
        '錯誤關聯 ↔ 不該召回 ↔ 降低誤連',
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: reflection,
            secondBrainTrace: trace,
            secondBrainMemoryFeedbacks: {
              'local://memory/transurfing-insights|遇到新工具或新平台時，最佳策略是把資訊消費轉成具體作品或任務輸出。':
                  SecondBrainMemoryFeedback.irrelevant,
            },
            secondBrainMemoryRoomOverrides: {
              '/Volumes/DATA/橋樑計劃/docs/Door Decision Card.md|Door Decision Card 會保存主線、支線與待回流門。':
                  SecondBrainRoom.bridges,
            },
            secondBrainAssociationFeedbacks: {
              '第二大腦 ↔ 檔案索引 ↔ AI Agent 共用記憶':
                  SecondBrainAssociationFeedback.useful,
              '錯誤關聯 ↔ 不該召回 ↔ 降低誤連': SecondBrainAssociationFeedback.wrong,
            },
          ),
        ),
      ),
    );

    expect(find.text('第二大腦工作台'), findsOneWidget);
    expect(find.textContaining('共用大腦：Bridge Brain'), findsOneWidget);
    expect(find.text('房間儀表'), findsOneWidget);
    expect(find.textContaining('七個燈號代表第二大腦'), findsOneWidget);
    expect(find.text('2/7 亮燈'), findsOneWidget);
    expect(find.textContaining('橋樑房間'), findsWidgets);
    expect(find.textContaining('橋樑房間：Transurfing 洞察庫'), findsOneWidget);
    expect(find.textContaining('門房間：Door Decision Card.md'), findsOneWidget);
    expect(find.text('校正回路'), findsOneWidget);
    expect(find.text('校正歷史'), findsOneWidget);
    expect(find.text('降低召回 1'), findsOneWidget);
    expect(find.text('移房間 1'), findsOneWidget);
    expect(find.textContaining('相似問題會降低召回'), findsWidgets);
    expect(find.textContaining('改用「橋樑房間」作為房間線索'), findsWidgets);
    expect(find.textContaining('面板密度'), findsOneWidget);
    expect(find.text('召回信心：需確認'), findsOneWidget);
    expect(find.text('鮮度：剛更新'), findsOneWidget);
    expect(find.textContaining('來源預覽'), findsOneWidget);
    expect(find.textContaining('可能記憶衝突'), findsOneWidget);
    expect(find.text('調閱了什麼'), findsOneWidget);
    expect(find.text('房間：橋樑房間'), findsWidgets);
    expect(find.textContaining('Transurfing 洞察庫'), findsWidgets);
    expect(find.textContaining('為什麼調閱'), findsWidgets);
    expect(find.text('召回線索'), findsWidgets);
    expect(find.text('意圖命中：AI 服務'), findsOneWidget);
    expect(find.text('房間命中：門房間'), findsOneWidget);
    expect(find.text('新增了什麼'), findsOneWidget);
    expect(find.text('存入：Bridges'), findsOneWidget);
    expect(find.text('關聯儀表板'), findsOneWidget);
    expect(find.text('強化召回 1'), findsOneWidget);
    expect(find.text('降低誤連 1'), findsOneWidget);
    expect(find.text('待校準 1'), findsOneWidget);
    expect(find.textContaining('提高召回：第二大腦'), findsOneWidget);
    expect(find.textContaining('降低誤連：錯誤關聯'), findsOneWidget);
    expect(find.text('新增關聯'), findsOneWidget);
  });

  testWidgets('second brain workbench exposes folder import action', (
    tester,
  ) async {
    var tapped = false;
    const trace = SecondBrainTrace(
      agentName: '約瑟',
      recalledMemories: [
        SecondBrainMemoryTrace(
          content: '定義六大房間、AI Agent 共用記憶與檔案立體檢索。',
          room: 'Projects',
          sourceLabel: '第二大腦架構.md',
          sourcePath: '/Volumes/DATA/橋樑計劃/docs/第二大腦架構.md',
          reason: '測試第二大腦資料夾匯入入口。',
          tags: ['計畫房間', '檔案索引'],
          trustScore: 82,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
      theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: reflection,
            secondBrainTrace: trace,
            onImportSecondBrainFolder: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));

    expect(tapped, isTrue);
  });

  testWidgets('second brain memory correction can be undone', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var undone = false;
    const memory = SecondBrainMemoryTrace(
      content: '正式橋能力與 adapter 規格。',
      room: 'Bridges',
      sourceLabel: '能力橋規格.md',
      sourcePath: '/Volumes/DATA/橋樑計劃/docs/能力橋規格.md',
      reason: '測試撤回校正。',
      retrievalSignals: ['房間命中：橋樑房間', '使用者標記：之後常引用'],
      tags: ['橋樑房間', 'adapter'],
      trustScore: 84,
    );
    const trace = SecondBrainTrace(recalledMemories: [memory]);

    await tester.pumpWidget(
      MaterialApp(
      theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: reflection,
            secondBrainTrace: trace,
            secondBrainMemoryFeedbacks: const {
              '/Volumes/DATA/橋樑計劃/docs/能力橋規格.md|正式橋能力與 adapter 規格。':
                  SecondBrainMemoryFeedback.pin,
            },
            onUndoSecondBrainMemoryCorrection: (_) => undone = true,
          ),
        ),
      ),
    );

    expect(find.textContaining('之後常引用'), findsWidgets);

    await tester.ensureVisible(find.text('撤回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤回'));

    expect(undone, isTrue);
  });

  testWidgets('second brain memory card sends feedback action', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SecondBrainMemoryTrace? tappedMemory;
    SecondBrainMemoryFeedback? tappedFeedback;
    const memory = SecondBrainMemoryTrace(
      content: '定義六大房間、AI Agent 共用記憶與檔案立體檢索。',
      room: 'Projects',
      sourceLabel: '第二大腦架構.md',
      sourcePath: '/Volumes/DATA/橋樑計劃/docs/第二大腦架構.md',
      reason: '測試第二大腦調閱回饋。',
      tags: ['計畫房間', '檔案索引'],
      trustScore: 82,
    );
    const trace = SecondBrainTrace(agentName: '約瑟', recalledMemories: [memory]);

    await tester.pumpWidget(
      MaterialApp(
      theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: reflection,
            secondBrainTrace: trace,
            secondBrainMemoryFeedbacks: const {
              '/Volumes/DATA/橋樑計劃/docs/第二大腦架構.md|定義六大房間、AI Agent 共用記憶與檔案立體檢索。':
                  SecondBrainMemoryFeedback.useful,
            },
            onSecondBrainMemoryFeedback: (memory, feedback) {
              tappedMemory = memory;
              tappedFeedback = feedback;
            },
          ),
        ),
      ),
    );

    expect(find.text('有用'), findsOneWidget);
    expect(find.text('不相關'), findsOneWidget);
    expect(find.text('常引用'), findsOneWidget);
    expect(find.text('不要引用'), findsOneWidget);

    final irrelevantButton = find.byKey(
      const ValueKey('second-brain-feedback-irrelevant'),
    );
    await tester.ensureVisible(irrelevantButton);
    await tester.pumpAndSettle();
    await tester.tap(irrelevantButton);

    expect(tappedMemory, memory);
    expect(tappedFeedback, SecondBrainMemoryFeedback.irrelevant);
  });

  testWidgets('second brain memory card sends room move action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SecondBrainMemoryTrace? tappedMemory;
    SecondBrainRoom? tappedRoom;
    const memory = SecondBrainMemoryTrace(
      content: '正式橋能力與 adapter 規格。',
      room: 'Files',
      sourceLabel: '能力橋規格.md',
      sourcePath: '/Volumes/DATA/橋樑計劃/docs/能力橋規格.md',
      reason: '測試房間校準。',
      tags: ['檔案房間', 'adapter'],
      trustScore: 70,
    );
    const trace = SecondBrainTrace(agentName: '約瑟', recalledMemories: [memory]);

    await tester.pumpWidget(
      MaterialApp(
      theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: reflection,
            secondBrainTrace: trace,
            secondBrainMemoryRoomOverrides: const {
              '/Volumes/DATA/橋樑計劃/docs/能力橋規格.md|正式橋能力與 adapter 規格。':
                  SecondBrainRoom.bridges,
            },
            onSecondBrainMemoryRoomMove: (memory, room) {
              tappedMemory = memory;
              tappedRoom = room;
            },
          ),
        ),
      ),
    );

    expect(find.text('已移到 橋樑房間'), findsOneWidget);

    final roomButton = find.byKey(
      const ValueKey('second-brain-move-room-Projects'),
    );
    await tester.ensureVisible(roomButton);
    await tester.pumpAndSettle();
    await tester.tap(roomButton);

    expect(tappedMemory, memory);
    expect(tappedRoom, SecondBrainRoom.projects);
  });

  testWidgets('second brain memory card exposes source actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SecondBrainMemoryTrace? openedMemory;
    SecondBrainMemoryTrace? copiedMemory;
    const memory = SecondBrainMemoryTrace(
      content: '正式橋能力與 adapter 規格。',
      room: 'Bridges',
      sourceLabel: '能力橋規格.md',
      sourcePath: '/Volumes/DATA/橋樑計劃/docs/能力橋規格.md',
      reason: '測試來源操作。',
      tags: ['橋樑房間'],
      trustScore: 70,
    );
    const trace = SecondBrainTrace(agentName: '約瑟', recalledMemories: [memory]);

    await tester.pumpWidget(
      MaterialApp(
      theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: reflection,
            secondBrainTrace: trace,
            onOpenSecondBrainMemorySource: (memory) => openedMemory = memory,
            onCopySecondBrainMemorySource: (memory) => copiedMemory = memory,
          ),
        ),
      ),
    );

    expect(find.text('開啟來源'), findsOneWidget);
    expect(find.text('複製路徑'), findsOneWidget);

    final openButton = find.byKey(const ValueKey('second-brain-open-source'));
    await tester.ensureVisible(openButton);
    await tester.pumpAndSettle();
    await tester.tap(openButton);
    expect(openedMemory, memory);

    final copyButton = find.byKey(const ValueKey('second-brain-copy-source'));
    await tester.ensureVisible(copyButton);
    await tester.pumpAndSettle();
    await tester.tap(copyButton);
    expect(copiedMemory, memory);
  });

  testWidgets('second brain memory card opens detail drawer', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const memory = SecondBrainMemoryTrace(
      content: '正式橋能力與 adapter 規格。',
      room: 'Bridges',
      sourceLabel: '能力橋規格.md',
      sourcePath: '/Volumes/DATA/橋樑計劃/docs/能力橋規格.md',
      reason: '因為這輪正在處理正式橋能力，需要調閱 adapter 規格。',
      tags: ['橋樑房間', 'adapter'],
      trustScore: 70,
    );
    const trace = SecondBrainTrace(
      agentName: '約瑟',
      recalledMemories: [
        memory,
        SecondBrainMemoryTrace(
          content: '新聞橋與網頁搜尋橋共用 adapter 完成訊號。',
          room: 'Bridges',
          sourceLabel: '新聞橋規格.md',
          sourcePath: '/Volumes/DATA/橋樑計劃/docs/新聞橋規格.md',
          reason: '同一輪也需要確認能力完成後回到卡點。',
          tags: ['橋樑房間', 'adapter', '新聞'],
          trustScore: 68,
        ),
      ],
      associations: ['正式橋能力 ↔ adapter 完成訊號 ↔ 回到原本卡點'],
    );
    String? tappedAssociation;
    SecondBrainAssociationFeedback? tappedAssociationFeedback;

    await tester.pumpWidget(
      MaterialApp(
      theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: reflection,
            secondBrainTrace: trace,
            secondBrainAssociationFeedbacks: const {
              '正式橋能力 ↔ adapter 完成訊號 ↔ 回到原本卡點':
                  SecondBrainAssociationFeedback.useful,
            },
            onSecondBrainAssociationFeedback: (association, feedback) {
              tappedAssociation = association;
              tappedAssociationFeedback = feedback;
            },
          ),
        ),
      ),
    );

    final detailButton = find
        .byKey(const ValueKey('second-brain-memory-detail'))
        .first;
    await tester.ensureVisible(detailButton);
    await tester.pumpAndSettle();
    await tester.tap(detailButton);
    await tester.pumpAndSettle();

    expect(find.text('記憶細節'), findsOneWidget);
    expect(find.text('記憶內容'), findsOneWidget);
    expect(find.text('正式橋能力與 adapter 規格。'), findsWidgets);
    expect(find.text('來源位置'), findsOneWidget);
    expect(find.text('/Volumes/DATA/橋樑計劃/docs/能力橋規格.md'), findsWidgets);
    expect(find.text('為什麼調閱'), findsWidgets);
    expect(find.text('橋樑房間、adapter'), findsWidgets);
    expect(find.text('記憶關聯圖'), findsOneWidget);
    expect(find.text('同房間記憶'), findsOneWidget);
    expect(find.textContaining('新聞橋規格.md'), findsWidgets);
    expect(find.text('本輪新增關聯'), findsOneWidget);
    expect(find.textContaining('回到原本卡點'), findsWidgets);
    expect(find.text('連得好'), findsOneWidget);
    expect(find.text('連錯了'), findsOneWidget);

    final wrongButton = find.byKey(
      const ValueKey('second-brain-association-feedback-wrong'),
    );
    await tester.ensureVisible(wrongButton);
    await tester.pumpAndSettle();
    await tester.tap(wrongButton);

    expect(tappedAssociation, '正式橋能力 ↔ adapter 完成訊號 ↔ 回到原本卡點');
    expect(tappedAssociationFeedback, SecondBrainAssociationFeedback.wrong);
  });

  testWidgets('renders agent motivation metrics', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: reflection,
            agentMotivation: AgentMotivationSnapshot(
              agentName: '約瑟',
              driveXp: 45,
              driveLevel: 1,
              accuracyScore: 78,
              resonanceScore: 72,
              autonomyScore: 69,
              usefulFeedbackCount: 3,
              correctionCount: 1,
              mutedCount: 0,
              recoveryRouteCount: 1,
              learningFocus: '延續高分線索，靠近使用者真正意圖。',
              lastSignal: '這筆洞察有用，之後可以更常引用相似線索。',
              activeRecoveryRoute: '下次遇到類似線索，先停下確認主線、卡點與能力缺口。',
            ),
          ),
        ),
      ),
    );

    expect(find.text('內在驅動'), findsOneWidget);
    await tester.tap(find.text('內在驅動'));
    await tester.pumpAndSettle();

    expect(find.textContaining('約瑟 · Drive Lv 1'), findsOneWidget);
    expect(find.text('準確度 '), findsOneWidget);
    expect(find.text('78'), findsOneWidget);
    expect(find.textContaining('學習焦點'), findsOneWidget);
    expect(find.textContaining('最新信號'), findsOneWidget);
    expect(find.textContaining('通關路線'), findsOneWidget);
    expect(find.textContaining('能力缺口'), findsOneWidget);
  });

  testWidgets('renders door decision card and stores user choice callback', (
    tester,
  ) async {
    DoorDecisionChoice? tappedChoice;

    await tester.pumpWidget(
      MaterialApp(
      theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: branchingReflection,
            onDoorChoice: (_, choice) => tappedChoice = choice,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('door-decision-card')), findsOneWidget);
    expect(find.text('偵測到重大分支門'), findsOneWidget);
    expect(find.text('先走主線'), findsWidgets);
    expect(find.text('先進支線'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, '先走主線'));

    expect(tappedChoice, DoorDecisionChoice.mainline);
  });

  testWidgets('renders flow decision card without door wording', (
    tester,
  ) async {
    DoorDecisionChoice? tappedChoice;

    await tester.pumpWidget(
      MaterialApp(
      theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: flowReflection,
            onDoorChoice: (_, choice) => tappedChoice = choice,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('door-decision-card')), findsOneWidget);
    expect(find.text('偵測到同一水流的細節收尾'), findsOneWidget);
    expect(find.text('建議順流'), findsOneWidget);
    expect(find.text('順著水流收尾'), findsWidgets);
    expect(find.text('暫存這股水流'), findsOneWidget);
    expect(find.text('偵測到重大分支門'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '順著水流收尾'));

    expect(tappedChoice, DoorDecisionChoice.mainline);
  });

  testWidgets('renders pending door return and resumes it', (tester) async {
    var resumed = false;
    var cleared = false;

    await tester.pumpWidget(
      MaterialApp(
      theme: tierHostTheme,
        home: Scaffold(
          body: BrainReflectionPanel(
            reflection: reflection,
            pendingDoorReturn: const DoorDecisionPendingReturn(
              decisionId: 'door-test',
              title: 'adapter 支線',
              chosenLabel: '先走主線',
              deferredLabel: '先進支線',
              returnPrompt: '回到 adapter 支線。',
              sourceSummary: '現在有兩條路都合理。',
              createdAtMs: 1,
            ),
            onResumePendingDoor: () => resumed = true,
            onClearPendingDoor: () => cleared = true,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('pending-door-return-card')),
      findsOneWidget,
    );
    expect(find.textContaining('待回流門'), findsOneWidget);

    await tester.tap(find.text('回到這扇門'));
    expect(resumed, isTrue);

    await tester.tap(find.text('已處理'));
    expect(cleared, isTrue);
  });
}
