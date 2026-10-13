// 內建 Skills 收編——把 App 既有 skills 納入插槽管理大家庭
//
// [Blue 提議 2026-10-06] 初始安裝完 App，使用者就該看到「裡面裝了哪些
// 東西」——不要可以單獨卸載。既有 7 個內建 skill（grill-me、to-spec、
// diagnose-bugs…）不是 GitHub repo，走 skill:// 虛擬來源。
//
// 語義：
// - 只在「插槽系統裡連一個 builtin 都沒有」時收編（新安裝/升級首啟）
// - 使用者卸載 builtin skill 後（全部消失）→ 不還魂（尊重使用者選擇）
// - 收編的插槽：skill:// 來源、🟢 零權限（本地 markdown，不碰網路）
//   、category='核心技能'、certified=true（官方內建）
//
// 資料真相源仍是 ~/Documents/skills/ 的 .md 檔（SkillStore 掃描載入）；
// 插槽記錄是「管理視圖」——解除兩套系統的耦合。

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'slot_registry.dart';
import '../skills/skill_store.dart';
import 'builtin_skills_intake.dart' show BuiltinSkillsIntake;

class BuiltinSkillsIntake {
  BuiltinSkillsIntake._();
  static final instance = BuiltinSkillsIntake._();

  static const String builtinCategory = '核心技能';
  static const String skillScheme = 'skill://';

  bool _done = false;

  /// 墓碑：使用者明確卸載過 builtin 後不再還魂。存 slots/index.json 旁
  /// （builtin_intake_tombstone.json）——「不要」也是一個要被尊重並記住的決定。
  File get _tombstoneFile => File(
      '${SlotRegistry.instance.slotsDir.path}/builtin_intake_tombstone.json');

  /// 首啟收編（冪等）。SkillStore 已載入後呼叫。
  Future<void> runIfNeeded() async {
    if (_done) return;
    _done = true;
    try {
      final registry = SlotRegistry.instance;
      await registry.ensureLoaded();

      // 墓碑在＝使用者曾明確清光 builtin——永不還魂。
      if (await _tombstoneFile.exists()) {
        debugPrint('[BuiltinSkillsIntake] 墓碑在——使用者已卸載 builtin，不還魂');
        return;
      }

      // 已有任何 builtin skill 插槽 → 收編過（或使用者已整理過），不動。
      final hasBuiltin = registry.all
          .any((s) => s.sourceRepo.startsWith(skillScheme));
      if (hasBuiltin) return;

      final skills = SkillStore.instance.all;
      if (skills.isEmpty) return; // SkillStore 還沒初始化——下次再說

      debugPrint('[BuiltinSkillsIntake] 收編 ${skills.length} 個內建 skills → 插槽');
      for (final skill in skills) {
        final record = await registry.addFromRepo(
          '$skillScheme${skill.name}',
          label: skill.name,
          category: builtinCategory,
        );
        // 內建 skill＝本地 markdown、零權限、官方認證——直接 running。
        // 注意：update 必須基於「最新版」record（enable 後的），否則會把
        // running 蓋回 pending（閉環 bug：copyWith 舊物件整筆覆寫）。
        await registry.enableWithPermissions(record.id, const []);
        final latest = registry.getById(record.id);
        if (latest != null) {
          await registry.update(
              latest.copyWith(certified: true, category: builtinCategory));
        }
      }
    } catch (e) {
      // 收編失敗不擋啟動——下次啟動再試
      debugPrint('[BuiltinSkillsIntake] 收編失敗（下次啟動再試）: $e');
      _done = false;
    }
  }

  /// 使用者卸載「最後一個」builtin skill 插槽後立墓碑。
  /// （由 uninstall 流程呼叫；只關心 builtin 來源。）
  Future<void> onSlotUninstalled(String sourceRepo) async {
    if (!sourceRepo.startsWith(skillScheme)) return;
    final registry = SlotRegistry.instance;
    await registry.ensureLoaded();
    final stillHasBuiltin =
        registry.all.any((s) => s.sourceRepo.startsWith(skillScheme));
    if (!stillHasBuiltin) {
      try {
        await SlotRegistry.instance.slotsDir.create(recursive: true);
        await _tombstoneFile.writeAsString('{"tombstone": true}');
        debugPrint('[BuiltinSkillsIntake] builtin 全數卸載——立墓碑，不再還魂');
      } catch (_) {}
    }
  }
}

/// _done 測試用重置。
@visibleForTesting
void resetBuiltinSkillsIntakeForTest() {
  BuiltinSkillsIntake.instance._done = false;
}
