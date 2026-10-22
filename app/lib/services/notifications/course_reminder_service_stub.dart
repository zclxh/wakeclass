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

class CourseReminderService {
  CourseReminderService._();

  static Future<void> init() async {}

  static Future<ReminderSettings> loadSettings() async =>
      const ReminderSettings(enabled: false, leadMinutes: ReminderSettings.defaultLead);

  static Future<void> saveSettings(ReminderSettings settings) async {}

  static Future<bool> requestPermission() async => false;

  static Future<void> sync(Schedule schedule, {required ReminderSettings settings}) async {}
}
