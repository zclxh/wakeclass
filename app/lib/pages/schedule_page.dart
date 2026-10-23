import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import '../model/period_model.dart';
import '../model/schedule_model.dart';
import '../model/theme_model.dart';
import '../services/notifications/reminders.dart';
import '../theme.dart';
import '../widgets/schedule_grid.dart';
import 'course_actions_sheet.dart';
import 'course_edit_page.dart';
import 'import_decision.dart';
import 'import_page.dart';
import 'settings_page.dart';
import 'widget_settings_sheet.dart';

/// 课表主页。
///
/// - 顶部栏：左侧桌面小组件入口；中间「第 N 周 + 日期范围」；右侧导入 + 设置；
/// - 左右滑动课表切换上一周 / 下一周；点击周次文字回到本周；
/// - 打开时直接停在当前周；点击课程可改颜色 / 编辑 / 删除。
class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    required this.model,
    required this.themeModel,
    required this.periodModel,
  });

  final ScheduleModel model;
  final ThemeModel themeModel;
  final PeriodModel periodModel;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late final PageController _pageController;
  late int _week;

  @override
  void initState() {
    super.initState();
    _week = _weekInRange(widget.model.displayWeek);
    _pageController = PageController(initialPage: _week - 1);
    widget.model.addListener(_onModelChanged);
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModelChanged);
    _pageController.dispose();
    super.dispose();
  }

  int _weekInRange(int week) {
    final total = widget.model.schedule.totalWeeks;
    if (total < 1) return 1;
    return week.clamp(1, total);
  }

  /// 课表变化（导入 / 改开学日）后，保证展示周仍在学期范围内。
  void _onModelChanged() {
    final target = _weekInRange(_week);
    if (target == _week) return;
    _week = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(target - 1);
    });
    setState(() {});
  }

  int get _currentWeek => widget.model.schedule.currentWeek();

  Future<void> _openImport() async {
    final decision = await Navigator.of(context).push<ImportDecision>(
      MaterialPageRoute(builder: (_) => const ImportPage()),
    );
    if (decision == null || !mounted) return;
    await decision.applyTo(widget.model);
    unawaited(_syncReminders());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '已${decision.replace ? '覆盖' : '追加'}导入 ${decision.courses.length} 门课'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 课表变化后重新注册课前提醒。
  Future<void> _syncReminders() async {
    try {
      final settings = await CourseReminderService.loadSettings();
      await CourseReminderService.sync(
        widget.model.schedule,
        settings: settings,
        periods: widget.periodModel.settings,
      );
    } catch (_) {
      // 通知不可用时忽略
    }
  }

  /// 点课程：改颜色 / 编辑 / 删除。
  Future<void> _openCourse(Course course) async {
    final action = await showCourseActionsSheet(
      context,
      course: course,
      periods: widget.periodModel.settings,
      onColorSelected: (index) =>
          widget.model.upsertCourse(course.copyWith(colorIndex: index)),
    );
    if (!mounted || action == null) return;
    if (action == CourseAction.edit) {
      await _editCourse(course);
    } else if (action == CourseAction.delete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除课程'),
          content: Text('确定删除「${course.name}」吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await widget.model.removeCourse(course.id);
        unawaited(_syncReminders());
      }
    }
  }

  Future<void> _editCourse(Course course) async {
    final result = await Navigator.of(context).push<CourseEditResult>(
      MaterialPageRoute(
        builder: (_) => CourseEditPage(
          course: course,
          totalWeeks: widget.model.schedule.totalWeeks,
          periods: widget.periodModel.settings,
        ),
      ),
    );
    if (result == null) return;
    if (result.delete && result.id != null) {
      await widget.model.removeCourse(result.id!);
    } else if (result.course != null) {
      await widget.model.upsertCourse(result.course!);
    }
    unawaited(_syncReminders());
  }

  Future<void> _addCourse() async {
    final result = await Navigator.of(context).push<CourseEditResult>(
      MaterialPageRoute(
        builder: (_) => CourseEditPage(
          totalWeeks: widget.model.schedule.totalWeeks,
          periods: widget.periodModel.settings,
        ),
      ),
    );
    if (result?.course != null) {
      await widget.model.upsertCourse(result!.course!);
      unawaited(_syncReminders());
    }
  }

  /// 打开桌面小组件设置（自定义文字 / 尺寸 / 配色 / 一键添加）。
  Future<void> _openWidgetSettings() {
    return showWidgetSettingsSheet(
      context,
      schedule: widget.model.schedule,
      periods: widget.periodModel.settings,
    );
  }

  /// 回到本周（点击周次文字触发）。
  Future<void> _goToCurrentWeek() async {
    final target = _currentWeek;
    if (target == _week) return;
    await _pageController.animateToPage(
      target - 1,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final schedule = widget.model.schedule;
    final monday = schedule.termStart.add(Duration(days: (_week - 1) * 7));
    final sunday = monday.add(const Duration(days: 6));
    final isCurrentWeek = _week == _currentWeek;
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 62,
        titleSpacing: 2,
        leading: IconButton(
          key: const ValueKey('widget-entry'),
          icon: const Icon(Icons.widgets_outlined, size: 22),
          tooltip: '桌面小组件',
          onPressed: _openWidgetSettings,
        ),
        title: InkWell(
          onTap: _goToCurrentWeek,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '第 $_week 周',
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.2,
                        letterSpacing: 0.2,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (!isCurrentWeek) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '回本周',
                          style: TextStyle(
                            fontSize: 9.5,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            color: primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${monday.month}月${monday.day}日 – '
                  '${sunday.month}月${sunday.day}日',
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.2,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 22),
            tooltip: '导入课表',
            onPressed: _openImport,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 22),
            tooltip: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsPage(
                  model: widget.model,
                  themeModel: widget.themeModel,
                  periodModel: widget.periodModel,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.8),
          child: Container(
            height: 0.8,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          ),
        ),
      ),
      body: schedule.courses.isEmpty
          ? _EmptyState(
              onImport: _openImport,
              onAdd: _addCourse,
            )
          : PageView.builder(
              controller: _pageController,
              itemCount: schedule.totalWeeks,
              onPageChanged: (index) => setState(() => _week = index + 1),
              itemBuilder: (context, index) {
                final weekStart =
                    schedule.termStart.add(Duration(days: index * 7));
                return ScheduleGrid(
                  schedule: schedule,
                  week: index + 1,
                  weekStart: weekStart,
                  periods: widget.periodModel.settings,
                  onCourseTap: _openCourse,
                );
              },
            ),
    );
  }
}

/// 空课表首屏：一个「迷你课表」插画 + 两种入口。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport, required this.onAdd});

  final VoidCallback onImport;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MiniScheduleArt(primary: primary),
            const SizedBox(height: 26),
            Text(
              '还没有课表',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '截图识别、教务直连、粘贴导入，任选一种\n导入后课表、提醒、小组件全部离线可用',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.7,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.file_download_outlined, size: 19),
              label: const Text('导入课表'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: onAdd,
              child: const Text('手动添加一门课'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空状态插画：一张迷你课表卡片（三行小色块）。
class _MiniScheduleArt extends StatelessWidget {
  const _MiniScheduleArt({required this.primary});

  final Color primary;

  static const _pattern = [
    [true, false, true],
    [false, true, false],
    [true, true, false],
  ];
  static const _paletteIndex = [5, 9, 13];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHigh
        : Colors.white;
    return Container(
      width: 156,
      height: 156,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: primary.withValues(alpha: 0.06),
      ),
      child: Center(
        child: Container(
          width: 104,
          height: 104,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              // 表头：星期小点
              for (var r = 0; r < 3; r++)
                Expanded(
                  child: Row(
                    children: [
                      for (var c = 0; c < 3; c++)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.all(2.2),
                            decoration: BoxDecoration(
                              color: _pattern[r][c]
                                  ? courseColor(_paletteIndex[r])
                                      .withValues(alpha: 0.9)
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
