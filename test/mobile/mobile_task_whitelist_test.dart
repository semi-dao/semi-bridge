// [S2 白名單轉發層] 手機通道 taskType 白名單——測試先行
// SPEC 條款（BRIDGE_MOBILE_SPEC.md L105，紅隊 #13/#14 修訂）：
//   「手機僅開放白名單子集工具（清單另行拍板），其餘回『此指令僅限 Agent 本機使用』」
//
// 設計鐵則：
// - 白名單預設為空（default-deny）——沒拍板的工具手機一律看不到
// - 拒絕訊息固定文案（不洩漏白名單內容、不區分「不存在」與「不開放」）
// - 純函數：清單是資料、判定是邏輯，可直接 unit test
import 'package:bridge_app/services/mobile/mobile_task_whitelist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const denyMessage = '此指令僅限 Agent 本機使用';

  group('S2 白名單：預設拒絕（default-deny）', () {
    test('空白名單：任何 taskType 都被拒（SPEC：沒拍板＝不開放）', () {
      final wl = MobileTaskWhitelist(allowed: []);
      final r = wl.check('browser.navigate');
      expect(r.allowed, isFalse,
          reason: 'SPEC L105：手機僅開放白名單子集——空清單=全拒');
      expect(r.denyMessage, denyMessage);
    });

    test('拒絕訊息是固定文案——不洩漏白名單、不區分不存在與不開放', () {
      final wl = MobileTaskWhitelist(allowed: ['browser.navigate']);
      expect(wl.check('browser.deleteEverything').denyMessage, denyMessage);
      expect(wl.check('nonexistent.tool').denyMessage, denyMessage,
          reason: '兩種拒絕原因（不開放/不存在）訊息必須相同，防探測');
    });
  });

  group('S2 白名單：前綴匹配語意', () {
    test('白名單條目允許前綴（browser.* 語意）', () {
      final wl = MobileTaskWhitelist(allowedPrefixes: ['browser.']);
      expect(wl.check('browser.navigate').allowed, isTrue);
      expect(wl.check('browser.screenshot').allowed, isTrue);
    });

    test('前綴必須吃到點號——browser. 不該放行 browserX.y', () {
      final wl = MobileTaskWhitelist(allowedPrefixes: ['browser.']);
      expect(wl.check('browserX.y').allowed, isFalse,
          reason: '前綴比對以完整 segment 為界，防僞造命名空間');
    });

    test('精確條目只放行完全相同（不前綴）', () {
      final wl = MobileTaskWhitelist(allowed: ['runtime.ping']);
      expect(wl.check('runtime.ping').allowed, isTrue);
      expect(wl.check('runtime.ping.all').allowed, isFalse,
          reason: '精確條目不是前綴——要開放子項須明列');
    });
  });

  group('S2 白名單：能力列表一致性', () {
    test('capabilityList 只列白名單內工具（手機不該看到全量清單）', () {
      final wl = MobileTaskWhitelist(
        allowed: ['runtime.ping'],
        allowedPrefixes: ['browser.'],
      );
      final caps = wl.capabilityList(
        allTaskTypes: ['runtime.ping', 'browser.navigate', 'fs.rm', 'shell.exec'],
      );
      expect(caps, containsAll(['runtime.ping', 'browser.navigate']));
      expect(caps, isNot(contains('fs.rm')),
          reason: '未拍板的工具不能出現在手機 capabilityList');
      expect(caps, isNot(contains('shell.exec')));
    });
  });

  group('S2 白名單：大小寫與邊界', () {
    test('taskType 大小寫敏感（協議層精確比對，不做 casefold）', () {
      final wl = MobileTaskWhitelist(allowed: ['browser.navigate']);
      expect(wl.check('Browser.Navigate').allowed, isFalse);
    });

    test('空 taskType 拒絕', () {
      final wl = MobileTaskWhitelist(allowed: ['browser.navigate']);
      expect(wl.check('').allowed, isFalse);
    });
  });

  group('S4 聊天直送：chat.send 白名單（2026-11-10）', () {
    test('defaultForMobile 含 chat.send', () {
      expect(MobileTaskWhitelist.defaultForMobile.check('chat.send').allowed,
          isTrue);
    });

    test('chat.* 前綴不外溢——chat.execute 工具執行仍拒', () {
      final wl = MobileTaskWhitelist.defaultForMobile;
      expect(wl.check('chat.execute').allowed, isFalse,
          reason: '白名單放行的是 chat.send 唯文字注入，不是任意 chat 指令');
    });

    test('capabilityList 含 chat.send——手機看得到自己有的能力', () {
      expect(
        MobileTaskWhitelist.defaultForMobile
            .capabilityList(allTaskTypes: const ['chat.send', 'shell.exec']),
        contains('chat.send'),
      );
    });
  });
}
