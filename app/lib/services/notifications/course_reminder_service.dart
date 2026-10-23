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

/// 一次提醒排程的结果（设置页用来显示状态）。
class ReminderSyncResult {
  const ReminderSyncResult({
    required this.scheduled,
    required this.exact,
    this.enabled = true,
  });

  /// 成功排程的提醒条数。
  final int scheduled;

  /// 是否使用了「精确闹钟」（关掉后系统可能延迟几分钟到几小时）。
  final bool exact;

  /// 用户是否开启了提醒。
  final bool enabled;

  static const ReminderSyncResult off =
      ReminderSyncResult(scheduled: 0, exact: false, enabled: false);
}

/// 课前提醒服务：基于本地通知，在上课前 N 分钟提醒课程与教室。
///
/// 关键点（v0.3.0 修复「提醒时间不准 / 收不到」）：
/// - 上课时间来自用户的作息设置 [PeriodSettings]，不再是硬编码的默认作息；
/// - 使用 `exactAllowWhileIdle` 精确闹钟，并申请 `SCHEDULE_EXACT_ALARM` 权限；
/// - 排程覆盖未来 60 天（上限 300 条），打开 App / 回到前台时自动补排；
/// - 所有平台调用均包裹异常处理：测试环境 / 桌面 / 无权限时静默降级。
class CourseReminderService {
  CourseReminderService._();

  static const _keyEnabled = 'wakeclass_reminder_enabled';
  static const _keyLead = 'wakeclass_reminder_lead_minutes';

  /// 单次最多排程多少条提醒（避免触发系统闹钟数量上限）。
  static const maxScheduled = 300;

  /// 最多向后排程多少天。
  static const horizonDays = 60;

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
        leadMinutes: prefs.getInt(_keyLead) ?? ReminderSettings.defaultLead,
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

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// 请求通知权限（Android 13+）。
  static Future<bool> requestPermission() async {
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 是否被允许使用精确闹钟（Android 12+ 需要用户授权）。
  static Future<bool> canScheduleExact() async {
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 申请精确闹钟权限（跳系统设置页）。返回申请后是否已获得授权。
  static Future<bool> requestExactAlarmsPermission() async {
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (_) {
      // 部分 ROM 不支持，忽略
    }
    return canScheduleExact();
  }

  /// 已排程但还没弹出的通知条数。
  static Future<int> pendingCount() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending.length;
    } catch (_) {
      return 0;
    }
  }

  /// 立刻弹一条测试通知（验证权限、通知渠道是否正常）。
  static Future<void> showTestNotification() async {
    await init();
    try {
      await _plugin.show(
        990001,
        '醒课 · 通知测试',
        '看到这条通知说明通知权限正常，课前提醒可以正常工作。',
        _details(),
      );
    } catch (_) {
      // 忽略
    }
  }

  /// 10 秒后的定时测试通知（验证「精确闹钟」是否真的准时）。
  static Future<bool> scheduleTestInTenSeconds() async {
    await init();
    try {
      final exact = await canScheduleExact();
      await _plugin.zonedSchedule(
        990002,
        '醒课 · 定时测试',
        '如果你在 10 秒后收到这条通知，说明定时提醒工作正常。',
        tz.TZDateTime.now(tz.local).add(const Duration(seconds: 10)),
        _details(),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return exact;
    } catch (_) {
      return false;
    }
  }

  /// 重新计算并注册未来 [horizonDays] 天内的课前提醒。
  ///
  /// [schedule] 课表；[periods] 作息设置；[settings] 提醒设置（关闭时只取消已有通知）。
  static Future<ReminderSyncResult> sync(
    Schedule schedule, {
    required ReminderSettings settings,
    PeriodSettings? periods,
  }) async {
    await init();
    final periodSettings = periods ?? PeriodSettings.defaults();
    try {
      await _plugin.cancelAll();
      if (!settings.enabled) return ReminderSyncResult.off;
      final exact = await canScheduleExact();
      final mode = exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      final now = DateTime.now();
      final horizon = now.add(const Duration(days: horizonDays));
      final currentWeek = schedule.currentWeek();
      var id = 1000;
      var scheduled = 0;
      for (var week = currentWeek;
          week <= schedule.totalWeeks && scheduled < maxScheduled;
          week++) {
        final monday = schedule.termStart.add(Duration(days: (week - 1) * 7));
        for (final course in schedule.courses) {
          if (scheduled >= maxScheduled) break;
          if (!course.includesWeek(week)) continue;
          if (course.dayOfWeek < 1 || course.dayOfWeek > 7) continue;
          final startMinute = periodSettings.startMinute(course.startPeriod);
          if (startMinute == null) continue;
          final date = monday.add(Duration(days: course.dayOfWeek - 1));
          final start = DateTime(date.year, date.month, date.day)
              .add(Duration(minutes: startMinute));
          final remindAt =
              start.subtract(Duration(minutes: settings.leadMinutes));
          if (!remindAt.isAfter(now) || remindAt.isAfter(horizon)) continue;
          final timeText = periodSettings.timeText(course.startPeriod);
          final body = [
            if (course.location.isNotEmpty) '地点：${course.location}',
            '${periodLabel(course.startPeriod, course.endPeriod)}'
                '${timeText.isEmpty ? '' : ' $timeText'}',
            if (course.teacher.isNotEmpty) course.teacher,
          ].join(' · ');
          await _plugin.zonedSchedule(
            id++,
            '即将上课：${course.name}',
            body,
            tz.TZDateTime.from(remindAt, tz.local),
            _details(),
            androidScheduleMode: mode,
          );
          scheduled++;
        }
      }
      return ReminderSyncResult(scheduled: scheduled, exact: exact);
    } catch (_) {
      // 通知不可用（测试环境 / 无权限）时静默失败
      return const ReminderSyncResult(scheduled: 0, exact: false);
    }
  }

  static NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          'course_reminder',
          '课程提醒',
          channelDescription: '课前提醒课程名称与教室',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          enableVibration: true,
          playSound: true,
        ),
      );
}
