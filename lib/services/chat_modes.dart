// chat_modes.dart
// [聊天模式 B 線 2026-10-20 Blue 拍板] 側欄「模式」選擇器的資料層。
//
// 6 個聊天模式，選定後每輪對話自動注入該模式的紀律 prompt。
// 文案為 Blue 拍板固定版——改文案前先問。
// 設計 precedent：vault/vault_templates.dart 的 builtin templates。

import 'package:shared_preferences/shared_preferences.dart';

/// 單一聊天模式定義（資料不可變，文案拍板版）
class ChatMode {
  final String id;
  final String name;
  final String icon; // emoji
  final String tooltip; // 側欄 hover 說明
  final String?
      prompt; // 每輪注入的紀律 prompt；null = 不注入（自由對話）

  const ChatMode({
    required this.id,
    required this.name,
    required this.icon,
    required this.tooltip,
    this.prompt,
  });
}

/// 6 個內建模式（順序即側欄縱列順序，勿改文案）
const List<ChatMode> chatModes = [
  ChatMode(
    id: 'chat',
    name: '自由對話',
    icon: '💬',
    tooltip: '一般聊天問答，不掛特別紀律。想到什麼問什麼（此模式不注入任何 prompt，預設值）',
    // 自由對話：不注入任何 prompt（預設值）
  ),
  ChatMode(
    id: 'research',
    name: '查證研究',
    icon: '🔍',
    tooltip: '回答前先查證，附上來源。查不到會直說查不到，不硬掰',
    prompt: '回答前必須先用工具查證（web_search/web_extract/本地資料），'
        '每個關鍵宣稱附來源連結或檔案路徑。查不到就明說查不到，禁止憑印象編造。',
  ),
  ChatMode(
    id: 'engineering',
    name: '工程開發',
    icon: '🔧',
    tooltip: '動程式碼前先理解現況，改完附驗證證據，不交空頭支票',
    prompt: '動任何程式碼前先讀現況（grep/read 真實檔案），'
        '修改後必須實際執行驗證（跑測試/建置）並附實測輸出節錄。'
        '禁止只描述要做什麼而不動手。',
  ),
  ChatMode(
    id: 'debugging',
    name: '除錯偵探',
    icon: '🐛',
    tooltip: '先重現問題再追根因。修好要拿出證據，不貼「看起來好了」',
    prompt: '先重現問題（最小步驟），再追根因（從病徵回溯到第一個出錯點），'
        '修復後用重現步驟驗證已消除。禁止貼「應該好了」。',
  ),
  ChatMode(
    id: 'creative',
    name: '內容創作',
    icon: '✍️',
    tooltip: 'IG 貼文、文案、農場日記。有畫面感、有個性、不要官腔',
    prompt: '用指定角色/品牌的語氣創作。要有畫面感、有個性、口語自然。'
        '禁止官腔、禁止 AI 味贅詞（首先/總之/值得一提的是）。',
  ),
  ChatMode(
    id: 'autonomous',
    name: '自主長跑',
    icon: '🌙',
    tooltip: '交辦後放手跑長任務。過程留決策紀錄，回頭可以對帳',
    prompt: '此任務授權全自主執行，過程中每個關鍵決策記一筆'
        '（做了什麼選擇、為什麼），最後回報完整決策清單。'
        '可逆操作不問，不可逆（刪除/花錢/對外發送）先停。',
  ),
];

/// 依 id 找模式（找不到 fallback 回 chat＝自由對話）
ChatMode chatModeById(String id) {
  for (final m in chatModes) {
    if (m.id == id) return m;
  }
  return chatModes.first;
}

/// 模式選擇服務——單例，SharedPreferences 持久化（重啟保留）。
/// UI（bridge_desktop_screen 側欄）與注入方（chat_controller）都讀這裡。
class ChatModeService {
  ChatModeService._();
  static final ChatModeService instance = ChatModeService._();

  static const _prefKey = 'chat_mode_id';

  ChatMode _current = chatModes.first;

  /// 當前模式（未載入前＝預設自由對話）
  ChatMode get currentMode => _current;

  /// 當前模式要注入的 prompt（null = 不注入）
  String? get currentPrompt => _current.prompt;

  /// 啟動時載入上次選的模式（讀失敗 fallback 預設，不擋啟動）
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefKey);
      if (id != null && id.isNotEmpty) {
        _current = chatModeById(id);
      }
    } catch (_) {
      // fail-open：讀不到就維持預設
    }
  }

  /// 切換模式並持久化
  Future<void> setMode(String id) async {
    _current = chatModeById(id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, _current.id);
    } catch (_) {
      // 持久化失敗不擋切換（本 session 仍生效）
    }
  }
}
