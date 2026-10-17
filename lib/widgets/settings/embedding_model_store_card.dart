// embedding_model_store_card.dart
// [小葵 2026-10-16 Blue 令] 大腦記憶模型商店——像本地 LLM 一樣：可下載、可測試、可換主力。
// 取代 BrainModelDownloadCard 的單一模型視角（那張卡保留給 tflite 備援）。
//
// 四步 LOOP：
// ① 目錄（EmbeddingModelCatalogService.catalog——加條目 UI 自動長）
// ② 下載（GGUF → LocalRuntime/models/，續傳＋進度條）
// ③ 測試（臨時埠 18899 起引擎跑中文同義對檢索，不動 18890 主力）
// ④ 換主力（改 launchd plist → 重啟 18890 → 提示觸發全庫重嵌）

import 'dart:async';
import 'dart:io';

import '../../services/vector_db/eg2_reembed_service.dart';

import 'package:flutter/material.dart';

import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../../services/brain_container/embedding/embedding_model_catalog_service.dart';

class EmbeddingModelStoreCard extends StatefulWidget {
  const EmbeddingModelStoreCard({super.key});

  @override
  State<EmbeddingModelStoreCard> createState() =>
      _EmbeddingModelStoreCardState();
}

class _EmbeddingModelStoreCardState extends State<EmbeddingModelStoreCard> {
  final _svc = EmbeddingModelCatalogService.instance;

  // 下載狀態（entryId → 進度 0-1；-1=失敗）
  final Map<String, double> _downloading = {};
  // 測試結果（entryId → 詳情）
  final Map<String, String> _testResults = {};
  bool _testing = false;
  bool _switching = false;
  Timer? _refreshTimer;

  bool _isFetchingCatalog = false;
  bool _usingLiveCatalog = false; // 動態（HF 最新）還是靜態保底

  @override
  void initState() {
    super.initState();
    // 10 秒刷新現役模型顯示（換主力後 plist 生效）
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
    // [Blue 令 2026-10-16 四修] 商店=最新消息——每次 App 開拉 HF 動態目錄
    // （對應現役主力家族的最新替代品；24h 快取；離線 fallback 靜態）
    _svc.refreshFromHuggingFace().then((ok) {
      if (mounted) {
        setState(() {
          _usingLiveCatalog = ok;
          _isFetchingCatalog = false;
        });
      }
    });
    _isFetchingCatalog = true;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String? get _activeFile {
    final p = _svc.activeModelPath;
    return p?.split('/').last;
  }

  Future<void> _download(EmbeddingCatalogEntry e) async {
    setState(() => _downloading[e.id] = 0.0);
    final ok = await _svc.download(e, onProgress: (f) {
      if (mounted) setState(() => _downloading[e.id] = f);
    });
    if (mounted) {
      setState(() => _downloading.remove(e.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? '「${e.name}」下載完成——可以先測試，滿意再換主力'
            : '「${e.name}」下載失敗（可重試，支援續傳）'),
      ));
    }
  }

  Future<void> _test(EmbeddingCatalogEntry e) async {
    setState(() => _testing = true);
    final file = '${EmbeddingModelCatalogService.modelsDir}/${e.fileName}';
    final r = await _svc.quickTest(
        _svc.isDownloaded(e) ? file : null); // 沒下載就測現役
    if (mounted) {
      setState(() {
        _testing = false;
        _testResults[e.id] =
            '${r.ok ? "✓" : "✗"} ${r.detail}（${_svc.isDownloaded(e) ? e.quantization : "現役"}）';
      });
    }
  }

  Future<void> _switchPrimary(EmbeddingCatalogEntry e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('更換大腦記憶模型',
            style: TierStyle.of(ctx, Tier.cardHeroTitle).toTextStyle()),
        content: Text(
          '確定要把主力記憶模型換成「${e.name}」嗎？\n\n'
          '· 18890 嵌入服務會重啟（幾秒）\n'
          '· 向量血型改變 → 需要觸發全庫重嵌\n'
          '  （可從向量資料庫頁的模型管理觸發，背景跑）\n'
          '· 原模型檔保留，隨時可換回來',
          style: TierStyle.of(ctx, Tier.cardBody)
              .toTextStyle()
              .copyWith(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確認更換'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _switching = true);
    final ok = await _svc.switchPrimary(e);
    if (mounted) {
      setState(() => _switching = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('更換失敗（plist 寫入或服務重啟出錯）'),
        ));
        return;
      }
      // [審計修 2026-10-16 #11] 換主力成功→直接給「立即重嵌」動作鈕
      // （血型鐵則：換模型不重嵌＝搜尋品質默默劣化的隱形坑）
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 20),
        content: const Text('已換主力——18890 重啟中。新血型需全庫重嵌（421K 筆，背景跑）'),
        action: SnackBarAction(
          label: '立即重嵌',
          onPressed: () async {
            // 等 18890 起來（kickstart 非同步）再啟動
            for (var i = 0; i < 20; i++) {
              await Future<void>.delayed(const Duration(seconds: 2));
              try {
                final c = HttpClient();
                final r = await c.getUrl(Uri.parse('http://127.0.0.1:18890/health'));
                final resp = await r.close();
                await resp.drain();
                c.close();
                if (resp.statusCode == 200) break;
              } catch (_) {}
            }
            final n = await Eg2ReembedService.instance.start();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('全庫重嵌已啟動（$n 筆待重嵌）——可到向量資料庫頁看進度'),
              ));
            }
          },
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    final active = _activeFile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 標題列：現役模型 ──
        Row(
          children: [
            Icon(Icons.storefront_outlined, size: 15, color: colors.accentPurple),
            const SizedBox(width: 8),
            Text('記憶模型商店',
                style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _usingLiveCatalog
                    ? colors.accentBlue.withValues(alpha: 0.12)
                    : colors.textMuted.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _isFetchingCatalog
                    ? '目錄更新中…'
                    : (_usingLiveCatalog ? 'HF 最新' : '離線目錄'),
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(
                        color: _usingLiveCatalog
                            ? colors.accentBlue
                            : colors.textMuted),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.accentGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                active != null ? '現役：$active' : '現役：偵測中…',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: colors.accentGreen),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '像本地 LLM 一樣管理大腦記憶模型：下載 → 測試 → 換主力。模型日新月異，這裡跟著長。',
          style: TierStyle.of(context, Tier.cardCaption)
              .toTextStyle()
              .copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 12),
        // ── 目錄 ──
        ..._svc.catalog.map((e) => _buildEntry(e, active)),
      ],
    );
  }

  Widget _buildEntry(EmbeddingCatalogEntry e, String? activeFile) {
    final colors = BridgeDSColors.of(context);
    final downloaded = _svc.isDownloaded(e);
    final isActive = activeFile == e.fileName;
    final dlProgress = _downloading[e.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive
            ? colors.accentGreen.withValues(alpha: 0.06)
            : colors.surfaceHover.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive
              ? colors.accentGreen.withValues(alpha: 0.4)
              : colors.borderSubtle,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isActive ? Icons.verified : Icons.memory,
                size: 14,
                color: isActive ? colors.accentGreen : colors.accentBlue,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  e.name,
                  style: TierStyle.of(context, Tier.cardBody)
                      .toTextStyle()
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                  e.sizeMb > 0 ? '${e.sizeMb}MB · ${e.dims}維' : '${e.dims}維 · ${e.quantization}',
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: colors.textMuted)),
            ],
          ),
          const SizedBox(height: 4),
          Text(e.note,
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: colors.textMuted)),
          // 測試結果（有的話）
          if (_testResults[e.id] != null) ...[
            const SizedBox(height: 6),
            Text(_testResults[e.id]!,
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(
                        color: _testResults[e.id]!.startsWith('✓')
                            ? colors.accentGreen
                            : colors.accentRed)),
          ],
          // 下載進度條
          if (dlProgress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: dlProgress,
                minHeight: 4,
                backgroundColor: colors.borderSubtle,
                valueColor: AlwaysStoppedAnimation(colors.accentBlue),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (!downloaded)
                _actionChip(
                  label: dlProgress != null ? '下載中 ${(dlProgress * 100).toInt()}%' : '下載',
                  icon: Icons.download,
                  color: colors.accentBlue,
                  onTap: dlProgress != null ? null : () => _download(e),
                ),
              if (downloaded && !isActive) ...[
                _actionChip(
                  label: _testing ? '測試中…' : '測試',
                  icon: Icons.science_outlined,
                  color: colors.accentPurple,
                  onTap: _testing ? null : () => _test(e),
                ),
                const SizedBox(width: 8),
                _actionChip(
                  label: _switching ? '更換中…' : '設為主力',
                  icon: Icons.swap_horiz,
                  color: colors.accentGreen,
                  onTap: _switching ? null : () => _switchPrimary(e),
                ),
              ],
              if (isActive) ...[
                _actionChip(
                  label: _testing ? '測試中…' : '體檢現役',
                  icon: Icons.health_and_safety_outlined,
                  color: colors.accentGreen,
                  onTap: _testing ? null : () => _test(e),
                ),
                const SizedBox(width: 8),
                Text('現役主力 ✓',
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(color: colors.accentGreen)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionChip({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 13),
      label: Text(label,
          style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        backgroundColor: color.withValues(alpha: 0.1),
        foregroundColor: color,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
