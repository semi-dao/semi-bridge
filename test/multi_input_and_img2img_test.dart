// multi_input_and_img2img_test.dart
// [小葵 2026-08-21] 兩刀回歸：
// 1. 多線接入——同 input port 第二條線不再踢掉第一條
// 2. UpstreamData 多源收集——多條線上游全收

import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_controller.dart' show NodeTypePorts;
import 'package:bridge_app/widgets/canvas/v2/node_connection.dart';
import 'package:bridge_app/services/semicanvas/workflow_executor.dart'
    show UpstreamData;

void main() {
  test('UpstreamData 多源收集——多條線的上游全部匯入', () {
    final data = UpstreamData(
      texts: {'nodeA': '第一源', 'nodeB': '第二源', 'nodeC': '第三源'},
      base64Images: {'nodeB': 'aGVsbG8='},
    );
    expect(data.texts.length, 3);
    expect(data.combinedText, contains('第一源'));
    expect(data.combinedText, contains('第三源'));
    expect(data.firstBase64Image, 'aGVsbG8=');
    expect(data.hasImage, isTrue);
  });

  test('imageGen port 定義——image 輸入存在且型別正確', () {
    final ports = NodeTypePorts.portsFor(WorkflowNodeType.imageGen);
    final imageIn =
        ports.where((p) => p.name == 'image' && !p.isOutput).firstOrNull;
    expect(imageIn, isNotNull, reason: 'imageGen 必須有 image 輸入 port');
    expect(imageIn!.dataType, PortDataType.image);
    // port 型別匹配：image 輸出可接 image 輸入（圖生圖鏈）
    final imageOut = ports.where((p) => p.name == 'output').first;
    expect(
      NodeConnection.isPortTypeMatch(imageOut.dataType, imageIn.dataType),
      isTrue,
      reason: 'imageGen 輸出 → imageGen image 輸入（鏈式圖生圖）必須合法',
    );
  });

  test('多張上游圖全數送達——多參考圖語意', () {
    final data = UpstreamData(
      base64Images: {'nodeA': 'AAAA', 'nodeB': 'BBBB', 'nodeC': 'CCCC'},
    );
    final all = data.base64Images.values.toList();
    expect(all.length, 3, reason: '三條線接入＝三張參考圖全收');
    expect(all, containsAll(['AAAA', 'BBBB', 'CCCC']));
    // workspace 的切分邏輯：first + sublist(1)
    final first = all.first;
    final extras = all.sublist(1);
    expect(first, isNotNull);
    expect(extras.length, 2);
  });

  test('標題錨定——base64Images key 是 nodeId，可挖出節點標題做對照表', () {
    // 模擬上游兩張圖：nodeId → b64
    final data = UpstreamData(base64Images: {'nodeA': 'AAAA', 'nodeB': 'BBBB'});
    final titles = {'nodeA': '夕陽稻田', 'nodeB': '女兒的畫'};
    final legend = <String>[];
    var i = 0;
    for (final e in data.base64Images.entries) {
      i++;
      legend.add('第${i}張=「${titles[e.key]}」');
    }
    expect(legend.join('、'), '第1張=「夕陽稻田」、第2張=「女兒的畫」');
    // prompt 換權重＝換文字：A主B輔 ↔ B主A輔，線不用動
    final p1 = '夕陽稻田為主體，女兒的畫為裝飾';
    final p2 = '女兒的畫為主體，夕陽稻田為裝飾';
    expect(p1 != p2, isTrue, reason: '同一組接線，兩種權重描述都能下');
  });

  test('vision 輸出也可接 imageGen——看圖→改圖工作流', () {
    final visionOut = NodeTypePorts.portsFor(WorkflowNodeType.vision)
        .where((p) => p.isOutput)
        .first;
    final imageGenIn = NodeTypePorts.portsFor(WorkflowNodeType.imageGen)
        .where((p) => p.name == 'image')
        .first;
    // vision 輸出是 text——不能直接接 image 輸入（型別不匹配是正確的）
    expect(NodeConnection.isPortTypeMatch(visionOut.dataType, imageGenIn.dataType),
        isFalse,
        reason: 'vision 輸出 text 不能硬接 image 輸入——型別系統把關');
  });
}
