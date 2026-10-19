// [小葵 2026-09-24 開源整備] 開發機路徑改寫——把 hardcode 的絕對路徑
// 換成環境變數 + \$HOME 展開。本地開發者設 BRIDGE_APP_HOME 即可對位。
import 'dart:io';

/// 展開開頭的 ~ 與 \$HOME，並解析 BRIDGE_APP_HOME 覆寫。
String resolveDevPath(String path) {
  var p = path;
  final home = Platform.environment['HOME'] ?? '';
  final override = Platform.environment['BRIDGE_APP_HOME'];
  if (p.startsWith('~/')) {
    p = '\$home/\${p.substring(2)}';
  } else if (p.contains('/Developer/bridge_app')) {
    // 專案根：預設 \$HOME/Developer/bridge_app，可被 BRIDGE_APP_HOME 覆寫
    final projectRoot = override ?? '\$home/Developer/bridge_app';
    p = p.replaceAll('/Developer/bridge_app', '\$projectRoot');
  }
  if (p.contains('~')) p = p.replaceAll('~', home);
  return p;
}
