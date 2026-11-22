// [特攻C 2026-11-17] 此刻頁真內容 v2——分頁消費邏輯鎖死測試
//
// 鎖住的行為（SPEC §8.8a/§8.8b＋此刻頁 v2）：
//   ① 分頁分配：池（圖文混排帶 kind，最新在前）→ 每頁 5 磚；
//      hero 恆「該頁最新圖」、文字磚恆「該頁最新文字檔」、
//      池不足時誠實降級（缺的磚顯示圖示，不 crash 不開天窗不假成功）。
//   ② 預載觸發：起點起連續 3 頁素材被抓（fake gateway 記錄 vaultFile 請求）；
//      換頁後窗口往前滾，超出窗口的頁不被抓、抓過的不重抓。
//   ③ 快取上限清理：縮圖快取有上限（LRU 60）——unique 請求推過上限後
//      重訪舊素材必須重抓（重複請求可證；無上限=記憶體無限成長病根）。
//
// 怎麼跑：flutter test test/mobile/now_page_pagination_test.dart
// 不連真 gateway——fake WebSocket 伺服器說 gateway 協議（hello/vaultList/
// vaultFile），_NowPage 經真 MobileBridgeClient 單例打進來（integration 式
// widget test）。禁碰實作：本檔只讀 mobile_home_screen.dart。

import 'dart:convert';
import 'dart:io';

import 'package:bridge_app/screens/mobile_home_screen.dart';
import 'package:bridge_app/services/mobile_bridge_client.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/theme/tier.dart';
import 'package:bridge_app/theme/tier_registry.dart';
import 'package:bridge_app/theme/tier_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_manifest_string.dart';

// ─────────────────────────────────────────────────────────
// Fake gateway：說 bridge desktop gateway 協議的最小伺服器
// ─────────────────────────────────────────────────────────

class FakeGateway {
  FakeGateway(this.pool, {this.texts = const {}});

  /// vaultList 回給手機的池（最新在前，每筆帶 path＋kind）
  final List<Map<String, dynamic>> pool;
  /// 文字檔全文內容（path → text）；圖檔一律回 1x1 PNG
  final Map<String, String> texts;

  late final HttpServer _server;

  /// 此刻牆預載縮圖請求（thumb:true maxPx:720）路徑序列——預載/快取記錄器。
  /// 過濾條件＝_NowPage 專屬指紋（_VaultPage 用 360、預覽器用原圖，隔開）。
  final wallThumbRequests = <String>[];
  /// 全文請求路徑（不帶 thumb）——文字磚抓全文記錄器
  final fullTextRequests = <String>[];
  /// 所有 vaultFile 請求路徑（不分 thumb/全文——總記錄器）
  final vaultFileRequests = <String>[];

  /// 所有請求型別（除 hello）
  final requestTypes = <String>[];

  int get uniqueVaultFileCount => wallThumbRequests.toSet().length;

  /// 被請求 ≥2 次的牆圖路徑（LRU 踢掉後重訪重抓＝可證上限清理生效）
  List<String> get duplicateRequests {
    final seen = <String>{};
    final dup = <String>{};
    for (final p in wallThumbRequests) {
      if (!seen.add(p)) dup.add(p);
    }
    return dup.toList();
  }

  /// 1x1 PNG（圖檔回應，base64）
  static const pngB64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

  Future<int> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.transform(WebSocketTransformer()).listen(_onSocket);
    return _server.port;
  }

  Future<void> stop() async => _server.close(force: true);

  void _onSocket(WebSocket ws) {
    ws.listen((data) {
      final req = jsonDecode(data as String) as Map<String, dynamic>;
      final type = req['type'] as String? ?? '';
      final id = req['id'] as String? ?? '';
      final payload = req['payload'] is Map
          ? Map<String, dynamic>.from(req['payload'] as Map)
          : const <String, dynamic>{};
      if (type != 'hello') requestTypes.add(type);

      Map<String, dynamic> respPayload = const {};
      switch (type) {
        case 'hello':
          respPayload = {'deviceToken': 'fake-token', 'desktopName': 'fake'};
          break;
        case 'vaultList':
          respPayload = {'total': pool.length, 'offset': 0, 'files': pool};
          break;
        case 'vaultFile': {
          final path = payload['path'] as String? ?? '';
          vaultFileRequests.add(path);
          // 牆縮圖指紋：thumb:true 且 maxPx≤720（預載路）；全文=無 thumb
          final maxPx = (payload['maxPx'] as num?) ?? 0;
          final isWallThumb = payload['thumb'] == true && maxPx == 720;
          if (isWallThumb) {
            wallThumbRequests.add(path);
          } else {
            fullTextRequests.add(path);
          }
          final text = texts[path];
          if (text != null) {
            respPayload = {
              'kind': 'text',
              'text': text,
              'size': text.length,
              'truncated': false,
            };
          } else {
            respPayload = {
              'kind': 'image',
              'base64': pngB64,
              'size': 70,
            };
          }
          break;
        }
        default:
          respPayload = const {}; // 其餘同步請求回空 ok（對話/任務/標籤…）
      }
      ws.add(jsonEncode({
        'schema': 'bridge.desktop.gateway.response.v1',
        'requestId': id,
        'type': type,
        'ok': true,
        if (respPayload.isNotEmpty) 'payload': respPayload,
      }));
    });
  }
}

// ─────────────────────────────────────────────────────────
// 池 builder（path 尾號＝池序＝新→舊；kind 顯式帶上）
// ─────────────────────────────────────────────────────────

Map<String, dynamic> _img(int i) =>
    {'path': '/v/i$i.png', 'kind': 'image', 'size': 1000};
Map<String, dynamic> _txt(int i) =>
    {'path': '/v/t$i.md', 'kind': 'text', 'size': 200};

/// 文字磚預期全文：每檔固定可認內容
Map<String, String> _bodies(List<Map<String, dynamic>> pool) => {
      for (final f in pool)
        if (f['kind'] == 'text')
          f['path'] as String: '內文_${(f['path'] as String).split('/').last}',
    };

// ─────────────────────────────────────────────────────────
// 測試驅動工具（真 IO：socket 收發必须在 runAsync 裡推進）
// ─────────────────────────────────────────────────────────

late FakeGateway _g;
late Directory _tmp;

/// 起 fake gateway＋pump 真 MobileHomeScreen＋client 配對＋等池與首輪預載收斂
Future<void> boot(WidgetTester tester, List<Map<String, dynamic>> pool) async {
  _g = FakeGateway(pool, texts: _bodies(pool));
  // HttpServer.bind 的 idleTimeout 週期 Timer 必須生在 runAsync 真時區——
  // 在 fake clock 區建會炸「Timer is still pending」（Pending timers 鐵證：
  // _HttpServer.idleTimeout=）。
  final port = await tester
      .runAsync(() => _g.start()) ?? (throw StateError('fake gateway 啟動失敗'));
  addTearDownNow(_g);
  await tester.runAsync(() => MobileBridgeClient.instance
      .connect(host: '127.0.0.1', port: port, pairingCode: 'BRIDGE-000001'));
  // [TierTheme 注入] TierStyle.of 需要 ThemeExtension（offline_behavior_test 同款）
  final tierTheme = TierTheme.fromManifest(
    TierRegistry.fromManifestString(TestManifestString.bridgeDefault),
  );
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      extensions: [BridgeDSColors.dark, tierTheme],
    ),
    home: const MobileHomeScreen(),
  ));
  // 等池到位（vaultList 已回）
  await settle(tester, () => _g.requestTypes.contains('vaultList'),
      maxRounds: 300);
  // 等首輪預載 IO 全部落地
  await drain(tester);
}

/// 排空在途 vaultFile：請求數穩定兩輪不变＝收斂
Future<void> drain(WidgetTester tester, {int maxRounds = 120}) async {
  var stable = 0;
  var last = _g.vaultFileRequests.length;
  for (var i = 0; i < maxRounds; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 16));
    if (_g.vaultFileRequests.length == last) {
      stable++;
      if (stable >= 3) return;
    } else {
      stable = 0;
      last = _g.vaultFileRequests.length;
    }
  }
}

/// 真 IO 排空＋pump 直到 predicate 或輪次盡
Future<void> settle(WidgetTester tester, bool Function() done,
    {int maxRounds = 200}) async {
  for (var i = 0; i < maxRounds; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 16));
    if (done()) return;
  }
}

/// 上/下換一頁（fling 此刻頁的 PageView）＋等換頁動畫＋預載 IO 收斂
Future<void> swipe(WidgetTester tester, {bool next = true}) async {
  final pv = nowPageView(tester);
  await tester.fling(pv, Offset(0, next ? -450 : 450), 1800);
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await settle(tester, () => true, maxRounds: 20);
  await drain(tester);
}

/// 此刻頁的 PageView（限定縱向滾動——IndexedStack 內對話頁等也有
/// PageView，byType().first 會抓錯人家的）
Finder nowPageView(WidgetTester tester) => find.byWidgetPredicate(
    (w) => w is PageView && w.scrollDirection == Axis.vertical);

void addTearDownNow(FakeGateway g) {
  // 必須用 testWidgets 內層 addTearDown（外層 tearDown() 在「Timer is still
  // pending」不變量檢查之後才跑——心跳/重連 Timer 會炸不變量）。
  addTearDown(() async {
    MobileBridgeClient.instance.disconnect();
    await g.stop();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    _tmp = Directory.systemTemp.createTempSync('now_page_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => _tmp.path,
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    MobileBridgeClient.instance.disconnect();
  });

  tearDown(() {
    MobileBridgeClient.instance.disconnect();
  });

  tearDownAll(() async {
    try {
      _tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ═════════════ ① 分頁消費邏輯 ═════════════

  group('① 分頁分配｜池→每頁磚位', () {
    testWidgets('池12筆→3頁；hero=該頁最新圖、文字磚=該頁最新文字檔全文',
        (tester) async {
      await boot(tester, [
        _txt(0), _img(1), _img(2), _txt(3), _img(4), // 頁1
        _img(5), _img(6), _txt(7), _img(8), _img(9), // 頁2
        _txt(10), _img(11), // 頁3（不足降級）
      ]);

      // DEBUG dump
      final probe = await tester.runAsync(
          () => MobileBridgeClient.instance.sendVaultFile('/v/t0.md'));
      // ignore: avoid_print
      print('PROBE t0=$probe');
      // ignore: avoid_print
      print('REQS: ${_g.vaultFileRequests}');
      expect(find.byType(PageView), findsWidgets,
          reason: '此刻頁必須是 PageView 輪播');
      expect(find.text('1/3 頁 '), findsOneWidget,
          reason: '頁碼指示 ceil(12/5)=3 頁（向上去整，不騙人）');
      // hero 恆該頁最新圖：頁1 第一張圖＝i1.png（idx0 是文字檔不可搶 hero）
      expect(find.text('i1.png'), findsWidgets,
          reason: 'hero caption 必須=頁內最新圖 i1.png');
      // 文字磚恆該頁最新文字檔：頁1 第一個 text＝t0.md 的全文
      expect(find.text('內文_t0.md'), findsWidgets,
          reason: '文字磚顯示頁內最新文字檔 t0.md 全文');
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('換到第2頁：hero=該頁最新圖、文字磚=該頁最新文字檔',
        (tester) async {
      await boot(tester, [
        _txt(0), _img(1), _img(2), _txt(3), _img(4),
        _img(5), _img(6), _txt(7), _img(8), _img(9),
        _txt(10), _img(11),
      ]);
      await swipe(tester);
      // ignore: avoid_print
      print('DBG after swipe texts=${tester.widgetList<Text>(find.byType(Text)).map((t)=>t.data).toList()}');
      await settle(tester, () => find.text('內文_t7.md').evaluate().isNotEmpty,
          maxRounds: 80);
      expect(find.text('2/3 頁 '), findsOneWidget);
      expect(find.text('內文_t7.md'), findsWidgets,
          reason: '頁2 文字磚=該頁最新文字檔 t7.md');
      expect(find.text('i5.png'), findsWidgets,
          reason: '頁2 hero=該頁最新圖 i5.png');
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('末頁池不足：誠實降級不 crash（缺磚顯示圖示開天窗禁止）',
        (tester) async {
      await boot(tester, [
        _img(0), _img(1), _img(2), _img(3), _img(4),
        _img(5), _img(6), _img(7), _img(8), _img(9),
        _txt(10), _img(11),
      ]);
      await swipe(tester); // →2
      await swipe(tester); // →3
      await settle(tester, () => find.text('內文_t10.md').evaluate().isNotEmpty,
          maxRounds: 80);
      expect(find.text('3/3 頁 '), findsOneWidget);
      expect(find.text('內文_t10.md'), findsWidgets,
          reason: '末頁文字磚仍是該頁最新文字檔');
      expect(find.text('i11.png'), findsWidgets,
          reason: '末頁 hero=該頁最新圖（文字檔之後的圖）');
      expect(tester.takeException(), isNull, reason: '末頁不足不可拋異常');
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('空池：誠實空牆不 crash、不顯示 /0 騙人頁碼', (tester) async {
      await boot(tester, []);
      expect(find.textContaining(RegExp(r'/0 頁')), findsNothing,
          reason: '空池不可顯示分母 0 的頁碼');
      expect(tester.takeException(), isNull);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // ═════════════ ② 預載觸發 ═════════════

  group('② 預載觸發｜起點起前方 3 頁被抓', () {
    testWidgets('初始：第 1-3 頁（idx0-14）全被抓、第 5 頁不被抓', (tester) async {
      await boot(tester, [for (var i = 0; i < 25; i++) _img(i)]); // 5 頁全圖
      final grabbed = _g.wallThumbRequests.toSet();
      for (var i = 0; i < 15; i++) {
        expect(grabbed, contains('/v/i$i.png'),
            reason: '起點起 3 頁素材必須全預載，缺 i$i');
      }
      for (var i = 20; i < 25; i++) {
        expect(grabbed, isNot(contains('/v/i$i.png')),
            reason: '超出窗口的第 5 頁不可被抓，i$i 漏抓=窗口過大');
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('換頁後窗口前滾：新頁（第4頁 idx15-19）被抓', (tester) async {
      await boot(tester, [for (var i = 0; i < 25; i++) _img(i)]);
      final before = _g.wallThumbRequests.length;
      await swipe(tester);
      expect(_g.wallThumbRequests.length, greaterThan(before),
          reason: 'onPageChanged 必須觸發新一頁素材抓取');
      final grabbed = _g.wallThumbRequests.toSet();
      expect(
          grabbed.intersection({for (var i = 15; i < 20; i++) '/v/i$i.png'}),
          isNotEmpty,
          reason: '換頁後新進入窗口的 idx15-19 應被抓到');
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('抓過的不重抓（cache/inflight 除重）', (tester) async {
      await boot(tester, [for (var i = 0; i < 25; i++) _img(i)]);
      for (var i = 0; i < 15; i++) {
        expect(_g.wallThumbRequests.where((p) => p == '/v/i$i.png').length, 1,
            reason: '初始窗口每檔恰好一次（除重失靈=風暴病根）');
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // ═════════════ ③ 快取上限清理 ═════════════

  group('③ 快取上限清理', () {
    testWidgets('unique 推過上限後重訪舊圖必須重抓（LRU 清理生效）',
        (tester) async {
      await boot(tester, [for (var i = 0; i < 70; i++) _img(i)]); // 14 頁全圖
      for (var g = 0; g < 16 && _g.uniqueVaultFileCount <= 60; g++) {
        await swipe(tester);
      }
      expect(_g.uniqueVaultFileCount, greaterThan(60),
          reason: '翻頁必須把 unique 推過 60（否則本測試無效）');
      for (var g = 0; g < 24 && _g.duplicateRequests.isEmpty; g++) {
        await swipe(tester, next: false);
      }
      expect(_g.duplicateRequests, isNotEmpty,
          reason: '超上限後重訪舊素材必須重抓＝快取有上限清理；'
              '零重複=快取無限成長病根');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  // ═════════════ ④ 圖不足向後補圖 ═════════════
  // [2026-11-20 此刻頁三刀·刀①] 切片圖不足（<3 張）→ 向切片之後的池範圍
  // （下 30 筆）掃 image 補縮圖請求集，讓磚型有圖可顯示。
  group('④ 圖不足切片向後補圖', () {
    testWidgets('頁1切片僅1圖→其後 30 筆內的圖全進縮圖請求集', (tester) async {
      // 頁1 = 4文1圖（圖文比失衡的真實切片）；頁2起全是圖
      await boot(tester, [
        _txt(0), _txt(1), _img(2), _txt(3), _txt(4), // 頁1：只有 i2 一張圖
        _img(5), _img(6), _img(7), _img(8), _img(9), // 頁2：全圖（補圖來源）
        _img(10), _img(11), _img(12), _img(13), _img(14), // 頁3
      ]);
      final grabbed = _g.wallThumbRequests.toSet();
      // 切片內唯一圖照抓
      expect(grabbed, contains('/v/i2.png'),
          reason: '切片內圖必須照常預載');
      // 圖不足 → 向後 30 筆的圖必須全部進請求集（補圖來源）
      for (var i = 5; i <= 9; i++) {
        expect(grabbed, contains('/v/i$i.png'),
            reason: '頁1圖不足，切片之後的 i$i 必須被補進縮圖請求集');
      }
      // hero caption 恆該頁最新圖（補圖不搶 hero 語義）
      expect(find.text('i2.png'), findsWidgets,
          reason: 'hero 仍是切片內最新圖 i2.png');
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('補圖不越窗：切片之後 30 筆外的圖不被抓', (tester) async {
      // 頁1圖不足（1圖）→ 向後 30 筆＝idx5-34：i5-i14 有圖可補、t15-t34 是文字。
      // i35+（idx35-39）在頁1的 30 筆窗口之外、又不在預載頁窗口（頁1-3=idx0-14）
      // → 任何路徑都不該被抓。頁2/3 圖充足（≥3）不觸發自己的補圖。
      await boot(tester, [
        _txt(0), _txt(1), _img(2), _txt(3), _txt(4), // 頁1：1圖
        _img(5), _img(6), _img(7), _img(8), _img(9), // 頁2：全圖
        _img(10), _img(11), _img(12), _img(13), _img(14), // 頁3：全圖
        for (var i = 15; i < 35; i++) _txt(i), // idx15-34：文字（補圖窗內無圖可補）
        _img(35), _img(36), _img(37), _img(38), _img(39), // idx35+：窗口外的圖
      ]);
      final grabbed = _g.wallThumbRequests.toSet();
      // 補圖窗內（頁1之後 30 筆）的圖有被抓
      expect(grabbed, contains('/v/i9.png'),
          reason: '頁1圖不足，補圖窗（idx5-34）內的圖要被抓');
      // 窗口外（補圖 30 筆之外＋預載頁窗口之外）的圖不被抓
      for (var i = 35; i <= 39; i++) {
        expect(grabbed, isNot(contains('/v/i$i.png')),
            reason: '補圖窗口上限 30 筆，越界的 i$i 不可被抓');
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
