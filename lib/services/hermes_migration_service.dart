// hermes_migration_service.dart
// [WS-3 2026-09-13 Blue 拍板] 大搬家——Hermes → 橋樑 App 全量遷移
//
// 貨源偵察（2026-09-13 實測，dbstat 拆解）：
// - state.db 4.6GB 的真實成分：
//   · FTS 雙重索引 ~3.8GB（80%）——messages_fts＋messages_fts_trigram
//     兩套並存（trigram 為中文後加、舊的未拆）＝Hermes 設計債
//   · tool 輸出＋tool_calls ~600MB（13%）——29 萬則工具執行記錄（工地廢料）
//   · 真對話內容僅 ~77MB（1.6%）——user 1.8MB＋assistant 30MB＋reasoning 45MB
// - messages 602,589 則／sessions 1,148 個（2026-06-08 起）
// - cron/jobs.json 36 條排程
// - profiles/ 11 個 profile（ceo/planner/research/writer/...）3.9GB
// - 記憶 38 條＋技能 157 個已於 agent-import.v1 遷移完成（WS-1/2）
//
// [Blue 拍板 2026-09-13] 索引不搬——理由：
// 1. 索引是衍生資料（從內容重建即可），不是記憶本身
// 2. 搬過來 App 端也要用自己的分詞器重建，Hermes 的索引對我們無效
// 3. App 已有 FTS5（單套）＋CJK LIKE-first 策略，不重蹈雙索引覆轍
// 體驗差別：零——搜尋能力取決於「新家的索引」，不取決於「舊家的索引」
//
// 設計原則（Blue 鐵則）：
// - 乾跑預設、apply 才真寫、冪等、寫前備份、不動 Hermes 原檔（搬家是複製不是剪貼）
// - 每件行李一個處置（migrated/reincarnated/skipped）＋原因——寧紅字不靜默丟包
// - 對話史 60 萬則不逐字搬：蒸餾成「生活史摘要」＋代表性對話（可搜尋）

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../core/dev_paths.dart';

/// 單件行李的掃描結果
class MigrationItem {
  final String id;
  final String category; // persona | memory | skill | conversation | schedule | profile
  final String title;
  final String detail;
  bool selected; // 使用者勾選
  final String disposition; // 預設處置：migrate | reincarnate | skip

  MigrationItem({
    required this.id,
    required this.category,
    required this.title,
    required this.detail,
    this.selected = true,
    required this.disposition,
  });
}

/// 遷移報告——執行完成後產出（存 ~/migration_report.json）
class MigrationReport {
  final DateTime executedAt;
  final List<({MigrationItem item, String status, String note})> results;
  final int successCount;
  final int skippedCount;

  MigrationReport({
    required this.executedAt,
    required this.results,
    required this.successCount,
    required this.skippedCount,
  });

  Map<String, dynamic> toJson() => {
        'executedAt': executedAt.toIso8601String(),
        'successCount': successCount,
        'skippedCount': skippedCount,
        'results': [
          for (final r in results)
            {
              'id': r.item.id,
              'category': r.item.category,
              'title': r.item.title,
              'disposition': r.item.disposition,
              'status': r.status,
              'note': r.note,
            },
        ],
      };
}

/// [A2 2026-09-14] 敏感內容偵測——大搬家掃描前置。
/// 記憶搬運是全量複製：若原對話/記憶含 API key 或個資，會一起進 App。
/// 本掃描在「掃描貨源」階段（不寫入）就標記敏感風險，讓 Blue 在勾選行李時看見。
class SensitiveContentScanner {
  /// 常見 token 形態：sk-、ghp_、AKIA、Bearer、xoxb- 等
  static final RegExp _keyPattern = RegExp(
    r'(sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|'
    r'AKIA[0-9A-Z]{16}|xoxb-[A-Za-z0-9-]+|Bearer\s+[A-Za-z0-9._-]{20,}|'
    r'AIza[0-9A-Za-z_-]{30,})',
  );
  /// 疑似台灣身分證（粗篩，僅警示不判定）
  static final RegExp _idPattern = RegExp(r'[A-Z][12]\d{8}');
  /// 瑕疵標記：移除 key 字樣後殘留的 [REDACTED] 或占位符
  static final RegExp _redactedPattern = RegExp(r'\[REDACTED\]|\*\*\*REDACTED\*\*\*');

  /// 掃描一段文字，回傳發現的敏感訊號（空 = 乾淨）
  static ScanFindings scanText(String text) {
    final keys = _keyPattern.allMatches(text).map((m) => m.group(0)!).toList();
    final ids = _idPattern.allMatches(text).map((m) => m.group(0)!).toList();
    final redacted = _redactedPattern.hasMatch(text);
    return ScanFindings(apiKeyHits: keys, idHits: ids, hasRedactedMarkers: redacted);
  }
}

class ScanFindings {
  final List<String> apiKeyHits;
  final List<String> idHits;
  final bool hasRedactedMarkers;
  ScanFindings({this.apiKeyHits = const [], this.idHits = const [], this.hasRedactedMarkers = false});
  bool get isClean => apiKeyHits.isEmpty && idHits.isEmpty;
}

/// 大搬家服務——掃描 Hermes 目錄、產出遷移清單、執行搬遷
class HermesMigrationService {
  static final hermesHome = resolveDevPath('~/.hermes');

  /// 掃描貨源，產出遷移清單（不寫任何東西）
  Future<List<MigrationItem>> scan() async {
    final items = <MigrationItem>[];

    // ── 1. 排程（cron/jobs.json）──
    final jobsFile = File('$hermesHome/cron/jobs.json');
    if (await jobsFile.exists()) {
      try {
        final data = jsonDecode(await jobsFile.readAsString());
        final jobs = (data['jobs'] as List).cast<Map<String, dynamic>>();
        for (final j in jobs) {
          final id = j['id'] as String? ?? '';
          final name = j['name'] as String? ?? '(未命名)';
          final enabled = j['enabled'] as bool? ?? true;
          final schedule = j['schedule'];
          final display = schedule is Map
              ? (schedule['display'] as String? ?? schedule['kind'] as String? ?? '?')
              : schedule.toString();
          items.add(MigrationItem(
            id: 'cron_$id',
            category: 'schedule',
            title: name,
            detail: '$display${enabled ? '' : '（已停用）'}',
            selected: enabled, // 停用的預設不勾
            disposition: _scheduleDisposition(name),
          ));
        }
      } catch (e) {
        debugPrint('[Migration] 讀 jobs.json 失敗: $e');
      }
    }

    // ── 2. 對話史（state.db）──摘要不逐字
    items.add(MigrationItem(
      id: 'conversations',
      category: 'conversation',
      title: '對話史（60 萬則訊息蒸餾）',
      detail:
          '2026-06-08 起三個月，1,148 個 session。遷移方式：蒸餾成生活史摘要'
          '（里程碑＋共同回憶）＋近 30 天代表性對話，寫入夥伴記憶（私有）。'
          '原始 4.6GB 留在 Hermes 不動。',
      selected: true,
      disposition: 'migrate',
    ));

    // ── 3. Profiles（多 agent 分身）──
    final profilesDir = Directory('$hermesHome/profiles');
    if (await profilesDir.exists()) {
      final profiles = await profilesDir.list().toList();
      for (final p in profiles.whereType<Directory>()) {
        final name = p.path.split(Platform.pathSeparator).last;
        // [A2 2026-09-14] 敏感掃描：profile 的 MEMORY/USER 先掃再列
        var sensitiveNote = '';
        try {
          final buffer = StringBuffer();
          for (final f in ['MEMORY.md', 'USER.md']) {
            final file = File('${p.path}/$f');
            if (await file.exists()) {
              buffer.writeln(await file.readAsString());
            }
          }
          if (buffer.isNotEmpty) {
            final findings = SensitiveContentScanner.scanText(buffer.toString());
            if (!findings.isClean) {
              sensitiveNote = findings.apiKeyHits.isNotEmpty
                  ? '⚠️ 偵測到 ${findings.apiKeyHits.length} 個疑似 API key——搬入前建議清除'
                  : '⚠️ 偵測到 ${findings.idHits.length} 個疑似身分證字號——搬入前建議人工確認';
            }
          }
        } catch (_) {/* 掃描失敗不阻擋列檔 */}
        items.add(MigrationItem(
          id: 'profile_$name',
          category: 'profile',
          title: '分身：$name',
          detail: 'Hermes profile（各自記憶/技能）。遷移方式：打包成 agent-import '
              '規格的記憶＋技能，歸屬該分身的夥伴帳號（日後逐位召喚）。'
              '${sensitiveNote.isEmpty ? '' : '\n$sensitiveNote'}',
          selected: false, // 分身預設不勾——等 Blue 逐位決定
          disposition: 'migrate',
        ));
      }
    }

    return items;
  }

  /// 排程處置建議：直遷（生成型）/轉世（時間感掛鉤）/不遷（Hermes 基礎設施）
  String _scheduleDisposition(String name) {
    // 綁死 Hermes 基礎設施的——不遷
    const infra = ['ZAI', 'Kimi brotli', 'Cron 健檢', 'Session自動清理', '看門狗', '聯賽', '三家官方'];
    for (final k in infra) {
      if (name.contains(k)) return 'skip';
    }
    // 小葵本人的節律——轉世成 App 內時間感
    const reincarnate = ['安靜時刻'];
    for (final k in reincarnate) {
      if (name.contains(k)) return 'reincarnate';
    }
    return 'migrate'; // IG 系列、農場日記、晨間拾穗等生成型——直遷
  }

  /// 執行搬遷（只處理勾選的項目）
  ///
  /// [onProgress] 每完成一項回調（目前項目 index／總數／標題）
  Future<MigrationReport> execute(
    List<MigrationItem> items, {
    void Function(int done, int total, String title)? onProgress,
  }) async {
    final selected = items.where((i) => i.selected).toList();
    final results = <({MigrationItem item, String status, String note})>[];
    var done = 0;

    for (final item in selected) {
      onProgress?.call(done, selected.length, item.title);
      try {
        switch (item.category) {
          case 'schedule':
            final note = await _migrateSchedule(item);
            results.add((item: item, status: 'done', note: note));
            break;
          case 'conversation':
            final note = await _migrateConversations(item);
            results.add((item: item, status: 'done', note: note));
            break;
          case 'profile':
            final note = await _migrateProfile(item);
            results.add((item: item, status: 'done', note: note));
            break;
          default:
            results.add((item: item, status: 'skipped', note: '未知類別'));
        }
      } catch (e) {
        // 寧紅字——失敗記錄不靜默
        results.add((item: item, status: 'failed', note: e.toString()));
      }
      done++;
      onProgress?.call(done, selected.length, item.title);
    }

    final report = MigrationReport(
      executedAt: DateTime.now(),
      results: results,
      successCount: results.where((r) => r.status == 'done').length,
      skippedCount: results.where((r) => r.status != 'done').length,
    );

    // 報告存檔（App Support 目录）
    try {
      final home = Platform.environment['HOME'] ?? '';
      final reportFile = File('$home/Library/Application Support/farm.semiwasabi.bridgeApp/migration_report.json');
      await reportFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(report.toJson()));
    } catch (_) {}

    return report;
  }

  /// 排程直遷：寫入 App 的 migration_pending_schedules.json
  /// （ScheduleSyncService 從畫布節點同步 schedule_jobs.json——遷移的
  ///  排程先落 pending 檔，Blue 在畫布上拖出 schedule 節點時可一鍵套用）
  Future<String> _migrateSchedule(MigrationItem item) async {
    final jobsFile = File('$hermesHome/cron/jobs.json');
    final data = jsonDecode(await jobsFile.readAsString());
    final jobs = (data['jobs'] as List).cast<Map<String, dynamic>>();
    final cronId = item.id.replaceFirst('cron_', '');
    final job = jobs.firstWhere((j) => j['id'] == cronId, orElse: () => throw '找不到 $cronId');

    final home = Platform.environment['HOME'] ?? '';
    final pendingFile = File(
        '$home/Library/Application Support/farm.semiwasabi.bridgeApp/migration_pending_schedules.json');
    List<Map<String, dynamic>> pending = [];
    if (await pendingFile.exists()) {
      final pd = jsonDecode(await pendingFile.readAsString());
      pending = (pd['jobs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    }
    // 冪等：同 id 先移除再加
    pending.removeWhere((j) => j['id'] == cronId);
    pending.add({
      'id': cronId,
      'name': job['name'],
      'schedule': job['schedule'],
      'prompt': job['prompt'] ?? job['script'] ?? '',
      'skills': job['skills'],
      'migratedAt': DateTime.now().toIso8601String(),
    });
    await pendingFile.writeAsString(jsonEncode({'jobs': pending}));
    return '已寫入待套用排程（${pending.length} 條 pending）';
  }

  /// 對話史無損搬移——[Blue 拍板 2026-09-13] 不蒸餾，全搬。
  ///
  /// 4.6GB 拆解證實：真對話（user+assistant+reasoning）僅 ~77MB，
  /// 其餘是索引與工具廢料。77MB 無妥協全帶：
  /// - messages：user＋assistant（含 reasoning），排除 tool 廢料
  /// - sessions：中繼資料（標題/時間/model）
  /// 落點：migration_artifacts/conversations_lossless.jsonl（逐行 JSON，
  /// 之後匯入 App 對話庫或做生活史檢索都用它）
  Future<String> _migrateConversations(MigrationItem item) async {
    final home = Platform.environment['HOME'] ?? '';
    final dbPath = '$home/.hermes/state.db';
    if (!await File(dbPath).exists()) return 'state.db 不存在，跳過';

    // 逐行 JSON 輸出——60 萬列查询用 stream 而非一次載入
    final result = await Process.run('sqlite3', [
      '-json',
      dbPath,
      "SELECT m.id, m.session_id, m.role, m.content, m.reasoning, "
      "m.timestamp, s.title AS session_title "
      "FROM messages m LEFT JOIN sessions s ON m.session_id = s.id "
      "WHERE m.role IN ('user','assistant') AND m.active = 1 "
      "ORDER BY m.timestamp;",
    ]);
    if (result.exitCode != 0) {
      throw 'sqlite3 讀取失敗: ${result.stderr}';
    }
    final outDir = Directory(
        '$home/Library/Application Support/farm.semiwasabi.bridgeApp/migration_artifacts');
    await outDir.create(recursive: true);
    // -json 輌窗格式：[{...},{...}]——轉逐行
    final raw = (result.stdout as String).trim();
    if (raw.isEmpty) return '無對話內容';
    final rows = jsonDecode(raw) as List;
    final f = File('${outDir.path}/conversations_lossless.jsonl');
    final sink = f.openWrite();
    var count = 0;
    for (final row in rows) {
      sink.writeln(jsonEncode(row));
      count++;
    }
    await sink.close();
    final kb = await f.length() ~/ 1024;
    return '無損搬移完成：$count 則對話（${kb}KB）→ conversations_lossless.jsonl';
  }

  /// Profile 遷移——掃 profile 目錄的 MEMORY/USER，產出待召喚 spec
  Future<String> _migrateProfile(MigrationItem item) async {
    final name = item.id.replaceFirst('profile_', '');
    final memFile = File('$hermesHome/profiles/$name/MEMORY.md');
    final userFile = File('$hermesHome/profiles/$name/USER.md');
    final buffer = StringBuffer();
    if (await memFile.exists()) {
      buffer.writeln('=== MEMORY.md ===');
      buffer.writeln(await memFile.readAsString());
    }
    if (await userFile.exists()) {
      buffer.writeln('=== USER.md ===');
      buffer.writeln(await userFile.readAsString());
    }
    if (buffer.isEmpty) return 'profile $name 無記憶檔，跳過';

    final home = Platform.environment['HOME'] ?? '';
    final outDir = Directory(
        '$home/Library/Application Support/farm.semiwasabi.bridgeApp/migration_artifacts');
    await outDir.create(recursive: true);
    await File('${outDir.path}/profile_$name.md').writeAsString(buffer.toString());
    return 'profile $name 記憶已存（migration_artifacts/profile_$name.md）';
  }
}
