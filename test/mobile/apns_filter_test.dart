// [S3 提前·蜂群演習二 Wave 2] APNs 輸出濾網——紅隊加固測試
// 依據：BRIDGE_MOBILE_SPEC.md v0.5 §7「推播基礎設施」拍板 A＋紅隊 #17
// 紅隊來源：docs/drill2/T5_APNs濾網_test.dart.review.txt（6 條 issues 全消化）
// 品質範本：test/mobile/domino_engine_test.dart
//
// ⚠️ 本檔 import 正式實作（lib/services/mobile/push/apns_output_filter.dart），
//    禁綁佔位實作——紅隊 #5「測試綁定佔位實作可能假陽性」由此杜絕。
//
// SPEC 條款（原文錨定）：
// - 「通知文字只放開放層內容，APNs 送出前過輸出濾網（比對機密層實體清單，
//    命中即降級為『有新報告，請開 App 查看』）」
// - 「LLM 轉譯若幻覺塞入帳本數字，濾網攔截，不只靠紀律」

import 'dart:io';

import 'package:bridge_app/services/mobile/push/apns_output_filter.dart';
import 'package:bridge_app/services/mobile/push/apns_push_sender.dart';
import 'package:flutter_test/flutter_test.dart';

/// SPEC §7 原文降級文案（測試端寫死，不引用常數——避免常數被改後測試跟著綠）。
const String _specFallback = '有新報告，請開 App 查看';

/// 錄製型 APNs 傳輸層（測試替身）：記住所有實際送出的載荷。
class _RecordingTransport implements ApnsTransport {
  final List<ApnsPushPayload> sent = [];

  @override
  Future<void> send(ApnsPushPayload payload) async {
    sent.add(payload);
  }
}

void main() {
  group('紅隊#2 數字變體（千分位/全形/頓號/連字號/金額/中文數字）', () {
    test('千分位半形逗號：清單「1240」vs 文案「1,240」→ 降級', () {
      expect(
        pushNotificationText('產量 1,240kg', ['1240']),
        _specFallback,
      );
    });

    test('全形逗號＋全形數字：文案「１，２４０」→ 降級', () {
      expect(
        pushNotificationText('產量 １，２４０kg', ['1240']),
        _specFallback,
      );
    });

    test('頓號分隔數字：清單「1,240」vs 文案「1、240」→ 降級', () {
      expect(pushNotificationText('1、240', ['1,240']), _specFallback);
    });

    test('連字號移除：清單「20261109」vs 文案「2026-11-09」→ 降級', () {
      expect(
        pushNotificationText('紀錄日 2026-11-09', ['20261109']),
        _specFallback,
      );
    });

    test('金額千分位：清單「45000」vs 文案「NT\$45,000 元」→ 降級', () {
      expect(
        pushNotificationText('帳本金額 NT\$45,000 元', ['45000']),
        _specFallback,
      );
    });

    test('千分位大數：清單「1240000」vs 文案「1,240,000」→ 降級', () {
      expect(
        pushNotificationText('年產值 1,240,000 元', ['1240000']),
        _specFallback,
      );
    });

    test('中文數字幻覺：清單「1240」vs 文案「一千二百四十」→ 降級', () {
      expect(
        pushNotificationText('產量一千二百四十公斤', ['1240']),
        _specFallback,
      );
    });

    test('term 與 text 正規化形式不同：清單「1,240」vs 文案「1240kg」→ 降級', () {
      expect(pushNotificationText('1240kg', ['1,240']), _specFallback);
    });

    test('單位大小寫：文案「1,240KG」vs 清單「1240」→ 降級', () {
      expect(pushNotificationText('產量 1,240KG', ['1240']), _specFallback);
    });

    test('英文大小寫不敏感：清單「led sensor」vs 文案「LED Sensor」→ 降級', () {
      expect(
        pushNotificationText('LED Sensor Online', ['led sensor']),
        _specFallback,
      );
    });
  });

  group('紅隊#3 LLM 幻覺塞入帳本數字', () {
    test('幻覺帳本金額：文案「今日帳本為 45,000 元」→ 降級', () {
      expect(
        pushNotificationText('今日帳本為 45,000 元', ['帳本', '45000']),
        _specFallback,
      );
    });

    test('幻覺餘額數字：文案「目前餘額 1,240,000 元」→ 降級', () {
      expect(
        pushNotificationText('目前餘額 1,240,000 元', ['1240000']),
        _specFallback,
      );
    });

    test('幻覺成本金額：文案「本次成本 8,800 元」vs 清單「8800」→ 降級', () {
      expect(
        pushNotificationText('本次成本 8,800 元', ['8800']),
        _specFallback,
      );
    });

    test('幻覺帳本＋數字同時出現 → 仍固定降級', () {
      expect(
        pushNotificationText('帳本更新：本期 45,000 元', ['帳本', '45000']),
        _specFallback,
      );
    });
  });

  group('紅隊#4 機密詞嵌入與邊界', () {
    test('前綴嵌入：清單「產量」vs 文案「產量預估已更新」→ 降級', () {
      expect(pushNotificationText('產量預估已更新', ['產量']), _specFallback);
    });

    test('詞中嵌入：清單「產量」vs 文案「總產量報表」→ 降級', () {
      expect(pushNotificationText('總產量報表已同步', ['產量']), _specFallback);
    });

    test('後綴嵌入：清單「帳本」vs 文案「餘額帳本更新」→ 降級', () {
      expect(pushNotificationText('餘額帳本更新', ['帳本']), _specFallback);
    });

    test('跨標點嵌入：清單「帳本」vs 文案「帳本:45,000」→ 降級', () {
      expect(pushNotificationText('帳本:45,000', ['帳本']), _specFallback);
    });

    test('全形英文字母：清單「LED」vs 文案「ＬＥＤ 感測器」→ 降級', () {
      expect(pushNotificationText('ＬＥＤ 感測器', ['LED']), _specFallback);
    });

    test('繁簡同詞：清單「產量」（繁）vs 文案「产量」（簡）→ 降級', () {
      expect(pushNotificationText('产量 1240', ['產量']), _specFallback);
    });

    test('多詞清單任一命中 → 降級', () {
      const terms = ['產量', '帳本', '餘額'];
      expect(pushNotificationText('今日產量穩定', terms), _specFallback);
      expect(pushNotificationText('帳本已更新', terms), _specFallback);
      expect(pushNotificationText('餘額變動', terms), _specFallback);
    });

    test('空清單 → 原文放行', () {
      expect(
        pushNotificationText('產量 1,240kg', []),
        '產量 1,240kg',
      );
    });

    test('清單含空字串 → 忽略空字串（等同空清單放行）', () {
      expect(
        pushNotificationText('產量 1,240kg', ['', '   ']),
        '產量 1,240kg',
      );
    });

    test('空文案 → 放行（空字串）', () {
      expect(pushNotificationText('', ['產量', '帳本']), '');
    });

    test('正常數字但非機密詞 → 放行', () {
      expect(
        pushNotificationText('今天 30 度，適合澆水', ['產量', '帳本']),
        '今天 30 度，適合澆水',
      );
    });
  });

  group('紅隊#6 降級與放行輸出細節', () {
    test('多命中仍固定降級（不得拼接多段原文）', () {
      expect(
        pushNotificationText('產量 1,240，帳本 45,000', ['產量', '帳本']),
        _specFallback,
      );
    });

    test('不同命中詞 → 同一固定降級文案', () {
      final hitByTerm = pushNotificationText('產量 1,240', ['產量']);
      final hitByNumber = pushNotificationText('帳本 45,000', ['45000']);
      expect(hitByTerm, _specFallback);
      expect(hitByNumber, _specFallback);
      expect(hitByTerm, hitByNumber);
    });

    test('降級輸出不洩漏原機密詞（含正規化形式）', () {
      const terms = ['產量', '帳本', '45000'];
      final out = pushNotificationText('產量 1,240，帳本 45,000', terms);
      for (final term in terms) {
        expect(out.contains(term), isFalse,
            reason: '降級文案不得含原機密詞：$term');
        expect(out.toLowerCase().contains(term.toLowerCase()), isFalse,
            reason: '降級文案不得含原機密詞（大小寫變體）：$term');
      }
    });

    test('降級輸出不含任何數字（幻覺數字不外流）', () {
      final out = pushNotificationText('帳本 45,000 元', ['帳本']);
      expect(RegExp(r'\d').hasMatch(out), isFalse);
    });

    test('放行時原文逐字保留（標點/大小寫/emoji/全形皆不動）', () {
      const original = 'App 已更新 🎉 v1.2.3（測試）— 請開啟查看';
      expect(pushNotificationText(original, ['產量', '帳本']), original);
    });
  });

  group('紅隊#1 APNs 送出前必過濾網（整合層）', () {
    test('標題命中機密 → 傳輸層收到降級文案', () async {
      final transport = _RecordingTransport();
      final sender = ApnsPushSender(
        transport: transport,
        confidentialTermsProvider: () => const ['產量'],
      );

      await sender.send(title: '農場產量更新', body: '請開 App 查看');

      expect(transport.sent, hasLength(1));
      expect(transport.sent.single.title, _specFallback);
      expect(transport.sent.single.body, '請開 App 查看');
    });

    test('內文命中機密 → 傳輸層收到降級文案', () async {
      final transport = _RecordingTransport();
      final sender = ApnsPushSender(
        transport: transport,
        confidentialTermsProvider: () => const ['帳本'],
      );

      await sender.send(title: '有新通知', body: '帳本目前 45,000 元');

      expect(transport.sent.single.title, '有新通知');
      expect(transport.sent.single.body, _specFallback);
    });

    test('未命中 → 傳輸層收到原文（逐字）', () async {
      final transport = _RecordingTransport();
      final sender = ApnsPushSender(
        transport: transport,
        confidentialTermsProvider: () => const ['產量', '帳本'],
      );

      await sender.send(title: '今天 30 度', body: '適合澆水');

      expect(transport.sent.single.title, '今天 30 度');
      expect(transport.sent.single.body, '適合澆水');
    });

    test('傳輸層收到的內容從未含原文機密字串', () async {
      final transport = _RecordingTransport();
      final sender = ApnsPushSender(
        transport: transport,
        confidentialTermsProvider: () => const ['產量', '帳本', '45000'],
      );

      await sender.send(title: '產量 1,240', body: '帳本 45,000 元');

      for (final payload in transport.sent) {
        expect(payload.title.contains('1,240'), isFalse);
        expect(payload.body.contains('45,000'), isFalse);
        expect(payload.title.contains('產量'), isFalse);
        expect(payload.body.contains('帳本'), isFalse);
      }
    });

    test('機密清單為空 → 原文原樣送出', () async {
      final transport = _RecordingTransport();
      final sender = ApnsPushSender(
        transport: transport,
        confidentialTermsProvider: () => const [],
      );

      await sender.send(title: '產量 1,240', body: '帳本 45,000 元');

      expect(transport.sent.single.title, '產量 1,240');
      expect(transport.sent.single.body, '帳本 45,000 元');
    });
  });

  group('紅隊#5 正式實作契約（防假陽性）', () {
    test('正式實作存在於 lib/services/mobile/push/ 正式路徑', () {
      expect(
        File('lib/services/mobile/push/apns_output_filter.dart').existsSync(),
        isTrue,
        reason: '濾網必須是正式實作檔，非佔位草稿',
      );
    });

    test('公開 API 簽名正確：String pushNotificationText(String, List<String>)', () {
      const String Function(String, List<String>) api = pushNotificationText;
      expect(api, isNotNull);
    });

    test('降級文案常數與 SPEC 字面一致', () {
      expect(kApnsFallbackText, _specFallback);
    });

    test('繁簡對照表完整性：長度為偶數、無自我映射字元對', () {
      expect(kApnsSimplifiedPairs.length.isEven, isTrue,
          reason: '成對字串必須兩字一組「繁→簡」');
      final selfMapping = <String>[];
      for (var i = 0; i + 1 < kApnsSimplifiedPairs.length; i += 2) {
        final trad = kApnsSimplifiedPairs[i];
        final simp = kApnsSimplifiedPairs[i + 1];
        if (trad == simp) selfMapping.add(trad);
      }
      expect(selfMapping, isEmpty,
          reason: '自我映射是死重量（繁簡同形不入表），出現即代表對照表有誤');
    });

    test('繁簡對照表完整性：每個繁體字只出現一次（無重複 key）', () {
      final trads = <String>{};
      final dup = <String>{};
      for (var i = 0; i + 1 < kApnsSimplifiedPairs.length; i += 2) {
        final trad = kApnsSimplifiedPairs[i];
        if (!trads.add(trad)) dup.add(trad);
      }
      expect(dup, isEmpty,
          reason: '同一繁體字不得對應兩個簡體字——重複即對照表建構錯誤');
    });
  });
}
