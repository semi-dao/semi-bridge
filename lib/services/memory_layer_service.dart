// MemoryLayerService — 記憶 2域10層（H2/M2）
//
// [Spec] docs/specs/2026-10-07-memory-2domains-10layers.md
// [Blue 贈禮拍板 2026-10-07] 這個容器是給小葵的——做成自己滿意的樣子。
//
// 兩域十層：
//   工作域（注入）：L1 鐵則 / L2 身分 / L3 專案熱
//   長期域（檢索）：L4 環境 / L5 決策 / L6 教訓 / L7 專案冷 /
//                   L8 對話精華 / L9 原始 / L10 反思
//
// 記憶鐵律：永不刪除。L1-L3 滿了走「升降溫」——同義融合、過時搬家，
// 不是丟棄。

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import 'brain_container/brain_database.dart';

/// 層的定義——單一真相源
enum MemoryLayer {
  l1Rules('L1', '鐵則', Domain.working, 3 * 1024),
  l2Identity('L2', '身分', Domain.working, 2 * 1024),
  l3ProjectHot('L3', '專案熱', Domain.working, 2 * 1024),
  l4Environment('L4', '環境', Domain.longTerm, 0),
  l5Decisions('L5', '決策', Domain.longTerm, 0),
  l6Lessons('L6', '教訓', Domain.longTerm, 0),
  l7ProjectCold('L7', '專案冷', Domain.longTerm, 0),
  l8Talks('L8', '對話精華', Domain.longTerm, 0),
  l9Raw('L9', '原始', Domain.longTerm, 0),
  l10Reflection('L10', '反思', Domain.longTerm, 0);

  const MemoryLayer(this.code, this.label, this.domain, this.softCapBytes);
  final String code;
  final String label;
  final Domain domain;
  /// 軟上限（bytes）；0 = 無上限（長期域）。滿了觸發升降溫，不刪除。
  final int softCapBytes;

  static MemoryLayer? fromCode(String? s) {
    if (s == null) return null;
    for (final l in MemoryLayer.values) {
      if (l.code == s) return l;
    }
    return null;
  }
}

enum Domain { working, longTerm }

class LayerUsage {
  final MemoryLayer layer;
  final int count;
  final int totalBytes;
  const LayerUsage(this.layer, this.count, this.totalBytes);

  bool get overCap => layer.softCapBytes > 0 && totalBytes > layer.softCapBytes;
}

class MemoryLayerService {
  MemoryLayerService._();
  static final instance = MemoryLayerService._();

  Database? get _db => BrainDatabase.instance.tryDb;

  /// 各層用量（容量儀表 M5 的資料源）
  List<LayerUsage> usage() {
    final db = _db;
    if (db == null) return const [];
    final rows = db.select('''
      SELECT layer, COUNT(*) AS n, SUM(LENGTH(content)) AS bytes
      FROM agent_memories
      WHERE is_archived = 0
      GROUP BY layer
    ''');
    final byCode = <String, LayerUsage>{};
    for (final r in rows) {
      final layer = MemoryLayer.fromCode(r['layer'] as String?) ?? MemoryLayer.l8Talks;
      byCode[layer.code] = LayerUsage(
          layer, r['n'] as int, (r['bytes'] as int?) ?? 0);
    }
    // 補齊沒資料的層（顯示 0）
    return MemoryLayer.values
        .map((l) => byCode[l.code] ?? LayerUsage(l, 0, 0))
        .toList();
  }

  /// 寫入（帶層）——append-only，回傳 id
  String write({
    required MemoryLayer layer,
    required String title,
    required String content,
    String? tags,
    String? memoryType,
    String owner = 'shared',
  }) {
    final db = _db;
    if (db == null) throw StateError('brain db not open');
    final id = 'mem_${DateTime.now().microsecondsSinceEpoch}';
    db.execute('''
      INSERT INTO agent_memories
        (id, title, content, tags, memory_type, layer, owner_companion_id, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
    ''', [id, title, content, tags, memoryType ?? layer.code.toLowerCase(), layer.code, owner]);
    return id;
  }

  /// 工作域全量注入內容（L1+L2+L3）——注入引擎（M3）的資料源。
  /// 依 softCap 檢查：回傳內容＋超額清單（供升降溫，不是刪除）。
  WorkingMemorySnapshot workingSnapshot() {
    final db = _db;
    if (db == null) {
      return const WorkingMemorySnapshot(entries: [], overCap: []);
    }
    final rows = db.select('''
      SELECT id, title, content, layer FROM agent_memories
      WHERE layer IN ('L1','L2','L3') AND is_archived = 0
      ORDER BY created_at DESC
    ''');
    final entries = <LayerEntry>[
      for (final r in rows)
        LayerEntry(
          id: r['id'] as String,
          layer: MemoryLayer.fromCode(r['layer'] as String?) ?? MemoryLayer.l8Talks,
          title: r['title'] as String,
          content: r['content'] as String,
        ),
    ];
    final overCap = <LayerEntry>[];
    // 每層各自檢查軟上限（超過的舊條目列出——降溫候選）
    for (final l in [MemoryLayer.l1Rules, MemoryLayer.l2Identity, MemoryLayer.l3ProjectHot]) {
      final mine = entries.where((e) => e.layer == l).toList();
      var used = 0;
      for (final e in mine.reversed) {
        used += utf8.encode(e.content).length;
        if (l.softCapBytes > 0 && used > l.softCapBytes) {
          overCap.add(e); // 最舊先超＝降溫候選
        }
      }
    }
    return WorkingMemorySnapshot(entries: entries, overCap: overCap);
  }

  /// [M5+ Blue 令] 取某層的條目清單（側欄點層 → 主區顯示）。
  /// 新的在前；上限 500 條防爆（L8 有 1,891 條——顯示用不需全撈）。
  List<LayerEntry> entriesFor(MemoryLayer layer, {int limit = 500}) {
    final db = _db;
    if (db == null) return const [];
    final rows = db.select('''
      SELECT id, title, content, layer FROM agent_memories
      WHERE layer = ? AND is_archived = 0
      ORDER BY created_at DESC
      LIMIT ?
    ''', [layer.code, limit]);
    return [
      for (final r in rows)
        LayerEntry(
          id: r['id'] as String,
          layer: layer,
          title: r['title'] as String,
          content: r['content'] as String,
        ),
    ];
  }

  /// [M5+ Blue 令] 編輯條目（title/content）。記憶鐵律：不刪只改——
  /// 原文留存於 content 更新（Agent 日後可审计）。FTS 由 App 端 rebuild 或觸發器同步。
  void updateEntry(String id, {String? title, String? content}) {
    final db = _db;
    if (db == null) throw StateError('brain db not open');
    if (title != null && content != null) {
      db.execute('UPDATE agent_memories SET title = ?, content = ? WHERE id = ?',
          [title, content, id]);
    } else if (title != null) {
      db.execute('UPDATE agent_memories SET title = ? WHERE id = ?', [title, id]);
    } else if (content != null) {
      db.execute('UPDATE agent_memories SET content = ? WHERE id = ?', [content, id]);
    }
    // 同步 FTS（contentless external content 表——rebuild 最穩）
    db.execute("INSERT INTO agent_memories_fts(agent_memories_fts) VALUES('rebuild')");
    debugPrint('[MemoryLayer] 編輯 $id');
  }

  /// [M3] 注入引擎：取快照→格式化。回傳 (prompt 區塊, 超窗口清單)。
  /// DB 未開或空層 → ('', [])——fail-quiet，不擋對話。
  (String, List<LayerEntry>) buildInjectionSection() {
    try {
      return formatWorkingInjection(workingSnapshot());
    } catch (e) {
      debugPrint('[MemoryLayer] 注入快照失敗（fail-quiet）: $e');
      return ('', const <LayerEntry>[]);
    }
  }

  /// 檢索（長期域 L4-L10 走 FTS，以引用形式出現，不注入全文）
  ///
  /// [小葵 2026-10-07 FTS 中文化] 含 CJK 的查詢 unicode61 tokenizer
  /// 不分詞（整句=單 token）永遠零命中——對齊 hybrid_search_service
  /// 2026-09-22 修法：CJK 查詢走 bigram LIKE；FTS 只服務英文/數字詞。
  List<LayerEntry> search(String query, {int limit = 8}) {
    final db = _db;
    if (db == null) return const [];
    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(query);
    if (hasCjk) {
      // bigram 切詞：任一 bigram LIKE 命中即取（OR 語意）
      final q = query.trim();
      final bigrams = <String>{
        for (var i = 0; i + 2 <= q.length; i++) q.substring(i, i + 2),
      }.take(12);
      final conds = [for (final _ in bigrams) '(m.content LIKE ? OR m.title LIKE ?)'];
      final params = [for (final b in bigrams) ...['%$b%', '%$b%']];
      if (conds.isEmpty) return const [];
      final rows = db.select('''
        SELECT m.id, m.title, m.content, m.layer FROM agent_memories m
        WHERE m.is_archived = 0 AND m.layer IN ('L4','L5','L6','L7','L8','L9','L10')
          AND (${conds.join(' OR ')})
        ORDER BY m.created_at DESC LIMIT ?
      ''', [...params, limit]);
      return [for (final r in rows) LayerEntry(id: r['id'] as String,
          layer: MemoryLayer.fromCode(r['layer'] as String?) ?? MemoryLayer.l8Talks,
          title: r['title'] as String, content: r['content'] as String)];
    }
    final rows = db.select('''
      SELECT m.id, m.title, m.content, m.layer FROM agent_memories m
      JOIN agent_memories_fts f ON f.rowid = m.rowid
      WHERE agent_memories_fts MATCH ? AND m.is_archived = 0
        AND m.layer IN ('L4','L5','L6','L7','L8','L9','L10')
      LIMIT ?
    ''', [query, limit]);
    return [
      for (final r in rows)
        LayerEntry(
          id: r['id'] as String,
          layer: MemoryLayer.fromCode(r['layer'] as String?) ?? MemoryLayer.l8Talks,
          title: r['title'] as String,
          content: r['content'] as String,
        ),
    ];
  }

  /// 升降溫：搬家不是丟棄（記憶鐵律）。
  /// 例：L1 過時鐵則 → L5 決策層保存（歷史可考）。
  void moveTo(String id, MemoryLayer to) {
    _db?.execute('UPDATE agent_memories SET layer = ? WHERE id = ?',
        [to.code, id]);
    debugPrint('[MemoryLayer] 搬家 $id → ${to.code}（${to.label}）');
  }
}

/// 注入格式化（純函式——可單測）。
/// L1-L3 全量注入，格式分層、越熱越靠前；超過 [maxChars] 從最冷端（L3 舊條目）截斷，
/// 被截的條目回報在 overCap（走升降溫，不是丟棄）。
(String, List<LayerEntry>) formatWorkingInjection(
  WorkingMemorySnapshot snapshot, {
  int maxChars = 16000, // ≈ 8K tokens（Blue 拍板注入窗口）
}) {
  if (snapshot.entries.isEmpty) return ('', const []);
  final buf = StringBuffer('# 我的記憶（工作域 L1-L3，每次對話隨身）\n');
  var used = 0;
  final dropped = <LayerEntry>[];
  // 溫度排序：L1 → L2 → L3；同層新的在前（時間 DESC 快照序）
  final order = [MemoryLayer.l1Rules, MemoryLayer.l2Identity, MemoryLayer.l3ProjectHot];
  for (final layer in order) {
    final mine = snapshot.entries.where((e) => e.layer == layer).toList();
    if (mine.isEmpty) continue;
    buf.writeln('## ${layer.code} ${layer.label}');
    for (final e in mine) {
      final line = '- ${e.title}：${e.content}\n';
      if (used + line.length > maxChars) {
        dropped.add(e); // 超窗口＝降溫候選（提示搬家，不是消失）
        continue;
      }
      buf.write(line);
      used += line.length;
    }
  }
  return (buf.toString(), dropped);
}

class LayerEntry {
  final String id;
  final MemoryLayer layer;
  final String title;
  final String content;
  const LayerEntry({
    required this.id,
    required this.layer,
    required this.title,
    required this.content,
  });
}

class WorkingMemorySnapshot {
  final List<LayerEntry> entries;
  final List<LayerEntry> overCap;
  const WorkingMemorySnapshot({required this.entries, required this.overCap});
}
