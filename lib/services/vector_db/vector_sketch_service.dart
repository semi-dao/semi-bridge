// vector_sketch_service.dart
// [小葵 2026-09-09 Blue 令] 「向量資料素描」——嵌入完成後分析全部檔案，
// 產出結構素描 MD 文檔，回寫 folder_origin（分類）與 topic_terms（關聯詞），
// 作為標籤與向量搜尋的結構基礎。
//
// 流程：
//  1. 掃 asset_index 全部檔案（含 audience 分層統計）
//  2. 依資料夾結構聚類（折疊日期段）→ 每群樣本摘要
//  3. 產出 MD 素描：資料庫住著誰、多少檔案、什麼主題、什麼結構
//  4. 回寫 folder_origin.category（規則推斷版 v2）
//  5. 回寫 topic_terms（品種→物種關聯——從同層兄弟資料夾推導）

import 'dart:convert';

import 'package:dio/dio.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart';

import '../brain_container/brain_database.dart';

class VectorSketchService {
  VectorSketchService._();
  static final VectorSketchService instance = VectorSketchService._();

  static const _sketchPath =
      '06_AI協作與知識庫/向量資料素描.md'; // 寫到知識庫根（記憶區）

  /// 執行素描。回傳 MD 全文。
  Future<String> run({bool writeBack = true}) async {
    final db = BrainDatabase.instance.db;
    final rows = db.select('''
      SELECT file_path, folder_root, file_ext, file_name, audience,
             summary, origin_kind, index_status
      FROM asset_index
    ''');

    // ── 1. 資料夾聚類（折疊日期段）──
    final dateRe = RegExp(r'^\d{4}[-_/]?\d{1,2}([-_/]?\d{1,2})?$');
    String fold(String folder) {
      final segs = folder
          .split('/')
          .where((s) => s.isNotEmpty && !dateRe.hasMatch(s.trim()))
          .toList();
      return segs.isEmpty ? folder : segs.join('/');
    }

    final groups = <String, _FolderStat>{};
    for (final r in rows) {
      final fp = r['file_path'] as String;
      final folder = fp.contains('/') ? fp.substring(0, fp.lastIndexOf('/')) : '';
      final key = fold(folder);
      final stat = groups.putIfAbsent(key, _FolderStat.new);
      stat.total++;
      final ext = (r['file_ext'] as String?) ?? '';
      if (['.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic'].contains(ext)) {
        stat.images++;
      } else if (['.md', '.txt', '.pdf', '.doc', '.docx'].contains(ext)) {
        stat.texts++;
      } else {
        stat.others++;
      }
      if (stat.sampleNames.length < 3) stat.sampleNames.add(r['file_name'] as String? ?? '');
    }

    // ── 2. 主題聚類（第一層）──
    final topLevels = <String, int>{};
    for (final e in groups.entries) {
      final top = e.key.contains('/') ? e.key.split('/').first : e.key;
      topLevels[top] = (topLevels[top] ?? 0) + e.value.total;
    }

    // ── 3. 產 MD ──
    final now = DateTime.now();
    final buf = StringBuffer();
    buf.writeln('# 向量資料素描');
    buf.writeln();
    buf.writeln('> 產出時間：$now · 自動分析 ${rows.length} 筆資產');
    buf.writeln('> 此素描由系統自動生成，描述這個向量資料庫「住著誰」。');
    buf.writeln('> 標籤與搜尋結構以此為基礎（folder_origin + topic_terms）。');
    buf.writeln();
    buf.writeln('## 總覽');
    buf.writeln();
    buf.writeln('| 授權根（第一層） | 檔案數 |');
    buf.writeln('|---|---|');
    final sortedTops = topLevels.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final t in sortedTops) {
      buf.writeln('| ${t.key} | ${t.value} |');
    }
    buf.writeln();
    buf.writeln('## 主題資料夾群（日期折疊後）');
    buf.writeln();
    buf.writeln('| 資料夾 | 總數 | 圖片 | 文字 | 範例 |');
    buf.writeln('|---|---|---|---|---|');
    final sortedGroups = groups.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    for (final g in sortedGroups.take(60)) {
      final sample = g.value.sampleNames.first;
      buf.writeln(
          '| ${g.key} | ${g.value.total} | ${g.value.images} | ${g.value.texts} | ${_trunc(sample, 24)} |');
    }
    buf.writeln();
    buf.writeln('## 品種/主題群推導（topic_terms 依據）');
    buf.writeln();
    // 同父層的兄弟資料夾名 → 該父層是「品種集合」
    final siblings = <String, List<String>>{};
    for (final g in groups.keys) {
      if (!g.contains('/')) continue;
      final parent = g.substring(0, g.lastIndexOf('/'));
      final child = g.substring(g.lastIndexOf('/') + 1);
      siblings.putIfAbsent(parent, () => []).add(child);
    }
    for (final e in siblings.entries) {
      if (e.value.length >= 3) {
        // 3+ 兄弟 → 品種集合
        buf.writeln('- **${e.key}** → ${e.value.length} 個子分類：${e.value.take(12).join('、')}');
      }
    }

    final md = buf.toString();

    // ── 4. 寫檔（知識庫 + 專案 docs）──
    try {
      final db2 = BrainDatabase.instance.db;
      // 寫入大腦記憶區（memories 資料夾）——讓素描本身可被搜尋
      // [小葵 2026-09-24] agent/source 是 NOT NULL 欄位——舊 INSERT 少帶，
      // 每次都 SqliteException(1299) 失敗（log 實錘）。補齊必填欄位。
      db2.execute(
        "INSERT OR REPLACE INTO memories (id, content, room, sub_category, "
            "  agent, source, importance, created_at, updated_at) VALUES "
            "('vector_sketch_auto', ?, 'sketch', '向量資料素描', "
            "  'xiaokui', 'vector_sketch', 3, ?, ?)",
        [md, now.millisecondsSinceEpoch, now.millisecondsSinceEpoch],
      );
    } catch (e) {
      debugPrint('[VectorSketch] memories 寫入失敗: $e');
    }
    try {
      // [小葵 2026-09-25 開源整備] 原寫死 ~/Developer/bridge_app/docs/——
      // 開發者機器沒這路徑，會憑空創目錄。改寫到使用者自己的 AppSupport
      // 知識庫（跨平台、無中文檔名 git 混亂），repo 的 docs/ 只留匯出範本。
      final supportDir = await getApplicationSupportDirectory();
      final f = File(p.join(supportDir.path, 'sketch', 'vector_sketch.md'));
      await f.create(recursive: true);
      await f.writeAsString(md);
      debugPrint('[VectorSketch] ✅ 素描寫檔 ${f.path}');
    } catch (e) {
      debugPrint('[VectorSketch] docs 寫檔失敗: $e');
    }

    // ── 5. 回寫 folder_origin.category（v2 規則）──
    if (writeBack) {
      var updated = 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      for (final g in groups.entries) {
        // 群可能還不在 folder_origin（素描先於 backfill 跑時）——先補行
        db.execute(
          "INSERT OR IGNORE INTO folder_origin "
          "(folder_path, root, category, summary, origin_kind, task_id, updated_at) "
          "VALUES (?, ?, NULL, NULL, 'user', NULL, ?)",
          [g.key, g.key.split('/').first, nowMs],
        );
        final cat = _categorize(g.key, g.value);
        if (cat != null) {
          db.execute(
            "UPDATE folder_origin SET category = ? WHERE folder_path = ? AND "
            "  (category IS NULL OR category != ?)",
            [cat, g.key, cat],
          );
          updated++;
        }
      }
      debugPrint('[VectorSketch] folder_origin 分類回寫 $updated 群');

      // topic_terms：兄弟品種 → 共同主題詞
      var termsWritten = 0;
      for (final e in siblings.entries) {
        if (e.value.length < 3) continue;
        final parentLast = e.key.split('/').last;
        for (final child in e.value) {
          final related = jsonEncode(
              [parentLast, ...e.value.where((c) => c != child).take(8)],
              );
          db.execute(
            "INSERT OR REPLACE INTO topic_terms (term, related, updated_at) "
            "VALUES (?, ?, ?) ON CONFLICT(term) DO UPDATE SET "
            "  related=excluded.related, updated_at=excluded.updated_at "
            "  WHERE topic_terms.updated_at < excluded.updated_at",
            [child, related, now.millisecondsSinceEpoch],
          );
          termsWritten++;
        }
      }
      debugPrint('[VectorSketch] topic_terms 回寫 $termsWritten 筆');
    }

    // [小葵 2026-09-09 Blue 令] LLM 蒸餾層——規則版先跑完，分不出來
    // 的群才交給本地 Gemma 讀樣本補分類（fail-open：LLM 掛了素描照常）
    if (writeBack) {
      try {
        await _distillWithLlm(groups);
      } catch (e) {
        debugPrint('[VectorSketch] LLM 蒸餾跳過（fail-open）: $e');
      }
    }

    return md;
  }

  /// [小葵 2026-09-09 Blue 令] LLM 蒸餾——規則版分類不到的群，
  /// 讓本地 Gemma 讀資料夾路徑＋樣本檔名，產出簡潔分類。
  /// 冪等：只碰 category IS NULL 的群；速率控制：每批 20 群，
  /// 每批間隔 500ms（不跟嵌入搶本地模型）。
  Future<void> _distillWithLlm(Map<String, _FolderStat> groups) async {
    final db = BrainDatabase.instance.db;
    // 只處理規則版沒分到的——兩個來源：
    // 1. 本輪素描的群（日期折疊 key）
    // 2. folder_origin 既有行 category 空/NULL 的（真實路徑，如
    //    backfill 建的根層行——素描折疊 key 對不到它們）
    final unclassified = <String>{};
    for (final g in groups.keys) {
      final row = db.select(
        "SELECT category FROM folder_origin WHERE folder_path = ?",
        [g],
      );
      final cat = row.isEmpty ? null : (row.first['category'] as String?);
      if (cat == null || cat.isEmpty) {
        unclassified.add(g);
      }
    }
    for (final row in db.select(
        "SELECT folder_path FROM folder_origin "
        "WHERE category IS NULL OR category = ''")) {
      unclassified.add(row['folder_path'] as String);
    }
    if (unclassified.isEmpty) return;
    debugPrint('[VectorSketch] LLM 蒸餾：${unclassified.length} 群待分類');

    const batchSize = 10;
    for (var i = 0; i < unclassified.length; i += batchSize) {
      final batch = unclassified.skip(i).take(batchSize).toList();
      // [小葵 2026-09-09] 既有 folder_origin 行不在本輪 groups map——
      // groups[g]! 直接炸（null check）被外層 fail-open 吞掉。防 null。
      final listing = batch
          .map((g) {
            final st = groups[g];
            final samples = st == null
                ? ''
                : '（樣本：${st.sampleNames.take(3).join('、')}）';
            return '- $g$samples';
          })
          .join('\n');
      final prompt = '以下是檔案庫的資料夾清單（含樣本檔名）。'
          '請為每個資料夾下一個簡潔的繁體中文分類標籤（2-6字，'
          '例如「鹿角蕨品種照」「工程報價單」「IG圖文素材」）。'
          '只輸出清單，每行格式：資料夾路徑|分類\n\n$listing';

      try {
        final resp = await Dio().post(
          'http://127.0.0.1:18789/v1/chat/completions',
          options: Options(
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 300),
          ),
          data: {
            'model': 'gemma-4-e4b',
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
            'stream': false,
            'max_tokens': 2500,
            'temperature': 0.2,
          },
        );
        // [小葵 2026-09-09] Gemma 是推理模型——正式答案常在
        // reasoning_content 尾部（content 可能空）；兩邊都讀，取能
        // parse 出「路徑|分類」行的那份
        final msg = resp.data['choices'][0]['message'] as Map<String, dynamic>;
        var text = (msg['content'] as String?) ?? '';
        if (!text.contains('|')) {
          text = (msg['reasoning_content'] as String?) ?? text;
        }
        var applied = 0;
        for (final line in text.split('\n')) {
          final m = RegExp(r'^(.+?)\|(.+)$').firstMatch(line.trim());
          if (m == null) continue;
          final path = m.group(1)!.trim();
          final cat = m.group(2)!.trim();
          if (cat.isEmpty || cat.length > 12) continue;
          if (!batch.any((b) => b == path || b.endsWith(path))) continue;
          db.execute(
            "UPDATE folder_origin SET category = ? WHERE folder_path = ? "
            "  AND (category IS NULL OR category = '')",
            [cat, batch.firstWhere((b) => b == path || b.endsWith(path),
                orElse: () => path)],
          );
          applied++;
        }
        debugPrint('[VectorSketch] LLM 批次 $i~${i + batch.length}：套用 $applied 分類');
      } catch (e) {
        debugPrint('[VectorSketch] LLM 批次失敗（跳過續跑）: $e');
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  String _trunc(String s, int n) =>
      s.length > n ? '${s.substring(0, n)}…' : s;

  /// v2 分類規則——依群統計特徵
  String? _categorize(String folder, _FolderStat st) {
    final f = folder.toLowerCase();
    if (f.contains('照片紀錄') || f.contains('inspection')) {
      if (st.images > st.texts * 5) return '植物照護紀錄照';
      return '照片紀錄';
    }
    if (f.contains('ig') || f.contains('發想')) return 'IG 內容';
    if (f.contains('巡查')) return '巡查筆記';
    if (f.contains('鹿角蕨')) return '鹿角蕨';
    if (f.contains('合約') || f.contains('contracts')) return '區塊鏈合約';
    if (f.contains('企劃') || f.contains('規劃')) return '企劃文件';
    if (st.images > st.total * 0.8) return '圖像素材';
    if (st.texts > st.total * 0.8) return '文件';
    return null;
  }
}

class _FolderStat {
  int total = 0;
  int images = 0;
  int texts = 0;
  int others = 0;
  final List<String> sampleNames = [];
}
