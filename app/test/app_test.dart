import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import 'package:wakeclass_app/app.dart';
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
    expect(find.text('截图导入'), findsOneWidget);
    // 导入入口在顶部栏（与齿轮同尺寸），不再使用悬浮按钮
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsWidgets);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('演示导入：识别出 14 门课并可确认', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WakeClassApp());
    await tester.pumpAndSettle();

    // 进入导入页
    await tester.tap(find.text('截图导入'));
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

    await tester.tap(find.text('截图导入'));
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

    // 七天一屏：7 个表头同时存在（无横向滚动），并在星期下显示日期。
    for (final d in ['周一', '周二', '周三', '周四', '周五', '周六', '周日']) {
      expect(find.text(d), findsOneWidget);
    }
    expect(find.text('9/7'), findsOneWidget);
    expect(find.text('9/13'), findsOneWidget);

    await tester.pumpWidget(wrap(2));
    await tester.pumpAndSettle();
    expect(find.text('本周课'), findsNothing);
    expect(find.text('下周课'), findsOneWidget);
    expect(find.text('9/14'), findsOneWidget);
  });

  testWidgets('设置页切换主题色并全局生效', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WakeClassApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('主题色'), findsOneWidget);

    final before = Theme.of(tester.element(find.text('主题色'))).colorScheme.primary;
    await tester.ensureVisible(find.byKey(const ValueKey('theme-1')));
    await tester.tap(find.byKey(const ValueKey('theme-1')));
    await tester.pumpAndSettle();

    final after = Theme.of(tester.element(find.text('主题色'))).colorScheme.primary;
    expect(after, isNot(before));
    expect(find.textContaining('海蓝'), findsOneWidget);
  });
}
