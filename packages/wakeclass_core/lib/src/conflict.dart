import 'models/course.dart';

/// 一对时间冲突的课程。
class CourseConflict {
  const CourseConflict(this.a, this.b);

  final Course a;
  final Course b;

  @override
  String toString() =>
      'CourseConflict(${a.name} ↔ ${b.name} ${a.dayText} ${a.periodText})';
}

/// 找出课程列表中全部冲突对（同一天、节次重叠、周次相交）。
List<CourseConflict> findConflicts(Iterable<Course> courses) {
  final list = courses.toList();
  final result = <CourseConflict>[];
  for (var i = 0; i < list.length; i++) {
    for (var j = i + 1; j < list.length; j++) {
      if (list[i].conflictsWith(list[j])) {
        result.add(CourseConflict(list[i], list[j]));
      }
    }
  }
  return result;
}
