// galaxy_settings_panel.dart
// [v232 小葵 2026-09-03 Blue 設定窗令] 星系圖譜視覺/聽覺參數設定窗
// 左側可收折、36 參數全上、全彩 RGB 色盤、每列可隱藏（持久化）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/dev_paths.dart';

/// 參數定義（id、名稱、群組、型別、預設、範圍）
class GParamDef {
  final String id, label, group;
  final String type; // slider | toggle | color
  final double min, max, def;
  final int divisions;
  const GParamDef(this.id, this.label, this.group, this.type,
      {this.min = 0, this.max = 1, this.def = 0, this.divisions = 0});
}

// [v237 Blue 記憶性質色板令] 13 種記憶性質代表色（與頁面 SUB_HUE 同步）
const kSubColorDefs = <(String, String, int)>[
  ('subColor.makesMeGlow', '讓我發光', 0xFFFFF3C4), // [v238]
  ('subColor.resonance', '共鳴', 0xFF4ECDC4),
  ('subColor.heartFelt', '心動', 0xFFFF6B9D),
  ('subColor.mindSaid', '心語', 0xFFB98AFF),
  ('subColor.smoothFlow', '順流', 0xFF7FD894),
  ('subColor.mustMoment', '必須時刻', 0xFFFFD166),
  ('subColor.synchronicity', '同步性', 0xFF5FD8E8),
  ('subColor.anxietySource', '焦慮源', 0xFFFF9E6B),
  ('subColor.activeBridging', '主動橋接', 0xFFC3F584),
  ('subColor.invitationAppeared', '邀請現身', 0xFFFF8FAB),
  ('subColor.doorEntered', '入門', 0xFF9D8BFF),
  ('subColor.splitMoment', '分裂時刻', 0xFFFFC09F),
  ('subColor.workflow_node', '工作流', 0xFF84DCFF),
  ('subColor.integrationResult', '整合結果', 0xFFD8B6FF),
];

final kGParams = <GParamDef>[
  // A 星系整體
  GParamDef('spinSpeed', '自轉速度', 'A · 星系', 'slider', min: 0, max: 0.3, def: 0.05),
  GParamDef('spinOn', '自轉開關', 'A · 星系', 'toggle', def: 1),
  GParamDef('initDist', '初始視角距離', 'A · 星系', 'slider', min: 800, max: 3200, def: 1900),
  GParamDef('pixelRatio', '畫質（像素比）', 'A · 星系', 'slider', min: 0.75, max: 2.0, def: 1.25),
  // B 縫線
  GParamDef('breatheSpd', '呼吸律動速度', 'B · 縫線', 'slider', min: 0.2, max: 4, def: 1.6),
  GParamDef('breatheAmp', '呼吸幅度', 'B · 縫線', 'slider', min: 0, max: 3.2, def: 1.6),
  GParamDef('sagK', '弦下垂弧度', 'B · 縫線', 'slider', min: 0, max: 0.001, def: 0.00035),
  GParamDef('flowSpd', '流光速度', 'B · 縫線', 'slider', min: 0.2, max: 3, def: 1.0),
  GParamDef('linksPerStar', '每星連線上限', 'B · 縫線', 'slider', min: 1, max: 6, def: 3, divisions: 5),
  // C 星點
  GParamDef('hubScale', '記憶球尺寸', 'C · 星點', 'slider', min: 0.5, max: 2, def: 1.0),
  GParamDef('hubCore', '光球核心比例', 'C · 星點', 'slider', min: 0.5, max: 2, def: 1.0),
  GParamDef('hoverRadius', 'hover 命中半徑', 'C · 星點', 'slider', min: 0.5, max: 2, def: 1.0),
  // D 聽覺
  GParamDef('audioOn', '音效總開關', 'D · 聽覺', 'toggle', def: 1),
  GParamDef('pluckVol', '撥弦音量', 'D · 聽覺', 'slider', min: 0, max: 0.4, def: 0.16),
  GParamDef('pluckDur', '撥弦殘響(秒)', 'D · 聽覺', 'slider', min: 0.5, max: 6, def: 3.5),
  GParamDef('repluckMs', '重撥間隔(ms)', 'D · 聽覺', 'slider', min: 300, max: 3000, def: 1100),
  GParamDef('freqLo', '弦音域下限(Hz)', 'D · 聽覺', 'slider', min: 55, max: 440, def: 110),
  GParamDef('freqHi', '弦音域上限(Hz)', 'D · 聽覺', 'slider', min: 440, max: 1760, def: 880),
  GParamDef('starVol', '檔案音量', 'D · 聽覺', 'slider', min: 0, max: 0.4, def: 0.12),
  GParamDef('starCoolS', '檔案冷卻(秒)', 'D · 聽覺', 'slider', min: 1, max: 10, def: 3),
  GParamDef('detuneCents', '音樂盒失諧(音分)', 'D · 聽覺', 'slider', min: 0, max: 10, def: 3),
  // E 顏色
  GParamDef('colImg', '影像檔色', 'E · 顏色', 'color', def: 0xFFF0CE5E),
  GParamDef('colDoc', '文件檔色', 'E · 顏色', 'color', def: 0xFF7FD894),
  GParamDef('colCode', '程式檔色', 'E · 顏色', 'color', def: 0xFFB98AFF),
  GParamDef('colData', '數據檔色', 'E · 顏色', 'color', def: 0xFF5FD8E8),
  GParamDef('colOther', '其他檔色', 'E · 顏色', 'color', def: 0xFFFF9E6B),
  GParamDef('colThread', '縫線顏色', 'E · 顏色', 'color', def: 0xFFB28DFF),
  GParamDef('colUI', 'UI 主題色', 'E · 顏色', 'color', def: 0xFFF0CE5E),
  GParamDef('colGold', '金球顏色', 'E · 顏色', 'color', def: 0xFFF0CE5E),
  // [v237] 記憶性質色板 13 色（改色→頁面光球+圖例同步）
  for (final (id, label, defColor) in kSubColorDefs)
    GParamDef(id, label, 'E · 顏色', 'color', def: defColor.toDouble()),
];

class GalaxySettingsPanel extends StatefulWidget {
  final int gatewayPort;
  const GalaxySettingsPanel({super.key, this.gatewayPort = 8420});
  @override
  State<GalaxySettingsPanel> createState() => _GalaxySettingsPanelState();
}

class _GalaxySettingsPanelState extends State<GalaxySettingsPanel> {
  bool _open = false;
  Timer? _pollTimer; // [v260] 外部（獨立視窗）改值 → App 拉桿跟隨
  final Map<String, DateTime> _editLock = {}; // 拖曳中/剛放開的參數不覆蓋
  Map<String, dynamic> _values = {};
  Set<String> _hidden = {};
  String? _token;

  @override
  void initState() {
    super.initState();
    _token = _readToken();
    _loadPersisted();
    // [v260] 每秒同步外部變更（獨立視窗拉桿 → App 面板跟隨；預覽本就同步）
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!_open || _token == null) return;
      try {
        final c = await HttpClient().getUrl(
            Uri.parse('http://127.0.0.1:${widget.gatewayPort}/galaxy_params?token=$_token'));
        final res = await c.close();
        if (res.statusCode != 200) return;
        final j = jsonDecode(await res.transform(utf8.decoder).join());
        final params = (j['params'] ?? {}) as Map<String, dynamic>;
        final now = DateTime.now();
        var changed = false;
        params.forEach((k, v) {
          if (_editLock[k] != null && now.difference(_editLock[k]!) < const Duration(seconds: 3)) return;
          final cur = _values[k];
          final same = (cur is num && v is num && cur == v) || (cur == v);
          if (!same) { _values[k] = v; changed = true; }
        });
        if (changed && mounted) setState(() {});
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  String? _readToken() {
    try {
      final f = File(resolveDevPath('~/Library/Application Support/farm.semiwasabi.bridgeApp/mcp_token'));
      if (f.existsSync()) return f.readAsStringSync().trim();
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> _persistFile(String name) {
    final dir = resolveDevPath('~/Library/Application Support/farm.semiwasabi.bridgeApp');
    return {'path': '$dir/galaxy_settings_$name.json'};
  }

  Future<void> _loadPersisted() async {
    try {
      final dir = Directory(resolveDevPath('~/Library/Application Support/farm.semiwasabi.bridgeApp'));
      final vFile = File('${dir.path}/galaxy_settings_values.json');
      final hFile = File('${dir.path}/galaxy_settings_hidden.json');
      if (vFile.existsSync()) {
        _values = jsonDecode(vFile.readAsStringSync()) as Map<String, dynamic>;
      }
      if (hFile.existsSync()) {
        _hidden = (jsonDecode(hFile.readAsStringSync()) as List).cast<String>().toSet();
      }
    } catch (_) {}
    if (mounted) setState(() {});
    _pushAll();
  }

  Future<void> _persistAndPush() async {
    try {
      final dir = resolveDevPath('~/Library/Application Support/farm.semiwasabi.bridgeApp');
      File('$dir/galaxy_settings_values.json').writeAsStringSync(jsonEncode(_values));
      File('$dir/galaxy_settings_hidden.json').writeAsStringSync(jsonEncode(_hidden.toList()));
      // 推送到 gateway（webview 1 秒內拉到）
      final token = _token ?? '';
      final req = await HttpClient().postUrl(Uri.parse('http://127.0.0.1:${widget.gatewayPort}/galaxy_params?token=$token'));
      req.headers.contentType = ContentType.json;
      req.headers.add('x-bridge-token', token);
      req.write(jsonEncode({'params': _values}));
      final res = await req.close();
      debugPrint('[galaxy-settings] push status=${res.statusCode}');
    } catch (e) {
      debugPrint('[galaxy-settings] push err=$e');
    }
  }

  void _pushAll() => _persistAndPush();

  dynamic _val(GParamDef d) => _values[d.id] ?? d.def;

  Future<void> _setVal(GParamDef d, dynamic v) async {
    _editLock[d.id] = DateTime.now(); // [v260] 拖曳/剛改的值不被輪詢覆蓋
    _values[d.id] = v;
    setState(() {});
    _persistAndPush();
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Positioned(
        left: 12, top: 80,
        child: _pillBtn('🎛️ 星系設定', _openPanel),
      );
    }
    final groups = <String, List<GParamDef>>{};
    for (final d in kGParams) {
      if (_hidden.contains(d.id)) continue;
      groups.putIfAbsent(d.group, () => []).add(d);
    }
    return Positioned(
      left: 12, top: 72, bottom: 60,
      child: Material(
        color: const Color(0xF0101418),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x40F0CE5E)),
          ),
          child: Column(
            children: [
              // 標題列
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0x30F0CE5E)))),
                child: Row(children: [
                  const Expanded(child: Text('🎛️ 星系設定',
                      style: const TextStyle(color: Color(0xFFF0CE5E), fontWeight: FontWeight.w600, fontSize: 13))),
                  // [v235 Blue 原廠令] 恢復原廠設定——36 參數回預設+隱藏清單清空
                  _miniBtn('↺ 原廠', _factoryReset),
                  const SizedBox(width: 6),
                  // [v233 Blue 聲音開關令] 標題列喇叭鈕——一鍵開關全部音效
                  _soundBtn(),
                  const SizedBox(width: 6),
                  if (_hidden.isNotEmpty)
                    _miniBtn('顯示全部', () { setState(() => _hidden.clear()); _persistAndPush(); }),
                  const SizedBox(width: 6),
                  _miniBtn('收起', _closePanel),
                ]),
              ),
              // 參數列表
              Expanded(
                child: ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (ctx, gi) {
                    final g = groups.keys.elementAt(gi);
                    final defs = groups[g]!;
                    return ExpansionTile(
                      initiallyExpanded: gi == 0,
                      title: Text(g, style: const TextStyle(color: Color(0xFF8FB8A5), fontSize: 13)),
                      children: [
                        for (final d in defs) _paramRow(d),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // [小葵 2026-09-25 開面板咚修] Blue 實測：開「星系設定」彈窗瞬間會
  // 「咚」一聲——面板蓋上 webview 時滑鼠 hover 注入還在跑，座標落在弦
  // 上=撥一聲。修：開面板時通知頁面進入 1.5s UI 靜音窗（UI 操作音吞掉），
  // 並暫停 hover 注入至面板關閉。
  void _openPanel() {
    setState(() => _open = true);
    _notifyUiMute();
  }
  void _closePanel() => setState(() => _open = false);

  void _notifyUiMute() {
    // 透過 gateway 廣播：頁面端 __uiMuteUntil 收到即吞音（playTone 檢查）
    // 用 fetch 短路而非 evaluateJavascript——不依賴 webview controller。
    final port = widget.gatewayPort;
    () async {
      try {
        final uri = Uri.parse('http://127.0.0.1:$port/galaxy_note?type=uiMute&ms=1500&token=${_token ?? ''}');
        final q = await HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        final req = await q.openUrl('GET', uri);
        req.headers.set('x-bridge-token', _token ?? '');
        await req.close();
        q.close();
      } catch (_) {}
    }();
  }

  Widget _pillBtn(String label, VoidCallback onTap) => MouseRegion(
        cursor: SystemMouseCursors.click, // [v260 Blue 令] 按鈕手指
        child: Material(
        color: const Color(0xCC101418),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(label, style: const TextStyle(color: Color(0xFFF0CE5E), fontSize: 13)),
          ),
        ),
        ),
      );

  // [v235] 恢復原廠設定——全部參數回預設值+隱藏清單清空+推送
  Future<void> _factoryReset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101418),
        title: const Text('恢復原廠設定？', style: TextStyle(color: Color(0xFFF0CE5E), fontSize: 16)),
        content: const Text('36 個參數全部回到預設值\n（你的自訂與隱藏清單會被清除）',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢復原廠', style: TextStyle(color: Color(0xFFF0CE5E))),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() {
      _values = {for (final d in kGParams) d.id: d.def};
      _hidden.clear();
    });
    _persistAndPush();
  }

  // [v233] 聲音開關（audioOn 參數的快捷鏡像）
  Widget _soundBtn() {
    final on = ((_values['audioOn'] as num?) ?? 1) > 0.5;
    return InkWell(
      onTap: () {
        _values['audioOn'] = on ? 0 : 1;
        setState(() {});
        _persistAndPush();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(on ? '🔊' : '🔇', style: const TextStyle(fontSize: 15)),
      ),
    );
  }

  Widget _miniBtn(String label, VoidCallback onTap) => MouseRegion(
        cursor: SystemMouseCursors.click, // [v261] 全元件手指令
        child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(label, style: const TextStyle(color: Color(0xFF8FB8A5), fontSize: 12)),
        ),
        ),
      );

  Widget _paramRow(GParamDef d) {
    final v = _val(d);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        Expanded(
          flex: 5,
          child: Text(d.label, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        ),
        Expanded(
          flex: 6,
          child: _control(d, v),
        ),
        // 隱藏鈕
        InkWell(
          onTap: () { setState(() => _hidden.add(d.id)); _persistAndPush(); },
          child: const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.visibility_off, size: 13, color: Color(0x608FB8A5)),
          ),
        ),
      ]),
    );
  }

  Widget _control(GParamDef d, dynamic v) {
    if (d.type == 'toggle') {
      // [v236 Blue 令] 開關置中（欄位中央）
      return Align(
        alignment: Alignment.center,
        child: SizedBox(
          width: 22, height: 12,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 44, height: 24,
              child: MouseRegion(
                cursor: SystemMouseCursors.click, // [v261] 開關手指
                child: Switch(
                value: (v as num) > 0.5,
                activeColor: const Color(0xFFF0CE5E),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (b) => _setVal(d, b ? 1 : 0),
              ),
            ),
            ),
          ),
        ),
      );
    }
    if (d.type == 'color') {
      final c = Color((v as num).toInt());
      return Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: () => _pickColor(d),
          child: Container(
            width: 30, height: 22,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.white24)),
          ),
        ),
        const SizedBox(width: 4),
        Text('#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ]);
    }
    // slider
    return Row(children: [
      Expanded(
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: const Color(0xFFF0CE5E),
            inactiveTrackColor: Colors.white12,
            thumbColor: const Color(0xFFF0CE5E),
          ),
          child: MouseRegion(
            cursor: SystemMouseCursors.click, // [v261] 拉桿手指
            child: Slider(
            value: (v as num).toDouble().clamp(d.min, d.max),
            min: d.min, max: d.max,
            divisions: d.divisions > 0 ? d.divisions : null,
            onChanged: (nv) => _setVal(d, nv),
          ),
          ),
        ),
      ),
      SizedBox(
        width: 38,
        child: Text(_fmt(v),
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ),
    ]);
  }

  String _fmt(dynamic v) {
    final d = (v as num).toDouble();
    if (d >= 100) return d.round().toString();
    return d.toStringAsFixed(d < 0.01 ? 5 : 2);
  }

  Future<void> _pickColor(GParamDef d) async {
    // 全彩 RGB：系統級揀色器（macOS 原生百萬色）
    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => _RgbPickerDialog(initial: Color((_val(d) as num).toInt())),
    );
    if (picked != null) _setVal(d, picked.value);
  }
}

/// 全彩 RGB 揀色器（HSV 平面+亮度條+HEX 輸入）
class _RgbPickerDialog extends StatefulWidget {
  final Color initial;
  const _RgbPickerDialog({required this.initial});
  @override
  State<_RgbPickerDialog> createState() => _RgbPickerDialogState();
}

class _RgbPickerDialogState extends State<_RgbPickerDialog> {
  late HSVColor hsv;
  late TextEditingController hexCtrl;

  @override
  void initState() {
    super.initState();
    hsv = HSVColor.fromColor(widget.initial);
    hexCtrl = TextEditingController(text: _toHex(widget.initial));
  }

  String _toHex(Color c) =>
      '#${c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final cur = hsv.toColor();
    return AlertDialog(
      backgroundColor: const Color(0xFF101418),
      title: const Text('全彩 RGB 揀色', style: TextStyle(color: Color(0xFFF0CE5E), fontSize: 16)),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // SV 平面
          // [v236 修] SV 面：色相純色底+上半白→透明+下半透明→黑（標準 HSV，
          // Blue 回報原本白黑相反——舊版把白色蓋在右側+黑色墊底方向錯了）
          GestureDetector(
            onPanDown: _onSVDown, onPanUpdate: _onSVUpdate,
            child: Container(
              width: 300, height: 160,
              decoration: BoxDecoration(
                color: hsv.withSaturation(1).withValue(1).toColor(),
              ),
              child: Stack(children: [
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.white.withAlpha(0), Colors.white.withAlpha(0)],
                    stops: const [0, 0.5, 1],
                  ),
                ))),
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black.withAlpha(0), Colors.black.withAlpha(0), Colors.black],
                    stops: const [0, 0.5, 1],
                  ),
                ))),
                Positioned(
                  left: hsv.saturation * 292,
                  top: (1 - hsv.value) * 152,
                  child: Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cur,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          // 色相條
          _hueBar(),
          const SizedBox(height: 10),
          Row(children: [
            Container(width: 34, height: 26,
                decoration: BoxDecoration(color: cur, borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.white24))),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: TextField(
                controller: hexCtrl,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                decoration: const InputDecoration(isDense: true, hintText: '#RRGGBB',
                    hintStyle: TextStyle(color: Colors.white24, fontSize: 12)),
                onSubmitted: (t) {
                  final v = int.tryParse(t.replaceFirst('#', ''), radix: 16);
                  if (v != null) setState(() {
                    hsv = HSVColor.fromColor(Color(0xFF000000 | v));
                    hexCtrl.text = _toHex(Color(0xFF000000 | v));
                  });
                },
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.pop(context, cur),
              child: const Text('確定', style: TextStyle(color: Color(0xFFF0CE5E))),
            ),
          ]),
        ]),
      ),
    );
  }

  void _onSVUpdate(DragUpdateDetails d) => _onSVAt(d.localPosition);
  void _onSVDown(DragDownDetails d) => _onSVAt(d.localPosition);
  void _onSVAt(Offset p) {
    setState(() {
      hsv = hsv.withSaturation((p.dx / 300).clamp(0.0, 1.0))
               .withValue(1 - (p.dy / 160).clamp(0.0, 1.0));
      hexCtrl.text = _toHex(hsv.toColor());
    });
  }

  Widget _hueBar() => GestureDetector(
        onPanDown: (d) => _onHue(d.localPosition),
        onPanUpdate: (d) => _onHue(d.localPosition),
        child: Container(
          width: 300, height: 16,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(colors: [
              for (var h = 0.0; h <= 360; h += 30)
                HSVColor.fromAHSV(1, h, 1, 1).toColor(),
            ]),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            alignment: Alignment(hsv.hue / 180 - 1, 0),
            child: Container(
              width: 10, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ),
      );

  void _onHue(Offset p) {
    setState(() {
      hsv = hsv.withHue((p.dx / 300 * 360).clamp(0.0, 360.0));
      hexCtrl.text = _toHex(hsv.toColor());
    });
  }
}
