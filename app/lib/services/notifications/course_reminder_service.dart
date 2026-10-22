import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakeclass_core/wakeclass_core.dart';

/// 课前提醒设置。
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

/// 课前提醒服务：基于本地通知，在上课前 N 分钟提醒课程与教室。
///
/// 所有平台调用均包裹异常处理：测试环境 / 桌面 / 无权限时静默降级。
class CourseReminderService {
  CourseReminderService._();

  static const _keyEnabled = 'wakeclass_reminder_enabled';
  static const _keyLead = 'wakeclass_reminder_lead_minutes';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {
      // 时区数据不可用时忽略
    }
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings);
      _inited = true;
    } catch (_) {
      // 平台不支持（测试 / 桌面）
    }
  }

  static Future<ReminderSettings> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ReminderSettings(
        enabled: prefs.getBool(_keyEnabled) ?? false,
        leadMinutes:
            prefs.getInt(_keyLead) ?? ReminderSettings.defaultLead,
      );
    } catch (_) {
      return const ReminderSettings(
          enabled: false, leadMinutes: ReminderSettings.defaultLead);
    }
  }

  static Future<void> saveSettings(ReminderSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEnabled, settings.enabled);
      await prefs.setInt(_keyLead, settings.leadMinutes);
    } catch (_) {
      // 保存失败忽略
    }
  }

  /// 请求通知权限（Android 13+）。
  static Future<bool> requestPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 重新计算并注册未来 8 天内的课前提醒。
  ///
  /// [schedule] 课表；[settings] 提醒设置（关闭时只取消已有通知）。
  static Future<void> sync(
    Schedule schedule, {
    required ReminderSettings settings,
  }) async {
    await init();
    try {
      await _plugin.cancelAll();
      if (!settings.enabled) return;
      final now = DateTime.now();
      final currentWeek = schedule.currentWeek();
      final horizon = now.add(const Duration(days: 8));
      var id = 1000;
      for (var week = currentWeek;
          week <= currentWeek + 1 && week <= schedule.totalWeeks;
          week++) {
        final monday = schedule.termStart.add(Duration(days: (week - 1) * 7));
        for (final course in schedule.courses) {
          if (!course.includesWeek(week)) continue;
          final date = monday.add(Duration(days: course.dayOfWeek - 1));
          final timeText = periodTimeText(course.startPeriod);
          if (timeText.isEmpty) continue;
          final hm = timeText.split('-').first.split(':');
          final start = DateTime(date.year, date.month, date.day,
              int.parse(hm[0]), int.parse(hm[1]));
          final remindAt = start.subtract(Duration(minutes: settings.leadMinutes));
          if (remindAt.isBefore(now) || remindAt.isAfter(horizon)) continue;
          final body = [
            if (course.location.isNotEmpty) '地点：${course.location}',
            '${periodLabel(course.startPeriod, course.endPeriod)} $timeText',
          ].join(' · ');
          await _plugin.zonedSchedule(
            id++,
            '即将上课：${course.name}',
            body,
            tz.TZDateTime.from(remindAt, tz.local),
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'course_reminder',
                '课程提醒',
                channelDescription: '课前提醒课程名称与教室',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
    } catch (_) {
      // 通知不可用（测试环境 / 无权限）时静默失败
    }
  }
}
