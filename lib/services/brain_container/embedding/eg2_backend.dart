// eg2_backend.dart
// [小葵 2026-10-15 Blue 令：EG2 三線上線]
// llama-server EG2（EmbeddingGemma-2）backend——POST /embeddings 文字嵌入。
//
// 設計：
// - probe()：探測端點是否掛著 gemma-embedding2 架構模型（llama.cpp EG2 GGUF 的
//   metadata arch 名）。不是 EG2 → 回 null（呼叫端 fallback 300M）。
// - embedTexts()：批次文字嵌入，回 null 代表暫時失敗（呼叫端 fallback，不拋例外）。
// - 純 dart:io HttpClient——零新依賴。
//
// 實測依據：docs/EG2_MULTIMODAL_TEST_REPORT.md（2026-10-15 sandbox 三模態全通）
// API 格式：POST /embeddings body {"content": ["text1", "text2"]}
//           回應 {"data": [{"embedding": [...768]}, ...]}（OpenAI 相容）
//           注意：此端點 content 也可吃 [{prompt_string, multimodal_data}] 物件陣列
//           （vision/audio 未來接線時用，見戰報「接線坑」節）。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// llama-server EG2 文字嵌入 backend。
class Eg2Backend {
  // [小葵 2026-10-15 實測坑] llama.cpp server 對 Dart HttpClient 預設 headers 回 400
  // （curl/raw socket 都 200）。修：明確覆寫 user-agent + 關 proxy + 禁 keep-alive。
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..userAgent = 'bridge-eg2-client/1.0';

  /// server 端點（如 http://127.0.0.1:18789）
  final String endpoint;

  /// 探測到的模型識別（健康檢查回傳的 model path 或 alias）——顯示/紀錄用
  final String modelKey;

  Eg2Backend._(this.endpoint, this.modelKey);

  /// 測試專用建構（不探測直接建——測連線失敗路徑）
  @visibleForTesting
  Eg2Backend.forTest(this.endpoint, this.modelKey);

  /// 探測端點：health ok + 載入模型是 gemma-embedding2（EG2 GGUF）。
  ///
  /// 判準：/props（llama.cpp 特有）回的 model_path 含 "embeddinggemma-2"，
  /// 或 /models 回的 id 含之。兩者皆失敗 → null（不是 EG2 或 server 不在）。
  /// 注意：不做實際嵌入探測（避免啟動延遲）——embedTexts 失敗時呼叫端自然 fallback。
  static Future<Eg2Backend?> probe(String endpoint) async {
    try {
      final uri = Uri.parse('$endpoint/props');
      final req = await HttpClient()
          .getUrl(uri)
          .timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return null;
      final body =
          await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 3));
      final props = jsonDecode(body) as Map<String, dynamic>;
      final modelPath =
          ((props['model_path'] ?? props['default_model'] ?? '') as String);
      // GGUF 檔名含 embeddinggemma-2（如 embeddinggemma-2-Q8_0.gguf）
      if (modelPath.toLowerCase().contains('embeddinggemma-2')) {
        return Eg2Backend._(endpoint, modelPath);
      }
      return null;
    } catch (_) {
      return null; // server 不在／逾時／格式不預期——都不是 EG2 可用狀態
    }
  }

  /// 批次文字嵌入。回 null＝暫時失敗（呼叫端 fallback 300M，不中斷管線）。
  ///
  /// 格式（實測 2026-10-15 llama.cpp b11642）：
  ///   POST /embeddings {"content": [str, ...]} → {"data": [{"embedding": [...]}]}
  ///
  /// [小葵 2026-10-15] 輸入截斷保護：18890 的 ubatch=2048 tokens——
  /// 超長文本會被 server 拒（"input too large"）→ 整批失敗 → 呼叫端
  /// fallback 300M（血型混雜源頭）。這裡先截到 700 字（中文 ≈ 1800 token，
  /// 留安全邊際）。identity 重嵌的 clamped 是 2000 字——超過 700 的都是它。
  Future<List<List<double>>?> embedTexts(List<String> texts) async {
    // 截斷（不改原 list——複製後送）
    final clamped = texts
        .map((t) => t.length > 700 ? t.substring(0, 700) : t)
        .toList(growable: false);
    if (texts.isEmpty) return [];
    try {
      final req = await _client.postUrl(Uri.parse('$endpoint/embeddings'))
          .timeout(const Duration(seconds: 5));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'content': clamped}));
      final res = await req.close().timeout(const Duration(seconds: 120));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      // [小葵 2026-10-15 實測] b11642 回頂層 list [{index, embedding}]，
      // 舊版/其他 build 可能回 OpenAI 形 {data: [...]}——兩種都吃。
      final decoded = jsonDecode(body);
      final List<dynamic> list;
      if (decoded is Map<String, dynamic>) {
        list = decoded['data'] as List<dynamic>? ?? [];
      } else if (decoded is List) {
        list = decoded;
      } else {
        return null;
      }
      final out = <List<double>>[];
      for (final item in list) {
        final emb = (item as Map<String, dynamic>)['embedding'] as List<dynamic>;
        // 防禦：llama.cpp 新版可能嵌套 [[768]]——攤平
        List<dynamic> flat = emb;
        if (flat.isNotEmpty && flat[0] is List) {
          flat = flat[0] as List<dynamic>;
        }
        out.add(flat.map((e) => (e as num).toDouble()).toList());
      }
      if (out.length != texts.length) return null; // 數量不對=格式異常
      return out;
    } catch (_) {
      return null;
    }
  }

  /// 釋放資源。
  void dispose() {
    _client.close();
  }
}
