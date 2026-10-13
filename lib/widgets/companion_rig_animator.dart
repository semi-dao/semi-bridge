// companion_rig_animator.dart
// [小葵 2026-09-11] 小橋活體懸浮窗——四層切圖（body/head/arm_R/arm_L）程序動畫。
//
// 核心設計（Blue 2026-09-11 令）：「每個狀態的圖都是能動的，切換時連動不突跳」。
// 做法＝每個狀態只是同一組動畫參數（幅度/速度/相位/偏移）的目標值，
// 狀態切換時參數用 lerp 平滑過渡（0.6s），畫面永遠連續。
// 成本恆定：無論幾個狀態，每幀就是 4 個 Transform.rotate，遠低於 GPU 5% 紀律。
//
// 素材源：Blue資料區/電腦代操測試/xiaoqiao_rig（Godot 版同源切層）。

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';

import 'companion_rig.dart';
import 'package:flutter/material.dart';

/// 單一狀態的動畫參數集——狀態差異=參數差異，不是不同素材
class RigParams {
  final double breatheAmp; // 呼吸幅度（scale 振幅）
  final double breatheSpeed;
  final double headNodAmp; // 點頭幅度（rad）
  final double headTiltAmp; // 頭偏轉幅度
  final double headSpeed;
  final double armRAmp; // 右臂（持筆）抬起幅度
  final double armRSpeed;
  final double armRAbs; // 是否用 |sin|（週期性單向抬起）
  final double armLAmp; // 左臂（托書）
  final double armLSpeed;
  final double bodySwayAmp; // 身體搖曳
  final double bodySwaySpeed;

  const RigParams({
    this.breatheAmp = 0.006,
    this.breatheSpeed = 1.1,
    this.headNodAmp = 0.05,
    this.headTiltAmp = 0.03,
    this.headSpeed = 0.8,
    this.armRAmp = 0.25,
    this.armRSpeed = 0.5,
    this.armRAbs = 1.0,
    this.armLAmp = 0.06,
    this.armLSpeed = 0.45,
    this.bodySwayAmp = 0.008,
    this.bodySwaySpeed = 0.4,
  });

  RigParams lerp(RigParams o, double t) => RigParams(
        breatheAmp: _l(breatheAmp, o.breatheAmp, t),
        breatheSpeed: _l(breatheSpeed, o.breatheSpeed, t),
        headNodAmp: _l(headNodAmp, o.headNodAmp, t),
        headTiltAmp: _l(headTiltAmp, o.headTiltAmp, t),
        headSpeed: _l(headSpeed, o.headSpeed, t),
        armRAmp: _l(armRAmp, o.armRAmp, t),
        armRSpeed: _l(armRSpeed, o.armRSpeed, t),
        armRAbs: _l(armRAbs, o.armRAbs, t),
        armLAmp: _l(armLAmp, o.armLAmp, t),
        armLSpeed: _l(armLSpeed, o.armLSpeed, t),
        bodySwayAmp: _l(bodySwayAmp, o.bodySwayAmp, t),
        bodySwaySpeed: _l(bodySwaySpeed, o.bodySwaySpeed, t),
      );

  static double _l(double a, double b, double t) => a + (b - a) * t;
}

/// 九狀態參數表——所有狀態共用四層素材，只換參數
const Map<String, RigParams> kRigParamsByState = {
  'idle': RigParams(
    headNodAmp: 0.05, headTiltAmp: 0.03,
    armRAmp: 0.25, armRSpeed: 0.5,
    armLAmp: 0.12,
    bodySwayAmp: 0.008,
  ),
  'reading': RigParams(
    headNodAmp: 0.05, headTiltAmp: 0.03,
    armRAmp: 0.25, armRSpeed: 0.5,
    armLAmp: 0.12,
    bodySwayAmp: 0.008,
  ),
  'writing': RigParams(
    headNodAmp: 0.04, headTiltAmp: 0.03, headSpeed: 1.2,
    armRAmp: 0.20, armRSpeed: 1.4, armRAbs: 0.0,
    armLAmp: 0.05,
    bodySwayAmp: 0.008,
  ),
  'stuck': RigParams(
    headTiltAmp: 0.12, headSpeed: 0.25,
    headNodAmp: 0.02,
    armRAmp: 0.06, armRSpeed: 0.2,
    armLAmp: 0.02,
    breatheAmp: 0.004, breatheSpeed: 0.6,
    bodySwayAmp: 0.004,
  ),
  'idea': RigParams(
    headNodAmp: 0.04, headTiltAmp: 0.03, headSpeed: 1.6,
    armRAmp: 0.35, armRSpeed: 1.0,
    armLAmp: 0.12,
    breatheAmp: 0.010, breatheSpeed: 1.4,
    bodySwayAmp: 0.008,
  ),
  'pointing': RigParams(
    headNodAmp: 0.04, headTiltAmp: 0.06,
    armRAmp: 0.30, armRSpeed: 0.7,
    armLAmp: 0.06,
    bodySwayAmp: 0.006,
  ),
  'bridging': RigParams(
    armRAmp: 0.22, armRSpeed: 0.6,
    armLAmp: 0.15, armLSpeed: 0.6,
    headTiltAmp: 0.08,
    bodySwayAmp: 0.008,
  ),
  'celebrating': RigParams(
    armRAmp: 0.45, armRSpeed: 1.8, armRAbs: 0.0,
    armLAmp: 0.25, armLSpeed: 1.5,
    headNodAmp: 0.08, headSpeed: 1.8,
    breatheAmp: 0.012, breatheSpeed: 1.8,
    bodySwayAmp: 0.020, bodySwaySpeed: 1.2,
  ),
  'wandering': RigParams(
    headTiltAmp: 0.11, headSpeed: 0.3,
        armRAmp: 0.10, armRSpeed: 0.3,
    armLAmp: 0.06,
    bodySwayAmp: 0.018, bodySwaySpeed: 0.25,
  ),
};

/// 四層 rig 動畫 widget——狀態由外部傳入（CompanionStatusSpec.id）
class CompanionRigAnimator extends StatefulWidget {
  final String companionName;
  final String stateId;
  final double size;

  const CompanionRigAnimator({
    super.key,
    required this.companionName,
    required this.stateId,
    required this.size,
  });

  @override
  State<CompanionRigAnimator> createState() => _CompanionRigAnimatorState();
}

class _CompanionRigAnimatorState extends State<CompanionRigAnimator>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _t = 0;
  RigParams _current = kRigParamsByState['idle']!;
  RigParams _from = kRigParamsByState['idle']!;
  RigParams _target = kRigParamsByState['idle']!;
  double _blend = 1.0; // 1 = 過渡完成

  // 幾何由 companion_rig.dart 註冊表供應（多夥伴）
  RigGeometry get _geo => kRigByCompanion[widget.companionName]!;
  String get _assetBase => _geo.assetBase;
  Rect get _headBox => Rect.fromLTRB(_geo.headBox[0], _geo.headBox[1], _geo.headBox[2], _geo.headBox[3]);
  Offset get _headPivot => Offset(_geo.headPivot[0], _geo.headPivot[1]);
  Rect get _armRBox => Rect.fromLTRB(_geo.armRBox[0], _geo.armRBox[1], _geo.armRBox[2], _geo.armRBox[3]);
  Offset get _armRPivot => Offset(_geo.armRPivot[0], _geo.armRPivot[1]);
  Rect get _armLBox => Rect.fromLTRB(_geo.armLBox[0], _geo.armLBox[1], _geo.armLBox[2], _geo.armLBox[3]);
  Offset get _armLPivot => Offset(_geo.armLPivot[0], _geo.armLPivot[1]);
  Size get _full => Size(_geo.fullW, _geo.fullH);

  @override
  void initState() {
    super.initState();
    _target = kRigParamsByState[widget.stateId] ?? kRigParamsByState['idle']!;
    _current = _target;
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(covariant CompanionRigAnimator old) {
    super.didUpdateWidget(old);
    if (old.stateId != widget.stateId) {
      // 狀態切換：從「目前混合值」平滑過渡到新目標（0.6s）
      _from = _current;
      _target = kRigParamsByState[widget.stateId] ?? _target;
      _blend = 0.0;
    }
  }

  void _tick(Duration elapsed) {
    // 用幀間 delta 驅動（不依賴 elapsed 絕對值，暫停後不跳變）
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    _t += dt;
    if (_blend < 1.0) {
      _blend = (_blend + dt / 0.6).clamp(0.0, 1.0); // 0.6 秒過渡
      final curve = Curves.easeInOut.transform(_blend);
      _current = _from.lerp(_target, curve);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _current;
    final scale = widget.size / _full.width; // 以寬度貼合
    final breathe = 1.0 + math.sin(_t * p.breatheSpeed) * p.breatheAmp;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipRect(
        child: Transform.scale(
          scale: breathe * scale,
          child: SizedBox(
            width: _full.width,
            height: _full.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 底層：完整身體（不動）
                Positioned(
                  left: 0,
                  top: 0,
                  child: Image.asset(
                    '$_assetBase/body_full.png',
                    width: _full.width,
                    height: _full.height,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                // 身體搖曳：整個 Stack 的外層旋轉（見 build 外框）
                _part(
                  '$_assetBase/head.png',
                  _headBox,
                  _headPivot,
                  math.sin(_t * p.headSpeed) * p.headNodAmp +
                      math.sin(_t * 0.13) * p.headTiltAmp,
                ),
                _part(
                  '$_assetBase/arm_R.png',
                  _armRBox,
                  _armRPivot,
                  _armAngle(p.armRAmp, p.armRSpeed, p.armRAbs) * -1,
                ),
                _part(
                  '$_assetBase/arm_L.png',
                  _armLBox,
                  _armLPivot,
                  math.sin(_t * p.armLSpeed) * p.armLAmp +
                      math.sin(_t * 0.23).abs() * p.armLAmp,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _armAngle(double amp, double speed, double absMode) {
    final wave = math.sin(_t * speed);
    final angled = wave * (1 - absMode) + wave.abs() * absMode;
    return angled * amp;
  }
  Widget _part(String asset, Rect box, Offset pivot, double rotation) {
    return Positioned(
      left: box.left,
      top: box.top,
      width: box.width,
      height: box.height,
      child: Transform(
        alignment: Alignment(
          // pivot 相對 box 的對齊分量（-1..1）
          (pivot.dx - box.left) / box.width * 2 - 1,
          (pivot.dy - box.top) / box.height * 2 - 1,
        ),
        transform: Matrix4.rotationZ(rotation),
        child: Image.asset(
          asset,
          width: box.width,
          height: box.height,
          fit: BoxFit.fill,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
