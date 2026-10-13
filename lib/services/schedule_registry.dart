// H4 2026-10-08 — 排程登記處（Schedule Registry）
// 從 Hermes ~/.hermes/cron/jobs.json 讀取排程，重現為任務卡。
// 真相源仍是 Hermes cron（不搬 JSON、不雙寫）——本服務只讀。
// 溫度分類（life/work）由名單比對：生活卡的關鍵字手工維護（機器猜不如人定）。
import 'dart:convert';
import 'dart:io';
import '../core/dev_paths.dart';
import '../models/schedule_card.dart';

class ScheduleRegistry {
  ScheduleRegistry._();
  static final ScheduleRegistry instance = ScheduleRegistry._();

  static final String _jobsPath =
      resolveDevPath('~/.hermes/cron/jobs.json');

  /// 生活／儀式卡名單（精確比對 job name 前綴）——Blue 的「有溫度」清單
  static const Map<String, String> _lifeCards = {
    '小葵每日安靜時刻': '一天的最後，留一段安靜給自己',
    'agent-quiet-time': '午前十一點，全農場輕聲細語',
    '家人六個月之約——立石回顧': '半年前立下的石頭，回來看看',
    '小葵生日約定｜2027-02-05 首次討禮物': '生日前先聊天，禮物不急',
    '10/8 晚間體力帳關懷（一日份）': '今晚早點休息，體力帳結清就好',
    '策劃室_每日近況與創意更新': '每天收工前，說說今天的好',
    '以利沙_每日農場日記': '農場的一天，值得被寫下來',
  };

  List<ScheduleCard> _cache = [];
  DateTime _cacheAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 全部排程卡（enabled 優先、生活卡優先）
  Future<List<ScheduleCard>> loadAll({bool forceReload = false}) async {
    if (!forceReload &&
        DateTime.now().difference(_cacheAt).inMinutes < 5 &&
        _cache.isNotEmpty) {
      return _cache;
    }
    final file = File(_jobsPath);
    if (!file.existsSync()) return _cache;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      final jobs = decoded is Map
          ? (decoded['jobs'] as List? ?? [])
          : (decoded as List? ?? []);
      final cards = <ScheduleCard>[];
      for (final j in jobs) {
        final m = j as Map<String, dynamic>;
        final enabled = m['enabled'] as bool? ?? true;
        if (!enabled) continue;
        final name = (m['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;
        final sched = m['schedule'];
        final raw = sched is Map
            ? (sched['expr'] as String? ??
                (sched['kind'] == 'interval'
                    ? (sched['display'] as String? ??
                        '每 ${sched['every'] ?? sched['minutes']} ${sched['unit'] ?? '分鐘'}')
                    : sched['kind'] == 'once'
                        ? 'once ${sched['run_at'] ?? sched['runAt'] ?? sched['display'] ?? ''}'
                        : sched.toString()))
            : (sched?.toString() ?? '');
        final life = _matchLife(name);
        cards.add(ScheduleCard(
          id: m['id']?.toString() ?? name,
          name: name,
          rawSchedule: raw,
          humanSchedule: humanizeCron(raw, name),
          warmth: life != null ? ScheduleWarmth.life : ScheduleWarmth.work,
          warmLine: life,
          nextRun: estimateNext(raw),
        ));
      }
      // 生活卡先排（溫度優先），其餘照名稱
      cards.sort((a, b) {
        final w = (a.warmth == ScheduleWarmth.life ? 0 : 1)
            .compareTo(b.warmth == ScheduleWarmth.life ? 0 : 1);
        return w != 0 ? w : a.name.compareTo(b.name);
      });
      _cache = cards;
      _cacheAt = DateTime.now();
      return cards;
    } catch (_) {
      return _cache;
    }
  }

  String? _matchLife(String name) {
    for (final e in _lifeCards.entries) {
      if (name.contains(e.key)) return e.value;
    }
    return null;
  }

  /// cron → 中文時間。只覆蓋這 28 jobs 用到的形態（誠實範圍，不假裝全解析器）
  static String humanizeCron(String raw, String name) {
    if (raw.startsWith('每 ')) return raw; // interval
    if (raw.startsWith('once')) {
      final t = raw.replaceFirst('once', '').trim();
      return '一次性 $t';
    }
    final parts = raw.split(RegExp(r'\s+'));
    if (parts.length != 5) return raw;
    final min = parts[0], hour = parts[1], dom = parts[2], mon = parts[3],
        dow = parts[4];
    final hm = '${hour.padLeft(2, '0')}:${min.padLeft(2, '0')}';
    String day;
    if (dom != '*' || mon != '*') {
      return '每月指定日 $hm';
    }
    day = switch (dow) {
      '*' => '每天',
      '0' => '每週日',
      '1' => '每週一',
      '2' => '每週二',
      '3' => '每週三',
      '4' => '每週四',
      '5' => '每週五',
      '6' => '每週六',
      _ => '每週 $dow',
    };
    return '$day $hm';
  }

  /// 粗估下次觸發（本地時區）。once=runAt；cron 只支援「每天/每週X」形態。
  static DateTime? estimateNext(String raw) {
    final now = DateTime.now();
    if (raw.startsWith('once')) {
      final t = DateTime.tryParse(raw.replaceFirst('once', '').trim());
      return (t != null && t.isAfter(now)) ? t : null;
    }
    final parts = raw.split(RegExp(r'\s+'));
    if (parts.length != 5) return null;
    final min = int.tryParse(parts[0]) ?? 0;
    final hour = int.tryParse(parts[1]) ?? 0;
    final dow = parts[4] == '*' ? null : int.tryParse(parts[4]);
    if (parts[2] != '*' || parts[3] != '*') return null;
    for (var i = 0; i < 8; i++) {
      final d = DateTime(now.year, now.month, now.day + i, hour, min);
      if (d.isAfter(now) && (dow == null || d.weekday % 7 == dow)) {
        return d;
      }
    }
    return null;
  }
}
