// 手機通道 taskType 白名單（S2 白名單轉發層核心）
// [S2 2026-11-09] 依據 BRIDGE_MOBILE_SPEC.md L105（紅隊 #13/#14 修訂）：
//
//   「轉發層 = gateway 進程內 in-process 呼叫（非另開 HTTP）；
//    手機僅開放白名單子集工具（清單另行拍板），
//    其餘回『此指令僅限 Agent 本機使用』」
//
// 設計鐵則：
// - **default-deny**：白名單預設空，沒拍板的工具手機一律拿不到。
// - 拒絕訊息固定文案——不洩漏白名單內容、不區分「不存在」與「不開放」
//   （兩種原因同一句話，防探測）。
// - 前綴條目以完整 segment 為界（`browser.` 不放行 `browserX.`）。
// - 大小寫敏感（協議層精確比對）。
// - 純函數：無 UI、無網路、無 DB。

/// 白名單判定結果。
class MobileTaskWhitelistResult {
  /// 是否放行。
  final bool allowed;

  /// 拒絕時的固定文案（放行時為 null）。
  final String? denyMessage;

  const MobileTaskWhitelistResult({required this.allowed, this.denyMessage});
}

/// 手機通道 taskType 白名單。
///
/// [allowed] 精確條目（完全相同才放行，不是前綴）。
/// [allowedPrefixes] 前綴條目（以完整 segment 為界：`browser.` → `browser.*`）。
class MobileTaskWhitelist {
  /// 拒絕時的固定文案（SPEC 拍板原文）。
  static const String kDenyMessage = '此指令僅限 Agent 本機使用';

  /// 白名單內容（不可變）。
  final Set<String> _allowed;

  /// 前綴白名單內容（不可變）。
  final Set<String> _allowedPrefixes;

  MobileTaskWhitelist({
    List<String> allowed = const [],
    List<String> allowedPrefixes = const [],
  })  : _allowed = Set.unmodifiable(allowed),
        _allowedPrefixes = Set.unmodifiable(allowedPrefixes);

  /// 判定 [taskType] 是否對手機開放。
  MobileTaskWhitelistResult check(String taskType) {
    if (taskType.isNotEmpty) {
      if (_allowed.contains(taskType)) {
        return const MobileTaskWhitelistResult(allowed: true);
      }
      for (final prefix in _allowedPrefixes) {
        // 前綴比對：`browser.` 放行 `browser.navigate`。
        // `browserX.` 不以 `browser.` 開頭（第 8 字元是 X 不是 .），
        // 天然擋掉僞造命名空間——無需額外規則。
        if (taskType.startsWith(prefix)) {
          return const MobileTaskWhitelistResult(allowed: true);
        }
      }
    }
    return const MobileTaskWhitelistResult(
      allowed: false,
      denyMessage: kDenyMessage,
    );
  }

  /// 從全量 taskType 清單過濾出手機能看到的子集（capabilityList 用）。
  ///
  /// 手機不該看到未開放的工具名——那本身就是資訊洩漏。
  List<String> capabilityList({required Iterable<String> allTaskTypes}) {
    return allTaskTypes.where((t) => check(t).allowed).toList()..sort();
  }

  /// [Blue 拍板 2026-11-09] 手機通道預設白名單——唯讀＋導航，最小開放。
  ///
  /// - `browser.navigate`：導航（會過 DataPathGate 分級）
  /// - `browser.screenshot`：截圖唯讀
  /// - `runtime.ping`：連線健康檢查
  ///
  /// 檔案系統／shell／表單填寫（fillForm）／步驟序列（runSteps）一律不開放
  /// ——runSteps 內含任意點擊鏈，風險等同 shell，等 S4 真機狗糧後再議。
  static MobileTaskWhitelist get defaultForMobile => MobileTaskWhitelist(
        allowed: const [
          'browser.navigate',
          'browser.screenshot',
          'runtime.ping',
          // [S4 2026-11-10] 聊天直送——手機訊息注入桌面對話（唯文字，
          // 不帶工具執行；走 sendDirectMessage 同 MCP 注入路）
          'chat.send',
        ],
      );
}
