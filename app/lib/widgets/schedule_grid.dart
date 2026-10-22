import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import '../theme.dart';

/// 周课表网格：左侧节次轴 + 7 列星期（七天一屏，无横向滚动）。
///
/// - 行高自适应屏幕高度：课程块更高、列分界线直达屏幕底部；
/// - 表头显示「星期 + 日期」，今天加深显示；
/// - 只渲染当前展示周的课程。
class ScheduleGrid extends StatelessWidget {
  const ScheduleGrid({
    super.key,
    required this.schedule,
    required this.week,
    this.weekStart,
    this.onCourseTap,
    this.showWeekend = true,
  });

  final Schedule schedule;
  final int week;

  /// 当前展示周的周一日期（用于表头日期与今天高亮，可空）。
  final DateTime? weekStart;
  final ValueChanged<Course>? onCourseTap;
  final bool showWeekend;

  static const double _axisWidth = 36;
  static const double _headerHeight = 40;

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
    final days = showWeekend ? const [1, 2, 3, 4, 5, 6, 7] : const [1, 2, 3, 4, 5];
    var maxPeriod = 10;
    for (final c in schedule.courses) {
      maxPeriod = math.max(maxPeriod, c.endPeriod);
    }
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
            ),
            for (final day in days)
              _DayColumn(
                day: day,
                courses: schedule.coursesOn(day, week),
                date: _dateOf(day),
                isToday: _isToday(_dateOf(day)),
                conflicts: conflictIds,
                width: dayWidth,
                headerHeight: _headerHeight,
                rowHeight: rowHeight,
                height: contentHeight,
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

class _PeriodAxis extends StatelessWidget {
  const _PeriodAxis({
    required this.maxPeriod,
    required this.headerHeight,
    required this.rowHeight,
  });

  final int maxPeriod;
  final double headerHeight;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
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
                  Text('第$p节', style: labelStyle?.copyWith(fontSize: 8)),
                  const SizedBox(height: 1),
                  Text(
                    periodTimeText(p),
                    style: labelStyle?.copyWith(fontSize: 7),
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
    required this.conflicts,
    required this.width,
    required this.headerHeight,
    required this.rowHeight,
    required this.height,
    required this.onCourseTap,
  });

  final int day;
  final List<Course> courses;
  final DateTime? date;
  final bool isToday;
  final Set<String> conflicts;
  final double width;
  final double headerHeight;
  final double rowHeight;
  final double height;
  final ValueChanged<Course>? onCourseTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText =
        date == null ? '' : '${date!.month}/${date!.day}';
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.dividerColor, width: 0.5),
          right: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // 表头：星期 + 日期（今天加深）
          Container(
            height: headerHeight,
            alignment: Alignment.center,
            decoration: isToday
                ? BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  courseDayName(day),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                    color: isToday
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
                ),
                if (dateText.isNotEmpty)
                  Text(
                    dateText,
                    style: TextStyle(
                      fontSize: 8,
                      color: isToday
                          ? theme.colorScheme.onPrimary.withValues(alpha: 0.9)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final course in courses)
                  if (course.startPeriod > 0)
                    Positioned(
                      top: (course.startPeriod - 1) * rowHeight + 1,
                      left: 1,
                      right: 1,
                      height: ((course.endPeriod - course.startPeriod + 1) *
                                  rowHeight)
                              .clamp(rowHeight, double.infinity) -
                          2,
                      child: CourseTile(
                        course: course,
                        hasConflict: conflicts.contains(course.id),
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
class CourseTile extends StatelessWidget {
  const CourseTile({
    super.key,
    required this.course,
    this.hasConflict = false,
    this.onTap,
  });

  final Course course;
  final bool hasConflict;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final base = courseColor(course.colorIndex);
    final fg =
        base.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: base.withValues(alpha: isDark ? 0.75 : 1),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: hasConflict
                ? Border.all(color: Colors.redAccent, width: 2)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                course.name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              if (course.location.isNotEmpty)
                Text(
                  course.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 8, height: 1.2),
                ),
              if (course.teacher.isNotEmpty)
                Text(
                  course.teacher,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.85),
                    fontSize: 8,
                    height: 1.2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
