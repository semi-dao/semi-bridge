// [小葵 2026-10-13] K1 修復線——訓練引導器（bootstrap）
//
// 線頭修復（Blue 拍板 B+複核 2026-10-13）：
//   R3（9-21）實作了規則層+DecisionHead.train，但 loadHead() 全 lib/ 零呼叫、
//   DecisionStore 落盤從未發生、自訓練迴路未接線——頭訓練完就消失。
//
// 本檔補上斷掉的三環：
//   1. bootstrapFromLabels：標註 JSONL → EmbeddingGemma 嵌入 → DecisionHead.train
//      → DecisionStore.saveMonotonic → K1Gatekeeper.loadHead（同一顆 runtime
//      嵌入模型，零 train/infer 偏移）
//   2. restoreFromStore：啟動時從 brain_state/k1_head.json 載回頭
//   3. LOO-CV 評測：訓練前留一交叉驗證，低於門檻拒掛（單調升級守門的資料版）
//
// 設計鐵則（沿 docs/K1_DECISION_GATEKEEPER_DESIGN.md）：
//   - 樣本在標註檔、頭只是衍生物，權重檔可刪可重建（資料主權）
//   - 單調升級：新頭 holdout ≥ 舊頭才落盤
import 'dart:convert';
import 'dart:io';

import '../brain_container/embedding/embedding_service.dart';
import 'decision_head.dart';
import 'k1_gatekeeper.dart';

/// K1 訓練引導器
class K1Bootstrapper {
  K1Bootstrapper._();
  static final K1Bootstrapper instance = K1Bootstrapper._();

  static const _minSamplesPerLabel = 5; // 每類最少樣本（LOO-CV 穩定下限）
  static const _minHoldoutAcc = 0.75; // 4 類 holdout 門檻（設計稿 79% 為目標）

  /// 權重檔路徑（brain_state/，與 DecisionStore 約定一致）
  static String get storePath {
    final dir = Platform.environment['BRIDGE_BRAIN_STATE'] ??
        '${Platform.environment['HOME']}/Library/Application Support/farm.semiwasabi.bridgeApp/brain_state';
    return '$dir/k1_head.json';
  }

  /// 啟動還原：brain_state/k1_head.json → K1Gatekeeper.loadHead
  /// 回傳 null = 無檔或解析失敗（呼叫端照常啟動，K1 走規則層+escalate）
  DecisionHead? restoreFromStore() {
    try {
      final store = DecisionStore(storePath);
      final head = store.load();
      if (head != null) {
        K1Gatekeeper.instance.loadHead(head);
      }
      return head;
    } catch (_) {
      return null;
    }
  }

  /// 從標註檔訓練並掛載。
  ///
  /// [labelsJson] 每行 {"text": "...", "label": "need_memory_lookup|repeat_query|direct_action|general_chat"}
  /// 回傳訓練報告（LOO-CV、樣本數、是否落盤/掛載）。
  Future<Map<String, dynamic>> bootstrapFromLabels(String labelsJson) async {
    final embedder = EmbeddingService.instance;
    if (!embedder.isModelAvailable) {
      return {'ok': false, 'error': 'embedding_model_unavailable'};
    }

    // 1. 解析標註
    final lines = labelsJson
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final samples = <({String text, String label})>[];
    for (final line in lines) {
      try {
        final j = jsonDecode(line) as Map<String, dynamic>;
        final text = (j['text'] ?? '') as String;
        var label = (j['label'] ?? '') as String;
        // [小葵 2026-10-13 路線1] 4 類標註自動映射二元（need/repeat→need，direct/chat→no）
        if (K1Labels.all.contains(label)) label = K1Labels.toBinary(label);
        if (text.isNotEmpty && K1Labels.binaryAll.contains(label)) {
          samples.add((text: text, label: label));
        }
      } catch (_) {
        // 跳過壞行
      }
    }
    if (samples.length < 20) {
      return {'ok': false, 'error': 'too_few_samples', 'n': samples.length};
    }
    final perLabel = <String, int>{};
    for (final s in samples) {
      perLabel[s.label] = (perLabel[s.label] ?? 0) + 1;
    }
    final starved =
        perLabel.entries.where((e) => e.value < _minSamplesPerLabel).toList();
    if (starved.isNotEmpty) {
      return {
        'ok': false,
        'error': 'label_starved',
        'starved': {for (final e in starved) e.key: e.value},
      };
    }

    // 2. 嵌入（runtime 同一顆 EmbeddingGemma，retrievalQuery 前綴）
    final vecs = <List<double>>[];
    for (final s in samples) {
      final v = await embedder.embedQuery(s.text);
      if (v.isEmpty || v.every((x) => x == 0.0)) {
        return {'ok': false, 'error': 'embedding_failed', 'text': s.text};
      }
      vecs.add(v);
    }

    // 3. LOO-CV（留一交叉驗證：n-1 訓練、1 驗證，輪流）——[路線1] 二元直接 4 類精度
    var cvCorrect = 0;
    for (var i = 0; i < samples.length; i++) {
      final train = <(List<double>, String)>[
        for (var j = 0; j < samples.length; j++)
          if (j != i) (vecs[j], samples[j].label)
      ];
      final head = DecisionHeadTrainer.train(
        train,
        epochs: 150, // LOO 用短輪數
        labelSet: K1Labels.binaryAll,
      );
      final probs = head.softmax(vecs[i]);
      var top = 0;
      for (var c = 1; c < probs.length; c++) {
        if (probs[c] > probs[top]) top = c;
      }
      if (head.labels[top] == samples[i].label) cvCorrect++;
    }
    final cv4 = cvCorrect / samples.length;
    if (cv4 < _minHoldoutAcc) {
      return {
        'ok': false,
        'error': 'loo_cv_below_threshold',
        'loo_cv_binary': cv4,
        'threshold': _minHoldoutAcc,
        'n': samples.length,
      };
    }

    // 4. 全量訓練 + 單調落盤 + 掛載
    final fullTrain = <(List<double>, String)>[
      for (var i = 0; i < samples.length; i++) (vecs[i], samples[i].label)
    ];
    final newHead = DecisionHeadTrainer.train(
      fullTrain,
      epochs: 300,
      holdoutAcc: cv4, // LOO-CV 當 holdout 指標
      labelSet: K1Labels.binaryAll,
    );
    final store = DecisionStore(storePath);
    final old = store.load();
    final saved = store.saveMonotonic(newHead, old);
    if (saved) {
      K1Gatekeeper.instance.loadHead(newHead);
    }
    return {
      'ok': true,
      'n': samples.length,
      'per_label': perLabel,
      'loo_cv_binary': cv4,
      'monotonic_saved': saved,
      'mounted': saved,
      'replaced_head': old != null,
    };
  }
}
