// galaxy_data_service.dart
// 大腦圖譜 3D 星系模式 — 資料匯出服務
// [小葵 2026-08-27] 從 brain_container.db 撈 memories + asset_index，
// 吐成單包 JSON 餵給 webview 裡的 three.js 星系頁。
// 資料形狀與外部版（/tmp/three_galaxy）完全一致——同一顆星系，搬進 App。
//
// 設計：
// - 記憶節點：非 observation 全量（背景塵埃 2026-08-28 起不顯示）
// - 檔案星：asset_index 全量（每檔一星），附 embedding 時才有語意位置；
//   沒 embedding 的用主題群中心 + 隨機擾動（naive 佈局，未來升級 UMAP 快取）
// - 佈境（UMAP 結果）目前由外部預計算匯入（galaxy_layout.json，放 assets）；
//   沒有佈局檔時 fallback 到主題分群定位——保證任何機器第一次跑就有畫面

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:sqlite3/sqlite3.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../vector_db/vector_sketch_service.dart'; // [小葵 2026-10-14] 星系 junk 過濾（第四層）
import 'package:flutter/services.dart' show rootBundle;
import 'brain_database.dart';
import '../collab/swarm_campaign.dart'; // [TRIO M5a] 戰爭層
import '../collab/agent_status_store.dart'; // [TRIO M5a] 狀態真相源
import '../companion_store.dart'; // [TRIO M5a] 軍官=活躍夥伴
// [小葵 2026-08-28] 雙擊開檔：file_path 由 MCP /galaxy_open 端點查 DB 後開啟，
// JSON 不帶絕對路徑（避免洩漏完整路徑到 webview）

class GalaxyDataService {
  static Map<String, dynamic>? _cache;
  static DateTime? _cacheAt;
  static const _cacheTtl = Duration(seconds: 30);

  /// 取得星系資料包（webview 直接 fetch 的 JSON）
  static Future<Map<String, dynamic>> getGalaxyData() async {
    if (_cache != null &&
        _cacheAt != null &&
        DateTime.now().difference(_cacheAt!) < _cacheTtl) {
      return _cache!;
    }
    // [v194 小葵 脈衝根治令] 符號解碼實錘：getGalaxyData 的 DB 大查詢
    // （6.6k 星+數萬連線）在 main thread 同步執行=Blue 看到的 261ms 脈衝。
    // 根治：整段查詢+組裝搬進 background isolate（worker 自開唯讀連線，
    // WAL 模式官方支援多連線並行讀）。main thread 從此零 DB 時間。
    final _dbPath = BrainDatabase.dbPath;
    final _layout = await _loadLayout(); // [v194] rootBundle 在 main isolate 載
    final _r = await Isolate.run(() => _queryGalaxyAll(_dbPath, _layout));
    final nodes = _r['nodes']!;
    final edges = _r['edges']!;
    final files = _r['files']!;
    final fileLinks = _r['file_links']!;
    final taskLinks = _r['task_links']!;
    final causalLinks = _r['causal_links']!;
    final memAssetLinks = _r['mem_asset_links']!;

    _cache = {
      'nodes': nodes,
      'edges': edges,
      'files': files,
      'file_links': fileLinks,
      'task_links': taskLinks,
      'causal_links': causalLinks,
      'mem_asset_links': memAssetLinks,
      'swarm': _swarmSection(), // [TRIO M5a] 戰爭層——軍官恆星/帶兵星/指揮鏈
      'generatedAt': DateTime.now().toIso8601String(),
    };
    _cacheAt = DateTime.now();
    return _cache!;
  }

  /// [TRIO M5a] 輕量戰況直取（swarmonly 端點用——繞過 30s cache 與 DB）
  static Map<String, dynamic>? swarmNow() => _swarmSection();

  /// [TRIO M5a 2026-09-23] 蜂群戰爭層——從 SwarmCommand/AgentStatusStore
  /// 組即時戰況（不經 cache——狀態必須新鮮，戰場不等 30 秒 TTL）。
  ///
  /// 形狀：
  /// ```json
  /// {
  ///   "campaign": {"id": "...", "objective": "...", "phase": "running"},
  ///   "officers": [{"id": "...", "name": "研究軍", "state": "live",
  ///                 "pos": [x, y, z], "troops": 10}],
  ///   "troops":   [{"id": "...", "legion": "研究軍", "state": "live",
  ///                 "pos": [x,y,z]}],
  ///   "chains":   [[officerIdx, troopIdx], ...]
  /// }
  /// ```
  /// 座標：軍官落在既有記憶球叢附近（用地圖 seed 偏移），
  /// 帶兵星繞軍官軌道散布——星系裡「一群星跟著恆星動」。
  static Map<String, dynamic>? _swarmSection() {
    try {
      final cmd = SwarmCommand.instance;
      final c = cmd.active;
      if (c == null) return null;
      final statusStore = AgentStatusStore.instance;

      // G3 計畫解析不到軍團結構時（plan 是自由文字），退回單軍官全兵
      final officers = <Map<String, dynamic>>[];
      final troops = <Map<String, dynamic>>[];
      final chains = <List<int>>[];

      // 軍官=活躍夥伴（TRIO 三人）；位置用 golden-angle 環繞星系核心
      final companions = CompanionStore().all;
      for (var i = 0; i < companions.length; i++) {
        final comp = companions[i];
        final st = statusStore.statusOf(comp.id);
        final ang = i * 2.399963; // golden angle
        final r = 900.0 + (i % 3) * 260;
        officers.add({
          'id': comp.id,
          'name': '${comp.name}（軍官）',
          'state': st?.state.name ?? 'exited',
          'detail': st?.detail ?? '',
          'pos': [
            (r * cos(ang)).round(),
            (120 + i * 90).round(),
            (r * sin(ang)).round(),
          ],
          'troops': c.phase == SwarmPhase.running ? 10 : 0,
        });
      }

      // 帶兵星：running/committed 期顯示（每軍官 10 顆）——
      // 狀態先用哨兵（頁面端以 officer state 驅動呼吸），
      // 真實 per-troop 狀態待 M4 執行層細化後接入
      if (c.phase == SwarmPhase.committed || c.phase == SwarmPhase.running) {
        for (var o = 0; o < officers.length; o++) {
          final off = officers[o];
          for (var t = 0; t < 10; t++) {
            final ang = t * 0.628 + o; // 環繞軍官
            troops.add({
              'id': 'troop-${off['id']}-$t',
              'legion': off['name'],
              'legionIdx': o,
              'state': off['state'],
              'pos': [
                ((off['pos'] as List)[0] as num).toDouble() +
                    (170 * cos(ang)),
                ((off['pos'] as List)[1] as num).toDouble() - 40 + t * 9,
                ((off['pos'] as List)[2] as num).toDouble() +
                    (170 * sin(ang)),
              ],
            });
            chains.add([o, troops.length - 1]);
          }
        }
      }

      return {
        'campaign': {
          'id': c.id,
          'objective': c.objective,
          'phase': c.phase.name,
          'gates': c.gatesPassed,
        },
        'officers': officers,
        'troops': troops,
        'chains': chains,
      };
    } catch (e) {
      // 戰爭層失敗不拖垮星系（fail-open——星系照轉，只是沒有戰況）
      return null;
    }
  }


  /// [v194] 背景 isolate 執行——唯讀連線查整包星系資料。
  /// 跑在 worker isolate：自開 ro 連線（WAL 並行讀安全）、查完即關。
  static Map<String, dynamic> _queryGalaxyAll(String dbPath, Map<String, Map<String, dynamic>>? layoutIn) {
    final db = sqlite3.open('file:' + dbPath + '?mode=ro', uri: true); // [v194] 唯讀 URI 連線（WAL 並行讀）

      // ── 記憶節點 ──
      final realMem = db.select('''
        SELECT id, room, sub_category, importance, access_count,
               replace(substr(content, 1, 40), char(10), ' ') AS txt,
               length(content) AS clen,
               CASE WHEN created_at > 1600000000000 AND created_at < 2000000000000
                    THEN created_at ELSE 0 END AS cat
        FROM memories WHERE sub_category != 'observation' AND archived = 0
      '''); // [Blue 時間忠實令 2026-08-29] cat=記憶誕生時間——房間節點也要進時間之河
      // [Blue 2026-08-28] 背景塵埃（observation）不顯示——星系只留真實記憶節點
      final nodes = <Map<String, dynamic>>[
        ...realMem.map((r) => _memRow(r, false)),
      ];
      final nodeIds = nodes.map((n) => n['id']).toSet();

      // ── 結構邊 ──
      final connRows = db.select('''
        SELECT from_memory_id AS a, to_memory_id AS b
        FROM connections
      ''');
      final edges = <Map<String, dynamic>>[
        for (final r in connRows)
          if (nodeIds.contains(r['a']) && nodeIds.contains(r['b']))
            {'a': r['a'], 'b': r['b']},
      ];

      // ── 檔案星（asset_index 全量）──
      // [小葵 2026-10-14 Blue 報案「橘色新星暴增」] venv 依賴樹 junk（.h 19,952+
      // .py 19,510 顆）副檔名不在 EXT_COLOR 映射→落到預設橘 0xff9e6b——
      // 四萬顆對人類無意義的橘星。junk 在 SQL 層直接排除（第四層過濾：
      // 素描/顯示/fastScan 之後，星系層同規則 isJunkFolder）。
      final assetRows = db.select('''
        SELECT id,
          file_path,
          replace(substr(file_path, 1, instr(file_path || '/', '/') - 1), '|', '_') AS top,
          COALESCE(NULLIF(file_ext, ''), 'x') AS ext,
          file_size AS sz,
          COALESCE(NULLIF(display_title, ''), NULLIF(title, ''), file_name) AS name,
          file_name AS fname,
          substr(COALESCE(content_text, ''), 1, 400) AS chead,
          COALESCE(NULLIF(topic_cluster, ''), 'solo') AS topic,
          CASE WHEN file_modified > 1600000000000 AND file_modified < 2000000000000
               THEN file_modified ELSE 0 END AS mt
        FROM asset_index
      ''').where((r) =>
          !VectorSketchService.isJunkFolder(r['file_path'] as String? ?? ''));

      // ── 佈局：優先吃預計算的 UMAP 佈局檔（id → x,y,z）──
      final layout = layoutIn; // [v194] main isolate 預載傳入（rootBundle 不能跨 isolate）
      final rng = Random(42);
      // 主題 → 星團中心（固定種子 → 每次打開位置一致，不會「宇宙一直洗牌」）
      final topicCenter = <String, List<double>>{};
      int ci = 0;
      for (final r in assetRows) {
        final t = r['topic'] as String? ?? 'solo';
        if (t == 'solo') continue;
        if (!topicCenter.containsKey(t)) {
          final th = (ci * 2.399963) % (2 * pi); // 黃金角分佈
          final r0 = 900.0 + (ci % 7) * 260;
          topicCenter[t] = [cos(th) * r0, sin(ci * 1.7) * 300.0, sin(th) * r0];
          ci++;
        }
      }

      final files = <Map<String, dynamic>>[
        for (final r in assetRows)
          () {
            final id = r['id'] as String;
            final topic = r['topic'] as String? ?? 'solo';
            Map<String, dynamic> pos;
            if (layout != null && layout.containsKey(id)) {
              pos = layout[id]!;
            } else if (topic != 'solo' && topicCenter.containsKey(topic)) {
              final c = topicCenter[topic]!;
              pos = {
                'x': c[0] + (rng.nextDouble() - .5) * 420,
                'y': c[1] + (rng.nextDouble() - .5) * 300,
                'z': c[2] + (rng.nextDouble() - .5) * 420,
              };
            } else {
              // solo / 無主題 → 外圍星塵殼
              final th = rng.nextDouble() * 2 * pi;
              final ph = acos(2 * rng.nextDouble() - 1);
              final r0 = 2300.0 + rng.nextDouble() * 1700;
              pos = {
                'x': r0 * sin(ph) * cos(th),
                'y': r0 * cos(ph) * .6,
                'z': r0 * sin(ph) * sin(th),
              };
            }
            return {
              'id': id,
              if (layout != null && layout.containsKey(id)) 'L': 1, // 真語意座標
              ...pos,
              't': topic.substring(0, topic.length > 16 ? 16 : topic.length),
              's': (r['sz'] as int?) ?? 0,
              'n': ((r['name'] as String?) ?? '').substring(
                  0, min(24, ((r['name'] as String?) ?? '').length)),
              'e': r['ext'] as String? ?? 'x',
              'm': _realBornAt(r['fname'] as String? ?? '',
                  r['chead'] as String? ?? '',
                  (r['mt'] as int?) ?? 0), // [小葵 2026-08-28 v9] 真實誕生日（內文日期優先）
              'c': _cleanChead(r['chead'] as String? ?? ''), // [v14] 內文摘要（點擊簡介卡）
            };
          }(),
      ];

      // ── 檔案星細線：同主題 2 近鄰（只連 UMAP 真座標的星；solo 隨機殼不連=不做假結構）──
      final fileLinks = <List<int>>[];
      {
        final groups = <String, List<int>>{};
        for (var i = 0; i < files.length; i++) {
          final f = files[i];
          if (f['L'] != 1) continue;
          final t = f['t'] as String;
          if (t == 'solo') continue;
          groups.putIfAbsent(t, () => []).add(i);
        }
        const k = 2, maxDist = 420.0; // 距離上限：避免橋接同主題的遠島
        for (final idxs in groups.values) {
          for (final i in idxs) {
            final best = <int>[]; final bestD = <double>[];
            for (final j in idxs) {
              if (i == j) continue;
              final dx = (files[i]['x'] as num).toDouble() - (files[j]['x'] as num).toDouble();
              final dy = (files[i]['y'] as num).toDouble() - (files[j]['y'] as num).toDouble();
              final dz = (files[i]['z'] as num).toDouble() - (files[j]['z'] as num).toDouble();
              final d2 = dx*dx + dy*dy + dz*dz;
              if (d2 > maxDist * maxDist) continue;
              if (best.length < k) {
                best.add(j); bestD.add(d2);
              } else {
                var worst = 0;
                for (var w = 1; w < k; w++) { if (bestD[w] > bestD[worst]) worst = w; }
                if (d2 < bestD[worst]) { best[worst] = j; bestD[worst] = d2; }
              }
            }
            for (final j in best) {
              final key = i < j ? '$i-$j' : '$j-$i';
              if (!fileLinks.any((l) => '${l[0]}-${l[1]}' == key)) {
                fileLinks.add(i < j ? [i, j] : [j, i]);
              }
            }
          }
        }
      }

      // ── [小葵 2026-08-28 Blue 排程/因果開工令] 語意線三種 ──
      // assetId → files index（只連看得到的星）
      final byId = <String, int>{};
      for (var i = 0; i < files.length; i++) {
        byId[files[i]['id'] as String] = i;
      }
      // ① 生產線：排程任務 → 產出檔案（青色虛線）
      final taskLinks = <List<int>>[];
      {
        final rows = db.select('''
          SELECT tal.asset_id AS aid FROM task_asset_links tal
        ''');
        for (final r in rows) {
          final i = byId[r['aid'] as String?];
          if (i != null) taskLinks.add([i]);
        }
      }
      // ② 因果鏈：cause → effect（橘色箭頭線）
      final causalLinks = <List<int>>[];
      {
        final rows = db.select('''
          SELECT cause_id AS a, effect_id AS b FROM asset_causal_links
        ''');
        for (final r in rows) {
          final i = byId[r['a'] as String?];
          final j = byId[r['b'] as String?];
          if (i != null && j != null && i != j) causalLinks.add([i, j]);
        }
      }
      // ③ 記憶→檔案引用線（紫色，memory_asset_links 既有 1,371 條）
      final memAssetLinks = <List<int>>[];
      {
        final rows = db.select('''
          SELECT mal.asset_id AS aid, mal.memory_id AS mid
          FROM memory_asset_links mal
          JOIN memories m ON m.id = mal.memory_id
        ''');
        final memIdx = <String, int>{};
        for (var i = 0; i < nodes.length; i++) {
          final nid = nodes[i]['id'] as String?;
          if (nid != null) memIdx[nid] = i;
        }
        // 節點 index 偏移：files 在 nodes 之後（galaxy.html 用全域 index）
        for (final r in rows) {
          final fi = byId[r['aid'] as String?]; // files index
          final mi = memIdx[r['mid'] as String?]; // nodes index
          if (fi != null && mi != null) memAssetLinks.add([mi, fi]);
        }
      }


    return {
      'nodes': nodes,
      'edges': edges,
      'files': files,
      'file_links': fileLinks,
      'task_links': taskLinks,
      'causal_links': causalLinks,
      'mem_asset_links': memAssetLinks,
    };
  }

  static Map<String, dynamic> _memRow(dynamic r, bool dust) => {
        'id': r['id'],
        'room': r['room'] ?? '',
        'sub': r['sub_category'],
        'cat': r['cat'] ?? 0, // [Blue 時間忠實令] 記憶誕生時間（ms epoch）
        'importance': r['importance'] ?? 1,
        'acc': r['access_count'] ?? 0,
        'txt': r['txt'] ?? '',
        'clen': r['clen'] ?? 0,
        if (dust) 'dust': true,
      };

  /// 預計算 UMAP 佈局（assets/galaxy/galaxy_layout.json）。
  /// 沒有 → null → fallback 主題分群。未來可改為背景重算後落盤。
  static Map<String, Map<String, dynamic>>? _layoutCache;
  static Future<Map<String, Map<String, dynamic>>?> _loadLayout() async {
    if (_layoutCache != null) return _layoutCache;
    try {
      final raw = await rootBundle.loadString('assets/galaxy/galaxy_layout.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _layoutCache = decoded.map((k, v) =>
          MapEntry(k, (v as Map).cast<String, dynamic>()));
      debugPrint('[Galaxy] UMAP 佈局載入：${_layoutCache!.length} 星');
    } catch (_) {
      debugPrint('[Galaxy] 無佈局檔 → 主題分群 fallback');
      _layoutCache = {}; // 標記已嘗試，避免每次都 re-try
    }
    return _layoutCache;
  }

  static void invalidateCache() {
    _cache = null;
    _cacheAt = null;
  }

  /// 產生 UMAP 佈局檔（給外部工具鏈用：把 asset embedding 投影落盤）
  /// 佈局檔格式：{ assetId: {x, y, z} }
  static Future<void> exportLayoutTemplate() async {
    final db = BrainDatabase.instance.db;
    final rows = db.select('SELECT id FROM asset_index');
    final f = File('/tmp/galaxy_layout_template.json');
    await f.writeAsString(jsonEncode({
      for (final r in rows)
        r['id'] as String: {'x': 0.0, 'y': 0.0, 'z': 0.0}
    }));
    debugPrint('[Galaxy] 佈局模板已寫 /tmp/galaxy_layout_template.json');
  }

  /// [小葵 2026-08-28 v8] 真實誕生日：檔名尾日期（如 "農場日記 08/21"、"daily-reflection 08/20"）
  /// 優先於匯入時間（mtime）——Blue：檔案被嵌入過、內容有日期，不該爆量同時誕生。
  /// 模式：MM/DD 或 M/D（允許尾端）；年份取 mtime 同年，若解析出的日期晚於 mtime
  /// 則回退前一年（避免未來日期）。解析失敗回傳 mtime。
    static String _cleanChead(String raw) {
    final c = raw
        .replaceAll(RegExp('[#*>`\n\r]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return c.length > 240 ? c.substring(0, 240) : c;
  }

static int _realBornAt(String fname, String chead, int mtime) {
    if (mtime <= 0) return mtime;
    // ① 檔名 ISO 前綴：2026-08-20_農場日記.md
    var m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(fname);
    // ② 內文 ISO 日期（開頭 400 字）：# 2026-08-20 農場日記…
    m ??= RegExp(r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(chead);
    if (m == null) return mtime;
    final y = int.tryParse(m.group(1)!);
    final mm = int.tryParse(m.group(2)!);
    final dd = int.tryParse(m.group(3)!);
    if (y == null || mm == null || dd == null) return mtime;
    if (y < 2000 || y > 2100 || mm < 1 || mm > 12 || dd < 1 || dd > 31) return mtime;
    final cand = DateTime(y, mm, dd);
    final mt = DateTime.fromMillisecondsSinceEpoch(mtime);
    if (cand.isAfter(mt.add(const Duration(days: 1)))) return mtime; // 未來→不可信
    return cand.millisecondsSinceEpoch;
  }
}
