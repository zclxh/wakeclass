import 'package:flutter/material.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import '../model/schedule_model.dart';
import '../model/theme_model.dart';
import '../services/notifications/reminders.dart';
import '../widgets/schedule_grid.dart';
import 'course_edit_page.dart';
import 'import_decision.dart';
import 'import_page.dart';
import 'settings_page.dart';
import 'widget_settings_sheet.dart';

/// 课表主页。
///
/// - 顶部栏：左侧桌面小组件入口；中间「第 N 周 + 日期范围」；右侧导入 + 设置；
/// - 左右滑动课表切换上一周 / 下一周；点击周次文字回到本周。
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key, required this.model, required this.themeModel});

  final ScheduleModel model;
  final ThemeModel themeModel;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late final PageController _pageController;
  late int _week;

  @override
  void initState() {
    super.initState();
    _week = widget.model.displayWeek;
    _pageController = PageController(initialPage: _week - 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _currentWeek => widget.model.schedule.currentWeek();

  Future<void> _openImport() async {
    final decision = await Navigator.of(context).push<ImportDecision>(
      MaterialPageRoute(builder: (_) => const ImportPage()),
    );
    if (decision == null || !mounted) return;
    if (decision.replace) {
      await widget.model.replaceCourses(decision.courses);
    } else {
      await widget.model.mergeCourses(decision.courses);
    }
    await _syncReminders();
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
      await CourseReminderService.sync(widget.model.schedule,
          settings: settings);
    } catch (_) {
      // 通知不可用时忽略
    }
  }

  Future<void> _editCourse(Course course) async {
    final result = await Navigator.of(context).push<CourseEditResult>(
      MaterialPageRoute(builder: (_) => CourseEditPage(course: course)),
    );
    if (result == null) return;
    if (result.delete && result.id != null) {
      await widget.model.removeCourse(result.id!);
    } else if (result.course != null) {
      await widget.model.upsertCourse(result.course!);
    }
    await _syncReminders();
  }

  Future<void> _addCourse() async {
    final result = await Navigator.of(context).push<CourseEditResult>(
      MaterialPageRoute(builder: (_) => const CourseEditPage()),
    );
    if (result?.course != null) {
      await widget.model.upsertCourse(result!.course!);
    }
  }

  /// 打开桌面小组件设置（自定义文字 / 尺寸 / 配色 / 一键添加）。
  Future<void> _openWidgetSettings() {
    return showWidgetSettingsSheet(
      context,
      schedule: widget.model.schedule,
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

    return Scaffold(
      appBar: AppBar(
        // 左上角：桌面小组件（自定义颜色 / 一键添加）
        leading: IconButton(
          key: const ValueKey('widget-entry'),
          icon: const Icon(Icons.widgets_outlined),
          tooltip: '桌面小组件',
          onPressed: _openWidgetSettings,
        ),
        // 周次与齿轮同一水平线
        title: InkWell(
          onTap: _goToCurrentWeek,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '第 $_week 周',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${monday.month}月${monday.day}日 - ${sunday.month}月${sunday.day}日'
                '${isCurrentWeek ? '' : ' · 点击回本周'}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actions: [
          // 导入：与齿轮同尺寸的图标按钮（无文字）
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: '导入课表',
            onPressed: _openImport,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) =>
                      SettingsPage(model: widget.model, themeModel: widget.themeModel)),
            ),
          ),
        ],
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
                  onCourseTap: _editCourse,
                );
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport, required this.onAdd});

  final VoidCallback onImport;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.grid_view_rounded,
              size: 72,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有课表',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '对教务系统的课表页面截图，即可自动识别导入。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('截图导入'),
            ),
            const SizedBox(height: 8),
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
