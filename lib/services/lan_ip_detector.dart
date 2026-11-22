// lan_ip_detector.dart
// 偵測桌面端在區域網路中的實際 IP 位址，讓手機可以連入。
// Sprint 15a by 教練 Agent (CEO)

import 'dart:io';

/// 偵測本機在區域網路中的 IPv4 位址。
///
/// 遍歷所有網路介面，找到第一個非 loopback 的 IPv4 位址。
/// 回傳 null 如果找不到（例如沒有連上任何網路）。
class LanIpDetector {
  const LanIpDetector();

  /// 回傳第一個可用的 LAN IPv4 位址。
  Future<String?> detectLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          // 過濾 link-local (169.254.x.x)
          if (!addr.isLinkLocal && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (_) {
      // ignore — 環境不支援
    }
    return null;
  }

  /// 回傳所有可用的 LAN IPv4 位址（多網卡環境）。
  ///
  /// [2026-11-13 Blue 令：不依賴外部平台] 區網 IP 排最前（QR 主 host——
  /// 同網直連是第 1 層，零外部依賴）。Tailscale CGNAT 段（100.64/10）
  /// 降為**最後候選**：使用者自己裝了才存在，純屬個人加值，產品不依賴、
  /// 不推薦、不改版就壞（一般使用者的 QR 根本不會出現此段）。
  /// 出門主路＝第 3 層自架中繼（§6.3，昨夜完工）。
  /// [2026-11-19 5G 直連排序] 出手排序 lan → v6 → tailscale（手機沒跑
  /// Tailscale 時 100.64/10 是 8s 必死黑洞，不得擋 v6 直連的路）。
  Future<List<String>> detectAllLanIps() async {
    final tailscale = <String>[];
    final lan = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLinkLocal || addr.type != InternetAddressType.IPv4) {
            continue;
          }
          if (_isTailscaleCidr(addr.address)) {
            tailscale.add(addr.address);
          } else {
            lan.add(addr.address);
          }
        }
      }
    } catch (_) {
      // ignore
    }

    // [11-16 IPv6 直連] 電信 CGNAT 破局——v6 無 NAT 直達公網。
    // [小葵 2026-11-18 Blue 報案「反覆跳連線成功/失敗」] 原版宣稱「secured
    // 優先、temporary 殿後」實際沒做任何排序——temporary（隱私輪換位址，
    // 約數小時~一天作廢）被選進 QR 的話，手機剛配對通、位址一輪換就斷線
    // 且永遠連不回。修：macOS 用 ifconfig 標籤分揀（secured=穩定、
    // temporary=會輪換），temporary 一律排除；非 macOS 環境 ifconfig
    // 不可用時 fallback 全收（行為同舊版，不更糟）。
    final v6 = <String>[];
    final temporarySet = <String>{};
    try {
      final ifconfigOut = await Process.run('ifconfig', <String>[]);
      if (ifconfigOut.exitCode == 0) {
        final out = ifconfigOut.stdout as String;
        for (final line in out.split('\n')) {
          final t = line.trim();
          if (t.contains('inet6 ') && t.contains('temporary')) {
            final m = RegExp(r'inet6\s+([0-9a-fA-F:]+)').firstMatch(t);
            if (m != null) temporarySet.add(m.group(1)!.split('%').first);
          }
        }
      }
    } catch (_) {
      // 非 macOS 或 ifconfig 不可用——靠 fallback 行為
    }
    try {
      final v6Ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv6,
        includeLoopback: false,
      );
      for (final iface in v6Ifaces) {
        for (final addr in iface.addresses) {
          final raw = addr.address;
          if (raw.contains('%') || raw.startsWith('fe80')) continue; // link-local 跳過
          if (!raw.contains(':')) continue; // 確保是 v6
          // 全球位址（2000::/3 開頭=2or3 開頭十六進位）
          final firstNibble = int.tryParse(raw[0], radix: 16) ?? 0;
          if (firstNibble < 2 || firstNibble > 3) continue;
          // temporary（會輪換的隱私位址）永不進 QR——門牌會過期
          if (temporarySet.contains(raw)) continue;
          v6.add(raw);
        }
      }
    } catch (_) {
      // ignore
    }

    // [2026-11-19 5G 直連排序] 排序改為 lan → v6 → tailscale：
    // 手機端多半沒跑 Tailscale——100.64/10 段對手機是 8s 必死黑洞（連 route
    // 都出不去），排 v6 前面只會把 IPv6 直連的連線時機堵死。區網最快、
    // v6 直連第二、Tailscale 殿後（自己裝了才存在，純屬個人加值）。
    return [...lan, ...v6, ...tailscale];
  }

  /// [2026-11-19 一機一筆] 本機穩定身分證——macOS 用 IOPlatformUUID
  /// （重灌 App / 換 IP / 位址輪換都不變），hash 成短碼放進 QR `did` 參數。
  /// 取不到（非 macOS / ioreg 失敗）回空字串——手機端退回 host_port 舊邏輯。
  static Future<String> detectDesktopId() async {
    try {
      final r = await Process.run(
        'ioreg',
        const ['-rd1', '-c', 'IOPlatformExpertDevice'],
      );
      if (r.exitCode != 0) return '';
      final out = r.stdout as String;
      final m = RegExp(
        r'"IOPlatformUUID"\s*=\s*"([^"]+)"',
      ).firstMatch(out);
      if (m == null) return '';
      final uuid = m.group(1)!.trim();
      // FNV-1a 32bit → 8 碼 hex：短、穩、不洩完整 UUID
      var hash = 0x811c9dc5;
      for (final c in uuid.codeUnits) {
        hash ^= c;
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }
      return hash.toRadixString(16).padLeft(8, '0');
    } catch (_) {
      return '';
    }
  }

  /// Tailscale CGNAT 段：100.64.0.0 – 100.127.255.255（100.64/10）。
  static bool _isTailscaleCidr(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final first = int.tryParse(parts[0]) ?? -1;
    final second = int.tryParse(parts[1]) ?? -1;
    return first == 100 && second >= 64 && second <= 127;
  }
}
