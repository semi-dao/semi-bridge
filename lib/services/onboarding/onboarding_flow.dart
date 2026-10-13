// onboarding_flow.dart
// 安裝精靈 — 資料庫位置選擇 + 初始化
// [教練 Agent 2026-07-22] Phase 1 ③
//
// 首次啟動時引導使用者選擇向量資料庫存放位置。
// 預設建議外接碟授權根目錄（使用者 指定）。
// 選擇後透過 BrainDatabase.setCustomDbDirectory() 持久化。
//
// 執行順序：
// 1. 檢查是否已完成 onboarding（SharedPreferences 'onboarding_completed'）
// 2. 未完成 → 顯示安裝精靈
// 3. 完成 → BrainDatabase 使用已設定的路徑初始化

import 'dart:io';

import 'package:bridge_app/services/brain_container/brain_database.dart';
import 'package:bridge_app/services/vault/vault_service.dart';
import 'package:bridge_app/services/agent_loop/agent_knowledge_service.dart'; // [教練 Agent 2026-07-22] Phase E
import 'package:bridge_app/services/onboarding/folder_scanner_service.dart'; // [教練 Agent 2026-07-22] Phase H
import 'package:bridge_app/services/vector_db/asset_sandbox.dart'; // [教練 Agent 2026-07-25] 向量資料庫
import 'package:bridge_app/services/vector_db/asset_index_service.dart'; // [教練 Agent 2026-07-25] 向量資料庫索引
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';

/// 安裝精靈狀態
enum OnboardingStep {
  /// 尚未開始
  notStarted,

  /// 選擇資料庫位置
  selectDbPath,

  /// [教練 Agent 2026-08-21] 偵探式導入——選擇要導入的資料夾（可多選）
  pickImportFolders,

  /// 偵探掃描中（規則層，背景）
  detectiveScanning,

  /// 正在初始化
  initializing,

  /// 完成
  completed,

  /// 錯誤
  error,
}

/// 安裝精靈管理器
class OnboardingManager {
  static const String _onboardingCompletedKey = 'onboarding_completed';
  // [教練 Agent 2026-08-02] DB 搬到系統碟，不再用外接碟
  static const String _defaultDbPath = '';

  /// 檢查是否已完成安裝程序。
  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompletedKey) ?? false;
  }

  /// 標記安裝程序完成。
  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompletedKey, true);
  }

  /// 取得預設資料庫路徑。
  static String get defaultDbPath => _defaultDbPath;

  /// 檢查路徑是否可用（目錄存在且可寫）。
  static Future<bool> isPathAccessible(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        return false;
      }
      // 嘗試寫入測試檔案
      final testFile = File('$path/.bridge_write_test');
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 執行安裝程序：設定 DB 路徑 → 初始化資料庫 → 標記完成。
  ///
  /// [dbPath] 使用者選擇的資料庫目錄
  /// [onProgress] 進度回調（可選）
  static Future<bool> runOnboarding({
    required String dbPath,
    void Function(String message)? onProgress,
  }) async {
    try {
      onProgress?.call('正在設定資料庫位置...');

      // 1. 設定 DB 路徑
      await BrainDatabase.setCustomDbDirectory(dbPath);

      onProgress?.call('正在初始化資料庫...');

      // 2. 初始化 BrainDatabase（如果還沒初始化的話）
      if (!BrainDatabase.instance.isInitialized) {
        await BrainDatabase.instance.initialize();
      }

      // [教練 Agent 2026-07-22] Phase E — 預裝 Agent 知識庫腳本
      if (!AgentKnowledgeService.instance.isSeeded) {
        AgentKnowledgeService.instance.seedDefaultScripts();
      }

      onProgress?.call('正在啟動 Vault 服務...');

      // 3. 標記 VaultService 為已初始化
      VaultService.instance.markInitialized();

      // [教練 Agent 2026-07-25] 向量資料庫 — 把 dbPath 登記為向量資料庫資料夾並掃描
      // 注意：使用者之後可在設定頁或向量資料庫 tab 加入更多資料夾
      onProgress?.call('正在建立向量資料庫索引...');
      AssetSandbox().addFolder(dbPath);
      await AssetIndexService().fullScan(dbPath);
      debugPrint('[Onboarding] 向量資料庫已初始化 — 之後可在設定頁加入更多資料夾');

      onProgress?.call('安裝完成！');

      // 4. 標記 onboarding 完成
      await markCompleted();

      debugPrint('[Onboarding] 完成 — DB 路徑: $dbPath');

      // [教練 Agent 2026-07-22] Phase H — 非阻塞觸發 Phase 1 資料夾掃描
      // 掃描結果存到 SharedPreferences，夥伴建立後推理人格卡時取用
      _triggerBackgroundScan(dbPath);

      return true;
    } catch (e, st) {
      debugPrint('[Onboarding] 失敗: $e\n$st');
      onProgress?.call('安裝失敗：$e');
      return false;
    }
  }

  /// [教練 Agent 2026-07-22] Phase H — 非阻塞背景掃描
  ///
  /// 安裝完成後立即觸發 Phase 1 掃描，結果存到 SharedPreferences。
  /// 夥伴建立後 ChatController 觸發人格推理時可直接取用。
  static void _triggerBackgroundScan(String dbPath) {
    // 非阻塞——fire and forget
    FolderScannerService.instance.scanMetadata(dbPath).then((result) {
      debugPrint('[Onboarding] Phase 1 掃描完成: ${result.totalFiles} 檔案, ${result.fileTypes.length} 類型');
    }).catchError((e) {
      debugPrint('[Onboarding] Phase 1 掃描失敗: $e');
    });
  }

  /// 重置安裝程序（開發用——回到未完成狀態）。
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_onboardingCompletedKey);
    await BrainDatabase.clearCustomDbDirectory();
  }
}

/// 安裝精靈 Widget
///
/// 全螢幕對話框，引導使用者完成首次設定。
class OnboardingFlow extends StatefulWidget {
  final VoidCallback onCompleted;

  const OnboardingFlow({
    super.key,
    required this.onCompleted,
  });

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  OnboardingStep _step = OnboardingStep.selectDbPath;
  String _selectedPath = OnboardingManager.defaultDbPath;
  String _statusMessage = '';
  String _errorMessage = '';
  bool _pathValid = false;
  bool _checkingPath = false;

  // [教練 Agent 2026-08-21] 偵探式導入 state
  final List<String> _importFolders = [];
  String _scanningFolder = '';
  int _scannedFiles = 0;
  bool _scanSummaryReady = false;

  @override
  void initState() {
    super.initState();
    _checkPath(OnboardingManager.defaultDbPath);
  }

  Future<void> _checkPath(String path) async {
    setState(() {
      _checkingPath = true;
      _errorMessage = '';
    });

    final accessible = await OnboardingManager.isPathAccessible(path);

    setState(() {
      _pathValid = accessible;
      _checkingPath = false;
      if (!accessible) {
        _errorMessage = '此路徑無法存取或寫入，請選擇其他位置';
      }
    });
  }

  Future<void> _pickDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '選擇向量資料庫存放位置',
      initialDirectory: _selectedPath,
    );

    if (result != null) {
      setState(() {
        _selectedPath = result;
      });
      await _checkPath(result);
    }
  }

  Future<void> _startOnboarding() async {
    setState(() {
      _step = OnboardingStep.initializing;
      _statusMessage = '正在設定資料庫位置...';
    });

    final success = await OnboardingManager.runOnboarding(
      dbPath: _selectedPath,
      onProgress: (msg) {
        if (mounted) {
          setState(() => _statusMessage = msg);
        }
      },
    );

    if (mounted) {
      if (success) {
        // [教練 Agent 2026-08-21] 偵探式：初始化完成 → 選要導入的資料夾
        setState(() => _step = OnboardingStep.pickImportFolders);
      } else {
        setState(() {
          _step = OnboardingStep.error;
          _errorMessage = _statusMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(32),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    switch (_step) {
      case OnboardingStep.selectDbPath:
        return _buildPathSelection();
      case OnboardingStep.pickImportFolders:
        return _buildImportFolderPicker();
      case OnboardingStep.detectiveScanning:
        return _buildDetectiveScanning();
      case OnboardingStep.initializing:
        return _buildInitializing();
      case OnboardingStep.completed:
        return _buildCompleted();
      case OnboardingStep.error:
        return _buildError();
      default:
        return _buildPathSelection();
    }
  }

  // ── [教練 Agent 2026-08-21] 偵探式導入 ──────────────────────────────
  // 研究文件 RESEARCH_DETECTIVE_INGEST_FRAMEWORK.md §6.2 Phase 0：
  // 必填最少化（0.2 已完成）＋「稍後再說」永遠可選＋透明預估。

  Future<void> _pickImportFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '選擇要導入的資料夾（建議選你最混亂的，越亂偵探越準）',
    );
    if (result != null && !_importFolders.contains(result)) {
      setState(() => _importFolders.add(result));
    }
  }

  Future<void> _startDetectiveScan() async {
    setState(() => _step = OnboardingStep.detectiveScanning);

    final indexService = AssetIndexService();
    var totalFiles = 0;
    for (final folder in _importFolders) {
      if (!mounted) return;
      setState(() {
        _scanningFolder = folder;
        _statusMessage = '偵探掃描中：$folder';
      });
      try {
        final result = await indexService.fullScan(folder);
        totalFiles += result.totalFiles;
        if (!mounted) return;
        setState(() => _scannedFiles = totalFiles);
      } catch (e) {
        // 單一資料夾失敗不擋整體——誠實顯示但不中斷
        if (!mounted) return;
        setState(() => _statusMessage = '掃描 $folder 失敗（$e），繼續下一個...');
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }

    if (!mounted) return;
    setState(() {
      _scanSummaryReady = true;
      _statusMessage = '掃描完成';
      _step = OnboardingStep.completed;
    });
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) widget.onCompleted();
  }

  Widget _buildImportFolderPicker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.travel_explore,
                size: 32, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Text(
              '偵探式導入',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '選擇要讓偵探分析的資料夾（可多選）。\n'
          '建議選你最混亂的資料夾——越亂，偵探越準。\n'
          '掃描只讀檔名與 metadata，不會修改你的檔案。',
          style: TextStyle(height: 1.5),
        ),
        const SizedBox(height: 16),
        ..._importFolders.map(
          (f) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    f,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () =>
                      setState(() => _importFolders.remove(f)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _pickImportFolder,
              icon: const Icon(Icons.add),
              label: const Text('加入資料夾'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => widget.onCompleted(),
              child: const Text('稍後再說'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed:
                  _importFolders.isEmpty ? null : _startDetectiveScan,
              icon: const Icon(Icons.search),
              label: const Text('開始偵探掃描'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetectiveScanning() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        const Text('偵探正在翻閱你的資料夾...',
            style: TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        Text(
          _scanningFolder,
          style: const TextStyle(fontSize: 11),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          '已掃描 $_scannedFiles 個檔案',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '（背景執行，不影響其他工作）',
          style: TextStyle(fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildPathSelection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 標題
        Row(
          children: [
            Icon(Icons.rocket_launch,
                size: 32, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Text(
              '歡迎使用橋樑 App',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '讓我們設定你的第二大腦資料庫位置。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),

        // 路徑選擇卡片
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _pathValid
                  ? Colors.green.withValues(alpha: 0.3)
                  : Colors.red.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '資料庫位置',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedPath,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_open),
                    onPressed: _pickDirectory,
                    tooltip: '選擇資料夾',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 路徑狀態
              if (_checkingPath)
                Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('檢查路徑中...', style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
                  ],
                )
              else if (_pathValid)
                Row(
                  children: [
                    Icon(Icons.check_circle,
                        size: 16, color: BridgeDS.green700),
                    const SizedBox(width: 6),
                    Text('路徑可用',
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDS.green700)),
                  ],
                )
              else if (_errorMessage.isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 16, color: Colors.red.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_errorMessage,
                          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: Colors.red.shade600)),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 提示
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '資料庫檔案（brain_container.db）會存放在此目錄。'
                  '建議放在外接硬碟或穩定的儲存位置。'
                  '所有記憶、知識、標籤和向量索引都存在這裡。',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant,),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 按鈕
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: _pathValid ? _startOnboarding : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('開始使用'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInitializing() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(strokeWidth: 4),
        ),
        const SizedBox(height: 24),
        Text(
          _statusMessage,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCompleted() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        Icon(Icons.check_circle,
            size: 64, color: BridgeDS.green700),
        const SizedBox(height: 16),
        Text(
          '安裝完成！',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        // [小葵 2026-10-02] 自我喚醒提醒（Blue 案 10-01）：
        // 初始安裝就告知使用者有防崩潰自動重啟，以及關閉它的開關在哪裡。
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.health_and_safety,
                  size: 18, color: BridgeDS.green700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '小提醒：App 內建「自我喚醒」保護——萬一崩潰或被意外關閉，'
                  '會在 30 秒內自動重新啟動。若你希望關掉就真的關掉，'
                  '可到「系統設定 → 自我喚醒（防崩潰保護）」關閉。',
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.start,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        Icon(Icons.error_outline, size: 64, color: Colors.red.shade600),
        const SizedBox(height: 16),
        Text(
          '安裝失敗',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage,
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: Colors.red.shade600,),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            setState(() {
              _step = OnboardingStep.selectDbPath;
              _errorMessage = '';
            });
          },
          child: const Text('重試'),
        ),
      ],
    );
  }
}
