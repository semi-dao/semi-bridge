// schedule_task_detail_drawer.dart
// [W4 2026-10-09 小葵·第二刀 UX] 排程任務詳情抽屜
//
// Blue 拍板（2026-10-09 W4 令）：點排隊卡（或左欄任務項）→ 展開
// 「任務內容（可編輯修改）＋執行歷史」抽屜。
//
// - 上半：任務內容（可編輯）——標題、排程規則（daily/weekly/once＋時間）、
//   提示詞（prompt）、產出資料夾。存檔 → 寫回畫布節點 params（setCanvasProps）
// - 下半：執行歷史時間線——schedule_runs.jsonl 逐筆：時間戳＋結果徽章
//   （✓ 綠 / ✗ 紅）＋耗時＋產出連結；失敗誠實展開錯誤訊息
// - 頂部統計列：7 天成功/失敗次數
// - 空狀態：「還沒跑過——下一場 XX:XX」
// - UI 鐵則：Tier 字級（最小 caption=12）、BridgeDSColors、誠實顯示

import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';

import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/project_door_store.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/services/semicanvas/schedule_run_store.dart';

import '../../../theme/bridge_design_system.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import 'schedule_queue_section.dart';

/// 任務詳情抽屜（右側滑入，寬 420）
class ScheduleTaskDetailDrawer extends StatefulWidget {
  final ScheduleQueueEntry entry;

  /// 存檔回呼——外面拿到新 params 自行寫回（或由本件處理亦可）
  final void Function(String nodeId, Map<String, dynamic> newParams)? onSaved;

  /// [W4.1] 點「指向畫布專案」→ 跳進畫布
  final void Function(String canvasId)? onOpenCanvas;

  /// [W4.4 Blue 令] ✕ 關閉資訊欄（頁內覆蓋模式——自己關才關）
  final VoidCallback? onClose;

  const ScheduleTaskDetailDrawer({
    super.key,
    required this.entry,
    this.onSaved,
    this.onOpenCanvas,
    this.onClose,
  });

  @override
  State<ScheduleTaskDetailDrawer> createState() =>
      _ScheduleTaskDetailDrawerState();
}

class _ScheduleTaskDetailDrawerState extends State<ScheduleTaskDetailDrawer> {
  late TextEditingController _titleCtrl;
  late TextEditingController _promptCtrl;
  late TextEditingController _folderCtrl;
  String _schedType = 'daily';
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  int _weekday = 1;
  String _onceDate = '';
  bool _saving = false;
  String? _saveMsg;

  List<ScheduleRunRecord> _runs = [];
  bool _runsLoaded = false;

  @override
  void initState() {
    super.initState();
    final p = widget.entry.params;
    _titleCtrl = TextEditingController(text: widget.entry.title);
    _promptCtrl = TextEditingController(text: (p['prompt'] as String?) ?? '');
    _folderCtrl =
        TextEditingController(text: (p['outputFolder'] as String?) ?? '');
    _schedType = (p['scheduleType'] as String?) ?? 'daily';
    _onceDate = (p['date'] as String?) ?? '';
    final t = (p['time'] as String?) ?? '09:00';
    final parts = t.split(':');
    _time = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
    _weekday = (p['weekday'] as int?) ?? 1;
    _loadRuns();
  }

  Future<void> _loadRuns() async {
    final all = await ScheduleRunStore.instance.allRuns();
    final mine =
        all.where((r) => r.jobId == widget.entry.nodeId).toList(growable: false);
    if (mounted) setState(() { _runs = mine; _runsLoaded = true; });
  }

  Future<void> _save() async {
    setState(() { _saving = true; _saveMsg = null; });
    final newParams = Map<String, dynamic>.from(widget.entry.params);
    newParams['title'] = _titleCtrl.text.trim();
    newParams['prompt'] = _promptCtrl.text;
    newParams['outputFolder'] = _folderCtrl.text.trim();
    newParams['scheduleType'] = _schedType;
    newParams['time'] =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    newParams['weekday'] = _weekday;
    if (_onceDate.isNotEmpty) newParams['date'] = _onceDate;

    String msg;
    try {
      final graph = EntityGraphService.withSqliteCanvasStore(
        memoryStore: MemoryStore(),
        doorStore: ProjectDoorStore(),
        assetStore: DigitalAssetRegistryStore(),
      );
      final nodes = await graph.getCanvasNodes(canvasId: null);
      final target = nodes.where((n) => n.entity.id == widget.entry.nodeId).firstOrNull;
      if (target == null) throw StateError('找不到節點 ${widget.entry.nodeId}');
      final newProps = target.props.copyWith(params: newParams);
      await graph.setCanvasProps(widget.entry.nodeId, newProps);
      widget.onSaved?.call(widget.entry.nodeId, newParams);
      msg = '已存檔 ✓';
    } catch (e) {
      msg = '存檔失敗：$e';
    }
    if (mounted) setState(() { _saving = false; _saveMsg = msg; });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _promptCtrl.dispose();
    _folderCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: ds.surfaceElevated,
        elevation: 12,
        child: Container(
          width: 440,
          height: double.infinity,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(ds),
              const Divider(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    _sectionLabel(ds, '任務內容', Icons.edit_outlined),
                    _field(ds, '標題', _titleCtrl),
                    _schedRuleEditor(ds),
                    _field(ds, '提示詞（prompt）', _promptCtrl, maxLines: 4),
                    // [W4.1 Blue 令] 產出位置＝「指定路徑」按鈕——Finder 式選資料夾
                    _pathPicker(ds),
                    // [W4.1 Blue 令] 指向畫布專案——點了跳進畫布調整內容（閉環）
                    _canvasLink(ds),
                    _saveRow(ds),
                    const SizedBox(height: 20),
                    _sectionLabel(ds, '執行歷史', Icons.history_outlined),
                    _statRow(ds),
                    const SizedBox(height: 8),
                    _timeline(ds),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BridgeDSColors ds) => Row(children: [
        Icon(Icons.schedule_outlined, size: 20, color: ds.accentPurple),
        const SizedBox(width: 8),
        Expanded(
          child: Text(widget.entry.title,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
        ),
        IconButton(
          icon: Icon(Icons.close, size: 18, color: ds.textMuted),
          // [W4.4] 頁內覆蓋模式：onClose 收欄；舊 modal 模式 fallback maybePop
          onPressed: () {
            if (widget.onClose != null) {
              widget.onClose!();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
      ]);

  Widget _sectionLabel(BridgeDSColors ds, String label, IconData icon) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, size: 15, color: ds.textTertiary),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: ds.textSecondary)),
        ]),
      );

  Widget _field(BridgeDSColors ds, String label, TextEditingController ctrl,
      {int maxLines = 1, bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: ds.textTertiary)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            style: TextStyle(
                fontSize: 13,
                color: ds.textPrimary,
                fontFamily: mono ? 'monospace' : null),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: ds.borderDefault)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: ds.accentBlue)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _schedRuleEditor(BridgeDSColors ds) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('排程規則', style: TextStyle(fontSize: 12, color: ds.textTertiary)),
          const SizedBox(height: 6),
          Row(children: [
            for (final t in const [('daily', '每天'), ('weekly', '每週'), ('once', '一次')])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(t.$2, style: const TextStyle(fontSize: 12)),
                  selected: _schedType == t.$1,
                  onSelected: (_) => setState(() => _schedType = t.$1),
                  selectedColor: ds.accentBlue.withValues(alpha: .25),
                  backgroundColor: ds.surface,
                  labelStyle: TextStyle(
                      color: _schedType == t.$1 ? ds.accentBlue : ds.textSecondary),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            TextButton(
              onPressed: () async {
                final picked = await showTimePicker(
                    context: context, initialTime: _time);
                if (picked != null) setState(() => _time = picked);
              },
              child: Text(
                  '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: ds.accentBlue)),
            ),
            if (_schedType == 'weekly') ...[
              const SizedBox(width: 8),
              for (var d = 1; d <= 7; d++)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                    label: Text('週$d', style: const TextStyle(fontSize: 11)),
                    selected: _weekday == d,
                    onSelected: (_) => setState(() => _weekday = d),
                    selectedColor: ds.accentBlue.withValues(alpha: .25),
                    backgroundColor: ds.surface,
                    labelStyle: TextStyle(
                        color: _weekday == d ? ds.accentBlue : ds.textSecondary),
                  ),
                ),
            ],
            if (_schedType == 'once') ...[
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) {
                      setState(() => _onceDate =
                          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
                    }
                  },
                  child: Text(
                    _onceDate.isEmpty ? '選擇日期…' : _onceDate,
                    style: TextStyle(fontSize: 13, color: ds.accentBlue),
                  ),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  /// [W4.1] 指定路徑——Finder 式資料夾選擇（file_picker getDirectoryPath）
  Widget _pathPicker(BridgeDSColors ds) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('產出位置', style: TextStyle(fontSize: 12, color: ds.textTertiary)),
          const SizedBox(height: 4),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () async {
                final dir = await FilePicker.platform.getDirectoryPath();
                if (dir != null) {
                  setState(() => _folderCtrl.text = dir);
                }
              },
              icon: Icon(Icons.folder_open_outlined, size: 15, color: ds.accentBlue),
              label: Text('指定路徑', style: TextStyle(fontSize: 13, color: ds.accentBlue)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: ds.borderDefault),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _folderCtrl.text.isEmpty ? '（未指定——預設 schedule_outputs）' : _folderCtrl.text,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, fontFamily: 'monospace', color: ds.textMuted),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// [W4.1] 指向畫布專案——顯示所屬畫布＋連線狀態；點擊跳進畫布
  Widget _canvasLink(BridgeDSColors ds) {
    final linked = widget.entry.hasConnection;
    return GestureDetector(
      onTap: _openCanvas,
      child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('指向畫布專案', style: TextStyle(fontSize: 12, color: ds.textTertiary)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.account_tree_outlined, size: 14, color: ds.accentPurple),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                _canvasTitle,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: ds.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            // [W4.1] 連線狀態徽章——緊跟名稱之後（右移 8px 間隔，不再被推到邊緣）
            if (!linked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ds.accentRed,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.link_off, size: 11, color: Colors.white),
                  const SizedBox(width: 3),
                  Text('未連接', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ]),
              )
            else
              Icon(Icons.link, size: 14, color: ds.accentGreen),
          ]),
          if (linked)
            Padding(
              padding: const EdgeInsets.only(left: 19, top: 2),
              child: Text('已連接下游節點', style: TextStyle(fontSize: 11, color: ds.accentGreen)),
            ),
          const SizedBox(height: 4),
          Text('點擊進入畫布調整工作流內容',
              style: TextStyle(fontSize: 11, color: ds.textMuted)),
        ],
      ),
    ),
    );
  }

  void _openCanvas() {
    Navigator.of(context).maybePop();
    widget.onOpenCanvas?.call(widget.entry.canvasId);
  }

  String get _canvasTitle {
    final t = widget.entry.params['canvasTitle'] as String?;
    return t ?? '（未命名畫布）';
  }

  Widget _saveRow(BridgeDSColors ds) => Row(children: [
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: ds.accentBlue,
            foregroundColor: Colors.white,
          ),
          child: Text(_saving ? '儲存中…' : '存檔',
              style: const TextStyle(fontSize: 13)),
        ),
        if (_saveMsg != null) ...[
          const SizedBox(width: 10),
          Text(_saveMsg!,
              style: TextStyle(
                  fontSize: 12,
                  color: _saveMsg!.contains('✓') ? ds.accentGreen : ds.accentRed)),
        ],
      ]);

  Widget _statRow(BridgeDSColors ds) {
    final week7 = DateTime.now().subtract(const Duration(days: 7));
    final recent = _runs.where((r) => r.firedAt.isAfter(week7)).toList();
    final ok = recent.where((r) => r.success).length;
    final fail = recent.length - ok;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ds.borderSubtle),
      ),
      child: Row(children: [
        Icon(Icons.insights_outlined, size: 14, color: ds.textTertiary),
        const SizedBox(width: 6),
        Text('近 7 天：',
            style: TextStyle(fontSize: 12, color: ds.textTertiary)),
        Text(' ✓ $ok 次',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: ds.accentGreen)),
        Text('  ✗ $fail 次',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: ds.accentRed)),
        const Spacer(),
        Text('共 ${_runs.length} 筆',
            style: TextStyle(fontSize: 12, color: ds.textMuted)),
      ]),
    );
  }

  Widget _timeline(BridgeDSColors ds) {
    if (!_runsLoaded) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('載入中…', style: TextStyle(fontSize: 12, color: ds.textMuted)),
      );
    }
    if (_runs.isEmpty) {
      final next = widget.entry.nextFire;
      final hint = next == null
          ? '還沒跑過'
          : '還沒跑過——下一場 ${next.month}/${next.day} ${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}';
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(hint, style: TextStyle(fontSize: 12, color: ds.textMuted)),
      );
    }
    // 新→舊
    final runs = List<ScheduleRunRecord>.from(_runs.reversed);
    return Column(
      children: [
        for (var i = 0; i < runs.length; i++) _runRow(ds, runs[i], i == 0),
      ],
    );
  }

  Widget _runRow(BridgeDSColors ds, ScheduleRunRecord r, bool isFirst) {
    final c = r.success ? ds.accentGreen : ds.accentRed;
    final hm =
        '${r.firedAt.month}/${r.firedAt.day} ${r.firedAt.hour.toString().padLeft(2, '0')}:${r.firedAt.minute.toString().padLeft(2, '0')}';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 時間線軸
          SizedBox(
            width: 22,
            child: Column(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
              Expanded(child: Container(width: 2, color: ds.borderSubtle)),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ds.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: r.success ? ds.borderSubtle : c.withValues(alpha: .4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(r.success ? '✓ 成功' : '✗ 失敗',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: c)),
                    const SizedBox(width: 8),
                    Text(hm, style: TextStyle(fontSize: 12, color: ds.textTertiary)),
                    const Spacer(),
                    if (r.duration.inMilliseconds > 0)
                      Text('${r.duration.inSeconds}s',
                          style: TextStyle(fontSize: 12, color: ds.textMuted)),
                  ]),
                  if (r.summary != null && r.summary!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(r.summary!,
                        style: TextStyle(fontSize: 12, color: ds.textSecondary)),
                  ],
                  if (!r.success && r.error != null) ...[
                    const SizedBox(height: 4),
                    Text(r.error!,
                        style: TextStyle(fontSize: 12, color: ds.accentRed)),
                  ],
                  for (final p in r.outputPaths) ...[
                    const SizedBox(height: 4),
                    Text(p,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: ds.accentBlue)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 顯示抽屜的入口（showDialog 版——點外部可關）
Future<void> showScheduleTaskDetailDrawer(
  BuildContext context, {
  required ScheduleQueueEntry entry,
  void Function(String nodeId, Map<String, dynamic> newParams)? onSaved,
}) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .45),
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      alignment: Alignment.centerRight,
      insetPadding: EdgeInsets.zero,
      child: ScheduleTaskDetailDrawer(entry: entry, onSaved: onSaved),
    ),
  );
}
