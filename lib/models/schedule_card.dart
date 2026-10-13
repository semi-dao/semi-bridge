// H4 2026-10-08 — 排程任務卡 model
// Hermes 43 cron jobs（28 啟用）重現為專案頁任務卡（Phase H spec §4）
// 「生活類排程要有溫度有反饋——不是冷冰冰數據與完成燈號」
import '../services/schedule_registry.dart';

class ScheduleCard {
  final String id;
  final String name;

  /// cron 表達式或 interval/once 描述
  final String rawSchedule;

  /// 人類可讀時間（中文）——「每天 07:30」「每週六 08:30」「一次性 2026-10-08 18:00」
  final String humanSchedule;

  /// 溫度維度：工作卡看進度，生活卡看心意（Blue 開放設計題的初步答案）
  final ScheduleWarmth warmth;

  /// 生活卡的心意一行（工作卡為 null——用功能描述）
  final String? warmLine;

  /// 下次觸發（估算；once=排定時間）
  final DateTime? nextRun;

  const ScheduleCard({
    required this.id,
    required this.name,
    required this.rawSchedule,
    required this.humanSchedule,
    required this.warmth,
    this.warmLine,
    this.nextRun,
  });
}

/// 溫度維度——生活與工作在同一面板共存的方式
enum ScheduleWarmth {
  /// 生活／儀式：安靜時刻、生日約定、六個月之約、體力帳關懷…
  life,

  /// 維運／工作：看門狗、清理、稽核、更新偵測…
  work;

  static ScheduleWarmth fromName(String? s) =>
      s == 'life' ? ScheduleWarmth.life : ScheduleWarmth.work;
}
