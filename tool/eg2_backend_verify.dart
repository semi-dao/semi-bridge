import 'dart:io';
import 'dart:math';
// 相對路徑直接 import 原始檔（不經 package，避免 pubspec 解析）
import 'package:bridge_app/services/brain_container/embedding/eg2_backend.dart';

Future<void> main() async {
  final b = await Eg2Backend.probe('http://127.0.0.1:18890');
  print('probe: ${b == null ? "null" : b.modelKey.split("/").last}');
  if (b != null) {
    final vecs = await b.embedTexts(['鹿角蕨需要散射光', 'staghorn fern light', '今天晚餐吃火鍋']);
    print('embedTexts: ${vecs?.length} 條, 各 ${vecs?[0].length} 維');
    if (vecs != null && vecs.length == 3) {
      double cos(List<double> x, List<double> y) {
        double d = 0, na = 0, nb = 0;
        for (var i = 0; i < x.length; i++) { d += x[i]*y[i]; na += x[i]*x[i]; nb += y[i]*y[i]; }
        return d / (sqrt(na) * sqrt(nb));
      }
      print('中英同義: ${cos(vecs[0], vecs[1]).toStringAsFixed(3)}');
      print('無關對照: ${cos(vecs[0], vecs[2]).toStringAsFixed(3)}');
    }
  }
  exit(0);
}
