import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wakeclass_app/services/jwxt/schedule_table_parser.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

void main() {
  final fixture = File('test/fixtures/zf.html').readAsStringSync();

  group('ScheduleTableParser', () {
    final parsed = const ScheduleTableParser().parseSchedule(fixture, source: 'jwxt');
    final courses = parsed.courses;

    Course by(String name, int day, int startPeriod) => courses.firstWhere(
        (c) =>
            c.name == name &&
            c.dayOfWeek == day &&
            c.startPeriod == startPeriod);

    test('完整强智课表页解析出 14 门课', () {
      expect(courses, hasLength(14));
      expect(parsed.warnings, isEmpty);
    });

    test('rowspan 合并单元格映射到正确节次区间', () {
      final math = by('高等数学A', 1, 1);
      expect(math.endPeriod, 2);
      expect(math.teacher, '张明远');
      expect(math.location, '教一101');
      expect(math.weeks, List.generate(16, (i) => i + 1));

      final english = by('大学英语III', 1, 3);
      expect(english.endPeriod, 4);
      expect(english.location, '外语楼302');
    });

    test('单双周解析', () {
      final innovation = by('创新创业实践', 6, 1);
      expect(innovation.weeks, [3, 5, 7, 9, 11, 13, 15]);
      expect(innovation.location, '创客空间');
    });

    test('一格两门课（hr 分隔）拆分', () {
      final linear = by('线性代数', 2, 7);
      expect(linear.teacher, '王建国');
      expect(linear.weeks, List.generate(8, (i) => i + 1));
      final prob = by('概率论与数理统计', 2, 7);
      expect(prob.teacher, '李芳');
      expect(prob.weeks, List.generate(7, (i) => i + 10));
    });

    test('晚课与实验课', () {
      expect(by('数字电路实验', 4, 9).endPeriod, 10);
      expect(by('机器学习导论', 5, 5).location, '计算机楼402');
    });

    test('全部课程 source 为 jwxt', () {
      for (final c in courses) {
        expect(c.source, 'jwxt');
      }
    });

    test('空页面 → 告警且无课程', () {
      final empty = const ScheduleTableParser().parseSchedule('<html><body></body></html>');
      expect(empty.courses, isEmpty);
      expect(empty.warnings, isNotEmpty);
    });
  });
}
