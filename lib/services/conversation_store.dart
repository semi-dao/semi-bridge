import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';

/// [小葵 2026-09-21 Blue 令] 回收桶細目——對話＋刪除時間
class TrashItem {
  final Conversation conversation;
  final DateTime deletedAt;
  const TrashItem({required this.conversation, required this.deletedAt});
}

class ConversationStore {
  static const String _keyConversations = 'bridge_conversations';

  /// [小葵 2026-09-21 P0] 本 session 明確刪除的對話 id——寫入守門員用。
  /// 16:57 事故根因：App 重啟時檔案系統暫態錯誤 → getAll() 回空 →
  /// save() 把空列表寫回 → 19 個對話被 1 個覆寫。
  /// 守門員：_writeAll 縮減列表時，磁碟上多出來的對話（不在刪除清單）
  /// 一律保留——「讀不到」永遠不等於「沒有」。
  static final Set<String> _explicitlyDeleted = {};
  static const String _keyCurrentId = 'bridge_current_conversation_id';
  static const String _storageFolderName = 'bridge_state';
  static const String _storageFileName = 'conversations.json';

  static Directory? _debugStorageDirectory;

  @visibleForTesting
  static void debugSetStorageDirectory(Directory? directory) {
    _debugStorageDirectory = directory;
  }

  static Future<List<Conversation>> getAll() async {
    final file = await _storageFile();
    if (await file.exists()) {
      try {
        final jsonStr = await file.readAsString();
        return _decodeConversations(jsonStr);
      } catch (e) {
        // [教練 Agent 2026-07-23] 檔案損壞時嘗試恢復 — 截掉尾端垃圾資料
        // [教練 Agent 2026-08-02] 增強：同時找最新備份
        debugPrint('[ConversationStore] 讀取失敗，嘗試恢復: $e');
        try {
          // 策略1：截斷尾端
          final raw = await file.readAsBytes();
          for (int i = raw.length; i > 0; i--) {
            try {
              final text = utf8.decode(raw.sublist(0, i));
              final list = jsonDecode(text);
              if (list is List) {
                debugPrint('[ConversationStore] 策略1成功，保留 ${list.length} 條對話');
                await file.writeAsString(text, flush: true);
                return list.map((e) => Conversation.fromJson(e)).toList()
                  ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
              }
            } catch (_) {}
          }

          // 策略2：找最新備份檔還原
          final dir = file.parent;
          final backups = await dir.list().where((e) =>
              e.path.contains('.${_storageFileName}.v')).toList();
          if (backups.isNotEmpty) {
            backups.sort((a, b) => b.path.compareTo(a.path)); // 最新在前
            for (final backup in backups) {
              try {
                final text = await File(backup.path).readAsString();
                final list = jsonDecode(text) as List;
                debugPrint('[ConversationStore] 策略2成功，從備份還原 ${list.length} 條對話');
                await file.writeAsString(text, flush: true);
                return list.map((e) => Conversation.fromJson(e)).toList()
                  ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
              } catch (_) {}
            }
          }
        } catch (e2) {
          debugPrint('[ConversationStore] 恢復失敗: $e2');
        }
        return [];
      }
    }

    final migrated = await _migrateLegacyPrefsIfNeeded(file);
    if (migrated.isNotEmpty) return migrated;

    return [];
  }

  static List<Conversation> _decodeConversations(String jsonStr) {
    if (jsonStr.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      return list.map((e) => Conversation.fromJson(e)).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      return [];
    }
  }

  static Future<void> save(Conversation conversation) async {
    final all = await getAll();
    final index = all.indexWhere((c) => c.id == conversation.id);

    if (index >= 0) {
      all[index] = conversation;
    } else {
      all.add(conversation);
    }

    await _writeAll(all);
  }

  static Future<void> delete(String id) async {
    // [小葵 2026-09-21 Blue 主權鐵則] 軟刪除——刪除=進回收桶，不是焚化爐。
    // 「絕不刪對話記憶」：使用者後悔了要救得回來。
    // 落地：完整對話備份到 bridge_state/trash/（永不清理），再從現行檔移除。
    _explicitlyDeleted.add(id); // [P0] 記進本 session 刪除清單——寫入守門員放行
    try {
      final conv = await getById(id);
      if (conv != null) {
        final trashDir = Directory(
            '${(await _storageFile()).parent.path}/trash');
        if (!await trashDir.exists()) {
          await trashDir.create(recursive: true);
        }
        final trashFile = File('${trashDir.path}/$id.json');
        await trashFile.writeAsString(
            jsonEncode(conv.toJson()), flush: true);
        debugPrint('[ConversationStore] 對話 $id 已進回收桶（可還原）');
      }
    } catch (e) {
      // 回收桶失敗不阻擋刪除主流程，但誠實記 log
      debugPrint('[ConversationStore] 回收桶寫入失敗: $e');
    }
    final all = await getAll();
    all.removeWhere((c) => c.id == id);
    await _writeAll(all);
  }

  /// [小葵 2026-09-21] 回收桶清單（救回 UI 用）
  static Future<List<Conversation>> listTrash() async {
    final items = await listTrashDetailed();
    return items.map((e) => e.conversation).toList();
  }

  /// [小葵 2026-09-21 Blue 令] 回收桶細目——帶刪除時間（檔案 mtime），
  /// UI 以日期分組顯示，累積多了好撈。
  static Future<List<TrashItem>> listTrashDetailed() async {
    final trashDir = Directory('${(await _storageFile()).parent.path}/trash');
    if (!await trashDir.exists()) return [];
    final out = <TrashItem>[];
    await for (final e in trashDir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final conv = Conversation.fromJson(
            jsonDecode(await e.readAsString()) as Map<String, dynamic>);
        final deletedAt = (await e.stat()).modified;
        out.add(TrashItem(conversation: conv, deletedAt: deletedAt));
      } catch (_) {}
    }
    out.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return out;
  }

  /// [小葵 2026-09-21 Blue 令] 永久刪除——清空對話、空對話等真不需要留的。
  /// 呼叫端必須先向使用者警示「刪除後無法恢復」，由使用者自己決定。
  static Future<bool> purge(String id) async {
    final trashDir = Directory('${(await _storageFile()).parent.path}/trash');
    final trashFile = File('${trashDir.path}/$id.json');
    if (!await trashFile.exists()) return false;
    await trashFile.delete();
    debugPrint('[ConversationStore] 對話 $id 已從回收桶永久刪除（不可恢復）');
    return true;
  }

  /// [小葵 2026-09-21] 從回收桶救回對話（後悔藥）
  static Future<bool> restore(String id) async {
    final trashDir = Directory('${(await _storageFile()).parent.path}/trash');
    final trashFile = File('${trashDir.path}/$id.json');
    if (!await trashFile.exists()) return false;
    final conv = Conversation.fromJson(
        jsonDecode(await trashFile.readAsString()) as Map<String, dynamic>);
    await save(conv);
    await trashFile.delete();
    debugPrint('[ConversationStore] 對話 $id 已從回收桶還原');
    return true;
  }

  static Future<String?> getCurrentId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCurrentId);
  }

  static Future<void> setCurrentId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrentId, id);
  }

  static Future<void> clearCurrentId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCurrentId);
  }

  static Future<Conversation?> getById(String id) async {
    final all = await getAll();
    try {
      return all.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  // [以利沙 P1 修復十四輪 2026-06-27] 依 companionId 查詢對話記錄
  static Future<List<Conversation>> getByCompanionId(String companionId) async {
    final all = await getAll();
    return all.where((c) => c.companionId == companionId).toList();
  }

  static Future<Conversation> createNew({
    String? title,
    String? companionId,
  }) async {
    final conv = Conversation.create(title: title, companionId: companionId);
    await save(conv);
    await setCurrentId(conv.id);
    return conv;
  }

  static Future<File> _storageFile() async {
    final directory = await _storageDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}/$_storageFileName');
  }

  static Future<Directory> _storageDirectory() async {
    if (_debugStorageDirectory != null) return _debugStorageDirectory!;

    try {
      final support = await getApplicationSupportDirectory();
      return Directory('${support.path}/$_storageFolderName');
    } catch (_) {
      return Directory(
        '${Directory.systemTemp.path}/bridge_app/$_storageFolderName',
      );
    }
  }

  static Future<List<Conversation>> _migrateLegacyPrefsIfNeeded(
    File destination,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyConversations);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    final conversations = _decodeConversations(jsonStr);
    if (conversations.isNotEmpty) {
      await destination.writeAsString(
        jsonEncode(conversations.map((c) => c.toJson()).toList()),
        flush: true,
      );
    }

    await prefs.remove(_keyConversations);
    return conversations;
  }

  /// [小葵 2026-09-21 P0] 守門員用的原始磁碟讀取——解讀成功回列表，
  /// 檔案不存在/讀取失敗/格式損壞一律回 null（絕不把「讀不到」當「空」）。
  static Future<List<Conversation>?> _readAllRaw(File file) async {
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString();
      if (text.isEmpty) return null;
      final list = jsonDecode(text) as List;
      return list.map((e) => Conversation.fromJson(e)).toList();
    } catch (_) {
      return null;
    }
  }

  /// [2026-10-16 盲測並發事故] 寫入互斥鎖——_rotateBackup 與 writeAsString
  /// 不是原子的：兩個 save() 交錯（備份A→備份B→寫A→寫B 或 0-byte 競態）
  /// 會產出 0-byte 備份甚至清空主檔。全 App 對話寫入序列化。
  static Future<void> _writeLock = Future.value();

  static Future<void> _writeAll(List<Conversation> conversations) async {
    final task = _writeLock.then((_) => _writeAllInner(conversations));
    _writeLock = task.catchError((_) {}); // 鎖不住也要解鎖
    return task;
  }

  static Future<void> _writeAllInner(List<Conversation> conversations) async {
    final file = await _storageFile();
    // [2026-10-16] 內容空保護——序列化結果空字串/空列表一律拒寫
    // （守門員依賴讀到舊檔；舊檔若已被競態清空，這裡是最後一道網）
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    // [小葵 2026-09-21 P0] 寫入守門員——防「空列表覆寫」資料事故。
    // 場景：啟動時 getAll() 因檔案系統暫態錯誤回空 → App 記憶體空列表 →
    // 第一個 save() 就把整份對話史清空。鐵則：只有明確 delete 過的 id
    // 才允許從寫入結果中消失；磁碟上多出來的一律帶著走。
    try {
      final onDisk = await _readAllRaw(file);
      if (onDisk != null && onDisk.isNotEmpty) {
        final incomingIds =
            conversations.map((c) => c.id).toSet();
        final missing = onDisk
            .where((c) =>
                !incomingIds.contains(c.id) &&
                !_explicitlyDeleted.contains(c.id))
            .toList();
        if (missing.isNotEmpty && conversations.length < onDisk.length) {
          debugPrint(
              '[ConversationStore] ⚠️ 守門員攔截：${missing.length} 個對話將被'
              '默默丟失（非刪除路徑），已自動保留: ${missing.map((m) => m.id).take(3)}...');
          conversations = [...conversations, ...missing];
          conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        }
      }
    } catch (e) {
      debugPrint('[ConversationStore] 守門員檢查失敗（不阻擋寫入）: $e');
    }

    // [教練 Agent 2026-08-02] 寫入前先備份（保留最近 10 版）
    await _rotateBackup(file);

    final payload =
        jsonEncode(conversations.map((c) => c.toJson()).toList());
    if (payload.length < 3) {
      // '[]' ——寫入等於清空。但若本 session 有明確刪除記錄
      // （_explicitlyDeleted），空列表是使用者意圖（刪到剩 0），放行；
      // 否則視為異常清空，拒寫保留現場。
      final intentionalEmpty = _explicitlyDeleted.isNotEmpty;
      if (!intentionalEmpty) {
        debugPrint('[ConversationStore] 🚫 空列表寫入被拒（防清空）');
        return;
      }
      debugPrint('[ConversationStore] 空列表寫入放行——'
          '本 session 有明確刪除記錄（${_explicitlyDeleted.length} 筆）');
    }
    await file.writeAsString(payload, flush: true);

    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_keyConversations)) {
      await prefs.remove(_keyConversations);
    }
  }

  /// [教練 Agent 2026-08-02] 每次寫入前滾動備份 conversations.json（保留 10 個版本）
  static Future<void> _rotateBackup(File currentFile) async {
    final dir = currentFile.parent;
    const maxBackups = 10;

    // 找現有的備份，刪掉超出上限的舊檔
    try {
      final existing = await dir
          .list()
          .where((e) => e.path.contains('.${_storageFileName}.v'))
          .map((e) => e.path)
          .toList();

      existing.sort();
      if (existing.length >= maxBackups) {
        // 刪掉最舊的 1 個
        await File(existing.first).delete();
      }

      // 如果目前檔案存在，複製一份帶版本號
      if (await currentFile.exists()) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final backupPath = '${dir.path}/.${_storageFileName}.v$timestamp';
        await currentFile.copy(backupPath);
      }
    } catch (e) {
      // 備份失敗不阻擋主流程
      debugPrint('[ConversationStore] 備份失敗: $e');
    }
  }
}
