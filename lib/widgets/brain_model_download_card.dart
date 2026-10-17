// brain_model_download_card.dart
// EmbeddingGemma 模型下載卡片 — 設定頁用
// 建立日期: 2026-07-03 by 教練 Agent (CEO)
// 修改日期: 2026-07-10 — 配色從 AppTheme 遷移至 BridgeDS（桌面深色主題）

import 'dart:async';

import 'package:flutter/material.dart';
import '../../services/brain_container/embedding/embedding_model_manager.dart';
import '../../services/brain_container/embedding/embedding_service.dart';
import '../../services/storage_service.dart';
import '../../services/vector_db/embedding_progress_tracker.dart';
import '../../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

class BrainModelDownloadCard extends StatefulWidget {
  final VoidCallback? onInstalled;

  const BrainModelDownloadCard({super.key, this.onInstalled});

  @override
  State<BrainModelDownloadCard> createState() =>
      _BrainModelDownloadCardState();
}

class _BrainModelDownloadCardState extends State<BrainModelDownloadCard> {
  final _hfTokenController = TextEditingController();
  bool _isLoading = true;
  bool _isInstalling = false;
  bool _modelInstalled = false;
  int _modelProgress = 0;
  int _tokenizerProgress = 0;
  String? _errorMessage;

  /// 監聽全域下載進度 Stream — 即使 Widget 重建也能接續進度
  StreamSubscription<ModelDownloadProgress>? _downloadSub;

  @override
  void initState() {
    super.initState();
    _loadState();
    _listenToDownloadProgress();
  }

  /// 監聽全域 tracker 的下載進度。
  ///
  /// 這樣即使使用者在下載中切換頁面再回來，
  /// Widget 重建後仍能顯示正確的下載進度。
  void _listenToDownloadProgress() {
    _downloadSub = EmbeddingProgressTracker.instance.downloadStream.listen((p) {
      if (!mounted) return;

      if (p.isDownloading || p.modelProgress > 0 || p.tokenizerProgress > 0) {
        setState(() {
          _isInstalling = p.isDownloading ||
              (p.modelProgress > 0 && p.modelProgress < 100);
          _modelProgress = p.modelProgress;
          _tokenizerProgress = p.tokenizerProgress;
        });
      }

      if (p.isCompleted) {
        setState(() {
          _isInstalling = false;
          _modelInstalled = true;
          _modelProgress = 100;
          _tokenizerProgress = 100;
        });
        widget.onInstalled?.call();
      }

      if (p.error != null) {
        setState(() {
          _isInstalling = false;
          _errorMessage = '下載失敗：${p.error}';
        });
      }
    });
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    _hfTokenController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final token = await StorageService.getHuggingFaceToken();
    if (token != null && token.isNotEmpty) {
      _hfTokenController.text = token;
    }
    _modelInstalled = EmbeddingModelManager.instance.isModelInstalled;

    // 恢復進行中的下載狀態（使用者切換頁面再回來時）
    final tracker = EmbeddingProgressTracker.instance;
    if (tracker.isDownloading) {
      _isInstalling = true;
      _modelProgress = tracker.currentDownload.modelProgress;
      _tokenizerProgress = tracker.currentDownload.tokenizerProgress;
    }

    _isLoading = false;
    if (mounted) setState(() {});
  }

  Future<void> _startInstall() async {
    final token = _hfTokenController.text.trim();

    if (token.isEmpty) {
      setState(() => _errorMessage = '需要 HuggingFace Token 才能下載此模型');
      return;
    }

    setState(() {
      _isInstalling = true;
      _errorMessage = null;
      _modelProgress = 0;
      _tokenizerProgress = 0;
    });

    try {
      await StorageService.saveHuggingFaceToken(token);

      await EmbeddingModelManager.instance.installModel(
        huggingFaceToken: token,
        onModelProgress: (p) {
          if (mounted) setState(() => _modelProgress = p);
        },
        onTokenizerProgress: (p) {
          if (mounted) setState(() => _tokenizerProgress = p);
        },
      );

      if (mounted) {
        setState(() {
          _isInstalling = false;
          _modelInstalled = true;
          _modelProgress = 100;
          _tokenizerProgress = 100;
        });
        // 通知父畫面刷新大腦容器狀態
        widget.onInstalled?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInstalling = false;
          _errorMessage = '下載失敗：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列
          Row(
            children: [
              Icon(
                _modelInstalled ? Icons.psychology : Icons.psychology_outlined,
                color: _modelInstalled ? BridgeDSColors.of(context).accentGreen : BridgeDSColors.of(context).textMuted,
                size: 24,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '大腦記憶模型',
                  style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                    color: BridgeDSColors.of(context).textPrimary,),
                ),
              ),
              _buildStatusChip(),
            ],
          ),
          SizedBox(height: 8),
          Builder(builder: (ctx) {
            // [Blue 報案 2026-10-16 二修] 現役主力是 EG2 時，這張 tflite 卡
            // 是備援身分——名稱與描述明確標示，不再冒充主力
            final isEg2Active = EmbeddingService.instance.activeModelVersion ==
                EmbeddingService.eg2ModelVersion;
            return Text(
              isEg2Active
                  ? '現役主力：EG2 嵌入引擎（18890，eg2-300m-v1）——'
                      '支援文字＋圖片語意搜尋。\n'
                      '離線備援：EmbeddingGemma 300M——EG2 不可用時自動接手，'
                      '裝置端推論，不需聯網。'
                  : '現役主力：EmbeddingGemma 300M——'
                      '讓夥伴的記憶從字串比對升級為語意理解。'
                      '模型在裝置上推論，不需聯網。',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                height: 1.4,),
            );
          }),
          SizedBox(height: 16),

          // 已安裝：顯示資訊
          if (_modelInstalled && !_isInstalling) ...[
            _buildInstalledInfo(),
          ]
          // 下載中：顯示進度
          else if (_isInstalling) ...[
            _buildDownloadProgress(),
          ]
          // 未安裝：顯示輸入欄 + 按鈕
          else ...[
            _buildInstallForm(),
          ],

          // 錯誤訊息
          if (_errorMessage != null) ...[
            SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).accentRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: BridgeDSColors.of(context).accentRed.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: BridgeDSColors.of(context).accentRed, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentRed,),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip() {
    if (_isInstalling) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '下載中',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentYellow,
            fontWeight: FontWeight.w600,),
        ),
      );
    }
    if (_modelInstalled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: BridgeDSColors.of(context).accentGreen, size: 14),
            SizedBox(width: 4),
            Text(
              '已安裝',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentGreen,
                fontWeight: FontWeight.w600,),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).textMuted.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '未安裝',
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
          fontWeight: FontWeight.w600,),
      ),
    );
  }

  Widget _buildInstalledInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: BridgeDSColors.of(context).accentGreen, size: 16),
            SizedBox(width: 8),
            Text(
              '模型已安裝，記憶系統使用真實語意搜尋。',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(
          '模型版本: ${EmbeddingService.instance.activeModelVersion}\n' /* [小葵 2026-10-16 審計修] 原寫死 300m 常數——EG2 上線時謊報；改真話 getter（EG2 優先） */
          '向量維度: ${EmbeddingService.vectorDimension} 維',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
            height: 1.4,),
        ),
      ],
    );
  }

  Widget _buildDownloadProgress() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 模型進度
        _buildProgressRow(
          label: '模型檔案',
          progress: _modelProgress,
          size: '~187 MB',
        ),
        SizedBox(height: 12),
        // Tokenizer 進度
        _buildProgressRow(
          label: '分詞器',
          progress: _tokenizerProgress,
          size: '~5 MB',
        ),
        SizedBox(height: 16),
        // 背景下載提示
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.sync,
                  color: BridgeDSColors.of(context).accentGreen, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '正在背景下載…，你可以切換到其他頁面。\n'
                  '下載會在背景繼續完成，回來時可查看進度。',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressRow({
    required String label,
    required int progress,
    required String size,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w500,
                  color: BridgeDSColors.of(context).textPrimary,),
              ),
            ),
            Text(
              size,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
            ),
          ],
        ),
        SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress / 100,
            minHeight: 8,
            backgroundColor: BridgeDSColors.of(context).surfaceHover,
            valueColor: AlwaysStoppedAnimation<Color>(BridgeDSColors.of(context).accentPurple),
          ),
        ),
        SizedBox(height: 4),
        Text(
          '$progress%',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
        ),
      ],
    );
  }

  Widget _buildInstallForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // HF Token 輸入
        Text(
          'HuggingFace Token',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w500,
            color: BridgeDSColors.of(context).textPrimary,),
        ),
        SizedBox(height: 4),
        Text(
          '此模型為 gated model，需要 HF 帳號接受授權後取得 token。\n'
          '前往 huggingface.co/settings/tokens 建立 token（權限選 Read）',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
            height: 1.4,),
        ),
        SizedBox(height: 8),
        TextField(
          controller: _hfTokenController,
          obscureText: true,
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
          decoration: InputDecoration(
            hintText: 'hf_xxx...xxxx',
            hintStyle: TextStyle(color: BridgeDSColors.of(context).textMuted),
            prefixIcon: Icon(Icons.key, size: 20, color: BridgeDSColors.of(context).textTertiary),
            filled: true,
            fillColor: BridgeDSColors.of(context).surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: BridgeDSColors.of(context).borderDefault),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: BridgeDSColors.of(context).borderDefault),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: BridgeDSColors.of(context).accentPurple),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
        SizedBox(height: 16),

        // 安裝按鈕
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _startInstall,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('下載並安裝模型'),
            style: FilledButton.styleFrom(
              backgroundColor: BridgeDSColors.of(context).accentPurple,
              foregroundColor: BridgeDSColors.of(context).textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          '模型大小約 192 MB，下載後離線使用。\n'
          '未安裝前記憶系統仍可運作（fallback 零向量模式）。',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
            height: 1.4,),
        ),
      ],
    );
  }
}
