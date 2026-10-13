import 'dart:io';

import 'package:flutter/material.dart';

import '../services/activity/background_task_registry.dart';
import '../services/local_model_runtime_service.dart';
import '../services/model_lab/model_lab_service.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import 'bridge_desktop_widgets.dart';

/// 模型實驗室——「告知 → 測試 → 替換選型」完整 LOOP 的家。
/// [小葵 2026-09-29] Blue 願景產品化：使用者遇到新開源模型時，
/// App 內完成：新模型偵察 → 兩段式快測（5張→問→20張）→ 自主報告 → 一鍵採用。
class ModelLabCard extends StatefulWidget {
  const ModelLabCard({super.key});

  @override
  State<ModelLabCard> createState() => _ModelLabCardState();
}

class _ModelLabCardState extends State<ModelLabCard> {
  int _tabIndex = 0; // 0=測試 1=報告
  final _lab = ModelLabService.instance;

  // [Blue 2026-09-29] 測試引擎=本機已下載模型動態偵測（不寫死）
  List<(String, String)> _engineOptions = []; // (modelId, 顯示名)
  String? _engineModelId;

  /// 從硬碟掃描已安裝模型（listInstalledModels → Swift 掃 .gguf）
  Future<void> _scanEngineOptions() async {
    try {
      final models = await LocalModelRuntimeService().listInstalledModels();
      final opts = <(String, String)>[];
      for (final m in models) {
        final id = m['modelId'] as String?;
        if (id == null || id.isEmpty) continue;
        final gb = ((m['fileSize'] as num?) ?? 0) / 1e9;
        final label = '${_engineDisplayName(id)}${gb > 0.5 ? '（${gb.toStringAsFixed(1)}GB）' : ''}';
        opts.add((id, label));
      }
      if (mounted) {
        setState(() {
          _engineOptions = opts;
          // 預設選最小的模型（測試引擎要快又穩）；現有選擇失效時重選
          if (_engineModelId == null || !opts.any((o) => o.$1 == _engineModelId)) {
            String? best;
            double bestGb = double.infinity;
            for (final m in models) {
              final gb = ((m['fileSize'] as num?) ?? 0) / 1e9;
              if (gb > 0 && gb < bestGb) { bestGb = gb; best = m['modelId'] as String?; }
            }
            _engineModelId = best ?? (opts.isNotEmpty ? opts.first.$1 : null);
          }
        });
      }
      debugPrint('[ModelLab] 測試引擎選項掃描: ${opts.length} 個 = ${opts.map((o) => o.$1).toList()}');
    } catch (e) {
      debugPrint('[ModelLab] 掃描測試引擎選項失敗: $e');
    }
  }

  String _engineDisplayName(String modelId) {
    // modelId e.g. gemma-4-e4b-q4 → Gemma 4 E4B
    final map = {
      'gemma-4-e4b-q4': 'Gemma 4 E4B',
      'gemma-4-12b-q4': 'Gemma 4 12B',
      'qwen3.5-4b-q4': 'Qwen3.5-4B',
    };
    return map[modelId] ?? modelId;
  }

  List<ModelLabReport> _reports = [];
  bool _loading = true;

  // 測試進行中的狀態
  bool _testing = false;
  double _progress = 0;
  String _testPhase = '';
  List<String> _pickedPhotos = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
    _scanEngineOptions();
    // [Blue 抓包 2026-09-29] 切頁回來測試「自己停了」——其實 UI 重建把 _testing 重置了。
    // 修法：測試會話掛在靜態欄位（跨 State 生存），UI 重建後恢復顯示。
    if (_activeSession != null && _activeSession!._running) {
      setState(() => _testing = true);
      _activeSession!.attach(this);
    }
  }

  @override
  void dispose() {
    // 切頁只「卸下」UI，不殺測試（未來如果要做「離開頁面=中止測試」再改這裡）
    if (_activeSession != null) _activeSession!.detach();
    super.dispose();
  }

  // ══════════ 測試會話（跨頁面生存）══════════
  static _QuickTestSession? _activeSession;

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    final reports = await _lab.loadReports();
    if (mounted) setState(() { _reports = reports; _loading = false; });
  }

  Future<void> _startQuickTest() async {
    setState(() { _testing = true; _testPhase = '抽取最近照片…'; _progress = 0; });
    _activeSession = _QuickTestSession();
    await _activeSession!.run(this);
  }

  /// 快測主體（由 _QuickTestSession 驅動；UI 更新走 onPhase/onProgress 以跨頁生存）
  Future<void> _runQuickTestBody({
    required void Function(String) onPhase,
    required void Function(double) onProgress,
    required bool Function() isAborted,
  }) async {
    final photos = await _lab.pickRecentPhotos(ModelLabService.quickTestCount);
    if (photos.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('找不到可測試的照片——先把照片匯入向量資料庫')));
      }
      return; // session._done() 會清 UI
    }
    if (_engineModelId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('請先選擇測試引擎（或先下載模型）')));
      }
      return;
    }
    if (mounted) setState(() => _pickedPhotos = photos);
    onPhase('快測 ${photos.length} 張（啟動測試引擎…）');

    // [小葵 2026-09-30 B'案] 快測引擎（18799）獨佔 GPU——
    // A案教訓：16GB 機器上主線+lab 雙 llama 疊加 GPU 統一記憶體壓力 → 兩隻連坐崩潰（實測）。
    // B'：先優雅停主線釋放 VRAM → lab 獨佔 → 測完自動復活主線（自動恢復鏈已驗證）。
    const labUrl = 'http://127.0.0.1:18799';
    final runtime = LocalModelRuntimeService();
    final engineId = _engineModelId!; // 前面已 guard 非 null
    onPhase('騰出 GPU（暫停現役模型）…');
    final stateBefore = await runtime.inspectBridgeRuntime();
    final mainWasRunning = stateBefore.phase == BridgeLocalRuntimePhase.running;
    if (mainWasRunning) {
      await runtime.stopServer();
      await Future.delayed(const Duration(seconds: 3)); // 等 llama 釋放 VRAM
    }
    BackgroundTaskRegistry.instance.update(BackgroundTask(
      id: 'model_lab_quicktest',
      name: '模型實驗室快測',
      detail: '測試引擎 ${_engineDisplayName(engineId)} 描述 $photos 張照片',
      startedAt: DateTime.now(),
    ));
    try {
      await _runLabTest(photos, labUrl, engineId, runtime, onPhase, onProgress, mainWasRunning);
    } finally {
      BackgroundTaskRegistry.instance.finish('model_lab_quicktest');
      if (mainWasRunning) {
        onPhase('恢復現役模型…');
        await runtime.startServer();
      }
    }
    return;
  }

  Future<void> _runLabTest(
    List<String> photos,
    String labUrl,
    String engineId,
    LocalModelRuntimeService runtime,
    void Function(String) onPhase,
    void Function(double) onProgress,
    bool mainWasRunning,
  ) async {
    await runtime.startLabServer(engineId);
    // 等就緒（Swift 端標記 labServer.status=running；輪詢最多 60s）
    var labReady = false;
    for (var i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse('$labUrl/health'));
        final resp = await req.close().timeout(const Duration(seconds: 2));
        labReady = resp.statusCode == 200;
        await resp.drain();
        client.close(force: true);
        if (labReady) break;
      } catch (_) {/* 還沒起 */}
    }
    if (!labReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('測試引擎啟動失敗——請確認模型已下載')));
      }
      return;
    }
    onPhase('快測 ${photos.length} 張（測試引擎描述中）');

    var hits = 0;
    var consecutiveFailures = 0; // [小葵 2026-09-29] 熔斷：llama 崩潤時不再傻等
    _lastQuickOkCount = 0;
    final perPhoto = <Map<String, dynamic>>[];
    for (var i = 0; i < photos.length; i++) {
      onProgress((i + 1) / photos.length);
      onPhase('快測中 ${i + 1}/${photos.length}：${_baseName(photos[i])}');
      final sw = Stopwatch()..start();
      final r = await _lab.describePhoto(labUrl, photos[i]);
      sw.stop();
      final ok = r['ok'] == true;
      if (!ok) {
        consecutiveFailures++;
        debugPrint('[ModelLab] 第 ${i + 1} 張失敗（連續 $consecutiveFailures）：${r['error']}');
        if (consecutiveFailures >= 2) {
          // 熔斷：連兩張失敗 = server 掛了，中止測試並保留已完成部分
          debugPrint('[ModelLab] 熔斷：本地模型 server 疑似崩潰，中止快測');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('本地模型 server 崩潰，快測中止（已完成部分已保留）')));
          }
          break;
        }
      } else {
        consecutiveFailures = 0;
        _lastQuickOkCount++;
      }
      // 判分用檔名線索（自動抽取無人工 hint）
      final hint = _hintsFromPath(photos[i]);
      final hit = ok && _lab.scoreDescription(r['desc'] as String? ?? '', hint);
      if (hit) hits++;
      perPhoto.add({
        'path': photos[i],
        'secs': sw.elapsedMilliseconds / 1000,
        'ok': ok,
        'hit': hit,
        'desc': (r['desc'] as String? ?? r['error'] as String? ?? '').substring(0, 150),
      });
    }

    // 產快測報告（無對照組——之後挑戰者模型下載後互跑才有對照）
    final report = ModelLabReport(
      id: 'quick_${DateTime.now().millisecondsSinceEpoch}',
      challengerName: '${_engineDisplayName(_engineModelId ?? '未知')}（快測基準）',
      incumbentName: '',
      createdAt: DateTime.now(),
      photoCount: photos.length,
      challengerHits: hits,
      incumbentHits: 0,
      challengerAvgSec: perPhoto.map((p) => p['secs'] as double).reduce((a, b) => a + b) / perPhoto.length,
      incumbentAvgSec: 0,
      recommendation: hits >= photos.length * 0.6 ? 'baseline-ok' : 'baseline-weak',
      oneLiner: '快測基準建立：測試引擎 ${photos.length} 張中命中 $hits 張。'
          '下載新模型後可以對照測試。',
      perPhoto: perPhoto,
    );
    await _lab.saveReport(report);
    // 關閉測試引擎（釋放 RAM）
    await LocalModelRuntimeService().stopLabServer();
    // UI 清理與報告刷新由 session._done() 統一處理（跨頁生存）
  }

  String _baseName(String p) => p.split('/').last;

  List<String> _hintsFromPath(String path) {
    // 從路徑抽線索詞（農場資料庫結構：/分類/日期_描述.jpg）
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final out = <String>[];
    // 檔名去附檔名、去日期前綴、切分隔符
    final fname = _baseName(path).replaceAll(RegExp(r'\.(jpg|jpeg|png|heic|webp)$', caseSensitive: false), '');
    fname.split(RegExp(r'[_\-]')).where((t) => t.isNotEmpty && !RegExp(r'^\d{4}').hasMatch(t)).forEach(out.add);
    // 上層資料夾名（分類）
    if (segments.length >= 2) out.add(segments[segments.length - 2]);
    return out.where((s) => s.length >= 2).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return BridgeCard(
      child: Padding(
        padding: const EdgeInsets.all(BridgeDS.spaceMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 標題列 ──
            Row(
              children: [
                Icon(Icons.science_outlined, color: colors.accentPurple, size: 16),
                const SizedBox(width: 8),
                SelectableText('模型實驗室',
                    style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
                const Spacer(),
                // Tab 切換
                _tabChip(0, '測試', Icons.play_arrow),
                const SizedBox(width: 6),
                _tabChip(1, '報告（${_reports.length}）', Icons.assessment_outlined),
              ],
            ),
            const SizedBox(height: BridgeDS.spaceMD),
            if (_tabIndex == 0) _buildTestTab(),
            if (_tabIndex == 1) _buildReportsTab(),
          ],
        ),
      ),
    );
  }

  Widget _tabChip(int idx, String label, IconData icon) {
    final colors = BridgeDSColors.of(context);
    final active = _tabIndex == idx;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? colors.accentPurple.withValues(alpha: 0.15) : colors.surfaceHover,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? colors.accentPurple : colors.borderDefault),
        ),
        child: Row(children: [
          Icon(icon, size: 12, color: active ? colors.accentPurple : colors.textMuted),
          const SizedBox(width: 4),
          Text(label, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
            color: active ? colors.accentPurple : colors.textMuted,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
        ]),
      ),
    );
  }

  /// 快測階段文字/進度回呼（session 呼叫）
  void onQuickTestPhase(String msg) {
    if (mounted) setState(() => _testPhase = msg);
  }

  void onQuickTestProgress(double v) {
    if (mounted) setState(() => _progress = v);
  }

  /// 快測結束回呼（session 呼叫——避免 protected setState 跨界）
  void onQuickTestDone() {
    if (!mounted) return;
    setState(() { _testing = false; _progress = 0; _testPhase = ''; });
    _loadReports();
    setState(() => _tabIndex = 1);
    // [grill 定案] 快測有希望 → 詢問是否全測 20 張（~35 分鐘）
    final okCount = _lastQuickOkCount;
    if (okCount >= 3) {
      Future.delayed(const Duration(milliseconds: 600), () => _askFullTest(okCount));
    }
  }

  int _lastQuickOkCount = 0;

  Future<void> _askFullTest(int okCount) async {
    if (!mounted) return;
    final colors = BridgeDSColors.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        title: Text('快測有希望（$okCount/5 成功）', style: TierStyle.of(context, Tier.dialogTitle).toTextStyle()),
        content: Text('要跑完整測試嗎？20 張照片，約 30-40 分鐘。'
            '測完會產出完整對照報告，作為日後換模型的基準。',
            style: TierStyle.of(context, Tier.dialogBody).toTextStyle()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('先不用')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.accentPurple),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('跑全測')),
        ],
      ),
    );
    if (go == true && mounted) {
      // TODO(全測): 20 張全測流程——素材抽 20 張+活動中心掛牌+B' 獨佔 GPU 復用
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('全測引擎下一版上線（快測已可用）')));
    }
  }

  Widget _engineChip((String, String) opt) {
    final colors = BridgeDSColors.of(context);
    final (id, label) = opt;
    final active = _engineModelId == id;
    // ignore: unnecessary_statements
    return GestureDetector(
      onTap: () => setState(() => _engineModelId = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? colors.accentPurple.withValues(alpha: 0.15) : colors.surfaceHover,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? colors.accentPurple : colors.borderDefault),
        ),
        child: Text(label, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
          color: active ? colors.accentPurple : colors.textMuted,
          fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
      ),
    );
  }

  Widget _buildTestTab() {
    final colors = BridgeDSColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          '用你自己的照片測試模型——就像換相機前先試拍一捲。'
          '快測 5 張（約 10 分鐘）建立基準，之後新模型下載後可對照。',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: BridgeDS.spaceMD),
        // [Blue 2026-09-29] 測試引擎=本機已下載模型（動態掃描）
        if (_engineOptions.isEmpty)
          SelectableText('測試引擎：尚未偵測到已下載的模型（先到上方下載模型）',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted))
        else
          Row(children: [
            SelectableText('測試引擎：', style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
            const SizedBox(width: 8),
            ..._engineOptions.map((opt) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _engineChip(opt),
            )),
          ]),
        const SizedBox(height: BridgeDS.spaceMD),
        if (_testing) ...[
          LinearProgressIndicator(value: _progress, backgroundColor: colors.surfaceHover, valueColor: AlwaysStoppedAnimation(colors.accentPurple)),
          const SizedBox(height: 8),
          SelectableText(_testPhase, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted)),
        ] else ...[
          Row(children: [
            _actionButton('開始快測（5 張）', Icons.flash_on, colors.accentPurple, _startQuickTest),
          ]),
        ],
        if (_pickedPhotos.isNotEmpty && !_testing) ...[
          const SizedBox(height: BridgeDS.spaceMD),
          SelectableText('上次抽取的照片：', style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
          ..._pickedPhotos.take(5).map((p) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Icon(Icons.photo_outlined, size: 12, color: colors.textMuted),
              const SizedBox(width: 6),
              Expanded(child: SelectableText(_baseName(p),
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted))),
            ]),
          )),
        ],
      ],
    );
  }

  Widget _buildReportsTab() {
    final colors = BridgeDSColors.of(context);
    if (_loading) return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
    if (_reports.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText('還沒有測試報告。先跑一次快測建立基準。',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted)),
      );
    }
    return Column(
      children: _reports.map((r) => _reportTile(r)).toList(),
    );
  }

  Widget _reportTile(ModelLabReport r) {
    final colors = BridgeDSColors.of(context);
    final acc = r.photoCount > 0 ? (r.challengerHits / r.photoCount * 100).round() : 0;
    final speed = r.challengerAvgSec > 0 ? '${r.challengerAvgSec.round()}s/張' : '—';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceHover,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.assessment_outlined, size: 14, color: colors.accentGreen),
            const SizedBox(width: 6),
            Expanded(child: SelectableText(r.challengerName,
                style: TierStyle.of(context, Tier.cardTitle).toTextStyle())),
            Text(_fmtDate(r.createdAt), style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted)),
          ]),
          const SizedBox(height: 6),
          SelectableText(r.oneLiner,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
          const SizedBox(height: 6),
          Row(children: [
            _statChip('命中率', '$acc%', colors.accentGreen),
            const SizedBox(width: 8),
            _statChip('速度', speed, colors.accentBlue),
            const Spacer(),
            _adoptButton(r, colors),
            if (r.challengerRamGb != null) ...[
              const SizedBox(width: 8),
              _statChip('RAM', '${r.challengerRamGb!.toStringAsFixed(1)}GB', colors.textMuted),
            ],
          ]),
        ],
      ),
    );
  }

  /// [金礦2] 採用測試引擎為現役——把快測引擎升格主生產線
  Widget _adoptButton(dynamic r, BridgeDSColors colors) {
    final name = (r.challengerName as String?) ?? '';
    final modelId = name.contains('12B') ? 'gemma-4-12b-q4'
        : name.contains('E4B') ? 'gemma-4-e4b-q4' : null;
    if (modelId == null) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () => _adoptEngine(modelId),
      icon: Icon(Icons.verified_outlined, size: 14, color: colors.accentPurple),
      label: Text('採用為現役', style: TierStyle.of(context, Tier.cardBody)
          .toTextStyle().copyWith(color: colors.accentPurple, fontSize: 12)),
    );
  }

  Future<void> _adoptEngine(String modelId) async {
    final runtime = LocalModelRuntimeService();
    await runtime.stopServer();
    await Future.delayed(const Duration(seconds: 2));
    await runtime.startServer(modelId: modelId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切換現役模型 → $modelId（18789）')));
    }
  }

  Widget _statChip(String label, String value, Color color) {
    final colors = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceHover,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Row(children: [
        Text('$label ', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted, fontSize: 11)),
        Text(value, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _actionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color),
        ),
        child: Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  String _fmtDate(DateTime d) => '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}


/// 快測會話——掛靜態欄位跨頁面生存，切頁不中斷（Blue 2026-09-29 抓包修復）
class _QuickTestSession {
  _ModelLabCardState? _ui;
  bool _running = false;
  bool _aborted = false;

  void attach(_ModelLabCardState ui) => _ui = ui;
  void detach() => _ui = null;

  void _phase(String msg) {
    final ui = _ui;
    if (ui != null && ui.mounted) ui.onQuickTestPhase(msg);
  }

  void _progress(double v) {
    final ui = _ui;
    if (ui != null && ui.mounted) ui.onQuickTestProgress(v);
  }

  void _done() {
    _running = false;
    final ui = _ui;
    if (ui != null && ui.mounted) {
      ui.onQuickTestDone();
    }
  }

  Future<void> run(_ModelLabCardState origin) async {
    if (_running) return;
    _running = true;
    _ui = origin;
    // 執行主體在 origin._runQuickTestBody（抽出來的純邏輯）
    await origin._runQuickTestBody(
      onPhase: _phase,
      onProgress: _progress,
      isAborted: () => _aborted,
    );
    _done();
  }
}
