// 出門連線三層樓梯（純函數）
// [蜂群演習二 Wave 2·工蜂E 2026-11-09] 依據 BRIDGE_MOBILE_SPEC.md v0.5 §6.2
// （2026-10-30 Blue 拍板 v0.1 版）：
//
//   第 1 層｜同網直連（預設，永遠優先）
//     → 人在家/農場 Wi-Fi 內，零設定零後門
//   第 2 層｜自開後門（出門主力）
//     → 主機開加密埠 + DDNS；App 偵測網路環境，
//        能開就一鍵引導開，開不了明講（寧紅字不假成功）
//   第 3 層｜自架中繼（救生艇，選配）
//     → 開源包附 Docker 一鍵自架；SemiDAO 不經營
//
// 設計鐵則：
//   - 第 1 層永遠優先（SPEC 明文「預設，永遠優先」）：同網直連可用時，
//     第 3 層中繼即使可用也不得翻盤（直連更快、更省、不經第三方）。
//   - 誠實失敗：全斷就是 offline，明講開不了 —— 不假成功、不假裝正在開。
//   - 純函數：無 UI、無網路、無 DB —— 偵測結果由呼叫端餵入，可直接 unit test。

/// 連線層級（SPEC §6.2 三層樓梯）。
///
/// 宣告順序即優先序：index 越小越優先。
enum LadderTier {
  /// 第 1 層：同網直連（零設定零後門，永遠優先）。
  direct(
    action: LadderAction.connectDirect,
    message: '同網直連可用（零設定零後門），直接連線。',
  ),

  /// 第 3 層：自架中繼（出門救生艇，選配）。
  relay(
    action: LadderAction.useRelay,
    message: '同網不可達，改走自架中繼（第 3 層救生艇）。',
  ),

  /// 全斷：沒有任何一層可用 —— 明講開不了（寧紅字不假成功）。
  offline(
    action: LadderAction.reportUnavailable,
    message: '連線失敗：同網直連不可達、自架中繼也不可用，'
        '請確認主機已開啟加密埠與 DDNS，或改用同網路環境。',
  );

  const LadderTier({required this.action, required this.message});

  /// 此層要採取的行動。
  final LadderAction action;

  /// 可直接顯示給使用者的說明（繁中，誠實字眼）。
  final String message;

  /// 此層是否代表「有路可走」（offline 為 false）。
  bool get isConnected => this != LadderTier.offline;
}

/// 連線層級對應的可行動作。
enum LadderAction {
  /// 直接連線（第 1 層）。
  connectDirect,

  /// 走中繼（第 3 層）。
  useRelay,

  /// 明講開不了 —— 不得假裝正在開、不得空轉。
  reportUnavailable,
}

/// 三層樓梯評估器。
class ConnectionLadder {
  ConnectionLadder._();

  /// 依偵測結果評估該走哪一層。
  ///
  /// [sameLanGatewayReachable] 同網段 gateway 是否可達（第 1 層）。
  /// [relayReachable] 自架中繼是否可達（第 3 層）。
  ///
  /// 優先序：direct > relay > offline。
  /// 第 1 層永遠優先 —— 同網可達時不論中繼是否可用，一律走 direct。
  static LadderTier evaluate({
    required bool sameLanGatewayReachable,
    required bool relayReachable,
  }) {
    if (sameLanGatewayReachable) return LadderTier.direct;
    if (relayReachable) return LadderTier.relay;
    return LadderTier.offline;
  }
}
