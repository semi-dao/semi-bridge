/// Agency Agents 匯入器——282 顧問模式人格入住（插槽輕量化 Task 5）
///
/// 來源：`~/.hermes/plugins/agency-agents-router/data/agents.json`
/// （282 agents，body 平均 11k 字，metadata ~30k tokens，bodies ~1.3M tokens）。
///
/// 每個 agent 轉 `skillsDir/agency-agents/<slug>.md`：
/// - frontmatter：name/description，**不加 trigger_keywords**——
///   顧問模式不被動觸發，只能 skillSearch 主動找到（= Hermes 同款紀律）
/// - body = 人格全文（留磁碟，SkillCatalog 懶載入）
///
/// 安檢：HermesSkillsGate 同款規則（[SkillAgencyImporter.scanContent]）——
/// RED 拒絕、GREEN/YELLOW 入庫但分類一律「顧問模式」。
///
/// 插槽卡：**不逐個開 282 張**——一張總卡
/// 「顧問模式・Agency 人格庫」（origin='agency-agents'、
/// sourceRepo='skill://agency-agents__library'）代表全體，
/// 個別人格靠 skill_search/skill_load 按需取用（不淹沒插槽管理頁）。
///
/// 冪等：目標 .md 已存在跳過（不覆寫）、總卡已存在跳過——重跑即同步上游。
///
/// 執行入口：`dart run tool/import_agency_agents.dart`（開發期一次性腳本）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../slots/slot_registry.dart';
import 'skill_catalog.dart';

/// 單一 agent 的安檢報告
class AgencyAuditFile {
  final String slug;
  final String division;
  final String verdict; // GREEN | YELLOW | RED
  final List<String> findings;
  final int contentChars;

  const AgencyAuditFile({
    required this.slug,
    required this.division,
    required this.verdict,
    required this.findings,
    required this.contentChars,
  });
}

/// 匯入報告——數字誠實
class AgencyImportReport {
  final int total;
  final int green;
  final int yellow;
  final int red;
  final int imported;
  final int skippedExisting;
  final List<AgencyAuditFile> files;
  final List<String> errors;

  const AgencyImportReport({
    required this.total,
    required this.green,
    required this.yellow,
    required this.red,
    required this.imported,
    required this.skippedExisting,
    required this.files,
    required this.errors,
  });

  Map<String, dynamic> toJson() => {
        'total': total,
        'green': green,
        'yellow': yellow,
        'red': red,
        'imported': imported,
        'skippedExisting': skippedExisting,
        if (errors.isNotEmpty) 'errors': errors,
      };

  @override
  String toString() =>
      'AgencyImportReport(總 $total：🟢 $green 🟡 $yellow 🔴 $red｜'
      '入庫 $imported、已有 $skippedExisting、錯誤 ${errors.length})';
}

class SkillAgencyImporter {
  /// 入庫分類——Blue 拍板（2026-10-13）新分類「顧問模式」
  static const String category = '顧問模式';

  /// origin 標記（SlotRecord [H1] 出身欄）
  static const String origin = 'agency-agents';

  /// 總卡識別——一張卡代表全體 282 人格
  static const String libraryRepo = 'skill://agency-agents__library';
  static const String libraryLabel = 'Agency 人格庫';

  final Directory skillsDir;
  final SlotRegistry registry;
  final SkillCatalog catalog;

  SkillAgencyImporter({
    required this.skillsDir,
    required this.registry,
    required this.catalog,
  });

  /// 從 agents.json 匯入（冪等）。
  ///
  /// [dryRun] = true 時只安檢不寫檔不建卡（Blue 驗收數字用）
  Future<AgencyImportReport> importFromJson(
    String jsonPath, {
    bool dryRun = false,
  }) async {
    final f = File(jsonPath);
    if (!await f.exists()) {
      return const AgencyImportReport(
        total: 0,
        green: 0,
        yellow: 0,
        red: 0,
        imported: 0,
        skippedExisting: 0,
        files: [],
        errors: ['來源 JSON 不存在'],
      );
    }

    final List<dynamic> raw;
    try {
      raw = jsonDecode(await f.readAsString()) as List<dynamic>;
    } catch (e) {
      return AgencyImportReport(
        total: 0,
        green: 0,
        yellow: 0,
        red: 0,
        imported: 0,
        skippedExisting: 0,
        files: const [],
        errors: ['JSON 解析失敗：$e'],
      );
    }

    // ── 安檢（逐 agent）──
    final audits = <AgencyAuditFile>[];
    final admissible = <Map<String, dynamic>>[]; // GREEN/YELLOW
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final slug = (item['slug'] as String?)?.trim() ?? '';
      if (slug.isEmpty) continue;
      final division = (item['division'] as String?)?.trim() ?? '';
      final body = (item['body'] as String?) ?? '';
      final (verdict, findings) = scanContent(body);
      audits.add(AgencyAuditFile(
        slug: slug,
        division: division,
        verdict: verdict,
        findings: findings,
        contentChars: body.length,
      ));
      if (verdict != 'RED') {
        admissible.add(item);
      }
    }

    final green = audits.where((a) => a.verdict == 'GREEN').length;
    final yellow = audits.where((a) => a.verdict == 'YELLOW').length;
    final red = audits.where((a) => a.verdict == 'RED').length;

    if (dryRun) {
      return AgencyImportReport(
        total: audits.length,
        green: green,
        yellow: yellow,
        red: red,
        imported: 0,
        skippedExisting: 0,
        files: audits,
        errors: const [],
      );
    }

    // ── 入庫──
    final destDir = Directory('${skillsDir.path}/agency-agents');
    await destDir.create(recursive: true);

    final errors = <String>[];
    var imported = 0;
    var skippedExisting = 0;

    for (final agent in admissible) {
      final slug = (agent['slug'] as String).trim();
      try {
        final dest = File('${destDir.path}/$slug.md');
        if (await dest.exists()) {
          skippedExisting++; // 不覆寫
          continue;
        }
        final md = _toMarkdown(agent);
        await dest.writeAsString(md);
        imported++;
      } catch (e) {
        errors.add('$slug：$e');
      }
    }

    // ── 總卡（不逐個開 282 張）——冪等──
    if (imported > 0 || skippedExisting > 0) {
      try {
        await registry.ensureLoaded();
        final hasCard =
            registry.all.any((s) => s.sourceRepo == libraryRepo);
        if (!hasCard) {
          final record = await registry.addFromRepo(
            libraryRepo,
            label: libraryLabel,
            category: category,
          );
          await registry
              .update(registry.getById(record.id)!.copyWith(origin: origin));
          await registry.enableWithPermissions(record.id, const []);
        }
      } catch (e) {
        errors.add('總卡建立失敗（檔案已入庫）: $e');
      }
    }

    // ── catalog 重掃──
    await catalog.reload();

    debugPrint(
        '[SkillAgencyImporter] 總 ${audits.length}：🟢 $green 🟡 $yellow 🔴 $red｜入庫 $imported、已有 $skippedExisting');

    return AgencyImportReport(
      total: audits.length,
      green: green,
      yellow: yellow,
      red: red,
      imported: imported,
      skippedExisting: skippedExisting,
      files: audits,
      errors: errors,
    );
  }

  /// agent → .md 全文。鐵則：frontmatter 不加 trigger_keywords。
  static String _toMarkdown(Map<String, dynamic> agent) {
    final name = ((agent['name'] as String?) ?? agent['slug'] as String)
        .replaceAll('\n', ' ')
        .trim();
    final description = ((agent['description'] as String?) ?? '')
        .replaceAll('\n', ' ')
        .trim();
    final body = (agent['body'] as String?) ?? '';
    final division = (agent['division'] as String?) ?? '';
    final buf = StringBuffer()
      ..writeln('---')
      ..writeln('name: ${agent['slug']}')
      ..writeln('description: $description')
      ..writeln('---')
      ..writeln()
      ..writeln('# $name');
    if (division.isNotEmpty) {
      buf.writeln();
      buf.writeln('> Division: $division');
    }
    buf.writeln();
    buf.write(body);
    return buf.toString();
  }

  // ═══════════════════════════════════════════════════
  // 安檢——HermesSkillsGate 同款規則（hermes_skills_gate.dart _scan 對位）
  // ═══════════════════════════════════════════════════

  /// 掃描單一內容。回傳 (verdict, findings)。
  /// 規則與 lib/services/slots/hermes_skills_gate.dart 的 _scan 完全對位；
  /// 獨立實作是因為 gate 掛著 flutter/foundation 且針對 SKILL.md 檔案形狀，
  /// 這裡吃純 body 字串。改規則時兩邊同步。
  static (String, List<String>) scanContent(String content) {
    final findings = <String>[];
    var red = false;
    var yellow = false;

    // RED：金鑰模式
    if (RegExp(
            r'(sk|api|pk|rk|ghp|gho|xox)[-_]?(key|token)?\s*[:=]\s*[A-Za-z0-9_-]{16,}',
            caseSensitive: false)
        .hasMatch(content)) {
      findings.add('疑似 API key/token 明文');
      red = true;
    }
    // RED：內部絕對路徑
    if (RegExp(r'/Users/[a-z]+/|/Volumes/[^\s/]+', caseSensitive: false)
        .hasMatch(content)) {
      findings.add('含內部絕對路徑（/Users 或 /Volumes）');
      red = true;
    }
    // RED：私網域/帳號
    if (content.contains('farm.semidao.net') ||
        content.contains('semiwasabi')) {
      findings.add('含私人網域/帳號（farm.semidao.net / semiwasabi）');
      red = true;
    }
    // RED：個資（身分證/電話）
    if (RegExp(r'[A-Z][12]\d{8}').hasMatch(content) ||
        RegExp(r'09\d{8}').hasMatch(content)) {
      findings.add('疑似身分證/電話號碼');
      red = true;
    }

    // YELLOW：金鑰位置指引（非明文）
    if (!red &&
        RegExp(r'keychain|金鑰位置|token.*位於|token@', caseSensitive: false)
            .hasMatch(content)) {
      findings.add('描述金鑰存放位置（非明文）——人工確認');
      yellow = true;
    }
    // YELLOW：內部服務依賴
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
}
