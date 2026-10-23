import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import 'dart:convert';

import 'package:wakeclass_app/app.dart';
import 'package:wakeclass_app/model/theme_model.dart';
import 'package:wakeclass_app/theme.dart';
import 'package:wakeclass_app/widgets/schedule_grid.dart';

void main() {
  test('core 依赖可用（跨包引用正常）', () {
    final expr = parseWeeks('1-16周(单)');
    expect(expr.weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
  });

  testWidgets('应用启动：空课表展示导入入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WakeClassApp());
    await tester.pumpAndSettle();

    expect(find.text('还没有课表'), findsOneWidget);
    expect(find.text('导入课表'), findsOneWidget);
    // 导入入口在顶部栏（与齿轮同尺寸），不再使用悬浮按钮
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsWidgets);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('演示导入：识别出 14 门课并可确认', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WakeClassApp());
    await tester.pumpAndSettle();

    // 进入导入页
    await tester.tap(find.text('导入课表'));
    await tester.pumpAndSettle();

    // 演示导入
    await tester.tap(find.text('体验导入流程'));
    await tester.pumpAndSettle();

    // 校对页：识别出 14 门课（摘要 + 副标题各出现一次）
    expect(find.textContaining('识别出 14 门课'), findsWidgets);
    expect(find.text('高等数学A'), findsWidgets);

    // 追加导入
    await tester.tap(find.text('追加导入'));
    await tester.pumpAndSettle();

    // 回到主页，课程网格出现
    expect(find.text('高等数学A'), findsWidgets);
  });

  testWidgets('导入页包含教务直连入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WakeClassApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入课表'));
    await tester.pumpAndSettle();

    expect(find.text('教务直连'), findsWidgets);
    expect(find.text('直连导入'), findsOneWidget);

    // 进入直连页
    await tester.tap(find.text('直连导入'));
    await tester.pumpAndSettle();
    expect(find.text('教务系统登录地址 *'), findsOneWidget);
    expect(find.text('系统类型'), findsOneWidget);
    expect(find.text('登录并导入'), findsOneWidget);
  });

  testWidgets('课表网格只显示当前周的课程', (tester) async {
    final schedule = Schedule(
      id: 's1',
      title: 't',
      termStart: DateTime(2026, 9, 7),
      totalWeeks: 20,
      courses: [
        Course.create(
            name: '本周课', weeks: const [1], dayOfWeek: 1, startPeriod: 1, endPeriod: 2),
        Course.create(
            name: '下周课', weeks: const [2], dayOfWeek: 1, startPeriod: 3, endPeriod: 4),
        Course.create(
            name: '每周课', weeks: const [], dayOfWeek: 1, startPeriod: 5, endPeriod: 6),
      ],
    );
    Widget wrap(int week) => MaterialApp(
          home: Scaffold(
            body: ScheduleGrid(
              schedule: schedule,
              week: week,
              weekStart: DateTime(2026, 9, 7).add(Duration(days: (week - 1) * 7)),
            ),
          ),
        );

    await tester.pumpWidget(wrap(1));
    await tester.pumpAndSettle();
    expect(find.text('本周课'), findsOneWidget);
    expect(find.text('下周课'), findsNothing);
    expect(find.text('每周课'), findsOneWidget);

    // 学期里没有周末课 → 只显示周一到周五（列更宽，课程名更好读）
    for (final d in ['周一', '周二', '周三', '周四', '周五']) {
      expect(find.text(d), findsOneWidget);
    }
    expect(find.text('周六'), findsNothing);
    expect(find.text('9/7'), findsOneWidget);
    expect(find.text('9/11'), findsOneWidget);

    await tester.pumpWidget(wrap(2));
    await tester.pumpAndSettle();
    expect(find.text('本周课'), findsNothing);
    expect(find.text('下周课'), findsOneWidget);
    expect(find.text('9/14'), findsOneWidget);

    // 有周末课时自动恢复 7 列
    final withWeekend = Schedule(
      id: 's2',
      title: 't',
      termStart: DateTime(2026, 9, 7),
      totalWeeks: 20,
      courses: [
        Course.create(
            name: '周末课',
            weeks: const [],
            dayOfWeek: 6,
            startPeriod: 1,
            endPeriod: 2),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleGrid(
            schedule: withWeekend,
            week: 1,
            weekStart: DateTime(2026, 9, 7),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('周六'), findsOneWidget);
    expect(find.text('9/12'), findsOneWidget);
  });

  testWidgets('设置页切换主题色并全局生效', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WakeClassApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('主题色'), findsOneWidget);

    final before = Theme.of(tester.element(find.text('设置'))).colorScheme.primary;
    await tester.ensureVisible(find.byKey(const ValueKey('theme-1')));
    await tester.tap(find.byKey(const ValueKey('theme-1')));
    await tester.pumpAndSettle();

    final after = Theme.of(tester.element(find.text('设置'))).colorScheme.primary;
    expect(after, isNot(before));
    // 滚回顶部看当前主题名
    await tester.dragUntilVisible(
      find.text('主题色'),
      find.byType(ListView),
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('海蓝'), findsOneWidget);
  });

  testWidgets('设置页可换背景色并全局生效', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WakeClassApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('背景颜色'), findsOneWidget);

    final before = Theme.of(tester.element(find.text('设置'))).scaffoldBackgroundColor;
    final swatch = find.byKey(const ValueKey('bg-3'));
    await tester.ensureVisible(swatch);
    await tester.pumpAndSettle();
    await tester.tap(swatch);
    await tester.pumpAndSettle();

    final after = Theme.of(tester.element(find.text('设置'))).scaffoldBackgroundColor;
    expect(after, isNot(before));
    expect(after, backgroundPresets[3].color);
  });

  testWidgets('打开 App 直接停在当前周（不是第 1 周）', (tester) async {
    // 开学日 = 7 周前的周一 → 现在是第 8 周
    final monday = mondayOf(DateTime.now()).subtract(const Duration(days: 49));
    final schedule = Schedule(
      id: 's1',
      title: '26年秋',
      termStart: monday,
      totalWeeks: 20,
      courses: [
        Course.create(
          name: '第八周课',
          weeks: const [8],
          dayOfWeek: 1,
          startPeriod: 1,
          endPeriod: 2,
        ),
        Course.create(
          name: '第一周课',
          weeks: const [1],
          dayOfWeek: 2,
          startPeriod: 3,
          endPeriod: 4,
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'wakeclass_schedule_v1': jsonEncode(schedule.toJson()),
    });

    await tester.pumpWidget(const WakeClassApp());
    await tester.pumpAndSettle();

    expect(find.text('第 8 周'), findsOneWidget);
    expect(find.text('第八周课'), findsOneWidget);
    expect(find.text('第一周课'), findsNothing);
  });

  testWidgets('点击课程可自定义颜色并保存', (tester) async {
    final schedule = Schedule(
      id: 's1',
      title: 't',
      termStart: mondayOf(DateTime.now()),
      totalWeeks: 20,
      courses: [
        Course.create(
          name: '高等数学A',
          location: '甲101',
          weeks: const [],
          dayOfWeek: DateTime.now().weekday,
          startPeriod: 1,
          endPeriod: 2,
          colorIndex: 0,
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'wakeclass_schedule_v1': jsonEncode(schedule.toJson()),
    });

    await tester.pumpWidget(const WakeClassApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('高等数学A'));
    await tester.pumpAndSettle();
    expect(find.text('课程颜色'), findsOneWidget);
    expect(find.text('编辑课程'), findsOneWidget);

    final swatch = find.byKey(const ValueKey('course-color-5'));
    await tester.ensureVisible(swatch);
    await tester.pumpAndSettle();
    await tester.tap(swatch);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('wakeclass_schedule_v1');
    expect(raw, isNotNull);
    final saved = Schedule.fromJson(jsonDecode(raw!) as Map<String, dynamic>);
    expect(saved.courses.single.colorIndex, 5);
  });

  testWidgets('上课时间入口显示当前作息', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WakeClassApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('period-entry')),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 1 节 08:00 · 每节 45 分钟 · 每天 12 节'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('period-entry')));
    await tester.pumpAndSettle();
    expect(find.text('上课时间'), findsOneWidget);
    expect(find.text('08:00-08:45'), findsOneWidget);
  });

  testWidgets('课表外观可在柔和 / 鲜艳之间切换并持久化', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WakeClassApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('课表外观'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前：柔和'), findsOneWidget);

    await tester.ensureVisible(find.byIcon(Icons.gradient_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.gradient_outlined));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('wakeclass_card_style'), 'vivid');
    // 选中的说明文字也跟着换（证明界面确实重建了）
    expect(find.text('整块课程色，颜色最醒目'), findsOneWidget);
  });

  test('课表外观：默认柔和，切换后写入偏好并在重启后恢复', () async {
    SharedPreferences.setMockInitialValues({});
    final model = ThemeModel();
    await model.init();
    expect(model.cardStyle, CourseCardStyle.soft);

    await model.setCardStyle(CourseCardStyle.vivid);
    expect(model.cardStyle, CourseCardStyle.vivid);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('wakeclass_card_style'), 'vivid');

    final reloaded = ThemeModel();
    await reloaded.init();
    expect(reloaded.cardStyle, CourseCardStyle.vivid);
  });
}
