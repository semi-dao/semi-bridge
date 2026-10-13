// Quick Assistant Context — Cmd+K 隨身小幫手的完整裝備
//
// [教練 Agent 2026-08-03] Phase 1
//
// 設計理念：
// - Cmd+K 開啟的簡易對話框不是普通對話
// - Agent 出動時已自帶完整裝備：
//   📖 橋樑完整說明書
//   🔧 自我修復 skill（diagnose-bugs）— 紀律化除錯
//   📸 當前頁面 App 自拍
//   🔑 缺失金鑰 → 改用後台監看/操控
//   🗺️ 全 App 導航地圖
//
// 當 context 非空時：
// 1. AgentLoopPromptBuilder 自動注入「除 bug Agent」system prompt
// 2. sendMessage 送出前自動截 App 自拍並附加到訊息
// 3. LLM 看到裝備齊全的提示 → 自動切換到「除 bug 人格」

import 'dart:io';

/// Quick Assistant 上下文
///
/// 當 Cmd+K 開啟時建立，關閉時清空。
/// Agent 透過這個 context 知道「這是除 bug 對話」並切換人格。
class QuickAssistantContext {
  /// 當前頁面名稱（'chat', 'canvas', 'project', 'brain', 'vault', 'system' 等）
  final String currentPage;

  /// 當前頁面的詳細路徑（sub-page，如 'system/settings'）
  final String currentSubPage;

  /// 當前 App 自拍（截圖檔案路徑）
  /// null 表示還沒截圖或截圖失敗
  File? appScreenshot;

  /// 截圖時間
  DateTime? screenshotAt;

  /// 是否自動開啟時截圖（如果 true，每次送出都會重新截）
  final bool autoScreenshot;

  /// 開啟時間
  final DateTime openedAt;

  /// App 診斷資訊（版本、路徑、OS 等）
  final Map<String, String> appDiagnostics;

  /// 使用者提問歷史（context）
  final List<String> conversationContext;

  /// [無限插槽 2026-10-06] 本次對話聚焦的插槽（grill-me 用）——
  /// 非空時 system prompt 注入「插槽面試官」人格：介紹專案→問需求→
  /// 建議權限燈號，並壓掉任務收工協議（對話不是任務）。
  final String? slotRepoUrl;
  final String? slotLabel;

  QuickAssistantContext({
    required this.currentPage,
    this.currentSubPage = '',
    this.appScreenshot,
    this.screenshotAt,
    this.autoScreenshot = true,
    DateTime? openedAt,
    Map<String, String>? appDiagnostics,
    List<String>? conversationContext,
    this.slotRepoUrl,
    this.slotLabel,
  })  : openedAt = openedAt ?? DateTime.now(),
        appDiagnostics = appDiagnostics ?? {},
        conversationContext = conversationContext ?? [];

  /// 截圖是否過期（超過 30 秒視為過期，需要重新截）
  bool get isScreenshotStale {
    if (screenshotAt == null) return true;
    return DateTime.now().difference(screenshotAt!).inSeconds > 30;
  }

  /// 完整描述（給 LLM 看）
  Map<String, dynamic> toMap() {
    return {
      'currentPage': currentPage,
      'currentSubPage': currentSubPage,
      'appScreenshot': appScreenshot?.path,
      'screenshotAt': screenshotAt?.toIso8601String(),
      'autoScreenshot': autoScreenshot,
      'openedAt': openedAt.toIso8601String(),
      'appDiagnostics': appDiagnostics,
      'conversationContext': conversationContext,
    };
  }

  QuickAssistantContext copyWith({
    String? currentPage,
    String? currentSubPage,
    File? appScreenshot,
    DateTime? screenshotAt,
    bool? autoScreenshot,
    Map<String, String>? appDiagnostics,
    List<String>? conversationContext,
  }) {
    return QuickAssistantContext(
      currentPage: currentPage ?? this.currentPage,
      currentSubPage: currentSubPage ?? this.currentSubPage,
      appScreenshot: appScreenshot ?? this.appScreenshot,
      screenshotAt: screenshotAt ?? this.screenshotAt,
      autoScreenshot: autoScreenshot ?? this.autoScreenshot,
      openedAt: openedAt,
      appDiagnostics: appDiagnostics ?? this.appDiagnostics,
      conversationContext: conversationContext ?? this.conversationContext,
    );
  }
}
