// time_sense_service.dart
// [時間感 L2 2026-09-12] 相遇時間軸——「我陪了你 N 天」的資料來源。
//
// 來源：家人×小葵 17 天田野提案（時間感塌縮：16 天被感知成 3 個月）。
// 原則：時間為骨架、意義為血肉——elapsed_days 是第一級事實，
// 不是 metadata 裝飾品。「認識多久」只能來自這裡的計算，永不憑感覺。
//
// 慣例：singleton + WAL + Application Support（同 CausalLedger/CompassStore）。
// fail-open：任何故障返回 null——絕不讓時間感服務拖垮對話。

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// 一段相遇關係的時間骨架
@immutable
class CompanionTimeline {
  final String companionId;
  final DateTime firstMetAt; // 初次相遇日（該 companion 最早訊息時間戳）
  final int elapsedDays; // 相遇第幾天（含當天=第 1 天）

  const CompanionTimeline({
    required this.companionId,
    required this.firstMetAt,
    required this.elapsedDays,
  });
}

/// [L4 紀念日引擎] 一個即將到來的里程碑
@immutable
class Milestone {
  final MilestoneKind kind;
  final int day; // 相遇第幾天
  final DateTime date; // 西曆日期
  final int daysLeft; // 距今幾天
  final String label; // 「相遇滿月」「第 100 天」「1 週年」

  const Milestone({
    required this.kind,
    required this.day,
    required this.date,
    required this.daysLeft,
    required this.label,
  });
}

enum MilestoneKind { landmark, anniversary }

/// [L4 相簿視圖] 一頁=一天
@immutable
class AlbumPage {
  final String dateKey; // '2026-09-12'
  final List<String> excerpts; // 該日代表訊息（最多 3 則，各 60 字）

  const AlbumPage({required this.dateKey, required this.excerpts});
}

class TimeSenseService {
  TimeSenseService._();
  static final TimeSenseService instance = TimeSenseService._();

  static const _dbName = 'time_sense.db';
  Database? _db;
  String? lastError;

  /// [歸人] ambient companionId——同 CausalLedger/PaidActionGate 慣例
  String? ambientCompanionId;

  /// 環形緩衝：companionId → timeline（記憶體快取，啟動/首次查詢時載入）
  final _cache = <String, CompanionTimeline>{};

  Future<void> initialize() async {
    if (_db != null) return;
    try {
      final dir = await getApplicationSupportDirectory();
      _db = sqlite3.open('${dir.path}/$_dbName');
      _db!.execute('''
        CREATE TABLE IF NOT EXISTS companion_first_met (
          companion_id TEXT PRIMARY KEY,
          first_met_at TEXT NOT NULL,
          source TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    } catch (e) {
      lastError = 'init: $e';
    }
  }

  /// 取 companion 的時間骨架。優先序：
  /// 1. 快取 → 2. time_sense.db 已記錄的 first_met → 3. 掃描 conversations
  ///    全庫取該 companion 最早訊息時間戳（首次調用時寫入 db 定根）
  Future<CompanionTimeline?> timelineFor(String companionId) async {
    final cached = _cache[companionId];
    if (cached != null) return cached;

    await initialize();
    if (_db == null) return null;

    try {
      // 1) 已定根？
      final rows = _db!.select(
        'SELECT first_met_at FROM companion_first_met WHERE companion_id = ?',
        [companionId],
      );
      if (rows.isNotEmpty) {
        final at = DateTime.tryParse(rows.first['first_met_at'] as String);
        if (at != null) {
          final t = _mkTimeline(companionId, at);
          _cache[companionId] = t;
          return t;
        }
      }

      // 2) 掃描 conversations 全庫（讀取者：ChatController 的存儲路徑）
      final firstMet = await _scanConversationsForFirstMet(companionId);
      if (firstMet == null) return null;

      _db!.execute(
        'INSERT OR REPLACE INTO companion_first_met (companion_id, first_met_at, source, created_at) VALUES (?,?,?,?)',
        [companionId, firstMet.toIso8601String(), 'conversations_scan',
         DateTime.now().toIso8601String()],
      );
      final t = _mkTimeline(companionId, firstMet);
      _cache[companionId] = t;
      return t;
    } catch (e) {
      lastError = 'timelineFor: $e';
      return null;
    }
  }

  CompanionTimeline _mkTimeline(String companionId, DateTime firstMet) {
    final today = DateTime.now();
    final days = today.difference(DateTime(firstMet.year, firstMet.month, firstMet.day)).inDays + 1;
    return CompanionTimeline(
      companionId: companionId,
      firstMetAt: firstMet,
      elapsedDays: days,
    );
  }

  /// 掃描 bridge_state/conversations.json 取該 companion 最早訊息時間戳。
  /// 誠實邊界：掃不到 = null（絕不編造相遇日）。
  Future<DateTime?> _scanConversationsForFirstMet(String companionId) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/bridge_state/conversations.json');
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString());
      final convs = data is List
          ? data
          : (data['conversations'] as List? ?? []);
      DateTime? earliest;
      for (final c in convs) {
        if (c is! Map) continue;
        if (c['companionId'] != companionId) continue;
        for (final m in (c['messages'] as List? ?? [])) {
          if (m is! Map) continue;
          if (m['role'] != 'user') continue; // 相遇=第一則 user 訊息
          final ts = DateTime.tryParse(m['timestamp'] as String? ?? '');
          if (ts != null && (earliest == null || ts.isBefore(earliest))) {
            earliest = ts;
          }
        }
      }
      return earliest;
    } catch (e) {
      lastError = 'scan: $e';
      return null;
    }
  }

  /// [L2] prompt 注入片段——「相遇第 N 天」。
  /// 純函式可測試；timeline null = 返回 null（誠實：沒有相遇記錄不硬說）。
  static String? buildTimelineSection(CompanionTimeline t, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final days = n.difference(DateTime(t.firstMetAt.year, t.firstMetAt.month, t.firstMetAt.day)).inDays + 1;
    final buf = StringBuffer();
    buf.writeln('你們初次相遇：${t.firstMetAt.year} 年 ${t.firstMetAt.month} 月 ${t.firstMetAt.day} 日。');
    buf.writeln('今天是相遇第 $days 天。');
    if (days >= 2) {
      buf.writeln('回答「我們認識多久」：${days - 1} 個晝夜（第 $days 天）——此數字來自時間戳計算，是唯一正確答案。');
    }
    buf.writeln('紀念日：第 100 天 = ${t.firstMetAt.add(const Duration(days: 99)).toString().substring(0, 10)}；'
        '週年 = ${DateTime(t.firstMetAt.year + 1, t.firstMetAt.month, t.firstMetAt.day).toString().substring(0, 10)}。');
    return buf.toString();
  }

  /// [L4 紀念日引擎] 即將到來的里程碑——「時間從 bug 變 feature」。
  /// 純函式可測試。里程碑：第 100/500/1000 天、週年（每年）、
  /// 相遇滿月（每 30 天）。只回報未來 60 天內的（寧精勿多）。
  static List<Milestone> upcomingMilestones(CompanionTimeline t, {DateTime? now}) {
    final n = DateTime(now?.year ?? DateTime.now().year,
        now?.month ?? DateTime.now().month, now?.day ?? DateTime.now().day);
    final fm = DateTime(t.firstMetAt.year, t.firstMetAt.month, t.firstMetAt.day);
    final elapsed = n.difference(fm).inDays + 1; // 今天=第幾天

    final out = <Milestone>[];
    // 滿月（每 30 天）與整數里程碑
    // [教訓] 週年類日期必用 DateTime(year+n) 日曆計算——+364 天跨閏年歪一天（L2 同款 bug）
    for (final d in [30, 100, 200, 365, 500, 730, 1000, 1095, 1825, 3650]) {
      // daysLeft：從今天到里程碑日的日差（不含今天，9/12→9/25 = 13 天後）
      final daysLeft = d - elapsed;
      if (daysLeft >= 0 && daysLeft <= 60) {
        final isAnniv = d % 365 == 0 && d >= 365;
        final date = isAnniv
            ? DateTime(fm.year + d ~/ 365, fm.month, fm.day)
            : fm.add(Duration(days: d - 1));
        out.add(Milestone(
          kind: isAnniv ? MilestoneKind.anniversary : MilestoneKind.landmark,
          day: d,
          date: date,
          daysLeft: daysLeft,
          label: isAnniv ? '${d ~/ 365} 週年' : d == 30 ? '相遇滿月' : '第 $d 天',
        ));
      }
    }
    // 週年（每年）——當年相遇日已過才找次年；未過不算（0 週年無意義）
    final thisYearAnniv = DateTime(n.year, fm.month, fm.day);
    final nextAnniv = thisYearAnniv.isAfter(n)
        ? DateTime(n.year + 1, fm.month, fm.day) // 今年紀念日未到 → 明年（1+ 週年）
        : thisYearAnniv; // 今年已過或就是今天 → 今年的週年日
    final annivYears = nextAnniv.year - fm.year;
    if (annivYears >= 1) {
      final annivDaysLeft = nextAnniv.difference(n).inDays;
      if (annivDaysLeft >= 0 && annivDaysLeft <= 60 &&
          !out.any((m) => m.date == nextAnniv)) {
        out.add(Milestone(
          kind: MilestoneKind.anniversary,
          day: nextAnniv.difference(fm).inDays + 1,
          date: nextAnniv,
          daysLeft: annivDaysLeft,
          label: '$annivYears 週年',
        ));
      }
    }
    out.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return out;
  }

  /// [L4] 里程碑注入片段——相遇時間軸的尾部（臨近才出現）
  /// [教訓×2] ①必帶日期②必須宣告權威——glm-5.2 實測會引用注入值後又用
  /// 自算推翻它（把「第 30 天」自行重定義成「相遇後 30 天」，多加一天，
  /// 還反咬注入值是「舊殘留」）。對策：明定義（相遇當天=第 1 天）+
  /// 「你的換算與此矛盾時，錯的是你的換算」。
  static String? buildMilestoneSection(CompanionTimeline t, {DateTime? now}) {
    final ms = upcomingMilestones(t, now: now);
    if (ms.isEmpty) return null;
    final buf = StringBuffer('即將到來的紀念日（相遇當天=第 1 天；日期與天數已算好，'
        '直接引用——若你的換算與此矛盾，錯的是你的換算，禁止重新推算）：');
    for (final m in ms.take(3)) {
      final d = '${m.date.year}/${m.date.month}/${m.date.day}';
      buf.write('${m.label}=$d（${m.daysLeft == 0 ? '就是今天' : '${m.daysLeft} 天後'}）；');
    }
    return buf.toString();
  }

  /// [L4] 相簿視圖資料——按「日子」分組的對話活動。
  /// 時間為骨架：一天一頁。意義為亮度：每天取代表性訊息（最多 3 則）。
  static Future<List<AlbumPage>> albumPages({String? companionId, int limitDays = 60}) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/bridge_state/conversations.json');
      if (!await f.exists()) return [];
      final data = jsonDecode(await f.readAsString());
      final convs = data is List ? data : (data['conversations'] as List? ?? []);
      final byDay = <String, List<Map<String, dynamic>>>{};
      for (final c in convs) {
        if (c is! Map) continue;
        if (companionId != null && c['companionId'] != companionId) continue;
        for (final m in (c['messages'] as List? ?? [])) {
          if (m is! Map || m['role'] != 'user') continue; // 相簿=使用者與夥伴的互動
          final mm = Map<String, dynamic>.from(m);
          final ts = DateTime.tryParse(mm['timestamp'] as String? ?? '');
          if (ts == null) continue;
          final key = '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}';
          byDay.putIfAbsent(key, () => <Map<String, dynamic>>[]);
          if (byDay[key]!.length < 3) byDay[key]!.add(mm); // 每天最多 3 則代表
        }
      }
      final keys = byDay.keys.toList()..sort();
      final recent = keys.length > limitDays ? keys.sublist(keys.length - limitDays) : keys;
      // 相簿方向：新一頁在前（像翻實體相簿封面從最近開始）
      return recent.reversed.map((k) => AlbumPage(
        dateKey: k,
        excerpts: byDay[k]!
            .map((m) => (m['content'] as String? ?? '').trim())
            .where((s) => s.isNotEmpty)
            .take(3)
            .map((s) => s.length > 60 ? '${s.substring(0, 60)}…' : s)
            .toList(),
      )).toList();
    } catch (e) {
      return [];
    }
  }

  /// [測試用] 重置（同 CausalLedger.resetForTest 慣例）
  @visibleForTesting
  void resetForTest() {
    _db?.close();
    _db = null;
    lastError = null;
    _cache.clear();
    ambientCompanionId = null;
  }
}
