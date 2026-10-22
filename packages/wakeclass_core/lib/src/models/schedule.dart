import 'course.dart';
import 'ocr_block.dart';
import 'raw_cell.dart';
import '../utils/dates.dart';
import '../utils/ids.dart';

/// 一个学期的完整课表。
class Schedule {
  const Schedule({
    required this.id,
    required this.title,
    required this.termStart,
    required this.totalWeeks,
    required this.courses,
    this.updatedAt,
  });

  /// 课表 id。
  final String id;

  /// 标题，如「2026-2027学年第一学期」。
  final String title;

  /// 第 1 周周一的日期（只使用日期部分）。
  final DateTime termStart;

  /// 学期总周数。
  final int totalWeeks;

  /// 全部课程单元。
  final List<Course> courses;

  /// 最后修改时间（JSON 字段，可空表示未知）。
  final DateTime? updatedAt;

  /// 新建空课表：开学日默认取最近一个周一，总周数 20。
  factory Schedule.empty({DateTime? now}) {
    final base = now ?? DateTime.now();
    final start = mondayOf(base);
    return Schedule(
      id: generateScheduleId(),
      title: '新学期课表',
      termStart: start,
      totalWeeks: 20,
      courses: const [],
      updatedAt: base,
    );
  }

  /// 当前教学周（1 起始，钳制到 [1, totalWeeks]）。
  int currentWeek([DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final start = DateTime(termStart.year, termStart.month, termStart.day);
    final week = today.difference(start).inDays ~/ 7 + 1;
    return week.clamp(1, totalWeeks);
  }

  /// 指定星期几（1..7）的全部课程单元，按起始节次排序。
  List<Course> coursesForDay(int day) {
    final list = courses.where((c) => c.dayOfWeek == day).toList();
    list.sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
    return list;
  }

  /// 在第 [week] 周、星期 [day] 真正上课的课程（过滤单双周）。
  List<Course> coursesOn(int day, int week) {
    final list =
        coursesForDay(day).where((c) => c.includesWeek(week)).toList();
    list.sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
    return list;
  }

  /// 该课程单元是否与课表中其他单元冲突（忽略自身）。
  List<Course> conflictsOf(Course course) => courses
      .where((c) => c.id != course.id && c.conflictsWith(course))
      .toList();

  Schedule copyWith({
    String? title,
    DateTime? termStart,
    int? totalWeeks,
    List<Course>? courses,
    DateTime? updatedAt,
  }) {
    return Schedule(
      id: id,
      title: title ?? this.title,
      termStart: termStart ?? this.termStart,
      totalWeeks: totalWeeks ?? this.totalWeeks,
      courses: courses ?? this.courses,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'term_start': formatDate(termStart),
        'total_weeks': totalWeeks,
        'updated_at': formatDate(updatedAt ?? termStart),
        'courses': courses.map((c) => c.toJson()).toList(),
      };

  factory Schedule.fromJson(Map<String, dynamic> json) {
    final rawCourses = json['courses'];
    return Schedule(
      id: json['id'] as String? ?? generateScheduleId(),
      title: json['title'] as String? ?? '课表',
      termStart: parseDate(json['term_start'] as String? ?? ''),
      totalWeeks: (json['total_weeks'] as num?)?.toInt() ?? 20,
      updatedAt: parseDateOrNull(json['updated_at'] as String?),
      courses: [
        if (rawCourses is List)
          for (final c in rawCourses)
            if (c is Map<String, dynamic>) Course.fromJson(c),
      ],
    );
  }

  @override
  String toString() => 'Schedule($title, ${courses.length} courses)';
}

/// 占位引用，防止 IDE 对未使用 import 的告警（models 间互相可见）。
// ignore: unused_element
const _modelDocRefs = [OcrTextBlock, RawCell];
