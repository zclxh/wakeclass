import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

import 'package:wakeclass_app/app.dart';
import 'package:wakeclass_app/services/widget/widget_settings.dart';

/// 2026-10-22 是周四。
Schedule _thursdaySchedule() => Schedule(
      id: 's1',
      title: '26年秋',
      termStart: DateTime(2026, 9, 1),
      totalWeeks: 20,
      courses: [
        Course.create(
          name: '大学英语Ⅰ(3)',
          location: '丁2501',
          weeks: const [],
          dayOfWeek: 4,
          startPeriod: 1,
          endPeriod: 2,
        ),
        Course.create(
          name: '模拟电子技术',
          location: 'C3405',
          weeks: const [],
          dayOfWeek: 4,
          startPeriod: 3,
          endPeriod: 4,
        ),
      ],
    );

void main() {
  group('自定义文字', () {
    test('最多 6 个字，超出按码点截断', () {
      expect(normalizeWidgetTitle('26年秋'), '26年秋');
      expect(normalizeWidgetTitle('2026-2027学年第一学期'), '2026-2');
      expect(normalizeWidgetTitle('  醒课  '), '醒课');
      expect(normalizeWidgetTitle(''), '');
    });

    test('emoji 不会被截成半个字符', () {
      expect(normalizeWidgetTitle('📚📚📚📚📚📚📚'), '📚📚📚📚📚📚');
    });
  });

  group('WidgetSettings', () {
    test('无保存记录时用课表标题兜底，并截断到 6 字', () async {
      SharedPreferences.setMockInitialValues({});
      final settings =
          await WidgetSettings.load(fallbackTitle: '2026-2027学年第一学期');
      expect(settings.title, '2026-2');
      expect(settings.colorIndex, 0);
      expect(settings.size.id, 'small');
    });

    test('保存后可原样读回（字符串键，原生端按字符串解析）', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = WidgetSettings(title: '26年秋', colorIndex: 5, sizeId: 'large');
      await settings.save();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(WidgetSettings.titleKey), '26年秋');
      expect(prefs.getString(WidgetSettings.colorKey), '5');
      expect(prefs.getString(WidgetSettings.sizeKey), 'large');

      final reloaded = await WidgetSettings.load();
      expect(reloaded.title, '26年秋');
      expect(reloaded.colorIndex, 5);
      expect(reloaded.size.id, 'large');
      expect(reloaded.color.name, '淡紫');
    });
  });

  group('小组件课程列表', () {
    test('已下课的课自动移除，只留没上的', () {
      final schedule = _thursdaySchedule();
      // 10:30：第 1-2 节（08:00-09:40）已结束，第 3-4 节进行中
      final lines = widgetTodayCourses(schedule, DateTime(2026, 10, 22, 10, 30));
      expect(lines.length, 1);
      expect(lines.first.name, '模拟电子技术');
      expect(lines.first.startText, '10:10');
      expect(lines.first.endText, '11:50');
      expect(lines.first.detail, '第3-4节 · C3405');
      expect(lines.first.status, '还有 1 小时 20 分下课');
    });

    test('上课前显示距上课时间', () {
      final schedule = _thursdaySchedule();
      // 09:50：第一节课已下课，只剩第 3-4 节
      final lines = widgetTodayCourses(schedule, DateTime(2026, 10, 22, 9, 50));
      expect(lines.length, 1);
      expect(lines.single.name, '模拟电子技术');
      expect(lines.single.status, '还有 20 分钟上课');
    });

    test('早于第一节课时两门课都在，倒计时按各自节次', () {
      final schedule = _thursdaySchedule();
      final lines = widgetTodayCourses(schedule, DateTime(2026, 10, 22, 7, 30));
      expect(lines.length, 2);
      expect(lines.first.name, '大学英语Ⅰ(3)');
      expect(lines.first.status, '还有 30 分钟上课');
      expect(lines.last.status, '还有 2 小时 40 分上课');
    });

    test('全部上完后返回空列表（显示「今天没有课啦」）', () {
      final schedule = _thursdaySchedule();
      final lines = widgetTodayCourses(schedule, DateTime(2026, 10, 22, 12, 30));
      expect(lines, isEmpty);
    });

    test('按尺寸限制数量（小 2 / 中 3 / 大 4）', () {
      final schedule = _thursdaySchedule();
      final lines = widgetTodayCourses(
        schedule,
        DateTime(2026, 10, 22, 7, 30),
        max: 1,
      );
      expect(lines.length, 1);

      expect(widgetSizePresets.map((s) => s.id), ['small', 'medium', 'large']);
      expect(widgetSizePresets.map((s) => s.maxCourses), [2, 3, 4]);
    });

    test('自定义作息后时间与倒计时都按新作息计算', () {
      final schedule = _thursdaySchedule();
      // 第 1 节改成 09:10 开始，每节 50 分钟 → 09:10-10:00、10:05-10:55 ...
      final periods = PeriodSettings.uniform(
        firstStart: '09:10',
        durationMinutes: 50,
        breakMinutes: 5,
        count: 12,
      );
      final lines = widgetTodayCourses(
        schedule,
        DateTime(2026, 10, 22, 9, 0),
        periods: periods,
      );
      expect(lines.first.startText, '09:10');
      expect(lines.first.endText, '10:55');
      expect(lines.first.status, '还有 10 分钟上课');
      expect(lines.first.detail, '第1-2节 · 丁2501');
    });
  });

  testWidgets('小组件设置面板：改文字与配色会立即保存', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const WakeClassApp());
    await tester.pumpAndSettle();

    // 入口在顶栏左上角
    await tester.tap(find.byKey(const ValueKey('widget-entry')));
    await tester.pumpAndSettle();
    expect(find.text('桌面小组件'), findsOneWidget);

    // 自定义文字最多 6 个字，预览同步更新
    await tester.enterText(
      find.byKey(const ValueKey('widget-title-field')),
      '26年秋季学期',
    );
    await tester.pump();
    final preview = tester.widget<Text>(
      find.byKey(const ValueKey('widget-preview-title')),
    );
    expect(preview.data, '26年秋季学');

    await tester.ensureVisible(find.byKey(const ValueKey('widget-color-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('widget-color-2')));
    await tester.pumpAndSettle();
    // 等防抖落盘
    await tester.pump(const Duration(milliseconds: 600));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(WidgetSettings.colorKey), '2');
    expect(prefs.getString(WidgetSettings.titleKey), '26年秋季学');
  });

  testWidgets('一键添加返回失败：直接给出手动添加步骤', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _openSheetAndTapPin(tester, pinAccepted: false);

    expect(find.textContaining('手动添加（4×2'), findsOneWidget);
    expect(find.textContaining('长按 1 秒'), findsOneWidget);
    expect(find.text('回到桌面'), findsOneWidget);
  });

  testWidgets('一键添加返回成功（MIUI 不弹窗）也给出手动步骤', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _openSheetAndTapPin(tester, pinAccepted: true);

    expect(find.textContaining('不会弹出确认框'), findsOneWidget);
    expect(find.textContaining('手动添加（4×2'), findsOneWidget);
  });
}

/// 打开小组件面板并点「添加到桌面」，[pinAccepted] 模拟原生返回值。
Future<void> _openSheetAndTapPin(
  WidgetTester tester, {
  required bool pinAccepted,
}) async {
  const channel = MethodChannel('wakeclass/widget');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'pinWidget') return pinAccepted;
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

  await tester.pumpWidget(const WakeClassApp());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('widget-entry')));
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.byKey(const ValueKey('widget-pin-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('widget-pin-button')));
  await tester.pumpAndSettle();
}
