// 配對 QR payload 解析器（唯一真相源：payload 裡的 port）
// [蜂群演習二 Wave 2·工蜂E 2026-11-09] 依據 BRIDGE_MOBILE_SPEC.md v0.5 §6.1
// （2026-10-31 紅隊 v0.4 修訂）：
//
//   「8787」為歷史慣稱；實際埠以配對 QR payload 的 `port` 參數為**唯一真相源**
//   （主機端 `DesktopBridgeLocalGatewayConfig.port`，目前預設 8790），**禁 hardcode**。
//
// 設計鐵則（寧紅字不假成功）：
//   - 任何無法確定的情況（缺參數、埠非法、scheme 不對、參數重複）→ **明確拋錯**，
//     絕不回填任何預設埠（回填 8790 就是 SPEC 禁止的 hardcode 猜預設）。
//   - port=0 是合法值（交給 OS 隨機分配，測試與開發常用），不是錯誤。
//   - 純函數：無 UI、無網路、無 DB —— 可直接 unit test。
//
// 純函數模組：手機端配對流程的第一道閘門（拿到 QR 先解析，再談連線）。

/// QR payload 格式不合法時丟出的錯誤。
///
/// 攜帶 [field] 讓 UI 可以針對出錯欄位給紅字說明（host/port/code/scheme）。
class QrPayloadException implements Exception {
  /// 出錯欄位名（'host' / 'port' / 'code' / 'scheme' / 'payload'）。
  final String field;

  /// 人可讀的錯誤訊息（繁中，可直接顯示）。
  final String message;

  const QrPayloadException(this.field, this.message);

  @override
  String toString() => 'QrPayloadException($field): $message';
}

/// 解析後的配對資訊。
class QrPairingPayload {
  /// 主機位址（IP 或主機名；原樣保留，不做格式假設）。
  final String host;

  /// 主機埠（唯一真相源來自 QR payload，不是程式內常數）。
  final int port;

  /// 配對碼。
  final String code;

  /// [§6.3] 候選位址清單（alts 參數）——host 連不上時逐個試。
  final List<String> altHosts;

  /// [2026-11-19 一機一筆] 桌面穩定身分證（did 參數，可缺）——
  /// 有它就同機覆蓋舊配對紀錄，換 IP/門牌不長第二筆。
  final String desktopId;

  const QrPairingPayload({
    required this.host,
    required this.port,
    required this.code,
    this.altHosts = const [],
    this.desktopId = '',
  });

  @override
  String toString() =>
      'QrPairingPayload(host: $host, port: $port, code: $code, altHosts: $altHosts, desktopId: $desktopId)';
}

/// 配對 QR payload 解析器。
class QrPayloadParser {
  QrPayloadParser._();

  /// 配對 protocol 的 scheme。
  static const String scheme = 'bridge';

  /// 配對 protocol 的 host 段落（`bridge://pair?...` 中的 `pair`）。
  static const String action = 'pair';

  /// 合法埠範圍上限（TCP/UDP 埠為 16 bit）。
  static const int maxPort = 65535;

  /// 解析 `bridge://pair?host=…&port=…&code=…`。
  ///
  /// 成功回傳 [QrPairingPayload]；任何不合規輸入丟 [QrPayloadException]。
  ///
  /// 規格：
  /// - scheme 必須是 `bridge`、host 段落必須是 `pair`。
  /// - `host`、`port`、`code` 三者皆必填，缺一即錯。
  /// - `port` 必須是整數且落在 `0..65535`；**port=0 合法**（OS 隨機分配）。
  /// - 同一參數重複出現 → 歧義，視為錯誤（寧紅字不猜）。
  static QrPairingPayload parseQrPayload(String uri) {
    if (uri.trim().isEmpty) {
      throw const QrPayloadException('payload', 'QR payload 是空的');
    }

    final Uri parsed;
    try {
      parsed = Uri.parse(uri.trim());
    } on FormatException {
      throw const QrPayloadException(
        'payload',
        'QR payload 不是合法的 URI 格式',
      );
    }

    if (parsed.scheme != scheme) {
      throw QrPayloadException(
        'scheme',
        'QR payload 的 scheme 必須是 "$scheme"，收到 "${parsed.scheme}"',
      );
    }
    if (parsed.host != action) {
      throw QrPayloadException(
        'scheme',
        'QR payload 必須是 $scheme://$action?...，收到 "$action" 以外的段落',
      );
    }

    final params = parsed.queryParametersAll;

    final hostRaw = _single(params, 'host');
    // [11-16 v6] host 可能是 [v6] 包裹——還原成裸 v6
    final host = (hostRaw != null && hostRaw.startsWith('[') && hostRaw.endsWith(']'))
        ? hostRaw.substring(1, hostRaw.length - 1)
        : hostRaw;
    if (host == null || host.isEmpty) {
      throw const QrPayloadException('host', 'QR payload 缺少 host');
    }

    final code = _single(params, 'code');
    if (code == null || code.isEmpty) {
      throw const QrPayloadException('code', 'QR payload 缺少配對碼 code');
    }

    // ⚠️ 埠真相源：缺 port 一律報錯，絕不猜預設值（SPEC §6.1 禁 hardcode）。
    final rawPort = _single(params, 'port');
    if (rawPort == null || rawPort.isEmpty) {
      throw const QrPayloadException(
        'port',
        'QR payload 缺少 port（埠真相源只能來自 QR payload，不猜預設值）',
      );
    }
    final port = int.tryParse(rawPort);
    if (port == null) {
      throw QrPayloadException('port', 'QR payload 的 port 不是整數："$rawPort"');
    }
    if (port < 0 || port > maxPort) {
      throw QrPayloadException(
        'port',
        'QR payload 的 port 超出範圍（0..$maxPort）：$port',
      );
    }

    // [§6.3] alts=逗號分隔候選位址（可缺）——host 連不上時逐個試
    final altsRaw = _single(params, 'alts');
    // [11-16 v6] alts 的 v6 host 是 [ ] 包裹格式——還原成裸 v6（防 [[..]] 雙括號）
    String unwrapV6(String h) {
      final t = h.trim();
      if (t.startsWith('[') && t.endsWith(']')) return t.substring(1, t.length - 1);
      return t;
    }
    final altHosts = (altsRaw == null || altsRaw.isEmpty)
        ? const <String>[]
        : altsRaw
            .split(',')
            .map(unwrapV6)
            .where((e) => e.isNotEmpty)
            .toList();

    return QrPairingPayload(
      host: host,
      port: port,
      code: code,
      altHosts: altHosts,
      desktopId: _single(params, 'did') ?? '',
    );
  }

  /// 取單值參數；重複出現視為歧義 → 拋錯（不挑一個猜）。
  static String? _single(Map<String, List<String>> params, String key) {
    final values = params[key];
    if (values == null) return null;
    if (values.length > 1) {
      throw QrPayloadException(
        key,
        'QR payload 的 $key 出現 ${values.length} 次（歧義輸入，不猜）',
      );
    }
    return values.first;
  }
}
