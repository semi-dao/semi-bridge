// [小葵 2026-09-21] R3——K1 決策頭（純 Dart softmax regression）
//
// 設計稿：docs/K1_DECISION_GATEKEEPER_DESIGN.md v0.1（Blue 拍板 escalate=0.7）
// 實證背書：2026-09-21 LOO-CV 79%/97%（39 題 $9 對話 ground truth）
//
// 設計鐵則：
// - 零外部依賴——768 維×N 類的矩陣乘手寫（微秒級）
// - 單調升級——新權重必須在保留集 ≥ 舊權重才替換
// - 底座可換——只吃 embedding 向量，不綁特定模型（模型跟隨鐵則）

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// K1 標籤體系（v1 四類；二元化生死題 = need/no）
class K1Labels {
  static const needMemoryLookup = 'need_memory_lookup';
  static const repeatQuery = 'repeat_query';
  static const directAction = 'direct_action';
  static const generalChat = 'general_chat';

  static const all = [
    needMemoryLookup,
    repeatQuery,
    directAction,
    generalChat,
  ];

  /// 二元化：查/不查記憶（守門員的生死題）
  static const needSet = {needMemoryLookup, repeatQuery};

  // [小葵 2026-10-13 路線1] 二元頭標籤——4 類 LOO 天花板 ~51%（表徵×rubric×容量
  // 三元瓶頸，實證見 docs/K1_EG2_MIGRATION_PLAN.md §2），二元 78% 過門檻。
  /// 二元「不查」標籤：direct_action + general_chat 的合併
  static const noLookup = 'no_lookup';

  /// 二元標籤集
  static const binaryAll = [needMemoryLookup, noLookup];

  /// 4 類 → 二元映射（訓練引導用）
  static String toBinary(String label) =>
      isNeed(label) ? needMemoryLookup : noLookup;

  static bool isNeed(String label) =>
      needSet.contains(label) || label == needMemoryLookup;
}

/// K1 判斷結果
class K1Decision {
  final String label;
  final double confidence; // softmax top1
  final double margin; // top1 - top2
  final bool escalated; // confidence < 閾值 或 margin 太薄
  final String source; // rule / head / escalate

  const K1Decision({
    required this.label,
    required this.confidence,
    required this.margin,
    required this.escalated,
    required this.source,
  });

  bool get needMemory => K1Labels.isNeed(label);
}

/// 線性分類頭（softmax regression，純 Dart）
class DecisionHead {
  final List<String> labels;
  final List<List<double>> w; // [dim][nLabels]
  final List<double> b; // [nLabels]
  final int trainedAtMs; // 訓練時間
  final int sampleCount; // 訓練樣本數
  final double holdoutAcc; // 保留集準確率（單調升級用）

  const DecisionHead({
    required this.labels,
    required this.w,
    required this.b,
    required this.trainedAtMs,
    required this.sampleCount,
    required this.holdoutAcc,
  });

  int get dim => w.length;

  /// 前向傳播：embedding → (各類機率)
  List<double> softmax(List<double> x) {
    final logits = List<double>.filled(labels.length, 0.0);
    for (var c = 0; c < labels.length; c++) {
      var z = b[c];
      for (var d = 0; d < dim; d++) {
        z += w[d][c] * x[d];
      }
      logits[c] = z;
    }
    final mx = logits.reduce(math.max);
    var sum = 0.0;
    final exp = List<double>.filled(logits.length, 0.0);
    for (var c = 0; c < logits.length; c++) {
      exp[c] = math.exp(logits[c] - mx);
      sum += exp[c];
    }
    return [for (final e in exp) e / sum];
  }

  Map<String, dynamic> toJson() => {
        'labels': labels,
        'w': w,
        'b': b,
        'trained_at_ms': trainedAtMs,
        'sample_count': sampleCount,
        'holdout_acc': holdoutAcc,
      };

  static DecisionHead fromJson(Map<String, dynamic> j) => DecisionHead(
        labels: (j['labels'] as List).cast<String>(),
        w: (j['w'] as List)
            .map((row) => (row as List).cast<double>())
            .toList(),
        b: (j['b'] as List).cast<double>(),
        trainedAtMs: j['trained_at_ms'] as int? ?? 0,
        sampleCount: j['sample_count'] as int? ?? 0,
        holdoutAcc: (j['holdout_acc'] as num?)?.toDouble() ?? 0.0,
      );
}

/// 訓練器（SGD softmax regression）——App 內自訓練的核心
class DecisionHeadTrainer {
  /// [samples]：(embedding, label) 對。dim 由第一個樣本決定。
  /// [epochs]=300, [lr]=0.5, [l2]=1e-3（與 2026-09-21 benchmark 同參數）。
  static DecisionHead train(
    List<(List<double>, String)> samples, {
    int epochs = 300,
    double lr = 0.5,
    double l2 = 1e-3,
    int trainedAtMs = 0,
    double holdoutAcc = 0.0,
    List<String>? labelSet, // [小葵 2026-10-13 路線1] 二元頭用 K1Labels.binaryAll
  }) {
    final labels = labelSet ?? K1Labels.all;
    final dim = samples.first.$1.length;
    final n = samples.length;
    final w = [
      for (var d = 0; d < dim; d++) List<double>.filled(labels.length, 0.0)
    ];
    final b = List<double>.filled(labels.length, 0.0);
    final yIdx = <int>[];
    for (final s in samples) {
      yIdx.add(labels.indexOf(s.$2));
    }
    final rnd = math.Random(42);
    for (var e = 0; e < epochs; e++) {
      // 洗牌（SGD）
      final order = [for (var i = 0; i < n; i++) i]..shuffle(rnd);
      for (final i in order) {
        final x = samples[i].$1;
        final c0 = yIdx[i];
        // forward
        final logits = List<double>.filled(labels.length, 0.0);
        for (var c = 0; c < labels.length; c++) {
          var z = b[c];
          for (var d = 0; d < dim; d++) {
            z += w[d][c] * x[d];
          }
          logits[c] = z;
        }
        final mx = logits.reduce(math.max);
        var sum = 0.0;
        final probs = List<double>.filled(labels.length, 0.0);
        for (var c = 0; c < labels.length; c++) {
          probs[c] = math.exp(logits[c] - mx);
          sum += probs[c];
        }
        for (var c = 0; c < labels.length; c++) {
          probs[c] /= sum;
        }
        // backward（cross-entropy 梯度 = p - y）
        for (var c = 0; c < labels.length; c++) {
          final g = (probs[c] - (c == c0 ? 1.0 : 0.0)) / n;
          for (var d = 0; d < dim; d++) {
            w[d][c] -= lr * (g * x[d] + l2 * w[d][c]);
          }
          b[c] -= lr * g;
        }
      }
    }
    return DecisionHead(
      labels: labels,
      w: w,
      b: b,
      trainedAtMs: trainedAtMs,
      sampleCount: n,
      holdoutAcc: holdoutAcc,
    );
  }
}

/// 權重持久化（JSON 檔，brain_state/）
class DecisionStore {
  final String path;
  DecisionStore(this.path);

  File get _file => File(path);

  DecisionHead? load() {
    try {
      if (!_file.existsSync()) return null;
      final j = jsonDecode(_file.readAsStringSync());
      return DecisionHead.fromJson(j as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 單調升級守門：新頭必須 holdout ≥ 舊頭才落盤
  bool saveMonotonic(DecisionHead newer, DecisionHead? older) {
    if (older != null && newer.holdoutAcc < older.holdoutAcc) {
      return false; // 爛樣本污染防護——不替換
    }
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode(newer.toJson()));
      return true;
    } catch (_) {
      return false;
    }
  }
}
