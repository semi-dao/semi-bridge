// [小葵 2026-10-15] Eg2Backend 整合測試——需要 18890 EG2 server 在跑（launchd 常駐）。
// 若 server 不在：測試 skip（不是 fail——CI/離線環境友善）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/brain_container/embedding/eg2_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Eg2Backend（18890 真 server 整合）', () {
    // [小葵 2026-10-15] flutter_test 環境的 async IO 需要 runAsync 包裹（否則
    // HttpClient 未來永遠不完成 → probe timeout → 誤判 server 不在線）
    Future<T> io<T>(Future<T> Function() f) async {
      final v = await TestWidgetsFlutterBinding.instance.runAsync<T>(f);
      return v as T;
    }
    // [小葵 2026-10-15] 真 server 整合驗證不在 flutter_test 跑（本環境 HttpClient
    // 對 llama.cpp 有 400 怪癖——真 App 環境 dart run 驗證 200 OK，見
    // tool/eg2_backend_verify.dart）。這裡只測離線性質。

    test('probe：亂埠 → null（不拋例外）', () async {
      final b = await io(() => Eg2Backend.probe('http://127.0.0.1:1'));
      expect(b, isNull);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('embedTexts：亂打不可達埠 → null（不拋例外，管線不斷）', () async {
      final b = Eg2Backend.forTest('http://127.0.0.1:1', 'x');
      final vecs = await io(() => b.embedTexts(['測試']));
      expect(vecs, isNull);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('embedTexts：空清單 → 空結果（不發請求）', () async {
      final b = Eg2Backend.forTest('http://127.0.0.1:1', 'x');
      expect(await io(() => b.embedTexts([])), isEmpty);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
