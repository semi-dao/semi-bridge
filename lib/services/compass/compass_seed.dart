// compass_seed.dart
// 羅盤首播種子 — 器官清單（源自 APP_ARCHITECTURE_MAP.md 快速導航）
// + 第一批規則卡（源自 docs/specs/galaxy-light-rules.md 燈光規則）。
// [小葵 2026-09-07] 2D 圖譜正式退役——brain.graph2d 器官與
//   simGate/veinEdge/xrefEdge 三條 2D 邊規則卡已移除。
//
// 種子只負責「註冊」，冪等（INSERT OR IGNORE）；事實層細節
// （行號、健康狀態）由 CompassHarvestService 持續更新。

import 'compass_models.dart';
import 'compass_store.dart';

/// 首播器官清單（v1：screen/service 級，~30 個）
const seedOrgans = <CompassOrgan>[
  // ── 對話 ──
  CompassOrgan(id: 'chat', systemGroup: '對話', name: '對話主畫面'),
  CompassOrgan(id: 'chat.controller', systemGroup: '對話', name: '對話控制器'),
  CompassOrgan(id: 'voice.input', systemGroup: '對話', name: '語音輸入'),
  CompassOrgan(id: 'voice.tts', systemGroup: '對話', name: '語音合成 TTS'),
  // ── 畫布 ──
  CompassOrgan(id: 'canvas.engine', systemGroup: '畫布', name: 'V2 畫布引擎'),
  CompassOrgan(id: 'canvas.chat', systemGroup: '畫布', name: '畫布聊天面板'),
  CompassOrgan(id: 'canvas.inspector', systemGroup: '畫布', name: '工作流體檢'),
  CompassOrgan(id: 'canvas.templates', systemGroup: '畫布', name: '工作流範本'),
  // ── 大腦 ──
  CompassOrgan(id: 'brain.galaxy3d', systemGroup: '大腦', name: '大腦圖譜 3D 星系'),
  CompassOrgan(id: 'brain.container', systemGroup: '大腦', name: '大腦容器（向量記憶）'),
  CompassOrgan(id: 'brain.ingest', systemGroup: '大腦', name: '資產導入 autoIngest'),
  CompassOrgan(id: 'brain.embed', systemGroup: '大腦', name: '嵌入管線'),
  // ── 向量 ──
  CompassOrgan(id: 'vault', systemGroup: '向量', name: '向量資料庫頁'),
  CompassOrgan(id: 'vault.graphrag', systemGroup: '向量', name: 'GraphRAG'),
  // ── 專案 ──
  CompassOrgan(id: 'project.door', systemGroup: '專案', name: '專案門'),
  CompassOrgan(id: 'project.kanban', systemGroup: '專案', name: '專案看板'),
  CompassOrgan(id: 'project.relation', systemGroup: '專案', name: '專案關係圖'),
  // ── 夥伴 ──
  CompassOrgan(id: 'companion.hall', systemGroup: '夥伴', name: '夥伴大廳'),
  CompassOrgan(id: 'companion.summon', systemGroup: '夥伴', name: '召喚引擎'),
  CompassOrgan(id: 'companion.control', systemGroup: '夥伴', name: '夥伴控制中心'),
  CompassOrgan(id: 'companion.floating', systemGroup: '夥伴', name: '懸浮夥伴視窗'),
  // ── 服務群 ──
  CompassOrgan(id: 'agent.loop', systemGroup: '服務群', name: 'Agent Loop'),
  CompassOrgan(id: 'agent.tools', systemGroup: '服務群', name: 'Agent 工具註冊'),
  CompassOrgan(id: 'agent.mcp', systemGroup: '服務群', name: 'MCP Server'),
  // ── 肢體：示範錄製 ──
  // [Blue 令 2026-09-12] 全電腦示範錄製是獨立器官——「很重要的器官跟肢體」。
  // 涵蓋：畫布內錄製（RoutineRecorder）+ 全電腦錄製（SystemRoutineRecorder）
  CompassOrgan(id: 'routine.record', systemGroup: '肢體', name: '示範錄製（全電腦）'),
  CompassOrgan(id: 'routine.replay', systemGroup: '肢體', name: '示範重播（Agent 代操作）'),

  // ── 協作系統：Buzz/Grok Bot 參考應用統一歸類 ──
  // [Blue 命令 2026-09-12] 正式命名「協作系統」——蜂群/小隊/單兵聯合作戰
  // 共享戰果的完整體系。新器官動到這些環節前必讀 collab.operatingModel。
  CompassOrgan(id: 'collab.system', systemGroup: '協作系統', name: '協作系統總覽'),
  CompassOrgan(id: 'collab.dispatch', systemGroup: '協作系統', name: '任務派工（隊友訊息流）'),
  CompassOrgan(id: 'collab.delegate', systemGroup: '協作系統', name: '分身戰術（delegate 工具）'),
  CompassOrgan(id: 'collab.room', systemGroup: '協作系統', name: '房間共居（任務卡四象限）'),
  CompassOrgan(id: 'collab.ledger', systemGroup: '協作系統', name: '戰果共享（工作真相帳本）'),
  CompassOrgan(id: 'agent.budget', systemGroup: '服務群', name: '預算帳本與付費閘門'),
  CompassOrgan(id: 'system.activity', systemGroup: '服務群', name: '系統活動中心'),
  CompassOrgan(id: 'system.fingerprint', systemGroup: '服務群', name: '樹指紋快取（重啟不重掃）'),
  CompassOrgan(id: 'runtime.autorevive', systemGroup: '服務群', name: '大腦自動復活（引擎級看門狗）'),
  CompassOrgan(id: 'scan.fastfingerprint', systemGroup: '服務群', name: '快指紋嵌入過濾（hash 前零讀檔）'),
  CompassOrgan(id: 'oss.harvest', systemGroup: '服務群', name: '七金礦開源收穫（semi-bridge 上傳）'),
  CompassOrgan(id: 'local.engine', systemGroup: '服務群', name: '本地模型引擎 (18789)'),
  CompassOrgan(id: 'local.kokoro', systemGroup: '服務群', name: 'Kokoro TTS (18900)'),
  // [小葵 2026-09-29] 新器官：模型實驗室（Blue 願景——選型閉環產品化）
  CompassOrgan(id: 'model.lab', systemGroup: '服務群', name: '模型實驗室（選型閉環）'),
  CompassOrgan(id: 'memory', systemGroup: '服務群', name: '長期記憶系統'),
  // [小葵 2026-10-05 Blue 令] 生命樹入羅盤器官地圖——夢境/歷史樹/反思樹的家
  CompassOrgan(id: 'life_tree', systemGroup: '服務群', name: '生命樹（夢·戰役·遺憾）'),
  CompassOrgan(id: 'schedule', systemGroup: '服務群', name: '排程引擎'),
  // ── 系統/外觀 ──
  CompassOrgan(id: 'theme', systemGroup: '外觀', name: '設計系統與主題'),
  CompassOrgan(id: 'goldenkeys', systemGroup: '系統', name: '金鑰匙系統'),
  CompassOrgan(id: 'semidao', systemGroup: '系統', name: 'SemiDAO 審查'),
  CompassOrgan(id: 'computeruse', systemGroup: '系統', name: 'Computer Use 接管閘門'),
];

/// 首播規則卡（第一批：2D 圖譜邊規則 + 3D 星系燈光規則）
/// 參數現值 = 程式碼裡的 hardcode 常數（種子化的當下忠實記錄）。
final _seedTime = DateTime(2026, 9, 6);

final seedRules = <CompassRule>[
  // ── 3D 星系（galaxy.html + galaxy-light-rules.md）──
  CompassRule(
    id: 'galaxy.lightAuthority',
    organId: 'brain.galaxy3d',
    description: '燈光權威中心：hub 光球亮度 = 基準 × 模式係數 × 距離衰減 × 設定倍率',
    why: 'v284 Blue 規則令「建立規則讓規則運行，不要單點改來改去」——'
        '五個舊寫手互蓋造成全景閃屏；唯一寫手 lightAuthority(t) 每幀結算。',
    params: {
      'modeCoef.galaxy': 1.0,
      // river = 名次誕生時序（房間按真實時間出現）
      // pulse = riverHub 壓暗
    },
    kind: CompassRuleKind.visual,
    updatedBy: 'auto:harvest',
    updatedAt: _seedTime,
  ),
];

// [三步長肉 Step 2 · 小葵 2026-09-07] 從 code 常數提煉的真實規則——
// 每條都是實測校準過的治理點，收編進羅盤統一管理。
final distilledRules = <CompassRule>[
  CompassRule(
    id: 'brain.xrefThreshold',
    organId: 'brain.container',
    description: '記憶↔檔案自動關聯的相似度門檻',
    why: '08-21 重嵌後 230 條記憶全量實測：真匹配 0.55-0.69、噪音頂 0.35；'
        '0.75 是假向量時代的舊值會全擋，0.50 是實測安全下限。',
    params: {'threshold': 0.50},
    kind: CompassRuleKind.behavioral,
    updatedBy: 'auto:harvest',
    updatedAt: _seedTime,
  ),
  CompassRule(
    id: 'galaxy.screensaverIdle',
    organId: 'brain.galaxy3d',
    description: '星系保護模式：閒置幾分鐘後接管畫面',
    why: '09-01 Blue 拍板 A 路線——App 開著就接管待機畫面；3 分鐘是防止'
        '操作中被接管、又能及時保護螢幕的平衡值。',
    params: {'idleMinutes': 3},
    kind: CompassRuleKind.behavioral,
    updatedBy: 'auto:harvest',
    updatedAt: _seedTime,
  ),
  // [小葵 2026-09-25 星系全貌令] Blue：「經歷搜尋跟看懂全貌的過程，
  // 羅盤該寫什麼讓未來 App Agent 對星系系統更快了解？」——把散在
  // code 註解裡的系統知識收編成規則，下次 agent 不用重新考古。
  CompassRule(
    id: 'galaxy.architectureMap',
    organId: 'brain.galaxy3d',
    description: '星系檔案地圖：改什麼去哪改',
    why: 'galaxy.html 是 3600 行單檔（three.js 場景+音效+參數+UI 全在裡面），'
        '沒地圖的 agent 會在單檔裡迷航。容器=galaxy_webview.dart'
        '（InAppWebView+FPS 監控+自動重載）；參數 API=/galaxy_params'
        '（MCP 8420，POST 持久化 galaxy_params.json）；羅盤↔星系橋='
        'compass_galaxy_bridge.dart。',
    params: {
      'galaxy.html': 'assets/galaxy/（唯一真相源）',
      'container': 'lib/widgets/brain/galaxy_webview.dart',
      'paramsApi': 'GET/POST /galaxy_params → galaxy_params.json',
      'rebuildTrap': '改 html 後必須 rebuild（assets 打包）＋cb=時間戳破 WKWebView 快取',
    },
    kind: CompassRuleKind.visual,
    updatedBy: 'xiaokui:galaxy-full-picture',
    updatedAt: DateTime(2026, 9, 25),
  ),
  CompassRule(
    id: 'galaxy.hoverBridge',
    organId: 'brain.galaxy3d',
    description: 'hover/撥弦事件鏈：WKWebView 不轉發純移動事件的補洞工程',
    why: 'WKWebView 收不到「滑鼠移動但沒按」的事件——CSS :hover 與 JS '
        'mousemove 在 App 內全死。解法：Dart MouseRegion 收事件→注入 '
        '__flutterHover(x,y) 手動開關 tooltip。另一坑：滑鼠靜止後 macOS '
        '把 key focus 收回 Flutter 層→hasFocus()=false→頁面誤判使用者'
        '離開→撥弦靜音（Blue 2026-09-25 實測）。解法：滑鼠在 webview 內'
        '時 Dart 每 500ms 戳 __appHoverAlive 心跳，頁面端心跳<2s 新鮮=活躍。',
    params: {
      'injectFn': '__flutterHover(x,y) 同步更新 mouse NDC',
      'heartbeat': '__appHoverAlive 500ms（Dart onEnter 啟/onExit 停）',
      'uiActiveRule': '心跳新鮮 OR hasFocus——不再一票否決',
      'rcActiveRule': '心跳新鮮=拾取不休眠（自轉弦掃過靜止鼠標也要響）',
    },
    kind: CompassRuleKind.visual,
    updatedBy: 'xiaokui:static-pluck-decree',
    updatedAt: DateTime(2026, 9, 25),
  ),
  CompassRule(
    id: 'galaxy.audioPhysics',
    organId: 'brain.galaxy3d',
    description: '星系音效物理：撥弦=弦長反比頻率、星音=副檔名五聲音階',
    why: '弦是星（作品）與記憶球的縫線。撥弦頻率 f∝1/L（鋼琴物理）：全場'
        '弦長 5~95 百分位映射 freqLo~freqHi（對數）；星 hover 音=副檔名'
        '決定音高家族（code=最高音 C6、文檔 A5、影像 F5、音訊 D5、影片 B4）'
        '×疏離密度倍率；repluckMs=同弦重撥冷卻。',
    params: {
      'pluckFreq': 'freqLo*(freqHi/freqLo)^t，t=弦長百分位',
      'starPitch': '副檔名→EXT_PITCH ×(1+密度)',
      'cooldown': 'repluckMs 定版 2800',
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: 'xiaokui:galaxy-full-picture',
    updatedAt: DateTime(2026, 9, 25),
  ),
  CompassRule(
    id: 'galaxy.modeExtension',
    organId: 'brain.galaxy3d',
    description: '新模式/新按鈕誕生術：使用者或 Agent 擴充星系的完整導航',
    why: 'Blue 2026-09-25 令：「將來讓使用者跟 App Agent 自己產生新的用法、'
        '新的按鈕——Agent 到羅盤面前，羅盤要給他完整的大腦圖譜工具跟地圖。」'
        '範本是 swarm（作戰模式）：本體只登記狀態，實作放獨立 layer 檔。',
    params: {
      'step1': 'VIZ_NAMES 註冊新模式名（按鈕自動長出來——buildVizUI 迭代此表）',
      'step2': '實作放獨立 layer（範本 swarm_layer：掛 window.__warEnter/__warExit，本體 setVizMode 認得就委託）',
      'step3': '鐵則·沙盒令：進場做自己（loadModeParams 模式參數包 GET /galaxy_params?mode=m），出場回基準（restoreBaseline＋STARC_PRISTINE 唯讀快照還原——A 模式不得污染 B 模式）',
      'step4': '鐵則·hover/音效：新模式若要 hover 撥弦，走既有 raycast 鏈（勿另建）；river 模式示範了「關撥弦讓位給敘事」的退出寫法（pluckString 開頭 return）',
      'step5': '鐵則·效能：分幀拾取（每幀 1/8 星）不可退；新視覺每幀直寫 color buffer 者，退出時必須全套強制還原（v275 教訓）',
      'step6': '出廠參數加進 GPARAMS（galaxy.html 頂部）＋galaxy_params.json 模式包同步',
      'step7': 'rebuild（assets 打包）＋cb=時間戳破快取＋本規則 updatedBy 留名',
    },
    kind: CompassRuleKind.visual,
    updatedBy: 'xiaokui:galaxy-extension-map',
    updatedAt: DateTime(2026, 9, 25),
  ),
  // [小葵 2026-09-25 Blue 修正令] 「不是只產生新按鈕這麼簡單——羅盤精靈
  // 給 App Agent 的是大腦星系圖譜的完整結構邏輯目錄。」modeExtension 是
  // 操作手冊；本規則是解剖圖——九大子系統＋各自真相源，任何星系問題
  // 先查這裡定座標，再進 galaxy.html 對應區塊。
  CompassRule(
    id: 'galaxy.structureCatalog',
    organId: 'brain.galaxy3d',
    description: '大腦星系圖譜完整結構邏輯目錄（九大子系統）——羅盤精靈的第一張圖',
    why: 'galaxy.html 3600 行單檔含 nine 子系統，Agent 沒有目錄會在裡面迷航。'
        '每個子系統標註：真相源（改哪裡）＋關鍵機制（為什麼是這樣）。'
        '任何星系任務＝先在本目錄定位子系統→進對應程式碼區塊→遵守該區鐵則。',
    params: {
      '①資料層': '星=assets[]（檔案：n 名/x,y,z 位置/dens 密度/屬性）；記憶球=nodes/nodeData（sources 源頭分類）；縫線=threads（星↔球關聯，弦長=L）；佈局=galaxy_layout.json',
      '②場景層': 'three.js：galaxy group（自轉容器）→sg 星幾何（STARC_PRISTINE 唯讀色彩快照=還原唯一真相源）/inst 記憶球 InstancedMesh/ threadMesh 弦/threadGeo＋__threadLens（音頻用長度）',
      '③渲染迴圈': 'animate()：慣性自轉 spin→呼吸 sun.intensity→因果流光→lightAuthority 結算亮度（唯一寫手）→分幀拾取（1/8 星/幀）→pluckString 全域殘響',
      '④互動層': '拖曳旋轉（midDown 旗標）/滾輪縮放/點擊認定（<4px 才算 click——拖曳後不誤觸）/focus 飛行（選星→相機飛去→繞星公轉）/lockTarget 飛彈鎖定框',
      '⑤模式系統': 'VIZ.mode＋VIZ_NAMES{galaxy全景,river時間之河,swarm作戰}；setVizMode=沙盒令（進場做自己、出場 restoreBaseline 回基準、模式參數包獨立）',
      '⑥音效系統': 'playTone(kind)：pluck 撥弦（f∝1/L 弦長反比、repluckMs 冷卻）/star 星音（副檔名→五聲音階家族×密度倍率）/ball 球音；audioOn 總開關；WebAudio 直發',
      '⑦參數系統': 'GPARAMS 出廠預設（Blue 定版 2026-09-25）→設定窗（__editing 編輯鎖 2.5s）→POST /galaxy_params→galaxy_params.json（每模式獨立包）→頁面每秒 GET 輪詢回寫',
      '⑧App 橋接': 'WKWebView 容器=galaxy_webview.dart（hover 座標注入 __flutterHover＋__appHoverAlive 心跳 500ms＋FPS 監控 30s＋連續低幀自動重載）；MCP 8420：/galaxy_ping 遙測+遠端指令（setMode/sandboxCheck）、/galaxy_params、galaxy_rules.json（羅盤橋）',
      '⑨擴充點': '新模式=VIZ_NAMES 註冊+獨立 layer（詳 galaxy.modeExtension）；新參數=GPARAMS+模式包；新音色=playTone kind 擴充；新指令=MCP ping 回應 cmd 擴充——全部有既有範本可抄',
    },
    kind: CompassRuleKind.visual,
    updatedBy: 'xiaokui:galaxy-structure-catalog',
    updatedAt: DateTime(2026, 9, 25),
  ),
  // [小葵 2026-09-25 Blue 改裝令] 「開源後 App 完全自由改裝——像改車。
  // 羅盤裡關於這部分的目錄是否完整？」調查結論：galaxy 九大子系統完整，
  // 但全 App 改裝面目錄缺——開源前必修。四大改裝層各有真相源：
  CompassRule(
    id: 'app.moddingCatalog',
    organId: 'agent.loop',
    description: '全 App 改裝目錄（開源賣點）：改什麼、去哪改、要不要重新編譯',
    why: 'Blue 2026-09-25：「羅盤裡的功能/頁面/按鈕/主題，開源後都可完全'
        '自由改裝——像改車一樣，這是我們的一大特點。」Agent 帶使用者改裝'
        '前先查本表：改裝面→真相源→編譯需求，避免亂拆引擎蓋。',
    params: {
      'L1·免編譯·主題包': 'Tier 系統（lib/theme/：tier.dart 33 語意層級→tier_registry manifest→bridge_ds_tokens）——改 token 值=200+ widget 全跟著變；ThemePack 模型=lib/models/theme_pack.dart、設定頁=theme_settings_page.dart；規範=docs/BRIDGE_TIER_SYSTEM.md（鐵則：widget 禁寫死顏色，違規 PR 不可 merge）',
      'L2·免編譯·星系調校': 'galaxy_params.json（GPARAMS 全參數）——設定窗或 POST /galaxy_params 即時生效；星系顏色/音效/自轉/光暈全在參數，詳 galaxy.structureCatalog ⑦',
      'L3·免編譯·內容與流程': '畫布工作流（節點+連線=使用者自由組裝）、vault_templates.dart 範本、夥伴外觀/聲音（companions appearance/voice 設定頁）——不改碼就能發明新用法',
      'L4·需重編·原始碼改裝': '新模式/新按鈕（galaxy.modeExtension 七步）、新節點型別（NodeTypePorts.portsFor 註冊+node_widget 渲染+executor 分支）、新 MCP 指令、Swift 橋（APP_ARCHITECTURE_MAP.md 標註兩端都要改的陷阱點）',
      '氣氛層': 'docs/BRIDGE_ATMOSPHERE_LANGUAGE.md——LOGO 鎖死 5 條+社群可改事項；氣氛主題包獨立於功能層；GPU≤5%/CPU≤8% 紀律',
      '設計憲法': '改裝不可違：Tier 鐵則（禁寫死色）、色塊規範、排版原則——違規 PR 不可 merge；衝突裁決順序見 BRIDGE_UNIFIED_DESIGN_LANGUAGE.md',
      '開源前檢查': 'docs/OPEN_SOURCE_READINESS_ROADMAP.md（隱私紅線：24 處 hardcode 路徑/金鑰掃描/git 歷史 secrets——重掃指令齊全）；圍觀開發者版改車手冊=docs/opensource/MODDING_GUIDE.md（README 已連結）',
    },
    kind: CompassRuleKind.visual,
    updatedBy: 'xiaokui:modding-catalog',
    updatedAt: DateTime(2026, 9, 25),
  ),
  CompassRule(
    id: 'galaxy.paramPipeline',
    organId: 'brain.galaxy3d',
    description: 'GPARAMS 參數管線：出廠預設→設定窗→持久化→輪詢回寫',
    why: '參數三層：galaxy.html GPARAMS（出廠預設）→設定窗拉桿（__editing '
        '編輯鎖 2.5s 防輪詢覆蓋）→galaxy_params.json（POST 持久化）→頁面'
        '每秒 GET 輪詢回寫 GPARAMS（1 秒內生效）。出廠預設已定版為 Blue '
        '2026-09-25 實測調校值——重置即定版樣子。分幀拾取（每幀只測 1/8 '
        '星，<2ms/幀）是效能命脈，勿改回全量 raycast（10-30ms=掉幀脈衝）。',
    params: {
      'factoryDefaults': 'Blue 定版 2026-09-25（pluckVol 0.05/starVol 0.23/freq 315-1500）',
      'editLock': '__editing 2.5s——拖桿中不被輪詢蓋',
      'frameSplitPick': '每幀 1/8 星，8 幀一輪 130ms 完整覆蓋',
    },
    kind: CompassRuleKind.visual,
    updatedBy: 'xiaokui:galaxy-full-picture',
    updatedAt: DateTime(2026, 9, 25),
  ),
  CompassRule(
    id: 'voice.vadSilence',
    organId: 'voice.input',
    description: '語音斷句：靜音多久判定話說完了',
    why: '1500ms 靜音 = 一句話結束；過短會切斷語氣中的停頓，過長會讓回應變慢。',
    params: {'silenceMs': 1500.0, 'onsetMs': 150.0},
    kind: CompassRuleKind.behavioral,
    updatedBy: 'auto:harvest',
    updatedAt: _seedTime,
  ),
  // [S4 Blue 統一令 2026-09-08] 搜尋引擎單一真相——寫進羅盤讓未來 Agent 不走錯路
  CompassRule(
    id: 'search.singleEngine',
    organId: 'vault',
    description: '搜尋引擎單一真相：所有搜尋入口（全域搜尋、向量資料庫 UI、'
        '未來任何新入口）一律走 VaultSearchFacade，不得另建搜尋路徑',
    why: 'Blue 2026-09-08 統一令「一次調整，兩邊生效」——之前全域搜尋走 hybrid'
        '（每次查詢跑本地嵌入推理=慢）、vault 走 fullText（LIKE=快），兩套系統'
        '速度與結果都不一致，改一邊漏一邊。收斂後：fullText=memories(LIKE)'
        '∥assets(FTS)並行合併；深化向量搜尋/標籤系統只改 facade 一處。',
    params: {
      'facade': 'lib/services/vault/vault_search_facade.dart',
      'globalSearch': 'lib/services/search/receipts_search_service.dart',
      'vaultUI': 'lib/screens/vault_screen.dart',
      'defaultMode': 'fullText',
      'modes': 'fullText|semantic|tag|hybrid',
      // hybrid 每查詢都跑嵌入推理——只留給使用者明確切換，不做任何入口的預設
      'hybridIsSlowReason': 'per-query local embedding inference',
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: 'agent:小葵（S4 統一令落地）',
    updatedAt: _seedTime,
  ),

  // [Blue 令 2026-09-12] 示範錄製是獨立器官——長器官的現場即視
  CompassRule(
    id: 'routine.organPrinciple',
    organId: 'routine.record',
    description: '示範錄製是橋樑的獨立器官（肢體），不隸屬任何頁面：'
        '涵蓋畫布內錄製（RoutineRecorder→範本）與全電腦錄製'
        '（SystemRoutineRecorder→routine 檔）。任何新入口（對話指令、'
        '快捷鍵、Agent 工具）都打這兩個服務，不得另建錄製路徑。',
    why: 'Blue 令（2026-09-12）：「示範錄製應該是一個獨立的動作，因為我們'
        '已經把它寫成錄製整個電腦工作流程不再只是僅限於 App——這是很重要的'
        '器官跟肢體。」它解決 MCP 不完備時的 Agent 代操作問題（全 macOS '
        '輔助使用樹=通用 MCP）。分層：Dart 層平台中立（schema/故事/遮罩），'
        'macOS 後端 CGEventTap+AX；Windows 後端未來=SetWindowsHookEx+UIA。',
    params: {
      'canvasRecorder': 'lib/services/routines/routine_recorder.dart',
      'systemRecorder': 'lib/services/routines/system_routine_recorder.dart',
      'replayEngine': 'lib/services/routines/system_routine_player.dart',
      'store': 'lib/services/routines/system_routine_store.dart',
      'entryPoints': ['home:訓練AI夥伴（唯一入口，Blue 拍板 2026-09-12）', 'tray:導航至訓練頁', 'canvas:歡迎卡錄製範本（App 內錄製）'],
      'privacy': 'AXSecureTextField 遮罩+全程本地+Agent 注入過濾',
      'replaySafety': 'gate.arm 圍欄+Esc 1.5s 急停+遮罩事件絕不重播',
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: 'agent:小葵（長器官入羅盤）',
    updatedAt: DateTime(2026, 9, 12),
  ),

  // [Blue 令 2026-09-12] 記憶架構法則——永不失憶+靈活調尋
  CompassRule(
    id: 'memory.architecture',
    organId: 'memory',
    description: '記憶分兩域，法則不同：'
        '①知識域（memories 表）會衰減——importance 決定半衰期'
        '（5→90天…1→5天），常被存取的記憶慢忘；降級→歸檔→休眠，'
        '永不刪除。②經驗域（agent_memories 表）永不衰減——lesson/'
        'preference/pattern/milestone/skill/experience 六型。'
        'Agent 檢索一律走 memory_search 十階段管線（FTS+語意→RRF→'
        'Reranker→圖譜展開→綜合答案），不预載全部記憶——按需調尋。',
    why: 'Blue 令（2026-09-12）：「記憶永不刪除永不失憶，但要滿足 Agent '
        '效率——不用負載全部記憶，能夠靈活調尋快速回憶。」對話紀錄完全'
        '保存同精神。衰減≠刪除：是安靜退到深處（歸檔可查），不是死亡。',
    params: {
      'knowledgeTable': 'memories（BrainDatabase——衰減跑這裡）',
      'experienceTable': 'agent_memories（AgentKnowledgeService——永不衰減）',
      'search': 'memory_search 工具（十階段管線）',
      'visual': 'galaxy_data_service（星系——記憶看得見）',
      'writer': 'MemoryWriter（帶 companionId——記憶有署名）',
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: 'agent:小葵（記憶架構入羅盤）',
    updatedAt: DateTime(2026, 9, 12),
  ),

  // [Blue 令 2026-09-12] 招式＝程序性記憶——學會的招式永不遺忘
  CompassRule(
    id: 'memory.moveAsSkill',
    organId: 'routine.record',
    description: '招式與記憶自動同步（MoveMemoryBridge）：存招式→寫程序性'
        '記憶（memory_type: skill，含使出方式）；使出後→寫自傳記憶'
        '（memory_type: experience——成功幾步/跳過幾步/建議）；刪除→'
        '同步歸檔記憶（不留指向虛空的手）。Agent 接手時用 memory_search '
        '查「招式」即可找到所有招式記憶，按內文使出方式直接用。',
    why: 'Blue 令（2026-09-12）：招式是訓練出來的能力=程序性記憶，'
        '屬經驗域永不衰減；使出結果是自傳——「自己藉由經驗記憶成長升級，'
        '非常符合橋樑精神」。下次同類任務，Agent 檢索得到上次的成績單。',
    params: {
      'bridge': 'lib/services/routines/move_memory_bridge.dart',
      'skillType': 'skill（程序性——怎麼做）',
      'experienceType': 'experience（自傳——做過得如何）',
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: 'agent:小葵（招式入記憶）',
    updatedAt: DateTime(2026, 9, 12),
  ),

  // [小葵 2026-10-05 Blue 令] 生命樹全貌——觀景窗在羅盤列表頂部入口卡
  CompassRule(
    id: 'life_tree.architecture',
    organId: 'life_tree',
    description: '生命樹=兩主幹+一夜一夢：反思樹（life_tree_dreams，'
        '02:00–05:00 夢境結論卡）+ 歷史樹（agent_causal_ledger，每次'
        '工具呼叫的戰役紀錄）+ 遺憾清單（life_tree_thought_branches，'
        '沒走的路）。觀景窗入口=羅盤頁頂部「生命樹」卡（夢/戰役/遺憾三 tab）。',
    why: 'Blue 2026-10-05：「生命樹是長在羅盤裡的，也跟羅盤有最大的關係，'
        '所以這個 UI 要長在羅盤頁面裡。」代謝環（2026-10-05 手術）：白天'
        '受傷→夜晚進夢→夢卡 7 天效期回灌她白天 prompt（上限 3 張）→被引用'
        '的草稿升級 consensus→遺憾進夢即結案。',
    params: {
      'dreams': 'life_tree_dreams（dream_session_id 同晚分組）',
      'ledger': 'agent_causal_ledger（環形緩衝上限 2000 筆）',
      'regrets': 'life_tree_thought_branches（revisited_at IS NULL=未重評）',
      '回灌': 'activeLessons()：7天效期+上限3張+安睡卡排除',
      '升級': 'promoteDraftsReferenced()：agent_draft→consensus（冪等）',
      'scheduler': 'DreamScheduler.tick（CompassHeartbeat 60s，重入鎖）',
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: 'xiaokui:life-tree-viewer',
    updatedAt: DateTime(2026, 10, 5),
  ),

  // [Blue 命令 2026-09-12] 協作系統運作總覽——新器官/肢體動工前必讀
  CompassRule(
    id: 'collab.operatingModel',
    organId: 'collab.system',
    description: '參考 Buzz 與 Grok Bot 設計的應用統一歸類為「協作系統」——'
        'Agent 蜂群執行、小隊執行、單兵聯合作戰共享戰果的完整體系。'
        '四種作戰形態：①單兵（夥伴獨立接工——TaskDispatcher 派工→'
        '狀態機 dispatched→working→awaitingReview→delivered）'
        '②小隊（房間制——任務卡🏠四象限：對話流/畫布/產出物/審計同屏，'
        '一件工作共居一室）③蜂群（delegate_subagent 分身戰術＋'
        'delegate_batch 批次派兵）④共享戰果（BudgetLedger 工作真相帳本——'
        '每筆工作蓋 AgentSeal 指紋章，全員可查）。'
        '⚠️ 新器官/肢體動到派工、房間、delegate、帳本任一環節＝踩空風險——'
        '動工前必讀本法則，並遵守：不另建任務通道（一律 TaskDispatcher）、'
        '不另建成果展示（一律房間四象限）、不另建記帳（一律 Ledger＋蓋章）。',
    why: 'Blue 命令（2026-09-12）：「這些協作系統我們目前已經做了不少功能與'
        '協作設計，未來 App Agent 如果想要長出的新器官或肢體會動到這一些'
        '環節的時候就很容易踩空，所以這個也要寫在羅盤裡——要讓任何一個'
        '接手的 Agent 或使用者能夠看到羅盤就一目了然知道我們的 Agent '
        '協作系統到底是怎麼運作的。」',
    params: {
      'dispatcher': 'lib/services/tasks/task_dispatcher.dart（唯一任務通道）',
      'sessionStates': 'dispatched→working→awaitingReview→delivered',
      'room': 'lib/widgets/chat/task_progress_card.dart（🏠四象限）',
      'swarm': 'delegate_subagent＋delegate_batch（分身戰術）',
      'ledger': 'lib/services/budget_ledger.dart＋AgentSeal 蓋章',
      'delivery': 'kind=task-delivery，前綴「✅ 任務完成」',
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: 'agent:小葵（協作系統入羅盤）',
    updatedAt: DateTime(2026, 9, 12),
  ),
  // [刀 6 Blue loop 鐵則 2026-09-08] 信任 loop——做事→回報→檢討→升級→再做事
  CompassRule(
    id: 'trust.visibleLoop',
    organId: 'agent.loop',
    description: '任何 Agent 自律/信任功能必須是活 loop 且使用者可見：'
        '做事→回報→檢討→升級→再做事。事件流（TrustLoop）是唯一可見化通道，'
        'UI 介面（跑馬燈/TrustMeterCard/托盤）都吃同一流，不得各建各的。',
    why: 'Blue 2026-09-08 鐵則「使用者都要在過程中看得到、體驗得到 Agent 有'
        '回報有檢討有升級；重要的事情記記憶、系統的事情記羅盤」——黑箱自律'
        '等於沒有自律，看不見的信任無法成長。',
    params: {
      'engine': 'lib/services/trust/trust_loop.dart',
      'score': 'lib/services/trust/trust_score.dart',
      'formula': 'score = 0.30 + 0.65×成功率 − 0.25×浪費率（clamp 0~1）',
      'tiers': '新手<50% ≤成長中<70% ≤中信任<90% ≤高信任',
      'consumers': 'trust_loop_ticker / trust_meter_card / tray_service',
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: 'agent:小葵（刀 6 loop 鐵則落地）',
    updatedAt: _seedTime,
  ),
  // [小葵 2026-09-09 Blue 令] 向量資料庫 v2 流程——嵌入+素描+標籤一條龍
  CompassRule(
    id: 'vault.identityPipeline',
    organId: 'vault',
    description: '向量寫入唯一流程：掃描(junk排除+audience分層) → 身份嵌入'
        '(五因素:資料夾/分類/主題/任務/屬性+內容) → embed_source=identity(終態)',
    why: 'Blue 2026-09-09 令「向量嵌入邏輯重整」——寫入時就該帶身份，'
        '不是事後補。embed_source 單調升級鏈 filename→metadata→content→'
        'identity，任何 backfill 不得降級（蓋寫競態實測教訓）。',
    params: {
      'embedTextFormat': '[資料夾:路徑] [分類:folder_origin] [主題:summary] [任務:name] [屬性:topic_terms] 檔名 內容',
      'reembedBatchDelayMs': 10,
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: '小葵',
    updatedAt: DateTime(2026, 9, 9),
  ),
  CompassRule(
    id: 'vault.vectorSketch',
    organId: 'vault',
    description: '嵌入完成自動觸發「向量資料素描」：全庫聚類分析(日期折疊)'
        '→MD素描文檔→回寫folder_origin分類+topic_terms關聯詞',
    why: 'Blue 2026-09-09 正式命名令——素描是標籤與搜尋結構的基礎，'
        '資料庫長大素描跟著更新，不靠人工規則維護。',
    params: {
      'sketchMdPath': 'docs/向量資料素描.md',
      'siblingClusterMin': 3,
      'writeToMemories': true,
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: '小葵',
    updatedAt: DateTime(2026, 9, 9),
  ),
  CompassRule(
    id: 'vault.searchGrouping',
    organId: 'vault',
    description: '搜尋結果分組：品種級葉段key(同葉名跨根合併、日期段折疊)'
        '+資料夾卡帶縮圖+圖片組排前(圖片>文字>其他)+搜尋無上限',
    why: 'Blue 2026-09-09 令——同一資料夾名在多授權根有副本(阿川資料區/'
        '01_現況紀錄撞名)造成重複分組；葉段key一律合併。maxPerSource=3'
        '舊閘門曾讓整個農場照片被壓到3筆（品種全滅）。',
    params: {
      'groupKey': 'leafSegment',
      'dateFold': true,
      'typeOrder': '["image","text","other"]',
      'maxPerSource': 0,
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: '小葵',
    updatedAt: DateTime(2026, 9, 9),
  ),

  // [小葵 2026-09-09 主動寫入] Blue 令「羅盤也是給 agent 們用的——
  // 原則要自己判斷、主動寫入」。以下兩條是當天實戰換來的教訓。
  CompassRule(
    id: 'agent.ruleEnforcement',
    organId: 'agent.loop',
    description: '規則寫進羅盤 ≠ 系統會遵守——每條規則必須指出自動執行'
        '機制（掛在哪個觸發點：事件/週期/寫入路徑），否則等於沒寫',
    why: '2026-09-09 實例：葉段合併規則寫了但沒執行機制，Blue 點破'
        '「規則不會自己執行，還是需要 agent 做」。修法是把素描掛上 '
        'autoIngest 完成點才真正自動化。以後立規則時同步回答：'
        '「誰在什麼時候執行這條？」',
    params: {'enforcementQuestion': '誰在什麼時候執行這條規則？'},
    kind: CompassRuleKind.behavioral,
    updatedBy: '小葵',
    updatedAt: DateTime(2026, 9, 9),
  ),
  CompassRule(
    id: 'vault.uiChangeVisibility',
    organId: 'vault',
    description: 'UI 變更必須在使用者當前可見區域內生效——展開/結果'
        '掛在捲動區尾端等畫面外位置，等於功能不存在',
    why: '2026-09-09 實例：資料夾卡「點了沒反應」——縮圖牆其實展開了，'
        '但在方格牆最尾端（畫面外），使用者只看到選取框延遲亮起。'
        '互動內容要嘛原地展開要嘛彈窗，不許丟到看不見的地方。',
    params: {'placement': 'inPlaceOrDialog'},
    kind: CompassRuleKind.behavioral,
    updatedBy: '小葵',
    updatedAt: DateTime(2026, 9, 9),
  ),

  // [小葵 2026-09-10 Blue 令] 字級修改統一原則——三次抓包換來的
  CompassRule(
    id: 'app.typographyScale',
    organId: 'agent.loop',
    description: '改字級大小前先查「真主題」與「元件是否吃主題」——'
        '統一走 Tier 尺寸表（12/14/16/18/20，每級差2），禁寫死非級距值',
    why: '2026-09-09/10 實例：(1) app.dart 用 BridgeDS.themeFrom()，'
        'app_theme.dart 的 light/darkTheme 是舊手機頁遺留沒人用——改錯'
        '檔等於沒改。(2) M3 PopupMenuItem 內自訂 child Text 不吃 '
        'popupMenuTheme.textStyle——全域主題改了穿不進去，要顯式指定。'
        '(3) OutlinedButton 漏設主題時吃 M3 預設 labelLarge 還被 '
        'textScale 放大。校準法（Blue）：畫面最小字+標題+最大字要成'
        '邏輯級距；最大字通常是問題所在。',
    params: {
      'realTheme': 'BridgeDS.themeFrom（bridge_design_system.dart）',
      'tierScale': '12/14/16/18/20',
      'checklist': '1.確認 MaterialApp 實際用的主題 2.確認元件類型是否吃該主題 3.不吃就顯式指定 fontSize',
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: '小葵',
    updatedAt: DateTime(2026, 9, 10),
  ),

  // [小葵 2026-09-10 Blue 令] 設計系統三原則——字級之外，顏色/
  // Tier 分類/主題包一起入羅盤（來源：BRIDGE_TIER_SYSTEM.md、
  // BRIDGE_COLOR_BLOCK_DESIGN_GUIDE.md、BRIDGE_TYPOGRAPHY 設計原則）
  CompassRule(
    id: 'app.colorTokens',
    organId: 'agent.loop',
    description: '顏色一律走 BridgeDSColors token——三層視覺架構：'
        'canvas(主背景)→surface(卡片)→surfaceElevated(浮出元素)；'
        '文字強弱 textPrimary>Secondary>Tertiary>Muted；'
        '強調色按語意選（accentBlue=CTA/焦點、accentPurple=品牌、'
        'accentGreen=成功、accentRed=錯誤），禁寫死 hex',
    why: 'Tier 系統三大防呆之一：寫死顏色會讓主題包失效——開源社群'
        '改 token 值要能一鍵對齊全 App，任何 hardcode hex 都是對不'
        '齊的破口。V2 Canvas 抽出的三層架構（畫布→卡片→浮出）是'
        '所有頁面的視覺基底。',
    params: {
      'layers': 'canvas→surface→surfaceElevated',
      'text': 'textPrimary/Secondary/Tertiary/Muted/Quaternary',
      'accents': 'blue=CTA,purple=品牌,green=成功,red=錯誤,yellow=警示',
      'rule': '禁 Color(0x...) hardcode；用 BridgeDSColors.of(context)',
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: '小葵',
    updatedAt: DateTime(2026, 9, 10),
  ),
  CompassRule(
    id: 'app.tierSemantics',
    organId: 'agent.loop',
    description: '文字樣式一律走 Tier（語意層）——TierStyle.of(context, '
        'Tier.cardTitle) 而非手寫 TextStyle；tier 命名「命名空間.元素.'
        '角色」（card.caption / list.item.title / form.label）；'
        '例外微調用 tierBasedStyle(context, Tier.X, fontSize: 級距內)',
    why: 'Tier 三層架構：L1 設計稿（語意）→L2 widget（TierStyle.of）'
        '→L3 主題包（manifest 資料）。跳過 Tier 直接寫 TextStyle＝'
        '主題包管不到的孤兒樣式。防呆已內建：textColor 只收 token 名'
        '（String）、拼錯 build 失敗、未定義 tier 會 throw。',
    params: {
      'usage': "TierStyle.of(context, Tier.cardTitle).toTextStyle()",
      'naming': 'namespace.element.role（card.caption/list.item.title）',
      'escape': 'tierBasedStyle(ctx, Tier.X, fontSize: 級距值)',
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: '小葵',
    updatedAt: DateTime(2026, 9, 10),
  ),
  CompassRule(
    id: 'app.themePack',
    organId: 'agent.loop',
    description: '主題包＝開源社群的一鍵換膚機制——manifest（assets/'
        'theme_packs/*.json）定義 tiers+tokens 值；App 端（widget→tier→'
        'token 三層）不動，改包不改碼；新增視覺變體優先擴 manifest 而非'
        '加 hardcode',
    why: '開源目標：社群設計者下載主題包就能對齊全 App 字色/字級/'
        '字型，不需重編譯。任何繞過 manifest 的樣式都會讓「一鍵對齊」'
        '破功——這是字級三次抓包事件的深層教訓：樣式入口不統一，'
        '修一處漏三處。',
    params: {
      'manifest': 'assets/theme_packs/bridge_default_v2.json',
      'principle': '改包不改碼（社群換膚零編譯）',
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: '小葵',
    updatedAt: DateTime(2026, 9, 10),
  ),
  // [小葵 2026-09-10 Blue 令] 生效機制升級——規則不再只躺 DB：
  // 設計四原則的精華已注入 agent_design_knowledge（每輪 system
  // prompt 都帶），agent 長 UI 前就被約束，不是靠它想到去讀。
  CompassRule(
    id: 'agent.designKnowledgeInjection',
    organId: 'agent.loop',
    description: '設計規則的生效機制＝雙層：(1) 靜態注入——四原則精華'
        '寫在 agent_design_knowledge.dart（AgentLoopPromptBuilder 每輪'
        'system prompt 必帶）；(2) 動態查閱——動 UI/器官前 compass_read'
        '看最新規則。新增設計規則時兩層都要考慮：DB 規則＋prompt 注入',
    why: 'Blue 2026-09-10：「規則寫好就要啟動生效機制，不要我們寫我'
        '們的、它走它的」。規則只在 compass_store DB 裡躺著＝沒有執行'
        '點（agent.ruleEnforcement 的教訓重演）。設計決策發生在 agent'
        '寫 code 的瞬間——prompt 注入是唯一保證每輪都生效的機制。',
    params: {
      'injectPoint': 'lib/services/agent_loop/agent_design_knowledge.dart → build() 每輪注入',
      'dynamicCheck': '動手前 compass_read（規則可能即時更新）',
    },
    kind: CompassRuleKind.behavioral,
    updatedBy: '小葵',
    updatedAt: DateTime(2026, 9, 10),
  ),

];

/// [三步長肉意義層初版 · 小葵 2026-09-07] 小葵代筆的白話說明——
/// 每個器官一句人話。只填空白欄位：如果 Blue 已寫過 nickname，
/// 永遠以人的版本為準（意義層是人的擁有物）。
const kSeedMeanings = <String, String>{
  'chat': '跟夥伴說話的地方——每天用最多的主畫面',
  'chat.controller': '對話的大腦——訊息怎麼送、記憶怎麼接都在這',
  'voice.input': '用說的輸入——VAD 斷句 1.5 秒靜音算說完',
  'voice.tts': '夥伴的嗓子——Kokoro 本地合成，不花雲端錢',
  'canvas.engine': '無限畫布引擎——視覺化思考的主戰場',
  'canvas.chat': '畫布裡的對話框——邊看圖邊聊',
  'brain.galaxy3d': '3D 星系——記憶的宇宙觀，每顆星是一段回憶',
  'brain.container': '大腦容器——向量記憶庫，記憶自動歸檔',
  'vault': '向量資料庫——檔案索引與語意搜尋',
  'agent.loop': 'Agent Loop——夥伴自主工作的引擎',
  'agent.mcp': 'MCP Server——App 對外的服務窗口（8420 埠）',
  'scan.fastfingerprint': '快指紋嵌入過濾（已實現 2026-10-01 F3）——generateEmbeddings 對 pending 檔先 stat 比對 DB 的 size:mtime，一致即跳過（零讀檔），不符才讀檔算 SHA256。掃描管線三層完成：F1 指紋（重啟不重掃）→F1b 批次化→F3 快指紋。',
  'oss.harvest': '七金礦開源收穫（已上傳 2026-10-01）——semi-dao/semi-bridge：docs/benchmarks/（12B 盲測包+可重演腳本）、docs/MODEL_LAB.md（一鍵 A/B 實驗室）、docs/MODDING_GUIDE.md（掛牌/三鐵律/換模型/懸浮窗之鑒）。兩天七礦（活動中心→互踩→CVDisplayLink→B方案快測→掃描架構→懸浮窗復活→狀態機）全數冶煉為產品+開源文件。',
  'runtime.autorevive': '大腦自動復活 v2（已實現+六輪實測 2026-10-01 F5a-d）——BrainRevivalService App 級 30s health poll（進程層、模型無關，任何 GGUF 通用）；2 miss 判死→startServer 復活；冷卻=嘗試節流（10 分鐘一試，非死亡鎖）；BrainLifecycle stream 單一真相源。教訓碑：URL 真相源=local_model_endpoint 非 gateway_url；看門狗不得掛 UI 依賴；冷卻節流≠見死不救。',
  'system.fingerprint': '樹指紋快取（已實現 2026-09-30 F1/F1b/F1c）——fullScan 指紋落盤 brain_meta（FNV-1a 穩定 key），重啟先比對再掃。實測：重啟掃描 80分→秒級；_persistRecords 批次化（7000 逐筆 SELECT→一次全撈）。教訓：String.hashCode 每啟動隨機化不可做持久 key。',
  'system.activity': '系統活動中心（已實現 2026-09-30）——BackgroundTaskRegistry 單一真相源+系統頁頂部卡。所有長時背景任務必須掛牌：名稱/進度/當前檔案；無任務時隱形（安靜=綠燈）。新任務接入：Registry.instance.update(BackgroundTask(...)) → finish(id)。',
  'local.engine': '本地模型引擎（18789）——不花雲端錢的算力。現役模型由 App 按鈕切換（模型頁「設為現役」），紫色框鎖定現役；安全閘：磁碟檢查→RAM 預算→OOM 回滾（Blue 2026-09-28 定案）',
  'local.kokoro': 'Kokoro TTS（18900）——語音合成服務',
  'model.lab': '模型實驗室——新模型出現→用你的照片快測(5張)→自主報告→一鍵採用。安全閘：磁碟→RAM→OOM回滾（2026-09-28 12B 選型之戰的產品化）',
  'theme': '設計系統——整個 App 的視覺語言',
  'goldenkeys': '金鑰匙系統——鑰匙鎖定後四處通行',
  'computeruse': 'Computer Use 接管閘門——安全先於功能',
  // [小葵 2026-09-11 Blue 令] 全器官說明補齊——每個點的特性與用法
  'agent.budget': '預算帳本與付費閘門——每天花多少錢、生成類動作的上限，都在這把關。超額會擋下並回報，不怕 agent 失手燒錢',
  'agent.computeruse': '代操引擎（Computer-Use Harness）——讓夥伴代你操作專業軟體（AutoCAD 量尺寸、Blender 建模）。三通道鐵則：能讀結構就不截圖，能跑腳本就不碰視覺',
  'agent.tools': 'Agent 工具註冊——夥伴會哪些動作（查資料、畫圖、開檔案）的總登記處。新增能力先在這註冊，夥伴才知道自己會',
  'brain.embed': '嵌入管線——把文字變成向量（數學指紋）的流水線。檔案匯入後自動跑，搜尋「鹿角蕨」能找到照片就是它的功勞',
  'brain.ingest': '資產導入 autoIngest——新檔案丟進資料夾後自動建索引、抽內文、生成嵌入。背景慢慢跑，不用按任何按鈕',
  'canvas.inspector': '工作流體檢——執行畫布前的品質檢查：抓空殼節點、重複產出、孤兒結果。體檢不過會拒絕執行並給修復指引',
  'canvas.templates': '工作流範本——常用的畫布流程存成範本，下次一鍵套用不用重拉',
  'collab.delegate': '分身戰術（delegate 工具）——一次派多個分身並行做事，各自獨立工作後回報。大工程拆著跑的指揮系統',
  'collab.dispatch': '任務派工（隊友訊息流）——用白話派工，任務自己變成工作畫布在背景跑，過程直播在任務卡上看得到',
  'collab.ledger': '戰果共享（工作真相帳本）——每次行動的花費與成果自動記帳，誰做的、花多少、成果在哪，一目了然',
  'collab.room': '房間共居（任務卡四象限）——任務卡展開就是一個房間：對話、畫布、產出、審計同屏共居，看一個任務不用切四個頁面',
  'collab.system': '協作系統總覽——單兵／小隊／蜂群四種作戰形態的調度中心。人多或事大時在這決定怎麼分工',
  'companion.control': '夥伴控制中心——各夥伴的個性、聲音、能力的設定台。想讓誰更活潑或更精確，在這調',
  'companion.floating': '懸浮夥伴視窗——夥伴的小視窗，飄在所有 App 之上隨喚隨到，不用切回主視窗',
  'companion.hall': '夥伴大廳——所有夥伴的集合點，在這挑人、看誰在線、切換對話對象',
  'companion.summon': '召喚引擎——把特定夥伴叫進對話或任務的機制。喊一聲誰該上場，它負責把人帶到',
  'memory': '長期記憶系統——夥伴跨對話記得你的關鍵脈絡。重要的事記進記憶，系統的事記進羅盤',
  'project.door': '專案門——每個專案的入口。進門就切換到該專案的脈絡與檔案群',
  'project.kanban': '專案看板——任務的進度牆，待辦／進行中／完成一拉即改',
  'project.relation': '專案關係圖——專案之間誰跟誰有關連的地圖，跨專案找線索用',
  'routine.record': '示範錄製（全電腦）——把你在電腦上的操作錄成結構化示範，之後夥伴能照著重做',
  'routine.replay': '示範重播（Agent 代操作）——夥伴照錄好的示範代你操作——錄一次，之後全自動',
  'schedule': '排程引擎——時間到的自動任務（農場日記、週報、每日反思）。不用人盯，時間到自己跑',
  'semidao': 'SemiDAO 審查——開源發布前的品質與安全審查關卡，社群共治的最後一道門',
  'vault.graphrag': 'GraphRAG——把知識連成圖再回答。跨檔案的關聯問題（「A 專案用到的方法跟 B 有什麼關係」）靠它',
};

void seedMeanings(CompassStore store) {
  for (final e in kSeedMeanings.entries) {
    final existing = store.meaningsOf(e.key);
    if (existing['nickname'] == null || existing['nickname']!.value.isEmpty) {
      store.setMeaning(e.key, 'nickname', e.value,
          author: 'agent:小葵（初版代筆）');
    }
  }
}

/// 執行首播種子（冪等——只在規則/器官不存在時插入）
void seedCompass(CompassStore store) {
  for (final o in seedOrgans) {
    store.upsertOrgan(o, byHarvest: CompassAuthor.harvest);
  }
  for (final r in seedRules) {
    store.seedRule(r);
  }
  for (final r in distilledRules) {
    store.seedRule(r);
  }
  seedMeanings(store); // [2026-09-07] 意義層初版（只填空白，不覆寫人）
}

/// [小葵 2026-09-07] 2D 圖譜退役遷移——既有 DB 中的 2D 器官與規則卡
/// 標記退役（append-only，不刪除）。冪等：retireRule 對已 retired 規則
/// 重複執行無害；種子檔已不再插入這些 id。
void migrateRetired2D(CompassStore store) {
  const reason = '2D 圖譜正式退役（Blue 2026-09-07），3D 星系不受影響';
  for (final rid in ['brain.simGate', 'brain.veinEdge', 'brain.xrefEdge']) {
    if (store.rule(rid) != null) {
      store.retireRule(rid, byHuman: 'human:Blue', reason: reason);
    }
  }
  store.retireOrgan('brain.graph2d', byHuman: 'human:Blue', reason: reason);
}
