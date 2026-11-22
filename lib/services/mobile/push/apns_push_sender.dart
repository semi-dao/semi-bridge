// APNs 推播發送器（送出前必過輸出濾網）
// [S3 提前·蜂群演習二 Wave 2] 依據 BRIDGE_MOBILE_SPEC.md v0.5 §7「推播基礎設施」
// 拍板 A＋紅隊 #17 修訂條款：
//
// 「通知文字只放開放層內容，APNs 送出前過輸出濾網（比對機密層實體清單，
//  命中即降級為『有新報告，請開 App 查看』）」
//
// ⚠️ 紅隊 #1 的教訓：只測純函數不夠——若送出路徑繞過濾網，測試會全綠但機密仍外洩。
//    因此本檔把「送出前必過濾網」做成**送出路徑唯一的入口**：
//    ApnsPushSender.send() 內部先濾網，之後才交給 transport。
//    任何繞過 filter 的路徑都不存在——要送出只能走 send()。
//
// 傳輸層（ApnsTransport）刻意抽象：真機環境接 APNs HTTP/2 憑證簽章，
// 測試環境接錄製型替身（本檔不碰網路、不碰憑證——純邏輯層可驗）。

import 'apns_output_filter.dart';

/// 一則待送出的 APNs 推播載荷（標題＋內文）。
class ApnsPushPayload {
  /// 通知標題（已過濾網）。
  final String title;

  /// 通知內文（已過濾網）。
  final String body;

  const ApnsPushPayload({required this.title, required this.body});

  @override
  String toString() => 'ApnsPushPayload(title: $title, body: $body)';
}

/// APNs 傳輸層介面（真實實作見 S4 真機階段）。
abstract class ApnsTransport {
  /// 送出推播。
  Future<void> send(ApnsPushPayload payload);
}

/// APNs 推播發送器——**送出前必過輸出濾網的唯一入口**。
class ApnsPushSender {
  /// 傳輸層（真機接 APNs 憑證簽章；測試接錄製型替身）。
  final ApnsTransport transport;

  /// 機密層實體清單提供者（延遲取用——清單隨帳本更新，不必重組 sender）。
  final List<String> Function() confidentialTermsProvider;

  ApnsPushSender({
    required this.transport,
    required this.confidentialTermsProvider,
  });

  /// 送出推播通知。
  ///
  /// 標題與內文各自過濾網；任一命中機密層實體 → 該欄位降級為
  /// [kApnsFallbackText]（固定文案，不洩漏原文與機密詞）。
  ///
  /// 回傳真正送出的載荷（已過濾）——測試與呼叫端都能驗證「送出的東西是乾淨的」。
  Future<ApnsPushPayload> send({
    required String title,
    required String body,
  }) async {
    final terms = confidentialTermsProvider();
    final payload = ApnsPushPayload(
      title: pushNotificationText(title, terms),
      body: pushNotificationText(body, terms),
    );
    await transport.send(payload);
    return payload;
  }
}
