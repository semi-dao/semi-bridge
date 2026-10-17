// test_mcp_http.dart — 最小化 HttpServer 測試
// 確認 dart:io HttpServer 在 Release build 的 Flutter 環境下能否正常回應
import 'dart:async';
import 'dart:io';

void main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8421);
  print('Test server on http://127.0.0.1:8421');
  
  server.listen((request) {
    print('Got request: ${request.method} ${request.uri}');
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"status":"ok"}');
    request.response.close();
  });
  
  // Keep alive
  await Future.delayed(Duration(minutes: 5));
}
