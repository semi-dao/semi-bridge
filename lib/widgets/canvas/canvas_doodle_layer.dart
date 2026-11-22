// canvas_doodle_layer.dart
// SemiCanvas 視覺 P4: 塗鴉層
// 畫筆 + 整筆擦除 + 吸色 + 打字 + 上一步 + 顏色/筆粗 + 圖層開關 + 持久化

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../../theme/bridge_design_system.dart';

/// 塗鴉模式
enum DoodleMode { draw, erase, eyedropper, text }

/// 一筆塗鴉
class DoodleStroke {
  final List<Offset> worldPoints;
  final Color color;
  final double strokeWidth;

  DoodleStroke({
    required this.worldPoints,
    required this.color,
    this.strokeWidth = 2.0,
  });

  String get type => 'stroke';

  Map<String, dynamic> toJson() => {
        'type': 'stroke',
        'points': worldPoints.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'color': color.toARGB32(),
        'strokeWidth': strokeWidth,
      };

  factory DoodleStroke.fromJson(Map<String, dynamic> json) {
    final points = (json['points'] as List)
        .map((p) => Offset(
              (p as Map<String, dynamic>)['x'] as double,
              p['y'] as double,
            ))
        .toList();
    return DoodleStroke(
      worldPoints: points,
      color: Color(json['color'] as int),
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
    );
  }
}

/// 一段文字標注
class DoodleText {
  Offset worldPos;
  String text;
  final Color color;
  double fontSize;

  DoodleText({
    required this.worldPos,
    required this.text,
    required this.color,
    this.fontSize = 14.0,
  });

  DoodleText copyWith({Offset? worldPos, double? fontSize}) {
    return DoodleText(
      worldPos: worldPos ?? this.worldPos,
      text: text,
      color: color,
      fontSize: fontSize ?? this.fontSize,
    );
  }

  String get type => 'text';

  Map<String, dynamic> toJson() => {
        'type': 'text',
        'x': worldPos.dx,
        'y': worldPos.dy,
        'text': text,
        'color': color.toARGB32(),
        'fontSize': fontSize,
      };

  factory DoodleText.fromJson(Map<String, dynamic> json) {
    return DoodleText(
      worldPos: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
      text: json['text'] as String,
      color: Color(json['color'] as int),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
    );
  }
}

/// 塗鴉層上的一個元素（stroke 或 text）— 用於統一 hit test / undo / 序列化
abstract class DoodleItem {
  String get type;
  Map<String, dynamic> toJson();
}

/// 塗鴉層 widget。
///
/// [mode] 決定行為：draw / erase / eyedropper / text
/// [visible] = false → 圖層完全隱藏
/// [enabled] = false → 顯示但不接收輸入
class CanvasDoodleLayer extends StatefulWidget {
  final List<DoodleStroke> strokes;
  final List<DoodleText> texts;
  final Offset viewportOffset;
  final double viewportScale;

  final bool enabled;
  final bool visible;
  final DoodleMode mode;

  final Color strokeColor;
  final double strokeWidth;

  final void Function(DoodleStroke stroke)? onStrokeAdded;
  final void Function(int index)? onStrokeRemoved;
  final void Function(DoodleText text)? onTextAdded;
  final void Function(int index)? onTextRemoved;
  final void Function(Color color)? onColorPicked;
  final void Function(double width)? onStrokeWidthChanged;
  /// 平移畫布 callback（右鍵/中鍵拖曳時觸發）
  final void Function(Offset delta)? onCanvasPan;
  /// 滾輪縮放透傳 — 塗鴉層啟用時仍允許畫布縮放
  final void Function(double scrollDelta, Offset localPosition)? onScrollZoom;
  /// 清空塗鴉板 — 像教練板擦戰術
  final VoidCallback? onClear;
  /// 切換塗鴉模式（draw/erase/text）
  final void Function(DoodleMode mode)? onModeChanged;
  /// 文字移動回調
  final void Function(int index, Offset newWorldPos)? onTextMoved;
  /// 文字調整大小回調
  final void Function(int index, double newFontSize)? onTextFontSizeChanged;
  /// 文字編輯回調（雙擊觸發 — 改文字內容 + 大小）
  final void Function(int index, String newText, double newFontSize)? onTextChanged;

  /// viewport 變化的監聯源（通常是 CanvasController）— 讓塗鴉重繪跟著縮放走
  final Listenable? viewportListenable;
  /// 取得最新 viewport offset 的函數（配合 viewportListenable 使用）
  final Offset Function()? viewportOffsetBuilder;
  /// 取得最新 viewport scale 的函數（配合 viewportListenable 使用）
  final double Function()? viewportScaleBuilder;

  final List<Color> colorPalette;

  const CanvasDoodleLayer({
    super.key,
    required this.strokes,
    required this.texts,
    required this.viewportOffset,
    required this.viewportScale,
    this.enabled = false,
    this.visible = true,
    this.mode = DoodleMode.draw,
    this.strokeColor = const Color(0xFFFFFFFF),
    this.strokeWidth = 2.5,
    this.onStrokeAdded,
    this.onStrokeRemoved,
    this.onTextAdded,
    this.onTextRemoved,
    this.onColorPicked,
    this.onStrokeWidthChanged,
    this.onCanvasPan,
    this.onScrollZoom,
    this.onClear,
    this.onModeChanged,
    this.onTextMoved,
    this.onTextFontSizeChanged,
    this.onTextChanged,
    this.viewportListenable,
    this.viewportOffsetBuilder,
    this.viewportScaleBuilder,
    this.colorPalette = _defaultColorPalette,
  });

  /// Default color palette for doodle colors
  static const _defaultColorPalette = [
    Color(0xFFFFFFFF),
    Color(0xFFFF6363),
    Color(0xFFFFBC33),
    Color(0xFF5FC992),
    Color(0xFF42A5F5),
    Color(0xFFCE93D8),
  ];

  @override
  State<CanvasDoodleLayer> createState() => _CanvasDoodleLayerState();
}

class _CanvasDoodleLayerState extends State<CanvasDoodleLayer> {
  static final _emptyListenable = ChangeNotifier();
  List<Offset> _currentStroke = [];

  // 平移狀態（右鍵/中鍵拖曳平移畫布）
  bool _isPanning = false;
  Offset _lastPanPos = Offset.zero;

  // 文字編輯狀態
  int? _editingTextIndex;

  // text 輸入狀態
  Offset? _textCursorPos; // 螢幕座標
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  final TextEditingController _editTextController = TextEditingController();
  final FocusNode _editFocus = FocusNode();

  Offset _worldPos(Offset screenPos) {
    final vp = widget.viewportOffsetBuilder?.call() ?? widget.viewportOffset;
    final vs = widget.viewportScaleBuilder?.call() ?? widget.viewportScale;
    return (screenPos - vp) / vs;
  }

  /// 取得即時 viewport offset
  Offset get _currentVp => widget.viewportOffsetBuilder?.call() ?? widget.viewportOffset;
  /// 取得即時 viewport scale
  double get _currentVs => widget.viewportScaleBuilder?.call() ?? widget.viewportScale;

  /// 命中測試 — stroke（用 strokeWidth 作為感應範圍）
  int? _hitTestStroke(Offset worldPos, {double? tolerance}) {
    final tol = tolerance ?? (widget.strokeWidth * 4 + 6);
    for (int i = widget.strokes.length - 1; i >= 0; i--) {
      for (final p in widget.strokes[i].worldPoints) {
        if ((p - worldPos).distance <= tol) return i;
      }
    }
    return null;
  }

  /// 擦除 — 拖曳劃過時呼叫，擦掉範圍內的筆畫/文字
  void _eraseAt(Offset localPos) {
    final wp = _worldPos(localPos);
    final si = _hitTestStroke(wp);
    if (si != null) { widget.onStrokeRemoved?.call(si); return; }
    final ti = _hitTestText(wp);
    if (ti != null) widget.onTextRemoved?.call(ti);
  }

  /// 命中測試 — text（用 bounding box）
  int? _hitTestText(Offset worldPos) {
    for (int i = widget.texts.length - 1; i >= 0; i--) {
      final t = widget.texts[i];
      // 粗略 bounding box：文字寬度 ≈ text.length * fontSize * 0.6
      final w = t.text.length * t.fontSize * 0.6 + 8;
      final h = t.fontSize + 8;
      final rect = Rect.fromLTWH(t.worldPos.dx - 4, t.worldPos.dy - 4, w, h);
      if (rect.contains(worldPos)) return i;
    }
    return null;
  }

  @override
  void didUpdateWidget(covariant CanvasDoodleLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 模式切換時取消文字輸入
    if (oldWidget.mode != widget.mode && _textCursorPos != null) {
      _cancelText();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFocus.dispose();
    _editTextController.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  void _submitText() {
    final text = _textController.text.trim();
    if (text.isNotEmpty && _textCursorPos != null) {
      // fontSize 由滑桿控制（strokeWidth 範圍 1-8，對應 24-72px）
      final fontSize = 24.0 + widget.strokeWidth * 6;
      widget.onTextAdded?.call(DoodleText(
        worldPos: _worldPos(_textCursorPos!),
        text: text,
        color: widget.strokeColor,
        fontSize: fontSize,
      ));
    }
    _textController.clear();
    setState(() => _textCursorPos = null);
  }

  /// 取消文字輸入 — 空字也能反悔
  void _cancelText() {
    _textController.clear();
    _textFocus.unfocus();
    setState(() => _textCursorPos = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: false,
      onKeyEvent: (e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          if (_textCursorPos != null) _cancelText();
        }
      },
      child: Listener(
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent) {
            widget.onScrollZoom?.call(signal.scrollDelta.dy, signal.localPosition);
          }
        },
        child: Stack(
          children: [
            _buildInputArea(),
            // 可互動文字物件（可拖曳移動、雙擊調大小）
            ..._buildTextWidgets(),
            // text 輸入框
            if (_textCursorPos != null) _buildTextInput(),
            // 畫筆設定面板（塗鴉啟用時）
            if (widget.enabled && widget.mode != DoodleMode.eyedropper)
              _buildDrawControls(),
          ],
        ),
      ),
    );
  }

  /// 渲染可互動文字物件 — 拖曳移動、雙擊編輯
  List<Widget> _buildTextWidgets() {
    final result = <Widget>[];
    for (int i = 0; i < widget.texts.length; i++) {
      final t = widget.texts[i];
      // 用 AnimatedBuilder 讓文字跟著 viewport 即時更新
      result.add(AnimatedBuilder(
        animation: widget.viewportListenable ?? _emptyListenable,
        builder: (context, _) {
          final vp = _currentVp;
          final vs = _currentVs;
          final screenPos = t.worldPos * vs + vp;
          final fontSize = t.fontSize * vs;
          return Positioned(
            left: screenPos.dx,
            top: screenPos.dy,
            child: GestureDetector(
              onPanUpdate: widget.onTextMoved != null
                  ? (d) {
                      final newScreenPos = screenPos + d.delta;
                      final newWorldPos = (newScreenPos - vp) / vs;
                      widget.onTextMoved!(i, newWorldPos);
                    }
                  : null,
              onDoubleTap: () => _showTextEditDialog(i),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Text(
                  t.text,
                  style: TextStyle(
                    fontFamily: 'Caveat',
                    color: t.color.withValues(alpha: 0.85),
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ));
    }
    return result;
  }

  /// 雙擊文字 — 彈出編輯對話框（改內容 + 調大小）
  void _showTextEditDialog(int index) {
    final t = widget.texts[index];
    _editTextController.text = t.text;
    double editFontSize = t.fontSize;
    final ds = BridgeDSColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: Text('編輯文字', style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: ds.textPrimary,)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _editTextController,
                    focusNode: _editFocus,
                    autofocus: true,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textPrimary,),
                    decoration: InputDecoration(
                      hintText: '輸入文字…',
                      hintStyle: TextStyle(color: ds.textTertiary),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: ds.borderDefault),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: ds.textSecondary),
                      ),
                    ),
                    onSubmitted: (_) {
                      widget.onTextChanged?.call(index, _editTextController.text, editFontSize);
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('大小: ${editFontSize.round()}',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textSecondary,)),
                  Slider(
                    value: editFontSize,
                    min: 12,
                    max: 96,
                    divisions: 84,
                    activeColor: t.color,
                    onChanged: (v) => setDialogState(() => editFontSize = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('取消', style: TextStyle(color: ds.textSecondary)),
                ),
                TextButton(
                  onPressed: () {
                    widget.onTextChanged?.call(index, _editTextController.text, editFontSize);
                    Navigator.pop(ctx);
                  },
                  child: Text('確認', style: TextStyle(color: t.color)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildInputArea() {
    if (!widget.enabled) {
      return IgnorePointer(
        child: _buildCanvas(const []),
      );
    }

    // 所有模式共用：右鍵/中鍵拖曳平移畫布
    return Listener(
      onPointerDown: (e) {
        if (e.buttons == 2 || e.buttons == 4) {
          _isPanning = true;
          _lastPanPos = e.localPosition;
        }
      },
      onPointerMove: (e) {
        if (_isPanning && widget.onCanvasPan != null) {
          final delta = e.localPosition - _lastPanPos;
          widget.onCanvasPan!(delta);
          _lastPanPos = e.localPosition;
        }
      },
      onPointerUp: (_) => _isPanning = false,
      onPointerCancel: (_) => _isPanning = false,
      child: _buildModeInput(),
    );
  }

  Widget _buildModeInput() {
    // erase 模式 — 拖曳劃過線條就擦掉
    if (widget.mode == DoodleMode.erase) {
      return GestureDetector(
        onPanStart: (d) {
          if (!_isPanning) _eraseAt(d.localPosition);
        },
        onPanUpdate: (d) {
          if (!_isPanning) _eraseAt(d.localPosition);
        },
        child: _buildCanvas(const []),
      );
    }

    // eyedropper 模式
    if (widget.mode == DoodleMode.eyedropper) {
      return GestureDetector(
        onTapDown: (d) {
          final wp = _worldPos(d.localPosition);
          final si = _hitTestStroke(wp);
          if (si != null) { widget.onColorPicked?.call(widget.strokes[si].color); return; }
          final ti = _hitTestText(wp);
          if (ti != null) widget.onColorPicked?.call(widget.texts[ti].color);
        },
        child: _buildCanvas(const []),
      );
    }

    // text 模式：tap 放置游標
    if (widget.mode == DoodleMode.text) {
      return GestureDetector(
        onTapDown: (d) {
          setState(() {
            _textCursorPos = d.localPosition;
            _textController.clear();
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _textFocus.requestFocus();
          });
        },
        child: _buildCanvas(const []),
      );
    }

    // draw 模式：左鍵 pan 畫線
    return GestureDetector(
      onPanStart: (d) {
        if (!_isPanning) _currentStroke = [_worldPos(d.localPosition)];
      },
      onPanUpdate: (d) {
        if (!_isPanning) setState(() => _currentStroke.add(_worldPos(d.localPosition)));
      },
      onPanEnd: (_) {
        if (!_isPanning && _currentStroke.length > 1) {
          widget.onStrokeAdded?.call(DoodleStroke(
            worldPoints: List.from(_currentStroke),
            color: widget.strokeColor,
            strokeWidth: widget.strokeWidth,
          ));
        }
        setState(() => _currentStroke = []);
      },
      child: _buildCanvas(_currentStroke),
    );
  }

  Widget _buildCanvas(List<Offset> current) {
    return CustomPaint(
      painter: _DoodlePainter(
        strokes: widget.strokes,
        texts: widget.texts,
        currentStroke: current,
        currentColor: widget.strokeColor,
        currentWidth: widget.strokeWidth,
        viewportOffset: widget.viewportOffset,
        viewportScale: widget.viewportScale,
        repaint: widget.viewportListenable,
        viewportOffsetBuilder: widget.viewportOffsetBuilder,
        viewportScaleBuilder: widget.viewportScaleBuilder,
      ),
      size: Size.infinite,
    );
  }

  /// 文字輸入框 — 浮在點擊位置
  Widget _buildTextInput() {
    return Positioned(
      left: _textCursorPos!.dx,
      top: _textCursorPos!.dy,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: widget.strokeColor, width: 1),
        ),
        child: TextField(
          controller: _textController,
          focusNode: _textFocus,
          style: TextStyle(
                    fontFamily: 'Caveat',
            color: widget.strokeColor,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            hintText: '輸入文字…',
            hintStyle: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textTertiary,),
          ),
          autofocus: true,
          onSubmitted: (_) => _submitText(),
          onEditingComplete: _submitText,
        ),
      ),
    );
  }

  /// 模式按鈕
  Widget _modeButton(DoodleMode mode, IconData icon, String label) {
    final isActive = widget.mode == mode;
    final ds = BridgeDSColors.of(context);
    return GestureDetector(
      onTap: () => widget.onModeChanged?.call(mode),
      child: Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 400),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isActive ? ds.textPrimary.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isActive ? Border.all(color: ds.textPrimary.withValues(alpha: 0.3), width: 1) : null,
          ),
          child: Icon(
            icon,
            size: 15,
            color: isActive ? ds.textPrimary : ds.textPrimary.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }

  /// 畫筆設定面板 — 浮動左下角（避開底部狀態列）
  Widget _buildDrawControls() {
    final ds = BridgeDSColors.of(context);
    return Positioned(
      left: 12,
      bottom: 52,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ds.textPrimary.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 模式切換列
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _modeButton(DoodleMode.draw, Icons.brush, '畫筆'),
                const SizedBox(width: 4),
                _modeButton(DoodleMode.erase, Icons.cleaning_services_outlined, '橡皮擦'),
                const SizedBox(width: 4),
                _modeButton(DoodleMode.text, Icons.text_fields, '文字'),
                const SizedBox(width: 12),
                // 清空按鈕
                GestureDetector(
                  onTap: widget.onClear,
                  child: Tooltip(
                    message: '清空塗鴉',
                    waitDuration: const Duration(milliseconds: 400),
                    child: Icon(Icons.delete_sweep_outlined, size: 16, color: ds.textPrimary.withValues(alpha: 0.6)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 色票列
            Row(
              mainAxisSize: MainAxisSize.min,
              children: widget.colorPalette.map((color) {
                final sel = color.toARGB32() == widget.strokeColor.toARGB32();
                return GestureDetector(
                  onTap: () => widget.onColorPicked?.call(color),
                  child: Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? ds.textPrimary : ds.textPrimary.withValues(alpha: 0.2),
                        width: sel ? 2.5 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            // 筆粗滑桿（永遠顯示 — draw 調線粗、erase 調感應範圍、text 調字大小）
            SizedBox(
              width: 160,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        activeTrackColor: widget.strokeColor,
                        inactiveTrackColor: ds.textPrimary.withValues(alpha: 0.2),
                        thumbColor: widget.strokeColor,
                        overlayColor: widget.strokeColor.withValues(alpha: 0.2),
                      ),
                      child: Slider(
                        value: widget.strokeWidth,
                        min: 1.0,
                        max: 8.0,
                        divisions: 7,
                        onChanged: widget.onStrokeWidthChanged,
                      ),
                    ),
                  ),
                  Text(
                    widget.strokeWidth.toStringAsFixed(1),
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textPrimary.withValues(alpha: 0.6),),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoodlePainter extends CustomPainter {
  final List<DoodleStroke> strokes;
  final List<DoodleText> texts;
  final List<Offset> currentStroke;
  final Color currentColor;
  final double currentWidth;
  final Offset viewportOffset;
  final double viewportScale;
  final Offset Function()? viewportOffsetBuilder;
  final double Function()? viewportScaleBuilder;

  _DoodlePainter({
    required this.strokes,
    required this.texts,
    required this.currentStroke,
    required this.viewportOffset,
    required this.viewportScale,
    this.currentColor = const Color(0xFFFFFFFF),
    this.currentWidth = 2.5,
    Listenable? repaint,
    this.viewportOffsetBuilder,
    this.viewportScaleBuilder,
  }) : super(repaint: repaint);

  Offset get _vp => viewportOffsetBuilder?.call() ?? viewportOffset;
  double get _vs => viewportScaleBuilder?.call() ?? viewportScale;

  Offset _screen(Offset world) => world * _vs + _vp;

  @override
  void paint(Canvas canvas, Size size) {
    // 筆畫
    for (final s in strokes) {
      _drawStroke(canvas, s.worldPoints, s.color, s.strokeWidth * _vs);
    }
    // 文字由 _buildTextWidgets 渲染（可互動 widget），不在 painter 裡畫
    // 當前筆畫
    if (currentStroke.length > 1) {
      _drawStroke(canvas, currentStroke, currentColor, currentWidth * _vs);
    }
  }

  void _drawStroke(Canvas canvas, List<Offset> worldPoints, Color color, double width) {
    if (worldPoints.length < 2) return;
    final sp = worldPoints.map(_screen).toList();
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(sp[0].dx, sp[0].dy);
    for (int i = 1; i < sp.length - 1; i++) {
      final mx = (sp[i].dx + sp[i + 1].dx) / 2;
      final my = (sp[i].dy + sp[i + 1].dy) / 2;
      path.quadraticBezierTo(sp[i].dx, sp[i].dy, mx, my);
    }
    if (sp.length > 1) path.lineTo(sp.last.dx, sp.last.dy);
    canvas.drawPath(path, paint);
  }

  void _drawText(Canvas canvas, DoodleText t) {
    final sp = _screen(t.worldPos);
    final fontSize = t.fontSize * _vs;
    final tp = TextPainter(
      text: TextSpan(
        text: t.text,
        style: TextStyle(
                    fontFamily: 'Caveat',
          color: t.color.withValues(alpha: 0.85),
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, sp);
  }

  @override
  bool shouldRepaint(covariant _DoodlePainter old) => true;
}
