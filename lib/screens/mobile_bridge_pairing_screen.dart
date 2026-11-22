// mobile_bridge_pairing_screen.dart
// 手機端 Bridge Desktop 配對畫面。
// 掃 QR 或手動輸入 → 連線 → 顯示狀態
// Sprint 15a by 教練 Agent (CEO)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/mobile_bridge_client.dart';
import '../services/mobile/pairing/qr_payload_parser.dart';
import '../services/mobile/mobile_token_access.dart';
import '../services/paired_desktop_store.dart';
import '../main.dart' show kMobileBuildStamp;
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

class MobileBridgePairingScreen extends StatefulWidget {
  const MobileBridgePairingScreen({super.key});

  @override
  State<MobileBridgePairingScreen> createState() =>
      _MobileBridgePairingScreenState();
}

class _MobileBridgePairingScreenState extends State<MobileBridgePairingScreen> {
  // Singleton — 連線跟 App 生命週期綁定，離開畫面不斷線
  final MobileBridgeClient _client = MobileBridgeClient.instance;
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '8790',
  );
  final TextEditingController _codeController = TextEditingController();

  bool _showScanner = false;
  bool _connecting = false;
  List<PairedDesktop> _paired = [];

  /// [2026-11-19 一機一筆] 最近一次 QR 帶的桌面身分證——存檔時用。
  String _lastQrDesktopId = '';

  @override
  void initState() {
    super.initState();
    _client.addListener(_onConnectionChanged);
    _loadPairedDesktops();
  }

  @override
  void dispose() {
    // 只移除 listener，不 dispose client — 連線繼續活著
    _client.removeListener(_onConnectionChanged);
    _hostController.dispose();
    _portController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onConnectionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPairedDesktops() async {
    final desktops = await PairedDesktopStore.getAll();
    if (mounted) setState(() => _paired = desktops);
  }

  Future<void> _connect({
    required String host,
    required int port,
    required String code,
  }) async {
    setState(() => _connecting = true);
    final ok = await _client.connect(host: host, port: port, pairingCode: code);
    if (ok && mounted) {
      // 持久化
      final desktop = PairedDesktop(
        id: PairedDesktop.makeId(host, port),
        host: host,
        port: port,
        pairingCode: code,
        desktopName: 'Bridge Desktop',
        pairedAt: DateTime.now(),
        desktopId: _lastQrDesktopId,
      );
      await PairedDesktopStore.add(desktop);
      await _loadPairedDesktops();

      // [S1] 裝置 token 落地——配對成功主機會簽發長期 token，存起來
      // 之後 App 重啟走 reconnectWithToken（不重掃 QR）
      // [刀① 2026-11-19] 存 did key（一機一筆）——不再按 host:port 各存一份
      final token = _client.deviceToken;
      if (token != null) {
        await saveTokenFor(desktop, token);
      }
    }
    if (mounted) setState(() => _connecting = false);
  }

  void _onQrDetected(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final raw = barcodes.first.rawValue;
    if (raw == null) return;

    // [Wave 2] 改用正式 parser（埠真相源=QR payload；寧紅字不猜預設）
    late final QrPairingPayload parsed;
    try {
      parsed = QrPayloadParser.parseQrPayload(raw);
    } on QrPayloadException {
      // 不是 bridge:// QR（或缺參數）——忽略非本 App 的 QR，不中斷掃描
      return;
    }

    // 停止掃描
    setState(() => _showScanner = false);

    // [2026-11-19 一機一筆] 記下 QR 的桌面身分證——存檔時同 did 覆蓋
    _lastQrDesktopId = parsed.desktopId;

    // 填入手動輸入欄位（讓使用者看到連了什麼）
    _hostController.text = parsed.host;
    _portController.text = parsed.port.toString();
    _codeController.text = parsed.code;

    // 直接連線（[§6.3] 失敗時逐個試 alts 候選位址——區網/Tailscale 誰通走誰）
    _connectWithFallback(
      hosts: [parsed.host, ...parsed.altHosts],
      port: parsed.port,
      code: parsed.code,
    );
  }

  /// [§6.3] 逐候選連線：host 連不上 → alts 依序試（配對碼一次有效可重試）。
  Future<void> _connectWithFallback({
    required List<String> hosts,
    required int port,
    required String code,
  }) async {
    for (var i = 0; i < hosts.length; i++) {
      final ok = await _client.connect(host: hosts[i], port: port, pairingCode: code);
      if (ok) {
        // [2026-11-13 真兇修正] fallback 成功也要持久化 paired+token——
        // 原本只 _connect()（primary 路）會存；QR alts fallback 路成功時
        // 什麼都沒存 → 手機沒有配對記錄 → bootstrap 讀空 → 永遠離線
        //（與截圖「disconnected 無錯誤」吻合）
        // [11-16 出門直連] 存全部候選——出門重連時 host 不通逐個試 alts（含 v6）
        final desktop = PairedDesktop(
          id: PairedDesktop.makeId(hosts[i], port),
          host: hosts[i],
          port: port,
          pairingCode: code,
          desktopName: 'Bridge Desktop',
          pairedAt: DateTime.now(),
          altHosts: hosts.where((h) => h != hosts[i]).toList(),
          desktopId: _lastQrDesktopId,
        );
        await PairedDesktopStore.add(desktop);
        final token = _client.deviceToken;
        if (token != null) {
          // [刀① 2026-11-19] 存 did key（一機一筆）——成功端點是誰不重要，
          // 同一台桌機一份 token，消滅「新 token 只在 LAN key、v6 key 躺殭屍」病根
          await saveTokenFor(desktop, token);
        }
        if (mounted) setState(() {});
        return;
      }
      debugPrint('[Pairing] ${hosts[i]} 連不上'
          '${i < hosts.length - 1 ? ' → 試下一個候選' : '（候選已用盡）'}');
    }
    // 全部落空——_connect 內部已設錯誤訊息（寧紅字不假成功）
  }

  void _manualConnect() {
    final host = _hostController.text.trim();
    // [SPEC §6.1 修正] 移除 `?? 8790` hardcode——埠必須明確填寫
    // （QR 掃碼路永遠帶正確 port；手動輸入缺 port 就是紅字，不猜）
    final portText = _portController.text.trim();
    final code = _codeController.text.trim();

    if (host.isEmpty || code.isEmpty || portText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請填入 IP 位址、連接埠和配對碼')));
      return;
    }
    final port = int.tryParse(portText);
    if (port == null || port < 0 || port > 65535) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('連接埠格式不正確（0-65535）')));
      return;
    }
    _connect(host: host, port: port, code: code);
  }

  void _disconnect() {
    _client.disconnect();
  }

  void _forgetDesktop(PairedDesktop desktop) async {
    await PairedDesktopStore.remove(desktop.id);
    await _loadPairedDesktops();
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final state = _client.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('桌面配對'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // [S4 2026-11-09] 返回保險——canPop 才 pop，否則回手機首頁
          // （go() 進來的堆疊沒有上一頁，直接 pop 會黑屏）
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/mobile-home');
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 連線狀態卡
            _buildStatusCard(state),
            const SizedBox(height: 16),

            // QR 掃描區或手動輸入
            if (_showScanner) ...[
              _buildScanner(),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _showScanner = false),
                child: const Text('取消掃描'),
              ),
              const SizedBox(height: 16),
            ] else if (!_client.isConnected) ...[
              // 掃描按鈕
              ElevatedButton.icon(
                onPressed: () => setState(() => _showScanner = true),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('掃描 QR 碼'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),

              // 分隔線
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '或手動輸入',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textSecondary,),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),

              // 手動輸入
              TextField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: '桌面 IP 位址',
                  hintText: '192.168.1.5',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.computer),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: '配對碼',
                        hintText: 'BRIDGE-XXXXXX',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.key),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _connecting ? null : _manualConnect,
                icon: _connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(_connecting ? '連線中…' : '連線'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],

            // 已配對桌面清單
            if (_paired.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('已配對的桌面', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._paired.map((d) => _buildPairedDesktopTile(d)),
            ],

            // [2026-11-13] build 標記——一眼辨識新舊 App（低調灰字）
            const SizedBox(height: 24),
            Text(
              'build $kMobileBuildStamp',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BridgeConnectionState state) {
    final ds = BridgeDSColors.of(context);
    final (color, icon, text) = switch (state) {
      BridgeConnectionState.disconnected => (
        ds.textTertiary,
        Icons.cloud_off,
        '未連線',
      ),
      BridgeConnectionState.connecting => (ds.accentYellow, Icons.sync, '連線中…'),
      BridgeConnectionState.connected => (
        ds.accentBlue,
        Icons.cloud_done,
        '已連線',
      ),
      BridgeConnectionState.handshaking => (
        ds.accentYellow,
        Icons.handshake,
        '握手中…',
      ),
      BridgeConnectionState.ready => (
        ds.accentGreen,
        Icons.check_circle,
        '已連線，就緒',
      ),
      BridgeConnectionState.error => (ds.accentRed, Icons.error, '連線錯誤'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 48),
            const SizedBox(height: 8),
            Text(
              text,
              style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                color: color,),
            ),
            // [S4 2026-11-10 Blue 令] 配對成功的儀式感回饋——
            // 綠燈＋明確告知「已完成綁定，重開機免重新配對」
            if (state == BridgeConnectionState.ready) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: ds.accentGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ds.accentGreen.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified, color: ds.accentGreen, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '綁定完成 ✓ 手機與電腦已建立信任——'
                        '之後任意一方重開機都會自動重連，不需再配對',
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.accentGreen),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_client.lastError != null &&
                state == BridgeConnectionState.error) ...[
              const SizedBox(height: 4),
              Text(
                _client.lastError!,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.accentRed),
                textAlign: TextAlign.center,
              ),
            ],
            if (_client.isConnected) ...[
              const SizedBox(height: 8),
              Text(
                _client.connectedEndpoint ?? '',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDS.grey600,
                  fontFamily: 'monospace',),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('斷線'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 300,
        child: MobileScanner(onDetect: _onQrDetected),
      ),
    );
  }

  Widget _buildPairedDesktopTile(PairedDesktop desktop) {
    final ds = BridgeDSColors.of(context);
    final isActive = _client.connectedEndpoint == desktop.endpoint;

    return Card(
      child: ListTile(
        leading: Icon(
          isActive ? Icons.desktop_windows : Icons.desktop_access_disabled,
          color: isActive ? ds.accentGreen : ds.textTertiary,
        ),
        title: Text(desktop.desktopName),
        subtitle: Text('${desktop.host}:${desktop.port}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isActive)
              IconButton(
                icon: const Icon(Icons.link),
                onPressed: () => _connect(
                  host: desktop.host,
                  port: desktop.port,
                  code: desktop.pairingCode,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _forgetDesktop(desktop),
            ),
          ],
        ),
      ),
    );
  }
}
