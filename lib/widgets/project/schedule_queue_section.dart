// schedule_queue_section.dart
// [W3 2026-10-08 小葵·第二刀 UX] 專案頁「自動排程任務」排隊分區
//
// 設計依據：Blue 拍板模擬圖（2026-10-08）：
// - 橫向排隊：直式卡由左至右排，最左＝下一棒（綠光呼吸）
// - 排隊線：水平線（綠→紫漸層）＋「現在」錨點＋順位圓標（觸發時間）
// - 倒數用相對時間「小時:分 後啟動」；每分鐘重算
// - 失敗卡照排隊（紅徽章不降級）；暫停卡離隊（半透明＋續跑鈕）
// - 四行動鈕：📂資料夾 / ⚙編輯 / ▶播放上次 / ⏸暫停
//
// 資料源（單一真相）：
// - 排程定義：畫布 schedule 節點（W1 AppScheduleEngine 掃的同源）
// - 執行結果：schedule_runs.jsonl（W2 ScheduleRunStore）
// - 下次觸發：ScheduleEngine.calculateNextFire
//
// UI 誠實鐵則：顯示真實節點數——畫布上 1 個 schedule 節點就 1 張卡。

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/project_door_store.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/services/semicanvas/schedule_engine.dart';
import 'package:bridge_app/services/semicanvas/schedule_run_store.dart';
import 'package:bridge_app/services/canvas_store.dart';

import '../../../theme/bridge_design_system.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 排隊卡資料——schedule 節點 + 最新執行紀錄的 Join 視圖
class ScheduleQueueEntry {
  final String nodeId;
  final String title;
  final String canvasId;
  final Map<String, dynamic> params;
  final DateTime? nextFire;
  final ScheduleRunRecord? lastRun;

  /// 暫停（params.paused == true）
  final bool paused;

  /// [W4.1 Blue 令] 排程節點有無出向連線（沒接=啟動也沒效果，UI 誠實警示）
  final bool hasConnection;

  const ScheduleQueueEntry({
    required this.nodeId,
    required this.title,
    required this.canvasId,
    required this.params,
    this.hasConnection = false,
    this.nextFire,
    this.lastRun,
    this.paused = false,
  });
}

/// 「⏰ 自動排程任務」排隊分區——專案頁最上方。
class ScheduleQueueSection extends StatefulWidget {
  /// 點卡片（開任務詳情設定）——W4 擴充點，現為選配
  final void Function(ScheduleQueueEntry entry)? onOpenDetail;

  /// [W4.3 Blue 令 2026-10-09] 四行動鈕——📂 開產出資料夾（Finder）
  final void Function(ScheduleQueueEntry entry)? onOpenFolder;

  /// [W4.3] ▶ 立即執行一次（不等排程時間）
  final void Function(ScheduleQueueEntry entry)? onRunNow;

  /// [W4.3] ⏸/續跑——暫停狀態切換（寫回節點 params.paused）
  final void Function(ScheduleQueueEntry entry, bool paused)? onTogglePause;

  /// [W4.3] 刷新訊號——外部改動排程狀態後 bump 觸發重載
  final ValueNotifier<int>? revNotifier;

  const ScheduleQueueSection({
    super.key,
    this.onOpenDetail,
    this.onOpenFolder,
    this.onRunNow,
    this.onTogglePause,
    this.revNotifier,
  });

  @override
  State<ScheduleQueueSection> createState() => _ScheduleQueueSectionState();
}

class _ScheduleQueueSectionState extends State<ScheduleQueueSection> {
  List<ScheduleQueueEntry> _entries = [];
  bool _loaded = false;
  bool _showAll = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    // 每分鐘重算倒數（設計：每分鐘重算，不開秒級動畫燒 CPU）
    _tick = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _load();
    });
    // [W4.3] 外部刷新訊號（暫停切換等）
    widget.revNotifier?.addListener(_onRev);
  }

  void _onRev() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    widget.revNotifier?.removeListener(_onRev);
    _tick?.cancel();
    super.dispose();
  }

  final Map<String, String> _canvasTitles = {};

  Future<void> _load() async {
    // [W4.1] 畫布標題對照表（供抽屜顯示「指向畫布專案」）
    try {
      for (final c in await CanvasStore.getAll()) {
        _canvasTitles[c.id] = c.title;
      }
    } catch (_) {}
    final entries = <ScheduleQueueEntry>[];
    try {
      final graph = EntityGraphService.withSqliteCanvasStore(
        memoryStore: MemoryStore(),
        doorStore: ProjectDoorStore(),
        assetStore: DigitalAssetRegistryStore(),
      );
      final nodes = await graph.getCanvasNodes(canvasId: null);
      final runs = await ScheduleRunStore.instance.allRuns();

      for (final e in nodes) {
        if (e.props.nodeType != WorkflowNodeType.schedule) continue;
        final params = e.props.params;
        final lastRun = runs
            .where((r) => r.jobId == e.entity.id)
            .fold<ScheduleRunRecord?>(null, (acc, r) => r);
        // [W4.1] 出向連線檢測：schedule 節點沒接線＝啟動無效果
        var hasConn = false;
        try {
          final rels = await graph.getRelations(e.entity.id);
          hasConn = rels.isNotEmpty;
        } catch (_) {}
        // [W4.1] 抽屜「指向畫布專案」顯示畫布標題
        final canvasTitle = _canvasTitles[e.props.canvasId] ?? '（未命名畫布）';
        final paramsWithTitle = Map<String, dynamic>.from(params);
        paramsWithTitle['canvasTitle'] = canvasTitle;
        entries.add(ScheduleQueueEntry(
          nodeId: e.entity.id,
          title: (params['title'] as String?) ??
              (params['label'] as String?) ??
              e.entity.title,
          canvasId: e.props.canvasId ?? '',
          params: paramsWithTitle,
          hasConnection: hasConn,
          nextFire: ScheduleEngine.calcNextFirePublic(params, DateTime.now()),
          lastRun: lastRun,
          paused: params['paused'] == true,
        ));
      }
      // 排序：暫停卡沉底；其餘按下次觸發時間升冪（最左＝下一棒）
      entries.sort((a, b) {
        if (a.paused != b.paused) return a.paused ? 1 : -1;
        final an = a.nextFire, bn = b.nextFire;
        if (an == null && bn == null) return 0;
        if (an == null) return 1;
        if (bn == null) return -1;
        return an.compareTo(bn);
      });
    } catch (_) {
      // fail-quiet：讀不到就空分區（不阻擋專案頁）
    }
    if (mounted) setState(() { _entries = entries; _loaded = true; });
  }


  // ── 佈局 ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    if (!_loaded) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 標題列
        Row(children: [
          Icon(Icons.schedule_outlined, size: 18, color: ds.accentPurple),
          const SizedBox(width: 8),
          Text('⏰ 自動排程任務',
              style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
          const SizedBox(width: 10),
          Text('排隊中 — 由左至右 · 最左=下一棒',
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: ds.textMuted)),
          const Spacer(),
          // [W3.5] 顯示全部——往下展開 S 型全卡列表（Blue 令 2026-10-09）
          GestureDetector(
            onTap: () => setState(() => _showAll = !_showAll),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: ds.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ds.borderSubtle),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('顯示全部',
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(color: ds.accentBlue)),
                Icon(_showAll ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: ds.accentBlue),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        if (_entries.isEmpty)
          _buildEmpty(ds)
        else
          _buildQueue(ds),
      ],
    );
  }

  Widget _buildEmpty(BridgeDSColors ds) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ds.borderSubtle),
      ),
      child: Text(
        '還沒有排程任務——在畫布上加一個 ⏰ schedule 節點，它就會出現在這裡排隊',
        style: TierStyle.of(context, Tier.cardBody)
            .toTextStyle()
            .copyWith(color: ds.textTertiary),
      ),
    );
  }

  Widget _buildQueue(BridgeDSColors ds) {
    final active =
        _entries.where((e) => !e.paused).toList(growable: false);
    final paused = _entries.where((e) => e.paused).toList(growable: false);
    final queue = [...active, ...paused];

    // [W3.5] 顯示全部——S 型換行全展開（照視窗寬自動排列，如 Finder 預覽）
    if (_showAll) {
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (var i = 0; i < queue.length; i++)
            _buildCardFixed(ds, queue[i], i,
                isFirst: i == 0 && !queue[i].paused,
                onOpen: () => widget.onOpenDetail?.call(queue[i]),
                onOpenFolder: () => widget.onOpenFolder?.call(queue[i]),
                onRunNow: () => widget.onRunNow?.call(queue[i]),
                onTogglePause: (p) => widget.onTogglePause?.call(queue[i], p)),
        ],
      );
    }

    // [W4.2 Blue 令] 高度隨內容：有警示行（未連接/上次失敗）時外框+34 讓卡完整呼吸
    final extraRows = queue.where((e) =>
        (!e.hasConnection && !e.paused) ||
        (e.lastRun != null && !e.lastRun!.success)).length;
    final sectionH = 296.0 + (extraRows > 0 ? 34.0 : 0.0);
    return SizedBox(
      height: sectionH,
      child: LayoutBuilder(builder: (context, consts) {
        final cardW = 208.0;
        final gap = 12.0;
        final visible =
            ((consts.maxWidth - 24) / (cardW + gap)).floor().clamp(1, 99);
        final showTail = queue.length > visible;

        return ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (var i = 0; i < queue.length; i++)
              _QueueCard(
                entry: queue[i],
                position: i,
                isFirst: i == 0 && !queue[i].paused,
                showLine: i < visible || !showTail,
                countdownNow: DateTime.now(),
                onOpen: () => widget.onOpenDetail?.call(queue[i]),
                onOpenFolder: () => widget.onOpenFolder?.call(queue[i]),
                onRunNow: () => widget.onRunNow?.call(queue[i]),
                onTogglePause: (p) => widget.onTogglePause?.call(queue[i], p),
              ),
            if (showTail)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.more_horiz,
                    size: 26, color: ds.textMuted),
              ),
          ],
        );
      }),
    );
  }
}

/// [W3.5] wrap 模式用的固定尺寸卡
Widget _buildCardFixed(BridgeDSColors ds, ScheduleQueueEntry entry, int position,
    {required bool isFirst, VoidCallback? onOpen, VoidCallback? onOpenFolder,
    VoidCallback? onRunNow, void Function(bool paused)? onTogglePause}) {
  return SizedBox(
    width: 208,
    height: 304,
    child: _QueueCard(
      entry: entry,
      position: position,
      isFirst: isFirst,
      showLine: false,
      countdownNow: DateTime.now(),
      onOpen: onOpen,
      onOpenFolder: onOpenFolder,
      onRunNow: onRunNow,
      onTogglePause: onTogglePause,
    ),
  );
}

/// 單張排隊直卡（縮短版——下排要讓位給畫布專案卡）
class _QueueCard extends StatelessWidget {
  final ScheduleQueueEntry entry;
  final int position;
  final bool isFirst;
  final bool showLine;
  final DateTime countdownNow;
  final VoidCallback? onOpen;

  /// [W4.3] 四行動鈕
  final VoidCallback? onOpenFolder;
  final VoidCallback? onRunNow;
  final void Function(bool paused)? onTogglePause;

  const _QueueCard({
    required this.entry,
    required this.position,
    required this.isFirst,
    required this.showLine,
    required this.countdownNow,
    this.onOpen,
    this.onOpenFolder,
    this.onRunNow,
    this.onTogglePause,
  });

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final run = entry.lastRun;
    final ok = run?.success ?? false;

    // 狀態燈：暫停灰 / 失敗紅 / 成功綠 / 沒跑過黃
    final ledColor = entry.paused
        ? ds.textMuted
        : run == null
            ? ds.accentYellow
            : (ok ? ds.accentGreen : ds.accentRed);

    final next = entry.nextFire;
    final durLeft = next?.difference(countdownNow);
    final countdown = (entry.paused || durLeft == null)
        ? null
        : (durLeft.isNegative ? Duration.zero : durLeft);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 208,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // [W4] 點卡片本體→開任務詳情抽屜（Blue 令 2026-10-09）
            // 順位圓標＋[W3.5] 起跑時間標（定案圖：卡頭頂標幾點起跑）
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFirst ? ds.accentGreen.withValues(alpha: .15) : ds.surfaceElevated,
                    border: Border.all(
                      color: isFirst ? ds.accentGreen : const Color(0xFF3D3570),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    entry.paused ? '⏸' : '${position + 1}',
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: entry.paused
                          ? ds.textMuted
                          : (isFirst ? ds.accentGreen : const Color(0xFFCDC4FF)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  entry.paused ? '不啟動' : _fireLabel(entry.nextFire),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ds.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 卡本體（[W4.5 Blue 令] 卡空白處不再開抽屜——⚙ 設定鈕是唯一入口）
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: entry.paused ? ds.surface.withValues(alpha: .5) : ds.surface,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: isFirst
                        ? ds.accentGreen.withValues(alpha: .55)
                        : ds.borderDefault,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 標題 + 狀態燈
                    Row(children: [
                      Expanded(
                        child: Text(entry.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TierStyle.of(context, Tier.listItemTitle)
                                .toTextStyle()),
                      ),
                      Container(
                        width: 7, height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, color: ledColor,
                          boxShadow: ledColor == ds.accentGreen
                              ? [BoxShadow(color: ledColor.withValues(alpha: .6), blurRadius: 6)]
                              : null,
                        ),
                      ),
                    ]),
                    if (isFirst) ...[
                      const SizedBox(height: 4),
                      _tag(ds, '下一棒', ds.accentGreen),
                    ],
                    // [W4.1] 未連接警示（誠實 UI：沒接線啟動無效果）
                    if (!entry.hasConnection && !entry.paused) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: ds.accentRed.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: ds.accentRed.withValues(alpha: .4)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.link_off, size: 11, color: ds.accentRed),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text('未連接——啟動無效果',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: ds.accentRed)),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 5),
                    ],
                    const SizedBox(height: 5),
                    // 排程描述
                    Text(_scheduleLabel(entry.params),
                        style: TierStyle.of(context, Tier.cardCaption)
                            .toTextStyle()
                            .copyWith(color: ds.textSecondary)),
                    const SizedBox(height: 4),
                    // [W3.5] 產出資料夾行（mono 小字）
                    Text(_folderLabel(entry.params, entry.nodeId),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: ds.textTertiary)),
                    const SizedBox(height: 6),
                    // 倒數大字
                    Container(
                      width: double.infinity,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: ds.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: ds.borderSubtle),
                      ),
                      child: countdown == null
                          ? Text('—',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: ds.textMuted))
                          : Text(
                              _formatCountdown(countdown),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [FontFeature.tabularFigures()],
                                color: isFirst ? ds.accentGreen : ds.textPrimary,
                              ),
                            ),
                    ),
                    const SizedBox(height: 6),
                    // 上次紀錄（W2 資料源）
                    Text(
                      run == null
                          ? '新任務——還沒跑過'
                          : (run.success
                              ? '上次 ✓ ${run.summary ?? '成功'}'
                              : '上次 ✗ ${_shortError(run.error)}'),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(
                            color: run != null && run.success
                                ? ds.accentGreen
                                : ds.accentRed,
                          ),
                    ),
                    const Spacer(),
                    // 四行動鈕 2×2
                    Row(children: [
                      _btn(ds, '📂', onOpenFolder),
                      const SizedBox(width: 6),
                      _btn(ds, '⚙', onOpen),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      _btn(ds, '▶', onRunNow),
                      const SizedBox(width: 6),
                      entry.paused
                          ? _btn(ds, '續跑',
                              () => onTogglePause?.call(false),
                              accent: ds.accentGreen)
                          : _btn(ds, '⏸', () => onTogglePause?.call(true)),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(BridgeDSColors ds, String label, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: c.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: c.withValues(alpha: .4)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 8.5, fontWeight: FontWeight.w700, color: c)),
      );

  Widget _btn(BridgeDSColors ds, String label, VoidCallback? onTap,
      {bool dim = false, Color? accent}) {
    return Expanded(
      child: GestureDetector(
        onTap: dim ? null : onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 5.5),
          decoration: BoxDecoration(
            color: accent != null
                ? accent.withValues(alpha: .14)
                : ds.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: accent != null
                  ? accent.withValues(alpha: .45)
                  : ds.borderSubtle,
            ),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: dim
                      ? ds.textMuted.withValues(alpha: .4)
                      : (accent ?? ds.textSecondary))),
        ),
      ),
    );
  }

  /// [W3.5] 起跑時間標——「15:00 起」「明天 09:00」「週日 21:30」
  static String _fireLabel(DateTime? next) {
    if (next == null) return '—';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(next.year, next.month, next.day);
    final hm =
        '${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}';
    final diffDays = d.difference(today).inDays;
    if (diffDays <= 0) return '$hm 起';
    if (diffDays == 1) return '明天 $hm';
    if (diffDays == 2) return '後天 $hm';
    const wd = ['一', '二', '三', '四', '五', '六', '日'];
    return '週${wd[next.weekday - 1]} $hm';
  }

  static String _folderLabel(Map<String, dynamic> params, String nodeId) {
    final f = params['outputFolder'] as String?;
    if (f != null && f.isNotEmpty) return '📁 $f/';
    return '📁 ${nodeId.length > 14 ? nodeId.substring(0, 14) : nodeId}/';
  }

  static String _shortError(String? e) {
    if (e == null || e.isEmpty) return '失敗';
    return e.length > 18 ? '${e.substring(0, 18)}…' : e;
  }

  static String _scheduleLabel(Map<String, dynamic> params) {
    final type = params['scheduleType']?.toString() ?? 'daily';
    final time = params['time']?.toString() ?? '09:00';
    switch (type) {
      case 'daily':
        return '每天 $time';
      case 'weekly':
        const wd = ['一', '二', '三', '四', '五', '六', '日'];
        final w = params['weekday'] as int? ?? 1;
        return '每週${wd[(w - 1) % 7]} $time';
      case 'monthly':
        return '每月 ${params['dayOfMonth'] ?? 1} 日 $time';
      case 'once':
        return '一次 ${params['date'] ?? ''} $time';
      case 'cron':
        return params['cronExpr']?.toString() ?? 'cron';
      default:
        return time;
    }
  }

  static String _formatCountdown(Duration d) {
    // [W4.1 Blue 令 2026-10-09] 格式：「倒數計時＊小時＊分鐘後啟動」
    if (d == Duration.zero) return '觸發中';
    if (d.inDays >= 1) {
      // 超過一天：天＋小時＋分鐘全展開（誠實精度）
      return '倒數計時${d.inDays}天${d.inHours % 24}小時${d.inMinutes % 60}分鐘後啟動';
    }
    return '倒數計時${d.inHours}小時${d.inMinutes % 60}分鐘後啟動';
  }
}
