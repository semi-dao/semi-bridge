// vector_benchmark_test.dart
// [小葵 2026-09-23] 向量檢索基準——flutter test 環境跑真 EmbeddingGemma。
//
// 為什麼是 flutter test：EmbeddingService 依賴 flutter_gemma 的
// LiteRT dylib（dart:ffi），純 dart run 的 FFI transformer 會 crash；
// flutter test 走 Flutter engine 的 native assets，dylib 可載。
// LiteRT dylib 由 bindings 的 fallback 路徑載入：
// native/litert_lm/prebuilt/macos_arm64/libLiteRtLm.dylib
// （從 build/native_assets/macos 複製——build 產物不進 git）。
//
// 跑法：flutter test tool/memory_benchmark/vector_benchmark_test.dart
// （timeout 拉長：模型載入 + 25 query 推論）

@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:bridge_app/services/brain_container/brain_schema_sql.dart'
    show kVectorInitSql;
import 'package:flutter_gemma/flutter_gemma_interface.dart' show TaskType;
import 'package:flutter_gemma_embeddings/src/litert/litert_embedding_model.dart'
    show LitertEmbeddingModel;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite_vector/sqlite_vector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pipeline_vector 基準（真 EmbeddingGemma 300M）', () async {
    final home = Platform.environment['HOME']!;
    final modelDir =
        '$home/Library/Application Support/farm.semiwasabi.bridgeApp/flutter_gemma';
    final modelPath =
        '$modelDir/embeddinggemma-300M_seq512_mixed-precision.tflite';
    final tokenizerPath = '$modelDir/sentencepiece.model';
    final goldenPath =
        '${Directory.current.path}/tool/memory_benchmark/golden_set.json';

    if (!File(modelPath).existsSync() || !File(goldenPath).existsSync()) {
      // ignore: avoid_print
      print('SKIP：模型或黃金集不存在（$modelPath）');
      return;
    }

    final golden = jsonDecode(File(goldenPath).readAsStringSync())
        as Map<String, dynamic>;
    final corpus = (golden['corpus'] as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final queries = (golden['queries'] as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();

    // 臨時 DB（絕不碰真實 DB）
    final tmpDir = await Directory.systemTemp.createTemp('bridge_vec_bench_');
    addTearDown(() {
      try {
        tmpDir.deleteSync(recursive: true);
      } catch (_) {}
    });
    sqlite3.sqlite3.loadSqliteVectorExtension();
    final db = sqlite3.sqlite3.open('${tmpDir.path}/brain.db');
    db.execute('''
      CREATE TABLE memories (
        id TEXT PRIMARY KEY, content TEXT NOT NULL, room TEXT NOT NULL,
        sub_category TEXT NOT NULL, agent TEXT NOT NULL, companion_id TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL, source_id TEXT, speaker TEXT, project TEXT NOT NULL DEFAULT '',
        tags TEXT NOT NULL DEFAULT '[]', importance INTEGER NOT NULL DEFAULT 3,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, expires_at INTEGER,
        access_count INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0,
        superseded_by TEXT, chunk_index INTEGER NOT NULL DEFAULT 0, total_chunks INTEGER NOT NULL DEFAULT 1,
        parent_memory_id TEXT, integration_result TEXT, embedding BLOB,
        vector_model_version TEXT
      )
    ''');

    // 載真模型
    // ignore: avoid_print
    print('載入 EmbeddingGemma 300M…');
    // [小葵 2026-09-23] vector 索引初始化——per-connection 必跑
    // （brain_schema_sql.dart 頂部註解警告過的坑；忘跑 = vector_full_scan
    //  拋「unable to retrieve context」）
    db.execute(kVectorInitSql);
    final model = await LitertEmbeddingModel.create(
      modelPath: modelPath,
      tokenizerPath: tokenizerPath,
      onClose: () {},
    );
    addTearDown(() => model.close());

    // 語料嵌入
    final now = DateTime.now().millisecondsSinceEpoch;
    // ignore: avoid_print
    print('嵌入 ${corpus.length} 筆語料…');
    for (var i = 0; i < corpus.length; i++) {
      final c = corpus[i];
      final vec = await model.generateEmbedding(
        c['content'] as String,
        taskType: TaskType.retrievalDocument,
      );
      db.execute(
        'INSERT INTO memories (id, content, room, sub_category, agent, source, '
        'importance, created_at, updated_at, embedding, vector_model_version) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, vector_as_f32(?), ?)',
        [
          'mem_$i',
          c['content'],
          c['room'] ?? 'stream',
          'benchmark',
          'bench',
          'chat',
          c['importance'] ?? 3,
          now,
          now,
          jsonEncode(vec),
          'gemma-300m-v1',
        ],
      );
    }

    // 向量 k-NN（production findSimilarMemories 同款 SQL，含 v18 temporal filtering）
    var r1 = 0, r5 = 0, r10 = 0;
    var mrr = 0.0;
    final misses = <String>[];

    for (final q in queries) {
      final query = q['query'] as String;
      final expected = (q['expected_content_substring'] as List)
          .map((e) => e.toString())
          .toList();

      final qvec = await model.generateEmbedding(
        query,
        taskType: TaskType.retrievalQuery,
      );
      final rows = db.select(
        "SELECT m.content, v.distance "
        "FROM memories m "
        "JOIN vector_full_scan('memories', 'embedding', vector_as_f32(?), 10) AS v "
        "  ON m.rowid = v.rowid "
        "WHERE m.archived = 0 "
        "AND m.superseded_by IS NULL "
        "AND (m.expires_at IS NULL OR m.expires_at > ?) "
        "ORDER BY v.distance ASC LIMIT 10",
        [jsonEncode(qvec), now],
      );
      final ranked =
          rows.map((r) => (r['content'] as String?) ?? '').toList();
      // 診斷：印第一個 query 的 top-3 與距離
      if (query == queries.first['query']) {
        // ignore: avoid_print
        print('--- 診斷 top-3 ---');
        final vrows = db.select(
          "SELECT v.rowid AS vid, v.distance FROM vector_full_scan("
          "'memories', 'embedding', vector_as_f32(?), 3) AS v",
          [jsonEncode(qvec)],
        );
        for (final r in vrows) {
          // ignore: avoid_print
          print('  vector_full_scan rowid=${r['vid']} dist=${(r['distance'] as num?)?.toStringAsFixed(4)}');
        }
        final mrows = db.select('SELECT id, rowid FROM memories LIMIT 3');
        for (final r in mrows) {
          // ignore: avoid_print
          print('  memories id=${r['id']} rowid=${r['rowid']}');
        }
      }
      int? hit;
      for (var i = 0; i < ranked.length && hit == null; i++) {
        for (final sub in expected) {
          if (ranked[i].contains(sub)) {
            hit = i + 1;
            break;
          }
        }
      }
      if (hit != null) {
        if (hit == 1) r1++;
        if (hit! <= 5) r5++;
        if (hit! <= 10) r10++;
        mrr += 1.0 / hit;
        // ignore: avoid_print
        print('[${q['note']}] $query → rank $hit');
      } else {
        misses.add(query);
        // ignore: avoid_print
        print('[${q['note']}] $query → miss');
      }
    }

    final n = queries.length;
    final report = {
      'run_at': DateTime.now().toIso8601String(),
      'path': 'pipeline_vector',
      'model': 'gemma-300m-v1 (real LiteRT, flutter test env)',
      'recall@1': r1 / n,
      'recall@5': r5 / n,
      'recall@10': r10 / n,
      'mrr': mrr / n,
      'misses': misses,
    };
    File('${Directory.current.path}/tool/memory_benchmark/vector_results.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(report));
    // ignore: avoid_print
    print('═' * 64);
    // ignore: avoid_print
    print('pipeline_vector（真 Gemma 300M）: '
        'recall@1=${(r1 / n).toStringAsFixed(3)} '
        'recall@5=${(r5 / n).toStringAsFixed(3)} '
        'recall@10=${(r10 / n).toStringAsFixed(3)} '
        'MRR=${(mrr / n).toStringAsFixed(3)}');
    // ignore: avoid_print
    print('misses(${misses.length}): ${misses.join(' / ')}');
    // ignore: avoid_print
    print('報表已寫入 tool/memory_benchmark/vector_results.json');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
