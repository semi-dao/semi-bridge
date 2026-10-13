// Hermes Skills 入境安檢器——先掃描去重安檢，乾淨的才准入
//
// [Blue 令 2026-10-06] 「先去重／精簡／檢查後，再搬進來」——順序反過來
// 的話（先搬再清）要多走好幾步。本工具在 App 外跑（開發期一次性），
// 產出報告 → Blue 過目 → 放行清單才寫進 Documents/skills/hermes/。
//
// 安檢規則（開源社群綠燈標準）：
//   RED 拒絕：API key/token 模式、內部絕對路徑（/Users/…、/Volumes/…）、
//            個資（身分證/電話/Email 明文）、私人網域（farm.semidao.net 等）
//   YELLOW 人工：提到金鑰位置指引（keychain 等）、外部磁碟路徑、
//            授權不明（無 license 標記且非原創）
//   GREEN 放行：通過全部規則
// 去重：同名 skill（name: 重複）取最新版；與 App 既有 8 個 builtin 同名
//       的視為「已在本土」跳過。

import 'dart:io';
import 'package:flutter/foundation.dart';

class HermesSkillAuditReport {
  final String name; // skill name
  final String category; // hermes 分類（頂層目錄）
  final String srcPath;
  final String verdict; // GREEN | YELLOW | RED
  final List<String> findings;
  final int contentChars;
  const HermesSkillAuditReport({
    required this.name,
    required this.category,
    required this.srcPath,
    required this.verdict,
    required this.findings,
    required this.contentChars,
  });
}

class HermesSkillsGate {
  /// 掃描 + 去重 + 安檢。回傳報告清單（GREEN/YELLOW/RED 分類好）。
  static Future<List<HermesSkillAuditReport>> audit({
    required String hermesSkillsDir,
    required Set<String> existingSkillNames,
  }) async {
    final src = Directory(hermesSkillsDir);
    if (!await src.exists()) return const [];

    final skillFiles = <File>[];
    await for (final e in src.list(recursive: true, followLinks: false)) {
      if (e is File && e.path.endsWith('/SKILL.md')) skillFiles.add(e);
    }

    // ── 去重：同 name 取 mtime 最新 ──
    final byName = <String, File>{};
    final catByName = <String, String>{};
    for (final f in skillFiles) {
      final rel = f.path.substring(src.path.length + 1);
      final category = rel.split('/').first;
      final content = await f.readAsString();
      final name = _frontmatterName(content) ??
          rel.split('/').lastWhere((p) => p != 'SKILL.md');
      // 去重：同名取新
      final prev = byName[name];
      if (prev == null) {
        byName[name] = f;
        catByName[name] = category;
      } else {
        final prevStat = await prev.stat();
        final curStat = await f.stat();
        if (curStat.modified.isAfter(prevStat.modified)) {
          byName[name] = f;
          catByName[name] = category;
        }
      }
    }

    // ── 安檢 ──
    final reports = <HermesSkillAuditReport>[];
    for (final entry in byName.entries) {
      final name = entry.key;
      final f = entry.value;
      final content = await f.readAsString();

      // 與本土 builtin 同名 → 不移民（本土已有）
      if (existingSkillNames.contains(name)) {
        reports.add(HermesSkillAuditReport(
          name: name,
          category: catByName[name]!,
          srcPath: f.path,
          verdict: 'SKIP_LOCAL',
          findings: ['與 App 內建 skill 同名——本土已有，不重複移民'],
          contentChars: content.length,
        ));
        continue;
      }

      final (verdict, findings) = _scan(content);
      reports.add(HermesSkillAuditReport(
        name: name,
        category: catByName[name]!,
        srcPath: f.path,
        verdict: verdict,
        findings: findings,
        contentChars: content.length,
      ));
    }

    reports.sort((a, b) => a.verdict.compareTo(b.verdict));
    return reports;
  }

  static String? _frontmatterName(String content) {
    final m = RegExp(r'^---\s*\n(.*?\n)---', dotAll: true).firstMatch(content);
    if (m == null) return null;
    final nm = RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(m.group(1)!);
    return nm?.group(1)?.trim();
  }

  /// 掃描單一內容。回傳 (verdict, findings)。
  static (String, List<String>) _scan(String content) {
    final findings = <String>[];
    var red = false;
    var yellow = false;

    // RED：金鑰模式
    if (RegExp(r'(sk|api|pk|rk|ghp|gho|xox)[-_]?(key|token)?\s*[:=]\s*[A-Za-z0-9_-]{16,}',
            caseSensitive: false)
        .hasMatch(content)) {
      findings.add('疑似 API key/token 明文');
      red = true;
    }
    // RED：內部絕對路徑
    final internalPath =
        RegExp(r'/Users/[a-z]+/|/Volumes/[^\s/]+', caseSensitive: false);
    if (internalPath.hasMatch(content)) {
      findings.add('含內部絕對路徑（/Users 或 /Volumes）');
      red = true;
    }
    // RED：私網域
    if (content.contains('farm.semidao.net') ||
        content.contains('semiwasabi')) {
      findings.add('含私人網域/帳號（farm.semidao.net / semiwasabi）');
      red = true;
    }
    // RED：個資模式（身分證/電話）
    if (RegExp(r'[A-Z][12]\d{8}').hasMatch(content) ||
        RegExp(r'09\d{8}').hasMatch(content)) {
      findings.add('疑似身分證/電話號碼');
      red = true;
    }

    // YELLOW：金鑰「位置」指引（keychain/token@ 這類描述，非明文）
    if (!red &&
        RegExp(r'keychain|金鑰位置|token.*位於|token@', caseSensitive: false)
            .hasMatch(content)) {
      findings.add('描述金鑰存放位置（非明文）——人工確認');
      yellow = true;
    }
    // YELLOW：外部服務帳號依賴（搬進開源社群後需要使用者自備）
    if (!red &&
        RegExp(r'MCP_TOKEN|8420|18789', caseSensitive: false)
            .hasMatch(content)) {
      findings.add('依賴本機內部服務（MCP 8420/llama 18789）');
      yellow = true;
    }

    if (red) return ('RED', findings);
    if (yellow) return ('YELLOW', findings);
    return ('GREEN', findings.isEmpty ? ['乾淨'] : findings);
  }

  /// 報告落檔（人類可讀 markdown）。
  static Future<File> writeReport(
      List<HermesSkillAuditReport> reports, String outPath) async {
    final buf = StringBuffer('# Hermes Skills 入境安檢報告\n\n');
    buf.writeln('產出時間：${DateTime.now()}\n');
    final green = reports.where((r) => r.verdict == 'GREEN').length;
    final yellow = reports.where((r) => r.verdict == 'YELLOW').length;
    final red = reports.where((r) => r.verdict == 'RED').length;
    final skip = reports.where((r) => r.verdict == 'SKIP_LOCAL').length;
    buf.writeln('**總計 ${reports.length}**：🟢 $green 放行 ｜ '
        '🟡 $yellow 人工複審 ｜ 🔴 $red 拒絕 ｜ ⏭️ $skip 本土已有\n');

    for (final v in ['RED', 'YELLOW', 'SKIP_LOCAL', 'GREEN']) {
      final list = reports.where((r) => r.verdict == v).toList();
      if (list.isEmpty) continue;
      final icon = { 'RED': '🔴', 'YELLOW': '🟡', 'SKIP_LOCAL': '⏭️', 'GREEN': '🟢' }[v]!;
      buf.writeln('## $icon $v（${list.length}）\n');
      for (final r in list) {
        buf.writeln('- **${r.name}**（${r.category}，${r.contentChars} 字）');
        for (final f in r.findings) {
          buf.writeln('  - $f');
        }
      }
      buf.writeln();
    }
    final f = File(outPath);
    await f.writeAsString(buf.toString());
    debugPrint('[HermesSkillsGate] 報告已落檔：$outPath');
    return f;
  }
}
