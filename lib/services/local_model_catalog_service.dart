enum LocalModelFit { unknown, excellent, good, limited, unsupported }

enum LocalModelTask {
  privateDraft,
  memoryTidy,
  quickChat,
  coding,
  longReasoning,
}

class LocalHardwareProfile {
  final String source;
  final int? ramGb;
  final int? vramGb;
  final String chipLabel;
  final bool desktopConnected;

  const LocalHardwareProfile({
    required this.source,
    this.ramGb,
    this.vramGb,
    this.chipLabel = '尚未偵測',
    this.desktopConnected = false,
  });

  const LocalHardwareProfile.preview()
    : source = 'preview',
      ramGb = null,
      vramGb = null,
      chipLabel = '等待 Bridge Desktop 回報',
      desktopConnected = false;

  factory LocalHardwareProfile.fromJson(Map<dynamic, dynamic> json) {
    return LocalHardwareProfile(
      source: _readString(json, 'source', 'unknown'),
      ramGb: _readInt(json, 'ramGb'),
      vramGb: _readInt(json, 'vramGb'),
      chipLabel: _readString(json, 'chipLabel', '尚未偵測'),
      desktopConnected: _readBool(json, 'desktopConnected', false),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'source': source,
      'ramGb': ramGb,
      'vramGb': vramGb,
      'chipLabel': chipLabel,
      'desktopConnected': desktopConnected,
    };
  }

  static int? _readInt(Map<dynamic, dynamic> json, String key) {
    final value = json[key];
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String _readString(
    Map<dynamic, dynamic> json,
    String key,
    String fallback,
  ) {
    final value = json[key];
    return value is String && value.isNotEmpty ? value : fallback;
  }

  static bool _readBool(Map<dynamic, dynamic> json, String key, bool fallback) {
    final value = json[key];
    return value is bool ? value : fallback;
  }
}

class LocalModelCatalogEntry {
  final String id;
  final String name;
  final String sizeClass;
  final String quantization;
  final int minRamGb;
  final int recommendedRamGb;
  final int? recommendedVramGb;
  final String downloadSize;
  final String runtime;
  final String sourceLabel;
  final String licenseLabel;
  final String manifestUrl;
  final String checksumSha256;
  final String fileName;
  final String repoId;
  final String downloadUrl;
  final List<LocalModelTask> bestFor;

  const LocalModelCatalogEntry({
    required this.id,
    required this.name,
    required this.sizeClass,
    required this.quantization,
    required this.minRamGb,
    required this.recommendedRamGb,
    required this.recommendedVramGb,
    required this.downloadSize,
    required this.runtime,
    required this.sourceLabel,
    required this.licenseLabel,
    required this.manifestUrl,
    required this.checksumSha256,
    required this.fileName,
    this.repoId = '',
    this.downloadUrl = '',
    required this.bestFor,
  });

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'sizeClass': sizeClass,
      'quantization': quantization,
      'minRamGb': minRamGb,
      'recommendedRamGb': recommendedRamGb,
      'recommendedVramGb': recommendedVramGb,
      'downloadSize': downloadSize,
      'runtime': runtime,
      'sourceManifest': {
        'sourceLabel': sourceLabel,
        'licenseLabel': licenseLabel,
        'manifestUrl': manifestUrl,
        'checksumSha256': checksumSha256,
        'fileName': fileName,
        'repoId': repoId,
        'downloadUrl': downloadUrl,
      },
      'bestFor': bestFor.map((task) => task.name).toList(),
    };
  }
}

class LocalModelRecommendation {
  final LocalModelCatalogEntry model;
  final LocalModelFit fit;
  final String reason;

  const LocalModelRecommendation({
    required this.model,
    required this.fit,
    required this.reason,
  });
}

class LocalModelPlan {
  final LocalHardwareProfile hardware;
  final List<LocalModelRecommendation> recommendations;
  final String summary;
  final String nextAction;

  const LocalModelPlan({
    required this.hardware,
    required this.recommendations,
    required this.summary,
    required this.nextAction,
  });

  LocalModelRecommendation? get preferredDownload {
    for (final fit in [
      LocalModelFit.excellent,
      LocalModelFit.good,
      LocalModelFit.limited,
      LocalModelFit.unknown,
    ]) {
      for (final recommendation in recommendations) {
        if (recommendation.fit == fit) return recommendation;
      }
    }
    return null;
  }
}

class LocalModelCatalogService {
  const LocalModelCatalogService();

  List<LocalModelCatalogEntry> catalog() {
    return const [
      // ── 推薦：Qwen3.5-4B ──
      LocalModelCatalogEntry(
        id: 'qwen3.5-4b-q4',
        name: 'Qwen3.5-4B',
        sizeClass: '4B',
        quantization: 'Q4_K_M',
        minRamGb: 8,
        recommendedRamGb: 16,
        recommendedVramGb: null,
        downloadSize: '約 2.52 GB',
        runtime: 'llama.cpp',
        sourceLabel: 'HuggingFace',
        licenseLabel: 'Apache-2.0',
        manifestUrl:
            'https://huggingface.co/HauhauCS/Qwen3.5-4B-Uncensored-HauhauCS-Aggressive',
        checksumSha256: 'pending-verification',
        fileName: 'Qwen3.5-4B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf',
        repoId: 'HauhauCS/Qwen3.5-4B-Uncensored-HauhauCS-Aggressive',
        downloadUrl:
            'https://huggingface.co/HauhauCS/Qwen3.5-4B-Uncensored-HauhauCS-Aggressive/resolve/main/Qwen3.5-4B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf',
        bestFor: [
          LocalModelTask.quickChat,
          LocalModelTask.privateDraft,
          LocalModelTask.memoryTidy,
          LocalModelTask.coding,
        ],
      ),
      // ── Google Gemma-4 12B Unified（多模態：視覺+文字；品質首選） ──
      // [小葵 2026-09-28] 盲測 19/20 = 95%（vs E4B 17/20 = 85%），Blue 拍板為預設本地模型。
      // 16GB 機實測：c=4096 穩定（32768 會 OOM）；速度 ~103s/張（E4B 的 1/2）。
      LocalModelCatalogEntry(
        id: 'gemma-4-12b-q4',
        name: 'Gemma 4 12B',
        sizeClass: '12B',
        quantization: 'Q4_K_M',
        minRamGb: 12,
        recommendedRamGb: 16,
        recommendedVramGb: null,
        downloadSize: '約 7 GB',
        runtime: 'llama.cpp',
        sourceLabel: 'Google · HuggingFace (unsloth)',
        licenseLabel: 'Apache-2.0',
        manifestUrl: 'https://huggingface.co/unsloth/gemma-4-12b-it-GGUF',
        checksumSha256: 'pending-verification',
        fileName: 'gemma-4-12b-it-Q4_K_M.gguf',
        repoId: 'unsloth/gemma-4-12b-it-GGUF',
        downloadUrl:
            'https://huggingface.co/unsloth/gemma-4-12b-it-GGUF/resolve/main/gemma-4-12b-it-Q4_K_M.gguf',
        bestFor: [
          LocalModelTask.quickChat,
          LocalModelTask.privateDraft,
        ],
      ),
      // ── Google Gemma-4 E4B（多模態：語音+視覺+文字；速度首選） ──
      // [小葵 2026-09-28] 盲測 17/20 = 85%，速度 40-55s/張（12B 的 2 倍快）。
      LocalModelCatalogEntry(
        id: 'gemma-4-e4b-q4',
        name: 'Gemma 4 E4B',
        sizeClass: '4B',
        quantization: 'Q4_K_M',
        minRamGb: 8,
        recommendedRamGb: 16,
        recommendedVramGb: null,
        downloadSize: '約 5 GB',
        runtime: 'llama.cpp',
        sourceLabel: 'Google · HuggingFace',
        licenseLabel: 'Apache-2.0',
        manifestUrl:
            'https://huggingface.co/HauhauCS/Gemma-4-E4B-Uncensored-HauhauCS-Aggressive',
        checksumSha256: 'pending-verification',
        fileName: 'Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf',
        repoId: 'HauhauCS/Gemma-4-E4B-Uncensored-HauhauCS-Aggressive',
        downloadUrl:
            'https://huggingface.co/HauhauCS/Gemma-4-E4B-Uncensored-HauhauCS-Aggressive/resolve/main/Gemma-4-E4B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf',
        bestFor: [
          LocalModelTask.quickChat,
          LocalModelTask.privateDraft,
        ],
      ),
      // ── Meta Llama-3.2-3B ──
      LocalModelCatalogEntry(
        id: 'llama-3.2-3b-q4',
        name: 'Llama 3.2 3B',
        sizeClass: '3B',
        quantization: 'Q4_K_M',
        minRamGb: 6,
        recommendedRamGb: 12,
        recommendedVramGb: null,
        downloadSize: '約 1.9 GB',
        runtime: 'llama.cpp',
        sourceLabel: 'Meta · HuggingFace',
        licenseLabel: 'Llama 3.2 Community License',
        manifestUrl: 'https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF',
        checksumSha256: 'pending-verification',
        fileName: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
        repoId: 'unsloth/Llama-3.2-3B-Instruct-GGUF',
        downloadUrl:
            'https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
        bestFor: [
          LocalModelTask.quickChat,
          LocalModelTask.privateDraft,
        ],
      ),
    ];
  }

  LocalModelPlan buildPlan({LocalHardwareProfile? hardware}) {
    final profile = hardware ?? const LocalHardwareProfile.preview();
    if (!profile.desktopConnected || profile.ramGb == null) {
      return LocalModelPlan(
        hardware: profile,
        recommendations: [
          for (final model in catalog())
            LocalModelRecommendation(
              model: model,
              fit: LocalModelFit.unknown,
              reason: '等待 Bridge Desktop 回報硬體後評估。',
            ),
        ],
        summary: '尚未連接 Bridge Desktop，先顯示可下載模型級距。',
        nextAction: '連接桌面後檢測硬體',
      );
    }

    final recommendations = [
      for (final model in catalog())
        LocalModelRecommendation(
          model: model,
          fit: _fitFor(profile, model),
          reason: _reasonFor(profile, model),
        ),
    ];
    return LocalModelPlan(
      hardware: profile,
      recommendations: recommendations,
      summary: _summaryFor(profile, recommendations),
      nextAction: '選擇合適模型下載',
    );
  }

  LocalModelFit _fitFor(
    LocalHardwareProfile hardware,
    LocalModelCatalogEntry model,
  ) {
    final ramGb = hardware.ramGb;
    if (ramGb == null) return LocalModelFit.unknown;
    final vramGb = hardware.vramGb;
    if (ramGb < model.minRamGb) return LocalModelFit.unsupported;
    final vramEnough =
        model.recommendedVramGb == null ||
        (vramGb != null && vramGb >= model.recommendedVramGb!);
    if (ramGb >= model.recommendedRamGb && vramEnough) {
      return LocalModelFit.excellent;
    }
    if (ramGb >= model.recommendedRamGb) return LocalModelFit.good;
    return LocalModelFit.limited;
  }

  String _reasonFor(
    LocalHardwareProfile hardware,
    LocalModelCatalogEntry model,
  ) {
    final ramGb = hardware.ramGb;
    if (ramGb == null) return '等待硬體檢測。';
    if (ramGb < model.minRamGb) {
      return '至少需要 ${model.minRamGb}GB RAM，目前不建議下載。';
    }
    if (ramGb < model.recommendedRamGb) {
      return '可嘗試，但建議關閉其他大型 App，速度可能較慢。';
    }
    if (model.recommendedVramGb != null &&
        (hardware.vramGb == null ||
            hardware.vramGb! < model.recommendedVramGb!)) {
      return 'RAM 足夠，若沒有 ${model.recommendedVramGb}GB VRAM 可能改走 CPU。';
    }
    return '硬體條件適合，可作為本地模型候選。';
  }

  String _summaryFor(
    LocalHardwareProfile hardware,
    List<LocalModelRecommendation> recommendations,
  ) {
    final best = recommendations
        .where(
          (item) =>
              item.fit == LocalModelFit.excellent ||
              item.fit == LocalModelFit.good,
        )
        .map((item) => item.model.sizeClass)
        .toList();
    if (best.isEmpty) {
      return '${hardware.chipLabel} 已連接，但目前只建議使用最輕量模型或雲端補強。';
    }
    return '${hardware.chipLabel} 已連接，適合優先嘗試 ${best.join(' / ')} 本地模型。';
  }
}

extension LocalModelTaskX on LocalModelTask {
  String get label {
    switch (this) {
      case LocalModelTask.privateDraft:
        return '私人草稿';
      case LocalModelTask.memoryTidy:
        return '記憶整理';
      case LocalModelTask.quickChat:
        return '快速對話';
      case LocalModelTask.coding:
        return '程式輔助';
      case LocalModelTask.longReasoning:
        return '長推理';
    }
  }
}

extension LocalModelFitX on LocalModelFit {
  String get label {
    switch (this) {
      case LocalModelFit.unknown:
        return '待檢測';
      case LocalModelFit.excellent:
        return '很適合';
      case LocalModelFit.good:
        return '可用';
      case LocalModelFit.limited:
        return '勉強';
      case LocalModelFit.unsupported:
        return '不建議';
    }
  }
}
