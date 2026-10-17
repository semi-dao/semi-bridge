// m2_chat_vs_task_test.dart
// [T4 + Blue 2026-10-16 對話/任務分流鐵則] 鎖死人格 v4 條款進 prompt——
// 盲測/實測已經出現「我好累」→ 撈工具開 workflow 變假報告的病
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('M2 e4b 版含 v4 對話/任務分流鐵則', () async {
    final txt = await rootBundle.loadString('assets/persona/persona_e4b.txt');
    expect(txt, contains('對話/任務分流鐵則'),
        reason: 'v4 鐵則必須注入 persona');
    expect(txt, contains('不主動開工具'),
        reason: '對話模式不開工具');
    expect(txt, contains('對話預設永遠是對話'),
        reason: '模糊時預設對話');
  });

  test('M2 cloud 版同樣含 v4 鐵則（雲端也怕同病）', () async {
    final txt = await rootBundle.loadString('assets/persona/persona_cloud.txt');
    expect(txt, contains('對話/任務分流鐵則'));
    expect(txt, contains('不主動開工具'));
  });
}
