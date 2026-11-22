// MemoryProvenanceService — 記憶出處簽章（防外部植入虛假記憶）
// [小葵 2026-11-11 Blue 紅隊演習] 攻擊面：任何同帳號 process 可直寫
// brain_container.db 的 agent_memories（FTS 立即可搜），且 App 重啟時
// AgentMemoryBackfillService 會幫無主記憶補嵌向量＝系統親手洗白植入記憶。
//
// 防護設計（Blue 拍板 2026-11-11：往回走修防護）：
//   1. secret 存 macOS Keychain（攻擊 process 讀不到）——HMAC-SHA256 簽章
//   2. 所有合法寫入點寫入時簽章（createMemory / MemoryLayerService.write /
//      L4 belief / hermes_lossless_importer）
//   3. 補嵌服務驗章才嵌入（斷「洗白」路）
//   4. 檢索層（語意＋FTS）過濾無章條目
//   5. 啟動稽核：無章條目 → is_archived=1（隔離非刪除，記憶鐵律）＋標籤曝光
//
// 簽章範圍：(id, title, owner) 三元組——簽 content 全文會讓編輯記憶
// （M5+ updateEntry）後簽章失效，編輯後重簽走 [reSign]。
//
// 爺爺條款：防護上線當下已存在的條目一次性補簽（視為合法）。攻擊窗口
// ＝上線前直寫的植入記憶也會被補簽——窗口需本機同帳號存取權，接受。

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../storage_service.dart';

import 'brain_database.dart';

class MemoryProvenanceService {
  static final MemoryProvenanceService instance = MemoryProvenanceService._();

  MemoryProvenanceService._();

  // [2026-11-12 Blue 令：授權整合] 委派 StorageService.secureStorage——
  // 全 App 一把 Keychain 鑰匙（開 App 只授權一次）。舊鑰匙項目開機遷移後清除。
  static FlutterSecureStorage get _secure => StorageService.secureStorage;

  static const _legacySecure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    mOptions: MacOsOptions(
      accountName: 'Bridge Memory Provenance',
      useDataProtectionKeyChain: false,
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const _keySecret = 'memory_provenance_secret_v1';
  static const _keyGrandfatherDone = 'memory_provenance_grandfather_v1';

  String? _cachedSecret;

  /// [2026-11-12 授權整合] 舊鑰匙（Bridge Memory Provenance）→ 唯一鑰匙遷移。
  /// 讀不到舊值=沒裝過舊版，靜默跳過；遷移成功即刪舊項（不再觸發第二次授權）。
  Future<void> _migrateLegacyKeychain() async {
    try {
      final existing = await _secure.read(key: _keySecret);
      if (existing != null) return; // 已在新鑰匙上
      final legacy = await _legacySecure.read(key: _keySecret);
      if (legacy != null) {
        await _secure.write(key: _keySecret, value: legacy);
        await _legacySecure.delete(key: _keySecret);
        await _legacySecure.delete(key: _keyGrandfatherDone);
      }
    } catch (_) {
      // 舊鑰匙讀取失敗（使用者拒絕授權）——不擋開機，下次再試
    }
  }

  bool _verifyReady = false;

  String _payload(String id, String title, String owner) => '$id|$title|$owner';

  /// 載入（或首次產生）HMAC secret。回 null = Keychain 不可用。
  Future<String?> _loadSecret() async {
    if (_cachedSecret != null) return _cachedSecret;
    try {
      await _migrateLegacyKeychain();
      var s = await _secure.read(key: _keySecret);
      if (s == null || s.isEmpty) {
        final rand = Random.secure();
        s = List<int>.generate(32, (_) => rand.nextInt(256))
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        await _secure.write(key: _keySecret, value: s);
        debugPrint('[MemoryProvenance] 已產生新 secret（首次啟用）');
      }
      _cachedSecret = s;
      _verifyReady = true;
      return s;
    } catch (e) {
      debugPrint('[MemoryProvenance] secret 載入/產生失敗: $e');
      return null;
    }
  }

  /// 簽章（HMAC-SHA256, hex）。secret 不可用回 null —— 呼叫端 fail-closed：
  /// 拿不到簽章就拒絕寫入（絕不無章寫入）。
  Future<String?> sign(String id, String title, String owner) async {
    final secret = await _loadSecret();
    if (secret == null) return null;
    final hmac = Hmac(sha256, utf8.encode(secret));
    return hmac.convert(utf8.encode(_payload(id, title, owner))).toString();
  }

  /// 同步驗章（須 [ensureReady] 已跑過）。sig 空 → false。
  bool verify(String id, String title, String owner, String? sig) {
    if (sig == null || sig.isEmpty) return false;
    final secret = _cachedSecret;
    if (secret == null) return false;
    final hmac = Hmac(sha256, utf8.encode(secret));
    final expect = hmac.convert(utf8.encode(_payload(id, title, owner)));
    return expect.toString() == sig;
  }

  /// 啟動時呼叫：載入 secret 到記憶體（驗章用）。非同步失敗不擋啟動。
  Future<void> ensureReady() async {
    await _loadSecret();
  }

  bool get isVerifyReady => _verifyReady && _cachedSecret != null;

  /// 編輯記憶（M5+ updateEntry）後重簽——title 變了章就失效。
  Future<void> reSign(String id, String newTitle, String owner) async {
    final sig = await sign(id, newTitle, owner);
    if (sig == null) return;
    BrainDatabase.instance.db.execute(
      'UPDATE agent_memories SET provenance_sig = ? WHERE id = ?',
      [sig, id],
    );
  }

  /// 爺爺條款：上線後首次啟動，把當下已存在的全部條目一次性補簽。
  /// 冪等：marker 存在即跳過（存 Keychain 而非 DB——攻擊者直寫 DB 碰不到）。
  Future<int> backfillGrandfathered() async {
    final marker = await _secure.read(key: _keyGrandfatherDone);
    if (marker != null) return 0;
    final secretOk = await _loadSecret();
    if (secretOk == null) return 0;
    final db = BrainDatabase.instance.db;
    final rows = db.select(
      'SELECT id, title, owner_companion_id FROM agent_memories',
    );
    var signed = 0;
    for (final r in rows) {
      final sig = await sign(
        r['id'] as String,
        (r['title'] as String?) ?? '',
        (r['owner_companion_id'] as String?) ?? 'shared',
      );
      if (sig == null) continue;
      db.execute(
        'UPDATE agent_memories SET provenance_sig = ? WHERE id = ?',
        [sig, r['id']],
      );
      signed++;
    }
    await _secure.write(key: _keyGrandfatherDone, value: 'done:$signed');
    debugPrint('[MemoryProvenance] 爺爺條款補簽完成：$signed 條');
    return signed;
  }

  /// 啟動稽核：找出無章條目（爺爺條款跑完後仍無章＝外部植入）→
  /// is_archived=1 隔離（記憶鐵律：不刪除）＋加標籤曝光。回傳隔離數。
  Future<int> auditAndQuarantine() async {
    if (!isVerifyReady) await _loadSecret();
    if (!isVerifyReady) return 0;
    final db = BrainDatabase.instance.db;
    final rows = db.select(
      'SELECT id, title, owner_companion_id, provenance_sig, tags, is_archived '
      'FROM agent_memories WHERE is_archived = 0',
    );
    var quarantined = 0;
    for (final r in rows) {
      final ok = verify(
        r['id'] as String,
        (r['title'] as String?) ?? '',
        (r['owner_companion_id'] as String?) ?? 'shared',
        r['provenance_sig'] as String?,
      );
      if (ok) continue;
      final tags = (r['tags'] as String?) ?? '';
      final newTags = tags.isEmpty
          ? 'provenance_unverified'
          : '$tags,provenance_unverified';
      db.execute(
        'UPDATE agent_memories SET is_archived = 1, tags = ? WHERE id = ?',
        [newTags, r['id']],
      );
      quarantined++;
    }
    if (quarantined > 0) {
      debugPrint('[MemoryProvenance] ⚠️ 稽核隔離 $quarantined 條無章記憶'
          '（provenance_unverified，已 archived）');
    }
    return quarantined;
  }
}
