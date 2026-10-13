// agent_safety.dart
// 安全邊界定義 — Track C 自主迴圈的安全護欄。
//
// 設計決策（使用者 2026-07-17 拍板）：
// - 確認機制 = 對話框非彈窗（Agent 在對話中說「我要執行 XX，確認嗎？」）
// - autoExecute 預設全 false（保守優先，破壞性操作必須問）
// - autoExecute = true 時，canvas_execute 不需確認（但仍受 prohibitedActions 約束）
// - 破壞性操作加紅色文字警告
//
// 安全層級：
//   1. prohibitedActions — 絕對禁止，無論任何設定都不能做
//   2. confirmationRequired — 需要使用者確認才能執行
//   3. autoExecute 例外 — 某些確認項可被 autoExecute 跳過
//
// [Phase 0 Track C 2026-07-17]

/// Agent 安全邊界約束
///
/// 定義原生 Agent 的行為邊界：
/// - 什麼動作絕對禁止（prohibitedActions）
/// - 什麼動作需要使用者確認（confirmationRequired）
/// - autoExecute 設定如何影響確認需求
///
/// 確認流程（對話框模式，非彈窗）：
/// 1. Agent 想執行需確認的動作
/// 2. Agent 在對話中說：「我要執行 XX，確認嗎？」
/// 3. 破壞性操作加紅色警告文字
/// 4. 使用者在對話中回覆確認/拒絕
/// 5. 確認 → 執行；拒絕 → 不執行
///
/// [Phase 0 Track C 2026-07-17]
class AgentSafetyConstraints {
  /// 禁止動作——無論任何設定都不得執行
  ///
  /// 這些是硬性邊界，Agent 連「詢問確認」都不行，直接拒絕。
  static const List<String> prohibitedActions = [
    '刪除使用者建立的節點', // 只能建議，不能刪
    '修改使用者輸入的內容', // 使用者輸入唯讀
    '存取 App 沙盒外的檔案', // sandbox 限制
    '發送網路請求到非白名單域名', // 網路限制
    '未經確認執行破壞性工作流', // 需確認，不能偷跑
  ];

  /// 需要確認的動作——Agent 必須先在對話中詢問使用者
  ///
  /// 這些動作可以執行，但必須先經過對話框確認流程。
  static const List<String> confirmationRequired = [
    'canvas_execute', // 執行工作流
    'canvas_remove', // 移除節點（實際工具名）
    'canvas_remove_node', // 向下相容
    'canvas_bulk_add_nodes', // 大量新增節點（>5 個）
    'canvas_clear_canvas', // 清空畫布
    'restart_app', // 重啟 App——會中斷所有正在進行的工作
    // [教練 Agent 2026-08-19] $33 止血——付費生成工具需使用者確認。
    // 根因：Agent Loop 可自行呼叫 generate_image 打 OpenAI（有 key 自動可用），
    // 單輪連發可燒數十美元。能力保留，花錢前必須問。
    'generate_image', // 圖片生成（每次呼叫都花 API 費用）
  ];

  /// [教練 Agent 2026-08-20] 付費生成工具——機器訊息（節點結果/畫布狀態）喚醒的
  /// 輪次一律禁止呼叫。根因：工作流每個節點結果都會喚醒 Agent Loop，
  /// LLM 看到「圖片生成、波西米亞」等字眼自行推論該生圖 → 單輪連發
  /// 燒數十美元的無用圖。花錢的授權只能來自使用者的親自發言，
  /// 機器訊息輪次連「提出」都不行（跳確認框也是一種 UI 噪音）。
  static const List<String> paidGenerativeTools = [
    'generate_image', // OpenAI 生圖
    // [教練 Agent 2026-08-21] $33 根治——canvas_execute 一張確認可觸發
    // N 個 imageGen/videoGen/musicGen 節點，機器輪次一律禁用
    'canvas_execute',
    // 未來 videoGen / musicGen 等付費生成工具加入這裡
  ];

  /// 需要紅色警告的破壞性動作
  ///
  /// 這些動作在確認對話中需附加紅色警告文字，提醒使用者後果嚴重。
  static const List<String> destructiveActions = [
    'canvas_execute', // 執行工作流可能有副作用
    'canvas_remove', // 刪除節點是不可逆的（實際工具名）
    'canvas_remove_node', // 向下相容
    'canvas_clear_canvas', // 清空畫布是不可逆的
    'restart_app', // 重啟會中斷所有工作
  ];

  /// [Pi Durable 借鑑 2026-10-03] 中斷安全工具——跑兩次 = 跑一次的唯讀操作。
  ///
  /// 判準：這個工具執行兩次，結果跟執行一次一樣嗎？
  /// - 是（唯讀、無副作用）→ interrupt-safe：崩潰/中斷後可自動重跑，不構成傷害
  /// - 否（有副作用）→ 不在此列：中斷後只回報「被中斷」，交給模型決策
  ///
  /// 用途：Agent Loop 崩潰恢復時的重跑決策；D002 確認框可據此降低打擾。
  /// 詳見 skill: pi-durable-borrowing-guide §①
  static const Set<String> interruptSafeTools = {
    'read_source_file', // 唯讀：讀原始碼
    'read_app_log', // 唯讀：讀 App 日誌
    'ui_get_state', // 唯讀：查 UI 狀態
    'ui_inspect', // 唯讀：檢視元件
    'memory_search', // 唯讀：搜記憶
    'compass_seek', // 唯讀：查羅盤
    'compass_read', // 唯讀：讀羅盤卡
    'web_search', // 唯讀：網搜（冪等）
    'image_recognition', // 唯讀：辨識（不改變被辨識物）
    'canvas_capture', // 唯讀：截圖畫布狀態
  };

  /// [Pi Durable 借鑑 2026-10-03] 判斷工具是否中斷安全（重跑無害）
  static bool isInterruptSafe(String toolName) {
    return interruptSafeTools.contains(toolName);
  }

  /// run_terminal 裡需要確認的危險命令模式
  ///
  /// 當 Agent 透過 run_terminal 執行包含這些模式的命令時，
  /// 需要先經過確認。
  static const List<String> dangerousTerminalPatterns = [
    'git stash', // 會丟失工作進度
    'git reset', // 會丟失 commit
    'git checkout', // 切換分支可能丟失變更
    'git clean', // 刪除未追蹤檔案
    'rm -rf', // 遞迴刪除
    'rm -r', // 遞迴刪除
    'flutter clean', // 清除建置快取
    'killall', // 殺進程
    'pkill', // 殺進程
    'shutdown', // 關機
    'reboot', // 重啟系統
  ];

  /// 判斷動作是否被禁止
  ///
  /// 回傳 true 表示 Agent 絕對不能執行此動作。
  static bool isProhibited(String action) {
    return prohibitedActions.any((p) => action.contains(p)) ||
        prohibitedActions.contains(action);
  }

  /// 判斷動作是否需要確認
  ///
  /// [action] — 動作名稱（如 canvas_execute、canvas_remove_node）
  /// [autoExecute] — 是否啟用自動執行（預設 false）
  ///
  /// 規則：
  /// - 禁止動作 → 永遠回傳 true（間接阻止，呼叫端應先檢查 isProhibited）
  /// - canvas_execute + autoExecute=true → 不需確認
  /// - 其他 confirmationRequired 動作 → 一律需確認
  static bool needsConfirmation(String action, {bool autoExecute = false}) {
    // 禁止動作不需要「確認」——直接不能做
    if (isProhibited(action)) return true;

    // autoExecute 例外：canvas_execute 可跳過確認
    if (action == 'canvas_execute' && autoExecute) {
      return false;
    }

    // 其他確認清單中的動作，一律需確認
    return confirmationRequired.contains(action);
  }

  /// 判斷動作是否為破壞性（需紅色警告）
  static bool isDestructive(String action) {
    return destructiveActions.contains(action);
  }

  /// [D002 擴充 2026-08-09] 判斷 terminal 命令是否危險
  ///
  /// 檢查 run_terminal 的命令字串是否包含危險模式。
  /// 回傳 true → 需要確認才能執行。
  static bool isDangerousTerminalCommand(String command) {
    final lower = command.toLowerCase();
    return dangerousTerminalPatterns.any((p) => lower.contains(p));
  }

  /// [D002 擴充 2026-08-09] 統一判斷工具呼叫是否需要確認
  ///
  /// 覆蓋所有工具：canvas 操作 + restart_app + run_terminal 危險命令
  static bool needsToolConfirmation(String toolName, Map<String, dynamic> args) {
    // 1. 已知需確認的工具
    if (needsConfirmation(toolName)) return true;

    // 2. run_terminal 裡的危險命令
    if (toolName == 'run_terminal' || toolName == 'terminal') {
      final command = args['command'] as String? ?? '';
      if (isDangerousTerminalCommand(command)) return true;
    }

    return false;
  }

  /// [D002 擴充 2026-08-09] 統一判斷工具呼叫是否為破壞性
  static bool isToolDestructive(String toolName, Map<String, dynamic> args) {
    if (isDestructive(toolName)) return true;

    if (toolName == 'run_terminal' || toolName == 'terminal') {
      final command = args['command'] as String? ?? '';
      if (isDangerousTerminalCommand(command)) return true;
    }

    return false;
  }

  /// 產生確認對話訊息
  ///
  /// Agent 在對話中發送此訊息，等待使用者回覆。
  /// 破壞性操作自動附加紅色警告。
  ///
  /// 回傳格式：
  /// - 一般確認：「我要執行 [動作描述]，確認嗎？」
  /// - 破壞性確認：同上 + 紅色警告行
  static String buildConfirmationMessage(
    String action, {
    String? description,
  }) {
    final desc = description ?? action;
    final buffer = StringBuffer('我要執行「$desc」，確認嗎？');

    if (isDestructive(action)) {
      // 破壞性操作加紅色警告
      // 注意：實際紅色渲染由 UI 層處理，這裡用標記包裹
      buffer.writeln();
      buffer.write('⚠️ 注意：此操作可能造成不可逆的變更，請確認後再執行。');
    }

    return buffer.toString();
  }

  /// 產生禁止動作的拒絕訊息
  ///
  /// 當 Agent 嘗試執行禁止動作時，回傳此訊息說明為何不能做。
  static String buildProhibitedMessage(String action) {
    return '抱歉，「$action」是安全邊界禁止的動作，我無法執行。'
        '如果你需要完成這件事，請自己手動操作。';
  }
}
