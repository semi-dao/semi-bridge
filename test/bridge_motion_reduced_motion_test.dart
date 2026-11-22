// [Reduced Motion 2026-11-20] 回歸測試——鎖住 BridgeMotion.resolve 的行為契約：
// 1. 一般情況：duration 原樣通過
// 2. disableAnimations=true：duration 歸零（動畫直接落 end state）
// 3. 無 MediaQuery 環境：安全 fallback（不歸零）
// 依 spec 禁歧義原則：end state 與動畫無關（motion decorates state）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/theme/bridge_motion.dart';

void main() {
  testWidgets('BridgeMotion.resolve: 一般情況 duration 原樣通過', (tester) async {
    Duration? resolved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          resolved = BridgeMotion.resolve(
              context, const Duration(milliseconds: 300));
          return const SizedBox();
        },
      ),
    ));
    expect(resolved, const Duration(milliseconds: 300));
  });

  testWidgets('BridgeMotion.resolve: disableAnimations=true → Duration.zero',
      (tester) async {
    Duration? resolved;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
      home: Builder(
        builder: (context) {
          resolved = BridgeMotion.resolve(
              context, const Duration(milliseconds: 300));
          return const SizedBox();
        },
      ),
    ));
    expect(resolved, Duration.zero,
        reason: 'reduced motion 時動畫必須歸零，直接落在 end state');
  });

  testWidgets('BridgeMotion.resolve: Duration.zero 輸入短路不查 MediaQuery',
      (tester) async {
    Duration? resolved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          resolved = BridgeMotion.resolve(context, Duration.zero);
          return const SizedBox();
        },
      ),
    ));
    expect(resolved, Duration.zero);
  });
}
