import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import '../theme.dart';

/// 周课表网格：左侧节次轴 + 7 列星期（七天一屏，无横向滚动）。
///
/// 视觉：
/// - 课程块 = 淡色底 + 左侧同色竖条 + 深色文字（小屏窄列也看得清）；
/// - 字号随列宽自适应，避免课程名被硬断成两行；
/// - 今天：表头胶囊高亮 + 整列极淡底色；
/// - 网格只用 0.06 透明度的细线，不抢课程块。
class ScheduleGrid extends StatelessWidget {
  const ScheduleGrid({
    super.key,
    required this.schedule,
    required this.week,
    this.weekStart,
    this.onCourseTap,
    this.showWeekend = true,
    this.periods,
    this.cardStyle = CourseCardStyle.soft,
  });

  final Schedule schedule;
  final int week;

  /// 当前展示周的周一日期（用于表头日期与今天高亮，可空）。
  final DateTime? weekStart;
  final ValueChanged<Course>? onCourseTap;
  final bool showWeekend;

  /// 作息设置（自定义上课时间）；为空时用默认作息。
  final PeriodSettings? periods;

  /// 课程卡片外观（柔和 / 鲜艳）。
  final CourseCardStyle cardStyle;

  static final PeriodSettings _defaultPeriods = PeriodSettings.defaults();

  static const double _axisWidth = 36;
  static const double _headerHeight = 44;

  PeriodSettings get _settings => periods ?? _defaultPeriods;

  DateTime? _dateOf(int day) {
    final base = weekStart;
    if (base == null) return null;
    return base.add(Duration(days: day - 1));
  }

  static bool _isToday(DateTime? date) {
    if (date == null) return false;
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    // 学期里没有周末课就只显示周一到周五：列宽从 50dp 涨到 70dp，
    // 课程名不用再被挤成两三个字一行。
    final hasWeekend = schedule.courses.any((c) => c.dayOfWeek >= 6);
    final days = (showWeekend && hasWeekend)
        ? const [1, 2, 3, 4, 5, 6, 7]
        : const [1, 2, 3, 4, 5];
    final settings = _settings;
    var maxPeriod = 8;
    for (final c in schedule.courses) {
      maxPeriod = math.max(maxPeriod, c.endPeriod);
    }
    // 不强行撑满作息表：没晚课就不画晚上那几行（有晚课时自动出现）。
    maxPeriod = math.min(maxPeriod, math.max(settings.count, 8));
    // 冲突在全部课程中计算；当周只显示本周课程。
    final conflictIds = _conflictIds(schedule);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dayWidth = (constraints.maxWidth - _axisWidth) / days.length;
        // 行高自适应：撑满可用高度，课程块更高、分界线直达底部。
        var rowHeight = (constraints.maxHeight - _headerHeight) / maxPeriod;
        var scrollable = false;
        if (!rowHeight.isFinite || rowHeight < 30) {
          rowHeight = 30;
          scrollable = true;
        }
        final contentHeight = _headerHeight + maxPeriod * rowHeight;
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PeriodAxis(
              maxPeriod: maxPeriod,
              headerHeight: _headerHeight,
              rowHeight: rowHeight,
              periods: settings,
            ),
            for (final day in days)
              _DayColumn(
                day: day,
                courses: schedule.coursesOn(day, week),
                date: _dateOf(day),
                isToday: _isToday(_dateOf(day)),
                isLast: day == days.last,
                conflicts: conflictIds,
                width: dayWidth,
                headerHeight: _headerHeight,
                rowHeight: rowHeight,
                height: contentHeight,
                cardStyle: cardStyle,
                onCourseTap: onCourseTap,
              ),
          ],
        );
        return scrollable ? SingleChildScrollView(child: row) : row;
      },
    );
  }

  /// 存在冲突的课程 id 集合（用于红框提示）。
  static Set<String> _conflictIds(Schedule schedule) {
    final ids = <String>{};
    for (final pair in findConflicts(schedule.courses)) {
      ids.add(pair.a.id);
      ids.add(pair.b.id);
    }
    return ids;
  }
}

/// 左侧节次轴：大一点的节次数字 + 很淡的开始时间。
class _PeriodAxis extends StatelessWidget {
  const _PeriodAxis({
    required this.maxPeriod,
    required this.headerHeight,
    required this.rowHeight,
    required this.periods,
  });

  final int maxPeriod;
  final double headerHeight;
  final double rowHeight;
  final PeriodSettings periods;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      children: [
        SizedBox(height: headerHeight),
        for (var p = 1; p <= maxPeriod; p++)
          SizedBox(
            height: rowHeight,
            width: ScheduleGrid._axisWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$p',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      color: onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    periods.startOf(p),
                    style: TextStyle(
                      fontSize: 8,
                      height: 1.1,
                      letterSpacing: -0.2,
                      color: muted.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.courses,
    required this.date,
    required this.isToday,
    required this.isLast,
    required this.conflicts,
    required this.width,
    required this.headerHeight,
    required this.rowHeight,
    required this.height,
    required this.cardStyle,
    required this.onCourseTap,
  });

  final int day;
  final List<Course> courses;
  final DateTime? date;
  final bool isToday;
  final bool isLast;
  final Set<String> conflicts;
  final double width;
  final double headerHeight;
  final double rowHeight;
  final double height;
  final CourseCardStyle cardStyle;
  final ValueChanged<Course>? onCourseTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final dateText = date == null ? '' : '${date!.month}/${date!.day}';
    final line = theme.colorScheme.onSurface.withValues(alpha: 0.07);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isToday ? primary.withValues(alpha: 0.045) : null,
        border: Border(
          left: BorderSide(color: line, width: 0.6),
          right:
              isLast ? BorderSide(color: line, width: 0.6) : BorderSide.none,
        ),
      ),
      child: Column(
        children: [
          // 表头：星期 + 日期（今天：淡色胶囊 + 主题色文字）
          SizedBox(
            height: headerHeight,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: isToday
                    ? BoxDecoration(
                        color: primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      )
                    : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      courseDayName(day),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.15,
                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                        color: isToday
                            ? primary
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.78),
                      ),
                    ),
                    if (dateText.isNotEmpty)
                      Text(
                        dateText,
                        style: TextStyle(
                          fontSize: 8.5,
                          height: 1.2,
                          fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                          color: isToday
                              ? primary.withValues(alpha: 0.8)
                              : theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final course in courses)
                  if (course.startPeriod > 0)
                    Positioned(
                      top: (course.startPeriod - 1) * rowHeight + 1.5,
                      left: 1.5,
                      right: 1.5,
                      height: ((course.endPeriod - course.startPeriod + 1) *
                                  rowHeight)
                              .clamp(rowHeight, double.infinity) -
                          3,
                      child: CourseTile(
                        course: course,
                        hasConflict: conflicts.contains(course.id),
                        style: cardStyle,
                        onTap: () => onCourseTap?.call(course),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个课程卡片（只渲染当前展示周的课程，由上游过滤）。
///
/// 淡色底 + 左侧同色竖条 + 深色文字：20 种课程色都能区分，
/// 但小字号文字始终有足够对比度。
class CourseTile extends StatelessWidget {
  const CourseTile({
    super.key,
    required this.course,
    this.hasConflict = false,
    this.style = CourseCardStyle.soft,
    this.onTap,
  });

  final Course course;
  final bool hasConflict;

  /// 卡片外观：柔和（淡底 + 色条）/ 鲜艳（整块课程色）。
  final CourseCardStyle style;
  final VoidCallback? onTap;

  /// 把课程色压深，用作文字色（保留色相，保证可读）。
  static Color _deepen(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - 0.42).clamp(0.16, 0.62))
        .withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0))
        .toColor();
  }

  /// 单行放得下就用 [max] 号字，放不下等比缩小；缩到 [min] 还不够就换行。
  static ({double size, bool oneLine}) _fitText(
    String text,
    double maxWidth, {
    required double max,
    required double min,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: max,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final natural = painter.width;
    painter.dispose();
    if (natural <= maxWidth || natural <= 0) {
      return (size: max, oneLine: true);
    }
    final scaled = max * maxWidth / natural;
    if (scaled >= min) return (size: scaled, oneLine: true);
    return (size: min, oneLine: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final vivid = style == CourseCardStyle.vivid;
    final base = courseColor(course.colorIndex);

    final Color bgColor;
    final Color fg;
    if (vivid) {
      bgColor = isDark ? Color.lerp(base, Colors.black, 0.28)! : base;
      fg = bgColor.computeLuminance() > 0.55
          ? Colors.black.withValues(alpha: 0.87)
          : Colors.white;
    } else {
      bgColor = isDark
          ? base.withValues(alpha: 0.26)
          : Color.lerp(base, theme.colorScheme.surface, 0.86)!;
      fg = isDark ? Color.lerp(base, Colors.white, 0.85)! : _deepen(base);
    }
    final sub = fg.withValues(alpha: vivid ? 0.86 : 0.72);
    final BoxBorder? border = hasConflict
        ? Border.all(color: Colors.redAccent, width: 1.6)
        : (vivid ? null : Border(top: BorderSide(color: base, width: 3)));

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final textWidth = math.max(16.0, w - 9);
        final fitted =
            _fitText(course.name, textWidth, max: 13.0, min: 10.0);
        final nameSize = fitted.size;
        final showLocation = h > 34 && course.location.isNotEmpty;
        final showTeacher = h > 52 && course.teacher.isNotEmpty;
        final subSize = math.max(nameSize * 0.78, 9.0);
        final noteSize = math.max(nameSize * 0.72, 8.5);

        final radius = BorderRadius.circular(9);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(5, 6, 4, 4),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: radius,
                border: border,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    course.name,
                    maxLines: fitted.oneLine ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: nameSize,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (showLocation)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        course.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: sub,
                          fontSize: subSize,
                          height: 1.3,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  if (showTeacher)
                    Text(
                      course.teacher,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: sub.withValues(alpha: 0.8),
                        fontSize: noteSize,
                        height: 1.3,
                        letterSpacing: -0.2,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
