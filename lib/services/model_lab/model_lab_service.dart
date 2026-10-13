import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../brain_container/brain_container_service.dart';
import '../brain_container/brain_database.dart';

/// 模型實驗室——把「新模型出現 → 快測 → 報告 → 一鍵採用」產品化。
/// [小葵 2026-09-29] Blue 拍板規格（grill 9 問定案）：
/// - 測試素材：使用者自己的照片（最近匯入自動抽 5 張快測 / 20 張全測，可換）
/// - 兩段式：快測有希望才問要不要全測
/// - 報告：逐張對照 + 品質/速度/RAM + 近 30 天使用量換算「換了每天多/少花幾分鐘」+ 一句話建議
/// - 安全閘：磁碟檢查 → RAM 預算 → OOM 自動回滾現役模型
class ModelLabService {
  ModelLabService._();
  static final ModelLabService instance = ModelLabService._();

  static const _reportDirName = 'ModelLab';

  // ── 快測/全測 張數（Blue 定案：5 快測、20 全測）──
  static const quickTestCount = 5;
  static const fullTestCount = 20;

  /// 從 asset_index 抽最近的照片（快測素材自動抽取）
  /// 回傳絕對路徑清單（新→舊）
  Future<List<String>> pickRecentPhotos(int count, {String? rootHint}) async {
    try {
      if (!BrainContainerService.instance.isInitialized) return [];
      final db = BrainDatabase.instance.db;
      final rows = db.select(
        "SELECT file_path, folder_root FROM asset_index "
        "WHERE (asset_kind = 'photo' OR lower(ifnull(file_ext,'')) IN ('.jpg','.jpeg','.png','.heic','.webp')) "
        "ORDER BY file_modified DESC LIMIT ?",
        [count * 4], // 多抽一些，過濾不存在檔案後仍夠數
      );
      final out = <String>[];
      for (final r in rows) {
        final p = _absPath(r['folder_root'] as String?, r['file_path'] as String);
        if (p != null && File(p).existsSync()) {
          out.add(p);
          if (out.length >= count) break;
        }
      }
      return out;
    } catch (e) {
      debugPrint('[ModelLab] 抽照片失敗: $e');
      return [];
    }
  }

  String? _absPath(String? root, String rel) {
    if (root == null || root.isEmpty) return null;
    if (rel.startsWith('/')) return rel;
    return '$root/$rel';
  }

  // ── 測試執行：對指定 llama-server 跑一張照片的描述 ──

  Future<Map<String, dynamic>> describePhoto(String url, String imagePath,
      {int maxTokens = 800, Duration timeout = const Duration(seconds: 240)}) async {
    final bytes = await File(imagePath).readAsBytes();
    final b64 = base64Encode(bytes);
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('$url/v1/chat/completions'))
        ..headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'model': 'local',
        'max_tokens': maxTokens,
        'temperature': 0.4,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$b64'}},
              {
                'type': 'text',
                'text': '這是一張生活照片。請詳細描述照片內容（場景、主體、動作、文字、地點線索），'
                    '供建立搜尋索引使用。'
              }
            ]
          }
        ],
      }));
      final resp = await req.close().timeout(timeout);
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        return {'ok': false, 'error': 'HTTP ${resp.statusCode}: ${body.substring(0, body.length > 200 ? 200 : body.length)}'};
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final desc = (((data['choices'] as List?)?.first
              as Map<String, dynamic>?)?['message'] as Map<String, dynamic>?)?['content'] as String? ??
          '';
      return {'ok': true, 'desc': desc.trim()};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    } finally {
      client.close(force: true);
    }
  }

  // ── 判分（與 vision_bench.py 同邏輯：hint 關鍵詞命中）──

  bool scoreDescription(String desc, List<String> hints) {
    final d = desc.toLowerCase();
    for (final h in hints) {
      if (h.trim().isEmpty) continue;
      if (d.contains(h.toLowerCase())) return true;
    }
    return false;
  }

  // ── 報告存讀 ──

  Future<Directory> _reportDir() async {
    final home = Platform.environment['BRIDGE_APP_HOME'] ??
        '${Platform.environment['HOME']}/Library/Application Support/farm.semiwasabi.bridgeApp';
    final d = Directory('$home/$_reportDirName');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<void> saveReport(ModelLabReport report) async {
    final dir = await _reportDir();
    final f = File('${dir.path}/${report.id}.json');
    await f.writeAsString(const JsonEncoder.withIndent(' ').convert(report.toJson()));
    debugPrint('[ModelLab] 報告已存: ${f.path}');
  }

  Future<List<ModelLabReport>> loadReports() async {
    final dir = await _reportDir();
    final out = <ModelLabReport>[];
    for (final f in dir.listSync()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        out.add(ModelLabReport.fromJson(
            jsonDecode((f as File).readAsStringSync()) as Map<String, dynamic>));
      } catch (e) {
        debugPrint('[ModelLab] 跳過壞報告 ${f.path}: $e');
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  // ── 安全閘：磁碟 + RAM（以當下主機規格平安測換為原則）──

  /// 回 null = 通過；回 String = 不通過的原因
  String? preflight({required double modelSizeGb, required int totalRamGb}) {
    // 磁碟：模型大小 x 1.2 需有富餘
    final freeGb = _freeDiskGb();
    if (freeGb == null) return null; // 讀不到就放行（保守不了就別擋）
    if (freeGb < modelSizeGb * 1.2 + 2) {
      return '磁碟空間不足：需要 ~${(modelSizeGb * 1.2).toStringAsFixed(1)}GB，僅剩 ${freeGb.toStringAsFixed(1)}GB';
    }
    // RAM 預算：模型檔 + KV cache + 系統 ≥ 佔用不超過實體 RAM 的 85%
    final projectedGb = modelSizeGb * 0.85 + 1.5; // 量化後常駐 + KV cache 估算
    if (projectedGb > totalRamGb * 0.85) {
      return 'RAM 預算不足：預估常駐 ${projectedGb.toStringAsFixed(1)}GB 超過 ${totalRamGb}GB 機器的安全上限';
    }
    return null;
  }

  double? _freeDiskGb() {
    try {
      final stat = Process.runSync('df', ['-g', Platform.environment['HOME'] ?? '/']);
      final lines = (stat.stdout as String).split('\n');
      if (lines.length > 1) {
        final cols = lines[1].trim().split(RegExp(r'\s+'));
        if (cols.length >= 4) return double.tryParse(cols[3]);
      }
    } catch (_) {}
    return null;
  }
}

/// 報告資料模型
class ModelLabReport {
  final String id; // e.g. 2026-09-28_12b-vs-e4b
  final String challengerName; // 挑戰者（新模型）
  final String incumbentName; // 現役
  final DateTime createdAt;
  final int photoCount;
  final int challengerHits;
  final int incumbentHits;
  final double challengerAvgSec;
  final double incumbentAvgSec;
  final double? challengerRamGb;
  final String recommendation; // 建議：switch / keep / more-data
  final String oneLiner; // 一句話人話結論
  final List<Map<String, dynamic>> perPhoto; // 逐張對照

  ModelLabReport({
    required this.id,
    required this.challengerName,
    required this.incumbentName,
    required this.createdAt,
    required this.photoCount,
    required this.challengerHits,
    required this.incumbentHits,
    required this.challengerAvgSec,
    required this.incumbentAvgSec,
    this.challengerRamGb,
    required this.recommendation,
    required this.oneLiner,
    required this.perPhoto,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'challengerName': challengerName,
        'incumbentName': incumbentName,
        'createdAt': createdAt.toIso8601String(),
        'photoCount': photoCount,
        'challengerHits': challengerHits,
        'incumbentHits': incumbentHits,
        'challengerAvgSec': challengerAvgSec,
        'incumbentAvgSec': incumbentAvgSec,
        'challengerRamGb': challengerRamGb,
        'recommendation': recommendation,
        'oneLiner': oneLiner,
        'perPhoto': perPhoto,
      };

  factory ModelLabReport.fromJson(Map<String, dynamic> j) => ModelLabReport(
        id: j['id'] as String,
        challengerName: j['challengerName'] as String,
        incumbentName: j['incumbentName'] as String? ?? '',
        createdAt: DateTime.parse(j['createdAt'] as String),
        photoCount: j['photoCount'] as int? ?? 0,
        challengerHits: j['challengerHits'] as int? ?? 0,
        incumbentHits: j['incumbentHits'] as int? ?? 0,
        challengerAvgSec: (j['challengerAvgSec'] as num?)?.toDouble() ?? 0,
        incumbentAvgSec: (j['incumbentAvgSec'] as num?)?.toDouble() ?? 0,
        challengerRamGb: (j['challengerRamGb'] as num?)?.toDouble(),
        recommendation: j['recommendation'] as String? ?? 'keep',
        oneLiner: j['oneLiner'] as String? ?? '',
        perPhoto: (j['perPhoto'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      );
}
