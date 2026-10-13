import 'dart:io';
import 'package:bridge_app/models/bridge_action.dart';
import 'package:bridge_app/screens/golden_keys_screen.dart';
import 'package:bridge_app/services/capability_activation_signal.dart';
import 'package:bridge_app/services/local_hardware_profile_store.dart';
import 'package:bridge_app/services/macos_desktop_shell_channel.dart';
import 'package:bridge_app/services/storage_service.dart';
import 'package:bridge_app/theme/tier_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MacosDesktopShellChannel.channelName);

  setUp(() {
    // [hang 修復 2026-09-22] macOS token 走 golden_keys.json → 會問
    // path_provider → FakeAsync 掛死。注入臨時目錄繞過。
    StorageService.useTestTokenDirectory(
      Directory.systemTemp.createTempSync('bridge_gk_token_'),
    );
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    CapabilityActivationBus.instance.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'hardwareProfile') return null;
          return null;
        });
  });

  tearDown(() {
    StorageService.useTestTokenDirectory(null);
    CapabilityActivationBus.instance.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('golden keys center renders cloud and local model keys', (
    tester,
  ) async {
    await tester.pumpWidget(_TestApp(child: const GoldenKeysScreen()));
    await _pumpSettled(tester);

    expect(find.text('金鑰匙中心'), findsOneWidget);
    expect(find.text('主腦鑰匙'), findsOneWidget);
    expect(find.text('創造鑰匙'), findsOneWidget);
    expect(find.text('搜尋鑰匙'), findsOneWidget);
    expect(find.text('本地模型鑰匙'), findsOneWidget);
    expect(find.text('待桌面檢測'), findsOneWidget);
    expect(find.text('Bridge Local Runtime'), findsOneWidget);
    expect(find.text('尚未安裝'), findsOneWidget);
    expect(find.text('請在 Bridge Desktop 內下載'), findsOneWidget);
    expect(find.text('進階：連接既有服務'), findsOneWidget);
    expect(find.text('設成本地主腦'), findsOneWidget);
    expect(find.textContaining('入門 0.5B 測試模型'), findsNothing);
    // [2026-09-22] catalog 改版：0.5B/3B/7B/14B 四級距 → 3 模型
    // （Qwen3.5-4B / Gemma 4 E4B / Llama 3.2 3B）
    expect(find.textContaining('Qwen3.5-4B'), findsOneWidget);
    expect(find.textContaining('Gemma 4 E4B'), findsOneWidget); // [2026-10-13] 12B 登基後 'Gemma 4' 命中 2 張卡，改精確比對
    expect(find.textContaining('Llama 3.2 3B'), findsOneWidget);
    expect(find.text('任務分配'), findsOneWidget);
    expect(find.text('待設定'), findsWidgets);
    expect(find.text('設定雲端主腦'), findsOneWidget);
    expect(find.text('設定圖片生成金鑰'), findsOneWidget);
    expect(find.text('設定搜尋金鑰'), findsOneWidget);
    expect(find.text('私人草稿'), findsOneWidget);
    expect(find.text('形象與圖片生成'), findsOneWidget);
    expect(find.text('自動判斷'), findsWidgets);
    expect(find.text('編輯雲端鑰匙'), findsOneWidget);
  });

  testWidgets('golden keys exposes formal bridge capability signals', (
    tester,
  ) async {
    await tester.pumpWidget(_TestApp(child: const GoldenKeysScreen()));
    await _pumpSettled(tester);

    expect(find.text('正式橋能力'), findsOneWidget);
    expect(find.text('新聞與網頁搜尋'), findsOneWidget);
    expect(find.text('音樂生成'), findsOneWidget);
    expect(find.text('桌面檔案整理'), findsOneWidget);
    expect(find.text('圖片辨識'), findsOneWidget);

    await tester.ensureVisible(find.text('音樂生成'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('formal-bridge-ready-music')));
    await tester.pumpAndSettle();

    final signal = CapabilityActivationBus.instance.latest.value;
    expect(signal, isNotNull);
    expect(signal!.title, '音樂生成能力已開通');
    expect(signal.actionType, BridgeActionType.generateMusic);
  });

  testWidgets('golden keys center reports ready cloud creation keys', (
    tester,
  ) async {
    // [hang 修復] StorageService 寫入是真實檔案 IO——runAsync 開洞執行
    await tester.runAsync(() async {
      await StorageService.saveProvider('kimi');
      await StorageService.saveToken('kimi-token', provider: 'kimi');
      await StorageService.saveToken('replicate-token', provider: 'replicate');
      await StorageService.saveLocalModelEndpoint('http://127.0.0.1:11434');
      await StorageService.saveLocalModelName('llama3.1:8b');
    });

    await tester.pumpWidget(_TestApp(child: const GoldenKeysScreen()));
    await _pumpSettled(tester);

    expect(find.textContaining('主腦與形象生成都已準備好'), findsOneWidget);
    expect(find.text('Kimi · 目前主腦 provider 已設定 token'), findsOneWidget);
    expect(find.textContaining('Replicate'), findsWidgets);
    expect(find.text('本地主腦可用'), findsOneWidget);
    expect(find.text('llama3.1:8b'), findsOneWidget);
    expect(find.text('雲端優先'), findsWidgets);
  });

  testWidgets('golden keys center evaluates models with desktop hardware', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'hardwareProfile') return null;
          return {
            'source': 'macos-method-channel',
            'ramGb': 32,
            'vramGb': 8,
            'chipLabel': 'Test Mac · 32GB RAM',
            'desktopConnected': true,
          };
        });

    await tester.pumpWidget(_TestApp(child: const GoldenKeysScreen()));
    await _pumpSettled(tester);

    expect(find.text('可評估'), findsOneWidget);
    expect(find.textContaining('Test Mac · 32GB RAM 已連接'), findsOneWidget);
    expect(find.textContaining('RAM 32GB · VRAM 8GB'), findsOneWidget);
    expect(find.text('很適合'), findsWidgets);
    // [2026-09-22] catalog 改版：模型清單換新，來源標籤也換
    expect(find.textContaining('HuggingFace'), findsWidgets);
    expect(find.text('本地優先'), findsWidgets);

    final cached = await const LocalHardwareProfileStore().load();
    expect(cached, isNotNull);
    expect(cached!.ramGb, 32);
  });

  testWidgets('golden keys center downloads preferred Bridge Local model', (
    tester,
  ) async {
    final localRuntimeActions = <String>[];
    Map<Object?, Object?>? downloadModel;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'hardwareProfile') {
            return {
              'source': 'macos-method-channel',
              'ramGb': 32,
              'vramGb': 8,
              'chipLabel': 'Test Mac · 32GB RAM',
              'desktopConnected': true,
            };
          }
          if (call.method == 'localRuntime') {
            final payload = call.arguments as Map<Object?, Object?>;
            final action = payload['action'] as String;
            localRuntimeActions.add(action);
            if (action == 'status') {
              return {
                'phase': 'installed',
                'title': 'Bridge Local Runtime',
                'detail': 'ready for model download',
                'primaryCommand': 'downloadModel',
                'primaryActionLabel': '下載推薦模型',
                'primaryActionEnabled': true,
              };
            }
            if (action == 'downloadModel') {
              downloadModel = payload['model'] as Map<Object?, Object?>;
              return {
                'phase': 'downloading',
                'title': 'Bridge Local Runtime',
                'detail': 'downloading',
                'primaryCommand': 'status',
                'primaryActionLabel': '下載中',
                'primaryActionEnabled': false,
                'progress': 0.05,
              };
            }
          }
          return null;
        });

    await tester.pumpWidget(_TestApp(child: const GoldenKeysScreen()));
    await _pumpSettled(tester);

    await tester.ensureVisible(find.text('下載推薦模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下載推薦模型'));
    await tester.pumpAndSettle();

    expect(
      localRuntimeActions,
      containsAllInOrder(['status', 'downloadModel']),
    );
    expect(downloadModel, isNotNull);
    // [2026-09-22] catalog 改版：推薦下載模型 = Qwen3.5-4B
    expect(downloadModel!['id'], 'qwen3.5-4b-q4');
    final sourceManifest =
        downloadModel!['sourceManifest'] as Map<Object?, Object?>;
    expect(
      sourceManifest['manifestUrl'],
      'https://huggingface.co/HauhauCS/Qwen3.5-4B-Uncensored-HauhauCS-Aggressive',
    );
    expect(
      sourceManifest['downloadUrl'],
      contains('Qwen3.5-4B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf'),
    );
  });

  testWidgets('golden keys center explains local downloads need desktop app', (
    tester,
  ) async {
    final localRuntimeActions = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'hardwareProfile') return null;
          if (call.method == 'localRuntime') {
            final payload = call.arguments as Map<Object?, Object?>;
            localRuntimeActions.add(payload['action'] as String);
            return {
              'phase': 'notInstalled',
              'title': 'Bridge Local Runtime',
              'detail': 'runtime unavailable',
              'primaryCommand': 'prepareRuntime',
              'primaryActionLabel': '準備下載本地引擎',
              'primaryActionEnabled': true,
            };
          }
          return null;
        });

    await tester.pumpWidget(_TestApp(child: const GoldenKeysScreen()));
    await _pumpSettled(tester);

    expect(find.textContaining('本地模型下載與啟動需要 Bridge Desktop'), findsOneWidget);
    expect(find.text('請在 Bridge Desktop 內下載'), findsOneWidget);

    await tester.ensureVisible(find.text('請在 Bridge Desktop 內下載'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('請在 Bridge Desktop 內下載'));
    await tester.pumpAndSettle();

    expect(localRuntimeActions, ['status']);
  });
}


// [2026-09-22] GoldenKeysScreen 的 _loadSnapshot 是 real-async 鏈
// （readiness + health + catalog + hardware + runtime 全是真的 IO），
// pumpAndSettle 等不到——輪詢直到畫面出現內容（最長 5 秒）。
Future<void> _pumpSettled(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final hasContent = find
        .byType(GoldenKeysScreen)
        .evaluate()
        .isNotEmpty;
    final stillLoading = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    if (hasContent && !stillLoading) return;
  }
}

class _TestApp extends StatelessWidget {
  final Widget child;

  const _TestApp({required this.child});

  @override
  Widget build(BuildContext context) {
    // [Tier 整肅 2026-09-21 後] GoldenKeysScreen 的卡都走 TierStyle.of()
    // ——host 須掛 TierTheme（loadDefaultTierTheme 已記憶化）。
    return FutureBuilder(
      future: loadDefaultTierTheme(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const MaterialApp(home: SizedBox.shrink());
        }
        return MaterialApp.router(
          theme: ThemeData.dark().copyWith(extensions: [snap.data!]),
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (context, state) => child),
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SizedBox(),
              ),
              GoRoute(
                path: '/first-summon',
                builder: (context, state) => const SizedBox(),
              ),
            ],
          ),
        );
      },
    );
  }
}
