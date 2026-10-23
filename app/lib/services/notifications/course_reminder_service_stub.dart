import 'package:wakeclass_core/wakeclass_core.dart';

/// Web 平台占位实现：本地通知不可用，所有操作降级为空操作。
///
/// 通过 `reminders.dart` 条件导出在 Web 构建时替换真实实现，
/// 避免编译 flutter_local_notifications（无 Web 支持）。
class ReminderSettings {
  const ReminderSettings({required this.enabled, required this.leadMinutes});

  final bool enabled;
  final int leadMinutes;

  static const int defaultLead = 10;

  ReminderSettings copyWith({bool? enabled, int? leadMinutes}) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        leadMinutes: leadMinutes ?? this.leadMinutes,
      );
}

/// 与真实实现保持同名同结构（Web 端永远排程 0 条）。
class ReminderSyncResult {
  const ReminderSyncResult({
    required this.scheduled,
    required this.exact,
    this.enabled = true,
  });

  final int scheduled;
  final bool exact;
  final bool enabled;

  static const ReminderSyncResult off =
      ReminderSyncResult(scheduled: 0, exact: false, enabled: false);
}

class CourseReminderService {
  CourseReminderService._();

  static Future<void> init() async {}

  static Future<ReminderSettings> loadSettings() async => const ReminderSettings(
      enabled: false, leadMinutes: ReminderSettings.defaultLead);

  static Future<void> saveSettings(ReminderSettings settings) async {}

  static Future<bool> requestPermission() async => false;

  static Future<bool> canScheduleExact() async => false;

  static Future<bool> requestExactAlarmsPermission() async => false;

  static Future<int> pendingCount() async => 0;

  static Future<void> showTestNotification() async {}

  static Future<bool> scheduleTestInTenSeconds() async => false;

  static Future<ReminderSyncResult> sync(
    Schedule schedule, {
    required ReminderSettings settings,
    PeriodSettings? periods,
  }) async =>
      ReminderSyncResult.off;
}
