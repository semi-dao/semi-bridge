// canvas_toolbar.dart
// F0 左側垂直工具列 — tldraw 風格圖示工具欄
// B2 Phase 1.5 Open Canvas 統一設計
//
// 設計文件: open-canvas-unified-design.md §3.0
//
// 職責：
// 1. 提供畫布操作工具切換（選取、新增節點、連線、標註）
// 2. 提供求救/匯入/匯出快捷入口
// 3. 以 activeTool enum 追蹤當前工具狀態

import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:flutter/material.dart';
import '../../theme/bridge_design_system.dart';

/// 畫布工具列可用工具。
enum CanvasTool {
  /// 選取/平移工具（預設）。
  select,

  /// 新增節點。
  addNode,

  /// 連線模式。
  connect,

  /// 標註（便利貼）。
  annotation,

  /// 塗鴉（手繪標注）。
  doodle,

  /// 截圖。
  screenshot,

  /// 匯入。
  import,

  /// 匯出。
  export,
}

/// 畫布左側垂直工具列（Column 1）。
///
/// tldraw 風格的極簡圖示工具欄，寬度約 48px。
/// 使用 [CanvasTool] enum 追蹤當前工具，點擊時觸發 [onToolChanged]
/// 及對應的回調。
///
/// 工具分組：
/// - 編輯工具：select, addNode, connect, annotation, screenshot
/// - 檔案工具：import, export（以分隔線區隔）
class CanvasToolbar extends StatefulWidget {
  /// 當前啟用的工具。
  final CanvasTool activeTool;

  /// 工具切換時呼叫，傳入新的 [CanvasTool]。
  final void Function(CanvasTool)? onToolChanged;

  /// 「新增節點」工具被選取時呼叫。
  final VoidCallback? onAddNode;

  /// 「連線模式」工具被選取時呼叫。
  final VoidCallback? onConnectMode;

  /// 「標註」工具被選取時呼叫。
  final VoidCallback? onAnnotation;

  /// 「塗鴉」工具被選取時呼叫。
  final VoidCallback? onDoodle;

  /// 「塗鴉圖層顯示/隱藏」切換時呼叫。
  final VoidCallback? onToggleDoodleVisible;

  /// 塗鴉圖層目前是否可見。
  final bool doodleVisible;

  /// 「截圖」工具被選取時呼叫。
  final VoidCallback? onScreenshot;

  /// 「匯入」工具被選取時呼叫。
  final VoidCallback? onImport;

  /// 「匯出」工具被選取時呼叫。
  final VoidCallback? onExport;

  /// [教練 Agent 2026-07-23] 「清空畫布」按鈕。
  final VoidCallback? onClear;

  /// [教練 Agent 2026-07-23] 恢復上一步。
  final VoidCallback? onUndo;

  /// [教練 Agent 2026-07-23] 恢復下一步。
  final VoidCallback? onRedo;

  /// [教練 Agent 2026-07-23] 是否可恢復上一步。
  final bool canUndo;

  /// [教練 Agent 2026-07-23] 是否可恢復下一步。
  final bool canRedo;

  /// [教練 Agent 2026-07-23] 可選的 Listenable — 讓 undo/redo 按鈕即時更新狀態
  final Listenable? listenable;

  const CanvasToolbar({
    super.key,
    required this.activeTool,
    this.onToolChanged,
    this.onAddNode,
    this.onConnectMode,
    this.onAnnotation,
    this.onDoodle,
    this.onToggleDoodleVisible,
    this.doodleVisible = true,
    this.onScreenshot,
    this.onImport,
    this.onExport,
    this.onClear,
    this.onUndo,
    this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.listenable,
  });

  @override
  State<CanvasToolbar> createState() => _CanvasToolbarState();
}

class _CanvasToolbarState extends State<CanvasToolbar> {
  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    // SemiCanvas 視覺 P1: Miro 風格半透明浮動工具列
    return Container(
      width: 60,  // [教練 Agent 2026-08-03] 配合按鈕升級 44x44
      margin: const EdgeInsets.only(top: 8, bottom: 8, left: 4),
      decoration: BoxDecoration(
        color: ds.surfaceElevated.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ds.borderSubtle.withValues(alpha: 0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: ds.canvas.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: BridgeDS.spaceSM),
          // ── [教練 Agent 2026-07-23] Undo / Redo — 最上方 ──
          if (widget.listenable != null)
            AnimatedBuilder(
              animation: widget.listenable!,
              builder: (context, _) {
                final ctrl = widget.listenable as dynamic;
                final canUndo = ctrl.canUndo as bool;
                final canRedo = ctrl.canRedo as bool;
                return Column(
                  children: [
                    _buildIconButton(
                      icon: Icons.undo,
                      tooltip: '上一步 (⌘Z)',
                      onTap: canUndo ? widget.onUndo : null,
                      enabled: canUndo,
                    ),
                    _buildIconButton(
                      icon: Icons.redo,
                      tooltip: '下一步 (⌘⇧Z)',
                      onTap: canRedo ? widget.onRedo : null,
                      enabled: canRedo,
                    ),
                  ],
                );
              },
            )
          else ...[
            _buildIconButton(
              icon: Icons.undo,
              tooltip: '上一步 (⌘Z)',
              onTap: widget.canUndo ? widget.onUndo : null,
              enabled: widget.canUndo,
            ),
            _buildIconButton(
              icon: Icons.redo,
              tooltip: '下一步 (⌘⇧Z)',
              onTap: widget.canRedo ? widget.onRedo : null,
              enabled: widget.canRedo,
            ),
          ],
          _buildDivider(),
          // ── 編輯工具組 ──
          _buildToolButton(
            tool: CanvasTool.select,
            icon: Icons.ads_click,
            tooltip: '選取 / 平移',
          ),
          _buildToolButton(
            tool: CanvasTool.addNode,
            icon: Icons.add_rounded,
            tooltip: '新增節點',
          ),
          _buildToolButton(
            tool: CanvasTool.doodle,
            icon: Icons.draw,
            tooltip: '塗鴉',
          ),
          // 塗鴉圖層顯示/隱藏
          Tooltip(
            message: widget.doodleVisible ? '隱藏塗鴉圖層' : '顯示塗鴉圖層',
            waitDuration: const Duration(milliseconds: 400),
            preferBelow: false,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onToggleDoodleVisible,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 44,  // [教練 Agent 2026-08-03] macOS HIG 最小點擊區
                  height: 44,
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.transparent, width: 1),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      hoverColor: BridgeDSColors.of(context).surfaceHover,
                      onTap: widget.onToggleDoodleVisible,
                      child: Icon(
                        widget.doodleVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 24,  // [教練 Agent 2026-08-03] iconHero
                        color: widget.doodleVisible
                            ? BridgeDSColors.of(context).textMuted
                            : BridgeDSColors.of(context).textMuted.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ── 分隔線 ──
          _buildDivider(),
          // ── 清空畫布 ──
          Tooltip(
            message: '清空畫布',
            waitDuration: const Duration(milliseconds: 400),
            preferBelow: false,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onClear,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 44,  // [教練 Agent 2026-08-03] macOS HIG 最小點擊區
                  height: 44,
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.transparent, width: 1),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      hoverColor: Colors.red.withValues(alpha: 0.1),
                      onTap: widget.onClear,
                      child: Icon(
                        Icons.cleaning_services_outlined,
                        size: 24,  // [教練 Agent 2026-08-03] iconHero
                        color: BridgeDSColors.of(context).textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ── 分隔線 ──
          _buildDivider(),
          // ── 檔案工具組 ──
          _buildToolButton(
            tool: CanvasTool.import,
            icon: Icons.file_download_outlined,
            tooltip: '匯入',
          ),
          _buildToolButton(
            tool: CanvasTool.export,
            icon: Icons.file_upload_outlined,
            tooltip: '匯出',
          ),
        ],
      ),
    );
  }

  /// 建構單一工具按鈕。
  ///
  /// 按鈕尺寸 36×36，hover 時顯示 [tooltip]，選中狀態以
  /// [BridgeDSColors.of(context).accentBlue] 背景標示。
  Widget _buildToolButton({
    required CanvasTool tool,
    required IconData icon,
    required String tooltip,
  }) {
    final isSelected = widget.activeTool == tool;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      preferBelow: false,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _handleToolTap(tool),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 36,
            height: 36,
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: isSelected
                  ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(
                      color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.5),
                      width: 1,
                    )
                  : Border.all(color: Colors.transparent, width: 1),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                hoverColor: BridgeDSColors.of(context).surfaceHover,
                onTap: () => _handleToolTap(tool),
                child: Icon(
                  icon,
                  size: 24,  // [教練 Agent 2026-08-03] iconHero token — 升一級（原 20）
                  color: isSelected
                      ? BridgeDSColors.of(context).accentBlue
                      : BridgeDSColors.of(context).textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 建構工具組之間的分隔線。
  Widget _buildDivider() {
    return Container(
      width: 28,
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: BridgeDSColors.of(context).borderSubtle,
    );
  }

  /// [教練 Agent 2026-07-23] 建構通用圖示按鈕（undo/redo 用，不帶 activeTool 狀態）
  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      preferBelow: false,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 36,
            height: 36,
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.transparent, width: 1),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                hoverColor: enabled ? BridgeDSColors.of(context).surfaceHover : Colors.transparent,
                onTap: onTap,
                child: Icon(
                  icon,
                  size: 24,  // [教練 Agent 2026-08-03] iconHero token
                  color: enabled
                      ? BridgeDSColors.of(context).textMuted
                      : BridgeDSColors.of(context).textMuted.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 處理工具點擊：先通知 [onToolChanged]，再觸發對應回調。
  void _handleToolTap(CanvasTool tool) {
    widget.onToolChanged?.call(tool);

    switch (tool) {
      case CanvasTool.select:
        // 選取工具無額外回調
        break;
      case CanvasTool.addNode:
        widget.onAddNode?.call();
        break;
      case CanvasTool.connect:
        widget.onConnectMode?.call();
        break;
      case CanvasTool.annotation:
        widget.onAnnotation?.call();
        break;
      case CanvasTool.doodle:
        widget.onDoodle?.call();
        break;
      case CanvasTool.screenshot:
        widget.onScreenshot?.call();
        break;
      case CanvasTool.import:
        widget.onImport?.call();
        break;
      case CanvasTool.export:
        widget.onExport?.call();
        break;
    }
  }
}
