// bridge_relay.dart —— CLI 薄殼：核心邏輯在 lib/services/relay/relay_server_core.dart
import 'dart:io';
import 'package:bridge_app/services/relay/relay_server_core.dart';

void main(List<String> args) async {
  var port = 8791;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--port') port = int.tryParse(args[i + 1]) ?? port;
  }
  final core = await RelayServerCore.start(
    port: port,
    onLog: (line) => stderr.writeln('[relay] \$line'),
  );
  stderr.writeln('[relay] 橋樑第 3 層中繼就緒 :\$port（盲轉——不解讀、不落地、不終結 TLS）');
  ProcessSignal.sigterm.watch().listen((_) async {
    await core.close();
    exit(0);
  });
}
