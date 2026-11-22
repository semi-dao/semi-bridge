// paired_desktop_store.dart
// 持久化已配對的桌面端資訊。
// Sprint 15a by 教練 Agent (CEO)

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 一台已配對的 Bridge Desktop。
class PairedDesktop {
  final String id; // 用 host+port hash
  final String host;
  final int port;
  final String pairingCode;
  final String desktopName;
  final DateTime pairedAt;
  // [11-16 出門直連] QR alts 候選位址（含 IPv6）——重連時 host 不通逐個試。
  final List<String> altHosts;

  /// [2026-11-19 一機一筆] 桌面穩定身分證（QR did 參數）——同 did 覆蓋舊紀錄。
  /// 舊資料（無 did）回空字串，走 host_port 舊邏輯。
  final String desktopId;

  const PairedDesktop({
    required this.id,
    required this.host,
    required this.port,
    required this.pairingCode,
    required this.desktopName,
    required this.pairedAt,
    this.altHosts = const [],
    this.desktopId = '',
  });

  String get endpoint =>
      'ws://${host.contains(':') ? '[$host]' : host}:$port/bridge';

  /// [11-16] 全部候選（host 優先，alts 依序）。
  List<String> get allHosts => [host, ...altHosts];

  factory PairedDesktop.fromJson(Map<String, dynamic> json) {
    return PairedDesktop(
      id: json['id'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 8790,
      pairingCode: json['pairingCode'] as String? ?? '',
      desktopName: json['desktopName'] as String? ?? 'Bridge Desktop',
      pairedAt: json['pairedAt'] != null
          ? DateTime.parse(json['pairedAt'] as String)
          : DateTime.now(),
      altHosts: (json['altHosts'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .where((e) => e.isNotEmpty)
          .toList(),
      desktopId: json['desktopId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'host': host,
        'port': port,
        'pairingCode': pairingCode,
        'desktopName': desktopName,
        'pairedAt': pairedAt.toIso8601String(),
        'altHosts': altHosts,
        'desktopId': desktopId,
      };

  static String makeId(String host, int port) =>
      '${host}_$port';
}

/// 管理 SharedPreferences 裡的已配對桌面清單。
class PairedDesktopStore {
  static const _key = 'bridge_paired_desktops';

  static Future<List<PairedDesktop>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PairedDesktop.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(PairedDesktop desktop) async {
    final all = await getAll();
    // [2026-11-19 一機一筆] 同 desktopId（QR did）覆蓋——換門牌不長第二筆；
    // 無 did（舊版手機/舊資料）退回 host_port 舊邏輯。
    if (desktop.desktopId.isNotEmpty) {
      all.removeWhere((d) =>
          d.desktopId == desktop.desktopId || d.id == desktop.id);
    } else {
      all.removeWhere((d) => d.id == desktop.id);
    }
    all.add(desktop);
    await _writeAll(all);
  }

  static Future<void> remove(String id) async {
    final all = await getAll();
    all.removeWhere((d) => d.id == id);
    await _writeAll(all);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Future<void> _writeAll(List<PairedDesktop> desktops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(desktops.map((d) => d.toJson()).toList()),
    );
  }
}
