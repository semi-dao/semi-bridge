// [T4 重寫 2026-11-09] 離線快照三契約＋離線行為測試
// 依據：BRIDGE_MOBILE_SPEC.md v0.5 §7 離線行為拍板（Blue 2026-10-30）
//
// ★ SPEC 條款原文錨定（本檔每個 group 的 reason 皆帶條款原文）：
//  條款 1「離線時 UI 誠實標灰、不裝活著；禁止整頁空白或轉圈騙人」
//  條款 2「顯示『上次快照＋時間戳』（時間戳屬於快照、非當前時間）」
//  條款 3「聊天輸入框保留可打字，標『離線中，訊息重連後送出』」
//  條款 4「離線排隊的訊息，重連後依序自動送出、不吞訊息」
//  條款 5「連線狀態只有 online/offline 兩態（不偽裝第三態）」
//
// 三契約類別（純函數核心，無 UI、無網路、無 DB——對照 test/mobile/domino_engine_test.dart 品質範本）：
//  1. HomeStateMachine  （lib/services/mobile/offline/home_state_machine.dart）
//  2. OfflineMessageQueue（lib/services/mobile/offline/offline_message_queue.dart）
//  3. HomeSnapshot      （lib/services/mobile/offline/home_snapshot.dart）
//
// 紅隊 9 條 issues 對應（docs/drill2/T4_離線快照_test.dart.review.txt）：
//  - 「API 契約未定義」→ 本檔三組 import 即正式契約（production API，非 TODO）
//  - 「ignore_for_file 掩蓋缺實作」→ 本檔零 ignore_for_file，缺實作即編譯紅
//  - 「缺少 HomeScreen 渲染測試」→ 以 HomeViewState（誠實視圖契約）鎖死「不空白、不轉圈」
//
// 怎麼跑：flutter test test/mobile/offline_behavior_test.dart

import 'package:bridge_app/services/mobile/offline/home_offline_coordinator.dart';
import 'package:bridge_app/services/mobile/offline/home_snapshot.dart';
import 'package:bridge_app/services/mobile/offline/home_state_machine.dart';
import 'package:bridge_app/services/mobile/offline/home_view_state.dart';
import 'package:bridge_app/services/mobile/offline/offline_home_view.dart';
import 'package:bridge_app/theme/tier_registry.dart';
import 'package:bridge_app/theme/tier_style.dart';
import 'package:bridge_app/services/mobile/offline/offline_message_queue.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:flutter/material.dart';

import 'test_manifest_string.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ─────────────────────────────────────────────────────────
  // 條款 5：連線狀態只有 online/offline 兩態
  // ─────────────────────────────────────────────────────────
  group('條款 5｜連線狀態只有 online/offline 兩態（不偽裝第三態）', () {
    test('狀態枚舉恰兩態：online 與 offline', () {
      expect(
        HomeConnectionState.values.map((e) => e.name).toSet(),
        equals({'online', 'offline'}),
        reason: 'SPEC §7 條款 5：連線狀態只有 online/offline 兩態（不偽裝第三態）',
      );
      expect(HomeConnectionState.values.length, 2);
    });

    test('不得存在 loading/reconnecting/unknown 等第三態名稱', () {
      for (final forbidden in ['loading', 'reconnect', 'unknown', 'connecting']) {
        expect(
          HomeConnectionState.values.any((e) => e.name.contains(forbidden)),
          isFalse,
          reason: 'SPEC §7 條款 5：不得偽裝第三態（$forbidden 不是合法連線態）',
        );
      }
    });

    test('預設初始態為 online，isOnline/isOffline 互斥', () {
      final machine = HomeStateMachine();
      expect(machine.state, HomeConnectionState.online);
      expect(machine.isOnline, isTrue);
      expect(machine.isOffline, isFalse);
      expect(machine.isOnline == machine.isOffline, isFalse);
    });

    test('online ＋ disconnect → offline（合法轉移被接受）', () {
      final machine = HomeStateMachine();
      final accepted = machine.dispatch(HomeConnectionEvent.disconnect);
      expect(accepted, isTrue);
      expect(machine.state, HomeConnectionState.offline);
    });

    test('online ＋ timeout → offline（逾時亦為合法斷線事件）', () {
      final machine = HomeStateMachine();
      final accepted = machine.dispatch(HomeConnectionEvent.timeout);
      expect(accepted, isTrue);
      expect(machine.state, HomeConnectionState.offline);
    });

    test('offline ＋ reconnect → online（重連事件才可回連線）', () {
      final machine = HomeStateMachine(initial: HomeConnectionState.offline);
      final accepted = machine.dispatch(HomeConnectionEvent.reconnect);
      expect(accepted, isTrue);
      expect(machine.state, HomeConnectionState.online);
    });

    test('非法轉移被拒且被記錄：online ＋ reconnect（不得偽裝重連）', () {
      final machine = HomeStateMachine();
      final accepted = machine.dispatch(HomeConnectionEvent.reconnect);
      expect(accepted, isFalse,
          reason: 'SPEC §7 條款 5：已在線上時 reconnect 屬非法轉移');
      expect(machine.state, HomeConnectionState.online, reason: '狀態不得被非法轉移改變');
      expect(machine.rejectedTransitions.length, 1);
      expect(machine.rejectedTransitions.first.event,
          HomeConnectionEvent.reconnect);
      expect(machine.rejectedTransitions.first.reason, contains('reconnect'));
      expect(machine.rejectedTransitions.first.from,
          HomeConnectionState.online);
      expect(machine.rejectedTransitions.first.to, HomeConnectionState.online);
    });

    test('非法轉移被拒且被記錄：offline ＋ disconnect（已離線不重複斷）', () {
      final machine = HomeStateMachine(initial: HomeConnectionState.offline);
      final accepted = machine.dispatch(HomeConnectionEvent.disconnect);
      expect(accepted, isFalse);
      expect(machine.state, HomeConnectionState.offline);
      expect(machine.rejectedTransitions.length, 1);
      expect(machine.rejectedTransitions.first.event,
          HomeConnectionEvent.disconnect);
    });

    test('非法轉移被拒且被記錄：offline ＋ timeout（已離線不重複逾時）', () {
      final machine = HomeStateMachine(initial: HomeConnectionState.offline);
      final accepted = machine.dispatch(HomeConnectionEvent.timeout);
      expect(accepted, isFalse);
      expect(machine.state, HomeConnectionState.offline);
      expect(machine.rejectedTransitions.length, 1);
      expect(machine.rejectedTransitions.first.event, HomeConnectionEvent.timeout);
    });

    test('歷史記錄含被拒事件（每一次事件都留痕）', () {
      final machine = HomeStateMachine();
      machine.dispatch(HomeConnectionEvent.disconnect); // online→offline 合法
      machine.dispatch(HomeConnectionEvent.timeout); // offline→offline 非法
      machine.dispatch(HomeConnectionEvent.reconnect); // offline→online 合法
      expect(machine.history.length, 3);
      expect(machine.history.where((r) => r.accepted).length, 2);
      expect(machine.history.where((r) => !r.accepted).length, 1);
      expect(machine.rejectedTransitions.length, 1);
      expect(machine.rejectedTransitions.first.event, HomeConnectionEvent.timeout);
    });

    test('連續轉移 offline→online→offline 最終態正確', () {
      final machine = HomeStateMachine(initial: HomeConnectionState.offline);
      machine.dispatch(HomeConnectionEvent.reconnect);
      machine.dispatch(HomeConnectionEvent.timeout);
      expect(machine.state, HomeConnectionState.offline);
      expect(machine.history.length, 2);
    });
  });

  // ─────────────────────────────────────────────────────────
  // 條款 1：誠實標灰、不裝活著、禁止整頁空白或轉圈騙人
  // ─────────────────────────────────────────────────────────
  group('條款 1｜離線時 UI 誠實標灰、不裝活著；禁止整頁空白或轉圈騙人', () {
    test('offline 視圖：標灰且不轉圈、不空白', () {
      const view = HomeViewState(connection: HomeConnectionState.offline);
      expect(view.isGreyedOut, isTrue,
          reason: 'SPEC §7 條款 1：離線時 UI 誠實標灰');
      expect(view.dimmedOpacity, lessThan(1.0));
      expect(view.isBlankPage, isFalse,
          reason: 'SPEC §7 條款 1：禁止整頁空白');
    });

    test('online 視圖：不標灰、不轉圈', () {
      const view = HomeViewState(connection: HomeConnectionState.online);
      expect(view.isGreyedOut, isFalse);
      expect(view.dimmedOpacity, 1.0);
      expect(view.isBlankPage, isFalse);
    });

    test('offline ＋ 有快照 → 顯示快照（不是空白頁）', () {
      final snapshot = HomeSnapshot(
        content: const {'標題': '快照內容'},
        capturedAt: DateTime(2026, 11, 8, 9, 30),
      );
      final view = HomeViewState(
        connection: HomeConnectionState.offline,
        snapshot: snapshot,
      );
      expect(view.showsSnapshot, isTrue);
      expect(view.showsEmptySnapshotNotice, isFalse);
      expect(view.isBlankPage, isFalse);
      expect(view.snapshotTimestampLabel, contains('2026-11-08'));
    });

    test('offline ＋ 從未同步（無快照）→ 誠實提示而非空白', () {
      const view = HomeViewState(connection: HomeConnectionState.offline);
      expect(view.showsSnapshot, isFalse);
      expect(view.showsEmptySnapshotNotice, isTrue,
          reason: 'SPEC §7 條款 1：沒有快照也要有誠實提示，不准整頁空白');
      expect(view.emptySnapshotNotice, isNotEmpty);
      expect(view.isBlankPage, isFalse);
    });

    test('online ＋ 尚未同步（無快照）→ 誠實提示而非空白', () {
      const view = HomeViewState(connection: HomeConnectionState.online);
      expect(view.showsSnapshot, isFalse);
      expect(view.showsEmptySnapshotNotice, isTrue,
          reason: '連線中但還沒資料 → 顯示提示，不准整頁空白');
      expect(view.emptySnapshotNotice, contains('正在取得最新資料'));
      expect(view.isBlankPage, isFalse);
    });

    test('offline 狀態標籤含「離線」且不含「已連線」（不裝活著）', () {
      const offline = HomeViewState(connection: HomeConnectionState.offline);
      const online = HomeViewState(connection: HomeConnectionState.online);
      expect(offline.statusLabel, contains('離線'));
      expect(offline.statusLabel, isNot(contains('已連線')));
      expect(online.statusLabel, contains('已連線'));
    });
  });

  // ─────────────────────────────────────────────────────────
  // 條款 2：上次快照＋時間戳（時間戳屬於快照、非當前時間）
  // ─────────────────────────────────────────────────────────
  group('條款 2｜顯示「上次快照＋時間戳」（時間戳屬於快照、非當前時間）', () {
    test('快照內容原樣保留', () {
      final snapshot = HomeSnapshot(
        content: const {'天氣': '晴', '番茄': 12},
        capturedAt: DateTime(2026, 11, 8, 9, 30),
      );
      expect(snapshot.content['天氣'], '晴',
          reason: 'SPEC §7 條款 2：快照內容必須原樣保留，不被加工');
      expect(snapshot.content['番茄'], 12,
          reason: 'SPEC §7 條款 2：快照內容必須原樣保留，不被加工');
      expect(snapshot.isNotEmpty, isTrue,
          reason: 'SPEC §7 條款 2：有內容的快照才算有快照可顯示');
    });

    test('capturedAt 是快照自己的時間，不是當前時間', () {
      final captured = DateTime(2026, 11, 8, 9, 30);
      final snapshot = HomeSnapshot(content: const {'a': 1}, capturedAt: captured);
      expect(snapshot.capturedAt, captured,
          reason: 'SPEC §7 條款 2：時間戳屬於快照、非當前時間');
      expect(snapshot.capturedAt.isAtSameMomentAs(DateTime.now()), isFalse,
          reason: 'SPEC §7 條款 2：時間戳屬於快照、非當前時間');
    });

    test('ageAt 反映快照與現在的時間差距', () {
      final snapshot = HomeSnapshot(
        content: const {'a': 1},
        capturedAt: DateTime(2026, 11, 8, 9, 0),
      );
      expect(snapshot.ageAt(DateTime(2026, 11, 8, 9, 30)), const Duration(minutes: 30),
          reason: 'SPEC §7 條款 2：快照年齡反映「距上次快照多久」');
      expect(snapshot.ageAt(DateTime(2026, 11, 8, 9, 0)), Duration.zero,
          reason: 'SPEC §7 條款 2：快照年齡為零（剛拍下）');
    });

    test('isStale 邊界成對：恰好等於門檻不過期、超過門檻才過期', () {
      final captured = DateTime(2026, 11, 8, 9, 0);
      final snapshot = HomeSnapshot(content: const {'a': 1}, capturedAt: captured);
      const threshold = Duration(minutes: 30);
      expect(
        snapshot.isStale(threshold, now: captured.add(threshold)),
        isFalse,
        reason: '邊界：年齡恰好等於門檻尚未過期（嚴格大於才算過期）',
      );
      expect(
        snapshot.isStale(threshold, now: captured.add(threshold + const Duration(microseconds: 1))),
        isTrue,
        reason: '邊界：超過門檻 1 微秒即為過期快照',
      );
    });

    test('capturedAtLabel 顯示快照當下的日期時間（非今日日期）', () {
      final snapshot = HomeSnapshot(
        content: const {'a': 1},
        capturedAt: DateTime(2026, 3, 7, 14, 5),
      );
      expect(snapshot.capturedAtLabel, '2026-03-07 14:05');
      expect(snapshot.capturedAtLabel, isNot(contains('2026-11-09')));
    });

    test('空快照邊界：內容為空時 isEmpty 為真（不得假裝有內容）', () {
      final snapshot = HomeSnapshot(
        content: const <String, dynamic>{},
        capturedAt: DateTime(2026, 11, 8, 9, 30),
      );
      expect(snapshot.isEmpty, isTrue);
      expect(snapshot.isNotEmpty, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────
  // 條款 3：聊天輸入框保留可打字，標「離線中，訊息重連後送出」
  // ─────────────────────────────────────────────────────────
  group('條款 3｜聊天輸入框保留可打字，標「離線中，訊息重連後送出」', () {
    test('offline 時輸入框仍可打字（不得被禁用）', () {
      const view = HomeViewState(connection: HomeConnectionState.offline);
      expect(view.inputEnabled, isTrue,
          reason: 'SPEC §7 條款 3：聊天輸入框保留可打字');
      expect(view.inputEnabled, isTrue);
    });

    test('offline 時輸入提示標「離線中，訊息重連後送出」', () {
      const view = HomeViewState(connection: HomeConnectionState.offline);
      expect(view.inputHint, '離線中，訊息重連後送出',
          reason: 'SPEC §7 條款 3：標「離線中，訊息重連後送出」');
      expect(view.inputHint, contains('重連後送出'));
    });

    test('online 時輸入提示不含離線字樣', () {
      const view = HomeViewState(connection: HomeConnectionState.online);
      expect(view.inputHint, isNot(contains('離線中')));
      expect(view.inputEnabled, isTrue);
    });

    test('offline 時輸入不吞：可排入佇列且長度遞增', () {
      final coordinator = HomeOfflineCoordinator(
        machine: HomeStateMachine(initial: HomeConnectionState.offline),
      );
      coordinator.enqueue('離線時打的第一句');
      expect(coordinator.queue.length, 1);
      expect(coordinator.queue.pending.single.text, '離線時打的第一句');
      expect(coordinator.viewState.inputEnabled, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────
  // 條款 4：離線排隊的訊息，重連後依序自動送出、不吞訊息
  // ─────────────────────────────────────────────────────────
  group('條款 4｜離線排隊的訊息，重連後依序自動送出、不吞訊息', () {
    test('enqueue 依序保留（FIFO 順序 = 送出順序）', () {
      final queue = OfflineMessageQueue();
      queue.enqueue('第一則');
      queue.enqueue('第二則');
      queue.enqueue('第三則');
      expect(queue.length, 3);
      expect(queue.pending.map((m) => m.text), ['第一則', '第二則', '第三則']);
    });

    test('dequeueAll 依序取出並清空佇列', () {
      final queue = OfflineMessageQueue();
      queue.enqueue('第一則');
      queue.enqueue('第二則');
      final taken = queue.dequeueAll();
      expect(taken.map((m) => m.text), ['第一則', '第二則']);
      expect(queue.isEmpty, isTrue);
      expect(queue.length, 0);
    });

    test('clear 清空佇列', () {
      final queue = OfflineMessageQueue();
      queue.enqueue('第一則');
      queue.clear();
      expect(queue.isEmpty, isTrue);
      expect(queue.length, 0);
    });

    test('flush 全部成功 → 依序送出、佇列清空、不吞訊息', () async {
      final queue = OfflineMessageQueue();
      queue.enqueue('第一則');
      queue.enqueue('第二則');
      queue.enqueue('第三則');
      final sent = <String>[];
      final result = await queue.flush((m) async {
        sent.add(m.text);
        return true;
      });
      expect(sent, ['第一則', '第二則', '第三則'],
          reason: 'SPEC §7 條款 4：重連後依序自動送出');
      expect(result.sent.map((m) => m.text), ['第一則', '第二則', '第三則']);
      expect(result.failed, isNull);
      expect(result.remaining, isEmpty);
      expect(queue.isEmpty, isTrue, reason: 'SPEC §7 條款 4：不吞訊息');
      expect(result.isComplete, isTrue);
    });

    test('flush 中途失敗 → 失敗者與後續保留（不吞）、順序不亂', () async {
      final queue = OfflineMessageQueue();
      queue.enqueue('第一則');
      queue.enqueue('第二則');
      queue.enqueue('第三則');
      final attempted = <String>[];
      final result = await queue.flush((m) async {
        attempted.add(m.text);
        return m.text != '第二則';
      });
      expect(attempted, ['第一則', '第二則'],
          reason: '失敗後不得跳過第三則（順序必須維持）');
      expect(result.sent.map((m) => m.text), ['第一則']);
      expect(result.failed?.text, '第二則');
      expect(result.remaining.map((m) => m.text), ['第二則', '第三則']);
      expect(queue.length, 2, reason: 'SPEC §7 條款 4：失敗訊息保留、不吞');
      expect(queue.pending.map((m) => m.text), ['第二則', '第三則']);
      expect(result.isComplete, isFalse);
    });

    test('flush 失敗後重試 → 依序補送完、訊息一個不漏', () async {
      final queue = OfflineMessageQueue();
      queue.enqueue('第一則');
      queue.enqueue('第二則');
      queue.enqueue('第三則');
      await queue.flush((m) async => m.text != '第二則');
      expect(queue.length, 2, reason: '第二則失敗 → 第二則＋第三則都留著');

      final retried = <String>[];
      final result = await queue.flush((m) async {
        retried.add(m.text);
        return true;
      });
      expect(retried, ['第二則', '第三則'],
          reason: '重試時依序補送（含先前失敗者），順序不亂');
      expect(result.sent.map((m) => m.text), ['第二則', '第三則']);
      expect(result.isComplete, isTrue);
      expect(queue.isEmpty, isTrue,
          reason: 'SPEC §7 條款 4：訊息一個不漏，全部送完才清空');
    });

    test('flush 送出拋例外 → 該訊息保留不吞', () async {
      final queue = OfflineMessageQueue();
      queue.enqueue('會爆炸的一則');
      queue.enqueue('後面一則');
      final result = await queue.flush((m) async {
        throw StateError('通道炸掉');
      });
      expect(result.failed?.text, '會爆炸的一則');
      expect(queue.length, 2, reason: '例外不得導致訊息被吞');
      expect(queue.pending.map((m) => m.text), ['會爆炸的一則', '後面一則']);
    });

    test('coordinator：離線排 3 則 → reconnect 自動依序送出、佇列清空', () async {
      final sent = <String>[];
      final coordinator = HomeOfflineCoordinator(
        machine: HomeStateMachine(initial: HomeConnectionState.offline),
        sender: (m) async {
          sent.add(m.text);
          return true;
        },
      );
      coordinator.enqueue('第一則');
      coordinator.enqueue('第二則');
      coordinator.enqueue('第三則');
      expect(coordinator.queue.length, 3);

      final result = await coordinator.handleEvent(HomeConnectionEvent.reconnect);

      expect(coordinator.machine.state, HomeConnectionState.online);
      expect(sent, ['第一則', '第二則', '第三則'],
          reason: 'SPEC §7 條款 4：重連後依序自動送出');
      expect(result.sent.length, 3);
      expect(result.isComplete, isTrue);
      expect(coordinator.queue.isEmpty, isTrue,
          reason: 'SPEC §7 條款 4：不吞訊息');
    });

    test('coordinator：online→disconnect→offline→enqueue→reconnect 全流程', () async {
      final sent = <String>[];
      final coordinator = HomeOfflineCoordinator(
        sender: (m) async {
          sent.add(m.text);
          return true;
        },
      );
      expect(coordinator.machine.state, HomeConnectionState.online);
      await coordinator.handleEvent(HomeConnectionEvent.disconnect);
      expect(coordinator.machine.state, HomeConnectionState.offline);
      expect(coordinator.viewState.isGreyedOut, isTrue);
      expect(coordinator.viewState.inputEnabled, isTrue);

      coordinator.enqueue('離線第一句');
      coordinator.enqueue('離線第二句');
      expect(coordinator.queue.length, 2);

      await coordinator.handleEvent(HomeConnectionEvent.reconnect);
      expect(coordinator.machine.state, HomeConnectionState.online);
      expect(sent, ['離線第一句', '離線第二句']);
      expect(coordinator.queue.isEmpty, isTrue);
    });

    test('coordinator：重連後送出失敗 → 訊息仍在佇列（不吞）', () async {
      final coordinator = HomeOfflineCoordinator(
        machine: HomeStateMachine(initial: HomeConnectionState.offline),
        sender: (m) async => false,
      );
      coordinator.enqueue('送不出去的訊息');
      final result = await coordinator.handleEvent(HomeConnectionEvent.reconnect);
      expect(result.failed?.text, '送不出去的訊息');
      expect(coordinator.queue.length, 1);
      expect(coordinator.queue.pending.single.text, '送不出去的訊息');
    });

    test('coordinator：非重連事件不得觸發送出（離線時不假送）', () async {
      final sent = <String>[];
      final coordinator = HomeOfflineCoordinator(
        machine: HomeStateMachine(initial: HomeConnectionState.offline),
        sender: (m) async {
          sent.add(m.text);
          return true;
        },
      );
      coordinator.enqueue('還在佇列');
      await coordinator.handleEvent(HomeConnectionEvent.timeout);
      expect(sent, isEmpty, reason: '離線時不得假裝訊息已送出');
      expect(coordinator.queue.length, 1);
    });
  });

  // ─────────────────────────────────────────────────────────
  // 條款 1（渲染層）：禁止整頁空白或轉圈騙人 —— 真的把畫面畫出來驗
  // ─────────────────────────────────────────────────────────
  group('條款 1｜渲染層：offline 首頁仍顯示快照、絕不空白、絕不轉圈', () {
    Future<void> pumpHome(
      WidgetTester tester,
      HomeViewState state, {
      TextEditingController? controller,
      ValueChanged<String>? onSubmit,
    }) async {
      // [S4 2026-11-10] TierTheme 注入——TierStyle.of 需要 ThemeExtension。
      // 測試環境 rootBundle 非同步會卡（見 tier_style.dart 註解），
      // 改同步：從同一份 asset manifest 字串直接建 registry。
      final tierTheme = TierTheme.fromManifest(
        TierRegistry.fromManifestString(
          TestManifestString.bridgeDefault,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            extensions: [BridgeDSColors.dark, tierTheme],
          ),
          home: OfflineHomeView(
            state: state,
            controller: controller,
            onSubmit: onSubmit,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offline 首頁顯示「離線」狀態、不顯示「已連線」', (tester) async {
      await pumpHome(
        tester,
        const HomeViewState(connection: HomeConnectionState.offline),
      );
      expect(find.text('離線'), findsOneWidget);
      expect(find.text('已連線'), findsNothing,
          reason: 'SPEC §7 條款 1：離線時不得顯示已連線（裝活著）');
    });

    testWidgets('online 首頁顯示「已連線」、不顯示「離線」', (tester) async {
      await pumpHome(
        tester,
        const HomeViewState(connection: HomeConnectionState.online),
      );
      expect(find.text('已連線'), findsOneWidget);
      expect(find.text('離線'), findsNothing);
    });

    testWidgets('offline 首頁不出现 CircularProgressIndicator（不轉圈騙人）', (
      tester,
    ) async {
      await pumpHome(
        tester,
        const HomeViewState(connection: HomeConnectionState.offline),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'SPEC §7 條款 1：禁止轉圈騙人');
      expect(find.byType(ProgressIndicator), findsNothing,
          reason: 'SPEC §7 條款 1：任何進度指示器都算裝活著');
    });

    testWidgets('offline 首頁有內容可見（禁止整頁空白）', (tester) async {
      await pumpHome(
        tester,
        const HomeViewState(connection: HomeConnectionState.offline),
      );
      // 離線提示字樣必須出現 → 畫面不是空的
      expect(find.textContaining('離線中'), findsWidgets,
          reason: 'SPEC §7 條款 1：禁止整頁空白——離線也要有可見內容');
    });

    testWidgets('offline ＋ 有快照 → 畫面顯示快照內容與快照時間戳', (tester) async {
      final snapshot = HomeSnapshot(
        content: const {'番茄': 12, '天氣': '晴'},
        capturedAt: DateTime(2026, 11, 8, 9, 30),
      );
      await pumpHome(
        tester,
        HomeViewState(
          connection: HomeConnectionState.offline,
          snapshot: snapshot,
        ),
      );
      // ★ 注意：狀態列也有「上次快照」字樣（「離線中，顯示的是上次快照」），
      //   所以這裡用完整字串比對，避免誤判成兩筆。
      expect(find.text('上次快照：2026-11-08 09:30'), findsOneWidget,
          reason: 'SPEC §7 條款 2：時間戳屬於快照、非當前時間');
      // [S4 2026-11-10] 語意化兩欄式渲染——key 與 value 是獨立 widget
      expect(find.text('番茄'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('天氣'), findsOneWidget);
      expect(find.text('晴'), findsOneWidget);
    });

    testWidgets('offline ＋ 無快照 → 顯示誠實提示而非空白頁', (tester) async {
      await pumpHome(
        tester,
        const HomeViewState(connection: HomeConnectionState.offline),
      );
      expect(find.textContaining('還沒有上次快照'), findsOneWidget);
    });

    testWidgets('offline 聊天輸入框可打字且標「離線中，訊息重連後送出」', (
      tester,
    ) async {
      final controller = TextEditingController();
      await pumpHome(
        tester,
        const HomeViewState(connection: HomeConnectionState.offline),
        controller: controller,
      );

      // 輸入框存在且未被禁用
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).enabled, isTrue,
          reason: 'SPEC §7 條款 3：離線時輸入框保留可打字');

      // 真的打得出字
      await tester.enterText(field, '離線時打的訊息');
      expect(controller.text, '離線時打的訊息');

      // 提示文字標記
      expect(find.text('離線中，訊息重連後送出'), findsOneWidget,
          reason: 'SPEC §7 條款 3：標「離線中，訊息重連後送出」');
    });

    testWidgets('online 聊天輸入框提示不含離線字樣', (tester) async {
      await pumpHome(
        tester,
        const HomeViewState(connection: HomeConnectionState.online),
      );
      expect(find.text('離線中，訊息重連後送出'), findsNothing);
    });

    testWidgets('offline 輸入框送出 → 交給回呼（由協調器排隊，不直接送）', (
      tester,
    ) async {
      final controller = TextEditingController(text: '要排隊的訊息');
      final submitted = <String>[];
      await pumpHome(
        tester,
        const HomeViewState(connection: HomeConnectionState.offline),
        controller: controller,
        onSubmit: submitted.add,
      );
      // [S4 2026-11-10] 送出鈕改單色箭頭 icon（Blue 符號簡約令）——改找 IconButton
      await tester.tap(find.byType(IconButton).first);
      await tester.pumpAndSettle();
      expect(submitted, ['要排隊的訊息'],
          reason: 'SPEC §7 條款 3：離線輸入不得被吞，要交給排隊流程');
    });

    testWidgets('offline 首頁整體標灰（Opacity 套用 dimmedOpacity）', (
      tester,
    ) async {
      final snapshot = HomeSnapshot(
        content: const {'番茄': 12},
        capturedAt: DateTime(2026, 11, 8, 9, 30),
      );
      await pumpHome(
        tester,
        HomeViewState(
          connection: HomeConnectionState.offline,
          snapshot: snapshot,
        ),
      );
      final opacities = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(opacities, isNotEmpty,
          reason: '離線快照區必須套用標灰（Opacity）');
      expect(
        opacities.any((o) => o.opacity < 1.0),
        isTrue,
        reason: 'SPEC §7 條款 1：離線時 UI 誠實標灰',
      );
    });
  });
}
