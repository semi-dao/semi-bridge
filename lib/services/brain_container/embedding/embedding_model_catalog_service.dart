// embedding_model_catalog_service.dart
// [小葵 2026-10-16 Blue 令] 大腦記憶模型商店——下載/測試/換主力 的目錄＋執行層。
// 仿本地 LLM（LocalModelCatalogService + LocalModelRuntimeService）的完整 LOOP：
// 告知（目錄）→ 下載（GGUF→models/）→ 測試（臨時埠檢索快測）→ 換主力（改 plist→重啟→重嵌）。
//
// 血型鐵則（D1）：模型換血＝embed model version 變更 → Eg2ReembedService 全庫重嵌。
// 查詢向量與庫向量必同血型——本服務只負責把新模型上架，重嵌由既有 eg2_reembed 軌道收尾。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 一個可下載的 embedding 模型條目。
class EmbeddingCatalogEntry {
  final String id; // 版本身份（model_version 標記，如 eg2-300m-v1）
  final String name; // 顯示名
  final String family; // 家族（embeddinggemma-2 …）
  final String quantization; // Q8_0 / Q4_K_XL …
  final int sizeMb;
  final String fileName; // 本地檔名（models/ 下）
  final String mmprojFile; // 多模態投影檔（有 vision 才需要）
  final String downloadUrl;
  final String mmprojUrl;
  final int dims; // 向量維度
  final bool multimodal; // 支援圖片嵌入
  final String note; // 一句話介紹

  const EmbeddingCatalogEntry({
    required this.id,
    required this.name,
    required this.family,
    required this.quantization,
    required this.sizeMb,
    required this.fileName,
    required this.mmprojFile,
    required this.downloadUrl,
    required this.mmprojUrl,
    required this.dims,
    required this.multimodal,
    required this.note,
  });
}

class EmbeddingModelCatalogService {
  EmbeddingModelCatalogService._();
  static final EmbeddingModelCatalogService instance =
      EmbeddingModelCatalogService._();

  static const _hfBase = 'https://huggingface.co/unsloth/embeddinggemma-2-GGUF/resolve/main';

  // [Blue 令 2026-10-16 四修] 商店=最新消息，不寫死——每次 App 開拉 HF
  // 對應現役主力家族的最新替代品。_fetched=null（未拉取/失敗）→ 靜態保底。
  List<EmbeddingCatalogEntry>? _fetched;
  DateTime _fetchedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 目錄：動態（HF 最新）優先；離線/失敗 fallback 靜態五檔。
  List<EmbeddingCatalogEntry> get catalog => _fetched ?? _fallbackCatalog;

  /// 從 HuggingFace 拉最新目錄（對應現役主力家族＋泛 embedding 新品）。
  /// 回傳是否成功；成功後 [catalog] 給最新清單。
  Future<bool> refreshFromHuggingFace() async {
    // 24h 快取（App 重開不必每次打 API）
    if (_fetched != null &&
        DateTime.now().difference(_fetchedAt).inHours < 24) {
      return true;
    }
    try {
      // ① 搜尋詞=現役家族（plist 檔名推導）＋泛 embedding
      final activeFile = activeModelPath?.split('/').last ?? '';
      final familyMatch =
          RegExp(r'([a-z0-9\-]+?)-?[A-Z0-9_]+\.gguf').firstMatch(activeFile);
      final family = familyMatch?.group(1) ?? 'embeddinggemma';
      final queries = [
        '$family GGUF',      // 同家族新品（最相關）
        'embedding GGUF',    // 泛 embedding 新品
      ];
      final entries = <EmbeddingCatalogEntry>[];
      final seen = <String>{};
      for (final q in queries) {
        final repos = await _hfJson(
            'https://huggingface.co/api/models?search=${Uri.encodeQueryComponent(q)}'
            '&sort=lastModified&direction=-1&limit=8');
        if (repos is! List) continue;
        for (final repo in repos.take(8)) {
          final repoId = repo['id'] as String?;
          if (repoId == null) continue;
          // ② repo 中繼：siblings 檔案清單＋下載數
          final info = await _hfJson('https://huggingface.co/api/models/$repoId');
          if (info is! Map) continue;
          final siblings = (info['siblings'] as List?)
                  ?.map((e) => (e['rfilename'] as String?) ?? '')
                  .where((f) => f.endsWith('.gguf'))
                  .toList() ??
              const <String>[];
          final mmproj = siblings.firstWhere(
              (f) => f.contains('mmproj') && !f.contains('imatrix'),
              orElse: () => '');
          final downloads = (info['downloads'] as num?)?.toInt() ?? 0;
          final lastMod = ((info['lastModified'] as String?) ?? '');
          // ③ 主檔候選：排除 mmproj/imatrix——挑量化檔（含 Q 者）
          final mains = siblings
              .where((f) =>
                  !f.contains('mmproj') &&
                  !f.contains('imatrix') &&
                  !f.startsWith('.'))
              .toList();
          for (final main in mains.take(4)) {
            final fname = main.split('/').last;
            final key = '$repoId/$fname';
            if (seen.contains(key)) continue;
            seen.add(key);
            final quant = RegExp(r'([A-Z0-9_]*Q[0-9][A-Z0-9_]*|[FI]16|BF16)')
                    .firstMatch(fname)
                    ?.group(1) ??
                'GGUF';
            final isMmprojAvailable = mmproj.isNotEmpty;
            entries.add(EmbeddingCatalogEntry(
              id: key,
              name: '${family == 'embeddinggemma' ? 'EmbeddingGemma 系新品' : family} · $quant',
              family: family,
              quantization: quant,
              sizeMb: 0, // HF API 不給 size——顯示「—」，下載時 curl 自會知道
              fileName: fname,
              mmprojFile: mmproj.split('/').last,
              downloadUrl: 'https://huggingface.co/$repoId/resolve/main/$main',
              mmprojUrl: mmproj.isEmpty
                  ? ''
                  : 'https://huggingface.co/$repoId/resolve/main/$mmproj',
              dims: 768,
              multimodal: isMmprojAvailable,
              note: '$repoId · 下載 ${_fmtK(downloads)} 次'
                  '${lastMod.length >= 10 ? ' · 更新 ${lastMod.substring(0, 10)}' : ''}'
                  '${isMmprojAvailable ? ' · 支援圖片' : ' · 純文字嵌入'}',
            ));
          }
          if (entries.length >= 12) break; // 上限——商店一頁可讀
        }
        if (entries.length >= 12) break;
      }
      if (entries.isEmpty) return false;
      _fetched = entries;
      _fetchedAt = DateTime.now();
      debugPrint('[EmbeddingCatalog] HF 動態目錄 ${entries.length} 條（家族=$family）');
      return true;
    } catch (e) {
      debugPrint('[EmbeddingCatalog] HF 目錄拉取失敗（用靜態保底）: $e');
      return false;
    }
  }

  String _fmtK(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : '$n';

  Future<dynamic> _hfJson(String url) async {
    final req = await HttpClient().getUrl(Uri.parse(url));
    final resp = await req.close();
    if (resp.statusCode != 200) return null;
    return jsonDecode(await resp.transform(utf8.decoder).join());
  }

  /// 靜態保底目錄（離線時）。第一項=現役家族的穩定版本。
  List<EmbeddingCatalogEntry> get _fallbackCatalog => const [
        EmbeddingCatalogEntry(
          id: 'eg2-300m-q8',
          name: 'EmbeddingGemma 2 · Q8_0（現役）',
          family: 'embeddinggemma-2',
          quantization: 'Q8_0',
          sizeMb: 310,
          fileName: 'embeddinggemma-2-Q8_0.gguf',
          mmprojFile: 'mmproj-eg2-Q8_0.gguf',
          downloadUrl: '$_hfBase/embeddinggemma-2-Q8_0.gguf',
          mmprojUrl: '$_hfBase/mmproj-Q8_0.gguf', // 555MB 統一 Q8 投影
          dims: 768,
          multimodal: true,
          note: '目前主力。品質與大小的平衡點，支援圖片嵌入。',
        ),
        EmbeddingCatalogEntry(
          id: 'eg2-300m-q6',
          name: 'EmbeddingGemma 2 · Q6_K_XL',
          family: 'embeddinggemma-2',
          quantization: 'UD-Q6_K_XL',
          sizeMb: 249,
          fileName: 'embeddinggemma-2-UD-Q6_K_XL.gguf',
          mmprojFile: 'mmproj-Q8_0.gguf',
          downloadUrl: '$_hfBase/embeddinggemma-2-UD-Q6_K_XL.gguf',
          mmprojUrl: '$_hfBase/mmproj-Q8_0.gguf',
          dims: 768,
          multimodal: true,
          note: '小 20%，品質幾乎不掉——低記憶體機器的好選擇。',
        ),
        EmbeddingCatalogEntry(
          id: 'eg2-300m-q5',
          name: 'EmbeddingGemma 2 · Q5_K_XL',
          family: 'embeddinggemma-2',
          quantization: 'UD-Q5_K_XL',
          sizeMb: 210,
          fileName: 'embeddinggemma-2-UD-Q5_K_XL.gguf',
          mmprojFile: 'mmproj-Q8_0.gguf',
          downloadUrl: '$_hfBase/embeddinggemma-2-UD-Q5_K_XL.gguf',
          mmprojUrl: '$_hfBase/mmproj-Q8_0.gguf',
          dims: 768,
          multimodal: true,
          note: '輕量型。農場筆記類文本夠用，長尾語感略損。',
        ),
        EmbeddingCatalogEntry(
          id: 'eg2-300m-q4',
          name: 'EmbeddingGemma 2 · Q4_K_XL',
          family: 'embeddinggemma-2',
          quantization: 'UD-Q4_K_XL',
          sizeMb: 176,
          fileName: 'embeddinggemma-2-UD-Q4_K_XL.gguf',
          mmprojFile: 'mmproj-Q8_0.gguf',
          downloadUrl: '$_hfBase/embeddinggemma-2-UD-Q4_K_XL.gguf',
          mmprojUrl: '$_hfBase/mmproj-Q8_0.gguf',
          dims: 768,
          multimodal: true,
          note: '最省空間。快速試水或空間緊張時用。',
        ),
        EmbeddingCatalogEntry(
          id: 'eg2-300m-f16',
          name: 'EmbeddingGemma 2 · F16（無量化）',
          family: 'embeddinggemma-2',
          quantization: 'F16',
          sizeMb: 558,
          fileName: 'embeddinggemma-2-F16.gguf',
          mmprojFile: 'mmproj-Q8_0.gguf',
          downloadUrl: '$_hfBase/embeddinggemma-2-F16.gguf',
          mmprojUrl: '$_hfBase/mmproj-Q8_0.gguf',
          dims: 768,
          multimodal: true,
          note: '滿血精度。追求檢索極致、空間充裕時用。',
        ),
      ];

  /// models/ 目錄。
  static String get modelsDir =>
      '${Platform.environment['HOME'] ?? ''}/Library/Application Support/Bridge/LocalRuntime/models';

  /// 某 entry 是否已下載（主檔＋mmproj 都在）。
  bool isDownloaded(EmbeddingCatalogEntry e) =>
      File('$modelsDir/${e.fileName}').existsSync() &&
      (!e.multimodal || File('$modelsDir/${e.mmprojFile}').existsSync());

  /// 下載進度回報（0.0-1.0）。
  Future<bool> download(
    EmbeddingCatalogEntry e, {
    void Function(double fraction)? onProgress,
  }) async {
    final ok1 = await _curlDownload(
      e.downloadUrl,
      '$modelsDir/${e.fileName}',
      expectedMb: e.sizeMb,
      onProgress: (f) => onProgress?.call(f * (e.multimodal ? 0.9 : 1.0)),
    );
    if (!ok1) return false;
    if (e.multimodal) {
      final ok2 = await _curlDownload(
        e.mmprojUrl,
        '$modelsDir/${e.mmprojFile}',
        expectedMb: 981,
        onProgress: (f) => onProgress?.call(0.9 + f * 0.1),
      );
      if (!ok2) return false;
    }
    return true;
  }

  /// curl 下載（支援續傳）。
  /// [小葵 2026-10-16 審計修] 原版解析 curl stderr % ——但 curl 非互動模式
  /// 不輸出進度表，regex 永遠抓不到（進度條恆 0 的擺設）。
  /// 改：背景輪詢 dest 檔案大小 / Content-Length——真實位元組級進度。
  Future<bool> _curlDownload(
    String url,
    String dest,
    {required int expectedMb, void Function(double)? onProgress}
  ) async {
    try {
      final file = File(dest);
      final partial = file.existsSync() ? file.lengthSync() : 0;
      final expectedBytes = expectedMb * 1024 * 1024;
      if (partial > 0 && partial >= expectedBytes * 0.95) return true; // 已存在
      final args = [
        '-L', '--fail', '--retry', '3',
        '-C', '-', // 續傳
        '-sS',     // 靜默（錯誤才輸出）——進度改用檔案大小輪詢
        '-o', dest,
        url,
      ];
      final proc = await Process.start('curl', args);
      // 位元組級進度輪詢（500ms）
      Timer? progressTimer;
      if (onProgress != null) {
        progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
          try {
            if (file.existsSync()) {
              final done = file.lengthSync();
              onProgress((done / expectedBytes).clamp(0.0, 1.0));
            }
          } catch (_) {}
        });
      }
      final code = await proc.exitCode;
      progressTimer?.cancel();
      if (code == 0 && onProgress != null) onProgress(1.0);
      return code == 0;
    } catch (e) {
      debugPrint('[EmbeddingCatalog] 下載失敗 $url: $e');
      return false;
    }
  }

  /// 18890 現在載的是哪個模型（讀 launchd plist 的 -m 參數）。
  String? get activeModelPath {
    try {
      final plist = File(
          '${Platform.environment['HOME']}/Library/LaunchAgents/farm.semiwasabi.bridgeApp.eg2.plist');
      if (!plist.existsSync()) return null;
      final xml = plist.readAsStringSync();
      final m = RegExp(r'<string>([^<]*\.gguf)</string>').firstMatch(xml);
      return m?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// 換主力：改 plist 的 -m/--mmproj 路徑 → 重啟 launchd 服務。
  /// 回傳成功與否。重嵌（eg2_reembed）由呼叫端在 server 起來後觸發。
  Future<bool> switchPrimary(EmbeddingCatalogEntry e) async {
    try {
      final home = Platform.environment['HOME']!;
      final plistPath = '$home/Library/LaunchAgents/farm.semiwasabi.bridgeApp.eg2.plist';
      final plist = File(plistPath);
      if (!plist.existsSync()) return false;
      var xml = plist.readAsStringSync();
      // [審計修 2026-10-16 #10] 加固：定位「-m」參數的下一個 <string>
      // （不依賴「第一個含 embeddinggemma 的字串」這種排版慣例）
      final mainRe = RegExp(r'(<string>-m</string>\s*<string>)([^<]*)(</string>)');
      if (!mainRe.hasMatch(xml)) return false;
      xml = xml.replaceFirst(mainRe, r'\1' '$modelsDir/${e.fileName}' r'\3');
      // 替換 --mmproj 後的路徑
      if (e.multimodal) {
        final mmRe = RegExp(r'(<string>)([^<]*mmproj[^<]*\.gguf)(</string>)');
        xml = xml.replaceFirst(mmRe, '<string>$modelsDir/${e.mmprojFile}</string>');
      }
      plist.writeAsStringSync(xml);
      // 重啟服務
      final r = await Process.run('bash', [
        '-c',
        r'launchctl kickstart -k gui/$(id -u)/farm.semiwasabi.bridgeApp.eg2',
      ]);
      return r.exitCode == 0;
    } catch (e) {
      debugPrint('[EmbeddingCatalog] 換主力失敗: $e');
      return false;
    }
  }

  /// 快測：起臨時 llama-server（埠 18899，不動 18890 主力）跑幾筆中文檢索命中。
  /// 回傳 (ok, 詳情)。modelPath=null 時用 18890 現役（免重啟，最快）。
  Future<({bool ok, String detail})> quickTest(String? modelPath) async {
    const port = 18899;
    Process? p;
    try {
      if (modelPath != null) {
        // [審計修正] mmproj 統一 Q8（555MB）；不存在時退回現役 eg2 檔；再沒有就不帶 mmproj
        var mmproj = '$modelsDir/mmproj-Q8_0.gguf';
        if (!File(mmproj).existsSync()) {
          mmproj = '$modelsDir/mmproj-eg2-Q8_0.gguf'; // 舊命名（現役檔）
        }
        final mmArgs = File(mmproj).existsSync() ? ['--mmproj', mmproj] : <String>[];
        p = await Process.start(
          '$modelsDir/../runtime/bin/llama-server',
          ['-m', modelPath, ...mmArgs, '--embedding', '--host', '127.0.0.1',
           '--port', '$port', '-ub', '2048'],
        );
        // 等 health
        var up = false;
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          try {
            final r = await HttpClient().getUrl(Uri.parse('http://127.0.0.1:$port/health'));
            final resp = await r.close();
            if (resp.statusCode == 200) { up = true; break; }
          } catch (_) {}
        }
        if (!up) return (ok: false, detail: '測試引擎啟動失敗（30 秒無回應）');
        // [審計修 2026-10-16] 埠碰撞防呆——18899 被別人佔時 health 會通過
        // （測到未知引擎）。用 /props 驗 model_path 真的是指定檔。
        try {
          final pr = await HttpClient().getUrl(Uri.parse('http://127.0.0.1:$port/props'));
          final presp = await pr.close();
          final pbody = jsonDecode(await presp.transform(utf8.decoder).join());
          final mpath = ((pbody['model_path'] ?? pbody['default_model'] ?? '') as String);
          if (!mpath.contains(modelPath.split('/').last)) {
            return (ok: false, detail: '測試埠 $port 被其他引擎佔用（偵測到 ${mpath.split("/").last}）——請稍後重試');
          }
        } catch (_) {
          return (ok: false, detail: '測試引擎身分驗證失敗（/props 無回應）');
        }
      }
      final target = modelPath != null ? port : 18890;
      final client = HttpClient();
      // 三筆語意測試：同義不同字——模型好=向量距離近
      final pairs = [
        ('鹿角蕨怎麼澆水', '蕨類植物的澆水頻率'),
        ('今天很熱', '氣溫很高'),
        ('幫我記住這件事', '請把這個存進記憶'),
      ];
      double sum = 0;
      for (final (a, b) in pairs) {
        final va = await _embed(client, target, a);
        final vb = await _embed(client, target, b);
        if (va == null || vb == null) {
          return (ok: false, detail: '嵌入呼叫失敗（$a）');
        }
        sum += _cosine(va, vb);
      }
      final avg = sum / pairs.length;
      // 中文同義對 cos 相似度經驗閾值：>0.6 健康；<0.45 異常
      final ok = avg > 0.55;
      final verdict = avg > 0.65
          ? '優秀'
          : avg > 0.55 ? '良好' : avg > 0.45 ? '偏弱' : '異常';
      return (ok: ok, detail: '同義對平均相似度 ${avg.toStringAsFixed(3)}（$verdict）');
    } catch (e) {
      return (ok: false, detail: '測試失敗：$e');
    } finally {
      p?.kill();
    }
  }

  Future<List<double>?> _embed(HttpClient client, int port, String text) async {
    try {
      final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port/embeddings'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'content': [text]}));
      final resp = await req.close();
      final body = jsonDecode(await resp.transform(utf8.decoder).join());
      final data = body is List ? body : (body['data'] as List);
      var emb = data[0]['embedding'];
      if (emb is List && emb.isNotEmpty && emb[0] is List) emb = emb[0];
      return (emb as List).cast<num>().map((v) => v.toDouble()).toList();
    } catch (_) {
      return null;
    }
  }

  double _cosine(List<double> a, List<double> b) {
    var dot = 0.0;
    var na = 0.0;
    var nb = 0.0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (na * nb).sqrt0();
  }
}

extension on double {
  double sqrt0() => sqrt0Impl();
  double sqrt0Impl() {
    // dart:math sqrt 不進 extension——手寫牛頓法（維度 768，收斂快）
    if (this <= 0) return 0;
    var x = this;
    for (var i = 0; i < 40; i++) {
      x = (x + this / x) / 2;
    }
    return x;
  }
}
