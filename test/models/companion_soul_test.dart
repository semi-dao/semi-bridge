// H3：SOUL 靈魂文檔——序列化回環＋systemPrompt 注入驗證
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/models/companion.dart';

Companion _mk({String soulMd = ''}) => Companion(
      id: 't1',
      name: '小葵',
      mbtiCode: 'INTJ',
      role: CompanionRole.research,
      soulMd: soulMd,
    );

void main() {
  test('soulMd 序列化回環：空不寫入、非空讀回', () {
    final empty = _mk();
    expect(empty.toJson().containsKey('soulMd'), false);
    expect(Companion.fromJson(empty.toJson()).soulMd, '');

    final withSoul = _mk(soulMd: '## 真實圖像思考\n先看見，再動手。');
    final json = withSoul.toJson();
    expect(json['soulMd'], contains('真實圖像思考'));
    expect(Companion.fromJson(json).soulMd, contains('先看見'));
  });

  test('systemPrompt：soulMd 注入最頂層、空時不出現段落標題', () {
    final withSoul = _mk(soulMd: '我是小葵，圖像思考者。');
    final p = withSoul.systemPrompt;
    // SOUL 段在最前（先於 basePrompt 的 MBTI 描述）
    expect(p.indexOf('靈魂文檔'), lessThan(p.indexOf('你是一位')));
    expect(p, contains('我是小葵，圖像思考者。'));

    final noSoul = _mk();
    expect(noSoul.systemPrompt.contains('靈魂文檔'), isFalse);
  });

  test('copyWith soulMd 可更新', () {
    final c = _mk().copyWith(soulMd: '新靈魂');
    expect(c.soulMd, '新靈魂');
  });
}
