// compass_seek_agent_tool.dart
// [小葵 2026-09-10 Blue 令] 羅盤目的導向檢索——agent 丟出意圖，
// 羅盤自動顯現所需規則＋程式碼位置。
//
// 自動升級機制（Blue 設計）：agent 回報「漏了什麼」（missing）
// 時，把這個不足條件滾動寫入 intent 索引表——下次同類意圖直接
// 命中，不用再自主深挖。
//
// 搭配架構（Blue 2026-09-10 羅盤強大功能令）：
//   Layer 0：system prompt 只帶 ~600 token 索引卡（何時查羅盤）
//   Layer 1：compass_seek(intent) → 精準規則＋檔案位置（本工具）
//   Layer 2：compass_read 全文深挖＋missing 回報升級索引

import 'dart:convert';

import '../agent_tool.dart';
import '/services/compass/compass_models.dart';
import '/services/compass/compass_store.dart';

/// 意圖 → 規則/位置的索引表（存 compass_store DB 的 compass_meta，
/// key='intent_index'。滾動升級：compass_seek?missing=... 會 append）
class _IntentIndex {
  // 每條：關鍵詞（|分隔）→ 提示文字 + 規則 id 們 + 檔案錨點
  static const seedJson = '''
[
  {"kw":"字|字級|字體|大小|fontSize|文字尺寸|排版|太大|太小|字重|粗體|title|text|px|字看不清|文字|粗細|字型|font|label|行高|line-height|字距|letterSpacing|截斷|ellipsis|ellipsis",
   "rules":["app.typographyScale","app.tierSemantics","app.themePack"],
   "hint":"Tier 級距 12/14/16/18/20 每級差2；真主題=themeFrom；M3 不吃主題就顯式指定；字重/粗細是 Tier 屬性；字型(fontFamily)活在主題包 manifest"},
  {"kw":"顏色|色|color|hex|主題色|深色|淺色|dark|light|對比|contrast|看不清|太淡|太亮|背景|白底|夜間|佈景|佈景主題|hover|hover 效果|玻璃|磨砂|blur|漸層|gradient|陰影|shadow",
   "rules":["app.colorTokens","app.themePack"],
   "hint":"一律 BridgeDSColors.of(context) 動態取；三層 canvas→surface→surfaceElevated；禁寫死 hex"},
  {"kw":"樣式|TextStyle|Tier|tier|樣式表|圓角|邊框|border|radius|間距|spacing|padding|modal|dialog 的樣式|樣式",
   "rules":["app.tierSemantics"],
   "hint":"TierStyle.of(context, Tier.xxx) 唯一入口；圓角/間距/邊框也是 BridgeDS token（roundStandard 等）"},
  {"kw":"主題包|theme pack|換膚|manifest|新主題|載入主題|主題 json|匯入主題|theme json",
   "rules":["app.themePack"],
   "hint":"視覺值活在 assets/theme_packs/*.json；改包不改碼"},
  {"kw":"UI|按鈕|button|畫面|元件|widget|新增功能|肢體|器官|對話框|dialog|開關|彈窗|選單|列表|頁面|分頁|顯示|選項|輸入框|表單|標籤|icon|圖示|照片牆|縮圖|卡片|怪怪的|跑版|介面|modal|sidebar|badge|snackbar|onboarding|empty state|表格|進度條|context menu|長按|面板|panel|浮窗|提示|checkbox|stepper|navbar|導覽列|步驟器|toast|switch|toggle|radio|下拉刷新|chip|手勢|FAB|浮動",
   "rules":["app.typographyScale","app.colorTokens","app.tierSemantics","app.themePack","vault.uiChangeVisibility"],
   "hint":"長/修 UI 前四原則+UI可見性全看；驗收=深淺色+自訂主題包+使用者當前視野內生效"},
  {"kw":"搜尋|檢索|向量|embedding|嵌入|分組|排序|素描|素材池|資料夾",
   "rules":["search.singleEngine","vault.identityPipeline","vault.searchGrouping","vault.vectorSketch"],
   "hint":"搜尋分組=葉段key+圖片優先+無上限；嵌入=身份嵌入五因素；素描=嵌入完成自動跑"},
  {"kw":"改裝|主題包|theme|自訂|客製|開源|社群|換色|換字|modding|個人化",
   "rules":["app.moddingCatalog"],
   "hint":"改車目錄：L1主題包(Tier系統·免編譯·改token全App變)→L2星系調校(參數·免編譯)→L3內容流程(畫布/範本/夥伴·免編譯)→L4原始碼(新按鈕/新節點/新指令·需重編)。設計憲法不可違：禁寫死色/Tier鐵則。開源前查OPEN_SOURCE_READINESS_ROADMAP"},
  {"kw":"星系|大腦圖譜|galaxy|光球|亮度|保護模式|螢幕保護|閒置|3D|光點|撥弦|懸停|hover|音效|弦|GPARAMS|星系參數|設定值",
   "rules":["galaxy.structureCatalog","galaxy.architectureMap","galaxy.modeExtension","galaxy.lightAuthority","galaxy.screensaverIdle","galaxy.hoverBridge","galaxy.audioPhysics","galaxy.paramPipeline"],
   "hint":"先讀structureCatalog（九大子系統完整目錄：資料/場景/渲染/互動/模式/音效/參數/橋接/擴充——任何星系任務先在目錄定位）→要改檔看architectureMap→要長新模式/新按鈕看modeExtension（7步+沙盒令）。檔案：galaxy.html=assets/galaxy/、容器=galaxy_webview.dart、參數API=/galaxy_params@8420。鐵則：hover全靠Dart注入+__appHoverAlive心跳；改html必rebuild+cb破快取；分幀拾取勿改回全量；出廠預設=Blue定版09-25"},
  {"kw":"語音|斷句|靜音|VAD|說話|收音",
   "rules":["voice.vadSilence"],
   "hint":"靜音多久判定話說完（VAD 門檻）"},
  {"kw":"記憶關聯|自動關聯|xref|相似度門檻|記憶.*檔案",
   "rules":["brain.xrefThreshold"],
   "hint":"記憶↔檔案自動關聯相似度門檻"},
  {"kw":"自律|信任|trust|回報|檢討|自我監督",
   "rules":["trust.visibleLoop"],
   "hint":"任何自律/信任功能必須是活 loop 且使用者可見：做事→回報→檢討→升級"},
  {"kw":"羅盤|compass|規則|衝突|system prompt|系統提示|提示詞|prompt",
   "rules":["agent.ruleEnforcement","agent.designKnowledgeInjection"],
   "hint":"立規則必答「誰何時執行」；設計規則=DB+prompt 注入雙層"}
]
''';

  // [小葵 2026-09-10] CompassStore.db 私有——meta 表走 store.setMeta/
  // getMeta（若無則用 rules/organs API；此處用 compass_meta key/value）
  static const seedVersion = 10; // bump 10：app.moddingCatalog 改車目錄（開源改裝賣點：L1主題包→L4原始碼四層）

  static List<Map<String, dynamic>> load(CompassStore store) {
    final seed =
        (jsonDecode(seedJson) as List).cast<Map<String, dynamic>>();
    try {
      final verRaw = store.getMeta('intent_index_ver');
      final raw = store.getMeta('intent_index');
      if (raw != null && verRaw == seedVersion.toString()) {
        return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      }
      if (raw != null && verRaw != seedVersion.toString()) {
        // 種子升級：合併——新種子為底，append agent 自主升級的條目
        final old = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        final seedKws = seed.map((e) => e['kw']).toSet();
        final extra = old.where((e) => !seedKws.contains(e['kw'])).toList();
        final merged = [...seed, ...extra];
        _save(store, merged);
        return merged;
      }
    } catch (_) {}
    _save(store, seed);
    return seed;
  }

  static void _save(CompassStore store, List<Map<String, dynamic>> idx) {
    store.setMeta('intent_index', jsonEncode(idx));
    store.setMeta('intent_index_ver', seedVersion.toString());
  }

  /// 滾動升級：agent 回報 missing → append 關鍵詞到最相關條目，
  /// 或建新條目。冪等（同 kw 不重複加）。
  static void upgrade(CompassStore store, String missing, String? rulesCsv) {
    final idx = load(store);
    final m = missing.trim();
    if (m.isEmpty) return;
    // 優先 append 到第一個 rules 有交集的條目；否則建新條目
    final wantRules = (rulesCsv ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    for (final e in idx) {
      final rules = (e['rules'] as List).cast<String>();
      if (wantRules.any((r) => rules.contains(r))) {
        final kw = e['kw'] as String;
        if (!kw.split('|').contains(m)) {
          e['kw'] = '$kw|$m';
          _save(store, idx);
        }
        return;
      }
    }
    idx.add({
      'kw': m,
      'rules': wantRules.toList(),
      'hint': 'agent 自主查詢經驗新增（2026-09-10+）',
    });
    _save(store, idx);
  }
}

/// [小葵 2026-09-17 W1] 啟動即 seed——intent_index 不再 lazy。
/// 病根（causal_ledger 驗屍實證）：lazy seed 只在 compass_seek 首次
/// 呼叫時播種，而 agent 從不主動呼叫 compass_seek（353 次工具呼叫
/// 0 次）→ 死鎖：種子等查詢、查詢等種子。掛到 CompassBootstrap
/// 啟動鏈後，index 在 App 啟動時就寫入 DB（冪等：版本相符即跳過）。
void ensureIntentIndexSeeded(CompassStore store) {
  _IntentIndex.load(store); // load() 本身就是 seed-or-migrate 冪等邏輯
}

/// compass_seek——目的導向羅盤檢索（Layer 1）
class CompassSeekTool extends AgentTool {
  @override
  String get name => 'compass_seek';

  @override
  String get description =>
      '目的導向羅盤檢索——告訴羅盤你要做什麼，它回傳你需要的規則'
      '與檔案位置。任何 App 修改任務的第一步。\n'
      '參數：intent=你的目的（如「加一個按鈕」「改字級」）；\n'
      'missing=（選填）回報剛才結果缺了什麼——會滾動升級索引，'
      '下次同類目的直接命中。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'intent',
          description: '你的目的（自然語言，如：新增一個對話框按鈕）',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'missing',
          description:
              '（選填）上一輪 seek 結果不足之處——寫入升級索引，下次自動補',
          required: false,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final store = CompassStore.instance;
    final missing = args['missing']?.toString();

    // 自動升級：先處理回報（滾動寫入）
    if (missing != null && missing.isNotEmpty) {
      _IntentIndex.upgrade(store, missing, null);
      return AgentToolResult.success(
          '✅ 已記錄不足條件「$missing」到羅盤索引。'
          '請再用 intent 重新 seek，本輪就會包含升級後的結果。');
    }

    final intent = args['intent']?.toString() ?? '';
    if (intent.isEmpty) {
      return AgentToolResult.failure('intent 必填（你要做什麼？）');
    }

    final idx = _IntentIndex.load(store);
    final hits = <Map<String, dynamic>>[];
    // [小葵 2026-09-17 W2-S3] 大小寫不敏感比對——agent 打 "mcp"/"dxf"
    // 小寫時大寫種子詞（MCP/DXF）會 miss（紅隊實證）。
    final intentLower = intent.toLowerCase();
    for (final e in idx) {
      final kws = (e['kw'] as String).split('|');
      if (kws.any((k) => k.isNotEmpty && intentLower.contains(k.toLowerCase()))) {
        hits.add(e);
      }
    }

    final buf = StringBuffer();
    buf.writeln('## 羅盤檢索：$intent');
    buf.writeln();
    if (hits.isEmpty) {
      // [小葵 2026-09-10 紅隊教訓] 關鍵詞 miss ≠ 沒規則——回傳安全網：
      // 設計四原則（任何 UI/功能修改都適用）+ 全域 agent 規則，
      // 寧可多給不可漏給。並提示 missing 升級讓下次精準。
      buf.writeln('（無直接命中——安全網：設計通用規則＋全部 active 規則清單）');
      buf.writeln();
      buf.writeln('設計通用：');
      final safetyIds = [
        'app.typographyScale',
        'app.colorTokens',
        'app.tierSemantics',
        'app.themePack',
        'agent.ruleEnforcement',
      ];
      for (final r in store.rules(includeRetired: true)) {
        if (safetyIds.contains(r.id) &&
            r.status != CompassRuleStatus.retired) {
          buf.writeln('- 【${r.id}】${r.description}');
        }
      }
      buf.writeln();
      buf.writeln('羅盤全部 active 規則（可能相關，用 compass_read 查詳情）：');
      for (final r in store.rules()) {
        final d = r.description.length > 50
            ? '${r.description.substring(0, 50)}…'
            : r.description;
        buf.writeln('- ${r.id}：$d');
      }
      buf.writeln();
      buf.writeln('用 compass_seek?missing=你的意圖 升級索引，'
          '下次同類目的直接命中。要全文 compass_read。');
      return AgentToolResult.success(buf.toString());
    }

    for (final h in hits) {
      buf.writeln('### ${h['hint']}');
      final ruleIds = (h['rules'] as List).cast<String>();
      for (final rid in ruleIds) {
        final rules = store.rules(includeRetired: true)
            .where((r) => r.id == rid && r.status != CompassRuleStatus.retired);
        for (final r in rules) {
          buf.writeln('- 【${r.id}】${r.description}');
          final why = r.why;
          if (why != null && why.isNotEmpty) {
            buf.writeln('  why: ${why.length > 160 ? why.substring(0, 160) : why}');
          }
          final params = r.params;
          if (params != null && params.isNotEmpty) {
            buf.writeln('  params: ${jsonEncode(params)}');
          }
        }
        // 器官檔案錨點
        for (final o in store.organs(includeRetired: true)) {
          final orgRules =
              store.rules(organId: o.id, includeRetired: true);
          if (orgRules.any((r) => r.id == rid)) {
            for (final p in o.facts.paths) {
              buf.writeln('  📄 $p');
            }
          }
        }
      }
      buf.writeln();
    }
    buf.writeln('（不足？compass_seek?missing=... 升級索引；'
        '要全文 compass_read）');
    return AgentToolResult.success(buf.toString());
  }
}
