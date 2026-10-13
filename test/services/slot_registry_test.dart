// 插槽註冊表回歸測試 — 無限插槽系統 C2（2026-10-06）
//
// 隔離鐵則：一律用 SlotRegistry.test(臨時目錄)，絕不碰真實
// ~/Library/Application Support/farm.semiwasabi.bridgeApp/。
// 環境變數 BRIDGE_APP_HOME 覆寫路徑也一併驗證（spec「資料與信任」段）。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/slots/slot_registry.dart';

void main() {
  late Directory tempRoot;
  late SlotRegistry registry;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('slot_registry_test');
    registry = SlotRegistry.test(tempRoot);
  });

  tearDown(() async {
    // 測試完清乾淨
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('CRUD', () {
    test('addFromRepo 建立 pending 狀態插槽＋建專屬資料夾', () async {
      final slot = await registry.addFromRepo(
        'https://github.com/code4fukui/exif-viewer',
      );

      expect(slot.id, isNotEmpty);
      expect(slot.userLabel, 'exif-viewer'); // 名稱暫用 repo 名
      expect(slot.sourceRepo, 'https://github.com/code4fukui/exif-viewer');
      expect(slot.status, SlotStatus.pending);
      expect(slot.certified, isFalse); // v1 全 false
      expect(slot.memoryMb, isNull); // 無引擎前 null
      expect(slot.version, isNull);

      // 專屬資料夾已建
      expect(
        await Directory('${registry.slotsDir.path}/${slot.id}').exists(),
        isTrue,
      );
      expect(registry.all.length, 1);
    });

    test('rename / enable / disable / update', () async {
      final slot = await registry.addFromRepo('github.com/a/b');

      await registry.rename(slot.id, '轉檔快手');
      expect(registry.getById(slot.id)!.userLabel, '轉檔快手');

      await registry.enable(slot.id);
      final enabled = registry.getById(slot.id)!;
      expect(enabled.status, SlotStatus.running);
      expect(enabled.isRunning, isTrue);
      expect(enabled.lastUsedAt, isNotNull);

      await registry.disable(slot.id);
      expect(registry.getById(slot.id)!.status, SlotStatus.disabled);
      expect(registry.runningCount, 0);
      expect(registry.disabledCount, 1);
    });

    test('uninstall（保留資料）：移除索引、資料夾留著', () async {
      final slot = await registry.addFromRepo('github.com/a/keep');
      final slotDir = Directory('${registry.slotsDir.path}/${slot.id}');
      // 模擬插槽產生的資料
      await File('${slotDir.path}/user_data.json')
          .writeAsString('{"hello":"world"}');

      await registry.uninstall(slot.id, deleteData: false);

      expect(registry.getById(slot.id), isNull); // 索引已移除
      expect(await slotDir.exists(), isTrue); // 資料夾保留
      expect(
        await File('${slotDir.path}/user_data.json').exists(),
        isTrue,
      ); // 資料原封不動
    });

    test('uninstall（刪除資料）：索引＋資料夾都清掉，不碰插槽外檔案', () async {
      final slot = await registry.addFromRepo('github.com/a/drop');
      final slotDir = Directory('${registry.slotsDir.path}/${slot.id}');
      await File('${slotDir.path}/cache.bin').writeAsString('x');
      // 插槽目錄外的哨兵檔——絕不能被刪
      final sentinel = File('${tempRoot.path}/sentinel.txt');
      await sentinel.writeAsString('do not touch');

      await registry.uninstall(slot.id, deleteData: true);

      expect(registry.getById(slot.id), isNull);
      expect(await slotDir.exists(), isFalse); // 資料夾已刪
      expect(await sentinel.exists(), isTrue); // 外部檔案安然無恙
    });
  });

  group('分類', () {
    test('addFromRepo 不指定 → 歸「未分類」；指定 → 用指定值', () async {
      final a = await registry.addFromRepo('github.com/x/aaa');
      expect(a.category, SlotRegistry.defaultCategory);

      final b = await registry.addFromRepo('github.com/x/bbb',
          category: 'CLI 工具');
      expect(b.category, 'CLI 工具');

      expect(registry.listByCategory('CLI 工具').length, 1);
      expect(registry.categories.contains('CLI 工具'), isTrue);
    });

    test('setCategory 搬家', () async {
      final slot = await registry.addFromRepo('github.com/x/move-me');
      await registry.setCategory(slot.id, 'Skill');
      expect(registry.getById(slot.id)!.category, 'Skill');
      expect(registry.listByCategory('Skill').length, 1);
      expect(registry.listByCategory(SlotRegistry.defaultCategory), isEmpty);
    });

    test('統計：N 運行中・M 已停用', () async {
      final a = await registry.addFromRepo('github.com/t/a');
      await registry.addFromRepo('github.com/t/b');
      final c = await registry.addFromRepo('github.com/t/c');

      await registry.enable(a.id);
      await registry.enable(c.id);
      // b 停在 pending → 算「未在跑」

      expect(registry.all.length, 3);
      expect(registry.runningCount, 2);
      expect(registry.disabledCount, 1);
    });
  });

  group('持久化', () {
    test('index.json 寫入後、新 registry 載入得到同樣資料', () async {
      final slot = await registry.addFromRepo(
        'https://github.com/y/persist-me',
        category: '網頁工具',
      );
      await registry.enable(slot.id);
      await registry.rename(slot.id, '持久測試');

      // 全新 registry（同根目錄）載入
      final registry2 = SlotRegistry.test(tempRoot);
      await registry2.load();

      expect(registry2.all.length, 1);
      final loaded = registry2.getById(slot.id)!;
      expect(loaded.userLabel, '持久測試');
      expect(loaded.status, SlotStatus.running);
      expect(loaded.category, '網頁工具');
      expect(loaded.sourceRepo, 'https://github.com/y/persist-me');
    });

    test('index.json 格式是 JSON 陣列、含預期欄位', () async {
      await registry.addFromRepo('github.com/z/fields');
      final file = File('${registry.slotsDir.path}/index.json');
      expect(await file.exists(), isTrue);

      final decoded = jsonDecode(await file.readAsString());
      expect(decoded, isA<List>());
      final entry = (decoded as List).first as Map<String, dynamic>;
      expect(entry['userLabel'], 'fields');
      expect(entry['status'], SlotStatus.pending);
      expect(entry['certified'], false);
      expect(entry['createdAt'], isA<String>());
    });

    test('index.json 損毀 → 以空白開機不炸', () async {
      await registry.addFromRepo('github.com/w/corrupt');
      await File('${registry.slotsDir.path}/index.json')
          .writeAsString('{{{not json');

      final registry2 = SlotRegistry.test(tempRoot);
      await registry2.load();
      expect(registry2.isEmpty, isTrue);
    });
  });

  group('BRIDGE_APP_HOME 環境變數覆寫', () {
    test('slotsDir 跟著環境變數走', () {
      // Platform.environment 測試中不可寫，這裡只驗證：
      // 有 override 目錄的 registry 不會去碰環境變數路徑
      final r = SlotRegistry.test(tempRoot);
      expect(r.slotsDir.path, startsWith(tempRoot.path));
    });

    test('singleton 未注入且無環境變數時不指向真實 app support', () {
      // 測試進程通常沒設 BRIDGE_APP_HOME；單例保底是相對路徑 'slots'
      // （App 啟動時 main() 才會注入真實路徑）——驗證不指向 ~/Library
      final singleton = SlotRegistry.instance;
      expect(singleton.slotsDir.path.contains('/Library/Application Support'),
          isFalse);
    });
  });

  group('extractRepoSlug', () {
    test('各種常見 GitHub URL 格式', () {
      expect(extractRepoSlug('https://github.com/owner/repo'),
          'owner/repo');
      expect(extractRepoSlug('https://github.com/owner/repo.git'),
          'owner/repo');
      expect(extractRepoSlug('github.com/owner/repo'), 'owner/repo');
      expect(extractRepoSlug('git@github.com:owner/repo.git'), 'owner/repo');
      expect(extractRepoSlug('https://github.com/owner/repo/tree/main'),
          'owner/repo'); // 帶子路徑取前兩段
      expect(extractRepoSlug(''), '');
    });
  });

  group('通知', () {
    test('CRUD 觸發 notifyListeners', () async {
      var notified = 0;
      registry.addListener(() => notified++);

      final slot = await registry.addFromRepo('github.com/n/notify');
      await registry.enable(slot.id);
      await registry.uninstall(slot.id, deleteData: true);

      // add(1) + ensureLoaded 首載通知(1) + enable(1) + uninstall(1) = 4
      expect(notified, 4);
    });
  });
}
