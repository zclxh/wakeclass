import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

/// 桌面小组件配色。
///
/// **顺序必须与 Android 端 `CourseWidgetProvider.PALETTES` / `widget_bg_*.xml`
/// 保持一致**，原生端按下标取色。
class WidgetColorPreset {
  const WidgetColorPreset(
    this.name,
    this.background,
    this.accent,
    this.text,
    this.muted,
  );

  /// 配色名，如「奶油」。
  final String name;

  /// 卡片背景色。
  final Color background;

  /// 强调色（日期、倒计时）。
  final Color accent;

  /// 正文色（课程名、自定义文字）。
  final Color text;

  /// 次要文字色（地点、时间）。
  final Color muted;
}

/// 8 套预设配色。
const widgetColorPresets = <WidgetColorPreset>[
  WidgetColorPreset('奶油', Color(0xFFFFF8F0), Color(0xFFB0652A),
      Color(0xFF3E2C1C), Color(0xFF8A7460)),
  WidgetColorPreset('薄荷', Color(0xFFE9F7F2), Color(0xFF00796B),
      Color(0xFF16352F), Color(0xFF5E7F78)),
  WidgetColorPreset('天蓝', Color(0xFFEAF2FE), Color(0xFF1565C0),
      Color(0xFF16283C), Color(0xFF5C7AA3)),
  WidgetColorPreset('米黄', Color(0xFFFFF6DF), Color(0xFFE07B00),
      Color(0xFF3E2E0F), Color(0xFF8A7448)),
  WidgetColorPreset('粉樱', Color(0xFFFDEDF3), Color(0xFFC2185B),
      Color(0xFF3C1524), Color(0xFF8C5F71)),
  WidgetColorPreset('淡紫', Color(0xFFF2ECFB), Color(0xFF6A1B9A),
      Color(0xFF2A1538), Color(0xFF7A6A8C)),
  WidgetColorPreset('森林', Color(0xFFEAF5EA), Color(0xFF2E7D32),
      Color(0xFF17301A), Color(0xFF5C7A5F)),
  WidgetColorPreset('石墨', Color(0xFFEDEFF1), Color(0xFF37474F),
      Color(0xFF1E2529), Color(0xFF66757D)),
];

/// 小组件尺寸（与 Android 端三个 AppWidgetProvider 对应）。
class WidgetSizePreset {
  const WidgetSizePreset({
    required this.id,
    required this.name,
    required this.cells,
    required this.maxCourses,
  });

  /// 传给原生的尺寸标识：`small` / `medium` / `large`。
  final String id;

  /// 中文尺寸名：小 / 中 / 大。
  final String name;

  /// 占格数，如 `4×2`。
  final String cells;

  /// 该尺寸最多显示几门剩余课程。
  final int maxCourses;

  String get label => '$name $cells';

  String get description => '$cells · 最多 $maxCourses 门课';
}

/// 三档尺寸。
const widgetSizePresets = <WidgetSizePreset>[
  WidgetSizePreset(id: 'small', name: '小', cells: '4×2', maxCourses: 3),
  WidgetSizePreset(id: 'medium', name: '中', cells: '4×4', maxCourses: 5),
  WidgetSizePreset(id: 'large', name: '大', cells: '4×5', maxCourses: 7),
];

/// 桌面小组件的可自定义配置：左上角文字、配色、尺寸。
class WidgetSettings {
  WidgetSettings({String title = '', this.colorIndex = 0, this.sizeId = 'small'})
      : title = normalizeWidgetTitle(title);

  static const titleKey = 'wakeclass_widget_title';
  static const colorKey = 'wakeclass_widget_color';
  static const sizeKey = 'wakeclass_widget_size';

  /// 自定义文字最多 6 个字。
  static const maxTitleLength = 6;

  /// 没有课表标题时的兜底文字。
  static const defaultTitle = '醒课';

  String title;
  int colorIndex;
  String sizeId;

  WidgetColorPreset get color =>
      widgetColorPresets[colorIndex.clamp(0, widgetColorPresets.length - 1)];

  WidgetSizePreset get size => widgetSizePresets.firstWhere(
        (s) => s.id == sizeId,
        orElse: () => widgetSizePresets.first,
      );

  /// 读取本地配置；没有保存过时用 [fallbackTitle]（一般是课表标题）。
  static Future<WidgetSettings> load({String fallbackTitle = defaultTitle}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(titleKey);
      final color = int.tryParse(prefs.getString(colorKey) ?? '') ?? 0;
      final size = prefs.getString(sizeKey) ?? 'small';
      return WidgetSettings(
        title: (saved == null || saved.trim().isEmpty) ? fallbackTitle : saved,
        colorIndex: color.clamp(0, widgetColorPresets.length - 1),
        sizeId: widgetSizePresets.any((s) => s.id == size) ? size : 'small',
      );
    } catch (_) {
      return WidgetSettings(title: fallbackTitle);
    }
  }

  /// 写入 shared_preferences（原生端读取 `flutter.` 前缀的同一个键）。
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(titleKey, title);
      await prefs.setString(colorKey, '$colorIndex');
      await prefs.setString(sizeKey, sizeId);
    } catch (_) {
      // 保存失败不影响本次会话
    }
  }
}

/// 自定义文字规整：去空格，最多 6 个字（按码点计数，emoji 不会被截断）。
String normalizeWidgetTitle(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final runes = trimmed.runes.toList();
  if (runes.length <= WidgetSettings.maxTitleLength) return trimmed;
  return String.fromCharCodes(runes.take(WidgetSettings.maxTitleLength));
}

/// 小组件里的一节课（App 内预览用，展示规则与 Android 端一致）。
class WidgetCourseLine {
  const WidgetCourseLine({
    required this.name,
    required this.detail,
    required this.status,
  });

  final String name;
  final String detail;
  final String status;
}

/// 今天还没上完的课程，最多 [max] 门。
///
/// 与原生端一致：已下课的课程直接从列表移除；未上课显示距上课时间，
/// 上课期间显示距下课时间。
List<WidgetCourseLine> widgetTodayCourses(
  Schedule schedule,
  DateTime now, {
  int max = 3,
}) {
  final week = schedule.currentWeek(now);
  if (week < 1 || week > schedule.totalWeeks) return const [];
  final lines = <WidgetCourseLine>[];
  for (final course in schedule.coursesOn(now.weekday, week)) {
    final periodStart = _periodTime(course.startPeriod);
    final periodEnd = _periodTime(course.endPeriod);
    if (periodStart == null || periodEnd == null) continue;
    final startMinute = _minutesOfDay(periodStart.start);
    final endMinute = _minutesOfDay(periodEnd.end);
    if (startMinute == null || endMinute == null) continue;
    final day = DateTime(now.year, now.month, now.day);
    final start = day.add(Duration(minutes: startMinute));
    final end = day.add(Duration(minutes: endMinute));
    if (!end.isAfter(now)) continue;
    final timeText = '${periodStart.start}-${periodEnd.end}';
    lines.add(
      WidgetCourseLine(
        name: course.name,
        detail:
            course.location.isEmpty ? timeText : '$timeText · ${course.location}',
        status: widgetStatusText(start, end, now),
      ),
    );
    if (lines.length >= max) break;
  }
  return lines;
}

/// 课前 / 课中倒计时文案（与原生端 `statusText` 一致）。
String widgetStatusText(DateTime start, DateTime end, DateTime now) {
  if (now.isBefore(start)) {
    return _countdownText(start.difference(now), '上课');
  }
  return _countdownText(end.difference(now), '下课');
}

String _countdownText(Duration left, String verb) {
  final minutes = (left.inSeconds / 60).ceil();
  if (minutes <= 1) return verb == '上课' ? '马上上课' : '即将下课';
  if (minutes < 60) return '还有 $minutes 分钟$verb';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (rest == 0) return '还有 $hours 小时$verb';
  return '还有 $hours 小时 $rest 分$verb';
}

PeriodTime? _periodTime(int period) {
  if (period < 1 || period > defaultPeriodTimes.length) return null;
  return defaultPeriodTimes[period - 1];
}

int? _minutesOfDay(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return hour * 60 + minute;
}

/// 中文星期：1 → 周一。
String widgetWeekdayName(int weekday) {
  const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  if (weekday < 1 || weekday > 7) return '';
  return names[weekday - 1];
}
