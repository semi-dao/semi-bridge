// m2_persona_service.dart
//
// [T4② 2026-10-16 編織線] M2 語氣層接進 runtime（D6：語氣層是 App 資產）
//
// 產物：assets/persona/persona_cloud.txt（85K，雲端版）＋
//       assets/persona/persona_e4b.txt（12K，本地 E4B 精簡版）
// 來源：training/semi_s15/m2/m2_compile_prompt.py 編譯 71 條凍結範例——
//       正式版（無 suffix）自動同步落本目錄。訓練目錄的檔案只是中間物。
//
// 選版規則（T7 分流結果決定）：ProviderRouter.current.target == local
//   → e4b 版（12K，塞得進 32K ctx）；cloud → cloud 版（85K 完整語感）。

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';

import '../provider_router.dart';

class M2PersonaService {
  static final M2PersonaService instance = M2PersonaService._();
  M2PersonaService._();

  String? _cloudCache;
  String? _e4bCache;

  /// 目前路由該用的語氣層（null=載入失敗，呼叫端跳過注入 fail-open）
  Future<String?> personaForCurrentRoute() async {
    final isLocal =
        ProviderRouter.instance.current?.target == RoutedTarget.local;
    return isLocal ? e4bPersona() : cloudPersona();
  }

  /// 雲端完整版（85K——71 凍結範例全文語感）
  Future<String?> cloudPersona() async {
    if (_cloudCache != null) return _cloudCache;
    try {
      _cloudCache = await rootBundle.loadString('assets/persona/persona_cloud.txt');
      debugPrint('[M2Persona] cloud 版載入成功（${_cloudCache!.length} 字元）');
      return _cloudCache;
    } catch (e) {
      debugPrint('[M2Persona] cloud 版載入失敗（fail-open 不注入）: $e');
      return null;
    }
  }

  /// E4B 本地精簡版（12K）
  Future<String?> e4bPersona() async {
    if (_e4bCache != null) return _e4bCache;
    try {
      _e4bCache = await rootBundle.loadString('assets/persona/persona_e4b.txt');
      debugPrint('[M2Persona] e4b 版載入成功（${_e4bCache!.length} 字元）');
      return _e4bCache;
    } catch (e) {
      debugPrint('[M2Persona] e4b 版載入失敗（fail-open 不注入）: $e');
      return null;
    }
  }
}
