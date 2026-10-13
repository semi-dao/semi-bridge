import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'provider_registry.dart'; // [教練 Agent 2026-07-30] detectAvailableProvider 委派 ProviderRegistry

class StorageService {
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    mOptions: MacOsOptions(
      accountName: 'Bridge Golden Keys',
      // [教練 Agent 2026-07-25] macOS Keychain 策略：
      // - useDataProtectionKeyChain=false：不需要 team ID / code signing
      //   Debug 模式 (ad-hoc signing) 也能用，不會 -34018
      // - accessibility=first_unlock：解鎖一次後不再彈密碼提示
      useDataProtectionKeyChain: false,
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const String _keyGatewayUrl = 'gateway_url';
  static const String _keyProvider = 'provider';
  static const String _keyAuthEnabled = 'auth_enabled';
  static const String _keyAuthType = 'auth_type';
  static const String _keyToken = 'api_token_v2';
  static const String _keyPasscode = 'passcode_v2';
  static const String _keyContextCompressionEnabled =
      'context_compression_enabled';
  static const String _keyLocalModelEndpoint = 'local_model_endpoint';
  static const String _keyLocalModelName = 'local_model_name';
  // [教練 Agent 2026-06-28] 審查 API 獨立設定（預設 fallback 到主腦）
  static const String _keyReviewProvider = 'review_provider';
  static const String _keyReviewGatewayUrl = 'review_gateway_url';
  static const String _keyReviewModel = 'review_model';
  static const String _keyReviewUseMain = 'review_use_main'; // bool, 預設 true
  static final Map<String, String> _tokenMemoryCache = <String, String>{};

  // [教練 Agent 2026-08-11] macOS SharedPreferences 不保證 persist 到磁碟。
  // token 改用獨立 JSON 檔案持久化（dart:io 直寫 Application Support）。
  static File? _tokenStoreFile;
  static Map<String, dynamic>? _tokenStoreCache;

  static Future<File> _getTokenStoreFile() async {
    if (_tokenStoreFile != null) return _tokenStoreFile!;
    // [測試環境] flutter_test 的 FakeAsync 下 path_provider platform
    // message 永遠不回（曾讓 first_summon / golden_keys 測試 600s hang）。
    // 測試可先呼叫 useTestTokenDirectory() 注入臨時目錄，繞過 channel。
    final overrideDir = _testTokenDirOverride;
    if (overrideDir != null) {
      _tokenStoreFile = File('${overrideDir.path}/golden_keys.json');
      return _tokenStoreFile!;
    }
    final dir = await getApplicationSupportDirectory();
    _tokenStoreFile = File('${dir.path}/golden_keys.json');
    return _tokenStoreFile!;
  }

  /// 僅測試用：注入 token store 目錄，避免 path_provider platform channel。
  /// 傳 null 還原。
  static Directory? _testTokenDirOverride;

  @visibleForTesting
  static void useTestTokenDirectory(Directory? dir) {
    _testTokenDirOverride = dir;
    _tokenStoreFile = null;
    _tokenStoreCache = null;
  }

  static Future<Map<String, dynamic>> _loadTokenStore() async {
    if (_tokenStoreCache != null) return _tokenStoreCache!;
    try {
      final file = await _getTokenStoreFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        _tokenStoreCache = jsonDecode(content) as Map<String, dynamic>;
      } else {
        _tokenStoreCache = {};
      }
    } catch (e) {
      debugPrint('[StorageService] 讀取 golden_keys.json 失敗: $e');
      _tokenStoreCache = {};
    }
    return _tokenStoreCache!;
  }

  static Future<void> _persistTokenStore() async {
    if (_tokenStoreCache == null) return;
    try {
      final file = await _getTokenStoreFile();
      final content = jsonEncode(_tokenStoreCache);
      await file.writeAsString(content, flush: true);
      debugPrint('[StorageService] golden_keys.json 已寫入 (${content.length} bytes)');
    } catch (e) {
      debugPrint('[StorageService] 寫入 golden_keys.json 失敗: $e');
    }
  }

  // ========== Token ==========
  //
  // [教練 Agent 2026-07-25] macOS 儲存策略：
  // flutter_secure_storage 在 macOS 有兩個問題：
  //   1. useDataProtectionKeyChain=true → -34018 (需要 team ID code signing)
  //   2. useDataProtectionKeyChain=false → 傳統 keychain 每次彈密碼提示
  // 解法：macOS 直接用 SharedPreferences 存 token（明文，但 app 有 sandbox 保護）
  // iOS/Android 仍用 secure storage
  // [教練 Agent 2026-08-11] macOS 改用 golden_keys.json（dart:io 直寫），
  // 因為 SharedPreferences 在 macOS sandbox 下不保證 persist。
  static bool get _useSecureStorage =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static Future<void> saveToken(String token, {String? provider}) async {
    final tokenKey = await _tokenKey(provider);
    // [教練 Agent 2026-07-25] 空字串不覆蓋已存的 token（保護信任鏈）
    if (token.isEmpty) return;
    if (kIsWeb || !_useSecureStorage) {
      // [教練 Agent 2026-08-11] 雙寫：JSON 檔案（保證 persist）+ SharedPreferences（向後相容讀取）
      final store = await _loadTokenStore();
      store[tokenKey] = token;
      await _persistTokenStore();
      _tokenMemoryCache[tokenKey] = token;
      // 同時寫 SharedPreferences（in-memory cache，有些程式碼可能直接讀 prefs）
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(tokenKey, token);
      } catch (_) {}
      debugPrint('[StorageService] saveToken: key=$tokenKey, len=${token.length}, persisted=true');
      return;
    }
    _tokenMemoryCache[tokenKey] = token;
    try {
      await _secure.write(key: tokenKey, value: token);
    } catch (e) {
      debugPrint('[StorageService] secure storage 寫入失敗: $e');
    }
    // [收斂任務 3] iOS/Android：同時寫入 SharedPreferences 作為 fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fallback_$tokenKey', token);
    } catch (_) {}
  }

  static Future<String?> getToken({String? provider}) async {
    final tokenKey = await _tokenKey(provider);
    // [教練 Agent 2026-08-11] macOS 讀取順序：memory cache → golden_keys.json → SharedPreferences
    if (kIsWeb || !_useSecureStorage) {
      // memory cache
      final cached = _tokenMemoryCache[tokenKey];
      if (cached != null && cached.isNotEmpty) return cached;
      // golden_keys.json
      final store = await _loadTokenStore();
      final jsonToken = store[tokenKey] as String?;
      if (jsonToken != null && jsonToken.isNotEmpty) {
        _tokenMemoryCache[tokenKey] = jsonToken;
        return jsonToken;
      }
      // fallback：舊版 SharedPreferences 資料（GLM/OpenAI/MiniMax 可能還在這裡）
      try {
        final prefs = await SharedPreferences.getInstance();
        final prefsToken = prefs.getString(tokenKey);
        if (prefsToken != null && prefsToken.isNotEmpty) {
          // 遷移到 JSON
          _tokenMemoryCache[tokenKey] = prefsToken;
          store[tokenKey] = prefsToken;
          await _persistTokenStore();
          return prefsToken;
        }
      } catch (_) {}
      return null;
    }
    final cached = _tokenMemoryCache[tokenKey];
    if (cached != null && cached.isNotEmpty) return cached;

    String? token;
    try {
      token = await _secure.read(key: tokenKey) ??
          await _secure.read(key: 'api_token');
    } catch (e) {
      debugPrint('[StorageService] secure storage 讀取失敗: $e');
    }
    if (token != null && token.isNotEmpty) {
      _tokenMemoryCache[tokenKey] = token;
      return token;
    }
    // iOS/Android：fallback 到 SharedPreferences（由 saveToken 的 fallback_ 前綴寫入）
    try {
      final prefs = await SharedPreferences.getInstance();
      final fallback = prefs.getString('fallback_$tokenKey');
      if (fallback != null && fallback.isNotEmpty) {
        _tokenMemoryCache[tokenKey] = fallback;
        return fallback;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> deleteToken({String? provider}) async {
    final tokenKey = await _tokenKey(provider);
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(tokenKey);
      return;
    }
    _tokenMemoryCache.remove(tokenKey);
    await _secure.delete(key: tokenKey);
  }

  /// [教練 Agent 2026-08-08] 金鑰清點——列出所有已存的 token provider 和狀態
  ///
  /// 回傳 Map<providerId, hasToken>——只有 hasToken=true 的 provider 有可用的金鑰。
  /// 用於 CapabilityHealthService 的 verifiedAlternatives 和 UI 金鑰管理頁面。
  static Future<Map<String, bool>> auditAllTokens() async {
    final knownProviders = [
      'glm', 'openai', 'kimi', 'claude', 'gemini',
      'minimax', 'replicate',
    ];
    final result = <String, bool>{};
    for (final provider in knownProviders) {
      final token = await getToken(provider: provider);
      result[provider] = token != null && token.trim().isNotEmpty;
    }
    return result;
  }

  static Future<String> _tokenKey(String? provider) async {
    final resolvedProvider = provider ?? await getProvider() ?? 'default';
    final normalizedProvider = resolvedProvider.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_]+'),
      '_',
    );
    return '${_keyToken}_$normalizedProvider';
  }

  // ========== Passcode ==========
  static Future<void> savePasscode(String code) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPasscode, code);
      return;
    }
    await _secure.write(key: 'passcode', value: code);
  }

  static Future<String?> getPasscode() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyPasscode);
    }
    return await _secure.read(key: 'passcode');
  }

  // ========== Gateway URL ==========
  static Future<void> saveGatewayUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGatewayUrl, url);
  }

  static Future<String?> getGatewayUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyGatewayUrl);
  }

  /// [收斂任務 3] 便捷方法：同時更新 provider 和 gateway_url
  /// 切換 provider 時呼叫此方法，確保 gateway_url 自動同步
  static Future<void> saveProviderConfig(String provider, String? gatewayUrl) async {
    _tokenMemoryCache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProvider, provider);
    if (gatewayUrl != null && gatewayUrl.isNotEmpty) {
      await prefs.setString(_keyGatewayUrl, gatewayUrl);
    }
  }

  // ========== Provider ==========
  static Future<void> saveProvider(String provider) async {
    _tokenMemoryCache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProvider, provider);
  }

  static Future<String?> getProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyProvider);
  }

  // ========== TTS Voice Preference ==========
  // [小葵 2026-09-24] MiniMax TTS 音色偏好（例：xiaokui_video_voice＝小葵 JK2 定案音色）
  static const String _keyTtsVoice = 'tts_voice_preference';

  static Future<void> saveTtsVoicePreference(String voiceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTtsVoice, voiceId);
  }

  static Future<String?> getTtsVoicePreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTtsVoice);
  }

  // ========== API Model (per-provider) ==========
  static const String _keyApiModelPrefix = 'api_model_v2_';

  static Future<void> saveApiModel(String model, {String? provider}) async {
    final p = provider ?? await getProvider() ?? 'default';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyApiModelPrefix$p', model);
  }

  static Future<String?> getApiModel({String? provider}) async {
    final p = provider ?? await getProvider() ?? 'default';
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_keyApiModelPrefix$p');
  }

  /// 掃描所有已設定 token 的 provider，回傳最強大腦
  /// [教練 Agent 2026-07-30] 重構——委派 ProviderRegistry，動態探測 + 能力排序
  /// 舊邏輯：按寫死順序 openai > glm > kimi > minimax > gemini > claude 檢查 token
  /// 新邏輯：ProviderRegistry.discoverAll() 拉取可用模型列表 + 按 Tier 排序
  static Future<String?> detectAvailableProvider() async {
    final best = await ProviderRegistry.instance.selectBestCloud();
    return best?.providerId;
  }

  // ========== Review API (Vision 審查專用) ==========
  // [教練 Agent 2026-06-28] 預設使用主腦設定，可獨立指定不同 provider
  // 設計：A 模型生成 → B 模型審查，支援 DAO 開放社群

  static Future<bool> isReviewUseMain() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyReviewUseMain) ?? true; // 預設 true
  }

  static Future<void> setReviewUseMain(bool useMain) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReviewUseMain, useMain);
  }

  static Future<String?> getReviewProvider() async {
    if (await isReviewUseMain()) return getProvider();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyReviewProvider);
  }

  static Future<void> saveReviewProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyReviewProvider, provider);
  }

  static Future<String?> getReviewGatewayUrl() async {
    if (await isReviewUseMain()) return getGatewayUrl();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyReviewGatewayUrl);
  }

  static Future<void> saveReviewGatewayUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyReviewGatewayUrl, url);
  }

  static Future<String?> getReviewToken() async {
    final provider = await getReviewProvider();
    return getToken(provider: provider);
  }

  static Future<void> saveReviewToken(String token) async {
    final provider = await getReviewProvider();
    if (provider != null) {
      await saveToken(token, provider: 'review_$provider');
    }
  }

  static Future<String?> getReviewModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyReviewModel);
  }

  static Future<void> saveReviewModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyReviewModel, model);
  }

  // ========== Local Model ==========
  static Future<void> saveLocalModelEndpoint(String endpoint) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocalModelEndpoint, endpoint);
  }

  static Future<String?> getLocalModelEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLocalModelEndpoint);
  }

  // [Blue 令 2026-10-05] 本地模型閒置自動卸載開關（預設開）
  static Future<bool> getLocalModelIdleUnloadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('local_model_idle_unload_enabled') ?? true;
  }

  static Future<void> saveLocalModelIdleUnloadEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('local_model_idle_unload_enabled', v);
  }

  static Future<void> saveLocalModelName(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocalModelName, model);
  }

  static Future<String?> getLocalModelName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLocalModelName);
  }

  // ========== 本地模型雙角色槽（自動離合器，小葵 2026-10-01） ==========
  static const _keyLocalCompanionModel = 'local_companion_model';
  static const _keyLocalVisionModel = 'local_vision_model';

  /// 夥伴模型槽（聊天＋簡單任務＋subagent）
  static Future<void> setLocalCompanionModel(String? modelId) async {
    final prefs = await SharedPreferences.getInstance();
    if (modelId == null || modelId.isEmpty) {
      await prefs.remove(_keyLocalCompanionModel);
    } else {
      await prefs.setString(_keyLocalCompanionModel, modelId);
    }
  }

  static Future<String?> getLocalCompanionModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLocalCompanionModel);
  }

  /// 辨識模型槽（照片嵌入＋視覺分析）
  static Future<void> setLocalVisionModel(String? modelId) async {
    final prefs = await SharedPreferences.getInstance();
    if (modelId == null || modelId.isEmpty) {
      await prefs.remove(_keyLocalVisionModel);
    } else {
      await prefs.setString(_keyLocalVisionModel, modelId);
    }
  }

  static Future<String?> getLocalVisionModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLocalVisionModel);
  }

  // ========== Auth Settings ==========
  static Future<void> setAuthEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAuthEnabled, enabled);
  }

  static Future<bool> isAuthEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAuthEnabled) ?? false;
  }

  static Future<void> setAuthType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAuthType, type);
  }

  static Future<String?> getAuthType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAuthType);
  }

  // ========== Context Compression ==========
  static Future<void> setContextCompressionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyContextCompressionEnabled, enabled);
  }

  static Future<bool> isContextCompressionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyContextCompressionEnabled) ?? true;
  }

  // ========== Semantic Intent Feature Flag ==========
  static const String _keySemanticIntentEnabled = 'semantic_intent_enabled';

  static Future<bool> isSemanticIntentEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySemanticIntentEnabled) ?? true; // [Sprint 12] 預設開啟
  }

  static Future<void> setSemanticIntentEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySemanticIntentEnabled, enabled);
  }

  // ========== Entity Graph Feature Flag (S24c) ==========
  static const String _keyEntityGraphEnabled = 'entity_graph_enabled';

  static Future<bool> isEntityGraphEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEntityGraphEnabled) ?? false; // 預設 false——零回歸
  }

  static Future<void> setEntityGraphEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEntityGraphEnabled, enabled);
  }

  // ========== Helpers ==========
  static Future<bool> hasToken() async {
    final provider = await getProvider();
    // [教練 Agent 2026-07-30] 'default' 預設選型——檢查有沒有任一雲端 provider 有 token
    if (provider == 'default') {
      return await hasAnyCloudToken();
    }
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// [教練 Agent 2026-07-30] 檢查是否任一雲端 provider 有 token（用於預設選型模式）
  static Future<bool> hasAnyCloudToken() async {
    final cloudProviders = ProviderRegistry.cloudProviderIds;
    for (final p in cloudProviders) {
      final token = await getToken(provider: p);
      if (token != null && token.isNotEmpty) return true;
    }
    return false;
  }

  static Future<bool> hasConfig() async {
    final url = await getGatewayUrl();
    final token = await getToken();
    return url != null && url.isNotEmpty && token != null && token.isNotEmpty;
  }

  // ========== Capability Unlocked State ==========
  // [以利沙 P0 修復十一輪 2026-06-27] 持久化已開通能力，防止次輪再觸發 gap 卡
  static Future<void> setCapabilityUnlocked(String gapType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('capability_unlocked_$gapType', true);
  }

  static Future<bool> isCapabilityUnlocked(String gapType) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('capability_unlocked_$gapType') ?? false;
  }

  // ========== HuggingFace Token (EmbeddingGemma) ==========
  static const String _keyHfToken = 'hf_token_v1';

  static Future<void> saveHuggingFaceToken(String token) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyHfToken, token);
      return;
    }
    await _secure.write(key: _keyHfToken, value: token);
  }

  static Future<String?> getHuggingFaceToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyHfToken);
    }
    return await _secure.read(key: _keyHfToken);
  }

  static Future<void> deleteHuggingFaceToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyHfToken);
      return;
    }
    await _secure.delete(key: _keyHfToken);
  }
}
