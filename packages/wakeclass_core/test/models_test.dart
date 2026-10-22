import 'package:test/test.dart';
import 'package:wakeclass_core/wakeclass_core.dart';

Course c({
  String name = '课',
  List<int> weeks = const [],
  int day = 1,
  int start = 1,
  int end = 2,
}) =>
    Course.create(
        name: name,
        weeks: weeks,
        dayOfWeek: day,
        startPeriod: start,
        endPeriod: end);

void main() {
  group('findConflicts', () {
    test('同天同节次、周次相交 → 冲突', () {
      final a = c(name: '高数', weeks: [1, 2, 3]);
      final b = c(name: '线代', weeks: [3, 4, 5]);
      final conflicts = findConflicts([a, b]);
      expect(conflicts, hasLength(1));
      expect(conflicts.single.a.name, '高数');
    });

    test('同天同节次、周次不相交 → 不冲突（1-8周 与 10-16周）', () {
      final a = c(name: '线代', weeks: List.generate(8, (i) => i + 1));
      final b = c(name: '概率论', weeks: List.generate(7, (i) => i + 10));
      expect(findConflicts([a, b]), isEmpty);
    });

    test('不同天 → 不冲突', () {
      final a = c(name: '高数', day: 1, weeks: [1, 2]);
      final b = c(name: '线代', day: 2, weeks: [1, 2]);
      expect(findConflicts([a, b]), isEmpty);
    });

    test('节次相邻但不重叠 → 不冲突', () {
      final a = c(name: '高数', start: 1, end: 2);
      final b = c(name: '线代', start: 3, end: 4);
      expect(findConflicts([a, b]), isEmpty);
    });

    test('空周次视为每周 → 与任何周次冲突', () {
      final a = c(name: '高数', weeks: const []);
      final b = c(name: '线代', weeks: [10, 11, 12]);
      expect(findConflicts([a, b]), hasLength(1));
    });
  });

  group('Course', () {
    test('JSON 往返保持字段', () {
      final course = Course.create(
        name: '高等数学A',
        teacher: '张明远',
        location: '教一101',
        weeks: [1, 3, 5],
        dayOfWeek: 1,
        startPeriod: 1,
        endPeriod: 2,
        source: 'ocr',
      );
      final restored = Course.fromJson(course.toJson());
      expect(restored, course);
    });

    test('Schedule JSON 往返', () {
      final schedule = Schedule(
        id: 's-1',
        title: '2026-2027学年第一学期',
        termStart: DateTime(2026, 9, 7),
        totalWeeks: 20,
        courses: [
          c(name: '高数', weeks: [1, 2, 3], day: 1),
          c(name: '英语', weeks: [1, 2, 3], day: 2),
        ],
        updatedAt: DateTime(2026, 9, 7, 12),
      );
      final restored = Schedule.fromJson(schedule.toJson());
      expect(restored.id, 's-1');
      expect(restored.title, '2026-2027学年第一学期');
      expect(restored.termStart, DateTime(2026, 9, 7));
      expect(restored.totalWeeks, 20);
      expect(restored.courses, hasLength(2));
      expect(restored.courses.first.name, '高数');
    });

    test('currentWeek 计算（开学日当周为第 1 周）', () {
      final schedule = Schedule(
        id: 's-1',
        title: 't',
        termStart: DateTime(2026, 9, 7), // 周一
        totalWeeks: 20,
        courses: const [],
      );
      expect(schedule.currentWeek(DateTime(2026, 9, 7)), 1);
      expect(schedule.currentWeek(DateTime(2026, 9, 13)), 1); // 周日仍第 1 周
      expect(schedule.currentWeek(DateTime(2026, 9, 14)), 2); // 下周一
      expect(schedule.currentWeek(DateTime(2026, 10, 12)), 6);
      expect(schedule.currentWeek(DateTime(2027, 9, 1)), 20); // 超出钳制
    });

    test('coursesOn 过滤单双周', () {
      final schedule = Schedule(
        id: 's-1',
        title: 't',
        termStart: DateTime(2026, 9, 7),
        totalWeeks: 20,
        courses: [
          c(name: '单周课', weeks: [1, 3, 5], day: 1),
          c(name: '每周课', weeks: const [], day: 1),
        ],
      );
      expect(schedule.coursesOn(1, 1).map((Course x) => x.name).toList(),
          ['单周课', '每周课']);
      expect(schedule.coursesOn(1, 2).map((Course x) => x.name).toList(),
          ['每周课']);
    });
  });
}
